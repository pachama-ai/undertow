-- Tests für Raum 3 „Wache halten“ (Druckplatte + Baby parken + Doppelschalter):
--   KEINE künstliche Startposition — ENTRY = Level-2-Ausgang (Player äußerer
--   Ring @135, Baby @145: Baby CW vor dem Player -> PUSH_DIRECTION = CW).
--   EXAKT ZWEI aktive Ringe: outer (5), inner (4) + Mittelpunkt.
--   ÄUSSERER RING: P (Platte @185), S1 (@290, von P, deckt Bridge A), Bridge
--     A (outer<->inner@290), Bridge B (inner<->outer@340).
--   INNERER RING: D (Doppelschalter @310; onB=S2, state A), S2 (@340, deckt
--     Bridge B@340), Tor T@135.
-- ABLAUF: Baby auf P -> S1 öffnet -> Player CW zu Bridge A@290 -> SOLO auf den
-- inneren Ring@290. D=A Start (S2 zu): die natürliche kurze CW-Anfahrt zu
-- Bridge B prallt an S2 ab (D=A ist falsch); die CCW-Überquerung von D
-- (Zustand B) öffnet S2 -> lange CCW-Route durch S2 (offen) zu Bridge B@340
-- -> SOLO auf outer@340 (andere Babyseite) -> Baby CCW von P holen und zu
-- Bridge B@340 schieben -> SHARED-Transit -> inner@340/330 -> CCW zum Tor
-- T@135 (D wird auf der finalen Route als No-Op überquert, S2 bleibt offen)
-- -> gemeinsamer Center-Transit -> EXIT.
-- Am Ende wird das Ergebnis in TestReport.room3 gesammelt.

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

