-- Tests für Raum 8 „Das letzte Band“ (NICHT-LINEARES Kombinationspuzzle).
--   EXAKT 2 aktive Ringbahnen 0/-1 + Mittelpunkt, KEIN dritter Ring, KEIN
--   Tutorial (phaseTwoStartRoom = 8).
--
--   MECHANIKEN (alle bekannt, kombiniert):
--     - ZWEI Druckplatten P1 (outer@130 -> Bridge A@112) und P2 (outer@149 ->
--       Bridge C@132): gedrückt nur, solange das Baby exakt dort geparkt ist.
--     - ZWEI Doppelschalter D1 (inner@95, Start A) und D2 (inner@225, Start B).
--     - Einmalschalter O (inner@200, Start A): nur die CCW-Überquerung (-> B)
--       verbraucht ihn und öffnet den finalen Shutter S_FINAL_O DAUERHAFT.
--     - ZWISCHENZIEL (O erreichbar): D1=B UND D2=A UND P2=aktiv.
--     - FINALZUSTAND (Weg zum Tor): D1=A, D2=B, O verbraucht, P2 frei.
--     - Vier aktivierbare Brücken A (P1), R (D1=B), C (P2), F (D2=B, durch
--       S_FI zusätzlich gesperrt bis D1=A) + Einmal-Brücke U (outer@325) +
--       Tor T (outer@355, nur gemeinsam).
--
--   ABLAUF (Soll-Lösung, Winkel physikalisch verifiziert):
--     1) Baby CW auf P1 (130) schieben -> Bridge A@112. Player SOLO über A
--        nach innen (inner@112).
--     2) D1 CCW -> B: Bridge R@60, S_D1 offen, S_FINAL_A + S_FI zu. SOLO über
--        R nach außen (outer@60, ANDERE Babyseite).
--     3) Baby von P1 CW zu P2 (149) schieben -> Bridge C@132 (A verschwindet).
--     4) SOLO über C nach innen (inner@132). D2 CW -> A: S_D2 offen.
--     5) Durch S_D1 + S_D2 (beide offen) zu O. O CCW -> B verbraucht,
--        S_FINAL_O dauerhaft offen. (CW wäre wirkungslos.)
--     6) D2 CCW -> B: S_D2 zu. D1 bleibt B (R wird noch gebraucht).
--     7) SOLO über R wieder nach außen (outer@60, RICHTIGE Seite von Baby/P2).
--     8) Baby von P2 zur Einmal-Brücke U (325) schieben. U GEMEINSAM ->
--        inner@325/Baby@315.
--     9) D1 CW -> A: R verschwindet, S_FINAL_A + S_FI öffnen den finalen Weg.
--    10) Über F (D2=B, D1=A) gemeinsam auf den Außenring (outer@295/Baby@305),
--        durch S_FINAL_O + S_FINAL_A zum Tor T (outer@355) -> gemeinsamer
--        Kernbrücken-Transit -> EXIT.
--
--   DIE FALLE: U ist früh sichtbar und benutzbar (frei). Zu frühe Benutzung
--   (solo oder gemeinsam) verbraucht U -> das Baby kann nicht mehr auf den
--   inneren Ring gebracht werden -> Sackgasse, B-Restart.
--
--   ANTI-BYPASS (explizit geprüft):
--     - A/C sind ohne Baby auf der jeweiligen Platte inaktiv.
--     - O ist ohne D1=B (S_D1 zu) NICHT erreichbar — der Korridor ist versiegelt.
--     - O CW überquert = wirkungslos (wird nicht verbraucht).
--     - F ist durch S_FI gesperrt, solange D1=B (kein F-Bypass statt U).
--     - U SOLO benutzt -> Level nicht lösbar.
--     - Finale Route mit D1=B ODER ohne O nicht offen (Tor gesperrt).
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
        "daten: D1 inner@95 (Start A — muss auf B und zurück auf A)")
    check(type(d1.onA) == "table" and d1.onA[1] == "S_FINAL_A" and d1.onA[2] == "S_FI"
        and type(d1.onB) == "table" and d1.onB[1] == "R" and d1.onB[2] == "S_D1",
        "daten: D1 — A öffnet S_FINAL_A+S_FI, B aktiviert R+S_D1")
    check(d2 ~= nil and d2.ring == "inner" and approx(d2.angle, 225) and d2.state == "B",
        "daten: D2 inner@225 (Start B — muss auf A und zurück auf B)")
    check(d2.onA == "S_D2" and d2.onB == "F",
        "daten: D2 — A öffnet S_D2, B aktiviert F")
    check(o ~= nil and o.ring == "inner" and approx(o.angle, 200) and o.state == "A" and o.oneShot == true,
        "daten: O inner@200 EINMALSCHALTER (Start A)")
    check(type(o.onA) == "table" and #o.onA == 0 and o.onB == "S_FINAL_O",
        "daten: O — A öffnet nichts, B öffnet S_FINAL_O (One-Shot)")
    check(#r8.shutters == 5, "daten: genau 5 Blenden (S_D1/S_D2/S_FI/S_FINAL_O/S_FINAL_A)")
    local sD1, sD2, sFI, sFO, sFA
    for _, shu in ipairs(r8.shutters) do
        if shu.id == "S_D1" then sD1 = shu end
        if shu.id == "S_D2" then sD2 = shu end
        if shu.id == "S_FI" then sFI = shu end
        if shu.id == "S_FINAL_O" then sFO = shu end
        if shu.id == "S_FINAL_A" then sFA = shu end
    end
    check(sD1 ~= nil and sD1.ring == "inner" and approx(sD1.angle, 150),
        "daten: S_D1 inner@150 (D1-B offen, erste O-Hälfte)")
    check(sD2 ~= nil and sD2.ring == "inner" and approx(sD2.angle, 255),
        "daten: S_D2 inner@255 (D2-A offen, zweite O-Hälfte)")
    check(sFI ~= nil and sFI.ring == "inner" and approx(sFI.angle, 295),
        "daten: S_FI inner@295 (D1-A offen, sperrt F bis zum Finalzustand)")
    check(sFO ~= nil and sFO.ring == "outer" and approx(sFO.angle, 340),
        "daten: S_FINAL_O outer@340 (O-B offen, finaler Shutter)")
    check(sFA ~= nil and sFA.ring == "outer" and approx(sFA.angle, 360),
        "daten: S_FINAL_A outer@360 (D1-A offen, finaler Abschnitt)")
    check(#r8.bridges == 5, "daten: genau 5 Brücken (A/R/C/F + Einmal-Brücke U)")
    local bA, bR, bC, bF, bU
    for _, b in ipairs(r8.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "R" then bR = b end
        if b.id == "C" then bC = b end
        if b.id == "F" then bF = b end
        if b.id == "U" then bU = b end
    end
    check(bA ~= nil and bA.free == false and approx(bA.angle, 112),
        "daten: Bridge A@112 (free=false — von P1 gesteuert)")
    check(bR ~= nil and bR.free == false and approx(bR.angle, 60),
        "daten: Bridge R@60 (free=false — von D1 in Zustand B)")
    check(bC ~= nil and bC.free == false and approx(bC.angle, 132),
        "daten: Bridge C@132 (free=false — von P2 gesteuert)")
    check(bF ~= nil and bF.free == false and approx(bF.angle, 295) and bF.babyLandDir == 1,
        "daten: Bridge F@295 (free=false — von D2 in Zustand B, finale Verbindung)")
    check(bU ~= nil and bU.free == true and bU.oneShot == true and approx(bU.angle, 325) and bU.babyLandDir == -1,
        "daten: Einmal-Brücke U@325 FREI + oneShot (die FALLE)")
    check(#r8.plates == 2, "daten: genau 2 Druckplatten (P1 + P2)")
    local p1, p2
    for _, p in ipairs(r8.plates) do
        if p.id == "P1" then p1 = p end
        if p.id == "P2" then p2 = p end
    end
    check(p1 ~= nil and p1.ring == "outer" and approx(p1.angle, 130) and p1.on == "A",
        "daten: P1 outer@130 steuert Bridge A (erster Baby-Parkplatz)")
    check(p2 ~= nil and p2.ring == "outer" and approx(p2.angle, 149) and p2.on == "C",
        "daten: P2 outer@149 steuert Bridge C (zweiter Baby-Parkplatz)")
    check(r8.gate.id == "T" and r8.gate.ring == "outer" and r8.gate.free == true
        and approx(r8.gate.angle, 355),
        "daten: Tor T outer@355 (frei, normale Center-Bridge)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[8])
    check(State.platePressed["P1"] == false and State.platePressed["P2"] == false,
        "start: beide Platten frei")
    check(State.switchStates["D1"] == "A", "start: D1 = A")
    check(State.elementStates["R"] == false, "start: Bridge R inaktiv (D1=A)")
    check(State.elementStates["S_D1"] == false, "start: S_D1 geschlossen (D1=A)")
    check(State.elementStates["S_FINAL_A"] == true, "start: S_FINAL_A offen (D1=A)")
    check(State.elementStates["S_FI"] == true, "start: S_FI offen (D1=A)")
    check(State.switchStates["D2"] == "B", "start: D2 = B")
    check(State.elementStates["S_D2"] == false, "start: S_D2 geschlossen (D2=B)")
    check(State.elementStates["F"] == true, "start: Bridge F aktiv (D2=B)")
    check(State.elementStates["A"] == false, "start: Bridge A INAKTIV (P1 frei)")
    check(State.elementStates["C"] == false, "start: Bridge C INAKTIV (P2 frei)")
    check(State.switchStates["O"] == "A", "start: O = A")
    check(State.elementStates["S_FINAL_O"] == false, "start: S_FINAL_O geschlossen (O=A)")
    check(State.elementStates["U"] == true, "start: Einmal-Brücke U FREI aktiv (Falle sichtbar)")
    check(State.elementStates["T"] == true, "start: Tor T frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 20),
        "start: Player outer@20")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 50),
        "start: Baby outer@50")
end

-- --- Anti-Bypass: A/C sind ohne Baby auf der Platte unbenutzbar -------------
do
    setup(Levels[8])
    check(State.elementStates["A"] == false, "a-inaktiv: Bridge A INAKTIV (Start)")
    check(State.elementStates["C"] == false, "a-inaktiv: Bridge C INAKTIV (Start)")
    -- Baby auf P1 parken (A aktiv), dann auf P2 schieben (A verschwindet, C da).
    local _, r1 = Room.movePlayer(101.83) -- 20 -> 121.83, Baby 50 -> 130 (P1)
    check(r1.blocked == false, "a-inaktiv: Parken auf P1 läuft")
    check(State.elementStates["A"] == true, "a-inaktiv: A aktiv (Baby auf P1)")
    check(State.elementStates["C"] == false, "a-inaktiv: C INAKTIV (Baby nicht auf P2)")
    local _, r2 = Room.movePlayer(19) -- 121.83 -> 140.83, Baby 130 -> 149 (P2)
    check(r2.blocked == false, "a-inaktiv: Schub zu P2 läuft")
    check(State.elementStates["A"] == false, "a-inaktiv: A INAKTIV (Baby nicht auf P1)")
    check(State.elementStates["C"] == true, "a-inaktiv: C aktiv (Baby auf P2)")
end

-- --- Anti-Bypass: Tor braucht das Baby (Solo am Tor = kein Exit) -------------
do
    setup(Levels[8])
    -- Player direkt an die Tor-Dockposition setzen, Baby bleibt auf dem
    -- Außenring: kein gemeinsamer Ausgang.
    State.player.ring = "outer"
    State.player.angle = 355
    check(Gate.isUsable(Levels[8].gate, "outer", 355) == false,
        "gate-baby: Tor ohne Baby auf dem Gate-Ring NICHT nutzbar")
    local res = Room.tryUseConnection()
    check(res.used == false, "gate-baby: tryUseConnection am Tor ohne Baby = kein Exit")
end

-- --- Phase 1: Baby auf P1 parken + Solo über A ------------------------------
do
    setup(Levels[8])
    local _, r = Room.movePlayer(101.83) -- 20 -> 121.83, Baby 50 -> 130 (EXAKT P1)
    check(r.blocked == false, "p1: Schub läuft")
    check(State.platePressed["P1"] == true, "p1: Baby EXAKT auf P1 -> gedrückt")
    check(State.elementStates["A"] == true, "p1: Bridge A MATERIALISIERT (P1 aktiv)")
    check(approx(State.player.angle, 121.83, 0.5), "p1: Player bei ~122")
    check(approx(State.baby.angle, 130, 1.0), "p1: Baby geparkt auf P1 (130)")
    -- Solo über A (outer@112): der Player steht bereits im A-Dock.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "A",
        "p1: Player benutzt Bridge A ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 112, 0.5),
        "p1: Player inner@112")
    check(State.platePressed["P1"] == true, "p1: Baby hält P1 -> A bleibt ausgefahren")
end

-- --- Phase 2: D1 CCW -> B + Solo über R ------------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@112
    -- D1@95 CCW -> B (Eintritt 102, Austritt 88), Sweep endet an R@60.
    local _, r1 = Room.movePlayer(-52) -- 112 -> 60
    check(r1.blocked == false, "p2: D1-CCW-Sweep läuft")
    check(State.switchStates["D1"] == "B", "p2: D1=B (Rückweg + O-Zugang)")
    check(State.elementStates["R"] == true, "p2: Bridge R materialisiert (D1=B)")
    check(State.elementStates["S_D1"] == true, "p2: S_D1 offen (erste O-Hälfte)")
    check(State.elementStates["S_FINAL_A"] == false, "p2: S_FINAL_A zu (finaler Weg gesperrt)")
    check(State.elementStates["S_FI"] == false, "p2: S_FI zu (finale Bridge F gesperrt)")
    -- Solo über R (inner@60) -> outer@60 (ANDERE Babyseite).
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "R", "p2: Solo-Transit R")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 60, 0.5),
        "p2: Player outer@60 (ANDERE Babyseite)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 130, 1.0),
        "p2: Baby weiterhin auf P1 (130)")
