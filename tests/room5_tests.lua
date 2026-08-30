-- Tests für Raum 5 „Punkt ohne Wiederkehr“ (EXAKT 2 aktive Ringbahnen 3/2 +
-- Mittelpunkt, KEIN dritter Ring; EINMAL-BRÜCKE U als Point of No Return).
--   KEINE künstliche Startposition — ENTRY = Level-4-Ausgang (Player äußerer
--   Ring @276, Baby @286: das Baby steht einen Bogen CW vor dem Player,
--   PUSH_DIRECTION = CW).
--   ÄUSSERER RING: P (Druckplatte @330), S1 (@210, von P, öffnet den Zugang
--     zu D/O), D (Doppelschalter @125; Start A, ANDERSHERUM: CCW -> B öffnet
--     DA, CW -> A schließt sie), DA (@95, in B offen), DB (@35, in A offen),
--     O (EINMALSCHALTER @65; CCW -> B verbraucht, öffnet S2 + Tor T),
--     EINMAL-BRÜCKE U (@342, CW vom Baby-Parkplatz erreichbar).
--     Kette gleichmäßig: D@125 --30°--> DA@95 --30°--> O@65 --30°--> DB@35.
--   INNERER RING: S2 (@60, von O dauerhaft geöffnet — gegenüberliegende
--     Seite), Tor T (@180, von O gesteuert — öffnet erst mit O; harter
--     Bypass-Schutz).
-- ABLAUF (Soll-Lösung): Baby CW auf P -> S1 öffnet -> Player CCW durch S1:
-- die NATÜRLICHE CCW-Überquerung von D öffnet DA (D -> B, andersherum) -> DA
-- passieren, O von der richtigen Seite (CCW) überqueren (O verbraucht, S2 +
-- Tor T dauerhaft offen) -> Rückkehr CW: das Baby wird dabei CW zu U@342
-- geschoben (P frei, S1 schließt — egal, S2/T sind vorbereitet) -> U
-- GEMEINSAM (U verschwindet erst nach vollständigem Transit) -> beide
-- inner@342/352 -> vorbereiteter Weg CW durch S2@60 (gegenüberliegende
-- Seite, durch 0°) zum Tor T@180 -> gemeinsamer Center-Transit -> EXIT.
-- Am Ende wird das Ergebnis in TestReport.room5 gesammelt.

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

