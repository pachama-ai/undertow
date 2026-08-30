-- Tests für Raum 4 „Einmalentscheidung“ (EXAKT 2 aktive Ringbahnen +
-- EINMALSCHALTER; KEINE weitere neue Mechanik):
--   KEINE künstliche Startposition — ENTRY = Level-3-Ausgang (Player äußerer
--   Ring @135, Baby @145: der Kernbrücken-Handoff landet das Baby einen Bogen
--   VOR dem Player -> PUSH_DIRECTION = CW).
--   EXAKT ZWEI aktive Ringe: outer (4), inner (3) + Mittelpunkt — KEIN
--   dritter Ring (ACTIVE RINGS = 2).
--   ÄUSSERER RING: P (Platte @250), S1 (@120, von P, deckt Bridge A), Bridge
--     A (outer<->inner@120), Bridge B (inner<->outer@340).
--   INNERER RING: D (Doppelschalter @250; onA=DA, onB=DB, state B), DA (@278,
--     Zustand A), O (EINMALSCHALTER @300, oneShot, onA=S2), DB (@20, Zustand
--     B), S2 (@340, deckt Bridge B@340), Tor T (@276, im Bogen (243°,340°)).
-- ABLAUF: Baby auf P -> S1 öffnet -> Player CCW zu Bridge A -> SOLO auf den
-- inneren Ring@120. D=B Start: die RICHTIGE Richtung (CW) überquert D zu
-- Zustand A (DA öffnet), erreicht O von der richtigen Seite und überquert ihn
-- korrekt (O verbraucht, S2 öffnet dauerhaft) -> durch S2 zu Bridge B ->
-- SOLO auf outer@340 (hinter dem Baby) -> Baby CCW holen -> Bridge B SHARED
-- -> inner@340/330 -> CCW durch den offenen S2-Bereich zum Tor T@276 (der
-- finale Weg kreuzt D NICHT erneut, damit D=A/DA offen bleibt) ->
-- gemeinsamer Center-Transit -> EXIT. Die falsche Richtung (CCW) prallt an
-- S2 ab (Bridge B versperrt) — mit Undo korrigierbar. Die falsche
-- O-Richtung (CCW) lässt S2 geschlossen.
-- Am Ende wird das Ergebnis in TestReport.room4 gesammelt.

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
    return math.abs(a - b) <= (tolerance or 0.05)
end

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(room.rings.outer)
    Render.resetPlayerVisual()
end

