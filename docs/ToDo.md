# Common

# Asteroids

## 1. Grundentscheidungen

| Thema | Vorschlag | Begründung |
|---|---|---|
| Spielkonzept | Side-Scroller wie im Port | Sterne nach links passen genau dazu; echtes Asteroids (Rotation, Trägheit) wäre ein anderes Spiel |
| Bildaufbau | HUD oben 2 Zeilen (16 px), Spielfeld 32x22 Zellen = 256x176 px | volle Breite für Scrolling |
| Sprites | maskiert, 8 vorverschobene Kopien (1-Pixel-Schritte) | bewährt aus Pacman/Tron |
| Positionen | 8.8-Festkomma in x und y | langsame, gebrochene Geschwindigkeiten (z. B. 0,75 px/Frame) |
| Takt | 50 Hz, Spiel-Logik pro Frame; Fallback auf 25 Hz, wenn das Budget reißt | wird in Stufe 0 gemessen |
| Sound | nur AY, kein Beeper, Standard-Lautstärke 3, Taste T; keine Dauermusik im Spiel, keine Sirene | deine bisherigen Vorgaben |
| Steuerung | Sinclair IF2: Joystick 1 (Tasten 6-0), Joystick 2 (Tasten 1-5); Menü per Joystick; P = Pause, C = Farbraum | wie Pacman/Tron |
| Rekord | nur pro Sitzung | Speichern nicht möglich |
| Kollision | Hitbox-Rechtecke (leicht verkleinert), keine Pixeltests | schnell und fair; Pixeltest bleibt Option |

## 2. Technik

### 2.1 Doppelpuffer (128K)
- Port 0x7FFD = 0x17 (48K-ROM, Bank 7 bei 0xC000); Anzeige Bank 5/7 per Bit 3.
- Schattenbildschirm-Adresse = normale Adresse | 0x8000.
- Ablauf pro Frame: im Zeichenpuffer löschen, zeichnen, auf `HALT` warten, Anzeigebit umschalten, Puffer tauschen.
- Pro Puffer eigene „alter Bereich“-Slots für jedes Objekt und jeden Stern; geänderte Dinge 2 Frames lang zeichnen (`dirty=2`).
- Statische Grafik (HUD-Rahmen, Attribute) in beide Puffer schreiben, Objekte nur in den Zeichenpuffer.

### 2.2 Zeichenreihenfolge pro Frame (kein Flackern, Sterne bleiben heil)
1. alte Objekt-Rechtecke dieses Puffers löschen (Pixel + Zellattribute zurück auf Hintergrund)
2. alte Sternpixel dieses Puffers löschen
3. Sterne an neuer Position setzen
4. Objekte maskiert zeichnen (Sterne hinter transparenten Maskenteilen bleiben sichtbar)
5. HUD nur bei Änderung

### 2.3 Parallax-Sterne
- ca. 48 Sterne, 1 Pixel groß, **3 Ebenen**: fern 0,5 / mittel 1,0 / nah 2,0 px pro Frame (8.8-Festkomma), nach links; am linken Rand neu rechts mit zufälligem y.
- Die Farbe hängt am Attribut der Zelle, nicht am Pixel: **die Ebene wird deshalb pro Zellzeile festgelegt** (Zeilenmuster z. B. 0,2,1,0,1,2,…). Fern = dunkelblau, mittel = cyan, nah = weiß (ULAplus-Palette, Classic: blau/cyan/weiß ohne BRIGHT).
- Sternpixel unter einem Sprite nehmen kurz die Spritefarbe an (bekannte Attributkollision, wie in Pacman).

### 2.4 Sprites und Grafik
Größen (Vorschlag): Schiff 24x16, Flamme 8x8 (3 Animationsbilder), Laser 8x2 (Code gezeichnet), Asteroid klein 8x8 / mittel 16x16 / groß 24x24 (je mit Rotationsbildern), Komet 16x8 mit Schweif, Explosion 16x16 (4–5 Bilder).
- Farbe nur pro 8x8-Zelle: Schattierung deshalb über Dither-Muster und Umriss; mehrere Zellen = mehrere Farben (Cockpit blau, Rumpf grau, Düse orange).
- ULAplus: Spritefarben nutzen freie Attribute, Hintergrund/HUD belegen eigene Slots; Palettenindex = (Flash*2+Bright)*16 + (ink | paper+8).
- Generator (Python) erzeugt Sprites, Masken, 8 Verschiebungen und Tabellen aus Textvorlagen; das Template `src/asteroids.asm.in` bleibt lesbar.

