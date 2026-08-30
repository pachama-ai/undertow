-- Tests für Raum 8 „Das letzte Band“ (NICHT-LINEARES Kombinationspuzzle).
--   EXAKT 2 aktive Ringbahnen 0/-1 + Mittelpunkt, KEIN dritter Ring, KEIN
--   Tutorial (phaseTwoStartRoom = 8).
--
--   MECHANIKEN (alle bekannt, kombiniert):
--     - DREI Druckplatten P1 (outer@130 -> A@112), P2 (outer@149 -> C@132),
--       P3 (outer@180 -> D@5): gedrückt nur, solange das Baby dort geparkt ist.
--     - ZWEI Doppelschalter D1 (inner@95, Start A) und D2 (inner@225, Start A).
--     - Einmalschalter O (inner@200, Start A): nur die CCW-Überquerung (-> B)
--       verbraucht ihn und öffnet den finalen Shutter S_FINAL_O DAUERHAFT.
--     - ZWISCHENZIEL (O erreichbar): D1=A UND D2=A UND P2=aktiv.
--     - FINALZUSTAND (Weg zum Tor): D1=A, D2=B, O verbraucht, P1/P2/P3 frei.
--     - D1 wird VIERMAL umgestellt (B->A->B->A), D2 EINMAL (A->B). Das Baby
--       wird DREIMAL umpositioniert (P1->P2->P3).
--     - Sechs Brücken: A (P1), B (D1=B), C (P2), D (P3), F (D2=B, finale
--       Verbindung, durch S_FI bis D1=A gesperrt) + Einmal-Brücke U (outer@45)
--       + Tor T (outer@355, nur gemeinsam).
--
--   ABLAUF (Soll-Lösung, Winkel physikalisch verifiziert):
--     1) Baby CW auf P1 (130) schieben -> Bridge A@112. Player SOLO über A
--        nach innen (inner@112).
--     2) D1 CCW -> B: Bridge B@75, S_O+S_FI+S_FINAL_D1 zu. SOLO über B nach
--        außen (outer@75, ANDERE Babyseite).
--     3) Baby von P1 CW zu P2 (149) schieben -> Bridge C@132 (A verschwindet).
--     4) SOLO über C nach innen (inner@132). D1 B -> A (CW): S_O öffnet,
--        S_FI+S_FINAL_D1 öffnen, B verschwindet.
--     5) CW durch S_O (D1=A) + S_D2 (D2=A) zu O. O CCW -> B verbraucht,
--        S_FINAL_O dauerhaft offen. (CW wäre wirkungslos.)
--     6) D1 A -> B (CCW): S_O+S_FI+S_FINAL_D1 zu, B wieder da. SOLO über B
--        nach außen (outer@75, RICHTIGE Seite von Baby/P2).
--     7) Baby von P2 CW zu P3 (180) schieben -> Bridge D@5 (C verschwindet).
--     8) SOLO über D nach innen (inner@5). D1 B -> A (CW): B weg (Rückweg
--        geopfert), S_FI+S_FINAL_D1 offen. D2 A -> B (CCW): S_D2 zu,
--        S_FINAL_D2 + F öffnen.
--     9) SOLO über D zurück nach außen (outer@5), Baby von P3 holen.
--    10) Baby zur Einmal-Brücke U (45) schieben. U GEMEINSAM -> inner@45/
--        Baby@35.
--    11) Finaler Push: Player+Baby über F (D2=B, inner@295) auf den Außenring
--        (outer@295/Baby@305), durch S_FINAL_D1 (D1=A) + S_FINAL_D2 (D2=B) +
--        S_FINAL_O (O verbraucht) zum Tor T (outer@355) -> gemeinsamer
--        Kernbrücken-Transit -> EXIT.
--
--   DIE FALLE: U ist früh sichtbar und benutzbar (frei). Zu frühe Benutzung
--   (solo oder gemeinsam) verbraucht U -> das Baby kann nicht mehr auf den
--   inneren Ring gebracht werden -> Sackgasse, B-Restart.
--
--   ANTI-BYPASS (explizit geprüft):
--     - A/C/D sind ohne Baby auf der jeweiligen Platte inaktiv.
--     - O ist ohne D1=A (S_O zu) ODER D2=A (S_D2 zu) NICHT erreichbar.
--     - O CW überquert = wirkungslos (wird nicht verbraucht).
--     - F ist durch S_FI gesperrt, solange D1=B (kein F-Bypass statt U).
--     - U SOLO benutzt -> Level nicht lösbar.
--     - Finale Route mit D1=B / D2=A / ohne O nicht offen (Tor gesperrt).
--     - Baby kann ohne Shared-U nicht zum Zentrum.
-- Am Ende wird das Ergebnis in TestReport.room8 gesammelt.

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

