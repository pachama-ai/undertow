-- Tests für die Baby-Mechanik (generisch, Begleiter) + Raum-1-Regression.
-- Neue Produktregel: KEIN Ablageziel — das Baby ist Begleiter. Der finale
-- Raumausgang (Gate) verlangt das Baby am Gate (gemeinsamer Raumausgang);
-- normale Brücken innerhalb eines Raums bleiben ohne Baby nutzbar. Das Baby
-- wird in Folge-Räume mitgenommen (carry).
-- Verwendet die echten Leveldaten (Levels[1], Levels[2]) und synthetische
-- Aufrufe. Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/room, world/bridge, world/gate, world/baby, ui/render, ui/camera und
-- data/levels per import geladen wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.baby gesammelt.

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

-- Gemeinsames Setup wie in render_tests: Raum laden, Room init, Undo leeren,
-- Transit-/Assistenzzustände zurücksetzen, Kamera auf den äußeren Ring.
-- LEVEL 2 (Raum 2) ist seit dem Level-Design der schalter-/shutterbasierte
-- Doppelschalter-Raum OHNE Baby. Die Baby-Mechanik-Tests nutzen deshalb einen
-- lokalen synthetischen Baby-Raum mit der früheren Raum-2-Struktur (B0 frei,
-- Baby outer@60, Gate frei). setup() übersetzt Levels[2] transparent darauf.
local BABY_INTRO_ROOM = {
    name = "BabyIntro",
    rings = { outer = 6, inner = 5 },
    start = { ring = "outer", angle = 0 },
    baby = { start = { ring = "outer", angle = 60 } },
    switches = {},
    shutters = {},
    bridges = { { id = "B0", angle = 180, free = true } },
    gate = { id = "T", angle = 0, free = true },
}
local function setup(room)
    if room == Levels[2] then
        room = BABY_INTRO_ROOM
    end
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(room.rings.outer)
end

-- --- Raum 1: Einstieg (Bewegung + Baby + freie Brücke) ---------------------
do
    local r1 = Levels[1]
    check(r1.name == "Über die Brücke", "room1: Name")
    check(r1.rings.outer == 7 and r1.rings.inner == 6, "room1: Ringe 7/6")
    check(r1.start.ring == "outer" and r1.start.angle == 0, "room1: Start outer@0")
    check(#r1.switches == 0 and #r1.shutters == 0, "room1: keine Schalter/Blenden")
    check(#r1.bridges == 1 and r1.bridges[1].id == "B1" and r1.bridges[1].angle == 90 and r1.bridges[1].free == true,
        "room1: B1 frei @90 (von Anfang an aktiv)")
    check(r1.gate.id == "T" and r1.gate.ring == "inner" and r1.gate.angle == 135 and r1.gate.free == true,
        "room1: Gate frei inner@135")
    -- Baby ist ab Level 1 dabei (kein separates Baby-Tutorial-Level mehr).
    check(r1.baby ~= nil and r1.baby.start.ring == "outer" and r1.baby.start.angle == 60,
        "room1: Baby start outer@60")
    check(r1.plates == nil, "room1: keine Platten")
    setup(Levels[1])
    check(State.baby ~= nil and State.baby.ring == "outer" and State.baby.angle == 60,
        "room1 state: Baby outer@60")
end

-- --- Raum 1: Lösungsweg (Bewegung -> gemeinsamer Transit -> inner -> Tor) ---
do
    setup(Levels[1])
    -- Brücke von Anfang an aktiv (frei, kein Schalter nötig).
    check(State.elementStates["B1"] == true, "room1 lösung: B1 von Anfang an aktiv")
    -- CW 0 -> 90: Player schiebt das Baby zur B1@90, A -> GEMEINSAMER Transit.
    Room.movePlayer(90)
    check(approx(State.player.angle, 90), "room1 lösung: Player bei 90")
    local res = Room.tryUseConnection()
    check(res.used and res.kind == "sharedBridge", "room1 lösung: A -> gemeinsamer Transit (Baby mit)")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and State.baby.ring == "inner",
        "room1 lösung: Player+Baby auf inner")
    -- Schub zum Tor T@135 (inner) -> abgeschlossen (gemeinsamer Ausgang).
    Room.movePlayer(50) -- inner ~90 -> ~140, Baby wird mitgeschoben
    check(Gate.isUsable(Levels[1].gate, "inner", State.player.angle) == true,
        "room1 lösung: Tor T@135 nutzbar (Player UND Baby)")
    local gres = Room.tryUseConnection()
    check(gres.used and gres.kind == "gate" and gres.crossing == true and gres.roomComplete == false,
        "room1 lösung: Gate -> Kernbrücken-Transit (Abschluss nach Transit)")
    local gdone, gshared, _, gcenter = Bridge.update(0.5)
    check(gdone == true and gshared == true and gcenter == true,
        "room1 lösung: gemeinsamer Center-Transit abgeschlossen")
    check(State.player.ring == "inner" and State.baby.ring == "inner",
        "room1 lösung: Figuren am Gate-Ring (Ziel = Mittelpunkt)")
end

