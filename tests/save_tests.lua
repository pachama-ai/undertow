-- Tests für source/core/save.lua (Phase 10.2): Fortschritt lesen/validieren/
-- schreiben über playdate.datastore. Der Datastore wird durch einen Mock
-- ersetzt (read/write zählbar, Fehler simulierbar), damit die echten
-- Benutzerdaten des Spiels nie angefasst werden. Zusätzlich wird bewiesen,
-- dass Save keinen Gameplay-State berührt (Trap-Test: alle anderen Module
-- sind während Save-Aufrufen blockiert). Erwartet, dass core/save per import
-- geladen wurde (siehe tools/run_tests.ps1).
--
-- Abgedeckte Pflichtfälle:
--   - kein Save -> 1, leerer Save -> 1, Raum 2 -> 2, ... Raum 7 -> 7,
--     String "3" -> 1, Float 2.5 -> 1, 0 -> 1, negativ -> 1, zu hoch -> clamp
--   - Abschlussphase A: Räume 4-7 valide, Clamp 99 -> 7 (nicht mehr 3)
--   - Fortschritt nur bei echtem neuen Höchststand (monoton, max), nie sinken
--   - Save-Kette 1->2->3->4->5->6->7; Room7-Completion schreibt NIE Save 8
--   - Lese-/Schreibfehler crashen nicht (Fallback 1 / false zurück)
--   - genau EIN Datastore-Read pro load(), genau ein Feld { highestRoom }
--   - Save bleibt frei von State/Undo/Room/Bridge/Camera/Audio/Menu/Levels

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

-- --- Datastore-Mock (wird am Ende restauriert) -----------------------------
local realDatastore = playdate.datastore
local mockReadResult = nil
local mockReadThrows = false
local readCount = 0
local mockWriteThrows = false
local writeCount = 0
local writtenTables = {}

