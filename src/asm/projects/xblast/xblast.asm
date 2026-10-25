; ============================================================
; XBlast fuer den ZX Spectrum - Stufe 2: Bomben legen, explodieren, animiert
; Assembler: pasmo   (pasmo --tapbas xblast.asm xblast.tap)
; ============================================================
; Spielfeld 15 x 11 Kacheln a 16x16 Pixel (2x2 Zeichenzellen)
; Feste Waende am Rand und auf jeder zweiten Kachel,
; zufaellige Bloecke, die vier Ecken bleiben frei.
;
; Steuerung (Sinclair IF2):
;   Spieler 1 (oben links)  : Joystick 1 = Tasten 6 7 8 9 0
;   Spieler 2 (unten rechts): Joystick 2 = Tasten 1 2 3 4 5
;   LEERTASTE               : neue Runde (neues Feld)
;   Feuer                   : Bombe legen (1 Bombe pro Spieler)
; Bewegung in Kachelschritten, Waende, Bloecke und Bomben blockieren.
; Eine Bombe explodiert nach 3 Sekunden: kreuzfoermige Flamme,
; Reichweite 2, gestoppt von Wand, Block und Bombe.
; ============================================================

        org 32768

; ---- Konstanten -------------------------------------------
FW          equ 15              ; Feldbreite in Kacheln
FH          equ 11              ; Feldhoehe in Kacheln
FIELD_COL   equ 1               ; Zeichenspalte der linken Feldkante
FIELD_ROW   equ 2               ; Zeichenzeile der oberen Feldkante

T_EMPTY     equ 0               ; Kachel-Typen
T_WALL      equ 1               ; feste Wand
T_BLOCK     equ 2               ; zerstoerbarer Block
T_BOMB      equ 3               ; Bombe
T_FLAME     equ 4               ; Flamme (Grafikindex)
; Flammen stehen als 0x80 + Restdauer im Feld (Bit 7 = Flamme)
FLAME_TICKS equ 25              ; Flammendauer in Frames
FLAME_VAL   equ 0x80 + FLAME_TICKS
BOMB_FUSE   equ 150             ; Zuenddauer in Frames (3 Sekunden)
BOMB_URGENT equ 50              ; unter dieser Restzeit pulsiert die Bombe schneller
T_BOMB2     equ 5               ; Grafikindex: Bombe, zweiter Animationsframe
MAX_BOMBS   equ 8               ; Bombenplaetze insgesamt
BS_SIZE     equ 8               ; Bytes je Bombenplatz

BLOCK_CHANCE equ 170            ; Blockwahrscheinlichkeit (von 256)

ATTR_TITLE  equ 0x46            ; hell gelb auf schwarz
ATTR_TEXT   equ 0x07            ; weiss auf schwarz
ATTR_P1     equ 0x47            ; Spieler 1: hell weiss auf schwarz
ATTR_P2     equ 0x43            ; Spieler 2: hell magenta auf schwarz

; Richtungen (Index in dir_dx / dir_dy und in spr_gfx)
DIR_UP      equ 0
DIR_RIGHT   equ 1
DIR_DOWN    equ 2
DIR_LEFT    equ 3

; Joystick-Bits (Ergebnis von read_joy1 / read_joy2, aktiv = 1)
J_FIRE      equ 0
J_UP        equ 1
J_DOWN      equ 2
J_RIGHT     equ 3
J_LEFT      equ 4
JM_FIRE     equ 1               ; Maske von J_FIRE

; Spieler-Struktur (PS_SIZE Bytes je Spieler)
PX          equ 0               ; Kachel x
PY          equ 1               ; Kachel y
PDIR        equ 2               ; Blickrichtung
PALIVE      equ 3               ; 1 = lebt
PDELAY      equ 4               ; Frames bis zum naechsten Schritt
PATTR       equ 5               ; Farbattribut des Sprites
PRANGE      equ 6               ; Flammenreichweite
PMAXB       equ 7               ; maximale Anzahl gleichzeitiger Bomben
PFIRE       equ 8               ; Feuertaste im letzten Frame (0/1)
POWNER      equ 9               ; Spielernummer (0/1)
PS_SIZE     equ 10

