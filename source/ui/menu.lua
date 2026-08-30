-- Menu: reiner Titelbildschirm. Zeichnet einen großen DICKEN Ring mittig
-- (Zentrum = Spielwelt-Zentrum, fest verankert auf (200,120)), der sich beim
-- Erscheinen „selbst schreibt“ (Bogen 0° -> 360°, 0.5-1.0 s) und danach ruhig
-- steht (keine Atmung). KEIN Titel über dem Kreis — das Menü steht DIREKT IM
-- Kreis:
--   MIT gültigem Save:  CONTINUE / NEW GAME / EXIT (Default: CONTINUE)
--   OHNE Save:          NEW GAME / EXIT (CONTINUE wird komplett weggelassen)
-- Alle Einträge dauerhaft an (kein Blinken), Großbuchstaben, horizontal
-- mittig im Kreis, kompakte Zeilenabstände (~15 px hohe skalierte
-- Playdate-Schrift). D-Pad hoch/runter wechselt die sichtbare Auswahl (die
-- Auswahl kann NIE auf einer ausgeblendeten Option landen); der gewählte
-- Eintrag trägt ein kleines weißes, nach rechts zeigendes Dreieck links vom
-- Text (keine Box, kein Punkt, keine Unterstreichung). A bestätigt:
-- CONTINUE startet das zuletzt gespeicherte Level, NEW GAME startet Level 1
-- (Fortschritt wird zurückgesetzt), EXIT verlässt das Spiel sauber über die
-- offizielle Playdate-API (playdate.simulator.exit, Simulator).
-- STARTTRANSITION nach A (Bestätigung von CONTINUE/NEW GAME):
--   Phase FILL (0.5-0.55 s): Menütext und Auswahldreieck verschwinden SOFORT,
--   NUR der dicke Ring bleibt — exakt bei (200,120), exakt gleicher Außen-
--   radius (~90 px), KEINE Positionsänderung. Der Ring füllt sich nach innen:
--   der Innenradius schrumpft (normaler Ring -> dicker Ring -> sehr dicker
--   Ring -> kleines dunkles Loch -> vollständige helle Kreisscheibe). Die
--   Außenkante bleibt dabei unverändert.
--   Phase REVEAL (0.7-0.8 s): Die gefüllte Menü-Scheibe IST der Level-Core
--   (kein Schnitt, kein Kreis-entfernen-und-neu-zeichnen). Das komplette
--   Level (Core + Ringbahnen + Bridges + Player/Baby) zoomt um den festen
--   Mittelpunkt (200,120) von stark vergrößert auf Normalgröße: der Core
--   wird kleiner, Ringbögen kommen von den Bildschirmrändern ins Bild, die
--   Geometrie rastet weich auf Normalpositionen ein. Keine Kameraverschiebung,
--   kein Fade, kein Flash, keine Ripple-Ringe. main.lua wechselt erst nach
--   Reveal-Ende (Level in Normalgröße) auf das Gameplay.
-- KEIN Gameplay: Menu liest nur Eingabe (A/D-Pad), meldet "continue"/
-- "newgame"/"exit" und steuert Fill/Reveal. Es verändert weder State,
-- Undo, Room, Bridge, Gate, Camera noch Levels. Keine Projekt-Imports;
-- Config wird zentral in main.lua geladen. Ob ein Save existiert, teilt
-- main.lua über Menu.show(hasSave) mit (read-only Information, kein Datastore-
-- Zugriff im Menü).
-- playdate.graphics wird zur Laufzeit aufgelöst (testbar via Mock).

Menu = {}

local config <const> = Config

-- Titelzustand: "drawing" (Ring zeichnet sich) | "idle" (bereit) |
-- "fill" (Ring füllt sich nach innen, Eingabe gesperrt) |
-- "reveal" (Level zoomt aus dem Core heraus, Eingabe gesperrt).
local state = "drawing"
local active = false

-- Ausgewählter Menüeintrag: "continue" | "newgame" | "exit". Default beim
-- Öffnen: "continue" mit Save, sonst "newgame".
Menu.selection = "newgame"

-- Existiert ein gültiger Spielfortschritt? (CONTINUE nur dann anzeigen.)
Menu.hasSave = false

-- Sichtbare Menüeinträge (in Anzeige-Reihenfolge):
-- { id, text, y, delay } — wird in Menu.show(hasSave) befüllt.
Menu.items = {}

