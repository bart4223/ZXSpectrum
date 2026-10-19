; ============================================================
;  BOULDER DASH fuer ZX Spectrum  -  Stufe 1: Rockford laeuft
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
;   - Scrollen in Kachelschritten; der Viewport wird gegen einen
;     Shadow-Puffer (was steht auf dem Schirm) verglichen, es werden
;     nur Kacheln gezeichnet, die sich wirklich geaendert haben
;   - Die Kamera folgt Rockford: ausserhalb einer Randzone rueckt der
;     Viewport um ein Feld nach (follow_camera)
;   - fester Spieltakt: HALT = 50 Hz, Logik-Tick alle 6 Frames
;   - Rockford laeuft pro Tick ein Feld durch leere Felder und Erde (graebt)
;     und sammelt Diamanten; Steine, Mauern und Stahl blockieren noch
;   - Leerlauf: nach einigen Ticks Stillstand blinzelt Rockford und
;     stampft mit dem linken Fuss auf
;   - Diamanten funkeln
;
;  Steuerung:  Q=hoch  A=runter  O=links  P=rechts
;              oder Sinclair-Joystick 1 (Tasten 6-0)
;              oder Sinclair-Joystick 2 (Tasten 1-5)
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
CAM_MARGIN_X    equ     5               ; Randzone: so nah darf Rockford am
CAM_MARGIN_Y    equ     3               ; Viewportrand sein, bevor die Kamera folgt
IDLE_DELAY      equ     8               ; Ticks Stillstand bis zur Leerlauf-Animation
MAX_DIAMONDS    equ     99
ROCK_START_X    equ     2
ROCK_START_Y    equ     1
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
T_ROCKFORD_UP   equ     7               ; linker Fuss angehoben
T_ROCKFORD_STOMP equ    8               ; Fuss aufgesetzt
T_ROCKFORD_BLINK equ    9               ; Augen zu
T_ROCKFORD_WALK equ     10              ; Schrittstellung
T_EXIT          equ     11

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
        xor     a
        ld      (rock_step),a
        ld      (diamonds),a
        ld      (rock_walk),a
        ld      a,IDLE_DELAY            ; Leerlauf-Animation laeuft von Anfang an
        ld      (rock_idle),a
        ld      a,ROCK_START_X
        ld      (rock_x),a
        ld      a,ROCK_START_Y
        ld      (rock_y),a
        ld      hl,shadow               ; Shadow-Puffer: 0FFh = noch nichts gezeichnet
        ld      de,shadow+1
        ld      bc,VIEW_W*VIEW_H-1
        ld      (hl),0FFh
        ldir
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
        call    scan_input              ; Eingabe merken

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
;  Spiellogik (Stufe 1: Rockford laeuft)
; ============================================================
game_tick:
        ld      a,(anim_phase)
        xor     1
        ld      (anim_phase),a
        call    move_rockford           ; NZ = Rockford hat sich bewegt
        jr      z,gt_idle
        call    follow_camera           ; NZ = Viewport wurde neu gezeichnet
        jr      nz,gt_stats             ; (dann ist auch das Funkeln erledigt)
        jr      gt_sparkle
gt_idle:
        call    animate_rockford        ; steht still: Leerlauf-Animation

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
;  Rockford
; ============================================================
; move_rockford: holt die gemerkte Eingabe und versucht, Rockford um ein Feld
; zu bewegen (Prioritaet: links, rechts, hoch, runter). Betretbar sind leere
; Felder, Erde (wird weggegraben) und Diamanten (werden eingesammelt).
; Steine, Mauern, Stahl und Ausgang blockieren (Stufe 2/3 erweitern das).
; Rueckgabe: NZ = Rockford hat sich bewegt, Z = nicht.
move_rockford:
        ld      a,(input_latch)
        ld      c,a
        xor     a
        ld      (input_latch),a
        ld      a,(rock_x)
        ld      e,a                     ; E = x
        ld      a,(rock_y)
        ld      d,a                     ; D = y
        bit     0,c                     ; links
        jr      z,mr_r
        dec     e
        jr      mr_try
mr_r:   bit     1,c                     ; rechts
        jr      z,mr_u
        inc     e
        jr      mr_try
mr_u:   bit     2,c                     ; hoch
        jr      z,mr_d
        dec     d
        jr      mr_try
mr_d:   bit     3,c                     ; runter
        ret     z                       ; keine Eingabe: Z = nicht bewegt
        inc     d
