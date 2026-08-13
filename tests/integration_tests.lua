-- Integrationstests für die in main.lua verdrahtete Systemsemantik
-- (Schritt 5.4). Testet NICHT Hardware-Buttons, sondern die API-Ebene mit
-- denselben Modulen: Player -> Room.movePlayer -> State/Undo -> Bridge/Gate.
-- Verwendet ausschließlich synthetische Raumdaten.
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/player, world/room, world/bridge und world/gate per import geladen
-- wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.integration gesammelt; die
-- aggregierte RESULT-Zeile schreibt der Test-Runner.

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

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
end

-- Konfiguration des Vertical Slices (Punkt 37).
check(Config.refreshRate == 50, "config: refreshRate 50")
check(Config.crankRatio == 0.5, "config: crankRatio 0.5")
check(Config.dpadSpeed == 90, "config: dpadSpeed 90")

-- Raum für die Player->Sweep-Pipeline: S1 steuert Brücke B1 und Blende D1.
local function makePipelineRoom()
    return {
        name = "Pipeline",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=200 },
        },
        bridges = {
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=270, free=true },
    }
end

-- Raum für Ring-Scoping nach Brückentransit: S1 outer, S2 inner; D1 outer
-- (im Startzustand geschlossen), D2 inner.
local function makeRingScopeRoom()
    return {
        name = "RingScope",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=180, symbol=1, onA="D1", onB="B1", state="B" },
            { id="S2", ring="inner", angle=135, symbol=2, onA="D2", onB="B2", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=300 },
            { id="D2", ring="inner", angle=300 },
        },
        bridges = {
            { id="B0", angle=90,  free=true  },
            { id="B1", angle=270, free=false },
            { id="B2", angle=45,  free=false },
        },
        gate = { id="T", angle=270, free=true },
    }
end

-- Raum für die Gate-Pipeline.
local function makeGateRoom()
    return {
        name = "Gate",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 0 },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=180, free=true },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- --- Integrationstest 1: komplette Movement-Pipeline --------------------
do
    setup(makePipelineRoom())
    local delta = Player.computeDesiredDelta(100, false, false, 0.02) -- 100*0.5 = 50
    local actual = Room.movePlayer(delta) -- 10 -> 60, S1 vollständig (Austritt 52)
    check(actual == 50, "int1: actual == wantedDelta (50)")
    check(State.player.angle == 60, "int1: Winkel 60")
    check(State.switchStates["S1"] == "A", "int1: Schalter im Sweep gesetzt")
end

