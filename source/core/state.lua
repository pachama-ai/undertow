-- State: veränderlicher Laufzeitzustand des aktuellen Raums.
-- Hält die roomData-Referenz, Schalter- und Elementzustände sowie die
-- Spielerposition. Keine Projekt-Imports; die Raumdaten werden von außen
-- übergeben (State.init). Kein Undo, keine G7-Verzögerung, keine Animation:
-- elementStates beschreibt nur den logischen Sollzustand.

State = {}

-- Referenz auf die unveränderte Leveldefinition des aktuellen Raums.
-- State verändert diese Tabellen niemals.
State.room = nil

-- Schalterzustände: State.switchStates[id] = "A" | "B"
State.switchStates = {}

-- Elementzustände: State.elementStates[id] = true (aktiv) | false (inaktiv)
-- Blende: true = offen, false = geschlossen.
-- Brücke/Gate: true = ausgefahren, false = eingefahren.
State.elementStates = {}

-- Spielerposition. Nur ring und angle; keine Bewegungshistorie.
State.player = {
    ring = "outer",
    angle = 0,
}

-- Initialisiert einen komplett frischen Raumzustand.
-- roomData wird nur referenziert, niemals verändert. Ein zweiter Aufruf
-- übernimmt keinerlei Zustände des vorherigen Raums.
function State.init(roomData)
    State.room = roomData
    State.switchStates = {}
    for _, sw in ipairs(roomData.switches) do
        State.switchStates[sw.id] = sw.state
    end
    State.player = {
        ring = roomData.start.ring,
        angle = roomData.start.angle,
    }
    State.deriveElements()
end

-- Leitet alle Elementzustände vollständig neu aus Schalterzuständen und
-- free-Flags ab. Wird immer komplett neu berechnet, nie inkrementell verändert.
function State.deriveElements()
    State.elementStates = {}

    -- free = true: immer aktiv, von keinem Schalter gesteuert.
    for _, b in ipairs(State.room.bridges) do
        if b.free == true then
            State.elementStates[b.id] = true
        end
    end
    if State.room.gate and State.room.gate.free == true then
        State.elementStates[State.room.gate.id] = true
    end

    -- Blenden sowie gesteuerte Brücken/Gate aus dem steuernden Schalter ableiten.
    -- Zustand A: onA aktiv, onB inaktiv. Zustand B: umgekehrt. Schalter toggeln nicht.
    for _, sw in ipairs(State.room.switches) do
        local state = State.switchStates[sw.id]
        if state == "A" then
            State.elementStates[sw.onA] = true
            State.elementStates[sw.onB] = false
        else
            State.elementStates[sw.onA] = false
            State.elementStates[sw.onB] = true
        end
    end
end

-- Setzt einen Schalterzustand. Erlaubt sind ausschließlich "A" und "B".
-- Rückgabe: changed (bool), elements (Liste tatsächlich geänderter Elemente).
--   Nicht-Toggle: Schalter steht bereits auf newState -> false, {} (keine
--   Elementableitung, kein Undo, keine Meldung).
--   Bei echter Änderung: Elementänderungen deterministisch in der Reihenfolge
--   der Leveldefinition (Blenden, Brücken, Gate).
-- Löst KEIN Undo aus; die Undo-Entscheidung trifft das Sweep-System.
function State.setSwitch(id, newState)
    if newState ~= "A" and newState ~= "B" then
        error("State.setSwitch: ungültiger Zustand '" .. tostring(newState) .. "'")
    end
    if State.switchStates[id] == nil then
        error("State.setSwitch: unbekannter Schalter '" .. tostring(id) .. "'")
    end
    if State.switchStates[id] == newState then
        return false, {}
    end

    -- Bisherigen Elementzustand sichern, um Änderungen zu vergleichen.
    local oldElementStates = {}
    for elId, val in pairs(State.elementStates) do
        oldElementStates[elId] = val
    end

    State.switchStates[id] = newState
    State.deriveElements()

    local changed = {}
    local function addChanged(elId)
        local from = oldElementStates[elId]
        local to = State.elementStates[elId]
        if from ~= to then
            changed[#changed + 1] = { id = elId, from = from, to = to }
        end
    end
    for _, s in ipairs(State.room.shutters) do addChanged(s.id) end
    for _, b in ipairs(State.room.bridges) do addChanged(b.id) end
    if State.room.gate then addChanged(State.room.gate.id) end

    return true, changed
end

-- Erzeugt einen echten unabhängigen Snapshot (Kopien, keine Referenzen auf
-- veränderliche State-Tabellen). Bleibt nach späteren State-Änderungen konstant.
function State.snapshot()
    local snap = {}
    snap.switchStates = {}
    for id, state in pairs(State.switchStates) do
        snap.switchStates[id] = state
    end
    snap.elementStates = {}
    for id, val in pairs(State.elementStates) do
        snap.elementStates[id] = val
    end
    snap.player = {
        ring = State.player.ring,
        angle = State.player.angle,
    }
    return snap
end

-- Stellt einen Snapshot wieder her: Schalterzustände und Spieler werden
-- kopiert; die Elementzustände werden danach deterministisch neu abgeleitet
-- statt als zweite unabhängige Wahrheit restauriert. Das verhindert, dass
-- switchStates und elementStates auseinanderlaufen.
function State.restore(snapshot)
    State.switchStates = {}
    for id, state in pairs(snapshot.switchStates) do
        State.switchStates[id] = state
    end
    State.player = {
        ring = snapshot.player.ring,
        angle = snapshot.player.angle,
    }
    State.deriveElements()
end

return State