end

-- --- Phase 3: Baby P1 -> P2 (A verschwindet, C erscheint) ------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B, inner@60
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5) -- outer@60
    -- CW-Schub 130 -> 149 (P2): der Player ist CCW des Babys.
    local _, r1 = Room.movePlayer(80.83) -- 60 -> 140.83, Baby 130 -> 149 (P2)
    check(r1.blocked == false, "p3: Schub P1->P2 läuft")
    check(State.platePressed["P1"] == false, "p3: P1 FREI (Baby herunter)")
    check(State.elementStates["A"] == false, "p3: Bridge A VERSCHWUNDEN (bewusst geopfert)")
    check(State.platePressed["P2"] == true, "p3: Baby EXAKT auf P2 -> gedrückt")
    check(State.elementStates["C"] == true, "p3: Bridge C MATERIALISIERT (P2 aktiv)")
    check(approx(State.baby.angle, 149, 1.0), "p3: Baby geparkt auf P2 (149)")
    check(approx(State.player.angle, 140.83, 0.5), "p3: Player bei ~141 (C-Dock)")
end

-- --- Phase 4: Solo über C + D2 CW -> A -------------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    -- Solo über C (outer@132): Player@140.83 steht bereits im C-Dock.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "C", "p4: Solo-Transit C")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 132, 0.5),
        "p4: Player inner@132")
    -- D2@225 CW -> A: CW durch S_D1 (offen), O CW (no-op), D2 CW -> A.
    local _, r2 = Room.movePlayer(100) -- 132 -> 232
    check(r2.blocked == false, "p4: D2-CW-Sweep läuft")
    check(State.switchStates["D2"] == "A", "p4: D2=A (zweite O-Hälfte)")
    check(State.elementStates["S_D2"] == true, "p4: S_D2 offen")
    check(State.elementStates["F"] == false, "p4: Bridge F inaktiv (D2=A)")
    check(approx(State.player.angle, 232, 0.5), "p4: Player inner@232")
