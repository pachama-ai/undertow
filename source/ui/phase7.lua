-- phase7.lua — Spezialübergang NACH LEVEL 7 (Ende der Lernphase).
--
-- Nach Abschluss von Level 7 läuft KEIN normaler Levelwechsel (kein Center-
-- Wipe): die Einführung ist vorbei. Der Übergang in die schwerere Phase 2
-- ist eine rein geometrische, KOSMISCHE Sequenz („Urknall“):
--
--   WICHTIG: Während der GESAMTEN Animation bleibt die Geometrie von ROOM 7
--   KOMPLETT STILL (keine Ringbewegung, keine Skalierung der Ringbahnen,
--   keine Verschiebung von Bridges, keine Player-/Babybewegung, keine
--   Kameraanimation): NUR der Core animiert seine Größe.
--
--   1) Player + Baby fahren wie bisher gemeinsam über die Center-Bridge in
--      den Mittelpunkt und verschwinden gleichzeitig hinter dem Kern
--      (Core-Cover-Regel im Renderer — kein getrenntes Verschwinden).
--   2) Kurze Verdichtung (phase7Rest): der Kern atmet normal weiter.
--   3) PULS 1 (p1_up -> p1_down -> pause1): der Core vergrößert sich schnell
--      auf phase7P1Scale (1.18x, ~0.08 s) und zieht sich wieder KOMPLETT auf
--      seine normale Größe zurück (~0.08 s). Kurze Pause (~0.04 s). Sehr
--      klar lesbarer einzelner Puls.
--   4) PULS 2 (p2_up -> p2_down -> pause2): der zweite Puls ist sichtbar
--      stärker (phase7P2Scale = 1.35x, ~0.10 s) und kehrt wieder exakt zur
--      normalen Größe zurück (~0.09 s). Kurze Pause (~0.04 s).
--      Lesbar: kleiner Puls -> normal -> größerer Puls -> normal.
--   5) GROSSE EXPANSION (phase7Expand, ~1.1 s): erst JETZT wächst der Core
--      langsam und kontinuierlich über die bestehende (unveränderte) Szene,
--      bis er die komplette Spielfläche ausfüllt (phase7CoverRadius = 250 px
--      deckt alle 4 Ecken ab) — der Bildschirm ist KOMPLETT WEISS.
--   6) VOLLBILD (phase7Hold, sehr kurz): rein weiß, kein Text. Hier wird der
--      neue Raum (Phase 2) verdeckt geladen (phase7.update liefert „load“).
--   7) ROOM-TEXT (label, phase7RoomLabelHold = exakt 2 s): auf rein weißem
--      Bildschirm nur „ROOM 8 / 9“ (schwarz, zentriert). ROOM 8 ist dabei
--      NICHT sichtbar (das volle Weiß überdeckt ihn), keine Ringe, kein
--      Core, keine Figuren, keine Transitionanimation.
--   8) TEXT WEG: nach exakt 2 s ist der Text komplett entfernt und der
--      Übergang beendet („done“). Erst im DARAUFFOLGENDEN Frame startet der
--      Room-Reveal (main.lua): ROOM 8 erscheint KOMPLETT aber KLEIN
--      (Startgröße ~0.30) im Mittelpunkt (200,120) und wächst als Einheit
--      auf Normalgröße. Kein Crossfade, kein Overlap, kein Fullsize-Flash.
--
-- Reine Präsentationslogik: berührt NIE State/Undo/Room/Bridge/Save/Levels
-- (read-only gegenüber Gameplay). Keine Projekt-Imports; Config/Geometry/
-- Camera/Render/TextUI werden zentral in main.lua geladen.

Phase7 = {}

local gfx = playdate.graphics

local config <const> = Config
local geo <const> = Geometry

