; ============================================================
;  TRON fuer den ZX Spectrum 128K  -  Stufe 0: Spielfeld und Geruest
;  Assembler: pasmo (--tapbas)    Dateien: tron.asm / tron.tap
; ============================================================
;  Bildschirm: 32x24 Zellen
;    Zeilen 0-1   : HUD (P1 | TRON | P2)
;    Zeile  2     : oberer Rahmen
;    Zeilen 3-22  : Spielfeld (Zellen 1..30)  = 240x160 Pixel
;    Zeile  23    : unterer Rahmen
;  Rahmenzellen sind voll gesetzt (0xFF): ein Pixeltest am Zielpixel
;  erkennt die Wand ohne Koordinatenvergleich.
; ============================================================

TESTMODE        equ 0           ; 1 = Selbsttest der Pixelroutinen (nur Build-Skript)

                org 0x8000

VARS            equ 0xB000      ; Variablenbereich (Code muss darunter enden)
ytab            equ VARS        ; 192 Zeilenadressen (384 Byte)
plus_avail      equ VARS+0x200  ; 1 = ULAplus vorhanden
plus_on         equ VARS+0x201  ; 1 = erweiterter Farbraum aktiv
key_prev        equ VARS+0x202  ; letzter Zustand Taste C (Bit 3, 0 = gedrueckt)
txt_attr        equ VARS+0x203  ; Attribut fuer print_str
testres         equ VARS+0x300  ; Ergebnisse des Selbsttests

ATTR_FIELD      equ 0x47        ; BRIGHT, Paper 0, Ink 7
ATTR_FRAME      equ 0x43        ; BRIGHT, Paper 0, Ink 3 (Magenta/Violett)
ATTR_BLACK      equ 0x40
ATTR_P1         equ 0x45        ; Cyan
ATTR_P2         equ 0x42        ; Rot/Orange
ATTR_TITLE      equ 0x46        ; Gelb

ROW_FRAME_TOP   equ 2
ROW_FRAME_BOT   equ 23
COL_FRAME_L     equ 0
COL_FRAME_R     equ 31

; ------------------------------------------------------------
start:
                di
                ld sp,0x7FF0
                ld bc,0x7FFD            ; 128K: ROM 1 (48K-ROM), Bank 0, Bildschirm normal
                ld a,0x10
                out (c),a
                xor a
                out (0xFE),a            ; Rand schwarz

                ld a,0x08
                ld (key_prev),a         ; Taste C losgelassen
                xor a
                ld (plus_on),a
                call detect_plus
                ld a,(plus_avail)
                ld (plus_on),a          ; ULAplus automatisch an, wenn vorhanden
                call apply_mode

                call init_ytab
                call cls
                call draw_frame
                call draw_field_attrs
                call draw_hud

                if TESTMODE
                call selftest
                endif

                im 1
                ei
main:
                halt
                call read_keys
                jr main

; ------------------------------------------------------------
;  Bildschirm
; ------------------------------------------------------------
cls:
                ld hl,0x4000
                ld de,0x4001
                ld bc,6143
                ld (hl),0
                ldir
                ld hl,0x5800
                ld de,0x5801
                ld bc,767
                ld (hl),ATTR_BLACK
                ldir
                ret

; D=Zeile, E=Spalte -> HL = Adresse des ersten Bitmap-Bytes der Zelle
cell_addr:
                ld a,d
                and 0x18
                or 0x40
                ld h,a
                ld a,d
                and 7
                rrca
                rrca
                rrca
                or e
                ld l,a
                ret

; D=Zeile, E=Spalte -> HL = Attribut-Adresse (BC bleibt erhalten)
attr_addr:
                ld h,0
                ld l,d
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld d,0
                add hl,de
                ld de,0x5800
                add hl,de
                ret

; D=Zeile, E=Spalte: Zelle voll setzen (DE bleibt erhalten)
solid_cell:
                push de
                call cell_addr
                ld b,8
sc1:            ld (hl),0xFF
                inc h
                djnz sc1
                pop de
                ret

draw_frame:
                ld e,0
df1:            ld d,ROW_FRAME_TOP
                call solid_cell
                ld d,ROW_FRAME_BOT
                call solid_cell
                inc e
                ld a,e
                cp 32
                jr nz,df1
                ld d,ROW_FRAME_TOP+1
df2:            ld e,COL_FRAME_L
                call solid_cell
                ld e,COL_FRAME_R
                call solid_cell
                inc d
                ld a,d
                cp ROW_FRAME_BOT
                jr nz,df2
                ret

; Attribute von Rahmen und Spielfeld; mit ULAplus Schachbrett aus Paper 0/1
; (dezentes Neon-Gitter), im Classic-Modus komplett schwarz
draw_field_attrs:
                ld d,ROW_FRAME_TOP
