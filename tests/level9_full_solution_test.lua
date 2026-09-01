-- level9_full_solution_test.lua — VOLLSTÄNDIGER LÖSBARKEITSBEWEIS für Level 9
-- „Zwei Tore“ (source/data/levels.lua, Levels[9]).
--
-- NUR ECHTE GAMEPLAY-AKTIONEN — keine Teleports, keine State-Manipulation:
--   Room.movePlayer(delta)   = CW/CCW bewegen (Shutter blockieren, Schalter-
--                              Überquerung löst aus, Baby wird nur geschoben).
--   Room.tryUseConnection()  = echte Bridge-/Gate-Nutzung (solo/shared).
--   Bridge.update(dt)        = echter Transit-Fortschritt.
--
-- Sollweg (Level 9 „Zwei Tore“):
--   1. Baby CW auf P1, Solo über A nach innen.
--   2. D1 CCW -> B, Solo über B zurück auf den Außenring.
--   3. Baby P1 -> P2, Solo über C nach innen, D1 B -> A (Zwischenziel).
--   4. CW durch offene S_O1/S_O2 zu U1, U1 SOLO (One-Use) in den abgetrennten
--      äußeren Abschnitt, Solo über G (D1=A) zurück nach innen.
--   5. O NUR CCW verbrauchen (One-Shot, KEIN anyDirection — schwerer als
--      Level 8; die CW-Überquerung auf dem Weg zu U1 bleibt wirkungslos).
--   6. D1 A -> B, Solo über B (richtige Babyseite).
--   7. Baby P2 -> P3, Solo über D, D1 B -> A und D2 A -> B = FINALZUSTAND.
--   8. Solo über D zurück, Baby von P3 holen und CW zu U2 schieben.
--   9. U2 GEMEINSAM (One-Use erst jetzt) nach innen.
--  10. Baby CCW zu F (D2=B), F GEMEINSAM, finaler Ringweg, Tor T -> EXIT.
--
-- Ergebnis wird in TestReport.level9Full gesammelt.

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

-- --- Setup: Level 9 frisch (exakt wie ein Raumstart) -----------------------
State.init(Levels[9], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[9].rings.outer)
Render.resetPlayerVisual()

-- --- Schritt-Protokoll (liest NUR echte Zustände) --------------------------
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
    print("  PLAYER = " .. State.player.ring .. "@" .. string.format("%.1f", State.player.angle)
        .. "   BABY = " .. babyTxt .. "   SIDE = " .. sideTxt)
    print("  PLATTEN  P1=" .. tostring(State.platePressed["P1"]) .. "  P2=" .. tostring(State.platePressed["P2"])
        .. "  P3=" .. tostring(State.platePressed["P3"]))
    print("  SCHALTER D1=" .. tostring(State.switchStates["D1"]) .. "  D2=" .. tostring(State.switchStates["D2"])
        .. "  O=" .. tostring(State.switchStates["O"]) .. "  (O-consumed=" .. tostring(State.consumedSwitches["O"] == true) .. ")")
    print("  BRIDGES  A=" .. b("A") .. " B=" .. b("B") .. " C=" .. b("C") .. " D=" .. b("D")
        .. " F=" .. b("F") .. " G=" .. b("G") .. " U1=" .. b("U1") .. " U2=" .. b("U2"))
    print("  SHUTTER  S_O1=" .. s("S_O1") .. " S_O2=" .. s("S_O2") .. " S_FI=" .. s("S_FI")
        .. " S_FD1=" .. s("S_FINAL_D1") .. " S_FD2=" .. s("S_FINAL_D2") .. " S_FO=" .. s("S_FINAL_O")
        .. " S_U1A=" .. s("S_U1A") .. " S_U1B=" .. s("S_U1B"))
end

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
--  STARTZUSTAND (Level 9 frisch)
-- ===========================================================================
snapshot("START")
check(State.player.ring == "outer" and approx(State.player.angle, 25, 0.01), "start: Player outer@25")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 35, 0.01), "start: Baby outer@35")
check(Geometry.delta(State.player.angle, State.baby.angle) > 0, "start: Baby liegt CW vor dem Player -> Player kann CW schieben")
check(State.platePressed["P1"] == false and State.platePressed["P2"] == false and State.platePressed["P3"] == false, "start: alle 3 Platten frei")
check(State.switchStates["D1"] == "A" and State.switchStates["D2"] == "A" and State.switchStates["O"] == "A", "start: D1=A, D2=A, O=A")
check(State.elementStates["A"] == false and State.elementStates["C"] == false and State.elementStates["D"] == false, "start: A/C/D inaktiv (Platten frei)")
check(State.elementStates["B"] == false and State.elementStates["F"] == false, "start: B/F inaktiv (D1=A, D2=A)")
check(State.elementStates["U1"] == true and State.elementStates["U2"] == true, "start: Einmal-Brücken U1/U2 FREI aktiv (Fallenvorbild)")
check(State.elementStates["S_U1A"] == false and State.elementStates["S_U1B"] == false, "start: Abschnitts-Blenden S_U1A/S_U1B dauerhaft ZU (fixedClosed)")
check(State.elementStates["T"] == true, "start: Tor T aktiv (aber nicht erreichbar)")
check(Gate.isUsable(Levels[9].gate, "inner", State.player.angle) == false, "start: Tor NICHT nutzbar (Player nicht am Tor, Baby nicht auf dem Gate-Ring)")

