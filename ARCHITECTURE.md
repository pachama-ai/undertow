# ARCHITECTURE.md — Ringe (Playdate)

Diese Datei ist die verbindliche Spezifikation des Projekts. Sie liegt im Repository-Wurzelverzeichnis, damit GitHub Copilot sie als Workspace-Kontext liest.

**Regel für Copilot:** Bei Widerspruch zwischen einem Chat-Prompt und dieser Datei gilt diese Datei. Bei Unklarheit nachfragen, statt zu erfinden. Niemals Levelinhalte, Konstanten oder SDK-Funktionen erfinden.

---

## 1. Was das Spiel ist

Ein ruhiges 1-Bit-Logikspiel für die Playdate-Konsole. Der Spieler bewegt sich mit der Kurbel auf konzentrischen Ringbahnen. Auf den Bahnen liegen richtungsabhängige Schalter, die Blenden und Brücken in Gegenzuständen steuern. Ziel jedes Rätselraums ist es, die Kernbrücke auf dem inneren Ring auszufahren, zu erreichen und zu überqueren. Danach fährt die Ansicht einen Ring weiter nach innen.

Kapitel 1 besteht aus **7 Ringen (R7 außen bis R1 innen)** und damit **6 Rätselräumen**.

Es gibt keine Gegner, keinen Tod, keinen Zeitdruck, keine Punkte.

Sprache: Kommentare auf Deutsch, Bezeichner auf Englisch.

---

## 2. Systemgesetze

Diese sieben Regeln definieren das gesamte Spiel. Alle Levelinhalte müssen ihnen genügen.

**G1 — Richtungsschalter.** Ein Schalter wird gesetzt, wenn die Spielfigur seinen Mittelpunkt vollständig überquert. Überquerung **im Uhrzeigersinn** setzt Zustand **A**, **gegen den Uhrzeigersinn** setzt Zustand **B**. Ein Schalter toggelt nicht: Ist der Zielzustand bereits gesetzt, passiert nichts — kein Ton, kein Undo-Eintrag, keine Animation.

**G2 — Gegenzustandskopplung.** Jeder Schalter steuert genau zwei Elemente. In Zustand A ist `onA` aktiv und `onB` inaktiv, in Zustand B umgekehrt. „Aktiv" heißt: Brücke ausgefahren beziehungsweise Blende offen. Es gibt niemals einen Zustand, in dem beide Elemente eines Schalters aktiv oder beide inaktiv sind.

**G3 — Jedes Element hat höchstens einen Herrn.** Ein Element wird von genau einem Schalter gesteuert oder ist mit `free = true` dauerhaft aktiv. Nie von zweien.

**G4 — Schalterzustände sind frei setzbar.** *Das wichtigste Designgesetz.* Ist ein Schalter erreichbar und liegt beidseitig genügend Bahn frei, kann der Spieler ihn in jeden Zustand bringen: vorbeifahren, umkehren, aus der anderen Richtung überfahren. **Die Fahrtrichtung ist daher niemals eine Sperre.** Rätsel dürfen nicht darauf bauen, dass ein Schalter „nur aus der falschen Richtung erreichbar" ist.

**G5 — Eine Blende sperrt nichts, sie lenkt nur.** Ein Ring ist ein Kreis. Eine einzelne geschlossene Blende schneidet ihn zu einem Bogen auf; jeder Punkt bleibt erreichbar, nur die Anfahrtsseite ist festgelegt. **Um einen Punkt unerreichbar zu machen, braucht es zwei geschlossene Blenden, die zu zwei verschiedenen Schaltern gehören** (aus G2 folgt: ein Schalterpaar lässt immer eine Seite offen).

**G6 — Die eigentliche Währung ist Erreichbarkeit.** Gute Rätsel entstehen aus zwei Sätzen: *„Diesen Schalter kann ich erst erreichen, wenn …"* und *„Ich muss dorthin, ohne diesen Schalter noch einmal zu überfahren."* Die Antwort auf den zweiten Satz ist immer: der lange Weg herum oder der Umweg über den anderen Ring.

**G7 — Nichts schließt sich auf dem Spieler.** Eine Blende, die sich schließen soll, während die Figur in ihrem Bogen steht, merkt sich den Wunsch und schließt sich, sobald der Bogen frei ist. Der Schalterzustand wechselt sofort; nur Grafik und Kollision folgen verzögert. Eine Brücke, die eingezogen wird, während die Figur sie überquert, lässt die Überquerung zuerst zu Ende laufen.

---

## 3. Konventionen

**Winkel.** Immer in Grad. **0° = 12 Uhr, im Uhrzeigersinn steigend.** Das entspricht `playdate.graphics.drawArc`. Nirgends umrechnen. Normalisierung ausschließlich über `geometry.norm(a) -> [0, 360)`.

**Richtung.** `+1` = im Uhrzeigersinn (Zustand A), `-1` = gegen den Uhrzeigersinn (Zustand B).

**Ringe.** Ein Raum kennt genau zwei Ringe: `"outer"` und `"inner"`. Die Ringnummern (7 bis 1) sind reine Anzeigeinformation für Kamera und Kernwachstum.

