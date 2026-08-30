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
    local off = Config.switchCircleOffset
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
    -- Referenz-Schalter: zwei Innenkreise bei ±switchCircleOffset (bei 90°
    -- tangential CW = +y unten, CCW = -y oben).
    local c1 = whiteAt(swX, swY - off, 2)
    local c2 = whiteAt(swX, swY + off, 2)
    log(string.format("MEASURE %s circleTop=%d circleBottom=%d", name, c1, c2))
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
        local okR, ringOuter = pcall(function() return State.room.rings.outer end)
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
            .. " activeMark=" .. tostring(probeImg:sample(304, 124))
            .. " inactiveMark=" .. tostring(probeImg:sample(304, 116))
            .. " bg=" .. tostring(probeImg:sample(5, 5)))
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

-- 6) GIF-Sequenz: Schalter-Snap A -> B (aktive Seite springt, 2-Frame-Press).
log("SECTION6_START")
Config.switchStyle = "C"
do
    local snapRoom = {
        name = "Snap",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = { { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" } },
        shutters = { { id = "D1", ring = "outer", angle = 45 } },
        bridges = { { id = "B0", angle = 270, free = true }, { id = "B1", angle = 180, free = false } },
        gate = { id = "T", angle = 0, free = true },
    }
    local function snapFrame(stateVal, press)
        State.init(snapRoom)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        Camera.init(snapRoom.rings.outer)
        Render.resetPlayerVisual()
        State.player.ring = "outer"
        State.player.angle = 90
        State.setSwitch("S1", stateVal)
        Render.switchPressFrames = press and 2 or 0
        renderScene("snap_" .. stateVal .. (press and "_press" or "_idle"))
    end
    snapFrame("A", false)
    snapFrame("A", true)
    snapFrame("B", true)
    snapFrame("B", false)
end

-- 7) GIF-Sequenz: Baby wird CW gegen die geschlossene Blende gedrückt und
--    stoppt exakt davor (kein Eindringen).
do
    local bsRoom = {
        name = "BabyShutterGif",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 55 } },
        switches = { { id = "S1", ring = "outer", angle = 200, symbol = 1, onA = "B1", onB = "D1", state = "A" } },
        shutters = { { id = "D1", ring = "outer", angle = 83 } }, -- Bogen [70,96] geschlossen
        bridges = { { id = "B0", angle = 180, free = true }, { id = "B1", angle = 300, free = false } },
        gate = { id = "T", angle = 0, free = true },
    }
    State.init(bsRoom)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(bsRoom.rings.outer)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 30
    State.baby.angle = 55
    renderScene("baby_push_0") -- Start: Baby vor der Blende
    Room.movePlayer(25)        -- Player schiebt Baby ein Stück
    renderScene("baby_push_1")
    Room.movePlayer(25)        -- Baby stoppt exakt vor der Blende
    renderScene("baby_push_2")
    Room.movePlayer(25)        -- gehalten: kein weiteres Eindringen
    renderScene("baby_push_3")
end

-- 8) GIF-Sequenz: aktive vs. inaktive Brücke im selben Raum (B0 aktiv@180,
--    B1 inaktiv@300 mit S1=B).
do
    local room = {
        name = "BridgeGif",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = { { id = "S1", ring = "outer", angle = 200, symbol = 1, onA = "B1", onB = "D1", state = "B" } },
        shutters = { { id = "D1", ring = "outer", angle = 45 } },
        bridges = { { id = "B0", angle = 180, free = true }, { id = "B1", angle = 300, free = false } },
        gate = { id = "T", angle = 0, free = true },
    }
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(room.rings.outer)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 20
    renderScene("bridge_activ_vs_inactive")
end

