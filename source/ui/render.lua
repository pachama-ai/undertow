-- Render: finales 1-Bit-Raumrendering (Phase 8.2). Zeichnet den kompletten
-- Raumzustand jeden Frame neu (whole-screen redraw, keine Sprites). KEINE
-- Zustandsänderung an Gameplay: liest ausschließlich State/Room/Camera/Bridge
-- und hält nur rein visuellen UI-State (visualTime, playerFacing). Keine
-- Imports; Module werden zentral in main.lua geladen (Room muss VOR Render
-- geladen sein, da Render Room cached).
--
-- Verbindliche Zeichenreihenfolge (ARCHITECTURE / Phase-8-Plan):
--   1. gfx.clear(kColorBlack)
--   2. Geisterringe abgeschlossener Räume (1 px, weiß, Camera-Radius)
--   3. Kern (Dithermuster, wächst mit Raumnummer, langsame Pulsation)
--   4. Bahnen (weiß, trackWidth 8, Camera-Radien)
--   5. Blenden (geschlossen: schwarz + 1 px weiße Kontur + Zähne; offen: Endmarken)
--   6. Brücken (aktiv: 6-px-Balken; eingefahren: zwei 5-px-Stummel)
--   7. Kernbrücke / Gate (inner -> Kern, mit Irisspitze)
--   8. Schalter (11-px-Scheibe, Symbol, zwei tangentiale Pfeilspitzen)
--   9. Elementmarken (dasselbe Symbol, abgeleitet vom steuernden Schalter)
--  10. Spieler (7 px, 1-px-Kontur, 3-px-Auge in Bewegungsrichtung)
--
-- Physische Blendendarstellung (Vertrag Phase 6.2): State.elementStates =
-- logischer Sollzustand, Room.shutters = physischer Zustand
-- (collisionActive/pendingClose). pendingClose wird NICHT wie eine Sperre
-- gezeichnet (offene Darstellung mit Endmarken).
--
-- Ringnummern-Konvention: siehe ui/camera.lua (nach innen abnehmend).

Render = {}

local gfx <const> = playdate.graphics
local config <const> = Config
local geo <const> = Geometry
local state <const> = State
local room <const> = Room

local WHITE <const> = gfx.kColorWhite
local BLACK <const> = gfx.kColorBlack

-- --- Rein visueller UI-State (keine Gameplay-Wahrheit) ---------------------
Render.visualTime = 0

-- B-Hold-Fortschritt für den Restart-Ring (Phase 10.4). 0 = kein Ring, 1 =
-- Schwelle erreicht. Wird NUR von main.lua gesetzt (Controller-Interaktion);
-- Render entscheidet NICHT, wann ein Restart passiert. Kein Gameplay-State.
Render.restartHoldProgress = 0

-- Read-only Setter für den Hold-Fortschritt (geclampt 0..1). Kein Effekt auf
-- State/Undo/Room/Bridge/Camera/Audio/Save.
function Render.setRestartHoldProgress(progress)
    local p = progress or 0
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    Render.restartHoldProgress = p
end

-- Spieler-/Augenanimation (Phase 8.4): reiner UI-State, keine zweite
-- Spielerposition (Ring/Winkel kommen nur aus State.player). Die
-- Brückenstreckung wird zur Laufzeit aus Bridge.isCrossing() und
-- Bridge.getTransitProgress() abgeleitet (kein eigener Bridge-Zustand).
Render.playerVisual = nil
-- Injizierbarer Zufallsgenerator [0,1) für das Blinkintervall; nil = math.random.
-- Tests setzen hier eine deterministische Funktion, um Flakes zu vermeiden.
Render.blinkRandom = nil

-- Wählt das nächste Blinkintervall in [blinkMinInterval, blinkMaxInterval].
-- Nach jedem abgeschlossenen Blink wird NEU gewürfelt (nicht pro Frame).
function Render.pickBlinkInterval()
    local minI = config.blinkMinInterval
    local span = config.blinkMaxInterval - config.blinkMinInterval
    local r = Render.blinkRandom
    if not r then
        r = math.random
    end
    return minI + (r() * span)
end

-- Setzt den rein visuellen Spielerzustand auf Neutral (Raumstart, Undo,
-- Raumabschluss). Kein Gameplay-Effekt.
function Render.resetPlayerVisual()
    Render.playerVisual = {
        facing = 1,                          -- CW-Standard (kein Zufall)
        idleTime = 0,                        -- Stillstandszeit für Blink
        nextBlinkAt = Render.pickBlinkInterval(), -- nächster Blinktermin
        blinkFramesRemaining = 0,
        switchWidenFramesRemaining = 0,
        shutterSquintFramesRemaining = 0,
        wasBlockedLastFrame = false,         -- Flankenerkennung Shutter-Kollision
    }
