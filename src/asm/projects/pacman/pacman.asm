; ============================================================
; Pacman-Variante fuer den ZX Spectrum 128K - Stufe 5: Streuen/Jagd, Haus, Pillen
; Assembler: pasmo   (pasmo --tapbas pacman.asm pacman.tap)
; ============================================================
; Nur 128K. Das Labyrinth ist eine Textkarte (map_text weiter unten), 28 x 21
; Kacheln zu je 8x8 Pixel. Die Wandzeichnung entsteht beim Start aus der Karte:
; fuer jede Wandkachel werden die 8 Nachbarn untersucht (Maske), daraus waehlt
; eine Tabelle die passende Kachel (Linien dort, wo ein Gang angrenzt).
;
; Stufe 5: Die Drohnen wechseln nach einer Zeittabelle zwischen Streuen (jede laeuft zu ihrer
; Ecke) und Jagd, beim Wechsel kehren die jagenden um. Die Drohnen im Haus kommen nach
; gefressenen Punkten (oder wenn zu lange keiner gefressen wird) heraus. Eine Pille macht
; jagende Drohnen blau und langsam (zufaellige Richtung, blinken vor dem Ende); fressen bringt
; 200/400/800/1600, die Augen laufen zum Haus zurueck und kommen als Jaeger wieder heraus.
; Tempo, Pillendauer, Zeit- und Freigabetabellen haengen vom Level ab (Tabellen am Dateiende).
; Stufe 4: Jede Drohne hat ihre eigene Zielwahl (nur in der Jagd):
;   Jaeger (rot)         : der Roboter selbst
;   Abfangjaeger (rosa)  : 4 Felder vor dem Roboter (in seiner Laufrichtung)
;   Flankierer (cyan)    : Spiegelpunkt des Jaegers am Punkt 2 Felder vor dem Roboter
;   Zoegerer (orange)    : der Roboter, solange er weiter als 8 Felder weg ist, sonst
;                          die eigene Ecke unten links
; Taste D schaltet die Zielanzeige ein/aus: jede Zielkachel erscheint als kleiner Ring
; in der Farbe ihrer Drohne.
; Stufe 3: Vier Drohnen (Geister) mit eigenem Tempo und eigener Farbe jagen den Roboter.
; An jeder Kachelmitte waehlt eine Drohne die Richtung: Reihenfolge hoch, links, runter,
; rechts, kein Umkehren, kleinster Abstand der naechsten Kachel zum Ziel (hier haben
; noch alle den Roboter als Ziel). Die drei Drohnen im Haus werden nacheinander
; freigelassen (2, 4, 6 Sekunden). Beruehrung kostet ein Leben (drei Leben, danach
; beginnt das Spiel von vorn). Pillen wirken noch nicht auf die Drohnen.
; Stufe 2: Punkte (10) und Pillen (50, blinken) werden beim Ueberfahren gefressen
; (Karte und Bildschirm), Punktestand und Rekord, Fresston auf AY-Kanal C (zwei
; abwechselnde Toene). Ist alles gefressen, blinken die Waende, dann beginnt das
; naechste Level. N / Leertaste / Enter ueberspringt ein Level.
; Stufe 1: Der Spieler (Roboter) laeuft pixelweise (2 Pixel je Schritt) mit Joystick 1
; (Tasten 6 7 8 9 0) oder 2 (Tasten 1 2 3 4 5, Sinclair IF2). Richtungswunsch wird
; gepuffert und an der naechsten Kachelmitte ausgefuehrt, Umkehren geht jederzeit.
; Tunnel in der mittleren Zeile. Die vier Drohnen stehen nur zur Ansicht an ihren
; Startfeldern. Zum Ausprobieren des Aussehens:
;   Wandstil: abgerundete Ecken (fest).
;   Wandfarbe: zufaellig bei jedem neuen Level.
;   P = Farbraum umschalten:
;       NORMAL    = Standardfarben (blau / cyan / magenta / gruen)
;       ERWEITERT = ULAplus (64 Farben): zufaellige Wandfarbe aus 8 Sondertoenen
;                   (orange, rosa, violett, tuerkis, limone, himmelblau, mint, purpur)
;   N, Leertaste oder Enter = neues Level simulieren (Levelzahl +1, neue Wandfarbe)
; ULAplus: Ports 0xBF3B (Register) / 0xFF3B (Daten). Auf Geraeten ohne ULAplus
; (und in Emulatoren ohne) bleibt ERWEITERT ohne Wirkung auf die Farben.
; ============================================================

        org 32768

; ---- Konstanten -------------------------------------------
MAZE_W      equ 28              ; Labyrinthbreite in Kacheln
MAZE_H      equ 21              ; Labyrinthhoehe in Kacheln
MAZE_COL    equ 2               ; Zeichenspalte der linken Kante
MAZE_ROW    equ 2               ; Zeichenzeile der oberen Kante

C_EMPTY     equ 0               ; Feldcodes in der Karte
C_WALL      equ 1
C_DOT       equ 2
C_PILL      equ 3
C_DOOR      equ 4               ; Tuer des Geisterhauses

ATTR_TEXT   equ 0x07            ; weiss auf schwarz
ATTR_HEAD   equ 0x46            ; hell gelb auf schwarz
ATTR_DOT    equ 0x47            ; Punkte und Pillen: hell weiss
ATTR_DOOR   equ 0x43            ; Tuer: hell magenta
ATTR_PLAYER equ 0x46            ; Spieler: hell gelb

M_WAIT      equ 0               ; Drohnenzustaende
M_EXIT      equ 1               ; verlaesst das Haus
M_CHASE     equ 2               ; jagt den Spieler (oder streunt zur eigenen Ecke)
M_FRIGHT    equ 3               ; verwirrt (Pille): blau, zufaellige Richtung, langsamer
M_EATEN     equ 4               ; gefressen: nur Augen, laufen zum Haus zurueck
M_ENTER     equ 5               ; Augen sinken durch die Tuer ins Haus

G_X         equ 0               ; Drohnen-Struktur (GS_SIZE Bytes je Drohne)
G_Y         equ 1
G_DIR       equ 2
G_ACC       equ 3               ; Tempo-Summe
G_SPD       equ 4               ; Schritte je 20 Frames
G_ATTR      equ 5
G_MODE      equ 6
G_TMR       equ 7               ; Freigabe in Zwei-Frame-Takten
G_CNT       equ 8               ; Schrittzaehler (Animation)
G_OC        equ 9               ; alter Bereich: Spalte, Zeile, Breite, Hoehe
G_OR        equ 10
G_OW        equ 11
G_OH        equ 12
G_OV        equ 13              ; 1 = alter Bereich gueltig
G_TYPE      equ 14              ; 0 Jaeger, 1 Abfangjaeger, 2 Flankierer, 3 Zoegerer
GS_SIZE     equ 16

GT_Y        equ (MAZE_ROW+10)*8 ; Tunnelzeile in Bildschirmpixeln

D_UP        equ 0               ; Richtungen
D_RIGHT     equ 1
D_DOWN      equ 2
D_LEFT      equ 3

PL_SPEED    equ 10              ; Schritte je 20 Frames (2 Pixel je Schritt)
PL_TTL      equ 30              ; Frames, wie lange ein Richtungswunsch gilt
PL_START_X  equ (13+MAZE_COL)*8 ; Startfeld des Spielers (Kachel 13,15) in Bildschirmpixeln
PL_START_Y  equ (15+MAZE_ROW)*8

; ---- Variablen (freier RAM, nicht im TAP) -----------------
VARS        equ 0xB000
maze        equ VARS            ; MAZE_W*MAZE_H Bytes: Feldcodes (588)
font        equ VARS + 0x300    ; 768 Bytes: Zeichensatz (Zeichen 32..127)
cur_attr    equ VARS + 0x700    ; Attribut fuer draw_cell
wall_attr   equ VARS + 0x701    ; Wandfarbe
col_mode    equ VARS + 0x702    ; 0 = Farbraum NORMAL, 1 = ERWEITERT (ULAplus)
wall_col    equ VARS + 0x703    ; Index in col_tab
key_p       equ VARS + 0x704    ; Taste P im letzten Frame
ext_col     equ VARS + 0x705    ; Index in ext_tab (Sonderton der Wand)
key_n       equ VARS + 0x706    ; Taste N im letzten Frame
level       equ VARS + 0x707    ; Levelnummer 1..99
rng         equ VARS + 0x708    ; 2 Bytes: Zufallszahl-Zustand
lvl_txt     equ VARS + 0x70A    ; 3 Bytes: Levelzahl als Text
pl_x        equ VARS + 0x710    ; Spieler: linke Kante in Bildschirmpixeln (0..248)
pl_y        equ VARS + 0x711    ; Spieler: obere Kante in Bildschirmpixeln
pl_dir      equ VARS + 0x712    ; aktuelle Richtung
pl_want     equ VARS + 0x713    ; gewuenschte Richtung
pl_ttl      equ VARS + 0x714    ; Restdauer des Wunsches
pl_acc      equ VARS + 0x715    ; Tempo-Summe (Schritt, wenn >= 20)
pl_cnt      equ VARS + 0x716    ; Schrittzaehler fuer die Animation
old_valid   equ VARS + 0x717    ; 1 = alter Bereich des Spielers muss geloescht werden
old_c       equ VARS + 0x718    ; alter Bereich: Spalte, Zeile, Breite, Hoehe (in Zeichen)
old_r       equ VARS + 0x719
old_w       equ VARS + 0x71A
old_h       equ VARS + 0x71B
dirty       equ VARS + 0x71C    ; 1 = Figuren neu zeichnen
spr_c       equ VARS + 0x720    ; Bereich der gerade gezeichneten Figur (Spalte, Zeile, Breite, Hoehe)
spr_r       equ VARS + 0x721
spr_w       equ VARS + 0x722
spr_h       equ VARS + 0x723
spr_attr    equ VARS + 0x724
spr_x       equ VARS + 0x725
spr_y       equ VARS + 0x726
era_c       equ VARS + 0x727    ; zu loeschender Bereich (Spalte, Zeile, Breite, Hoehe) fuer erase_old
era_r       equ VARS + 0x728
era_w       equ VARS + 0x729
era_h       equ VARS + 0x72A
dk_c        equ VARS + 0x72B    ; Zielmarker: neue Spalte, Zeile
dk_row      equ VARS + 0x72C
pos         equ VARS + 0x7E0    ; 5 Positionen (x, y) fuer die Ueberlappungspruefung
score       equ VARS + 0x730    ; 3 Bytes BCD, niedrigstes Byte zuerst
record      equ VARS + 0x733    ; 3 Bytes BCD
dots_left   equ VARS + 0x736    ; 2 Bytes: noch nicht gefressene Punkte und Pillen
win_flag    equ VARS + 0x738    ; 1 = alles gefressen
blink_cnt   equ VARS + 0x739    ; Frame-Zaehler fuer das Pillenblinken
blink_off   equ VARS + 0x73A    ; 1 = Pillen gerade unsichtbar
sfx_t       equ VARS + 0x73B    ; Restdauer des Fresstons in Frames
sfx_flip    equ VARS + 0x73C    ; wechselt bei jedem Punkt den Ton
sc_txt      equ VARS + 0x740    ; 7 Bytes: Zahl als Text
lives       equ VARS + 0x748    ; Leben
door_ok     equ VARS + 0x749    ; 1 = Haustuer ist passierbar (nur beim Verlassen des Hauses)
gc_cc       equ VARS + 0x750    ; Richtungswahl: aktuelle Zelle (Spalte, Zeile)
gc_rr       equ VARS + 0x751
gc_tc       equ VARS + 0x752    ; Ziel (Spalte, Zeile)
gc_tr       equ VARS + 0x753
gc_i        equ VARS + 0x754    ; Kandidat 0..3
gc_d        equ VARS + 0x755    ; Richtung des Kandidaten
gc_nc       equ VARS + 0x756    ; Nachbarzelle
gc_nr       equ VARS + 0x757
gc_bd       equ VARS + 0x758    ; beste Richtung (255 = keine)
gc_best     equ VARS + 0x759    ; 2 Bytes: bester Abstand (quadriert)
gt_pc       equ VARS + 0x75B    ; Zelle des Spielers (Spalte, Zeile)
gt_pr       equ VARS + 0x75C
key_d       equ VARS + 0x75D    ; Taste D im letzten Frame
dbg         equ VARS + 0x75E    ; 1 = Zielanzeige an
gmode       equ VARS + 0x760    ; 0 = Streuen (Ecken), 1 = Jagd
mode_idx    equ VARS + 0x761    ; Abschnitt 0..7 der Streu-/Jagdtabelle
mode_tmr    equ VARS + 0x762    ; 2 Bytes: Restdauer des Abschnitts (65535 = ohne Ende)
tm_ptr      equ VARS + 0x764    ; 2 Bytes: Zeiger auf die Abschnittsdauern der Levelklasse
fright_tmr  equ VARS + 0x766    ; 2 Bytes: Restdauer der Pillenwirkung (0 = keine)
fr_frames   equ VARS + 0x768    ; 2 Bytes: Pillendauer dieses Levels
chain       equ VARS + 0x76A    ; wie viele Drohnen seit der letzten Pille gefressen (0..3)
pl_spd      equ VARS + 0x76B    ; Spielertempo dieses Levels
gbonus      equ VARS + 0x76C    ; Zuschlag aufs Drohnentempo
fr_spd      equ VARS + 0x76D    ; Tempo verwirrter Drohnen
dot_cnt     equ VARS + 0x76E    ; gefressene Punkte seit Levelbeginn / Lebensverlust
idle_tmr    equ VARS + 0x76F    ; Frames seit dem letzten gefressenen Punkt (bis 255)
idle_lim    equ VARS + 0x770    ; ab so vielen Frames ohne Punkt wird eine Drohne freigelassen
lvl_cls     equ VARS + 0x771    ; Levelklasse 0..2
dth_f       equ VARS + 0x772    ; Bildnummer der Sterbeanimation / Spaltenzaehler
extra       equ VARS + 0x773    ; 1 = Extraleben schon vergeben
bonus_t     equ VARS + 0x774    ; 2 Bytes: Restdauer des Bonusobjekts in Frames (0 = keins da)
dots_tot    equ VARS + 0x776    ; 2 Bytes: Punkte und Pillen zu Levelbeginn
vol_lvl     equ VARS + 0x778    ; Lautstaerke 0..3 (Taste T)
vol_mul     equ VARS + 0x779    ; Faktor (Viertel) zur Lautstaerke
key_t       equ VARS + 0x77A    ; Taste T im letzten Frame
sfx_p       equ VARS + 0x77B    ; 2 Bytes: aktuelle Tonperiode des Effekts
sfx_d       equ VARS + 0x77D    ; 2 Bytes: Aenderung je Frame (Tonrutsch), vorzeichenbehaftet
snd_run     equ VARS + 0x77F    ; 1 = Sirene laeuft
dth_p       equ VARS + 0x7F6    ; 2 Bytes: Tonperiode beim Sterben
seq_n       equ VARS + 0x7F8    ; Notendauer in play_seq
intro_done  equ VARS + 0x7F9    ; 1 = Titelmelodie schon gespielt
fr_n        equ VARS + 0x7F0    ; Anzahl Kandidaten bei der Zufallswahl
fr_list     equ VARS + 0x7F1    ; die Kandidatenrichtungen (4 Bytes)
ghosts      equ VARS + 0x780    ; 4 Drohnen zu GS_SIZE Bytes
mk          equ VARS + 0x7C0    ; Zielmarker je Drohne (8 Bytes): Ziel x,y, alter Bereich c,r,w,h, gueltig

