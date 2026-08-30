-- Player: liest Eingabe (Kurbel + D-Pad) und berechnet das gewünschte,
-- vorzeichenbehaftete Winkel-Delta für einen Frame.
-- Keine Bewegung: State.player wird hier noch NICHT verändert. Kein Sweep,
-- keine Kollision, keine Schalter, kein Undo. Keine Imports; Config und State
-- werden zentral in main.lua geladen.

Player = {}

local config <const> = Config
local state <const> = State
local geo <const> = Geometry

-- Reine, testbare Berechnung des gewünschten Deltas für einen Frame.
--   crankChange:  roher Kurbel-Delta in Grad (normal, nicht beschleunigt)
--   leftPressed:  D-Pad links gedrückt?
--   rightPressed: D-Pad rechts gedrückt?
--   dt:           Framedauer in Sekunden
--   resistance:   optionaler Dämpfungsfaktor für den Kurbelanteil (1 = normal;
--                 <1 = Kurbel-Widerstand, z. B. vor einer aktiven Brücke).
--                 Rein mechanisch: der D-Pad-Anteil bleibt IMMER ungedämpft.
-- Rückgabe: vorzeichenbehaftetes gewünschtes Winkel-Delta, KEINE Normalisierung.
function Player.computeDesiredDelta(crankChange, leftPressed, rightPressed, dt, resistance)
    local crankDelta = crankChange * config.crankRatio
    local factor = resistance or 1
    if factor < 1 then
        crankDelta = crankDelta * factor
    end

    local dpadDelta = 0
    if leftPressed and not rightPressed then
        dpadDelta = -config.dpadSpeed * dt
    elseif rightPressed and not leftPressed then
        dpadDelta = config.dpadSpeed * dt
    end

    return crankDelta + dpadDelta
end

-- Kurbel-Widerstand kurz vor einer AKTIVEN Brücke (Auftrag): liefert den
-- Dämpfungsfaktor (1 = normal) für den Kurbelanteil, wenn der Player in der
-- schmalen Widerstandszone unmittelbar VOR dem Dock einer aktiven Brücke
-- steht und sich in deren Richtung bewegt (direction: +1 CW, -1 CCW). Die
-- Zone liegt zwischen dockRange und dockRange + bridgeResistanceRange —
-- also noch vor dem eigentlichen Andocken. D-Pad bleibt unberührt. Reine
-- Query, kein Gameplay-Effekt auf State; fährt der Player weg (Vorwärts-
-- distanz > Zone bzw. hinter der Brücke), greift sofort wieder Faktor 1.
function Player.bridgeResistanceFactor(direction)
    local range = config.bridgeResistanceRange
    if not range or range <= 0 then
        return 1
    end
    local dock = config.dockRange
    local pa = state.player.angle
    for _, b in ipairs(state.room.bridges) do
        if state.elementStates[b.id] == true then
            local dist
            if direction > 0 then
                dist = geo.norm(b.angle - pa)
            else
                dist = geo.norm(pa - b.angle)
            end
            if dist > dock and dist <= dock + range then
                return config.bridgeResistanceFactor
            end
        end
    end
    -- Kernbrücke (Gate): dieselbe leichte Kurbel-Schwelle kurz vor dem
    -- aktiven Ausgang — der Spieler fühlt denselben Übergang wie an jeder
    -- anderen Brücke (Ring -> Bridge-Dock -> bewusster Kurbelimpuls).
    local g = state.room.gate
    if g and state.elementStates[g.id] == true and state.player.ring == (g.ring or "inner") then
        local dist
        if direction > 0 then
            dist = geo.norm(g.angle - pa)
        else
            dist = geo.norm(pa - g.angle)
        end
        if dist > dock and dist <= dock + range then
            return config.bridgeResistanceFactor
        end
    end
    return 1
end

-- Liest die echte Playdate-Eingabe genau einmal pro Aufruf/Frame und delegiert
-- an computeDesiredDelta. Verwendet den normalen, nicht beschleunigten
-- Kurbel-Delta-Wert (erster Rückgabewert von playdate.getCrankChange()).
-- Verändert State.player nicht.
function Player.getDesiredDelta(dt)
    local change, _ = playdate.getCrankChange()
    local leftPressed = playdate.buttonIsPressed(playdate.kButtonLeft)
    local rightPressed = playdate.buttonIsPressed(playdate.kButtonRight)
    -- Kurbel-Widerstand vor aktiven Brücken: nur auf den Kurbelanteil
    -- anwenden (D-Pad bleibt voll spielbar). Nur bei tatsächlichem Kurbel-
    -- Input (change ~= 0), damit reines D-Pad nie gedämpft wird.
    local resistance = 1
    if change ~= 0 then
        resistance = Player.bridgeResistanceFactor(change > 0 and 1 or -1)
    end
    return Player.computeDesiredDelta(change, leftPressed, rightPressed, dt, resistance)
end

return Player