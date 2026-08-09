-- sysmenu.lua — kleine Registrierungs-Hilfe für das Playdate-Systemmenü
-- (Phase 10.3). Nur Registrierung/Entfernung/Inspektion der zwei eigenen
-- Gameplay-Einträge; KEINE Gameplay-/World-Logik. Die Callbacks werden vom
-- Composition Root (main.lua) geliefert und setzen dort eine Pending-Aktion;
-- dieses Modul führt sie nur aus (Testbarkeit + Fallback).
--
-- API (verifiziert aus Inside Playdate, SDK 3.0.5):
--   playdate.getSystemMenu() -> playdate.menu
--   menu:addMenuItem(title, callback) -> (item, error)   (max. 3 eigene Items)
--   menu:removeMenuItem(item)
--   menu:removeAllMenuItems()   (nur eigene Items; OS-Items bleiben)
--   menu:getMenuItems()         (nur eigene Items)
--
-- Verhalten:
--   - install() ist idempotent: nie mehr als zwei eigene Einträge.
--   - removeAll() entfernt alle eigenen Einträge (Startmenü-Modus).
--   - Kein Spiel-Code berührt dieses Modul außer main.lua.

Sysmenu = {}

-- Systemmenu-Objekt (aus playdate.getSystemMenu(), nil falls nicht verfügbar).
local systemMenu = nil
-- Eigene Einträge: parallele Arrays (item, callback, label).
local items = {}
local itemCallbacks = {}
local itemLabels = {}
local installed = false

-- Exakte Labels der zwei Gameplay-Einträge (verbindlich, Punkt 42/49).
local GAMEPLAY_LABELS <const> = { "Raum neu starten", "Zum Menü" }

-- Initialisiert den Zugriff und entfernt alle eigenen Einträge (App-Start;
-- Startmenü hat keine Gameplay-Systemitems, Punkt 45/51). Idempotent.
function Sysmenu.init()
    systemMenu = playdate.getSystemMenu()
    installed = false
    items = {}
    itemCallbacks = {}
    itemLabels = {}
    if systemMenu ~= nil and systemMenu.removeAllMenuItems ~= nil then
        systemMenu:removeAllMenuItems()
    end
end

-- Registriert exakt die zwei Gameplay-Einträge (Raum neu starten / Zum Menü).
-- Idempotent: bei bereits installierten Einträgen passiert nichts (kein
-- Duplikat, Punkt 43/44/46). Bei fehlendem Systemmenu oder fehlgeschlagenem
-- Add wird zurückgerollt und false geliefert (keine halb-installierten Items).
-- restartCallback / mainMenuCallback sind reine Controller-Signale (setzen
-- im Composition Root eine Pending-Aktion); hier wird keine Logik gedeutet.
function Sysmenu.install(restartCallback, mainMenuCallback)
    if installed then
        return true
    end
    if systemMenu == nil then
        return false
    end
    local callbacks = { restartCallback, mainMenuCallback }
    local added = {}
    for i = 1, 2 do
        local item, err = systemMenu:addMenuItem(GAMEPLAY_LABELS[i], callbacks[i])
        if item == nil then
            -- Teil-Add rückgängig machen und NICHT als installiert markieren.
            Sysmenu.removeAll()
            return false
        end
        added[i] = item
        itemCallbacks[i] = callbacks[i]
        itemLabels[i] = GAMEPLAY_LABELS[i]
    end
    items = added
    installed = true
    return true
end

-- Entfernt alle eigenen Einträge (Startmenü-Modus; Punkt 45). Idempotent.
function Sysmenu.removeAll()
    if systemMenu ~= nil and systemMenu.removeAllMenuItems ~= nil then
        systemMenu:removeAllMenuItems()
    end
    installed = false
    items = {}
    itemCallbacks = {}
    itemLabels = {}
end

-- Sind die zwei Gameplay-Einträge gerade registriert?
function Sysmenu.isInstalled()
    return installed
end

-- Anzahl der erfolgreich registrierten eigenen Einträge (0, 1 oder 2).
function Sysmenu.getItemCount()
    return #items
end

-- Label eines registrierten Eintrags (1-basiert), sonst nil.
function Sysmenu.getLabel(index)
    return itemLabels[index]
end

-- Führt den Callback eines Eintrags aus (1-basiert). Rein für Tests und als
-- definierter Fallback; im Produktivbetrieb ruft das OS den Callback direkt.
function Sysmenu.invokeItem(index)
    local cb = itemCallbacks[index]
    if cb ~= nil then
        cb()
    end
end

return Sysmenu
