-- tutorial.lua — kleines, nicht-invasives Hinweis-/Anleitungs-System (1-Bit,
-- minimalistisch, schwarz/weiß). KEINE Gameplay-Änderung: Es liest nur die
-- Welt (Objektpositionen für Fokus-Fenster) und pausiert das Gameplay über
-- Signale an main.lua (introActive / focusActive / helpActive). Seen-Flags
-- werden über Save persistiert und bei NEW GAME zurückgesetzt. Keine
-- Projekt-Imports; die Module werden zentral in main.lua geladen.

Tutorial = {}

local gfx = playdate.graphics
local WHITE <const> = playdate.graphics.kColorWhite
local BLACK <const> = playdate.graphics.kColorBlack

-- Persistierte Seen-Flags (Save): tutorial.move, tutorial.noPull sowie pro
-- Element-Erklaerung ein Flag (begleiter, bruecke, doppelschalter,
-- druckplatte, einmalschalter, einmalbruecke, inaktivebruecke, blockade, ziel).
Tutorial.flags = {}

-- true, wenn in diesem Frame ein neues Flag gesetzt wurde (main.lua persistiert
-- dann via Save.write). Wird von consumeChanged() konsumiert.
Tutorial.changed = false

-- Einleitung (nur NEW GAME): zwei kurze Seiten NACH dem Level-Reveal — die
-- Willkommensseite (Player-Figur + Begrüßungstext + „A = Weiter“ unten) und
-- die Begleiterseite (Player + runder Baby-Kopf, Erklärung + B-Hinweis unten,
-- ohne Spielfeld-Vorschau). introBoard: 0 = Willkommensseite, 1 = Begleiter-
-- seite; danach beendet (Gameplay startet auf der bereits fertig aufgebauten
-- Levelansicht).
Tutorial.introActive = false
Tutorial.introBoard = 0

-- Kontext-Hinweis (Level 1): kleine Einblendung, die automatisch
-- ausblendet. persistent (key) bleibt bis dismissHint (Kurbel-Hinweis).
Tutorial.hint = nil -- { title, sub, t, hold, key, dismissing }

-- Mechanik-Fokus (neues Element): Gameplay pausiert, Szene abgedunkelt bis
-- auf ein Fenster um das Objekt, Titel + 1-2 Erklaerzeilen + A-Hinweis auf
-- dem schwarzen Bereich. Text IMMER ohne Umlaute (ae/oe/ue/ss) — die
-- System-Font hat keine Umlaut-Glyphen, so ist die Darstellung sicher.
Tutorial.focus = nil -- { title, lines, ring, angle, t }

-- Proximity-Mechanik (Auftrag: „erst VOR Kontakt“): das im Raum noch nicht
-- erklärte neue Element wird NICHT beim Levelstart eingeblendet. maybeStartFocus
-- merkt es sich nur als pending; erst wenn der Player sich dem Element zum
-- ersten Mal deutlich nähert (checkProximityFocus, ± tutorialProximityRange),
-- startet der Fokus — kurz bevor er es berührt/überquert. Gameplay pausiert,
-- Rest des Bildes schwarz, nur das echte Element + kleiner Bereich bleiben
-- sichtbar; nach A exakt dieselbe Spielsituation.
Tutorial.pendingMechanic = nil -- { key, obj }

-- Anleitung (Systemmenüpunkt „ANLEITUNG“): Vollbild-Übersicht, B = zurück.
Tutorial.helpActive = false

-- Timing (weiche Ein-/Ausblendung in 1-Bit als Dissolve-Raster).
local HINT_FADE <const> = 0.3   -- Ein-/Ausblendezeit (s)
local HINT_HOLD <const> = 2.4   -- volle Sichtbarkeit transienter Hinweise (s)
local INTRO_GUIDE <const> = "A = Continue"
local INTRO_START <const> = "A = Start"

-- Einleitungsseite 1 (THIS IS YOU): komplett ENGLISCH (Auftrag). Player groß
-- links (lebendig: Pupille wandert, Blinzeln), Text rechts sauber gesetzt.
local WELCOME_TITLE <const> = "THIS IS YOU."
local WELCOME_LINE1 <const> = "Turn the crank to move along the rings."
local WELCOME_LINE2 <const> = "Find a way to the center."

-- Einleitungsseite 2 (YOUR COMPANION): ENGLISCH. Player EXAKT an derselben
-- Position wie Seite 1; Baby unten rechts (schwarzes Quadrat auf kurzem
-- weißen Bahnstück); oben rechts kleine echte Spielfeldvorschau.
local COMPANION_TITLE <const> = "YOUR COMPANION."
local COMPANION_LINE1 <const> = "Push it with you."
local COMPANION_LINE2 <const> = "You cannot pull it."
local COMPANION_LINE3 <const> = "Reach the center together."

