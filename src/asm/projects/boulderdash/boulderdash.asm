; ============================================================
;  BOULDER DASH fuer ZX Spectrum  -  Stufe 4: Gegner und Explosionen
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
;     und sammelt Diamanten; Mauern und Stahl blockieren
;   - Physik (physics): Steine und Diamanten fallen, wenn darunter frei ist,
;     und rollen von runden Dingen (Stein, Diamant, Ziegel) nach links/rechts
;   - Rockford schiebt Steine seitlich, wenn dahinter frei ist; ein Stein ist
;     schwer: erst im zweiten Tick des Drueckens bewegt er sich
;   - Ein fallender Stein oder Diamant zerquetscht Rockford (Explosion)
;   - Spielziel: genug Diamanten sammeln (Quote), dann oeffnet sich der
;     blinkende Ausgang; hineinlaufen = Level geschafft (Zeitbonus, naechstes
;     Level mit hoeherer Quote). 10 Punkte je Diamant.
;   - Zeit: laeuft sie ab, explodiert Rockford. 3 Leben, dann GAME OVER.
;   - Gegner: Gluehwuermchen (halten sich links an der Wand) und Schmetterlinge
;     (rechts). Beruehren sie Rockford, explodieren sie und reissen ihn mit.
;     Ein fallender Stein/Diamant auf einen Gegner loest ebenfalls die
;     Explosion aus: Gluehwuermchen -> 3x3 leer, Schmetterling -> 3x3 Diamanten.
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
FRAMES          equ     5C78h           ; ROM-Systemvariable: Bildzaehler
START_LIVES     equ     3
TIME_START      equ     150             ; Spielsekunden je Level
TICKS_PER_SEC   equ     8               ; Ticks je Spielsekunde (~8,3 Hz)
WIN_TICKS       equ     12              ; Pause nach dem Ausgang
OVER_TICKS      equ     24              ; Pause bei GAME OVER
EXIT_X          equ     38              ; Position des Ausgangs
EXIT_Y          equ     20
NEED_BASE       equ     10              ; Quote Level 1
NEED_STEP       equ     2               ; mehr je Level
NEED_MAX        equ     30
DIA_SCORE       equ     10

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
T_STONE_F       equ     12              ; fallender Stein (Grafik wie Stein)
T_DIAMOND_F     equ     13              ; fallender Diamant
T_FIREFLY       equ     16              ; Gluehwuermchen 16..23, Schmetterling 24..31
T_BUTTERFLY     equ     24              ;   Kachel = Typ + 4*Paritaet + Richtung (0 hoch,
                                        ;   1 rechts, 2 runter, 3 links)
T_EXPLODE       equ     32              ; Explosion 32..35 (danach leer)
T_DEXPLODE      equ     36              ; Diamant-Explosion 36..39 (danach Diamant)
DEAD_TICKS      equ     16              ; Explosionsdauer bis zum Neustart
T_EXIT_OFF      equ     15              ; geschlossener Ausgang (sieht aus wie Stahl)

; Eingabe-Bits
IN_LEFT         equ     1
IN_RIGHT        equ     2
IN_UP           equ     4
IN_DOWN         equ     8

; ============================================================
start:
        ld      a,START_LIVES
        ld      (lives),a
        ld      a,1
        ld      (level),a
        ld      hl,0
        ld      (score),hl
new_level:                              ; (Neu-)Start des aktuellen Levels
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
        ld      (dead),a
        ld      (win),a
        ld      (over),a
        ld      (par),a
        ld      (push_cnt),a
        ld      (push_prev),a
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
        ld      a,TIME_START
        ld      (time),a
        ld      a,TICKS_PER_SEC
        ld      (time_sub),a
        ld      a,(level)               ; Quote: NEED_BASE + NEED_STEP*(level-1)
        dec     a
        add     a,a
        add     a,NEED_BASE
        cp      NEED_MAX+1
        jr      c,nl_need
        ld      a,NEED_MAX
nl_need:ld      (need),a
        ld      hl,SEED_START           ; Hoehle je Level, aber reproduzierbar
        ld      a,(level)
        dec     a
        jr      z,nl_seed
        ld      b,a
        ld      de,1357h