mr_try:                                 ; (E,D) = Zielfeld
        push    de
        call    cave_addr               ; HL = Zielzelle (zerstoert BC, DE)
        ld      a,(hl)
        or      a                       ; T_EMPTY = 0
        jr      z,mr_go
        cp      T_DIRT
        jr      z,mr_go
        cp      T_DIAMOND
        jr      nz,mr_blocked
        ld      a,(diamonds)            ; Diamant einsammeln
        cp      MAX_DIAMONDS
        jr      nc,mr_go
        inc     a
        ld      (diamonds),a
mr_go:  ld      a,(rock_walk)           ; Schrittanimation: abwechselnd stehen/gehen
        xor     1
        ld      (rock_walk),a
        ld      a,T_ROCKFORD
        jr      z,mr_t
        ld      a,T_ROCKFORD_WALK
mr_t:   ld      (hl),a                  ; Rockford steht jetzt im Zielfeld
        pop     de                      ; DE = Ziel (x in E, y in D)
        ld      a,(rock_x)
        ld      c,a                     ; C = alte x
        ld      a,(rock_y)
        ld      b,a                     ; B = alte y
        ld      a,e
        ld      (rock_x),a
        ld      a,d
        ld      (rock_y),a
        call    mark_dirty              ; Zielfeld neu zeichnen
        ld      d,b
        ld      e,c                     ; DE = alte Position
        push    de
        call    cave_addr
        ld      (hl),T_EMPTY            ; altes Feld ist leer
        pop     de
        call    mark_dirty
        xor     a
        ld      (rock_idle),a           ; Leerlauf-Animation beginnt von vorn
        ld      (rock_step),a
        inc     a                       ; NZ = bewegt
        ret
mr_blocked:
        pop     de
        xor     a                       ; Z = nicht bewegt
        ret

; follow_camera: Kamera folgt Rockford. Ausserhalb der Randzone (CAM_MARGIN_X/Y)
; rueckt der Viewport um ein Feld nach. Danach wird er per Shadow-Vergleich neu
; gezeichnet. Rueckgabe: NZ = Viewport wurde neu gezeichnet.
follow_camera:
        ld      c,0                     ; C = Anzahl Kamerabewegungen
        ld      a,(rock_x)
        ld      hl,cam_x
        sub     (hl)                    ; A = Spalte Rockfords im Viewport
        cp      CAM_MARGIN_X
        jr      nc,fc_xr
        ld      a,(hl)                  ; zu weit links
        or      a
        jr      z,fc_y
        dec     (hl)
        inc     c
        jr      fc_y
fc_xr:  cp      VIEW_W-CAM_MARGIN_X
        jr      c,fc_y
        ld      a,(hl)                  ; zu weit rechts
        cp      CAM_MAX_X
        jr      nc,fc_y
        inc     (hl)
        inc     c
fc_y:   ld      a,(rock_y)
        ld      hl,cam_y
        sub     (hl)                    ; A = Zeile Rockfords im Viewport
        cp      CAM_MARGIN_Y
        jr      nc,fc_yd
        ld      a,(hl)                  ; zu weit oben
        or      a
        jr      z,fc_done
        dec     (hl)
        inc     c
        jr      fc_done
fc_yd:  cp      VIEW_H-CAM_MARGIN_Y
        jr      c,fc_done
        ld      a,(hl)                  ; zu weit unten
        cp      CAM_MAX_Y
        jr      nc,fc_done
        inc     (hl)
        inc     c
fc_done:
        ld      a,c
        or      a
        ret     z                       ; Kamera steht still: Z
        call    draw_view
        xor     a                       ; Dirty-Liste erledigt (Shadow-Vergleich)
        ld      (dirty_count),a
        ld      (dirty_overflow),a
        inc     a                       ; NZ = neu gezeichnet
        ret

; animate_rockford: Leerlauf-Animation, wird in Ticks ohne Bewegung aufgerufen.
; Zuerst steht Rockford IDLE_DELAY Ticks still, dann laeuft rock_pattern (ein
; Eintrag je Tick). Weicht die Kachel an Rockfords Position von der gewuenschten
; ab, wird sie getauscht und das Feld als "dirty" markiert.
animate_rockford:
        ld      a,(rock_idle)
        cp      IDLE_DELAY
        jr      nc,ar_pat
        inc     a
        ld      (rock_idle),a
        ld      a,T_ROCKFORD            ; kurz nach dem Laufen: einfach stehen
        jr      ar_apply
ar_pat: ld      a,(rock_step)
        inc     a
        cp      rock_pattern_end-rock_pattern
        jr      c,ar_ok
        xor     a
ar_ok:  ld      (rock_step),a
        ld      e,a
        ld      d,0
        ld      hl,rock_pattern
        add     hl,de
        ld      a,(hl)                  ; A = gewuenschte Kachel
