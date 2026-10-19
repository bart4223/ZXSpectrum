# Common
- ...

# Games
- Boulderdash
- Pacman
- Super Mario

# Boulderdash

Stufe 0: Fundament

Die Höhle als Byte-Array mit Tile-IDs anlegen. Das Original ist 40×22 Felder groß.
Dazu ein Tile-Renderer und ein fester Spieltakt. Das Original läuft mit etwa 8–10 Logik-Ticks pro Sekunde, unabhängig von der Framerate.
Gleich festlegen: Es werden nur Zellen neu gezeichnet, die sich geändert haben (Dirty-Liste). Auf dem Spectrum entscheidet das über die Performance.
Die Tilegröße wählst du jetzt. Mit 8×8 passt eine 32×22-Höhle ohne Scrolling auf den Bildschirm. Mit 16×16 sieht man nur 16×12 Felder, du brauchst also früher Scrolling, bekommst aber hübschere Grafik. Ich würde mit 8×8 und verkleinerten Höhlen starten.

-State: Open

Stufe 1: Rockford läuft

Bewegung durch Erde und leere Felder, Wände blockieren.
Steuerung per Tastatur oder Kempston-Joystick.

-State: Open

Stufe 2: Schwerkraft (das Herzstück)

Steine und Diamanten fallen und rollen von runden Objekten ab, also von Steinen, Diamanten und Mauern.
Die Zustände „liegt“ und „fällt“ unterscheiden: Nur ein fallender Stein tötet.
Den Scan von oben nach unten aufbauen und bewegte Objekte für den Rest des Ticks markieren, damit nichts doppelt bewegt wird.
Rockford kann Steine waagerecht schieben. Im Original klappt das nur mit einer gewissen Wahrscheinlichkeit.

-State: Open

Stufe 3: Erste spielbare Version

Diamanten zählen. Sind genug gesammelt, öffnet sich der Ausgang.
Dazu Zeitlimit, Leben, Punkte und eine Statuszeile.
Ab hier ist es ein echtes Spiel und ein guter Meilenstein.

-1. Meilenstein
-State: Open

Stufe 4: Gegner und Explosionen

Fireflies folgen der Wand links herum, Butterflies rechts herum.
Explosionen erfassen ein 3×3-Feld. Eine explodierende Butterfly hinterlässt Diamanten.
Animationsphasen für Gegner, Diamanten und den blinkenden Ausgang.

-State: Open

Stufe 5: Level-DSL

Höhlen als kompakte Beschreibung statt als Bitmap: Seed für den Zufallsfüller plus Befehle wie Linie, Rechteck und Punkt.
Dazu ein Decoder im Spiel und mehrere Höhlen mit Levelauswahl.
Optional ein Compiler oder Editor auf dem PC, der die Leveldaten erzeugt.

-State: Open

Stufe 6: Scrolling

Ab jetzt können Höhlen größer sein als der Bildschirm, und ein Viewport folgt Rockford.
Am einfachsten ist Scrolling in Tile-Schritten mit Neuzeichnen des sichtbaren Ausschnitts.
Weiches Scrolling ist eine eigene, deutlich härtere Baustelle.

-2. Meilenstein
-State: Open

Stufe 7: Spezialelemente

Amöbe: Sie wächst. Wird sie eingeschlossen, verwandelt sie sich in Diamanten, wird sie zu groß, in Steine.
Magic Wall: Fallende Steine werden zu Diamanten und umgekehrt.
Dazu Schwierigkeitsgrade pro Höhle.

-State: Open

Stufe 8: Politur

Sound über den Beeper oder den AY-Chip im 128K-Modus.
Rockford-Animationen, etwa das Fußwippen beim Warten.
Titelbild, Intro-Sequenz beim Höhlenstart und Highscore.

-3. Meilenstein
-State: Open