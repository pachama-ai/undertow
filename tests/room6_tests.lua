-- Tests für Raum 6 „Die Schalterkette“ (SCHALTERKETTE als Kernmechanik).
--   EXAKT 2 aktive Ringbahnen 2/1 + Mittelpunkt, KEIN dritter Ring.
--   KEINE künstliche Startposition — ENTRY = Level-5-Ausgang (Player äußerer
--   Ring @180, Baby @190: Baby 10° CW vor dem Player, PUSH_DIRECTION = CW).
--
--   SCHALTERKETTE: P -> D1 -> O -> U. Jeder Schritt macht erst den nächsten
--   erreichbar; kein Schalter öffnet direkt den Ausgang.
--   ÄUSSERER RING: P (Druckplatte @240, Baby wird hier geparkt), S1 (@120,
--     von P, öffnet die SOLO-Bridge A@120), A (outer<->inner), B (@40,
--     RÜCK-Bridge auf die andere Babyseite), S4 (@300, von O gesteuert —
--     versperrt den P->U-Weg, bis die Kette gelöst ist), U (EINMAL-BRÜCKE
--     @340, freie oneShot — der gemeinsame Endweg, babyLandDir=+1).
--   INNERER RING: A-Landeplatz @120, D1 (Doppelschalter @170; CW -> A öffnet
--     S2@220), S2 (@220, bewacht O), O (EINMALSCHALTER @270; CW -> A verbraucht,
--     öffnet S3@320 + Tor T@10), S3 (@320, öffnet den Weg zu B@40), B (@40),
--     U-Landung @340, T (Tor @10, O-gesteuert — harter Ketten-Abschluss),
--     F1 (FESTE Blende @90 — versperrt den CCW-Schleichweg).
--
-- ABLAUF (Soll-Lösung): Baby CW auf P parken -> S1 öffnet -> Player SOLO über
-- A auf den inneren Ring (inner@120) -> D1 CW überqueren (A, S2 offen) -> S2
-- passieren -> O CW überqueren (verbraucht, S3+T+S4 dauerhaft offen) -> S3
-- passieren -> SOLO über B zurück (outer@40, andere Babyseite) -> Baby CW von
-- P DURCH S4 zur EINMAL-BRÜCKE U@340 schieben -> U GEMEINSAM (inner@340,
-- Baby@350, U verschwindet) -> CW zum Tor T@10 -> gemeinsamer Center-Transit
-- -> EXIT. Wer vor der Kette versucht, das Baby CW über S4 hinaus zu
-- schieben, wird an S4 gestoppt (U bleibt unerreichbar).
-- Am Ende wird das Ergebnis in TestReport.room6 gesammelt.

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

