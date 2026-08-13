-- Tests für die logische Verbindungs-Interaktion: source/world/bridge.lua
-- (Bridge), source/world/gate.lua (Gate) und Room.tryUseConnection() in
-- source/world/room.lua.
-- Verwendet ausschließlich synthetische Raumdaten; die sechs echten Levels
-- werden nur lesend für die statische Ambiguitätsprüfung herangezogen.
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/room, world/bridge, world/gate und data/levels per import geladen
-- wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.connection gesammelt; die
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
    return math.abs(a - b) <= (tolerance or 1e-9)
end

local function deepCopy(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = deepCopy(v)
        else
            out[k] = v
        end
    end
    return out
end

-- Zwei Tabellen mit boolean/string-Werten identisch?
local function sameValues(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then
            return false
        end
    end
    return true
end

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
end

-- Schließt einen laufenden Bridge-Transit ab (Überbrückung der vollen Dauer)
-- und synchronisiert die physische Welt (G7 nach Ringwechsel).
local function completeTransit()
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    Room.syncPhysicalShutters()
end

-- Freie Brücke B0 bei bridgeAngle; Spieler bei playerRing/playerAngle.
local function makeBridgeRoom(bridgeAngle, playerRing, playerAngle)
    return {
        name = "Bruecke",
        rings = { outer = 7, inner = 6 },
        start = { ring = playerRing, angle = playerAngle },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=bridgeAngle, free=true },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Gesteuerte Brücke B1 (S1=A aktiv), im Startzustand B inaktiv.
local function makeControlledBridgeRoom()
    return {
        name = "GesteuerteBruecke",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=180 },
        },
        bridges = {
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Freies Gate T bei 0°.
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

-- Inaktives Gate T (S1=A -> T inaktiv).
local function makeInactiveGateRoom()
    return {
        name = "GateInaktiv",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 0 },
        switches = {
            { id="S1", ring="inner", angle=45, symbol=1, onA="D1", onB="T", state="A" },
        },
        shutters = {
            { id="D1", ring="inner", angle=180 },
        },
        bridges = {},
        gate = { id="T", angle=0, free=false },
    }
end

-- Für Undo- und Transit-Tests: S1 steuert B1; Spieler startet outer@10.
local function makeTransitRoom()
    return {
        name = "Transit",
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
end

-- G7-Zielring: geschlossene Blende D1 (inner) umfasst die Brückenachse 90°.
local function makeG7TransitRoom()
    return {
        name = "G7Transit",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="A" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90 },
        },
        bridges = {
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Geschlossene Blende D1 auf dem ANDEREN Ring (outer) bei Brückenachse 90°.
local function makeOtherRingRoom()
    return {
        name = "AndererRing",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Zwei aktive Brücken, nur B0 dockbar.
local function makeTwoBridgeRoom()
    return {
        name = "ZweiBruecken",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=90,  free=true },
            { id="B2", angle=200, free=true },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Zwei gleichzeitig dockbare Brücken (Ambiguität, synthetisch absichtlich
-- regelwidrig eng gelegt).
local function makeAmbiguousBridgeRoom()
    return {
        name = "AmbigBruecken",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=90, free=true },
            { id="B2", angle=93, free=true },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Brücke + Gate gleichzeitig dockbar auf inner (Ambiguität).
local function makeAmbiguousGateBridgeRoom()
    return {
        name = "AmbigGateBruecke",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 90 },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=90, free=true },
        },
        gate = { id="T", angle=93, free=true },
    }
end

-- Keine Verbindung in Reichweite.
local function makeDistantRoom()
    return {
        name = "Weit",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {},
        shutters = {},
        bridges = {
            { id="B0", angle=180, free=true },
        },
        gate = { id="T", angle=270, free=true },
    }
end

-- --- Test 1: freie Brücke outer -> inner ---------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    local result = Room.tryUseConnection()
    check(result.used == true, "brücke o->i: used true")
    check(result.kind == "bridge", "brücke o->i: kind bridge")
    check(result.id == "B0", "brücke o->i: id B0")
    check(result.roomComplete == false, "brücke o->i: roomComplete false")
    check(result.crossing == true, "brücke o->i: crossing true")
    check(Bridge.isCrossing() == true, "brücke o->i: Transit aktiv")
    check(State.player.ring == "outer", "brücke o->i: Ring bleibt outer (vor Abschluss)")
    check(State.player.angle == 90, "brücke o->i: Winkel 90")
    completeTransit()
    check(State.player.ring == "inner", "brücke o->i: nach Abschluss Ring inner")
    check(Bridge.isCrossing() == false, "brücke o->i: Transit beendet")
