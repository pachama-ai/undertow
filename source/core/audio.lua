-- Audio: vollständiges Synth-Audiosystem (Phase 9.1). Alle Klänge werden
-- ausschließlich mit playdate.sound.synth erzeugt — KEINE Samples, KEINE
-- Audiodateien. Audio ist das einzige Projektmodul, das Synth-Objekte besitzt.
-- Audio entscheidet NIE Gameplay: es liest ausschließlich gemeldete Ereignisse
-- und hält nur reinen Audiozustand (Bewegungsakkumulator, Kernpuls-Timer).
-- World-Module bleiben audiounabhängig; Main (Composition Root) meldet echte
-- Gameplayresultate an Audio.
--
-- DER KERNPULS IST DIE MUSIK: kein Musiksystem, keine Tracks, keine Samples.
--
-- Keine Imports; Module werden zentral in main.lua geladen. Für Tests kann
-- Audio.init(mockSound) eine injizierbare Sound-API erhalten.

Audio = {}

local config <const> = Config

-- Injektierbare Sound-API (nil bis Audio.init; Tests setzen einen Mock).
local snd = nil

-- Synth-Stimmen (einmalig in Audio.init erzeugt; pro Klang getrennt, damit
-- sich SFX überlagern können — ein Switch-Snap darf neben einem Bridge-Extend
-- und dem leisen Kernpuls klingen).
local movementSynth = nil -- Noise, Klick
local switchSynth = nil   -- Square, zwei absteigende Töne
local bridgeSynth = nil   -- Sawtooth, Glide aufwärts
local impactSynth = nil   -- Sine, tiefer Stoß
local gateSynth = nil     -- Sine, langer tiefer Puls
local coreSynth = nil     -- Sine, Kernpuls
local bridgeCrossSynth = nil -- Square, kurzer Zip+Snap (Brückenwechsel)
local roomTransSynth = nil   -- Triangle, tiefer ziehender Sweep (Raumübergang)
local babyPushSynth = nil    -- Triangle, hoch/weich (Baby wird geschoben)
local babyImpactSynth = nil  -- Sine, dumpf (blockierter Schub ans Baby)
local babyBridgeLayerSynth = nil -- Square, hell (gemeinsamer Brückentransfer)
local bridgeGlide = nil   -- Controlsignal für den Bridge-Glide
local bridgeCrossGlide = nil -- Controlsignal für den Brückenwechsel-Sweep
local roomTransGlide = nil   -- Controlsignal für den Raumübergangs-Sweep

-- Reine Audiozustände (keine Gameplay-Wahrheit).
local moveAccum = 0         -- 15°-Akkumulator (tatsächliche Ringstrecke)
local coreTimer = 0         -- Kernpuls-Zeit
local coreRoomIndex = 1     -- Raumnummer für die Kernpuls-Frequenz
local coreCompleted = false -- nach finaler Completion keine neuen Kernpulse
local wasBlocked = false    -- Flankenerkennung Shutter-Kollision
local wasBabyPushing = false -- Flankenerkennung Baby-Push (false->true)
local wasBabyImpact = false  -- Flankenerkennung Baby-Impact (false->true)
local bridgeSettleTimer = 0 -- Brücken-End-Klick (Pass 2, einmalig pro Ausfahren)
local inited = false

-- --- öffentliche API -------------------------------------------------------

