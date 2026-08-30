-- Tests für Raum 7 „Die Brücke hinter dir“ (INAKTIVE / AKTIVIERBARE BRÜCKEN).
--   EXAKT 2 aktive Ringbahnen 1/0 + Mittelpunkt, KEIN dritter Ring.
--
--   NEUE MECHANIK: Brücken starten INAKTIV (nur Punktreihe) und materialisieren
--   sich, wenn ihr Herr aktiv ist; deaktivieren läuft rückwärts.
--     - Bridge A (outer<->inner @60): von der Druckplatte P (outer@200)
--       gesteuert — ausgefahren NUR solange das Baby P hält. Einziger Weg nach
--       innen, nur SOLO benutzbar.
--     - Bridge B (outer<->inner @300): vom Doppelschalter D (inner@280)
--       gesteuert — aktiv in Zustand A, eingefahren in Zustand B.
--     - Shutter S (inner@255): von D gesteuert — geschlossen in Zustand A,
--       offen in Zustand B (Ausgangsweg zum Tor).
--     - Tor T (inner@225, frei): normale Center-Bridge, nur gemeinsam mit Baby.
--
--   ABLAUF (Soll-Lösung): Baby auf P -> A erscheint -> A SOLO -> D CW auf A
--   (B erscheint, S zu) -> B SOLO zurück (andere Babyseite) -> Baby von P holen
--   (A verschwindet) -> Baby zu B -> B SHARED zurück (inner@300, Baby@310) ->
--   D CCW auf B (B verschwindet hinter ihnen, S öffnet) -> Player kehrt CCW
--   durch die offene S ohne D-Überquerung zum Baby zurück -> schiebt es CCW
--   durch S zum Tor -> Center-Transit -> LEVELENDE. Nach Zustand B wird D
--   nicht wieder überquert.
-- Am Ende wird das Ergebnis in TestReport.room7 gesammelt.

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

