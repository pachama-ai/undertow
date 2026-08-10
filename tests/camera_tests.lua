-- Tests für source/ui/camera.lua (globale Tabelle Camera): Ringkamera und
-- 1,2-s-Raumtransition (Phase 8.1). Reine visuelle Geometrie; keine Gameplay-
-- Wahrheit. Ringnummern-Konvention (Audit): Die Leveldaten nummerieren nach
-- innen abnehmend (inner == outer - 1), daher:
--   radius = Config.outerRadius - (cameraOuterRing - ringNumber) * ringSpacing
-- Erwartet, dass core/config, core/state, core/undo, data/levels und ui/camera
-- per import geladen wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.camera gesammelt.

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

local ringSpacing <const> = Config.outerRadius - Config.innerRadius -- 36, aus Config

-- Echte Ringnummern aus den Leveldaten (Räume 1-6).
local R1_OUTER <const> = Levels[1].rings.outer -- 7
local R1_INNER <const> = Levels[1].rings.inner -- 6
local R2_OUTER <const> = Levels[2].rings.outer -- 6
local R2_INNER <const> = Levels[2].rings.inner -- 5
local R3_OUTER <const> = Levels[3].rings.outer -- 5
local R3_INNER <const> = Levels[3].rings.inner -- 4
local R4_OUTER <const> = Levels[4].rings.outer -- 4
local R4_INNER <const> = Levels[4].rings.inner -- 3
local R5_OUTER <const> = Levels[5].rings.outer -- 3
local R5_INNER <const> = Levels[5].rings.inner -- 2
local R6_OUTER <const> = Levels[6].rings.outer -- 2
local R6_INNER <const> = Levels[6].rings.inner -- 1

-- --- Config ---------------------------------------------------------------
check(Config.cameraDuration == 1.2, "config: cameraDuration 1.2")
check(ringSpacing == 36, "config: ringSpacing = outerRadius - innerRadius = 36")

-- --- Pflicht-Test: Initialabbildung ---------------------------------------
do
    Camera.init(R1_OUTER)
    check(Camera.isTransitioning() == false, "initial: keine Transition")
    check(Camera.getRadius(R1_OUTER) == Config.outerRadius, "initial: outer -> 104")
    check(Camera.getRadius(R1_INNER) == Config.innerRadius, "initial: inner -> 68")
    check(approx(Camera.getRadius(R1_OUTER + 1), Config.outerRadius + ringSpacing), "initial: vorheriger outer -> 140")
    check(approx(Camera.getRadius(R1_INNER - 1), Config.innerRadius - ringSpacing), "initial: nächster inner -> 32")
end

-- --- Pflicht-Test: Transitionstart (1 -> 2) -------------------------------
do
    Camera.init(R1_OUTER)
    local started = Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    check(started == true, "start: beginRoomTransition akzeptiert")
    check(Camera.isTransitioning() == true, "start: aktiv")
    check(Camera.getProgress() == 0, "start: progress 0")
    check(Camera.getEasedProgress() == 0, "start: eased 0")
    check(Camera.getRadius(R1_OUTER) == Config.outerRadius, "start: alter outer 104")
    check(Camera.getRadius(R1_INNER) == Config.innerRadius, "start: shared 68")
    check(approx(Camera.getRadius(R2_INNER), Config.innerRadius - ringSpacing), "start: neuer inner 32")
end

-- --- Pflicht-Test: 0,3 s --------------------------------------------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(0.3) -- raw 0.25
    check(approx(Camera.getProgress(), 0.25), "0.3s: raw 0.25")
    check(approx(Camera.getEasedProgress(), 0.15625), "0.3s: eased 0.15625")
    -- visualOuter = 7 - 0.15625 = 6.84375
    check(approx(Camera.getRadius(R1_OUTER), 104 + 0.15625 * ringSpacing), "0.3s: alter outer 109.625")
    check(approx(Camera.getRadius(R1_INNER), 104 - 0.84375 * ringSpacing), "0.3s: shared 73.625")
    check(approx(Camera.getRadius(R2_INNER), 104 - 1.84375 * ringSpacing), "0.3s: neuer inner 37.625")
end

-- --- Pflicht-Test: Halbzeit (0,6 s) ---------------------------------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(0.6) -- raw 0.5
    check(approx(Camera.getProgress(), 0.5), "0.6s: raw 0.5")
    check(approx(Camera.getEasedProgress(), 0.5), "0.6s: eased 0.5")
    check(approx(Camera.getRadius(R1_OUTER), 122), "0.6s: alter outer 122")
    check(approx(Camera.getRadius(R1_INNER), 86), "0.6s: shared 86")
    check(approx(Camera.getRadius(R2_INNER), 50), "0.6s: neuer inner 50")
end

-- --- Pflicht-Test: 0,9 s (Ende verlangsamt sich) --------------------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(0.9) -- raw 0.75
    check(approx(Camera.getProgress(), 0.75), "0.9s: raw 0.75")
    check(approx(Camera.getEasedProgress(), 0.84375), "0.9s: eased 0.84375 (Ende verlangsamt)")
    -- visualOuter = 7 - 0.84375 = 6.15625
    check(approx(Camera.getRadius(R1_OUTER), 104 + 0.84375 * ringSpacing), "0.9s: alter outer 134.375")