end

-- --- Test 2: freie Brücke inner -> outer ---------------------------------
do
    setup(makeBridgeRoom(90, "inner", 90))
    local result = Room.tryUseConnection()
    check(result.used == true, "brücke i->o: used true")
    check(result.kind == "bridge", "brücke i->o: kind bridge")
    check(State.player.ring == "inner", "brücke i->o: Ring bleibt inner (vor Abschluss)")
    check(State.player.angle == 90, "brücke i->o: Winkel 90")
    completeTransit()
    check(State.player.ring == "outer", "brücke i->o: nach Abschluss Ring outer")
end

-- --- Test 3: Snap auf Brückenachse ---------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 86))
    local result = Room.tryUseConnection()
    check(result.used == true, "snap: used true (86 in Range)")
    check(State.player.angle == 90, "snap: Winkel exakt 90 (nicht 86)")
    check(State.player.ring == "outer", "snap: Ring bleibt outer (vor Abschluss)")
    completeTransit()
    check(State.player.ring == "inner", "snap: nach Abschluss Ring inner")
end

-- --- Test 4: exakt auf dockRange -----------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 78)) -- Differenz 12 -> exakt dockRange (12)
    local result = Room.tryUseConnection()
    check(result.used == true, "grenze inklusiv: 78 bei Range 12 nutzbar")
end

-- --- Test 5: minimal außerhalb -------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 77.999)) -- Differenz 12.001 > dockRange (12)
    local result = Room.tryUseConnection()
    check(result.used == false, "grenze exklusiv: 77.999 nicht nutzbar")
    check(State.player.ring == "outer", "grenze exklusiv: Ring unverändert")
    check(approx(State.player.angle, 77.999), "grenze exklusiv: Winkel unverändert")
end

-- --- Test 5b: Slightly before / after / outside (Bridge-Handling) ---------
do
    setup(makeBridgeRoom(90, "outer", 82)) -- 8° vor dem Dock
    local r1 = Room.tryUseConnection()
    check(r1.used == true, "leicht vorher: 8° vor der Brücke nutzbar")
    completeTransit()
    check(State.player.ring == "inner", "leicht vorher: Transit abgeschlossen")

    setup(makeBridgeRoom(90, "outer", 97)) -- 7° hinter dem Dock
    local r2 = Room.tryUseConnection()
    check(r2.used == true, "leicht nachher: 7° hinter der Brücke nutzbar")
    completeTransit()
    check(State.player.ring == "inner", "leicht nachher: Transit abgeschlossen")

    setup(makeBridgeRoom(90, "outer", 76)) -- 14° außerhalb der Dockzone
    local r3 = Room.tryUseConnection()
    check(r3.used == false, "außerhalb: 14° weg -> kein Bridge-Transit")
    check(State.player.ring == "outer", "außerhalb: Ring unverändert")
end

-- --- Test 6: Wraparound bei 0° -------------------------------------------
do
    setup(makeBridgeRoom(2, "outer", 358))
    local result = Room.tryUseConnection()
    check(result.used == true, "wraparound: 358 zu Brücke 2 nutzbar (Differenz 4)")
    check(State.player.angle == 2, "wraparound: Snap auf 2")
end

-- --- Test 7: inaktive Brücke ---------------------------------------------
do
    setup(makeControlledBridgeRoom()) -- S1=B -> B1 inaktiv
    local result = Room.tryUseConnection()
    check(result.used == false, "inaktiv: used false")
    check(State.player.ring == "outer", "inaktiv: Ring unverändert")
    check(State.player.angle == 90, "inaktiv: Winkel unverändert")
    check(Undo.count() == 0, "inaktiv: kein Undo")
end

