-- Tests für source/ui/phase7.lua (Level-7-Spezialübergang: Ende der Lernphase
-- -> neue schwere Phase, kosmische „Urknall“-Sequenz mit 2 Pulsen + großer
-- Expansion + ROOM-Text auf weiß). Nur die Übergangslogik selbst: Phasen-
-- Maschine (rest -> p1_up -> p1_down -> pause1 -> p2_up -> p2_down -> pause2
-- -> expand -> hold -> label -> done), Puls-/Expansions-/Label-Radius,
-- Vollbild + „ROOM X / 9“-Text, Verdeckung der Figuren. KEINE Implosion mehr.
-- Erwartet, dass die Module per import geladen wurden (siehe
-- tools/run_tests.ps1). Ergebnis wird in TestReport.phase7 gesammelt.

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

-- --- Ausgangszustand: Abschluss von Level 7 (Kernbrücken-Abschluss) --------
State.init(Levels[7], true)
Room.init()
Undo.clear()
Camera.init(Levels[7].rings.outer)
Camera.clearRestartScale()
Camera.clearRevealScale()
Render.currentRoomIndex = 7

Phase7.reset()
check(not Phase7.isActive(), "Phase7: nach reset inaktiv")
check(Phase7.hidesFigures() == false, "Phase7: inaktiv versteckt keine Figuren")

-- Figuren-Daten wie in main.handleConnectionResult (Kernbrücken-Abschluss:
-- Player/Baby am Mittelpunkt mit eigenen Winkeln, Ziel = Startring Raum 8).
local pf = { ring = "center", angle = 135 }
local pt = { ring = Levels[8].rings.outer, angle = Levels[8].start.angle }
local bf = { ring = "center", angle = 145 }
local bt = { ring = Levels[8].rings[Levels[8].baby.start.ring], angle = Levels[8].baby.start.angle }

Phase7.start(8, pf, pt, bf, bt, 7)
check(Phase7.isActive(), "Phase7: nach start aktiv")
check(Phase7.phase == "rest", "Phase7: startet in rest (kurze Verdichtung)")
check(Phase7.hidesFigures(), "Phase7: rest verdeckt Player+Baby")
check(near(Phase7.fromCoreRadius, Config.coreRadius + 6 * Config.coreGrowthPerRoom), "Phase7: fromCoreRadius = Kern von Raum 7")
check(near(Phase7.toCoreRadius, Config.coreRadius + 7 * Config.coreGrowthPerRoom), "Phase7: toCoreRadius = Kern von Raum 8")
check(Phase7.coreRadius() == nil, "Phase7: in rest kein Übergangskreis (Kern atmet normal)")

-- --- Phasen-Maschine (rest -> p1_up -> p1_down -> pause1 -> p2_up -> p2_down -> pause2 -> expand -> hold -> label -> done) ---
local event = Phase7.update(Config.phase7Rest)
check(event == nil and Phase7.phase == "p1_up", "Phase7: rest -> p1_up (kein Event)")
event = Phase7.update(Config.phase7P1Up)
check(event == nil and Phase7.phase == "p1_down", "Phase7: p1_up -> p1_down (kein Event)")
event = Phase7.update(Config.phase7P1Down)
check(event == nil and Phase7.phase == "pause1", "Phase7: p1_down -> pause1 (kein Event)")
event = Phase7.update(Config.phase7Pause1)
check(event == nil and Phase7.phase == "p2_up", "Phase7: pause1 -> p2_up (kein Event)")
event = Phase7.update(Config.phase7P2Up)
check(event == nil and Phase7.phase == "p2_down", "Phase7: p2_up -> p2_down (kein Event)")
event = Phase7.update(Config.phase7P2Down)
check(event == nil and Phase7.phase == "pause2", "Phase7: p2_down -> pause2 (kein Event)")
event = Phase7.update(Config.phase7Pause2)
check(event == nil and Phase7.phase == "expand", "Phase7: pause2 -> expand (kein Event)")
event = Phase7.update(Config.phase7Expand)
check(event == "load" and Phase7.phase == "hold", "Phase7: expand -> hold mit Event 'load' (neuer Raum wird verdeckt geladen)")
check(Phase7.hidesFigures(), "Phase7: hold verdeckt Player+Baby")
event = Phase7.update(Config.phase7Hold)
check(event == nil and Phase7.phase == "label", "Phase7: hold -> label (kein Event)")
check(Phase7.hidesFigures(), "Phase7: label verdeckt Player+Baby")
event = Phase7.update(Config.phase7RoomLabelHold)
check(event == "done" and not Phase7.isActive(), "Phase7: label -> done (Text weg, Room-Reveal folgt)")

