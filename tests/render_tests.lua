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

-- --- Schalterdarstellung (Referenz): abgerundetes Rechteck + zwei Kreise ---
-- Der Schalter ist ein breites flaches Rechteck (WEISSER Block mit schwarzer
-- 1-px-Kontur auf der weißen Bahn) mit zwei Innenkreisen nahe den Längsenden.
-- Auftrag „Doppelschalter visuell klarer": die AKTIVE Richtung (CW = A,
-- CCW = B) ist als GEFÜLLTER Innenkreis markiert, die inaktive Seite als
-- reine KONTOUR — damit liest man sofort, welche Richtung aktiv ist. Pixel-
-- probe aus der ECHTEN Render-Pipeline (drawRoom -> drawSwitch). Eigener
-- Raum, damit die Blende die Probe nicht verfälscht.
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

    -- Gameplay-Semantik A/B bleibt (CW=A, CCW=B) — die Darstellung markiert
    -- jetzt die aktive Seite (gefüllt) und lässt die inaktive als Kontur.
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

    -- Schalter S1 outer@90 -> Zentrum (304,120); lange Achse = Ringtangente
    -- (bei 90° vertikal, +y = unten). Zwei Innenkreise bei ±switchCircleOffset.
    -- Bei 90° ist +tangential = +y (unten): die CW-Seite (A) liegt also UNTEN
    -- (c2y), die CCW-Seite (B) OBEN (c1y).
    local swX = 200 + Config.outerRadius * math.sin(math.rad(90))
    local swY = 120 - Config.outerRadius * math.cos(math.rad(90))
    local ix, iy = math.floor(swX + 0.5), math.floor(swY + 0.5)
    local off = Config.switchCircleOffset
    local c1y = math.floor(iy - off + 0.5) -- Innenkreis 1 (oben, CCW-Seite)
    local c2y = math.floor(iy + off + 0.5) -- Innenkreis 2 (unten, CW-Seite)
    -- Körperpunkte zwischen Innenkreis und Längsende (weiß, kein Pfeil).
    local b1y = math.floor(iy - (off + Config.switchCircleRadius + 1) + 0.5)
    local b2y = math.floor(iy + (off + Config.switchCircleRadius + 1) + 0.5)

    -- A: CW-Seite (unten, c2y) GEFÜLLT, CCW-Seite (oben, c1y) nur Kontur
    -- (Kreismitte weiß). B: genau umgekehrt.
    State.setSwitch("S1", "A")
    local imgA = renderSwitchCanvas()
    State.setSwitch("S1", "B")
    local imgB = renderSwitchCanvas()

    -- Gemeinsame Grundform in beiden Zuständen.
    for _, img in ipairs({ imgA, imgB }) do
        check(img:sample(ix, iy) == gfxApi.kColorWhite, "schalter-pixel: Körper weiß (Zentrum, kein Symbol)")
        check(img:sample(ix, b1y) == gfxApi.kColorWhite, "schalter-pixel: Körper weiß (zwischen Kreis und Ende)")
        check(img:sample(ix, b2y) == gfxApi.kColorWhite, "schalter-pixel: Körper weiß (zwischen Kreis und Ende, unten)")
    end
    -- A: aktive CW-Seite (unten) gefüllt schwarz, inaktive CCW-Seite (oben) als
    -- Kontur (Kreismitte weiß = schwach, aber sichtbar).
    check(imgA:sample(ix, c2y) == gfxApi.kColorBlack, "schalter-pixel A: aktive CW-Seite gefüllt (schwarz)")
    check(imgA:sample(ix, c1y) == gfxApi.kColorWhite, "schalter-pixel A: inaktive CCW-Seite nur Kontur (Mitte weiß)")
    -- B: aktive CCW-Seite (oben) gefüllt schwarz, inaktive CW-Seite (unten) Kontur.
    check(imgB:sample(ix, c1y) == gfxApi.kColorBlack, "schalter-pixel B: aktive CCW-Seite gefüllt (schwarz)")
    check(imgB:sample(ix, c2y) == gfxApi.kColorWhite, "schalter-pixel B: inaktive CW-Seite nur Kontur (Mitte weiß)")
    -- Die Markierung WANDERT beim Umschalten (A und B sind jetzt unterscheidbar).
    check(imgA:sample(ix, c1y) ~= imgB:sample(ix, c1y)
        and imgA:sample(ix, c2y) ~= imgB:sample(ix, c2y),
        "schalter-pixel: aktive Richtung wandert beim Umschalten (A/B unterscheidbar)")
end

-- --- Einmalschalter: nach dem Verbrauch verschwindet er ---------------------
-- Einmalschalter (oneShot) werden nach dem Auslösen dauerhaft gesperrt
-- (State.consumedSwitches) und dann NICHT mehr gezeichnet — die weiße Bahn
-- bleibt frei (kein Schalterkörper, kein aktiver Innenkreis, keine Schraffur).
-- Pixelprobe aus der ECHTEN Render-Pipeline (drawRoom -> drawSwitch).
do
    local oneShotRoom = {
        name = "OneShotGone",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = { { id = "O1", ring = "outer", angle = 90, symbol = 1, onA = "S2", onB = {}, state = "A", oneShot = true } },
        shutters = { { id = "S2", ring = "inner", angle = 45 } },
        bridges = { { id = "B0", angle = 270, free = true } },
        gate = { id = "T", angle = 0, free = true },
    }
    setup(oneShotRoom) -- O1=A, oneShot, noch nicht verbraucht
    check(State.consumedSwitches["O1"] == nil, "oneshot-gone: O1 noch nicht verbraucht")

    local gfxApi = playdate.graphics
    local function renderSwitchCanvas()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then
            error("oneshot-gone-canvas: " .. tostring(err))
        end
        return img
    end

    -- Schalter O1 outer@90 -> Zentrum (304,120); CW-Seite (+tangential, unten)
    -- ist in Zustand A GEFÜLLT schwarz, die CCW-Seite (oben) in Zustand B.
    local swX = 200 + Config.outerRadius * math.sin(math.rad(90))
    local swY = 120 - Config.outerRadius * math.cos(math.rad(90))
    local ix, iy = math.floor(swX + 0.5), math.floor(swY + 0.5)
    local off = Config.switchCircleOffset
    local c1y = math.floor(iy - off + 0.5) -- CCW-Seite (oben; in Zustand B aktiv)
    local c2y = math.floor(iy + off + 0.5) -- CW-Seite (unten; in Zustand A aktiv)

    -- Vor dem Verbrauch: der Schalter ist sichtbar (aktiver CW-Kreis schwarz).
    local imgBefore = renderSwitchCanvas()
    check(imgBefore:sample(ix, c2y) == gfxApi.kColorBlack,
        "oneshot-gone: Schalter vor dem Verbrauch sichtbar (CW-Kreis gefüllt)")

    -- Verbrauch: O1 einmal umlegen -> oneShot dauerhaft gesperrt.
    local changed, _ = State.setSwitch("O1", "B")
    check(changed == true and State.consumedSwitches["O1"] == true,
        "oneshot-gone: O1 verbraucht (oneShot gesperrt)")

    -- Der erste Draw-Frame startet die Verschwinde-Animation (Anspann-Puls,
    -- dann Zusammenfallen) — der Schalter bleibt bis zum Ende sichtbar.
    -- Nach dem Verbrauch steht O1 auf Zustand B: die aktive Füllung sitzt auf
    -- der CCW-Seite (c1y, oben).
    local imgStart = renderSwitchCanvas()
    check(Render.oneShotVanishAnims["O1"] ~= nil,
        "oneshot-gone: Verschwinde-Animation aktiv (kein 1-Frame-Loch)")
    check(imgStart:sample(ix, c1y) == gfxApi.kColorBlack,
        "oneshot-gone: Schalter während der Animation noch sichtbar (CCW-Kreis gefüllt)")

    -- Skala-Verlauf: Anspann > 1, dann Zusammenfallen < 1, Ende ~0.
    local dur = Config.oneShotSwitchVanishDuration
    check(Render.oneShotVanishScale({ t = 0 }) >= 1.0, "oneshot-gone: Startskala 1.0")
    check(Render.oneShotVanishScale({ t = dur * 0.1 }) > 1.0,
        "oneshot-gone: Anspann-Puls (Skala > 1)")
    check(Render.oneShotVanishScale({ t = dur * 0.8 }) < 0.5,
        "oneshot-gone: Zusammenfallen (Skala < 0.5)")
    check(Render.oneShotVanishScale({ t = dur }) <= 0.01, "oneshot-gone: Ende-Skala ~0")

    -- Animation abschließen -> der Schalter ist dauerhaft weg (nur weiße Bahn).
    Render.update(dur + 0.1, false)
    check(Render.oneShotVanishAnims["O1"] == nil and Render.oneShotVanishDone["O1"] == true,
        "oneshot-gone: Animation abgeschlossen")
    local imgAfter = renderSwitchCanvas()
    check(imgAfter:sample(ix, c2y) == gfxApi.kColorWhite
        and imgAfter:sample(ix, c1y) == gfxApi.kColorWhite,
        "oneshot-gone: Schalter nach der Animation nicht mehr gezeichnet (weiße Bahn)")
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

