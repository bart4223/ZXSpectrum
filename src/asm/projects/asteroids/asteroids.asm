; =====================================================================
; ASTEROIDS fuer ZX Spectrum 128K  -  Stufe 0: Geruest und Messung
; Z80, pasmo (--tapbas), nur 128K.
;
; Inhalt Stufe 0:
;   - 128K-Start (48K-ROM, Bank 7 bei 0xC000 als Schattenbildschirm)
;   - Doppelpuffer: pro Bild in den verdeckten Puffer zeichnen, nach
;     HALT per Port 0x7FFD umschalten
;   - ULAplus: automatische Erkennung + Palette, Taste C schaltet um
;   - Layout: HUD (2 Zeilen) + Spielfeld 32x22 Zellen = 256x176 Pixel
;   - Testbild: Box mit 1-Pixel-Bewegung, je Puffer eigener "alter Bereich"
;   - Messung: Bilder pro Schleifendurchlauf (BILDER/LOOP), BENCH_N-Boxen
;
; Speicher:  0x6000-0x7FFF reserviert (spaeter Sprites)
;            0x8000-...    Code und Daten
;            0xB400-0xB7FF Variablen (VARS)
;            0xBC00-0xBFFF Stack (waechst nach unten ab 0xC000)
;            0xC000-0xDAFF Bank 7 = Schattenbildschirm
; =====================================================================

BENCH_N     equ 0               ; Testbau: Anzahl Zusatz-Blits pro Bild
VARS        equ 0xB400
STACK_TOP   equ 0xC000
FRAMES      equ 0x5C78          ; Bildzaehler der ROM-Unterbrechung
PORT_BANK   equ 0x7FFD
DISP_A      equ 0x17            ; 48K-ROM, Bank 7 bei 0xC000, Bank 5 sichtbar
BOX_Y       equ 120             ; Zeile 15, Testbox (16x16)
BOX_MAX     equ 239             ; groesstes x (Box 16 breit -> Byte 31 maximal)
BOX_STEP    equ 3               ; Schritt in Pixeln: durchlaeuft alle 8 Pixelphasen

; ---- Variablen -------------------------------------------------------
v_disp      equ VARS+0          ; aktueller Wert von Port 0x7FFD (sichtbar)
v_draw      equ VARS+1          ; Hi-Byte des Zeichenpuffers (0x40 oder 0xC0)
v_buf       equ VARS+2          ; Index des Zeichenpuffers (0 = Bank 5, 1 = Bank 7)
v_plus_av   equ VARS+3          ; ULAplus vorhanden
v_plus_on   equ VARS+4          ; ULAplus eingeschaltet
v_ckey      equ VARS+5          ; Taste C war gedrueckt
v_boxx      equ VARS+6          ; Box x
v_boxdir    equ VARS+7          ; Box Richtung (+2 / -2)
v_oldx      equ VARS+8          ; alter Bereich je Puffer (2 Byte)
v_lastf     equ VARS+10         ; letzter FRAMES-Wert (Low-Byte)
v_dur       equ VARS+11         ; Bilder des letzten Durchlaufs
v_max       equ VARS+12         ; Maximum seit Start (ohne ersten Durchlauf)
v_started   equ VARS+13
v_bn        equ VARS+14         ; Bench-Zaehler
v_bx        equ VARS+15         ; Bench-x
VARS_LEN    equ 16

        org 0x8000

; =====================================================================
start:
        di
        ld sp,STACK_TOP
        im 1
        ld a,DISP_A
        ld bc,PORT_BANK
        out (c),a
        xor a
        out (0xFE),a            ; Rand schwarz

        ld hl,VARS              ; Variablen loeschen
        ld de,VARS+1
        ld bc,VARS_LEN-1
        ld (hl),0
        ldir
        ld a,DISP_A
        ld (v_disp),a
        ld a,BOX_STEP
        ld (v_boxdir),a

        call ula_init           ; ULAplus erkennen, Palette setzen

        ld a,0x40
        call draw_static        ; statische Grafik in beide Puffer
        ld a,0xC0
        call draw_static        ; (laesst v_draw = 0xC0)
        ld a,1
        ld (v_buf),a            ; sichtbar ist Bank 5, gezeichnet wird in Bank 7
        ei

