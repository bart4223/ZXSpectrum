; ===========================================================================
; BREAKOUT fuer den ZX Spectrum 128K - Stufe 2
; Geruest: ULAplus (blind), Doppelpuffer, HUD, Waende, 14x8 Steine (16x8 px)
; Stufe 1: Schlaeger (32 px, pixelgenau) mit Joystick 1 (Sinclair IF2: 6=links, 7=rechts)
; Stufe 2: Ball 4x4 (1-Pixel-Bewegung, 8.8-Festkomma), klebt am Schlaeger, Feuer (0) startet,
;          Abprall an Waenden und Decke, unten raus = zurueck auf den Schlaeger
; Assembler: pasmo --tapbas
; ===========================================================================
        org 0x8000

STACK       equ 0xBFF0
VARS        equ 0xB400
ISR_VEC     equ 0xFDFD

BRICK_ROW0  equ 5           ; erste Steinreihe (Zellzeile)
BRICK_COL0  equ 2           ; erste Steinspalte (Zelle)
BRICK_ROWS  equ 8
BRICK_COLS  equ 14

; ---- Variablen (ungebremstes RAM, zur Laufzeit initialisiert) ----
frame       equ VARS+0
pagebits    equ VARS+1
mode_plus   equ VARS+2
keyprev     equ VARS+3
dbase       equ VARS+4
abase       equ VARS+5
pattr       equ VARS+6
v_row       equ VARS+7
v_col       equ VARS+8
v_n         equ VARS+9
v_m         equ VARS+10
padx        equ VARS+11     ; Schlaeger links, Pixel 16..208
hold        equ VARS+12     ; Frames gleiche Richtung gehalten
hdir        equ VARS+13
oldx0       equ VARS+14     ; alte Position im Puffer Bank 5
oldx1       equ VARS+15     ; alte Position im Puffer Bank 7
at_cur      equ VARS+16     ; 12 Bytes: bg, hud, wand, 8x stein, schlaeger
brickmap    equ VARS+32     ; 8x14 Bytes (1 = Stein da)
p_flag      equ VARS+0x90   ; 1 = zeichnen, 0 = loeschen
p_k         equ VARS+0x91
p_mask      equ VARS+0x92

bx_l        equ VARS+0x94   ; Ball-Position 8.8 (Pixel in *_h)
bx_h        equ VARS+0x95
by_l        equ VARS+0x96
by_h        equ VARS+0x97
vx_l        equ VARS+0x98   ; Geschwindigkeit 8.8, vorzeichenbehaftet
vx_h        equ VARS+0x99
vy_l        equ VARS+0x9A
vy_h        equ VARS+0x9B
bstate      equ VARS+0x9C   ; 0 = klebt am Schlaeger, 1 = fliegt
firprev     equ VARS+0x9D
launchdir   equ VARS+0x9E   ; Startrichtung wechselt je Start
obx0        equ VARS+0x9F   ; alte Ballposition im Puffer Bank 5 (y=0xFF: keine)
oby0        equ VARS+0xA0
obx1        equ VARS+0xA1   ; ... im Puffer Bank 7
oby1        equ VARS+0xA2

BALL_XMIN   equ 16
BALL_XMAX   equ 236         ; 240 - 4
BALL_YMIN   equ 16
BALL_LOST   equ 189         ; ab hier unten raus
BALL_Y0     equ 173         ; Ball sitzt auf dem Schlaeger
BALL_VX     equ 0x0100      ; 1,0 Pixel/Bild
BALL_VY     equ 0x0200      ; 2,0 Pixel/Bild

PAD_ROW     equ 22
PAD_MIN     equ 16
PAD_MAX     equ 208
PAD_START   equ 112
PAD_SPD1    equ 2           ; Schlaegertempo (Pixel/Bild) - Anfang
PAD_SPD2    equ 3           ; nach PAD_T2 Bildern
PAD_SPD3    equ 4           ; nach PAD_T3 Bildern
PAD_T2      equ 8
PAD_T3      equ 24