-- --- Brückendarstellung (Design-Legende): aktiv solide konstant, inaktiv Docks+Punkte --
-- AKTIVE Brücken: dicke, vollständig weiße Brücke (solide, keine Punkte).
-- INAKTIVE Brücken: lockere Punktspur (5 Punkte, Spacing ein Sechstel der
-- Länge), keine fertige Verbindung. Aktivierung: nur Dichte-Verdichtung an
-- festen Positionen (bridgeDensityStage) und erst bei p=1 die weiße Form
-- (bridgeSolidProgress). Pixelprobe
-- aus der ECHTEN Render-Pipeline.
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
    local function bridgeSample(angle, tanOff)
        local rMid = (Config.outerRadius + Config.innerRadius) / 2
        local mx = 200 + rMid * math.sin(math.rad(angle))
        local my = 120 - rMid * math.cos(math.rad(angle))
        local tx, ty = math.cos(math.rad(angle)), math.sin(math.rad(angle))
        local off = tanOff or 2
        return math.floor(mx + tx * off + 0.5), math.floor(my + ty * off + 0.5)
    end
    local function bridgeSampleAt(radius, angle)
        local mx = 200 + radius * math.sin(math.rad(angle))
        local my = 120 - radius * math.cos(math.rad(angle))
        return math.floor(mx + 0.5), math.floor(my + 0.5)
    end

    -- Phasen-Helfer (Design-Legende, Dichte-Verdichtung): feste Punkt-
    -- positionen, nur die Dichte wächst; die weiße Form erscheint erst ganz
    -- am Ende (p=1) — kein Wachstum von den Enden zur Mitte.
    check(Render.bridgeDensityStage(0) == 1, "brücke-stufe: p=0 -> Stufe 1 (nur Anker)")
    check(Render.bridgeDensityStage(0.3) == 2, "brücke-stufe: p=0.3 -> Stufe 2 (Mittelpunkte)")
    check(Render.bridgeDensityStage(0.6) == 3, "brücke-stufe: p=0.6 -> Stufe 3 (dichte Achsenlinie)")
    check(Render.bridgeDensityStage(0.9) == 4, "brücke-stufe: p=0.9 -> Stufe 4 (Breite)")
    check(Render.bridgeDensityStage(1) == 5, "brücke-stufe: p=1 -> Stufe 5 (solid)")
    check(Render.bridgeDensityStage(0.24) == 1 and Render.bridgeDensityStage(0.25) == 2
        and Render.bridgeDensityStage(0.49) == 2 and Render.bridgeDensityStage(0.5) == 3
        and Render.bridgeDensityStage(0.74) == 3 and Render.bridgeDensityStage(0.75) == 4,
        "brücke-stufe: Stufengrenzen exakt")
    check(Render.bridgeSolidProgress(0.5) == 0 and Render.bridgeSolidProgress(0.99) == 0,
        "brücke-phase: vor p=1 keine Form (kein Wachstum von den Enden)")
    check(Render.bridgeSolidProgress(1) == 1, "brücke-phase: p=1 -> volle Form")

    setup(makeRenderRoom()) -- S1=A: B0 frei aktiv@270, B1 aktiv@180, T aktiv@0
    local img = renderBridgeCanvas()
    -- Aktive Brücke = dicke, vollständig weiße Form: durchgehend bei ±2,
    -- Breite ~9 (±4 weiß, ±6 schwarz). B1@180: (198,206) abseits des Symbols.
    local ax, ay = bridgeSample(180)
    check(img:sample(ax, ay) == gfxApi.kColorWhite, "brücke-pixel: aktive B1 durchgehend (weiß)")
    local w4x, w4y = bridgeSample(180, 4)
    local b6x, b6y = bridgeSample(180, 6)
    check(img:sample(w4x, w4y) == gfxApi.kColorWhite, "brücke-pixel: aktive B1 dicke weiße Brücke (±4 weiß)")
    check(img:sample(b6x, b6y) == gfxApi.kColorBlack, "brücke-pixel: aktive B1 nicht massiver (±6 schwarz)")
    -- B0@270 (frei): ebenfalls solide (kein Symbol).
    local bx0, by0 = bridgeSample(270)
    check(img:sample(bx0, by0) == gfxApi.kColorWhite, "brücke-pixel: aktive B0 durchgehend (weiß)")

    -- S1=B -> B1 inaktiv: AUSSCHLIESSLICH eine klare Punktspur (5 deutlich
    -- sichtbare identische weiße Punkte bei 74/80/86/92/98; die Endpunkte bei
    -- 68/104 liegen auf den weißen Ringbahnen und gehen dort in der Bahn auf —
    -- zusammen eine durchgehende Punktspur zwischen den beiden Anschlüssen).
    -- Keine separaten Dock-Blöcke, keine Striche, keine Symbole, keine
    -- Pixelblöcke. B0 bleibt aktiv. Der Kausalitäts-Strichcode sitzt TANGENTIAL
    -- neben dem Brückenkörper (schwarzer Grund), nicht auf der Achse.
    State.setSwitch("S1", "B")
    local img2 = renderBridgeCanvas()
    local function axisSample(radius)
        return bridgeSampleAt(radius, 180)
    end
    local dotOK = true
    for _, rd in ipairs({ 74, 80, 86, 92, 98 }) do
        local x, y = axisSample(rd)
        if img2:sample(x, y) ~= gfxApi.kColorWhite then dotOK = false end
    end
    check(dotOK, "brücke-pixel: inaktive B1 reine Punktspur (identische Punkte weiß)")
    local gapOK = true
    for _, rg in ipairs({ 77, 83, 89, 95 }) do
        local x, y = axisSample(rg)
        if img2:sample(x, y) ~= gfxApi.kColorBlack then gapOK = false end
    end
    check(gapOK, "brücke-pixel: inaktive B1 Lücken zwischen den Punkten (schwarz)")
    local cx, cy = axisSample(86)
    check(img2:sample(cx, cy) == gfxApi.kColorWhite,
        "brücke-pixel: Brückenmitte = Punkt (kein Symbol auf der Achse)")
    check(img2:sample(bx0, by0) == gfxApi.kColorWhite, "brücke-pixel: B0 bleibt aktiv (weiß)")

    -- Inaktive B1: Punktabstand exakt ein Sechstel der Brückenlänge (6 px).
    local spacing = (Config.outerRadius - Config.innerRadius) / 6
    check(math.abs(math.abs(86 - 80) - spacing) < 0.01 and math.abs(math.abs(92 - 86) - spacing) < 0.01,
        "brücke-pixel: Punkte gleichmäßig (Spacing = " .. tostring(spacing) .. ")")
end

