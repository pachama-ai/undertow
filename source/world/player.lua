-- Player: liest Eingabe (Kurbel + D-Pad) und berechnet das gewünschte,
-- vorzeichenbehaftete Winkel-Delta für einen Frame.
-- Keine Bewegung: State.player wird hier noch NICHT verändert. Kein Sweep,
-- keine Kollision, keine Schalter, kein Undo. Keine Imports; Config und State
-- werden zentral in main.lua geladen.

Player = {}

local config <const> = Config
local state <const> = State

-- Reine, testbare Berechnung des gewünschten Deltas für einen Frame.
--   crankChange:  roher Kurbel-Delta in Grad (normal, nicht beschleunigt)
--   leftPressed:  D-Pad links gedrückt?
--   rightPressed: D-Pad rechts gedrückt?
--   dt:           Framedauer in Sekunden
-- Rückgabe: vorzeichenbehaftetes gewünschtes Winkel-Delta, KEINE Normalisierung.
function Player.computeDesiredDelta(crankChange, leftPressed, rightPressed, dt)
    local crankDelta = crankChange * config.crankRatio

    local dpadDelta = 0
    if leftPressed and not rightPressed then
        dpadDelta = -config.dpadSpeed * dt
    elseif rightPressed and not leftPressed then
        dpadDelta = config.dpadSpeed * dt
    end

    return crankDelta + dpadDelta
end

-- Liest die echte Playdate-Eingabe genau einmal pro Aufruf/Frame und delegiert
-- an computeDesiredDelta. Verwendet den normalen, nicht beschleunigten
-- Kurbel-Delta-Wert (erster Rückgabewert von playdate.getCrankChange()).
-- Verändert State.player nicht.
function Player.getDesiredDelta(dt)
    local change, _ = playdate.getCrankChange()
    local leftPressed = playdate.buttonIsPressed(playdate.kButtonLeft)
    local rightPressed = playdate.buttonIsPressed(playdate.kButtonRight)
    return Player.computeDesiredDelta(change, leftPressed, rightPressed, dt)
end

return Player