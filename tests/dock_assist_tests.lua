-- Tests für die Andockhilfe (Phase 7.3): source/world/room.lua
-- (Room.updateDockAssist / resetDockAssist / isDockAssisting / getDockAssist).
-- Reine Positionskorrektur über exakt Config.dockAssistFrames Frames, nur ohne
-- Bewegungsinput, auf aktive Brücken (beide Ringe) und Schalter (aktueller
-- Ring). Kein Gate, kein Undo, kein Schalter-Trigger, keine Kollisionsumgehung.
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/room, world/bridge, world/switch und world/gate per import geladen
-- wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.dockAssist gesammelt; die
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
    Room.resetDockAssist()
end

-- Freie aktive Brücke B0 bei bridgeAngle; Spieler outer@playerAngle.
local function makeBridgeRoom(bridgeAngle, playerAngle)
    return {
        name = "AssistBruecke",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = playerAngle },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=bridgeAngle, free=true } },
        gate = { id="T", angle=180, free=true },
    }
end

-- Gesteuerte, anfangs inaktive Brücke B1@90 (S1=B -> B1 inaktiv).
local function makeInactiveBridgeRoom(playerAngle)
    return {
        name = "AssistInaktiv",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = playerAngle },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=200 } },
        bridges = { { id="B1", angle=90, free=false } },
        gate = { id="T", angle=180, free=true },
    }
end

-- Schalter S1@switchAngle auf outer; Spieler outer@playerAngle.
local function makeSwitchRoom(switchAngle, playerAngle)
    return {
        name = "AssistSwitch",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = playerAngle },
        switches = {
            { id="S1", ring="outer", angle=switchAngle, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=200 } },
        bridges = { { id="B0", angle=180, free=true } },
        gate = { id="T", angle=0, free=true },
    }
end

-- Schalter auf INNEREM Ring; Spieler auf outer (darf nicht assistieren).
local function makeOtherRingSwitchRoom()
    return {
        name = "AssistOtherRing",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 87 },
        switches = {
            { id="S1", ring="inner", angle=90, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=200 } },
        bridges = { { id="B0", angle=180, free=true } },
        gate = { id="T", angle=0, free=true },
    }
end

-- Geschlossene Blende D1 (outer@101, Bogen [88,114]) zwischen Spieler 87 und
-- Ziel B0@90: der CW-Weg 87->90 kreuzt die Eintrittskante 88.
local function makeBlockedBridgeRoom()
    return {
        name = "AssistBlocked",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 87 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B2", onB="D1", state="A" },
        },
        shutters = { { id="D1", ring="outer", angle=101 } },
        bridges = {
            { id="B0", angle=90, free=true },
            { id="B2", angle=270, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Zwei gleich weit entfernte Ziele (-2/+2) -> kein Assistenzstart.
local function makeTieRoom()
    return {
        name = "AssistTie",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=88, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=200 } },
        bridges = { { id="B0", angle=92, free=true } },
        gate = { id="T", angle=180, free=true },
    }
end

-- Nächstes Ziel: Switch S1@89 (dist 1) näher als Brücke B0@93 (dist 3).
local function makeNearestRoom()
    return {
        name = "AssistNearest",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=89, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=200 } },
        bridges = { { id="B0", angle=93, free=true } },
        gate = { id="T", angle=180, free=true },
    }
end

-- --- Pflicht-Test 1: aktive Brücke +3° -----------------------------------
do
    setup(makeBridgeRoom(90, 87))
    check(Room.isDockAssisting() == false, "+3: vorher inaktiv")
    Room.updateDockAssist()
    check(approx(State.player.angle, 88), "+3: Frame 1 -> 88")
    check(Room.isDockAssisting() == true, "+3: Frame 1 aktiv")
    local da = Room.getDockAssist()
    check(da ~= nil and da.kind == "bridge" and da.id == "B0", "+3: Ziel Brücke B0")
    check(da ~= nil and approx(da.signedDelta, 3), "+3: signedDelta +3")
    Room.updateDockAssist()
    check(approx(State.player.angle, 89), "+3: Frame 2 -> 89")
    Room.updateDockAssist()
    check(State.player.angle == 90, "+3: Frame 3 -> 90")
    check(Room.isDockAssisting() == false, "+3: danach inaktiv")
    check(Room.getDockAssist() == nil, "+3: keine Restdaten")