nl_sl:  add     hl,de
        djnz    nl_sl
nl_seed:ld      (seed),hl

        call    clear_screen
        ld      a,2
        call    CHAN_OPEN               ; ROM-Ausgabe auf oberen Bildschirm
        ld      hl,txt_header
        call    print_str

        call    gen_cave
        call    draw_view
        call    print_all
        ld      a,(FRAMES)
        ld      (frame_ctr),a           ; Tick-Takt beginnt jetzt

main_loop:
        halt                            ; auf Bildstrahl-Ruecklauf warten
        call    flush_dirty             ; zuerst zeichnen (wenig Flackern)
        call    scan_input              ; Eingabe merken

        ld      a,(FRAMES)              ; ROM-Zaehler (50 Hz, niedriges Byte)
        ld      hl,frame_ctr            ; Zeitstempel des letzten Ticks
        sub     (hl)
        cp      FRAMES_PER_TICK
        jr      c,ml_keys
        ld      a,(hl)
        add     a,FRAMES_PER_TICK       ; Stempel um genau einen Tick weiter:
        ld      (hl),a                  ; feste Tickrate, auch wenn ein Tick laenger dauert
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
;  Spiellogik (Stufe 4: Gegner und Explosionen)
; ============================================================
game_tick:
        ld      a,(anim_phase)
        xor     1
        ld      (anim_phase),a
        ld      a,(over)
        or      a
        jr      nz,gt_over
        ld      a,(dead)
        or      a
        jr      nz,gt_dying
        ld      a,(win)
        or      a
        jr      nz,gt_win
        call    move_rockford           ; NZ = Rockford hat sich bewegt
        push    af
        call    physics                 ; Steine und Diamanten bewegen sich
        call    game_time               ; Zeit laeuft
        pop     af
        jr      z,gt_idle
        call    follow_camera           ; NZ = Viewport wurde neu gezeichnet
        jp      nz,gt_stats             ; (dann ist auch das Funkeln erledigt)
        jr      gt_sparkle
gt_idle:
        call    animate_rockford        ; steht still: Leerlauf-Animation
        jr      gt_sparkle
gt_dying:                               ; Rockford ist zerquetscht: Explosion laeuft
        call    physics
        ld      hl,dead
        dec     (hl)
        jr      nz,gt_sparkle
        ld      hl,lives                ; Explosion vorbei: ein Leben weniger
        dec     (hl)
        jr      z,gt_gameover
        pop     hl                      ; Ruecksprung nach main_loop verwerfen
        jp      new_level               ; gleiche Hoehle nochmal
gt_gameover:
        ld      a,OVER_TICKS
        ld      (over),a
        ld      hl,txt_over
        call    print_str
        jr      gt_sparkle
gt_over:                                ; GAME OVER steht, dann komplett neu
        dec     a
        ld      (over),a
        jr      nz,gt_sparkle
        pop     hl
        jp      start
gt_win:                                 ; Ausgang erreicht: kurze Pause, dann Bonus
        dec     a
        ld      (win),a
        jr      nz,gt_sparkle
        ld      a,(time)                ; Zeitbonus: 5 Punkte je Restsekunde
        ld      e,a
        ld      d,0
        ld      h,d
        ld      l,e
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,(score)
        add     hl,de
        ld      (score),hl
        ld      hl,level
        inc     (hl)
        pop     hl
        jp      new_level

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
        and     0F7h                    ; fallender Diamant (13) -> 5
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
        ret

; game_time: Spielsekunden herunterzaehlen; bei 0 explodiert Rockford.
game_time:
        ld      hl,time_sub
        dec     (hl)
        ret     nz
        ld      (hl),TICKS_PER_SEC
        ld      hl,time
        dec     (hl)
        call    print_time
        ld      a,(time)
        or      a
        ret     nz
        ld      a,(rock_y)              ; Zeit abgelaufen: Explosion um Rockford
        ld      d,a
        ld      a,(rock_x)
        ld      e,a
        push    de
        call    cave_addr
        pop     de
        ld      a,T_EXPLODE
        jp      explode_at