-- --- Raum 8 Daten ----------------------------------------------------------
do
    local r8 = Levels[8]
    check(r8.name == "Das letzte Band", "daten: Name 'Das letzte Band'")
    check(r8.rings.outer == 0 and r8.rings.inner == -1 and r8.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (0/-1) — kein dritter Ring")
    check(r8.start.ring == "outer" and approx(r8.start.angle, 20),
        "daten: ENTRY = Level-7-Ausgang (Player outer@20)")
    check(r8.baby ~= nil and r8.baby.start.ring == "outer" and approx(r8.baby.start.angle, 50),
        "daten: Baby outer@50 (CW vor dem Player)")
    check(#r8.switches == 3, "daten: genau 3 Schalter (D1 + D2 + O)")
    local d1, d2, o
    for _, sw in ipairs(r8.switches) do
        if sw.id == "D1" then d1 = sw end
        if sw.id == "D2" then d2 = sw end
        if sw.id == "O" then o = sw end
    end
    check(d1 ~= nil and d1.ring == "inner" and approx(d1.angle, 95) and d1.state == "A",
        "daten: D1 inner@95 (Start A — 4 Wechsel: B->A->B->A)")
    check(type(d1.onA) == "table" and d1.onA[1] == "S_O" and d1.onA[2] == "S_FI"
        and d1.onA[3] == "S_FINAL_D1" and d1.onB == "B",
        "daten: D1 — A öffnet S_O+S_FI+S_FINAL_D1, B aktiviert B")
    check(d2 ~= nil and d2.ring == "inner" and approx(d2.angle, 225) and d2.state == "A",
        "daten: D2 inner@225 (Start A — genau 1 Wechsel: A->B)")
    check(type(d2.onA) == "string" and d2.onA == "S_D2" and type(d2.onB) == "table"
        and d2.onB[1] == "S_FINAL_D2" and d2.onB[2] == "F",
        "daten: D2 — A öffnet S_D2, B öffnet S_FINAL_D2 + aktiviert F")
    check(o ~= nil and o.ring == "inner" and approx(o.angle, 200) and o.state == "A" and o.oneShot == true,
        "daten: O inner@200 EINMALSCHALTER (Start A)")
    check(type(o.onA) == "table" and #o.onA == 0 and o.onB == "S_FINAL_O",
        "daten: O — A öffnet nichts, B öffnet S_FINAL_O (One-Shot)")
    check(#r8.shutters == 6, "daten: genau 6 Blenden (S_O/S_D2/S_FI/S_FINAL_D1/S_FINAL_D2/S_FINAL_O)")
    local sO, sD2, sFI, sFD1, sFD2, sFO
    for _, shu in ipairs(r8.shutters) do
        if shu.id == "S_O" then sO = shu end
        if shu.id == "S_D2" then sD2 = shu end
        if shu.id == "S_FI" then sFI = shu end
        if shu.id == "S_FINAL_D1" then sFD1 = shu end
        if shu.id == "S_FINAL_D2" then sFD2 = shu end
        if shu.id == "S_FINAL_O" then sFO = shu end
    end
    check(sO ~= nil and sO.ring == "inner" and approx(sO.angle, 150),
        "daten: S_O inner@150 (D1-A offen, erste O-Hälfte)")
    check(sD2 ~= nil and sD2.ring == "inner" and approx(sD2.angle, 178),
        "daten: S_D2 inner@178 (D2-A offen, zweite O-Hälfte auf dem O-Zulauf)")
    check(sFI ~= nil and sFI.ring == "inner" and approx(sFI.angle, 295),
        "daten: S_FI inner@295 (D1-A offen, sperrt F bis zum Finalzustand)")
    check(sFD1 ~= nil and sFD1.ring == "outer" and approx(sFD1.angle, 305),
        "daten: S_FINAL_D1 outer@305 (D1-A offen, finaler Shutter)")
    check(sFD2 ~= nil and sFD2.ring == "outer" and approx(sFD2.angle, 322),
        "daten: S_FINAL_D2 outer@322 (D2-B offen, finaler Shutter)")
    check(sFO ~= nil and sFO.ring == "outer" and approx(sFO.angle, 340),
        "daten: S_FINAL_O outer@340 (O-B offen, finaler Shutter)")
    check(#r8.bridges == 6, "daten: genau 6 Brücken (A/B/C/D/F + Einmal-Brücke U)")
    local bA, bB, bC, bD, bF, bU
    for _, b in ipairs(r8.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "B" then bB = b end
        if b.id == "C" then bC = b end
        if b.id == "D" then bD = b end
        if b.id == "F" then bF = b end
        if b.id == "U" then bU = b end
    end
    check(bA ~= nil and bA.free == false and approx(bA.angle, 112),
        "daten: Bridge A@112 (free=false — von P1 gesteuert)")
    check(bB ~= nil and bB.free == false and approx(bB.angle, 75),
        "daten: Bridge B@75 (free=false — von D1 in Zustand B)")
    check(bC ~= nil and bC.free == false and approx(bC.angle, 132),
        "daten: Bridge C@132 (free=false — von P2 gesteuert)")
    check(bD ~= nil and bD.free == false and approx(bD.angle, 5) and bD.babyLandDir == -1,
        "daten: Bridge D@5 (free=false — von P3 gesteuert, dritter Einstieg)")
    check(bF ~= nil and bF.free == false and approx(bF.angle, 295) and bF.babyLandDir == 1,
        "daten: Bridge F@295 (free=false — von D2 in Zustand B, finale Verbindung)")
    check(bU ~= nil and bU.free == true and bU.oneShot == true and approx(bU.angle, 45) and bU.babyLandDir == -1,
        "daten: Einmal-Brücke U@45 FREI + oneShot (die FALLE)")
    check(#r8.plates == 3, "daten: genau 3 Druckplatten (P1 + P2 + P3)")
    local p1, p2, p3
    for _, p in ipairs(r8.plates) do
        if p.id == "P1" then p1 = p end
        if p.id == "P2" then p2 = p end
        if p.id == "P3" then p3 = p end
    end
    check(p1 ~= nil and p1.ring == "outer" and approx(p1.angle, 130) and p1.on == "A",
        "daten: P1 outer@130 steuert Bridge A (erster Baby-Parkplatz)")
    check(p2 ~= nil and p2.ring == "outer" and approx(p2.angle, 149) and p2.on == "C",
        "daten: P2 outer@149 steuert Bridge C (zweiter Baby-Parkplatz)")
    check(p3 ~= nil and p3.ring == "outer" and approx(p3.angle, 180) and p3.on == "D",
        "daten: P3 outer@180 steuert Bridge D (dritter Baby-Parkplatz)")
    check(r8.gate.id == "T" and r8.gate.ring == "outer" and r8.gate.free == true
        and approx(r8.gate.angle, 355),
        "daten: Tor T outer@355 (frei, normale Center-Bridge)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[8])
    check(State.platePressed["P1"] == false and State.platePressed["P2"] == false
        and State.platePressed["P3"] == false,
        "start: alle drei Platten frei")
    check(State.switchStates["D1"] == "A", "start: D1 = A")
    check(State.elementStates["B"] == false, "start: Bridge B inaktiv (D1=A)")
    check(State.elementStates["S_O"] == true, "start: S_O offen (D1=A)")
    check(State.elementStates["S_FI"] == true, "start: S_FI offen (D1=A)")
    check(State.elementStates["S_FINAL_D1"] == true, "start: S_FINAL_D1 offen (D1=A)")
    check(State.switchStates["D2"] == "A", "start: D2 = A")
    check(State.elementStates["S_D2"] == true, "start: S_D2 offen (D2=A)")
    check(State.elementStates["S_FINAL_D2"] == false, "start: S_FINAL_D2 zu (D2=A)")
    check(State.elementStates["F"] == false, "start: Bridge F inaktiv (D2=A)")
    check(State.elementStates["A"] == false, "start: Bridge A INAKTIV (P1 frei)")
    check(State.elementStates["C"] == false, "start: Bridge C INAKTIV (P2 frei)")
    check(State.elementStates["D"] == false, "start: Bridge D INAKTIV (P3 frei)")
    check(State.switchStates["O"] == "A", "start: O = A")
    check(State.elementStates["S_FINAL_O"] == false, "start: S_FINAL_O geschlossen (O=A)")
    check(State.elementStates["U"] == true, "start: Einmal-Brücke U FREI aktiv (Falle sichtbar)")
    check(State.elementStates["T"] == true, "start: Tor T frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 20),
        "start: Player outer@20")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 50),
        "start: Baby outer@50")
end

-- --- Anti-Bypass: A/C/D sind ohne Baby auf der Platte unbenutzbar ----------
do
    setup(Levels[8])
    check(State.elementStates["A"] == false, "platten: Bridge A INAKTIV (Start)")
    check(State.elementStates["C"] == false, "platten: Bridge C INAKTIV (Start)")
    check(State.elementStates["D"] == false, "platten: Bridge D INAKTIV (Start)")
    -- Baby auf P1 parken (A aktiv), auf P2 schieben (C aktiv), auf P3 schieben (D aktiv).
    local _, r1 = Room.movePlayer(101.83) -- 20 -> 121.83, Baby 50 -> 130 (P1)
    check(r1.blocked == false, "platten: Parken auf P1 läuft")
    check(State.elementStates["A"] == true, "platten: A aktiv (Baby auf P1)")
    check(State.elementStates["C"] == false, "platten: C INAKTIV (Baby nicht auf P2)")
    -- Schub P1 -> P2: Player bei 121.83 (CCW des Babys) schiebt CW.
    local _, r2 = Room.movePlayer(19) -- 121.83 -> 140.83, Baby 130 -> 149 (P2)
    check(r2.blocked == false, "platten: Schub zu P2 läuft")
    check(State.elementStates["A"] == false, "platten: A INAKTIV (Baby nicht auf P1)")
    check(State.elementStates["C"] == true, "platten: C aktiv (Baby auf P2)")
    -- Schub P2 -> P3: Player bei 140.83 (CCW des Babys) schiebt CW.
    local _, r3 = Room.movePlayer(31) -- 140.83 -> 171.83, Baby 149 -> 180 (P3)
    check(r3.blocked == false, "platten: Schub zu P3 läuft")
    check(State.elementStates["C"] == false, "platten: C INAKTIV (Baby nicht auf P2)")
    check(State.elementStates["D"] == true, "platten: D aktiv (Baby auf P3)")
end

-- --- Anti-Bypass: Tor braucht das Baby (Solo am Tor = kein Exit) -----------
do
    setup(Levels[8])
    State.player.ring = "outer"
    State.player.angle = 355
    check(Gate.isUsable(Levels[8].gate, "outer", 355) == false,
        "gate-baby: Tor ohne Baby auf dem Gate-Ring NICHT nutzbar")
    local res = Room.tryUseConnection()
    check(res.used == false, "gate-baby: tryUseConnection am Tor ohne Baby = kein Exit")
end

-- --- Phase 1: Baby auf P1 parken + Solo über A -----------------------------
do
    setup(Levels[8])
    local _, r = Room.movePlayer(101.83) -- 20 -> 121.83, Baby 50 -> 130 (EXAKT P1)
    check(r.blocked == false, "p1: Schub läuft")
    check(State.platePressed["P1"] == true, "p1: Baby EXAKT auf P1 -> gedrückt")
    check(State.elementStates["A"] == true, "p1: Bridge A MATERIALISIERT (P1 aktiv)")
    check(approx(State.player.angle, 121.83, 0.5), "p1: Player bei ~122")
    check(approx(State.baby.angle, 130, 1.0), "p1: Baby geparkt auf P1 (130)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "A",
        "p1: Player benutzt Bridge A ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 112, 0.5),
        "p1: Player inner@112")
    check(State.platePressed["P1"] == true, "p1: Baby hält P1 -> A bleibt ausgefahren")
end

-- --- Phase 2: D1 CCW -> B + Solo über B ------------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- inner@112
    -- D1@95 CCW -> B (Eintritt 102, Austritt 88); Sweep endet direkt am B-Dock
    -- (inner@63): Bridge B@75 materialisiert während des Sweeps.
    local _, r1 = Room.movePlayer(-49) -- 112 -> 63
    check(r1.blocked == false, "p2: D1-CCW-Sweep läuft")
    check(State.switchStates["D1"] == "B", "p2: D1=B (Rückweg + O-Zugang zu)")
    check(State.elementStates["B"] == true, "p2: Bridge B materialisiert (D1=B)")
    check(State.elementStates["S_O"] == false, "p2: S_O zu (O-Zugang 1 gesperrt)")
    check(State.elementStates["S_FI"] == false, "p2: S_FI zu (finale Verbindung F gesperrt)")
    check(State.elementStates["S_FINAL_D1"] == false, "p2: S_FINAL_D1 zu (finaler Weg zu)")
    check(approx(State.player.angle, 63, 0.5), "p2: Player inner@63 (B-Dock)")
    -- SOLO über B -> outer@75 (ANDERE Babyseite).
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "B", "p2: Solo-Transit B")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 75, 0.5),
        "p2: Player outer@75 (ANDERE Babyseite)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 130, 1.0),
        "p2: Baby weiterhin auf P1 (130)")
end

-- --- Phase 3: Baby P1 -> P2 (A verschwindet, C erscheint) ------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B, inner@63
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5) -- outer@75
    -- CW-Schub 130 -> 149 (P2): der Player ist CCW des Babys.
    local _, r1 = Room.movePlayer(65.83) -- 75 -> 140.83, Baby 130 -> 149 (P2)
    check(r1.blocked == false, "p3: Schub P1->P2 läuft")
    check(State.platePressed["P1"] == false, "p3: P1 FREI (Baby herunter)")
    check(State.elementStates["A"] == false, "p3: Bridge A VERSCHWUNDEN (bewusst geopfert)")
    check(State.platePressed["P2"] == true, "p3: Baby EXAKT auf P2 -> gedrückt")
    check(State.elementStates["C"] == true, "p3: Bridge C MATERIALISIERT (P2 aktiv)")
    check(approx(State.baby.angle, 149, 1.0), "p3: Baby geparkt auf P2 (149)")
    check(approx(State.player.angle, 140.83, 0.5), "p3: Player bei ~141 (C-Dock)")
end

-- --- Phase 4: Solo über C + D1 B -> A (CW) ---------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83) -- Baby auf P2
    -- Solo über C (outer@132): Player@140.83 steht bereits im C-Dock.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "C", "p4: Solo-Transit C")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 132, 0.5),
        "p4: Player inner@132")
    -- CCW VOR D1's CW-Eintritt (87, strikt < 88), dann CW durch [88,102] -> A.
    local _, r1 = Room.movePlayer(-45) -- 132 -> 87 (D1 bleibt B)
    check(r1.blocked == false, "p4: CCW-Anlauf zu D1 läuft")
    local _, r2 = Room.movePlayer(15) -- 87 -> 102 (D1 CW -> A)
    check(r2.blocked == false, "p4: D1-CW-Sweep läuft")
    check(State.switchStates["D1"] == "A", "p4: D1=A (ZWISCHENZIEL)")
    check(State.elementStates["B"] == false, "p4: Bridge B verschwunden (D1=A)")
    check(State.elementStates["S_O"] == true, "p4: S_O offen (erste O-Hälfte)")
    check(State.elementStates["S_FI"] == true, "p4: S_FI offen (F entsperrt)")
    check(State.elementStates["S_FINAL_D1"] == true, "p4: S_FINAL_D1 offen")
    check(approx(State.player.angle, 102, 0.5), "p4: Player inner@102")
