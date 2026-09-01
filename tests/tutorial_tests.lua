-- Tests für das Tutorial-/Anleitungs-System (source/core/tutorial.lua) und
-- dessen Persistenz-/Systemmenü-Anbindung (Save.loadTutorial, Sysmenu.installHelp).
--
-- Erwartet, dass core/config, core/geometry, core/state, core/save,
-- core/sysmenu, core/tutorial, world/baby und data/levels per import geladen
-- wurden (siehe tools/run_tests.ps1).

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

-- --- Teil A: Seen-Flags -----------------------------------------------------
Tutorial.init({})
check(Tutorial.isSeen("move") == false, "tutorial: init -> kein Flag gesetzt")
check(Tutorial.markSeen("move") == true, "tutorial: markSeen liefert true bei neuer Änderung")
check(Tutorial.isSeen("move") == true, "tutorial: markSeen setzt Flag")
check(Tutorial.markSeen("move") == false, "tutorial: erneutes markSeen liefert false (kein Duplikat)")
check(Tutorial.consumeChanged() == true, "tutorial: consumeChanged liefert true nach Änderung")
check(Tutorial.consumeChanged() == false, "tutorial: consumeChanged konsumiert (danach false)")
Tutorial.reset()
check(Tutorial.isSeen("move") == false, "tutorial: reset -> Flags leer")
check(Tutorial.consumeChanged() == false, "tutorial: reset -> changed leer")

-- --- Teil B: Einleitung (NEW GAME) ------------------------------------------
Tutorial.init({})
Tutorial.startIntro()
check(Tutorial.isIntroActive() == true, "tutorial: intro startet")
check(Tutorial.introBoard == 0, "tutorial: intro beginnt mit Willkommensseite")
Tutorial.advanceIntro()
check(Tutorial.introBoard == 1, "tutorial: advanceIntro -> Begleiterseite")
check(Tutorial.isIntroActive() == true, "tutorial: nach Willkommensseite noch aktiv")
Tutorial.advanceIntro()
check(Tutorial.isIntroActive() == false, "tutorial: advanceIntro auf Begleiterseite beendet Einleitung")
Tutorial.advanceIntro()
check(Tutorial.isIntroActive() == false, "tutorial: advanceIntro nach Ende bleibt beendet")
-- B = zurück innerhalb der Einleitung (1 -> 0, nicht weiter zurück)
Tutorial.startIntro()
check(Tutorial.introBoard == 0, "tutorial: backIntro-Setup auf Willkommensseite")
Tutorial.advanceIntro()
Tutorial.backIntro()
check(Tutorial.introBoard == 0, "tutorial: backIntro -> Willkommensseite")
Tutorial.backIntro()
check(Tutorial.introBoard == 0, "tutorial: backIntro auf Willkommensseite bleibt (kein Zurück weiter)")
check(Tutorial.isIntroActive() == true, "tutorial: backIntro beendet Einleitung nicht")
Tutorial.reset()
check(Tutorial.isIntroActive() == false, "tutorial: reset beendet Einleitung")

-- --- Teil C: Kontext-Hinweise -----------------------------------------------
Tutorial.init({})
Tutorial.showHint("HINWEIS", "UNTERHINWEIS")
check(Tutorial.hasHint() == true, "tutorial: showHint -> Hinweis aktiv")
Tutorial.updateHint(2.4 + 0.31) -- hold + Fade überschreiten
check(Tutorial.hasHint() == false, "tutorial: transienter Hinweis blendet automatisch aus")
check(Tutorial.markSeen("dummy") == true, "tutorial: markSeen funktioniert neben Hinweis")
Tutorial.consumeChanged()

-- persistenter Hinweis: bleibt bis dismiss (generische Infrastruktur — der
-- alte Kurbel-Hinweis selbst ist entfernt)
Tutorial.init({})
Tutorial.showHintPersistent("dummy", "PERSISTENT")
check(Tutorial.hasHint() == true, "tutorial: persistenter Hinweis aktiv")
check(Tutorial.isHintPersistent("dummy") == true, "tutorial: isHintPersistent erkennt key")
Tutorial.updateHint(5.0)
check(Tutorial.hasHint() == true, "tutorial: persistenter Hinweis läuft nicht ab")
Tutorial.dismissHint()
check(Tutorial.hasHint() == true, "tutorial: dismissHint startet Ausblenden (noch sichtbar)")
Tutorial.updateHint(0.31) -- Fade vorbei
check(Tutorial.hasHint() == false, "tutorial: persistenter Hinweis ist ausgeblendet")
Tutorial.hint = nil

