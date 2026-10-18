; ==========================================================================
;  TETRIS fuer den ZX Spectrum - Schritt 1-6
;  Spielfeld (eigene Datenstruktur), Blockgrafik, Figuren mit
;  Rotationstabelle, Kollision, Schwerkraft, Ablegen, Zeilen loeschen,
;  Zufallsfiguren (Xorshift + 7-Bag), Punkte, Level, Vorschau, Bestwert,
;  Beeper-Sound, Wall Kicks, Ghost-Figur, Hard Drop,
;  Splash-Screen mit Einstellungen (Lautstaerke, Ghost an/aus).
;
;  Assemblieren:  pasmo --tapbas tetris.asm tetris.tap
;
;  Steuerung:  O / P  links / rechts      Q  drehen
;              A      runter              SPACE  fallen lassen (Hard Drop)
;              Sinclair-Joystick (IF2) Port 1 (6-0) und Port 2 (1-5):
;              links/rechts/runter, Feuer = drehen, hoch = fallen lassen
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
PREV_ROW    equ 6           ; Vorschau: 4x2 Zellen ab Zeile 6, Spalte 25
PREV_COL    equ 25
LINES_PER_LEVEL equ 10
MAX_LEVEL_SPEED equ 29      ; ab hier bleibt die Geschwindigkeit gleich

ATTR_TEXT   equ $47         ; BRIGHT, PAPER 0, INK 7
ATTR_TITLE  equ $46         ; BRIGHT, PAPER 0, INK 6
ATTR_EMPTY  equ $01         ; leere Zelle: PAPER 0, INK 1
ATTR_FLASH  equ $78         ; volle Zeile beim Blinken: BRIGHT, PAPER 7
ATTR_OVER   equ $42         ; GAME OVER: BRIGHT, PAPER 0, INK 2 (rot)

; Eingabebits (aktiv high) in keys / pressed
K_LEFT      equ 0
K_RIGHT     equ 1
K_DOWN      equ 2
K_ROT       equ 3
K_HARD      equ 4
M_LR        equ %00000011   ; Maske links|rechts
M_FIRE      equ %00001000   ; Maske Feuer = K_ROT (startet im Splash)

; ==========================================================================
start:
        ld (sp_save),sp         ; Stack fuer spaetere Neustarts merken
        ld hl,0
        ld (best),hl
        ld (best+1),hl
        ld a,2                  ; Standard: Lautstaerke MITTEL, Ghost AUS, Hoch AUS
        ld (opt_vol),a
        xor a
        ld (opt_ghost),a
        ld (opt_up),a
        ld a,$ff
        ld (keys),a             ; gehaltene Taste zaehlt nicht als Druck
        call cls
        ld hl,msg_load
        call draw_list
        call load_best          ; gesicherten Rekord laden (falls vorhanden)

new_game:                       ; auch nach Game Over: wieder zum Splash
        ld sp,(sp_save)
        xor a
        out ($fe),a             ; Rand schwarz
        call cls
        call splash             ; Einstellungen, liefert auch den Zufallsstartwert
        call cls
        call init_board
        call draw_patterns
        call render_board
        call draw_texts
        ld hl,$5800+2*32+24     ; Titel gelb
        ld b,6
st_ttl: ld (hl),ATTR_TITLE
        inc hl
        djnz st_ttl
        call draw_prev_pattern
        call clear_next         ; Vorschau leer, bis die erste Figur gezogen ist

        xor a
        ld (das_cnt),a
        ld (drop_cnt),a
        call reset_game

        ld a,7                  ; Beutel leer -> wird beim ersten Ziehen gefuellt
        ld (bag_pos),a
        call bag_next
        ld (next_type),a
        call new_piece

main_loop:
        halt                    ; 50 Hz (IM 1, ROM-Interrupt)
        call read_input
        call handle_input
        call gravity
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
; HL = Liste aus Zeile, Spalte, String, 0 ... $ff
draw_list:
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

; Figur und Ghost loeschen (Zellen aus dem Brett wiederherstellen)
erase_piece:
        ld a,(opt_ghost)
        or a
        jr z,ep_piece           ; Ghost aus -> nichts zu loeschen
        ld a,(ghost_row)
        ld (paint_row),a
        xor a
        call paint
ep_piece:
        ld a,(piece_row)
        ld (paint_row),a
        xor a
        jr paint

; Ghost (Landeposition) und Figur zeichnen
draw_piece:
        ld a,(opt_ghost)
        or a
        jr z,draw_only          ; Ghost aus
        call calc_ghost
        ld a,(ghost_row)
        ld (paint_row),a
        ld a,(piece_type)
        inc a
        call color_of           ; PAPER-Farbe der Figur ...
        rrca
        rrca
        rrca
        and 7                   ; ... als INK: nur die Fugenlinien leuchten
        or $40                  ; BRIGHT, hebt sich vom dunkelblauen Raster ab
        call paint
draw_only:                      ; nur die Figur (ohne Ghost)
        ld a,(piece_row)
        ld (paint_row),a
        ld a,(piece_type)
        inc a
        call color_of

; A = Attribut (0 = loeschen), Zeile aus paint_row, Spalte/Rotation der Figur
paint:  ld (paint_attr),a
        ld a,(piece_rot)
        call cells_ptr
        ld a,(paint_row)
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

