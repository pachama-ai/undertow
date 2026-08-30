-- RoomTransition: radialer Raumwechsel (der neue Level-/Room-Übergang).
--
-- Wenn ein Raum erfolgreich beendet wurde, schiebt sich der GESAMTE Ring-
-- aufbau visuell EINE STUFE NACH AUSSEN — um den festen Mittelpunkt
-- (200,120). Keine Kamerafahrt, kein Fade-to-black, kein Flash, kein
-- "LEVEL X"-Text, kein Screen-Skalieren. Der Bildschirmmittelpunkt bleibt
-- während des gesamten Übergangs stabil.
--
-- Kette (Design-Legende):
--   FUTURE  (innerster nächster Ring)  -> neuer AKTIVER Innenring
--   aktiver Innenring                   -> wandert auf die Außenposition
--   aktiver Außenring                   -> wandert weiter nach außen
--   ältere Ringe                         -> HISTORY (nur noch feine Spur)
--
-- Die Radius-Interpolation übernimmt die Kamera (Camera.beginRoomTransition
-- / Camera.getRadius); RoomTransition steuert nur die Phase im Übergang:
--   1) Target Settle (kurzer Halt, Camera-Hold)
--   2) Future Impuls (einmaliges kurzes Aufleuchten des Future-Rings)
--   3) Radial Shift (Ringe wandern nach außen, Ease-In-Out)
--   4) alte Puzzleobjekte lösen sich gestaffelt auf
--   5) neuer Raum wird am Reveal-Punkt geladen (main.lua)
--   6) neue Puzzleobjekte bauen sich gestaffelt auf (Brücken -> Objekte ->
--      Baby-Dock -> Player/Baby)
--   7) finaler Settle; danach gibt main.lua die Eingabe frei
--
-- Reine Präsentationslogik: berührt NIE State/Undo/Room/Bridge/Save/Levels
-- (read-only gegenüber Gameplay). Keine Projekt-Imports; Config/Camera werden
-- zentral in main.lua geladen.

RoomTransition = {}

local config <const> = Config
local geo <const> = Geometry

-- Laufender Übergang (nil/nicht aktiv = normales Gameplay).
RoomTransition.active = false
-- Nächster Raum (wird am Reveal-Punkt geladen, main.lua). nil = keiner.
RoomTransition.pendingRoomIndex = nil
-- Wurde der neue Raum bereits geladen (State-Swap)?
RoomTransition.newRoomLoaded = false

-- Figuren-Kontinuität (Player/Baby dürfen während der Transition NICHT
-- verschwinden): alte Position (RingNUMMER + Winkel, aus dem noch aktiven
-- Raum) und neue Startposition (aus den Daten des nächsten Raums). Wird von
-- main.lua gesetzt (RoomTransition selbst bleibt read-only gegenüber State).
-- Die Bildschirmposition wird radial mit der Kamera mitgeführt und über den
-- eased Fortschritt interpoliert (kein harter Sprung, kein Verschwinden).
RoomTransition.playerFrom = nil
RoomTransition.playerTo = nil
RoomTransition.babyFrom = nil
RoomTransition.babyTo = nil
-- Raumnummer des alten (gerade beendeten) Raums — wird nur für die
-- Mittelpunkt-Startposition der Figuren beim Kernbrücken-Abschluss (Gate)
-- gebraucht (from = Kernrand). Wird von main.lua gesetzt.
RoomTransition.oldRoomIndex = nil

-- Deterministischer Objekt-Offset [0,1] aus einem Seed (ID-String). Gibt
-- jedem Objekt eine feste, reproduzierbare Position in der Auflösungs-/
-- Aufbau-Staffelung (kein Zufall, keine Magic Number). Bewusst ohne Bit-Ops:
-- die Werte bleiben im exakt darstellbaren Ganzzahlbereich von Lua-Doubles
-- (< 2^53), damit kein "has no integer representation"-Fehler auftreten kann.
local function hashSeed(seed)
    local s = tostring(seed)
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 2147483647
    end
    return (h % 1000) / 1000
end

