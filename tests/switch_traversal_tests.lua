-- Tests für Release-Fix 1: geschwindigkeitsunabhängige vollständige
-- Schalterdurchquerung (world/room.lua + world/switch.lua).
--
-- Vertrag (ARCHITECTURE G1 + Release-Fix-1-Spezifikation):
--   Ein Schalter wird gesetzt, wenn die Spielfigur seinen Bogen
--   (center ± switchArcWidth/2) vollständig durchquert — über beliebig viele
--   Frames (kleine D-Pad-Deltas wie 1,8°/Frame) ODER in einem einzigen großen
--   Delta (Kurbel). Crank und D-Pad besitzen exakt dieselbe Semantik.
--   Eintritt allein löst NICHT aus; Rückkehr über die Eintrittsseite bricht
--   die Traversierung ab; Start innerhalb des Bogens armiert NICHT.
--
-- Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/room, world/switch, world/bridge und world/gate per import geladen
-- wurden (siehe tools/run_tests.ps1). Ergebnis in TestReport.switchTraversal.

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

-- Grundraum: S1/S2 auf outer, Blenden auf inner (blockieren nie auf outer).
-- S1@100 (Bogen [93,107]), S2@200 (Bogen [193,207]).
local function makeRoom()
    return {
        name = "Traversal",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 60 },
        switches = {
            { id="S1", ring="outer", angle=100, symbol=1, onA="B1", onB="D1", state="B" },
            { id="S2", ring="outer", angle=200, symbol=2, onA="D2", onB="B2", state="B" },
        },
        shutters = {
            { id="D1", ring="inner", angle=90 },
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

-- Schalter über 0°: S1@358 (Bogen [351,5]).
local function makeWrapRoom()
    return {
        name = "Wrap",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 350 },
        switches = {
            { id="S1", ring="outer", angle=358, symbol=1, onA="B1", onB="D1", state="B" },
        },
        shutters = { { id="D1", ring="inner", angle=90 } },
        bridges = { { id="B0", angle=0, free=true }, { id="B1", angle=270, free=false } },
        gate = { id="T", angle=0, free=true },
    }
end

-- Schalter + Blende auf outer, deren Eintrittskante den Spieler NACH dem
-- Schalter-Eintritt, aber VOR dem Schalter-Austritt stoppt. S1@100 (Bogen
-- [93,107]), D1@110 (Bogen [97,123]). S1=A öffnet D1 (onA="D1").
local function makeBlockRoom()
    return {
        name = "Block",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 60 },
        switches = {
            { id="S1", ring="outer", angle=100, symbol=1, onA="D1", onB="B1", state="B" },
        },
        shutters = { { id="D1", ring="outer", angle=110 } },
        bridges = { { id="B0", angle=0, free=true }, { id="B1", angle=270, free=false } },
        gate = { id="T", angle=0, free=true },
    }
end

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
end

-- ==================== D-Pad-Regression (der Release-Blocker) ================

-- --- 1) viele kleine +1.8°-Moves -> CW vollständig -> A ---------------------
-- Spieler bei 60 (vor S1-Eintrittskante 93) fährt mit 1.8° pro Frame durch den
-- kompletten Bogen bis 115.8 (über Austrittskante 107). Der alte Ein-Frame-
-- Check ließ das niemals auslösen -> S1 blieb B.
do
    setup(makeRoom())
    State.player.angle = 60
    local actualTotal = 0
    for _ = 1, 31 do -- 31 * 1.8 = 55.8 -> 60 -> 115.8
        local a, _ = Room.movePlayer(1.8)
        actualTotal = actualTotal + a
    end
    check(approx(actualTotal, 31 * 1.8, 0.5), "dpad-cw: Gesamtweg 55.8 (actual " .. tostring(actualTotal) .. ")")
    check(State.switchStates["S1"] == "A", "dpad-cw: S1 -> A (viele kleine Schritte)")
    check(State.elementStates["B1"] == true, "dpad-cw: B1 aktiv")
    check(State.elementStates["D1"] == false, "dpad-cw: D1 geschlossen")
    check(Undo.count() == 1, "dpad-cw: genau 1 Undo")
end

-- --- 2) viele kleine -1.8°-Moves -> CCW vollständig -> B --------------------
do
    setup(makeRoom())
    State.setSwitch("S1", "A") -- echte Änderung A->B möglich
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 140
    for _ = 1, 34 do -- 34 * 1.8 = 61.2 -> 140 -> 78.8 (über Austritt 93 CCW)
        Room.movePlayer(-1.8)
    end
    check(State.switchStates["S1"] == "B", "dpad-ccw: S1 -> B (viele kleine Schritte)")
    -- S1: onA="B1", onB="D1" -> Zustand B aktiviert D1, deaktiviert B1.
    check(State.elementStates["B1"] == false, "dpad-ccw: B1 eingefahren")
    check(State.elementStates["D1"] == true, "dpad-ccw: D1 offen")
    check(Undo.count() == 1, "dpad-ccw: genau 1 Undo")