; Bombenplatz (BS_SIZE Bytes): Zeit (0 = frei), x, y, Besitzer, Reichweite

MOVE_DELAY  equ 8               ; Frames pro Schritt (50 Hz / 8 = 6,25 Schritte/s)

; ---- Variablen (freier RAM, nicht im TAP) -----------------
VARS        equ 0xA000
seed        equ VARS            ; 2 Bytes
cur_attr    equ VARS + 2        ; 1 Byte: Attribut fuer draw_cell
dirty       equ VARS + 3        ; 1 = Spieler muessen neu gezeichnet werden
ex_cx       equ VARS + 4        ; Explosion: Zentrum x
ex_cy       equ VARS + 5        ; Explosion: Zentrum y
ex_range    equ VARS + 6        ; Explosion: Reichweite
ex_dir      equ VARS + 7        ; Explosion: aktuelle Richtung
ex_cnt      equ VARS + 8        ; Explosion: verbleibende Schritte
anim        equ VARS + 9        ; Frame-Zaehler fuer Animationen
bomb_frame  equ VARS + 10       ; Bombenanimation: 0 oder 2 (Grafik 3 oder 5)
field       equ VARS + 16       ; FW*FH Bytes: Kacheltypen
bombs       equ VARS + 0xC0     ; MAX_BOMBS * BS_SIZE Bytes
pl1         equ VARS + 0x100    ; Spieler 1
pl2         equ pl1 + PS_SIZE   ; Spieler 2

; ============================================================
; Programmstart
; ============================================================
start:
        xor a
        out (0xFE),a            ; Rand schwarz
        call cls
        call seed_init

        ; Kopfzeile
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld hl,txt_title
        ld b,0                  ; Zeile
        ld c,1                  ; Spalte
        call print_at
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,txt_hint
        ld b,0
        ld c,16
        call print_at

new_round:
        call init_field
        call draw_field
        call init_players
        call init_bombs
        xor a
        ld (dirty),a
        call draw_players

; ---- Hauptschleife: ein Durchlauf pro Frame (50 Hz) -------
game_loop:
        halt
        call rnd                ; Zufallsgenerator weiterdrehen
        ld a,0x7F
        in a,(0xFE)             ; Reihe B-N-M-Symbol-Leertaste
        rra                     ; Carry = Leertaste (0 = gedrueckt)
        jr nc,reset_round
        ld ix,pl1
        call read_joy1
        call update_player
        ld ix,pl2
        call read_joy2
        call update_player
        call update_bombs
        call animate_bombs
        call update_flames
        ld a,(dirty)
        or a
        jr z,game_loop
        xor a
        ld (dirty),a
        call draw_players       ; Spieler nach Flammen-Zeichnen wieder oben
        jr game_loop

reset_round:
        ld a,0x7F               ; warten bis die Leertaste losgelassen ist
        in a,(0xFE)
        rra
        jr nc,reset_round
        jr new_round

; ============================================================
; Joystick lesen (Sinclair IF2)
; out: A = Bits J_FIRE, J_UP, J_DOWN, J_RIGHT, J_LEFT (aktiv = 1)
; ============================================================
; Joystick 1 = Tasten 6 7 8 9 0 (Port 0xEFFE):
;   Bit0 = 0 (Feuer), Bit1 = 9 (hoch), Bit2 = 8 (runter),
;   Bit3 = 7 (rechts), Bit4 = 6 (links)  -> passt direkt
read_joy1:
        ld bc,0xEFFE
        in a,(c)
        cpl
        and 0x1F
        ret

; Joystick 2 = Tasten 1 2 3 4 5 (Port 0xF7FE):
;   Bit0 = 1 (links), Bit1 = 2 (rechts), Bit2 = 3 (runter),
;   Bit3 = 4 (hoch), Bit4 = 5 (Feuer)    -> Bits umdrehen
read_joy2:
        ld bc,0xF7FE
        in a,(c)
        cpl
        and 0x1F
        ld e,a
        ld d,0
        ld b,5
rj2_rev:
        rr e
        rl d
        djnz rj2_rev
        ld a,d
        ret