-- Weiches Easing (Smoothstep) für die Ringbewegung: beginnt kontrolliert,
-- beschleunigt, rastet weich ein. Kein Bounce, kein Overshoot.
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Startet den Übergang in den nächsten Raum. Der alte Raum bleibt zunächst
-- aktiv (Eingabe gesperrt); der neue Raum wird erst am Reveal-Punkt geladen.
function RoomTransition.start(nextIndex)
    RoomTransition.active = true
    RoomTransition.pendingRoomIndex = nextIndex
    RoomTransition.newRoomLoaded = false
    RoomTransition.oldRoomIndex = nil
end

-- Erfasst die Figuren-Positionen für die kontinuierliche Transition:
--   playerFrom/playerTo = { ring = <RingNUMMER>, angle = <Grad> }
--   babyFrom/babyTo     = gleiche Struktur oder nil (kein Baby).
-- playerFrom/babyFrom sind die Positionen des alten Raums (vor dem Laden),
-- playerTo/babyTo die Startpositionen des neuen Raums. Reine Daten, keine
-- State-Berührung.
function RoomTransition.captureFigures(playerFrom, playerTo, babyFrom, babyTo)
    RoomTransition.playerFrom = playerFrom
    RoomTransition.playerTo = playerTo
    RoomTransition.babyFrom = babyFrom or nil
    RoomTransition.babyTo = babyTo or nil
end

-- Bricht den Übergang vollständig ab (Raumstart/Restart/Menü).
function RoomTransition.reset()
    RoomTransition.active = false
    RoomTransition.pendingRoomIndex = nil
    RoomTransition.newRoomLoaded = false
    RoomTransition.playerFrom = nil
    RoomTransition.playerTo = nil
    RoomTransition.babyFrom = nil
    RoomTransition.babyTo = nil
    RoomTransition.oldRoomIndex = nil
end

-- Läuft gerade ein Raumübergang? Nur solange die Kamera-Transition aktiv ist.
function RoomTransition.isActive()
    return RoomTransition.active and Camera.isTransitioning()
end

-- Roher Bewegungsfortschritt 0..1 (ohne Settle-Hold), nil wenn inaktiv.
function RoomTransition.progress()
    if not RoomTransition.isActive() then
        return nil
    end
    return Camera.getProgress() or 0
end

-- Eased Bewegungsfortschritt 0..1 (Smoothstep), nil wenn inaktiv.
function RoomTransition.eased()
    local p = RoomTransition.progress()
    if p == nil then
        return nil
    end
    return smoothstep(p)
end

-- Ist der Reveal-Punkt erreicht (neuer Raum darf geladen werden)?
function RoomTransition.revealReached()
    local p = RoomTransition.progress()
    return p ~= nil and p >= config.roomTransRevealPoint
end

-- Markiert den neuen Raum als geladen (main.lua ruft dies nach startRoom auf).
function RoomTransition.markLoaded()
    RoomTransition.newRoomLoaded = true
end

-- Ist der neue Raum bereits geladen?
function RoomTransition.isNewRoomLoaded()
    return RoomTransition.newRoomLoaded
end

-- Auflösungsfaktor alter Puzzleobjekte: 1 (voll sichtbar) -> 0 (aufgelöst)
-- über [roomTransDissolveStart, roomTransDissolveEnd] des Bewegungsfortschritts.
function RoomTransition.oldFade(p)
    p = p or RoomTransition.progress() or 1
    local s = config.roomTransDissolveStart
    local e = config.roomTransDissolveEnd
    if p <= s then
        return 1
    end
    if p >= e then
        return 0
    end
    return 1 - (p - s) / (e - s)
end

-- Ist ein ALTES Objekt (Seed) beim Fortschritt p noch sichtbar? Die Objekte
-- verschwinden gestaffelt (deterministischer Offset je Objekt) zwischen
-- DissolveStart und DissolveEnd — kein gemeinsames Ein-Frame-Verschwinden.
function RoomTransition.oldVisible(p, seed)
    p = p or RoomTransition.progress() or 0
    local s = config.roomTransDissolveStart
    local e = config.roomTransDissolveEnd
    local t = s + (e - s) * hashSeed(seed)
    return p < t
end

