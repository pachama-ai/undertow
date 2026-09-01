-- Render: finales 1-Bit-Raumrendering (Phase 8.2). Zeichnet den kompletten
-- Raumzustand jeden Frame neu (whole-screen redraw, keine Sprites). KEINE
-- Zustandsänderung an Gameplay: liest ausschließlich State/Room/Camera/Bridge
-- und hält nur rein visuellen UI-State (visualTime, playerFacing). Keine
-- Imports; Module werden zentral in main.lua geladen (Room muss VOR Render
-- geladen sein, da Render Room cached).
--
-- Verbindliche Zeichenreihenfolge (ARCHITECTURE / Phase-8-Plan + Design-Legende):
--   1. gfx.clear(kColorBlack)
--   2. HISTORY: Geisterringe abgeschlossener Räume (1 px, durchgehend, ruhig)
--   3. Kern (Dithermuster, wächst mit Raumnummer, langsame Pulsation)
--   3b. FUTURE: pulsierende gestrichelte Linie des nächsten inneren Rings
--   4. AKTIV: Bahnen (weiß, trackWidth 8, Camera-Radien)
--   5. Blenden (geschlossen: schwarz + 1 px weiße Kontur + Zähne; offen: Endmarken)
--   6. Brücken (aktiv: solide Verbindung; eingefahren: verdichtete Punktspur)
--   7. Kernbrücke / Gate (inner -> Kern, mit Irisspitze)
--   8. Schalter (abgerundetes Rechteck + zwei Kreise)
--   9. Elementmarken (dasselbe Symbol, abgeleitet vom steuernden Schalter)
--  10. Spieler (schwarze Kugel + weiße Pupille)
--
-- Physische Blendendarstellung (Vertrag Phase 6.2): State.elementStates =
-- logischer Sollzustand, Room.shutters = physischer Zustand
-- (collisionActive/pendingClose). pendingClose wird NICHT wie eine Sperre
-- gezeichnet (offene Darstellung mit Endmarken).
--
-- Ringnummern-Konvention: siehe ui/camera.lua (nach innen abnehmend).

Render = {}

local gfx <const> = playdate.graphics
local config <const> = Config
local geo <const> = Geometry
local state <const> = State
local room <const> = Room

local WHITE <const> = gfx.kColorWhite
local BLACK <const> = gfx.kColorBlack

-- --- Rein visueller UI-State (keine Gameplay-Wahrheit) ---------------------
Render.visualTime = 0

-- Spieler-/Augenanimation (Phase 8.4): reiner UI-State, keine zweite
-- Spielerposition (Ring/Winkel kommen nur aus State.player). Die
-- Brückenstreckung wird zur Laufzeit aus Bridge.isCrossing() und
-- Bridge.getTransitProgress() abgeleitet (kein eigener Bridge-Zustand).
Render.playerVisual = nil
-- Injizierbarer Zufallsgenerator [0,1) für das Blinkintervall; nil = math.random.
-- Tests setzen hier eine deterministische Funktion, um Flakes zu vermeiden.
Render.blinkRandom = nil
-- Injizierbarer Zufallsgenerator [0,1) für den Idle-Blick; nil = math.random.
Render.idleLookRandom = nil

-- Wählt das nächste Blinkintervall in [blinkMinInterval, blinkMaxInterval].
-- Nach jedem abgeschlossenen Blink wird NEU gewürfelt (nicht pro Frame).
function Render.pickBlinkInterval()
    local minI = config.blinkMinInterval
    local span = config.blinkMaxInterval - config.blinkMinInterval
    local r = Render.blinkRandom
    if not r then
        r = math.random
    end
    return minI + (r() * span)
end

-- --- Idle-Herumschauen (Player, neugierig/verspielt, NICHT hektisch) -------
-- Nach einer ZUFÄLLIGEN Ruhezeit beginnt ein kurzer Blick in eine ZUFÄLLIGE
-- Richtung (innen/außen/CW/CCW/neutral), wird 0.4-1.0 s gehalten und kehrt
-- sanft zurück; danach neue zufällige Ruhe (1.5-3.5 s). Der Blick ist rein
-- visuell und wird bei echter Bewegung (notePlayerMovement) abgebrochen.
-- Zufallshelfer (deterministisch testbar über Render.idleLookRandom).

-- Zufällige Ruhezeit bis zum nächsten Blick (first = erste Ruhe nach Reset).
function Render.pickIdleLookRest(first)
    local minR, maxR
    if first then
        minR, maxR = config.idleLookFirstRestMin, config.idleLookFirstRestMax
    else
        minR, maxR = config.idleLookRestMin, config.idleLookRestMax
    end
    local r = Render.idleLookRandom
    if not r then
        r = math.random
    end
    return minR + (r() * (maxR - minR))
end

-- Zufällige Haltedauer des Blicks in [idleLookHoldMin, idleLookHoldMax].
function Render.pickIdleLookHold()
    local r = Render.idleLookRandom
    if not r then
        r = math.random
    end
    return config.idleLookHoldMin + (r() * (config.idleLookHoldMax - config.idleLookHoldMin))
end

-- Zufällige Blickrichtung: 1=innen, 2=außen, 3=CW, 4=CCW, 5=neutral.
function Render.pickIdleLookDirection()
    local r = Render.idleLookRandom
    if not r then
        r = math.random
    end
    return math.min(5, math.max(1, math.floor(r() * 5) + 1))
end

-- Einheitsvektor einer Blickrichtung im Bildschirmraum (read-only, rein
-- visuell). Innen/außen hängen von der Figurenposition (Zentrum 200,120) ab,
-- CW/CCW vom Ringwinkel.
function Render.idleLookUnit(x, y, angle, dir)
    if dir == 1 then -- nach innen (zum Ringzentrum)
        local dx, dy = config.centerX - x, config.centerY - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.01 then return 0, 0 end
        return dx / len, dy / len
    elseif dir == 2 then -- nach außen
        local dx, dy = x - config.centerX, y - config.centerY
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.01 then return 0, 0 end
        return dx / len, dy / len
    elseif dir == 3 then -- tangential CW
        local rad = math.rad(angle)
        return math.cos(rad), math.sin(rad)
    elseif dir == 4 then -- tangential CCW
        local rad = math.rad(angle)
        return -math.cos(rad), -math.sin(rad)
    end
    return 0, 0 -- 5: neutral
end

-- Schreibt die Idle-Blick-State-Machine fort (wird nur in ruhiger Szene
-- aufgerufen, siehe Render.update). Zustände: rest -> move -> hold -> return.
-- Die Ruhe-Clock nutzt pv.idleTime (echte Stillstandszeit); move/hold/return
-- laufen über den eigenen Timer und bleiben auch bei einem Blink aktiv.
function Render.updateIdleLook(dt)
    local pv = Render.playerVisual
    if not pv or not pv.idleLook then return end
    local il = pv.idleLook
    il.timer = il.timer + dt
    if il.state == "rest" then
        if pv.idleTime >= il.nextAt then
            il.targetDir = Render.pickIdleLookDirection()
            il.from = il.amount
            il.to = config.idleLookTravel
            il.state = "move"
            il.timer = 0
        end
    elseif il.state == "move" then
        local k = math.min(1, il.timer / config.idleLookMoveTime)
        k = k * k * (3 - 2 * k)
        il.amount = il.from + (il.to - il.from) * k
        if il.timer >= config.idleLookMoveTime then
            il.amount = il.to
            il.holdFor = Render.pickIdleLookHold()
            il.state = "hold"
            il.timer = 0
        end
    elseif il.state == "hold" then
        if il.timer >= il.holdFor then
            il.from = il.amount
            il.to = 0
            il.state = "return"
            il.timer = 0
        end
    elseif il.state == "return" then
        local k = math.min(1, il.timer / config.idleLookReturnTime)
        k = k * k * (3 - 2 * k)
        il.amount = il.from + (il.to - il.from) * k
        if il.timer >= config.idleLookReturnTime then
            il.amount = 0
            il.state = "rest"
            il.timer = 0
            il.nextAt = pv.idleTime + Render.pickIdleLookRest(false)
        end
    end
end

-- --- Baby-Visualzustand (generisch, Raum 2, rein visuell) ------------------
-- Eigener Blink-Timer, Idle-Zeit und Reaktions-Framezähler (Push/Settle/
-- Landing) des Babys. KEIN Gameplay-State (nie in State.snapshot/Save/Levels);
-- wird bei Raumstart, Undo und Raumwechsel über resetBabyVisual neutralisiert.
Render.babyVisual = nil
-- Injizierbarer Zufallsgenerator [0,1) für das Baby-Blinkintervall.
Render.babyBlinkRandom = nil

-- Wählt das nächste Baby-Blinkintervall in [babyBlinkMinInterval,
-- babyBlinkMaxInterval]. Nach jedem abgeschlossenen Blink wird NEU gewürfelt.
function Render.pickBabyBlinkInterval()
    local minI = config.babyBlinkMinInterval
    local span = config.babyBlinkMaxInterval - config.babyBlinkMinInterval
    local r = Render.babyBlinkRandom
    if not r then
        r = math.random
    end
    return minI + (r() * span)
end

-- Setzt den rein visuellen Baby-Zustand auf Neutral (Raumstart, Undo,
-- Raumwechsel). Kein Gameplay-Effekt.
function Render.resetBabyVisual()
    Render.babyVisual = {
        idleTime = 0,
        nextBlinkAt = Render.pickBabyBlinkInterval(),
        blinkFramesRemaining = 0,
        pushFramesRemaining = 0,
        pushDir = 1,
        settleFramesRemaining = 0,
        landingFramesRemaining = 0,
        blockedFramesRemaining = 0,
        wasBlockedLastFrame = false,
        hopT = 0,                 -- Hüpf-Zeitbasis (kontinuierlicher sanfter Bob)
        excitedFrames = 0,        -- freudiger Extra-Hüpfer nach Push/Landing (Frames)
    }
end

-- Setzt den rein visuellen Spielerzustand auf Neutral (Raumstart, Undo,
-- Raumabschluss). Kein Gameplay-Effekt.
function Render.resetPlayerVisual()
    Render.playerVisual = {
        facing = 1,                          -- CW-Standard (kein Zufall)
        idleTime = 0,                        -- Stillstandszeit für Blink/Idle-Blick
        nextBlinkAt = Render.pickBlinkInterval(), -- nächster Blinktermin
        blinkFramesRemaining = 0,
        switchWidenFramesRemaining = 0,
        shutterSquintFramesRemaining = 0,
        pushFramesRemaining = 0,             -- minimaler Druck beim Baby-Push
        landingFramesRemaining = 0,          -- ruhiges Landing nach gemeinsamem Transit
        transitFocusFramesRemaining = 0,     -- Transit-Fokus-Boost (Shared Bridge)
        landingSquintFramesRemaining = 0,    -- Landing-Squint (kurze Lidlinie)
        lookAtBabyFramesRemaining = 0,       -- kurzer Blick zum Baby nach Landing
        wasBlockedLastFrame = false,         -- Flankenerkennung Shutter-Kollision
        -- Idle-Herumschauen: Zufalls-State-Machine (rest -> move -> hold ->
        -- return). amount = aktueller Blickabstand (0..idleLookTravel),
        -- targetDir = Blickrichtung, nextAt = Ruhe-Schwelle (idleTime).
        idleLook = {
            state = "rest",
            timer = 0,
            nextAt = Render.pickIdleLookRest(true),
            amount = 0,
            from = 0,
            to = 0,
            targetDir = 1,
            holdFor = 0,
        },
    }
    -- Press-Animation der Schalter: keine Restzähler in neue Räume tragen.
    Render.switchPressFrames = 0
    -- Baby-Visualzustand (Blink/Idle/Push/Settle/Landing) für Raumstart, Undo,
    -- Restart und Raumwechsel neutralisieren. Rein visuell.
    Render.resetBabyVisual()
    Render.resetObjectAnims()
end

-- --- Transiente Objekt-Mikroanimationen (Atmosphäre, rein visuell) --------
-- Per-Objekt-Zustände für kurze Übergangs-Animationen: Blenden-Überschwinger
-- beim Schließen, Blenden-Einfahren beim Öffnen, Brücken-Stufen-Ausfahren mit
-- 1-px-Nachsetzen und der Raumabschluss-Systemimpuls. Kein Gameplay, kein
-- State, kein Undo-Eingriff. Wird bei jedem Raumstart (resetPlayerVisual) neu
-- initialisiert.
Render.shutterAnims = {}
Render.bridgeAnims = {}
Render.prevShutter = {}
Render.prevBridge = {}
Render.completionPulseT = nil -- Raumabschluss-Systemimpuls (nil = inaktiv)
-- Einmalschalter-Verschwinden (nach dem Verbrauch): transiente Animation.
-- oneShotVanishAnims[id] = { t = 0 } (aktiv), oneShotVanishDone[id] = true
-- (fertig — der Schalter bleibt dauerhaft weg). Rein visuell, kein Gameplay.
Render.oneShotVanishAnims = {}
Render.oneShotVanishDone = {}
-- Spieler-Partikelschweif (rein visuell): { t, angle, baseR } — altert und
-- wird beim Zeichnen als schrumpfende weiße Punkte ausgegeben.
Render.trailParticles = {}
-- Finaler Raum-6-Moment: hält die Welt still (statische Zeitbasis), solange
-- aktiv (rein visuell; unterdrückt auch „ROOM COMPLETE“-Text).
Render.finalMomentActive = false
Render.finalMomentDriftTime = nil

function Render.resetObjectAnims()
    Render.shutterAnims = {}
    Render.bridgeAnims = {}
    Render.prevShutter = {}
    Render.prevBridge = {}
    Render.prevReady = {}
    Render.bridgeReadyFrames = {}
    -- Einmalschalter-Verschwinde-Animation (rein visuell): bei Raumstart,
    -- Undo, Restart und Raumwechsel zurücksetzen — der Schalter erscheint
    -- wieder (falls nicht verbraucht) und startet bei erneutem Verbrauch frisch.
    Render.oneShotVanishAnims = {}
    Render.oneShotVanishDone = {}
    -- Spieler-Partikelschweif (rein visuell): bei Raumstart/Undo/Restart
    -- räumen (keine Partikel aus dem alten Zustand).
    Render.trailParticles = {}
    -- Baby-Dock-Ready-Feedback (rein visuell): Flanke „Transfer bereit“ startet
    -- eine einmalige 1-px-Innenbewegung der vier Eckmarken (2-3 Frames).
    Render.babyDockReadyPrev = {}
    Render.babyDockFeedbackFrames = {}
    -- Player-Dock-Ready-Feedback : gleiche Flanke wie
    -- das Baby-Dock — sobald ein Transfer (Brücke oder Tor) bereit wird,
    -- rückt der offene Rahmen 1 px nach innen (einmalig, 2-3 Frames).
    Render.playerDockReadyPrev = {}
    Render.playerDockFeedbackFrames = {}
    Render.completionPulseT = nil
    Render.finalMomentActive = false
    Render.finalMomentDriftTime = nil
    -- Mittelpunkt-Landung (Kernbrücken-Abschluss): bei Raumstart/Raumwechsel/
    -- Undo zurücksetzen — der Player steht wieder auf seiner normalen Position.
    Render.playerAtCenter = false
end
-- Initialer Raumstart: setzt auch die Objekt-Animationen zurück.
Render.resetPlayerVisual()
Render.resetObjectAnims()

-- --- Reine read-only Visual-Helfer (testbar) ------------------------------

-- Bildschirmradius zum Ringnamen über die Kamera (Phase 8.1): liest die
-- World-Ringnummer aus State.room.rings und bildet sie über Camera.getRadius
-- ab. Dadurch wandern alle Elemente während einer Raumtransition mit.
-- "middle" (Mittelring, Level 4) ist optional — nur Räume mit rings.middle
-- besitzen ihn.
function Render.ringRadius(ringName)
    if ringName ~= "outer" and ringName ~= "middle" and ringName ~= "inner" then
        error("Render.ringRadius: unbekannter Ring '" .. tostring(ringName) .. "'")
    end
    if ringName == "middle" and state.room.rings.middle == nil then
        error("Render.ringRadius: Raum hat keinen Mittelring")
    end
    return Camera.getRadius(state.room.rings[ringName])
end

-- Physischer Blenden-Visualzustand: "closed" | "open" | "pendingClose".
function Render.shutterVisualState(shutterId)
    local phys = room.shutters[shutterId]
    if not phys then
        return "open"
    end
    if phys.collisionActive then
        return "closed"
    end
    if phys.pendingClose then
        return "pendingClose"
    end
    return "open"
end

-- Schalter-Visualzustand: "A" | "B" (aus State.switchStates).
function Render.switchVisualState(switchId)
    return state.switchStates[switchId]
end

-- Read-only Helfer (Tests/Lesbarkeit): welche tangentiale Seite des Schalters
-- ist aktuell aktiv? CW-Seite = Zustand A, CCW-Seite = Zustand B. Rückgabe
-- { cw = bool, ccw = bool }. Rein aus State.switchStates abgeleitet; die
-- tatsächliche Zeichnung (aktiv = gefüllt, inaktiv = Kontur) nutzt dieselbe
-- Zuordnung. Kein Gameplay-Effekt.
function Render.switchSideState(switchId)
    local isA = Render.switchVisualState(switchId) == "A"
    return { cw = isA, ccw = not isA }
end

-- Brücken-/Gate-Visualzustand: "active" | "inactive" (aus State.elementStates).
function Render.bridgeVisualState(elementId)
    if state.elementStates[elementId] == true then
        return "active"
    end
    return "inactive"
end

-- Neue Brücken-Aktivierung (Design-Legende, Dichte statt Wanderung): feste
-- Punktpositionen, nur die DICHTE wächst. Stufen aus p (0..1), read-only und
-- testbar:
--   Stufe 1: 7 Ankerpunkte (Abstand 6 px)
--   Stufe 2: + Mittelpunkte exakt zwischen den Ankern (Abstand 3 px)
--   Stufe 3: volle dichte Achsenpunktlinie (Abstand bridgeGridStep)
--   Stufe 4: + Reihen über/unter der Mittellinie (Breite)
--   Stufe 5 (p=1): durchgehender weißer Brückenkörper
function Render.bridgeDensityStage(p)
    if p >= 1 then return 5 end
    if p >= 0.75 then return 4 end
    if p >= 0.5 then return 3 end
    if p >= 0.25 then return 2 end
    return 1
end

-- Fortschritt der geschlossenen weißen Form (0 vor bridgeSolidStart=1, 1 bei
-- voller Brücke). Die solide Form erscheint erst ganz am Ende der Dichte-
-- Verdichtung (kein Wachstum von den Enden zur Mitte). p=1 muss VOR der
-- Start-Schwelle geprüft werden (bei Start=1.0 sonst 0).
function Render.bridgeSolidProgress(p)
    local start = config.bridgeSolidStart
    if p >= 1 then
        return 1
    end
    if p <= start then
        return 0
    end
    return (p - start) / (1 - start)
end

-- Radial interpolierter Radius für einen Bridge-Transit (linear). Bei einem
-- Kernbrücken-Transit (Gate) ist das Ziel der sichtbare Kernrand ("center")
-- statt eines Rings — exakt dieselbe Transitgeometrie wie bei Ring->Ring.
function Render.transitRadius(progress, fromRing, toRing)
    local fromRadius = Render.ringRadius(fromRing)
    local toRadius
    if toRing == "center" then
        toRadius = Render.coreEdgeRadius()
    else
        toRadius = Render.ringRadius(toRing)
    end
    return fromRadius + (toRadius - fromRadius) * progress
end

-- Sichtbarer Spielerradius: während eines Bridge-Transits aus den
-- Transitdaten, sonst aus State.player.ring (Camera-Radius). Keine zweite
-- persistente Spielerposition. Bridge-Transit und Camera-Transition treten
-- nie gleichzeitig auf (beide sperren Input). Nach einem Kernbrücken-
-- Abschluss (Gate) rendert der Player bis zum Raumwechsel am Kernrand
-- (Player.atCenter, rein visuell — er ist am Mittelpunkt gelandet).
Render.playerAtCenter = false