-- Intro-Zeit seit show() (Zeichenphase + Idle). Bleibt während Fill/Reveal
-- stehen (nur für die Titel-Zeichnung relevant).
Menu.introT = 0

-- Fill-Zeit seit beginFill() (s). Rein visuell; kein Gameplay-Effekt.
Menu.fillT = 0

-- Reveal-Zeit seit beginReveal() (s) + Startskala (Core = Menü-Scheibe).
Menu.revealT = 0
Menu.revealFrom = 1

-- Weiche Interpolation 0..1 (Smoothstep, deterministisch; wie Kamera/Outro).
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Fortschritt 0..1 der Ring-Zeichenanimation (0 = leer, 1 = voller Ring).
local function drawProgress()
    local d = config.menuDrawDuration
    return d > 0 and math.min(1, math.max(0, Menu.introT) / d) or 1
end

-- Initialisiert das Menü auf Neutral (nicht aktiv, Zeichenphase).
function Menu.init()
    active = false
    state = "drawing"
    Menu.introT = 0
    Menu.fillT = 0
    Menu.revealT = 0
    Menu.revealFrom = 1
end

-- Zeigt den Titelbildschirm (Zeichenanimation startet neu). hasSave (optional,
-- Default false): ob ein gültiger Spielfortschritt existiert. MIT Save werden
-- CONTINUE/NEW GAME/EXIT gezeigt (Default: CONTINUE), OHNE Save nur
-- NEW GAME/EXIT (Default: NEW GAME). Die Auswahl startet immer auf einer
-- sichtbaren Option.
function Menu.show(hasSave)
    active = true
    state = "drawing"
    Menu.introT = 0
    Menu.fillT = 0
    Menu.revealT = 0
    Menu.revealFrom = 1
    Menu.hasSave = hasSave == true
    if Menu.hasSave then
        Menu.items = {
            { id = "continue", text = "CONTINUE", y = config.menuContinueY, delay = config.menuContinueDelay },
            { id = "newgame",  text = "NEW GAME",  y = config.menuNewGameY,  delay = config.menuNewGameDelay },
            { id = "exit",     text = "EXIT",      y = config.menuExitY,     delay = config.menuExitDelay },
        }
        Menu.selection = "continue"
    else
        Menu.items = {
            { id = "newgame", text = "NEW GAME", y = config.menuNoSaveNewGameY, delay = config.menuNoSaveNewGameDelay },
            { id = "exit",    text = "EXIT",     y = config.menuNoSaveExitY,    delay = config.menuNoSaveExitDelay },
        }
        Menu.selection = "newgame"
    end
end

-- Blendet den Titelbildschirm aus.
function Menu.hide()
    active = false
end

-- Ist der Titelbildschirm gerade aktiv?
function Menu.isActive()
    return active
end

-- Ist die Ring-Zeichenanimation abgelaufen? (Eingabe vollständig frei)
function Menu.isIntroDone()
    return Menu.introT >= config.menuDrawDuration
end

-- Läuft gerade die Fill-Phase (Ring füllt sich nach innen)?
function Menu.isFillPhase()
    return state == "fill"
end

-- Läuft gerade die Reveal-Phase (Level zoomt aus dem Core heraus)?
function Menu.isRevealPhase()
    return state == "reveal"
end

-- Startet die Fill-Phase (von main.lua nach der Bestätigung). Menütext und
-- Auswahldreieck sind ab sofort weg; nur noch Ring/Fill/Reveal werden
-- gezeichnet.
function Menu.beginFill()
    state = "fill"
    Menu.fillT = 0
end

-- Schaltet die Fill-Phase weiter. Rückgabe true, wenn der Ring vollständig
-- zur Scheibe gefüllt ist (dann startet main.lua den Reveal).
function Menu.updateFill(dt)
    if state ~= "fill" then
        return true
    end
    Menu.fillT = (Menu.fillT or 0) + (dt or 0)
    return Menu.fillT >= config.menuFillDuration
end

-- Eased Fill-Fortschritt 0..1 (linear: stetiges Schließen des Innenlochs).
function Menu.getFillProgress()
    local d = config.menuFillDuration
    if d <= 0 then
        return 1
    end
    return math.min(1, math.max(0, (Menu.fillT or 0)) / d)
end

