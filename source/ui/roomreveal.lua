-- roomreveal.lua — Room-Reveal-Wachstum (nach einem Raumwechsel).
--
-- Nach jedem Raumübergang (Center-Wipe ODER Level-7->8-Spezialtransition)
-- erscheint der neue Raum NICHT sofort in voller Größe, sondern wächst als
-- KOMPLETTE EINHEIT aus dem Mittelpunkt (200,120) auf Normalgröße:
--
--   RoomRevealStartScale (0.35) -> 1.00  über roomRevealGrow (1.0 s),
--   mit weicher Ease-Out-Cubic-Kurve (am Anfang schneller, am Ende sanft).
--   Kein Bounce, kein Overshoot, kein Pulsieren — der Raum erreicht exakt
--   Scale 1.0 und bleibt dort stabil.
--
-- Reines Timing-/Präsentationsmodul (read-only gegenüber Gameplay). Es
-- berechnet NUR die Skala; main.lua wendet sie über Camera.setRevealScale an
-- (Camera skaliert damit alle World-Radien gemeinsam um den festen Mittel-
-- punkt — Ringbahnen, Core, Bridges, Shutter, Switches, Platten, Player und
-- Baby behalten ihre relativen Positionen). Während des Wachstums ist die
-- Gameplay-Eingabe gesperrt; erst bei exakt Scale 1.0 wird sie freigegeben.
--
-- Keine Projekt-Imports (Config/Geometry/Camera werden zentral in main.lua
-- geladen); nur die globale Config-Tabelle wird gelesen.

RoomReveal = {}

local config <const> = Config

RoomReveal.active = false
RoomReveal.phase = nil          -- "hold" (optionaler Roomtext bei Startgröße) | "grow"
RoomReveal.t = 0
RoomReveal.scale = 1
RoomReveal.holdTime = 0

-- Ease-Out-Cubic: beginnt sichtbar schneller, bremst gegen Ende sanft ab.
local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

-- Startet das Wachstum des neuen Raums. holdTime (s): optionale Haltephase
-- bei der Startgröße VOR dem Wachstum — z. B. für den „ROOM 8 / 9“-Text nach
-- der Level-7->8-Spezialtransition (kein Roomtext während des Wachstums).
-- Während der gesamten Phase (hold + grow) ist die Gameplay-Eingabe gesperrt.
function RoomReveal.start(holdTime)
    RoomReveal.active = true
    RoomReveal.phase = (holdTime and holdTime > 0) and "hold" or "grow"
    RoomReveal.t = 0
    RoomReveal.scale = config.roomRevealStartScale
    RoomReveal.holdTime = holdTime or 0
end

-- Bricht das Wachstum ab (Raumstart/Restart/Menü) und setzt auf Normalgröße.
function RoomReveal.reset()
    RoomReveal.active = false
    RoomReveal.phase = nil
    RoomReveal.t = 0
    RoomReveal.scale = 1
    RoomReveal.holdTime = 0
end

-- Läuft gerade ein Room-Reveal (Haltephase ODER Wachstum)?
function RoomReveal.isActive()
    return RoomReveal.active
end

-- Aktuelle gemeinsame Skala des Raums (1.0 = Normalgröße).
function RoomReveal.getScale()
    return RoomReveal.scale
end

-- Startgröße des Wachstums (aus Config, für die erste sichtbare Skala).
function RoomReveal.getStartScale()
    return config.roomRevealStartScale
end

-- Schaltet den Reveal weiter. Rückgabe: true wenn abgeschlossen (Scale exakt
-- 1.0 erreicht — main.lua räumt dann die Render-Skalierung ab und gibt das
-- Gameplay frei), sonst false.
function RoomReveal.update(dt)
    if not RoomReveal.active then
        return false
    end
    RoomReveal.t = RoomReveal.t + (dt or 0)
    if RoomReveal.phase == "hold" then
        -- Raum steht bei Startgröße (Roomtext darüber), noch kein Wachstum.
        if RoomReveal.t >= RoomReveal.holdTime then
            RoomReveal.t = RoomReveal.t - RoomReveal.holdTime
            RoomReveal.phase = "grow"
        end
        return false
    end
    local dur = config.roomRevealGrow
    local p = math.min(1, RoomReveal.t / math.max(dur, 0.0001))
    RoomReveal.scale = config.roomRevealStartScale + (1 - config.roomRevealStartScale) * easeOutCubic(p)
    if p >= 1 then
        RoomReveal.scale = 1
        RoomReveal.active = false
        return true
    end
    return false
end

return RoomReveal
