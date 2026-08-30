-- Tests für source/ui/transition.lua (Abschlussphase B): Outro nach Raum 7.
-- Reine Präsentationslogik: Phasenfolge (R1 dissolve -> Core expand -> Iris
-- open -> Hold -> Finish), Timing (Sekunden + dt, große dt mit Restübernahme,
-- deterministisch), Reset, Read-only (kein Gameplay-State), Geometrie-Erfassung
-- aus Camera/Config. Der Gate->Outro->Menü-Lebenszyklus liegt im Composition
-- Root (main.lua) und wird im Produktions-Smoke End-to-End geprüft.
--
-- Erwartet, dass core/config, core/geometry, ui/camera und ui/transition per
-- import geladen wurden (siehe tools/run_tests.ps1). Ergebnis in
-- TestReport.transition.

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

-- Dauern aus Config (benannte Werte, Punkt 38).
local D0 = Config.outroRingDissolveDuration -- 1.5
local D1 = Config.outroCoreExpandDuration  -- 1.5
local D2 = Config.outroIrisDuration        -- 1.2
local D3 = Config.outroHoldDuration        -- 0.8
local TOTAL = D0 + D1 + D2 + D3            -- 5.0

-- --- 1) initial idle ----------------------------------------------------------
Transition.reset()
check(Transition.isActive() == false, "tr: initial inaktiv")
check(Transition.isFinished() == false, "tr: initial nicht finished")
check(Transition.getPhase() == nil, "tr: initial keine Phase")
check(Transition.getPhaseProgress() == nil, "tr: initial kein Fortschritt")
check(approx(Transition.getTotalDuration(), TOTAL, 1e-9),
    "tr: Gesamtdauer = Summe aller Phasen")

-- --- 2) Geometrie-Erfassung (Raum 7) ------------------------------------------
Camera.init(1) -- Room-7-outer (Finalraum 1/0)
Transition.reset()
Transition.startOutro(7, 1, 0)
check(Transition.isActive() == true, "tr: startOutro -> aktiv")
check(Transition.isFinished() == false, "tr: startOutro -> nicht finished")
check(Transition.getPhase() == Transition.PHASE_R1_DISSOLVE,
    "tr: startOutro -> Phase R1_DISSOLVE")
check(Transition.getPhaseProgress() == 0, "tr: startOutro -> Zeit 0")
check(Transition.outerR == Config.outerRadius, "tr: outerR = 104 (Camera Room-7)")
check(Transition.innerR == Config.innerRadius, "tr: innerR = 68 (Camera Room-7)")
check(Transition.coreStartR == Config.coreRadius + 6 * Config.coreGrowthPerRoom,
    "tr: coreStartR = Room-7-Kern (61)")
check(Transition.cx == Config.centerX and Transition.cy == Config.centerY,
    "tr: Zentrum aus Config")

-- --- 3) kein früher Finish ------------------------------------------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
local f = Transition.update(D0 - 0.05)
check(f == false, "tr: knapp vor R1-Ende nicht finished")
check(Transition.getPhase() == Transition.PHASE_R1_DISSOLVE,
    "tr: noch Phase R1_DISSOLVE")

-- --- 4) Phasenfolge -------------------------------------------------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
check(Transition.update(D0) == false, "tr: nach R1 keine Finish")
check(Transition.getPhase() == Transition.PHASE_CORE_EXPAND,
    "tr: Phase CORE_EXPAND nach R1")
check(Transition.getPhaseProgress() == 0, "tr: Core-Phase bei Zeit 0")
check(Transition.update(D1) == false, "tr: nach Core keine Finish")
check(Transition.getPhase() == Transition.PHASE_IRIS_OPEN,
    "tr: Phase IRIS_OPEN nach Core")
check(Transition.update(D2) == false, "tr: nach Iris keine Finish")
check(Transition.getPhase() == Transition.PHASE_HOLD, "tr: Phase HOLD nach Iris")
check(Transition.update(D3 - 0.001) == false, "tr: knapp vor Hold-Ende nicht finished")
check(Transition.update(0.001) == true, "tr: Hold zu Ende -> finished")
check(Transition.isActive() == false, "tr: nach Finish inaktiv")
check(Transition.isFinished() == true, "tr: nach Finish finished")
check(Transition.getPhase() == Transition.PHASE_FINISHED, "tr: Phase FINISHED")

