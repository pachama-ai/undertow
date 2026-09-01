-- Room: koordiniert die Ringbewegung des Spielers als chronologischer
-- Movement-Sweep. Verarbeitet Schalterüberquerungen, Blendenkollision und G7
-- während einer Frame-Bewegung sowie die logische A-Interaktion mit Brücken
-- und Gate (Room.tryUseConnection). Keine Imports; die Module werden zentral
-- in main.lua geladen. Keine Raumprogression in diesem Schritt.

Room = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State
local undo <const> = Undo

local EPSILON <const> = 0.000001
local MAX_SWEEP_EVENTS <const> = 256

-- Schalterregeln (Austrittskante, Zielzustand, vollständige Durchquerung)
-- liegen in Switch und werden zur Laufzeit über die globale Tabelle aufgelöst
-- (wie Bridge/Gate). switch.lua muss daher von main.lua (Composition Root)
-- importiert werden.

-- Physischer Blendenzustand: Room.shutters[id] = { collisionActive, pendingClose }
-- Gehört bewusst zu Room, nicht zu State.
Room.shutters = {}

-- Transienter Traversal-Zustand der Schalterdurchquerung (Release-Fix 1):
-- Room.switchTraversal[id] = 1 (CW) | -1 (CCW) | nil (nicht armiert).
-- Gehört BEWUSST nicht zu State/Save/Levels: Er ist nur temporärer Bewegungs-
-- /Kontaktzustand zwischen zwei movePlayer-Frames und wird weder gespeichert
-- noch undo-et (der Snapshot enthält ihn nicht). Armierung beim Überschreiten
-- der Eintrittskante, Auslösung beim Überschreiten der Austrittskante in
-- derselben Richtung, Abbruch bei Rückkehr über die Eintrittskante.
Room.switchTraversal = {}

-- Setzt den Traversal-Zustand vollständig zurück (Room.init/Raumstart/
-- Raumwechsel/Restart sowie Undo- und Ringwechselpfade in main.lua). Keine
-- alte halbe Schalterdurchquerung bleibt erhalten.
function Room.resetSwitchTraversal()
    Room.switchTraversal = {}
end

-- Initialisiert ausschließlich den physischen Blendenzustand der Blenden.
-- Setzt keine Schalterzustände und ruft State.init nicht selbst auf. Der
-- Schalter-Traversal-Zustand wird vollständig zurückgesetzt (kein Zustands-
-- Leak über Raumstart/Restart/Raumwechsel).
function Room.init()
    Room.shutters = {}
    for _, sh in ipairs(state.room.shutters) do
        Room.shutters[sh.id] = { collisionActive = false, pendingClose = false }
    end
    Room.resetSwitchTraversal()
    Room.syncPhysicalShutters()
end

-- Distanz von fromAngle zu targetAngle entlang der Bewegungsrichtung.
-- direction: +1 = im Uhrzeigersinn, -1 = gegen den Uhrzeigersinn.
-- Ergebnis in [0, 360).
local function distanceAlongDirection(fromAngle, targetAngle, direction)
    if direction > 0 then
        return Geometry.norm(targetAngle - fromAngle)
    end
    return Geometry.norm(fromAngle - targetAngle)
end

-- Prüft, ob ein Winkel strikt (ohne die beiden Kanten) innerhalb eines Bogens
-- liegt. Eine Figur exakt auf einer Kante gilt als außerhalb.
local function isStrictlyInsideArc(angle, centerAngle, width)
    local a = Geometry.norm(angle)
    local startAngle = Geometry.norm(centerAngle - width / 2)
    local d = Geometry.norm(a - startAngle)
    if d <= EPSILON then
        return false
    end
    if math.abs(d - width) <= EPSILON then
        return false
    end
    return d < width
end

-- Rekonstruiert den physischen Blendenzustand vollständig aus dem logischen
-- Sollzustand (State.elementStates) und der Spielerposition (G7).
-- Nach Undo.undo() stellt diese Funktion den korrekten physischen Zustand
-- wieder her.
function Room.syncPhysicalShutters()
    if not Room.shutters then
        return
    end
    for _, sh in ipairs(state.room.shutters) do
        local phys = Room.shutters[sh.id]
        local logical = state.elementStates[sh.id]
        if logical == true then
            -- logisch offen: nie kollisionsaktiv, kein Schließwunsch
            phys.collisionActive = false
            phys.pendingClose = false
        else
            local inside = false
            if sh.ring == state.player.ring then
                inside = isStrictlyInsideArc(state.player.angle, sh.angle, config.shutterArcWidth)
            end
            -- G7 auch für das Baby: eine Blende schließt nicht, solange das
            -- Baby in ihrem Bogen steht (z. B. wenn eine Druckplatte losgelassen
            -- wird, während das Baby im Bogen parkt).
            if not inside and state.baby and sh.ring == state.baby.ring then
                inside = isStrictlyInsideArc(state.baby.angle, sh.angle, config.shutterArcWidth)
            end
            if inside then
                -- G7: Blende schließt nicht auf der Figur
                phys.collisionActive = false
                phys.pendingClose = true
            else
                phys.collisionActive = true
                phys.pendingClose = false
            end
        end
    end
end

