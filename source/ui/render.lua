-- Render: finales 1-Bit-Raumrendering (Phase 8.2). Zeichnet den kompletten
-- Raumzustand jeden Frame neu (whole-screen redraw, keine Sprites). KEINE
-- Zustandsänderung an Gameplay: liest ausschließlich State/Room/Camera/Bridge
-- und hält nur rein visuellen UI-State (visualTime, playerFacing). Keine
-- Imports; Module werden zentral in main.lua geladen (Room muss VOR Render
-- geladen sein, da Render Room cached).
--
-- Verbindliche Zeichenreihenfolge (ARCHITECTURE / Phase-8-Plan):
--   1. gfx.clear(kColorBlack)
--   2. Geisterringe abgeschlossener Räume (1 px, weiß, Camera-Radius)
--   3. Kern (Dithermuster, wächst mit Raumnummer, langsame Pulsation)
--   4. Bahnen (weiß, trackWidth 8, Camera-Radien)
--   5. Blenden (geschlossen: schwarz + 1 px weiße Kontur + Zähne; offen: Endmarken)
--   6. Brücken (aktiv: 6-px-Balken; eingefahren: zwei 5-px-Stummel)
--   7. Kernbrücke / Gate (inner -> Kern, mit Irisspitze)
--   8. Schalter (11-px-Scheibe, Symbol, zwei tangentiale Pfeilspitzen)
--   9. Elementmarken (dasselbe Symbol, abgeleitet vom steuernden Schalter)
--  10. Spieler (7 px, 1-px-Kontur, 3-px-Auge in Bewegungsrichtung)
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

-- B-Hold-Fortschritt für den Restart-Ring (Phase 10.4). 0 = kein Ring, 1 =
-- Schwelle erreicht. Wird NUR von main.lua gesetzt (Controller-Interaktion);
-- Render entscheidet NICHT, wann ein Restart passiert. Kein Gameplay-State.
Render.restartHoldProgress = 0

-- Read-only Setter für den Hold-Fortschritt (geclampt 0..1). Kein Effekt auf
-- State/Undo/Room/Bridge/Camera/Audio/Save.
function Render.setRestartHoldProgress(progress)
    local p = progress or 0
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    Render.restartHoldProgress = p
end

-- Spieler-/Augenanimation (Phase 8.4): reiner UI-State, keine zweite
-- Spielerposition (Ring/Winkel kommen nur aus State.player). Die
-- Brückenstreckung wird zur Laufzeit aus Bridge.isCrossing() und
-- Bridge.getTransitProgress() abgeleitet (kein eigener Bridge-Zustand).
Render.playerVisual = nil
-- Injizierbarer Zufallsgenerator [0,1) für das Blinkintervall; nil = math.random.
-- Tests setzen hier eine deterministische Funktion, um Flakes zu vermeiden.
Render.blinkRandom = nil

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
    }
end

-- Setzt den rein visuellen Spielerzustand auf Neutral (Raumstart, Undo,
-- Raumabschluss). Kein Gameplay-Effekt.
function Render.resetPlayerVisual()
    Render.playerVisual = {
        facing = 1,                          -- CW-Standard (kein Zufall)
        idleTime = 0,                        -- Stillstandszeit für Blink
        nextBlinkAt = Render.pickBlinkInterval(), -- nächster Blinktermin
        blinkFramesRemaining = 0,
        switchWidenFramesRemaining = 0,
        shutterSquintFramesRemaining = 0,
        pushFramesRemaining = 0,             -- minimaler Druck beim Baby-Push
        wasBlockedLastFrame = false,         -- Flankenerkennung Shutter-Kollision
    }
    -- Press-Animation der Schalter: keine Restzähler in neue Räume tragen.
    Render.switchPressFrames = 0
    -- Crank-Onboarding-Hinweis („Kurbel ausklappen / D-Pad“): pro Raum nur
    -- kurz sichtbar, danach räumt er die Spielfläche.
    Render.crankHintTime = config.crankHintDuration
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
-- Finaler Raum-6-Moment: friert die Ghost-Drift ein, solange aktiv (rein visuell).
Render.finalMomentActive = false
Render.finalMomentDriftTime = nil

function Render.resetObjectAnims()
    Render.shutterAnims = {}
    Render.bridgeAnims = {}
    Render.prevShutter = {}
    Render.prevBridge = {}
    Render.completionPulseT = nil
    Render.finalMomentActive = false
    Render.finalMomentDriftTime = nil
end
-- Initialer Raumstart: setzt auch die Objekt-Animationen zurück.
Render.resetPlayerVisual()
Render.resetObjectAnims()

-- --- Reine read-only Visual-Helfer (testbar) ------------------------------

-- Bildschirmradius zum Ringnamen über die Kamera (Phase 8.1): liest die
-- World-Ringnummer aus State.room.rings und bildet sie über Camera.getRadius
-- ab. Dadurch wandern alle Elemente während einer Raumtransition mit.
function Render.ringRadius(ringName)
    if ringName ~= "outer" and ringName ~= "inner" then
        error("Render.ringRadius: unbekannter Ring '" .. tostring(ringName) .. "'")
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

-- Brücken-/Gate-Visualzustand: "active" | "inactive" (aus State.elementStates).
function Render.bridgeVisualState(elementId)
    if state.elementStates[elementId] == true then
        return "active"
    end
    return "inactive"
end

-- Radial interpolierter Radius für einen Bridge-Transit (linear).
function Render.transitRadius(progress, fromRing, toRing)
    local fromRadius = Render.ringRadius(fromRing)
    local toRadius = Render.ringRadius(toRing)
    return fromRadius + (toRadius - fromRadius) * progress
end

