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

-- --- Optionaler Widerstands-Faktor (Kurbel-Widerstand, Auftrag) ----------
-- computeDesiredDelta bleibt rein: der Dämpfungsfaktor wird als Parameter
-- übergeben (1 = normal). Nur der Kurbelanteil wird gedämpft, der D-Pad-
-- Anteil bleibt unberührt.
check(approx(Player.computeDesiredDelta(20, false, false, 0.02, 1.0), 10),
    "resistance: Faktor 1 -> normal (+10)")
check(approx(Player.computeDesiredDelta(20, false, false, 0.02, Config.bridgeResistanceFactor), 10 * Config.bridgeResistanceFactor),
    "resistance: Faktor <1 dämpft nur den Kurbelanteil")
check(approx(Player.computeDesiredDelta(-20, false, false, 0.02, Config.bridgeResistanceFactor), -10 * Config.bridgeResistanceFactor),
    "resistance: negativer Kurbelanteil wird symmetrisch gedämpft")
check(approx(Player.computeDesiredDelta(20, false, true, 0.02, Config.bridgeResistanceFactor),
    20 * Config.crankRatio * Config.bridgeResistanceFactor + 1.8),
    "resistance: D-Pad bleibt ungedämpft (Kurbel gedämpft)")
check(approx(Player.computeDesiredDelta(0, false, true, 0.02, Config.bridgeResistanceFactor), 1.8),
    "resistance: reines D-Pad nie gedämpft")
check(approx(Player.computeDesiredDelta(20, false, false, 0.02, nil), 10),
    "resistance: nil -> Faktor 1 (Abwärtskompatibilität)")

-- --- Player.bridgeResistanceFactor (lokale Widerstandszone vor der Brücke) -
-- Rein aus State gelesen: nur AKTIVE Brücken, nur in der Zone zwischen
-- dockRange und dockRange + bridgeResistanceRange VOR der Brücke (in
-- Bewegungsrichtung), und nur wenn der Player in deren Richtung fährt.
do
    local resRoom = {
        name = "Resistance",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 0, free = false } },
        gate = nil,
    }
    State.init(resRoom)
    -- B0 ist NICHT aktiv (kein freier Eintrag, kein Schalter aktiviert).
    State.player.ring = "outer"
    State.player.angle = 350 -- 10° VOR B0@0 (dockRange 12)
    check(Player.bridgeResistanceFactor(1) == 1,
        "resistance-zone: inaktive Brücke -> kein Widerstand")

    -- Brücke aktivieren (freie Brücke).
    State.elementStates["B0"] = true
    -- Von 350° CW zu B0@0 sind 10° -> noch im Dock (<= dockRange): dort greift
    -- KEIN Widerstand (die Schwelle liegt VOR dem Andocken).
    State.player.angle = 350
    check(Player.bridgeResistanceFactor(1) == 1,
        "resistance-zone: im Dock (<= dockRange) kein Widerstand")
    -- Zone: von 345° CW zu 0 sind 15° -> in (dockRange 12, dockRange+range 15]
    -- = exakt die inklusive Zonengrenze (bridgeResistanceRange 3).
    State.player.angle = 345
    check(Player.bridgeResistanceFactor(1) == Config.bridgeResistanceFactor,
        "resistance-zone: in der Zone / Zonengrenze inklusiv -> gedämpft")
    -- Gegenrichtung (CCW von 345 weg von 0): dist norm(345-0)=345 -> kein Widerstand.
    check(Player.bridgeResistanceFactor(-1) == 1,
        "resistance-zone: Wegfahren -> sofort normal")
    -- Außerhalb der Zone (dist 20 > 15).
    State.player.angle = 340
    check(Player.bridgeResistanceFactor(1) == 1,
        "resistance-zone: außerhalb der Zone -> normal")
    -- Knapp außerhalb der Zonengrenze (dist 16 > 15 -> normal).
    State.player.angle = 344
    check(Player.bridgeResistanceFactor(1) == 1,
        "resistance-zone: knapp außerhalb der Grenze -> normal")
end

-- --- Player.bridgeResistanceFactor am GATE (gleiche Schwelle) ------------
-- Center-Bridge-Fix: die Kernbrücke (Gate) fühlt sich wie jede andere Brücke
-- an — dieselbe leichte Kurbel-Schwelle kurz vor dem aktiven Ausgang.
do
    local gateResRoom = {
        name = "GateResistance",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 0 },
        switches = {},
        shutters = {},
        bridges = {},
        gate = { id = "T", angle = 0, free = true },
    }
    State.init(gateResRoom)
    State.player.ring = "inner"
    -- Im Dock (<= dockRange): kein Widerstand.
    State.player.angle = 350 -- 10° CW vor T@0 -> im Dock
    check(Player.bridgeResistanceFactor(1) == 1,
        "gate-res: im Dock kein Widerstand")
    -- In der Zone (dist 15 in (12, 18]): gedämpft.
    State.player.angle = 345
    check(Player.bridgeResistanceFactor(1) == Config.bridgeResistanceFactor,
        "gate-res: Zone vor dem Ausgang -> gedämpft")
    -- Außerhalb der Zone.
    State.player.angle = 340
    check(Player.bridgeResistanceFactor(1) == 1,
        "gate-res: außerhalb der Zone -> normal")
    -- Falscher Ring (outer): keine Gate-Schwelle.
    State.player.ring = "outer"
    State.player.angle = 345
    check(Player.bridgeResistanceFactor(1) == 1,
        "gate-res: falscher Ring -> kein Widerstand")
end

TestReport.player = { pass = pass, fail = fail }