end
Render.resetPlayerVisual()

-- --- Reine read-only Visual-Helfer (testbar) ------------------------------

-- Bildschirmradius zum Ringnamen über die Kamera (Phase 8.1): liest die
-- World-Ringnummer aus State.room.rings und bildet sie über Camera.getRadius
-- ab. Dadurch wandern alle Elemente während einer Raumtransition mit.
function Render.ringRadius(ringName)
    if ringName ~= "outer" and ringName ~= "inner" then
        error("Render.ringRadius: unbekannter Ring '" .. tostring(ringName) .. "'")
    end
    return Camera.getRadius(state.room.rings[ringName])
end

-- Physischer Blenden-Visualzustand: "closed" | "open" | "pendingClose".
function Render.shutterVisualState(shutterId)
    local phys = room.shutters[shutterId]
    if not phys then
        return "open"
    end
    if phys.collisionActive then
        return "closed"
    end
    if phys.pendingClose then
        return "pendingClose"
    end
    return "open"
end

-- Schalter-Visualzustand: "A" | "B" (aus State.switchStates).
function Render.switchVisualState(switchId)
    return state.switchStates[switchId]
end

-- Brücken-/Gate-Visualzustand: "active" | "inactive" (aus State.elementStates).
function Render.bridgeVisualState(elementId)
    if state.elementStates[elementId] == true then
        return "active"
    end
    return "inactive"
end

-- Radial interpolierter Radius für einen Bridge-Transit (linear).
function Render.transitRadius(progress, fromRing, toRing)
    local fromRadius = Render.ringRadius(fromRing)
    local toRadius = Render.ringRadius(toRing)
    return fromRadius + (toRadius - fromRadius) * progress
end

-- Sichtbarer Spielerradius: während eines Bridge-Transits aus den
-- Transitdaten, sonst aus State.player.ring (Camera-Radius). Keine zweite
-- persistente Spielerposition. Bridge-Transit und Camera-Transition treten
-- nie gleichzeitig auf (beide sperren Input).
function Render.playerRadius()
    if Bridge.isCrossing() then
        local t = Bridge.getTransit()
        local progress = Bridge.getTransitProgress() or 0
        return Render.transitRadius(progress, t.fromRing, t.toRing)
    end
    return Render.ringRadius(state.player.ring)
end

-- Schreibt die rein visuelle Zeit fort (Main ruft dies einmal pro Frame).
-- Keine Gameplaywirkung; läuft auch während Camera-Transition weiter. Blink-
-- Planung läuft nur im Stillstand und in aktiver Szene (kein Transit, keine
-- Camera-Transition, kein Raumabschluss). roomComplete optional (Tests).
function Render.update(dt, roomComplete)
    Render.visualTime = Render.visualTime + dt
    local pv = Render.playerVisual

    -- Blink-Abschluss erkennen (Zähler lief auf 0): neuen Termin planen.
    local wasBlinking = pv.blinkFramesRemaining > 0
    if pv.blinkFramesRemaining > 0 then pv.blinkFramesRemaining = pv.blinkFramesRemaining - 1 end
    local nowBlinking = pv.blinkFramesRemaining > 0
    if wasBlinking and not nowBlinking then
        pv.nextBlinkAt = pv.idleTime + Render.pickBlinkInterval()
    end

    -- Reaktions-Framezähler abbauen (Widen/Squint).
    if pv.switchWidenFramesRemaining > 0 then pv.switchWidenFramesRemaining = pv.switchWidenFramesRemaining - 1 end
    if pv.shutterSquintFramesRemaining > 0 then pv.shutterSquintFramesRemaining = pv.shutterSquintFramesRemaining - 1 end

    -- Blink-Planung nur im Stillstand, ohne aktive Augenreaktion.
    local animatable = not Bridge.isCrossing() and not Camera.isTransitioning() and not roomComplete
    if animatable then
        local eyeBusy = pv.blinkFramesRemaining > 0 or pv.switchWidenFramesRemaining > 0 or pv.shutterSquintFramesRemaining > 0
        if not eyeBusy then
            pv.idleTime = pv.idleTime + dt
            if pv.nextBlinkAt <= 0 then
                pv.nextBlinkAt = Render.pickBlinkInterval()
            end
            if pv.idleTime >= pv.nextBlinkAt then
                pv.blinkFramesRemaining = config.blinkFrames
            end
        end
    end
end