-- --- Raum 3 Daten ----------------------------------------------------------
do
    local r3 = Levels[3]
    check(r3.name == "Wache halten", "daten: Name 'Wache halten'")
    check(r3.rings.outer == 5 and r3.rings.inner == 4 and r3.rings.middle == nil,
        "daten: EXAKT 2 aktive Ringe (5/4) — kein dritter Ring")
    check(r3.start.ring == "outer" and approx(r3.start.angle, 135),
        "daten: ENTRY = Level-2-Ausgang (Player outer@135)")
    check(r3.baby ~= nil and r3.baby.start.ring == "outer" and approx(r3.baby.start.angle, 145),
        "daten: Baby outer@145 (CW vor dem Player)")
    check(#r3.switches == 1, "daten: genau 1 Schalter (Doppelschalter D)")
    local d = r3.switches[1]
    check(d.id == "D" and d.ring == "inner" and approx(d.angle, 310) and d.state == "A",
        "daten: D inner@310 (Start A)")
    check(type(d.onA) == "table" and #d.onA == 0 and d.onB == "S2",
        "daten: D öffnet S2 in Zustand B (A: S2 zu)")
    check(#r3.shutters == 2, "daten: genau 2 Blenden (S1, S2)")
    local byId = {}
    for _, sh in ipairs(r3.shutters) do byId[sh.id] = sh end
    check(byId["S1"] ~= nil and byId["S1"].ring == "outer" and approx(byId["S1"].angle, 290),
        "daten: S1 outer@290 (von P — deckt Bridge A)")
    check(byId["S2"] ~= nil and byId["S2"].ring == "inner" and approx(byId["S2"].angle, 340),
        "daten: S2 inner@340 (von D — deckt Bridge B)")
    check(#r3.plates == 1, "daten: genau 1 Druckplatte")
    check(r3.plates[1].id == "P" and r3.plates[1].ring == "outer"
        and approx(r3.plates[1].angle, 185) and r3.plates[1].on == "S1",
        "daten: P outer@185 steuert S1 (Baby-Parkplatz)")
    check(#r3.bridges == 2, "daten: genau 2 Brücken (A + B)")
    local bA, bB
    for _, b in ipairs(r3.bridges) do
        if b.id == "A" then bA = b end
        if b.id == "B" then bB = b end
    end
    check(bA ~= nil and bA.free and approx(bA.angle, 290),
        "daten: Bridge A@290 (Dock im S1-Bogen)")
    check(bB ~= nil and bB.free and approx(bB.angle, 340),
        "daten: Bridge B@340 (Dock im S2-Bogen)")
    check(r3.gate.id == "T" and r3.gate.free == true and r3.gate.ring == "inner"
        and approx(r3.gate.angle, 135), "daten: Tor T inner@135 (frei)")
    check(Levels.validate() == 0, "daten: Levels.validate() == 0")
end

-- --- Startzustand ----------------------------------------------------------
do
    setup(Levels[3])
    check(State.platePressed["P"] == false, "start: P frei (Baby nicht drauf)")
    check(State.elementStates["S1"] == false, "start: S1 geschlossen (P frei)")
    check(State.switchStates["D"] == "A", "start: D = A")
    check(State.elementStates["S2"] == false, "start: S2 geschlossen (D=A)")
    check(State.elementStates["A"] == true and State.elementStates["B"] == true
        and State.elementStates["T"] == true, "start: A+B+T frei aktiv")
    check(State.player.ring == "outer" and approx(State.player.angle, 135), "start: Player outer@135")
    check(State.baby ~= nil and State.baby.ring == "outer" and approx(State.baby.angle, 145),
        "start: Baby outer@145")
end

-- --- Druckplatte: Baby auf P -> S1 offen -----------------------------------
do
    setup(Levels[3])
    local _, r = Room.movePlayer(41.83) -- 135 -> ~177, Baby 145 -> 185 (P@185)
    check(r.blocked == false, "platte: Schub läuft")
    check(State.platePressed["P"] == true, "platte: Baby auf P -> gedrückt")
    check(State.elementStates["S1"] == true, "platte: S1 offen (P aktiv)")
    check(approx(State.player.angle, 176.83, 0.5), "platte: Player bei ~177")
    check(approx(State.baby.angle, 185, 1.0), "platte: Baby geparkt auf P (185)")
end

-- --- S1 blockiert Zugang zu Bridge A, bis das Baby auf P steht -------------
do
    setup(Levels[3])
    -- Ohne Baby auf P: S1 (Bogen [277,303]) blockiert den CCW-Zugang zu A.
    local _, r = Room.movePlayer(-200) -- 135 CCW, stoppt an S1@303
    check(r.blocked == true, "s1: CCW zu Bridge A blockiert (S1 zu)")
    check(approx(State.player.angle, 303, 1.5), "s1: Player stoppt an S1-Kante (303)")
    local res1 = Room.tryUseConnection()
    check(res1.used == false, "s1: Bridge A nicht nutzbar (CCW)")
    -- Mit Baby auf P: S1 offen, Player erreicht Bridge A und geht SOLO.
    setup(Levels[3])
    Room.movePlayer(41.83) -- Baby auf P@185, S1 offen
    -- Der Player geht CCW um den Ring (CW würde das Baby von P schieben)
    -- und erreicht Bridge A@290 durch die offene S1.
    local _, r2 = Room.movePlayer(-246.83) -- ~177 -> 290 CCW (durch S1)
    check(r2.blocked == false, "s1: Player passiert S1")
    check(approx(State.player.angle, 290, 1), "s1: Player an Bridge A")
    check(State.platePressed["P"] == true, "s1: Baby bleibt auf P")
    local resA = Room.tryUseConnection()
    check(resA.used == true and resA.kind == "bridge", "s1: Player geht ALLEIN über Bridge A")
    Bridge.update(0.5)
    Room.syncPhysicalShutters()
    check(State.player.ring == "inner" and State.baby.ring == "outer",
        "s1: Player auf Ring B (inner), Baby auf P (getrennt)")
end

-- --- NATÜRLICHE CW-Anfahrt zu Bridge B ist versperrt (D=A falsch) ----------
do
    setup(Levels[3])
    State.player.ring = "inner"
    State.player.angle = 290
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    check(State.switchStates["D"] == "A" and State.elementStates["S2"] == false,
        "cw-start: D=A, S2 zu")
    -- CW (natürlich, falsch): 290 -> D CW (kein Wechsel, A) -> S2@327 (zu).
    local _, r = Room.movePlayer(50) -- 290 -> 340 (stoppt an S2)
    check(r.blocked == true, "cw-falsch: CW-Anfahrt prallt an S2 ab")
    check(approx(State.player.angle, 327, 1.5), "cw-falsch: Player stoppt an S2 (327)")
    check(State.switchStates["D"] == "A", "cw-falsch: D unverändert (A)")
    check(State.elementStates["S2"] == false, "cw-falsch: S2 geschlossen")
    local res = Room.tryUseConnection()
    check(res.used == false, "cw-falsch: Bridge B nicht nutzbar (Sackgasse)")
end

-- --- RICHTIGE Richtung: D CCW -> B (S2 öffnet), lange Route zu B -----------
do
    setup(Levels[3])
    State.player.ring = "inner"
    State.player.angle = 327 -- an S2 abgeprallt (D=A)
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    -- CCW zurück über D: 327 -> 317 (Eintritt) -> 303 (Austritt) -> B.
    local _, r1 = Room.movePlayer(-24) -- 327 -> 303 (über D CCW)
    check(r1.blocked == false, "ccw-richtig: Rückweg über D läuft")
    check(State.switchStates["D"] == "B", "ccw-richtig: D=B (CCW-Überquerung)")
    check(State.elementStates["S2"] == true, "ccw-richtig: S2 offen (D=B)")
    -- Lange CCW-Route durch S2 (offen) zu Bridge B@340.
    local _, r2 = Room.movePlayer(-323) -- 303 -> 340 (durch S2, um den Ring)
    check(r2.blocked == false, "ccw-richtig: lange CCW-Route läuft (S2 offen)")
    check(approx(State.player.angle, 340, 0.5), "ccw-richtig: Player an Bridge B (inner@340)")
    check(State.switchStates["D"] == "B", "ccw-richtig: D NICHT erneut überquert")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "ccw-richtig: SOLO über Bridge B")
    Bridge.update(0.5)
    check(State.player.ring == "outer" and approx(State.player.angle, 340, 0.5),
        "ccw-richtig: Player outer@340 (ANDERE Babyseite)")
end

-- --- BABY RECOVERY (Push-only) + gemeinsamer Rücktransit -------------------
do
    setup(Levels[3])
    -- Zustand nach Bridge B: Player outer@340, Baby geparkt auf P (185).
    -- Player steht CW vom Baby -> schiebt es CCW (um den Ring) zurück zur
    -- Bridge B@340.
    State.player.ring = "outer"
    State.player.angle = 340
    State.baby.ring = "outer"
    State.baby.angle = 185
    State.setSwitch("D", "B") -- S2 offen (wie nach der richtigen Wahl)
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.player.angle > State.baby.angle, "recovery: Player CW vom Baby (340 > 185)")
    check(State.platePressed["P"] == true, "recovery: Baby hält P")
    local _, r = Room.movePlayer(-351.83) -- Player 340 -> ~348, Baby 185 -> ~340
    check(r.blocked == false, "recovery: CCW-Schub läuft (kein Ziehen)")
    check(approx(State.player.angle, 348.17, 1), "recovery: Player bei ~348")
    check(approx(State.baby.angle, 340, 1), "recovery: Baby an Bridge B (340)")
    check(State.platePressed["P"] == false, "recovery: P frei (Baby herunter)")
    check(State.elementStates["S1"] == false, "recovery: S1 geschlossen (egal)")
    -- Gemeinsamer Transit über Bridge B zurück auf den inneren Ring.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "recovery: gemeinsamer Transit über Bridge B")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "recovery: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 330, 0.5),
        "recovery: Baby inner@330 (CCW vor dem Player, letzte Schieberichtung)")