ar_apply:
        push    af
        ld      a,(rock_y)
        ld      d,a
        ld      a,(rock_x)
        ld      e,a
        push    de
        call    cave_addr               ; HL = Zelle Rockfords
        pop     de                      ; DE = (x,y) fuer mark_dirty
        pop     af
        ld      c,a                     ; C = gewuenschte Kachel
        ld      a,(hl)
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        ret     nc                      ; dort steht kein Rockford: nichts tun
        ld      a,(hl)
        cp      c
        ret     z                       ; schon richtig
        ld      (hl),c
        jp      mark_dirty

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
        jr      nz,ri_s2
        set     2,c
ri_s2:  ld      a,0F7h                  ; Sinclair 2: 1=links 2=rechts 3=runter 4=hoch
        in      a,(0FEh)
        ld      b,a
        bit     0,b
        jr      nz,ri_s2b
        set     0,c
ri_s2b: bit     1,b
        jr      nz,ri_s2c
        set     1,c
ri_s2c: bit     2,b
        jr      nz,ri_s2d
        set     3,c
ri_s2d: bit     3,b
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
; draw_view: bringt den Viewport auf den Stand der Hoehle. Pro Feld wird der
; Frame-Schluessel mit dem Shadow-Puffer verglichen; nur bei Abweichung wird
; gezeichnet (draw_tile aktualisiert den Puffer). Dadurch ist Scrollen ueber
; gleichfoermige Flaechen (Erde!) fast kostenlos.
draw_view:
        ld      a,(cam_y)
        ld      d,a
        ld      a,(cam_x)
        ld      e,a
        call    cave_addr               ; HL = Zeiger auf (cam_x,cam_y)
        ld      ix,shadow
        ld      c,0                     ; C = ty
dv_row:
        push    hl                      ; Zeilenanfang merken
        ld      b,0                     ; B = tx
dv_col:
        ld      a,(hl)                  ; Tile
        add     a,a
        ld      e,a
        ld      a,(anim_phase)
        or      e                       ; A = Frame = Tile*2 + Phase
        ld      e,a
        ld      d,0
        push    hl
        ld      hl,frame_key
        add     hl,de
        ld      a,(hl)                  ; A = Schluessel (gleiche Grafik = gleicher Schluessel)
        pop     hl
        cp      (ix+0)
        jr      z,dv_next               ; steht schon richtig auf dem Schirm
        push    bc
        push    hl
        ld      a,(hl)
        call    draw_tile
        pop     hl
        pop     bc
dv_next:
        inc     hl
        inc     ix
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
        add     a,a
        ld      hl,anim_phase
        or      (hl)                    ; A = Frame = Tile*2 + Phase
        ld      (tmp_frame),a

        ; --- Shadow-Puffer: shadow[ty*16 + tx] = frame_key[Frame] ---
        ld      e,a
        ld      d,0
        ld      hl,frame_key
        add     hl,de
        ld      e,(hl)                  ; E = Schluessel
        ld      a,c
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      b                       ; A = ty*16 + tx
        ld      l,a
        ld      h,0
        ld      a,e
        ld      de,shadow
        add     hl,de
        ld      (hl),a

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

        ; --- Frame-Block: frame_table[Frame] ---
        ld      a,(tmp_frame)
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
        rept    8                       ; 8 Pixelzeilen entrollt (kein DJNZ)
        ld      a,(de)                  ; linkes Byte
        ld      (hl),a
        inc     de
        inc     l
        ld      a,(de)                  ; rechtes Byte
        ld      (hl),a
        inc     de
        dec     l
        inc     h                       ; naechste Pixelzeile
        endm
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
        ld      (cave+ROCK_START_Y*CAVE_W+ROCK_START_X),a
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

; print_status: Ticks und Diamanten in die Kopfzeile
print_status:
        ld      hl,txt_tickpos
        call    print_str
        ld      hl,(tick_count)
        call    print_num
        ld      hl,txt_diapos
        call    print_str
        ld      a,(diamonds)
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
        db      "BOULDER DASH  -  STUFE 1"
        db      22,1,0, 16,7, 17,0, 19,0
        db      "TICKS"
        db      22,1,12
        db      "DIA:"
        db      22,1,21
        db      "SPACE=ENDE"
        db      0FFh
txt_tickpos:
        db      22,1,6, 16,5, 17,0, 19,1, 0FFh
txt_diapos:
        db      22,1,16, 16,5, 17,0, 19,1, 0FFh