-- Merkt die letzte tatsächliche Bewegungsrichtung (actualDelta, nicht
-- wantedDelta: Kollision kann Bewegung verhindern). Nur echte Spielerbewegung
-- ändert das Facing; DockAssist-Snaps ändern es nicht. Echte Bewegung
-- unterbricht die Blink-Idle: Timer zurücksetzen, geplanten Blink neu termi-
-- nieren und laufenden Blink abbrechen.
function Render.notePlayerMovement(actualDelta)
    local pv = Render.playerVisual
    if actualDelta > 0 then
        pv.facing = 1
    elseif actualDelta < 0 then
        pv.facing = -1
    end
    if actualDelta ~= 0 then
        pv.idleTime = 0
        pv.nextBlinkAt = Render.pickBlinkInterval()
        pv.blinkFramesRemaining = 0
    end
end

-- Schalterkontakt: echter erfolgreicher Trigger durch Vorwärtsbewegung
-- (Room.movePlayer liefert switchChanges>0). Weitet das Auge kurz; Priorität
-- über Blink, unter Squint. Rein visuell, kein Gameplay-Effekt.
function Render.noteSwitchContact()
    local pv = Render.playerVisual
    if pv.shutterSquintFramesRemaining <= 0
        and not Bridge.isCrossing()
        and not Camera.isTransitioning() then
        pv.switchWidenFramesRemaining = config.switchEyeWidenFrames
        pv.blinkFramesRemaining = 0
    end
end

-- Shutter-Kollision: echter blockierter Anstoß (Room.movePlayer -> blocked).
-- Flankenerkennung: nur ein neuer Kollisionsimpuls (false->true) startet das
-- exakt 6-Frame-Zusammenkneifen; gehaltenes Anstoßen verlängert es nicht.
function Render.noteShutterBlocked(blocked)
    local pv = Render.playerVisual
    if blocked then
        if not pv.wasBlockedLastFrame then
            pv.shutterSquintFramesRemaining = config.shutterSquintFrames
            pv.blinkFramesRemaining = 0
            pv.switchWidenFramesRemaining = 0
        end
        pv.wasBlockedLastFrame = true
    else
        pv.wasBlockedLastFrame = false
    end
end

-- Undo: keine neue Reaktion; vorhandene Squint/Widen/Blink auf neutral setzen,
-- damit kein alter Feedbackzustand in den restaurierten State hineinragt.
function Render.noteUndo()
    local pv = Render.playerVisual
    pv.blinkFramesRemaining = 0
    pv.switchWidenFramesRemaining = 0
    pv.shutterSquintFramesRemaining = 0
    pv.wasBlockedLastFrame = false
    pv.idleTime = 0
    pv.nextBlinkAt = Render.pickBlinkInterval()
end

-- Aktuelle Augenreaktion nach Priorität: Squint > Widen > Blink > normal.
function Render.currentEyeReaction()
    local pv = Render.playerVisual
    if pv.shutterSquintFramesRemaining > 0 then return "squint" end
    if pv.switchWidenFramesRemaining > 0 then return "widen" end
    if pv.blinkFramesRemaining > 0 then return "blink" end
    return "normal"
end

-- Radiale Körperstreckung bei Bridge-Transit: sin(pi*progress)*amount,
-- damit Start/Ende Kreis und Mitte maximale Streckung ergeben.
function Render.bridgeStretch(progress)
    return math.sin(math.pi * (progress or 0)) * config.bridgeStretchAmount
end

-- Achsenvektoren des Körpers für eine Ellipsenstreckung: radial nach außen
-- (ax,ay) und tangential CW (bx,by). 0° -> radial vertikal, 90° -> radial
-- horizontal (Winkelkonvention 0° = 12 Uhr, CW positiv).
function Render.bodyAxisVectors(angle)
    local rad = math.rad(angle)
    return math.sin(rad), -math.cos(rad), math.cos(rad), math.sin(rad)
end

-- Aktuelle Augenposition (read-only): tangential in Facing-Richtung von der
-- Spielermitte versetzt. Wird von drawPlayer und Tests genutzt.
-- Bildschirmposition der Spielerfigur (Mittelpunkt, für Körper UND Hold-Ring).
-- Gleiche Berechnung wie drawPlayer: normaler Ring -> Render.playerRadius() +
-- State.player.angle; bei Bridge-Transit -> Transit-Winkel (Körper wandert
-- radial). Damit liegt der Restart-Ring exakt um die sichtbare Figur.
function Render.playerScreenPosition()
    local radius = Render.playerRadius()
    local angle = state.player.angle
    if Bridge.isCrossing() then
        angle = Bridge.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    return x, y, angle
end

function Render.playerEyePosition()
    local radius = Render.playerRadius()
    local angle = state.player.angle
    if Bridge.isCrossing() then
        angle = Bridge.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    local rad = math.rad(angle)
    local off = Render.playerVisual.facing * 1.0
    return x + off * math.cos(rad), y + off * math.sin(rad)
end

