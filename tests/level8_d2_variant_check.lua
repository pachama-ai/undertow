-- level8_d2_variant_check.lua — D2-RICHTUNGSZUORDNUNG in Level 8 empirisch prüfen.
--
-- Fragestellung: Welcher D2-Endzustand öffnet die finale Route? Aktuell ist
-- D2=B der finale Zustand (B -> S_FINAL_D2 + F; A -> S_D2). Getestet werden
-- BEIDE Varianten mit der ECHTEN aktuellen Gameplaylogik (keine Teleports,
-- keine State-Manipulation):
--
--   VARIANTE 1 (D2 = B): O verbraucht, D1=A, D2=B -> finale Brücke F aktiv,
--                        S_FINAL_D2 offen -> kompletter Durchlauf bis echter
--                        ROOM COMPLETE.
--   VARIANTE 2 (D2 = A): O verbraucht, D1=A, D2 bleibt A (Start) -> F inaktiv,
--                        S_FINAL_D2 zu -> finaler Ringweg (Baby-Schub oben
--                        links) blockiert -> KEINE Lösung.
--
-- Ergebnis wird in TestReport.level8D2Variant gesammelt.

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
    return math.abs(a - b) <= (tolerance or 0.5)
end

local function physClosed(id)
    local p = Room.shutters[id]
    return p ~= nil and p.collisionActive == true
end

-- Frisches Level-8-Setup.
local function fresh()
    State.init(Levels[8], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[8].rings.outer)
    Render.resetPlayerVisual()
end

-- Spielt bis zum „final-nahen" Zustand: One-Shot O verbraucht, D1=A,
-- Baby auf P3 (D aktiv), Player inner@102 — D2 wurde NOCH NICHT überquert
-- (bleibt im Startzustand A). Das ist die GABELUNG für beide Varianten.
local function playToFinalNear()
    fresh()
    Room.movePlayer(101.83)  -- Baby auf P1
    Room.tryUseConnection()  -- A solo -> inner@112
    Bridge.update(0.5)
    Room.movePlayer(-49)     -- D1 CCW -> B
    Room.tryUseConnection()  -- B solo -> outer@75
    Bridge.update(0.5)
    Room.movePlayer(65.83)   -- Baby P1 -> P2
    Room.tryUseConnection()  -- C solo -> inner@132
    Bridge.update(0.5)
    Room.movePlayer(-45)     -- D1-Anlauf
    Room.movePlayer(15)      -- D1 CW -> A (Zwischenziel)
    Room.movePlayer(106)     -- O verbrauchen (One-Shot, S_FINAL_O offen)
    Room.movePlayer(-15)
    Room.movePlayer(-130)    -- D1 CCW -> B
    Room.tryUseConnection()  -- B solo -> outer@75
    Bridge.update(0.5)
    Room.movePlayer(96.83)   -- Baby P2 -> P3
    Room.movePlayer(-96.83)  -- CCW zu B (Einstieg, B aktiv weil D1=B)
    Room.tryUseConnection()  -- B solo -> inner@75
    Bridge.update(0.5)
    Room.movePlayer(12)      -- 75 -> 87
    Room.movePlayer(15)      -- D1 CW -> A (Player inner@102, D2 noch A)
end

