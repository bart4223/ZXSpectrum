; ============================================================
;  BOULDER DASH fuer ZX Spectrum  -  Stufe 0: Fundament
;  16x16-Kacheln, Hoehle 40x22, scrollender Viewport 16x11
;
;  Assembler: pasmo   ->   pasmo --tapbas boulderdash.asm boulderdash.tap
;
;  Inhalt dieser Stufe:
;   - Hoehle als Byte-Array (40 x 22 Felder, Tile-IDs)
;   - Viewport (Kamera): 16 x 11 Felder sichtbar, cam_x / cam_y
;   - Kachel = 16x16 Pixel = 2x2 Zeichen, je Zeichen ein eigenes
;     Attribut (also 4 Farben pro Kachel, kein Attribute Clash)
;   - Dirty-Liste: nur geaenderte Felder werden neu gezeichnet,
;     Felder ausserhalb des Viewports werden verworfen
;   - Scrollen in Kachelschritten = Viewport komplett neu zeichnen
;   - fester Spieltakt: HALT = 50 Hz, Logik-Tick alle 6 Frames
;   - Demo: Diamanten funkeln, Kamera per Tasten/Joystick bewegen
;
;  Steuerung (Kamera):  Q=hoch  A=runter  O=links  P=rechts
;                       oder Sinclair-Joystick 1 (Tasten 6-0)
;                       SPACE beendet und kehrt zu BASIC zurueck
; ============================================================

        org     32768

; ---------- Konstanten ----------
CAVE_W          equ     40
CAVE_H          equ     22
CAVE_SIZE       equ     CAVE_W*CAVE_H   ; 880
VIEW_W          equ     16              ; sichtbare Felder
VIEW_H          equ     11
CAM_MAX_X       equ     CAVE_W-VIEW_W   ; 24
CAM_MAX_Y       equ     CAVE_H-VIEW_H   ; 11
CAM_START_X     equ     0
CAM_START_Y     equ     0
FRAMES_PER_TICK equ     6
DIRTY_MAX       equ     192
SEED_START      equ     0ACE1h
CHAN_OPEN       equ     1601h

; Tile-IDs (Reihenfolge = frame_table)
T_EMPTY         equ     0
T_DIRT          equ     1
T_BRICK         equ     2
T_STEEL         equ     3
T_STONE         equ     4
T_DIAMOND       equ     5
T_ROCKFORD      equ     6
T_EXIT          equ     7

; Eingabe-Bits
IN_LEFT         equ     1
IN_RIGHT        equ     2
IN_UP           equ     4
IN_DOWN         equ     8

; ============================================================
start:
        xor     a
        out     (0FEh),a                ; Rand schwarz
        ld      (frame_ctr),a
        ld      (anim_phase),a
        ld      (dirty_count),a
        ld      (dirty_overflow),a
        ld      (input_latch),a
        ld      a,CAM_START_X
        ld      (cam_x),a
        ld      a,CAM_START_Y
        ld      (cam_y),a
        ld      hl,0
        ld      (tick_count),hl
        ld      hl,SEED_START
        ld      (seed),hl               ; gleiche Hoehle bei jedem Start

        call    clear_screen
        ld      a,2
        call    CHAN_OPEN               ; ROM-Ausgabe auf oberen Bildschirm
        ld      hl,txt_header
        call    print_str

        call    gen_cave
        call    draw_view
        call    print_status

main_loop:
        halt                            ; auf Bildstrahl-Ruecklauf warten
        call    flush_dirty             ; zuerst zeichnen (wenig Flackern)
        call    scan_input              ; Eingabe merken, bis der Tick sie holt

        ld      hl,frame_ctr
        inc     (hl)
        ld      a,(hl)
        cp      FRAMES_PER_TICK
        jr      c,ml_keys
        ld      (hl),0
        call    game_tick

ml_keys:
        ld      a,7Fh                   ; Halbreihe SPACE..B
        in      a,(0FEh)
        rra                             ; Bit 0 = SPACE (0 = gedrueckt)
        jr      c,main_loop
        exx
        ld      hl,2758h                ; HL' fuer die Rueckkehr nach BASIC
        exx
        ret

