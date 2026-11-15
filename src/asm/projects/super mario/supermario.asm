; ===========================================================
;  SUPERMARIO (Feuerwehr-Jump'n'Run)  -  ZX Spectrum 128K
;  Stufe 1: Feuerwehrmann laeuft (klein/gross), Doppelpuffer, ULAplus
;  Assembler: pasmo   (pasmo --tapbas --name supermario supermario.asm supermario.tap)
;  Diese Datei wird aus src/supermario.asm.in + tools/gen.py erzeugt.
;
;  Steuerung: Joystick 1 (Sinclair, Tasten 6-0) oder O/P, Leertaste/Feuer = Start
;             G = zwischen klein und gross umschalten (Test, ab Stufe 7 Power-up)
;  Speicher:  Code ab 6000h; Variablen ab VARS (nicht im TAP); IM2-Tabelle 0BE00h;
;             Bank 7 (0C000h) = zweiter Bildschirm, Stack ganz oben.
; ===========================================================

ULAPLUS         equ 1                   ; 1 = ULAplus (Auslieferung), 0 = nur Diagnose-Build ohne Portzugriff

VARS            equ 0B800h
IM2TAB          equ 0BE00h              ; 257 Bytes 0BFh
IM2VEC          equ 0BFBFh              ; Handler: ei / reti
STACKTOP        equ 0FFF0h
BANKREG         equ 7FFDh

; ---- Eingabe-Bits (wie Sinclair-Joystick 1, nach CPL) ----
I_FIRE          equ 01h
I_UP            equ 02h
I_DOWN          equ 04h
I_RIGHT         equ 08h
I_LEFT          equ 10h
I_SIZE          equ 20h                 ; Taste G

; ---- Physik (Festkomma 8.8, Pixel pro Bild) ----
ACC             equ 0030h               ; Beschleunigung
TURN            equ 0070h               ; Gegenbremsen beim Richtungswechsel
FRIC            equ 0020h               ; Auslaufen ohne Eingabe
MAXV            equ 0200h               ; hoechstes Tempo 2 Pixel/Bild
XMAX            equ 0F000h              ; rechte Grenze 240 Pixel
ANIMPER         equ 5                   ; Bilder je Laufphase

; ---- Variablen (VARS, bei Start geloescht) ----
V_BANK          equ VARS+0              ; Zeichenpuffer: 0 = Bank 5 (4000h), 80h = Bank 7 (0C000h)
V_ATTR          equ VARS+1              ; Attribut fuer print_str
PX              equ VARS+2              ; x als 8.8, High-Byte = Pixel
PV              equ VARS+4              ; Tempo 8.8 mit Vorzeichen
PDIR            equ VARS+6              ; 0 rechts, 1 links
PFRM            equ VARS+7              ; 0 steht, 1/2 laeuft
PTIM            equ VARS+8
PSIZE           equ VARS+9              ; 0 klein, 1 gross
INP             equ VARS+10
INPOLD          equ VARS+11
OLD0            equ VARS+12             ; Merker Puffer 0: gueltig, x, Groesse
OLD1            equ VARS+15             ; Merker Puffer 1
V_X             equ VARS+18
V_CX            equ VARS+19
V_CY            equ VARS+20
V_ROWS          equ VARS+21
V_FL            equ VARS+22
V_INK           equ VARS+23
V_RX            equ VARS+24
V_RS            equ VARS+25
V_TX0           equ VARS+26
V_TX1           equ VARS+27
V_TY0           equ VARS+28
V_IMG           equ VARS+30             ; Wort
V_FLG           equ VARS+32             ; Wort
V_INKP          equ VARS+34             ; Wort
V_BLK           equ VARS+36             ; Wort
V_FLGOFF        equ VARS+38             ; Wort
VARS_LEN        equ 48

                org 6000h

start:          di
                ld sp,STACKTOP
                ld bc,BANKREG           ; 48K-ROM (Schrift), Bank 7 bei 0C000h, Bank 5 sichtbar
                ld a,17h
                out (c),a
                xor a                   ; Rand schwarz
                out (0FEh),a
                call init_im2
                if ULAPLUS
; ---- ULAplus: Palette blind schreiben (nie zuruecklesen!) ----
                ld hl,palette
                ld e,0                  ; Palettenindex 0..63
                ld d,64
