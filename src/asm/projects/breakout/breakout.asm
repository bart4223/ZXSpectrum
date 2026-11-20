; ===========================================================================
; BREAKOUT fuer den ZX Spectrum 128K - Stufe 4
; Geruest: ULAplus (blind), Doppelpuffer, HUD, Waende, 14x8 Steine (16x8 px)
; Stufe 1: Schlaeger (32 px, pixelgenau) mit Joystick 1 (Sinclair IF2: 6=links, 7=rechts)
; Stufe 2: Ball 4x4 (1-Pixel-Bewegung, 8.8-Festkomma), klebt am Schlaeger, Feuer (0) startet,
;          Abprall an Waenden und Decke, unten raus = zurueck auf den Schlaeger
; Stufe 3: Schlaegerabprall, 8 Zonen (je 4 px) bestimmen Winkel, Mindest-Vertikaltempo 1,0
; Stufe 4: Steine zerstoeren (Achsen getrennt: erst X, dann Y; Treffer macht den Schritt rueckgaengig
;          und kehrt diese Achse um), Punkte je Reihe 7/7/5/5/3/3/1/1, HUD-Punktestand
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
autocnt     equ VARS+0xA3   ; nur Testbau
hitcnt      equ VARS+0xA4   ; nur Testbau: Anzahl Schlaegertreffer
scorel      equ VARS+0xA5   ; Punkte BCD (niederwertig)
scoreh      equ VARS+0xA6   ; Punkte BCD (hoeherwertig)
bricks_left equ VARS+0xA7
sv_bx       equ VARS+0xA8   ; Ball vor dem Schritt (Wort)
sv_by       equ VARS+0xAA
bh_any      equ VARS+0xAC
bh_c0       equ VARS+0xAD
bh_c1       equ VARS+0xAE
bh_r1       equ VARS+0xAF
bh_r        equ VARS+0xB0
bh_c        equ VARS+0xB1
numbuf      equ VARS+0xB2   ; 5 Bytes
bm_ptr      equ VARS+0xB8   ; Wort

BRICK_Y0    equ 40          ; BRICK_ROW0 * 8
BRICK_Y1    equ 103         ; letzte Pixelzeile der Steine

AUTOPLAY    equ 0           ; 1 = Testbau: Schlaeger folgt dem Ball, Auto-Start
NOBRICKS    equ 0           ; 1 = Testbau: Ball fliegt durch die Steine

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
        if AUTOPLAY
        xor a
        ld (autocnt),a
        ld (hitcnt),a
        endif
        ld a,PAD_START
        ld (padx),a
        xor a
        ld (scorel),a
        ld (scoreh),a
        ld a,BRICK_ROWS*BRICK_COLS
        ld (bricks_left),a
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
        call print_score
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
        ld hl,brickmap
        ld (bm_ptr),hl
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
        ld hl,(bm_ptr)
        ld a,(hl)
        inc hl
        ld (bm_ptr),hl
        or a
        jr z,db_skip
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
db_skip:
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
        if AUTOPLAY
        call autoplay
        endif
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
        if AUTOPLAY
        ld a,(autocnt)
        inc a
        ld (autocnt),a
        cp 10
        ret c
        xor a
        ld (autocnt),a
        jr bu_launch
        endif
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
bu_launch:
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
        ; --- X-Schritt ---
        ld hl,(bx_l)
        ld (sv_bx),hl
        ld de,(vx_l)
        add hl,de
        ld (bx_l),hl
        ld a,(bx_h)
        cp BALL_XMIN
        jr nc,bu_xr
        ld a,BALL_XMIN
        ld (bx_h),a
        xor a
        ld (bx_l),a
        call neg_vx
        jr bu_xb
bu_xr:  cp BALL_XMAX+1
        jr c,bu_xb
        ld a,BALL_XMAX
        ld (bx_h),a
        xor a
        ld (bx_l),a
        call neg_vx
bu_xb:  call brick_hit
        or a
        jr z,bu_ystep
        ld hl,(sv_bx)           ; Stein getroffen: X-Schritt zurueck, X umkehren
        ld (bx_l),hl
        call neg_vx
        ; --- Y-Schritt ---