-- Player ist am Mittelpunkt angekommen (Kernbrücken-Transit abgeschlossen).
-- Rein visuell; wird bei Raumstart/Undo/Raumwechsel zurückgesetzt.
function Render.notePlayerAtCenter()
    Render.playerAtCenter = true
end

function Render.playerRadius()
    if Bridge.isCrossing() then
        local t = Bridge.getTransit()
        local progress = Bridge.getTransitProgress() or 0
        return Render.transitRadius(progress, t.fromRing, t.toRing)
    end
    if Render.playerAtCenter and not RoomTransition.isActive() then
        return Render.coreEdgeRadius()
    end
    return Render.ringRadius(state.player.ring)
end

-- Schreibt die rein visuelle Zeit fort (Main ruft dies einmal pro Frame).
-- Keine Gameplaywirkung; läuft auch während Camera-Transition weiter. Blink-
-- Planung läuft nur im Stillstand und in aktiver Szene (kein Transit, keine
-- Camera-Transition, kein Raumabschluss). roomComplete optional (Tests).
function Render.update(dt, roomComplete)
    Render.visualTime = Render.visualTime + dt
    -- Schalter-Press-Animation: kurzer Frame-Zähler (nur echtes Umschalten).
    if Render.switchPressFrames > 0 then
        Render.switchPressFrames = Render.switchPressFrames - 1
    end
    -- Player-Push-Kompression (Baby-Kontakt): kurzer Frame-Zähler.
    if Render.playerVisual and Render.playerVisual.pushFramesRemaining > 0 then
        Render.playerVisual.pushFramesRemaining = Render.playerVisual.pushFramesRemaining - 1
    end
    if Render.playerVisual and Render.playerVisual.landingFramesRemaining > 0 then
        Render.playerVisual.landingFramesRemaining = Render.playerVisual.landingFramesRemaining - 1
    end
    -- Player-Auge (Shared-Bridge-Transit): Fokus-/Landing-/Blick-Zähler abbauen.
    if Render.playerVisual and Render.playerVisual.transitFocusFramesRemaining > 0 then
        Render.playerVisual.transitFocusFramesRemaining = Render.playerVisual.transitFocusFramesRemaining - 1
    end
    if Render.playerVisual and Render.playerVisual.landingSquintFramesRemaining > 0 then
        Render.playerVisual.landingSquintFramesRemaining = Render.playerVisual.landingSquintFramesRemaining - 1
    end
    if Render.playerVisual and Render.playerVisual.lookAtBabyFramesRemaining > 0 then
        Render.playerVisual.lookAtBabyFramesRemaining = Render.playerVisual.lookAtBabyFramesRemaining - 1
    end
    local pv = Render.playerVisual

    -- Blink-Abschluss erkennen (Zähler lief auf 0): neuen Termin planen.
    local wasBlinking = pv.blinkFramesRemaining > 0
    if pv.blinkFramesRemaining > 0 then pv.blinkFramesRemaining = pv.blinkFramesRemaining - 1 end
    local nowBlinking = pv.blinkFramesRemaining > 0
    if wasBlinking and not nowBlinking then
        pv.nextBlinkAt = pv.idleTime + Render.pickBlinkInterval()
    end

    -- Reaktions-Framezähler abbauen (Widen/Squint).
    if pv.switchWidenFramesRemaining > 0 then pv.switchWidenFramesRemaining = pv.switchWidenFramesRemaining - 1 end
    if pv.shutterSquintFramesRemaining > 0 then pv.shutterSquintFramesRemaining = pv.shutterSquintFramesRemaining - 1 end

    -- Blink-Planung nur im Stillstand, ohne aktive Augenreaktion.
    local animatable = not Bridge.isCrossing() and not Camera.isTransitioning() and not roomComplete
    if animatable then
        local eyeBusy = pv.blinkFramesRemaining > 0 or pv.switchWidenFramesRemaining > 0 or pv.shutterSquintFramesRemaining > 0
        if not eyeBusy then
            pv.idleTime = pv.idleTime + dt
            if pv.nextBlinkAt <= 0 then
                pv.nextBlinkAt = Render.pickBlinkInterval()
            end
            if pv.idleTime >= pv.nextBlinkAt then
                pv.blinkFramesRemaining = config.blinkFrames
            end
        end
        -- Idle-Herumschauen (rein visuell): auch während eines Blinks läuft ein
        -- begonnener Blick weiter; neue Blicke starten erst nach Ruhezeit.
        Render.updateIdleLook(dt)
    end

    -- Objekt-Mikroanimationen + Raumabschluss-Impuls fortschreiben.
    Render.updateObjectAnimations(dt)
    -- Baby-Lebendigkeit (Blink/Idle/Reaktionen) fortschreiben.
    Render.updateBabyVisual(dt)
end

-- Baby-Lebendigkeit (rein visuell): eigener Blink-Timer, Idle-Zeit und Abbau
-- der Reaktions-Framezähler (Push/Settle/Landing). Blink nur in ruhiger Szene
-- (kein Transit, keine höher priorisierte Reaktion). Deterministisch seedbar
-- über Render.babyBlinkRandom.
function Render.updateBabyVisual(dt)
    local bv = Render.babyVisual
    if not bv then
        return
    end
    -- Süßes Hüpfen (kindliches Verhalten): Zeitbasis fortschreiben und den
    -- freudigen Extra-Hüpfer (nach Push/Landing) abbauen.
    bv.hopT = (bv.hopT or 0) + dt
    if bv.excitedFrames and bv.excitedFrames > 0 then
        bv.excitedFrames = bv.excitedFrames - 1
    end
    -- Reaktions-Framezähler abbauen.
    if bv.pushFramesRemaining > 0 then bv.pushFramesRemaining = bv.pushFramesRemaining - 1 end
    if bv.settleFramesRemaining > 0 then bv.settleFramesRemaining = bv.settleFramesRemaining - 1 end
    if bv.landingFramesRemaining > 0 then bv.landingFramesRemaining = bv.landingFramesRemaining - 1 end
    if bv.blockedFramesRemaining > 0 then bv.blockedFramesRemaining = bv.blockedFramesRemaining - 1 end
    -- Blink-Abschluss erkennen: neuen Termin planen.
    local wasBlinking = bv.blinkFramesRemaining > 0
    if bv.blinkFramesRemaining > 0 then bv.blinkFramesRemaining = bv.blinkFramesRemaining - 1 end
    local nowBlinking = bv.blinkFramesRemaining > 0
    if wasBlinking and not nowBlinking then
        bv.nextBlinkAt = bv.idleTime + Render.pickBabyBlinkInterval()
    end
    -- Idle-Zeit nur in ruhiger Szene (kein Transit, keine höher priorisierte
    -- Reaktion); dann auch den nächsten Blink planen.
    local busy = bv.pushFramesRemaining > 0 or bv.settleFramesRemaining > 0
        or bv.landingFramesRemaining > 0 or bv.blockedFramesRemaining > 0 or Baby.isCrossing()
    if not busy then
        if not nowBlinking then
            bv.idleTime = bv.idleTime + dt
            if bv.nextBlinkAt <= 0 then
                bv.nextBlinkAt = Render.pickBabyBlinkInterval()
            end
            if bv.idleTime >= bv.nextBlinkAt then
                bv.blinkFramesRemaining = config.babyBlinkFrames
            end
        end
    end
end

-- Erkennt Zustandswechsel der Elemente und treibt die transiente Animations-
-- Zustände (Blende/Brücke) sowie den Raumabschluss-Impuls fort.
-- Rein visuell; die physischen Zustände (State/ElementStates) bleiben unangetastet.
function Render.updateObjectAnimations(dt)
    -- Blenden: Übergang zwischen closed <-> offen startet die Animation.
    -- prev==nil ist der erste Frame nach Raumstart: nur Zustand merken, kein
    -- Anim (kein Schein-Überschwinger beim Raumwechsel). +1 Frame, weil der
    -- Abbau-Loop denselben Frame durchläuft (Startwert der Zeichnung:
    -- close = voller Überschwinger, open = volle Breite).
    for id, _ in pairs(room.shutters) do
        local cur = Render.shutterVisualState(id)
        local prev = Render.prevShutter[id]
        if prev ~= nil then
            if prev == "closed" and cur ~= "closed" then
                Render.shutterAnims[id] = { kind = "open", frames = 5 }
            elseif cur == "closed" and prev ~= "closed" then
                Render.shutterAnims[id] = { kind = "close", frames = config.shutterOvershootFrames + 1 }
            end
        end
        Render.prevShutter[id] = cur
    end
    -- Brücken/Gates: inactive <-> active startet die Materialisierungs-/
    -- Deaktivierungs-Animation (Design-Legende: Punkte -> Segmente -> Brücke
    -- bzw. rückwärts). prev==nil (erster Frame) erzeugt kein Schein-Ausfahren.
    for id, st in pairs(state.elementStates) do
        local cur = st == true and "active" or "inactive"
        local prev = Render.prevBridge[id]
        if cur == "active" and prev == "inactive" then
            Render.bridgeAnims[id] = { t = 0, p = 0, state = "extending", settleFrames = 0 }
        elseif cur == "inactive" and prev == "active" then
            -- Deaktivierung: rückwärts — volle Brücke -> dichte Punktmasse ->
            -- dichte Mittelachse -> 5-7 Punkte (keine wegfliegenden Partikel).
            local curP = (Render.bridgeAnims[id] and Render.bridgeAnims[id].p) or 1
            Render.bridgeAnims[id] = { t = 0, p = curP, fromP = curP, state = "retracting", settleFrames = 0 }
        end
        Render.prevBridge[id] = cur
    end
    -- Bridge-Ready-Impuls : wird ein
    -- aktives Bridge-Dock angedockt (Spieler in dockRange, kein laufender
    -- Transit/Camera), startet ein kurzer Frame-Impuls (minimal kräftiger +
    -- mechanischer Tick im Anschlussbereich). Kein permanentes Blinken, kein
    -- Gameplay-Effekt — rein visuell.
    for _, b in ipairs(state.room.bridges) do
        local docked = not Bridge.isCrossing() and not Baby.isCrossing() and not Camera.isTransitioning()
            and Render.bridgeVisualState(b.id) == "active"
            and Bridge.isUsable(b, state.player.angle)
        local prev = Render.prevReady[b.id]
        if docked and prev ~= true then
            Render.bridgeReadyFrames[b.id] = config.bridgeReadyFrames
        end
        Render.prevReady[b.id] = docked
    end
    -- Kernbrücke (Gate): identischer Ready-Impuls wie an normalen Brücken —
    -- der Ausgang wird als dockbarer Übergang gefühlt (keine Sonderlogik).
    if state.room.gate then
        local g = state.room.gate
        local gDocked = not Bridge.isCrossing() and not Baby.isCrossing() and not Camera.isTransitioning()
            and Render.bridgeVisualState(g.id) == "active"
            and Gate.isUsable(g, state.player.ring, state.player.angle)
        local gPrev = Render.prevReady[g.id]
        if gDocked and gPrev ~= true then
            Render.bridgeReadyFrames[g.id] = config.bridgeReadyFrames
        end
        Render.prevReady[g.id] = gDocked
    end
    for id, f in pairs(Render.bridgeReadyFrames) do
        if f and f > 0 then
            Render.bridgeReadyFrames[id] = f - 1
        else
            Render.bridgeReadyFrames[id] = nil
        end
    end
    -- Baby-Dock-Ready-Feedback (Referenz, rein visuell): sobald ein Baby-
    -- Transfer an einer Brücke ODER am Tor bereit wird (Baby am Dock, Player
    -- dahinter), eine einmalige 1-px-Innenbewegung der vier Eckmarken
    -- (2-3 Frames). Kein Puls, kein Blinken, kein Ready-Punkt.
    local readyBridge = Baby.findTransferReadyBridge()
    for _, b in ipairs(state.room.bridges) do
        local readyNow = (readyBridge ~= nil and readyBridge.id == b.id)
        local prev = Render.babyDockReadyPrev[b.id]
        if readyNow and prev ~= true then
            Render.babyDockFeedbackFrames[b.id] = config.babyDockReadyFrames
        end
        Render.babyDockReadyPrev[b.id] = readyNow
    end
    -- Tor / Zielausgang: gleiches Ready-Feedback, wenn das gemeinsame
    -- Torübergang-Dock sichtbar wird.
    if state.room.gate then
        local gid = state.room.gate.id
        local gateReady = Render.babyDockForGate()
        local gprev = Render.babyDockReadyPrev[gid]
        if gateReady and gprev ~= true then
            Render.babyDockFeedbackFrames[gid] = config.babyDockReadyFrames
        end
        Render.babyDockReadyPrev[gid] = gateReady
    end
    for id, f in pairs(Render.babyDockFeedbackFrames) do
        if f and f > 0 then
            Render.babyDockFeedbackFrames[id] = f - 1
        else
            Render.babyDockFeedbackFrames[id] = nil
        end
    end
    -- Player-Dock-Ready-Feedback : identische Ready-Flanken wie das
    -- Baby-Dock (Brücke bereit / Gate bereit) — der offene Rahmen rückt
    -- einmalig 1 px nach innen. Rein visuell, kein Gameplay-Effekt.
    for _, b in ipairs(state.room.bridges) do
        local readyNow = (readyBridge ~= nil and readyBridge.id == b.id)
        local pprev = Render.playerDockReadyPrev[b.id]
        if readyNow and pprev ~= true then
            Render.playerDockFeedbackFrames[b.id] = config.babyDockReadyFrames
        end
        Render.playerDockReadyPrev[b.id] = readyNow
    end
    if state.room.gate then
        local gid = state.room.gate.id
        local gateReady = Render.babyDockForGate()
        local gprev = Render.playerDockReadyPrev[gid]
        if gateReady and gprev ~= true then
            Render.playerDockFeedbackFrames[gid] = config.babyDockReadyFrames
        end
        Render.playerDockReadyPrev[gid] = gateReady
    end
    for id, f in pairs(Render.playerDockFeedbackFrames) do
        if f and f > 0 then
            Render.playerDockFeedbackFrames[id] = f - 1
        else
            Render.playerDockFeedbackFrames[id] = nil
        end
    end
    -- Blenden-Framezähler abbauen.
    for id, a in pairs(Render.shutterAnims) do
        a.frames = a.frames - 1
        if a.frames <= 0 then
            Render.shutterAnims[id] = nil
        end
    end
    -- Brücken-Fortschritt (dt-basiert): einfache, schnelle Dichte-Verdichtung.
    -- extending: p linear 0->1 über config.bridgeExtendDuration, danach
    -- 1-px-Nachsetzen (config.bridgeSettleFrames). retracting: exakt rückwärts
    -- 1->0. Keine Phasen-/Stufen-Maschine mehr, keine Punktwanderung.
    for id, a in pairs(Render.bridgeAnims) do
        if a.state == "extending" then
            a.t = a.t + dt
            local dur = config.bridgeExtendDuration
            if dur > 0 and a.t < dur then
                a.p = a.t / dur
            else
                a.p = 1
                a.state = "settle"
                a.settleFrames = config.bridgeSettleFrames
            end
        elseif a.state == "retracting" then
            a.t = a.t + dt
            local dur = config.bridgeExtendDuration
            if dur > 0 and a.t < dur then
                a.p = (a.fromP or 1) * (1 - a.t / dur)
            else
                a.p = 0
                Render.bridgeAnims[id] = nil
            end
        elseif a.state == "settle" then
            a.settleFrames = a.settleFrames - 1
            if a.settleFrames <= 0 then
                Render.bridgeAnims[id] = nil
            end
        end
    end
    -- Raumabschluss-Impuls: läuft einmal durch und verschwindet.
    if Render.completionPulseT ~= nil then
        Render.completionPulseT = Render.completionPulseT + dt
        if Render.completionPulseT > config.completionPulseDuration then
            Render.completionPulseT = nil
        end
    end
    -- Einmalschalter-Verschwinden: Animation fortschreiben; abgeschlossene
    -- entfernen (der Schalter bleibt danach dauerhaft verschwunden).
    for id, a in pairs(Render.oneShotVanishAnims) do
        a.t = a.t + dt
        if a.t >= config.oneShotSwitchVanishDuration then
            Render.oneShotVanishAnims[id] = nil
            Render.oneShotVanishDone[id] = true
        end
    end
    -- Spieler-Partikelschweif: Partikel altern; abgelaufene entfernen.
    for i = #Render.trailParticles, 1, -1 do
        Render.trailParticles[i].t = Render.trailParticles[i].t + dt
        if Render.trailParticles[i].t >= (config.playerTrailLife or 0.3) then
            table.remove(Render.trailParticles, i)
        end
    end
end

-- Merkt die letzte tatsächliche Bewegungsrichtung (actualDelta, nicht
-- wantedDelta: Kollision kann Bewegung verhindern). Nur echte Spielerbewegung
-- ändert das Facing; DockAssist-Snaps ändern es nicht. Echte Bewegung
-- unterbricht die Blink-Idle: Timer zurücksetzen, geplanten Blink neu termi-
-- nieren und laufenden Blink abbrechen.
function Render.notePlayerMovement(actualDelta)
    local pv = Render.playerVisual
    if actualDelta > 0 then
        pv.facing = 1
    elseif actualDelta < 0 then
        pv.facing = -1
    end
    if actualDelta ~= 0 then
        pv.idleTime = 0
        pv.nextBlinkAt = Render.pickBlinkInterval()
        pv.blinkFramesRemaining = 0
        -- Idle-Blick abbrechen: Auge orientiert sich wieder in Bewegungsrichtung.
        if pv.idleLook then
            pv.idleLook.state = "rest"
            pv.idleLook.timer = 0
            pv.idleLook.amount = 0
            pv.idleLook.nextAt = Render.pickIdleLookRest(true)
        end
        -- Baby-Idle: Bewegung des Players beendet die gemeinsame Ruhephase.
        if Render.babyVisual then
            Render.babyVisual.idleTime = 0
        end
        -- Partikelschweif: beim echten Bewegen kleine weiße Partikel spawne.
        Render.spawnTrailParticles(actualDelta)
    end
end

-- Partikelschweif :
-- beim echten Bewegen spawnt der Player kleine SCHWARZE Partikel exakt auf
-- seiner Ringbahn (baseR = Bahnradius, kein Versatz, keine Drift), leicht
-- hinter ihm in Bewegungsrichtung. Sie schrumpfen über die Lebensdauer.
-- Auf weißer Bahn entsteht so ein dezenter dunkler Bewegungsschweif.
-- Obergrenze gegen Ansammlung. Rein visuell.
function Render.spawnTrailParticles(direction)
    local radius = Render.playerRadius()
    local angle = state.player.angle
    local dir = (direction and direction >= 0) and 1 or -1
    local count = config.playerTrailSpawn or 2
    local max = config.playerTrailMax or 40
    local off = config.playerTrailOffset or 5
    for i = 1, count do
        -- Partikel leicht HINTER dem Player (in Bewegungsrichtung zurück).
        local a = geo.norm(angle - dir * (i * 2))
        Render.trailParticles[#Render.trailParticles + 1] = {
            t = 0, angle = a, baseR = radius + off,
        }
    end
    -- Obergrenze: älteste Partikel verwerfen.
    while #Render.trailParticles > max do
        table.remove(Render.trailParticles, 1)
    end
end

-- Schalterkontakt: echter erfolgreicher Trigger durch Vorwärtsbewegung
-- (Room.movePlayer liefert switchChanges>0). Weitet das Auge kurz und drückt
-- den Schalter für 2 Frames ein (mechanisches Klack). Priorität über Blink,
-- unter Squint. Rein visuell, kein Gameplay-Effekt.
function Render.noteSwitchContact()
    local pv = Render.playerVisual
    if pv.shutterSquintFramesRemaining <= 0
        and not Bridge.isCrossing()
        and not Camera.isTransitioning() then
        pv.switchWidenFramesRemaining = config.switchEyeWidenFrames
        pv.blinkFramesRemaining = 0
        pv.idleTime = 0
        pv.nextBlinkAt = Render.pickBlinkInterval()
        -- Press-Animation nur bei ECHTEM Umschalten (dieser Hook feuert nur
        -- bei switchChanges>0): 2-Frame-Zähler für die eingedrückte Darstellung.
        Render.switchPressFrames = config.switchPressFrames
    end