end

-- --- Phase 5: O korrekt (CCW) verbrauchen ----------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5) -- inner@132
    Room.movePlayer(100) -- D2=A, Player@232
    -- O@200 CCW -> B verbrauchen (Eintritt 207, Austritt 193).
    local _, r = Room.movePlayer(-39) -- 232 -> 193
    check(r.blocked == false, "p5: O-CCW-Sweep läuft")
    check(State.switchStates["O"] == "B", "p5: O korrekt CCW verbraucht (O=B)")
    check(State.consumedSwitches["O"] == true, "p5: O DAUERHAFT verbraucht (oneShot)")
    check(State.elementStates["S_FINAL_O"] == true, "p5: S_FINAL_O DAUERHAFT offen")
    check(approx(State.player.angle, 193, 0.5), "p5: Player inner@193")
end

-- --- Phase 6: D2 CCW -> B (O-Zugang schließt) ------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5)
    Room.movePlayer(100) -- D2=A, Player@232
    Room.movePlayer(-39) -- O verbraucht, Player@193
    -- CW über O (no-op) und D2 (no-op) an die CW-Seite, dann CCW -> B.
    local _, r = Room.movePlayer(47) -- 193 -> 240
    check(r.blocked == false, "p6: CW-Anlauf läuft")
    local _, r2 = Room.movePlayer(-22) -- 240 -> 218 (D2 CCW -> B)
    check(r2.blocked == false, "p6: D2-CCW-Sweep läuft")
    check(State.switchStates["D2"] == "B", "p6: D2=B (finale Bridge F)")
    check(State.elementStates["F"] == true, "p6: Bridge F MATERIALISIERT (D2=B)")
    check(State.elementStates["S_D2"] == false, "p6: S_D2 zu (O-Zugang wieder gesperrt)")
    check(State.switchStates["D1"] == "B", "p6: D1 bleibt B (R wird noch gebraucht)")
    check(State.elementStates["S_FI"] == false, "p6: S_FI zu (F bleibt bis D1=A gesperrt)")
