-- level8_full_solution_test.lua — VOLLSTÄNDIGER LÖSBARKEITSBEWEIS für Level 8
-- „Das letzte Band“ (source/data/levels.lua, Levels[8]).
--
-- NUR ECHTE GAMEPLAY-AKTIONEN — keine Teleports, keine State-Manipulation,
-- keine Test-Abkürzungen:
--   Room.movePlayer(delta)   = CW/CCW bewegen (Shutter blockieren, Schalter-
--                              Überquerung löst aus, Baby wird NUR geschoben,
--                              wenn der Player es in Fahrtrichtung erreicht).
--   Room.tryUseConnection()  = echte Bridge-/Gate-Nutzung (solo/shared).
--   Bridge.update(dt)        = echter Transit-Fortschritt bis zum Abschluss.
--
-- Nach JEDEM Schritt wird der Weltzustand protokolliert (STEP-Log) und an
-- jedem kritischen Zustand assertiert (Erreichbarkeit der Route wird durch
-- den erfolgreichen Lauf + gezielte Checks bewiesen). Am Ende wird der ECHTE
-- Raum-Exit (Kernbrücken-Transit am Tor T, gemeinsamer Center-Transit)
-- assertiert — dieselbe Mechanik wie main.lua.
-- Ergebnis wird in TestReport.level8Full gesammelt.

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

-- --- Schritt-Protokoll (liest NUR echte Zustände, setzt nichts) ------------
local stepNo = 0
local function snapshot(label)
    stepNo = stepNo + 1
    local babyTxt = "keins"
    local sideTxt = "-"
    if State.baby then
        babyTxt = State.baby.ring .. "@" .. string.format("%.1f", State.baby.angle)
        local d = Geometry.delta(State.player.angle, State.baby.angle)
        sideTxt = (d > 0) and "Baby CCW-vom-Player -> Player kann CW schieben"
            or "Baby CW-vom-Player -> Player kann CCW schieben"
    end
    local function b(id) return (State.elementStates[id] == true) and "AKTIV" or "inaktiv" end
    local function s(id) return (State.elementStates[id] == true) and "offen" or "ZU" end
    print("STEP " .. stepNo .. ": " .. label)
    print("  ACTION-RESULT:")
    print("  PLAYER = " .. State.player.ring .. "@" .. string.format("%.1f", State.player.angle)
        .. "   BABY = " .. babyTxt .. "   SIDE = " .. sideTxt)
    print("  PLATTEN  P1=" .. tostring(State.platePressed["P1"]) .. "  P2=" .. tostring(State.platePressed["P2"])
        .. "  P3=" .. tostring(State.platePressed["P3"]))
    print("  SCHALTER D1=" .. tostring(State.switchStates["D1"]) .. "  D2=" .. tostring(State.switchStates["D2"])
        .. "  O=" .. tostring(State.switchStates["O"]) .. "  (O-consumed=" .. tostring(State.consumedSwitches["O"] == true) .. ")")
    print("  BRIDGES  A=" .. b("A") .. " B=" .. b("B") .. " C=" .. b("C") .. " D=" .. b("D")
        .. " F=" .. b("F") .. " U=" .. b("U"))
    print("  SHUTTER  S_O=" .. s("S_O") .. " S_D2=" .. s("S_D2") .. " S_FI=" .. s("S_FI")
        .. " S_FD1=" .. s("S_FINAL_D1") .. " S_FD2=" .. s("S_FINAL_D2") .. " S_FO=" .. s("S_FINAL_O"))
end

-- Einfacher Schritt: Bewegen + Ergebnis prüfen, danach protokollieren.
local lastRes
local function actMove(delta, label)
    local _, r = Room.movePlayer(delta)
    lastRes = r
    snapshot(label)
    return r
end

local function actBridge(label)
    lastRes = Room.tryUseConnection()
    Bridge.update(0.5)
    snapshot(label)
    return lastRes
end