-- --- Baby-Einführungsraum (synthetisch, frühere Raum-2-Struktur) ------------
-- Raum 2 ist seit dem Level-Design der Doppelschalter-Raum ohne Baby; die
-- Baby-Mechanik-Tests laufen gegen den lokalen BABY_INTRO_ROOM.
do
    local r2 = BABY_INTRO_ROOM
    check(r2.name == "BabyIntro", "room2: Name")
    check(r2.rings.outer == 6 and r2.rings.inner == 5, "room2: Ringe 6/5")
    check(r2.baby ~= nil and r2.baby.start.ring == "outer" and r2.baby.start.angle == 60, "room2: Baby-Start")
    check(r2.baby.goal == nil, "room2: kein Baby-Ablageziel (goal) mehr")
    check(#r2.switches == 0 and #r2.shutters == 0, "room2: keine Schalter/Blenden")
    check(#r2.bridges == 1 and r2.bridges[1].id == "B0" and r2.bridges[1].free == true and r2.bridges[1].angle == 180, "room2: B0 frei @180")
    check(r2.gate.id == "T" and r2.gate.angle == 0 and r2.gate.free == true and r2.gate.babyLocked == nil,
        "room2: Gate frei (kein babyLocked, kein Ablageziel-Kopplung)")

    setup(r2)
    check(State.baby ~= nil, "room2 state: Baby vorhanden")
    check(State.baby.ring == "outer" and State.baby.angle == 60, "room2 state: Baby Startposition")
    check(State.baby.settled == false, "room2 state: Baby nicht eingerastet (settled immer false)")
    check(State.baby.lastPushDirection == 1, "room2 state: lastPushDirection CW")
    check(State.elementStates["B0"] == true, "room2 state: B0 aktiv")
    check(State.elementStates["T"] == true, "room2 state: Gate T mechanisch frei (aktiv)")
    -- Das Gate verlangt jetzt das Baby am Ausgang (gemeinsamer Raumausgang).
    check(Gate.isUsable(r2.gate, "inner", 0) == false, "room2: Gate ohne Baby am Ausgang gesperrt")
end

-- --- Schieben: CW ----------------------------------------------------------
do
    setup(Levels[2])
    local _, res = Room.movePlayer(60)
    check(approx(State.player.angle, 60), "push cw: Player bei 60")
    check(approx(State.baby.angle, 60 + Baby.contactDeg()), "push cw: Baby im Kontaktabstand")
    check(State.baby.ring == "outer" and State.baby.settled == false, "push cw: Baby outer, nicht eingerastet")
    check(res.babyMoved == true, "push cw: babyMoved true")
    check(res.undoStored == true, "push cw: Undo-Snapshot entstanden")
end

-- --- Schieben: CCW ---------------------------------------------------------
do
    setup(Levels[2])
    State.player.angle = 100
    local _, res = Room.movePlayer(-50)
    check(approx(State.player.angle, 50), "push ccw: Player bei 50")
    check(approx(State.baby.angle, 60 - (50 - (100 - 60 - Baby.contactDeg()))), "push ccw: Baby mitgeschoben")
    check(res.babyMoved == true, "push ccw: babyMoved true")
end

-- --- Kein Ziehen -----------------------------------------------------------
do
    setup(Levels[2])
    local _, res = Room.movePlayer(-30)
    check(approx(State.player.angle, 330), "no pull: Player CCW weg")
    check(State.baby.angle == 60, "no pull: Baby bleibt stehen")
    check(res.babyMoved == false, "no pull: babyMoved false")
end

-- --- Kein Durchspringen (großes Delta) -------------------------------------
do
    setup(Levels[2])
    Room.movePlayer(300)
    check(approx(State.player.angle, 300), "no tunnel: Player bei 300")
    -- Baby endet im Kontaktabstand VOR dem Spieler (300 + contact)
    check(approx(State.baby.angle, 300 + Baby.contactDeg()), "no tunnel: Baby endet vor dem Player")
end

-- --- Wraparound über 0° ----------------------------------------------------
do
    setup(Levels[2])
    State.player.angle = 355
    State.baby.angle = 5
    Room.movePlayer(10)
    check(approx(State.player.angle, 5), "wraparound: Player bei 5")
    check(approx(State.baby.angle, 5 + Baby.contactDeg()), "wraparound: Baby über 0° geschoben")
end

-- --- Reine Push-Mathematik ------------------------------------------------
do
    local newA, amt, dir = Baby.computePush(60, 0, 1, 60)
    check(newA ~= nil and approx(newA, 60 + Baby.contactDeg()), "math: computePush CW")
    check(amt ~= nil and approx(amt, Baby.contactDeg()), "math: pushAmount = contact")
    check(dir == 1, "math: Richtung CW")
    local none = Baby.computePush(60, 0, 1, 30)
    check(none == nil, "math: kein Schub wenn nicht erreicht")
end

-- --- Gemeinsamer Brückentransfer (EIN A für Player + Baby) -----------------
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "shared: A -> gemeinsamer Transit")
    check(Bridge.isCrossing() == true, "shared: Transit aktiv")
    -- Vor dem Abschluss bleiben beide logisch auf dem Quellring (sauberer Zustand)
    check(State.player.ring == "outer" and State.baby.ring == "outer", "shared: vor Abschluss beide outer")
    Bridge.update(0.5) -- Gesamtdauer ~0.43 s
    check(State.player.ring == "inner" and approx(State.player.angle, 180), "shared: Player auf inner@180")
    check(State.baby.ring == "inner" and approx(State.baby.angle, 190), "shared: Baby auf inner@190 (voraus)")
    check(State.player.angle ~= State.baby.angle, "shared: kein Overlap (unterschiedliche Winkel)")
end

-- --- Gemeinsamer Transit: Baby ist auf der Brücke vor dem Player -----------
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    Room.tryUseConnection()
    local total = Config.sharedBridgeHold + Config.sharedBabyLead + Config.sharedPlayerDuration
    Bridge.update(total * 0.5) -- halb durch
    local bp = Bridge.getBabyTransitProgress() or 0
    local pp = Bridge.getTransitProgress() or 0
    check(bp > 0 and bp < 1, "shared mid: Baby mitten auf der Brücke (kein Teleport)")
    check(bp > pp, "shared mid: Baby-Fortschritt > Player-Fortschritt (voraus)")
    Bridge.update(total)
    check(State.player.ring == "inner" and State.baby.ring == "inner", "shared mid: nach Abschluss beide inner")
end

-- --- Gemeinsamer Transit: Baby läuft VOR dem Player (kein Overlap) --------
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    Room.tryUseConnection()
    local t = Bridge.getTransit()
    check(t ~= nil and t.shared, "anim: gemeinsamer Transit")
    check(approx(Bridge.getBabyTransitProgress() or 0, 0), "anim: Baby-Start bei 0")
    check(approx(Bridge.getTransitProgress() or 0, 0), "anim: Player-Start bei 0 (Hold+Lead)")
    -- Sanftes Alignment: beide Figuren starten auf ihren TATSÄCHLICHEN
    -- Positionen (kein Teleport) und gleiten im Hold in die Dockformation.
    local dir = (State.baby and State.baby.lastPushDirection) or 1
    check(t.playerStartAngle ~= nil and approx(t.playerStartAngle, 176),
        "anim: Player-Startwinkel = reale Position (Alignment)")
    check(t.babyStartAngle ~= nil and approx(t.babyStartAngle, 184),
        "anim: Baby-Startwinkel = reale Position (Alignment)")
    -- Ready-Moment (Hold): nach dem Hold sitzt das Baby auf der Achse, der
    -- Player in der Dockformation direkt dahinter (sichtbarer Abstand).
    Bridge.update(Config.sharedBridgeHold)   -- Ende Hold (elapsed = hold)
    local babyAngle = Render.sharedBabyAngle() or 0
    local playerAngle = Render.sharedPlayerAngle() or 0
    check(approx(babyAngle, 180, 0.5), "anim: Baby nach Hold auf der Achse")
    check(approx(playerAngle, Geometry.norm(180 - dir * Config.sharedFormationGapDeg), 0.5),
        "anim: Player nach Hold in Formation direkt hinter dem Baby")
    -- Baby startet zuerst (eigene kürzere Dauer): während der Lead-Phase ist
    -- der Player noch bei 0, das Baby schon unterwegs.
    Bridge.update(0.04)                       -- elapsed hold+0.04
    local bp = Bridge.getBabyTransitProgress() or 0
    local pp = Bridge.getTransitProgress() or 0
    check(bp > 0 and approx(pp, 0), "anim: Baby startet vor dem Player (Lead)")
    -- Mittendrin: Baby deutlich voraus (radiale Trennung, kein Overlap).
    Bridge.update(0.11)                       -- elapsed 0.21
    bp = Bridge.getBabyTransitProgress() or 0
    pp = Bridge.getTransitProgress() or 0
    check(bp > 0.5 and pp > 0, "anim: beide auf der Brücke")
    check(bp - pp > 0.15, "anim: Baby deutlich vor Player (radial getrennt)")
    local babyR = Render.babyRadius() or 0
    local playerR = Render.playerRadius() or 0
    check(math.abs(babyR - playerR) >= 2, "anim: radiale Trennung >= 2px (kein Overlap)")
    -- Baby landet ZUERST (Landing-Event vor dem Abschluss).
    local babyLanded = false
    local completed = false
    while not completed do
        local done, shared, landed = Bridge.update(0.02)
        if landed then babyLanded = true end
        completed = done
    end
    check(babyLanded == true, "anim: Baby-Landing-Event gefeuert (Baby zuerst)")
    -- Finale Positionen: Player auf der Achse, Baby voraus, kein Overlap.
    check(State.player.ring == "inner" and State.baby.ring == "inner", "anim: beide inner")
    check(approx(State.player.angle, 180), "anim: Player final auf Achse 180")
    check(State.player.angle ~= State.baby.angle, "anim: kein Overlap (unterschiedliche Winkel)")
    local gap = math.abs(Geometry.delta(State.player.angle, State.baby.angle))
    check(gap >= 2, "anim: finaler Abstand >= 2°")
end

-- --- SHARED BRIDGE PATH FIX: harte Geometrie (kein Hintergrund-Cutting) ---
-- Während ALIGNMENT: Winkel darf sich ändern, Radius bleibt Ringradius.
-- Während CROSSING: Winkel = Bridge-Achse (konstant), nur Radius wandert.
-- Zusätzlich Screenspace-Check: Figuren-Center liegen auf der Bridge-Achse.
do
    local hold = Config.sharedBridgeHold
    local lead = Config.sharedBabyLead
    local babyDur = Config.sharedBabyDuration
    local playerDur = Config.sharedPlayerDuration
    local axis = 180
    local fromR = Render.ringRadius("outer")
    local toR = Render.ringRadius("inner")
    local function distToAxis(x, y)
        local ax1, ay1 = Geometry.polar(Config.centerX, Config.centerY, fromR, axis)
        local ax2, ay2 = Geometry.polar(Config.centerX, Config.centerY, toR, axis)
        local lineLen = math.sqrt((ax2 - ax1) ^ 2 + (ay2 - ay1) ^ 2)
        return math.abs((ax2 - ax1) * (ay1 - y) - (ax1 - x) * (ay2 - ay1)) / lineLen
    end

    -- ALIGNMENT: bei mehreren Progresswerten bleibt der Radius der Ringradius.
    for _, p in ipairs({ 0.15, 0.30, 0.50, 0.70, 0.85 }) do
        setup(Levels[2])
        State.player.angle = 176
        State.baby.angle = 184
        Room.tryUseConnection()
        Bridge.update(hold * p)
        local pr = Render.playerRadius() or -1
        local br = Render.babyRadius() or -1
        check(approx(pr, fromR, 0.01),
            string.format("path-align-p%.2f: Player-Radius = Ringradius", p))
        check(approx(br, fromR, 0.01),
            string.format("path-align-b%.2f: Baby-Radius = Ringradius", p))
        Bridge.resetTransit()
    end

    -- CROSSING (Player): bei Player-Fortschrittspunkten ist der Winkel exakt
    -- die Bridge-Achse und das Player-Center liegt auf der Achse.
    for _, p in ipairs({ 0.15, 0.30, 0.50, 0.70, 0.85 }) do
        setup(Levels[2])
        State.player.angle = 176
        State.baby.angle = 184
        Room.tryUseConnection()
        Bridge.update(hold + lead + playerDur * p) -- Player-Fortschritt p
        local pa = Render.sharedPlayerAngle() or -1
        check(approx(pa, axis, 0.01),
            string.format("path-cross-p%.2f: Player-Winkel = Bridge-Achse", p))
        local px, py = Render.playerScreenPosition()
        check(px ~= nil and distToAxis(px, py) <= 0.01,
            string.format("path-axis-p%.2f: Player-Center auf Bridge-Achse", p))
        Bridge.resetTransit()
    end

    -- CROSSING (Baby): bei Baby-Fortschrittspunkten ist der Winkel exakt die
    -- Bridge-Achse und das Baby-Center liegt auf der Achse.
    for _, p in ipairs({ 0.15, 0.30, 0.50, 0.70, 0.85 }) do
        setup(Levels[2])
        State.player.angle = 176
        State.baby.angle = 184
        Room.tryUseConnection()
        Bridge.update(hold + babyDur * p) -- Baby-Fortschritt p
        local ba = Render.sharedBabyAngle() or -1
        check(approx(ba, axis, 0.01),
            string.format("path-cross-b%.2f: Baby-Winkel = Bridge-Achse", p))
        local bx, by = Render.babyScreenPosition()
        check(bx ~= nil and distToAxis(bx, by) <= 0.01,
            string.format("path-axis-b%.2f: Baby-Center auf Bridge-Achse", p))
        Bridge.resetTransit()
    end

    -- SOLO-Transit (Player allein, Baby nicht am Dock): ebenfalls exakt
    -- radial über den sichtbaren Bridge-Kanal — kein Hintergrund-Cutting.
    do
        setup(Levels[2])
        State.player.angle = 176
        Room.tryUseConnection() -- Baby bei 60 (fern) -> Player-Solo
        Bridge.update(Config.bridgeAnimDuration * 0.5)
        local px, py, pa = Render.playerScreenPosition()
        check(px ~= nil and approx(pa, axis, 0.01),
            "path-solo: Player-Winkel = Bridge-Achse (konstant)")
        check(px ~= nil and distToAxis(px, py) <= 0.01,
            "path-solo: Player-Center auf Bridge-Achse")
        Bridge.resetTransit()
    end
end

-- --- Solo-Player-Brücke (Baby NICHT am Dock) -------------------------------
do
    setup(Levels[2])
    -- Baby zu weit weg (Start outer@60) -> Player benutzt die Brücke alleine.
    State.player.angle = 176
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "solo: Player nutzt Brücke alleine (Baby nicht am Dock)")
    check(Bridge.isCrossing() == true, "solo: Solo-Transit aktiv")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and approx(State.player.angle, 180), "solo: Player auf inner@180")
    check(State.baby.ring == "outer" and approx(State.baby.angle, 60), "solo: Baby bleibt outer@60")
    check(Render.babyBridgeReady() == false, "solo: Baby auf anderem Ring nicht ready")
