# VISUAL_SPEC — Ringe (Playdate)

Verbindliche visuelle Referenz für die Figurenfamilie. 1-Bit, Hintergrund schwarz,
Bahnen weiß. Diese Datei beschreibt die Referenzdarstellung (auf schwarzem Grund)
und die In-Game-Umsetzung auf den weißen Bahnen.

## Grundprinzip

Zwei bewusst stark unterschiedliche Silhouetten + ein reiner Signifier:

- **PLAYER**: großer runder Körper + großer runder, aus der Mitte versetzter Innenkreis.
- **BABY**: kleiner quadratischer Rahmen + runder Kreis in der Mitte.
- **BABY DOCK**: vier L-förmige Eckmarken, die ungefähr die quadratische Babyfläche
  umschreiben.

In-Game-Hinweis: Die Figuren stehen im Gameplay IMMER auf der weißen Bahn bzw.
weißen Brücke. Dort gilt die „Papier-Version“ (schwarze Zeichnung auf weißem
Grund): der Player ist eine vollflächige schwarze Kugel mit weißer Pupille, das
Baby ein schwarzer Quadratrahmen mit schwarzem Mittelpunkt. Auf rein schwarzem
Grund hält eine weiße Unterlage beide Figuren lesbar (weißer Halo hinter dem
schwarzen Player-Körper, weiße Fläche unter dem schwarzen Baby-Rahmen). Die
Formidentität ist in beiden Fällen identisch.

---

## PLAYER

    SHAPE = filled circle (vollflächiger runder Körper)
    BODY  = black (gefüllter schwarzer Außenkörper; auf der weißen Bahn als
            vollflächige schwarze Kugel lesbar)
    INNER = white movable circle (weiße Pupille, deutlich aus der Mitte versetzbar)
    HALO  = white underlay außerhalb des Körpers (nur am Bahnrand auf schwarzem
            Grund sichtbar; auf der Bahn unsichtbar)

- BODY DIAMETER: 12 px Kern (config.playerRadius 6); zusammen mit dem schwarzen
  Außenbereich (config.playerStroke 2) durchgehend schwarz bis ~16 px
- INNER / PUPIL: ca. 6 px (config.pupilRadius 3.0), WEISS, ~50 % des Kerns
- INNER TRAVEL: tangential in Facing-Richtung, max. config.pupilTravel (2.4 px)
- IDLE GAZE: im Stillstand wandert die Pupille auf einer sanften Acht (Lissajous
  1:2, config.idleGazeTravel 2.0 px) um die Körpermitte — süßes Herumschauen,
  kein starrer Kern-Blick
- KEINE Gliedmaßen, KEINE rechteckige Form, KEINE Schraffur.
- Muss eindeutig als „großer runder schwarzer Charakter mit hellem Innenkreis“
  lesbar sein.

### Animationen (erhalten, unverändert)

- Facing CW / CCW
- Pupillenverschiebung (tangential, Bewegungsrichtung; weiße Pupille)
- Blink (weiße Lidlinie auf dem schwarzen Körper; Timing 1.5–3 s,
  config.blinkMinInterval/blinkMaxInterval)
- Widen (Schalterkontakt)
- Squint (Shutter-Kollision, exakt 6 Frames; weiße Lidlinie). Impact-Reaktion:
  der Körper staucht sich dabei kurz zusammen — radial 1.5 px + tangential
  1 px (config.impactBodyCompression/impactBodyTanCompression), die Lidlinie
  ist etwas länger als der Blink (config.impactSquintHalfLen 2.5). Flanken-
  erkennung: kein Flackern bei gehaltenem Anstoß.
- Shutter-Reaktion
- Bridge-Stretch (Ellipsenstreckung beim Transit)
- Push-Kompression (Baby-Push)
- Idle-Look (Core-Gaze)
- Shared-Transit-Blick (Fokus + Landing + Blick zum Baby)

---

