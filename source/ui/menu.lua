-- Menu: reines UI-Modul für das Startmenü (Phase 10.1). Zeichnet eine 1-Bit-
-- Ring-Titelgrafik und zwei Einträge („Weiter", „Von vorn"). KEIN Gameplay:
-- Menu liest ausschließlich Eingabe (D-Pad hoch/runter, A), wechselt die
-- Auswahl und meldet eine Aktion an den Composition Root ("continue" |
-- "restart"). Es verändert weder State, Undo, Room, Bridge, Gate, Camera noch
-- Levels; keine Datastore-/Systemmenü-/Save-Logik (kommt in 10.2/10.3).
-- Keine Projekt-Imports; Config und Geometry werden zentral in main.lua
-- geladen. playdate.graphics wird zur Laufzeit aufgelöst (testbar via Mock).
--
-- Aktionssemantik (bewusst getrennt): "continue" und "restart" sind zwei
-- verschiedene Aktionen, auch wenn bis 10.2 beide Raum 1 starten. So kann
-- 10.2 die Continue-Auflösung (höchster erreichter Raum) ersetzen, ohne das
-- Menü umzubauen.

Menu = {}

local config <const> = Config
local geo <const> = Geometry

-- Einträge: exakt zwei, Reihenfolge verbindlich (Index 1 = „Weiter").
local ITEMS <const> = {
    { label = "Weiter",   action = "continue" },
    { label = "Von vorn", action = "restart" },
}

-- Menüzustand (rein UI-intern, keine Gameplay-Wahrheit).
local active = false
local selectedIndex = 1

-- Initialisiert das Menü auf Neutral (nicht aktiv, Initialauswahl „Weiter").
function Menu.init()
    active = false
    selectedIndex = 1
end

-- Zeigt das Menü (Initialauswahl „Weiter").
function Menu.show()
    active = true
    selectedIndex = 1
end

-- Blendet das Menü aus.
function Menu.hide()
    active = false
end

-- Ist das Menü gerade aktiv?
function Menu.isActive()
    return active
end

-- Aktuell ausgewählter Index (1 = „Weiter", 2 = „Von vorn").
function Menu.getSelectedIndex()
    return selectedIndex
end

-- Anzahl der Einträge (verbindlich 2).
function Menu.getEntryCount()
    return #ITEMS
end

-- Label eines Eintrags (1-basiert): "Weiter" | "Von vorn".
function Menu.getEntryLabel(index)
    return ITEMS[index].label
end

-- Aktion eines Eintrags (1-basiert): "continue" | "restart".
function Menu.getEntryAction(index)
    return ITEMS[index].action
end

-- Liest die Menüeingabe (D-Pad hoch/runter und A, jeweils justPressed) und
-- wechselt die Auswahl. Rückgabe nur bei Bestätigung: "continue" | "restart",
-- sonst nil. B hat im Startmenü KEINE Aktion. Gehaltene Tasten lösen dank
-- justPressed nur einmal aus (kein Frame-weise Weiterschalten).
function Menu.update()
    if not active then
        return nil
    end
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then
            selectedIndex = #ITEMS -- Wraparound: Von vorn -> Weiter
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #ITEMS then
            selectedIndex = 1 -- Wraparound: Weiter -> Von vorn -> Weiter
        end
    end
    if playdate.buttonJustPressed(playdate.kButtonA) then
        return ITEMS[selectedIndex].action
    end
    return nil
end

-- Ring-Titelgrafik: schwarzer Hintergrund, weiße konzentrische Ringformen,
-- Kern und Brücken-Andeutung. Reduziert/mysteriös, keine spielbare Szene,
-- keine Switch-/Puzzleinformation. Rein prozedural (keine Bilddatei).
local function drawTitle(gfx, cx, cy)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(config.menuTitleLineWidth)
    gfx.drawCircleAtPoint(cx, cy, config.menuTitleOuterRadius)
    gfx.drawCircleAtPoint(cx, cy, config.menuTitleInnerRadius)
    -- Pfad-Andeutung: kurzer Bogen zwischen den Ringen (unterer Bereich)
    gfx.drawArc(cx, cy, config.menuTitleArcRadius, config.menuTitleArcStart, config.menuTitleArcEnd)
    -- Brücken-Andeutung: radialer Strich zwischen innerem und äußerem Ring
    local bx1, by1 = geo.polar(cx, cy, config.menuTitleInnerRadius, config.menuTitleBridgeAngle)
    local bx2, by2 = geo.polar(cx, cy, config.menuTitleOuterRadius, config.menuTitleBridgeAngle)
    gfx.drawLine(bx1, by1, bx2, by2)
    -- Kern
    gfx.fillCircleAtPoint(cx, cy, config.menuTitleCoreRadius)
    gfx.setLineWidth(1)
end

-- Zeichnet das komplette Startmenü (Bildschirm-Clearing inklusive). Read-only:
-- verändert die Auswahl nicht, nur zeichnen.
function Menu.draw()
    local gfx = playdate.graphics
    gfx.clear(gfx.kColorBlack)
    drawTitle(gfx, config.menuTitleCenterX, config.menuTitleCenterY)

    -- Einträge unterhalb der Titelgrafik mit ringförmiger Auswahlmarkierung:
    -- aktiv = gefüllter kleiner Ring, inaktiv = leerer Ring. Klar bei 400×240.
    -- Playdate-Fonts sind schwarz-auf-transparent definiert; für weiß-auf-
    -- schwarz-Text muss der Zeichenmodus auf kDrawModeFillWhite stehen (sonst
    -- bleibt der Text schwarz und ist auf dem schwarzen Menü unsichtbar).
    local font = gfx.getSystemFont()
    gfx.setFont(font)
    gfx.setColor(gfx.kColorWhite)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    for i, item in ipairs(ITEMS) do
        local y = (i == 1) and config.menuEntryY1 or config.menuEntryY2
        local tw = font:getTextWidth(item.label)
        local tx = config.menuEntryX - math.floor(tw / 2)
        gfx.drawText(item.label, tx, y)
        local mx = tx - config.menuMarkerOffset
        local my = y + math.floor(config.menuFontHeight / 2)
        if i == selectedIndex then
            gfx.fillCircleAtPoint(mx, my, config.menuMarkerRadius)
        else
            gfx.drawCircleAtPoint(mx, my, config.menuMarkerRadius)
        end
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

return Menu