; ============================================================
;  Spiellogik (Stufe 0: Kamera + Animation)
; ============================================================
game_tick:
        ld      a,(anim_phase)
        xor     1
        ld      (anim_phase),a

        ; --- Kamera bewegen ---
        ld      a,(input_latch)
        ld      c,a
        xor     a
        ld      (input_latch),a
        ld      b,0                     ; B = Anzahl Kamerabewegungen

        ld      a,(cam_x)
        bit     0,c                     ; links
        jr      z,gt_r
        or      a
        jr      z,gt_r
        dec     a
        inc     b
gt_r:   bit     1,c                     ; rechts
        jr      z,gt_xs
        cp      CAM_MAX_X
        jr      nc,gt_xs
        inc     a
        inc     b
gt_xs:  ld      (cam_x),a

        ld      a,(cam_y)
        bit     2,c                     ; hoch
        jr      z,gt_d
        or      a
        jr      z,gt_d
        dec     a
        inc     b
gt_d:   bit     3,c                     ; runter
        jr      z,gt_ys
        cp      CAM_MAX_Y
        jr      nc,gt_ys
        inc     a
        inc     b
gt_ys:  ld      (cam_y),a

        ld      a,b
        or      a
        jr      z,gt_sparkle

        ; Kamera hat sich bewegt: Liste verwerfen, alles neu zeichnen
        xor     a
        ld      (dirty_count),a
        ld      (dirty_overflow),a
        call    draw_view
        jr      gt_stats

        ; --- sichtbare Diamanten als "dirty" markieren (Funkeln) ---
gt_sparkle:
        ld      a,(cam_y)
        ld      d,a
        ld      a,(cam_x)
        ld      e,a
        call    cave_addr               ; HL = Zeiger auf (cam_x,cam_y)
        ld      a,(cam_y)
        ld      d,a                     ; D = y
        ld      c,VIEW_H
gs_row:
        push    hl
        ld      a,(cam_x)
        ld      e,a                     ; E = x
        ld      b,VIEW_W
gs_col:
        ld      a,(hl)
        cp      T_DIAMOND
        call    z,mark_dirty
        inc     hl
        inc     e
        djnz    gs_col
        pop     hl
        ld      a,l                     ; HL += CAVE_W
        add     a,CAVE_W
        ld      l,a
        jr      nc,gs_nc
        inc     h
gs_nc:  inc     d
        dec     c
        jr      nz,gs_row

gt_stats:
        ld      hl,(tick_count)
        inc     hl
        ld      (tick_count),hl
        jp      print_status

; ============================================================
;  Eingabe
; ============================================================
; scan_input: ODER-verknuepft die aktuelle Eingabe in input_latch
scan_input:
        call    read_input
        ld      hl,input_latch
        or      (hl)
        ld      (hl),a
        ret

; read_input: A = IN_LEFT/IN_RIGHT/IN_UP/IN_DOWN (gesetzte Bits)
read_input:
        ld      c,0
        ld      a,0FBh                  ; Q = hoch
        in      a,(0FEh)
        bit     0,a
        jr      nz,ri_a
        set     2,c
ri_a:   ld      a,0FDh                  ; A = runter
        in      a,(0FEh)
        bit     0,a
        jr      nz,ri_o
        set     3,c
ri_o:   ld      a,0DFh                  ; O = links, P = rechts
        in      a,(0FEh)
        ld      b,a
        bit     1,b
        jr      nz,ri_p
        set     0,c
ri_p:   bit     0,b
        jr      nz,ri_j
        set     1,c
ri_j:   ld      a,0EFh                  ; Sinclair 1: 6=links 7=rechts 8=runter 9=hoch
        in      a,(0FEh)
        ld      b,a
        bit     4,b
        jr      nz,ri_j2
        set     0,c
ri_j2:  bit     3,b
        jr      nz,ri_j3
        set     1,c
ri_j3:  bit     2,b
        jr      nz,ri_j4
        set     3,c
ri_j4:  bit     1,b
        jr      nz,ri_end
        set     2,c
ri_end: ld      a,c
        ret

; ============================================================
;  Hoehle: Adressen
; ============================================================
; cave_addr: D = y, E = x  ->  HL = cave + y*40 + x
; zerstoert BC, DE
cave_addr:
        ld      l,d
        ld      h,0
        ld      b,h
        ld      c,l                     ; BC = y
        add     hl,hl
        add     hl,hl                   ; 4y
        add     hl,bc                   ; 5y
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; 40y
        ld      d,0
        add     hl,de                   ; + x
        ld      de,cave
        add     hl,de
        ret