end

-- --- Phase 5: O korrekt (CCW) verbrauchen ----------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- inner@132
    Room.movePlayer(-45)
    Room.movePlayer(15) -- D1=A, Player@102
    -- CW durch S_O (offen) + S_D2 (offen, D2=A) + O CW (no-op) ÜBER die
    -- O-Austrittskante (208) hinaus, dann CCW durch [193,207] -> B (One-Shot).
    local _, r1 = Room.movePlayer(106) -- 102 -> 208
    check(r1.blocked == false, "p5: CW-Zulauf zum O läuft")
    local _, r2 = Room.movePlayer(-15) -- 208 -> 193 (O CCW -> B)
    check(r2.blocked == false, "p5: O-CCW-Sweep läuft")
    check(State.switchStates["O"] == "B", "p5: O korrekt CCW verbraucht (O=B)")
    check(State.consumedSwitches["O"] == true, "p5: O DAUERHAFT verbraucht (oneShot)")
    check(State.elementStates["S_FINAL_O"] == true, "p5: S_FINAL_O DAUERHAFT offen")
    check(approx(State.player.angle, 193, 0.5), "p5: Player inner@193")
end

-- --- Phase 6: D1 A -> B (CCW) + Solo über B (Rückweg) ----------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15) -- D1=A
    Room.movePlayer(106)
    Room.movePlayer(-15) -- O verbraucht, Player@193
    -- CCW durch S_O + S_D2 (beide noch offen, D1=D2=A bis zum Crossing) zu D1
    -- -> B; Sweep endet direkt am B-Dock (inner@63).
    local _, r1 = Room.movePlayer(-130) -- 193 -> 63 (D1 CCW -> B)
    check(r1.blocked == false, "p6: D1-CCW-Sweep läuft")
    check(State.switchStates["D1"] == "B", "p6: D1=B (B wieder da)")
    check(State.elementStates["B"] == true, "p6: Bridge B materialisiert")
    check(State.elementStates["S_O"] == false, "p6: S_O zu (O-Zugang versiegelt)")
    check(State.elementStates["S_FINAL_D1"] == false, "p6: S_FINAL_D1 zu")
    check(approx(State.player.angle, 63, 0.5), "p6: Player inner@63 (B-Dock)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "B", "p6: Solo-Transit B (2.)")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 75, 0.5),
        "p6: Player outer@75 (RICHTIGE Seite von Baby/P2)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 149, 1.0),
        "p6: Baby weiterhin auf P2 (149)")
