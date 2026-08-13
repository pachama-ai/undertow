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
import "ui/menu"
import "ui/transition"

-- Lokale Referenzen auf die globalen Module (keine Import-Rückgabewerte).
local config <const> = Config
local state <const> = State
local undo <const> = Undo
local audio <const> = Audio
local save <const> = Save
local sysmenu <const> = Sysmenu
local player <const> = Player
local baby <const> = Baby
local room <const> = Room
local levels <const> = Levels
local render <const> = Render
local camera <const> = Camera
local menu <const> = Menu
local bridge <const> = Bridge
local transition <const> = Transition

local gfx <const> = playdate.graphics

-- Fester Frame-Step aus der konfigurierten Refreshrate.
local FRAME_DT <const> = 1 / config.refreshRate

playdate.display.setRefreshRate(config.refreshRate)

-- Szenenzustand: für diesen Vertical Slice ausschließlich "room".
local currentScene = "room"

-- App-Zustand: "menu" (Startmenü) | "game" (Gameplay) | "outro" (Abschluss-
-- phase B: Präsentation nach dem finalen Gate). Kleine App-Ebene, keine
-- State-Machine-Bibliothek. Beim App-Start ist das Menü aktiv; Gameplay beginnt
-- erst nach Auswahl von „Weiter" oder „Von vorn".
local appMode = "menu"

-- Minimaler lokaler Raumcontrollerzustand (kein Levelmanager).
local currentRoomIndex = 1
local roomComplete = false
-- Finaler Raum-6-Moment (Pass 2): Frame-Zähler für den kurzen Stillstand vor
-- dem Outro (nil = nicht aktiv). Währenddessen ist die Eingabe gesperrt und
-- die Welt steht (Ghost-Drift eingefroren).
local finalHoldFrames = nil

-- Vom Playdate-Systemmenü angefordete Aktion (Phase 10.3). Die Callbacks
-- registrieren hier NUR einen Wunsch ("restartRoom" | "mainMenu"); verarbeitet
-- wird die Aktion einmalig am Anfang des nächsten playdate.update() (atomar,
-- ohne alten Frameinput). nil = keine ausstehende Aktion.
local pendingSystemAction = nil

-- Abschlussphase A: Maximal spielbarer Raum wird aus den tatsächlichen
-- Leveldaten abgeleitet (alle vorhandenen Räume sind spielbar). Der frühere
-- temporäre Phasen-Gate-Wert MAX_PLAYABLE_ROOM = 3 ist entfernt; es gibt keine
-- künstliche Begrenzung mehr (ARCHITECTURE: 6 Rätselräume / 7 Ringe).
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
-- „Von vorn" setzt es zurück; „Weiter" hinter dem Einführungsraum behält es.
local babyCarried = false

-- Session-Fortschritt (Phase 10.2): höchste in dieser Session erreichte
-- Raumnummer. Wird beim App-Start aus dem Datastore geladen (Save.load) und
-- steigt monoton; "Weiter" startet genau diesen Raum.
local highestRoom = 1