main:
        call keys
        call update_box
        call bench_ops
        call print_dyn
        halt                    ; auf Bildanfang warten
        call flip               ; fertig gezeichneten Puffer anzeigen
        call frame_stats
        jr main

; ---------------------------------------------------------------------
; flip: Anzeige umschalten, naechsten Zeichenpuffer bestimmen
flip:
        ld a,(v_disp)
        xor 0x08
        ld (v_disp),a
        ld bc,PORT_BANK
        out (c),a
        bit 3,a
        ld a,0x40               ; sichtbar Bank 7 -> zeichnen in Bank 5
        ld b,0
        jr nz,fl_1
        ld a,0xC0               ; sichtbar Bank 5 -> zeichnen in Bank 7
        ld b,1
fl_1:   ld (v_draw),a
        ld a,b
        ld (v_buf),a
        ret

; ---------------------------------------------------------------------
; frame_stats: Bilder seit dem letzten Durchlauf zaehlen
frame_stats:
        ld a,(FRAMES)
        ld b,a
        ld a,(v_lastf)
        ld c,a
        ld a,b
        ld (v_lastf),a
        sub c
        ld (v_dur),a
        ld a,(v_started)
        or a
        jr nz,fs_go
        inc a
        ld (v_started),a        ; ersten Durchlauf nicht werten
        ret
fs_go:  ld a,(v_dur)
        ld hl,v_max
        cp (hl)
        ret c
        ld (hl),a
        ret

; ---------------------------------------------------------------------
; keys: Taste C schaltet ULAplus um (nur wenn vorhanden)
keys:
        ld a,0xFE
        in a,(0xFE)             ; Port 0xFEFE: Shift Z X C V
        bit 3,a
        ld a,(v_ckey)
        jr z,ky_down
        xor a
        ld (v_ckey),a
        ret
ky_down:
        or a
        ret nz                  ; wird noch gehalten
        ld a,1
        ld (v_ckey),a
        ld a,(v_plus_av)
        or a
        ret z
        ld a,(v_plus_on)
        xor 1
        ld (v_plus_on),a
        jp ula_set_mode

; ---------------------------------------------------------------------
; ULAplus
ula_init:
        ld bc,0xBF3B
        ld a,0x40               ; Register 64 = Modus
        out (c),a
        ld b,0xFF               ; BC = 0xFF3B (Datenport)
        ld a,1
        out (c),a
        in a,(c)
        cp 1
        jr nz,ui_no
        xor a
        out (c),a
        in a,(c)
        or a
        jr nz,ui_no
        ld a,1
        ld (v_plus_av),a
        ld (v_plus_on),a
        call ula_palette
        ld a,1
        jp ula_set_mode
ui_no:  ld a,0
        ld (v_plus_av),a
        ld (v_plus_on),a
        ret

; A = 1 an / 0 aus
ula_set_mode:
        push af
        ld bc,0xBF3B
        ld a,0x40
        out (c),a
        ld b,0xFF
        pop af
        out (c),a
        ret

; Palette: 4 CLUTs a 16 Eintraege (Tinte 0-7, Papier 8-15)
; Index = (Flash*2+Bright)*16 + (Tinte | Papier+8)
ula_palette:
        ld e,0
ulp_l:  ld a,e
        and 0x10                ; Bright-Bit des Index
        rrca                    ; -> 8
        ld d,a
        ld a,e
        and 7
        or d
        ld l,a
        ld h,0
        ld bc,pal_tab
        add hl,bc
        ld d,(hl)
        ld bc,0xBF3B
        out (c),e
        ld b,0xFF
        out (c),d
        inc e
        ld a,e
        cp 64
        jr nz,ulp_l
        ret

; Farben als GGGRRRBB: schwarz blau rot magenta gruen cyan gelb weiss
pal_tab:
        db 0x00,0x02,0x14,0x16,0xA0,0xA2,0xB4,0xB6      ; normal
        db 0x00,0x03,0x1C,0x1F,0xE0,0xE3,0xFC,0xFF      ; hell

; ---------------------------------------------------------------------
; Zeichenhilfen (zeichnen immer in den Puffer v_draw)