; Ghost-Zeile: so weit nach unten, wie die Figur passt
calc_ghost:
        ld a,(piece_row)
        ld b,a
        ld a,(piece_col)
        ld c,a
cg_lp:  inc b
        ld a,(piece_rot)
        call cells_ptr          ; aendert BC nicht
        call fits               ; erhaelt BC
        jr z,cg_lp
        dec b
        ld a,b
        ld (ghost_row),a
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
        bit 0,a
        jr nz,ri_5
        set K_HARD,c            ; SPACE
ri_5:   ld a,(menu_mode)        ; im Splash zaehlt die Tastatur nicht:
        or a                    ; Einstellungen und Start nur per Joystick
        jr z,ri_nk
        ld c,0
ri_nk:
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
ri_8:   bit 0,b
        jr z,ri_8b
        set K_ROT,c             ; Feuer (Taste 0)
ri_8b:  bit 1,b
        jr z,ri_9
        ld a,(opt_up)           ; Option "HOCH" aus -> Stick hoch ohne Wirkung
        or a
        jr z,ri_9
        set K_HARD,c            ; hoch (Taste 9)
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
ri_12:  bit 4,b
        jr z,ri_12b
        set K_ROT,c             ; Feuer (Taste 5)
ri_12b: bit 3,b
        jr z,ri_13
        ld a,(opt_up)
        or a
        jr z,ri_13
        set K_HARD,c            ; hoch (Taste 4)
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
        bit K_HARD,a
        jp nz,hard_drop
        ld a,(pressed)
        bit K_ROT,a
        call nz,do_rotate

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
        ld (down_lock),a        ; losgelassen -> Sperre aufheben
        ret
hd_held:
        ld a,(down_lock)        ; nach neuer Figur erst loslassen
        or a
        ret nz
        ld a,(drop_cnt)
        or a
        jr z,hd_go
        dec a
        ld (drop_cnt),a
        ret
hd_go:  ld a,DROP_RATE-1
        ld (drop_cnt),a
        ld a,(fall_delay)       ; Schwerkraft-Takt neu starten
        ld (fall_cnt),a
        call try_down
        jp nz,lock_and_next
        ld de,pts_soft          ; 1 Punkt pro Zeile Runterdruecken
        call add_score
        jp draw_stats

; Drehen mit Wall Kicks: Spalte +0, -1, +1 (beim I zusaetzlich -2, +2)
do_rotate:
        ld a,(piece_rot)
        inc a
        and 3
        ld (rot_try),a
        ld hl,kick_tab
        ld b,3
        ld a,(piece_type)
        or a
        jr nz,dr_lp
        ld b,5                  ; I-Stueck
dr_lp:  push hl
        push bc
        ld a,(piece_col)
        add a,(hl)
        ld c,a
        ld a,(piece_row)
        ld b,a
        ld a,(rot_try)
        call try_move
        pop bc
        pop hl
        jr z,dr_ok              ; POP aendert keine Flags
        inc hl
        djnz dr_lp
        ret                     ; keine Variante passt
dr_ok:  ld bc,4*256+30          ; kurzer Klick
        jp tone

; Hard Drop: sofort auf die Ghost-Position, 2 Punkte pro Zeile, ablegen
hard_drop:
        call calc_ghost         ; sicherheitshalber frisch berechnen
        ld a,(piece_row)
        ld c,a
        ld a,(ghost_row)
        sub c
        jr z,hdr_lock
        ld b,a
hdr_pts:
        push bc
        ld de,pts_hard
        call add_score
        pop bc
        djnz hdr_pts
        call erase_piece
        ld a,(ghost_row)
        ld (piece_row),a
        call draw_only
        call draw_stats
hdr_lock:
        jp lock_and_next

; ==========================================================================
;  Schwerkraft, Ablegen, neue Figur
; ==========================================================================

; Jeden Frame aufrufen: nach fall_delay Frames eine Zeile fallen
gravity:
        ld hl,fall_cnt
        dec (hl)
        ret nz
        ld a,(fall_delay)
        ld (hl),a
        ; weiter in step_down

; Eine Zeile nach unten; geht das nicht, Figur ablegen + neue Figur
step_down:
        call try_down
        ret z
lock_and_next:
        ld bc,10*256+180        ; dumpfer Aufsetz-Ton
        call tone
        call lock_piece
        call check_lines
        jp new_piece

; Eine Zeile nach unten versuchen: Z = bewegt, NZ = liegt auf
try_down:
        ld a,(piece_row)
        inc a
        ld b,a
        ld a,(piece_col)
        ld c,a
        ld a,(piece_rot)
        jp try_move

; Aktive Figur ins Spielfeld-Array schreiben (Wert = Typ+1).
; Auf dem Bildschirm steht sie schon in der richtigen Farbe.
lock_piece:
        ld a,(piece_type)
        inc a
        ld (lock_val),a
        ld a,(piece_rot)
        call cells_ptr
        ld a,(piece_row)
        ld b,a
        ld a,(piece_col)
        ld c,a
        ld a,4