end

-- --- 3) sehr kleine 0.5°-Schritte -> beweist: nicht nur für 1.8° gefixt -----
do
    setup(makeRoom())
    State.player.angle = 60
    for _ = 1, 100 do -- 100 * 0.5 = 50 -> 60 -> 110
        Room.movePlayer(0.5)
    end
    check(State.switchStates["S1"] == "A", "0.5°: S1 -> A")
    check(Undo.count() == 1, "0.5°: genau 1 Undo")
end

-- --- 3b) sehr kleine -0.5°-Schritte CCW -> B ---------------------------------
do
    setup(makeRoom())
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 140
    for _ = 1, 100 do -- 100 * 0.5 = 50 -> 140 -> 90 (über CCW-Austritt 93)
        Room.movePlayer(-0.5)
    end
    check(State.switchStates["S1"] == "B", "0.5° ccw: S1 -> B")
    check(Undo.count() == 1, "0.5° ccw: genau 1 Undo")
end

-- ==================== Kurbel-Regression (große Ein-Frame-Deltas) ============

-- --- 4) +40° / -60° in einem Frame bleiben korrekt --------------------------
do
    setup(makeRoom())
    State.player.angle = 80
    local actual, result = Room.movePlayer(40) -- 80 -> 120, über [93,107]
    check(actual == 40, "gross: actual +40")
    check(State.switchStates["S1"] == "A", "gross cw: S1 -> A (40° in einem Frame)")
    check(Undo.count() == 1, "gross cw: 1 Undo")
    check(result.switchChanges == 1, "gross cw: 1 echte Schalteränderung")

    setup(makeRoom())
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 140
    local a2, r2 = Room.movePlayer(-60) -- 140 -> 80, über [93,107] CCW
    check(a2 == -60, "gross ccw: actual -60")
    check(State.switchStates["S1"] == "B", "gross ccw: S1 -> B (-60° in einem Frame)")
    check(Undo.count() == 1, "gross ccw: 1 Undo")
    check(r2.switchChanges == 1, "gross ccw: 1 echte Schalteränderung")
end

-- ==================== Eintritt / Reverse / Start-inside =====================

-- --- 5) Eintritt allein -> kein Trigger, kein Undo --------------------------
do
    setup(makeRoom())
    State.player.angle = 60
    local a1, r1 = Room.movePlayer(40) -- 60 -> 100, innerhalb des Bogens [93,107]
    check(a1 == 40, "enter-only: actual 40")
    check(State.player.angle == 100, "enter-only: Winkel 100 (im Bogen)")
    check(State.switchStates["S1"] == "B", "enter-only: kein Trigger")
    check(Undo.count() == 0, "enter-only: kein Undo")
    check(r1.switchChanges == 0, "enter-only: 0 Schalteränderungen")
    check(r1.undoStored == false, "enter-only: kein Undo gespeichert")
end

-- --- 6) CW Enter + Reverse (zurück über Eintrittskante) -> kein Trigger -----
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(40) -- 60 -> 100 (im Bogen, armiert)
    local a2, _ = Room.movePlayer(-15) -- 100 -> 85 (zurück über Eintrittskante 93)
    check(a2 == -15, "cw-rev: actual -15")
    check(State.player.angle == 85, "cw-rev: Winkel 85 (außerhalb)")
    check(State.switchStates["S1"] == "B", "cw-rev: kein Trigger (Rückkehr über Eintrittsseite)")
    check(Undo.count() == 0, "cw-rev: kein Undo")
end

-- --- 7) CCW Enter + Reverse -> kein Trigger ----------------------------------
do
    setup(makeRoom())
    State.player.angle = 140
    Room.movePlayer(-40) -- 140 -> 100 (im Bogen, CCW armiert)
    local a2, _ = Room.movePlayer(15) -- 100 -> 115 (zurück über CCW-Eintrittskante 107)
    check(a2 == 15, "ccw-rev: actual +15")
    check(State.switchStates["S1"] == "B", "ccw-rev: kein Trigger (Rückkehr über Eintrittsseite)")
    check(Undo.count() == 0, "ccw-rev: kein Undo")
end