### 2.5 Speicher und Zeit (in Stufe 0 messen, nicht schätzen)
- Grobschätzung vorverschobener Sprites: Schiff ~1 KB, Flamme ~0,8 KB, Asteroid mittel (4 Bilder) ~3 KB, klein ~0,5 KB, groß (3 Bilder) ~4,5 KB, Komet ~0,8 KB, Explosion ~3 KB → **ca. 13–14 KB**. Dazu Code ~8–10 KB. Das passt nur knapp zwischen 0x6000 und `VARS` (0xB400).
- Maßnahmen: Build-Skript bricht ab, wenn Code in `VARS` hineinwächst (Lehre aus Pacman); große Asteroiden und Explosionsbilder sind die ersten Streichkandidaten.
- Zeitbudget ≈ 70.900 T-States pro Frame. Grenzen: max. ca. 8 Asteroiden, 3 Kometen, 4 Laserstrahlen, 1 Explosion gleichzeitig; Messung im Headless-Emulator (T-States pro Frame).
- Heiße Schleifen möglichst oberhalb von 0x8000 (unkontendiert) legen.

### 2.6 Spiellogik (Original → Pixel)
- Spawn: aus `random(0,10) % base` wird ein Frame-Zähler mit Zufall (LFSR); Spawn-Zeile im ganzen Spielfeld, Geschwindigkeit leicht zufällig, optional leichte vertikale Drift.
- Schwierigkeit: wie im Original alle 10 Treffer schneller (`gmNormal` ×0,75, `gmBig` ×0,5 als Tempo-Auswahl im Menü).
- Wertung: Arcade-Punkte (groß 20, mittel 50, klein 100), 3 Leben, kein Abzug für entkommene Asteroiden.
- **Original-Macken, die wir bewusst nicht übernehmen:** Asteroid frisst Laser ohne Punkt, Schiff stirbt am eigenen Strahl, Flügel ohne Kollision, unterste Zeile ohne Asteroiden, Laser-Tempo hängt an der Schleife.
- Tunneling vermeiden: Laser 4 px/Frame, Asteroiden höchstens 3 px/Frame, Hitbox mindestens 8 px breit.

## 3. Stufenplan

**Stufe 0 – Gerüst und Messung**
128K-Start, `end start`, Doppelpuffer-Umschaltung (Testbild), ULAplus-Erkennung und Palette, Taste C, Spielfeld/HUD-Layout, Frame-Zähler, Speicherplan, T-State-Messung pro Frame. Test: beide Puffer wechseln sauber, Loader enthält `RANDOMIZE USR`.

- State: Done

**Stufe 1 – Parallax-Sternenhimmel**
Drei Ebenen im Doppelpuffer mit eigenen alten Slots, Attribute je Zellzeile. Test: Sternpositionen rücken genau um die Geschwindigkeit vor, beide Puffer konsistent, kein Stern außerhalb. GIF.

- State: Done

**Stufe 2 – Schiff mit Pixelbewegung**
Maskiertes Schiff mit 8 Verschiebungen, Joystick 1 in 4 Richtungen (z. B. 2 px/Frame), Ränder, Flammenanimation. Test: Position und Pixel im Speicherabzug, Sterne bleiben hinter der Maske heil.

- State: Done

**Stufe 3 – Laser**
Feuerknopf mit Feuerrate (Wiederholverzögerung wie `LASERBEAMSPAWNDELAY`), 4 px/Frame, max. 4 Strahlen, Mündungsblitz, AY-„Pew“ (kurzer Platzhalter).

- State: Done

**Stufe 4 – Asteroiden**
Spawn, Fließkomma-Geschwindigkeit, Rotationsanimation, Treffer Laser/Asteroid (symmetrisch), Explosion, Punkte (zunächst eine Größe, der Zerfall folgt in Stufe 8).

- State: Done

**Stufe 5 – Kometen und Schiffstod**
Kometen (schnell, mit Schweif), Kollision Schiff, Explosion des Schiffs, 3 Leben mit blinkender Schutzzeit, Game Over. Kometen sind nicht abschießbar.

- State: Done

**Stufe 6 – Spielablauf**
Titelbild (Intro wie im Original: Asteroiden, Schiff, Laserschuss), Menü per Joystick (Tempo/Modus), Level und Tempo-Anstieg, Pause P, Game-Over-Bild, Rekord pro Sitzung, Abspann (expandierender Kreis).

- 1. Meilenstein
- State: Done

**Stufe 7 – Sound über AY**
Laser, Explosion (Rauschen, satter „Peng“), Kometen-Zischen, Schiffstod, Titelmusik, Game-Over-Jingle, Taste T Lautstärke (Standard 3), keine Dauermusik.

- State: Done