end

-- --- Pflicht-Test 2: aktive Brücke -3° -----------------------------------
do
    setup(makeBridgeRoom(90, 93))
    Room.updateDockAssist()
    check(approx(State.player.angle, 92), "-3: Frame 1 -> 92")
    Room.updateDockAssist()
    check(approx(State.player.angle, 91), "-3: Frame 2 -> 91")
    Room.updateDockAssist()
    check(State.player.angle == 90, "-3: Frame 3 -> 90")
    check(Room.isDockAssisting() == false, "-3: danach inaktiv")
end

-- --- Pflicht-Test 3: exakt 4° --------------------------------------------
do
    setup(makeBridgeRoom(90, 86))
    Room.updateDockAssist()
    check(Room.isDockAssisting() == true, "exakt 4°: Assistenz startet")
    local da = Room.getDockAssist()
    check(da ~= nil and approx(da.signedDelta, 4), "exakt 4°: signedDelta +4")
end

-- --- Pflicht-Test 4: außerhalb (>4°) -------------------------------------
do
    setup(makeBridgeRoom(90, 85.999))
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, ">4°: keine Assistenz")
    check(approx(State.player.angle, 85.999), ">4°: Position unverändert")
end

-- --- Pflicht-Test 5: Wraparound ------------------------------------------
do
    setup(makeBridgeRoom(2, 359))
    Room.updateDockAssist()
    check(approx(State.player.angle, 0), "wrap: Frame 1 -> 0")
    Room.updateDockAssist()
    check(approx(State.player.angle, 1), "wrap: Frame 2 -> 1")
    Room.updateDockAssist()
    check(State.player.angle == 2, "wrap: Frame 3 -> 2")
    check(Room.isDockAssisting() == false, "wrap: danach inaktiv")
end

-- --- Pflicht-Test 6: inaktive Brücke -------------------------------------
do
    setup(makeInactiveBridgeRoom(89)) -- S1=B -> B1@90 inaktiv
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "inaktiv: keine Assistenz")
    check(approx(State.player.angle, 89), "inaktiv: Position unverändert")
end

-- --- Pflicht-Test 7: Switch auf gleichem Ring ----------------------------
do
    setup(makeSwitchRoom(90, 87))
    Room.updateDockAssist()
    check(approx(State.player.angle, 88), "switch: Frame 1 -> 88")
    local da = Room.getDockAssist()
    check(da ~= nil and da.kind == "switch" and da.id == "S1", "switch: Ziel Schalter S1")
    Room.updateDockAssist()
    check(approx(State.player.angle, 89), "switch: Frame 2 -> 89")
    Room.updateDockAssist()
    check(State.player.angle == 90, "switch: Frame 3 -> 90")
    check(Room.isDockAssisting() == false, "switch: danach inaktiv")
end

-- --- Pflicht-Test 8: Switch wird NICHT ausgelöst -------------------------
do
    setup(makeSwitchRoom(90, 87))
    local swBefore = State.switchStates["S1"]
    local elBefore = {}
    for k, v in pairs(State.elementStates) do
        elBefore[k] = v
    end
    local undoBefore = Undo.count()
    Room.updateDockAssist()
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 90, "switch-sicher: Snap auf 90")
    check(State.switchStates["S1"] == swBefore, "switch-sicher: switchStates unverändert")
    check(sameValues(State.elementStates, elBefore), "switch-sicher: elementStates unverändert")
    check(Undo.count() == undoBefore, "switch-sicher: Undo unverändert")
end