lk_lp:  push af
        push bc
        ld a,(de)
        and $0f
        add a,c
        ld c,a
        ld a,(de)
        rrca
        rrca
        rrca
        rrca
        and $0f
        add a,b
        ld b,a
        call board_addr
        ld a,(lock_val)
        ld (hl),a
        pop bc
        pop af
        inc de
        dec a
        jr nz,lk_lp
        ret

; Naechste Figur oben einsetzen: next_type wird aktiv, neue Vorschau ziehen.
; Passt sie nicht mehr: Game Over -> Meldung, Taste, Feld leeren.
new_piece:
        ld a,(next_type)
        ld (piece_type),a
        call bag_next
        ld (next_type),a
        call draw_next
        call spawn
        ld a,(fall_delay)
        ld (fall_cnt),a
        ld a,1
        ld (down_lock),a
        xor a
        call cells_ptr
        ld b,0
        ld c,SPAWN_COL
        call fits
        jr z,np_ok
        call draw_only          ; ueberlappende Figur zeigen
        call snd_over
        call update_best
        ld hl,msg_over
        call draw_list
        ld a,ATTR_OVER          ; GAME OVER rot
        call color_over
        ld b,50                 ; 1 s Pause, damit niemand versehentlich weiterdrueckt
        call wait_frames
        call save_best          ; neuer Rekord -> als TAP sichern
        call wait_key
        jp new_game             ; zurueck zum Splash (Einstellungen aendern)
np_ok:  jp draw_piece

; A = Attribut fuer die GAME-OVER-Zeile (Zeile 17, Spalten 23-31)
color_over:
        ld hl,$5800+17*32+23
        ld b,9
co_lp:  ld (hl),a
        inc hl
        djnz co_lp
        ret

; ==========================================================================
;  Punkte, Level, Anzeige
; ==========================================================================

; Neues Spiel: Punkte, Zeilen, Level auf 0
reset_game:
        ld hl,0
        ld (score),hl
        ld (score+1),hl         ; 3 Bytes BCD
        ld (lines),hl           ; 2 Bytes BCD
        xor a
        ld (level),a
        ld (level_bcd),a
        ld a,LINES_PER_LEVEL
        ld (level_left),a
        call set_speed
        ld a,(fall_delay)       ; Schwerkraft-Takt passend zum neuen Tempo
        ld (fall_cnt),a
        jp draw_stats

; fall_delay aus der Tabelle fuer das aktuelle Level
set_speed:
        ld a,(level)
        cp MAX_LEVEL_SPEED
        jr c,ss_ok
        ld a,MAX_LEVEL_SPEED
ss_ok:  ld e,a
        ld d,0
        ld hl,speed_table
        add hl,de
        ld a,(hl)
        ld (fall_delay),a
        ret

; DE = 3 Byte BCD (niederwertiges Byte zuerst) zu score addieren.
; Ueberlauf -> 999999.  Veraendert A, B, DE, HL.
add_score:
        ld hl,score
        ld b,3
        or a                    ; Carry loeschen
as_lp:  ld a,(de)
        adc a,(hl)
        daa
        ld (hl),a
        inc hl                  ; INC rr / DJNZ lassen das Carry stehen
        inc de
        djnz as_lp
        ret nc
        ld a,$99
        ld (score),a
        ld (score+1),a
        ld (score+2),a
        ret

; Punkte fuer full_cnt Zeilen: Basis * (Level+1), danach Zeilen/Level erhoehen
score_lines:
        ld a,(full_cnt)
        dec a
        ld e,a
        add a,a
        add a,e                 ; *3 Bytes
        ld e,a
        ld d,0
        ld hl,pts_lines
        add hl,de               ; HL = Basispunkte
        ld a,(level)
        inc a
        ld c,a                  ; Level+1 mal addieren
sl_add: push hl
        push bc
        ex de,hl
        call add_score
        pop bc
        pop hl
        dec c
        jr nz,sl_add

        ld a,(full_cnt)
        ld c,a
sl_line:
        ld a,(lines)            ; lines += 1 (BCD)
        add a,1
        daa
        ld (lines),a
        ld a,(lines+1)
        adc a,0
        daa
        ld (lines+1),a
        ld hl,level_left
        dec (hl)
        jr nz,sl_next
        ld (hl),LINES_PER_LEVEL
        ld hl,level             ; Level hoch
        inc (hl)
        ld a,(level_bcd)
        add a,1
        daa
        ld (level_bcd),a
        call set_speed
        call level_flash
sl_next:
        dec c
        jr nz,sl_line
        jp draw_stats

; kurzer Randblitz beim Levelaufstieg
level_flash:
        push bc
        ld b,6
lf_lp:  push bc
        ld a,b                  ; steigende Toene
        add a,a
        add a,a
        add a,a
        add a,20
        ld c,a
        ld b,40
        call tone
        pop bc                  ; tone setzt den Rand schwarz -> Farbe erst danach
        push bc
        ld a,b
        and 1
        jr z,lf_1
        ld a,6                  ; gelb
lf_1:   out ($fe),a
        ld b,2
        call wait_frames
        pop bc
        djnz lf_lp
        xor a
        out ($fe),a
        pop bc
        ret

; Bestwert merken, falls score groesser
update_best:
        ld hl,score+2
        ld de,best+2
        ld b,3
