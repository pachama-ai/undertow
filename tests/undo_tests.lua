-- Tests für source/core/undo.lua (globale Tabelle Undo).
-- Nutzt State mit synthetischen Raumtabellen (keine echten Level).
-- Erwartet, dass core/state und core/undo per import geladen wurden
-- (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.undo gesammelt; die aggregierte
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

-- Synthetischer Raum (wie in state_tests): 2 Schalter, 2 Blenden,
-- 1 freie + 2 gesteuerte Brücken, 1 freies Gate.
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

-- --- Test 1: leerer Stack -------------------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    check(Undo.count() == 0, "leerer Stack: count 0")
    check(Undo.undo() == false, "leerer Stack: undo false")
    check(State.player.angle == 0, "leerer Stack: State unverändert (Winkel)")
    check(State.switchStates["S1"] == "B", "leerer Stack: State unverändert (S1)")
end

-- --- Test 2: ein Snapshot -------------------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    Undo.push(State.snapshot())
    State.setSwitch("S1", "A")
    State.setSwitch("S2", "B")
    State.player.ring = "inner"
    State.player.angle = 90
    check(Undo.count() == 1, "ein Snapshot: count 1 vor undo")
    local restored = Undo.undo()
    check(restored == true, "ein Snapshot: undo true")
    check(Undo.count() == 0, "ein Snapshot: count 0 nach undo")
    check(State.switchStates["S1"] == "B", "ein Snapshot: S1 zurück")
    check(State.switchStates["S2"] == "A", "ein Snapshot: S2 zurück")
    check(State.elementStates["B1"] == false, "ein Snapshot: B1 abgeleitet zurück")
    check(State.elementStates["D1"] == true, "ein Snapshot: D1 abgeleitet zurück")
    check(State.elementStates["D2"] == true, "ein Snapshot: D2 abgeleitet zurück")
    check(State.player.ring == "outer", "ein Snapshot: Ring zurück")
    check(State.player.angle == 0, "ein Snapshot: Winkel zurück")
end

-- --- Test 3: kritische Position-vor-Schalter-Regel ------------------------
do
    State.init(makeRoom())
    Undo.clear()
    State.player.angle = 40          -- Frame-Start bei 40°
    local frameStart = State.snapshot()  -- Snapshot bei 40° (Schalter bei 45°)
    Undo.push(frameStart)
    State.player.angle = 50          -- Spieler fährt auf/über 45°
    State.setSwitch("S1", "A")       -- Schalter ändert Zustand
    local restored = Undo.undo()
    check(restored == true, "Position-vor-Schalter: undo true")
    check(State.player.angle == 40, "Position-vor-Schalter: angle zurück auf 40 (nicht 45/50)")
    check(State.switchStates["S1"] == "B", "Position-vor-Schalter: S1 zurück")
end

-- --- Test 4: mehrere Schritte vollständig zurückrollen --------------------
do
    State.init(makeRoom())
    Undo.clear()
    -- Handlung 1
    Undo.push(State.snapshot())
    State.setSwitch("S1", "A")
    State.player.angle = 60
    -- Handlung 2
    Undo.push(State.snapshot())
    State.setSwitch("S2", "B")
    State.player.ring = "inner"
    -- Handlung 3
    Undo.push(State.snapshot())
    State.setSwitch("S1", "B")
    State.player.angle = 180
    -- Rückrollen: 3 -> nach Handlung 2, 2 -> nach Handlung 1, 1 -> Ausgang
    local u1 = Undo.undo()
    check(u1 == true, "Rückrollen: undo 1 true")
    check(State.switchStates["S1"] == "A" and State.switchStates["S2"] == "B", "Rückrollen: nach Handlung 2 (S1=A, S2=B)")
    check(State.player.ring == "inner" and State.player.angle == 60, "Rückrollen: Position nach Handlung 2")
    local u2 = Undo.undo()
    check(u2 == true, "Rückrollen: undo 2 true")
    check(State.switchStates["S1"] == "A" and State.switchStates["S2"] == "A", "Rückrollen: nach Handlung 1 (S1=A, S2=A)")
    check(State.player.ring == "outer" and State.player.angle == 60, "Rückrollen: Position nach Handlung 1")
    local u3 = Undo.undo()
    check(u3 == true, "Rückrollen: undo 3 true")
    check(State.switchStates["S1"] == "B" and State.switchStates["S2"] == "A", "Rückrollen: Ausgang (S1=B, S2=A)")
    check(State.player.ring == "outer" and State.player.angle == 0, "Rückrollen: Ausgangsposition")
    check(Undo.count() == 0, "Rückrollen: Stack leer")
end

-- --- Test 5: zwei Schalter in einem Frame ---------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    local frameStart = State.snapshot()
    Undo.push(frameStart)            -- nur einmal beim ersten Schalterwechsel
    State.setSwitch("S1", "A")
    State.setSwitch("S2", "B")
    check(Undo.count() == 1, "zwei Schalter im Frame: genau 1 Undo")
    local restored = Undo.undo()
    check(restored == true, "zwei Schalter im Frame: undo true")
    check(State.switchStates["S1"] == "B", "zwei Schalter im Frame: S1 zurück")
    check(State.switchStates["S2"] == "A", "zwei Schalter im Frame: S2 zurück")
    check(State.elementStates["B1"] == false, "zwei Schalter im Frame: B1 abgeleitet")
    check(State.elementStates["D2"] == true, "zwei Schalter im Frame: D2 abgeleitet")
    check(State.player.ring == "outer" and State.player.angle == 0, "zwei Schalter im Frame: Position vom Frame-Beginn")
end

-- --- Test 6: wirkungsloser Schalterkontakt --------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    -- S1 steht bereits auf B
    local changed = State.setSwitch("S1", "B")
    check(changed == false, "wirkungsloser Kontakt: changed false")
    if changed then
        Undo.push(State.snapshot())
    end
    check(Undo.count() == 0, "wirkungsloser Kontakt: kein Undo-Eintrag")
end

-- --- Test 7: Stack-Reihenfolge (LIFO) -------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    Undo.push(State.snapshot())      -- A: S1=B, angle 0
    State.setSwitch("S1", "A")
    State.player.angle = 30
    Undo.push(State.snapshot())      -- B: S1=A, angle 30
    State.setSwitch("S1", "B")
    State.player.angle = 60
    Undo.push(State.snapshot())      -- C: S1=B, angle 60
    State.player.angle = 90
    check(Undo.count() == 3, "LIFO: count 3")
    local u1 = Undo.undo()
    check(u1 == true and State.player.angle == 60 and State.switchStates["S1"] == "B", "LIFO: undo1 -> C")
    local u2 = Undo.undo()
    check(u2 == true and State.player.angle == 30 and State.switchStates["S1"] == "A", "LIFO: undo2 -> B")
    local u3 = Undo.undo()
    check(u3 == true and State.player.angle == 0 and State.switchStates["S1"] == "B", "LIFO: undo3 -> A")
    local u4 = Undo.undo()
    check(u4 == false, "LIFO: leer -> false")
end

-- --- Test 8: 64-Einträge-Grenze -------------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    for i = 1, 64 do
        State.player.angle = i
        Undo.push(State.snapshot())
    end
    check(Undo.count() == 64, "Grenze: count 64")
    State.player.angle = 65
    Undo.push(State.snapshot())
    check(Undo.count() == 64, "Grenze: nach 65. Push weiterhin 64")
    -- Vollständig zurückrollen: die älteste verbleibende Position muss
    -- Snapshot 2 sein (Snapshot 1 wurde verworfen).
    local lastAngle = nil
    for i = 1, 64 do
        if Undo.undo() then
            lastAngle = State.player.angle
        end
    end
    check(lastAngle == 2, "Grenze: älteste verbleibende Position ist 2 (nicht 1)")
    check(Undo.count() == 0, "Grenze: nach 64 Undos leer")
end

-- --- Test 9: clear() ------------------------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    Undo.push(State.snapshot())
    Undo.push(State.snapshot())
    Undo.push(State.snapshot())
    check(Undo.count() == 3, "clear: count 3 vor clear")
    Undo.clear()
    check(Undo.count() == 0, "clear: count 0 nach clear")
    check(Undo.undo() == false, "clear: undo false")
    check(State.player.angle == 0, "clear: State unverändert (Winkel)")
end

-- --- Test 10: Snapshot-Isolation ------------------------------------------
do
    State.init(makeRoom())
    Undo.clear()
    State.player.angle = 40
    local frameStart = State.snapshot()   -- S1=B, angle 40
    Undo.push(frameStart)                 -- interne Kopie wird gespeichert
    State.setSwitch("S1", "A")            -- Zustand ändern
    State.player.angle = 90
    -- Aufrufer-Seite mutiert die lokale Snapshot-Tabelle (versehentlich)
    frameStart.switchStates["S1"] = "A"   -- falscher Zustand, falls keine Kopie
    frameStart.player.angle = 999
    local restored = Undo.undo()
    check(restored == true, "Isolation: undo true")
    check(State.switchStates["S1"] == "B", "Isolation: S1=B (nicht die mutierte A)")
    check(State.player.angle == 40, "Isolation: angle 40 (nicht 999)")
    check(State.elementStates["B1"] == false, "Isolation: B1 abgeleitet false")
    check(State.elementStates["D1"] == true, "Isolation: D1 abgeleitet true")
end

TestReport.undo = { pass = pass, fail = fail }