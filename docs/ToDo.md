# Common
- ...

# Games
- Pacman
- Super Mario

# XBlast

Ziel: Ein Bomberman-artiges Spiel für zwei Spieler in Z80-Assembler, in Stufen aufgebaut wie bei Boulder Dash. Jede Stufe ist lauffähig und wird einzeln getestet.

- **Artefakte:** `xblast.asm` und `xblast.tap`
- **Assembler:** pasmo (48K) – sjasmplus erst in Stufe 7 für die 128K-Fassung
- **Steuerung:** Sinclair IF2, Joystick 1 und 2 (je Richtung + Feuer = Bombe legen)
- **Test:** Retro The Spectrum, TAP vom USB-Stick

---

## Grundentscheidungen

| Thema | Vorschlag |
|---|---|
| Kachelgröße | 16x16 Pixel (wie bei Boulder Dash), also 2x2 Zeichenzellen |
| Spielfeld | 15 x 11 Kacheln = 240 x 176 Pixel, passt ohne Scrolling auf den Bildschirm |
| Seitenleiste / Kopfzeile | Restplatz für Punkte, Rundenstand, Zeit |
| Spielfeld-Daten | 1 Byte pro Kachel in einem Array (165 Bytes), getrennt von der Darstellung |
| Spielschleife | feste Tick-Rate über HALT (50 Hz), Logik jeden n-ten Frame |
| Zeichnen | nur geänderte Kacheln neu zeichnen (Dirty-Flags), kein Vollbild-Redraw |
| Farben | eine Attributfarbe pro Kachel, passend zu den 2x2 Zellen |

### Kachel-Typen (Byte im Spielfeld)

| Wert | Bedeutung |
|---|---|
| 0 | leer |
| 1 | feste Wand (unzerstörbar) |
| 2 | Block (zerstörbar) |
| 3 | Bombe |
| 4 | Flamme |
| 5+ | Power-Ups (Reichweite, Bombenanzahl, Tempo) |

Spieler und Gegner liegen nicht im Feld, sondern in eigenen Strukturen (Position, Richtung, Zustand), damit Bewegung unabhängig vom Raster laufen kann.

---

## Stufe 0 – Gerüst und Spielfeld

- Bildschirm löschen, Raster mit festen Wänden (jede zweite Kachel in Zeile und Spalte, Rand außen) zeichnen
- Zufällig Blöcke verteilen, die Startecken bleiben frei (je ein 3er-Eck-Bereich)
- Kachel-Grafiken als Tabelle, Zeichenroutine `draw_tile`
- **Test:** Feld erscheint, Ecken sind frei

-State: Done

## Stufe 1 – Zwei Spieler laufen

- Spieler-Struktur: x, y (in Kacheln), Richtung, Lebend-Flag
- IF2-Abfrage für beide Joysticks
- Bewegung in Kachelschritten, Blockieren durch Wand und Block
- Sprites der Spieler (16x16, Maske oder einfach per XOR)
- **Test:** Beide Figuren laufen unabhängig durchs Feld

-State: Done

## Stufe 2 – Bomben legen und explodieren

- Feuertaste legt Bombe auf die aktuelle Kachel (eine Bombe pro Spieler zu Beginn)
- Bombe hat einen Zähler, nach einigen Sekunden explodiert sie
- Explosion breitet sich kreuzförmig aus, Reichweite 2, stoppt an festen Wänden
- Flammen halten wenige Ticks, danach wird die Kachel wieder leer
- Spieler darf von der eigenen Bombe weglaufen, danach ist sie eine Wand
- **Test:** Bombe legen, weglaufen, Explosion sieht richtig aus

-State: Done

## Stufe 3 – Zerstören und Treffer

- Flammen zerstören Blöcke (Block wird zu leer oder zu Power-Up)
- Flammen treffen Spieler: Spieler stirbt (oder verliert ein Leben)
- Kettenreaktion: Flamme trifft eine Bombe, diese explodiert sofort
- **Test:** Kettenreaktionen, Tod, mehrere Bomben gleichzeitig

-State: Done

## Stufe 4 – Power-Ups

- Zerstörte Blöcke lassen mit fester Wahrscheinlichkeit Power-Ups fallen
- Aufsammeln durch Betreten: mehr Reichweite, mehr Bomben gleichzeitig, schneller laufen
- Power-Ups können durch Flammen zerstört werden
- **Test:** jedes Power-Up wirkt sichtbar

-State: Done

## Stufe 5 – Runden und Spielablauf

- Siegbedingung: Wer als Letzter lebt, gewinnt die Runde
- Unentschieden, wenn beide in derselben Explosion sterben
- Rundenzähler (z. B. best of 3), Anzeige in der Seitenleiste
- Titelbild / Menü: Spielerzahl wählen, Start per Feuer
- Rundenzeit mit Ablauf (optional: das Feld füllt sich am Ende mit Wänden von außen)
- **Test:** komplette Partie von Titel bis Sieger

-1. Meilenstein
-State: Done

## Stufe 6 – Gegner für den Einzelspieler

- Einfache Gegner (Monster), die zufällig laufen und bei Berührung töten
- Danach klügere Variante: weicht Flammen aus, folgt dem Spieler
- Einzelspielermodus: Level geschafft, wenn alle Gegner besiegt sind
- Mehrere Level mit steigender Gegnerzahl
- **Test:** Gegner laufen, sterben durch Flammen, töten den Spieler