end

-- --- Phase 7: Solo über R (zweiter Rückweg) --------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5)
    Room.movePlayer(100) -- D2=A
    Room.movePlayer(-39) -- O verbraucht
    Room.movePlayer(47) -- 240
    Room.movePlayer(-22) -- D2=B, Player@218
    -- CCW durch S_D1 (offen) zu R@60 und SOLO über R -> outer@60.
    local _, r = Room.movePlayer(-158) -- 218 -> 60
    check(r.blocked == false, "p7: CCW zu R läuft")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "R", "p7: Solo-Transit R (2.)")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 60, 0.5),
        "p7: Player outer@60 (RICHTIGE Seite von Baby/P2)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 149, 1.0),
        "p7: Baby weiterhin auf P2 (149)")
end

-- --- Phase 8: Baby zu U, GEMEINSAM nach innen ------------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5)
    Room.movePlayer(100) -- D2=A
    Room.movePlayer(-39) -- O verbraucht
    Room.movePlayer(47) -- 240
    Room.movePlayer(-22) -- D2=B
    Room.movePlayer(-158) -- inner@60
    Room.tryUseConnection() -- Solo R (2.)
    Bridge.update(0.5) -- outer@60
    -- CW-Schub 149 -> 325 (U): Player@60 ist CCW des Babys.
    local _, r1 = Room.movePlayer(256.83) -- 60 -> 316.83, Baby 149 -> 325 (U)
    check(r1.blocked == false, "p8: Schub zu U läuft")
    check(State.platePressed["P2"] == false, "p8: P2 FREI (Baby herunter)")
    check(State.elementStates["C"] == false, "p8: Bridge C VERSCHWUNDEN")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "p8: U GEMEINSAM benutzt (Baby voran)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 325, 0.5),
        "p8: Player inner@325 (U-Transit)")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 315, 0.5),
        "p8: Baby inner@315 (babyLandDir -1)")
    check(State.elementStates["U"] == false, "p8: U NACH dem Shared-Transit verbraucht")
