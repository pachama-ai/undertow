-- Tests für das Playdate-Systemmenü (Phase 10.3).
--
-- Teil A: Sysmenu-Unit (source/core/sysmenu.lua) mit gemocktem Systemmenu —
--   exakte Labels, exakt zwei Einträge, idempotente Registrierung (keine
--   Duplikate), removeAll -> 0 (Startmenü-Modus), testbare Callbacks, keine
--   World-/Gameplay-Kopplung (Trap).
-- Teil B: Restart-Contract — die Produktions-Reset-Sequenz (startRoom + stabile
--   Kamera, exakt die Reihenfolge aus main.lua) lässt State/Player/Switches/
--   Elements/Undo/Bridge/DockAssist/Camera frisch und denselben Raum; KEIN
--   Datastore-Write; funktioniert während Bridge-Crossing, Camera-Transition
--   und nach Completion; erzeugt keine künstlichen SFX.
-- Teil C: „Zum Menü"-Contract — Menu.show() zeigt den Titel mit den passenden
--   Optionen (CONTINUE/NEW GAME/EXIT je nach Save), entfernt Gameplay-
--   Systemitems, schreibt/liest Datastore nicht; ein Spielstart danach startet
--   frisch (CONTINUE/NEW GAME), das Save bleibt unverändert.
--
-- Erwartet, dass core/sysmenu, core/state, core/undo, core/audio, world/room,
-- world/bridge, ui/camera, ui/render, ui/menu und data/levels per import
-- geladen wurden (siehe tools/run_tests.ps1).

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