end

-- --- Pflicht-Test: Ende (1,2 s) -------------------------------------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(1.2)
    check(Camera.isTransitioning() == false, "1.2s: Transition beendet")
    check(Camera.getCurrentOuterRing() == R2_OUTER, "1.2s: currentOuterRing == neuer Outer")
    check(approx(Camera.getRadius(R1_OUTER), Config.outerRadius + ringSpacing), "1.2s: alter outer 140")
    check(Camera.getRadius(R2_OUTER) == Config.outerRadius, "1.2s: neuer outer 104")
    check(Camera.getRadius(R2_INNER) == Config.innerRadius, "1.2s: neuer inner 68")
end

-- --- Pflicht-Test: Overshoot ----------------------------------------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(2.0)
    check(Camera.isTransitioning() == false, "overshoot: inactive")
    check(Camera.getProgress() == nil, "overshoot: kein Restfortschritt")
    check(Camera.getCurrentOuterRing() == R2_OUTER, "overshoot: exakter Zielring")
    check(Camera.getRadius(R2_OUTER) == Config.outerRadius, "overshoot: exakt 104")
    check(Camera.getRadius(R2_INNER) == Config.innerRadius, "overshoot: exakt 68")
end

-- --- Pflicht-Test: kein zweiter Transit -----------------------------------
do
    Camera.init(R1_OUTER)
    local s1 = Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    check(s1 == true, "zweiter: erster Begin ok")
    local s2 = Camera.beginRoomTransition(R2_OUTER, R2_INNER, R3_OUTER, R3_INNER)
    check(s2 == false, "zweiter: zweiter Begin abgewiesen")
    check(Camera.isTransitioning() == true, "zweiter: erste Transition unverändert aktiv")
    Camera.update(0.6)
    check(approx(Camera.getProgress(), 0.5), "zweiter: erste Transition läuft weiter")
end

-- --- Pflicht-Test: Ringkontinuität ----------------------------------------
do
    Camera.init(R1_OUTER)
    local ok1 = Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    check(ok1 == true, "kontinuität: fromInner == toOuter akzeptiert")
    Camera.reset()
    -- Synthetischer Fehlerfall: fromInner ~= toOuter.
    local ok2, err2 = pcall(function()
        Camera.beginRoomTransition(R1_OUTER, R1_INNER, R3_OUTER, R3_INNER)
    end)
    check(ok2 == false, "kontinuität: fromInner != toOuter abgewiesen")
    check(type(err2) == "string" and string.find(err2, "fromInnerRing", 1, true) ~= nil, "kontinuität: Fehlermeldung benennt Ring")
    -- Ringpaar nicht benachbart (Datenkonvention inner == outer - 1).
    local ok3, _ = pcall(function()
        Camera.beginRoomTransition(R1_OUTER, R1_OUTER - 2, R2_OUTER, R2_INNER)
    end)
    check(ok3 == false, "kontinuität: nicht benachbartes from-Paar abgewiesen")
end

-- --- Pflicht-Test: 2 -> 3 --------------------------------------------------
do
    Camera.init(R2_OUTER)
    Camera.beginRoomTransition(R2_OUTER, R2_INNER, R3_OUTER, R3_INNER)
    Camera.update(1.2)
    check(Camera.getCurrentOuterRing() == R3_OUTER, "2->3: Zielring 5")
    check(approx(Camera.getRadius(R2_OUTER), Config.outerRadius + ringSpacing), "2->3: alter outer 140")
    check(Camera.getRadius(R3_OUTER) == Config.outerRadius, "2->3: neuer outer 104")
    check(Camera.getRadius(R3_INNER) == Config.innerRadius, "2->3: neuer inner 68")
end

-- --- Pflicht-Test: initialer Raum ohne Transition ---------------------------
do
    Camera.init(R3_OUTER) -- Raum 3: outer 5, inner 4
    check(Camera.isTransitioning() == false, "raum3: keine Transition")
    check(Camera.getRadius(R3_OUTER) == Config.outerRadius, "raum3: outer 104")
    check(Camera.getRadius(R3_INNER) == Config.innerRadius, "raum3: inner 68")
    -- Ohne beginRoomTransition bleibt das Ziel stabil (Transition wird nur
    -- über einen echten Gate-Übergang 3->4 gestartet).
    check(Camera.getTargetOuterRing() == R3_OUTER, "raum3: Ziel stabil ohne Transition")
end

-- --- Pflicht-Test: 3 -> 4 (Abschlussphase A) --------------------------------
do
    Camera.init(R3_OUTER)
    Camera.beginRoomTransition(R3_OUTER, R3_INNER, R4_OUTER, R4_INNER)
    Camera.update(1.2)
    check(Camera.getCurrentOuterRing() == R4_OUTER, "3->4: Zielring 4")
    check(approx(Camera.getRadius(R3_OUTER), Config.outerRadius + ringSpacing), "3->4: alter outer 140")
    check(Camera.getRadius(R4_OUTER) == Config.outerRadius, "3->4: neuer outer 104")
    check(Camera.getRadius(R4_INNER) == Config.innerRadius, "3->4: neuer inner 68")