; ============================================================
; Programmstart
; ============================================================
start:
        ; 128K: 48K-BASIC-ROM einblenden (dort liegt der Zeichensatz bei 0x3D00).
        ; Zuerst 0x1FFD (+2A/+3: ROM 3), dann 0x7FFD (ROM-Bit 4 = 1).
        di
        ld bc,0x1FFD
        ld a,0x04
        out (c),a
        ld bc,0x7FFD
        ld a,0x10
        out (c),a
        ei
        xor a
        out (0xFE),a            ; Rand schwarz
        ; Zeichensatz einmal ins RAM kopieren, danach braucht das Spiel das ROM nicht mehr
        ld hl,0x3D00
        ld de,font
        ld bc,768
        ldir
        ; Voreinstellungen
        xor a
        ld (wall_col),a
        ld (ext_col),a
        ld (key_p),a
        ld (key_n),a
        ld (col_mode),a
        ld (pl_ttl),a
        ld (pl_acc),a
        ld (pl_cnt),a
        ld (old_valid),a
        ld (score),a
        ld (score+1),a
        ld (score+2),a
        ld (record),a
        ld (record+1),a
        ld (record+2),a
        ld (blink_cnt),a
        ld (sfx_t),a
        ld (sfx_flip),a
        ld (extra),a
        ld a,1
        ld (level),a
        ld a,3
        ld (lives),a
        xor a
        ld (door_ok),a
        ld (key_d),a
        ld (dbg),a
        ld hl,mk
        ld de,mk+1
        ld bc,31
        ld (hl),0
        ldir
        ld hl,0xA280
        ld (rng),hl
        call apply_space        ; ULAplus aus, falls ein Vorgaenger es angelassen hat
        call pick_color         ; Wandfarbe fuer Level 1
        call reset_level        ; Karte laden, Punkte zaehlen, Spieler an den Start
        call ay_init
        call cls
        call draw_hud
        call draw_maze
        call ready

; ---- Hauptschleife: ein Durchlauf pro Frame (50 Hz) -------
main_loop:
        halt
        call blink_pills       ; Pillenfelder (selten)
        call redraw             ; Zeichnen direkt nach HALT, mit dem Stand des letzten Frames
        call update_player      ; danach erst rechnen
        call update_ghosts
        call update_modes
        call release_check
        call check_hits
        call keys
        call sfx_tick
        call siren_tick
        call bonus_tick
        ld a,(win_flag)
        or a
        call nz,level_clear
        jr main_loop

; ============================================================
; Tasten P (Farbraum), D (Zielanzeige) und N (neues Level), nur bei neuem Druck
; ============================================================
keys:
        ld a,0xDF
        in a,(0xFE)             ; Reihe P O I U Y
        cpl
        and 0x01                ; Bit 0 = P
        ld hl,key_p
        call edge
        jr z,k_d
        ld a,(col_mode)
        xor 1
        ld (col_mode),a
        call apply_space
        call draw_foot
        call draw_maze
k_d:    ld a,0xFD
        in a,(0xFE)             ; Reihe A S D F G
        cpl
        and 0x04                ; Bit 2 = D
        ld hl,key_d
        call edge
        jr z,k_t
        ld a,(dbg)              ; Zielanzeige umschalten
        xor 1
        ld (dbg),a
        call draw_foot
        ld a,1
        ld (dirty),a
k_t:    ld a,0xFB
        in a,(0xFE)             ; Reihe Q W E R T
        cpl
        and 0x10                ; Bit 4 = T
        ld hl,key_t
        call edge
        jr z,k_n
        ld a,(vol_lvl)          ; Lautstaerke weiterschalten: aus / leise / mittel / laut
        inc a
        and 3
        ld (vol_lvl),a
        call set_vol
        call draw_foot
        call sfx_dot            ; zur Probe ein Fressgeraeusch
k_n:    ld a,0x7F
        in a,(0xFE)             ; Reihe Leertaste Sym M N B
        cpl
        and 0x09                ; Bit 3 = N, Bit 0 = Leertaste
        ld d,a
        ld a,0xBF
        in a,(0xFE)             ; Reihe Enter L K J H
        cpl
        and 0x01                ; Bit 0 = Enter
        or d                    ; N, Leertaste oder Enter
        ld hl,key_n
        call edge
        ret z
        jp new_level

; Wandfarbe aus Index in A setzen
set_color:
        ld (wall_col),a
        ld e,a
        ld d,0
        ld hl,col_tab
        add hl,de
        ld a,(hl)
        ld (wall_attr),a
        ret

; Farbraum anwenden (col_mode): ULAplus ein/aus und Wandattribut passend setzen
apply_space:
        ld a,(col_mode)
        or a
        jr nz,as_ext
        ld d,0x40               ; Modusregister
        ld e,0                  ; ULAplus aus: Standardfarben
        call ulp_set
        ld a,(wall_col)
        jr set_color
as_ext: ld d,0x40
        ld e,1                  ; ULAplus ein
        call ulp_set
        call load_pal           ; alle 64 Eintraege = Standardfarben
        call load_ext           ; die 8 Sondertoene fest in ihre Eintraege schreiben
        jp set_ext_attr

; Die 8 Wandtoene liegen dauerhaft in 8 eigenen Paletteneintraegen; beim Levelwechsel
; wird nur das Attribut gewechselt (genau wie im NORMAL-Farbraum).
load_ext:
        ld c,0
le_1:   ld b,0
        ld hl,ext_ent
        add hl,bc
        ld d,(hl)               ; Eintragsnummer
        ld hl,ext_tab
        add hl,bc
        ld e,(hl)               ; Farbe (GGGRRRBB)
        push bc
        call ulp_set
        pop bc
        inc c
        ld a,c
        cp 7
        jr nz,le_1
        ret

; Wandattribut fuer den Sonderton ext_col setzen
set_ext_attr:
        ld a,(ext_col)
        ld c,a
        ld b,0
        ld hl,ext_atr
        add hl,bc
        ld a,(hl)
        ld (wall_attr),a
        ret

; ULAplus-Register schreiben: D = Register, E = Wert
ulp_set:
        ld bc,0xBF3B
        out (c),d
        ld b,0xFF               ; BC = 0xFF3B
        out (c),e
        ret

; alle 64 Paletteeintraege auf die Standard-Spectrumfarben setzen
; Eintrag = (Flash*2+Bright)*16 + (0..7 Tinte | 8..15 Papier); Farbe = Eintrag & 7
load_pal:
        ld d,0
lp_1:   ld a,d
        and 7
        ld c,a
        ld b,0
        ld hl,std_norm
        bit 4,d                 ; Bright-Bit der Palettengruppe
        jr z,lp_2
        ld hl,std_brt
lp_2:   add hl,bc
        ld e,(hl)
        call ulp_set
        inc d
        ld a,d
        cp 64
        jr nz,lp_1
        ret

; Zufallsfarbe, immer verschieden von der bisherigen
pick_color:
        ld a,r                  ; Zeitpunkt der Eingabe als zusaetzliche Streuung
        ld hl,(rng)
        xor l
        ld l,a
        ld a,h
        or l
        jr nz,pk_1
        inc l                   ; Zustand 0 waere eine Sackgasse
pk_1:   ld (rng),hl
        call rnd
        ld c,a
        ld a,(col_mode)
        or a
        ld a,c
        jr nz,pk_ext
        ld b,3
        call mod_a
        ld b,a                  ; 0..2
        ld a,(wall_col)
        inc a
        add a,b                 ; Abstand 1..3 zur alten Farbe
        and 3
        jp set_color
pk_ext: ld b,4
        call mod_a
        ld b,a                  ; 0..3
        ld a,(ext_col)
        inc a
        add a,b                 ; Abstand 1..4 zur alten Farbe
pk_x:   cp 5
        jr c,pk_y
        sub 5
        jr pk_x
pk_y:   ld (ext_col),a
        jp set_ext_attr

; A = A mod B (B > 0)
mod_a:
        cp b
        ret c
        sub b
        jr mod_a

; 16-Bit-xorshift, out: A = Zufallszahl
rnd:
        ld hl,(rng)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (rng),hl
        ret

; Neues Level: Zahl hochzaehlen, neue Wandfarbe, Labyrinth neu zeichnen
new_level:
        ld a,(level)
        inc a
        cp 100
        jr c,nl_1
        ld a,1
nl_1:   ld (level),a
        call pick_color         ; in beiden Farbraeumen eine neue Wandfarbe
        call reset_level
        call draw_level
        call draw_maze
        jp ready

; in: A = Tastenzustand jetzt (0 = nicht gedrueckt), HL = Zeiger auf den Zustand vorher
; out: NZ = Taste wurde neu gedrueckt
edge:
        ld b,(hl)
        ld (hl),a
        ld c,a
        ld a,b
        cpl
        and c
        ret

; ============================================================
; Karte laden: Textzeichen in Feldcodes umsetzen
; ============================================================
load_maze:
        ld hl,map_text
        ld de,maze
        ld bc,MAZE_W*MAZE_H
lm_loop:
        ld a,(hl)
        inc hl
        cp "#"
        jr nz,lm_1
        ld a,C_WALL
        jr lm_st
lm_1:   cp "."
        jr nz,lm_2
        ld a,C_DOT
        jr lm_st
lm_2:   cp "o"
        jr nz,lm_3
        ld a,C_PILL
        jr lm_st
lm_3:   cp "="
        ld a,C_EMPTY            ; (ld aendert die Flags nicht)
        jr nz,lm_st
        ld a,C_DOOR
lm_st:  ld (de),a
        inc de
        dec bc
        ld a,b
        or c
        jr nz,lm_loop
        ret

; in: B = x, C = y (Kachelkoordinaten); out: HL = Adresse in maze
; erhaelt BC, DE
maze_addr:
        push de
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl               ; 4y
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl               ; 32y
        or a
        sbc hl,de               ; 28y
        ld e,b
        ld d,0
        add hl,de               ; + x
        ld de,maze
        add hl,de
        pop de
        ret

; in: B = x, C = y (auch -1 / ausserhalb); out: A = 1 offen (Gang oder ausserhalb),
; A = 0 Wand; erhaelt BC, DE
is_open:
        ld a,b
        cp MAZE_W
        jr nc,io_out            ; x ausserhalb (auch 255 = -1)
        ld a,c
        cp MAZE_H
        jr nc,io_out
        call maze_addr
        ld a,(hl)
        cp C_WALL
        ld a,0                  ; (ld aendert die Flags nicht)
        ret z                   ; Wand
io_out: ld a,1
        ret

; in: D = x, E = y einer Wandkachel
; out: A = Nachbarmaske: Bit 7 = N, 6 = NO, 5 = O, 4 = SO, 3 = S, 2 = SW, 1 = W, 0 = NW;
; ein gesetztes Bit bedeutet: der Nachbar ist offen (Gang oder ausserhalb)
; erhaelt DE; veraendert BC, HL
wall_mask:
        ld hl,nb_tab
        ld bc,8*256+0           ; B = 8 Nachbarn, C = Maske
wm_loop:
        push bc
        ld a,(hl)
        inc hl
        add a,d
        ld b,a                  ; x des Nachbarn
        ld a,(hl)
        inc hl
        add a,e
        ld c,a                  ; y des Nachbarn
        push hl
        call is_open
        pop hl
        pop bc
        sla c
        or c
        ld c,a
        djnz wm_loop
        ld a,c
        ret

; Nachbarn der Reihe nach: N, NO, O, SO, S, SW, W, NW (dx, dy; 255 = -1)
nb_tab:
        db 0,255, 1,255, 1,0, 1,1, 0,1, 255,1, 255,0, 255,255

; ============================================================
; Labyrinth zeichnen
; ============================================================
draw_maze:
        ld hl,maze
        ld e,0                  ; y
