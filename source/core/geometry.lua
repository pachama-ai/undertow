-- Geometrie- und Winkelhilfen für Ringe.
-- Reine Mathematik: kein Rendering, keine Eingabe, kein Spielzustand.
-- Winkel in Grad, 0 = 12 Uhr, im Uhrzeigersinn steigend.
-- Modulkonvention: genau eine globale PascalCase-Tabelle (Geometry).

Geometry = {}

-- Normalisiert jeden Winkel auf [0, 360).
function Geometry.norm(a)
    return ((a % 360) + 360) % 360
end

-- Kürzeste vorzeichenbehaftete Winkeldifferenz von fromAngle zu toAngle.
-- Positiv = im Uhrzeigersinn, Rückgabebereich (-180, 180].
-- Exakt gegenüberliegende Winkel ergeben konsistent +180.
function Geometry.delta(fromAngle, toAngle)
    local d = Geometry.norm(toAngle - fromAngle)
    if d > 180 then
        d = d - 360
    end
    return d
end

-- Prüft, ob Winkel a im Bogen liegt, der bei startAngle beginnt und sich im
-- Uhrzeigersinn über width Grad erstreckt. Beide Ränder zählen als enthalten.
-- width = 0 enthält nur exakt startAngle; width >= 360 gilt als Vollkreis.
function Geometry.inArc(a, startAngle, width)
    if width >= 360 then
        return true
    end
    return Geometry.norm(a - startAngle) <= width
end

-- Geometry.crossed(fromAngle, delta, targetAngle)
-- Prüft, ob die tatsächliche Bewegung von fromAngle um `delta` Grad den
-- Zielwinkel targetAngle überstrichen hat.
--
--   fromAngle   normalisierter Startwinkel
--   delta       tatsächlich zurückgelegte vorzeichenbehaftete Winkeländerung
--               positiv = im Uhrzeigersinn, negativ = gegen den Uhrzeigersinn
--               |delta| darf größer als 180° und größer als 360° sein
--   targetAngle Zielwinkel
--
-- Rückgabe: 1 = im Uhrzeigersinn überstrichen, -1 = gegen den Uhrzeigersinn
-- überstrichen, 0 = nicht überstrichen.
--
-- Randsemantik: Bewegungsweg ist (Startpunkt, Endpunkt]. Der Startpunkt ist
-- ausgeschlossen (fromAngle == targetAngle allein löst nichts aus). Der
-- Endpunkt ist eingeschlossen. Bei vollständiger Umrundung (|delta| >= 360)
-- gilt derselbe Zielwinkel wieder als überstrichen.
--
-- Rückgabe ist nur Richtung/Vorhandensein, nicht die Anzahl: Mehrfaches
-- Überstreichen desselben Schalters in derselben kontinuierlichen Bewegung
-- wirkt wie einmaliges Setzen (Schalter toggeln nicht, siehe G1).
function Geometry.crossed(fromAngle, delta, targetAngle)
    if delta == 0 then
        return 0
    end
    local from = Geometry.norm(fromAngle)
    local target = Geometry.norm(targetAngle)
    local travel = math.abs(delta)
    local crossedAny = false
    if delta > 0 then
        -- Abstand vom Start zum Ziel im Uhrzeigersinn: [0, 360)
        local forwardDistance = Geometry.norm(target - from)
        -- Volle Umrundungen überstreichen auch den Startwinkel selbst erneut.
        if math.floor(travel / 360) >= 1 and forwardDistance == 0 then
            crossedAny = true
        end
        if forwardDistance > 0 and forwardDistance <= travel then
            crossedAny = true
        end
        if crossedAny then
            return 1
        end
        return 0
    end
    -- delta < 0: Abstand vom Start zum Ziel gegen den Uhrzeigersinn
    local backwardDistance = Geometry.norm(from - target)
    if math.floor(travel / 360) >= 1 and backwardDistance == 0 then
        crossedAny = true
    end
    if backwardDistance > 0 and backwardDistance <= travel then
        crossedAny = true
    end
    if crossedAny then
        return -1
    end
    return 0
end

-- Geometry.polar(cx, cy, radius, angle) -> x, y
-- Winkelkonvention: 0° = oben, 90° = rechts, 180° = unten, 270° = links.
-- Da Bildschirm-Y nach unten wächst, wird der Kosinus-Anteil negiert.
-- Nur hier wird lokal in Radiant umgerechnet.
function Geometry.polar(cx, cy, radius, angle)
    local rad = math.rad(angle)
    return cx + radius * math.sin(rad), cy - radius * math.cos(rad)
end

return Geometry