-- PLAYER-VORSTELLUNG (ROOM 1): startPlayerIntro markiert „move“ und startet
-- einen Fokus auf den Player — KEIN separater Kurbel-Hinweis mehr.
Tutorial.init({})
State.init(Levels[1], false)
check(Tutorial.isSeen("move") == false, "tutorial: NEW GAME -> move noch nicht gesehen")
local pStarted = Tutorial.startPlayerIntro()
check(pStarted == true, "tutorial: startPlayerIntro startet die Vorstellung")
check(Tutorial.focusActive() == true, "tutorial: Player-Vorstellung = Fokus aktiv")
check(Tutorial.focus ~= nil and Tutorial.focus.key == "player", "tutorial: Fokus-Key = player")
check(Tutorial.focus.text == "Turn the crank. See where it takes you.", "tutorial: Text = 'Turn the crank. See where it takes you.'")
check(Tutorial.isSeen("move") == true, "tutorial: startPlayerIntro markiert move als gesehen")
check(Tutorial.hasHint() == false, "tutorial: KEIN separater Kurbel-Hinweis (alter Hinweis entfernt)")
-- einmal: erneuter Aufruf startet nichts Neues (auch nach A).
check(Tutorial.startPlayerIntro() == false, "tutorial: Player-Vorstellung nur einmal")
Tutorial.dismissFocus()
check(Tutorial.startPlayerIntro() == false, "tutorial: nach A keine erneute Vorstellung")
-- Raum 2: keine Player-Vorstellung.
Tutorial.init({})
State.init(Levels[2], false)
check(Tutorial.checkLevelHints(2) == false, "tutorial: checkLevelHints in Raum 2 startet nichts")

-- Begleiter-Screen: erster Baby-Schub startet den Fokus (genau einmal).
Tutorial.init({})
State.init(Levels[1], false)
local started = Tutorial.checkElementTriggers(1, { babyMoved = true })
check(started == true, "tutorial: erster Baby-Schub -> Begleiter-Fokus")
check(Tutorial.isSeen("begleiter") == true, "tutorial: begleiter markiert")
check(Tutorial.focusActive() == true, "tutorial: Begleiter-Fokus aktiv")
Tutorial.dismissFocus()
check(Tutorial.checkElementTriggers(1, { babyMoved = true }) == false, "tutorial: Begleiter nur einmal")
Tutorial.init({})
State.init(Levels[1], false)
check(Tutorial.checkElementTriggers(1, {}) == false, "tutorial: ohne Baby-Schub kein Begleiter-Fokus")

-- erster Ziehversuch (Kontakt + Bewegung vom Baby weg)
Tutorial.init({})
State.init(Levels[1], false)
State.player.angle = 0
State.baby.angle = Geometry.norm(360 - Baby.contactDeg())
check(Baby.isContactingPlayer() == true, "tutorial: Test-Setup hat Kontakt (Baby hinter Player)")
Tutorial.onPullAttempt(1, 5) -- CW-Bewegung, Baby bei 355 (hinten)
check(Tutorial.isSeen("noPull") == true, "tutorial: Ziehversuch markiert noPull")
check(Tutorial.hasHint() == true, "tutorial: Ziehversuch zeigt Hinweis")
Tutorial.hint = nil
-- kein Ziehversuch ohne Kontakt
Tutorial.init({})
State.init(Levels[1], false)
State.player.angle = 0
State.baby.angle = 180
Tutorial.onPullAttempt(1, 5)
check(Tutorial.isSeen("noPull") == false, "tutorial: ohne Kontakt kein Ziehversuch")
-- kein Ziehversuch in anderen Räumen
Tutorial.init({})
State.init(Levels[1], false)
State.player.angle = 0
State.baby.angle = Geometry.norm(360 - Baby.contactDeg())
Tutorial.onPullAttempt(2, 5)
check(Tutorial.isSeen("noPull") == false, "tutorial: Ziehversuch nur in Raum 1")