-- Lädt den Fortschritt beim App-Start (genau ein Datastore-Read). Read-only:
-- verändert keinen Gameplay-State, setzt nur den Sessionwert. Ungültige oder
-- fehlende Saves fallen auf Raum 1 zurück; zu hohe Werte werden auf den
-- höchsten spielbaren Raum geclamped.
local function loadProgress()
    highestRoom = Save.load(maxPlayableRoom, #levels)
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
    local ok, err = Save.write(highestRoom)
    if not ok then
        print("main.saveHighestRoom: Datastore-Write fehlgeschlagen: " .. tostring(err))
    end
end

-- B-Eingabe (B-Taste Rework): B verarbeitet ausschließlich die Press-Edge
-- (buttonJustPressed) als Undo — genau ein Undo pro physischem B-Drücken, kein
-- B-Hold-Restart mehr. Die Undo-Ausführung liegt in updateRoom (nach allen
-- Input-Locks). Es gibt keinen Hold-Timer, keinen Fortschrittsring und keine
-- B-Gesten-Zustandsmaschine mehr (core/bgesture.lua entfernt); Raumneustart
-- ist ausschließlich über das Playdate-Systemmenü erreichbar.

-- Initialisiert einen Raum: State.init -> Undo.clear -> Room.init.
local function startRoom(index)
    local roomData = levels[index]
    if not roomData then
        error("main.startRoom: Raum " .. tostring(index) .. " existiert nicht")
    end
    -- Ein alter Brückentransit, Baby-Transit oder eine alte Andockhilfe darf
    -- nie in einen neuen Raum weiterlaufen.
    bridge.resetTransit()
    baby.resetTransit()
    room.resetDockAssist()
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
end

-- Startet das Outro nach dem finalen Gate (Raum 6). Nur Präsentation: wechselt
-- in den Outro-Modus, startet die Transition mit der sichtbaren Room-6-Geometrie
-- und entfernt die Gameplay-Systemmenüeinträge (Punkt 16: kein „Raum neu
-- starten"/„Zum Menü" im Outro). sysmenu.removeAll() direkt (Äquivalent zu
-- removeGameplaySystemMenu, das erst später deklariert ist). B ist im Outro
-- gesperrt (updateScene ruft updateRoom dort nicht auf).
local function startOutro()
    transition.startOutro(currentRoomIndex, state.room.rings.outer, state.room.rings.inner)
    appMode = "outro"
    sysmenu.removeAll()
end

-- Zentrale Progressionsentscheidung nach einer Verbindungs-Aktion (A).
--   crossing     -> eine laufende Andockhilfe beenden
--   roomComplete -> nächsten Raum laden (falls vorhanden), sonst abgeschlossen.
-- Räume 1-5: sofort nächsten Raum initialisieren (roomComplete wird von
-- startRoom zurückgesetzt). Raum 6: kein nächster Raum (nextIndex 7 existiert
-- nicht) -> roomComplete bleibt true und das Gameplay friert sichtbar ein
-- (kein Crash, kein nil-Zugriff; das Outro folgt separat in Abschlussphase B).
local function handleConnectionResult(result)
    if result.crossing then
        room.resetDockAssist()
    end
    if result.roomComplete then
        local nextIndex = currentRoomIndex + 1
        if levels[nextIndex] ~= nil then
            -- Fortschritt persistieren (nur bei echtem neuen Höchststand) BEVOR
            -- der nächste Raum initialisiert wird: Raum 1 -> Save 2, ..., Raum 5
            -- -> Save 6. Raum 6-Completion lädt keinen Raum 7 und speichert nie
            -- einen Wert >= 7 (Save bleibt 6).
            saveHighestRoom(nextIndex)
            -- Alte Ringnummern merken, neuen Raum laden, dann Kamera-Transition
            -- starten (gemeinsamer Ring wandert nach 104, neuer Innenring fährt
            -- bei 68 ein). Keine Gameplay-State-Kopie.
            local fromOuter = state.room.rings.outer
            local fromInner = state.room.rings.inner
            currentRoomIndex = nextIndex
            startRoom(currentRoomIndex)
            -- Atmosphäre (Pass 2): kurze visuelle Ruhe (0.1 s) über den Kamera-
            -- Initial-Hold, BEVOR die Raumtransition startet (der neue Raum
            -- steht kurz komprimiert, dann fährt die Kamera ein). Progression
            -- unverändert: kein Menü, kein Startscreen zwischen den Räumen.
            camera.beginRoomTransition(fromOuter, fromInner, state.room.rings.outer, state.room.rings.inner, config.completionPause)
            -- Atmosphäre: kurzer Systemimpuls (visuell + klanglich) am Beginn
            -- des Raumwechsels. Nach startRoom, damit der Reset die Timer nicht
            -- überschreibt; rein visuell, Progression unverändert. Der Klang
            -- wird pro gelöstem Raum minimal tiefer/resonanter.
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
            audio.setCompleted()
            render.beginFinalMoment()
            audio.playRoomCompletion(currentRoomIndex)
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
    sysmenu.install(
        function() pendingSystemAction = "restartRoom" end,
        function() pendingSystemAction = "mainMenu" end)
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
-- gesetzt (kein 1,2-s-Raumwechsel, Punkt 17).
local function restartRoom()
    startRoom(currentRoomIndex)
    camera.init(state.room.rings.outer)
end

-- --- Startmenü-Controller (Phase 10.1 + 10.3) ------------------------------
-- Zeigt das Startmenü (App-Start; Rückkehr via Systemmenü „Zum Menü").
-- Entfernt die Gameplay-Systemmenüeinträge (keine Duplikate beim erneuten
-- Gameplay-Start, Punkt 45/46). Menu.show() setzt die Auswahl auf „Weiter".
local function showMainMenu()
    menu.show()
    appMode = "menu"
    removeGameplaySystemMenu()
end

-- „Zum Menü": laufenden Raum verlassen, Startmenü anzeigen. Der Mid-Room-State
-- wird NICHT gespeichert (nur highestRoom ist persistiert); kein Datastore-
-- Zugriff. Nutzt exakt showMainMenu (Punkt 24/29).
local function goToMainMenu()
    showMainMenu()
end

-- „Weiter": startet den Continue-Zielraum. Seit Phase 10.2 ist das der
-- gespeicherte höchste erreichte Raum (highestRoom, beim Boot via
-- Save.load validiert und geclamped). "Von vorn" (startNewGame) startet
-- weiterhin Raum 1. Beide Pfade nutzen denselben zentralen startRoom.
local function startContinueGame()
    menu.hide()
    -- Continue hinter dem Einführungsraum: das Baby wurde mitgenommen und
    -- startet als Begleiter (gemeinsamer Raumausgang ab dann Pflicht).
    babyCarried = highestRoom >= babyIntroducedAt
    startRoom(highestRoom)
    camera.init(state.room.rings.outer)
    appMode = "game"
    installGameplaySystemMenu()
end

-- „Von vorn": startet Raum 1 mit frischem Zustand über denselben zentralen
-- Initialisierungspfad startRoom. Kein Datastore-Löschen (existiert noch
-- nicht; kommt erst in 10.2).
local function startNewGame()
    menu.hide()
    -- Frisches Spiel: Baby ist (noch) kein Begleiter — es wird erst durch die
    -- baby-Definition des Einführungsraums eingeführt („Von vorn" setzt zurück).
    babyCarried = false
    startRoom(1)
    camera.init(state.room.rings.outer)
    appMode = "game"
    installGameplaySystemMenu()
end

-- Leitet die vom Menü gemeldete Aktion an den richtigen Controllerpfad.
-- Die Aktionen bleiben intern getrennt (kein "if action then startRoom(1)").
local function handleMenuAction(action)
    if action == "continue" then
        startContinueGame()
    elseif action == "restart" then
        startNewGame()
    end
end

-- Gameplay-Update eines Raum-Frames.
-- Verbindliche Reihenfolge:
--   1) B-Undo (Press-Edge; nur bei entsperrtem Gameplay — ein Undo-Frame
--      macht keine Bewegung/A)
--   2) Bewegung (Player -> Room.movePlayer)
--   3) A-Aktion (nach der Bewegung, an der tatsächlich erreichten Position)
local function updateRoom()
    -- Finaler Raum-6-Moment (Pass 2): kurzer Stillstand vor dem Outro. Alle
    -- Eingaben gesperrt (auch B/Undo); die Welt steht (Ghost-Drift
    -- eingefroren). Danach startet das Outro genau einmal.
    if finalHoldFrames ~= nil then
        finalHoldFrames = finalHoldFrames - 1
        if finalHoldFrames <= 0 then
            finalHoldFrames = nil
            render.endFinalMoment()
            startOutro()
        end
        return
    end

    -- Kamera-Raumwechsel: während der 1,2-s-Transition ist die gesamte
    -- Gameplay-Eingabe gesperrt (Kurbel, D-Pad, A, B/Undo, DockAssist).
    -- Nur die Kamera wird weitergeschaltet; Rendering und Timer laufen weiter
    -- (drawScene/updateTimers sind unabhängig von updateRoom). B löst während
    -- des Locks nichts aus (B-Taste-Rework Teil 12).
    if camera.isTransitioning() then
        camera.update(FRAME_DT)
        render.noteShutterBlocked(false)
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
        local completed, wasShared, babyLanded = bridge.update(FRAME_DT)
        if completed then
            -- Ringwechsel: alle Traversierungen des alten Rings sind gegenstandslos
            -- (Release-Fix 1) — keine halbe Schalterdurchquerung über die Ring-
            -- grenze hinweg.
            room.resetSwitchTraversal()
            room.syncPhysicalShutters()
            -- Gemeinsamer Player+Baby-Transit: der Player landet ruhig
            -- (subtiler als das Baby). Rein visuell.
            if wasShared then
                render.notePlayerLanding()
            end
        end
        -- Baby-Landing (gemeinsamer Transit): das Baby erreicht den Zielring
        -- früher als der Player — der Settling-/Blick-zurück-Impuls startet
        -- dann schon in DIESEM Frame (Baby landet zuerst, Player kurz danach).
        if babyLanded then
            render.noteBabyLanding()
        end
        render.noteShutterBlocked(false)
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
        render.noteShutterBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    -- 1) B-Undo (B-Taste Rework): B verarbeitet NUR die Press-Edge
    --    (buttonJustPressed) — genau ein Undo pro physischem B-Drücken, egal
    --    wie lange gehalten wird (kein Restart, kein Wiederholen pro Frame,
    --    Teile 1/11). Nur hier erreichbar, wenn KEIN Input-Lock greift
    --    (Camera/Bridge/roomComplete sind oben bereits zurückgekehrt) — B
    --    während eines Locks erzeugt also kein Undo (Teil 12). Eine laufende
    --    Andockhilfe wird dabei verworfen. Undo startet keine Reaktion;
    --    Player-Animation neutral.
    if playdate.buttonJustPressed(playdate.kButtonB) then
        room.resetDockAssist()
        -- Traversal-State vollständig neutralisieren (Release-Fix 1): Nach einem
        -- Undo darf keine halbe Schalterdurchquerung phantomartig weiterleben
        -- (kein stale Trigger bei der nächsten minimalen Bewegung). Wird auch bei
        -- leerem Stack zurückgesetzt (harmlos, da der Zustand nur transiente
        -- Bewegungsinformation trägt).
        room.resetSwitchTraversal()
        local restored = undo.undo()
        if restored then
            room.syncPhysicalShutters()
        end
        -- Audio: Undo ist State-Restore, kein neues Ereignis.
        render.noteUndo()
        render.noteShutterBlocked(false)
        audio.noteShutterBlocked(false)
        return
    end

    -- 2) Bewegung / Andockhilfe. Player.getDesiredDelta ist die einzige
    --    Kurbelabfrage. Bewegungsinput gewinnt immer: eine laufende Assistenz
    --    wird abgebrochen und nur normal bewegt (kein Assistenzdelta zusätzlich).
    --    Die Blickrichtung (Facing) folgt der tatsächlich zurückgelegten
    --    Bewegung (actualDelta), nicht der gewünschten. UI-Reaktionen (Widen/
    --    Squint) entstehen ausschließlich aus dem echten movePlayer-Resultat.
    local wantedDelta = player.getDesiredDelta(FRAME_DT)
    if wantedDelta ~= 0 then
        room.resetDockAssist()
        local actualDelta, moveResult = room.movePlayer(wantedDelta)
        if actualDelta ~= 0 then
            render.notePlayerMovement(actualDelta)
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
            audio.playSwitchSnap(actualDelta > 0)
        end
        -- Brücke ausfahren: für jede echte Elementänderung einer normalen
        -- Brücke false->true (freie Brücken und das Gate zählen nicht).
        if moveResult.elementChanges then
            for _, ce in ipairs(moveResult.elementChanges) do
                if ce.to == true and ce.from ~= true then
                    for _, b in ipairs(state.room.bridges) do
                        if b.id == ce.id and b.free ~= true then
                            audio.playBridgeExtend()
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
        -- leichte Kompression in Fahrtrichtung + Augenweiten (Baby) und
        -- minimaler Druck + fokussierter Blick (Player). Kein Gameplay-Effekt.
        if moveResult.babyMoved then
            render.noteBabyPush(actualDelta)
            render.notePlayerPushContact()
        end
        -- Baby-Sounds (Begleiter): weicher Push-Ton bei Kontaktaufnahme
        -- (Flanke, nicht pro Frame), dumpfer Impact-Ton bei blockiertem Schub
        -- an das Baby (Baby gegen Grenze/Shutter, Spieler drückt weiter).
        audio.noteBabyPush(moveResult.babyMoved == true)
        audio.noteBabyImpact(moveResult.blocked and Baby.isContactingPlayer())
    else
        room.updateDockAssist()
        -- Kein Bewegungsversuch in diesem Frame: keine Kollision, kein
        -- Baby-Kontakt (Flanken-Latches zurücksetzen).
        render.noteShutterBlocked(false)
        audio.noteShutterBlocked(false)
        audio.noteBabyPush(false)
        audio.noteBabyImpact(false)
    end

    -- 3) A-Aktion (Just-Pressed, damit ein gehaltenes A nicht frameweise
    --    zwischen den Ringen hin- und herschaltet). Die Andockhilfe läuft VOR
    --    der A-Prüfung, sodass der letzte Assistenzframe + A direkt eine aktive
    --    Brücke benutzen kann. Die Progressionsentscheidung (nächsten Raum laden
    --    oder abgeschlossen) liegt zentral in handleConnectionResult; der Frame
    --    endet danach ohne weitere Movement-/Assistenz-/Connection-Verarbeitung.
    if playdate.buttonJustPressed(playdate.kButtonA) then
        local result = room.tryUseConnection()
        -- Torübergang nur bei erfolgreichem Gate (nicht bei erfolglosem A,
        -- nicht bei reiner Brücke). Der Puls klingt über den Raumwechsel aus.
        if result.used and result.kind == "gate" then
            audio.playGateTransition()
        end
        -- Brückenwechsel-Sound beim tatsächlichen Transferstart (solo ODER
        -- gemeinsam mit Baby). Nicht beim bloßen Andocken — tryUseConnection
        -- startet den Transit erst, wenn die Brücke tatsächlich genutzt wird.
        if result.used and result.crossing then
            audio.playBridgeCrossing()
        end
        -- Baby-Schicht-Sound beim GEMEINSAMEN Transfer (Player+Baby über eine
        -- Brücke): heller Klingelton über dem mechanischen Zip — das Baby
        -- „geht mit“. Nur bei sharedBridge.
        if result.used and result.kind == "sharedBridge" then
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

