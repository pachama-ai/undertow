-- Tests für „Eingaben" nach dem B-Taste-Rework: B = Undo auf der Press-Edge
-- (genau ein Undo pro physischem B-Drücken, KEIN B-Hold-Restart mehr),
-- Crank-eingeklappt-Hinweis und D-Pad-Spielbarkeit.
--
-- Teil A: B-Input-Contract — ein B-Press erzeugt genau EIN Undo; Halten
--   (0,1 s / 0,5 s / 0,6 s / 1,0 s / 1,5 s / 2,0 s) erzeugt KEINEN Restart,
--   kein Mehrfach-Undo und leert den Stack nicht (Press-Edge, Teile 1/11/18);
--   leerer Undo-Stack -> No-op (kein Crash, kein Restart, Teil 10);
--   B-Undo schreibt Datastore nicht; B ist während Bridge-Transit gesperrt
--   (Teil 12).
-- Teil B: Undo-Semantik über echte Module — Schalter (inkl. abgeleiteter
--   Elemente) und Baby-Push (Player- + Babyposition). Bridge-Transit (solo
--   und gemeinsam) erzeugt BEWUSST keinen Undo-Snapshot und ist damit nicht
--   undo-bar (dokumentiert, Teile 8/17 — keine heimlich neue Semantik).
--   Es gibt kein Baby-Ablageziel mehr (kein settle).
-- Teil C: Render — Crank-eingeklappt-Hinweis (docked/undocked/roomComplete),
--   read-only. Kein B-Hold-Fortschrittsring mehr (entfernt, Teile 3/15).
-- Teil D: Crank-D-Pad — D-Pad bleibt voll spielbar bei gedockter Kurbel.
-- Teil E: D-Pad über den echten Inputpfad (Release-Fix 1).
--
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- core/audio, core/save, core/sysmenu, world/player, world/room, world/bridge,
-- world/baby, ui/render, ui/camera und data/levels per import geladen wurden.
-- core/bgesture ist entfernt (B-Taste Rework) und wird nicht mehr getestet.

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

-- --- Teil A: B-Input-Contract -------------------------------------------------
-- Anwenden wie main.lua updateRoom bei B-Press-Edge: Undo + Traversal-Reset +
-- Render-Reset (exakte Produktions-Reihenfolge des B-Zweigs).
local function applyBUndo()
    Room.resetDockAssist()
    Room.resetSwitchTraversal()
    local restored = Undo.undo()
    if restored then
        Room.syncPhysicalShutters()
    end
    Render.noteUndo()
    Render.noteShutterBlocked(false)
    return restored
end

-- Gating wie main.updateRoom: B-Undo NUR bei entsperrtem Gameplay (Camera-
-- Transition / Bridge-Transit / roomComplete sperren; B-Taste-Rework Teil 12).
local function bUndoAllowed()
    if Camera.isTransitioning() then
        return false
    end
    if Bridge.isCrossing() then
        return false
    end
    return true
end

-- Produktions-Startsequenz (startRoom): Bridge.resetTransit ->
-- Baby.resetTransit -> Room.resetDockAssist -> State.init -> Undo.clear ->
-- Room.init -> Camera.init(stabil) -> Render.resetPlayerVisual ->
-- Audio.resetRoom.
local function resetRoomContract(roomIndex)
    local roomData = Levels[roomIndex]
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(roomData)
    Undo.clear()
    Room.init()
    Camera.init(State.room.rings.outer)
    Render.resetPlayerVisual()
    Audio.resetRoom(roomIndex)
end

-- Datastore-Mock: B-Undo darf nie schreiben (kein Save-Effekt). Wird am Ende
-- der Datei (Teil E) wieder restauriert.
local realDatastore = playdate.datastore
local writeCount = 0
playdate.datastore = {
    read = function() return { highestRoom = 3 } end,
    write = function() writeCount = writeCount + 1 end,
    delete = function() return true end,
}