-- --- Test 8: gesteuerte Brücke wird nutzbar ------------------------------
do
    setup(makeControlledBridgeRoom())
    local r1 = Room.tryUseConnection()
    check(r1.used == false, "gesteuert: vor Aktivierung inaktiv")
    State.setSwitch("S1", "A") -- B1 aktiv
    Room.syncPhysicalShutters()
    local r2 = Room.tryUseConnection()
    check(r2.used == true, "gesteuert: nach Aktivierung nutzbar")
    check(r2.id == "B1", "gesteuert: id B1")
    completeTransit()
    check(State.player.ring == "inner", "gesteuert: Ringwechsel erfolgreich")
end

-- --- Test 9: Gate aktiv auf inner ----------------------------------------
do
    setup(makeGateRoom())
    local result = Room.tryUseConnection()
    check(result.used == true, "gate aktiv: used true")
    check(result.kind == "gate", "gate aktiv: kind gate")
    check(result.id == "T", "gate aktiv: id T")
    check(result.roomComplete == true, "gate aktiv: roomComplete true")
    check(State.room.name == "Gate", "gate aktiv: kein Raumwechsel")
    check(State.player.ring == "inner", "gate aktiv: Ring unverändert")
    check(State.player.angle == 0, "gate aktiv: Winkel unverändert")
    check(Undo.count() == 0, "gate aktiv: kein Undo")
end

-- --- Test 10: Gate inaktiv -----------------------------------------------
do
    setup(makeInactiveGateRoom()) -- S1=A -> T inaktiv
    local result = Room.tryUseConnection()
    check(result.used == false, "gate inaktiv: used false")
    check(result.roomComplete == false, "gate inaktiv: roomComplete false")
end

-- --- Test 11: Gate auf outer nicht nutzbar -------------------------------
do
    local room = makeGateRoom()
    room.start.ring = "outer"
    room.start.angle = 0
    setup(room)
    local result = Room.tryUseConnection()
    check(result.used == false, "gate auf outer: used false")
    check(result.roomComplete == false, "gate auf outer: roomComplete false")
end

-- --- Test 12: Gate-Dockgrenze --------------------------------------------
do
    setup(makeGateRoom())
    State.player.angle = 348 -- Differenz 12 -> exakt dockRange
    local r1 = Room.tryUseConnection()
    check(r1.used == true, "gate grenze inklusiv: 348 nutzbar")

    setup(makeGateRoom())
    State.player.angle = 347.999 -- minimal außerhalb (12.001)
    local r2 = Room.tryUseConnection()
    check(r2.used == false, "gate grenze exklusiv: 347.999 nicht nutzbar")
end

-- --- Test 13: Brücke verändert keine Schalter-/Elementzustände -----------
do
    setup(makeControlledBridgeRoom())
    State.setSwitch("S1", "A") -- B1 aktiv machen
    local switchBefore = deepCopy(State.switchStates)
    local elementBefore = deepCopy(State.elementStates)
    local result = Room.tryUseConnection()
    check(result.used == true, "transit zustand: Brücke nutzbar")
    check(sameValues(State.switchStates, switchBefore), "transit zustand: switchStates identisch")
    check(sameValues(State.elementStates, elementBefore), "transit zustand: elementStates identisch")
    completeTransit()
    check(State.player.ring == "inner", "transit zustand: nur Ring geändert (nach Abschluss)")
end

-- --- Test 14: Brücke erzeugt kein Undo -----------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    check(Undo.count() == 0, "transit undo: 0 vor Transit")
    local result = Room.tryUseConnection()
    check(result.used == true, "transit undo: genutzt")
    check(Undo.count() == 0, "transit undo: nach Start 0")
    completeTransit()
    check(Undo.count() == 0, "transit undo: nach Abschluss 0")
end

