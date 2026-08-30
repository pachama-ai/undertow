-- phase7.lua — Spezialübergang NACH LEVEL 7 (Ende der Lernphase).
--
-- Nach Abschluss von Level 7 läuft KEIN normaler Levelwechsel (kein Center-
-- Wipe): die Einführung ist vorbei. Der Übergang in die schwerere Phase 2
-- ist eine rein geometrische, KOSMISCHE Sequenz („Urknall“):
--
--   1) Player + Baby fahren wie bisher gemeinsam über die Center-Bridge in
--      den Mittelpunkt und verschwinden gleichzeitig hinter dem Kern
--      (Core-Cover-Regel im Renderer — kein getrenntes Verschwinden).
--   2) Kurze Ruhe / Verdichtung (phase7Rest): der Kern atmet normal weiter.
--   3) LANGSAME EXPANSION (phase7Expand): der helle Kern wächst gleichmäßig,
--      ruhig und unaufhaltsam aus dem Zentrum, wird dabei immer heller
--      (50%-Dither -> volles Weiß) und verdrängt die übrigen Ringelemente.
--      Kurz vor dem Füllen entsteht maximale Spannung (Ease-In).
--   4) VOLLBILD: der Mittelpunkt hat die komplette Spielfläche gefüllt. Auf
--      dem vollen weißen Bild erscheint zentriert „ROOM X / 10“ für ~2 s
--      (phase7TextHold). In dieser Phase wird der neue Raum (Phase 2)
--      verdeckt geladen (phase7.update liefert „load“).
--   5) SCHNELLE KONTRAKTION (phase7Contract): das volle helle Bild zieht sich
--      extrem schnell (deutlich schneller als die Expansion) zum winzigen
--      weißen Punkt im Mittelpunkt zusammen — wie ein Urknall in umgekehrter
--      Richtung.
--   6) DIREKTER REVEAL: sobald sich alles zusammengezogen hat, ist Level 8
--      sofort sichtbar (kein Nachblenden, kein Leerlauf, keine Figuren-Exit-
--      Animation) — Player/Baby stehen direkt korrekt an ihren Level-8-
--      Startpositionen (wurden beim verdeckten Laden gesetzt).
--
-- Reine Präsentationslogik: berührt NIE State/Undo/Room/Bridge/Save/Levels
-- (read-only gegenüber Gameplay). Keine Projekt-Imports; Config/Geometry/
-- Camera/Render/TextUI werden zentral in main.lua geladen.

Phase7 = {}

local gfx = playdate.graphics

local config <const> = Config
local geo <const> = Geometry

Phase7.active = false
Phase7.phase = nil          -- "rest" | "expand" | "text" | "contract"
Phase7.t = 0
Phase7.frames = 0
Phase7.fromCoreRadius = 0
Phase7.toCoreRadius = 0
Phase7.nextIndex = nil      -- Zielraum (für die „ROOM X / 10“-Anzeige)
Phase7.playerFrom = nil
Phase7.playerTo = nil
Phase7.babyFrom = nil
Phase7.babyTo = nil

local function easeIn(t)
    return t * t
end

-- Läuft gerade der Spezialübergang?
function Phase7.isActive()
    return Phase7.active
end

-- Startet den Spezialübergang. nextIndex = Zielraum (Phase 2), oldRoomIndex
-- = Ausgangsraum (Level 7). Figuren-Daten wie beim Wipe: from = Position am
-- Mittelpunkt (Ring "center" oder Ringnummer), to = Zielring des neuen Raums
-- (werden im direkten Reveal nicht mehr für einen Figuren-Exit benötigt —
-- die Figuren stehen nach dem verdeckten Laden an ihren finalen
-- Startpositionen).
function Phase7.start(nextIndex, playerFrom, playerTo, babyFrom, babyTo, oldRoomIndex)
    Phase7.active = true
    Phase7.phase = "rest"
    Phase7.t = 0
    Phase7.frames = 0
    Phase7.nextIndex = nextIndex
    Phase7.playerFrom = playerFrom
    Phase7.playerTo = playerTo
    Phase7.babyFrom = babyFrom
    Phase7.babyTo = babyTo
    local fromIdx = oldRoomIndex or (nextIndex and (nextIndex - 1)) or 1
    Phase7.fromCoreRadius = config.coreRadius + (fromIdx - 1) * config.coreGrowthPerRoom
    Phase7.toCoreRadius = config.coreRadius + (nextIndex - 1) * config.coreGrowthPerRoom
end

-- Bricht den Übergang ab (Raumstart/Restart/Menü).
function Phase7.reset()
    Phase7.active = false
    Phase7.phase = nil
    Phase7.t = 0
    Phase7.frames = 0
    Phase7.nextIndex = nil
    Phase7.playerFrom = nil
    Phase7.playerTo = nil
    Phase7.babyFrom = nil
    Phase7.babyTo = nil
end