-- --- Teil D: Element-Erklaer-Fokus (Proximity, NICHT bei Raumstart) --------
-- NEU (Auftrag „erst VOR Kontakt“): maybeStartFocus startet KEINEN Fokus
-- mehr beim Raumstart — es merkt sich das neue Element nur als pending.
-- checkProximityFocus startet den Fokus erst, wenn der Player sich dem
-- Element zum ersten Mal nähert (auf demselben Ring, innerhalb
-- Config.tutorialProximityRange) — kurz bevor er es berührt/überquert.
local FOCUS_ROOMS = {
    [2] = "doppelschalter",
    [3] = "druckplatte",
    [4] = "einmalschalter",
    [5] = "einmalbruecke",
    [7] = "inaktivebruecke",
}
local FOCUS_OBJ = {
    [2] = "switch",
    [3] = "plate",
    [4] = "oneShot",
    [5] = "oneUseBridge",
    [7] = "inactiveBridge",
}
for roomIdx, key in pairs(FOCUS_ROOMS) do
    Tutorial.init({})
    State.init(Levels[roomIdx], false)
    local started = Tutorial.maybeStartFocus(roomIdx)
    check(started == false, "tutorial: Raumstart startet KEINEN Fokus (Raum " .. roomIdx .. ")")
    check(Tutorial.isSeen(key) == false, "tutorial: noch nicht markiert (" .. key .. ")")
    check(Tutorial.focusActive() == false, "tutorial: kein Fokus aktiv in Raum " .. roomIdx)
    check(Tutorial.pendingMechanic ~= nil, "tutorial: Element ist pending in Raum " .. roomIdx)
    -- Fokus-Objekt finden; Player in Proximity stellen -> Fokus startet.
    local ring, angle = Tutorial.focusObject(FOCUS_OBJ[roomIdx])
    check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet Element (Raum " .. roomIdx .. ")")
    State.player.ring = ring
    State.player.angle = Geometry.norm(angle - (Config.tutorialProximityRange - 2))
    local prox = Tutorial.checkProximityFocus(roomIdx)
    check(prox == true, "tutorial: Proximity startet Fokus in Raum " .. roomIdx)
    check(Tutorial.isSeen(key) == true, "tutorial: Fokus markiert " .. key)
    check(Tutorial.focusActive() == true, "tutorial: Fokus aktiv in Raum " .. roomIdx)
    Tutorial.dismissFocus()
    check(Tutorial.focusActive() == false, "tutorial: dismissFocus beendet Fokus")
    check(Tutorial.checkProximityFocus(roomIdx) == false, "tutorial: Fokus nur einmal in Raum " .. roomIdx)
    -- Fern vom Element -> kein Fokus (frisches pending).
    Tutorial.init({})
    State.init(Levels[roomIdx], false)
    Tutorial.maybeStartFocus(roomIdx)
    State.player.ring = ring
    State.player.angle = Geometry.norm(angle + 90)
    check(Tutorial.checkProximityFocus(roomIdx) == false, "tutorial: fern vom Element kein Fokus (" .. roomIdx .. ")")
end
-- keine neue Mechanik -> kein pending, kein Fokus
for _, roomIdx in ipairs({ 1, 6, 8 }) do
    Tutorial.init({})
    State.init(Levels[roomIdx], false)
    Tutorial.maybeStartFocus(roomIdx)
    check(Tutorial.pendingMechanic == nil, "tutorial: kein pending in Raum " .. roomIdx)
    check(Tutorial.checkProximityFocus(roomIdx) == false, "tutorial: kein Fokus in Raum " .. roomIdx)
end

-- Fokus-Objekt wird gefunden (Ring + Winkel)
Tutorial.init({})
State.init(Levels[2], false)
local ring, angle = Tutorial.focusObject("switch")
check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet Schalter (Raum 2)")
State.init(Levels[3], false)
ring, angle = Tutorial.focusObject("plate")
check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet Platte (Raum 3)")
State.init(Levels[4], false)
ring, angle = Tutorial.focusObject("oneShot")
check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet Einmalschalter (Raum 4)")
State.init(Levels[5], false)
ring, angle = Tutorial.focusObject("oneUseBridge")
check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet Einmal-Brücke (Raum 5)")
State.init(Levels[7], false)
ring, angle = Tutorial.focusObject("inactiveBridge")
check(ring ~= nil and angle ~= nil, "tutorial: focusObject findet inaktive Brücke (Raum 7)")

-- Level-1-Check: Player-Vorstellung erscheint im ersten kontrollierbaren
-- Moment (ersetzt den alten Kurbel-Hinweis vollständig).
Tutorial.init({})
State.init(Levels[1], false)
check(Tutorial.checkLevelHints(1) == true, "tutorial: checkLevelHints startet Player-Vorstellung (Raum 1)")
check(Tutorial.focusActive() == true and Tutorial.focus ~= nil and Tutorial.focus.key == "player",
    "tutorial: Player-Vorstellung = Fokus auf den Player")