-- --- Test 15: vorhandenes Undo bleibt erhalten ---------------------------
do
    setup(makeTransitRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, 1 Undo-Snapshot
    check(Undo.count() == 1, "transit undo-erhalten: 1 Undo vor Transit")
    local result = Room.tryUseConnection() -- B1 aktiv, Spieler 90 -> inner
    check(result.used == true, "transit undo-erhalten: genutzt")
    completeTransit()
    check(Undo.count() == 1, "transit undo-erhalten: Undo unverändert (kein clear, kein push)")
end

-- --- Test 16: Undo nach späterem Brückentransit --------------------------
do
    setup(makeTransitRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, Snapshot (Frame-Start 10, S1=B)
    Room.tryUseConnection() -- B1: outer -> inner (Transit starten)
    completeTransit()
    check(State.player.ring == "inner", "transit undo-nach: vor Undo auf inner")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "transit undo-nach: S1 restauriert")
    check(State.elementStates["B1"] == false, "transit undo-nach: B1 eingefahren")
    check(State.elementStates["D1"] == true, "transit undo-nach: D1 offen")
    check(State.player.ring == "outer", "transit undo-nach: Ring wieder outer")
    check(State.player.angle == 10, "transit undo-nach: Winkel vor Schalterhandlung (10)")
end

-- --- Test 17: Ringwechsel + G7-Sicherheit --------------------------------
do
    setup(makeG7TransitRoom()) -- S1=A -> B1 aktiv, D1 (inner@90) geschlossen
    local result = Room.tryUseConnection()
    check(result.used == true, "g7 zielring: Brücke genutzt")
    completeTransit() -- Ringwechsel + G7-Synchronisierung
    check(State.player.ring == "inner", "g7 zielring: Spieler auf inner")
    check(State.player.angle == 90, "g7 zielring: Winkel 90")
    check(Room.shutters["D1"].collisionActive == false, "g7 zielring: nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == true, "g7 zielring: pendingClose true")
end

-- --- Test 18: geschlossene Blende auf anderem Ring -----------------------
do
    setup(makeOtherRingRoom()) -- S1=A -> B1 aktiv, D1 (outer@90) geschlossen
    local result = Room.tryUseConnection()
    check(result.used == true, "anderer ring: Brücke genutzt")
    completeTransit()
    check(State.player.ring == "inner", "anderer ring: Spieler auf inner")
    check(Room.shutters["D1"].collisionActive == true, "anderer ring: outer-Blende kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "anderer ring: kein pendingClose auf outer")
end

-- --- Test 19: mehrere Brücken, nur eine dockbar --------------------------
do
    setup(makeTwoBridgeRoom())
    local result = Room.tryUseConnection()
    check(result.used == true, "mehrere: used true")
    check(result.id == "B0", "mehrere: genau B0 benutzt")
    completeTransit()
    check(State.player.ring == "inner", "mehrere: Ring inner")
end

-- --- Test 20: zwei gleichzeitig dockbare Brücken -------------------------
do
    setup(makeAmbiguousBridgeRoom())
    local ok, err = pcall(function()
        Room.tryUseConnection()
    end)
    check(ok == false, "zwei brücken: Ambiguitätsfehler ausgelöst")
    check(type(err) == "string" and string.find(err, "mehrdeutig", 1, true) ~= nil, "zwei brücken: Fehlermeldung benennt Ambiguität")
end

-- --- Test 21: Bridge + Gate gleichzeitig dockbar -------------------------
do
    setup(makeAmbiguousGateBridgeRoom())
    local ok, err = pcall(function()
        Room.tryUseConnection()
    end)
    check(ok == false, "bridge+gate: Ambiguitätsfehler ausgelöst")
    check(type(err) == "string" and string.find(err, "mehrdeutig", 1, true) ~= nil, "bridge+gate: Fehlermeldung benennt Ambiguität")
end

-- --- Test 22: keine Verbindung -------------------------------------------
do
    setup(makeDistantRoom())
    local before = deepCopy(State.player)
    local result = Room.tryUseConnection()
    check(result.used == false, "keine verbindung: used false")
    check(result.kind == nil, "keine verbindung: kind nil")
    check(result.id == nil, "keine verbindung: id nil")
    check(result.roomComplete == false, "keine verbindung: roomComplete false")
    check(State.player.ring == before.ring, "keine verbindung: Ring unverändert")
    check(State.player.angle == before.angle, "keine verbindung: Winkel unverändert")
    check(Undo.count() == 0, "keine verbindung: kein Undo")
end

-- --- Test 23: wiederholte A-Aktion nach Brückentransit -------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    local r1 = Room.tryUseConnection() -- outer -> inner (Transit starten)
    check(r1.used == true and r1.crossing == true, "wiederholt: 1. A startet Transit")
    completeTransit()
    check(State.player.ring == "inner", "wiederholt: nach Transit auf inner")
    local r2 = Room.tryUseConnection() -- inner -> outer (B0 weiterhin dockbar)
    check(r2.used == true and r2.kind == "bridge", "wiederholt: 2. A startet Transit zurück")
    completeTransit()
    check(State.player.ring == "outer", "wiederholt: nach Transit auf outer")
end

-- --- Test 24: Transit startet --------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    local result = Room.tryUseConnection()
    check(result.used == true, "transit start: used true")
    check(result.kind == "bridge", "transit start: kind bridge")
    check(Bridge.isCrossing() == true, "transit start: crossing true")
    check(State.player.ring == "outer", "transit start: Ring bleibt outer")
    check(State.player.angle == 90, "transit start: Winkel 90")
end

-- --- Test 25: Winkel wird ausgerichtet ------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 86))
    Room.tryUseConnection()
    check(State.player.angle == 90, "transit ausrichten: Winkel 90")
    check(State.player.ring == "outer", "transit ausrichten: Ring Ausgangsring")
end

-- --- Test 26: halbe Zeit --------------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    Room.tryUseConnection()
    Bridge.update(Config.bridgeAnimDuration / 2)
    local progress = Bridge.getTransitProgress()
    check(approx(progress, 0.5), "transit mitte: progress ~0.5")
    check(Bridge.isCrossing() == true, "transit mitte: noch aktiv")
    check(State.player.ring == "outer", "transit mitte: noch kein Ringwechsel")
end

-- --- Test 27: Abschluss ---------------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    Room.tryUseConnection()
    local completed = Bridge.update(Config.bridgeAnimDuration + 0.001)
    check(completed == true, "transit abschluss: genau einmal completed")
    check(Bridge.isCrossing() == false, "transit abschluss: nicht mehr aktiv")
    check(State.player.ring == "inner", "transit abschluss: Ring inner")
    check(State.player.angle == 90, "transit abschluss: Winkel 90")
end

-- --- Test 28: Overshoot ---------------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    Room.tryUseConnection()
    local completed = Bridge.update(1.0) -- viel größer als die Dauer
    check(completed == true, "overshoot: completed true")
    check(Bridge.isCrossing() == false, "overshoot: nicht mehr aktiv")
    check(State.player.ring == "inner", "overshoot: Ring exakt einmal gewechselt")
    check(Bridge.getTransitProgress() == nil, "overshoot: kein Fortschritt nach Abschluss (kein >1)")
end

-- --- Test 29: inner -> outer ----------------------------------------------
do
    setup(makeBridgeRoom(90, "inner", 90))
    Room.tryUseConnection()
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    check(State.player.ring == "outer", "i->o: Ring outer")
    check(State.player.angle == 90, "i->o: Winkel 90")
end

-- --- Test 30: kein zweiter Transit ----------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    Room.tryUseConnection()
    check(Bridge.isCrossing() == true, "kein zweiter: 1. Transit aktiv")
    local r2 = Room.tryUseConnection()
    check(r2.used == false, "kein zweiter: tryUseConnection used false")
    check(Bridge.isCrossing() == true, "kein zweiter: erster Transit unverändert")
    check(State.player.angle == 90, "kein zweiter: Winkel unverändert")
end

-- --- Test 31: kein Undo durch Transit -------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    check(Undo.count() == 0, "kein undo: vor 0")
    Room.tryUseConnection()
    check(Undo.count() == 0, "kein undo: nach Start 0")
    Bridge.update(Config.bridgeAnimDuration / 2)
    check(Undo.count() == 0, "kein undo: Mitte 0")
    Bridge.update(Config.bridgeAnimDuration / 2 + 0.001)
    check(Undo.count() == 0, "kein undo: nach Abschluss 0")
end

-- --- Test 32: vorhandener Undo bleibt -------------------------------------
do
    setup(makeTransitRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, 1 Undo
    check(Undo.count() == 1, "vorhanden undo: vor Transit 1")
    Room.tryUseConnection()
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    check(Undo.count() == 1, "vorhanden undo: nach komplettem Transit 1")
end

-- --- Test 33: Undo nach abgeschlossener Brücke ----------------------------
do
    setup(makeTransitRoom())
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, Snapshot (10, S1=B)
    Room.tryUseConnection() -- Transit starten
    Bridge.update(Config.bridgeAnimDuration + 0.001) -- auf inner
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "undo-nach-abschluss: auf inner")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "undo-nach-abschluss: S1 zurück")
    check(State.elementStates["B1"] == false, "undo-nach-abschluss: B1 eingefahren")
    check(State.elementStates["D1"] == true, "undo-nach-abschluss: D1 offen")
    check(State.player.ring == "outer", "undo-nach-abschluss: Ring outer")
    check(State.player.angle == 10, "undo-nach-abschluss: Winkel 10")