-- --- Kernbrücke (Gate) = NORMALE Brücke zum Kern (Center-Bridge-Fix) ------
-- Das Tor wird über drawBridgeSegment gezeichnet: exakt dieselbe Darstellung
-- wie eine Ring->Ring-Brücke — gleiche Breite (bridgeBodyWidth), gleiche
-- weiße Fläche, gleiche Punktspur im inaktiven Zustand, gleiche Achse. Nur
-- das Ziel ist der sichtbare Kernrand statt des äußeren Rings.
do
    local gfxApi = playdate.graphics
    local function renderGateCanvas(room)
        setup(room)
        Render.resetPlayerVisual()
        Render.visualTime = 0
        Render.currentRoomIndex = 1
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then error("gate-canvas: " .. tostring(err)) end
        return img
    end
    local function gateSample(radius, angle, tanOff)
        local mx = 200 + radius * math.sin(math.rad(angle))
        local my = 120 - radius * math.cos(math.rad(angle))
        local tx, ty = math.cos(math.rad(angle)), math.sin(math.rad(angle))
        local off = tanOff or 0
        return math.floor(mx + tx * off + 0.5), math.floor(my + ty * off + 0.5)
    end

    -- Aktives Gate (frei): dicke, vollständig weiße Brücke inner -> Kernrand.
    -- Pixelprobe auf der Achse in der Brückenmitte (inner+Kern)/2.
    local gateRoom = {
        name = "GateCanvas",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 0 },
        switches = {},
        shutters = {},
        bridges = {},
        gate = { id = "T", angle = 90, free = true },
    }
    local coreEdge = Config.coreRadius -- Raum 1, visualTime 0 -> Kernrand
    local gMid = (Config.innerRadius + coreEdge) / 2
    local img = renderGateCanvas(gateRoom)
    local gax, gay = gateSample(gMid, 90, 0)
    check(img:sample(gax, gay) == gfxApi.kColorWhite, "gate-pixel: aktive Kernbrücke durchgehend (weiß)")
    local gw4x, gw4y = gateSample(gMid, 90, 4)
    local gw6x, gw6y = gateSample(gMid, 90, 6)
    check(img:sample(gw4x, gw4y) == gfxApi.kColorWhite, "gate-pixel: Kernbrücke dicke weiße Brücke (±4 weiß)")
    check(img:sample(gw6x, gw6y) == gfxApi.kColorBlack, "gate-pixel: Kernbrücke nicht massiver (±6 schwarz)")
    -- Bündiger Anschluss an den Mittelpunkt: die Kernbrücke endet mit einer
    -- kleinen Überlapp IN den Kern (coreBridgeOverlap) — auf der Achse direkt
    -- an der Kernkante (und 1 px im Kern) ist die Verbindung vollflächig weiß
    -- (keine sichtbare schwarze Lücke zwischen Brücke und Mittelpunkt).
    local jx, jy = gateSample(coreEdge - 1, 90, 0)
    check(img:sample(jx, jy) == gfxApi.kColorWhite,
        "gate-pixel: Kernbrücke bündig am Kern (keine Lücke)")

    -- Inaktives Gate: reine Punktspur auf der Achse (5-7 identische Punkte),
    -- keine dünne Speiche, kein Stummel, keine Irisspitze. Punkte außerhalb
    -- der Kernfläche geprüft (der letzte Anker läge auf dem Kernrand).
    local gateRoomInactive = {
        name = "GateCanvasInactive",
        rings = { outer = 7, inner = 6 },
        start = { ring = "inner", angle = 0 },
        switches = {
            { id = "S1", ring = "outer", angle = 180, symbol = 1, onA = {}, onB = "T", state = "A" },
        },
        shutters = {},
        bridges = {},
        gate = { id = "T", angle = 90, free = false },
    }
    local img2 = renderGateCanvas(gateRoomInactive)
    check(Render.bridgeVisualState("T") == "inactive", "gate-inaktiv: T inaktiv (S1=A)")
    -- Die Kernbrücke reicht bis (Kernrand - coreBridgeOverlap) in den Kern;
    -- die Anker der Punktspur liegen also zwischen inner und dieser Kante.
    local coreEnd = coreEdge - Config.coreBridgeOverlap
    local L = Config.innerRadius - coreEnd
    local anchorStep = L / 6
    local gdotOK = true
    for i = 0, 5 do -- Anker 68..39.7 (klar außerhalb des Kerns)
        local r = Config.innerRadius - anchorStep * i
        local x, y = gateSample(r, 90, 0)
        if img2:sample(x, y) ~= gfxApi.kColorWhite then gdotOK = false end
    end
    check(gdotOK, "gate-inaktiv: Punktspur auf der Achse (identische Punkte weiß)")
end

-- --- Player am Mittelpunkt (nach Kernbrücken-Abschluss, rein visuell) -----
do
    setup(makeRenderRoom()) -- start outer@0
    Render.currentRoomIndex = 1
    Render.visualTime = 0
    check(Render.playerRadius() == Config.outerRadius, "playeratcenter: normal auf Ring")
    Render.notePlayerAtCenter()
    check(Render.playerAtCenter == true, "playeratcenter: Flag gesetzt")
    check(approx(Render.playerRadius(), Config.coreRadius), "playeratcenter: Radius = Kernrand")
    -- Reset bei Raumstart (resetPlayerVisual -> resetObjectAnims).
    Render.resetPlayerVisual()
    check(Render.playerAtCenter == false, "playeratcenter: Reset bei Raumstart")
end

-- --- Einmal-Motiv (grobe Diagonalschraffur, gleiche Form) ------------------
-- Einmalschalter = normale weiße Schalterform + schwarze Schraffur; Einmal-
-- Brücke = normale weiße Brückenform + dieselbe schwarze Schraffur. Pixel-
-- Vergleich bei identischer Geometrie: beide Körper verlieren weiße Pixel
-- (schwarze Striche auf weißem Grund) — ohne weitere Formänderung.
do
    local gfxApi = playdate.graphics
    local function countWhiteIn(img, x0, y0, w, h)
        local c = 0
        for yy = y0, y0 + h - 1 do
            for xx = x0, x0 + w - 1 do
                if img:sample(xx, yy) == gfxApi.kColorWhite then c = c + 1 end
            end
        end
        return c
    end
    local function baseRoom(oneShot)
        return {
            name = "Hatch",
            rings = { outer = 7, inner = 6 },
            start = { ring = "outer", angle = 0 },
            switches = {
                { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A",
                    oneShot = oneShot and true or nil },
            },
            shutters = { { id = "D1", ring = "inner", angle = 180 } },
            bridges = {
                { id = "B1", angle = 180, free = false, oneShot = oneShot and true or nil },
            },
            gate = { id = "T", angle = 270, free = true },
        }
    end
    local function renderRoom(r)
        setup(r)
        Render.resetPlayerVisual()
        Render.visualTime = 0
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then error("hatch-canvas: " .. tostring(err)) end
        return img
    end

    local imgNormal = renderRoom(baseRoom(false))
    local imgOneShot = renderRoom(baseRoom(true))

    -- Schalterkörper (S1@90 outer): identische Grundform, WENIGER weiße Pixel
    -- durch die schwarze Schraffur auf dem weißen Körper.
    local sx = math.floor(200 + Config.outerRadius * math.sin(math.rad(90)) + 0.5)
    local sy = math.floor(120 - Config.outerRadius * math.cos(math.rad(90)) + 0.5)
    local nSw = countWhiteIn(imgNormal, sx - 14, sy - 7, 28, 14)
    local oSw = countWhiteIn(imgOneShot, sx - 14, sy - 7, 28, 14)
    check(oSw < nSw, "einmal-schalter: Diagonalschraffur reduziert weiße Pixel im Körper (n=" .. nSw .. " -> o=" .. oSw .. ")")

    -- Brückenkörper (B1@180, aktiv): identische Form, weniger weiße Pixel
    -- durch die schwarze Schraffur auf der weißen Form.
    local nBr = countWhiteIn(imgNormal, 195, 186, 11, 40)
    local oBr = countWhiteIn(imgOneShot, 195, 186, 11, 40)
    check(oBr < nBr, "einmal-brücke: Diagonalschraffur reduziert weiße Pixel (n=" .. nBr .. " -> o=" .. oBr .. ")")

    -- INAKTIVE Einmal-Brücke (state B): Punktspur + reduzierte WEISSE Schraffur
    -- in den Lücken zwischen den Punkten -> mehr weiße Pixel als bei der
    -- normalen inaktiven Brücke (die Einmal-Eigenschaft bleibt erkennbar).
    local function baseRoomInactive(oneShot)
        local r = baseRoom(oneShot)
        r.switches[1].state = "B"
        return r
    end
    local imgNIn = renderRoom(baseRoomInactive(false))
    local imgOIn = renderRoom(baseRoomInactive(true))
    local nIn = countWhiteIn(imgNIn, 195, 186, 11, 40)
    local oIn = countWhiteIn(imgOIn, 195, 186, 11, 40)
    check(oIn > nIn,
        "einmal-brücke-inaktiv: reduzierte Schraffur erhöht weiße Pixel (n=" .. nIn .. " -> o=" .. oIn .. ")")

    -- Kein Zerfall-Redesign: unbenutzte Einmal-Brücke rendert wie die normale
    -- (Form bleibt; nur die Schraffur unterscheidet) — die Kollaps-Darstellung
    -- wird gesondert über State.consumedBridges getestet (unverändert).
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

