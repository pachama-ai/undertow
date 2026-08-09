-- Tests für source/world/player.lua (globale Tabelle Player).
-- Testet ausschließlich die reine Berechnung Player.computeDesiredDelta mit
-- synthetischen Eingaben (keine echten Playdate-Hardwarezustände).
-- Erwartet, dass core/config, core/state und world/player per import geladen
-- wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.player gesammelt; die aggregierte
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

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-9)
end

-- --- Kurbel (crankRatio = 0.5) -------------------------------------------
check(Player.computeDesiredDelta(20, false, false, 0.02) == 10, "Kurbel +20 -> +10")
check(Player.computeDesiredDelta(-20, false, false, 0.02) == -10, "Kurbel -20 -> -10")

-- --- Keine Eingabe -------------------------------------------------------
check(Player.computeDesiredDelta(0, false, false, 0.02) == 0, "keine Eingabe -> 0")

-- --- D-Pad bei dt = 0.02 (dpadSpeed = 90 -> 1.8) -------------------------
check(approx(Player.computeDesiredDelta(0, false, true, 0.02), 1.8), "D-Pad rechts -> +1.8")
check(approx(Player.computeDesiredDelta(0, true, false, 0.02), -1.8), "D-Pad links -> -1.8")

-- --- Links + Rechts gleichzeitig -----------------------------------------
check(Player.computeDesiredDelta(0, true, true, 0.02) == 0, "links+rechts -> 0 (D-Pad neutral)")
check(Player.computeDesiredDelta(20, true, true, 0.02) == 10, "Kurbel +20 + links+rechts -> +10")

-- --- Kombinationen -------------------------------------------------------
check(approx(Player.computeDesiredDelta(20, false, true, 0.02), 11.8), "Kurbel +20 + rechts -> +11.8")
check(approx(Player.computeDesiredDelta(20, true, false, 0.02), 8.2), "Kurbel +20 + links -> +8.2")

-- --- Große signed Deltas (keine Normalisierung) --------------------------
check(Player.computeDesiredDelta(400, false, false, 0.02) == 200, "Kurbel +400 -> +200 (>180, unverändert)")
check(Player.computeDesiredDelta(-400, false, false, 0.02) == -200, "Kurbel -400 -> -200 (<-180, unverändert)")
check(Player.computeDesiredDelta(800, false, false, 0.02) == 400, "Kurbel +800 -> +400 (>360, unverändert)")
check(Player.computeDesiredDelta(-800, false, false, 0.02) == -400, "Kurbel -800 -> -400 (<-360, unverändert)")

-- --- State bleibt unverändert --------------------------------------------
do
    State.player.ring = "inner"
    State.player.angle = 123
    local d = Player.computeDesiredDelta(20, true, false, 0.02)
    check(State.player.ring == "inner", "State: ring unverändert (inner)")
    check(State.player.angle == 123, "State: angle unverändert (123)")
    check(approx(d, 8.2), "State-Test: Berechnung liefert weiterhin +8.2")
end

TestReport.player = { pass = pass, fail = fail }