-- --- Teil A: Systemmenu-Mock -------------------------------------------------
local realGetSystemMenu = playdate.getSystemMenu
local menuItems = {}
local menuMock = {
    addMenuItem = function(self, title, callback)
        local item = { label = title, callback = callback }
        menuItems[#menuItems + 1] = item
        return item
    end,
    removeAllMenuItems = function(self)
        menuItems = {}
    end,
    getMenuItems = function(self)
        return menuItems
    end,
}
local function resetMenuMock()
    menuItems = {}
end
playdate.getSystemMenu = function()
    return menuMock
end

-- --- Teil A: Sysmenu-Unit ----------------------------------------------------
Sysmenu.init()
check(Sysmenu.getItemCount() == 0, "sysmenu: init -> 0 eigene Einträge")
check(Sysmenu.isInstalled() == false, "sysmenu: init -> nicht installiert")

local cbRestart = 0
local cbMenu = 0
local okInstall = Sysmenu.install(
    function() cbRestart = cbRestart + 1 end,
    function() cbMenu = cbMenu + 1 end)
check(okInstall == true, "sysmenu: install erfolgreich")
check(Sysmenu.isInstalled() == true, "sysmenu: installiert")
check(Sysmenu.getItemCount() == 2, "sysmenu: exakt 2 Einträge im Gameplay")
check(Sysmenu.getLabel(1) == "Raum neu starten", "sysmenu: Label 1 = 'Raum neu starten'")
check(Sysmenu.getLabel(2) == "Zum Menü", "sysmenu: Label 2 = 'Zum Menü'")

-- Idempotenz: erneutes install darf nicht duplizieren (Punkt 43/44/46).
Sysmenu.install(function() end, function() end)
Sysmenu.install(function() end, function() end)
check(Sysmenu.getItemCount() == 2, "sysmenu: mehrfach install -> weiterhin 2 (kein Duplikat)")
check(#menuItems == 2, "sysmenu: Mock bestätigt exakt 2 registrierte Items")

-- Callbacks testbar via invokeItem (Punkt 48).
Sysmenu.invokeItem(1)
Sysmenu.invokeItem(2)
check(cbRestart == 1, "sysmenu: invokeItem(1) ruft Restart-Callback genau einmal")
check(cbMenu == 1, "sysmenu: invokeItem(2) ruft Menü-Callback genau einmal")

-- Startmenü-Modus: removeAll -> 0 Gameplay-Items (Punkt 45/51).
Sysmenu.removeAll()
check(Sysmenu.getItemCount() == 0, "sysmenu: removeAll -> 0 Einträge (Startmenü-Modus)")
check(Sysmenu.isInstalled() == false, "sysmenu: removeAll -> nicht installiert")
check(#menuItems == 0, "sysmenu: Mock bestätigt 0 Items nach removeAll")

-- Erneutes Gameplay: install -> wieder exakt 2 (Punkt 52/46).
Sysmenu.install(function() end, function() end)
check(Sysmenu.getItemCount() == 2, "sysmenu: nach removeAll erneut install -> 2")
Sysmenu.removeAll()

-- Keine World-Kopplung: während Sysmenu-Aufrufen dürfen State/Undo/Room/
-- Bridge/Camera/Audio/Menu/Levels/Config/Geometry/Player/Switch/Gate nicht
-- berührt werden (Trap). Callbacks sind opaque Controller-Signale.
local trapped = {
    "State", "Undo", "Room", "Bridge", "Camera", "Audio", "Menu",
    "Levels", "Config", "Geometry", "Player", "Switch", "Gate",
}
local function withTrap(globalName, fn)
    local real = _G[globalName]
    _G[globalName] = setmetatable({}, {
        __index = function()
            error("trap: " .. globalName .. " während Sysmenu-Aufruf berührt")
        end,
    })
    local okTrap, errTrap = pcall(fn)
    _G[globalName] = real
    return okTrap
end
Sysmenu.init()
for _, name in ipairs(trapped) do
    local callbackCount = 0
    local okTrap = withTrap(name, function()
        callbackCount = 0
        Sysmenu.install(
            function() callbackCount = callbackCount + 1 end,
            function() callbackCount = callbackCount + 1 end)
        Sysmenu.invokeItem(1)
        Sysmenu.invokeItem(2)
        Sysmenu.removeAll()
    end)
    check(okTrap, "sysmenu: " .. name .. " bleibt unberührt (Trap nicht ausgelöst)")
    check(callbackCount == 2, "sysmenu: Callbacks liefen trotz Trap (opaque Signale, " .. name .. ")")
end

-- --- Datastore-Mock für Teil B/C (wird am Ende restauriert) -----------------
local realDatastore = playdate.datastore
local readCount = 0
local writeCount = 0
playdate.datastore = {
    read = function()
        readCount = readCount + 1
        return { highestRoom = 7 }
    end,
    write = function(t)
        writeCount = writeCount + 1
        return nil
    end,
    delete = function()
        return true
    end,
}

-- Audio mit frischem Mock re-injizieren (Zähler für künstliche SFX).
local playNoteCount = 0
local function makeSoundMock()
    local synth = {}
    local s = {
        setADSR = function() end,
        playNote = function()
            playNoteCount = playNoteCount + 1
        end,
        playMIDINote = function()
            playNoteCount = playNoteCount + 1
        end,
        setFrequencyMod = function() end,
        stop = function() end,
    }
    return {
        synth = {
            new = function() return s end,
        },
        controlsignal = {
            new = function()
                return { addEvent = function() end, clearEvents = function() end }
            end,
        },
        getCurrentTime = function()
            return 0
        end,
        kWaveNoise = 0, kWaveSquare = 1, kWaveSawtooth = 2, kWaveSine = 3,
    }
end
Audio.init(makeSoundMock())
playNoteCount = 0

-- --- Teil B: Restart-Contract (Produktions-Reset-Sequenz) --------------------
-- Exakt die Reihenfolge aus main.lua: Bridge.resetTransit -> Room.resetDockAssist
-- -> State.init -> Undo.clear -> Room.init -> Camera.init(stabil) ->
-- Render.resetPlayerVisual -> Audio.resetRoom(roomIndex). Das ist die zentrale
-- startRoom-Wahrheit, die „Raum neu starten" benutzt (Punkt 6/16/17).
local function resetRoomContract(roomIndex)
    local roomData = Levels[roomIndex]
    Bridge.resetTransit()
    Baby.resetTransit()
    Room.resetDockAssist()
    State.init(roomData)
    Undo.clear()
    Room.init()
    Camera.init(State.room.rings.outer)
    Render.resetPlayerVisual()
    Audio.resetRoom(roomIndex)
end

local function assertFreshRoom(roomIndex, prefix)
    local roomData = Levels[roomIndex]
    check(State.room ~= nil and State.room.name == roomData.name,
        prefix .. " State.room = gleicher Raum (" .. roomData.name .. ")")
    check(State.player.ring == roomData.start.ring and State.player.angle == roomData.start.angle,
        prefix .. " Player = Startposition")
    local allInitial = true
    for _, sw in ipairs(roomData.switches) do
        if State.switchStates[sw.id] ~= sw.state then
            allInitial = false
        end
    end
    check(allInitial, prefix .. " Switchstates = Initialwerte")
    check(State.elementStates ~= nil, prefix .. " Elementstates neu abgeleitet")
    check(Undo.count() == 0, prefix .. " Undo = 0")
    check(Bridge.isCrossing() == false, prefix .. " Bridge crossing = false")
    check(Room.isDockAssisting() == false, prefix .. " DockAssist inaktiv")
    check(Camera.isTransitioning() == false, prefix .. " Camera transitioning = false")
    check(Camera.getCurrentOuterRing() == State.room.rings.outer,
        prefix .. " Camera current outer = Raum outer (stabil)")
end

-- Raum 1/2: verändern (Player bewegen -> Baby-Push erzeugt genau 1 Undo).
State.init(Levels[1])
Undo.clear()
Room.init()
Room.movePlayer(45) -- schiebt nicht (Baby bei 60, Kontakt bei ~52) -> 0 Undo
State.init(Levels[2])
Undo.clear()
Room.init()
Room.movePlayer(45) -- schiebt Baby (Kontakt bei ~37) -> genau 1 Undo
check(Undo.count() == 1, "sm-contract: Undo vor Restart > 0 (Vorbereitung)")

resetRoomContract(1)
assertFreshRoom(1, "sm-contract-restart1:")
check(writeCount == 0, "sm-contract-restart1: kein Datastore-Write durch Restart (Punkt 15/58)")
check(playNoteCount == 0, "sm-contract-restart1: Restart erzeugt keine künstlichen SFX (Punkt 18/19)")

-- Raum 2: Reset bleibt Raum 2 (Punkt 56).
resetRoomContract(2)
assertFreshRoom(2, "sm-contract-restart2:")

-- Räume 3-7: analog (Punkt 57/48, Abschlussphase A: Restart in allen Räumen).
resetRoomContract(3)
assertFreshRoom(3, "sm-contract-restart3:")
resetRoomContract(4)
assertFreshRoom(4, "sm-contract-restart4:")
resetRoomContract(5)
assertFreshRoom(5, "sm-contract-restart5:")
resetRoomContract(6)
assertFreshRoom(6, "sm-contract-restart6:")
resetRoomContract(7)
assertFreshRoom(7, "sm-contract-restart7:")

-- Restart während Bridge-Crossing (Punkt 21/59).
State.init(Levels[1])
Undo.clear()
Room.init()
State.elementStates["B1"] = true -- Brücke nutzbar machen
Bridge.beginTransit({ id = "B1", angle = 270, free = false }, "outer")
check(Bridge.isCrossing() == true, "sm-contract: Bridge vor Restart aktiv (Vorbereitung)")
resetRoomContract(1)
check(Bridge.isCrossing() == false, "sm-contract-crossing: Restart beendet Bridge-Transit")
check(State.player.ring == Levels[1].start.ring and State.player.angle == Levels[1].start.angle,
    "sm-contract-crossing: Player = Start nach Restart (kein Crash)")

-- Restart während Camera-Transition nach 1->2 (Punkt 22/60).
resetRoomContract(1)
Camera.beginRoomTransition(7, 6, 6, 5) -- Raum 1 outer/inner -> Raum 2 outer/inner
check(Camera.isTransitioning() == true, "sm-contract: Camera vor Restart transitioniert (Vorbereitung)")
resetRoomContract(2) -- „aktueller Raum" ist Raum 2
check(State.room ~= nil and State.room.name == Levels[2].name,
    "sm-contract-camera: Restart bleibt Raum 2 (nicht Raum 1)")
check(Camera.isTransitioning() == false, "sm-contract-camera: Camera-Transition beendet")
check(Camera.getCurrentOuterRing() == State.room.rings.outer,
    "sm-contract-camera: Camera stabil auf Raum-2-outer")

-- Restart nach Completion (Punkt 23/61/20): Audio-Completion -> Reset ->
-- wieder aktiv (Core-Timer neu; nächster Puls bei coreFrequency(7), Raum 7 ist
-- der Finalraum).
resetRoomContract(7)
Audio.setCompleted()
Audio.update(4.5) -- wäre bei completed still
local pulsesAfterCompleted = playNoteCount
Audio.resetRoom(7)
Audio.update(4.5) -- nach Reset wieder pulsierend
check(playNoteCount > pulsesAfterCompleted,
    "sm-contract-completion: Restart nach Completion setzt Audio-Kernpuls zurück")

-- --- Teil C: „Zum Menü"-Contract ---------------------------------------------
-- Menu.show() zeigt den Titelbildschirm (Punkt 30). Der Titel hat Menüoptionen
-- (CONTINUE/NEW GAME/EXIT je nach Save); die Zeichenanimation startet neu.
readCount = 0
writeCount = 0
Menu.show()
check(Menu.isActive() == true, "sm-menu: Menu aktiv")
check(Menu.isFillPhase() == false and Menu.isRevealPhase() == false, "sm-menu: nach show nicht in Fill/Reveal")
check(Menu.isIntroDone() == false, "sm-menu: nach show läuft die Zeichenanimation")
-- Startmenü-Modus: keine Gameplay-Systemitems (Punkt 45).
Sysmenu.removeAll()
check(Sysmenu.getItemCount() == 0, "sm-menu: im Startmenü 0 Gameplay-Systemitems")
-- „Zum Menü" schreibt/liest Datastore nicht (Punkt 25/34/35/65/66).
check(readCount == 0 and writeCount == 0,
    "sm-menu: Zum-Menü-Sequenz liest/schreibt Datastore nicht")
-- Menu.draw (Menü-Rahmen) verändert nichts.
Menu.hide()

-- Mid-Room-State wird nicht persistiert: „Weiter" danach startet frisch
-- (Punkt 26/27/64). Der Mid-Room-Undo entsteht im Baby-/Platten-Raum 3
-- (keine Schalter): der Baby-Push erzeugt genau 1 Undo (babyMoved).
State.init(Levels[3])
Undo.clear()
Room.init()
Room.movePlayer(70) -- schiebt das Baby -> genau 1 Undo (babyMoved)
check(Undo.count() == 1, "sm-menu: Mid-Room-Undo vor Weiter > 0 (Vorbereitung)")
resetRoomContract(3) -- „Weiter" = startRoom(highestRoom=3) frisch
assertFreshRoom(3, "sm-menu-continue:")

-- „Von vorn" danach bei Save=7: Raum 1 frisch, Save bleibt 7, kein Write
-- (Punkt 28/67/18).
resetRoomContract(1)
assertFreshRoom(1, "sm-menu-vonvorn:")
check(writeCount == 0, "sm-menu-vonvorn: kein Datastore-Write (Save bleibt 7)")

-- --- Restauration ------------------------------------------------------------
playdate.datastore = realDatastore
playdate.getSystemMenu = realGetSystemMenu
Sysmenu.init()
check(playdate.datastore == realDatastore, "sm: echter Datastore restauriert")
check(playdate.getSystemMenu == realGetSystemMenu, "sm: echtes getSystemMenu restauriert")

TestReport.systemMenu = { pass = pass, fail = fail }