-- Findet das nächste relevante Ereignis in Bewegungsrichtung auf dem aktuellen
-- Ring. Rückgabe: nil (kein Ereignis) oder
-- { kind = "switch"|"shutter", sub = "entry"|"exit"|nil, id = <id>, distance = <grad>, angle = <absoluter Winkel> }.
-- Schalter (Release-Fix 1): Eintritts- UND Austrittskante sind Ereignisse —
-- die Eintrittskante armiert die Traversierung, die Austrittskante löst sie
-- aus. Damit funktionieren vollständige Durchquerungen über beliebig viele
-- Frames (kleine D-Pad-Deltas) wie auch in einem einzigen großen Delta.
-- Startpunkt ausgeschlossen (Distanz 0 wird auf 360 gesetzt).
-- Blendenkollision: Distanz 0 ist erlaubt (direkt an der Eintrittskante).
local function findNextEvent(fromAngle, direction, remaining)
    local best = nil
    local bestDist = math.huge
    local ring = state.player.ring

    -- Schalter-Kanten (Eintritt + Austritt, nur aktueller Ring)
    for _, sw in ipairs(state.room.switches) do
        if sw.ring == ring then
            local entryAngle = Switch.getEntryAngle(sw, direction)
            local exitAngle = Switch.getExitAngle(sw, direction)
            local entryDist = distanceAlongDirection(fromAngle, entryAngle, direction)
            if entryDist <= EPSILON then
                entryDist = 360 -- Startpunkt ausgeschlossen
            end
            local exitDist = distanceAlongDirection(fromAngle, exitAngle, direction)
            if exitDist <= EPSILON then
                exitDist = 360 -- Startpunkt ausgeschlossen
            end
            if entryDist < bestDist then
                best = { kind = "switch", sub = "entry", id = sw.id, distance = entryDist, angle = entryAngle }
                bestDist = entryDist
            end
            if exitDist < bestDist then
                best = { kind = "switch", sub = "exit", id = sw.id, distance = exitDist, angle = exitAngle }
                bestDist = exitDist
            end
        end
    end

    -- Druckplatten-Kanten (Eintritt + Austritt des Druckbereichs, nur
    -- aktueller Ring): Die Platte ist gedrückt, solange die Figur im
    -- Druckbereich um plate.angle steht (|delta| <= platePressRange). Beim
    -- Überqueren einer Kante ändert sich der Press-Zustand mitten im Sweep,
    -- deshalb sind die Kanten chronologische Sweep-Ereignisse (analog zu
    -- Schalterkanten, aber ohne Rasten — rein positionsabhängig).
    for _, p in ipairs(state.room.plates or {}) do
        if p.ring == ring then
            local entryAngle, exitAngle
            if direction > 0 then
                entryAngle = Geometry.norm(p.angle - config.platePressRange)
                exitAngle = Geometry.norm(p.angle + config.platePressRange)
            else
                entryAngle = Geometry.norm(p.angle + config.platePressRange)
                exitAngle = Geometry.norm(p.angle - config.platePressRange)
            end
            local entryDist = distanceAlongDirection(fromAngle, entryAngle, direction)
            if entryDist <= EPSILON then
                entryDist = 360 -- Startpunkt ausgeschlossen
            end
            local exitDist = distanceAlongDirection(fromAngle, exitAngle, direction)
            if exitDist <= EPSILON then
                exitDist = 360 -- Startpunkt ausgeschlossen
            end
            if entryDist < bestDist then
                best = { kind = "plate", sub = "entry", id = p.id, distance = entryDist, angle = entryAngle }
                bestDist = entryDist
            end
            if exitDist < bestDist then
                best = { kind = "plate", sub = "exit", id = p.id, distance = exitDist, angle = exitAngle }
                bestDist = exitDist
            end
        end
    end

    -- kollisionsaktive Blenden-Eintrittskanten (nur aktueller Ring)
    for _, sh in ipairs(state.room.shutters) do
        if sh.ring == ring then
            local phys = Room.shutters[sh.id]
            if phys and phys.collisionActive then
                local entryAngle
                if direction > 0 then
                    entryAngle = Geometry.norm(sh.angle - config.shutterArcWidth / 2)
                else
                    entryAngle = Geometry.norm(sh.angle + config.shutterArcWidth / 2)
                end
                local dist = distanceAlongDirection(fromAngle, entryAngle, direction)
                if dist < bestDist then
                    best = { kind = "shutter", id = sh.id, distance = dist, angle = entryAngle }
                    bestDist = dist
                end
            end
        end
    end

    return best
end