end

-- --- Phase 7: Baby P2 -> P3 (C verschwindet, D erscheint) ------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15)
    Room.movePlayer(106)
    Room.movePlayer(-15)
    Room.movePlayer(-130)
    Room.tryUseConnection()
    Bridge.update(0.5) -- outer@75
    -- CW-Schub 149 -> 180 (P3): Player@75 ist CCW des Babys.
    local _, r1 = Room.movePlayer(96.83) -- 75 -> 171.83, Baby 149 -> 180 (P3)
    check(r1.blocked == false, "p7: Schub P2->P3 läuft")
    check(State.platePressed["P2"] == false, "p7: P2 FREI (Baby herunter)")
    check(State.elementStates["C"] == false, "p7: Bridge C VERSCHWUNDEN")
    check(State.platePressed["P3"] == true, "p7: Baby EXAKT auf P3 -> gedrückt")
    check(State.elementStates["D"] == true, "p7: Bridge D MATERIALISIERT (P3 aktiv)")
    check(approx(State.baby.angle, 180, 1.0), "p7: Baby geparkt auf P3 (180)")
    check(approx(State.player.angle, 171.83, 0.5), "p7: Player bei ~172")
end

-- --- Phase 8: D solo + D1 B->A + D2 A->B (FINALZUSTAND) --------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15)
    Room.movePlayer(106)
    Room.movePlayer(-15)
    Room.movePlayer(-130)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(96.83) -- Baby auf P3, Player@171.83
    -- SOLO über D@5: CCW zu D's outer-Dock (353), dann Transit.
    local _, r1 = Room.movePlayer(-178.83) -- 171.83 -> 353
    check(r1.blocked == false, "p8: CCW zu D läuft")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "D", "p8: Solo-Transit D")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 5, 0.5),
        "p8: Player inner@5 (dritter Einstieg)")
    -- D1 B -> A (CW): CW zu 87 (strikt vor dem Eintritt), dann CW durch [88,102].
    local _, r2 = Room.movePlayer(82) -- 5 -> 87
    check(r2.blocked == false, "p8: CW-Anlauf zu D1 läuft")
    local _, r3 = Room.movePlayer(15) -- 87 -> 102 (D1 CW -> A)
    check(r3.blocked == false, "p8: D1-CW-Sweep läuft")
    check(State.switchStates["D1"] == "A", "p8: D1=A (Rückweg B geopfert)")
    check(State.elementStates["B"] == false, "p8: Bridge B VERSCHWUNDEN")
    check(State.elementStates["S_FI"] == true, "p8: S_FI offen (F entsperrt)")
    check(State.elementStates["S_FINAL_D1"] == true, "p8: S_FINAL_D1 offen")
    -- D2 A -> B (CCW): CCW von 102 durch 0/360 zu D2's Eintritt (232), dann
    -- Austritt (218) -> D2=B. Der Weg [0,102]+[232,360] nutzt S_D2 (offen,
    -- D2=A bis Crossing) und vermeidet S_FI (D1=A offen).
    local _, r4 = Room.movePlayer(-244) -- 102 -> 218 (D2 CCW -> B)
    check(r4.blocked == false, "p8: D2-CCW-Sweep läuft")
    check(State.switchStates["D2"] == "B", "p8: D2=B (FINALZUSTAND)")
    check(State.elementStates["S_D2"] == false, "p8: S_D2 zu (O-Zugang versiegelt)")
    check(State.elementStates["S_FINAL_D2"] == true, "p8: S_FINAL_D2 offen")
    check(State.elementStates["F"] == true, "p8: finale Verbindung F aktiv (D2=B)")
    check(approx(State.player.angle, 218, 0.5), "p8: Player inner@218")
