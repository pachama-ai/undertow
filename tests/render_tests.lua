-- Tests für source/ui/render.lua (globale Tabelle Render): reine, read-only
-- Visual-Hilfsfunktionen. KEINE Pixel- oder Screenshot-Tests; die Grafik-
-- Abnahme erfolgt im Simulator-Playtest.
-- Erwartet, dass core/config, core/geometry, core/state, world/room und
-- ui/render per import geladen wurden (siehe tools/run_tests.ps1).
-- Am Ende wird das Ergebnis in TestReport.render gesammelt.

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
    return math.abs(a - b) <= (tolerance or 1e-9)
end

local function setup(room)
    State.init(room)
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    -- Render nutzt seit Phase 8.1 die Kamera: auf den äußeren Ring initialisieren.
    Camera.init(room.rings.outer)
end

-- Raum: S1 steuert D1 (S1=A -> D1 geschlossen) und B1; freie Brücke B0,
-- freies Gate.
local function makeRenderRoom()
    return {
        name = "Render",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="A" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
        },
        bridges = {
            { id="B0", angle=270, free=true  },
            { id="B1", angle=180, free=false },
        },
        gate = { id="T", angle=0, free=true },
    }
end

-- --- Ringradius ----------------------------------------------------------
do
    setup(makeRenderRoom()) -- rings 7/6, Camera.init(7)
    check(Render.ringRadius("outer") == Config.outerRadius, "ring: outer -> outerRadius")
    check(Render.ringRadius("inner") == Config.innerRadius, "ring: inner -> innerRadius")
    local okRing, _ = pcall(function() Render.ringRadius("core") end)
    check(okRing == false, "ring: unbekannter Ring -> Fehler")
end

-- --- Blenden-Visualzustand (G7-konsistent) -------------------------------
do
    setup(makeRenderRoom()) -- S1=A -> D1 (outer@90) logisch geschlossen, Spieler@0 außerhalb
    check(Render.shutterVisualState("D1") == "closed", "blende: collisionActive -> closed")
    check(Room.shutters["D1"].collisionActive == true, "blende: physical collisionActive true")
    -- pendingClose: Spieler in den Bogen setzen
    State.player.angle = 90
    Room.syncPhysicalShutters()
    check(Render.shutterVisualState("D1") == "pendingClose", "blende: pendingClose -> pendingClose")
    check(Room.shutters["D1"].collisionActive == false, "blende: pendingClose nicht kollisionsaktiv")
    -- wieder öffnen
    State.setSwitch("S1", "B") -- D1 aktiv (offen)
    Room.syncPhysicalShutters()
    check(Render.shutterVisualState("D1") == "open", "blende: logisch offen -> open")
end

-- --- Schalter-Visualzustand ----------------------------------------------
do
    setup(makeRenderRoom()) -- S1=A
    check(Render.switchVisualState("S1") == "A", "schalter: S1 A")
    State.setSwitch("S1", "B")
    check(Render.switchVisualState("S1") == "B", "schalter: S1 B")
end

