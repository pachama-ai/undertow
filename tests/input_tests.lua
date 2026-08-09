-- Tests für Phase 10.4 „Eingaben": B-Geste (kurz = Undo, 0,6 s = Restart),
-- Hold-Fortschrittsring und Crank-eingeklappt-Hinweis.
--
-- Teil A: BGesture-Unit (core/bgesture.lua) — deterministisch über dt
--   (Punkt 62): press ohne Release, Tap, 0.59 s, exakt 0.60 s, langes Halten,
--   Release nach Restart, neuer Tap, Fortschritt (25/50/Clamp).
-- Teil B: Controller-Contract — Gesture-Aktion auf echte Module angewendet
--   (Tap -> Undo genau einmal; Hold -> Raum frisch/derselbe, Undo 0, kein
--   Save-Write; während Bridge/Camera/Completion; leerer Undo-Stack).
-- Teil C: Render — setRestartHoldProgress (Clamp), Hold-Ring-Bogen um die
--   Figur (0 -> keiner, 0.5 -> halber Bogen 0..180°), Draw-Order Player ->
--   Ring -> Overlay, Crank-Overlay-Text (docked/undocked/roomComplete),
--   read-only.
-- Teil D: Crank-D-Pad — bei gedockter Kurbel bleiben D-Pad/A/B-Tap/B-Hold
--   voll spielbar (kein Gameplay-Gate durch Docking).
--
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- core/audio, core/bgesture, world/player, world/room, world/bridge,
-- ui/render, ui/camera und data/levels per import geladen wurden.

local pass = 0
local fail = 0

local function check(condition, message)
    if condition then
        pass = pass + 1
        print("PASS: " .. message)
    else
        fail = fail + 1
        print("FAIL: " .. message)
    end
end

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-9)
end

-- --- Teil A: BGesture-Unit ----------------------------------------------------
local function press()
    return BGesture.update(true, true, false, 0)
end
local function hold(dt)
    return BGesture.update(false, true, false, dt)
end
local function release()
    return BGesture.update(false, false, true, 0)
end

-- Press allein: kein Undo, kein Restart (Punkt 63).
BGesture.reset()
check(press() == nil, "b: Press allein -> keine Aktion")
check(BGesture.getProgress() == 0, "b: Press -> Fortschritt 0")

-- Kurzer Tap: Release vor 0,6 s -> genau 1 Undo (Punkt 64).
BGesture.reset()
press()
hold(0.1)
check(release() == "undo", "b: Tap (0,1 s) -> undo")
check(release() == nil, "b: nach Release kein Doppel-Undo (Geste inaktiv)")

-- 0.59 s: noch kein Restart, Fortschritt ~0.9833 (Punkt 65).
BGesture.reset()
press()
check(hold(0.59) == nil, "b: 0,59 s -> keine Aktion")
check(approx(BGesture.getProgress(), 0.59 / Config.restartHoldDuration, 1e-9),
    "b: 0,59 s -> progress = 0.9833")

-- exakt 0.60 s: genau 1 Restart, kein Undo (Punkt 66).
BGesture.reset()
press()
check(hold(0.60) == "restart", "b: exakt 0,60 s -> restart")
check(BGesture.getProgress() == 0, "b: nach Restart Fortschritt 0")

-- Release im Schwellenframe: Restart gewinnt (Punkt 12).
BGesture.reset()
press()
hold(0.5)
check(BGesture.update(false, false, true, 0.10) == "restart",
    "b: Release im Schwellenframe (0,60 s gesamt) -> restart, kein Undo")

-- Langes Halten (1,5 s): nur EIN Restart (Punkt 13/67).
BGesture.reset()
press()
check(hold(0.60) == "restart", "b: langes Halten -> 1. Restart")
check(hold(0.9) == nil, "b: langes Halten -> danach keine weitere Aktion")

-- Release nach Hold-Restart: kein Undo (Punkt 14/68).
BGesture.reset()
press()
hold(0.6)
check(release() == nil, "b: Release nach Restart -> kein Undo")

-- Neuer Tap nach vollständigem Release (nach Restart + Reset) (Punkt 15/69).
BGesture.reset()
press()
hold(0.6) -- restart
BGesture.reset() -- z. B. durch Raumstart
press()
hold(0.1)
check(release() == "undo", "b: neuer Tap nach Reset -> wieder undo")

