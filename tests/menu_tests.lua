-- Tests für source/ui/menu.lua (Titelbildschirm UNDERTOW): Zeichenanimation,
-- A-Bestätigung ("continue"/"newgame"/"exit"), Fill-/Reveal-Lebenszyklus und
-- read-only Verhalten. Die Zeichnung wird über einen GFX-Mock geprüft
-- (gfx.clear, Ringbogen, UNDERTOW-Text, Menüoptionen). MIT Save zeigt das
-- Menü CONTINUE/NEW GAME/EXIT (Default CONTINUE), OHNE Save nur NEW GAME/EXIT
-- (Default NEW GAME, CONTINUE komplett weggelassen). Kein Gameplay: Menu darf
-- State/Undo/Room/Bridge/Camera nicht verändern. Erwartet, dass core/config,
-- core/geometry, core/state, core/undo, world/room, world/bridge, data/levels,
-- ui/render, ui/camera und ui/menu per import geladen wurden
-- (siehe tools/run_tests.ps1).

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

-- --- Eingabe-/GFX-Mock (wird am Ende restauriert) --------------------------
local realButtonJustPressed = playdate.buttonJustPressed
local realGraphics = playdate.graphics
local pressed = {}

local function press(button)
    pressed[button] = true
end

playdate.buttonJustPressed = function(b)
    local v = pressed[b] == true
    pressed[b] = nil
    return v
end