; ============================================================
;  Physik und Gegner
; ============================================================
; physics: ein Durchlauf ueber die Hoehle (Zeilen von unten nach oben, in jeder
; Zeile von links nach rechts), damit jedes Objekt pro Tick hoechstens ein Feld
; weit kommt. Betroffen:
;   Stein (4), Diamant (5) und ihre fallenden Formen (12, 13 = +8):
;   - darunter leer              -> faellt ein Feld (wird "fallend")
;   - fallend auf Rockford       -> zerquetscht ihn (Explosion)
;   - fallend auf einen Gegner   -> Gegner explodiert
;   - darunter Stein/Diamant/Ziegel (rund) -> rollt nach links, sonst rechts,
;     wenn das Feld daneben UND das Feld darunter daneben frei sind
;   - sonst: liegt still (fallend -> normal)
;   Gegner (16..31): Rockford daneben -> Explosion; sonst ein Schritt nach der
;   Wandregel (Gluehwuermchen: links, geradeaus, rechts drehen; Schmetterling
;   spiegelbildlich). Die Paritaet (Bit 2 der Kachel) verhindert, dass ein
;   Gegner im selben Tick zweimal zieht.
;   Explosionen (32..39) altern pro Tick; die letzte Stufe wird leer bzw. Diamant.
physics:
        ld      a,(par)                 ; Paritaet wechselt je Tick
        xor     4
        ld      (par),a
        ld      hl,cave+(CAVE_H-2)*CAVE_W+1
        ld      d,CAVE_H-2
ph_row: push    hl                      ; Zeilenanfang (x = 1)
        ld      e,1
ph_col: ld      a,(hl)
        cp      T_STONE
        jp      c,ph_next               ; 0..3: nichts
        cp      T_DIAMOND+1
        jr      c,ph_obj                ; 4, 5
        cp      T_STONE_F
        jp      c,ph_next               ; 6..11
        cp      T_DIAMOND_F+1
        jr      c,ph_obj                ; 12, 13
        cp      16
        jp      c,ph_next               ; 14, 15
        cp      32
        jp      c,ph_enemy              ; 16..31 Gegner
        cp      40
        jp      nc,ph_next
        ld      c,a                     ; 32..39 Explosion altert
        and     3
        cp      3
        jr      z,ph_xend
        inc     (hl)
        jp      ph_next
ph_xend:
        ld      a,c
        cp      T_DEXPLODE
        ld      a,T_EMPTY               ; Fluechtigkeit: ld aendert die Flags nicht
        jr      c,ph_xe
        ld      a,T_DIAMOND
ph_xe:  ld      (hl),a
        call    mark_dirty
        jp      ph_next

; ---- Steine und Diamanten ----
ph_obj: ld      c,a                     ; C = Kachel des Objekts
        push    hl
        pop     ix
        ld      a,(ix+CAVE_W)           ; Feld darunter
        or      a
        jr      z,ph_fall
        ld      b,a                     ; B = Kachel darunter
        bit     3,c
        jr      z,ph_nocrush            ; nur fallende Objekte treffen
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      c,ph_crush              ; auf Rockford
        ld      a,b
        and     0F0h
        cp      10h
        jr      nz,ph_nocrush           ; kein Gegner
        bit     3,b                     ; Gegner getroffen
        ld      a,T_EXPLODE
        jr      z,ph_hit
        ld      a,T_DEXPLODE
        jr      ph_hit
ph_crush:
        ld      a,T_EXPLODE
ph_hit: push    hl                      ; Explosion um das Feld darunter
        ld      bc,CAVE_W
        add     hl,bc
        inc     d
        call    explode_at
        dec     d
        pop     hl
        jp      ph_next
ph_nocrush:
        ld      a,b
        cp      T_BRICK
        jr      z,ph_round
        cp      T_STONE
        jr      z,ph_round
        cp      T_DIAMOND
        jr      nz,ph_land
ph_round:                               ; runde Unterlage: Rollen versuchen
        ld      a,(ix-1)
        or      a
        jr      nz,ph_right
        ld      a,(ix+CAVE_W-1)
        or      a
        jr      nz,ph_right
        ld      a,c                     ; nach links rollen
        or      8
        ld      (ix-1),a
        ld      (hl),T_EMPTY
        call    mark_dirty
        dec     e
        call    mark_dirty
        inc     e
        jp      ph_next
