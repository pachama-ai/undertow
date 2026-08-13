-- Screenshot-Harness für die visuelle Abnahme (Switch/Bridge Visual Polish).
-- Wird NICHT ins Spiel eingebaut: tools/run_screenshots.ps1 kopiert dieses
-- Runner-main.lua in ein separates Screenshot-PDX (bundleID com.selina.ringe.shots)
-- und startet den Simulator. Dieses Skript rendert echte Render.drawRoom-Szenen
-- in 400x240-Offscreen-Images und schreibt sie als PNG in den Datenordner des
-- PDX (Disk\Data\com.selina.ringe.shots\). Danach beendet es sich selbst.

import("CoreLibs/graphics")
import("core/config")
import("core/geometry")
import("core/state")
import("core/undo")
import("core/audio")
import("core/save")
import("core/sysmenu")
import("world/player")
import("world/room")
import("world/bridge")
import("world/gate")
import("world/baby")
import("world/switch")
import("data/levels")
import("ui/render")
import("ui/camera")
import("ui/menu")
import("ui/transition")

local gfx = playdate.graphics

-- Log in den Datenordner schreiben (für Diagnose, da Simulator-print nicht
-- im Terminal landet).
local logF, logErr = playdate.file.open("shot_log.txt", playdate.file.kFileWrite)
if not logF then
    print("LOG_OPEN_ERROR: " .. tostring(logErr))
end
local function log(text)
    if logF then
        logF:write(text .. "\n")
        logF:flush()
    end
end

-- Testraum: zwei Schalter (S1 outer, S2 inner), zwei Blenden, drei Brücken
-- (B0 frei/aktiv, B1 von S1 gesteuert, B2 von S2 gesteuert), Gate frei.
local room = {
    name = "Shots",
    rings = { outer = 7, inner = 6 },
    start = { ring = "outer", angle = 0 },
    switches = {
        { id = "S1", ring = "outer", angle = 90,  symbol = 1, onA = "B1", onB = "D1", state = "A" },
        { id = "S2", ring = "inner", angle = 270, symbol = 2, onA = "B2", onB = "D2", state = "B" },
    },
    shutters = {
        { id = "D1", ring = "outer", angle = 90 },
        { id = "D2", ring = "inner", angle = 270 },
    },
    bridges = {
        { id = "B0", angle = 180, free = true  },
        { id = "B1", angle = 0,   free = false },
        { id = "B2", angle = 90,  free = false },
    },
    gate = { id = "T", angle = 45, free = true },
}

local shots = {}

local function setupRoom()
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(room.rings.outer)
    Render.resetPlayerVisual()
    Render.updateObjectAnimations(0.016)
end