pal_loop:       ld bc,0BF3Bh            ; Registerport
                ld a,e
                out (c),a
                ld b,0FFh               ; Datenport 0FF3Bh
                ld a,(hl)
                out (c),a
                inc hl
                inc e
                dec d
                jr nz,pal_loop
                ld bc,0BF3Bh            ; Register 64 = Modusgruppe
                ld a,40h
                out (c),a
                ld b,0FFh
                ld a,1                  ; Palettenmodus an
                out (c),a
                endif
                ld hl,VARS              ; Variablen loeschen
                ld de,VARS+1
                ld bc,VARS_LEN-1
                ld (hl),0
                ldir
                call clear_both
                ei
                call title_screen
                call clear_both
                call new_game

main_loop:      call read_input
                call update_player
                call restore_old
                call draw_player
main_wait:      halt                    ; auf den naechsten Bildwechsel warten
                call flip
                jr main_loop

; ---------------------------------------------------------
; IM2: Tabelle 257 x 0BFh, Handler bei 0BFBFh = ei / reti
; ---------------------------------------------------------
init_im2:       ld hl,IM2TAB
                ld de,IM2TAB+1
                ld bc,256
                ld (hl),0BFh
                ldir
                ld hl,IM2VEC
                ld (hl),0FBh            ; ei
                inc hl
                ld (hl),0EDh            ; reti
                inc hl
                ld (hl),4Dh
                ld a,high IM2TAB
                ld i,a
                im 2
                ret

; ---------------------------------------------------------
; beide Bildschirme (Bank 5 und Bank 7) loeschen, Attribute 0
; ---------------------------------------------------------
clear_both:     ld hl,4000h
                ld de,4001h
                ld bc,1AFFh
                ld (hl),0
                ldir
                ld hl,0C000h
                ld de,0C001h
                ld bc,1AFFh
                ld (hl),0
                ldir
                ret

; ---------------------------------------------------------
; Titelbild (Bank 5): Text mit der ROM-Schrift (3C00h + Zeichen*8)
; ---------------------------------------------------------
title_screen:   ld hl,5800h
                ld de,5801h
                ld bc,02FFh
                ld (hl),38h             ; Paper 7 (dunkel), Ink 0
                ldir
                xor a
                ld (V_BANK),a
                ld a,3Ah                ; Ink 2 (gold)
                ld (V_ATTR),a
                ld hl,txt_title
                ld b,8
                ld c,9
                call print_str
                ld a,39h                ; Ink 1 (weiss)
                ld (V_ATTR),a
                ld hl,txt_stage
                ld b,11
                ld c,8
                call print_str
                ld hl,txt_start
                ld b,15
                ld c,2
                call print_str
                ld hl,txt_keys
                ld b,17
                ld c,1
                call print_str
ts_wait:        halt
                call read_input
                ld a,(INP)
                and I_FIRE
                jr z,ts_wait
ts_rel:         halt
                call read_input
                ld a,(INP)
                and I_FIRE
                jr nz,ts_rel
                ret

; print_str: HL = Text (0-terminiert), B = Zeile, C = Spalte, Attribut in V_ATTR
print_str:      ld a,(hl)
                or a
                ret z
                push hl
                push bc
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,3C00h
                add hl,de               ; HL = Zeichenmuster
                call cell_addr
                ld b,8
ps_row:         ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz ps_row
                pop bc
                push bc
                call attr_addr
                ld a,(V_ATTR)
                ld (de),a
                pop bc
                inc c
                pop hl
                inc hl
                jr print_str

; ---------------------------------------------------------
; Neues Spiel: Szene in beide Puffer, Spieler auf Startposition
; ---------------------------------------------------------
new_game:       xor a
                ld (V_BANK),a
                call draw_scene
                ld a,80h
                ld (V_BANK),a
                call draw_scene
                ld hl,2000h             ; x = 32
                ld (PX),hl
                ld hl,0
                ld (PV),hl
                xor a
                ld (PDIR),a
                ld (PFRM),a
                ld (PTIM),a
                ld (PSIZE),a
                ld (OLD0),a
                ld (OLD1),a
                ld (INPOLD),a
                ret                     ; V_BANK = 80h: erst in Bank 7 zeichnen, Bank 5 ist sichtbar