end

-- --- Pflicht-Test: 4 -> 5 (Abschlussphase A) --------------------------------
do
    Camera.init(R4_OUTER)
    Camera.beginRoomTransition(R4_OUTER, R4_INNER, R5_OUTER, R5_INNER)
    Camera.update(0.6)
    check(approx(Camera.getProgress(), 0.5), "4->5: raw 0.5 bei Halbzeit")
    Camera.update(0.6)
    check(Camera.getCurrentOuterRing() == R5_OUTER, "4->5: Zielring 3")
    check(approx(Camera.getRadius(R4_OUTER), Config.outerRadius + ringSpacing), "4->5: alter outer 140")
    check(Camera.getRadius(R5_OUTER) == Config.outerRadius, "4->5: neuer outer 104")
    check(Camera.getRadius(R5_INNER) == Config.innerRadius, "4->5: neuer inner 68")
end

-- --- Pflicht-Test: 5 -> 6 (Abschlussphase A) --------------------------------
do
    Camera.init(R5_OUTER)
    Camera.beginRoomTransition(R5_OUTER, R5_INNER, R6_OUTER, R6_INNER)
    Camera.update(0.3)
    check(approx(Camera.getProgress(), 0.25), "5->6: raw 0.25 bei 0,3 s")
    Camera.update(0.9)
    check(Camera.getCurrentOuterRing() == R6_OUTER, "5->6: Zielring 2")
    check(approx(Camera.getRadius(R5_OUTER), Config.outerRadius + ringSpacing), "5->6: alter outer 140")
    check(Camera.getRadius(R6_OUTER) == Config.outerRadius, "5->6: neuer outer 104")
    check(Camera.getRadius(R6_INNER) == Config.innerRadius, "5->6: neuer inner 68")
end

-- --- Pass 2: Initial-Hold (kurze Ruhe vor der Raumtransition) ---------------
do
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER, 0.1)
    -- Während des Holds: keine Kamerabewegung, Progress 0.
    Camera.update(0.05)
    check(Camera.isTransitioning() == true, "p2 hold: noch in Transition")
    check(approx(Camera.getProgress(), 0), "p2 hold: Progress 0 während Hold")
    check(Camera.getCurrentOuterRing() == R1_OUTER, "p2 hold: alter Ring stabil")
    check(Camera.getVisualOuterRing() == R1_OUTER, "p2 hold: Kamera hält Ausgangsposition")
    -- Nach dem Hold beginnt die Interpolation.
    Camera.update(0.05)
    check(Camera.getProgress() ~= nil and Camera.getProgress() > 0, "p2 hold: nach Hold startet Transition")
    -- Gesamtdauer = Hold + cameraDuration.
    Camera.update(Config.cameraDuration)
    check(Camera.getCurrentOuterRing() == R2_OUTER, "p2 hold: Zielring nach Hold + Dauer")
end

-- --- Pflicht-Test: Raum 6 stabil (Finalraum, keine Transition ohne Gate) ----
do
    Camera.init(R6_OUTER) -- Raum 6: outer 2, inner 1
    check(Camera.isTransitioning() == false, "raum6: keine Transition")
    check(Camera.getRadius(R6_OUTER) == Config.outerRadius, "raum6: outer 104")
    check(Camera.getRadius(R6_INNER) == Config.innerRadius, "raum6: inner 68")
    check(approx(Camera.getRadius(R6_OUTER + 1), Config.outerRadius + ringSpacing), "raum6: vorheriger outer 140")
    check(Camera.getTargetOuterRing() == R6_OUTER, "raum6: Ziel stabil (Room6-Completion lädt nichts)")
end

-- --- Pflicht-Test: Camera verändert keine Gameplay-Daten ------------------
do
    State.init(Levels[1])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    Camera.init(R1_OUTER)
    Camera.beginRoomTransition(R1_OUTER, R1_INNER, R2_OUTER, R2_INNER)
    Camera.update(0.3)
    Camera.update(0.6)
    Camera.update(1.2)
    check(Camera.getCurrentOuterRing() == R2_OUTER, "readonly: Kamera abgeschlossen")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "readonly: State.player unverändert")
    check(Undo.count() == undoBefore, "readonly: Undo unverändert")
    check(sameValues(State.switchStates, swBefore), "readonly: switchStates unverändert")
    check(sameValues(State.elementStates, elBefore), "readonly: elementStates unverändert")
end

-- --- getProgress/getEasedProgress nil ohne Transition ---------------------
do
    Camera.init(R1_OUTER)
    check(Camera.getProgress() == nil, "progress: nil ohne Transition")
    check(Camera.getEasedProgress() == nil, "eased: nil ohne Transition")
    check(Camera.getTargetOuterRing() == R1_OUTER, "target: stabil ohne Transition")
end

TestReport.camera = { pass = pass, fail = fail }