ph_right:
        ld      a,(ix+1)
        or      a
        jr      nz,ph_land
        ld      a,(ix+CAVE_W+1)
        or      a
        jr      nz,ph_land
        ld      a,c                     ; nach rechts rollen
        or      8
        ld      (ix+1),a
        ld      (hl),T_EMPTY
        call    mark_dirty
        inc     e
        call    mark_dirty
        inc     hl                      ; das Zielfeld nicht nochmal bearbeiten
        jp      ph_next
ph_land:
        ld      a,c                     ; liegt still: "fallend"-Bit loeschen
        and     0F7h                    ; (gleiche Grafik, kein Neuzeichnen noetig)
        ld      (hl),a
        jp      ph_next
ph_fall:
        ld      a,c
        or      8
        ld      (ix+CAVE_W),a
        ld      (hl),T_EMPTY
        call    mark_dirty
        inc     d
        call    mark_dirty
        dec     d
        jp      ph_next

; ---- Gegner ----
ph_enemy:
        ld      c,a                     ; C = Kachel
        ld      a,(par)
        ld      b,a
        ld      a,c
        and     4
        cp      b
        jp      z,ph_next               ; hat in diesem Tick schon gezogen
        push    hl
        pop     ix
        ld      a,(ix-CAVE_W)           ; Rockford direkt daneben?
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      c,ph_boom
        ld      a,(ix+CAVE_W)
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      c,ph_boom
        ld      a,(ix-1)
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      c,ph_boom
        ld      a,(ix+1)
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      c,ph_boom
        ld      a,c
        and     3
        ld      b,a                     ; B = Richtung
        ld      a,c
        and     18h
        ld      c,a                     ; C = Typ (10h Gluehwuermchen, 18h Schmetterling)
        ld      a,b
        bit     3,c
        jr      nz,pe_b1
        dec     a                       ; Gluehwuermchen: zuerst nach links
        jr      pe_t1
pe_b1:  inc     a                       ; Schmetterling: zuerst nach rechts
pe_t1:  and     3
        push    af
        call    nbr
        or      a
        jr      z,pe_go
        pop     af
        ld      a,b                     ; sonst geradeaus
        push    af
        call    nbr
        or      a
        jr      z,pe_go
        pop     af
        ld      a,b                     ; sonst auf der Stelle drehen
        bit     3,c
        jr      nz,pe_tb
        inc     a                       ; Gluehwuermchen dreht nach rechts
        jr      pe_ts
pe_tb:  dec     a                       ; Schmetterling nach links
pe_ts:  and     3
        or      c
        ld      c,a
        ld      a,(par)
        or      c
        ld      (hl),a
        call    mark_dirty
        jp      ph_next
pe_go:  pop     af                      ; A = neue Richtung
        ld      b,a
        or      c
        ld      c,a
        ld      a,(par)
        or      c
        ld      c,a                     ; C = neue Kachel
        ld      a,b
        call    nbr_wr
        ld      (hl),T_EMPTY
        call    mark_dirty
        ld      a,b
        call    nbr_dirty
        jp      ph_next
ph_boom:
        bit     3,c                     ; Typ steckt in Bit 3 der Original-Kachel
        ld      a,T_EXPLODE
        jr      z,pb_x
        ld      a,T_DEXPLODE
pb_x:   call    explode_at              ; Mitte = HL, (E,D)
        jp      ph_next

ph_next:
        inc     hl
        inc     e
        ld      a,e
        cp      CAVE_W-1
        jp      nz,ph_col
        pop     hl
        ld      bc,-CAVE_W
        add     hl,bc
        dec     d
        jp      nz,ph_row
        ret

; nbr: A = Richtung (0 hoch, 1 rechts, 2 runter, 3 links) -> A = Kachel dort
; (relativ zu IX = Gegnerfeld)
nbr:    or      a
        jr      z,nb_u
        dec     a
        jr      z,nb_r
        dec     a
        jr      z,nb_d
        ld      a,(ix-1)
        ret
nb_u:   ld      a,(ix-CAVE_W)
        ret
nb_r:   ld      a,(ix+1)
        ret
nb_d:   ld      a,(ix+CAVE_W)
        ret