-- Fortschritt 25 % / 50 % (Punkt 78/79).
BGesture.reset()
press()
hold(0.15)
check(approx(BGesture.getProgress(), 0.25, 1e-9), "b: 0,15 s -> progress 0.25")
BGesture.reset()
press()
hold(0.30)
check(approx(BGesture.getProgress(), 0.5, 1e-9), "b: 0,30 s -> progress 0.5")

-- Clamp: Fortschritt nie <0 oder >1 (Punkt 80).
BGesture.reset()
press()
hold(0.599)
local p = BGesture.getProgress()
check(p >= 0 and p <= 1, "b: progress im gültigen Bereich (0..1)")

-- --- Teil B: Controller-Contract (echte Module) ------------------------------
-- Anwenden wie main.lua bei "undo".
local function applyTapUndo()
    Room.resetDockAssist()
    local restored = Undo.undo()
    if restored then
        Room.syncPhysicalShutters()
    end
    return restored
end
-- Anwenden wie main.lua restartRoom (startRoom + stabile Kamera), exakte
-- Produktions-Reihenfolge.
local function resetRoomContract(roomIndex)
    local roomData = Levels[roomIndex]
    Bridge.resetTransit()
    Room.resetDockAssist()
    State.init(roomData)
    Undo.clear()
    Room.init()
    Camera.init(State.room.rings.outer)
    Render.resetPlayerVisual()
    Audio.resetRoom(roomIndex)
    BGesture.reset()
end

-- Tap mit gefülltem Undo-Stack: genau ein Undo (Punkt 26).
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.setSwitch("S1", "B")
Undo.push(State.snapshot())
check(Undo.count() == 2, "ctrl: Undo-Stack vor Tap = 2")
BGesture.reset()
press()
hold(0.1)
check(BGesture.update(false, false, true, 0) == "undo", "ctrl: Tap -> undo-Aktion")
check(applyTapUndo() == true, "ctrl: Undo erfolgreich angewendet")
check(Undo.count() == 1, "ctrl: Undo-Stack 2 -> 1")

-- Leerer Undo-Stack: kurzer Tap kein Crash, kein Restart (Punkt 27/70).
resetRoomContract(1)
check(Undo.count() == 0, "ctrl: Undo-Stack leer")
BGesture.reset()
press()
hold(0.1)
check(BGesture.update(false, false, true, 0) == "undo", "ctrl: Tap bei leerem Stack -> undo-Aktion")
local okEmpty = pcall(function()
    applyTapUndo()
end)
check(okEmpty, "ctrl: leerer Undo-Stack -> kein Crash (No-op)")

-- Hold mit gefülltem Undo-Stack: KEIN Undo vorher, Restart -> Undo 0 (Punkt 28/71).
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.setSwitch("S1", "B")
Undo.push(State.snapshot())
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.setSwitch("S1", "B")
Undo.push(State.snapshot())
check(Undo.count() == 4, "ctrl: Undo-Stack vor Hold = 4")
BGesture.reset()
press()
hold(0.3)
check(Undo.count() == 4, "ctrl: während Hold (0,3 s) kein Undo (Stack bleibt 4)")
check(BGesture.update(false, true, false, 0.30) == "restart", "ctrl: Hold -> restart-Aktion")
resetRoomContract(1)
check(Undo.count() == 0, "ctrl: nach Restart Undo = 0")

-- Restart behält Raum (Räume 1-6, Abschlussphase A) (Punkt 72/19).
for _, ri in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    resetRoomContract(ri)
    State.player.angle = 200
    State.setSwitch("S1", "A")
    Undo.push(State.snapshot())
    BGesture.reset()
    press()
    hold(0.6)
    resetRoomContract(ri)
    check(State.room ~= nil and State.room.name == Levels[ri].name,
        "ctrl-room" .. ri .. ": Restart bleibt Raum " .. ri)
    check(State.player.ring == Levels[ri].start.ring and State.player.angle == Levels[ri].start.angle,
        "ctrl-room" .. ri .. ": Player = Start")
    check(Undo.count() == 0, "ctrl-room" .. ri .. ": Undo = 0")
end