end

-- --- Shared Bridge: leichte Ungenauigkeit wird akzeptiert -----------------
do
    setup(Levels[2])
    -- Beide leicht vom exakten Dock versetzt, aber visuell korrekt (Baby vorne,
    -- Player dahinter): Shared Transit funktioniert zuverlässig.
    State.player.angle = 173 -- 7° vor der Brückenachse (dockRange 12)
    State.baby.angle = 187   -- 7° nach der Achse (babyDockRange 16)
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "shared-offset: leicht versetzt -> Shared Transit")
    check(Bridge.isCrossing() == true and Bridge.getTransit().shared == true, "shared-offset: gemeinsamer Transit")
    Bridge.update(0.5)
    check(State.player.ring == "inner" and State.baby.ring == "inner", "shared-offset: beide auf inner")
end

-- --- Shared Bridge: Baby zu weit weg -> kein Shared ------------------------
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 197 -- 17° > babyDockRange (16) von B0@180
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "shared-far: Baby zu weit -> Player-Solo-Brücke")
    check(Bridge.isCrossing() == true and not Bridge.getTransit().shared, "shared-far: kein Shared-Transit")
    Bridge.update(0.5)
end

-- --- Shared Bridge: Baby auf falscher Ringseite -> kein Shared -------------
do
    setup(Levels[2])
    State.player.ring = "outer"
    State.player.angle = 176
    State.baby.ring = "inner" -- falsche Ringseite (Baby nicht am Player-Dock)
    State.baby.angle = 184
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "shared-ring: Baby anderer Ring -> Player-Solo-Brücke")
    check(Bridge.isCrossing() == true and not Bridge.getTransit().shared, "shared-ring: kein Shared-Transit")
    Bridge.update(0.5)
end

-- --- Shared Bridge Handling: Dockzone + relative Formation (Pass) ----------
-- Der gemeinsame Übergang soll handlich sein: leicht versetzte Figuren im
-- Bereich der Shared-Dockzone lösen den Shared-Transit zuverlässig aus, eine
-- unplausible Formation (Baby deutlich hinter dem Player) NICHT.
do
    -- Exaktes Dock -> Shared.
    setup(Levels[2])
    State.player.angle = 180
    State.baby.angle = 180
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "handling-exact: exaktes Dock -> Shared")

    -- Leicht VOR dem Dock (Player 7° vor, Baby minimal nach der Achse) -> Shared.
    setup(Levels[2])
    State.player.angle = 173
    State.baby.angle = 183
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "handling-vor: leicht vor dem Dock -> Shared")

    -- Leicht HINTER dem Dock (Player knapp nach der Achse, Baby voraus) -> Shared.
    setup(Levels[2])
    State.player.angle = 183
    State.baby.angle = 187
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "handling-hinter: leicht hinter dem Dock -> Shared")

    -- Baby leicht versetzt, aber innerhalb der Shared-Dockzone -> Shared.
    setup(Levels[2])
    State.player.angle = 174
    State.baby.angle = 192 -- 12° nach der Achse (innerhalb sharedDockRange 15)
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "handling-versatz: Baby leicht versetzt -> Shared")

    -- Baby zu weit (17° > sharedDockRange 15) -> kein Shared.
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 197
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge",
        "handling-fern: Baby zu weit -> kein Shared")
    check(Bridge.isCrossing() == true and not Bridge.getTransit().shared,
        "handling-fern: Solo-Transit statt Shared")

    -- Baby auf falscher Seite (deutlich HINTER dem Player) -> kein Shared.
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 170
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge",
        "handling-seite: Baby hinter dem Player -> kein Shared")
    check(Bridge.isCrossing() == true and not Bridge.getTransit().shared,
        "handling-seite: Solo-Transit statt Shared")

    -- Baby nicht dabei -> Player-Solo-Brücke (unverändert).
    setup(Levels[2])
    State.baby.angle = 60 -- weit weg, nicht am Dock
    State.player.angle = 176
    res = Room.tryUseConnection()
    check(res.used == true and res.kind == "bridge", "handling-solo: Baby nicht dabei -> Solo-Brücke")
    Bridge.update(0.5)

    -- Inaktive Brücke (S1=B -> B0 aus? B0 ist frei/aktiv in Raum 2; eigener
    -- Raum mit inaktiver Brücke) -> kein Transit, kein Shared.
    do
        local room = {
            name = "HandlingInactive",
            rings = { outer = 7, inner = 6 },
            start = { ring = "outer", angle = 0 },
            switches = { { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "B" } },
            shutters = {},
            bridges = { { id = "B1", angle = 180, free = false } },
            gate = { id = "T", angle = 0, free = true },
            baby = { start = { ring = "outer", angle = 180 } },
        }
        setup(room)
        State.player.angle = 180
        State.baby.angle = 180
        res = Room.tryUseConnection()
        check(res.used == false, "handling-inaktiv: inaktive Brücke -> kein Transit")
        check(Bridge.isCrossing() == false, "handling-inaktiv: kein Crossing")
    end

    -- Sanftes Alignment: die Snapkorrektur beim Transitstart ist klein
    -- (beide Figuren sind bereits in der Shared-Dockzone; der Gameplay-State
    -- wird auf die Zielformation gesetzt, die Render-Gleitspur nutzt die
    -- realen Startwinkel — kein sichtbarer Teleport).
    setup(Levels[2])
    State.player.angle = 174
    State.baby.angle = 186
    Room.tryUseConnection()
    local t2 = Bridge.getTransit()
    check(t2 ~= nil and t2.shared, "handling-align: Transit gestartet")
    check(approx(t2.playerStartAngle, 174, 0.01), "handling-align: Player-Start = reale Position")
    check(approx(t2.babyStartAngle, 186, 0.01), "handling-align: Baby-Start = reale Position")