-- Sichtbarer Spielerradius: während eines Bridge-Transits aus den
-- Transitdaten, sonst aus State.player.ring (Camera-Radius). Keine zweite
-- persistente Spielerposition. Bridge-Transit und Camera-Transition treten
-- nie gleichzeitig auf (beide sperren Input).
function Render.playerRadius()
    if Bridge.isCrossing() then
        local t = Bridge.getTransit()
        local progress = Bridge.getTransitProgress() or 0
        return Render.transitRadius(progress, t.fromRing, t.toRing)
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
    -- Crank-Onboarding-Hinweis: Restzeit abbauen (räumt die Spielfläche).
    if Render.crankHintTime ~= nil and Render.crankHintTime > 0 then
        Render.crankHintTime = Render.crankHintTime - dt
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
    -- Reaktions-Framezähler abbauen.
    if bv.pushFramesRemaining > 0 then bv.pushFramesRemaining = bv.pushFramesRemaining - 1 end
    if bv.settleFramesRemaining > 0 then bv.settleFramesRemaining = bv.settleFramesRemaining - 1 end
    if bv.landingFramesRemaining > 0 then bv.landingFramesRemaining = bv.landingFramesRemaining - 1 end
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
        or bv.landingFramesRemaining > 0 or Baby.isCrossing()
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
    -- Brücken/Gates: inactive -> active startet das Stufen-Ausfahren.
    -- prev==nil (erster Frame) erzeugt kein Schein-Ausfahren.
    for id, st in pairs(state.elementStates) do
        local cur = st == true and "active" or "inactive"
        local prev = Render.prevBridge[id]
        if cur == "active" and prev == "inactive" then
            Render.bridgeAnims[id] = { t = 0, p = 0, state = "extending", settleFrames = 0 }
        end
        Render.prevBridge[id] = cur
    end
    -- Blenden-Framezähler abbauen.
    for id, a in pairs(Render.shutterAnims) do
        a.frames = a.frames - 1
        if a.frames <= 0 then
            Render.shutterAnims[id] = nil
        end
    end
    -- Brücken-Fortschritt (dt-basiert): 0->45% schnell, Pause, 45->100% schnell,
    -- danach 1-px-Nachsetzen über config.bridgeSettleFrames.
    for id, a in pairs(Render.bridgeAnims) do
        if a.state == "extending" then
            a.t = a.t + dt
            local s1, s2, s3 = config.bridgeExtendStage1, config.bridgeExtendStage2, config.bridgeExtendStage3
            if a.t < s1 then
                a.p = (a.t / s1) * 0.45
            elseif a.t < s1 + s2 then
                a.p = 0.45
            elseif a.t >= s1 + s2 + s3 then
                a.p = 1
                a.state = "settle"
                a.settleFrames = config.bridgeSettleFrames
            else
                a.p = 0.45 + ((a.t - s1 - s2) / s3) * 0.55
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
        -- Baby-Idle: Bewegung des Players beendet die gemeinsame Ruhephase.
        if Render.babyVisual then
            Render.babyVisual.idleTime = 0
        end
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
-- leichtes Augenweiten beim echten Schieben (Room.movePlayer -> result.babyMoved).
-- direction: tatsächliche Bewegungsrichtung (+1 CW, -1 CCW). Unterbricht
-- Blink/Idle. Rein visuell, kein Gameplay-Effekt.
function Render.noteBabyPush(direction)
    local bv = Render.babyVisual
    if not bv then
        return
    end
    bv.pushFramesRemaining = config.babyPushFrames
    bv.pushDir = (direction and direction >= 0) and 1 or -1
    bv.blinkFramesRemaining = 0
    bv.idleTime = 0
    bv.nextBlinkAt = Render.pickBabyBlinkInterval()
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

-- Baby-Ziel-Einrasten (generisch, Raum 2): kurze Kompression + Augenweiten,
-- danach ruhiger lebendiger Endzustand. Rein visuell, kein Gameplay-Effekt.
function Render.noteBabySettled()
    local bv = Render.babyVisual
    if not bv then
        return
    end
    bv.settleFramesRemaining = config.babySettleFrames
    bv.blinkFramesRemaining = 0
    bv.pushFramesRemaining = 0
    bv.idleTime = 0
    bv.nextBlinkAt = Render.pickBabyBlinkInterval()
end

-- Baby-Landing nach dem Brückentransit (generisch, Raum 2): kleiner
-- Settling-Impuls, damit die Ankunft auf dem anderen Ring sichtbar ist.
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
end

-- Aktuelle Baby-Reaktion nach Priorität (rein visuell):
--   transit > settle > landing > bridge-ready > push > blink > normal.
-- Hängt von Render.babyVisual und der read-only Transfer-Bereitschaft ab.
-- Höher priorisierte Reaktionen pausieren/überschreiben niedrigere.
function Render.babyEyeState()
    local bv = Render.babyVisual or {}
    if Render.babyIsTransiting() then return "transit" end
    if bv.settleFramesRemaining and bv.settleFramesRemaining > 0 then return "settle" end
    if bv.landingFramesRemaining and bv.landingFramesRemaining > 0 then return "landing" end
    if Render.babyBridgeReady() then return "bridge" end
    if bv.pushFramesRemaining and bv.pushFramesRemaining > 0 then return "push" end
    if bv.blinkFramesRemaining and bv.blinkFramesRemaining > 0 then return "blink" end
    return "normal"
end

-- Read-only: ist gerade ein Baby-Brückentransfer bereit (Baby am aktiven
-- Bridge-Dock, Player dahinter)? Reine UI-Query, kein Gameplay-Effekt.
function Render.babyBridgeReady()
    return Baby.findTransferReadyBridge() ~= nil
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
    pv.wasBlockedLastFrame = false
    pv.idleTime = 0
    pv.nextBlinkAt = Render.pickBlinkInterval()
    Render.resetObjectAnims()
    -- Baby-Visualzustand sauber zurücksetzen (keine hängende Reaktion nach Undo).
    Render.resetBabyVisual()
end