-- --- 5) große dt: mehrere Phasen überspringen, Restübernahme --------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
check(Transition.update(D0 + D1 + 0.5) == false,
    "tr: großes dt (R1+Core+0,5 s) kein Finish")
check(Transition.getPhase() == Transition.PHASE_IRIS_OPEN,
    "tr: großes dt -> Iris-Phase")
check(approx(Transition.getPhaseProgress(), 0.5 / D2, 1e-6),
    "tr: Rest 0,5 s in Iris übernommen")
-- Großes dt über das gesamte Outro -> finished in einem Schritt.
Transition.reset()
Transition.startOutro(6, 2, 1)
check(Transition.update(TOTAL + 0.5) == true,
    "tr: ein großes dt über Gesamtdauer -> finished")
check(Transition.isFinished() == true, "tr: nach Gesamt-dt finished")

-- --- 6) deterministisch (viele kleine dt == wenige große dt) ---------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
for _ = 1, 50 do
    Transition.update(0.05)
end
local phaseSmall = Transition.getPhase()
local progSmall = Transition.getPhaseProgress()
Transition.reset()
Transition.startOutro(6, 2, 1)
Transition.update(0.05 * 50)
check(phaseSmall == Transition.getPhase(), "tr: deterministisch gleiche Phase")
check(approx(progSmall or 0, Transition.getPhaseProgress() or 0, 1e-6),
    "tr: deterministisch gleicher Fortschritt")

-- --- 7) Reset ----------------------------------------------------------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
-- Knapp vor der Gesamtdauer (mit Sicherheitsabstand gegen Float-ULP an der
-- exakten Phasengrenze): noch nicht finished.
check(Transition.update(TOTAL - 0.01) == false, "tr: knapp vor Gesamtende nicht finished")
check(Transition.update(0.02) == true, "tr: letzte Restzeit -> finished")
check(Transition.isFinished() == true, "tr: vor Reset finished")
Transition.reset()
check(Transition.isActive() == false, "tr: reset -> inaktiv")
check(Transition.isFinished() == false, "tr: reset -> nicht finished")
check(Transition.getPhase() == nil, "tr: reset -> keine alte Phase")
check(Transition.getPhaseProgress() == nil, "tr: reset -> kein Fortschritt")

-- --- 8) Read-only: kein Gameplay-State-Zugriff --------------------------------------
local trappedModules = {
    "State", "Undo", "Room", "Bridge", "Save", "Levels", "Player", "Switch", "Gate",
}
local function withTrap(globalName, fn)
    local real = _G[globalName]
    _G[globalName] = setmetatable({}, {
        __index = function()
            error("trap: " .. globalName .. " während Transition berührt")
        end,
    })
    local okTrap = pcall(fn)
    _G[globalName] = real
    return okTrap
end
for _, name in ipairs(trappedModules) do
    local okTrap = withTrap(name, function()
        Transition.reset()
        Transition.startOutro(6, 2, 1)
        Transition.update(0.5)
        Transition.getPhaseProgress()
        Transition.reset()
    end)
    check(okTrap, "tr: " .. name .. " bleibt unberührt (Trap nicht ausgelöst)")
end

-- --- 9) Zeichnen ohne Fehler ----------------------------------------------------------
Transition.reset()
Transition.startOutro(6, 2, 1)
check(pcall(function() Transition.draw() end), "tr: draw Phase R1 ohne Fehler")
Transition.update(D0)
check(pcall(function() Transition.draw() end), "tr: draw Phase Core ohne Fehler")
Transition.update(D1)
check(pcall(function() Transition.draw() end), "tr: draw Phase Iris ohne Fehler")
Transition.update(D2)
check(pcall(function() Transition.draw() end), "tr: draw Phase Hold ohne Fehler")
Transition.update(D3)
check(pcall(function() Transition.draw() end), "tr: draw nach Finish ohne Fehler (No-op)")

TestReport.transition = { pass = pass, fail = fail }