; ============================================================
; Spieler
; ============================================================
init_players:
        ld hl,pl_init
        ld de,pl1
        ld bc,PS_SIZE*2
        ldir
        ret

; zeichnet beide Spieler
draw_players:
        ld ix,pl1
        call draw_player
        ld ix,pl2
        jp draw_player

; in: IX = Spieler
draw_player:
        ld a,(ix+PALIVE)
        or a
        ret z
        ld a,(ix+PATTR)
        ld (cur_attr),a
        ld a,(ix+PY)
        add a,a
        add a,FIELD_ROW
        ld b,a                  ; Zeichenzeile
        ld a,(ix+PX)
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld a,(ix+PDIR)
        jp draw_sprite

; in: IX = Spieler, A = Joystick-Bits
update_player:
        ld e,a                  ; Joystick-Bits merken
        ld a,(ix+PALIVE)
        or a
        ret z
        ; Feuer-Flanke: Bombe legen
        ld a,e
        and JM_FIRE
        ld d,a                  ; D = Feuer jetzt (0 oder 1)
        ld a,(ix+PFIRE)
        ld (ix+PFIRE),d
        or a
        jr nz,up_move           ; Taste war schon gedrueckt
        ld a,d
        or a
        jr z,up_move
        push de
        call place_bomb
        pop de
up_move:
        ld a,(ix+PDELAY)
        or a
        jr z,up_ready
        dec (ix+PDELAY)
        ret
up_ready:
        ld a,e
        ; Richtung bestimmen: hoch vor runter vor links vor rechts
        ld d,DIR_UP
        bit J_UP,a
        jr nz,up_dir
        ld d,DIR_DOWN
        bit J_DOWN,a
        jr nz,up_dir
        ld d,DIR_LEFT
        bit J_LEFT,a
        jr nz,up_dir
        ld d,DIR_RIGHT
        bit J_RIGHT,a
        ret z                   ; nichts gedrueckt
up_dir:
        ld (ix+PDIR),d          ; Blickrichtung uebernehmen
        ; Zielkachel berechnen
        ld e,d
        ld d,0
        ld hl,dir_dx
        add hl,de
        ld a,(ix+PX)
        add a,(hl)
        ld b,a                  ; neues x
        ld hl,dir_dy
        add hl,de
        ld a,(ix+PY)
        add a,(hl)
        ld c,a                  ; neues y
        call field_addr
        ld a,(hl)
        or a                    ; T_EMPTY?
        jr nz,up_blocked
        ; Schritt: alte Kachel neu zeichnen, Position setzen
        push bc
        ld b,(ix+PX)
        ld c,(ix+PY)
        call redraw_tile
        pop bc
        ld (ix+PX),b
        ld (ix+PY),c
        ld (ix+PDELAY),MOVE_DELAY
        jp draw_players
up_blocked:
        jp draw_player          ; nur die Blickrichtung hat sich evtl. geaendert

; ============================================================
; Bomben
; ============================================================
init_bombs:
        ld hl,bombs
        ld de,bombs+1
        ld bc,MAX_BOMBS*BS_SIZE-1
        ld (hl),0
        ldir
        xor a
        ld (bomb_frame),a
        ret

; in: IX = Spieler; legt eine Bombe auf seine Kachel, falls erlaubt
place_bomb:
        ld b,(ix+PX)
        ld c,(ix+PY)
        call field_addr
        ld a,(hl)
        or a
        ret nz                  ; Kachel nicht frei
        ; eigene Bomben zaehlen (C) und freien Platz suchen (DE)
        ld hl,bombs
        ld b,MAX_BOMBS
        ld c,0
        ld de,0
pb_scan:
        ld a,(hl)
        or a
        jr nz,pb_used
        ld a,d                  ; Platz ist frei: den ersten merken
        or e
        jr nz,pb_next
        ld d,h
        ld e,l
        jr pb_next
pb_used:
        push hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)               ; Besitzer
        pop hl
        cp (ix+POWNER)
        jr nz,pb_next
        inc c
pb_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,pb_cont
        inc h