-- --- Puls 1: klar lesbarer einzelner Puls (auf 1.18x und zurück) -----------
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest) -- -> p1_up, t=0
local base1 = Phase7.coreRadius()
check(base1 ~= nil and base1 > Config.coreRadius, "Phase7: p1_up startet am normalen Kern (nahtlos)")
-- Ende von p1_up: exakt 1.18x.
Phase7.update(Config.phase7P1Up)
check(Phase7.phase == "p1_down", "Phase7: p1_up Ende -> p1_down")
local peak1 = Phase7.coreRadius()
check(near(peak1, Config.phase7P1Scale * base1, 0.5), "Phase7: Puls 1 erreicht 1.18x des normalen Cores")
-- Ende von p1_down: exakt zurück auf die normale Größe.
Phase7.update(Config.phase7P1Down)
check(Phase7.phase == "pause1", "Phase7: p1_down Ende -> pause1")
local back1 = Phase7.coreRadius()
check(near(back1, base1, 0.5), "Phase7: Puls 1 kehrt exakt zur normalen Größe zurück")

-- --- Puls 2: sichtbar stärker (auf 1.35x) und wieder zurück ----------------
Phase7.update(Config.phase7Pause1) -- -> p2_up, t=0
check(Phase7.phase == "p2_up", "Phase7: pause1 Ende -> p2_up")
local mid2 = Phase7.coreRadius()
check(near(mid2, base1, 0.5), "Phase7: Pause hält den Core auf der normalen Größe")
Phase7.update(Config.phase7P2Up)
check(Phase7.phase == "p2_down", "Phase7: p2_up Ende -> p2_down")
local peak2 = Phase7.coreRadius()
check(near(peak2, Config.phase7P2Scale * base1, 0.5), "Phase7: Puls 2 erreicht 1.35x des normalen Cores")
check(peak2 > peak1, "Phase7: Puls 2 ist klar größer als Puls 1")
check(Config.phase7P2Scale > Config.phase7P1Scale, "Phase7: Puls-2-Skala größer als Puls-1-Skala")
Phase7.update(Config.phase7P2Down)
check(Phase7.phase == "pause2", "Phase7: p2_down Ende -> pause2")
local back2 = Phase7.coreRadius()
check(near(back2, base1, 0.5), "Phase7: Puls 2 kehrt exakt zur normalen Größe zurück")

-- --- Große Expansion: langsam und kontinuierlich bis zum Vollbild ----------
Phase7.update(Config.phase7Pause2) -- -> expand, t=0
check(Phase7.phase == "expand", "Phase7: pause2 Ende -> expand")
local startR = Phase7.coreRadius()
check(near(startR, base1, 0.5), "Phase7: expand startet am normalen Core (nicht sprungartig)")
check(Config.phase7Expand >= 1.0 and Config.phase7Expand <= 1.3, "Phase7: Expansionsdauer 1.0-1.3 s")
Phase7.update(Config.phase7Expand / 2)
local midR = Phase7.coreRadius()
check(midR > startR and midR < Config.phase7CoverRadius, "Phase7: expand wächst stetig (Mitte)")
Phase7.update(Config.phase7Expand / 2) -- -> hold, t=0
check(Phase7.phase == "hold", "Phase7: expand Ende -> hold")
check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.5), "Phase7: expand füllt am Ende das komplette Bild")
check(Config.phase7CoverRadius >= 245, "Phase7: Vollbild-Radius >= 245 (deckt alle 4 Ecken)")
check(Phase7.hidesFigures(), "Phase7: expand verdeckt Player+Baby")