-- 9) GIF-Sequenzen: Gemeinsamer Brückenübergang (Handling + Animation + Eye).
--    Frames einer Shared-Transit-Sequenz: Ready -> A -> Baby Lead -> beide
--    Mid-Bridge -> Baby landet -> Player landet -> kurzer Blick zum Baby.
do
    local sharedRoom = {
        name = "SharedGif",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 180 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
    local function setupShared(playerAngle, babyAngle)
        State.init(sharedRoom)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        Camera.init(sharedRoom.rings.outer)
        Render.resetPlayerVisual()
        State.player.ring = "outer"
        State.player.angle = playerAngle
        State.baby.ring = "outer"
        State.baby.angle = babyAngle
        Render.updateObjectAnimations(0.016)
    end
    -- Vollständige Shared-Transit-Sequenz rendern (Ready bis Post-Landing).
    local function renderSharedSequence(prefix)
        renderScene(prefix .. "_ready") -- Ready: Dockformation + radialer Blick
        local res = Room.tryUseConnection() -- A
        if not (res.used and res.crossing and res.kind == "sharedBridge") then
            log("SHARED_NO_TRANSIT " .. prefix)
            return
        end
        Render.notePlayerTransitStart() -- Transit-Fokus (Auge)
        -- Baby Lead: Baby beginnt die radiale Überquerung, Player steht noch.
        Bridge.update(Config.sharedBridgeHold + Config.sharedBabyLead * 0.5)
        renderScene(prefix .. "_baby_lead")
        -- Mid-Bridge: beide gleichzeitig im radialen Zwischenraum (Baby voraus).
        Bridge.update(Config.sharedBabyDuration * 0.5)
        renderScene(prefix .. "_mid_bridge")
        -- Baby-Landephase: Baby am Zielring (Exit), Player folgt.
        Bridge.update(Config.sharedPlayerDuration * 0.5)
        renderScene(prefix .. "_baby_landing")
        -- Player-Landing: Abschluss + Landing-Squint.
        local done = false
        while not done do
            local d = Bridge.update(0.02)
            done = d
        end
        Render.notePlayerLanding()
        renderScene(prefix .. "_landing")
        -- Post-Landing: kurzer Blick zum Baby (Eye-Frames vorgeschaltet).
        Render.update(0.02, false)
        Render.update(0.02, false)
        renderScene(prefix .. "_post_landing")
    end

    -- GIF 1: ideales Dock (Player + Baby exakt an der Achse).
    setupShared(180, 180)
    renderSharedSequence("shared_ideal")

    -- GIF 2: leicht ungenaues Docking (beide leicht VOR dem exakten Winkel).
    setupShared(173, 183)
    renderSharedSequence("shared_vor")

    -- GIF 3: leicht von der anderen Seite versetzt (Player knapp nach der Achse).
    setupShared(183, 187)
    renderSharedSequence("shared_hinter")

    -- GIF 4: Player-Auge (Gameplay-Zoom) — Ready-Gaze, Transit-Fokus,
    -- Landing-Squint, kurzer Blick zum Baby.
    do
        setupShared(176, 184)
        renderScene("eye_ready") -- Ready: Pupille radial zur Brücke
        local res4 = Room.tryUseConnection()
        if not (res4.used and res4.crossing) then
            log("EYE_NO_TRANSIT")
        else
            Render.notePlayerTransitStart()
            renderScene("eye_focus") -- Transit-Fokus (Pupille größer/radial)
            Bridge.update(Config.sharedBridgeHold + Config.sharedBabyLead + 0.06)
            renderScene("eye_mid")   -- Mid-Bridge: Auge sichtbar, radial
            local done4 = false
            while not done4 do
                local d = Bridge.update(0.02)
                done4 = d
            end
            Render.notePlayerLanding()
            renderScene("eye_landing") -- Landing-Squint (Lidlinie)
            Render.update(0.02, false)
            Render.update(0.02, false)
            renderScene("eye_post")  -- kurzer Blick zum Baby
        end
    end

    -- GIF 5: zu weit weg -> A darf KEIN Shared-Transit auslösen (Solo erlaubt).
    do
        setupShared(176, 210) -- Baby 30° von der Achse (>> sharedDockRange)
        renderScene("shared_zu_weit") -- vor A: Player nahe, Baby fern
        local res5 = Room.tryUseConnection()
        if res5.used and res5.crossing and res5.kind == "sharedBridge" then
            log("FAR_SHARED_UNEXPECTED")
        else
            log("FAR_NO_SHARED kind=" .. tostring(res5.kind))
        end
        Bridge.resetTransit()
    end
end

-- 10) SHARED BRIDGE PATH FIX: 14-Frame-Sequenz + Debug-Overlay (NUR Test-
--     Harness, NICHT im Produktionsspiel). Markiert die Bridge-Achse und die
--     Figuren-Center, damit eindeutig sichtbar ist: alle Crossing-Center
--     liegen auf der sichtbaren Bridge-Achse.
do
    local function drawAxisOverlay()
        local fromR = Render.ringRadius("outer")
        local toR = Render.ringRadius("inner")
        local axis = 180
        local ax1, ay1 = Geometry.polar(Config.centerX, Config.centerY, fromR, axis)
        local ax2, ay2 = Geometry.polar(Config.centerX, Config.centerY, toR, axis)
        -- Bridge-Achse markieren (Test-Harness only).
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(1)
        gfx.drawLine(ax1, ay1, ax2, ay2)
        gfx.fillCircleAtPoint(ax1, ay1, 2)
        gfx.fillCircleAtPoint(ax2, ay2, 2)
        -- Figuren-Center: Player + Baby als schwarze Kreuze auf den weißen
        -- Körpern (müssen auf der Achse liegen).
        local px, py = Render.playerScreenPosition()
        if px then
            gfx.drawLine(px - 2.5, py, px + 2.5, py)
            gfx.drawLine(px, py - 2.5, px, py + 2.5)
        end
        local bx, by = Render.babyScreenPosition()
        if bx then
            gfx.drawLine(bx - 2, by, bx + 2, by)
            gfx.drawLine(bx, by - 2, bx, by + 2)
        end
        gfx.setColor(gfx.kColorWhite)
    end
    local function renderSceneDebug(name)
        local img = gfx.image.new(400, 240)
        gfx.pushContext(img)
        local ok, err = pcall(function()
            Render.drawRoom(false, 1)
            drawAxisOverlay()
        end)
        gfx.popContext()
        if not ok then
            log("RENDER_ERROR " .. name .. ": " .. tostring(err))
            return
        end
        writeBMP(name, img, 4) -- 4x für die Detailprüfung der Achse
    end

    local pathRoom = {
        name = "PathGif",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 184 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
    State.init(pathRoom)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(pathRoom.rings.outer)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 176
    State.baby.ring = "outer"
    State.baby.angle = 184
    Render.updateObjectAnimations(0.016)

    -- 1. vor A
    renderSceneDebug("path_pre_a")
    local res = Room.tryUseConnection() -- A
    if not (res.used and res.crossing and res.kind == "sharedBridge") then
        log("PATH_NO_TRANSIT")
    else
        Render.notePlayerTransitStart()
        local function step(dt) Bridge.update(dt) end
        -- 2-4. Alignment (Phase A, [0, hold=0.08]): Winkel, Radius = Ring.
        step(0.02); renderSceneDebug("path_align_start")   -- 2
        step(0.03); renderSceneDebug("path_align_mid")     -- 3  elapsed 0.05
        step(0.03); renderSceneDebug("path_align_done")    -- 4  elapsed 0.08
        -- 5-7. Baby Lead + Player gleitet auf die Achse (Radius bleibt Ring).
        step(0.04); renderSceneDebug("path_baby_lead")     -- 5  elapsed 0.12
        step(0.05); renderSceneDebug("path_player_start")  -- 6  elapsed 0.17
        step(0.03); renderSceneDebug("path_bridge_start")  -- 7  elapsed 0.20
        -- 8-12. Crossing (Phase B): Winkel = Achse, nur Radius wandert.
        step(0.07); renderSceneDebug("path_bridge_1_3")    -- 8  elapsed 0.27
        step(0.06); renderSceneDebug("path_bridge_mid")    -- 9  elapsed 0.33
        step(0.06); renderSceneDebug("path_bridge_2_3")    -- 10 elapsed 0.39
        step(0.05); renderSceneDebug("path_baby_landing")  -- 11 elapsed 0.44
        step(0.04); renderSceneDebug("path_player_near_landing") -- 12 elapsed 0.48
        -- 13-14. Landing + Post-Landing.
        local done = false
        while not done do
            local d = Bridge.update(0.02)
            done = d
        end
        Render.notePlayerLanding()
        renderSceneDebug("path_player_landing")            -- 13
        Render.update(0.02, false)
        Render.update(0.02, false)
        renderSceneDebug("path_post_landing")              -- 14
    end
end

-- 11) GIF-Sequenzen Raum 3 „Fernwirkung“ (Planungskette): Start, S1->D1,
--     Player-Solo nach innen, S2->D2, Rückweg, Baby-Retrieval + Shared
--     Bridge, Gate-Abschluss.
do
    local function setupRoom3()
        State.init(Levels[3])
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        Camera.init(Levels[3].rings.outer)
        Render.resetPlayerVisual()
        Render.updateObjectAnimations(0.016)
    end

    -- Startzustand (Player+Baby außen, S1, D1/D2 geschlossen).
    setupRoom3()
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 50
    renderScene("r3_start")

    -- S1 aktivieren: Player schiebt Baby, Baby parkt vor D2, D1 innen öffnet.
    setupRoom3()
    Room.movePlayer(220)
    log("R3_S1 S1=" .. State.switchStates["S1"] .. " D1=" .. tostring(State.elementStates["D1"])
        .. " baby=" .. tostring(math.floor(State.baby.angle)))
    renderScene("r3_s1")

    -- Player geht CCW zur Brücke und SOLO nach innen (Baby bleibt außen).
    Room.movePlayer(-12)
    local solo = Room.tryUseConnection()
    log("R3_SOLO kind=" .. tostring(solo.kind))
    Bridge.update(0.5)
    renderScene("r3_solo_inner")

    -- D1 offen -> S2 erreichen und schalten (D2 außen öffnet).
    Room.movePlayer(130)
    log("R3_S2 S2=" .. State.switchStates["S2"] .. " D2=" .. tostring(State.elementStates["D2"]))
    renderScene("r3_s2")

    -- Rückweg (langer CW-Weg, S2 bleibt A) -> wieder außen.
    Room.movePlayer(230)
    local back = Room.tryUseConnection()
    log("R3_BACK kind=" .. tostring(back.kind))
    Bridge.update(0.5)
    renderScene("r3_return")

    -- Baby holen: langen Weg bis ins Dock, dann Shared Transit.
    Room.movePlayer(350)
    renderScene("r3_shared_ready") -- Dockformation vor A
    local shared = Room.tryUseConnection()
    log("R3_SHARED kind=" .. tostring(shared.kind))
    if shared.used and shared.crossing then
        Bridge.update(0.25)
        renderScene("r3_shared_mid")
        Bridge.update(0.5)
    else
        log("R3_SHARED_FAILED")
    end

    -- Gemeinsam zum Gate, Abschluss.
    Room.movePlayer(205)
    renderScene("r3_gate")
    local gres = Room.tryUseConnection()
    if gres.used and gres.kind == "gate" then
        log("R3_GATE_COMPLETE roomComplete=" .. tostring(gres.roomComplete))
    else
        log("R3_GATE_FAILED")
    end
