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
    local names = { "movement", "switch", "bridge", "impact", "gate", "core" }
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
    check(#mock.created == 6, "init: 6 Synths erzeugt")
    Audio.init() -- defensiv: kein erneutes Erzeugen
    check(#mock.created == 6, "init: wiederholtes init erzeugt keine neuen Stimmen")
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
    -- Abschlussphase A: Formel läuft für Räume 4-6 automatisch weiter (keine
    -- neue Frequenzliste; große Terz = +4 Halbtöne pro Raum).
    check(approx(Audio.coreFrequency(4), 55 * (2 ^ (12 / 12)), 1e-6), "core Room4 = 55*2^(12/12) = 110")
    check(approx(Audio.coreFrequency(5), 55 * (2 ^ (16 / 12)), 1e-6), "core Room5 = 55*2^(16/12)")
    check(approx(Audio.coreFrequency(6), 55 * (2 ^ (20 / 12)), 1e-6), "core Room6 = 55*2^(20/12)")
    check(Audio.coreFrequency(2) > Audio.coreFrequency(1) and Audio.coreFrequency(3) > Audio.coreFrequency(2), "core Pitch steigend pro Raum")
    check(Audio.coreFrequency(4) > Audio.coreFrequency(3) and Audio.coreFrequency(5) > Audio.coreFrequency(4) and Audio.coreFrequency(6) > Audio.coreFrequency(5), "core Pitch steigend bis Raum 6")
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
    local bTotal = Config.bridgeExtendStage1 + Config.bridgeExtendStage2 + Config.bridgeExtendStage3
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

TestReport.audio = { pass = pass, fail = fail }