-- Alle Element-Erklaerungen (AUFTRAG „extrem kurz"): KEINE Titel, nur EIN
-- sehr kurzer englischer Satz. Einheitliche Struktur: key -> { text }.
-- "ziel" (Kernbrücke) bleibt mit seinem kurzen Satz (Raumabschluss).
-- "undo" ist definiert, wird aber nicht ausgeloest. Alle Zeichen ASCII
-- (die gebuendelte Font hat keine Umlaute/Striche).
local ELEMENT_TEXT = {
    begleiter =       { text = "Push your companion with you." },
    bruecke =         { text = "Cross to another ring." },
    doppelschalter =  { text = "This switch changes direction." },
    druckplatte =     { text = "A pressure plate stays active only while something stands on it." },
    einmalschalter =  { text = "This switch works only once." },
    einmalbruecke =   { text = "This bridge can be used only once." },
    inaktivebruecke = { text = "Activate it to make it solid." },
    blockade =        { text = "Closed means no way through." },
    ziel =            { text = "Reach the center together." },
    undo =            { text = "B - Restart room" },
}

-- Raum -> Element-Erklaerung beim ersten kontrollierbaren Moment (key zeigt
-- auf ELEMENT_TEXT; obj = Fokus-Objektfinder).
local MECHANIC_BY_ROOM = {
    [2] = { key = "doppelschalter", obj = "switch" },
    [3] = { key = "druckplatte",    obj = "plate" },
    [4] = { key = "einmalschalter", obj = "oneShot" },
    [5] = { key = "einmalbruecke",  obj = "oneUseBridge" },
    [7] = { key = "inaktivebruecke", obj = "inactiveBridge" },
}

-- --- Intro-Idle (lebendig, ruhig) ------------------------------------------
-- Player und Baby blinzeln gelegentlich und schauen sanft umher. Das Baby ist
-- ruhiger (seltenere Blicke/Blink). updateIntro(dt) schreibt den aktuellen
-- Blick-/Blink-Zustand auf das Idle-Objekt; die Zeichenfunktionen lesen ihn.
local function newIntroIdle(blinkMin, blinkMax, lookPeriod, lookAmp)
    return {
        t = 0, blinkMin = blinkMin, blinkMax = blinkMax,
        nextBlinkAt = blinkMin, blink = 0, lookPeriod = lookPeriod, lookAmp = lookAmp,
        dx = 0, dy = 0, blinkOn = false,
    }
end

local function updateIntroIdle(idle, dt)
    idle.t = idle.t + dt
    if idle.blink > 0 then
        idle.blink = idle.blink - dt
        if idle.blink <= 0 then
            idle.nextBlinkAt = idle.t + idle.blinkMin + math.random() * (idle.blinkMax - idle.blinkMin)
        end
    elseif idle.t >= idle.nextBlinkAt then
        idle.blink = 0.14 -- Augen zu (kurz)
    end
    idle.blinkOn = idle.blink > 0
    -- Sanfte Blickwanderung (Sinus-Überlagerung; deterministisch ruhig).
    local a = idle.t / idle.lookPeriod
    idle.dx = math.sin(a * 1.7 + idle.t * 0.3) * idle.lookAmp
    idle.dy = math.cos(a * 1.1) * idle.lookAmp * 0.8
end

Tutorial.introPlayerIdle = newIntroIdle(1.4, 3.2, 3.4, 0.9)
Tutorial.introBabyIdle = newIntroIdle(2.2, 4.5, 5.5, 0.5)

-- --- Flags ----------------------------------------------------------------
function Tutorial.init(flags)
    Tutorial.flags = flags or {}
    Tutorial.changed = false
    Tutorial.introActive = false
    Tutorial.hint = nil
    Tutorial.focus = nil
    Tutorial.pendingMechanic = nil
    Tutorial.helpActive = false
    Tutorial.introPlayerIdle = newIntroIdle(1.4, 3.2, 3.4, 0.9)
    Tutorial.introBabyIdle = newIntroIdle(2.2, 4.5, 5.5, 0.5)
end

-- NEW GAME: alle Hinweise zurücksetzen (persistiert main.lua via Save.write).
function Tutorial.reset()
    Tutorial.flags = {}
    Tutorial.changed = false
    Tutorial.introActive = false
    Tutorial.introBoard = 0
    Tutorial.hint = nil
    Tutorial.focus = nil
    Tutorial.pendingMechanic = nil
    Tutorial.helpActive = false
    Tutorial.introPlayerIdle = newIntroIdle(1.4, 3.2, 3.4, 0.9)
    Tutorial.introBabyIdle = newIntroIdle(2.2, 4.5, 5.5, 0.5)
end

function Tutorial.isSeen(key)
    return Tutorial.flags[key] == true
end

-- Markiert einen Hinweis als gesehen. Liefert true bei echter Änderung
-- (dann persistiert main.lua via Save.write).
function Tutorial.markSeen(key)
    if Tutorial.flags[key] == true then
        return false
    end
    Tutorial.flags[key] = true
    Tutorial.changed = true
    return true
end

-- true + Reset, wenn in diesem Frame ein neues Flag gesetzt wurde.
function Tutorial.consumeChanged()
    local c = Tutorial.changed
    Tutorial.changed = false
    return c
end

-- --- Einleitung (NEW GAME) ------------------------------------------------
function Tutorial.startIntro()
    Tutorial.introActive = true
    Tutorial.introBoard = 0
end

function Tutorial.isIntroActive()
    return Tutorial.introActive
end

-- A: nächste Einleitungsseite (0 -> 1 -> Ende, dann ins Level).
function Tutorial.advanceIntro()
    if Tutorial.introActive then
        if Tutorial.introBoard < 1 then
            Tutorial.introBoard = Tutorial.introBoard + 1
        else
            Tutorial.introActive = false
        end
    end
end

-- B: eine Einleitungsseite zurück (1 -> 0; auf Seite 0 kein weiterer
-- Rückschritt).
function Tutorial.backIntro()
    if Tutorial.introActive and Tutorial.introBoard > 0 then
        Tutorial.introBoard = Tutorial.introBoard - 1
    end
end

function Tutorial.updateIntro(dt)
    -- Intro-Lebendigkeit: Player und Baby blinzeln (fester Blick, keine
    -- Pupillenwanderung — die Blickrichtung ist fix: Player runter, Baby
    -- hoch zum Player).
    updateIntroIdle(Tutorial.introPlayerIdle, dt)
    updateIntroIdle(Tutorial.introBabyIdle, dt)
end

-- --- Kontext-Hinweis ------------------------------------------------------
-- Transienter Hinweis: erscheint, bleibt kurz, blendet weich aus.
function Tutorial.showHint(title, sub)
    Tutorial.hint = { title = title, sub = sub, t = 0, hold = HINT_HOLD, key = nil, dismissing = false }
end

-- Persistenter Hinweis (bleibt bis dismissHint — z. B. „KURBEL — BEWEGEN“,
-- bis der Player sich tatsächlich bewegt hat).
function Tutorial.showHintPersistent(key, title, sub)
    Tutorial.hint = { title = title, sub = sub, t = 0, hold = nil, key = key, dismissing = false }
end

-- Blendet einen persistenten Hinweis weich aus.
function Tutorial.dismissHint()
    local h = Tutorial.hint
    if h then
        h.dismissing = true
        h.t = 0
    end
end

-- Ist gerade der genannte persistente Hinweis aktiv?
function Tutorial.isHintPersistent(key)
    local h = Tutorial.hint
    return h ~= nil and h.key == key
end

function Tutorial.hasHint()
    return Tutorial.hint ~= nil
end

function Tutorial.updateHint(dt)
    local h = Tutorial.hint
    if not h then
        return
    end
    h.t = h.t + dt
    if h.dismissing then
        if h.t > HINT_FADE then
            Tutorial.hint = nil
        end
    elseif h.hold then
        -- transient: automatisch ausblenden.
        if h.t > h.hold + HINT_FADE then
            Tutorial.hint = nil
        end
    end
end

-- --- Element-Erklaer-Fokus -------------------------------------------------
function Tutorial.focusActive()
    return Tutorial.focus ~= nil
end

-- Startet einen Element-Erklaer-Screen (Fokus-Hervorhebung + Infoleiste).
-- key zeigt auf ELEMENT_TEXT (text) und steuert die Markergröße; ring/angle
-- = Fokus-Objekt.
function Tutorial.startElementFocus(key, ring, angle)
    local e = ELEMENT_TEXT[key]
    if not e then
        return
    end
    Tutorial.markSeen(key)
    Tutorial.focus = { key = key, text = e.text, ring = ring, angle = angle, t = 0 }
end

function Tutorial.dismissFocus()
    Tutorial.focus = nil
end

function Tutorial.updateFocus(dt)
    if Tutorial.focus then
        Tutorial.focus.t = Tutorial.focus.t + dt
    end
end

-- Phase-2-Schwelle: ab config.phaseTwoStartRoom (nach LEVEL 7) gibt es KEINE
-- Tutorial-Overlays mehr (keine Mechanik-Fokus, keine Kontext-Hinweise, keine
-- Level-1-Hinweise) — die Einführung ist vorbei, die schwere Phase beginnt.
-- Alle bisherigen Elemente dürfen dort kombiniert werden, nichts wird mehr
-- erklärt. Abhängig vom zentral geladenen Config-Modul (kein Import).
function Tutorial.enabledForRoom(roomIndex)
    local phaseStart = (Config and Config.phaseTwoStartRoom) or 8
    if roomIndex == nil then
        return true
    end
    return roomIndex < phaseStart
end

-- Prüft beim ersten kontrollierbaren Moment eines Raums, ob ein neues Element
-- eingeführt wird; merkt es sich dann als PENDING (Proximity). Startet NIE
-- direkt einen Fokus — das passiert erst in checkProximityFocus, wenn der
-- Player sich dem Element nähert. Rückgabe immer false (kein Sofort-Fokus).
function Tutorial.maybeStartFocus(roomIndex)
    if not Tutorial.enabledForRoom(roomIndex) then
        return false
    end
    local m = MECHANIC_BY_ROOM[roomIndex]
    if not m then
        return false
    end
    if Tutorial.flags[m.key] == true then
        return false
    end
    Tutorial.pendingMechanic = { key = m.key, obj = m.obj }
    return false
end

-- Proximity-Trigger (Auftrag: „deutlich VOR dem Element“): wenn ein pending
-- neues Element existiert und der Player sich ihm zum ersten Mal nähert (auf
-- demselben Ring, innerhalb tutorialProximityRange ~12-20°), startet der
-- Fokus — der Player steht dann noch VOR dem Element (kleine sichtbare Lücke,
-- Hitbox/Aktivierungsbereich noch nicht erreicht). Zusätzlich gilt dasselbe
-- für die erste geschlossene Blende (Shutter): auch sie wird VOR dem Kontakt
-- erklärt, nicht erst beim Aufprall. true = Fokus aktiv (Gameplay pausiert).
-- Wird pro Frame geprüft (auch im Stand), damit die Einblendung zuverlässig
-- kurz VOR dem Kontakt erscheint.
function Tutorial.checkProximityFocus(roomIndex)
    if not Tutorial.enabledForRoom(roomIndex) then
        return false
    end
    -- 1) pending Mechanik-Element (Doppelschalter, Platte, One-Shot, One-Use,
    --    Inactive Bridge).
    local m = Tutorial.pendingMechanic
    if m then
        if Tutorial.flags[m.key] == true then
            Tutorial.pendingMechanic = nil
            return false
        end
        local ring, angle = Tutorial.focusObject(m.obj)
        if ring then
            local range = (Config and Config.tutorialProximityRange) or 15
            if State.player and State.player.ring == ring then
                if math.abs(Geometry.delta(State.player.angle, angle)) <= range then
                    Tutorial.startElementFocus(m.key, ring, angle)
                    Tutorial.pendingMechanic = nil
                    return true
                end
            end
        end
    end
    -- 2) Shutter (Blockade): erste geschlossene Blende wird VOR dem Kontakt
    --    erklärt — der Player steht noch davor (Proximity auf dem Ring).
    if not Tutorial.isSeen("blockade") then
        local ring, angle = Tutorial.findNearbyClosedShutter()
        if ring then
            Tutorial.startElementFocus("blockade", ring, angle)
            return true
        end
    end
    return false