; ============================================================
;  Dirty-Liste (Eintraege: x, y in Hoehlenkoordinaten)
; ============================================================
; mark_dirty: E = x, D = y. Alle Register ausser A bleiben erhalten.
mark_dirty:
        push    hl
        push    bc
        ld      a,(dirty_count)
        cp      DIRTY_MAX
        jr      nc,md_full
        ld      c,a
        inc     a
        ld      (dirty_count),a
        ld      l,c
        ld      h,0
        add     hl,hl
        ld      bc,dirty_list
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     bc
        pop     hl
        ret
md_full:
        ld      a,1                     ; Liste voll -> beim naechsten Flush
        ld      (dirty_overflow),a      ; wird einfach alles neu gezeichnet
        pop     bc
        pop     hl
        ret

; flush_dirty: zeichnet alle markierten Felder und leert die Liste
flush_dirty:
        ld      a,(dirty_overflow)
        or      a
        jr      nz,fd_full
        ld      a,(dirty_count)
        or      a
        ret     z
        ld      b,a
        ld      hl,dirty_list
fd_loop:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    bc
        push    hl
        call    draw_cell
        pop     hl
        pop     bc
        djnz    fd_loop
        xor     a
        ld      (dirty_count),a
        ret
fd_full:
        call    draw_view
        xor     a
        ld      (dirty_count),a
        ld      (dirty_overflow),a
        ret

; ============================================================
;  Renderer
; ============================================================
; draw_view: zeichnet den kompletten Viewport
draw_view:
        ld      a,(cam_y)
        ld      d,a
        ld      a,(cam_x)
        ld      e,a
        call    cave_addr               ; HL = Zeiger auf (cam_x,cam_y)
        ld      c,0                     ; C = ty
dv_row:
        push    hl                      ; Zeilenanfang merken
        ld      b,0                     ; B = tx
dv_col:
        push    bc
        push    hl
        ld      a,(hl)
        call    draw_tile
        pop     hl
        pop     bc
        inc     hl
        inc     b
        ld      a,b
        cp      VIEW_W
        jr      nz,dv_col
        pop     hl
        ld      de,CAVE_W
        add     hl,de                   ; naechste Hoehlenzeile
        inc     c
        ld      a,c
        cp      VIEW_H
        jr      nz,dv_row
        ret

; draw_cell: E = x, D = y in Hoehlenkoordinaten.
; Zeichnet das Feld, falls es im Viewport liegt, sonst nichts.
draw_cell:
        ld      a,(cam_x)
        ld      b,a
        ld      a,e
        sub     b
        cp      VIEW_W
        ret     nc                      ; links/rechts ausserhalb
        ld      b,a                     ; B = tx
        ld      a,(cam_y)
        ld      c,a
        ld      a,d
        sub     c
        cp      VIEW_H
        ret     nc                      ; oben/unten ausserhalb
        ld      c,a                     ; C = ty
        push    bc
        call    cave_addr
        pop     bc
        ld      a,(hl)                  ; A = Tile-ID
        jp      draw_tile

; draw_tile: A = Tile-ID, B = tx (0..15), C = ty (0..10) im Viewport.
; Schreibt 4 Attribute und 16x16 Pixel. Zerstoert alle Register.
draw_tile:
        ld      (tmp_tile),a

        ; --- Bildschirmadresse der Kachel (links oben) ---
        ld      a,c
        add     a,a
        add     a,2                     ; Zeichenzeile r = 2 + 2*ty
        ld      d,a
        and     18h
        or      40h
        ld      h,a                     ; H = 010rr000
        ld      a,d
        and     7
        rrca
        rrca
        rrca
        ld      e,a                     ; E = (r & 7) << 5
        ld      a,b
        add     a,a                     ; Spalte = 2*tx
        or      e
        ld      l,a
        push    hl

        ; --- Frame-Block: frame_table[(Tile*2 + Phase)] ---
        ld      a,(tmp_tile)
        add     a,a
        ld      hl,anim_phase
        or      (hl)
        add     a,a                     ; * 2 (Tabelle aus Woertern)
        ld      c,a
        ld      b,0
        ld      hl,frame_table
        add     hl,bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE = Block (4 Attribute, 32 Bytes Grafik)
        pop     hl                      ; HL = Bildschirmadresse

        ; --- Attributadresse in BC ---
        ld      a,h
        and     18h
        rrca
        rrca
        rrca
        add     a,58h
        ld      b,a
        ld      c,l

        ld      a,(de)                  ; links oben
        ld      (bc),a
        inc     de
        inc     c
        ld      a,(de)                  ; rechts oben
        ld      (bc),a
        inc     de
        ld      a,c
        add     a,31
        ld      c,a
        ld      a,(de)                  ; links unten
        ld      (bc),a
        inc     de
        inc     c
        ld      a,(de)                  ; rechts unten
        ld      (bc),a
        inc     de

        ; --- Pixel: obere Haelfte, dann untere Haelfte (+32 = naechste Zeichenzeile)
        call    dt_half
        ld      a,h
        sub     8
        ld      h,a
        ld      a,l
        add     a,32
        ld      l,a
