-- bgesture.lua — kleine, reine B-Gesten-Zustandsmaschine (Phase 10.4).
--
-- Semantik (verbindlich, Punkt 5/7/11/12/13/14/15):
--   Press                     -> Geste beginnt, noch KEIN Undo
--   Release vor 0,6 s         -> "undo" (genau einmal)
--   >= 0,6 s erreicht         -> "restart" (genau einmal; gewinnt auch bei
--                                 Release im selben Frame; danach Release
--                                 erzeugt kein Undo)
--   Neuer Druck               -> erst nach vollständigem Release
--
-- Reine Zustandsmaschine OHNE World-/Gameplay-Abhängigkeit: bekommt Eingabe
-- (justPressed/held/justReleased) + dt und liefert eine Aktion + Fortschritt.
-- main.lua (Composition Root) treibt sie mit echten Playdate-Eingaben und
-- führt die Aktionen zentral aus (Restart via restartRoom, Undo via undo).
-- Der Fortschritt (0..1) dient dem Hold-Ring um die Figur.

BGesture = {}

local config <const> = Config

-- Interaktionszustand (Punkt 10): KEIN Gameplay-State.
local holdTime = 0
local active = false
local consumed = false
local progress = 0

-- Setzt die Geste vollständig zurück (Raumstart/-wechsel, Restart, Zum Menü;
-- Punkte 55-60). Verhindert stale Releases: ein späteres B-Release löst dann
-- kein Undo mehr aus.
function BGesture.reset()
    holdTime = 0
    active = false
    consumed = false
    progress = 0
end

-- Aktueller Fortschritt 0..1 (für den Hold-Ring; 0 = kein Ring).
function BGesture.getProgress()
    return progress
end

-- Fortschreiben um einen Frame.
--   justPressed:  B in diesem Frame neu gedrückt
--   held:         B aktuell gehalten
--   justReleased: B in diesem Frame losgelassen
--   dt:           Framedauer in Sekunden (zeitbasiert, Punkt 8/62)
-- Rückgabe: "undo" | "restart" | nil
function BGesture.update(justPressed, held, justReleased, dt)
    if not active then
        if justPressed then
            active = true
            holdTime = 0
            consumed = false
            progress = 0
        end
        return nil
    end

    holdTime = holdTime + dt
    -- Schwelle: in diesem Frame erreicht -> Restart gewinnt (auch bei Release
    -- im selben Frame, Punkt 12). Genau einmal (Punkt 13).
    if not consumed and holdTime >= config.restartHoldDuration then
        consumed = true
        active = false
        progress = 0
        return "restart"
    end
    if justReleased or not held then
        active = false
        progress = 0
        if not consumed then
            return "undo"
        end
        return nil
    end
    -- weiterhin gehalten, vor Schwelle: Fortschritt melden (Punkt 30).
    progress = holdTime / config.restartHoldDuration
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    return nil
end

return BGesture
