# Common
- Asteroids

# Tron

## Grundentscheidungen

| Thema | Entscheidung |
|---|---|
| Spur | 1 Pixel breit, Kollision per Pixeltest im Bildschirm-RAM (das Bild ist die Wahrheit, keine zweite Spielfeld-Struktur nötig) |
| Spielfläche | Randzellen (8 px) als Wand, innen 30x20 Zellen = **240x160 Pixel** |
| Rahmen | Als ganze Zellen, nicht als 1-Pixel-Linie, damit der Rahmen keine Attributkollision mit Spuren verursacht |
| HUD | Obere zwei Zeichenzeilen: Punkte Spieler 1 / Titel / Punkte Spieler 2 |
| Steuerung | Vier Richtungen absolut (Joystick links/rechts/hoch/runter), Umkehr um 180° gesperrt |
| Tempo | Takt über HALT (50 Hz), Schritte pro Frame einstellbar; bei zwei Schritten pro Frame wird jeder Schritt einzeln geprüft |
| Gleichzeitigkeit | Beide Köpfe ermitteln zuerst ihr Zielpixel, dann wird geprüft, erst danach gesetzt (fair, Remis möglich) |
| Farben | ULAplus automatisch an, "Classic" nur als Fallback; Spur 1 und Spur 2 in je einer Ink-Farbe, Hintergrund schwarz |
| Ton | alle Stufen AY-Musik/Effekte und Taste T schaltet die Lautstärke durch |
| Taste P | Pause |

### Das Attribut-Problem (1-Pixel-Spur)

Der Spectrum kennt nur eine Ink-Farbe pro 8x8-Zelle. Zwei Spuren in derselben Zelle färben sich also gegenseitig um. Lösung:

- Eine kleine **Besitzer-Tabelle** (32x24 Byte): 0 = leer, 1 = nur Spieler 1, 2 = nur Spieler 2, 3 = beide.
- Wird eine Zelle von beiden befahren, bekommt sie eine neutrale **Kreuzungsfarbe** (z. B. Weiß/hell) statt einer Mischung oder dem Überschreiben durch den zuletzt Gekommenen.
- Die Tabelle dient nur der Farbe; die Kollision entscheidet weiterhin der Pixeltest.
- Der aktuelle Kopf wird über BRIGHT der Zelle hervorgehoben.

---

## Stufen

### Stufe 0 – Spielfeld und Gerüst
- Bildaufbau: Rahmen aus Zellen, HUD-Zeilen, schwarzer Hintergrund.
- Optional: dezentes Neon-Gitter über **Paper-Farbe** (Schachbrettmuster in sehr dunklem Blau), nicht über Pixel, damit Gitterpunkte nicht als Kollision zählen.
- ULAplus automatisch an, Fallback Classic, Taste C schaltet manuell um.
- Zeilenadress-Tabelle für Y (192 Einträge) und Bitmasken-Tabelle für X.
- Ergebnis: leeres Spielfeld im Emulator und auf dem Gerät.

- State: Done

### Stufe 1 – Ein Kopf läuft
- Ein Lichtmotorrad, Joystick 1 steuert vier Richtungen, Umkehr gesperrt.
- Kopf setzt pro Schritt ein Pixel (Spur), Besitzer-Tabelle wird gepflegt.
- Tempo über Frames pro Schritt, Startwert so, dass die Querung des Felds etwa 5 Sekunden dauert.
- Noch keine Kollision.

- State: Done

### Stufe 2 – Kollision und Crash
- Pixeltest am Zielpixel: Wand, eigene Spur, fremde Spur.
- Crash-Animation (kleine Explosion aus Pixeln/Zellen), Crash-Sound (Beeper-Rauschen).
- Rundenende, kurze Pause, Neustart des Felds.

- State: Done

### Stufe 3 – Zwei Spieler
- Zweiter Kopf mit Joystick 2, Kontext-Tausch per `swap_ctx` wie bei Pacman.
- Gleichzeitige Zugermittlung: beide Ziele zuerst prüfen, dann setzen.
- Frontalzusammenstoß und gleicher Zielpixel = **Remis**.
- Sieger/Remis-Anzeige am Rundenende.

- State: Done