dt_half:
        ld      b,8
dt_row:
        ld      a,(de)                  ; linkes Byte
        ld      (hl),a
        inc     de
        inc     l
        ld      a,(de)                  ; rechtes Byte
        ld      (hl),a
        inc     de
        dec     l
        inc     h                       ; naechste Pixelzeile
        djnz    dt_row
        ret

; ============================================================
;  Hoehlengenerator (Testhoehle)
; ============================================================
gen_cave:
        ld      hl,cave
        ld      bc,CAVE_SIZE
gc_loop:
        push    bc
        push    hl
        call    rnd                     ; A = Zufallsbyte
        pop     hl
        pop     bc
        cp      30
        jr      nc,gc_a
        ld      d,T_STONE
        jr      gc_store
gc_a:   cp      40
        jr      nc,gc_b
        ld      d,T_DIAMOND
        jr      gc_store
gc_b:   cp      70
        jr      nc,gc_c
        ld      d,T_EMPTY
        jr      gc_store
gc_c:   ld      d,T_DIRT
gc_store:
        ld      (hl),d
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,gc_loop

        ; Stahlrand oben und unten
        ld      hl,cave
        ld      b,CAVE_W
gc_top: ld      (hl),T_STEEL
        inc     hl
        djnz    gc_top
        ld      hl,cave+(CAVE_H-1)*CAVE_W
        ld      b,CAVE_W
gc_bot: ld      (hl),T_STEEL
        inc     hl
        djnz    gc_bot

        ; Stahlrand links und rechts
        ld      hl,cave
        ld      b,CAVE_H
        ld      de,CAVE_W-1
gc_side:
        ld      (hl),T_STEEL
        add     hl,de
        ld      (hl),T_STEEL
        inc     hl
        djnz    gc_side

        ; zwei Ziegelmauern (Zickzack ueber die ganze Hoehle)
        ld      hl,cave+7*CAVE_W+1
        ld      b,24
gc_w1:  ld      (hl),T_BRICK
        inc     hl
        djnz    gc_w1
        ld      hl,cave+14*CAVE_W+15
        ld      b,24
gc_w2:  ld      (hl),T_BRICK
        inc     hl
        djnz    gc_w2

        ; Rockford oben links, Ausgang unten rechts
        ld      a,T_ROCKFORD
        ld      (cave+1*CAVE_W+2),a
        ld      a,T_EXIT
        ld      (cave+20*CAVE_W+38),a
        ret

; rnd: 16-Bit-Xorshift, Ergebnis in A (und HL)
rnd:
        ld      hl,(seed)
        ld      a,h
        rra
        ld      a,l
        rra
        xor     h
        ld      h,a
        ld      a,l
        rra
        ld      a,h
        rra
        xor     l
        ld      l,a
        xor     h
        ld      h,a
        ld      (seed),hl
        ret

; ============================================================
;  Hilfsroutinen Bildschirm / Text
; ============================================================
clear_screen:
        ld      hl,4000h
        ld      de,4001h
        ld      bc,6143
        ld      (hl),0
        ldir
        ld      hl,5800h
        ld      de,5801h
        ld      bc,767
        ld      (hl),07h
        ldir
        ret

; print_status: Ticks, Kameraposition in die Kopfzeile
print_status:
        ld      hl,txt_tickpos
        call    print_str
        ld      hl,(tick_count)
        call    print_num
        ld      hl,txt_xpos
        call    print_str
        ld      a,(cam_x)
        call    print_dec2
        ld      hl,txt_ypos
        call    print_str
        ld      a,(cam_y)
        jp      print_dec2