-- Ghost-Ringnummern (reine Berechnung): äußere World-Ringnummern der
-- abgeschlossenen Räume, die außerhalb des aktiven Außenrings liegen.
-- Konvention: nach innen abnehmende Nummern (aktueller outer = n, abgeschlossen
-- = n+1, n+2, ...).
function Render.ghostRingNumbers(currentRoomIndex)
    local idx = currentRoomIndex or 1
    local baseOuter = state.room.rings.outer
    local top = baseOuter + (idx - 1)
    local rings = {}
    for ringNumber = baseOuter + 1, top do
        rings[#rings + 1] = ringNumber
    end
    return rings
end

-- Kernbasisradius (ohne Pulsation) für eine Raumnummer.
function Render.coreRadius(currentRoomIndex)
    local idx = currentRoomIndex or 1
    return config.coreRadius + (idx - 1) * config.coreGrowthPerRoom
end

-- Aktueller Pulsations-Offset des Kerns (sinusförmig, rein visuell).
function Render.corePulseOffset()
    return math.sin(Render.visualTime * 2 * math.pi / config.corePulsePeriod) * config.corePulseAmplitude
end

-- Baut den temporären Controller->Element-Lookup: elementId -> Symbol des
-- steuernden Schalters (onA/onB). Freie Elemente (ohne Controller) fehlen.
-- Wird pro Frame für die Elementmarken erstellt; nichts wird in State/Levels
-- gespeichert oder mutiert.
function Render.buildElementSymbolLookup()
    local lookup = {}
    for _, sw in ipairs(state.room.switches) do
        lookup[sw.onA] = sw.symbol
        lookup[sw.onB] = sw.symbol
    end
    return lookup
end

-- Zentraler Symbolrenderer (Punkt 1/2/3), identisch für Switch und
-- Elementmarken. Unbekannte Symbole werden defensiv mit einem Fehler gemeldet.
function Render.drawSymbol(symbol, x, y, size, color)
    gfx.setColor(color)
    if symbol == 1 then
        gfx.fillCircleAtPoint(x, y, math.max(1, math.floor(size * 0.4)))
    elseif symbol == 2 then
        local off = math.max(1, math.floor(size * 0.5))
        local r = math.max(1, math.floor(size * 0.3))
        gfx.fillCircleAtPoint(x - off, y, r)
        gfx.fillCircleAtPoint(x + off, y, r)
    elseif symbol == 3 then
        local w = math.max(3, math.floor(size * 1.2))
        local h = math.max(1, math.floor(size * 0.3))
        gfx.fillRect(x - math.floor(w / 2), y - math.floor(h / 2), w, h)
    else
        error("Render.drawSymbol: unbekanntes Symbol '" .. tostring(symbol) .. "'")
    end
end

-- --- Schaltervorschau (Phase 8.3): rein visuell, read-only ----------------

-- Blinkphase der Preview: 1 vollständiger Zyklus pro Sekunde (0.5 s ON,
-- 0.5 s OFF). Determinismus: (t % periode) < periode/2 -> ON. Nutzt dieselbe
-- visuelle Zeitquelle wie die Kernpulsation (Render.visualTime).
function Render.previewBlinkOn(time)
    local t = time or Render.visualTime
    local period = config.previewBlinkPeriod
    if period <= 0 then
        return true
    end
    return (t % period) < (period / 2)
end

-- Schalter auf demselben Ring wie der Spieler mit strikt < previewRange Grad
-- Abstand (Winkel über Geometry.delta, Wraparound-sicher). Reine Nähe,
-- keine Zustandsänderung.
function Render.nearbyPreviewSwitches()
    local result = {}
    local playerRing = state.player.ring
    for _, sw in ipairs(state.room.switches) do
        if sw.ring == playerRing then
            local d = math.abs(geo.delta(state.player.angle, sw.angle))
            if d < config.switchPreviewRange then
                result[#result + 1] = sw
            end
        end
    end
    return result
end

-- Menge aller hervorgehobenen Element-IDs (onA + onB der nahen Schalter,
-- unabhängig vom aktuellen Schalterzustand: Preview zeigt Zuordnung, nicht
-- Aktivität). Sperrzustände -> leer: Config off, roomComplete, Camera-Transi-
-- tion, Bridge-Transit. Reine UI-Menge; nichts wird in State/Levels gespeichert.
function Render.previewElementIds(roomComplete)
    if not config.switchPreviewEnabled then
        return {}
    end
    if roomComplete then
        return {}
    end
    if Camera.isTransitioning() then
        return {}
    end
    if Bridge.isCrossing() then
        return {}
    end
    local set = {}
    for _, sw in ipairs(Render.nearbyPreviewSwitches()) do
        set[sw.onA] = true
        set[sw.onB] = true
    end
    return set
end

-- --- Zeichenhelfer (nur Grafik, keine Zustandsänderung) -------------------

-- 2) Geisterringe abgeschlossener Räume: 1 px weiße Kreislinien außerhalb des
-- aktiven Außenrings (Camera-Radius), teilweise vom Bildrand geschnitten.
local function drawGhostRings(currentRoomIndex)
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    for _, ringNumber in ipairs(Render.ghostRingNumbers(currentRoomIndex)) do
        local radius = Camera.getRadius(ringNumber)
        if radius > config.outerRadius then
            gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
        end
    end
    gfx.setLineWidth(1)
end

-- 3) Kern: gefüllter Kreis mit 50%-Dither, Radius wächst mit Raumnummer,
-- langsame Pulsation. Dither deterministisch (setDitherPattern), danach Reset.
local function drawCore(currentRoomIndex)
    local radius = Render.coreRadius(currentRoomIndex) + Render.corePulseOffset()
    gfx.setDitherPattern(50)
    gfx.setColor(WHITE)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setDitherPattern(100) -- volle Deckung: kein Pattern-Leak
    gfx.setColor(WHITE)