**Stufe 8 – Asteroiden-Zerfall**
Groß → 2 mittlere → 2 kleine; Arcade-Punkte; Spawn-Gewichtung. Hier entscheidet sich, ob große Sprites in den Speicher passen.

- 2. Meilenstein
- State: Done

**Stufe 9 – Grafik-Feinschliff**
ULAplus-Paletten je Objekttyp, Dither-Schattierung, Funken-Partikel bei Explosionen, Triebwerksglühen, evtl. ferner Planet/Nebel als Extra-Ebene, Classic-Fallback abgleichen.

- State: InProgress

**Stufe 10 – Koop-Modus und Tuning**
Moduswahl 1/2 Spieler im Titelbild per Joystick, zweites Schiff (eigene Farbe) mit Joystick 2 per Kontext-Tausch (`swap_ctx`), je Spieler 3 Leben und eigene Punkte, Performance-Feinschliff (mehr Objekte bei zwei Schiffen), mehrere Schwierigkeitsprofile.

- 3. Meilenstein
- State: Open

## 4. Testbau und Abläufe
- Headless-Emulator (libz80ex) mit Tasten-Skript, Frame-Dump als .scr → PNG, Speicherabzug per Umgebungsvariable.
- Testbau-Schalter per Textersetzung (`TESTBUILD`, `RNG_SEED`, `LEVEL_*`, `FIRE_NEW`), keine Sonderpfade im Spiel.
- Zufall nur ziehen, wenn nötig (Testläufe bleiben reproduzierbar).
- Texte mit fester Spaltenbreite gleich lang polstern.
- Vor jeder Abgabe alle früheren Tests erneut laufen lassen.
- Sprünge: `jr` nur ±127, sonst `jp`; Labelnamen global eindeutig.

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
- State: Done

### Stufe 6 – Titelbild und Menü
- Titelbild im Neon-Look, Moduswahl per Joystick (links/hoch = 1 Spieler, rechts/runter = 2 Spieler).
- Tempo-Auswahl vor dem Start (wie bei Pong).
- Lautstärke per T (fünf Stufen plus Aus).
- Rekord/Siegesserie im Titelbild.

- State: Done

### Stufe 7 – Computergegner (Einzelspieler)
- 7a: Geradeaus fahren, 1-3 Pixel vorausschauen, bei Hindernis abbiegen (Seite mit mehr freiem Raum).
- 7b: Raumbewertung per begrenztem Flood-Fill (welche Richtung lässt mehr freie Fläche?), Fehlerquote einstellbar.
- 7c: Schwierigkeitsstufen (leicht / mittel / schwer) über Vorausschau-Tiefe und Reaktionszufall.
- Test: Headless-Läufe computer gegen computer, um Endlosschleifen und Selbstmordmuster zu finden.

- 2. Meilenstein
- State: Done

### Stufe 8 – Sound (128K)
- AY-Titelmusik, Crash- und Siegeseffekte, kein Dauergeräusch im Spiel (wie bei XBlast Pro).
- Soundcode aus Pong Pro / XBlast Pro als Basis.

- State: Done

### Stufe 9 – Arenen
- Feldvarianten: leer, Block in der Mitte, Säulen, Rahmen mit Lücken.
- Hindernisse werden als gesetzte Pixel/Zellen angelegt und bekommen eigene Wandfarbe.
- Zufällige Arena pro Runde oder wählbar im Menü.

- 3. Meilenstein
- State: Done

### Stufe 10 – Feinschliff und Extras (optional, einzeln freigebbar)
- Boost mit Feuertaste (kurz schneller, begrenzt).
- Abspann/Siegerbild, Rekord-Anzeige verfeinern.

- 4. Meilenstein
- State: Done

## Technische Hinweise

- **Pixeladressierung:** Y über Tabelle, X über Spaltenbyte plus Bitmaske. Schritt in X: Maske rotieren, bei Übertrag Byte weiter. Schritt in Y: Zeilenadresse über Tabelle oder `inc h`/Drittelgrenze beachten.
- **Speicher:** Code gegen den Variablenbereich prüfen (Pacman-Erfahrung), VARS ausreichend weit oben legen; 128K: ab 0xC000 liegt Bank 7.
- **Doppelpuffer:** Nicht nötig, solange nur Köpfe und Spur gesetzt werden. Eventuell nur für Explosionseffekte.
- **Tests ohne Hardware:** Headless-Emulator mit Tastenskript, Frame-Dump nach PNG, Speicherdump per Env-Variable. Feste Testfälle: Wandcrash, Eigenspur, Frontalzusammenstoß, gleichzeitiger Zielpixel, Kreuzung zweier Spuren in einer Zelle.

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