; scr_addr: B = y (0-191), C = x (0-255)  ->  HL = Pixeladresse
scr_addr:
        ld a,b
        and 7
        ld h,a
        ld a,b
        rra
        rra
        rra
        and 0x18
        or h
        ld h,a
        ld a,(v_draw)
        or h
        ld h,a
        ld a,b
        add a,a
        add a,a
        and 0xE0
        ld l,a
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        or l
        ld l,a
        ret

; down_hl: HL eine Pixelzeile nach unten
down_hl:
        inc h
        ld a,h
        and 7
        ret nz
        ld a,l
        add a,32
        ld l,a
        ret c
        ld a,h
        sub 8
        ld h,a
        ret

; attr_addr: D = Zeile (0-23)  ->  HL = Attributadresse Spalte 0
attr_addr:
        ld a,(v_draw)
        add a,0x18
        ld h,a
        ld a,d
        rrca
        rrca
        rrca
        ld l,a
        and 0x1F
        add a,h
        ld h,a
        ld a,l
        and 0xE0
        ld l,a
        ret

; fill_cells: HL = Adresse, B = Anzahl, A = Wert
fill_cells:
        ld (hl),a
        inc hl
        djnz fill_cells
        ret

; print_str: HL = Text (0-terminiert), D = Zeile, E = Spalte
print_str:
        ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        push de
        call put_char
        pop de
        pop hl
        inc e
        jr print_str

; put_char: A = Zeichen (32-95), D = Zeile, E = Spalte
put_char:
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,font
        add hl,bc               ; HL = Glyphe
        ld a,d
        and 0x18
        ld b,a
        ld a,(v_draw)
        or b
        ld b,a                  ; B = Hi(Ziel)
        ld a,d
        and 7
        rrca
        rrca
        rrca
        or e
        ld c,a                  ; C = Lo(Ziel)
        ex de,hl                ; DE = Glyphe
        ld h,b
        ld l,c
        ld b,7                  ; nur 7 Zeilen: Zeile 8 bleibt frei (HUD-Trennlinie)
pc_l:   ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz pc_l
        ret

; ---------------------------------------------------------------------
; draw_static: A = Hi-Byte des Puffers (0x40 / 0xC0)
draw_static:
        ld (v_draw),a
        ld h,a
        ld l,0
        ld d,h
        ld e,1
        ld bc,6143
        ld (hl),l               ; 0
        ldir                    ; Pixel loeschen
        ld a,(v_draw)
        add a,0x18
        ld h,a
        ld l,0
        ld d,h
        ld e,1
        ld bc,767
        ld (hl),0x07
        ldir                    ; Attribute: weiss auf schwarz

        ld d,0                  ; HUD Zeile 0: hell weiss
        call attr_addr
        ld b,32
        ld a,0x47
        call fill_cells
        ld d,1                  ; HUD Zeile 1: hell cyan
        call attr_addr
        ld b,32
        ld a,0x45
        call fill_cells
        ld d,15                 ; Band der Testbox: hell cyan
        call attr_addr
        ld b,64
        ld a,0x45
        call fill_cells

        ld d,21                 ; Palette-Muster in der letzten Zeile
        call attr_addr
        ld b,32
        ld c,0
sw_l:   ld a,c
        srl a
        ld e,a
        and 8
        rlca
        rlca
        rlca
        ld d,a
        ld a,e
        and 7
        rlca
        rlca
        rlca
        or d
        ld (hl),a
        inc hl
        inc c
        djnz sw_l

        ld b,15                 ; Trennlinie unter dem HUD
        ld c,0
        call scr_addr
        ld b,32
sp_l:   ld (hl),0xFF
        inc l
        djnz sp_l

        ld hl,txt_p0
        ld de,0x0000
        call print_str
        ld hl,txt_p1
        ld de,0x0100
        call print_str
        ld hl,txt_t0
        ld de,0x050B
        call print_str
        ld hl,txt_t1
        ld de,0x0708
        call print_str
        ld hl,txt_t2
        ld de,0x090C
        call print_str
        ld hl,txt_t3
        ld de,0x0D07
        call print_str
        ret

; print_dyn: Dynamisches (jedes Bild in den Zeichenpuffer, so landet es in beiden)
print_dyn:
        ld hl,txt_std
        ld a,(v_plus_on)
        or a
        jr z,pd_1
        ld hl,txt_plus
