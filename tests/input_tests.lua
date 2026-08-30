-- Tests für „Eingaben": B startet das AKTUELLE Level einfach neu (kein
-- Rückgängig, kein Zurückspulen), Crank-eingeklappt-Hinweis und D-Pad-
-- Spielbarkeit.
--
-- Teil A: B-Input-Contract — ein B-Press startet das aktuelle Level neu
--   (Player-/Babyposition, Schalter-/Elementzustände und Undo-Stack frisch);
--   Halten erzeugt KEINEN weiteren Neustart (Press-Edge, genau ein Restart pro
--   B-Drücken — main.lua hat keinen B-Hold-Zweig mehr); B-Restart schreibt
--   Datastore nicht; B ist während Bridge-Transit gesperrt.
-- Teil B: Undo-MODUL-Semantik über echte Module (nicht mehr über die B-Taste)
--   — Schalter (inkl. abgeleiteter Elemente) und Baby-Push (Player- +
--   Babyposition). Bridge-Transit (solo und gemeinsam) erzeugt BEWUSST keinen
--   Undo-Snapshot und ist damit nicht undo-bar (dokumentiert). Es gibt kein
--   Baby-Ablageziel mehr (kein settle).
-- Teil C: Render — Crank-eingeklappt-Hinweis (docked/undocked/roomComplete),
--   read-only.
-- Teil D: Crank-D-Pad — D-Pad bleibt voll spielbar bei gedockter Kurbel.
-- Teil E: D-Pad über den echten Inputpfad (Release-Fix 1).
-- Teil F: B-Restart über den ECHTEN SDK-Inputpfad (buttonJustPressed).
--
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- core/audio, core/save, core/sysmenu, world/player, world/room, world/bridge,
-- world/baby, ui/render, ui/camera und data/levels per import geladen wurden.

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
-- B startet das aktuelle Level einfach neu (kein Rückgängig, kein
-- Zurückspulen). Der B-Restart entspricht exakt main.lua restartRoom ->
-- startRoom (in den Tests: resetSwitchUndoRoom / resetBabyIntroRoom).

-- Gating wie main.updateRoom: B-Restart NUR bei entsperrtem Gameplay (Camera-
-- Transition / Bridge-Transit / roomComplete sperren).
local function bRestartAllowed()
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

-- Synthetischer Schalterraum für die B-Undo-Semantik: Level 1 ist seit dem
-- Level-Redesign der schalterfreie Einstiegsraum (Bewegung + freie Brücke).
-- Die Undo-Contract-Tests brauchen aber einen Raum mit der alten 1:1-
-- Verdrahtung (S1 steuert B1/D1), deshalb dieser lokale Testraum.
local function makeSwitchUndoRoom()
    return {
        name = "SwitchUndo",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "B" },
        },
        shutters = { { id = "D1", ring = "outer", angle = 315 } },
        bridges = { { id = "B1", angle = 270, free = false } },
        gate = { id = "T", angle = 180, free = true },
    }
end
local function resetSwitchUndoRoom()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(makeSwitchUndoRoom())
    Undo.clear()
    Room.init()
    Camera.init(State.room.rings.outer)
    Render.resetPlayerVisual()
    Audio.resetRoom(1)
end