-- --- Schalterdarstellung: beidseitig + aktive Seite (neue Regel) ------------
-- Der Schalter zeigt BEIDE Richtungen gleichzeitig (CW-Seite = Zustand A,
-- CCW-Seite = Zustand B). Die AKTIVE Seite ist gefüllt (Punkt + Richtungsnase),
-- die inaktive nur eine kleine Kontur (Mitte schwarz). Pixelprobe aus der
-- ECHTEN Render-Pipeline (drawRoom -> drawSwitch). Eigener Raum, damit die
-- Blende (sonst auf demselben Winkel) die Probe nicht verfälscht.
do
    local switchRoom = {
        name = "SwitchPixel",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = { { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" } },
        shutters = { { id = "D1", ring = "outer", angle = 45 } },
        bridges = { { id = "B0", angle = 270, free = true }, { id = "B1", angle = 180, free = false } },
        gate = { id = "T", angle = 0, free = true },
    }
    setup(switchRoom) -- S1=A, S1 outer@90

    -- Semantik-Helfer: welche tangentiale Seite ist aktiv?
    local sA = Render.switchSideState("S1")
    check(sA.cw == true and sA.ccw == false, "schalter-seiten: A -> CW-Seite aktiv")
    State.setSwitch("S1", "B")
    local sB = Render.switchSideState("S1")
    check(sB.cw == false and sB.ccw == true, "schalter-seiten: B -> CCW-Seite aktiv")
    State.setSwitch("S1", "A")

    -- Pixelbild: Offscreen-Canvas mit der ECHTEN Render-Pipeline (drawRoom ->
    -- drawSwitch). render.lua bindet gfx beim Laden; Sampling wie in input_tests.
    local gfxApi = playdate.graphics
    local function renderSwitchCanvas()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then
            error("schalter-canvas: " .. tostring(err))
        end
        return img
    end
    -- Anzahl weißer Pixel im (2*half+1)^2-Fenster um (cx,cy). Die gefüllte
    -- aktive Marke liefert deutlich mehr weiße Pixel als die dünne Kontur-Marke.
    local function countWhite(img, cx, cy, half)
        half = half or 1
        local n = 0
        for dy = -half, half do
            for dx = -half, half do
                local sx = math.floor(cx + dx + 0.5)
                local sy = math.floor(cy + dy + 0.5)
                if sx >= 0 and sy >= 0 and sx < 400 and sy < 240 then
                    if img:sample(sx, sy) == gfxApi.kColorWhite then
                        n = n + 1
                    end
                end
            end
        end
        return n
    end

    -- Markenpositionen (Variante C, Default): Schalter outer@90 -> (304,120);
    -- tangential CW = +y. Aktiver Punkt bei bodyR-2.9, inaktive Kontur bei
    -- bodyR-2.1. Der Test zielt auf die Default-Variante C (aktiver Punkt +
    -- gefüllte Richtungsnase vs. inaktive Kontur).
    local swX = 200 + Config.outerRadius * math.sin(math.rad(90))
    local swY = 120 - Config.outerRadius * math.cos(math.rad(90))
    local activeDist = Config.switchBodyRadius - 2.9
    local inactiveDist = Config.switchBodyRadius - 2.1
    local aX, aY = math.floor(swX + 0.5), math.floor(swY + activeDist + 0.5)
    local iX, iY = math.floor(swX + 0.5), math.floor(swY - inactiveDist + 0.5)

    -- S1=A: BEIDE Marken sichtbar; die aktive CW-Seite ist GEFÜLLT (Mitte
    -- weiß), die inaktive CCW-Seite nur Kontur (Mitte schwarz). Das ist die
    -- geforderte Lesbarkeit: aktive Richtung springt sofort ins Auge.
    State.setSwitch("S1", "A")
    local imgA = renderSwitchCanvas()
    local aCw = countWhite(imgA, aX, aY, 2)
    local aCcw = countWhite(imgA, iX, iY, 2)
    check(aCw > 0, "schalter-pixel: A -> CW-Seite sichtbar (aktiv, gefüllt)")
    check(aCcw > 0, "schalter-pixel: A -> CCW-Seite sichtbar (Kontur, beide Seiten)")
    check(imgA:sample(aX, aY) == gfxApi.kColorWhite, "schalter-pixel: A -> aktive CW-Marke gefüllt (Mitte weiß)")
    check(imgA:sample(iX, iY) ~= gfxApi.kColorWhite, "schalter-pixel: A -> inaktive CCW-Marke Kontur (Mitte schwarz)")

    -- S1=B: Seiten vertauscht (Zustandswechsel aktualisiert die Darstellung).
    State.setSwitch("S1", "B")
    local imgB = renderSwitchCanvas()
    local bCw = countWhite(imgB, aX, aY, 2)
    local bCcw = countWhite(imgB, iX, iY, 2)
    check(bCcw > 0, "schalter-pixel: B -> CCW-Seite sichtbar (aktiv, gefüllt)")
    check(imgB:sample(iX, iY) == gfxApi.kColorWhite, "schalter-pixel: B -> aktive CCW-Marke gefüllt (Mitte weiß)")
    check(imgB:sample(aX, aY) ~= gfxApi.kColorWhite, "schalter-pixel: B -> inaktive CW-Marke Kontur (Mitte schwarz)")
end

-- --- Brücken-/Gate-Visualzustand -----------------------------------------
do
    setup(makeRenderRoom()) -- S1=A -> B1 aktiv; B0 frei aktiv; T frei aktiv
    check(Render.bridgeVisualState("B0") == "active", "brücke: freie B0 aktiv")
    check(Render.bridgeVisualState("B1") == "active", "brücke: B1 aktiv (S1=A)")
    check(Render.bridgeVisualState("T") == "active", "gate: T aktiv (frei)")
    State.setSwitch("S1", "B") -- B1 inaktiv, D1 offen
    check(Render.bridgeVisualState("B1") == "inactive", "brücke: B1 inaktiv (S1=B)")
end

-- --- Brückendarstellung: aktiv durchgehend, inaktiv unterbrochen -----------
-- Aktive Brücken haben einen durchgehenden weißen Balken über die Lücke
-- zwischen den Ringen; inaktive Brücken zeigen dort Schwarz (sichtbarer
-- Spalt). Pixelprobe aus der ECHTEN Render-Pipeline (2 px tangential vom
-- Mittelpunkt entfernt, damit das schwarze Element-Symbol nicht stört).
do
    local gfxApi = playdate.graphics
    local function renderBridgeCanvas()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then error("bridge-canvas: " .. tostring(err)) end
        return img
    end
    local function bridgeSample(angle)
        local rMid = (Config.outerRadius + Config.innerRadius) / 2
        local mx = 200 + rMid * math.sin(math.rad(angle))
        local my = 120 - rMid * math.cos(math.rad(angle))
        local tx, ty = math.cos(math.rad(angle)), math.sin(math.rad(angle))
        return math.floor(mx + tx * 2 + 0.5), math.floor(my + ty * 2 + 0.5)
    end

    setup(makeRenderRoom()) -- S1=A: B0 frei aktiv@270, B1 aktiv@180, T aktiv@0
    local img = renderBridgeCanvas()
    local bx0, by0 = bridgeSample(270)
    local bx1, by1 = bridgeSample(180)
    check(img:sample(bx0, by0) == gfxApi.kColorWhite, "brücke-pixel: aktive B0 durchgehend (Lücke weiß)")
    check(img:sample(bx1, by1) == gfxApi.kColorWhite, "brücke-pixel: aktive B1 durchgehend (Lücke weiß)")

    -- S1=B -> B1 inaktiv: Spalt sichtbar (Mitte schwarz), B0 bleibt aktiv.
    State.setSwitch("S1", "B")
    local img2 = renderBridgeCanvas()
    check(img2:sample(bx1, by1) == gfxApi.kColorBlack, "brücke-pixel: inaktive B1 unterbrochen (Lücke schwarz)")
    check(img2:sample(bx0, by0) == gfxApi.kColorWhite, "brücke-pixel: B0 bleibt aktiv (Lücke weiß)")
end

-- --- Bridge-Ready-Impuls: nur Visual, kein Gameplay-State ------------------
do
    setup(makeRenderRoom()) -- B0 frei aktiv@270
    Render.resetObjectAnims() -- prevReady/bridgeReadyFrames frisch
    -- Player weit vom Dock: kein Ready-Impuls.
    State.player.ring = "outer"
    State.player.angle = 40
    Render.updateObjectAnimations(0.016)
    local f0 = (Render.bridgeReadyFrames and Render.bridgeReadyFrames["B0"]) or 0
    check(f0 == 0, "bridge-ready: weit weg kein Impuls")

    -- Player am Dock der aktiven Brücke B0@270 -> kurzer Frame-Impuls startet.
    State.player.angle = 270
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    Render.updateObjectAnimations(0.016)
    local f1 = (Render.bridgeReadyFrames and Render.bridgeReadyFrames["B0"]) or 0
    check(f1 > 0, "bridge-ready: am Dock startet Impuls (Frames=" .. tostring(f1) .. ")")
    -- rein visuell: Gameplay-State bleibt unverändert.
    local swSame, elSame = true, true
    for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
    for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
    for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
    for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
    check(swSame and elSame, "bridge-ready: nur Visual, State unverändert")
    -- Impuls läuft nach wenigen Frames aus (kein permanentes Blinken).
    for _ = 1, Config.bridgeReadyFrames + 2 do
        Render.updateObjectAnimations(0.016)
    end
    local f2 = (Render.bridgeReadyFrames and Render.bridgeReadyFrames["B0"]) or 0
    check(f2 == 0, "bridge-ready: Impuls klingt aus (kein Blinken)")
end

-- --- Transitradius (linear) ----------------------------------------------
do
    setup(makeRenderRoom()) -- rings 7/6, Camera.init(7)
    check(Render.transitRadius(0, "outer", "inner") == Config.outerRadius, "transitradius: p0 -> outerRadius")
    check(approx(Render.transitRadius(0.5, "outer", "inner"), (Config.outerRadius + Config.innerRadius) / 2), "transitradius: p0.5 -> Mittelpunkt")
    check(Render.transitRadius(1, "outer", "inner") == Config.innerRadius, "transitradius: p1 -> innerRadius")
    check(Render.transitRadius(0, "inner", "outer") == Config.innerRadius, "transitradius: gegenrichtung p0")
    check(Render.transitRadius(1, "inner", "outer") == Config.outerRadius, "transitradius: gegenrichtung p1")
end

-- --- Sichtbarer Spielerradius (Transit überschreibt Ring) ----------------
do
    local room = {
        name = "PlayerRadius",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 90 },
        switches = {},
        shutters = {},
        bridges = { { id="B0", angle=90, free=true } },
        gate = { id="T", angle=180, free=true },
    }
    setup(room)
    check(Render.playerRadius() == Config.outerRadius, "playerradius: normal outer")
    Room.tryUseConnection() -- Transit starten
    check(Render.playerRadius() == Config.outerRadius, "playerradius: transit p0 = outerRadius")
    Bridge.update(Config.bridgeAnimDuration / 2)
    check(approx(Render.playerRadius(), (Config.outerRadius + Config.innerRadius) / 2), "playerradius: transit p0.5 = Mittelpunkt")
    Bridge.update(Config.bridgeAnimDuration / 2 + 0.001)
    Room.syncPhysicalShutters()
    check(Render.playerRadius() == Config.innerRadius, "playerradius: nach Abschluss inner")
end

-- --- Kamera-Radien (Phase 8.1): Render nutzt Camera, nicht hart 104/68 -----
do
    State.init(Levels[1]) -- rings 7/6
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    Camera.init(7)
    check(Render.ringRadius("outer") == Config.outerRadius, "camera: stabil outer 104")
    check(Render.ringRadius("inner") == Config.innerRadius, "camera: stabil inner 68")
    Camera.beginRoomTransition(7, 6, 6, 5)
    Camera.update(0.6) -- eased 0.5 -> visualOuter 6.5
    check(approx(Render.ringRadius("outer"), 122), "camera: Halbzeit alter outer ~122")
    check(approx(Render.ringRadius("inner"), 86), "camera: Halbzeit shared ~86")
    check(Render.ringRadius("outer") ~= Config.outerRadius, "camera: kein hartes 104 während Transition")
    Camera.update(0.6)
    check(Camera.isTransitioning() == false, "camera: Transition beendet")
    check(approx(Render.ringRadius("outer"), Config.outerRadius + (Config.outerRadius - Config.innerRadius)), "camera: alter outer 140 nach Abschluss")
    check(approx(Render.ringRadius("inner"), Config.outerRadius), "camera: shared 104 nach Abschluss")
end

-- --- Phase 8.2: drawRoom ist read-only ------------------------------------
do
    State.init(Levels[1])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    Camera.init(7)
    Render.visualTime = 0
    Render.resetPlayerVisual()
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    local shutterBefore = Room.shutters["D1"] and Room.shutters["D1"].collisionActive
    local camBefore = Camera.getCurrentOuterRing()
    local okDraw = pcall(Render.drawRoom, false, 1)
    check(okDraw, "8.2 read-only: drawRoom läuft fehlerfrei")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "8.2 read-only: State.player unverändert")
    check(Undo.count() == undoBefore, "8.2 read-only: Undo unverändert")
    check(Room.shutters["D1"].collisionActive == shutterBefore, "8.2 read-only: Shutter-Runtime unverändert")
    check(Camera.getCurrentOuterRing() == camBefore, "8.2 read-only: Camera unverändert")
    local swSame, elSame = true, true
    for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
    for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
    for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
    for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
    check(swSame, "8.2 read-only: switchStates unverändert")
    check(elSame, "8.2 read-only: elementStates unverändert")
