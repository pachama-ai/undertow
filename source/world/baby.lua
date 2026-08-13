-- Baby: kleines Wesen derselben Art wie der Spieler (generisch, Raum 2).
-- Kapselt die reine Baby-Logik: Schiebemathematik, Brückentransfer-Query,
-- isolierter Brückentransit und Ziel-Einrastung. Kein Rendering, keine
-- Eingabe, kein Undo. Alle Mutationen laufen über core/state.lua
-- (State.baby / State.setBaby / State.settleBaby), damit Undo und Restart
-- korrekt funktionieren. Keine Imports; die Module werden zentral in
-- main.lua geladen (Bridge wird zur Laufzeit als globale Tabelle aufgelöst).

Baby = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State

-- Distanz von fromAngle zu targetAngle entlang der Bewegungsrichtung.
-- direction: +1 = im Uhrzeigersinn, -1 = gegen den Uhrzeigersinn.
-- Ergebnis in [0, 360).
local function distanceAlongDirection(fromAngle, targetAngle, direction)
    if direction > 0 then
        return geo.norm(targetAngle - fromAngle)
    end
    return geo.norm(fromAngle - targetAngle)
end

-- Kontaktabstand in Grad: Winkelabstand der Mittelpunkte, bei dem der Spieler
-- das Baby zu schieben beginnt. Abgeleitet aus Spielerradius + Babyradius und
-- dem inneren Ringradius (konservativ: kleinster sichtbarer Ring => größter
-- Winkelabstand pro Pixel). Damit überlappen die Mittelpunkte auf keinem Ring.
-- Keine Magic Number im Gameplaycode.
function Baby.contactDeg()
    return (config.playerRadius + config.babyRadius) / config.innerRadius * (180 / math.pi)
end

-- Reine Push-Berechnung für einen Frame (nach dem Spieler-Sweep).
--   babyAngle:    Babywinkel vor dem Schub
--   playerStart:  Spielerwinkel am Frame-Anfang
--   direction:    +1 CW, -1 CCW
--   actualDist:   tatsächlich zurückgelegte Spielerstrecke (|delta|)
-- Rückgabe: nil (kein Schub: Spieler erreicht das Baby nicht; Ziehen ist
-- verboten) oder (newAngle, pushAmount, direction).
-- Das Baby endet exakt im Kontaktabstand VOR dem Spieler (kein Durchspringen,
-- Wraparound über Geometry.norm am Ende).
function Baby.computePush(babyAngle, playerStart, direction, actualDist)
    if babyAngle == nil or actualDist <= 0 then
        return nil
    end
    local gapForward = distanceAlongDirection(playerStart, babyAngle, direction)
    local contact = Baby.contactDeg()
    local travelBeforeContact = math.max(0, gapForward - contact)
    if actualDist <= travelBeforeContact then
        return nil
    end
    local pushAmount = actualDist - travelBeforeContact
    return geo.norm(babyAngle + direction * pushAmount), pushAmount, direction
end

-- Brückentransfer-Query (Fall A): kann das Baby an diesem aktiven Bridge-Dock
-- zuerst über die Brücke geschickt werden? Bedingungen:
--   Baby auf demselben Ring wie der Spieler, nicht eingerastet,
--   Brücke aktiv UND für den Spieler nutzbar (DockRange),
--   Baby innerhalb Config.babyDockRange der Brückenachse.
function Baby.canTransfer(bridgeData, playerRing, playerAngle)
    local baby = state.baby
    if not baby or baby.settled then
        return false
    end
    if baby.ring ~= playerRing then
        return false
    end
    if state.elementStates[bridgeData.id] ~= true then
        return false
    end
    if not Bridge.isUsable(bridgeData, playerAngle) then
        return false
    end
    return math.abs(geo.delta(baby.angle, bridgeData.angle)) <= config.babyDockRange
end

-- Ist das Baby bereits im Ziel eingerastet? Read-only-Helfer.
function Baby.isSettled()
    return state.baby ~= nil and state.baby.settled == true
end

-- Read-only: liefert das Bridge-Dock, an dem ein Baby-Transfer aktuell bereit
-- ist (Baby am Dock, Player dahinter, Brücke aktiv), oder nil. Reine Query,
-- kein Gameplay-Effekt; wird vom Renderer für den visuellen "Ready"-Zustand
-- genutzt. Während eines laufenden Baby-Transits ist nie ein Dock bereit.
function Baby.findTransferReadyBridge()
    -- Während eines Brückentransits (solo oder gemeinsam) ist nie ein Dock bereit.
    if Baby.isCrossing() or (Bridge.isCrossing() and Bridge.getTransit().shared) then
        return nil
    end
    local baby = state.baby
    if not baby or baby.settled then
        return nil
    end
    for _, b in ipairs(state.room.bridges) do
        if Baby.canTransfer(b, state.player.ring, state.player.angle) then
            return b
        end
    end
    return nil
end

-- --- Isolierter Baby-Brückentransit (kurze radiale Bewegung) --------------
-- Analog zu Bridge.transit, wirkt aber auf State.baby statt auf State.player.
-- Der Ring wechselt erst beim Abschluss; kein Undo (wie beim Spielertransit).
Baby.transit = nil

function Baby.isCrossing()
    return Baby.transit ~= nil and Baby.transit.active == true
end

function Baby.getTransit()
    return Baby.transit
end

-- Fortschritt 0..1 während eines aktiven Transits, sonst nil. Kein Overshoot.
function Baby.getTransitProgress()
    if not Baby.isCrossing() then
        return nil
    end
    local t = Baby.transit
    if t.duration <= 0 then
        return 1
    end
    return math.min(1, t.elapsed / t.duration)
end

-- Bricht einen laufenden Transit ab (Raumstart, Undo, Raumwechsel).
function Baby.resetTransit()
    Baby.transit = nil
end

-- Startet den Baby-Transit an der Brücke von fromRing zur Gegenseite.
-- Rückgabe false bei bereits laufendem Transit oder ohne Baby.
function Baby.beginTransit(bridgeData, fromRing)
    if Baby.isCrossing() then
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
        error("Baby.beginTransit: ungültiger fromRing '" .. tostring(fromRing) .. "'")
    end
    Baby.transit = {
        active = true,
        fromRing = fromRing,
        toRing = toRing,
        angle = bridgeData.angle,
        elapsed = 0,
        duration = config.babyBridgeAnimDuration,
    }
    return true
end

-- Schaltet den Baby-Transit weiter. Rückgabe true im Abschlussframe: dann wird
-- State.baby auf den Zielring gesetzt — mit kleiner Austrittsposition in der
-- bisherigen Schieberichtung, damit Baby und Spieler nach dem anschließenden
-- Spielertransit nicht exakt übereinander liegen.
function Baby.update(dt)
    if not Baby.isCrossing() then
        return false
    end
    local t = Baby.transit
    t.elapsed = t.elapsed + dt
    if t.elapsed >= t.duration then
        local dir = state.baby.lastPushDirection or 1
        state.setBaby(t.toRing, geo.norm(t.angle + dir * config.babyBridgeExitOffset))
        Baby.transit = nil
        return true
    end
    return false
end

return Baby