### Stufe 4 – Farben und Kreuzungen
- Besitzer-Tabelle steuert Zellfarbe: Spur 1, Spur 2, Kreuzung.
- Kopfhervorhebung über BRIGHT, ULAplus-Palette für kräftige Neonfarben.
- Prüfen, dass sich keine Zelle ungewollt umfärbt (Test mit Skript, Speicherdump der Attribute).

- State: Done

### Stufe 5 – Spielablauf
- Runden und Match (z. B. "best of 5"), Punktestand im HUD.
- Pause (P), Rundenende-Jingle, Matchende-Anzeige.
- Startsequenz: kurzer Countdown, Köpfe stehen sichtbar am Start.

- 1. Meilenstein
- State: InProgress

### Stufe 6 – Titelbild und Menü
- Titelbild im Neon-Look, Moduswahl per Joystick (links/hoch = 1 Spieler, rechts/runter = 2 Spieler).
- Tempo-Auswahl vor dem Start (wie bei Pong).
- Lautstärke per T (fünf Stufen plus Aus).
- Rekord/Siegesserie im Titelbild.

- State: Open

### Stufe 7 – Computergegner (Einzelspieler)
- 7a: Geradeaus fahren, 1-3 Pixel vorausschauen, bei Hindernis abbiegen (Seite mit mehr freiem Raum).
- 7b: Raumbewertung per begrenztem Flood-Fill (welche Richtung lässt mehr freie Fläche?), Fehlerquote einstellbar.
- 7c: Schwierigkeitsstufen (leicht / mittel / schwer) über Vorausschau-Tiefe und Reaktionszufall.
- Test: Headless-Läufe computer gegen computer, um Endlosschleifen und Selbstmordmuster zu finden.

- 2. Meilenstein
- State: Open

### Stufe 8 – Sound (128K)
- AY-Titelmusik, Crash- und Siegeseffekte, kein Dauergeräusch im Spiel (wie bei XBlast Pro).
- Soundcode aus Pong Pro / XBlast Pro als Basis.

### Stufe 9 – Arenen
- Feldvarianten: leer, Block in der Mitte, Säulen, Rahmen mit Lücken.
- Hindernisse werden als gesetzte Pixel/Zellen angelegt und bekommen eigene Wandfarbe.
- Zufällige Arena pro Runde oder wählbar im Menü.

- 3. Meilenstein
- State: Open

### Stufe 10 – Feinschliff und Extras (optional, einzeln freigebbar)
- Boost mit Feuertaste (kurz schneller, begrenzt).
- Lücken-Sprung (ein Pixel Lücke in der eigenen Spur).
- Abspann/Siegerbild, Rekord-Anzeige verfeinern.
- Weitere Ideen nach Geschmack.

- 4. Meilenstein
- State: Open

## Technische Hinweise

- **Pixeladressierung:** Y über Tabelle, X über Spaltenbyte plus Bitmaske. Schritt in X: Maske rotieren, bei Übertrag Byte weiter. Schritt in Y: Zeilenadresse über Tabelle oder `inc h`/Drittelgrenze beachten.
- **Speicher:** Code gegen den Variablenbereich prüfen (Pacman-Erfahrung), VARS ausreichend weit oben legen; 128K: ab 0xC000 liegt Bank 7.
- **Doppelpuffer:** Nicht nötig, solange nur Köpfe und Spur gesetzt werden. Eventuell nur für Explosionseffekte.
- **Tests ohne Hardware:** Headless-Emulator mit Tastenskript, Frame-Dump nach PNG, Speicherdump per Env-Variable. Feste Testfälle: Wandcrash, Eigenspur, Frontalzusammenstoß, gleichzeitiger Zielpixel, Kreuzung zweier Spuren in einer Zelle.
- **Abgabe pro Stufe:** `tron.tap`, `tron.asm`, Screenshot oder GIF.

---

# Super Mario

## Eckdaten

- Kacheln: 16x16 Pixel (2x2 Zeichenzellen), Bildschirm 16x12 Kacheln (256x192)
- Figuren: klein 16x16, groß 16x32, beide von Anfang an
- Scrolling: zuerst in 8-Pixel-Schritten (eine Zeichenzelle), später weich (Pixel)
- Spieler: Ein- und Zwei-Spieler-Modus, gleichzeitig (Joy1 und Joy2, Sinclair IF2: Joy1 = Tasten 6-0, Joy2 = Tasten 1-5), Tastatur als Alternative

## Thema: Ritter

