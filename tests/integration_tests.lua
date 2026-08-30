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

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-6)
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

-- --- Integrationstest 5: Gate (Kernbrücke) ------------------------------
-- Seit dem Center-Bridge-Fix ist das Gate eine NORMALE Brücke zum Mittelpunkt:
-- A startet einen Kernbrücken-Transit (crossing, roomComplete=false); der
-- Raumabschluss folgt erst NACH dem Transit/Landing (main.lua, wasCenter).
do
    setup(makeGateRoom()) -- Gate T@0 auf inner, kein Baby -> Solo-Center-Transit
    local result = Room.tryUseConnection()
    check(result.used == true and result.kind == "gate", "int5: Gate genutzt")
    check(result.roomComplete == false, "int5: roomComplete erst nach Transit")
    check(result.crossing == true, "int5: Kernbrücken-Transit gestartet")
    check(Bridge.isCrossing() == true, "int5: Bridge-Transit aktiv")
    check(State.player.angle == 0, "int5: Snap auf Brückenachse 0")
    local completed, wasShared, babyLanded, wasCenter = Bridge.update(Config.bridgeAnimDuration + 0.001)
    check(completed == true and wasCenter == true, "int5: Transit abgeschlossen (Center)")
    check(State.room.name == "Gate", "int5: State.room unverändert")
    check(State.player.ring == "inner", "int5: Ring bleibt Gate-Ring (kein Center-Ring)")
    check(State.player.angle == 0, "int5: Winkel auf Achse")
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
    check(r2.roomComplete == false and r2.crossing == true,
        "int8: Kernbrücken-Transit (Abschluss nach Transit)")
    local c2, _, _, center2 = Bridge.update(Config.bridgeAnimDuration + 0.001)
    check(c2 == true and center2 == true, "int8: Center-Transit abgeschlossen")
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
    -- Raum 1 (Einstieg): freie Brücke B1@90 von Anfang an aktiv. Der Player
    -- schiebt das Baby zur Brücke; der Baby-Schub erzeugt genau 1 Undo-
    -- Snapshot (der Raum hat keine Schalter).
    Room.movePlayer(90) -- 0 -> 90 (B1@90 frei aktiv), Baby wird mitgeschoben
    check(State.elementStates["B1"] == true, "rwechsel1: Raum-1-B1 frei aktiv")
    check(Undo.count() == 1, "rwechsel1: 1 Undo in Raum 1 (Baby-Schub)")
    -- DockAssist aktivieren (Ziel B1@90) und Bridge-Transit starten. Das Baby
    -- wird aus dem Dockbereich geholt, damit der Solo-Transit/Assist klar läuft.
    State.player.angle = 87
    State.baby.angle = 200
    Room.updateDockAssist()
    check(Room.isDockAssisting() == true, "rwechsel1: Assistenz aktiv vor Wechsel")
    State.player.angle = 90
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
    check(State.room == Levels[2] and State.room.name == "Richtung entscheidet", "rwechsel1: State.room = Raum 2")
    check(State.player.ring == Levels[2].start.ring and State.player.angle == Levels[2].start.angle, "rwechsel1: Spielerstart = Raum 2")
    -- Raum 2: S1 auf Initialzustand (kein Leak aus Raum 1), B1/T frei aktiv.
    check(State.switchStates["S1"] == "B", "rwechsel1: Raum-2-S1 = Initial (kein Leak aus Raum 1)")
    check(State.elementStates["B1"] == true, "rwechsel1: B1 frei aktiv (Raum 2)")
    check(State.elementStates["T"] == true, "rwechsel1: Gate T frei aktiv (Raum 2)")
    -- Baby ist ab Level 1 dabei: Raum 2 hat eine EIGENE Baby-Definition und
    -- startet sie frisch (kein Carry-Leak aus Raum 1; Startlaut Leveldaten).
    check(State.baby ~= nil and State.baby.ring == Levels[2].baby.start.ring
        and math.abs(State.baby.angle - Levels[2].baby.start.angle) < 0.01,
        "rwechsel1: Baby in Raum 2 (eigene Definition outer@45)")
    check(Undo.count() == 0, "rwechsel1: Undo leer")
    check(Bridge.isCrossing() == false, "rwechsel1: kein Transit")
    check(Room.isDockAssisting() == false, "rwechsel1: keine Assistenz")
    -- Shutter-Runtime aus Raum 2: D1 vorhanden und geschlossen (S1=B, kein
    -- Leak-Konflikt mit dem schalterfreien Raum 1).
    check(Room.shutters["D1"] ~= nil and Room.shutters["D1"].collisionActive == true,
        "rwechsel1: Raum-2-Shutter D1 vorhanden/geschlossen")