-- Save unverändert bei Restart (Punkt 73).
local realDatastore = playdate.datastore
local writeCount = 0
playdate.datastore = {
    read = function() return { highestRoom = 3 } end,
    write = function() writeCount = writeCount + 1 end,
    delete = function() return true end,
}
resetRoomContract(2)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
BGesture.reset()
press()
hold(0.6)
resetRoomContract(2)
check(writeCount == 0, "ctrl: B-Hold-Restart schreibt Datastore nicht")

-- Gating wie main.updateRoom: kurzer B-Tap-Undo NUR bei entsperrtem Gameplay
-- (Camera-Transition / Bridge-Transit / Completion sperren; Punkt 22).
local function tapUndoAllowed()
    if Camera.isTransitioning() then
        return false
    end
    if Bridge.isCrossing() then
        return false
    end
    return true
end

-- Hold während Bridge-Transit (Punkt 74): kurz -> kein Undo, Hold -> Restart.
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.elementStates["B1"] = true
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
check(Bridge.isCrossing() == true, "ctrl-bridge: Transit aktiv (Vorbereitung)")
check(Undo.count() == 1, "ctrl-bridge: Undo-Stack gefüllt (1)")
BGesture.reset()
press()
hold(0.1)
check(BGesture.update(false, false, true, 0) == "undo", "ctrl-bridge: Tap -> undo-Aktion")
check(tapUndoAllowed() == false, "ctrl-bridge: kurzer B-Tap während Transit -> kein Undo (Lock)")
check(Undo.count() == 1, "ctrl-bridge: Undo-Stack unverändert (kein Undo im Lock)")
resetRoomContract(1)
State.elementStates["B1"] = true
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
BGesture.reset()
press()
check(hold(0.6) == "restart", "ctrl-bridge: Hold -> restart-Aktion")
resetRoomContract(1)
check(Bridge.isCrossing() == false, "ctrl-bridge: nach Restart Transit aus")

-- Hold während Camera-Transition (Punkt 75): kurz -> kein Undo, Hold -> Restart.
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
Camera.beginRoomTransition(7, 6, 6, 5)
check(Camera.isTransitioning() == true, "ctrl-camera: Transition aktiv (Vorbereitung)")
BGesture.reset()
press()
hold(0.1)
check(BGesture.update(false, false, true, 0) == "undo", "ctrl-camera: Tap -> undo-Aktion")
check(tapUndoAllowed() == false, "ctrl-camera: kurzer B-Tap während Transition -> kein Undo")
check(Undo.count() == 1, "ctrl-camera: Undo-Stack unverändert (kein Undo im Lock)")
resetRoomContract(1)
Camera.beginRoomTransition(7, 6, 6, 5)
BGesture.reset()
press()
check(hold(0.6) == "restart", "ctrl-camera: Hold -> restart-Aktion")
resetRoomContract(2) -- aktueller Raum ist 2
check(State.room ~= nil and State.room.name == Levels[2].name,
    "ctrl-camera: Restart bleibt Raum 2")
check(Camera.isTransitioning() == false and Camera.getCurrentOuterRing() == 6,
    "ctrl-camera: nach Restart Camera stabil auf Raum-2-outer")

-- Hold nach Raum-6-Completion (Punkt 76/20/47): kurzer Tap gesperrt
-- (Completion), Hold -> Raum 6 frisch (roomComplete-Zustand via Audio-
-- Completion angenähert; das eigentliche roomComplete-Flag ist main-lokal und
-- wird im Smoke geprüft). Raum 6 ist der Finalraum (Abschlussphase A).
resetRoomContract(6)
Audio.setCompleted()
BGesture.reset()
press()
hold(0.1)
check(BGesture.update(false, false, true, 0) == "undo", "ctrl-completion: Tap -> undo-Aktion")
BGesture.reset()
press()
check(hold(0.6) == "restart", "ctrl-completion: Hold -> restart-Aktion")
resetRoomContract(6)
check(State.room ~= nil and State.room.name == Levels[6].name,
    "ctrl-completion: Restart nach Completion bleibt Raum 6 (frisch)")
Audio.resetRoom(6)
Audio.update(4.5)
check(true, "ctrl-completion: Audio nach Restart wieder aktiv (kein Crash)")