end

-- Baby-Push (generisch, Raum 2): kurze 1-px-Kompression in Fahrtrichtung +
-- leichter Innenkreis-Versatz in Bewegungsrichtung beim echten Schieben
-- (Room.movePlayer -> result.babyMoved). direction: tatsächliche Bewegungs-
-- richtung (+1 CW, -1 CCW). Unterbricht Blink/Idle/Blocked. Rein visuell,
-- kein Gameplay-Effekt.
function Render.noteBabyPush(direction)
    local bv = Render.babyVisual
    if not bv then
        return
    end
    bv.pushFramesRemaining = config.babyPushFrames
    bv.pushDir = (direction and direction >= 0) and 1 or -1
    bv.blockedFramesRemaining = 0
    bv.wasBlockedLastFrame = false
    bv.blinkFramesRemaining = 0
    bv.idleTime = 0
    bv.nextBlinkAt = Render.pickBabyBlinkInterval()
    -- Süßes Verhalten: freudiger Extra-Hüpfer beim Schieben.
    bv.excitedFrames = config.babyExcitedFrames
end

-- Baby-Blocked (generisch, Raum 2): wenn das Baby tatsächlich gegen eine
-- Blockade (geschlossene Blende) gedrückt wird, sehr kurze Reaktion —
-- Innenkreis wird kurz zur Squint-Linie + minimale 1-px-Kompression.
-- Schwächer als die Player-Reaktion. Flankenerkennung (wie noteShutterBlocked):
-- nur ein NEUER Blockadestoß startet die Reaktion; gehaltenes Drücken gegen
-- dieselbe Blockade retriggert nicht. Rein visuell, kein Gameplay-Effekt.
function Render.noteBabyBlocked(blocked)
    local bv = Render.babyVisual
    if not bv then
        return
    end
    if blocked then
        if not bv.wasBlockedLastFrame then
            bv.blockedFramesRemaining = config.babyBlockedFrames
            bv.pushFramesRemaining = 0
            bv.blinkFramesRemaining = 0
            bv.idleTime = 0
            bv.nextBlinkAt = Render.pickBabyBlinkInterval()
        end
        bv.wasBlockedLastFrame = true
    else
        bv.wasBlockedLastFrame = false
    end
end

-- Player-Push-Kontakt (generisch, Raum 2): beim echten Schieben des Babys
-- zeigt der Player minimal Druck (1 px radiale Kompression) und behält einen
-- kurzen fokussierten Blick. Rein visuell, kein Gameplay-Effekt.
function Render.notePlayerPushContact()
    local pv = Render.playerVisual
    if not pv then
        return
    end
    pv.pushFramesRemaining = config.babyPushFrames
end

-- Player-Transit-Fokus beim Start des GEMEINSAMEN Brückentransits: wenige
-- Frames eine kleine Fokus-Reaktion (Pupille minimal größer + stärker radial
-- zur Brücke). Nur eine kleine Reaktion, keine Cartoon-Animation; der Blink
-- wird unterdrückt (Transit-Priorität). Rein visuell, kein Gameplay-Effekt.
function Render.notePlayerTransitStart()
    local pv = Render.playerVisual
    if not pv then
        return
    end
    pv.transitFocusFramesRemaining = config.transitFocusFrames
    pv.blinkFramesRemaining = 0
    pv.switchWidenFramesRemaining = 0
    pv.shutterSquintFramesRemaining = 0
    pv.idleTime = 0
    pv.nextBlinkAt = Render.pickBlinkInterval()
end

-- Player-Landing nach dem GEMEINSAMEN Brückentransit (Player+Baby): ruhiges,
-- kleines Setzen (1 px radiale Kompression, nur wenige Frames) — bewusst
-- subtiler als die Babyreaktion, damit das Baby die Szene „erzählt“. Das Auge
-- BLEIBT sichtbar (normale Pupille) und blickt danach für kurze Zeit zum Baby
-- (gemeinsam angekommen) — kein Lidlinien-Squint, der das Auge versteckt.
-- Rein visuell, kein Gameplay-Effekt.
function Render.notePlayerLanding()
    local pv = Render.playerVisual
    if not pv then
        return
    end
    pv.landingFramesRemaining = 3
    pv.landingSquintFramesRemaining = config.landingSquintFrames
    pv.lookAtBabyFramesRemaining = config.lookAtBabyFrames
    pv.transitFocusFramesRemaining = 0
    pv.blinkFramesRemaining = 0
    pv.switchWidenFramesRemaining = 0
    pv.shutterSquintFramesRemaining = 0
    pv.idleTime = 0
    pv.nextBlinkAt = Render.pickBlinkInterval()
end

-- Baby-Landing nach dem Brückentransit (generisch): kleiner Settling-Impuls,
-- damit die Ankunft auf dem anderen Ring sichtbar ist.
function Render.noteBabyLanding()
    local bv = Render.babyVisual
    if not bv then
        return
    end
    bv.landingFramesRemaining = config.babyLandingFrames
    bv.blinkFramesRemaining = 0
    bv.pushFramesRemaining = 0
    bv.idleTime = 0
    bv.nextBlinkAt = Render.pickBabyBlinkInterval()
    -- Süßes Verhalten: freudiger Extra-Hüpfer nach der Landung.
    bv.excitedFrames = config.babyExcitedFrames
end

-- Aktuelle Baby-Reaktion nach Priorität (rein visuell):
--   transit > settle > landing > bridge-ready > push > blocked > blink > normal.
-- Hängt von Render.babyVisual und der read-only Transfer-Bereitschaft ab.
-- Höher priorisierte Reaktionen pausieren/überschreiben niedrigere.
function Render.babyEyeState()
    local bv = Render.babyVisual or {}
    if Render.babyIsTransiting() then return "transit" end
    if bv.settleFramesRemaining and bv.settleFramesRemaining > 0 then return "settle" end
    if bv.landingFramesRemaining and bv.landingFramesRemaining > 0 then return "landing" end
    if Render.babyBridgeReady() then return "bridge" end
    if bv.pushFramesRemaining and bv.pushFramesRemaining > 0 then return "push" end
    if bv.blockedFramesRemaining and bv.blockedFramesRemaining > 0 then return "blocked" end
    if bv.blinkFramesRemaining and bv.blinkFramesRemaining > 0 then return "blink" end
    return "normal"
end

-- Read-only: ist gerade ein Baby-Brückentransfer bereit (Baby am aktiven
-- Bridge-Dock, Player dahinter)? Reine UI-Query, kein Gameplay-Effekt.
function Render.babyBridgeReady()
    return Baby.findTransferReadyBridge() ~= nil
end

-- Baby-Dock-Sichtbarkeit (kontextuell, read-only): das Dock aus vier
-- L-förmigen Eckmarken erscheint NUR, wenn die konkrete Brücke für die
-- aktuelle Situation relevant ist —
--   * Baby vorhanden, auf demselben Ring wie der Player (Shared Transit
--     grundsätzlich möglich),
--   * Brücke aktiv,
--   * Player UND Baby in sinnvoller Nähe zur Brückenachse
--     (babyDockProximityRange),
--   * kein laufender Transit / keine Kamera-Transition.
-- NICHT: „Baby irgendwo auf demselben Ring → Dock erscheint sofort“.
function Render.babyDockForBridge(b)
    local baby = state.baby
    if not baby then
        return false
    end
    if baby.ring ~= state.player.ring then
        return false
    end
    if state.elementStates[b.id] ~= true then
        return false
    end
    if Bridge.isCrossing() or Baby.isCrossing() or Camera.isTransitioning() then
        return false
    end
    local range = config.babyDockProximityRange
    if math.abs(geo.delta(state.player.angle, b.angle)) > range then
        return false
    end
    if math.abs(geo.delta(baby.angle, b.angle)) > range then
        return false
    end
    return true
end

-- Baby-Dock-Sichtbarkeit am TOR/Zielausgang: dieselbe Regel wie an normalen
-- Brücken — Baby vorhanden und auf dem Tor-Ring, Tor AKTIV (ausgefahren),
-- Player UND Baby in sinnvoller Nähe zur Torachse, kein laufender Transit /
-- keine Kamera-Transition. Rein visuell (renderer-level), kein Gameplay-Effekt.
function Render.babyDockForGate()
    local g = state.room.gate
    local baby = state.baby
    if not g or not baby then
        return false
    end
    local gateRing = g.ring or "inner"
    if baby.ring ~= gateRing or state.player.ring ~= gateRing then
        return false
    end
    if state.elementStates[g.id] ~= true then
        return false
    end
    if Bridge.isCrossing() or Baby.isCrossing() or Camera.isTransitioning() then
        return false
    end
    local range = config.babyDockProximityRange
    if math.abs(geo.delta(state.player.angle, g.angle)) > range then
        return false
    end
    if math.abs(geo.delta(baby.angle, g.angle)) > range then
        return false
    end
    return true
end

-- Winkel der gemeinsamen Dockformation (Player direkt hinter dem Baby) zu
-- einer Achse (Brücke oder Tor): Abstand aus den Figurenradien abgeleitet, in
-- der bisherigen Schieberichtung. Rein visuell, kein Gameplay. nil nur, wenn
-- kein Baby vorhanden ist.
function Render.sharedFormationAngle(axisAngle)
    local gapDeg = config.sharedFormationGapDeg
        or (config.playerRadius + config.babyRadius + 2) / config.innerRadius * (180 / math.pi)
    local dir = (state.baby and state.baby.lastPushDirection) or 1
    return geo.norm(axisAngle - dir * gapDeg)
end

-- Player-Dock-Sichtbarkeit an einer Brücke : das Player-Dock zeigt
-- NUR die GEMEINSAME Dockformation — wo der Player hinter dem Baby stehen
-- muss, damit der gemeinsame Brückentransit möglich ist (das Baby-Dock zeigt
-- die Babyposition). Im Solo-Fall gibt es KEIN Player-Dock: an der Brücken-
-- achse wäre eine Markierung auf der weißen Brücke unsichtbar, und die aktive
-- Brücke selbst + die Bridge-Silhouette zeigen den Weg. Kein laufender
-- Transit / keine Kamera-Transition. Rückgabe: Winkel der Player-Dockposition
-- (Grad) oder nil. Rein visuell, kein Gameplay-Effekt.
function Render.playerDockForBridge(b)
    if Bridge.isCrossing() or Baby.isCrossing() or Camera.isTransitioning() then
        return nil
    end
    if not Render.babyDockForBridge(b) then
        return nil
    end
    return Render.sharedFormationAngle(b.angle)
end

-- Player-Dock am TOR/Zielausgang : nur im Shared-Kontext (das Baby-
-- Dock am Tor ist sichtbar) — dann an der Formation direkt hinter dem Baby.
-- Ein Solo-Dock am Tor gibt es nicht (der Ausgang verlangt immer das Baby).
function Render.playerDockForGate()
    local g = state.room.gate
    if not g then
        return nil
    end
    if Bridge.isCrossing() or Baby.isCrossing() or Camera.isTransitioning() then
        return nil
    end
    if state.elementStates[g.id] ~= true then
        return nil
    end
    if Render.babyDockForGate() then
        return Render.sharedFormationAngle(g.angle)
    end
    return nil
end

-- Bridge-Silhouetten-Sichtbarkeit : die Geistumrisse erscheinen NUR,
-- wenn der Player im Wechsel-Radius der Brücke steht (Bridge.isUsable ->
-- aktive Brücke + innerhalb dockRange) — also genau dann, wenn er tatsächlich
-- wechseln kann. GEMEINSAM (Baby-Dock sichtbar): Player + Baby; SOLO: nur
-- Player. Kein laufender Transit / keine Kamera-Transition. Rein visuell.
function Render.bridgeGhostMode(b)
    if Bridge.isCrossing() or Baby.isCrossing() or Camera.isTransitioning() then
        return nil
    end
    if not Bridge.isUsable(b, state.player.angle) then
        return nil
    end
    if Render.babyDockForBridge(b) then
        return "shared"
    end
    return "player"
end

-- Raumabschluss-Systemimpuls (Atmosphäre): setzt einen kurzen Timer, während
-- dessen drawRoom einen hellen, nach außen laufenden Impuls zeichnet. Wird vom
-- Main im roomComplete-Pfad der Räume 1-5 und beim finalen Raum-6-Moment
-- aufgerufen. Rein visuell; Progression/Timing bleiben unverändert.
function Render.noteRoomComplete()
    Render.completionPulseT = 0
end

-- Finaler Raum-6-Moment (Pass 2): die sichtbare Welt hält kurz inne. Friert die
-- Ghost-Drift ein (zum ersten Mal wird alles still) und zeigt den Systemimpuls.
-- Kein Gameplay-Effekt; endFinalMoment hebt den Zustand wieder auf.
function Render.beginFinalMoment()
    Render.finalMomentActive = true
    Render.finalMomentDriftTime = Render.visualTime
    Render.completionPulseT = 0
end

function Render.endFinalMoment()
    Render.finalMomentActive = false
    Render.finalMomentDriftTime = nil
end

-- Shutter-Kollision: echter blockierter Anstoß (Room.movePlayer -> blocked).
-- Flankenerkennung: nur ein neuer Kollisionsimpuls (false->true) startet das
-- exakt 6-Frame-Zusammenkneifen; gehaltenes Anstoßen verlängert es nicht.
function Render.noteShutterBlocked(blocked)
    local pv = Render.playerVisual
    if blocked then
        if not pv.wasBlockedLastFrame then
            pv.shutterSquintFramesRemaining = config.shutterSquintFrames
            pv.blinkFramesRemaining = 0
            pv.switchWidenFramesRemaining = 0
            pv.idleTime = 0
            pv.nextBlinkAt = Render.pickBlinkInterval()
        end
        pv.wasBlockedLastFrame = true
    else
        pv.wasBlockedLastFrame = false
    end
end

-- Undo: keine neue Reaktion; vorhandene Squint/Widen/Blink auf neutral setzen,
-- damit kein alter Feedbackzustand in den restaurierten State hineinragt.
-- Außerdem werden die transienten Objekt-Animationen (Blende/Brücke, System-
-- impuls) abgeräumt (Pass 2, §52): keine hängenden Anims aus dem alten Zustand.
function Render.noteUndo()
    local pv = Render.playerVisual
    pv.blinkFramesRemaining = 0
    pv.switchWidenFramesRemaining = 0
    pv.shutterSquintFramesRemaining = 0
    pv.transitFocusFramesRemaining = 0
    pv.landingSquintFramesRemaining = 0
    pv.lookAtBabyFramesRemaining = 0
    pv.wasBlockedLastFrame = false
    pv.idleTime = 0
    pv.nextBlinkAt = Render.pickBlinkInterval()
    Render.resetObjectAnims()
    -- Baby-Visualzustand sauber zurücksetzen (keine hängende Reaktion nach Undo).
    Render.resetBabyVisual()
end

-- Aktuelle Augenreaktion nach Priorität (Pass „Player-Eye“):
--   Shared Bridge Transit > Landing Impact > Squint > Widen > Blink > normal.
-- Während eines GEMEINSAMEN Transits gewinnt der Transit-Fokus (Blink kann
-- nicht dazwischenfunken); direkt nach der Landung der kurze Landing-Squint.
-- Rein visuell, kein Gameplay-Effekt.
function Render.currentEyeReaction()
    local pv = Render.playerVisual
    local bt = Bridge.getTransit()
    if bt and bt.active and bt.shared then return "transit" end
    if pv.landingSquintFramesRemaining > 0 then return "landing" end
    if pv.shutterSquintFramesRemaining > 0 then return "squint" end
    if pv.switchWidenFramesRemaining > 0 then return "widen" end
    if pv.blinkFramesRemaining > 0 then return "blink" end
    return "normal"
end

-- Radiale Körperstreckung bei Bridge-Transit: sin(pi*progress)*amount,
-- damit Start/Ende Kreis und Mitte maximale Streckung ergeben.
function Render.bridgeStretch(progress)
    return math.sin(math.pi * (progress or 0)) * config.bridgeStretchAmount
end

-- Achsenvektoren des Körpers für eine Ellipsenstreckung: radial nach außen
-- (ax,ay) und tangential CW (bx,by). 0° -> radial vertikal, 90° -> radial
-- horizontal (Winkelkonvention 0° = 12 Uhr, CW positiv).
function Render.bodyAxisVectors(angle)
    local rad = math.rad(angle)
    return math.sin(rad), -math.cos(rad), math.cos(rad), math.sin(rad)
end

-- Aktuelle Augenposition (read-only): tangential in Facing-Richtung von der
-- Spielermitte versetzt. Wird von drawPlayer und Tests genutzt.
-- Bildschirmposition der Spielerfigur (Mittelpunkt, für Körper UND Hold-Ring).
-- Gleiche Berechnung wie drawPlayer: normaler Ring -> Render.playerRadius() +
-- State.player.angle; bei Bridge-Transit -> Transit-Winkel (Körper wandert
-- radial). Damit liegt der Restart-Ring exakt um die sichtbare Figur.
-- Gemeinsamer Transit — SHARED BRIDGE PATH FIX: räumlich getrennte Phasen.
--   Phase A  [0, hold]        Alignment auf dem RING: Player gleitet in die
--                             Dockformation hinter dem Baby (Winkel ändert
--                             sich, Radius bleibt Ringradius).
--   Phase A2 [hold, hold+babyLead] Baby beginnt radial; Player gleitet
--                             tangential auf die Bridge-Achse (Radius bleibt
--                             noch Ringradius).
--   Phase B  [hold+babyLead, total] Crossing: Winkel = Bridge-Achse (KONSTANT),
--                             nur der Radius wandert (via getTransitProgress).
-- Niemals ändern sich Winkel und Radius gleichzeitig während der Überquerung.
function Render.sharedPlayerAngle()
    local bt = Bridge.getTransit()
    if not (bt and bt.active and bt.shared and bt.playerStartAngle) then
        return nil
    end
    local elapsed = bt.elapsed or 0
    local hold = bt.hold or 0
    local lead = bt.babyLead or 0
    local form = bt.formationAngle or bt.angle
    -- Phase A: Alignment auf dem Ring (Radius = Ringradius).
    if elapsed < hold then
        local p = math.min(1, math.max(0, elapsed / hold))
        local d = geo.delta(bt.playerStartAngle, form)
        return geo.norm(bt.playerStartAngle + d * p)
    end
    -- Baby beginnt radial, der Player gleitet tangential auf die Achse
    -- (Radius bleibt noch der Ringradius — keine Diagonale).
    if elapsed < hold + lead then
        if lead <= 0 then
            return bt.angle
        end
        local q = math.min(1, math.max(0, (elapsed - hold) / lead))
        local d = geo.delta(form, bt.angle)
        return geo.norm(form + d * q)
    end
    -- Phase B: Crossing — Winkel = Bridge-Achse (KONSTANT), nur der Radius
    -- wandert. Keine Winkelinterpolation in dieser Phase.
    return bt.angle
end

-- Baby-Winkel während eines GEMEINSAMEN Transits — SHARED BRIDGE PATH FIX:
--   Phase A  [0, hold]        Alignment auf dem Ring: Baby gleitet tangential
--                             auf die Bridge-Achse (Radius = Ringradius).
--   Phase B  [hold, ...]      Crossing: Winkel = Bridge-Achse (KONSTANT),
--                             nur der Radius wandert.
-- nil außerhalb des gemeinsamen Transits.
function Render.sharedBabyAngle()
    local bt = Bridge.getTransit()
    if not (bt and bt.active and bt.shared and bt.babyStartAngle) then
        return nil
    end
    local hold = bt.hold or 0
    local elapsed = bt.elapsed or 0
    if elapsed < hold then
        -- Phase A: Alignment auf der Bridge-Achse (Radius bleibt Ringradius).
        local p = math.min(1, math.max(0, elapsed / hold))
        local d = geo.delta(bt.babyStartAngle, bt.angle)
        return geo.norm(bt.babyStartAngle + d * p)
    end
    -- Phase B: Crossing — Winkel = Bridge-Achse (KONSTANT).
    return bt.angle
