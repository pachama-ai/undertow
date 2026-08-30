-- main.lua — Composition Root für Ringe (Playdate).
-- Lädt CoreLibs und alle Projektmodule in deterministischer Reihenfolge
-- (Schicht 0 bis Schicht 3). Keine Import-Rückgabewerte werden ausgewertet;
-- die Module legen selbst ihre globale PascalCase-Tabelle an.
--
-- Räume 1-6 sind durchspielbar (Abschlussphase A: alle Leveldaten-Räume).
--   Kurbel / D-Pad  -> Bewegung (Player -> Room.movePlayer)
--   A               -> Brücke/Gate benutzen (Room.tryUseConnection)
--   B               -> letzte zustandsändernde Handlung rückgängig (Undo)
--   Render.drawRoom  -> Rendering (read-only)
-- Raumprogression: ein erfolgreiches Gate beendet Raum 1-5 und lädt automatisch
-- den nächsten Raum (Controller). Das finale Gate in Raum 6 startet das Outro
-- (Abschlussphase B: R1 löst sich auf, der Kern füllt den Bildschirm, die Iris
-- öffnet sich, Schnitt zum Titel) und führt automatisch zurück ins Startmenü.
-- Kamera, Raumwechselanimation, Audio, Startmenü und Speicherstand sind
-- implementiert.

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
import "CoreLibs/crank"

-- --- Projektmodule (Composition Root) ------------------------------------
import "core/config"
import "core/geometry"
import "core/state"
import "core/undo"
import "core/audio"
import "core/save"
import "core/sysmenu"
import "core/textui"
import "core/tutorial"
-- World-Abhängigkeiten: switch/bridge/gate VOR room (Room nutzt sie zur
-- Laufzeit; switch muss für die Schalterregeln geladen sein).
import "world/switch"
import "world/bridge"
import "world/gate"
import "world/baby"
import "world/player"
-- World-Koordinator
import "world/room"
import "data/levels"
-- UI (Room muss VOR Render geladen sein: Render cached Room beim Laden)
import "ui/render"
import "ui/camera"
import "ui/roomtransition"
import "ui/wipe"
import "ui/phase7"
import "ui/menu"
import "ui/transition"

-- Lokale Referenzen auf die globalen Module (keine Import-Rückgabewerte).
local config <const> = Config
local geo <const> = Geometry
local state <const> = State
local undo <const> = Undo
local audio <const> = Audio
local save <const> = Save
local sysmenu <const> = Sysmenu
local tutorial <const> = Tutorial
local player <const> = Player
local baby <const> = Baby
local room <const> = Room
local levels <const> = Levels
local render <const> = Render
local camera <const> = Camera
local menu <const> = Menu
local bridge <const> = Bridge
local transition <const> = Transition
local roomTransition <const> = RoomTransition
local wipe <const> = Wipe
local phase7 <const> = Phase7

local gfx <const> = playdate.graphics

-- Fester Frame-Step aus der konfigurierten Refreshrate.
local FRAME_DT <const> = 1 / config.refreshRate

playdate.display.setRefreshRate(config.refreshRate)

-- Szenenzustand: für diesen Vertical Slice ausschließlich "room".
local currentScene = "room"

-- App-Zustand: "menu" (Startmenü) | "game" (Gameplay) | "outro" (Abschluss-
-- phase B: Präsentation nach dem finalen Gate). Kleine App-Ebene, keine
-- State-Machine-Bibliothek. Beim App-Start ist das Menü aktiv; Gameplay beginnt
-- erst nach Auswahl von CONTINUE oder NEW GAME.
local appMode = "menu"

-- Minimaler lokaler Raumcontrollerzustand (kein Levelmanager).
local currentRoomIndex = 1
local roomComplete = false
-- Finaler Raum-6-Moment (Pass 2): Frame-Zähler für den kurzen Stillstand vor
-- dem Outro (nil = nicht aktiv). Währenddessen ist die Eingabe gesperrt und
-- die Welt steht (Ghost-Drift eingefroren).
local finalHoldFrames = nil

-- Level-Restart-Animation (B): statt hartem Schnitt kollabieren die Ringe zum
-- Mittelpunkt, das Level wird im Kollaps-Ende neu geladen und baut sich aus
-- dem Kern wieder auf. nil = keine laufende Animation. Währenddessen ist die
-- Eingabe gesperrt (updateRoom kehrt oben zurück).
local restartAnim = nil -- { t = 0, reloaded = false }
local RESTART_COLLAPSE <const> = config.restartCollapseDuration
local RESTART_HOLD <const> = config.restartHoldDuration
local RESTART_EXPAND <const> = config.restartExpandDuration
local RESTART_TOTAL <const> = RESTART_COLLAPSE + RESTART_HOLD + RESTART_EXPAND

-- Kurze Ruhe NACH dem Level-Reveal (Start vom Titel ODER Raumübergang): die
-- fertige Levelansicht steht sichtbar, Gameplay ist gesperrt. Erst danach
-- startet die NEW-GAME-Einleitung bzw. die Mechanik-Fokus-Prüfung — das
-- Tutorial unterbricht den Reveal nie (Punkt 8/9/10).
local revealSettle = 0
-- NEW GAME: Einleitung startet erst NACH dem Level-Reveal + der Ruhe.
local introPending = false

-- Druckplatten-Audio (EDGE-Trigger): letzter bekannter Press-Zustand für die
-- ON/OFF-Flankenerkennung (kein Sound pro Frame). nil = noch keine Messung.
local prevPlatePressed = nil
-- Phase-7-Spezialübergang: letzte gemeldete Phase (Audio-Edge-Trigger).
local lastP7Phase = nil

-- Radialer Raumwechsel (neuer Level-/Room-Übergang): der nächste Raum wird
-- NICHT sofort geladen. Der alte Raum bleibt während der Auflösungsphase aktiv
-- (Eingabe gesperrt); am Reveal-Punkt der Ring-Transition lädt dieser Puffer
-- den neuen Raum (pendingRoomIndex -> startRoom -> markLoaded). nil = kein
-- ausstehender Raumwechsel.
local pendingRoomIndex = nil

-- Vom Playdate-Systemmenü angefordete Aktion (Phase 10.3). Die Callbacks
-- registrieren hier NUR einen Wunsch ("restartRoom" | "mainMenu"); verarbeitet
-- wird die Aktion einmalig am Anfang des nächsten playdate.update() (atomar,
-- ohne alten Frameinput). nil = keine ausstehende Aktion.
local pendingSystemAction = nil

-- Abschlussphase A: Maximal spielbarer Raum wird aus den tatsächlichen
-- Leveldaten abgeleitet (alle vorhandenen Räume sind spielbar). Der frühere
-- temporäre Phasen-Gate-Wert MAX_PLAYABLE_ROOM = 3 ist entfernt; es gibt keine
-- künstliche Begrenzung mehr (ARCHITECTURE: 7 Rätselräume / 8 Ringnummern).
local maxPlayableRoom <const> = #levels

-- Gemeinsamer Raumausgang (Baby-Regel): Index des ersten Raums mit einer
-- baby-Definition (datengetrieben, keine Raum-2-Hardcode). Ab diesem Raum
-- wird das Baby mitgeführt und der finale Ausgang verlangt das Baby.
local babyIntroducedAt = 0
for i = 1, #levels do
    if levels[i].baby then
        babyIntroducedAt = i
        break
    end
end
-- Session-Begleiter-Flag: true, sobald das Baby in einem Raum war; es wird ab
-- dann in jeden Folge-Raum mitgenommen (State.init erzeugt den Begleiter-Start).
-- NEW GAME setzt es zurück; CONTINUE hinter dem Einführungsraum behält es.
local babyCarried = false

-- Session-Fortschritt (Phase 10.2): höchste in dieser Session erreichte
-- Raumnummer. Wird beim App-Start aus dem Datastore geladen (Save.load) und
-- steigt monoton; "CONTINUE" startet genau diesen Raum.
local highestRoom = 1

-- Existiert ein gültiger Spielfortschritt (für den Startscreen: CONTINUE nur
-- anzeigen, wenn ein Save vorhanden ist)? Wird beim Menü-Öffnen frisch
-- bestimmt (Save.hasSave).
local saveExists = false

