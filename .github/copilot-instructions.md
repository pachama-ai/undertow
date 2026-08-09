# Projekt: Ringe (Playdate)

Ein 1-Bit-Logikspiel. Lua, Playdate SDK. Kein Framework, keine externen Libs.

## Harte Regeln
- Nur Playdate SDK Lua. Keine erfundenen Funktionen. Im Zweifel nachfragen statt raten.
- Keine Sprites. Der gesamte Bildschirm wird jeden Frame neu gezeichnet.
- Winkel immer in Grad, 0 = 12 Uhr, im Uhrzeigersinn steigend. Das entspricht
  playdate.graphics.drawArc. Nirgends umrechnen.
- Alle Winkel werden mit einer einzigen Funktion normalisiert: Geometry.norm(a) -> [0,360)
- Keine Physik, keine Trägheit. Position ist ein Winkel, Bewegung ist eine Winkeländerung.
- Keine Magic Numbers im Spielcode. Alle Werte in core/config.lua.
- Levelinhalte stehen ausschließlich in data/levels.lua. Nie im Code.
- Jede Zustandsänderung der Welt geht über core/state.lua, damit Undo funktioniert.
- Deutsch für Kommentare, Englisch für Bezeichner.
- Projektmodule ausschließlich mit `import "core/geometry"` in Slash-Notation laden.
  `require` nicht für Projektmodule verwenden.
- Alle Projekt-Imports stehen ausschließlich in `main.lua`.
- Jede Moduldatei legt genau eine globale PascalCase-Tabelle an; der Rückgabewert
  von `import` wird nicht ausgewertet.
- Die Importreihenfolge in `main.lua` folgt strikt den Schichten aus ARCHITECTURE.md.
- Das pdc-Ausgabeverzeichnis darf niemals innerhalb des Quellverzeichnisses liegen.
- Spielerbewegung wird chronologisch als Sweep über Schalter und Kollisionen
  verarbeitet; niemals erst komplett clampen und danach Schalter auswerten.
- Pro Frame höchstens ein Undo-Snapshot, auch wenn der Sweep mehrere Schalter auslöst.

## Rendering
- Hintergrund schwarz. Bahnen weiß. Blockiert = schwarz mit weißer Kontur.
- gfx.setLineWidth vor drawArc setzen, danach zurücksetzen.
- 50 fps: playdate.display.setRefreshRate(50)

## Antwortstil
- Immer nur eine Datei pro Antwort.
- Keine Beispiel- oder Platzhalterdaten erfinden.
- Wenn eine SDK-Funktion unsicher ist: Kommentar `-- TODO SDK prüfen` setzen.