end

-- Winkel der gemeinsamen Dockformation im READY-Zustand (Shared-Transfer
-- bereit, A noch nicht gedrückt): das Baby sitzt an der Brückenachse, der
-- Player wird direkt dahinter auf die Formation ausgerichtet — Abstand aus den
-- Figurenradien abgeleitet, in der bisherigen Schieberichtung. Rein visuell,
-- kein Gameplay. nil, wenn kein Transfer bereit ist.
function Render.sharedReadyPlayerAngle()
    local tb = Baby.findTransferReadyBridge()
    if not tb then
        return nil
    end
    return Render.sharedFormationAngle(tb.angle)
end

function Render.playerScreenPosition()
    -- Level-7-Spezialübergang (neue Phase): Player kommt am Ende gemeinsam
    -- mit dem Baby radial aus dem neuen Kern heraus (eigener Winkel).
    local pX, pY, pA
    if Phase7 ~= nil and Phase7.playerPosAndAngle ~= nil then
        pX, pY, pA = Phase7.playerPosAndAngle()
    end
    if pX then
        return pX, pY, pA
    end
    -- Center-Wipe (Raumwechsel): Player kommt am Ende gemeinsam mit dem Baby
    -- aus dem Mittelpunkt heraus (radial, eigener Winkel, kein Wandern).
    local wX, wY, wA
    if Wipe ~= nil and Wipe.playerPosAndAngle ~= nil then
        wX, wY, wA = Wipe.playerPosAndAngle()
    end
    if wX then
        return wX, wY, wA
    end
    -- Radialer Raumwechsel: Player bleibt die komplette Transition sichtbar
    -- und wird kontinuierlich von der alten zur neuen Startposition geführt
    -- (kein Verschwinden, kein harter Sprung). Außerhalb der Transition nil.
    local rtX, rtY, rtAngle = RoomTransition.playerPosAndAngle()
    if rtX then
        return rtX, rtY, rtAngle
    end
    local radius = Render.playerRadius()
    local angle = state.player.angle
    local sharedAngle = Render.sharedPlayerAngle()
    if sharedAngle then
        angle = sharedAngle
    elseif not Bridge.isCrossing() and not Baby.isCrossing() then
        -- Ready-Formation nur OHNE laufenden Transit: während einer Überquerung
        -- (solo oder gemeinsam) gilt immer die reale Achs-/Babyposition.
        local readyAngle = Render.sharedReadyPlayerAngle()
        if readyAngle then
            angle = readyAngle
        end
    elseif Bridge.isCrossing() then
        angle = Bridge.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    return x, y, angle
end

-- Baby-Transit-Fortschritt (0..1) während eines Transits (gemeinsam oder
-- Baby-solo), sonst nil. Read-only für das Rendering.
function Render.babyTransitProgress()
    local bt = Bridge.getTransit()
    if bt and bt.active and bt.shared then
        return Bridge.getBabyTransitProgress()
    end
    if Baby.isCrossing() then
        return Baby.getTransitProgress()
    end
    return nil
end

-- Befindet sich das Baby gerade in einem Brückentransit (gemeinsam oder solo)?
function Render.babyIsTransiting()
    return Render.babyTransitProgress() ~= nil
end

-- Bildschirmradius des Babys (generisch, Raum 2): während eines Transits
-- (gemeinsam oder solo) radial interpoliert, sonst Camera-Radius des
-- Babyrings. nil, wenn der Raum kein Baby hat.
function Render.babyRadius()
    local bt = Bridge.getTransit()
    if bt and bt.active and bt.shared then
        local progress = Bridge.getBabyTransitProgress() or 0
        return Render.transitRadius(progress, bt.fromRing, bt.toRing)
    end
    if Baby.isCrossing() then
        local t = Baby.getTransit()
        local progress = Baby.getTransitProgress() or 0
        return Render.transitRadius(progress, t.fromRing, t.toRing)
    end
    if state.baby then
        return Render.ringRadius(state.baby.ring)
    end
    return nil
end

-- Bildschirmposition des Babys (Mittelpunkt). nil, wenn kein Baby vorhanden.
-- Während eines gemeinsamen Transits auf der Brückenachse (Player-Follow) mit
-- sanftem Austritt in die Landeposition im letzten Wegviertel (kein Sprung).
function Render.babyScreenPosition()
    local radius = Render.babyRadius()
    if not radius then
        return nil
    end
    local angle = state.baby.angle
    local bt = Bridge.getTransit()
    if bt and bt.active and bt.shared then
        local progress = Bridge.getBabyTransitProgress() or 0
        -- Phase A+B: Baby auf der Bridge-Achse (Winkel konstant während der
        -- radialen Überquerung — SHARED BRIDGE PATH FIX).
        angle = Render.sharedBabyAngle() or bt.angle
        -- Phase C (Landing): erst wenn das Baby RADIAL auf dem Zielring
        -- angekommen ist (progress >= 1), gleitet es TANGENTIAL auf seine
        -- Austrittsposition — der Winkel ändert sich, der Radius ist bereits
        -- der Zielring. Keine gleichzeitige Winkel- und Radialinterpolation.
        if progress >= 1 then
            local landStart = (bt.hold or 0) + (bt.babyDuration or 0)
            local landEnd = (bt.hold or 0) + (bt.babyLead or 0) + (bt.playerDuration or 0)
            local span = landEnd - landStart
            if span > 0 then
                local k = math.min(1, math.max(0, ((bt.elapsed or 0) - landStart) / span))
                local dir = (state.baby and state.baby.lastPushDirection) or 1
                local exitAngle = geo.norm(bt.angle + dir * config.babyBridgeExitOffset)
                angle = geo.norm(bt.angle + geo.delta(bt.angle, exitAngle) * k)
            end
        end
    elseif Baby.isCrossing() then
        angle = Baby.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    return x, y, angle
end

-- Pupillen-Nachlauf (normierter Wert in [-1,1]): rein visuell, kein
-- Gameplay-Einfluss. Ohne geladenes Motion-Modul (Fallback) basiert die
-- Pupille auf playerVisual.facing (1:1 der alte Look, nur mit pupilTravel).
function Render.pupilLagOffset()
    if Motion == nil or Motion.getLag == nil then
        return Render.playerVisual.facing or 0
    end
    local lag = Motion.getLag() or 0
    local maxLag = config.motionMaxPxPerFrame or 3
    local n = lag / maxLag
    if n > 1 then n = 1 elseif n < -1 then n = -1 end
    return n
end

function Render.playerEyePosition()
    local pv = Render.playerVisual
    -- Level-7-Spezialübergang (neue Phase): Auge folgt dem Körper (gleiche
    -- interpolierte Position wie playerScreenPosition).
    local pX, pY, pA
    if Phase7 ~= nil and Phase7.playerPosAndAngle ~= nil then
        pX, pY, pA = Phase7.playerPosAndAngle()
    end
    if pX then
        local rad = math.rad(pA)
        local off = Render.pupilLagOffset() * config.pupilTravel
        return Render.clampPupil(pX, pY, pX + off * math.cos(rad), pY + off * math.sin(rad))
    end
    -- Center-Wipe (Raumwechsel): Auge folgt dem Körper (gleiche interpolierte
    -- Position wie playerScreenPosition), damit das Auge immer im Körper
    -- bleibt.
    local wX, wY, wA
    if Wipe ~= nil and Wipe.playerPosAndAngle ~= nil then
        wX, wY, wA = Wipe.playerPosAndAngle()
    end
    if wX then
        local rad = math.rad(wA)
        local off = Render.pupilLagOffset() * config.pupilTravel
        return Render.clampPupil(wX, wY, wX + off * math.cos(rad), wY + off * math.sin(rad))
    end
    -- Radialer Raumwechsel: Auge folgt dem Körper (gleiche interpolierte
    -- Position wie playerScreenPosition), damit das Auge immer im Körper
    -- bleibt.
    local rtX, rtY, rtAngle = RoomTransition.playerPosAndAngle()
    if rtX then
        -- Nach der Landung: kurzer Blick zum Baby (nur wenn Baby vorhanden).
        if pv.lookAtBabyFramesRemaining > 0 and state.baby then
            local bx, by = Render.babyScreenPosition()
            if bx then
                local dx, dy = bx - rtX, by - rtY
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0.01 then
                    return Render.clampPupil(rtX, rtY, rtX + dx / len * config.pupilTravel, rtY + dy / len * config.pupilTravel)
                end
            end
        end
        local rad = math.rad(rtAngle)
        local off = Render.pupilLagOffset() * config.pupilTravel
        return Render.clampPupil(rtX, rtY, rtX + off * math.cos(rad), rtY + off * math.sin(rad))
    end
    local radius = Render.playerRadius()
    -- Winkelauflösung EXAKT wie in playerScreenPosition (Körper), damit das
    -- Auge immer im Körper liegt: Shared-Transit-Winkel, sonst Ready-Formation
    -- (Dock bereit), sonst Transit-Achse, sonst State-Winkel. Vorher fehlte
    -- die Ready-Formation -> nach der Landung wurde das Auge am Achs-Winkel
    -- gezeichnet, während der Körper in der Formation stand (Auge „weg“).
    local angle = state.player.angle
    local sharedAngle = Render.sharedPlayerAngle()
    if sharedAngle then
        angle = sharedAngle
    elseif not Bridge.isCrossing() and not Baby.isCrossing() then
        local readyAngle = Render.sharedReadyPlayerAngle()
        if readyAngle then
            angle = readyAngle
        end
    elseif Bridge.isCrossing() then
        angle = Bridge.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)

    -- Nach der Landung: kurzer Blick zum Baby („gemeinsam angekommen“). Rein
    -- visuell; die Pupille bleibt per Clamp im Augenkörper.
    if pv.lookAtBabyFramesRemaining > 0 and state.baby then
        local bx, by = Render.babyScreenPosition()
        if bx then
            local dx, dy = bx - x, by - y
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.01 then
                return Render.clampPupil(x, y, x + dx / len * config.pupilTravel, y + dy / len * config.pupilTravel)
            end
        end
    end

    -- Gemeinsamer Brückentransit / Bridge-Ready / Kernbrücken-Transit: der
    -- Player blickt zur Brücke (radial zum anderen Ring bzw. zum Mittelpunkt)
    -- — als Paar mit dem Baby. Am Transitstart mit kleinem Fokus-Boost (stärker
    -- radial), danach normal. Rein visuell.
    local bt = Bridge.getTransit()
    if (bt and bt.active and (bt.shared or bt.toRing == "center"))
        or (not Bridge.isCrossing() and Baby.findTransferReadyBridge() ~= nil) then
        local travel = config.pupilTravel
        if bt and bt.active and bt.shared and pv.transitFocusFramesRemaining > 0 then
            travel = travel + config.transitFocusTravelBoost
        end
        local dx, dy = config.centerX - x, config.centerY - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            return Render.clampPupil(x, y, x + dx / len * travel, y + dy / len * travel)
        end
    end
    local rad = math.rad(angle)
    -- Pupillen-Versatz folgt der Facing-Richtung (bzw. Motion-Lag, falls
    -- geladen) und skaliert auf max pupilTravel. Max-Auslenkung = pupilTravel.
    local off = Render.pupilLagOffset() * config.pupilTravel
    local px = x + off * math.cos(rad)
    local py = y + off * math.sin(rad)
    -- Idle-Herumschauen (neugierig/verspielt, NICHT hektisch): nach zufälliger
    -- Ruhe ein kurzer Blick in eine ZUFÄLLIGE Richtung (innen/außen/CW/CCW/
    -- neutral), kurz gehalten, sanft zurück. Rein visuell; die Pupille bleibt
    -- per Clamp vollständig im schwarzen Körper.
    local il = Render.playerVisual.idleLook
    if il and il.state ~= "rest" then
        local ux, uy = Render.idleLookUnit(x, y, angle, il.targetDir)
        px = px + ux * il.amount
        py = py + uy * il.amount
    end
    return Render.clampPupil(x, y, px, py)
end

-- Klemmt die Pupillenmitte so, dass der Pupillenrand nie außerhalb der
-- sichtbaren Kugel liegt (Offset <= playerBodyRadius - Pupillenradius - 0.5).
-- Rein visuell; „kein Auge außerhalb der Figur“ während des Transit-Fokus.
function Render.clampPupil(cx, cy, px, py)
    local pr = config.pupilRadius
    if Render.playerVisual and Render.playerVisual.transitFocusFramesRemaining > 0 then
        pr = pr + config.transitFocusPupilBoost
    end
    local maxOffset = config.playerBodyRadius - pr - 0.5
    local dx, dy = px - cx, py - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= maxOffset then
        return px, py
    end
    if len < 0.001 then
        return cx, cy
    end
    return cx + dx / len * maxOffset, cy + dy / len * maxOffset
end

-- Baby-Innenkreis-Position: der Innenkreis folgt IMMER dem Player (Screen-
-- Vektor baby->player), sobald keine höher priorisierte Reaktion aktiv ist —
-- das Baby sucht den Player, wo immer er ist (gleicher Ring tangential, über
-- Ringe hinweg radial/diagonal). Nur gezielte, kleine Versätze überlagern das:
--   transit : in Transitrichtung (radial zum Zielring)
--   bridge  : kurz Richtung Brücke (radial, je nach Babyring)
--   push    : geringfügig in Bewegungsrichtung (tangential CW/CCW)
--   settle/landing : zurück Richtung Zentrum
-- Travel konstant babyLookTravel (klein, ruhig, kein googly-eye). Rein visuell.
function Render.babyEyePosition(reaction, x, y)
    local travel = config.babyLookTravel

    -- transit: in Transitrichtung (radial). Gemeinsamer Transit (Bridge) und
    -- Baby-Solotransit haben beide eine toRing-Information.
    if reaction == "transit" then
        local dx, dy
        local bt = Bridge.getTransit()
        if bt and bt.active and bt.shared then
            if bt.toRing == "inner" then
                dx, dy = config.centerX - x, config.centerY - y
            else
                dx, dy = x - config.centerX, y - config.centerY
            end
        elseif Baby.isCrossing() then
            local t = Baby.getTransit()
            if t.toRing == "inner" then
                dx, dy = config.centerX - x, config.centerY - y
            else
                dx, dy = x - config.centerX, y - config.centerY
            end
        end
        if dx and dy then
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.01 then
                return x + dx / len * travel, y + dy / len * travel
            end
        end
        return x, y
    end

    -- bridge: kurz Richtung Brücke (radial; von außen zur Brücke = zum Kern,
    -- von innen = weg vom Kern).
    if reaction == "bridge" then
        local baby = state.baby
        local babyRing = (baby and baby.ring) or state.player.ring
        local dx, dy
        if babyRing == "outer" then
            dx, dy = config.centerX - x, config.centerY - y
        else
            dx, dy = x - config.centerX, y - config.centerY
        end
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            return x + dx / len * travel, y + dy / len * travel
        end
        return x, y
    end

    -- push: geringfügig in Bewegungsrichtung (tangential). pushDir stammt aus
    -- Render.noteBabyPush (echte Schieberichtung).
    if reaction == "push" then
        local dir = (Render.babyVisual and Render.babyVisual.pushDir) or 1
        local radx = x - config.centerX
        local rady = y - config.centerY
        local len = math.sqrt(radx * radx + rady * rady)
        if len > 0.01 then
            -- radialer Einheitsvektor (rx, ry); tangential CW = (-ry, rx).
            local rx, ry = radx / len, rady / len
            return x + (-ry) * dir * travel, y + rx * dir * travel
        end
        return x, y
    end

    -- settle/landing: zurück Richtung Zentrum (kein Versatz).
    -- normal: der Innenkreis folgt IMMER dem Player (Screen-Vektor
    -- baby->player) — das Baby sucht den Player, wo immer er ist.
    if reaction == "normal" then
        local px, py = Render.playerScreenPosition()
        local dx, dy = px - x, py - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            return x + dx / len * travel, y + dy / len * travel
        end
        return x, y
    end
    return x, y
end

