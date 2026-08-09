-- Camera: reine visuelle Ringkamera (Phase 8.1). Bildet eine World-Ringnummer
-- über die aktuelle Kameraposition (äußere Ringnummer) auf einen Bildschirmradius
-- ab. Beim Raumwechsel läuft über Config.cameraDuration eine Interpolation, in
-- der der alte Außenring nach außen wandert, der gemeinsame Ring auf 104 rückt
-- und ein neuer Innenring bei 68 einfährt. Easing: Smoothstep (langsam beginnen,
-- langsam enden). KEINE Gameplay-Wahrheit: Camera besitzt/verändert weder
-- State.player, State.switchStates/elementStates, Undo, Room.shutters,
-- Bridge.transit, roomComplete noch currentRoomIndex. Keine Kopie von Levels/
-- RoomData. Keine Imports; die Module werden zentral in main.lua geladen.
--
-- Ringnummern-Konvention (Audit): Die Leveldaten nummerieren die Ringe nach
-- innen ABNEHMEND: outer = n, inner = n-1, nächster Raum outer = n-1. Daher:
--   radius = Config.outerRadius - (cameraOuterRing - ringNumber) * ringSpacing
-- Damit gilt stabil: aktueller outer -> outerRadius, aktueller inner ->
-- innerRadius, vorheriger outer -> >outerRadius, nächster inner -> <innerRadius.

Camera = {}

local config <const> = Config

-- Toleranz für den Transitionsabschluss: verhindert, dass eine über viele
-- Frames akkumulierte Float-Abweichung (bei 50 fps: 60 * (1/50) ~= 1.1999994
-- statt exakt 1.2) den letzten Abschlussframe verschluckt. 1 ms ist ein
-- winziger Bruchteil eines Frames und verursacht keinen vorzeitigen Abschluss.
local EPSILON <const> = 1e-3

-- Ringabstand in Pixeln, aus Config abgeleitet (keine Magic Number).
local ringSpacing <const> = config.outerRadius - config.innerRadius

-- Stabile aktuelle äußere Ringnummer (wird erst beim Abschluss der Transition
-- auf den Zielring gesetzt).
Camera.currentOuterRing = nil

-- Laufende Transition (nil = keine).
Camera.transition = nil

-- Deterministisches Smoothstep-Easing: t in [0,1], ease-in + ease-out.
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Initialisiert die Kamera auf den aktuellen äußeren Ring (Spielstart). Keine
-- Animation.
function Camera.init(outerRing)
    Camera.currentOuterRing = outerRing
    Camera.transition = nil
end

-- Läuft gerade eine Raumtransition?
function Camera.isTransitioning()
    return Camera.transition ~= nil and Camera.transition.active == true
end

-- Roher Fortschritt 0..1 während einer Transition, sonst nil. Kein Overshoot.
function Camera.getProgress()
    if not Camera.isTransitioning() then
        return nil
    end
    local t = Camera.transition
    if t.duration <= 0 then
        return 1
    end
    return math.min(1, t.elapsed / t.duration)
end

-- Eased Fortschritt (Smoothstep) 0..1, sonst nil.
function Camera.getEasedProgress()
    local raw = Camera.getProgress()
    if raw == nil then
        return nil
    end
    return smoothstep(raw)
end

-- Stabile aktuelle äußere Ringnummer (Zielring nach Abschluss).
function Camera.getCurrentOuterRing()
    return Camera.currentOuterRing
end

-- Zielring der laufenden Transition (oder aktuelle äußere Ringnummer).
function Camera.getTargetOuterRing()
    if Camera.isTransitioning() then
        return Camera.transition.toOuterRing
    end
    return Camera.currentOuterRing
end

-- Kontinuierliche (visuell wirksame) äußere Ringnummer: während der Transition
-- interpoliert, sonst stabil.
function Camera.getVisualOuterRing()
    if Camera.isTransitioning() then
        local t = Camera.transition
        local eased = Camera.getEasedProgress() or 0
        return t.fromOuterRing + (t.toOuterRing - t.fromOuterRing) * eased
    end
    return Camera.currentOuterRing
end

-- Bildschirmradius einer World-Ringnummer (allgemeine Abbildung).
--   radius = outerRadius - (visualOuter - ringNumber) * ringSpacing
-- Dadurch: visualOuter -> 104, visualOuter-1 -> 68, visualOuter-2 -> 32,
-- visualOuter+1 -> 140 (alter Außenring), jeweils gemäß Datenkonvention.
function Camera.getRadius(ringNumber)
    local visualOuter = Camera.getVisualOuterRing()
    return config.outerRadius - (visualOuter - ringNumber) * ringSpacing
end

-- Bricht eine laufende Transition ab (defensiv; Raumstart u.ä.).
function Camera.reset()
    Camera.transition = nil
end

-- Startet eine Raumtransition. Defensiv:
--   - bei bereits laufender Transition: false (keine parallele Transition)
--   - fromInnerRing muss == toOuterRing sein (gemeinsamer Ring; die Kamera
--     ersetzt keinen Ring durch eine andere Nummer)
--   - Ringpaare müssen benachbart sein (Datenkonvention: inner == outer - 1)
-- Rückgabe: true bei Erfolg, false wenn bereits eine Transition läuft.
function Camera.beginRoomTransition(fromOuterRing, fromInnerRing, toOuterRing, toInnerRing)
    if Camera.isTransitioning() then
        return false
    end
    if fromInnerRing ~= toOuterRing then
        error("Camera.beginRoomTransition: fromInnerRing (" .. tostring(fromInnerRing) .. ") != toOuterRing (" .. tostring(toOuterRing) .. ")")
    end
    if fromInnerRing ~= fromOuterRing - 1 then
        error("Camera.beginRoomTransition: Ringpaar nicht benachbart (fromOuter " .. tostring(fromOuterRing) .. ", fromInner " .. tostring(fromInnerRing) .. ")")
    end
    if toInnerRing ~= toOuterRing - 1 then
        error("Camera.beginRoomTransition: Ringpaar nicht benachbart (toOuter " .. tostring(toOuterRing) .. ", toInner " .. tostring(toInnerRing) .. ")")
    end
    Camera.transition = {
        active = true,
        fromOuterRing = fromOuterRing,
        fromInnerRing = fromInnerRing,
        toOuterRing = toOuterRing,
        toInnerRing = toInnerRing,
        elapsed = 0,
        duration = config.cameraDuration,
    }
    return true
end

-- Schaltet die Transition weiter. Abschluss genau einmal bei raw >= 1:
-- currentOuterRing = toOuterRing, transition = nil. Kein Overshoot.
function Camera.update(dt)
    if not Camera.isTransitioning() then
        return
    end
    local t = Camera.transition
    t.elapsed = t.elapsed + dt
    -- Abschluss genau einmal, tolerant gegen Float-Akkumulation (keine
    -- Floating-Reste: currentOuterRing exakt auf den Zielring).
    if t.elapsed >= t.duration - EPSILON then
        Camera.currentOuterRing = t.toOuterRing
        Camera.transition = nil
    end
end

return Camera