ub_cmp: ld a,(de)
        cp (hl)
        jr c,ub_copy            ; best < score
        ret nz                  ; best > score
        dec hl
        dec de
        djnz ub_cmp
        ret                     ; gleich
ub_copy:
        ld hl,score
        ld de,best
        ld bc,3
        ldir
        jp draw_stats

; Neuer Rekord seit dem letzten Sichern?  Dann ueber die ROM-Routine
; SA-BYTES ($04C2) als Kopfblock + Datenblock auf "Band" (TAP) schreiben.
save_best:
        ld hl,best
        ld de,best_sv
        ld b,3
sb_cmp: ld a,(de)
        cp (hl)
        jr nz,sb_do
        inc hl
        inc de
        djnz sb_cmp
        ret                     ; Rekord unveraendert
sb_do:  ld hl,best
        ld de,best_sv
        ld bc,3
        ldir
        ld hl,msg_save
        call draw_list
        ld ix,hdr_best          ; Kopfblock (17 Bytes, Flag 0)
        ld de,17
        xor a
        call $04c2
        ld b,10                 ; kurze Pause zwischen den Bloecken
        call wait_frames
        ld ix,best              ; Datenblock (3 Bytes, Flag $FF)
        ld de,3
        ld a,$ff
        call $04c2
        xor a
        out ($fe),a             ; Rand wieder schwarz
        ei
        ld hl,msg_clr
        jp draw_list

; Rekord vom "Band" lesen (ROM LD-BYTES $0556): erst der Kopfblock, dessen
; Name "tetris_hi" sein muss, dann die 3 Datenbytes.  Bei Fehler bleibt best = 0.
load_best:
        ld ix,hdr_in
        ld de,17
        xor a                   ; Flag 0 = Kopfblock
        scf                     ; Carry = laden
        call $0556
        jr nc,lb_fail
        ld hl,hdr_in            ; Typ + Name pruefen
        ld de,hdr_best
        ld b,11
lb_cmp: ld a,(de)
        cp (hl)
        jr nz,lb_fail
        inc hl
        inc de
        djnz lb_cmp
        ld ix,best
        ld de,3
        ld a,$ff                ; Flag $FF = Datenblock
        scf
        call $0556
        jr nc,lb_fail
        ld hl,best              ; als gesichert merken -> kein sofortiges Neu-Sichern
        ld de,best_sv
        ld bc,3
        ldir
        jr lb_end
lb_fail:
        ld hl,0
        ld (best),hl
        ld (best+1),hl
lb_end: xor a
        out ($fe),a
        ei
        ret

; Punkte, Zeilen, Level, Bestwert anzeigen
draw_stats:
        ld hl,score+2
        ld d,3
        ld bc,3*256+2           ; Zeile 3, Spalte 2
        call print_bcd
        ld hl,level_bcd
        ld d,1
        ld bc,7*256+3
        call print_bcd
        ld hl,lines+1
        ld d,2
        ld bc,11*256+3
        call print_bcd
        ld hl,best+2
        ld d,3
        ld bc,19*256+2
        ; weiter in print_bcd

; HL = hoechstwertiges BCD-Byte, D = Anzahl Bytes, B/C = Position
print_bcd:
        ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        and $0f
        call pb_dig
        ld a,(hl)
        and $0f
        call pb_dig
        dec hl
        dec d
        jr nz,print_bcd
        ret
pb_dig: add a,'0'
        push hl
        push de
        push bc
        call print_char
        pop bc
        pop de
        pop hl
        inc c
        ret

; Vorschaufeld: Blockmuster einmalig zeichnen
draw_prev_pattern:
        ld b,PREV_ROW
dpp_r:  ld c,PREV_COL
dpp_c:  push bc
        call cell_pix
        ld de,pat_block
        ld b,8
dpp_l:  ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz dpp_l
        pop bc
        inc c
        ld a,c
        cp PREV_COL+4
        jr nz,dpp_c
        inc b
        ld a,b
        cp PREV_ROW+2
        jr nz,dpp_r
        ret

; Vorschaufeld: 4x2 Zellen schwarz (Attribut 0)
clear_next:
        ld b,PREV_ROW           ; erst 4x2 Zellen schwarz
dn_r:   ld c,PREV_COL
        call cell_attr
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        inc b
        ld a,b
        cp PREV_ROW+2
        jr nz,dn_r
        ret

; next_type in Grundstellung ins Vorschaufeld malen
draw_next:
        call clear_next
        ld a,(next_type)
        inc a
        call color_of
        ld (paint_attr),a
        ld a,(next_type)        ; Zellen von Typ next_type, Rot 0
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,pieces
        add hl,de
        ex de,hl
        ld a,4
dn_lp:  push af
        ld a,(de)
        and $0f
        add a,PREV_COL
        ld c,a
        ld a,(de)
        rrca
        rrca
        rrca
        rrca
        and $0f
        ld b,a                  ; dy (0..1)
        ld a,(next_type)
        or a
        jr nz,dn_y
        dec b                   ; I liegt in Grundstellung in Zeile 1 -> hochziehen
