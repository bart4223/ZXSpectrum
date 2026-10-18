; ============================================================
;  BOULDER DASH fuer ZX Spectrum  -  Stufe 0: Fundament
;  Assembler: pasmo   ->   pasmo --tapbas boulderdash.asm boulderdash.tap
;
;  Inhalt dieser Stufe:
;   - Hoehle als Byte-Array (32 x 22 Felder, Tile-IDs)
;   - Tile-Renderer (8x8 Pixel, ein Attribut pro Feld -> kein Clash)
;   - Dirty-Liste: nur geaenderte Felder werden neu gezeichnet
;   - fester Spieltakt: HALT = 50 Hz, Logik-Tick alle 6 Frames (~8 Hz)
;   - Testhoehle per Zufallsgenerator mit festem Seed (wie im Original)
;   - Demo: Diamanten funkeln (Animationsphase), Tick-Zaehler oben
;   - SPACE beendet und kehrt zu BASIC zurueck
; ============================================================

        org     32768

; ---------- Konstanten ----------
CAVE_W          equ     32
CAVE_H          equ     22
CAVE_SIZE       equ     CAVE_W*CAVE_H   ; 704 = 02C0h
CAVE_TOP        equ     2               ; Hoehle beginnt in Bildschirmzeile 2
ATTR_CAVE       equ     5800h+CAVE_TOP*32
FRAMES_PER_TICK equ     6
DIRTY_MAX       equ     200
SEED_START      equ     0ACE1h
CHAN_OPEN       equ     1601h

; Tile-IDs
T_EMPTY         equ     0
T_DIRT          equ     1
T_BRICK         equ     2
T_STEEL         equ     3
T_STONE         equ     4
T_DIAMOND       equ     5
T_ROCKFORD      equ     6
T_EXIT          equ     7

; ============================================================
start:
        xor     a
        out     (0FEh),a                ; Rand schwarz
        ld      (frame_ctr),a
        ld      (anim_phase),a
        ld      (dirty_count),a
        ld      (dirty_overflow),a
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
        call    draw_all

main_loop:
        halt                            ; auf Bildstrahl-Ruecklauf warten
        call    flush_dirty             ; zuerst zeichnen (wenig Flackern)

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
        ret                             ; zurueck zu BASIC

; ============================================================
;  Spiellogik (Stufe 0: nur Animation + Zaehler)
; ============================================================
game_tick:
        ld      a,(anim_phase)
        xor     1
        ld      (anim_phase),a

        ; alle Diamanten als "dirty" markieren, damit sie funkeln
        ld      hl,0                    ; HL = Feldindex
gt_loop:
        push    hl
        ld      de,cave
        add     hl,de
        ld      a,(hl)
        pop     hl
        cp      T_DIAMOND
        call    z,mark_dirty
        inc     hl
        ld      a,l
        cp      0C0h                    ; Ende bei Index 704 = 02C0h
        jr      nz,gt_loop
        ld      a,h
        cp      02h
        jr      nz,gt_loop

        ld      hl,(tick_count)
        inc     hl
        ld      (tick_count),hl
        ld      hl,txt_tickpos
        call    print_str
        ld      hl,(tick_count)
        call    print_num
        ret

; ============================================================
;  Dirty-Liste
; ============================================================
; mark_dirty: HL = Feldindex. HL bleibt erhalten, A/BC/DE veraendert.
mark_dirty:
        ld      a,(dirty_count)
        cp      DIRTY_MAX
        jr      nc,md_full
        push    hl
        ex      de,hl                   ; DE = Index
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      bc,dirty_list
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     a
        ld      (dirty_count),a
        pop     hl
        ret
md_full:
        ld      a,1                     ; Liste voll -> naechster Frame
        ld      (dirty_overflow),a      ; zeichnet einfach alles neu
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
        ex      de,hl
        call    draw_cell
        pop     hl
        pop     bc
        djnz    fd_loop
        xor     a
        ld      (dirty_count),a
        ret
fd_full:
        call    draw_all
        xor     a
        ld      (dirty_count),a
        ld      (dirty_overflow),a
        ret

; ============================================================
;  Renderer
; ============================================================
draw_all:
        ld      hl,0
da_loop:
        push    hl
        call    draw_cell
        pop     hl
        inc     hl
        ld      a,l
        cp      0C0h
        jr      nz,da_loop
        ld      a,h
        cp      02h
        jr      nz,da_loop
        ret