end

-- --- Phase 9: D1 CW -> A (R opfern, finalen Weg öffnen) --------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5)
    Room.movePlayer(100) -- D2=A
    Room.movePlayer(-39) -- O verbraucht
    Room.movePlayer(47) -- 240
    Room.movePlayer(-22) -- D2=B
    Room.movePlayer(-158)
    Room.tryUseConnection() -- Solo R (2.)
    Bridge.update(0.5)
    Room.movePlayer(256.83) -- Baby zu U
    Room.tryUseConnection() -- Shared U
    Bridge.update(0.5) -- inner@325/Baby@315
    -- D1@95 CW -> A: von inner@325 CW durch 360/0 zu D1 (Baby@315 bleibt hinten).
    local _, r1 = Room.movePlayer(137) -- 325 -> 102 (D1 CW -> A)
    check(r1.blocked == false, "p9: D1-CW-Sweep läuft")
    check(State.switchStates["D1"] == "A", "p9: D1=A (FINALZUSTAND)")
    check(State.elementStates["R"] == false, "p9: Bridge R VERSCHWUNDEN (Rückweg geopfert)")
    check(State.elementStates["S_FINAL_A"] == true, "p9: S_FINAL_A offen (finaler Weg)")
    check(State.elementStates["S_FI"] == true, "p9: S_FI offen (finale Bridge F entsperrt)")
    check(State.switchStates["D2"] == "B", "p9: D2 bleibt B")
    check(approx(State.player.angle, 102, 0.5), "p9: Player inner@102")
