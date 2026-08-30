-- Tests für source/ui/phase7.lua (Level-7-Spezialübergang: Ende der Lernphase
-- -> neue schwere Phase). Nur die Übergangslogik selbst (Phasen-Maschine,
-- Pulse, Kollaps, Fragmente, Wiederaufbau, Figuren-Exit, Tutorial-Sperre).
-- Keine Spielmechanik. Erwartet, dass die Module per import geladen wurden
-- (siehe tools/run_tests.ps1). Ergebnis wird in TestReport.phase7 gesammelt.

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
check(Phase7.phase == "rest", "Phase7: startet in rest (kurze Ruhe)")
check(Phase7.hidesFigures(), "Phase7: rest verdeckt Player+Baby")
check(near(Phase7.fromCoreRadius, Config.coreRadius + 6 * Config.coreGrowthPerRoom), "Phase7: fromCoreRadius = Kern von Raum 7")
check(near(Phase7.toCoreRadius, Config.coreRadius + 7 * Config.coreGrowthPerRoom), "Phase7: toCoreRadius = Kern von Raum 8")
check(Phase7.outerR > Phase7.innerR, "Phase7: Explosions-Ringradien Außen > Innen")
check(near(Phase7.outerR, Config.outerRadius), "Phase7: Außenring-Fragment-Start = 104")
check(near(Phase7.innerR, Config.innerRadius), "Phase7: Innenring-Fragment-Start = 68")

-- --- Phasen-Maschine (rest -> pulse -> collapse -> flash -> explode -> dark
--     -> rebuild -> done) ----------------------------------------------------
local event = Phase7.update(Config.phase7Rest)
check(event == nil and Phase7.phase == "pulse", "Phase7: rest -> pulse (kein Event)")
local pulseTotal = Config.phase7Pulse1Dur + Config.phase7Pulse2Dur + Config.phase7Pulse3Dur
event = Phase7.update(pulseTotal)
check(event == nil and Phase7.phase == "collapse", "Phase7: pulse -> collapse (kein Event)")
event = Phase7.update(Config.phase7Collapse)
check(event == nil and Phase7.phase == "flash", "Phase7: collapse -> flash (kein Event)")
event = Phase7.update(Config.phase7Flash)
check(event == nil and Phase7.phase == "explode", "Phase7: flash -> explode (kein Event)")
event = Phase7.update(Config.phase7Explosion)
check(event == "load" and Phase7.phase == "dark", "Phase7: explode -> dark mit Event 'load' (neuer Raum wird verdeckt geladen)")
check(Phase7.hidesFigures(), "Phase7: dark verdeckt Player+Baby")
event = Phase7.update(Config.phase7Dark)
check(event == nil and Phase7.phase == "rebuild", "Phase7: dark -> rebuild (kein Event)")
check(Phase7.hidesFigures(), "Phase7: rebuild vor Figuren-Exit verdeckt Player+Baby")
event = Phase7.update(Config.phase7Rebuild)
check(event == "done" and not Phase7.isActive(), "Phase7: rebuild -> done (Übergang beendet)")

-- --- Pulse: drei Pulse, zunehmende Stärke, dritter schneller ---------------
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest) -- -> pulse, t=0
local base = Render.coreRadius(Render.currentRoomIndex) + Render.corePulseOffset()
-- Puls 1 (leicht): bei der Hälfte der Dauer ist sin(pi*0.5) = 1 -> Basis + Amp.
Phase7.update(Config.phase7Pulse1Dur / 2)
local peak1 = Phase7.coreRadius()
check(near(peak1, base + Config.phase7Pulse1Amp, 0.5), "Puls 1: Peak = Basis + Amplitude (leicht)")
-- Puls 2 (stärker): an den Peak von Puls 2 springen.
Phase7.update(Config.phase7Pulse1Dur / 2 + Config.phase7Pulse2Dur / 2)
local peak2 = Phase7.coreRadius()
check(near(peak2, base + Config.phase7Pulse2Amp, 0.5), "Puls 2: Peak = Basis + Amplitude (stärker)")
check(peak2 > peak1, "Puls 2 ist stärker als Puls 1")
-- Puls 3 (deutlich stärker UND schneller): an den Peak von Puls 3 springen.
Phase7.update(Config.phase7Pulse2Dur / 2 + Config.phase7Pulse3Dur / 2)
local peak3 = Phase7.coreRadius()
check(near(peak3, base + Config.phase7Pulse3Amp, 0.5), "Puls 3: Peak = Basis + Amplitude (deutlich stärker)")
check(peak3 > peak2, "Puls 3 ist stärker als Puls 2")
check(Config.phase7Pulse3Dur < Config.phase7Pulse2Dur, "Puls 3 ist schneller als Puls 2")
-- Zwischen den Pulsen (Puls-Ruhe am Sinus-Nullpunkt) = Basisradius.
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
Phase7.update(Config.phase7Rest)
Phase7.update(Config.phase7Pulse1Dur * 0.001)
check(near(Phase7.coreRadius(), base, 0.5), "Puls 1 startet am Basisradius (sin(0)=0)")