dn_y:   ld a,b
        add a,PREV_ROW
        ld b,a
        call cell_attr
        ld a,(paint_attr)
        ld (hl),a
        inc de
        pop af
        dec a
        jr nz,dn_lp
        ret

; ==========================================================================
;  Volle Zeilen
; ==========================================================================

; Nach dem Ablegen: volle Zeilen suchen, blinken lassen, entfernen
check_lines:
        xor a
        ld (full_cnt),a
        ld b,0                  ; Brettzeile (Boden = Zeile 20 nicht pruefen)
cl_row: ld c,1
        call board_addr
        ld e,BOARD_W-2
cl_col: ld a,(hl)
        or a
        jr z,cl_next            ; Luecke -> Zeile nicht voll
        inc hl
        dec e
        jr nz,cl_col
        ld hl,full_rows         ; volle Zeile merken (aufsteigend)
        ld a,(full_cnt)
        ld e,a
        ld d,0
        add hl,de
        ld (hl),b
        inc a
        ld (full_cnt),a
cl_next:
        inc b
        ld a,b
        cp BOARD_H-1
        jr nz,cl_row

        ld a,(full_cnt)
        or a
        ret z

        ld d,3                  ; 3x blinken
cl_fl:  push de
        ld a,ATTR_FLASH
        call paint_full
        ld a,(full_cnt)         ; Tonhoehe: mehr Reihen = hoeher
        ld e,a
        ld a,90
cl_snd: sub 15
        dec e
        jr nz,cl_snd
        ld c,a
        ld b,60
        call tone
        ld b,3
        call wait_frames
        ld a,ATTR_EMPTY
        call paint_full
        ld b,4
        call wait_frames
        pop de
        dec d
        jr nz,cl_fl

        ; von oben nach unten entfernen: so bleiben die gemerkten
        ; Zeilennummern darunter gueltig
        ld a,(full_cnt)
        ld b,a
        ld hl,full_rows
cl_rm:  push bc
        push hl
        ld b,(hl)
        call remove_row
        pop hl
        inc hl
        pop bc
        djnz cl_rm

        call render_board
        jp score_lines

; A = Attribut fuer alle gemerkten vollen Zeilen (nur Bildschirm)
paint_full:
        ld e,a
        ld a,(full_cnt)
        ld d,a
        ld hl,full_rows
pf_lp:  ld a,(hl)
        push hl
        push de
        add a,SCR_ROW0
        ld b,a
        ld c,SCR_COL0+1
        call cell_attr
        ld b,BOARD_W-2
pf_col: ld (hl),e
        inc hl
        djnz pf_col
        pop de
        pop hl
        inc hl
        dec d
        jr nz,pf_lp
        ret

; B = Brettzeile entfernen: alles darueber eine Zeile tiefer, Zeile 0 leer.
; Ganze Zeilen inkl. Waende werden kopiert, die Waende bleiben also stehen.
remove_row:
        ld a,b
        or a
        jr z,rr_top
        ld c,BOARD_W-1
        call board_addr         ; HL = letzte Zelle der Zeile (Ziel-Ende)
        ld d,h
        ld e,l
        ld a,l
        sub BOARD_W
        ld l,a                  ; HL = letzte Zelle der Zeile darueber
        inc a
        ld c,a                  ; Anzahl = 12 * Zeile
        ld b,0
        lddr
rr_top: ld hl,BOARD+1
        ld b,BOARD_W-2
rr_clr: ld (hl),0
        inc hl
        djnz rr_clr
        ret

; ==========================================================================
;  Zufall: Xorshift16 (Periode 65535) + 7-Bag
; ==========================================================================

; -> A = Zufallsbyte.  Veraendert HL.
rnd:    ld hl,(seed)
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
        ret

; -> A = naechste Figur aus dem Beutel (jede der 7 genau einmal pro Runde)
bag_next:
        ld a,(bag_pos)
        cp 7
        call nc,bag_fill
        ld a,(bag_pos)
        ld e,a
        inc a
        ld (bag_pos),a
        ld d,0
        ld hl,bag
        add hl,de
        ld a,(hl)
        ret

; Beutel mit 0..6 fuellen und mischen (Fisher-Yates)
bag_fill:
        ld hl,bag
        xor a
bf_ini: ld (hl),a
        inc hl
        inc a
        cp 7
        jr nz,bf_ini
        ld c,6                  ; i = 6 .. 1
bf_shf: call rnd
        ld e,c
        inc e                   ; Modulo i+1
bf_mod: cp e
        jr c,bf_swp
        sub e
        jr bf_mod
bf_swp: ld hl,bag               ; A = j, tausche bag[i] <-> bag[j]
        ld e,a
        ld d,0
        add hl,de
        push hl
        ld hl,bag
        ld e,c
        add hl,de
        pop de
        ld a,(de)
        ld b,(hl)
        ld (hl),a
        ld a,b
        ld (de),a
        dec c
        jr nz,bf_shf
        xor a
        ld (bag_pos),a
        ret

; ==========================================================================
;  Sound (Beeper, Port $FE Bit 4)
; ==========================================================================

