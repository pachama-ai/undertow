-- phase7.lua — Spezialübergang NACH LEVEL 7 (Ende der Lernphase).
--
-- Nach Abschluss von Level 7 läuft KEIN normaler Levelwechsel (kein Center-
-- Wipe): die Einführung ist vorbei. Der Übergang in die schwerere Phase 2
-- ist eine rein geometrische Sequenz OHNE Text (kein „Level 8“, kein
-- „Hard Mode“) — die Animation allein vermittelt den Einschnitt:
--
--   1) Player + Baby fahren wie bisher gemeinsam über die Center-Bridge in
--      den Mittelpunkt und verschwinden gleichzeitig hinter dem Kern
--      (Core-Cover-Regel im Renderer — kein getrenntes Verschwinden).
--   2) Kurze Ruhe (phase7Rest): der Kern atmet normal weiter.
--   3) Der Kern pulsiert DREIMAL: Puls 1 leicht, Puls 2 stärker, Puls 3
--      deutlich stärker UND schneller (reine Radius-Änderung, deterministisch).
--   4) Der Kern zieht sich sehr schnell auf einen winzigen weißen Punkt im
--      exakten Mittelpunkt (200,120) zusammen (Ease-In).
--   5) 2-3 Frames Pause mit dem winzigen weißen Punkt.
--   6) GEOMETRISCHE EXPLOSION: grobe weiße Ringsegmente (Teile der vorhandenen
--      Ringgeometrie, die an mehreren Stellen gleichzeitig aufbricht) und
--      radiale Splitter fliegen radial aus dem Bild (0.35-0.45 s). Keine
--      Partikelwolke, kein Glow, kein Feuer, kein Konfetti.
--   7) Danach nur dunkler Hintergrund (phase7Dark) — main.lua lädt in dieser
--      Phase den neuen Raum (Phase 2) KOMPLETT verdeckt.
--   8) Im Mittelpunkt erscheint wieder ein kleiner Kern; aus ihm baut sich
--      die neue Spielwelt auf (weiterhin exakt 2 aktive Ringbahnen, kein
--      dritter Ring).
--   9) Player + Baby kommen gemeinsam radial aus dem Kern heraus (Baby
--      leicht voraus, Player folgt, eigene Winkel) und landen sauber auf der
--      Ringbahn (kein letzter Positions-Snap).
--  10) Sofort Gameplay — keine Tutorials, keine zusätzliche Ruhe.
--
-- Reine Präsentationslogik: berührt NIE State/Undo/Room/Bridge/Save/Levels
-- (read-only gegenüber Gameplay). Keine Projekt-Imports; Config/Geometry/
-- Camera/Render werden zentral in main.lua geladen.

Phase7 = {}

local gfx = playdate.graphics

local config <const> = Config
local geo <const> = Geometry

Phase7.active = false
Phase7.phase = nil          -- "rest" | "pulse" | "collapse" | "flash" | "explode" | "dark" | "rebuild"
Phase7.t = 0
Phase7.frames = 0
Phase7.fromCoreRadius = 0
Phase7.toCoreRadius = 0
Phase7.outerR = 0           -- Ringgeometrie des alten Raums (Explosions-Fragmente)
Phase7.innerR = 0
Phase7.playerFrom = nil
Phase7.playerTo = nil
Phase7.babyFrom = nil
Phase7.babyTo = nil
Phase7.fragments = nil

local function easeIn(t)
    return t * t
end

local function easeOut(t)
    return 1 - (1 - t) * (1 - t)