end

-- --- Phase 8.2: Ghost-Ringnummern ------------------------------------------
do
    State.init(Levels[1]) -- outer 7
    Room.init()
    Camera.init(7)
    local g1 = Render.ghostRingNumbers(1)
    check(#g1 == 0, "ghost: Raum 1 keine Geisterringe")
    State.init(Levels[2]) -- outer 6
    Room.init()
    Camera.init(6)
    local g2 = Render.ghostRingNumbers(2)
    check(#g2 == 1 and g2[1] == 7, "ghost: Raum 2 -> Ring 7")
    State.init(Levels[3]) -- outer 5
    Room.init()
    Camera.init(5)
    local g3 = Render.ghostRingNumbers(3)
    check(#g3 == 2 and g3[1] == 6 and g3[2] == 7, "ghost: Raum 3 -> Ringe 6,7")
end

-- --- Phase 8.2: Kernwachstum ----------------------------------------------
do
    check(Render.coreRadius(1) == Config.coreRadius, "kern: Raum 1 Basis")
    check(Render.coreRadius(2) == Config.coreRadius + Config.coreGrowthPerRoom, "kern: Raum 2 +6")
    check(Render.coreRadius(3) == Config.coreRadius + 2 * Config.coreGrowthPerRoom, "kern: Raum 3 +12")
    check(Render.coreRadius(1) < Render.coreRadius(2) and Render.coreRadius(2) < Render.coreRadius(3), "kern: R1<R2<R3")
end

-- --- Phase 8.2: Kernpulsation (Atmosphäre: zweiwelliges organisches Atmen) --
do
    Render.visualTime = 0
    check(approx(Render.corePulseOffset(), 0), "puls: t=0 Offset 0")
    -- Hauptwelle bei t=T/4 (Phase pi/2) plus zweite Atemwelle am selben Punkt.
    Render.visualTime = Config.corePulsePeriod / 4
    local expected = Config.corePulseAmplitude
        + Config.corePulseAmplitude2 * math.sin((Config.corePulsePeriod / 4) * 2 * math.pi / Config.corePulsePeriod2)
    check(approx(Render.corePulseOffset(), expected, 1e-3), "puls: t=T/4 zweiwellig exakt")
    -- Determinismus: gleiche Zeit -> gleicher Wert (reine Funktion von visualTime).
    local a1 = Render.corePulseOffset()
    local a2 = Render.corePulseOffset()
    check(a1 == a2, "puls: deterministisch")
    -- Amplitude durch Summe beider Wellen begrenzt.
    Render.visualTime = Config.corePulsePeriod / 4 + 100
    check(math.abs(Render.corePulseOffset()) <= Config.corePulseAmplitude + Config.corePulseAmplitude2,
        "puls: Amplitude begrenzt (Haupt + Atemwelle)")
end

-- --- Phase 8.2: Symbole ----------------------------------------------------
do
    local white = playdate.graphics.kColorWhite
    check(pcall(function() Render.drawSymbol(1, 100, 100, 4, white) end), "symbol: 1 rendert")
    check(pcall(function() Render.drawSymbol(2, 100, 100, 4, white) end), "symbol: 2 rendert")
    check(pcall(function() Render.drawSymbol(3, 100, 100, 4, white) end), "symbol: 3 rendert")
    local okUnknown = pcall(function() Render.drawSymbol(9, 100, 100, 4, white) end)
    check(okUnknown == false, "symbol: unbekannt -> Fehler")
end

-- --- Phase 8.2: Elementmarken-Lookup --------------------------------------
do
    local room = {
        name = "Marks",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=90, symbol=2, onA="D1", onB="B1", state="B" },
        },
        shutters = { { id="D1", ring="outer", angle=180 } },
        bridges = {
            { id="B0", angle=270, free=true },
            { id="B1", angle=0, free=false },
        },
        gate = { id="T", angle=180, free=true },
    }
    State.init(room)
    Room.init()
    local lookup = Render.buildElementSymbolLookup()
    check(lookup["D1"] == 2, "marks: D1 erhält Symbol 2 (onB)")
    check(lookup["B1"] == 2, "marks: B1 erhält Symbol 2 (onA)")
    check(lookup["B0"] == nil, "marks: freie Brücke B0 ohne Marke")
    check(lookup["T"] == nil, "marks: freies Gate T ohne Marke")
end

-- --- Phase 8.2: Player-Facing ----------------------------------------------
do
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5)
    check(Render.playerVisual.facing == 1, "facing: actualDelta>0 -> CW")
    Render.notePlayerMovement(-3)
    check(Render.playerVisual.facing == -1, "facing: actualDelta<0 -> CCW")
    Render.notePlayerMovement(0)
    check(Render.playerVisual.facing == -1, "facing: actualDelta==0 -> letzte Richtung bleibt")
    Render.notePlayerMovement(2)
    check(Render.playerVisual.facing == 1, "facing: erneut CW")