-- Ghost-Ringnummern (reine Berechnung): äußere World-Ringnummern der
-- abgeschlossenen Räume, die außerhalb des aktiven Außenrings liegen.
-- Konvention: nach innen abnehmende Nummern (aktueller outer = n, abgeschlossen
-- = n+1, n+2, ...).
function Render.ghostRingNumbers(currentRoomIndex)
    local idx = currentRoomIndex or 1
    local baseOuter = state.room.rings.outer
    local top = baseOuter + (idx - 1)
    local rings = {}
    for ringNumber = baseOuter + 1, top do
        rings[#rings + 1] = ringNumber
    end
    return rings
end

-- Future-Ring (Design-Legende): der nächste innere Ring (inner-1), der beim
-- nächsten Raumwechsel zum neuen aktiven Innenring wird. Existiert nur,
-- solange es einen echten nächsten Ring gibt (inner-1 >= 1; Ring 0 ist das
-- Zentrum/Ende des Finalraums und kein Future-Ring). Reine Berechnung,
-- read-only — kein Gameplay-Effekt.
function Render.futureRingNumber()
    local inner = state.room.rings.inner
    local n = inner - 1
    if n >= 1 then
        return n
    end
    return nil
end

-- Bildschirmradius des Future-Rings über die Kamera (wandert während einer
-- Raumtransition automatisch mit: future -> neue Innenring-Position). nil,
-- wenn es keinen Future-Ring gibt.
function Render.futureRingRadius()
    local n = Render.futureRingNumber()
    if not n then
        return nil
    end
    return Camera.getRadius(n)
end

-- Kernbasisradius (ohne Pulsation, ohne Reveal-Skalierung) für eine Raum-
-- nummer. Wird von main.lua für die Start-Reveal-Startskala benutzt (die
-- gefüllte Menü-Scheibe = Kern in dieser Größe).
function Render.coreBaseRadius(currentRoomIndex)
    local idx = currentRoomIndex or 1
    return config.coreRadius + (idx - 1) * config.coreGrowthPerRoom
end

-- Kernradius (ohne Pulsation) für eine Raumnummer. Während der Start-Reveal-
-- Animation (Camera.revealScale gesetzt) wird der Kern gemeinsam mit allen
-- Ringradien um den Mittelpunkt skaliert — die Menü-Scheibe geht so nahtlos
-- in den Level-Core über.
function Render.coreRadius(currentRoomIndex)
    local r = Render.coreBaseRadius(currentRoomIndex)
    if Camera.revealScale ~= nil then
        r = r * Camera.revealScale
    end
    return r
end

-- Aktive Raumnummer für Render-Helfer (wird in drawRoom pro Frame gesetzt).
Render.currentRoomIndex = 1

-- Sichtbarer Kernrand (Kernbasis + Pulsation) für die aktive Raumnummer.
-- Wird für Kernbrücken (Gate) und Kernbrücken-Transite verwendet, damit die
-- Brücke und die Figuren EXAKT am sichtbaren Kernrand enden (sauberer
-- Anschluss, kein Spalt, kein Überstand).
function Render.coreEdgeRadius()
    local idx = Render.currentRoomIndex or 1
    return Render.coreRadius(idx) + Render.corePulseOffset()
end

-- Ist eine Figur (Abstand vom Mittelpunkt) optisch HINTER dem gefüllten Kern
-- verdeckt? Ja, wenn ihr Radius (Mittelpunkt-Abstand) klar KLEINER als der
-- STABILE Basis-Kernradius ist (1-px-Marge: eine Figur am Kernrand wird nie
-- verdeckt — sonst würde die Kern-Pulsation beim Transit-Ende am Kernrand
-- flackern). Während Transit/Raumwechsel gilt: Figuren hinter dem Kern werden
-- vom Kern verdeckt (der Kern „zeichnet über" sie — sie werden nicht
-- gezeichnet, ihr Transition-State läuft aber kontinuierlich weiter; kein
-- Despawn/Respawn). Sobald der Radius den Kernrand wieder überschreitet,
-- tauchen sie an ihrer kontinuierlichen Position wieder auf. Rein visuell;
-- im normalen Gameplay (Ringe >= innerRadius > Kern) nie aktiv.
function Render.figureCoveredByCore(radius)
    if not radius then
        return false
    end
    -- Level-7-Spezialübergang (neue Phase): während Ruhe/Puls/Kollaps/
    -- Explosion/Dunkel und dem Ring-Wiederaufbau sind die Figuren hinter dem
    -- Kern verdeckt (kein getrenntes Erscheinen); erst beim Figuren-Exit im
    -- Rebuild werden sie gezeichnet.
    if Phase7 ~= nil and Phase7.isActive ~= nil and Phase7.isActive() and Phase7.hidesFigures() then
        return true
    end
    local idx = Render.currentRoomIndex or 1
    return radius < Render.coreBaseRadius(idx) - 1
end

-- Aktuelle Pulsations-Offset des Kerns (rein visuell): organisches Atmen aus
-- einer langsamen Hauptwelle plus einer sehr kleinen, langsameren Atemwelle.
-- Deterministisch (reine Funktion von visualTime), kein Zufall.
function Render.corePulseOffset()
    local t = Render.visualTime
    local main = math.sin(t * 2 * math.pi / config.corePulsePeriod) * config.corePulseAmplitude
    local slow = math.sin(t * 2 * math.pi / config.corePulsePeriod2) * config.corePulseAmplitude2
    return main + slow
end

-- --- Schaltervorschau (Phase 8.3): rein visuell, read-only ----------------

-- Blinkphase der Preview: 1 vollständiger Zyklus pro Sekunde (0.5 s ON,
-- 0.5 s OFF). Determinismus: (t % periode) < periode/2 -> ON. Nutzt dieselbe
-- visuelle Zeitquelle wie die Kernpulsation (Render.visualTime).
function Render.previewBlinkOn(time)
    local t = time or Render.visualTime
    local period = config.previewBlinkPeriod
    if period <= 0 then
        return true
    end
    return (t % period) < (period / 2)
end

-- Schalter auf demselben Ring wie der Spieler mit strikt < previewRange Grad
-- Abstand (Winkel über Geometry.delta, Wraparound-sicher). Reine Nähe,
-- keine Zustandsänderung.
function Render.nearbyPreviewSwitches()
    local result = {}
    local playerRing = state.player.ring
    for _, sw in ipairs(state.room.switches) do
        -- Einmalschalter nach dem Verbrauch: verschwunden (nicht gezeichnet) —
        -- auch die Schaltervorschau blendet sie aus.
        if sw.oneShot == true and State.consumedSwitches[sw.id] then
            -- übersprungen
        elseif sw.ring == playerRing then
            local d = math.abs(geo.delta(state.player.angle, sw.angle))
            if d < config.switchPreviewRange then
                result[#result + 1] = sw
            end
        end
    end
    return result
end

-- Menge aller hervorgehobenen Element-IDs (onA + onB der nahen Schalter,
-- unabhängig vom aktuellen Schalterzustand: Preview zeigt Zuordnung, nicht
-- Aktivität). Sperrzustände -> leer: Config off, roomComplete, Camera-Transi-
-- tion, Bridge-Transit. Reine UI-Menge; nichts wird in State/Levels gespeichert.
function Render.previewElementIds(roomComplete)
    if not config.switchPreviewEnabled then
        return {}
    end
    if roomComplete then
        return {}
    end
    if Camera.isTransitioning() then
        return {}
    end
    if Bridge.isCrossing() then
        return {}
    end
    local set = {}
    for _, sw in ipairs(Render.nearbyPreviewSwitches()) do
        -- onA/onB dürfen einzelne IDs ODER Listen sein (Segment-Schalter).
        for _, id in ipairs(State.controlIds(sw.onA)) do set[id] = true end
        for _, id in ipairs(State.controlIds(sw.onB)) do set[id] = true end
    end
    return set
end

-- --- Zeichenhelfer (nur Grafik, keine Zustandsänderung) -------------------

-- 2) Geisterringe abgeschlossener Räume = HISTORY (Design-Legende): nur noch
-- eine sehr zurückhaltende visuelle Spur — dünne, durchgehende 1-px-weiße
-- Kreislinien außerhalb des aktiven Außenrings (Camera-Radius), statisch und
-- ruhig. Keine Dash-Segmente, keine Indexmarke, kein Drift, kein Puls, keine
-- Animation im normalen Gameplay. Damit bleibt History deutlich schwächer als
-- die solide aktive Ringbahn und fällt beim kurzen Blick nie vor Player, Baby
-- oder Puzzleobjekten auf (Zielhierarchie: ganz hinten).
local function drawGhostRings(currentRoomIndex)
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    for _, ringNumber in ipairs(Render.ghostRingNumbers(currentRoomIndex)) do
        local radius = Camera.getRadius(ringNumber)
        if radius > config.outerRadius then
            gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
        end
    end
    gfx.setLineWidth(1)
end

-- Future-Ring (Design-Legende): durchgehende, subtil pulsierende Linie an der
-- Position des nächsten inneren Rings (inner-1) — klar als Kreis/Ring lesbar,
-- weniger dominant als die aktive Ringbahn, ohne technischen Ballast (keine
-- Dash-Segmente, keine Skala, keine Marken). Wird NACH dem Kern gezeichnet,
-- damit sie auch dann lesbar bleibt, wenn der wachsende Kern sie überlagert
-- (der nächste Ring „entsteht“ im Kern — „bald relevant“). Während einer
-- Raumtransition wandert sie über die Kamera automatisch in die neue
-- Innenring-Position (future -> active); die Mindestradius-Grenze verhindert
-- Zeichnen bei (noch) ungültigem Radius.
--
-- ZENTRUMS-REGEL : Der Future-Ring wird
-- NUR gezeichnet, wenn er (noch) innerhalb der Kernfläche liegt (Raum 2+:
-- Kern ist über den Future-Ring gewachsen -> der nächste Ring „entsteht“ im
-- Kern). Liegt er dagegen AUẞERHALB oder exakt auf dem Kernrand (Raum 1:
-- Kern 30 px, Future-Ring 32 px), entfällt er — sonst erschiene um den kleinen
-- Kern ein zusätzlicher pulsierender Outline-/Echo-Ring. Diese Regel gilt
-- UNBEDINGT — im normalen Gameplay UND während der gesamten Raumtransition:
-- der Ring darf nicht nur in Level 1 verschwinden und während der Transition
-- wieder auftauchen (sonst wäre der Echo-Ring um den Kern sichtbar, wenn der
-- alte Future-Ring seine Morph-Reise beginnt). Damit hat Level 1 im Zentrum
-- exakt dieselbe Darstellung wie die späteren Level: nur die zentrale
-- pulsierende Kernfläche, nie ein zusätzlicher dünner Ring darum.
local function drawFutureRing(currentRoomIndex)
    local r = Render.futureRingRadius()
    if not r or r < config.futureRingMinRadius then
        return
    end
    -- Zentrums-Regel (immer): nur zeichnen, wenn der Future-Ring klar im
    -- Kernbereich liegt (auch während der Transition — kein Echo-Ring).
    local coreR = Render.coreRadius(currentRoomIndex or 1) + Render.corePulseOffset()
    if r >= coreR - config.coreEchoHideMargin then
        return
    end
    local width = config.futureRingLineWidth
    local radius = r
    if RoomTransition.isActive() then
        local p = RoomTransition.progress() or 0
        if not RoomTransition.isNewRoomLoaded() then
            -- Alter Future-Ring: einmaliger Impuls, dann Wachstum zur Bahn
            -- (Morph zum neuen aktiven Innenring).
            radius = r + RoomTransition.futureImpulse(p)
            width = RoomTransition.futureWidth(p)
        else
            -- Neuer Future-Ring: erst erscheinen, wenn der Morph weit genug
            -- fortgeschritten ist (sonst wirken zwei Kreise nebeneinander).
            if p < config.roomTransNewFutureStart then
                return
            end
            radius = r
            width = config.futureRingLineWidth
        end
    else
        -- Normales Gameplay: subtile Atmung (kein Puls während der Transition).
        local t = Render.visualTime
        radius = r + math.sin(t * 2 * math.pi / config.futureRingPulsePeriod) * config.futureRingPulseAmplitude
    end
    gfx.setColor(WHITE)
    gfx.setLineWidth(width)
    gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setLineWidth(1)
end

-- 3) Kern: gefüllter Kreis mit 50%-Dither, Radius wächst mit Raumnummer,
-- langsame Pulsation. Dither deterministisch (setDitherPattern), danach Reset.
local function drawCore(currentRoomIndex)
    local radius = Render.coreRadius(currentRoomIndex) + Render.corePulseOffset()
    gfx.setDitherPattern(50)
    gfx.setColor(WHITE)
    gfx.fillCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setDitherPattern(100) -- volle Deckung: kein Pattern-Leak
    gfx.setColor(WHITE)
end

-- 4) Bahn eines Rings: weißer Bogen, trackWidth 8, Camera-Radius.
local function drawTrack(radius)
    gfx.setColor(WHITE)
    gfx.setLineWidth(config.trackWidth)
    gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setLineWidth(1)
end

-- 5) Blende: geschlossen = schwarzer Sperr-Bahnabschnitt mit 1 px weißer
--    Kontur und klaren weißen Endbegrenzungen (KEINE Schraffur im Segment);
--    offen/pendingClose = weiße Bahn + zwei kleine Endmarken.
-- previewOn: zusätzl. 1-px-Halo (zweite Außenkontur), niemals Größenwachstum.
local function drawShutter(sh, previewOn)
    local visual = Render.shutterVisualState(sh.id)
    local radius = Render.ringRadius(sh.ring)
    local anim = Render.shutterAnims[sh.id]
    local startAngle = geo.norm(sh.angle - config.shutterArcWidth / 2)
    local endAngle = geo.norm(sh.angle + config.shutterArcWidth / 2)
    if visual == "closed" then
        -- Mechanischer Überschwinger: beim Zuschnappen 1 px über die End-
        -- position hinaus und über 2 Frames zurück (rein visuell, Kollision
        -- und pendingClose bleiben unverändert).
        local overDeg = 0
        if anim and anim.kind == "close" then
            local frac = anim.frames / config.shutterOvershootFrames
            overDeg = config.shutterOvershootPx * frac * 180 / (math.pi * radius)
        end
        local sA = geo.norm(startAngle - overDeg)
        local eA = geo.norm(endAngle + overDeg)
        -- Preview-Halo: zweite weiße Außenkontur 1 px weiter außen (14 px)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.trackWidth + 6)
            gfx.drawArc(config.centerX, config.centerY, radius, sA, eA)
            gfx.setLineWidth(1)
        end
        -- 1 px weiße Kontur (12-px-Bogen unter dem 10-px-Schwarzblock)
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.trackWidth + 4)
        gfx.drawArc(config.centerX, config.centerY, radius, sA, eA)
        -- schwarzer Block (unterbricht die weiße Bahn)
        gfx.setColor(BLACK)
        gfx.setLineWidth(config.trackWidth + 2)
        gfx.drawArc(config.centerX, config.centerY, radius, sA, eA)
        -- KEINE Schraffur im Sperrsegment (die Absperrung bleibt schlicht):
        -- nur klare 1-px-weiße Endbegrenzungen über die Bahn, damit der
        -- blockierte Abschnitt direkt als gesperrt lesbar ist. Kein Hatch-
        -- Muster — weder weiß (Shutter) noch schwarz (Einmal-Code).
        gfx.setColor(WHITE)
        gfx.setLineWidth(1)
        local tw2 = config.trackWidth / 2
        local e1x, e1y = geo.polar(config.centerX, config.centerY, radius - tw2, startAngle)
        local e1ox, e1oy = geo.polar(config.centerX, config.centerY, radius + tw2, startAngle)
        gfx.drawLine(e1x, e1y, e1ox, e1oy)
        local e2x, e2y = geo.polar(config.centerX, config.centerY, radius - tw2, endAngle)
        local e2ox, e2oy = geo.polar(config.centerX, config.centerY, radius + tw2, endAngle)
        gfx.drawLine(e2x, e2y, e2ox, e2oy)
        -- Mittelpunkt: ein klarer WEISSER Punkt exakt im geometrischen Zentrum
        -- der Blockade (rund, ~3 px, statisch — gehört zum Blockade-Design,
        -- KEIN Kausalitätssymbol). Auf dem schwarzen Sperrblock klar sichtbar.
        local ccx, ccy = geo.polar(config.centerX, config.centerY, radius, sh.angle)
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(ccx, ccy, config.shutterCenterDotRadius)
        gfx.setLineWidth(1)
    else
        -- offen (auch pendingClose): Bahn bleibt weiß, zwei kleine Endmarken.
        -- Beim Öffnen zieht sich der schwarze Bogen schnell->langsam zurück.
        if anim and anim.kind == "open" then
            local rem = math.max(0, anim.frames / 4)
            local w = config.shutterArcWidth * rem * rem -- schneller Start
            gfx.setColor(BLACK)
            gfx.setLineWidth(config.trackWidth + 2)
            gfx.drawArc(config.centerX, config.centerY, radius,
                geo.norm(sh.angle - w / 2), geo.norm(sh.angle + w / 2))
            gfx.setColor(WHITE)
        end
        if previewOn then
            -- 1-px-Außenkontur knapp außerhalb der Bahn über dem Blendbogen
            gfx.setColor(WHITE)
            gfx.setLineWidth(1)
            gfx.drawArc(config.centerX, config.centerY, radius + config.trackWidth / 2 + 1, startAngle, endAngle)
        end
        gfx.setColor(WHITE)
        local m1x, m1y = geo.polar(config.centerX, config.centerY, radius, startAngle)
        local m2x, m2y = geo.polar(config.centerX, config.centerY, radius, endAngle)
        gfx.fillCircleAtPoint(m1x, m1y, 1.5)
        gfx.fillCircleAtPoint(m2x, m2y, 1.5)
        -- Ehemalige Blockadenposition subtil markieren: sehr reduzierter
        -- SCHWARZER Mittelpunkt auf der weißen Bahn (~2 px). Die durchgehende
        -- Ringbahn bleibt klar dominant; der Punkt wirkt NICHT als Sperre.
        local ccx, ccy = geo.polar(config.centerX, config.centerY, radius, sh.angle)
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ccx, ccy, config.shutterOpenCenterDotRadius)
        gfx.setColor(WHITE)
    end
end

-- Grobe diagonale Schraffur (Einmal-Motiv): kurze, parallele 45°-Striche von
-- links unten nach rechts oben über einem um angle rotierten Rechteck (Länge
-- w, Breite h). Kein Dither, keine Kreuzschraffur, keine Symbole. Identisches
-- Muster für Einmalschalter und Einmal-Brücke (gleiche Richtung, gleiche
-- Stärke 1 px, gleicher Abstand): beide zeichnen grobe SCHWARZE Striche auf
-- weißem Grundkörper. Die Striche laufen lokal von (t-half, sgn*half) nach
-- (t+half, -sgn*half) — in Bildschirmkoordinaten „links unten -> rechts oben“
-- (/), gedreht mit dem Objekt (Muster lokal gekoppelt). flip=true dreht den
-- Quer-Sinn um: damit zeigen Einmalschalter (flip=false) und Einmal-Brücke
-- (flip=true, Länge radial statt tangential) in Bildschirmkoordinaten in
-- DIESELBE Richtung (bei gleichem Winkel exakt parallel; die Striche kreuzen
-- den Körper jeweils um 45°).
local function drawHatch(x, y, angle, w, h, step, len, color, width, tStart, flip)
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad)   -- Längsrichtung
    local rx, ry = math.sin(rad), -math.cos(rad)  -- Querrichtung
    gfx.setColor(color)
    gfx.setLineWidth(width or 1)
    local half = len / 2
    local sgn = flip and 1 or -1
    local t = tStart or (-w / 2 + half)
    while t <= w / 2 - half do
        -- Strichzentrum auf (t, 0); von (t-half, sgn*half) zu (t+half, -sgn*half):
        -- in Bildschirmkoordinaten von LINKS UNTEN nach RECHTS OBEN (45°-/
        -- Schrägstrich) — dieselbe Richtung für Einmalschalter und Einmal-Brücke.
        local x1 = x + tx * (t - half) + rx * (sgn * half)
        local y1 = y + ty * (t - half) + ry * (sgn * half)
        local x2 = x + tx * (t + half) + rx * (-sgn * half)
        local y2 = y + ty * (t + half) + ry * (-sgn * half)
        gfx.drawLine(x1, y1, x2, y2)
        t = t + step
    end
    gfx.setLineWidth(1)
end

