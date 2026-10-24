# Boulder Dash für den ZX Spectrum – Höhlen bauen

Höhlen sind Textdateien in `levels/`. Das Build-Werkzeug macht daraus die Daten im Spiel.

## Ablauf

1. Datei `levels/NN_name.cave` anlegen oder ändern (jeder Texteditor, Nur-Text, UTF-8).
2. Bauen lassen: `python3 tools/build.py` (oder Claude bauen lassen, dann kommen `boulderdash.tap` und `boulderdash.asm` zurück).
3. Vorschau ansehen: `levels/preview/NN_name.png`.
4. Die `.tap` auf dem Spectrum laden und spielen.

Die Reihenfolge der Dateien (nach Name sortiert) ist die Reihenfolge der Level: `01_...` ist Level 1, `02_...` Level 2 und so weiter. Nach der letzten Datei folgen Zufallshöhlen.

Zum Selbstbauen brauchst du Python 3 und pasmo (Mac: `brew install pasmo`).

## Dateiformat

```
name:   Einstieg
need:   10        ; Diamanten, bis der Ausgang aufgeht
time:   120       ; Sekunden
magic:  160       ; Zauberwand-Aktivzeit in Ticks (8 Ticks = 1 Sekunde)
amoeba: 40        ; ab so vielen Amöbenfeldern erstarrt sie zu Steinen
map:
########################################
#R.....(22 Zeilen à 40 Zeichen)
########################################
```

- Alle Kopfwerte sind optional (Standard: need 10, time 150, magic 160, amoeba 40) und liegen zwischen 1 und 255.
- Nach `;` beginnt ein Kommentar im Kopf. In der Karte gibt es keine Kommentare.
- Die Karte hat genau 22 Zeilen mit je genau 40 Zeichen.

## Zeichen

| Zeichen | Bedeutung |
|---|---|
| `#` | Stahl (unzerstörbar, Rand) |
| `W` | Ziegelmauer (Bomben sprengen sie) |
| `.` | Erde |
| ` ` (Leerzeichen) | leer |
| `o` | Stein |
| `*` | Diamant |
| `R` | Rockford (Start), genau einmal |
| `X` | Ausgang, genau einmal (sieht geschlossen wie Stahl aus) |
| `B` | Bombe (ruhend, schiebbar, fällt wie ein Stein) |
| `~` | Lava |
| `F` | Glühwürmchen |
| `S` | Schmetterling |
| `M` | Zauberwand |
| `A` | Amöbe |
| `G` | wachsende Mauer |

## Was das Werkzeug prüft

Bei einem Fehler bricht der Build mit einer Meldung ab, es entsteht keine `.tap`.

- Format: 22 Zeilen, 40 Zeichen, nur bekannte Zeichen.
- Rockford und Ausgang kommen genau einmal vor.
- Stahlrand rundherum vollständig.
- Der Ausgang ist von Rockford aus erreichbar (Graben und Steine schieben zählen mit; Ziegel, Stahl, Lava, Bomben und Zauberwand sperren).
- Es gibt mindestens `need` + 2 erreichbare Diamanten (Reserve).

Nicht geprüft werden Spielbarkeit und Schwierigkeit. Das musst du ausprobieren.

## Hinweise zum Bauen

- Ein Stein oder Diamant ohne Boden darunter fällt gleich im ersten Tick. Wenn das nicht gewollt ist, lege sie auf Erde oder Stein.
- Rockford und Gegner sollten nicht direkt nebeneinander starten.
- Die Kamera folgt Rockford, die sichtbare Fläche ist 16x11 Felder.
- Eine Bombe zündet man, indem man daneben steht und Feuer drückt (`M`, Sinclair 1: `0`, Sinclair 2: `5`). Explosion nach etwa 1,3 s, 3x3 Felder, Stahl, Ausgang und Lava bleiben.
- Lava verschluckt Steine, Diamanten und Bomben, Rockford stirbt darin.
- Zauberwand: Stein wird zu Diamant und umgekehrt, wenn darunter Platz ist. Danach wird sie zu einer normalen Mauer.
- Amöbe: eingeschlossen wird sie zu Diamanten, zu groß wird sie zu Steinen.

## Dateien

| Datei | Zweck |
|---|---|
| `boulderdash_src.asm` | Hauptquelltext (von Hand ändern) |
| `levels/*.cave` | Höhlen (von Hand ändern) |
| `tools/gen_levels.py` | Höhlen prüfen und in Assembler-Daten umwandeln |
| `tools/gen_tiles.py` | Kachelgrafik (ASCII-Zeichnungen) in Bytes umwandeln |
| `tools/build.py` | Alles zusammen bauen |
| `boulderdash.asm`, `boulderdash.tap` | erzeugt, nicht von Hand ändern |