end

-- --- Phase 10: Über F zum Tor, gemeinsamer Exit ----------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- Baby auf P2
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5)
    Room.movePlayer(100) -- D2=A
    Room.movePlayer(-39) -- O verbraucht
    Room.movePlayer(47) -- 240
    Room.movePlayer(-22) -- D2=B
    Room.movePlayer(-158)
    Room.tryUseConnection() -- Solo R (2.)
    Bridge.update(0.5)
    Room.movePlayer(256.83) -- Baby zu U
    Room.tryUseConnection() -- Shared U
    Bridge.update(0.5) -- inner@325/315
    Room.movePlayer(137) -- D1=A, Player@102
    -- CCW zum Baby (inner@315) und CCW-Schub 315 -> 295 (F-Dock).
    local _, r1 = Room.movePlayer(-158.83) -- 102 -> 303.17, Baby 315 -> 295 (F)
    check(r1.blocked == false, "p10: CCW-Schub zu F läuft")
    check(approx(State.baby.angle, 295, 1.0), "p10: Baby an F (inner@295)")
    local resF = Room.tryUseConnection()
    check(resF.used == true and resF.kind == "sharedBridge" and resF.id == "F", "p10: Shared-Transit F")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 295, 0.5),
        "p10: Player outer@295 (finale Verbindung)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 305, 0.5),
        "p10: Baby outer@305 (babyLandDir +1)")
    -- CW durch S_FINAL_O (O) und S_FINAL_A (D1) zum Tor T@355.
    local _, r2 = Room.movePlayer(51.83) -- 295 -> 346.83, Baby 305 -> 355 (Tor)
    check(r2.blocked == false, "p10: finaler Ringweg läuft")
    check(State.elementStates["S_FINAL_O"] == true, "p10: S_FINAL_O offen (O verbraucht)")
    check(State.elementStates["S_FINAL_A"] == true, "p10: S_FINAL_A offen (D1=A)")
    check(Gate.isUsable(Levels[8].gate, "outer", State.player.angle) == true,
        "p10: Tor nutzbar (FINALZUSTAND)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "p10: Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "p10: gemeinsamer Center-Transit abgeschlossen (Level 8 fertig)")
end

-- --- O-FALSCH: CW-Überquerung verbraucht O NICHT ---------------------------
do
    setup(Levels[8])
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5)
    Room.movePlayer(80.83) -- 60 -> 140.83, Baby 130 -> 149 (P2)
    Room.tryUseConnection() -- Solo C
    Bridge.update(0.5) -- inner@132
    -- CW-Sweep 132 -> 232 überquert O CW (wirkungslos) und D2 CW -> A.
    Room.movePlayer(100)
    check(State.switchStates["O"] == "A", "o-falsch: O bleibt A (CW wirkungslos)")
    check(State.consumedSwitches["O"] == nil, "o-falsch: O NICHT verbraucht (CW)")
    check(State.elementStates["S_FINAL_O"] == false, "o-falsch: S_FINAL_O bleibt zu")
    -- Erst die CCW-Überquerung verbraucht O.
    Room.movePlayer(-39) -- O CCW -> B
    check(State.switchStates["O"] == "B", "o-falsch: O=B nach CCW")
    check(State.consumedSwitches["O"] == true, "o-falsch: O verbraucht (CCW)")