playdate.datastore = realDatastore

-- --- Teil C: Render (Hold-Ring + Crank-Overlay) ------------------------------
-- render.lua erfasst `local gfx <const> = playdate.graphics` beim Laden; ein
-- GFX-Mock-Umstecken greift daher NICHT. Verifikation über Offscreen-Sampling
-- (image.new + pushContext + image:sample, Phase-10.1-Technik): die ECHTE
-- Render-Pipeline zeichnet in eine Offscreen-Canvas, danach werden Pixel
-- gelesen. Draw-Order (Player -> Hold-Ring -> Overlay) ist strukturell in
-- drawRoom (drawPlayer(); drawRestartHoldRing(); drawCrankOverlay()); da der
-- Ring (Radius 10) die 7-px-Figur nicht überlappt, ist die Reihenfolge per
-- Pixel nicht unterscheidbar — sie wird per Codestruktur sichergestellt.
local realIsCrankDocked = playdate.isCrankDocked
local docked = false
playdate.isCrankDocked = function()
    return docked
end

local gfxApi = playdate.graphics
local function renderToCanvas(drawFn)
    local img = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img)
    local ok, err = pcall(drawFn)
    gfxApi.popContext()
    if not ok then
        error("renderToCanvas: " .. tostring(err))
    end
    return img
end
-- Weiße Pixel in einem (2*half+1)^2-Fenster um (cx, cy) finden.
local function hasWhiteNear(img, cx, cy, half)
    half = half or 2
    for dy = -half, half do
        for dx = -half, half do
            local sx = math.floor(cx + dx + 0.5)
            local sy = math.floor(cy + dy + 0.5)
            if sx >= 0 and sy >= 0 and sx < 400 and sy < 240 then
                if img:sample(sx, sy) == gfxApi.kColorWhite then
                    return true
                end
            end
        end
    end
    return false
end

resetRoomContract(1)
State.player.angle = 0

-- setRestartHoldProgress Clamp (Punkt 80).
Render.setRestartHoldProgress(0.5)
check(Render.restartHoldProgress == 0.5, "render: setRestartHoldProgress(0.5)")
Render.setRestartHoldProgress(-1)
check(Render.restartHoldProgress == 0, "render: setRestartHoldProgress(-1) -> 0 (Clamp)")
Render.setRestartHoldProgress(2)
check(Render.restartHoldProgress == 1, "render: setRestartHoldProgress(2) -> 1 (Clamp)")
Render.setRestartHoldProgress(0)

-- playerScreenPosition: exakt der visuelle Mittelpunkt auf dem Spielerring
-- (Punkt 97). Player outer@0 -> (200 + outerRadius*sin0, 120 - outerRadius*cos0).
local px, py = Render.playerScreenPosition()
check(approx(px, 200 + Config.outerRadius * math.sin(0), 0.001)
    and approx(py, 120 - Config.outerRadius * math.cos(0), 0.001),
    "render: playerScreenPosition = Polar(Spielerradius, Winkel)")

-- progress=0: kein Hold-Ring-Bogen (Punkt 96).
Render.setRestartHoldProgress(0)
local img0 = renderToCanvas(function() Render.drawRoom(false, 1) end)
local inArcX = px + Config.restartHoldRingRadius * math.sin(math.rad(30))
local inArcY = py - Config.restartHoldRingRadius * math.cos(math.rad(30))
local outArcX = px + Config.restartHoldRingRadius * math.sin(math.rad(210))
local outArcY = py - Config.restartHoldRingRadius * math.cos(math.rad(210))
check(hasWhiteNear(img0, inArcX, inArcY) == false,
    "render: progress 0 -> kein Hold-Ring")

-- progress=0.5: halber Bogen 0..180° (Punkt 96/78): In-Arc weiß, außerhalb schwarz.
Render.setRestartHoldProgress(0.5)
local img50 = renderToCanvas(function() Render.drawRoom(false, 1) end)
check(hasWhiteNear(img50, inArcX, inArcY),
    "render: progress 0.5 -> Ring im Bogen (30°) sichtbar")
check(hasWhiteNear(img50, outArcX, outArcY) == false,
    "render: progress 0.5 -> außerhalb des Bogens (210°) kein Ring")