end

-- --- Gemeinsamer Raumausgang (finales Gate verlangt das Baby) --------------
do
    setup(Levels[2])
    -- Player am Gate (inner@0), Baby weit weg (inner@190): KEIN Wechsel.
    State.player.ring = "inner"
    State.player.angle = 0
    State.baby.ring = "inner"
    State.baby.angle = 190
    check(Gate.isUsable(BABY_INTRO_ROOM.gate, "inner", 0) == false,
        "shared-exit: Player allein am Gate (Baby fern) -> kein Ausgang")
    local resAlone = Room.tryUseConnection()
    check(resAlone.used == false, "shared-exit: A am Gate ohne Baby -> keine Aktion")

    -- Baby auf anderem Ring: ebenfalls kein Ausgang.
    State.baby.ring = "outer"
    State.baby.angle = 60
    check(Gate.isUsable(BABY_INTRO_ROOM.gate, "inner", 0) == false,
        "shared-exit: Baby auf anderem Ring -> kein Ausgang")

    -- Player + Baby beide am Gate: Raumwechsel.
    State.baby.ring = "inner"
    State.baby.angle = 0
    check(Gate.isUsable(BABY_INTRO_ROOM.gate, "inner", 0) == true,
        "shared-exit: Player + Baby am Gate -> Ausgang nutzbar")
    local resBoth = Room.tryUseConnection()
    check(resBoth.used == true and resBoth.kind == "gate" and resBoth.crossing == true and resBoth.roomComplete == false,
        "shared-exit: A mit Baby am Gate -> Kernbrücken-Transit")
    local sdone, sshared, _, scenter = Bridge.update(0.5)
    check(sdone == true and sshared == true and scenter == true,
        "shared-exit: gemeinsamer Center-Transit abgeschlossen (Ausgang bereit)")
end

-- --- Undo ------------------------------------------------------------------
do
    setup(Levels[2])
    local _, res = Room.movePlayer(60)
    check(res.undoStored == true, "undo: Schub erzeugt Snapshot")
    check(approx(State.baby.angle, 60 + Baby.contactDeg()), "undo: Baby nach Schub im Kontaktabstand")
    check(Undo.undo() == true, "undo: undo erfolgreich")
    check(approx(State.player.angle, 0), "undo: Playerposition wiederhergestellt")
    check(approx(State.baby.angle, 60), "undo: Babyposition wiederhergestellt")
    check(State.baby.settled == false, "undo: settled false (kein Ablageziel)")
end

-- --- Restart (State.init = frischer Raum) ----------------------------------
do
    setup(Levels[2])
    State.player.ring = "inner"
    State.player.angle = 180
    State.baby.ring = "inner"
    State.baby.angle = 190
    setup(Levels[2])
    check(State.player.ring == "outer" and State.player.angle == 0, "restart: Player zurück outer@0")
    check(State.baby.ring == "outer" and approx(State.baby.angle, 60), "restart: Baby zurück outer@60")
    check(State.baby.settled == false, "restart: settled false (kein Ablageziel)")
    check(State.elementStates["T"] == true, "restart: Gate frei (mechanisch aktiv)")
end

-- --- Raumwechsel: Baby-Cleanup + Begleiter-Mitnahme ------------------------
do
    setup(Levels[2])
    check(State.baby ~= nil, "wechsel: Baby in Raum 2 vorhanden")
    setup(Levels[1])
    -- Baby ist ab Level 1 dabei: auch Raum 1 hat eine eigene Definition.
    check(State.baby ~= nil and State.baby.ring == "outer",
        "wechsel: Baby in Raum 1 vorhanden (eigene Definition)")

    -- Begleiter-Mitnahme: das Baby ist ab Level 1 dabei. In einem Folge-Raum
    -- OHNE eigene Baby-Definition übernimmt State.init(roomData, carry) den
    -- Begleiter-Start; in einem Raum MIT eigener Definition startet das Baby
    -- laut Leveldaten (hier: Raum 5 hat eine eigene Definition -> outer@286).
    setup(Levels[2])
    State.init(Levels[5], true)
    check(State.baby ~= nil, "wechsel-carry: Baby im Folge-Raum (5) vorhanden")
    check(State.baby.ring == Levels[5].baby.start.ring, "wechsel-carry: Baby auf dem definierten Ring")
    check(approx(State.baby.angle, Levels[5].baby.start.angle, 0.01),
        "wechsel-carry: Baby startet laut eigener Definition (outer@286)")
    check(State.baby.ring == "outer" and approx(State.baby.angle, 286, 0.01),
        "wechsel-carry: genau EIN Baby (eigene Definition), kein Doppel/Leak")
end

-- --- Renderer read-only ----------------------------------------------------
do
    setup(Levels[2])
    local beforeRing = State.baby.ring
    local beforeAngle = State.baby.angle
    local beforeSettled = State.baby.settled
    local okDraw, drawErr = pcall(Render.drawRoom, false, 2)
    check(okDraw, "render: drawRoom läuft fehlerfrei (Raum 2)")
    if not okDraw then
        print("BABY_RENDER_ERR: " .. tostring(drawErr))
    end
    check(State.baby.ring == beforeRing and State.baby.angle == beforeAngle and State.baby.settled == beforeSettled, "render: Baby nach drawRoom unverändert")
    check(Render.babyRadius() ~= nil, "render: babyRadius liefert Radius")
    local px, py = Render.babyScreenPosition()
    check(px ~= nil and py ~= nil, "render: babyScreenPosition liefert Position")
    check(approx(Render.babyRadius(), Config.outerRadius), "render: Baby auf outer -> outerRadius")
    setup(Levels[1])
    check(Render.babyRadius() ~= nil, "render: Baby auch in Raum 1 (eigene Definition)")
end

-- --- Vollständige deterministische Raum-2-Lösung (neue Regel) --------------
-- Kein Ablageziel: das Baby wird gemeinsam bis zum Gate geschoben.
do
    setup(Levels[2])
    -- 1) Player CW 0 -> 176 schiebt Baby 60 -> ~184 (Richtung Brücke B0@180)
    Room.movePlayer(176)
    check(approx(State.player.angle, 176), "lösung: Player bei 176 (outer)")
    check(approx(State.baby.angle, 184, 0.5), "lösung: Baby bei ~184 (outer)")
    -- 2) EIN A -> gemeinsamer Transfer (Player + Baby zusammen auf inner)
    local res2 = Room.tryUseConnection()
    check(res2.used == true and res2.kind == "sharedBridge", "lösung: A -> gemeinsamer Transfer")
    Bridge.update(0.5)
    check(State.baby.ring == "inner" and approx(State.baby.angle, 190), "lösung: Baby auf inner@190")
    check(State.player.ring == "inner" and approx(State.player.angle, 180), "lösung: Player auf inner@180")
    -- 3) Player CW schiebt Baby bis kurz vor das Gate (inner@0): 180 -> 350
    Room.movePlayer(170)
    check(approx(State.player.angle, 350), "lösung: Player bei 350 (inner)")
    -- 4) letzte kleine Strecke: beide am Gate (inner@0)
    Room.movePlayer(10)
    check(approx(State.player.angle, 0), "lösung: Player am Gate 0")
    check(State.baby.ring == "inner" and State.baby.angle <= Config.babyDockRange,
        "lösung: Baby im Gate-Dock-Bereich")
    -- 5) A am Gate MIT Baby -> gemeinsamer Kernbrücken-Transit (Abschluss folgt
    --    nach dem Transit/Landing, main.lua).
    local res5 = Room.tryUseConnection()
    check(res5.used == true and res5.kind == "gate" and res5.crossing == true and res5.roomComplete == false,
        "lösung: Gate -> Kernbrücken-Transit (gemeinsam, kein Ablageziel)")
    local ldone, lshared, _, lcenter = Bridge.update(0.5)
    check(ldone == true and lshared == true and lcenter == true,
        "lösung: gemeinsamer Center-Transit abgeschlossen")