end

-- --- ANTI-BYPASS: O ohne D1=B (S_D1 zu) unerreichbar -----------------------
do
    setup(Levels[8])
    -- D1=A: S_D1 ist zu -> der Korridor zu O ist versiegelt.
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@112 (D1 bleibt A)
    local _, r1 = Room.movePlayer(30) -- 112 -> CW, prallt an S_D1 (137)
    check(r1.blocked == true, "bypass-o: CW-Weg zu O PRALLT AN S_D1 (D1=A)")
    check(approx(State.player.angle, 137, 1.0), "bypass-o: Player an S_D1-Kante (137)")
    local _, r2 = Room.movePlayer(-30) -- 137 -> 107 (CCW, kein D1-Flip)
    check(r2.blocked == false, "bypass-o: CCW zurück läuft")
    check(State.switchStates["D1"] == "A", "bypass-o: D1 unverändert A")
end

-- --- ANTI-BYPASS: F ist bis D1=A durch S_FI gesperrt -----------------------
do
    setup(Levels[8])
    local bF = nil
    for _, b in ipairs(Levels[8].bridges) do
        if b.id == "F" then bF = b end
    end
    check(bF ~= nil, "bypass-f: Bridge F gefunden")
    check(State.elementStates["F"] == true, "bypass-f: F aktiv (D2=B)")
    -- Bei D1=A ist S_FI offen -> F benutzbar. Der eigentliche Anti-Bypass:
    -- nach D1=B ist S_FI zu -> F gesperrt (kein F-Bypass statt U).
    check(Bridge.isUsable(bF, 295) == true, "bypass-f: F bei D1=A benutzbar (S_FI offen)")
    -- Nach D1=B ist F gesperrt:
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    check(Bridge.isUsable(bF, 295) == false, "bypass-f: F gesperrt (S_FI zu, D1=B)")
end

-- --- DIE FALLE: U zu früh (gemeinsam) = Sackgasse --------------------------
do
    setup(Levels[8])
    -- U ist frei: Player schiebt das Baby CW bis zur geschlossenen S_FINAL_O
    -- (O nicht verbraucht) — das Baby steht dann in Shared-Reichweite von U.
    local _, r = Room.movePlayer(500) -- CW bis S_FINAL_O, Baby@~324
    check(r.blocked == true, "falle: CW-Schub PRALLT AN S_FINAL_O")
    check(approx(State.player.angle, 315.97, 1.5), "falle: Player am U-Dock (~316)")
    check(math.abs(Geometry.delta(State.baby.angle, 325)) < 15,
        "falle: Baby in Shared-Reichweite von U")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "falle: U wird zu früh GEMEINSAM benutzt")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 325, 0.5),
        "falle: Player inner@325")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 315, 0.5),
        "falle: Baby inner@315 (auch eingesperrt)")
    check(State.elementStates["U"] == false, "falle: U verbraucht — kein Rückweg")
    check(State.elementStates["S_FINAL_O"] == false, "falle: S_FINAL_O ZU (O wurde nie gesetzt)")
    check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == false,
        "falle: Tor NIE erreichbar (O fehlt, Tor ist auf dem Außenring)")
    -- Der eingeschlossene Player prallt in BEIDEN Richtungen an geschlossenen
    -- Blenden: CCW an S_D2 (268), CW an S_D1 (137).
    local _, r2 = Room.movePlayer(-100) -- 325 -> CCW, prallt an S_D2
    check(r2.blocked == true, "falle: CCW PRALLT AN geschlossener Blende")
    local _, r3 = Room.movePlayer(400) -- CW, prallt an S_D1
    check(r3.blocked == true, "falle: CW PRALLT AN geschlossener Blende")
end