end

-- Objekt für das Fokus-Fenster bestimmen (Ring + Winkel) aus State.room.
function Tutorial.focusObject(objKind)
    local roomData = State.room
    if not roomData then
        return nil
    end
    if objKind == "switch" then
        local s = roomData.switches and roomData.switches[1]
        return s and s.ring, s and s.angle
    elseif objKind == "oneShot" then
        for _, sw in ipairs(roomData.switches) do
            if sw.oneShot == true then
                return sw.ring, sw.angle
            end
        end
    elseif objKind == "plate" then
        local p = roomData.plates and roomData.plates[1]
        return p and p.ring, p and p.angle
    elseif objKind == "oneUseBridge" or objKind == "inactiveBridge" then
        for _, b in ipairs(roomData.bridges) do
            local match = (objKind == "oneUseBridge" and b.oneShot == true)
                or (objKind == "inactiveBridge" and b.free == false)
            if match then
                return "outer", b.angle
            end
        end
    end
    return nil
end

-- Kontextabhängige Element-Erklaerungen (beim ersten sinnvollen Auftreten,
-- nur einmal — Flags persistiert). Liefert true, wenn ein Screen startet
-- (Gameplay pausiert dann). Wird nach der Bewegung aufgerufen.
function Tutorial.checkElementTriggers(roomIndex, moveResult)
    if not Tutorial.enabledForRoom(roomIndex) then
        return false
    end
    -- Begleiter: erster Baby-Schub.
    if not Tutorial.isSeen("begleiter") and moveResult and moveResult.babyMoved then
        local baby = State.baby
        if baby then
            Tutorial.startElementFocus("begleiter", baby.ring, baby.angle)
            return true
        end
    end
    -- Bruecke: erste Andock-Annäherung.
    if not Tutorial.isSeen("bruecke") then
        local ring, angle = Tutorial.findApproachableBridge()
        if ring then
            Tutorial.startElementFocus("bruecke", ring, angle)
            return true
        end
    end
    -- Blockade (Shutter) wird NICHT mehr beim Aufprall erklärt (Auftrag:
    -- deutlich VOR dem Kontakt) — der Fokus läuft über
    -- checkProximityFocus/findNearbyClosedShutter, solange der Player noch
    -- VOR der geschlossenen Blende steht.
    -- Ziel: erste Andock-Annäherung an das Tor.
    if not Tutorial.isSeen("ziel") then
        local ring, angle = Tutorial.findApproachableGate()
        if ring then
            Tutorial.startElementFocus("ziel", ring, angle)
            return true
        end
    end
    return false
end

-- Liefert Ring + Winkel der ersten Brücke, an der der Player andocken kann
-- (innerhalb tutorialProximityRange, also deutlich VOR dem Dock), sonst nil.
function Tutorial.findApproachableBridge()
    local roomData = State.room
    if not roomData then
        return nil
    end
    local range = (Config and Config.tutorialProximityRange) or 15
    for _, b in ipairs(roomData.bridges) do
        if math.abs(Geometry.delta(State.player.angle, b.angle)) <= range then
            return State.player.ring, b.angle
        end
    end
    return nil