-- Initialisiert die Synth-Stimmen. Optional injizierbare Sound-API für Tests
-- (Mock mit synth.new / controlsignal.new / getCurrentTime). Defensiv: ein
-- erneutes Audio.init() ohne Argument erzeugt keine neuen Stimmen.
function Audio.init(soundAPI)
    local sndAPI = soundAPI or playdate.sound
    if inited and soundAPI == nil then
        return
    end
    inited = true
    snd = sndAPI

    movementSynth = snd.synth.new(snd.kWaveNoise)
    movementSynth:setADSR(0.001, 0.03, 0, 0.01) -- sehr schnell, kein Sustain

    switchSynth = snd.synth.new(snd.kWaveSquare)
    switchSynth:setADSR(0.002, 0.05, 0, 0.02)   -- kurz, mechanisch

    bridgeSynth = snd.synth.new(snd.kWaveSawtooth)
    bridgeSynth:setADSR(0.005, 0.0, 1.0, 0.02)
    bridgeGlide = snd.controlsignal.new()
    bridgeSynth:setFrequencyMod(bridgeGlide)

    impactSynth = snd.synth.new(snd.kWaveSine)
    impactSynth:setADSR(0.002, 0.1, 0, 0.03)    -- tiefer, schneller Abfall

    gateSynth = snd.synth.new(snd.kWaveSine)
    gateSynth:setADSR(0.01, 0.08, 0.3, 0.4)     -- langer tiefer Puls

    bridgeCrossSynth = snd.synth.new(snd.kWaveSquare)
    bridgeCrossSynth:setADSR(0.002, 0.04, 0.2, 0.02) -- kurz, etwas Körper, mechanisch
    bridgeCrossGlide = snd.controlsignal.new()
    bridgeCrossSynth:setFrequencyMod(bridgeCrossGlide)

    roomTransSynth = snd.synth.new(snd.kWaveTriangle)
    roomTransSynth:setADSR(0.02, 0.12, 0.6, 0.25)    -- mehr Körper, atmosphärisch
    roomTransGlide = snd.controlsignal.new()
    roomTransSynth:setFrequencyMod(roomTransGlide)

    babyPushSynth = snd.synth.new(snd.kWaveTriangle)
    babyPushSynth:setADSR(0.002, 0.04, 0, 0.02)   -- hoch, weich, kurz

    babyImpactSynth = snd.synth.new(snd.kWaveSine)
    babyImpactSynth:setADSR(0.002, 0.06, 0, 0.02) -- dumpf, kurz

    babyBridgeLayerSynth = snd.synth.new(snd.kWaveSquare)
    babyBridgeLayerSynth:setADSR(0.002, 0.03, 0, 0.02) -- hell, sehr kurz

    coreSynth = snd.synth.new(snd.kWaveSine)
    coreSynth:setADSR(0.01, 0.4, 0, 0.3)        -- weich, leise

    -- Für Tests sichtbare Referenzen (read-only).
    Audio.synths = {
        movement = movementSynth,
        switch = switchSynth,
        bridge = bridgeSynth,
        impact = impactSynth,
        gate = gateSynth,
        core = coreSynth,
        bridgeCross = bridgeCrossSynth,
        roomTrans = roomTransSynth,
        babyPush = babyPushSynth,
        babyImpact = babyImpactSynth,
        babyBridgeLayer = babyBridgeLayerSynth,
    }
end

-- Raumbezogene Audiowerte zurücksetzen (Spielstart, Raumwechsel): Bewegungs-
-- Rest, Kernpuls-Timer und Raumton. Stoppt KEINE laufenden einmaligen SFX —
-- ein gerade gestarteter Torübergang darf über den Raumwechsel ausklingen.
function Audio.resetRoom(roomIndex)
    moveAccum = 0
    coreTimer = 0
    coreCompleted = false
    coreRoomIndex = roomIndex or 1
    wasBlocked = false
    wasBabyPushing = false
    wasBabyImpact = false
    bridgeSettleTimer = 0
end

-- Zentrale zeitbasierte Audiologik (Main ruft dies einmal pro Frame): Kernpuls.
-- Kernpuls-Timer läuft auch während der Camera-Transition weiter (Raumwechsel
-- setzt den Timer via resetRoom neu, nicht das Camera-Ende).
function Audio.update(dt)
    if not inited then
        return
    end
    -- Brücken-End-Klick (Pass 2): einmalig nach vollständigem Ausfahren.
    if bridgeSettleTimer > 0 then
        bridgeSettleTimer = bridgeSettleTimer - dt
        if bridgeSettleTimer <= 0 then
            bridgeSettleTimer = 0
            movementSynth:playNote(
                config.audioBridgeSettleFreq,
                config.audioBridgeSettleVolume,
                config.audioBridgeSettleLen)
        end
    end
    if coreCompleted then
        return
    end
    coreTimer = coreTimer + dt
    while coreTimer >= config.audioCoreInterval do
        coreTimer = coreTimer - config.audioCoreInterval
        coreSynth:playNote(
            Audio.coreFrequency(coreRoomIndex),
            config.audioCoreVolume,
            config.audioCoreDuration)
    end
