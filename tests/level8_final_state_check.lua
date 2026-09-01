-- level8_final_state_check.lua — GEZIELTER ENDZUSTANDS-NACHWEIS für Level 8
-- „Das letzte Band“ (source/data/levels.lua, Levels[8]).
--
-- Prüft die gemeldete Sackgassen-Hypothese: Der blockierende Abschnitt OBEN
-- LINKS (S_FINAL_D1@305, S_FINAL_D2@322, S_FINAL_O@340 auf dem Außenring,
-- plus S_FI@295 auf dem Innenring) muss im korrekten FINALZUSTAND offen sein:
--   One-Shot O verbraucht  UND  D1 = A  UND  D2 = B
-- -> der Player kann den Ring vollständig umrunden, die Baby-Seite erreichen
--    und mit dem Baby gemeinsam zum Tor / EXIT kommen.
--
-- NUR ECHTE GAMEPLAY-AKTIONEN — keine Teleports, keine State-Manipulation:
--   Room.movePlayer(delta)  = CW/CCW bewegen (Shutter blockieren, Schalter-
--                             Überquerung löst aus, Baby wird nur geschoben)
--   Room.tryUseConnection() = echte Bridge-/Gate-Nutzung (solo/shared)
--   Bridge.update(dt)       = echter Transit-Fortschritt
--
-- Ergebnis wird in TestReport.level8FinalState gesammelt.

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

-- --- Setup: Level 8 frisch (exakt wie ein Raumstart) -----------------------
State.init(Levels[8], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[8].rings.outer)
Render.resetPlayerVisual()

-- Physischer Kollisionszustand einer Blende (echter State, read-only).
local function physClosed(id)
    local p = Room.shutters[id]
    return p ~= nil and p.collisionActive == true
end

-- ===========================================================================
--  VOLLSTÄNDIGER SOLLWEG (echte Aktionen) bis in den FINALZUSTAND
-- ===========================================================================
-- Phase 1: Baby CW auf P1, Solo über A nach innen.
Room.movePlayer(101.83) -- 20 -> 121.83, Baby 50 -> 130 (P1)
Room.tryUseConnection() -- A solo -> inner@112
Bridge.update(0.5)
-- Phase 2: D1 CCW -> B, Solo über B zurück.
Room.movePlayer(-49)    -- 112 -> 63 (D1 CCW -> B)
Room.tryUseConnection() -- B solo -> outer@75
Bridge.update(0.5)
-- Phase 3: Baby P1 -> P2, Solo über C.
Room.movePlayer(65.83)  -- 75 -> 140.83, Baby 130 -> 149 (P2)
Room.tryUseConnection() -- C solo -> inner@132
Bridge.update(0.5)
-- Phase 4: D1 B -> A (CW) = Zwischenziel.
Room.movePlayer(-45)    -- 132 -> 87 (Anlauf vor D1-CW-Eintritt)
Room.movePlayer(15)     -- 87 -> 102 (D1 CW -> A)
-- Phase 5: O verbrauchen (One-Shot, anyDirection: CW-Überquerung zählt).
local _, r5 = Room.movePlayer(106) -- 102 -> 208 (O wird verbraucht, S_FINAL_O offen)
check(r5.blocked == false, "fs: CW-Zulauf zu O nicht blockiert (S_O+S_D2 offen)")
check(State.consumedSwitches["O"] == true, "fs: One-Shot O verbraucht")
check(State.switchStates["O"] == "B", "fs: O = B (S_FINAL_O logisch offen)")
Room.movePlayer(-15)    -- 208 -> 193
-- Phase 6: D1 A -> B, Solo über B (richtige Babyseite).
Room.movePlayer(-130)   -- 193 -> 63 (D1 CCW -> B)
Room.tryUseConnection() -- B solo -> outer@75
Bridge.update(0.5)
-- Phase 7: Baby P2 -> P3.
Room.movePlayer(96.83)  -- 75 -> 171.83, Baby 149 -> 180 (P3)
-- Phase 8: Einstieg über B (B aktiv, D1=B), D1 B->A, D2 A->B = FINALZUSTAND.
Room.movePlayer(-96.83)-- 171.83 -> 75 (CCW zu B, B aktiv weil D1=B)
Room.tryUseConnection() -- B solo -> inner@75
Bridge.update(0.5)
Room.movePlayer(12)     -- 75 -> 87 (D1-Anlauf)
Room.movePlayer(15)     -- 87 -> 102 (D1 CW -> A)
Room.movePlayer(146)    -- CW 102 -> 248 (D2-CW = No-op, bleibt A)
Room.movePlayer(-15)    -- CCW 248 -> 233 (D2 CCW -> B)