draw_scene:     ld hl,level_map
                ld b,0
ds_row:         ld c,0
ds_col:         push hl
                push bc
                ld a,(hl)
                call draw_tile
                pop bc
                pop hl
                inc hl
                inc c
                ld a,c
                cp 16
                jr nz,ds_col
                inc b
                ld a,b
                cp 12
                jr nz,ds_row
                ret

; ---------------------------------------------------------
; Bildwechsel: den eben gezeichneten Puffer anzeigen, dann den anderen zum Zeichnen waehlen
; ---------------------------------------------------------
flip:           ld a,17h
                ld hl,V_BANK
                bit 7,(hl)
                jr z,fl_a
                ld a,1Fh
fl_a:           ld bc,BANKREG
                out (c),a
                ld a,(V_BANK)
                xor 80h
                ld (V_BANK),a
                ret

; ---------------------------------------------------------
; cell_addr: B=cy (0..23), C=cx (0..31)  ->  DE = Pixeladresse im Zeichenpuffer
; ---------------------------------------------------------
cell_addr:      ld a,b
                and 18h
                or 40h
                ld d,a
                ld a,(V_BANK)
                or d
                ld d,a
                ld a,b
                and 7
                rrca
                rrca
                rrca
                add a,c
                ld e,a
                ret

; attr_addr: B=cy, C=cx -> DE = Attributadresse im Zeichenpuffer
attr_addr:      ld a,b
                rrca
                rrca
                rrca
                ld e,a
                and 3
                or 58h
                ld d,a
                ld a,(V_BANK)
                or d
                ld d,a
                ld a,e
                and 0E0h
                add a,c
                ld e,a
                ret

; ---------------------------------------------------------
; draw_tile: A=Kachel-Instanz, B=ty, C=tx (16x16 Pixel). Zerstoert alle Register.
; Kachel-Daten: TL,TR,BL,BR je 8 Byte, danach 4 Attribute
; ---------------------------------------------------------
draw_tile:      ld e,a
                ld d,0
                ld hl,tile_ptr
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl                ; HL = Kachel-Daten
                ld a,c
                add a,a
                ld c,a                  ; cx = 2*tx
                ld a,b
                add a,a
                ld b,a                  ; cy = 2*ty
                push bc
                call cell_addr
                push de
                call blit8              ; links oben
                pop de
                inc e
                push de
                call blit8              ; rechts oben
                pop de
                ld a,e
                add a,31
                ld e,a
                push de
                call blit8              ; links unten
                pop de
                inc e
                call blit8              ; rechts unten
                pop bc
                call attr_addr
                ld a,(hl)
                ld (de),a
                inc hl
                inc e
                ld a,(hl)
                ld (de),a
                inc hl
                ld a,e
                add a,31
                ld e,a
                ld a,(hl)
                ld (de),a
                inc hl
                inc e
                ld a,(hl)
                ld (de),a
                ret

blit8:          ld b,8
bl8_l:          ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz bl8_l
                ret

; ---------------------------------------------------------
; Eingabe: INP = Sinclair-Joystick 1 (Tasten 6-0) oder O/P/Leertaste, plus G
; ---------------------------------------------------------
read_input:     ld bc,0EFFEh
                in a,(c)
                cpl
                and 1Fh
                ld d,a
                ld bc,0DFFEh            ; P O I U Y
                in a,(c)
                ld e,a
                bit 0,e                 ; P = rechts
                jr nz,ri_1
                ld a,d
                or I_RIGHT
                ld d,a
ri_1:           bit 1,e                 ; O = links
                jr nz,ri_2
                ld a,d
                or I_LEFT
                ld d,a
ri_2:           ld bc,7FFEh             ; Leertaste
                in a,(c)
                bit 0,a
                jr nz,ri_3
                ld a,d
                or I_FIRE
                ld d,a
ri_3:           ld bc,0FDFEh            ; A S D F G
                in a,(c)
                bit 4,a
                jr nz,ri_4
                ld a,d
                or I_SIZE
                ld d,a
ri_4:           ld a,d
                ld (INP),a
                ret