-- Lädt den Fortschritt beim App-Start (genau ein Datastore-Read). Read-only:
-- verändert keinen Gameplay-State, setzt nur den Sessionwert. Ungültige oder
-- fehlende Saves fallen auf Raum 1 zurück; zu hohe Werte werden auf den
-- höchsten spielbaren Raum geclamped.
local function loadProgress()
    highestRoom = Save.load(maxPlayableRoom, #levels)
    saveExists = Save.hasSave(maxPlayableRoom, #levels)
    -- Tutorial-Seen-Flags laden (persistiert; fehlende Daten = leere Tabelle).
    tutorial.init(Save.loadTutorial())
end

-- Schreibt einen erreichten Raum NUR bei einem echten neuen Höchststand
-- (monoton; der gespeicherte Wert sinkt nie). Schreibfehler stoppen die
-- Progression nicht: Der Sessionwert steigt trotzdem, nur der persistierte
-- Stand fehlt dann (wird geloggt).
local function saveHighestRoom(roomIndex)
    local newHighest, shouldWrite = Save.applyProgress(highestRoom, roomIndex)
    if not shouldWrite then
        return
    end
    highestRoom = newHighest
    -- Tutorial-Flags mitschreiben, damit der persistierte Stand sie behält.
    local ok, err = Save.write(highestRoom, tutorial.flags)
    if not ok then
        print("main.saveHighestRoom: Datastore-Write fehlgeschlagen: " .. tostring(err))
    end
end

-- B-Eingabe: B startet das AKTUELLE Level einfach neu (kein Rückgängig, kein
-- Zurückspulen). Raumneustart ist damit sowohl über das Systemmenü als auch
-- direkt über B möglich.

-- Initialisiert einen Raum: State.init -> Undo.clear -> Room.init.
local function startRoom(index)
    local roomData = levels[index]
    if not roomData then
        error("main.startRoom: Raum " .. tostring(index) .. " existiert nicht")
    end
    -- Ein alter Brückentransit, Baby-Transit, eine alte Andockhilfe oder ein
    -- laufender Plattensnap darf nie in einen neuen Raum weiterlaufen.
    bridge.resetTransit()
    baby.resetTransit()
    room.resetDockAssist()
    room.resetPlateSnap()
    -- Baby-Begleiter (Raum-Regel): expliziter Carry-Parameter — das Baby wird
    -- in Folge-Räume mitgenommen (State erzeugt dann den Begleiter-Start), und
    -- sobald ein Raum eine eigene baby-Definition hat, gilt es als eingeführt.
    state.init(roomData, babyCarried)
    if roomData.baby then
        babyCarried = true
    end
    undo.clear()
    room.init()
    roomComplete = false
    currentRoomIndex = index
    -- Finaler Raum-6-Stillstand beenden: Ein Systemmenü-Restart mitten im
    -- finalen Moment darf kein Outro mehr nachziehen („temporäre Visualstates"
    -- zurücksetzen, B-Taste-Rework Teil 4).
    finalHoldFrames = nil
    render.endFinalMoment()
    -- Spieler-/Augenanimation auf Neutral (kein Squint/Widen/Blink-Rest,
    -- Facing-Standard CW, Idle-Timer neu). Rein visuell.
    render.resetPlayerVisual()
    -- Audio: Bewegungsrest/Kernpuls-Timer/Raumton neu; laufende SFX (z. B.
    -- Torübergang) klingen weiter aus.
    audio.resetRoom(index)
    -- Druckplatten-Audio: Press-Erbe beim Raumstart verwerfen (kein Phantom-ON/OFF).
    prevPlatePressed = nil
end

-- Startet das Outro nach dem finalen Gate (Raum 7). Nur Präsentation: wechselt
-- in den Outro-Modus, startet die Transition mit der sichtbaren Room-7-Geometrie
-- und entfernt die Gameplay-Systemmenüeinträge (Punkt 16: kein „Raum neu
-- starten"/„Zum Menü" im Outro). sysmenu.removeAll() direkt (Äquivalent zu
-- removeGameplaySystemMenu, das erst später deklariert ist). B ist im Outro
-- gesperrt (updateScene ruft updateRoom dort nicht auf).
local function startOutro()
    transition.startOutro(currentRoomIndex, state.room.rings.outer, state.room.rings.inner)
    appMode = "outro"
    sysmenu.removeAll()
    -- FINALES ENDE (letzter Raum): das System kommt zur Ruhe — kein Sieg-
    -- Jingle. Sine gleitet langsam von der Core-Frequenz auf 55 Hz.
    audio.playFinalSettle(currentRoomIndex)
end

-- Zentrale Progressionsentscheidung nach einer Verbindungs-Aktion (A).
--   crossing     -> eine laufende Andockhilfe beenden
--   roomComplete -> nächsten Raum laden (falls vorhanden), sonst abgeschlossen.
-- Räume 1-6: sofort nächsten Raum initialisieren (roomComplete wird von
-- startRoom zurückgesetzt). Raum 7: kein nächster Raum (nextIndex 8 existiert
-- nicht) -> roomComplete bleibt true und das Gameplay friert sichtbar ein
-- (kein Crash, kein nil-Zugriff; das Outro folgt separat in Abschlussphase B).
local function handleConnectionResult(result, fromCenterTransit)
    if result.crossing then
        room.resetDockAssist()
    end
    if result.roomComplete then
        local nextIndex = currentRoomIndex + 1
        if levels[nextIndex] ~= nil then
            -- Fortschritt persistieren (nur bei echtem neuen Höchststand) BEVOR
            -- der nächste Raum initialisiert wird: Raum 1 -> Save 2, ..., Raum 6
            -- -> Save 7. Raum-7-Completion lädt keinen Raum 8 und speichert nie
            -- einen Wert >= 8 (Save bleibt 7).
            saveHighestRoom(nextIndex)
            -- Center-Wipe: Der neue Raum wird NICHT sofort geladen. Gameplay
            -- friert ein; der gefüllte Mittelpunkt wächst über den Bildschirm
            -- (alte Welt schließt sich), erst bei vollständiger Abdeckung lädt
            -- der Wipe-Puffer den neuen Raum VERDECKT (startRoom), danach
            -- schrumpft der Kreis und gibt das fertige neue Level frei.
            roomComplete = true
            pendingRoomIndex = nextIndex
            -- Figuren für die KONTINUIERLICHE Transition erfassen (Player/Baby
            -- bleiben sichtbar und interpolieren von der alten zur neuen
            -- Startposition — kein 200-300-ms-Verschwinden). Alte Position aus
            -- dem noch aktiven Raum, neue Position aus den Daten des nächsten
            -- Raums (Ringnummern + Winkel; Baby-Begleiter analog zum Carry).
            -- Nach einem Kernbrücken-Abschluss (Gate) stehen die Figuren am
            -- MITTELPUNKT (Kernrand) — die Transition startet von dort.
            --
            -- BABY-WINKEL-REGEL (globaler Bugfix): transitionEntry erfasst
            -- playerAngle und babyAngle als GETRENNTE Werte aus den
            -- TATSÄCHLICHEN State-Winkeln (state.player.angle /
            -- state.baby.angle) — niemals wird babyAngle == playerAngle
            -- gesetzt. Beim gemeinsamen Kernbrücken-Abschluss hat das Baby
            -- durch die Shared-Landing (babyBridgeExitOffset) bereits einen
            -- EIGENEN Winkel (leicht VOR dem Player); dieser echte Winkel wird
            -- übernommen und beim Handoff wieder angewendet (A1/A2/A5/A8).
            local function ringNum(roomData, ringName) return roomData.rings[ringName] end
            local gateAngle = state.room.gate and state.room.gate.angle
            local pf
            if fromCenterTransit and gateAngle then
                pf = { ring = "center", angle = state.player.angle }
            else
                pf = { ring = ringNum(state.room, state.player.ring), angle = state.player.angle }
            end
            local pt = { ring = ringNum(levels[nextIndex], levels[nextIndex].start.ring), angle = levels[nextIndex].start.angle }
            local bf, bt = nil, nil
            if state.baby then
                if fromCenterTransit and gateAngle then
                    bf = { ring = "center", angle = state.baby.angle }
                else
                    bf = { ring = ringNum(state.room, state.baby.ring), angle = state.baby.angle }
                end
            end
            if levels[nextIndex].baby then
                bt = { ring = ringNum(levels[nextIndex], levels[nextIndex].baby.start.ring), angle = levels[nextIndex].baby.start.angle }
            elseif babyCarried then
                bt = { ring = ringNum(levels[nextIndex], levels[nextIndex].start.ring), angle = geo.norm(levels[nextIndex].start.angle - config.babyCompanionOffsetDeg) }
            end
            -- Kernrand des alten Raums für die Mittelpunkt-Startposition.
            roomTransition.oldRoomIndex = currentRoomIndex
            roomTransition.captureFigures(pf, pt, bf, bt)
            if nextIndex == config.phaseTwoStartRoom then
                -- LEVEL-7-SPEZIALÜBERGANG (Ende der Lernphase): statt des
                -- normalen Center-Wipes läuft die geometrische Sequenz
                -- (Ruhe -> 3 Kern-Pulse -> Kollaps zum Punkt -> Explosion ->
                -- Dunkel -> Wiederaufbau der neuen Phase aus dem Kern). Der
                -- neue Raum wird erst in der dunklen Phase verdeckt geladen
                -- (phase7.update liefert "load").
                phase7.start(nextIndex, pf, pt, bf, bt, currentRoomIndex)
                -- Audio (MIXING): Kernpuls während der Sequenz pausieren;
                -- Phasen-Edge-Tracking zurücksetzen.
                lastP7Phase = nil
                audio.setCoreHold(4.0)
            else
                -- Center-Wipe starten: der gefüllte Mittelpunkt wird zur
                -- Blende. Player/Baby stehen am Mittelpunkt; ihr gemeinsamer
                -- Exit erfolgt am Ende des Wipes
                -- (wipe.playerPosAndAngle/babyPosAndAngle).
                wipe.start(nextIndex, pf, pt, bf, bt, currentRoomIndex)
                -- LEVELÜBERGANG-WOOSH: sobald der weiße Kreis zu wachsen
                -- beginnt, läuft der breite Luft-/Energie-Woosh exakt mit dem
                -- Wachsen mit und klingt auf dem weißen Bildschirm aus. Genau
                -- EIN Woosh pro Übergang; beim direkten Cut kein zweiter.
                audio.playTransitionWoosh()
            end
            -- Atmosphäre: kurzer Systemimpuls (visuell + klanglich) am Beginn
            -- des Raumwechsels. Rein visuell, Progression unverändert. Der
            -- Klang wird pro gelöstem Raum minimal tiefer/resonanter.
            render.noteRoomComplete()
            audio.playRoomCompletion(nextIndex - 1)
            -- Raumübergang: eigener, größerer Abschlusssound beim bestätigten
            -- GEMEINSAMEN Raumabschluss (Gate verlangt das Baby am Ausgang) —
            -- nicht schon beim bloßen Erreichen des Gates ohne Baby.
            audio.playRoomTransition()
        else
            -- Raum 6 finales Gate -> finaler Gameplay-Abschluss + Outro.
            -- roomComplete bleibt interner Zustand; die Gameplaypipeline läuft
            -- danach nicht weiter. Kein Room7, kein Save7, highestRoom bleibt 6.
            -- Atmosphäre (Pass 2): kurzer mechanischer Systemimpuls wie in
            -- 1-5, dann hält die Welt einen Moment still (Ghost-Drift stoppt,
            -- Eingabe gesperrt), BEVOR das Outro startet. Kein Startscreen.
            roomComplete = true
            render.resetPlayerVisual()
            -- Player ist am Mittelpunkt gelandet (Kernbrücke): die finale
            -- Welt bleibt mit der Figur am Kernrand stehen (kein Sprung zurück
            -- zum Ring), bevor das Outro den Kern wachsen lässt. Rein visuell.
            if fromCenterTransit then
                render.notePlayerAtCenter()
            end
            audio.setCompleted()
            render.beginFinalMoment()
            audio.playRoomCompletion(currentRoomIndex)
            -- FINALES ENDE: etwas längerer, abschließender Room-Transition-Sweep
            -- (statt des normalen) — kein Victory-Fanfare.
            audio.playRoomTransitionFinal()
            finalHoldFrames = config.finalHoldFrames
        end
    end
end

-- --- Playdate-Systemmenü-Controller (Phase 10.3) ----------------------------
-- Die Callbacks registrieren nur eine Pending-Aktion; die eigentliche Aktion
-- führt playdate.update() zentral aus (kein Gameplaycode im Systemmenü-
-- Callstack, keine duplizierte Resetlogik).

-- Registriert die zwei Gameplay-Systemmenüeinträge (Raum neu starten / Zum
-- Menü), genau einmal; beide Callbacks setzen nur pendingSystemAction.
local function installGameplaySystemMenu()
    -- Erst alle eigenen Items entfernen (auch das ANLEITUNG-Item aus dem
    -- Startmenü-Modus), dann in fester Reihenfolge neu registrieren:
    -- [Raum neu starten, Zum Menü, ANLEITUNG] (ANLEITUNG immer zuletzt).
    sysmenu.removeAll()
    sysmenu.install(
        function() pendingSystemAction = "restartRoom" end,
        function() pendingSystemAction = "mainMenu" end)
    -- Anleitung ist immer verfügbar (auch während des Gameplays).
    sysmenu.installHelp(function() pendingSystemAction = "anleitung" end)
end

-- Entfernt die Gameplay-Systemmenüeinträge (Startmenü-Modus: keine
-- gameplaybezogenen Custom-Items sichtbar, Punkt 45).
local function removeGameplaySystemMenu()
    sysmenu.removeAll()
end

-- „Raum neu starten": aktuellen Raum vollständig neu initialisieren. Reiner
-- Controller-Wunsch des Systemmenüs; die zentrale Wahrheit bleibt startRoom.
-- Aktuelle Raumnummer bleibt (kein highestRoom, kein nächster Raum). KEIN
-- Datastore-/Save-Zugriff. Camera wird direkt stabil auf denselben Raum
-- gesetzt (kein 1,2-s-Raumwechsel, Punkt 17). Ein laufender radialer
-- Raumübergang wird dabei abgebrochen (kein ausstehender Raumwechsel).
local function restartRoom()
    pendingRoomIndex = nil
    roomTransition.reset()
    wipe.reset()
    phase7.reset()
    camera.clearRevealScale()
    startRoom(currentRoomIndex)
    camera.init(state.room.rings.outer)
end

-- --- B-Restart-Animation ----------------------------------------------------
-- B startet das aktuelle Level neu — NICHT als harter Schnitt, sondern als
-- kurze geometrische Animation: die aktuellen Ringbahnen (mit allen Objekten)
-- kollabieren zum Mittelpunkt (Ease-In), kurz bleibt nur der zentrale Kreis
-- sichtbar, dann bauen sich die Ringe des frisch geladenen Levels aus dem Kern
-- wieder auf (Ease-Out). Kein Text, kein Flash, keine Partikel.

-- Startet die Restart-Animation (Gameplay friert sofort ein; updateRoom kehrt
-- während der Animation oben zurück). Der Level-Reset (startRoom) passiert im
-- Kollaps-Ende, damit der Wiederaufbau den frischen Startzustand zeigt.
local function startRestartAnim()
    restartAnim = { t = 0, reloaded = false }
    camera.setRestartScale(1)
    -- MIXING (AUFTRAG): während Collapse/Rebuild pausiert der Kernpuls.
    audio.setCoreHold(RESTART_TOTAL)
end

-- Treibt die Restart-Animation (Kollaps -> Kern -> Wiederaufbau). Wird von
-- updateRoom oben aufgerufen, solange restartAnim aktiv ist. Jede Phase startet
-- ihren eigenen, exakt synchronen Sound (EDGE-Trigger, genau einmal).
local function updateRestartAnim(dt)
    local a = restartAnim
    if not a then
        return
    end
    a.t = a.t + dt
    if a.t <= RESTART_COLLAPSE then
        -- Kollaps: 1 -> 0 mit Ease-In (schnell, geometrisch).
        if not a.collapsePlayed then
            a.collapsePlayed = true
            audio.playRestartCollapse()
        end
        local p = a.t / RESTART_COLLAPSE
        camera.setRestartScale(1 - p * p)
    elseif a.t <= RESTART_COLLAPSE + RESTART_HOLD then
        -- Am Kern angekommen: nur der zentrale Kreis bleibt sichtbar. Genau
        -- einmal hier das Level neu laden (alle Zustände auf Levelstart; die
        -- Tutorial-Flags und der Kampagnen-Fortschritt bleiben unberührt).
        if not a.corePlayed then
            a.corePlayed = true
            audio.playRestartCore()
        end
        camera.setRestartScale(0)
        if not a.reloaded then
            a.reloaded = true
            restartRoom()
            camera.setRestartScale(0)
        end
    else
        -- Wiederaufbau: 0 -> 1 mit Ease-Out.
        if not a.expandPlayed then
            a.expandPlayed = true
            audio.playRestartRebuild()
        end
        local p = math.min(1, (a.t - RESTART_COLLAPSE - RESTART_HOLD) / RESTART_EXPAND)
        camera.setRestartScale(1 - (1 - p) * (1 - p))
    end
    if a.t >= RESTART_TOTAL then
        camera.clearRestartScale()
        restartAnim = nil
    end
end

-- --- Startmenü-Controller (Phase 10.1 + 10.3) ------------------------------
-- Zeigt das Startmenü (App-Start; Rückkehr via Systemmenü „Zum Menü").
-- Entfernt die Gameplay-Systemmenüeinträge (keine Duplikate beim erneuten
-- Gameplay-Start, Punkt 45/46). Die Save-Existenz wird frisch bestimmt
-- (CONTINUE-Anzeige): nach einem NEW GAME oder einem neu erreichten Level hat
-- sich der Persistenzzustand geändert. Menu.show() setzt die Auswahl auf
-- „CONTINUE" (mit Save) bzw. „NEW GAME" (ohne Save).
local function showMainMenu()
    saveExists = Save.hasSave(maxPlayableRoom, #levels)
    menu.show(saveExists)
    appMode = "menu"
    removeGameplaySystemMenu()
    -- Anleitung auch im Startmenü verfügbar (Systemmenü ist dort offen).
    sysmenu.installHelp(function() pendingSystemAction = "anleitung" end)
    -- STARTANIMATION (AUFTRAG): sehr leiser kontinuierlicher Rise über die
    -- Ring-Zeichenzeit (kein Ton pro Segment, nicht überladen).
    audio.playMenuRise(config.menuDrawDuration)
end

-- „Zum Menü": laufenden Raum verlassen, Startmenü anzeigen. Der Mid-Room-State
-- wird NICHT gespeichert (nur highestRoom ist persistiert); kein Datastore-
-- Zugriff. Ein laufender radialer Raumübergang bzw. Center-Wipe wird
-- abgebrochen. Nutzt exakt showMainMenu (Punkt 24/29).
local function goToMainMenu()
    pendingRoomIndex = nil
    roomTransition.reset()
    wipe.reset()
    phase7.reset()
    camera.clearRevealScale()
    showMainMenu()
end

-- „CONTINUE" (Titelbildschirm): lädt den Spielstand (höchster erreichter Raum;
-- frisch = Raum 1) und startet die Starttransition: Menütext und Auswahl
-- verschwinden, NUR der dicke Ring wächst radial um den festen Mittelpunkt
-- (200,120) — KEIN Gameplay innerhalb des Rings; erst wenn die Ringkante
-- komplett aus dem Bild gewachsen ist (Endradius >= ~250 px), wechselt der
-- Modus zu "game" (nahtlos, kein harter Cut solange der Ring sichtbar ist).
-- Das Gameplay-Systemmenü wird erst nach Zoom-Ende installiert; während des
-- Zooms bleibt die Eingabe gesperrt (appMode bleibt "menu").
local function startFromTitle()
    -- Continue hinter dem Einführungsraum: das Baby wurde mitgenommen und
    -- startet als Begleiter (gemeinsamer Raumausgang ab dann Pflicht).
    babyCarried = highestRoom >= babyIntroducedAt
    startRoom(highestRoom)
    camera.init(state.room.rings.outer)
    -- Starttransition: Menütext/Auswahl verschwinden sofort, der Ring füllt
    -- sich nach innen (Fill), die Scheibe wird zum Core und das Level zoomt
    -- heraus (Reveal). Gameplay übernimmt erst nach Reveal-Ende.
    menu.beginFill()
    -- STARTANIMATION Fill: kurzer tiefer Abschlussimpuls (Scheibe entsteht).
    audio.playMenuFillImpulse()
end

-- „NEW GAME" (Titelbildschirm): Fortschritt zurücksetzen und Level 1 von
-- vorne starten. Der bisherige Levelprogress wird auf currentLevel = 1
-- zurückgesetzt und persistiert (auch ein höherer alter Save wird ersetzt),
-- das Baby-Carry-Flag wird neu gestartet. Danach exakt dieselbe Start-
-- transition wie CONTINUE (Ring füllt sich -> Core -> Level zoomt heraus).
-- Die Einleitung wird NICHT sofort gezeigt, sondern erst NACH dem kompletten
-- Level-Reveal (+ kurzer Ruhe), als Ebene über dem fertigen Level. Keine
-- Bestätigungsseite.
local function startNewGame()
    highestRoom = 1
    babyCarried = false
    saveExists = true -- ab jetzt existiert wieder ein (Level-1-)Fortschritt
    -- Tutorial: NEW GAME zeigt die kurze Einleitung und setzt alle Seen-Flags
    -- zurück (persistiert als leere Tabelle).
    tutorial.reset()
    local ok, err = Save.write(1, tutorial.flags)
    if not ok then
        print("main.startNewGame: Datastore-Write fehlgeschlagen: " .. tostring(err))
    end
    startRoom(1)
    camera.init(state.room.rings.outer)
    introPending = true
    menu.beginFill()
    -- STARTANIMATION Fill: kurzer tiefer Abschlussimpuls (Scheibe entsteht).
    audio.playMenuFillImpulse()
end

-- GLOBALE TRANSITIONSREGEL (4.1/4.2/4.3): Beim Laden des nächsten Levels im
-- Raumübergang übernehmen Player und Baby ihre TATSÄCHLICHE Position aus dem
-- vorherigen Level — Ring UND Winkel — NICHT den definierten Levelstart.
-- PLAYER_ANGLE_OUT == PLAYER_ANGLE_IN, BABY_ANGLE_OUT == BABY_ANGLE_IN; die
-- relative Player/Baby-Anordnung bleibt erhalten (Push-only: die Reihenfolge
-- bestimmt, von welcher Seite der Player das Baby schieben kann). Der Ring-
-- NAME des neuen Raums wird aus der RingNUMMER des Ausgangsraums über die
-- Ringnummern des neuen Raums abgeleitet (der radiale Übergang schiebt die
-- Ringe eine Stufe nach außen: alter Innenring = neuer Außenring usw.).
-- "center" (Kernbrücken-Abschluss am Mittelpunkt) hat keinen Ring — dann
-- bleibt der Levelstart-Ring erhalten, nur der Winkel wird übernommen.
-- Diese Übernahme gilt NUR für Room-Transitionen; NEW GAME / CONTINUE /
-- Raum-Neustart nutzen den normalen definierten Levelstart (startRoom ohne
-- Übergang). Der neue Raum wird um diesen tatsächlichen Entry herum aufgebaut.
local function applyTransitionPosition()
    local pFrom = roomTransition.playerFrom
    if pFrom then
        local name = roomTransition.ringNameForRoom(pFrom.ring, state.room)
        if name then
            state.player.ring = name
        end
        state.player.angle = pFrom.angle
    end
    local bFrom = roomTransition.babyFrom
    if state.baby and bFrom then
        local name = roomTransition.ringNameForRoom(bFrom.ring, state.room)
        if name then
            state.baby.ring = name
        end
        state.baby.angle = bFrom.angle
    end
end

-- Druckplatten-Audio (EDGE-Trigger): vergleicht die tatsächliche
-- Platten-Belegung (state.platePressed) mit dem zuletzt gemeldeten Stand und
-- meldet NUR Übergänge an audio.notePlateTransitions (kein Sound pro Frame).
local function syncPlateAudio()
    local nowPressed = state.platePressed or {}
    local changes = {}
    for id, pressed in pairs(nowPressed) do
        local before = prevPlatePressed and prevPlatePressed[id]
        if before ~= pressed then
            changes[#changes + 1] = { id = id, on = pressed }
        end
    end
    -- Platten, die im vorherigen Frame gedrückt waren und es jetzt nicht mehr
    -- sind (IDs, die aus nowPressed verschwunden sind) ebenfalls melden.
    if prevPlatePressed then
        for id, pressed in pairs(prevPlatePressed) do
            if pressed and not nowPressed[id] then
                changes[#changes + 1] = { id = id, on = false }
            end
        end
    end
    if #changes > 0 then
        audio.notePlateTransitions(changes)
    end
    prevPlatePressed = nowPressed
end

-- Gameplay-Update eines Raum-Frames.
-- Verbindliche Reihenfolge:
--   1) B-Restart (Press-Edge; nur bei entsperrtem Gameplay — ein Restart-
--      Frame macht keine Bewegung/A)
--   2) Bewegung (Player -> Room.movePlayer)
--   3) A-Aktion (nach der Bewegung, an der tatsächlich erreichten Position)
local function updateRoom()
    -- Level-Restart-Animation (B): während des Kollaps/Wiederaufbaus ist die
    -- gesamte Eingabe gesperrt. Erst nach Abschluss wird Gameplay freigegeben.
    if restartAnim ~= nil then
        updateRestartAnim(FRAME_DT)
        return
    end

    -- Finaler Raum-7-Moment (Pass 2): kurzer Stillstand vor dem Outro. Alle
    -- Eingaben gesperrt (auch B); die Welt steht (Ghost-Drift eingefroren).
    -- Danach startet das Outro genau einmal.
    if finalHoldFrames ~= nil then
        finalHoldFrames = finalHoldFrames - 1
        if finalHoldFrames <= 0 then
            finalHoldFrames = nil
            render.endFinalMoment()
            startOutro()
        end
        return
    end

    -- Kurze Ruhe NACH dem Level-Reveal (Start vom Titel oder Raumübergang):
    -- Gameplay gesperrt, die fertige Levelansicht bleibt sichtbar (kein
    -- Zoomen, kein Neuladen). Danach: die Intro-/Anleitungs-Screens sind
    -- ENTFERNT (Auftrag) — bei NEW GAME startet stattdessen die ROOM-Anzeige
    -- für Level 1 („ROOM 1 / ROOM 10" auf weiß, ~3 s, dann direkter Cut ins
    -- fertige Level 1), bei CONTINUE gar keine Intro-/ROOM-Anzeige. Die
    -- kontextbezogenen Element-Tutorials IN den Leveln bleiben erhalten und
    -- kommen IMMER erst nach dem komplett fertigen Level-Reveal.
    if revealSettle > 0 then
        revealSettle = revealSettle - FRAME_DT
        if revealSettle <= 0 then
            revealSettle = 0
            if introPending then
                introPending = false
                wipe.startRoomDisplay(1)
            end
        end
        return
    end

    -- Radialer Raumwechsel: während der Kamera-Transition ist die gesamte
    -- Gameplay-Eingabe gesperrt (Kurbel, D-Pad, A, B/Undo, DockAssist).
    -- Nur die Kamera wird weitergeschaltet; Rendering und Timer laufen weiter
    -- (drawScene/updateTimers sind unabhängig von updateRoom). B löst während
    -- des Locks nichts aus (B-Taste-Rework Teil 12).
    --
    -- Der neue Raum wird NICHT sofort geladen: am Reveal-Punkt (alte Objekte
    -- sind aufgelöst, nur Ringe/History bleiben) lädt pendingRoomIndex den
    -- nächsten Raum genau EINMAL (startRoom); die neuen Puzzleobjekte bauen
    -- sich ab dann gestaffelt auf. Am Ende der Transition wird der Übergang
    -- beendet und die Eingabe im selben Frame freigegeben.
    -- LEVEL-7-SPEZIALÜBERGANG (Ende der Lernphase -> Phase 2): der Kern
    -- pulsiert dreimal, kollabiert zu einem winzigen Punkt, explodiert
    -- geometrisch (Fragmente fliegen aus dem Bild), dann nur Dunkelheit — in
    -- dieser Phase wird der neue Raum (Phase 2) verdeckt geladen
    -- (phase7.update liefert "load") — und aus einem kleinen Kern baut sich
    -- die neue Spielwelt auf (Camera.revealScale skaliert alle Radien).
    -- Player/Baby kommen am Ende gemeinsam radial aus dem Kern heraus und
    -- landen auf der Ringbahn. Sofort danach Gameplay (keine Tutorials, keine
    -- zusätzliche Ruhe). Währenddessen ist die gesamte Gameplay-Eingabe
    -- gesperrt (Kurbel, D-Pad, A, B, DockAssist).
    if phase7.isActive() then
        local event = phase7.update(FRAME_DT)
        local p7phase = phase7.phase
        if event == "load" then
            -- Dunkle Phase: den neuen Raum KOMPLETT verdeckt laden — kein
            -- Teleport/Respawn/Geometry-Snap sichtbar.
            currentRoomIndex = pendingRoomIndex
            pendingRoomIndex = nil
            startRoom(currentRoomIndex)
            -- Startposition des neuen Levels = tatsächliche Position aus dem
            -- vorherigen Level (Winkel; Ring = Levelstart-Ring bei "center").
            applyTransitionPosition()
            -- Kamera auf den neuen Außenring stabil setzen (kein Ring-Morph;
            -- der Wiederaufbau skaliert über revealScale).
            camera.init(state.room.rings.outer)
        elseif event == "done" then
            phase7.reset()
            camera.clearRevealScale()
        end
        -- Audio (EDGE-Trigger): Phasenwechsel melden — 3 Pulse, Kollaps,
        -- Explosion, neuer Kern (kein Sound pro Frame).
        if p7phase ~= nil and p7phase ~= lastP7Phase then
            lastP7Phase = p7phase
            audio.notePhase7Phase(p7phase, currentRoomIndex)
            -- LEVELÜBERGANG-WOOSH (ROOM 7 -> 8): auch beim Spezialübergang
            -- muss der Wechsel eindeutig hörbar sein. Der Woosh startet beim
            -- WIEDERAUFBAU der neuen Phase — nach der Explosion, kein Stapeln
            -- mit dem Explosions-Sound.
            if p7phase == "rebuild" then
                audio.playTransitionWoosh()
            end
        end
        if not phase7.isActive() then
            lastP7Phase = nil
        end
        -- Wiederaufbau: Kamera-Skala jeden Frame an den Core-Wachstum anpassen
        -- (die neue Welt baut sich aus dem kleinen Kern heraus auf).
        if phase7.isActive() and phase7.phase == "rebuild" then
            camera.setRevealScale(phase7.revealScale())
        end
        render.noteShutterBlocked(false)
        render.noteBabyBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    -- Center-Wipe (Raumwechsel): der gefüllte Mittelpunkt wächst über den
    -- Bildschirm (alte Welt schließt sich), der neue Raum wird verdeckt
    -- geladen, dann schrumpft der Kreis und gibt das fertige neue Level frei
    -- (Iris-/Maskenblende). Player/Baby kommen am Ende gemeinsam aus dem
    -- Mittelpunkt heraus. Währenddessen ist die gesamte Gameplay-Eingabe
    -- gesperrt (Kurbel, D-Pad, A, B, DockAssist).
    if wipe.isActive() then
        local event = wipe.update(FRAME_DT)
        if event == "reload" then
            -- Vollständig bedeckt: den neuen Raum VERDECKT laden — kein
            -- Teleport/Respawn/Geometry-Snap sichtbar. Die neue Welt steht
            -- danach bereits an ihren FINALEN Positionen; Player/Baby stehen
            -- an ihren korrekten Startpositionen (startRoom). KEINE
            -- applyTransitionPosition (die würde alte Figurenwinkel anwenden)
            -- und KEINE Exit-Animation — der direkte Cut gibt den fertigen
            -- Raum einfach frei.
            currentRoomIndex = pendingRoomIndex
            pendingRoomIndex = nil
            startRoom(currentRoomIndex)
            -- Kamera auf den neuen Außenring stabil setzen (keine Ring-Morph-
            -- Transition; das Level rendert direkt in Normalgröße).
            camera.init(state.room.rings.outer)
            -- MIXING (AUFTRAG): während der ROOM-X-/ROOM-10-Anzeige komplette
            -- Ruhe (kein Kernpuls, keine Klicks); danach startet der Puls des
            -- neuen Raums nach kurzer Pause automatisch wieder.
            audio.setCoreHold(config.roomWipeRoomHold + config.roomTransTutorialSettle)
        elseif event == "done" then
            wipe.reset()
            -- Level 2+: nach dem KOMPLETT fertigen Raumübergang (Player/Baby
            -- sauber am Start) bleibt das neue Level ca. 0.25 s vollständig
            -- sichtbar, erst dann greifen Mechanik-Fokus/Hinweise (Punkt 10).
            revealSettle = config.roomTransTutorialSettle
        end
        render.noteShutterBlocked(false)
        render.noteBabyBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    if roomComplete then
        -- Nach Raumabschluss: Bewegung, A und B bleiben gesperrt.
        return
    end

    -- Brückentransit: während der radialen Überquerung wird keine
    -- Gameplay-Eingabe angenommen (Kurbel, D-Pad, A, B/Undo). Eine laufende
    -- Andockhilfe wird dabei verworfen. Das Rendering läuft im Frame weiter
    -- (drawScene ist davon abhängig). Ein gemeinsamer Player+Baby-Transit
    -- löst beim Abschluss einen Landing-Impuls aus (rein visuell).
    if bridge.isCrossing() then
        room.resetDockAssist()
        -- ONE-USE BRIDGE: vor dem Update merken, ob der Transit über eine
        -- Einmal-Brücke lief (Collapse erst NACH erfolgreichem Transit).
        local btBefore = bridge.getTransit()
        local wasOneShot = btBefore ~= nil and btBefore.oneShot == true
        local completed, wasShared, babyLanded, wasCenter = bridge.update(FRAME_DT)
        if completed then
            -- Ringwechsel: alle Traversierungen des alten Rings sind gegenstandslos
            -- (Release-Fix 1) — keine halbe Schalterdurchquerung über die Ring-
            -- grenze hinweg.
            room.resetSwitchTraversal()
            room.syncPhysicalShutters()
            -- ONE-USE BRIDGE (AUFTRAG): nach dem abgeschlossenen Transit
            -- kollabiert sie — eigener kurzer Collapse-Sound, nicht beim Start.
            if wasOneShot then
                audio.playOneUseCollapse()
            end
            -- Gemeinsamer Player+Baby-Transit: der Player landet ruhig
            -- (subtiler als das Baby). Rein visuell.
            if wasShared then
                render.notePlayerLanding()
            end
            -- Kernbrücke (Gate): der Levelabschluss erfolgt ERST NACH dem
            -- Transit/Landing am Mittelpunkt — nicht beim Betreten der
            -- Brücke. Der Player ist am Kernrand gelandet (rein visuell);
            -- der tiefe Gate-Puls markiert die Ankunft und klingt in den
            -- Raumwechsel über. handleConnectionResult startet danach die
            -- Room-Transition (Player/Baby-Startposition = Kernrand).
            if wasCenter then
                render.notePlayerAtCenter()
                local gid = state.room.gate and state.room.gate.id or nil
                audio.playGateTransition()
                handleConnectionResult({ used = true, kind = "gate", id = gid, roomComplete = true, crossing = false }, true)
            end
        end
        -- Baby-Landing (gemeinsamer Transit): das Baby erreicht den Zielring
        -- früher als der Player — der Settling-/Blick-zurück-Impuls startet
        -- dann schon in DIESEM Frame (Baby landet zuerst, Player kurz danach).
        if babyLanded then
            render.noteBabyLanding()
        end
        -- Druckplatten-Audio: Transit-Landung kann eine Platte drücken/lösen.
        syncPlateAudio()
        render.noteShutterBlocked(false)
        render.noteBabyBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    -- Baby-Brückentransit (generisch, Raum 2): wie beim Spielertransit wird
    -- während der kurzen radialen Bewegung keine Gameplay-Eingabe angenommen
    -- (Kurbel, D-Pad, A, B/Undo). Das Rendering läuft im Frame weiter. Beim
    -- Abschluss startet ein kleiner Landing-Impuls (rein visuell).
    if baby.isCrossing() then
        room.resetDockAssist()
        local completed = baby.update(FRAME_DT)
        if completed then
            render.noteBabyLanding()
        end
        -- Druckplatten-Audio: Baby-Landung kann eine Platte drücken/lösen.
        syncPlateAudio()
        render.noteShutterBlocked(false)
        render.noteBabyBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    -- Tutorial: Mechanik-Fokus (neues Objekt) pausiert das Gameplay; nur A
    -- schließt ihn. Solange aktiv werden keine Spielereingaben verarbeitet.
    if tutorial.focusActive() then
        tutorial.updateFocus(FRAME_DT)
        if playdate.buttonJustPressed(playdate.kButtonA) then
            tutorial.dismissFocus()
            -- Tutorial-Infoleiste schließt: kleiner neutraler Tick (A = continue).
            audio.playTutorialContinue()
        end
        return
    end
    -- Tutorial: neues Element wird NICHT beim Levelstart eingeblendet — die
    -- Tutorial-BREMSE (siehe Bewegungsblock) merkt es als pending und stoppt
    -- den Player beim ersten Kennenlernen weich VOR dem Element (kleine
    -- Lücke); danach startet der Fokus (Highlight + untere Infoleiste).
    tutorial.maybeStartFocus(currentRoomIndex)
    -- Level-1-Kontext-Hinweise (Kurbel; unterer Hinweis, kein Text in der
    -- Bildmitte mehr, keine „Bringt euch beide zur Bruecke.“-Meldung).
    -- Wurde ein Hinweis neu erzeugt, klingt ein dezent hoher Tick (EDGE).
    if tutorial.checkLevelHints(currentRoomIndex) then
        audio.playTutorialAppear()
    end

    -- B = aktuelles Level neu starten (einfach, ohne Rückgängig). Kein harter
    -- Schnitt: eine kurze Kollaps-/Wiederaufbau-Animation läuft. Nur hier
    -- erreichbar, wenn KEIN Input-Lock greift (Camera/Bridge/roomComplete sind
    -- oben bereits zurückgekehrt). Eine laufende Andockhilfe wird dabei
    -- verworfen.
    if playdate.buttonJustPressed(playdate.kButtonB) then
        startRestartAnim()
        return
    end

    -- 2) Bewegung / Andockhilfe. Player.getDesiredDelta ist die einzige
    --    Kurbelabfrage. Bewegungsinput gewinnt immer: eine laufende Assistenz
    --    wird abgebrochen und nur normal bewegt (kein Assistenzdelta zusätzlich).
    --    Die Blickrichtung (Facing) folgt der tatsächlich zurückgelegten
    --    Bewegung (actualDelta), nicht der gewünschten. UI-Reaktionen (Widen/
    --    Squint) entstehen ausschließlich aus dem echten movePlayer-Resultat.
    local moveResult = nil
    local wantedDelta = player.getDesiredDelta(FRAME_DT)
    if wantedDelta ~= 0 then
        -- KEINE Tutorial-Bremse mehr (AUFTRAG „natuerliches Kurbelgefuehl"):
        -- die Steuerung ist völlig normal; Tutorials starten rein über
        -- Proximity-Zonen, ohne Bewegungskorrektur.
        -- Tutorial: erster Ziehversuch (Player in Kontakt, bewegt sich vom
        -- Baby weg) -> einmaliger Hinweis (Ton nur bei NEU gezeigtem Hinweis).
        if tutorial.onPullAttempt(currentRoomIndex, wantedDelta) then
            audio.playTutorialAppear()
        end
        room.resetDockAssist()
        room.resetPlateSnap()
        local actualDelta
        actualDelta, moveResult = room.movePlayer(wantedDelta)
        if actualDelta ~= 0 then
            render.notePlayerMovement(actualDelta)
            -- Tutorial: erste echte Bewegung blendet den Kurbel-Hinweis aus.
            tutorial.onPlayerMoved(currentRoomIndex)
            -- Audio: Bewegungsklick nur bei echter Ringstrecke (actualDelta);
            -- Bridge-Transit/Camera/DockAssist melden hier nichts.
            audio.noteRingMovement(actualDelta)
        end
        -- Rein visuelle UI-Meldungen (keine Gameplaywahrheit, kein State-Mutate):
        -- mindestens ein Schalter tatsächlich ausgelöst -> Augenweiten + Snap;
        -- echter blockierter Anstoß -> Zusammenkneifen + Aufprall (Flanke).
        if moveResult.switchChanges > 0 then
            render.noteSwitchContact()
            -- Pass 2: A/B leicht unterschiedlich (actualDelta>0 = CW -> A,
            -- actualDelta<0 = CCW -> B); man hört die Umschaltrichtung.
            if moveResult.switchOneShot then
                -- EINMAL-Schalter: markanterer Doppel-Snap (zwei kurze Töne).
                audio.playOneShotSnap()
            else
                audio.playSwitchSnap(actualDelta > 0)
            end
        end
        -- Brücke ausfahren/Retract: für jede echte Elementänderung einer
        -- normalen Brücke false->true (freie Brücken und das Gate zählen
        -- nicht). true->false (Retract, z.B. durch Einschalter) löst einen
        -- kurzen, tiefer abfallenden Retract-Ton aus.
        if moveResult.elementChanges then
            for _, ce in ipairs(moveResult.elementChanges) do
                if ce.to == true and ce.from ~= true then
                    for _, b in ipairs(state.room.bridges) do
                        if b.id == ce.id and b.free ~= true then
                            audio.playBridgeExtend()
                        end
                    end
                elseif ce.to == false and ce.from ~= false then
                    for _, b in ipairs(state.room.bridges) do
                        if b.id == ce.id and b.free ~= true then
                            audio.playBridgeRetract()
                        end
                    end
                end
            end
        end
        render.noteShutterBlocked(moveResult.blocked)
        audio.noteShutterBlocked(moveResult.blocked)
        -- Pass 2: Blenden-Körperton beim tatsächlichen Öffnen/Schließen
        -- (Schließen tiefer/härter, Öffnen etwas höher und leiser).
        audio.noteShutterTransitions(moveResult.shutterTransitions)
        -- Baby-Reaktionen (generisch, rein visuell): beim echten Schieben
        -- leichte Kompression in Fahrtrichtung + Innenkreis-Versatz (Baby) und
        -- minimaler Druck + fokussierter Blick (Player). Wird das Baby selbst
        -- gegen eine Blockade gedrückt (geschlossene Blende), startet eine
        -- sehr kurze Baby-Blocked-Reaktion (Flanke, kein Retrigger). Kein
        -- Gameplay-Effekt.
        if moveResult.babyMoved then
            render.noteBabyPush(actualDelta)
            render.notePlayerPushContact()
        end
        render.noteBabyBlocked(moveResult.blocked and Baby.isContactingPlayer())
        -- Baby-Sounds (Begleiter): weicher Push-Ton bei Kontaktaufnahme
        -- (Flanke, nicht pro Frame), dumpfer Impact-Ton bei blockiertem Schub
        -- an das Baby (Baby gegen Grenze/Shutter, Spieler drückt weiter).
        audio.noteBabyPush(moveResult.babyMoved == true)
        audio.noteBabyImpact(moveResult.blocked and Baby.isContactingPlayer())
    else
        room.updateDockAssist()
        -- Druckplatten-Magnet („leicht magnetisch“): nur im bewegungsfreien
        -- Frame — Player/Baby rasten sanft auf die exakte Plattenmitte ein,
        -- wenn sie sehr nah dranstehen (Steuerung wird nie weggenommen).
        room.updatePlateSnap()
        -- Kein Bewegungsversuch in diesem Frame: keine Kollision, kein
        -- Baby-Kontakt (Flanken-Latches zurücksetzen).
        render.noteShutterBlocked(false)
        render.noteBabyBlocked(false)
        audio.noteShutterBlocked(false)
        audio.noteBabyPush(false)
        audio.noteBabyImpact(false)
    end

    -- Druckplatten-Audio: nach jedem Bewegungsframe die Belegung abgleichen
    -- (ON/OFF-Edge nur bei tatsächlichem Wechsel).
    syncPlateAudio()

    -- Tutorial-Trigger (AUFTRAG „frueh, ohne Bewegungskorrektur"): neue
    -- Elemente werden per Proximity-Zone erklärt, sobald der Player in ihre
    -- Einführungszone kommt (kurz VOR dem Element). KEINE Brems-/Snap-/Kamera-
    -- Eingriffe — die Steuerung bleibt völlig normal. Startet der Fokus
    -- (Highlight + untere Infoleiste), pausiert das Gameplay bis A und der
    -- Player bleibt exakt an seiner Position (kein Versatz, kein Rücksetzen).
    if tutorial.checkProximityFocus(currentRoomIndex) then
        -- Neues Element in der Nähe: dezent hoher Erscheinen-Tick.
        audio.playTutorialAppear()
        return
    end
    if tutorial.checkElementTriggers(currentRoomIndex, moveResult) then
        -- Neues Element per Trigger erreicht: dezent hoher Erscheinen-Tick.
        audio.playTutorialAppear()
        return
    end

    -- 3) A-Aktion (Just-Pressed, damit ein gehaltenes A nicht frameweise
    --    zwischen den Ringen hin- und herschaltet). Die Andockhilfe läuft VOR
    --    der A-Prüfung, sodass der letzte Assistenzframe + A direkt eine aktive
    --    Brücke benutzen kann. Die Progressionsentscheidung (nächsten Raum laden
    --    oder abgeschlossen) liegt zentral in handleConnectionResult; der Frame
    --    endet danach ohne weitere Movement-/Assistenz-/Connection-Verarbeitung.
    if playdate.buttonJustPressed(playdate.kButtonA) then
        local result = room.tryUseConnection()
        -- Brückenwechsel-Sound beim tatsächlichen Transferstart (solo ODER
        -- gemeinsam mit Baby; auch die Kernbrücke/Gate ist eine normale
        -- Brückenüberquerung). Nicht beim bloßen Andocken — tryUseConnection
        -- startet den Transit erst, wenn die Brücke tatsächlich genutzt wird.
        -- Der tiefe Gate-Puls erklingt erst bei der ANKUNFT am Mittelpunkt
        -- (nach dem Transit/Landing, siehe Brücken-Crossing-Block).
        if result.used and result.crossing then
            audio.playBridgeCrossing()
        end
        -- Baby-Schicht-Sound beim GEMEINSAMEN Transfer (Player+Baby über eine
        -- Brücke): heller Klingelton über dem mechanischen Zip — das Baby
        -- „geht mit“. Nur bei sharedBridge. Zusätzlich startet der Player-
        -- Transit-Fokus (Auge: kurze Fokus-Reaktion am Transitbeginn).
        if result.used and result.kind == "sharedBridge" then
            render.notePlayerTransitStart()
            audio.playBabyBridgeLayer()
        end
        handleConnectionResult(result)
    end
end

local function updateScene()
    if appMode == "outro" then
        -- Outro läuft automatisch; alle Gameplay-Eingaben sind gesperrt (Crank,
        -- D-Pad, A, B-Tap, B-Hold, DockAssist; Punkt 15). Kein B-Hold-Restart im
        -- Outro (Punkt 69). Am Ende -> Schnitt zum Menü (Punkt 32/33).
        if transition.update(FRAME_DT) then
            goToMainMenu()
        end
    elseif currentScene == "room" then
        updateRoom()
    end
end

-- Zeichnet den Titelbildschirm:
--   normal: komplette Titel-UI (dicker Ring + Menüoptionen IM Kreis).
--   Fill  : NUR die sich nach innen füllende Scheibe (Menütext weg, Ring
--           bleibt exakt bei (200,120), Außenkante ~90 px unverändert).
--   Reveal: das ECHTE Level wird aus dem Core herausgezoomt dargestellt
--           (Camera.revealScale skaliert alle Radien um 200,120) — die
--           gefüllte Menü-Scheibe geht nahtlos in den Level-Core über, die
--           Ringgeometrie kommt von den Bildschirmrändern, bis Normalgröße
--           erreicht ist. KEIN Gameplay-Eingriff währenddessen.
local function drawTitle()
    if menu.isFillPhase() then
        gfx.clear(gfx.kColorBlack)
        menu.drawFill()
    elseif menu.isRevealPhase() then
        render.drawRoom(roomComplete, currentRoomIndex)
    else
        Menu.draw()
    end
end

local function drawScene()
    if appMode == "outro" then
        transition.draw()
    elseif appMode == "menu" then
        -- Schnitt zum Titel: Menü direkt im Outro-Finish-Frame zeichnen (kein
        -- schwarzer Zwischenframe; Punkt 33).
        drawTitle()
    elseif currentScene == "room" then
        render.drawRoom(roomComplete, currentRoomIndex)
        -- Tutorial-Overlays (Mechanik-Fokus / Kontext-Hinweis) über der Szene.
        tutorial.draw()
    end
end

-- Spielstart: Startmenü anzeigen. Noch KEIN Gameplay, noch kein Raum geladen.
-- Audio-Synths werden einmalig initialisiert (keine Samples, reine Synth);
-- der Kernpuls startet erst nach Spielstart via Audio.resetRoom.
audio.init()
-- Fortschritt genau EINMAL beim App-Start laden (vor dem Menü, damit
-- CONTINUE den korrekten Fortsetzungs-Raum kennt). Kein Datastore-Zugriff pro
-- Frame.
loadProgress()
menu.init()
-- Systemmenu-Zugriff initialisieren (eigene Einträge leeren); die zwei
-- Gameplay-Einträge werden erst beim Spielstart registriert.
sysmenu.init()
-- Produktionsstart: Titelbildschirm anzeigen. Gameplay beginnt erst nach
-- Bestätigung von CONTINUE oder NEW GAME (Zoom ins Spiel).
showMainMenu()

function playdate.update()
    playdate.timer.updateTimers()

    -- Ausstehende Systemmenü-Aktion atomar verarbeiten (Punkt 40/41): VOR jeder
    -- neuen Eingabe. Danach wird in DIESEM Frame keine Gameplay-Eingabe mehr
    -- verarbeitet (kein alter Crank/Button bewegt den frisch gestarteten Raum),
    -- sondern nur gerendert. Die Aktion wird genau einmal konsumiert.
    if pendingSystemAction ~= nil then
        local action = pendingSystemAction
        pendingSystemAction = nil
        if action == "restartRoom" then
            restartRoom()
            gfx.clear(gfx.kColorBlack)
            render.update(FRAME_DT, roomComplete)
            audio.update(FRAME_DT)
            drawScene()
            return
        elseif action == "mainMenu" then
            goToMainMenu()
            Menu.draw()
            return
        elseif action == "anleitung" then
            -- Systemmenü „ANLEITUNG“: Vollbild-Hilfe sofort zeichnen; die
            -- Folgeframes laufen durch den Hilfe-Zweig unten.
            tutorial.openHelp()
            gfx.clear(gfx.kColorBlack)
            render.update(FRAME_DT, roomComplete)
            audio.update(FRAME_DT)
            tutorial.drawHelp()
            return
        end
    end

    -- Anleitung (Systemmenü „ANLEITUNG“): Vollbild-Hilfe; B oder A schließt
    -- zurück zum Spiel bzw. Menü. Solange aktiv ist die Eingabe gesperrt.
    if tutorial.isHelpActive() then
        gfx.clear(gfx.kColorBlack)
        render.update(FRAME_DT, roomComplete)
        audio.update(FRAME_DT)
        if playdate.buttonJustPressed(playdate.kButtonB)
            or playdate.buttonJustPressed(playdate.kButtonA) then
            tutorial.closeHelp()
        end
        tutorial.drawHelp()
        return
    end

    -- NEW-GAME-Einleitung (nur nach NEW GAME): zwei kurze Tafeln. Sie startet
    -- ERST NACH dem kompletten Level-Reveal + kurzer Ruhe (revealSettle in
    -- updateRoom) — also IMMER als Ebene über dem bereits fertig aufgebauten
    -- Level, nie als Unterbrechung des Startscreen-/Reveal-Ablaufs (Punkt 8/9).
    -- A = weiter, B = eine Seite zurück.
    if tutorial.isIntroActive() then
        gfx.clear(gfx.kColorBlack)
        render.update(FRAME_DT, roomComplete)
        audio.update(FRAME_DT)
        tutorial.updateIntro(FRAME_DT)
        if playdate.buttonJustPressed(playdate.kButtonA) then
            tutorial.advanceIntro()
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            tutorial.backIntro()
        end
        tutorial.drawIntro()
        return
    end

    -- Startmenü (Titelbildschirm): normal nur Titel-Update + Titelzeichnung.
    -- Bestätigt der Spieler START, lädt startFromTitle/startNewGame den Raum
    -- und beginnt die Starttransition (Punkt 2-7):
    --   Fill   (0.5-0.55 s): Menütext/Auswahl verschwinden sofort, der Ring
    --          bleibt exakt bei (200,120) und füllt sich nach innen -> Scheibe.
    --   Reveal (0.7-0.8 s): die Scheibe IST der Level-Core (kein Schnitt);
    --          das Level zoomt um 200,120 aus dem Mittelpunkt heraus auf
    --          Normalgröße. Kein Gameplay vorher (keine Spielerbewegung,
    --          kein Sweep, keine A/B-Aktionen, kein DockAssist).
    -- Danach wechselt appMode zu "game" + revealSettle (kurze Ruhe).
    if appMode == "menu" then
        if menu.isFillPhase() then
            -- Fill: Weltzeit/Audio weiterlaufen lassen (Blink, Kernpuls),
            -- Eingabe gesperrt; am Ende startet der Reveal.
            render.update(FRAME_DT, roomComplete)
            audio.update(FRAME_DT)
            if menu.updateFill(FRAME_DT) then
                -- Reveal-Startskala: Core = gefüllte Menü-Scheibe (kein
                -- Sprung, kein Neuzeichnen — die Scheibe geht in den Core
                -- über). Die Ringgeometrie liegt anfangs außerhalb des
                -- Bildschirms und fährt beim Herauszoomen ein.
                local s0 = config.menuTitleOuterRadius / Render.coreBaseRadius(currentRoomIndex)
                camera.setRevealScale(s0)
                menu.beginReveal(s0)
            end
            drawTitle()
            return
        end
        if menu.isRevealPhase() then
            -- Reveal: das ECHTE Level (skaliert) wird gezeichnet; Eingabe
            -- gesperrt. Die Kamera-Skala folgt jedem Frame dem Reveal-
            -- Fortschritt (s0 -> 1). Am Ende: Normalgröße, kurze Ruhe, dann
            -- Gameplay.
            render.update(FRAME_DT, roomComplete)
            audio.update(FRAME_DT)
            local revealDone = menu.updateReveal(FRAME_DT)
            camera.setRevealScale(menu.getRevealScale())
            if revealDone then
                camera.clearRevealScale()
                appMode = "game"
                installGameplaySystemMenu()
                revealSettle = config.menuRevealSettle
            end
            drawTitle()
            return
        end
        local selBefore = Menu.selection
        local action = Menu.update(FRAME_DT)
        -- MENU MOVE (EDGE-Trigger): nur wenn sich die gewählte Option wirklich
        -- ändert, nicht bei jeder Crank-/Frame-Bewegung.
        if Menu.selection ~= selBefore then
            audio.playMenuMove()
        end
        -- MENU CONFIRM: kurzer Sweep bei A-Bestätigung (danach Startanimation).
        if action ~= nil then
            audio.playMenuConfirm()
        end
        if action == "continue" then
            -- CONTINUE: zuletzt gespeichertes Level fortsetzen (gleiche
            -- Starttransition wie NEW GAME).
            startFromTitle()
        elseif action == "newgame" then
            -- NEW GAME: Fortschritt zurücksetzen, Level 1 von vorne starten.
            startNewGame()
        elseif action == "exit" then
            -- EXIT: sauberes Verlassen des Spiels. Offizielle Playdate-API:
            -- playdate.simulator.exit() beendet den Playdate-Simulator (in
            -- der SDK-Referenz dokumentiert: "Quits the Playdate Simulator
            -- app."). Auf dem physischen Gerät ist diese Simulator-Funktion
            -- nicht verfügbar (playdate.isSimulator() == false) — dort gibt es
            -- keinen programmatischen App-Exit; das System/der Launcher
            -- übernimmt die Rückkehr. Kein Crash, kein Fehler, kein Fake-Exit.
            if playdate.isSimulator and playdate.isSimulator()
                and playdate.simulator and playdate.simulator.exit then
                playdate.simulator.exit()
            end
        end
        if appMode == "menu" then
            drawTitle()
        end
        return
    end

    gfx.clear(gfx.kColorBlack)

    -- Rein visuelle Zeit fortschreiben (Kernpulsation, Preview, Blink-Planung),
    -- auch während Camera-Transition; Blink startet bei roomComplete nicht neu.
    render.update(FRAME_DT, roomComplete)
    -- Tutorial: Hinweis-Zeit (Ein-/Ausblenden).
    tutorial.update(FRAME_DT)
    -- Audio: Kernpuls (DER PULS IST DIE MUSIK), zeitbasiert.
    audio.update(FRAME_DT)

    updateScene()
    drawScene()

    -- Tutorial-Flags persistieren, falls in diesem Frame ein neuer Hinweis als
    -- „gesehen“ markiert wurde (harmlos bei Schreibfehlern).
    if tutorial.consumeChanged() then
        Save.write(highestRoom, tutorial.flags)
    end
end