-- --- Transitradius KERNBRÜCKE (Ziel = Kernrand, gleiche Linearität) ------
do
    setup(makeRenderRoom()) -- rings 7/6, Camera.init(7), Kernbasis Raum 1 = 34
    Render.currentRoomIndex = 1
    Render.visualTime = 0 -- Kernpuls = 0
    local coreEdge = Config.coreRadius + 0 -- corePulseOffset(0) = 0
    check(approx(Render.transitRadius(0, "inner", "center"), Config.innerRadius),
        "center-radius: p0 -> innerRadius")
    check(approx(Render.transitRadius(1, "inner", "center"), coreEdge),
        "center-radius: p1 -> Kernrand")
    check(approx(Render.transitRadius(0.5, "inner", "center"), (Config.innerRadius + coreEdge) / 2),
        "center-radius: p0.5 -> Mitte zwischen Ring und Kern")
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
    -- Shutter-Runtime nur prüfen, wenn der Raum Blenden hat (Raum 1 = Einstieg
    -- ohne Blenden; die Read-only-Eigenschaft gilt dann trivial).
    local shutterBefore = Room.shutters["D1"] and Room.shutters["D1"].collisionActive
    local camBefore = Camera.getCurrentOuterRing()
    local okDraw = pcall(Render.drawRoom, false, 1)
    check(okDraw, "8.2 read-only: drawRoom läuft fehlerfrei")
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "8.2 read-only: State.player unverändert")
    check(Undo.count() == undoBefore, "8.2 read-only: Undo unverändert")
    if Room.shutters["D1"] then
        check(Room.shutters["D1"].collisionActive == shutterBefore, "8.2 read-only: Shutter-Runtime unverändert")
    end
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

-- --- Design-Legende: Future-Ring (nächster innerer Ring) -------------------
do
    -- Raum 1 (outer 7, inner 6): Future-Ring = Ring 5 bei 32 px.
    State.init(Levels[1])
    Room.init()
    Camera.init(7)
    check(Render.futureRingNumber() == 5, "future: Raum 1 (7/6) -> Ring 5")
    local expected = Config.outerRadius - 2 * (Config.outerRadius - Config.innerRadius)
    check(approx(Render.futureRingRadius(), expected, 1e-6), "future: Radius = Ring inner-1 (32 px)")

    -- Raum 2 (outer 6, inner 5): Future-Ring = Ring 4 bei 32 px.
    State.init(Levels[2])
    Room.init()
    Camera.init(6)
    check(Render.futureRingNumber() == 4, "future: Raum 2 (6/5) -> Ring 4")
    check(approx(Render.futureRingRadius(), expected, 1e-6), "future: Raum 2 Radius 32 px")

    -- Raumtransition (Design-Legende, future -> active): der bisherige
    -- Future-Ring wird zum neuen aktiven Innenring (dieselbe Ringnummer 5);
    -- danach beginnt der Zyklus mit einem NEUEN Future-Ring (4) bei 32 px neu.
    Camera.beginRoomTransition(7, 6, 6, 5, 0)
    Camera.update(Config.cameraDuration) -- vollständig abschließen
    State.init(Levels[2])
    Room.init()
    check(State.room.rings.inner == 5, "future->active: neuer Innenring = alter Future-Ring (5)")
    check(Render.futureRingNumber() == 4, "future: Raum 2 -> neuer Future-Ring 4")
    check(approx(Render.futureRingRadius(), expected, 1e-6), "future: neuer Future-Ring bei 32 px")

    -- Raum 6 (inner = 1): kein Future-Ring (Ring 0 = Zentrum/Ende).
    State.init(Levels[6])
    Room.init()
    Camera.init(2)
    check(Render.futureRingNumber() == nil, "future: Raum 6 (2/1) -> kein Future-Ring")
    check(Render.futureRingRadius() == nil, "future: Raum 6 -> kein Radius")

    -- Finalraum 7 (inner = 0): ebenfalls kein Future-Ring (inner-1 < 1).
    State.init(Levels[7])
    Room.init()
    Camera.init(1)
    check(Render.futureRingNumber() == nil, "future: Finalraum 7 (1/0) -> kein Future-Ring")
    check(Render.futureRingRadius() == nil, "future: Finalraum 7 -> kein Radius")
end

-- --- Design-Legende: Future-Ring-Zentrumsregel (nur im Kernbereich) ---------
-- ZENTRUMS-REGEL (Auftrag „Level 1 Mitte“): Im normalen Gameplay wird der
-- Future-Ring NUR gezeichnet, wenn er innerhalb der Kernfläche liegt (Raum 2+:
-- Kern 38 px > Future-Ring 32 px). Liegt er außerhalb/auf dem Kernrand (Raum 1:
-- Kern 32 px, Future-Ring 32 px), entfällt er — sonst erschiene um den Kern
-- ein zusätzlicher pulsierender Outline-Ring. Level 1 hat damit im Zentrum
-- exakt dieselbe Darstellung wie die späteren Level: nur die pulsierende
-- Kernfläche.
do
    -- Raum 1 (Kern 32 px, Future-Ring 32 px): KEIN Ring um den Kern.
    State.init(Levels[1])
    Room.init()
    Camera.init(7)
    Render.resetPlayerVisual()
    Render.visualTime = 0 -- deterministische Pulsphase (Puls-Offset 0)
    local gfxApi = playdate.graphics
    local img = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img)
    local ok, err = pcall(function() Render.drawRoom(false, 1) end)
    gfxApi.popContext()
    if not ok then error("future-pixel: " .. tostring(err)) end
    -- Am Radius coreRadius+4 (klar außerhalb des Kerns) darf KEINE weiße
    -- Ringbande liegen (der zusätzliche pulsierende Outline-Ring ist entfernt).
    -- Das Tor (Kernbrücke) erreicht den Kern und liegt dort bewusst auf der
    -- Achse (Level-1-Tor inner@135) — deshalb wird nur die Ringbande ABSEITS
    -- der Torachse geprüft.
    local probeR = Config.coreRadius + 4
    local ringWhite = 0
    local gateAxis = Levels[1].gate.angle -- Torachse (Kernbrücke) ausklammern
    for i = 1, 23 do -- 15°..345°
        local a = i * 15
        if math.abs(Geometry.delta(a, gateAxis)) > 10 then
            local x = math.floor(200 + probeR * math.sin(math.rad(a)) + 0.5)
            local y = math.floor(120 - probeR * math.cos(math.rad(a)) + 0.5)
            if img:sample(x, y) == gfxApi.kColorWhite then ringWhite = ringWhite + 1 end
        end
    end
    check(ringWhite == 0, "future-pixel: Raum 1 KEIN Future-Ring um den Kern (Zentrumsregel)")

    -- Raum 2 (Kern 38 px, Future-Ring 32 px im Kernbereich): der Future-Ring
    -- wird weiterhin gezeichnet (nächster Ring „entsteht“ im Kern).
    State.init(Levels[2])
    Room.init()
    Camera.init(6)
    Render.resetPlayerVisual()
    Render.visualTime = 0
    local img2 = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img2)
    ok, err = pcall(function() Render.drawRoom(false, 2) end)
    gfxApi.popContext()
    if not ok then error("future-pixel2: " .. tostring(err)) end
    local coreRingWhite = 0
    for i = 0, 23 do
        local x = math.floor(200 + 32 * math.sin(math.rad(i * 15)) + 0.5)
        local y = math.floor(120 - 32 * math.cos(math.rad(i * 15)) + 0.5)
        if img2:sample(x, y) == gfxApi.kColorWhite then coreRingWhite = coreRingWhite + 1 end
    end
    check(coreRingWhite >= 22, "future-pixel: Raum 2 Future-Ring weiterhin im Kernbereich gezeichnet")