end

-- --- Level-Validator: alle Räume konsistent --------------------------------
do
    local errs = Levels.validate()
    check(errs == 0, "validator: alle Räume konsistent (Fehler: " .. tostring(errs) .. ")")
end

-- --- Baby-Polish: Blink (deterministisch, seedbar) --------------------------
do
    setup(Levels[2])
    Render.babyBlinkRandom = function() return 0.5 end
    Render.resetPlayerVisual()
    -- Intervall: 0.6 + 0.5*(1.5-0.6) = 1.05 s (häufig — User: mehr Blinzeln)
    check(approx(Render.babyVisual.nextBlinkAt, 1.05, 1e-6), "polish blink: Termin 1.05 s (seeded)")
    -- Vor Ablauf kein Blink (10 × 0.1 = 1.0 s < 1.05 s)
    for _ = 1, 10 do
        Render.update(0.1, false)
    end
    check(Render.babyVisual.blinkFramesRemaining == 0, "polish blink: kein Blink vor Termin")
    -- Blinkphase startet kurz nach dem Termin (Float-Toleranz: 1-2 Frames).
    local started = false
    for _ = 1, 3 do
        Render.update(0.1, false)
        if Render.babyVisual.blinkFramesRemaining > 0 then started = true end
    end
    check(started, "polish blink: Blinkphase startet (nahe 1.05 s)")
    -- Blinkphase endet nach babyBlinkFrames Updates (Auge wieder offen)
    for _ = 1, Config.babyBlinkFrames do
        Render.update(0.1, false)
    end
    check(Render.babyVisual.blinkFramesRemaining == 0, "polish blink: Blinkphase endet (Auge offen)")
    -- Nicht permanent: direkt danach startet kein neuer Blink (Termin in Zukunft)
    Render.update(0.1, false)
    check(Render.babyVisual.blinkFramesRemaining == 0, "polish blink: Baby blinkt nicht permanent")
    Render.babyBlinkRandom = nil
end

-- --- Baby-Polish: Innenkreis (Player-Tracking) ------------------------------
-- Der Innenkreis folgt IMMER dem Player (Screen-Vektor baby->player), sobald
-- keine höher priorisierte Reaktion aktiv ist. Gleicher Ring (tangential) und
-- verschiedene Ringe (inward/outward). Push/Bridge/Transit: gezielte kleine
-- Versätze; Settle/Landing: zurück Richtung Zentrum.
do
    setup(Levels[2])
    Render.resetPlayerVisual()

    -- Gleicher Ring: Player links vom Baby -> Innenkreis zeigt links.
    State.player.ring = "outer"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 40
    local bx, by = Render.babyScreenPosition()
    local ex, ey = Render.babyEyePosition("normal", bx, by)
    check(ex < bx, "blick: Player links -> Innenkreis zeigt links")

    -- Player rechts -> Innenkreis zeigt rechts.
    State.player.angle = 100
    local bx2, by2 = Render.babyScreenPosition()
    local ex2, ey2 = Render.babyEyePosition("normal", bx2, by2)
    check(ex2 > bx2, "blick: Player rechts -> Innenkreis zeigt rechts")

    -- Player innen (Baby außen) -> inward-Komponente.
    State.player.ring = "inner"
    State.player.angle = 40
    State.baby.ring = "outer"
    State.baby.angle = 40
    local bx3, by3 = Render.babyScreenPosition()
    local ex3, ey3 = Render.babyEyePosition("normal", bx3, by3)
    check(ey3 > by3, "blick: Player innen -> Innenkreis zeigt nach innen")

    -- Player außen (Baby innen) -> outward-Komponente.
    State.player.ring = "outer"
    State.player.angle = 40
    State.baby.ring = "inner"
    State.baby.angle = 40
    local bx4o, by4o = Render.babyScreenPosition()
    local ex4o, ey4o = Render.babyEyePosition("normal", bx4o, by4o)
    check(ey4o < by4o, "blick: Player außen -> Innenkreis zeigt nach außen")

    -- Travel konstant babyLookTravel (klein, ruhig, kein googly-eye).
    local d3 = math.sqrt((ex3 - bx3) ^ 2 + (ey3 - by3) ^ 2)
    check(approx(d3, Config.babyLookTravel, 0.01), "blick: Travel = babyLookTravel (klein, ruhig)")

    -- Settle/Landing: zurück Richtung Zentrum (kein Versatz).
    local sx, sy = Render.babyEyePosition("settle", bx3, by3)
    check(approx(sx, bx3, 1e-6) and approx(sy, by3, 1e-6), "blick: settle -> zentral")
    local lx, ly = Render.babyEyePosition("landing", bx3, by3)
    check(approx(lx, bx3, 1e-6) and approx(ly, by3, 1e-6), "blick: landing -> zentral")

    -- Push: Innenkreis geringfügig in Bewegungsrichtung (tangential).
    State.player.angle = 40
    State.baby.angle = 40
    local bx4, by4 = Render.babyScreenPosition()
    Render.noteBabyPush(1) -- CW
    check(Render.babyEyeState() == "push", "blick-push: Push-State aktiv")
    local ex4, ey4 = Render.babyEyePosition("push", bx4, by4)
    check(ex4 > bx4, "blick-push: CW -> Innenkreis in Bewegungsrichtung")
    Render.noteBabyPush(-1) -- CCW
    local ex5, ey5 = Render.babyEyePosition("push", bx4, by4)
    check(ex5 < bx4, "blick-push: CCW -> Innenkreis gegen Bewegungsrichtung")

    -- Bridge-Ready: kurz Richtung Brücke (radial; Baby auf outer -> zum Kern).
    -- Baby zurück auf den Außenring setzen (der Tracking-Abschnitt oben
    -- wechselte auf inner für die inward/outward-Komponentenprüfung).
    State.baby.ring = "outer"
    State.player.angle = 176
    State.baby.angle = 184
    check(Render.babyBridgeReady() == true, "blick-bridge: Transfer bereit (Vorbereitung)")
    local bx5, by5 = Render.babyScreenPosition()
    local ex6, ey6 = Render.babyEyePosition("bridge", bx5, by5)
    check(ex6 > bx5 and ey6 < by5, "blick-bridge: Innenkreis radial zur Brücke (zum Kern)")

    -- Shared Transit: Innenkreis in Transitrichtung (zum Zielring).
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "blick-transit: Shared-Transit (Vorbereitung)")
    check(Render.babyEyeState() == "transit", "blick-transit: Transit-State gewinnt")
    local tx, ty = Render.babyScreenPosition()
    local ex7, ey7 = Render.babyEyePosition("transit", tx, ty)
    -- outer -> inner: exakt radial zum Kern mit babyLookTravel.
    local cxDir, cyDir = Config.centerX - tx, Config.centerY - ty
    local cLen = math.sqrt(cxDir * cxDir + cyDir * cyDir)
    local expected = Config.babyLookTravel / cLen
    check(approx(ex7 - tx, cxDir * expected, 0.01) and approx(ey7 - ty, cyDir * expected, 0.01),
        "blick-transit: exakt radial zum Kern (Travel)")
    Bridge.update(0.5)
    check(Render.babyIsTransiting() == false, "blick-transit: Transit beendet")

    -- Weg von der Brücke (damit kein Bridge-Ready dazwischenfunkt):
    -- Blink-State gewinnt über normal; danach wieder normal. Frischer
    -- Visual-State (kein hängender Push-Zähler aus dem Push-Abschnitt).
    Render.resetPlayerVisual()
    State.player.ring = "inner"
    State.player.angle = 90
    State.baby.ring = "inner"
    State.baby.angle = 90
    check(Render.babyBridgeReady() == false, "blick-blink: kein Bridge-Ready (Vorbereitung)")
    Render.babyVisual.blinkFramesRemaining = Config.babyBlinkFrames
    check(Render.babyEyeState() == "blink", "blick-blink: Blink aktiv -> Blink-State")
    Render.babyVisual.blinkFramesRemaining = 0
    check(Render.babyEyeState() == "normal", "blick-blink: nach Blink -> normal")