dm_row: ld d,0                  ; x
dm_col: ld a,(hl)
        push hl
        push de
        call draw_code
        pop de
        pop hl
        inc hl
        inc d
        ld a,d
        cp MAZE_W
        jr nz,dm_col
        inc e
        ld a,e
        cp MAZE_H
        jr nz,dm_row
        ld a,1
        ld (dirty),a            ; Figuren muessen danach neu gezeichnet werden
        ret

; in: A = Feldcode, D = x, E = y; zeichnet das Feld
draw_code:
        cp C_WALL
        jr z,dc_wall
        ld hl,gfx_empty
        ld b,ATTR_TEXT
        or a
        jr z,dc_draw
        ld hl,gfx_dot
        ld b,ATTR_DOT
        cp C_DOT
        jr z,dc_draw
        cp C_PILL
        jr nz,dc_door
        ld hl,gfx_pill
        ld a,(blink_off)        ; Pillen blinken
        or a
        jr z,dc_draw
        ld hl,gfx_empty
        jr dc_draw
dc_door:
        ld hl,gfx_door
        ld b,ATTR_DOOR
        jr dc_draw
dc_wall:
        call wall_mask          ; A = Maske
        ld hl,idx_round
        ld c,a
        ld b,0
        add hl,bc
        ld l,(hl)               ; Kachelnummer
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl               ; * 8
        ld bc,gfx_round
        add hl,bc
        ld a,(wall_attr)
        ld b,a
dc_draw:                        ; HL = Grafik, B = Attribut
        ld a,b
        ld (cur_attr),a
        ld a,e
        add a,MAZE_ROW
        ld b,a                  ; Zeichenzeile
        ld a,d
        add a,MAZE_COL
        ld c,a                  ; Zeichenspalte
        jp draw_cell


; ============================================================
; Joystick lesen (Sinclair IF2); out: A = Bits (aktiv = 1)
;   Bit 1 hoch, Bit 2 runter, Bit 3 rechts, Bit 4 links, Bit 0 Feuer
; Joystick 1 = Tasten 6 7 8 9 0 (Port 0xEFFE), passt direkt;
; Joystick 2 = Tasten 1 2 3 4 5 (Port 0xF7FE), Bits werden umgedreht
; ============================================================
get_joy:
        ld bc,0xEFFE
        in a,(c)
        cpl
        and 0x1F
        ld h,a
        ld bc,0xF7FE
        in a,(c)
        cpl
        and 0x1F
        ld e,a
        ld d,0
        ld b,5
gj_rev: rr e
        rl d
        djnz gj_rev
        ld a,d
        or h
        ret

; Richtungswunsch aus dem Joystick (haelt PL_TTL Frames, auch nach dem Loslassen)
read_input:
        call get_joy
        ld c,a
        ld a,(pl_want)
        ld d,a                  ; D = Wunsch (bisher)
        ld e,0                  ; E = 1, wenn eine Richtung gedrueckt ist
        bit 1,c
        jr z,ri_1
        ld d,D_UP
        ld e,1
ri_1:   bit 2,c
        jr z,ri_2
        ld d,D_DOWN
        ld e,1
ri_2:   bit 4,c
        jr z,ri_3
        ld d,D_LEFT
        ld e,1
ri_3:   bit 3,c
        jr z,ri_4
        ld d,D_RIGHT
        ld e,1
ri_4:   ld a,e
        or a
        jr z,ri_rel
        ld a,d
        ld (pl_want),a
        ld a,PL_TTL
        ld (pl_ttl),a
        ret
ri_rel: ld a,(pl_ttl)
        or a
        ret z
        dec a
        ld (pl_ttl),a
        ret nz
        ld a,(pl_dir)           ; Wunsch verfallen: einfach weiterlaufen
        ld (pl_want),a
        ret

; ============================================================
; Spieler bewegen
; ============================================================
update_player:
        call read_input
        ld a,(pl_acc)
        ld hl,pl_spd
        add a,(hl)
        cp 20
        jr c,up_st
        sub 20
        ld (pl_acc),a
        jp move_step
up_st:  ld (pl_acc),a
        ret

; ein Schritt (2 Pixel)
move_step:
        ld a,(pl_x)
        ld b,a
        ld a,(pl_y)
        or b
        and 7
        jr nz,ms_between        ; nicht auf einer Kachelmitte
        ld a,(pl_want)          ; Kachelmitte: erst den Wunsch probieren
        call can_move
        jr z,ms_cur
        ld a,(pl_want)
        ld (pl_dir),a
        jr ms_go
ms_cur: ld a,(pl_dir)
        call can_move
        ret z                   ; Wand voraus: stehen bleiben
        jr ms_go
ms_between:
        ld a,(pl_dir)           ; zwischen Kacheln nur Umkehren
        xor 2
        ld b,a
        ld a,(pl_want)
        cp b
        jr nz,ms_go
        ld (pl_dir),a
ms_go:  ld a,(pl_dir)
        or a
        jr z,ms_up
        dec a
        jr z,ms_right
        dec a
        jr z,ms_down
        ld a,(pl_x)             ; links, im Tunnel mit Umbruch
        or a
        jr nz,ms_l1
        ld a,250
ms_l1:  sub 2
        ld (pl_x),a
        jr ms_done
ms_right:
        ld a,(pl_x)
        cp 248
        jr nz,ms_r1
        ld a,254
ms_r1:  add a,2
        ld (pl_x),a
        jr ms_done
ms_up:  ld a,(pl_y)
        sub 2
        ld (pl_y),a
        jr ms_done
ms_down:
        ld a,(pl_y)
        add a,2
        ld (pl_y),a
ms_done:
        ld hl,pl_cnt
        inc (hl)
        ld a,1
        ld (dirty),a
        ld a,(pl_x)
        ld b,a
        ld a,(pl_y)
        or b
        and 7
        ret nz
        jp eat                  ; auf einer Kachelmitte: fressen

; in: A = Richtung, Spieler steht auf einer Kachelmitte
; out: NZ = Nachbarfeld ist frei
can_move:
        ld e,a
        ld a,(pl_x)
        rrca
        rrca
        rrca
        and 0x1F
        ld b,a                  ; B = Zeichenspalte
        ld a,(pl_y)
        rrca
        rrca
        rrca
        and 0x1F
        ld c,a                  ; C = Zeichenzeile
        ld a,e
        or a
        jr nz,cm_1
        dec c                   ; hoch
        jr passable
cm_1:   dec a
        jr nz,cm_2
        inc b                   ; rechts
        jr passable
cm_2:   dec a
        jr nz,cm_3
        inc c                   ; runter
        jr passable
cm_3:   dec b                   ; links

; in: B = Zeichenspalte, C = Zeichenzeile; out: NZ = Spieler darf hinein
; Ausserhalb des Labyrinths geht es nur in der Tunnelzeile.
passable:
        ld a,b
        sub MAZE_COL
        cp MAZE_W
        jr nc,pa_out
        ld d,a                  ; D = x
        ld a,c
        sub MAZE_ROW
        cp MAZE_H
        jr nc,pa_no
        ld c,a
        ld b,d
        call maze_addr
        ld a,(hl)
        cp C_WALL
        jr z,pa_no
        cp C_DOOR
        jr nz,pa_yes
        ld a,(door_ok)          ; Haustuer: nur beim Verlassen des Hauses
        or a
        ret
pa_yes: ld a,1
        or a
        ret
pa_out: ld a,c
        cp MAZE_ROW+10          ; Tunnelzeile
        jr z,pa_yes
pa_no:  xor a
        ret

; ============================================================
; Figuren zeichnen
; ============================================================
redraw:
        ld a,(dirty)
        or a
        ret z
        xor a
        ld (dirty),a
        ; Jede Figur einzeln: erst ihren alten Bereich loeschen, gleich danach neu zeichnen
        ; (so ist der Bereich nur ganz kurz leer und flackert kaum)
        ld ix,ghosts
        ld b,4
rd_g:   push bc
        call erase_ghost
        call draw_ghost
        pop bc
        ld de,GS_SIZE
        add ix,de
        djnz rd_g
        call erase_player
        call draw_player
        call check_overlap      ; zwei Figuren so nah, dass das Loeschen der einen
        call c,repair           ; die andere angekratzt haben koennte: nochmal zeichnen
        ld a,(dbg)
        or a
        jp z,erase_markers
        call draw_markers
        jp draw_player          ; Spielerfarbe wiederherstellen (der Jaeger-Marker liegt auf ihm)

; Drohne IX zeichnen und ihren Bereich merken
draw_ghost:
        ld a,(ix+G_MODE)
        cp M_EATEN
        jr c,dg_n
        ld a,0x47               ; Augen: hell weiss
        push af
        ld hl,spr_eyes
        jr dg_s
dg_n:   cp M_FRIGHT
        ld a,(ix+G_ATTR)
        jr nz,dg_f
        ld a,(fright_tmr+1)     ; verwirrt: blau, in den letzten 100 Frames blau/weiss blinkend
        or a
        ld a,0x01
        jr nz,dg_f
        ld a,(fright_tmr)
        cp 100
        ld a,0x01
        jr nc,dg_f
        ld a,(fright_tmr)
        and 8
        ld a,0x01
        jr z,dg_f
        ld a,0x07
dg_f:   push af
        ld a,(ix+G_CNT)
        rrca
        rrca
        and 1                   ; Bild 0/1
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; * 64
        ld de,spr_drone
        add hl,de
dg_s:   ld b,(ix+G_X)
        ld c,(ix+G_Y)
        pop af
        call draw_sprite
        ld a,(spr_c)
        ld (ix+G_OC),a
        ld a,(spr_r)
        ld (ix+G_OR),a
        ld a,(spr_w)
        ld (ix+G_OW),a
        ld a,(spr_h)
        ld (ix+G_OH),a
        ld (ix+G_OV),1
        ret

; Spieler zeichnen und seinen Bereich merken
draw_player:
        ld a,(pl_cnt)           ; Bild nach Richtung und Animationsschritt
        and 3
        ld e,a
        ld d,0
        ld hl,anim_seq
        add hl,de
        ld c,(hl)               ; Bild 0..2
        ld a,(pl_dir)
        ld b,a
        add a,a
        add a,b                 ; Richtung * 3
        add a,c
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; * 64 Bytes je Bild (4 Verschiebungen zu 16)
        ld de,spr_player
        add hl,de
        ld a,(pl_x)
        ld b,a
        ld a,(pl_y)
        ld c,a
        ld a,ATTR_PLAYER
        call draw_sprite
        ld hl,spr_c             ; belegten Bereich merken
        ld de,old_c
        ld bc,4
        ldir
        ld a,1
        ld (old_valid),a
        ret

; alle Figuren noch einmal zeichnen (ODER, ohne zu loeschen)
repair:
        ld ix,ghosts
        ld b,4
rp_g:   push bc
        call draw_ghost
        pop bc
        ld de,GS_SIZE
        add ix,de
        djnz rp_g
        jp draw_player

; out: Carry = zwei Figuren liegen weniger als 16 Pixel auseinander (in x und y)
check_overlap:
        ld hl,pos
        ld ix,ghosts
        ld b,4
co_f:   ld a,(ix+G_X)
        ld (hl),a
        inc hl
        ld a,(ix+G_Y)
        ld (hl),a
        inc hl
        ld de,GS_SIZE
        add ix,de
        djnz co_f
        ld a,(pl_x)
        ld (hl),a
        inc hl
        ld a,(pl_y)
        ld (hl),a
        ld ix,pos
        ld c,4
co_o:   push ix
        pop hl
        inc hl
        inc hl
        ld b,c
co_i:   ld a,(ix+0)
        sub (hl)
        jr nc,co_a
        neg
co_a:   inc hl
        cp 16
        jr nc,co_nx
        ld a,(ix+1)
        sub (hl)
        jr nc,co_b
        neg
co_b:   cp 16
        jr nc,co_nx
        scf
        ret
co_nx:  inc hl
        djnz co_i
        inc ix
        inc ix
        dec c
        jr nz,co_o
        or a
        ret

anim_seq:
        db 0,1,2,1

; alten Bereich des Spielers aus der Karte wiederherstellen
erase_old:
        ld a,(era_r)
        ld c,a
        ld a,(era_h)
        ld d,a
eo_row: ld a,(era_c)
        ld b,a
        ld a,(era_w)
        ld e,a
eo_col: push bc
        push de
        call erase_cell
        pop de
        pop bc
        inc b
        dec e
        jr nz,eo_col
        inc c
        dec d
        jr nz,eo_row
        ret

; Spieler: gemerkten Bereich loeschen (nur wenn gueltig)
erase_player:
        ld a,(old_valid)
        or a
        ret z
        ld hl,old_c
        ld de,era_c
        ld bc,4
        ldir
        jp erase_old

; Drohne IX: gemerkten Bereich loeschen (nur wenn gueltig)
erase_ghost:
        ld a,(ix+G_OV)
        or a
        ret z
        ld a,(ix+G_OC)
        ld (era_c),a
        ld a,(ix+G_OR)
        ld (era_r),a
        ld a,(ix+G_OW)
        ld (era_w),a
        ld a,(ix+G_OH)
        ld (era_h),a
        ld (ix+G_OV),0
        jp erase_old

; in: B = Zeichenspalte, C = Zeichenzeile: Feld aus der Karte neu zeichnen
; (ausserhalb des Labyrinths: leer)
erase_cell:
        ld a,b
        sub MAZE_COL
        cp MAZE_W
        jr nc,ec_blank
        ld d,a
        ld a,c
        sub MAZE_ROW
        cp MAZE_H
        jr nc,ec_blank
        ld e,a
        push de
        ld b,d
        ld c,a
        call maze_addr
        ld a,(hl)
        pop de
        jp draw_code
ec_blank:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,gfx_empty
        ld a,b
        ld b,c
        ld c,a
        jp draw_cell

