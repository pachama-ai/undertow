-- Switch: reine, schalterspezifische Regeln (Kanten, Zielzustand, Bogen-
-- Zugehörigkeit). Keine Bewegung, kein Undo, kein State-Mutation, kein Sweep.
-- Die Orchestrierung (Sweep, Traversal-State, Undo-Timing, State.setSwitch)
-- liegt in Room. Keine Imports; die Module werden zentral in main.lua geladen.
--
-- Geschwindigkeitsunabhängige vollständige Durchquerung (Release-Fix 1):
-- Ein Schalter wird bei vollständiger Überquerung seines Bogens gesetzt —
-- über beliebig viele Frames (kleine D-Pad-Deltas wie 1,8°/Frame) ODER in
-- einem einzigen großen Delta (Kurbel). Crank und D-Pad besitzen exakt
-- dieselbe Gameplaysemantik. Switch selbst hält KEINEN Traversal-Zustand; er
-- bietet nur die reinen Kanten-/Bogen-Geometrie-Hilfen, mit denen Room den
-- transienten Traversal-Zustand (Room.switchTraversal) verwaltet.

Switch = {}

local config <const> = Config
local geo <const> = Geometry

local EPSILON <const> = 0.000001

-- Distanz von fromAngle zu targetAngle entlang der Bewegungsrichtung.
-- direction: +1 = im Uhrzeigersinn, -1 = gegen den Uhrzeigersinn.
-- Ergebnis in [0, 360).
local function distanceAlongDirection(fromAngle, targetAngle, direction)
    if direction > 0 then
        return Geometry.norm(targetAngle - fromAngle)
    end
    return Geometry.norm(fromAngle - targetAngle)
end

-- Eintrittskante des Schalterbogens für die Bewegungsrichtung.
-- CW: angle - width/2, CCW: angle + width/2.
function Switch.getEntryAngle(switchData, direction)
    if direction == 1 then
        return Geometry.norm(switchData.angle - config.switchArcWidth / 2)
    end
    if direction == -1 then
        return Geometry.norm(switchData.angle + config.switchArcWidth / 2)
    end
    error("Switch.getEntryAngle: ungültige Richtung '" .. tostring(direction) .. "'")
end

-- Austrittskante des Schalterbogens für die Bewegungsrichtung.
-- CW: angle + width/2, CCW: angle - width/2. Auslösung erfolgt an der
-- Austrittskante, nicht am Mittelpunkt.
function Switch.getExitAngle(switchData, direction)
    if direction == 1 then
        return Geometry.norm(switchData.angle + config.switchArcWidth / 2)
    end
    if direction == -1 then
        return Geometry.norm(switchData.angle - config.switchArcWidth / 2)
    end
    error("Switch.getExitAngle: ungültige Richtung '" .. tostring(direction) .. "'")
end

-- Zielzustand zur Bewegungsrichtung. Kein Toggle: Die Entscheidung, ob eine
-- echte Änderung vorliegt, trifft State.setSwitch.
function Switch.getTargetState(direction)
    if direction == 1 then
        return "A"
    end
    if direction == -1 then
        return "B"
    end
    error("Switch.getTargetState: ungültige Richtung '" .. tostring(direction) .. "'")
end

-- Prüft, ob ein Winkel strikt (ohne die beiden Kanten) innerhalb des
-- Schalterbogens liegt. Eine Figur exakt auf einer Kante gilt als außerhalb.
-- Reine Bogen-Geometrie (kein Traversal-Zustand).
function Switch.isInsideArc(angle, switchData)
    local a = Geometry.norm(angle)
    local startAngle = Geometry.norm(switchData.angle - config.switchArcWidth / 2)
    local d = Geometry.norm(a - startAngle)
    if d <= EPSILON then
        return false
    end
    if math.abs(d - config.switchArcWidth) <= EPSILON then
        return false
    end
    return d < config.switchArcWidth
end

return Switch