-- ===========================================================================
--  FINALZUSTAND ASSERTIEREN
-- ===========================================================================
check(State.switchStates["D1"] == "A", "final: D1 = A (final)")
check(State.switchStates["D2"] == "B", "final: D2 = B (final)")
check(State.consumedSwitches["O"] == true, "final: One-Shot O verbraucht")
check(State.player.ring == "inner" and approx(State.player.angle, 233), "final: Player inner@233 (nach D2=B)")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 180, 1.0), "final: Baby weiterhin auf P3 (180)")

-- --- UPPER_LEFT_SHUTTER_OPEN_IN_FINAL_STATE --------------------------------
check(not physClosed("S_FINAL_D1"), "UPPER_LEFT_SHUTTER_OPEN_IN_FINAL_STATE: S_FINAL_D1 physisch OFFEN (D1=A)")
check(not physClosed("S_FINAL_D2"), "UPPER_LEFT_SHUTTER_OPEN_IN_FINAL_STATE: S_FINAL_D2 physisch OFFEN (D2=B)")
check(not physClosed("S_FINAL_O"), "UPPER_LEFT_SHUTTER_OPEN_IN_FINAL_STATE: S_FINAL_O physisch OFFEN (O verbraucht)")
check(not physClosed("S_FI"), "UPPER_LEFT_SHUTTER_OPEN_IN_FINAL_STATE: S_FI (inner@295) physisch OFFEN (D1=A)")
-- Der komplette obere linke Ringabschnitt (inner+outer) ist damit frei.

-- --- PLAYER_CAN_PASS --------------------------------------------------------
-- Player erreicht D direkt aus dem Finalzustand: inner 233 -> 220 (D-inner-
-- Dock im freien Abschnitt [191,233], KEIN Schalter überquert), dann Solo
-- über D zurück auf den Außenring (Baby-Seite).
local _, rPass1 = Room.movePlayer(-13) -- 233 -> 220 (zu D)
check(rPass1.blocked == false, "PLAYER_CAN_PASS: inner 233->220 (zu D) NICHT blockiert")
check(rPass1.switchChanges == 0, "PLAYER_CAN_PASS: KEIN Switch auf dem Weg zu D überquert")
check(State.switchStates["D1"] == "A" and State.switchStates["D2"] == "B", "PLAYER_CAN_PASS: D1=A und D2=B UNVERÄNDERT (Finalzustand erhalten)")
local rD2 = Room.tryUseConnection() -- D solo -> outer@220
Bridge.update(0.5)
check(rD2.used == true and rD2.id == "D", "PLAYER_CAN_PASS: Solo über D zurück -> outer@220")
check(State.player.ring == "outer" and approx(State.player.angle, 220), "PLAYER_CAN_PASS: Player outer@220")
-- Vollständige Umrundung zur Baby-Seite (CW hinter das Baby — Baby@180 liegt
-- CCW vom Player@220, CCW-Ansatz würde das Baby von P3 schieben).
local _, rPass2 = Room.movePlayer(311.83) -- 220 -> 171.83 (CW über 0/360, hinter Baby@180)
check(rPass2.blocked == false, "PLAYER_CAN_PASS: outer 220->171.83 (Umrundung zur Baby-Seite) NICHT blockiert")
check(approx(State.player.angle, 171.83), "PLAYER_CAN_PASS: Player bei ~172 (Kontakt hinter Baby)")