end

-- Liefert Ring + Winkel einer geschlossenen Blende (physical collisionActive),
-- sonst nil.
function Tutorial.findBlockingShutter()
    local roomData = State.room
    if not roomData then
        return nil
    end
    for _, sh in ipairs(roomData.shutters) do
        local phys = Room.shutters and Room.shutters[sh.id]
        if phys and phys.collisionActive == true then
            return sh.ring, sh.angle
        end
    end
    return nil
end

-- Liefert Ring + Winkel einer GESCHLOSSENEN Blende auf dem Player-Ring, die
-- der Player bereits deutlich ANNÄHERT (innerhalb tutorialProximityRange) —
-- der Shutter-Fokus erscheint so VOR dem Kontakt, nicht erst beim Aufprall.
-- sonst nil.
function Tutorial.findNearbyClosedShutter()
    local roomData = State.room
    if not roomData or not State.player then
        return nil
    end
    local range = (Config and Config.tutorialProximityRange) or 15
    for _, sh in ipairs(roomData.shutters) do
        if sh.ring == State.player.ring then
            local phys = Room.shutters and Room.shutters[sh.id]
            if phys and phys.collisionActive == true then
                if math.abs(Geometry.delta(State.player.angle, sh.angle)) <= range then
                    return sh.ring, sh.angle
                end
            end
        end
    end
    return nil
end

-- Liefert Ring + Winkel des Tores, wenn der Player in die Einführungszone
-- kommt (auf dem Tor-Ring, innerhalb tutorialProximityRange), sonst nil.
function Tutorial.findApproachableGate()
    local roomData = State.room
    if not roomData or not roomData.gate then
        return nil
    end
    local g = roomData.gate
    if State.player.ring ~= g.ring then
        return nil
    end
    local range = (Config and Config.tutorialProximityRange) or 15
    if math.abs(Geometry.delta(State.player.angle, g.angle)) <= range then
        return g.ring, g.angle
    end
    return nil
end

-- --- Level-1-Hinweise (Steuerung im Spiel lernen) -------------------------
-- Wird pro kontrollierbarem Frame aufgerufen. Liefert true, wenn in DIESEM
-- Frame ein neuer Hinweis erzeugt wurde (für den dezenten Erscheinen-Tick).
function Tutorial.checkLevelHints(roomIndex)
    if roomIndex ~= 1 or not Tutorial.enabledForRoom(roomIndex) then
        return false
    end
    -- „Turn the crank to move." beim ersten kontrollierbaren Moment; bleibt
    -- bis zur ersten Bewegung (onPlayerMoved), im gleichen unteren Leisten-
    -- format wie alle Hinweise. NUR dieser Hinweis bleibt in Level 1
    -- sichtbar (kein Hinweis mitten auf dem Bildschirm).
    if not Tutorial.isSeen("move") and not Tutorial.hint then
        Tutorial.showHintPersistent("move", "Turn the crank to move.")
        return true
    end
    return false
end

-- Erste echte Bewegung blendet den Kurbel-Hinweis aus (Level 1).
function Tutorial.onPlayerMoved(roomIndex)
    if roomIndex == 1 and Tutorial.enabledForRoom(roomIndex) and Tutorial.isHintPersistent("move") then
        Tutorial.dismissHint()
        Tutorial.markSeen("move")
    end
end

-- Erster Ziehversuch (Player in Kontakt, bewegt sich vom Baby weg).
-- Liefert true, wenn in DIESEM Frame ein Hinweis gezeigt wurde (Audio-Tick).
function Tutorial.onPullAttempt(roomIndex, delta)
    if roomIndex ~= 1 or not Tutorial.enabledForRoom(roomIndex) or Tutorial.isSeen("noPull") or delta == 0 then
        return false
    end
    if not Baby.isContactingPlayer() then
        return false
    end
    local d = delta > 0 and 1 or -1
    if Geometry.delta(State.player.angle, State.baby.angle) * d < 0 then
        Tutorial.markSeen("noPull")
        Tutorial.showHint("You cannot pull.")
        return true
    end
    return false
end

-- Erste Undo-Nutzung entfällt: B startet das Level neu (kein Rückgängig),
-- daher gibt es keinen B-/Undo-Hinweis.

-- --- Anleitung (Systemmenü) -----------------------------------------------
function Tutorial.openHelp()
    Tutorial.helpActive = true
end

function Tutorial.closeHelp()
    Tutorial.helpActive = false
end

function Tutorial.isHelpActive()
    return Tutorial.helpActive
end

-- --- Update ---------------------------------------------------------------
function Tutorial.update(dt)
    Tutorial.updateHint(dt)
end

-- --- Zeichnen (schlicht, schwarz/weiß) ------------------------------------
-- Weißer Text (zentriert / linksbündig) über TextUI: gebündelte Font mit
-- Umlauten + invertierter DrawMode (drawText malt sonst immer schwarz).
local function drawTextCentered(text, y)
    TextUI.drawTextCentered(text, y)
end

local function drawTextAt(text, x, y)
    TextUI.drawText(text, x, y)
end

-- 1-Bit-Dissolve: schwarzt (1-alpha) eines groben Rasters im Bereich (x,y,w,h)
-- — weiße Pixel (Text) zerfallen dadurch weich.
local function applyDither(alpha, x, y, w, h)
    if alpha >= 0.999 then
        return
    end
    local covered = math.floor((1 - alpha) * 100)
    gfx.setColor(BLACK)
    local cell = 3
    for i = 0, math.floor(w / cell) do
        for j = 0, math.floor(h / cell) do
            if ((i * 3 + j * 2) % 100) < covered then
                gfx.fillRect(x + i * cell, y + j * cell, cell, cell)
            end
        end
    end
end

-- Zeichnet die große Player-Figur (Referenzstil) mit Idle: schwarzer runder
-- Körper, dünne weiße Außenkontur, große weiße Pupille, die sanft umher-
-- schaut und beim Blinzeln zu einer kurzen Linie wird.
local function drawPlayerFigureIdle(cx, cy, r, eyeDx, eyeDy, blink)
    gfx.setColor(WHITE)
    gfx.setLineWidth(1)
    gfx.drawCircleAtPoint(cx, cy, r)
    gfx.setColor(BLACK)
    gfx.fillCircleAtPoint(cx, cy, r - 1)
    -- Pupille: Basis Richtung Bildschirmmitte (200,120) + sanfte Wanderung.
    local dx, dy = 200 - cx, 120 - cy
    local dist = math.max(1, math.sqrt(dx * dx + dy * dy))
    local px = cx + (dx / dist) * r * 0.30 + eyeDx * r * 0.14
    local py = cy + (dy / dist) * r * 0.30 + eyeDy * r * 0.14
    gfx.setColor(WHITE)
    if blink then
        gfx.drawLine(px - math.floor(r * 0.32), py, px + math.floor(r * 0.32), py)
    else
        gfx.fillCircleAtPoint(math.floor(px + 0.5), math.floor(py + 0.5), math.floor(r * 0.42))
    end
    gfx.setLineWidth(1)
