-- Tests für die Baby-Mechanik (generisch, Raum 2) + Raum-1-Regression.
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
local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    Camera.init(room.rings.outer)
end

-- --- Raum 1: unverändert + kein Baby ---------------------------------------
do
    local r1 = Levels[1]
    check(r1.name == "Ein Anlauf", "room1: Name")
    check(r1.rings.outer == 7 and r1.rings.inner == 6, "room1: Ringe 7/6")
    check(r1.start.ring == "outer" and r1.start.angle == 0, "room1: Start outer@0")
    check(#r1.switches == 1, "room1: genau 1 Schalter")
    local s = r1.switches[1]
    check(s.id == "S1" and s.ring == "outer" and s.angle == 90 and s.symbol == 1, "room1: S1 Geometrie")
    check(s.onA == "B1" and s.onB == "D1" and s.state == "B", "room1: S1 onA/onB/state")
    check(#r1.shutters == 1 and r1.shutters[1].id == "D1" and r1.shutters[1].ring == "outer" and r1.shutters[1].angle == 315, "room1: D1")
    check(#r1.bridges == 1 and r1.bridges[1].id == "B1" and r1.bridges[1].angle == 270 and r1.bridges[1].free == false, "room1: B1")
    check(r1.gate.id == "T" and r1.gate.angle == 180 and r1.gate.free == true, "room1: Gate")
    check(r1.baby == nil, "room1: kein Baby")
    setup(Levels[1])
    check(State.baby == nil, "room1 state: State.baby nil")
end

-- --- Raum 1: Lösungsweg funktioniert unverändert ---------------------------
do
    setup(Levels[1])
    -- CW 0 -> 100: S1@90 CW überquert -> A (B1 aus, D1 zu)
    Room.movePlayer(100)
    check(State.switchStates["S1"] == "A", "room1 lösung: S1 auf A")
    check(State.elementStates["B1"] == true, "room1 lösung: B1 ausgefahren")
    check(State.elementStates["D1"] == false, "room1 lösung: D1 geschlossen")
    -- CW weiter zu B1@270, A -> Brücke, inner
    Room.movePlayer(170)
    check(approx(State.player.angle, 270), "room1 lösung: Player bei 270")
    local res = Room.tryUseConnection()
    check(res.used and res.kind == "bridge", "room1 lösung: A -> Brücke")
    Bridge.update(0.5)
    check(State.player.ring == "inner", "room1 lösung: Player auf inner")
    -- CCW 270 -> 180: Gate T@180 (frei) -> abgeschlossen
    Room.movePlayer(-90)
    check(approx(State.player.angle, 180), "room1 lösung: Player am Gate 180")
    local gres = Room.tryUseConnection()
    check(gres.used and gres.kind == "gate" and gres.roomComplete == true, "room1 lösung: Gate -> abgeschlossen")
end

-- --- Raum 2: Baby-Initialisierung + Gate gesperrt --------------------------
do
    local r2 = Levels[2]
    check(r2.name == "Nicht allein", "room2: Name")
    check(r2.rings.outer == 6 and r2.rings.inner == 5, "room2: Ringe 6/5")
    check(r2.baby ~= nil and r2.baby.start.ring == "outer" and r2.baby.start.angle == 60, "room2: Baby-Start")
    check(r2.baby.goal.ring == "inner" and r2.baby.goal.angle == 300, "room2: Baby-Ziel")
    check(#r2.switches == 0 and #r2.shutters == 0, "room2: keine Schalter/Blenden")
    check(#r2.bridges == 1 and r2.bridges[1].id == "B0" and r2.bridges[1].free == true and r2.bridges[1].angle == 180, "room2: B0 frei @180")
    check(r2.gate.id == "T" and r2.gate.angle == 0 and r2.gate.babyLocked == true, "room2: Gate babyLocked @0")

    setup(Levels[2])
    check(State.baby ~= nil, "room2 state: Baby vorhanden")
    check(State.baby.ring == "outer" and State.baby.angle == 60, "room2 state: Baby Startposition")
    check(State.baby.settled == false, "room2 state: Baby nicht eingerastet")
    check(State.baby.lastPushDirection == 1, "room2 state: lastPushDirection CW")
    check(State.elementStates["B0"] == true, "room2 state: B0 aktiv")
    check(State.elementStates["T"] == false, "room2 state: Gate inaktiv")
    check(Gate.isUsable(r2.gate, "inner", 0) == false, "room2: Gate vor Ziel gesperrt")
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
    local total = Config.sharedBridgeHold + Config.sharedBridgeDuration + Config.sharedBabyLead
    Bridge.update(total * 0.5) -- halb durch
    local bp = Bridge.getBabyTransitProgress() or 0
    local pp = Bridge.getTransitProgress() or 0
    check(bp > 0 and bp < 1, "shared mid: Baby mitten auf der Brücke (kein Teleport)")
    check(bp > pp, "shared mid: Baby-Fortschritt > Player-Fortschritt (voraus)")
    Bridge.update(total)
    check(State.player.ring == "inner" and State.baby.ring == "inner", "shared mid: nach Abschluss beide inner")
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

-- --- Ziel: Einrasten + Gate ------------------------------------------------
do
    setup(Levels[2])
    State.player.ring = "inner"
    State.player.angle = 180
    State.baby.ring = "inner"
    State.baby.angle = 190
    check(Gate.isUsable(Levels[2].gate, "inner", 0) == false, "gate: vor Ziel gesperrt")
    Room.movePlayer(112)
    check(State.baby.settled == true, "goal: Baby eingerastet")
    check(State.baby.ring == "inner" and approx(State.baby.angle, 300), "goal: Baby exakt im Ziel 300")
    check(State.elementStates["T"] == true, "goal: Gate aktiv")
    check(Gate.isUsable(Levels[2].gate, "inner", 0) == true, "gate: nach Ziel benutzbar")
    -- eingerastetes Baby ist unverrückbar
    local before = State.baby.angle
    Room.movePlayer(30)
    check(State.baby.angle == before and State.baby.settled == true, "goal: eingerastetes Baby unbeweglich")
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
    check(State.baby.settled == false, "undo: settled wiederhergestellt")
end

-- --- Restart (State.init = frischer Raum) ----------------------------------
do
    setup(Levels[2])
    State.player.ring = "inner"
    State.player.angle = 180
    State.baby.ring = "inner"
    State.baby.angle = 190
    Room.movePlayer(112)
    check(State.baby.settled == true, "restart: vorher eingerastet")
    setup(Levels[2])
    check(State.player.ring == "outer" and State.player.angle == 0, "restart: Player zurück outer@0")
    check(State.baby.ring == "outer" and approx(State.baby.angle, 60), "restart: Baby zurück outer@60")
    check(State.baby.settled == false, "restart: settled false")
    check(State.elementStates["T"] == false, "restart: Gate inaktiv")
end

-- --- Raumwechsel-Cleanup (kein Baby-Leak) ----------------------------------
do
    setup(Levels[2])
    check(State.baby ~= nil, "wechsel: Baby in Raum 2 vorhanden")
    setup(Levels[1])
    check(State.baby == nil, "wechsel: kein Baby-State in Raum 1")
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
    check(Render.babyRadius() == nil, "render: kein Baby in Raum 1 -> nil")
end

-- --- Vollständige deterministische Raum-2-Lösung ---------------------------
do
    setup(Levels[2])
    -- 1) Player CW 0 -> 176 schiebt Baby 60 -> ~184 (Richtung Brücke B0@180)
    Room.movePlayer(176)
    check(approx(State.player.angle, 176), "lösung: Player bei 176 (outer)")
    check(approx(State.baby.angle, 184, 0.5), "lösung: Baby bei ~184 (outer)")
    -- 2) EIN A -> gemeinsamer Transfer (Player + Baby zusammen)
    local res2 = Room.tryUseConnection()
    check(res2.used == true and res2.kind == "sharedBridge", "lösung: A -> gemeinsamer Transfer")
    Bridge.update(0.5)
    check(State.baby.ring == "inner" and approx(State.baby.angle, 190), "lösung: Baby auf inner@190")
    check(State.player.ring == "inner" and approx(State.player.angle, 180), "lösung: Player auf inner@180")
    -- 4) Player CW schiebt Baby bis ins Ziel (180 -> 292, Baby 190 -> 300)
    Room.movePlayer(112)
    check(State.baby.settled == true, "lösung: Baby eingerastet")
    check(State.baby.ring == "inner" and approx(State.baby.angle, 300), "lösung: Baby im Ziel 300")
    check(State.elementStates["T"] == true, "lösung: Gate aktiv")
    -- 5) Player weiter CW zum Gate (292 -> 0), Raum abschließen
    Room.movePlayer(68)
    check(approx(State.player.angle, 0), "lösung: Player am Gate 0")
    local res5 = Room.tryUseConnection()
    check(res5.used == true and res5.kind == "gate" and res5.roomComplete == true, "lösung: Gate -> Raum abgeschlossen")
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
    -- Intervall: 3.0 + 0.5*(7.0-3.0) = 5.0 s
    check(approx(Render.babyVisual.nextBlinkAt, 5.0, 1e-6), "polish blink: Termin 5 s (seeded)")
    -- Vor Ablauf kein Blink
    for _ = 1, 49 do
        Render.update(0.1, false)
    end
    check(Render.babyVisual.blinkFramesRemaining == 0, "polish blink: kein Blink vor Termin")
    -- Blinkphase startet bei ~5 s (Float-Toleranz: 1 Frame später als exakt)
    Render.update(0.1, false)
    Render.update(0.1, false)
    check(Render.babyVisual.blinkFramesRemaining == Config.babyBlinkFrames, "polish blink: Blinkphase startet")
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

-- --- Baby-Polish: Idle-Look + Bewegung resetet Idle ------------------------
do
    setup(Levels[2])
    Render.resetPlayerVisual()
    local bx, by = Render.babyScreenPosition()
    Render.babyVisual.idleTime = 0
    local ex0, ey0 = Render.babyEyePosition("normal", bx, by)
    Render.babyVisual.idleTime = Config.idleGazeDelay + 2
    local ex1, ey1 = Render.babyEyePosition("normal", bx, by)
    local d0 = math.sqrt((ex0 - bx) ^ 2 + (ey0 - by) ^ 2)
    local d1 = math.sqrt((ex1 - bx) ^ 2 + (ey1 - by) ^ 2)
    check(d1 > d0, "polish idle: Idle-Look verstärkt die Pupillenrichtung zum Player")
    check(approx(d0, Config.babyLookBase, 0.05), "polish idle: Basis-Awareness entspricht babyLookBase")
    -- Bewegung resetet die Baby-Idle-Zeit
    Render.babyVisual.idleTime = 3
    Render.notePlayerMovement(5)
    check(Render.babyVisual.idleTime == 0, "polish idle: Bewegung resetet Baby-Idle")
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
    -- Goal-Settle schlägt Idle
    Render.noteBabySettled()
    check(Render.babyEyeState() == "settle", "polish priorität: Goal-Settle schlägt Idle")
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
    Render.noteBabySettled() -- höhere Priorität: setzt Push auf 0, Settle aktiv
    check(Render.babyVisual.settleFramesRemaining > 0 and Render.babyVisual.pushFramesRemaining == 0,
        "polish reset: Settle-Reaktion aktiv, Push überstimmt (Vorbereitung)")
    -- Raumstart/Restart (Render.resetPlayerVisual) setzt den visuellen Zustand zurück
    Render.resetPlayerVisual()
    check(Render.babyVisual.pushFramesRemaining == 0 and Render.babyVisual.settleFramesRemaining == 0,
        "polish reset: ResetPlayerVisual setzt Baby-Visual zurück")
    -- Undo setzt den visuellen Zustand ebenfalls zurück
    Render.noteBabyPush(1)
    Render.noteUndo()
    check(Render.babyVisual.pushFramesRemaining == 0,
        "polish reset: noteUndo setzt Baby-Visual zurück")
end

-- --- Gemeinsamer Transit: kein konkurrierendes A + Reset + Visual-Priorität --
do
    setup(Levels[2])
    State.player.angle = 176
    State.baby.angle = 184
    local res = Room.tryUseConnection()
    check(res.used == true and res.kind == "sharedBridge", "shared2: A -> gemeinsamer Transit")
    -- Während des Transits ist keine weitere A-Aktion möglich (kein zweites A)
    local resMid = Room.tryUseConnection()
    check(resMid.used == false, "shared2: während Transit kein zweites A")
    -- Visual-Priorität: Transit schlägt alle anderen Baby-Reaktionen
    Render.noteBabyPush(-1)
    check(Render.babyEyeState() == "transit", "shared2: Transit-Priorität im Visual-State")
    -- Reset (Restart/Raumwechsel via startRoom ruft Bridge.resetTransit)
    Bridge.resetTransit()
    check(Bridge.isCrossing() == false, "shared2: Reset beendet den Transit")
    check(State.player.ring == "outer" and State.baby.ring == "outer", "shared2: kein State-Leak nach Reset")
end

TestReport.baby = { pass = pass, fail = fail }
