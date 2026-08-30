-- Bridge: logische Abfrage, ob eine Brücke an der aktuellen Position nutzbar
-- ist (ausgefahren + in Docking-Reichweite). Reine Query — keine Bewegung,
-- keine Zustandsänderung, kein Undo. Der Aktivzustand kommt ausschließlich
-- aus State.elementStates; es gibt keine zweite mutable Wahrheit.
-- Keine Imports; die Module werden zentral in main.lua geladen.

Bridge = {}

local config <const> = Config
local geo <const> = Geometry
local state <const> = State

-- Prüft, ob die Brücke bridgeData an der Position playerAngle nutzbar ist.
--   bridgeData:  Eintrag aus room.bridges ({ id, angle, free, rings? })
--   playerAngle: aktueller Spielerwinkel
-- Rückgabe: true nur wenn State.elementStates[bridgeData.id] == true UND
--   (bei 3-Ring-Brücken mit rings-Feld) der Spieler auf einem der verbundenen
--   Ringe steht UND |Geometry.delta(playerAngle, bridgeData.angle)| <=
--   Config.dockRange. Die Dockgrenze ist inklusive; den 0°-Wraparound
--   übernimmt Geometry.delta. Legacy-Brücken ohne rings-Feld verbinden
--   outer <-> inner und sind auf beiden Ringen andockbar.
function Bridge.isUsable(bridgeData, playerAngle)
    if state.elementStates[bridgeData.id] ~= true then
        return false
    end
    -- KEIN SEGMENT GENAU VOR DER BRÜCKE: Überdeckt eine LOGISCH geschlossene
    -- Blende auf EINEM der beiden Brückenringe die Brückenachse (|Delta| <=
    -- shutterArcWidth/2), kann die Brücke NICHT benutzt werden — der Player
    -- kann sie nicht überqueren, solange das Segment zu ist (egal von welcher
    -- Seite er kommt; auch das Landen in einem geschlossenen Segment wird
    -- verhindert). Bewusst die LOGISCHE Schließung (State.elementStates) statt
    -- der physischen collisionActive: G7 (pendingClose, wenn eine Figur im
    -- Bogen steht) darf das Blockieren nicht aufheben — auch ein bereits im
    -- Dock-Bereich stehender Player kann die Brücke dann nicht mehr nutzen.
    for _, sh in ipairs(state.room.shutters or {}) do
        if State.elementStates[sh.id] == false then
            if math.abs(geo.delta(sh.angle, bridgeData.angle)) <= config.shutterArcWidth / 2 then
                return false
            end
        end
    end
    -- 3-Ring-Räume: die Brücke verbindet nur ihre Endpunkt-Ringe (b.rings).
    -- Ein Spieler auf einem anderen Ring kann das Dock NICHT benutzen
    -- (sonst würden z. B. outer<->middle-Brücken vom inneren Ring aus als
    -- nutzbar erscheinen und einen Ambiguitäts-/Transitfehler auslösen).
    if bridgeData.rings and type(bridgeData.rings) == "table" and #bridgeData.rings == 2 then
        local pr = state.player.ring
        if bridgeData.rings[1] ~= pr and bridgeData.rings[2] ~= pr then
            return false
        end
    end
    return math.abs(geo.delta(playerAngle, bridgeData.angle)) <= config.dockRange
end

-- --- Brückentransit (temporärer Runtime-Zustand) ---------------------------
-- Die radiale Überquerung über Config.bridgeAnimDuration. Während des
-- Transits bleibt State.player die einzige persistente Spielerposition; der
-- Ring wechselt erst beim Abschluss. Keine zweite Spielerposition, kein Undo.

Bridge.transit = nil

-- Läuft gerade ein Brückentransit?
function Bridge.isCrossing()
    return Bridge.transit ~= nil and Bridge.transit.active == true
end

-- Aktueller Transit (oder nil).
function Bridge.getTransit()
    return Bridge.transit
end

-- Fortschritt 0..1 während eines aktiven Transits, sonst nil. Kein Overshoot.
-- Bei einem GEMEINSAMEN Transit (Player+Baby) ist das der Player-Fortschritt
-- (nach kurzem Halt + Lead, eigene Player-Dauer), damit der Player knapp
-- hinter dem Baby bleibt.
function Bridge.getTransitProgress()
    if not Bridge.isCrossing() then
        return nil
    end
    local t = Bridge.transit
    if t.shared then
        local denom = t.playerDuration
        if denom <= 0 then
            return 1
        end
        local p = (t.elapsed - t.hold - t.babyLead) / denom
        return math.max(0, math.min(1, p))
    end
    if t.duration <= 0 then
        return 1
    end
    return math.min(1, t.elapsed / t.duration)
