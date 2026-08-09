-- Undo: verwaltet einen LIFO-Stack von State-Snapshots für den laufenden Raum.
-- Maximal 64 Einträge. Undo erstellt selbst keine Snapshots und kennt keinen
-- Frame, keinen Sweep und kein Undo-Timing — die Entscheidung, wann gepusht
-- wird, trifft das spätere Movement-/Sweep-System.
--
-- Pro-Frame-Regel (verbindlich, Architektur):
--   Pro Frame entsteht höchstens ein Undo-Eintrag. Ein Sweep kann mehrere
--   Schalter überfahren; der Aufrufer pusht den Frame-Start-Snapshot nur beim
--   ersten tatsächlich zustandsändernden Ereignis (anhand des `changed`-
--   Rückgabewerts von State.setSwitch). Undo erfindet keine Frame-ID und
--   implementiert keine Sweep-Logik.

Undo = {}

local state <const> = State

local MAX_ENTRIES <const> = 64

-- Interner LIFO-Stack (Array). Undo besitzt die gespeicherten Snapshots.
local stack = {}

-- Erzeugt eine unabhängige interne Kopie eines State-Snapshots. Eine spätere
-- externe Mutation der übergebenen Tabelle darf keinen gespeicherten
-- Undo-Eintrag beschädigen (Snapshot-Isolation).
local function copySnapshot(snap)
    local copy = {}
    copy.switchStates = {}
    for id, s in pairs(snap.switchStates) do
        copy.switchStates[id] = s
    end
    copy.elementStates = {}
    for id, v in pairs(snap.elementStates) do
        copy.elementStates[id] = v
    end
    copy.player = {
        ring = snap.player.ring,
        angle = snap.player.angle,
    }
    return copy
end

-- Entfernt alle gespeicherten Snapshots. Verändert den aktuellen State nicht.
function Undo.clear()
    for i = #stack, 1, -1 do
        stack[i] = nil
    end
end

-- Anzahl der gespeicherten Snapshots.
function Undo.count()
    return #stack
end

-- Legt einen Snapshot oben auf dem Stack. Bei vollen 64 Einträgen wird der
-- älteste entfernt; die neuesten 64 bleiben erhalten.
function Undo.push(snapshot)
    if #stack >= MAX_ENTRIES then
        table.remove(stack, 1)
    end
    stack[#stack + 1] = copySnapshot(snapshot)
end

-- Stellt den neuesten Snapshot wieder her (LIFO). Stellt Weltzustand UND
-- Spielerposition wieder her (Snapshot stammt vom Beginn der Spielerhandlung).
-- Rückgabe true bei Erfolg, false wenn der Stack leer ist (dann wird nichts am
-- State verändert und kein Fehler geworfen).
function Undo.undo()
    local n = #stack
    if n == 0 then
        return false
    end
    local snap = stack[n]
    stack[n] = nil
    state.restore(snap)
    return true
end

return Undo