end

-- 4) Bahn eines Rings: weißer Bogen, trackWidth 8, Camera-Radius.
local function drawTrack(radius)
    gfx.setColor(WHITE)
    gfx.setLineWidth(config.trackWidth)
    gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setLineWidth(1)
end

-- 5) Blende: geschlossen = schwarzer Bogen mit 1 px weißer Kontur und zwei
-- weißen Zähnen; offen/pendingClose = weiße Bahn + zwei kleine Endmarken.
-- previewOn: zusätzl. 1-px-Halo (zweite Außenkontur), niemals Größenwachstum.
local function drawShutter(sh, previewOn)
    local visual = Render.shutterVisualState(sh.id)
    local radius = Render.ringRadius(sh.ring)
    local startAngle = geo.norm(sh.angle - config.shutterArcWidth / 2)
    local endAngle = geo.norm(sh.angle + config.shutterArcWidth / 2)
    if visual == "closed" then
        -- Preview-Halo: zweite weiße Außenkontur 1 px weiter außen (14 px)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.trackWidth + 6)
            gfx.drawArc(config.centerX, config.centerY, radius, startAngle, endAngle)
            gfx.setLineWidth(1)
        end
        -- 1 px weiße Kontur (12-px-Bogen unter dem 10-px-Schwarzblock)
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.trackWidth + 4)
        gfx.drawArc(config.centerX, config.centerY, radius, startAngle, endAngle)
        -- schwarzer Block (unterbricht die weiße Bahn)
        gfx.setColor(BLACK)
        gfx.setLineWidth(config.trackWidth + 2)
        gfx.drawArc(config.centerX, config.centerY, radius, startAngle, endAngle)
        -- zwei weiße Zähne an den Enden
        gfx.setColor(WHITE)
        gfx.setLineWidth(1)
        local e1x, e1y = geo.polar(config.centerX, config.centerY, radius, startAngle)
        local e2x, e2y = geo.polar(config.centerX, config.centerY, radius, endAngle)
        gfx.fillCircleAtPoint(e1x, e1y, 2)
        gfx.fillCircleAtPoint(e2x, e2y, 2)
    else
        -- offen (auch pendingClose): Bahn bleibt weiß, zwei kleine Endmarken
        if previewOn then
            -- 1-px-Außenkontur knapp außerhalb der Bahn über dem Blendbogen
            gfx.setColor(WHITE)
            gfx.setLineWidth(1)
            gfx.drawArc(config.centerX, config.centerY, radius + config.trackWidth / 2 + 1, startAngle, endAngle)
        end
        gfx.setColor(WHITE)
        local m1x, m1y = geo.polar(config.centerX, config.centerY, radius, startAngle)
        local m2x, m2y = geo.polar(config.centerX, config.centerY, radius, endAngle)
        gfx.fillCircleAtPoint(m1x, m1y, 1.5)
        gfx.fillCircleAtPoint(m2x, m2y, 1.5)
    end
end

-- 6) Brücke: aktiv = durchgehender 6-px-Balken; eingefahren = zwei 5-px-Stummel.
-- previewOn: 1-px-Halo je Seite (8-px-Unterbalken). Bei inaktiver Brücke wird
-- die Lücke NICHT geschlossen (beide Stummel separat hervorgehoben).
local function drawBridge(b, previewOn)
    local outerR = Render.ringRadius("outer")
    local innerR = Render.ringRadius("inner")
    local x1, y1 = geo.polar(config.centerX, config.centerY, outerR, b.angle)
    local x2, y2 = geo.polar(config.centerX, config.centerY, innerR, b.angle)
    local visual = Render.bridgeVisualState(b.id)
    if visual == "active" then
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, x2, y2)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, x2, y2)
    else
        local a1x, a1y = geo.polar(config.centerX, config.centerY, outerR - config.stubLength, b.angle)
        local a2x, a2y = geo.polar(config.centerX, config.centerY, innerR + config.stubLength, b.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, a1x, a1y)
            gfx.drawLine(x2, y2, a2x, a2y)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, a1x, a1y)
        gfx.drawLine(x2, y2, a2x, a2y)
    end
    gfx.setLineWidth(1)
