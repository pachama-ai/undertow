-- Tests für source/ui/menu.lua (Phase 10.1): Auswahl-/Aktionslogik und
-- read-only Verhalten. Die Menü-Zeichnung wird über einen GFX-Mock geprüft
-- (gfx.clear, Ring-/Bogenoperationen, Eintragstext, ringförmige Auswahl-
-- markierung). Kein Gameplay: Menu darf State/Undo/Room/Bridge/Camera nicht
-- verändern. Erwartet, dass core/config, core/geometry, core/state, core/undo,
-- world/room, world/bridge, data/levels, ui/render, ui/camera und ui/menu per
-- import geladen wurden (siehe tools/run_tests.ps1).

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
        circles = {}, filled = {}, arcs = {}, lines = {}, texts = {},
    }
    local font = {
        getTextWidth = function(self, t)
            return #t * 6
        end,
    }
    local g = {
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
        drawText = function(t, x, y) calls.texts[#calls.texts + 1] = { text = t, x = x, y = y } end,
        drawCircleAtPoint = function(x, y, r) calls.circles[#calls.circles + 1] = { x = x, y = y, r = r } end,
        fillCircleAtPoint = function(x, y, r) calls.filled[#calls.filled + 1] = { x = x, y = y, r = r } end,
        drawArc = function(x, y, r, s, e) calls.arcs[#calls.arcs + 1] = { x = x, y = y, r = r, s = s, e = e } end,
        drawLine = function(x1, y1, x2, y2) calls.lines[#calls.lines + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end,
        getSystemFont = function() return font end,
    }
    return g
end

local my1 = Config.menuEntryY1 + math.floor(Config.menuFontHeight / 2)
local my2 = Config.menuEntryY2 + math.floor(Config.menuFontHeight / 2)

-- Zeigt das Menü und schließt die Startanimation sofort ab (für die Eingabe-/
-- Zeichentests; die Intro-Logik wird separat getestet).
local function showMenuReady()
    Menu.show()
    Menu.update(Config.menuIntroDuration + 1)
end

-- --- initial aktiv + Initialauswahl Weiter ---------------------------------
Menu.init()
Menu.show()
check(Menu.isActive() == true, "menu: aktiv nach show")
check(Menu.getSelectedIndex() == 1, "menu: initial Weiter (Index 1)")

-- --- Reihenfolge / Anzahl / Labels / Aktionen ------------------------------
check(Menu.getEntryCount() == 2, "menu: genau 2 Einträge")
check(Menu.getEntryLabel(1) == "Weiter", "menu: Eintrag 1 = Weiter")
check(Menu.getEntryLabel(2) == "Von vorn", "menu: Eintrag 2 = Von vorn")
check(Menu.getEntryAction(1) == "continue", "menu: Aktion 1 = continue")
check(Menu.getEntryAction(2) == "restart", "menu: Aktion 2 = restart")

-- --- Startanimation (Intro) ------------------------------------------------
Menu.show()
check(Menu.isIntroDone() == false, "menu-intro: nach show noch nicht fertig")
Menu.update(0.1) -- 0,1 s
check(Menu.isIntroDone() == false, "menu-intro: nach 0,1 s noch nicht fertig")
-- Up/Down während der Intro ändern die Auswahl nicht (Einträge unsichtbar).
pressed = {}
press(playdate.kButtonDown)
check(Menu.update(0.1) == nil, "menu-intro: Down während Intro -> kein Effekt")
check(Menu.getSelectedIndex() == 1, "menu-intro: Auswahl bleibt 1 während Intro")
-- A überspringt das Intro, löst aber KEINE Aktion aus (kein Doppel-Trigger).
pressed = {}
press(playdate.kButtonA)
check(Menu.update(0.1) == nil, "menu-intro: A überspringt Intro ohne Aktion")
check(Menu.isIntroDone() == true, "menu-intro: nach A-Skip fertig")
-- Nach dem Skip funktioniert die normale Eingabe wieder.
pressed = {}
press(playdate.kButtonDown)
check(Menu.update(0.1) == nil, "menu-intro: Down nach Intro -> kein A")
check(Menu.getSelectedIndex() == 2, "menu-intro: Down nach Intro -> Von vorn")
-- Vollständiger Ablauf: nach menuIntroDuration ist das Intro fertig.
Menu.show()
local introSteps = math.ceil(Config.menuIntroDuration / 0.1) + 1
for _ = 1, introSteps do Menu.update(0.1) end
check(Menu.isIntroDone() == true, "menu-intro: nach vollem Ablauf fertig")

-- --- Down: Weiter -> Von vorn ----------------------------------------------
showMenuReady()
pressed = {}
press(playdate.kButtonDown)
check(Menu.update() == nil, "menu: Down ohne A -> nil")
check(Menu.getSelectedIndex() == 2, "menu: Down -> Von vorn")

-- --- Up: Von vorn -> Weiter ------------------------------------------------
pressed = {}
press(playdate.kButtonUp)
check(Menu.update() == nil, "menu: Up ohne A -> nil")
check(Menu.getSelectedIndex() == 1, "menu: Up -> Weiter")

-- --- Wraparound ------------------------------------------------------------
showMenuReady() -- Index 1 (Weiter)
pressed = {}
press(playdate.kButtonUp)
Menu.update()
check(Menu.getSelectedIndex() == 2, "menu: Weiter Up (Wrap) -> Von vorn")
pressed = {}
press(playdate.kButtonDown)
Menu.update()
check(Menu.getSelectedIndex() == 1, "menu: Von vorn Down (Wrap) -> Weiter")

-- --- A auf Weiter -> continue, genau einmal --------------------------------
showMenuReady() -- Index 1
pressed = {}
press(playdate.kButtonA)
local a1 = Menu.update()
check(a1 == "continue", "menu: A auf Weiter -> continue")
check(Menu.update() == nil, "menu: A nur einmal (kein Doppel-Trigger)")

-- --- A auf Von vorn -> restart ---------------------------------------------
showMenuReady()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonA)
check(Menu.update() == "restart", "menu: A auf Von vorn -> restart")

-- --- B: keine Aktion, Auswahl unverändert ----------------------------------
showMenuReady()
pressed = {}
press(playdate.kButtonB)
local beforeB = Menu.getSelectedIndex()
check(Menu.update() == nil, "menu: B -> nil")
check(Menu.getSelectedIndex() == beforeB, "menu: B ändert Auswahl nicht")

-- --- inaktiv: update liefert nil -------------------------------------------
Menu.hide()
check(Menu.isActive() == false, "menu: hide -> inaktiv")
pressed = {}
press(playdate.kButtonDown)
press(playdate.kButtonA)
check(Menu.update() == nil, "menu: inaktiv -> update nil")
showMenuReady()

-- --- Read-only / kein Gameplay während Menü --------------------------------
State.init(Levels[1])
Room.init()
Undo.clear()
Bridge.resetTransit()
Room.resetDockAssist()
Camera.init(7)
showMenuReady()
local swBefore = {}
for k, v in pairs(State.switchStates) do swBefore[k] = v end
local elBefore = {}
for k, v in pairs(State.elementStates) do elBefore[k] = v end
local ringBefore = State.player.ring
local angleBefore = State.player.angle
local undoBefore = Undo.count()
local camBefore = Camera.getCurrentOuterRing()
local shBefore = Room.shutters["D1"].collisionActive
pressed = {}
press(playdate.kButtonDown)
Menu.update()
pressed = {}
press(playdate.kButtonA)
Menu.update()
pressed = {}
press(playdate.kButtonUp)
Menu.update()
local mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
playdate.graphics = realGraphics
check(State.player.ring == ringBefore and State.player.angle == angleBefore, "menu read-only: player unverändert")
check(Undo.count() == undoBefore, "menu read-only: undo unverändert")
check(Camera.getCurrentOuterRing() == camBefore, "menu read-only: camera unverändert")
check(Room.shutters["D1"].collisionActive == shBefore, "menu read-only: shutters unverändert")
local swSame = true
for k, v in pairs(State.switchStates) do if swBefore[k] ~= v then swSame = false end end
for k, v in pairs(swBefore) do if State.switchStates[k] ~= v then swSame = false end end
check(swSame, "menu read-only: switchStates unverändert")
local elSame = true
for k, v in pairs(State.elementStates) do if elBefore[k] ~= v then elSame = false end end
for k, v in pairs(elBefore) do if State.elementStates[k] ~= v then elSame = false end end
check(elSame, "menu read-only: elementStates unverändert")

-- --- GFX-Mock: Zeichnung ----------------------------------------------------
-- schwarzer Hintergrund + Eintragstexte + Ringgrafik + ringförmige Markierung
showMenuReady() -- Index 1
pressed = {}
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
check(mockG.calls.clears == 1 and mockG.calls.clearColor == 0, "menu draw: gfx.clear(kColorBlack)")
local hasWeiter, hasVonvorn = false, false
for _, t in ipairs(mockG.calls.texts) do
    if t.text == "Weiter" then hasWeiter = true end
    if t.text == "Von vorn" then hasVonvorn = true end
end
check(hasWeiter and hasVonvorn, "menu draw: Einträge Weiter + Von vorn gezeichnet")
local circleOps = #mockG.calls.circles + #mockG.calls.filled + #mockG.calls.arcs
check(circleOps >= 4, "menu draw: mehrere Kreis-/Bogenoperationen (Ringgrafik)")
local filledMarkerY = nil
for _, f in ipairs(mockG.calls.filled) do
    if f.r == Config.menuMarkerRadius then filledMarkerY = f.y end
end
local emptyMarkerY = nil
for _, c in ipairs(mockG.calls.circles) do
    if c.r == Config.menuMarkerRadius then emptyMarkerY = c.y end
end
check(filledMarkerY == my1, "menu draw: Marker gefüllt an Weiter (aktiv)")
check(emptyMarkerY == my2, "menu draw: Marker leer an Von vorn (inaktiv)")

-- Auswahlwechsel -> Marker wechselt
showMenuReady()
pressed = {}
press(playdate.kButtonDown)
Menu.update()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
filledMarkerY = nil
emptyMarkerY = nil
for _, f in ipairs(mockG.calls.filled) do if f.r == Config.menuMarkerRadius then filledMarkerY = f.y end end
for _, c in ipairs(mockG.calls.circles) do if c.r == Config.menuMarkerRadius then emptyMarkerY = c.y end end
check(filledMarkerY == my2, "menu draw: Marker wechselt zu Von vorn (aktiv)")
check(emptyMarkerY == my1, "menu draw: Marker leer an Weiter (inaktiv)")
playdate.graphics = realGraphics

-- --- draw read-only: Auswahl unverändert -----------------------------------
showMenuReady()
local idxBefore = Menu.getSelectedIndex()
mockG = makeGfxMock()
playdate.graphics = mockG
Menu.draw()
Menu.draw()
playdate.graphics = realGraphics
check(Menu.getSelectedIndex() == idxBefore, "menu draw read-only: Auswahl unverändert")

-- Mocks restaurieren (Testumgebung sauber halten).
playdate.buttonJustPressed = realButtonJustPressed
playdate.graphics = realGraphics

TestReport.menu = { pass = pass, fail = fail }
