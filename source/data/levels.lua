-- Ein Raum:
-- rings = { outer = <Ringnummer>, inner = <Ringnummer> }
-- start = { ring = "outer", angle = 0 }
-- switches = { { id, ring, angle, symbol, onA, onB, state } }
--   state ist "A" oder "B" beim Start.
--   onA/onB sind IDs von Blenden oder Brücken.
--   In Zustand A ist onA aktiv (Brücke ausgefahren / Blende offen),
--   onB inaktiv. In Zustand B umgekehrt. Immer genau eines.
-- shutters = { { id, ring, angle } }        -- Blende, Bogenbreite aus config
-- bridges  = { { id, angle, free } }        -- verbindet outer und inner
--   free = true bedeutet dauerhaft ausgefahren, von keinem Schalter gesteuert.
-- gate     = { id = "T", angle, free }      -- Kernbrücke, sitzt auf dem inneren Ring
-- symbol: 1 = Punkt, 2 = zwei Punkte, 3 = Strich

-- Alle acht Räume, exakt in dieser Reihenfolge.
Levels = {

    -------------------------------------------------------------------- 1
    -- LEVEL 1 (Einstieg): Player + Baby + Brücke. Zwei Ringe, keine Schalter,
    -- keine Blenden, keine Druckplatte, keine Einmalmechanik. Das Baby ist ab
    -- LEVEL 1 dabei (der frühere reine Baby-Tutorial-Raum entfällt; sein Aufbau
    -- ist jetzt LEVEL 1). Der Player startet außen@0, das Baby startet außen@60
    -- (einige wenige Winkelpositionen VOR dem Bridge-Dock B1@90) — der Player
    -- muss das Baby also auf natürliche Weise in Richtung Brücke SCHIEBEN. Die
    -- FREIE Brücke B1@90 ist von Anfang an aktiv; die leichte Kurbel-Schwelle
    -- leitet den gemeinsamen Transit.
    --
    -- Ablauf: Player schiebt Baby CW 60 -> ~90 (Bridge-Dock B1@90). Ein A
    -- startet den GEMEINSAMEN Brückentransit (Baby voran, Player folgt). Beide
    -- landen auf dem inneren Ring (Player@90, Baby@100). Danach schiebt der
    -- Player das Baby den kurzen Weg CW zum freien Tor T@135 (inner) — das
    -- Level ist NUR gemeinsam abschließbar (Gate verlangt Player UND Baby).
    -- Keine Sackgasse: die freie Brücke bleibt in beide Richtungen nutzbar.
    {
        name = "Über die Brücke",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },

        -- Baby (Begleiter): startet gemeinsam mit dem Spieler auf dem äußeren
        -- Ring, wenige Winkelpositionen vor der Brücke B1@90 (2 × 15° vor dem
        -- Dock-Rand ~75). Nicht fertig auf dem Dock, aber nah genug für einen
        -- kurzen, klaren Schub.
        baby = {
            start = { ring = "outer", angle = 60 },
        },

        switches = {},

        shutters = {},

        bridges = {
            -- Einzige Brücke: frei (= von Anfang an aktiv), normal, bidirektional.
            { id="B1", angle=90, free=true },
        },

        -- Tor auf dem INNEREN Ring bei 135°, frei: nach dem gemeinsamen Transit
        -- (Landung inner@90/Baby@100) nur ein kurzer Schub bis zum Ausgang.
        -- Abschluss nur gemeinsam mit dem Baby (Gate.isUsable prüft Player UND
        -- Baby auf dem Gate-Ring).
        gate = { id="T", ring="inner", angle=135, free=true },
    },

    -------------------------------------------------------------------- 2
    -- LEVEL 2: gerichteter Doppelschalter + Shutter (mit Baby). Zwei Ringe,
    -- keine Druckplatte, keine Einmalmechanik. Das Baby startet außen@45 und
    -- wird ab hier mitgeführt. Der Shutter D1@90 (Bogen [77,103]) blockiert
    -- den direkten Zugang zur freien Brücke B1@90: deren gesamter Dockbereich
    -- liegt im Shutter-Bogen — solange D1 zu ist, kann der Player nicht
    -- andocken. Der Doppelschalter S1@270 liegt auf der offenen Ringseite.
    -- CW-Überquerung -> Zustand A (öffnet D1, schließt D2 inner), CCW -> B
    -- (D1 zu, D2 inner offen). Startzustand B -> D1 geschlossen: der
    -- natürliche CW-Weg prallt an der Blende ab; der Umweg führt über S1 aus
    -- CCW-Richtung (B = falsch, Weg bleibt zu), zurück über S1 aus CW-
    -- Richtung (A = richtig, sichtbarer Wechsel) öffnet D1 -> Brücke -> Tor.
    -- Das Baby wird im CW-Umweg als erster „Mitnahme-Schub“ Richtung Brücke
    -- geschoben; nach dem gemeinsamen Transit ein kurzer Schub zum Tor.
    {
        name = "Richtung entscheidet",
        rings = { outer = 6, inner = 5 },
        start = { ring = "outer", angle = 0 },

        baby = {
            start = { ring = "outer", angle = 45 },
        },

        switches = {
            { id="S1", ring="outer", angle=270, symbol=1, onA="D1", onB="D2", state="B" },
        },

        shutters = {
            { id="D1", ring="outer", angle=90 },
            -- D2 inner@180: in Zustand B offen, in Zustand A (richtige CW-
            -- Wahl) geschlossen — sichtbare Rückwirkung des Doppelschalters
            -- auf beiden Ringen; blockiert nach S1=A den inneren CCW-Rückweg
            -- (kein Herumirren nach dem Transit, kein Einfluss auf den
            -- Torweg CW).
            { id="D2", ring="inner", angle=180 },
        },

        bridges = {
            { id="B1", angle=90, free=true },
        },

        gate = { id="T", ring="inner", angle=135, free=true },
    },

    -------------------------------------------------------------------- 3
    -- LEVEL 3 (Druckplatte + Baby parken + Doppelschalter, erstes echtes
    -- Puzzle): KEINE künstliche Startposition — Player und Baby kommen aus
    -- Level 2 (ENTRY = Level-2-Tor @135: Player äußerer Ring @135, Baby @145,
    -- Baby liegt CW vor dem Player -> PUSH_DIRECTION = CW). Alle Objekte sind
    -- relativ zu ENTRY platziert (P = ENTRY+105).
    --
    -- DREI ZU KOMBINIERENDE TEILE (mittel-leicht bis mittel):
    --   1) BABY PARKEN: Das Baby wird mit wenigen bewussten Pushes CW auf die
    --      Druckplatte P (outer@240) geschoben und dort GEHALTEN. P öffnet S1
    --      (outer@290) — der einzige Zugang zur Brücke A (outer/inner@290,
    --      Dock liegt im S1-Bogen) führt also durch den geöffneten S1. Die
    --      Plattenposition ist zugleich der räumliche Bezugspunkt: Player
    --      verlässt das Baby auf P, muss um den Ring herum und später über die
    --      ANDERE Seite zurückkehren (Aha: „Baby hält die Wache“).
    --   2) DOPPELSCHALTER D (inner@310): Nach dem Solo-Transit über Brücke A
    --      (Landung inner@290) ist der kurze offensichtliche CW-Weg zu Brücke B
    --      durch S2 (inner@335, Bogen [322,348], anfangs zu) versperrt. Die
    --      CW-Überquerung von D (Zustand A, anfangs aktiv) setzt den FALSCHEN
    --      Zustand (S2 bleibt zu); erst die CCW-Überquerung (Zustand B) öffnet
    --      S2. Danach darf D NICHT erneut überquert werden — deshalb die lange
    --      CCW-Route um den inneren Ring durch S2 (offen) zu Brücke B@340.
    --   3) ANDERE BABYSEITE (Aha): Brücke B landet den Player auf dem äußeren
    --      Ring bei 340° — auf der ANDEREN Seite des Babys (vorher konnte der
    --      Player nur CW schieben, weil S1 den Weg zur Gegenseite versperrte).
    --      Jetzt schiebt er das Baby in der GEGENRICHTUNG (CCW) von P herunter
    --      (P wird frei, S1 schließt — egal, Brücke A wird nicht mehr
    --      gebraucht) und weiter CCW um den Ring bis zur Brücke B@340.
    --      Gemeinsamer Transit -> innerer Ring -> kurzer Schub zum Tor T@135.
    -- Keine Einmalmechanik, keine zusätzlichen Objekte. Alle Objekte sind
    -- relativ zum ENTRY platziert; die Anordnung (Baby CW vor dem Player)
    -- entspricht der CW-Variante (keine Spiegelung nötig).
    {
        name = "Wache halten",
        rings = { outer = 5, inner = 4 },
        start = { ring = "outer", angle = 135 },  -- ENTRY = Level-2-Ausgang

        -- Baby: erbt die tatsächliche Position aus Level 2 (am Tor, Baby liegt
        -- CW vor dem Player -> Push-Richtung CW).
        baby = {
            start = { ring = "outer", angle = 145 },
        },

        switches = {
            -- Doppelschalter D (inner@310): CW -> A, CCW -> B. S2 ist über onB
            -- gekoppelt: in Zustand B OFFEN, in Zustand A ZU (Start A -> S2 zu).
            -- Die natürliche kurze CW-Anfahrt von Brücke A (Landung inner@290)
            -- erzeugt den FALSCHEN Zustand (S2 bleibt zu, Brücke B versperrt);
            -- die Gegenrichtung (CCW zurück über D) öffnet S2 — danach muss D
            -- NICHT erneut überquert werden (lange CCW-Route durch S2 zu B@340).
            { id="D", ring="inner", angle=310, symbol=1, onA={}, onB="S2", state="A" },
        },

        shutters = {
            -- S1 outer@290 (Bogen [277,303]): von der Druckplatte P gesteuert
            -- (momentan). Anfangs GESCHLOSSEN und deckt die Brücke A@290 ab —
            -- ohne Baby auf P ist Brücke A aus KEINER Richtung erreichbar.
            { id="S1", ring="outer", angle=290 },
            -- S2 inner@340 (Bogen [327,353]): vom Doppelschalter D gesteuert.
            -- Anfangs zu (D=A) und EXAKT auf die Brücke B@340 zentriert — der
            -- Dock-Bereich von Brücke B liegt vollständig im geschlossenen
            -- S2-Bogen, sodass die Brücke ohne D=richtig (Zustand B) aus
            -- KEINER Richtung erreichbar ist (kein Andocken über die Kante).
            { id="S2", ring="inner", angle=340 },
        },

        bridges = {
            -- Brücke A@290 (äußere/innere Seite): Solo-Übergang des Players auf
            -- den inneren Ring (Baby bleibt auf P). Dock liegt im S1-Bogen.
            { id="A", angle=290, free=true },
            -- Brücke B@340 (äußere/innere Seite): Rückweg des Players auf die
            -- ANDERE Babyseite (outer@340 > Baby@240) + finaler gemeinsamer
            -- Transit. Dock liegt im S2-Bogen (nur mit D=richtig erreichbar).
            { id="B", angle=340, free=true },
        },

        -- Druckplatte P (outer@240 = ENTRY+105, momentan): gedrückt, solange
        -- Player ODER Baby auf dem äußeren Ring im Druckbereich um 240° steht
        -- (das geparkte Baby hält sie). Steuert die Blende S1 (outer@290).
        -- Kein Rasten: sobald niemand mehr draufsteht, schließt S1 wieder.
        -- Position bewusst auf der LINKEN Ringseite (240°): bei eingeblendeter
        -- Tutorial-Infoleiste (schwarzer Balken unten, Trennlinie bei y=200)
        -- bleibt die gesamte Platte samt weißer Umrandung oberhalb sichtbar.
        plates = {
            { id="P", ring="outer", angle=240, on="S1" },
        },

        -- Tor inner@135 (= ENTRY, gleiche logische Position wie Level 2):
        -- nach dem gemeinsamen Transit über Brücke B (Landung inner@340/330)
        -- ein kurzer CCW-Schub zum Tor. Abschluss nur gemeinsam mit dem Baby.
        gate = { id="T", ring="inner", angle=135, free=true },
    },

    -------------------------------------------------------------------- 4
    -- LEVEL 4 „Einmalentscheidung“ (EXAKT 2 aktive Ringbahnen + Mittelpunkt;
    -- EINMALSCHALTER als neue Mechanik): KEINE künstliche Startposition —
    -- ENTRY = Level-3-Ausgang (Player äußerer Ring @135, Baby @145: der
    -- Kernbrücken-Handoff landet das Baby einen Bogen VOR dem Player,
    -- PUSH_DIRECTION = CW). Der Mittelpunkt/Future-Core zählt NICHT als
    -- dritte Ringbahn — Level 4 hat genau die zwei aktiven Ringe outer (4)
    -- und inner (3).
    --
    -- PUZZLEGEDANKE: Der Doppelschalter D bestimmt, VON WELCHER SEITE der
    -- Player den EINMALSCHALTER O erreichen kann. Die zunächst naheliegende
    -- Stellung (Zustand B, DB offen) führt auf die FALSCHE Richtung; der
    -- Player muss das erkennen, zurück zu D fahren und ihn aus der
    -- Gegenrichtung überqueren (CW -> Zustand A, DA offen) — dann erreicht er
    -- O von der richtigen Seite und überquert ihn korrekt (CW -> A, O
    -- dauerhaft verbraucht, S2 öffnet dauerhaft). Die falsche Richtung (CCW)
    -- ändert O nicht (S2 bleibt zu) und ist mit Undo korrigierbar.
    --
    -- ABLAUF (Soll-Lösung):
    --   1) Baby CW auf P schieben (P@250) -> S1 öffnet (Bridge A frei).
    --   2) Player CCW durch S1 zu Bridge A@120 -> SOLO auf den inneren Ring.
    --   3) Innerer Ring, D=B Start (DA zu, DB offen): Die RICHTIGE Richtung
    --      (CW) überquert D zu Zustand A (DA öffnet), erreicht O von der
    --      richtigen Seite und überquert ihn korrekt (O verbraucht, S2 öffnet
    --      dauerhaft). Die falsche Richtung (CCW) prallt an S2 ab (Bridge B
    --      versperrt) — mit Undo korrigierbar.
    --   4) Durch den offenen S2-Bereich zu Bridge B@340 -> SOLO zurück auf den
    --      äußeren Ring (outer@340, ANDERE Babyseite).
    --   5) Baby CCW von P holen und zu Bridge B@340 schieben -> SHARED-Transit
    --      zurück auf den inneren Ring (inner@340/330).
    --   6) Player+Baby CCW durch den dauerhaft offenen S2-Bereich zum Tor
    --      T@276 -> gemeinsamer Center-Transit -> EXIT.
    --      (Tor im Bogen (243°,340°): der finale Weg kreuzt D NICHT erneut —
    --      sonst flippte D A->B, DA schlösse und das geschobene Baby prallte
    --      an der geschlossenen DA ab. Das Tor liegt bewusst jenseits von
    --      O/DA auf der CCW-Seite von Bridge B.)
    --
    -- PUZZLEBEDINGUNGEN: P zwingend (Bridge A nur mit Baby auf P), D
    -- bestimmt die O-Anlaufseite (CW -> A -> richtige Seite; CCW -> B ->
    -- falsche Richtung), O löst nur bei vollständiger Überquerung, die
    -- falsche O-Richtung lässt S2 zu (mit Undo korrigierbar), die richtige
    -- O-Richtung öffnet S2 permanent, Bridge B bringt den Player hinter das
    -- Baby, keine Abkürzung macht D oder O überflüssig.
    {
        name = "Einmalentscheidung",
        -- EXAKT 2 aktive Ringbahnen (4/3) + Mittelpunkt — kein dritter Ring.
        rings = { outer = 4, inner = 3 },
        start = { ring = "outer", angle = 135 },  -- ENTRY = Level-3-Ausgang

        -- Baby: erbt die tatsächliche Position aus Level 3 (Kernbrücken-
        -- Handoff: Baby landet einen Bogen VOR dem Player -> CW vor dem
        -- Player, Push-Richtung CW).
        baby = {
            start = { ring = "outer", angle = 145 },
        },

        switches = {
            -- Doppelschalter D (inner@250): CW -> A, CCW -> B. Liegt auf
            -- derselben radialen Linie wie die Druckplatte P (outer@250) und
            -- direkt am Ausgang: kurz VOR der Absperrung DA (inner@278) am
            -- Ziel-Tor T@276 — nur eine kleine Lücke, groß genug für den
            -- Player/Baby-Transit zur Tor-Brücke. DA (inner@278) über onA
            -- (in A OFFEN, bewacht die RICHTIGE Route zu O), DB (inner@20)
            -- über onB (in B OFFEN, bewacht die FALSCHE Richtung). Start B:
            -- DA zu, DB offen. Die richtige Richtung (CW) überquert D zu
            -- Zustand A (DA öffnet) und erreicht O von der richtigen Seite;
            -- die falsche Richtung (CCW) lässt D=B und prallt an S2 ab.
            { id="D", ring="inner", angle=250, symbol=1, onA="DA", onB="DB", state="B" },
            -- EINMALSCHALTER O (inner@300): öffnet S2 in Zustand A (onA="S2")
            -- und ist danach dauerhaft verbraucht (oneShot). Start B -> S2 zu.
            -- Die RICHTIGE Überquerung (CW) setzt A (S2 öffnet dauerhaft); die
            -- falsche Richtung (CCW) ändert O nicht (S2 bleibt zu).
            { id="O", ring="inner", angle=300, symbol=1, onA="S2", onB={}, state="B", oneShot=true },
        },

        shutters = {
            -- S1 outer@120 (Bogen [107,133]): von der Druckplatte P gesteuert.
            -- Anfangs GESCHLOSSEN und deckt die Brücke A@120 ab — ohne Baby
            -- auf P ist Brücke A aus KEINER Richtung erreichbar.
            { id="S1", ring="outer", angle=120 },
            -- DA inner@278 (Bogen [265,291]): vom Doppelschalter D gesteuert,
            -- in ZUSTAND A offen. Bewacht den richtigen Weg von D zu O — als
            -- Absperrung am Ziel-Tor, mit nur kleiner Lücke zum Schalter
            -- D@250 davor.
            { id="DA", ring="inner", angle=278 },
            -- DB inner@20 (Bogen [7,33]): vom Doppelschalter D gesteuert,
            -- in ZUSTAND B offen. Bewacht den falschen (CCW-)Weg.
            { id="DB", ring="inner", angle=20 },
            -- S2 inner@340 (Bogen [327,353]): vom Einmalschalter O gesteuert,
            -- in ZUSTAND A offen (nach dem richtigen One-Shot DAUERHAFT).
            -- EXAKT auf die Brücke B@340 zentriert — der Dock-Bereich liegt
            -- vollständig im geschlossenen S2-Bogen, bis O richtig entschieden
            -- ist.
            { id="S2", ring="inner", angle=340 },
        },

        bridges = {
            -- Bridge A@120 (outer <-> inner): Solo-Übergang des Players auf den
            -- inneren Ring (Baby bleibt auf P). Dock liegt im S1-Bogen.
            { id="A", angle=120, free=true },
            -- Bridge B@340 (inner <-> outer): RÜCKWEG des Players hinter das
            -- Baby (outer@340 > Baby@250) + gemeinsamer Rücktransit. Dock
            -- liegt im S2-Bogen (nur mit O richtig erreichbar).
            -- babyLandDir = -1: Das Baby landet nach dem GEMEINSAMEN Transit
            -- DETERMINISTISCH auf der CCW-Seite (links, inner@330) — vor dem
            -- Player@340. Dadurch greift der finale CCW-Schub zum Tor immer
            -- (unabhängig davon, aus welcher Richtung das Baby zuletzt an die
            -- Brücke geschoben wurde: auch ein CW-Schub in den Dock-Bereich
            -- würde sonst das Baby auf die CW-Seite (inner@350) legen und den
            -- finalen Weg blockieren).
            { id="B", angle=340, free=true, babyLandDir=-1 },
        },

        -- Druckplatte P (outer@250, die Position des Doppelschalters — die
        -- beiden haben ihre Winkelplätze getauscht, je auf dem eigenen Ring):
        -- gedrückt, solange Player ODER Baby auf dem äußeren Ring im
        -- Druckbereich um 250° steht (das geparkte Baby hält sie). Steuert die
        -- Blende S1 (outer@120). Kein Rasten: sobald niemand mehr draufsteht,
        -- schließt S1 wieder.
        plates = {
            { id="P", ring="outer", angle=250, on="S1" },
        },

        -- Tor inner@276, frei: die finale Center-Bridge. Erreichbar nur über
        -- den dauerhaft geöffneten S2-Bereich (O richtig entschieden). Das Tor
        -- verlangt Player UND Baby (nur gemeinsam abschließbar).
        -- Position 276° (im Bogen (243°,340°)): der finale CCW-Weg von Bridge
        -- B@340 zum Tor kreuzt D NICHT erneut — ein CCW-Rückweg über D würde
        -- D A->B flippen, DA schließen und das geschobene Baby prallte an der
        -- geschlossenen DA ab (Push wird nach dem Sweep ausgewertet). Der
        -- Doppelschalter D sitzt bei 250° (gleiche radiale Linie wie P@250),
        -- direkt am Ausgang kurz vor der Absperrung DA@278; die kleine Lücke
        -- (Bogenende D 257° -> Tor-Dock 264°) reicht für den Transit aus.
        gate = { id="T", ring="inner", angle=276, free=true },
    },

    -------------------------------------------------------------------- 5
    -- LEVEL 5 „Punkt ohne Wiederkehr“ (EINMAL-BRÜCKE als Point of No Return):
    -- EXAKT 2 aktive Ringbahnen (3/2) + Mittelpunkt, KEIN dritter Ring.
    -- ENTRY = Level-4-Ausgang (Player outer@276, Baby outer@286: das Baby
    -- steht einen Bogen CW vor dem Player -> PUSH_DIRECTION = CW).
    --
    -- PUZZLEIDEE: Die Einmal-Brücke U (outer@342) ist FREI und liegt CW vom
    -- Baby-Parkplatz — sie ist nur erreichbar, indem der Player das Baby dorthin
    -- SCHIEBT. Wer U sofort (vor der Vorbereitung) benutzt, landet auf dem
    -- inneren Ring, aber S2 UND das Tor T sind noch geschlossen (O nicht
    -- ausgelöst) und U ist danach weg -> falsche Reihenfolge, mit Undo
    -- korrigierbar. Der AHA-MOMENT: „Bevor ich diese Brücke verbrauche, muss
    -- ich auf der anderen Seite alles vorbereitet haben.“
    --
    -- ABLAUF (Soll-Lösung):
    --   1) Baby CW auf P schieben (P@330) -> S1 öffnet (Weg zu D/O).
    --   2) Player CCW durch S1 zu D@125: die NATÜRLICHE CCW-Überquerung von D
    --      öffnet den richtigen Weg (D -> B, DA@95 offen — andersherum als
    --      gewohnt).
    --   3) DA passieren, O@65 von der richtigen Seite (CCW) überqueren ->
    --      O verbraucht, S2 (inner@60) UND das Tor T (inner@180) öffnen
    --      DAUERHAFT — der innere Weg ist vorbereitet.
    --   4) Player kehrt CW zurück und schiebt das Baby dabei CW zu U@342
    --      (Baby verlässt P, S1 schließt — egal, denn O/S2/T sind vorbereitet).
    --   5) U GEMEINSAM überqueren (U verschwindet erst NACH der vollständigen
    --      Überquerung).
    --   6) Beide sind nun auf dem inneren Ring (kein Zurück) und nehmen den
    --      vorbereiteten Weg CW durch S2 (inner@60, gegenüberliegende Seite)
    --      zur Center-Bridge T@180 -> EXIT.
    --
    -- TANZ-SEKTION gleichmäßig verteilt (je 30° Abstand zwischen den Zentren):
    --   D@125 --30°--> DA@95 --30°--> O@65 --30°--> DB@35. Der Doppelschalter
    --   steht damit 30° von O (Einmalschalter) und 30° von seinem Segment DA
    --   entfernt; auch vom Tor T@180 ist D weit (55°).
    --
    -- PUZZLEBEDINGUNGEN: P zwingend (ohne Baby auf P kommt Player nicht zu
    -- D/O), D bestimmt die Anlaufseite von O (B sperrt den richtigen Weg über
    -- DA; A öffnet ihn), O öffnet S2 dauerhaft UND das Tor T (One-Shot; das
    -- Tor ist der harte Bypass-Schutz: die frühe U-Überquerung endet am
    -- geschlossenen Tor, egal welchen inneren Weg man wählt), U ist die
    -- EINZIGE Verbindung zum inneren Ring und kollabiert nach der ersten
    -- vollständigen Überquerung, S2 führt den vorbereiteten inneren Weg CW
    -- (gegenüberliegende Seite) zur Center-Bridge. Kein trivialer Bypass,
    -- keine dritte Ringbahn.
    {
        name = "Punkt ohne Wiederkehr",
        rings = { outer = 3, inner = 2 },
        start = { ring = "outer", angle = 276 },  -- ENTRY = Level-4-Ausgang (Tor T@276)

        baby = {
            start = { ring = "outer", angle = 286 },  -- Baby 10° CW vor dem Player
        },

        switches = {
            -- Doppelschalter D (outer@125): CW -> A, CCW -> B. Start A.
            -- ANDERSHERUM als üblich: Die natürliche CCW-Überquerung (vom
            -- Einstieg kommend) öffnet den RICHTIGEN Weg — DA@95 ist über onB
            -- (in B OFFEN). DB@35 ist über onA (in A OFFEN) und bewacht die
            -- andere (falsche) Seite; nach der natürlichen Überquerung (B) ist
            -- DB zu. Gleichmäßig 30° von O und von DA entfernt (Kette
            -- D@125 --30°--> DA@95 --30°--> O@65 --30°--> DB@35); auch vom
            -- Tor T (inner@180) weit entfernt (55°).
            { id="D", ring="outer", angle=125, symbol=1, onA="DB", onB="DA", state="A" },
            -- EINMALSCHALTER O (outer@65): Start A, S2/T zu (onB = { "S2", "T" }).
            -- Die richtige Überquerung (CCW -> B) verbraucht O und öffnet S2
            -- (inner@240) UND das Tor T (inner@180) DAUERHAFT — der Weg auf dem
            -- inneren Ring (inkl. Center-Bridge) ist damit vorbereitet, BEVOR
            -- die Einmal-Brücke verbraucht wird. Das O-gesteuerte Tor ist der
            -- harte Bypass-Schutz: eine frühe U-Überquerung endet am
            -- geschlossenen Tor. 30° von DA und 60° von D entfernt.
            { id="O", ring="outer", angle=65, symbol=1, onA={}, onB={ "S2", "T" }, state="A", oneShot=true },
        },

        shutters = {
            -- S1 outer@210 (Bogen [197,223]): von der Druckplatte P gesteuert.
            -- Anfangs GESCHLOSSEN (sperrt den CCW-Weg zu D/O) — ohne Baby auf
            -- P kommt der Player nicht zu D/O. Verlässt das Baby P (nach
            -- getaner Vorbereitung), schließt S1 wieder — egal, O/S2/T sind
            -- bereits dauerhaft vorbereitet.
            { id="S1", ring="outer", angle=210 },
            -- DA outer@95 (Bogen [82,108]): von D gesteuert, in ZUSTAND B
            -- offen (ANDERSHERUM: die natürliche CCW-Überquerung von D öffnet
            -- den richtigen Anlauf zu O; in Zustand A ist DA zu). 30° von
            -- D@125 und 30° von O@65 entfernt.
            { id="DA", ring="outer", angle=95 },
            -- DB outer@35 (Bogen [22,48]): von D gesteuert, in ZUSTAND A
            -- offen. Bewacht die andere (falsche) Seite hinter O (Startzustand
            -- A: DB offen, DA zu). 30° von O@65.
            { id="DB", ring="outer", angle=35 },
            -- S2 inner@60 (Bogen [47,73]): von O (outer@65) gesteuert, in
            -- ZUSTAND B offen (nach dem richtigen One-Shot DAUERHAFT). Liegt
            -- genau auf der GEGENÜBERLIEGENDEN Seite (180° von der alten
            -- Position 240). Führt den vorbereiteten inneren Weg von der
            -- U-Landung (inner@342/352) CW (durch 0°) zur Center-Bridge T@180.
            -- Der harte Bypass-Schutz ist das O-gesteuerte Tor selbst — S2
            -- führt nur und blockiert zusätzlich den frühen CW-Weg (und den
            -- CCW-Weg hinter dem Tor).
            { id="S2", ring="inner", angle=60 },
        },

        bridges = {
            -- EINMAL-BRÜCKE U@342 (outer <-> inner): die EINZIGE Verbindung
            -- zum inneren Ring — FREI, aber nur erreichbar, indem der Player
            -- das Baby dorthin SCHIEBT (U liegt CW vom Baby-Parkplatz; das
            -- Baby ist immer mit dabei -> frühe Nutzung ist ein GEMEINSAMER
            -- Transit). Kollabiert erst NACH der ersten vollständigen
            -- Überquerung (oneShot, consumedBridges). Frühe Nutzung landet
            -- auf dem inneren Ring bei geschlossener S2 und geschlossenem Tor
            -- -> falsche Reihenfolge, Undo korrigiert. Die richtige Lösung
            -- spart U für den GEMEINSAMEN Transit, NACHDEM O/S2/T vorbereitet
            -- sind.
            { id="U", angle=342, free=true, oneShot=true },
        },

        plates = {
            -- Druckplatte P (outer@330): gedrückt, solange Player ODER Baby im
            -- Druckbereich um 330° steht (das geparkte Baby hält sie). Steuert
            -- S1 (outer@210) — der einzige Zugang zu D/O. Kein Rasten.
            { id="P", ring="outer", angle=330, on="S1" },
        },

        -- Tor inner@180, von O gesteuert (free=false, öffnet in O=B): die
        -- finale Center-Bridge. Geschlossen, solange O nicht richtig entschieden
        -- ist — der harte Bypass-Schutz (eine frühe U-Überquerung endet hier,
        -- egal welcher innere Weg). Erreichbar nur über den VOR der Einmal-
        -- Brücke dauerhaft vorbereiteten Weg. Verlangt Player UND Baby (nur
        -- gemeinsam abschließbar).
        gate = { id="T", ring="inner", angle=180, free=false },
    },

    -------------------------------------------------------------------- 6
    -- LEVEL 6 „Die Schalterkette“ (SCHALTERKETTE als Kernmechanik): die
    -- Einmal-Brücke als gemeinsamer Endweg. EXAKT 2 aktive Ringbahnen (2/1) +
    -- Mittelpunkt, KEIN dritter Ring. ENTRY = Level-5-Ausgang (Player outer@180,
    -- Baby outer@190: Baby 10° CW vor dem Player -> PUSH_DIRECTION = CW).
    --
    -- SCHALTERKETTE (Aha): P -> D1 -> O -> U. Jeder Schritt macht erst den
    -- nächsten erreichbar; kein Schalter öffnet direkt den Ausgang.
    --   1) BABY PARKEN: Baby CW auf P (outer@240) schieben -> P öffnet S1
    --      (outer@120) und erlaubt dem Player den SOLO-Wechsel über Bridge A
    --      auf den inneren Ring (inner@120).
    --   2) D1 (Doppelschalter, inner@170): die richtige Überquerung (CW -> A)
    --      öffnet S2 (inner@220) — hinter S2 liegt der EINMALSCHALTER O.
    --      Falscher Zustand (Start B) lässt S2 geschlossen.
    --   3) O (inner@270, oneShot): CW korrekt auslösen -> O dauerhaft
    --      verbraucht -> S3 (inner@320), das Tor T (inner@10) UND die äußere
    --      Blende S4 (outer@300, der Zugang zur EINMAL-BRÜCKE U) öffnen
    --      dauerhaft. S3 macht die RÜCK-Bridge B (inner@40) erreichbar; S4
    --      sperrt den P->U-Weg, bis die Kette gelöst ist (kein frühes Erreichen
    --      von U mit dem Baby).
    --   4) Player geht SOLO über B zurück auf den Außenring (outer@40) — auf
    --      die ANDERE Seite des Babys.
    --   5) BABY ABHOLEN: Player schiebt das Baby CW (vom Parkplatz@244) durch
    --      die geöffnete S4 zur EINMAL-BRÜCKE U (outer@340) -> U GEMEINSAM
    --      benutzen (U verschwindet erst nach vollständigem Transit). U ist der
    --      einzige Weg, Player + Baby endgültig gemeinsam auf den inneren Ring
    --      zu bringen; ein SOLO-Verbrauch von U ist eine Sackgasse (Baby bleibt
    --      außen, Undo).
    --   6) FINALER WEG: O hat das Tor T dauerhaft geöffnet -> Player + Baby
    --      schieben CW zum Tor (inner@10) -> gemeinsamer Center-Transit -> EXIT.
    --
    -- ANTI-BYPASS: die FESTE Blende F1 (inner@90) versperrt den CCW-Schleichweg
    -- vom A-Landeplatz direkt zur Rück-Bridge B (und den CW-Umweg zum Tor);
    -- der einzige Weg führt durch die Kette. U ist vor der Kette unerreichbar
    -- (S3 zu / F1 zu) und ein Solo-Verbrauch danach ist eine Sackgasse. Das
    -- Tor T ist O-gesteuert — der Ausgang verlangt die volle Kette.
    {
        name = "Die Schalterkette",
        rings = { outer = 2, inner = 1 },
        start = { ring = "outer", angle = 180 },  -- ENTRY = Level-5-Ausgang (Tor T@180)

        baby = {
            start = { ring = "outer", angle = 190 },  -- Baby 10° CW vor dem Player
        },

        switches = {
            -- DOPPELSCHALTER D1 (inner@170): CW -> A, CCW -> B. Start B.
            -- Die richtige Überquerung (CW -> A) öffnet S2 (inner@220) — hinter
            -- S2 liegt O. Falscher Zustand (B) lässt S2 geschlossen (O
            -- unerreichbar). Der CCW-Anlauf ist durch S3/F1 blockiert -> die
            -- richtige Richtung ist die einzig mögliche.
            { id="D1", ring="inner", angle=170, symbol=1, onA="S2", onB={}, state="B" },
            -- EINMALSCHALTER O (inner@270): Start B, S3/T/S4 zu (onA = { "S3", "T", "S4" }).
            -- Die richtige Überquerung (CW -> A) verbraucht O dauerhaft und
            -- öffnet S3 (inner@320), das Tor T (inner@10) UND die äußere
            -- Blende S4 (outer@300) — der Rückweg über B, der finale Weg zum
            -- Ausgang und der Zugang zur EINMAL-BRÜCKE U sind damit
            -- vorbereitet. S4 verhindert, dass U vor der Kette mit dem Baby
            -- erreicht werden kann.
            { id="O", ring="inner", angle=270, symbol=1, onA={ "S3", "T", "S4" }, onB={}, state="B", oneShot=true },
        },

        shutters = {
            -- S1 outer@120 (Bogen [107,133]): von der Druckplatte P gesteuert.
            -- Öffnet den Zugang zur SOLO-Bridge A (innerer Ring), solange das
            -- Baby auf P steht.
            { id="S1", ring="outer", angle=120 },
            -- S2 inner@220 (Bogen [207,233]): von D1 gesteuert, in ZUSTAND A
            -- offen (nach der richtigen D1-Überquerung). Sperrt den Zugang zu
            -- O bei falscher D1-Stellung.
            { id="S2", ring="inner", angle=220 },
            -- S3 inner@320 (Bogen [307,333]): von O gesteuert, in ZUSTAND A
            -- offen (nach dem richtigen One-Shot DAUERHAFT). Gibt den Weg zur
            -- RÜCK-Bridge B (inner@40) frei.
            { id="S3", ring="inner", angle=320 },
            -- F1 inner@90 (Bogen [77,103]): FESTE Blende (fixedClosed) —
            -- versperrt den CCW-Schleichweg vom A-Landeplatz (inner@120) direkt
            -- zur Rück-Bridge B@40 und den CW-Umweg zum Tor. Der einzige Weg
            -- führt durch die Schalterkette.
            { id="F1", ring="inner", angle=90, fixedClosed=true },
            -- S4 outer@300 (Bogen [287,313]): von O gesteuert, in ZUSTAND A
            -- offen (nach dem richtigen One-Shot DAUERHAFT). Versperrt den
            -- äußeren P->U-Weg (CW vom Baby-Parkplatz zur EINMAL-BRÜCKE U@340),
            -- bis die Kette gelöst ist — U ist damit erst NACH der Kette mit
            -- dem Baby erreichbar (kein verwirrendes frühes Erreichen).
            { id="S4", ring="outer", angle=300 },
        },

        bridges = {
            -- Bridge A@120 (outer <-> inner): SOLO-Übergang des Players auf den
            -- inneren Ring (Baby bleibt auf P). Dock liegt im S1-Bogen.
            { id="A", angle=120, free=true },
            -- Bridge B@40 (inner <-> outer): RÜCKWEG des Players auf die ANDERE
            -- Seite des Babys (outer@40 < Baby@244), nur über S3 (O) erreichbar.
            { id="B", angle=40, free=true },
            -- EINMAL-BRÜCKE U@340 (outer <-> inner): die EINZIGE Verbindung für
            -- den GEMEINSAMEN Wechsel von Player + Baby auf den inneren Ring.
            -- Vor der Kette unerreichbar; ein SOLO-Verbrauch danach ist eine
            -- Sackgasse (Baby bleibt außen, Undo). babyLandDir = +1: das Baby
            -- landet nach dem gemeinsamen Transit inner@350 (CW vom Player@340)
            -- — der kurze CW-Weg zum Tor T@10 ist damit direkt möglich.
            { id="U", angle=340, free=true, oneShot=true, babyLandDir=1 },
        },

        plates = {
            -- Druckplatte P (outer@240): gedrückt, solange Player ODER Baby im
            -- Druckbereich um 240° steht (das geparkte Baby hält sie). Steuert
            -- S1 (outer@120) — der einzige Zugang zur SOLO-Bridge A. Kein
            -- zufälliger Parkplatz: P liegt CW vom Einstieg und genau zwischen
            -- Einstieg und U-Brücke; das Baby MUSS hier warten, bis der Player
            -- die Kette innen gelöst und über B zurückgekehrt ist.
            { id="P", ring="outer", angle=240, on="S1" },
        },

        -- Tor inner@10, von O gesteuert (free=false, öffnet in O=A): die finale
        -- Center-Bridge. Geschlossen, solange O nicht richtig ausgelöst ist —
        -- der harte Abschluss der Schalterkette (nur die volle Kette öffnet den
        -- Ausgang). Verlangt Player UND Baby (nur gemeinsam abschließbar).
        gate = { id="T", ring="inner", angle=10, free=false },
    },

    -------------------------------------------------------------------- 7
    -- LEVEL 7 (Finale): INAKTIVE / AKTIVIERBARE BRÜCKEN — „Die Brücke hinter dir“.
    -- Zwei Brücken, die sichtbar kommen und gehen; Druckplatte und
    -- Doppelschalter sind ihre einzigen Herren. Der zentrale Aha-Moment: Man
    -- deaktiviert bewusst die eigene Rückkehrbrücke, weil man sie nicht mehr
    -- braucht — und genau dadurch öffnet sich der Ausgang.
    --
    --   Bridge A (outer<->inner @60): startet INAKTIV (nur Punktreihe). Nur
    --     solange das Baby die Druckplatte P (outer@200) hält, ist A
    --     ausgefahren (Punkte verdichten sich zur normalen Brücke). A ist der
    --     EINZIGE Weg nach innen und nur SOLO benutzbar (das Baby kann nie
    --     gleichzeitig auf P und am A-Dock stehen; sobald es P verlässt,
    --     verschwindet A wieder — absichtlich).
    --   Bridge B (outer<->inner @300): startet INAKTIV. Der Doppelschalter D
    --     (inner@280) aktiviert B in Zustand A und öffnet in Zustand B den
    --     finalen Shutter S (inner@255). B ist der SOLO-Rückweg auf die ANDERE
    --     Babyseite und danach der GEMEINSAME Rückweg (Player + Baby).
    --   Shutter S (inner@255): von D gesteuert, in Zustand B offen — der
    --     Zugang zum finalen Weg zum Tor T (inner@225). Liegt CCW vor dem
    --     Ausgang, damit der letzte Schub nach der D-Umschaltung CCW durch S
    --     zum Tor verläuft (ohne D erneut zu überqueren).
    --   Tor T (inner@225, frei): die normale Center-Bridge — nur gemeinsam mit
    --     dem Baby benutzbar.
    --
    -- ABLAUF (Soll-Lösung):
    --   1) Baby CW auf P (outer@200) schieben -> P gedrückt -> Bridge A
    --      materialisiert sich.
    --   2) Player lässt das Baby BEWUSST auf P zurück und geht SOLO über A
    --      nach innen (inner@60).
    --   3) Player überquert D CW (-> Zustand A): Bridge B materialisiert sich,
    --      Shutter S bleibt geschlossen.
    --   4) Player geht SOLO über B zurück auf den Außenring (outer@300) — auf
    --      die ANDERE Seite des Babys.
    --   5) Player holt das Baby von P (schiebt es CW); sobald das Baby P
    --      verlässt, verschwindet Bridge A wieder (absichtlich — A wird nicht
    --      mehr benötigt). Player schiebt das Baby zu B@300 (outer).
    --   6) Player + Baby benutzen B GEMEINSAM nach innen (inner@300, Baby@310).
    --      D steht noch auf Zustand A -> B ist weiterhin aktiv.
    --   7) Player überquert D jetzt CCW (-> Zustand B): Bridge B verschwindet
    --      HINTER den Figuren (der Rückweg ist bewusst zu), Shutter S öffnet
    --      den Weg zum Tor. D wird danach nie wieder überquert.
    --   8) Player kehrt CCW zum Baby zurück (langer Weg durch die offene S,
    --      ohne D erneut zu überqueren), schiebt es CCW durch den geöffneten
    --      S-Bereich zum Tor T@225.
    --   9) GEMEINSAMER Center-Transit -> LEVELENDE.
    {
        name = "Die Brücke hinter dir",
        rings = { outer = 1, inner = 0 },
        start = { ring = "outer", angle = 20 },

        baby = {
            start = { ring = "outer", angle = 50 },
        },

        switches = {
            -- Doppelschalter D (inner@280): Start B. Zustand A (CW) aktiviert
            -- die Rück-Brücke B und hält den finalen Shutter S geschlossen;
            -- Zustand B (CCW) deaktiviert B und öffnet S. Der Player braucht
            -- ZUERST Zustand A (B materialisiert -> Solo-Rückweg), und erst
            -- NACH dem gemeinsamen B-Transit Zustand B — B verschwindet dann
            -- HINTER den Figuren und S öffnet den Ausgang. Nach Zustand B
            -- wird D nicht wieder überquert.
            { id="D", ring="inner", angle=280, symbol=1, onA="B", onB="S", state="B" },
        },

        shutters = {
            -- Finaler Shutter S (inner@255): von D gesteuert, in Zustand B
            -- offen. Versperrt den CCW-Weg von der B-Landung (inner@310) zum
            -- Tor T@225, solange D auf Zustand A steht; erst die bewusste
            -- D-Umschaltung auf B öffnet den Ausgangsweg.
            { id="S", ring="inner", angle=255 },
        },

        bridges = {
            -- Bridge A (outer<->inner @60): INAKTIVE / AKTIVIERBARE Brücke.
            -- Von der Druckplatte P gesteuert (free=false): ausgefahren NUR
            -- solange das Baby auf P steht. Materialisiert sich sichtbar
            -- (Punktreihe -> normale Brücke), wenn das Baby P hält, und
            -- verschwindet wieder, sobald es P verlässt. A ist der einzige Weg
            -- nach innen und nur SOLO benutzbar.
            { id="A", angle=60, free=false },
            -- Bridge B (outer<->inner @300): INAKTIVE / AKTIVIERBARE Brücke.
            -- Vom Doppelschalter D gesteuert (free=false): in Zustand A aktiv,
            -- in Zustand B eingefahren. SOLO-Rückweg des Players auf die andere
            -- Babyseite, danach GEMEINSAMER Rückweg mit dem Baby. Nach der
            -- D-Umschaltung auf B verschwindet B dauerhaft (hinter den Figuren).
            { id="B", angle=300, free=false },
        },

        -- Druckplatte P (outer@200, momentan): gedrückt, solange das Baby im
        -- Druckbereich um 200° steht. Zwingender Baby-Parkplatz: NUR während
        -- das Baby P hält, materialisiert sich Bridge A. Der Player lässt das
        -- Baby bewusst zurück (Solo über A) und holt es später über B.
        plates = {
            { id="P", ring="outer", angle=200, on="A" },
        },

        -- Tor T (inner@225, frei): die normale Center-Bridge. Abschluss nur
        -- gemeinsam (Player + Baby) — das Tor verlangt das Baby.
        gate = { id="T", ring="inner", angle=225, free=true },
    },

    -------------------------------------------------------------------- 8
    -- LEVEL 8 „Das letzte Band“ (ERSTE STUFE DER SCHWEREN PHASE): ein
    -- NICHT-LINEARES Kombinationspuzzle aus ALLEN bisherigen Mechaniken —
    -- Baby/Push-only, DREI Druckplatten (P1/P2/P3), ZWEI Doppelschalter
    -- (D1/D2), Einmalschalter O, VIER aktivierbare Bridges (A/B/C/D) + finale
    -- Verbindung F (D2=B) + Einmal-Brücke U, MEHRERE Shutter, normale
    -- Center-Bridge (Tor T). EXAKT 2 aktive Ringbahnen (0/-1) + Mittelpunkt,
    -- KEIN dritter Ring, KEIN Tutorial. ENTRY = Level-7-Ausgang (Player
    -- outer@20, Baby outer@50).
    --
    -- PUZZLEKERN: Es gibt ZWEI unterschiedliche notwendige Schalterkonfigura-
    -- tionen — der Spieler muss dieselben Systeme später bewusst wieder
    -- umstellen:
    --   ZWISCHENZIEL (O erreichbar):  D1 = A  UND  D2 = A  UND  P2 = aktiv.
    --   FINALZUSTAND (Weg zum Zentrum): D1 = A, D2 = B, O korrekt verbraucht,
    --   P1/P2/P3 frei.
    -- D1 wird im Sollweg VIERMAL umgestellt (B -> A -> B -> A), D2 GENAU
    -- EINMAL (A -> B). Das Baby wird DREIMAL umpositioniert (P1 -> P2 -> P3).
    -- Die Einmal-Brücke U wird bis zur Phase 10 aufgespart.
    --
    -- ABLAUF (Soll-Lösung, alle Winkel physikalisch verifiziert):
    --   PHASE 1: Baby CW auf P1 (outer@130) schieben -> Bridge A@112 materiali-
    --     siert sich. Player SOLO über A auf den inneren Ring (inner@112).
    --   PHASE 2: D1 (inner@95, Start A) CCW überqueren -> ZUSTAND B: Bridge
    --     B@75 materialisiert (Rückweg), S_O + S_FI + S_FINAL_D1 schließen
    --     (O-Zugang und finaler Weg zu). Player SOLO über B zurück auf den
    --     Außenring (outer@75) — auf der ANDEREN Seite des auf P1 stehenden
    --     Babys.
    --   PHASE 3: Player holt Baby von P1 (Bridge A verschwindet) und schiebt
    --     es CW zur ZWEITEN Druckplatte P2 (outer@149). P2 aktiv -> Bridge
    --     C@132 materialisiert sich.
    --   PHASE 4: Player SOLO über C auf den inneren Ring (inner@132). D1
    --     B -> A (CW): S_O öffnet (erste Hälfte des O-Zugangs), S_FI + S_FINAL_D1
    --     öffnen, Bridge B verschwindet. Jetzt gilt das ZWISCHENZIEL (D2 ist
    --     noch A).
    --   PHASE 5: Player läuft CW durch S_O (D1=A) und S_D2 (D2=A) zum EINMAL-
    --     SCHALTER O (inner@200). Die KORREKTE Überquerung (CCW -> B) verbraucht
    --     O dauerhaft und öffnet den finalen Shutter S_FINAL_O (outer@340)
    --     DAUERHAFT. Die falsche Richtung (CW -> A) ändert O nicht.
    --   PHASE 6: D1 A -> B (CCW): S_O + S_FI + S_FINAL_D1 schließen wieder,
    --     Bridge B materialisiert. Player SOLO über B zurück auf den Außenring
    --     (outer@75) — auf die RICHTIGE Seite von Baby/P2.
    --   PHASE 7: Player holt Baby von P2 (C verschwindet) und schiebt es CW
    --     zur DRITTEN Druckplatte P3 (outer@180). P3 aktiv -> Bridge D@5
    --     materialisiert sich (der dritte, weit entfernte Solo-Einstieg).
    --   PHASE 8: Player SOLO über D auf den inneren Ring (inner@5). D1 B -> A
    --     (CW): S_FI + S_FINAL_D1 öffnen, B verschwindet ENDGÜLTIG für den
    --     Lösungsweg (Rückweg geopfert). D2 A -> B (CCW): S_D2 schließt (O-Zu-
    --     gang zu), S_FINAL_D2 + die finale Verbindung F@295 öffnen.
    --   PHASE 9: Player SOLO über D zurück auf den Außenring (outer@353) und
    --     holt das Baby von P3 (D verschwindet).
    --   PHASE 10: Player schiebt Baby zur EINMAL-BRÜCKE U (outer@45). U JETZT
    --     GEMEINSAM benutzen -> beide auf den inneren Ring (inner@45/Baby@35),
    --     U verschwindet erst NACH dem vollständigen Shared-Transit.
    --   PHASE 11: FINALER PUSH: Player+Baby über die finale Verbindung F
    --     (D2=B, inner@295) auf den Außenring (outer@295/Baby@305), dann CW
    --     durch die drei finalen Shutter S_FINAL_D1 (D1=A), S_FINAL_D2 (D2=B)
    --     und S_FINAL_O (O verbraucht) zum Tor T (outer@355) -> gemeinsamer
    --     Kernbrücken-Transit -> EXIT.
    --
    -- DIE FALLE: U (outer@45) ist früh sichtbar UND benutzbar (frei). Benutzt
    -- der Player sie zu früh (SOLO oder GEMEINSAM), wird U verbraucht und das
    -- Baby kann nicht mehr auf den inneren Ring gebracht werden — Sackgasse,
    -- B-Restart. Die korrekte Lösung spart U bis zur Phase 10 auf.
    --
    -- PUZZLEBEDINGUNGEN / ANTI-BYPASS:
    --   - P1 zwingend (ohne Baby auf P1 ist A inaktiv — A nur solo).
    --   - P2 zwingend (ohne Baby auf P2 ist C inaktiv — der zweite Solo-
    --     Einstieg und damit der O-Zugang sind unerreichbar).
    --   - P3 zwingend (ohne Baby auf P3 ist D inaktiv — der dritte Solo-
    --     Einstieg für die FINALEN Schalterstellungen ist unerreichbar).
    --   - O erreichbar NUR mit D1=A (S_O) UND D2=A (S_D2) UND P2=aktiv (C als
    --     einzige Route auf die innere O-Seite).
    --   - O ist ein EINMALSCHALTER: nur die CCW-Überquerung verbraucht ihn.
    --   - Der finale Weg (F + S_FINAL_O + S_FINAL_D1 + S_FINAL_D2 + Tor) ist
    --     erst offen, wenn O verbraucht, D1=A und D2=B sind — die falschen
    --     Zustände sperren den Ausgang (F ist durch S_FI gesperrt, solange
    --     D1=B; D2=A lässt F verschwinden).
    --   - U früh verbraucht = Sackgasse (das Tor verlangt Player UND Baby).
    {
        name = "Das letzte Band",
        rings = { outer = 0, inner = -1 },
        start = { ring = "outer", angle = 20 },

        baby = {
            start = { ring = "outer", angle = 50 },
        },

        switches = {
            -- DOPPELSCHALTER D1 (inner@95, Start A). A öffnet den O-Zugang
            -- (S_O), entsperrt die finale Verbindung F (S_FI) und öffnet den
            -- ersten finalen Shutter (S_FINAL_D1); B aktiviert die Rück-Bridge
            -- B@75. Der Spieler MUSS D1 im Sollweg VIERMAL umstellen:
            -- B (Ph2) -> A (Ph4, für O) -> B (Ph6, Rückweg) -> A (Ph8, final).
            { id="D1", ring="inner", angle=95, symbol=1, onA={ "S_O", "S_FI", "S_FINAL_D1" }, onB="B", state="A" },
            -- DOPPELSCHALTER D2 (inner@225, Start A). A öffnet S_D2 (zweite
            -- Hälfte des O-Zugangs); B öffnet den zweiten finalen Shutter
            -- (S_FINAL_D2) und materialisiert die finale Verbindung F@295.
            -- Im Sollweg GENAU EIN Wechsel: A -> B (Ph8).
            { id="D2", ring="inner", angle=225, symbol=1, onA="S_D2", onB={ "S_FINAL_D2", "F" }, state="A" },
            -- EINMALSCHALTER O (inner@200, Start A): S_FINAL_O zu (onB). Die
            -- RICHTIGE Überquerung (CCW -> B) verbraucht O dauerhaft und
            -- öffnet den finalen Shutter S_FINAL_O DAUERHAFT. Die CW-Überque-
            -- rung (O bleibt A) ist wirkungslos.
            { id="O", ring="inner", angle=200, symbol=1, onA={}, onB="S_FINAL_O", state="A", oneShot=true },
        },

        shutters = {
            -- S_O inner@150 (Bogen [137,163]): vom Doppelschalter D1 gesteuert,
            -- in ZUSTAND A offen. ERSTE Hälfte des Zugangs zum EINMALSCHALTER O.
            { id="S_O", ring="inner", angle=150 },
            -- S_D2 inner@178 (Bogen [165,191]): vom Doppelschalter D2 gesteuert,
            -- in ZUSTAND A offen. ZWEITE Hälfte des Zugangs zu O (liegt direkt
            -- auf dem O-Zulauf zwischen S_O und O). Schließt wieder, sobald D2
            -- auf B zurückgestellt wird (Ph8).
            { id="S_D2", ring="inner", angle=178 },
            -- S_FI inner@295 (Bogen [282,308]): vom Doppelschalter D1 gesteuert,
            -- in ZUSTAND A offen. Deckt die finale Verbindung F@295 ab: solange
            -- D1=B ist, ist F nicht benutzbar — kein vorzeitiger Wechsel über F
            -- statt U. Öffnet mit D1=A (Ph4/Ph8).
            { id="S_FI", ring="inner", angle=295 },
            -- S_FINAL_D1 outer@305 (Bogen [292,318]): vom Doppelschalter D1
            -- gesteuert, in ZUSTAND A offen. ERSTER finaler Shutter auf dem Weg
            -- zum Tor — schließt, solange D1 auf B steht.
            { id="S_FINAL_D1", ring="outer", angle=305 },
            -- S_FINAL_D2 outer@322 (Bogen [309,335]): vom Doppelschalter D2
            -- gesteuert, in ZUSTAND B offen. ZWEITER finaler Shutter — schließt,
            -- solange D2 auf A steht.
            { id="S_FINAL_D2", ring="outer", angle=322 },
            -- S_FINAL_O outer@340 (Bogen [327,353]): vom EINMALSCHALTER O
            -- gesteuert, in ZUSTAND B (nach dem korrekten One-Shot) DAUERHAFT
            -- offen. DRITTER finaler Shutter auf dem Weg zum Tor.
            { id="S_FINAL_O", ring="outer", angle=340 },
        },

        bridges = {
            -- Bridge A (outer<->inner @112): INAKTIVE / AKTIVIERBARE Brücke.
            -- Von der Druckplatte P1 gesteuert (free=false): ausgefahren NUR
            -- solange das Baby auf P1 steht. Einziger erster Weg nach innen, nur
            -- SOLO benutzbar.
            { id="A", angle=112, free=false },
            -- Bridge B (inner<->outer @75): vom Doppelschalter D1 gesteuert
            -- (free=false), in ZUSTAND B ausgefahren. SOLO-Rückweg des Players
            -- auf die ANDERE Babyseite — benutzt in Phase 2 (nach D1=B) und
            -- Phase 6 (nach D1=B). Nach dem finalen D1=A (Ph8) verschwindet B.
            { id="B", angle=75, free=false },
            -- Bridge C (inner<->outer @132): von der Druckplatte P2 gesteuert
            -- (free=false), ausgefahren NUR solange das Baby auf P2 steht.
            -- Zweiter SOLO-Einstieg (Phase 4).
            { id="C", angle=132, free=false },
            -- Bridge D (inner<->outer @5): von der Druckplatte P3 gesteuert
            -- (free=false), ausgefahren NUR solange das Baby auf P3 steht.
            -- Dritter SOLO-Einstieg (Phase 8) und letzter Rückweg (Phase 9).
            -- babyLandDir = -1: das Baby landet nach einem Shared-Transit auf
            -- der CCW-Seite.
            { id="D", angle=5, free=false, babyLandDir=-1 },
            -- Bridge F (inner<->outer @295): die FINALE VERBINDUNG, vom Doppel-
            -- schalter D2 gesteuert (free=false), in ZUSTAND B ausgefahren und
            -- durch S_FI (D1=A) zusätzlich gesperrt — erst im FINALZUSTAND
            -- (Phase 11) nutzbar. Player+Baby wechseln gemeinsam auf den
            -- Außenring, von wo der Weg zum Tor führt.
            -- babyLandDir = +1: das Baby landet nach dem gemeinsamen Transit
            -- auf der CW-Seite (outer@305 vor dem Player@295).
            { id="F", angle=295, free=false, babyLandDir=1 },
            -- EINMAL-BRÜCKE U (outer<->inner @45): die FALLE + finale Shared-
            -- Brücke. FREI (früh sichtbar UND benutzbar — der Player kann sie
            -- vorzeitig erreichen). Benutzt er sie zu früh, verschwindet sie und
            -- das Baby kann nicht mehr auf den inneren Ring gebracht werden.
            -- babyLandDir = -1: das Baby landet nach dem gemeinsamen Transit auf
            -- der CCW-Seite (inner@35 hinter dem Player@45).
            { id="U", angle=45, free=true, oneShot=true, babyLandDir=-1 },
        },

        plates = {
            -- Druckplatte P1 (outer@130): gedrückt, solange Player ODER Baby im
            -- Druckbereich um 130° steht (das geparkte Baby hält sie). Steuert
            -- Bridge A. Zwingender erster Baby-Parkplatz.
            { id="P1", ring="outer", angle=130, on="A" },
            -- Druckplatte P2 (outer@149): gedrückt, solange Player ODER Baby im
            -- Druckbereich um 149° steht. Steuert Bridge C. Zwingender zweiter
            -- Baby-Parkplatz: P2 bereitet den zweiten Solo-Einstieg und damit
            -- den O-Zugang vor.
            { id="P2", ring="outer", angle=149, on="C" },
            -- Druckplatte P3 (outer@180): gedrückt, solange Player ODER Baby im
            -- Druckbereich um 180° steht. Steuert Bridge D. Zwingender dritter
            -- Baby-Parkplatz: P3 bereitet den dritten Solo-Einstieg (Ph8) für
            -- die FINALEN Schalterstellungen vor.
            { id="P3", ring="outer", angle=180, on="D" },
        },

        -- Tor T (outer@355, frei): die finale Center-Bridge auf dem Außenring.
        -- Nur gemeinsam abschließbar (Gate verlangt Player UND Baby). Erreichbar
        -- nur über die finale Verbindung F (D2=B, D1=A) und die geöffneten
        -- Shutter S_FINAL_O (O verbraucht), S_FINAL_D1 (D1=A) und S_FINAL_D2
        -- (D2=B).
        gate = { id="T", ring="outer", angle=355, free=true },
    },

}