| Element | Festlegung |
|---|---|
| Spieler 1 | Junger Ritter (rote Farbgebung); klein = ohne Rüstung, groß = mit Helm und Rüstung |
| Spieler 2 | Zweiter Ritter in anderer Farbe (blau), gleiche Grafik, andere Farbattribute |
| Gegner | Skelette (Läufer), Skelett-Schildträger (Panzer-Typ: Schild bleibt liegen, kann geschubst werden), Fledermäuse (fliegen in Wellen), später Geister |
| Endgegner | Drache am Ende des Burg-Levels (mehrere Treffer, Feuerspucken) |
| Kacheln | Himmel, Gras/Erde, Stein, Ziegel, Truhe (statt Fragezeichen-Block), leere Truhe, Fass/Säule (statt Röhre), Münze, Fackel, Zugbrücke, Fahne |
| Power-up 1 | Rüstung (Ritter wird groß, Hitbox 16x32) |
| Power-up 2 | Feuerball (Ritter wirft Feuerbälle, springen von Boden und Wänden ab) |
| Power-up 3 | Stern (kurze Unverwundbarkeit, blinkende Farben) |
| Welten | Wiese, Wald, Höhle, Burg, Drachenhöhle |

## Technische Grundentscheidungen

| Thema | Entscheidung |
|---|---|
| Bildspeicher | Doppelpuffer ab Stufe 1 (Port 0x7FFD = 0x17, Bank 5/7), wie bei Pacman |
| Level-Format | Textkarten `levels/LevelNN.map` (ein Zeichen = eine 16x16-Kachel), Build-Skript wandelt sie in Bytes um |
| Level-Größe | Höhe 12 Kacheln, Breite bis 200 Kacheln (Byte pro Kachel, ca. 2,4 KB pro Level) |
| Kollision | Kachelbasiert gegen die Level-Karte; Hitbox kleiner als Sprite, Höhe abhängig von klein/groß |
| Physik | Festkomma 8.8 für Position und Geschwindigkeit, Gravitation pro Frame, variable Sprunghöhe (Taste gehalten = höher) |
| Scrolling | Kamera-Position in Pixeln, Darstellung zunächst nur in 8er-Schritten; Kamera mit Totzone |
| Zwei Spieler | Kontext-Tausch (swap_ctx: Zustandsblock tauschen) statt doppelter Routinen, wie bei Pacman; Kamera folgt dem vorderen Spieler, der hintere kann nicht links aus dem Bild laufen |
| Speicher | Code gegen VARS prüfen (Erfahrung Pacman), Level-Daten und Sprites in eigenen 128K-Bänken, VARS bei Bedarf verschieben |
| Farben | Attribut-Clash beachten: Himmel pro Zelle eine Farbe, Sprites mit freien Attributen; ULAplus automatisch, Fallback Classic |
| Bauprozess | Template `src/mario.asm.in` + Python-Generator (Kacheln, Sprites, Tabellen, Level) -> `tools/build.sh` -> pasmo |
| Test | Headless-Emulator mit Tasten-Skript, Frame-Dump als .scr -> PNG, Speicher-Dump zum Prüfen von Variablen |

## Stufen

### Stufe 0: Kacheln und statisches Level

- Kachelsatz 16x16: Himmel, Gras, Stein, Ziegel, Truhe, Fass, Münze, Fackel
- Figuren-Studien: Ritter klein (16x16) und groß (16x32), Skelett, Fledermaus, jeweils in zwei Bildern als Vorschau
- Ein Bildschirm (16x12) mit Wiesenlandschaft, Wolken und Hügeln als Deko

- State: Open

### Stufe 1: Ritter läuft (klein und groß)

- Ritter mit Joystick und Tastatur nach links/rechts, Blickrichtung, Laufanimation (2 bis 3 Bilder)
- Taste zum Umschalten klein/groß zum Testen (wird in Stufe 6 durch das Power-up ersetzt)
- Doppelpuffer, Beschleunigung und Abbremsen
- Noch ohne Schwerkraft, Figur steht auf dem Boden
- Tempo bei dir abfragen, "ein wenig langsamer/schneller" ist bei dir Standard

- State: Open

### Stufe 2: Schwerkraft, Sprung und Kollision