-- --- 8) Eintritt -> kleiner Reverse (im Bogen) -> gegenüberliegender Exit ----
-- CW rein bis 96, 2° zurück (94, immer noch im Bogen), dann CW bis 108 -> A.
-- Nur Rückkehr über die Eintrittsseite bricht die Traversierung ab.
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(36) -- 60 -> 96 (im Bogen, armiert)
    Room.movePlayer(-2) -- 96 -> 94 (kleiner Reverse, bleibt im Bogen)
    check(State.player.angle == 94, "part-rev: Winkel 94 (noch im Bogen)")
    local a3, _ = Room.movePlayer(14) -- 94 -> 108 (über Austritt 107)
    check(a3 == 14, "part-rev: actual +14")
    check(State.switchStates["S1"] == "A", "part-rev: S1 -> A (vollständige Durchquerung trotz Mini-Reverse)")
    check(Undo.count() == 1, "part-rev: 1 Undo")
end

-- --- 9) CCW analog -> B -------------------------------------------------------
do
    setup(makeRoom())
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 140
    Room.movePlayer(-44) -- 140 -> 96 (im Bogen, CCW armiert)
    Room.movePlayer(2)   -- 96 -> 98 (kleiner Reverse, bleibt im Bogen)
    local a3, _ = Room.movePlayer(-14) -- 98 -> 84 (über Austritt 93 CCW)
    check(a3 == -14, "part-rev-ccw: actual -14")
    check(State.switchStates["S1"] == "B", "part-rev-ccw: S1 -> B")
    check(Undo.count() == 1, "part-rev-ccw: 1 Undo")
end

-- --- 10) Start innerhalb des Bogens -> kein falscher Trigger -----------------
do
    setup(makeRoom())
    State.player.angle = 100 -- künstlich im Bogen [93,107]
    local a1, _ = Room.movePlayer(-10) -- 100 -> 90, verlässt über Eintrittskante 93
    check(a1 == -10, "start-inside: actual -10")
    check(State.switchStates["S1"] == "B", "start-inside: kein Trigger beim Verlassen")
    check(Undo.count() == 0, "start-inside: kein Undo")
    -- Danach komplette echte Durchquerung CW -> A.
    local a2, _ = Room.movePlayer(40) -- 90 -> 130, über [93,107]
    check(a2 == 40, "start-inside: actual +40")
    check(State.switchStates["S1"] == "A", "start-inside: danach echte Durchquerung -> A")
    check(Undo.count() == 1, "start-inside: 1 Undo nach echter Durchquerung")
end

-- ==================== Wraparound 0° ==========================================

-- --- 11) Wrap CW: kleine Schritte über 0° -> A ------------------------------
do
    setup(makeWrapRoom()) -- S1@358, Bogen [351,5], Start 350
    for _ = 1, 15 do -- 15 * 1.8 = 27 -> 350 -> 17 (über Eintritt 351, Austritt 5)
        Room.movePlayer(1.8)
    end
    check(State.switchStates["S1"] == "A", "wrap cw: S1 -> A (über 0° in kleinen Schritten)")
    check(Undo.count() == 1, "wrap cw: genau 1 Undo")
end

-- --- 12) Wrap CCW: kleine Schritte über 0° -> B ------------------------------
do
    setup(makeWrapRoom())
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 20
    for _ = 1, 17 do -- 17 * 1.8 = 30.6 -> 20 -> 349.4 (über Eintritt 5, Austritt 351)
        Room.movePlayer(-1.8)
    end
    check(State.switchStates["S1"] == "B", "wrap ccw: S1 -> B (über 0° CCW in kleinen Schritten)")
    check(Undo.count() == 1, "wrap ccw: genau 1 Undo")
end

-- ==================== No-op (G1: kein Toggle) ================================

-- --- 13) bereits A, vollständige CW-Durchquerung -> bleibt A, kein Undo -----
do
    setup(makeRoom())
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Undo.clear()
    State.player.angle = 60
    local _, result = Room.movePlayer(50) -- 60 -> 110, kreuzt S1 CW
    check(State.switchStates["S1"] == "A", "noop-a: bleibt A")
    check(Undo.count() == 0, "noop-a: kein Undo")
    check(result.switchChanges == 0, "noop-a: keine echte Schalteränderung")
end

-- --- 14) bereits B, vollständige CCW-Durchquerung -> bleibt B, kein Undo -----
do
    setup(makeRoom()) -- S1 startet B
    Undo.clear()
    State.player.angle = 140
    local _, result = Room.movePlayer(-60) -- 140 -> 80, kreuzt S1 CCW
    check(State.switchStates["S1"] == "B", "noop-b: bleibt B")
    check(Undo.count() == 0, "noop-b: kein Undo")
    check(result.switchChanges == 0, "noop-b: keine echte Schalteränderung")