; nbr_wr: schreibt C in das Nachbarfeld in Richtung A (relativ zu IX)
nbr_wr: or      a
        jr      z,nw_u
        dec     a
        jr      z,nw_r
        dec     a
        jr      z,nw_d
        ld      (ix-1),c
        ret
nw_u:   ld      (ix-CAVE_W),c
        ret
nw_r:   ld      (ix+1),c
        ret
nw_d:   ld      (ix+CAVE_W),c
        ret

; nbr_dirty: markiert das Nachbarfeld in Richtung A (E,D = Gegnerfeld) als dirty
nbr_dirty:
        or      a
        jr      z,nd_u
        dec     a
        jr      z,nd_r
        dec     a
        jr      z,nd_d
        dec     e
        call    mark_dirty
        inc     e
        ret
nd_u:   dec     d
        call    mark_dirty
        inc     d
        ret
nd_r:   inc     e
        call    mark_dirty
        dec     e
        ret
nd_d:   inc     d
        call    mark_dirty
        dec     d
        ret

; explode_at: A = erste Explosionskachel (T_EXPLODE / T_DEXPLODE), HL = Mitte,
; E = x, D = y. Der 3x3-Block um die Mitte wird zur Explosion (ausser Stahl und
; Ausgang). Liegt Rockford darin, ist er tot. Alle Register bleiben erhalten.
explode_at:
        ld      (ex_tile),a
        push    hl
        push    de
        push    bc
        ld      bc,-(CAVE_W+1)
        add     hl,bc                   ; Feld (x-1, y-1)
        dec     d
        dec     e
        ld      b,3                     ; 3 Zeilen
ex_row: push    hl
        push    de
        ld      c,3
ex_col: ld      a,(hl)
        cp      T_STEEL
        jr      z,ex_nx
        cp      T_EXIT
        jr      z,ex_nx
        cp      T_EXIT_OFF
        jr      z,ex_nx
        sub     T_ROCKFORD
        cp      T_ROCKFORD_WALK-T_ROCKFORD+1
        jr      nc,ex_set
        ld      a,DEAD_TICKS            ; Rockford liegt in der Explosion
        ld      (dead),a
ex_set: ld      a,(ex_tile)
        ld      (hl),a
        call    mark_dirty
ex_nx:  inc     hl
        inc     e
        dec     c
        jr      nz,ex_col
        pop     de
        pop     hl
        ld      a,l                     ; HL += CAVE_W
        add     a,CAVE_W
        ld      l,a
        jr      nc,ex_nc
        inc     h
ex_nc:  inc     d
        djnz    ex_row
        pop     bc
        pop     de
        pop     hl
        ret

; ============================================================
;  Rockford
; ============================================================
; move_rockford: holt die gemerkte Eingabe und versucht, Rockford um ein Feld
; zu bewegen (Prioritaet: links, rechts, hoch, runter). Betretbar sind leere
; Felder, Erde (wird weggegraben) und Diamanten (werden eingesammelt).
; Steine werden seitlich geschoben, wenn dahinter frei ist. Mauern, Stahl,
; geschlossener Ausgang und fallende Steine blockieren.
; Rueckgabe: NZ = Rockford hat sich bewegt, Z = nicht.
move_rockford:
        ld      a,(input_latch)
        ld      c,a
        xor     a
        ld      (input_latch),a
        ld      a,(push_cnt)            ; Schiebe-Zaehler: war im letzten Tick schon
        ld      (push_prev),a           ; ein Schiebeversuch? (sonst wieder 0)
        xor     a
        ld      (push_cnt),a
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
        jp      z,mr_go
        cp      T_DIRT
        jp      z,mr_go
        cp      T_DIAMOND
        jp      z,mr_dia
        cp      T_DIAMOND_F
        jp      z,mr_dia
        cp      T_EXIT                  ; nur der offene Ausgang (geschlossen = 15)
        jp      z,mr_exit
        cp      T_STONE
        jp      z,mr_stone