-- --- Raum 7 Daten ----------------------------------------------------------
do
    local r7 = Levels[7]
    check(r7.name == "Die Brücke hinter dir", "daten: Name 'Die Brücke hinter dir'")
    check(r7.rings.outer == 1 and r7.rings.inner == 0 and r7.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (1/0) — kein dritter Ring")
    check(r7.start.ring == "outer" and approx(r7.start.angle, 20),
        "daten: ENTRY = Level-6-Ausgang (Player outer@20)")
    check(r7.baby ~= nil and r7.baby.start.ring == "outer" and approx(r7.baby.start.angle, 50),
        "daten: Baby outer@50 (CW vor dem Player)")
    check(#r7.switches == 1, "daten: genau 1 Schalter (Doppelschalter D)")
    local d = r7.switches[1]
    check(d.id == "D" and d.ring == "inner" and approx(d.angle, 280) and d.state == "B",
        "daten: D inner@280 (Start B)")
    check(d.onA == "B" and d.onB == "S",
        "daten: D — Zustand A aktiviert Bridge B, Zustand B öffnet Shutter S")
    check(#r7.shutters == 1, "daten: genau 1 Blende (finaler Shutter S)")
    check(r7.shutters[1].id == "S" and r7.shutters[1].ring == "inner"
        and approx(r7.shutters[1].angle, 255),
        "daten: S inner@255 (von D, öffnet in Zustand B den Ausgangsweg)")
    check(#r7.bridges == 2, "daten: genau 2 Brücken (A + B, beide INAKTIVIERBAR)")
    local bA, bB
    for _, b in ipairs(r7.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "B" then bB = b end
    end
    check(bA ~= nil and bA.free == false and approx(bA.angle, 60),
        "daten: Bridge A@60 (free=false — von Platte P gesteuert)")
    check(bB ~= nil and bB.free == false and approx(bB.angle, 300),
        "daten: Bridge B@300 (free=false — von D gesteuert)")
    check(#r7.plates == 1, "daten: genau 1 Druckplatte")
    check(r7.plates[1].id == "P" and r7.plates[1].ring == "outer"
        and approx(r7.plates[1].angle, 200) and r7.plates[1].on == "A",
        "daten: P outer@200 steuert Bridge A (Baby-Parkplatz)")
    check(r7.gate.id == "T" and r7.gate.ring == "inner" and r7.gate.free == true
        and approx(r7.gate.angle, 225),
        "daten: Tor T inner@225 (frei, normale Center-Bridge)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[7])
    check(State.platePressed["P"] == false, "start: P frei (Baby nicht drauf)")
    check(State.elementStates["A"] == false, "start: Bridge A INAKTIV (nur Punkte)")
    check(State.switchStates["D"] == "B", "start: D = B")
    check(State.elementStates["B"] == false, "start: Bridge B INAKTIV (D=B)")
    check(State.elementStates["S"] == true, "start: Shutter S offen (D=B)")
    check(State.elementStates["T"] == true, "start: Tor T frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 20),
        "start: Player outer@20")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 50),
        "start: Baby outer@50")
end

-- --- Anti-Bypass: A und B sind ohne Aktivierung unbenutzbar -----------------
do
    setup(Levels[7])
    -- Bridge A INAKTIV: Player kann an A@60 (outer) nichts benutzen.
    local _, r1 = Room.movePlayer(40) -- Player 20 -> 60 (A-Dock, A inaktiv)
    check(r1.blocked == false, "a-inaktiv: Bewegung zu A läuft (Brücken blockieren nicht)")
    check(approx(State.player.angle, 60, 0.5), "a-inaktiv: Player an A (60)")
    local resA = Room.tryUseConnection()
    check(resA.used == false, "a-inaktiv: A VOR dem Baby-Parken nicht nutzbar")
    -- Bridge B INAKTIV (D=B): Player erreicht B@300 (outer) und kann nichts tun.
    local _, r2 = Room.movePlayer(240) -- 60 -> 300 (B-Dock, B inaktiv)
    check(r2.blocked == false, "b-inaktiv: Bewegung zu B läuft")
    local resB = Room.tryUseConnection()
    check(resB.used == false, "b-inaktiv: B VOR D-Zustand-A nicht nutzbar")
end

-- --- Baby parken auf P -> Bridge A materialisiert sich ----------------------
do
    setup(Levels[7])
    local _, r = Room.movePlayer(171.83) -- Player 20 -> 191.83, Baby 50 -> 200 (EXAKT P@200)
    check(r.blocked == false, "parken: Schub läuft")
    check(State.platePressed["P"] == true, "parken: Baby EXAKT auf P -> gedrückt")
    check(State.elementStates["A"] == true, "parken: Bridge A MATERIALISIERT (P aktiv)")
    check(approx(State.player.angle, 191.83, 0.5), "parken: Player bei ~192")
    check(approx(State.baby.angle, 200, 1.0), "parken: Baby geparkt auf P (200)")
end

-- --- SOLO über Bridge A auf den inneren Ring (Baby bleibt auf P) ------------
do
    setup(Levels[7])
    Room.movePlayer(171.83) -- Baby EXAKT auf P, A aktiv
    local _, r = Room.movePlayer(-131.83) -- Player 191.83 -> 60 (A-Dock)
    check(r.blocked == false, "solo-a: CCW zu Bridge A läuft")
    check(approx(State.player.angle, 60, 0.5), "solo-a: Player an A (60)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "A",
        "solo-a: Player benutzt Bridge A ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 60, 0.5),
        "solo-a: Player inner@60")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 200, 1.0),
        "solo-a: Baby bleibt EXAKT auf P (getrennt)")
    check(State.platePressed["P"] == true and State.elementStates["A"] == true,
        "solo-a: Baby hält P -> A bleibt ausgefahren")
end

-- --- Anti-Bypass: Tor braucht das Baby (Solo am Tor = Sackgasse) ------------
do
    setup(Levels[7])
    Room.movePlayer(171.83) -- Baby EXAKT auf P
    Room.movePlayer(-131.83) -- Player outer@60
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- Player inner@60, Baby auf P, D=B (S offen)
    local _, r = Room.movePlayer(-195) -- 60 -> 225 (Tor-Dock CCW, D noch B -> S offen)
    check(r.blocked == false, "solo-gate: CCW zum Tor läuft (S ist offen)")
    check(approx(State.player.angle, 225, 0.5), "solo-gate: Player am Tor (225)")
    local res = Room.tryUseConnection()
    check(res.used == false, "solo-gate: Tor ohne Baby NICHT nutzbar (kein Bypass)")
end

-- --- D CW überqueren (Zustand A): B erscheint, S schließt -------------------
do
    setup(Levels[7])
    Room.movePlayer(171.83) -- Baby EXAKT auf P
    Room.movePlayer(-131.83) -- Player outer@60
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- Player inner@60
    local _, r = Room.movePlayer(240) -- 60 -> 300 (über S offen + D CW, danach zu B)
    check(r.blocked == false, "kette-a: CW zu B läuft (über D)")
    check(State.switchStates["D"] == "A", "kette-a: D=A (CW-Überquerung)")
    check(State.elementStates["B"] == true, "kette-a: Bridge B MATERIALISIERT (D=A)")
    check(State.elementStates["S"] == false, "kette-a: Shutter S GESCHLOSSEN (D=A)")
    check(approx(State.player.angle, 300, 0.5), "kette-a: Player an B (inner@300)")
    -- SOLO über B zurück auf den Außenring (andere Babyseite).
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge" and res.id == "B",
        "kette-a: Player benutzt Bridge B ALLEIN")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 300, 0.5),
        "kette-a: Player outer@300 (ANDERE Babyseite)")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 200, 1.0),
        "kette-a: Baby wartet noch EXAKT auf P")