-- ===========================================================================
--  STARTZUSTAND (Level 8 frisch)
-- ===========================================================================
snapshot("START")
check(State.player.ring == "outer" and approx(State.player.angle, 20, 0.01), "start: Player outer@20 (Level-7-Ausgang)")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 50, 0.01), "start: Baby outer@50")
check(Geometry.delta(State.player.angle, State.baby.angle) > 0, "start: Baby liegt CW vor dem Player (delta +30) -> Player kann CW schieben")
check(State.platePressed["P1"] == false and State.platePressed["P2"] == false and State.platePressed["P3"] == false, "start: alle 3 Platten frei")
check(State.switchStates["D1"] == "A" and State.switchStates["D2"] == "A" and State.switchStates["O"] == "A", "start: D1=A, D2=A, O=A")
check(State.elementStates["A"] == false and State.elementStates["C"] == false and State.elementStates["D"] == false, "start: A/C/D inaktiv (Platten frei)")
check(State.elementStates["B"] == false and State.elementStates["F"] == false, "start: B/F inaktiv (D1=A, D2=A)")
check(State.elementStates["U"] == true, "start: Einmal-Brücke U FREI aktiv (Falle)")
check(State.elementStates["T"] == true, "start: Tor T aktiv (aber nicht erreichbar)")
check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == false, "start: Tor NICHT nutzbar (Player nicht am Tor, Baby nicht auf dem Gate-Ring)")

-- ===========================================================================
--  PHASE 1: Baby CW auf P1 schieben, Solo über A nach innen
-- ===========================================================================
actMove(101.83, "Baby CW schieben: 50 -> 130 (P1)")
check(State.platePressed["P1"] == true, "p1: Baby EXAKT auf P1 -> Platte gedrückt")
check(State.elementStates["A"] == true, "p1: Bridge A materialisiert (P1 aktiv)")
check(approx(State.player.angle, 121.83), "p1: Player bei ~122 (im A-Dock)")
actBridge("SOLO über Bridge A: outer@122 -> inner@112")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "A", "p1: A-Transit genutzt (echte Brücken-Mechanik)")
check(State.player.ring == "inner" and approx(State.player.angle, 112), "p1: Player inner@112")
check(State.platePressed["P1"] == true, "p1: Baby hält P1 -> A bleibt ausgefahren")

-- ===========================================================================
--  PHASE 2: D1 CCW -> B, Solo über B zurück auf den Außenring (andere Seite)
-- ===========================================================================
actMove(-49, "D1 gegen Uhrzeigersinn überqueren: inner 112 -> 63")
check(State.switchStates["D1"] == "B", "p2: D1=B (CCW-Überquerung)")
check(State.elementStates["B"] == true, "p2: Bridge B materialisiert (D1=B)")
check(State.elementStates["S_O"] == false and State.elementStates["S_FI"] == false and State.elementStates["S_FINAL_D1"] == false, "p2: S_O+S_FI+S_FD1 geschlossen (O-Zugang/finaler Weg zu)")
check(approx(State.player.angle, 63), "p2: Player inner@63 (im B-Dock)")
actBridge("SOLO über Bridge B: inner@63 -> outer@75")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "B", "p2: B-Transit genutzt")
check(State.player.ring == "outer" and approx(State.player.angle, 75), "p2: Player outer@75 — ANDERE Seite des Babys")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 130, 1.0), "p2: Baby weiterhin auf P1 (130)")

-- ===========================================================================
--  PHASE 3: Baby P1 -> P2 schieben (A verschwindet, C erscheint)
-- ===========================================================================
actMove(65.83, "Baby CW schieben: 130 -> 149 (P2)")
check(State.platePressed["P1"] == false, "p3: P1 frei (Baby herunter)")
check(State.elementStates["A"] == false, "p3: Bridge A verschwunden (P1 frei — Route 1 bewusst geopfert)")
check(State.platePressed["P2"] == true, "p3: Baby EXAKT auf P2 -> gedrückt")
check(State.elementStates["C"] == true, "p3: Bridge C materialisiert (P2 aktiv)")
check(approx(State.player.angle, 140.83), "p3: Player bei ~141 (im C-Dock)")