end

-- --- KEIN SEITEN-FLIP beim gemeinsamen Transit (Level-3-Bugfix) -------------
-- Das Baby muss auf DERSELBEN Seite wie vor dem Transit landen (PLAYER -> BABY
-- bleibt PLAYER -> BABY, NICHT BABY -> PLAYER), auch wenn Player + Baby exakt
-- am Dock stehen (delta(player,baby) = 0) und das Baby nur minimal neben der
-- Bridge-Achse steht. Die Landeseite wird aus der BABY-Position relativ zur
-- Bridge-Achse abgeleitet (kein Winkel-Flip, keine Vorzeichenumkehr).
do
    -- Baby minimal CCW der Bridge-Achse @340 (Player exakt auf der Achse):
    -- landet CCW (330) — dieselbe Seite, kein Flip.
    setup(Levels[3])
    State.player.ring = "outer"
    State.player.angle = 340
    State.baby.ring = "outer"
    State.baby.angle = 338
    State.setSwitch("D", "B")
    State.deriveElements()
    Room.syncPhysicalShutters()
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "kein-flip: Shared-Transit startet (CCW-Dock)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "kein-flip: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 330, 0.5),
        "kein-flip: Baby inner@330 — DIESELBE (CCW-)Seite wie vorher")
end
do
    -- Baby minimal CW der Bridge-Achse @340 (Player exakt auf der Achse):
    -- landet CW (350) — dieselbe Seite, kein Flip.
    setup(Levels[3])
    State.player.ring = "outer"
    State.player.angle = 340
    State.baby.ring = "outer"
    State.baby.angle = 342
    State.setSwitch("D", "B")
    State.deriveElements()
    Room.syncPhysicalShutters()
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "kein-flip-cw: Shared-Transit startet (CW-Dock)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "kein-flip-cw: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 350, 0.5),
        "kein-flip-cw: Baby inner@350 — DIESELBE (CW-)Seite wie vorher")