end

-- --- Integrationstest 10: Raumwechsel-Reset-Semantik 2 -> 3 ---------------
do
    -- Ausgangsraum für den Leak-Check: Level 2 ist der Doppelschalter-Raum
    -- OHNE Baby; der Carry-Contract braucht eine Baby-Quelle, daher der lokale
    -- synthetische Baby-Raum (B0 frei, Gate frei).
    local fromRoom = {
        name = "BabyIntro",
        rings = { outer = 6, inner = 5 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 60 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
    State.init(fromRoom)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    -- Quell-Zustand herstellen, der sich klar von Raum 3 unterscheidet:
    -- Player + Baby auf inner (Begleiter), Undo gefüllt. Das Gate T ist frei
    -- (kein Ablageziel mehr); der gemeinsame Ausgang prüft die Baby-Position.
    State.player.ring = "inner"
    State.player.angle = 292
    State.baby.ring = "inner"
    State.baby.angle = 300
    check(State.elementStates["T"] == true, "rwechsel2: Quell-T frei aktiv (Begleiter-Regel)")
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
    check(State.room == Levels[3] and State.room.name == "Wache halten", "rwechsel2: State.room = Raum 3")
    -- Raum 3 hat eine EIGENE Baby-Definition: das Baby startet laut Leveldaten
    -- (äußerer Ring); die Carry-Semantik greift nur in Räumen ohne Definition.
    check(State.baby ~= nil and State.baby.ring == Levels[3].start.ring,
        "rwechsel2: Baby in Raum 3 vorhanden (eigene Definition)")
    check(State.player.ring == Levels[3].start.ring and State.player.angle == Levels[3].start.angle, "rwechsel2: Spielerstart = Raum 3")
    -- Raum 3 hat EINEN Doppelschalter D (inner@310, Start A).
    check(State.switchStates["D"] == "A" and State.switchStates["S1"] == nil
        and State.switchStates["S2"] == nil, "rwechsel2: D im Zustand A (S1/S2 sind Blenden)")
    check(State.elementStates["T"] == true, "rwechsel2: T frei aktiv (Raum 3, Gate inner)")
    -- Raum 3 (Druckplatte + Doppelschalter): die plattengesteuerte Blende S1
    -- ist geschlossen (P frei), die D-gesteuerte Blende S2 ebenfalls (D=A);
    -- keine D1/D2/D3/B0/B1/B2.
    check(State.elementStates["S1"] == false and State.elementStates["S2"] == false
        and State.elementStates["D1"] == nil and State.elementStates["D2"] == nil
        and State.elementStates["D3"] == nil,
        "rwechsel2: Raum 3 S1+S2 geschlossen, keine D-Shutter")
    check(State.elementStates["A"] == true and State.elementStates["B"] == true
        and State.elementStates["B0"] == nil and State.elementStates["B1"] == nil
        and State.elementStates["B2"] == nil,
        "rwechsel2: A+B frei aktiv (Raum 3, keine B0/B1/B2)")
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

-- --- Integrationstest: LEVEL 2 (Doppelschalter + Shutter + Baby) ------------
-- Richtung bestimmt Zustand: CW über S1@270 -> A (öffnet D1@90, schließt D2
-- inner), CCW -> B (D1 bleibt zu). Startzustand B -> D1 geschlossen: der
-- direkte CW-Weg zur freien Brücke B1@90 ist blockiert (der Dockbereich liegt
-- im Shutter-Bogen). Lösung: CCW herum, S1 aus CCW-Richtung (B = falsch, D1
-- bleibt zu), zurück aus CW-Richtung (A = richtig, D1 öffnet), Baby durch D1
-- zur Brücke schieben, GEMEINSAMER Transit, kurzer Schub zum Tor T@135 (inner).
do
    State.init(Levels[2])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    check(State.switchStates["S1"] == "B", "lvl2: S1 initial B (D1 zu)")
    check(State.elementStates["D1"] == false, "lvl2: D1 geschlossen (Start)")
    check(State.elementStates["B1"] == true and State.elementStates["T"] == true, "lvl2: B1+T frei aktiv")
    check(State.baby ~= nil and State.baby.ring == "outer"
        and math.abs(State.baby.angle - 45) < 0.01, "lvl2: Baby outer@45")
    -- 1) CW direkt: der Player schiebt das Baby, beide prallen an die
    --    geschlossene Blende D1@90 (Bogen [77,103]); die Brücke ist trotz
    --    freier Aktivität NICHT andockbar (Dockbereich im Bogen).
    local _, r1 = Room.movePlayer(90)
    check(r1.blocked == true, "lvl2: CW blockiert (D1 zu, Baby davor)")
    check(State.player.angle < 77, "lvl2: Player stoppt vor D1 (77)")
    check(Bridge.isUsable(State.room.bridges[1], State.player.angle) == false,
        "lvl2: B1 nicht andockbar, solange D1 zu ist")
    -- 2) CCW herum auf die S1-Seite (S1@270 CCW überquert): -> B (kein
    --    Wechsel, D1 bleibt zu — falsche Richtung).
    local _, r2 = Room.movePlayer(-180) -- ~68 -> ~248 (CCW über S1@270)
    check(r2.blocked == false, "lvl2: CCW-Umweg läuft")
    check(State.player.angle > 180, "lvl2: Player nach CCW-Umweg auf S1-Seite")
    check(State.switchStates["S1"] == "B", "lvl2: CCW -> B (kein Wechsel, D1 bleibt zu)")
    check(State.elementStates["D1"] == false, "lvl2: D1 bleibt geschlossen (falsche Richtung)")
    -- 3) Zurück über S1 aus CW-Richtung -> A: D1 öffnet (sichtbarer Wechsel),
    --    D2 inner schließt (Rückwirkung auf beiden Ringen).
    local _, r3 = Room.movePlayer(36) -- ~248 -> ~284, über S1@270 CW
    check(State.switchStates["S1"] == "A", "lvl2: CW -> A (richtige Richtung)")
    check(State.elementStates["D1"] == true, "lvl2: D1 öffnet (Ursache-Wirkung sofort)")
    check(State.elementStates["D2"] == false, "lvl2: D2 inner schließt (S1=A)")
    -- 4) Am Brückendock positionieren (Baby mit) und GEMEINSAM transitieren —
    --    der eigentliche Schub durch die offene D1 ist in room3 abgedeckt.
    State.player.angle = 90
    State.baby.angle = 90
    local rB = Room.tryUseConnection()
    check(rB.used and rB.kind == "sharedBridge", "lvl2: A -> GEMEINSAMER Transit (Baby mit)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and State.baby.ring == "inner",
        "lvl2: Player+Baby auf inner nach Transit")
    -- 5) Kurzer Schub zum Tor T@135 (inner, frei, Baby dabei) -> Abschluss.
    Room.movePlayer(50) -- inner ~90 -> ~140, Baby mit
    check(Gate.isUsable(State.room.gate, "inner", State.player.angle) == true,
        "lvl2: Tor T@135 nutzbar (Player UND Baby)")
    local rG = Room.tryUseConnection()
    check(rG.used and rG.kind == "gate" and rG.crossing == true and rG.roomComplete == false,
        "lvl2: Tor -> Kernbrücken-Transit")
    local ldone, lshared, _, lcenter = Bridge.update(0.5)
    check(ldone == true and lshared == true and lcenter == true,
        "lvl2: gemeinsamer Center-Transit abgeschlossen (Level 2 fertig)")