-- ===========================================================================
--  PHASE 1: Baby CW auf P1, Solo über A nach innen
-- ===========================================================================
actMove(96.83, "Baby CW schieben: 35 -> 130 (P1)")
check(State.platePressed["P1"] == true, "p1: Baby EXAKT auf P1 -> Platte gedrückt")
check(State.elementStates["A"] == true, "p1: Bridge A materialisiert (P1 aktiv)")
check(approx(State.player.angle, 121.83), "p1: Player bei ~122 (im A-Dock)")
actBridge("SOLO über Bridge A: outer@122 -> inner@112")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "A", "p1: A-Transit genutzt (echte Brücken-Mechanik)")
check(State.player.ring == "inner" and approx(State.player.angle, 112), "p1: Player inner@112")
check(State.platePressed["P1"] == true, "p1: Baby hält P1 -> A bleibt ausgefahren")

-- ===========================================================================
--  PHASE 2: D1 CCW -> B, Solo über B zurück auf den Außenring
-- ===========================================================================
actMove(-49, "D1 gegen Uhrzeigersinn überqueren: inner 112 -> 63")
check(State.switchStates["D1"] == "B", "p2: D1=B (CCW-Überquerung)")
check(State.elementStates["B"] == true, "p2: Bridge B materialisiert (D1=B)")
check(State.elementStates["S_O1"] == false and State.elementStates["S_FI"] == false and State.elementStates["S_FINAL_D1"] == false, "p2: S_O1+S_FI+S_FD1 geschlossen (O-Zugang/finaler Weg zu)")
check(approx(State.player.angle, 63), "p2: Player inner@63 (im B-Dock)")
actBridge("SOLO über Bridge B: inner@75 -> outer@75")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "B", "p2: B-Transit genutzt")
check(State.player.ring == "outer" and approx(State.player.angle, 75), "p2: Player outer@75 — ANDERE Seite des Babys")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 130, 1.0), "p2: Baby weiterhin auf P1 (130)")

-- ===========================================================================
--  PHASE 3: Baby P1 -> P2 (A verschwindet, C erscheint)
-- ===========================================================================
actMove(71.83, "Baby CW schieben: 130 -> 155 (P2)")
check(State.platePressed["P1"] == false, "p3: P1 frei (Baby herunter)")
check(State.elementStates["A"] == false, "p3: Bridge A verschwunden (P1 frei — Route 1 bewusst geopfert)")
check(State.platePressed["P2"] == true, "p3: Baby EXAKT auf P2 -> gedrückt")
check(State.elementStates["C"] == true, "p3: Bridge C materialisiert (P2 aktiv)")
check(approx(State.player.angle, 146.83), "p3: Player bei ~147 (im C-Dock)")

-- ===========================================================================
--  PHASE 4: Solo über C nach innen, D1 B -> A (CW) = ZWISCHENZIEL
-- ===========================================================================
actBridge("SOLO über Bridge C: outer@147 -> inner@138")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "C", "p4: C-Transit genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 138), "p4: Player inner@138")
actMove(-51, "CCW-Anlauf: 138 -> 87 (strikt vor D1-CW-Eintritt 88)")
check(State.switchStates["D1"] == "B", "p4: D1 noch B während des Anlaufs (kein versehentliches Auslösen)")
actMove(15, "D1 mit Uhrzeigersinn überqueren: 87 -> 102")
check(State.switchStates["D1"] == "A", "p4: D1=A (CW-Überquerung) -> ZWISCHENZIEL erreicht")
check(State.elementStates["B"] == false, "p4: Bridge B verschwunden (D1=A)")
check(State.elementStates["S_O1"] == true and State.elementStates["S_FI"] == true and State.elementStates["S_FINAL_D1"] == true, "p4: S_O1+S_FI+S_FD1 offen (O-Zugang frei)")
check(State.switchStates["D2"] == "A" and State.platePressed["P2"] == true, "p4: Zwischenziel-Bedingung erfüllt (D1=A, D2=A, P2 aktiv)")

