-- State: veränderlicher Laufzeitzustand des aktuellen Raums.
-- Hält die roomData-Referenz, Schalter- und Elementzustände sowie die
-- Spielerposition. Keine Projekt-Imports; die Raumdaten werden von außen
-- übergeben (State.init). Kein Undo, keine G7-Verzögerung, keine Animation:
-- elementStates beschreibt nur den logischen Sollzustand.

State = {}

local config <const> = Config
local geo <const> = Geometry

-- Referenz auf die unveränderte Leveldefinition des aktuellen Raums.
-- State verändert diese Tabellen niemals.
State.room = nil

-- Schalterzustände: State.switchStates[id] = "A" | "B"
State.switchStates = {}

-- Elementzustände: State.elementStates[id] = true (aktiv) | false (inaktiv)
-- Blende: true = offen, false = geschlossen.
-- Brücke/Gate: true = ausgefahren, false = eingefahren.
State.elementStates = {}

-- Einmal-Mechanik: verbrauchte (gesperrte/zerstörte) Elemente.
-- State.consumedSwitches[id] = true: Einmal-Schalter wurde bereits umgelegt
-- und ist damit dauerhaft gesperrt (flippt nie wieder).
-- State.consumedBridges[id] = true: Einmal-Brücke wurde benutzt und ist
-- dauerhaft zusammengebrochen (kann nie wieder genutzt werden, auch wenn der
-- Schalter sie aktivieren würde). Beide Mengen gehören in den Snapshot
-- (Undo stellt damit den „unbenutzt“-Zustand wieder her).
State.consumedSwitches = {}
State.consumedBridges = {}

-- Druckplatten: aktueller Press-Zustand (rein positionsabhängig, momentan).
-- State.platePressed[id] = true, solange Player ODER Baby auf der Platte
-- steht. Wird in deriveElements aus den aktuellen Positionen neu berechnet.
State.platePressed = {}

-- Spielerposition. Nur ring und angle; keine Bewegungshistorie.
State.player = {
    ring = "outer",
    angle = 0,
}

-- Baby-Runtime-Zustand (generisch): nil, wenn der Raum kein Baby hat.
-- { ring, angle, settled, lastPushDirection }.
-- settled = immer false (kein Ablageziel mehr; Feld bleibt für Snapshot-/
-- Undo-/Render-Kompatibilität im Datenmodell).
State.baby = nil

-- Initialisiert einen komplett frischen Raumzustand.
-- roomData wird nur referenziert, niemals verändert. Ein zweiter Aufruf
-- übernimmt keinerlei Zustände des vorherigen Raums.
-- carryBaby (optional): true, wenn ein in einem früheren Raum eingeführtes
-- Baby als Begleiter in diesen Raum mitgenommen wird (kein Ablageziel).
function State.init(roomData, carryBaby)
    State.room = roomData
    State.switchStates = {}
    for _, sw in ipairs(roomData.switches) do
        State.switchStates[sw.id] = sw.state
    end
    State.consumedSwitches = {}
    State.consumedBridges = {}
    State.platePressed = {}
    State.player = {
        ring = roomData.start.ring,
        angle = roomData.start.angle,
    }
    if roomData.baby then
        State.baby = {
            ring = roomData.baby.start.ring,
            angle = roomData.baby.start.angle,
            settled = false,
            lastPushDirection = 1, -- CW-Standard (wie Player-Facing)
        }
    elseif carryBaby then
        -- Begleiter-Start in Folge-Räumen (gemeinsamer Raumausgang): das Baby
        -- startet direkt hinter der offiziellen Spielerstartposition (gleicher
        -- Ring, kleiner Winkelversatz rückwärts) — keine Überlappung, kein
        -- Segment, keine Kollision. Rein datengetrieben, keine Raum-Sonderlogik.
        State.baby = {
            ring = roomData.start.ring,
            angle = geo.norm(roomData.start.angle - config.babyCompanionOffsetDeg),
            settled = false,
            lastPushDirection = 1,
        }
    else
        State.baby = nil
    end
    State.deriveElements()
end