-- ===========================================================================
--  PHASE 4: Solo über C nach innen, D1 B -> A (CW) = ZWISCHENZIEL
-- ===========================================================================
actBridge("SOLO über Bridge C: outer@141 -> inner@132")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "C", "p4: C-Transit genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 132), "p4: Player inner@132")
actMove(-45, "CCW-Anlauf: 132 -> 87 (strikt vor D1-CW-Eintritt 88)")
check(State.switchStates["D1"] == "B", "p4: D1 noch B während des Anlaufs (kein versehentliches Auslösen)")
actMove(15, "D1 mit Uhrzeigersinn überqueren: 87 -> 102")
check(State.switchStates["D1"] == "A", "p4: D1=A (CW-Überquerung) -> ZWISCHENZIEL erreicht")
check(State.elementStates["B"] == false, "p4: Bridge B verschwunden (D1=A)")
check(State.elementStates["S_O"] == true and State.elementStates["S_FI"] == true and State.elementStates["S_FINAL_D1"] == true, "p4: S_O+S_FI+S_FD1 offen (O-Zugang frei)")
check(State.switchStates["D2"] == "A" and State.platePressed["P2"] == true, "p4: Zwischenziel-Bedingung erfüllt (D1=A, D2=A, P2 aktiv)")

-- ===========================================================================
--  PHASE 5: CW durch S_O+S_D2 zu O, O NUR CCW verbrauchen (One-Shot)
-- ===========================================================================
actMove(106, "CW-Zulauf: 102 -> 208 (durch offene S_O+S_D2, O wird auf dem Weg verbraucht)")
check(lastRes.blocked == false, "p5: CW-Zulauf nicht blockiert (S_O+S_D2 offen)")
check(State.switchStates["O"] == "B", "p5: O wird schon bei der CW-Überquerung verbraucht (anyDirection)")
check(State.consumedSwitches["O"] == true, "p5: O DAUERHAFT verbraucht (oneShot)")
check(State.elementStates["S_FINAL_O"] == true, "p5: S_FINAL_O dauerhaft offen")
actMove(-15, "CCW zurück: 208 -> 193 (O bereits verbraucht)")
check(State.switchStates["O"] == "B", "p5: O bleibt verbraucht (One-Shot, kein Retrigger)")
check(approx(State.player.angle, 193), "p5: Player inner@193")

-- ===========================================================================
--  PHASE 6: D1 A -> B (CCW), Solo über B zurück (RICHTIGE Babyseite)
-- ===========================================================================
actMove(-130, "D1 gegen Uhrzeigersinn überqueren: 193 -> 63")
check(State.switchStates["D1"] == "B", "p6: D1=B (B wieder da)")
check(State.elementStates["B"] == true, "p6: Bridge B materialisiert")
check(State.elementStates["S_O"] == false and State.elementStates["S_FI"] == false and State.elementStates["S_FINAL_D1"] == false, "p6: O-Zugang wieder versiegelt")
check(approx(State.player.angle, 63), "p6: Player inner@63 (B-Dock)")
actBridge("SOLO über Bridge B (2.): inner@63 -> outer@75")
check(lastRes.used == true and lastRes.id == "B", "p6: B-Transit (2.) genutzt")
check(State.player.ring == "outer" and approx(State.player.angle, 75), "p6: Player outer@75 — RICHTIGE Seite von Baby/P2")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 149, 1.0), "p6: Baby weiterhin auf P2 (149)")

-- ===========================================================================
--  PHASE 7: Baby P2 -> P3 schieben (C verschwindet, D erscheint)
-- ===========================================================================
actMove(96.83, "Baby CW schieben: 149 -> 180 (P3)")
check(State.platePressed["P2"] == false, "p7: P2 frei (Baby herunter)")
check(State.elementStates["C"] == false, "p7: Bridge C verschwunden")
check(State.platePressed["P3"] == true, "p7: Baby EXAKT auf P3 -> gedrückt")
check(State.elementStates["D"] == true, "p7: Bridge D materialisiert (P3 aktiv)")
check(approx(State.player.angle, 171.83), "p7: Player bei ~172")