end

-- --- Phase 9: D zurück + Baby von P3 holen ---------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15)
    Room.movePlayer(106)
    Room.movePlayer(-15)
    Room.movePlayer(-130)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(96.83)
    Room.movePlayer(-178.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- inner@5
    Room.movePlayer(82)
    Room.movePlayer(15)
    Room.movePlayer(-244) -- D2=B, Player@218
    -- SOLO über D zurück: CW von 218 zu 353 (vermeidet S_D2 [165,191]), Transit
    -- (Landung an der Brückenachse outer@5).
    local _, r1 = Room.movePlayer(135) -- 218 -> 353
    check(r1.blocked == false, "p9: CW zu D läuft")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "D", "p9: Solo-Transit D (2.)")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 5, 0.5),
        "p9: Player outer@5 (Landung an der Brückenachse)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 180, 1.0),
        "p9: Baby weiterhin auf P3 (180)")
end

-- --- Phase 10: Baby zu U, GEMEINSAM nach innen -----------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15)
    Room.movePlayer(106)
    Room.movePlayer(-15)
    Room.movePlayer(-130)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(96.83)
    Room.movePlayer(-178.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(82)
    Room.movePlayer(15)
    Room.movePlayer(-244)
    Room.movePlayer(135)
    Room.tryUseConnection()
    Bridge.update(0.5) -- outer@5
    -- CW umrunden hinter das Baby (180), dann CW-Schub 180 -> 45 (U).
    local _, r1 = Room.movePlayer(166.83) -- 5 -> 171.83 (hinter Baby)
    check(r1.blocked == false, "p10: CW-Anlauf läuft")
    local _, r2 = Room.movePlayer(225) -- 171.83 -> 36.83, Baby 180 -> 45 (U)
    check(r2.blocked == false, "p10: Schub zu U läuft")
    check(State.platePressed["P3"] == false, "p10: P3 FREI (Baby herunter)")
    check(State.elementStates["D"] == false, "p10: Bridge D VERSCHWUNDEN")
    check(approx(State.baby.angle, 45, 1.0), "p10: Baby an U (outer@45)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "p10: U GEMEINSAM benutzt (Baby voran)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 45, 0.5),
        "p10: Player inner@45 (U-Transit)")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 35, 0.5),
        "p10: Baby inner@35 (babyLandDir -1)")
    check(State.elementStates["U"] == false, "p10: U NACH dem Shared-Transit verbraucht")