dfa_r:          ld e,0
dfa_c:          ld a,d
                cp ROW_FRAME_TOP
                jr z,dfa_frame
                cp ROW_FRAME_BOT
                jr z,dfa_frame
                ld a,e
                cp COL_FRAME_L
                jr z,dfa_frame
                cp COL_FRAME_R
                jr z,dfa_frame
                ld c,ATTR_FIELD
                ld a,(plus_on)
                or a
                jr z,dfa_set
                ld a,d
                add a,e
                and 1
                add a,a
                add a,a
                add a,a                 ; Paper = 0 oder 1
                or ATTR_FIELD
                ld c,a
                jr dfa_set
dfa_frame:      ld c,ATTR_FRAME
dfa_set:        push de
                call attr_addr
                ld (hl),c
                pop de
                inc e
                ld a,e
                cp 32
                jr nz,dfa_c
                inc d
                ld a,d
                cp 24
                jr nz,dfa_r
                ret

; ------------------------------------------------------------
;  Text (eigener Mini-Zeichensatz, unabhaengig von der ROM)
;  Glyphen: 0-9 Ziffern, 10=P, 11=T, 12=R, 13=O, 14=N, 15=Leerzeichen
; ------------------------------------------------------------
; A=Glyphe, D=Zeile, E=Spalte (DE bleibt erhalten)
put_glyph:
                push de
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,font
                add hl,bc
                push hl
                call cell_addr
                ex de,hl
                pop hl
                ld b,8
pg1:            ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz pg1
                pop de
                ret

; HL=String (Glyphen, Ende 0xFF), D=Zeile, E=Startspalte, txt_attr = Farbe
print_str:
                ld a,(hl)
                cp 0xFF
                ret z
                push hl
                call put_glyph
                push de
                call attr_addr
                ld a,(txt_attr)
                ld (hl),a
                pop de
                pop hl
                inc hl
                inc e
                jr print_str

draw_hud:
                ld a,ATTR_P1
                ld (txt_attr),a
                ld hl,str_p1
                ld d,0
                ld e,1
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld hl,str_title
                ld d,0
                ld e,14
                call print_str
                ld a,ATTR_P2
                ld (txt_attr),a
                ld hl,str_p2
                ld d,0
                ld e,25
                call print_str
                ret

str_p1:         db 10,1,15,0,0,0,0xFF
str_title:      db 11,12,13,14,0xFF
str_p2:         db 10,2,15,0,0,0,0xFF

font:           ; 0-9
                db 0x00,0x3C,0x46,0x4A,0x52,0x62,0x3C,0x00
                db 0x00,0x18,0x28,0x08,0x08,0x08,0x3E,0x00
                db 0x00,0x3C,0x42,0x02,0x3C,0x40,0x7E,0x00
                db 0x00,0x3C,0x42,0x0C,0x02,0x42,0x3C,0x00
                db 0x00,0x08,0x18,0x28,0x48,0x7E,0x08,0x00
                db 0x00,0x7E,0x40,0x7C,0x02,0x42,0x3C,0x00
                db 0x00,0x3C,0x40,0x7C,0x42,0x42,0x3C,0x00
                db 0x00,0x7E,0x02,0x04,0x08,0x10,0x10,0x00
                db 0x00,0x3C,0x42,0x3C,0x42,0x42,0x3C,0x00
                db 0x00,0x3C,0x42,0x3E,0x02,0x04,0x38,0x00
                ; P T R O N Leerzeichen
                db 0x00,0x7C,0x42,0x42,0x7C,0x40,0x40,0x00
                db 0x00,0xFE,0x10,0x10,0x10,0x10,0x10,0x00
                db 0x00,0x7C,0x42,0x42,0x7C,0x44,0x42,0x00
                db 0x00,0x3C,0x42,0x42,0x42,0x42,0x3C,0x00
                db 0x00,0x42,0x62,0x52,0x4A,0x46,0x42,0x00
                db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

; ------------------------------------------------------------
;  Pixelroutinen (fuer die naechsten Stufen)
; ------------------------------------------------------------
; Zeilenadress-Tabelle: ytab[y] = Adresse des ersten Bytes der Pixelzeile y
init_ytab:
                ld hl,ytab
                ld c,0
yt1:            ld a,c
                and 0xC0
                rrca
                rrca
                rrca
                ld b,a
                ld a,c
                and 7
                or b
                or 0x40
                ld d,a                  ; High-Byte
                ld a,c
                and 0x38
                rlca
                rlca
                ld e,a                  ; Low-Byte
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                inc c
                ld a,c
                cp 192
                jr nz,yt1
                ret

; D=y (0..191), E=x (0..255) -> HL = Byte-Adresse, A = Bitmaske (DE bleibt)
pixel_addr:
                ld l,d
                ld h,0
                add hl,hl
                ld bc,ytab
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld a,e
                rrca
                rrca
                rrca
                and 0x1F
                or l
                ld l,a
                ld a,e
                and 7
                ld c,a
                ld b,0
                push hl
                ld hl,xmask
                add hl,bc
                ld a,(hl)
                pop hl
                ret

