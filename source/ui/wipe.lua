-- wipe.lua — Center-Wipe (Raumwechsel, AUFTRAG „direkter Cut“):
--
-- Ablauf:
--   1) Player + Baby fahren wie bisher gemeinsam über die Center-Bridge zum
--      Mittelpunkt. Sobald beide hinter dem gefüllten Mittelpunkt liegen,
--      verdeckt der Kern beide (Core-Cover-Regel im Renderer).
--   2) Der gefüllte WEISSE Mittelpunkt WÄCHST kontinuierlich nach außen
--      (fester Mittelpunkt 200,120, Ease-In, NUR EIN gefüllter Kreis), bis
--      seine Kreisfläche den KOMPLETTEN 400x240-Bildschirm bedeckt
--      (roomWipeCoverRadius). Keine Ripple-Ringe, keine Partikel, kein Flash.
--   3) Erst bei vollständiger Abdeckung lädt main.lua den neuen Raum VERDECKT
--      („reload“): das neue Level steht danach bereits an seinen FINALEN
--      Positionen, Player/Baby an ihren korrekten Startpositionen.
--   4) Auf dem weißen Bildschirm erscheint mittig kurz „ROOM X"
--      (roomWipeRoomHold). Kein weiterer Text.
--   5) Danach DIREKTER CUT: der weiße Kreis wird NICHT wieder kleiner — er
--      verschwindet einfach und gibt den KOMPLETT FERTIGEN neuen Raum frei.
--      Keine Reveal-Animation, kein Positionssprung, keine automatische
--      Bewegung; Player/Baby stehen sofort korrekt.
--
-- Reine Präsentationslogik: berührt NIE State/Undo/Room/Bridge/Save/Levels
-- (read-only gegenüber Gameplay). Keine Projekt-Imports; Config/Geometry/
-- Camera werden zentral in main.lua geladen.

Wipe = {}

local config <const> = Config
local geo <const> = Geometry

Wipe.active = false
Wipe.phase = nil          -- "grow" | "room"
Wipe.t = 0
Wipe.fromCoreRadius = 0
-- Zielraum für die „ROOM X“-Anzeige.
Wipe.roomIndex = nil

local function easeIn(t)
    return t * t
end

-- Läuft gerade ein Center-Wipe?
function Wipe.isActive()
    return Wipe.active
end

-- Startet den Center-Wipe. nextIndex = Zielraum, oldRoomIndex = Ausgangsraum
-- (für die Kernradien). Figuren-Daten (playerFrom/…/babyTo) werden für die
-- Kompatibilität übernommen, aber im neuen direkten Cut nicht mehr benötigt —
-- Player/Baby stehen nach „reload“ an ihren finalen Startpositionen.
function Wipe.start(nextIndex, playerFrom, playerTo, babyFrom, babyTo, oldRoomIndex)
    Wipe.active = true
    Wipe.phase = "grow"
    Wipe.t = 0
    Wipe.roomIndex = nextIndex
    local fromIdx = oldRoomIndex or (nextIndex and (nextIndex - 1)) or 1
    Wipe.fromCoreRadius = config.coreRadius + (fromIdx - 1) * config.coreGrowthPerRoom
end

-- Startet die ROOM-ANZEIGE DIREKT (ohne Grow) — z. B. „ROOM 1 / 10“ beim
-- Beginn von Level 1 (NEW GAME) direkt nach der Starttransition: sofort
-- weißer Bildschirm, ROOM-Text für roomWipeRoomHold, dann direkter Cut auf
-- das (bereits fertig darunterliegende) Level.
function Wipe.startRoomDisplay(roomIndex)
    Wipe.active = true
    Wipe.phase = "room"
    Wipe.t = 0
    Wipe.roomIndex = roomIndex
end

-- Bricht den Wipe ab (Raumstart/Restart/Menü).
function Wipe.reset()
    Wipe.active = false
    Wipe.phase = nil
    Wipe.t = 0
    Wipe.roomIndex = nil
end

-- Schaltet den Wipe weiter. Rückgabe: "reload" (einmalig bei vollständiger
-- Abdeckung — main.lua lädt dann den neuen Raum VERDECKT), "done"
-- (abgeschlossen — direkter Cut), sonst nil.
function Wipe.update(dt)
    if not Wipe.active then
        return nil
    end
    Wipe.t = Wipe.t + (dt or 0)
    if Wipe.phase == "grow" then
        if Wipe.t >= config.roomWipeGrow then
            Wipe.t = Wipe.t - config.roomWipeGrow
            Wipe.phase = "room"
            return "reload"
        end
        return nil
    end
    -- phase == "room": „ROOM X“ kurz halten, dann direkter Cut.
    if Wipe.t >= (config.roomWipeRoomHold or 0.55) then
        Wipe.active = false
        return "done"
    end
    return nil
end

-- Aktueller Radius des Wipe-Kreises (nil wenn inaktiv). In der ROOM-Phase
-- konstant = vollständige Bildschirmabdeckung (kein Schrumpfen mehr).
function Wipe.radius()
    if not Wipe.active then
        return nil
    end
    if Wipe.phase == "grow" then
        local t = math.min(1, Wipe.t / config.roomWipeGrow)
        return Wipe.fromCoreRadius + (config.roomWipeCoverRadius - Wipe.fromCoreRadius) * easeIn(t)
    end
    return config.roomWipeCoverRadius
end

-- Zielraum-Nummer für die „ROOM X“-Anzeige (nur in der ROOM-Phase aktiv).
function Wipe.roomNumber()
    return Wipe.roomIndex
end

-- Bildschirmposition + Winkel des PLAYERS während des Wipes. Im neuen
-- direkten Cut gibt es KEINE Figuren-Exit-Animation mehr: die Figuren stehen
-- nach „reload“ an ihren finalen Startpositionen (vom weißen Kreis verdeckt)
-- und werden beim Cut einfach freigegeben. Deshalb immer nil (die Figuren
-- zeichnen an ihrer State-Position).
function Wipe.playerPosAndAngle()
    return nil
end

-- Bildschirmposition + Winkel des BABYS während des Wipes (wie oben: nil).
function Wipe.babyPosAndAngle()
    return nil
end

return Wipe