pb_cont:
        djnz pb_scan
        ld a,c
        cp (ix+PMAXB)
        ret nc                  ; schon genug Bomben gelegt
        ld a,d
        or e
        ret z                   ; kein freier Platz
        ex de,hl                ; HL = Bombenplatz
        ld (hl),BOMB_FUSE
        inc hl
        ld a,(ix+PX)
        ld (hl),a
        inc hl
        ld a,(ix+PY)
        ld (hl),a
        inc hl
        ld a,(ix+POWNER)
        ld (hl),a
        inc hl
        ld a,(ix+PRANGE)
        ld (hl),a
        ld b,(ix+PX)
        ld c,(ix+PY)
        call field_addr
        ld (hl),T_BOMB          ; die Spielerfigur verdeckt die Bombe,
        ret                     ; bis sie die Kachel verlaesst

; Zuendschnuere herunterzaehlen, abgelaufene Bomben sprengen
update_bombs:
        ld hl,bombs
        ld b,MAX_BOMBS
ub_loop:
        ld a,(hl)
        or a
        jr z,ub_next
        dec a
        ld (hl),a
        jr nz,ub_next
        push bc
        push hl
        call explode
        pop hl
        pop bc
ub_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ub_cont
        inc h
ub_cont:
        djnz ub_loop
        ret

; Bombenanimation: alle Bomben pulsieren im gleichen Takt (2 Frames),
; alle 8 Bildschirmframes; ist eine Zuendschnur fast durch (unter
; BOMB_URGENT), doppelt so schnell. Bomben unter einer Spielerfigur
; werden nicht neu gezeichnet; die Figur verdeckt sie ohnehin.
animate_bombs:
        ld hl,anim
        inc (hl)
        ld d,(hl)               ; D = Frame-Zaehler
        ld hl,bombs
        ld b,MAX_BOMBS
        ld e,8                  ; normaler Takt
ab_scan:
        ld a,(hl)
        or a
        jr z,ab_next
        cp BOMB_URGENT
        jr nc,ab_next
        ld e,4                  ; eine Bombe geht bald hoch: schneller
ab_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ab_cont
        inc h
ab_cont:
        djnz ab_scan
        ld a,d
        and e
        jr z,ab_set
        ld a,2
ab_set:
        ld hl,bomb_frame
        cp (hl)
        ret z                   ; Frame hat sich nicht geaendert
        ld (hl),a
        ld hl,bombs
        ld d,MAX_BOMBS
ab_loop:
        ld a,(hl)
        or a
        jr z,ab_skip
        push hl
        inc hl
        ld b,(hl)               ; x
        inc hl
        ld c,(hl)               ; y
        call tile_has_player
        call z,redraw_tile
        pop hl
ab_skip:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ab_next2
        inc h
ab_next2:
        dec d
        jr nz,ab_loop
        ret

; in: B = x, C = y; out: NZ = ein lebender Spieler steht auf der Kachel
; erhaelt BC, DE, HL
tile_has_player:
        ld a,(pl1+PALIVE)
        or a
        jr z,thp_p2
        ld a,(pl1+PX)
        cp b
        jr nz,thp_p2
        ld a,(pl1+PY)
        cp c
        jr z,thp_yes
thp_p2:
        ld a,(pl2+PALIVE)
        or a
        jr z,thp_no
        ld a,(pl2+PX)
        cp b
        jr nz,thp_no
        ld a,(pl2+PY)
        cp c
        jr z,thp_yes
thp_no:
        xor a                   ; Z: niemand da
        ret
thp_yes:
        ld a,1
        or a                    ; NZ: Spieler steht darauf
        ret

; in: HL = Bombenplatz (Zeit ist schon 0)
; setzt die Flammen: Zentrum und je Richtung bis Reichweite,
; gestoppt von Wand, Block oder Bombe
explode:
        inc hl
        ld a,(hl)
        ld (ex_cx),a
        inc hl
        ld a,(hl)
        ld (ex_cy),a
        inc hl
        inc hl
        ld a,(hl)
        ld (ex_range),a
        ld a,(ex_cx)
        ld b,a
        ld a,(ex_cy)
        ld c,a
        call set_flame          ; Zentrum
        xor a
        ld (ex_dir),a