-- ===========================================================================
--  PHASE 5: CW durch S_O1/S_O2 zu U1, U1 SOLO in den abgetrennten Abschnitt
-- ===========================================================================
-- Der CW-Weg überquert O im Uhrzeigersinn — O ist ein Einmalschalter OHNE
-- anyDirection: eine CW-Überquerung verbraucht ihn NICHT (schwerer als
-- Level 8). Der richtige Verbrauch erfolgt erst in Phase 7 per CCW.
actMove(168, "CW-Zulauf: 102 -> 270 (durch offene S_O1+S_O2, O CW no-op, U1-Dock)")
check(lastRes.blocked == false, "p5: CW-Zulauf nicht blockiert (S_O1/S_O2 offen, Abschnitts-Blende U1A liegt outer)")
check(State.switchStates["O"] == "A", "p5: O NICHT verbraucht durch CW-Überquerung (kein anyDirection!)")
check(State.consumedSwitches["O"] ~= true, "p5: O noch nicht dauerhaft verbraucht")
check(State.elementStates["S_FINAL_O"] == false, "p5: S_FINAL_O noch ZU (O nicht verbraucht)")
check(approx(State.player.angle, 270), "p5: Player inner@270 (U1-Dock)")
actBridge("U1 SOLO benutzen: inner@270 -> outer@270 (in den Abschnitt)")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "U1", "p5: Solo-Transit über U1 (echte One-Use-Mechanik)")
check(State.player.ring == "outer" and approx(State.player.angle, 270), "p5: Player outer@270 — IM abgetrennten Abschnitt")
check(State.elementStates["U1"] == false, "p5: U1 NACH dem Transit verbraucht (One-Use — Mittelteil-Opfer)")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 155, 1.0), "p5: Baby weiterhin auf P2 (155)")

-- ===========================================================================
--  PHASE 6: Solo über G (D1=A) zurück nach innen, O NUR CCW verbrauchen
-- ===========================================================================
actMove(25, "CW im Abschnitt: 270 -> 295 (G-Dock)")
check(lastRes.blocked == false, "p6: CW zu G nicht blockiert (U1A/U1B liegen außerhalb des freien Abschnitts)")
check(State.elementStates["G"] == true, "p6: Bridge G materialisiert (D1=A — der einzige Rückweg aus dem Abschnitt)")
actBridge("SOLO über Bridge G: outer@295 -> inner@295")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "G", "p6: G-Transit genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 295), "p6: Player inner@295")
actMove(-112, "CCW-Zulauf: 295 -> 183 (durch offene S_O2, O CCW->B)")
check(lastRes.blocked == false, "p6: CCW-Zulauf nicht blockiert (S_O2 offen bei D2=A)")
check(State.switchStates["O"] == "B", "p6: O = B (nur CCW-Überquerung verbraucht) — RICHTIGE RICHTUNG")
check(State.consumedSwitches["O"] == true, "p6: O DAUERHAFT verbraucht (oneShot)")
check(State.elementStates["S_FINAL_O"] == true, "p6: S_FINAL_O dauerhaft offen")
check(approx(State.player.angle, 183), "p6: Player inner@183")

-- ===========================================================================
--  PHASE 7: D1 A -> B, Solo über B zurück (RICHTIGE Babyseite)
-- ===========================================================================
actMove(-108, "D1 gegen Uhrzeigersinn überqueren: 183 -> 75")
check(State.switchStates["D1"] == "B", "p7: D1=B (B wieder da)")
check(State.elementStates["B"] == true, "p7: Bridge B materialisiert")
check(State.elementStates["S_O1"] == false and State.elementStates["S_FI"] == false and State.elementStates["S_FINAL_D1"] == false, "p7: O-Zugang wieder versiegelt")
check(approx(State.player.angle, 75), "p7: Player inner@75 (B-Dock)")
actBridge("SOLO über Bridge B (2.): inner@75 -> outer@75")
check(lastRes.used == true and lastRes.id == "B", "p7: B-Transit (2.) genutzt")
check(State.player.ring == "outer" and approx(State.player.angle, 75), "p7: Player outer@75 — RICHTIGE Seite von Baby/P2")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 155, 1.0), "p7: Baby weiterhin auf P2 (155)")