-- --- Kollaps: Kern zieht sich auf den winzigen Punkt zusammen --------------
Phase7.update(Config.phase7Pulse1Dur * 0.999) -- fast ans Puls-Ende
Phase7.update(Config.phase7Pulse2Dur + Config.phase7Pulse3Dur) -- -> collapse, t=0
Phase7.update(Config.phase7Collapse / 2)
local midCollapse = Phase7.coreRadius()
check(midCollapse < base and midCollapse > Config.phase7TinyPoint, "Kollaps: Radius schrumpft zwischen Basis und winzigem Punkt")
-- Kurz vor dem Kollaps-Ende: Radius ist nahezu der winzige Punkt.
Phase7.update(Config.phase7Collapse / 2 - 0.01)
check(Phase7.coreRadius() < 8, "Kollaps: Radius nahe am winzigen weißen Punkt am Ende")
Phase7.update(0.01) -- -> flash, t=0

-- --- Explosion: deterministische Fragmente (6-10, grobe Ringsegmente +
--     radiale Splitter) -----------------------------------------------------
Phase7.update(Config.phase7Flash) -- -> explode
check(#Phase7.fragments >= 6 and #Phase7.fragments <= 10, "Explosion: 6-10 Fragmente (" .. #Phase7.fragments .. ")")
local arcCount, spikeCount = 0, 0
for _, f in ipairs(Phase7.fragments) do
    if f.kind == "arc" then
        arcCount = arcCount + 1
        check(f.startR >= Config.innerRadius - 0.5 and f.startR <= Config.outerRadius + 0.5, "Ringsegment startet auf der alten Ringgeometrie")
        check(f.width >= 6 and f.width <= 8, "Ringsegment hat Bahnbreite")
    else
        spikeCount = spikeCount + 1
        check(f.kind == "spike" and f.width == 3, "Radialer Splitter vorhanden")
    end
    check(f.angle >= 0 and f.angle < 360, "Fragment-Winkel in [0,360)")
end
check(arcCount >= 4 and spikeCount >= 2, "Explosion: grobe Ringsegmente + radiale Splitter gemischt")
-- Deterministisch: ein zweiter Start erzeugt identische Fragmente.
local angles1 = {}
for i, f in ipairs(Phase7.fragments) do angles1[i] = f.angle end
Phase7.reset()
Phase7.start(8, pf, pt, bf, bt, 7)
check(#Phase7.fragments == #angles1, "Explosion: Fragmentanzahl deterministisch")
local deterministic = true
for i, f in ipairs(Phase7.fragments) do
    if math.abs(f.angle - angles1[i]) > 0.001 then deterministic = false end
end
check(deterministic, "Explosion: Fragment-Winkel deterministisch (kein Zufall)")

-- --- Wiederaufbau: Welt baut sich aus dem kleinen Kern auf -----------------
-- Phase für Phase bis rebuild vorrücken (jeder update-Aufruf vollzieht
-- höchstens EINEN Phasenwechsel — die elseif-Kette wird pro Aufruf nur einmal
-- durchlaufen, der Carryover ist subtraktiv).
Phase7.update(Config.phase7Rest)
Phase7.update(pulseTotal)
Phase7.update(Config.phase7Collapse)
Phase7.update(Config.phase7Flash)
check(Phase7.phase == "explode", "Phase7: mitten in der Explosion (für Rebuild-Test)")
Phase7.update(Config.phase7Explosion * 0.5)
local loadEvent = Phase7.update(Config.phase7Explosion * 0.5)
check(Phase7.phase == "dark", "Phase7: dark erreicht (Rebuild-Vorbereitung)")
-- main.lua lädt beim "load"-Event den neuen Raum (Raum 8) und setzt die
-- Kamera auf dessen Außenring (outer = 0) — erst dann ist der Zielradius der
-- Ringbahn 104.
check(loadEvent == "load", "Phase7: dark liefert 'load' (verdeckter Raumwechsel)")
Camera.init(Levels[8].rings.outer)
Phase7.update(Config.phase7Dark)
check(Phase7.phase == "rebuild", "Phase7: rebuild aktiv")
check(near(Phase7.revealScale(), Config.phase7RebuildStartScale, 0.001), "Rebuild: Startskala = kleiner Kern")
check(near(Phase7.exitProgress(), 0), "Rebuild: Exit-Fortschritt 0 am Start")
check(Phase7.hidesFigures(), "Rebuild: Figuren noch verdeckt (Ringe bauen sich auf)")
-- Vor ExitStart (u=0.5 < 0.55): noch kein Figuren-Exit, Figuren verdeckt.
Phase7.update(Config.phase7Rebuild * 0.5)
check(near(Phase7.exitProgress(), 0) and Phase7.hidesFigures(), "Rebuild: vor ExitStart kein Figuren-Exit")
-- Ringe sind ab RebuildRingEnd (u=0.6) ausgebaut.
Phase7.update(Config.phase7Rebuild * (Config.phase7RebuildRingEnd - 0.5))
check(near(Phase7.revealScale(), 1, 0.01), "Rebuild: Ringe sind ab RebuildRingEnd ausgebaut (Skala ~1)")
-- Exit: Figuren kommen radial aus dem Kern heraus (Baby leicht voraus, eigene
-- Winkel).
Phase7.update(Config.phase7Rebuild * (0.7 - Config.phase7RebuildRingEnd))
local p1x, p1y, p1a = Phase7.playerPosAndAngle()
local b1x, b1y, b1a = Phase7.babyPosAndAngle()
local p1r = math.sqrt((p1x - Config.centerX) ^ 2 + (p1y - Config.centerY) ^ 2)
local b1r = math.sqrt((b1x - Config.centerX) ^ 2 + (b1y - Config.centerY) ^ 2)
check(p1r > Config.coreRadius + 6 * Config.coreGrowthPerRoom and p1r < Config.outerRadius,
    "Player-Exit: mittlerer Radius zwischen Kern und Ringbahn")
check(b1r > Config.coreRadius + 6 * Config.coreGrowthPerRoom and b1r < Config.outerRadius,
    "Baby-Exit: mittlerer Radius zwischen Kern und Ringbahn")
check(near(p1a, 135, 0.001), "Player-Exit: eigener Winkel bleibt (135)")
check(near(b1a, 145, 0.001), "Baby-Exit: eigener Winkel bleibt (145)")
check(not Phase7.hidesFigures(), "Rebuild: beim Figuren-Exit werden Figuren gezeichnet")
-- Ende: sauberes Landing auf der Ringbahn (Radius 104 = Startring Raum 8).
Phase7.update(Config.phase7Rebuild * (0.999 - 0.7))
local p2x, p2y, p2a = Phase7.playerPosAndAngle()
local p2r = math.sqrt((p2x - Config.centerX) ^ 2 + (p2y - Config.centerY) ^ 2)
check(near(p2r, Config.outerRadius, 1), "Player: sauberes Landing auf der Ringbahn (Radius ~104)")
check(near(p2a, 135, 0.001), "Player: Landewinkel = eigener Winkel (kein Snap)")
check(Phase7.exitProgress() > 0.99, "Rebuild: Exit-Fortschritt ~1 am Ende")

-- --- Tutorial-Sperre ab Phase 2 --------------------------------------------
check(Tutorial.enabledForRoom(7) == true, "Tutorial: Raum 7 erlaubt Tutorials (Lernphase)")
check(Tutorial.enabledForRoom(8) == false, "Tutorial: Raum 8 = KEINE Tutorials (Phase 2)")
check(Tutorial.enabledForRoom(9) == false, "Tutorial: ab Raum 8 keine Tutorials")
check(Tutorial.maybeStartFocus(8) == false, "Tutorial: kein Mechanik-Fokus in Raum 8")
check(Tutorial.checkElementTriggers(8, nil) == false, "Tutorial: keine Kontext-Erklärungen in Raum 8")
check(Tutorial.checkLevelHints(8) == nil, "Tutorial: keine Level-1-Hinweise in Raum 8")

-- --- Aufräumen --------------------------------------------------------------
Phase7.reset()
check(not Phase7.isActive(), "Phase7: reset beendet den Übergang")
check(near(Phase7.revealScale(), 1), "Phase7: revealScale inaktiv = 1 (kein Skalieren)")
Camera.clearRevealScale()
Camera.clearRestartScale()

TestReport.phase7 = { pass = pass, fail = fail }
