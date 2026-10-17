; ==========================================================================
;  TETRIS fuer den ZX Spectrum - Schritt 1+2
;  Spielfeld (eigene Datenstruktur), Blockgrafik, eine Figur mit
;  Rotationstabelle per Tastatur/Joystick bewegen.
;
;  Assemblieren:  pasmo --tapbas tetris.asm tetris.tap
;
;  Steuerung:  O / P  links / rechts      Q  drehen
;              A      runter              N  naechste Figur (Testtaste)
;              Sinclair-Joystick (IF2) Port 1 (6-0) und Port 2 (1-5):
;              links/rechts/runter, hoch oder Feuer = drehen
; ==========================================================================

        org $8000

; --- Konstanten -----------------------------------------------------------
BOARD_W     equ 12          ; 10 Spalten + 2 Waende
BOARD_H     equ 21          ; 20 Zeilen + Boden
BOARD_HI    equ $90         ; Spielfeld liegt page-aligned bei $9000
BOARD       equ BOARD_HI*256
WALL        equ 8           ; Zellwert fuer Wand/Boden (0 = leer, 1..7 = Figur)

SCR_ROW0    equ 2           ; Bildschirmzeile von Brettzeile 0
SCR_COL0    equ 10          ; Bildschirmspalte von Brettspalte 0

SPAWN_COL   equ 4           ; Ankerspalte beim Erscheinen
DAS_DELAY   equ 10          ; Frames bis Auto-Repeat links/rechts
DAS_RATE    equ 3           ; Frames zwischen Wiederholungen
DROP_RATE   equ 3           ; Frames zwischen Schritten beim Runterdruecken

ATTR_TEXT   equ $47         ; BRIGHT, PAPER 0, INK 7
ATTR_TITLE  equ $46         ; BRIGHT, PAPER 0, INK 6

; Eingabebits (aktiv high) in keys / pressed
K_LEFT      equ 0
K_RIGHT     equ 1
K_DOWN      equ 2
K_ROT       equ 3
K_NEXT      equ 4
M_LR        equ %00000011   ; Maske links|rechts

; ==========================================================================
start:
        xor a
        out ($fe),a             ; Rand schwarz
        call cls
        call init_board
        call draw_patterns
        call render_board
        call draw_texts
        ld hl,$5800+2*32+23     ; Titel gelb
        ld b,6
st_ttl: ld (hl),ATTR_TITLE
        inc hl
        djnz st_ttl

        xor a
        ld (piece_type),a
        ld (keys),a
        ld (das_cnt),a
        ld (drop_cnt),a
        call spawn
        call draw_piece

main_loop:
        halt                    ; 50 Hz (IM 1, ROM-Interrupt)
        call read_input
        call handle_input
        jr main_loop

; ==========================================================================
;  Spielfeld
; ==========================================================================

; Brett fuellen: Waende links/rechts, Boden unten, sonst leer
init_board:
        ld hl,BOARD
        ld b,BOARD_H
ib_row: ld (hl),WALL
        inc hl
        ld c,BOARD_W-2
ib_col: ld (hl),0
        inc hl
        dec c
        jr nz,ib_col
        ld (hl),WALL
        inc hl
        djnz ib_row
        ld hl,BOARD+(BOARD_H-1)*BOARD_W
        ld b,BOARD_W
ib_flr: ld (hl),WALL
        inc hl
        djnz ib_flr
        ret

; B = Brettzeile, C = Brettspalte  ->  HL = Adresse im Brett
; (Zeile*12 passt in ein Byte, da max. 20*12+11 = 251)
board_addr:
        ld a,b
        add a,a                 ; 2r
        add a,b                 ; 3r
        add a,a                 ; 6r
        add a,a                 ; 12r
        add a,c
        ld l,a
        ld h,BOARD_HI
        ret

; ==========================================================================
;  Bildschirm
; ==========================================================================

cls:
        ld hl,$4000
        ld de,$4001
        ld bc,6143
        ld (hl),0
        ldir
        ld hl,$5800
        ld de,$5801
        ld bc,767
        ld (hl),ATTR_TEXT
        ldir
        ret

; B = Zeichenzeile (0-23), C = Spalte (0-31)  ->  HL = Pixeladresse
cell_pix:
        ld a,b
        and $18
        or $40
        ld h,a
        ld a,b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l,a
        ret

; B = Zeichenzeile, C = Spalte  ->  HL = Attributadresse
cell_attr:
        ld a,b
        rrca
        rrca
        rrca                    ; Bits 0-2 -> 5-7, Bits 3-4 -> 0-1
        ld l,a
        and 3
        or $58
        ld h,a
        ld a,l
        and $e0
        or c
        ld l,a
        ret