; print_str: Text ab HL bis Endekennung FFh ueber ROM (RST 10h)
print_str:
        ld      a,(hl)
        cp      0FFh
        ret     z
        push    hl
        rst     10h
        pop     hl
        inc     hl
        jr      print_str

; print_dec2: A (0..99) als zweistellige Dezimalzahl ausgeben
print_dec2:
        ld      b,'0'
pd2_l:  cp      10
        jr      c,pd2_d
        sub     10
        inc     b
        jr      pd2_l
pd2_d:  add     a,'0'
        push    af
        ld      a,b
        rst     10h
        pop     af
        rst     10h
        ret

; print_num: HL als 5-stellige Dezimalzahl ausgeben
print_num:
        ld      bc,-10000
        call    pn_digit
        ld      bc,-1000
        call    pn_digit
        ld      bc,-100
        call    pn_digit
        ld      bc,-10
        call    pn_digit
        ld      bc,-1
pn_digit:
        ld      a,'0'-1
pn_loop:
        inc     a
        add     hl,bc
        jr      c,pn_loop
        sbc     hl,bc
        push    hl
        rst     10h
        pop     hl
        ret

; ============================================================
;  Daten
; ============================================================
txt_header:
        db      22,0,0, 16,6, 17,0, 19,1
        db      "BOULDER DASH  -  STUFE 0"
        db      22,1,0, 16,7, 17,0, 19,0
        db      "TICKS"
        db      22,1,12
        db      "X"
        db      22,1,16
        db      "Y"
        db      22,1,21
        db      "SPACE=ENDE"
        db      0FFh
txt_tickpos:
        db      22,1,6, 16,5, 17,0, 19,1, 0FFh
txt_xpos:
        db      22,1,13, 0FFh
txt_ypos:
        db      22,1,17, 0FFh

; Frame-Tabelle: je Tile zwei Eintraege (Phase 0 und Phase 1)
frame_table:
        dw      blk_empty,   blk_empty
        dw      blk_dirt,    blk_dirt
        dw      blk_brick,   blk_brick
        dw      blk_steel,   blk_steel
        dw      blk_stone,   blk_stone
        dw      blk_diamond0,blk_diamond1
        dw      blk_rockford,blk_rockford
        dw      blk_exit,    blk_exit

; Kachel-Bloecke: 4 Attributbytes (oben links, oben rechts, unten links,
; unten rechts), danach 16 Pixelzeilen zu je 2 Bytes (links, rechts).
; Attribut: FLASH(80h) BRIGHT(40h) PAPER*8 INK  (0=schwarz 1=blau 2=rot
; 3=magenta 4=gruen 5=cyan 6=gelb 7=weiss). '#' = Vordergrund (INK).
blk_empty:  ; leer
        db      000h,000h,000h,000h
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................

blk_dirt:  ; Erde
        db      016h,016h,016h,016h
        db      %00100000,%10000010   ; ..#.....#.....#.
        db      %00000010,%00001000   ; ......#.....#...
        db      %10000010,%10000000   ; #.....#.#.......
        db      %00001000,%00001001   ; ....#.......#..#
        db      %01000000,%01000000   ; .#.......#......
        db      %00000010,%00001000   ; ......#.....#...
        db      %00100000,%10000000   ; ..#.....#.......
        db      %10000000,%10010001   ; #.......#..#...#
        db      %00001000,%00001000   ; ....#.......#...
        db      %01000000,%10000000   ; .#......#.......
        db      %00000010,%00001001   ; ......#.....#..#
        db      %00100000,%10000000   ; ..#.....#.......
        db      %10000100,%00000100   ; #....#.......#..
        db      %00000010,%01000000   ; ......#..#......
        db      %01000000,%00010001   ; .#.........#...#
        db      %00001000,%00001000   ; ....#.......#...

blk_brick:  ; Ziegelmauer
        db      057h,057h,057h,057h
        db      %11111111,%11111111   ; ################
        db      %10000000,%10000000   ; #.......#.......
        db      %10000000,%10000000   ; #.......#.......
        db      %10000000,%10000000   ; #.......#.......
        db      %11111111,%11111111   ; ################
        db      %00001000,%00001000   ; ....#.......#...
        db      %00001000,%00001000   ; ....#.......#...
        db      %00001000,%00001000   ; ....#.......#...
        db      %11111111,%11111111   ; ################
        db      %10000000,%10000000   ; #.......#.......
        db      %10000000,%10000000   ; #.......#.......
        db      %10000000,%10000000   ; #.......#.......
        db      %11111111,%11111111   ; ################
        db      %00001000,%00001000   ; ....#.......#...
        db      %00001000,%00001000   ; ....#.......#...
        db      %00001000,%00001000   ; ....#.......#...