end

-- ==================== Mehrere Schalter / Undo-Invariante =====================

-- --- 15) großer Sweep über zwei Schalter: chronologisch, max 1 Undo ----------
do
    setup(makeRoom())
    State.player.angle = 50
    local actual, result = Room.movePlayer(170) -- 50 -> 220, über S1 und S2
    check(actual == 170, "multi: actual 170")
    check(State.switchStates["S1"] == "A", "multi: S1 -> A")
    check(State.switchStates["S2"] == "A", "multi: S2 -> A")
    check(Undo.count() == 1, "multi: genau 1 Undo (zwei Statechanges, ein Snapshot)")
    check(result.switchChanges == 2, "multi: 2 echte Schalteränderungen")
end

-- ==================== Shutter blockiert vor dem Austritt =====================

-- --- 16) Blende stoppt nach Eintritt, vor Austritt -> kein Trigger -----------
do
    setup(makeBlockRoom()) -- S1@100 [93,107], D1@110 [97,123] geschlossen (S1=B)
    local actual, result = Room.movePlayer(40) -- 60 -> Stopp an D1-Eintritt 97
    check(actual == 37, "block-before-exit: actual 37 (Stopp bei 97)")
    check(State.player.angle == 97, "block-before-exit: Stopp 97 (im S1-Bogen)")
    check(State.switchStates["S1"] == "B", "block-before-exit: kein Trigger (nicht ausgetreten)")
    check(result.blocked == true, "block-before-exit: blockiert")
    check(Undo.count() == 0, "block-before-exit: kein Undo")
end

-- --- 17) nach Block den gegenüberliegenden Ausgang erreichen -> Trigger ------
-- Simulation: die Blende wird geöffnet (z. B. von einem entfernten Schalter),
-- dann fährt der Spieler weiter über die Austrittskante. Die Traversierung
-- bleibt über den Block hinweg armiert.
do
    setup(makeBlockRoom())
    Room.movePlayer(40) -- Stopp bei 97 (im Bogen, armiert)
    State.elementStates["D1"] = true -- Blende öffnet (Fremdmechanismus)
    Room.syncPhysicalShutters()
    local a2, _ = Room.movePlayer(15) -- 97 -> 112 (über Austritt 107)
    check(a2 == 15, "continue-after-block: actual +15")
    check(State.player.angle == 112, "continue-after-block: Winkel 112")
    check(State.switchStates["S1"] == "A", "continue-after-block: S1 -> A (späterer echter Exit)")
    check(Undo.count() == 1, "continue-after-block: 1 Undo")
end

-- --- 18) nach Block zurück über Eintrittskante -> kein Trigger ---------------
do
    setup(makeBlockRoom())
    Room.movePlayer(40) -- Stopp bei 97 (im Bogen, armiert)
    local a2, _ = Room.movePlayer(-10) -- 97 -> 87 (zurück über Eintrittskante 93)
    check(a2 == -10, "reverse-after-block: actual -10")
    check(State.switchStates["S1"] == "B", "reverse-after-block: kein Trigger")
    check(Undo.count() == 0, "reverse-after-block: kein Undo")
end

-- ==================== Undo: kein stale/Phantom-Traversal =====================

-- --- 19) Trigger -> Undo -> kleine Bewegung -> kein Phantomtrigger -----------
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(50) -- 60 -> 110, S1 -> A, 1 Undo
    check(State.switchStates["S1"] == "A", "undo-stale: S1 A vor Undo")
    Undo.undo()
    Room.syncPhysicalShutters()
    check(State.switchStates["S1"] == "B", "undo-stale: S1 restauriert")
    check(State.player.angle == 60, "undo-stale: Position restauriert (60)")
    -- main.lua-Äquivalent: Room.resetSwitchTraversal() beim Undo.
    Room.resetSwitchTraversal()
    local a1, _ = Room.movePlayer(5) -- 60 -> 65, kein Schalter erreicht
    check(a1 == 5, "undo-stale: kleine Bewegung ok")
    check(State.switchStates["S1"] == "B", "undo-stale: kein Phantomtrigger")
    check(Undo.count() == 0, "undo-stale: kein neues Undo")
end