; ---------------------------------------------------------
; Spieler: Groesse, Beschleunigung, Bewegung, Animation
; ---------------------------------------------------------
update_player:  ld a,(INPOLD)           ; G: Flanke -> klein/gross
                and I_SIZE
                jr nz,up_sz_done
                ld a,(INP)
                and I_SIZE
                jr z,up_sz_done
                ld a,(PSIZE)
                xor 1
                ld (PSIZE),a
up_sz_done:     ld a,(INP)
                ld (INPOLD),a
                and I_LEFT+I_RIGHT
                jr z,up_none
                cp I_LEFT+I_RIGHT
                jr z,up_none
                cp I_LEFT
                jr z,up_left
; ---- rechts
                xor a
                ld (PDIR),a
                ld hl,(PV)
                ld de,ACC
                bit 7,h
                jr z,up_r1
                ld de,TURN
up_r1:          add hl,de
                bit 7,h
                jr nz,up_rok
                ld a,h
                cp 2
                jr c,up_rok
                ld hl,MAXV
up_rok:         ld (PV),hl
                jr up_move
; ---- links
up_left:        ld a,1
                ld (PDIR),a
                ld hl,(PV)
                ld de,ACC
                bit 7,h
                jr nz,up_l1
                ld de,TURN
up_l1:          or a
                sbc hl,de
                bit 7,h
                jr z,up_lok
                ld a,h
                cp 0FEh
                jr nc,up_lok
                ld hl,0FE00h            ; -MAXV
up_lok:         ld (PV),hl
                jr up_move
; ---- ohne Eingabe: auslaufen
up_none:        ld hl,(PV)
                ld a,h
                or l
                jr z,up_move
                bit 7,h
                jr nz,un_neg
                ld de,FRIC
                or a
                sbc hl,de
                jr nc,un_st
                ld hl,0
                jr un_st
un_neg:         ld de,FRIC
                add hl,de
                bit 7,h
                jr nz,un_st
                ld hl,0
un_st:          ld (PV),hl
; ---- bewegen, an den Raendern anhalten
up_move:        ld a,(PV+1)
                bit 7,a
                jr nz,um_neg
                ld hl,(PV)
                ld de,(PX)
                add hl,de
                ld a,h
                cp 0F0h
                jr c,um_st
                ld hl,XMAX
                ld de,0
                ld (PV),de
                jr um_st
um_neg:         ld hl,(PV)
                ld de,(PX)
                add hl,de
                jr c,um_st
                ld hl,0
                ld de,0
                ld (PV),de
um_st:          ld (PX),hl
; ---- Animation
                ld hl,(PV)
                bit 7,h
                jr z,an_1
                ld de,0
                ex de,hl
                or a
                sbc hl,de               ; HL = |v|
an_1:           ld a,h
                or a
                jr nz,an_run
                ld a,l
                cp 40h
                jr c,an_stand
an_run:         ld a,(PFRM)
                or a
                jr nz,an_cnt
                inc a
                ld (PFRM),a
                xor a
                ld (PTIM),a
                ret
an_cnt:         ld a,(PTIM)
                inc a
                cp ANIMPER
                jr c,an_t
                ld a,(PFRM)
                cp 1
                ld a,1
                jr nz,an_f
                ld a,2
an_f:           ld (PFRM),a
                xor a
an_t:           ld (PTIM),a
                ret
an_stand:       xor a
                ld (PFRM),a
                ld (PTIM),a
                ret

; ---------------------------------------------------------
; Alte Position im Zeichenpuffer aus der Karte wiederherstellen (Kacheln neu zeichnen)
; Merker je Puffer: gueltig, x, Groesse
; ---------------------------------------------------------
restore_old:    ld hl,OLD0
                ld a,(V_BANK)
                or a
                jr z,ro_a
                ld hl,OLD1
ro_a:           ld a,(hl)
                or a
                ret z
                inc hl
                ld a,(hl)
                ld (V_RX),a
                inc hl
                ld a,(hl)
                ld (V_RS),a
                ld a,(V_RX)             ; Kachelspalten von x bis x+15
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld (V_TX0),a
                ld a,(V_RX)
                add a,15
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld (V_TX1),a
                ld a,(V_RS)             ; Kachelzeilen: klein 9, gross 8..9
                ld b,a
                ld a,9
                sub b
                ld b,a
ro_row:         ld a,(V_TX0)
                ld c,a