; Zellwert in A -> Attribut in A
color_of:
        push hl
        ld hl,cell_colors
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        pop hl
        ret

; Pixelmuster einmalig ins Spielfeld schreiben.
; Wandzellen bekommen ein Ziegelmuster, alle anderen das Blockmuster.
; Danach wird nur noch ueber Attribute gezeichnet.
draw_patterns:
        ld hl,BOARD
        ld b,SCR_ROW0
dp_row: ld c,SCR_COL0
dp_col: push hl
        push bc
        ld a,(hl)
        ld de,pat_block
        cp WALL
        jr nz,dp_pat
        ld de,pat_wall
dp_pat: call cell_pix
        ld b,8
dp_ln:  ld a,(de)
        ld (hl),a
        inc de
        inc h                   ; naechste Pixelzeile in der Zelle
        djnz dp_ln
        pop bc
        pop hl
        inc hl
        inc c
        ld a,c
        cp SCR_COL0+BOARD_W
        jr nz,dp_col
        inc b
        ld a,b
        cp SCR_ROW0+BOARD_H
        jr nz,dp_row
        ret

; Komplettes Brett als Attribute darstellen
render_board:
        ld hl,BOARD
        ld b,SCR_ROW0
rb_row: push bc
        push hl
        ld c,SCR_COL0
        call cell_attr
        ex de,hl                ; DE = Attributadresse Zeilenanfang
        pop hl
        ld b,BOARD_W
rb_col: ld a,(hl)
        call color_of
        ld (de),a
        inc hl
        inc de
        djnz rb_col
        pop bc
        inc b
        ld a,b
        cp SCR_ROW0+BOARD_H
        jr nz,rb_row
        ret

; ==========================================================================
;  Text (ROM-Zeichensatz)
; ==========================================================================

; B = Zeile, C = Spalte, HL = 0-terminierter String
print_at:
        ld a,(hl)
        or a
        ret z
        push hl
        push bc
        call print_char
        pop bc
        pop hl
        inc hl
        inc c
        jr print_at

; A = Zeichen, B/C = Position
print_char:
        push af
        call cell_pix
        ex de,hl                ; DE = Bildschirm
        pop af
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,$3c00             ; ROM-Font $3D00 minus 32*8
        add hl,bc
        ld b,8
pc_ln:  ld a,(hl)
        ld (de),a
        inc hl
        inc d
        djnz pc_ln
        ret

draw_texts:
        ld hl,texts
dt_lp:  ld a,(hl)
        cp $ff
        ret z
        ld b,a                  ; Zeile
        inc hl
        ld c,(hl)               ; Spalte
        inc hl
        call print_at           ; HL steht danach auf der 0
        inc hl
        jr dt_lp

; ==========================================================================
;  Aktive Figur
; ==========================================================================

spawn:
        xor a
        ld (piece_rot),a
        ld (piece_row),a
        ld a,SPAWN_COL
        ld (piece_col),a
        ret

; A = Rotation (0-3)  ->  DE = Zeiger auf 4 Zellen der aktuellen Figur
; Zelle = $yx (High-Nibble dy, Low-Nibble dx)
cells_ptr:
        ld e,a
        ld a,(piece_type)
        add a,a
        add a,a
        add a,e                 ; Typ*4 + Rot
        add a,a
        add a,a                 ; *4 Bytes
        ld e,a
        ld d,0
        ld hl,pieces
        add hl,de
        ex de,hl
        ret

; Passt die Figur?  B = Zeile, C = Spalte, DE = Zellen
; Ergebnis: Z = frei, NZ = Kollision.  Veraendert A, DE, HL.
; Negative Spalten werden als >= 244 unsigned erkannt bzw. treffen die Wand.
fits:
        ld a,4
ft_lp:  push af
        push bc
        ld a,(de)
        and $0f
        add a,c
        cp BOARD_W
        jr nc,ft_hit
        ld c,a
        ld a,(de)
        rrca
        rrca
        rrca
        rrca
        and $0f
        add a,b
        cp BOARD_H
        jr nc,ft_hit
        ld b,a
        call board_addr
        ld a,(hl)
        or a
        jr nz,ft_hit
        pop bc
        pop af
        inc de
        dec a
        jr nz,ft_lp
        ret                     ; Z
ft_hit: pop bc
        pop af                  ; A = Restzaehler, nie 0
        or a                    ; -> NZ
        ret

; Figur loeschen (Zellen aus dem Brett wiederherstellen) bzw. zeichnen
erase_piece:
        xor a
        jr paint
draw_piece:
        ld a,(piece_type)
        inc a
        call color_of