end

-- --- Echo-Ring-Regel auch WÄHREND der Transition (kein Wiederauftauchen) ----
-- Der zusätzliche dünne Ring um den zentralen Kern darf NICHT nur im normalen
-- Level 1 fehlen, sondern auch während des Raumwechsels nicht erscheinen
-- (der alte Future-Ring beginnt seine Morph-Reise dicht am Kern — sonst wäre
-- der Echo-Ring während der Transition wieder sichtbar).
do
    State.init(Levels[1])
    Room.init()
    Camera.init(7)
    Render.resetPlayerVisual()
    Render.visualTime = 0
    -- Aktive Transition 1 -> 2 (Phase A, neuer Raum noch nicht geladen).
    RoomTransition.reset()
    RoomTransition.start(2)
    Camera.beginRoomTransition(7, 6, 6, 5, 0, Config.roomTransitionDuration)
    Camera.update(Config.roomTransitionDuration * 0.1)
    check(Camera.isTransitioning() == true and not RoomTransition.isNewRoomLoaded(),
        "future-trans: Transition läuft (Phase A)")
    local gfxApi = playdate.graphics
    local img = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img)
    local ok, err = pcall(function() Render.drawRoom(false, 1) end)
    gfxApi.popContext()
    if not ok then error("future-trans-pixel: " .. tostring(err)) end
    -- Am Radius coreRadius+4 (klar außerhalb des Kerns) darf während der
    -- Transition KEINE weiße Echo-Ringbande liegen (Torachse des alten Raums
    -- ausgeklammert: dort erreicht die Kernbrücke den Kern — Level-1-Tor@135).
    local probeR = Config.coreRadius + 4
    local echoWhite = 0
    local gateAxis2 = Levels[1].gate.angle
    for i = 1, 23 do -- 15°..345°
        local a = i * 15
        if math.abs(Geometry.delta(a, gateAxis2)) > 10 then
            local x = math.floor(200 + probeR * math.sin(math.rad(a)) + 0.5)
            local y = math.floor(120 - probeR * math.cos(math.rad(a)) + 0.5)
            if img:sample(x, y) == gfxApi.kColorWhite then echoWhite = echoWhite + 1 end
        end
    end
    check(echoWhite == 0, "future-trans: KEIN Echo-Ring um den Kern während der Transition")
    RoomTransition.reset()
    Camera.reset()
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

-- --- Keine zusätzlichen Marker auf Schaltern -------------------------------
-- Schalter tragen ausschließlich ihre eigene Form (weißer Rounded-Block + zwei
-- schwarze Innenkreise; Einmal zusätzlich Schraffur). KEINE Strichcodes, KEINE
-- externen Kausalitätsmarker neben dem Schalter.
do
    local gfxApi = playdate.graphics
    local room = {
        name = "NoMark",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" },
        },
        shutters = { { id = "D1", ring = "outer", angle = 180 } },
        bridges = {
            { id = "B0", angle = 270, free = true },
            { id = "B1", angle = 0, free = false },
        },
        gate = { id = "T", angle = 180, free = true },
    }
    setup(room)
    local img = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img)
    local ok, err = pcall(function() Render.drawRoom(false, 1) end)
    gfxApi.popContext()
    if not ok then error("nomark-canvas: " .. tostring(err)) end
    -- Außerhalb der Bahn neben dem Schalter (wo früher der Strichcode saß):
    -- KEIN weißer Marker mehr (schwarzer Grund).
    local mx = math.floor(200 + (Config.outerRadius + 7) * math.sin(math.rad(90)) + 0.5)
    local my = math.floor(120 - (Config.outerRadius + 7) * math.cos(math.rad(90)) + 0.5)
    check(img:sample(mx, my) == gfxApi.kColorBlack,
        "schalter-marker: kein Code neben dem Schalter (schwarz)")
    -- Der Schalterkörper selbst bleibt unverändert (weißer Block in der Mitte).
    local bxc = math.floor(200 + Config.outerRadius * math.sin(math.rad(90)) + 0.5)
    local byc = math.floor(120 - Config.outerRadius * math.cos(math.rad(90)) + 0.5)
    check(img:sample(bxc, byc) == gfxApi.kColorWhite, "schalter-marker: Körper-Zentrum weiß (eigene Form)")
end

-- --- Blockade-Mittelpunkt (Design-Punkt, kein Kausalitätssymbol) ----------
-- Geschlossene Blockade: exakt im Zentrum des Sperrsegments sitzt ein klarer
-- WEISSER Punkt auf dem schwarzen Block. Geöffnet: sehr reduzierter SCHWARZER
-- Positionspunkt auf der weißen Bahn (Bahn bleibt dominant, keine Sperre).
do
    local gfxApi = playdate.graphics
    local room = {
        name = "ShutDot",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = {
            { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" },
        },
        shutters = { { id = "D1", ring = "outer", angle = 180 } },
        bridges = {
            { id = "B0", angle = 270, free = true },
            { id = "B1", angle = 0, free = false },
        },
        gate = { id = "T", angle = 180, free = true },
    }
    setup(room)
    -- S1=A -> D1 geschlossen (onB inaktiv).
    State.setSwitch("S1", "A")
    Room.syncPhysicalShutters()
    local img = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img)
    local ok, err = pcall(function() Render.drawRoom(false, 1) end)
    gfxApi.popContext()
    if not ok then error("shutdot-canvas: " .. tostring(err)) end
    local ccx = math.floor(200 + Config.outerRadius * math.sin(math.rad(180)) + 0.5)
    local ccy = math.floor(120 - Config.outerRadius * math.cos(math.rad(180)) + 0.5)
    check(ccx == 200 and ccy == 224, "blockade-punkt: Zentrum exakt auf der Achse (200,224)")
    check(img:sample(ccx, ccy) == gfxApi.kColorWhite,
        "blockade-punkt: geschlossene Blockade -> weißer Mittelpunkt")
    -- Geöffnet: reduzierter schwarzer Positionspunkt, Bahn bleibt weiß/dominant.
    State.setSwitch("S1", "B")
    Room.syncPhysicalShutters()
    local img2 = gfxApi.image.new(400, 240)
    gfxApi.pushContext(img2)
    local ok2, err2 = pcall(function() Render.drawRoom(false, 1) end)
    gfxApi.popContext()
    if not ok2 then error("shutdot-open-canvas: " .. tostring(err2)) end
    check(img2:sample(ccx, ccy) == gfxApi.kColorBlack,
        "blockade-punkt: offene Blockade -> reduzierter schwarzer Punkt")
    local nx = math.floor(ccx + 6 + 0.5)
    check(img2:sample(nx, ccy) == gfxApi.kColorWhite,
        "blockade-punkt: offen -> Bahn daneben bleibt weiß/dominant")
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
-- Deterministische Blink-Zufallsquelle (0.5 -> Intervall 2.1 s).
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