end

-- Baby (Intro-Seite 2, AUFTRAG: exakt die Spiel-Form, auf dunklem Grund lesbar):
-- kleines SCHWARZES Quadrat (Kantenlänge = config.babyVisualSize, exakt die
-- Gameplay-Größe) mit klarer WEISSER Umrandung (1 px) — dieselbe Quadrat-
-- Formensprache wie im eigentlichen Spiel, kein Kreis, kein Platzhalter,
-- keine falsche Symbolform. Die weiße Umrandung hält es auf dem dunklen
-- Hintergrund gut lesbar (das schwarze Quadrat selbst wäre dort unsichtbar).
local function drawBabyIdle(bx, by, size)
    local half = math.floor(size / 2 + 0.5)
    local outline = 1
    gfx.setColor(WHITE)
    gfx.fillRect(bx - half - outline, by - half - outline,
        half * 2 + 2 * outline, half * 2 + 2 * outline)
    gfx.setColor(BLACK)
    gfx.fillRect(bx - half, by - half, half * 2, half * 2)
    gfx.setColor(WHITE)
end

-- Kleine echte Spielfeldvorschau (Intro-Seite 2): Miniatur der Spieloptik —
-- schwarzer Grund, zwei weiße Ringbahnen, dither-gepunkteter Kern, eine
-- Ring-zu-Ring-Brücke UND die Brücke zum Mittelpunkt (Core-Bridge) OBEN —
-- im selben visuellen Vokabular, nur skaliert (keine erfundene Logo-Grafik).
-- Reine Primitiven, kein Sprite.
function Tutorial.drawMiniPreview(x, y, w, h)
    gfx.setColor(BLACK)
    gfx.fillRect(x, y, w, h)
    local cx, cy = x + w / 2, y + h / 2
    -- Ringbahnen (weiß, ~2 px) — Verhältnis wie im Spiel (104 : 68 : 37).
    gfx.setColor(WHITE)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(cx, cy, 26)
    gfx.drawCircleAtPoint(cx, cy, 17)
    -- Kern (50 %-Dither weiß über schwarz — exakt die Kern-Optik).
    gfx.setColor(BLACK)
    gfx.fillCircleAtPoint(cx, cy, 9)
    gfx.setDitherPattern(50)
    gfx.setColor(WHITE)
    gfx.fillCircleAtPoint(cx, cy, 9)
    gfx.setDitherPattern(100)
    -- Ring-zu-Ring-Brücke (dicke weiße Linie radial, wie im Spiel).
    gfx.setColor(WHITE)
    gfx.setLineWidth(4)
    local bx1, by1 = Geometry.polar(cx, cy, 17, 40)
    local bx2, by2 = Geometry.polar(cx, cy, 26, 40)
    gfx.drawLine(bx1, by1, bx2, by2)
    -- BRÜCKE ZUM MITTELPUNKT (Core-Bridge) OBEN sichtbar (0° = 12 Uhr): vom
    -- inneren Ring direkt zum Kern — genau wie die echte Center-Bridge.
    local gx1, gy1 = Geometry.polar(cx, cy, 17, 0)
    local gx2, gy2 = Geometry.polar(cx, cy, 9, 0)
    gfx.drawLine(gx1, gy1, gx2, gy2)
    gfx.setLineWidth(1)
end

-- Erste Einleitungsseite (THIS IS YOU): Player GROSS LINKS (lebendig —
-- Pupille wandert sanft, gelegentliches Blinzeln, keine hektische Bewegung),
-- Text RECHTS sauber gesetzt, feste Safe-Margins. Keine anderen Elemente.
-- Unten: NUR „A = Continue“ allein auf schwarzer Grundleiste.
function Tutorial.drawWelcome()
    local p = Tutorial.introPlayerIdle
    drawPlayerFigureIdle(72, 118, 42, p.dx, p.dy, p.blinkOn == true)
    -- Text rechts (Safe-Margin links 16 px, rechts 16 px).
    local tx = 150
    TextUI.drawText(WELCOME_TITLE, tx, 66)
    TextUI.drawText(WELCOME_LINE1, tx, 104)
    TextUI.drawText(WELCOME_LINE2, tx, 130)
    -- Unten: NUR „A = Continue“ allein auf schwarzer Grundleiste.
    gfx.setColor(BLACK)
    gfx.fillRect(0, 206, 400, 34)
    TextUI.drawTextCentered(INTRO_GUIDE, 216)
end

-- Zweite Einleitungsseite (YOUR COMPANION): Player EXAKT an derselben
-- Position und Animation wie Seite 1. Struktur: links große Player-Abbildung,
-- rechts kurzer Textblock, oben rechts kleine echte Spielfeldvorschau (mit
-- Brücke zum Mittelpunkt), unten rechts das korrekt dargestellte Baby
-- (schwarzes Quadrat mit weißer Umrandung). Feste Safe-Margins, keine
-- Überlappungen, genug Luft zwischen Text und Grafiken. Unten: NUR
-- „A = Start“ allein auf schwarzer Grundleiste (eigene letzte Zeile).
function Tutorial.drawCompanion()
    local p = Tutorial.introPlayerIdle
    -- Player an exakt derselben Position wie auf Seite 1 (nicht verschieben).
    drawPlayerFigureIdle(72, 118, 42, p.dx, p.dy, p.blinkOn == true)
    -- Kleine echte Spielfeldvorschau oben rechts (mit Brücke zum Mittelpunkt).
    Tutorial.drawMiniPreview(286, 10, 102, 56)
    -- Textblock rechts, unterhalb der Vorschau — sauber gesetzt, feste
    -- Safe-Margins, nicht zu breit, genug Abstand zu Vorschau und Baby.
    local tx = 150
    TextUI.drawText(COMPANION_TITLE, tx, 78)
    TextUI.drawText(COMPANION_LINE1, tx, 110)
    TextUI.drawText(COMPANION_LINE2, tx, 136)
    TextUI.drawText(COMPANION_LINE3, tx, 162)
    -- Baby unten rechts (schwarzes Quadrat mit weißer Umrandung), über der
    -- unteren Grundleiste, klar vom Text und vom A-Hinweis getrennt.
    drawBabyIdle(330, 192, Config.babyVisualSize or 9)
    -- Unten: NUR „A = Start“ allein auf schwarzer Grundleiste (genug Abstand
    -- nach oben, nie in derselben Zeile wie der Haupttext).
    gfx.setColor(BLACK)
    gfx.fillRect(0, 206, 400, 34)
    TextUI.drawTextCentered(INTRO_START, 216)