**Zeit.** Sekunden als Fließkommazahl. `dt` wird aus der Refreshrate abgeleitet, nicht gemessen.

**Keine Magic Numbers.** Jeder Zahlenwert im Spielcode kommt aus `core/config.lua`. Jeder Levelinhalt kommt aus `data/levels.lua`.

---

## 4. Modulkarte

Abhängigkeiten dürfen ausschließlich nach unten zeigen. Ein Modul importiert nie ein Modul aus einer höheren Schicht.

```
Schicht 4  main.lua
Schicht 3  ui/          menu, transition, render, camera
Schicht 2  world/       room, player, switch, shutter, bridge, gate
Schicht 1  core/        state, undo, audio, geometry, config
Schicht 0  data/        levels
```

| Datei | Verantwortung | Darf nicht |
|---|---|---|
| `core/config.lua` | Alle Konstanten. Reine Tabelle. | Logik enthalten |
| `core/geometry.lua` | Winkelmathematik, reine Funktionen | Zeichnen, Zustand lesen |
| `core/state.lua` | Laufender Raumzustand, Ableitung der Elementzustände | Zeichnen, Eingaben lesen |
| `core/undo.lua` | Snapshot-Stack | Zeichnen |
| `core/audio.lua` | Synth-Stimmen und Auslöser | Zustand ändern |
| `world/room.lua` | Raum laden, Kollisionsdienst, Raumende | Zeichnen |
| `world/player.lua` | Eingabe, Position, Ringwechsel | Schalter auswerten |
| `world/switch.lua` | Überquerungserkennung, Zustandsänderung | Zeichnen |
| `world/shutter.lua` | Blendenanimation, Wartelogik nach G7 | Zustand setzen |
| `world/bridge.lua` | Brückenanimation, Andocken, Überquerung | Zustand setzen |
| `world/gate.lua` | Kernbrücke, Raumende auslösen | Szenenwechsel selbst durchführen |
| `ui/camera.lua` | Ringnummer → Bildschirmradius, Übergangsinterpolation | Zeichnen |
| `ui/render.lua` | Alles Zeichnen, in fester Reihenfolge | Zustand ändern |
| `ui/transition.lua` | Ringwechsel-Animation | Levelinhalte kennen |
| `ui/menu.lua` | Titel, Fortsetzen, Neu | Spiellogik |
| `main.lua` | Szenenautomat, Update-Schleife | Spiellogik enthalten |

**Rendering-Grundsatz:** Keine Sprites. Der gesamte Bildschirm wird jeden Frame neu gezeichnet. `playdate.display.setRefreshRate(50)`.

---

## 4.1 — Modul- und Laufzeitkonventionen (verbindlich)

### Modulladen

- Playdate-Projektmodule werden mit `import "pfad/modul"` geladen.
- Pfade verwenden ausschließlich Slash-Notation `/`.
- `require` wird im Projekt nicht verwendet.
- Der Rückgabewert von `import` wird nicht ausgewertet.
- Jede Moduldatei erzeugt genau eine globale PascalCase-Tabelle (z. B. `core/geometry.lua` → `Geometry`, `core/state.lua` → `State`, `world/player.lua` → `Player`).
- Alle Projekt-Imports stehen ausschließlich in `main.lua`.
- Die Importreihenfolge läuft von Schicht 0 bis Schicht 4 (siehe Modulkarte).
- Abhängige Dateien dürfen globale Module am Dateianfang lokal zwischenspeichern, z. B. `local geo <const> = Geometry`.
- Deshalb darf die Importreihenfolge in `main.lua` nicht beliebig verändert werden.

### pdc-Buildregel

> Das Ausgabeverzeichnis von `pdc` darf niemals innerhalb des Quellverzeichnisses liegen. Andernfalls kann sich ein erzeugtes `.pdx` bei späteren Builds rekursiv selbst einbetten.

### Bewegungssweep

Spielerbewegung wird NICHT nach dem Muster „gesamte Bewegung clampen → danach Schalter auswerten" implementiert. Stattdessen wird die gewünschte Winkelbewegung chronologisch als **Sweep über Ereignisse** verarbeitet:

```
gewünschtes Delta
↓
nächstes Ereignis auf dem tatsächlich zurückgelegten Weg bestimmen
↓
bis zu diesem Ereignis bewegen
↓
Ereignis anwenden
↓
Weltzustand neu ableiten
↓
Restbewegung mit neuem Weltzustand fortsetzen
```

Relevante Ereignisse sind insbesondere: Schalterüberquerungen und geschlossene Blendenkanten.

**Zusammenhang mit Levelinvariante:** Die Sweep-Reihenfolge ist eindeutig, weil der Levelvalidator einen Mindestwinkelabstand zwischen allen relevanten Objekten auf demselben Ring erzwingt. Ein Schalter und eine Blendenkante dürfen niemals exakt auf demselben Winkel liegen. Diese Invariante darf nicht gelockert werden, ohne die Sweep-Semantik neu zu definieren. Der konkrete Mindestwinkelwert wird erst festgelegt, wenn er verbindlich in der Spezifikation steht.