end

-- Nach der finalen Raum-3-Completion: keine weiteren neuen Kernpulse
-- (ein laufender Torübergang darf ausklingen).
function Audio.setCompleted()
    coreCompleted = true
end

-- --- Bewegungsklicken (Teil A) ---------------------------------------------

-- Echter tatsächlicher Ringweg (actualDelta, NICHT wantedDelta): akkumuliert
-- die zurückgelegte Ringstrecke und spielt je vollständige audioMovement-
-- ClickStep (15°) einen kurzen Noise-Klick (exakt Volume 0.15). Gibt die
-- Anzahl der Klicks zurück. Bridge-Transit / Camera-Transition / DockAssist
-- rufen diese Funktion NICHT auf (Main meldet nur echte Ringbewegung).
function Audio.noteRingMovement(actualDelta)
    if not inited or actualDelta == 0 then
        return 0
    end
    moveAccum = moveAccum + math.abs(actualDelta)
    local clicks = 0
    while moveAccum >= config.audioMovementClickStep do
        moveAccum = moveAccum - config.audioMovementClickStep
        clicks = clicks + 1
        -- Bei mehreren Schwellen in einem Frame retriggert derselbe Synth kurz
        -- (Synth-Puffer erlaubt nur eine wartende Note; der Zähler bleibt exakt).
        -- Sehr kurzer Impuls -> akustisch ein feines mechanisches Tick.
        movementSynth:playNote(
            config.audioMovementClickFreq,
            config.audioMovementClickVolume,
            config.audioMovementClickLen)
    end
    return clicks
end

-- --- Schaltereinrasten (Teil B) --------------------------------------------

-- Kurze Rechteckwelle, zwei kurze absteigende Töne. Nur bei echtem Switch-
-- Zustandswechsel (Main prüft switchChanges>0). isA (Pass 2): CW-Durchquerung
-- schaltet auf A (Ton minimal höher), CCW auf B (Ton exakt 1 Halbton tiefer) —
-- man hört dadurch zusätzlich die Richtung. Kein Argument = A (Rückwärtskompat.).
function Audio.playSwitchSnap(isA)
    if not inited then return end
    local n1 = (isA == false) and config.audioSwitchBNote1 or config.audioSwitchNote1
    local n2 = (isA == false) and config.audioSwitchBNote2 or config.audioSwitchNote2
    local t0 = snd.getCurrentTime()
    switchSynth:playMIDINote(n1, config.audioSwitchVolume, config.audioSwitchLen)
    switchSynth:playMIDINote(n2, config.audioSwitchVolume, config.audioSwitchLen, t0 + config.audioSwitchGap)
end

-- --- Brücke ausfahren (Teil C) ---------------------------------------------

-- Sägezahn mit Glide aufwärts über exakt config.audioBridgeDuration (0.25 s).
-- Nur bei echtem Übergang einer normalen Brücke false->true (Main prüft die
-- Elementänderungen). Freie Brücken (Raumstart) und das Gate lösen das NICHT aus.
function Audio.playBridgeExtend()
    if not inited then return end
    -- Kontinuierliche Frequenzmodulation über ein Control-Signal: linearer
    -- Anstieg von Start- zu Endfrequenz über die Brückendauer.
    bridgeGlide:clearEvents()
    bridgeGlide:addEvent(0, 0, true)
    bridgeGlide:addEvent(config.audioBridgeDuration, config.audioBridgeEndFreq - config.audioBridgeStartFreq, true)
    bridgeSynth:playNote(config.audioBridgeStartFreq, config.audioBridgeVolume, config.audioBridgeDuration)
    -- Pass 2: sehr kleines End-Klick, sobald die Brücke voll ausgefahren ist
    -- (synchron zur visuellen Settle-Phase). Einmal pro Ausfahren; kein zweiter
    -- lauter Sound, kein Neu-Start in jedem Frame.
    bridgeSettleTimer = config.bridgeExtendStage1 + config.bridgeExtendStage2 + config.bridgeExtendStage3
end