check(Tutorial.isSeen("move") == true, "tutorial: checkLevelHints markiert move")
check(Tutorial.hasHint() == false, "tutorial: kein alter Kurbel-Hinweis mehr")
Tutorial.dismissFocus()
check(Tutorial.checkLevelHints(1) == false, "tutorial: Player-Vorstellung nur einmal (Flag gesehen)")
Tutorial.focus = nil

-- --- Kontext-Trigger: Bruecke, Blockade, Ziel -------------------------------
-- Bruecke: Player in dockRange einer Bruecke -> Fokus.
Tutorial.init({})
State.init(Levels[1], false)
State.player.angle = 90 -- B1@90 in Level 1
check(Tutorial.checkElementTriggers(1, {}) == true, "tutorial: an Bruecke -> Bruecken-Fokus")
check(Tutorial.isSeen("bruecke") == true, "tutorial: bruecke markiert")
Tutorial.dismissFocus()
check(Tutorial.checkElementTriggers(1, {}) == false, "tutorial: Bruecke nur einmal")
Tutorial.init({})
State.init(Levels[1], false)
State.player.angle = 0
check(Tutorial.checkElementTriggers(1, {}) == false, "tutorial: fern der Bruecke kein Fokus")

-- Blockade (Shutter): Proximity VOR dem Kontakt (nicht beim Aufprall) -> Fokus.
Tutorial.init({})
State.init(Levels[2], false)
Room.init() -- Room.shutters frisch aufbauen (alle offen)
Room.shutters["D1"] = { collisionActive = true } -- Blende D1@90 in Level 2 zu
State.player.ring = "outer"
State.player.angle = Geometry.norm(90 - (Config.tutorialProximityRange - 2)) -- noch davor
check(Tutorial.checkProximityFocus(2) == true, "tutorial: nahe geschlossener Blende -> Blockade-Fokus")
check(Tutorial.isSeen("blockade") == true, "tutorial: blockade markiert")
Tutorial.dismissFocus()
check(Tutorial.checkProximityFocus(2) == false, "tutorial: Blockade nur einmal")
Tutorial.init({})
State.init(Levels[1], false) -- Level 1 hat keine Blenden
check(Tutorial.checkProximityFocus(1) == false, "tutorial: ohne Blende kein Blockade-Fokus")

-- Ziel: Player am Tor (Ring + dockRange) -> Fokus.
Tutorial.init({})
State.init(Levels[1], false)
State.player.ring = "inner"
State.player.angle = 135 -- Gate T@135 in Level 1
check(Tutorial.checkElementTriggers(1, {}) == true, "tutorial: am Tor -> Ziel-Fokus")
check(Tutorial.isSeen("ziel") == true, "tutorial: ziel markiert")
Tutorial.dismissFocus()
Tutorial.init({})
State.init(Levels[1], false)
State.player.ring = "outer"
check(Tutorial.checkElementTriggers(1, {}) == false, "tutorial: ohne Tor-Kontakt kein Ziel-Fokus")

-- --- Teil E: Save-Persistenz (mock Datastore) -------------------------------
local realDatastore = playdate.datastore
local stored = nil
playdate.datastore = {
    read = function()
        return stored
    end,
    write = function(t)
        stored = t
    end,
    delete = function()
        stored = nil
        return true
    end,
}
stored = nil
local okW = Save.write(2, { move = true })
check(okW == true, "tutorial: Save.write mit tutorial ok")
check(stored ~= nil and stored.highestRoom == 2 and stored.tutorial ~= nil and stored.tutorial.move == true,
    "tutorial: Save.write schreibt highestRoom + tutorial")
local flags = Save.loadTutorial()
check(flags.move == true, "tutorial: Save.loadTutorial liest Flags zurück")
-- fehlende/kaputte Daten -> leere Tabelle (harmlos, Hinweise erscheinen erneut)
stored = nil
check(next(Save.loadTutorial()) == nil, "tutorial: loadTutorial ohne Daten -> leer")
stored = { highestRoom = 3 }
check(next(Save.loadTutorial()) == nil, "tutorial: loadTutorial ohne tutorial-Feld -> leer")
stored = { highestRoom = 3, tutorial = "kaputt" }
check(next(Save.loadTutorial()) == nil, "tutorial: loadTutorial mit kaputtem Feld -> leer")
stored = { highestRoom = 3, tutorial = { move = true, kaputt = 1, anderes = "x" } }
local flags2 = Save.loadTutorial()
check(flags2.move == true and flags2.kaputt == nil and flags2.anderes == nil,
    "tutorial: loadTutorial übernimmt nur echte true-Flags")