mr_blocked:
        pop     de
        xor     a                       ; Z = nicht bewegt
        ret
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
mr_stone:
        ; --- Stein schieben: nur seitlich, und nur wenn dahinter frei ist ---
        pop     de
        push    de                      ; DE = Zielfeld
        ld      a,(rock_y)
        cp      d
        jp      nz,mr_blocked           ; vertikal laesst sich kein Stein schieben
        ld      a,(push_prev)           ; Stein ist schwer: erster Tick nur Druck,
        or      a
        jr      nz,mr_heavy             ; erst beim zweiten Tick bewegt er sich
        inc     a
        ld      (push_cnt),a
        jp      mr_blocked
mr_heavy:
        ld      a,(rock_x)
        cp      e
        jr      c,mr_pr                 ; Ziel rechts von Rockford
        dec     hl                      ; Feld links hinter dem Stein
        ld      a,(hl)
        or      a
        jp      nz,mr_blocked
        ld      (hl),T_STONE
        inc     hl
        dec     e
        call    mark_dirty
        inc     e
        jp      mr_go
mr_pr:  inc     hl                      ; Feld rechts hinter dem Stein
        ld      a,(hl)
        or      a
        jp      nz,mr_blocked
        ld      (hl),T_STONE
        dec     hl
        inc     e
        call    mark_dirty
        dec     e
        jp      mr_go
mr_exit:                                ; offener Ausgang: Level geschafft
        ld      a,WIN_TICKS
        ld      (win),a
        push    hl
        ld      hl,txt_win
        call    print_str
        pop     hl
        jp      mr_go
mr_dia: ld      a,(diamonds)            ; Diamant einsammeln
        cp      MAX_DIAMONDS
        jp      nc,mr_go
        inc     a
        ld      (diamonds),a
        push    hl
        ld      hl,(score)
        ld      de,DIA_SCORE
        add     hl,de
        ld      (score),hl
        ld      a,(diamonds)
        ld      hl,need
        cp      (hl)
        jr      nz,mr_dn
        ld      a,T_EXIT                ; Quote erreicht: der Ausgang oeffnet sich
        ld      (cave+EXIT_Y*CAVE_W+EXIT_X),a
        ld      e,EXIT_X
        ld      d,EXIT_Y
        call    mark_dirty
mr_dn:  call    print_dia_score
        pop     hl
        jp      mr_go

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
gc_b:   cp      68
        jr      nc,gc_e
        ld      d,T_EMPTY
        jr      gc_store
gc_e:   cp      70                      ; 68 = Gluehwuermchen, 69 = Schmetterling
        jr      nc,gc_c
        cp      69
        ld      d,T_FIREFLY
        jr      nz,gc_store
        ld      d,T_BUTTERFLY
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
        ld      a,T_EMPTY               ; Startbereich frei (keine Gegner direkt neben Rockford)
        ld      (cave+ROCK_START_Y*CAVE_W+ROCK_START_X-1),a
        ld      (cave+ROCK_START_Y*CAVE_W+ROCK_START_X+1),a
        ld      (cave+(ROCK_START_Y+1)*CAVE_W+ROCK_START_X),a
        ld      a,T_EXIT_OFF
        ld      (cave+EXIT_Y*CAVE_W+EXIT_X),a
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

; Statuszeilen (nur bei Aenderung ausgeben, ROM-Ausgabe ist langsam)
print_all:
        call    print_time
        call    print_dia_score
        call    print_need
        call    print_lives
        jp      print_level
print_time:
        ld      hl,txt_timepos
        call    print_str
        ld      a,(time)
        jp      print_dec3
print_dia_score:
        ld      hl,txt_diapos
        call    print_str
        ld      a,(diamonds)
        call    print_dec2
print_score:
        ld      hl,txt_scorepos
        call    print_str
        ld      hl,(score)
        jp      print_num
print_need:
        ld      hl,txt_needpos
        call    print_str
        ld      a,(need)
        jp      print_dec2
print_lives:
        ld      hl,txt_livespos
        call    print_str
        ld      a,(lives)
        add     a,'0'
        rst     10h
        ret
print_level:
        ld      hl,txt_levelpos
        call    print_str
        ld      a,(level)
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

; print_dec3: A (0..255) als dreistellige Dezimalzahl ausgeben
print_dec3:
        ld      b,'0'
pd3_l:  cp      100
        jr      c,pd3_d
        sub     100
        inc     b
        jr      pd3_l