Phase7.active = false
Phase7.phase = nil          -- "rest" | "p1_up" | "p1_down" | "pause1" | "p2_up" | "p2_down" | "pause2" | "expand" | "hold" | "label"
Phase7.t = 0
Phase7.frames = 0
Phase7.fromCoreRadius = 0
Phase7.toCoreRadius = 0
Phase7.nextIndex = nil      -- Zielraum (für die „ROOM X / 9“-Anzeige)
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
--   "load" (einmalig beim Erreichen des Vollbilds — das Bild ist komplett
--          gefüllt, main.lua lädt dann den neuen Raum KOMPLETT verdeckt),
--   "done" (abgeschlossen — Text weg, Room-Reveal folgt), sonst nil.
function Phase7.update(dt)
    if not Phase7.active then
        return nil
    end
    Phase7.t = Phase7.t + (dt or 0)
    if Phase7.phase == "rest" then
        if Phase7.t >= config.phase7Rest then
            Phase7.t = Phase7.t - config.phase7Rest
            Phase7.phase = "p1_up"
        end
    elseif Phase7.phase == "p1_up" then
        if Phase7.t >= config.phase7P1Up then
            Phase7.t = Phase7.t - config.phase7P1Up
            Phase7.phase = "p1_down"
        end
    elseif Phase7.phase == "p1_down" then
        if Phase7.t >= config.phase7P1Down then
            Phase7.t = Phase7.t - config.phase7P1Down
            Phase7.phase = "pause1"
        end
    elseif Phase7.phase == "pause1" then
        if Phase7.t >= config.phase7Pause1 then
            Phase7.t = Phase7.t - config.phase7Pause1
            Phase7.phase = "p2_up"
        end
    elseif Phase7.phase == "p2_up" then
        if Phase7.t >= config.phase7P2Up then
            Phase7.t = Phase7.t - config.phase7P2Up
            Phase7.phase = "p2_down"
        end
    elseif Phase7.phase == "p2_down" then
        if Phase7.t >= config.phase7P2Down then
            Phase7.t = Phase7.t - config.phase7P2Down
            Phase7.phase = "pause2"
        end
    elseif Phase7.phase == "pause2" then
        if Phase7.t >= config.phase7Pause2 then
            Phase7.t = Phase7.t - config.phase7Pause2
            Phase7.phase = "expand"
        end
    elseif Phase7.phase == "expand" then
        if Phase7.t >= config.phase7Expand then
            Phase7.t = Phase7.t - config.phase7Expand
            Phase7.phase = "hold"
            return "load"
        end
    elseif Phase7.phase == "hold" then
        -- Sehr kurzer Vollbildmoment (rein weiß, noch kein Text): hier wurde
        -- der neue Raum gerade verdeckt geladen.
        if Phase7.t >= config.phase7Hold then
            Phase7.t = Phase7.t - config.phase7Hold
            Phase7.phase = "label"
        end
    elseif Phase7.phase == "label" then
        -- „ROOM 8 / 9“ auf rein weißem Bildschirm (phase7RoomLabelHold, exakt
        -- 2 s). ROOM 8 bleibt dabei unsichtbar (das weiße Overlay deckt ihn).
        -- KEINE Implosion mehr: nach dem Text ist der Übergang beendet und
        -- der Room-Reveal startet im nächsten Frame (Room 8 klein).
        if Phase7.t >= config.phase7RoomLabelHold then
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
    local base = expandStartRadius()
    if Phase7.phase == "p1_up" then
        local u = math.min(1, Phase7.t / config.phase7P1Up)
        return base * (1 + (config.phase7P1Scale - 1) * u)
    elseif Phase7.phase == "p1_down" then
        local u = math.min(1, Phase7.t / config.phase7P1Down)
        return base * (config.phase7P1Scale + (1 - config.phase7P1Scale) * u)
    elseif Phase7.phase == "pause1" then
        return base
    elseif Phase7.phase == "p2_up" then
        local u = math.min(1, Phase7.t / config.phase7P2Up)
        return base * (1 + (config.phase7P2Scale - 1) * u)
    elseif Phase7.phase == "p2_down" then
        local u = math.min(1, Phase7.t / config.phase7P2Down)
        return base * (config.phase7P2Scale + (1 - config.phase7P2Scale) * u)
    elseif Phase7.phase == "pause2" then
        return base
    elseif Phase7.phase == "expand" then
        local u = math.min(1, Phase7.t / config.phase7Expand)
        return base + (config.phase7CoverRadius - base) * easeIn(u)
    elseif Phase7.phase == "hold" or Phase7.phase == "label" then
        -- Vollbild bzw. ROOM-Text: der Kreis füllt die komplette Fläche
        -- (weiß), ROOM 8 ist darunter nicht sichtbar.
        return config.phase7CoverRadius
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