-- Aktuelle Augenreaktion nach Priorität: Squint > Widen > Blink > normal.
function Render.currentEyeReaction()
    local pv = Render.playerVisual
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
-- Während eines gemeinsamen Transits gleitet der Player in der Baby-Lead-
-- Phase von seiner Startposition auf die Brückenachse (das Baby wartet am
-- Dock und startet voraus). Während der Hold-Phase bleibt er an seiner
-- Kontaktposition hinter dem Baby. Danach exakt auf der Achse. nil außerhalb
-- des gemeinsamen Transits.
function Render.sharedPlayerAngle()
    local bt = Bridge.getTransit()
    if not (bt and bt.active and bt.shared and bt.playerStartAngle) then
        return nil
    end
    local lead = bt.babyLead or 0
    if lead <= 0 then
        return bt.angle
    end
    local elapsed = (bt.elapsed or 0) - (bt.hold or 0)
    local p = math.min(1, math.max(0, elapsed / lead))
    local d = geo.delta(bt.playerStartAngle, bt.angle)
    return geo.norm(bt.playerStartAngle + d * p)
end

function Render.playerScreenPosition()
    local radius = Render.playerRadius()
    local angle = state.player.angle
    local sharedAngle = Render.sharedPlayerAngle()
    if sharedAngle then
        angle = sharedAngle
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
-- Während eines gemeinsamen Transits auf der Brückenachse (Player-Follow).
function Render.babyScreenPosition()
    local radius = Render.babyRadius()
    if not radius then
        return nil
    end
    local angle = state.baby.angle
    local bt = Bridge.getTransit()
    if bt and bt.active and bt.shared then
        angle = bt.angle
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
    local radius = Render.playerRadius()
    local angle = state.player.angle
    local sharedAngle = Render.sharedPlayerAngle()
    if sharedAngle then
        angle = sharedAngle
    elseif Bridge.isCrossing() then
        angle = Bridge.getTransit().angle
    end
    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    -- Gemeinsamer Brückentransit / Bridge-Ready: der Player blickt zur Brücke
    -- (radial zum anderen Ring) — als Paar mit dem Baby. Rein visuell.
    local bt = Bridge.getTransit()
    if (bt and bt.active and bt.shared)
        or (not Bridge.isCrossing() and Baby.findTransferReadyBridge() ~= nil) then
        local dx, dy = config.centerX - x, config.centerY - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            return x + dx / len * config.pupilTravel, y + dy / len * config.pupilTravel
        end
    end
    local rad = math.rad(angle)
    -- Pupillen-Versatz folgt der Facing-Richtung (bzw. Motion-Lag, falls
    -- geladen) und skaliert auf max pupilTravel. Max-Auslenkung = pupilTravel.
    local off = Render.pupilLagOffset() * config.pupilTravel
    local px = x + off * math.cos(rad)
    local py = y + off * math.sin(rad)
    -- Idle-Core-Blick (Atmosphäre): nach längerem Stillstand wandert die
    -- Pupille langsam Richtung Kern und zurück (einzelner Sinus-Halbwellen-
    -- Zyklus, danach Pause). Deterministisch, rein visuell.
    local idle = Render.playerVisual.idleTime
    if idle > config.idleGazeDelay then
        local g = math.max(0, math.sin((idle - config.idleGazeDelay) / config.idleGazeCycle * math.pi))
        if g > 0 then
            local dx, dy = config.centerX - x, config.centerY - y
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.01 then
                px = px + dx / len * config.idleGazeTravel * g
                py = py + dy / len * config.idleGazeTravel * g
            end
        end
    end
    return px, py
end

-- Baby-Augenposition: subtile Pupillenrichtung. Bridge-Ready -> radial zur
-- Brücke/anderen Ring (kein Text, die Welt erklärt die Aktion). Sonst kleine
-- Basis-Awareness Richtung Player (kein hektisches Tracking) + nach längerem
-- Stillstand stärkerer, langsamer Idle-Blick. Rein visuell, kein Gameplay.
function Render.babyEyePosition(reaction, x, y)
    if reaction == "bridge" or reaction == "transit" then
        local dx, dy = config.centerX - x, config.centerY - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            return x + dx / len * config.babyLookTravel, y + dy / len * config.babyLookTravel
        end
        return x, y
    end
    local px, py = Render.playerScreenPosition()
    local dx, dy = px - x, py - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then
        return x, y
    end
    local bv = Render.babyVisual or {}
    local idle = bv.idleTime or 0
    local g = 0
    if idle > config.idleGazeDelay then
        g = math.max(0, math.sin((idle - config.idleGazeDelay) / config.idleGazeCycle * math.pi))
    end
    local travel = config.babyLookBase + (config.babyLookTravel - config.babyLookBase) * g
    return x + dx / len * travel, y + dy / len * travel
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

-- Kernbasisradius (ohne Pulsation) für eine Raumnummer.
function Render.coreRadius(currentRoomIndex)
    local idx = currentRoomIndex or 1
    return config.coreRadius + (idx - 1) * config.coreGrowthPerRoom
end

-- Aktueller Pulsations-Offset des Kerns (rein visuell): organisches Atmen aus
-- einer langsamen Hauptwelle plus einer sehr kleinen, langsameren Atemwelle.
-- Deterministisch (reine Funktion von visualTime), kein Zufall.
function Render.corePulseOffset()
    local t = Render.visualTime
    local main = math.sin(t * 2 * math.pi / config.corePulsePeriod) * config.corePulseAmplitude
    local slow = math.sin(t * 2 * math.pi / config.corePulsePeriod2) * config.corePulseAmplitude2
    return main + slow
end

-- Baut den temporären Controller->Element-Lookup: elementId -> Symbol des
-- steuernden Schalters (onA/onB). Freie Elemente (ohne Controller) fehlen.
-- Wird pro Frame für die Elementmarken erstellt; nichts wird in State/Levels
-- gespeichert oder mutiert.
function Render.buildElementSymbolLookup()
    local lookup = {}
    for _, sw in ipairs(state.room.switches) do
        lookup[sw.onA] = sw.symbol
        lookup[sw.onB] = sw.symbol
    end
    return lookup