; Frame-Tabelle: je Tile zwei Eintraege (Phase 0 und Phase 1)
frame_table:
        dw      blk_empty,   blk_empty
        dw      blk_dirt,    blk_dirt
        dw      blk_brick,   blk_brick
        dw      blk_steel,   blk_steel
        dw      blk_stone,   blk_stone
        dw      blk_diamond0,blk_diamond1
        dw      blk_rockford,blk_rockford
        dw      blk_rockford_up,blk_rockford_up
        dw      blk_rockford_stomp,blk_rockford_stomp
        dw      blk_rockford_blink,blk_rockford_blink
        dw      blk_rockford_walk,blk_rockford_walk
        dw      blk_exit,    blk_exit

; Schluessel je Frame fuer den Shadow-Puffer: Frames mit identischer Grafik
; (alle ausser den animierten) bekommen denselben Schluessel, damit ein
; Phasenwechsel nicht ueberall ein Neuzeichnen ausloest.
frame_key:
        db      0,0, 2,2, 4,4, 6,6, 8,8, 10,11, 12,12, 14,14, 16,16, 18,18, 20,20, 22,22

; Leerlauf-Animation Rockford: ein Eintrag je Tick (6 Frames = ca. 0,12 s).
; Beliebig aenderbar; die Laenge ergibt sich aus den Labels.
rock_pattern:
        db      T_ROCKFORD, T_ROCKFORD, T_ROCKFORD, T_ROCKFORD       ; steht
        db      T_ROCKFORD_BLINK, T_ROCKFORD, T_ROCKFORD, T_ROCKFORD ; blinzelt
        db      T_ROCKFORD_UP, T_ROCKFORD_STOMP                      ; Fuss hoch, Stampf
        db      T_ROCKFORD_UP, T_ROCKFORD_STOMP                      ; nochmal
        db      T_ROCKFORD, T_ROCKFORD, T_ROCKFORD, T_ROCKFORD       ; steht
        db      T_ROCKFORD, T_ROCKFORD_BLINK, T_ROCKFORD, T_ROCKFORD ; blinzelt
rock_pattern_end:

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
        db      046h,046h,041h,041h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001111,%11110000   ; ....########....
        db      %00001111,%11110000   ; ....########....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00011110,%01111000   ; ...####..####...
        db      %00000000,%00000000   ; ................

blk_rockford_up:  ; Rockford, linker Fuss angehoben
        db      046h,046h,041h,041h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001111,%11110000   ; ....########....
        db      %00001111,%11110000   ; ....########....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01111000   ; ....###..####...
        db      %00001110,%00000000   ; ....###.........
        db      %00011110,%00000000   ; ...####.........
        db      %00000000,%00000000   ; ................

blk_rockford_stomp:  ; Rockford, Fuss aufgesetzt (Stosslinien)
        db      046h,046h,041h,041h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001111,%11110000   ; ....########....
        db      %00001111,%11110000   ; ....########....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110010   ; ....###..###..#.
        db      %00001110,%01110001   ; ....###..###...#
        db      %00001110,%01110010   ; ....###..###..#.
        db      %00011110,%01111001   ; ...####..####..#
        db      %00000000,%00000000   ; ................

blk_rockford_blink:  ; Rockford, Augen zu (blinzelt)
        db      046h,046h,041h,041h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001111,%11110000   ; ....########....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001111,%11110000   ; ....########....
        db      %00001111,%11110000   ; ....########....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00001110,%01110000   ; ....###..###....
        db      %00011110,%01111000   ; ...####..####...
        db      %00000000,%00000000   ; ................

blk_rockford_walk:  ; Rockford, Schrittstellung
        db      046h,046h,041h,041h
        db      %00000000,%00000000   ; ................
        db      %00000111,%11100000   ; .....######.....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001101,%10110000   ; ....##.##.##....
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00111111,%11111100   ; ..############..
        db      %00101111,%11110100   ; ..#.########.#..
        db      %00001111,%11110000   ; ....########....
        db      %00001111,%11110000   ; ....########....
        db      %00001110,%01110000   ; ....###..###....
        db      %00011100,%00111000   ; ...###....###...
        db      %00111000,%00011100   ; ..###......###..
        db      %00111000,%00011100   ; ..###......###..
        db      %01111000,%00011110   ; .####......####.
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
tmp_frame:      db      0
diamonds:       db      0
rock_idle:      db      0
rock_walk:      db      0
rock_x:         db      0
rock_y:         db      0
rock_step:      db      0
shadow:         ds      VIEW_W*VIEW_H
dirty_list:     ds      DIRTY_MAX*2
cave:           ds      CAVE_SIZE

        end     start