-- --- Pflicht-Test 9: kleine Bewegung nach Snap ---------------------------
do
    setup(makeSwitchRoom(90, 87)) -- S1@90 (Bogen [83,97]), Zustand B
    Room.updateDockAssist()
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 90, "snap+move: auf Switch-Mittelpunkt 90")
    local a1 = Room.movePlayer(5) -- 90 -> 95, erreicht die CW-Austrittskante 97 nicht
    check(a1 == 5, "snap+move: kleine CW-Bewegung actual 5")
    check(State.player.angle == 95, "snap+move: Winkel 95")
    check(State.switchStates["S1"] == "B", "snap+move: kein Trigger (Start innerhalb des Bogens)")
    check(Undo.count() == 0, "snap+move: kein Undo")
    -- Vollständiges Verlassen in CW-Richtung (Eintritt vor Austritt im selben
    -- Frame) setzt A — die normale Switch-Regel bleibt unverändert.
    State.player.angle = 80 -- vor der Eintrittskante 83
    local a2 = Room.movePlayer(20) -- 80 -> 100, kreuzt Eintritt 83 und Austritt 97
    check(a2 == 20, "snap+move: vollständige CW-Überfahrt actual 20")
    check(State.switchStates["S1"] == "A", "snap+move: vollständige CW-Überfahrt -> A")
end

-- --- Pflicht-Test 10: eigenes Input bricht Assistenz ---------------------
do
    setup(makeBridgeRoom(90, 87))
    Room.updateDockAssist() -- Frame 1, aktiv, Winkel 88
    check(Room.isDockAssisting() == true, "input: Assistenz aktiv nach Frame 1")
    -- main.lua bei wantedDelta ~= 0: resetDockAssist + movePlayer (kein
    -- Assistenzdelta zusätzlich).
    Room.resetDockAssist()
    local actual = Room.movePlayer(5)
    check(actual == 5, "input: normale Bewegung +5")
    check(State.player.angle == 93, "input: Winkel 88+5=93")
    check(Room.isDockAssisting() == false, "input: Assistenz inaktiv")
end

-- --- Pflicht-Test 11: kein Undo ------------------------------------------
do
    setup(makeBridgeRoom(90, 87))
    check(Undo.count() == 0, "undo: vorher 0")
    Room.updateDockAssist()
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 90, "undo: Snap auf 90")
    check(Undo.count() == 0, "undo: nach kompletter Assistenz 0")
end

-- --- Pflicht-Test 12: Bridge-Crossing ------------------------------------
do
    setup(makeBridgeRoom(90, 87))
    Room.updateDockAssist() -- Frame 1, aktiv, Winkel 88
    check(Room.isDockAssisting() == true, "crossing: Assistenz aktiv")
    local r = Room.tryUseConnection() -- 88 in dockRange(6) von 90 -> Transit
    check(r.used == true and r.crossing == true, "crossing: Transit gestartet")
    -- main.lua bei Crossing: resetDockAssist; updateDockAssist ist No-op.
    Room.resetDockAssist()
    check(Room.isDockAssisting() == false, "crossing: Assistenz inaktiv")
    check(Bridge.isCrossing() == true, "crossing: Transit läuft")
    Room.updateDockAssist() -- Guard: während Crossing kein Assistenzupdate
    check(Bridge.isCrossing() == true, "crossing: Transit unverändert")
    check(Room.isDockAssisting() == false, "crossing: kein Assistenzstart während Crossing")
    check(State.player.angle == 90, "crossing: Winkel 90 (Brückenachse)")
end

-- --- Pflicht-Test 13: B/Undo-Reset ---------------------------------------
do
    setup(makeSwitchRoom(90, 80)) -- S1@90 (Bogen [83,97]), Zustand B
    Room.movePlayer(20) -- 80 -> 100, S1 -> A, 1 Undo
    check(Undo.count() == 1, "undo-reset: 1 Undo erzeugt")
    State.player.angle = 87 -- nahe dem Switch-Mittelpunkt (Zustand jetzt A)
    Room.updateDockAssist() -- Frame 1, aktiv (Ziel S1@90)
    check(Room.isDockAssisting() == true, "undo-reset: Assistenz aktiv")
    -- main.lua bei B justPressed: resetDockAssist + Undo.undo
    Room.resetDockAssist()
    local restored = Undo.undo()
    check(restored == true, "undo-reset: Undo ausgeführt")
    check(Room.isDockAssisting() == false, "undo-reset: Assistenz inaktiv")
    check(State.switchStates["S1"] == "B", "undo-reset: S1 restauriert")
    check(State.player.angle == 80, "undo-reset: Position restauriert (80)")
    check(Undo.count() == 0, "undo-reset: Stack leer")
end