-- Datenvalidator: nur lesend, verändert die Daten nicht.
-- Abnahme-/Entwicklungslogik, keine Spielmechanik.
-- Gibt die Anzahl gefundener Datenfehler zurück; 0 = konsistent.
function Levels.validate()
    local errorCount = 0

    local function report(roomIndex, roomName, id, rule)
        errorCount = errorCount + 1
        local idPart = ""
        if id then
            idPart = " (ID: " .. id .. ")"
        end
        print("Raum " .. roomIndex .. ' "' .. roomName .. '": ' .. rule .. idPart)
    end

    if #Levels ~= 8 then
        errorCount = errorCount + 1
        print("Levels: Anzahl der Räume ist " .. #Levels .. " statt 8")
    end

    for roomIndex, room in ipairs(Levels) do
        local roomName = room.name or "<ohne Name>"
        local before = errorCount

        -- Struktur des Raums
        if room.name == nil then
            report(roomIndex, roomName, nil, "Raum hat kein name")
        end
        if type(room.rings) ~= "table" then
            report(roomIndex, roomName, nil, "Raum hat kein rings")
        else
            if room.rings.outer == nil then report(roomIndex, roomName, nil, "rings.outer fehlt") end
            if room.rings.inner == nil then report(roomIndex, roomName, nil, "rings.inner fehlt") end
            -- Optionaler Mittelring (3-Ring-Raum, Level 4): muss numerisch
            -- STRENG zwischen inner und outer liegen (die Kamera bildet die
            -- Ringnummern über die globale Formel auf Radien ab; der
            -- Mittelring ist "outer - 0.5" = exakt zwischen beiden Bahnen).
            if room.rings.middle ~= nil then
                if type(room.rings.middle) ~= "number" then
                    report(roomIndex, roomName, nil, "rings.middle ist keine Zahl")
                elseif type(room.rings.outer) == "number" and type(room.rings.inner) == "number"
                    and not (room.rings.inner < room.rings.middle and room.rings.middle < room.rings.outer) then
                    report(roomIndex, roomName, nil, "rings.middle muss zwischen inner und outer liegen")
                end
            end
        end
        if type(room.start) ~= "table" then
            report(roomIndex, roomName, nil, "Raum hat kein start")
        else
            if room.start.ring ~= "outer" then report(roomIndex, roomName, nil, 'start.ring ist nicht "outer"') end
            -- Startwinkel: jede Zahl in [0,360) erlaubt. Räume starten generisch
            -- auf einem beliebigen Winkel; die frühere Festlegung auf exakt 0
            -- war eine reine Datenkonvention.
            if type(room.start.angle) ~= "number" then report(roomIndex, roomName, nil, "start.angle fehlt") end
        end

        -- Elemente sammeln (Blenden, Brücken, Tor)
        local elements = {}          -- id -> { kind = "shutter"|"bridge"|"gate", free = bool|nil }
        local controlCount = {}      -- id -> Anzahl der Steuerreferenzen (onA + onB)
        local switchIds = {}

        local function registerElement(id, kind, free, fixedClosed)
            if elements[id] then
                report(roomIndex, roomName, id, "Element-ID doppelt vergeben")
            end
            elements[id] = { kind = kind, free = free, fixedClosed = (fixedClosed == true) }
        end

        for _, s in ipairs(room.shutters or {}) do
            if s.id == nil or s.ring == nil or s.angle == nil then
                report(roomIndex, roomName, s.id, "Blende unvollständig (id/ring/angle)")
            else
                -- fixedClosed = true: dauerhaft geschlossene Blende (feste Wand),
                -- von KEINEM Schalter gesteuert (generische Fähigkeit).
                registerElement(s.id, "shutter", nil, (s.fixedClosed == true))
            end
        end

        for _, b in ipairs(room.bridges or {}) do
            if b.id == nil or b.angle == nil or b.free == nil then
                report(roomIndex, roomName, b.id, "Brücke unvollständig (id/angle/free)")
            else
                registerElement(b.id, "bridge", b.free)
            end
            -- Endpunkt-Ringe (3-Ring-Räume): b.rings = { <RingA>, <RingB> }
            -- gibt an, welche beiden Ringe die Brücke verbindet (z. B. outer
            -- <-> middle). Ohne rings-Feld gilt der 2-Ring-Standard
            -- (inner <-> outer). Beide Namen müssen existierende Ringe des
            -- Raums sein und sich unterscheiden.
            if b.rings ~= nil then
                if type(b.rings) ~= "table" or #b.rings ~= 2 then
                    report(roomIndex, roomName, b.id, "Brücke rings muss ein 2er-Feld sein")
                else
                    local ringA, ringB = b.rings[1], b.rings[2]
                    local valid = { outer = room.rings.outer ~= nil, middle = room.rings.middle ~= nil, inner = room.rings.inner ~= nil }
                    if not (valid[ringA] and valid[ringB]) then
                        report(roomIndex, roomName, b.id, "Brücke rings verweist auf unbekannten Ring")
                    elseif ringA == ringB then
                        report(roomIndex, roomName, b.id, "Brücke rings muss zwei verschiedene Ringe verbinden")
                    end
                end
            end
        end

        if type(room.gate) == "table" then
            if room.gate.id == nil or room.gate.angle == nil or room.gate.free == nil then
                report(roomIndex, roomName, "gate", "Tor unvollständig (id/angle/free)")
            else
                registerElement(room.gate.id, "gate", room.gate.free)
            end
            -- Generisches Gate: ring darf "outer"/"inner" sein (Default "inner");
            -- das Gate kann damit auf jedem spielbaren Ring liegen.
            if room.gate.ring ~= nil and room.gate.ring ~= "outer" and room.gate.ring ~= "inner" then
                report(roomIndex, roomName, "gate", 'gate.ring ist nicht "outer"/"inner"')
            end
        else
            report(roomIndex, roomName, nil, "Raum hat kein gate")
        end

        -- Baby (generisch, Begleiter): optional. Wenn vorhanden muss start
        -- einen gültigen Ring und Winkel haben. Räume ohne Baby bleiben
        -- valide. Es gibt KEIN Ablageziel (baby.goal) mehr.
        if room.baby ~= nil then
            local bStart = room.baby.start
            if type(bStart) ~= "table" then
                report(roomIndex, roomName, "baby", "Baby ohne start-Tabelle")
            else
                if bStart.ring ~= "outer" and bStart.ring ~= "inner" then
                    report(roomIndex, roomName, "baby", 'baby.start.ring ist nicht "outer"/"inner"')
                end
                if type(bStart.angle) ~= "number" then
                    report(roomIndex, roomName, "baby", "baby.start.angle ist keine Zahl")
                end
            end
        end

        for _, sw in ipairs(room.switches or {}) do
            local swId = sw.id or "<ohne id>"
            if switchIds[swId] then
                report(roomIndex, roomName, swId, "Schalter-ID doppelt")
            end
            switchIds[swId] = true

            if sw.id == nil or sw.ring == nil or sw.angle == nil or sw.symbol == nil
                or sw.onA == nil or sw.onB == nil or sw.state == nil then
                report(roomIndex, roomName, swId, "Schalter unvollständig (id/ring/angle/symbol/onA/onB/state)")
            end
            if sw.symbol ~= 1 and sw.symbol ~= 2 and sw.symbol ~= 3 then
                report(roomIndex, roomName, swId, "symbol ist nicht 1/2/3")
            end
            if sw.state ~= "A" and sw.state ~= "B" then
                report(roomIndex, roomName, swId, 'state ist nicht "A"/"B"')
            end
            if sw.ring ~= "outer" and sw.ring ~= "middle" and sw.ring ~= "inner" then
                report(roomIndex, roomName, swId, 'ring ist nicht "outer"/"middle"/"inner"')
            end

            -- Normierung: onA/onB dürfen einzelne IDs ODER Listen sein
            -- (Segment-Schalter, z. B. Raum 3 „Fernwirkung“: S1 onA = { D1, D2 }
            -- steuert mehrere Shutters in derselben Richtung). Leere Listen sind
            -- erlaubt (onB = {} -> in Zustand B öffnet nichts).
            local onAList = sw.onA
            if type(onAList) ~= "table" then
                onAList = (onAList ~= nil) and { onAList } or {}
            end
            local onBList = sw.onB
            if type(onBList) ~= "table" then
                onBList = (onBList ~= nil) and { onBList } or {}
            end

            -- F: onA und onB dürfen kein gemeinsames Element steuern.
            local seenB = {}
            for _, id in ipairs(onBList) do seenB[id] = true end
            for _, id in ipairs(onAList) do
                if seenB[id] then
                    report(roomIndex, roomName, swId, "onA und onB steuern dasselbe Element (" .. tostring(id) .. ")")
                end
            end

            -- A: Referenzen existieren
            for _, id in ipairs(onAList) do
                if not elements[id] then
                    report(roomIndex, roomName, id, "onA verweist auf nicht existierendes Element")
                end
            end
            for _, id in ipairs(onBList) do
                if not elements[id] then
                    report(roomIndex, roomName, id, "onB verweist auf nicht existierendes Element")
                end
            end

            -- Steuerungszählung (B/C/D/E): jede referenzierte Element-ID zählt.
            for _, id in ipairs(onAList) do controlCount[id] = (controlCount[id] or 0) + 1 end
            for _, id in ipairs(onBList) do controlCount[id] = (controlCount[id] or 0) + 1 end
        end

        -- Druckplatten (momentan): steuern genau ein Element (Blende). Der
        -- Press-Zustand ist rein positionsabhängig (Player ODER Baby im
        -- Druckbereich); die Platte selbst ist KEIN Schalter und trägt keinen
        -- Schalterzustand. Die on-Referenz zählt wie eine Schaltersteuerung
        -- zur G3-Prüfung (ein Element, genau ein Herr).
        local plateIds = {}
        for _, p in ipairs(room.plates or {}) do
            local pId = p.id or "<ohne id>"
            if plateIds[pId] then
                report(roomIndex, roomName, pId, "Platten-ID doppelt")
            end
            plateIds[pId] = true
            if switchIds[pId] or elements[pId] then
                report(roomIndex, roomName, pId, "Platten-ID kollidiert mit Schalter/Element-ID")
            end

            if p.id == nil or p.ring == nil or p.angle == nil or p.on == nil then
                report(roomIndex, roomName, pId, "Druckplatte unvollständig (id/ring/angle/on)")
            end
            if p.ring ~= nil and p.ring ~= "outer" and p.ring ~= "inner" then
                report(roomIndex, roomName, pId, 'ring ist nicht "outer"/"inner"')
            end
            if type(p.angle) ~= "number" then
                report(roomIndex, roomName, pId, "angle ist keine Zahl")
            end
            if p.on ~= nil then
                if not elements[p.on] then
                    report(roomIndex, roomName, pId, "on verweist auf nicht existierendes Element (" .. tostring(p.on) .. ")")
                elseif elements[p.on].kind ~= "shutter" and elements[p.on].kind ~= "bridge" then
                    report(roomIndex, roomName, pId, "on muss eine Blende oder Brücke sein (Druckplatte steuert genau ein Element)")
                end
                controlCount[p.on] = (controlCount[p.on] or 0) + 1
            end
        end

        -- B: kein Element von mehr als einem Herrn (Schalter oder Platte) gesteuert
        for id, count in pairs(controlCount) do
            if count > 1 then
                report(roomIndex, roomName, id, "Element wird von mehr als einem Herrn gesteuert (Schalter/Platte)")
            end
        end

        -- C/D/E: Steuerung pro Element
        for id, el in pairs(elements) do
            local controlled = controlCount[id] or 0
            if el.kind == "shutter" then
                if el.fixedClosed == true then
                    -- Feste (dauerhaft geschlossene) Blende: von keinem Herrn steuerbar.
                    if controlled ~= 0 then
                        report(roomIndex, roomName, id, "Feste Blende (fixedClosed) darf von keiner Steuerung (Schalter/Platte) gesteuert werden")
                    end
                elseif controlled ~= 1 then
                    report(roomIndex, roomName, id, "Blende wird nicht genau von einer Steuerung (Schalter/Platte) gesteuert")
                end
            elseif el.kind == "bridge" then
                if el.free == true then
                    if controlled ~= 0 then
                        report(roomIndex, roomName, id, "Freie Brücke wird von einer Steuerung (Schalter/Platte) gesteuert")
                    end
                elseif controlled ~= 1 then
                    report(roomIndex, roomName, id, "Nicht-freie Brücke wird nicht genau von einer Steuerung (Schalter/Platte) gesteuert")
                end
            elseif el.kind == "gate" then
                if el.free == true then
                    if controlled ~= 0 then
                        report(roomIndex, roomName, id, "Freies Tor wird von einem Schalter gesteuert")
                    end
                elseif controlled ~= 1 then
                    report(roomIndex, roomName, id, "Nicht-freies Tor wird nicht genau von einem Schalter gesteuert")
                end
            end
        end

        if errorCount == before then
            print("Raum " .. roomIndex .. ": OK")
        end
    end

    return errorCount
end

return Levels