-- --- Integrationstest 2: Schalter + Undo --------------------------------
do
    setup(makePipelineRoom())
    local delta = Player.computeDesiredDelta(100, false, false, 0.02) -- 50
    Room.movePlayer(delta) -- 10 -> 60, S1 -> A, 1 Undo
    check(State.switchStates["S1"] == "A", "int2: S1 A vor Undo")
    check(Undo.count() == 1, "int2: genau 1 Undo")
    -- B-Semantik: Undo.undo() + physische Synchronisierung
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "int2: S1 restauriert")
    check(State.elementStates["B1"] == false, "int2: B1 eingefahren")
    check(State.elementStates["D1"] == true, "int2: D1 offen")
    check(State.player.ring == "outer", "int2: Ring restauriert")
    check(State.player.angle == 10, "int2: Winkel restauriert")
    check(Room.shutters["D1"].collisionActive == false, "int2: D1 nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "int2: D1 kein pendingClose")
end

-- --- Integrationstest 3: Movement -> Brücke -----------------------------
do
    setup(makePipelineRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, B1 aktiv
    local result = Room.tryUseConnection() -- B1 bei 90 dockbar -> Transit
    check(result.used == true and result.kind == "bridge", "int3: Brücke genutzt")
    Bridge.update(Config.bridgeAnimDuration + 0.001) -- Transit abschließen
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "int3: Ringwechsel auf inner")
    check(State.player.angle == 90, "int3: Snap auf Brückenachse 90")
end

-- --- Integrationstest 4: Brücke -> Bewegung auf Zielring ----------------
do
    setup(makeRingScopeRoom())
    Room.movePlayer(80) -- outer 10 -> 90, B0 erreichbar
    local result = Room.tryUseConnection() -- B0 -> inner@90 (Transit)
    check(result.used == true, "int4: Transit auf inner")
    Bridge.update(Config.bridgeAnimDuration + 0.001) -- Abschluss
    Room.syncPhysicalShutters()
    local actual = Room.movePlayer(150) -- inner 90 -> 240, kreuzt S2 (inner)
    check(actual == 150, "int4: Bewegung auf Zielring nicht blockiert (actual 150)")
    check(State.switchStates["S2"] == "A", "int4: innerer Schalter S2 gesetzt")
    check(State.switchStates["S1"] == "B", "int4: äußerer Schalter S1 unberührt")
    check(State.player.angle == 240, "int4: Ende 240")
end

-- --- Integrationstest 5: Gate -------------------------------------------
do
    setup(makeGateRoom())
    local result = Room.tryUseConnection()
    check(result.used == true and result.kind == "gate", "int5: Gate genutzt")
    check(result.roomComplete == true, "int5: roomComplete true")
    check(State.room.name == "Gate", "int5: State.room unverändert")
    check(State.player.ring == "inner", "int5: Ring unverändert")
    check(State.player.angle == 0, "int5: Winkel unverändert")
    check(Undo.count() == 0, "int5: kein Undo")
end

-- --- Integrationstest 6: vorhandener Undo + Brücke + B-Semantik ---------
do
    setup(makePipelineRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, 1 Undo, B1 aktiv
    check(Undo.count() == 1, "int6: 1 Undo nach Schalterhandlung")
    Room.tryUseConnection() -- B1 -> inner (Transit)
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "int6: nach Brücke auf inner")
    check(Undo.count() == 1, "int6: Brücke erzeugt kein neues Undo")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "int6: S1 restauriert")
    check(State.elementStates["B1"] == false, "int6: B1 eingefahren")
    check(State.elementStates["D1"] == true, "int6: D1 offen")
    check(State.player.ring == "outer", "int6: Ring zurück auf outer")
    check(State.player.angle == 10, "int6: Winkel vor Schalterhandlung (10)")
    check(Room.shutters["D1"].collisionActive == false, "int6: D1 nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "int6: D1 kein pendingClose")
end

-- --- Integrationstest 7: keine doppelte Bewegungswahrheit ---------------
do
    setup(makePipelineRoom())
    Room.movePlayer(Player.computeDesiredDelta(100, false, false, 0.02))
    Undo.undo()
    Room.syncPhysicalShutters()
    check(type(State.player.ring) == "string" and type(State.player.angle) == "number", "int7: State.player ist die Position")
    check(Player.ring == nil and Player.angle == nil, "int7: Player hält keine eigene Position")
    check(Bridge.ring == nil and Bridge.angle == nil, "int7: Bridge hält keine eigene Position")
    check(Gate.ring == nil and Gate.angle == nil, "int7: Gate hält keine eigene Position")
    check(Room.player == nil, "int7: Room hält keine zweite Spielerposition")
end

-- --- Integrationstest 8: Brücke -> inner -> Gate (Raumende) --------------
-- Pflicht-Test 11: kompletter Fluss über 7.1 (Brückentransit) zu 7.2 (Gate).
do
    local room = {
        name = "BridgeGate",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=200 },
        },
        bridges = {
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
    setup(room)
    Room.movePlayer(80) -- outer 10 -> 90, S1 -> A, B1 aktiv (1 Undo)
    check(State.switchStates["S1"] == "A", "int8: S1 A vor Brücke")
    local r1 = Room.tryUseConnection() -- B1 -> inner (Transit)
    check(r1.used == true and r1.kind == "bridge", "int8: Brücke genutzt")
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "int8: nach Brücke auf inner")
    check(State.player.angle == 90, "int8: Winkel 90")
    local actual = Room.movePlayer(90) -- inner 90 -> 180 (Gate)
    check(actual == 90, "int8: Bewegung zum Gate ungehindert (actual 90)")
    check(State.player.angle == 180, "int8: an Gate-Position 180")
    local r2 = Room.tryUseConnection()
    check(r2.used == true and r2.kind == "gate", "int8: Gate genutzt")
    check(r2.id == "T", "int8: id T")
    check(r2.roomComplete == true, "int8: roomComplete true")
    check(State.room.name == "BridgeGate", "int8: kein Raumwechsel")
    check(Undo.count() == 1, "int8: Schalter-Undo bleibt (1)")
end

