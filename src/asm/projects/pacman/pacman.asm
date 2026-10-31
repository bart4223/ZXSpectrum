; ============================================================
; Pacman-Variante fuer den ZX Spectrum 128K - Stufe 3: Drohnen laufen
; Assembler: pasmo   (pasmo --tapbas pacman.asm pacman.tap)
; ============================================================
; Nur 128K. Das Labyrinth ist eine Textkarte (map_text weiter unten), 28 x 21
; Kacheln zu je 8x8 Pixel. Die Wandzeichnung entsteht beim Start aus der Karte:
; fuer jede Wandkachel werden die 8 Nachbarn untersucht (Maske), daraus waehlt
; eine Tabelle die passende Kachel (Linien dort, wo ein Gang angrenzt).
;
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
M_CHASE     equ 2               ; jagt den Spieler

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
ghosts      equ VARS + 0x780    ; 4 Drohnen zu GS_SIZE Bytes

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
        ld a,1
        ld (level),a
        ld a,3
        ld (lives),a
        xor a
        ld (door_ok),a
        ld hl,0xA280
        ld (rng),hl
        call apply_space        ; ULAplus aus, falls ein Vorgaenger es angelassen hat
        call pick_color         ; Wandfarbe fuer Level 1
        call reset_level        ; Karte laden, Punkte zaehlen, Spieler an den Start
        call ay_init
        call cls
        call draw_hud
        call draw_maze

; ---- Hauptschleife: ein Durchlauf pro Frame (50 Hz) -------
main_loop:
        halt
        call update_player      ; Bewegung (nur Zahlen)
        call update_ghosts
        call check_hits
        call blink_pills
        call redraw             ; Zeichnen direkt nach HALT
        call keys
        call sfx_tick
        ld a,(win_flag)
        or a
        call nz,level_clear
        jr main_loop

; ============================================================
; Tasten P (Farbraum) und N (neues Level), nur bei neuem Druck
; ============================================================
keys:
        ld a,0xDF
        in a,(0xFE)             ; Reihe P O I U Y
        cpl
        and 0x01                ; Bit 0 = P
        ld hl,key_p
        call edge
        jr z,k_n
        ld a,(col_mode)
        xor 1
        ld (col_mode),a
        call apply_space
        call draw_foot
        call draw_maze
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
        cp 8
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
pk_ext: ld b,5
        call mod_a
        ld b,a                  ; 0..4
        ld a,(ext_col)
        inc a
        add a,b                 ; Abstand 1..5 zur alten Farbe
pk_x:   cp 6
        jr c,pk_y
        sub 6
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
        jp draw_maze

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
        add a,PL_SPEED
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
        call erase_all          ; alle alten Bereiche aus der Karte wiederherstellen
        ld ix,ghosts            ; Drohnen
        ld b,4
rd_g:   push bc
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
        ld b,(ix+G_X)
        ld c,(ix+G_Y)
        ld a,(ix+G_ATTR)
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
        pop bc
        ld de,GS_SIZE
        add ix,de
        djnz rd_g
        ld a,(pl_cnt)           ; Spieler: Bild nach Richtung und Animationsschritt
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

anim_seq:
        db 0,1,2,1

; alten Bereich des Spielers aus der Karte wiederherstellen
erase_old:
        ld a,(old_r)
        ld c,a
        ld a,(old_h)
        ld d,a
eo_row: ld a,(old_c)
        ld b,a
        ld a,(old_w)
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
        ld a,1
        ld (dirty),a
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
        call maze_addr
        ld a,(hl)
        cp C_DOT
        jr z,ea_dot
        cp C_PILL
        ret nz
        ld (hl),C_EMPTY
        call sfx_pill
        ld a,0x50
        jr ea_sc
ea_dot: ld (hl),C_EMPTY
        call sfx_dot
        ld a,0x10
ea_sc:  call add_score
        ld hl,(dots_left)
        dec hl
        ld (dots_left),hl
        ld a,h
        or l
        ret nz
        ld a,1
        ld (win_flag),a
        ret

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
        ld a,(score+2)          ; Rekord = max(Rekord, Punkte)
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
        ld e,0x3B               ; nur Ton C an, kein Rauschen
        call ay_wr
        ld d,10
        ld e,0
        jp ay_wr

sfx_dot:
        ld a,(sfx_flip)
        xor 1
        ld (sfx_flip),a
        ld hl,200               ; zwei abwechselnde Toene
        jr z,sd_1
        ld hl,150
sd_1:   ld bc,0x0404            ; Lautstaerke 4 (leise), 4 Frames
        jr sfx_go
sfx_pill:
        ld hl,600
        ld bc,0x0E06            ; Lautstaerke 6 (leise), 14 Frames
sfx_go: ld a,b
        ld (sfx_t),a
        push bc
        ld d,4
        ld e,l
        call ay_wr
        ld d,5
        ld e,h
        call ay_wr
        pop bc
        ld d,10
        ld e,c
        jp ay_wr

sfx_tick:
        ld a,(sfx_t)
        or a
        ret z
        dec a
        ld (sfx_t),a
        ret nz
        ld d,10
        ld e,0                  ; Ton aus
        jp ay_wr