start:
        di
        ld sp,STACK
        ld bc,0x7FFD
        ld a,0x17               ; ROM1, Bank 7 bei 0xC000, Bild Bank 5
        out (c),a
        ld (pagebits),a
        ; --- IM2: Tabelle 0xFE00..0xFF00 = 0xFD, Sprung bei 0xFDFD ---
        ld hl,0xFE00
        ld de,0xFE01
        ld bc,0x0100
        ld (hl),0xFD
        ldir
        ld a,0xC3
        ld (ISR_VEC),a
        ld hl,isr
        ld (ISR_VEC+1),hl
        ld a,0xFE
        ld i,a
        im 2
        xor a
        ld (frame),a
        ld (keyprev),a
        ld (hold),a
        ld (hdir),a
        ld (bstate),a
        ld (firprev),a
        ld (launchdir),a
        inc a
        ld (mode_plus),a        ; Standard: erweiterte Farben (ULAplus)
        ld hl,brickmap
        ld de,brickmap+1
        ld bc,BRICK_ROWS*BRICK_COLS-1
        ld (hl),1
        ldir
        ld a,PAD_START
        ld (padx),a
        call apply_mode
        call draw_all
        ei
main:
        ld a,(frame)
        ld b,a
mwait:  halt
        ld a,(frame)
        cp b
        jr z,mwait
        call flip
        call keys
        call frame_logic
        jr main

; ---- Interrupt: nur Bildzaehler ----
isr:
        push af
        ld a,(frame)
        inc a
        ld (frame),a
        pop af
        ei
        reti

; ---- Anzeigepuffer umschalten (Bank 5 <-> Bank 7) ----
flip:
        ld a,(pagebits)
        xor 0x08
        ld (pagebits),a
        ld bc,0x7FFD
        out (c),a
        ret

; ---- Taste C: Farbraum umschalten ----
keys:
        ld a,0xFE
        in a,(0xFE)
        cpl
        and 0x08
        ld b,a
        ld a,(keyprev)
        ld c,a
        ld a,b
        ld (keyprev),a
        or a
        ret z
        ld a,c
        or a
        ret nz
        ld a,(mode_plus)
        xor 1
        ld (mode_plus),a
        call apply_mode
        jp draw_all

; ---- Farbraum anwenden: Attributtabelle, Palette/Modus blind schreiben ----
apply_mode:
        ld a,(mode_plus)
        or a
        jr z,am_classic
        ld hl,at_plus
        ld de,at_cur
        ld bc,12
        ldir
        call set_palette
        ld bc,0xBF3B
        ld a,0x40
        out (c),a
        ld bc,0xFF3B
        ld a,1
        out (c),a
        ret
am_classic:
        ld hl,at_cls
        ld de,at_cur
        ld bc,12
        ldir
        ld bc,0xBF3B
        ld a,0x40
        out (c),a
        ld bc,0xFF3B
        xor a
        out (c),a
        ret

set_palette:
        ld hl,pal_plus
        ld e,0
sp_loop:
        ld bc,0xBF3B
        ld a,e
        out (c),a
        ld bc,0xFF3B
        ld a,(hl)
        out (c),a
        inc hl
        inc e
        ld a,e
        cp 64
        jr nz,sp_loop
        ret

; ---- statische Grafik in beide Puffer ----
draw_all:
        ld a,0xFF
        ld (oby0),a
        ld (oby1),a
        ld a,0x40
        ld (dbase),a
        ld a,0x58
        ld (abase),a
        call draw_screen
        ld a,0xC0
        ld (dbase),a
        ld a,0xD8
        ld (abase),a
        call draw_screen
        jp pad_redraw

draw_screen:
        ld a,(dbase)
        ld h,a
        ld l,0
        ld bc,0x1800
        xor a
        call fill
        ld a,(abase)
        ld h,a
        ld l,0
        ld bc,0x0300
        ld a,(at_cur)
        call fill
        ld hl,s_punkte
        ld b,0
        ld c,0
        ld a,(at_cur+1)
        call print_str
        ld hl,s_leben
        ld b,0
        ld c,12
        ld a,(at_cur+1)
        call print_str
        ld hl,s_rekord
        ld b,0
        ld c,20
        ld a,(at_cur+1)
        call print_str
        ld a,(abase)
        add a,2
        ld h,a
        ld l,0xC2               ; Zeile 22, Spalte 2
        ld bc,28
        ld a,(at_cur+11)
        call fill
        call draw_walls
        jp draw_bricks