-- Startradius einer Figur beim Transitionsstart (p=0):
--   ring == "center" (Kernbrücken-Abschluss am Gate): die Figur ist am
--     MITTELPUNKT gelandet — ihr Startradius ist der Kernrand des alten Raums
--     (die Kernbrücke endet dort; der Kern selbst bleibt unverändert).
--   ring == RingNUMMER: exakt der Kamera-Radius dieser Nummer beim Start.
local function figureStartRadius(f)
    if f.ring == "center" then
        local idx = RoomTransition.oldRoomIndex or 1
        return config.coreRadius + (idx - 1) * config.coreGrowthPerRoom
    end
    return Camera.getRadiusAtProgress(f.ring, 0)
end

-- Zielradius einer Figur beim Transitionsende (p=1): exakt der finale
-- Kamera-Radius des Zielrings (neue Levelgeometrie in Normalgröße). Dadurch
-- schließt der letzte Transitionsradius nahtlos an die State-Position des
-- neuen Levels an (kein Snap, kein Teleport).
local function figureEndRadius(t)
    if t.ring == "center" then
        return figureStartRadius(t)
    end
    return Camera.getRadiusAtProgress(t.ring, 1)
end

-- GLOBALE FIGURENREGEL (Raumübergang, kontinuierlich): Während der GESAMTEN
-- Transition bleibt der WINKEL einer Figur KONSTANT — ihr EIGENER Winkel aus
-- dem Übergang (playerTransitionAngle / babyTransitionAngle). Es gibt KEINE
-- tangentiale Interpolation, kein autonomes Herumlaufen, keine Bewegung zu
-- playerStartAngle/babyStartAngle. NUR der RADIUS transformiert — kontinuier-
-- lich von der Startposition (Kernrand / alter Ring) zur Zielposition (finaler
-- Radius des neuen Rings) mit DERSELBEN Transitionfunktion wie die Welt
-- (eased Kamera-Fortschritt, Smoothstep). Kein Sprung am Reveal-Punkt, kein
-- Despawn/Respawn: Die Figur wird radial MIT der Welt transformiert
-- (oldRadius -> Kern/Mittelpunkt -> newRadius). Der finale State-Handoff zur
-- neuen Startposition des nächsten Levels erfolgt erst NACH der Transition
-- (RoomTransition wird inaktiv, das normale Rendering übernimmt die State-
-- Position) — die Figur läuft also nie selbst und wird nie neu erzeugt.
local function figureContinuousPos(f, t)
    local fromR = figureStartRadius(f)
    local toR = figureEndRadius(t)
    local eased = RoomTransition.eased() or 0
    local radius = fromR + (toR - fromR) * eased
    local angle = f.angle
    -- ZWEI Werte einzeln auffangen, dann mit dem Winkel zurückgeben (ein
    -- direkter `return geo.polar(...), angle` würde den zweiten Wert (y)
    -- verschlucken — Lua-Adjustment bei Mehrfachrückgaben).
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    return x, y, angle
end

-- Bildschirmposition + Winkel des PLAYERS während der Transition (nil, wenn
-- inaktiv oder keine Daten). Winkel konstant (eigener Winkel), nur der Radius
-- wandert kontinuierlich (figureContinuousPos).
function RoomTransition.playerPosAndAngle()
    if not RoomTransition.isActive() then
        return nil
    end
    local f, t = RoomTransition.playerFrom, RoomTransition.playerTo
    if not f or not t then
        return nil
    end
    return figureContinuousPos(f, t)
end

-- Bildschirmposition + Winkel des BABYS während der Transition (nil, wenn
-- inaktiv, kein Baby oder keine Daten). Gleiche kontinuierliche Winkel-/Radius-
-- Regel wie beim Player (kein autonomes Baby-Wandern, kein Despawn).
function RoomTransition.babyPosAndAngle()
    if not RoomTransition.isActive() then
        return nil
    end
    local f, t = RoomTransition.babyFrom, RoomTransition.babyTo
    if not f or not t then
        return nil
    end
    return figureContinuousPos(f, t)
end

-- Ist ein NEUES Objekt (Seed) beim Fortschritt p sichtbar? Erscheint
-- gestaffelt innerhalb des Kategorie-Fensters [catStart, catEnd] (per Objekt
-- deterministisch versetzt) — kein gemeinsames Pop-In.
function RoomTransition.newVisible(p, catStart, catEnd, seed)
    p = p or RoomTransition.progress() or 0
    local t = catStart + (catEnd - catStart) * hashSeed(seed)
    return p >= t
