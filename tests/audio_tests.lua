-- Tests für source/core/audio.lua (Phase 9.1): deterministische Logik- und
-- Ereignistests mit einem kleinen Synth-Testdouble. Akustische Qualität wird
-- NICHT aus Unit-Tests abgeleitet (echter Simulator-Smoke + Hörtest separat).
-- Erwartet, dass core/config, core/state, core/undo, world/room, world/bridge,
-- data/levels und core/audio per import geladen wurden (run_tests.ps1).

local pass = 0
local fail = 0

local function check(condition, message)
    if condition then
        pass = pass + 1
        print("PASS: " .. message)
    else
        fail = fail + 1
        print("FAIL: " .. message)
    end
end

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-9)
end

-- --- Kleiner Synth-Testdouble ----------------------------------------------
-- Mockt synth.new/controlsignal.new/getCurrentTime; zeichnet Waveform, ADSR,
-- playNote/playMIDINote (Frequenz/Note, Volume, Dauer, when) und Stops auf.
local function makeMockSound()
    local names = { "movement", "switch", "bridge", "impact", "gate", "bridgeCross", "roomTrans", "babyPush", "babyImpact", "babyBridgeLayer", "core", "tone", "special", "woosh" }
    local idx = 0
    local mock = {
        synth = {},
        controlsignal = {},
        created = {},
        synths = {},
        cs = nil,
        now = 0,
        -- Waveform-Konstanten aus der echten SDK-API spiegeln, damit
        -- Audio.init(mock) dieselben Werte an synth.new übergibt.
        kWaveSine = playdate.sound.kWaveSine,
        kWaveSquare = playdate.sound.kWaveSquare,
        kWaveSawtooth = playdate.sound.kWaveSawtooth,
        kWaveTriangle = playdate.sound.kWaveTriangle,
        kWaveNoise = playdate.sound.kWaveNoise,
    }
    function mock.synth.new(waveform)
        idx = idx + 1
        local name = names[idx]
        local s = {
            name = name,
            waveform = waveform,
            adsr = nil,
            calls = {},
            freqMod = nil,
            stopped = 0,
        }
        function s:setADSR(a, d, su, r) s.adsr = { a, d, su, r } end
        function s:playNote(pitch, vol, len, when)
            s.calls[#s.calls + 1] = { kind = "note", pitch = pitch, vol = vol, len = len, when = when }
        end
        function s:playMIDINote(note, vol, len, when)
            s.calls[#s.calls + 1] = { kind = "midi", note = note, vol = vol, len = len, when = when }
        end
        function s:setFrequencyMod(sig) s.freqMod = sig end
        function s:setWaveform(w) s.waveform = w end
        function s:stop() s.stopped = s.stopped + 1 end
        mock.synths[name] = s
        mock.created[#mock.created + 1] = s
        return s
    end
    function mock.controlsignal.new()
        local cs = { events = {} }
        function cs:clearEvents() cs.events = {} end
        function cs:addEvent(step, value, interp) cs.events[#cs.events + 1] = { step = step, value = value, interp = interp } end
        mock.cs = cs
        return cs
    end
    function mock.getCurrentTime() return mock.now end
    return mock
end

-- Neuer frischer Mock + Audio.init für jeden Testblock.
local function freshAudio()
    local mock = makeMockSound()
    Audio.init(mock)
    return mock
end

local sndConst = playdate.sound

-- Pflicht-Test 77: Init erzeugt 6 Synths; wiederholtes init ohne Arg erzeugt keine.
do
    local mock = makeMockSound()
    Audio.init(mock)
    check(#mock.created == 14, "init: 14 Synths erzeugt")
    Audio.init() -- defensiv: kein erneutes Erzeugen
    check(#mock.created == 14, "init: wiederholtes init erzeugt keine neuen Stimmen")
    check(Audio.synths.movement == mock.synths.movement, "init: Audio.synths zeigt auf Mock")
end

-- Pflicht-Test 78-83 + Bewegungsklicken
do
    freshAudio()
    Audio.resetRoom(1)
    check(Audio.noteRingMovement(14) == 0, "movement 14°: 0 Klicks")
    check(#Audio.synths.movement.calls == 0, "movement 14°: kein Synthcall")
    check(Audio.noteRingMovement(1) == 1, "movement 14+1: genau 1 Klick")
    check(#Audio.synths.movement.calls == 1, "movement 14+1: 1 Synthcall")
    Audio.resetRoom(1)
    check(Audio.noteRingMovement(10) == 0, "movement 10: 0 Klicks")
    check(Audio.noteRingMovement(6) == 1, "movement 10+6: genau 1 Klick (Rest 1)")
    check(Audio.noteRingMovement(1) == 0, "movement Rest: nach 1 kein weiterer Klick")
    Audio.resetRoom(1)
    check(Audio.noteRingMovement(40) == 2, "movement 40°: zwei 15°-Schwellen")
    Audio.resetRoom(1)
    check(Audio.noteRingMovement(10) == 0, "movement Richtungswechsel +10: 0")
    check(Audio.noteRingMovement(-10) == 1, "movement Richtungswechsel -10: 1 (20° Weg)")
    check(Audio.noteRingMovement(-5) == 0, "movement Richtungswechsel Rest 5: 0")
    check(Audio.noteRingMovement(0) == 0, "movement blocked (0): kein Klick")
    -- Volume exakt 0.15
    Audio.resetRoom(1)
    Audio.noteRingMovement(15)
    local c = Audio.synths.movement.calls[1]
    check(c ~= nil and c.vol == Config.audioMovementClickVolume and c.vol == 0.15, "movement Volume exakt 0.15")
    check(c ~= nil and c.len < 0.1, "movement Impuls sehr kurz")
    check(Audio.synths.movement.waveform == sndConst.kWaveNoise, "movement Waveform Noise")
    -- große Deltas: Rest korrekt (40 -> 2 Klicks, Rest 10); danach 10 -> 1 Klick
    Audio.resetRoom(1)
    check(Audio.noteRingMovement(40) == 2, "movement 40: 2 Klicks")
    check(Audio.noteRingMovement(10) == 1, "movement 40+10: Rest 10 -> 1 Klick")
end

-- Pflicht-Test 87-89: Switch
do
    freshAudio()
    Audio.playSwitchSnap()
    local calls = Audio.synths.switch.calls
    check(#calls == 2, "switch: zwei Töne")
    check(calls[1].kind == "midi" and calls[2].kind == "midi", "switch: MIDI-Noten")
    check(calls[1].note == Config.audioSwitchNote1 and calls[2].note == Config.audioSwitchNote2, "switch: Töne 72/71")
    check(calls[2].note < calls[1].note, "switch: absteigend")
    check(calls[1].note - calls[2].note == 1, "switch: exakt 1 Halbton tiefer")
    check(Audio.synths.switch.waveform == sndConst.kWaveSquare, "switch Waveform Square")
    check(calls[1].when == nil and calls[2].when ~= nil, "switch: erster Ton sofort, zweiter zeitversetzt")
    check(calls[1].len < 0.2, "switch: Noten kurz")
    -- gleicher Zustand / kein Trigger: kein Call ohne playSwitchSnap-Aufruf
    check(#Audio.synths.switch.calls == 2, "switch: kein Sound bei gleichem State (kein Auto-Trigger)")
end

-- Pflicht-Test 90-94: Bridge Extend
do
    freshAudio()
    Audio.playBridgeExtend()
    local calls = Audio.synths.bridge.calls
    check(#calls == 1, "bridge false->true: genau 1 Extend")
    check(Audio.synths.bridge.waveform == sndConst.kWaveSawtooth, "bridge Waveform Sawtooth")
    check(calls[1].len == Config.audioBridgeDuration and calls[1].len == 0.25, "bridge Dauer exakt 0.25 s")
    check(calls[1].pitch == Config.audioBridgeStartFreq, "bridge Startfrequenz")
    -- Glide: Controlsignal-Ereignisse (0 -> 0, 0.25 -> end-start) mit Interpolate
    local cs = Audio.synths.bridge.freqMod
    check(cs ~= nil, "bridge: Frequenzmodulation gesetzt")
    check(#cs.events == 2 and cs.events[2].step == 0.25, "bridge Glide über 0.25 s")
    check(cs.events[2].value == Config.audioBridgeEndFreq - Config.audioBridgeStartFreq, "bridge Endfrequenz > Start (Glide aufwärts)")
    check(cs.events[2].value > 0, "bridge Glide aufwärts")
    check(cs.events[1].interp == true and cs.events[2].interp == true, "bridge Glide linear interpoliert")
    -- true->false / free Bridge / Gate: kein Call (kein Auto-Trigger)
    check(#Audio.synths.bridge.calls == 1, "bridge: kein Sound bei true->false / free / Gate (nur Main-Trigger)")
end

-- Pflicht-Test 95-98: Shutter Impact
do
    freshAudio()
    Audio.noteShutterBlocked(true)
    check(#Audio.synths.impact.calls == 1, "impact: neue Kollision -> 1 Sound")
    check(Audio.synths.impact.waveform == sndConst.kWaveSine, "impact Waveform Sine")
    check(Audio.synths.impact.calls[1].pitch < 110, "impact: Frequenz tiefer als Switch/Bridge-SFX")
    check(Audio.synths.impact.calls[1].len < 0.3, "impact: kurzer Stoß")
    Audio.noteShutterBlocked(true) -- gehalten
    check(#Audio.synths.impact.calls == 1, "impact held: kein neuer Sound")
    Audio.noteShutterBlocked(false)
    Audio.noteShutterBlocked(true) -- re-contact
    check(#Audio.synths.impact.calls == 2, "impact re-contact: zweiter Sound")
    freshAudio()
    Audio.noteShutterBlocked(false) -- pendingClose/keine Collision
    check(#Audio.synths.impact.calls == 0, "impact pendingClose: kein Sound")
end

-- Pflicht-Test 99-102: Gate
do
    freshAudio()
    -- erfolgloses Gate: kein playGateTransition-Aufruf
    check(#Audio.synths.gate.calls == 0, "gate fail: kein Sound (kein Auto-Trigger)")
    Audio.playGateTransition()
    local calls = Audio.synths.gate.calls
    check(#calls == 1, "gate success: genau 1 Puls")
    check(Audio.synths.gate.waveform == sndConst.kWaveSine, "gate Waveform Sine")
    check(calls[1].pitch == Config.audioGateFreq and calls[1].len >= 0.5, "gate: langer tiefer Puls")
    -- resetRoom schneidet den Gate-Sound nicht ab
    Audio.resetRoom(2)
    check(#Audio.synths.gate.calls == 1 and Audio.synths.gate.stopped == 0, "gate: resetRoom stoppt den Puls nicht")
    Audio.playGateTransition() -- weiterer Gate-Übergang (z. B. 3->4)
    check(#Audio.synths.gate.calls == 2, "gate weiter: ebenfalls ein Puls")
end

-- --- Brückenwechsel (neuer Sound, Transferstart) ---------------------------
-- Kurzer mechanischer Zip+Snap beim tatsächlichen Bridge-Transferstart;
-- klar getrennt von Schalterklick, Bridge-Extend und Raumübergang.
do
    freshAudio()
    check(#Audio.synths.bridgeCross.calls == 0, "bridgeCross: anfangs kein Call")
    Audio.playBridgeCrossing()
    local calls = Audio.synths.bridgeCross.calls
    -- Pass 3: Zip (sofort) + kleiner Lande-Tick (zeitversetzt) = 2 Noten,
    -- aber EIN Transit-Sound (kein Frame-/Dock-Spam).
    check(#calls == 2, "bridgeCross: Zip + Lande-Tick (2 Noten, 1 Transit)")
    check(Audio.synths.bridgeCross.waveform == sndConst.kWaveSquare, "bridgeCross Waveform Square")
    check(calls[1].pitch == Config.audioBridgeCrossFreq, "bridgeCross Startfrequenz (Zip)")
    check(calls[1].len == Config.audioBridgeCrossDuration, "bridgeCross sehr kurz")
    check(calls[1].when == nil, "bridgeCross: Zip sofort")
    check(calls[2].pitch == Config.audioBridgeCrossTickFreq, "bridgeCross Lande-Tick Frequenz")
    check(calls[2].len == Config.audioBridgeCrossTickLen, "bridgeCross Lande-Tick sehr kurz")
    check(calls[2].when ~= nil and approx(calls[2].when, Config.audioBridgeCrossDuration),
        "bridgeCross: Tick bei Landung (when = Start + Dauer)")
    local cs = Audio.synths.bridgeCross.freqMod
    check(cs ~= nil and #cs.events == 2, "bridgeCross: Glide gesetzt")
    check(cs.events[2].value == Config.audioBridgeCrossEndFreq - Config.audioBridgeCrossFreq,
        "bridgeCross: Abwärts-Glide (Zip)")
    -- Kein interner Mehrfach-Trigger: ein zweiter Aufruf = ein zweiter Transit.
    Audio.playBridgeCrossing()
    check(#Audio.synths.bridgeCross.calls == 4, "bridgeCross: 2 Aufrufe = 2 Transits (kein Spam)")
end

-- --- Raumübergang (neuer Sound, gemeinsamer Raumabschluss) -----------------
-- Größerer, tiefer ziehender Sweep; klar größer/länger als Brückenwechsel.
do
    freshAudio()
    check(#Audio.synths.roomTrans.calls == 0, "roomTrans: anfangs kein Call")
    Audio.playRoomTransition()
    local calls = Audio.synths.roomTrans.calls
    check(#calls == 1, "roomTrans: genau 1 Call")
    check(Audio.synths.roomTrans.waveform == sndConst.kWaveTriangle, "roomTrans Waveform Triangle")
    check(calls[1].pitch == Config.audioRoomTransFreq, "roomTrans Startfrequenz")
    check(calls[1].len == Config.audioRoomTransDuration, "roomTrans Dauer")
    local cs = Audio.synths.roomTrans.freqMod
    check(cs ~= nil and #cs.events == 2, "roomTrans: Glide gesetzt")
    check(cs.events[2].value == Config.audioRoomTransEndFreq - Config.audioRoomTransFreq,
        "roomTrans: tiefer ziehender Sweep")
    -- Klanghierarchie: Raumübergang deutlich länger als Brückenwechsel.
    check(Config.audioRoomTransDuration > Config.audioBridgeCrossDuration,
        "roomTrans: länger als Brückenwechsel (Klanghierarchie)")
end

-- --- Baby-Sounds (Begleiter): Push / Impact / Bridge-Layer -----------------
do
    freshAudio()
    Audio.resetRoom(1)
    -- Push: nur bei Flanke false->true (einmal pro Schub, nicht pro Frame).
    check(#Audio.synths.babyPush.calls == 0, "babyPush: anfangs kein Call")
    Audio.noteBabyPush(false)
    check(#Audio.synths.babyPush.calls == 0, "babyPush: kein Kontakt -> kein Ton")
    Audio.noteBabyPush(true)
    check(#Audio.synths.babyPush.calls == 1, "babyPush: Kontakt -> genau 1 Ton")
    Audio.noteBabyPush(true) -- gehalten
    check(#Audio.synths.babyPush.calls == 1, "babyPush held: kein neuer Ton pro Frame")
    Audio.noteBabyPush(false)
    Audio.noteBabyPush(true) -- re-contact
    check(#Audio.synths.babyPush.calls == 2, "babyPush re-contact: zweiter Ton")
    local pc = Audio.synths.babyPush.calls[1]
    check(Audio.synths.babyPush.waveform == sndConst.kWaveTriangle, "babyPush Waveform Triangle (weich)")
    check(pc.pitch == Config.audioBabyPushFreq, "babyPush Frequenz")
    check(pc.len == Config.audioBabyPushLen, "babyPush sehr kurz")
    -- resetRoom setzt die Push-Flanke zurück (nächster Schub klingt wieder).
    Audio.resetRoom(1)
    Audio.noteBabyPush(true)
    check(#Audio.synths.babyPush.calls == 3, "babyPush: resetRoom setzt Flanke zurück")

    -- Impact: dumpf, nur bei Flanke (blockierter Schub an das Baby).
    freshAudio()
    check(#Audio.synths.babyImpact.calls == 0, "babyImpact: anfangs kein Call")
    Audio.noteBabyImpact(false)
    check(#Audio.synths.babyImpact.calls == 0, "babyImpact: kein Kontakt -> kein Ton")
    Audio.noteBabyImpact(true)
    check(#Audio.synths.babyImpact.calls == 1, "babyImpact: blockierter Schub -> 1 Ton")
    Audio.noteBabyImpact(true) -- gehalten
    check(#Audio.synths.babyImpact.calls == 1, "babyImpact held: kein neuer Ton pro Frame")
    Audio.noteBabyImpact(false)
    Audio.noteBabyImpact(true)
    check(#Audio.synths.babyImpact.calls == 2, "babyImpact re-contact: zweiter Ton")
    local ic = Audio.synths.babyImpact.calls[1]
    check(Audio.synths.babyImpact.waveform == sndConst.kWaveSine, "babyImpact Waveform Sine (dumpf)")
    check(ic.pitch == Config.audioBabyImpactFreq, "babyImpact Frequenz")
    check(ic.pitch < Config.audioBabyPushFreq, "babyImpact tiefer als Push (dumpf)")

    -- Shared Bridge: mechanischer Zip+Tick (bridgeCross) + heller Baby-Layer.
    freshAudio()
    Audio.playBridgeCrossing()
    Audio.playBabyBridgeLayer()
    check(#Audio.synths.bridgeCross.calls == 2, "babyBridge: bridgeCross Zip+Tick (1 Transit)")
    check(#Audio.synths.babyBridgeLayer.calls == 1, "babyBridge: Layer 1 Call")
    local bl = Audio.synths.babyBridgeLayer.calls[1]
    check(Audio.synths.babyBridgeLayer.waveform == sndConst.kWaveSquare, "babyBridge Waveform Square (hell)")
    check(bl.pitch == Config.audioBabyBridgeFreq, "babyBridge Frequenz")
    check(bl.pitch > Config.audioBridgeCrossFreq, "babyBridge heller als mechanischer Zip")
    check(bl.len == Config.audioBabyBridgeLen, "babyBridge sehr kurz")

    -- Keine Sounds bei Blink/Idle (kein Auto-Trigger ohne gemeldetes Event).
    freshAudio()
    Audio.noteBabyPush(false)
    Audio.noteBabyImpact(false)
    check(#Audio.synths.babyPush.calls == 0 and #Audio.synths.babyImpact.calls == 0
        and #Audio.synths.babyBridgeLayer.calls == 0, "baby: keine Sounds bei Blink/Idle")
end

-- Pflicht-Test 103-111: Core Pulse
do
    freshAudio()
    Audio.resetRoom(1)
    check(approx(Audio.coreFrequency(1), 55), "core Room1 = 55 Hz")
    Audio.update(3.999)
    check(#Audio.synths.core.calls == 0, "core 3.999 s: kein Puls")
    Audio.update(0.001)
    check(#Audio.synths.core.calls == 1, "core 4.000 s: genau 1 Puls")
    Audio.update(4.0)
    check(#Audio.synths.core.calls == 2, "core 8 s: zweiter Puls (kein Drift)")
    freshAudio()
    Audio.resetRoom(1)
    Audio.update(8.5)
    check(#Audio.synths.core.calls == 2, "core großer dt 8.5: zwei 4-s-Schwellen")
    check(approx(Audio.synths.core.calls[1].pitch, 55), "core großer dt: Raum-1-Frequenz")
    check(approx(Audio.coreFrequency(2), 55 * (2 ^ (4 / 12)), 1e-6), "core Room2 = 55*2^(4/12)")
    check(approx(Audio.coreFrequency(3), 55 * (2 ^ (8 / 12)), 1e-6), "core Room3 = 55*2^(8/12)")
    -- Abschlussphase A: Formel läuft für Räume 4-7 automatisch weiter (keine
    -- neue Frequenzliste; große Terz = +4 Halbtöne pro Raum).
    check(approx(Audio.coreFrequency(4), 55 * (2 ^ (12 / 12)), 1e-6), "core Room4 = 55*2^(12/12) = 110")
    check(approx(Audio.coreFrequency(5), 55 * (2 ^ (16 / 12)), 1e-6), "core Room5 = 55*2^(16/12)")
    check(approx(Audio.coreFrequency(6), 55 * (2 ^ (20 / 12)), 1e-6), "core Room6 = 55*2^(20/12)")
    check(approx(Audio.coreFrequency(7), 55 * (2 ^ (24 / 12)), 1e-6), "core Room7 = 55*2^(24/12)")
    check(Audio.coreFrequency(2) > Audio.coreFrequency(1) and Audio.coreFrequency(3) > Audio.coreFrequency(2), "core Pitch steigend pro Raum")
    check(Audio.coreFrequency(4) > Audio.coreFrequency(3) and Audio.coreFrequency(5) > Audio.coreFrequency(4) and Audio.coreFrequency(6) > Audio.coreFrequency(5) and Audio.coreFrequency(7) > Audio.coreFrequency(6), "core Pitch steigend bis Raum 7")
    -- reset room: Timer=0, neue Raumfrequenz
    freshAudio()
    Audio.resetRoom(1)
    Audio.update(3.5)
    Audio.resetRoom(2)
    Audio.update(0.1)
    check(#Audio.synths.core.calls == 0, "core reset: Timer=0, kein sofortiger Puls")
    Audio.update(3.9) -- 4.0 gesamt in Raum 2
    check(#Audio.synths.core.calls == 1, "core reset: Puls nach 4 s in Raum 2")
    check(approx(Audio.synths.core.calls[1].pitch, Audio.coreFrequency(2), 1e-6), "core reset: Raum-2-Frequenz")
    -- Camera-Zeit zählt in die 4 s hinein (kein Camera-Ende-Reset)
    freshAudio()
    Audio.resetRoom(2)
    Audio.update(1.2)
    check(#Audio.synths.core.calls == 0, "core camera: nach 1.2 s noch kein Puls")
    Audio.update(2.8)
    check(#Audio.synths.core.calls == 1, "core camera: nach insgesamt 4.0 s Puls")
    -- completion: keine neuen Pulse
    freshAudio()
    Audio.resetRoom(1)
    Audio.setCompleted()
    Audio.update(20)
    check(#Audio.synths.core.calls == 0, "core completion: keine neuen Pulse")
end

-- Pflicht-Test 112: read-only (Audio verändert keinen Gameplay-State)
do
    State.init(Levels[1])
    Room.init()
    Undo.clear()
    Bridge.resetTransit()
    Room.resetDockAssist()
    Camera.init(7)
    freshAudio()
    Audio.resetRoom(1)
    local swBefore = {}
    for k, v in pairs(State.switchStates) do swBefore[k] = v end
    local elBefore = {}
    for k, v in pairs(State.elementStates) do elBefore[k] = v end
    local ringBefore = State.player.ring
    local angleBefore = State.player.angle
    local undoBefore = Undo.count()
    local camBefore = Camera.getCurrentOuterRing()
    -- viele Audio-Aufrufe
    Audio.noteRingMovement(40)
    Audio.playSwitchSnap()
    Audio.playBridgeExtend()
    Audio.noteShutterBlocked(true)
    Audio.noteShutterBlocked(false)
    Audio.playGateTransition()
    Audio.update(5.0)
    Audio.stopAll()
    check(State.player.ring == ringBefore and State.player.angle == angleBefore, "audio read-only: player unverändert")
    check(Undo.count() == undoBefore, "audio read-only: undo unverändert")
    check(Camera.getCurrentOuterRing() == camBefore, "audio read-only: camera unverändert")
    local swSame = true
    for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
    for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
    check(swSame, "audio read-only: switchStates unverändert")
    local elSame = true
    for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
    for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
    check(elSame, "audio read-only: elementStates unverändert")
end

-- --- Pass 2: Switch A/B minimal unterschiedlich ----------------------------
do
    freshAudio()
    Audio.playSwitchSnap(true)  -- A (CW): Standardtöne 72/71
    local calls = Audio.synths.switch.calls
    check(#calls == 2, "p2 switch: A zwei Töne")
    check(calls[1].note == Config.audioSwitchNote1 and calls[2].note == Config.audioSwitchNote2, "p2 switch: A = 72/71")
    Audio.playSwitchSnap(false) -- B (CCW): exakt 1 Halbton tiefer
    local calls2 = Audio.synths.switch.calls
    check(#calls2 == 4, "p2 switch: B zwei weitere Töne")
    check(calls2[3].note == Config.audioSwitchBNote1 and calls2[4].note == Config.audioSwitchBNote2, "p2 switch: B = B-Noten")
    check(calls2[3].note == calls[1].note - 1, "p2 switch: B exakt 1 Halbton tiefer als A")
    check(calls2[4].note < calls2[3].note, "p2 switch: B ebenfalls absteigend")
end

-- --- Pass 2: Blenden-Körperton (Öffnen/Schließen) --------------------------
do
    freshAudio()
    Audio.noteShutterTransitions({ { id = "D1", opened = false } }) -- schließen
    local calls = Audio.synths.impact.calls
    check(#calls == 1, "p2 shutter: Schließen -> 1 Ton")
    check(approx(calls[1].pitch, Config.audioShutterCloseFreq), "p2 shutter: Schließen tiefer/härter")
    Audio.noteShutterTransitions({ { id = "D1", opened = true } })  -- öffnen
    local calls2 = Audio.synths.impact.calls
    check(#calls2 == 2, "p2 shutter: Öffnen -> 1 weiterer Ton")
    check(approx(calls2[2].pitch, Config.audioShutterOpenFreq), "p2 shutter: Öffnen höher")
    check(Config.audioShutterOpenFreq > Config.audioShutterCloseFreq, "p2 shutter: Öffnen > Schließen")
    check(Config.audioShutterOpenVolume < Config.audioShutterCloseVolume, "p2 shutter: Öffnen leiser")
    Audio.noteShutterTransitions(nil)
    Audio.noteShutterTransitions({})
    check(#Audio.synths.impact.calls == 2, "p2 shutter: nil/leer kein Ton")
end

-- --- Pass 2: Brücken-End-Klick (einmalig, nach vollständigem Ausfahren) ----
do
    freshAudio()
    Audio.resetRoom(1)
    local m = Audio.synths.movement
    check(#m.calls == 0, "p2 bridge: anfangs kein Klick")
    Audio.playBridgeExtend()
    local bTotal = Config.bridgeExtendDuration
    Audio.update(bTotal - 0.01)
    check(#m.calls == 0, "p2 bridge: kurz vor Ausfahren kein Klick")
    Audio.update(0.02) -- über die Schwelle
    check(#m.calls == 1, "p2 bridge: Klick nach vollständigem Ausfahren")
    check(approx(m.calls[1].pitch, Config.audioBridgeSettleFreq), "p2 bridge: Klick-Frequenz")
    Audio.update(1.0)
    check(#m.calls == 1, "p2 bridge: kein Wiederholen (einmal pro Ausfahren)")
    -- resetRoom räumt einen ausstehenden Klick (Raumwechsel vor Ablauf).
    Audio.playBridgeExtend()
    Audio.resetRoom(1)
    Audio.update(1.0)
    check(#m.calls == 1, "p2 bridge: resetRoom stoppt ausstehenden Klick")
end

-- --- Pass 2: Raumabschluss-Resonanz (pro Raum minimal tiefer) --------------
do
    freshAudio()
    Audio.resetRoom(1)
    Audio.playRoomCompletion(1)
    Audio.playRoomCompletion(5)
    local calls = Audio.synths.impact.calls
    check(#calls == 2, "p2 completion: zwei Impulse")
    check(approx(calls[1].pitch, Config.audioCompletionFreq), "p2 completion: Raum 1 Basis")
    check(calls[2].pitch < calls[1].pitch, "p2 completion: Raum 5 tiefer/resonanter")
    Audio.playRoomCompletion()
    check(approx(Audio.synths.impact.calls[3].pitch, Config.audioCompletionFreq), "p2 completion: ohne Index = Basis")
end

-- --- Pass 3: Bridge-/Room-Trigger einmalig (Architektur) -------------------
-- Room/Audio sind entkoppelt: Reines Andocken erzeugt KEINEN Bridge-Transit-
-- Sound und kein Raumwechsel erzeugt keinen Room-Transition-Sound von selbst.
-- Main verdrahtet die Hooks genau einmal pro echtem Ereignis; hier prüfen wir
-- das Verhalten der Module + dass ein Hook-Aufruf genau einen Sound liefert.
do
    local dockRoom = {
        name = "AudioDock",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },
        switches = { { id = "S1", ring = "outer", angle = 90, symbol = 1, onA = "B1", onB = "D1", state = "A" } },
        shutters = { { id = "D1", ring = "outer", angle = 90 } },
        bridges = { { id = "B0", angle = 270, free = true }, { id = "B1", angle = 180, free = false } },
        gate = { id = "T", angle = 0, free = true },
    }
    local function setupDock()
        State.init(dockRoom)
        Room.init()
        Undo.clear()
        Bridge.resetTransit()
        Room.resetDockAssist()
    end

    -- nur Docking (Player im DockRange, kein A) -> kein Bridge-Transit-Sound.
    freshAudio()
    setupDock()
    State.player.ring = "outer"
    State.player.angle = 270 -- B0@270 frei aktiv, im DockRange
    Room.updateDockAssist()
    check(#Audio.synths.bridgeCross.calls == 0, "nur-docking: kein Bridge-Transit-Sound")
    check(#Audio.synths.roomTrans.calls == 0, "nur-docking: kein Room-Transition-Sound")

    -- echter Transit: tryUseConnection startet genau einen Transit; Main ruft
    -- den Hook genau einmal -> ein Zip + ein Tick.
    freshAudio()
    setupDock()
    State.player.ring = "outer"
    State.player.angle = 270
    local r = Room.tryUseConnection()
    check(r.used == true and r.crossing == true, "transit-trigger: Transit startet")
    Audio.playBridgeCrossing() -- der eine Hook-Aufruf aus main.lua
    check(#Audio.synths.bridgeCross.calls == 2, "bridge-transit: genau 1 Zip + 1 Tick")

    -- kein Raumwechsel -> kein Room-Transition-Sound.
    check(#Audio.synths.roomTrans.calls == 0, "kein-raumwechsel: kein Room-Transition-Sound")
    -- echter Raumwechsel -> genau einmal (Main ruft den Hook einmal auf).
    Audio.playRoomTransition()
    check(#Audio.synths.roomTrans.calls == 1, "raumwechsel: genau 1 Room-Transition-Sound")
    Audio.playRoomTransition() -- zweiter Raumwechsel
    check(#Audio.synths.roomTrans.calls == 2, "raumwechsel: 2 Aufrufe = 2 Übergänge (kein Frame-Spam)")
end

-- --- Pass: Bridge-/Room-Sound präsenter (Tuning + Hierarchie) ---------------
-- Die neuen Tuningwerte sichern die Hörbarkeit am kleinen Lautsprecher und
-- die Klanghierarchie der Feature-Events Bridge < RoomTransition. Switch- und
-- Baby-Sounds sind in diesem Pass bewusst unverändert (kein Auftragsteil).
do
    freshAudio()
    -- Bridge-Transit: laut, mittleres Band, Abwärts-Sweep, hörbarer Lande-Tick.
    check(Config.audioBridgeCrossVolume >= 0.9,
        "tune-bridge: Transit laut genug (>= 0.9)")
    check(Config.audioBridgeCrossFreq >= 300 and Config.audioBridgeCrossFreq <= 500,
        "tune-bridge: Zip im mittleren Band (300-500 Hz, kleiner Lautsprecher)")
    check(Config.audioBridgeCrossEndFreq < Config.audioBridgeCrossFreq,
        "tune-bridge: Abwärts-Sweep (Zip-Richtung)")
    check(Config.audioBridgeCrossTickVolume >= 0.9,
        "tune-bridge: Lande-Tick laut")
    check(Config.audioBridgeCrossTickFreq >= Config.audioBridgeCrossEndFreq,
        "tune-bridge: Tick nicht unter dem Sweep-Ende (hörbar)")
    -- Room-Transition: tragend, mindestens so laut wie Bridge, länger.
    check(Config.audioRoomTransDuration >= 1.0,
        "tune-room: Raumübergang tragend (>= 1.0 s)")
    check(Config.audioRoomTransVolume >= Config.audioBridgeCrossVolume,
        "tune-room: Raumübergang laut >= Brückenwechsel (Hierarchie)")
    check(Config.audioRoomTransDuration > Config.audioBridgeCrossDuration,
        "tune-room: länger als Brückenwechsel (Hierarchie)")
    check(Config.audioRoomTransFreq < Config.audioBridgeCrossFreq,
        "tune-room: tieferer Charakter als Bridge-Zip (Atmosphäre)")
end

-- --- Pass: Shared Bridge spielt den Bridge-Sound GENAU EINMAL ---------------
-- Gemeinsamer Player+Baby-Transfer: genau ein Zip + ein Tick (Main ruft den
-- Hook genau einmal); der Baby-Layer liegt darüber, ohne den Mechanik-Sound
-- zu vervielfachen. Erneuter Hook = neuer Transit (kein Frame-/Dock-Spam).
do
    freshAudio()
    Audio.playBridgeCrossing()   -- der eine Hook-Aufruf für den Shared-Transit
    Audio.playBabyBridgeLayer()
    check(#Audio.synths.bridgeCross.calls == 2,
        "shared-once: Bridge-Sound genau 1x (1 Zip + 1 Tick)")
    check(#Audio.synths.babyBridgeLayer.calls == 1,
        "shared-once: Baby-Layer genau 1x")
    Audio.playBridgeCrossing()   -- zweiter echter Transit
    check(#Audio.synths.bridgeCross.calls == 4,
        "shared-once: zweiter Transit = zweiter Sound (kein Spam)")
end

-- --- Sounddesign-Erweiterung: Menü ----------------------------------------
do
    freshAudio()
    -- MENU MOVE: kleiner trockener Square-Tick auf der Switch-Stimme.
    Audio.playMenuMove()
    local c = Audio.synths.switch.calls
    check(#c == 1, "menu-move: genau 1 Tick")
    check(c[1].pitch == Config.audioMenuMoveFreq, "menu-move Frequenz")
    check(c[1].len == Config.audioMenuMoveLen, "menu-move sehr kurz")
    check(c[1].vol == Config.audioMenuMoveVolume, "menu-move Volume")

    -- MENU CONFIRM: Triangle-Sweep auf der tone-Stimme (180->260).
    Audio.playMenuConfirm()
    local tc = Audio.synths.tone.calls
    check(#tc == 1, "menu-confirm: genau 1 Note")
    check(tc[1].pitch == Config.audioMenuConfirmStart, "menu-confirm Startfrequenz")
    check(tc[1].len == Config.audioMenuConfirmDuration, "menu-confirm Dauer")
    local tcs = Audio.synths.tone.freqMod
    check(tcs ~= nil and #tcs.events == 2, "menu-confirm: Glide gesetzt")
    check(tcs.events[2].value == Config.audioMenuConfirmEnd - Config.audioMenuConfirmStart,
        "menu-confirm: Glide aufwärts")

    -- STARTANIMATION Rise: kontinuierlicher Sweep über menuDrawDuration.
    Audio.playMenuRise(1.35)
    local rc = Audio.synths.tone.calls
    check(#rc == 2, "menu-rise: genau 1 Note")
    check(rc[2].pitch == Config.audioMenuRiseStart, "menu-rise Startfrequenz")
    check(rc[2].len == 1.35, "menu-rise Dauer = menuDrawDuration")
    check(Audio.synths.tone.freqMod.events[2].value == Config.audioMenuRiseEnd - Config.audioMenuRiseStart,
        "menu-rise: Glide aufwärts")

    -- FILL-Abschlussimpuls: tiefer Impuls auf der Impact-Stimme.
    Audio.playMenuFillImpulse()
    local fc = Audio.synths.impact.calls
    check(#fc == 1, "menu-fill: genau 1 Impuls")
    check(fc[1].pitch == Config.audioMenuFillFreq, "menu-fill Frequenz (tief)")
    check(fc[1].len == Config.audioMenuFillDuration, "menu-fill Dauer")
end

-- --- Sounddesign-Erweiterung: Druckplatte ---------------------------------
do
    freshAudio()
    -- PLATE ON: Triangle steigt.
    Audio.playPlateOn()
    local c = Audio.synths.tone.calls
    check(#c == 1, "plate-on: genau 1 Note")
    check(c[1].pitch == Config.audioPlateOnStart, "plate-on Startfrequenz")
    check(Audio.synths.tone.freqMod.events[2].value == Config.audioPlateOnEnd - Config.audioPlateOnStart,
        "plate-on: Glide aufwärts")
    check(c[1].len == Config.audioPlateLen, "plate-on kurz")

    -- PLATE OFF: Triangle fällt.
    Audio.playPlateOff()
    check(#Audio.synths.tone.calls == 2, "plate-off: genau 1 Note")
    check(Audio.synths.tone.calls[2].pitch == Config.audioPlateOffStart, "plate-off Startfrequenz")
    check(Audio.synths.tone.freqMod.events[2].value == Config.audioPlateOffEnd - Config.audioPlateOffStart,
        "plate-off: Glide abwärts")

    -- notePlateTransitions: jede gemeldete Kante = genau ein Sound (EDGE).
    freshAudio()
    Audio.notePlateTransitions({ { id = "P1", on = true } })
    check(#Audio.synths.tone.calls == 1, "plate-trans: on -> 1 Sound")
    check(Audio.synths.tone.calls[1].pitch == Config.audioPlateOnStart, "plate-trans: ON-Ton")
    Audio.notePlateTransitions({ { id = "P1", on = false } })
    check(#Audio.synths.tone.calls == 2, "plate-trans: off -> 1 Sound")
    check(Audio.synths.tone.calls[2].pitch == Config.audioPlateOffStart, "plate-trans: OFF-Ton")
    Audio.notePlateTransitions(nil)
    Audio.notePlateTransitions({})
    check(#Audio.synths.tone.calls == 2, "plate-trans: nil/leer kein Sound")
    Audio.notePlateTransitions({ { id = "P1", on = true }, { id = "P2", on = false } })
    check(#Audio.synths.tone.calls == 4, "plate-trans: 2 Kanten = 2 Sounds")
end

-- --- Sounddesign-Erweiterung: Einmalschalter -------------------------------
do
    freshAudio()
    Audio.playOneShotSnap()
    local s = Audio.synths.switch.calls
    check(#s == 2, "oneshot: zwei Square-Snaps (MIDI)")
    check(s[1].kind == "midi" and s[2].kind == "midi", "oneshot: MIDI-Noten")
    check(s[1].note == Config.audioOneShotNote1 and s[2].note == Config.audioOneShotNote2,
        "oneshot: Noten 74 -> 67")
    check(s[2].note < s[1].note, "oneshot: absteigend")
    check(s[1].when == nil and s[2].when ~= nil, "oneshot: zweiter Ton zeitversetzt")
    check(s[2].when == Config.audioOneShotGap, "oneshot: Gap exakt (t0=0)")
    -- zusätzlicher tiefer Sine-Tick auf der Impact-Stimme.
    check(#Audio.synths.impact.calls == 1, "oneshot: 1 tiefer Tick")
    check(Audio.synths.impact.calls[1].pitch == Config.audioOneShotTickFreq, "oneshot: Tick-Frequenz")
    check(approx(Audio.synths.impact.calls[1].when, Config.audioOneShotGap + Config.audioOneShotLen),
        "oneshot: Tick nach dem zweiten Snap")
    -- deutlich anders als Doppelschalter (anderes Notenpaar).
    freshAudio()
    Audio.playSwitchSnap(true)
    check(Audio.synths.switch.calls[1].note ~= Config.audioOneShotNote1,
        "oneshot: anders als Doppelschalter (Notenpaar)")
end

-- --- Sounddesign-Erweiterung: Bridge Retract / One-Use Collapse ------------
do
    freshAudio()
    -- BRIDGE RETRACT: Sägezahn ABWÄRTS (320->160) auf der Bridge-Stimme.
    Audio.playBridgeRetract()
    local c = Audio.synths.bridge.calls
    check(#c == 1, "retract: genau 1 Note")
    check(c[1].pitch == Config.audioBridgeRetractStart, "retract Startfrequenz")
    check(c[1].len == Config.audioBridgeRetractDuration, "retract Dauer")
    check(Audio.synths.bridge.freqMod.events[2].value == Config.audioBridgeRetractEnd - Config.audioBridgeRetractStart,
        "retract: Glide ABWÄRTS (verschwindet)")
    check(Audio.synths.bridge.freqMod.events[2].value < 0, "retract: Endfrequenz < Start (Runter-Glide)")

    -- ONE-USE COLLAPSE: Sägezahn 260->90 auf der Bridge-Stimme.
    Audio.playOneUseCollapse()
    local c2 = Audio.synths.bridge.calls
    check(#c2 == 2, "oneuse: genau 1 Note")
    check(c2[2].pitch == Config.audioCollapseStart, "oneuse Startfrequenz")
    check(c2[2].len == Config.audioCollapseDuration, "oneuse Dauer")
    check(Audio.synths.bridge.freqMod.events[2].value == Config.audioCollapseEnd - Config.audioCollapseStart,
        "oneuse: Glide abwärts")
    -- Extend vs. Retract/Collapse: Extend steigt, Retract/Collapse fallen.
    -- (bridgeGlide ist ein geteiltes Controlsignal — Wert direkt nach jedem
    -- Aufruf prüfen, bevor der nächste ihn überschreibt.)
    freshAudio()
    Audio.playBridgeExtend()
    local extVal = Audio.synths.bridge.freqMod.events[2].value
    Audio.playBridgeRetract()
    local retVal = Audio.synths.bridge.freqMod.events[2].value
    Audio.playOneUseCollapse()
    local colVal = Audio.synths.bridge.freqMod.events[2].value
    check(extVal > 0, "hierarchie: Extend steigt")
    check(retVal < 0, "hierarchie: Retract fällt")
    check(colVal < 0, "hierarchie: Collapse fällt")
end

-- --- Sounddesign-Erweiterung: Tutorial ------------------------------------
do
    freshAudio()
    -- Leiste erscheint: winziger Triangle-Tick (Baby-Push-Stimme, ruhig).
    Audio.playTutorialAppear()
    local c = Audio.synths.babyPush.calls
    check(#c == 1, "tut-appear: genau 1 Tick")
    check(c[1].pitch == Config.audioTutorialTickFreq, "tut-appear Frequenz")
    check(c[1].len == Config.audioTutorialTickLen, "tut-appear sehr kurz")
    check(c[1].vol == Config.audioTutorialTickVolume and c[1].vol < 0.2,
        "tut-appear sehr leise (< 0.2)")

    -- A = continue: kleiner neutraler Square-Tick.
    Audio.playTutorialContinue()
    local s = Audio.synths.switch.calls
    check(#s == 1, "tut-continue: genau 1 Tick")
    check(s[1].pitch == Config.audioTutorialContinueFreq, "tut-continue Frequenz")
    check(s[1].len == Config.audioTutorialContinueLen, "tut-continue sehr kurz")
end

-- --- Sounddesign-Erweiterung: Restart (B) ----------------------------------
do
    freshAudio()
    -- Phase 1 Collapse: Sine-Sweep 150->55 auf der special-Stimme.
    Audio.playRestartCollapse()
    local c = Audio.synths.special.calls
    check(#c == 1, "restart-collapse: genau 1 Note")
    check(c[1].pitch == Config.audioRestartCollapseStart, "restart-collapse Startfrequenz")
    check(c[1].len == Config.audioRestartCollapseDuration, "restart-collapse Dauer")
    check(Audio.synths.special.freqMod.events[2].value == Config.audioRestartCollapseEnd - Config.audioRestartCollapseStart,
        "restart-collapse: Glide abwärts")

    -- Phase 2 am Core: sehr kurzer tiefer Impuls.
    Audio.playRestartCore()
    check(#Audio.synths.impact.calls == 1, "restart-core: genau 1 Impuls")
    check(Audio.synths.impact.calls[1].pitch == Config.audioRestartCoreFreq, "restart-core Frequenz (55)")

    -- Phase 3 Rebuild: Sägezahn 90->220 (Energie).
    Audio.playRestartRebuild()
    local b = Audio.synths.bridge.calls
    check(#b == 1, "restart-rebuild: genau 1 Note")
    check(b[1].pitch == Config.audioRestartRebuildStart, "restart-rebuild Startfrequenz")
    check(b[1].len == Config.audioRestartRebuildDuration, "restart-rebuild Dauer")
    check(Audio.synths.bridge.freqMod.events[2].value == Config.audioRestartRebuildEnd - Config.audioRestartRebuildStart,
        "restart-rebuild: Glide aufwärts")
end

-- --- Sounddesign-Erweiterung: LEVEL-7-Spezialübergang ----------------------
do
    freshAudio()
    -- pulse: 3 zeitversetzte Kern-Pulse, steigend.
    Audio.notePhase7Phase("pulse", 7)
    local sp = Audio.synths.special.calls
    check(#sp == 3, "p7-pulse: 3 Pulse")
    local base = Audio.coreFrequency(7)
    check(approx(sp[1].pitch, base * Config.audioP7Pulse1Mult, 1e-6), "p7-pulse: Puls 1 = base")
    check(approx(sp[2].pitch, base * Config.audioP7Pulse2Mult, 1e-6), "p7-pulse: Puls 2 höher")
    check(approx(sp[3].pitch, base * Config.audioP7Pulse3Mult, 1e-6), "p7-pulse: Puls 3 am höchsten")
    check(sp[1].when == nil and sp[2].when ~= nil and sp[3].when ~= nil, "p7-pulse: zeitversetzt")
    check(sp[3].when > sp[2].when, "p7-pulse: Puls 3 nach Puls 2")
    check(sp[1].vol < sp[2].vol and sp[2].vol < sp[3].vol, "p7-pulse: jeder lauter")

    -- collapse: Sine-Sweep base -> 38 Hz.
    freshAudio()
    Audio.notePhase7Phase("collapse", 7)
    check(#Audio.synths.special.calls == 1, "p7-collapse: genau 1 Note")
    check(Audio.synths.special.calls[1].pitch == base, "p7-collapse Start = base")
    check(approx(Audio.synths.special.freqMod.events[2].value, Config.audioP7CollapseEnd - base, 1e-6),
        "p7-collapse: Glide zum Punkt (38 Hz)")

    -- explode: Noise + tiefer Impact + abfallender Saw-Sweep.
    freshAudio()
    Audio.notePhase7Phase("explode", 7)
    check(#Audio.synths.movement.calls == 1, "p7-explode: 1 Noise-Impuls")
    check(#Audio.synths.impact.calls == 1, "p7-explode: 1 tiefer Impact")
    check(#Audio.synths.bridge.calls == 1, "p7-explode: 1 Frag-Sweep")
    check(Audio.synths.bridge.freqMod.events[2].value < 0, "p7-explode: Frag-Sweep abfallend")

    -- rebuild: ein klarer Sine-Puls (neuer Kern).
    freshAudio()
    Audio.notePhase7Phase("rebuild", 7)
    check(#Audio.synths.special.calls == 1, "p7-rebuild: genau 1 Puls")
    check(approx(Audio.synths.special.calls[1].pitch, base * Config.audioP7NewCoreMult, 1e-6),
        "p7-rebuild: neuer Kern (base * 1.5)")

    -- andere Phasen: kein Sound (rest/flash/dark sind still).
    freshAudio()
    Audio.notePhase7Phase("rest", 7)
    Audio.notePhase7Phase("flash", 7)
    Audio.notePhase7Phase("dark", 7)
    check(#Audio.synths.special.calls == 0 and #Audio.synths.movement.calls == 0
        and #Audio.synths.impact.calls == 0 and #Audio.synths.bridge.calls == 0,
        "p7: rest/flash/dark still (kein Sound)")
end

-- --- Sounddesign-Erweiterung: finales Ende (letzter Raum) ------------------
do
    freshAudio()
    -- Finaler Room-Transition-Sweep: länger als der normale.
    Audio.playRoomTransitionFinal()
    local c = Audio.synths.roomTrans.calls
    check(#c == 1, "final-trans: genau 1 Note")
    check(c[1].len == Config.audioFinalTransDuration, "final-trans Dauer (1.8 s)")
    check(c[1].len > Config.audioRoomTransDuration, "final-trans: länger als normaler Übergang")
    check(Audio.synths.roomTrans.freqMod.events[2].value == Config.audioRoomTransEndFreq - Config.audioRoomTransFreq,
        "final-trans: gleicher Abwärts-Charakter")

    -- Outro-Settle: Sine gleitet von Room-Core-Frequenz auf 55 Hz.
    Audio.playFinalSettle(1)
    local sp = Audio.synths.special.calls
    check(#sp == 1, "final-settle: genau 1 Note")
    check(approx(sp[1].pitch, 55, 1e-6), "final-settle Start = Room-1-Core (55)")
    check(sp[1].len == Config.audioFinalSettleDuration, "final-settle Dauer (1.8 s)")
    check(Audio.synths.special.freqMod.events[2].value == Config.audioCoreRoom1Freq - 55,
        "final-settle: gleitet auf 55 Hz (Ruhe)")
    check(sp[1].vol == Config.audioFinalSettleVolume, "final-settle Volume")
end

-- --- Sounddesign-Erweiterung: LEVELÜBERGANG-SOG ---------------------------
do
    freshAudio()
    Audio.playTransitionWoosh()
    -- Textur-Schicht: ein sehr kurzer, leiser Noise-Einsatz (nur Haptik).
    local m = Audio.synths.movement.calls
    check(#m == 1, "sog: genau 1 Noise-Textur")
    check(m[1].pitch == Config.audioWooshNoiseFreq, "sog: Noise-Frequenz")
    check(m[1].len == Config.audioWooshNoiseLen, "sog: Noise sehr kurz")
    check(m[1].len < Config.audioWooshDuration, "sog: Noise kürzer als Sweep")
    check(m[1].vol == Config.audioWooshNoiseVolume, "sog: Noise sehr leise (Textur)")
    -- Energie-Schicht: ein breiter Triangle-Sweep auf der Woosh-Stimme.
    local w = Audio.synths.woosh.calls
    check(#w == 1, "sog: genau 1 Triangle-Note")
    check(Audio.synths.woosh.waveform == sndConst.kWaveTriangle, "sog: Triangle-Waveform")
    check(w[1].pitch == Config.audioWooshStart, "sog: Sweep-Start (tief, 80)")
    check(w[1].len == Config.audioWooshDuration, "sog: Sweep-Dauer")
    check(w[1].vol == Config.audioWooshVolume, "sog: Volume")
    check(Audio.synths.woosh.freqMod ~= nil and #Audio.synths.woosh.freqMod.events == 2,
        "sog: Glide gesetzt")
    check(Audio.synths.woosh.freqMod.events[2].value == Config.audioWooshEnd - Config.audioWooshStart,
        "sog: Sweep aufwärts (tief -> kurz höher)")
    -- Charakter: tiefer SOG — Dauer 0.60-0.90 s, Volume deutlich, nicht schrill.
    check(Config.audioWooshDuration >= 0.60 and Config.audioWooshDuration <= 0.90,
        "sog: Dauer 0.60-0.90 s")
    check(Config.audioWooshVolume >= 0.55 and Config.audioWooshVolume <= 0.80,
        "sog: Volume 0.55-0.80")
    -- Tiefer Abschlussimpuls (Sine): genau EIN kurzer, tiefer Impuls auf der
    -- Impact-Stimme (kein Explosions-Boom, nur das „Einziehen" des Cores).
    check(#Audio.synths.impact.calls == 1, "sog: genau 1 Abschlussimpuls (Sine)")
    check(Audio.synths.impact.calls[1].pitch == Config.audioWooshImpulseFreq,
        "sog: Abschlussimpuls tief (70 Hz)")
    check(Audio.synths.impact.calls[1].when == Config.audioWooshImpulseDelay,
        "sog: Impuls kurz vor dem Ausklingen")
    -- genau 1 Aufruf = genau 1 SOG (kein Frame-Spam).
    Audio.playTransitionWoosh()
    check(#Audio.synths.woosh.calls == 2, "sog: 2 Aufrufe = 2 SOGs (kein Spam)")
end

-- --- Sounddesign-Erweiterung: Mixing (Core-Hold) ---------------------------
do
    freshAudio()
    Audio.resetRoom(1)
    -- ohne Hold: Puls nach 4 s.
    Audio.update(4.0)
    check(#Audio.synths.core.calls == 1, "corehold: ohne Hold Puls nach 4 s")
    -- mit Hold: Kernpuls pausiert für die Dauer, danach startet der 4-s-
    -- Intervall frisch (kein Akkumulieren während der Ruhe).
    freshAudio()
    Audio.resetRoom(1)
    Audio.setCoreHold(2.0)
    Audio.update(4.0)
    check(#Audio.synths.core.calls == 0, "corehold: 4 s während Hold -> kein Puls")
    Audio.update(4.0) -- nach Hold-Ende: kompletter neuer Intervall
    check(#Audio.synths.core.calls == 1, "corehold: nach Hold-Ende Puls nach weiteren 4 s")
    -- kurzer Hold (< 4 s): kein Puls innerhalb des Fensters.
    freshAudio()
    Audio.resetRoom(1)
    Audio.setCoreHold(3.0)
    Audio.update(3.5)
    check(#Audio.synths.core.calls == 0, "corehold: innerhalb Hold-Fenster kein Puls")
    Audio.update(4.0) -- Hold längst abgelaufen, neuer Intervall ab Hold-Ende
    check(#Audio.synths.core.calls == 1, "corehold: Puls nach abgelaufenem Hold + neuem Intervall")
    -- setCoreHold(0) = kein Hold.
    freshAudio()
    Audio.resetRoom(1)
    Audio.setCoreHold(0)
    Audio.update(4.0)
    check(#Audio.synths.core.calls == 1, "corehold: Hold 0 = normaler Puls")
end

-- --- Sounddesign-Erweiterung: stopAll deckt alle 13 Stimmen ab -------------
do
    local mock = makeMockSound()
    Audio.init(mock)
    Audio.stopAll()
    local total = 0
    for _, s in pairs(mock.synths) do total = total + s.stopped end
    check(total == 14, "stopall: alle 14 Stimmen gestoppt (inkl. tone/special/woosh)")
    check(mock.synths.tone.stopped == 1, "stopall: tone gestoppt")
    check(mock.synths.special.stopped == 1, "stopall: special gestoppt")
    check(mock.synths.woosh.stopped == 1, "stopall: woosh gestoppt")
end

TestReport.audio = { pass = pass, fail = fail }
