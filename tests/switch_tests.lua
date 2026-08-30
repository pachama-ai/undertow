-- Tests für source/world/switch.lua (globale Tabelle Switch): reine
-- Schalterregeln (Kanten, Zielzustand, Bogen-Zugehörigkeit).
-- Keine State-Mutation, kein Sweep, kein Undo, KEIN Traversal-Zustand — die
-- geschwindigkeitsunabhängige vollständige Durchquerung (Release-Fix 1)
-- testen switch_traversal_tests.lua / movement_tests.lua / input_tests.lua.
-- Erwartet, dass core/config, core/geometry und world/switch per import
-- geladen wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.switch gesammelt; die aggregierte
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

-- Synthetischer Schalter (Bogenbreite Config.switchArcWidth = 14).
local sw45 = { id = "S1", ring = "outer", angle = 45, symbol = 1, onA = "B1", onB = "D1", state = "B" }

-- --- Test 1: Austrittskante CW -------------------------------------------
check(Switch.getExitAngle(sw45, 1) == 52, "exit cw: 45 + 7 = 52")

-- --- Test 2: Austrittskante CCW ------------------------------------------
check(Switch.getExitAngle(sw45, -1) == 38, "exit ccw: 45 - 7 = 38")

-- --- Test 3: Wraparound --------------------------------------------------
local sw358 = { id = "S2", ring = "outer", angle = 358, symbol = 2, onA = "B1", onB = "D1", state = "B" }
check(Switch.getExitAngle(sw358, 1) == 5, "wrap cw: 358 + 7 -> 5")
local sw2 = { id = "S3", ring = "outer", angle = 2, symbol = 3, onA = "B1", onB = "D1", state = "B" }
check(Switch.getExitAngle(sw2, -1) == 355, "wrap ccw: 2 - 7 -> 355")

-- --- Test 4: Zielzustand + ungültige Richtungen --------------------------
check(Switch.getTargetState(1) == "A", "target: +1 -> A")
check(Switch.getTargetState(-1) == "B", "target: -1 -> B")
local ok0, _ = pcall(function() Switch.getTargetState(0) end)
check(ok0 == false, "target: Richtung 0 -> Fehler")
local ok2, _ = pcall(function() Switch.getTargetState(2) end)
check(ok2 == false, "target: Richtung 2 -> Fehler")
local okBad, _ = pcall(function() Switch.getExitAngle(sw45, 0) end)
check(okBad == false, "exit: Richtung 0 -> Fehler")

-- --- Test 5: Bogen-Zugehörigkeit (isInsideArc) ---------------------------
-- Reine Bogen-Geometrie: strikt innerhalb [38,52] (Kanten ausgeschlossen).
check(Switch.isInsideArc(45, sw45) == true, "inside: Mitte 45 -> true")
check(Switch.isInsideArc(40, sw45) == true, "inside: 40 (nahe Eintritt) -> true")
check(Switch.isInsideArc(51, sw45) == true, "inside: 51 (nahe Austritt) -> true")
check(Switch.isInsideArc(38, sw45) == false, "inside: exakt Eintrittskante 38 -> false")
check(Switch.isInsideArc(52, sw45) == false, "inside: exakt Austrittskante 52 -> false")
check(Switch.isInsideArc(37, sw45) == false, "inside: 37 (davor) -> false")
check(Switch.isInsideArc(53, sw45) == false, "inside: 53 (danach) -> false")

-- --- Test 6: Bogen-Zugehörigkeit mit Wraparound --------------------------
-- Schalter über 0°: Bogen [351,5] für sw358.
check(Switch.isInsideArc(0, sw358) == true, "inside wrap: 0 -> true")
check(Switch.isInsideArc(359, sw358) == true, "inside wrap: 359 -> true")
check(Switch.isInsideArc(4, sw358) == true, "inside wrap: 4 -> true")
check(Switch.isInsideArc(351, sw358) == false, "inside wrap: exakt Kante 351 -> false")
check(Switch.isInsideArc(5, sw358) == false, "inside wrap: exakt Kante 5 -> false")
check(Switch.isInsideArc(350, sw358) == false, "inside wrap: 350 (davor) -> false")
check(Switch.isInsideArc(6, sw358) == false, "inside wrap: 6 (danach) -> false")

-- --- Test 7: Kanten über 0° bleiben konsistent ----------------------------
check(Switch.getExitAngle(sw358, 1) == 5, "wrap cw: 358 + 7 -> 5")
check(Switch.getEntryAngle(sw358, -1) == 5, "wrap ccw: Eintritt 5")
check(Switch.getExitAngle(sw358, -1) == 351, "wrap ccw: Austritt 351")
check(Switch.getEntryAngle(sw358, 1) == 351, "wrap cw: Eintritt 351")

TestReport.switch = { pass = pass, fail = fail }