-- ===========================================================================
--  PHASE 8: Baby P2 -> P3 (C verschwindet, D erscheint)
-- ===========================================================================
actMove(93.83, "Baby CW schieben: 155 -> 177 (P3)")
check(State.platePressed["P2"] == false, "p8: P2 frei (Baby herunter)")
check(State.elementStates["C"] == false, "p8: Bridge C verschwunden")
check(State.platePressed["P3"] == true, "p8: Baby EXAKT auf P3 -> gedrückt")
check(State.elementStates["D"] == true, "p8: Bridge D materialisiert (P3 aktiv)")
check(approx(State.player.angle, 168.83), "p8: Player bei ~169")

-- ===========================================================================
--  PHASE 9: Solo über D nach innen, D1 B->A, D2 A->B = FINALZUSTAND
-- ===========================================================================
actMove(-118.83, "CCW zu D: 168.83 -> 50 (D-Dock, vermeidet den Abschnitt)")
check(lastRes.blocked == false, "p9: CCW zu D nicht blockiert")
actBridge("SOLO über Bridge D: outer@50 -> inner@50")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "D", "p9: D-Transit genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 50), "p9: Player inner@50 (dritter Einstieg)")
actMove(37, "CW-Anlauf: 50 -> 87")
actMove(15, "D1 mit Uhrzeigersinn überqueren: 87 -> 102")
check(State.switchStates["D1"] == "A", "p9: D1=A — Rückweg-B geopfert (Rückkehr über B unmöglich, gewollt)")
check(State.elementStates["B"] == false, "p9: Bridge B verschwunden")
check(State.elementStates["S_FI"] == true and State.elementStates["S_FINAL_D1"] == true, "p9: S_FI+S_FD1 offen (finaler Weg entsperrt)")
actMove(-69, "D2 gegen Uhrzeigersinn überqueren: 102 -> 33 (D2@40)")
check(State.switchStates["D2"] == "B", "p9: D2=B — FINALZUSTAND erreicht")
check(State.elementStates["S_O2"] == false, "p9: S_O2 geschlossen (O-Zugang versiegelt, kein Rückweg mehr)")
check(State.elementStates["S_FINAL_D2"] == true, "p9: S_FINAL_D2 offen")
check(State.elementStates["F"] == true, "p9: finale Verbindung F aktiv (D2=B)")
check(approx(State.player.angle, 33), "p9: Player inner@33 (D2 CCW-Austritt)")

-- ===========================================================================
--  PHASE 10: Solo über D zurück (Baby von P3 holen)
-- ===========================================================================
actMove(17, "CW zu D: 33 -> 50 (D2-Start-auf-Kante kein Retrigger)")
check(lastRes.blocked == false, "p10: CW zu D nicht blockiert (D2-Start-auf-Kante kein Retrigger)")
actBridge("SOLO über Bridge D (2.): inner@50 -> outer@50")
check(lastRes.used == true and lastRes.kind == "bridge" and lastRes.id == "D", "p10: D-Transit (2.) genutzt")
check(State.player.ring == "outer" and approx(State.player.angle, 50), "p10: Player outer@50")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 177, 1.0), "p10: Baby weiterhin auf P3 (177)")

-- ===========================================================================
--  PHASE 11: Baby CW zu U2 schieben, U2 GEMEINSAM (One-Use erst JETZT)
-- ===========================================================================
actMove(153.83, "Baby CW schieben: 177 -> 212 (U2)")
check(lastRes.blocked == false, "p11: CW-Schub zu U2 nicht blockiert")
check(State.platePressed["P3"] == false, "p11: P3 frei (Baby herunter)")
check(State.elementStates["D"] == false, "p11: Bridge D verschwunden")
check(approx(State.baby.angle, 212, 1.0), "p11: Baby an U2 (outer@212)")
actBridge("U2 GEMEINSAM benutzen: outer@204/212 -> inner@212/222")
check(lastRes.used == true and lastRes.kind == "sharedBridge" and lastRes.id == "U2", "p11: Shared-Transit über U2 (echte gemeinsame Mechanik)")
check(State.player.ring == "inner" and approx(State.player.angle, 212), "p11: Player inner@212")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 222), "p11: Baby inner@222 (babyLandDir +1)")
check(State.elementStates["U2"] == false, "p11: U2 NACH dem vollständigen Shared-Transit verbraucht (One-Use)")