paint:  ld (paint_attr),a
        ld a,(piece_rot)
        call cells_ptr
        ld a,(piece_row)
        ld b,a
        ld a,(piece_col)
        ld c,a
        ld a,4
pt_lp:  push af
        push bc
        push de
        ld a,(de)
        and $0f
        add a,c
        ld c,a                  ; Brettspalte
        ld a,(de)
        rrca
        rrca
        rrca
        rrca
        and $0f
        add a,b
        ld b,a                  ; Brettzeile
        ld a,(paint_attr)
        or a
        jr nz,pt_set
        call board_addr         ; loeschen: Farbe aus dem Brett
        ld a,(hl)
        call color_of
pt_set: ld e,a
        ld a,b
        add a,SCR_ROW0
        ld b,a
        ld a,c
        add a,SCR_COL0
        ld c,a
        call cell_attr
        ld (hl),e
        pop de
        inc de
        pop bc
        pop af
        dec a
        jr nz,pt_lp
        ret

; Bewegung versuchen: B = neue Zeile, C = neue Spalte, A = neue Rotation
; Z = ausgefuehrt, NZ = blockiert
try_move:
        ld (new_rot),a
        ld (new_pos),bc         ; (new_pos) = Spalte, (new_pos+1) = Zeile
        call cells_ptr
        call fits
        ret nz
        call erase_piece
        ld a,(new_rot)
        ld (piece_rot),a
        ld bc,(new_pos)
        ld a,b
        ld (piece_row),a
        ld a,c
        ld (piece_col),a
        call draw_piece
        xor a
        ret

; ==========================================================================
;  Eingabe
; ==========================================================================

; Liest Tastatur + beide IF2-Joysticks.
; keys    = aktuell gehaltene Richtungen/Aktionen
; pressed = in diesem Frame neu gedrueckt
read_input:
        ld c,0
        ld a,$df                ; P O I U Y
        in a,($fe)
        bit 1,a
        jr nz,ri_1
        set K_LEFT,c            ; O
ri_1:   bit 0,a
        jr nz,ri_2
        set K_RIGHT,c           ; P
ri_2:   ld a,$fd                ; A S D F G
        in a,($fe)
        bit 0,a
        jr nz,ri_3
        set K_DOWN,c            ; A
ri_3:   ld a,$fb                ; Q W E R T
        in a,($fe)
        bit 0,a
        jr nz,ri_4
        set K_ROT,c             ; Q
ri_4:   ld a,$7f                ; SPACE SYM M N B
        in a,($fe)
        bit 3,a
        jr nz,ri_5
        set K_NEXT,c            ; N
ri_5:
        ; Sinclair-Joystick 1: 6=links 7=rechts 8=runter 9=hoch 0=Feuer
        ld a,$ef                ; 0 9 8 7 6
        in a,($fe)
        cpl
        ld b,a
        bit 4,b
        jr z,ri_6
        set K_LEFT,c
ri_6:   bit 3,b
        jr z,ri_7
        set K_RIGHT,c
ri_7:   bit 2,b
        jr z,ri_8
        set K_DOWN,c
ri_8:   ld a,b
        and %00000011           ; hoch oder Feuer
        jr z,ri_9
        set K_ROT,c
ri_9:
        ; Sinclair-Joystick 2: 1=links 2=rechts 3=runter 4=hoch 5=Feuer
        ld a,$f7                ; 1 2 3 4 5
        in a,($fe)
        cpl
        ld b,a
        bit 0,b
        jr z,ri_10
        set K_LEFT,c
ri_10:  bit 1,b
        jr z,ri_11
        set K_RIGHT,c
ri_11:  bit 2,b
        jr z,ri_12
        set K_DOWN,c
ri_12:  ld a,b
        and %00011000           ; hoch oder Feuer
        jr z,ri_13
        set K_ROT,c
ri_13:
        ld a,(keys)
        cpl
        and c
        ld (pressed),a
        ld a,c
        ld (keys),a
        ret

handle_input:
        ld a,(pressed)
        bit K_ROT,a
        call nz,do_rotate
        ld a,(pressed)
        bit K_NEXT,a
        call nz,do_next

        ; --- links/rechts mit Auto-Repeat (DAS) ---
        ld a,(keys)
        and M_LR
        jr nz,hi_lr
        xor a
        ld (das_cnt),a
        jr hi_down
hi_lr:  ld a,(das_cnt)
        or a
        jr z,hi_first
        dec a
        ld (das_cnt),a
        jr nz,hi_down
        ld a,DAS_RATE
        ld (das_cnt),a
        jr hi_step
hi_first:
        ld a,DAS_DELAY
        ld (das_cnt),a