-- Bewegt den Spieler chronologisch um das gewünschte signed Delta.
-- Ein Aufruf entspricht genau einer Frame-Bewegung.
-- Rückgabe: actualDelta (signed), result = { blocked, switchChanges, undoStored }.
function Room.movePlayer(wantedDelta)
    -- elementChanges (Phase 9.1): Liste der {id, from, to}-Elementänderungen,
    -- die durch Schalterauslösung in diesem Frame entstanden sind. Reine
    -- Event-Exposition für UI/Audio; keine Mechanikänderung, kein zweiter
    -- Wahrheitskanal (State bleibt die Quelle). switchOneShot: true, wenn in
    -- diesem Frame ein EINMAL-Schalter ausgelöst wurde (eigener Sound).
    local result = { blocked = false, switchChanges = 0, undoStored = false, elementChanges = {}, switchOneShot = false }
    if wantedDelta == 0 then
        return 0, result
    end

    -- Physischer Blendenzustand vor der Bewegung (Pass 2): Grundlage für die
    -- Audio-Transitions-Exposition (welche Blende hat sich in diesem Frame
    -- geöffnet/geschlossen). Reine Event-Exposition, keine Mechanikänderung.
    local shutterBefore = {}
    for id, phys in pairs(Room.shutters) do
        shutterBefore[id] = phys.collisionActive
    end

    -- Snapshot am Frame-Anfang, VOR jeder Bewegung.
    local frameStartSnapshot = state.snapshot()
    -- Ausgangswinkel des Spielers für den Baby-Push (der Sweep verändert
    -- state.player.angle schrittweise).
    local playerStartAngle = state.player.angle
    local undoStored = false
    local direction = wantedDelta > 0 and 1 or -1
    local remaining = math.abs(wantedDelta)
    local actual = 0
    local blocked = false
    local switchChanges = 0
    local iterations = 0

    while remaining > EPSILON and not blocked do
        iterations = iterations + 1
        if iterations > MAX_SWEEP_EVENTS then
            error("Room.movePlayer: Maximalanzahl Sweep-Ereignisse überschritten")
        end

        local fromAngle = state.player.angle
        local event = findNextEvent(fromAngle, direction, remaining)

        if event == nil or event.distance > remaining + EPSILON then
            -- kein Ereignis innerhalb der Reststrecke: ganze Reststrecke fahren
            local step = direction * remaining
            state.player.angle = Geometry.norm(state.player.angle + step)
            actual = actual + remaining
            remaining = 0
        else
            -- bis zum Ereignis fahren
            local dist = event.distance
            local step = direction * dist
            state.player.angle = Geometry.norm(state.player.angle + step)
            actual = actual + dist
            remaining = remaining - dist

            if event.kind == "shutter" then
                blocked = true
            elseif event.kind == "plate" then
                -- Druckplatte (momentan): beim Überqueren der Druckbereichs-
                -- Kante ändert sich der Press-Zustand rein positionsabhängig
                -- (State.deriveElements liest die aktuelle Position). Kein
                -- Undo, kein Sound, kein Schalterzustand — die Position ist
                -- Teil des Frame-Snapshots.
                State.deriveElements()
                Room.syncPhysicalShutters()
            else
                -- Schalter-Ereignis (Release-Fix 1): Eintritt armiert die
                -- Traversierung, Austritt löst sie aus (oder bricht sie ab).
                local sw = nil
                for _, s in ipairs(state.room.switches) do
                    if s.id == event.id then
                        sw = s
                        break
                    end
                end
                if sw then
                    if event.sub == "entry" then
                        -- Eintrittskante in Fahrtrichtung: Traversierung für
                        -- diese Richtung armieren. KEIN Statewechsel, kein
                        -- Undo, kein Sound, kein Widen (Traversal-State ist
                        -- keine Gameplayentscheidung).
                        Room.switchTraversal[sw.id] = direction
                    else
                        -- Austrittskante: nur bei armierter Durchquerung in
                        -- DIESER Richtung auslösen (vollständige Überquerung).
                        if Room.switchTraversal[sw.id] == direction then
                            -- EINMAL-Schalter mit anyDirection (Level 8, O):
                            -- JEDE vollständige Überquerung (CW ODER CCW)
                            -- führt zum Verbrauchszustand — der Spieler muss
                            -- keine Richtungs-Konvention erraten. Nur für
                            -- Schalter mit der anyDirection-Eigenschaft; alle
                            -- übrigen behalten ihre Richtungslogik.
                            local targetState = sw.anyDirection and "B" or Switch.getTargetState(direction)
                            local changed, changedElements = state.setSwitch(sw.id, targetState)
                            if changed then
                                switchChanges = switchChanges + 1
                                -- Einmalschalter (eigener Snap, „verriegelt"):
                                -- im Ergebnis kennzeichnen, damit main.lua den
                                -- passenden Sound wählen kann.
                                if sw.oneShot == true then
                                    result.switchOneShot = true
                                end
                                -- Reine Event-Exposition: Elementänderungen im
                                -- Return sammeln (deterministisch in Levelreihenfolge).
                                for _, ce in ipairs(changedElements) do
                                    result.elementChanges[#result.elementChanges + 1] = ce
                                end
                                if not undoStored then
                                    undo.push(frameStartSnapshot)
                                    undoStored = true
                                end
                            end
                        end
                        -- Traversierung gilt als abgeschlossen/reset — egal ob
                        -- ausgelöst (Austritt in Fahrtrichtung), No-op (Ziel
                        -- bereits erreicht) oder abgebrochen (Rückkehr über
                        -- die Eintrittsseite in Gegenrichtung).
                        Room.switchTraversal[sw.id] = nil
                    end
                end
                -- Weltzustand neu ableiten und physischen Zustand rekonstruieren,
                -- damit der nächste Ereignisschritt mit dem neuen Zustand arbeitet.
                Room.syncPhysicalShutters()
            end
        end
    end

    -- Physischen Blendenzustand nach der Bewegung rekonstruieren (z. B. wenn
    -- der Spieler eine pendingClose-Blende in der finalen Bewegungsphase
    -- verlassen hat). Ist idempotent, wenn bereits im Loop synchronisiert wurde.
    Room.syncPhysicalShutters()

    -- Blenden-Transitions (Pass 2, reine Event-Exposition für Audio): nach der
    -- Bewegung, deterministisch in Levelreihenfolge. opened = (war zu, jetzt
    -- offen); geschlossen = (war offen, jetzt zu). Kein Mechanik-Effekt.
    local shutterTransitions = {}
    for _, sh in ipairs(state.room.shutters) do
        local phys = Room.shutters[sh.id]
        local before = shutterBefore[sh.id]
        if before ~= phys.collisionActive then
            shutterTransitions[#shutterTransitions + 1] = {
                id = sh.id,
                opened = (phys.collisionActive == false),
            }
        end
    end

    result.blocked = blocked
    result.switchChanges = switchChanges
    result.shutterTransitions = shutterTransitions

    -- Baby-Push (generisch): nach dem Sweep. Bewegt sich der Spieler auf
    -- demselben Ring auf das Baby zu und erreicht dessen Kontaktabstand, wird
    -- das Baby um den restlichen Bewegungsanteil in Fahrtrichtung geschoben
    -- (kein Ziehen, kein Durchspringen, Wraparound). Kein Ablageziel mehr —
    -- das Baby ist Begleiter. Ein echter Schub zählt als zustandsändernde
    -- Spielerhandlung: Es entsteht genau ein Undo-Snapshot (Frame-Anfang),
    -- falls nicht bereits ein Schalterereignis in diesem Frame einen angelegt hat.
    local babyMoved, babyBlocked = Room.applyBabyPush(playerStartAngle, direction, actual)
    if babyBlocked then
        result.blocked = true
    end
    if babyMoved and not undoStored then
        undo.push(frameStartSnapshot)
        undoStored = true
    end

    -- Druckplatten: nach der Bewegung UND dem Baby-Push neu ableiten (rein
    -- positionsabhängig). Der Baby-Push ist kein Sweep-Ereignis — das Baby
    -- kann dabei in den Druckbereich einer Platte geschoben werden (oder
    -- heraus), was die Plattenzustände und damit die physischen Blenden
    -- (G7) verändert. Idempotent.
    State.deriveElements()
    Room.syncPhysicalShutters()

    result.undoStored = undoStored
    result.babyMoved = babyMoved
    return actual * direction, result
end

-- Nächste kollisionsaktive Blenden-Eintrittskante in Pushrichtung VOR dem
-- Baby auf demselben Ring (dieselbe Kollisionssemantik wie der Spieler-Sweep).
-- Rückgabe: (stopAngle, entryAngle, inside)
--   stopAngle = Eintrittskante minus Baby-Kontaktabstand — dort stoppt das Baby
--               exakt, damit Baby-Körper + Kontaktradius die geschlossene
--               Shutterfläche nie schneiden (keine visuelle Korrektur, der
--               Gameplay-State selbst ist die Wahrheit).
--   entryAngle = die Eintrittskante (für die Distanzvergleiche).
--   inside     = true, wenn das Baby bereits im Segment steckt (defensiv:
--               dann wird es auf den Stoppwinkel zurückgezogen).
local function nextBabyShutterStop(babyAngle, direction)
    local ring = state.player.ring
    local margin = Baby.shutterMarginDeg(ring)
    local bestEntry = nil
    local bestDist = math.huge
    local insideEntry = nil
    local inside = false
    for _, sh in ipairs(state.room.shutters) do
        if sh.ring == ring then
            local phys = Room.shutters[sh.id]
            if phys and phys.collisionActive then
                local entryAngle
                if direction > 0 then
                    entryAngle = Geometry.norm(sh.angle - config.shutterArcWidth / 2)
                else
                    entryAngle = Geometry.norm(sh.angle + config.shutterArcWidth / 2)
                end
                if isStrictlyInsideArc(babyAngle, sh.angle, config.shutterArcWidth) then
                    inside = true
                    if insideEntry == nil then
                        insideEntry = entryAngle
                    end
                else
                    local dist = distanceAlongDirection(babyAngle, entryAngle, direction)
                    if dist < bestDist then
                        bestDist = dist
                        bestEntry = entryAngle
                    end
                end
            end
        end
    end
    local entry = inside and insideEntry or bestEntry
    if not entry then
        return nil, nil, false
    end
    return Geometry.norm(entry - direction * margin), entry, inside
end

-- Bewegt das Baby nach einem Spieler-Sweep (aufgerufen aus movePlayer).
-- Reine Orchestrierung: die Push-Mathematik liegt in Baby.computePush; die
-- Mutationen laufen über State (State.setBaby), damit Undo und Restart
-- korrekt funktionieren.
--
-- BABY-SHUTTER-KOLLISION (Regression-Fix): Das Baby wird niemals in ein
-- geschlossenes Segment hineingeschoben. Nach der Push-Mathematik wird der
-- Weg in Fahrtrichtung auf die nächste kollisionsaktive Blenden-Eintrittskante
-- begrenzt; das Baby stoppt exakt davor (Kontaktabstand zur Shutterfläche),
-- der Player wird entsprechend zurückgenommen (Kontaktabstand hinter dem
-- Baby). Gameplay-State ist die Wahrheit — KEINE visuelle Korrektur im
-- Renderer.
--
-- Rückgabe: (moved, babyBlocked)
--   moved=true       wenn das Baby bewegt wurde (dann ist ein Undo-Snapshot
--                    fällig); false, wenn es (bereits) am Hindernis steht.
--   babyBlocked=true wenn der Schub durch eine geschlossene Blende gestoppt
--                    wurde (für den Impact-Sound; Main meldet das echte
--                    Gameplayresultat).
function Room.applyBabyPush(playerStartAngle, direction, actualDist)
    local baby = state.baby
    if not baby then
        return false, false
    end
    -- Nur auf demselben Ring wird geschoben.
    if baby.ring ~= state.player.ring then
        return false, false
    end
    if actualDist <= 0 then
        return false, false
    end
    local oldAngle = baby.angle
    local newAngle, pushAmount, pushDir = Baby.computePush(baby.angle, playerStartAngle, direction, actualDist)
    if not newAngle then
        return false, false
    end

    -- Kollisionsbegrenzung: nächste geschlossene Blende in Pushrichtung.
    -- Stoppmarge = sichtbare Baby-Silhouette (Baby.shutterMarginDeg); der
    -- Player-Pullback bleibt im Figurenkontaktabstand (Baby.contactDeg).
    local stopAngle, entryAngle, inside = nextBabyShutterStop(baby.angle, direction)
    local moved = newAngle
    local babyBlocked = false
    if stopAngle then
        local margin = Baby.shutterMarginDeg(state.player.ring)
        local dNew = distanceAlongDirection(baby.angle, newAngle, direction)
        local dEntry = distanceAlongDirection(baby.angle, entryAngle, direction)
        -- Baby stoppt, wenn: es bereits im Segment steckt, bereits im Kontakt-
        -- bereich der Kante ist ODER der Push die Kante (minus Kontakt) über-
        -- schreiten würde. In allen Fällen: exakt am Stoppwinkel (kein Ein-
        -- dringen, kein Tunneling bei großen Deltas).
        if inside or dEntry < margin + EPSILON or dNew > dEntry - margin then
            moved = stopAngle
            babyBlocked = true
        end
    end

    -- Player entsprechend stoppen: er darf das Baby nicht durch das Hindernis
    -- drücken und bleibt im Kontaktabstand hinter dem Baby.
    if babyBlocked then
        state.player.angle = Geometry.norm(stopAngle - direction * Baby.contactDeg())
    end

    -- Baby hat sich nicht bewegt (steht bereits am Hindernis): kein Undo,
    -- kein erneuter Push (gehaltenes Drücken erzeugt keinen neuen Schub).
    if math.abs(Geometry.delta(oldAngle, moved)) <= EPSILON then
        return false, babyBlocked
    end

    state.setBabyPushDirection(pushDir)
    state.setBaby(baby.ring, moved)
    -- Kein Ablageziel mehr (Baby-Regel): das Baby wird nur geschoben, nie
    -- abgelegt/eingerastet. Der gemeinsame Raumausgang (Gate) prüft die
    -- Baby-Anwesenheit separat in Gate.isUsable.
    return true, babyBlocked
end

-- Führt die logische A-Aktion an der aktuellen Spielerposition aus.
-- Reine Gameplay-Logik; die tatsächliche Abfrage
--   playdate.buttonJustPressed(playdate.kButtonA)
-- wird erst bei der main.lua-Integration verdrahtet.
--
-- Rückgabevertrag (einheitlich):
--   { used = false, kind = nil, id = nil, roomComplete = false }  keine Verbindung
--   { used = true, kind = "bridge", id = <id>, roomComplete = false }
--   { used = true, kind = "gate",   id = <id>, crossing = true }
--   (Gate: Start eines Kernbrücken-Transits zum Mittelpunkt — der Raum-
--   abschluss erfolgt erst NACH dem Transit/Landing, main.lua)
--
-- Kandidatensuche: erst ALLE nutzbaren Verbindungen bestimmen — auf inner
-- sind Brücken UND das Gate Kandidaten, auf outer nur Brücken. Dann:
--   0 Kandidaten -> nichts, 1 Kandidat -> benutzen,
--   >1 Kandidaten -> Ambiguitätsfehler (keine versteckte Priorität).
--
-- Bridge und Gate werden bewusst als globale Tabellen zur Laufzeit aufgelöst
-- (kein Caching am Dateianfang), damit die Lade-Reihenfolge von room.lua
-- gegenüber bridge.lua/gate.lua keine Rolle spielt.
function Room.tryUseConnection()
    local result = { used = false, kind = nil, id = nil, roomComplete = false, crossing = false }
    local playerRing = state.player.ring
    local playerAngle = state.player.angle

    -- Gemeinsamer Brückentransit (Baby korrekt an der aktiven Brücke, Player
    -- direkt dahinter, gleicher Ring): EIN A bewegt beide gemeinsam über die
    -- Brücke. Reine Query über Baby.canTransfer (read-only); es gibt keinen
    -- separaten Baby-Solotransfer mehr (der Player-Solo bleibt möglich, wenn
    -- das Baby nicht am Dock steht).
    for _, b in ipairs(state.room.bridges) do
        if Baby.canTransfer(b, playerRing, playerAngle) then
            -- EINMAL-Brücke (oneShot): die ERSTE Überquerung verbraucht die
            -- Brücke dauerhaft. Vor dem Transit einen Undo-Snapshot sichern,
            -- damit z. B. eine verfrühte (Solo-)Nutzung rückgängig gemacht
            -- werden kann. Nur oneShot-Brücken — normale Brücken und das Gate
            -- erzeugen weiterhin keinen Undo.
            if b.oneShot == true and not state.consumedBridges[b.id] then
                undo.push(state.snapshot())
            end
            local started = Bridge.beginSharedTransit(b, playerRing)
            if started then
                -- Einmal-Brücke: wird erst NACH der Überquerung verbraucht
                -- (kollabiert, wenn der Player drüber hinweg ist — siehe
                -- Bridge.update), nicht schon beim Transitstart.
                result.used = true
                result.kind = "sharedBridge"
                result.id = b.id
                result.roomComplete = false
                result.crossing = true
                return result
            end
        end
    end

    -- Alle nutzbaren Kandidaten in deterministischer Reihenfolge sammeln.
    local candidates = {}
    for _, b in ipairs(state.room.bridges) do
        if Bridge.isUsable(b, playerAngle) then
            candidates[#candidates + 1] = { kind = "bridge", data = b }
        end
    end
    -- Gate generisch: nutzbar auf dem Gate-Ring (gate.ring, Default "inner").
    if state.room.gate and playerRing == (state.room.gate.ring or "inner") then
        if Gate.isUsable(state.room.gate, playerRing, playerAngle) then
            candidates[#candidates + 1] = { kind = "gate", data = state.room.gate }
        end
    end

    if #candidates == 0 then
        return result
    end
    if #candidates > 1 then
        error("Room.tryUseConnection: mehrdeutige Docking-Situation (" .. #candidates .. " nutzbare Verbindungen)")
    end

    local cand = candidates[1]
    if cand.kind == "gate" then
        -- Kernbrücke (Gate): EIN A startet einen GEMEINSAMEN (mit Baby) bzw.
        -- Solo-Transit zum MITTELPUNKT — exakt dieselbe Bridge-Transit-Logik
        -- wie bei einer normalen Ring->Ring-Brücke (nur das Ziel ist der
        -- Kernrand). Der Levelabschluss erfolgt ERST NACH dem Transit/Landing
        -- am Mittelpunkt (main.lua über den Center-Abschluss des Transits),
        -- NICHT beim Betreten der Brücke.
        local shared = state.baby ~= nil
        local started
        if shared then
            started = Bridge.beginSharedTransit(cand.data, playerRing, "center")
        else
            started = Bridge.beginTransit(cand.data, playerRing, "center")
        end
        if not started then
            -- defensiv: einen laufenden Transit niemals überschreiben
            return result
        end
        result.used = true
        result.kind = "gate"
        result.id = cand.data.id
        result.roomComplete = false
        result.crossing = true
        return result
    end

    -- Brücke: Bridge-Transit starten. Kein sofortiger Ringwechsel — der Ring
    -- wechselt erst bei Transitabschluss (Bridge.update in main.lua), danach
    -- Room.syncPhysicalShutters() (G7 auf Zielring). Kein Sweep; Undo nur bei
    -- EINMAL-Brücken (siehe unten).
    local bridgeData = cand.data
    -- EINMAL-Brücke (oneShot): die ERSTE Überquerung verbraucht die Brücke
    -- dauerhaft. Vor dem Transit einen Undo-Snapshot sichern, damit z. B. eine
    -- verfrühte Solo-Nutzung rückgängig gemacht werden kann. Nur oneShot-
    -- Brücken — normale Brücken und das Gate erzeugen weiterhin keinen Undo.
    if bridgeData.oneShot == true and not state.consumedBridges[bridgeData.id] then
        undo.push(state.snapshot())
    end
    local started = Bridge.beginTransit(bridgeData, playerRing)
    if not started then
        -- defensiv: einen laufenden Transit niemals überschreiben
        return result
    end
    -- Einmal-Brücke: wird erst NACH der Überquerung verbraucht (kollabiert,
    -- wenn der Player drüber hinweg ist — siehe Bridge.update), nicht schon
    -- beim Transitstart.
    result.used = true
    result.kind = "bridge"
    result.id = bridgeData.id
    result.roomComplete = false
    result.crossing = true
    return result
end

-- --- Andockhilfe (Phase 7.3) -----------------------------------------------
-- Sanfte, rein positionale Ausrichtung über exakt Config.dockAssistFrames
-- Frames auf eine aktive Brücke (beide Ringe), einen Schalter (nur aktueller
-- Ring) oder die aktive Kernbrücke (Gate, gleiche Fangzone wie Ring-Brücken),
-- sofern keine Bewegungsabsicht vorliegt und der kurze Weg nicht durch eine
-- kollisionsaktive Blende blockiert ist. Kein Undo, kein Schalter-Trigger,
-- kein Sweep. KEINE zweite persistente Spielerposition: State.player.angle
-- bleibt die einzige Wahrheit und wird je Frame neu gesetzt.

-- Temporärer Assistenzzustand (nil = inaktiv).
Room.dockAssist = nil

-- Bricht eine laufende Assistenz ab (Eingabe, Crossing, Undo, Raumstart).
function Room.resetDockAssist()
    Room.dockAssist = nil
end

-- Läuft gerade eine Andockhilfe?
function Room.isDockAssisting()
    return Room.dockAssist ~= nil
end

-- Read-only Kopie des Assistenzzustands (für Tests/Debug).
function Room.getDockAssist()
    local da = Room.dockAssist
    if not da then
        return nil
    end
    return {
        active = da.active,
        kind = da.kind,
        id = da.id,
        startAngle = da.startAngle,
        targetAngle = da.targetAngle,
        signedDelta = da.signedDelta,
        frame = da.frame,
        totalFrames = da.totalFrames,
    }
end

-- Prüft read-only, ob auf dem kurzen signed Weg von fromAngle zu toAngle eine
-- kollisionsaktive Blenden-Eintrittskante des aktuellen Rings liegt. Kein
-- State-, Schalter- oder Undo-Effekt; nutzt dieselbe Kollisionssemantik wie
-- der Sweep (Eintrittskante in Bewegungsrichtung).
local function dockPathBlocked(fromAngle, toAngle)
    local signedDelta = geo.delta(fromAngle, toAngle)
    if signedDelta == 0 then
        return false
    end
    local direction = signedDelta > 0 and 1 or -1
    local travel = math.abs(signedDelta)
    local ring = state.player.ring
    for _, sh in ipairs(state.room.shutters) do
        if sh.ring == ring then
            local phys = Room.shutters[sh.id]
            if phys and phys.collisionActive then
                local entryAngle
                if direction > 0 then
                    entryAngle = Geometry.norm(sh.angle - config.shutterArcWidth / 2)
                else
                    entryAngle = Geometry.norm(sh.angle + config.shutterArcWidth / 2)
                end
                if distanceAlongDirection(fromAngle, entryAngle, direction) <= travel then
                    return true
                end
            end
        end
    end
    return false
end

-- Ein Frame der Andockhilfe: eine laufende Assistenz weiterschieben oder (ohne
-- aktive Assistenz) eine neue suchen, starten und sofort den ersten Frame
-- anwenden. Genau Config.dockAssistFrames Aufrufe ergeben den vollen Snap.
function Room.updateDockAssist()
    -- Während eines Bridge-Transits ist Assistenz verboten (7.1-Regel dominant).
    if Bridge.isCrossing() then
        Room.resetDockAssist()
        return
    end

    -- Start einer neuen Assistenz, falls keine läuft.
    if not Room.dockAssist then
        local playerRing = state.player.ring
        local playerAngle = state.player.angle

        -- Kandidaten: aktive Brücken (beide Ringe) + Schalter auf dem aktuellen
        -- Ring, jeweils innerhalb Config.dockAssistRange.
        local candidates = {}
        for _, b in ipairs(state.room.bridges) do
            if state.elementStates[b.id] == true then
                -- Shared-Transfer bereits bereit (Baby am Dock, Player dahinter):
                -- DIESE Brücke NICHT assistieren — ein Snap des Players auf die
                -- Brückenachse würde Player und Baby überlappen (Silhouetten-
                -- Verschmelzung, Pass „Bridge Handling"). Der Player steht dort
                -- ohnehin innerhalb von dockRange und A funktioniert direkt.
                if not Baby.canTransfer(b, playerRing, playerAngle) then
                    local d = math.abs(geo.delta(playerAngle, b.angle))
                    if d <= config.dockAssistRange then
                        candidates[#candidates + 1] = { kind = "bridge", id = b.id, angle = b.angle, dist = d }
                    end
                end
            end
        end
        for _, sw in ipairs(state.room.switches) do
            -- Einmalschalter nach dem Verbrauch: verschwunden — keine Andockhilfe.
            if sw.ring == playerRing and not (sw.oneShot == true and state.consumedSwitches[sw.id]) then
                local d = math.abs(geo.delta(playerAngle, sw.angle))
                if d <= config.dockAssistRange then
                    candidates[#candidates + 1] = { kind = "switch", id = sw.id, angle = sw.angle, dist = d }
                end
            end
        end
        -- Kernbrücke (Gate): DIESELBE Andockhilfe/Fangzone wie an normalen
        -- Brücken  — die Center-
        -- Bridge fühlt sich steuerungstechnisch genauso an wie eine Ring->Ring-
        -- Brücke. Nur auf dem Gate-Ring, nur bei aktiver Kernbrücke. Wie bei
        -- Brücken NICHT assistieren, wenn der gemeinsame Baby-Transfer bereits
        -- bereit ist (ein Snap auf die Achse würde Player und Baby überlappen).
        if state.room.gate and playerRing == (state.room.gate.ring or "inner") then
            if state.elementStates[state.room.gate.id] == true then
                if not Baby.canTransfer(state.room.gate, playerRing, playerAngle) then
                    local d = math.abs(geo.delta(playerAngle, state.room.gate.angle))
                    if d <= config.dockAssistRange then
                        candidates[#candidates + 1] = { kind = "gate", id = state.room.gate.id, angle = state.room.gate.angle, dist = d }
                    end
                end
            end
        end
        if #candidates == 0 then
            return
        end

        -- Nächstes Ziel: kleinster absoluter Winkelabstand. Exakter Gleichstand:
        -- keine Assistenz (defensive Regel, keine Array-Reihenfolge).
        local minDist = math.huge
        local chosen = nil
        local tie = false
        for _, c in ipairs(candidates) do
            if c.dist < minDist - EPSILON then
                minDist = c.dist
                chosen = c
                tie = false
            elseif math.abs(c.dist - minDist) <= EPSILON then
                tie = true
            end
        end
        if tie or not chosen then
            return
        end
        if minDist <= EPSILON then
            return -- bereits exakt auf Ziel: keine Animation
        end

        -- Kollisionssicherheit: der kurze signed Weg darf keine geschlossene
        -- Blende kreuzen.
        if dockPathBlocked(playerAngle, chosen.angle) then
            return
        end

        Room.dockAssist = {
            active = true,
            kind = chosen.kind,
            id = chosen.id,
            startAngle = playerAngle,
            targetAngle = chosen.angle,
            signedDelta = geo.delta(playerAngle, chosen.angle),
            frame = 0,
            totalFrames = config.dockAssistFrames,
        }
    end

    -- Einen Frame weiterschieben und Position setzen.
    local da = Room.dockAssist
    da.frame = da.frame + 1
    local progress = da.frame / da.totalFrames
    state.player.angle = Geometry.norm(da.startAngle + da.signedDelta * progress)
    if da.frame >= da.totalFrames then
        state.player.angle = da.targetAngle -- exakt (Float-Sicherheit)
        Room.dockAssist = nil
    end
end

-- --- Druckplatten-Magnet  -------------------
-- Wenn Player oder Baby IDLE sehr nah an einer Plattenmitte stehen (gleicher
-- Ring, innerhalb config.plateSnapRange), rastet die Figur sanft über
-- config.plateSnapFrames auf die exakte Plattenmitte ein. Kleiner Fangbereich,
-- weiches kurzes Einrasten, kein sichtbarer Teleport, keine starke
-- automatische Bewegung; die Steuerung wird nicht weggenommen (nur im
-- bewegungsfreien Frame aufgerufen, wie die Andockhilfe). Reine Position —
-- die Platten-Ableitung (State.deriveElements) läuft danach, damit der
-- Press-Zustand aktuell ist.

-- Temporärer Snap-Zustand (nil = inaktiv).
Room.plateSnap = nil

-- Bricht einen laufenden Plattensnap ab (Eingabe, Crossing, Raumstart).
function Room.resetPlateSnap()
    Room.plateSnap = nil
end

-- Ein Frame des Platten-Magneten: Ziel bestimmen (nächstes Plattenzentrum
-- für Baby oder Player, gleicher Ring) und sanft darauf zubewegen.
function Room.updatePlateSnap()
    -- Während eines Bridge-Transits ist kein Snap erlaubt.
    if Bridge.isCrossing() then
        Room.plateSnap = nil
        return
    end
    local range = config.plateSnapRange or 2.5
    local frames = math.max(1, config.plateSnapFrames or 8)

    -- Nächstes Plattenzentrum im Fangbereich (oder nil).
    local function targetFor(ring, angle)
        local bestDist = range
        local best = nil
        for _, p in ipairs(state.room.plates or {}) do
            if p.ring == ring then
                local d = math.abs(geo.delta(angle, p.angle))
                if d < bestDist then
                    bestDist = d
                    best = p.angle
                end
            end
        end
        return best
    end

    -- Baby zuerst (wird geparkt), dann Player.
    local ring, angle, target, kind = nil, nil, nil, nil
    if state.baby then
        local t = targetFor(state.baby.ring, state.baby.angle)
        if t then
            ring, angle, target, kind = state.baby.ring, state.baby.angle, t, "baby"
        end
    end
    if not target and state.player then
        local t = targetFor(state.player.ring, state.player.angle)
        if t then
            ring, angle, target, kind = state.player.ring, state.player.angle, t, "player"
        end
    end
    if not target then
        Room.plateSnap = nil
        return
    end

    -- Snap-Zustand starten oder fortsetzen (nur bei gleichem Ziel).
    local s = Room.plateSnap
    if not s or s.ring ~= ring or s.target ~= target or s.kind ~= kind then
        s = { ring = ring, target = target, kind = kind, frame = 0, start = angle }
        Room.plateSnap = s
    end
    s.frame = s.frame + 1
    local progress = math.min(1, s.frame / frames)
    local newAngle = Geometry.norm(s.start + geo.delta(s.start, s.target) * progress)
    if kind == "baby" then
        state.setBaby(ring, newAngle)
    else
        state.player.angle = newAngle
    end
    if s.frame >= frames then
        -- exakt auf der Mitte einrasten (Float-Sicherheit)
        if kind == "baby" then
            state.setBaby(ring, target)
        else
            state.player.angle = target
        end
        Room.plateSnap = nil
    end
    -- Platten-/Blendenzustand aktuell halten (rein positionsabhängig).
    state.deriveElements()
    Room.syncPhysicalShutters()
end

return Room