-- --- Raum 4 Daten (ACTIVE RINGS = 2) ---------------------------------------
do
    local r4 = Levels[4]
    check(r4.name == "Einmalentscheidung", "daten: Name 'Einmalentscheidung'")
    check(r4.rings.outer == 4 and r4.rings.inner == 3 and r4.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (4/3) — kein dritter Ring")
    check(r4.start.ring == "outer" and approx(r4.start.angle, 135),
        "daten: ENTRY = Level-3-Ausgang (Player outer@135)")
    check(r4.baby ~= nil and r4.baby.start.ring == "outer" and approx(r4.baby.start.angle, 145),
        "daten: Baby outer@145 (CW vor dem Player)")
    check(#r4.switches == 2, "daten: genau 2 Schalter (D + Einmalschalter O)")
    local d, o
    for _, sw in ipairs(r4.switches) do
        if sw.id == "D" then d = sw end
        if sw.id == "O" then o = sw end
    end
    check(d ~= nil and d.ring == "inner" and approx(d.angle, 250) and d.state == "B",
        "daten: D inner@250 (B) — bewacht beide Wege zu O")
    check(d.onA == "DA" and d.onB == "DB", "daten: D steuert DA (A) und DB (B)")
    check(o ~= nil and o.ring == "inner" and approx(o.angle, 300) and o.state == "B"
        and o.oneShot == true, "daten: O Einmalschalter inner@300 (B, oneShot)")
    check(o.onA == "S2" and type(o.onB) == "table" and #o.onB == 0,
        "daten: O öffnet S2 in Zustand A (B: S2 zu)")
    check(#r4.shutters == 4, "daten: genau 4 Blenden")
    local byId = {}
    for _, sh in ipairs(r4.shutters) do byId[sh.id] = sh end
    check(byId["S1"] ~= nil and byId["S1"].ring == "outer" and approx(byId["S1"].angle, 120),
        "daten: S1 outer@120 (von P gesteuert, deckt Bridge A)")
    check(byId["DA"] ~= nil and byId["DA"].ring == "inner" and approx(byId["DA"].angle, 278),
        "daten: DA inner@278 (von D in Zustand A, richtiger Weg zu O)")
    check(byId["DB"] ~= nil and byId["DB"].ring == "inner" and approx(byId["DB"].angle, 20),
        "daten: DB inner@20 (von D in Zustand B, falsche Richtung)")
    check(byId["S2"] ~= nil and byId["S2"].ring == "inner" and approx(byId["S2"].angle, 340),
        "daten: S2 inner@340 (von O in Zustand A, deckt Bridge B)")
    check(#r4.plates == 1, "daten: genau 1 Druckplatte")
    check(r4.plates[1].id == "P" and r4.plates[1].ring == "outer"
        and approx(r4.plates[1].angle, 250) and r4.plates[1].on == "S1",
        "daten: P outer@250 steuert S1")
    check(#r4.bridges == 2, "daten: genau 2 Brücken (A + B)")
    local bA, bB
    for _, b in ipairs(r4.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "B" then bB = b end
    end
    check(bA ~= nil and bA.free and approx(bA.angle, 120) and bA.rings == nil,
        "daten: Bridge A@120 (outer <-> inner, 2-Ring-Standard)")
    check(bB ~= nil and bB.free and approx(bB.angle, 340) and bB.rings == nil,
        "daten: Bridge B@340 (inner <-> outer, Rückweg)")
    check(r4.gate.id == "T" and r4.gate.free == true and r4.gate.ring == "inner"
        and approx(r4.gate.angle, 276), "daten: Tor T inner@276 (finaler Weg)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[4])
    check(State.platePressed["P"] == false, "start: P frei")
    check(State.elementStates["S1"] == false, "start: S1 geschlossen (P frei)")
    check(State.switchStates["D"] == "B", "start: D = B")
    check(State.elementStates["DA"] == false, "start: DA geschlossen (D=B)")
    check(State.elementStates["DB"] == true, "start: DB offen (D=B)")
    check(State.switchStates["O"] == "B", "start: O = B")
    check(State.elementStates["S2"] == false, "start: S2 geschlossen (O=B)")
    check(State.elementStates["A"] == true and State.elementStates["B"] == true
        and State.elementStates["T"] == true, "start: A+B+T frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 135), "start: Player outer@135")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 145),
        "start: Baby outer@145")
end

-- --- Druckplatte: Baby auf P -> S1 offen -----------------------------------
do
    setup(Levels[4])
    local _, r = Room.movePlayer(105) -- 135 -> 240, Baby 145 -> ~248 (P@250)
    check(r.blocked == false, "platte: Schub läuft")
    check(State.platePressed["P"] == true, "platte: Baby auf P -> gedrückt")
    check(State.elementStates["S1"] == true, "platte: S1 offen (P aktiv)")
    -- Player entfernt sich: Baby bleibt auf P -> P weiter aktiv.
    State.player.angle = 100
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.platePressed["P"] == true, "platte: Baby bleibt auf P -> P aktiv")
    check(State.elementStates["S1"] == true, "platte: S1 bleibt offen (Baby hält)")
    -- Baby verlässt P -> P frei -> S1 schließt.
    State.baby.angle = 200
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.platePressed["P"] == false, "platte: Baby weg -> P frei")
    check(State.elementStates["S1"] == false, "platte: S1 wieder geschlossen")
end

-- --- S1 blockiert Zugang zu Bridge A, bis das Baby auf P steht -------------
do
    setup(Levels[4])
    -- Ohne Baby auf P: S1 (Bogen [107,133]) blockiert den CCW-Weg zu Bridge A.
    local _, r = Room.movePlayer(-10) -- 135 CCW, stoppt an S1@133
    check(r.blocked == true, "s1: CCW zu Bridge A blockiert (S1 zu)")
    check(approx(State.player.angle, 133, 1.5), "s1: Player stoppt an S1-Kante (133)")
    local res1 = Room.tryUseConnection()
    check(res1.used == false, "s1: Bridge A nicht nutzbar (CCW)")
    -- Ohne Baby auf P: CW schiebt das Baby über P hinweg (kein Parken); die
    -- Platte wird nur transient berührt, Bridge A bleibt unerreichbar.
    setup(Levels[4])
    local _, rcw = Room.movePlayer(250)
    check(State.platePressed["P"] == false, "s1: Baby nicht geparkt (CW-Schub)")
    local res2 = Room.tryUseConnection()
    check(res2.used == false, "s1: Bridge A nicht nutzbar (CW)")
    -- Mit Baby auf P: S1 offen, Player erreicht Bridge A und geht SOLO.
    setup(Levels[4])
    Room.movePlayer(105) -- Baby auf P@250, S1 offen
    local _, r2 = Room.movePlayer(-120) -- 240 -> 120 (Bridge A, durch S1)
    check(r2.blocked == false, "s1: Player passiert S1")
    check(approx(State.player.angle, 120, 1), "s1: Player an Bridge A")
    check(State.platePressed["P"] == true, "s1: Baby bleibt auf P")
    local resA = Room.tryUseConnection()
    check(resA.used == true and resA.kind == "bridge", "s1: Player geht ALLEIN über Bridge A")
    Bridge.update(0.5)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner" and State.baby.ring == "outer",
        "s1: Player auf Ring B (inner), Baby auf P (getrennt)")
end

-- --- FALSCHE Richtung (CCW, D=B): prallt an S2 ab --------------------------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 120
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    check(State.switchStates["D"] == "B" and State.elementStates["DA"] == false
        and State.elementStates["DB"] == true,
        "falsch-start: D=B, DA zu, DB offen")
    -- CCW (falsche Richtung): 119 -> 0 -> 359 -> ... -> S2@353 (geschlossen).
    local _, r = Room.movePlayer(-200)
    check(r.blocked == true, "falsch: CCW prallt an S2 ab")
    check(approx(State.player.angle, 353, 1.5), "falsch: Player stoppt an S2 (353)")
    check(State.switchStates["D"] == "B", "falsch: D unverändert (nicht überquert)")
    check(State.switchStates["O"] == "B" and State.consumedSwitches["O"] == nil,
        "falsch: O unberührt")
    check(State.elementStates["S2"] == false, "falsch: S2 geschlossen")
    local res = Room.tryUseConnection()
    check(res.used == false, "falsch: Bridge B nicht nutzbar (Sackgasse)")
end

-- --- RICHTIGE Richtung (CW): D -> A, O -> A (verbraucht), S2 offen ---------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 120
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    -- CW: D CW überqueren -> Zustand A (DA öffnet), O CW überqueren -> A
    -- (verbraucht, S2 öffnet dauerhaft), durch S2 zu Bridge B@340.
    local _, r = Room.movePlayer(220) -- 120 -> 340
    check(r.blocked == false, "richtig: CW-Route läuft")
    check(State.switchStates["D"] == "A", "richtig: D=A (CW-Richtung)")
    check(State.elementStates["DA"] == true, "richtig: DA offen (Zustand A)")
    check(State.elementStates["DB"] == false, "richtig: DB geschlossen (Zustand A)")
    check(State.switchStates["O"] == "A", "richtig: O=A (richtige Richtung)")
    check(State.consumedSwitches["O"] == true, "richtig: O verbraucht (oneShot)")
    check(State.elementStates["S2"] == true, "richtig: S2 offen (dauerhaft)")
    check(approx(State.player.angle, 340, 0.5), "richtig: Player an Bridge B (inner)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "richtig: SOLO über Bridge B")
    Bridge.update(0.5)
    Room.syncPhysicalShutters()
    check(State.player.ring == "outer" and approx(State.player.angle, 340, 0.5),
        "richtig: Player outer@340 (ANDERE Babyseite)")
end

-- --- FALSCHE O-Richtung (CCW): S2 bleibt geschlossen -----------------------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 308 -- O's falsche Seite (CW von O@300)
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    check(State.elementStates["S2"] == false, "falsch-o-start: S2 geschlossen (O=B)")
    -- CCW über O (falsche Richtung): O bleibt B, NICHT verbraucht, S2 zu.
    -- Direkt dahinter prallt der Player an der geschlossenen DA@288 ab
    -- (D=B) — die falsche Richtung ist eine Sackgasse.
    local _, r = Room.movePlayer(-20) -- 308 -> 291, überquert O CCW
    check(r.blocked == true, "falsch-o: CCW über O läuft (O bleibt B)")
    check(approx(State.player.angle, 291, 1.5), "falsch-o: Player stoppt an DA (291)")
    check(State.switchStates["O"] == "B", "falsch-o: O bleibt B (falsche Richtung)")
    check(State.consumedSwitches["O"] == nil, "falsch-o: O nicht verbraucht (kein Umschalten)")
    check(State.elementStates["S2"] == false, "falsch-o: S2 bleibt geschlossen")
end

-- --- RICHTIGE O-Richtung (CW): S2 öffnet permanent -------------------------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 150 -- O's richtige Seite (CCW von O@300)
    State.baby.ring = "outer"
    State.baby.angle = 183
    State.setSwitch("D", "A") -- DA offen (Zustand A)
    Room.syncPhysicalShutters()
    -- Vorlauf bis an den O-Eintritt (293) — der Eintritt armiert die
    -- Traversierung, löst aber noch NICHT aus.
    local _, r1 = Room.movePlayer(143) -- 150 -> 293 (O-Eintritt CW)
    check(r1.blocked == false, "oneshot: Vorlauf läuft")
    check(approx(State.player.angle, 293, 0.5), "oneshot: Player an O-Eintritt (293)")
    check(State.switchStates["O"] == "B" and State.consumedSwitches["O"] == nil,
        "oneshot: Eintritt löst NICHT aus")
    -- Halbe Überquerung: Player stoppt im O-Bogen -> KEIN Auslösen.
    local _, r1b = Room.movePlayer(2) -- 293 -> 295 (im O-Bogen [293,307])
    check(r1b.blocked == false, "oneshot: halbe Überquerung läuft")
    check(State.switchStates["O"] == "B" and State.consumedSwitches["O"] == nil,
        "oneshot: kein Auslösen bei halber Überquerung")
    check(State.elementStates["S2"] == false, "oneshot: S2 weiterhin zu")
    -- Vollständige CW-Überquerung: Austritt bei 307 -> O=A (verbraucht),
    -- S2 öffnet dauerhaft.
    local _, r2 = Room.movePlayer(15) -- 295 -> 310 (über Austrittskante 307)
    check(r2.blocked == false, "oneshot: vollständige Überquerung läuft")
    check(State.switchStates["O"] == "A", "oneshot: O=A (richtige Richtung)")
    check(State.consumedSwitches["O"] == true, "oneshot: O verbraucht (oneShot)")
    check(State.elementStates["S2"] == true, "oneshot: S2 offen")
    -- O bleibt verbraucht: erneute Überquerung (CCW) ändert nichts.
    local _, r3 = Room.movePlayer(-20) -- 310 -> 290, überquert O zurück
    check(r3.blocked == false, "oneshot: Rücküberquerung läuft")
    check(State.switchStates["O"] == "A", "oneshot: O bleibt A (verbraucht/fest)")
    check(State.elementStates["S2"] == true, "oneshot: S2 bleibt offen (permanent)")
end

-- --- NO BYPASS: Bridge B nur mit O richtig (S2 deckt das Dock) -------------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters() -- O=B -> S2 zu
    local _, r = Room.movePlayer(60)
    check(r.blocked == true, "anti-b: CW zu Bridge B blockiert (S2 zu)")
    check(State.player.angle < 340, "anti-b: Player erreicht Bridge B NICHT")
    local res = Room.tryUseConnection()
    check(res.used == false, "anti-b: Bridge B nicht nutzbar (O=B)")
    -- Nach O=A: S2 offen, Bridge B erreichbar.
    State.setSwitch("O", "A")
    State.deriveElements()
    Room.syncPhysicalShutters()
    State.player.angle = 300
    local _, r2 = Room.movePlayer(40) -- 300 -> 340 (durch den offenen S2-Bereich)
    check(r2.blocked == false, "anti-b: CW läuft (S2 offen)")
    check(approx(State.player.angle, 340, 0.5), "anti-b: Player an Bridge B (340)")
    local bB
    for _, b in ipairs(Levels[4].bridges) do
        if b.id == "B" then bB = b end
    end
    check(bB ~= nil and Bridge.isUsable(bB, State.player.angle) == true,
        "anti-b: Bridge B nutzbar (O=A)")
end

-- --- BABY RECOVERY (Push-only) + gemeinsamer Rücktransit -------------------
do
    setup(Levels[4])
    -- Zustand nach Bridge B: Player outer@340, Baby geparkt auf P (~249).
    -- Player steht CW vom Baby -> schiebt es CCW (durch den offenen S1-Bogen
    -- dieser Frame-Phase) zurück zur Bridge B@340.
    State.player.ring = "outer"
    State.player.angle = 340
    State.baby.ring = "outer"
    State.baby.angle = 249
    State.setSwitch("O", "A") -- O verbraucht -> S2 offen (B@340 frei)
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.player.angle > State.baby.angle, "recovery: Player CW vom Baby (340 > 248)")
    check(State.platePressed["P"] == true, "recovery: Baby hält P")
    local _, r = Room.movePlayer(-352) -- Player 340 -> 348, Baby ~249 -> ~340
    check(r.blocked == false, "recovery: CCW-Schub läuft (kein Ziehen)")
    check(approx(State.player.angle, 348, 1), "recovery: Player bei ~348")
    check(approx(State.baby.angle, 340, 2), "recovery: Baby an Bridge B (Wrap um 0)")
    check(State.platePressed["P"] == false, "recovery: P frei (Baby herunter)")
    check(State.elementStates["S1"] == false, "recovery: S1 geschlossen (egal)")
    -- Gemeinsamer Transit über Bridge B zurück auf den inneren Ring.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "recovery: gemeinsamer Transit über Bridge B")
    Bridge.update(0.5)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "recovery: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 330, 0.5), "recovery: Baby inner@330 (vor dem Player)")
end

-- --- Deterministische Baby-Landeseite bei B (babyLandDir=-1) --------------
-- Regressionssicherung: Das Baby kann an B@340 auch aus der ANDEREN Richtung
-- (CW, durch 0°) in den Dock-Bereich geschoben werden. Ohne babyLandDir würde
-- die letzte Schieberichtung (+1) das Baby bei inner@350 (rechts/CW vom
-- Player@340) landen lassen — der finale CCW-Schub zum Tor griffe nicht.
-- babyLandDir=-1 erzwingt die Landung auf der CCW-Seite (inner@330).
do
    setup(Levels[4])
    State.player.ring = "outer"
    State.player.angle = 340
    State.baby.ring = "outer"
    State.baby.angle = 249
    State.setSwitch("D", "A")
    State.setSwitch("O", "A")
    State.deriveElements()
    Room.syncPhysicalShutters()
    local _, r = Room.movePlayer(352) -- Player 340 -> 332, Baby 248 -> ~340 (CW durch 0)
    check(r.blocked == false, "land-cw: CW-Schub zu B läuft")
    check(approx(State.player.angle, 332, 1), "land-cw: Player an B (332)")
    check(approx(State.baby.angle, 340, 1), "land-cw: Baby an B (340, CW-Push)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "B",
        "land-cw: gemeinsamer Transit über B")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "land-cw: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 330, 0.5),
        "land-cw: Baby inner@330 (deterministisch links/CCW, NICHT 350)")
end

-- --- Finale: durch den offenen S2-Bereich zum Tor, Center-Transit ---------
do
    setup(Levels[4])
    -- Zustand nach der gemeinsamen Rückkehr (Soll-Lösung): Player inner@340,
    -- Baby inner@330, D=A (richtige Richtung), O=A verbraucht (S2 dauerhaft
    -- offen).
    State.player.ring = "inner"
    State.player.angle = 340
    State.baby.ring = "inner"
    State.baby.angle = 330
    State.setBabyPushDirection(-1)
    State.setSwitch("D", "A") -- richtige Richtung (DA offen, DB zu)
    State.setSwitch("O", "A") -- O verbraucht, S2 dauerhaft offen
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.elementStates["S2"] == true, "final-start: S2 dauerhaft offen (O=A)")
    check(State.elementStates["DA"] == true, "final-start: DA offen (D=A)")
    -- Player schiebt Baby CCW durch S2 und O (verbraucht -> kein Retrigger)
    -- zum Tor T@276. Der finale Weg kreuzt D NICHT (Tor im Bogen (243°,340°))
    -- — D bleibt A, DA bleibt offen, kein Push-Block.
    local _, r = Room.movePlayer(-64) -- Player 340 -> 276, Baby 330 -> 268
    check(r.blocked == false, "final: Schub zum Tor läuft")
    check(State.switchStates["O"] == "A", "final: O bleibt A (verbraucht, kein Retrigger)")
    check(State.switchStates["D"] == "A", "final: D bleibt A (nicht erneut überquert)")
    check(State.elementStates["S2"] == true, "final: S2 bleibt offen")
    check(approx(State.player.angle, 276, 0.5), "final: Player am Tor (276)")
    check(approx(State.baby.angle, 268, 2), "final: Baby am Tor")
    check(Gate.isUsable(Levels[4].gate, "inner", State.player.angle) == true,
        "final: Tor nutzbar (Player UND Baby)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "final: Kernbrücken-Transit (Abschluss nach Transit)")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "final: gemeinsamer Center-Transit abgeschlossen (Level 4 fertig)")
    check(State.player.ring == "inner" and State.baby.ring == "inner"
        and approx(State.player.angle, 276, 0.5),
        "final: Player am Gate-Ring @276 (Ziel = Mittelpunkt)")
    -- Baby-Winkel-Handoff: das Baby landet einen Bogen VOR dem Player auf der
    -- Brückenachse (eigener Winkel, nie == Player).
    check(approx(State.baby.angle, 286, 0.5),
        "final: Baby behält EIGENEN Winkel @286 (VOR dem Player)")
end

-- --- NO BYPASS: Gate verlangt das Baby (nicht solo abschließbar) -----------
do
    setup(Levels[4])
    State.player.ring = "inner"
    State.player.angle = 276
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    local res = Room.tryUseConnection()
    check(res.used == false, "gate-solo: Tor ohne Baby NICHT nutzbar (kein Bypass)")
end

TestReport.room4 = { pass = pass, fail = fail }