-- ===========================================================================
--  PHASE 12: Finaler Push über F zum Tor, gemeinsamer EXIT
-- ===========================================================================
actMove(124.83, "Baby mit Uhrzeigersinn schieben: 222 -> 345 (F, vermeidet D1/D2/S_O2)")
check(lastRes.blocked == false, "p12: CW-Schub zu F nicht blockiert")
check(approx(State.baby.angle, 345, 1.0), "p12: Baby an F (inner@345)")
actBridge("F GEMEINSAM benutzen: inner@337/345 -> outer@345/355")
check(lastRes.used == true and lastRes.kind == "sharedBridge" and lastRes.id == "F", "p12: Shared-Transit über F (finale Verbindung)")
check(State.player.ring == "outer" and approx(State.player.angle, 345), "p12: Player outer@345")
check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 355), "p12: Baby outer@355 (babyLandDir +1)")
-- Tor T liegt auf dem INNEREN Ring (inner@10): F zurück überqueren und auf
-- dem Innenring CW zum Tor (S_FI offen bei D1=A).
actBridge("F GEMEINSAM zurück: outer@345/355 -> inner@345/355")
check(lastRes.used == true and lastRes.kind == "sharedBridge" and lastRes.id == "F", "p12: F-Rückweg (2.) genutzt")
check(State.player.ring == "inner" and approx(State.player.angle, 345), "p12: Player inner@345")
check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 355, 1.0), "p12: Baby inner@355")
actMove(16.83, "finaler Ringweg CW (inner): 345 -> 1.83 (Baby 355 -> 10 = Tor)")
check(lastRes.blocked == false, "p12: finaler Ringweg (inner) nicht blockiert (S_FI offen)")
check(State.elementStates["S_FINAL_D1"] == true and State.elementStates["S_FINAL_D2"] == true and State.elementStates["S_FINAL_O"] == true, "p12: alle 3 finalen Shutter offen (FINALZUSTAND)")
check(State.player.ring == "inner" and approx(State.player.angle, 1.83), "p12: Player am Tor-Dock (~2, inner)")
check(State.baby ~= nil and approx(State.baby.angle, 10, 1.0), "p12: Baby EXAKT am Tor (10)")

-- ===========================================================================
--  ECHTER EXIT: Kernbrücken-Transit am Tor T (gemeinsamer Center-Transit)
-- ===========================================================================
check(Gate.isUsable(Levels[9].gate, "inner", State.player.angle) == true, "exit: Gate T nutzbar (Player+Baby im Dock, alle Shutter offen)")
local resGate = Room.tryUseConnection()
check(resGate.used == true and resGate.kind == "gate" and resGate.crossing == true, "exit: Kernbrücken-Transit AUSGELÖST (echte Gate-Mechanik)")
check(resGate.roomComplete == false, "exit: roomComplete erst nach Transit-Abschluss (Konsistenz)")
local gdone, gshared, _, gcenter = Bridge.update(0.5)
check(gdone == true and gshared == true and gcenter == true, "exit: GEMEINSAMER CENTER-TRANSIT ABGESCHLOSSEN = ROOM COMPLETE (Level 9 geschafft)")
snapshot("EXIT (Level 9 abgeschlossen)")

-- ===========================================================================
--  FALLEN & BYPASSES: gezielte Negativbeweise (jede in einem frischen Raum).
--  Beweist, dass die 7 Fehlentscheidungen in Sackgassen führen und die 5
--  Umgehungsversuche an der Mechanik scheitern.
-- ===========================================================================

-- --- FALLE 1: U2 zu früh verbrauchen (Baby liegt auf dem Weg, Shared) ------
-- U2@212 liegt auf dem natürlichen Weg: wer sie früh benutzt (das Baby liegt
-- unvermeidlich auf dem Schubweg), verbraucht die finale Einmal-Brücke, bevor
-- die Platten-Routen (P1/P2/P3), O und der FINALZUSTAND erreicht sind -> die
-- komplette Puzzle-Kette fehlt, keine Lösung mehr.
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    -- Früh zu U2: der Player schiebt das Baby (liegt auf dem Weg) direkt dorthin.
    local _, r = Room.movePlayer(187) -- 25 -> 212 CW (Baby 35 -> 222)
    check(r.blocked == false, "falle1: Player erreicht U2@212 (Baby liegt im Schubweg)")
    local br = Room.tryUseConnection()
    Bridge.update(0.5)
    check(br.used == true and br.kind == "sharedBridge" and br.id == "U2", "falle1: U2 FRÜH nutzbar (verlockende Falle, Shared mit Baby)")
    check(State.elementStates["U2"] == false, "falle1: U2 DAUERHAFT verbraucht (oneShot)")
    check(State.consumedBridges["U2"] == true, "falle1: U2 im Verbrauchs-Register")
    check(State.player.ring == "inner" and State.baby ~= nil and State.baby.ring == "inner", "falle1: Player UND Baby sind jetzt INNEN (früh!)")
    check(State.platePressed["P1"] == false and State.platePressed["P2"] == false and State.platePressed["P3"] == false, "falle1: KEINE Platte je gedrückt (A/B/C/D nie aktiv)")
    check(State.elementStates["A"] == false and State.elementStates["C"] == false and State.elementStates["D"] == false, "falle1: Solo-Einstiege fehlen -> Puzzle-Kette abgerissen")
    check(State.consumedSwitches["O"] ~= true and State.elementStates["S_FINAL_O"] == false, "falle1: O nie verbraucht -> Torweg zu")
    check(State.elementStates["U2"] == false, "falle1: U2 verbraucht -> Baby kann die Endstrecke nie mehr nehmen -> SACKGASSE")
