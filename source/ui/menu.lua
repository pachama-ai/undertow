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
-- Startanimation (neuer Startbildschirm): abgelaufene Intro-Zeit seit show().
Menu.introT = 0

-- Initialisiert das Menü auf Neutral (nicht aktiv, Initialauswahl „Weiter").
function Menu.init()
    active = false
    selectedIndex = 1
    Menu.introT = 0
end

-- Zeigt das Menü (Initialauswahl „Weiter") und startet die Intro-Animation neu.
function Menu.show()
    active = true
    selectedIndex = 1
    Menu.introT = 0
end

-- Blendet das Menü aus.
function Menu.hide()
    active = false
end

-- Ist die Menü-Startanimation bereits abgelaufen? (Eingaben freigegeben)
function Menu.isIntroDone()
    return Menu.introT >= config.menuIntroDuration
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

-- Liest die Menüeingabe und schaltet die Startanimation weiter. dt = Frame-
-- dauer. Während der Intro-Animation ist die Auswahl gesperrt (kein blindes
-- Weiterschalten auf unsichtbaren Einträgen); A überspringt das Intro (ohne
-- die Aktion auszulösen, kein Doppel-Trigger). Nach dem Intro: D-Pad hoch/
-- runter und A (jeweils justPressed) wechseln die Auswahl; Rückgabe nur bei
-- Bestätigung: "continue" | "restart", sonst nil. B hat im Startmenü KEINE
-- Aktion. Gehaltene Tasten lösen dank justPressed nur einmal aus.
function Menu.update(dt)
    if not active then
        return nil
    end
    -- Startanimation fortschreiben; A überspringt sie (kein Start).
    local skippedByA = false
    if Menu.introT < config.menuIntroDuration then
        Menu.introT = Menu.introT + (dt or 0)
        if playdate.buttonJustPressed(playdate.kButtonA) then
            Menu.introT = config.menuIntroDuration
            skippedByA = true
        end
        if Menu.introT < config.menuIntroDuration then
            return nil -- Intro läuft: keine Auswahl, keine Aktion
        end
    end
    if skippedByA then
        return nil -- A hat das Intro in DIESEM Frame übersprungen: keine Aktion
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

-- Weiche Interpolation 0..1 (Smoothstep, deterministisch; wie Kamera/Outro).
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Zeichnet das komplette Startmenü (Bildschirm-Clearing inklusive) inklusive
-- der Startanimation (neuer Startbildschirm). Read-only: verändert die
-- Auswahl nicht, nur zeichnen.
function Menu.draw()
    local gfx = playdate.graphics
    gfx.clear(gfx.kColorBlack)
    local cx = config.menuTitleCenterX
    local cy = config.menuTitleCenterY
    local d = config.menuIntroDuration

    -- Fortschritt 0..1 der Startanimation; t = 1 -> vollständiges Menü.
    local t = d > 0 and math.min(1, Menu.introT / d) or 1

    -- Ringe bauen sich auf (Bogen 0° -> 360°), ruhig und reduziert.
    local outerSpan = smoothstep(math.min(1, math.max(0, Menu.introT) / (d * 0.40))) * 360
    local innerSpan = smoothstep(math.min(1, math.max(0, Menu.introT - d * 0.25) / (d * 0.45))) * 360
    local pathP = smoothstep(math.min(1, math.max(0, Menu.introT - d * 0.55) / (d * 0.20)))
    local coreP = smoothstep(math.min(1, math.max(0, Menu.introT - d * 0.5) / (d * 0.20)))

    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(config.menuTitleLineWidth)
    if outerSpan > 0.5 then
        gfx.drawArc(cx, cy, config.menuTitleOuterRadius, 0, outerSpan)
    end
    if innerSpan > 0.5 then
        gfx.drawArc(cx, cy, config.menuTitleInnerRadius, 0, innerSpan)
    end
    -- Pfad-Andeutung + Brücken-Andeutung (erscheinen, wenn beide Ringe da sind)
    if pathP > 0 then
        gfx.drawArc(cx, cy, config.menuTitleArcRadius, config.menuTitleArcStart, config.menuTitleArcEnd)
        local bx1, by1 = geo.polar(cx, cy, config.menuTitleInnerRadius, config.menuTitleBridgeAngle)
        local bx2, by2 = geo.polar(cx, cy, config.menuTitleOuterRadius, config.menuTitleBridgeAngle)
        gfx.drawLine(bx1, by1, bx2, by2)
    end
    -- Kern: wächst sanft ein
    if coreP > 0 then
        gfx.fillCircleAtPoint(cx, cy, math.max(1, config.menuTitleCoreRadius * coreP))
    end
    gfx.setLineWidth(1)

    -- Titel (VERSALIEN): gleitet von oben in Position, sobald er freigegeben ist.
    local titleP = smoothstep(math.min(1, math.max(0, Menu.introT - config.menuIntroTitleDelay) / 0.3))
    if titleP > 0 then
        gfx.setFont(gfx.getSystemFont())
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        local tw = #config.menuTitleText * config.menuTitleCharW
        local ty = config.menuTitleY - (1 - titleP) * 16
        gfx.drawText(config.menuTitleText, cx - math.floor(tw / 2), ty)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end

    -- Einträge unterhalb der Titelgrafik mit ringförmiger Auswahlmarkierung:
    -- aktiv = gefüllter kleiner Ring, inaktiv = leerer Ring. Gleiten von unten
    -- ein. Playdate-Fonts sind schwarz-auf-transparent; für weiß-auf-schwarz
    -- Text muss der Zeichenmodus auf kDrawModeFillWhite stehen.
    local itemsP = smoothstep(math.min(1, math.max(0, Menu.introT - config.menuIntroItemsDelay) / 0.35))
    if itemsP > 0 then
        local font = gfx.getSystemFont()
        gfx.setFont(font)
        gfx.setColor(gfx.kColorWhite)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        local slide = (1 - itemsP) * 24
        for i, item in ipairs(ITEMS) do
            local y = ((i == 1) and config.menuEntryY1 or config.menuEntryY2) + slide
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
end

return Menu