bu_ystep:
        ld hl,(by_l)
        ld (sv_by),hl
        ld de,(vy_l)
        add hl,de
        ld (by_l),hl
        ld a,(by_h)
        cp BALL_YMIN
        jr nc,bu_ynb
        ld a,BALL_YMIN
        ld (by_h),a
        xor a
        ld (by_l),a
        jp neg_vy
bu_ynb: call brick_hit
        or a
        jr z,bu_ypad
        ld hl,(sv_by)           ; Stein getroffen: Y-Schritt zurueck, Y umkehren
        ld (by_l),hl
        jp neg_vy
bu_ypad:
        ld a,(by_h)
bu_yb:  ld b,a                  ; B = by_h
        ld a,(vy_h)
        bit 7,a
        jr nz,bu_nopad          ; Ball steigt
        ld a,b
        cp BALL_Y0              ; Ballunterkante erreicht Schlaegeroberkante
        jr c,bu_nopad
        cp BALL_Y0+6            ; tiefer als die Schlaegerdicke: vorbei
        jr nc,bu_nopad
        ld a,(padx)
        ld c,a
        ld a,(bx_h)
        add a,4
        cp c
        jr c,bu_nopad           ; Ball rechts von ... links vom Schlaeger
        jr z,bu_nopad
        ld a,c
        add a,32
        ld c,a
        ld a,(bx_h)
        cp c
        jr nc,bu_nopad          ; Ball rechts vom Schlaeger
        ld a,(bx_h)             ; Treffer: Zone = (Ballmitte - Schlaeger links) / 4
        add a,2
        ld hl,padx
        sub (hl)
        jr c,bu_z0
        cp 32
        jr c,bu_zok
        ld a,31
        jr bu_zok
bu_z0:  xor a
bu_zok: srl a
        srl a
        add a,a
        add a,a                 ; * 4 Bytes je Zone
        ld e,a
        ld d,0
        ld hl,zone_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (vx_l),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (vy_l),de
        ld a,BALL_Y0            ; Ball auf den Schlaeger setzen
        ld (by_h),a
        xor a
        ld (by_l),a
        if AUTOPLAY
        ld a,(hitcnt)
        inc a
        ld (hitcnt),a
        endif
        ret
bu_nopad:
        ld a,(by_h)
        cp BALL_LOST
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


; Testbau: Schlaeger folgt dem fliegenden Ball, Trefferstelle wandert ueber alle Zonen
        if AUTOPLAY
autoplay:
        ld a,(bstate)
        or a
        ret z
        ld a,(hitcnt)
        ld b,a
        add a,a
        add a,a
        add a,b                 ; *5
        add a,3
        and 31
        ld b,a                  ; gewuenschte Trefferstelle
        ld a,(bx_h)
        add a,2
        sub b
        jr c,ap_min
        cp PAD_MIN
        jr nc,ap_1
ap_min: ld a,PAD_MIN
ap_1:   cp PAD_MAX+1
        jr c,ap_2
        ld a,PAD_MAX
ap_2:   ld (padx),a
        ret
        endif

; vx, vy je Zone (8.8, vorzeichenbehaftet): flach an den Raendern, steil in der Mitte
zone_tab:
        dw 65536-512, 65536-256         ; Zone 0: links aussen
        dw 65536-384, 65536-435
        dw 65536-256, 65536-512
        dw 65536-128, 65536-563
        dw 128, 65536-563
        dw 256, 65536-512
        dw 384, 65536-435
        dw 512, 65536-256               ; Zone 7: rechts aussen

ball_spr:
        include "ball.inc"

; ===========================================================================
; Stufe 4: Steine
; ===========================================================================
; Ball-Box (bx_h, by_h, 4x4) gegen das Steinraster. A=0: kein Stein, A=1: Steine
; entfernt (Karte, beide Puffer, Punkte, HUD)
brick_hit:
        if NOBRICKS
        xor a
        ret
        endif
        xor a
        ld (bh_any),a
        ld a,(by_h)
        cp BRICK_Y1+1
        jp nc,bh_none           ; Oberkante unterhalb der Steine
        add a,3                 ; Unterkante
        cp BRICK_Y0
        jp c,bh_none            ; Unterkante oberhalb der Steine
        sub BRICK_Y0
        srl a
        srl a
        srl a
        cp BRICK_ROWS
        jr c,bh_r1ok
        ld a,BRICK_ROWS-1
