-- textui.lua — kleines, wiederverwendbares Text-/Layout-System für alle
-- Erklär- und Tutorial-Screens (1-Bit, schwarz/weiß).
--
-- Warum: (1) Die Playdate-System-Font (Roobert-20) enthält KEINE Umlaut-
-- Glyphen — ä/ö/ü/Ä/Ö/Ü/ß rendern als Ersatzzeichen. Lösung: die gebündelte
-- Asheville-Rounded-24-Font (Playdate-Systemfont, weich/freundlich/ruhig,
-- leicht rund — AUFTRAG „natuerlichere Schrift") wird geladen und für allen
-- Text genutzt. Alle sichtbaren Spieltexte sind englisch (keine Umlaute
-- mehr noetig). (2) playdate.graphics.drawText malt in diesem SDK IMMER
-- schwarz (setColor wirkt nicht auf Text). Lösung: Text in ein Clear-Image
-- rendern (imageWithText) und mit invertiertem DrawMode zeichnen — weiße
-- Glyphen auf schwarzem Grund.
--
-- API:
--   TextUI.font                   -> geladene Font (nil = Systemfont-Fallback)
--   TextUI.textWidth(text)        -> Textbreite in px (UTF-8-sicher)
--   TextUI.drawText(text, x, y)   -> weißer Text, linksbündig
--   TextUI.drawTextCentered(text, y) -> weißer Text, zentriert (Mitte 200)
--   TextUI.wrap(text, maxWidth)   -> Zeilenliste (Wortgrenzen, UTF-8-sicher)
--   TextUI.drawTextStack(y, heading, text1, text2, hint)
--                                 -> zentrierter Standard-Text-Stapel mit
--                                    festem, großzügigem Zeilenabstand

TextUI = {}

local gfx = playdate.graphics

-- Gebündelte Playdate-Systemfont (Asheville Rounded 24, aus dem SDK in das
-- Projekt kopiert) laden (defensiv). Fehlt sie, bleibt nil und der
-- System-Font fällt zurück (ohne Umlaute, aber ohne Crash). Basis-Hoehe 24 px
-- (Zelle 32 px); die natuerlichere Schrift fuer Tutorial-/Room-UI (AUFTRAG).
local font = nil
pcall(function()
    font = gfx.font.new("font/Asheville-Rounded-24-px")
end)
TextUI.font = font

-- FEINE Schrift für die untere Infoleiste (AUFTRAG „fein, ruhig, gut lesbar").
-- Asheville-Sans-14-Bold: natürliche 14 px, KEINE Skalierung (scharf, kein
-- grober Downscale-Artefakt), weich/ruhig, gleiche Asheville-Familie. Nur für
-- die Info-/Hinweis-Leiste; TextUI.font (Rounded 24) bleibt für Titel/ROOM.
local barFont = nil
pcall(function()
    barFont = gfx.font.new("font/Asheville-Sans-14-Bold")
end)
TextUI.barFont = barFont

-- Effektive Font: eigene (mit Umlauten) oder Systemfont.
local function effectiveFont()
    return font or gfx.getSystemFont()
end

-- Effektive LEISTEN-Font (feine 14-px-Asheville) oder Systemfont.
local function effectiveBarFont()
    return barFont or gfx.getSystemFont()
end

-- Textbreite der feinen Leisten-Font messen (UTF-8-sicher).
function TextUI.barTextWidth(text)
    if not text then
        return 0
    end
    return effectiveBarFont():getTextWidth(text)
end

-- Weißer Text mit der feinen Leisten-Font (natürliche 14 px, keine Skalierung).
function TextUI.drawBarText(text, x, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, effectiveBarFont())
    if not img then
        return
    end
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor(x), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Weißer Text, rechtsbündig (rechte Kante bei rightX) mit der Leisten-Font.
function TextUI.drawBarTextRight(text, rightX, y)
    if not text then
        return
    end
    local w = TextUI.barTextWidth(text)
    TextUI.drawBarText(text, rightX - w, y)
end

-- Textbreite messen (UTF-8-sicher über die Font).
function TextUI.textWidth(text)
    if not text then
        return 0
    end
    return effectiveFont():getTextWidth(text)
end

-- Weißer Text, linksbündig. Render-Trick: imageWithText (Clear-Image) +
-- invertierter DrawMode -> weiße Glyphen.
function TextUI.drawText(text, x, y)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, effectiveFont())
    if not img then
        return
    end
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor(x), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Weißer Text, zentriert (Mitte 200).
function TextUI.drawTextCentered(text, y)
    if not text then
        return
    end
    local w = TextUI.textWidth(text)
    TextUI.drawText(text, math.floor((400 - w) / 2), y)
end

-- Weißer Text mit Skalierung (für kompakte Element-Erklär-Screens: kleine,
-- konsistente Schrift, damit auch 2 Erklärzeilen unterhalb eines Fokus-
-- Fensters passen). scale < 1 verkleinert die 22-px-Font (0.82 -> ~18 px).
function TextUI.drawTextScaled(text, x, y, scale)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, effectiveFont())
    if not img then
        return
    end
    if scale ~= 1 and img.scaledImage ~= nil then
        img = img:scaledImage(scale, scale)
    end
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor(x), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Skalierter weißer Text, zentriert (Mitte 200).
function TextUI.drawTextCenteredScaled(text, y, scale)
    if not text then
        return
    end
    local img = gfx.imageWithText(tostring(text), 400, 240, gfx.kColorClear, nil, nil, kTextAlignment.left, effectiveFont())
    if not img then
        return
    end
    if scale ~= 1 and img.scaledImage ~= nil then
        img = img:scaledImage(scale, scale)
    end
    local w = img:getSize()
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    img:draw(math.floor((400 - w) / 2), math.floor(y))
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Text an Wortgrenzen auf maxWidth umbrechen (UTF-8-sicher: Wörter werden an
-- Leerzeichen getrennt, nie mitten in einem Zeichen).
function TextUI.wrap(text, maxWidth)
    local lines = {}
    if not text or text == "" then
        return lines
    end
    for word in (text .. " "):gmatch("(%S+)%s*") do
        local current = lines[#lines]
        if current and TextUI.textWidth(current .. " " .. word) <= maxWidth then
            lines[#lines] = current .. " " .. word
        else
            lines[#lines + 1] = word
        end
    end
    return lines
end

-- Standard-Text-Stapel (zentriert): Überschrift, Erklärung (1-2 Zeilen),
-- Eingabehinweis — mit festem, großzügigem Zeilenabstand (32/30/32 px).
-- y = obere Kante der Überschrift.
function TextUI.drawTextStack(y, heading, text1, text2, hint)
    if heading then
        TextUI.drawTextCentered(heading, y)
    end
    if text1 then
        TextUI.drawTextCentered(text1, y + 32)
    end
    if text2 then
        TextUI.drawTextCentered(text2, y + 62)
    end
    if hint then
        TextUI.drawTextCentered(hint, y + 94)
    end
end

return TextUI