-- --- 20) Undo während halber Traversierung -> neutralisiert, kein Trigger ----
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(36) -- 60 -> 96 (im Bogen, armiert), kein Trigger/Undo
    check(Undo.count() == 0, "undo-half: vorher kein Undo (Eintritt erzeugt keins)")
    -- main.lua-Äquivalent: B -> resetSwitchTraversal + Undo.undo (leerer Stack).
    Room.resetSwitchTraversal()
    Undo.undo() -- leer -> false
    local a1, _ = Room.movePlayer(12) -- 96 -> 108 (verlässt über Austritt 107)
    check(a1 == 12, "undo-half: Verlassen ok")
    check(State.switchStates["S1"] == "B", "undo-half: kein Trigger (Traversal durch B neutralisiert)")
    check(Undo.count() == 0, "undo-half: kein Undo")
    -- frische vollständige Durchquerung von außen -> A.
    State.player.angle = 80
    Room.movePlayer(40) -- 80 -> 120, über [93,107]
    check(State.switchStates["S1"] == "A", "undo-half: frische Durchquerung -> A")
end

-- ==================== Verschiedene Frameraten ================================

-- --- 21) gleiche reale Bewegung, verschiedene dt/Step -> gleiches Ergebnis ----
do
    local rates = {
        { label = "50fps", step = 90 / 50 },  -- 1.8
        { label = "30fps", step = 90 / 30 },  -- 3.0
        { label = "20fps", step = 90 / 20 },  -- 4.5
    }
    for _, r in ipairs(rates) do
        setup(makeRoom())
        State.player.angle = 60
        local frames = math.ceil(54 / r.step)
        for _ = 1, frames do
            Room.movePlayer(r.step)
        end
        check(State.switchStates["S1"] == "A", "rate " .. r.label .. ": S1 -> A (dt-unabhängig)")
        check(Undo.count() == 1, "rate " .. r.label .. ": genau 1 Undo")
    end
end

-- ==================== Exakte Austrittskante (Start,End]-Regel ================

-- --- 22) Stopp exakt auf Austrittskante -> Trigger; minimal davor -> nicht ---
do
    setup(makeRoom())
    State.player.angle = 60
    local a1, _ = Room.movePlayer(47) -- 60 -> 107, exakt auf Austrittskante
    check(a1 == 47, "exact-exit: actual 47")
    check(State.player.angle == 107, "exact-exit: Ende exakt 107")
    check(State.switchStates["S1"] == "A", "exact-exit: S1 -> A (Ende inklusive)")
    check(Undo.count() == 1, "exact-exit: 1 Undo")

    setup(makeRoom())
    State.player.angle = 60
    local a2, _ = Room.movePlayer(46) -- 60 -> 106, minimal davor
    check(a2 == 46, "min-before-exit: actual 46")
    check(State.player.angle == 106, "min-before-exit: Ende 106")
    check(State.switchStates["S1"] == "B", "min-before-exit: kein Trigger")
    check(Undo.count() == 0, "min-before-exit: kein Undo")
end

-- ==================== White-Box: Traversal-Zustand ===========================

-- --- 23) Armierung beim Eintritt, Disarm nach Austritt / Abbruch ------------
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(35) -- 60 -> 95 (im Bogen), armiert
    check(Room.switchTraversal["S1"] == 1, "traversal-state: armiert CW nach Eintritt")
    Room.movePlayer(15) -- 95 -> 110 (über Austritt 107) -> Trigger -> Disarm
    check(Room.switchTraversal["S1"] == nil, "traversal-state: disarm nach Austritt")
    check(State.switchStates["S1"] == "A", "traversal-state: S1 -> A")

    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(35) -- 95 (armiert)
    Room.movePlayer(-10) -- 95 -> 85 (zurück über Eintrittskante) -> Cancel
    check(Room.switchTraversal["S1"] == nil, "traversal-state: cancel nach Reverse")
    check(State.switchStates["S1"] == "B", "traversal-state: kein Trigger")

    setup(makeRoom())
    State.player.angle = 140
    Room.movePlayer(-44) -- 96 (CCW armiert)
    check(Room.switchTraversal["S1"] == -1, "traversal-state: armiert CCW nach Eintritt")
    Room.resetSwitchTraversal()
    check(Room.switchTraversal["S1"] == nil, "traversal-state: reset räumt Zustand")
end

-- --- 24) Room.init setzt Traversal zurück (Raumstart/Restart/Raumwechsel) ----
do
    setup(makeRoom())
    State.player.angle = 60
    Room.movePlayer(35) -- armiert
    check(Room.switchTraversal["S1"] == 1, "init-reset: vorher armiert")
    Room.init() -- Raumstart-Äquivalent (Neuinitalisierung)
    check(Room.switchTraversal["S1"] == nil, "init-reset: nach Room.init leer")
end

TestReport.switchTraversal = { pass = pass, fail = fail }
