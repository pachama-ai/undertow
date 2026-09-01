-- level8_top_left_check.lua — GEZIELTE PRÜFUNG des sichtbaren Ringabschnitts
-- oben links im Level 8 (ÄUSSERE Ringbahn, ca. 10-11 Uhr = ~300-340°).
--
-- Auf diesem Abschnitt liegen DREI finale Blenden (Shutter):
--   S_FINAL_D1 @305  (Bogen [292,318]) — logisch offen, wenn D1 = A
--   S_FINAL_D2 @322  (Bogen [309,335]) — logisch offen, wenn D2 = B
--   S_FINAL_O  @340  (Bogen [327,353]) — logisch offen, wenn O verbraucht (O=B)
--
-- Der Test beweist mit der ECHTEN Kollisionslogik (Room.movePlayer /
-- Room.syncPhysicalShutters / Room.shutters[*].collisionActive):
--   1. Was ist das Element genau (Daten + Bogenbereiche).
--   2. Ist der Abschnitt für den Player begehbar (Start- vs. Sollzustand).
--   3. In welchen D1/D2/O-Zuständen ist jede Blende offen/geschlossen.
--   4. Blockiert er einen Schritt des Lösungswegs (Phase 11)?
--   5. Nutzt der automatische Lösungstest eine Bewegung, die ein echter
--      Spieler mit der Crank nicht ausführen kann? (Antwort: Nein — der Test
--      ruft exakt dieselbe Room.movePlayer-Funktion auf, die main.lua bei
--      jeder Crank-Bewegung aufruft; zusätzlich wird die Gleichwertigkeit
--      großer vs. fraktionierter Crank-Drehungen nachgewiesen.)
--
-- Ergebnis wird in TestReport.level8TopLeft gesammelt.

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
    return math.abs(a - b) <= (tolerance or 0.5)
end

-- --- Setup: Level 8 frisch --------------------------------------------------
State.init(Levels[8], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[8].rings.outer)
Render.resetPlayerVisual()

-- ===========================================================================
--  1. WAS IST DAS ELEMENT? (Daten + Bogenbereiche)
-- ===========================================================================
local sFD1, sFD2, sFO
for _, sh in ipairs(Levels[8].shutters) do
    if sh.id == "S_FINAL_D1" then sFD1 = sh end
    if sh.id == "S_FINAL_D2" then sFD2 = sh end
    if sh.id == "S_FINAL_O" then sFO = sh end
end
check(sFD1 ~= nil and sFD2 ~= nil and sFO ~= nil, "daten: alle 3 finalen Shutter vorhanden")
check(sFD1 ~= nil and sFD1.ring == "outer" and approx(sFD1.angle, 305, 0.01), "daten: S_FINAL_D1 = Blende auf OUTER @305")
check(sFD2 ~= nil and sFD2.ring == "outer" and approx(sFD2.angle, 322, 0.01), "daten: S_FINAL_D2 = Blende auf OUTER @322")
check(sFO ~= nil and sFO.ring == "outer" and approx(sFO.angle, 340, 0.01), "daten: S_FINAL_O = Blende auf OUTER @340")
local half = Config.shutterArcWidth / 2
check(approx(sFD1.angle - half, 292, 0.01) and approx(sFD1.angle + half, 318, 0.01), "daten: S_FD1-Bogen [292,318] (Blende 26° breit)")
check(approx(sFD2.angle - half, 309, 0.01) and approx(sFD2.angle + half, 335, 0.01), "daten: S_FD2-Bogen [309,335]")
check(approx(sFO.angle - half, 327, 0.01) and approx(sFO.angle + half, 353, 0.01), "daten: S_FO-Bogen [327,353]")

-- ===========================================================================
--  2. STARTZUSTAND: logisch + physisch + ECHTE Bewegung
-- ===========================================================================
check(State.elementStates["S_FINAL_D1"] == true, "start: S_FD1 logisch OFFEN (D1=A)")
check(State.elementStates["S_FINAL_D2"] == false, "start: S_FD2 logisch GESCHLOSSEN (D2=A)")
check(State.elementStates["S_FINAL_O"] == false, "start: S_FO logisch GESCHLOSSEN (O=A)")
Room.syncPhysicalShutters()
check(Room.shutters["S_FINAL_D1"].collisionActive == false, "start: S_FD1 physisch NICHT kollisionsaktiv (offen)")
check(Room.shutters["S_FINAL_D2"].collisionActive == true, "start: S_FD2 physisch KOLLISIONSAKTIV (blockiert)")
check(Room.shutters["S_FINAL_O"].collisionActive == true, "start: S_FO physisch KOLLISIONSAKTIV (blockiert)")