end

-- --- Phase 11: Finaler Push über F zum Tor, gemeinsamer Exit ---------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-45)
    Room.movePlayer(15)
    Room.movePlayer(106)
    Room.movePlayer(-15)
    Room.movePlayer(-130)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(96.83)
    Room.movePlayer(-178.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(82)
    Room.movePlayer(15)
    Room.movePlayer(-244)
    Room.movePlayer(135)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(166.83)
    Room.movePlayer(225)
    Room.tryUseConnection()
    Bridge.update(0.5) -- inner@45/Baby@35
    -- CCW-Schub 35 -> 295 (F-Dock): der Weg [0,35]+[295,360] vermeidet S_D2.
    local _, r1 = Room.movePlayer(-101.83) -- 45 -> 303.17, Baby 35 -> 295 (F)
    check(r1.blocked == false, "p11: CCW-Schub zu F läuft")
    check(approx(State.baby.angle, 295, 1.0), "p11: Baby an F (inner@295)")
    local resF = Room.tryUseConnection()
    check(resF.used == true and resF.kind == "sharedBridge" and resF.id == "F", "p11: Shared-Transit F")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 295, 0.5),
        "p11: Player outer@295 (finale Verbindung)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 305, 0.5),
        "p11: Baby outer@305 (babyLandDir +1)")
    -- CW durch die drei finalen Shutter zum Tor T@355.
    local _, r2 = Room.movePlayer(51.83) -- 295 -> 346.83, Baby 305 -> 355 (Tor)
    check(r2.blocked == false, "p11: finaler Ringweg läuft")
    check(State.elementStates["S_FINAL_D1"] == true, "p11: S_FINAL_D1 offen (D1=A)")
    check(State.elementStates["S_FINAL_D2"] == true, "p11: S_FINAL_D2 offen (D2=B)")
    check(State.elementStates["S_FINAL_O"] == true, "p11: S_FINAL_O offen (O verbraucht)")
    check(Gate.isUsable(Levels[8].gate, "outer", State.player.angle) == true,
        "p11: Tor nutzbar (FINALZUSTAND)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "p11: Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "p11: gemeinsamer Center-Transit abgeschlossen (Level 8 fertig)")
end