end

-- Baby-Fortschritt beim GEMEINSAMEN Transit (Baby startet nach dem Halt vor
-- dem Player und bewegt sich mit eigener, kürzerer Dauer — es zieht dadurch
-- sichtbar nach vorn und landet zuerst). Sonst nil. Kein Overshoot.
function Bridge.getBabyTransitProgress()
    local t = Bridge.transit
    if not (t and t.active and t.shared) then
        return nil
    end
    local denom = t.babyDuration
    if denom <= 0 then
        return 1
    end
    local p = (t.elapsed - t.hold) / denom
    return math.max(0, math.min(1, p))
end

-- Bricht einen laufenden Transit ab (Raumstart, Tests, spätere Raumwechsel).
function Bridge.resetTransit()
    Bridge.transit = nil
end

-- Zielring eines Brückentransits (reine Ableitung).
--   toTarget   = "center" (Kernbrücke/Gate) -> "center".
--   bridgeData.rings = { <RingA>, <RingB> } (3-Ring-Räume): die Brücke
--     verbindet diese beiden Ringe; Ziel = der Ring, der NICHT fromRing ist.
--   Legacy (kein rings-Feld): gegenüberliegender Ring (outer <-> inner).
-- Rückgabe: Ringname oder "center"; Fehler bei unbekanntem fromRing.
function Bridge.targetRing(bridgeData, fromRing, toTarget)
    if toTarget == "center" then
        return "center"
    end
    if bridgeData and type(bridgeData.rings) == "table" and #bridgeData.rings == 2 then
        if bridgeData.rings[1] == fromRing then
            return bridgeData.rings[2]
        end
        if bridgeData.rings[2] == fromRing then
            return bridgeData.rings[1]
        end
        error("Bridge.targetRing: fromRing '" .. tostring(fromRing) .. "' ist keiner der Brückenringe")
    end
    if fromRing == "outer" then
        return "inner"
    end
    if fromRing == "inner" then
        return "outer"
    end
    error("Bridge.targetRing: ungültiger fromRing '" .. tostring(fromRing) .. "'")
end

-- Startet einen Brückentransit von fromRing zur gegenüberliegenden Seite.
-- toTarget ist optional und erlaubt die Kernbrücke (Gate): toTarget = "center"
-- bedeutet eine Brücke vom Gate-Ring zum MITTELPUNKT (Kernrand) — dieselbe
-- Bridge-Logik wie bei einer normalen Ring->Ring-Brücke, nur mit anderem Ziel.
-- Richtet State.player.angle auf die Brückenachse aus, wechselt den Ring aber
-- NICHT (erst bei Transitabschluss via Bridge.update; bei "center" gibt es
-- keinen Zielring — der Raum wird danach abgeschlossen). Rückgabe: false, wenn
-- bereits ein Transit läuft (dann wird nichts überschrieben).
function Bridge.beginTransit(bridgeData, fromRing, toTarget)
    if Bridge.isCrossing() then
        return false
    end
    local toRing = Bridge.targetRing(bridgeData, fromRing, toTarget)
    Bridge.transit = {
        active = true,
        fromRing = fromRing,
        toRing = toRing,
        angle = bridgeData.angle,
        elapsed = 0,
        duration = config.bridgeAnimDuration,
        -- Einmal-Brücke: erst beim Abschluss verbrauchen (der Player ist dann
        -- über die Brücke hinweg) — Bridge.update konsumiert sie dort.
        bridgeId = bridgeData.id,
        oneShot = (bridgeData.oneShot == true),
    }
    state.player.angle = Geometry.norm(bridgeData.angle)
    return true
end

