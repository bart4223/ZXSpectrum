; ===========================================================================
; BREAKOUT fuer den ZX Spectrum 128K - Stufe 0
; Geruest: ULAplus (blind), Doppelpuffer, HUD, Waende, 14x8 Steine (16x8 px)
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
at_cur      equ VARS+16     ; 11 Bytes: bg, hud, wand, 8x stein
brickmap    equ VARS+32     ; 8x14 Bytes (1 = Stein da)

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
        inc a
        ld (mode_plus),a        ; Standard: erweiterte Farben (ULAplus)
        ld hl,brickmap
        ld de,brickmap+1
        ld bc,BRICK_ROWS*BRICK_COLS-1
        ld (hl),1
        ldir
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
        ld bc,11
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
        ld bc,11
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
        ld a,0x40
        ld (dbase),a
        ld a,0x58
        ld (abase),a
        call draw_screen
        ld a,0xC0
        ld (dbase),a
        ld a,0xD8
        ld (abase),a
        jp draw_screen

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

; ---- Daten ----
s_punkte:   db "PUNKTE 0000",0
s_leben:    db "LEBEN 3",0
s_rekord:   db "REKORD 0000",0

tile_solid: db 255,255,255,255,255,255,255,255
tile_bl:    db 255,255,255,255,255,255,255,0
tile_br:    db 254,254,254,254,254,254,254,0

; bg, hud, wand, 8 Steinreihen
at_plus:    db 0x00,0x07,0x80, 0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47
at_cls:     db 0x00,0x47,0x47, 0x42,0x02,0x46,0x06,0x44,0x45,0x41,0x43

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