end
-- KRITISCH: Player und Baby stehen auf DERSELBEN Seite der Bridge-Achse
-- (CCW-Überschwinger: Baby @342 ist CW der Achse @340, aber CCW vom Player
-- @350.17). Die Referenz MUSS der PLAYER sein, sonst wird das Baby gespiegelt.
do
    setup(Levels[3])
    State.setBabyPushDirection(-1) -- CCW-Schub (wie die Level-3-Lösung)
    State.player.ring = "outer"
    State.player.angle = 350.17
    State.baby.ring = "outer"
    State.baby.angle = 342 -- CCW-Überschwinger: auf derselben (CW-)Seite der Achse wie der Player
    State.setSwitch("D", "B")
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.player.angle > State.baby.angle, "seite-player: Player CW vom Baby (350 > 342)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "seite-player: Shared-Transit startet (CCW-Überschwinger)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "seite-player: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 330, 0.5),
        "seite-player: Baby inner@330 — CCW vom Player WIE VORHER (350->340, 342->330), KEIN Flip")
end
do
    -- Gegenstück (CW-Überschwinger): Baby @338 ist CCW der Achse @340, aber CW
    -- vom Player @331.83 -> landet CW (350), kein Flip.
    setup(Levels[3])
    State.setBabyPushDirection(1) -- CW-Schub
    State.player.ring = "outer"
    State.player.angle = 331.83
    State.baby.ring = "outer"
    State.baby.angle = 338
    State.setSwitch("D", "B")
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.player.angle < State.baby.angle, "seite-player-cw: Player CCW vom Baby (332 < 338)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge",
        "seite-player-cw: Shared-Transit startet (CW-Überschwinger)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 340, 0.5),
        "seite-player-cw: Player inner@340")
    check(State.baby ~= nil and State.baby.ring == "inner"
        and approx(State.baby.angle, 350, 0.5),
        "seite-player-cw: Baby inner@350 — CW vom Player WIE VORHER, KEIN Flip")
end

-- --- Finale: CCW zum Tor, Center-Transit -----------------------------------
do
    setup(Levels[3])
    -- Zustand nach der gemeinsamen Rückkehr (Soll-Lösung): Player inner@340,
    -- Baby inner@330, D=B (S2 offen).
    State.player.ring = "inner"
    State.player.angle = 340
    State.baby.ring = "inner"
    State.baby.angle = 330
    State.setBabyPushDirection(-1)
    State.setSwitch("D", "B")
    State.deriveElements()
    Room.syncPhysicalShutters()
    check(State.elementStates["S2"] == true, "final-start: S2 offen (D=B)")
    -- Player schiebt Baby CCW zum Tor T@135 (D wird als No-Op überquert).
    local _, r = Room.movePlayer(-195) -- Player 340 -> 145, Baby 330 -> ~137
    check(r.blocked == false, "final: Schub zum Tor läuft")
    check(State.switchStates["D"] == "B", "final: D bleibt B (CCW-Überquerung No-Op)")
    check(State.elementStates["S2"] == true, "final: S2 bleibt offen")
    check(approx(State.player.angle, 145, 1), "final: Player am Tor (~145)")
    check(approx(State.baby.angle, 136.83, 2), "final: Baby am Tor (~137)")
    check(Gate.isUsable(Levels[3].gate, "inner", State.player.angle) == true,
        "final: Tor nutzbar (Player UND Baby)")
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "gate" and res.crossing == true
        and res.roomComplete == false, "final: Kernbrücken-Transit (Abschluss nach Transit)")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "final: gemeinsamer Center-Transit abgeschlossen (Level 3 fertig)")
    check(State.player.ring == "inner" and State.baby.ring == "inner"
        and approx(State.player.angle, 135, 0.5),
        "final: Player am Gate-Ring @135 (Ziel = Mittelpunkt)")
    check(approx(State.baby.angle, 145, 0.5),
        "final: Baby behält EIGENEN Winkel @145 (VOR dem Player)")
end

-- --- NO BYPASS: Gate verlangt das Baby (nicht solo abschließbar) -----------
do
    setup(Levels[3])
    State.player.ring = "inner"
    State.player.angle = 135
    State.baby.ring = "outer"
    State.baby.angle = 183
    Room.syncPhysicalShutters()
    local res = Room.tryUseConnection()
    check(res.used == false, "gate-solo: Tor ohne Baby NICHT nutzbar (kein Bypass)")
end

TestReport.room3 = { pass = pass, fail = fail }