end

-- --- Phase 8.3: Schaltervorschau -------------------------------------------
-- S1 (outer@90) steuert B1 + D1; S2 (inner@90) steuert T + D2; B0 frei.
local function makePreviewRoom()
    return {
        name = "Preview",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="A" },
            { id="S2", ring="inner", angle=90, symbol=2, onA="T",  onB="D2", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=90 },
            { id="D2", ring="inner", angle=90 },
        },
        bridges = {
            { id="B0", angle=45, free=true  },
            { id="B1", angle=180, free=false },
        },
        gate = { id="T", angle=180, free=false },
    }
end

-- Zwei Switches auf demselben Ring nahe beieinander (Wraparound/Multiple).
local function makeWraparoundRoom()
    return {
        name = "Wraparound",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id="S1", ring="outer", angle=350, symbol=1, onA="B1", onB="D1", state="A" },
            { id="S2", ring="outer", angle=2,   symbol=2, onA="T",  onB="D2", state="B" },
        },
        shutters = {
            { id="D1", ring="outer", angle=330 },
            { id="D2", ring="outer", angle=20 },
        },
        bridges = {
            { id="B0", angle=180, free=true  },
            { id="B1", angle=90, free=false },
        },
        gate = { id="T", angle=270, free=false },
    }
end

-- Pflicht-Test 1: 19° -> Preview aktiv (onA + onB)
-- Pflicht-Test 2: 20°  -> keine Preview
-- Pflicht-Test 3: 21°  -> keine Preview
-- (inkl. exakter Grenze 19.999/20/20.001)
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    local ids = Render.previewElementIds(false)
    check(ids["D1"] == true, "preview 19°: D1 hervorgehoben (onB)")
    check(ids["B1"] == true, "preview 19°: B1 hervorgehoben (onA)")
    check(ids["T"] == nil, "preview 19°: T (inner S2) NICHT")
    State.player.angle = 70
    ids = Render.previewElementIds(false)
    check(ids["D1"] == nil and ids["B1"] == nil, "preview 20°: keine Hervorhebung")
    State.player.angle = 69
    ids = Render.previewElementIds(false)
    check(ids["D1"] == nil and ids["B1"] == nil, "preview 21°: keine Hervorhebung")
    State.player.angle = 90 - 19.999
    check(Render.previewElementIds(false)["D1"] == true, "preview 19.999°: aktiv")
    State.player.angle = 70
    check(Render.previewElementIds(false)["D1"] == nil, "preview 20° exakt: aus")
    State.player.angle = 90 - 20.001
    check(Render.previewElementIds(false)["D1"] == nil, "preview 20.001°: aus")
end

-- Pflicht-Test 4: Wraparound 359°/2° -> delta 3 -> Preview aktiv
do
    setup(makeWraparoundRoom())
    State.player.ring = "outer"
    State.player.angle = 359
    local ids = Render.previewElementIds(false)
    check(ids["D1"] == true, "wraparound 359/350 (delta 9): D1")
    check(ids["B1"] == true, "wraparound 359/350: B1")
    check(ids["T"] == true, "wraparound 359/2 (delta 3): T")
    check(ids["D2"] == true, "wraparound 359/2: D2")
end

-- Pflicht-Test 5: anderer Ring (gleicher Winkel) -> keine Preview
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 90
    local ids = Render.previewElementIds(false)
    check(ids["D1"] == true, "anderer Ring: S1 outer hervorgehoben")
    check(ids["B1"] == true, "anderer Ring: B1 hervorgehoben")
    check(ids["T"] == nil, "anderer Ring: T (inner S2) NICHT")
    check(ids["D2"] == nil, "anderer Ring: D2 (inner S2) NICHT")
end

-- Pflicht-Test 6+7: onA + onB beide, unabhängig vom aktuellen Zustand
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    State.setSwitch("S1", "B")
    local idsB = Render.previewElementIds(false)
    check(idsB["D1"] == true and idsB["B1"] == true, "zustand B: onA+onB beide")
    State.setSwitch("S1", "A")
    local idsA = Render.previewElementIds(false)
    check(idsA["D1"] == true and idsA["B1"] == true, "zustand A: onA+onB beide")