pd_1:   ld de,0x011C            ; Zeile 1, Spalte 28
        call print_str
        ld a,(v_dur)
        cp 10
        jr c,pd_2
        ld a,9
pd_2:   add a,'0'
        ld (txt_dd),a
        ld hl,txt_dur
        ld de,0x0B07            ; Zeile 11, Spalte 7
        jp print_str

txt_p0:  db "PUNKTE 000000  REKORD 000000",0
txt_p1:  db "LEVEL 01     LEBEN 3",0
txt_t0:  db "ASTEROIDS",0
txt_t1:  db "ZX SPECTRUM 128K",0
txt_t2:  db "STUFE 0",0
txt_t3:  db "TASTE C: FARBMODUS",0
txt_plus: db "PLUS",0
txt_std: db "STD ",0
txt_dur: db "BILDER PRO LOOP "
txt_dd:  db "0",0

; ---------------------------------------------------------------------
; Testbox 16x16 mit 1-Pixel-Bewegung, je Puffer eigener alter Bereich
update_box:
        ld hl,v_oldx
        ld a,(v_buf)
        add a,l
        ld l,a                  ; HL -> alter Bereich dieses Puffers
        ld c,(hl)
        push hl
        ld b,BOX_Y
        xor a
        call box_op             ; alte Box loeschen
        ld a,(v_boxx)
        ld hl,v_boxdir
        add a,(hl)
        cp BOX_MAX+1
        jr c,ub_in              ; im erlaubten Bereich
        bit 7,(hl)              ; ueber den Rand: links (unter 0 gelaufen) oder rechts?
        jr z,ub_right
        xor a                   ; links: x = 0, nach rechts
        ld (hl),BOX_STEP
        jr ub_in
ub_right:
        ld a,BOX_MAX            ; rechts: x = Maximum, nach links
        ld (hl),256-BOX_STEP
ub_in:  ld (v_boxx),a
        ld c,a
        ld b,BOX_Y
        ld a,1
        call box_op             ; neue Box zeichnen
        pop hl
        ld a,(v_boxx)
        ld (hl),a
        ret

; box_op: B = y, C = x, A = 1 zeichnen / 0 loeschen (16x16, 3 Byte breit)
box_op:
        ld d,a
        call scr_addr           ; HL
        ld a,c
        and 7
        ld c,a
        ld b,0
        push hl
        ld hl,rmask
        add hl,bc
        ld e,(hl)               ; E = linke Maske
        ld hl,lmask
        add hl,bc
        ld c,(hl)               ; C = rechte Maske
        pop hl
        ld b,16
bo_l:   ld a,d
        or a
        jr z,bo_e
        ld (hl),e
        inc l
        ld (hl),0xFF
        inc l
        ld (hl),c
        jr bo_n
bo_e:   xor a
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
bo_n:   dec l
        dec l
        call down_hl
        djnz bo_l
        ret

rmask:  db 0xFF,0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01
lmask:  db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE

; bench_ops: BENCH_N mal Box zeichnen und wieder loeschen (nur Messung)
bench_ops:
        ld a,BENCH_N
        or a
        ret z
        ld (v_bn),a
bn_l:   ld a,(v_bn)
        ld e,a
        add a,a
        add a,e
        add a,a
        add a,a
        add a,a                 ; *24
        ld (v_bx),a
        ld c,a
        ld b,24
        ld a,1
        call box_op
        ld a,(v_bx)
        ld c,a
        ld b,24
        xor a
        call box_op
        ld hl,v_bn
        dec (hl)
        jr nz,bn_l
        ret