-- Startet einen GEMEINSAMEN Brückentransit von Player + Baby (EIN A).
-- Voraussetzung: Baby korrekt an der Brücke (Room.tryUseConnection prüft das
-- über Baby.canTransfer). toTarget ist optional und erlaubt die Kernbrücke
-- (Gate): toTarget = "center" bedeutet einen gemeinsamen Transit zum
-- MITTELPUNKT — exakt dieselbe Shared-Transit-Logik wie auf jeder anderen
-- Brücke, nur mit anderem Zielort. Eine gemeinsame Progress-Wahrheit steuert
-- beide; das Baby startet nach kurzem Halt (hold) und kleinem Lead vor dem
-- Player. Der Ring wechselt für beide erst beim Abschluss (Bridge.update;
-- bei "center" gibt es keinen Zielring — der Raum wird danach abgeschlossen).
-- Rückgabe false, wenn bereits ein Transit läuft oder kein Baby vorhanden.
function Bridge.beginSharedTransit(bridgeData, fromRing, toTarget)
    if Bridge.isCrossing() then
        return false
    end
    if not state.baby then
        return false
    end
    local toRing = Bridge.targetRing(bridgeData, fromRing, toTarget)
    -- SHARED BRIDGE PATH FIX — räumlich getrennte Phasen (kein Hintergrund-
    -- Cutting): beide Figuren starten den Transit auf ihren TATSÄCHLICHEN
    -- Positionen. Phase A (hold): tangentiales Alignment auf dem RING — Baby
    -- auf die Bridge-Achse, Player in die Dockformation direkt dahinter
    -- (aus den Figurenradien abgeleiteter Abstand, in der bisherigen Schieberich-
    -- tung); der Radius bleibt der Ringradius. Danach beginnt die RADIALE
    -- Überquerung (Baby zuerst, Player folgt) mit konstantem Achswinkel.
    -- WICHTIG: Der Gameplay-State wird hier NICHT vorzeitig auf die Achse
    -- gesetzt — der Transitstate trägt die realen Startwinkel; erst beim
    -- Abschluss (Bridge.update) wechseln ring/angle auf den Zielring. Dadurch
    -- widersprechen sich Gameplay-State und sichtbare Transitgeometrie nie.
    local gapDeg = config.sharedFormationGapDeg or (config.playerRadius + config.babyRadius + 2) / config.innerRadius * (180 / math.pi)
    -- BABY-LANDESEITE (Level-3-Bugfix): die Richtung, in die das Baby nach
    -- dem gemeinsamen Transit auf dem Zielring landet, wird DETERMINISTISCH
    -- abgeleitet — die relative Reihenfolge wird beim Landing IMMER erhalten,
    -- kein Winkel-Flip, kein Spawn auf Gegenrichtung, keine automatische
    -- Seitenkorrektur. Das Baby bleibt leicht VOR dem Player in
    -- Transitrichtung, auf DERSELBEN SEITE wie VOR dem Wechsel.
    --   Priorität 1: explizites bridgeData.babyLandDir (Level-Daten).
    --   Priorität 2 (DIE REGEL): PLAYER relativ zum BABY — sign(delta(player,
    --     baby)) ist exakt „auf welcher Seite des Players das Baby VOR dem
    --     Transit steht". Diese Seite wird IMMER beibehalten (auch wenn beide
    --     auf derselben Seite der Bridge-Achse stehen — die Bridge-Achse ist
    --     hier bewusst NICHT die Referenz, sonst würde das Baby gespiegelt).
    --   Priorität 3: letzte Schieberichtung (Fallback, nur wenn beide exakt
    --     auf demselben Winkel stehen — dann ist die Seite per Formation
    --     undefiniert; lastPushDirection spiegelt den echten Schub).
    local dir = bridgeData.babyLandDir
    if dir == nil and state.baby and state.player then
        local d = geo.delta(state.player.angle, state.baby.angle)
        if math.abs(d) > 0.01 then
            dir = (d > 0) and 1 or -1
        end
    end
    if dir == nil then
        dir = (state.baby and state.baby.lastPushDirection) or 1
    end
    local formationAngle = geo.norm(bridgeData.angle - dir * gapDeg)
    Bridge.transit = {
        active = true,
        fromRing = fromRing,
        toRing = toRing,
        angle = bridgeData.angle,
        elapsed = 0,
        hold = config.sharedBridgeHold,
        bridgeId = bridgeData.id,
        oneShot = (bridgeData.oneShot == true),
        -- Optionale deterministische Landeseite des Babys (Level-Daten) ODER
        -- die aus der Formation abgeleitete Richtung (Level-3-Bugfix). Der
        -- Landing-Code nutzt nur noch diesen Wert (kein lastPushDirection
        -- mehr), damit die Reihenfolge nie gespiegelt wird.
        babyLandDir = dir,
        babyLead = config.sharedBabyLead,
        babyDuration = config.sharedBabyDuration,
        playerDuration = config.sharedPlayerDuration,
        shared = true,
        babyStartAngle = state.baby.angle,
        playerStartAngle = state.player.angle,
        formationAngle = formationAngle,
        babyLanded = false,
    }
    return true