-- --- Raum 6 Daten ----------------------------------------------------------
do
    local r6 = Levels[6]
    check(r6.name == "Die Schalterkette", "daten: Name 'Die Schalterkette'")
    check(r6.rings.outer == 2 and r6.rings.inner == 1 and r6.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (2/1) — kein dritter Ring")
    check(r6.start.ring == "outer" and approx(r6.start.angle, 180),
        "daten: ENTRY = Level-5-Ausgang (Player outer@180)")
    check(r6.baby ~= nil and r6.baby.start.ring == "outer" and approx(r6.baby.start.angle, 190),
        "daten: Baby outer@190 (CW vor dem Player)")
    check(#r6.switches == 2, "daten: genau 2 Schalter (D1 + Einmalschalter O)")
    local d1, o
    for _, sw in ipairs(r6.switches) do
        if sw.id == "D1" then d1 = sw end
        if sw.id == "O" then o = sw end
    end
    check(d1 ~= nil and d1.ring == "inner" and approx(d1.angle, 170) and d1.state == "B",
        "daten: D1 inner@170 (B) — richtige Richtung CW -> A öffnet S2")
    check(d1.onA == "S2" and type(d1.onB) == "table" and #d1.onB == 0,
        "daten: D1 öffnet S2 (A), nichts in B")
    check(o ~= nil and o.ring == "inner" and approx(o.angle, 270) and o.state == "B"
        and o.oneShot == true, "daten: O Einmalschalter inner@270 (B, oneShot)")
    check(type(o.onA) == "table" and #o.onA == 3 and o.onA[1] == "S3"
        and o.onA[2] == "T" and o.onA[3] == "S4",
        "daten: O öffnet S3 + Tor T + Blende S4 in Zustand A")
    check(#r6.shutters == 5, "daten: genau 5 Blenden (S1..S3 + S4 + F1)")
    local byId = {}
    for _, sh in ipairs(r6.shutters) do byId[sh.id] = sh end
    check(byId["S1"] ~= nil and byId["S1"].ring == "outer" and approx(byId["S1"].angle, 120),
        "daten: S1 outer@120 (von P, Zugang zu Bridge A)")
    check(byId["S2"] ~= nil and byId["S2"].ring == "inner" and approx(byId["S2"].angle, 220),
        "daten: S2 inner@220 (von D1, bewacht O)")
    check(byId["S3"] ~= nil and byId["S3"].ring == "inner" and approx(byId["S3"].angle, 320),
        "daten: S3 inner@320 (von O, öffnet den Weg zu B)")
    check(byId["S4"] ~= nil and byId["S4"].ring == "outer" and approx(byId["S4"].angle, 300),
        "daten: S4 outer@300 (von O — sperrt den P->U-Weg bis zur Kette)")
    check(byId["F1"] ~= nil and byId["F1"].ring == "inner" and approx(byId["F1"].angle, 90)
        and byId["F1"].fixedClosed == true,
        "daten: F1 inner@90 (FESTE Blende — versperrt den Schleichweg)")
    check(#r6.plates == 1, "daten: genau 1 Druckplatte")
    check(r6.plates[1].id == "P" and r6.plates[1].ring == "outer"
        and approx(r6.plates[1].angle, 240) and r6.plates[1].on == "S1",
        "daten: P outer@240 steuert S1 (Baby-Parkplatz)")
    check(#r6.bridges == 3, "daten: genau 3 Brücken (A + B + EINMAL-BRÜCKE U)")
    local bA, bB, bU
    for _, b in ipairs(r6.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "B" then bB = b end
        if b.id == "U" then bU = b end
    end
    check(bA ~= nil and bA.free and approx(bA.angle, 120), "daten: Bridge A@120 (Solo, frei)")
    check(bB ~= nil and bB.free and approx(bB.angle, 40), "daten: Bridge B@40 (Rückweg, frei)")
    check(bU ~= nil and bU.free and bU.oneShot == true and approx(bU.angle, 340)
        and bU.babyLandDir == 1,
        "daten: EINMAL-BRÜCKE U@340 (frei, oneShot, babyLandDir=+1)")
    check(r6.gate.id == "T" and r6.gate.free == false and r6.gate.ring == "inner"
        and approx(r6.gate.angle, 10),
        "daten: Tor T inner@10 (von O gesteuert — harter Ketten-Abschluss)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[6])
    check(State.platePressed["P"] == false, "start: P frei")
    check(State.elementStates["S1"] == false, "start: S1 geschlossen (P frei)")
    check(State.switchStates["D1"] == "B", "start: D1 = B")
    check(State.elementStates["S2"] == false, "start: S2 geschlossen (D1=B)")
    check(State.switchStates["O"] == "B", "start: O = B")
    check(State.elementStates["S3"] == false, "start: S3 geschlossen (O=B)")
    check(State.elementStates["S4"] == false, "start: S4 geschlossen (O=B)")
    check(State.elementStates["T"] == false, "start: Tor T geschlossen (O=B)")
    check(State.elementStates["U"] == true, "start: U frei aktiv")
    check(State.elementStates["A"] == true and State.elementStates["B"] == true,
        "start: A + B frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 180),
        "start: Player outer@180")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 190),
        "start: Baby outer@190")
end

-- --- Baby parken auf P -> S1 offen -----------------------------------------
do
    setup(Levels[6])
    local _, r = Room.movePlayer(51.83) -- Player 180 -> 231.83, Baby 190 -> 240 (EXAKT P@240)
    check(r.blocked == false, "parken: Schub läuft")
    check(State.platePressed["P"] == true, "parken: Baby EXAKT auf P -> gedrückt")
    check(State.elementStates["S1"] == true, "parken: S1 offen (P aktiv)")
    check(approx(State.player.angle, 231.83, 0.5), "parken: Player bei ~232")
    check(approx(State.baby.angle, 240, 1.0), "parken: Baby geparkt auf P (240)")
end

-- --- SOLO-Wechsel über A auf den inneren Ring ------------------------------
do
    setup(Levels[6])
    Room.movePlayer(51.83) -- Baby EXAKT auf P, S1 offen
    local _, r = Room.movePlayer(-111.83) -- Player 231.83 -> 120 (durch S1, zu Bridge A)
    check(r.blocked == false, "solo: CCW zu Bridge A läuft (S1 offen)")
    check(approx(State.player.angle, 120, 0.5), "solo: Player an Bridge A (120)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "A",
        "solo: Player benutzt Bridge A ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 120, 0.5),
        "solo: Player inner@120")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 240, 1.0),
        "solo: Baby bleibt EXAKT auf P (getrennt)")
end

-- --- SCHALTERKETTE inner: D1 -> S2 -> O -> S3 -> B -------------------------
do
    setup(Levels[6])
    Room.movePlayer(51.83) -- Baby EXAKT auf P
    Room.movePlayer(-111.83) -- 231.83 -> 120
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- Player inner@120
    -- D1 CW überqueren (richtige Richtung) -> A -> S2 offen.
    local _, r1 = Room.movePlayer(57) -- 120 -> 177 (D1 CW-Eintritt 163, Austritt 177)
    check(r1.blocked == false, "kette1: CW zu D1 läuft")
    check(State.switchStates["D1"] == "A", "kette1: D1=A (richtige Richtung)")
    check(State.elementStates["S2"] == true, "kette1: S2 offen (D1=A)")
    -- S2 passieren + O CW überqueren -> verbraucht, S3 + Tor T dauerhaft offen.
    local _, r2 = Room.movePlayer(100) -- 177 -> 277 (S2 offen, O CW 263->277)
    check(r2.blocked == false, "kette2: S2 + O (CW) laufen")
    check(State.switchStates["O"] == "A", "kette2: O=A (richtige Richtung)")
    check(State.consumedSwitches["O"] == true, "kette2: O verbraucht (oneShot)")
    check(State.elementStates["S3"] == true, "kette2: S3 dauerhaft offen (vorbereitet)")
    check(State.elementStates["S4"] == true, "kette2: S4 dauerhaft offen (vorbereitet)")
    check(State.elementStates["T"] == true, "kette2: Tor T dauerhaft offen (vorbereitet)")
    -- S3 passieren + SOLO über B zurück auf den Außenring (andere Babyseite).
    local _, r3 = Room.movePlayer(135) -- 277 -> 52 (S3 offen, Wrap um 0, B-Dock)
    check(r3.blocked == false, "kette3: S3 + Weg zu B läuft")
    check(approx(State.player.angle, 52, 0.5), "kette3: Player an Bridge B (52)")
    local resB = Room.tryUseConnection()
    check(resB.used == true and resB.kind == "bridge" and resB.id == "B",
        "kette3: Player benutzt Bridge B ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 40, 0.5),
        "kette3: Player outer@40 (ANDERE Babyseite)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 240, 1.0),
        "kette3: Baby wartet noch EXAKT auf P")
end

-- --- Baby abholen + GEMEINSAM über die EINMAL-BRÜCKE U ---------------------
do
    setup(Levels[6])
    Room.movePlayer(51.83) -- Baby EXAKT auf P
    Room.movePlayer(-111.83) -- 231.83 -> 120
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- Player inner@120
    Room.movePlayer(57) -- D1=A, S2 offen
    Room.movePlayer(100) -- O=A verbraucht, S3+T offen
    Room.movePlayer(135) -- 277 -> 52 (S3 offen)
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5) -- Player outer@40
    -- Baby CW von P (EXAKT 240) zur EINMAL-BRÜCKE U@340 schieben.
    local _, r = Room.movePlayer(291.83) -- Player 40 -> 331.83, Baby 240 -> 340 (U-Dock)
    check(r.blocked == false, "u: CW-Schub zu U läuft")
    check(approx(State.player.angle, 331.83, 0.5), "u: Player an U (~332)")
    check(approx(State.baby.angle, 340, 1.0), "u: Baby an U (340)")
    check(State.platePressed["P"] == false, "u: P frei (Baby herunter)")
    check(State.elementStates["S1"] == false, "u: S1 geschlossen (egal)")
    -- U GEMEINSAM benutzen -> verschwindet erst nach vollständigem Transit.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "U",
        "u: U GEMEINSAM benutzt")
    Bridge.update(0.5)
    check(State.consumedBridges["U"] == true, "u: U verbraucht (Point of No Return)")
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "u: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 350, 0.5),
        "u: Baby inner@350 (CW vor dem Player, babyLandDir=+1)")