end

-- --- Integrationstest 11: Progression-Contract Level 1 -> 2 -----------------
-- Simuliert exakt die main.lua-Sequenz beim Abschluss von Level 1 (Gate):
-- nextIndex = currentRoomIndex + 1 (GENAU EIN Levelwechsel), dann der
-- Raumwechsel (Reveal -> startRoom(nextIndex) + Winkel-Übernahme). Verifiziert:
-- (a) exakt Level 2 wird geladen (kein Überspringen/kein späterer Raum),
-- (b) der Levelindex wird nur EINMAL erhöht, (c) Level 2 ist nach dem Laden
-- NICHT automatisch abgeschlossen (kein sofortiger Weiterwechsel zu Level 3).
do
    -- Level 1 vollständig spielen: Bewegung -> Baby mit zur Brücke B1@90 ->
    -- GEMEINSAMER Transit -> inner -> Schub zum Tor T@135.
    State.init(Levels[1])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[1].rings.outer)
    Room.movePlayer(90) -- outer 0 -> 90 (B1), Baby wird mitgeschoben
    local rBridge = Room.tryUseConnection()
    check(rBridge.used and rBridge.kind == "sharedBridge", "prog: L1 GEMEINSAMER Transit (Baby mit)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and State.baby.ring == "inner", "prog: L1 auf inner (mit Baby)")
    Room.movePlayer(50) -- inner ~90 -> ~140 (Tor T@135), Baby wird mitgeschoben
    check(Gate.isUsable(Levels[1].gate, "inner", State.player.angle) == true,
        "prog: L1 Tor T@135 nutzbar (Player UND Baby)")
    local rGate = Room.tryUseConnection()
    check(rGate.used and rGate.kind == "gate" and rGate.crossing == true and rGate.roomComplete == false,
        "prog: L1 Tor -> Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "prog: L1 gemeinsamer Center-Transit abgeschlossen")
    -- handleConnectionResult-Äquivalent: nextIndex = currentRoomIndex + 1.
    local currentIndex = 1
    local nextIndex = currentIndex + 1
    check(nextIndex == 2, "prog: nextIndex = 2 (exakt EIN Levelwechsel)")
    check(Levels[nextIndex] == Levels[2] and Levels[nextIndex].name == "Richtung entscheidet",
        "prog: exakt Level 2 wird geladen (kein Überspringen)")
    -- Transition-Reveal: startRoom(Level 2). Der Winkel wird per
    -- applyTransitionStartAngle auf den Level-1-Ausgang gesetzt; der Ring
    -- kommt aus dem Levelstart (outer). Kein Teleport, kein Wandern.
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(Levels[nextIndex])
    Undo.clear()
    Room.init()
    Camera.init(Levels[nextIndex].rings.outer)
    check(State.room == Levels[2], "prog: State.room = exakt Level 2")
    check(State.player.ring == "outer", "prog: Level 2 Player auf outer")
    -- KEIN Auto-Complete: an der Level-2-Startposition ist kein Ausgang
    -- nutzbar (Tor T@135 ist inner, Player startet outer; Brücke B1@90 ist
    -- entfernt) — keine sofortige Completion.
    local resStart = Room.tryUseConnection()
    check(resStart.used == false, "prog: Level 2 Start -> kein sofortiger Abschluss")
    check(resStart.roomComplete == false, "prog: Level 2 Start -> kein roomComplete")
    -- Level 2 bleibt aktiv (mehrere Frames „stehen lassen", keine automatische
    -- Progression zu Level 3).
    local stillL2 = true
    for _ = 1, 120 do
        if State.room ~= Levels[2] then
            stillL2 = false
        end
    end
    check(stillL2, "prog: Level 2 bleibt aktiv (kein automatischer Wechsel)")
end

-- --- Integrationstest: ROOM TRANSITION erhält die TATSÄCHLICHE Position ----
-- Beim normalen Levelwechsel (Room-Transition) behalten Player und Baby ihre
-- tatsächliche Position (Ring + Winkel + relative Reihenfolge) — der neue
-- Raum wird um den tatsächlichen Entry aufgebaut, NICHT um den Levelstart.
-- Simuliert exakt die main.lua-Logik: handleConnectionResult erfasst die
-- Ausgangspositionen (captureFigures), am Reveal lädt startRoom den neuen
-- Raum (State.init = Levelstart) und applyTransitionPosition übernimmt dann
-- Ring + Winkel aus der Transition (RoomTransition.ringNameForRoom).
do
    local function simulateTransition(fromIdx, toIdx, carry, playerAngle, babyAngle)
        local from = Levels[fromIdx]
        local to = Levels[toIdx]
        State.init(from, carry)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        -- Tatsächliche Ausgangsposition: Abschluss am Tor des Ausgangsraums.
        local gateRing = from.gate.ring or "inner"
        State.player.ring = gateRing
        State.player.angle = playerAngle
        State.baby.ring = gateRing
        State.baby.angle = babyAngle
        local function ringNum(rd, name) return rd.rings[name] end
        local pf = { ring = ringNum(from, State.player.ring), angle = State.player.angle }
        local pt = { ring = ringNum(to, to.start.ring), angle = to.start.angle }
        local bf = { ring = ringNum(from, State.baby.ring), angle = State.baby.angle }
        local bt
        if to.baby then
            bt = { ring = ringNum(to, to.baby.start.ring), angle = to.baby.start.angle }
        else
            bt = { ring = ringNum(to, to.start.ring), angle = Geometry.norm(to.start.angle - Config.babyCompanionOffsetDeg) }
        end
        RoomTransition.start(toIdx)
        RoomTransition.captureFigures(pf, pt, bf, bt)
        -- Reveal-Punkt: neuen Raum laden (startRoom-Äquivalent: State.init
        -- setzt den Levelstart) und danach die Transition-Position übernehmen.
        State.init(to, carry)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        -- applyTransitionPosition-Äquivalent (Ring + Winkel aus der Transition).
        local pName = RoomTransition.ringNameForRoom(pf.ring, State.room)
        if pName then State.player.ring = pName end
        State.player.angle = pf.angle
        if State.baby and bf then
            local bName = RoomTransition.ringNameForRoom(bf.ring, State.room)
            if bName then State.baby.ring = bName end
            State.baby.angle = bf.angle
        end
    end

    -- L1 -> L2: Player verlässt L1 am Tor inner@135, Baby inner@145.
    do
        simulateTransition(1, 2, true, 135, 145)
        check(State.room == Levels[2], "transpos-12: neuer Raum = Level 2")
        check(State.player.ring == "outer" and approx(State.player.angle, 135),
            "transpos-12: Player behält tatsächlichen Winkel (outer@135)")
        check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 145),
            "transpos-12: Baby behält tatsächlichen Winkel (outer@145)")
        check(State.player.angle < State.baby.angle,
            "transpos-12: Reihenfolge erhalten (Player -> Baby, CW)")
    end

    -- L2 -> L3: Player verlässt L2 am Tor inner@135, Baby inner@145.
    do
        simulateTransition(2, 3, true, 135, 145)
        check(State.room == Levels[3], "transpos-23: neuer Raum = Level 3")
        check(State.player.ring == "outer" and approx(State.player.angle, 135),
            "transpos-23: Player behält tatsächlichen Winkel (outer@135)")
        check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 145),
            "transpos-23: Baby behält tatsächlichen Winkel (outer@145)")
        check(State.player.angle < State.baby.angle,
            "transpos-23: Reihenfolge erhalten (Player -> Baby, CW)")
    end

    -- Direkter Start (NEW GAME / CONTINUE frisch): der LEVELSTART gilt.
    do
        State.init(Levels[2], false)
        check(State.player.ring == Levels[2].start.ring and State.player.angle == Levels[2].start.angle,
            "direct-start: Player nutzt definierten Levelstart (outer@0)")
        check(State.baby ~= nil and State.baby.ring == Levels[2].baby.start.ring
            and State.baby.angle == Levels[2].baby.start.angle,
            "direct-start: Baby nutzt definierten Levelstart (outer@45)")
    end