-- --- PLAYER_CAN_REACH_CORRECT_BABY_SIDE ------------------------------------
-- Der Player steht jetzt CCW vom Baby (171.83 < 180): er kann das Baby CW in
-- Richtung U schieben — das ist die für Baby/Exit benötigte Seite.
check(Geometry.delta(State.player.angle, State.baby.angle) > 0, "PLAYER_CAN_REACH_CORRECT_BABY_SIDE: Baby liegt CW vor dem Player (Player kann CW schieben)")

-- --- PLAYER_AND_BABY_CAN_REACH_EXIT ----------------------------------------
-- Baby CW durch den OBEREN LINKEN Ringabschnitt schieben (180 -> 45 = U):
-- genau hier würde eine geschlossene Blockade oben links das Baby stoppen.
local _, rPush = Room.movePlayer(225) -- Baby 180 -> 45 (CW durch S_FD1/S_FD2/S_FO)
check(rPush.blocked == false, "PLAYER_AND_BABY_CAN_REACH_EXIT: Baby-Schub 180->45 durch OBEN LINKS NICHT blockiert")
check(State.baby ~= nil and approx(State.baby.angle, 45, 1.0), "PLAYER_AND_BABY_CAN_REACH_EXIT: Baby an U (outer@45)")
local rU = Room.tryUseConnection() -- U GEMEINSAM -> inner
Bridge.update(0.5)
check(rU.used == true and rU.kind == "sharedBridge" and rU.id == "U", "PLAYER_AND_BABY_CAN_REACH_EXIT: U GEMEINSAM benutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 45), "PLAYER_AND_BABY_CAN_REACH_EXIT: Player inner@45")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 35), "PLAYER_AND_BABY_CAN_REACH_EXIT: Baby inner@35")
-- Tor T liegt auf dem INNEREN Ring (inner@355). Vom U-Landeplatz
-- (inner@45/Baby@35) schiebt der Player das Baby CCW direkt zum Tor —
-- S_FI ist bei D1=A offen, S_D2 [165,191] wird umgangen.
local _, rFinal = Room.movePlayer(-40) -- Player 45 -> 5, Baby 35 -> ~357 (Tor)
check(rFinal.blocked == false, "PLAYER_AND_BABY_CAN_REACH_EXIT: direkter Schub zum Tor (inner@355) NICHT blockiert")
check(State.player.ring == "inner" and approx(State.player.angle, 5), "PLAYER_AND_BABY_CAN_REACH_EXIT: Player inner@5 (Tor-Dock)")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 355, 2.0), "PLAYER_AND_BABY_CAN_REACH_EXIT: Baby am Tor (inner@355)")

-- --- REAL_ROOM_COMPLETE ------------------------------------------------------
check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == true, "REAL_ROOM_COMPLETE: Gate T nutzbar (Player+Baby im Dock)")
local resGate = Room.tryUseConnection()
check(resGate.used == true and resGate.kind == "gate" and resGate.crossing == true, "REAL_ROOM_COMPLETE: Kernbrücken-Transit AUSGELÖST (echte Gate-Mechanik)")
local gdone, gshared, _, gcenter = Bridge.update(0.5)
check(gdone == true and gshared == true and gcenter == true, "REAL_ROOM_COMPLETE: GEMEINSAMER CENTER-TRANSIT ABGESCHLOSSEN = ROOM COMPLETE")

-- ===========================================================================
--  ZUSAMMENFASSUNG
-- ===========================================================================
print("LEVEL8_FINAL_STATE: pass=" .. pass .. " fail=" .. fail)
check(fail == 0, "level8-final: Endzustand (O+D1=A+D2=B) OHNE Sackgasse — oberer linker Abschnitt offen")

TestReport.level8FinalState = { pass = pass, fail = fail }