### G7-Ausnahme im Sweep

> Eine Blende darf sich niemals auf der Spielfigur schließen.

Wenn ein Schalter während eines Sweeps eine Blende schließen möchte und die Spielfigur sich zu diesem Zeitpunkt bereits innerhalb ihres Bogens befindet:

- Schalterzustand ändert sich sofort.
- Gewünschter Blendenzustand wird gespeichert.
- Kollision wird noch nicht aktiviert.
- Die Figur darf den Bogen verlassen.
- Erst danach darf die Blende physisch schließen.

Daraus folgt für den Sweep: Eine Bewegung endet an einer Blendenkante nur dann, wenn diese Blende für die Figur zu diesem Zeitpunkt tatsächlich kollisionsaktiv geschlossen ist. Eine wegen G7 noch ausstehende Schließung stoppt die Figur nicht.

### Undo pro Frame

> Pro Frame darf höchstens ein Undo-Snapshot entstehen.

Wenn ein Sweep innerhalb desselben Frames mehrere Schalter überquert:

- beim ersten zustandsändernden Ereignis wird genau ein Snapshot angelegt,
- dieser enthält Weltzustand und Spielerposition vom Beginn des Frames,
- weitere Schalterereignisse desselben Frames erzeugen keinen weiteren Undo-Eintrag.

Damit entspricht `1 × B` immer genau einer wahrgenommenen Spielerhandlung.

### Bewegungstests

Für die spätere Sweep-Implementierung (Phase 5) werden eigene Tests unter `tests/movement_tests.lua` angelegt. Mindestens diese Fälle werden dort geprüft:

- **Fall 1 – Schalter öffnet kommende Blende:** Ein Schalter öffnet eine Blende 20° weiter vorne im selben Sweep. Erwartung: Figur fährt durch die nun offene Blende.
- **Fall 2 – Schalter schließt kommende Blende:** Ein Schalter schließt eine Blende 20° weiter vorne. Erwartung: Figur stoppt an der kollisionsaktiven Blendenkante.
- **Fall 3 – G7:** Ein Schalter schließt eine Blende, in deren Bogen sich die Figur beim Schalten bereits befindet. Erwartung: Schließung verzögert, Figur darf den Bogen verlassen, Sweep stoppt dort nicht.
- **Fall 4 – zwei Schalter in einem Frame:** Ein Delta überfährt zwei zustandsändernde Schalter. Erwartung: beide chronologisch verarbeitet, genau ein Undo-Snapshot.
- **Fall 5 – mehrere Umrundungen:** `delta = +720°` überstreicht denselben Schalter mehrfach. Erwartung: eine relevante Zustandssetzung, kein Toggle, kein mehrfacher Undo-Eintrag.

---

## 5. Konstanten (`core/config.lua`)

```lua
return {
  -- Bildschirm
  cx = 200, cy = 120,
  radiusOuter = 104,      -- Bildschirmradius des äußeren sichtbaren Rings
  radiusInner = 68,       -- Bildschirmradius des inneren sichtbaren Rings
  radiusCore  = 30,       -- Grundradius des Kerns in Raum 1
  coreGrowth  = 6,        -- Zuwachs des Kernradius pro Raum

  -- Maße
  trackWidth   = 8,       -- Bandbreite der Bahn
  playerSize   = 7,
  bridgeWidth  = 6,
  stubLength   = 5,       -- sichtbarer Stummel einer eingefahrenen Brücke

  -- Bögen in Grad
  shutterArc = 26,
  switchArc  = 14,
  dockRange  = 6,         -- Andockbereich für Brücke und Kernbrücke
  snapRange  = 4,         -- sanftes Ausrichten ohne Eingabe

  -- Bewegung
  crankRatio  = 0.5,      -- Ringgrad je Kurbelgrad. Eine Umdrehung = 180 Grad Bahn.
  dpadSpeed   = 90,       -- Grad je Sekunde

  -- Zeiten in Sekunden
  shutterTime    = 0.20,
  bridgeTime     = 0.25,
  crossTime      = 0.35,  -- Brückenüberquerung, währenddessen keine Eingabe
  cameraTime     = 1.20,
  holdToRestart  = 0.60,

  -- Vorschau
  previewRange   = 20,    -- Grad
  previewEnabled = true,  -- zum Vergleich im Playtest abschaltbar
}
```

`crankRatio` ist der wichtigste einzelne Wert des Projekts. Er entscheidet über das Spielgefühl und wird als Erstes im Playtest justiert.

---

## 6. Datenvertrag (`data/levels.lua`)

`data/levels.lua` gibt eine Liste von Räumen zurück. Keine Funktionen, keine Berechnungen, keine Verweise auf andere Module. Reine Daten.

