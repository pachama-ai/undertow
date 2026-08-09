-- transition.lua — Outro nach Raum 6 (Abschlussphase B).
--
-- Reine Präsentation/Übergangslogik, KEIN Gameplay und KEIN Gameplay-State.
-- Verarbeitet ausschließlich Outro-Zeit, -Phase und visuelle Interpolation.
-- Quelle (ARCHITECTURE.md):
--   L431: „Nach Raum 6: R1 löst sich auf, der Kern füllt den Bildschirm, die
--          Iris öffnet sich einen Spalt, dahinter ist ein weiterer Ring
--          erkennbar. Schnitt zum Titel. Kein Text."
--   L574 (Szenenautomat): transition nach Raum 6 --> outro --> menu
-- Keine Zeit-/Audio-/Inputvorgaben in ARCHITECTURE -> benannte Configwerte.
--
-- Modulkonvention: genau eine globale PascalCase-Tabelle `Transition`; der
-- Rückgabewert von import wird nicht ausgewertet. Transition berührt NIE
-- State/Undo/Save/Room/Levels (read-only gegenüber Gameplay).

Transition = {}

-- Phasenfolge (verbindlich, ARCHITECTURE L431):
Transition.PHASE_R1_DISSOLVE = 0 -- R1 (innerer Ring des Finalraums) löst sich auf
Transition.PHASE_CORE_EXPAND  = 1 -- der Kern wächst auf Vollbild
Transition.PHASE_IRIS_OPEN    = 2 -- die Iris öffnet sich, dahinter ein weiterer Ring
Transition.PHASE_HOLD         = 3 -- Schlussphase (Iris voll offen), dann Schnitt
Transition.PHASE_FINISHED     = 4 -- abgeschlossen (idle; main wechselt zum Menü)

-- Laufzustand
Transition.active = false
Transition.finished = false
Transition.phase = nil
Transition.t = 0
-- Erfasste Ausgangsgeometrie (bei startOutro; read-only, keine Gameplaydaten)
Transition.cx = 0
Transition.cy = 0
Transition.outerR = 0
Transition.innerR = 0
Transition.coreStartR = 0

-- gfx/config/geometry wie render.lua beim Laden erfasst (Konvention).
local gfx <const> = playdate.graphics
local config <const> = Config
local geo <const> = Geometry

local function phaseDuration(phase)
    if phase == Transition.PHASE_R1_DISSOLVE then
        return config.outroRingDissolveDuration
    elseif phase == Transition.PHASE_CORE_EXPAND then
        return config.outroCoreExpandDuration
    elseif phase == Transition.PHASE_IRIS_OPEN then
        return config.outroIrisDuration
    elseif phase == Transition.PHASE_HOLD then
        return config.outroHoldDuration
    end
    return 0
end

-- Volle Outro-Dauer (Summe aller Phasen), für Tests/Progression.
function Transition.getTotalDuration()
    local sum = 0
    for ph = Transition.PHASE_R1_DISSOLVE, Transition.PHASE_HOLD do
        sum = sum + phaseDuration(ph)
    end
    return sum
end

function Transition.isActive()
    return Transition.active
end

function Transition.isFinished()
    return Transition.finished
end

function Transition.getPhase()
    return Transition.phase
end

-- Fortschritt 0..1 innerhalb der aktuellen Phase (nil wenn inaktiv).
function Transition.getPhaseProgress()
    if not Transition.active then
        return nil
    end
    local d = phaseDuration(Transition.phase)
    if d <= 0 then
        return 1
    end
    return math.min(1, Transition.t / d)
end

-- Startet das Outro. roomIndex = Finalraum (6); outerRing/innerRing = dessen
-- Ringnummern aus dem sichtbaren Room-6-Zustand (Camera dort stabil). Erfasst
-- die Ausgangsgeometrie, ohne Gameplay-State zu berühren.
function Transition.startOutro(roomIndex, outerRing, innerRing)
    Transition.cx = config.centerX
    Transition.cy = config.centerY
    Transition.outerR = Camera.getRadius(outerRing)
    Transition.innerR = Camera.getRadius(innerRing)
    Transition.coreStartR = config.coreRadius + (roomIndex - 1) * config.coreGrowthPerRoom
    Transition.active = true
    Transition.finished = false
    Transition.phase = Transition.PHASE_R1_DISSOLVE
    Transition.t = 0
end

-- Schaltet das Outro weiter. Überschüssige Zeit wird in die nächste Phase
-- übernommen (keine verlorenen dt-Reste; Punkt 40/41). Rückgabe: true, sobald
-- das Outro vollständig abgelaufen ist (einmalig).
function Transition.update(dt)
    if not Transition.active then
        return false
    end
    Transition.t = Transition.t + dt
    while Transition.t >= phaseDuration(Transition.phase) do
        local rest = Transition.t - phaseDuration(Transition.phase)
        Transition.phase = Transition.phase + 1
        Transition.t = rest
        if Transition.phase > Transition.PHASE_HOLD then
            Transition.active = false
            Transition.finished = true
            Transition.phase = Transition.PHASE_FINISHED
            Transition.t = 0
            return true
        end
    end
    return false