-- --- Brückenwechsel (Sound) ------------------------------------------------
-- Kurzer, mechanischer Zip+Snap beim tatsächlichen Transferstart über eine
-- normale Brücke (solo ODER gemeinsam mit Baby). Klar anders als Schalterklick
-- (klein/mechanisch) und Raumübergang (groß/atmosphärisch). Main ruft diesen
-- Hook, sobald tryUseConnection einen Transit startet (crossing) — nicht beim
-- bloßen Andocken, nicht erst nach der Landung.
function Audio.playBridgeCrossing()
    if not inited then return end
    local t0 = snd.getCurrentTime()
    bridgeCrossGlide:clearEvents()
    bridgeCrossGlide:addEvent(0, 0, true)
    bridgeCrossGlide:addEvent(config.audioBridgeCrossDuration,
        config.audioBridgeCrossEndFreq - config.audioBridgeCrossFreq, true)
    bridgeCrossSynth:playNote(
        config.audioBridgeCrossFreq,
        config.audioBridgeCrossVolume,
        config.audioBridgeCrossDuration)
    -- Pass 3 (Auftrag): kleiner mechanischer Abschluss beim Landen
    -- (zip/shff -> tick). Zeitversetzt auf demselben Synth (when = Start +
    -- Dauer) — genau EIN Transit-Sound pro Aufruf, kein Frame-Sound, kein Spam.
    bridgeCrossSynth:playNote(
        config.audioBridgeCrossTickFreq,
        config.audioBridgeCrossTickVolume,
        config.audioBridgeCrossTickLen,
        t0 + config.audioBridgeCrossDuration)
end

-- --- Raumübergang (Sound) --------------------------------------------------
-- Größerer, bedeutungsvoller Abschlusssound beim bestätigten GEMEINSAMEN
-- Raumwechsel (Gate mit Baby). Tief ziehender Sweep — atmosphärisch, kein
-- Sieg-Jingle. Main ruft den Hook beim Laden des nächsten Raums; ohne Baby am
-- Gate wird gar kein Gate genutzt, daher wird der Sound nie „zu früh" gehört.
function Audio.playRoomTransition()
    if not inited then return end
    roomTransGlide:clearEvents()
    roomTransGlide:addEvent(0, 0, true)
    roomTransGlide:addEvent(config.audioRoomTransDuration,
        config.audioRoomTransEndFreq - config.audioRoomTransFreq, true)
    roomTransSynth:playNote(
        config.audioRoomTransFreq,
        config.audioRoomTransVolume,
        config.audioRoomTransDuration)
end

-- --- Baby-Sounds (Begleiter) ---------------------------------------------

-- Weicher, hoher Ton, wenn der Spieler das Baby tatsächlich zu schieben
-- beginnt (Kontaktaufnahme). Flankenerkennung: nur beim Übergang false->true
-- (einmal pro Schub), gehaltener Kontakt erzeugt KEINEN neuen Ton pro Frame.
-- Main meldet das reale Gameplayresultat (moveResult.babyMoved).
function Audio.noteBabyPush(isPushing)
    if not inited then
        return
    end
    if isPushing then
        if not wasBabyPushing then
            babyPushSynth:playNote(
                config.audioBabyPushFreq,
                config.audioBabyPushVolume,
                config.audioBabyPushLen)
        end
        wasBabyPushing = true
    else
        wasBabyPushing = false
    end
end

-- Dumpfer, tiefer Ton, wenn ein Schub am Baby blockiert wird (Baby gegen
-- Shutter/Grenze, Spieler drückt weiter dagegen). Flankenerkennung wie oben;
-- Main meldet moveResult.blocked + Baby.isContactingPlayer().
function Audio.noteBabyImpact(impacted)
    if not inited then
        return
    end
    if impacted then
        if not wasBabyImpact then
            babyImpactSynth:playNote(
                config.audioBabyImpactFreq,
                config.audioBabyImpactVolume,
                config.audioBabyImpactLen)
        end
        wasBabyImpact = true
    else
        wasBabyImpact = false
    end
end

-- Heller, kurzer Klingelton beim Start eines GEMEINSAMEN Brückentransfers
-- (Player+Baby) — liegt über dem mechanischen Bridge-Crossing-Zip und klingt
-- wie ein freundliches „Los geht's" für das Baby. Main ruft den Hook bei
-- result.kind == "sharedBridge".
function Audio.playBabyBridgeLayer()
    if not inited then return end
    babyBridgeLayerSynth:playNote(
        config.audioBabyBridgeFreq,
        config.audioBabyBridgeVolume,
        config.audioBabyBridgeLen)