```lua
-- Ein Raum:
-- {
--   name    = <string>,                        -- nur für Konsole und Debug
--   rings   = { outer = <int>, inner = <int> },-- Ringnummern 7..1
--   start   = { ring = "outer"|"inner", angle = <grad> },
--
--   switches = {
--     { id     = <string>,                     -- eindeutig im Raum
--       ring   = "outer"|"inner",
--       angle  = <grad>,
--       symbol = 1|2|3,                        -- 1 Punkt, 2 zwei Punkte, 3 Strich
--       onA    = <id>,                         -- aktiv in Zustand A
--       onB    = <id>,                         -- aktiv in Zustand B
--       state  = "A"|"B" },                    -- Startzustand
--   },
--
--   shutters = {
--     { id = <string>, ring = "outer"|"inner", angle = <grad> },
--   },
--
--   bridges = {                                -- verbindet outer und inner
--     { id = <string>, angle = <grad>, free = <bool> },
--   },
--
--   gate = { id = "T", angle = <grad>, free = <bool> },  -- Kernbrücke, sitzt auf inner
-- }
```

**Zur Kernbrücke.** Sie ist eine Brücke mit besonderer Grafik: Sie sitzt auf dem inneren Ring und zeigt nach innen. Wer bei ausgefahrener Kernbrücke innerhalb von `dockRange` um ihren Winkel auf dem inneren Ring steht und A drückt, beendet den Raum. Sie wird wie jede Brücke von einem Schalter gesteuert, es sei denn `free = true`.

**Symbolzuordnung.** Ein Schalter und seine beiden gesteuerten Elemente tragen dasselbe Symbol. Pro Raum höchstens drei Symbole.

---

## 7. Die sechs Räume

Alle sechs Räume sind von Hand gegen die Systemgesetze verifiziert. Die Lösungswege in Abschnitt 8 sind nachgerechnet. **Diese Daten nicht verändern, ohne den Validator aus Abschnitt 12 laufen zu lassen.**

```lua
-- data/levels.lua
return {

  -------------------------------------------------------------------- 1
  {
    name  = "Ein Anlauf",
    rings = { outer = 7, inner = 6 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="B" },
    },
    shutters = {
      { id="D1", ring="outer", angle=315 },
    },
    bridges = {
      { id="B1", angle=270, free=false },
    },
    gate = { id="T", angle=180, free=true },
  },

  -------------------------------------------------------------------- 2
  {
    name  = "Die ganze Runde",
    rings = { outer = 6, inner = 5 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=45,  symbol=1, onA="B1", onB="D1", state="B" },
      { id="S2", ring="outer", angle=315, symbol=2, onA="T",  onB="D2", state="B" },
    },
    shutters = {
      { id="D1", ring="inner", angle=225 },
      { id="D2", ring="inner", angle=90  },
    },
    bridges = {
      { id="B1", angle=135, free=false },
    },
    gate = { id="T", angle=180, free=false },
  },

  -------------------------------------------------------------------- 3
  {
    name  = "Der lange Weg",
    rings = { outer = 5, inner = 4 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=45, symbol=1, onA="T", onB="D1", state="B" },
    },
    shutters = {
      { id="D1", ring="inner", angle=315 },
    },
    bridges = {
      { id="B0", angle=270, free=true },
    },
    gate = { id="T", angle=0, free=false },
  },

  -------------------------------------------------------------------- 4
  {
    name  = "Der Umbau",
    rings = { outer = 4, inner = 3 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=45,  symbol=1, onA="T",  onB="D1", state="B" },
      { id="S2", ring="inner", angle=135, symbol=2, onA="D2", onB="B2", state="B" },
    },
    shutters = {
      { id="D1", ring="inner", angle=315 },
      { id="D2", ring="inner", angle=45  },
    },
    bridges = {
      { id="B0", angle=90,  free=true  },
      { id="B2", angle=180, free=false },
    },
    gate = { id="T", angle=0, free=false },
  },

  -------------------------------------------------------------------- 5
  {
    name  = "Fernwirkung",
    rings = { outer = 3, inner = 2 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=270, symbol=1, onA="T",  onB="D2", state="B" },
      { id="S2", ring="inner", angle=180, symbol=2, onA="D1", onB="B1", state="B" },
    },
    shutters = {
      { id="D1", ring="outer", angle=180 },
      { id="D2", ring="inner", angle=315 },
    },
    bridges = {
      { id="B0", angle=90,  free=true },
      { id="B1", angle=225, free=false },
    },
    gate = { id="T", angle=0, free=false },
  },

  -------------------------------------------------------------------- 6
  {
    name  = "Die Umkehr",
    rings = { outer = 2, inner = 1 },
    start = { ring = "outer", angle = 0 },
    switches = {
      { id="S1", ring="outer", angle=180, symbol=1, onA="B1", onB="D2", state="A" },
      { id="S2", ring="inner", angle=90,  symbol=2, onA="D1", onB="T",  state="A" },
    },
    shutters = {
      { id="D1", ring="outer", angle=270 },
      { id="D2", ring="inner", angle=315 },
    },
    bridges = {
      { id="B0", angle=45,  free=true },
      { id="B1", angle=135, free=false },
    },
    gate = { id="T", angle=0, free=false },
  },

}
```

---

## 8. Verifizierte Lösungswege

