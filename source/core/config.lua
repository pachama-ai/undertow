Config = {
    -- Bildschirmmitte in Pixel
    centerX = 200,
    centerY = 120,

    -- Refreshrate in Hz (fester Frame-Step)
    refreshRate = 50,

    -- Radien in Pixel
    outerRadius = 104,
    innerRadius = 68,
    coreRadius = 30,

    -- Abmessungen in Pixel
    trackWidth = 8,
    -- Spieler (neue Figur): Kugel im mechanischen Lager
    playerRadius = 6,        -- weiße Kugel, 12 px Durchmesser
    playerStroke = 2,        -- schwarze Kontur
    playerHalo = 1.5,        -- weißer Halo außerhalb der Kontur
    pupilRadius = 2.5,       -- 5-px-Pupille
    pupilTravel = 2.4,       -- tangentialer Pupillen-Versatz in Facing-Richtung
    -- Finales Rendering (Phase 8.2), visuelle Tuningwerte
    coreGrowthPerRoom = 6,   -- Kernradius-Wachstum pro Raum (ARCHITECTURE coreGrowth)
    corePulseAmplitude = 0.8, -- Haupt-Atemwelle des Kerns (px, leicht reduziert)
    corePulsePeriod = 3.0,   -- Sekunden pro Hauptwelle
    bridgeWidth = 6,         -- Breite ausgefahrener Brücken-/Gate-Balken
    stubLength = 5,          -- sichtbarer Stummel eingefahrener Brücken/Gate
    -- Brücken-Look (Auftrag: Switch/Bridge Visual Polish): aktive Brücken
    -- bekommen definierte Endkappen (kurze Tangential-Anker an den Ring-
    -- anschlässen) und heben sich so klar von den Bahnen ab; inaktive Brücken
    -- zeigen an den Stummelspitzen eine kleine Bruch-Kerbe (der Spalt bleibt
    -- klar sichtbar). Ready-Impuls: sobald der Spieler an einer aktiven Brücke
    -- andockt, wird sie für wenige Frames minimal kräftiger plus mechanischer
    -- Tick im Anschlussbereich (kein permanentes Blinken).
    bridgeEndCapLen = 4,           -- Endkappen-Länge (px, tangential je Seite)
    bridgeEndCapWidth = 2,         -- Endkappen-Strichstärke (px)
    bridgeInactiveNotch = 4,       -- Bruch-Kerbe an den Stummelspitzen (px)
    bridgeReadyFrames = 3,         -- Ready-Impuls: Frames minimal kräftiger
    bridgeReadyThicken = 1,        -- Ready-Impuls: +px Balkendicke

    -- Steuerung: Ringgrad pro Kurbelgrad bzw. Grad pro Sekunde
    crankRatio = 0.5,
    dpadSpeed = 90,

    -- Bögen in Grad
    shutterArcWidth = 26,
    switchArcWidth = 14,
    -- Dockzone Brücke/Gate (Grad, inklusiv): moderat großzügig, damit man nicht
    -- pixelgenau andocken muss. Geometrisch begründet: der Spielerkörper
    -- (playerRadius 6 px) überlappt den Brückenbalken (bridgeWidth/2 = 3 px) auf
    -- dem innersten Ring (68 px) ab ~9,3° — 12° deckt das komfortabel ab.
    dockRange = 12,
    -- Andockhilfe: Bereich in Grad und exakte Frames für die sanfte Ausrichtung
    -- auf nutzbare aktive Brücken und Schalter (kein Gate). Unabhängig von dockRange.
    -- Bewusst KLEINER als dockRange: Assist nur unmittelbar am Dock, kein
    -- magnetisches Festkleben aus der Ferne.
    dockAssistRange = 10,
    dockAssistFrames = 3,

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
    -- blinkMinInterval/blinkMaxInterval und shutterSquintFrames sind aus dem
    -- Konzept zwingend (3-6 s, exakt 6 Frames); der Rest sind Tuningwerte.
    blinkMinInterval = 3.0,    -- Blink frühestens nach 3 s Stillstand
    blinkMaxInterval = 6.0,    -- Blink spätestens nach 6 s Stillstand
    blinkFrames = 4,           -- Blinkdauer in Frames (kurz, 50 fps)
    switchEyeWidenFrames = 6,  -- Augenweiten-Dauer in Frames
    shutterSquintFrames = 6,   -- Zusammenkneifen: exakt 6 Frames (verbindlich)
    bridgeStretchAmount = 2,   -- maximale radiale Streckung (px je Seite)

    -- Baby (generisch, Begleiter): kleines Wesen derselben Art wie der Spieler.
    -- Der Spieler bleibt visuell wichtiger (kleiner, schwächerer Halo). Kein
    -- Ablageziel: das Baby reist mit dem Spieler (gemeinsamer Raumausgang).
    babyRadius = 3.7,              -- Körperradius (px) ~62 % des Player-Durchmessers (lesbar, kleiner als Player)
    babyStroke = 1,                -- schwarze Kontur (px)
    babyHalo = 1,                  -- weißer Halo (px), schwächer als der Player-Halo
    babyPupilRadius = 1.3,         -- Pupille (px), lesbar in 1-Bit
    babyDockRange = 16,            -- Baby gilt als "am Bridge-/Gate-Dock" (Grad Abstand zu angle; gemeinsamer Transfer/Exit handlicher)
    babyCompanionOffsetDeg = 10,   -- Begleiter-Start in Folge-Räumen: Baby steht direkt hinter dem Player
    babyBridgeExitOffset = 10,     -- Austrittsposition nach Baby-Brückentransit (Grad, in Schieberichtung)
    babyBridgeAnimDuration = 0.25, -- Dauer des Baby-Brückentransits (s)
    -- Gemeinsame Dockformation (Ready/Transitstart): Player steht mit einem aus
    -- den Figurenradien abgeleiteten Abstand hinter dem Baby (innerster Ring als
    -- Worst Case für Grad->Pixel). 2 px Mindestabstand der Körper.
    sharedFormationGapDeg = (6 + 3.7 + 2) / 68 * (180 / math.pi),

    -- Baby-Polish (Lebendigkeit, rein visuell): eigene Blink-/Idle-/Reaktions-
    -- Logik im Renderer (UI-State, nie Gameplay/Snapshot/Save).
    babyBlinkMinInterval = 3.0,    -- Baby-Blink: frühestens nach 3 s Stillstand
    babyBlinkMaxInterval = 7.0,    -- Baby-Blink: spätestens nach 7 s Stillstand
    babyBlinkFrames = 3,           -- Baby-Blinkdauer in Frames (kurze tangentiale Lidlinie)
    babyPushFrames = 5,            -- Push-Reaktion: Kompression + Augenweiten (Frames)
    babyLandingFrames = 9,         -- Bridge-Landing-Impuls + kurzer Blick zurück (Frames, ~0.18 s)
    babyLookTravel = 1.2,          -- Pupillen-Travel: Player-Tracking (Auge folgt dem Spieler) und Bridge-Ready (radial zur Brücke)
    babyReadyPull = 1,             -- Bridge-Ready: Körper 1 px radial zur Brücke
    babyReadyPulsePeriod = 1.2,    -- Bridge-Ready: subtiler Körper-/Dock-Puls (s)
    babyReadyPulse = 0.5,          -- Bridge-Ready: 1-px-Pulsamplitude (px)

    -- Gemeinsamer Brückentransit (Player + Baby, EIN A): kurzer Halt, dann
    -- startet das Baby zuerst (Lead) und bewegt sich schneller (kleinere Figur),
    -- der Player folgt direkt dahinter mit längerer Dauer. Dadurch bleiben beide
    -- gleichzeitig auf der Brücke, aber mit sauberem, sichtbarem Abstand.
    --   Baby:  hold .. hold+babyDuration (~0,05-0,23 s)
    --   Player: hold+babyLead .. hold+babyLead+playerDuration (~0,12-0,44 s)
    sharedBridgeHold = 0.05,       -- Phase 1: kurzer Halt (Blick zur Brücke) (s)
    sharedBabyLead = 0.07,         -- Phase 2: Baby startet vor dem Player (s)
    sharedBabyDuration = 0.18,     -- Baby-Bewegungsdauer (s, kleiner/schneller)
    sharedPlayerDuration = 0.32,   -- Player-Bewegungsdauer (s, folgt direkt) -> total ~0,44 s

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
    audioBridgeVolume = 0.7,          -- deutlich hörbar, klar unter dem Crossing-Zip
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
    -- mechanischer Zip+Snap. Lauter/länger + mittleres Frequenzband, damit er
    -- auch ohne Kopfhörer am kleinen Playdate-Lautsprecher klar hörbar ist.
    audioBridgeCrossFreq = 300,       -- Zip-Glide Startfrequenz (Hz)
    audioBridgeCrossEndFreq = 150,    -- Zip-Glide Endfrequenz (Hz, Abwärts-Sweep)
    audioBridgeCrossDuration = 0.18,  -- kurz, aber klar hörbar (s)
    audioBridgeCrossVolume = 0.95,
    -- Pass 3 (Auftrag): Zip + kleiner mechanischer Abschluss beim Landen
    -- (zip/shff -> tick). Der Tick wird auf demselben Synth zeitversetzt
    -- (when = Start + Dauer) getriggert — genau einmal pro Transit, kein Spam.
    audioBridgeCrossTickFreq = 200,   -- Tick-Frequenz (Hz, mechanisch)
    audioBridgeCrossTickVolume = 0.8,
    audioBridgeCrossTickLen = 0.04,   -- sehr kurz (s)
    -- Raumübergang (eigener Sound beim bestätigten GEMEINSAMEN Raumabschluss;
    -- klar größer als Brückenwechsel, ruhig-atmosphärisch, kein Sieg-Jingle).
    -- Tiefes Ende angehoben (55 Hz wäre am kleinen Lautsprecher unhörbar).
    audioRoomTransFreq = 260,         -- Sweep-Startfrequenz (Hz)
    audioRoomTransEndFreq = 110,      -- Sweep-Endfrequenz (Hz, tief ziehend)
    audioRoomTransDuration = 0.9,     -- Dauer (s)
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

    -- Menü (Phase 10.1): Startmenü-Layout (rein visuell, 1-Bit, keine Animation).
    menuFontHeight = 8,             -- Systemfont-Höhe (px) für die Marker-Zentrierung
    -- Menü-Startanimation (neuer Startbildschirm): ruhiger, reduzierter Einstieg.
    menuIntroDuration = 2.2,        -- Gesamtdauer der Start-Animation (s)
    menuIntroTitleDelay = 1.1,      -- Titeltext erscheint ab dieser Zeit (s)
    menuIntroItemsDelay = 1.6,      -- Menüeinträge gleiten ab dieser Zeit ein (s)
    menuTitleText = "RINGE",        -- Spieltitel (VERSALIEN, spiegelt pdxinfo)
    menuTitleY = 88,                -- Titel-y (Zentrum)
    menuTitleCharW = 8,             -- grobe Zeichenbreite für die Titel-Zentrierung (px)
    menuTitleCenterX = 200,         -- Zentrum der Ring-Titelgrafik
    menuTitleCenterY = 92,
    menuTitleOuterRadius = 60,      -- äußerer Titelring
    menuTitleInnerRadius = 42,      -- innerer Titelring
    menuTitleArcRadius = 51,        -- Pfad-Andeutung (Bogen zwischen den Ringen)
    menuTitleArcStart = 200,        -- Bogenanfang (Grad CW)
    menuTitleArcEnd = 260,          -- Bogenende (Grad CW)
    menuTitleCoreRadius = 8,        -- Kern (gefüllt)
    menuTitleLineWidth = 2,         -- Linienstärke der Titelringe
    menuTitleBridgeAngle = 270,     -- Andeutung einer Brücke (radialer Strich)
    menuEntryX = 200,               -- horizontale Mitte der Einträge
    menuEntryY1 = 168,              -- y-Position „Weiter"
    menuEntryY2 = 196,              -- y-Position „Von vorn"
    menuMarkerRadius = 4,           -- Auswahlmarkierung (aktiv gefüllt, inaktiv leer)
    menuMarkerOffset = 16,          -- Abstand der Markierung links vom Text

    -- Eingaben (Phase 10.4): B = Undo (Press-Edge, genau ein Undo pro Druck;
    -- kein B-Hold-Restart, kein Fortschrittsring — B-Taste Rework) + Crank-
    -- eingeklappt-Hinweis. Raumneustart nur noch über das Systemmenü.
    crankOverlayX = 288,            -- Crank-Hinweis-Box (obere rechte Ecke, kompakt)
    crankOverlayY = 8,
    crankOverlayWidth = 106,
    crankOverlayHeight = 34,
    crankHintDuration = 6.0,       -- Crank-Hinweis nur die ersten X s pro Raum (Onboarding)

    -- Schalter-Darstellung (rein visuell, kein Gameplay): kleine mechanische
    -- Nocke in der Ringbahn mit gerichteter Spitze (A=CW, B=CCW) und kurzer
    -- Press-Animation bei echtem Umschalten.
    -- Schalter-Look (Auftrag: Switch/Bridge Visual Polish). Drei Zeichen-
    -- Varianten stehen im Renderer bereit (per Screenshot-Harness verglichen);
    -- switchStyle wählt die aktive. Gemeinsam: beide Richtungen (CW-Seite =
    -- Zustand A, CCW-Seite = Zustand B) sind GLEICHZEITIG sichtbar; die AKTIVE
    -- Seite ist gefüllt + kräftig, die inaktive nur Kontur + kleiner. Kein Text,
    -- kein 1-px-Detail (bei 400x240-Gameplayansicht klar erkennbar).
    switchStyle = "C",             -- "A" (Pfeile) | "B" (Kapsel) | "C" (Punkt+Nase)
    switchBodyRadius = 5.5,        -- Nocke (px), überdeckt die 8-px-Bahn (lesbar)
    switchMarkActive = 1.3,        -- aktiver Punkt: Radius (px), gefüllt
    switchMarkInactive = 2.0,      -- inaktive Marke: Außenradius (px), 1-px-Konturring
    switchArrowLen = 1.6,          -- Pfeilspitze aktiv: Länge (px, halbe Spannweite)
    switchArrowLenInactive = 1.2,  -- Pfeilspitze inaktiv: Länge (px)
    switchArrowWidth = 2,          -- Pfeilspitze aktiv: Strichstärke (px)
    switchArrowWidthInactive = 1,  -- Pfeilspitze inaktiv: Strichstärke (px)
    switchCapsuleLong = 9.0,       -- Variante B: Kapsel-Längsradius tangential (px)
    switchCapsuleShort = 4.5,      -- Variante B: Kapsel-Querradius radial (px)
    switchCapsuleMark = 2.0,       -- Variante B: aktive Endmarke Radius (px, gefüllt)
    switchCapsuleMarkInactive = 1.5, -- Variante B: inaktive Endmarke Radius (px, Kontur)
    switchNoseTip = 5.0,           -- Variante C: Nasen-Spitze (px vom Zentrum)
    switchNoseBase = 3.4,          -- Variante C: Nasen-Basis (px vom Zentrum)
    switchNoseHalf = 2.2,          -- Variante C: Nasen-Halbbreite (px)
    switchPressFrames = 2,         -- Press-Animation: Frames eingedrückt (nur echtes Umschalten)
    switchPressOffset = 1.5,       -- Press-Offset radial zur Ringmitte (px)
    switchPressProximity = 12,     -- Winkelbereich (°) für die Zuordnung „Spieler am Schalter"

    -- Atmosphere (rein visuell, kein Gameplay): Mikroreaktionen + Lebendigkeit.
    switchPreContactRangePx = 8,   -- Vor-Kontakt: Lasche spannt sich (px Bogenlänge)
    switchPreContactLash = 1,      -- Vor-Kontakt: max. 1 px Bewegung der Spitze
    shutterOvershootFrames = 2,    -- Blende schließen: 1 px über Endposition, 2 Frames zurück
    shutterOvershootPx = 1,        -- Überschwinger der Blende (px, rein visuell)
    bridgeExtendStage1 = 0.10,     -- Brücke 0 -> 45 % schnell (s)
    bridgeExtendStage2 = 0.06,     -- kurze mechanische Pause (s)
    bridgeExtendStage3 = 0.09,     -- 45 -> 100 % schnell (s)
    bridgeSettleFrames = 2,        -- Brücke voll ausgefahren: 1 px Nachsetzen (Frames)
    idleGazeDelay = 3.5,           -- Idle-Blick: nach X Sekunden ohne Bewegung (s)
    idleGazeTravel = 1.2,          -- Idle: Pupille wandert max. 1.2 px Richtung Kern
    idleGazeCycle = 4.0,           -- Idle: Zeit für Blick hin und zurück (s)
    corePulseAmplitude2 = 0.15,    -- zweite, langsamere Atemwelle (px)
    corePulsePeriod2 = 7.0,        -- zweite Wellenperiode (s)
    ghostDriftSpeeds = { 0.05, 0.08, 0.06, 0.10 },  -- Ghost-Drift (°/s)
    ghostDriftDirections = { -1, 1, -1, 1 },        -- gegenläufig
    ghostMarkDotDeg = 4,           -- kleine Indexmarke je Ghost (Bogen °) für sichtbaren Drift
    -- Pass 2: Mikro-Partikel entfernt (1-px-Funken wirkten arcade-artig und
    -- redundant neben Press-Animation + Snap-Sound). Kurze visuelle Ruhe vor
    -- der Raumtransition + kurzer Stillstand am finalen Gate.
    completionPulseDuration = 0.20,-- Systemimpuls nach Raum-Lösung (s)
    completionPause = 0.10,        -- Kamera hält 0.1 s, bevor die Raumtransition startet (s)
    finalHoldFrames = 10,          -- Raum 6: Welt hält 0.2 s still (Ghost-Drift stoppt) vor dem Outro
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