-- --- DIE FALLE: U zu früh (solo) = Sackgasse -------------------------------
do
    setup(Levels[8])
    -- Player allein an U (Baby manuell weit entfernt): SOLO über U.
    State.player.ring = "outer"
    State.player.angle = 325
    State.baby.ring = "outer"
    State.baby.angle = 200
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "U",
        "falle-solo: U SOLO benutzt (Baby zu weit)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 325, 0.5),
        "falle-solo: Player ALLEIN inner@325")
    check(State.baby ~= nil and State.baby.ring == "outer",
        "falle-solo: Baby bleibt auf dem Außenring")
    check(State.elementStates["U"] == false, "falle-solo: U verbraucht")
    check(Gate.isUsable(Levels[8].gate, "inner", State.player.angle) == false,
        "falle-solo: Tor ohne Baby NIE erreichbar")
    -- Der alleinige Player prallt in BEIDEN Richtungen an geschlossenen Blenden.
    local _, r2 = Room.movePlayer(-100) -- CCW, prallt an S_D2
    check(r2.blocked == true, "falle-solo: CCW PRALLT AN geschlossener Blende")
    local _, r3 = Room.movePlayer(400) -- CW, prallt an S_D1
    check(r3.blocked == true, "falle-solo: CW PRALLT AN geschlossener Blende")
end

-- --- ANTI-BYPASS: Tor vor dem FINALZUSTAND gesperrt ------------------------
do
    setup(Levels[8])
    -- D1=B: S_FINAL_A [347,13] ist zu und deckt das Tor T@355 direkt ab.
    Room.movePlayer(101.83) -- Baby auf P1
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5)
    Room.movePlayer(-52) -- D1=B
    Room.tryUseConnection() -- Solo R
    Bridge.update(0.5) -- outer@60
    check(State.elementStates["S_FINAL_A"] == false, "bypass-final: S_FINAL_A zu (D1=B)")
    check(Gate.isUsable(Levels[8].gate, "outer", 355) == false,
        "bypass-final: Tor NICHT nutzbar (S_FINAL_A deckt T ab)")
    -- O nicht verbraucht: S_FINAL_O [327,353] blockiert den Zulauf zum Tor.
    local _, rb = Room.movePlayer(500) -- CW bis zur geschlossenen S_FINAL_O
    check(rb.blocked == true, "bypass-final: CW prallt an S_FINAL_O (O fehlt)")
    check(approx(State.player.angle, 315.97, 1.5),
        "bypass-final: Player am S_FINAL_O (O fehlt)")
end

-- --- Undo: genau EIN Snapshot pro Frame trotz Schalter + Push ----------------
do
    setup(Levels[8])
    Room.movePlayer(101.83) -- Push (Baby auf P1): genau 1 Undo-Eintrag
    check(Undo.count() == 1, "undo: Push auf P1 = genau 1 Snapshot")
    Room.movePlayer(-16.83) -- 121.83 -> 105, reine Bewegung: kein Snapshot
    check(Undo.count() == 1, "undo: reine Bewegung = kein Snapshot")
    Room.tryUseConnection() -- Solo A (keine oneShot-Brücke): kein Snapshot
    Bridge.update(0.5)
    check(Undo.count() == 1, "undo: Solo-Transit A = kein Snapshot")
    Room.movePlayer(-52) -- D1 CCW -> B (Schalter): genau 1 Snapshot
    check(Undo.count() == 2, "undo: D1-Wechsel = genau 1 Snapshot")
    Room.tryUseConnection() -- Solo R (R ist NICHT oneShot)
    Bridge.update(0.5)
    check(Undo.count() == 2, "undo: Solo-Transit R = kein Snapshot (R nicht oneShot)")
    Room.movePlayer(80.83) -- Push (Baby auf P2): genau 1 Snapshot
    check(Undo.count() == 3, "undo: Push auf P2 = genau 1 Snapshot")
    Room.tryUseConnection() -- Solo C (keine oneShot-Brücke): kein Snapshot
    Bridge.update(0.5)
    check(Undo.count() == 3, "undo: Solo-Transit C = kein Snapshot")
    Room.movePlayer(100) -- D2 CW -> A (Schalter): genau 1 Snapshot
    check(Undo.count() == 4, "undo: D2-Wechsel = genau 1 Snapshot")
end

TestReport.room8 = { pass = pass, fail = fail }