end

-- Irisspitze: zwei kurze diagonale Linien (Chevron) am Kernende, Richtung Kern.
-- width optional für die Preview-Hervorhebung (sonst 1 px).
local function drawIrisTip(tipx, tipy, angle, width)
    local w = width or 1
    local rad = math.rad(angle)
    local rx, ry = -math.sin(rad), math.cos(rad) -- Richtung zum Kern
    local tx, ty = math.cos(rad), math.sin(rad)  -- tangential CW
    gfx.setLineWidth(w)
    gfx.drawLine(tipx, tipy, tipx + rx * 3 + tx * 3, tipy + ry * 3 + ty * 3)
    gfx.drawLine(tipx, tipy, tipx + rx * 3 - tx * 3, tipy + ry * 3 - ty * 3)
end

-- 7) Kernbrücke / Gate: Balken inner -> Kern mit Irisspitze (aktiv) oder
-- kurzer Stummel am inneren Ring (inaktiv).
-- previewOn: 1-px-Halo je Seite + verbreiterte Irisspitze; inaktives Gate
-- wird NICHT wie ausgefahren dargestellt.
local function drawGate(previewOn)
    local g = state.room.gate
    if not g then
        return
    end
    local innerR = Render.ringRadius("inner")
    local x1, y1 = geo.polar(config.centerX, config.centerY, innerR, g.angle)
    local visual = Render.bridgeVisualState(g.id)
    if visual == "active" then
        local x2, y2 = geo.polar(config.centerX, config.centerY, config.coreRadius + 4, g.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, x2, y2)
            drawIrisTip(x2, y2, g.angle, 3)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, x2, y2)
        drawIrisTip(x2, y2, g.angle)
    else
        local a1x, a1y = geo.polar(config.centerX, config.centerY, innerR - config.stubLength, g.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, a1x, a1y)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, a1x, a1y)
    end
    gfx.setLineWidth(1)
end

-- Kleine Pfeilspitze (Dreieck) an Position (cx,cy) in Richtung (dirx,diry).
local function drawArrowTip(cx, cy, dirx, diry, perpx, perpy, filled)
    local apexX = cx + dirx * 3
    local apexY = cy + diry * 3
    local bx1 = cx - dirx * 1.5 + perpx * 2
    local by1 = cy - diry * 1.5 + perpy * 2
    local bx2 = cx - dirx * 1.5 - perpx * 2
    local by2 = cy - diry * 1.5 - perpy * 2
    if filled then
        gfx.fillPolygon(apexX, apexY, bx1, by1, bx2, by2)
    else
        gfx.drawPolygon(apexX, apexY, bx1, by1, bx2, by2)
    end
end

-- 8) Schalter: 11-px weiße Scheibe, schwarze Innenfläche, Symbol weiß auf
-- schwarz (Kontrastlösung), zwei tangentiale Pfeilspitzen am Rand (CW/CCW);
-- aktive Marke gefüllt, inaktive nur konturiert.
local function drawSwitch(sw)
    local radius = Render.ringRadius(sw.ring)
    local x, y = geo.polar(config.centerX, config.centerY, radius, sw.angle)
    local isA = Render.switchVisualState(sw.id) == "A"
    local rad = math.rad(sw.angle)
    local tanx, tany = math.cos(rad), math.sin(rad) -- tangential CW
    local perpx, perpy = -tany, tanx                -- radial

    gfx.setColor(WHITE)
    gfx.fillCircleAtPoint(x, y, 5.5) -- 11 px Scheibe
    gfx.setColor(BLACK)
    gfx.fillCircleAtPoint(x, y, 3)   -- schwarze Innenfläche
    -- Symbol weiß auf der schwarzen Innenfläche (lesbar)
    Render.drawSymbol(sw.symbol, x, y, 4, WHITE)
    -- tangentiale Pfeilspitzen: CW aktiv bei Zustand A, CCW aktiv bei B
    gfx.setColor(WHITE)
    drawArrowTip(x + tanx * 4, y + tany * 4, tanx, tany, perpx, perpy, isA)
    drawArrowTip(x - tanx * 4, y - tany * 4, -tanx, -tany, perpx, perpy, not isA)
    gfx.setColor(WHITE)