; HL = Ziel, BC = Laenge, A = Wert
fill:
        ld (hl),a
        ld d,h
        ld e,l
        inc de
        dec bc
        ldir
        ret

; B=Zeile, C=Spalte -> HL = Pixeladresse (Zeile 0 der Zelle), Puffer aus dbase
cell_pix:
        ld a,b
        and 0x18
        ld h,a
        ld a,(dbase)
        or h
        ld h,a
        ld a,b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l,a
        ret

; B=Zeile, C=Spalte -> HL = Attributadresse, Puffer aus abase
cell_attr:
        ld a,b
        rrca
        rrca
        rrca
        and 3
        ld h,a
        ld a,(abase)
        add a,h
        ld h,a
        ld a,b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l,a
        ret

; B=Zeile, C=Spalte, DE=Kachel (8 Bytes), A=Attribut; erhaelt B, C
put_tile:
        push af
        push de
        call cell_pix
        pop de
        push bc
        ld b,8
pt_l:   ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz pt_l
        pop bc
        call cell_attr
        pop af
        ld (hl),a
        ret

; HL = Text (0-terminiert), B=Zeile, C=Spalte, A=Attribut
print_str:
        ld (pattr),a
ps_loop:
        ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,font
        add hl,de
        ex de,hl
        ld a,(pattr)
        call put_tile
        pop hl
        inc c
        jr ps_loop

draw_walls:
        ld a,1
        ld (v_row),a
        xor a
        ld (v_col),a
dw_top:
        ld a,(v_row)
        ld b,a
        ld a,(v_col)
        ld c,a
        call dw_cell
        ld a,(v_col)
        inc a
        ld (v_col),a
        cp 32
        jr nz,dw_top
        ld a,2
        ld (v_row),a
dw_side:
        ld a,(v_row)
        ld b,a
        ld c,0
        call dw_cell
        ld c,1
        call dw_cell
        ld c,30
        call dw_cell
        ld c,31
        call dw_cell
        ld a,(v_row)
        inc a
        ld (v_row),a
        cp 24
        jr nz,dw_side
        ret
dw_cell:
        ld de,tile_solid
        ld a,(at_cur+2)
        jp put_tile

draw_bricks:
        ld ix,at_cur+3
        ld a,BRICK_ROW0
        ld (v_row),a
        ld a,BRICK_ROWS
        ld (v_n),a
db_row:
        ld a,BRICK_COL0
        ld (v_col),a
        ld a,BRICK_COLS
        ld (v_m),a
db_col:
        ld a,(v_row)
        ld b,a
        ld a,(v_col)
        ld c,a
        ld de,tile_bl
        ld a,(ix+0)
        call put_tile
        inc c
        ld de,tile_br
        ld a,(ix+0)
        call put_tile
        ld a,(v_col)
        add a,2
        ld (v_col),a
        ld a,(v_m)
        dec a
        ld (v_m),a
        jr nz,db_col
        inc ix
        ld a,(v_row)
        inc a
        ld (v_row),a
        ld a,(v_n)
        dec a
        ld (v_n),a
        jr nz,db_row
        ret

; ===========================================================================
; Stufe 1: Schlaeger
; ===========================================================================
; Joystick 1 lesen, Position mit Beschleunigung aendern, in den verdeckten
; Puffer zeichnen (alte Position dieses Puffers loeschen)
frame_logic:
        call read_input
        call ball_update
        ld a,(pagebits)
        and 8
        ld hl,oldx0
        ld ix,obx0
        ld b,0x40               ; Bild zeigt Bank 7 -> zeichnen in Bank 5
        jr nz,fl_have
        ld hl,oldx1
        ld ix,obx1
        ld b,0xC0
fl_have:
        ld a,b
        ld (dbase),a
        push hl
        ld a,(ix+1)             ; alten Ball per XOR entfernen
        cp 0xFF
        jr z,fl_noball
        ld b,a
        ld a,(ix+0)
        call ball_xor