-- 6) Brücke (Design-Legende, Teil 3): drei klar unterscheidbare Zustände.
-- INAKTIV: sichtbare Docks an beiden Ringbahnen + klare Punktspur (5-7
-- Punkte, Radius 1.5) entlang der Achse — nur möglicher Übergang, „hier ist
-- noch keine echte Verbindung“, keine fertige Brücke.
-- AKTIVIERUNG (extending): Verdichtung von BEIDEN DOCKS zur Mitte — die
-- Punktdichte wächst lokal (6 px -> 2 px), die Brückenfläche füllt sich mit
-- Punkten und bekommt Breite; Phase 3 — ab bridgeSolidStart wächst eine
-- geschlossene, vollständig weiße Form von beiden Ringen zur Mitte über das
-- verdichtete Raster.
-- AKTIV: dicke, vollständig weiße Brücke (bridgeBodyWidth 9), sofort als
-- begehbarer Übergang lesbar. Keine Fugen/Docks/Schraffur. Deaktivierung
-- (retracting) läuft rückwärts (weiße Form -> dichte Punkte -> Punktspur).
-- Ready: wenige Frames minimal kräftiger (Form +1 px). KEIN Baby-Dock-Punkt
-- mehr an der Brücke (die Baby-Stellfläche zeigt drawBabyDocks). EINMAL-
-- Brücken (oneShot): verbraucht (State.consumedBridges) -> nur noch reduzierte
-- Dockreste, keine Punktspur/Form mehr, dauerhaft weg und nicht benutzbar.
-- GEMEINSAMER SEGMENT-HELFER für ALLE radialen Brücken: Eine Kernbrücke
-- (Gate, inner -> MITTELPUNKT) ist KEIN eigener visueller Brückentyp — sie ist
-- eine NORMALE BRÜCKE, deren Ziel lediglich der Kernrand ist. drawBridgeSegment
-- zeichnet jede radiale Brücke zwischen fromR (Ringseite) und toR (Gegenseite:
-- äußerer Ring ODER sichtbarer Kernrand) exakt gleich: gleiche Breite, gleiche
-- weiße Fläche, gleiche Docks, gleiche Punktspur, gleiche Materialisierung.
-- Für toR < fromR (Raum 7: Kern 64 < Innenring 68) läuft die Achse nach
-- innen — identische Punkt-/Formlogik, nur die Richtung ist umgekehrt.
local function drawBridgeSegment(b, previewOn, fromR, toR)
    local rad = math.rad(b.angle)
    local tanx, tany = math.cos(rad), math.sin(rad) -- tangential CW
    local visual = Render.bridgeVisualState(b.id)
    -- Ready-Impuls: wenige Frames minimal kräftiger nach dem Andocken.
    local ready = (Render.bridgeReadyFrames and Render.bridgeReadyFrames[b.id] or 0) > 0
    local halo = previewOn and 2 or 0
    -- Achse: L = Abstand (positiv), dir = Richtung Ring -> Gegenseite.
    local L = math.abs(toR - fromR)
    local dir = (toR >= fromR) and 1 or -1

    -- Verbrauchte Einmal-Brücke: nur reduzierte, beschädigte Dockreste an
    -- beiden Ringen (keine Punktspur, keine Form, dauerhaft weg).
    if b.oneShot and state.consumedBridges[b.id] then
        local function stub(r, t)
            local sx, sy = geo.polar(config.centerX, config.centerY, r, b.angle)
            gfx.setColor(WHITE)
            gfx.fillCircleAtPoint(sx + tanx * t, sy + tany * t, 1)
        end
        stub(fromR + 2, 0)
        stub(fromR + 4, -2)
        stub(fromR + 3, 2)
        stub(toR - 2, 0)
        stub(toR - 4, -2)
        stub(toR - 3, 2)
        return
    end

    -- Punkt auf der Brückenachse bei Radius r.
    local function pt(r)
        return geo.polar(config.centerX, config.centerY, r, b.angle)
    end

    -- Materialisierungs-Fortschritt p: 0 = eingefahren (nur Punktspur),
    -- 1 = volle Brücke (weiße Form). extending 0->1, retracting 1->0. Rein
    -- visuell; A-Input/Docking/Transitdauer bleiben unverändert.
    local anim = Render.bridgeAnims[b.id]
    local p = 1
    if anim then
        p = anim.p or 1
    end
    if visual == "inactive" then
        p = 0
    end

    -- KEINE separaten Dock-Punkte mehr: eine inaktive normale Brücke wird
    -- AUSSCHLIESSLICH durch die klare Punktspur dargestellt (5-7 identische
    -- weiße Punkte, gleiche Größe, gleicher Abstand — die Endpunkte der Spur
    -- sind die Anschlüsse). Keine Mischung aus Punkten/Strichen/Pixelblöcken.

    -- NEUE Aktivierung (Design-Legende): feste Punktpositionen, NUR die Dichte
    -- wächst — kein Wandern, kein Wachstum von den Enden, keine Partikel, kein
    -- Flash. Die Bridge-Position bleibt während der gesamten Animation absolut
    -- stabil; es werden nur Zwischenräume ergänzt und am Ende Reihen gefüllt.
    --   Stufe 1: 7 Ankerpunkte gleichmäßig über die ganze Verbindung
    --   Stufe 2: neue Punkte exakt zwischen den Ankern (Mittelpunkte)
    --   Stufe 3: volle dichte Achsenpunktlinie
    --   Stufe 4: zusätzliche Reihen über/unter der Mittellinie (Breite)
    --   Stufe 5 (p=1): durchgehende weiße Brücke (darunter, kein Raster)
    if p < 1 then
        local dotR = config.bridgeDotRadius + (halo > 0 and 0.5 or 0)
        local stage = Render.bridgeDensityStage(p)
        local anchorStep = L / 6 -- 7 Anker, Abstand L/6
        local gridStep = config.bridgeGridStep
        gfx.setColor(WHITE)
        local function dotAt(t, tOff)
            local bx, by = pt(fromR + t * dir)
            gfx.fillCircleAtPoint(bx + tanx * tOff, by + tany * tOff, dotR)
        end
        -- Anker: IMMER sichtbar (identische Größe, gleicher Abstand, statisch).
        for i = 0, 6 do
            dotAt(anchorStep * i, 0)
        end
        if stage >= 2 then
            -- Mittelpunkte exakt zwischen den Ankern (die Originalpunkte
            -- bewegen sich NICHT — nur Zwischenräume werden ergänzt).
            for i = 0, 5 do
                dotAt(anchorStep * (i + 0.5), 0)
            end
        end
        if stage >= 3 then
            -- volle Achsenlinie: alle Gitterpositionen (sehr dichte, aber noch
            -- eindeutig punktartige Verbindung).
            local t = 0
            while t <= L + 0.01 do
                dotAt(t, 0)
                t = t + gridStep
            end
        end
        if stage >= 4 then
            -- Breite: Reihen über/unter der Mittellinie innerhalb der finalen
            -- Brückensilhouette (Materialverdichtung, kein Partikeleffekt).
            local row = config.bridgeGridRowStep
            local t = 0
            while t <= L + 0.01 do
                dotAt(t, -row)
                dotAt(t, row)
                t = t + gridStep
            end
        end
    end

    -- Einmal-Brücke, INAKTIV (noch vorhanden): reduzierte Schraffur über der
    -- Punktspur — kurze, dünne WEISSE Diagonalstriche auf schwarzem Grund
    -- (Papier-Inversion), in den Lücken zwischen den Punkten. Dieselbe
    -- Richtung/Sprache wie die aktive Schraffur, aber deutlich reduziert,
    -- damit die Punktspur („noch keine Brücke“) lesbar bleibt und die Platte
    -- nicht wie ein neues Objekt wirkt. Kein Dither, keine Symbole.
    if visual == "inactive" and b.oneShot and not state.consumedBridges[b.id] then
        local mid = (fromR + toR) / 2
        local mx, my = pt(mid)
        drawHatch(mx, my, geo.norm(b.angle - 90), L, config.bridgeBodyWidth,
            config.oneShotInactiveHatchStep, config.oneShotInactiveHatchLen, WHITE,
            config.oneShotInactiveHatchWidth, config.oneShotInactiveHatchStart, true)
    end

    -- Phase 3: die geschlossene weiße Form wächst von beiden Ringen zur Mitte
    -- (über dem verdichteten Raster) -> dicke, vollständig weiße aktive Brücke.
    local sp = Render.bridgeSolidProgress(p)
    if sp > 0 then
        local halfLen = L / 2
        local fromTip = fromR + dir * halfLen * sp
        local toTip = toR - dir * halfLen * sp
        local w = config.bridgeBodyWidth + (ready and 1 or 0) + halo
        gfx.setColor(WHITE)
        gfx.setLineWidth(w)
        if math.abs(fromTip - fromR) > 0.5 then
            local fx, fy = pt(fromR)
            local tx, ty = pt(fromTip)
            gfx.drawLine(fx, fy, tx, ty)
        end
        if math.abs(toTip - toR) > 0.5 then
            local fx, fy = pt(toR)
            local tx, ty = pt(toTip)
            gfx.drawLine(fx, fy, tx, ty)
        end
        gfx.setLineWidth(1)
    end

    -- Einmal-Brücke (oneShot, noch nicht verbraucht): ZUERST die normale weiße
    -- Brücke, ERST DARAUF dieselben groben SCHWARZEN Diagonalen wie beim
    -- Einmalschalter (gleiche Richtung, Stärke 1 px, gleiche Rhythmik — eine
    -- Einmal-Sprache). Die Striche bleiben deutlich VOR den weißen Längskanten
    -- zurück (oneShotBridgeHatchLen 4 auf Körperbreite 9), damit die
    -- zusammenhängende weiße Brückensilhouette nie in einzelne
    -- Diamanten/Segmente zerfällt — die weißen Längskanten bleiben
    -- kontinuierlich lesbar. WICHTIG: die Brücke verläuft RADIAL (Länge =
    -- outerR-innerR), während drawHatch die Länge entlang der tangentialen
    -- Achse legt. Deshalb den Winkel um 90° drehen, damit die Striche über die
    -- Brückenbreite (quer) laufen (Muster rotiert mit der Brückenorientierung).
    if sp >= 1 and b.oneShot and not state.consumedBridges[b.id] then
        local mid = (fromR + toR) / 2
        local mx, my = pt(mid)
        drawHatch(mx, my, geo.norm(b.angle - 90), L, config.bridgeBodyWidth,
            config.oneShotBridgeHatchStep, config.oneShotBridgeHatchLen, BLACK, 1, nil, true)
    end
end

-- Normale Ring->Ring-Brücke (inner <-> outer bzw. beliebige Endpunkt-Ringe):
-- exakt das gemeinsame Segment zwischen den beiden verbundenen Ringen. Im
-- 2-Ring-Standard sind das inner <-> outer; in 3-Ring-Räumen (Level 4) gibt
-- die Brücke ihre Endpunkte über b.rings = { <RingA>, <RingB> } an
-- (z. B. outer <-> middle oder inner <-> outer).
local function drawBridge(b, previewOn)
    local fromR, toR
    if b.rings and type(b.rings) == "table" and #b.rings == 2 then
        fromR = Render.ringRadius(b.rings[1])
        toR = Render.ringRadius(b.rings[2])
    else
        fromR = Render.ringRadius("inner")
        toR = Render.ringRadius("outer")
    end
    drawBridgeSegment(b, previewOn, fromR, toR)
end

-- 7) Kernbrücke / Gate: EINE NORMALE BRÜCKE zum Mittelpunkt — keine eigene
-- Grafik, keine Irisspitze, keine Sonderbreite, kein Stummel. Das Tor wird
-- über den gemeinsamen Segment-Helfer (drawBridgeSegment) EXAKT wie eine
-- Ring->Ring-Brücke gezeichnet, nur mit dem Ziel = sichtbarer Kernrand
-- (statt äußerer Ring): gleiche Breite (bridgeBodyWidth), gleiche weiße
-- Fläche, gleiche Anschlussform am inneren Ring, gleiche Punktspur im
-- inaktiven Zustand, gleiche Materialisierungs-Animation, gleiche Docks.
-- Sauberer Anschluss am Kernrand (kein Spalt, kein Überstand) — der
-- Mittelpunkt/Kern selbst bleibt unverändert (drawCore). Für toR < fromR
-- (Raum 7: Kern 64 < Innenring 68) zeichnet das Segment nach innen.
-- Das Gate kann auf dem INNEREN oder dem ÄUSSEREN Ring liegen (gate.ring).
-- Beide Fälle sind Center-Bridges zum Kern: inner -> Kernrand bzw.
-- outer -> Kernrand (die äußere Speiche überbrückt sichtbar den Innenring).
local function drawGate(previewOn, currentRoomIndex)
    local g = state.room.gate
    if not g then
        return
    end
    local ringName = g.ring or "inner"
    if ringName == "outer" then
        -- Außenring-Gate (generisch, z. B. Level 8): Center-Bridge von der
        -- AUSSENRING-Bahn zum sichtbaren Kernrand — NICHT als Ring->Ring-
        -- Brücke, sondern als echte Speiche zum Mittelpunkt (das Segment
        -- überbrückt den Innenring; der Transit führt im Gameplay zum Kern).
        local outerR = Render.ringRadius("outer")
        local coreEnd = Render.coreEdgeRadius() - config.coreBridgeOverlap
        drawBridgeSegment(g, previewOn, outerR, coreEnd)
    else
        -- Innenring-Gate (Standard): Brücke inner -> sichtbarer Kernrand. Die
        -- Brücke endet mit einem kleinen Überlapp IN den Kern (coreBridgeOverlap),
        -- damit die Verbindung an der dither-gepunkteten Kernkante immer
        -- vollflächig weiß ist — keine sichtbare schwarze Lücke zwischen
        -- Kernbrücke und Mittelpunkt, ohne tief hineinzuragen.
        local innerR = Render.ringRadius("inner")
        local coreEnd = Render.coreEdgeRadius() - config.coreBridgeOverlap
        drawBridgeSegment(g, previewOn, innerR, coreEnd)
    end
    gfx.setLineWidth(1)
end

-- Vorwärtsdeklarationen: fillOval (rotierte Ellipse) und fillRoundRectRot
-- (abgerundetes Rechteck) werden weiter unten definiert; drawSwitch nutzt
-- fillRoundRectRot für den Schalter-Körper.
local fillOval
local fillRoundRectRot

-- 8) Schalter (Referenz): breites flaches Rechteck mit deutlich abgerundeten
--    Ecken (width:height ≈ 2.8:1, Höhe ≈ Bahnbreite) + zwei Innenkreise nahe
--    den Längsenden (vertikal zentriert, symmetrisch). Grundform EXAKT nach
--    Referenz: WEISSER Rounded-Block + schwarze 1-px-Kontur (das weiße Füllen
--    verschmilzt mit der Bahn; die Kontur definiert die Blockform — wie bei
--    der Druckplatte). KEINE Pfeile/Nase/Kerbe/Statussymbole/Textlabels.
--    die AKTIVE Richtung (CW = A,
--    CCW = B) ist als GEFÜLLTER Innenkreis markiert, die inaktive Seite als
--    reine Kontur — man sieht sofort, welche Richtung gerade aktiv ist, ohne
--    neue Symbole. Beim echten Umschalten sinkt der Körper 2 Frames radial
--    ein (mechanisches Klack) und kehrt danach in die Referenzform zurück.
--    Kein Gameplay-Effekt.
local function drawSwitch(sw, scale)
    local s = scale or 1
    local radius = Render.ringRadius(sw.ring)
    local x, y = geo.polar(config.centerX, config.centerY, radius, sw.angle)
    local rad = math.rad(sw.angle)
    local tanx, tany = math.cos(rad), math.sin(rad) -- tangential CW
    local perpx, perpy = -tany, tanx                -- radial zur Ringmitte

    -- Press-Offset: nur bei echtem Umschalten und wenn der Spieler an diesem
    -- Schalter steht (kurzer 2-Frame-Zähler). 1-2 px radial nach innen, danach
    -- exakt zurück in die Referenzform. Kein Rest.
    local pressing = Render.switchPressFrames > 0
        and state.player.ring == sw.ring
        and math.abs(geo.delta(state.player.angle, sw.angle)) <= config.switchPressProximity
    local press = 0
    if pressing then
        press = config.switchPressOffset
    end
    local bx, by = x + perpx * press, y + perpy * press

    -- Körper: weißer abgerundeter Block mit schwarzer 1-px-Kontur (Referenz:
    -- weißer Rounded-Block; die Kontur hält ihn auf der weißen Bahn lesbar).
    -- Bei Skalierung (Verschwinde-Animation) schrumpft alles zum Mittelpunkt.
    local w = config.switchWidth * s
    local h = config.switchHeight * s
    local crr = config.switchCornerRadius * s
    fillRoundRectRot(bx, by, sw.angle,
        w + 2, h + 2, crr + 1, BLACK)
    fillRoundRectRot(bx, by, sw.angle,
        w, h, crr, WHITE)

    -- Zwei gleich große Innenkreise nahe den Längsenden (symmetrisch,
    -- vertikal zentriert) — auf dem weißen Block lesbar. Die AKTIVE Richtung
    -- (CW = A, CCW = B) wird als
    -- GEFÜLLTER schwarzer Kreis markiert; die INAKTIVE Seite bleibt als reine
    -- schwarze KONTOUR sichtbar (schwächer, aber präsent). Damit liest man die
    -- aktive Seite sofort, ohne neue Symbole oder Text. Umschalten = Füllung
    -- wandert auf die andere Seite. Kein Gameplay-Effekt.
    local off = config.switchCircleOffset * s
    local cr = config.switchCircleRadius * s
    local sides = Render.switchSideState(sw.id)
    -- Inaktiver Kreis: als Ring gezeichnet (schwarz füllen, weißen Kern 1 px
    -- ausstechen) — garantiert hohl und auf dem weißen Körper klar lesbar.
    gfx.setColor(BLACK)
    local function drawCircleRing(cx, cy)
        if cr <= 1 then
            -- Schlussphase (sehr klein): gefüllter Punkt statt hohlem Ring.
            gfx.fillCircleAtPoint(cx, cy, 1)
            return
        end
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(cx, cy, cr)
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(cx, cy, cr - 1)
        gfx.setColor(BLACK)
    end
    local function drawActiveCircle(cx, cy)
        if cr >= 0.5 then
            gfx.fillCircleAtPoint(cx, cy, math.max(1, cr))
        end
    end
    -- CW-Seite (+tangential): aktiv bei Zustand A.
    if sides.cw then
        drawActiveCircle(bx + tanx * off, by + tany * off)
    else
        drawCircleRing(bx + tanx * off, by + tany * off)
    end
    -- CCW-Seite (-tangential): aktiv bei Zustand B.
    if sides.ccw then
        drawActiveCircle(bx - tanx * off, by - tany * off)
    else
        drawCircleRing(bx - tanx * off, by - tany * off)
    end

    -- Einmalschalter (oneShot): exakt dieselbe Grundform + dieselben groben
    -- SCHWARZEN Diagonalen wie die Einmal-Brücke (gleiche Richtung, Stärke,
    -- Dichte, Rhythmik — eine Einmal-Sprache). Keine Kerbe, kein X, keine
    -- Symbole. Wo ein Strich einen Kreis kreuzt, bleibt er unsichtbar
    -- (schwarz auf schwarz).
    if sw.oneShot then
        drawHatch(bx, by, sw.angle,
            w, h,
            config.oneShotHatchStep, config.oneShotHatchLen * s, BLACK)
    end
    gfx.setColor(WHITE)
end

-- Skala der Einmalschalter-Verschwinde-Animation (p = t/Duration, 0..1):
-- Anspann-Phase 1 -> 1+Grow (leichtes Aufquellen), dann beschleunigtes
-- Zusammenfallen 1+Grow -> 0. Rein visuell, kein Gameplay. Testbar über die
-- anim-Tabelle (anim.t).
function Render.oneShotVanishScale(anim)
    local dur = config.oneShotSwitchVanishDuration
    if dur <= 0 then
        return 0
    end
    local p = math.min(1, anim.t / dur)
    local pulseEnd = math.max(0, math.min(1, config.oneShotSwitchVanishPulse))
    local grow = config.oneShotSwitchVanishGrow or 0.25
    if p < pulseEnd then
        local q = pulseEnd > 0 and (p / pulseEnd) or 1
        return 1 + grow * math.sin(q * math.pi / 2) -- 1 -> 1+Grow
    end
    local q = pulseEnd >= 1 and 1 or ((p - pulseEnd) / (1 - pulseEnd))
    local inv = 1 - q
    return (1 + grow) * inv * inv -- 1+Grow -> 0 (ease-in)
end

-- Einmalschalter-VERSCHWINDEN nach dem Verbrauch: der Schalter wird während
-- der kurzen Animation skaliert gezeichnet (Anspann-Puls, dann Zusammenfallen
-- in den Mittelpunkt); in der Schlussphase wird nichts mehr gezeichnet.
local function drawSwitchVanish(sw)
    local anim = Render.oneShotVanishAnims[sw.id]
    if not anim then
        return
    end
    local s = Render.oneShotVanishScale(anim)
    if s < 0.05 then
        return
    end
    drawSwitch(sw, s)
end

-- 8b) Druckplatte : die Platte
--     ist ein klares RECHTECK (tangential plateSize px, radial exakt die
--     Bahnbreite trackWidth), EXAKT in die Ringbahn eingelassen. Die weiße
--     Ringlinie endet sauber an der Plattenkante (schwarzer Eraser-Balken),
--     die Platte folgt als SCHWARZE Innenfläche mit kräftiger WEISSER
--     Außenkontur (plateOutlineWidth 3 px — deutlich dicker als die normalen
--     Ringlinien), danach setzt die Bahn fort. Keine Ringlinie läuft durch
--     die Platte. Das schwarze Baby-Quadrat passt optisch perfekt in die
--     schwarze Innenfläche.
--     GEDRÜCKT = nur eine sehr kleine 1-px-Reaktion (die weiße Kontur wird
--     1 px dicker — die schwarze Fläche bleibt lesbar); NICHT GEDRÜCKT =
--     schwarze Innenfläche mit weißem Rahmen. Kein Symbol, keine Pfeile.
local function drawPlate(p)
    local radius = Render.ringRadius(p.ring)
    local x, y = geo.polar(config.centerX, config.centerY, radius, p.angle)
    local pressed = state.platePressed[p.id] == true
    local outline = config.plateOutlineWidth or 3
    local w = config.plateSize
    local h = config.trackWidth

    -- 1) Ringlinie an der Plattenkante sauber unterbrechen: schwarzer
    --    Rechteck-Balken über den Plattenbereich (inkl. Outline), damit die
    --    weiße Bahn exakt an der Platte endet und danach wieder fortfährt.
    fillRoundRectRot(x, y, p.angle, w + 2 * outline, h + 2 * outline, 0, BLACK)
    -- 2) WEISSE Außenkontur (deutlich dicker als die Ringlinien).
    fillRoundRectRot(x, y, p.angle, w + 2 * outline, h + 2 * outline, 0, WHITE)
    -- 3) SCHWARZE Innenfläche (Bahnbreite): das Baby-Quadrat passt hinein.
    fillRoundRectRot(x, y, p.angle, w, h, 0, BLACK)

    if pressed then
        -- GEDRÜCKT: nur eine sehr kleine 1-px-Reaktion — die weiße Kontur
        -- wird 1 px dicker (die schwarze Innenfläche bleibt unverändert
        -- lesbar). Kein Füllen, keine Mulde, kein Icon.
        fillRoundRectRot(x, y, p.angle, w + 2 * outline + 2, h + 2 * outline + 2, 0, WHITE)
        fillRoundRectRot(x, y, p.angle, w, h, 0, BLACK)
    end
    gfx.setLineWidth(1)
    gfx.setColor(WHITE)