-- --- Raum 5 Daten ----------------------------------------------------------
do
    local r5 = Levels[5]
    check(r5.name == "Punkt ohne Wiederkehr", "daten: Name 'Punkt ohne Wiederkehr'")
    check(r5.rings.outer == 3 and r5.rings.inner == 2 and r5.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (3/2) — kein dritter Ring")
    check(r5.start.ring == "outer" and approx(r5.start.angle, 276),
        "daten: ENTRY = Level-4-Ausgang (Player outer@276)")
    check(r5.baby ~= nil and r5.baby.start.ring == "outer" and approx(r5.baby.start.angle, 286),
        "daten: Baby outer@286 (CW vor dem Player)")
    check(#r5.switches == 2, "daten: genau 2 Schalter (D + Einmalschalter O)")
    local d, o
    for _, sw in ipairs(r5.switches) do
        if sw.id == "D" then d = sw end
        if sw.id == "O" then o = sw end
    end
    check(d ~= nil and d.ring == "outer" and approx(d.angle, 125) and d.state == "A",
        "daten: D outer@125 (A) — ANDERSHERUM: CCW -> B öffnet DA")
    check(d.onA == "DB" and d.onB == "DA", "daten: D steuert DB (A) und DA (B)")
    check(o ~= nil and o.ring == "outer" and approx(o.angle, 65) and o.state == "A"
        and o.oneShot == true, "daten: O Einmalschalter outer@65 (A, oneShot)")
    check(type(o.onA) == "table" and #o.onA == 0
        and type(o.onB) == "table" and #o.onB == 2
        and o.onB[1] == "S2" and o.onB[2] == "T",
        "daten: O öffnet S2 (inner) UND Tor T in Zustand B — dauerhaft vorbereitet")
    check(#r5.shutters == 4, "daten: genau 4 Blenden")
    local byId = {}
    for _, sh in ipairs(r5.shutters) do byId[sh.id] = sh end
    check(byId["S1"] ~= nil and byId["S1"].ring == "outer" and approx(byId["S1"].angle, 210),
        "daten: S1 outer@210 (von P, Zugang zu D/O)")
    check(byId["DA"] ~= nil and byId["DA"].ring == "outer" and approx(byId["DA"].angle, 95),
        "daten: DA outer@95 (von D in Zustand B, richtiger Anlauf zu O)")
    check(byId["DB"] ~= nil and byId["DB"].ring == "outer" and approx(byId["DB"].angle, 35),
        "daten: DB outer@35 (von D in Zustand A, andere Seite)")
    check(byId["S2"] ~= nil and byId["S2"].ring == "inner" and approx(byId["S2"].angle, 60),
        "daten: S2 inner@60 (von O in Zustand B, vorbereiteter Weg — gegenüberliegende Seite)")
    check(#r5.plates == 1, "daten: genau 1 Druckplatte")
    check(r5.plates[1].id == "P" and r5.plates[1].ring == "outer"
        and approx(r5.plates[1].angle, 330) and r5.plates[1].on == "S1",
        "daten: P outer@330 steuert S1")
    check(#r5.bridges == 1, "daten: genau 1 Brücke (EINMAL-BRÜCKE U)")
    local bU
    for _, b in ipairs(r5.bridges) do
        if b.id == "U" then bU = b end
    end
    check(bU ~= nil and bU.free and bU.oneShot == true and approx(bU.angle, 342),
        "daten: EINMAL-BRÜCKE U@342 (frei, oneShot, einzige Verbindung)")
    check(r5.gate.id == "T" and r5.gate.free == false and r5.gate.ring == "inner"
        and approx(r5.gate.angle, 180),
        "daten: Tor T inner@180 (Center-Bridge, von O gesteuert — Bypass-Schutz)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[5])
    check(State.platePressed["P"] == false, "start: P frei")
    check(State.elementStates["S1"] == false, "start: S1 geschlossen (P frei)")
    check(State.switchStates["D"] == "A", "start: D = A")
    check(State.elementStates["DA"] == false, "start: DA geschlossen (D=A)")
    check(State.elementStates["DB"] == true, "start: DB offen (D=A)")
    check(State.switchStates["O"] == "A", "start: O = A")
    check(State.elementStates["S2"] == false, "start: S2 geschlossen (O=A)")
    check(State.elementStates["U"] == true, "start: U frei aktiv")
    check(State.elementStates["T"] == false,
        "start: Tor T geschlossen (O=A, öffnet erst mit O)")
    check(State.player.ring == "outer" and approx(State.player.angle, 276), "start: Player outer@276")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 286),
        "start: Baby outer@286")
end

-- --- EINMAL-BRÜCKE: früh (falsche Reihenfolge) -----------------------------
do
    setup(Levels[5])
    -- U@342 liegt CW vom Baby@286: der Player erreicht U nur, indem er das
    -- Baby dorthin SCHIEBT (das Baby kommt immer mit -> gemeinsamer Transit).
    local _, r = Room.movePlayer(58) -- Player 276 -> 334, Baby 286 -> 342 (U-Dock)
    check(r.blocked == false, "frueh: CW-Schub zu U läuft")
    check(approx(State.player.angle, 334, 0.5), "frueh: Player an U (334)")
    check(approx(State.baby.angle, 342, 1.0), "frueh: Baby an U (342)")
    -- U überqueren (gemeinsam, weil das Baby am Dock steht).
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "frueh: Player benutzt U (gemeinsam)")
    check(State.consumedBridges["U"] == nil, "frueh: vor Abschluss noch nicht verbraucht")
    check(State.elementStates["U"] == true, "frueh: U bleibt während des Transits aktiv")
    Bridge.update(0.5)
    check(State.consumedBridges["U"] == true, "frueh: U erst NACH der Überquerung verbraucht")
    check(State.elementStates["U"] == false, "frueh: U verschwindet (elementState false)")
    check(State.player.ring == "inner" and approx(State.player.angle, 342, 0.5),
        "frueh: Player inner@342")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 352, 0.5),
        "frueh: Baby inner@352")
    check(State.elementStates["S2"] == false, "frueh: S2 geschlossen (O nicht vorbereitet)")
    check(State.elementStates["T"] == false,
        "frueh: Tor T geschlossen (O nicht vorbereitet — harter Bypass-Schutz)")
    -- Falsche Reihenfolge: auf dem inneren Ring ist der CW-Sollweg durch S2
    -- (geschlossen, Bogen [47,73]) versperrt; selbst der CCW-Weg endet hinter
    -- dem geschlossenen Tor an S2. U ist weg -> Sackgasse.
    local _, r2 = Room.movePlayer(-600)
    check(r2.blocked == true, "frueh: CCW prallt an der geschlossenen S2 ab")
    check(State.player.angle < 120, "frueh: Player erreicht das Tor (180) nicht")
    -- UNDO: die frühe Nutzung ist rückgängig machbar.
    check(Undo.count() >= 1, "frueh: Einmal-Brücken-Transit erzeugt Undo-Snapshot")
    local restored = Undo.undo()
    check(restored == true, "frueh: Undo stellt den Zustand wieder her")
    check(State.player.ring == "outer" and approx(State.player.angle, 334, 0.5),
        "frueh: Player zurück auf outer@334")
    check(State.consumedBridges["U"] == nil, "frueh: U wieder aktiv (nicht verbraucht)")
    check(State.elementStates["U"] == true, "frueh: elementState U wieder true")
end

-- --- Druckplatte: Baby auf P -> S1 offen -----------------------------------
do
    setup(Levels[5])
    local _, r = Room.movePlayer(44) -- 276 -> 320, Baby 286 -> ~328 (P@330)
    check(r.blocked == false, "platte: Schub läuft")
    check(State.platePressed["P"] == true, "platte: Baby auf P -> gedrückt")
    check(State.elementStates["S1"] == true, "platte: S1 offen (P aktiv)")
    check(approx(State.player.angle, 320, 0.5), "platte: Player bei ~320")
    check(approx(State.baby.angle, 328, 1.5), "platte: Baby geparkt auf P (~328)")
    -- Player entfernt sich: Baby bleibt auf P -> P weiter aktiv.
    State.player.angle = 300
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

-- --- P zwingend: ohne Baby auf P kein Zugang zu D/O ------------------------
do
    setup(Levels[5])
    -- Ohne Baby auf P: S1 (Bogen [197,223]) blockiert den CCW-Weg zu D/O.
    local _, r = Room.movePlayer(-53) -- 276 CCW, stoppt an S1@223
    check(r.blocked == true, "p-zwingend: CCW zu D/O blockiert (S1 zu)")
    check(approx(State.player.angle, 223, 1.5), "p-zwingend: Player stoppt an S1-Kante (223)")
    local res = Room.tryUseConnection()
    check(res.used == false, "p-zwingend: kein Zugang zu D/O")
end

-- --- D natürlich (CCW): öffnet DA (andersherum) -----------------------------
do
    setup(Levels[5])
    Room.movePlayer(44) -- Baby auf P, S1 offen
    -- CCW durch S1, D CCW voll überqueren (bis Austrittskante 118) -> D=B,
    -- DA öffnet (andersherum: die natürliche Richtung ist die richtige).
    local _, r = Room.movePlayer(-202) -- 320 -> 118
    check(r.blocked == false, "d-natuerlich: CCW-Überquerung läuft")
    check(State.switchStates["D"] == "B", "d-natuerlich: D=B (natürliche Richtung)")
    check(State.elementStates["DA"] == true, "d-natuerlich: DA offen (D=B)")
    check(State.elementStates["DB"] == false, "d-natuerlich: DB geschlossen (D=B)")
    check(approx(State.player.angle, 118, 0.5), "d-natuerlich: Player bei ~118")
end

-- --- D verkehrt (CW): schließt DA wieder (andersherum) ---------------------
do
    setup(Levels[5])
    Room.movePlayer(44) -- Baby auf P, S1 offen
    Room.movePlayer(-202) -- 320 -> 118 (D CCW -> B, DA offen)
    check(State.switchStates["D"] == "B", "d-verkehrt-start: D=B (DA offen)")
    -- 1° CCW in die Lücke (D-CW-Eintritt@118 wird wieder echtes Ereignis),
    -- dann D CW voll überqueren -> A -> DA schließt, DB öffnet.
    Room.movePlayer(-1) -- 118 -> 117
    local _, r = Room.movePlayer(15) -- 117 -> 132 (D CW überqueren -> A)
    check(r.blocked == false, "d-verkehrt: CW-Überquerung läuft")
    check(State.switchStates["D"] == "A", "d-verkehrt: D=A (Gegenrichtung)")
    check(State.elementStates["DA"] == false, "d-verkehrt: DA wieder zu (D=A)")
    check(State.elementStates["DB"] == true, "d-verkehrt: DB offen (D=A)")
    check(approx(State.player.angle, 132, 0.5), "d-verkehrt: Player bei ~132")
end

-- --- O falsche Richtung (CW): kein Auslösen --------------------------------
do
    setup(Levels[5])
    State.player.ring = "outer"
    State.player.angle = 40 -- CW-Seite von O@65 (unterhalb, im offenen DB-Bogen)
    State.baby.ring = "outer"
    State.baby.angle = 200 -- nicht auf P (irrelevant)
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.elementStates["S2"] == false, "falsch-o-start: S2 geschlossen (O=A)")
    -- CW über O@65 (falsche Richtung): O bleibt A, NICHT verbraucht, S2 zu.
    -- Danach prallt der Player an der geschlossenen DA@82 ab (D=A, Start).
    local _, r = Room.movePlayer(42) -- 40 -> 82 (über DB/offen, O CW, bis DA)
    check(r.blocked == true, "falsch-o: CW-Anlauf prallt an DA ab")
    check(approx(State.player.angle, 82, 1.5), "falsch-o: Player stoppt an DA (82)")
    check(State.switchStates["O"] == "A", "falsch-o: O bleibt A (falsche Richtung)")
    check(State.consumedSwitches["O"] == nil, "falsch-o: O nicht verbraucht (kein Umschalten)")
    check(State.elementStates["S2"] == false, "falsch-o: S2 bleibt geschlossen")