end

-- --- Integrationstest: BABY-WINKEL-PERSISTENZ (Teil A Bugfix) --------------
-- Reproduziert EXAKT den main.lua-Fluss des natürlichen Levelwechsels
-- (Kernbrücken-Abschluss -> RoomTransition -> startRoom -> applyTransition-
-- Position). Regeln:
--   A1/A2: transitionEntry speichert playerAngle und babyAngle GETRENNT;
--          niemals babyAngle == playerAngle.
--   A5:    Beim gemeinsamen Center-Transit landet das Baby (wie bei normalen
--          Shared-Bridges) einen Bogen (babyBridgeExitOffset) VOR dem Player
--          auf der Gate-Brückenachse; dieser EIGENE Winkel wird beim Handoff
--          erhalten (nicht der Mittelpunkt, nicht der Player-Winkel, nicht
--          der Levelstart-Spawn).
--   A8:    Der Mechanismus erhält beliebige tatsächliche Winkel exakt
--          (BABY_ANGLE_BEFORE == BABY_ANGLE_AFTER) und die relative
--          Reihenfolge (Player -> Baby) bleibt erhalten.
do
    local function ringNum(rd, name) return rd.rings[name] end

    -- A5: L3 -> L4 über die Kernbrücke. Beide Figuren beenden den gemeinsamen
    -- Transit: Player auf der Achse (Gate-Winkel), Baby VOR dem Player
    -- (Gate-Winkel + babyBridgeExitOffset). Der Handoff übernimmt beide
    -- getrennt.
    do
        State.init(Levels[3])
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        local gateAngle = Levels[3].gate.angle -- 135
        -- Abschluss der gemeinsamen Kernbrücke (Bridge.update-Zentrum): Player
        -- auf der Achse, Baby einen Bogen voraus (Fixed-Winkel-Handoff).
        State.player.ring = Levels[3].gate.ring or "inner"
        State.player.angle = gateAngle
        State.baby.ring = Levels[3].gate.ring or "inner"
        State.baby.angle = Geometry.norm(gateAngle + Config.babyBridgeExitOffset)
        -- handleConnectionResult-Äquivalent (fromCenterTransit=true): getrennte
        -- transitionEntry-Winkel aus den TATSÄCHLICHEN State-Winkeln.
        local pf = { ring = "center", angle = State.player.angle }
        local pt = { ring = ringNum(Levels[4], Levels[4].start.ring), angle = Levels[4].start.angle }
        local bf = { ring = "center", angle = State.baby.angle }
        local bt = { ring = ringNum(Levels[4], Levels[4].baby.start.ring), angle = Levels[4].baby.start.angle }
        RoomTransition.start(4)
        RoomTransition.captureFigures(pf, pt, bf, bt)
        -- Reveal-Punkt: startRoom(4) + applyTransitionPosition.
        State.init(Levels[4], true)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        local pName = RoomTransition.ringNameForRoom(pf.ring, State.room)
        if pName then State.player.ring = pName end
        State.player.angle = pf.angle
        if State.baby and bf then
            local bName = RoomTransition.ringNameForRoom(bf.ring, State.room)
            if bName then State.baby.ring = bName end
            State.baby.angle = bf.angle
        end
        check(State.room == Levels[4], "babyfix-a5: L3 -> L4 lädt Level 4")
        check(approx(State.player.angle, gateAngle, 1e-6) and State.player.ring == "outer",
            "babyfix-a5: Player auf Achse outer@135 (kein Spawnwinkel)")
        local expectBaby = Geometry.norm(gateAngle + Config.babyBridgeExitOffset)
        check(State.baby ~= nil and approx(State.baby.angle, expectBaby, 1e-6)
            and State.baby.ring == "outer",
            "babyfix-a5: Baby behält EIGENEN Winkel outer@" .. tostring(expectBaby))
        check(State.player.angle < State.baby.angle,
            "babyfix-a5: Reihenfolge erhalten (Player -> Baby, CW)")
        check(State.player.angle ~= State.baby.angle,
            "babyfix-a5: babyAngle != playerAngle (getrennte Zustände)")
    end

    -- A8: L2 -> L3 mit tatsächlichen Winkeln Player=100, Baby=118.
    do
        State.init(Levels[2], true)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        State.player.ring = Levels[2].gate.ring or "inner"
        State.player.angle = 100
        State.baby.ring = Levels[2].gate.ring or "inner"
        State.baby.angle = 118
        local pf = { ring = ringNum(Levels[2], State.player.ring), angle = State.player.angle }
        local pt = { ring = ringNum(Levels[3], Levels[3].start.ring), angle = Levels[3].start.angle }
        local bf = { ring = ringNum(Levels[2], State.baby.ring), angle = State.baby.angle }
        local bt = { ring = ringNum(Levels[3], Levels[3].baby.start.ring), angle = Levels[3].baby.start.angle }
        RoomTransition.start(3)
        RoomTransition.captureFigures(pf, pt, bf, bt)
        State.init(Levels[3], true)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        local pName = RoomTransition.ringNameForRoom(pf.ring, State.room)
        if pName then State.player.ring = pName end
        State.player.angle = pf.angle
        if State.baby and bf then
            local bName = RoomTransition.ringNameForRoom(bf.ring, State.room)
            if bName then State.baby.ring = bName end
            State.baby.angle = bf.angle
        end
        check(State.room == Levels[3], "babyfix-100-118: L2 -> L3 lädt Level 3")
        check(approx(State.player.angle, 100, 1e-6),
            "babyfix-100-118: Player behält 100°")
        check(State.baby ~= nil and approx(State.baby.angle, 118, 1e-6),
            "babyfix-100-118: Baby behält 118° (BABY_ANGLE_BEFORE == BABY_ANGLE_AFTER)")
        check(State.player.angle < State.baby.angle,
            "babyfix-100-118: Reihenfolge erhalten (Player 100 < Baby 118)")
    end

    -- A8: L3 -> L4 mit tatsächlichen Winkeln Player=247, Baby=231 (gespiegelte
    -- Reihenfolge: Baby liegt hier CCW/links vom Player — exakt erhalten).
    do
        State.init(Levels[3], true)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        State.player.ring = Levels[3].gate.ring or "inner"
        State.player.angle = 247
        State.baby.ring = Levels[3].gate.ring or "inner"
        State.baby.angle = 231
        local pf = { ring = ringNum(Levels[3], State.player.ring), angle = State.player.angle }
        local pt = { ring = ringNum(Levels[4], Levels[4].start.ring), angle = Levels[4].start.angle }
        local bf = { ring = ringNum(Levels[3], State.baby.ring), angle = State.baby.angle }
        local bt = { ring = ringNum(Levels[4], Levels[4].baby.start.ring), angle = Levels[4].baby.start.angle }
        RoomTransition.start(4)
        RoomTransition.captureFigures(pf, pt, bf, bt)
        State.init(Levels[4], true)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Baby.resetTransit()
        Room.resetDockAssist()
        local pName = RoomTransition.ringNameForRoom(pf.ring, State.room)
        if pName then State.player.ring = pName end
        State.player.angle = pf.angle
        if State.baby and bf then
            local bName = RoomTransition.ringNameForRoom(bf.ring, State.room)
            if bName then State.baby.ring = bName end
            State.baby.angle = bf.angle
        end
        check(State.room == Levels[4], "babyfix-247-231: L3 -> L4 lädt Level 4")
        check(approx(State.player.angle, 247, 1e-6),
            "babyfix-247-231: Player behält 247°")
        check(State.baby ~= nil and approx(State.baby.angle, 231, 1e-6),
            "babyfix-247-231: Baby behält 231° (BABY_ANGLE_BEFORE == BABY_ANGLE_AFTER)")
        check(State.player.angle > State.baby.angle,
            "babyfix-247-231: Reihenfolge erhalten (Player 247 > Baby 231)")
        check(State.player.angle ~= State.baby.angle,
            "babyfix-247-231: babyAngle != playerAngle (getrennt)")
    end
end

TestReport.integration = { pass = pass, fail = fail }