Diese Wege dienen als Testfälle. Der Validator muss für jeden Raum mindestens diesen Weg finden.

**Raum 1 — Ein Anlauf.** Startzustand B: B1 eingefahren, D1 offen. Im Uhrzeigersinn 0° → 90°: S1 setzt A, B1 fährt aus, D1 schließt sich (harmlos, hinter dem Spieler). Weiter im Uhrzeigersinn bis 270°, A drücken, hinunter auf den inneren Ring bei 270°. Gegen den Uhrzeigersinn bis 180° zur dauerhaft ausgefahrenen Kernbrücke. A.

*Lehre:* Richtung setzt Zustand. Jeder Schalter schließt immer auch etwas. Kosten: keine.

**Raum 2 — Die ganze Runde.** Zwei gültige Wege.

*Lang:* Im Uhrzeigersinn über S1 (45°) — B1 fährt aus, D1 schließt. Weiter über 135° hinweg bis S2 (315°) — T fährt aus, D2 schließt. Weiter im Uhrzeigersinn über 0° und erneut über S1 (**nichts passiert**, Zustand schon A) bis 135°. Hinunter. Innen im Uhrzeigersinn 135° → 180°. A.

*Kurz:* Gegen den Uhrzeigersinn 0° → 315° (S2 setzt B, war schon B, nichts passiert) → 270°. Umkehren, im Uhrzeigersinn zurück über S2 → A. Dann über S1 → A, hinunter bei 135°, innen zum Tor.

Beide Wege sind erwünscht. Der kurze Weg ist die erste Begegnung mit Systemgesetz G4 und wird von aufmerksamen Spielern gefunden.

**Raum 3 — Der lange Weg.** Über S1 (45°) im Uhrzeigersinn: T fährt aus, D1 schließt sich bei innen 315°, direkt neben dem Tor bei 0°. Beide Ringe sind sichtbar, der Spieler sieht die Sperre entstehen. Weiter im Uhrzeigersinn bis 270°, hinunter über B0, dann innen **gegen** den Uhrzeigersinn 270° → 225° → 180° → 135° → 90° → 45° → 0°. A.

Der Rückweg über S1 ist keine Option: Er nimmt die Kernbrücke wieder weg.

**Raum 4 — Der Umbau.** Reihenfolge ist erzwungen: S2 muss vor S1 gesetzt werden.

1. Außen im Uhrzeigersinn 0° → 90° (S1 bei 45° wird dabei überquert und setzt A — **falsch**). Korrekt: außen **gegen** den Uhrzeigersinn 0° → 315° → … → 90°, dabei wird S1 nicht berührt. Hinunter über B0.
2. Innen im Uhrzeigersinn 90° → 135°: S2 setzt A, D2 (innen 45°) öffnet sich, B2 (180°) fährt ein.
3. Rückweg über S2 verboten (setzt B, D2 schließt wieder). Also innen **im Uhrzeigersinn einmal ganz herum**: 135° → 180° → 225° → 270° → 315° (D1 noch offen, weil S1 auf B steht) → 0° → 45° (D2 jetzt offen) → 90°. Hinauf über B0.
4. Außen gegen den Uhrzeigersinn 90° → 45° (S1 setzt B, war schon B) → 0°, umkehren, im Uhrzeigersinn 0° → 45°: S1 setzt A. T fährt aus, D1 schließt sich.
5. Weiter im Uhrzeigersinn 45° → 90°, hinunter, innen gegen den Uhrzeigersinn 90° → 45° (offen) → 0°. A.

*Fallen:* Wer zuerst S1 setzt, schließt D1 und sitzt innen zwischen S2 und der geschlossenen D1 fest — nicht tödlich, aber eine verlorene Runde. B2 ist ein Köder: ein zweiter Abstieg, der genau dann verschwindet, wenn man ihn bräuchte.

**Raum 5 — Fernwirkung.** Startzustand: D1 (außen 135°) und D2 (außen 225°) sind **beide** geschlossen. S1 bei außen 180° liegt zwischen ihnen und ist unerreichbar. Zwei verschiedene Schalter, beide auf dem inneren Ring, müssen ihn freilegen — das ist Systemgesetz G5 in Reinform.

1. Außen im Uhrzeigersinn 0° → 45°, hinunter über B0 (dauerhaft).
2. Innen im Uhrzeigersinn 45° → 90°: S2 setzt A. D1 (außen 135°) öffnet sich, B1 (202,5°) fährt ein.
3. Weiter im Uhrzeigersinn 90° → 135° (D5 noch offen) → 180° → 202,5° → 225° → 270°: S3 setzt A. D2 (außen 225°) öffnet sich, D5 (innen 135°) schließt sich hinter dem Spieler.
4. Weiter im Uhrzeigersinn 270° → 315° (D3 offen) → 0° (Tor noch eingefahren) → 45°. Hinauf über B0.
5. Außen im Uhrzeigersinn 45° → 90° → 135° (jetzt offen) → 180°: S1 setzt A. T fährt aus, D3 (innen 315°) schließt sich.
6. Umkehren verboten (nimmt das Tor zurück). Also außen weiter im Uhrzeigersinn 180° → 225° (offen) → 270° → 315° → 0° → 45°. Hinunter, innen gegen den Uhrzeigersinn 45° → 0°. A.