- Gravitation, Fallen, Landen auf Boden, Ziegeln und Fässern
- Sprung mit Feuertaste, variable Sprunghöhe (kurz tippen = kleiner Sprung)
- Kollision seitlich, oben (Kopf stößt an Ziegel, bei der großen Figur 32 Pixel höher) und unten
- Sprung- und Lande-Animation
- Feinabstimmung von Sprunghöhe und Gravitation mit deinem Feedback

- State: Open

### Stufe 3: Scrolling in 8-Pixel-Schritten

- Level wird breiter als der Bildschirm, Kamera folgt dem Ritter
- Scrollen um eine Zeichenzelle (8 Pixel), Figur bewegt sich in Pixeln
- Kachelspalten am Rand nachzeichnen, Bildspeicher per LDIR verschieben
- Levelgrenzen links und rechts
- Messung: Frames pro Sekunde, Reserve für Gegner, Sound und zweiten Spieler prüfen

- 1. Meilenstein
- State: Open

### Stufe 4: Zwei Spieler

- Zweiter Ritter mit Joy2, Kontext-Tausch statt doppelter Routinen
- Kamera folgt dem vorderen Spieler, der hintere kann nicht links aus dem Bild
- Moduswahl (1 oder 2 Spieler) per Joystick im Titelbild (Spalte wie bei Pacman, links/hoch = 1, rechts/runter = 2)
- Früh eingebaut, damit alle späteren Stufen von Anfang an für zwei Spieler getestet werden

- State: Open

### Stufe 5: Truhen, Münzen, Punktestand

- Truhe: von unten anspringen, Münze oder Power-up kommt heraus, Truhe wird leer
- Ziegel: anspringen, bei der großen Figur zerbrechen sie
- Münzen einsammeln, Münzzähler je Spieler
- Kopfzeile: Punkte, Münzen, Welt/Level, Zeit, Leben (für beide Spieler)
- Münz-Sound (Beeper, AY-Sound folgt in Stufe 9)

- State: Open

### Stufe 6: Gegner

- Skelett: läuft auf der Kachelkarte, dreht an Wänden um, fällt von Kanten
- Draufspringen besiegt es (Punkte), seitlicher Kontakt kostet Rüstung oder Leben
- Skelett-Schildträger: beim Draufspringen bleibt der Schild liegen und kann geschubst werden
- Fledermaus: fliegt in Wellenlinien
- Gegnerlisten pro Level aus der Karte (Zeichen in der Textkarte), aktiv erst im Kamerabereich
- Tod: Animation, Leben abziehen, Level neu starten (Zwei Spieler: der andere läuft weiter)

- State: Open

### Stufe 7: Power-ups

- Rüstung: Ritter wird groß; Treffer als große Figur: schrumpfen statt sterben, kurze Unverwundbarkeit (Blinken)
- Feuerball: Feuertaste wirft Feuerbälle, springen vom Boden ab, besiegen Gegner
- Stern: kurze Unverwundbarkeit, wechselnde Farben, Gegner besiegt durch Berührung
- Power-ups kommen aus Truhen

### Stufe 8: Endgegner

- Drache am Ende des Burg-Levels: mehrere Treffer (Feuerball oder auf den Kopf springen), Feuerspucken, Bewegungsmuster
- Zugbrücke oder Brücke über Lava als Arena
- Sieg öffnet das Ende des Levels

- 2. Meilenstein
- State: Open

### Stufe 9: Sound und Musik (128K)

- AY-Musik für Titel, Level und Fanfaren, eigene Melodien (keine Originalmelodien)
- Effekte: Sprung, Münze, Truhe, Gegner besiegt, Feuerball, Stern, Schrumpfen, Tod, Levelende, Drachenbrüllen
- Lautstärke per Taste T durchschalten (5 Stufen plus Aus), wie bei XBlast
- Musik im Spiel optional abschaltbar

- State: Open

### Stufe 10: Spielablauf, Titelbild, Abspann

- Titelbild mit Moduswahl, Titelmelodie
- Levelende mit Fahne, Zeitbonus, Übergang zum nächsten Level
- Leben, Game Over, Highscore pro Sitzung
- Pause mit P, Farbraum automatisch erweitert (ULAplus), Fallback Classic, Umschalter C
- Abspann nach dem letzten Level

- 3. Meilenstein
- State: Open

### Stufe 11: Weiches Scrolling und Feintuning