pd3_d:  push    af
        ld      a,b
        rst     10h
        pop     af
        jr      print_dec2

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
        db      22,0,0, 16,7, 17,0, 19,0
        db      "PUNKTE"
        db      22,0,13
        db      "LEBEN"
        db      22,0,21
        db      "LV"
        db      22,1,0
        db      "ZEIT"
        db      22,1,9
        db      "DIA:"
        db      22,1,15
        db      "/"
        db      22,1,19
        db      "SPACE=ENDE"
        db      16,5, 17,0, 19,1        ; Farbe fuer die Zahlen (bleibt gesetzt)
        db      0FFh
txt_timepos:   db      22,1,5, 0FFh
txt_diapos:    db      22,1,13, 0FFh
txt_needpos:   db      22,1,16, 0FFh
txt_scorepos:  db      22,0,7, 0FFh
txt_livespos:  db      22,0,19, 0FFh
txt_levelpos:  db      22,0,24, 0FFh
txt_win:
        db      22,0,0, 16,6, 17,0, 19,1
        db      "        LEVEL GESCHAFFT!        "
        db      16,5, 17,0, 19,1, 0FFh
txt_over:
        db      22,0,0, 16,2, 17,0, 19,1
        db      "           GAME OVER            "
        db      16,5, 17,0, 19,1, 0FFh

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
        dw      blk_stone,   blk_stone       ; fallender Stein
        dw      blk_diamond0,blk_diamond1    ; fallender Diamant
        dw      blk_explode, blk_explode
        dw      blk_steel,   blk_steel       ; geschlossener Ausgang
        rept    8                            ; 16..23 Gluehwuermchen
        dw      blk_firefly0,blk_firefly1
        endm
        rept    8                            ; 24..31 Schmetterling
        dw      blk_butterfly0,blk_butterfly1
        endm
        rept    8                            ; 32..39 Explosionen
        dw      blk_explode, blk_explode
        endm

; Schluessel je Frame fuer den Shadow-Puffer: Frames mit identischer Grafik
; (alle ausser den animierten) bekommen denselben Schluessel, damit ein
; Phasenwechsel nicht ueberall ein Neuzeichnen ausloest.
frame_key:
        db      0,0, 2,2, 4,4, 6,6, 8,8, 10,11, 12,12, 14,14, 16,16, 18,18, 20,20, 22,22, 8,8, 10,11, 28,28, 6,6
        rept    8
        db      40,41                   ; Gluehwuermchen (Phase 0/1)
        endm
        rept    8
        db      44,45                   ; Schmetterling
        endm
        rept    8
        db      28,28                   ; Explosionen
        endm

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

blk_firefly0:  ; Gluehwuermchen, Phase 0
        db      046h,046h,042h,042h
        db      %00000000,%00000000   ; ................
        db      %00010000,%00001000   ; ...#........#...
        db      %00001000,%00010000   ; ....#......#....
        db      %00000111,%11100000   ; .....######.....
        db      %00001111,%11110000   ; ....########....
        db      %00011011,%11011000   ; ...##.####.##...
        db      %00111011,%11011100   ; ..###.####.###..
        db      %00111111,%11111100   ; ..############..
        db      %00111111,%11111100   ; ..############..
        db      %00111011,%11011100   ; ..###.####.###..
        db      %00011011,%11011000   ; ...##.####.##...
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00001000,%00010000   ; ....#......#....
        db      %00010000,%00001000   ; ...#........#...
        db      %00000000,%00000000   ; ................

blk_firefly1:  ; Gluehwuermchen, Phase 1
        db      046h,046h,042h,042h
        db      %00000000,%00000000   ; ................
        db      %00001000,%00010000   ; ....#......#....
        db      %00000100,%00100000   ; .....#....#.....
        db      %00000111,%11100000   ; .....######.....
        db      %00001111,%11110000   ; ....########....
        db      %00011011,%11011000   ; ...##.####.##...
        db      %00111011,%11011100   ; ..###.####.###..
        db      %00111111,%11111100   ; ..############..
        db      %00111111,%11111100   ; ..############..
        db      %00111011,%11011100   ; ..###.####.###..
        db      %00011011,%11011000   ; ...##.####.##...
        db      %00001111,%11110000   ; ....########....
        db      %00000111,%11100000   ; .....######.....
        db      %00010000,%00001000   ; ...#........#...
        db      %00100000,%00000100   ; ..#..........#..
        db      %00000000,%00000000   ; ................