*Köder:* B1 bei 202,5° führt in den abgeriegelten äußeren Bogen. Wer ihn früh nutzt, landet neben S1 auf der falschen Seite und kann ihn nur gegen den Uhrzeigersinn überqueren — also wirkungslos. Sobald S2 gesetzt wird, verschwindet der Köder.

**Raum 6 — Die Umkehr.** Der kürzeste Raum des Levels.

Beide Schalter starten in Zustand **A**. Das Tor ist an `onB` von S1 gekoppelt, fährt also nur aus, wenn S1 **gegen** den Uhrzeigersinn überquert wird.

1. Außen im Uhrzeigersinn 0° → 45°, hinunter über B0.
2. Innen im Uhrzeigersinn 45° → 90°: S1 wird überquert, setzt A — **nichts passiert**. Der Spieler fährt weiter und findet bei 135° die geschlossene D2.
3. Umkehren. Innen gegen den Uhrzeigersinn zurück über S1: setzt B. T fährt aus, D1 (315°) schließt sich.
4. Weiter gegen den Uhrzeigersinn 90° → 45° → 0°. A.

*Köder:* Der äußere Ring bietet einen zweiten Abstieg bei 270° an. Wer ihn nimmt, läuft innen gegen die geschlossene D2 und muss dieselbe Erkenntnis auf dem langen Weg machen.

*Warum das das Finale ist:* Fünf Räume lang trainiert das Spiel das Fahren im Uhrzeigersinn. Der letzte Raum verlangt, an einem Schalter vorbeizufahren, das Ausbleiben der Wirkung zu bemerken und zurückzukommen.

**Nach Raum 6:** R1 löst sich auf, der Kern füllt den Bildschirm, die Iris öffnet sich einen Spalt, dahinter ist ein weiterer Ring erkennbar. Schnitt zum Titel. Kein Text.

---

## 9. Zustand und Undo

**`core/state.lua`** hält:

```lua
{
  roomIndex, 
  switches = { [id] = "A"|"B" },
  elements = { [id] = true|false },   -- abgeleitet, nie direkt gesetzt
  player   = { ring = "outer"|"inner", angle = <grad>, facing = 1|-1 },
}
```

`deriveElements()` berechnet `elements` vollständig neu aus `switches` und den `free`-Flags. Es wird nach jeder Schalteränderung aufgerufen und gibt die Liste der geänderten Element-IDs zurück, damit Animationen und Töne ausgelöst werden können.

`elements` wird niemals von Hand gesetzt. Das ist die einzige Stelle, an der Zustandskonsistenz garantiert wird.

**`core/undo.lua`** ist ein Stack von Snapshots, maximal 64 Einträge.

> **Wichtig:** Der Snapshot wird **vor** der Schalteränderung gepusht und enthält die Spielerposition **vor** der Überquerung, nicht danach. Sonst steht die Figur nach dem Undo genau auf dem Schalter und löst ihn beim nächsten Kurbelzucken erneut aus.

Ein Undo stellt Schalterzustände, abgeleitete Elemente und Spielerposition wieder her, setzt alle Animationen sofort auf ihren Endzustand und spielt einen kurzen Rückwärtston.

---

## 10. Eingabe und Bewegung

| Eingabe | Wirkung |
|---|---|
| Kurbel | Bewegung. `getCrankChange() * config.crankRatio` = Winkeländerung |
| D-Pad links/rechts | Bewegung mit `config.dpadSpeed`, vollwertige Alternative |
| A | Erreichbare Brücke oder Kernbrücke überqueren |
| B kurz | Letzte Zustandsänderung rückgängig |
| B halten (0,6 s) | Raum neu starten, mit einem sich schließenden Ring als Fortschrittsanzeige |
| Systemmenü | „Raum neu starten", „Zum Menü" |

Ist die Kurbel eingeklappt, erscheint ein dezenter Hinweis. Das Spiel bleibt mit dem D-Pad vollständig spielbar — das ist eine Barrierefreiheitsentscheidung, keine Notlösung.

**Bewegungsablauf pro Frame:**

1. Gewünschte Winkeländerung aus Kurbel und D-Pad bestimmen.
2. `room.maxTravel(ring, fromAngle, delta)` fragen: Wo stoppt die erste geschlossene Blende?
3. Position setzen. Figur wird an der Blendenkante gestoppt, nie hineingelassen.
4. `switch.evaluate(prevAngle, newAngle, ring)` aufrufen.
5. Sanftes Ausrichten, wenn keine Eingabe anliegt und ein Schalter oder Brückenkopf innerhalb von `snapRange` liegt.

**Tunneling.** `maxTravel` und `geometry.crossed` müssen mit Winkeländerungen größer als die Blenden- beziehungsweise Schalterbreite in einem einzigen Frame korrekt umgehen. Bei sehr schneller Kurbelbewegung sind 40° pro Frame möglich. Die Überquerungsprüfung darf nicht auf Punktkollision beruhen, sondern muss den überstrichenen Bogen prüfen — inklusive Überquerung der 0°-Grenze in beide Richtungen. **Das ist die häufigste Fehlerquelle des Projekts.**