end

-- Gefülltes Oval (Polygon-Approximation, 8 Punkte) an (x,y) mit Halbachsen
-- rLong (radial) und rShort (tangential), Winkel 0° = 12 Uhr, CW positiv.
-- Keine Sprite-Rotation nötig; billige primitive 1-Bit-Operationen.
fillOval = function(x, y, angle, rLong, rShort, color)
    local ax, ay, bx, by = Render.bodyAxisVectors(angle)
    gfx.setColor(color)
    local pts = {}
    for i = 0, 7 do
        local t = (i / 8) * 2 * math.pi
        local c, s = math.cos(t), math.sin(t)
        pts[#pts + 1] = x + ax * rLong * c + bx * rShort * s
        pts[#pts + 1] = y + ay * rLong * c + by * rShort * s
    end
    gfx.fillPolygon(table.unpack(pts))
end

-- Gefülltes abgerundetes Rechteck an (x,y), lokal entlang der Ringtangente
-- ausgerichtet (Winkel angle in Grad, 0° = 12 Uhr, CW positiv). Länge w
-- entlang der Tangente, Höhe h radial, Eckenrundung cornerR. Robuste 1-Bit-
-- Konstruktion (kein Arc-Polygon, das im SDK bandenförmig füllte): Mittelsteg
-- + Endkappen (4-Punkt-Rechteckpolygone, rotiert) + vier Eckkreise (rotations-
-- invariant). Fällt cornerR auf 0 zurück, entsteht ein scharfes Rechteck.
fillRoundRectRot = function(x, y, angle, w, h, cornerR, color)
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad)  -- tangential CW
    local rx, ry = math.sin(rad), -math.cos(rad) -- radial nach außen
    local halfW, halfH = w / 2, h / 2
    local cr = math.max(0, math.min(cornerR or 0, halfW - 0.5, halfH - 0.5))
    gfx.setColor(color)
    if cr < 0.5 then
        -- Rundung passt nicht in die Maße: scharfes Rechteck (4 Punkte).
        gfx.fillPolygon(
            x + tx * -halfW + rx * -halfH, y + ty * -halfW + ry * -halfH,
            x + tx * halfW + rx * -halfH, y + ty * halfW + ry * -halfH,
            x + tx * halfW + rx * halfH, y + ty * halfW + ry * halfH,
            x + tx * -halfW + rx * halfH, y + ty * -halfW + ry * halfH)
        return
    end
    -- Mittelsteg (volle Höhe, Breite minus 2cr) und Endkappen (volle Breite,
    -- Höhe minus 2cr) — schneiden die vier Eckenquadrate weg.
    local innerW = w - 2 * cr
    local innerH = h - 2 * cr
    local function rect(lw, lh)
        local hw, hh = lw / 2, lh / 2
        gfx.fillPolygon(
            x + tx * -hw + rx * -hh, y + ty * -hw + ry * -hh,
            x + tx * hw + rx * -hh, y + ty * hw + ry * -hh,
            x + tx * hw + rx * hh, y + ty * hw + ry * hh,
            x + tx * -hw + rx * hh, y + ty * -hw + ry * hh)
    end
    rect(innerW, h)
    rect(w, innerH)
    -- Vier Eckenkreise (Radius cr) runden die Ecken; Kreise sind
    -- rotationsinvariant, die Zentren sitzen in den Eckquadraten.
    local cx0, cy0 = -halfW + cr, -halfH + cr
    local cx1, cy1 = halfW - cr, halfH - cr
    local function corner(lx, ly)
        gfx.fillCircleAtPoint(x + tx * lx + rx * ly, y + ty * lx + ry * ly, cr)
    end
    corner(cx0, cy0)
    corner(cx1, cy0)
    corner(cx0, cy1)
    corner(cx1, cy1)
end

-- 10) Spieler (Referenz „schwarze Kugel + weiße Pupille“): gefüllter
-- SCHWARZER Kreis, dessen Durchmesser EXAKT der Ringbahnbreite entspricht
-- (trackWidth 8 -> playerBodyRadius 4), mit WEIẞER Pupille. KEINE weiße
-- Umrandung/Unterlage mehr — die Figur ist eine reine schwarze Kugel, auf der
-- weißen Bahn (wo der Player im Gameplay immer steht) klar lesbar. Bei
-- Bridge-Transit wird der Körper radial zur Ellipse gestreckt (Start/Ende
-- Kreis, Mitte maximale Streckung; keine Hitboxänderung). Die Augenform folgt
-- der Reaktionspriorität Squint > Widen > Blink > normal; das Auge (weiß)
-- bleibt auch während der Streckung sichtbar.
local function drawPlayer()
    local crossing = Bridge.isCrossing()
    local x, y, angle = Render.playerScreenPosition()

    -- HINTER dem gefüllten Kern (Radius < Kernrand): der Kern verdeckt die
    -- Figur — sie wird nicht gezeichnet, der Transition-State läuft aber
    -- kontinuierlich weiter (kein Despawn/Respawn, kein separates
    -- Verschwinden von Player/Baby). Sobald der Radius den Kernrand wieder
    -- überschreitet, taucht die Figur an ihrer kontinuierlichen Position auf.
    if Render.figureCoveredByCore(math.sqrt((x - config.centerX) ^ 2 + (y - config.centerY) ^ 2)) then
        return
    end

    -- Sichtbarer Körper: genau so breit wie die Ringbahn. Während des radialen
    -- Raumwechsels skaliert die Figur subtil mit (alte Phase: kleine Ausbuchtung
    -- in der Bewegung; neue Phase: wächst beim Landen ein), damit sie mit dem
    -- Übergang verbunden bleibt (kein hartes Poppen). Außerhalb der Transition
    -- ist der Faktor exakt 1.
    local figScale = RoomTransition.figureScale()
    local rBody = config.playerBodyRadius * figScale

    -- Reaktion früh bestimmen (Körperform kann von Squint abhängen).
    local reaction = Render.currentEyeReaction()

    -- Körper: reine schwarze Kugel mit 1-px-WEISSER Außenkontur (auf der
    -- weißen Bahn sichtbar, weil der Körper breiter als die Bahn ist und die
    -- Kontur gegen den schwarzen Grund zeichnet).
    local ow = config.playerOutlineWidth or 0
    if crossing then
        local stretch = Render.bridgeStretch(Bridge.getTransitProgress())
        local sh = math.max(2.5, stretch * 0.25)
        fillOval(x, y, angle, rBody + stretch + ow, rBody - sh + ow, WHITE)
        fillOval(x, y, angle, rBody + stretch, rBody - sh, BLACK)
    elseif reaction == "squint" then
        -- Impact-Kompression : der Körper staucht
        -- sich kurz zusammen — radial 1.5 px + tangential 1 px, als ob die
        -- Figur gegen die Sperre stößt. Nur 6 Frames, keine Positionsänderung.
        local compR = config.impactBodyCompression
        local compT = config.impactBodyTanCompression
        fillOval(x, y, angle, rBody - compR + ow, rBody - compT + ow, WHITE)
        fillOval(x, y, angle, rBody - compR, rBody - compT, BLACK)
    elseif Render.playerVisual.pushFramesRemaining > 0 then
        -- Minimaler Druck beim Baby-Push (Beziehung): 1 px radiale Kompression,
        -- der Blick bleibt fokussiert nach vorn (Richtung Baby).
        local comp = 1
        fillOval(x, y, angle, rBody - comp + ow, rBody + ow, WHITE)
        fillOval(x, y, angle, rBody - comp, rBody, BLACK)
    elseif Render.playerVisual.landingFramesRemaining > 0 then
        -- Ruhiges Landing nach dem gemeinsamen Transit: 1 px radiale
        -- Kompression, wenige Frames, kein Positions-Offset.
        local comp = 1
        fillOval(x, y, angle, rBody - comp + ow, rBody + ow, WHITE)
        fillOval(x, y, angle, rBody - comp, rBody, BLACK)
    else
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(x, y, rBody + ow)
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(x, y, rBody)
    end

    -- Pupille/Auge: WEISS auf dem schwarzen Körper (bleibt während Streckung
    -- sichtbar). Lidlinien (Blink/Squint) ebenfalls weiß, damit sie auf dem
    -- schwarzen Körper lesbar sind.
    local ex, ey = Render.playerEyePosition()
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad) -- tangential CW
    if reaction == "squint" then
        -- Zusammenkneifen (leicht verstärkt):
        -- kurze schmale tangentiale Lidlinie — das Auge zieht sich sichtbar
        -- zusammen (etwas länger als der normale Blink, bleibt aber kompakt).
        local hl = config.impactSquintHalfLen
        gfx.setColor(WHITE)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * hl, ey - ty * hl, ex + tx * hl, ey + ty * hl)
        gfx.setLineWidth(1)
    elseif reaction == "landing" then
        -- Landing nach dem gemeinsamen Transit: das Auge BLEIBT SICHTBAR
        -- (normale Pupille, ggf. kurzer Blick zum Baby) — kein Lidlinien-
        -- Squint, der das Auge verschwinden lässt.
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(ex, ey, config.pupilRadius)
    elseif reaction == "transit" then
        -- Transit-Fokus: Pupille minimal größer (nur am Start, wenige Frames),
        -- danach normale Pupillengröße — der Blick ist weiterhin radial zur
        -- Brücke (playerEyePosition).
        local pr = config.pupilRadius
        if Render.playerVisual.transitFocusFramesRemaining > 0 then
            pr = pr + config.transitFocusPupilBoost
        end
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(ex, ey, pr)
    elseif reaction == "widen" then
        -- Augenweiten: größere Pupille (Basis ist größer, Zuwachs über
        -- config.pupilWidenBoost, damit die geweitete Größe stabil ~4 px bleibt
        -- und die Pupille nie über den Körperrand hinausragt).
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(ex, ey, config.pupilRadius + config.pupilWidenBoost)
    elseif reaction == "blink" then
        -- Blink: geschlossene Lidlinie (lang genug, um die große Pupille
        -- sichtbar zu schließen; kürzer als der Squint).
        local hl = config.blinkLidHalfLen
        gfx.setColor(WHITE)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * hl, ey - ty * hl, ex + tx * hl, ey + ty * hl)
        gfx.setLineWidth(1)
    else
        -- normal: große weiße Pupille (config.pupilRadius, deutlich sichtbar)
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(ex, ey, config.pupilRadius)
    end
    gfx.setColor(WHITE)
end

-- Spieler-Partikelschweif : zeichnet die gespeicherten
-- Trail-Partikel als kleine SCHWARZE Punkte exakt auf der Ringbahn (baseR =
-- Bahnradius, keine radiale Drift), die über ihre Lebensdauer schrumpfen.
-- Unter dem Spieler (über der Bahn), lesbar auf der weißen Bahn. Rein
-- visuell, kein Gameplay-Effekt.
local function drawPlayerTrail()
    local life = config.playerTrailLife
    if not life or life <= 0 then
        return
    end
    local drift = config.playerTrailDrift or 0
    local size = config.playerTrailSize or 1.5
    for _, p in ipairs(Render.trailParticles) do
        local q = math.min(1, p.t / life)
        local r = math.max(0.5, size * (1 - q))
        local pr = p.baseR + drift * q
        local x, y = geo.polar(config.centerX, config.centerY, pr, p.angle)
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(x, y, r)
    end
    gfx.setColor(WHITE)
end

-- Baby-Dock (Referenz-Variante A): vier L-förmige weiße Eckwinkel an der
-- TATSÄCHLICH notwendigen Babyposition vor einer Brücke (Ringradius des
-- Babys auf der Brückenachse) — „Hier muss das Baby stehen“. Der Mittelpunkt
-- der vier Eckmarken stimmt exakt mit der gültigen Baby-Dockposition überein.
-- Keine vollständige Box, kein Kreis, kein Punkt in der Mitte, keine
-- Punktmatrix (Punkte bedeuten im Spiel bereits mögliche/inaktive Brücken).
-- Sichtbarkeit nur kontextuell (Render.babyDockForBridge).
local function drawBabyDocks()
    local baby = state.baby
    if not baby then
        return
    end
    -- Gemeinsame Dock-Zeichnung (vier weiße L-förmige Eckwinkel, Referenz-
    -- Variante A) an einer Ringachse. Die Ecken liegen tangential ~6 px neben
    -- der Bahnmitte und damit außerhalb der 8-px-Bahn (±4 px) auf SCHWARZEM
    -- Grund. Jede Ecke: horizontaler + vertikaler Schenkel (arm px, 1 px stark).
    local function dockAt(id, angle)
        local radius = Render.ringRadius(baby.ring)
        local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
        local ix = math.floor(x + 0.5)
        local iy = math.floor(y + 0.5)
        local half = config.babyDockHalf
        local arm = config.babyDockArm
        -- Ready-Feedback (rein visuell): sobald das Baby die korrekte Position
        -- erreicht, rücken die Ecken einmalig 1 px nach innen und wieder zurück
        -- (2-3 Frames). Kein Puls, kein Blinken, kein Punkt.
        local f = Render.babyDockFeedbackFrames and Render.babyDockFeedbackFrames[id] or 0
        if f >= 1 then
            half = half - 1
        end
        gfx.setColor(WHITE)
        -- oben links
        gfx.fillRect(ix - half, iy - half, arm, 1)
        gfx.fillRect(ix - half, iy - half, 1, arm)
        -- oben rechts
        gfx.fillRect(ix + half - arm + 1, iy - half, arm, 1)
        gfx.fillRect(ix + half, iy - half, 1, arm)
        -- unten links
        gfx.fillRect(ix - half, iy + half - arm + 1, arm, 1)
        gfx.fillRect(ix - half, iy + half, 1, arm)
        -- unten rechts
        gfx.fillRect(ix + half - arm + 1, iy + half - arm + 1, arm, 1)
        gfx.fillRect(ix + half, iy + half, 1, arm)
    end
    -- Normale Brücken (kontextuell relevante, aktive Brücken).
    for _, b in ipairs(state.room.bridges) do
        if Render.babyDockForBridge(b) then
            dockAt(b.id, b.angle)
        end
    end
    -- Tor / Zielausgang (gleiche Dock-Regel): das Baby-Dock erscheint auch am
    -- aktiven Tor, wenn Player und Baby in Position sind (gemeinsamer
    -- Abschluss).
    if state.room.gate and Render.babyDockForGate() then
        dockAt(state.room.gate.id, state.room.gate.angle)
    end
end

-- Player-Dock : kompakte KLAMMERFORM, die die Bahn „einklammert" —
-- je ein tangentialer Balken knapp über und unter der Bahn (nur RADIALE
-- Versätze liegen auf schwarzem Grund), mit kleinen Einhak-Füßen zur Bahn.
-- Deutlich von der Baby-Dock-Sprache (vier L-Ecken) getrennt und kleiner/
-- ruhiger als der frühere offene Rahmen. Ready-Feedback wie beim Baby-Dock:
-- die Klammern rücken einmalig 1 px zur Bahn (2-3 Frames). Rein visuell.
local function drawPlayerDockAt(id, angle)
    local radius = Render.ringRadius(state.player.ring)
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad)   -- tangential CW
    local rx, ry = math.sin(rad), -math.cos(rad)  -- radial nach außen
    local off = config.playerDockHalf
    local bar = config.playerDockBar
    local foot = config.playerDockFoot
    -- Ready-Feedback (rein visuell): sobald der Transfer bereit ist, rücken
    -- die Klammern einmalig 1 px zur Bahn und wieder zurück (kein Puls).
    local f = Render.playerDockFeedbackFrames and Render.playerDockFeedbackFrames[id] or 0
    if f >= 1 then
        off = off - 1
    end
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    -- Innenbalken (unter der Bahn, Richtung Zentrum) + Einhak-Füße nach außen.
    local inx, iny = x - rx * off, y - ry * off
    local inLx, inLy = inx - tx * bar, iny - ty * bar
    local inRx, inRy = inx + tx * bar, iny + ty * bar
    gfx.drawLine(inLx, inLy, inRx, inRy)
    gfx.drawLine(inLx, inLy, inLx + rx * foot, inLy + ry * foot)
    gfx.drawLine(inRx, inRy, inRx + rx * foot, inRy + ry * foot)
    -- Außenbalken (über der Bahn, vom Zentrum weg) + Einhak-Füße nach innen.
    local outx, outy = x + rx * off, y + ry * off
    local outLx, outLy = outx - tx * bar, outy - ty * bar
    local outRx, outRy = outx + tx * bar, outy + ty * bar
    gfx.drawLine(outLx, outLy, outRx, outRy)
    gfx.drawLine(outLx, outLy, outLx - rx * foot, outLy - ry * foot)
    gfx.drawLine(outRx, outRy, outRx - rx * foot, outRy - ry * foot)
    gfx.setLineWidth(1)
end

-- Zeichnet alle kontextuell sichtbaren Player-Docks (Brücken + Tor). Die
-- Sichtbarkeit entscheidet Render.playerDockForBridge/-Gate (read-only);
-- außerhalb von Dock-Situationen bleibt nichts gezeichnet.
local function drawPlayerDocks()
    for _, b in ipairs(state.room.bridges) do
        local pa = Render.playerDockForBridge(b)
        if pa then
            drawPlayerDockAt(b.id, pa)
        end
    end
    if state.room.gate then
        local pa = Render.playerDockForGate()
        if pa then
            drawPlayerDockAt(state.room.gate.id, pa)
        end
    end
end

-- Dünner gestrichelter Kreisumriss (Geist-Form, Schwarz auf der weißen
-- Brücke): Segmente der Bogenlänge playerGhostDash mit Lücken playerGhostGap.
-- Reine 1-Bit-Outline, subtil — keine gefüllte Form.
local function drawDashedCircle(cx, cy, r)
    gfx.setColor(BLACK)
    gfx.setLineWidth(1)
    local seg = config.playerGhostDash
    local gap = config.playerGhostGap
    local step = seg + gap
    local a = 0
    while a < 360 do
        gfx.drawArc(cx, cy, r, geo.norm(a), geo.norm(a + seg))
        a = a + step
    end
    gfx.setLineWidth(1)
end

-- Gemeinsamer Ghost-Segment-Helfer für normale Brücken UND Kernbrücken
-- (Gate): zeichnet die Geistumrisse exakt gleich auf jeder radialen
-- Verbindung — Player-Geist (gestrichelter Kreis) in der Mitte (bzw. leicht
-- zurück beim Shared-Modus), Baby-Geist (dünnes Quadrat) Richtung Ziel.
local function drawGhostSegment(mode, fromR, toR, angle, dir)
    local mid = (fromR + toR) / 2
    local off = (toR - fromR) * config.ghostRadialOffset
    local px, py
    if mode == "shared" then
        -- Player folgt dem Baby: Player-Geist etwas dahinter (in Bewegungs-
        -- richtung des Transits), Baby-Geist zum Ziel hin.
        px, py = geo.polar(config.centerX, config.centerY, mid - dir * off, angle)
    else
        px, py = geo.polar(config.centerX, config.centerY, mid, angle)
    end
    drawDashedCircle(px, py, config.playerGhostRadius)
    if mode == "shared" then
        local bx, by = geo.polar(config.centerX, config.centerY, mid + dir * off, angle)
        local h = config.babyGhostHalf
        gfx.setColor(BLACK)
        gfx.fillRect(bx - h, by - h, h * 2, 1)
        gfx.fillRect(bx - h, by + h, h * 2, 1)
        gfx.fillRect(bx - h, by - h, 1, h * 2)
        gfx.fillRect(bx + h, by - h, 1, h * 2)
    end