end

-- Pflicht-Test 8: Switch steuert Gate -> Gate ist Preview-Ziel
do
    setup(makePreviewRoom())
    State.player.ring = "inner"
    State.player.angle = 90
    local ids = Render.previewElementIds(false)
    check(ids["T"] == true, "gate: T hervorgehoben (onA von S2)")
    check(ids["D2"] == true, "gate: D2 hervorgehoben (onB von S2)")
end

-- Pflicht-Test 9: freie Bridge ohne Controller -> nie hervorgehoben
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 45
    local ids = Render.previewElementIds(false)
    check(ids["B0"] == nil, "free bridge: B0 nie hervorgehoben")
end

-- Pflicht-Test 10: mehrere nahe Switches -> Union aller Element-IDs
do
    setup(makeWraparoundRoom())
    State.player.ring = "outer"
    State.player.angle = 0
    local ids = Render.previewElementIds(false)
    check(ids["D1"] == true and ids["B1"] == true and ids["T"] == true and ids["D2"] == true,
        "mehrere Switches: Union aller Elemente")
end

-- Pflicht-Test 11: Config off -> keine Preview-IDs; danach wiederherstellen
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    local saved = Config.switchPreviewEnabled
    Config.switchPreviewEnabled = false
    check(next(Render.previewElementIds(false)) == nil, "config off: keine Preview-IDs")
    Config.switchPreviewEnabled = saved
    check(Render.previewElementIds(false)["D1"] == true, "config an: Preview wieder da")
end

-- Pflicht-Test 12/13/14: Blink 1 Hz (0.5 s ON / 0.5 s OFF)
do
    Render.visualTime = 0.25
    check(Render.previewBlinkOn() == true, "blink t=0.25: ON")
    Render.visualTime = 0.75
    check(Render.previewBlinkOn() == false, "blink t=0.75: OFF")
    Render.visualTime = 1.25
    check(Render.previewBlinkOn() == true, "blink t=1.25: wieder ON (1 Hz)")
    Render.visualTime = 0
    check(Render.previewBlinkOn() == true, "blink t=0: ON")
    Render.visualTime = Config.previewBlinkPeriod / 2
    check(Render.previewBlinkOn() == false, "blink t=0.5: OFF (Grenze)")
end

-- Pflicht-Test 15: read-only bei aktiver Preview
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    Render.visualTime = 0.25 -- blink ON
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    local shBefore = {}
    for k, v in pairs(Room.shutters) do
        shBefore[k] = { collisionActive = v.collisionActive, pendingClose = v.pendingClose }
    end
    local camBefore = Camera.getCurrentOuterRing()
    local okDraw = pcall(Render.drawRoom, false, 1)
    check(okDraw, "preview read-only: drawRoom läuft fehlerfrei")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "preview read-only: player unverändert")
    check(Undo.count() == undoBefore, "preview read-only: undo unverändert")
    check(Camera.getCurrentOuterRing() == camBefore, "preview read-only: camera unverändert")
    local swSame = true
    for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
    for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
    check(swSame, "preview read-only: switchStates unverändert")
    local elSame = true
    for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
    for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
    check(elSame, "preview read-only: elementStates unverändert")
    local shSame = true
    for k, v in pairs(Room.shutters) do
        if shBefore[k] then
            if shBefore[k].collisionActive ~= v.collisionActive or shBefore[k].pendingClose ~= v.pendingClose then
                shSame = false
            end
        end
    end
    check(shSame, "preview read-only: shutters unverändert")
end

-- Pflicht-Test 16: Camera-Transition -> keine Preview
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    Camera.beginRoomTransition(7, 6, 6, 5)
    check(Camera.isTransitioning(), "camera transition aktiv")
    check(next(Render.previewElementIds(false)) == nil, "camera transition: keine Preview")
end

-- Pflicht-Test 17: roomComplete -> keine Preview
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    check(next(Render.previewElementIds(true)) == nil, "roomComplete: keine Preview")
end

-- Pflicht-Test 18: Bridge-Transit -> keine Preview
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    Bridge.beginTransit({ id = "B0", angle = 45, free = true }, "outer")
    check(Bridge.isCrossing(), "bridge crossing aktiv")
    check(next(Render.previewElementIds(false)) == nil, "bridge crossing: keine Preview")
    Bridge.resetTransit()
end

-- Pflicht-Test 19+20: inaktive Bridge bleibt inaktiv, closed Shutter bleibt
-- geschlossen (Zustand unverändert, drawRoom fehlerfrei mit Preview-Halos).
do
    setup(makePreviewRoom())
    State.setSwitch("S1", "B") -- D1 zu, B1 inaktiv; S2=B -> T inaktiv, D2 zu
    State.player.ring = "outer"
    State.player.angle = 71 -- nahe S1 -> D1 (closed) + B1 (inaktiv) previewed
    Render.visualTime = 0.25
    check(Render.bridgeVisualState("B1") == "inactive", "preview bruecke: B1 inaktiv vorher")
    check(Render.shutterVisualState("D1") == "closed", "preview blende: D1 geschlossen vorher")
    local okDraw = pcall(Render.drawRoom, false, 1)
    check(okDraw, "preview inaktiv+closed: drawRoom ok")
    check(Render.bridgeVisualState("B1") == "inactive", "preview bruecke: B1 bleibt inaktiv")
    check(Render.shutterVisualState("D1") == "closed", "preview blende: D1 bleibt geschlossen")
end

-- Pflicht-Test 21+77: Elementmarken bleiben (drawRoom mit Preview ok, kein
-- Switch in der Preview-Menge).
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    Render.visualTime = 0.25
    local okDraw = pcall(Render.drawRoom, false, 1)
    check(okDraw, "preview marks: drawRoom ok")
    local ids = Render.previewElementIds(false)
    check(ids["S1"] == nil and ids["S2"] == nil, "preview: Switch selbst nie hervorgehoben")
    check(ids["D1"] ~= nil, "preview: nur gesteuerte Elemente")
end

-- --- Phase 8.4: Spieler-/Augenanimation ------------------------------------
-- Deterministische Blink-Zufallsquelle (0.5 -> Intervall 4.5 s).
local savedBlinkRandom = Render.blinkRandom
Render.blinkRandom = function() return 0.5 end