-- Bild via img:sample in ein 24-Bit-BMP (unskomprimiert, bottom-up) schreiben.
-- writePNG gibt es in dieser SDK-Version nicht; das BMP wird am Host (PS1)
-- nach PNG konvertiert. scale: Vergrößerungsfaktor für die Betrachtung.
local function writeBMP(name, img, scale)
    scale = scale or 2
    local w, h = 400, 240
    local ww, hh = w * scale, h * scale
    local rowBytes = math.ceil(ww * 3 / 4) * 4
    local pixelBytes = rowBytes * hh
    local fileSize = 14 + 40 + pixelBytes
    local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
    local fileHeader = "BM" .. u32(fileSize) .. u32(0) .. u32(54)
    local dib = u32(40) .. u32(ww) .. u32(hh) .. u16(1) .. u16(24) .. u32(0) .. u32(pixelBytes) .. u32(2835) .. u32(2835) .. u32(0) .. u32(0)
    local rows = {}
    for y = hh - 1, 0, -1 do
        local sy = math.floor(y / scale)
        local row = {}
        for x = 0, ww - 1 do
            local sx = math.floor(x / scale)
            local c = img:sample(sx, sy)
            local v = (c == gfx.kColorWhite) and 255 or 0
            row[#row + 1] = string.char(v, v, v)
        end
        local rowStr = table.concat(row)
        if #rowStr < rowBytes then
            rowStr = rowStr .. string.rep("\0", rowBytes - #rowStr)
        end
        rows[#rows + 1] = rowStr
    end
    local f, err = playdate.file.open(name .. ".bmp", playdate.file.kFileWrite)
    if not f then
        log("BMP_OPEN_ERROR " .. name .. ": " .. tostring(err))
        return
    end
    f:write(fileHeader)
    f:write(dib)
    for i = 1, #rows do f:write(rows[i]) end
    f:close()
    log("BMP_OK " .. name)
end

local function renderScene(name)
    local img = gfx.image.new(400, 240)
    gfx.pushContext(img)
    local ok, err = pcall(function() Render.drawRoom(false, 1) end)
    gfx.popContext()
    if not ok then
        log("RENDER_ERROR " .. name .. ": " .. tostring(err))
        return nil
    end
    writeBMP(name, img, 2)
    return img
end

-- Objektiver Varianten-Vergleich: zählt weiße Pixel im Fenster um die
-- Markenpositionen beider Seiten (CW-Seite = A, CCW-Seite = B) und loggt die
-- Mengen. Höhere aktive-vs-inaktive Trennung = besser lesbar. Rein quantitativ.
local function measureSwitch(name, img)
    local swX = 200 + Config.outerRadius * math.sin(math.rad(90))
    local swY = 120 - Config.outerRadius * math.cos(math.rad(90))
    local style = Config.switchStyle or "C"
    local dCw, dCcw
    if style == "A" then
        dCw, dCcw = 3.4, 3.4
    elseif style == "B" then
        dCw, dCcw = Config.switchCapsuleLong - 2.5, Config.switchCapsuleLong - 2.5
    else
        dCw, dCcw = Config.switchBodyRadius - 2.1, Config.switchBodyRadius - 2.1
    end
    local function whiteAt(cx, cy, half)
        local n = 0
        for dy = -half, half do
            for dx = -half, half do
                local sx = math.floor(cx + dx + 0.5)
                local sy = math.floor(cy + dy + 0.5)
                if sx >= 0 and sy >= 0 and sx < 400 and sy < 240 then
                    if img:sample(sx, sy) == gfx.kColorWhite then n = n + 1 end
                end
            end
        end
        return n
    end
    -- tangential CW bei 90° = +y (unten), CCW = -y (oben).
    local cw = whiteAt(swX, swY + dCw, 2)
    local ccw = whiteAt(swX, swY - dCcw, 2)
    log(string.format("MEASURE %s style=%s cw=%d ccw=%d", name, style, cw, ccw))
end

-- 0) Isolierter Probe-Scene: NUR ein Schalter (kein Shutter/Bridge/Gate), um
--    die Nockenzeichnung ohne Überlagerungen zu prüfen.
do
    local probeRoom = {
        name = "Probe",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" },
        },
        shutters = {},
        bridges = {},
        gate = nil,
    }
    Config.switchStyle = "C"
    State.init(probeRoom)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(probeRoom.rings.outer)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 200
    State.setSwitch("S1", "A")
    local probeImg = renderScene("probe_switch_C_A")
    if probeImg then
        measureSwitch("probe_switch_C_A", probeImg)
        local okT, visOut = pcall(function() return Camera.getVisualOuterRing() end)
        local okI, isTrans = pcall(function() return Camera.isTransitioning() end)
        local okR, ringOuter = pcall(function() return state.room.rings.outer end)
        local okRR, rOuter = pcall(function() return Render.ringRadius("outer") end)
        log(string.format("CAM probe visOuter=%s trans=%s ringsOuter=%s rOuter=%s",
            tostring(visOut), tostring(isTrans), tostring(ringOuter), tostring(rOuter)))
        local scan = {}
        for x = 280, 330 do
            local c = probeImg:sample(x, 120)
            scan[#scan + 1] = (c == gfx.kColorWhite) and "W" or "."
        end
        log("SCAN y=120 x280-330: " .. table.concat(scan))
        log("SAMPLE probe_center=" .. tostring(probeImg:sample(304, 120))
            .. " activeMark=" .. tostring(probeImg:sample(304, 123))
            .. " inactiveMark=" .. tostring(probeImg:sample(304, 117))
            .. " bg=" .. tostring(probeImg:sample(5, 5)))
        -- Raster um den Schalter (neue Geometrie, Debug).
        for ry = -6, 6 do
            local row = {}
            for rx = -6, 6 do
                local c = probeImg:sample(304 + rx, 120 + ry)
                row[#row + 1] = (c == gfx.kColorWhite) and "W" or "."
            end
            log("GRID2 probe y" .. tostring(ry) .. " " .. table.concat(row))
        end
    end
end

-- 1) Schalter: Zustand A und B je Variante (config.switchStyle).
for _, style in ipairs({ "A", "B", "C" }) do
    Config.switchStyle = style
    setupRoom()
    -- Player weit weg, damit der Schalter klar lesbar ist.
    State.player.ring = "outer"
    State.player.angle = 200
    State.setSwitch("S1", "A")
    local imgA = renderScene("switch_" .. style .. "_A")
    if imgA then measureSwitch("switch_" .. style .. "_A", imgA) end
    State.setSwitch("S1", "B")
    local imgB = renderScene("switch_" .. style .. "_B")
    if imgB then measureSwitch("switch_" .. style .. "_B", imgB) end
end

-- Schalter-Press-Zustand (2 Frames eingedrückt, echter Umschalt-Snap).
Config.switchStyle = "C"
setupRoom()
State.player.ring = "outer"
State.player.angle = 90
State.setSwitch("S1", "A")
Render.switchPressFrames = 2
renderScene("switch_C_press_A")

-- 2) Aktive Brücke (frei, voll ausgefahren mit Endkappen).
setupRoom()
State.player.ring = "outer"
State.player.angle = 60
renderScene("bridge_active_B0")

-- 3) Inaktive Brücke (S1=B -> B1 inaktiv, Stummel + Bruch-Kerbe).
setupRoom()
State.player.ring = "outer"
State.player.angle = 60
State.setSwitch("S1", "B")
renderScene("bridge_inactive_B1")

-- 4) Bridge Ready: Player dockt an aktiver Brücke B0@180 an -> kurzer
--    Verdichtungs-Impuls (bridgeReadyFrames > 0).
setupRoom()
State.player.ring = "outer"
State.player.angle = 180
Render.update(0.016)
Render.updateObjectAnimations(0.016)
renderScene("bridge_ready_B0")

-- 5) Raum-Überblick: mehrere Elemente gleichzeitig (Schalter A, aktive und
--    inaktive Brücke, Blende, Gate, Player + Baby).
setupRoom()
State.player.ring = "outer"
State.player.angle = 100
State.setSwitch("S1", "B") -- B1 inaktiv, D1 offen; S2=B -> B2 inaktiv, D2 zu
Render.update(0.016)
Render.updateObjectAnimations(0.016)
renderScene("room_overview")

-- Fertig-Marker + Beenden.
local f, ferr = playdate.file.open("screenshot_done.txt", playdate.file.kFileWrite)
if f then
    f:write("done")
    f:close()
end
log("SCREENSHOTS_DONE")
if logF then
    logF:flush()
    logF:close()
end
playdate.simulator.exit()