-State: Done

## Stufe 7 – Sound und 128K-Fassung (optional)

- 48K: Beeper-Effekte für Bombe legen, Explosion, Power-Up, Tod
- Titelmelodie per Beeper (wie bei Boulder Dash)
- 128K: AY-Musik im Interrupt, Effekte als Kanal mitlaufen lassen (wie bei Pong Pro, sjasmplus, `xblastpro.*`)
- **Test:** Sound stört die Spielgeschwindigkeit nicht

-2. Meilenstein
-State: Done

## Stufe 8 – Feinschliff

- Highscore bzw. Rundenstatistik pro Sitzung (kein Speichern auf dem Stick)
- Animierte Flammen und Bomben (2 Frames)
- Zusätzliche Feldlayouts
- Balance: Zünddauer, Flammendauer, Laufgeschwindigkeit

-3. Meilenstein
-State: Done

---

## Risiken und offene Punkte

- **Rechenzeit:** Explosionen mit Kettenreaktionen sind der aufwendigste Teil; Ausbreitung in Ticks verteilen statt in einem Frame
- **Attribute Clash:** zwei Spieler mit unterschiedlichen Farben auf derselben Kachel; Lösung: feste Farbe pro Spielerfigur und Hintergrund der Kachel einheitlich
- **Eingabe:** IF2-Port 1 und 2 lesen; Diagonalen sperren, damit nur eine Richtung gilt
- **Zufallszahlen:** einfache LFSR-Routine, Seed vom R-Register oder Frame-Zähler beim Start

## Vorschlag für die Reihenfolge

Stufen 0 bis 5 ergeben ein vollständig spielbares Zwei-Spieler-XBlast. Stufe 6 bis 8 sind Ausbau und können einzeln nachgezogen werden.

# Boulderdash

Stufe 0: Fundament

Die Höhle als Byte-Array mit Tile-IDs anlegen. Das Original ist 40×22 Felder groß.
Dazu ein Tile-Renderer und ein fester Spieltakt. Das Original läuft mit etwa 8–10 Logik-Ticks pro Sekunde, unabhängig von der Framerate.
Gleich festlegen: Es werden nur Zellen neu gezeichnet, die sich geändert haben (Dirty-Liste). Auf dem Spectrum entscheidet das über die Performance.
Die Tilegröße wählst du jetzt. Mit 8×8 passt eine 32×22-Höhle ohne Scrolling auf den Bildschirm. Mit 16×16 sieht man nur 16×12 Felder, du brauchst also früher Scrolling, bekommst aber hübschere Grafik. Ich würde mit 8×8 und verkleinerten Höhlen starten.

-State: Done

Stufe 1: Rockford läuft

Bewegung durch Erde und leere Felder, Wände blockieren.
Steuerung per Tastatur oder Kempston-Joystick.

-State: Done

Stufe 2: Schwerkraft (das Herzstück)

Steine und Diamanten fallen und rollen von runden Objekten ab, also von Steinen, Diamanten und Mauern.
Die Zustände „liegt“ und „fällt“ unterscheiden: Nur ein fallender Stein tötet.
Den Scan von oben nach unten aufbauen und bewegte Objekte für den Rest des Ticks markieren, damit nichts doppelt bewegt wird.
Rockford kann Steine waagerecht schieben. Im Original klappt das nur mit einer gewissen Wahrscheinlichkeit.

-State: Done

Stufe 3: Erste spielbare Version

Diamanten zählen. Sind genug gesammelt, öffnet sich der Ausgang.
Dazu Zeitlimit, Leben, Punkte und eine Statuszeile.
Ab hier ist es ein echtes Spiel und ein guter Meilenstein.

-1. Meilenstein
-State: Done

Stufe 4: Gegner und Explosionen

Fireflies folgen der Wand links herum, Butterflies rechts herum.
Explosionen erfassen ein 3×3-Feld. Eine explodierende Butterfly hinterlässt Diamanten.
Animationsphasen für Gegner, Diamanten und den blinkenden Ausgang.

-State: Done

Stufe 5: Level-DSL

Höhlen als kompakte Beschreibung statt als Bitmap: Seed für den Zufallsfüller plus Befehle wie Linie, Rechteck und Punkt.
Dazu ein Decoder im Spiel und mehrere Höhlen mit Levelauswahl.
Optional ein Compiler oder Editor auf dem PC, der die Leveldaten erzeugt.

-State: Done

Stufe 6: Scrolling

Ab jetzt können Höhlen größer sein als der Bildschirm, und ein Viewport folgt Rockford.
Am einfachsten ist Scrolling in Tile-Schritten mit Neuzeichnen des sichtbaren Ausschnitts.
Weiches Scrolling ist eine eigene, deutlich härtere Baustelle.

-2. Meilenstein
-State: Done

Stufe 7: Spezialelemente

Amöbe: Sie wächst. Wird sie eingeschlossen, verwandelt sie sich in Diamanten, wird sie zu groß, in Steine.
Magic Wall: Fallende Steine werden zu Diamanten und umgekehrt.
Dazu Schwierigkeitsgrade pro Höhle.

-State: Done

Stufe 8: Politur

Sound über den Beeper oder den AY-Chip im 128K-Modus.
Rockford-Animationen, etwa das Fußwippen beim Warten.
Titelbild, Intro-Sequenz beim Höhlenstart und Highscore.

-3. Meilenstein
-State: Done