## BABY

    SHAPE  = square outline (quadratischer Rahmen, Screen-Space stabil,
             NICHT mit dem Ringwinkel rotiert)
    FRAME  = white (Referenz auf schwarz); auf der weißen Bahn als schwarzer
             1-px-Rahmen sichtbar (Papier-Version)
    INTERIOR = black (Referenz auf schwarz); auf der Bahn weiß/transparent
    INNER  = small white circle (Referenz auf schwarz); auf der Bahn als
             schwarzer Mittelkreis sichtbar
    DEFAULT INNER POSITION = centered / near-centered
    ANIMATION = blink + subtle look + push/bridge reactions

- OUTER SIZE: 8×8 px (config.babyOuterSize 8; Halbseite 4)
- FRAME: 1 px (config.babyStroke), klar geschlossen, quadratisch
- INNER SIZE: 4 px Durchmesser (config.babyInnerRadius 2), zentral
- Blink: kurzer horizontaler Strich an derselben Position (config.babyBlinkFrames 3)
- Blink-Timing: 1.2–2.5 s (config.babyBlinkMinInterval/MaxInterval), eigenständig
  vom Player, keine Synchronisation
- Kein Halo, keine Kontur außer dem Rahmen, keine Rotation, keine Gliedmaßen

### Blickverhalten (aufmerksam)

- NORMAL: Innenkreis folgt IMMER dem Player (Screen-Vektor baby->player,
  config.babyLookTravel 1.2 als max. Versatz). Gleicher Ring: tangential,
  verschiedene Ringe: inward/outward.
- BEIM SCHIEBEN: Innenkreis geringfügig in Bewegungsrichtung (tangential).
- BRIDGE READY: Innenkreis kurz Richtung Brücke (radial).
- SHARED TRANSIT: Innenkreis in Transitrichtung (radial zum Zielring).
- LANDING: zurück Richtung Zentrum.
- Kein Blickfenster, keine zeitgesteuerte Glance-Logik (entfernt); die höher
  priorisierten Reaktionen (Push/Bridge/Transit/Settle/Landing) überschreiben
  das Tracking.

### Push / Blocked (mechanisch, minimal)

- PUSH: max. 1 px Kompression in Pushrichtung (config.babyPushCompression), kein
  Bounce, keine Rotation, kein Wackeln.
- BLOCKED: kurze Squint-Linie + minimale 1-px-Kompression (config.babyBlockedFrames),
  schwächer als der Player, kein Retrigger bei gehaltener Blockade.
- BRIDGE READY: keine Körperpulsation mehr (entfernt).
- TRANSIT: max. 1 px längsgerichtete Streckung (config.babyTransitStretch);
  Quadratidentität bleibt erhalten.

---

## BABY DOCK

    SHAPE  = four L-shaped corner markers (Referenz-Variante A)
    COLOR  = white (auf dem schwarzen Grund um die Bahn sichtbar)
    FILL   = none
    CENTER MARK = none
    DOTS   = none
    VISIBILITY = only contextually near relevant bridge

- FOOTPRINT: 12×12 px (config.babyDockHalf 6)
- CORNER LENGTH: 2 px je Schenkel (config.babyDockArm), 1 px Strichstärke
- Position: exakt an der gültigen Baby-Dockposition (Babyring auf der
  Brückenachse); Mittelpunkt der vier Eckmarken == Baby-Dockposition.
- KEINE vollständige Box, KEIN Kreis, KEIN Punkt in der Mitte, KEINE Punktmatrix.
- KEINE Verwechslung mit der Bridge-Punktspur möglich (Punkte bedeuten im Spiel
  mögliche/inaktive Brücken).
- READY FEEDBACK: einmaliges 1-px-Nach-innen über 2-3 Frames, wenn das Baby die
  korrekte Position erreicht (kein Puls, kein Blinken, kein Ready-Punkt).

### Sichtbarkeit (kontextuell)

Das Dock erscheint NUR, wenn die konkrete Brücke für die aktuelle Situation
relevant ist (Render.babyDockForBridge):

- Baby vorhanden, auf demselben Ring wie der Player (Shared Transit möglich)
- Brücke aktiv
- Player UND Baby in sinnvoller Nähe zur Brückenachse
  (config.babyDockProximityRange 45°)
- kein laufender Transit / keine Kamera-Transition

Nicht: „Baby irgendwo auf demselben Ring → Dock erscheint sofort“.