end

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Deterministische Fragmente der Explosion (kein Zufall): grobe weiße
-- Ringsegmente (Teile der vorhandenen Ringgeometrie des alten Raums, die an
-- mehreren Stellen aufbricht) + radiale Splitter. Winkel gleichmäßig verteilt
-- mit kleiner deterministischer Abweichung; die Ringsegmente starten exakt
-- auf dem alten Außen-/Innenring.
local function buildFragments()
    local frags = {}
    local n = config.phase7ExplosionFragments
    for i = 1, n do
        local angle = (i - 1) * (360 / n) + ((i % 2 == 1) and 6 or -4)
        local frag
        if i <= 5 then
            local fromOuter = (i % 2 == 1)
            frag = {
                kind = "arc",
                angle = angle,
                startR = fromOuter and Phase7.outerR or Phase7.innerR,
                arc = fromOuter and 40 or 52,
                width = fromOuter and 8 or 6,
                spin = (i % 2 == 1) and 26 or -20,
            }
        else
            frag = {
                kind = "spike",
                angle = angle,
                startR = 6 + (i - 6) * 10,
                width = 3,
                spin = 0, -- Splitter drehen nicht (rein radial)
            }
        end
        frags[#frags + 1] = frag
    end
    return frags
end

-- Läuft gerade der Spezialübergang?
function Phase7.isActive()
    return Phase7.active
end

-- Startet den Spezialübergang. nextIndex = Zielraum (Phase 2), oldRoomIndex
-- = Ausgangsraum (Level 7). Figuren-Daten wie beim Wipe: from = Position am
-- Mittelpunkt (Ring "center" oder Ringnummer), to = Zielring des neuen Raums.
function Phase7.start(nextIndex, playerFrom, playerTo, babyFrom, babyTo, oldRoomIndex)
    Phase7.active = true
    Phase7.phase = "rest"
    Phase7.t = 0
    Phase7.frames = 0
    Phase7.playerFrom = playerFrom
    Phase7.playerTo = playerTo
    Phase7.babyFrom = babyFrom
    Phase7.babyTo = babyTo
    local fromIdx = oldRoomIndex or (nextIndex and (nextIndex - 1)) or 1
    Phase7.fromCoreRadius = config.coreRadius + (fromIdx - 1) * config.coreGrowthPerRoom
    Phase7.toCoreRadius = config.coreRadius + (nextIndex - 1) * config.coreGrowthPerRoom
    -- Ringgeometrie des alten Raums für die Explosions-Fragmente einfrieren
    -- (State.room ist zu diesem Zeitpunkt noch der alte Raum).
    local s = State.room
    if s and s.rings then
        Phase7.outerR = Camera.getRadius(s.rings.outer) or config.outerRadius
        Phase7.innerR = Camera.getRadius(s.rings.inner) or (config.outerRadius - config.ringSpacing)
    else
        Phase7.outerR = config.outerRadius
        Phase7.innerR = config.outerRadius - config.innerRadius
    end
    Phase7.fragments = buildFragments()
end

-- Bricht den Übergang ab (Raumstart/Restart/Menü).
function Phase7.reset()
    Phase7.active = false
    Phase7.phase = nil
    Phase7.t = 0
    Phase7.frames = 0
    Phase7.playerFrom = nil
    Phase7.playerTo = nil
    Phase7.babyFrom = nil
    Phase7.babyTo = nil
    Phase7.fragments = nil
end

-- Schaltet den Übergang weiter. Rückgabe:
--   "load" (einmalig beim Start der dunklen Phase — main.lua lädt dann den
--          neuen Raum KOMPLETT verdeckt),
--   "done" (abgeschlossen), sonst nil.
function Phase7.update(dt)
    if not Phase7.active then
        return nil
    end
    Phase7.t = Phase7.t + (dt or 0)
    if Phase7.phase == "rest" then
        if Phase7.t >= config.phase7Rest then
            Phase7.t = Phase7.t - config.phase7Rest
            Phase7.phase = "pulse"
        end
    elseif Phase7.phase == "pulse" then
        local total = config.phase7Pulse1Dur + config.phase7Pulse2Dur + config.phase7Pulse3Dur
        if Phase7.t >= total then
            Phase7.t = Phase7.t - total
            Phase7.phase = "collapse"
        end
    elseif Phase7.phase == "collapse" then
        if Phase7.t >= config.phase7Collapse then
            Phase7.t = Phase7.t - config.phase7Collapse
            Phase7.phase = "flash"
        end
    elseif Phase7.phase == "flash" then
        if Phase7.t >= config.phase7Flash then
            Phase7.t = Phase7.t - config.phase7Flash
            Phase7.phase = "explode"
        end
    elseif Phase7.phase == "explode" then
        if Phase7.t >= config.phase7Explosion then
            Phase7.t = Phase7.t - config.phase7Explosion
            Phase7.phase = "dark"
            return "load"
        end
    elseif Phase7.phase == "dark" then
        if Phase7.t >= config.phase7Dark then
            Phase7.t = Phase7.t - config.phase7Dark
            Phase7.phase = "rebuild"
        end
    elseif Phase7.phase == "rebuild" then
        if Phase7.t >= config.phase7Rebuild then
            Phase7.active = false
            return "done"
        end
    end
    return nil
end

-- Anteil innerhalb der Puls-Phase [0,1] + Amplitude des aktuellen Pulses.
local function pulseInfo()
    local p1 = config.phase7Pulse1Dur
    local p2 = config.phase7Pulse2Dur
    local t = Phase7.t
    if t < p1 then
        return t / p1, config.phase7Pulse1Amp
    elseif t < p1 + p2 then
        return (t - p1) / p2, config.phase7Pulse2Amp
    else
        return (t - p1 - p2) / config.phase7Pulse3Dur, config.phase7Pulse3Amp
    end
end

-- Radius des Übergangs-Kerns für die Overlay-Phase (Puls/Kollaps), bezogen
-- auf den normalen Kern (inkl. Normalpulsation), damit der Übergangskern
-- nahtlos über dem normalen Kern liegt.
function Phase7.coreRadius()
    if not Phase7.active then
        return nil
    end
    local base = Render.coreRadius(Render.currentRoomIndex) + Render.corePulseOffset()
    if Phase7.phase == "pulse" then
        local u, amp = pulseInfo()
        return base + amp * math.sin(math.pi * math.min(1, math.max(0, u)))
    elseif Phase7.phase == "collapse" then
        local u = math.min(1, Phase7.t / config.phase7Collapse)
        return base + (config.phase7TinyPoint - base) * (u * u)
    end
    return base
end

-- Wiederaufbau-Skala (0.12 -> 1): alle Ringradien UND der Kern werden über
-- Camera.revealScale gemeinsam aus dem Mittelpunkt heraus skaliert, bis die
-- neue Welt (exakt 2 aktive Ringbahnen) in Normalgröße steht.
function Phase7.revealScale()
    if not Phase7.active or Phase7.phase ~= "rebuild" then
        return 1
    end
    local u = math.min(1, Phase7.t / config.phase7Rebuild)
    local ringEnd = config.phase7RebuildRingEnd
    local s = config.phase7RebuildStartScale
    local k = math.min(1, u / ringEnd)
    return s + (1 - s) * easeOut(k)
end

-- Exit-Fortschritt der Figuren (0 = am Kern, 1 = auf der Zielbahn). Nur
-- während der REBUILD-Phase, im letzten Fenster (phase7RebuildExitStart..1):
-- die Figuren kommen erst heraus, wenn die Ringe fast ausgebaut sind.
function Phase7.exitProgress()
    if not Phase7.active or Phase7.phase ~= "rebuild" then
        return 0
    end
    local u = math.min(1, Phase7.t / config.phase7Rebuild)
    local s = config.phase7RebuildExitStart
    if u <= s then
        return 0
    end
    return smoothstep(math.min(1, (u - s) / (1 - s)))
end

-- Sind die Figuren hinter dem Kern verdeckt? true in allen Phasen außer dem
-- Figuren-Exit im Rebuild (kein getrenntes Erscheinen/Verschwinden).
function Phase7.hidesFigures()
    if not Phase7.active then
        return false
    end
    if Phase7.phase == "rebuild" then
        return Phase7.exitProgress() <= 0
    end
    return true
end

-- Startradius einer Figur (Ring "center" = Kernrand des alten Raums).
local function startRadius(f)
    if f.ring == "center" then
        return Phase7.fromCoreRadius
    end
    return Camera.getRadiusAtProgress(f.ring, 0)
end

-- Zielradius einer Figur (finaler Radius des Zielrings im neuen Raum).
local function endRadius(t)
    if t.ring == "center" then
        return Phase7.toCoreRadius
    end
    return Camera.getRadiusAtProgress(t.ring, 1)
end

-- Kontinuierliche Exit-Position: Winkel konstant (eigener Winkel), nur der
-- Radius wandert aus dem Kern auf die Zielbahn (Baby leicht voraus — es hat
-- durch die Shared-Landing bereits einen eigenen, leicht vorderen Winkel).
local function figurePos(f, t)
    local p = Phase7.exitProgress()
    local fromR = startRadius(f)
    local toR = endRadius(t)
    local radius = fromR + (toR - fromR) * p
    local angle = f.angle
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    return x, y, angle
end

-- Bildschirmposition + Winkel des PLAYERS während des Übergangs (nil wenn
-- inaktiv oder keine Daten).
function Phase7.playerPosAndAngle()
    if not Phase7.active then
        return nil
    end
    local f, t = Phase7.playerFrom, Phase7.playerTo
    if not f or not t then
        return nil
    end
    return figurePos(f, t)
end

-- Bildschirmposition + Winkel des BABYS während des Übergangs (nil wenn
-- inaktiv, kein Baby oder keine Daten).
function Phase7.babyPosAndAngle()
    if not Phase7.active then
        return nil
    end
    local f, t = Phase7.babyFrom, Phase7.babyTo
    if not f or not t then
        return nil
    end
    return figurePos(f, t)
end

-- --- Overlay-Zeichnung (wird am Ende von Render.drawRoom aufgerufen) -------

local function fillScreenBlack()
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, config.screenWidth or 400, config.screenHeight or 240)
end