-- Pflicht-Test 1/2: Facing CW/CCW via actualDelta; Auge tangential
-- Pflicht-Test 3/4: blockierte Bewegung ändert Facing nicht; Idle behält
do
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5)
    check(Render.playerVisual.facing == 1, "facing84: actualDelta>0 -> CW")
    Render.notePlayerMovement(-3)
    check(Render.playerVisual.facing == -1, "facing84: actualDelta<0 -> CCW")
    setup(makeRenderRoom())
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5)
    local ex1, ey1 = Render.playerEyePosition()
    Render.notePlayerMovement(-5)
    local ex2, ey2 = Render.playerEyePosition()
    check(ex1 ~= ex2 or ey1 ~= ey2, "facing84: Auge tangential CW/CCW verschieden")
    Render.notePlayerMovement(5) -- CW
    Render.noteShutterBlocked(true) -- blockierter Anstoß (kein notePlayerMovement)
    check(Render.playerVisual.facing == 1, "facing84: blockiert ändert Facing nicht")
    for i = 1, 20 do Render.update(0.02, false) end -- idle
    check(Render.playerVisual.facing == 1, "facing84: Idle behält CW")
end

-- Pflicht-Test 5/6: Blink frühestens 3 s, spätestens 6 s, deterministisch
do
    Render.resetPlayerVisual()
    check(Render.playerVisual.nextBlinkAt >= Config.blinkMinInterval
        and Render.playerVisual.nextBlinkAt <= Config.blinkMaxInterval, "blink: Termin in [3,6] s")
    for i = 1, 149 do Render.update(0.02, false) end -- idleTime ~2.98
    check(Render.playerVisual.blinkFramesRemaining == 0, "blink: <3 s kein Blink")
    Render.resetPlayerVisual()
    local firstBlinkAtIdle = nil
    for i = 1, 400 do
        Render.update(0.02, false)
        if Render.playerVisual.blinkFramesRemaining > 0 and not firstBlinkAtIdle then
            firstBlinkAtIdle = Render.playerVisual.idleTime
        end
    end
    check(firstBlinkAtIdle ~= nil, "blink: tritt auf")
    check(firstBlinkAtIdle >= Config.blinkMinInterval - 0.02, "blink: frühestens ~3 s")
    check(firstBlinkAtIdle <= Config.blinkMaxInterval + 0.02, "blink: spätestens ~6 s")
end

-- Pflicht-Test 7: Bewegung resetet Blinktimer
do
    Render.resetPlayerVisual()
    Render.playerVisual.nextBlinkAt = 0.5
    for i = 1, 20 do Render.update(0.02, false) end -- idleTime ~0.4
    Render.notePlayerMovement(5)
    check(Render.playerVisual.idleTime == 0, "blink: Bewegung resetet idleTime")
    check(Render.playerVisual.blinkFramesRemaining == 0, "blink: kein sofortiger Blink nach Bewegung")
    for i = 1, 20 do Render.update(0.02, false) end
    check(Render.playerVisual.blinkFramesRemaining == 0, "blink: nach Stopp kein sofortiger Blink")
end

-- Pflicht-Test 8: Blinkdauer exakt config.blinkFrames; Form -> 'blink'
do
    Render.resetPlayerVisual()
    Render.playerVisual.nextBlinkAt = 0.01
    local count = 0
    for i = 1, 20 do
        Render.update(0.02, false)
        if Render.playerVisual.blinkFramesRemaining > 0 then count = count + 1 end
    end
    check(count == Config.blinkFrames, "blink: Dauer " .. Config.blinkFrames .. " Frames")
    Render.resetPlayerVisual()
    Render.playerVisual.nextBlinkAt = 0.01
    Render.update(0.02, false)
    check(Render.currentEyeReaction() == "blink", "blink: Reaktion 'blink'")
end

-- Pflicht-Test 9: Switch-Widen
do
    Render.resetPlayerVisual()
    Render.noteSwitchContact()
    check(Render.playerVisual.switchWidenFramesRemaining == Config.switchEyeWidenFrames, "widen: aktiv")
    check(Render.currentEyeReaction() == "widen", "widen: Reaktion 'widen'")
end

-- Pflicht-Test 10: DockAssist kein Widen (echte Assistenz auf freie Brücke)
do
    setup(makeRenderRoom())
    State.player.ring = "outer"
    State.player.angle = 268 -- nahe freier Brücke B0@270 (dockAssistRange 4)
    Render.resetPlayerVisual()
    Room.updateDockAssist()
    Render.noteShutterBlocked(false)
    check(Render.currentEyeReaction() == "normal", "widen: DockAssist kein Widen")
    check(Render.playerVisual.switchWidenFramesRemaining == 0, "widen: Frames 0 nach DockAssist")
end

-- Pflicht-Test 11: Preview-Nähe kein Widen
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71 -- Preview aktiv (<20° von S1)
    Render.resetPlayerVisual()
    Render.visualTime = 0.25
    pcall(Render.drawRoom, false, 1)
    check(Render.playerVisual.switchWidenFramesRemaining == 0, "widen: Preview-Nähe kein Widen")
end

-- Pflicht-Test 12: Undo kein Widen
do
    Render.resetPlayerVisual()
    Render.noteSwitchContact()
    check(Render.currentEyeReaction() == "widen", "widen: aktiv vor Undo")
    Render.noteUndo()
    check(Render.playerVisual.switchWidenFramesRemaining == 0, "widen: Undo neutralisiert")
    check(Render.currentEyeReaction() == "normal", "widen: nach Undo normal")
end