-- --- Hold: sehr kurzer Vollbildmoment, KEIN ROOM-Text ----------------------
Phase7.update(0)
check(Phase7.phase == "hold", "Phase7: hold aktiv (Vollbild, kein Text)")
check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.001), "Phase7: hold hält das volle Bild konstant")
check(Config.phase7Hold >= 0.03 and Config.phase7Hold <= 0.08, "Phase7: Vollbildmoment sehr kurz (0.03-0.08 s)")

-- --- Label: „ROOM 8 / 9“ auf rein weißem Bildschirm (KEINE Implosion) -----
Phase7.update(Config.phase7Hold) -- -> label, t=0
check(Phase7.phase == "label", "Phase7: label aktiv (ROOM-Text auf weiß)")
check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.001), "Phase7: label hält das volle weiße Bild konstant")
check(Config.phase7RoomLabelHold == 2.0, "Phase7: ROOM-Text exakt 2.0 s")
check(Phase7.labelText() == "ROOM 8 / 9", "Phase7: labelText exakt 'ROOM 8 / 9'")
check(Config.roomDisplayTotal == 9, "Phase7: Gesamtzahl = 9 (nie /10)")
check(Phase7.hidesFigures(), "Phase7: label verdeckt Player+Baby (nur weiß + Text)")
-- Text läuft noch (kein vorzeitiges Ende).
Phase7.update(Config.phase7RoomLabelHold / 2)
check(Phase7.phase == "label" and Phase7.isActive(), "Phase7: nach 1 s ist der Text noch aktiv (2 s gesamt)")
-- Kein Room-Reveal während des Textes (startet erst nach „done“ in main.lua).
check(RoomReveal ~= nil and not RoomReveal.isActive(), "Phase7: RoomReveal NICHT aktiv während des Textes (kein Overlap)")
Phase7.update(Config.phase7RoomLabelHold / 2) -- -> done
check(not Phase7.isActive(), "Phase7: label -> done (Übergang beendet)")

-- --- Deterministisch (kein Zufall) ----------------------------------------
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
Phase7.update(Config.phase7P1Up)
Phase7.update(Config.phase7P1Down)
Phase7.update(Config.phase7Pause1)
Phase7.update(Config.phase7P2Up)
Phase7.update(Config.phase7P2Down)
Phase7.update(Config.phase7Pause2)
Phase7.update(Config.phase7Expand / 3)
local rA = Phase7.coreRadius()
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
Phase7.update(Config.phase7P1Up)
Phase7.update(Config.phase7P1Down)
Phase7.update(Config.phase7Pause1)
Phase7.update(Config.phase7P2Up)
Phase7.update(Config.phase7P2Down)
Phase7.update(Config.phase7Pause2)
Phase7.update(Config.phase7Expand / 3)
local rB = Phase7.coreRadius()
check(near(rA, rB, 0.001), "Phase7: Expansionsradius deterministisch (kein Zufall)")

-- --- Tutorial-Sperre ab Phase 2 --------------------------------------------
check(Tutorial.enabledForRoom(7) == true, "Tutorial: Raum 7 erlaubt Tutorials (Lernphase)")
check(Tutorial.enabledForRoom(8) == false, "Tutorial: Raum 8 = KEINE Tutorials (Phase 2)")
check(Tutorial.enabledForRoom(9) == false, "Tutorial: ab Raum 8 keine Tutorials")
check(Tutorial.maybeStartFocus(8) == false, "Tutorial: kein Mechanik-Fokus in Raum 8")
check(Tutorial.checkElementTriggers(8, nil) == false, "Tutorial: keine Kontext-Erklärungen in Raum 8")
check(Tutorial.checkLevelHints(8) == false, "Tutorial: keine Level-1-Hinweise in Raum 8")

-- --- Aufräumen --------------------------------------------------------------
Phase7.reset()
check(not Phase7.isActive(), "Phase7: reset beendet den Übergang")
Camera.clearRevealScale()
Camera.clearRestartScale()

TestReport.phase7 = { pass = pass, fail = fail }