end

-- --- Baby-Polish: Reaktionspriorität ---------------------------------------
do
    setup(Levels[2])
    Render.resetPlayerVisual()
    -- Push schlägt Blink
    Render.babyVisual.blinkFramesRemaining = 2
    Render.noteBabyPush(1)
    check(Render.babyEyeState() == "push", "polish priorität: Push schlägt Blink")
    -- Bridge-Ready schlägt Push (Baby am aktiven Dock, Player dahinter)
    State.player.angle = 176
    State.baby.angle = 184
    Render.noteBabyPush(1)
    check(Render.babyEyeState() == "bridge", "polish priorität: Bridge-Ready schlägt Push")
    -- Landing (Ankunft nach Brückentransit) schlägt Idle/Push
    Render.noteBabyPush(1)
    Render.noteBabyLanding()
    check(Render.babyEyeState() == "landing", "polish priorität: Landing schlägt Push/Idle")
    -- Blocked schlägt Blink, Push schlägt Blocked. Frischer Visual-State
    -- (Landing-Zähler abgeräumt) und weg von der Brücke (kein Bridge-Ready,
    -- das sonst höhere Priorität hätte).
    Render.resetPlayerVisual()
    State.player.angle = 90
    State.baby.angle = 90
    Render.babyVisual.blinkFramesRemaining = 2
    Render.noteBabyBlocked(true)
    check(Render.babyEyeState() == "blocked", "polish priorität: Blocked schlägt Blink")
    Render.noteBabyPush(1)
    check(Render.babyEyeState() == "push", "polish priorität: Push schlägt Blocked")
end

-- --- Baby-Blocked-Reaktion (Referenz, rein visuell) -------------------------
-- Wird das Baby tatsächlich gegen eine Blockade gedrückt: sehr kurze Reaktion
-- (Squint-Linie + minimale Kompression), schwächer als der Player, kein
-- Retrigger bei gehaltener Blockade.
do
    setup(Levels[2])
    Render.resetPlayerVisual()
    check(Render.babyEyeState() == "normal", "blocked: Start normal")
    Render.noteBabyBlocked(true)
    check(Render.babyEyeState() == "blocked", "blocked: Reaktion aktiv")
    check(Render.babyVisual.blockedFramesRemaining == Config.babyBlockedFrames,
        "blocked: Reaktionsdauer = babyBlockedFrames")
    -- Gehaltenes Drücken gegen dieselbe Blockade: kein Retrigger/keine
    -- Verlängerung über babyBlockedFrames hinaus.
    Render.noteBabyBlocked(true)
    check(Render.babyVisual.blockedFramesRemaining == Config.babyBlockedFrames,
        "blocked: keine Verlängerung bei gehaltener Blockade")
    -- Freigabe setzt die Flanke zurück; der nächste Stoß retriggert.
    Render.noteBabyBlocked(false)
    check(Render.babyVisual.wasBlockedLastFrame == false, "blocked: Flanke zurückgesetzt")
    Render.noteBabyBlocked(true)
    check(Render.babyVisual.blockedFramesRemaining == Config.babyBlockedFrames,
        "blocked: neuer Stoß retriggert (Flanke)")
    -- Reaktion klingt ab (zurück zu normal).
    for _ = 1, Config.babyBlockedFrames do
        Render.update(0.016, false)
    end
    check(Render.babyEyeState() == "normal", "blocked: klingt ab")
end

-- --- Baby-Dock: kontextuelle Sichtbarkeit (Referenz-Variante A) ------------
-- Das Dock aus vier Eckmarken erscheint NUR, wenn die konkrete Brücke relevant
-- ist: Baby auf demselben Ring wie der Player, Brücke aktiv, beide in
-- sinnvoller Nähe, kein Transit. NICHT „Baby irgendwo auf dem Ring -> sofort“.
do
    setup(Levels[2]) -- B0 frei/aktiv @180, Baby outer@60
    local b0 = State.room.bridges[1]
    check(b0.id == "B0" and b0.angle == 180, "dock: B0 vorhanden (Vorbereitung)")

    -- Baby und Player weit von der Brücke: kein Dock.
    State.player.ring = "outer"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 300
    check(Render.babyDockForBridge(b0) == false, "dock: weit weg -> kein Dock")

    -- Beide auf demselben Ring, nahe der aktiven Brücke: Dock sichtbar.
    State.player.angle = 170
    State.baby.angle = 190
    check(Render.babyDockForBridge(b0) == true, "dock: Player+Baby nahe aktiver Brücke -> Dock")

    -- Baby fern, Player nahe: kein Dock.
    State.player.angle = 170
    State.baby.angle = 300
    check(Render.babyDockForBridge(b0) == false, "dock: Baby fern -> kein Dock")

    -- Baby nahe, Player fern: kein Dock.
    State.player.angle = 300
    State.baby.angle = 190
    check(Render.babyDockForBridge(b0) == false, "dock: Player fern -> kein Dock")

    -- Verschiedene Ringe: Shared Transit grundsätzlich nicht möglich -> kein Dock.
    State.player.ring = "inner"
    State.player.angle = 170
    State.baby.ring = "outer"
    State.baby.angle = 190
    check(Render.babyDockForBridge(b0) == false, "dock: verschiedene Ringe -> kein Dock")

    -- Inaktive Brücke: kein Dock.
    State.player.ring = "outer"
    State.player.angle = 170
    State.baby.ring = "outer"
    State.baby.angle = 190
    State.elementStates[b0.id] = false
    check(Render.babyDockForBridge(b0) == false, "dock: inaktive Brücke -> kein Dock")
    State.elementStates[b0.id] = true

    -- Während eines Transits: kein Dock.
    State.player.angle = 176
    State.baby.angle = 184
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "dock: A -> gemeinsamer Transit (Vorbereitung)")
    check(Bridge.isCrossing() == true, "dock: Transit aktiv")
    check(Render.babyDockForBridge(b0) == false, "dock: während Transit -> kein Dock")
    Bridge.update(0.5)
    check(Bridge.isCrossing() == false, "dock: Transit beendet")
    -- Nach der Landung (Paar auf inner, B0 zweiwegig) ist das Dock wieder relevant.
    check(Render.babyDockForBridge(b0) == true, "dock: nach Transit wieder sichtbar (zweiwegige Brücke)")
end

-- --- Baby-Dock: Ready-Feedback (einmalig, kein Puls) ------------------------
do
    setup(Levels[2])
    Render.resetObjectAnims()
    -- Kein Transfer bereit -> kein Feedback.
    State.player.angle = 300
    State.baby.angle = 300
    Render.updateObjectAnimations(0.016)
    local f0 = (Render.babyDockFeedbackFrames and Render.babyDockFeedbackFrames["B0"]) or 0
    check(f0 == 0, "dock-feedback: weit weg kein Feedback")

    -- Transfer bereit -> einmaliges Feedback startet (setzt auf
    -- babyDockReadyFrames und wird im selben updateObjectAnimations-Lauf auf
    -- babyDockReadyFrames-1 abgebaut) und klingt danach aus.
    State.player.angle = 176
    State.baby.angle = 184
    Render.updateObjectAnimations(0.016)
    local f1 = (Render.babyDockFeedbackFrames and Render.babyDockFeedbackFrames["B0"]) or 0
    check(f1 > 0 and f1 <= Config.babyDockReadyFrames, "dock-feedback: bereit -> Feedback startet")
    for _ = 1, Config.babyDockReadyFrames + 2 do
        Render.updateObjectAnimations(0.016)
    end
    local f2 = (Render.babyDockFeedbackFrames and Render.babyDockFeedbackFrames["B0"]) or 0
    check(f2 == 0, "dock-feedback: Feedback klingt aus (kein Puls/Blinken)")
end