end

-- 9) Elementmarken: dasselbe Symbol (klein, schwarz) auf jeder gesteuerten
-- Blende/Brücke/Kernbrücke. Auf geschlossener (schwarzer) Blende mit kleiner
-- weißer Trägerfläche. Freie Elemente ohne Marke.
local function drawElementMarks()
    local lookup = Render.buildElementSymbolLookup()
    -- Blenden
    for _, sh in ipairs(state.room.shutters) do
        local sym = lookup[sh.id]
        if sym then
            local radius = Render.ringRadius(sh.ring)
            local x, y = geo.polar(config.centerX, config.centerY, radius, sh.angle)
            if Render.shutterVisualState(sh.id) == "closed" then
                gfx.setColor(WHITE)
                gfx.fillCircleAtPoint(x, y, 4) -- weiße Trägerfläche
            end
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
    -- Brücken
    for _, b in ipairs(state.room.bridges) do
        local sym = lookup[b.id]
        if sym then
            local rMid = (Render.ringRadius("outer") + Render.ringRadius("inner")) / 2
            local x, y = geo.polar(config.centerX, config.centerY, rMid, b.angle)
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
    -- Kernbrücke / Gate
    if state.room.gate then
        local sym = lookup[state.room.gate.id]
        if sym then
            local rMid = (Render.ringRadius("inner") + (config.coreRadius + 4)) / 2
            local x, y = geo.polar(config.centerX, config.centerY, rMid, state.room.gate.angle)
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
end

-- Gefülltes Oval (Polygon-Approximation, 8 Punkte) an (x,y) mit Halbachsen
-- rLong (radial) und rShort (tangential), Winkel 0° = 12 Uhr, CW positiv.
-- Keine Sprite-Rotation nötig; billige primitive 1-Bit-Operationen.
local function fillOval(x, y, angle, rLong, rShort, color)
    local ax, ay, bx, by = Render.bodyAxisVectors(angle)
    gfx.setColor(color)
    local pts = {}
    for i = 0, 7 do
        local t = (i / 8) * 2 * math.pi
        local c, s = math.cos(t), math.sin(t)
        pts[#pts + 1] = x + ax * rLong * c + bx * rShort * s
        pts[#pts + 1] = y + ay * rLong * c + by * rShort * s
    end
    gfx.fillPolygon(table.unpack(pts))
end

-- 10) Spieler: 7-px-Scheibe (weiß, 1-px schwarze Kontur, 3-px-Auge tangential
-- in Facing-Richtung). Bei Bridge-Transit wird der Körper radial zur Ellipse
-- gestreckt (Start/Ende Kreis, Mitte maximale Streckung; keine Hitboxände-
-- rung). Die Augenform folgt der Reaktionspriorität Squint > Widen > Blink >
-- normal; das Auge bleibt auch während der Streckung sichtbar.
local function drawPlayer()
    local crossing = Bridge.isCrossing()
    local x, y, angle = Render.playerScreenPosition()

    -- Körper
    if crossing then
        local stretch = Render.bridgeStretch(Bridge.getTransitProgress())
        local halfLen = config.playerDiameter / 2 + stretch
        local halfWid = math.max(2.5, config.playerDiameter / 2 - stretch * 0.25)
        fillOval(x, y, angle, halfLen + 1, halfWid + 1, BLACK) -- 1-px Kontur
        fillOval(x, y, angle, halfLen, halfWid, WHITE)
    else
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(x, y, config.playerDiameter / 2)
        gfx.setColor(BLACK)
        gfx.drawCircleAtPoint(x, y, config.playerDiameter / 2)
    end

    -- Auge (bleibt während Streckung sichtbar)
    local ex, ey = Render.playerEyePosition()
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad) -- tangential CW
    local reaction = Render.currentEyeReaction()
    if reaction == "squint" then
        -- Zusammenkneifen: kurze schmale tangentiale Lidlinie
        gfx.setColor(BLACK)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * 2, ey - ty * 2, ex + tx * 2, ey + ty * 2)
        gfx.setLineWidth(1)
    elseif reaction == "widen" then
        -- Augenweiten: größeres Auge (5 px), Körper bleibt Kreis
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ex, ey, 2.5)
    elseif reaction == "blink" then
        -- Blink: geschlossene Lidlinie (kürzer als Squint)
        gfx.setColor(BLACK)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * 1.5, ey - ty * 1.5, ex + tx * 1.5, ey + ty * 1.5)
        gfx.setLineWidth(1)
    else
        -- normal: 3-px-Auge
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ex, ey, 1.5)
    end
    gfx.setColor(WHITE)
end

