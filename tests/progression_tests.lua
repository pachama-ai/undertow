-- Tests für die Abschlussphase-A-Progression (Räume 4-6): Die Controller-
-- Entscheidung (vorrücken bei levels[nextIndex] ~= nil, sonst Completion) wird
-- gegen die echten Leveldaten + das Save-Modul unit-seitig verifiziert.
--
-- Die eigentliche Progressionslogik (handleConnectionResult) lebt im
-- Composition Root (source/main.lua, nicht importierbar) und wird über den
-- Produktions-Smoke End-to-End geprüft; hier wird die Datenvorbedingung
-- (alle 6 Räume, Ringkontinuität, kein Raum 7) und die Save-Semantik
-- (1->2->...->6, kein Write über Raum 6 hinaus) abgesichert.
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

-- --- 1) Datenvorbedingung: alle 6 Räume, kein Raum 7 ------------------------
check(#Levels == 6, "prog: Levels enthält exakt 6 Räume")
check(Levels[1] ~= nil and Levels[6] ~= nil, "prog: Raum 1 und Raum 6 vorhanden")
check(Levels[7] == nil, "prog: kein Raum 7 (Room6-Completion lädt nichts)")

-- --- 2) Ringkontinuität 7/6 -> 6/5 -> 5/4 -> 4/3 -> 3/2 -> 2/1 (Punkt 3) ----
-- Geteilter Ring: der alte Innenring wird der neue Außenring
-- (inner[i] == outer[i+1], wie im Camera-Übergang genutzt).
local ringContinuityOk = true
for i = 1, 5 do
    if Levels[i].rings.inner ~= Levels[i + 1].rings.outer then
        ringContinuityOk = false
    end
end
check(ringContinuityOk, "prog: Ringkontinuität inner[i] == outer[i+1] für i=1..5")
check(Levels[1].rings.outer == 7 and Levels[6].rings.inner == 1,
    "prog: R1 outer 7, R6 inner 1")
check(Levels[6].rings.outer == 2 and Levels[6].rings.inner == 1,
    "prog: R6 outer/inner = 2/1 (innerster Ring)")

-- --- 3) Progression 1->2, ..., 5->6: levels[nextIndex] ~= nil (Punkt 44-46) --
for i = 1, 5 do
    check(Levels[i + 1] ~= nil,
        "prog: " .. i .. "->" .. (i + 1) .. " hat nächsten Raum")
end

-- --- 4) Room6-Completion: nextIndex 7 existiert nicht (Punkt 47) ------------
check(Levels[6 + 1] == nil, "prog: Room6 nextIndex 7 existiert nicht -> Completion")

-- --- 5) Save-Semantik bis Raum 6 (Punkt 14/15) -------------------------------
local nh, sw
nh, sw = Save.applyProgress(3, 4)
check(nh == 4 and sw == true, "prog: 3->4 schreibt Save 4")
nh, sw = Save.applyProgress(4, 5)
check(nh == 5 and sw == true, "prog: 4->5 schreibt Save 5")
nh, sw = Save.applyProgress(5, 6)
check(nh == 6 and sw == true, "prog: 5->6 schreibt Save 6")
nh, sw = Save.applyProgress(6, 6)
check(nh == 6 and sw == false, "prog: Room6-Completion (6->6) schreibt nicht")
nh, sw = Save.applyProgress(6, 7)
check(nh == 7 and sw == true,
    "prog: apply 6->7 gäbe (7,true) — Controller ruft es aber nie (kein Raum 7)")

-- --- 6) Continue-Ziele Save 1..6 (Punkt 16) ---------------------------------
for i = 1, 6 do
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
local clamped = Save.load(6, #Levels)
check(clamped == 6, "prog: Save 99 -> clamp 6 (nicht mehr 3)")
check(clamped == #Levels, "prog: Clamp == tatsächlicher letzter Levelindex")
playdate.datastore = realDatastore

TestReport.progression = { pass = pass, fail = fail }