ex_dir_loop:
        ld a,(ex_cx)
        ld b,a
        ld a,(ex_cy)
        ld c,a
        ld a,(ex_range)
        ld (ex_cnt),a
ex_step:
        ld a,(ex_dir)
        ld e,a
        ld d,0
        ld hl,dir_dx
        add hl,de
        ld a,b
        add a,(hl)
        ld b,a
        ld hl,dir_dy
        add hl,de
        ld a,c
        add a,(hl)
        ld c,a                  ; naechste Kachel in dieser Richtung
        call field_addr
        ld a,(hl)
        or a
        jr z,ex_flame           ; leer: Flamme
        cp 0x80
        jr c,ex_stop            ; Wand, Block, Bombe: hier ist Schluss
ex_flame:
        call set_flame          ; leer oder schon Flamme: (neu) setzen
        ld hl,ex_cnt
        dec (hl)
        jr nz,ex_step
ex_stop:
        ld hl,ex_dir
        inc (hl)
        ld a,(hl)
        cp 4
        jr c,ex_dir_loop
        ld a,1
        ld (dirty),a
        ret

; in: B = x, C = y; setzt die Kachel auf Flamme und zeichnet sie
set_flame:
        call field_addr
        ld (hl),FLAME_VAL
        jp redraw_tile

; Flammen herunterzaehlen, erloschene werden wieder leer
update_flames:
        ld hl,field
        ld d,0                  ; y
uf_row:
        ld e,0                  ; x
uf_col:
        ld a,(hl)
        bit 7,a
        jr z,uf_next
        dec a
        cp 0x80
        jr nz,uf_store
        xor a
        ld (hl),a               ; Flamme erloschen
        push hl
        ld b,e
        ld c,d
        call redraw_tile
        pop hl
        ld a,1
        ld (dirty),a
        jr uf_next
uf_store:
        ld (hl),a
uf_next:
        inc hl
        inc e
        ld a,e
        cp FW
        jr nz,uf_col
        inc d
        ld a,d
        cp FH
        jr nz,uf_row
        ret

; ============================================================
; anykey: Z gesetzt = keine Taste gedrueckt
; ============================================================
anykey:
        xor a
        in a,(0xFE)             ; alle Tastaturreihen gleichzeitig
        cpl
        and 0x1F
        ret

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
; Zufallszahlen (16-Bit xorshift)
; ============================================================
seed_init:
        ld hl,(23672)           ; Systemvariable FRAMES
        ld a,r
        xor l
        ld l,a
        ld a,h
        or l
        jr nz,seed_ok
        ld hl,0xACE1            ; Seed darf nicht 0 sein
seed_ok:
        ld (seed),hl
        ret

; out: A = Zufallsbyte; alle anderen Register bleiben erhalten
rnd:
        push hl
        ld hl,(seed)
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
        ld (seed),hl
        pop hl
        ret

; ============================================================
; Spielfeld erzeugen
; ============================================================
init_field:
        ld hl,field
        ld c,0                  ; y
if_row:
        ld b,0                  ; x
if_col:
        call tile_for
        ld (hl),a
        inc hl
        inc b
        ld a,b
        cp FW
        jr nz,if_col
        inc c
        ld a,c
        cp FH
        jr nz,if_row
        ret

; in:  B = x, C = y
; out: A = Kacheltyp
; veraendert: A, DE (BC und HL bleiben erhalten)
tile_for:
        ; Rand
        ld a,b
        or a
        jr z,tf_wall
        cp FW-1
        jr z,tf_wall
        ld a,c
        or a
        jr z,tf_wall
        cp FH-1
        jr z,tf_wall
        ; Saeulen: x und y beide gerade
        ld a,b
        or c
        and 1
        jr z,tf_wall
        ; Ecken freihalten: Abstand zur naechsten Ecke dx+dy <= 3
        ld a,b
        cp FW/2
        jr c,tf_dx
        ld a,FW-1
        sub b
tf_dx:
        ld e,a                  ; dx
        ld a,c
        cp FH/2
        jr c,tf_dy
        ld a,FH-1
        sub c
