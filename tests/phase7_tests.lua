-- Tests für source/ui/phase7.lua (Level-7-Spezialübergang: Ende der Lernphase
-- -> neue schwere Phase, kosmische „Urknall“-Sequenz). Nur die Übergangs-
-- logik selbst: Phasen-Maschine (rest -> expand -> text -> contract -> done),
-- Expansions-/Kontraktions-Radius, Vollbild + „ROOM X / 10“, Verdeckung der
-- Figuren, direkter Reveal. Keine Spielmechanik. Erwartet, dass die Module
-- per import geladen wurden (siehe tools/run_tests.ps1). Ergebnis wird in
-- TestReport.phase7 gesammelt.

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
check(Phase7.phase == "rest", "Phase7: startet in rest (kurze Ruhe/Verdichtung)")
check(Phase7.hidesFigures(), "Phase7: rest verdeckt Player+Baby")
check(near(Phase7.fromCoreRadius, Config.coreRadius + 6 * Config.coreGrowthPerRoom), "Phase7: fromCoreRadius = Kern von Raum 7")
check(near(Phase7.toCoreRadius, Config.coreRadius + 7 * Config.coreGrowthPerRoom), "Phase7: toCoreRadius = Kern von Raum 8")
check(Phase7.coreRadius() == nil, "Phase7: in rest kein Übergangskreis (Kern atmet normal)")

-- --- Phasen-Maschine (rest -> expand -> text -> contract -> done) ----------
local event = Phase7.update(Config.phase7Rest)
check(event == nil and Phase7.phase == "expand", "Phase7: rest -> expand (kein Event)")
event = Phase7.update(Config.phase7Expand)
check(event == "load" and Phase7.phase == "text", "Phase7: expand -> text mit Event 'load' (neuer Raum wird verdeckt geladen)")
check(Phase7.hidesFigures(), "Phase7: text verdeckt Player+Baby")
event = Phase7.update(Config.phase7TextHold)
check(event == nil and Phase7.phase == "contract", "Phase7: text -> contract (kein Event)")
event = Phase7.update(Config.phase7Contract)
check(event == "done" and not Phase7.isActive(), "Phase7: contract -> done (direkter Reveal von Level 8)")

-- --- Expansion: langsames, gleichmäßiges Wachstum zum Vollbild -------------
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest) -- -> expand, t=0
local startR = Phase7.coreRadius()
check(startR ~= nil and startR > Config.coreRadius, "Phase7: expand startet über dem Kernradius (nahtlos)")
check(startR < Config.phase7CoverRadius, "Phase7: expand startet unter dem Vollbild")
-- Mitte: Radius ist gewachsen, aber noch nicht am Vollbild.
Phase7.update(Config.phase7Expand / 2)
local midR = Phase7.coreRadius()
check(midR > startR and midR < Config.phase7CoverRadius, "Phase7: expand wächst stetig (Mitte)")
-- Ende: exakt die Vollbild-Abdeckung.
Phase7.update(Config.phase7Expand / 2)
check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.5), "Phase7: expand füllt am Ende das komplette Bild")
check(Phase7.hidesFigures(), "Phase7: expand verdeckt Player+Baby")

-- --- ROOM-Text: Vollbild bleibt konstant (~2 s) ----------------------------
Phase7.update(0)
check(Phase7.phase == "text", "Phase7: text aktiv (Vollbild + ROOM-Anzeige)")
check(near(Phase7.coreRadius(), Config.phase7CoverRadius, 0.001), "Phase7: text hält das volle Bild konstant")
Phase7.update(Config.phase7TextHold / 2)
check(Phase7.phase == "text", "Phase7: text hält ~2 s (ROOM 8 / 10)")

-- --- Kontraktion: extrem schnelles Zusammenziehen zum Punkt ----------------
Phase7.update(Config.phase7TextHold / 2) -- -> contract, t=0
check(Phase7.phase == "contract", "Phase7: contract aktiv (schneller Kollaps)")
local cStart = Phase7.coreRadius()
check(near(cStart, Config.phase7CoverRadius, 0.001), "Phase7: contract startet am Vollbild")
Phase7.update(Config.phase7Contract / 2)
local cMid = Phase7.coreRadius()
check(cMid < cStart and cMid > Config.phase7TinyPoint, "Phase7: contract schrumpft zum winzigen Punkt")
-- Ganz am Ende (kurz vor dem Phasenwechsel, t²-beschleunigt) ist der Radius
-- nahe dem winzigen Punkt.
Phase7.update(Config.phase7Contract * 0.49)
check(Phase7.phase == "contract", "Phase7: contract noch aktiv (kurz vor dem Ende)")
check(Phase7.coreRadius() < 8, "Phase7: contract endet nahe dem winzigen Punkt")
check(Config.phase7Contract < Config.phase7Expand, "Phase7: Kontraktion ist deutlich schneller als die Expansion")
Phase7.update(Config.phase7Contract * 0.01) -- -> done
check(not Phase7.isActive(), "Phase7: contract -> done (Übergang beendet)")

-- --- Deterministisch (kein Zufall) ----------------------------------------
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
Phase7.update(Config.phase7Expand / 3)
local rA = Phase7.coreRadius()
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
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