end

-- Bridge-Silhouetten ENTFERNT : keine Player-/Baby-Geister, keine
-- Kreis-/Quadrat-Silhouetten, keine Ghost-Positionen mehr auf Brücken/Gate.
-- Brücke + Dock allein reichen; keine Ersatzmarkierung.

-- Baby (generisch, Begleiter): QUADRATISCHER RAHMEN + runder Innenkreis —
-- Referenz-Silhouette, klar getrennt vom runden Player. Screen-Space stabil
-- (das Quadrat wird NICHT mit dem Ringwinkel rotiert): oben/unten/links/rechts
-- bleiben bildschirmbezogen, kein Rotationsflimmern, sofort als Baby erkennbar.
-- Etwas kleiner als der Player (~75-85 % der Playerbreite), Gameplay-Position
-- liegt trotzdem exakt auf der Ringbahn.
-- Reaktionspriorität (rein visuell): Transit > Settle > Landing > Bridge-Ready >
-- Push > Blocked > Blink > normal. Auf der weißen Bahn gilt die Papier-Version
-- der Referenz (schwarzer Rahmen + schwarzer Mittelkreis auf Weiß), mit weißer
-- Unterlage für schwarze Randbereiche (Transit). Beim Transit maximal eine sehr
-- kleine längsgerichtete Streckung; beim Push max. 1 px Kompression in Push-
-- richtung; bei Blockade kurze Squint-Linie + minimale Kompression.
local function drawBaby(transferBridge)
    local baby = state.baby
    if not baby then
        return
    end
    local radius = Render.babyRadius()
    if not radius then
        return
    end
    local transit = Render.babyIsTransiting()
    local angle = baby.angle
    local sharedBt = Bridge.getTransit()
    if transit then
        if sharedBt and sharedBt.shared then
            angle = sharedBt.angle
        else
            angle = Baby.getTransit().angle
        end
    end

    -- Visueller Bridge-Dock-Snap: bei bereitem Transfer sitzt das Baby exakt
    -- an der Brückenachse (rein visuell, kein Gameplay-Snap/keine Bewegung).
    if transferBridge and not transit then
        angle = transferBridge.angle
    end

    -- Level-7-Spezialübergang (neue Phase): Baby kommt am Ende gemeinsam mit
    -- dem Player radial aus dem neuen Kern heraus (eigener Winkel — kein
    -- getrenntes Verschwinden/Erscheinen). Außerhalb nil -> normale State-
    -- Position.
    local pBX, pBY, pBA
    if Phase7 ~= nil and Phase7.babyPosAndAngle ~= nil then
        pBX, pBY, pBA = Phase7.babyPosAndAngle()
    end
    -- Center-Wipe (Raumwechsel): Baby kommt am Ende gemeinsam mit dem Player
    -- aus dem Mittelpunkt heraus (radial, eigener Winkel — kein getrenntes
    -- Verschwinden/Erscheinen). Außerhalb nil -> normale State-Position.
    local wBX, wBY, wBA
    if Wipe ~= nil and Wipe.babyPosAndAngle ~= nil then
        wBX, wBY, wBA = Wipe.babyPosAndAngle()
    end
    local rtBX, rtBY, rtBA = RoomTransition.babyPosAndAngle()
    local x, y
    if pBX then
        x, y, angle = pBX, pBY, pBA
    elseif wBX then
        x, y, angle = wBX, wBY, wBA
    elseif rtBX then
        x, y, angle = rtBX, rtBY, rtBA
    else
        x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    end

    -- HINTER dem gefüllten Kern (Radius < Kernrand): der Kern verdeckt das
    -- Baby — es wird nicht gezeichnet, der Transition-State läuft aber
    -- kontinuierlich weiter (kein Despawn/Respawn, kein separates
    -- Verschwinden von Player/Baby). Sobald der Radius den Kernrand wieder
    -- überschreitet, taucht das Baby an seiner kontinuierlichen Position auf.
    if Render.figureCoveredByCore(math.sqrt((x - config.centerX) ^ 2 + (y - config.centerY) ^ 2)) then
        return
    end
    -- Baby-REDESIGN : schwarze QUADRATISCHE Fläche, die sich EXAKT
    -- der Ringbahn anpasst — klare WEISSE Umrandung (1-2 px, config.baby-
    -- OutlineWidth), schwarze Innenfläche, KEINE Augen/Gesicht/Blinkanimation.
    -- Die Form folgt IMMER dem aktuellen Ringwinkel (rotierend mit der Bahn,
    -- 0 = 12 Uhr, im Uhrzeigersinn steigend), radial sauber mittig, kein
    -- seitlicher Versatz. DERSELBE Renderer überall: normale Ringbahn,
    -- Druckplatte, Bridge-Transit und Landing — keine unterschiedlichen
    -- Baby-Renderer. Baby-Breite = exakt die normale Bridge-Breite
    -- (config.babyVisualSize = bridgeBodyWidth 9); die Druckplatte ist auf
    -- diese Breite abgestimmt (Baby sitzt optisch perfekt darin). Gameplay
    -- bleibt Push-only. Während des radialen Raumwechsels skaliert die Form
    -- subtil mit (figScale), die Outline bleibt 1 px.
    local figScale = RoomTransition.figureScale()
    local size = (config.babyVisualSize or config.bridgeBodyWidth or 9) * figScale
    local ow = config.babyOutlineWidth or 1
    fillRoundRectRot(x, y, angle, size + 2 * ow, size + 2 * ow, 0, WHITE)
    fillRoundRectRot(x, y, angle, size, size, 0, BLACK)
    gfx.setColor(WHITE)
end

-- --- Weißer Text (1-Bit-Notlösung) -----------------------------------------
-- playdate.graphics.drawText malt in diesem SDK IMMER schwarz (setColor und
-- setImageDrawMode wirken NICHT auf Text; die SDK-Beispiele zeichnen Text
-- deshalb auf weißem Grund). Für weißen Text auf schwarzem Grund: Text in ein
-- Clear-Image rendern (imageWithText -> schwarze Glyphen auf transparent) und
-- mit invertiertem DrawMode zeichnen -> weiße Glyphen auf schwarzem Grund.
-- Als Font wird die gebündelte Umlaut-Font (TextUI.font) genutzt, damit auch
-- ä/ö/ü/Ä/Ö/Ü/ß korrekt erscheinen (die System-Font hat keine Umlaut-Glyphen).
function Render.drawTextWhite(text, x, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, TextUI.font)
    if not img then
        return
    end
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor(x), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Zentrierter weißer Text (Mitte 200).
function Render.drawTextWhiteCentered(text, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, TextUI.font)
    if not img then
        return
    end
    local w = img:getSize()
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor((400 - w) / 2), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- SCHWARZER Text (linksbündig): direkter DrawMode (Copy) — die schwarzen
-- Glyphen erscheinen auf hellem Grund (z. B. „ROOM X" auf dem weißen
-- Wipe-Bildschirm).
function Render.drawTextBlack(text, x, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, TextUI.font)
    if not img then
        return
    end
    img:draw(math.floor(x), math.floor(y))
end

-- Zentrierter schwarzer Text (Mitte 200) auf hellem Grund.
function Render.drawTextBlackCentered(text, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, TextUI.font)
    if not img then
        return
    end
    local w = img:getSize()
    img:draw(math.floor((400 - w) / 2), math.floor(y))
end

-- --- Öffentliches Zeichnen -------------------------------------------------

-- Zeichnet den aktuellen Raumzustand in der verbindlichen Reihenfolge.
-- Read-only gegenüber Gameplay. currentRoomIndex wird nur als
-- Darstellungsinformation gelesen (Kernwachstum, Geisterringe).

-- Raumabschluss-Systemimpuls (Atmosphäre): kurzer heller Impuls läuft nach dem
-- Lösen eines Raums (Räume 1-5 und finaler Raum-6-Moment) als 2-px-Ring vom
-- Kern zum Außenring. Wird am Beginn der Camera-Transition gezeichnet;
-- Progression/Timing bleiben unverändert.
local function drawCompletionPulse(currentRoomIndex)
    if Render.completionPulseT == nil then
        return
    end
    local t = Render.completionPulseT
    local dur = config.completionPulseDuration
    local p = t / dur
    if p > 1 then p = 1 end
    local from = Render.coreRadius(currentRoomIndex)
    local to = Render.ringRadius("outer")
    local radius = from + (to - from) * p
    gfx.setColor(WHITE)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
    gfx.setLineWidth(1)
end

function Render.drawRoom(roomComplete, currentRoomIndex)
    -- Aktive Raumnummer für Kern-Helfer (Kernrand der Kernbrücke, Landeposition
    -- am Mittelpunkt). Wird pro Frame gesetzt, bevor drawGate/Player sie lesen.
    Render.currentRoomIndex = currentRoomIndex or 1
    -- Preview-Set und Blinkphase einmal pro Frame bestimmen (rein visuell).
    local previewSet = Render.previewElementIds(roomComplete)
    local blinkOn = Render.previewBlinkOn()
    local function previewOf(id)
        return blinkOn and previewSet[id] == true
    end
    -- Baby-Transfer-Bereitschaft (rein visuell, read-only): genau das Bridge-
    -- Dock, an dem gerade ein Baby-Transfer möglich wäre (oder nil).
    local transferBridge = Baby.findTransferReadyBridge()

    -- Radialer Raumwechsel (read-only Sichtbarkeitsregeln): während der
    -- Transition lösen sich alte Puzzleobjekte gestaffelt auf (oldVisible,
    -- erste Hälfte der Bewegung) und neue bauen sich gestaffelt auf
    -- (newVisible je Kategorie, erst wenn der neue Ring fast eingerastet ist).
    -- Außerhalb der Transition ist jedes Objekt uneingeschränkt sichtbar.
    local transActive = RoomTransition.isActive()
    local transP = RoomTransition.progress() or 0
    local transOld = transActive and not RoomTransition.isNewRoomLoaded()
    local function drawIfVisible(seed, catStart, catEnd, fn)
        if transActive then
            if transOld then
                if not RoomTransition.oldVisible(transP, seed) then
                    return
                end
            elseif not RoomTransition.newVisible(transP, catStart, catEnd, seed) then
                return
            end
        end
        fn()
    end

    -- 1) Hintergrund schwarz
    gfx.clear(gfx.kColorBlack)
    -- 2) Geisterringe abgeschlossener Räume = HISTORY (gestrichelt, zurückgenommen)
    drawGhostRings(currentRoomIndex)
    -- 3) Kern
    drawCore(currentRoomIndex)
    -- 3b) Future-Ring (Design-Legende): pulsierende gestrichelte Linie des
    --     nächsten inneren Rings — nach dem Kern, damit er lesbar bleibt.
    --     Während der Transition: einmaliger Impuls, dann Wachstum (siehe
    --     drawFutureRing).
    drawFutureRing(currentRoomIndex)
    -- 4) Brücken (inaktiv zuerst, dann aktiv) + Kernbrücke/Gate: IMMER UNTER
    --    den Ringbahnen gezeichnet — die Bahnen überdecken die Brückenenden,
    --    damit Brücken/Gate die Ringlinien nicht aufbrechen. (Transitions-
    --    Sichtbarkeit über drawIfVisible unverändert.)
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "inactive" then
            drawIfVisible(b.id, config.roomTransBridgeStart, config.roomTransBridgeEnd,
                function() drawBridge(b, previewOf(b.id)) end)
        end
    end
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "active" then
            drawIfVisible(b.id, config.roomTransBridgeStart, config.roomTransBridgeEnd,
                function() drawBridge(b, previewOf(b.id)) end)
        end
    end
    -- Kernbrücke / Gate (kein Gate -> previewOf(nil) ist false)
    drawIfVisible(state.room.gate and state.room.gate.id or "gate",
        config.roomTransBridgeStart, config.roomTransBridgeEnd,
        function() drawGate(previewOf(state.room.gate and state.room.gate.id), currentRoomIndex) end)
    -- 5) Bahnen (weiß, 8 px, die sichtbaren Ringe = AKTIV, präsenteste Bahn).
    --    Während der alten Phase der Transition schmilzt der alte Außenring
    --    zur History-Linie (Breite trackWidth -> 1); der alte Innenring bleibt
    --    volle Bahn (er wird der neue Außenring). In der neuen Phase ist der
    --    neue Außenring kontinuierlich (alter Innenring), und der neue
    --    Innenring wächst aus der Future-Linie nahtlos zur vollen Bahnbreite.
    --    Der MITTELRING (3-Ring-Raum, Level 4) ist eine volle aktive Bahn
    --    (zwischen Außen- und Innenring); er existiert nur in Räumen mit
    --    rings.middle und wird in allen Phasen als volle Bahn gezeichnet.
    local function drawMiddleTrackIfPresent()
        if state.room.rings.middle ~= nil then
            drawTrack(Render.ringRadius("middle"))
        end
    end
    if transActive and transOld then
        local outerW = 1 + (config.trackWidth - 1) * RoomTransition.oldFade(transP)
        gfx.setColor(WHITE)
        gfx.setLineWidth(outerW)
        gfx.drawCircleAtPoint(config.centerX, config.centerY, Render.ringRadius("outer"))
        gfx.setLineWidth(1)
        drawMiddleTrackIfPresent()
        drawTrack(Render.ringRadius("inner"))
    elseif transActive then
        drawTrack(Render.ringRadius("outer"))
        drawMiddleTrackIfPresent()
        local innerW = RoomTransition.futureWidth(transP)
        gfx.setColor(WHITE)
        gfx.setLineWidth(innerW)
        gfx.drawCircleAtPoint(config.centerX, config.centerY, Render.ringRadius("inner"))
        gfx.setLineWidth(1)
    else
        drawTrack(Render.ringRadius("outer"))
        drawMiddleTrackIfPresent()
        drawTrack(Render.ringRadius("inner"))
    end
    -- 6) Blenden (Preview-Halo unmittelbar vor dem jeweiligen Element)
    for _, sh in ipairs(state.room.shutters) do
        drawIfVisible(sh.id, config.roomTransObjectStart, config.roomTransObjectEnd,
            function() drawShutter(sh, previewOf(sh.id)) end)
    end
    -- 7) Schalter (keine Preview am Switch selbst). EINMALSCHALTER: nach dem
    --    Verbrauch (State.consumedSwitches) läuft kurz die Verschwinde-
    --    Animation (Anspann-Puls + Zusammenfallen), danach wird der Schalter
    --    dauerhaft nicht mehr gezeichnet.
    for _, sw in ipairs(state.room.switches) do
        if sw.oneShot == true and State.consumedSwitches[sw.id] then
            if not Render.oneShotVanishDone[sw.id] then
                -- Animation bei Bedarf starten (auch im Draw-Frame, damit kein
                -- 1-Frame-Verschwinden entsteht) — rein visuell.
                if not Render.oneShotVanishAnims[sw.id] then
                    Render.oneShotVanishAnims[sw.id] = { t = 0 }
                end
                drawIfVisible(sw.id, config.roomTransObjectStart, config.roomTransObjectEnd,
                    function() drawSwitchVanish(sw) end)
            end
        else
            drawIfVisible(sw.id, config.roomTransObjectStart, config.roomTransObjectEnd,
                function() drawSwitch(sw) end)
        end
    end
    -- 8b) Druckplatten (passive Bodenelemente, momentan; unter den Marken)
    for _, p in ipairs(state.room.plates or {}) do
        drawIfVisible(p.id, config.roomTransObjectStart, config.roomTransObjectEnd,
            function() drawPlate(p) end)
    end
    -- 9) (Kausalitätsmarken entfernt: Schalter tragen keine Zusatzmarker,
    --     Zielobjekte behalten ihre eigene klare Form — ruhigeres Spielfeld.)
    -- 9b) Raumabschluss-Impuls (Atmosphäre): über den Bahnen, unter dem Spieler.
    --     Alter Inhalt -> löst sich mit den alten Objekten auf. Während des
    --     Level-7-Spezialübergangs entfällt er (dort zählt nur die Puls-/Kollaps-
    --     /Explosions-Sequenz des Kerns — kein zusätzlicher Ringimpuls).
    local phase7Active = Phase7 ~= nil and Phase7.isActive ~= nil and Phase7.isActive()
    if not phase7Active then
        drawIfVisible("pulse", config.roomTransObjectStart, config.roomTransObjectEnd,
            function() drawCompletionPulse(currentRoomIndex) end)
    end
    -- 9c3) Bridge-Silhouetten ENTFERNT : keine Player-/Baby-Geister,
    --      keine Kreis-/Quadrat-Silhouetten, keine Ghost-Positionen mehr auf
    --      den Brücken. Brücke + Dock allein reichen — keine Ersatzmarkierung.
    -- 9d) Baby (generisch, Begleiter): vor dem Spieler, damit der Spieler
    --     visuell wichtiger bleibt und das Baby als Begleiter sichtbar ist.
    -- 10) Spieler (bleibt ganz oben).
    --     Während des radialen Raumwechsels werden beide Figuren IMMER
    --     gezeichnet (Kontinuität: kein 200-300-ms-Verschwinden). Ihre
    --     Bildschirmposition interpoliert von der alten zur neuen Start-
    --     position (RoomTransition.playerPosAndAngle / babyPosAndAngle);
    --     außerhalb der Transition liefern diese nil und es gilt die normale
    --     State-Position.
    drawBaby(transferBridge)
    -- Partikelschweif des Players (unter der Figur, über der Bahn).
    drawPlayerTrail()
    drawPlayer()

    -- KEIN Text beim Levelabschluss : nach dem Erreichen des
    -- Mittelpunkts läuft NUR der weiße Kreis-Wipe (vergrößern -> Bildschirm
    -- komplett weiß -> neuer Raum verdeckt laden -> schrumpfen). Keine
    -- Levelnummer, kein Levelname, kein "Complete"/"Next Level", kein
    -- Zwischenhinweis — nichts Schriftliches.

    -- Center-Wipe (Raumwechsel): der
    -- gefüllte WEISSE Kreis wächst zentriert bei (200,120) über den KOMPLETTEN
    -- 400x240-Bildschirm (deckt die alte Welt ab — der neue Raum wird dann
    -- verdeckt geladen). Auf dem weißen Bildschirm erscheint mittig kurz
    -- „ROOM X"; danach DIREKTER CUT auf den fertigen neuen Raum (der Kreis
    -- wird NICHT wieder kleiner). Kein Ring-Morphing, kein Ripple, keine
    -- Echo-Ringe, kein Flash zusätzlich. Rein visuell, kein Gameplay-Effekt.
    local wipeR = Wipe and Wipe.radius and Wipe.radius()
    if wipeR then
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(config.centerX, config.centerY, wipeR)
        -- „ROOM X / 9" mittig auf dem weißen Bildschirm (nur in der
        -- ROOM-Phase): links der aktuell geladene Raum, rechts immer die
        -- Gesamtzahl (config.roomDisplayTotal). Schwarz auf komplett weißem
        -- Grund, horizontal und vertikal sauber zentriert, nur diese eine
        -- Zeile. „ROOM" steht NUR einmal am Anfang.
        -- Font: die natuerliche Asheville-Rounded-24 (TextUI.font);
        -- vertikale Mitte aus der Font-Hoehe.
        if Wipe.phase == "room" and Wipe.roomNumber then
            local fh = (TextUI.font and TextUI.font:getHeight()) or 22
            Render.drawTextBlackCentered("ROOM " .. Wipe.roomNumber() .. " / " .. config.roomDisplayTotal, math.floor((240 - fh) / 2))
        end
    end

    -- Level-7-Spezialübergang (neue Phase): Overlay ÜBER allem (Puls-Kern,
    -- Kollaps-Punkt, Explosions-Fragmente, dunkle Phase). In der Rebuild-
    -- Phase zeichnet das Overlay nichts — der neue Raum rendert über
    -- Camera.revealScale selbst skaliert aus dem Kern heraus.
    if phase7Active then
        Phase7.draw()
    end
end

return Render