; alte Bereiche von Spieler und Drohnen aus der Karte wiederherstellen
erase_all:
        ld a,(old_valid)
        or a
        call nz,erase_old
        xor a
        ld (old_valid),a
        ld ix,ghosts
        ld b,4
ea_l:   push bc
        ld a,(ix+G_OV)
        or a
        jr z,ea_n
        ld a,(ix+G_OC)
        ld (old_c),a
        ld a,(ix+G_OR)
        ld (old_r),a
        ld a,(ix+G_OW)
        ld (old_w),a
        ld a,(ix+G_OH)
        ld (old_h),a
        call erase_old
        ld (ix+G_OV),0
ea_n:   pop bc
        ld de,GS_SIZE
        add ix,de
        djnz ea_l
        ret

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
        jr nz,ug_act
        ld a,(blink_cnt)        ; Wartezeit: alle 2 Frames um 1 herunter
        and 1
        ret nz
        ld a,(ix+G_TMR)
        or a
        jr z,ug_rel
        dec (ix+G_TMR)
        ret
ug_rel: ld (ix+G_MODE),M_EXIT
        ld (ix+G_DIR),D_UP
        ret
ug_act: ld a,(ix+G_Y)           ; im Tunnel langsamer
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
ug_n:   ld a,(ix+G_SPD)
ug_a:   add a,(ix+G_ACC)
        cp 20
        jr c,ug_st
        sub 20
        ld (ix+G_ACC),a
        jr ghost_step
ug_st:  ld (ix+G_ACC),a
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
        ret nz
        ld a,(ix+G_Y)           ; draussen vor dem Haus: jagen
        cp 73
        ret nc
        ld (ix+G_MODE),M_CHASE
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
        cp M_EXIT
        jr nz,gc_t1
        ld a,15                 ; Ziel beim Verlassen des Hauses: ueber der Tuer
        ld (gc_tc),a
        ld a,7
        ld (gc_tr),a
        ld a,1
        ld (door_ok),a
        jr gc_t2
gc_t1:  ld a,(pl_x)             ; Ziel: der Spieler
        rrca
        rrca
        rrca
        and 0x1F
        ld (gc_tc),a
        ld a,(pl_y)
        rrca
        rrca
        rrca
        and 0x1F
        ld (gc_tr),a
gc_t2:  ld hl,0xFFFF
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
        jp life_lost
ch_n:   ld de,GS_SIZE
        add ix,de
        djnz ch_l
        ret

; Leben verlieren (noch ohne Animation): kurze Pause, alle an den Start
life_lost:
        call erase_all
        ld a,(lives)
        dec a
        ld (lives),a
        jr z,game_over
        call draw_lives
        ld b,50
ll_w:   halt
        djnz ll_w
        jp reset_actors

; keine Leben mehr: neues Spiel
game_over:
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
        jp draw_maze

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
txt_punkte:
        db "PUNKTE",0
txt_rekord:
        db "REKORD",0
txt_level:
        db "LEVEL",0
txt_leben:
        db "LEBEN ",0
txt_normal:
        db "P:NORMAL    N/LEER:NEU",0
txt_ext:
        db "P:ERWEITERT N/LEER:NEU",0

; Wandfarben (NORMAL): hell blau, hell cyan, hell magenta, hell gruen
col_tab:
        db 0x41,0x45,0x43,0x44

; ULAplus-Sondertoene (GGGRRRBB): 6 Wandtoene (violett, tuerkis, limone, himmelblau, mint,
; purpur) und 2 Drohnentoene
ext_tab:
        db 0x2F,0xC3,0xF0,0x8B,0xEE,0x2B
        db 0x7E,0x9C                    ; Drohnen: rosa (Eintrag 3), orange (Eintrag 6)
; zugehoerige Paletteneintraege und Attribute (hell Tinte 1,2,4,5 und dunkel Tinte 1..4;
; Tinte 3 hell = Tuer und Tinte 6/7 hell = Kopfzeile/Punkte bleiben unberuehrt)
ext_ent:
        db 17,20,21,1,2,4,3,6
ext_atr:
        db 0x41,0x44,0x45,0x01,0x02,0x04

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
; Startwerte der vier Drohnen (GS_SIZE = 16 Bytes): x, y, Richtung, Tempo-Summe, Tempo,
;   Attribut, Zustand (0 wartet, 2 jagt), Freigabe (Zwei-Frame-Takte), Zaehler, alter Bereich (5), 2 frei
ghost_init:
        db 120,72,3,0,9,0x42,2,0,0,0,0,0,0,0,0,0          ; J
        db 120,96,0,0,8,0x03,0,50,0,0,0,0,0,0,0,0          ; A
        db 104,96,0,0,8,0x05,0,100,0,0,0,0,0,0,0,0          ; F
        db 144,96,0,0,7,0x06,0,150,0,0,0,0,0,0,0,0          ; Z
; Quadrate 0..31 fuer die Abstandsberechnung
sq_tab:
        dw 0,1,4,9,16,25,36,49
        dw 64,81,100,121,144,169,196,225
        dw 256,289,324,361,400,441,484,529
        dw 576,625,676,729,784,841,900,961

        end start