end

-- Setzt das Outro vollständig zurück (idle; keine alte Phase).
function Transition.reset()
    Transition.active = false
    Transition.finished = false
    Transition.phase = nil
    Transition.t = 0
end

-- --- Zeichnen (nur Präsentation; 1-Bit schwarz/weiß + binäres Dither) --------
-- Gleiches Smoothstep wie die Kamera (keine neue Easing-Bibliothek).
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Weißer Ring im Bahnstil (trackWidth), wie Render.drawTrack.
local function drawRingSolid(radius)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(config.trackWidth)
    gfx.drawCircleAtPoint(Transition.cx, Transition.cy, radius)
    gfx.setLineWidth(1)
end

-- Kern mit 50%-Dither (gleiche Darstellung wie Render.drawCore).
local function drawCore(radius)
    gfx.setDitherPattern(50)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(Transition.cx, Transition.cy, radius)
    gfx.setDitherPattern(100)
end

-- R1 löst sich auf: der Ring zerfällt in 8 Segmente, die jeweils symmetrisch
-- schrumpfen (Span 360°/8 -> 0°). Bei 0 % = geschlossener Vollkreis (wie der
-- sichtbare Room-6-Ring), bei 100 % = nichts. Reines 1-Bit, keine Graustufen;
-- setDitherPattern(50) ist in diesem SDK ein No-Op (verifiziert), daher Segment-
-- Schrumpfen statt Dither (Punkt 22: „Ringsegment wird schrittweise kürzer").
local function drawRingDissolving(radius, progress)
    -- Ganz am Anfang (p ~ 0) den geschlossenen Vollkreis zeichnen, damit kein
    -- Naht-Sprung zum sichtbaren Room-6-Ring entsteht (Punkt 70).
    if progress <= 0.05 then
        gfx.setColor(gfx.kColorWhite)
        gfx.setLineWidth(config.trackWidth)
        gfx.drawCircleAtPoint(Transition.cx, Transition.cy, radius)
        gfx.setLineWidth(1)
        return
    end
    local segmentCount = 8
    local segSpan = (360 / segmentCount) * (1 - progress)
    if segSpan <= 0.25 then
        return -- vollständig aufgelöst (nichts zeichnen)
    end
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(config.trackWidth)
    for i = 0, segmentCount - 1 do
        local center = (i / segmentCount) * 360
        local s = geo.norm(center - segSpan / 2)
        local e = geo.norm(center + segSpan / 2)
        gfx.drawArc(Transition.cx, Transition.cy, radius, s, e)
    end
    gfx.setLineWidth(1)
end

-- Iris: Apertur öffnet sich, dahinter wird ein weiterer Ring erkennbar.
local function drawIris(progress)
    local apertureR = progress * config.outroIrisOpenRadius
    -- Apertur (schwarze Öffnung im Vollbild-Kern)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(Transition.cx, Transition.cy, apertureR)
    -- „weiterer Ring" (im Öffnungsbereich sichtbar, weiß auf schwarz)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(Transition.cx, Transition.cy, config.outroIrisRingRadius)
    gfx.setLineWidth(1)
    -- Iris-Blätter: dünne schwarze Radiallinien vom Aperturrand nach außen
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    for i = 0, config.outroIrisBladeCount - 1 do
        local ang = (i / config.outroIrisBladeCount) * 360
        local x1, y1 = geo.polar(Transition.cx, Transition.cy, apertureR, ang)
        local x2, y2 = geo.polar(Transition.cx, Transition.cy, config.outroIrisBladeOuter, ang)
        gfx.drawLine(x1, y1, x2, y2)
    end
    gfx.setLineWidth(1)
end

-- Zeichnet den aktuellen Outro-Frame (vollständige Bildschirmkomposition).
-- Phase 0 beginnt aus der sichtbaren Room-6-Komposition (Ringe + Kern).
function Transition.draw()
    if not Transition.active then
        return
    end
    gfx.clear(gfx.kColorBlack)
    local phase = Transition.phase
    local p = Transition.getPhaseProgress() or 1
    local fullR = config.outroCoreFullRadius

    if phase == Transition.PHASE_R1_DISSOLVE then
        drawRingSolid(Transition.outerR)
        drawRingDissolving(Transition.innerR, p)
        drawCore(Transition.coreStartR)
    elseif phase == Transition.PHASE_CORE_EXPAND then
        drawRingSolid(Transition.outerR)
        local eased = smoothstep(p)
        local r = Transition.coreStartR + (fullR - Transition.coreStartR) * eased
        drawCore(r)
    elseif phase == Transition.PHASE_IRIS_OPEN then
        drawCore(fullR)
        drawIris(smoothstep(p))
    elseif phase == Transition.PHASE_HOLD then
        drawCore(fullR)
        drawIris(1)
    end
end

return Transition