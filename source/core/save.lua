-- save.lua — Kleiner Core-Persistenzbaustein (Phase 10.2).
--
-- Zentrale Stelle für den Zugriff auf playdate.datastore. Das Modul kennt
-- weder Gameplay noch UI: Es liest/validiert einen einzelnen Fortschrittswert
-- (höchste erreichte Raumnummer) und schreibt ihn zurück. Alle anderen Module
-- bleiben Datastore-frei.
--
-- Verantwortlichkeiten:
--   Save.validate(data, maxPlayable, roomCount)  -> validierter Integer (1..avail)
--   Save.load(maxPlayable, roomCount)            -> Datastore lesen + validieren
--   Save.applyProgress(current, reached)         -> Monotonie-Entscheidung
--   Save.write(highestRoom)                      -> Datastore schreiben (pcall)
--
-- Fehlerverhalten: Lese- und Schreibfehler crashen weder den App-Start noch
-- das Gameplay; sie werden als false/1 gemeldet bzw. geloggt. Es gibt nur EINEN
-- Datastore (playdate.datastore, kein Dateiname) und genau EIN Feld
-- { highestRoom = <int> }.

-- Globale PascalCase-Tabelle (Modul-Konvention). Keine Imports nötig.
Save = {}

-- Validierung der gelesenen Datastore-Tabelle. Rein (kein Datastore-Zugriff).
-- Regeln (Spez 10.2):
--   - nil / keine Tabelle            -> 1 (nie gespeichert oder korrupt)
--   - Feld fehlt oder kein number    -> 1 (z. B. "3" als String: ungültig)
--   - nicht ganzzahlig (z. B. 2.5)   -> 1
--   - kleiner als 1 (0, -5)          -> 1
--   - größer als höchster spielbarer -> clamp auf min(maxPlayable, roomCount)
-- Rückgabe: Integer im Bereich 1..available. Der Datastore wird dabei nicht
-- umgeschrieben (defensiver Umgang mit Werten aus künftigen Versionen).
function Save.validate(data, maxPlayable, roomCount)
    local available = math.min(maxPlayable, roomCount)
    if type(data) ~= "table" then
        return 1
    end
    local v = data.highestRoom
    if type(v) ~= "number" then
        return 1
    end
    if v ~= math.floor(v) then
        return 1
    end
    if v < 1 then
        return 1
    end
    if v > available then
        return available
    end
    return v
end

-- Liest den Datastore genau einmal und liefert den validierten Fortschritt
-- (Fallback 1 bei Fehlern). Read-only: verändert keinen Gameplay-State.
function Save.load(maxPlayable, roomCount)
    local ok, data = pcall(function()
        return playdate.datastore.read()
    end)
    if not ok then
        -- Lesefehler: nicht crashen, sauber auf Raum 1 zurückfallen.
        return 1
    end
    return Save.validate(data, maxPlayable, roomCount)
end

-- Fortschritt anwenden (rein, monoton). Nur ein ECHTER neuer Höchststand
-- (reached > current) löst einen Write aus; der Wert sinkt nie.
-- Rückgabe: (neuerHöchststand, sollGeschriebenWerden)
function Save.applyProgress(currentHighest, reachedRoom)
    if reachedRoom > currentHighest then
        return reachedRoom, true
    end
    return currentHighest, false
end

-- Schreibt den Fortschritt in den Datastore (Default-Datastore, kein
-- Dateiname, genau ein Feld). pcall: Ein Schreibfehler darf das Gameplay
-- nicht blockieren — der Aufrufer bekommt false und kann loggen.
-- Rückgabe: (ok, errOrNil)
function Save.write(highestRoom)
    local ok, err = pcall(function()
        playdate.datastore.write({ highestRoom = highestRoom })
    end)
    return ok, err
end

return Save