end

-- --- Test 34: G7 auf Zielring ---------------------------------------------
do
    setup(makeG7TransitRoom()) -- S1=A -> B1 aktiv, D1 (inner@90) geschlossen
    Room.tryUseConnection()
    Bridge.update(Config.bridgeAnimDuration + 0.001)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "g7 ziel: auf inner")
    check(Room.shutters["D1"].pendingClose == true, "g7 ziel: pendingClose true")
    check(Room.shutters["D1"].collisionActive == false, "g7 ziel: collisionActive false")
end

-- --- Test 35: Switch am Zielwinkel wird nicht ausgelöst -------------------
-- Zielring besitzt einen Switch exakt am Brückenwinkel. Der Transit ist eine
-- reine radiale Bewegung (keine tangentiale Überfahrt) -> kein Switch-Event.
do
    local room = {
        name = "ZielSwitch",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S2", ring="inner", angle=90, symbol=1, onA="D1", onB="B1", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=180 },
        },
        bridges = {
            { id="B0", angle=90, free=true },
            { id="B1", angle=0,  free=false },
        },
        gate = { id="T", angle=270, free=true },
    }
    setup(room)
    check(State.switchStates["S2"] == "B", "ziel-switch: Start B")
    Room.tryUseConnection() -- B0 -> inner (Transit)
    check(State.player.angle == 90, "ziel-switch: Winkel 90")
    Bridge.update(Config.bridgeAnimDuration + 0.001) -- Abschluss auf inner@90
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner", "ziel-switch: auf inner")
    check(State.switchStates["S2"] == "B", "ziel-switch: S2 NICHT ausgelöst (bleibt B)")
    check(Undo.count() == 0, "ziel-switch: kein Undo")