-- Pflicht-Test 13/14/15/16: Shutter-Squint, exakt 6 Frames, gehalten, neu
do
    Render.resetPlayerVisual()
    Render.noteShutterBlocked(true)
    check(Render.playerVisual.shutterSquintFramesRemaining == Config.shutterSquintFrames, "squint: startet")
    check(Render.currentEyeReaction() == "squint", "squint: Reaktion 'squint'")
    Render.resetPlayerVisual()
    Render.noteShutterBlocked(true) -- Frame 1
    check(Render.currentEyeReaction() == "squint", "squint: Frame 1")
    for i = 1, 4 do Render.update(0.02, false) end -- Frames 2-5
    check(Render.currentEyeReaction() == "squint", "squint: Frame 5")
    Render.update(0.02, false) -- Frame 6
    check(Render.currentEyeReaction() == "squint", "squint: Frame 6")
    Render.update(0.02, false) -- Frame 7
    check(Render.currentEyeReaction() == "normal", "squint: Frame 7 normal")
    Render.resetPlayerVisual()
    Render.noteShutterBlocked(true)
    for i = 1, 6 do
        Render.noteShutterBlocked(true) -- gehalten: kein Restart
        Render.update(0.02, false)
    end
    check(Render.playerVisual.shutterSquintFramesRemaining == 0, "squint: gehalten endet nach 6 Frames")
    Render.resetPlayerVisual()
    Render.noteShutterBlocked(true)
    Render.update(0.02, false)
    Render.noteShutterBlocked(false) -- unblocked
    Render.update(0.02, false)
    Render.noteShutterBlocked(true) -- neue Kollision
    check(Render.playerVisual.shutterSquintFramesRemaining == Config.shutterSquintFrames, "squint: neue Kollision neue 6 Frames")
end

-- Pflicht-Test 17/18/19: Bridge-Stretch Formel (Kreis -> max -> Kreis)
do
    check(approx(Render.bridgeStretch(0), 0), "stretch: progress 0 -> Kreis")
    check(approx(Render.bridgeStretch(0.5), Config.bridgeStretchAmount), "stretch: progress 0.5 -> max")
    check(approx(Render.bridgeStretch(1), 0, 1e-3), "stretch: progress 1 -> Kreis")
end

-- Pflicht-Test 20: Bridge radial (Längsachse)
do
    local ax, ay, bx, by = Render.bodyAxisVectors(0)
    check(approx(ax, 0, 1e-3) and approx(ay, -1, 1e-3) and approx(bx, 1, 1e-3) and approx(by, 0, 1e-3),
        "stretch: 0° radial vertikal, tangential horizontal")
    local ax2, ay2, bx2, by2 = Render.bodyAxisVectors(90)
    check(approx(ax2, 1, 1e-3) and approx(ay2, 0, 1e-3) and approx(bx2, 0, 1e-3) and approx(by2, 1, 1e-3),
        "stretch: 90° radial horizontal")
end

-- Pflicht-Test 21: Bridge-Stretch read-only
do
    setup(makeRenderRoom())
    Render.resetPlayerVisual()
    Bridge.beginTransit({ id = "B0", angle = 270, free = true }, "outer")
    Bridge.update(Config.bridgeAnimDuration / 2) -- Mitte
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    local ok = pcall(Render.drawRoom, false, 1)
    check(ok, "stretch read-only: drawRoom ok")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "stretch read-only: player unverändert")
    check(Undo.count() == undoBefore, "stretch read-only: undo unverändert")
    check(Bridge.isCrossing(), "stretch read-only: transit unverändert")
    Bridge.resetTransit()
end

-- Pflicht-Test 22: Reaktionspriorität Squint > Widen > Blink
do
    Render.resetPlayerVisual()
    Render.noteSwitchContact() -- Widen
    Render.playerVisual.blinkFramesRemaining = Config.blinkFrames
    check(Render.currentEyeReaction() == "widen", "priority: Widen gewinnt über Blink")
    Render.noteShutterBlocked(true) -- Squint
    check(Render.currentEyeReaction() == "squint", "priority: Squint gewinnt über Widen/Blink")
end

-- Pflicht-Test 23: Bridge-Transit verhindert neuen Blink
do
    setup(makeRenderRoom())
    Render.resetPlayerVisual()
    Render.playerVisual.nextBlinkAt = 0.5
    Bridge.beginTransit({ id = "B0", angle = 270, free = true }, "outer")
    for i = 1, 60 do Render.update(0.02, false) end
    check(Render.playerVisual.blinkFramesRemaining == 0, "blink: Crossing kein neuer Blink")
    Bridge.resetTransit()
end

-- Pflicht-Test 24: Raumwechsel Reset
do
    Render.resetPlayerVisual()
    Render.noteShutterBlocked(true)
    Render.noteSwitchContact()
    Render.playerVisual.blinkFramesRemaining = Config.blinkFrames
    Render.resetPlayerVisual()
    check(Render.currentEyeReaction() == "normal", "reset: alle neutral")
    check(Render.playerVisual.shutterSquintFramesRemaining == 0
        and Render.playerVisual.switchWidenFramesRemaining == 0
        and Render.playerVisual.blinkFramesRemaining == 0, "reset: Frames 0")
end

-- Pflicht-Test 25: roomComplete -> kein neuer Blink
do
    Render.resetPlayerVisual()
    Render.playerVisual.nextBlinkAt = 0.5
    for i = 1, 60 do Render.update(0.02, true) end -- roomComplete=true
    check(Render.playerVisual.blinkFramesRemaining == 0, "roomComplete: kein neuer Blink")
end

-- Read-only-Test: mehrere Animationsframes rendern ohne Mutation
do
    setup(makePreviewRoom())
    State.player.ring = "outer"
    State.player.angle = 71
    Render.resetPlayerVisual()
    Render.visualTime = 0.25
    Render.noteSwitchContact()
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    local camBefore = Camera.getCurrentOuterRing()
    local transitBefore = Bridge.getTransit()
    local okDraw = true
    for i = 1, 5 do
        if not pcall(Render.drawRoom, false, 1) then okDraw = false end
    end
    check(okDraw, "anim read-only: drawRoom ok")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "anim read-only: player unverändert")
    check(Undo.count() == undoBefore, "anim read-only: undo unverändert")
    check(Camera.getCurrentOuterRing() == camBefore, "anim read-only: camera unverändert")
    check(Bridge.getTransit() == transitBefore, "anim read-only: transit unverändert")
    local swSame = true
    for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
    for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
    check(swSame, "anim read-only: switchStates unverändert")
    local elSame = true
    for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
    for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
    check(elSame, "anim read-only: elementStates unverändert")
end