ro_col:         push bc
                ld a,b                  ; Karten-Index = ty*16 + tx
                add a,a
                add a,a
                add a,a
                add a,a
                or c
                ld e,a
                ld d,0
                ld hl,level_map
                add hl,de
                ld a,(hl)
                call draw_tile
                pop bc
                ld a,(V_TX1)
                cp c
                jr z,ro_cd
                inc c
                jr ro_col
ro_cd:          inc b
                ld a,b
                cp 10
                jr c,ro_row
                ret

; ---------------------------------------------------------
; Spieler zeichnen: Bild (Groesse, Richtung, Phase) in der Verschiebung (x and 6)/2,
; 3 Zellen breit, maskiert; danach Ink der Zellen setzen (nur wo Pixel liegen)
; ---------------------------------------------------------
draw_player:    ld a,(PX+1)
                ld (V_X),a
                ld a,(PSIZE)            ; Bildnummer = Groesse*6 + Richtung*3 + Phase
                ld b,a
                add a,a
                add a,b
                add a,a
                ld b,a
                ld a,(PDIR)
                ld c,a
                add a,a
                add a,c
                add a,b
                ld hl,PFRM
                add a,(hl)
                add a,a
                ld e,a
                ld d,0
                ld hl,img_ptr
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = Bildanfang
                ld a,(PSIZE)
                or a
                jr nz,dp_large
                ld hl,BLK_SMALL
                ld (V_BLK),hl
                ld hl,ink_small
                ld (V_INKP),hl
                ld a,2
                ld (V_ROWS),a
                ld a,18
                ld (V_CY),a
                ld hl,96
                ld (V_FLGOFF),hl
                jr dp_c
dp_large:       ld hl,BLK_LARGE
                ld (V_BLK),hl
                ld hl,ink_large
                ld (V_INKP),hl
                ld a,4
                ld (V_ROWS),a
                ld a,16
                ld (V_CY),a
                ld hl,192
                ld (V_FLGOFF),hl
dp_c:           ld a,(V_X)              ; Verschiebung (x and 6)/2
                and 6
                rrca
                ld b,a
                ld hl,(V_BLK)
                ex de,hl                ; HL = Bildanfang, DE = Blockgroesse
                ld a,b
                or a
                jr z,dp_s0
dp_shl:         add hl,de
                djnz dp_shl
dp_s0:          ld (V_IMG),hl
                ld de,(V_FLGOFF)
                add hl,de
                ld (V_FLG),hl
                ld a,(V_X)
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_CX),a
dp_row:         ld a,(V_CY)
                ld b,a
                ld a,(V_CX)
                ld c,a
                call cell_addr
                ld hl,(V_IMG)
                ld b,8
dp_line:        ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                inc e
                ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                inc e
                ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                dec e
                dec e
                inc d
                djnz dp_line
                ld (V_IMG),hl
                ld hl,(V_FLG)           ; Flags und Ink dieser Zellzeile
                ld a,(hl)
                inc hl
                ld (V_FLG),hl
                ld (V_FL),a
                ld hl,(V_INKP)
                ld a,(hl)
                inc hl
                ld (V_INKP),hl
                ld (V_INK),a
                ld a,(V_CY)
                ld b,a
                ld a,(V_CX)
                ld c,a
                call attr_addr
                ld a,(V_FL)
                ld b,a
                ld a,(V_INK)
                ld c,a
                ld l,3
dp_at:          srl b
                jr nc,dp_an
                ld a,(de)
                and 0F8h                ; Paper und Palettenbits behalten
                or c
                ld (de),a
dp_an:          inc e
                dec l
                jr nz,dp_at
                ld a,(V_CY)
                inc a
                ld (V_CY),a
                ld a,(V_ROWS)
                dec a
                ld (V_ROWS),a
                jp nz,dp_row
                ld hl,OLD0              ; Merker fuer diesen Puffer
                ld a,(V_BANK)
                or a
                jr z,dp_o
                ld hl,OLD1
dp_o:           ld (hl),1
                inc hl
                ld a,(V_X)
                ld (hl),a
                inc hl
                ld a,(PSIZE)
                ld (hl),a
                ret

; ---------------------------------------------------------
; Texte
; ---------------------------------------------------------
txt_title:      db "FEUERWEHRMANN",0
txt_stage:      db "STUFE 1 - LAUFEN",0
txt_start:      db "FEUER ODER LEERTASTE = START",0
txt_keys:       db "O P = LAUFEN  G = KLEIN/GROSS",0