-- --- Baby-Polish: Bridge-Ready (read-only) ----------------------------------
do
    setup(Levels[2])
    check(Render.babyBridgeReady() == false, "polish ready: Start nicht bereit")
    State.player.angle = 176
    State.baby.angle = 184
    check(Render.babyBridgeReady() == true, "polish ready: bereit an aktiver Brücke")
    -- Während des Transits ist kein Dock bereit
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "polish ready: A -> gemeinsamer Transfer")
    check(Bridge.isCrossing() == true, "polish ready: Transit aktiv")
    check(Render.babyBridgeReady() == false, "polish ready: während Transit nicht bereit")
    Bridge.update(0.5)
    check(State.baby.ring == "inner" and State.player.ring == "inner", "polish ready: beide auf inner")
    -- B0 ist frei/zweiwegig: das Paar landet als Dock-Ready am selben Dock —
    -- ein weiteres A schickt beide GEMEINSAM zurück (Paar-Metapher).
    check(Render.babyBridgeReady() == true, "polish ready: Paar am Dock wieder bereit (zweiwegige Brücke)")
end

-- --- Baby-Polish: Brückentransfer-Kette (Baby zuerst, Player danach) -------
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "polish transfer: A -> gemeinsamer Transit")
    check(Bridge.isCrossing() == true, "polish transfer: Transit läuft")
    check(State.player.ring == "outer" and State.baby.ring == "outer", "polish transfer: vor Abschluss beide outer")
    Bridge.update(0.5)
    check(State.baby.ring == "inner", "polish transfer: Baby auf inner")
    check(State.player.ring == "inner", "polish transfer: Player auf inner")
    check(Bridge.isCrossing() == false, "polish transfer: Transit beendet")
end

-- --- Baby-Polish: Reset des transienten Visual-State ------------------------
do
    setup(Levels[2])
    Render.resetPlayerVisual()
    Render.noteBabyPush(1)
    Render.noteBabyLanding() -- höhere Priorität: setzt Push auf 0, Landing aktiv
    check(Render.babyVisual.landingFramesRemaining > 0 and Render.babyVisual.pushFramesRemaining == 0,
        "polish reset: Landing-Reaktion aktiv, Push überstimmt (Vorbereitung)")
    -- Raumstart/Restart (Render.resetPlayerVisual) setzt den visuellen Zustand zurück
    Render.resetPlayerVisual()
    check(Render.babyVisual.pushFramesRemaining == 0 and Render.babyVisual.landingFramesRemaining == 0,
        "polish reset: ResetPlayerVisual setzt Baby-Visual zurück")
    -- Undo setzt den visuellen Zustand ebenfalls zurück
    Render.noteBabyPush(1)
    Render.noteUndo()
    check(Render.babyVisual.pushFramesRemaining == 0,
        "polish reset: noteUndo setzt Baby-Visual zurück")
end

-- --- Baby-Shutter-Kollision (Regression-Fix) -------------------------------
-- Das Baby darf NIEMALS in ein geschlossenes Segment hineingeschoben werden.
-- Eigener Raum: Baby + geschlossene Blende D1@83 (Bogen [70,96], S1=A).
do
    local function makeBabyShutterRoom()
        return {
            name = "BabyShutter",
            rings = { outer = 7, inner = 6 },
            start = { ring = "outer", angle = 0 },
            baby = { start = { ring = "outer", angle = 60 } },
            switches = {
                { id = "S1", ring = "outer", angle = 200, symbol = 1, onA = "B1", onB = "D1", state = "A" },
            },
            shutters = {
                { id = "D1", ring = "outer", angle = 83 }, -- Bogen [70,96], geschlossen
            },
            bridges = {
                { id = "B0", angle = 180, free = true },
                { id = "B1", angle = 300, free = false },
            },
            gate = { id = "T", angle = 0, free = true },
        }
    end
    local contact = Baby.contactDeg()
    -- Stoppmarge = sichtbare Baby-Silhouette auf dem Ring des Babys (hier
    -- outer, da die Blende auf dem äußeren Ring liegt). Deutlich kleiner als
    -- contactDeg -> das Baby steht optisch direkt an der Kante (0-1 px).
    local sMargin = Baby.shutterMarginDeg("outer")
    local visibleEdgeDeg = (Config.babyRadius + Config.babyStroke) / Config.outerRadius * (180 / math.pi)
    local pxToDeg = 1 / Config.outerRadius * (180 / math.pi)

    -- CW: Player schiebt Baby gegen die geschlossene Blende -> stoppt direkt davor.
    do
        setup(makeBabyShutterRoom())
        State.player.angle = 40
        State.baby.angle = 60
        local _, res = Room.movePlayer(60)
        -- Player-Sweep stoppt an der Blendenkante 70 (blocked); das Baby wird
        -- bis 70 - sMargin geschoben und NICHT in den Bogen [70,96].
        check(approx(State.baby.angle, 70 - sMargin, 0.5), "bcoll-cw: Baby stoppt direkt an der Blende")
        check(State.baby.angle < 70, "bcoll-cw: Baby nicht im Segment (Winkel < 70)")
        check(approx(State.player.angle, 70 - sMargin - contact, 0.5), "bcoll-cw: Player im Kontaktabstand hinter dem Baby")
        -- Sichtbarer Abstand der Silhouette (Körper + Kontur) zur Shutterkante:
        -- 0-1 px (nominal babyShutterGapPx), nie negativ (kein Overlap).
        local gapCw = (70 - State.baby.angle) - visibleEdgeDeg
        check(gapCw >= -0.001 and gapCw <= pxToDeg + 0.001,
            "bcoll-cw: sichtbarer Abstand 0-1 px zur Shutterkante")
        check(State.baby.angle + visibleEdgeDeg < 70,
            "bcoll-cw: sichtbare Silhouette bleibt außerhalb der Shutterfläche")
        -- Formation: Player steht exakt im Figurenkontakt hinter dem Baby.
        check(approx(State.baby.angle - State.player.angle, contact, 0.5),
            "bcoll-cw: Formation Player-hinter-Baby")
        check(res.babyMoved == true, "bcoll-cw: babyMoved true")
        check(res.blocked == true, "bcoll-cw: blocked true (Impact-Sound)")
        -- Gehaltenes Drücken: kein weiteres Eindringen, kein Undo-Spam.
        local undoBefore = Undo.count()
        Room.movePlayer(30)
        check(approx(State.baby.angle, 70 - sMargin, 0.5), "bcoll-cw-held: Baby bleibt direkt an der Blende")
        check(State.baby.angle < 70, "bcoll-cw-held: kein Eindringen bei gehaltenem Push")
        check(Undo.count() == undoBefore, "bcoll-cw-held: kein Undo-Spam")
    end

    -- CCW: Player schiebt Baby von der anderen Seite gegen die Blende.
    do
        setup(makeBabyShutterRoom())
        State.player.angle = 140
        State.baby.angle = 110
        local _, res = Room.movePlayer(-50)
        -- CCW-Eintrittskante bei 96; Baby stoppt bei 96 + sMargin.
        check(approx(State.baby.angle, 96 + sMargin, 0.5), "bcoll-ccw: Baby stoppt direkt an der Blende")
        check(State.baby.angle > 96, "bcoll-ccw: Baby nicht im Segment (Winkel > 96)")
        check(approx(State.player.angle, 96 + sMargin + contact, 0.5), "bcoll-ccw: Player im Kontaktabstand hinter dem Baby")
        local gapCcw = (State.baby.angle - 96) - visibleEdgeDeg
        check(gapCcw >= -0.001 and gapCcw <= pxToDeg + 0.001,
            "bcoll-ccw: sichtbarer Abstand 0-1 px zur Shutterkante")
        check(State.baby.angle - visibleEdgeDeg > 96,
            "bcoll-ccw: sichtbare Silhouette bleibt außerhalb der Shutterfläche")
        check(approx(State.player.angle - State.baby.angle, contact, 0.5),
            "bcoll-ccw: Formation Player-hinter-Baby")
        check(res.babyMoved == true, "bcoll-ccw: babyMoved true")
        check(res.blocked == true, "bcoll-ccw: blocked true")
    end

    -- Große Deltas (D-Pad/Crank): kein Tunneling durch die Blende.
    do
        setup(makeBabyShutterRoom())
        State.player.angle = 40
        State.baby.angle = 60
        Room.movePlayer(340) -- sehr großes CW-Delta
        check(State.baby.angle < 70, "bcoll-tunnel-cw: kein Tunneling (Baby < 70)")
        check(approx(State.baby.angle, 70 - sMargin, 0.5), "bcoll-tunnel-cw: Baby exakt davor")
        setup(makeBabyShutterRoom())
        State.player.angle = 140
        State.baby.angle = 110
        Room.movePlayer(-300) -- sehr großes CCW-Delta
        check(State.baby.angle > 96, "bcoll-tunnel-ccw: kein Tunneling (Baby > 96)")
        check(approx(State.baby.angle, 96 + sMargin, 0.5), "bcoll-tunnel-ccw: Baby exakt davor")
    end

    -- Renderposition entspricht dem kollisionssicheren State (Render liest
    -- State.baby.angle direkt; kein separater visueller Winkel). Zusätzlich
    -- Pixel-Nachweis: die schwarze Baby-Kontur bleibt ~0-1 px vor der
    -- Shutterkante auf dem Bildschirm (kein sichtbarer Overlap).
    do
        setup(makeBabyShutterRoom())
        State.player.angle = 40
        State.baby.angle = 60
        Room.movePlayer(60)
        local rx, ry, ra = Render.babyScreenPosition()
        check(rx ~= nil and approx(ra, State.baby.angle, 0.5),
            "bcoll-render: Renderposition entspricht kollisionssicherem State")
        check(State.baby.angle < 70, "bcoll-render: State außerhalb des Segments")
        -- Pixelabstand Baby-Mitte -> Shutterkante (70°) minus sichtbarem Rand.
        local ringPx = Render.babyRadius()
        local ex, ey = Geometry.polar(Config.centerX, Config.centerY, ringPx, 70)
        local screenGapPx = math.sqrt((rx - ex) ^ 2 + (ry - ey) ^ 2) - (Config.babyRadius + Config.babyStroke)
        check(screenGapPx >= -0.01 and screenGapPx <= 1.5,
            "bcoll-render: sichtbarer Pixelabstand 0-1 px zur Shutterkante")
    end

    -- Dock Assist nahe einer Bridge + geschlossene Blende nahe: Assist darf
    -- das Hindernis NICHT ignorieren (auch mit Baby im Raum).
    do
        local room = {
            name = "AssistBabyBlock",
            rings = { outer = 7, inner = 6 },
            start = { ring = "outer", angle = 87 },
            baby = { start = { ring = "outer", angle = 30 } },
            switches = {
                { id = "S1", ring = "outer", angle = 45, symbol = 1, onA = "B2", onB = "D1", state = "A" },
            },
            shutters = { { id = "D1", ring = "outer", angle = 101 } }, -- Bogen [88,114] geschlossen
            bridges = {
                { id = "B0", angle = 90, free = true },
                { id = "B2", angle = 270, free = false },
            },
            gate = { id = "T", angle = 180, free = true },
        }
        setup(room)
        check(Room.shutters["D1"].collisionActive == true, "assist-baby: Blende geschlossen")
        Room.updateDockAssist()
        check(Room.isDockAssisting() == false, "assist-baby: keine Assistenz durch geschlossene Blende")
        check(approx(State.player.angle, 87), "assist-baby: Player unverändert")
    end