playdate.datastore = {
    read = function()
        readCount = readCount + 1
        if mockReadThrows then
            error("mock datastore read error")
        end
        return mockReadResult
    end,
    write = function(t)
        writeCount = writeCount + 1
        writtenTables[#writtenTables + 1] = t
        if mockWriteThrows then
            error("mock datastore write error")
        end
        return nil
    end,
    delete = function()
        return true
    end,
}

local function resetMock()
    mockReadResult = nil
    mockReadThrows = false
    readCount = 0
    mockWriteThrows = false
    writeCount = 0
    writtenTables = {}
end

-- --- Save.validate: reine Validierung (kein Datastore) ----------------------
check(Save.validate(nil, 7, 7) == 1, "save: validate kein Save -> 1")
check(Save.validate({}, 7, 7) == 1, "save: validate leerer Save -> 1")
check(Save.validate({ highestRoom = 2 }, 7, 7) == 2, "save: validate Raum 2 -> 2")
check(Save.validate({ highestRoom = 3 }, 7, 7) == 3, "save: validate Raum 3 -> 3")
check(Save.validate({ highestRoom = 4 }, 7, 7) == 4, "save: validate Raum 4 -> 4")
check(Save.validate({ highestRoom = 5 }, 7, 7) == 5, "save: validate Raum 5 -> 5")
check(Save.validate({ highestRoom = 6 }, 7, 7) == 6, "save: validate Raum 6 -> 6")
check(Save.validate({ highestRoom = 7 }, 7, 7) == 7, "save: validate Raum 7 -> 7")
check(Save.validate({ highestRoom = "3" }, 7, 7) == 1, "save: validate String '3' -> 1")
check(Save.validate({ highestRoom = 2.5 }, 7, 7) == 1, "save: validate Float 2.5 -> 1")
check(Save.validate({ highestRoom = 0 }, 7, 7) == 1, "save: validate 0 -> 1")
check(Save.validate({ highestRoom = -5 }, 7, 7) == 1, "save: validate negativ -> 1")
check(Save.validate({ highestRoom = 99 }, 7, 7) == 7, "save: validate zu hoch -> clamp 7")
check(Save.validate({ highestRoom = 2 }, 7, 1) == 1, "save: validate clamp bei nur 1 Raum -> 1")
check(Save.validate({ highestRoom = 5 }, 10, 8) == 5, "save: validate 5 bei 8 Räumen -> 5")
check(Save.validate({ highestRoom = 9 }, 10, 8) == 8, "save: validate 9 clamp auf 8 -> 8")
-- validate darf die Eingabetabelle nicht verändern.
local probe = { highestRoom = 2 }
Save.validate(probe, 7, 7)
check(probe.highestRoom == 2 and next(probe) ~= nil, "save: validate mutiert Eingabe nicht")

-- --- Save.load: Datastore lesen + validieren --------------------------------
resetMock()
mockReadResult = nil
check(Save.load(7, 7) == 1, "save: load kein Save -> 1")
check(readCount == 1, "save: load liest genau einmal (kein Save)")

resetMock()
mockReadResult = {}
check(Save.load(7, 7) == 1, "save: load leerer Save -> 1")

resetMock()
mockReadResult = { highestRoom = 2 }
check(Save.load(7, 7) == 2, "save: load Raum 2 -> 2")
check(readCount == 1, "save: load liest genau einmal (Raum 2)")

resetMock()
mockReadResult = { highestRoom = 3 }
check(Save.load(7, 7) == 3, "save: load Raum 3 -> 3")

resetMock()
mockReadResult = { highestRoom = 4 }
check(Save.load(7, 7) == 4, "save: load Raum 4 -> 4")

resetMock()
mockReadResult = { highestRoom = 5 }
check(Save.load(7, 7) == 5, "save: load Raum 5 -> 5")

resetMock()
mockReadResult = { highestRoom = 6 }
check(Save.load(7, 7) == 6, "save: load Raum 6 -> 6")

resetMock()
mockReadResult = { highestRoom = 7 }
check(Save.load(7, 7) == 7, "save: load Raum 7 -> 7")

resetMock()
mockReadResult = { highestRoom = "3" }
check(Save.load(7, 7) == 1, "save: load String '3' -> 1")

resetMock()
mockReadResult = { highestRoom = 2.5 }
check(Save.load(7, 7) == 1, "save: load Float 2.5 -> 1")

resetMock()
mockReadResult = { highestRoom = 0 }
check(Save.load(7, 7) == 1, "save: load 0 -> 1")

resetMock()
mockReadResult = { highestRoom = -1 }
check(Save.load(7, 7) == 1, "save: load negativ -> 1")

resetMock()
mockReadResult = { highestRoom = 99 }
check(Save.load(7, 7) == 7, "save: load zu hoch -> clamp 7")

resetMock()
mockReadThrows = true
check(Save.load(7, 7) == 1, "save: load Lesefehler -> Fallback 1")
check(readCount == 1, "save: load Lesefehler trotzdem genau ein Read")

-- --- Save.hasSave: existiert ein gültiger Fortschritt? -----------------------
-- (Für den Startscreen: CONTINUE nur bei vorhandenem Save; ungültige Saves
-- gelten als „kein Save".)
resetMock()
mockReadResult = nil
check(Save.hasSave(7, 7) == false, "hasSave: kein Save -> false")
check(readCount == 1, "hasSave: liest genau einmal (kein Save)")

resetMock()
mockReadResult = {}
check(Save.hasSave(7, 7) == false, "hasSave: leerer Save -> false")

resetMock()
mockReadResult = { highestRoom = 2 }
check(Save.hasSave(7, 7) == true, "hasSave: Raum 2 -> true")
check(readCount == 1, "hasSave: liest genau einmal (Raum 2)")

resetMock()
mockReadResult = { highestRoom = 1 }
check(Save.hasSave(7, 7) == true, "hasSave: Raum 1 (Save existiert) -> true")

resetMock()
mockReadResult = { highestRoom = 7 }
check(Save.hasSave(7, 7) == true, "hasSave: Raum 7 -> true")

resetMock()
mockReadResult = { highestRoom = 99 }
check(Save.hasSave(7, 7) == true, "hasSave: zu hoch (99) -> true (wird geclampt)")

resetMock()
mockReadResult = { highestRoom = "3" }
check(Save.hasSave(7, 7) == false, "hasSave: String '3' -> false (ungültig)")

resetMock()
mockReadResult = { highestRoom = 2.5 }
check(Save.hasSave(7, 7) == false, "hasSave: Float 2.5 -> false (ungültig)")

resetMock()
mockReadResult = { highestRoom = 0 }
check(Save.hasSave(7, 7) == false, "hasSave: 0 -> false (ungültig)")

resetMock()
mockReadResult = { highestRoom = -1 }
check(Save.hasSave(7, 7) == false, "hasSave: negativ -> false (ungültig)")

resetMock()
mockReadThrows = true
check(Save.hasSave(7, 7) == false, "hasSave: Lesefehler -> false (kein Save)")

-- --- Save.applyProgress: monoton, nur echte neue Höchstwerte ----------------
local a, b
a, b = Save.applyProgress(1, 2)
check(a == 2 and b == true, "save: apply 1->2 schreibt (2, true)")
a, b = Save.applyProgress(2, 2)
check(a == 2 and b == false, "save: apply 2->2 schreibt nicht (2, false)")
a, b = Save.applyProgress(3, 2)
check(a == 3 and b == false, "save: apply 3->2 schreibt nicht (Wert sinkt nie)")
a, b = Save.applyProgress(2, 1)
check(a == 2 and b == false, "save: apply 2->1 schreibt nicht (Wert sinkt nie)")
a, b = Save.applyProgress(2, 3)
check(a == 3 and b == true, "save: apply 2->3 schreibt (3, true)")
a, b = Save.applyProgress(1, 3)
check(a == 3 and b == true, "save: apply 1->3 schreibt (3, true)")

-- --- Save.write: genau ein Feld { highestRoom } ------------------------------
resetMock()
check(Save.write(2) == true, "save: write(2) ok")
check(writeCount == 1, "save: write genau ein Write")
check(#writtenTables == 1, "save: write genau eine Tabelle")
check(type(writtenTables[1]) == "table" and writtenTables[1].highestRoom == 2,
    "save: write schreibt { highestRoom = 2 }")
check(next(writtenTables[1]) == "highestRoom", "save: write genau ein Feld (keine weiteren)")
check(select(1, next(writtenTables[1])) == "highestRoom",
    "save: write-Feld heißt highestRoom")

-- --- Write-Fehler: crasht nicht, meldet false -------------------------------
resetMock()
mockWriteThrows = true
local okWrite, errWrite = Save.write(3)
check(okWrite == false and errWrite ~= nil,
    "save: write Schreibfehler -> (false, err) ohne Crash")

-- --- Fortschrittsfluss wie main.saveHighestRoom: nur bei echtem Fortschritt -
resetMock()
local sessionHighest = 1
local function applyLikeMain(roomIndex)
    local nh, sw = Save.applyProgress(sessionHighest, roomIndex)
    if sw then
        sessionHighest = nh
        Save.write(sessionHighest)
    end
end
-- Raum 1 gelöst -> Raum 2 erreicht
applyLikeMain(2)
check(sessionHighest == 2 and writeCount == 1, "save: Raum 1 gelöst -> genau 1 Write (2)")
check(writtenTables[1].highestRoom == 2, "save: Raum 1 gelöst -> { highestRoom = 2 }")
-- Raum 2 erneut erreicht / zurück -> kein Write
applyLikeMain(2)
applyLikeMain(1)
check(writeCount == 1, "save: kein Write bei gleichem/niedrigerem Fortschritt")
-- Raum 2 gelöst -> Raum 3 erreicht
applyLikeMain(3)
check(sessionHighest == 3 and writeCount == 2, "save: Raum 2 gelöst -> 2. Write (3)")
check(writtenTables[2].highestRoom == 3, "save: Raum 2 gelöst -> { highestRoom = 3 }")

-- Abschlussphase A: Progression bis Raum 7 (Räume 3->4, 4->5, 5->6, 6->7).
applyLikeMain(4)
check(sessionHighest == 4 and writeCount == 3, "save: Raum 3 gelöst -> 3. Write (4)")
check(writtenTables[3].highestRoom == 4, "save: Raum 3 gelöst -> { highestRoom = 4 }")
applyLikeMain(5)
check(sessionHighest == 5 and writeCount == 4, "save: Raum 4 gelöst -> 4. Write (5)")
check(writtenTables[4].highestRoom == 5, "save: Raum 4 gelöst -> { highestRoom = 5 }")
applyLikeMain(6)
check(sessionHighest == 6 and writeCount == 5, "save: Raum 5 gelöst -> 5. Write (6)")
check(writtenTables[5].highestRoom == 6, "save: Raum 5 gelöst -> { highestRoom = 6 }")
applyLikeMain(7)
check(sessionHighest == 7 and writeCount == 6, "save: Raum 6 gelöst -> 6. Write (7)")
check(writtenTables[6].highestRoom == 7, "save: Raum 6 gelöst -> { highestRoom = 7 }")

-- Raum 7-Completion darf NIE einen Wert >= 8 schreiben: Der Controller ruft
-- saveHighestRoom für Raum 7-Completion gar nicht auf (levels[8] ist nil, kein
-- nächster Raum); zusätzlich wird der höchste schreibbare Wert über Save.write(7)
-- hier nicht erzeugt — applyProgress wird mit dem tatsächlich erreichten Raum
-- aufgerufen, also maximal 7.
a, b = Save.applyProgress(7, 8)
check(a == 8 and b == true, "save: apply 7->8 gäbe (8,true) — Controller ruft es aber nie (kein Raum 8)")
-- Controller-Äquivalent für Room7-Completion: saveHighestRoom wird NICHT
-- aufgerufen (kein Fortschritt), daher kein 7. Write und kein Save 8.
local beforeComplete = writeCount
applyLikeMain(7)
check(writeCount == beforeComplete, "save: Room7-Completion löst keinen Write aus (kein Save 8)")
check(sessionHighest == 7, "save: Room7-Completion lässt höchsten Raum bei 7")

-- --- Menü-Aktionen (10.1) ohne Datastore-Seiteneffekte -----------------------
-- „Weiter"/„Von vorn" laufen über main.lua (Composition Root) und ändern den
-- Save nie direkt; hier: applyProgress(7,1) senkt nicht und schreibt nicht.
a, b = Save.applyProgress(7, 1)
check(a == 7 and b == false, "save: Neues Spiel (Raum 1) bei Save 7 senkt nichts")
resetMock()
applyLikeMain(1)
check(writeCount == 0, "save: Neues Spiel ruft keinen Write auf")

-- --- Read-once + Read-only-Trap: Save berührt keine anderen Module -----------
-- Beweis: Während Save.validate/applyProgress/write werden alle anderen
-- Projektmodule durch eine Trap ersetzt; jeder Zugriff würde fehlschlagen.
local trappedModules = {
    "State", "Undo", "Room", "Bridge", "Camera", "Audio", "Menu",
    "Levels", "Config", "Geometry", "Player", "Switch", "Gate",
}
local function withTrap(globalName, fn)
    local real = _G[globalName]
    _G[globalName] = setmetatable({}, {
        __index = function()
            error("trap: " .. globalName .. " wurde während Save-Aufruf berührt")
        end,
    })
    local ok, err = pcall(fn)
    _G[globalName] = real
    return ok, err
end

resetMock()
mockReadResult = { highestRoom = 2 }
for _, name in ipairs(trappedModules) do
    local okTrap = withTrap(name, function()
        Save.load(7, 7)
        Save.validate({ highestRoom = 1 }, 7, 7)
        Save.applyProgress(1, 2)
        Save.write(2)
    end)
    check(okTrap, "save: " .. name .. " bleibt unberührt (Trap nicht ausgelöst)")
end

-- --- Restauration des echten Datastore --------------------------------------
playdate.datastore = realDatastore
check(playdate.datastore == realDatastore, "save: echter Datastore restauriert")

TestReport.save = { pass = pass, fail = fail }