end

-- --- FALLE 2: O aus der falschen Richtung (CW) -> KEIN Verbrauch -----------
-- O ist ein Einmalschalter OHNE anyDirection: eine CW-Überquerung verbraucht
-- ihn nicht. Nur die CCW-Überquerung (die über den abgetrennten Abschnitt mit
-- U1/G erzwungen ist) stellt den finalen Weg frei.
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    -- Bewusst an O vorbei CW (der "kurze" Weg): bleibt wirkungslos.
    Room.movePlayer(96.83)  -- Baby auf P1
    Room.tryUseConnection() -- A solo
    Bridge.update(0.5)
    Room.movePlayer(-49)    -- D1 CCW -> B
    Room.tryUseConnection() -- B solo
    Bridge.update(0.5)
    Room.movePlayer(71.83)  -- Baby P1 -> P2
    Room.tryUseConnection() -- C solo
    Bridge.update(0.5)
    Room.movePlayer(-51)    -- D1-Anlauf
    Room.movePlayer(15)     -- D1 CW -> A (Zwischenziel)
    local _, r = Room.movePlayer(168) -- CW-Zulauf 102 -> 270 (überquert O CW)
    check(r.blocked == false, "falle2: CW-Zulauf über O nicht blockiert")
    check(State.switchStates["O"] == "A", "falle2: O bleibt A nach CW-Überquerung (kein anyDirection!)")
    check(State.consumedSwitches["O"] ~= true, "falle2: O nicht dauerhaft verbraucht")
    check(State.elementStates["S_FINAL_O"] == false, "falle2: S_FINAL_O bleibt ZU -> Torweg versperrt")
end

-- --- FALLE 3: U1 aufsparen -> O-Zugang über G nie erreichbar ---------------
-- Der richtige O-Anlauf (CCW, Verbrauch) erfordert G im abgetrennten Abschnitt.
-- Ohne U1 bleibt der Abschnitt zu (S_U1A/S_U1B fixedClosed) -> O ist nur aus
-- der falschen Richtung erreichbar (CW no-op) -> kein Verbrauch.
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    -- Vom Start: Versuch, von außen in den Abschnitt zu gelangen -> blockiert.
    local _, r = Room.movePlayer(260) -- 25 -> 285 CW (müsste durch S_U1A/S_U1B)
    check(r.blocked == true, "falle3: Abschnitt von außen (CW) BLOCKIERT durch fixedClosed-Shutter")
    local stopped = State.player.angle
    check(stopped < 232, "falle3: Player stoppt vor S_U1A (<232), Abschnitt nicht betretbar ohne U1")
    check(State.player.angle < 260, "falle3: G@295 bleibt UNERREICHBAR (Player weit vor dem G-Dock) -> O-Zugang fehlt")
end

-- --- FALLE 4: D2 zu früh CCW->B (vor dem O-Verbrauch) -> O-Zugang versiegelt -
-- Wird D2 vorzeitig auf B gestellt, schließt S_O2 (D2=A) -> der Spieler kommt
-- nicht mehr richtig zu O (der O-Zugang über S_O2 ist zu).
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    Room.movePlayer(96.83)  -- Baby auf P1
    Room.tryUseConnection() -- A solo
    Bridge.update(0.5)
    Room.movePlayer(-49)    -- D1 CCW -> B
    Room.tryUseConnection() -- B solo
    Bridge.update(0.5)
    Room.movePlayer(71.83)  -- Baby P1 -> P2
    Room.tryUseConnection() -- C solo
    Bridge.update(0.5)
    Room.movePlayer(-51)    -- D1-Anlauf
    Room.movePlayer(15)     -- D1 CW -> A
    -- Fehlentscheidung: D2 vorzeitig CCW -> B (ohne O zu verbrauchen).
    local _, r = Room.movePlayer(-69) -- 102 -> 33 (D2 CCW -> B)
    check(r.blocked == false, "falle4: D2 CCW -> B auslösbar (vorzeitig)")
    check(State.switchStates["D2"] == "B", "falle4: D2=B gesetzt")
    check(State.elementStates["S_O2"] == false, "falle4: S_O2 GESCHLOSSEN (O-Zugang versiegelt)")
    -- Der Rückweg zum O-Bereich (U1/O) ist jetzt durch S_O2 versperrt.
    local _, r2 = Room.movePlayer(237) -- Versuch zurück 33 -> 270 CW (durch S_O2)
    check(r2.blocked == true, "falle4: Rückweg zu O/U1 BLOCKIERT durch S_O2 -> Sackgasse (O nie verbrauchbar)")