end

-- Zentraler Symbolrenderer (Punkt 1/2/3), identisch für Switch und
-- Elementmarken. Unbekannte Symbole werden defensiv mit einem Fehler gemeldet.
function Render.drawSymbol(symbol, x, y, size, color)
    gfx.setColor(color)
    if symbol == 1 then
        gfx.fillCircleAtPoint(x, y, math.max(1, math.floor(size * 0.4)))
    elseif symbol == 2 then
        local off = math.max(1, math.floor(size * 0.5))
        local r = math.max(1, math.floor(size * 0.3))
        gfx.fillCircleAtPoint(x - off, y, r)
        gfx.fillCircleAtPoint(x + off, y, r)
    elseif symbol == 3 then
        local w = math.max(3, math.floor(size * 1.2))
        local h = math.max(1, math.floor(size * 0.3))
        gfx.fillRect(x - math.floor(w / 2), y - math.floor(h / 2), w, h)
    else
        error("Render.drawSymbol: unbekanntes Symbol '" .. tostring(symbol) .. "'")
    end
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
        if sw.ring == playerRing then
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
        set[sw.onA] = true
        set[sw.onB] = true
    end
    return set
end

-- --- Zeichenhelfer (nur Grafik, keine Zustandsänderung) -------------------

-- 2) Geisterringe abgeschlossener Räume: 1 px weiße Kreislinien außerhalb des
-- aktiven Außenrings (Camera-Radius), teilweise vom Bildrand geschnitten.
local function drawGhostRings(currentRoomIndex)
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    local gi = 0
    for _, ringNumber in ipairs(Render.ghostRingNumbers(currentRoomIndex)) do
        gi = gi + 1
        local radius = Camera.getRadius(ringNumber)
        if radius > config.outerRadius then
            gfx.drawCircleAtPoint(config.centerX, config.centerY, radius)
            -- Extreme langsame Drift: kleine schwarze Indexmarke wandert auf
            -- der weißen Linie gegenläufig (deterministisch, rein visuell).
            local spd = config.ghostDriftSpeeds[gi] or 0.05
            local dir = config.ghostDriftDirections[gi] or -1
            -- Finaler Raum-6-Moment: Drift eingefroren (statische Zeitbasis).
            local t = Render.finalMomentActive and Render.finalMomentDriftTime or Render.visualTime
            local drift = math.fmod(t * spd * dir, 360)
            gfx.setColor(BLACK)
            gfx.drawArc(config.centerX, config.centerY, radius, drift, geo.norm(drift + config.ghostMarkDotDeg))
            gfx.setColor(WHITE)
        end
    end
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

-- 5) Blende: geschlossen = schwarzer Bogen mit 1 px weißer Kontur und zwei
-- weißen Zähnen; offen/pendingClose = weiße Bahn + zwei kleine Endmarken.
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
        -- zwei weiße Zähne an den Enden
        gfx.setColor(WHITE)
        gfx.setLineWidth(1)
        local e1x, e1y = geo.polar(config.centerX, config.centerY, radius, sA)
        local e2x, e2y = geo.polar(config.centerX, config.centerY, radius, eA)
        gfx.fillCircleAtPoint(e1x, e1y, 2)
        gfx.fillCircleAtPoint(e2x, e2y, 2)
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
    end
end

-- 6) Brücke: aktiv = durchgehender 6-px-Balken; eingefahren = zwei 5-px-Stummel.
-- previewOn: 1-px-Halo je Seite (8-px-Unterbalken). Bei inaktiver Brücke wird
-- die Lücke NICHT geschlossen (beide Stummel separat hervorgehoben).
-- transferReady: an genau dieser Brücke ist ein Baby-Transfer bereit -> kleiner
-- pulsierender Dock-Punkt am Mittelpunkt (weltbasierter Hinweis, kein Text).
local function drawBridge(b, previewOn, transferReady)
    local outerR = Render.ringRadius("outer")
    local innerR = Render.ringRadius("inner")
    local x1, y1 = geo.polar(config.centerX, config.centerY, outerR, b.angle)
    local x2, y2 = geo.polar(config.centerX, config.centerY, innerR, b.angle)
    local visual = Render.bridgeVisualState(b.id)
    if visual == "active" then
        -- Stufen-Ausfahren: die zwei Stummel wachsen 0->45% schnell, kurze
        -- Pause, 45->100% schnell und setzen 1 px nach (KLACK). Rein visuell,
        -- A-Input/Docking/Transitdauer bleiben unverändert.
        local anim = Render.bridgeAnims[b.id]
        local p = 1
        local settle = 0
        if anim then
            p = anim.p or 1
            if anim.state == "settle" then
                settle = 1
            end
        end
        local mid = (outerR + innerR) / 2
        local c1x, c1y = geo.polar(config.centerX, config.centerY, outerR - (outerR - mid) * p, b.angle)
        local c2x, c2y = geo.polar(config.centerX, config.centerY, innerR + (mid - innerR) * p, b.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2 + settle)
            gfx.drawLine(x1, y1, c1x, c1y)
            gfx.drawLine(x2, y2, c2x, c2y)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth + settle)
        gfx.drawLine(x1, y1, c1x, c1y)
        gfx.drawLine(x2, y2, c2x, c2y)
    else
        local a1x, a1y = geo.polar(config.centerX, config.centerY, outerR - config.stubLength, b.angle)
        local a2x, a2y = geo.polar(config.centerX, config.centerY, innerR + config.stubLength, b.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, a1x, a1y)
            gfx.drawLine(x2, y2, a2x, a2y)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, a1x, a1y)
        gfx.drawLine(x2, y2, a2x, a2y)
    end
    -- Subtiler Dock-Puls (Baby-Ready): kleiner SCHWARZER Punkt am Brücken-
    -- Mittelpunkt pulsiert langsam, wenn genau an dieser Brücke ein Baby-
    -- Transfer bereit ist (auf der weißen Brücke in 1-Bit sichtbar).
    if transferReady then
        local mx, my = geo.polar(config.centerX, config.centerY, (outerR + innerR) / 2, b.angle)
        local on = (Render.visualTime % config.babyReadyPulsePeriod) < (config.babyReadyPulsePeriod / 2)
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(mx, my, on and 2 or 1)
        gfx.setColor(WHITE)
    end
    gfx.setLineWidth(1)