-- 11) B-Hold-Fortschrittsring (Phase 10.4): weißer 1-px-Bogen um die sichtbare
--     Spielerfigur, Start bei 12 Uhr, im Uhrzeigersinn 0°->360° (Spiel-Winkel-
--     konvention, entspricht drawArc). progress=0 -> nichts, 0.5 -> halber
--     Bogen, ~1 -> fast geschlossen. Kein gefüllter Kreis, keine Graustufen;
--     die Figur bleibt sichtbar. Rein read-only (nur Zeichnen).
local function drawRestartHoldRing()
    local p = Render.restartHoldProgress or 0
    if p <= 0 then
        return
    end
    local x, y = Render.playerScreenPosition()
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    gfx.drawArc(x, y, config.restartHoldRingRadius, 0, math.min(360, p * 360))
    gfx.setLineWidth(1)
end

-- 12) Crank-eingeklappt-Hinweis (Phase 10.4): kompakte 1-Bit-Box (schwarze
--     Fläche, 1-px weiße Kontur, weißer Text) in der oberen rechten Ecke.
--     Sichtbar nur im Gameplay mit eingeklappter Kurbel und solange der Raum
--     nicht abgeschlossen ist (Startmenü zeichnet nie diese Szene). Rein
--     visuell: sperrt KEINE Eingabe (D-Pad/A/B/Undo/Hold laufen weiter).
--     Kein Fade, keine Pulsation, kein Sound.
local function drawCrankOverlay(roomComplete)
    local docked = playdate.isCrankDocked()
    if not docked or roomComplete then
        return
    end
    local bx = config.crankOverlayX
    local by = config.crankOverlayY
    local bw = config.crankOverlayWidth
    local bh = config.crankOverlayHeight
    gfx.setColor(BLACK)
    gfx.fillRect(bx, by, bw, bh)
    gfx.setColor(WHITE)
    gfx.drawRect(bx, by, bw, bh)
    local font = gfx.getSystemFont()
    gfx.setFont(font)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText("Kurbel ausklappen", bx + 4, by + 3)
    gfx.drawText("oder D-Pad benutzen", bx + 4, by + 3 + config.menuFontHeight)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- --- Öffentliches Zeichnen -------------------------------------------------

-- Zeichnet den aktuellen Raumzustand in der verbindlichen Reihenfolge.
-- Read-only gegenüber Gameplay. currentRoomIndex wird nur als
-- Darstellungsinformation gelesen (Kernwachstum, Geisterringe).
function Render.drawRoom(roomComplete, currentRoomIndex)
    -- Preview-Set und Blinkphase einmal pro Frame bestimmen (rein visuell).
    local previewSet = Render.previewElementIds(roomComplete)
    local blinkOn = Render.previewBlinkOn()
    local function previewOf(id)
        return blinkOn and previewSet[id] == true
    end

    -- 1) Hintergrund schwarz
    gfx.clear(gfx.kColorBlack)
    -- 2) Geisterringe abgeschlossener Räume
    drawGhostRings(currentRoomIndex)
    -- 3) Kern
    drawCore(currentRoomIndex)
    -- 4) Bahnen (weiß, 8 px, beide sichtbare Ringe)
    drawTrack(Render.ringRadius("outer"))
    drawTrack(Render.ringRadius("inner"))
    -- 5) Blenden (Preview-Halo unmittelbar vor dem jeweiligen Element)
    for _, sh in ipairs(state.room.shutters) do
        drawShutter(sh, previewOf(sh.id))
    end
    -- 6) Brücken (inaktiv zuerst, dann aktiv)
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "inactive" then
            drawBridge(b, previewOf(b.id))
        end
    end
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "active" then
            drawBridge(b, previewOf(b.id))
        end
    end
    -- 7) Kernbrücke / Gate (kein Gate -> previewOf(nil) ist false)
    drawGate(previewOf(state.room.gate and state.room.gate.id))
    -- 8) Schalter (keine Preview am Switch selbst)
    for _, sw in ipairs(state.room.switches) do
        drawSwitch(sw)
    end
    -- 9) Elementmarken (bleiben über den Preview-Halos)
    drawElementMarks()
    -- 10) Spieler (bleibt ganz oben)
    drawPlayer()
    -- 11) B-Hold-Restart-Fortschrittsring (direkt um die Figur, 1-px-Bogen von
    --     12 Uhr im Uhrzeigersinn 0°->360°, nur bei aktivem Hold) + globales
    --     Crank-eingeklappt-Hinweis-Overlay (rein visuell, 1-Bit).
    drawRestartHoldRing()
    drawCrankOverlay(roomComplete)

    if roomComplete then
        gfx.setColor(WHITE)
        gfx.drawText("ROOM COMPLETE", 150, 30)
    end
end

return Render
