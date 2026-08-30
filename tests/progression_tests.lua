-- Tests für die Abschlussphase-A-Progression (Räume 4-8): Die Controller-
-- Entscheidung (vorrücken bei levels[nextIndex] ~= nil, sonst Completion) wird
-- gegen die echten Leveldaten + das Save-Modul unit-seitig verifiziert.
--
-- Die eigentliche Progressionslogik (handleConnectionResult) lebt im
-- Composition Root (source/main.lua, nicht importierbar) und wird über den
-- Produktions-Smoke End-to-End geprüft; hier wird die Datenvorbedingung
-- (alle 8 Räume, Ringkontinuität, kein Raum 9) und die Save-Semantik
-- (1->2->...->8, kein Write über Raum 8 hinaus) abgesichert.
--
-- Erwartet, dass core/config, core/geometry, core/save und data/levels per
-- import geladen wurden (siehe tools/run_tests.ps1). Ergebnis in
-- TestReport.progression.

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

-- --- 1) Datenvorbedingung: alle 8 Räume, kein Raum 9 ------------------------
check(#Levels == 8, "prog: Levels enthält exakt 8 Räume")
check(Levels[1] ~= nil and Levels[8] ~= nil, "prog: Raum 1 und Raum 8 vorhanden")
check(Levels[9] == nil, "prog: kein Raum 9 (Room8-Completion lädt nichts)")

-- --- 2) Ringkontinuität 7/6 -> 6/5 -> ... -> 1/0 -> 0/-1 (Punkt 3) -----------
-- Geteilter Ring: der alte Innenring wird der neue Außenring
-- (inner[i] == outer[i+1], wie im Camera-Übergang genutzt).
local ringContinuityOk = true
for i = 1, 7 do
    if Levels[i].rings.inner ~= Levels[i + 1].rings.outer then
        ringContinuityOk = false
    end
end
check(ringContinuityOk, "prog: Ringkontinuität inner[i] == outer[i+1] für i=1..7")
check(Levels[1].rings.outer == 7 and Levels[8].rings.inner == -1,
    "prog: R1 outer 7, R8 inner -1")
check(Levels[8].rings.outer == 0 and Levels[8].rings.inner == -1,
    "prog: R8 outer/inner = 0/-1 (innerster Ring)")

-- --- 3) Progression 1->2, ..., 7->8: levels[nextIndex] ~= nil (Punkt 44-46) --
for i = 1, 7 do
    check(Levels[i + 1] ~= nil,
        "prog: " .. i .. "->" .. (i + 1) .. " hat nächsten Raum")
end

-- --- 4) Room8-Completion: nextIndex 9 existiert nicht (Punkt 47) ------------
check(Levels[8 + 1] == nil, "prog: Room8 nextIndex 9 existiert nicht -> Completion")

-- --- 5) Save-Semantik bis Raum 8 (Punkt 14/15) -------------------------------
local nh, sw
nh, sw = Save.applyProgress(4, 5)
check(nh == 5 and sw == true, "prog: 4->5 schreibt Save 5")
nh, sw = Save.applyProgress(5, 6)
check(nh == 6 and sw == true, "prog: 5->6 schreibt Save 6")
nh, sw = Save.applyProgress(6, 7)
check(nh == 7 and sw == true, "prog: 6->7 schreibt Save 7")
nh, sw = Save.applyProgress(7, 8)
check(nh == 8 and sw == true, "prog: 7->8 schreibt Save 8")
nh, sw = Save.applyProgress(8, 8)
check(nh == 8 and sw == false, "prog: Room8-Completion (8->8) schreibt nicht")

-- --- 6) Continue-Ziele Save 1..8 (Punkt 16) ---------------------------------
for i = 1, 8 do
    check(Levels[i] ~= nil and type(Levels[i].name) == "string",
        "prog: Continue " .. i .. " hat Raum (" .. (Levels[i] and Levels[i].name or "?") .. ")")
end

-- --- 7) Zu hoher Save clamp auf letzten Levelindex (Punkt 17) ---------------
local realDatastore = playdate.datastore
playdate.datastore = {
    read = function() return { highestRoom = 99 } end,
    write = function() end,
    delete = function() return true end,
}
local clamped = Save.load(8, #Levels)
check(clamped == 8, "prog: Save 99 -> clamp 8 (nicht mehr 7)")
check(clamped == #Levels, "prog: Clamp == tatsächlicher letzter Levelindex")
playdate.datastore = realDatastore

TestReport.progression = { pass = pass, fail = fail }
