-- Tests für source/world/room.lua (globale Tabelle Room): chronologischer
-- Movement-Sweep. Verwendet ausschließlich synthetische Raumdaten.
-- Erwartet, dass core/config, core/geometry, core/state, core/undo und
-- world/room per import geladen wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.movement gesammelt; die aggregierte
-- RESULT-Zeile schreibt der Test-Runner.

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

-- Basissynthetischer Raum: S1/S2 auf outer, S3 auf inner; D1/D2 auf outer.
local function makeRoom()
    return {
        name = "Bewegungstest",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45,  symbol=1, onA="B1", onB="D1", state="B" },
            { id="S2", ring="outer", angle=200, symbol=2, onA="D2", onB="B2", state="B" },
            { id="S3", ring="inner", angle=100, symbol=3, onA="D3", onB="B3", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90  },
            { id="D2", ring="outer", angle=250 },
            { id="D3", ring="inner", angle=100 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
            { id="B2", angle=90,  free=false },
            { id="B3", angle=180, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- S1 öffnet D1 (onA=D1): S1 CW -> A öffnet D1.
local function makeOpenRoom()
    return {
        name = "Offen",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="D1", onB="B1", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- G7-Raum: S1 liegt im Bogen von D1; S1 CW -> A schließt D1, während der
-- Spieler (Start 80) noch im D1-Bogen steht. Nur für den Sweep-Test gültig.
local function makeG7Room()
    return {
        name = "G7",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 80 },
        switches = {
            { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- Zwei Schalter auf outer, Blenden auf inner (blockieren nie auf outer).
local function makeTwoSwitchRoom()
    return {
        name = "ZweiSchalter",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45,  symbol=1, onA="B1", onB="D1", state="B" },
            { id="S2", ring="outer", angle=200, symbol=2, onA="B2", onB="D2", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90  },
            { id="D2", ring="inner", angle=250 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
            { id="B2", angle=90,  free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- Ein Schalter auf outer, Blende auf inner (blockiert nie auf outer).
local function makeSingleSwitchRoom()
    return {
        name = "EinSchalter",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- Schalter getrennt auf outer und inner (Ringtrennung).
local function makeRingRoom()
    return {
        name = "Ringe",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 10 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B" },
            { id="S3", ring="inner", angle=100, symbol=2, onA="D3", onB="B3", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90  },
            { id="D3", ring="inner", angle=180 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
            { id="B3", angle=90,  free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
end

-- Schalter erst später im Weg (S1 bei 90, Start 40 außerhalb des Bogens).
local function makeLateSwitchRoom()
    return {
        name = "SpäterSchalter",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 40 },
        switches = {
            { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- pendingClose-Öffnen: S1 (steuert D1, A öffnet D1) liegt AUSSERHALB des
-- D1-Bogens [77,103]. Dadurch kann nach dem Öffnen eine freie Durchquerung
-- des Bogens getestet werden, ohne erneut über S1 zu fahren.
local function makePendingCloseOpenRoom()
    return {
        name = "PendingCloseOffnen",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 80 },
        switches = {
            { id="S1", ring="outer", angle=150, symbol=1, onA="D1", onB="B1", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B0", angle=0,   free=true  },
            { id="B1", angle=270, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- Tunneling-Raum: D1 (outer@180, Bogen [167,193]) ist im Startzustand S1=A
-- statisch geschlossen. S1@0 (Bogen [353,7]) liegt fern vom Testweg. Keine
-- Schalter im Bewegungsweg 90 -> 167 bzw. 250 -> 193.
local function makeTunnelRoom()
    return {
        name = "Tunnel",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=0, symbol=1, onA="B1", onB="D1", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=180 },
        },
        bridges = {
            { id="B0", angle=270, free=true  },
            { id="B1", angle=45,  free=false },
        },
        gate = { id="T", angle=90, free=true },
    }
end

-- --- Test 40: freie Bewegung ---------------------------------------------
do
    setup(makeRoom())
    local actual, result = Room.movePlayer(40)
    check(actual == 40, "frei: actual +40")
    check(State.player.angle == 50, "frei: Ende 50")
    check(Undo.count() == 0, "frei: kein Undo")
    check(result.blocked == false, "frei: nicht blockiert")

    setup(makeRoom())
    local a2, _ = Room.movePlayer(-40)
    check(a2 == -40, "frei negativ: actual -40")
    check(State.player.angle == 330, "frei negativ: Ende 330")
end

-- --- Test 41: Wrap über 0° -----------------------------------------------
do
    setup(makeRoom())
    State.player.angle = 350
    local actual, _ = Room.movePlayer(20)
    check(actual == 20, "wrap: actual +20")
    check(State.player.angle == 10, "wrap: Ende 10")
end

-- --- Test 42: Schalter CW vollständig ------------------------------------
do
    setup(makeRoom())
    local actual, _ = Room.movePlayer(50)
    check(State.switchStates["S1"] == "A", "S1 CW: Zustand A")
    check(State.elementStates["B1"] == true, "S1 CW: B1 aktiv")
    check(State.elementStates["D1"] == false, "S1 CW: D1 geschlossen")
    check(Undo.count() == 1, "S1 CW: 1 Undo")
    check(actual == 50, "S1 CW: actual 50")
    check(State.player.angle == 60, "S1 CW: Ende 60")
end

-- --- Test 43: nicht vollständig überfahren --------------------------------
do
    setup(makeRoom())
    local a1, _ = Room.movePlayer(40) -- 10 -> 50 (im S1-Bogen [38,52])
    check(State.switchStates["S1"] == "B", "nur hinein: S1 bleibt B")
    check(Undo.count() == 0, "nur hinein: kein Undo")
    local a2, _ = Room.movePlayer(-40) -- 50 -> 10 (zurück heraus)
    check(State.switchStates["S1"] == "B", "zurück heraus: weiterhin B")
    check(Undo.count() == 0, "zurück heraus: kein Undo")
end

-- --- Test 44: Schalter CCW ------------------------------------------------
do
    State.init(makeSingleSwitchRoom())
    State.setSwitch("S1", "A")
    Room.init()
    Undo.clear()
    State.player.angle = 100
    Room.syncPhysicalShutters()
    local actual, _ = Room.movePlayer(-100)
    check(State.switchStates["S1"] == "B", "S1 CCW: Zustand B")
    check(Undo.count() == 1, "S1 CCW: 1 Undo")
    check(actual == -100, "S1 CCW: actual -100")
end

-- --- Test 45: Schalter öffnet kommende Blende ----------------------------
do
    setup(makeOpenRoom())
    local actual, result = Room.movePlayer(120)
    check(State.elementStates["D1"] == true, "öffnen: D1 logisch offen")
    check(Room.shutters["D1"].collisionActive == false, "öffnen: D1 nicht kollisionsaktiv")
    check(actual == 120, "öffnen: actual == wanted (120)")
    check(State.player.angle == 130, "öffnen: Figur passiert D1, Ende 130")
    check(Undo.count() == 1, "öffnen: genau 1 Undo")
end

-- --- Test 46: Schalter schließt kommende Blende --------------------------
do
    setup(makeRoom())
    local actual, result = Room.movePlayer(120)
    check(State.elementStates["D1"] == false, "schließen: D1 logisch geschlossen")
    check(Room.shutters["D1"].collisionActive == true, "schließen: D1 kollisionsaktiv")
    check(actual == 67, "schließen: Figur stoppt an Eintrittskante (actual 67)")
    check(State.player.angle == 77, "schließen: Ende an Eintrittskante 77")
    check(result.blocked == true, "schließen: blockiert")
    check(Undo.count() == 1, "schließen: genau 1 Undo")
end

-- --- Test 47: G7 ----------------------------------------------------------
do
    State.init(makeG7Room())
    Room.init()
    Undo.clear()
    Room.movePlayer(17) -- S1 -> A, D1 schließt, Spieler (97) im Bogen
    check(State.elementStates["D1"] == false, "G7: D1 logisch geschlossen")
    check(Room.shutters["D1"].collisionActive == false, "G7: im Bogen -> nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == true, "G7: pendingClose true")
    local a2, _ = Room.movePlayer(43) -- 97 -> 140, verlässt D1
    check(Room.shutters["D1"].collisionActive == true, "G7: nach Verlassen kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "G7: pendingClose gelöst")
    check(State.player.angle == 140, "G7: Ende 140")
    check(Undo.count() == 1, "G7: genau 1 Undo")
end

-- --- Test 48: G7 + Richtungswechsel ---------------------------------------
do
    State.init(makeG7Room())
    Room.init()
    Undo.clear()
    Room.movePlayer(17) -- S1 -> A, D1 schließt, pendingClose, Spieler bei 97
    check(Room.shutters["D1"].pendingClose == true, "G7+WC: pendingClose vor Ausfahrt")
    local a2, _ = Room.movePlayer(-40) -- CCW heraus
    check(a2 == -40, "G7+WC: Bewegung erlaubt (actual -40)")
    check(State.player.angle == 57, "G7+WC: Ende 57")
    check(Room.shutters["D1"].collisionActive == true, "G7+WC: schließt hinter Spieler")
    check(Room.shutters["D1"].pendingClose == false, "G7+WC: pendingClose gelöst")
end

-- --- Test 49: zwei Schalter in einem Frame --------------------------------
do
    setup(makeTwoSwitchRoom())
    local actual, result = Room.movePlayer(220)
    check(State.switchStates["S1"] == "A", "zwei: S1 -> A")
    check(State.switchStates["S2"] == "A", "zwei: S2 -> A")
    check(Undo.count() == 1, "zwei: genau 1 Undo")
    check(result.switchChanges == 2, "zwei: 2 echte Schalteränderungen")
    check(actual == 220, "zwei: actual 220")
    check(State.player.angle == 230, "zwei: Ende 230")
    -- gemeinsames Rückrollen
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "zwei: nach Undo S1=B")
    check(State.switchStates["S2"] == "B", "zwei: nach Undo S2=B")
    check(State.player.ring == "outer", "zwei: nach Undo Ring=outer (Frame-Start)")
    check(State.player.angle == 10, "zwei: nach Undo Spieler bei Frame-Start 10")
    -- alle abhängigen Elementzustände restauriert (B1/D1 aus S1, B2/D2 aus S2)
    check(State.elementStates["D1"] == true, "zwei: nach Undo D1 offen")
    check(State.elementStates["D2"] == true, "zwei: nach Undo D2 offen")
    check(State.elementStates["B1"] == false, "zwei: nach Undo B1 eingefahren")
    check(State.elementStates["B2"] == false, "zwei: nach Undo B2 eingefahren")
    check(State.elementStates["B0"] == true, "zwei: nach Undo B0 frei aktiv")
    check(State.elementStates["T"] == true, "zwei: nach Undo T frei aktiv")
    -- physischer Blendenzustand rekonstruiert (logisch offen -> nicht aktiv)
    check(Room.shutters["D1"].collisionActive == false, "zwei: nach Undo D1 nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "zwei: nach Undo D1 kein pendingClose")
    check(Room.shutters["D2"].collisionActive == false, "zwei: nach Undo D2 nicht kollisionsaktiv")
    check(Room.shutters["D2"].pendingClose == false, "zwei: nach Undo D2 kein pendingClose")
end

-- --- Test 50: kritische Position-vor-Schalter -----------------------------
do
    State.init(makeLateSwitchRoom())
    Room.init()
    Undo.clear()
    local actual, _ = Room.movePlayer(70) -- 40 -> 110, kreuzt S1 (Austritt 97)
    check(State.switchStates["S1"] == "A", "pos-vor-Schalter: S1 geändert")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.player.angle == 40, "pos-vor-Schalter: nach Undo exakt 40")
    check(State.switchStates["S1"] == "B", "pos-vor-Schalter: S1 zurück")
end

-- --- Test 51: bereits richtiger Schalterzustand ---------------------------
do
    setup(makeRoom())
    State.setSwitch("S1", "A")
    Undo.clear()
    Room.syncPhysicalShutters()
    local actual, _ = Room.movePlayer(60) -- 10 -> 70, kreuzt S1
    check(State.switchStates["S1"] == "A", "bereits A: bleibt A")
    check(Undo.count() == 0, "bereits A: kein Undo")
    check(actual == 60, "bereits A: Bewegung läuft weiter (actual 60)")
end

-- --- Test 52: +720° -------------------------------------------------------
do
    setup(makeSingleSwitchRoom())
    local actual, _ = Room.movePlayer(720)
    check(actual == 720, "+720: actual 720")
    check(State.player.angle == 10, "+720: Endwinkel 10")
    check(State.switchStates["S1"] == "A", "+720: S1 A")
    check(Undo.count() == 1, "+720: genau 1 Undo (eine echte Änderung)")
end

-- --- Test 53: -720° -------------------------------------------------------
do
    State.init(makeSingleSwitchRoom())
    State.setSwitch("S1", "A")
    Room.init()
    Undo.clear()
    local actual, _ = Room.movePlayer(-720)
    check(actual == -720, "-720: actual -720")
    check(State.player.angle == 10, "-720: Endwinkel 10")
    check(State.switchStates["S1"] == "B", "-720: S1 B")
    check(Undo.count() == 1, "-720: maximal 1 Undo")
end

-- --- Test 54: Start direkt an geschlossener Kante -------------------------
do
    setup(makeRoom()) -- S2 startet B -> D2 (outer 250, Bogen [237,263]) geschlossen
    Undo.clear()
    Room.syncPhysicalShutters()
    State.player.angle = 237 -- exakt an der CW-Eintrittskante von D2
    local actual, result = Room.movePlayer(10)
    check(actual == 0, "Kante: actual 0")
    check(State.player.angle == 237, "Kante: Position unverändert")
    check(result.blocked == true, "Kante: blockiert")
end

-- --- Test 55: von der Kante wegfahren -------------------------------------
do
    setup(makeRoom()) -- S2 startet B -> D2 geschlossen
    Undo.clear()
    Room.syncPhysicalShutters()
    State.player.angle = 237
    local actual, _ = Room.movePlayer(-20)
    check(actual == -20, "Kante weg: actual -20")
    check(State.player.angle == 217, "Kante weg: Ende 217")
end

-- --- Test 56: Undo + G7-Rekonstruktion ------------------------------------
do
    State.init(makeG7Room())
    Room.init()
    Undo.clear()
    Room.movePlayer(17) -- S1 -> A, D1 schließt, Spieler (97) im Bogen -> pendingClose
    check(Room.shutters["D1"].pendingClose == true, "undo+G7: pendingClose vor Undo")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "undo+G7: S1 restauriert")
    check(State.player.angle == 80, "undo+G7: Position restauriert (80)")
    check(Room.shutters["D1"].collisionActive == false, "undo+G7: D1 wieder offen -> nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "undo+G7: pendingClose false")
end

-- --- Test 57: Ringtrennung ------------------------------------------------
do
    setup(makeRingRoom())
    local a1, _ = Room.movePlayer(100) -- outer 10 -> 110, kreuzt S1
    check(State.switchStates["S1"] == "A", "ring outer: S1 geändert")
    check(State.switchStates["S3"] == "B", "ring outer: S3 (inner) unverändert")

    State.init(makeRingRoom())
    State.setSwitch("S3", "A")
    Room.init()
    Undo.clear()
    State.player.ring = "inner"
    State.player.angle = 110
    Room.syncPhysicalShutters()
    local a2, _ = Room.movePlayer(-200) -- inner 110 -> 270, kreuzt S3 CCW
    check(State.switchStates["S3"] == "B", "ring inner: S3 geändert")
    check(State.switchStates["S1"] == "B", "ring inner: S1 (outer) unverändert")
end

-- --- Test 58: exakte Schalter-Endkante ------------------------------------
do
    setup(makeRoom())
    local a1, _ = Room.movePlayer(42) -- 10 -> 52, exakt auf S1-Austrittskante
    check(State.switchStates["S1"] == "A", "exakte Kante: S1 -> A")
    check(Undo.count() == 1, "exakte Kante: 1 Undo")
    check(a1 == 42, "exakte Kante: actual 42")
    check(State.player.angle == 52, "exakte Kante: Ende exakt 52")

    setup(makeRoom())
    local a2, _ = Room.movePlayer(41) -- 10 -> 51, minimal davor
    check(State.switchStates["S1"] == "B", "minimal davor: S1 bleibt B")
    check(Undo.count() == 0, "minimal davor: kein Undo")
    check(State.player.angle == 51, "minimal davor: Ende 51")
end

-- --- Test 59: Öffnen einer Blende während pendingClose -------------------
do
    State.init(makePendingCloseOpenRoom()) -- S1=A -> D1 logisch offen
    Room.init()
    Undo.clear()

    -- Ausgangszustand: D1 offen, kein Schließwunsch
    check(State.elementStates["D1"] == true, "open-pc: Ausgang D1 offen")
    check(Room.shutters["D1"].collisionActive == false, "open-pc: Ausgang nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "open-pc: Ausgang kein pendingClose")

    -- Phase 1: D1 logisch schließen (S1 -> B), Spieler (80) bleibt im Bogen
    -- [77,103]: G7 hält die Blende physisch offen -> pendingClose
    State.setSwitch("S1", "B")
    Room.syncPhysicalShutters()
    check(State.elementStates["D1"] == false, "open-pc: D1 logisch geschlossen")
    check(Room.shutters["D1"].collisionActive == false, "open-pc: G7 -> nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == true, "open-pc: pendingClose true")

    -- Phase 2: D1 über echten Schalterlauf wieder öffnen (S1 CW -> A)
    local a2, r2 = Room.movePlayer(80) -- 80 -> 160, S1 vollständig (Austritt 157)
    check(State.switchStates["S1"] == "A", "open-pc: S1 wieder A")
    check(State.elementStates["D1"] == true, "open-pc: D1 wieder logisch offen")
    check(Room.shutters["D1"].collisionActive == false, "open-pc: Öffnen -> nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == false, "open-pc: Öffnen hebt pendingClose auf")
    check(r2.blocked == false, "open-pc: nicht blockiert")
    check(a2 == 80, "open-pc: actual == wanted (80)")

    -- Phase 3: Bewegung durch den Blendenbogen weiterhin frei (volle Runde)
    local a3, r3 = Room.movePlayer(360) -- passiert D1-Bogen [77,103] frei
    check(a3 == 360, "open-pc: Durchquerung actual == wanted (360)")
    check(r3.blocked == false, "open-pc: Durchquerung nicht blockiert")
    check(State.player.angle == 160, "open-pc: Ende 160")
    check(State.elementStates["D1"] == true, "open-pc: D1 bleibt offen")
    check(Room.shutters["D1"].pendingClose == false, "open-pc: kein pendingClose erneut")
end

-- --- Test 60: klassischer Tunneling-Test CW ------------------------------
-- Blende 26° breit, gewünschtes Delta +80° (> Blendenbreite). Ohne Sweep
-- würde die Figur geometrisch vor die Blende und dahinter springen.
do
    setup(makeTunnelRoom()) -- S1=A -> D1 (outer@180, Bogen [167,193]) geschlossen
    local actual, result = Room.movePlayer(80) -- 90 -> 170 geplant
    check(actual == 77, "tunnel cw: actual 77 (< wanted 80)")
    check(State.player.angle == 167, "tunnel cw: Stopp an CW-Eintrittskante 167")
    check(result.blocked == true, "tunnel cw: blockiert")
    check(State.player.angle < 193, "tunnel cw: Spieler NICHT hinter der Blende")
end

-- --- Test 61: Tunneling CW extrem (+180°) --------------------------------
-- Ein noch deutlich größeres Delta darf ebenfalls nicht durchtunneln.
do
    setup(makeTunnelRoom())
    local actual, result = Room.movePlayer(180)
    check(actual == 77, "tunnel cw extrem: actual 77 (bei wanted 180)")
    check(State.player.angle == 167, "tunnel cw extrem: Stopp an 167")
    check(result.blocked == true, "tunnel cw extrem: blockiert")
end

-- --- Test 62: +720° mit geschlossener Blende -----------------------------
-- Eine geschlossene Blende im Weg darf auch ein +720°-Delta an der ERSTEN
-- Eintrittskante stoppen (kein vollständiger Umlauf, kein Durchtunneln).
do
    setup(makeTunnelRoom())
    local actual, result = Room.movePlayer(720)
    check(actual == 77, "tunnel cw +720: actual 77 (Stop an erster Kante)")
    check(State.player.angle == 167, "tunnel cw +720: Stopp an 167")
    check(result.blocked == true, "tunnel cw +720: blockiert")
end

-- --- Test 63: Tunneling CCW ----------------------------------------------
-- Gegenrichtung: gewünschtes Delta < -Blendenbreite stoppt an der
-- CCW-Eintrittskante (angle + shutterArcWidth/2 = 193).
do
    setup(makeTunnelRoom())
    State.player.angle = 250
    Room.syncPhysicalShutters()
    local actual, result = Room.movePlayer(-80) -- CCW zur CCW-Eintrittskante 193
    check(actual == -57, "tunnel ccw: actual -57 (wanted -80)")
    check(State.player.angle == 193, "tunnel ccw: Stopp an CCW-Eintrittskante 193")
    check(result.blocked == true, "tunnel ccw: blockiert")
end

-- G7-Pflichtfall H: Start innerhalb einer logisch geschlossenen Blende.
-- Der (synthetisch ungültige) Startzustand wird nicht als Falle gewertet:
-- Die Figur kann den Bogen verlassen, danach schließt die Blende.
local function makeStartInsideRoom()
    return {
        name = "StartInside",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {
            { id="S1", ring="outer", angle=0, symbol=1, onA="B1", onB="D1", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B0", angle=270, free=true },
            { id="B1", angle=45,  free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- --- Test 64: G7-Pflichtfall H – Start in geschlossener Blende -----------
do
    setup(makeStartInsideRoom()) -- S1=A -> D1 (outer@90, Bogen [77,103]) logisch geschlossen
    check(State.elementStates["D1"] == false, "start-in-blende: D1 logisch geschlossen")
    check(Room.shutters["D1"].collisionActive == false, "start-in-blende: nicht kollisionsaktiv")
    check(Room.shutters["D1"].pendingClose == true, "start-in-blende: pendingClose true")
    local actual, _ = Room.movePlayer(-40) -- 90 -> 50, verlässt den Bogen
    check(actual == -40, "start-in-blende: Austritt erlaubt (actual -40)")
    check(State.player.angle == 50, "start-in-blende: Ende 50")
    check(Room.shutters["D1"].collisionActive == true, "start-in-blende: danach geschlossen")
    check(Room.shutters["D1"].pendingClose == false, "start-in-blende: pendingClose gelöst")
    check(Undo.count() == 0, "start-in-blende: kein Undo")
end

-- --- Test 65: G7-Pflichtfall C – kein Wiedereintritt nach Schließen ------
-- G7 erlaubt nur das Verlassen, nicht späteres Wiedereintreten in die
-- logisch geschlossene Blende. Das Auflösen von pendingClose erzeugt keinen
-- zusätzlichen Undo-Eintrag.
do
    State.init(makeG7Room())
    Room.init()
    Undo.clear()
    Room.movePlayer(17) -- S1 -> A, D1 schließt, Spieler (97) im Bogen -> pendingClose
    check(Undo.count() == 1, "kein-wiedereintritt: 1 Undo (Schalterhandlung)")
    Room.movePlayer(43) -- 97 -> 140, verlässt D1 -> physisch geschlossen
    check(Room.shutters["D1"].collisionActive == true, "kein-wiedereintritt: D1 geschlossen")
    check(Room.shutters["D1"].pendingClose == false, "kein-wiedereintritt: kein pendingClose")
    -- Wiedereintritt CCW: Stopp an der Eintrittskante 103
    local actual, result = Room.movePlayer(-80) -- 140 -> CCW Richtung D1
    check(actual == -37, "kein-wiedereintritt: actual -37 (Stop an 103)")
    check(State.player.angle == 103, "kein-wiedereintritt: Stopp an CCW-Eintrittskante 103")
    check(result.blocked == true, "kein-wiedereintritt: blockiert")
    check(Undo.count() == 1, "kein-wiedereintritt: G7 erzeugt keinen zusätzlichen Undo")
end

TestReport.movement = { pass = pass, fail = fail }