- Pixel-Scrolling mit vorverschobenen Kacheln (8 Versionen pro Kachel)
- Sprite-Bewegung in 1-Pixel-Schritten (8 vorverschobene Kopien, auch für 16x32)
- Tempo, Sprunghöhe und Gegner-Geschwindigkeit nach deinem Feedback
- Speicherlayout und Codegröße prüfen

- State: Open

### Stufe 12: Level

- Welt 1 Wiese: Level 1 als Einstieg, danach weitere Level im Retro-Stil
- Welt 2 Wald, Welt 3 Höhle (dunkle Farben), Welt 4 Burg mit Drachen, optional Wasser-Level (andere Physik)
- Bonusbereiche (Fass führt in einen Münzraum)
- Alle Level in `levels/LevelNN.map` und `Level.md` mit Übersicht
- Eigene Nachbauten nach deinen Screenshots von Vorlagen, wenn du sie schickst (als eigene Gestaltung)

- 4. Meilenstein
- State: Open

## Risiken

- **Rechenzeit beim Scrollen:** Spalten nachzeichnen und Doppelpuffer kosten Frames, mit zwei Spielern und großen Figuren noch mehr. Deshalb früh messen (Stufe 3 und 4), bevor Gegner dazukommen.
- **Attribut-Clash:** Zwei Ritter plus Gegner auf bunten Kacheln; Himmel und Sprite-Farben von Anfang an mit freien Attributen planen.
- **Speicher:** Level, Sprites (klein, groß, Gegner, vorverschobene Kopien) und Code in 128K-Bänken verteilen, Code gegen Variablenbereich prüfen (Pacman-Erfahrung).
- **Kamera bei zwei Spielern:** Der hintere Spieler darf nicht links aus dem Bild; Verhalten beim Tod und beim Wiedereinsteigen früh testen.
- **pasmo:** `jr` nur +-127, Labels global eindeutig.

---

# Pacman

Ziel: Labyrinth-Jagd im Stil von Pacman in Z80-Assembler, nur 128K, AY-Sound.

## Architektur

**Schichten:** Logik (Zustand, Geister-KI, Modi) getrennt von Darstellung (Sprite-Engine, Karte), Eingabe und Sound. Die Logik kennt nur Kachel + Subschritt, keine Bildschirmadressen.

**Figur (`actor`)** – Kachel x/y, Pixel-Offset in der Kachel, Richtung, gewünschte Richtung, Tempo-Akkumulator, Modus, Zielkachel.

**Karte** – 28 × 21 Bytes mit Flags: Wand, Punkt, Pille, Tunnel, Käfig, „Kreuzung ohne Aufwärts". Wandzellen wählen ihre Grafik zur Laufzeit über eine 4-Bit-Nachbarmaske (16 Wandtiles) – so entstehen durchgehende Linien statt Klötzen.

**Frame-Ablauf (50 Hz):** `HALT` → Figuren löschen (Hintergrund aus Karte wiederherstellen, kein Maskenspeichern) → Logik einen Schritt → Figuren zeichnen → Sound-Tick.

**Tempo.** 2-Pixel-Schritte (bei Bedarf 1 Pixel) mit einem Takt-Muster über 20 Frames. Richtwerte Level 1: Spieler ca. 12 von 20 Frames, Geister ca. 11, Tunnel ca. 6, verängstigte Geister ca. 8. Feintuning auf dem Gerät.

**Sprites.** Vorgeschobene Kopien (4 Phasen bei 2-Pixel-Schritten) mit Maske, erzeugt vom Build-Skript. Geschätzt rund 5 KB, kein Problem im 128K.

**Speicher.** Code bei 32768 wie gehabt, Variablen und Karte im Bereich ab 0xB000, große Tabellen bei Bedarf in gebankten RAM.

## Stufenplan

### Stufe 0 – Gerüst und Labyrinth
- Start, Joystick, Zeichensatz im RAM, Hauptschleife mit `HALT`.
- Textkarte für das Labyrinth, Zeichnen mit Wandtiles (Nachbarmaske), Punkte und Pillen als Tiles
- HUD-Zeilen mit Platzhaltern

- State: Done

### Stufe 1 – Spieler läuft
- Sprite-Engine (Löschen aus Karte, Zeichnen vorgeschobener Sprites), Mundanimation
- Pixelweise Bewegung, gepufferte Richtungswunsch, Abbiegen nur an der Kachelmitte
- Tunnel links/rechts, Tempo-Muster

- State: Done

