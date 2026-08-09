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
local bridgeGlide = nil   -- Controlsignal für den Bridge-Glide

-- Reine Audiozustände (keine Gameplay-Wahrheit).
local moveAccum = 0         -- 15°-Akkumulator (tatsächliche Ringstrecke)
local coreTimer = 0         -- Kernpuls-Zeit
local coreRoomIndex = 1     -- Raumnummer für die Kernpuls-Frequenz
local coreCompleted = false -- nach finaler Completion keine neuen Kernpulse
local wasBlocked = false    -- Flankenerkennung Shutter-Kollision
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
end

-- Zentrale zeitbasierte Audiologik (Main ruft dies einmal pro Frame): Kernpuls.
-- Kernpuls-Timer läuft auch während der Camera-Transition weiter (Raumwechsel
-- setzt den Timer via resetRoom neu, nicht das Camera-Ende).
function Audio.update(dt)
    if not inited or coreCompleted then
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

-- Kurze Rechteckwelle, zwei kurze absteigende Töne (Ton 2 exakt einen Halbton
-- tiefer). Nur bei echtem Switch-Zustandswechsel (Main prüft switchChanges>0;
-- kein Sound bei gleichem Zustand, kein DockAssist-/Undo-Sound).
function Audio.playSwitchSnap()
    if not inited then return end
    local t0 = snd.getCurrentTime()
    switchSynth:playMIDINote(config.audioSwitchNote1, config.audioSwitchVolume, config.audioSwitchLen)
    switchSynth:playMIDINote(config.audioSwitchNote2, config.audioSwitchVolume, config.audioSwitchLen, t0 + config.audioSwitchGap)
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
end

return Audio