; ---------------------------------------------------------
; Daten (vom Generator erzeugt)
; ---------------------------------------------------------
; ---- ULAplus-Palette: 4 Paletten x (8 Ink + 8 Paper), Byte = GGGRRRBB ----
palette:
                db 025h,0FFh,0DCh,038h,0BDh,046h,07Ch,0A9h,06Bh,08Fh,0D3h,0D7h,0A9h,029h,02Ch,024h
                db 024h,0FFh,064h,0CDh,0DCh,028h,038h,0B6h,089h,070h,069h,054h,04Ch,074h,0D7h,025h
                db 025h,0FFh,0DCh,038h,0BDh,046h,07Ch,0A9h,06Bh,08Fh,0D3h,0D7h,0A9h,029h,02Ch,024h
                db 024h,0FFh,064h,0CDh,0DCh,028h,038h,0B6h,089h,070h,069h,054h,04Ch,074h,0D7h,025h

; ---- Kachel-Zeiger ----
tile_ptr:
                dw tile_sky_0
                dw tile_cloud_l_0
                dw tile_cloud_r_0
                dw tile_sky_1
                dw tile_coin_1
                dw tile_sky_2
                dw tile_brick
                dw tile_chest
                dw tile_sky_3
                dw tile_hill_l_3
                dw tile_hill_m_3
                dw tile_hill_r_3
                dw tile_grass
                dw tile_dirt

; ---- Kacheln: TL,TR,BL,BR je 8 Byte, dann 4 Attribute ----
tile_sky_0:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 1,1,1,1
tile_cloud_l_0:
                db 0,0,0,3,7,00Fh,03Fh,07Fh
                db 0,0,0,0E0h,0F0h,0F8h,0F8h,0FFh
                db 0FFh,0FFh,0FFh,07Fh,03Fh,0,0,0
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 1,1,1,1
tile_cloud_r_0:
                db 0,0,0,7,00Fh,01Fh,01Fh,0FFh
                db 0,0,0,0C0h,0E0h,0F0h,0FCh,0FEh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 0FFh,0FFh,0FFh,0FEh,0FCh,0,0,0
                db 1,1,1,1
tile_sky_1:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 9,9,9,9
tile_coin_1:
                db 0,0,3,7,00Fh,00Eh,00Eh,00Eh
                db 0,0,0C0h,0E0h,0F0h,070h,070h,070h
                db 00Eh,00Eh,00Eh,00Fh,7,3,0,0
                db 070h,070h,070h,0F0h,0E0h,0C0h,0,0
                db 00Ah,00Ah,00Ah,00Ah
tile_sky_2:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 011h,011h,011h,011h
tile_brick:
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 05Fh,05Fh,05Fh,05Fh
tile_chest:
                db 0FFh,080h,080h,080h,080h,0FFh,080h,081h
                db 0FFh,1,1,1,1,0FFh,1,081h
                db 083h,083h,081h,080h,080h,080h,080h,0FFh
                db 0C1h,0C1h,081h,1,1,1,1,0FFh
                db 064h,064h,064h,064h
tile_sky_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,019h,019h
tile_hill_l_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,019h,021h
tile_hill_m_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 021h,021h,021h,021h
tile_hill_r_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,021h,019h
tile_grass:
                db 0,0,020h,0,2,0ADh,089h,0
                db 0,0,084h,0,010h,06Bh,024h,0
                db 044h,2,082h,010h,021h,2,040h,8
                db 022h,8,020h,010h,0,022h,8,040h
                db 042h,042h,04Dh,04Dh
tile_dirt:
                db 0,0,0,2,011h,038h,040h,081h
                db 010h,2,040h,0DAh,0,2,0,0
                db 090h,031h,010h,044h,050h,0,0,080h
                db 019h,8,040h,0,010h,080h,040h,8
                db 04Dh,04Dh,04Dh,04Dh

; ---- Karte 16x12 (Kachel-Instanz-Nummern) ----
level_map:
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,1,2,0,0,0,0,0,0,0,0,0,1,2,0
                db 0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0
                db 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
                db 3,3,3,3,3,3,4,4,4,3,3,3,3,3,3,3
                db 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
                db 5,5,5,5,5,6,7,6,7,6,5,5,5,5,5,5
                db 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
                db 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8
                db 8,8,8,8,8,8,8,8,8,8,9,00Ah,00Bh,8,8,8
                db 00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch,00Ch
                db 00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh,00Dh

