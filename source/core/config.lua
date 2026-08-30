Config = {
    -- Bildschirmmitte in Pixel
    centerX = 200,
    centerY = 120,

    -- Refreshrate in Hz (fester Frame-Step)
    refreshRate = 50,

    -- Radien in Pixel
    outerRadius = 104,
    -- Mittelring (3-Ring-Raum, Level 4): exakt zwischen Außen- und Innenring.
    -- Die Kamera leitet Radien aus RingNUMMERN ab (Radius = outerRadius -
    -- (visualOuter - ringNumber) * ringSpacing, ringSpacing = 36); ein
    -- Mittelring bei 86 entspricht der Ringnummer "outer - 0.5". Diese
    -- Konstante dient der Ring-abhängigen Figuren-Marge (Baby.shutterMarginDeg)
    -- und bleibt mit der Kameraformel konsistent (86 = 104 - 18).
    middleRadius = 86,
    innerRadius = 68,
    -- Kernbasis: 37 px (etwas größer als die früheren 34 px, damit normale
    -- Center-Bridges sauber und bündig an der Außenkante anschließen — keine
    -- sichtbare schwarze Lücke zwischen Kernbrücke und Mittelpunkt). Der Kern
    -- bleibt bewusst KOMPAKT: selbst in Raum 8 (37 + 7*2 = 51) hält er einen
    -- großen Abstand zum inneren Ring (68) — der Mittelpunkt dominiert die
    -- Bahnen nicht (ab Level 5 zuvor viel zu groß).
    coreRadius = 37,
    -- Kernbrücke (Gate) Überlappung: die normale Brücke zum Mittelpunkt endet
    -- nicht exakt auf der (dither-gepunkteten) Kernkante, sondern greift um
    -- diesen kleinen Betrag IN den Kern — dadurch ist die Verbindung an der
    -- Stelle immer vollflächig weiß (kein sichtbarer Spalt am Übergang), ohne
    -- tief in den Mittelpunkt hineinzuragen.
    coreBridgeOverlap = 2,
    -- Zentrums-Regel (Echo-Ring): liegt der Future-Ring näher als dieser
    -- Abstand an der Kernkante, wird er nicht gezeichnet (Raum 1: Kern 37,
    -- Future 32 -> unterdrückt). Room 2+ (Kern deutlich größer) zeichnet ihn.
    coreEchoHideMargin = 3,

    -- Abmessungen in Pixel
    trackWidth = 8,
    -- Spieler (verbindliche Referenz): ein kompakter VOLLSTÄNDIG SCHWARZ
    -- GEFÜLLTER Kreis (~12 px Durchmesser = playerBodyRadius 6) mit EINEM
    -- großen weißen runden Augenkreis (~5 px = 40-50 % der Körperbreite) und
    -- einer 1-px-WEISSEN Außenkontur (playerOutlineWidth): sichtbar, weil der
    -- Körper breiter als die Bahn ist und die Kontur gegen den schwarzen
    -- Grund zeichnet (auf der weißen Bahn selbst geht sie darin unter).
    -- playerRadius bleibt der GAMEPLAY-Kontaktradius (Push/Kollision/Shutter
    -- unverändert).
    playerRadius = 6,        -- GAMEPLAY-Kontaktradius (px), unverändert
    playerBodyRadius = 6,    -- VISUELLER Körperradius (px) -> 12 px Durchmesser (11-13 px)
    playerStroke = 0,        -- nicht mehr genutzt (Körper = playerBodyRadius)
    playerHalo = 0,          -- keine weiße Unterlage mehr
    playerOutlineWidth = 1,  -- WEISSE Außenkontur um den schwarzen Körper (px)
    -- Pupille (Auge): großer weißer runder Kreis, Radius 2.5 px (~5 px
    -- Durchmesser = 42 % der 12-px-Körperbreite). maxOffset =
    -- playerBodyRadius - pupilRadius - 0.5 = 3.0. pupilTravel (Bewegungsblick)
    -- ist moderat, sodass das Auge bei echter Bewegung tangential leicht
    -- vorausschaut, aber immer vollständig im Körper bleibt.
    pupilRadius = 2.5,       -- WEIẞES AUGE: Radius 2.5 px (~5 px Durchmesser, klar sichtbar)
    pupilTravel = 2.0,       -- Bewegungsblick: tangentialer Versatz in Facing-Richtung (px)
    pupilWidenBoost = 0.4,   -- Widen (Schalterkontakt): Auge kurz etwas größer (px; per Clamp im Körper)
    -- Idle-Herumschauen (neugierig/verspielt, NICHT hektisch): nach einer
    -- ZUFÄLLIGEN Ruhezeit ein kurzer Blick in eine ZUFÄLLIGE Richtung
    -- (innen/außen/CW/CCW/neutral), kurz halten, sanft zurück, neue Ruhe.
    idleLookTravel = 1.5,          -- Blick-Amplitude (px; <= maxOffset 3.0)
    idleLookMoveTime = 0.25,       -- sanftes Einschwenken zum Blickziel (s)
    idleLookHoldMin = 0.4,         -- Blick halten: minimal (s)
    idleLookHoldMax = 1.0,         -- Blick halten: maximal (s)
    idleLookReturnTime = 0.3,      -- sanftes Zurückkehren (s)
    idleLookFirstRestMin = 1.5,    -- erste Ruhe vor dem ersten Blick (s)
    idleLookFirstRestMax = 2.5,    -- erste Ruhe vor dem ersten Blick (s)
    idleLookRestMin = 1.5,         -- Ruhe zwischen Blicken: minimal (s)
    idleLookRestMax = 3.5,         -- Ruhe zwischen Blicken: maximal (s)
    -- Finales Rendering (Phase 8.2), visuelle Tuningwerte
    -- Kernradius-Wachstum pro Raum (ARCHITECTURE coreGrowth). Bewusst KLEIN
    -- (2 px): der Mittelpunkt soll die Bahnen nie dominieren — selbst in Raum
    -- 8 (37 + 7*2 = 51) bleibt ein großer Abstand zum inneren Ring (68). Die
    -- frühere Wachstumsrate 4 machte den Kern ab Level 5 (53) viel zu groß.
    coreGrowthPerRoom = 2,
    corePulseAmplitude = 0.6, -- Haupt-Atemwelle des Kerns (px, flacher -> Puls-Minimum größer)
    corePulsePeriod = 3.0,   -- Sekunden pro Hauptwelle
    -- Legacy (nicht mehr genutzt): Die Kernbrücke (Gate) ist seit dem Center-
    -- Bridge-Fix eine NORMALE Brücke (gleiche Breite bridgeBodyWidth, gleiche
    -- Punktspur/Form). Keine zweite Center-Bridgebreite, kein Stummel mehr.
    bridgeWidth = 6,         -- Legacy: alte Gate-Balkenbreite (unbenutzt)
    stubLength = 5,          -- Legacy: alter eingefahrener Gate-Stummel (unbenutzt)
    -- Brücken-Look (Design-Legende, Teil 3): INAKTIV = klare Punktspur (5-7
    -- identische weiße Punkte, Radius 1.5, Abstand 6 px) auf der Brücken-
    -- achse — nur möglicher Übergang, keine fertige Brücke.
    -- AKTIVIERUNG (ruhige Dichte-Verdichtung, keine Wanderung): die Punkt-
    -- positionen bleiben ABSOLUT stabil — es werden nur Zwischenräume ergänzt.
    --   Stufe 1: 7 Ankerpunkte (Abstand 6 px)
    --   Stufe 2: + Mittelpunkte exakt zwischen den Ankern (Abstand 3 px)
    --   Stufe 3: volle dichte Achsenpunktlinie (Abstand bridgeGridStep)
    --   Stufe 4: + Reihen über/unter der Mittellinie (Breite, Material-
    --            verdichtung innerhalb der finalen Silhouette)
    --   Stufe 5 (p=1): durchgehender weißer Brückenkörper (bridgeSolidStart 1)
    -- Deaktivierung läuft exakt rückwärts. Timing ~0.18 s.
    bridgeBodyWidth = 9,           -- AKTIV: Breite der weißen Brücke (px, Bahn 8 + 1)
    bridgeDotRadius = 1.5,         -- INAKTIV/Animation: Punktradius (px, gut lesbar)
    bridgeGridStep = 2,            -- Verdichtung: radialer Gitterabstand der Achsenpunkte (px)
    bridgeGridRowStep = 3,         -- Verdichtung Stufe 4: tangentialer Reihenabstand für die Breite (px)
    bridgeSolidStart = 1.0,        -- Verdichtung: die weiße Form erscheint erst ganz am Ende (p=1)
    bridgeExtendDuration = 0.18,   -- Aktivierung/Deaktivierung: Gesamtdauer der Dichte-Verdichtung (s)
    bridgeSettleFrames = 2,        -- Brücke voll ausgefahren: 1 px Nachsetzen (Frames)
    bridgeReadyFrames = 3,         -- Ready-Impuls: Frames minimal kräftiger
    -- Blockade-Mittelpunkt: ein klarer runder Punkt exakt im geometrischen
    -- Zentrum des Sperrsegments (gehört zum Blockade-Design, KEIN Kausalitäts-
    -- symbol). Geschlossen: WEISS auf dem schwarzen Sperrblock (~3 px). Offen:
    -- sehr reduzierter schwarzer Positionspunkt auf der weißen Bahn (~2 px),
    -- damit die ehemalige Blockadenposition subtil identifizierbar bleibt,
    -- ohne den Weg blockiert wirken zu lassen.
    shutterCenterDotRadius = 1.5,      -- Blockade geschlossen: Mittelpunkt-Radius (px, weiß)
    shutterOpenCenterDotRadius = 1.0,  -- Blockade offen: reduzierter Positionspunkt-Radius (px, schwarz)
    -- Einmal-Motiv (gemeinsame Regel: grobe schwarze Diagonalschraffur auf
    -- weißem Grundkörper = Einmal-Element). Einmal-Brücke = normale weiße
    -- Brückenform + Schraffur; Einmalschalter = normale weiße Schalterform
    -- + dieselbe Schraffur. Gleiche Linienrichtung (links unten -> rechts
    -- oben, lokal mit dem Objekt mitgedreht), gleiche Stärke (1 px), gleiche
    -- Abstände/Rhythmik: Schritt 8, Länge 6 -> Einmalschalter 3 Striche,
    -- Einmal-Brücke 4 Striche (Referenz: „[ ● / / / ● ]“ bzw. „██/███/███/███/██“).
    -- Das Weiß des Körpers dominiert; die Striche liegen klar getrennt mit
    -- großen gleichmäßigen Abständen. Kein Dither, keine Kreuzschraffur,
    -- keine zweite Einmal-Sprache. Kein Kausalitätscode — reine Markierung.
    oneShotHatchStep = 8,          -- Einmal-Motiv: Abstand der Schraffurstriche (px, Schalter + Brücke)
    oneShotHatchLen = 6,           -- Einmal-Motiv: Strichlänge (px, je Achse; über den Großteil der Körperbreite)
    -- Einmal-Brücke, AKTIV: eigene, kürzere Schraffur (Schalter unverändert).
    -- Die Striche bleiben deutlich VOR den weißen Längskanten der Brücke
    -- zurück (len 4 auf Körperbreite 9 -> ~2.5 px weißer Rand oben/unten),
    -- damit die zusammenhängende weiße Brückensilhouette nie in einzelne
    -- Diamanten/Segmente zerfällt. Gleiche Sprache wie der Einmalschalter.
    oneShotBridgeHatchStep = 9,    -- Einmal-Brücke aktiv: Strichabstand (px, gleichmäßig, wenige Linien)
    oneShotBridgeHatchLen = 4,     -- Einmal-Brücke aktiv: Strichlänge (px, Rand bleibt weiß)
    -- Einmal-Motiv, INAKTIVE Einmal-Brücke (reduzierte Schraffur): die Brücke
    -- bleibt auch eingefahren als Einmal-Element erkennbar. Kurze, dünne WEISSE
    -- Diagonalstriche (Papier-Inversion auf schwarzem Grund) in den Lücken der
    -- Punktspur — gleiche Richtung/Sprache wie die aktive Schraffur, aber
    -- deutlich reduziert, damit die Punktspur („noch keine Brücke“) lesbar bleibt.
    oneShotInactiveHatchStep = 12, -- Einmal-Motiv inaktiv: Abstand der reduzierten Striche (px) -> 3 Striche
    oneShotInactiveHatchLen = 4,   -- Einmal-Motiv inaktiv: Strichlänge (px, je Achse)
    oneShotInactiveHatchWidth = 1, -- Einmal-Motiv inaktiv: Strichstärke (px)
    -- Start-Offset der reduzierten Striche entlang der Brückenlänge (t-Achse,
    -- rel. zur Brückenmitte): -9 -> Radien 77/89/101, exakt in den Lücken der
    -- Punktspur (Punkte bei Radien 74/80/86/92/98, Strich halbe Länge 2).
    oneShotInactiveHatchStart = -9,

    -- Einmalschalter-VERSCHWINDEN (nach dem Verbrauch): kurze Animation —
    -- leichter „Anspann“-Puls (Quellen auf ~1+Grow), dann beschleunigtes
    -- Zusammenfallen in den Mittelpunkt (die Bahn bleibt frei). Rein visuell.
    oneShotSwitchVanishDuration = 0.32, -- Gesamtdauer der Verschwinde-Animation (s)
    oneShotSwitchVanishPulse = 0.18,    -- Anteil der Anspann-Phase (0..1)
    oneShotSwitchVanishGrow = 0.25,     -- Anspann-Zuwachs (Faktor, 1 -> 1+Grow)

    -- Druckplatte (momentan): gedrückt, solange Player ODER Baby auf demselben
    -- Ring im Druckbereich steht (Winkelabstand < platePressRange). Löst aus,
    -- sobald niemand mehr draufsteht — kein Rasten. Rein positionsabhängig:
    -- kein Undo-Eintrag, kein Schalterzustand (Position ist Teil des Snapshots).
    -- Steuert genau ein Element (Blende).
    -- DARSTELLUNG: exakt die Baby-Form ohne Auge — die Platte nutzt direkt die
    -- Baby-Visual-Konstanten babyOuterSize und babyStroke (1-px-Rahmen), damit
    -- die Platte genauso aussieht wie die Baby-Stellfläche. Keine eigenen
    -- Größen-Konstanten (bewusst: gleiche Form, kein Drift). GEDRÜCKT = nur
    -- eine sehr kleine 1-px-Reaktion (Rahmen 1 px dicker, Inneres rückt 1 px
    -- zusammen), die leere Rahmenform bleibt lesbar — kein Füllen/Mulde/Icon.
    -- PRÄZISION (Auftrag): die Druckplatte reagiert nur, wenn das Baby (oder
    -- der Player) WIRKLICH auf der Platte steht — der Druckbereich ist sehr
    -- klein (± platePressRange Grad), damit das Baby sichtbar exakt auf der
    -- Platte geparkt werden muss („genau auf der Platte, sonst geht es nicht“).
    platePressRange = 2,           -- Druckbereich der Platte (± Grad um plate.angle, präzise)

    -- Druckplatte DARSTELLUNG (Auftrag: "Teil der Ringbahn, aber SOFORT
    -- erkennbar"): die Platte ist ein BAHNSEGMENT — radial exakt über die
    -- volle Bahnbreite (trackWidth), tangential plateSize px breit — mit
    -- SCHWARZER Innenfläche und kräftiger WEISSER Outline (plateOutlineWidth
    -- 3 px). Die Ringlinie endet sauber an der Plattenkante, die Platte folgt,
    -- danach setzt die Bahn fort. Das schwarze Baby-Quadrat passt exakt in
    -- die schwarze Innenfläche.
    plateSize = 13,                -- tangentiale Plattenbreite (px; Baby 9 px + 2x2 Rand)
    plateOutlineWidth = 3,         -- WEISSE Outline-Stärke (px, deutlich sichtbar, dicker als früher)

    -- Druckplatte MAGNET (Auftrag: "leicht magnetisch"): wenn Player oder Baby
    -- IDLE sehr nah an einer Plattenmitte stehen (gleicher Ring, innerhalb
    -- plateSnapRange), rastet die Figur sanft über plateSnapFrames auf die
    -- exakte Plattenmitte ein. Kleiner Fangbereich, weiches kurzes Einrasten,
    -- kein Teleport, keine starke automatische Bewegung; die Steuerung wird
    -- nicht weggenommen (greift nur ohne Bewegungsinput).
    plateSnapRange = 2.5,          -- Fangbereich (± Grad um plate.angle)
    plateSnapFrames = 8,           -- weiche Snap-Dauer in Frames (50 fps -> ~0.16 s)

    -- Steuerung: Ringgrad pro Kurbelgrad bzw. Grad pro Sekunde
    crankRatio = 0.5,
    dpadSpeed = 90,
    -- Kurbel-Widerstand kurz vor dem Brückenübergang (Auftrag): unmittelbar
    -- vor dem Dock einer AKTIVEN Brücke wird der Kurbelanteil leicht gedämpft
    -- (subtile Schwelle/Reibung — „hier ist etwas Besonderes“). Nur lokal
    -- (wenige Grad VOR dem Dock), kein harter Lock, kein Ruckeln; D-Pad bleibt
    -- immer ungedämpft. Fährt der Player wieder weg, greift sofort wieder die
    -- normale Bewegung.
    bridgeResistanceRange = 3,        -- Widerstandszone: Grad vor dem Dock (dockRange 12 .. 15)
    bridgeResistanceFactor = 0.95,    -- Widerstand: Multiplikator auf den Kurbelanteil in der Zone (deutlich reduziert)

    -- Bögen in Grad
    shutterArcWidth = 26,
    switchArcWidth = 14,
    -- Dockzone Brücke/Gate (Grad, inklusiv): moderat großzügig, damit man nicht
    -- pixelgenau andocken muss. Geometrisch begründet: der Spielerkörper
    -- (playerRadius 6 px) überlappt den Brückenkörper (bridgeBodyWidth/2 ≈ 4.5 px) auf
    -- dem innersten Ring (68 px) ab ~9,3° — 12° deckt das komfortabel ab.
    dockRange = 12,
    -- Andockhilfe: Bereich in Grad und exakte Frames für die sanfte Ausrichtung
    -- auf nutzbare aktive Brücken, Schalter und die Kernbrücke (Gate) — die
    -- Center-Bridge nutzt exakt dieselbe Fangzone wie jede Ring-Bridge.
    -- Unabhängig von dockRange. Bewusst KLEINER als dockRange: Assist nur
    -- unmittelbar am Dock, kein magnetisches Festkleben aus der Ferne.
    dockAssistRange = 6,
    dockAssistFrames = 3,
    -- Gemeinsame Shared-Dockzone (Brücke mit Baby): akzeptierte Toleranz für
    -- BEIDE Figuren relativ zur Brückenachse. Geometrisch abgeleitet: Player
    -- (6 px) + Baby (3.7 px) + halbe Brücke (3 px) = 12.7 px -> ~10.7° auf dem
    -- innersten Ring (68 px); plus großzügiger Spielraum für handliches
    -- Andocken (moderat größer als der alte Player-dockRange 12 / Baby 16).
    -- Die relative Formation (Baby nicht hinter dem Player) wird separat
    -- geprüft, damit kein falscher Shared-Transit entsteht.
    sharedDockRange = 15,
    -- Relative-Formationstoleranz (Grad): das Baby darf hinter dem Player
    -- liegen, solange der Versatz diese kleine Toleranz nicht überschreitet.
    sharedFormationTolDeg = 2,

    -- Animationsdauern in Sekunden
    shutterAnimDuration = 0.2,
    -- Brückenüberquerung/-transit (radiale Bewegung), währenddessen keine Eingabe
    bridgeAnimDuration = 0.35,
    cameraDuration = 1.2,

    -- Schaltervorschau (Phase 8.3): gesteuerte Elemente naher Schalter werden
    -- mit einer 1-px-Aufhellung ihrer Kontur hervorgehoben (1 Blinkzyklus/s).
    -- Rein visuell; kein Gameplay-Effekt.
    switchPreviewEnabled = true,  -- Effekt komplett abschaltbar (Playtest-Vergleich)
    switchPreviewRange = 20,      -- Grad; streng < 20° (exakt 20° ausgeschlossen)
    previewBlinkPeriod = 1.0,     -- Sekunden pro Blinkzyklus (0.5 s ON / 0.5 s OFF)

    -- Spieler-/Augenanimation (Phase 8.4), visuelle Tuningwerte. Nur
    -- shutterSquintFrames ist konzeptzwingend (exakt 6 Frames); die Blink-
    -- Intervalle sind Tuning (User: häufigeres Blinzeln — 1.5-3 s).
    blinkMinInterval = 1.2,    -- Blink frühestens nach 1.2 s Stillstand (zufällig, häufig)
    blinkMaxInterval = 3.0,    -- Blink spätestens nach 3.0 s Stillstand (zufällig)
    blinkFrames = 4,           -- Blinkdauer in Frames (kurz, 50 fps)
    -- Spieler-PARTIKELSCHWEIF (leichtes Partikelsystem beim Bewegen): beim
    -- echten Bewegen spawnt der Player kleine weiße Partikel knapp AUSSERHALB
    -- der Bahn (auf schwarzem Grund), die kurz hinter ihm herschrumpfen und
    -- radial nach außen driften — ein dezenter Schweif. Rein visuell.
    playerTrailLife = 0.3,     -- Partikellebensdauer (s)
    playerTrailSpawn = 2,      -- Partikel pro Bewegungs-Frame
    playerTrailSize = 1.5,     -- Partikel-Startradius (px)
    playerTrailOffset = 0,     -- radialer Versatz vom Bahnzentrum (0 = exakt auf der Ringbahn)
    playerTrailDrift = 0,      -- radiale Drift über die Lebensdauer (0 = bleibt auf der Bahn)
    playerTrailMax = 40,       -- Obergrenze gleichzeitiger Partikel (Flut-Schutz)
    switchEyeWidenFrames = 6,  -- Augenweiten-Dauer in Frames
    shutterSquintFrames = 6,   -- Zusammenkneifen: exakt 6 Frames (verbindlich)
    bridgeStretchAmount = 2,   -- maximale radiale Streckung (px je Seite)
    -- Impact-Reaktion (Auftrag: Segment-Kollision): stoppt der Player an einer
    -- geschlossenen Blende, staucht sich der Körper kurz zusammen (radial +
    -- leicht tangential — als ob die Figur anstößt) und das Auge kneift zu.
    -- Dauer = shutterSquintFrames (6 Frames); die Flankenerkennung in
    -- noteShutterBlocked verhindert dauerhaftes Flackern bei gehaltenem Druck.
    -- Bewusst subtil verstärkt gegenüber der Basis-Reaktion (1 px), keine
    -- große Cartoon-Animation.
    impactBodyCompression = 1.5,      -- Impact: radiale Stauchung des Körpers (px)
    impactBodyTanCompression = 1.0,   -- Impact: tangentiale Stauchung des Körpers (px)
    impactSquintHalfLen = 3.0,        -- Impact: halbe Länge der Squint-Lidlinie (px; deckt das ~2.5-px-Auge)
    blinkLidHalfLen = 2.6,            -- Blink: halbe Länge der geschlossenen Lidlinie (px; deckt das Auge)
    -- Player-Auge beim GEMEINSAMEN Brückentransit (Pass „Player-Eye“):
    -- Transit-Fokus (wenige Frames am Start, Pupille leicht größer + stärker
    -- radial), Landing-Squint (kurze Lidlinie nach der Landung) und ein kurzer
    -- Blick zum Baby nach der Ankunft. Nur wenige Pixel, keine Cartoon-
    -- Animation; Pupille bleibt per Clamp immer im Augenkörper.
    transitFocusFrames = 5,    -- Fokus-Boost am Transitstart (Frames)
    transitFocusPupilBoost = 0.4, -- +px Augenradius während des Fokus (im Körper per Clamp)
    transitFocusTravelBoost = 0.3, -- +px Pupillen-Travel während des Fokus (per Clamp begrenzt)
    -- Landing nach dem gemeinsamen Transit: wenige Frames Blink-Priorität
    -- (das Auge bleibt SICHTBAR — normale Pupille + kurzer Blick zum Baby,
    -- KEIN Lidlinien-Squint, der das Auge verschwinden lässt).
    landingSquintFrames = 3,   -- Landing-Frames nach gemeinsamem Transit
    lookAtBabyFrames = 8,      -- kurzer Blick zum Baby nach der Landung (Frames, ~0.16 s)

    -- Baby (generisch, Begleiter): QUADRATISCHER RAHMEN + runder Innenkreis
    -- (Referenz: kleine quadratische Silhouette, klar vom runden Player
    -- getrennt). Visualgröße und Gameplay-Kontaktradius sind sauber getrennt:
    -- babyRadius/babyStroke (Gameplay-Kontakt/Schieben/Kollision) bleiben
    -- unverändert; die reine Darstellung nutzt babyOuterSize/babyInnerRadius.
    babyRadius = 3.7,              -- GAMEPLAY-Kontaktradius (px), unverändert (Schieben/Kollision)
    babyStroke = 1,                -- Rahmenstärke (px); auch Gameplay-Marge (Shutter-Stopp)
    babyOuterSize = 8,             -- Visual (Druckplatte): äußere Quadratgröße (px), bleibt für die Platte
    babyInnerRadius = 2.0,         -- Visual (Druckplatte): runder Innenkreis (px), bleibt für die Platte
    -- BABY-KÖRPER (neuer Look, wie der Player): schwarze Kugel + 1-px weiße
    -- Außenkontur + RIESIGE weiße Pupille (süß). Baby-Radius ~5.5 px (~11 px
    -- Durchmesser, etwas kleiner als der Player 12 px); Pupille 4 px (~8 px
    -- Durchmesser = deutlich größer als die Player-Pupille 5 px — „riesige
    -- süße Pupille“). Visualgröße ist von babyRadius (Gameplay) getrennt.
    babyBodyRadius = 5.5,          -- Visual: Körperradius der runden Baby-Kugel (px) [nicht mehr genutzt: Baby ist Quadrat]
    babyPupilRadius = 4.0,         -- Visual: Radius der großen weißen Pupille (px) [nicht mehr genutzt]
    babyOutlineWidth = 1,          -- Visual: weiße Außenkontur (px, wie beim Player) [nicht mehr genutzt]
    -- Baby-REDESIGN (Auftrag): das Baby ist ein VOLLSTÄNDIG SCHWARZ gefülltes
    -- Quadrat — KEINE Augen/Pupille/Outline/Blink-Animation. Baby-Breite =
    -- exakt die normale Bridge-Breite (bridgeBodyWidth 9). Auf der weißen Bahn
    -- und der weißen Brücke bleibt es klar sichtbar; die Druckplatte ist auf
    -- diese Breite abgestimmt (plateSize = 9 + 2x2). Gameplay bleibt Push-only.
    babyVisualSize = 9,            -- Visual: Kantenlänge des schwarzen Baby-Quadrats (px = Bridge-Breite)
    -- Baby-Shutter-Kontakt (Auftrag: Baby-Kontakt): das Baby stoppt mit seiner
    -- sichtbaren Silhouette (Körper + Kontur) praktisch direkt an der Kante
    -- einer geschlossenen Blende — maximal ~0-1 px sichtbarer Abstand, NIE
    -- überlappend. babyShutterGapPx ist der nominale Restabstand der schwarzen
    -- Kontur zur schwarzen Shutterfläche (positiv = kein Overlap). Die Marge
    -- wird pro Ring aus diesem Wert + babyRadius + babyStroke berechnet
    -- (Baby.shutterMarginDeg), damit der Pixelabstand auf beiden Ringen gleich
    -- ist (kleiner Ring = mehr Grad pro px).
    babyShutterGapPx = 0.5,        -- sichtbarer Restabstand Kontur->Shutter (px)
    babyDockRange = 16,            -- Baby gilt als "am Bridge-/Gate-Dock" (Grad Abstand zu angle; gemeinsamer Transfer/Exit handlicher)
    babyCompanionOffsetDeg = 10,   -- Begleiter-Start in Folge-Räumen: Baby steht direkt hinter dem Player
    babyBridgeExitOffset = 10,     -- Austrittsposition nach Baby-Brückentransit (Grad, in Schieberichtung)
    babyBridgeAnimDuration = 0.25, -- Dauer des Baby-Brückentransits (s)
    -- Gemeinsame Dockformation (Ready/Transitstart): Player steht mit einem aus
    -- den Figurenradien abgeleiteten Abstand hinter dem Baby (innerster Ring als
    -- Worst Case für Grad->Pixel). 2 px Mindestabstand der Körper.
    sharedFormationGapDeg = (6 + 3.7 + 2) / 68 * (180 / math.pi),

    -- Baby-Polish (Lebendigkeit, rein visuell): eigene Blink-/Idle-/Reaktions-
    -- Logik im Renderer (UI-State, nie Gameplay/Snapshot/Save). Blink etwas
    -- eigenständiger/häufiger als der Player (User: häufigeres Blinzeln).
    babyBlinkMinInterval = 0.6,    -- Baby-Blink: frühestens nach 0.6 s Stillstand (häufig)
    babyBlinkMaxInterval = 1.5,    -- Baby-Blink: spätestens nach 1.5 s Stillstand
    babyBlinkFrames = 3,           -- Baby-Blinkdauer in Frames (kurze horizontale Lidlinie)
    babyPushFrames = 5,            -- Push-Reaktion: 1 px Kompression in Pushrichtung (Frames)
    babyLandingFrames = 9,         -- Bridge-Landing-Impuls (Frames, ~0.18 s)
    babyLookTravel = 1.2,          -- Innenkreis-Versatz (px) für Blick/Reaktionen (klein, ruhig)
    -- Baby-Blick: der Innenkreis folgt IMMER dem Player (Screen-Vektor
    -- baby->player), sobald keine höher priorisierte Reaktion aktiv ist — das
    -- Baby sucht den Player, wo immer er ist. Travel klein (babyLookTravel),
    -- kein googly-eye. Die frühere Glance-Fensterlogik wurde entfernt.
    -- Baby-Reaktionen (rein visuell, mechanisch-minimalistisch):
    babyPushCompression = 1,       -- Push: max. 1 px Kompression in Pushrichtung
    babyBlockedFrames = 4,         -- Blocked: kurze Squint-Reaktion (Frames), schwächer als Player
    babyTransitStretch = 1,        -- Transit: max. 1 px längsgerichtete Streckung (Quadratidentität bleibt)
    -- Baby-HOP (süßes/kindliches Verhalten): sanfter kontinuierlicher Bob
    -- (radial), beim Schieben/Landen ein kurzer freudiger Extra-Hüpfer mit
    -- leicht „großen Augen“. Rein visuell.
    babyHopAmount = 0.7,       -- Grund-Hüpfamplitude (px, sanft)
    babyHopSpeed = 8.0,        -- Hüpf-Geschwindigkeit (rad/s)
    babyExcitedFrames = 6,     -- Extra-Hüpfer-Dauer nach Push/Landing (Frames)
    babyExcitedHop = 1.8,      -- Extra-Hüpf-Höhe (px) während der Aufregung
    babyExcitedEye = 0.5,      -- Innenkreis-Boost (px) während der Aufregung
    -- Baby-Dock (vier L-förmige Eckmarken an der gültigen Babyposition vor
    -- einer Brücke; Referenz-Variante A). Kein Punkt, keine Box, kein Puls.
    babyDockHalf = 6,              -- Dock-Footprint-Halber (px) -> 12×12
    babyDockArm = 2,               -- Schenkellänge je Eckwinkel (px, 1 px Strichstärke)
    babyDockProximityRange = 45,   -- Dock-Sichtbarkeit: Player UND Baby innerhalb (Grad zur Brückenachse)
    babyDockReadyFrames = 3,       -- Ready-Feedback: Ecken 1 px nach innen (Frames, einmalig)
    -- Player-Dock (Auftrag: Positionshinweis Brückentransit): eigene reduzierte
    -- Markierung für die PLAYER-Zielposition am Brückenübergang — klar von der
    -- Baby-Dock-Sprache (vier L-Ecken) getrennt: eine kompakte KLAMMERFORM,
    -- die die Bahn „einklammert" (je ein tangentialer Balken knapp über und
    -- unter der Bahn, mit kleinen Einhak-Füßen zur Bahn). Nur RADIALE
    -- Versätze liegen auf schwarzem Grund (tangentiale Marker gehen in der
    -- weißen Bahn unter). Gemeinsamer Transit: Player-Dock an der Formation
    -- direkt hinter dem Baby; Solo: an der Brückenachse. Ready-Feedback wie
    -- beim Baby-Dock (1 px nach innen).
    playerDockHalf = 7,               -- Player-Dock: radialer Abstand der Klammerbalken von der Ringmitte (px) -> Bahnrand ± 3 px
    playerDockBar = 5,                -- Player-Dock: halbe tangentiale Länge eines Klammerbalkens (px) -> 10 px lang
    playerDockFoot = 2,               -- Player-Dock: Länge der Einhak-Füße (px, radial zur Bahn)
    -- Bridge-Silhouetten (Auftrag: Ghost-Formen auf der Brücke): im Ready-/
    -- Dock-Zustand zeigen dünne Geistumrisse auf der Brückenachse, wohin
    -- Player (gestrichelter Kreis) und Baby (dünnes Quadrat) beim Transit
    -- laufen. Nur kontextuell (aktive Brücke + Nähe), nie alle Brücken. Auf
    -- der weißen Brücke gelten die Geister als SCHWARZE Umrisse (Papier-Form,
    -- wie die Figuren auf der Brücke), dünn und gestrichelt -> subtil.
    playerGhostRadius = 5,            -- Player-Geist: Radius des Kreisumrisses (px, etwas kleiner als der Körper)
    playerGhostDash = 4,              -- Player-Geist: Segmentlänge der gestrichelten Linie (px, Bogenlänge)
    playerGhostGap = 2,               -- Player-Geist: Lücke zwischen den Segmenten (px, Bogenlänge)
    babyGhostHalf = 4,                -- Baby-Geist: halbe Quadratkante (px, etwas kleiner als die Figur)
    ghostRadialOffset = 0.15,         -- Geist-Versatz aus der Brückenmitte (Anteil der Brückenlänge): Baby führt zum Zielring, Player folgt dahinter

    -- Gemeinsamer Brückentransit (Player + Baby, EIN A): räumlich strikt in
    -- Phasen getrennt (SHARED BRIDGE PATH FIX — kein Hintergrund-Cutting):
    --   PHASE A [0, hold]            tangentiales Alignment auf dem RING
    --                                (Baby -> Bridge-Achse, Player -> Formation
    --                                hinter dem Baby); Radius bleibt Ringradius.
    --   PHASE A2 [hold, hold+babyLead] Baby beginnt RADIAL (Achse, Radius
    --                                wandert); Player gleitet tangential auf
    --                                die Achse, Radius bleibt noch Ringradius.
    --   PHASE B [hold+babyLead, total] Player kreuzt RADIAL: Winkel = Achse
    --                                (konstant), nur Radius wandert.
    --   PHASE C  Baby nach hold+babyDuration auf dem Zielring tangential zum
    --                                Exit gleiten; Player landet auf der Achse.
    -- Niemals ändern sich Winkel UND Radius gleichzeitig während der Crossing-
    -- Phase. Beide Figuren liegen dann auf der sichtbaren Bridge-Achse.
    sharedBridgeHold = 0.08,       -- Phase A: Alignment auf dem Ring (s)
    sharedBabyLead = 0.08,         -- Baby startet radial, Player gleitet auf die Achse (s)
    sharedBabyDuration = 0.20,     -- Baby-Bewegungsdauer (s, kleiner/schneller)
    sharedPlayerDuration = 0.34,   -- Player-Bewegungsdauer (s, folgt direkt) -> total ~0,50 s

    -- Audio (Phase 9.1): benannte Tuningwerte, alle Klänge rein synth.
    -- Konzept-zwingend: Klick alle 15° bei exakt 0.15; Brücke exakt 0.25 s;
    -- Kernpuls Raum 1 = 55 Hz alle 4.0 s. Der Rest sind Audio-Tuningwerte.
    audioMovementClickStep = 15,      -- Grad tatsächlicher Ringstrecke pro Klick
    audioMovementClickVolume = 0.15,  -- exakt 0.15 (verbindlich)
    audioMovementClickFreq = 40,      -- Noise-Pitch (Hz, mechanisches Tick)
    audioMovementClickLen = 0.03,     -- Impulsdauer (s), sehr kurz
    audioSwitchNote1 = 72,            -- Rechteck Ton 1 (MIDI)
    audioSwitchNote2 = 71,            -- Rechteck Ton 2, exakt 1 Halbton tiefer
    audioSwitchLen = 0.05,            -- Notenlänge (s)
    audioSwitchGap = 0.06,            -- Abstand zwischen den zwei Tönen (s)
    audioSwitchVolume = 0.5,
    -- Pass 2: A/B minimal unterschiedlich (B exakt 1 Halbton tiefer), damit man
    -- die Umschaltrichtung hört (CW -> A, CCW -> B). Kein zweiter Klang.
    audioSwitchBNote1 = 71,
    audioSwitchBNote2 = 70,
    audioBridgeStartFreq = 160,       -- Sägezahn Glide-Start (Hz, mittleres Band für kleinen Lautsprecher)
    audioBridgeEndFreq = 320,         -- Glide-Ende (Hz, ca. eine Oktave aufwärts)
    audioBridgeDuration = 0.25,       -- exakt 0.25 s (verbindlich)
    audioBridgeVolume = 0.85,         -- Ausfahren deutlich hörbar (klar unter dem Crossing-Zip)
    -- Pass 2: sehr kleines End-Klick, sobald die Brücke voll ausgefahren und
    -- nachgesetzt ist (synchron zur visuellen Settle-Phase; ein Sound mit Bewegung).
    audioBridgeSettleFreq = 90,
    audioBridgeSettleVolume = 0.2,
    audioBridgeSettleLen = 0.03,
    audioImpactFreq = 90,             -- tiefer Sinus (Hz)
    audioImpactDuration = 0.12,       -- kurzer Stoß (s)
    audioImpactVolume = 0.6,
    -- Pass 2: Blenden-Körperton beim tatsächlichen Öffnen/Schließen (eigene
    -- Töne; Schließen tiefer/härter, Öffnen etwas höher und leiser).
    audioShutterOpenFreq = 100,
    audioShutterOpenDuration = 0.06,
    audioShutterOpenVolume = 0.3,
    audioShutterCloseFreq = 60,
    audioShutterCloseDuration = 0.10,
    audioShutterCloseVolume = 0.45,
    audioGateFreq = 80,               -- langer tiefer Puls (Hz)
    audioGateDuration = 1.0,          -- Pulsdauer (s)
    audioGateVolume = 0.5,
    -- Brückenwechsel (eigener Sound beim tatsächlichen Transferstart über eine
    -- normale Brücke; NICHT Schalterklick, NICHT Raumübergang): kurzer
    -- mechanischer Zip+Shff->Tick (Bewegung zwischen den Ringen + Landepunkt).
    -- Pass: deutlich präsenter — Volume 1.0, höheres mittleres Frequenzband
    -- (400->180 Hz Abwärts-Sweep, auf dem kleinen Lautsprecher klar hörbar,
    -- nicht zu schrill), Sustain im Envelope angehoben (Körper statt nur Attack).
    audioBridgeCrossFreq = 400,       -- Zip-Glide Startfrequenz (Hz, mittleres Band)
    audioBridgeCrossEndFreq = 180,    -- Zip-Glide Endfrequenz (Hz, Abwärts-Sweep)
    audioBridgeCrossDuration = 0.18,  -- kurz, aber klar hörbar (s)
    audioBridgeCrossVolume = 1.0,
    -- Zip + kleiner mechanischer Abschluss beim Landen (zip/shff -> tick). Der
    -- Tick wird auf demselben Synth zeitversetzt (when = Start + Dauer)
    -- getriggert — genau einmal pro Transit, kein Spam.
    audioBridgeCrossTickFreq = 260,   -- Tick-Frequenz (Hz, mechanisch, präsent)
    audioBridgeCrossTickVolume = 1.0,
    audioBridgeCrossTickLen = 0.04,   -- sehr kurz (s)
    -- Raumübergang (eigener Sound beim bestätigten GEMEINSAMEN Raumabschluss;
    -- klar größer als Brückenwechsel, ruhig-atmosphärisch, kein Sieg-Jingle).
    -- Pass: deutlich hörbarer, tragender (1.1 s), mehr Sustain, Frequenzband
    -- leicht angehoben für den kleinen Lautsprecher — Charakter (tief ziehender
    -- Triangle-Sweep) bleibt erhalten.
    audioRoomTransFreq = 300,         -- Sweep-Startfrequenz (Hz)
    audioRoomTransEndFreq = 140,      -- Sweep-Endfrequenz (Hz, tief ziehend, hörbar)
    audioRoomTransDuration = 1.1,     -- Dauer (s), tragender
    audioRoomTransVolume = 1.0,       -- größter Sound der Gruppe (charaktererhaltend lauter)
    -- Baby-Sounds (sehr subtil, synthetisch, mechanisch-minimalistisch):
    -- Baby-Push (weicher hoher Kurzimpuls, nur bei neuem Pushkontakt).
    audioBabyPushFreq = 720,          -- weich, hoch (Hz)
    audioBabyPushVolume = 0.32,
    audioBabyPushLen = 0.05,          -- sehr kurz (s)
    -- Baby-Impact (dumpferer, kürzerer „tik/tup“ beim Drücken gegen ein Hindernis).
    audioBabyImpactFreq = 200,        -- dumpfer (Hz)
    audioBabyImpactVolume = 0.35,
    audioBabyImpactLen = 0.04,        -- sehr kurz (s)
    -- Baby-Bridge-Layer (winziger heller Akzent beim gemeinsamen Brückenwechsel;
    -- der Bridge-Sound bleibt das Hauptereignis).
    audioBabyBridgeFreq = 920,        -- heller, hoch (Hz)
    audioBabyBridgeVolume = 0.28,
    audioBabyBridgeLen = 0.06,        -- kurz (s)
    audioCoreRoom1Freq = 55,          -- Raum 1 exakt 55 Hz (verbindlich)
    audioCoreInterval = 4.0,          -- alle 4.0 s (verbindlich)
    audioCoreDuration = 0.6,          -- Pulsdauer (s)
    audioCoreVolume = 0.25,           -- sehr leise, konservativ
    audioCoreSemitoneStep = 4,        -- große Terz = +4 Halbtöne pro Raum

    -- NEUE SOUNDS (AUFTRAG „geschlossenes minimalistischeres Sounddesign"):
    -- bestehende Grundklänge bleiben; diese Werte ergänzen Feedback für Menü,
    -- Platte, Einmalschalter, Bridge-Retract/-Collapse, Tutorial, Restart,
    -- Raum-7-Spezialübergang und das finale Ende. Alle edge-getriggert.

    -- Menü (Startscreen): sehr dezentes Feedback.
    audioMenuMoveFreq = 240,            -- MENU MOVE: kleiner trockener Square-Tick (Hz)
    audioMenuMoveLen = 0.03,            -- sehr kurz (s)
    audioMenuMoveVolume = 0.22,
    audioMenuConfirmStart = 180,        -- MENU CONFIRM: Triangle-Sweep aufwärts (Hz)
    audioMenuConfirmEnd = 260,
    audioMenuConfirmDuration = 0.12,    -- kurz (s)
    audioMenuConfirmVolume = 0.35,
    audioMenuRiseStart = 90,            -- STARTANIMATION Rise (Ring zeichnet sich): Triangle (Hz)
    audioMenuRiseEnd = 150,
    audioMenuRiseVolume = 0.15,         -- sehr leise (Vol. max. 0.15)
    audioMenuFillFreq = 90,             -- FILL-Abschlussimpuls (Scheibe entsteht): tiefer Sine (Hz)
    audioMenuFillDuration = 0.25,
    audioMenuFillVolume = 0.3,

    -- Druckplatte: eigenes eindeutiges Feedback (leichtes Einrasten).
    audioPlateOnStart = 170,            -- PLATE ON: Triangle steigt (Hz)
    audioPlateOnEnd = 230,
    audioPlateLen = 0.10,               -- kurz, aber deutlich (s)
    audioPlateOnVolume = 0.60,          -- DEUTLICH hörbar (Ziel: sofort wahrnehmen)
    audioPlateTickFreq = 330,           -- kleiner Square-Tick am ON-Anfang (Druckpunkt, Hz)
    audioPlateTickLen = 0.03,
    audioPlateTickVolume = 0.30,
    audioPlateOffStart = 220,           -- PLATE OFF: Triangle fällt (Hz)
    audioPlateOffEnd = 150,
    audioPlateOffVolume = 0.50,

    -- Einmalschalter: unterscheidet sich vom Doppelschalter („verriegelt").
    audioOneShotNote1 = 74,             -- Square-Snap MIDI 74 -> 67 (zweistufig)
    audioOneShotNote2 = 67,
    audioOneShotLen = 0.06,
    audioOneShotGap = 0.06,
    audioOneShotVolume = 0.5,
    audioOneShotTickFreq = 60,          -- optionaler tiefer Sine-Tick (Hz)
    audioOneShotTickLen = 0.06,
    audioOneShotTickVolume = 0.25,

    -- Bridge RETRACT (deaktivieren/verschwinden): Sägezahn ABWÄRTS — hoch =
    -- Bridge entsteht, runter = Bridge verschwindet.
    audioBridgeRetractStart = 320,
    audioBridgeRetractEnd = 160,
    audioBridgeRetractDuration = 0.22,
    audioBridgeRetractVolume = 0.65,

    -- ONE-USE BRIDGE COLLAPSE (nach abgeschlossenem Transit): Sägezahn abwärts.
    audioCollapseStart = 260,
    audioCollapseEnd = 90,
    audioCollapseDuration = 0.18,
    audioCollapseVolume = 0.55,

    -- Tutorial-Infoleiste: ruhig, extrem kleine Ticks.
    audioTutorialTickFreq = 300,        -- Leiste erscheint: winziger Triangle-Tick (Hz)
    audioTutorialTickLen = 0.025,
    audioTutorialTickVolume = 0.14,
    audioTutorialContinueFreq = 200,    -- A = continue: kleiner neutraler Square-Tick (Hz)
    audioTutorialContinueLen = 0.03,
    audioTutorialContinueVolume = 0.2,

    -- Restart (B): passend zur Collapse/Rebuild-Animation.
    audioRestartCollapseStart = 150,    -- Phase 1 Collapse: Sine-Sweep abwärts (Hz)
    audioRestartCollapseEnd = 55,
    audioRestartCollapseDuration = 0.32, -- = restartCollapseDuration (synchron)
    audioRestartCollapseVolume = 0.55,
    audioRestartCoreFreq = 55,          -- Phase 2 am Core: sehr kurzer tiefer Impuls (Hz)
    audioRestartCoreDuration = 0.12,
    audioRestartCoreVolume = 0.4,
    audioRestartRebuildStart = 90,      -- Phase 3 Rebuild: Sägezahn aufwärts (Hz)
    audioRestartRebuildEnd = 220,
    audioRestartRebuildDuration = 0.34, -- = restartExpandDuration (synchron)
    audioRestartRebuildVolume = 0.45,

    -- LEVEL-7-SPEZIALÜBERGANG (Audio, „Urknall“): während der langsamen
    -- Expansion ein ansteigendes, raumhaftes Sog-Gefühl (der Haupt-Woosh
    -- läuft in main.lua via playTransitionWoosh; hier die dezente Sog-
    -- Unterlage über die gesamte Expansionsdauer). Beim schnellen Zusammen-
    -- ziehen ein kurzer, starker Rückzugs-/Collapse-Sound (absteigender
    -- Sweep + tiefer Impact). Die ROOM-Anzeige bleibt still.
    audioP7ExpandStart = 0.5,        -- Expansion: Sog-Unterlage startet halb so tief wie der Kern
    audioP7ExpandEnd = 1.15,         -- ... und steigt leicht über die Kernfrequenz
    audioP7ExpandDuration = 2.0,     -- Sog-Unterlage begleitet die komplette Expansion (= phase7Expand)
    audioP7ExpandVolume = 0.18,      -- dezent (der Woosh trägt den Hauptanteil)
    audioP7ContractStart = 1.3,      -- Kontraktion: Sweep startet über der Kernfrequenz
    audioP7ContractEnd = 30,         -- ... und fällt extrem tief ab (kosmischer Kollaps)
    audioP7ContractDuration = 0.28,  -- kurzer, prägnanter Rückzug (0.25-0.30 s)
    audioP7ContractVolume = 0.5,
    audioP7ContractImpactFreq = 40,  -- tiefer Impact beim Kollaps (Hz)
    audioP7ContractImpactDuration = 0.15,
    audioP7ContractImpactVolume = 0.6,

    -- FINALES ENDE (letzter Raum): kein Victory-Fanfare — System kommt zur Ruhe.
    audioFinalTransDuration = 1.8,      -- etwas längerer finaler Room-Transition-Sweep (s)
    audioFinalSettleDuration = 1.8,     -- Sine gleitet von Room-Core-Frequenz langsam auf 55 Hz (s)
    audioFinalSettleVolume = 0.4,

    -- LEVELÜBERGANG-WOOSH (normaler Center-Wipe): der große WEISSE Kreis wächst
    -- über den Bildschirm — deutlich spürbarer Luft-/Energie-Woosh (breit und
    -- weich, KEINE Explosion). Saw-Sweep 120 -> 420 Hz über die volle Dauer +
    -- sehr kurzer Noise-Einsatz (Luft). Läuft exakt mit dem Wachsen des Kreises
    -- (roomWipeGrow 0.35 s) und klingt auf dem vollständig weißen Bildschirm aus
    -- (Release). Genau EIN Woosh pro Übergang; KEIN zweiter Woosh beim Cut.
    audioWooshStart = 80,               -- SOG-Sweep Start (Hz, tief — der Core zieht ein)
    audioWooshEnd = 210,                -- SOG-Sweep Ende (Hz, kurzer Anstieg, nicht schrill)
    audioWooshDuration = 0.70,          -- Sweep-Dauer (s; 0.6-0.9)
    audioWooshVolume = 0.70,            -- deutlich, aber weich
    audioWooshNoiseFreq = 400,          -- Noise-Textur (Hz; bei Noise ohne Tonhöhe)
    audioWooshNoiseLen = 0.12,          -- Noise sehr kurz eingeblendet (s)
    audioWooshNoiseVolume = 0.12,       -- sehr wenig Textur (nur für die Haptik)
    audioWooshImpulseFreq = 70,         -- tiefer Abschlussimpuls (Sine, Hz)
    audioWooshImpulseDelay = 0.52,      -- kurz vor dem Ausklingen (s)
    audioWooshImpulseDuration = 0.28,   -- langer tiefer Ausklang (s)
    audioWooshImpulseVolume = 0.50,     -- deutlich, nicht schrill

    -- Menü (Titelbildschirm): ruhig, klar, 1-Bit — großer dicker Ring mittig
    -- (Zentrum = Spielwelt-Zentrum, fest verankert auf 200,120), der sich beim
    -- Erscheinen selbst schreibt (0.5-1.0 s) und danach ruhig steht (keine
    -- Atmung). Das Menü steht DIREKT IM Kreis (kein Titel über dem Kreis).
    -- A bestätigt und startet die Starttransition (0.6-0.8 s): Menütext und
    -- Auswahl verschwinden, nur der dicke Ring bleibt und wächst stark nach
    -- außen — Mittelpunkt exakt (200,120), KEIN Gameplay innerhalb des Rings,
    -- bis die Ringkante komplett aus dem Bild gewachsen ist (Endradius >= ~250).
    menuFontHeight = 8,             -- (Kurbel-Overlay-Zeilenabstand; NICHT die echte Font-Höhe!)
    menuTitleText = "UNDERTOW",     -- Spieltitel (nicht mehr auf dem Startscreen angezeigt; bleibt für Kompatibilität)
    menuTextLineHeight = 20,        -- echte Zeilenbox-Höhe des Systemfonts (font:getHeight(), gemessen)
    menuTitleCenterX = 200,         -- Titelkreis-Zentrum = Spielwelt-Zentrum (fixer Anker, nie wandern)
    menuTitleCenterY = 120,
    menuTitleOuterRadius = 90,      -- Außenradius des dicken Titelrings (~90 px => Außendurchmesser ~180 px)
    menuTitleLineWidth = 15,        -- Ringstärke (~15 px, dicker Playdate-Ring, bewusst pixelige Kante)
    menuDrawDuration = 1.35,        -- Ring-Zeichenanimation (1.3-1.4 s): Bogen schreibt sich von 12 Uhr aus
    menuTextScale = 1.0,            -- Skalierung des Systemfonts (1.0 = volle 20px-Schrift, gut lesbar)
    -- Startmenü-Optionen: direkt IM Kreis, horizontal mittig, kompakte
    -- Zeilenabstände (~20 px). MIT Save (CONTINUE / NEW GAME / EXIT):
    menuContinueY = 92,             -- y (obere Textkante) des CONTINUE-Eintrags
    menuContinueDelay = 1.38,       -- erscheint nach dem Ring (gestaffelt)
    menuNewGameY = 113,             -- y des NEW GAME-Eintrags
    menuNewGameDelay = 1.42,
    menuExitY = 134,                -- y des EXIT-Eintrags
    menuExitDelay = 1.46,
    -- OHNE Save (NEW GAME/EXIT): kompakt zentriert im selben Band.
    menuNoSaveNewGameY = 106,
    menuNoSaveNewGameDelay = 1.38,
    menuNoSaveExitY = 128,
    menuNoSaveExitDelay = 1.42,
    -- Auswahl: kleines weißes, nach rechts zeigendes Dreieck links vom
    -- gewählten Eintrag (keine Box, kein Punkt, keine Unterstreichung).
    menuSelectionTriangleSize = 6,  -- Dreieck: Länge von der Spitze zur Basis (px)
    menuSelectionTriangleHalf = 4,  -- Dreieck: halbe Höhe (px)
    menuSelectionTriangleGap = 6,   -- Abstand Dreiecksspitze -> Textanfang (px)
    -- Starttransition nach A (Bestätigung von CONTINUE/NEW GAME):
    --   Fill   (0.5-0.55 s): Menütext/Auswahl verschwinden SOFORT, der Ring
    --          bleibt exakt bei (200,120) und füllt sich nach innen (Außen-
    --          kante bleibt ~90 px, Innenloch schließt sich) -> volle Scheibe.
    --   Reveal (0.7-0.8 s): die gefüllte Menü-Scheibe IST der Level-Core
    --          (kein Schnitt); das komplette Level zoomt aus dem Mittelpunkt
    --          heraus auf Normalgröße (gemeinsamer Zoom-Mittelpunkt 200,120,
    --          keine Kameraverschiebung, kein Fade/Flash/Ripple).
    --   Settle (0.15-0.25 s): kurze Ruhe auf der fertigen Levelansicht,
    --          erst DANACH startet das Tutorial-Overlay (auch Level 2+ nach
    --          dem Raumübergang).
    menuFillDuration = 0.52,        -- Ring füllt sich nach innen (0.5-0.55 s)
    menuRevealDuration = 0.75,      -- Level zoomt aus dem Core heraus (0.7-0.8 s)
    menuRevealSettle = 0.2,         -- kurze Ruhe vor dem Tutorial-Overlay (0.15-0.25 s)

    -- Eingaben: B startet das AKTUELLE Level einfach neu (Press-Edge, genau
    -- ein Restart pro B-Drücken; kein Rückgängig, kein Zurückspulen) +
    -- Crank-eingeklappt-Hinweis. Der Restart läuft als kurze geometrische
    -- Kollaps-/Wiederaufbau-Animation (Kamera-Skalierung), kein Hardcut.
    crankOverlayX = 288,            -- Crank-Hinweis-Box (obere rechte Ecke, kompakt)
    crankOverlayY = 8,
    crankOverlayPadding = 5,        -- Crank-Hinweis: Innenabstand Text -> Rahmen (px; Boxgröße wird aus den echten Font-Metriken berechnet)
    crankHintDuration = 6.0,       -- Crank-Hinweis nur die ersten X s pro Raum (Onboarding)
    -- Restart-Animation (B): Ringe kollabieren zum Kern (Ease-In), kurzer
    -- Stillstand am Kern (Level wird dabei neu geladen), dann Wiederaufbau aus
    -- dem Kern (Ease-Out). Gesamtdauer ~0.6-0.9 s.
    restartCollapseDuration = 0.32, -- Kollaps der Ringe zum Mittelpunkt (s)
    restartHoldDuration = 0.12,     -- kurzer Stillstand am Kern (s)
    restartExpandDuration = 0.34,   -- Wiederaufbau aus dem Kern (s)

    -- Schalter-Look (Referenz): breites flaches Rechteck mit deutlich
    -- abgerundeten Ecken (width:height ≈ 2.8:1, Höhe ≈ Bahnbreite 8) und zwei
    -- gleich großen Innenkreisen nahe den Längsenden (vertikal zentriert,
    -- symmetrisch). Grundform EXAKT nach Referenz: WEISSER Rounded-Block +
    -- zwei SCHWARZE Kreise. Auf der weißen Bahn hält eine schwarze 1-px-Kontur
    -- den Block lesbar (das weiße Füllen verschmilzt mit der Bahn; die Kontur
    -- definiert die Blockform — wie bei der Druckplatte). Keine Pfeile, keine
    -- Nase/Kerbe, keine Statussymbole, kein Text. Gameplay-Semantik A/B
    -- (CW=A, CCW=B) bleibt unverändert — nur die Darstellung.
    switchWidth = 23,              -- Länge entlang der Bahn (px) ~2.8:1
    switchHeight = 8,              -- Höhe (px), ungefähr Bahnbreite
    switchCornerRadius = 3,        -- Eckenrundung (px; deutlich, aber noch Rechteck)
    switchCircleRadius = 2.6,      -- Innenkreis-Radius (px, ~65 % der Höhe)
    switchCircleOffset = 5,        -- Innenkreis-Mitte Abstand vom Zentrum (px, symmetrisch)
    switchPressFrames = 2,         -- Press-Animation: Frames eingedrückt (nur echtes Umschalten)
    switchPressOffset = 1.5,       -- Press-Offset radial zur Ringmitte (px)
    switchPressProximity = 12,     -- Winkelbereich (°) für die Zuordnung „Spieler am Schalter"

    -- Atmosphere (rein visuell, kein Gameplay): Mikroreaktionen + Lebendigkeit.
    shutterOvershootFrames = 2,    -- Blende schließen: 1 px über Endposition, 2 Frames zurück
    shutterOvershootPx = 1,        -- Überschwinger der Blende (px, rein visuell)
    corePulseAmplitude2 = 0.1,    -- zweite, langsamere Atemwelle (px)
    corePulsePeriod2 = 7.0,        -- zweite Wellenperiode (s)
    -- Ring-Legende (Design-Legende): drei klar unterscheidbare Ringzustände.
    -- AKTIV  = die beiden begehbaren Bahnen (outer/inner, trackWidth 8, solide
    --          und präsenteste Bahnen im Bild).
    -- FUTURE = der nächste innere Ring (inner-1), der beim nächsten Raumwechsel
    --          zum neuen aktiven Innenring wird: pulsierende, gestrichelte Linie
    --          im Kernbereich (nach dem Kern gezeichnet, damit sie auch bei
    --          wachsendem Kern lesbar bleibt — der nächste Ring „entsteht“ im
    --          Kern; „bald relevant“, kein Deko-Effekt).
    -- HISTORY = Geisterringe der abgeschlossenen Räume außerhalb (1 px,
    --          durchgehend, statisch, ruhig — nur noch feine Spur im Hintergrund;
    --          keine Dash-Segmente, keine Indexmarke, kein Drift, kein Puls).
    futureRingLineWidth = 3,        -- FUTURE: Linienbreite (px; >2 vermeidet 1-px-Rasterlücken; klar dünner als die 8-px-Bahn)
    futureRingPulseAmplitude = 1.5, -- FUTURE: Radius-Pulsation (px, atmet subtil)
    futureRingPulsePeriod = 2.0,    -- FUTURE: Pulsperiode (s)
    futureRingMinRadius = 6,        -- FUTURE: erst ab diesem Radius zeichnen (px; Transition-Einblendung)
    -- Pass 2: Mikro-Partikel entfernt (1-px-Funken wirkten arcade-artig und
    -- redundant neben Press-Animation + Snap-Sound). Kurze visuelle Ruhe vor
    -- der Raumtransition + kurzer Stillstand am finalen Gate.
    completionPulseDuration = 0.20,-- Systemimpuls nach Raum-Lösung (s)
    finalHoldFrames = 10,          -- Raum 6: Welt hält 0.2 s still (Ghost-Drift stoppt) vor dem Outro

    -- Room-Transition (radialer Raumwechsel; ui/roomtransition.lua + Render):
    -- Der gesamte Ringaufbau schiebt sich visuell EINE STUFE NACH AUSSEN um den
    -- festen Mittelpunkt (200,120) — keine Kamerafahrt, kein Fade, kein Flash.
    -- Future-Ring -> neuer aktiver Innenring, bisheriger Innenring -> Außenring,
    -- bisheriger Außenring -> History. Alte Puzzleobjekte lösen sich gestaffelt
    -- auf (erste Hälfte), neue erscheinen erst, wenn der neue Ring fast
    -- eingerastet ist (gestaffelt: Brücken -> Schalter/Blenden/Platten ->
    -- Baby-Dock -> Player/Baby). Gesamtdauer ~0.97 s (Settle 0.12 + Bewegung
    -- 0.85). Alle Anteile beziehen sich auf den Bewegungsfortschritt (0..1).
    roomTransitionSettle = 0.12,      -- kurzer visueller Halt nach Raumabschluss (s; Target Settle)
    roomTransitionDuration = 0.85,    -- Hauptbewegung der Ringradien (s, Ease-In-Out)
    roomTransDissolveStart = 0.30,    -- alte Puzzleobjekte beginnen aufzulösen (Anteil)
    roomTransDissolveEnd = 0.55,      -- alte Puzzleobjekte aufgelöst (nur Ringe/History bleiben)
    roomTransRevealPoint = 0.62,      -- neuer Raum wird geladen; neue Staffelung beginnt
    roomTransBridgeStart = 0.66,      -- neue Brücken/Docks/inaktive Punkte erscheinen
    roomTransBridgeEnd = 0.78,
    roomTransObjectStart = 0.70,      -- neue Schalter/Blenden/Platten/Marken erscheinen
    roomTransObjectEnd = 0.84,
    roomTransBabyDockStart = 0.74,    -- neues Baby-Dock erscheint
    roomTransBabyDockEnd = 0.88,
    roomTransFigureStart = 0.78,      -- neuer Player/Baby erscheinen (Landing-Settle)
    roomTransFigureEnd = 0.94,
    roomTransImpulseWindow = 0.10,    -- Future-Impuls: Dauer des einmaligen Impulses (Anteil Bewegung)
    roomTransImpulsePx = 2.0,         -- Future-Impuls: max. Radius-Zuwachs (px)
    roomTransNewFutureStart = 0.85,   -- Neuer Future-Ring erscheint erst, wenn der alte Future fast eingerastet ist (Anteil; verhindert zwei eng nebeneinanderliegende Kreise um das Zentrum)
    roomTransFigureBulge = 0.06,      -- alte Figur: subtile Größenänderung während der Bewegung (Anteil)
    roomTransFigureScaleMin = 0.85,   -- neue Figur: Startgröße beim Landen (Anteil)
    -- Center-Wipe (Raumwechsel, ui/wipe.lua, AUFTRAG „direkter Cut“): der
    -- gefüllte WEISSE Mittelpunkt wächst kontinuierlich aus (fester
    -- Mittelpunkt 200,120, Ease-In, NUR EIN gefüllter Kreis), bis er den
    -- KOMPLETTEN 400x240-Bildschirm bedeckt; erst dann wird der neue Raum
    -- verdeckt geladen. Auf dem weißen Bildschirm erscheint mittig kurz
    -- „ROOM X" (roomWipeRoomHold), danach DIREKTER CUT auf den fertigen neuen
    -- Raum — der weiße Kreis wird NICHT wieder kleiner. Kein Reveal, keine
    -- Figuren-Exit-Animation; Player/Baby stehen sofort korrekt.
    roomWipeGrow = 0.35,              -- Wipe: Kreis wächst über den Bildschirm (0.30-0.40 s)
    roomWipeRoomHold = 2.0,           -- Wipe: „ROOM X / 10“ auf dem weißen Bildschirm (exakt ~2.0 s)
    roomDisplayTotal = 10,            -- ROOM-Anzeige: Gesamtzahl („ROOM 1 / 10“ … „ROOM 10 / 10“)
    roomWipeCoverRadius = 250,        -- Wipe-Zielradius: bedeckt den Screen komplett (Eckabstand ~233)
    -- Tutorial-Timing nach einem Raumwechsel: die Transition ist KOMPLETT
    -- fertig und Player/Baby sind sauber gelandet, dann bleibt das neue Level
    -- ca. 0.2-0.3 s vollständig sichtbar, ERST DANACH startet das
    -- Tutorial-Overlay (Mechanik-Fokus). Das Tutorial lädt nie Position oder
    -- Levelstate neu.
    roomTransTutorialSettle = 0.25,

    -- Tutorial-Trigger (AUFTRAG „früh, ohne Bewegungskorrektur"): ein neues
    -- Element wird NICHT beim Levelstart erklärt, sondern erst, wenn der
    -- Player in dessen Einführungszone kommt — ca. 12-20° VOR dem Element
    -- (es ist bereits klar sichtbar, noch vor Kontakt/Aktivierung). KEINE
    -- Brems-, Snap- oder Kamera-Eingriffe: die Steuerung fühlt sich völlig
    -- normal an; das Gameplay pausiert nur kurz, bis A gedrückt wird.
    tutorialProximityRange = 15,

    -- Tutorial-Highlight (AUFTRAG „komplettes Spielfeld sichtbar"): KEIN
    -- schwarzer Vollbild-Overlay, KEINE harte Abdunkelung, kein Ausschnitt,
    -- kein Fokusfenster. Das restliche Spielfeld wird nur DEZENT abgeschwächt
    -- (siehe tutorialDimStep unten), das neue Element bleibt voll kontrast-
    -- reich und wird von einem engen, dezent pulsierenden Fokusrahmen markiert.
    -- Player/Baby bleiben normal sichtbar. Text steht in der unteren Infoleiste.

    -- Tutorial-Untere Infoleiste (AUFTRAG „schwarzer Bereich nur unten"):
    -- SOLID schwarzer Bereich unten mit feiner WEISSER Trennlinie fast über
    -- die volle Breite; darin weisse, FEINE Schrift (Asheville-Sans-14-Bold,
    -- natürliche 14 px — kein Downscale, keine abgeschnittene/grobe Typo).
    -- Text links, „A = continue" rechts (eigene Spalte, nie gequetscht).
    -- Genau dasselbe Leistenformat gilt für alle Hinweise (auch
    -- „Turn the crank to move.").
    tutorialBarHeight = 46,          -- Höhe der unteren Infoleiste (px; 2 Zeilen der 14-px-Font passen sicher)
    tutorialBarMargin = 14,          -- Randabstand Text/A (px, sauberer Innenabstand)
    tutorialLineX0 = 8,              -- Trennlinie: Start-x (fast volle Breite)
    tutorialLineX1 = 392,            -- Trennlinie: End-x

    -- Tutorial-Element-Hervorhebung (AUFTRAG „neues Element deutlich
    -- hervorheben"): das restliche Spielfeld wird NUR dezent abgeschwächt
    -- (1 schwarze Zeile alle tutorialDimStep Zeilen — Spielfeld bleibt klar
    -- lesbar, kein schwarzer Overlay); das neue Element + Player/Baby bleiben
    -- voll kontrastreich. Ein enger, symmetrischer Fokusrahmen (vier Eck-
    -- marker, Länge tutorialMarkerLen) sitzt nah am Element und pulsiert
    -- dezent (1 px, tutorialMarkerPulseSpeed).
    tutorialDimStep = 5,             -- Abschwächung: 1 schwarze Zeile alle N Zeilen (dezent)
    tutorialMarkerPad = 2,           -- Fokusrahmen: Abstand zum Element (px)
    tutorialMarkerLen = 10,          -- Fokusrahmen: Eckmarker-Länge (px)
    tutorialMarkerPulseSpeed = 2.5,  -- Puls-Geschwindigkeit (rad/s, dezent, kein Blinken)

    -- Level-7-Spezialübergang (neue Phase, ui/phase7.lua, „Urknall“): nach
    -- Abschluss von LEVEL 7 läuft KEIN normaler Levelwechsel (kein Center-
    -- Wipe) — die Einführung ist vorbei. Stattdessen eine rein geometrische
    -- kosmische Sequenz: Player+Baby sind bereits hinter dem Kern (Center-
    -- Bridge) -> kurze Ruhe/Verdichtung -> LANGSAME, gleichmäßige EXPANSION
    -- des hellen Kerns (wird immer heller und verdrängt die Ringelemente),
    -- bis er die komplette Spielfläche füllt -> auf dem vollen weißen Bild
    -- zentriert „ROOM X / 10“ für ~2 s (hier wird die neue Phase verdeckt
    -- geladen) -> SCHNELLE Kontraktion zurück zum winzigen Punkt (wie ein
    -- Urknall in umgekehrter Richtung) -> DIREKTER REVEAL von Level 8 (kein
    -- Nachblenden, kein Wiederaufbau; Player/Baby stehen direkt korrekt an
    -- ihren Startpositionen) -> sofort Gameplay, KEINE Tutorials.
    screenWidth = 400,               -- Bildschirmbreite (Overlay-Fläche)
    screenHeight = 240,              -- Bildschirmhöhe
    phaseTwoStartRoom = 8,           -- ab diesem Raum beginnt Phase 2 (keine Tutorial-Overlays mehr)
    phase7Rest = 0.30,               -- kurze Ruhe/Verdichtung am Kern (0.25-0.35 s)
    phase7Expand = 2.0,              -- LANGSAME Expansion des Kerns bis zum Vollbild (gleichmäßig, unaufhaltsam)
    phase7TextHold = 2.0,            -- „ROOM X / 10“ auf dem vollen weißen Bild (exakt ~2 s)
    phase7Contract = 0.30,           -- SCHNELLE Kontraktion zurück zum winzigen Punkt (deutlich schneller als die Expansion)
    phase7TinyPoint = 2,             -- Radius des winzigen weißen Punkts (px)
    phase7ExpandDitherStart = 50,    -- Start-Deckkraft des hellen Kerns (Kern-Optik) — wächst auf 100%
    phase7CoverRadius = 250,         -- Expansions-Zielradius: bedeckt den Screen komplett (Eckabstand ~233)

    audioCompletionFreq = 55,      -- tiefer Systemimpuls (Hz)
    audioCompletionDuration = 0.25,-- Impulsdauer (s)
    audioCompletionVolume = 0.5,   -- Lautstärke
    audioCompletionSemitoneStep = -1, -- pro Raum minimal tiefer (resonanter), keine große Linie

    -- Outro (Abschlussphase B): nach Raum 6. Reine Präsentation (ui/transition.lua).
    -- ARCHITECTURE (L431) nennt keine Dauern -> benannte Dauerwerte. Vollbildradius
    -- des Kerns: minimale Vollbildabdeckung = ceil(sqrt(centerX^2 + centerY^2))
    -- = ceil(sqrt(200^2 + 120^2)) = 234 (entfernteste Ecke bei ~233,2 px).
    outroRingDissolveDuration = 1.0,  -- R1 löst sich auf (s) [vorher 1.5]
    outroCoreExpandDuration  = 1.0,  -- Kern wächst auf Vollbild (s) [vorher 1.5]
    outroIrisDuration        = 0.8,  -- Iris öffnet sich (s) [vorher 1.2]
    outroHoldDuration        = 0.6,  -- Schlussphase: Iris voll offen vor dem Schnitt (s) [vorher 0.8]
    outroCoreFullRadius      = 224,  -- Vollbildabdeckung des Kerns (px) [vorher 234: pulsierender Kreis etwas kleiner]
    outroIrisOpenRadius      = 64,   -- Endradius der Iris-Apertur (px)
    outroIrisRingRadius      = 34,   -- „weiterer Ring" hinter der Iris (px)
    outroIrisBladeCount      = 8,    -- Anzahl Iris-Blattlinien
    outroIrisBladeOuter      = 150,  -- Endradius der Iris-Blattlinien (px)
}

return Config