fl_noball:
        xor a
        ld (p_flag),a
        pop hl
        push hl
        ld a,(hl)
        call put_pad
        ld a,1
        ld (p_flag),a
        ld a,(padx)
        call put_pad
        pop hl
        ld a,(padx)
        ld (hl),a
        ld a,(bx_h)             ; neuen Ball per XOR zeichnen
        ld (ix+0),a
        ld a,(by_h)
        ld (ix+1),a
        ld b,a
        ld a,(bx_h)
        jp ball_xor

; beide Puffer neu zeichnen (nach Farbraumwechsel)
pad_redraw:
        ld a,0x40
        ld (dbase),a
        ld a,1
        ld (p_flag),a
        ld a,(padx)
        call put_pad
        ld a,0xC0
        ld (dbase),a
        ld a,(padx)
        call put_pad
        ld a,(padx)
        ld (oldx0),a
        ld (oldx1),a
        ret

; Sinclair IF2 Joystick 1: Taste 6 = links (Bit 4), 7 = rechts (Bit 3) an Port 0xEFFE
read_input:
        ld a,0xEF
        in a,(0xFE)
        cpl
        ld b,a
        bit 4,b
        jr z,ri_noleft
        ld c,0xFF
        jr ri_dir
ri_noleft:
        bit 3,b
        jr z,ri_none
        ld c,1
        jr ri_dir
ri_none:
        xor a
        ld (hold),a
        ld (hdir),a
        ret
ri_dir:
        ld a,(hdir)
        cp c
        jr z,ri_same
        ld a,c
        ld (hdir),a
        xor a
        ld (hold),a
        jr ri_speed
ri_same:
        ld a,(hold)
        cp 255
        jr z,ri_speed
        inc a
        ld (hold),a
ri_speed:
        ld a,(hold)
        ld b,PAD_SPD1
        cp PAD_T2
        jr c,ri_move
        ld b,PAD_SPD2
        cp PAD_T3
        jr c,ri_move
        ld b,PAD_SPD3
ri_move:
        ld a,(padx)
        bit 7,c
        jr nz,ri_left
        add a,b
        cp PAD_MAX+1
        jr c,ri_store
        ld a,PAD_MAX
        jr ri_store
ri_left:
        sub b
        jr c,ri_min
        cp PAD_MIN
        jr nc,ri_store
ri_min:
        ld a,PAD_MIN
ri_store:
        ld (padx),a
        ret

; A = x (Pixel), p_flag: 1 = Schlaeger zeichnen, 0 = loeschen; Puffer aus dbase
; Schlaeger 32 px breit, Zeilen 1..6 der Zellzeile PAD_ROW
put_pad:
        ld c,a
        and 7
        ld e,a                  ; E = Verschiebung
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        ld c,a                  ; C = erste Spalte
        ld d,5
        ld a,e
        or a
        jr nz,pp_go
        dec d                   ; Verschiebung 0 -> nur 4 Zellen
pp_go:
        xor a
        ld (p_k),a
pp_cell:
        ld a,(p_flag)
        or a
        jr z,pp_have            ; loeschen: Maske 0
        ld a,(p_k)
        or a
        jr z,pp_first
        cp 4
        ld a,0xFF
        jr nz,pp_have
        ld hl,mask_right
        jr pp_idx
pp_first:
        ld hl,mask_left
pp_idx:
        ld a,e
        add a,l
        ld l,a
        ld a,0
        adc a,h
        ld h,a
        ld a,(hl)
pp_have:
        ld (p_mask),a
        ld b,PAD_ROW
        call cell_pix
        ld a,(p_mask)
        inc h
        ld b,6
pp_l:   ld (hl),a
        inc h
        djnz pp_l
        ld a,(p_k)
        inc a
        ld (p_k),a
        inc c
        dec d
        jr nz,pp_cell
        ret

mask_left:  db 0xFF,0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01
mask_right: db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE

; ===========================================================================
; Stufe 2: Ball
; ===========================================================================
ball_update:
        ld a,(bstate)
        or a
        jr nz,bu_fly
        call bu_follow
        ld a,0xEF               ; Feuer = Taste 0 (Bit 0), Flanke
        in a,(0xFE)
        cpl
        and 1
        ld b,a
        ld a,(firprev)
        ld c,a
        ld a,b
        ld (firprev),a
        or a
        ret z
        ld a,c
        or a
        ret nz
        ld a,1                  ; Start
        ld (bstate),a
        ld a,(launchdir)
        xor 1
        ld (launchdir),a
        ld hl,BALL_VX
        jr nz,bu_vx
        ld hl,0x10000-BALL_VX