end

-- --- Finaler Weg: CW zum Tor T@10, gemeinsamer Center-Transit --------------
do
    setup(Levels[6])
    Room.movePlayer(51.83)
    Room.movePlayer(-111.83)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(57)
    Room.movePlayer(100)
    Room.movePlayer(135)
    Room.tryUseConnection()
    Bridge.update(0.5)
    Room.movePlayer(291.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- Player inner@340, Baby@350, U verbraucht
    check(State.elementStates["T"] == true, "final: Tor T offen (vorbereitet)")
    local _, r = Room.movePlayer(22) -- Player 340 -> 2, Baby 350 -> ~10 (Tor)
    check(r.blocked == false, "final: CW-Schub zum Tor läuft")
    check(approx(State.player.angle, 2, 0.5), "final: Player am Tor (2)")
    check(Gate.isUsable(Levels[6].gate, "inner", State.player.angle) == true,
        "final: Tor nutzbar (Player UND Baby)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "final: Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "final: gemeinsamer Center-Transit abgeschlossen (Level 6 fertig)")
    check(State.player.ring == "inner" and approx(State.player.angle, 10, 0.5),
        "final: Player am Gate-Ring @10 (Ziel = Mittelpunkt)")
    check(approx(State.baby.angle, 20, 0.5),
        "final: Baby behält EIGENEN Winkel @20 (VOR dem Player)")
end

-- --- D1 falscher Zustand (B): S2 geschlossen -> O unerreichbar -------------
do
    setup(Levels[6])
    -- D1=B (Start, falscher Zustand): S2 bleibt geschlossen.
    State.player.ring = "inner"
    State.player.angle = 190 -- zwischen D1@170 und S2@220 (CCW von S2)
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.elementStates["S2"] == false, "d1-falsch: S2 geschlossen (D1=B)")
    local _, r = Room.movePlayer(17) -- 190 -> 207 (S2 CW-Eintritt, geschlossen)
    check(r.blocked == true, "d1-falsch: CW-Anlauf prallt an S2 ab")
    check(approx(State.player.angle, 207, 1.5), "d1-falsch: Player stoppt an S2 (207)")
    check(State.elementStates["S3"] == false, "d1-falsch: S3 geschlossen (O unerreichbar)")