-- ===========================================================================
--  VARIANTE 1: D2 = B  (der aktuelle finale Zustand)
-- ===========================================================================
playToFinalNear()
check(State.consumedSwitches["O"] == true, "v1: One-Shot O verbraucht")
check(State.switchStates["D1"] == "A", "v1: D1 = A (final)")
-- D2 auf B stellen (natürlicher Weg: CW an D2 vorbei = No-op, dann kurzer
-- CCW-Dip durch D2 — echte Schaltermechanik, KEIN 0/360-Wrap, D1 bleibt A).
Room.movePlayer(146)       -- CW 102 -> 248 (D2-CW = No-op, bleibt A)
Room.movePlayer(-15)       -- CCW 248 -> 233 (D2 CCW -> B)
check(State.switchStates["D2"] == "B", "v1: D2 = B (final)")
check(State.elementStates["F"] == true, "v1: finale Bridge F AKTIV (D2=B)")
check(not physClosed("S_FINAL_D2"), "v1: S_FINAL_D2 physisch OFFEN (D2=B)")
check(not physClosed("S_FINAL_D1"), "v1: S_FINAL_D1 physisch OFFEN (D1=A)")
check(not physClosed("S_FINAL_O"), "v1: S_FINAL_O physisch OFFEN (O verbraucht)")
check(not physClosed("S_FI"), "v1: S_FI physisch OFFEN (D1=A)")
-- Kompletter Durchlauf bis zum echten Exit (kein Switch mehr überquert).
Room.movePlayer(-13)       -- inner 233 -> 220 (D-inner-Dock, KEIN Switch)
Room.tryUseConnection()    -- D solo -> outer@220
Bridge.update(0.5)
Room.movePlayer(311.83)    -- 220 -> 171.83 (CW über 0/360, hinter Baby@180)
local _, rPushB = Room.movePlayer(225) -- Baby 180 -> 45 (CW durch OBEN LINKS)
check(rPushB.blocked == false, "v1: Baby-Schub 180->45 durch OBEN LINKS NICHT blockiert")
check(State.baby ~= nil and approx(State.baby.angle, 45, 1.0), "v1: Baby an U (outer@45)")
Room.tryUseConnection()    -- U GEMEINSAM -> inner@45/Baby@35
Bridge.update(0.5)
Room.movePlayer(-40)       -- direkter Schub zum Tor (inner@355): Player 45 -> 5, Baby 35 -> ~357
check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == true, "v1: Gate T nutzbar")
local g1 = Room.tryUseConnection()
check(g1.used == true and g1.kind == "gate" and g1.crossing == true, "v1: Kernbrücken-Transit AUSGELÖST")
local done1, shared1, _, center1 = Bridge.update(0.5)
local v1Solvable = (done1 == true and shared1 == true and center1 == true)
check(v1Solvable, "v1: GEMEINSAMER CENTER-TRANSIT = ROOM COMPLETE")
print("VARIANTE_1_D2_B_SOLVABLE = " .. tostring(v1Solvable))

-- ===========================================================================
--  VARIANTE 2: D2 = A  (D2 wird NICHT auf B gestellt — bleibt Start A)
-- ===========================================================================
playToFinalNear()
check(State.consumedSwitches["O"] == true, "v2: One-Shot O verbraucht")
check(State.switchStates["D1"] == "A", "v2: D1 = A (final)")
check(State.switchStates["D2"] == "A", "v2: D2 bleibt A (Start — Variante 2)")
check(State.elementStates["F"] == false, "v2: finale Bridge F INAKTIV (D2=A) -> keine finale Verbindung")
check(physClosed("S_FINAL_D2"), "v2: S_FINAL_D2 GESCHLOSSEN (D2=A) -> finaler Ringweg zu")
-- Versuch, den finalen Ringweg zu nutzen: über D zurück, Baby durch OBEN LINKS
-- schieben -> muss an S_FINAL_D2 blockiert werden (D2=A -> S_FD2 zu).
Room.movePlayer(118)       -- inner 102 -> 220 (CW zu D, D2 [233,247] nicht gekreuzt)
Room.tryUseConnection()    -- D solo -> outer@220
Bridge.update(0.5)
Room.movePlayer(311.83)    -- 220 -> 171.83 (CW über 0/360, hinter Baby@180, wie im Solllauf)
local _, rPushA = Room.movePlayer(225) -- Baby 180 -> 45 (CW durch OBEN LINKS)
check(rPushA.blocked == true, "v2: Baby-Schub 180->45 an S_FINAL_D2 BLOCKIERT (oben links zu)")
check(State.baby ~= nil and State.baby.angle < 330, "v2: Baby kommt NICHT durch den oberen linken Abschnitt (Stopp < U)")
check(State.baby ~= nil and not approx(State.baby.angle, 45, 2.0), "v2: Baby erreicht U NICHT -> finale Route unpassierbar")
print("VARIANTE_2_D2_A_SOLVABLE = false")

-- ===========================================================================
--  ZUSAMMENFASSUNG
-- ===========================================================================
print("LEVEL8_D2_VARIANT: pass=" .. pass .. " fail=" .. fail)
check(fail == 0, "level8-d2: D2=B ist die korrekte finale Richtungszuordnung (A wäre Sackgasse)")

TestReport.level8D2Variant = { pass = pass, fail = fail }