pixel_set:
                call pixel_addr
                or (hl)
                ld (hl),a
                ret

; Z = Pixel nicht gesetzt, NZ = gesetzt (Wand oder Spur)
pixel_test:
                call pixel_addr
                and (hl)
                ret

xmask:          db 0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01

; ------------------------------------------------------------
;  ULAplus (Ports 0xBF3B Auswahl / 0xFF3B Daten)
; ------------------------------------------------------------
; A=Wert: Palettenzelle 0 beschreiben und zuruecklesen, Z = gleich
dp_try:
                ld d,a
                ld bc,0xBF3B
                xor a
                out (c),a
                ld bc,0xFF3B
                out (c),d
                ld bc,0xBF3B
                xor a
                out (c),a
                ld bc,0xFF3B
                in a,(c)
                cp d
                ret

detect_plus:
                xor a
                ld (plus_avail),a
                ld a,0x55
                call dp_try
                ret nz
                ld a,0xAA
                call dp_try
                ret nz
                ld a,1
                ld (plus_avail),a
                ret

; plus_on = 1: Palette laden und ULAplus einschalten, sonst ausschalten
apply_mode:
                ld a,(plus_avail)
                or a
                ret z
                ld a,(plus_on)
                or a
                jr z,am_off
                call set_palette
                ld bc,0xBF3B
                ld a,0x40
                out (c),a
                ld bc,0xFF3B
                ld a,1
                out (c),a
                ret
am_off:         ld bc,0xBF3B
                ld a,0x40
                out (c),a
                ld bc,0xFF3B
                xor a
                out (c),a
                ret

set_palette:
                ld hl,palette
                ld d,0
sp1:            ld bc,0xBF3B
                out (c),d
                ld bc,0xFF3B
                ld a,(hl)
                out (c),a
                inc hl
                inc d
                ld a,d
                and 15
                jr nz,sp2
                ld hl,palette
sp2:            ld a,d
                cp 64
                jr nz,sp1
                ret

; GRB 3-3-2:  Tinte 0-7, Paper 0-7 (Index 8-15); gleiche Tabelle in allen vier CLUTs
palette:
                ; Tinte: schwarz, blau, orange, violett, gruen, cyan, gelb, weiss
                db 0x00,0x03,0x5C,0x1B,0xE0,0xE3,0xFC,0xFF
                ; Paper: schwarz, dunkles Blau (Gitter), Rest wie Tinte
                db 0x00,0x01,0x5C,0x1B,0xE0,0xE3,0xFC,0xFF

; ------------------------------------------------------------
;  Tastatur: C schaltet den Farbraum um (nur mit ULAplus)
; ------------------------------------------------------------
read_keys:
                ld a,0xFE
                in a,(0xFE)
                and 0x08                ; 0 = gedrueckt
                ld b,a
                ld a,(key_prev)
                ld c,a
                ld a,b
                ld (key_prev),a
                or a
                ret nz
                ld a,c
                or a
                ret z
                ; steigende Flanke -> umschalten
                ld a,(plus_avail)
                or a
                ret z
                ld a,(plus_on)
                xor 1
                ld (plus_on),a
                call apply_mode
                call draw_field_attrs
                ret

; ------------------------------------------------------------
;  Selbsttest (nur TESTMODE=1)
; ------------------------------------------------------------
                if TESTMODE
selftest:
                ld ix,testres           ; Ergebnis-Zeiger in IX (pixel_addr nutzt HL)
                ld d,40
                ld e,100
                call pixel_set
                ld d,40
                ld e,100
                call tst                ; 1: gesetztes Pixel
                ld d,40
                ld e,101
                call tst                ; 0: Nachbar
                ld d,100
                ld e,3
                call tst                ; 1: linke Wand
                ld d,100
                ld e,20
                call tst                ; 0: Feld
                ld d,50
                ld e,250
                call tst                ; 1: rechte Wand
                ld d,17
                ld e,100
                call tst                ; 1: oberer Rahmen
                ld d,185
                ld e,100
                call tst                ; 1: unterer Rahmen
                ld d,100
                ld e,127
                call tst                ; 0: Feldmitte
                ld d,191
                ld e,255
                call tst                ; 1: Ecke rechts unten
                ld d,20
                ld e,8
                call tst                ; 1: Ecke Wand/Feld (Zeile 2, Spalte 1)
                ld d,24
                ld e,8
                call tst                ; 0: erstes Feldpixel (Zeile 3, Spalte 1)
                ld d,0
                ld e,0
                call pixel_set          ; Testpixel links oben
                ld d,191
                ld e,0
                call pixel_set
                ret

tst:            call pixel_test
                jr z,tst0
                ld (ix+0),1
                inc ix
                ret
tst0:           ld (ix+0),0
                inc ix
                ret
                endif
