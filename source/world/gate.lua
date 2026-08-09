-- Gate: logische Abfrage, ob die Kernbrücke an der aktuellen Position nutzbar
-- ist (Spieler auf inner, Gate ausgefahren, in Docking-Reichweite). Reine
-- Query — keine Raumprogression, keine Zustandsänderung. Der Aktivzustand
-- kommt ausschließlich aus State.elementStates; es gibt keine zweite mutable
-- Wahrheit. Keine Imports; die Module werden zentral in main.lua geladen.

Gate = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State

-- Prüft, ob das Gate gateData für den Spieler nutzbar ist.
--   gateData:    room.gate ({ id, angle, free })
--   playerRing:  "outer" | "inner"
--   playerAngle: aktueller Spielerwinkel
-- Rückgabe: true nur wenn playerRing == "inner" UND
--   State.elementStates[gateData.id] == true UND
--   |Geometry.delta(playerAngle, gateData.angle)| <= Config.dockRange.
-- Das Gate beendet in diesem Schritt nur den Raum; es lädt selbst keinen
-- nächsten Raum und verändert keinen Raumindex.
function Gate.isUsable(gateData, playerRing, playerAngle)
    if playerRing ~= "inner" then
        return false
    end
    if state.elementStates[gateData.id] ~= true then
        return false
    end
    return math.abs(geo.delta(playerAngle, gateData.angle)) <= config.dockRange
end

return Gate