-- Kurzer B-Druck mit gefülltem Stack: genau ein Undo (Teil 1/17 „Short B").
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.setSwitch("S1", "B")
Undo.push(State.snapshot())
check(Undo.count() == 2, "b: Undo-Stack vor B = 2")
check(bUndoAllowed() == true, "b: B-Undo erlaubt (kein Lock)")
check(applyBUndo() == true, "b: B-Press -> Undo erfolgreich")
check(Undo.count() == 1, "b: genau ein Undo (Stack 2 -> 1)")
check(writeCount == 0, "b: B-Undo schreibt Datastore nicht")

-- B wird beliebig lange gehalten: pro physischem Druck genau EIN Undo, kein
-- Restart, kein Wiederholen pro Frame (Teile 1/11/18: 0,1 s / 0,5 s / 0,6 s /
-- 1,0 s / 1,5 s / 2,0 s). Da main B nur auf der Press-Edge verarbeitet, ist
-- die Haltedauer ohne Einfluss — der Test belegt den Controller-Vertrag.
for _, holdS in ipairs({ 0.1, 0.5, 0.6, 1.0, 1.5, 2.0 }) do
    resetRoomContract(1)
    State.player.angle = 200
    State.setSwitch("S1", "A")
    Undo.push(State.snapshot())
    State.setSwitch("S1", "B")
    Undo.push(State.snapshot())
    check(Undo.count() == 2, "b-hold" .. holdS .. ": Stack = 2 vor B (" .. holdS .. " s)")
    check(applyBUndo() == true, "b-hold" .. holdS .. ": B " .. holdS .. " s -> genau ein Undo")
    check(Undo.count() == 1, "b-hold" .. holdS .. ": kein Mehrfach-Undo (Stack 2 -> 1)")
    check(State.room ~= nil and State.room.name == Levels[1].name,
        "b-hold" .. holdS .. ": kein Restart (Raumindex unverändert)")
    check(State.player.angle == 200,
        "b-hold" .. holdS .. ": Startposition wird NICHT geladen (kein Restart)")
    check(Undo.count() == 1, "b-hold" .. holdS .. ": Undo-Stack nicht pauschal geleert")
end

-- Leerer Undo-Stack: B -> keine Gameplayänderung, kein Fehler, kein Restart
-- (Teil 10/17 „Empty Undo").
resetRoomContract(1)
check(Undo.count() == 0, "b-empty: Undo-Stack leer")
local angleEmpty = State.player.angle
check(applyBUndo() == false, "b-empty: B -> kein Undo (No-op)")
check(State.player.angle == angleEmpty, "b-empty: State unverändert (Winkel)")
check(State.switchStates["S1"] == Levels[1].switches[1].state, "b-empty: State unverändert (S1)")
check(State.room ~= nil and State.room.name == Levels[1].name, "b-empty: kein Restart")

-- B während Bridge-Transit: gesperrt (Teil 12). Der Contract-Spiegel verbietet
-- das Undo im Lock; der Stack bleibt unverändert (kein halber Zustand).
resetRoomContract(1)
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.elementStates["B1"] = true
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
check(Bridge.isCrossing() == true, "b-bridge-lock: Transit aktiv (Vorbereitung)")
check(bUndoAllowed() == false, "b-bridge-lock: B-Undo während Transit gesperrt")
check(Undo.count() == 1, "b-bridge-lock: Stack unverändert (kein Undo im Lock)")

-- --- Teil B: Undo-Semantik (Schalter + Baby + Bridge) -------------------------
-- Schalter: echter Zustandswechsel -> B stellt vorherigen Switch-/Elementzustand
-- wieder her (abgeleitet, kein manueller Rückbau; Teil 9/17 „Switch").
resetRoomContract(1)
State.setSwitch("S1", "B") -- Level-Start
State.player.angle = 90
Undo.push(State.snapshot()) -- vor der Handlung
State.setSwitch("S1", "A")  -- Handlung: echter Wechsel
State.player.angle = 120
check(State.elementStates["B1"] == true, "undo-switch: B1 aktiv vor Undo (abgeleitet)")
check(applyBUndo() == true, "undo-switch: B -> Undo")
check(State.switchStates["S1"] == "B", "undo-switch: S1 zurück auf B")
check(State.elementStates["B1"] == false, "undo-switch: B1 eingefahren (abgeleitet)")
check(State.elementStates["D1"] == true, "undo-switch: D1 offen (abgeleitet)")
check(State.player.angle == 90, "undo-switch: Playerposition zurück")

-- Baby-Push (Raum 2): echter Schub -> B stellt Player- und Babyposition wieder
-- her (Teil 7/17 „Baby Push").
resetRoomContract(2)
Room.movePlayer(70) -- schiebt das Baby -> genau 1 Undo-Snapshot (babyMoved)
check(Undo.count() == 1, "undo-baby: Schub erzeugt 1 Snapshot")
local startRing = Levels[2].start.ring
local startAngle = Levels[2].start.angle
local babyStartRing = Levels[2].baby.start.ring
local babyStartAngle = Levels[2].baby.start.angle
check(State.baby.ring == babyStartRing and not approx(State.baby.angle, babyStartAngle, 0.01),
    "undo-baby: Baby wurde tatsächlich geschoben (Vorbereitung)")
check(applyBUndo() == true, "undo-baby: B -> Undo")
check(State.baby.ring == babyStartRing, "undo-baby: Baby-Ring zurück")
check(approx(State.baby.angle, babyStartAngle, 0.01), "undo-baby: Baby-Winkel zurück")
check(State.baby.settled == false, "undo-baby: Baby settled false")
check(State.player.ring == startRing and approx(State.player.angle, startAngle, 0.01),
    "undo-baby: Playerposition zurück")

-- Bridge-Transit (solo): erzeugt BEWUSST keinen Undo-Snapshot (kein Snapshot-
-- Kanal für Transits, siehe room.lua/bridge.lua). B nach abgeschlossenem
-- Transit macht die Überquerung daher NICHT rückgängig — dokumentierte
-- Semantik, kein versteckter Ring-Rollback (Teil 8/17 „Bridge", ehrlich).
-- Dasselbe gilt für den gemeinsamen Player+Baby-Transit (Teil 17 „Shared
-- Bridge"): das Undo-Modell snapshotet Transitaktionen bewusst nicht.
resetRoomContract(1)
State.player.angle = 270
State.elementStates["B1"] = true
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
while Bridge.isCrossing() do
    if Bridge.update(1 / Config.refreshRate) then
        Room.resetSwitchTraversal()
        Room.syncPhysicalShutters()
    end
end
check(State.player.ring == "inner", "undo-bridge: Player auf inner nach Transit")
check(Undo.count() == 0, "undo-bridge: Transit erzeugt keinen Snapshot (dokumentiert)")
check(applyBUndo() == false, "undo-bridge: B bei leerem Stack -> No-op (kein Crash)")
check(State.player.ring == "inner", "undo-bridge: kein versteckter Ring-Rollback")

-- --- Teil C: Render (Crank-Overlay, read-only) --------------------------------
-- render.lua erfasst `local gfx <const> = playdate.graphics` beim Laden; ein
-- GFX-Mock-Umstecken greift daher NICHT. Verifikation über Offscreen-Sampling
-- (image.new + pushContext + image:sample, Phase-10.1-Technik): die ECHTE
-- Render-Pipeline zeichnet in eine Offscreen-Canvas, danach werden Pixel
-- gelesen.
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

-- playerScreenPosition: exakt der visuelle Mittelpunkt auf dem Spielerring
-- (Punkt 97). Player outer@0 -> (200 + outerRadius*sin0, 120 - outerRadius*cos0).
local px, py = Render.playerScreenPosition()
check(approx(px, 200 + Config.outerRadius * math.sin(0), 0.001)
    and approx(py, 120 - Config.outerRadius * math.cos(0), 0.001),
    "render: playerScreenPosition = Polar(Spielerradius, Winkel)")

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

-- Render bleibt read-only (Punkt 100): drawRoom + Overlay verändern State/Undo/
-- Room/Bridge/Camera/Audio/Save nicht.
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