tf_dy:
        add a,e                 ; dx+dy
        cp 4
        jr c,tf_empty
        ; zufaellig Block oder leer
        call rnd
        cp BLOCK_CHANCE
        jr nc,tf_empty
        ld a,T_BLOCK
        ret
tf_empty:
        xor a                   ; T_EMPTY
        ret
tf_wall:
        ld a,T_WALL
        ret

; in:  B = x, C = y (Kachelkoordinaten)
; out: HL = Adresse der Kachel im Feld (field + y*15 + x)
; veraendert: A, HL (BC und DE bleiben erhalten)
field_addr:
        push de
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; y*16
        ld e,c
        ld d,0
        or a
        sbc hl,de               ; y*15
        ld e,b
        add hl,de               ; + x
        ld de,field
        add hl,de
        pop de
        ret

; ============================================================
; Spielfeld zeichnen
; ============================================================
draw_field:
        ld hl,field
        ld d,0                  ; y
df_row:
        ld e,0                  ; x
df_col:
        ld a,d
        add a,a
        add a,FIELD_ROW
        ld b,a                  ; Zeichenzeile
        ld a,e
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld a,(hl)
        call draw_tile          ; erhaelt BC, DE, HL
        inc hl
        inc e
        ld a,e
        cp FW
        jr nz,df_col
        inc d
        ld a,d
        cp FH
        jr nz,df_row
        ret

; in: B = x, C = y (Kachelkoordinaten)
; zeichnet die Kachel aus dem Spielfeld neu (ohne Spieler)
; erhaelt BC, DE; veraendert A, HL
redraw_tile:
        push bc
        push de
        call field_addr
        ld e,(hl)               ; Kacheltyp
        ld a,c
        add a,a
        add a,FIELD_ROW
        ld d,a                  ; Zeichenzeile
        ld a,b
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld b,d
        ld a,e
        call draw_tile
        pop de
        pop bc
        ret

; ============================================================
; draw_tile: eine 16x16-Kachel zeichnen
; in: A = Kacheltyp, B = Zeichenzeile, C = Zeichenspalte
; erhaelt BC, DE, HL
; ============================================================
draw_tile:
        push de
        push hl
        bit 7,a
        jr z,dt_type
        ld a,T_FLAME            ; Flammen-Bytes (0x80+Restdauer) -> Grafik 4
dt_type:
        cp T_BOMB
        jr nz,dt_go
        ld a,(bomb_frame)       ; Bombe: Animationsframe 0 oder 2
        add a,T_BOMB            ; -> Grafik 3 oder 5
dt_go:
        ld e,a
        ld d,0
        ld hl,tile_attr
        add hl,de
        ld a,(hl)
        ld (cur_attr),a         ; Attribut der Kachel
        ld l,e
        ld h,0
        add hl,hl               ; *2
        add hl,hl               ; *4
        add hl,hl               ; *8
        add hl,hl               ; *16
        add hl,hl               ; *32
        ld de,tile_gfx
        add hl,de               ; HL = Grafik der Kachel
        call draw_gfx
        pop hl
        pop de
        ret

; ============================================================
; draw_sprite: Spieler-Sprite zeichnen (Attribut in cur_attr)
; in: A = Richtung, B = Zeichenzeile, C = Zeichenspalte
; erhaelt BC, DE, HL
; ============================================================
draw_sprite:
        push de
        push hl
        ld l,a
        ld h,0
        add hl,hl               ; *2
        add hl,hl               ; *4
        add hl,hl               ; *8
        add hl,hl               ; *16
        add hl,hl               ; *32
        ld de,spr_gfx
        add hl,de
        call draw_gfx
        pop hl
        pop de
        ret