-- --- O-FALSCH: CW-Überquerung verbraucht O NICHT ---------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B, inner@63
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5)
    Room.movePlayer(65.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5) -- inner@132
    Room.movePlayer(-45) -- 132 -> 87
    Room.movePlayer(15) -- D1=A, Player@102
    -- CW-Sweep 102 -> 208 überquert O CW (wirkungslos).
    local _, r = Room.movePlayer(106)
    check(r.blocked == false, "o-falsch: CW-Zulauf läuft")
    check(State.switchStates["O"] == "A", "o-falsch: O bleibt A (CW wirkungslos)")
    check(State.consumedSwitches["O"] == nil, "o-falsch: O NICHT verbraucht (CW)")
    check(State.elementStates["S_FINAL_O"] == false, "o-falsch: S_FINAL_O bleibt zu")
    -- Erst die CCW-Überquerung verbraucht O.
    Room.movePlayer(-15) -- 208 -> 193, O CCW -> B
    check(State.switchStates["O"] == "B", "o-falsch: O=B nach CCW")
    check(State.consumedSwitches["O"] == true, "o-falsch: O verbraucht (CCW)")
end

-- --- ANTI-BYPASS: O ohne P2 (C inaktiv) unerreichbar -----------------------
do
    setup(Levels[8])
    -- Baby bleibt auf P1 (nicht P2): C bleibt inaktiv -> kein innerer Zugang.
    local bC = nil
    for _, b in ipairs(Levels[8].bridges) do
        if b.id == "C" then bC = b end
    end
    Room.movePlayer(101.83) -- Baby auf P1, Player@121.83
    check(State.elementStates["C"] == false, "bypass-o-p2: C INAKTIV (Baby auf P1)")
    check(bC ~= nil and Bridge.isUsable(bC, 132) == false,
        "bypass-o-p2: C nicht benutzbar (O unerreichbar)")
end

-- --- ANTI-BYPASS: O mit D2=B (S_D2 zu) unerreichbar ------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B, inner@63
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(65.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- inner@132
    Room.movePlayer(-45)
    Room.movePlayer(15) -- D1=A, Player@102
    -- D2 zu früh auf B (bewusst): S_D2 schließt und versiegelt den O-Zulauf.
    State.switchStates["D2"] = "B"
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.elementStates["S_D2"] == false, "bypass-o-d2: S_D2 zu (D2=B)")
    -- Der Player müsste O erreichen, aber der O-Zulauf (102 -> O) ist durch
    -- S_D2 versiegelt: CW von 102 prallt an S_D2 (165).
    local _, r2 = Room.movePlayer(105) -- CW, prallt an S_D2@178 [165,191]
    check(r2.blocked == true, "bypass-o-d2: CW PRALLT AN S_D2 (O unerreichbar)")
    check(approx(State.player.angle, 165, 1.0), "bypass-o-d2: Player an S_D2-Kante (165)")
    check(State.switchStates["O"] == "A", "bypass-o-d2: O bleibt A")
end

-- --- ANTI-BYPASS: O mit D1=B (S_O zu) unerreichbar -------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B, inner@63
    check(State.elementStates["S_O"] == false, "bypass-o-d1: S_O zu (D1=B)")
    -- Der Player steht an D1's CW-Eintritt (102) bei D1=B: CW zu O prallt an S_O.
    State.player.ring = "inner"
    State.player.angle = 102
    local _, r2 = Room.movePlayer(105) -- CW, prallt an S_O@150 [137,163]
    check(r2.blocked == true, "bypass-o-d1: CW PRALLT AN S_O (O unerreichbar)")
    check(approx(State.player.angle, 137, 1.0), "bypass-o-d1: Player an S_O-Kante (137)")
    check(State.switchStates["O"] == "A", "bypass-o-d1: O bleibt A")
end

-- --- ANTI-BYPASS: F ist bis D1=A durch S_FI gesperrt -----------------------
do
    setup(Levels[8])
    local bF = nil
    for _, b in ipairs(Levels[8].bridges) do
        if b.id == "F" then bF = b end
    end
    check(bF ~= nil, "bypass-f: Bridge F gefunden")
    -- Bei D2=A ist F inaktiv.
    check(State.elementStates["F"] == false, "bypass-f: F INAKTIV (D2=A) am Start")
    check(Bridge.isUsable(bF, 295) == false, "bypass-f: F nicht benutzbar (D2=A)")
    -- Nach D1=B (bei D2=A) bleibt F inaktiv.
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B
    check(State.elementStates["F"] == false, "bypass-f: F bleibt inaktiv (D2=A)")
    check(Bridge.isUsable(bF, 295) == false, "bypass-f: F nicht benutzbar (D2=A)")
    -- Selbst mit D2=B: solange D1=B ist S_FI zu -> F gesperrt (kein F-Bypass statt U).
    State.switchStates["D2"] = "B"
    State.deriveElements()
    check(State.elementStates["F"] == true, "bypass-f: F aktiv (D2=B) — aber S_FI zu (D1=B)")
    check(Bridge.isUsable(bF, 295) == false, "bypass-f: F GESPERRT (S_FI zu, D1=B)")
end

