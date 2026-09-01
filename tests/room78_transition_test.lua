-- room78_transition_test.lua — FRAMEWEISER TEST der Spezialtransition
-- ROOM 7 -> 8 (source/ui/phase7.lua + source/ui/roomreveal.lua + der
-- Orchestrierung aus main.lua, hier nachgestellt).
--
-- Läuft die komplette Sequenz in 50-fps-Frames (FRAME_DT = 0.02 s) durch:
--   Puls 1 (0.08 s auf, 0.08 s ab, 0.04 s Pause) -> Puls 2 (0.10 s auf,
--   0.09 s ab, 0.04 s Pause) -> große Expansion (~1.1 s) -> Vollbild weiß
--   -> „ROOM 8 / 9“ für exakt 2 s auf rein weiß (Room 8 NICHT sichtbar,
--   kein Overlap) -> Text weg -> Room 8 erscheint klein (Scale ~0.30, kein
--   Fullsize-Flash) -> wächst als Einheit auf Scale 1.0.
--
-- Geprüft wird NUR die Transition (Timing, Phasenfolge, Vollbild, Text,
-- Reveal-Skala). Keine Levelgeometrie-/Puzzlelogik-Änderungen, kein
-- Gameplay-Input (bis Scale 1.0 bleibt die Eingabe gesperrt — das ist
-- Aufgabe von main.lua und hier durch die reine Präsentationsschicht
-- implizit gegeben).
--
-- Ergebnis wird in TestReport.room78Transition gesammelt.

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

local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 0.001)
end

local FRAME_DT <const> = 1 / 50

-- --- Setup: Level 7 frisch (wie phase7_tests) -----------------------------
State.init(Levels[7], true)
Room.init()
Undo.clear()
Camera.init(Levels[7].rings.outer)
Camera.clearRestartScale()
Camera.clearRevealScale()
Render.currentRoomIndex = 7
RoomReveal.reset()
Phase7.reset()

local pf = { ring = "center", angle = 135 }
local pt = { ring = Levels[8].rings.outer, angle = Levels[8].start.angle }
local bf = { ring = "center", angle = 145 }
local bt = { ring = Levels[8].rings[Levels[8].baby.start.ring], angle = Levels[8].baby.start.angle }

-- --- 1) Timing-Vorgaben aus der Config -------------------------------------
check(near(Config.phase7P1Up, 0.08, 0.001), "Spec: Puls-1-Expansion ~0.08 s")
check(near(Config.phase7P1Down, 0.08, 0.001), "Spec: Puls-1-Rueckkehr ~0.08 s")
check(near(Config.phase7Pause1, 0.04, 0.001), "Spec: Pause nach Puls 1 ~0.04 s")
check(near(Config.phase7P2Up, 0.10, 0.001), "Spec: Puls-2-Expansion ~0.10 s")
check(near(Config.phase7P2Down, 0.09, 0.001), "Spec: Puls-2-Rueckkehr ~0.09 s")
check(near(Config.phase7Pause2, 0.04, 0.001), "Spec: Pause nach Puls 2 ~0.04 s")
check(Config.phase7Expand >= 1.0 and Config.phase7Expand <= 1.2, "Spec: grosse Expansion 1.0-1.2 s")
check(Config.phase7RoomLabelHold == 2.0, "Spec: ROOM-Text exakt 2.0 s")
check(Config.roomDisplayTotal == 9, "Spec: Gesamtzahl = 9 (kein /10)")
check(Config.roomRevealStartScale >= 0.28 and Config.roomRevealStartScale <= 0.32, "Spec: Startskala 0.28-0.32")
check(Config.roomRevealGrow >= 0.8 and Config.roomRevealGrow <= 0.9, "Spec: Reveal-Dauer 0.8-0.9 s")

-- --- 2) Phase 7->8 frameweise durchlaufen -----------------------------------
Phase7.start(8, pf, pt, bf, bt, 7)
local counts = {}
local order = {}
local loadSeen = false
local doneSeen = false
local sawContract = false
local sawLabel = false
local labelChecked = false
local frames = 0
local maxFrames = 400 -- Sicherheitslimit (~8 s)

while Phase7.isActive() and frames < maxFrames do
    frames = frames + 1
    local event = Phase7.update(FRAME_DT)
    if event == "load" then loadSeen = true end
    if event == "done" then doneSeen = true end
    local ph = Phase7.phase
    counts[ph] = (counts[ph] or 0) + 1
    if #order == 0 or order[#order] ~= ph then
        order[#order + 1] = ph
    end
    if ph == "contract" then sawContract = true end
    if ph == "label" then
        sawLabel = true
        -- Während des ROOM-Textes: volles weißes Bild, keine Figuren, KEIN
        -- Room-Reveal (kein Overlap, kein frühzeitiges Wachstum). Der
        -- allerletzte Label-Frame löst bereits „done“ aus (dann ist
        -- Phase7.active false) — daher die Checks nur, solange aktiv.
        if Phase7.isActive() and not labelChecked then
            labelChecked = true
            check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.001), "label: Vollbild weiss waehrend des Textes")
            check(Phase7.hidesFigures(), "label: Figuren verdeckt")
            check(not RoomReveal.isActive(), "label: RoomReveal NICHT aktiv (kein Text/Room-Overlap)")
        end
    end
end