### Stufe 2 – Punkte, Pillen, Punktestand
- Punkte fressen (Karte und Bildschirm aktualisieren), Pillen blinken, Punktezähler
- Level geschafft, wenn alles gefressen ist (Blinken, dann Neuaufbau)
- Fresseffekt als einfacher AY-Effekt auf Kanal C (zwei abwechselnde Töne)

- State: Done

### Stufe 3 – Geister laufen (Grundgerüst)
- Vier Geister als Figuren mit eigenem Tempo und Farbe, zunächst ohne Käfig
- Richtungswahl an jeder Kachelmitte, vorausberechnet: Reihenfolge hoch, links, runter, rechts, kein Umkehren, kürzeste Distanz zum Ziel. Zunächst haben alle den Spieler als Ziel.
- Kollision Spieler–Geist: Leben verlieren (noch ohne Animation)

- State: Done

### Stufe 4 – Individuelle Zielwahl
- Jäger: Spieler
- Abfangjäger: einige Kacheln vor dem Spieler
- Flankierer: Spiegelpunkt über Jäger und Vorfeld des Spielers
- Zögerer: Spieler, solange weit weg, sonst eigene Ecke
- Debug-Overlay (Taste D): Zielkachel jedes Geistes als farbiger Punkt, Modus und Timer in der HUD-Zeile

- State: Done

### Stufe 5 – Modi und Käfig
- Scatter/Chase nach Zeittabelle, Richtungsumkehr beim Moduswechsel
- Käfig mit Freilassungsregel über Punktzähler, Ausgangsweg
- Pille → verängstigt (zufällige Richtungswahl, langsamer, Blinken vor Ende), Geist fressen → Augen laufen zurück in den Käfig, Kettenpunkte 200/400/800/1600
- Tabellen je Level: Tempo, Modus-Zeiten, Pillendauer

- State: Done

### Stufe 6 – Spielablauf
- Leben, Todesanimation, Neustart-Pause „BEREIT", Game Over
- Level-Folge mit steigendem Tempo, Bonusobjekt (eigene Symbole) mit Zeitfenster
- Extraleben bei Punktestand X

- 1. Meilenstein
- State: Done

### Stufe 7 – Sound (AY, 128K)
- Eigene Titelmelodie, Sirene im Spiel (wechselnd je Modus), Fress-, Geister-fressen-, Tod-, Bonus- und Extraleben-Effekte
- Lautstärke per T kein Dauermusik-Zwang im Spiel

- State: Done

### Stufe 8 – Titelbild und Rundherum
- Titelbild mit Regenbogen-Schrift, Spielstart per Feuer
- Sitzungsrekord, Pause (P), Abspann nach dem letzten Level

- 2. Meilenstein
- State: Done

### Stufe 9 – Feinschliff
- Flimmerfrei: wenn sichtbar, zweiter Bildschirm (Bank 7) mit Umschalten pro Frame
- 2–4 Labyrinthe im Wechsel
- Feintuning der Tempi und Zeiten auf dem Gerät

- 3. Meilenstein
- State: Done

### Stufe 10 – Zwei Spieler
- beide Spieler laufen gleichzeitig, wer mehr frisst, gewinnt

- 4. Meilenstein
- State: Done

## Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Flimmern bei Löschen/Zeichnen aller Figuren | Zeichnen direkt nach `HALT`; Stufe 9: Doppelpuffer |
| Zu langsame Frames | Geister-KI nur an Kachelmitten; Zeitbudget pro Frame messen (Rand-Farbstreifen) |
| Zielwahl-Fehler schwer zu sehen | Debug-Overlay ab Stufe 4 |
| Kurven-Gefühl ungewohnt | Gepufferter Richtungswunsch, ggf. „Vorab-Abbiegen" um 1–2 Pixel |

---

# XBlast

Ziel: Ein Bomberman-artiges Spiel für zwei Spieler in Z80-Assembler, in Stufen aufgebaut wie bei Boulder Dash. Jede Stufe ist lauffähig und wird einzeln getestet.

- **Artefakte:** `xblast.asm` und `xblast.tap`
- **Assembler:** pasmo (48K) – sjasmplus erst in Stufe 7 für die 128K-Fassung
- **Steuerung:** Sinclair IF2, Joystick 1 und 2 (je Richtung + Feuer = Bombe legen)
- **Test:** Retro The Spectrum, TAP vom USB-Stick

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

## Stufenplan