local function makeGfxMock()
    local calls = {
        clears = 0, clearColor = nil,
        arcs = {}, texts = {}, circles = {}, filled = {}, lines = {},
    }
    local font = {
        getTextWidth = function(self, t)
            return #t * 6
        end,
    }
    return {
        kColorBlack = 0,
        kColorWhite = 1,
        calls = calls,
        -- Hinweis: playdate.graphics-Methoden werden im Simulator OHNE Lua-Self
        -- aufgerufen (die C-Bindung normalisiert intern); der Mock bildet das
        -- exakt ab (Argumente = (x, y, r) bzw. (x, y, r, s, e)).
        clear = function(c) calls.clears = calls.clears + 1; calls.clearColor = c end,
        setColor = function() end,
        setLineWidth = function() end,
        setFont = function() end,
        setImageDrawMode = function() end,
        getSystemFont = function() return font end,
        drawText = function(t, x, y) calls.texts[#calls.texts + 1] = { text = t, x = x, y = y } end,
        drawArc = function(x, y, r, s, e) calls.arcs[#calls.arcs + 1] = { x = x, y = y, r = r, s = s, e = e } end,
        drawCircleAtPoint = function(x, y, r) calls.circles[#calls.circles + 1] = { x = x, y = y, r = r } end,
        fillCircleAtPoint = function(x, y, r) calls.filled[#calls.filled + 1] = { x = x, y = y, r = r } end,
        drawLine = function(x1, y1, x2, y2) calls.lines[#calls.lines + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end,
    }
end

-- Zeigt den Titel MIT Save (CONTINUE/NEW GAME/EXIT) und schließt die
-- Zeichenphase exakt ab (introT = Dauer), sodass alle Optionen gezeichnet
-- werden und A die Auswahl liefert.
local function showTitleReady()
    Menu.show(true)
    -- Über die Ring-Zeichenphase UND alle Item-Delays hinaus (0.72-0.80 s),
    -- damit alle Einträge sichtbar sind.
    Menu.update(Config.menuDrawDuration + 0.5)
end

-- Zeigt den Titel OHNE Save (NEW GAME/EXIT) und schließt die Zeichenphase ab.
local function showTitleReadyNoSave()
    Menu.show(false)
    Menu.update(Config.menuDrawDuration + 0.5)
end

-- --- initial aktiv, Zeichenphase läuft -------------------------------------
Menu.init()
Menu.show()
check(Menu.isActive() == true, "menu: aktiv nach show")
check(Menu.isFillPhase() == false and Menu.isRevealPhase() == false, "menu: nicht in Fill/Reveal nach show")
check(Menu.isIntroDone() == false, "menu: Zeichenphase läuft nach show")

-- --- Zeichenphase: A überspringt, aber keine Aktion -------------------------
pressed = {}
press(playdate.kButtonA)
check(Menu.update(0.1) == nil, "menu-draw: A während Zeichnen -> keine Aktion")
check(Menu.isIntroDone() == true, "menu-draw: A überspringt Zeichnen")
-- Andere Eingaben während der Zeichenphase ändern nichts.
Menu.show()
pressed = {}
press(playdate.kButtonDown)
press(playdate.kButtonB)
check(Menu.update(0.1) == nil, "menu-draw: Down/B während Zeichnen -> nil")

-- --- Vollständiger Ablauf: nach menuDrawDuration fertig ---------------------
Menu.show()
local steps = math.ceil(Config.menuDrawDuration / 0.1) + 1
for _ = 1, steps do Menu.update(0.1) end
check(Menu.isIntroDone() == true, "menu-draw: nach vollem Ablauf fertig")

-- --- MIT Save: Default-Auswahl CONTINUE, A -> "continue" ---------------------
showTitleReady()
check(Menu.selection == "continue", "menu: MIT Save Default-Auswahl = CONTINUE")
check(#Menu.items == 3, "menu: MIT Save 3 sichtbare Optionen")
pressed = {}
press(playdate.kButtonA)
check(Menu.update() == "continue", "menu: A im Idle bei CONTINUE -> continue")
check(Menu.update() == nil, "menu: A nur einmal (kein Doppel-Trigger)")

-- --- Navigation MIT Save: CONTINUE <-> NEW GAME <-> EXIT --------------------
showTitleReady()
pressed = {}
press(playdate.kButtonDown)
check(Menu.update() == nil, "menu-save: Down -> keine Aktion (nur Auswahl)")
check(Menu.selection == "newgame", "menu-save: Down -> Auswahl NEW GAME")
pressed = {}
press(playdate.kButtonDown)
check(Menu.update() == nil, "menu-save: Down -> keine Aktion (nur Auswahl)")
check(Menu.selection == "exit", "menu-save: Down -> Auswahl EXIT")
pressed = {}
press(playdate.kButtonA)
check(Menu.update() == "exit", "menu-save: A im Idle bei EXIT -> exit")
check(Menu.update() == nil, "menu-save: A bei EXIT nur einmal")
-- Zurück nach oben.
showTitleReady()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonUp)
check(Menu.update() == nil, "menu-save: Up -> keine Aktion (nur Auswahl)")
check(Menu.selection == "newgame", "menu-save: Up -> Auswahl NEW GAME")
pressed = {}
press(playdate.kButtonUp)
Menu.update()
check(Menu.selection == "continue", "menu-save: Up -> Auswahl CONTINUE")
-- Klemmt an den Enden: Up über CONTINUE / Down über EXIT hinaus.
pressed = {}
press(playdate.kButtonUp)
Menu.update()
check(Menu.selection == "continue", "menu-save: Up über CONTINUE hinaus bleibt CONTINUE")
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
check(Menu.selection == "exit", "menu-save: Down mehrfach bleibt EXIT")

-- --- OHNE Save: nur NEW GAME/EXIT, Default NEW GAME -------------------------
showTitleReadyNoSave()
check(#Menu.items == 2, "menu-nosave: OHNE Save 2 sichtbare Optionen")
check(Menu.selection == "newgame", "menu-nosave: Default-Auswahl = NEW GAME")
pressed = {}
press(playdate.kButtonA)
check(Menu.update() == "newgame", "menu-nosave: A bei NEW GAME -> newgame")
-- Navigation: Down -> EXIT, Up -> NEW GAME (CONTINUE nie erreichbar).
showTitleReadyNoSave()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
check(Menu.selection == "exit", "menu-nosave: Down -> EXIT")
pressed = {}
press(playdate.kButtonUp)
Menu.update()
check(Menu.selection == "newgame", "menu-nosave: Up -> NEW GAME")
-- Up über NEW GAME hinaus: bleibt NEW GAME (kein Sprung auf CONTINUE).
pressed = {}
press(playdate.kButtonUp)
Menu.update()
check(Menu.selection == "newgame", "menu-nosave: Up bleibt NEW GAME (CONTINUE unsichtbar)")

-- --- B / D-Pad links/rechts: keine Aktion, nichts kaputt ---------------------
showTitleReady()
pressed = {}
press(playdate.kButtonB)
check(Menu.update() == nil, "menu: B -> nil")
pressed = {}
press(playdate.kButtonLeft)
press(playdate.kButtonRight)
check(Menu.update() == nil, "menu: Left/Right -> nil")

-- --- inaktiv: update liefert nil -------------------------------------------
Menu.hide()
check(Menu.isActive() == false, "menu: hide -> inaktiv")
pressed = {}
press(playdate.kButtonA)
check(Menu.update() == nil, "menu: inaktiv -> update nil")

-- --- Fill-Lebenszyklus (Ring füllt sich nach innen) ------------------------
showTitleReady()
Menu.beginFill()
check(Menu.isFillPhase() == true, "menu-fill: nach beginFill isFillPhase")
check(Menu.isRevealPhase() == false, "menu-fill: nicht im Reveal")
check(Menu.getFillProgress() == 0, "menu-fill: Fortschritt 0 zu Beginn")
check(Menu.updateFill(Config.menuFillDuration / 2) == false, "menu-fill: halber Fill noch nicht fertig")
local pFillMid = Menu.getFillProgress()
check(pFillMid > 0 and pFillMid < 1, "menu-fill: Fortschritt zwischen 0 und 1")
check(Menu.updateFill(Config.menuFillDuration / 2 + 0.001) == true, "menu-fill: nach voller Dauer fertig")
check(Menu.getFillProgress() == 1, "menu-fill: Fortschritt 1 am Ende")
-- Eingabe während Fill gesperrt (keine A-Aktion).
showTitleReady()
Menu.beginFill()
pressed = {}
press(playdate.kButtonA)
check(Menu.update(0.1) == nil, "menu-fill: A während Fill -> nil")

-- --- Reveal-Lebenszyklus (Level zoomt aus dem Core heraus) ------------------
showTitleReady()
Menu.beginReveal(2.5)
check(Menu.isRevealPhase() == true, "menu-reveal: nach beginReveal isRevealPhase")
check(Menu.isFillPhase() == false, "menu-reveal: nicht im Fill")
check(Menu.getRevealScale() == 2.5, "menu-reveal: Skala = Startskala zu Beginn")
check(Menu.updateReveal(Config.menuRevealDuration / 2) == false, "menu-reveal: halber Reveal noch nicht fertig")
local sMid = Menu.getRevealScale()
check(sMid > 1 and sMid < 2.5, "menu-reveal: Skala zwischen Start und 1")
check(Menu.updateReveal(Config.menuRevealDuration / 2 + 0.001) == true, "menu-reveal: nach voller Dauer fertig")
check(Menu.getRevealScale() == 1, "menu-reveal: Skala 1 am Ende (Normalgröße)")
-- Eingabe während Reveal gesperrt.
pressed = {}
press(playdate.kButtonA)
check(Menu.update(0.1) == nil, "menu-reveal: A während Reveal -> nil")
Menu.hide()
Menu.show()

-- --- Read-only: kein Gameplay während Titel --------------------------------
State.init(Levels[1])
Room.init()
Undo.clear()
Bridge.resetTransit()
Room.resetDockAssist()
Camera.init(7)
showTitleReady()
local swBefore = {}
for k, v in pairs(State.switchStates) do swBefore[k] = v end
local elBefore = {}
for k, v in pairs(State.elementStates) do elBefore[k] = v end
local ringBefore = State.player.ring
local angleBefore = State.player.angle
local undoBefore = Undo.count()
local camBefore = Camera.getCurrentOuterRing()
-- Shutter-Runtime nur prüfen, wenn der Raum Blenden hat (Raum 1 = Einstieg
-- ohne Blenden; die Read-only-Eigenschaft gilt dann trivial).
local shBefore = Room.shutters["D1"] and Room.shutters["D1"].collisionActive
pressed = {}
press(playdate.kButtonA)
Menu.update()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
local mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
playdate.graphics = realGraphics
check(State.player.ring == ringBefore and State.player.angle == angleBefore, "menu read-only: player unverändert")
check(Undo.count() == undoBefore, "menu read-only: undo unverändert")
check(Camera.getCurrentOuterRing() == camBefore, "menu read-only: camera unverändert")
if Room.shutters["D1"] then
    check(Room.shutters["D1"].collisionActive == shBefore, "menu read-only: shutters unverändert")
end
local swSame = true
for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
check(swSame, "menu read-only: switchStates unverändert")
local elSame = true
for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
check(elSame, "menu read-only: elementStates unverändert")

-- --- GFX-Mock MIT Save: Ring + UNDERTOW + CONTINUE/NEW GAME/EXIT -------------
showTitleReady()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
check(mockG.calls.clears == 1 and mockG.calls.clearColor == 0, "menu draw: gfx.clear(kColorBlack)")
check(#mockG.calls.arcs >= 1, "menu draw: Ringbogen gezeichnet")
local hasContinue, hasNewGame, hasExit = false, false, false
for _, t in ipairs(mockG.calls.texts) do
    if t.text == "CONTINUE" then hasContinue = true end
    if t.text == "NEW GAME" then hasNewGame = true end
    if t.text == "EXIT" then hasExit = true end
end
-- Kein Titel über dem Kreis (bewusst entfernt): nur die Menüoptionen.
check(hasContinue, "menu draw: CONTINUE-Text gezeichnet")
check(hasNewGame, "menu draw: NEW GAME-Text gezeichnet")
check(hasExit, "menu draw: EXIT-Text gezeichnet")
-- CONTINUE ist Default -> genau EIN Auswahldreieck (3 Kanten) links von
-- CONTINUE (Spitze nach rechts, vertikal zur Zeilenbox mittig).
local fontC = playdate.graphics.getSystemFont()
local textLeftC = Config.menuTitleCenterX - math.floor(fontC:getTextWidth("CONTINUE") / 2)
local cyC = Config.menuContinueY + math.floor(Config.menuTextLineHeight * (Config.menuTextScale or 1) / 2)
local tipXC = textLeftC - Config.menuSelectionTriangleGap
local tipsC = 0
for _, l in ipairs(mockG.calls.lines) do
    if l.x1 == tipXC and l.y1 == cyC then tipsC = tipsC + 1 end
end
check(#mockG.calls.lines == 3, "menu draw: genau ein Auswahldreieck (3 Kanten)")
check(tipsC >= 2, "menu draw: Dreiecksspitze links vom CONTINUE-Text auf Zeilenhöhe")
playdate.graphics = realGraphics

-- --- GFX-Mock: bei EXIT-Auswahl wandert die Marke zu EXIT ---------------------
showTitleReady()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
check(Menu.selection == "exit", "menu draw: Auswahl EXIT gesetzt")
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
-- Bei EXIT-Auswahl wandert das Dreieck zur EXIT-Zeile.
local fontE = playdate.graphics.getSystemFont()
local textLeftE = Config.menuTitleCenterX - math.floor(fontE:getTextWidth("EXIT") / 2)
local cyE = Config.menuExitY + math.floor(Config.menuTextLineHeight * (Config.menuTextScale or 1) / 2)
local tipXE = textLeftE - Config.menuSelectionTriangleGap
local tipsE = 0
for _, l in ipairs(mockG.calls.lines) do
    if l.x1 == tipXE and l.y1 == cyE then tipsE = tipsE + 1 end
end
check(#mockG.calls.lines == 3, "menu draw: genau ein Auswahldreieck (EXIT)")
check(tipsE >= 2, "menu draw: Dreiecksspitze links vom EXIT-Text auf Zeilenhöhe")
playdate.graphics = realGraphics

-- --- GFX-Mock OHNE Save: nur NEW GAME/EXIT, KEIN CONTINUE --------------------
showTitleReadyNoSave()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
local hasContinueNoSave, hasNewGameNoSave, hasExitNoSave = false, false, false
for _, t in ipairs(mockG.calls.texts) do
    if t.text == "CONTINUE" then hasContinueNoSave = true end
    if t.text == "NEW GAME" then hasNewGameNoSave = true end
    if t.text == "EXIT" then hasExitNoSave = true end
end
check(hasNewGameNoSave and hasExitNoSave, "menu draw-nosave: NEW GAME + EXIT gezeichnet")
check(hasContinueNoSave == false, "menu draw-nosave: KEIN CONTINUE ohne Save")
-- NEW GAME ist Default -> genau ein Auswahldreieck links von NEW GAME.
local fontN = playdate.graphics.getSystemFont()
local textLeftN = Config.menuTitleCenterX - math.floor(fontN:getTextWidth("NEW GAME") / 2)
local cyN = Config.menuNoSaveNewGameY + math.floor(Config.menuTextLineHeight * (Config.menuTextScale or 1) / 2)
local tipXN = textLeftN - Config.menuSelectionTriangleGap
local tipsN = 0
for _, l in ipairs(mockG.calls.lines) do
    if l.x1 == tipXN and l.y1 == cyN then tipsN = tipsN + 1 end
end
check(#mockG.calls.lines == 3, "menu draw-nosave: genau ein Auswahldreieck (NEW GAME)")
check(tipsN >= 2, "menu draw-nosave: Dreiecksspitze links vom NEW GAME-Text auf Zeilenhöhe")
playdate.graphics = realGraphics

-- --- draw read-only: kein Zustandswechsel -----------------------------------
showTitleReady()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
Menu.draw()
playdate.graphics = realGraphics
check(Menu.isFillPhase() == false and Menu.isRevealPhase() == false, "menu draw read-only: kein Fill/Reveal gestartet")

-- --- drawFill (Mock): NUR die gefüllte Scheibe, kein Text ------------------
-- Starttransition: Menütext und Auswahldreieck verschwinden SOFORT bei
-- beginFill; drawFill zeichnet nur die sich nach innen füllende Scheibe
-- (weißer Kreis + schwarzes Innenloch, das schrumpft). Die Außenkante bleibt
-- exakt beim Titelring-Radius (keine Skalierung des Außenradius).
showTitleReady()
Menu.beginFill()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.drawFill()  -- Fill-Start: kein Text, nur die Scheibe + Innenloch
check(#mockG.calls.filled >= 2, "menu drawFill: weiße Scheibe + schwarzes Innenloch (Fill-Start)")
check(#mockG.calls.texts == 0, "menu drawFill: kein Text während des Fills")
playdate.graphics = realGraphics
Menu.updateFill(Config.menuFillDuration + 0.01)  -- Fill abgeschlossen
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.drawFill()
check(#mockG.calls.filled >= 1, "menu drawFill: vollständige Scheibe am Fill-Ende")
check(#mockG.calls.texts == 0, "menu drawFill: weiterhin kein Text")
playdate.graphics = realGraphics
Menu.hide()

-- Mocks restaurieren (Testumgebung sauber halten).
playdate.buttonJustPressed = realButtonJustPressed
playdate.graphics = realGraphics

TestReport.menu = { pass = pass, fail = fail }
