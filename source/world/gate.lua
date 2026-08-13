-- Gate: logische Abfrage, ob die Kernbrücke an der aktuellen Position nutzbar
-- ist (Spieler auf inner, Gate ausgefahren, in Docking-Reichweite). Reine
-- Query — keine Raumprogression, keine Zustandsänderung. Der Aktivzustand
-- kommt ausschließlich aus State.elementStates; es gibt keine zweite mutable
-- Wahrheit. Keine Imports; die Module werden zentral in main.lua geladen.

Gate = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State

-- Prüft, ob das Gate gateData für den Spieler nutzbar ist (GEMEINSAMER
-- RAUMAUSGANG).
--   gateData:    room.gate ({ id, angle, free })
--   playerRing:  "outer" | "inner"
--   playerAngle: aktueller Spielerwinkel
-- Rückgabe: true nur wenn playerRing == "inner" UND
--   State.elementStates[gateData.id] == true UND
--   |Geometry.delta(playerAngle, gateData.angle)| <= Config.dockRange UND
--   (falls ein Baby im Raum ist) das Baby ebenfalls auf dem inneren Ring UND
--   im Gate-Dock-Bereich steht. Ein Raum mit Baby kann NUR gemeinsam
--   abgeschlossen werden (Produktregel: finale Raumübergänge nur mit Baby;
--   normale Brücken innerhalb eines Raums bleiben ohne Baby nutzbar).
-- Das Gate beendet in diesem Schritt nur den Raum; es lädt selbst keinen
-- nächsten Raum und verändert keinen Raumindex.
function Gate.isUsable(gateData, playerRing, playerAngle)
    if playerRing ~= "inner" then
        return false
    end
    if state.elementStates[gateData.id] ~= true then
        return false
    end
    if math.abs(geo.delta(playerAngle, gateData.angle)) > config.dockRange then
        return false
    end
    -- Gemeinsamer Ausgang: ist ein Baby im Raum, muss es mit dabei sein.
    if state.baby then
        if state.baby.ring ~= "inner" then
            return false
        end
        if math.abs(geo.delta(state.baby.angle, gateData.angle)) > config.babyDockRange then
            return false
        end
    end
    return true
end

return Gate