### Stufe 0 – Gerüst und Spielfeld

- Bildschirm löschen, Raster mit festen Wänden (jede zweite Kachel in Zeile und Spalte, Rand außen) zeichnen
- Zufällig Blöcke verteilen, die Startecken bleiben frei (je ein 3er-Eck-Bereich)
- Kachel-Grafiken als Tabelle, Zeichenroutine `draw_tile`
- **Test:** Feld erscheint, Ecken sind frei

- State: Done

### Stufe 1 – Zwei Spieler laufen

- Spieler-Struktur: x, y (in Kacheln), Richtung, Lebend-Flag
- IF2-Abfrage für beide Joysticks
- Bewegung in Kachelschritten, Blockieren durch Wand und Block
- Sprites der Spieler (16x16, Maske oder einfach per XOR)
- **Test:** Beide Figuren laufen unabhängig durchs Feld

- State: Done

### Stufe 2 – Bomben legen und explodieren

- Feuertaste legt Bombe auf die aktuelle Kachel (eine Bombe pro Spieler zu Beginn)
- Bombe hat einen Zähler, nach einigen Sekunden explodiert sie
- Explosion breitet sich kreuzförmig aus, Reichweite 2, stoppt an festen Wänden
- Flammen halten wenige Ticks, danach wird die Kachel wieder leer
- Spieler darf von der eigenen Bombe weglaufen, danach ist sie eine Wand
- **Test:** Bombe legen, weglaufen, Explosion sieht richtig aus

- State: Done

### Stufe 3 – Zerstören und Treffer

- Flammen zerstören Blöcke (Block wird zu leer oder zu Power-Up)
- Flammen treffen Spieler: Spieler stirbt (oder verliert ein Leben)
- Kettenreaktion: Flamme trifft eine Bombe, diese explodiert sofort
- **Test:** Kettenreaktionen, Tod, mehrere Bomben gleichzeitig

- State: Done

### Stufe 4 – Power-Ups

- Zerstörte Blöcke lassen mit fester Wahrscheinlichkeit Power-Ups fallen
- Aufsammeln durch Betreten: mehr Reichweite, mehr Bomben gleichzeitig, schneller laufen
- Power-Ups können durch Flammen zerstört werden
- **Test:** jedes Power-Up wirkt sichtbar

- State: Done

### Stufe 5 – Runden und Spielablauf

- Siegbedingung: Wer als Letzter lebt, gewinnt die Runde
- Unentschieden, wenn beide in derselben Explosion sterben
- Rundenzähler (z. B. best of 3), Anzeige in der Seitenleiste
- Titelbild / Menü: Spielerzahl wählen, Start per Feuer
- Rundenzeit mit Ablauf (optional: das Feld füllt sich am Ende mit Wänden von außen)
- **Test:** komplette Partie von Titel bis Sieger

- 1. Meilenstein
- State: Done

### Stufe 6 – Gegner für den Einzelspieler

- Einfache Gegner (Monster), die zufällig laufen und bei Berührung töten
- Danach klügere Variante: weicht Flammen aus, folgt dem Spieler
- Einzelspielermodus: Level geschafft, wenn alle Gegner besiegt sind
- Mehrere Level mit steigender Gegnerzahl
- **Test:** Gegner laufen, sterben durch Flammen, töten den Spieler

- State: Done

### Stufe 7 – Sound und 128K-Fassung (optional)

- 48K: Beeper-Effekte für Bombe legen, Explosion, Power-Up, Tod
- Titelmelodie per Beeper (wie bei Boulder Dash)
- 128K: AY-Musik im Interrupt, Effekte als Kanal mitlaufen lassen (wie bei Pong Pro, sjasmplus, `xblastpro.*`)
- **Test:** Sound stört die Spielgeschwindigkeit nicht

- 2. Meilenstein
- State: Done

### Stufe 8 – Feinschliff

- Highscore bzw. Rundenstatistik pro Sitzung (kein Speichern auf dem Stick)
- Animierte Flammen und Bomben (2 Frames)
- Zusätzliche Feldlayouts
- Balance: Zünddauer, Flammendauer, Laufgeschwindigkeit

- 3. Meilenstein
- State: Done

### Risiken und offene Punkte

