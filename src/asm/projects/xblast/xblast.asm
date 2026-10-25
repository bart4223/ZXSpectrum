; ============================================================
; XBlast fuer den ZX Spectrum - Stufe 0: Geruest und Spielfeld
; Assembler: pasmo   (pasmo --tapbas xblast.asm xblast.tap)
; ============================================================
; Spielfeld 15 x 11 Kacheln a 16x16 Pixel (2x2 Zeichenzellen)
; Feste Waende am Rand und auf jeder zweiten Kachel,
; zufaellige Bloecke, die vier Ecken bleiben frei.
; Eine beliebige Taste erzeugt ein neues Feld.
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

BLOCK_CHANCE equ 170            ; Blockwahrscheinlichkeit (von 256)

ATTR_TITLE  equ 0x46            ; hell gelb auf schwarz
ATTR_TEXT   equ 0x07            ; weiss auf schwarz

; ---- Variablen (freier RAM, nicht im TAP) -----------------
VARS        equ 0xA000
seed        equ VARS            ; 2 Bytes
cur_attr    equ VARS + 2        ; 1 Byte: Attribut fuer draw_cell
field       equ VARS + 16       ; FW*FH Bytes: Kacheltypen

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
        ld c,14
        call print_at

new_field:
        call init_field
        call draw_field

wait_release:
        call anykey
        jr nz,wait_release
wait_press:
        call rnd                ; Zufallszahlen mitlaufen lassen
        call anykey
        jr z,wait_press
        jr new_field

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

; ============================================================
; draw_tile: eine 16x16-Kachel zeichnen
; in: A = Kacheltyp, B = Zeichenzeile, C = Zeichenspalte
; erhaelt BC, DE, HL
; ============================================================
draw_tile:
        push bc
        push de
        push hl
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
        call draw_cell          ; oben links
        inc c
        call draw_cell          ; oben rechts
        dec c
        inc b
        call draw_cell          ; unten links
        inc c
        call draw_cell          ; unten rechts
        pop hl
        pop de
        pop bc
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
        db "TASTE: NEUES FELD",0

; Attribute je Kacheltyp
tile_attr:
        db 0x01                 ; leer:  blaue Punkte auf schwarz
        db 0x4D                 ; Wand:  hell cyan auf blau
        db 0x7A                 ; Block: rot auf hellweiss (Ziegel)

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

        end start