; Figur zeichnen (ODER ueber den Hintergrund) und die Attribute der belegten Zellen setzen
; in: HL = 4 vorverschobene Bilder zu je 16 Bytes, B = x, C = y (Bildschirmpixel,
;     x gerade), A = Attribut
draw_sprite:
        push ix                 ; IX gehoert dem Aufrufer (Drohnen-Schleifen)
        ld (spr_attr),a
        ld a,b
        ld (spr_x),a
        ld a,c
        ld (spr_y),a
        ld a,b
        and 6
        add a,a
        add a,a
        add a,a                 ; (x & 6) * 8 = Verschiebung * 16
        ld e,a
        ld d,0
        add hl,de
        push hl
        pop ix
        ld a,(spr_x)            ; belegte Zeichenzellen
        ld b,a
        rrca
        rrca
        rrca
        and 0x1F
        ld (spr_c),a
        ld a,b
        and 7
        ld a,1
        jr z,ds_w
        inc a
ds_w:   ld (spr_w),a
        ld a,(spr_y)
        ld b,a
        rrca
        rrca
        rrca
        and 0x1F
        ld (spr_r),a
        ld a,b
        and 7
        ld a,1
        jr z,ds_h
        inc a
ds_h:   ld (spr_h),a
        ld a,(spr_r)            ; Attribute setzen
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,0x5800
        add hl,de
        ld a,(spr_c)
        ld e,a
        ld d,0
        add hl,de
        ld a,(spr_attr)
        ld c,a
        ld a,(spr_h)
        ld b,a
ds_ar:  ld (hl),c
        ld a,(spr_w)
        cp 2
        jr nz,ds_a1
        inc hl
        ld (hl),c
        dec hl
ds_a1:  ld de,32
        add hl,de
        djnz ds_ar
        ld c,0                  ; Pixelzeilen 0..7
ds_row: ld a,(spr_y)
        add a,c
        ld e,a                  ; E = Pixelzeile
        and 0xC0
        rrca
        rrca
        rrca
        ld d,a
        ld a,e
        and 7
        or d
        or 0x40
        ld h,a
        ld a,e
        and 0x38
        add a,a
        add a,a
        ld l,a
        ld a,(spr_c)
        add a,l
        ld l,a
        ld a,(ix+0)
        or (hl)
        ld (hl),a
        ld a,(spr_w)
        cp 2
        jr nz,ds_n
        inc hl
        ld a,(ix+1)
        or (hl)
        ld (hl),a
ds_n:   inc ix
        inc ix
        inc c
        ld a,c
        cp 8
        jr nz,ds_row
        pop ix
        ret


; ============================================================
; Stufe 2: Fressen, Punkte, Level-Ende, Ton
; ============================================================
; Karte laden, Punkte zaehlen, Spieler an den Start (Anfang jedes Levels)
reset_level:
        call load_maze
        call count_dots
        xor a
        ld (blink_off),a
        ld (win_flag),a
        ; (weiter mit reset_actors)

; Spieler und Drohnen an die Startfelder
reset_actors:
        xor a
        ld (pl_acc),a
        ld (pl_cnt),a
        ld (pl_ttl),a
        ld (old_valid),a
        ld a,PL_START_X
        ld (pl_x),a
        ld a,PL_START_Y
        ld (pl_y),a
        ld a,D_LEFT
        ld (pl_dir),a
        ld (pl_want),a
        ld hl,ghost_init
        ld de,ghosts
        ld bc,4*GS_SIZE
        ldir
        call set_level_params
        xor a
        ld (gmode),a            ; jedes Level / jedes Leben beginnt mit Streuen
        ld (mode_idx),a
        ld (chain),a
        ld (dot_cnt),a
        ld (idle_tmr),a
        ld h,a
        ld l,a
        ld (fright_tmr),hl
        ld (bonus_t),hl
        ld hl,(tm_ptr)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (mode_tmr),de
        ld a,(lvl_cls)          ; Freigabeschwellen der Drohnen 2..4
        ld e,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        ld hl,rel_tab
        add hl,de
        ld a,(hl)
        ld (ghosts+GS_SIZE+G_TMR),a
        inc hl
        ld a,(hl)
        ld (ghosts+2*GS_SIZE+G_TMR),a
        inc hl
        ld a,(hl)
        ld (ghosts+3*GS_SIZE+G_TMR),a
        ld a,1
        ld (dirty),a
        ret

; Tempo, Pillendauer und Zeittabelle aus der Levelnummer
set_level_params:
        ld a,(level)
        ld b,0
        cp 2
        jr c,sl_c               ; Level 1 -> Klasse 0
        inc b
        cp 5
        jr c,sl_c               ; Level 2..4 -> Klasse 1
        inc b                   ; ab Level 5 -> Klasse 2
sl_c:   ld a,b
        ld (lvl_cls),a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,lvl_tab
        add hl,de
        ld a,(hl)
        ld (pl_spd),a
        inc hl
        ld a,(hl)
        ld (gbonus),a
        inc hl
        ld a,(hl)
        ld (fr_spd),a
        inc hl
        ld a,(hl)
        ld (idle_lim),a
        ld a,(lvl_cls)          ; Zeiger auf 8 Abschnitte zu je 2 Bytes
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,tm_tab
        add hl,de
        ld (tm_ptr),hl
        ld a,(level)            ; Pillendauer: Level 1..21, danach wie 21
        cp 22
        jr c,sl_f
        ld a,21
sl_f:   dec a
        ld l,a
        ld h,0
        add hl,hl
        ld de,fr_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (fr_frames),de
        ret

count_dots:
        ld hl,maze
        ld bc,MAZE_W*MAZE_H
        ld de,0
cd_1:   ld a,(hl)
        inc hl
        cp C_DOT
        jr z,cd_c
        cp C_PILL
        jr nz,cd_n
cd_c:   inc de
cd_n:   dec bc
        ld a,b
        or c
        jr nz,cd_1
        ld (dots_left),de
        ld (dots_tot),de
        ret

; Der Spieler steht auf einer Kachelmitte: Punkt oder Pille fressen
eat:
        ld a,(pl_x)
        rrca
        rrca
        rrca
        and 0x1F
        sub MAZE_COL
        cp MAZE_W
        ret nc                  ; im Tunnel ausserhalb: nichts zu fressen
        ld b,a
        ld a,(pl_y)
        rrca
        rrca
        rrca
        and 0x1F
        sub MAZE_ROW
        cp MAZE_H
        ret nc
        ld c,a
        ld hl,(bonus_t)         ; Bonusobjekt (Kachel 13/14, Zeile 13) aufgesammelt?
        ld a,h
        or l
        jr z,ea_nb
        ld a,c
        cp 13
        jr nz,ea_nb
        ld a,b
        cp 13
        jr z,ea_bo
        cp 14
        jr nz,ea_nb
ea_bo:  push bc
        call bonus_eat
        pop bc
ea_nb:  call maze_addr
        ld a,(hl)
        cp C_DOT
        jr z,ea_dot
        cp C_PILL
        ret nz
        ld (hl),C_EMPTY
        call sfx_pill
        call start_fright
        ld a,0x50
        jr ea_sc
ea_dot: ld (hl),C_EMPTY
        call sfx_dot
        ld a,0x10
ea_sc:  call add_score
        ld a,(dot_cnt)          ; fuer die Freigabe der Drohnen mitzaehlen
        inc a
        jr z,ea_i
        ld (dot_cnt),a
ea_i:   xor a
        ld (idle_tmr),a
        ld hl,(dots_left)
        dec hl
        ld (dots_left),hl
        push hl
        call bonus_check
        pop hl
        ld a,h
        or l
        ret nz
        ld a,1
        ld (win_flag),a
        ret

; in: A = Punkte in Hundertern (BCD, 0x02 = 200)
add_score100:
        ld hl,score+1
        add a,(hl)
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        jp score_post

; in: A = Punkte (BCD, 0x10 / 0x50); aktualisiert Punktestand und Rekord
add_score:
        ld hl,score
        add a,(hl)
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
score_post:
        ld a,(extra)            ; Extraleben bei 10000 Punkten (einmal)
        or a
        jr nz,sp_r
        ld a,(score+2)
        or a
        jr z,sp_r
        ld a,1
        ld (extra),a
        ld a,(lives)
        cp 9
        jr nc,sp_r
        inc a
        ld (lives),a
        call draw_lives
        ld hl,tune_extra
        call play_seq
sp_r:   ld a,(score+2)          ; Rekord = max(Rekord, Punkte)
        ld b,a
        ld a,(record+2)
        cp b
        jr c,as_new
        jr nz,draw_score
        ld a,(score+1)
        ld b,a
        ld a,(record+1)
        cp b
        jr c,as_new
        jr nz,draw_score
        ld a,(score)
        ld b,a
        ld a,(record)
        cp b
        jr nc,draw_score
as_new: ld hl,score
        ld de,record
        ld bc,3
        ldir
        ; (weiter mit draw_score)

draw_score:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,score+2
        ld de,sc_txt
        call bcd_txt
        ld hl,sc_txt
        ld bc,1*256+2
        call print_at
        ld hl,record+2
        ld de,sc_txt
        call bcd_txt
        ld hl,sc_txt
        ld bc,1*256+12
        jp print_at

; in: HL = hoechstes Byte einer 3-Byte-BCD-Zahl, DE = Zielpuffer (7 Bytes)
bcd_txt:
        ld b,3
bt_1:   ld a,(hl)
        dec hl
        push af
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,"0"
        ld (de),a
        inc de
        pop af
        and 15
        add a,"0"
        ld (de),a
        inc de
        djnz bt_1
        xor a
        ld (de),a
        ret

; Pillen blinken (alle 16 Frames umschalten)
blink_pills:
        ld hl,blink_cnt
        inc (hl)
        ld a,(hl)
        and 15
        ret nz
        ld a,(blink_off)
        xor 1
        ld (blink_off),a
        ld hl,maze
        ld e,0
bp_r:   ld d,0
bp_c:   ld a,(hl)
        cp C_PILL
        jr nz,bp_n
        push hl
        push de
        call draw_code
        pop de
        pop hl
bp_n:   inc hl
        inc d
        ld a,d
        cp MAZE_W
        jr nz,bp_c
        inc e
        ld a,e
        cp MAZE_H
        jr nz,bp_r
        ld a,1
        ld (dirty),a            ; Figuren danach neu zeichnen
        ret

; Alles gefressen: Waende blinken, dann naechstes Level
level_clear:
        call siren_off
        ld hl,tune_clear
        call play_seq
        xor a
        ld (win_flag),a
        ld e,25
lc_w:   halt
        dec e
        jr nz,lc_w
        ld e,6
lc_1:   push de
        ld a,e
        and 1
        ld a,0x47
        jr nz,lc_2
        ld a,(wall_attr)
lc_2:   call set_wall_attr
        ld b,8
lc_3:   halt
        djnz lc_3
        pop de
        dec e
        jr nz,lc_1
        jp new_level

; in: A = Attribut: alle Wandzellen umfaerben
set_wall_attr:
        ld (cur_attr),a
        ld hl,maze
        ld de,0x5800+MAZE_ROW*32+MAZE_COL
        ld c,MAZE_H
swa_r:  push de
        ld b,MAZE_W
swa_c:  ld a,(hl)
        cp C_WALL
        jr nz,swa_n
        ld a,(cur_attr)
        ld (de),a
swa_n:  inc hl
        inc de
        djnz swa_c
        pop de
        push hl
        ld hl,32
        add hl,de
        ex de,hl
        pop hl
        dec c
        jr nz,swa_r
        ret

; ---- AY-3-8912: Fresston auf Kanal C ----
; D = Register, E = Wert
ay_wr:
        ld bc,0xFFFD
        out (c),d
        ld b,0xBF
        out (c),e
        ret

ay_init:
        ld d,7
        ld e,0x3A               ; Ton A (Sirene) und Ton C (Effekte), kein Rauschen
        call ay_wr
        ld d,10
        ld e,0
        call ay_wr
        ld d,8
        ld e,0
        call ay_wr
        xor a
        ld (key_t),a
        ld (snd_run),a
        ld (intro_done),a
        ld (sfx_t),a
        ld h,a
        ld l,a
        ld (sfx_d),hl
        ld a,1                  ; Vorgabe: leise
        ld (vol_lvl),a
        ; (weiter mit set_vol)

set_vol:
        ld a,(vol_lvl)
        ld e,a
        ld d,0
        ld hl,vol_tab
        add hl,de
        ld a,(hl)
        ld (vol_mul),a
        ret
vol_tab:
        db 0,4,8,12

; in: A = Grundlautstaerke 0..15; out: A = mit der gewaehlten Lautstaerke skaliert (max. 15)
vol_sc:
        ld c,a
        ld a,(vol_mul)
        ld b,a
        or a
        ret z
        xor a
vs_l:   add a,c
        djnz vs_l
        srl a
        srl a
        cp 16
        ret c
        ld a,15
        ret

sfx_dot:
        ld a,(sfx_flip)
        xor 1
        ld (sfx_flip),a
        ld hl,200               ; zwei abwechselnde Toene
        jr z,sd_1
        ld hl,150
sd_1:   ld bc,0x0404            ; Lautstaerke 4, 4 Frames
        jr sfx_go
sfx_pill:
        ld hl,600               ; Ton rutscht nach oben
        ld bc,0x0E06
        call sfx_go
        ld hl,-20
        ld (sfx_d),hl
        ret

; HL = Tonperiode, B = Dauer in Frames, C = Lautstaerke (Kanal C)
sfx_go: ld a,b
        ld (sfx_t),a
        ld (sfx_p),hl
        ld hl,0
        ld (sfx_d),hl
        push bc
        call sfx_tone
        pop bc
        ld a,c
        call vol_sc
        ld e,a
        ld d,10
        jp ay_wr