- **Rechenzeit:** Explosionen mit Kettenreaktionen sind der aufwendigste Teil; Ausbreitung in Ticks verteilen statt in einem Frame
- **Attribute Clash:** zwei Spieler mit unterschiedlichen Farben auf derselben Kachel; Lösung: feste Farbe pro Spielerfigur und Hintergrund der Kachel einheitlich
- **Eingabe:** IF2-Port 1 und 2 lesen; Diagonalen sperren, damit nur eine Richtung gilt
- **Zufallszahlen:** einfache LFSR-Routine, Seed vom R-Register oder Frame-Zähler beim Start

### Vorschlag für die Reihenfolge

Stufen 0 bis 5 ergeben ein vollständig spielbares Zwei-Spieler-XBlast. Stufe 6 bis 8 sind Ausbau und können einzeln nachgezogen werden.

---

# Boulderdash

Stufe 0: Fundament

Die Höhle als Byte-Array mit Tile-IDs anlegen. Das Original ist 40×22 Felder groß.
Dazu ein Tile-Renderer und ein fester Spieltakt. Das Original läuft mit etwa 8–10 Logik-Ticks pro Sekunde, unabhängig von der Framerate.
Gleich festlegen: Es werden nur Zellen neu gezeichnet, die sich geändert haben (Dirty-Liste). Auf dem Spectrum entscheidet das über die Performance.
Die Tilegröße wählst du jetzt. Mit 8×8 passt eine 32×22-Höhle ohne Scrolling auf den Bildschirm. Mit 16×16 sieht man nur 16×12 Felder, du brauchst also früher Scrolling, bekommst aber hübschere Grafik. Ich würde mit 8×8 und verkleinerten Höhlen starten.

- State: Done

Stufe 1: Rockford läuft

Bewegung durch Erde und leere Felder, Wände blockieren.
Steuerung per Tastatur oder Kempston-Joystick.

- State: Done

Stufe 2: Schwerkraft (das Herzstück)

Steine und Diamanten fallen und rollen von runden Objekten ab, also von Steinen, Diamanten und Mauern.
Die Zustände „liegt“ und „fällt“ unterscheiden: Nur ein fallender Stein tötet.
Den Scan von oben nach unten aufbauen und bewegte Objekte für den Rest des Ticks markieren, damit nichts doppelt bewegt wird.
Rockford kann Steine waagerecht schieben. Im Original klappt das nur mit einer gewissen Wahrscheinlichkeit.

- State: Done

Stufe 3: Erste spielbare Version

Diamanten zählen. Sind genug gesammelt, öffnet sich der Ausgang.
Dazu Zeitlimit, Leben, Punkte und eine Statuszeile.
Ab hier ist es ein echtes Spiel und ein guter Meilenstein.

- 1. Meilenstein
- State: Done

Stufe 4: Gegner und Explosionen

Fireflies folgen der Wand links herum, Butterflies rechts herum.
Explosionen erfassen ein 3×3-Feld. Eine explodierende Butterfly hinterlässt Diamanten.
Animationsphasen für Gegner, Diamanten und den blinkenden Ausgang.

- State: Done

Stufe 5: Level-DSL

Höhlen als kompakte Beschreibung statt als Bitmap: Seed für den Zufallsfüller plus Befehle wie Linie, Rechteck und Punkt.
Dazu ein Decoder im Spiel und mehrere Höhlen mit Levelauswahl.
Optional ein Compiler oder Editor auf dem PC, der die Leveldaten erzeugt.

- State: Done

Stufe 6: Scrolling

Ab jetzt können Höhlen größer sein als der Bildschirm, und ein Viewport folgt Rockford.
Am einfachsten ist Scrolling in Tile-Schritten mit Neuzeichnen des sichtbaren Ausschnitts.
Weiches Scrolling ist eine eigene, deutlich härtere Baustelle.

- 2. Meilenstein
- State: Done

Stufe 7: Spezialelemente

Amöbe: Sie wächst. Wird sie eingeschlossen, verwandelt sie sich in Diamanten, wird sie zu groß, in Steine.
Magic Wall: Fallende Steine werden zu Diamanten und umgekehrt.
Dazu Schwierigkeitsgrade pro Höhle.

- State: Done

Stufe 8: Politur

Sound über den Beeper oder den AY-Chip im 128K-Modus.
Rockford-Animationen, etwa das Fußwippen beim Warten.
Titelbild, Intro-Sequenz beim Höhlenstart und Highscore.

- 3. Meilenstein
- State: Done