-- Text der ROOM-Anzeige in der LABEL-Phase: exakt „ROOM X / 9“ (X = Zielraum,
-- Gesamtzahl immer aus config.roomDisplayTotal = 9 — niemals /10).
function Phase7.labelText()
    return "ROOM " .. (Phase7.nextIndex or 1) .. " / " .. config.roomDisplayTotal
end

-- Hell wachsender Übergangskern: schwarze Basis (verschluckt die alte Welt
-- sauber), darüber ein heller Kreis, dessen Deckkraft von der Kern-Optik
-- (50%-Dither) bis zum vollen Weiß ansteigt („Energie entsteht im Zentrum“).
-- Sauber kreisförmig, kein Ruckeln. In der Vollbild-Phase bleibt das Bild
-- volles Weiß.
local function drawExpandingCore(r)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    local dither
    if Phase7.phase == "expand" then
        local u = math.min(1, Phase7.t / config.phase7Expand)
        dither = config.phase7ExpandDitherStart + (100 - config.phase7ExpandDitherStart) * u
    elseif Phase7.phase == "p1_up" or Phase7.phase == "p1_down"
        or Phase7.phase == "p2_up" or Phase7.phase == "p2_down" then
        dither = config.phase7ExpandDitherStart -- Pulse behalten die Kern-Optik (dezent)
    else
        dither = 100 -- hold: volles helles Bild bleibt vollweiß
    end
    gfx.setDitherPattern(math.floor(dither))
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, r)
    gfx.setDitherPattern(100)
end

-- Zeichnet das Overlay des Spezialübergangs ÜBER dem normalen Raum. In der
-- LABEL-Phase zeichnet es das volle weiße Bild + „ROOM 8 / 9“ — der darunter
-- bereits geladene Raum bleibt unsichtbar (kein Overlap mit dem Reveal, der
-- erst NACH dem Text startet).
function Phase7.draw()
    if not Phase7.active then
        return
    end
    if Phase7.phase == "rest" then
        -- Nichts: der normale Kern atmet weiter; die Figuren sind verdeckt.
    elseif Phase7.phase == "p1_up" or Phase7.phase == "p1_down"
        or Phase7.phase == "p2_up" or Phase7.phase == "p2_down" then
        -- Puls: der Core wächst über den normalen Kern hinaus und zieht sich
        -- wieder auf seine normale Größe zurück (linear, klar lesbar).
        drawExpandingCore(Phase7.coreRadius())
    elseif Phase7.phase == "pause1" or Phase7.phase == "pause2" then
        -- Nichts: der Kern steht auf seiner normalen Größe (kurze Pause).
    elseif Phase7.phase == "expand" then
        drawExpandingCore(Phase7.coreRadius())
    elseif Phase7.phase == "hold" then
        -- Volles helles Bild, KEIN ROOM-Text: nur der kurze Vollbildmoment.
        -- ROOM 8 wurde hier verdeckt geladen, bleibt aber unsichtbar.
        fillScreenWhite()
    elseif Phase7.phase == "label" then
        -- Komplett weiße Fläche + NUR „ROOM 8 / 9“ (schwarzer Text, zentriert,
        -- exakt 2 s). Keine Level-8-Geometrie sichtbar, keine Ringe, kein
        -- Core, keine Figuren, keine Transitionanimation.
        fillScreenWhite()
        local fh = (TextUI ~= nil and TextUI.font ~= nil and TextUI.font:getHeight()) or 22
        Render.drawTextBlackCentered(Phase7.labelText(), math.floor((240 - fh) / 2))
    end
end

return Phase7