check(frames < maxFrames, "Sequenz: laeuft ohne Haenger zu Ende")
check(loadSeen, "Sequenz: 'load' ausgeloest (Room 8 wurde verdeckt geladen)")
check(doneSeen, "Sequenz: 'done' ausgeloest (Text weg)")
check(sawLabel, "Sequenz: label-Phase (ROOM-Text) wurde durchlaufen")
check(not sawContract, "Sequenz: KEINE Implosion/contract-Phase mehr")

-- --- 3) Phasendauern (frameweise gemessen, mit Toleranz) -------------------
-- 0.02-s-Frames teilen nicht jede Dauer exakt (z. B. 0.09 s, 2.0 s) und die
-- Phasenmaschine trägt Restbruchteile weiter -> Dauer-Toleranz statt exakter
-- Framezahlen. Erwartete Dauern: P1 0.08/0.08/0.04, P2 0.10/0.09/0.04,
-- Expansion 1.1, Label exakt 2.0.
local function phaseDur(name)
    return ((counts[name] or 0) * FRAME_DT)
end
local function durCheck(name, expected, tol)
    local d = phaseDur(name)
    check(math.abs(d - expected) <= tol,
        "Dauer: " .. name .. " = " .. string.format("%.2f", d) .. " s (erwartet ~" .. string.format("%.2f", expected) .. " s)")
end
durCheck("p1_up", 0.08, 0.03)
durCheck("p1_down", 0.08, 0.03)
durCheck("pause1", 0.04, 0.03)
durCheck("p2_up", 0.10, 0.03)
durCheck("p2_down", 0.09, 0.03)
durCheck("pause2", 0.04, 0.03)
durCheck("expand", 1.1, 0.06)
durCheck("label", 2.0, 0.06)

-- --- 4) Puls-Größen (lesbar: Puls 1 kleiner als Puls 2, Rückkehr exakt) ----
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)            -- -> p1_up, t=0
local base1 = Phase7.coreRadius()
Phase7.update(Config.phase7P1Up)
local peak1 = Phase7.coreRadius()
Phase7.update(Config.phase7P1Down)          -- -> pause1
local back1 = Phase7.coreRadius()
check(near(peak1, Config.phase7P1Scale * base1, 0.5), "Pulse: Puls 1 erreicht 1.18x")
check(near(back1, base1, 0.5), "Pulse: Puls 1 kehrt exakt zur Normalgroesse zurueck")
Phase7.update(Config.phase7Pause1)          -- -> p2_up
Phase7.update(Config.phase7P2Up)
local peak2 = Phase7.coreRadius()
Phase7.update(Config.phase7P2Down)          -- -> pause2
local back2 = Phase7.coreRadius()
check(peak2 > peak1, "Pulse: Puls 2 ist klar groesser als Puls 1")
check(near(peak2, Config.phase7P2Scale * base1, 0.5), "Pulse: Puls 2 erreicht 1.35x")
check(near(back2, base1, 0.5), "Pulse: Puls 2 kehrt exakt zur Normalgroesse zurueck")

-- --- 5) Nach „done“: Room-Reveal wie in main.lua ---------------------------
-- (main.lua: phase7.reset() -> roomReveal.start(0) ->
--  camera.setRevealScale(config.roomRevealStartScale))
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
Phase7.update(Config.phase7P1Up)
Phase7.update(Config.phase7P1Down)
Phase7.update(Config.phase7Pause1)
Phase7.update(Config.phase7P2Up)
Phase7.update(Config.phase7P2Down)
Phase7.update(Config.phase7Pause2)
Phase7.update(Config.phase7Expand)          -- -> hold, "load"
Phase7.update(Config.phase7Hold)            -- -> label
Phase7.update(Config.phase7RoomLabelHold)   -- -> done
check(not Phase7.isActive(), "Reveal: Phase7 beendet (Text komplett weg)")

-- Room 8 wird erst JETZT sichtbar: sofort klein, kein Fullsize-Flash.
RoomReveal.start(0)
Camera.setRevealScale(Config.roomRevealStartScale)
check(near(RoomReveal.getScale(), Config.roomRevealStartScale, 0.001), "Reveal: erster sichtbarer Frame bei Startskala ~0.30 (kein Fullsize-Flash)")
check(near(Camera.revealScale, Config.roomRevealStartScale, 0.001), "Reveal: Camera.revealScale sofort auf Startskala gesetzt")

-- Wachstum frameweise: 0.30 -> 1.00 (easeOutCubic, ~0.8 s = 40 Frames).
local prev = RoomReveal.getScale()
local growFrames = 0
local monotonic = true
local completed = false
while not completed and growFrames < 200 do
    growFrames = growFrames + 1
    completed = RoomReveal.update(FRAME_DT)
    local s = RoomReveal.getScale()
    if s < prev - 0.0001 then monotonic = false end
    prev = s
end
check(completed, "Reveal: Wachstum abgeschlossen (Scale exakt 1.0)")
check(near(RoomReveal.getScale(), 1.0, 0.001), "Reveal: Scale exakt 1.0 am Ende")
check(monotonic, "Reveal: waechst monoton (kein Bounce/Overshoot)")
check(growFrames == math.ceil(Config.roomRevealGrow / FRAME_DT) or near(growFrames * FRAME_DT, Config.roomRevealGrow, 0.02),
    "Reveal: Dauer ~0.8-0.9 s (" .. string.format("%.2f", growFrames * FRAME_DT) .. " s)")

-- --- 6) Aufräumen ----------------------------------------------------------
Phase7.reset()
RoomReveal.reset()
Camera.clearRevealScale()
Camera.clearRestartScale()

TestReport.room78Transition = { pass = pass, fail = fail }