end

-- Irisspitze: zwei kurze diagonale Linien (Chevron) am Kernende, Richtung Kern.
-- width optional für die Preview-Hervorhebung (sonst 1 px).
local function drawIrisTip(tipx, tipy, angle, width)
    local w = width or 1
    local rad = math.rad(angle)
    local rx, ry = -math.sin(rad), math.cos(rad) -- Richtung zum Kern
    local tx, ty = math.cos(rad), math.sin(rad)  -- tangential CW
    gfx.setLineWidth(w)
    gfx.drawLine(tipx, tipy, tipx + rx * 3 + tx * 3, tipy + ry * 3 + ty * 3)
    gfx.drawLine(tipx, tipy, tipx + rx * 3 - tx * 3, tipy + ry * 3 - ty * 3)
end

-- 7) Kernbrücke / Gate: Balken inner -> Kern mit Irisspitze (aktiv) oder
-- kurzer Stummel am inneren Ring (inaktiv).
-- previewOn: 1-px-Halo je Seite + verbreiterte Irisspitze; inaktives Gate
-- wird NICHT wie ausgefahren dargestellt.
local function drawGate(previewOn)
    local g = state.room.gate
    if not g then
        return
    end
    local innerR = Render.ringRadius("inner")
    local x1, y1 = geo.polar(config.centerX, config.centerY, innerR, g.angle)
    local visual = Render.bridgeVisualState(g.id)
    if visual == "active" then
        local x2, y2 = geo.polar(config.centerX, config.centerY, config.coreRadius + 4, g.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, x2, y2)
            drawIrisTip(x2, y2, g.angle, 3)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, x2, y2)
        drawIrisTip(x2, y2, g.angle)
    else
        local a1x, a1y = geo.polar(config.centerX, config.centerY, innerR - config.stubLength, g.angle)
        if previewOn then
            gfx.setColor(WHITE)
            gfx.setLineWidth(config.bridgeWidth + 2)
            gfx.drawLine(x1, y1, a1x, a1y)
        end
        gfx.setColor(WHITE)
        gfx.setLineWidth(config.bridgeWidth)
        gfx.drawLine(x1, y1, a1x, a1y)
    end
    gfx.setLineWidth(1)
end

-- Kleine Pfeilspitze (Dreieck) an Position (cx,cy) in Richtung (dirx,diry).
local function drawArrowTip(cx, cy, dirx, diry, perpx, perpy, filled)
    local apexX = cx + dirx * 3
    local apexY = cy + diry * 3
    local bx1 = cx - dirx * 1.5 + perpx * 2
    local by1 = cy - diry * 1.5 + perpy * 2
    local bx2 = cx - dirx * 1.5 - perpx * 2
    local by2 = cy - diry * 1.5 - perpy * 2
    if filled then
        gfx.fillPolygon(apexX, apexY, bx1, by1, bx2, by2)
    else
        gfx.drawPolygon(apexX, apexY, bx1, by1, bx2, by2)
    end
end

-- 8) Schalter (rein visuell, mechanisch): kleine dunkle Nocke direkt IN der
-- Ringbahn (Bahnhöhe), mit gerichteter weißer Kerbe/Spitze: Zustand A -> CW,
-- Zustand B -> CCW (Asymmetrie ohne Text lesbar). Das kleine Verknüpfungs-
-- symbol bleibt in der Nocke (optionaler Hinweis; die Form funktioniert auch
-- ohne). Bei echtem Umschalten drückt sich der Schalter config.switchPress-
-- Frames lang 1-2 px radial zur Ringmitte ein (config.switchPressOffset), nur
-- am Schalter, an dem der Spieler steht (config.switchPressProximity).
local function drawSwitch(sw)
    local radius = Render.ringRadius(sw.ring)
    local x, y = geo.polar(config.centerX, config.centerY, radius, sw.angle)
    local isA = Render.switchVisualState(sw.id) == "A"
    local rad = math.rad(sw.angle)
    local tanx, tany = math.cos(rad), math.sin(rad) -- tangential CW
    local perpx, perpy = -tany, tanx                -- radial zur Ringmitte

    -- Press-Offset: nur bei echtem Umschalten und wenn der Spieler an diesem
    -- Schalter steht (kurzer 2-Frame-Zähler). 1-2 px nach innen, kein Rest.
    local press = 0
    if Render.switchPressFrames > 0
        and state.player.ring == sw.ring
        and math.abs(geo.delta(state.player.angle, sw.angle)) <= config.switchPressProximity then
        press = config.switchPressOffset
    end
    -- Vor-Kontakt-Spannung (Atmosphäre): nähert sich der Spieler dem Schalter
    -- von außen (zwischen Blendrand und Vor-Kontakt-Bereich), spannt sich die
    -- Nocke 1 px tangential in seine Richtung an. Rein visuell, kein Hook.
    local lash = 0
    if press == 0 and state.player.ring == sw.ring then
        local d = geo.delta(state.player.angle, sw.angle)
        local absD = math.abs(d)
        local preDeg = config.switchPreContactRangePx * 180 / (math.pi * radius)
        if absD > config.switchArcWidth / 2 and absD <= config.switchArcWidth / 2 + preDeg then
            local signD = d > 0 and -1 or 1
            lash = config.switchPreContactLash * signD
        end
    end
    local bx, by = x + perpx * press + tanx * lash, y + perpy * press + tany * lash

    -- Grundkörper: dunkle Nocke auf der weißen Bahn.
    gfx.setColor(BLACK)
    gfx.fillCircleAtPoint(bx, by, config.switchBodyRadius)
    -- Richtungsspitze (weiße Kerbe in der Nocke): A -> CW, B -> CCW.
    local dir = isA and 1 or -1
    gfx.setColor(WHITE)
    drawArrowTip(
        bx + tanx * dir * (config.switchBodyRadius - 1.5),
        by + tany * dir * (config.switchBodyRadius - 1.5),
        tanx * dir, tany * dir, perpx, perpy, true)
    -- Kleines Verknüpfungssymbol (weiß) in der Nocke (optionaler Hinweis).
    Render.drawSymbol(sw.symbol, bx, by, 3, WHITE)
    gfx.setColor(WHITE)