-- Kern-Optik wie drawCore: schwarze Basis + 50%-Dither-Weiß (voll deckend).
local function drawCoreCircle(r)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    gfx.setDitherPattern(50)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    gfx.setDitherPattern(100)
end

-- Der winzige weiße Punkt im exakten Mittelpunkt (200,120).
local function drawTinyPoint()
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, config.phase7TinyPoint)
end

-- Geometrische Explosion: schwarzer Hintergrund + grobe weiße Ringsegmente
-- und radiale Splitter, die radial (beschleunigt) aus dem Bild fliegen.
local function drawExplosion()
    fillScreenBlack()
    local u = math.min(1, Phase7.t / config.phase7Explosion)
    -- Der zentrale Explosionspunkt bleibt kurz sichtbar (der Punkt „zerplatzt“).
    if u < config.phase7ExplosionDot then
        drawTinyPoint()
    end
    local e = u * u -- Beschleunigung nach außen
    for _, f in ipairs(Phase7.fragments) do
        local r = f.startR + (config.phase7ExplosionClear - f.startR) * e
        local a = geo.norm(f.angle + f.spin * Phase7.t)
        if f.kind == "arc" then
            -- Ringsegment: fliegt mit seiner Krümmung radial nach außen.
            gfx.setColor(gfx.kColorWhite)
            gfx.setLineWidth(f.width)
            gfx.drawArc(config.centerX, config.centerY, r, geo.norm(a - f.arc / 2), geo.norm(a + f.arc / 2))
            gfx.setLineWidth(1)
        else
            -- Radialer Splitter: kurzes Segment, das vom Mittelpunkt nach
            -- außen fliegt (Bruchstück, kein Strahl von 0 bis zum Rand).
            local x1, y1 = geo.polar(config.centerX, config.centerY, r * 0.55, a)
            local x2, y2 = geo.polar(config.centerX, config.centerY, r, a)
            gfx.setColor(gfx.kColorWhite)
            gfx.setLineWidth(f.width)
            gfx.drawLine(x1, y1, x2, y2)
            gfx.setLineWidth(1)
        end
    end