end

-- --- F1: CCW-Schleichweg vom A-Landeplatz ist versperrt --------------------
do
    setup(Levels[6])
    State.player.ring = "inner"
    State.player.angle = 120 -- A-Landeplatz
    State.deriveElements()
    Room.syncPhysicalShutters()
    local _, r = Room.movePlayer(-17) -- 120 -> 103 (F1 CCW-Eintritt, fest)
    check(r.blocked == true, "f1: CCW-Schleichweg blockiert (F1 fest)")
    check(approx(State.player.angle, 103, 1.5), "f1: Player stoppt an F1 (103)")
end

-- --- Frühe U-Nutzung: SOLO-Verbrauch nach der Kette = Sackgasse ------------
-- U ist nur DURCH die Kette erreichbar (D1/S2/O liegen linear davor). Wer U
-- nach der Kette ALLEIN benutzt (Baby ist nicht am Dock), verbraucht die
-- Einmal-Brücke und strandet das Baby auf dem Außenring -> Sackgasse, Undo.
do
    setup(Levels[6])
    Room.movePlayer(51.83)
    Room.movePlayer(-111.83)
    Room.tryUseConnection()
    Bridge.update(0.5) -- Player inner@120, Baby EXAKT auf P, Kette noch offen
    Room.movePlayer(57) -- D1=A, S2 offen
    Room.movePlayer(100) -- O=A verbraucht, S3+T offen
    local _, r = Room.movePlayer(63) -- 277 -> 340 (S3 offen, an U)
    check(r.blocked == false, "frueh-u: U nach der Kette erreichbar")
    check(approx(State.player.angle, 340, 0.5), "frueh-u: Player an U (340)")
    -- SOLO-Verbrauch von U (Baby ist nicht am Dock) -> Sackgasse.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "U",
        "frueh-u: Player benutzt U ALLEIN (falsch)")
    Bridge.update(0.5)
    check(State.consumedBridges["U"] == true, "frueh-u: U verbraucht")
    check(State.player.ring == "outer" and approx(State.player.angle, 340, 0.5),
        "frueh-u: Player outer@340")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 240, 1.0),
        "frueh-u: Baby auf P zurückgelassen (Sackgasse)")
    -- UNDO stellt U wieder her.
    check(Undo.count() >= 1, "frueh-u: U-Transit erzeugt Undo-Snapshot")
    local restored = Undo.undo()
    check(restored == true, "frueh-u: Undo stellt den Zustand wieder her")
    check(State.consumedBridges["U"] == nil, "frueh-u: U wieder aktiv (nicht verbraucht)")