local function drawScene()
    if appMode == "outro" then
        transition.draw()
    elseif appMode == "menu" then
        -- Schnitt zum Titel: Menü direkt im Outro-Finish-Frame zeichnen (kein
        -- schwarzer Zwischenframe; Punkt 33).
        Menu.draw()
    elseif currentScene == "room" then
        render.drawRoom(roomComplete, currentRoomIndex)
    end
end

-- Spielstart: Startmenü anzeigen. Noch KEIN Gameplay, noch kein Raum geladen.
-- Audio-Synths werden einmalig initialisiert (keine Samples, reine Synth);
-- der Kernpuls startet erst nach Spielstart via Audio.resetRoom.
audio.init()
-- Fortschritt genau EINMAL beim App-Start laden (vor dem Menü, damit „Weiter"
-- den korrekten Continue-Raum kennt). Kein Datastore-Zugriff pro Frame.
loadProgress()
menu.init()
-- Systemmenu-Zugriff initialisieren (eigene Einträge leeren); die zwei
-- Gameplay-Einträge werden erst beim Spielstart registriert.
sysmenu.init()
-- Produktionsstart: Startmenü anzeigen (vorher sprang der Build per
-- TEMPORÄR-Testblock direkt in Raum 2 — Testartefakt, im Zuge des B-Taste-
-- Reworks entfernt). Gameplay beginnt erst nach Auswahl: „Weiter" = höchster
-- erreichter Raum, „Von vorn" = Raum 1.
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
        end
    end

    -- Startmenü: nur Menüupdate + Menüzeichnung. Kein Gameplay (keine
    -- Spielerbewegung, kein Sweep, keine A/B-Aktionen, kein DockAssist,
    -- kein Kernpuls). Das Menü zeichnet seinen eigenen schwarzen Rahmen.
    -- Startet eine Aktion das Spiel, wird im selben Frame kein Menü-Frame
    -- mehr gezeichnet (kein veralteter Menü-Rest).
    if appMode == "menu" then
        local action = Menu.update(FRAME_DT)
        if action ~= nil then
            handleMenuAction(action)
        end
        if appMode == "menu" then
            Menu.draw()
        end
        return
    end

    gfx.clear(gfx.kColorBlack)

    -- Rein visuelle Zeit fortschreiben (Kernpulsation, Preview, Blink-Planung),
    -- auch während Camera-Transition; Blink startet bei roomComplete nicht neu.
    render.update(FRAME_DT, roomComplete)
    -- Audio: Kernpuls (DER PULS IST DIE MUSIK), zeitbasiert.
    audio.update(FRAME_DT)

    updateScene()
    drawScene()
end