end

-- --- SOLL-LÖSUNG (kompletter Durchlauf) ------------------------------------
do
    setup(Levels[5])
    -- 1) Baby auf P parken (S1 öffnet).
    Room.movePlayer(44) -- Player 276 -> 320, Baby 286 -> 328 (P)
    check(State.platePressed["P"] == true, "loesung1: Baby auf P -> S1 offen")
    -- 2) CCW durch S1 + D: die NATÜRLICHE CCW-Überquerung von D öffnet DA
    --    (andersherum), dann DA + O CCW überqueren -> O verbraucht, S2+Tor offen.
    local _, r2 = Room.movePlayer(-262) -- 320 -> 58 (S1, D->B, DA, O->B)
    check(r2.blocked == false, "loesung2: CCW-Route läuft (D öffnet DA)")
    check(State.switchStates["D"] == "B", "loesung2: D=B (natürliche Richtung)")
    check(State.elementStates["DA"] == true, "loesung2: DA offen (D=B)")
    check(State.switchStates["O"] == "B", "loesung2: O=B (richtige Richtung)")
    check(State.consumedSwitches["O"] == true, "loesung2: O verbraucht (oneShot)")
    check(State.elementStates["S2"] == true, "loesung2: S2 dauerhaft offen (vorbereitet)")
    check(State.elementStates["T"] == true, "loesung2: Tor T dauerhaft offen (vorbereitet)")
    check(approx(State.player.angle, 58, 0.5), "loesung2: Player bei ~58")
    -- 3) Rückkehr CW: das Baby wird dabei CW zu U@342 geschoben (der Player
    --    endet bei 334 — außerhalb des PRÄZISEN Druckbereichs der Platte
    --    (±2°), also hält der Player P NICHT mehr; S1 schließt, sobald das
    --    Baby P verlässt — egal, die Kette (O/S2/T) ist bereits vorbereitet.
    local _, r3 = Room.movePlayer(276) -- 58 -> 334, Baby 328 -> 342 (U-Dock)
    check(r3.blocked == false, "loesung3: Rückkehr (CW) läuft")
    check(approx(State.player.angle, 334, 0.5), "loesung3: Player an U (334)")
    check(approx(State.baby.angle, 342, 1.0), "loesung3: Baby an U (342)")
    check(State.platePressed["P"] == false,
        "loesung3: P frei (präziser Druckbereich — Player@334 steht nicht mehr drauf)")
    -- 4) U GEMEINSAM benutzen -> verschwindet erst nach vollständigem Transit.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "loesung4: U GEMEINSAM benutzt")
    Bridge.update(0.5)
    check(State.consumedBridges["U"] == true, "loesung4: U verbraucht (Point of No Return)")
    check(State.player.ring == "inner" and approx(State.player.angle, 342, 0.5),
        "loesung4: Player inner@342")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 352, 0.5),
        "loesung4: Baby inner@352 (vor dem Player)")
    -- Nach dem Transit steht niemand mehr auf P -> S1 schließt (egal).
    check(State.platePressed["P"] == false, "loesung4: P frei (beide inner)")
    check(State.elementStates["S1"] == false, "loesung4: S1 geschlossen (egal)")
    -- 5) Vorbereiteter Weg CW durch S2@60 zur Center-Bridge T@180.
    check(State.elementStates["S2"] == true, "loesung5: S2 offen (vorbereitet)")
    local _, r5 = Room.movePlayer(190) -- Player 342 -> 172, Baby 352 -> 180 (CW durch 0°)
    check(r5.blocked == false, "loesung5: Schub durch S2 zum Tor läuft")
    check(approx(State.player.angle, 172, 0.5), "loesung5: Player am Tor (172)")
    check(Gate.isUsable(Levels[5].gate, "inner", State.player.angle) == true,
        "loesung5: Tor nutzbar (Player UND Baby)")
    -- 6) Gemeinsamer Kernbrücken-Transit -> EXIT.
    local resG = Room.tryUseConnection()
    check(resG.used == true and resG.kind == "gate" and resG.crossing == true
        and resG.roomComplete == false, "loesung6: Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "loesung6: gemeinsamer Center-Transit abgeschlossen (Level 5 fertig)")
    check(State.player.ring == "inner" and approx(State.player.angle, 180, 0.5),
        "loesung6: Player am Gate-Ring @180 (Ziel = Mittelpunkt)")
    check(approx(State.baby.angle, 190, 0.5),
        "loesung6: Baby behält EIGENEN Winkel @190 (VOR dem Player)")
end

-- --- LEVEL-6-ÜBERGABE: Exit @180, Ring 2 -> Level-6-Außenring --------------
do
    -- Nach dem gemeinsamen Center-Transit stehen beide Figuren am Gate-Ring
    -- inner@180/190 (Level-5-Tor). Der RingNAME des neuen Raums wird aus der
    -- RingNUMMER des alten Raums abgeleitet: Level-5-Innenring (2) wird zu
    -- Level-6-Außenring (2).
    check(RoomTransition.ringNameForRoom(Levels[5].rings.inner, Levels[6]) == "outer",
        "uebergabe: Level-5-inner (2) -> Level-6-outer (2)")
    check(Levels[5].rings.middle == nil, "uebergabe: kein dritter Ring in Level 5")
    check(Levels[5].gate.angle == 180, "uebergabe: Exit-Winkel @180 (beide Figuren)")
end

TestReport.room5 = { pass = pass, fail = fail }