end

-- Mappt eine RingNUMMER (tatsächliche Position aus dem Ausgangsraum) auf den
-- RING-NAMEN des Zielraums ("outer"/"middle"/"inner"). Beim radialen
-- Raumwechsel schieben sich die Ringe eine Stufe nach außen (der alte
-- Innenring wird zum neuen Außenring — gleiche Ringnummer). Damit können
-- Player und Baby ihre TATSÄCHLICHE Position (Ring + Winkel) über den
-- Übergang hinweg behalten, statt auf einen definierten Levelstart gesetzt
-- zu werden. Der Mittelring (Level 4, Ringnummer "outer - 0.5") wird
-- mitberücksichtigt, falls der Zielraum einen besitzt.
--   ringOrCenter: Ringnummer (Zahl) ODER "center" (Kernbrücken-Abschluss:
--     die Figuren stehen am Mittelpunkt — es gibt keinen Ring, Rückgabe nil).
--   roomData:     der NEUE Raum (Ringnummern).
-- Rückgabe: Ringname wenn die Nummer einem Ring des Zielraums entspricht,
-- sonst nil (dann bleibt der Levelstart-Ring erhalten).
function RoomTransition.ringNameForRoom(ringOrCenter, roomData)
    if type(ringOrCenter) == "number" and roomData and roomData.rings then
        if ringOrCenter == roomData.rings.outer then
            return "outer"
        end
        if roomData.rings.middle ~= nil and ringOrCenter == roomData.rings.middle then
            return "middle"
        end
        if ringOrCenter == roomData.rings.inner then
            return "inner"
        end
    end
    return nil
end

-- Future-Impuls (Phase 2): beim Start der Bewegung reagiert der Future-Ring
-- EINMAL klar (Radius kurzzeitig +roomTransImpulsePx) und klingt sofort ab.
-- Außerhalb des Übergangs 0 (kein Puls während der Transition — nur dieser
-- eine Impuls; das normale Atmen läuft nur außerhalb des Übergangs).
function RoomTransition.futureImpulse(p)
    p = p or RoomTransition.progress()
    if p == nil then
        return 0
    end
    local window = config.roomTransImpulseWindow
    if window <= 0 or p >= window then
        return 0
    end
    return config.roomTransImpulsePx * (1 - p / window)
end

-- Linienbreite des Future-Rings während des Übergangs: der Future-Ring wächst
-- kontinuierlich von der dünnen Future-Linie zur vollen aktiven Bahnbreite
-- (er wird der neue aktive Innenring). Außerhalb des Übergangs = normale
-- Future-Breite.
function RoomTransition.futureWidth(p)
    p = p or RoomTransition.progress() or 0
    local f = smoothstep(math.max(0, math.min(1, p)))
    return config.futureRingLineWidth
        + (config.trackWidth - config.futureRingLineWidth) * f
end

-- Figuren-Skalierung (Player/Baby) während des Übergangs:
--   alte Phase (neuer Raum noch nicht geladen): subtile Größenänderung von
--     maximal roomTransFigureBulge (Anteil) in der Mitte der Bewegung,
--     danach zurück auf 1 — die Figur bleibt mit dem Übergang verbunden.
--   neue Phase: die neue Figur startet bei roomTransFigureScaleMin und wächst
--     bis 1, synchron zum Einrasten des neuen Rings (Landing-Settle).
-- Außerhalb des Übergangs exakt 1.
function RoomTransition.figureScale()
    if not RoomTransition.isActive() then
        return 1
    end
    local p = RoomTransition.progress() or 0
    if not RoomTransition.newRoomLoaded then
        local q = math.max(0, math.min(1, p / config.roomTransRevealPoint))
        return 1 + config.roomTransFigureBulge * math.sin(q * math.pi)
    end
    local s = config.roomTransFigureStart
    local e = config.roomTransFigureEnd
    local f = 0
    if p >= e then
        f = 1
    elseif p > s then
        f = (p - s) / (e - s)
    end
    return config.roomTransFigureScaleMin
        + (1 - config.roomTransFigureScaleMin) * f
end

return RoomTransition