-- ===========================================================================
--  PHASE 8: EINSTIEG ÜBER B (D1=B -> B aktiv), D1 B->A, D2 A->B = FINALZUSTAND
-- ===========================================================================
actMove(-96.83, "CCW zu B: 171.83 -> 75 (B-Dock auf dem Außenring, B aktiv weil D1=B)")
check(lastRes.blocked == false, "p8: CCW zu B nicht blockiert")
actBridge("SOLO über Bridge B: outer@75 -> inner@75 (Einstieg)")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "B", "p8: B-Transit (Einstieg) genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 75), "p8: Player inner@75 (Einstieg über B)")
actMove(12, "CW-Anlauf: 75 -> 87")
actMove(15, "D1 mit Uhrzeigersinn überqueren: 87 -> 102")
check(State.switchStates["D1"] == "A", "p8: D1=A — Rückweg-B B geopfert (Rückkehr über B unmöglich, gewollt)")
check(State.elementStates["B"] == false, "p8: Bridge B verschwunden")
check(State.elementStates["S_FI"] == true and State.elementStates["S_FINAL_D1"] == true, "p8: S_FI+S_FD1 offen (finaler Weg entsperrt)")
actMove(146, "D2 CW-Anlauf: 102 -> 248 (durch offenes S_O, O bereits verbraucht; D2-CW = No-op)")
check(State.switchStates["D2"] == "A", "p8: D2 bleibt A beim CW-Vorbeifahren (kein versehentliches Auslösen)")
actMove(-15, "D2 gegen Uhrzeigersinn überqueren: 248 -> 233 (kurzer Dip)")
check(State.switchStates["D1"] == "A", "p8: D1 NICHT erneut ausgelöst (D1=A)")
check(State.switchStates["D2"] == "B", "p8: D2=B — FINALZUSTAND erreicht")
check(State.elementStates["S_D2"] == false, "p8: S_D2 geschlossen (O-Zugang versiegelt, kein Rückweg mehr)")
check(State.elementStates["S_FINAL_D2"] == true, "p8: S_FINAL_D2 offen")
check(State.elementStates["F"] == true, "p8: finale Verbindung F aktiv (D2=B)")
check(approx(State.player.angle, 233), "p8: Player inner@233")

-- ===========================================================================
--  PHASE 9: Solo über D zurück (Baby von P3 holen) — OHNE Schalterüberquerung
-- ===========================================================================
check(State.switchStates["D1"] == "A" and State.switchStates["D2"] == "B", "p9: D1_BEFORE_D = A, D2_BEFORE_D = B (Finalzustand vor dem Weg zu D)")
actMove(-13, "CCW zu D: 233 -> 220 (D-inner-Dock @220 — im freien Abschnitt [191,233])")
check(lastRes.blocked == false, "p9: CCW zu D nicht blockiert (kein S_D2 [165,191] gekreuzt)")
check(lastRes.switchChanges == 0, "p9: PLAYER_CAN_REACH_D_WITHOUT_SWITCH_CROSSING = true (0 Schalterwechsel auf dem Weg)")
check(State.switchStates["D1"] == "A", "p9: D1_AFTER_REACHING_D = A (kein Switch überquert)")
check(State.switchStates["D2"] == "B", "p9: D2_AFTER_REACHING_D = B (kein Switch überquert)")
actBridge("SOLO über Bridge D: inner@220 -> outer@220")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "D", "p9: D_TRANSIT_TO_OUTER = true (D-Transit genutzt)")
check(State.player.ring == "outer" and approx(State.player.angle, 220), "p9: Player outer@220 (Landung an der Brückenachse)")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 180, 1.0), "p9: Baby weiterhin auf P3 (180)")