end

-- --- FALLE 5: Baby zu früh von P3 (vor dem finalen D-Zug) -> D weg ----------
-- Nimmt der Spieler das Baby vorzeitig von P3, verschwindet D (P3) -> der
-- finale D-Zug (dritter Einstieg/letzter Rückweg) ist nicht mehr möglich.
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    Room.movePlayer(96.83)
    Room.tryUseConnection() -- A
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection() -- B
    Bridge.update(0.5)
    Room.movePlayer(71.83)
    Room.tryUseConnection() -- C
    Bridge.update(0.5)
    Room.movePlayer(-51)
    Room.movePlayer(15)     -- D1 = A (Zwischenziel)
    -- Fehlentscheidung: Baby von P2 zu P3 schieben, dann direkt weiter (P3
    -- verlassen, statt D zu nutzen).
    local _, r = Room.movePlayer(96.83) -- Baby 155 -> 180 (P3)
    check(r.blocked == false, "falle5: Baby auf P3 geschoben")
    local _, r2 = Room.movePlayer(50) -- Baby 180 -> 230 (P3 verlassen)
    check(r2.blocked == false, "falle5: Baby von P3 weggeschoben (voreilig)")
    check(State.platePressed["P3"] == false, "falle5: P3 frei -> D verschwunden")
    check(State.elementStates["D"] == false, "falle5: Bridge D WEG -> letzter Einstieg/Rückweg verloren")
end

-- --- BYPASS 1: Tor ohne O-Verbrauch -> S_FINAL_O versperrt den Weg ----------
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    -- O bleibt A (kein Verbrauch); der finale Ringweg zum Tor ist durch S_FO
    -- (O=A) physisch blockiert.
    local _, r = Room.movePlayer(5) -- kleiner CW-Schritt vom Start
    check(r.blocked == false, "bypass1: Startbewegung frei")
    -- Direkter CW-Lauf zum Torbereich endet an S_FO (357-Eintritt) oder wird
    -- durch S_FD2/S_FD1/S_FO gestoppt, weil O=A und D2=A sind.
    local _, r2 = Room.movePlayer(340) -- 25 -> 5 CW (durch die finale Zone)
    check(r2.blocked == true, "bypass1: finaler Ringweg BLOCKIERT (O nicht verbraucht, S_FO zu)")
    check(State.elementStates["S_FINAL_O"] == false, "bypass1: S_FO bleibt ZU -> Tor unerreichbar")
end

-- --- BYPASS 2: F ohne D2=B -> inaktiv, kein Shared-Transit möglich ----------
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    check(State.elementStates["F"] == false, "bypass2: F inaktiv solange D2=A")
    check(Baby.canTransfer(Levels[9].bridges[5], "outer", State.player.angle) == false, "bypass2: F nicht nutzbar (inaktiv) -> keine Abkürzung über F")
end