-- --- Pflicht-Test 14: Raumstart-Reset ------------------------------------
do
    setup(makeBridgeRoom(90, 87))
    Room.updateDockAssist() -- aktiv
    check(Room.isDockAssisting() == true, "raumstart: Assistenz aktiv")
    -- startRoom-Äquivalent aus main.lua.
    Bridge.resetTransit()
    Room.resetDockAssist()
    State.init(makeBridgeRoom(90, 0))
    Undo.clear()
    Room.init()
    check(Room.isDockAssisting() == false, "raumstart: Assistenz inaktiv")
    check(Room.getDockAssist() == nil, "raumstart: keine Restdaten")
end

-- --- Pflicht-Test 15: geschlossene Blende dazwischen ---------------------
do
    setup(makeBlockedBridgeRoom()) -- D1@101 geschlossen, Spieler 87, Ziel B0@90
    check(State.elementStates["D1"] == false, "blendenblock: D1 geschlossen")
    check(Room.shutters["D1"].collisionActive == true, "blendenblock: collisionActive true")
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "blendenblock: keine Assistenz")
    check(State.player.angle == 87, "blendenblock: Position unverändert")
end

-- --- Pflicht-Test 16: Gate assistiert nicht ------------------------------
do
    local room = {
        name = "AssistGate",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 179 },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=90, free=true } },
        gate = { id="T", angle=180, free=true },
    }
    setup(room)
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "gate: keine Assistenz (Gate assistiert nicht)")
    check(State.player.angle == 179, "gate: Winkel unverändert")
end

-- --- Pflicht-Test 17: nächstes Ziel --------------------------------------
do
    setup(makeNearestRoom()) -- Switch S1@89 (dist 1), Brücke B0@93 (dist 3)
    Room.updateDockAssist()
    local da = Room.getDockAssist()
    check(da ~= nil and da.kind == "switch" and da.id == "S1", "nächstes: Switch S1 (dist 1) gewählt")
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 89, "nächstes: Snap auf 89")
end

-- --- Pflicht-Test 18: Gleichstand ----------------------------------------
do
    setup(makeTieRoom()) -- Switch S1@88 (dist 2), Brücke B0@92 (dist 2)
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "gleichstand: keine Assistenz")
    check(State.player.angle == 90, "gleichstand: Position unverändert")
end

-- --- Pflicht-Test 19: bereits exakt --------------------------------------
do
    setup(makeBridgeRoom(90, 90))
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "exakt: keine Assistenz")
    check(State.player.angle == 90, "exakt: Position unverändert")
end

-- --- Switch auf anderem Ring assistiert nicht ----------------------------
do
    setup(makeOtherRingSwitchRoom()) -- S1 auf inner, Spieler outer@87
    Room.updateDockAssist()
    check(Room.isDockAssisting() == false, "anderer ring: Switch auf inner assistiert outer nicht")
    check(State.player.angle == 87, "anderer ring: Position unverändert")
end

-- --- Integration: Assistenz -> A -> Bridge -------------------------------
do
    setup(makeBridgeRoom(90, 87))
    Room.updateDockAssist()
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 90, "assist->a: Snap auf Brückenwinkel 90")
    check(Room.isDockAssisting() == false, "assist->a: Assistenz nach Frame 3 inaktiv")
    local r = Room.tryUseConnection() -- A
    check(r.used == true and r.kind == "bridge", "assist->a: Brücke benutzt")
    check(r.crossing == true, "assist->a: crossing true")
    check(Bridge.isCrossing() == true, "assist->a: Transit aktiv")
    Room.resetDockAssist()
    check(Room.isDockAssisting() == false, "assist->a: Assistenz bleibt inaktiv")
end

-- --- Integration: Assistenz beeinflusst Gate nicht -----------------------
do
    local room = {
        name = "AssistGateInt",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 179 },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=90, free=true } },
        gate = { id="T", angle=180, free=true },
    }
    setup(room)
    Room.updateDockAssist()
    Room.updateDockAssist()
    Room.updateDockAssist()
    check(State.player.angle == 179, "gate-int: Winkel nach 3 Frames unverändert")
    local r = Room.tryUseConnection()
    check(r.used == true and r.kind == "gate", "gate-int: Gate über dockRange nutzbar")
    check(r.roomComplete == true, "gate-int: roomComplete true")
end

TestReport.dockAssist = { pass = pass, fail = fail }