-- ECHTE Bewegung im Startzustand: Player startet outer@20, läuft CW Richtung
-- oberer linker Abschnitt. Der Weg 20 -> 309 kreuzt KEINE geschlossene Blende
-- (S_FD1 ist offen; Brücken/Platten blockieren nie). Er MUSS blockiert werden.
-- WICHTIG: Der Player schiebt dabei das Baby CW vor sich her; das Baby stößt
-- zuerst an die geschlossene S_FD2-Kante (309), der Player stoppt im Kontakt-
-- abstand dahinter — beide kommen nicht durch den Abschnitt.
local _, rStart = Room.movePlayer(289) -- 20 -> CW Richtung 309 (S_FD2-Eintritt)
check(rStart.blocked == true, "start-lauf: Player PRALLT an S_FD2 — Abschnitt oben links im Startzustand BLOCKIERT")
print("  TOPLEFT start-lauf: Player stoppt bei " .. string.format("%.1f", State.player.angle)
    .. ", Baby bei " .. string.format("%.1f", State.baby.angle) .. " (S_FD2-Eintritt 309)")
check(State.player.angle < 309, "start-lauf: Player kommt NICHT durch den Abschnitt (Stopp < 309)")
check(State.baby ~= nil and State.baby.angle < 309, "start-lauf: Baby kommt ebenfalls nicht durch (Stopp < 309)")

-- Auch von der ANDEREN Seite: Player kann nicht von 350 CCW durch S_FO (zu).
State.player.ring = "outer"
State.player.angle = 355
Room.syncPhysicalShutters()
local _, rStart2 = Room.movePlayer(-5) -- 355 -> 350 (CCW, in S_FO-Bogen [327,353])
check(rStart2.blocked == true, "start-lauf-2: CCW von 355 PRALLT an S_FO (353) — Abschnitt auch von der Torseite blockiert")
check(approx(State.player.angle, 353, 1.0), "start-lauf-2: Player stoppt exakt an der S_FO-Eintrittskante (353)")

-- ===========================================================================
--  3./4. ZUSTANDSABHÄNGIGKEIT entlang des ECHTEN Lösungswegs + Phase 11
-- ===========================================================================
-- Frisches Setup, dann den vollständigen legitimen Lösungsweg abspielen und
-- die 3 Shutter nach jedem Schalterwechsel gezielt prüfen.
State.init(Levels[8], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[8].rings.outer)
Render.resetPlayerVisual()

local function shunters()
    return (State.elementStates["S_FINAL_D1"] == true) .. "/"
        .. (State.elementStates["S_FINAL_D2"] == true) .. "/"
        .. (State.elementStates["S_FINAL_O"] == true)
end

-- Phase 1: Baby auf P1, Solo über A (inner@112)
Room.movePlayer(101.83)
Room.tryUseConnection()
Bridge.update(0.5)
-- Phase 2: D1=B
Room.movePlayer(-49)
check(State.elementStates["S_FINAL_D1"] == false, "phase2: D1=B -> S_FD1 GESCHLOSSEN (offen nur bei D1=A)")
Room.tryUseConnection()
Bridge.update(0.5)
-- Phase 3: Baby auf P2
Room.movePlayer(65.83)
-- Phase 4: Solo C, D1=A (Zwischenziel)
Room.tryUseConnection()
Bridge.update(0.5)
Room.movePlayer(-45)
Room.movePlayer(15)
check(State.elementStates["S_FINAL_D1"] == true, "phase4: D1=A -> S_FD1 OFFEN (erste Hälfte des oberen Abschnitts frei)")
check(State.elementStates["S_FINAL_D2"] == false, "phase4: D2=A -> S_FD2 weiter GESCHLOSSEN")
-- Phase 5: O verbrauchen
Room.movePlayer(106)
Room.movePlayer(-15)
check(State.elementStates["S_FINAL_O"] == true, "phase5: O verbraucht -> S_FO OFFEN (dritte Hälfte frei)")
-- Phase 6: D1=B
Room.movePlayer(-130)
check(State.elementStates["S_FINAL_D1"] == false, "phase6: D1=B -> S_FD1 wieder GESCHLOSSEN")
Room.tryUseConnection()
Bridge.update(0.5)
-- Phase 7: Baby auf P3
Room.movePlayer(96.83)
-- Phase 8: Einstieg über B (B aktiv, D1=B), D1=A, D2=B (FINALZUSTAND)
Room.movePlayer(-96.83)
Room.tryUseConnection()
Bridge.update(0.5)
Room.movePlayer(12)
Room.movePlayer(15)
Room.movePlayer(146) -- D2-CW-Anlauf 102 -> 248 (No-op, bleibt A)
Room.movePlayer(-15) -- D2 CCW -> B
check(State.elementStates["S_FINAL_D1"] == true, "phase8: D1=A -> S_FD1 OFFEN")
check(State.elementStates["S_FINAL_D2"] == true, "phase8: D2=B -> S_FD2 OFFEN")
check(State.elementStates["S_FINAL_O"] == true, "phase8: O=B -> S_FO OFFEN (alle 3 offen = FINALZUSTAND)")
-- Phase 9: D zurück (inner 233 -> 220, Solo -> outer@220)
Room.movePlayer(-13)
Room.tryUseConnection()
Bridge.update(0.5)
-- Phase 10: Baby zu U, gemeinsam über U (inner@45/35)
Room.movePlayer(311.83)
Room.movePlayer(225)
Room.tryUseConnection()
Bridge.update(0.5)
-- Phase 11: Tor liegt auf dem INNEREN Ring (inner@355) — direkter CCW-Schub
-- vom U-Landeplatz (inner@45/35) zum Tor (vermeidet S_D2, S_FI offen).