bh_r1ok:
        ld (bh_r1),a
        ld a,(by_h)
        sub BRICK_Y0
        jr nc,bh_r0ok
        xor a
        jr bh_r0st
bh_r0ok:
        srl a
        srl a
        srl a
bh_r0st:
        ld (bh_r),a
        ld a,(bx_h)
        sub 16
        srl a
        srl a
        srl a
        srl a
        ld (bh_c0),a
        ld a,(bx_h)
        add a,3
        sub 16
        srl a
        srl a
        srl a
        srl a
        ld (bh_c1),a
bh_row:
        ld a,(bh_c0)
        ld (bh_c),a
bh_col:
        ld a,(bh_r)             ; Index = Reihe*14 + Spalte
        ld e,a
        add a,a
        add a,a
        add a,a
        sub e
        add a,a
        ld b,a
        ld a,(bh_c)
        add a,b
        ld e,a
        ld d,0
        ld hl,brickmap
        add hl,de
        ld a,(hl)
        or a
        jr z,bh_next
        ld (hl),0
        ld a,(bh_r)
        ld e,a
        ld d,0
        ld hl,pts_row
        add hl,de
        ld a,(hl)
        call add_score
        ld hl,bricks_left
        dec (hl)
        ld a,1
        ld (bh_any),a
        call erase_brick
bh_next:
        ld a,(bh_c1)
        ld b,a
        ld a,(bh_c)
        cp b
        jr nc,bh_nextrow
        inc a
        ld (bh_c),a
        jr bh_col
bh_nextrow:
        ld a,(bh_r1)
        ld b,a
        ld a,(bh_r)
        cp b
        jr nc,bh_done
        inc a
        ld (bh_r),a
        jr bh_row
bh_done:
        ld a,(bh_any)
        or a
        ret z
        call score_both
        ld a,1
        ret
bh_none:
        xor a
        ret

; Stein (bh_r, bh_c) aus beiden Puffern loeschen (Bitmap leer, Attribut = Hintergrund)
erase_brick:
        ld a,0x40
        ld (dbase),a
        ld a,0x58
        ld (abase),a
        call eb_one
        ld a,0xC0
        ld (dbase),a
        ld a,0xD8
        ld (abase),a
eb_one:
        ld a,(bh_r)
        add a,BRICK_ROW0
        ld b,a
        ld a,(bh_c)
        add a,a
        add a,BRICK_COL0
        ld c,a
        ld de,tile_blank
        ld a,(at_cur)
        call put_tile
        inc c
        ld de,tile_blank
        ld a,(at_cur)
        jp put_tile

; A = Punkte (BCD) addieren
add_score:
        ld b,a
        ld a,(scorel)
        add a,b
        daa
        ld (scorel),a
        ld a,(scoreh)
        adc a,0
        daa
        ld (scoreh),a
        ret

; Punktestand in beide Puffer zeichnen
score_both:
        ld a,0x40
        ld (dbase),a
        ld a,0x58
        ld (abase),a
        call print_score
        ld a,0xC0
        ld (dbase),a
        ld a,0xD8
        ld (abase),a
        jp print_score

; Punktestand (4 Ziffern) bei Zeile 0, Spalte 7 in den Puffer aus dbase/abase
print_score:
        ld a,(scoreh)
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,'0'
        ld (numbuf),a
        ld a,(scoreh)
        and 15
        add a,'0'
        ld (numbuf+1),a
        ld a,(scorel)
        rrca
        rrca
        rrca
        rrca
        and 15
        add a,'0'
        ld (numbuf+2),a
        ld a,(scorel)
        and 15
        add a,'0'
        ld (numbuf+3),a
        xor a
        ld (numbuf+4),a
        ld hl,numbuf
        ld b,0
        ld c,7
        ld a,(at_cur+1)
        jp print_str

; ---- Daten ----
s_punkte:   db "PUNKTE 0000",0
s_leben:    db "LEBEN 3",0
s_rekord:   db "REKORD 0000",0

tile_solid: db 255,255,255,255,255,255,255,255
tile_blank: db 0,0,0,0,0,0,0,0
pts_row:    db 7,7,5,5,3,3,1,1      ; Punkte je Steinreihe (BCD, oben nach unten)
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