end

-- --- Player-Auge beim GEMEINSAMEN Brückentransit (Pass „Player-Eye“) --------
-- Ready-Gaze, Transit-Fokus, Mid-Bridge-Clamp, Landing-Squint und der kurze
-- Blick zum Baby nach der Ankunft — jeweils rein visuell, kein Gameplay-Effekt.
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    Render.resetPlayerVisual()

    -- Ready: Pupille zeigt radial zur Brücke (nicht neutral tangential). Basis
    -- ist die Ready-Formation (playerScreenPosition == playerEyePosition-
    -- Winkelauflösung, Auge liegt im Körper).
    check(Render.babyBridgeReady() == true, "eye-ready: Shared-Transfer bereit")
    local baseX, baseY = Render.playerScreenPosition()
    local px, py = Render.playerEyePosition()
    local vx, vy = px - baseX, py - baseY
    local cx, cy = Config.centerX - baseX, Config.centerY - baseY
    local cross = vx * cy - vy * cx
    check(baseX ~= nil and math.abs(cross) < 0.01, "eye-ready: Pupille radial zur Brücke")

    -- A -> Transit: der Transit-Eye-State gewinnt über alles.
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "eye-transit: Shared-Transit")
    check(Render.currentEyeReaction() == "transit", "eye-transit: Transit-State gewinnt")
    -- Transit-Fokus: Pupille bleibt per Clamp im Playerkörper.
    local fpx, fpy = Render.playerEyePosition()
    local fsx, fsy = Render.playerScreenPosition()
    local foff = math.sqrt((fpx - fsx) ^ 2 + (fpy - fsy) ^ 2)
    check(foff + Config.pupilRadius + Config.transitFocusPupilBoost <= Config.playerRadius + 0.01,
        "eye-transit: Pupille bleibt im Playerkörper (Clamp)")

    -- Mid-Bridge: Auge bleibt sichtbar/innerhalb des Körpers.
    Bridge.update(0.15)
    local mpx, mpy = Render.playerEyePosition()
    local msx, msy = Render.playerScreenPosition()
    local moff = math.sqrt((mpx - msx) ^ 2 + (mpy - msy) ^ 2)
    check(moff + Config.pupilRadius <= Config.playerRadius + 0.01,
        "eye-mid: Pupille innerhalb des Playerkörpers")

    -- Landing: kurzer Landing-Squint (Lidlinie), danach wieder normal.
    Bridge.update(0.4) -- Transit abschließen
    check(Bridge.isCrossing() == false, "eye-landing: Transit beendet")
    Render.notePlayerLanding()
    check(Render.currentEyeReaction() == "landing", "eye-landing: Landing-Squint aktiv")
    for _ = 1, Config.landingSquintFrames do
        Render.update(0.02, false)
    end
    check(Render.currentEyeReaction() == "normal", "eye-landing: nach Squint wieder normal")

    -- Post-Landing: kurzer Blick zum Baby, danach normale Eye-Logik.
    check(Render.playerVisual.lookAtBabyFramesRemaining > 0, "eye-post: Blick-zum-Baby aktiv")
    local lpx, lpy = Render.playerEyePosition()
    local lsx, lsy = Render.playerScreenPosition()
    check(math.abs(lpx - lsx) > 0.01 or math.abs(lpy - lsy) > 0.01,
        "eye-post: Pupille Richtung Baby versetzt")
    for _ = 1, Config.lookAtBabyFrames + 2 do
        Render.update(0.02, false)
    end
    check(Render.playerVisual.lookAtBabyFramesRemaining == 0, "eye-post: Blick-Frames abgelaufen")
    check(Render.currentEyeReaction() == "normal", "eye-post: normale Eye-Logik wieder aktiv")
end

-- --- Regression: Auge nach der Landung IM Playerkörper --------------------
-- Auf einer zweiwegigen Brücke ist das Paar nach der Landung sofort wieder
-- dock-bereit (Ready-Formation). Das Auge muss am gleichen Winkel wie der
-- Körper liegen (playerScreenPosition == playerEyePosition-Winkelauflösung) —
-- vorher wurde das Auge am Achs-Winkel gezeichnet und schwebte neben dem
-- Körper im Hintergrund („Auge weg“).
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    Room.tryUseConnection()
    check(Bridge.isCrossing(), "eye-nachland: Shared-Transit gestartet")
    Bridge.update(0.5) -- Abschluss -> Paar auf inner
    check(Render.babyBridgeReady() == true, "eye-nachland: Paar dock-bereit (zweiwegig)")
    local bx, by = Render.playerScreenPosition()
    local ex, ey = Render.playerEyePosition()
    local dist = math.sqrt((ex - bx) ^ 2 + (ey - by) ^ 2)
    check(bx ~= nil and ex ~= nil and dist <= Config.playerRadius,
        "eye-nachland: Auge liegt im Playerkörper")
    -- Auch im Ready-Zustand VOR dem Transfer (Formation) liegt das Auge im Körper.
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    check(Render.babyBridgeReady() == true, "eye-ready-pos: bereit vor A")
    local rx, ry = Render.playerScreenPosition()
    local rex, rey = Render.playerEyePosition()
    local rdist = math.sqrt((rex - rx) ^ 2 + (rey - ry) ^ 2)
    check(rx ~= nil and rex ~= nil and rdist <= Config.playerRadius,
        "eye-ready-pos: Auge liegt im Playerkörper (Ready-Formation)")
end

TestReport.baby = { pass = pass, fail = fail }