; B = Anzahl Halbwellen, C = Laenge einer Halbwelle (groesser = tiefer)
; Lautstaerke (opt_vol 0-3) ueber das Tastverhaeltnis: Der Beeper hat nur
; 1 Bit, aber je schmaler die Hoch-Phase einer Periode, desto leiser.
;   3 = 50 %   2 = 25 %   1 = 12,5 %   0 = aus (kehrt sofort zurueck)
; Periode = 2*C: Hoch H, danach Tief (C-H) + C.  Rand bleibt schwarz.
; Veraendert A und B, erhaelt C, D, E, H, L.
tone:   ld a,(opt_vol)
        or a
        ret z
        push hl
        push de
        ld e,a
        ld a,c
        dec e
        jr z,tn_q               ; Stufe 1: C/4
        dec e
        jr z,tn_h               ; Stufe 2: C/2
        jr tn_f                 ; Stufe 3: C
tn_q:   srl a
tn_h:   srl a
tn_f:   ld h,a                  ; H = Hoch-Zaehler
        ld a,c
        sub h
        ld l,a                  ; L = C - H (bei Stufe 3 gleich 0)
        ld a,b
        srl a                   ; B Halbwellen = B/2 Perioden
        jr nz,tn_cnt
        inc a
tn_cnt: ld b,a
        di
tn_per: ld a,$10
        out ($fe),a
        ld d,h
tn_d1:  dec d
        jr nz,tn_d1
        xor a
        out ($fe),a
        ld d,l
        inc d
        dec d
        jr z,tn_l2              ; L = 0 ueberspringen (sonst 256 Durchlaeufe)
tn_d2:  dec d
        jr nz,tn_d2
tn_l2:  ld d,c
tn_d3:  dec d
        jr nz,tn_d3
        djnz tn_per
        ei
        pop de
        pop hl
        ret

; Game Over: absteigende Tonfolge
snd_over:
        ld c,40
so_lp:  ld b,30
        call tone
        ld a,c
        add a,20
        ld c,a
        cp 240
        jr c,so_lp
        ret

; ==========================================================================
;  Splash-Screen mit Einstellungen
; ==========================================================================

SPL_ROW_VOL equ 11              ; Zeile der Lautstaerke-Einstellung
SPL_ROW_GHO equ 13              ; Zeile der Ghost-Einstellung
SPL_ROW_UP  equ 15              ; Zeile Joystick-hoch (Hard Drop)
SPL_SEL     equ $46             ; gewaehlte Zeile: BRIGHT, INK 6 (gelb)
SPL_DIM     equ $07             ; andere Zeile: normal weiss

; Zeigt Titel und Einstellungen.  Joystick links/rechts aendert den Wert,
; Joystick runter wechselt die Zeile.  Nur Feuer startet.  Waehrend des Wartens laeuft seed hoch -> Zufallsstartwert.
splash:
        ld a,1
        ld (menu_mode),a        ; Tastatur: nur Start, Einstellungen per Joystick
        call draw_title
        ld hl,splash_texts
        call draw_list
        ld hl,$5800+20*32+9     ; "FEUER = START" blinkt (FLASH-Attribut)
        ld b,13
        ld a,$c7                ; FLASH, BRIGHT, INK 7
spl_bl: ld (hl),a
        inc hl
        djnz spl_bl
        ld hl,best+2            ; Rekord
        ld d,3
        ld bc,22*256+16
        call print_bcd
        xor a
        ld (spl_sel),a
        call spl_refresh
spl_lp: halt
        ld hl,(seed)
        inc hl
        ld (seed),hl
        call read_input
        ld a,(pressed)
        and M_FIRE              ; nur Feuer startet (hoch/Tastatur nicht)
        jr nz,spl_go
        ld a,(pressed)
        bit K_DOWN,a
        jr z,spl_lr
        ld a,(spl_sel)          ; Zeile wechseln (0,1,2 im Kreis)
        inc a
        cp 3
        jr c,spl_sv
        xor a
spl_sv: ld (spl_sel),a
        call spl_refresh
spl_lr: ld a,(pressed)
        and M_LR
        jr z,spl_lp
        call spl_change
        call spl_refresh
        jr spl_lp
spl_go: xor a
        ld (menu_mode),a        ; im Spiel gilt die Tastatur wieder voll
        ld hl,(seed)            ; Zufall: Frames + Register R
        ld a,r
        xor l
        ld l,a
        or h
        jr nz,sg_ok
        inc l                   ; Xorshift braucht Startwert <> 0
sg_ok:  ld (seed),hl
        ld a,$ff                ; gehaltene Taste nicht als neuen Druck werten
        ld (keys),a
        ret

; Wert der gewaehlten Zeile aendern (links/rechts aus pressed)
spl_change:
        ld a,(spl_sel)
        or a
        jr nz,sc_o
        ld a,(opt_vol)
        ld b,a
        ld a,(pressed)
        bit K_LEFT,a
        jr z,sc_r
        ld a,b                  ; leiser (bei 0 stehen bleiben)
        or a
        ret z
        dec a
        jr sc_st
sc_r:   ld a,b                  ; lauter (bei 3 stehen bleiben)
        cp 3
        ret nc
        inc a
sc_st:  ld (opt_vol),a
        ld bc,20*256+60         ; Hoerprobe in der neuen Lautstaerke
        jp tone
sc_o:   dec a
        jr nz,sc_up
        ld a,(opt_ghost)
        xor 1
        ld (opt_ghost),a
        ret