sfx_tone:
        ld hl,(sfx_p)
        ld d,4
        ld e,l
        call ay_wr
        ld d,5
        ld a,(sfx_p+1)
        ld e,a
        jp ay_wr

sfx_tick:
        ld a,(sfx_t)
        or a
        ret z
        dec a
        ld (sfx_t),a
        jr z,st_off
        ld hl,(sfx_d)
        ld a,h
        or l
        ret z
        ld de,(sfx_p)
        add hl,de
        ld (sfx_p),hl
        jp sfx_tone
st_off: ld d,10
        ld e,0                  ; Ton aus
        jp ay_wr

; Melodie spielen und warten: HL = Tabelle (Periode, Dauer in Frames >= 2; Ende mit Periode 0)
play_seq:
ps_n:   ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        ret z
        ld a,(hl)
        inc hl
        ld (seq_n),a
        push hl
        ld (sfx_p),de
        call sfx_tone
        ld a,8
        call vol_sc
        ld e,a
        ld d,10
        call ay_wr
ps_w:   halt
        ld a,(seq_n)
        dec a
        ld (seq_n),a
        cp 1
        jr nz,ps_w
        ld d,10                 ; kurze Luecke zwischen den Noten
        ld e,0
        call ay_wr
        halt
        pop hl
        jr ps_n

; Sirene (Kanal A): Hoehe je nach Lage, steigt mit den gefressenen Punkten
siren_tick:
        ld a,(snd_run)
        or a
        ret z
        ld hl,ghosts+G_MODE     ; Augen unterwegs: schnelles Piepen
        ld de,GS_SIZE
        ld b,4
sr_g:   ld a,(hl)
        cp M_EATEN
        jr nc,sr_eyes
        add hl,de
        djnz sr_g
        ld hl,(fright_tmr)
        ld a,h
        or l
        jr nz,sr_fr
        ld a,(blink_cnt)        ; normal: Dreieckschwingung, Grundton steigt mit den Punkten
        and 31
        cp 16
        jr c,sr_t
        cpl
        and 15
sr_t:   ld c,a
        add a,a
        add a,c
        add a,a                 ; * 6
        ld e,a
        ld d,0
        ld hl,(dots_tot)
        ld bc,(dots_left)
        or a
        sbc hl,bc               ; gefressene Punkte
        ld a,h
        add a,a
        add a,a
        ld b,a
        ld a,l
        rlca
        rlca
        and 3
        add a,b                 ; Stufe = gefressen / 64
        cp 4
        jr c,sr_s
        ld a,3
sr_s:   ld c,a
        add a,a
        add a,a
        add a,c
        add a,a
        add a,a
        add a,a                 ; Stufe * 40
        ld c,a
        ld hl,420
        ld b,0
        or a
        sbc hl,bc               ; 420 - Stufe*40
        add hl,de               ; + Dreieck
        ld a,(gmode)
        or a
        jr nz,sr_w
        ld bc,30                ; Streuphase etwas tiefer
        add hl,bc
sr_w:   ld a,3
        jr sr_out
sr_fr:  ld a,(blink_cnt)        ; verwirrt: Trillern
        and 8
        ld hl,270
        jr z,sr_f2
        ld hl,330
sr_f2:  ld a,4
        jr sr_out
sr_eyes:
        ld a,(blink_cnt)
        and 4
        ld hl,150
        jr z,sr_e2
        ld hl,110
sr_e2:  ld a,5
sr_out: push af
        ld d,0
        ld e,l
        call ay_wr
        ld d,1
        ld e,h
        call ay_wr
        pop af
        call vol_sc
        ld e,a
        ld d,8
        jp ay_wr

siren_off:
        xor a
        ld (snd_run),a
        ld d,8
        ld e,0
        jp ay_wr

; alle alten Bereiche (Spieler, Drohnen, Zielmarker) aus der Karte wiederherstellen
erase_all:
        call erase_player
        xor a
        ld (old_valid),a
        ld ix,ghosts
        ld b,4
ea_l:   push bc
        call erase_ghost
        pop bc
        ld de,GS_SIZE
        add ix,de
        djnz ea_l
        jp erase_markers

; ============================================================
; Drohnen
; ============================================================
update_ghosts:
        ld ix,ghosts
        ld b,4
ug_l:   push bc
        call update_ghost
        pop bc
        ld de,GS_SIZE
        add ix,de
        djnz ug_l
        ret

; IX = Drohne
update_ghost:
        ld a,(ix+G_MODE)
        or a
        ret z                   ; wartet im Haus (Freigabe: release_check)
        cp M_EATEN
        ld a,20
        jr nc,ug_a              ; Augen: ein Schritt je Frame
        ld a,(ix+G_Y)           ; im Tunnel langsamer
        cp GT_Y
        jr nz,ug_n
        ld a,(ix+G_X)
        cp 33
        jr c,ug_slow
        cp 216
        jr c,ug_n
ug_slow:
        ld a,4
        jr ug_a
ug_n:   ld a,(ix+G_MODE)
        cp M_FRIGHT
        ld a,(fr_spd)
        jr z,ug_a
        ld a,(gbonus)
        add a,(ix+G_SPD)
ug_a:   add a,(ix+G_ACC)
        cp 20
        jr c,ug_st
        sub 20
        ld (ix+G_ACC),a
        jp ghost_step
ug_st:  ld (ix+G_ACC),a
        ret

; ---- Streu-/Jagdzeiten, Pillenwirkung, Freigabe ------------------------------------
; einmal je Frame
update_modes:
        ld hl,(fright_tmr)
        ld a,h
        or l
        jr z,um_mode
        dec hl                  ; waehrend der Pillenwirkung steht die Streu-/Jagduhr still
        ld (fright_tmr),hl
        ld a,l
        and 7
        jr nz,um_f1
        ld a,1                  ; alle 8 Frames neu zeichnen (Blinken)
        ld (dirty),a
um_f1:  ld a,h
        or l
        ret nz
        ; (weiter mit end_fright)

; Pillenwirkung vorbei: verwirrte Drohnen jagen wieder
end_fright:
        ld ix,ghosts
        ld b,4
ef_l:   ld a,(ix+G_MODE)
        cp M_FRIGHT
        jr nz,ef_n
        ld (ix+G_MODE),M_CHASE
ef_n:   ld de,GS_SIZE
        add ix,de
        djnz ef_l
        ld a,1
        ld (dirty),a
        ret

um_mode:
        ld hl,(mode_tmr)
        ld a,h
        and l
        inc a
        ret z                   ; 65535 = ohne Ende
        dec hl
        ld (mode_tmr),hl
        ld a,h
        or l
        ret nz
        ld a,(mode_idx)         ; naechster Abschnitt: gerade = Streuen, ungerade = Jagd
        inc a
        ld (mode_idx),a
        ld c,a
        and 1
        ld (gmode),a
        ld a,c
        add a,a
        ld e,a
        ld d,0
        ld hl,(tm_ptr)
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (mode_tmr),de
        ld ix,ghosts            ; alle jagenden Drohnen kehren um
        ld b,4
um_l:   ld a,(ix+G_MODE)
        cp M_CHASE
        jr nz,um_n
        ld a,(ix+G_DIR)
        xor 2
        ld (ix+G_DIR),a
um_n:   ld de,GS_SIZE
        add ix,de
        djnz um_l
        ret

; Pille gefressen: jagende Drohnen werden verwirrt und kehren um
start_fright:
        ld hl,(fr_frames)
        ld a,h
        or l
        ret z                   ; in diesem Level wirkt die Pille nicht
        ld (fright_tmr),hl
        xor a
        ld (chain),a
        push ix
        ld ix,ghosts
        ld b,4
sf_l:   ld a,(ix+G_MODE)
        cp M_CHASE
        jr nz,sf_n
        ld (ix+G_MODE),M_FRIGHT
        ld a,(ix+G_DIR)
        xor 2
        ld (ix+G_DIR),a
sf_n:   ld de,GS_SIZE
        add ix,de
        djnz sf_l
        pop ix
        ld a,1
        ld (dirty),a
        ret

; Drohnen im Haus freilassen: die naechste wartende, wenn genug Punkte gefressen sind
; oder zu lange kein Punkt gefressen wurde
release_check:
        ld a,(idle_tmr)
        inc a
        jr z,rc_0
        ld (idle_tmr),a
rc_0:   ld ix,ghosts+GS_SIZE
        ld b,3
rc_l:   ld a,(ix+G_MODE)
        or a
        jr z,rc_w
        ld de,GS_SIZE
        add ix,de
        djnz rc_l
        ret
rc_w:   ld a,(dot_cnt)          ; nur die erste wartende Drohne kommt in Frage
        cp (ix+G_TMR)
        jr nc,rc_go
        ld a,(idle_tmr)
        ld hl,idle_lim
        cp (hl)
        ret c
rc_go:  ld (ix+G_MODE),M_EXIT
        ld (ix+G_DIR),D_UP
        xor a
        ld (idle_tmr),a
        ret

; verwirrte Drohne IX gefressen
eat_ghost:
        ld (ix+G_MODE),M_EATEN
        ld a,(chain)
        ld e,a
        ld d,0
        ld hl,chain_tab
        add hl,de
        ld a,(hl)
        push ix
        call add_score100
        pop ix
        ld a,(chain)
        cp 3
        jr nc,eg_s
        inc a
        ld (chain),a
eg_s:   ld hl,500
        ld bc,0x1008
        call sfx_go
        ld hl,-25
        ld (sfx_d),hl
        ld a,1
        ld (dirty),a
        ret

; verwirrte Drohne: an der Kachelmitte zufaellig eine der freien Richtungen (ohne Umkehren)
choose_random:
        xor a
        ld (fr_n),a
        ld (gc_i),a
cr_l:   ld a,(gc_i)
        ld e,a
        ld d,0
        ld hl,cand_dirs
        add hl,de
        ld a,(hl)
        ld (gc_d),a
        ld b,a
        ld a,(ix+G_DIR)
        xor 2
        cp b
        jr z,cr_n
        ld a,(gc_cc)
        ld b,a
        ld a,(gc_rr)
        ld c,a
        ld a,(gc_d)
        call apply_dir
        ld a,b
        and 0x1F
        ld b,a
        call passable
        jr z,cr_n
        ld a,(fr_n)
        ld e,a
        ld d,0
        ld hl,fr_list
        add hl,de
        ld a,(gc_d)
        ld (hl),a
        ld a,(fr_n)
        inc a
        ld (fr_n),a
cr_n:   ld a,(gc_i)
        inc a
        ld (gc_i),a
        cp 4
        jr nz,cr_l
        ld a,(fr_n)
        or a
        jr z,cr_rev
        ld b,a
        call rnd
        call mod_a
        ld e,a
        ld d,0
        ld hl,fr_list
        add hl,de
        ld a,(hl)
        ld (ix+G_DIR),a
        ret
cr_rev: ld a,(ix+G_DIR)         ; Sackgasse: umkehren
        xor 2
        ld (ix+G_DIR),a
        ret

; ein Schritt (2 Pixel); auf einer Kachelmitte zuerst die Richtung waehlen
ghost_step:
        ld a,(ix+G_X)
        or (ix+G_Y)
        and 7
        call z,ghost_choose
        ld a,(ix+G_DIR)
        or a
        jr z,gs_up
        dec a
        jr z,gs_r
        dec a
        jr z,gs_d
        ld a,(ix+G_X)           ; links, im Tunnel mit Umbruch
        or a
        jr nz,gs_l1
        ld a,250
gs_l1:  sub 2
        ld (ix+G_X),a
        jr gs_done
gs_r:   ld a,(ix+G_X)
        cp 248
        jr nz,gs_r1
        ld a,254
gs_r1:  add a,2
        ld (ix+G_X),a
        jr gs_done
gs_up:  ld a,(ix+G_Y)
        sub 2
        ld (ix+G_Y),a
        jr gs_done
gs_d:   ld a,(ix+G_Y)
        add a,2
        ld (ix+G_Y),a
gs_done:
        inc (ix+G_CNT)
        ld a,1
        ld (dirty),a
        ld a,(ix+G_MODE)
        cp M_EXIT
        jr z,gd_ex
        cp M_EATEN
        jr z,gd_eat
        cp M_ENTER
        ret nz
        ld a,(ix+G_Y)           ; Augen im Haus angekommen: gleich wieder hinaus
        cp 96
        ret c
        ld (ix+G_MODE),M_EXIT
        ld (ix+G_DIR),D_UP
        ret
gd_ex:  ld a,(ix+G_Y)           ; draussen vor dem Haus: jagen
        cp 73
        ret nc
        ld (ix+G_MODE),M_CHASE
        ret
gd_eat: ld a,(ix+G_Y)           ; Augen ueber der Haustuer: hinein
        cp 72
        ret nz
        ld a,(ix+G_X)
        cp 120
        jr z,gd_in
        cp 128
        ret nz
gd_in:  ld (ix+G_MODE),M_ENTER
        ret

; Richtung an einer Kachelmitte waehlen (IX = Drohne): von den Nachbarfeldern (ohne Umkehren,
; Reihenfolge hoch, links, runter, rechts) das mit dem kleinsten Abstand zum Ziel
ghost_choose:
        ld a,(ix+G_X)
        rrca
        rrca
        rrca
        and 0x1F
        ld (gc_cc),a
        ld a,(ix+G_Y)
        rrca
        rrca
        rrca
        and 0x1F
        ld (gc_rr),a
        ld a,(ix+G_MODE)
        cp M_FRIGHT
        jp z,choose_random      ; verwirrt: keine Zielwahl
        cp M_EXIT
        jr z,gc_ex
        cp M_EATEN
        jr z,gc_eat
        cp M_ENTER
        jr z,gc_ent
        call ghost_target       ; Ziel je nach Drohnenart
        jr gc_t2
gc_ex:  ld a,7                  ; Verlassen des Hauses: Ziel ueber der Tuer
        jr gc_dr