end

-- 12) GIF-Sequenzen Raum 4 „Zwei Systeme“ (ZWEI zwingende Schalter + Planung):
--     Start, S1 (Segment) -> D1+D3+D4, Player-Solo nach innen (Baby parkt an
--     D2), S2 (Brücke) -> B1+D2+T, Rückweg, Baby-Retrieval + Shared Bridge B1,
--     Gate-Abschluss.
do
    local function setupRoom4()
        State.init(Levels[4])
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        Camera.init(Levels[4].rings.outer)
        Render.resetPlayerVisual()
        Render.updateObjectAnimations(0.016)
    end

    -- Startzustand (Player+Baby außen, S1/S2=B, D1/D3/D4 geschlossen, B1/T zu).
    setupRoom4()
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 50
    renderScene("r4_start")

    -- S1 (Segment-Schalter) aktivieren: Player schiebt Baby, Baby parkt vor
    -- D2 (zu) bei ~234, D1+D3+D4 innen öffnen. SOLO-TRENNUNG vorbereitet.
    setupRoom4()
    Room.movePlayer(240)
    log("R4_S1 S1=" .. State.switchStates["S1"]
        .. " D1=" .. tostring(State.elementStates["D1"])
        .. " D3=" .. tostring(State.elementStates["D3"])
        .. " D4=" .. tostring(State.elementStates["D4"])
        .. " baby=" .. tostring(math.floor(State.baby.angle)))
    renderScene("r4_s1")

    -- Player geht CCW ans B0-Dock und SOLO nach innen (Baby bleibt außen).
    Room.movePlayer(-34)
    local solo = Room.tryUseConnection()
    log("R4_SOLO kind=" .. tostring(solo.kind))
    Bridge.update(0.5)
    renderScene("r4_solo_inner")

    -- D1 offen -> S2 (Brückenschalter) erreichen und schalten:
    -- B1 aktiv, D2 (Babyweg) offen, Tor T offen.
    Room.movePlayer(130)
    log("R4_S2 S2=" .. State.switchStates["S2"]
        .. " B1=" .. tostring(State.elementStates["B1"])
        .. " D2=" .. tostring(State.elementStates["D2"])
        .. " T=" .. tostring(State.elementStates["T"]))
    renderScene("r4_s2")

    -- Rückweg (langer CW-Weg, S2 bleibt A, D4/D3 offen) -> wieder außen.
    Room.movePlayer(230)
    local back = Room.tryUseConnection()
    log("R4_BACK kind=" .. tostring(back.kind))
    Bridge.update(0.5)
    renderScene("r4_return")

    -- Baby holen: D2 ist offen, Player schiebt Baby CW bis ins B1-Dock
    -- (Player ~272, Baby ~280), dann Shared Transit B1.
    Room.movePlayer(92)
    renderScene("r4_shared_ready") -- Dockformation vor A
    local shared = Room.tryUseConnection()
    log("R4_SHARED kind=" .. tostring(shared.kind))
    if shared.used and shared.crossing then
        Bridge.update(0.25)
        renderScene("r4_shared_mid")
        Bridge.update(0.5)
    else
        log("R4_SHARED_FAILED")
    end

    -- Gemeinsam zum Gate (Tor T offen durch S2, D4 offen durch S1), Abschluss.
    Room.movePlayer(105)
    renderScene("r4_gate")
    local gres = Room.tryUseConnection()
    if gres.used and gres.kind == "gate" then
        log("R4_GATE_COMPLETE roomComplete=" .. tostring(gres.roomComplete))
    else
        log("R4_GATE_FAILED")
    end