end

-- --- Test 36: Reset -------------------------------------------------------
do
    setup(makeBridgeRoom(90, "outer", 90))
    Room.tryUseConnection()
    check(Bridge.isCrossing() == true, "reset: vorher aktiv")
    Bridge.resetTransit()
    check(Bridge.isCrossing() == false, "reset: nachher inaktiv")
    check(Bridge.getTransit() == nil, "reset: keine Restdaten")
    check(State.player.ring == "outer", "reset: Ring unverändert (kein erzwungener Wechsel)")
end

-- --- Test 37: Gate-Wraparound (Spieler 358, Gate 2) ----------------------
-- Pflicht-Test 6: Differenz 4 über die 0°-Grenze -> nutzbar (dockRange inklusiv).
do
    local room = {
        name = "GateWrap",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 358 },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=180, free=true } },
        gate = { id="T", angle=2, free=true },
    }
    setup(room)
    local result = Room.tryUseConnection()
    check(result.used == true, "gate wraparound: 358 zu Gate 2 nutzbar (Differenz 4)")
    check(result.kind == "gate", "gate wraparound: kind gate")
    check(result.id == "T", "gate wraparound: id T")
    check(result.roomComplete == true, "gate wraparound: roomComplete true")
end

-- --- Test 38: Gate verändert keine Zustände (Pflicht-Test 7) -------------
do
    setup(makeGateRoom())
    local switchBefore = deepCopy(State.switchStates)
    local elementBefore = deepCopy(State.elementStates)
    local roomBefore = State.room
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local result = Room.tryUseConnection()
    check(result.used == true and result.roomComplete == true, "gate zustand: genutzt")
    check(sameValues(State.switchStates, switchBefore), "gate zustand: switchStates identisch")
    check(sameValues(State.elementStates, elementBefore), "gate zustand: elementStates identisch")
    check(State.room == roomBefore, "gate zustand: State.room identisch (kein Raumwechsel)")
    check(State.player.ring == ringBefore, "gate zustand: Ring unverändert")
    check(State.player.angle == angleBefore, "gate zustand: Winkel unverändert")
end