-- Normiert eine Schalter-Steuerreferenz auf eine Liste von Element-IDs.
-- Einzelne ID (String) -> { id }; Liste -> unverändert. Damit kann ein
-- Segment-Schalter MEHRERE Shutters in derselben Schalterrichtung steuern
-- (Raum 3 „Fernwirkung“: S1 onA = { "D1", "D2" } -> A öffnet beide).
function State.controlIds(ref)
    if ref == nil then
        return {}
    end
    if type(ref) == "table" then
        return ref
    end
    return { ref }
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
    -- onA/onB dürfen einzelne IDs ODER Listen sein (Segment-Schalter: mehrere
    -- Shutters in derselben Richtung).
    for _, sw in ipairs(State.room.switches) do
        local state = State.switchStates[sw.id]
        local onA = State.controlIds(sw.onA)
        local onB = State.controlIds(sw.onB)
        if state == "A" then
            for _, id in ipairs(onA) do State.elementStates[id] = true end
            for _, id in ipairs(onB) do State.elementStates[id] = false end
        else
            for _, id in ipairs(onA) do State.elementStates[id] = false end
            for _, id in ipairs(onB) do State.elementStates[id] = true end
        end
    end

    -- fixedClosed = true: dauerhaft geschlossene Blende (feste Wand), von keinem
    -- Schalter gesteuert — elementStates bleibt IMMER false. Bewusst NACH der
    -- Schalterableitung, damit eine feste Blende nie von einem Schalter geöffnet
    -- werden kann (der Validator verbietet Steuerreferenzen auf feste Blenden).
    for _, sh in ipairs(State.room.shutters) do
        if sh.fixedClosed == true then
            State.elementStates[sh.id] = false
        end
    end

    -- Verbrauchte Einmal-Brücken: dauerhaft zusammengebrochen — elementStates
    -- bleibt IMMER false, unabhängig vom steuernden Schalter (kann nie wieder
    -- genutzt werden). Bewusst NACH der Schalterableitung.
    for _, b in ipairs(State.room.bridges) do
        if State.consumedBridges[b.id] then
            State.elementStates[b.id] = false
        end
    end

    -- Druckplatten (momentan): der Press-Zustand ist rein positionsabhängig.
    -- Eine Platte ist gedrückt, solange Player ODER Baby auf demselben Ring
    -- STRENG innerhalb des Druckbereichs steht (|delta| < platePressRange;
    -- die Kante selbst zählt nicht, damit das Überqueren der Austrittskante
    -- die Platte im selben Sweep sofort loslässt). Das gesteuerte Element
    -- (eine Blende) ist dann aktiv, sonst inaktiv. Kein Rasten: sobald
    -- niemand mehr draufsteht, löst die Platte aus. Kein Undo-Eintrag
    -- (Position ist Teil des Snapshots). Die Platten-Ableitung läuft NACH der
    -- Schalterableitung, damit eine von einer Platte gesteuerte Blende nie
    -- von einem Schalter doppelt gesteuert wird (Validator: genau ein Herr).
    State.platePressed = {}
    for _, p in ipairs(State.room.plates or {}) do
        local pressed = false
        if State.player then
            pressed = State.player.ring == p.ring
                and math.abs(geo.delta(State.player.angle, p.angle)) < config.platePressRange
        end
        if not pressed and State.baby then
            pressed = State.baby.ring == p.ring
                and math.abs(geo.delta(State.baby.angle, p.angle)) < config.platePressRange
        end
        State.platePressed[p.id] = pressed
        State.elementStates[p.on] = pressed
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
    -- Einmal-Schalter (oneShot): bereits einmal umgelegt -> dauerhaft gesperrt.
    -- Auch ein „zurückflippen" ist damit unmöglich (keine erneute Benutzung).
    if State.consumedSwitches[id] then
        return false, {}
    end
    if State.switchStates[id] == newState then
        return false, {}
    end

    -- Einmal-Schalter: die ECHTE erste Änderung verbraucht ihn (Sperre setzen,
    -- bevor der neue Zustand gilt — die Sperre gehört zum Snapshot für Undo).
    for _, s in ipairs(State.room.switches) do
        if s.id == id and s.oneShot == true then
            State.consumedSwitches[id] = true
            break
        end
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

-- Verbraucht eine Einmal-Brücke dauerhaft (kollabiert nach Benutzung). Reine
-- Zustandsänderung: consumedBridges setzen + Elementzustand neu ableiten — die
-- Brücke wird dadurch dauerhaft inaktiv, auch wenn der Schalter sie aktivieren
-- würde. Kein Undo: Brücken-Transitaktionen sind bewusst nicht undo-bar
-- (dokumentiert), damit bleibt auch der Verbrauch konsistent nicht-undo-bar.
function State.consumeBridge(id)
    if State.consumedBridges[id] then
        return
    end
    State.consumedBridges[id] = true
    State.deriveElements()
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
    snap.consumedSwitches = {}
    for id in pairs(State.consumedSwitches) do snap.consumedSwitches[id] = true end
    snap.consumedBridges = {}
    for id in pairs(State.consumedBridges) do snap.consumedBridges[id] = true end
    snap.player = {
        ring = State.player.ring,
        angle = State.player.angle,
    }
    if State.baby then
        snap.baby = {
            ring = State.baby.ring,
            angle = State.baby.angle,
            settled = State.baby.settled,
            lastPushDirection = State.baby.lastPushDirection,
        }
    end
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
    State.consumedSwitches = {}
    for id in pairs(snapshot.consumedSwitches or {}) do State.consumedSwitches[id] = true end
    State.consumedBridges = {}
    for id in pairs(snapshot.consumedBridges or {}) do State.consumedBridges[id] = true end
    State.player = {
        ring = snapshot.player.ring,
        angle = snapshot.player.angle,
    }
    if snapshot.baby then
        State.baby = {
            ring = snapshot.baby.ring,
            angle = snapshot.baby.angle,
            settled = snapshot.baby.settled,
            lastPushDirection = snapshot.baby.lastPushDirection,
        }
    else
        State.baby = nil
    end
    State.deriveElements()
end

-- --- Baby (generisch) -----------------------------------------------------

-- Setzt die Baby-Position (gleicher Ring, normalisierter Winkel). Ein bereits
-- eingerastetes Baby wird nicht bewegt. Kein Elementeffekt; keine Neuableitung.
function State.setBaby(ring, angle)
    if not State.baby then
        return
    end
    if State.baby.settled then
        return
    end
    State.baby.ring = ring
    State.baby.angle = angle
end

-- Merkt die Richtung des letzten Schubs (+1 CW, -1 CCW). Wird für den
-- Austrittswinkel des Babys nach einem Brückentransit genutzt (bisherige
-- Schieberichtung). Rein deklarativ, kein Elementeffekt.
function State.setBabyPushDirection(direction)
    if not State.baby then
        return
    end
    State.baby.lastPushDirection = direction
end

return State