end

-- Zeichnet das Overlay des Spezialübergangs ÜBER dem normalen Raum. In der
-- REBUILD-Phase zeichnet das Overlay nichts: der neue Raum rendert über
-- Camera.revealScale selbst skaliert aus dem Kern heraus.
function Phase7.draw()
    if not Phase7.active then
        return
    end
    if Phase7.phase == "rest" then
        -- Nichts: der normale Kern atmet weiter; die Figuren sind verdeckt.
    elseif Phase7.phase == "pulse" then
        drawCoreCircle(Phase7.coreRadius())
    elseif Phase7.phase == "collapse" then
        -- Den normalen Kern zuerst verdecken, dann den schrumpfenden Kern
        -- zeichnen (sonst bliebe der volle Kernrand sichtbar).
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(config.centerX, config.centerY, Render.coreRadius(Render.currentRoomIndex) + 2)
        local r = Phase7.coreRadius()
        if r > config.phase7TinyPoint + 0.5 then
            drawCoreCircle(r)
        else
            drawTinyPoint()
        end
    elseif Phase7.phase == "flash" then
        -- Winziger weißer Punkt im exakten Mittelpunkt: den normalen Kern
        -- verdecken, nur der Punkt bleibt.
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(config.centerX, config.centerY, Render.coreRadius(Render.currentRoomIndex) + 2)
        drawTinyPoint()
    elseif Phase7.phase == "explode" then
        drawExplosion()
    elseif Phase7.phase == "dark" then
        fillScreenBlack()
    elseif Phase7.phase == "rebuild" then
        -- Nichts (Welt skaliert aus dem Kern über Camera.revealScale).
    end
end

return Phase7