end

-- --- Baby holen: A verschwindet, Baby zu B, B SHARED zurück -----------------
do
    setup(Levels[7])
    Room.movePlayer(171.83) -- Baby EXAKT auf P (A aktiv)
    Room.movePlayer(-131.83) -- outer@60
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@60
    Room.movePlayer(240) -- D=A (B aktiv, S zu), inner@300
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5) -- Player outer@300, Baby EXAKT auf P
    -- Player geht CW um den Ring herum auf die CCW-Seite des Babys.
    local _, r1 = Room.movePlayer(251.83) -- 300 -> 191.83 (Kontakt hinter Baby, kein Schub)
    check(r1.blocked == false, "abholen: Umrundung läuft")
    check(approx(State.player.angle, 191.83, 1.0), "abholen: Player hinter Baby (~192)")
    check(approx(State.baby.angle, 200, 1.0), "abholen: Baby noch EXAKT auf P")
    -- Baby CW zu B@300 (outer) schieben -> verlässt P -> A verschwindet.
    local _, r2 = Room.movePlayer(103) -- 191.83 -> 294.83, Baby 200 -> 303
    check(r2.blocked == false, "abholen: CW-Schub zu B läuft")
    check(State.platePressed["P"] == false, "abholen: P frei (Baby herunter)")
    check(State.elementStates["A"] == false, "abholen: Bridge A VERSCHWUNDEN (P frei)")
    check(approx(State.baby.angle, 303, 1.5), "abholen: Baby an B (outer@~303)")
    check(approx(State.player.angle, 294.83, 1.0), "abholen: Player hinter Baby (~295)")
    check(State.elementStates["B"] == true, "abholen: B weiterhin aktiv (D=A)")
    -- B GEMEINSAM benutzen -> Player + Baby auf den inneren Ring.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge" and res.id == "B",
        "abholen: B GEMEINSAM benutzt")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 300, 0.5),
        "abholen: Player inner@300")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 310, 0.5),
        "abholen: Baby inner@310 (CW vor dem Player)")
    check(State.switchStates["D"] == "A", "abholen: D noch Zustand A")
end