; --- Font 5x7 (ASCII 32..95, Grossbuchstaben), erzeugt von tools/build.py ---
font:
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; ' '
        db 0x10,0x10,0x10,0x10,0x10,0x00,0x10,0x00     ; '!'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '"'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '#'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '$'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '%'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '&'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '''
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '('
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; ')'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '*'
        db 0x00,0x10,0x10,0x7C,0x10,0x10,0x00,0x00     ; '+'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; ','
        db 0x00,0x00,0x00,0x7C,0x00,0x00,0x00,0x00     ; '-'
        db 0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x00     ; '.'
        db 0x04,0x04,0x08,0x10,0x20,0x40,0x40,0x00     ; '/'
        db 0x38,0x44,0x4C,0x54,0x64,0x44,0x38,0x00     ; '0'
        db 0x10,0x30,0x10,0x10,0x10,0x10,0x38,0x00     ; '1'
        db 0x38,0x44,0x04,0x08,0x10,0x20,0x7C,0x00     ; '2'
        db 0x38,0x44,0x04,0x18,0x04,0x44,0x38,0x00     ; '3'
        db 0x08,0x18,0x28,0x48,0x7C,0x08,0x08,0x00     ; '4'
        db 0x7C,0x40,0x78,0x04,0x04,0x44,0x38,0x00     ; '5'
        db 0x18,0x20,0x40,0x78,0x44,0x44,0x38,0x00     ; '6'
        db 0x7C,0x04,0x08,0x10,0x20,0x20,0x20,0x00     ; '7'
        db 0x38,0x44,0x44,0x38,0x44,0x44,0x38,0x00     ; '8'
        db 0x38,0x44,0x44,0x3C,0x04,0x08,0x30,0x00     ; '9'
        db 0x00,0x10,0x10,0x00,0x10,0x10,0x00,0x00     ; ':'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; ';'
        db 0x08,0x10,0x20,0x40,0x20,0x10,0x08,0x00     ; '<'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '='
        db 0x20,0x10,0x08,0x04,0x08,0x10,0x20,0x00     ; '>'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '?'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '@'
        db 0x38,0x44,0x44,0x7C,0x44,0x44,0x44,0x00     ; 'A'
        db 0x78,0x44,0x44,0x78,0x44,0x44,0x78,0x00     ; 'B'
        db 0x38,0x44,0x40,0x40,0x40,0x44,0x38,0x00     ; 'C'
        db 0x78,0x44,0x44,0x44,0x44,0x44,0x78,0x00     ; 'D'
        db 0x7C,0x40,0x40,0x78,0x40,0x40,0x7C,0x00     ; 'E'
        db 0x7C,0x40,0x40,0x78,0x40,0x40,0x40,0x00     ; 'F'
        db 0x38,0x44,0x40,0x5C,0x44,0x44,0x38,0x00     ; 'G'
        db 0x44,0x44,0x44,0x7C,0x44,0x44,0x44,0x00     ; 'H'
        db 0x38,0x10,0x10,0x10,0x10,0x10,0x38,0x00     ; 'I'
        db 0x1C,0x08,0x08,0x08,0x08,0x48,0x30,0x00     ; 'J'
        db 0x44,0x48,0x50,0x60,0x50,0x48,0x44,0x00     ; 'K'
        db 0x40,0x40,0x40,0x40,0x40,0x40,0x7C,0x00     ; 'L'
        db 0x44,0x6C,0x54,0x54,0x44,0x44,0x44,0x00     ; 'M'
        db 0x44,0x64,0x54,0x4C,0x44,0x44,0x44,0x00     ; 'N'
        db 0x38,0x44,0x44,0x44,0x44,0x44,0x38,0x00     ; 'O'
        db 0x78,0x44,0x44,0x78,0x40,0x40,0x40,0x00     ; 'P'
        db 0x38,0x44,0x44,0x44,0x54,0x48,0x34,0x00     ; 'Q'
        db 0x78,0x44,0x44,0x78,0x50,0x48,0x44,0x00     ; 'R'
        db 0x3C,0x40,0x40,0x38,0x04,0x04,0x78,0x00     ; 'S'
        db 0x7C,0x10,0x10,0x10,0x10,0x10,0x10,0x00     ; 'T'
        db 0x44,0x44,0x44,0x44,0x44,0x44,0x38,0x00     ; 'U'
        db 0x44,0x44,0x44,0x44,0x44,0x28,0x10,0x00     ; 'V'
        db 0x44,0x44,0x44,0x54,0x54,0x6C,0x44,0x00     ; 'W'
        db 0x44,0x44,0x28,0x10,0x28,0x44,0x44,0x00     ; 'X'
        db 0x44,0x44,0x28,0x10,0x10,0x10,0x10,0x00     ; 'Y'
        db 0x7C,0x04,0x08,0x10,0x20,0x40,0x7C,0x00     ; 'Z'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '['
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '\'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; ']'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '^'
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00     ; '_'


        end start