sc_up:  ld a,(opt_up)
        xor 1
        ld (opt_up),a
        ret

; Werte als Text ausgeben und die gewaehlte Zeile gelb markieren
spl_refresh:
        ld a,(opt_vol)
        ld e,a
        add a,a
        add a,a
        add a,a
        add a,e                 ; *9 (8 Zeichen + Endmarke)
        ld e,a
        ld d,0
        ld hl,vol_txt
        add hl,de
        ld b,SPL_ROW_VOL
        ld c,16
        call print_at
        ld a,(opt_ghost)
        ld e,a
        add a,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        ld hl,ghost_txt
        add hl,de
        ld b,SPL_ROW_GHO
        ld c,16
        call print_at
        ld a,(opt_up)
        ld e,a
        add a,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        ld hl,ghost_txt
        add hl,de
        ld b,SPL_ROW_UP
        ld c,16
        call print_at
        ld hl,$5800+SPL_ROW_VOL*32+6
        ld b,0                  ; Zeilen 0..2: gewaehlte gelb, andere weiss
sr_lp3: ld a,(spl_sel)
        cp b
        ld a,SPL_DIM
        jr nz,sr_c
        ld a,SPL_SEL
sr_c:   push bc
        call spl_row
        pop bc
        ld de,45                ; naechste Einstellungszeile (2 Zeilen weiter)
        add hl,de
        inc b
        ld a,b
        cp 3
        jr nz,sr_lp3
        ret
spl_row:
        ld b,19                 ; Spalten 6-24
sr_lp:  ld (hl),a
        inc hl
        djnz sr_lp
        ret

; Grosser Titel aus Blockzellen: 6 Buchstaben, je 3x5 Zellen, ab Zeile 3
draw_title:
        xor a
        ld (tt_pos),a
dtt_p:  ld a,(tt_pos)
        ld e,a
        ld d,0
        ld hl,title_word
        add hl,de
        ld a,(hl)               ; Buchstabennummer
        ld c,a
        add a,a
        add a,a
        add a,c                 ; *5 Bytes je Buchstabe
        ld e,a
        ld hl,font5
        add hl,de
        ld (tt_font),hl
        ld a,(tt_pos)
        ld e,a
        ld hl,title_cols
        add hl,de
        ld a,(hl)
        ld (tt_attr),a
        ld a,(tt_pos)
        add a,a
        add a,a
        add a,4                 ; Startspalte = 4 + 4*Position
        ld (tt_col),a
        xor a
        ld (tt_row),a
dtt_r:  ld hl,(tt_font)
        ld a,(tt_row)
        ld e,a
        ld d,0
        add hl,de
        ld d,(hl)               ; D = 3 Bits der Zeile (Bit 2 = links)
        ld e,0                  ; E = Spalte im Buchstaben
dtt_c:  bit 2,d
        jr z,dtt_n
        push de
        ld a,(tt_row)
        add a,3
        ld b,a
        ld a,(tt_col)
        add a,e
        ld c,a
        call put_block
        pop de
dtt_n:  sla d
        inc e
        ld a,e
        cp 3
        jr nz,dtt_c
        ld a,(tt_row)
        inc a
        ld (tt_row),a
        cp 5
        jr nz,dtt_r
        ld a,(tt_pos)
        inc a
        ld (tt_pos),a
        cp 6
        jr nz,dtt_p
        ret

; Blockzelle bei B = Zeile, C = Spalte: Muster + Farbe aus tt_attr
put_block:
        push bc
        call cell_pix
        ld de,pat_block
        ld b,8
pbk_l:  ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz pbk_l
        pop bc
        call cell_attr
        ld a,(tt_attr)
        ld (hl),a
        ret

; ==========================================================================
;  Warten
; ==========================================================================

; B = Anzahl Frames
wait_frames:
        halt
        djnz wait_frames
        ret

; Auf Loslassen, dann auf eine Taste (inkl. IF2-Joystick) warten.
; Die Frames bis zum Druck + Register R ergeben den Startwert fuer rnd.
wait_key:
        xor a
        in a,($fe)
        cpl
        and $1f
        jr nz,wait_key
wk_lp:  ld hl,(seed)
        inc hl
        ld (seed),hl
        halt
        xor a
        in a,($fe)
        cpl
        and $1f
        jr z,wk_lp
        ld a,r
        ld hl,(seed)
        xor l
        ld l,a
        or h
        jr nz,wk_ok
        inc l                   ; Xorshift braucht Startwert <> 0
wk_ok:  ld (seed),hl
        ld a,$ff                ; gehaltene Taste nicht als neuen Druck werten
        ld (keys),a
        ret

; ==========================================================================
;  Daten
; ==========================================================================