-- --- D CCW überqueren (Zustand B): B verschwindet hinter ihnen, S öffnet ----
do
    setup(Levels[7])
    Room.movePlayer(171.83)
    Room.movePlayer(-131.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@60
    Room.movePlayer(240)
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5) -- outer@300
    Room.movePlayer(251.83) -- hinter Baby
    Room.movePlayer(103) -- Baby zu B (outer)
    Room.tryUseConnection() -- Shared B
    Bridge.update(0.5) -- Player inner@300, Baby@310
    -- Player überquert D CCW (287..273) -> Zustand B.
    local _, r = Room.movePlayer(-30) -- 300 -> 270 (über D CCW)
    check(r.blocked == false, "d-b: CCW zu D läuft")
    check(State.switchStates["D"] == "B", "d-b: D=B (CCW-Überquerung)")
    check(State.elementStates["B"] == false, "d-b: Bridge B VERSCHWUNDEN (hinter ihnen)")
    check(State.elementStates["S"] == true, "d-b: Shutter S GEÖFFNET (D=B)")
    check(approx(State.player.angle, 270, 0.5), "d-b: Player nach D (270)")
    check(State.baby ~= nil and State.baby.ring == "inner" and approx(State.baby.angle, 310, 0.5),
        "d-b: Baby wartet bei inner@310")
end

-- --- Rückkehr ohne D-Überquerung + Schub durch S zum Tor --------------------
do
    setup(Levels[7])
    Room.movePlayer(171.83)
    Room.movePlayer(-131.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@60
    Room.movePlayer(240)
    Room.tryUseConnection() -- Solo B
    Bridge.update(0.5) -- outer@300
    Room.movePlayer(251.83)
    Room.movePlayer(103) -- Baby zu B (outer)
    Room.tryUseConnection() -- Shared B
    Bridge.update(0.5) -- inner@300 / Baby@310
    Room.movePlayer(-30) -- D=B (B weg, S offen), Player@270
    -- Rückkehr CCW (langer Weg durch die offene S, am Tor vorbei) — KEINE
    -- erneute D-Überquerung (die CW-Route würde D treffen).
    local _, r1 = Room.movePlayer(-311.83) -- 270 -> 318.17 (Kontakt hinter Baby@310)
    check(r1.blocked == false, "rueckkehr: langer CCW-Weg läuft (S offen)")
    check(State.switchStates["D"] == "B", "rueckkehr: D wurde NICHT erneut überquert")
    check(approx(State.player.angle, 318.17, 1.0), "rueckkehr: Player hinter Baby (~318)")
    check(approx(State.baby.angle, 310, 1.0), "rueckkehr: Baby unversehrt bei 310")
    -- Schub CCW durch den geöffneten S-Bereich zum Tor T@225.
    local _, r2 = Room.movePlayer(-85) -- 318.17 -> 233.17, Baby 310 -> 225
    check(r2.blocked == false, "rueckkehr: CCW-Schub durch S zum Tor läuft")
    check(approx(State.baby.angle, 225, 1.0), "rueckkehr: Baby am Tor (225)")
    check(approx(State.player.angle, 233.17, 1.0), "rueckkehr: Player am Tor (~233)")
    check(Gate.isUsable(Levels[7].gate, "inner", State.player.angle) == true,
        "rueckkehr: Tor nutzbar (Player UND Baby)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "rueckkehr: Kernbrücken-Transit")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "rueckkehr: gemeinsamer Center-Transit abgeschlossen (Level 7 fertig)")
    check(State.player.ring == "inner" and approx(State.player.angle, 225, 0.5),
        "rueckkehr: Player am Gate-Ring @225 (Ziel = Mittelpunkt)")
    check(approx(State.baby.angle, 235, 0.5),
        "rueckkehr: Baby behält EIGENEN Winkel @235 (VOR dem Player)")
end

-- --- Anti-Bypass: mit D=A ist der Weg zum Tor durch S gesperrt -------------
do
    setup(Levels[7])
    Room.movePlayer(171.83)
    Room.movePlayer(-131.83)
    Room.tryUseConnection() -- Solo A
    Bridge.update(0.5) -- inner@60
    Room.movePlayer(240) -- D=A, S zu, inner@300
    check(State.elementStates["S"] == false, "s-blockiert: S geschlossen (D=A)")
    local _, r = Room.movePlayer(302) -- 300 -> CW um den Ring -> 242 (S CW-Eintritt)
    check(r.blocked == true, "s-blockiert: CW-Anlauf prallt an S ab")
    check(approx(State.player.angle, 242, 2), "s-blockiert: Player stoppt an S (~242)")
end

TestReport.room7 = { pass = pass, fail = fail }