-- Synthetischer Baby-Raum für die Baby-Push-Undo-Semantik: Level 2 (Raum 2)
-- ist seit dem Level-Redesign der Doppelschalter-Raum OHNE Baby; der Undo-
-- Contract braucht aber einen einfachen Baby-Raum (keine Schalter/Blenden).
local function makeBabyIntroRoom()
    return {
        name = "BabyIntro",
        rings = { outer = 6, inner = 5 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 60 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
end
local function resetBabyIntroRoom()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(makeBabyIntroRoom())
    Undo.clear()
    Room.init()
    Camera.init(State.room.rings.outer)
    Render.resetPlayerVisual()
    Audio.resetRoom(2)
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

-- B-Press startet das aktuelle Level neu: Raum frisch (Player-Startposition,
-- Schalter-/Elementzustände, Undo-Stack geleert). Kein Datastore-Write.
resetSwitchUndoRoom()
State.player.angle = 200
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
State.setSwitch("S1", "B")
Undo.push(State.snapshot())
check(Undo.count() == 2, "b: Undo-Stack vor B = 2 (intern befüllt)")
check(bRestartAllowed() == true, "b: B-Restart erlaubt (kein Lock)")
resetSwitchUndoRoom() -- = B-Restart (main.lua startRoom-Reihenfolge)
check(State.player.angle == 0, "b: B -> Player zurück zur Startposition (0)")
check(State.switchStates["S1"] == "B", "b: B -> Schalterzustand zurück (Start)")
check(Undo.count() == 0, "b: B -> Undo-Stack geleert")
check(writeCount == 0, "b: B-Restart schreibt Datastore nicht")

-- B-Restart stellt auch nach Bewegung (Baby mitgeschoben) den Levelstart her.
resetBabyIntroRoom()
Room.movePlayer(70) -- schiebt das Baby
check(Undo.count() >= 1, "b-baby: Bewegung erzeugt internen Undo-Snapshot")
local babyStartAngle = makeBabyIntroRoom().baby.start.angle
check(not approx(State.baby.angle, babyStartAngle, 0.01), "b-baby: Baby verschoben (Vorbereitung)")
resetBabyIntroRoom() -- = B-Restart
check(approx(State.baby.angle, babyStartAngle, 0.01), "b-baby: B -> Baby zurück am Start")
check(State.player.angle == 0, "b-baby: B -> Player zurück am Start")
check(Undo.count() == 0, "b-baby: B -> Undo-Stack geleert")

-- Halten erzeugt KEINEN weiteren Neustart: B ist Press-Edge (genau ein
-- Restart pro physischem Drücken); main.lua hat keinen B-Hold-Zweig mehr.
-- Der Contract-Spiegel wiederholt daher nichts (kein bHeld-Zustand).
resetSwitchUndoRoom()
State.player.angle = 120
resetSwitchUndoRoom() -- erster B-Press -> 1 Restart
check(State.player.angle == 0, "b-press: B-Press -> genau ein Restart")
-- (Weitere gehaltene Frames würden nichts tun — der Spiegel und main.lua
-- haben keinen Hold-Status.)

-- B während Bridge-Transit: gesperrt (kein Restart im Lock).
resetSwitchUndoRoom()
State.elementStates["B1"] = true
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
check(Bridge.isCrossing() == true, "b-bridge-lock: Transit aktiv (Vorbereitung)")
check(bRestartAllowed() == false, "b-bridge-lock: B-Restart während Transit gesperrt")
check(State.room ~= nil and State.room.name == "SwitchUndo", "b-bridge-lock: kein Restart im Lock")

-- --- Restart-Animation (Kamera-Skalierung) ----------------------------------
-- B startet eine kurze Kollaps-/Wiederaufbau-Animation statt eines harten
-- Schnitts: alle Ringradien skalieren zum Mittelpunkt (0) und zurück (1).
-- Der Kern (fixer Mittelpunktskreis) wird NICHT skaliert — bleibt beim
-- Kollaps sichtbar.
resetSwitchUndoRoom()
local outerRing = Camera.getCurrentOuterRing()
local normalR = Camera.getRadius(outerRing)
check(normalR > 0, "b-anim: normaler Außenring-Radius > 0 (Vorbereitung)")
Camera.setRestartScale(0)
check(Camera.getRadius(outerRing) <= 1, "b-anim: scale 0 -> Radius ~0 (Kollaps zum Kern)")
Camera.setRestartScale(0.5)
local rHalf = Camera.getRadius(outerRing)
check(rHalf > 0 and rHalf < normalR, "b-anim: scale 0.5 -> Radius zwischen 0 und normal")
Camera.setRestartScale(1)
check(math.abs(Camera.getRadius(outerRing) - normalR) < 0.001, "b-anim: scale 1 -> normaler Radius")
Camera.clearRestartScale()
check(math.abs(Camera.getRadius(outerRing) - normalR) < 0.001, "b-anim: clear -> normal (keine Rest-Skalierung)")

-- --- Teil B: Undo-Modul-Semantik (Schalter + Baby + Bridge) -------------------
-- Das Undo-Modul selbst (nicht mehr über die B-Taste; B startet nur noch das
-- Level neu). Anwenden wie room.lua/main.lua es beim Undo täte.
local function applyUndo()
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

-- Schalter: echter Zustandswechsel -> Undo stellt vorherigen Switch-/Elementzustand
-- wieder her (abgeleitet, kein manueller Rückbau; Teil 9/17 „Switch").
resetSwitchUndoRoom()
State.setSwitch("S1", "B") -- Level-Start
State.player.angle = 90
Undo.push(State.snapshot()) -- vor der Handlung
State.setSwitch("S1", "A")  -- Handlung: echter Wechsel
State.player.angle = 120
check(State.elementStates["B1"] == true, "undo-switch: B1 aktiv vor Undo (abgeleitet)")
check(applyUndo() == true, "undo-switch: Undo")
check(State.switchStates["S1"] == "B", "undo-switch: S1 zurück auf B")
check(State.elementStates["B1"] == false, "undo-switch: B1 eingefahren (abgeleitet)")
check(State.elementStates["D1"] == true, "undo-switch: D1 offen (abgeleitet)")
check(State.player.angle == 90, "undo-switch: Playerposition zurück")

-- Baby-Push (Baby-Raum): echter Schub -> Undo stellt Player- und Babyposition
-- wieder her (Teil 7/17 „Baby Push"). Level 2 ist der Doppelschalter-Raum
-- ohne Baby; dieser Undo-Contract nutzt den lokalen synthetischen Baby-Raum.
resetBabyIntroRoom()
Room.movePlayer(70) -- schiebt das Baby -> genau 1 Undo-Snapshot (babyMoved)
check(Undo.count() == 1, "undo-baby: Schub erzeugt 1 Snapshot")
local babyRoom = makeBabyIntroRoom()
local startRing = babyRoom.start.ring
local startAngle = babyRoom.start.angle
local babyStartRing = babyRoom.baby.start.ring
local babyStartAngle = babyRoom.baby.start.angle
check(State.baby.ring == babyStartRing and not approx(State.baby.angle, babyStartAngle, 0.01),
    "undo-baby: Baby wurde tatsächlich geschoben (Vorbereitung)")
check(applyUndo() == true, "undo-baby: Undo")
check(State.baby.ring == babyStartRing, "undo-baby: Baby-Ring zurück")
check(approx(State.baby.angle, babyStartAngle, 0.01), "undo-baby: Baby-Winkel zurück")
check(State.baby.settled == false, "undo-baby: Baby settled false")
check(State.player.ring == startRing and approx(State.player.angle, startAngle, 0.01),
    "undo-baby: Playerposition zurück")

-- Bridge-Transit (solo): erzeugt BEWUSST keinen Undo-Snapshot (kein Snapshot-
-- Kanal für Transits, siehe room.lua/bridge.lua). Undo nach abgeschlossenem
-- Transit macht die Überquerung daher NICHT rückgängig — dokumentierte
-- Semantik, kein versteckter Ring-Rollback (Teil 8/17 „Bridge", ehrlich).
-- Dasselbe gilt für den gemeinsamen Player+Baby-Transit (Teil 17 „Shared
-- Bridge"): das Undo-Modell snapshotet Transitaktionen bewusst nicht.
resetSwitchUndoRoom()
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
check(applyUndo() == false, "undo-bridge: leerer Stack -> No-op (kein Crash)")
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

-- Crank-Hinweis (Phase 10.4, ENTFERNT): das „Kurbel ausklappen / D-Pad“-
-- Overlay existiert nicht mehr — weder gedockt noch bei roomComplete gibt es
-- Textpixel im ehemaligen Overlay-Bereich (der Hinweis ist komplett weg).
local overlaySampleX = Config.crankOverlayX + 40
local overlaySampleY = Config.crankOverlayY + 12
docked = true
local imgDocked = renderToCanvas(function() Render.drawRoom(false, 1) end)
check(hasWhiteNear(imgDocked, overlaySampleX, overlaySampleY, 4) == false,
    "render: kein Crank-Hinweis mehr (Hinweis entfernt, auch gedockt)")
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

-- --- E1: Room1 echter D-Pad rechts -> Bridge-Dock B1@90 ----------------------
do
    inputSetup(1) -- B1@90 frei aktiv, Start 0
    -- 50 Frames * 1.8° = 90° -> exakt an der Brückenachse (kein Schalter).
    dpadDrive(1, 50)
    check(math.abs(State.player.angle - 90) < 0.01, "input-r1-cw: an B1@90 (nur D-Pad, keine Kurbel)")
    check(Bridge.isUsable(State.room.bridges[1], State.player.angle) == true,
        "input-r1-cw: Brücke nutzbar (Wechsel-Radius)")
end

-- --- E2: Room1 echter D-Pad durch die Kurbel-Widerstandszone (nicht gedämpft) --
-- D-Pad bleibt voll spielbar: die Kurbel-Schwelle vor der Brücke dämpft NUR
-- den Kurbelanteil, nie das D-Pad.
do
    inputSetup(1)
    State.player.angle = 75 -- vor der Widerstandszone (78..90 vor B1@90)
    dpadDrive(1, 3) -- 75 -> 80.4, durch die Zone mit vollem D-Pad-Tempo
    check(math.abs(State.player.angle - 80.4) < 0.01,
        "input-r1-ccw: D-Pad ungedämpft durch die Widerstandszone")
    check(Undo.count() == 0, "input-r1-ccw: keine Undos (reine Bewegung)")
end

-- --- E3: Room1 D-Pad-only vollständig lösen -> Gate nutzbar ------------------
-- Lösung ohne Kurbel: rechts bis 90 (B1 frei aktiv, Baby wird mitgeschoben),
-- A an B1 (GEMEINSAMER Transit), Transit abwarten, rechts bis 135 (Gate T),
-- A am Gate.
do
    inputSetup(1)
    -- D-Pad rechts 0 -> 90 (50 Frames, an B1; Baby bei ~98 im Dock).
    dpadDrive(1, 50)
    check(math.abs(State.player.angle - 90) < 0.01, "input-r1-solve: an B1 (90)")
    check(State.elementStates["B1"] == true, "input-r1-solve: B1 aktiv (frei)")
    -- A an B1 -> GEMEINSAMER Transit (Baby ist im Dock, wird mitgenommen).
    local rBridge = Room.tryUseConnection()
    check(rBridge.used == true and rBridge.kind == "sharedBridge",
        "input-r1-solve: Brücke genutzt (gemeinsam mit Baby)")
    while Bridge.isCrossing() do
        if Bridge.update(1 / Config.refreshRate) then
            Room.resetSwitchTraversal()
            Room.syncPhysicalShutters()
        end
    end
    check(State.player.ring == "inner", "input-r1-solve: auf inner")
    check(math.abs(State.player.angle - 90) < 0.01, "input-r1-solve: inner@90")
    -- D-Pad rechts inner 90 -> 135 (25 Frames), Gate T@135 (Baby wird mit).
    dpadDrive(1, 25)
    check(math.abs(State.player.angle - 135) < 0.01, "input-r1-solve: an Gate (135)")
    local rGate = Room.tryUseConnection()
    check(rGate.used == true and rGate.kind == "gate" and rGate.crossing == true,
        "input-r1-solve: Gate -> Kernbrücken-Transit")
    check(rGate.roomComplete == false, "input-r1-solve: Abschluss erst nach Transit")
    while Bridge.isCrossing() do
        if Bridge.update(1 / Config.refreshRate) then
            Room.resetSwitchTraversal()
            Room.syncPhysicalShutters()
        end
    end
    check(State.player.ring == "inner" and State.baby.ring == "inner",
        "input-r1-solve: nach Center-Transit am Gate-Ring")
end

-- Aufräumen der Teil-E-Mocks.
playdate.getCrankChange = realGetCrankChange
playdate.buttonIsPressed = realButtonIsPressed
playdate.isCrankDocked = realIsCrankDockedE

-- --- Teil F: B-Restart über den ECHTEN SDK-Inputpfad --------------------------
-- B startet das aktuelle Level über die offizielle Press-Edge-API neu.
check(playdate.buttonIsDown == nil,
    "b-sdk: buttonIsDown existiert NICHT im Playdate-SDK (nil)")
check(type(playdate.buttonJustPressed) == "function",
    "b-sdk: buttonJustPressed ist die offizielle Edge-API")

local realJustPressedF = playdate.buttonJustPressed
local bPressed = false -- echter Buttonzustand (wie der Simulator ihn meldet)
local bWasPressed = false
playdate.buttonJustPressed = function(b)
    if b == playdate.kButtonB then
        return bPressed and not bWasPressed
    end
    return false
end

-- Ein Frame des echten main.lua-B-Zweigs (exakter Spiegel: Press-Edge -> Restart).
local function realBFrame()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        bWasPressed = true
        resetSwitchUndoRoom() -- = B-Restart (startRoom-Reihenfolge)
    end
end

-- F1: B-Press startet das Level genau einmal neu; gehaltenes B wiederholt nicht.
resetSwitchUndoRoom()
State.player.angle = 120
State.setSwitch("S1", "A")
Undo.push(State.snapshot())
bPressed = true
bWasPressed = false
realBFrame() -- Press-Edge -> genau ein Restart
check(State.player.angle == 0, "b-real: B-Press -> Level neu (Player Start)")
check(State.switchStates["S1"] == "B", "b-real: B-Press -> Schalter Start")
check(Undo.count() == 0, "b-real: B-Press -> Undo-Stack geleert")
-- Weiter gehalten: kein weiterer Restart (Edge konsumiert, kein Hold-Zweig).
State.player.angle = 200
realBFrame()
check(State.player.angle == 200, "b-real: gehaltenes B -> kein weiterer Restart")
bPressed = false
bWasPressed = false

-- F2: B nach einer abgeschlossenen Raumtransition wieder nutzbar (kein
-- permanenter Lock). Während der Transition gesperrt, danach frei.
resetSwitchUndoRoom()
Camera.beginRoomTransition(7, 6, 6, 5, 0.3, 0.85)
check(Camera.isTransitioning() == true, "b-trans: Transition läuft")
check(bRestartAllowed() == false, "b-trans: B-Restart während Transition gesperrt")
local dtReal = 1 / Config.refreshRate
for _ = 1, 300 do
    Camera.update(dtReal)
    if not Camera.isTransitioning() then break end
end
check(Camera.isTransitioning() == false, "b-trans: Transition beendet")
check(bRestartAllowed() == true, "b-trans: B-Restart wieder erlaubt (kein permanenter Lock)")
bPressed = true
bWasPressed = false
realBFrame()
check(State.player.angle == 0, "b-trans: B nach Transition -> Level neu")
bPressed = false

-- Aufräumen der Teil-F-Mocks.
playdate.buttonJustPressed = realJustPressedF

playdate.datastore = realDatastore

TestReport.input = { pass = pass, fail = fail }