blk_steel:  ; Stahlwand
        db      00Dh,00Dh,00Dh,00Dh
        db      %11111111,%11111111   ; ################
        db      %10000000,%00000001   ; #..............#
        db      %10100000,%00000101   ; #.#..........#.#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10000000,%00000001   ; #..............#
        db      %10100000,%00000101   ; #.#..........#.#
        db      %10000000,%00000001   ; #..............#
        db      %11111111,%11111111   ; ################

blk_stone:  ; Stein
        db      047h,047h,007h,007h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00011111,%11111000   ; ...##########...
        db      %00111111,%11111100   ; ..############..
        db      %00110111,%11111100   ; ..##.#########..
        db      %01110111,%11111110   ; .###.##########.
        db      %01101111,%11111110   ; .##.###########.
        db      %01111111,%11111110   ; .##############.
        db      %01111111,%11111110   ; .##############.
        db      %01111111,%11111110   ; .##############.
        db      %01111111,%11111110   ; .##############.
        db      %00111111,%11111100   ; ..############..
        db      %00111111,%11111100   ; ..############..
        db      %00011111,%11111000   ; ...##########...
        db      %00000111,%11100000   ; .....######.....
        db      %00000000,%00000000   ; ................

blk_diamond0:  ; Diamant, Phase 0
        db      045h,045h,045h,045h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00011111,%11111000   ; ...##########...
        db      %00111111,%11111100   ; ..############..
        db      %01111110,%01111110   ; .######..######.
        db      %11111111,%11111111   ; ################
        db      %11111111,%11111111   ; ################
        db      %01111110,%01111110   ; .######..######.
        db      %00111110,%01111100   ; ..#####..#####..
        db      %00011110,%01111000   ; ...####..####...
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00000011,%11000000   ; ......####......
        db      %00000001,%10000000   ; .......##.......
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................

blk_diamond1:  ; Diamant, Phase 1 (Funkeln)
        db      047h,047h,047h,047h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00011111,%11111000   ; ...##########...
        db      %00111111,%11111100   ; ..############..
        db      %01100111,%11100110   ; .##..######..##.
        db      %11111111,%11111111   ; ################
        db      %11011111,%11111011   ; ##.##########.##
        db      %01100111,%11100110   ; .##..######..##.
        db      %00110011,%11001100   ; ..##..####..##..
        db      %00011001,%10011000   ; ...##..##..##...
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00000011,%11000000   ; ......####......
        db      %00000001,%10000000   ; .......##.......
        db      %00000000,%00000000   ; ................
        db      %00000000,%00000000   ; ................

blk_rockford:  ; Rockford
        db      046h,046h,047h,047h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001111,%11110000   ; ....########....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00000011,%11000000   ; ......####......
        db      %00011111,%11111000   ; ...##########...
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00011110,%01111000   ; ...####..####...
        db      %00000000,%00000000   ; ................

blk_exit:  ; Ausgang (FLASH-Attribut blinkt)
        db      0C5h,0C5h,0C5h,0C5h
        db      %11111111,%11111111   ; ################
        db      %10000000,%00000001   ; #..............#
        db      %10111111,%11111101   ; #.############.#
        db      %10100000,%00000101   ; #.#..........#.#
        db      %10101111,%11110101   ; #.#.########.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101000,%00010101   ; #.#.#......#.#.#
        db      %10101111,%11110101   ; #.#.########.#.#
        db      %10100000,%00000101   ; #.#..........#.#
        db      %10111111,%11111101   ; #.############.#
        db      %10000000,%00000001   ; #..............#
        db      %11111111,%11111111   ; ################

; ---------- Variablen ----------
seed:           dw      SEED_START
tick_count:     dw      0
frame_ctr:      db      0
anim_phase:     db      0
dirty_count:    db      0
dirty_overflow: db      0
input_latch:    db      0
cam_x:          db      0
cam_y:          db      0
tmp_tile:       db      0
dirty_list:     ds      DIRTY_MAX*2
cave:           ds      CAVE_SIZE

        end     start