-- Pflicht-Test 5/6: Blink frühestens ~1.2 s, spätestens ~3 s, deterministisch
do
    Render.resetPlayerVisual()
    check(Render.playerVisual.nextBlinkAt >= Config.blinkMinInterval
        and Render.playerVisual.nextBlinkAt <= Config.blinkMaxInterval, "blink: Termin in [1.2,3] s")
    for i = 1, 58 do Render.update(0.02, false) end -- idleTime ~1.16 < 1.2
    check(Render.playerVisual.blinkFramesRemaining == 0, "blink: <1.2 s kein Blink")
    Render.resetPlayerVisual()
    local firstBlinkAtIdle = nil
    for i = 1, 400 do
        Render.update(0.02, false)
        if Render.playerVisual.blinkFramesRemaining > 0 and not firstBlinkAtIdle then
            firstBlinkAtIdle = Render.playerVisual.idleTime
        end
    end
    check(firstBlinkAtIdle ~= nil, "blink: tritt auf")
    check(firstBlinkAtIdle >= Config.blinkMinInterval - 0.02, "blink: frühestens ~1.2 s")
    check(firstBlinkAtIdle <= Config.blinkMaxInterval + 0.02, "blink: spätestens ~3 s")
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

-- --- Atmosphere: Brücken-Materialisierung (Trigger, retracting, Fortschritt) ---
do
    Render.resetObjectAnims()
    setup(makeRenderRoom()) -- S1=A -> B1 aktiv; B0/T frei aktiv
    -- Erster Frame: keine Schein-Anims für bereits aktive Brücken.
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] == nil and Render.bridgeAnims["B0"] == nil,
        "brücken-anim: kein Anim ohne false->true-Wechsel")
    -- active -> inactive startet das Rückwärts-Einfahren (Deaktivierung:
    -- volle Brücke -> breite Punktstruktur -> dichte Mittelachse -> 5-7 Punkte).
    State.setSwitch("S1", "B")
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] ~= nil and Render.bridgeAnims["B1"].state == "retracting",
        "brücken-anim: aktiv->inaktiv startet retracting")
    -- Retracting läuft aus (wieder Punktspur).
    local bTotal = Config.bridgeExtendDuration
    for i = 1, math.ceil((bTotal + 0.1) / 0.02) do Render.update(0.02) end
    check(Render.bridgeAnims["B1"] == nil, "brücken-anim: retracting ausgelaufen (Punkte)")
    -- inactive -> active startet das Ausfahren mit kleinem Anfangsforschritt.
    State.setSwitch("S1", "A")
    Render.update(0.02)
    check(Render.bridgeAnims["B1"] ~= nil and Render.bridgeAnims["B1"].p > 0
        and Render.bridgeAnims["B1"].p < 1,
        "brücken-anim: false->true startet Ausfahren")
    -- Nach Ausfahr- + Settle-Dauer ist die Animation abgeräumt.
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
    check(Render.finalMomentDriftTime ~= nil, "final: Zeitbasis eingefroren")
    check(Render.completionPulseT == 0, "final: zeigt Systemimpuls")
    -- Zeitbasis bleibt eingefroren (die Welt steht still; History rendert
    -- keinen Drift mehr, die Zeitbasis ist aber stabil und deterministisch).
    local tbA = Render.finalMomentDriftTime
    Render.visualTime = Render.visualTime + 1.0
    check(Render.finalMomentDriftTime == tbA, "final: Zeitbasis eingefroren (statisch)")
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

-- --- Atmosphere: Idle-Herumschauen (ZUFÄLLIGER kurzer Blick, neugierig) ----
-- Nach einer zufälligen Ruhezeit (1.5-2.5 s) beginnt ein kurzer Blick in eine
-- ZUFÄLLIGE Richtung (innen/außen/CW/CCW/neutral), wird 0.4-1.0 s gehalten und
-- kehrt sanft zurück. Rein visuell; deterministisch über Render.idleLookRandom.
do
    setup(makeRenderRoom())
    State.player.ring = "outer"
    State.player.angle = 0 -- 12 Uhr
    Render.idleLookRandom = function() return 0.5 end -- deterministisch
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5) -- facing CW, idleTime 0
    local pv = Render.playerVisual
    local il = pv.idleLook
    local bx, by = Render.playerScreenPosition()
    local g0x, g0y = Render.playerEyePosition()
    -- Mit random 0.5: erste Ruhe = 2.0 s, Blickrichtung CW, Halt 0.7 s.
    local lookAt = Config.idleLookFirstRestMin
        + 0.5 * (Config.idleLookFirstRestMax - Config.idleLookFirstRestMin)
    -- 1) Vor der Ruhezeit: rest, keine Blickbewegung.
    for _ = 1, math.floor((lookAt - 0.5) * 50) do Render.update(0.02, false) end
    check(il.state == "rest", "idle-look: vor Ruhezeit rest")
    local g2x, g2y = Render.playerEyePosition()
    check(g2x == g0x and g2y == g0y, "idle-look: vor Ruhezeit keine Blickbewegung")
    -- 2) Nach der Ruhezeit + Einschwenken: Blick aktiv, Pupille weicht ab.
    for _ = 1, math.floor((0.5 + Config.idleLookMoveTime + 0.1) * 50) do Render.update(0.02, false) end
    check(il.state ~= "rest", "idle-look: Blick begonnen (nach Ruhezeit)")
    local g1x, g1y = Render.playerEyePosition()
    check(g1x ~= g0x or g1y ~= g0y, "idle-look: Pupille weicht ab (neugieriger Blick)")
    -- 3) Blick wird gehalten (0.4-1.0 s): kurz nach dem Einschwenken noch aktiv.
    local heldActive = false
    for _ = 1, math.floor((Config.idleLookHoldMin * 0.5) * 50) do
        Render.update(0.02, false)
        if il.state ~= "rest" then heldActive = true end
    end
    check(heldActive, "idle-look: Blick wird gehalten (0.4-1.0 s)")
    -- 4) Nach Halt + Rückkehr: wieder rest, Pupille in Facing-Lage.
    for _ = 1, math.floor((Config.idleLookHoldMax + Config.idleLookReturnTime + 0.3) * 50) do
        Render.update(0.02, false)
    end
    check(il.state == "rest", "idle-look: Blick kehrt zurück (wieder rest)")
    local g3x, g3y = Render.playerEyePosition()
    check(g3x == g0x and g3y == g0y, "idle-look: Pupille wieder in Facing-Lage")
    -- 5) Die Pupille bleibt im Körper (Clamp) über viele Zyklen.
    local maxOff = Config.playerBodyRadius - Config.pupilRadius - 0.5
    local clampOK = true
    for _ = 1, 120 do
        Render.update(0.02, false)
        local ex, ey = Render.playerEyePosition()
        local d = math.sqrt((ex - bx) ^ 2 + (ey - by) ^ 2)
        if d > maxOff + 0.01 then clampOK = false end
    end
    check(clampOK, "idle-look: Pupille bleibt im Körper (Clamp)")
    -- 6) Echte Bewegung bricht den Blick ab (Auge orientiert sich neu).
    Render.notePlayerMovement(-5)
    check(il.state == "rest", "idle-look: Bewegung bricht den Blick ab")
    local g6x, g6y = Render.playerEyePosition()
    check(g6x < bx and approx(g6y, by, 0.05),
        "idle-look: nach Bewegung Blick in Bewegungsrichtung (CCW)")
    -- 7) Determinismus: gleiche Zufalls-Sequenz, gleicher Blickverlauf.
    local savedX, savedY = g1x, g1y
    Render.resetPlayerVisual()
    Render.notePlayerMovement(5)
    for _ = 1, math.floor((lookAt + Config.idleLookMoveTime + 0.1) * 50) do Render.update(0.02, false) end
    local g5x, g5y = Render.playerEyePosition()
    check(g5x == savedX and g5y == savedY, "idle-look: deterministisch")
    Render.idleLookRandom = nil
end

Render.blinkRandom = savedBlinkRandom