-- ===========================================================================
--  PHASE 10: Baby zu U schieben, U GEMEINSAM nach innen (One-Use erst JETZT)
-- ===========================================================================
actMove(311.83, "CW umrunden hinter das Baby: 220 -> 171.83 (langer Weg über 0/360, Baby bleibt auf P3)")
check(lastRes.blocked == false, "p10: CW-Anlauf nicht blockiert")
actMove(225, "Baby CW schieben: 180 -> 45 (U)")
check(State.platePressed["P3"] == false, "p10: P3 frei (Baby herunter)")
check(State.elementStates["D"] == false, "p10: Bridge D verschwunden")
check(approx(State.baby.angle, 45, 1.0), "p10: Baby an U (outer@45)")
actBridge("U GEMEINSAM benutzen: outer@37/45 -> inner@45/35")
check(lastRes.used == true and lastRes.kind == "sharedBridge" and lastRes.id == "U", "p10: Shared-Transit über U (echte gemeinsame Mechanik)")
check(State.player.ring == "inner" and approx(State.player.angle, 45), "p10: Player inner@45")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 35), "p10: Baby inner@35 (babyLandDir -1)")
check(State.elementStates["U"] == false, "p10: U NACH dem vollständigen Shared-Transit verbraucht (One-Use)")

-- ===========================================================================
--  PHASE 11: Finaler Push direkt zum Tor (inner@355), gemeinsamer EXIT
-- ===========================================================================
-- Tor T liegt auf dem INNEREN Ring (inner@355). Vom U-Landeplatz
-- (inner@45/Baby@35) schiebt der Player das Baby gegen den Uhrzeigersinn
-- direkt zum Tor — vermeidet S_D2 [165,191] und D2 [233,247], S_FI ist bei
-- D1=A offen. KEIN Schalter wird mehr überquert.
actMove(-40, "Baby CCW schieben direkt zum Tor: 35 -> ~357, Player 45 -> 5")
check(lastRes.blocked == false, "p11: CCW-Schub zum Tor nicht blockiert (S_FI offen, S_D2 umgangen)")
check(lastRes.switchChanges == 0, "p11: KEIN Schalter auf dem Weg zum Tor überquert")
check(State.player.ring == "inner" and approx(State.player.angle, 5), "p11: Player inner@5 (am Tor-Dock)")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 355, 2.0), "p11: Baby am Tor (inner@355)")
check(State.elementStates["S_FINAL_D1"] == true and State.elementStates["S_FINAL_D2"] == true and State.elementStates["S_FINAL_O"] == true, "p11: alle 3 finalen Shutter offen (FINALZUSTAND)")

-- ===========================================================================
--  ECHTER EXIT: Kernbrücken-Transit am Tor T (gemeinsamer Center-Transit)
-- ===========================================================================
check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == true, "exit: Gate T nutzbar (Player+Baby im Dock, alle Shutter offen)")
local resGate = Room.tryUseConnection()
check(resGate.used == true and resGate.kind == "gate" and resGate.crossing == true, "exit: Kernbrücken-Transit AUSGELÖST (echte Gate-Mechanik)")
check(resGate.roomComplete == false, "exit: roomComplete erst nach Transit-Abschluss (Konsistenz)")
local gdone, gshared, _, gcenter = Bridge.update(0.5)
check(gdone == true and gshared == true and gcenter == true, "exit: GEMEINSAMER CENTER-TRANSIT ABGESCHLOSSEN = ROOM COMPLETE (Level 8 geschafft)")
snapshot("EXIT (Level 8 abgeschlossen)")

-- ===========================================================================
--  ZUSAMMENFASSUNG
-- ===========================================================================
print("LEVEL8_FULL_SOLUTION: pass=" .. pass .. " fail=" .. fail)
check(fail == 0, "level8: vollständiger Lösungsdurchlauf OHNE Fehler")

TestReport.level8Full = { pass = pass, fail = fail }
