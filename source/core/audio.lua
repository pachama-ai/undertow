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
-- NEUE Stimmen (AUFTRAG „Palette erweitern statt ersetzen"): tone = Triangle
-- + Glide (Menü, Platte, weiche UI-Sweeps), special = Sine + Glide (Restart,
-- Phase-7-Spezialübergang, finales Ausschwingen).
local toneSynth = nil        -- Triangle, weiche/freundliche Aktionen
local toneGlide = nil
local specialSynth = nil     -- Sine, Tiefe/Raum/große Zustandsänderungen
local specialGlide = nil
local wooshSynth = nil       -- Sawtooth, breiter Luft-/Energie-Woosh (Levelübergang)
local wooshGlide = nil

-- Reine Audiozustände (keine Gameplay-Wahrheit).
local moveAccum = 0         -- 15°-Akkumulator (tatsächliche Ringstrecke)
local coreTimer = 0         -- Kernpuls-Zeit
local coreRoomIndex = 1     -- Raumnummer für die Kernpuls-Frequenz
local coreCompleted = false -- nach finaler Completion keine neuen Kernpulse
local coreHold = 0          -- MIXING: Sekunden ohne Kernpuls (große Übergänge/ROOM-Anzeige)
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
    -- Pass: mehr Sustain (0.55 statt 0.2) -> der Zip/Shff-Körper ist präsent,
    -- nicht nur der Attack; weiterhin kurz und mechanisch (kein Piep, kein Sweep).
    bridgeCrossSynth:setADSR(0.002, 0.03, 0.55, 0.03)
    bridgeCrossGlide = snd.controlsignal.new()
    bridgeCrossSynth:setFrequencyMod(bridgeCrossGlide)

    roomTransSynth = snd.synth.new(snd.kWaveTriangle)
    -- Pass: mehr Körper/Präsenz (schnellerer Attack, Sustain 0.85, längeres
    -- Release) — der Charakter (atmosphärischer tiefer Sweep) bleibt erhalten.
    roomTransSynth:setADSR(0.015, 0.06, 0.85, 0.35)
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

    -- NEUE Stimmen (Menü/Platte + Restart/Phase7/finales Ende).
    toneSynth = snd.synth.new(snd.kWaveTriangle)
    toneSynth:setADSR(0.005, 0.03, 0.6, 0.05)
    toneGlide = snd.controlsignal.new()
    toneSynth:setFrequencyMod(toneGlide)

    specialSynth = snd.synth.new(snd.kWaveSine)
    specialSynth:setADSR(0.01, 0.05, 0.7, 0.15)
    specialGlide = snd.controlsignal.new()
    specialSynth:setFrequencyMod(specialGlide)

    -- LEVELÜBERGANG-WOOSH: breiter weicher Saw-Sweep, langsames Ausklingen
    -- (Release 0.25) — klingt auf dem vollständig weißen Bildschirm aus.
    wooshSynth = snd.synth.new(snd.kWaveSawtooth)
    wooshSynth:setADSR(0.01, 0.06, 0.8, 0.25)
    wooshGlide = snd.controlsignal.new()
    wooshSynth:setFrequencyMod(wooshGlide)

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
        tone = toneSynth,
        special = specialSynth,
        woosh = wooshSynth,
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
    -- MIXING (AUFTRAG): während großer Übergänge (Center-Wipe-ROOM-Anzeige,
    -- Restart, Phase-7-Sequenz) pausiert der Kernpuls — komplette Ruhe bei der
    -- ROOM-X-/ROOM-10-Anzeige; danach startet er automatisch wieder.
    if coreHold > 0 then
        coreHold = coreHold - dt
        if coreHold < 0 then
            coreHold = 0
        end
        return
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

-- Nach der finalen Completion: keine weiteren neuen Kernpulse (ein laufender
-- Torübergang darf ausklingen).
function Audio.setCompleted()
    coreCompleted = true
end

-- MIXING (AUFTRAG): unterdrückt den Kernpuls für `seconds` Sekunden (große
-- Übergänge, ROOM-X-/ROOM-10-Anzeige = komplette Ruhe). Danach läuft er
-- automatisch weiter.
function Audio.setCoreHold(seconds)
    coreHold = math.max(0, seconds or 0)
end

-- Helfer: Note mit linearem Frequenz-Glide über die volle Dauer.
local function glideNote(synth, glide, startFreq, endFreq, duration, volume)
    glide:clearEvents()
    glide:addEvent(0, 0, true)
    glide:addEvent(duration, endFreq - startFreq, true)
    synth:playNote(startFreq, volume, duration)
end

-- --- Menü / Startanimation ------------------------------------------------
-- MENU MOVE: sehr kleiner trockener Square-Tick. main.lua meldet ihn NUR,
-- wenn sich die gewählte Menüoption tatsächlich ändert (edge, nie pro Frame).
function Audio.playMenuMove()
    if not inited then return end
    switchSynth:playNote(
        config.audioMenuMoveFreq,
        config.audioMenuMoveVolume,
        config.audioMenuMoveLen)
end

-- MENU CONFIRM: kurzer Triangle-Sweep 180->260 Hz bei A im Startscreen.
function Audio.playMenuConfirm()
    if not inited then return end
    glideNote(toneSynth, toneGlide,
        config.audioMenuConfirmStart, config.audioMenuConfirmEnd,
        config.audioMenuConfirmDuration, config.audioMenuConfirmVolume)
end

-- STARTANIMATION Rise: sehr leiser kontinuierlicher Triangle-Sweep 90->150 Hz
-- über die Ring-Zeichenzeit (einmal beim Einblenden des Menüs; kein Ton pro
-- Segment). duration = config.menuDrawDuration.
function Audio.playMenuRise(duration)
    if not inited then return end
    glideNote(toneSynth, toneGlide,
        config.audioMenuRiseStart, config.audioMenuRiseEnd,
        duration or config.menuDrawDuration, config.audioMenuRiseVolume)
end

-- STARTANIMATION Fill: kurzer tiefer Abschlussimpuls, wenn der Ring sich nach
-- innen zur Scheibe füllt.
function Audio.playMenuFillImpulse()
    if not inited then return end
    impactSynth:playNote(
        config.audioMenuFillFreq,
        config.audioMenuFillVolume,
        config.audioMenuFillDuration)
end

-- --- Druckplatte ----------------------------------------------------------
-- PLATE ON: Triangle steigt 170->210 Hz (leichtes mechanisches Einrasten).
function Audio.playPlateOn()
    if not inited then return end
    glideNote(toneSynth, toneGlide,
        config.audioPlateOnStart, config.audioPlateOnEnd,
        config.audioPlateLen, config.audioPlateOnVolume)
end

-- PLATE OFF: Triangle fällt 210->160 Hz.
function Audio.playPlateOff()
    if not inited then return end
    glideNote(toneSynth, toneGlide,
        config.audioPlateOffStart, config.audioPlateOffEnd,
        config.audioPlateLen, config.audioPlateOffVolume)
end

-- PLATE-Transitions (EDGE-Trigger, AUFTRAG): main.lua meldet jede echte
-- Zustandskante false->true (on) bzw. true->false (off). Nie pro Frame.
function Audio.notePlateTransitions(transitions)
    if not inited or not transitions then return end
    for _, t in ipairs(transitions) do
        if t.on then
            Audio.playPlateOn()
        else
            Audio.playPlateOff()
        end
    end
end

-- --- Einmalschalter -------------------------------------------------------
-- ONE-SHOT SWITCH: zweistufiger Square-Snap (MIDI 74 -> 67) + tiefer Sine-
-- Tick — „Entscheidung verriegelt". Deutlich anders als der Doppelschalter.
function Audio.playOneShotSnap()
    if not inited then return end
    local t0 = snd.getCurrentTime()
    switchSynth:playMIDINote(config.audioOneShotNote1, config.audioOneShotVolume, config.audioOneShotLen)
    switchSynth:playMIDINote(config.audioOneShotNote2, config.audioOneShotVolume, config.audioOneShotLen, t0 + config.audioOneShotGap)
    impactSynth:playNote(
        config.audioOneShotTickFreq,
        config.audioOneShotTickVolume,
        config.audioOneShotTickLen,
        t0 + config.audioOneShotGap + config.audioOneShotLen)
end

-- --- Bridge Retract / One-Use Collapse ------------------------------------
-- BRIDGE RETRACT (deaktivieren/verschwinden): Sägezahn ABWÄRTS 320->160 Hz.
-- Akustisch sofort klar: hoch = Bridge entsteht, runter = Bridge verschwindet.
function Audio.playBridgeRetract()
    if not inited then return end
    glideNote(bridgeSynth, bridgeGlide,
        config.audioBridgeRetractStart, config.audioBridgeRetractEnd,
        config.audioBridgeRetractDuration, config.audioBridgeRetractVolume)
end

-- ONE-USE BRIDGE COLLAPSE: Sägezahn 260->90 Hz — erst NACH dem abgeschlossenen
-- Transit, wenn die Einmal-Brücke verbraucht wird (main.lua meldet das).
function Audio.playOneUseCollapse()
    if not inited then return end
    glideNote(bridgeSynth, bridgeGlide,
        config.audioCollapseStart, config.audioCollapseEnd,
        config.audioCollapseDuration, config.audioCollapseVolume)
end

-- --- Tutorial-Infoleiste --------------------------------------------------
-- Leiste erscheint: extrem kleiner Triangle-Tick (ruhig, kein großer Sound).
function Audio.playTutorialAppear()
    if not inited then return end
    babyPushSynth:playNote(
        config.audioTutorialTickFreq,
        config.audioTutorialTickVolume,
        config.audioTutorialTickLen)
end

-- A = continue: kleiner neutraler Square-Tick.
function Audio.playTutorialContinue()
    if not inited then return end
    switchSynth:playNote(
        config.audioTutorialContinueFreq,
        config.audioTutorialContinueVolume,
        config.audioTutorialContinueLen)
end

-- --- Restart (B) ----------------------------------------------------------
-- Phase 1 (Collapse): Sine-Sweep 150->55 Hz, synchron zur Kollaps-Animation.
function Audio.playRestartCollapse()
    if not inited then return end
    glideNote(specialSynth, specialGlide,
        config.audioRestartCollapseStart, config.audioRestartCollapseEnd,
        config.audioRestartCollapseDuration, config.audioRestartCollapseVolume)
end

-- Phase 2 (kurzer Moment am Core): sehr kurzer tiefer Impuls bei 55 Hz.
function Audio.playRestartCore()
    if not inited then return end
    impactSynth:playNote(
        config.audioRestartCoreFreq,
        config.audioRestartCoreVolume,
        config.audioRestartCoreDuration)
end

-- Phase 3 (Rebuild): Sägezahn 90->220 Hz (Energie/Materialisierung).
function Audio.playRestartRebuild()
    if not inited then return end
    glideNote(bridgeSynth, bridgeGlide,
        config.audioRestartRebuildStart, config.audioRestartRebuildEnd,
        config.audioRestartRebuildDuration, config.audioRestartRebuildVolume)
end

-- --- LEVEL-7-SPEZIALÜBERGANG ----------------------------------------------
-- main.lua meldet jeden Phasenwechsel (edge-getriggert). Akustisch besonders,
-- aber minimalistisch; der Kernpuls ist während der Sequenz pausiert.
function Audio.notePhase7Phase(phase, roomIndex)
    if not inited then return end
    local base = Audio.coreFrequency(roomIndex or 7)
    local t0 = snd.getCurrentTime()
    if phase == "pulse" then
        -- 3 Kern-Pulse: jeder etwas höher/dichter/stärker, der letzte deutlich.
        specialSynth:playNote(base * config.audioP7Pulse1Mult, config.audioP7PulseVol1, config.phase7Pulse1Dur)
        specialSynth:playNote(base * config.audioP7Pulse2Mult, config.audioP7PulseVol2, config.phase7Pulse2Dur, t0 + config.phase7Pulse1Dur)
        specialSynth:playNote(base * config.audioP7Pulse3Mult, config.audioP7PulseVol3, config.phase7Pulse3Dur, t0 + config.phase7Pulse1Dur + config.phase7Pulse2Dur)
    elseif phase == "collapse" then
        -- Kern zieht sich zum Punkt: Sine-Sweep base -> 38 Hz.
        glideNote(specialSynth, specialGlide,
            base, config.audioP7CollapseEnd,
            config.audioP7CollapseDuration, config.audioP7CollapseVolume)
    elseif phase == "explode" then
        -- KEINE klassische Explosion: grober Noise-Impuls + tiefer Sine-Impact
        -- + abfallender Saw-Sweep (Ringfragmente fliegen).
        movementSynth:playNote(
            config.audioP7ExplosionNoiseFreq,
            config.audioP7ExplosionNoiseVolume,
            config.audioP7ExplosionNoiseLen)
        impactSynth:playNote(
            config.audioP7ExplosionImpactFreq,
            config.audioP7ExplosionImpactVolume,
            config.audioP7ExplosionImpactDuration)
        glideNote(bridgeSynth, bridgeGlide,
            config.audioP7FragStart, config.audioP7FragEnd,
            config.audioP7FragDuration, config.audioP7FragVolume)
    elseif phase == "rebuild" then
        -- Neuer Kern erscheint: ein einzelner klarer Sine-Puls — neue Phase.
        specialSynth:playNote(
            base * config.audioP7NewCoreMult,
            config.audioP7NewCoreVolume,
            config.audioP7NewCoreDuration)
    end
end

-- --- FINALES ENDE (letzter Raum) ------------------------------------------
-- Etwas längerer, abschließender Room-Transition-Sweep (statt des normalen).
function Audio.playRoomTransitionFinal()
    if not inited then return end
    glideNote(roomTransSynth, roomTransGlide,
        config.audioRoomTransFreq, config.audioRoomTransEndFreq,
        config.audioFinalTransDuration, config.audioRoomTransVolume)
end

-- Outro: Sine gleitet langsam von der aktuellen Room-Core-Frequenz auf die
-- Ausgangsfrequenz 55 Hz (1.5-2.0 s) — „das System kommt zur Ruhe". Keine
-- Melodie, kein Ta-da.
function Audio.playFinalSettle(roomIndex)
    if not inited then return end
    local base = Audio.coreFrequency(roomIndex or 1)
    glideNote(specialSynth, specialGlide,
        base, config.audioCoreRoom1Freq,
        config.audioFinalSettleDuration, config.audioFinalSettleVolume)
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
    bridgeSettleTimer = config.bridgeExtendDuration
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

-- --- LEVELÜBERGANG-WOOSH (normaler Center-Wipe) ----------------------------
-- Der große WEISSE Kreis wächst über den Bildschirm — dieses breite, weiche
-- Luft-/Energie-Woosh läuft exakt mit dem Wachsen mit (Main triggert ihn beim
-- Start des Wipe-Grows) und klingt auf dem vollständig weißen Bildschirm aus
-- (Sustain + langes Release der Woosh-Stimme). KEINE Explosion, kein Boom.
-- Zwei Schichten: sehr kurzer Noise-Einsatz (Luft) + Saw-Sweep 120 -> 420 Hz.
-- Genau EIN Woosh pro Übergang; beim Cut gibt es KEINEN zweiten Woosh.
function Audio.playTransitionWoosh()
    if not inited then return end
    local t0 = snd.getCurrentTime()
    -- Luft-Schicht: sehr kurz eingeblendetes Noise („Kreis bläst auf").
    movementSynth:playNote(
        config.audioWooshNoiseFreq,
        config.audioWooshNoiseVolume,
        config.audioWooshNoiseLen,
        t0)
    -- Energie-Schicht: breiter Saw-Sweep tief -> höher über die volle Dauer.
    wooshGlide:clearEvents()
    wooshGlide:addEvent(0, 0, true)
    wooshGlide:addEvent(config.audioWooshDuration,
        config.audioWooshEnd - config.audioWooshStart, true)
    wooshSynth:playNote(
        config.audioWooshStart,
        config.audioWooshVolume,
        config.audioWooshDuration)
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
    toneSynth:stop()
    specialSynth:stop()
    wooshSynth:stop()
end

return Audio