-- Startet die Reveal-Phase. fromScale = Start-Skalierung (>1), bei der der
-- Level-Core exakt die Größe der gefüllten Menü-Scheibe hat (s0 =
-- menuTitleOuterRadius / Kernradius des Raums) — dadurch geht die Scheibe
-- nahtlos in den Core über.
function Menu.beginReveal(fromScale)
    state = "reveal"
    Menu.revealT = 0
    Menu.revealFrom = fromScale or 1
end

-- Schaltet die Reveal-Phase weiter. Rückgabe true, wenn das Level Normalgröße
-- erreicht hat (dann übernimmt main.lua das Gameplay).
function Menu.updateReveal(dt)
    if state ~= "reveal" then
        return true
    end
    Menu.revealT = (Menu.revealT or 0) + (dt or 0)
    return Menu.revealT >= config.menuRevealDuration
end

-- Eased Reveal-Skalierung 1..fromScale (Smoothstep): Start beim Core =
-- Menü-Scheibe, weich herauszoomen bis 1.0 (Normalgröße). Kein Overshoot.
function Menu.getRevealScale()
    local d = config.menuRevealDuration
    if d <= 0 then
        return 1
    end
    local raw = math.min(1, math.max(0, (Menu.revealT or 0)) / d)
    local eased = smoothstep(raw)
    local s0 = Menu.revealFrom or 1
    return s0 + (1 - s0) * eased
end

-- Liest die Titelbildschirm-Eingabe und schaltet die Zeichen-/Idle-Phase
-- weiter. dt = Frame-Dauer.
--   D-Pad hoch/runter: wechselt die Auswahl zwischen den SICHTBAREN Optionen
--     (CONTINUE/NEW GAME/EXIT bzw. NEW GAME/EXIT; auch während der Zeichen-
--     phase; Just-Pressed, kein Halte-Wiederholen). Die Auswahl bleibt immer
--     auf einer sichtbaren Option (kein Sprung auf eine ausgeblendete).
--   A: während der Zeichenphase überspringt A die Animation (keine Aktion,
--     kein Doppel-Trigger); im Idle bestätigt A den ausgewählten Eintrag
--     (Rückgabe "continue" | "newgame" | "exit").
-- Andere Eingaben (B, D-Pad links/rechts, Crank) haben KEINE Aktion und
-- brechen nichts ab. Gehaltene Tasten lösen dank justPressed nur einmal aus.
-- Rückgabe: "continue" | "newgame" | "exit" | nil.
function Menu.update(dt)
    if not active or state == "fill" or state == "reveal" then
        return nil
    end
    Menu.introT = (Menu.introT or 0) + (dt or 0)
    local drawing = Menu.introT < config.menuDrawDuration
    -- Navigation über die sichtbaren Optionen (Just-Pressed, genau ein
    -- Wechsel pro Druck; klemmt an den Enden, kein Zyklus).
    local idx = nil
    for i, item in ipairs(Menu.items) do
        if item.id == Menu.selection then
            idx = i
            break
        end
    end
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        if idx and idx > 1 then
            Menu.selection = Menu.items[idx - 1].id
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        if idx and idx < #Menu.items then
            Menu.selection = Menu.items[idx + 1].id
        end
    end
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if drawing then
            Menu.introT = config.menuDrawDuration -- A überspringt das Zeichnen
        else
            return Menu.selection
        end
    end
    return nil
end

-- Weißer Text (1-Bit-Notlösung): playdate.graphics.drawText malt in diesem
-- SDK IMMER schwarz (setColor/setImageDrawMode wirken nicht auf Text). Für
-- weißen Text: in ein Clear-Image rendern (imageWithText) und invertiert
-- zeichnen. playdate.graphics wird zur LAUFZEIT aufgelöst, damit der
-- Test-Mock (der kein imageWithText kennt) über den drawText-Fallback weiter
-- funktioniert.
local function drawTextWhite(text, x, y, scale)
    local g = playdate.graphics
    if g.imageWithText ~= nil then
        local img = g.imageWithText(tostring(text), 400, 240, g.kColorClear)
        if img then
            -- Skalierung für ~15 px hohe Schrift (Systemfont ist 20 px).
            local s = scale or 1
            if s ~= 1 and img.scaledImage ~= nil then
                img = img:scaledImage(s, s)
            end
            g.setImageDrawMode(g.kDrawModeInverted)
            img:draw(math.floor(x), math.floor(y))
            g.setImageDrawMode(g.kDrawModeCopy)
            return
        end
    end
    if g.drawText ~= nil then
        g.drawText(tostring(text), math.floor(x), math.floor(y))
    end