gc_eat: ld a,9                  ; Augen: Ziel direkt vor der Tuer (Tuer noch zu)
        ld (gc_tr),a
        ld a,15
        ld (gc_tc),a
        jr gc_t2
gc_ent: ld a,12                 ; Augen: Ziel mitten im Haus (Tuer offen)
gc_dr:  ld (gc_tr),a
        ld a,15
        ld (gc_tc),a
        ld a,1
        ld (door_ok),a
gc_t2:  call mk_addr            ; Ziel fuer die Anzeige merken
        ld a,(gc_tc)
        ld (hl),a
        inc hl
        ld a,(gc_tr)
        ld (hl),a
        ld hl,0xFFFF
        ld (gc_best),hl
        ld a,0xFF
        ld (gc_bd),a
        xor a
        ld (gc_i),a
gc_l:   ld a,(gc_i)
        ld e,a
        ld d,0
        ld hl,cand_dirs
        add hl,de
        ld a,(hl)
        ld (gc_d),a
        ld b,a
        ld a,(ix+G_DIR)
        xor 2                   ; Umkehr ausschliessen
        cp b
        jr z,gc_next
        ld a,(gc_cc)
        ld b,a
        ld a,(gc_rr)
        ld c,a
        ld a,(gc_d)
        call apply_dir
        ld a,b
        and 0x1F                ; im Tunnel umbrechen
        ld b,a
        ld (gc_nc),a
        ld a,c
        ld (gc_nr),a
        call passable
        jr z,gc_next
        ld a,(gc_nc)            ; Abstand (dx*dx + dy*dy) zum Ziel
        ld b,a
        ld a,(gc_tc)
        sub b
        jr nc,gc_x
        neg
gc_x:   ld e,a
        ld d,0
        ld hl,sq_tab
        add hl,de
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld a,(gc_nr)
        ld b,a
        ld a,(gc_tr)
        sub b
        jr nc,gc_y
        neg
gc_y:   ld e,a
        ld d,0
        ld hl,sq_tab
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        pop de
        add hl,de
        push hl
        ld de,(gc_best)
        or a
        sbc hl,de
        pop hl
        jr nc,gc_next           ; nur echt kleiner gewinnt (Reihenfolge entscheidet bei Gleichstand)
        ld (gc_best),hl
        ld a,(gc_d)
        ld (gc_bd),a
gc_next:
        ld a,(gc_i)
        inc a
        ld (gc_i),a
        cp 4
        jp nz,gc_l
        xor a
        ld (door_ok),a
        ld a,(gc_bd)
        cp 0xFF
        jr nz,gc_set
        ld a,(ix+G_DIR)         ; Sackgasse: umkehren
        xor 2
gc_set: ld (ix+G_DIR),a
        ret


; HL = Markerplatz der Drohne IX
mk_addr:
        ld a,(ix+G_TYPE)
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,mk
        add hl,de
        ret

; Ziel der Drohne IX in der Jagd -> gc_tc, gc_tr (Zeichenzellen, auf 0..31 begrenzt)
ghost_target:
        ld a,(gmode)
        or a
        jr nz,gt_chs
        ld a,(ix+G_TYPE)        ; Streuphase: jede Drohne zu ihrer Ecke
        add a,a
        ld e,a
        ld d,0
        ld hl,scat_tab
        add hl,de
        ld b,(hl)
        inc hl
        ld c,(hl)
        jp gt_set
gt_chs: ld a,(pl_x)
        rrca
        rrca
        rrca
        and 0x1F
        ld (gt_pc),a
        ld a,(pl_y)
        rrca
        rrca
        rrca
        and 0x1F
        ld (gt_pr),a
        ld a,(ix+G_TYPE)
        or a
        jr z,gt_pl
        dec a
        jr z,gt_a4
        dec a
        jr z,gt_fl
        ; Zoegerer: weit weg -> Spieler, nah -> eigene Ecke
        ld a,(gc_cc)
        ld b,a
        ld a,(gt_pc)
        sub b
        jr nc,gt_z1
        neg
gt_z1:  ld e,a
        ld d,0
        ld hl,sq_tab
        add hl,de
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld a,(gc_rr)
        ld b,a
        ld a,(gt_pr)
        sub b
        jr nc,gt_z2
        neg
gt_z2:  ld e,a
        ld d,0
        ld hl,sq_tab
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        pop de
        add hl,de
        ld de,65                ; Abstand^2 < 65 = naeher als 8 Felder
        or a
        sbc hl,de
        jr c,gt_corner
gt_pl:  ld a,(gt_pc)
        ld b,a
        ld a,(gt_pr)
        ld c,a
        jr gt_set
gt_corner:
        ld b,2
        ld c,23
        jr gt_set
gt_a4:  ld a,4
        call gt_ahead
        jr gt_set
gt_fl:  ld a,2
        call gt_ahead           ; B, C = 2 Felder vor dem Spieler
        ld a,(ghosts+G_X)       ; Jaeger (Drohne 0)
        rrca
        rrca
        rrca
        and 0x1F
        ld d,a
        ld a,(ghosts+G_Y)
        rrca
        rrca
        rrca
        and 0x1F
        ld e,a
        ld a,b                  ; Ziel = 2 * Punkt - Jaeger
        add a,a
        sub d
        ld b,a
        ld a,c
        add a,a
        sub e
        ld c,a
gt_set: ld a,b
        call clamp31
        ld (gc_tc),a
        ld a,c
        call clamp31
        ld (gc_tr),a
        ret

; in: A = Anzahl Felder; out: B, C = Spielerzelle + A Felder in Laufrichtung (vorzeichenbehaftet)
gt_ahead:
        ld c,a
        ld a,(pl_dir)
        add a,a
        ld e,a
        ld d,0
        ld hl,dirvec
        add hl,de
        ld b,(hl)               ; dx
        inc hl
        ld e,(hl)               ; dy
        ld a,(gt_pc)
        ld h,a
        ld a,(gt_pr)
        ld l,a
ga_l:   ld a,h
        add a,b
        ld h,a
        ld a,l
        add a,e
        ld l,a
        dec c
        jr nz,ga_l
        ld b,h
        ld c,l
        ret

; A (vorzeichenbehaftet) auf 0..31 begrenzen
clamp31:
        bit 7,a
        jr z,cl_1
        xor a
        ret
cl_1:   cp 32
        ret c
        ld a,31
        ret

dirvec:
        db 0,255, 1,0, 0,1, 255,0       ; hoch, rechts, runter, links (dx, dy)

; Zielmarker zeichnen: ein Marker wird nur geloescht, wenn sein Ziel wandert; sonst einfach
; nochmal darueber gezeichnet (ODER) - das flackert nicht
draw_markers:
        ld ix,ghosts
        ld b,4
dk_l:   push bc
        ld a,(ix+G_MODE)
        or a
        jr z,dk_n               ; wartende Drohnen haben noch kein Ziel
        call mk_addr
        ld a,(hl)
        ld (dk_c),a
        inc hl
        ld a,(hl)
        cp 2                    ; Marker nur im Bereich des Labyrinths (Zeilen 2..22)
        jr nc,dk_a
        ld a,2
dk_a:   cp 23
        jr c,dk_b
        ld a,22
dk_b:   ld (dk_row),a
        call mk_addr
        push hl
        ld de,6
        add hl,de
        ld a,(hl)               ; alter Marker gueltig?
        pop hl
        or a
        jr z,dk_draw
        inc hl
        inc hl                  ; HL -> alte Spalte
        ld a,(dk_c)
        cp (hl)
        jr nz,dk_er
        inc hl
        ld a,(dk_row)
        cp (hl)
        jr z,dk_draw            ; gleiches Feld: nicht loeschen
        dec hl
dk_er:  ld de,era_c
        ld bc,4
        ldir
        call erase_old
dk_draw:
        ld a,(dk_c)
        add a,a
        add a,a
        add a,a
        ld b,a
        ld a,(dk_row)
        add a,a
        add a,a
        add a,a
        ld c,a
        ld a,(ix+G_ATTR)
        ld hl,mark_gfx
        call draw_sprite
        call mk_addr
        inc hl
        inc hl
        ex de,hl
        ld hl,spr_c
        ld bc,4
        ldir
        ex de,hl
        ld (hl),1
dk_n:   pop bc
        ld de,GS_SIZE
        add ix,de
        djnz dk_l
        ret

; alle Zielmarker aus der Karte wegzeichnen
erase_markers:
        ld ix,ghosts
        ld b,4
em_l:   push bc
        call mk_addr
        push hl
        ld de,6
        add hl,de
        ld a,(hl)
        ld (hl),0
        pop hl
        or a
        jr z,em_n
        inc hl
        inc hl
        ld de,era_c
        ld bc,4
        ldir
        call erase_old
em_n:   pop bc
        ld de,GS_SIZE
        add ix,de
        djnz em_l
        ret

mark_gfx:
        db 0x00,0x00, 0x18,0x00, 0x24,0x00, 0x42,0x00, 0x42,0x00, 0x24,0x00, 0x18,0x00, 0x00,0x00

; in: A = Richtung, B = Spalte, C = Zeile; out: B, C = Nachbarfeld
apply_dir:
        or a
        jr nz,ad_1
        dec c
        ret
ad_1:   dec a
        jr nz,ad_2
        inc b
        ret
ad_2:   dec a
        jr nz,ad_3
        inc c
        ret
ad_3:   dec b
        ret

cand_dirs:
        db D_UP,D_LEFT,D_DOWN,D_RIGHT

; Beruehrung Spieler - Drohne
check_hits:
        ld ix,ghosts
        ld b,4
ch_l:   ld a,(ix+G_MODE)
        or a
        jr z,ch_n               ; wartende Drohnen im Haus: nein
        cp M_EATEN
        jr nc,ch_n              ; Augen sind harmlos
        ld a,(pl_x)
        sub (ix+G_X)
        jr nc,ch_1
        neg
ch_1:   cp 6
        jr nc,ch_n
        ld a,(pl_y)
        sub (ix+G_Y)
        jr nc,ch_2
        neg
ch_2:   cp 6
        jr nc,ch_n
        ld a,(ix+G_MODE)
        cp M_FRIGHT
        jp nz,life_lost
        push bc                 ; verwirrte Drohne: fressen
        call eat_ghost
        pop bc
ch_n:   ld de,GS_SIZE
        add ix,de
        djnz ch_l
        ret

; Leben verlieren (noch ohne Animation): kurze Pause, alle an den Start
life_lost:
        call siren_off
        ld b,30                 ; kurz einfrieren
ll_p:   halt
        djnz ll_p
        call bonus_hide
        call erase_all          ; Drohnen verschwinden, der Roboter zerfaellt
        call death_anim
        ld a,(lives)
        dec a
        ld (lives),a
        jp z,game_over
        call draw_lives
        call reset_actors
        jp ready

; Sterbeanimation an der Stelle des Roboters
death_anim:
        ld hl,180               ; Ton faellt waehrend des Zerfalls
        ld (dth_p),hl
        xor a
        ld (sfx_t),a
        ld a,9
        call vol_sc
        ld e,a
        ld d,10
        call ay_wr
        xor a
da_l:   ld (dth_f),a
        call erase_player
        ld a,(dth_f)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; * 64
        ld de,spr_death
        add hl,de
        ld a,(pl_x)
        ld b,a
        ld a,(pl_y)
        ld c,a
        ld a,ATTR_PLAYER
        call draw_sprite
        ld hl,spr_c
        ld de,old_c
        ld bc,4
        ldir
        ld a,1
        ld (old_valid),a
        ld b,8
da_w:   halt
        push bc
        ld hl,(dth_p)
        ld de,10
        add hl,de
        ld (dth_p),hl
        ld (sfx_p),hl
        call sfx_tone
        pop bc
        djnz da_w
        ld a,(dth_f)
        inc a
        cp 6
        jr nz,da_l
        ld d,10
        ld e,0
        call ay_wr
        jp erase_player

; BEREIT!-Pause: Figuren stehen am Start, Text unter dem Haus
ready:
        ld a,1
        ld (dirty),a
        call redraw
        ld a,ATTR_HEAD
        ld (cur_attr),a
        ld hl,txt_bereit
        ld bc,15*256+13
        call print_at
        ld a,(intro_done)       ; beim ersten Mal die Titelmelodie, sonst zwei Sekunden Stille
        or a
        jr nz,rdy_n
        ld a,1
        ld (intro_done),a
        ld hl,tune_intro
        call play_seq
        jr rdy_x
rdy_n:  ld b,100
rdy_w:  halt
        djnz rdy_w
rdy_x:  ld a,1
        ld (snd_run),a
        ld a,13
        ld b,7
        jp clr15

; B Felder der Zeile 15 ab Spalte A aus der Karte neu zeichnen
clr15:  ld (dth_f),a
c15_l:  push bc
        ld a,(dth_f)
        ld b,a
        ld c,15
        call erase_cell
        ld a,(dth_f)
        inc a
        ld (dth_f),a
        pop bc
        djnz c15_l
        ret

; ---- Bonusobjekt (Kachel 13/13 = Zeichenfeld 15/15) ----
; HL = verbleibende Punkte: nach 70 und 170 gefressenen erscheint es
bonus_check:
        ex de,hl
        ld hl,(dots_tot)
        or a
        sbc hl,de
        ld a,h
        or a
        ret nz
        ld a,l
        cp 70
        jr z,bc_show
        cp 170
        ret nz
bc_show:
        ld hl,500               ; 10 Sekunden
        ld (bonus_t),hl
        call bonus_kind
        ld e,a
        ld d,0
        ld hl,bonus_atr
        add hl,de
        ld a,(hl)
        ld (cur_attr),a
        ld a,e
        add a,a
        add a,a
        add a,a
        ld e,a
        ld hl,bonus_gfx
        add hl,de
        ld bc,15*256+15
        jp draw_cell