end

-- Schaltet den Transit weiter. Rückgabe true genau im Abschlussframe: dann
-- werden Player (und bei gemeinsamem Transit auch das Baby) auf den Zielring
-- gesetzt und der Transit deaktiviert. Kein Overshoot. Zweiter Rückgabewert:
-- true, wenn es ein gemeinsamer Player+Baby-Transit war. Dritter Rückgabewert:
-- true, wenn das Baby in DIESEM Frame erstmals den Zielring erreicht hat
-- (Baby-Landing-Event für die Settle-/Blick-zurück-Animation; nur gemeinsam).
-- Vierter Rückgabewert: true, wenn es ein Kernbrücken-Transit zum MITTELPUNKT
-- war (dann folgt der Levelabschluss erst nach dem Landing — main.lua).
function Bridge.update(dt)
    if not Bridge.isCrossing() then
        return false, false, false, false
    end
    local t = Bridge.transit
    t.elapsed = t.elapsed + dt
    local done
    if t.shared then
        done = t.elapsed >= t.hold + t.babyLead + t.playerDuration
    else
        done = t.elapsed >= t.duration
    end
    -- Baby-Landing: das Baby erreicht den Zielring früher als der Player
    -- (eigene, kürzere Dauer). Einmalig melden (kein Repeat pro Frame).
    local babyJustLanded = false
    if t.shared and not t.babyLanded and (t.elapsed - t.hold) >= t.babyDuration then
        t.babyLanded = true
        babyJustLanded = true
    end
    if done then
        if t.toRing == "center" then
            -- Kernbrücke (Gate): Ziel ist der MITTELPUNKT — es gibt keinen
            -- Zielring. Player und Baby bleiben auf dem Gate-Ring; die
            -- sichtbare Landung am Kernrand liegt im Renderer
            -- (Render.playerAtCenter), der Levelabschluss folgt erst danach
            -- (main.lua). Kein Teleport, kein Ringwechsel.
            state.player.angle = Geometry.norm(t.angle)
            if t.shared and state.baby then
                -- GEMEINSAMER Kernbrücken-Abschluss (Baby-Winkel-Handoff):
                -- Das Baby landet wie bei jeder NORMALEN Shared-Bridge einen
                -- kleinen Bogen (babyBridgeExitOffset) VOR dem Player — nie
                -- exakt auf der Brückenachse (die Brückenachse behält der
                -- Player). Dadurch hat der Handoff zum nächsten Raum einen
                -- deterministischen Winkel-Versatz (Player an der Achse, Baby
                -- davor): BABY_ANGLE ist nie == PLAYER_ANGLE, die relative
                -- Push-only-Reihenfolge (Player -> Baby) bleibt erhalten und
                -- das Baby erscheint im Folge-Raum an seinem EIGENEN Winkel.
                -- Dies ist exakt die etablierte Shared-Landing-Regel
                -- (config.babyBridgeExitOffset) — nur auf den Kernbrücken-
                -- Abschluss übertragen.
                state.setBaby(t.fromRing, Geometry.norm(t.angle + config.babyBridgeExitOffset))
            end
        else
            state.player.ring = t.toRing
            state.player.angle = Geometry.norm(t.angle)
            if t.shared then
                -- Baby landet leicht voraus. Die Richtung ist DETERMINISTISCH
                -- im Transit gespeichert (bridgeData.babyLandDir oder aus der
                -- Formation abgeleitet — Level-3-Bugfix): die relative
                -- Reihenfolge wird beim Landing NIE gespiegelt.
                local dir = t.babyLandDir or 1
                state.setBaby(t.toRing, Geometry.norm(t.angle + dir * config.babyBridgeExitOffset))
            end
        end
        -- Einmal-Brücke: erst NACH der Überquerung verbrauchen (der Player ist
        -- drüber hinweg, dann kollabiert sie) — nicht schon beim Transitstart.
        if t.oneShot then
            state.consumeBridge(t.bridgeId)
        end
        -- Druckplatten: die Figuren sind auf den Zielring gewechselt — die
        -- Plattenzustände sind rein positionsabhängig und werden neu abgeleitet
        -- (z. B. Landung im Druckbereich einer Platte). Kein Gameplay-Effekt
        -- der Platte selbst (kein Undo, kein Sound).
        state.deriveElements()
        Bridge.transit = nil
        return true, t.shared, babyJustLanded, (t.toRing == "center")
    end
    return false, t.shared, babyJustLanded, false
end

return Bridge