-- --- DIE FALLE: U zu früh (gemeinsam) = Sackgasse --------------------------
do
    setup(Levels[8])
    -- U ist frei: Player setzt das Baby direkt in Shared-Reichweite von U
    -- (frühe, scheinbar verführerische Benutzung).
    State.player.ring = "outer"
    State.player.angle = 36.83
    State.baby.ring = "outer"
    State.baby.angle = 45
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "falle: U wird zu früh GEMEINSAM benutzt")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 45, 0.5),
        "falle: Player inner@45")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 35, 0.5),
        "falle: Baby inner@35 (auch eingesperrt)")
    check(State.elementStates["U"] == false, "falle: U verbraucht — kein Rückweg")
    check(State.elementStates["S_FINAL_O"] == false, "falle: S_FINAL_O ZU (O wurde nie gesetzt)")
    check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == false,
        "falle: Tor NIE erreichbar (Tor ist auf dem Außenring, F zu)")
    -- Keine der Brücken ist mehr benutzbar: A/C/D (Platten frei), B (D1=A),
    -- F (D2=A) — der eingeschlossene Player kommt nie mehr zum Tor.
    local anyUsable = false
    for _, b in ipairs(Levels[8].bridges) do
        if b.id ~= "U" and Bridge.isUsable(b, State.player.angle) then
            anyUsable = true
        end
    end
    check(anyUsable == false, "falle: KEINE Brücke mehr benutzbar (Sackgasse)")
end

-- --- DIE FALLE: U zu früh (solo) = Sackgasse -------------------------------
do
    setup(Levels[8])
    -- Player allein an U (Baby manuell weit entfernt): SOLO über U.
    State.player.ring = "outer"
    State.player.angle = 45
    State.baby.ring = "outer"
    State.baby.angle = 200
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "U",
        "falle-solo: U SOLO benutzt (Baby zu weit)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 45, 0.5),
        "falle-solo: Player ALLEIN inner@45")
    check(State.baby ~= nil and State.baby.ring == "outer",
        "falle-solo: Baby bleibt auf dem Außenring")
    check(State.elementStates["U"] == false, "falle-solo: U verbraucht")
    check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == false,
        "falle-solo: Tor ohne Baby NIE erreichbar")
end

-- --- ANTI-BYPASS: Tor vor dem FINALZUSTAND gesperrt ------------------------
do
    setup(Levels[8])
    -- Finalzustand = D1=A, D2=B, O verbraucht. Vorher ist mindestens ein
    -- finaler Shutter zu: S_FINAL_O (O), S_FINAL_D1 (D1=B), S_FINAL_D2 (D2=A).
    Room.movePlayer(101.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(-49) -- D1=B
    check(State.elementStates["S_FINAL_D1"] == false, "bypass-final: S_FINAL_D1 zu (D1=B)")
    check(Gate.isUsable(Levels[8].gate, "outer", 355) == false,
        "bypass-final: Tor NICHT nutzbar (finaler Shutter zu)")
    -- O nicht verbraucht: S_FINAL_O [327,353] blockiert den Zulauf zum Tor.
    check(State.elementStates["S_FINAL_O"] == false, "bypass-final: S_FINAL_O zu (O=A)")
    -- D2=A: S_FINAL_D2 zu + F inaktiv.
    check(State.elementStates["S_FINAL_D2"] == false, "bypass-final: S_FINAL_D2 zu (D2=A)")
    check(State.elementStates["F"] == false, "bypass-final: F inaktiv (D2=A)")
end

-- --- Undo: genau EIN Snapshot pro Frame trotz Schalter + Push --------------
do
    setup(Levels[8])
    Room.movePlayer(101.83) -- Push (Baby auf P1): genau 1 Undo-Eintrag
    check(Undo.count() == 1, "undo: Push auf P1 = genau 1 Snapshot")
    Room.movePlayer(-16.83) -- 121.83 -> 105, reine Bewegung: kein Snapshot
    check(Undo.count() == 1, "undo: reine Bewegung = kein Snapshot")
    Room.tryUseConnection() -- Solo A (keine oneShot-Brücke): kein Snapshot
    Bridge.update(0.5)
    check(Undo.count() == 1, "undo: Solo-Transit A = kein Snapshot")
    Room.movePlayer(-49) -- D1 CCW -> B (Schalter): genau 1 Snapshot
    check(Undo.count() == 2, "undo: D1-Wechsel = genau 1 Snapshot")
    Room.tryUseConnection() -- Solo B (B ist NICHT oneShot)
    Bridge.update(0.5)
    check(Undo.count() == 2, "undo: Solo-Transit B = kein Snapshot (B nicht oneShot)")
    Room.movePlayer(65.83) -- Push (Baby auf P2): genau 1 Snapshot
    check(Undo.count() == 3, "undo: Push auf P2 = genau 1 Snapshot")
    Room.tryUseConnection() -- Solo C (keine oneShot-Brücke): kein Snapshot
    Bridge.update(0.5)
    check(Undo.count() == 3, "undo: Solo-Transit C = kein Snapshot")
    Room.movePlayer(-45) -- CCW-Anlauf (kein Wechsel): kein Snapshot
    check(Undo.count() == 3, "undo: CCW-Anlauf = kein Snapshot")
    Room.movePlayer(15) -- D1 CW -> A (Schalter): genau 1 Snapshot
    check(Undo.count() == 4, "undo: D1-Wechsel zurück = genau 1 Snapshot")
end

TestReport.room8 = { pass = pass, fail = fail }