-- --- Baby-Dock (Referenz-Variante A): vier L-förmige Eckmarken --------------
-- Pixel-Semantik aus der ECHTEN Render-Pipeline: an der gültigen Baby-Dock-
-- position (Babyring auf der Brückenachse) liegen weiße Pixel NUR in den vier
-- Ecken; keine Box, kein Punkt in der Mitte, kein pulsierender Punkt mehr am
-- Brückenmittelpunkt.
do
    local gfxApi = playdate.graphics
    local dockRoom = {
        name = "DockPixel",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 170 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = 180, free = true } },
        gate = nil,
    }
    local function renderDockScene()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then
            error("dock-canvas: " .. tostring(err))
        end
        return img
    end
    local function sampleAt(img, sx, sy)
        if sx < 0 or sy < 0 or sx >= 400 or sy >= 240 then
            return gfxApi.kColorBlack
        end
        return img:sample(sx, sy)
    end

    -- Dock sichtbar: Player nahe der Achse, Baby in Dock-Nähe, aber NICHT
    -- transfer-bereit (> sharedDockRange, damit das Baby nicht auf die Achse
    -- gesnappt wird und die Dockmarken frei bleiben).
    setup(dockRoom)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 170
    State.baby.ring = "outer"
    State.baby.angle = 200
    local b0 = State.room.bridges[1]
    check(Render.babyDockForBridge(b0) == true, "dock-pixel: Dock sichtbar (Vorbereitung)")
    check(Render.babyBridgeReady() == false, "dock-pixel: Baby nicht transfer-bereit (kein Snap)")
    local imgDock = renderDockScene()

    -- Dockzentrum: Babyring-Radius (outer) auf der Brückenachse 180°.
    local ix = math.floor(200 + Config.outerRadius * math.sin(math.rad(180)) + 0.5)
    local iy = math.floor(120 - Config.outerRadius * math.cos(math.rad(180)) + 0.5)
    check(ix == 200 and iy == 224, "dock-pixel: Dockzentrum exakt auf der Achse (200,224)")
    local half = Config.babyDockHalf
    -- WEISSE Dock-Markierungen sind entfernt (Auftrag): beim markierten
    -- Brückenübergang bleibt NUR die schwarze Markierung auf der Brücke.
    -- Die ehemaligen Ecken liegen jetzt auf schwarzem Grund (keine weiße
    -- Baby-Dockmarke mehr).
    check(sampleAt(imgDock, ix - half, iy - half) == gfxApi.kColorBlack, "dock-pixel: keine weiße Dockmarke (oben-links)")
    check(sampleAt(imgDock, ix + half, iy - half) == gfxApi.kColorBlack, "dock-pixel: keine weiße Dockmarke (oben-rechts)")
    check(sampleAt(imgDock, ix - half, iy + half) == gfxApi.kColorBlack, "dock-pixel: keine weiße Dockmarke (unten-links)")
    check(sampleAt(imgDock, ix + half, iy + half) == gfxApi.kColorBlack, "dock-pixel: keine weiße Dockmarke (unten-rechts)")
    -- Die Ecken sind separate L-Winkel (keine vollständige Box, nichts
    -- gefüllt): der Innenpunkt jeder Ecke bleibt schwarz. Die obere/untere
    -- Kante ist in der Mitte von der aktiven Brücke (9 px) überdeckt.
    check(sampleAt(imgDock, ix - half + 1, iy - half + 1) == gfxApi.kColorBlack, "dock-pixel: TL-Ecke L-förmig (innen schwarz)")
    check(sampleAt(imgDock, ix + half - 1, iy - half + 1) == gfxApi.kColorBlack, "dock-pixel: TR-Ecke L-förmig (innen schwarz)")
    check(sampleAt(imgDock, ix - half + 1, iy + half) == gfxApi.kColorBlack, "dock-pixel: BL-Ecke L-förmig (innen schwarz)")
    check(sampleAt(imgDock, ix + half - 1, iy + half) == gfxApi.kColorBlack, "dock-pixel: BR-Ecke L-förmig (innen schwarz)")
    -- KEIN pulsierender Baby-Ready-Punkt mehr am Brückenmittelpunkt.
    local mx = math.floor(200 + (Config.outerRadius + Config.innerRadius) / 2 * math.sin(math.rad(180)) + 0.5)
    local my = math.floor(120 - (Config.outerRadius + Config.innerRadius) / 2 * math.cos(math.rad(180)) + 0.5)
    check(mx == 200 and my == 206, "dock-pixel: Brückenmittelpunkt (200,206)")
    check(sampleAt(imgDock, mx, my) == gfxApi.kColorWhite, "dock-pixel: Brückenmittelpunkt weiß (kein Ready-Punkt)")

    -- Ohne Dock-Kontext (Player weit weg): dieselben Eckpositionen bleiben
    -- schwarz (kein Dock an beliebiger Stelle).
    setup(dockRoom)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 300
    State.baby.ring = "outer"
    State.baby.angle = 200
    check(Render.babyDockForBridge(b0) == false, "dock-pixel: ohne Kontext kein Dock")
    local imgNoDock = renderDockScene()
    check(sampleAt(imgNoDock, ix - half, iy - half) == gfxApi.kColorBlack, "dock-pixel: ohne Kontext Ecke schwarz")
    check(sampleAt(imgNoDock, ix + half, iy + half) == gfxApi.kColorBlack, "dock-pixel: ohne Kontext Ecke schwarz (BR)")
end

-- --- Baby-Dock am TOR/Zielausgang (vier L-Ecken, gleiche Regel wie an Brücken)
-- Das Dock erscheint auch am aktiven Tor, wenn Player UND Baby auf dem Tor-
-- Ring in der Nähe der Torachse stehen. Ohne Kontext (Player weit weg) keine
-- Eckmarken am Tor.
do
    local gfxApi = playdate.graphics
    local gateRoom = {
        name = "GateDock",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "inner", angle = 25 } },
        switches = {},
        shutters = {},
        bridges = {},
        gate = { id = "T", angle = 0, free = true }, -- aktives Tor (frei)
    }
    local function renderGateDockScene()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then error("gatedock-canvas: " .. tostring(err)) end
        return img
    end
    local function sampleAt(img, sx, sy)
        if sx < 0 or sy < 0 or sx >= 400 or sy >= 240 then return gfxApi.kColorBlack end
        return img:sample(sx, sy)
    end

    -- Dock sichtbar: Player und Baby auf dem inneren Ring nahe der Torachse 0°.
    setup(gateRoom)
    Render.resetPlayerVisual()
    State.player.ring = "inner"
    State.player.angle = 20
    State.baby.ring = "inner"
    State.baby.angle = 25
    check(Render.babyDockForGate() == true, "gatedock: aktives Tor + Figuren in Position -> Dock sichtbar")
    local imgDock = renderGateDockScene()
    -- Dockzentrum: Torachse auf dem inneren Ring (200, 52).
    local ix = math.floor(200 + Config.innerRadius * math.sin(math.rad(0)) + 0.5)
    local iy = math.floor(120 - Config.innerRadius * math.cos(math.rad(0)) + 0.5)
    check(ix == 200 and iy == 52, "gatedock: Dockzentrum exakt auf der Torachse (200,52)")
    local half = Config.babyDockHalf
    -- KEINE weißen Dock-Markierungen am Tor mehr (nur noch die schwarze
    -- Markierung auf der Brücke). Die ehemaligen Ecken liegen auf Schwarz.
    check(sampleAt(imgDock, ix - half, iy - half) == gfxApi.kColorBlack, "gatedock: keine weiße Dockmarke (oben-links)")
    check(sampleAt(imgDock, ix + half, iy - half) == gfxApi.kColorBlack, "gatedock: keine weiße Dockmarke (oben-rechts)")
    check(sampleAt(imgDock, ix - half, iy + half) == gfxApi.kColorBlack, "gatedock: keine weiße Dockmarke (unten-links)")
    check(sampleAt(imgDock, ix + half, iy + half) == gfxApi.kColorBlack, "gatedock: keine weiße Dockmarke (unten-rechts)")
    -- Die Ecken sind separate L-Winkel (nichts gefüllt).
    check(sampleAt(imgDock, ix - half + 1, iy - half + 1) == gfxApi.kColorBlack, "gatedock: TL-Ecke L-förmig (innen schwarz)")

    -- Ohne Dock-Kontext (Player weit weg): keine Eckmarken am Tor.
    setup(gateRoom)
    Render.resetPlayerVisual()
    State.player.ring = "inner"
    State.player.angle = 200
    State.baby.ring = "inner"
    State.baby.angle = 25
    check(Render.babyDockForGate() == false, "gatedock: ohne Kontext kein Dock")
    local imgNoDock = renderGateDockScene()
    check(sampleAt(imgNoDock, ix - half, iy - half) == gfxApi.kColorBlack, "gatedock: ohne Kontext Ecke schwarz")
    check(sampleAt(imgNoDock, ix + half, iy + half) == gfxApi.kColorBlack, "gatedock: ohne Kontext Ecke schwarz (BR)")