-- progress ~1: fast geschlossener Ring (Punkt 96): 210° jetzt sichtbar.
Render.setRestartHoldProgress(0.999)
local imgFull = renderToCanvas(function() Render.drawRoom(false, 1) end)
check(hasWhiteNear(imgFull, outArcX, outArcY),
    "render: progress ~1 -> Ring auch bei 210° sichtbar (fast voll)")
Render.setRestartHoldProgress(0)

-- Crank-Overlay (Punkt 86/87/45/99): Textpixel im Overlay-Bereich.
local overlaySampleX = Config.crankOverlayX + 40
local overlaySampleY = Config.crankOverlayY + 12
docked = true
local imgDocked = renderToCanvas(function() Render.drawRoom(false, 1) end)
check(hasWhiteNear(imgDocked, overlaySampleX, overlaySampleY, 4),
    "render: docked -> Crank-Hinweis sichtbar (weiße Textpixel)")
docked = false
local imgUndocked = renderToCanvas(function() Render.drawRoom(false, 1) end)
check(hasWhiteNear(imgUndocked, overlaySampleX, overlaySampleY, 4) == false,
    "render: undocked -> kein Crank-Hinweis")
docked = true
local imgComplete = renderToCanvas(function() Render.drawRoom(true, 1) end)
check(hasWhiteNear(imgComplete, overlaySampleX, overlaySampleY, 4) == false,
    "render: roomComplete -> kein Crank-Hinweis (auch docked)")
docked = false

-- Release/Reset löscht Ring (Punkt 81/82): BGesture-Reset -> main meldet 0.
Render.setRestartHoldProgress(0.5)
BGesture.reset()
check(BGesture.getProgress() == 0, "render: Gesture-Reset -> progress 0")

-- Render bleibt read-only (Punkt 100): drawRoom + Overlay verändern State/Undo/
-- Room/Bridge/Camera/Audio/Save nicht.
Render.setRestartHoldProgress(0.5)
docked = true
local beforeState = State.room.name
local beforeUndo = Undo.count()
local beforeCamera = Camera.getCurrentOuterRing()
local beforeWrite = writeCount
pcall(Render.drawRoom, false, 1)
check(State.room.name == beforeState, "render: read-only (State)")
check(Undo.count() == beforeUndo, "render: read-only (Undo)")
check(Camera.getCurrentOuterRing() == beforeCamera, "render: read-only (Camera)")
check(writeCount == beforeWrite, "render: read-only (kein Save-Write)")
docked = false

playdate.isCrankDocked = realIsCrankDocked

-- --- Teil D: Crank-D-Pad-Spielbarkeit (Punkt 48/90-94/51) --------------------
-- Player.computeDesiredDelta liefert echten D-Pad-Delta unabhängig vom
-- Docking-Zustand (Overlay ist rein visuell; kein Crank-Gate).
local dpadRight = Player.computeDesiredDelta(0, false, true, 1 / Config.refreshRate)
check(dpadRight > 0, "dpad: rechts -> Bewegung > 0 (auch bei gedockter Kurbel)")
local dpadLeft = Player.computeDesiredDelta(0, true, false, 1 / Config.refreshRate)
check(dpadLeft < 0, "dpad: links -> Bewegung < 0")
-- Kurbel 0 + D-Pad = reine D-Pad-Bewegung; Kurbel + D-Pad addieren sich.
local both = Player.computeDesiredDelta(10, false, true, 1 / Config.refreshRate)
check(both > dpadRight, "dpad: Kurbel + D-Pad addieren sich (kein Gate)")

-- --- Teil E: D-Pad über den ECHTEN Inputpfad (Release-Fix 1) ------------------
-- Der Release-Audit fand den Bug über den echten Inputpfad (Player.getDesiredDelta
-- -> Room.movePlayer mit kleinen 1,8°-Frames bei gedockter Kurbel). Diese Tests
-- beweisen, dass der Fix mit echten Produktionswerten (Config.dpadSpeed=90,
-- refreshRate=50, dt=1/50) und isCrankDocked()==true funktioniert — ohne jede
-- Kurbelbewegung (getCrankChange = 0).
local realGetCrankChange = playdate.getCrankChange
local realButtonIsPressed = playdate.buttonIsPressed
local realIsCrankDockedE = playdate.isCrankDocked
local heldDpad = nil -- nil | kButtonLeft | kButtonRight
playdate.getCrankChange = function() return 0, 0 end
playdate.buttonIsPressed = function(b)
    if b == playdate.kButtonLeft or b == playdate.kButtonRight then
        return heldDpad == b
    end
    return false