end

-- --- S4: Der P->U-Weg ist VOR der Kette gesperrt --------------------------
-- S4 (outer@300, von O gesteuert) verhindert, dass das Baby vor der
-- Schalterkette CW über den Parkplatz hinaus zur EINMAL-BRÜCKE U@340 geschoben
-- werden kann — U ist erst NACH O erreichbar (kein verwirrendes frühes
-- Erreichen mit dem Baby).
do
    setup(Levels[6])
    Room.movePlayer(51.83) -- Player 231.83, Baby 240 (EXAKT P)
    check(State.elementStates["S4"] == false, "s4: S4 geschlossen (O noch B)")
    local _, r = Room.movePlayer(60) -- Baby CW Richtung U: wird an S4 gestoppt
    check(r.blocked == true, "s4: früher CW-Schub prallt an S4 ab")
    check(State.baby.angle < 290, "s4: Baby blockiert vor S4 (<290)")
    check(approx(State.player.angle, 276, 3),
        "s4: Player bleibt im Kontaktabstand hinter dem Baby (~276)")
    local res = Room.tryUseConnection()
    check(res.used == false, "s4: U vor der Kette nicht nutzbar")
end

-- --- LEVEL-7-ÜBERGABE: Exit @10, Ring 1 -> Level-7-Außenring ---------------
do
    check(RoomTransition.ringNameForRoom(Levels[6].rings.inner, Levels[7]) == "outer",
        "uebergabe: Level-6-inner (1) -> Level-7-outer (1)")
    check(Levels[6].rings.middle == nil, "uebergabe: kein dritter Ring in Level 6")
    check(Levels[6].gate.angle == 10, "uebergabe: Exit-Winkel @10 (beide Figuren)")
end

TestReport.room6 = { pass = pass, fail = fail }