-- Schaltet den Übergang weiter. Rückgabe:
--   "load" (einmalig beim Start der TEXT-Phase — das Bild ist komplett
--          gefüllt, main.lua lädt dann den neuen Raum KOMPLETT verdeckt),
--   "done" (abgeschlossen — direkter Reveal von Level 8), sonst nil.
function Phase7.update(dt)
    if not Phase7.active then
        return nil
    end
    Phase7.t = Phase7.t + (dt or 0)
    if Phase7.phase == "rest" then
        if Phase7.t >= config.phase7Rest then
            Phase7.t = Phase7.t - config.phase7Rest
            Phase7.phase = "expand"
        end
    elseif Phase7.phase == "expand" then
        if Phase7.t >= config.phase7Expand then
            Phase7.t = Phase7.t - config.phase7Expand
            Phase7.phase = "text"
            return "load"
        end
    elseif Phase7.phase == "text" then
        if Phase7.t >= config.phase7TextHold then
            Phase7.t = Phase7.t - config.phase7TextHold
            Phase7.phase = "contract"
        end
    elseif Phase7.phase == "contract" then
        if Phase7.t >= config.phase7Contract then
            Phase7.active = false
            return "done"
        end
    end
    return nil
end

-- Startradius der Expansion: nahtlos über dem normalen (pulsierenden) Kern
-- von Raum 7, damit kein optischer Sprung entsteht.
local function expandStartRadius()
    if Render and Render.coreRadius then
        return Render.coreRadius(Render.currentRoomIndex) + Render.corePulseOffset()
    end
    return Phase7.fromCoreRadius
end

-- Aktueller Radius des hellen Übergangskreises (nil wenn inaktiv oder in
-- der Ruhephase — dort zeichnet das Overlay nichts, der Kern atmet normal).
function Phase7.coreRadius()
    if not Phase7.active then
        return nil
    end
    if Phase7.phase == "expand" then
        local start = expandStartRadius()
        local u = math.min(1, Phase7.t / config.phase7Expand)
        return start + (config.phase7CoverRadius - start) * easeIn(u)
    elseif Phase7.phase == "text" then
        return config.phase7CoverRadius
    elseif Phase7.phase == "contract" then
        local u = math.min(1, Phase7.t / config.phase7Contract)
        return config.phase7CoverRadius + (config.phase7TinyPoint - config.phase7CoverRadius) * easeIn(u)
    end
    return nil
end

-- Sind die Figuren hinter dem Übergang verdeckt? true in ALLEN Phasen —
-- Player/Baby bleiben während der kompletten Sequenz unsichtbar und stehen
-- beim direkten Reveal an ihren Level-8-Startpositionen.
function Phase7.hidesFigures()
    return Phase7.active
end

-- Bildschirmposition + Winkel des PLAYERS während des Übergangs. Es gibt
-- KEINE Figuren-Exit-Animation mehr (direkter Reveal): immer nil — die
-- Figuren zeichnen nach dem Reveal an ihrer State-Position.
function Phase7.playerPosAndAngle()
    return nil
end

-- Bildschirmposition + Winkel des BABYS während des Übergangs (wie oben: nil).
function Phase7.babyPosAndAngle()
    return nil
end

-- --- Overlay-Zeichnung (wird am Ende von Render.drawRoom aufgerufen) -------

local function fillScreenWhite()
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, config.screenWidth or 400, config.screenHeight or 240)
end

-- Der winzige weiße Punkt im exakten Mittelpunkt (200,120).
local function drawTinyPoint()
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, config.phase7TinyPoint)
end

-- Hell wachsender Übergangskern: schwarze Basis (verschluckt die alte Welt
-- sauber), darüber ein heller Kreis, dessen Deckkraft von der Kern-Optik
-- (50%-Dither) bis zum vollen Weiß ansteigt („Energie entsteht im Zentrum“).
-- Sauber kreisförmig, kein Ruckeln. In der Kontraktionsphase bleibt das Bild
-- volles Weiß (das volle helle Bild zieht sich zusammen).
local function drawExpandingCore(r)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    local dither
    if Phase7.phase == "expand" then
        local u = math.min(1, Phase7.t / config.phase7Expand)
        dither = config.phase7ExpandDitherStart + (100 - config.phase7ExpandDitherStart) * u
    else
        dither = 100 -- contract: volles helles Bild bleibt vollweiß
    end
    gfx.setDitherPattern(math.floor(dither))
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    gfx.setDitherPattern(100)
end

-- Zeichnet das Overlay des Spezialübergangs ÜBER dem normalen Raum. In der
-- TEXT-Phase zeichnet es das volle helle Bild + „ROOM X / 10“; während der
-- Kontraktion wird der neue Raum rund um den schrumpfenden Kreis bereits
-- sichtbar (sauberer kosmischer Kollaps, danach direkter Reveal).
function Phase7.draw()
    if not Phase7.active then
        return
    end
    if Phase7.phase == "rest" then
        -- Nichts: der normale Kern atmet weiter; die Figuren sind verdeckt.
    elseif Phase7.phase == "expand" then
        drawExpandingCore(Phase7.coreRadius())
    elseif Phase7.phase == "text" then
        -- Volles helles Bild + zentriert „ROOM X / 10“ (schwarz auf weiß).
        fillScreenWhite()
        local fh = (TextUI and TextUI.font and TextUI.font:getHeight()) or 22
        local label = "ROOM " .. (Phase7.nextIndex or 8) .. " / " .. config.roomDisplayTotal
        if Render and Render.drawTextBlackCentered then
            Render.drawTextBlackCentered(label, math.floor((config.screenHeight - fh) / 2))
        end
    elseif Phase7.phase == "contract" then
        local r = Phase7.coreRadius()
        if r > config.phase7TinyPoint + 0.5 then
            drawExpandingCore(r)
        else
            drawTinyPoint()
        end
    end
end

return Phase7