---

## 11. Rendering

**Farbregel:** Hintergrund schwarz. Die Bahn ist weiß. Wo die weiße Fläche fehlt, kommt man nicht durch.

**Zeichenreihenfolge in `ui/render.lua`.** Keine Abweichung.

1. `gfx.clear(gfx.kColorBlack)`
2. Geisterringe der abgeschlossenen Räume: 1 px weiße Kreislinien außerhalb von `radiusOuter`, teilweise vom Bildrand geschnitten. Fortschrittsanzeige ohne HUD.
3. Kern: gefüllter Kreis mit Dithermuster, Radius `radiusCore + coreGrowth * (roomIndex - 1)`, langsame Pulsation.
4. Bahnen: weiße Bögen, `setLineWidth(config.trackWidth)`, für beide sichtbaren Ringe. Danach Linienbreite zurücksetzen.
5. Blenden: geschlossen als schwarzer Bogen mit 1 px weißer Kontur und zwei weißen Zähnen an den Enden. Offen als weißer Bogen mit zwei kleinen Randmarken. Die Animation läuft quer zur Bahn als Irisbewegung, nicht als Schiebetür.
6. Brücken: radiale weiße Balken, `bridgeWidth`. Eingefahren als zwei Stummel von `stubLength` an beiden Ringen. Das Ausfahren läuft in drei sichtbaren Stufen, mechanisch ruckartig.
7. Kernbrücke: wie eine Brücke, aber vom inneren Ring nach innen gerichtet, mit einer Irisspitze am Ende.
8. Schalter: weiße Scheibe von 11 px, innen schwarz, Symbol schwarz, zwei tangentiale Pfeilspitzen am Rand. Die aktive Marke ist gefüllt, die inaktive nur konturiert.
9. Elementmarken: dasselbe Symbol klein und schwarz auf jeder gesteuerten Blende und Brücke.
10. Spieler: weiße Scheibe von 7 px, 1 px schwarze Kontur, schwarzes Auge von 3 px, in Bewegungsrichtung verschoben.

**Vorschau.** Ist der Spieler weniger als `previewRange` Grad von einem Schalter entfernt, blinken die von diesem Schalter gesteuerten Elemente einmal pro Sekunde mit einer 1 px starken Aufhellung ihrer Kontur. Über `previewEnabled` abschaltbar, um im Playtest zu vergleichen, ob die Vorschau hilft oder die Lösung verrät.

**Augenanimation.** Blick in Bewegungsrichtung. Blinzeln alle 3 bis 6 Sekunden im Stillstand. Kurzes Weiten bei Schalterkontakt. Zusammenkneifen über 6 Frames beim Anstoßen an eine Blende. Streckung zur Ellipse beim Überqueren einer Brücke.

**Kamera und Übergang.** `ui/camera.lua` bildet die beiden sichtbaren Ringnummern auf feste Bildschirmradien ab. Beim Raumwechsel läuft über `cameraTime` eine Interpolation: Der bisherige innere Ring wandert von `radiusInner` nach `radiusOuter`, der alte äußere Ring läuft aus dem Bild und wird zum Geisterring, ein neuer innerer Ring fährt bei `radiusInner` ein, der Kern wächst. Easing langsam am Anfang und am Ende.

---

## 12. Invarianten und Validator

Diese Prüfungen laufen beim Laden jedes Raums im Simulator und melden Fehler in der Konsole.

**Datenintegrität**

- Jede in `onA` oder `onB` genannte ID existiert als Blende, Brücke oder Kernbrücke.
- Jedes Element mit `free = false` wird von **genau einem** Schalter gesteuert.
- Kein Element wird von zwei Schaltern gesteuert (G3).
- `onA ~= onB` für jeden Schalter.
- Alle IDs sind im Raum eindeutig.
- Höchstens drei verschiedene Symbole pro Raum.

**Geometrie**

- Zwischen zwei Objekten auf demselben Ring beträgt der Winkelabstand mindestens die Summe ihrer halben Bögen plus 6° Rand. Ein Schalter darf niemals im Bogen einer Blende liegen.
- Eine Brücke belegt denselben Winkel auf **beiden** Ringen. Die Prüfung muss beide Ringe berücksichtigen.
- Die Kernbrücke belegt einen Winkel auf dem inneren Ring.
- Die Startposition liegt nicht im Bogen einer im Startzustand geschlossenen Blende.

**Lösbarkeit (`tools/solver.py`)**

Breitensuche über Zustände `(ring, winkelindex auf 24er-Raster, tupel aller schalterzustände)`. Übergänge: ein Rasterschritt in eine Richtung, sofern keine geschlossene Blende im Weg liegt, dabei gegebenenfalls Schalter setzen; Brückenwechsel bei ausgefahrener Brücke. Ziel: Torposition auf dem inneren Ring bei ausgefahrener Kernbrücke.