BLK_SMALL       equ 98
BLK_LARGE       equ 196

; ---- Ink je Zellzeile ----
ink_small:
                db 2,3
ink_large:
                db 2,4,3,0

; ---- Bild-Zeiger (Groesse, Richtung, Phase) ----
img_ptr:
                dw img_s0_d0_f0
                dw img_s0_d0_f1
                dw img_s0_d0_f2
                dw img_s0_d1_f0
                dw img_s0_d1_f1
                dw img_s0_d1_f2
                dw img_s1_d0_f0
                dw img_s1_d0_f1
                dw img_s1_d0_f2
                dw img_s1_d1_f0
                dw img_s1_d1_f1
                dw img_s1_d1_f2

; ---- Bilder: je 4 Verschiebungen x (Zeilen x 6 Byte + Flags) ----
img_s0_d0_f0:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 7,6
img_s0_d0_f1:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 7,6
img_s0_d0_f2:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F9h,6,08Fh,070h,0FFh,0
                db 0F1h,00Eh,0E3h,01Ch,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FEh,1,063h,09Ch,0FFh,0
                db 0FCh,3,078h,087h,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,098h,067h,0FFh,0
                db 0FFh,0,01Eh,0E1h,03Fh,0C0h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0E6h,019h,03Fh,0C0h
                db 0FFh,0,0C7h,038h,08Fh,070h
                db 7,6
img_s0_d1_f0:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 7,7
img_s0_d1_f1:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 7,7
img_s0_d1_f2:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F1h,00Eh,09Fh,060h,0FFh,0
                db 0C7h,038h,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,067h,098h,0FFh,0
                db 0F1h,00Eh,0E3h,01Ch,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,019h,0E6h,0FFh,0
                db 0FCh,3,078h,087h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C6h,039h,07Fh,080h
                db 0FFh,0,01Eh,0E1h,03Fh,0C0h
                db 7,7
img_s1_d0_f0:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 7,6,7,6
img_s1_d0_f1:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 0C3h,03Ch,0C3h,03Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 0F0h,00Fh,0F0h,00Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 0FCh,3,03Ch,0C3h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 0FFh,0,00Fh,0F0h,00Fh,0F0h
                db 7,6,7,6
img_s1_d0_f2:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,01Fh,0E0h,0FFh,0
                db 0F8h,7,03Fh,0C0h,0FFh,0
                db 0F9h,6,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F3h,00Ch,0CFh,030h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,7,0F8h,0FFh,0
                db 0FEh,1,00Fh,0F0h,0FFh,0
                db 0FEh,1,047h,0B8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,0F3h,00Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,1,0FEh,0FFh,0
                db 0FFh,0,083h,07Ch,0FFh,0
                db 0FFh,0,091h,06Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,03Ch,0C3h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,07Fh,080h
                db 0FFh,0,0E0h,01Fh,0FFh,0
                db 0FFh,0,0E4h,01Bh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0CFh,030h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 7,6,7,6
img_s1_d1_f0:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 7,6,7,6
img_s1_d1_f1:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 0C3h,03Ch,0C3h,03Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 0F0h,00Fh,0F0h,00Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 0FCh,3,03Ch,0C3h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 0FFh,0,00Fh,0F0h,00Fh,0F0h
                db 7,6,7,6
img_s1_d1_f2:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F8h,7,00Fh,0F0h,0FFh,0
                db 0FCh,3,01Fh,0E0h,0FFh,0
                db 0F8h,7,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F3h,00Ch,0CFh,030h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FEh,1,3,0FCh,0FFh,0
                db 0FFh,0,7,0F8h,0FFh,0
                db 0FEh,1,027h,0D8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,0F3h,00Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,080h,07Fh,0FFh,0
                db 0FFh,0,0C1h,03Eh,0FFh,0
                db 0FFh,0,089h,076h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,03Ch,0C3h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0E0h,01Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,07Fh,080h
                db 0FFh,0,0E2h,01Dh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0CFh,030h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 7,6,7,6

code_end:

                end start