end

function Tutorial.drawIntro()
    gfx.clear(BLACK)
    if Tutorial.introBoard == 0 then
        Tutorial.drawWelcome()
    else
        Tutorial.drawCompanion()
    end
end

-- --- Fokus-Overlay (AUFTRAG „deutlich minimalistischer") --------------------
-- KEINE grosse Karte, KEIN Rahmen um den Text, KEINE technische Überschrift,
-- KEINE langen Erklaerungen. Das echte Spielelement bleibt sichtbar (ebenso
-- Player/Baby, die noch sichtbar Abstand zum Element haben), der Rest des
-- Bildes wird schwarz. Daneben steht nur EIN kurzer Satz (max. ~200 px breit,
-- an Wortgrenzen umbrochen) und darunter, mit grossem Abstand auf eigener
-- Zeile, „A - Continue". Text wird VOR dem Rendern gemessen und darf nie über
-- dem Element, Player oder Baby liegen; Mindestabstand zum Bildschirmrand
-- tutorialSafeMargin.

-- Layout-Werte aus Config (keine Magic Numbers im Spielcode).
local function cfg(name, fallback)
    local v = Config and Config[name]
    if v == nil then
        return fallback
    end
    return v
end

-- Umbruch an Wortgrenzen in SKALIERTEN Pixeln (maxWidth bezieht sich auf die
-- gerenderte, skalierte Breite). Vermeidet einzelne Waisen-Zeilen: ist die
-- letzte Zeile nur ein einzelnes Wort, wandert das letzte Wort der vorherigen
-- Zeile nach unten (balanciert).
local function wrapScaled(text, maxWidth, scale)
    local lines = {}
    if not text or text == "" then
        return lines
    end
    for word in (text .. " "):gmatch("(%S+)%s*") do
        local cur = lines[#lines]
        if cur and TextUI.textWidth(cur .. " " .. word) * scale <= maxWidth then
            lines[#lines] = cur .. " " .. word
        else
            lines[#lines + 1] = word
        end
    end
    if #lines >= 2 then
        local last = lines[#lines]
        local single = last:match("^%S+$")
        if single then
            local prev = lines[#lines - 1]
            local words = {}
            for w in (prev .. " "):gmatch("(%S+)%s*") do
                words[#words + 1] = w
            end
            if #words >= 2 then
                lines[#lines - 1] = table.concat(words, " ", 1, #words - 1)
                lines[#lines] = words[#words] .. " " .. last
            end
        end
    end
    return lines
end

-- Überlappen sich zwei Rechtecke {x0,y0,x1,y1}?
local function rectsOverlap(a, b)
    return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- Füllt die Bildschirmfläche [yMin,yMax) AUSSER den Rechtecken in keep
-- (Element, Player, Baby bleiben unangetastet). Robust fuer beliebige
-- Rechteckmengen: pro y-Band werden nur die LÜCKEN zwischen den keep-
-- Rechtecken gefüllt (die keep-Intervalle selbst bleiben unangetastet).
-- stripeStep > 0: statt solide zu füllen werden horizontale 1-px-Linien im
-- festen Bildschirm-Raster gezeichnet (manueller Dither-Dim — setDitherPattern
-- wirkt in dieser SDK-Version nicht zuverlässig; kein Pattern-Zustand, der in
-- den nächsten Frame leakt). stripeStep = nil/0: solide (untere Leiste).
local function fillComplement(keep, yMin, yMax, stripeStep)
    local ys = { yMin, yMax }
    for _, k in ipairs(keep) do
        ys[#ys + 1] = math.max(yMin, math.floor(k.y0))
        ys[#ys + 1] = math.min(yMax, math.ceil(k.y1))
    end
    table.sort(ys)
    for i = 1, #ys - 1 do
        local y0 = ys[i]
        local y1 = ys[i + 1]
        if y1 > y0 then
            local ix = {}
            for _, k in ipairs(keep) do
                if k.y0 < y1 and k.y1 > y0 then
                    ix[#ix + 1] = { x0 = math.max(0, math.floor(k.x0)), x1 = math.min(400, math.ceil(k.x1)) }
                end
            end
            table.sort(ix, function(a, b) return a.x0 < b.x0 end)
            local cur = 0
            for _, iv in ipairs(ix) do
                local sx = math.max(cur, iv.x0)
                if sx > cur then
                    if stripeStep and stripeStep > 1 then
                        -- manueller Streifen-Dim (feste Bildschirmzeilen)
                        for yy = y0, y1 - 1 do
                            if yy % stripeStep == 0 then
                                gfx.fillRect(cur, yy, sx - cur, 1)
                            end
                        end
                    else
                        gfx.fillRect(cur, y0, sx - cur, y1 - y0)
                    end
                end
                cur = math.max(cur, iv.x1)
            end
            if cur < 400 then
                if stripeStep and stripeStep > 1 then
                    for yy = y0, y1 - 1 do
                        if yy % stripeStep == 0 then
                            gfx.fillRect(cur, yy, 400 - cur, 1)
                        end
                    end
                else
                    gfx.fillRect(cur, y0, 400 - cur, y1 - y0)
                end
            end
        end
    end
end

-- --- Tutorial-Trigger (AUFTRAG „früh, ohne Bewegungskorrektur") ------------
-- KEINE Tutorial-Bremse mehr: die Steuerung fühlt sich völlig normal an
-- (kein Dämpfen, kein Stopp, kein Snap, keine Kameraänderung). Die Hinweise
-- starten über reine Proximity-Zonen (checkProximityFocus für Mechanik +
-- Blende, checkElementTriggers für Baby/Brücke/Ziel) — der Player darf sich
-- währenddessen normal weiterbewegen; pausiert wird nur, solange der Fokus
-- aktiv ist (bis A). Getrennt vom Bridge-Crank-Widerstand (der bleibt
-- normale Gameplaymechanik und funktioniert auch später weiter).

-- --- Untere Infoleiste (AUFTRAG „schwarzer Bereich nur unten") -------------
-- SOLID schwarzer Balken unten mit feiner WEISSER Trennlinie fast über die
-- volle Breite. Darin weisse, FEINE Schrift (Asheville-Sans-14-Bold, natür-
-- liche 14 px — kein Downscale, keine abgeschnittene/grobe Typo). Text links,
-- optionaler rechter Hinweis („A = continue") in EIGENER Spalte rechts (nie
-- gequetscht). Max. 2 kurze Zeilen; Text wird VOR dem Rendern gemessen und
-- umbrochen — nie abgeschnitten, nie überlappend. Wird von drawFocus
-- (Element-Fokus) UND drawHint (alle Hinweise, z. B. „Turn the crank to
-- move.") verwendet — exakt derselbe Aufbau für alle Tutorial-Hinweise.

-- Umbruch an Wortgrenzen mit der feinen Leisten-Font (natürliche Breiten).
local function wrapBarText(text, maxWidth)
    local lines = {}
    if not text or text == "" then
        return lines
    end
    for word in (text .. " "):gmatch("(%S+)%s*") do
        local cur = lines[#lines]
        if cur and TextUI.barTextWidth(cur .. " " .. word) <= maxWidth then
            lines[#lines] = cur .. " " .. word
        else
            lines[#lines + 1] = word
        end
    end
    return lines
end

function Tutorial.drawInfoBar(text, rightText)
    local BAR_H <const> = cfg("tutorialBarHeight", 40)
    local MARGIN <const> = cfg("tutorialBarMargin", 14)
    local LINE_X0 <const> = cfg("tutorialLineX0", 8)
    local LINE_X1 <const> = cfg("tutorialLineX1", 392)
    local LINE_Y = 240 - BAR_H
    local fontH = (TextUI.barFont and TextUI.barFont:getHeight()) or 18

    -- Rechter Hinweis („A = continue") in eigener Spalte rechts.
    local rightW = 0
    if rightText then
        rightW = TextUI.barTextWidth(rightText)
    end
    local COL_GAP = 18 -- Abstand zwischen Textspalte und A-Spalte (nie quetschen)
    local textMaxW = 400 - MARGIN - rightW - COL_GAP - MARGIN
    textMaxW = math.max(60, textMaxW)

    -- Text links: an Wortgrenzen umbrechen (feine Font), max. 2 Zeilen.
    local lines = wrapBarText(text, textMaxW)
    if #lines > 2 then
        lines = { lines[1], lines[2] }
    end
    local lineGap = 2
    local blockH = #lines * fontH + (#lines - 1) * lineGap

    -- SOLID schwarzer Bereich unter der Trennlinie (alles unterhalb ist
    -- schwarz — nichts scheint durch) + feine weisse Trennlinie.
    gfx.setColor(BLACK)
    gfx.fillRect(0, LINE_Y + 1, 400, 240 - (LINE_Y + 1))
    gfx.setColor(WHITE)
    gfx.fillRect(LINE_X0, LINE_Y, LINE_X1 - LINE_X0, 1)

    -- Text links (weiß, feine 14-px-Font), vertikal zentriert im Balken. Der
    -- Start wird geclampt, damit Text NIE über die Trennlinie ragt.
    local textY = LINE_Y + math.floor((BAR_H - blockH) / 2)
    if textY < LINE_Y + 2 then
        textY = LINE_Y + 2
    end
    for i, l in ipairs(lines) do
        TextUI.drawBarText(l, MARGIN, textY)
        textY = textY + fontH + lineGap
    end
    -- A rechts (eigene Spalte, vertikal zentriert, nie mit dem Text kollidierend).
    if rightText then
        TextUI.drawBarTextRight(rightText, 400 - MARGIN, LINE_Y + math.floor((BAR_H - fontH) / 2))
    end
end

-- Halbe Marker-Abmessungen (tangential/radial, px) für den engen Fokusrahmen
-- um das ELEMENT — abgeleitet aus den echten Elementgrößen (Config), damit
-- nur das konkrete Element markiert wird (kein ganzer Ringabschnitt).
local function focusMarkerHalf(key, radius)
    local c = Config
    local pad = (c and c.tutorialMarkerPad) or 2
    local mk = key or ""
    if mk == "begleiter" then
        local s = (c and c.babyVisualSize) or 9
        return s / 2 + 4, s / 2 + 4
    elseif mk == "druckplatte" then
        local s = (c and c.plateSize) or 13
        return s / 2 + pad + 2, 10
    elseif mk == "doppelschalter" or mk == "einmalschalter" then
        local w = (c and c.switchWidth) or 23
        local h = (c and c.switchHeight) or 8
        return w / 2 + 4, h / 2 + 6
    elseif mk == "blockade" then
        local deg = (c and c.shutterArcWidth) or 26
        return math.max(13, radius * math.sin(math.rad(deg / 2))), 12
    else
        -- bruecke, einmalbruecke, inaktivebruecke, ziel
        return 14, 11
    end
end

function Tutorial.drawFocus()
    local focus = Tutorial.focus
    if not focus then
        return
    end
    -- Elementposition (Ring + Winkel -> Bildschirmposition).
    local radius = Render.ringRadius(focus.ring)
    local ox, oy = Geometry.polar(200, 120, radius, focus.angle)
    local tangHalf, radHalf = focusMarkerHalf(focus.key, radius)
    local pad = (Config and Config.tutorialMarkerPad) or 2
    local wx0 = math.max(0, math.floor(ox - tangHalf - pad))
    local wy0 = math.max(0, math.floor(oy - radHalf - pad))
    local wx1 = math.min(400, math.floor(ox + tangHalf + pad))
    local wy1 = math.min(240, math.floor(oy + radHalf + pad))
    local LINE_Y = 240 - (cfg("tutorialBarHeight", 46))

    -- Keep-Flächen: das neue Element + Player + Baby bleiben voll
    -- kontrastreich (nicht abgeschwächt). Player/Baby immer sichtbar; nur wenn
    -- das Baby SELBST das Element ist, umschließt der Fokusrahmen es.
    local keep = {
        { x0 = wx0, y0 = wy0, x1 = wx1, y1 = wy1 },
    }
    local function addFigure(x, y)
        if not x then
            return
        end
        local h = 9
        keep[#keep + 1] = { x0 = x - h, y0 = y - h, x1 = x + h, y1 = y + h }
    end
    local px, py = Render.playerScreenPosition()
    addFigure(px, py)
    if State.baby then
        local br = Render.babyRadius()
        if br then
            local bx, by = Geometry.polar(200, 120, br, State.baby.angle)
            addFigure(bx, by)
        end
    end

    -- 1) Restliches Spielfeld NUR dezent abschwächen (1 schwarze Zeile alle
    --    tutorialDimStep Zeilen): bleibt komplett sichtbar und klar lesbar,
    --    kein schwarzer Overlay, kein Vollbild-Dimming. Das neue Element
    --    (keep) sticht voll kontrastreich heraus.
    local dimStep = (Config and Config.tutorialDimStep) or 5
    gfx.setColor(BLACK)
    fillComplement(keep, 0, LINE_Y - 1, dimStep)

    -- 2) Untere Infoleiste (unverändert): schwarzer Balken, weisse Trennlinie,
    --    feine weisse Schrift, Text links, „A = continue" rechts.
    Tutorial.drawInfoBar(focus.text, "A = continue")

    -- 3) Klarer Fokusrahmen: vier symmetrische Eckmarker nah am Element,
    --    dezent pulsierend (1 px langsam nach innen/aussen, kein Blinken).
    local pulseSpeed = (Config and Config.tutorialMarkerPulseSpeed) or 2.5
    local L = (Config and Config.tutorialMarkerLen) or 10
    local pulse = (math.sin(focus.t * pulseSpeed) >= 0) and 1 or 0
    local x0 = math.max(0, wx0 - pulse)
    local y0 = math.max(0, wy0 - pulse)
    local x1 = math.min(400, wx1 + pulse)
    local y1 = math.min(240, wy1 + pulse)
    gfx.setColor(WHITE)
    gfx.drawLine(x0, y0 + L, x0, y0)
    gfx.drawLine(x0, y0, x0 + L, y0)
    gfx.drawLine(x1 - L, y0, x1, y0)
    gfx.drawLine(x1, y0, x1, y0 + L)
    gfx.drawLine(x0, y1 - L, x0, y1)
    gfx.drawLine(x0, y1, x0 + L, y1)
    gfx.drawLine(x1 - L, y1, x1, y1)
    gfx.drawLine(x1, y1 - L, x1, y1)
end

local function hintAlpha(h)
    if h.dismissing then
        return math.max(0, 1 - h.t / HINT_FADE)
    end
    if h.hold then
        if h.t < HINT_FADE then
            return h.t / HINT_FADE
        end
        if h.t > h.hold then
            return math.max(0, (h.hold + HINT_FADE - h.t) / HINT_FADE)
        end
    end
    return 1
end

function Tutorial.drawHint()
    local h = Tutorial.hint
    if not h then
        return
    end
    local alpha = hintAlpha(h)
    if alpha <= 0 then
        return
    end
    -- GLEICHE untere Infoleiste wie bei allen Element-Hinweisen (AUFTRAG
    -- „einheitlicher Aufbau"): Spielfeld bleibt komplett sichtbar, weisse
    -- Trennlinie, feiner weisser Text links. Kein A rechts — diese Hinweise
    -- schliesst nicht A, sondern Bewegung (Kurbel) bzw. Zeit (transient).
    -- Ausblenden per Dissolve-Raster in der Leiste.
    local text = h.title or h.sub or ""
    Tutorial.drawInfoBar(text, nil)
    if alpha < 0.999 then
        local bh = cfg("tutorialBarHeight", 40)
        applyDither(alpha, 0, 240 - bh, 400, bh)
    end
end

-- Zeichnet das aktive Overlay (Fokus oder Hinweis) über der Szene.
function Tutorial.draw()
    if Tutorial.focus then
        Tutorial.drawFocus()
    elseif Tutorial.hint then
        Tutorial.drawHint()
    end
end

-- --- Anleitung (Systemmenü „ANLEITUNG“) -----------------------------------
-- Kurze Übersicht der Regeln mit kleinen Symbolen der echten Elemente.
-- ALLE TEXTE ENGLISCH. Kurze, einzeilige Beschreibungen (mit der 22-px-Font
-- passen Label + Text sauber auf eine Zeile; kein Überlauf, kein Umbruch
-- mitten im Satz).
local HELP_ENTRIES = {
    { icon = "crank",  label = "Crank",            desc = "Move" },
    { icon = "baby",   label = "Companion",       desc = "Can be pushed" },
    { icon = "switch", label = "Double Switch",   desc = "Direction decides" },
    { icon = "plate",  label = "Pressure Plate",  desc = "Active under weight" },
    { icon = "oneshot",label = "One-Shot Switch", desc = "Triggers once" },
    { icon = "oneuse", label = "One-Use Bridge",  desc = "Disappears after" },
    { icon = "point",  label = "Inactive Bridge", desc = "Activatable" },
    { icon = "b",      label = "Button B",        desc = "Restart level" },
}

local function drawHelpIcon(kind, x, y, scale)
    local s = scale or 0.55
    gfx.setColor(WHITE)
    if kind == "crank" then
        gfx.drawLine(x + 2, y + 2, x + 9, y + 11)
        gfx.fillCircleAtPoint(x + 11, y + 13, 3)
    elseif kind == "baby" then
        gfx.drawRect(x + 1, y + 1, 12, 12)
        gfx.fillCircleAtPoint(x + 7, y + 7, 2)
    elseif kind == "switch" then
        gfx.drawRect(x, y + 4, 14, 6)
        gfx.fillCircleAtPoint(x + 4, y + 7, 1)
        gfx.drawCircleAtPoint(x + 10, y + 7, 1)
    elseif kind == "plate" then
        gfx.drawRect(x + 2, y + 2, 10, 10)
    elseif kind == "oneshot" then
        gfx.drawRect(x, y + 4, 14, 6)
        gfx.drawLine(x + 3, y + 5, x + 6, y + 9)
        gfx.drawLine(x + 8, y + 5, x + 11, y + 9)
    elseif kind == "oneuse" then
        gfx.fillRect(x, y + 5, 14, 4)
        gfx.drawLine(x + 3, y + 6, x + 6, y + 9)
        gfx.drawLine(x + 8, y + 6, x + 11, y + 9)
    elseif kind == "point" then
        gfx.fillRect(x, y + 5, 5, 2)
        gfx.fillRect(x + 7, y + 5, 2, 2)
        gfx.fillRect(x + 11, y + 5, 3, 2)
    elseif kind == "b" then
        TextUI.drawTextScaled("B", x, y, s)
    elseif kind == "bhold" then
        TextUI.drawTextScaled("B", x, y, s)
        gfx.drawLine(x + 11, y + 8, x + 3, y + 8)
        gfx.drawLine(x + 5, y + 6, x + 3, y + 8)
        gfx.drawLine(x + 5, y + 10, x + 3, y + 8)
    end
end

function Tutorial.drawHelp()
    gfx.clear(BLACK)
    -- ANLEITUNG (Systemmenü): mit der 24-px-Font kompakt skaliert (~14 px),
    -- damit alle 8 Einträge + Kopf + B-Hinweis sauber auf 240 px passen.
    local SCALE <const> = 0.55
    local LINE <const> = 20
    TextUI.drawTextCenteredScaled("Guide", 8, SCALE)
    local y = 30
    for _, e in ipairs(HELP_ENTRIES) do
        drawHelpIcon(e.icon, 20, y + 3, SCALE)
        TextUI.drawTextScaled(e.label, 46, y, SCALE)
        local labelW = math.ceil(TextUI.textWidth(e.label) * SCALE)
        TextUI.drawTextScaled("- " .. e.desc, 46 + labelW + 10, y, SCALE)
        y = y + LINE
    end
    TextUI.drawTextCenteredScaled("B = Back", 212, SCALE)
end

return Tutorial
