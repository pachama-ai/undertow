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
--   gateData:    room.gate ({ id, angle, free, ring? })
--   playerRing:  "outer" | "inner"
--   playerAngle: aktueller Spielerwinkel
-- Rückgabe: true nur wenn playerRing == gateData.ring (Default "inner") UND
--   State.elementStates[gateData.id] == true UND
--   |Geometry.delta(playerAngle, gateData.angle)| <= Config.dockRange UND
--   (falls ein Baby im Raum ist) das Baby ebenfalls auf dem Gate-Ring UND
--   im Gate-Dock-Bereich steht. Ein Raum mit Baby kann NUR gemeinsam
--   abgeschlossen werden (Produktregel: finale Raumübergänge nur mit Baby;
--   normale Brücken innerhalb eines Raums bleiben ohne Baby nutzbar).
-- Das Gate beendet in diesem Schritt nur den Raum; es lädt selbst keinen
-- nächsten Raum und verändert keinen Raumindex.
function Gate.isUsable(gateData, playerRing, playerAngle)
    -- Generisch: das Gate kann auf jedem spielbaren Ring liegen (gate.ring,
    -- Default "inner" für alle bestehenden Räume).
    local gateRing = gateData.ring or "inner"
    if playerRing ~= gateRing then
        return false
    end
    if state.elementStates[gateData.id] ~= true then
        return false
    end
    -- KEIN SEGMENT GENAU VOR DEM TOR: Überdeckt eine LOGISCH geschlossene
    -- Blende auf dem Tor-Ring die Torachse (|Delta| <= shutterArcWidth/2), ist
    -- das Gate NICHT benutzbar — ein Segment direkt vor der (Kern-)Brücke
    -- verhindert das Überqueren. Bewusst die logische Schließung statt der
    -- physischen collisionActive (G7 darf das Blockieren nicht aufheben).
    for _, sh in ipairs(state.room.shutters or {}) do
        if sh.ring == gateRing and State.elementStates[sh.id] == false then
            if math.abs(geo.delta(sh.angle, gateData.angle)) <= config.shutterArcWidth / 2 then
                return false
            end
        end
    end
    if math.abs(geo.delta(playerAngle, gateData.angle)) > config.dockRange then
        return false
    end
    -- Gemeinsamer Ausgang: ist ein Baby im Raum, muss es mit dabei sein.
    if state.baby then
        if state.baby.ring ~= gateRing then
            return false
        end
        if math.abs(geo.delta(state.baby.angle, gateData.angle)) > config.babyDockRange then
            return false
        end
    end
    return true
end

return Gate