end

-- 9) Elementmarken: dasselbe Symbol (klein, schwarz) auf jeder gesteuerten
-- Blende/Brücke/Kernbrücke. Auf geschlossener (schwarzer) Blende mit kleiner
-- weißer Trägerfläche. Freie Elemente ohne Marke.
local function drawElementMarks()
    local lookup = Render.buildElementSymbolLookup()
    -- Blenden
    for _, sh in ipairs(state.room.shutters) do
        local sym = lookup[sh.id]
        if sym then
            local radius = Render.ringRadius(sh.ring)
            local x, y = geo.polar(config.centerX, config.centerY, radius, sh.angle)
            if Render.shutterVisualState(sh.id) == "closed" then
                gfx.setColor(WHITE)
                gfx.fillCircleAtPoint(x, y, 4) -- weiße Trägerfläche
            end
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
    -- Brücken
    for _, b in ipairs(state.room.bridges) do
        local sym = lookup[b.id]
        if sym then
            local rMid = (Render.ringRadius("outer") + Render.ringRadius("inner")) / 2
            local x, y = geo.polar(config.centerX, config.centerY, rMid, b.angle)
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
    -- Kernbrücke / Gate
    if state.room.gate then
        local sym = lookup[state.room.gate.id]
        if sym then
            local rMid = (Render.ringRadius("inner") + (config.coreRadius + 4)) / 2
            local x, y = geo.polar(config.centerX, config.centerY, rMid, state.room.gate.angle)
            Render.drawSymbol(sym, x, y, 4, BLACK)
        end
    end
end

-- Gefülltes Oval (Polygon-Approximation, 8 Punkte) an (x,y) mit Halbachsen
-- rLong (radial) und rShort (tangential), Winkel 0° = 12 Uhr, CW positiv.
-- Keine Sprite-Rotation nötig; billige primitive 1-Bit-Operationen.
local function fillOval(x, y, angle, rLong, rShort, color)
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

-- 10) Spieler (neue Figur): 12-px-Kugel (weiß), 2-px schwarze Kontur, weißer
-- Halo außerhalb der Kontur (~1,5 px), 5-px-Pupille (schwarz, tangential in
-- Facing-Richtung versetzt). Wirkt wie eine Kugel in einem mechanischen Lager.
-- Bei Bridge-Transit wird der Körper radial zur Ellipse gestreckt (Start/Ende
-- Kreis, Mitte maximale Streckung; keine Hitboxänderung). Die Augenform folgt
-- der Reaktionspriorität Squint > Widen > Blink > normal; das Auge bleibt auch
-- während der Streckung sichtbar.
local function drawPlayer()
    local crossing = Bridge.isCrossing()
    local x, y, angle = Render.playerScreenPosition()

    -- Radien der visuellen Schichten (Kugel -> Kontur -> Halo)
    local rBall = config.playerRadius
    local rContour = rBall + config.playerStroke
    local rHalo = rContour + config.playerHalo

    -- Reaktion früh bestimmen (Körperform kann von Squint abhängen).
    local reaction = Render.currentEyeReaction()

    -- Körper (Halo außen, dann Kontur, dann Kugel; Überlagerung ergibt die
    -- konzentrischen Ringe)
    if crossing then
        local stretch = Render.bridgeStretch(Bridge.getTransitProgress())
        local sh = math.max(2.5, stretch * 0.25)
        fillOval(x, y, angle, rHalo + stretch, rHalo - sh, WHITE)      -- Halo
        fillOval(x, y, angle, rContour + stretch, rContour - sh, BLACK) -- Kontur
        fillOval(x, y, angle, rBall + stretch, rBall - sh, WHITE)       -- Kugel
    elseif reaction == "squint" then
        -- Impact-Kompression (Atmosphäre): Körper kurz 1 px radial gestaucht,
        -- tangential unverändert. Nur 2-6 Frames, keine Positionsänderung.
        local comp = 1
        fillOval(x, y, angle, rHalo - comp, rHalo, WHITE)
        fillOval(x, y, angle, rContour - comp, rContour, BLACK)
        fillOval(x, y, angle, rBall - comp, rBall, WHITE)
    elseif Render.playerVisual.pushFramesRemaining > 0 then
        -- Minimaler Druck beim Baby-Push (Beziehung): 1 px radiale Kompression,
        -- der Blick bleibt fokussiert nach vorn (Richtung Baby). Nicht stärker
        -- als die Babyreaktion.
        local comp = 1
        fillOval(x, y, angle, rHalo - comp, rHalo, WHITE)
        fillOval(x, y, angle, rContour - comp, rContour, BLACK)
        fillOval(x, y, angle, rBall - comp, rBall, WHITE)
    else
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(x, y, rHalo)
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(x, y, rContour)
        gfx.setColor(WHITE)
        gfx.fillCircleAtPoint(x, y, rBall)
    end

    -- Pupille/Auge (bleibt während Streckung sichtbar)
    local ex, ey = Render.playerEyePosition()
    local rad = math.rad(angle)
    local tx, ty = math.cos(rad), math.sin(rad) -- tangential CW
    if reaction == "squint" then
        -- Zusammenkneifen: kurze schmale tangentiale Lidlinie
        gfx.setColor(BLACK)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * 2, ey - ty * 2, ex + tx * 2, ey + ty * 2)
        gfx.setLineWidth(1)
    elseif reaction == "widen" then
        -- Augenweiten: größere Pupille
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ex, ey, config.pupilRadius + 1)
    elseif reaction == "blink" then
        -- Blink: geschlossene Lidlinie (kürzer als Squint)
        gfx.setColor(BLACK)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * 1.5, ey - ty * 1.5, ex + tx * 1.5, ey + ty * 1.5)
        gfx.setLineWidth(1)
    else
        -- normal: 5-px-Pupille
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ex, ey, config.pupilRadius)
    end
    gfx.setColor(WHITE)
