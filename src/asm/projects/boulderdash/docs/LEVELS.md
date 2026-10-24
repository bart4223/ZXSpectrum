# Boulder Dash für den ZX Spectrum – Höhlen bauen

Höhlen sind Textdateien in `levels/`. Das Build-Werkzeug macht daraus die Daten im Spiel.

## Ablauf

1. Datei `levels/LevelNN.cave` anlegen oder ändern (jeder Texteditor, Nur-Text, UTF-8).
2. Bauen lassen: `python3 tools/build.py` (oder Claude bauen lassen, dann kommen `boulderdash.tap` und `boulderdash.asm` zurück).
3. Vorschau ansehen: `levels/preview/LevelNN.png`.
4. Die `.tap` auf dem Spectrum laden und spielen.

Die Reihenfolge der Dateien (nach Name sortiert) ist die Reihenfolge der Level: `Level01` ist Level 1, `Level02` Level 2 und so weiter. Nach der letzten Datei folgen Zufallshöhlen.

Zum Selbstbauen brauchst du Python 3 und pasmo (Mac: `brew install pasmo`).

## Bisher gebaute Höhlen

Alle achtzehn wurden im Emulator mit einer aufgezeichneten Lösung durchgespielt. Das beweist, dass sie lösbar sind, nicht dass sie sich gut spielen.

| Nr. | Datei | Name | Diamanten (nötig) | Zeit | Besonderheit |
|---|---|---|---|---|---|
| 1 | `Level01.cave` | Einstieg | 10 | 120 s | Erde, Steine und Diamanten, zum Kennenlernen |
| 2 | `Level02.cave` | Glühwürmchen | 13 | 150 s | Drei Räume mit Glühwürmchen, Diamanten in den Raummitten |
| 3 | `Level03.cave` | Schmetterlinge | 22 | 200 s | Steine in Schächte schieben und auf Schmetterlinge fallen lassen, dabei entstehen Diamanten |
| 4 | `Level04.cave` | Zauberwand | 18 | 220 s | Zwei Zauberwände, Steine auf Regalen werden zu Diamanten (beide teilen sich die Aktivzeit) |
| 5 | `Level05.cave` | Amöbe | 30 | 250 s | Amöbe in zwei Kammern, Bomben zum Freisprengen, eingeschlossene Amöbe wird zu Diamanten |
| 6 | `Level06.cave` | Feuerprobe | 26 | 250 s | Lavafeld, Glühwürmchen-Gang, Tresore mit Bomben |
| 7 | `Level07.cave` | Sprengmeister | 12 | 200 s | Zwei Ziegelwände, je ein Bombenpaar öffnet sie, Ausgang in der dritten Zone |
| 8 | `Level08.cave` | Kettenreaktion | 14 | 200 s | 22 Bomben in einer Reihe sprengen den Ziegeltunnel zum Ausgang |
| 9 | `Level09.cave` | Käfig | 16 | 220 s | Zwei Ziegelkammern mit Glühwürmchen, Bomben sprengen sie auf |
| 10 | `Level10.cave` | Lavasee | 17 | 230 s | Lavasee mit Erdbrücken und Inseln, Bombe öffnet den Tresor mit dem Ausgang |
| 11 | `Level11.cave` | Steinfeld | 4 | 100 s | Achteckige Erdhöhle mit 44 verstreuten Steinen und 6 Diamanten, Ausgang am unteren Rand, nachrutschende Steine sind die Gefahr |
| 12 | `Level12.cave` | Schlitz | 8 | 140 s | Erdhöhle mit langem, leerem Ziegelschlitz in der Mitte und Nische oben, Ausgang mittig rechts, 46 verstreute Steine |
| 13 | `Level13.cave` | Raute | 12 | 230 s | Große Raute mit Ziegeltreppen und weite Halle rechts, Ausgang am Ende eines langen, engen Gangs unten links mit einem Diamanten, ein Stein am Gangeingang |
| 14 | `Level14.cave` | Höhlenlabyrinth | 12 | 250 s | Langer Gang oben, Steinketten im Gelände, Steinringkammer mit Diamanten, eine Bombe, Schacht mit Diamant und Halle unten, Ausgang unten rechts |
| 15 | `Level15.cave` | Trichter | 12 | 200 s | Trichterhöhle, unten spitz, Rockford unten, Ausgang oben rechts in einem Ziegeltresor (Bombe nötig). Zwei Ziegelkäfige mit je einem Schmetterling und 4 Diamanten, nur mit Bomben zu öffnen; ohne beide Käfige reichen die Diamanten nicht. 5 Bomben, 3x3-Steinblock mit Diamant |
| 16 | `Level16.cave` | Gewundene Höhle | 18 | 255 s | Organische Höhle mit mehreren Armen, Kammer mit Glühwürmchen und Ziegelinsel, Ziegelkasten mit 3 Diamanten (Bombe nötig, sonst fehlen Diamanten), Ausgang links, 3 weitere Bomben, Steinreihen |
| 17 | `Level17.cave` | Kammern | 22 | 200 s | Quadratische Höhle voller Steine und Diamanten, sechs versiegelte Hohlräume (3 Felder breit) mit Glühwürmchen oder Schmetterlingen, an den Enden je ein Diamant, darunter je eine Bombe, die den Gegner in der Kammer erwischt; mindestens vier Kammern müssen geräumt werden |
| 18 | `Level18.cave` | Regale | 14 | 220 s | Vier lange Ziegelregale in der Mitte (man muss außen herum), vier Kammern mit Gegnern (je ein Diamant an den Enden, Bombe darunter), Bomben und freie Diamanten auf den Seiten, Ausgang oben neben dem Start; mindestens zwei Kammern müssen geräumt werden |

Vorschaubilder liegen in `levels/preview/` (`LevelNN.png` einfach, `LevelNN_voll.png` mit der echten Spielgrafik). Nach Level 18 folgen Zufallshöhlen.

## Dateiformat

```
name:   Einstieg
need:   10        ; Diamanten, bis der Ausgang aufgeht
time:   120       ; Sekunden
magic:  160       ; Zauberwand-Aktivzeit in Ticks (8 Ticks = 1 Sekunde)
amoeba: 40        ; ab so vielen Amöbenfeldern erstarrt sie zu Steinen
extra:  0         ; Diamanten, die erst im Spiel entstehen (Sprengung, Zauberwand, Amöbe)
map:
########################################
#R.....(22 Zeilen à 40 Zeichen)
########################################
```

- Alle Kopfwerte sind optional (Standard: need 10, time 150, magic 160, amoeba 40, extra 0). `time`, `magic` und `amoeba` liegen zwischen 1 und 255 (die Zeit also höchstens 255 Sekunden).
- `extra` sagt dem Werkzeug, wie viele Diamanten erst im Spiel entstehen. Es geht nur in die Prüfung ein (sichtbare + extra Diamanten müssen mindestens `need` + 2 ergeben).
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
- Der Ausgang ist von Rockford aus erreichbar (Graben und Steine schieben zählen mit; Stahl, Lava und Zauberwand sperren. Ziegel und Bomben sperren nur, wenn die Höhle keine Bombe enthält, denn mit Bomben kann man Mauern sprengen).
- Es gibt mindestens `need` + 2 Diamanten (sichtbare erreichbare plus `extra`, als Reserve).

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