---

## PLAYER DOCK

    SHAPE  = bracket form [ ] (zwei vertikale Klammerbalken links/rechts mit
            kleinen Einhak-Füßen zur Mitte)
    COLOR  = white (auf dem schwarzen Grund um die Bahn sichtbar)
    FILL   = none
    CENTER MARK = none
    DOTS   = none
    VISIBILITY = only contextually near relevant bridge

- FOOTPRINT: kompakt (~13×11 px, config.playerDockHalf 6, playerDockBar 5) —
  kleiner als das Baby-Dock und klar als KLAMMER [ ] lesbar (das Baby-Dock
  nutzt vier L-Ecken): nie verwechselbar.
- BAR: 1 px, Länge 10 px je Balken; Füße 2 px lang, zeigen zur Mitte
  (config.playerDockFoot). Die Mitte bleibt offen.
- Position: NUR im GEMEINSAMEN Transit an der Dockformation direkt hinter dem
  Baby (config.sharedFormationGapDeg, in Schieberichtung); im Solo-Fall gibt es
  KEIN Player-Dock (die aktive Brücke selbst + die Bridge-Silhouette zeigen den
  Weg). Am TOR nur im Shared-Kontext.
- READY FEEDBACK: einmaliges 1-px-Nach-innen über 2-3 Frames, wenn der Transfer
  bereit wird (gleiche Flanke wie das Baby-Dock).
- Sichtbarkeit: gleiche kontextuelle Regel wie das Baby-Dock (aktive Brücke +
  Nähe des Players, config.babyDockProximityRange 45°); kein laufender Transit /
  keine Kamera-Transition. Am TOR nur im Shared-Kontext.

---

## BRIDGE SILHOUETTES (Ghost-Formen)

    PLAYER = thin dashed circle outline (gestrichelter Kreis, config.playerGhostRadius 5)
    BABY   = thin square outline (dünnes Quadrat, config.babyGhostHalf 4)
    COLOR  = black (auf der weißen Brücke; Papier-Form wie die Figuren)
    FILL   = none (nur 1-px-Umriss)
    VISIBILITY = NUR wenn der Player im Wechsel-Radius steht (Bridge.isUsable:
            aktive Brücke + innerhalb dockRange) — genau dann, wenn er wirklich
            wechseln kann

- Liegen direkt auf der Brückenachse (Mitte bzw. Baby zum Zielring hin,
  Player dahinter; config.ghostRadialOffset 0.15).
- Gemeinsamer Transit: beide Geister; Solo: nur der Player-Geist in der Mitte.
- Zeigen, wohin Player und Baby beim Transit laufen. Nicht dominant, nie alle
  Brücken vollstellen; KEINE Geister auf entfernten, noch nicht nutzbaren
  Brücken.

---

## DOPPELSCHALTER (aktive Richtung)

- Beide Innenkreise bleiben sichtbar; die AKTIVE Richtung (CW = A, CCW = B) ist
  als GEFÜLLTER schwarzer Kreis markiert, die inaktive Seite als reine
  schwarze KONTOUR (Kreismitte weiß). Beim Umschalten wandert die Füllung auf
  die andere Seite.
- Keine neuen Symbole, keine Textlabels A/B.

---

## Unterschiede (verbindlich)

| | FORM | MASS | INNER ELEMENT | PERSONALITY |
|---|---|---|---|---|
| PLAYER | CIRCLE | FILLED (schwarz) | LIGHT CIRCLE (weiße Pupille) | stärker bewegliche Pupille |
| BABY | SQUARE OUTLINE | HOLLOW (schwarzer Rahmen) | DARK CIRCLE (schwarzer Mittelpunkt) | ruhiger / zentraler |
| BABY DOCK | FOUR CORNERS | NONE | NONE | keine – nur Signifier |
| PLAYER DOCK | OPEN FRAME (Seitenmitten) | NONE | NONE | keine – nur Signifier |
| BRIDGE GHOST | DASHED OUTLINES | NONE | NONE | Vorschau/Geist |

Ein einzelner 400×240-Frame muss genügen, um die drei Formen eindeutig zu
unterscheiden.