end

-- --- Player-Dock (Auftrag): Klammerform, klar vom Baby-Dock getrennt ----
-- Das Player-Dock zeigt NUR die GEMEINSAME Dockformation (wo der Player hinter
-- dem Baby stehen muss); im Solo-Fall gibt es kein Player-Dock. Die Bridge-
-- SILHOUETTEN erscheinen dagegen NUR, wenn der Player im Wechsel-Radius steht
-- (Bridge.isUsable -> innerhalb dockRange). Testraum: Brücke bei
-- sharedFormationGapDeg -> Formation exakt bei 0° (Klammerbalken achsen-
-- parallel -> robuste Pixelprobe). Pixelprobe aus der ECHTEN Render-Pipeline.
do
    local gfxApi = playdate.graphics
    local pdRoom = {
        name = "PlayerDock",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "outer", angle = 350 } },
        switches = {},
        shutters = {},
        bridges = { { id = "B0", angle = Config.sharedFormationGapDeg, free = true } },
        gate = nil,
    }
    local function renderPlayerDockScene()
        local img = gfxApi.image.new(400, 240)
        gfxApi.pushContext(img)
        local ok, err = pcall(function() Render.drawRoom(false, 1) end)
        gfxApi.popContext()
        if not ok then error("playerdock-canvas: " .. tostring(err)) end
        return img
    end
    local function sampleAt(img, sx, sy)
        if sx < 0 or sy < 0 or sx >= 400 or sy >= 240 then return gfxApi.kColorBlack end
        return img:sample(sx, sy)
    end

    -- GEMEINSAMER Kontext: Player + Baby in Dock-Nähe, Player aber NOCH NICHT
    -- im Wechsel-Radius (20° > dockRange): Player-Dock sichtbar, KEINE
    -- Silhouette auf der Brücke.
    setup(pdRoom)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 30 -- 20° von der Achse (9.86°) -> außerhalb dockRange
    State.baby.ring = "outer"
    State.baby.angle = 350
    local b0 = State.room.bridges[1]
    check(Render.babyDockForBridge(b0) == true, "playerdock: Shared-Kontext aktiv (Baby-Dock sichtbar)")
    local sharedAngle = Render.playerDockForBridge(b0)
    check(sharedAngle ~= nil and sharedAngle ~= b0.angle,
        "playerdock: Shared -> Formation hinter dem Baby (nicht auf der Achse)")
    check(Render.bridgeGhostMode(b0) == nil,
        "playerdock: außerhalb des Wechsel-Radius -> KEINE Silhouette")
    -- Formation exakt 0° (Brücke bei sharedFormationGapDeg, dir=1).
    check(sharedAngle ~= nil and (math.abs(sharedAngle) < 0.01 or math.abs(sharedAngle - 360) < 0.01),
        "playerdock: Formation exakt 0°")

    -- Pixelprobe: Klammerform bei 0° -> Innenbalken radius 97 (y=23),
    -- Außenbalken radius 111 (y=9), tangential x 195..205; Einhak-Füße an den
    -- Balkenenden zur Bahn (Innenbalken nach oben, Außenbalken nach unten).
    -- WEISSE Player-Dock-Klammern sind entfernt (Auftrag): nur noch die
    -- schwarze Markierung auf der Brücke. Alle ehemaligen Balken-/Fuß-
    -- positionen liegen jetzt auf schwarzem Grund.
    local imgDock = renderPlayerDockScene()
    check(sampleAt(imgDock, 200, 23) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (Innenbalken)")
    check(sampleAt(imgDock, 200, 9) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (Außenbalken)")
    check(sampleAt(imgDock, 195, 23) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (links)")
    check(sampleAt(imgDock, 205, 23) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (rechts)")
    check(sampleAt(imgDock, 195, 21) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (Fuß Innen)")
    check(sampleAt(imgDock, 195, 11) == gfxApi.kColorBlack, "playerdock: keine weiße Klammer (Fuß Außen)")
    -- Zwischen den ehemaligen Klammern und der Bahn bleibt schwarz.
    check(sampleAt(imgDock, 200, 22) == gfxApi.kColorBlack, "playerdock: zwischen Klammer und Bahn schwarz (offen)")

    -- Player IM Wechsel-Radius (15°, 5° von der Achse): Silhouetten erscheinen.
    State.player.angle = 15
    check(Render.bridgeGhostMode(b0) == "shared", "playerdock: im Wechsel-Radius -> beide Silhouetten (shared)")

    -- SOLO-Kontext (kein Baby): KEIN Player-Dock (nur gemeinsame Formation);
    -- Silhouette NUR im Wechsel-Radius.
    setup(pdRoom)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 30
    State.baby = nil
    check(Render.playerDockForBridge(b0) == nil,
        "playerdock: Solo -> kein Player-Dock (nur gemeinsame Formation)")
    check(Render.bridgeGhostMode(b0) == nil,
        "playerdock: Solo außerhalb des Wechsel-Radius -> keine Silhouette")
    State.player.angle = 15
    check(Render.bridgeGhostMode(b0) == "player", "playerdock: Solo im Wechsel-Radius -> nur Player-Silhouette")

    -- Ohne Kontext (Player weit weg): kein Dock, keine Silhouette.
    setup(pdRoom)
    Render.resetPlayerVisual()
    State.player.ring = "outer"
    State.player.angle = 200
    State.baby.ring = "outer"
    State.baby.angle = 350
    check(Render.playerDockForBridge(b0) == nil, "playerdock: ohne Kontext kein Dock")
    check(Render.bridgeGhostMode(b0) == nil, "playerdock: ohne Kontext keine Silhouette")
end

-- --- Player-Dock am TOR (gemeinsamer Abschluss) ----------------------------
-- Der Player-Dock erscheint auch am aktiven Tor, wenn das Baby-Dock sichtbar
-- ist (nur Shared — ein Solo-Dock gibt es am Ausgang nicht).
do
    local gateRoom = {
        name = "GatePlayerDock",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        baby = { start = { ring = "inner", angle = 25 } },
        switches = {},
        shutters = {},
        bridges = {},
        gate = { id = "T", angle = 0, free = true },
    }
    setup(gateRoom)
    Render.resetPlayerVisual()
    State.player.ring = "inner"
    State.player.angle = 20
    State.baby.ring = "inner"
    State.baby.angle = 25
    check(Render.babyDockForGate() == true, "gatedock-player: Baby-Dock am Tor sichtbar")
    local pa = Render.playerDockForGate()
    check(pa ~= nil, "gatedock-player: Player-Dock am Tor sichtbar (Shared)")
    if pa then
        check(math.abs(Geometry.delta(pa, Render.sharedFormationAngle(0))) < 0.01,
            "gatedock-player: Formation-Winkel hinter dem Baby")
    end
    -- Ohne Kontext: kein Player-Dock am Tor.
    State.player.angle = 200
    check(Render.playerDockForGate() == nil, "gatedock-player: ohne Kontext kein Dock")
end

TestReport.render = { pass = pass, fail = fail }