-- --- Atmosphere: Blenden-Überschwinger (Trigger, Dauer, No-op) -------------
do
    Render.resetObjectAnims()
    setup(makeRenderRoom()) -- S1=A -> D1 geschlossen (Spieler @0 außerhalb)
    -- Erster Frame nach Reset: Zustand wird nur gemerkt, kein Schein-Anim.
    Render.update(0.02)
    check(Render.shutterAnims["D1"] == nil, "blenden-anim: kein Anim ohne Zustandswechsel")
    -- closed -> open startet die Einfahr-Animation.
    State.setSwitch("S1", "B")
    Room.syncPhysicalShutters()
    Render.update(0.02)
    check(Render.shutterAnims["D1"] ~= nil and Render.shutterAnims["D1"].kind == "open",
        "blenden-anim: closed->open startet open-Anim")
    for i = 1, 8 do Render.update(0.02) end
    check(Render.shutterAnims["D1"] == nil, "blenden-anim: open-Anim läuft aus")
    -- open -> closed startet den Überschwinger (max. overshootFrames + 1).
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    Render.update(0.02)
    check(Render.shutterAnims["D1"] ~= nil and Render.shutterAnims["D1"].kind == "close"
        and Render.shutterAnims["D1"].frames <= Config.shutterOvershootFrames + 1,
        "blenden-anim: open->closed startet close-Anim (begrenzte Dauer)")
    for i = 1, 8 do Render.update(0.02) end
    check(Render.shutterAnims["D1"] == nil, "blenden-anim: close-Anim läuft aus")
end

-- --- Atmosphere: Brücken-Stufen-Ausfahren (Trigger, Fortschritt, Settle) ---
do
    Render.resetObjectAnims()
    setup(makeRenderRoom()) -- S1=A -> B1 aktiv; B0/T frei aktiv
    -- Erster Frame: keine Schein-Anims für bereits aktive Brücken.
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] == nil and Render.bridgeAnims["B0"] == nil,
        "brücken-anim: kein Anim ohne false->true-Wechsel")
    -- active -> inactive erzeugt kein Anim.
    State.setSwitch("S1", "B")
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] == nil, "brücken-anim: aktiv->inaktiv kein Anim")
    -- inactive -> active startet das Ausfahren mit kleinem Anfangsforschritt.
    State.setSwitch("S1", "A")
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] ~= nil and Render.bridgeAnims["B1"].p <= 0.45,
        "brücken-anim: false->true startet Ausfahren")
    -- Nach Ausfahr- + Settle-Dauer ist die Animation abgeräumt.
    local bTotal = Config.bridgeExtendStage1 + Config.bridgeExtendStage2 + Config.bridgeExtendStage3
    for i = 1, math.ceil((bTotal + 0.1) / 0.02) do Render.update(0.02) end
    check(Render.bridgeAnims["B1"] == nil, "brücken-anim: Ausfahren + Settle ausgelaufen")
end

-- --- Atmosphere: finaler Raum-6-Moment (Ghost-Drift-Freeze, Impuls, Reset) -
do
    Render.resetObjectAnims()
    setup(makeRenderRoom())
    check(Render.finalMomentActive == false, "final: anfangs inaktiv")
    Render.beginFinalMoment()
    check(Render.finalMomentActive == true, "final: beginFinalMoment aktiviert")
    check(Render.finalMomentDriftTime ~= nil, "final: Drift-Zeitbasis eingefroren")
    check(Render.completionPulseT == 0, "final: zeigt Systemimpuls")
    -- Drift deterministisch eingefroren: gleiche Marke zu späteren Zeiten.
    local markA = math.fmod(Render.finalMomentDriftTime * Config.ghostDriftSpeeds[1] * Config.ghostDriftDirections[1], 360)
    Render.visualTime = Render.visualTime + 1.0
    local markB = math.fmod(Render.finalMomentDriftTime * Config.ghostDriftSpeeds[1] * Config.ghostDriftDirections[1], 360)
    check(markA == markB, "final: Ghost-Drift eingefroren (statische Marke)")
    Render.endFinalMoment()
    check(Render.finalMomentActive == false and Render.finalMomentDriftTime == nil, "final: endFinalMoment räumt auf")
    -- Raumstart-Reset: kein hängender Final-Zustand.
    Render.beginFinalMoment()
    Render.resetObjectAnims()
    check(Render.finalMomentActive == false, "final: resetObjectAnims räumt Final-Zustand")
end

-- --- Atmosphere: Raumabschluss-Systemimpuls (genau einmal) -----------------
do
    Render.resetObjectAnims()
    setup(makeRenderRoom())
    check(Render.completionPulseT == nil, "impuls: anfangs inaktiv")
    Render.noteRoomComplete()
    check(Render.completionPulseT == 0, "impuls: noteRoomComplete setzt Timer")
    Render.update(0.02)
    check(Render.completionPulseT ~= nil and Render.completionPulseT > 0, "impuls: läuft")
    local pulseFrames = math.ceil(Config.completionPulseDuration / 0.02) + 2
    for i = 1, pulseFrames do Render.update(0.02) end
    check(Render.completionPulseT == nil, "impuls: läuft exakt einmal aus (kein Selbst-Nachlauf)")
    -- Erneut auslösbar (nächster Raum): wieder Timer, wieder beendet.
    Render.noteRoomComplete()
    check(Render.completionPulseT == 0, "impuls: erneut startbar")
    for i = 1, pulseFrames do Render.update(0.02) end
    check(Render.completionPulseT == nil, "impuls: zweiter Lauf beendet")
end

-- --- Atmosphere: Idle-Core-Blick (Pupille wandert Richtung Kern) -----------
do
    setup(makeRenderRoom())
    State.player.ring = "outer"
    State.player.angle = 0 -- 12 Uhr: Kern liegt direkt unterhalb (+y)
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5) -- facing CW, idleTime 0
    local g0x, g0y = Render.playerEyePosition()
    -- Nach Überschreiten der Verzögerung wandert die Pupille radial zum Kern
    -- (bei 0° also nach unten, +y); die tangentiale Achse bleibt unberührt.
    Render.playerVisual.idleTime = Config.idleGazeDelay + 1.5
    local g1x, g1y = Render.playerEyePosition()
    check(g1x == g0x and g1y > g0y, "idle-gaze: nach Verzögerung radial Richtung Kern")
    -- Vor der Verzögerung: keine Wanderung.
    Render.playerVisual.idleTime = Config.idleGazeDelay - 0.5
    local g2x, g2y = Render.playerEyePosition()
    check(g2x == g0x and g2y == g0y, "idle-gaze: vor Verzögerung keine Wanderung")
    -- Determinismus: gleicher Zustand -> gleiche Position.
    Render.playerVisual.idleTime = Config.idleGazeDelay + 1.5
    local g3x, g3y = Render.playerEyePosition()
    check(g3x == g1x and g3y == g1y, "idle-gaze: deterministisch")
end

Render.blinkRandom = savedBlinkRandom

TestReport.render = { pass = pass, fail = fail }