end

-- Baby-Ziel (generisch, Raum 2): kleine Andockmulde auf der Zielbahn.
-- Leer = schmalerer schwarzer Bogen (Vertiefung) mit zwei weißen Randmarken
-- (○-artige Mulde); besetzt = das Baby sitzt sichtbar darin (Zeichenreihenfolge:
-- Mulde vor dem Baby). Kein Text, kein Symbol.
local function drawBabyGoal()
    local babyDef = state.room.baby
    if not babyDef then
        return
    end
    local radius = Render.ringRadius(babyDef.goal.ring)
    local ang = babyDef.goal.angle
    local arc = config.babyGoalArcDeg
    local sA = geo.norm(ang - arc / 2)
    local eA = geo.norm(ang + arc / 2)
    -- Vertiefung in der weißen Bahn: schmalerer schwarzer Bogen, die Bahn bleibt
    -- an den Rändern sichtbar -> dezent als Ruheplatz lesbar, nicht als Blende.
    gfx.setColor(BLACK)
    gfx.setLineWidth(config.trackWidth - 4)
    gfx.drawArc(config.centerX, config.centerY, radius, sA, eA)
    gfx.setLineWidth(1)
    -- Bewusst unauffällig: KEINE weißen Dock-Brackets (die „○ -> fertig“-Metapher
    -- wird nicht weiter betont; Spieler und Baby reisen als Paar weiter).
    gfx.setColor(WHITE)
end

-- Baby (generisch, Raum 2): kleine Kugel derselben Art wie der Spieler
-- (~62 % des Player-Durchmessers), 1-px-Kontur, schwacher Halo, kleines Auge.
-- Reaktionspriorität (rein visuell): Bridge-Transit > Goal-Settle > Landing >
-- Bridge-Ready > Push > Blink > Idle. Beim Brückentransit radial interpoliert,
-- beim Push tangential komprimiert (mit kurzer Rückfederung), am bereiten
-- Bridge-Dock radial zur Brücke gezogen und leicht pulsierend (weltbasierter
-- "A"-Hinweis, kein Text). Kein autonomes Laufen, keine KI.
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

    local x, y = geo.polar(config.centerX, config.centerY, radius, angle)
    local bv = Render.babyVisual or {}
    local reaction = Render.babyEyeState()

    -- Körperparameter (rLong radial, rShort tangential).
    local rLong = config.babyRadius
    local rShort = config.babyRadius
    local radialPull = 0
    if reaction == "settle" or reaction == "landing" then
        -- kleine Kompression beim Einrasten/Landen
        rLong = rLong - 1
        rShort = rShort - 1
    elseif reaction == "push" then
        -- Kompression in Schieberichtung (tangential); letzter Frame = Rückfederung
        local squash = 1
        if bv.pushFramesRemaining == 1 then
            squash = -0.5
        end
        rShort = rShort - squash
    elseif reaction == "bridge" then
        -- minimaler Körperzug zur Brücke + subtiler Puls
        radialPull = config.babyReadyPull
        local pulse = config.babyReadyPulse * (0.5 + 0.5 * math.sin(Render.visualTime * (2 * math.pi / config.babyReadyPulsePeriod)))
        rLong = rLong + pulse
        rShort = rShort + pulse
    end
    -- Transit: leichte radiale Streckung während der Überquerung (gemeinsam
    -- oder solo; eine gemeinsame Progress-Wahrheit).
    if transit then
        local p = Render.babyTransitProgress() or 0
        local stretch = math.sin(math.pi * p) * 1.5
        rLong = rLong + stretch
        rShort = rShort - stretch * 0.4
    end

    -- Bridge-Ready: Körper 1 px radial zur Brücke ziehen.
    if radialPull ~= 0 then
        x, y = geo.polar(config.centerX, config.centerY, radius - radialPull, angle)
    end

    -- Konzentrische Ellipsen (Halo, Kontur, Körper); fillOval hält die
    -- Kompression/Streckung in 1-Bit sauber lesbar.
    local stroke = config.babyStroke
    local halo = config.babyHalo
    local function layer(rl, rs, color)
        fillOval(x, y, angle, rl, rs, color)
    end
    layer(rLong + stroke + halo, rShort + stroke + halo, WHITE)
    layer(rLong + stroke, rShort + stroke, BLACK)
    layer(rLong, rShort, WHITE)

    -- Auge: Blink = kurze tangentiale Lidlinie (Player-Konvention); sonst
    -- Pupille, bei Push/Settle/Landing/Transit kurz weiter.
    local ex, ey = Render.babyEyePosition(reaction, x, y)
    if reaction == "blink" then
        local rad = math.rad(angle)
        local tx, ty = math.cos(rad), math.sin(rad)
        gfx.setColor(BLACK)
        gfx.setLineWidth(1)
        gfx.drawLine(ex - tx * 1.5, ey - ty * 1.5, ex + tx * 1.5, ey + ty * 1.5)
        gfx.setLineWidth(1)
    else
        local pr = config.babyPupilRadius
        if reaction == "push" or reaction == "settle" or reaction == "landing" or reaction == "transit" then
            pr = pr + 0.5
        end
        gfx.setColor(BLACK)
        gfx.fillCircleAtPoint(ex, ey, pr)
    end
    gfx.setColor(WHITE)