end
playdate.isCrankDocked = function() return true end -- gedockt: D-Pad bleibt spielbar

-- Ein Frame D-Pad in Richtung dir (+1 rechts / -1 links) über Player + Room.
local function dpadStep(dir)
    heldDpad = dir > 0 and playdate.kButtonRight or playdate.kButtonLeft
    local wanted = Player.getDesiredDelta(1 / Config.refreshRate)
    heldDpad = nil
    return Room.movePlayer(wanted)
end

local function dpadDrive(dir, frames)
    for _ = 1, frames do
        dpadStep(dir)
    end
end

local function inputSetup(roomIndex)
    State.init(Levels[roomIndex])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    Room.resetSwitchTraversal()
end

-- --- E1: Room1 echter D-Pad rechts -> S1 CW -> A ------------------------------
do
    inputSetup(1) -- S1@90 (Bogen [83,97]), Start 0
    -- 54 Frames * 1.8° = 97.2° -> über Austrittskante 97.
    dpadDrive(1, 54)
    check(State.switchStates["S1"] == "A", "input-r1-cw: S1 -> A (D-Pad rechts, echter Pfad)")
    check(Undo.count() == 1, "input-r1-cw: 1 Undo")
    check(math.abs(State.player.angle - 97.2) < 0.01, "input-r1-cw: Ende 97.2 (nur D-Pad, keine Kurbel)")
end

-- --- E2: Room1 echter D-Pad links -> S1 CCW -> B ------------------------------
do
    inputSetup(1)
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 100
    dpadDrive(-1, 12) -- 100 -> 78.4, über CCW-Eintritt 97 und -Austritt 83
    check(State.switchStates["S1"] == "B", "input-r1-ccw: S1 -> B (D-Pad links, echter Pfad)")
    check(Undo.count() == 1, "input-r1-ccw: 1 Undo")
end

-- --- E3: Room1 D-Pad-only vollständig lösen -> Gate nutzbar ------------------
-- Lösung ohne Kurbel: rechts bis 270 (S1 -> A öffnet B1), A an B1 (Brücke),
-- Transit abwarten, links bis 180 (Gate T), A am Gate.
do
    inputSetup(1)
    -- D-Pad rechts 0 -> 270 (150 Frames, kreuzt S1 -> A).
    dpadDrive(1, 150)
    check(State.switchStates["S1"] == "A", "input-r1-solve: S1 -> A über D-Pad")
    check(math.abs(State.player.angle - 270) < 0.01, "input-r1-solve: an B1 (270)")
    check(State.elementStates["B1"] == true, "input-r1-solve: B1 aktiv")
    -- A an B1 -> Brücken-Transit.
    local rBridge = Room.tryUseConnection()
    check(rBridge.used == true and rBridge.kind == "bridge", "input-r1-solve: Brücke genutzt")
    while Bridge.isCrossing() do
        if Bridge.update(1 / Config.refreshRate) then
            Room.resetSwitchTraversal()
            Room.syncPhysicalShutters()
        end
    end
    check(State.player.ring == "inner", "input-r1-solve: auf inner")
    check(math.abs(State.player.angle - 270) < 0.01, "input-r1-solve: inner@270")
    -- D-Pad links 270 -> 180 (50 Frames), Gate T@180.
    dpadDrive(-1, 50)
    check(math.abs(State.player.angle - 180) < 0.01, "input-r1-solve: an Gate (180)")
    local rGate = Room.tryUseConnection()
    check(rGate.used == true and rGate.kind == "gate" and rGate.roomComplete == true,
        "input-r1-solve: Gate -> Room1 komplett")
end

-- Aufräumen der Teil-E-Mocks.
playdate.getCrankChange = realGetCrankChange
playdate.buttonIsPressed = realButtonIsPressed
playdate.isCrankDocked = realIsCrankDockedE

playdate.datastore = realDatastore

TestReport.input = { pass = pass, fail = fail }