; out: A = Symbolnummer 0..7 nach dem Level
bonus_kind:
        ld a,(level)
        cp 9
        jr c,bk_1
        ld a,8
bk_1:   dec a
        ret

; Bonusobjekt verschwindet (Feld aus der Karte neu zeichnen)
bonus_hide:
        ld hl,0
        ld (bonus_t),hl
        ld bc,15*256+15
        call erase_cell
        ld a,1
        ld (dirty),a
        ret

bonus_eat:
        call bonus_hide
        call bonus_kind
        ld e,a
        ld d,0
        ld hl,bonus_pts
        add hl,de
        ld a,(hl)
        call add_score100
        ld hl,400
        ld bc,0x1408
        call sfx_go
        ld hl,-14
        ld (sfx_d),hl
        ret

bonus_tick:
        ld hl,(bonus_t)
        ld a,h
        or l
        ret z
        dec hl
        ld (bonus_t),hl
        ld a,h
        or l
        ret nz
        jp bonus_hide

; keine Leben mehr: Text, dann neues Spiel
game_over:
        ld a,0x42
        ld (cur_attr),a
        ld hl,txt_ende
        ld bc,15*256+12
        call print_at
        ld b,150
go_w:   halt
        djnz go_w
        xor a
        ld (extra),a
        ld a,3
        ld (lives),a
        xor a
        ld (score),a
        ld (score+1),a
        ld (score+2),a
        ld a,1
        ld (level),a
        call reset_level
        call draw_hud
        call draw_maze
        jp ready

draw_lives:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,txt_leben
        ld bc,23*256+2
        call print_at
        ld a,(lives)
        add a,"0"
        ld (sc_txt),a
        xor a
        ld (sc_txt+1),a
        ld hl,sc_txt
        ld bc,23*256+8
        jp print_at

; ============================================================
; Kopf- und Fusszeile
; ============================================================
draw_hud:
        ld a,ATTR_HEAD
        ld (cur_attr),a
        ld hl,txt_punkte
        ld bc,0*256+2
        call print_at
        ld hl,txt_rekord
        ld bc,0*256+12
        call print_at
        ld hl,txt_level
        ld bc,0*256+24
        call print_at
        call draw_score
        call draw_level
        call draw_lives
        ; (fall through)

; Fusszeile: Tastenhilfe mit Zustand der Farbwahl
draw_foot:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,txt_normal
        ld a,(col_mode)
        or a
        jr z,df_1
        ld hl,txt_ext
df_1:   ld bc,23*256+10
        call print_at
        ld hl,txt_d_aus
        ld a,(dbg)
        or a
        jr z,df_2
        ld hl,txt_d_an
df_2:   ld bc,23*256+19
        call print_at
        ld hl,txt_neu
        ld bc,23*256+25
        call print_at
        ld a,"T"                ; Lautstaerke
        ld (sc_txt),a
        ld a,(vol_lvl)
        add a,"0"
        ld (sc_txt+1),a
        xor a
        ld (sc_txt+2),a
        ld hl,sc_txt
        ld bc,23*256+30
        jp print_at

; Levelzahl (2 Stellen) oben rechts
draw_level:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld a,(level)
        ld b,"0"
dl_1:   cp 10
        jr c,dl_2
        sub 10
        inc b
        jr dl_1
dl_2:   add a,"0"
        ld (lvl_txt+1),a
        ld a,b
        ld (lvl_txt),a
        xor a
        ld (lvl_txt+2),a
        ld hl,lvl_txt
        ld bc,1*256+24
        jp print_at

; ============================================================
; cls: Bildschirm loeschen, Attribute weiss auf schwarz
; ============================================================
cls:
        ld hl,0x4000
        ld de,0x4001
        ld bc,0x17FF
        ld (hl),0
        ldir
        ld hl,0x5800
        ld de,0x5801
        ld bc,0x02FF
        ld (hl),ATTR_TEXT
        ldir
        ret

; ============================================================
; draw_cell: eine 8x8-Zelle samt Attribut zeichnen
; in: HL = 8 Bytes Grafik, B = Zeile, C = Spalte, (cur_attr)
; out: HL zeigt hinter die 8 Bytes; BC bleibt erhalten
; veraendert: A, DE
; ============================================================
draw_cell:
        push bc
        ; Bildschirmadresse der Zelle
        ld a,b
        and 0x18
        or 0x40
        ld d,a
        ld a,b
        and 7
        rrca
        rrca
        rrca                    ; (Zeile & 7) * 32
        add a,c
        ld e,a
        ld b,8
dc_line:
        ld a,(hl)
        ld (de),a
        inc hl
        inc d
        djnz dc_line
        pop bc
        ; Attributadresse: 0x5800 + Zeile*32 + Spalte
        ld a,b
        rrca
        rrca
        rrca
        ld e,a
        and 3
        or 0x58
        ld d,a
        ld a,e
        and 0xE0
        add a,c
        ld e,a
        ld a,(cur_attr)
        ld (de),a
        ret

; ============================================================
; print_at: Text mit dem Zeichensatz aus dem RAM ausgeben
; in: HL = Text (Ende mit 0), B = Zeile, C = Spalte, (cur_attr)
; ============================================================
print_at:
        ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl               ; * 8
        ld de,font-256          ; Zeichen 32 liegt am Anfang von font
        add hl,de
        call draw_cell
        pop hl
        inc c
        jr print_at

; ============================================================
; Daten
; ============================================================
; Melodien: Tonperiode, Dauer in Frames (Ende: 0)
tune_intro:
        dw 168
        db 6
        dw 141
        db 6
        dw 126
        db 6
        dw 168
        db 6
        dw 106
        db 6
        dw 126
        db 6
        dw 141
        db 6
        dw 168
        db 6
        dw 189
        db 6
        dw 159
        db 6
        dw 126
        db 6
        dw 95
        db 6
        dw 126
        db 6
        dw 159
        db 6
        dw 168
        db 16
        dw 0
tune_extra:
        dw 168
        db 5
        dw 141
        db 5
        dw 126
        db 5
        dw 106
        db 12
        dw 0
tune_clear:
        dw 212
        db 5
        dw 168
        db 5
        dw 141
        db 5
        dw 106
        db 5
        dw 141
        db 5
        dw 106
        db 14
        dw 0

txt_bereit:
        db "BEREIT!",0
txt_ende:
        db "SPIELENDE",0
txt_punkte:
        db "PUNKTE",0
txt_rekord:
        db "REKORD",0
txt_level:
        db "LEVEL",0
txt_leben:
        db "LEBEN ",0
txt_normal:
        db "P:NORMAL ",0
txt_ext:
        db "P:ERWEIT ",0
txt_d_aus:
        db "D:AUS",0
txt_d_an:
        db "D:AN ",0
txt_neu:
        db "N:NEU",0

; Wandfarben (NORMAL): hell blau, hell cyan, hell magenta, hell gruen
col_tab:
        db 0x41,0x45,0x43,0x44

; ULAplus-Sondertoene (GGGRRRBB): 6 Wandtoene (violett, tuerkis, limone, himmelblau, mint,
; purpur) und 2 Drohnentoene
ext_tab:
        db 0x2F,0xC3,0xF0,0x8B,0xEE
        db 0x7E,0x9C                    ; Drohnen: rosa (Eintrag 3), orange (Eintrag 6)
; zugehoerige Paletteneintraege und Attribute (hell Tinte 1,2,4,5 und dunkel Tinte 1..4;
; Tinte 3 hell = Tuer und Tinte 6/7 hell = Kopfzeile/Punkte bleiben unberuehrt)
ext_ent:
        db 17,20,21,2,4,3,6
ext_atr:
        db 0x41,0x44,0x45,0x02,0x04

; Standardpalette fuer ULAplus (Farbe 0..7 = schwarz blau rot magenta gruen cyan gelb weiss)
std_norm:
        db 0x00,0x02,0x18,0x1A,0xC0,0xC2,0xD8,0xDA
std_brt:
        db 0x00,0x03,0x1C,0x1F,0xE0,0xE3,0xFC,0xFF

; Grafiken der Feldtypen
gfx_empty:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
gfx_dot:
        db 0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00
gfx_pill:
        db 0x00,0x3C,0x7E,0x7E,0x7E,0x7E,0x3C,0x00
gfx_door:
        db 0x00,0x00,0x00,0xFF,0xFF,0x00,0x00,0x00

; ---- Labyrinth (erzeugt von tools/gen_pacman_data.py, von Hand aenderbar) ----
; #  Wand      .  Punkt     o  Pille    _  Gang ohne Punkt    =  Tuer des Geisterhauses
; P  Spieler   J  Jaeger   A  Abfangjaeger   F  Flankierer   Z  Zoegerer  (Startfelder)
; Die Wandzeichnung entsteht beim Start aus der Karte (siehe wall_mask).
map_text:
        db "############################"      ;  0
        db "#..........................#"      ;  1
        db "#.####.#####.##.#####.####.#"      ;  2
        db "#o####.#####.##.#####.####o#"      ;  3
        db "#.####.#####.##.#####.####.#"      ;  4
        db "#..........................#"      ;  5
        db "#.####.##.########.##.####.#"      ;  6
        db "#.####.##....J.....##.####.#"      ;  7
        db "#.####.##.###==###.##.####.#"      ;  8
        db "#.####.##.#______#.##.####.#"      ;  9
        db "_.........#F_A__Z#........._"      ; 10
        db "#.####.##.#______#.##.####.#"      ; 11
        db "#.####.##.########.##.####.#"      ; 12
        db "#.####.##..........##.####.#"      ; 13
        db "#.####.##.########.##.####.#"      ; 14
        db "#............P.............#"      ; 15
        db "#.####.#####.##.#####.####.#"      ; 16
        db "#o####.#####.##.#####.####o#"      ; 17
        db "#.####.#####.##.#####.####.#"      ; 18
        db "#..........................#"      ; 19
        db "############################"      ; 20

; ---- Wandgrafiken (abgerundet): eine Index-Tabelle (Nachbarmaske -> Kachel) und die Kacheln ----
idx_round:
        db 0,1,2,2,3,4,2,2,5,6,7,7,5,6,7,7
        db 8,9,10,10,11,12,10,10,5,6,7,7,5,6,7,7
        db 13,14,15,15,16,17,15,15,18,19,20,20,18,19,20,20
        db 13,14,15,15,16,17,15,15,18,19,20,20,18,19,20,20
        db 21,22,23,23,24,25,23,23,26,27,28,28,26,27,28,28
        db 29,30,31,31,32,33,31,31,26,27,28,28,26,27,28,28
        db 13,14,15,15,16,17,15,15,18,19,20,20,18,19,20,20
        db 13,14,15,15,16,17,15,15,18,19,20,20,18,19,20,20
        db 34,34,35,35,36,36,35,35,37,37,38,38,37,37,38,38
        db 39,39,40,40,41,41,40,40,37,37,38,38,37,37,38,38
        db 42,42,43,43,44,44,43,43,45,45,46,46,45,45,46,46
        db 42,42,43,43,44,44,43,43,45,45,46,46,45,45,46,46
        db 34,34,35,35,36,36,35,35,37,37,38,38,37,37,38,38
        db 39,39,40,40,41,41,40,40,37,37,38,38,37,37,38,38
        db 42,42,43,43,44,44,43,43,45,45,46,46,45,45,46,46
        db 42,42,43,43,44,44,43,43,45,45,46,46,45,45,46,46
gfx_round:      ; 47 Kacheln
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x40,0x80,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x80,0x40
        db 0x40,0x80,0x00,0x00,0x00,0x00,0x80,0x40
        db 0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00
        db 0x40,0x80,0x00,0x00,0x00,0x00,0xFF,0x00
        db 0x40,0x40,0x40,0x40,0x40,0x40,0x3F,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x02
        db 0x40,0x80,0x00,0x00,0x00,0x00,0x01,0x02
        db 0x40,0x40,0x40,0x40,0x40,0x40,0x41,0x42
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x81,0x42
        db 0x40,0x80,0x00,0x00,0x00,0x00,0x81,0x42
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02
        db 0x42,0x82,0x02,0x02,0x02,0x02,0x02,0x02
        db 0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42
        db 0x02,0x02,0x02,0x02,0x02,0x02,0x82,0x42
        db 0x42,0x82,0x02,0x02,0x02,0x02,0x82,0x42
        db 0x02,0x02,0x02,0x02,0x02,0x02,0xFC,0x00
        db 0x42,0x82,0x02,0x02,0x02,0x02,0xFC,0x00
        db 0x42,0x42,0x42,0x42,0x42,0x42,0x3C,0x00
        db 0x02,0x01,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x42,0x81,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x42,0x41,0x40,0x40,0x40,0x40,0x40,0x40
        db 0x02,0x01,0x00,0x00,0x00,0x00,0x80,0x40
        db 0x42,0x81,0x00,0x00,0x00,0x00,0x80,0x40
        db 0x02,0x01,0x00,0x00,0x00,0x00,0xFF,0x00
        db 0x42,0x81,0x00,0x00,0x00,0x00,0xFF,0x00
        db 0x42,0x41,0x40,0x40,0x40,0x40,0x3F,0x00
        db 0x02,0x01,0x00,0x00,0x00,0x00,0x01,0x02
        db 0x42,0x81,0x00,0x00,0x00,0x00,0x01,0x02
        db 0x42,0x41,0x40,0x40,0x40,0x40,0x41,0x42
        db 0x02,0x01,0x00,0x00,0x00,0x00,0x81,0x42
        db 0x42,0x81,0x00,0x00,0x00,0x00,0x81,0x42
        db 0x00,0xFF,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x3F,0x40,0x40,0x40,0x40,0x40,0x40
        db 0x00,0xFF,0x00,0x00,0x00,0x00,0x80,0x40
        db 0x00,0xFF,0x00,0x00,0x00,0x00,0xFF,0x00
        db 0x00,0x3F,0x40,0x40,0x40,0x40,0x3F,0x00
        db 0x00,0xFF,0x00,0x00,0x00,0x00,0x01,0x02
        db 0x00,0x3F,0x40,0x40,0x40,0x40,0x41,0x42
        db 0x00,0xFF,0x00,0x00,0x00,0x00,0x81,0x42
        db 0x00,0xFC,0x02,0x02,0x02,0x02,0x02,0x02
        db 0x00,0x3C,0x42,0x42,0x42,0x42,0x42,0x42
        db 0x00,0xFC,0x02,0x02,0x02,0x02,0x82,0x42
        db 0x00,0xFC,0x02,0x02,0x02,0x02,0xFC,0x00
        db 0x00,0x3C,0x42,0x42,0x42,0x42,0x3C,0x00