; ============================================================
; draw_gfx: 16x16-Grafik aus 4 Zellen (OL, OR, UL, UR) zeichnen
; in: HL = 32 Bytes Grafik, B = Zeile, C = Spalte, (cur_attr)
; erhaelt BC; HL zeigt danach hinter die Grafik
; ============================================================
draw_gfx:
        call draw_cell          ; oben links
        inc c
        call draw_cell          ; oben rechts
        dec c
        inc b
        call draw_cell          ; unten links
        inc c
        call draw_cell          ; unten rechts
        dec c
        dec b
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
; print_at: Text mit dem ROM-Zeichensatz ausgeben
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
        add hl,hl               ; *8
        ld de,0x3C00            ; ROM-Zeichensatz (Zeichen 32 liegt bei 0x3D00)
        add hl,de
        call draw_cell
        pop hl
        inc c
        jr print_at

; ============================================================
; Daten
; ============================================================
txt_title:
        db "XBLAST",0
txt_hint:
        db "LEERTASTE: NEU",0

; Startwerte der Spieler: x, y, Richtung, lebt, Verzoegerung, Attribut
; dazu: Reichweite, max. Bomben, Feuer, Spielernummer
pl_init:
        db 1,1,DIR_DOWN,1,0,ATTR_P1,2,1,0,0
        db FW-2,FH-2,DIR_UP,1,0,ATTR_P2,2,1,0,1

; Schrittweite je Richtung (hoch, rechts, runter, links)
dir_dx:
        db 0,1,0,255
dir_dy:
        db 255,0,1,0

; Attribute je Kacheltyp
tile_attr:
        db 0x01                 ; leer:  blaue Punkte auf schwarz
        db 0x4D                 ; Wand:  hell cyan auf blau
        db 0x7A                 ; Block: rot auf hellweiss (Ziegel)
        db 0x42                 ; Bombe: hell rot auf schwarz
        db 0x56                 ; Flamme: hell gelb auf rot
        db 0x42                 ; Bombe, Frame 2: hell rot auf schwarz

; Kachelgrafiken: je 4 Zellen (oben links, oben rechts,
; unten links, unten rechts) zu 8 Bytes = 32 Bytes
tile_gfx:
        ; leer
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x80
        db 0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        ; feste Wand
        db 0xFF,0x80,0xAA,0x95,0xAA,0x95,0xAA,0x95
        db 0xFF,0x01,0xA9,0x55,0xA9,0x55,0xA9,0x55
        db 0xAA,0x95,0xAA,0x95,0xAA,0x95,0x80,0xFF
        db 0xA9,0x55,0xA9,0x55,0xA9,0x55,0x01,0xFF
        ; Block (Ziegel)
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        ; Bombe
        db 0x00,0x00,0x00,0x00,0x01,0x07,0x0F,0x19
        db 0x04,0x0A,0x0C,0x30,0xC0,0xE0,0xF0,0xF8
        db 0x1B,0x3B,0x3F,0x1F,0x1F,0x0F,0x07,0x01
        db 0xF8,0xFC,0xFC,0xF8,0xF8,0xF0,0xE0,0x80
        ; Flamme
        db 0x00,0x01,0x01,0x07,0x0B,0x1F,0x37,0x7E
        db 0x00,0x80,0xC0,0xA0,0xF0,0x78,0xEC,0xFC
        db 0x6F,0x3D,0x1F,0x0B,0x07,0x03,0x00,0x00
        db 0xDE,0xF8,0xB8,0xF0,0x60,0xC0,0x80,0x00
        ; Bombe, Frame 2 (aufgeblaeht, Funken anders)
        db 0x00,0x00,0x00,0x00,0x07,0x0F,0x1F,0x31
        db 0x14,0x0C,0x3A,0x40,0xE0,0xF0,0xF8,0xFC
        db 0x37,0x37,0x3F,0x3F,0x3F,0x1F,0x1F,0x07
        db 0xFC,0xFC,0xFC,0xFC,0xFC,0xF8,0xF8,0xE0

; Spieler-Sprites (Blick hoch, rechts, runter, links), je 32 Bytes
spr_gfx:
        ; Blick hoch
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x1F,0x1F
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xF8,0xF8
        db 0x1F,0x1F,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0xF8,0xF8,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick rechts
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x19
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x38
        db 0x19,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x38,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick runter
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x1A
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x58
        db 0x1A,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x58,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick links
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x1C
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x98
        db 0x1C,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x98,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C

        end start