hi_step:
        ld e,$ff                ; -1
        ld a,(keys)
        bit K_LEFT,a
        jr nz,hi_dir
        ld e,1
hi_dir: ld a,(piece_col)
        add a,e
        ld c,a
        ld a,(piece_row)
        ld b,a
        ld a,(piece_rot)
        call try_move

        ; --- runter mit Wiederholung ---
hi_down:
        ld a,(keys)
        bit K_DOWN,a
        jr nz,hd_held
        xor a
        ld (drop_cnt),a
        ret
hd_held:
        ld a,(drop_cnt)
        or a
        jr z,hd_go
        dec a
        ld (drop_cnt),a
        ret
hd_go:  ld a,DROP_RATE-1
        ld (drop_cnt),a
        ld a,(piece_row)
        inc a
        ld b,a
        ld a,(piece_col)
        ld c,a
        ld a,(piece_rot)
        jp try_move

do_rotate:
        ld a,(piece_row)
        ld b,a
        ld a,(piece_col)
        ld c,a
        ld a,(piece_rot)
        inc a
        and 3
        jp try_move

; Testfunktion: naechste Figur oben neu einsetzen
do_next:
        call erase_piece
        ld a,(piece_type)
        inc a
        cp 7
        jr c,dn_set
        xor a
dn_set: ld (piece_type),a
        call spawn
        jp draw_piece

; ==========================================================================
;  Daten
; ==========================================================================

; Attribut je Zellwert: 0 leer, 1 I, 2 O, 3 T, 4 S, 5 Z, 6 J, 7 L, 8 Wand
; Figuren: BRIGHT + PAPER Farbe + INK 0 (schwarze Fuge aus dem Muster)
cell_colors:
        db $01                  ; leer: PAPER 0, INK 1 -> dunkelblaues Raster
        db $68                  ; I cyan
        db $70                  ; O gelb
        db $58                  ; T magenta
        db $60                  ; S gruen
        db $50                  ; Z rot
        db $48                  ; J blau
        db $78                  ; L weiss
        db $17                  ; Wand: PAPER 2, INK 7 -> rote Ziegel

pat_block:                      ; gesetzte Bits = INK (Fuge rechts/unten)
        db %00000001
        db %00000001
        db %00000001
        db %00000001
        db %00000001
        db %00000001
        db %00000001
        db %11111111

pat_wall:                       ; Ziegel mit Fugen
        db %11111111
        db %10000000
        db %10000000
        db %10000000
        db %11111111
        db %00001000
        db %00001000
        db %00001000

; Rotationstabelle: 7 Figuren x 4 Rotationen x 4 Zellen ($yx im 4x4-Feld)
; Reihenfolge I O T S Z J L, SRS-Grundstellungen, im Uhrzeigersinn
pieces:
        db $10,$11,$12,$13      ; I
        db $02,$12,$22,$32
        db $20,$21,$22,$23
        db $01,$11,$21,$31
        db $01,$02,$11,$12      ; O
        db $01,$02,$11,$12
        db $01,$02,$11,$12
        db $01,$02,$11,$12
        db $01,$10,$11,$12      ; T
        db $01,$11,$12,$21
        db $10,$11,$12,$21
        db $01,$10,$11,$21
        db $01,$02,$10,$11      ; S
        db $01,$11,$12,$22
        db $11,$12,$20,$21
        db $00,$10,$11,$21
        db $00,$01,$11,$12      ; Z
        db $02,$11,$12,$21
        db $10,$11,$21,$22
        db $01,$10,$11,$20
        db $00,$10,$11,$12      ; J
        db $01,$02,$11,$21
        db $10,$11,$12,$22
        db $01,$11,$20,$21
        db $02,$10,$11,$12      ; L
        db $01,$11,$21,$22
        db $10,$11,$12,$20
        db $00,$01,$11,$21

; Texte: Zeile, Spalte, String, 0 ... $ff = Ende
texts:
        db 2,23,"TETRIS",0
        db 6,23,"O P  <  >",0
        db 8,23,"Q  DREHEN",0
        db 10,23,"A  RUNTER",0
        db 12,23,"N  NEXT",0
        db 15,23,"JOYSTICK",0
        db 16,23,"IF2 1+2",0
        db $ff

; --- Variablen ------------------------------------------------------------
piece_type: db 0
piece_rot:  db 0
piece_row:  db 0
piece_col:  db 0
new_rot:    db 0
new_pos:    dw 0                ; Low = Spalte (C), High = Zeile (B)
paint_attr: db 0
keys:       db 0
pressed:    db 0
das_cnt:    db 0
drop_cnt:   db 0

        end start