-- === ECHTE DURCHFAHRT im FINALZUSTAND ===
-- Tor T@355 (inner). Der Player schiebt das Baby CCW 45 -> 5 (Baby 35 -> ~357)
-- direkt zum Tor; der obere linke Abschnitt (S_FD1/S_FD2/S_FO, outer) bleibt
-- im Finalzustand physisch offen (Anti-Blockade).
check(Room.shutters["S_FINAL_D1"].collisionActive == false
    and Room.shutters["S_FINAL_D2"].collisionActive == false
    and Room.shutters["S_FINAL_O"].collisionActive == false,
    "phase11: alle 3 Shutter oben links physisch NICHT kollisionsaktiv (Finalzustand)")
local _, rFinal = Room.movePlayer(-40) -- CCW-Schub 45 -> 5 (Baby 35 -> ~357 = Tor)
check(rFinal.blocked == false, "phase11: ECHTE Durchfahrt zum Tor (inner@355) NICHT blockiert — FINALZUSTAND FREI")
check(approx(State.player.angle, 5, 1.0), "phase11: Player steht am Tor-Dock (inner@5)")
check(approx(State.baby.angle, 355, 2.0), "phase11: Baby am Tor (355)")

-- ===========================================================================
--  5. EINGABE-GLEICHWERTIGKEIT: großes Delta == viele kleine Crank-Schritte
-- ===========================================================================
-- Room.movePlayer ist DIE Funktion, die main.lua bei jeder Crank-Bewegung
-- aufruft. Die Sweep-/Switch-Logik ist frame-agnostisch (Release-Fix 1:
-- Eintritt armiert, Austritt löst aus — über beliebig viele Frames). Beweis:
-- dieselbe Durchfahrt einmal in EINEM großen Delta, einmal in 52 kleinen
-- Crank-Schritten — identisches Ergebnis.
State.init(Levels[8], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[8].rings.outer)
Render.resetPlayerVisual()
-- Zustand gezielt über ECHTE Spielaktionen auf den Finalzustand bringen ist
-- lang; hier reicht der Nachweis der Deltagrößen-Gleichwertigkeit an einem
-- frühen, kollisionsrelevanten Punkt: der Abschnitt oben links ist im Start
-- zu — ein kleines CW-Delta von 20 muss GENAU SO an 309 stoppen wie das große.
local _, rBig = Room.movePlayer(289)      -- 1 großes Delta
local bigAngle = State.player.angle
State.init(Levels[8], true)
Room.init()
Undo.clear()
Bridge.resetTransit()
Baby.resetTransit()
Room.resetDockAssist()
Camera.init(Levels[8].rings.outer)
Render.resetPlayerVisual()
local blockedSmall = false
for i = 1, 52 do
    local _, rs = Room.movePlayer(5.5) -- 52 x 5.5° ≈ 286° in kleinen Crank-Schritten
    if rs.blocked then
        blockedSmall = true
        break
    end
end
check(blockedSmall == true, "eingabe: 52 kleine Crank-Schritte (je 5.5°) werden GENAU SO an S_FD2 blockiert")
check(approx(State.player.angle, bigAngle, 1.0), "eingabe: Endposition identisch (großes Delta == viele kleine Crank-Schritte)")

-- ===========================================================================
--  ZUSAMMENFASSUNG
-- ===========================================================================
print("LEVEL8_TOP_LEFT: pass=" .. pass .. " fail=" .. fail)
check(fail == 0, "level8-top-left: Prüfung des oberen linken Abschnitts OHNE Fehler")

TestReport.level8TopLeft = { pass = pass, fail = fail }