; draw_cell: HL = Feldindex (0..703). Veraendert alle Register ausser IX/IY.
draw_cell:
        push    hl
        ld      de,cave
        add     hl,de
        ld      c,(hl)                  ; C = Tile-ID
        pop     hl
        push    hl

        ; --- Attribut: ATTR_CAVE + Index ---
        ld      de,ATTR_CAVE
        add     hl,de
        ex      de,hl                   ; DE = Attributadresse
        ld      hl,tile_attr
        ld      b,0
        add     hl,bc
        ld      a,(hl)
        ld      (de),a

        ; --- Grafik: tile_gfx + (Tile*2 + Phase)*8 ---
        ld      a,c
        add     a,a
        ld      hl,anim_phase
        or      (hl)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,tile_gfx
        add     hl,de
        ex      de,hl                   ; DE = Grafikquelle

        ; --- Bildschirmadresse aus Index ---
        pop     hl                      ; HL = Index
        ld      a,l
        and     31
        ld      c,a                     ; C = Spalte
        ld      a,l
        rlca
        rlca
        rlca
        and     7
        ld      b,a                     ; B = Bits 7..5 von L
        ld      a,h
        add     a,a
        add     a,a
        add     a,a
        add     a,b
        add     a,CAVE_TOP              ; A = Bildschirmzeile 0..23
        ld      b,a
        and     18h
        or      40h
        ld      h,a                     ; H = 010rr000
        ld      a,b
        and     7
        rrca
        rrca
        rrca
        or      c
        ld      l,a                     ; L = rrrccccc

        ld      b,8
dc_loop:
        ld      a,(de)
        ld      (hl),a
        inc     de
        inc     h                       ; naechste Pixelzeile
        djnz    dc_loop
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
        cp      18
        jr      nc,gc_a
        ld      d,T_STONE
        jr      gc_store
gc_a:   cp      28
        jr      nc,gc_b
        ld      d,T_DIAMOND
        jr      gc_store
gc_b:   cp      38
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

        ; zwei Ziegelmauern
        ld      hl,cave+7*CAVE_W+1
        ld      b,20
gc_w1:  ld      (hl),T_BRICK
        inc     hl
        djnz    gc_w1
        ld      hl,cave+14*CAVE_W+11
        ld      b,20
gc_w2:  ld      (hl),T_BRICK
        inc     hl
        djnz    gc_w2

        ; Rockford und Ausgang
        ld      a,T_ROCKFORD
        ld      (cave+1*CAVE_W+2),a
        ld      a,T_EXIT
        ld      (cave+19*CAVE_W+31),a
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
        db      22,1,21
        db      "SPACE=ENDE"
        db      0FFh
txt_tickpos:
        db      22,1,6, 16,5, 17,0, 19,1, 0FFh

; Attribut je Tile: FLASH(80h) BRIGHT(40h) PAPER*8 INK
tile_attr:
        db      00h     ; EMPTY    schwarz
        db      06h     ; DIRT     gelb (ocker)
        db      42h     ; BRICK    hellrot
        db      05h     ; STEEL    cyan
        db      07h     ; STONE    grau
        db      45h     ; DIAMOND  hellcyan
        db      47h     ; ROCKFORD hellweiss
        db      85h     ; EXIT     cyan, blinkend

; Grafik je Tile: Phase 0 (8 Byte), Phase 1 (8 Byte)
tile_gfx:
        ; EMPTY
        db      0,0,0,0,0,0,0,0
        db      0,0,0,0,0,0,0,0
        ; DIRT
        db      88h,22h,88h,22h,88h,22h,88h,22h
        db      88h,22h,88h,22h,88h,22h,88h,22h
        ; BRICK
        db      0EEh,0EEh,0EEh,00h,0BBh,0BBh,0BBh,00h
        db      0EEh,0EEh,0EEh,00h,0BBh,0BBh,0BBh,00h
        ; STEEL
        db      7Eh,81h,0A5h,81h,81h,0A5h,81h,7Eh
        db      7Eh,81h,0A5h,81h,81h,0A5h,81h,7Eh
        ; STONE
        db      3Ch,5Eh,0BFh,0FFh,0FFh,0FFh,7Eh,3Ch
        db      3Ch,5Eh,0BFh,0FFh,0FFh,0FFh,7Eh,3Ch
        ; DIAMOND (Phase 1 = Funkeln)
        db      18h,3Ch,7Eh,0FFh,7Eh,3Ch,18h,00h
        db      18h,24h,5Ah,0BDh,5Ah,24h,18h,00h
        ; ROCKFORD
        db      18h,18h,3Ch,5Ah,18h,24h,24h,66h
        db      18h,18h,3Ch,5Ah,18h,24h,24h,66h
        ; EXIT
        db      7Eh,81h,0A5h,81h,81h,0A5h,81h,7Eh
        db      7Eh,81h,0A5h,81h,81h,0A5h,81h,7Eh

; ---------- Variablen ----------
seed:           dw      SEED_START
tick_count:     dw      0
frame_ctr:      db      0
anim_phase:     db      0
dirty_count:    db      0
dirty_overflow: db      0
dirty_list:     ds      DIRTY_MAX*2
cave:           ds      CAVE_SIZE

        end     start