-- --- Integrationstest 9: Raumwechsel-Reset-Semantik 1 -> 2 -----------------
-- main.lua.startRoom() führt aus: Bridge.resetTransit(); Room.resetDockAssist();
-- State.init(roomData); Undo.clear(); Room.init(). Diese Sequenz wird hier mit
-- echten Leveldaten (Raum 1 -> Raum 2) geprüft: kein State-Leak über die
-- Raumgrenze (Pflicht-Tests 4-9 und 13). data/levels und ui/render werden vom
-- Test-Runner vor den Testdateien importiert.
do
    State.init(Levels[1])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    -- Raum 1 spielen: S1 -> A (B1 aktiv, D1 geschlossen), 1 Undo.
    Room.movePlayer(100) -- 0 -> 100, S1 -> A
    check(State.switchStates["S1"] == "A", "rwechsel1: Raum-1-S1 auf A")
    check(Undo.count() == 1, "rwechsel1: 1 Undo in Raum 1")
    check(State.elementStates["B1"] == true, "rwechsel1: Raum-1-B1 aktiv")
    -- DockAssist aktivieren (Ziel S1@90) und Bridge-Transit starten (B1@270).
    State.player.angle = 87
    Room.updateDockAssist()
    check(Room.isDockAssisting() == true, "rwechsel1: Assistenz aktiv vor Wechsel")
    State.player.angle = 270
    local r = Room.tryUseConnection()
    check(r.used == true and r.crossing == true, "rwechsel1: Transit aktiv vor Wechsel")
    check(Bridge.isCrossing() == true, "rwechsel1: crossing true vor Wechsel")
    -- startRoom-Äquivalent: Raum 1 -> Raum 2.
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(Levels[2])
    Undo.clear()
    Room.init()
    check(State.room == Levels[2] and State.room.name == "Nicht allein", "rwechsel1: State.room = Raum 2")
    check(State.player.ring == Levels[2].start.ring and State.player.angle == Levels[2].start.angle, "rwechsel1: Spielerstart = Raum 2")
    -- Raum 2 hat keine Schalter: switchStates leer (kein Leak aus Raum 1).
    check(next(State.switchStates) == nil, "rwechsel1: keine Schalter in Raum 2")
    check(State.elementStates["B0"] == true, "rwechsel1: B0 frei aktiv (Raum 2)")
    check(State.elementStates["T"] == true, "rwechsel1: Gate T frei aktiv (Raum 2)")
    -- Baby frisch initialisiert (kein Leak aus Raum 1).
    check(State.baby ~= nil and State.baby.ring == "outer" and State.baby.angle == 60 and State.baby.settled == false,
        "rwechsel1: Baby frisch outer@60")
    check(Undo.count() == 0, "rwechsel1: Undo leer")
    check(Bridge.isCrossing() == false, "rwechsel1: kein Transit")
    check(Room.isDockAssisting() == false, "rwechsel1: keine Assistenz")
    -- Kein Shutter-Runtime-Leak aus Raum 1 (Raum 2 hat keine Blenden).
    check(Room.shutters["D1"] == nil, "rwechsel1: kein Shutter-Leak (Raum 2 ohne Blenden)")
end

-- --- Integrationstest 10: Raumwechsel-Reset-Semantik 2 -> 3 ---------------
do
    State.init(Levels[2])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    -- Raum-2-Zustand herstellen, der sich klar von Raum 3 unterscheidet:
    -- Player + Baby auf inner (Begleiter), Undo gefüllt. Das Gate T ist frei
    -- (kein Ablageziel mehr); der gemeinsame Ausgang prüft die Baby-Position.
    State.player.ring = "inner"
    State.player.angle = 292
    State.baby.ring = "inner"
    State.baby.angle = 300
    check(State.elementStates["T"] == true, "rwechsel2: Raum-2-T frei aktiv (Begleiter-Regel)")
    Undo.push(State.snapshot())
    check(Undo.count() == 1, "rwechsel2: 1 Undo")
    -- startRoom-Äquivalent: Raum 2 -> Raum 3 MIT Begleiter-Mitnahme
    -- (main.lua übergibt babyCarried=true an State.init).
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(Levels[3], true)
    Undo.clear()
    Room.init()
    check(State.room == Levels[3] and State.room.name == "Der lange Weg", "rwechsel2: State.room = Raum 3")
    -- Begleiter-Mitnahme: das Baby ist im Folge-Raum als Begleiter präsent.
    check(State.baby ~= nil and State.baby.ring == Levels[3].start.ring,
        "rwechsel2: Baby als Begleiter in Raum 3 übernommen")
    check(State.player.ring == Levels[3].start.ring and State.player.angle == Levels[3].start.angle, "rwechsel2: Spielerstart = Raum 3")
    check(State.switchStates["S1"] == "B", "rwechsel2: S1 = Raum-3-Definition (B)")
    check(State.elementStates["T"] == false, "rwechsel2: T eingefahren (Raum 3)")
    check(State.elementStates["D1"] == true, "rwechsel2: D1 offen (Raum 3)")
    check(State.elementStates["B0"] == true, "rwechsel2: B0 frei aktiv (Raum 3)")
    check(Undo.count() == 0, "rwechsel2: Undo leer")
    check(Bridge.isCrossing() == false, "rwechsel2: kein Transit")
    check(Room.isDockAssisting() == false, "rwechsel2: keine Assistenz")
    -- Render nutzt seit Phase 8.1 die Kamera: auf den äußeren Ring setzen.
    Camera.init(State.room.rings.outer)
    local okDraw, drawErr = pcall(Render.drawRoom, false)
    check(okDraw, "rwechsel2: Render Raum 3 fehlerfrei")
    if not okDraw then
        print("RENDER_ERR3: " .. tostring(drawErr))
    end
end

TestReport.integration = { pass = pass, fail = fail }