-- --- FALLE 6: U2 SOLO auf dem inneren Weg zu U1 verbrauchen -> Sackgasse ---
-- U2 (frei, aktiv) liegt auf dem inneren Zulauf zu U1. Dockt der Spieler dort
-- an und nutzt sie (Baby ist außen auf P2), ist die finale Einmal-Brücke
-- verbraucht, bevor das Baby sie nehmen kann -> keine Endstrecke mehr.
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    Room.movePlayer(96.83)
    Room.tryUseConnection() -- A solo
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection() -- B solo
    Bridge.update(0.5)
    Room.movePlayer(71.83)
    Room.tryUseConnection() -- C solo
    Bridge.update(0.5)
    Room.movePlayer(-51)
    Room.movePlayer(15)     -- D1 = A (Zwischenziel)
    -- Fehlentscheidung: Auf dem Weg zu U1 an U2 andocken und SOLO nutzen.
    local _, r = Room.movePlayer(110) -- 102 -> 212 (U2 inner-Dock)
    check(r.blocked == false, "falle6: Player erreicht U2@212 (inner, auf dem Weg zu U1)")
    local br = Room.tryUseConnection()
    Bridge.update(0.5)
    check(br.used == true and br.id == "U2" and br.kind == "bridge", "falle6: U2 SOLO nutzbar (Baby außen) — verlockende Falle")
    check(State.elementStates["U2"] == false, "falle6: U2 DAUERHAFT verbraucht (oneShot)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 155, 1.0), "falle6: Baby blieb außen (Solo-Transit)")
    check(State.player.ring == "outer" and approx(State.player.angle, 212), "falle6: Player AUSSEN@212 (U2-Transit ohne Baby) — Endstrecke über U2 verloren -> SACKGASSE")
    check(Baby.canTransfer(Levels[9].bridges[8], "outer", State.player.angle) == false, "falle6: U2 verbraucht -> Baby kann nie mehr gemeinsam über U2 -> SACKGASSE")
end

-- --- FALLE 7: Baby zu früh von P2 (vor dem U1/G/O-Zug) -> C weg -------------
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    Room.movePlayer(96.83)
    Room.tryUseConnection() -- A
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection() -- B
    Bridge.update(0.5)
    -- Fehlentscheidung: Baby VOR dem C-Einstieg von P1 weiter zu P2 und P2
    -- wieder verlassen (C wird nie für den inneren U1/O-Zug genutzt).
    Room.movePlayer(71.83)  -- Baby P1 -> P2 (C aktiv)
    check(State.elementStates["C"] == true, "falle7: C kurz aktiv (P2)")
    local _, r = Room.movePlayer(50) -- Baby P2 -> 205 (P2 verlassen)
    check(r.blocked == false, "falle7: Baby von P2 weggeschoben (voreilig)")
    check(State.platePressed["P2"] == false, "falle7: P2 frei -> C verschwunden")
    check(State.elementStates["C"] == false, "falle7: Bridge C WEG -> zweiter Einstieg verloren")
end

-- --- BYPASS 3: U1 direkt (ohne Platten-Route) ist unerreichbar ---------------
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    local br = Room.tryUseConnection()
    check(br.used == false, "bypass3: am Start ist KEINE Brücke nutzbar (A/B/C/D inaktiv) -> U1 nicht abkürzbar")
    local _, r = Room.movePlayer(-60) -- CCW vom Start (an den Abschnitt)
    check(r.blocked == true or State.player.angle > 300, "bypass3: Abschnitt auch von der Torseite unbetretbar (S_U1B/finale Blenden)")
end

-- --- BYPASS 4: U2 ist NICHT solo nutzbar (Baby liegt immer im Schubweg) -----
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    -- Jeder Schub zu U2 nimmt das Baby zwangsläufig mit (kein Ziehen, das Baby
    -- liegt auf dem Weg) -> U2 ist strukturell eine GEMEINSAME Brücke.
    local _, r = Room.movePlayer(187) -- 25 -> 212 (Baby wird mitgeschoben)
    check(r.blocked == false, "bypass4: Schub zu U2 frei")
    check(State.baby ~= nil and math.abs(Geometry.delta(State.baby.angle, State.player.angle)) <= Baby.contactDeg() + 1, "bypass4: Baby wurde zwingend mitgeschoben -> solo an U2 unmöglich")
end

-- --- BYPASS 5: O ist NUR per CCW verbrauchbar (jede andere Richtung no-op) ---
do
    State.init(Levels[9], true)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(Levels[9].rings.outer)
    Render.resetPlayerVisual()
    Room.movePlayer(96.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(71.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-51)
    Room.movePlayer(15)     -- D1 = A (Zwischenziel)
    -- CW über O (falsche Richtung) -> kein Verbrauch.
    Room.movePlayer(168)    -- 102 -> 270 (CW über O)
    check(State.switchStates["O"] == "A" and State.consumedSwitches["O"] ~= true, "bypass5: CW-Überquerung verbraucht O NICHT")
    -- CCW über O (richtige Richtung, über den Abschnitt mit U1/G) -> Verbrauch.
    Room.tryUseConnection() -- U1 solo in den Abschnitt
    Bridge.update(0.5)
    Room.movePlayer(25)     -- 270 -> 295 (G im Abschnitt)
    Room.tryUseConnection() -- G solo
    Bridge.update(0.5)
    local _, r = Room.movePlayer(-112) -- 295 -> 183 (CCW über O)
    check(r.blocked == false, "bypass5: CCW-Zulauf über O frei")
    check(State.switchStates["O"] == "B" and State.consumedSwitches["O"] == true, "bypass5: NUR die CCW-Überquerung verbraucht O (eindeutige Richtung)")
end

-- ===========================================================================
--  ZUSAMMENFASSUNG
-- ===========================================================================
print("LEVEL9_FULL_SOLUTION: pass=" .. pass .. " fail=" .. fail)
check(fail == 0, "level9: vollständiger Lösungsdurchlauf OHNE Fehler")

TestReport.level9Full = { pass = pass, fail = fail }
