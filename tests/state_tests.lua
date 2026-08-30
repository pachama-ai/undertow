-- Tests für source/core/state.lua (globale Tabelle State).
-- Verwendet ausschließlich synthetische Raumtabellen, keine echten Level.
-- Erwartet, dass core/state per import geladen wurde (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.state gesammelt; die aggregierte
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

-- Synthetischer Raum: 2 Schalter, 2 Blenden, 1 freie + 2 gesteuerte Brücken,
-- 1 freies Gate. Erfüllt alle Validator-Invarianten.
local function makeRoom()
    return {
        name = "Testraum",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=90,  symbol=1, onA="B1", onB="D1", state="B" },
            { id="S2", ring="outer", angle=180, symbol=2, onA="D2", onB="B2", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=315 },
            { id="D2", ring="inner", angle=45  },
        },
        bridges = {
            { id="B0", angle=270, free=true  },
            { id="B1", angle=135, free=false },
            { id="B2", angle=90,  free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
end

-- Zweiter synthetischer Raum mit anderer Struktur (kein S1, anderes Gate).
local function makeRoom2()
    return {
        name = "Testraum 2",
        rings = { outer = 5, inner = 4 },
        start = { ring = "inner", angle = 120 },
        switches = {
            { id="X1", ring="inner", angle=200, symbol=1, onA="DX1", onB="BX1", state="A" },
        },
        shutters = {
            { id="DX1", ring="inner", angle=300 },
        },
        bridges = {
            { id="BX0", angle=90, free=true },
            { id="BX1", angle=45, free=false },
        },
        gate = { id="TG", angle=0, free=true },
    }
end

-- --- Test 1: Initialisierung --------------------------------------------
do
    State.init(makeRoom())
    check(State.switchStates["S1"] == "B", "init: S1 Startzustand B")
    check(State.switchStates["S2"] == "A", "init: S2 Startzustand A")
    check(State.player.ring == "outer", "init: Spielerring outer")
    check(State.player.angle == 0, "init: Spielerwinkel 0")
    check(State.elementStates["B1"] == false, "init: B1 inaktiv (S1=B)")
    check(State.elementStates["D1"] == true, "init: D1 offen (S1=B)")
    check(State.elementStates["D2"] == true, "init: D2 offen (S2=A)")
    check(State.elementStates["B2"] == false, "init: B2 eingefahren (S2=A)")
    check(State.elementStates["B0"] == true, "init: B0 frei aktiv")
    check(State.elementStates["T"] == true, "init: T frei aktiv")
end

-- --- Test 2: Zustand A ---------------------------------------------------
do
    State.init(makeRoom())
    local changed = State.setSwitch("S1", "A")
    check(changed == true, "S1->A: changed")
    check(State.elementStates["B1"] == true, "S1->A: B1 aktiv")
    check(State.elementStates["D1"] == false, "S1->A: D1 geschlossen")
end

-- --- Test 3: Zustand B ---------------------------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    State.setSwitch("S1", "B")
    check(State.elementStates["B1"] == false, "S1->B: B1 eingefahren")
    check(State.elementStates["D1"] == true, "S1->B: D1 offen")
end

-- --- Test 4: freie Brücke bleibt aktiv -----------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    State.setSwitch("S1", "B")
    State.setSwitch("S2", "B")
    check(State.elementStates["B0"] == true, "B0 bleibt frei aktiv nach Schalterwechseln")
end

-- --- Test 5: freies Gate bleibt aktiv ------------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    State.setSwitch("S2", "B")
    check(State.elementStates["T"] == true, "T bleibt frei aktiv nach Schalterwechseln")
end

-- --- Test 6: Nicht-Toggle ------------------------------------------------
do
    State.init(makeRoom())
    local c1, e1 = State.setSwitch("S1", "A")
    local c2, e2 = State.setSwitch("S1", "A")
    check(c1 == true, "1. setSwitch S1->A: changed true")
    check(c2 == false, "2. setSwitch S1->A: changed false (Nicht-Toggle)")
    check(#e2 == 0, "Nicht-Toggle: leere Elementliste")
end

-- --- Test 7: Change-Report -----------------------------------------------
do
    State.init(makeRoom())
    local changed, els = State.setSwitch("S1", "A")
    check(changed == true, "Change-Report: changed true")
    check(#els == 2, "Change-Report: genau 2 Änderungen")
    if #els >= 2 then
        check(els[1].id == "D1" and els[1].from == true and els[1].to == false,
            "Change-Report[1] = D1 true->false (Levelreihenfolge)")
        check(els[2].id == "B1" and els[2].from == false and els[2].to == true,
            "Change-Report[2] = B1 false->true (Levelreihenfolge)")
    end
end

-- --- Test 8: unbekannter Schalter ----------------------------------------
do
    State.init(makeRoom())
    local ok = pcall(State.setSwitch, "NICHT_DA", "A")
    check(ok == false, "unbekannter Schalter schlägt fehl")
end

-- --- Test 9: ungültiger Zustand ------------------------------------------
do
    State.init(makeRoom())
    local ok = pcall(State.setSwitch, "S1", "C")
    check(ok == false, "ungültiger Zustand 'C' schlägt fehl")
end

-- --- Test 10: Snapshot-Unabhängigkeit ------------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    local snap = State.snapshot()
    State.setSwitch("S1", "B")
    State.setSwitch("S2", "B")
    State.player.ring = "inner"
    State.player.angle = 180
    check(snap.switchStates["S1"] == "A", "Snapshot: S1 bleibt A")
    check(snap.switchStates["S2"] == "A", "Snapshot: S2 bleibt A")
    check(snap.player.ring == "outer", "Snapshot: Spielerring bleibt outer")
    check(snap.player.angle == 0, "Snapshot: Spielerwinkel bleibt 0")
    check(snap.elementStates["B1"] == true, "Snapshot: B1 bleibt true")
    check(snap.elementStates["D1"] == false, "Snapshot: D1 bleibt false")
end

-- --- Test 11: Restore -----------------------------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    State.player.ring = "outer"
    State.player.angle = 0
    local snap = State.snapshot()
    -- Zustand und Position verändern
    State.setSwitch("S1", "B")
    State.setSwitch("S2", "B")
    State.player.ring = "inner"
    State.player.angle = 90
    -- Restore
    State.restore(snap)
    check(State.player.ring == "outer", "Restore: Spielerring zurück")
    check(State.player.angle == 0, "Restore: Spielerwinkel zurück")
    check(State.switchStates["S1"] == "A", "Restore: S1 zurück")
    check(State.switchStates["S2"] == "A", "Restore: S2 zurück")
    -- Elementzustände korrekt neu abgeleitet (S1=A, S2=A, B0/T frei)
    check(State.elementStates["B1"] == true, "Restore: B1 abgeleitet true")
    check(State.elementStates["D1"] == false, "Restore: D1 abgeleitet false")
    check(State.elementStates["D2"] == true, "Restore: D2 abgeleitet true")
    check(State.elementStates["B2"] == false, "Restore: B2 abgeleitet false")
    check(State.elementStates["B0"] == true, "Restore: B0 frei true")
    check(State.elementStates["T"] == true, "Restore: T frei true")
end

-- --- Test 12: Raum-Neuinitialisierung ------------------------------------
do
    State.init(makeRoom())
    State.setSwitch("S1", "A")
    State.player.ring = "inner"
    State.player.angle = 200
    State.init(makeRoom2())
    check(State.switchStates["X1"] == "A", "Neuinit: Raum2 X1=A")
    check(State.switchStates["S1"] == nil, "Neuinit: S1 aus Raum1 nicht mehr vorhanden")
    check(State.player.ring == "inner", "Neuinit: Raum2 Spielerring")
    check(State.player.angle == 120, "Neuinit: Raum2 Spielerwinkel")
    check(State.elementStates["DX1"] == true, "Neuinit: Raum2 DX1 offen")
    check(State.elementStates["BX1"] == false, "Neuinit: Raum2 BX1 eingefahren")
    check(State.elementStates["B1"] == nil, "Neuinit: B1 aus Raum1 nicht mehr vorhanden")
end

-- --- Test 13: Leveldaten bleiben unverändert ------------------------------
do
    local room = makeRoom()
    local before = deepCopy(room)
    State.init(room)
    State.setSwitch("S1", "A")
    State.setSwitch("S1", "B")
    State.setSwitch("S2", "B")
    State.player.angle = 77
    local snap = State.snapshot()
    State.restore(snap)
    check(room.name == before.name, "Leveldaten: name unverändert")
    check(room.start.ring == before.start.ring, "Leveldaten: start.ring unverändert")
    check(room.start.angle == before.start.angle, "Leveldaten: start.angle unverändert")
    check(room.switches[1].state == before.switches[1].state, "Leveldaten: S1.state unverändert")
    check(room.switches[1].onA == before.switches[1].onA, "Leveldaten: S1.onA unverändert")
    check(room.switches[2].angle == before.switches[2].angle, "Leveldaten: S2.angle unverändert")
    check(room.shutters[1].ring == before.shutters[1].ring, "Leveldaten: D1.ring unverändert")
    check(room.bridges[1].free == before.bridges[1].free, "Leveldaten: B0.free unverändert")
    check(room.gate.free == before.gate.free, "Leveldaten: gate.free unverändert")
end

-- --- Test 14: Einmal-Mechanik (oneShot-Schalter + verbrauchte Brücke) ------
do
    local room = {
        name = "OneShot",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="B1", onB="D1", state="B", oneShot=true },
        },
        shutters = { { id="D1", ring="inner", angle=180 } },
        bridges = {
            { id="B0", angle=270, free=true },
            { id="B1", angle=90,  free=false, oneShot=true },
        },
        gate = { id="T", angle=180, free=true },
    }
    State.init(room)
    check(State.consumedSwitches["S1"] == nil and State.consumedBridges["B1"] == nil,
        "oneshot-state: frisch unbenutzt")

    -- Einmal-Schalter: erste echte Änderung sperrt ihn dauerhaft.
    local ch1 = State.setSwitch("S1", "A")
    check(ch1 == true, "oneshot-state: S1 erste Änderung")
    check(State.consumedSwitches["S1"] == true, "oneshot-state: S1 gesperrt")
    local ch2 = State.setSwitch("S1", "B")
    check(ch2 == false, "oneshot-state: S1 gesperrt -> kein Flip zurück")
    check(State.switchStates["S1"] == "A", "oneshot-state: S1 bleibt A")

    -- Verbrauchte Brücke: elementStates wird dauerhaft false erzwungen, auch
    -- wenn der (gesperrte) Schalter sie aktivieren würde.
    State.consumeBridge("B1")
    check(State.consumedBridges["B1"] == true, "oneshot-state: B1 verbraucht")
    check(State.elementStates["B1"] == false, "oneshot-state: B1 elementState false")

    -- Snapshot/Restore: Verbrauchsmengen sind Teil des Snapshots.
    local snap = State.snapshot()
    check(snap.consumedSwitches["S1"] == true and snap.consumedBridges["B1"] == true,
        "oneshot-state: Snapshot enthält Verbrauch")
    State.consumedSwitches["S1"] = nil
    State.consumedBridges["B1"] = nil
    State.restore(snap)
    check(State.consumedSwitches["S1"] == true, "oneshot-state: Restore stellt Sperre her")
    check(State.consumedBridges["B1"] == true, "oneshot-state: Restore stellt Verbrauch her")
    check(State.elementStates["B1"] == false, "oneshot-state: B1 bleibt kollabiert nach Restore")
end

TestReport.state = { pass = pass, fail = fail }