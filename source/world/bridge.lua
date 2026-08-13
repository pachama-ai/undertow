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
-- Bei einem GEMEINSAMEN Transit (Player+Baby) ist das der Player-Fortschritt
-- (nach kurzem Halt + Lead), damit der Player knapp hinter dem Baby bleibt.
function Bridge.getTransitProgress()
    if not Bridge.isCrossing() then
        return nil
    end
    local t = Bridge.transit
    if t.shared then
        local denom = t.duration
        if denom <= 0 then
            return 1
        end
        local p = (t.elapsed - t.hold - t.babyLead) / denom
        return math.max(0, math.min(1, p))
    end
    if t.duration <= 0 then
        return 1
    end
    return math.min(1, t.elapsed / t.duration)
end

-- Baby-Fortschritt beim GEMEINSAMEN Transit (Baby startet nach dem Halt vor
-- dem Player). Sonst nil. Kein Overshoot.
function Bridge.getBabyTransitProgress()
    local t = Bridge.transit
    if not (t and t.active and t.shared) then
        return nil
    end
    local denom = t.duration
    if denom <= 0 then
        return 1
    end
    local p = (t.elapsed - t.hold) / denom
    return math.max(0, math.min(1, p))
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

-- Startet einen GEMEINSAMEN Brückentransit von Player + Baby (EIN A).
-- Voraussetzung: Baby korrekt an der Brücke (Room.tryUseConnection prüft das
-- über Baby.canTransfer). Eine gemeinsame Progress-Wahrheit steuert beide; das
-- Baby startet nach kurzem Halt (hold) und kleinem Lead vor dem Player. Der
-- Ring wechselt für beide erst beim Abschluss (Bridge.update). Rückgabe false,
-- wenn bereits ein Transit läuft oder kein Baby vorhanden.
function Bridge.beginSharedTransit(bridgeData, fromRing)
    if Bridge.isCrossing() then
        return false
    end
    if not state.baby then
        return false
    end
    local toRing
    if fromRing == "outer" then
        toRing = "inner"
    elseif fromRing == "inner" then
        toRing = "outer"
    else
        error("Bridge.beginSharedTransit: ungültiger fromRing '" .. tostring(fromRing) .. "'")
    end
    -- Player-Startwinkel für die visuelle Achs-Gleitphase (Hold+Lead): Der
    -- Player bleibt kurz hinter dem am Dock wartenden Baby sichtbar und
    -- gleitet erst auf die Brückenachse, statt sofort exakt darauf zu landen
    -- (kein Überlappen der beiden Charaktere beim Transitstart).
    local playerStartAngle = state.player.angle
    Bridge.transit = {
        active = true,
        fromRing = fromRing,
        toRing = toRing,
        angle = bridgeData.angle,
        elapsed = 0,
        duration = config.sharedBridgeDuration,
        hold = config.sharedBridgeHold,
        babyLead = config.sharedBabyLead,
        shared = true,
        playerStartAngle = playerStartAngle,
    }
    state.player.angle = Geometry.norm(bridgeData.angle)
    return true
end

-- Schaltet den Transit weiter. Rückgabe true genau im Abschlussframe: dann
-- werden Player (und bei gemeinsamem Transit auch das Baby) auf den Zielring
-- gesetzt und der Transit deaktiviert. Kein Overshoot. Zweiter Rückgabewert:
-- true, wenn es ein gemeinsamer Player+Baby-Transit war (für UI-Landing).
function Bridge.update(dt)
    if not Bridge.isCrossing() then
        return false, false
    end
    local t = Bridge.transit
    t.elapsed = t.elapsed + dt
    local done
    if t.shared then
        done = t.elapsed >= t.hold + t.duration + t.babyLead
    else
        done = t.elapsed >= t.duration
    end
    if done then
        state.player.ring = t.toRing
        state.player.angle = Geometry.norm(t.angle)
        if t.shared then
            -- Baby landet leicht voraus (in der bisherigen Schieberichtung).
            local dir = (state.baby and state.baby.lastPushDirection) or 1
            state.setBaby(t.toRing, Geometry.norm(t.angle + dir * config.babyBridgeExitOffset))
        end
        Bridge.transit = nil
        return true, t.shared
    end
    return false, t.shared
end

return Bridge