-- --- Test 39: Gate löscht vorhandenes Undo nicht (Pflicht-Test 9) --------
do
    setup(makeTransitRoom()) -- S1 steuert B1; Gate T@180 free
    Room.movePlayer(80) -- 10 -> 90, S1 -> A, 1 Undo
    check(Undo.count() == 1, "gate undo-vorhanden: 1 Undo vor Gate")
    State.player.ring = "inner"
    State.player.angle = 180 -- an der freien Kernbrücke T
    local result = Room.tryUseConnection()
    check(result.used == true and result.kind == "gate", "gate undo-vorhanden: Gate genutzt")
    check(result.roomComplete == true, "gate undo-vorhanden: roomComplete true")
    check(Undo.count() == 1, "gate undo-vorhanden: Undo unverändert (1)")
end

-- --- Test 40: Gate während Bridge-Crossing nicht erreichbar --------------
-- Pflicht-Test 12: Während Bridge.isCrossing() darf tryUseConnection weder
-- ein zweites Bridge- noch ein Gate-Event auslösen (main.lua ruft es in der
-- Crossing-Phase ohnehin nicht auf; hier zusätzlich die defensive No-op-Erwartung).
do
    local room = {
        name = "CrossGate",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=90, free=true } },
        gate = { id="T", angle=90, free=true },
    }
    setup(room)
    -- Start: nur B0 ist Kandidat (Gate ist inner-only, Spieler outer).
    local r1 = Room.tryUseConnection()
    check(r1.used == true and r1.kind == "bridge", "crossing gate: Brücke gestartet")
    check(Bridge.isCrossing() == true, "crossing gate: Transit aktiv")
    -- Während der radialen Überquerung: kein Gate-, kein zweites Bridge-Event.
    local r2 = Room.tryUseConnection()
    check(r2.used == false, "crossing gate: während Transit used false")
    check(r2.roomComplete == false, "crossing gate: kein Raumende während Transit")
    check(Bridge.isCrossing() == true, "crossing gate: Transit unverändert")
    check(State.player.ring == "outer", "crossing gate: Ring unverändert (noch outer)")
    check(State.player.angle == 90, "crossing gate: Winkel unverändert")
end
-- Integrationsanforderung (festhalten): Die spätere echte Eingabeintegration
-- muss playdate.buttonJustPressed(playdate.kButtonA) verwenden und NICHT
-- buttonIsPressed, damit ein gehaltenes A nicht jeden Frame zwischen den
-- Ringen hin- und herschaltet.

-- --- Statische Ambiguitätsprüfung der sechs echten Räume (nur lesend) ----
do
    local minDist = math.huge
    local ambiguous = false
    local info = nil
    for _, room in ipairs(Levels) do
        for _, ring in ipairs({ "outer", "inner" }) do
            -- Kandidaten auf diesem Ring: Brücken (beide Ringe), auf inner
            -- zusätzlich das Gate.
            local conns = {}
            for _, b in ipairs(room.bridges) do
                conns[#conns + 1] = { id = b.id, angle = b.angle }
            end
            if ring == "inner" and room.gate then
                conns[#conns + 1] = { id = room.gate.id, angle = room.gate.angle }
            end
            for i = 1, #conns do
                for j = i + 1, #conns do
                    local d = math.abs(Geometry.delta(conns[i].angle, conns[j].angle))
                    if d < minDist then
                        minDist = d
                    end
                    -- Zwei Verbindungen lägen im selben Dockfenster, wenn der
                    -- Spieler beide gleichzeitig in Reichweite haben könnte.
                    if d <= 2 * Config.dockRange then
                        ambiguous = true
                        info = { room = room.name, a = conns[i].id, b = conns[j].id, angleA = conns[i].angle, angleB = conns[j].angle, dist = d }
                    end
                end
            end
        end
    end
    check(ambiguous == false, "level: keine Docking-Ambiguität in sechs Räumen")
    if ambiguous and info then
        print("LEVEL_AMBIG: " .. info.room .. " " .. info.a .. "/" .. info.b .. " bei " .. info.angleA .. "°/" .. info.angleB .. "° Abstand " .. info.dist .. "°")
    else
        print("LEVEL_CHECK: kein Verbindungspaar näher als " .. (2 * Config.dockRange) .. "° (minimaler Abstand " .. tostring(minDist) .. "°)")
    end
end

TestReport.connection = { pass = pass, fail = fail }