end

-- 11) B-Hold-Fortschrittsring (Phase 10.4): weißer 1-px-Bogen um die sichtbare
--     Spielerfigur, Start bei 12 Uhr, im Uhrzeigersinn 0°->360° (Spiel-Winkel-
--     konvention, entspricht drawArc). progress=0 -> nichts, 0.5 -> halber
--     Bogen, ~1 -> fast geschlossen. Kein gefüllter Kreis, keine Graustufen;
--     die Figur bleibt sichtbar. Rein read-only (nur Zeichnen).
local function drawRestartHoldRing()
    local p = Render.restartHoldProgress or 0
    if p <= 0 then
        return
    end
    local x, y = Render.playerScreenPosition()
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    gfx.drawArc(x, y, config.restartHoldRingRadius, 0, math.min(360, p * 360))
    gfx.setLineWidth(1)
end

-- 12) Crank-eingeklappt-Hinweis (Phase 10.4): kompakte 1-Bit-Box (schwarze
--     Fläche, 1-px weiße Kontur, weißer Text) in der oberen rechten Ecke.
--     Sichtbar nur im Gameplay mit eingeklappter Kurbel und solange der Raum
--     nicht abgeschlossen ist (Startmenü zeichnet nie diese Szene). Rein
--     visuell: sperrt KEINE Eingabe (D-Pad/A/B/Undo/Hold laufen weiter).
--     Kein Fade, keine Pulsation, kein Sound.
local function drawCrankOverlay(roomComplete)
    local docked = playdate.isCrankDocked()
    local hintT = Render.crankHintTime or 0
    if not docked or roomComplete or hintT <= 0 then
        return
    end
    local bx = config.crankOverlayX
    local by = config.crankOverlayY
    local bw = config.crankOverlayWidth
    local bh = config.crankOverlayHeight
    gfx.setColor(BLACK)
    gfx.fillRect(bx, by, bw, bh)
    gfx.setColor(WHITE)
    gfx.drawRect(bx, by, bw, bh)
    local font = gfx.getSystemFont()
    gfx.setFont(font)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText("Kurbel ausklappen", bx + 4, by + 3)
    gfx.drawText("oder D-Pad benutzen", bx + 4, by + 3 + config.menuFontHeight)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
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
    -- Preview-Set und Blinkphase einmal pro Frame bestimmen (rein visuell).
    local previewSet = Render.previewElementIds(roomComplete)
    local blinkOn = Render.previewBlinkOn()
    local function previewOf(id)
        return blinkOn and previewSet[id] == true
    end
    -- Baby-Transfer-Bereitschaft (rein visuell, read-only): genau das Bridge-
    -- Dock, an dem gerade ein Baby-Transfer möglich wäre (oder nil).
    local transferBridge = Baby.findTransferReadyBridge()

    -- 1) Hintergrund schwarz
    gfx.clear(gfx.kColorBlack)
    -- 2) Geisterringe abgeschlossener Räume
    drawGhostRings(currentRoomIndex)
    -- 3) Kern
    drawCore(currentRoomIndex)
    -- 4) Bahnen (weiß, 8 px, beide sichtbare Ringe)
    drawTrack(Render.ringRadius("outer"))
    drawTrack(Render.ringRadius("inner"))
    -- 4b) Baby-Ziel-Mulde (generisch, Raum 2): auf der Zielbahn, unter den
    --     Brücken/Gate, damit sie nie von ausgefahrenen Balken verdeckt wird.
    drawBabyGoal()
    -- 5) Blenden (Preview-Halo unmittelbar vor dem jeweiligen Element)
    for _, sh in ipairs(state.room.shutters) do
        drawShutter(sh, previewOf(sh.id))
    end
    -- 6) Brücken (inaktiv zuerst, dann aktiv)
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "inactive" then
            drawBridge(b, previewOf(b.id), (transferBridge ~= nil and transferBridge.id == b.id) or false)
        end
    end
    for _, b in ipairs(state.room.bridges) do
        if Render.bridgeVisualState(b.id) == "active" then
            drawBridge(b, previewOf(b.id), (transferBridge ~= nil and transferBridge.id == b.id) or false)
        end
    end
    -- 7) Kernbrücke / Gate (kein Gate -> previewOf(nil) ist false)
    drawGate(previewOf(state.room.gate and state.room.gate.id))
    -- 8) Schalter (keine Preview am Switch selbst)
    for _, sw in ipairs(state.room.switches) do
        drawSwitch(sw)
    end
    -- 9) Elementmarken (bleiben über den Preview-Halos)
    drawElementMarks()
    -- 9b) Raumabschluss-Impuls (Atmosphäre): über den Bahnen, unter dem Spieler.
    drawCompletionPulse(currentRoomIndex)
    -- 9c) Baby (generisch, Raum 2): vor dem Spieler, damit der Spieler visuell
    --     wichtiger bleibt und das Baby in seiner Mulde sichtbar ist.
    drawBaby(transferBridge)
    -- 10) Spieler (bleibt ganz oben)
    drawPlayer()
    -- 11) B-Hold-Restart-Fortschrittsring (direkt um die Figur, 1-px-Bogen von
    --     12 Uhr im Uhrzeigersinn 0°->360°, nur bei aktivem Hold) + globales
    --     Crank-eingeklappt-Hinweis-Overlay (rein visuell, 1-Bit).
    drawRestartHoldRing()
    drawCrankOverlay(roomComplete)

    -- „ROOM COMPLETE" nur außerhalb des finalen Raum-6-Stillstands (dort soll
    -- die Welt ruhig stehen, ohne Spieltext).
    if roomComplete and not Render.finalMomentActive then
        gfx.setColor(WHITE)
        gfx.drawText("ROOM COMPLETE", 150, 30)
    end
end

return Render