; Attribut je Zellwert: 0 leer, 1 I, 2 O, 3 T, 4 S, 5 Z, 6 J, 7 L, 8 Wand
; Figuren: BRIGHT + PAPER Farbe + INK 0 (schwarze Fuge aus dem Muster)
cell_colors:
        db ATTR_EMPTY           ; leer: PAPER 0, INK 1 -> dunkelblaues Raster
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
        db 2,24,"TETRIS",0
        db 4,25,"NEXT",0
        db 9,23,"O P <  >",0
        db 10,23,"Q DREHEN",0
        db 11,23,"A RUNTER",0
        db 12,23,"SPC DROP",0
        db 14,23,"JOYSTICK",0
        db 15,23,"IF2 1+2",0
        db 2,2,"PUNKTE",0
        db 6,2,"LEVEL",0
        db 10,2,"REIHEN",0
        db 18,2,"REKORD",0
        db $ff

; Wall-Kick-Versatz in Spalten (I nutzt alle 5)
kick_tab:   db 0,-1,1,-2,2

; Frames pro Zeile je Level (50 Hz), angelehnt an NES-Tetris (PAL)
speed_table:
        db 48,43,38,33,28,23,18,13,8,6
        db 5,5,5,4,4,4,3,3,3,2
        db 2,2,2,2,2,2,2,2,2,1

; Punkte als 3 Byte BCD, niederwertig zuerst
pts_soft:   db $01,$00,$00
pts_hard:   db $02,$00,$00
pts_lines:  db $40,$00,$00      ;   40  Single
            db $00,$01,$00      ;  100  Double
            db $00,$03,$00      ;  300  Triple
            db $00,$12,$00      ; 1200  Tetris

msg_load:
        db 11,10,"LADE REKORD",0
        db $ff
msg_save:
        db 22,23,"SICHERE",0
        db 23,23,"REKORD",0
        db $ff
msg_clr:
        db 22,22,"       ",0
        db 23,22,"      ",0
        db $ff

msg_over:
        db 17,23,"GAME OVER",0
        db 19,24,"TASTE",0
        db 20,23,"DRUECKEN",0
        db $ff

splash_texts:
        db 9,8,"FUER ZX SPECTRUM",0
        db 11,6,"SOUND",0
        db 11,14,"<",0
        db 11,24,">",0
        db 13,6,"GHOST",0
        db 13,14,"<",0
        db 13,24,">",0
        db 15,6,"HOCH",0
        db 15,14,"<",0
        db 15,24,">",0
        db 17,3,"STICK LINKS RECHTS = WERT",0
        db 18,3,"STICK RUNTER = ZEILE",0
        db 20,9,"FEUER = START",0
        db 22,9,"REKORD",0
        db $ff

; Werte der Einstellungen, je 8 Zeichen + Endmarke
vol_txt:    db "AUS     ",0
            db "LEISE   ",0
            db "MITTEL  ",0
            db "LAUT    ",0
ghost_txt:  db "AUS     ",0
            db "AN      ",0

; Titelschrift 3x5: T E R I S (Bit 2 = linke Spalte)
font5:      db %111,%010,%010,%010,%010     ; T
            db %111,%100,%110,%100,%111     ; E
            db %110,%101,%110,%101,%101     ; R
            db %111,%010,%010,%010,%111     ; I
            db %111,%100,%111,%001,%111     ; S
title_word: db 0,1,0,2,3,4                  ; T E T R I S
title_cols: db $50,$70,$58,$60,$68,$48      ; rot gelb magenta gruen cyan blau

; --- Variablen ------------------------------------------------------------
piece_type: db 0
piece_rot:  db 0
piece_row:  db 0
piece_col:  db 0
new_rot:    db 0
new_pos:    dw 0                ; Low = Spalte (C), High = Zeile (B)
paint_attr: db 0
paint_row:  db 0
ghost_row:  db 0
rot_try:    db 0
sp_save:    dw 0                ; Stack beim Programmstart
opt_vol:    db 2                ; Lautstaerke 0 aus .. 3 laut
opt_ghost:  db 0                ; Ghost 0 aus, 1 an
opt_up:     db 0                ; Stick hoch = Hard Drop: 0 aus, 1 an
spl_sel:    db 0                ; Splash: gewaehlte Zeile
menu_mode:  db 0                ; 1 = Splash aktiv (Tastatur nur Start)
tt_pos:     db 0                ; Titel-Zeichenroutine
tt_font:    dw 0
tt_attr:    db 0
tt_col:     db 0
tt_row:     db 0
keys:       db 0
pressed:    db 0
das_cnt:    db 0
drop_cnt:   db 0
fall_delay: db 0                ; Frames pro Zeile
fall_cnt:   db 0
down_lock:  db 0                ; 1 = Runter erst nach Loslassen
lock_val:   db 0
next_type:  db 0                ; Vorschau
seed:       dw 1
bag:        ds 7
bag_pos:    db 7
full_rows:  ds 4
full_cnt:   db 0
lines:      dw 0                ; BCD, 4 Stellen
score:      ds 3                ; BCD, 6 Stellen, niederwertig zuerst
best:       ds 3
best_sv:    ds 3                ; zuletzt gesicherter Rekord
hdr_in:     ds 17               ; gelesener Kopfblock
hdr_best:   db 3,"tetris_hi ",3,0   ; Typ CODE, Name (10), Laenge 3
            dw best,32768           ; Startadresse, Parameter
level:      db 0                ; binaer (fuer Tabelle/Multiplikator)
level_bcd:  db 0                ; BCD (fuer Anzeige)
level_left: db 0                ; Zeilen bis zum naechsten Level

        end start