Zielwerte für jeden Raum:

| Kennzahl | Sollbereich | Bedeutung bei Verletzung |
|---|---|---|
| lösbar | immer wahr | Raum kaputt |
| minimale Schritte | 30 bis 120 | darunter leer, darüber wird gefahren statt gedacht |
| Anzahl Lösungen bis 1,5× Minimum | unter 20 | darüber ist der Raum beliebig |
| Sackgassenzustände | über 0, unter 15 % | ohne sie keine Konsequenz, zu viele frustrieren |

**Kein Softlock.** Der Solver muss zusätzlich prüfen: Aus keinem erreichbaren Zustand darf das Ziel dauerhaft unerreichbar werden, ohne dass der Spieler Undo braucht. Sackgassen sind erlaubt, echte Sackgassen ohne Rückweg nicht.

---

## 13. Ton

Alles über `playdate.sound.synth`. Keine Samples, keine Musikdateien.

| Ereignis | Stimme |
|---|---|
| Bewegung | sehr kurzer Rauschimpuls, alle 15° Bahnbewegung, Lautstärke 0,15 |
| Schalter rastet ein | kurze Rechteckwelle, zwei Halbtöne absteigend |
| Brücke fährt aus | Sägezahn mit Glide aufwärts, 0,25 s |
| Aufprall an Blende | tiefer Sinus mit schnellem Abfall |
| Kernbrücke überquert | langer tiefer Puls |
| Undo | derselbe Schalterton, rückwärts in der Tonhöhe |
| Kernpuls | Sinus 55 Hz, alle 4 s, sehr leise, pro Raum eine Terz höher |

Der Kernpuls ist die Musik. Kein weiteres Musiksystem im Prototyp.

Ein Schalter, der nichts bewirkt (G1), macht **keinen** Ton. Das Ausbleiben des Tons ist die Rückmeldung.

---

## 14. Szenenautomat

```
menu  --„Weiter"/„Neu"-->  room  --Kernbrücke überquert-->  transition
                            ^                                    |
                            +--------- neuer Raum geladen --------+
room  --Systemmenü „Zum Menü"-->  menu
transition nach Raum 6  -->  outro  -->  menu
```

Fortschritt wird über `playdate.datastore` gespeichert: nur die höchste erreichte Raumnummer. Beim Start wird sie gelesen. Kein Speichern des Raumzustands innerhalb eines Raums — ein Raum ist kurz genug.

---

## 15. Bekannte Fallstricke

1. **0°-Grenze.** Jede Winkeloperation muss die Überquerung von 359° nach 1° und umgekehrt korrekt behandeln. `geometry.crossed` mit Randfällen testen, bevor irgendetwas anderes gebaut wird.
2. **Tunneling.** Siehe Abschnitt 10.
3. **Stehenbleiben auf dem Schalter.** Wer auf dem Schalter anhält und umkehrt, darf ihn nicht auslösen. Ausgelöst wird nur bei vollständiger Überquerung des Mittelpunkts.
4. **Undo-Position.** Siehe Abschnitt 9.
5. **Blende schließt auf Figur.** G7. Betrifft auch das Wesen in späteren Kapiteln.
6. **Brücke fährt ein während der Überquerung.** Überquerung zu Ende laufen lassen, dann einfahren.
7. **Simulator lügt.** Kurbelgefühl und Kontrast müssen auf echter Hardware geprüft werden, bevor irgendein Wert festgeschrieben wird.

---

## 16. Umfang von Kapitel 1

**Enthalten:** 6 Räume, 7 Ringe, Kurbel- und D-Pad-Steuerung, Undo, Neustart, Speicherstand, Menü, Systemmenü, Ringwechsel-Animation, Synth-Ton, Launcher-Assets.

**Nicht enthalten und bewusst nicht zu bauen:** das Wesen, Taktmarken, Druckplatten, Kapitel 2 und höher, Einstellungsmenü, Erfolge, Hinweissystem, Text jeglicher Art im Spiel außer dem Titel, mehr als drei Symbole, mehr als zwei sichtbare Ringe gleichzeitig.

Das Wesen kommt in Kapitel 2. Der Datenvertrag ist so gebaut, dass es als eigene Liste `creature = { ring = "inner", angle = …, marks = { … } }` ergänzt werden kann, ohne Bestehendes zu ändern.

---

## 17. Änderungshistorie dieser Spezifikation

**v0.2** — Systemgesetz G4 formuliert („Schalterzustände sind frei setzbar"). Daraufhin Raum 5 vollständig neu gebaut: Er war ohne den inneren Ring lösbar, weil eine einzelne Blende einen Schalter nicht abriegeln kann. Raum 6 neu gebaut, um die Umkehr-Pointe an gekoppelte Startzustände statt an eine Richtungssperre zu binden. Die „Schleuse" als Abschnitt auf dem inneren Ring wurde durch die **Kernbrücke** ersetzt — sie ist eine gewöhnliche Brücke und braucht keine Sonderregel.

**v0.1** — Erste Fassung, sechs Räume, Datenvertrag, Modulkarte.