; ---- Figuren (erzeugt): je Bild 4 um 0/2/4/6 Pixel verschobene Kopien, 8 Zeilen * 2 Bytes ----
; Spieler: Richtung hoch, rechts, runter, links; je Richtung 3 Bilder (zu, halb, offen)
spr_player:
        ; Richtung 0 Bild 0
        db 0x7E,0x00,0xFF,0x00,0xFF,0x00,0xDF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3F,0xC0,0x37,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0xF0,0x0D,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xFC,0x03,0x7C,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 0 Bild 1
        db 0x62,0x00,0xE3,0x00,0xF7,0x00,0xDF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x18,0x80,0x38,0xC0,0x3D,0xC0,0x37,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x06,0x20,0x0E,0x30,0x0F,0x70,0x0D,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0x88,0x03,0x8C,0x03,0xDC,0x03,0x7C,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 0 Bild 2
        db 0x62,0x00,0xE3,0x00,0xE3,0x00,0xC3,0x00,0xF7,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x18,0x80,0x38,0xC0,0x38,0xC0,0x30,0xC0,0x3D,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x06,0x20,0x0E,0x30,0x0E,0x30,0x0C,0x30,0x0F,0x70,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0x88,0x03,0x8C,0x03,0x8C,0x03,0x0C,0x03,0xDC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 1 Bild 0
        db 0x7E,0x00,0xFF,0x00,0xF7,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3D,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0x70,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xDC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 1 Bild 1
        db 0x7E,0x00,0xFF,0x00,0xF7,0x00,0xFC,0x00,0xF8,0x00,0xFC,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3D,0xC0,0x3F,0x00,0x3E,0x00,0x3F,0x00,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0x70,0x0F,0xC0,0x0F,0x80,0x0F,0xC0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xDC,0x03,0xF0,0x03,0xE0,0x03,0xF0,0x03,0xFC,0x01,0xF8
        ; Richtung 1 Bild 2
        db 0x7E,0x00,0xFF,0x00,0xF7,0x00,0xF0,0x00,0xE0,0x00,0xF0,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3D,0xC0,0x3C,0x00,0x38,0x00,0x3C,0x00,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0x70,0x0F,0x00,0x0E,0x00,0x0F,0x00,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xDC,0x03,0xC0,0x03,0x80,0x03,0xC0,0x03,0xFC,0x01,0xF8
        ; Richtung 2 Bild 0
        db 0x7E,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0xFB,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x3E,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xB0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x03,0xEC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 2 Bild 1
        db 0x7E,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0xFB,0x00,0xEF,0x00,0xC7,0x00,0x46,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x3E,0xC0,0x3B,0xC0,0x31,0xC0,0x11,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xB0,0x0E,0xF0,0x0C,0x70,0x04,0x60
        db 0x01,0xF8,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x03,0xEC,0x03,0xBC,0x03,0x1C,0x01,0x18
        ; Richtung 2 Bild 2
        db 0x7E,0x00,0xFF,0x00,0xFF,0x00,0xEF,0x00,0xC3,0x00,0xC7,0x00,0xC7,0x00,0x46,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3F,0xC0,0x3B,0xC0,0x30,0xC0,0x31,0xC0,0x31,0xC0,0x11,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0xF0,0x0E,0xF0,0x0C,0x30,0x0C,0x70,0x0C,0x70,0x04,0x60
        db 0x01,0xF8,0x03,0xFC,0x03,0xFC,0x03,0xBC,0x03,0x0C,0x03,0x1C,0x03,0x1C,0x01,0x18
        ; Richtung 3 Bild 0
        db 0x7E,0x00,0xFF,0x00,0xEF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3B,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0E,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xBC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 3 Bild 1
        db 0x7E,0x00,0xFF,0x00,0xEF,0x00,0x3F,0x00,0x1F,0x00,0x3F,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3B,0xC0,0x0F,0xC0,0x07,0xC0,0x0F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0E,0xF0,0x03,0xF0,0x01,0xF0,0x03,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xBC,0x00,0xFC,0x00,0x7C,0x00,0xFC,0x03,0xFC,0x01,0xF8
        ; Richtung 3 Bild 2
        db 0x7E,0x00,0xFF,0x00,0xEF,0x00,0x0F,0x00,0x07,0x00,0x0F,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3B,0xC0,0x03,0xC0,0x01,0xC0,0x03,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0E,0xF0,0x00,0xF0,0x00,0x70,0x00,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xBC,0x00,0x3C,0x00,0x1C,0x00,0x3C,0x03,0xFC,0x01,0xF8
; Drohne: 2 Bilder (Rotoren/Beine), je 4 Verschiebungen
spr_drone:
        db 0xC3,0x00,0x7E,0x00,0xFF,0x00,0xDB,0x00,0xFF,0x00,0xFF,0x00,0x5A,0x00,0x24,0x00
        db 0x30,0xC0,0x1F,0x80,0x3F,0xC0,0x36,0xC0,0x3F,0xC0,0x3F,0xC0,0x16,0x80,0x09,0x00
        db 0x0C,0x30,0x07,0xE0,0x0F,0xF0,0x0D,0xB0,0x0F,0xF0,0x0F,0xF0,0x05,0xA0,0x02,0x40
        db 0x03,0x0C,0x01,0xF8,0x03,0xFC,0x03,0x6C,0x03,0xFC,0x03,0xFC,0x01,0x68,0x00,0x90
        db 0x66,0x00,0x7E,0x00,0xFF,0x00,0xDB,0x00,0xFF,0x00,0xFF,0x00,0x5A,0x00,0x42,0x00
        db 0x19,0x80,0x1F,0x80,0x3F,0xC0,0x36,0xC0,0x3F,0xC0,0x3F,0xC0,0x16,0x80,0x10,0x80
        db 0x06,0x60,0x07,0xE0,0x0F,0xF0,0x0D,0xB0,0x0F,0xF0,0x0F,0xF0,0x05,0xA0,0x04,0x20
        db 0x01,0x98,0x01,0xF8,0x03,0xFC,0x03,0x6C,0x03,0xFC,0x03,0xFC,0x01,0x68,0x01,0x08
; Augen einer gefressenen Drohne: 1 Bild, 4 Verschiebungen
spr_eyes:
        db 0x00,0x00,0x00,0x00,0xE7,0x00,0xE7,0x00,0xE7,0x00,0xE7,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x39,0xC0,0x39,0xC0,0x39,0xC0,0x39,0xC0,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x0E,0x70,0x0E,0x70,0x0E,0x70,0x0E,0x70,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x03,0x9C,0x03,0x9C,0x03,0x9C,0x03,0x9C,0x00,0x00,0x00,0x00
; Sterbebilder des Roboters: 6 Bilder (zerfaellt), je 4 Verschiebungen
spr_death:
        db 0x7E,0x00,0xFF,0x00,0xF7,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0xFF,0x00,0x7E,0x00
        db 0x1F,0x80,0x3F,0xC0,0x3D,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x3F,0xC0,0x1F,0x80
        db 0x07,0xE0,0x0F,0xF0,0x0F,0x70,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x0F,0xF0,0x07,0xE0
        db 0x01,0xF8,0x03,0xFC,0x03,0xDC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x03,0xFC,0x01,0xF8
        db 0x00,0x00,0x76,0x00,0x62,0x00,0x76,0x00,0x7E,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00
        db 0x00,0x00,0x1D,0x80,0x18,0x80,0x1D,0x80,0x1F,0x80,0x1F,0x80,0x1F,0x80,0x00,0x00
        db 0x00,0x00,0x07,0x60,0x06,0x20,0x07,0x60,0x07,0xE0,0x07,0xE0,0x07,0xE0,0x00,0x00
        db 0x00,0x00,0x01,0xD8,0x01,0x88,0x01,0xD8,0x01,0xF8,0x01,0xF8,0x01,0xF8,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x20,0x00,0x34,0x00,0x3C,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x08,0x00,0x0D,0x00,0x0F,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x03,0x40,0x03,0xC0,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x80,0x00,0xD0,0x00,0xF0,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x92,0x00,0x24,0x00,0x00,0x00,0x88,0x00,0x20,0x00,0x05,0x00,0xA0,0x00,0x22,0x00
        db 0x24,0x80,0x09,0x00,0x00,0x00,0x22,0x00,0x08,0x00,0x01,0x40,0x28,0x00,0x08,0x80
        db 0x09,0x20,0x02,0x40,0x00,0x00,0x08,0x80,0x02,0x00,0x00,0x50,0x0A,0x00,0x02,0x20
        db 0x02,0x48,0x00,0x90,0x00,0x00,0x02,0x20,0x00,0x80,0x00,0x14,0x02,0x80,0x00,0x88
        db 0x81,0x00,0x00,0x00,0x10,0x00,0x00,0x00,0x08,0x00,0x00,0x00,0x81,0x00,0x00,0x00
        db 0x20,0x40,0x00,0x00,0x04,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x20,0x40,0x00,0x00
        db 0x08,0x10,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x80,0x00,0x00,0x08,0x10,0x00,0x00
        db 0x02,0x04,0x00,0x00,0x00,0x40,0x00,0x00,0x00,0x20,0x00,0x00,0x02,0x04,0x00,0x00
; Bonusobjekte (Level 1..8, ab 8 gleich), 8 Bytes je Symbol
bonus_gfx:
        db 0x18,0x3C,0x7E,0xFF,0x7E,0x3C,0x18,0x00
        db 0x18,0x18,0x18,0xFF,0xFF,0x18,0x18,0x18
        db 0x3C,0x7E,0xE7,0xC3,0xE7,0x7E,0x3C,0x00
        db 0x0E,0x1C,0x38,0x7E,0x1C,0x38,0x70,0xE0
        db 0x3C,0x42,0x42,0x3C,0x18,0x1C,0x18,0x1C
        db 0x18,0x3C,0x3C,0x7E,0x7E,0xFF,0x00,0x18
        db 0xAA,0xFF,0xBD,0xFF,0xBD,0xFF,0xAA,0x00
        db 0x18,0x18,0xFF,0x7E,0x3C,0x66,0xC3,0x00
; Farbe, Punkte in Hundertern (BCD): 100 300 500 700 1000 2000 3000 5000
bonus_atr:
        db 0x42,0x46,0x43,0x47,0x42,0x46,0x43,0x47
bonus_pts:
        db 0x01,0x03,0x05,0x07,0x10,0x20,0x30,0x50
; ---- Tabellen je Levelklasse (0 = Level 1, 1 = Level 2..4, 2 = ab Level 5) ----
; Spielertempo, Drohnenzuschlag, Tempo der verwirrten Drohnen (je 20 Frames), Wartegrenze (Frames)
lvl_tab:
        db 10,0,5,200
        db 11,1,6,150
        db 12,2,7,150
; Dauer von Streuen / Jagd, 8 Abschnitte je Klasse (65535 = ohne Ende)
tm_tab:
        dw 350,1000,350,1000,250,1000,250,65535
        dw 350,1000,350,1000,250,51650,1,65535
        dw 250,1000,250,1000,250,51850,1,65535
; Pillenwirkung in Sekunden fuer Level 1..21 (ab 22 wie 21), als Frames
fr_tab:
        dw 300,250,200,150,100,250,100,100,50,250,100,50,50,150,50,50,0,50,0,0,0
; Freigabe der Drohnen 2..4 nach so vielen gefressenen Punkten (je Klasse)
rel_tab:
        db 0,30,60
        db 0,0,50
        db 0,0,0
; Ecken fuer die Streuphase (Zeichenspalte, Zeichenzeile): Jaeger, Abfang, Flank, Zoegerer
scat_tab:
        db 29,0, 2,0, 29,23, 2,23
; Punkte fuer gefressene Drohnen (BCD, in Hundertern): 200 400 800 1600
chain_tab:
        db 0x02,0x04,0x08,0x16
; Startwerte der vier Drohnen (GS_SIZE = 16 Bytes): x, y, Richtung, Tempo-Summe, Tempo,
;   Attribut, Zustand (0 wartet, 2 jagt), Freigabe (Zwei-Frame-Takte), Zaehler, alter Bereich (5), 2 frei
ghost_init:
        db 120,72,3,0,8,0x42,2,0,0,0,0,0,0,0,0,0          ; J
        db 120,96,0,0,7,0x03,0,50,0,0,0,0,0,0,1,0          ; A
        db 104,96,0,0,7,0x05,0,100,0,0,0,0,0,0,2,0          ; F
        db 144,96,0,0,6,0x06,0,150,0,0,0,0,0,0,3,0          ; Z
; Quadrate 0..31 fuer die Abstandsberechnung
sq_tab:
        dw 0,1,4,9,16,25,36,49
        dw 64,81,100,121,144,169,196,225
        dw 256,289,324,361,400,441,484,529
        dw 576,625,676,729,784,841,900,961

        end start