end

-- --- Aufprall an Blende (Teil D) -------------------------------------------

-- Tiefer Sinus, schneller Abfall. Nur bei NEUEM echtem Kollisionsimpuls
-- (Flankenerkennung false->true); gehaltener Input erzeugt keinen neuen Ton.
-- pendingClose (ohne Collision) erreicht diese Funktion nicht.
function Audio.noteShutterBlocked(blocked)
    if not inited then
        return
    end
    if blocked then
        if not wasBlocked then
            impactSynth:playNote(
                config.audioImpactFreq,
                config.audioImpactVolume,
                config.audioImpactDuration)
        end
        wasBlocked = true
    else
        wasBlocked = false
    end
end

-- --- Blenden-Körperton (Pass 2) -------------------------------------------

-- Beim tatsächlichen Öffnen/Schließen einer Blende (Room.movePlayer liefert
-- shutterTransitions). Schließen = tiefer/härter, Öffnen = etwas höher und
-- leiser. Einmal pro Übergang; kein Frame-Sound, kein zweiter Ton beim Settle.
-- Wiederverwendet impactSynth (kein neues Synth-Objekt).
function Audio.noteShutterTransitions(transitions)
    if not inited or not transitions then
        return
    end
    for _, t in ipairs(transitions) do
        if t.opened then
            impactSynth:playNote(
                config.audioShutterOpenFreq,
                config.audioShutterOpenVolume,
                config.audioShutterOpenDuration)
        else
            impactSynth:playNote(
                config.audioShutterCloseFreq,
                config.audioShutterCloseVolume,
                config.audioShutterCloseDuration)
        end
    end
end

-- --- Torübergang (Teil E) --------------------------------------------------

-- Langer, tiefer Puls. Nur bei erfolgreichem Gate (Main prüft das Connection-
-- Resultat). resetRoom stoppt die laufende Stimme NICHT — der Puls klingt über
-- den anschließenden Raum-/Camerawechsel aus.
function Audio.playGateTransition()
    if not inited then return end
    gateSynth:playNote(
        config.audioGateFreq,
        config.audioGateVolume,
        config.audioGateDuration)
end

-- --- Raum-Lösungs-Impuls (Atmosphäre) --------------------------------------

-- Kurzer tiefer Systemimpuls, sobald ein Raum (1-5) gelöst ist; beim finalen
-- Gate (Raum 6) ebenfalls. Wiederverwendet impactSynth (kein neuer Synth).
-- roomIndex (Pass 2): pro Raum minimal tiefer (resonanter), keine große Linie.
function Audio.playRoomCompletion(roomIndex)
    if not inited then return end
    local idx = roomIndex or 1
    local freq = config.audioCompletionFreq
        * (2 ^ (((idx - 1) * config.audioCompletionSemitoneStep) / 12))
    impactSynth:playNote(
        freq,
        config.audioCompletionVolume,
        config.audioCompletionDuration)
end

-- --- Kernpuls (Teil F) -----------------------------------------------------

-- Frequenz des Kernpulses: Raum 1 exakt 55 Hz, pro Raum +4 Halbtöne (große
-- Terz). Reine Mathematik, testbar (keine handgeschriebene Frequenzliste).
function Audio.coreFrequency(roomIndex)
    local idx = roomIndex or 1
    return config.audioCoreRoom1Freq * (2 ^ (((idx - 1) * config.audioCoreSemitoneStep) / 12))
end

-- --- Lifecycle -------------------------------------------------------------

-- Stoppt alle Synth-Stimmen (Spielneustart, spätere Menüs, Tests). Kein
-- Voice-Leak.
function Audio.stopAll()
    if not inited then return end
    movementSynth:stop()
    switchSynth:stop()
    bridgeSynth:stop()
    impactSynth:stop()
    gateSynth:stop()
    coreSynth:stop()
    bridgeCrossSynth:stop()
    roomTransSynth:stop()
    babyPushSynth:stop()
    babyImpactSynth:stop()
    babyBridgeLayerSynth:stop()
end

return Audio