playdate.datastore = realDatastore

-- --- Teil F: Systemmenü „ANLEITUNG“ -----------------------------------------
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
playdate.getSystemMenu = function()
    return menuMock
end
Sysmenu.init()
local cbHelp = 0
check(Sysmenu.installHelp(function() cbHelp = cbHelp + 1 end) == true,
    "tutorial: installHelp erfolgreich")
check(Sysmenu.isHelpInstalled() == true, "tutorial: help installiert")
check(Sysmenu.getItemCount() == 1, "tutorial: genau 1 Anleitungs-Eintrag")
check(Sysmenu.getLabel(1) == "ANLEITUNG", "tutorial: Label = ANLEITUNG")
check(Sysmenu.installHelp(function() end) == true, "tutorial: installHelp idempotent")
check(Sysmenu.getItemCount() == 1, "tutorial: installHelp erzeugt kein Duplikat")
Sysmenu.invokeItem(1)
check(cbHelp == 1, "tutorial: invokeItem(1) ruft Help-Callback")
Sysmenu.removeAll()
check(Sysmenu.isHelpInstalled() == false, "tutorial: removeAll entfernt Help-Eintrag")
check(Sysmenu.getItemCount() == 0, "tutorial: removeAll -> 0 Einträge")
playdate.getSystemMenu = realGetSystemMenu

-- --- Teil G: Zeichen-Smoke-Tests (laufen im Simulator mit gfx) --------------
-- Die Overlay-Zeichenfunktionen dürfen nicht crashen (auch mit aktiver
-- Ein-/Ausblendung und Fokus-Fenster).
Tutorial.init({})
local okDraw = pcall(function()
    Tutorial.startIntro()      -- Willkommensseite (0)
    Tutorial.drawIntro()
    Tutorial.advanceIntro()    -- Begleiterseite (1)
    Tutorial.drawIntro()
    Tutorial.advanceIntro()    -- Ende
end)
check(okDraw, "tutorial: drawIntro läuft fehlerfrei (Willkommensseite + Begleiterseite)")

Tutorial.init({})
okDraw = pcall(function()
    Tutorial.showHint("HINWEIS", "SUB")
    Tutorial.drawHint()
    Tutorial.hint.t = 0.15 -- halbe Einblendung -> Dissolve-Pfad
    Tutorial.drawHint()
    Tutorial.hint = nil
    Tutorial.showHintPersistent("move", "KURBEL — BEWEGEN")
    Tutorial.drawHint()
    Tutorial.hint = nil
end)
check(okDraw, "tutorial: drawHint läuft fehlerfrei (transient/persistent/Dissolve)")

okDraw = pcall(function()
    State.init(Levels[2], false)
    Camera.init(State.room.rings.outer)
    Tutorial.init({})
    Tutorial.maybeStartFocus(2)
    local ring, angle = Tutorial.focusObject("switch")
    if ring then
        State.player.ring = ring
        State.player.angle = Geometry.norm(angle - 4) -- in Proximity
        Tutorial.checkProximityFocus(2)
    end
    Tutorial.drawFocus()
    Tutorial.dismissFocus()
end)
check(okDraw, "tutorial: drawFocus läuft fehlerfrei (Fokus-Fenster)")

-- Player-Vorstellung (ROOM 1): Fokus auf den echten Player — die Zeichnung
-- (Hervorhebung + Infoleiste) darf nicht crashen und nutzt die echte
-- Player-Bildschirmposition (keine Ersatzgrafik).
okDraw = pcall(function()
    State.init(Levels[1], false)
    Camera.init(State.room.rings.outer)
    Tutorial.init({})
    local ok = Tutorial.startPlayerIntro()
    if ok then
        Tutorial.drawFocus()
        local f = Tutorial.focus
        if f then
            check(f.key == "player", "tutorial: drawFocus-Player-Fokus key = player")
        end
        Tutorial.dismissFocus()
    end
end)
check(okDraw, "tutorial: drawFocus mit Player-Vorstellung läuft fehlerfrei")

okDraw = pcall(function()
    Tutorial.drawHelp()
end)
check(okDraw, "tutorial: drawHelp läuft fehlerfrei (ANLEITUNG, alle Einträge)")

TestReport.tutorial = { pass = pass, fail = fail }