bu_vx:  ld (vx_l),hl
        ld hl,0x10000-BALL_VY
        ld (vy_l),hl
        ret

bu_follow:
        ld a,(padx)
        add a,14
        ld (bx_h),a
        ld a,BALL_Y0
        ld (by_h),a
        xor a
        ld (bx_l),a
        ld (by_l),a
        ret

bu_fly:
        ld a,0xEF
        in a,(0xFE)
        cpl
        and 1
        ld (firprev),a
        ld hl,(bx_l)
        ld de,(vx_l)
        add hl,de
        ld (bx_l),hl
        ld hl,(by_l)
        ld de,(vy_l)
        add hl,de
        ld (by_l),hl
        ld a,(bx_h)
        cp BALL_XMIN
        jr nc,bu_xr
        ld a,BALL_XMIN
        ld (bx_h),a
        xor a
        ld (bx_l),a
        call neg_vx
        jr bu_y
bu_xr:  cp BALL_XMAX+1
        jr c,bu_y
        ld a,BALL_XMAX
        ld (bx_h),a
        xor a
        ld (bx_l),a
        call neg_vx
bu_y:   ld a,(by_h)
        cp BALL_YMIN
        jr nc,bu_yb
        ld a,BALL_YMIN
        ld (by_h),a
        xor a
        ld (by_l),a
        jp neg_vy
bu_yb:  cp BALL_LOST
        ret c
        xor a                   ; unten raus: zurueck auf den Schlaeger
        ld (bstate),a
        jp bu_follow

neg_vx:
        ld hl,(vx_l)
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld (vx_l),hl
        ret
neg_vy:
        ld hl,(vy_l)
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld (vy_l),hl
        ret

; Ball per XOR zeichnen/loeschen: A = x, B = y (Pixel), Puffer aus dbase
ball_xor:
        ld c,a
        and 7
        add a,a
        add a,a
        add a,a                 ; Verschiebung * 8
        ld e,a
        ld d,0
        ld hl,ball_spr
        add hl,de
        ex de,hl                ; DE = Sprite
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        ld c,a                  ; C = Spalte
        ld a,4
        ld (p_k),a
bxo_loop: ld a,b
        and 0xC0
        rrca
        rrca
        rrca
        ld h,a
        ld a,b
        and 7
        or h
        ld h,a
        ld a,(dbase)
        or h
        ld h,a
        ld a,b
        and 0x38
        add a,a
        add a,a
        or c
        ld l,a
        ld a,(de)
        xor (hl)
        ld (hl),a
        inc de
        inc hl
        ld a,(de)
        xor (hl)
        ld (hl),a
        inc de
        inc b
        ld a,(p_k)
        dec a
        ld (p_k),a
        jr nz,bxo_loop
        ret

ball_spr:
        include "ball.inc"

; ---- Daten ----
s_punkte:   db "PUNKTE 0000",0
s_leben:    db "LEBEN 3",0
s_rekord:   db "REKORD 0000",0

tile_solid: db 255,255,255,255,255,255,255,255
tile_bl:    db 255,255,255,255,255,255,255,0
tile_br:    db 254,254,254,254,254,254,254,0

; bg, hud, wand, 8 Steinreihen, Schlaeger
at_plus:    db 0x07,0x07,0x80, 0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47, 0x07
at_cls:     db 0x47,0x47,0x47, 0x42,0x02,0x46,0x06,0x44,0x45,0x41,0x43, 0x47

; ULAplus-Palette GGGRRRBB: CLUT0 Standard, CLUT1 Regenbogen, CLUT2 Wand
pal_plus:
        db 0x00,0x03,0x1C,0x1F,0xE0,0xE3,0xFC,0xFF
        db 0x00,0x03,0x1C,0x1F,0xE0,0xE3,0xFC,0xFF
        db 0x1C,0x7C,0xDC,0xE0,0xE3,0x4B,0x37,0x1F
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x92,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

font:
        include "font.inc"

code_end:
        end start