end

-- Menüeintrag (CONTINUE/NEW GAME/EXIT): horizontal mittig im Kreis,
-- dauerhaft an (kein Blinken), ~15 px hohe skalierte Playdate-Schrift. Der
-- AUSGEWÄHLTE Eintrag trägt ein kleines weißes, nach rechts zeigendes Dreieck
-- links vom Text (vertikal zur Zeilenbox mittig). Keine Box, kein Punkt,
-- keine Unterstreichung.
local function drawMenuEntry(text, y, selected)
    local gfx = playdate.graphics
    local font = gfx.getSystemFont()
    gfx.setFont(font)
    gfx.setColor(gfx.kColorWhite)
    local scale = config.menuTextScale or 1
    local tw = font:getTextWidth(text) * scale
    local x = config.menuTitleCenterX - math.floor(tw / 2)
    drawTextWhite(text, x, y, scale)
    -- Auswahldreieck: kleines weißes Dreieck, Spitze nach rechts, links vom
    -- gewählten Eintrag (3 Kanten; fillPolygon benötigt ein geometry.polygon).
    if selected then
        local lineH = config.menuTextLineHeight * scale
        local cy = y + math.floor(lineH / 2)
        local len = config.menuSelectionTriangleSize
        local half = config.menuSelectionTriangleHalf
        local gap = config.menuSelectionTriangleGap
        local tipX = x - gap
        if gfx.drawLine then
            gfx.drawLine(tipX, cy, tipX - len, cy - half)
            gfx.drawLine(tipX, cy, tipX - len, cy + half)
            gfx.drawLine(tipX - len, cy - half, tipX - len, cy + half)
        end
    end
end

-- Zeichnet den kompletten Titelbildschirm (Bildschirm-Clearing inklusive).
-- Read-only: verändert weder Auswahl noch State, nur zeichnen.
function Menu.draw()
    local gfx = playdate.graphics
    gfx.clear(gfx.kColorBlack)
    local cx = config.menuTitleCenterX
    local cy = config.menuTitleCenterY

    -- Großer dicker Ring „schreibt sich selbst“ (Bogen 0° -> 360°) und steht
    -- danach ruhig (keine Atmung, kein Pulsieren). Dicke Linie = bewusst
    -- pixelige Playdate-Kante, kein dünner Vektorkreis. Kein Titel über dem
    -- Kreis; das Menü steht direkt IM Kreis.
    local p = drawProgress()
    local radius = config.menuTitleOuterRadius
    local span = smoothstep(p) * 360
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(config.menuTitleLineWidth)
    if span > 0.5 then
        gfx.drawArc(cx, cy, radius, 0, span)
    end
    gfx.setLineWidth(1)

    -- Menütext erscheint nach dem Ring (gestaffelt je item.delay), dauerhaft
    -- an (kein Blinken), horizontal mittig im Kreis.
    for _, item in ipairs(Menu.items) do
        local itemT = smoothstep(math.min(1, math.max(0, Menu.introT - item.delay) / 0.25))
        if itemT > 0 then
            drawMenuEntry(item.text, item.y, Menu.selection == item.id)
        end
    end
end

-- Zeichnet während der Fill-Phase: NUR die gefüllte Scheibe (Menütext und
-- Auswahldreieck sind bereits verschwunden). Die AUSSENKANTE bleibt exakt
-- beim Titelring-Radius (~90 px, keine Positions-/Größenänderung); nur der
-- Innenradius schrumpft bis auf 0 -> vollständig gefüllte helle Kreisscheibe
-- an exakt derselben Position. Diese Scheibe wird (im Reveal) direkt zum
-- Level-Core.
function Menu.drawFill()
    local gfx = playdate.graphics
    local cx = config.menuTitleCenterX
    local cy = config.menuTitleCenterY
    local outer = config.menuTitleOuterRadius
    local p = Menu.getFillProgress()
    local inner = (outer - config.menuTitleLineWidth) * (1 - p)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, outer)
    if inner > 0.5 then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(cx, cy, inner)
    end
end

return Menu
