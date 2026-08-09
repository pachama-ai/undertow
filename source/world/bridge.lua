-- Bridge: logische Abfrage, ob eine Brücke an der aktuellen Position nutzbar
-- ist (ausgefahren + in Docking-Reichweite). Reine Query — keine Bewegung,
-- keine Zustandsänderung, kein Undo. Der Aktivzustand kommt ausschließlich
-- aus State.elementStates; es gibt keine zweite mutable Wahrheit.
-- Keine Imports; die Module werden zentral in main.lua geladen.

Bridge = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State

-- Prüft, ob die Brücke bridgeData an der Position playerAngle nutzbar ist.
--   bridgeData:  Eintrag aus room.bridges ({ id, angle, free })
--   playerAngle: aktueller Spielerwinkel
-- Rückgabe: true nur wenn State.elementStates[bridgeData.id] == true UND
--   |Geometry.delta(playerAngle, bridgeData.angle)| <= Config.dockRange.
-- Die Dockgrenze ist inklusive; den 0°-Wraparound übernimmt Geometry.delta.
function Bridge.isUsable(bridgeData, playerAngle)
    if state.elementStates[bridgeData.id] ~= true then
        return false
    end
    return math.abs(geo.delta(playerAngle, bridgeData.angle)) <= config.dockRange
end

-- --- Brückentransit (temporärer Runtime-Zustand) ---------------------------
-- Die radiale Überquerung über Config.bridgeAnimDuration. Während des
-- Transits bleibt State.player die einzige persistente Spielerposition; der
-- Ring wechselt erst beim Abschluss. Keine zweite Spielerposition, kein Undo.

Bridge.transit = nil

-- Läuft gerade ein Brückentransit?
function Bridge.isCrossing()
    return Bridge.transit ~= nil and Bridge.transit.active == true
end

-- Aktueller Transit (oder nil).
function Bridge.getTransit()
    return Bridge.transit
end

-- Fortschritt 0..1 während eines aktiven Transits, sonst nil. Kein Overshoot.
function Bridge.getTransitProgress()
    if not Bridge.isCrossing() then
        return nil
    end
    local t = Bridge.transit
    if t.duration <= 0 then
        return 1
    end
    return math.min(1, t.elapsed / t.duration)
end

-- Bricht einen laufenden Transit ab (Raumstart, Tests, spätere Raumwechsel).
function Bridge.resetTransit()
    Bridge.transit = nil
end

-- Startet einen Brückentransit von fromRing zur gegenüberliegenden Seite.
-- Richtet State.player.angle auf die Brückenachse aus, wechselt den Ring aber
-- NICHT (erst bei Transitabschluss via Bridge.update). Rückgabe: false, wenn
-- bereits ein Transit läuft (dann wird nichts überschrieben).
function Bridge.beginTransit(bridgeData, fromRing)
    if Bridge.isCrossing() then
        return false
    end
    local toRing
    if fromRing == "outer" then
        toRing = "inner"
    elseif fromRing == "inner" then
        toRing = "outer"
    else
        error("Bridge.beginTransit: ungültiger fromRing '" .. tostring(fromRing) .. "'")
    end
    Bridge.transit = {
        active = true,
        fromRing = fromRing,
        toRing = toRing,
        angle = bridgeData.angle,
        elapsed = 0,
        duration = config.bridgeAnimDuration,
    }
    state.player.angle = Geometry.norm(bridgeData.angle)
    return true
end

-- Schaltet den Transit weiter. Rückgabe true genau im Abschlussframe:
-- dann wird State.player.ring auf den Zielring gesetzt und der Transit
-- deaktiviert. Kein Overshoot (Fortschritt ist auf 0..1 begrenzt).
function Bridge.update(dt)
    if not Bridge.isCrossing() then
        return false
    end
    local t = Bridge.transit
    t.elapsed = t.elapsed + dt
    if t.elapsed >= t.duration then
        state.player.ring = t.toRing
        state.player.angle = Geometry.norm(t.angle)
        Bridge.transit = nil
        return true
    end
    return false
end

return Bridge