blk_butterfly0:  ; Schmetterling, Fluegel offen
        db      043h,043h,045h,045h
        db      %00000010,%01000000   ; ......#..#......
        db      %00000101,%10100000   ; .....#.##.#.....
        db      %11100011,%11000111   ; ###...####...###
        db      %11111011,%11011111   ; #####.####.#####
        db      %11111101,%10111111   ; ######.##.######
        db      %11111101,%10111111   ; ######.##.######
        db      %11111001,%10011111   ; #####..##..#####
        db      %01110001,%10001110   ; .###...##...###.
        db      %00110001,%10001100   ; ..##...##...##..
        db      %01110011,%11001110   ; .###..####..###.
        db      %11111011,%11011111   ; #####.####.#####
        db      %11110011,%11001111   ; ####..####..####
        db      %11100011,%11000111   ; ###...####...###
        db      %01000001,%10000010   ; .#.....##.....#.
        db      %00000010,%01000000   ; ......#..#......
        db      %00000000,%00000000   ; ................

blk_butterfly1:  ; Schmetterling, Fluegel schmal
        db      043h,043h,045h,045h
        db      %00000010,%01000000   ; ......#..#......
        db      %00000101,%10100000   ; .....#.##.#.....
        db      %00000011,%11000000   ; ......####......
        db      %00110011,%11001100   ; ..##..####..##..
        db      %01110011,%11001110   ; .###..####..###.
        db      %01111011,%11011110   ; .####.####.####.
        db      %01110011,%11001110   ; .###..####..###.
        db      %00110011,%11001100   ; ..##..####..##..
        db      %00110011,%11001100   ; ..##..####..##..
        db      %01110011,%11001110   ; .###..####..###.
        db      %01110011,%11001110   ; .###..####..###.
        db      %00110011,%11001100   ; ..##..####..##..
        db      %00100011,%11000100   ; ..#...####...#..
        db      %00000010,%01000000   ; ......#..#......
        db      %00000010,%01000000   ; ......#..#......
        db      %00000000,%00000000   ; ................

blk_explode:  ; Explosion (FLASH)
        db      0C6h,0C6h,0C6h,0C6h
        db      %00000001,%10000000   ; .......##.......
        db      %01000001,%10000010   ; .#.....##.....#.
        db      %00100011,%11000100   ; ..#...####...#..
        db      %00010111,%11101000   ; ...#.######.#...
        db      %00001111,%11110000   ; ....########....
        db      %01011111,%11111010   ; .#.##########.#.
        db      %00111111,%11111100   ; ..############..
        db      %11111111,%11111111   ; ################
        db      %11111111,%11111111   ; ################
        db      %00111111,%11111100   ; ..############..
        db      %01011111,%11111010   ; .#.##########.#.
        db      %00001111,%11110000   ; ....########....
        db      %00010111,%11101000   ; ...#.######.#...
        db      %00100011,%11000100   ; ..#...####...#..
        db      %01000001,%10000010   ; .#.....##.....#.
        db      %00000001,%10000000   ; .......##.......

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
push_cnt:       db      0               ; Schiebeversuch im letzten Tick (0/1)
push_prev:      db      0
score:          dw      0
lives:          db      0
level:          db      1
need:           db      10              ; Diamantenquote
time:           db      0               ; Restzeit in Spielsekunden
time_sub:       db      0
win:            db      0               ; >0: Ausgang erreicht (Pausen-Ticks)
over:           db      0               ; >0: GAME OVER (Pausen-Ticks)
par:            db      0               ; Tick-Paritaet (0/4) fuer die Gegner
ex_tile:        db      0               ; erste Kachel der laufenden Explosion
dead:           db      0               ; >0: Explosion laeuft (Ticks bis Neustart)
shadow:         ds      VIEW_W*VIEW_H
dirty_list:     ds      DIRTY_MAX*2
cave:           ds      CAVE_SIZE

        end     start