end

-- 13) QA-Serie „PLAYER + BABY + BABY-DOCK“ (Referenz-Abnahme in 400×240).
--     Gezielte Szenen für die visuelle Prüfung der Figurenfamilie:
--     Player (großer Kreis + dunkler Innenkreis), Baby (kleiner Quadratrahmen
--     + Innenkreis) und Baby-Dock (vier L-förmige Eckmarken).
do
    local qaRoom = {
        name = "QaFig",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 300 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
    local function setupQa()
        State.init(qaRoom)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        Camera.init(qaRoom.rings.outer)
        Render.resetPlayerVisual()
        Render.updateObjectAnimations(0.016)
    end

    -- 01) Player neutral: großer runder Körper + zentraler dunkler Innenkreis.
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 300 -- Baby weit weg (Fokus auf den Player)
    renderScene("01_player_neutral")

    -- 02) Player Pupillenversatz (Facing CW -> Pupille tangential versetzt).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 300
    Render.notePlayerMovement(5)
    renderScene("02_player_pupil_offset")

    -- 03) Player Blink (kurze Lidlinie).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 300
    Render.playerVisual.blinkFramesRemaining = Config.blinkFrames
    renderScene("03_player_blink")

    -- 04) Baby neutral: kleiner Quadratrahmen + runder Innenkreis (zentral).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 40
    renderScene("04_baby_neutral")

    -- 05) Baby Blink (kurzer horizontaler Strich an derselben Position).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 40
    Render.babyVisual.blinkFramesRemaining = Config.babyBlinkFrames
    renderScene("05_baby_blink")

    -- 06) Baby Look links (Player-Tracking: Innenkreis zeigt zum Player links).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 30 -- CCW vom Baby (links)
    State.baby.ring = "outer"
    State.baby.angle = 40
    renderScene("06_baby_look_left")

    -- 07) Baby Look rechts (Player-Tracking: Innenkreis zeigt zum Player rechts).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 50 -- CW vom Baby (rechts)
    State.baby.ring = "outer"
    State.baby.angle = 40
    renderScene("07_baby_look_right")

    -- 08) Baby Push: 1-px-Kompression in Pushrichtung + Innenkreis-Versatz.
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 60
    State.baby.ring = "outer"
    State.baby.angle = 40
    Render.notePlayerMovement(5)
    Render.noteBabyPush(1) -- Player schiebt Baby CW
    Render.notePlayerPushContact()
    renderScene("08_baby_push")

    -- 09) Baby Blocked: kurze Squint-Linie + minimale Kompression.
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 60
    State.baby.ring = "outer"
    State.baby.angle = 40
    Render.noteBabyBlocked(true)
    renderScene("09_baby_blocked")

    -- 10) Player + Baby auf demselben Ring (mittlerer Abstand).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 20
    State.baby.ring = "outer"
    State.baby.angle = 60
    renderScene("10_player_and_baby_same_ring")

    -- 11) Player + Baby direkt nahe (Kontaktabstand).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 36
    State.baby.ring = "outer"
    State.baby.angle = 40
    renderScene("11_player_and_baby_close")

    -- 12) Player + Baby weit voneinander (dieselbe Ringebene).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 0
    State.baby.ring = "outer"
    State.baby.angle = 180
    renderScene("12_player_and_baby_far")

    -- 13) Dock erscheint (Brücke relevant, Baby in Dock-Nähe, NICHT bereit):
    --     vier weiße L-förmige Eckmarken an der gültigen Babyposition.
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 160
    State.baby.ring = "outer"
    State.baby.angle = 200 -- 20° von der Achse (Dock sichtbar, kein Snap)
    renderScene("13_dock_appears")

    -- 14) Baby nähert sich dem Dock (noch > sharedDockRange -> kein Snap).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 170
    State.baby.ring = "outer"
    State.baby.angle = 196 -- 16° von der Achse
    renderScene("14_baby_approaches_dock")

    -- 15) Baby im Dock (Transfer bereit): Baby exakt auf der Achse, Eckmarken
    --     umschreiben die Figur, Baby voll sichtbar; kein Feedback (abgeklungen).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 176
    State.baby.ring = "outer"
    State.baby.angle = 184
    Render.updateObjectAnimations(0.016) -- Feedback-Flanke
    Render.updateObjectAnimations(0.016) -- abklingen lassen
    Render.updateObjectAnimations(0.016) -- abgeklungen
    renderScene("15_baby_inside_dock")

    -- 16) Shared Ready: Dockformation + einmaliges Ready-Feedback der Ecken
    --     (Ecken 1 px nach innen, 2-3 Frames).
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 176
    State.baby.ring = "outer"
    State.baby.angle = 184
    Render.updateObjectAnimations(0.016) -- Flanke: Feedback gerade aktiv
    renderScene("16_shared_ready")

    -- 17-19) Shared Transit als EINE Sequenz: Start / Mitte / Landing.
    setupQa()
    State.player.ring = "outer"
    State.player.angle = 176
    State.baby.ring = "outer"
    State.baby.angle = 184
    Render.updateObjectAnimations(0.016)
    local resS = Room.tryUseConnection()
    if resS.used and resS.crossing and resS.kind == "sharedBridge" then
        Render.notePlayerTransitStart()
        -- Start: Baby beginnt radial, Player steht noch in der Formation.
        Bridge.update(Config.sharedBridgeHold + Config.sharedBabyLead * 0.5)
        renderScene("17_shared_transit_start")
        -- Mitte: beide auf der Brücke, Baby deutlich voraus.
        Bridge.update(Config.sharedBabyDuration * 0.5)
        renderScene("18_shared_transit_middle")
        -- Landing: Baby am Zielring, Player folgt.
        Bridge.update(Config.sharedPlayerDuration * 0.5)
        renderScene("19_shared_transit_landing")
        -- Transit abschließen (Zustand sauber).
        local doneS = false
        while not doneS do
            local d = Bridge.update(0.02)
            doneS = d
        end
    else
        log("QA17_NO_TRANSIT")
    end
end

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
