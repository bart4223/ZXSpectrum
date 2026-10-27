; ============================================================
; XBlast fuer den ZX Spectrum - Stufe 6: Monster und Einzelspieler
; Assembler: pasmo   (pasmo --tapbas xblast.asm xblast.tap)
; ============================================================
; Spielfeld 15 x 11 Kacheln a 16x16 Pixel (2x2 Zeichenzellen)
; Feste Waende am Rand und auf jeder zweiten Kachel,
; zufaellige Bloecke, die vier Ecken bleiben frei.
;
; Steuerung (Sinclair IF2):
;   Spieler 1 (oben links)  : Joystick 1 = Tasten 6 7 8 9 0
;   Spieler 2 (unten rechts): Joystick 2 = Tasten 1 2 3 4 5
;   Feuer                   : Bombe legen (1 Bombe pro Spieler)
;   LEERTASTE               : Spiel abbrechen, zurueck zum Titel
; Einzelspieler: Spieler 1 wird mit Joystick 1 ODER 2 gesteuert.
;
; Ablauf: Titelbild (Siege pro Spiel waehlen: Stick links/rechts, Feuer
; startet) -> Runden bis ein Spieler genug Siege hat. Eine Runde gewinnt,
; wer als Letzter lebt (beide tot = Unentschieden). Laeuft die Rundenzeit
; ab, schliesst sich das Feld von aussen mit Waenden (Endspiel).
; Bewegung in Kachelschritten, Waende, Bloecke und Bomben blockieren.
; Eine Bombe explodiert nach 3 Sekunden: kreuzfoermige Flamme,
; Reichweite 2. Feste Waende halten die Flamme auf. Ein Block brennt
; ab und stoppt die Flamme. Trifft die Flamme eine andere Bombe, zuendet
; sie diese (Kettenreaktion). Wer in einer Flamme steht, stirbt.
; In Bloecken stecken Power-Ups, die nach dem Abbrennen erscheinen:
;   Stern  = Flammenreichweite +1
;   Bombe  = eine Bombe mehr gleichzeitig
;   Blitz  = schneller laufen
; Flammen zerstoeren liegende Power-Ups.
; Einzelspieler: Monster laufen durchs Feld und toeten bei Beruehrung.
; Gruene Monster laufen zufaellig, gelbe (ab Level 3) verfolgen den
; Spieler und meiden Flammen. Flammen toeten Monster. Sind alle tot,
; ist das Level geschafft (mehr Monster im naechsten Level). 3 Leben.
; ============================================================

        org 32768

; ---- Konstanten -------------------------------------------
FW          equ 15              ; Feldbreite in Kacheln
FH          equ 11              ; Feldhoehe in Kacheln
FIELD_COL   equ 1               ; Zeichenspalte der linken Feldkante
FIELD_ROW   equ 2               ; Zeichenzeile der oberen Feldkante

T_EMPTY     equ 0               ; Kachel-Typen
T_WALL      equ 1               ; feste Wand
T_BLOCK     equ 2               ; zerstoerbarer Block
T_BOMB      equ 3               ; Bombe
T_FLAME     equ 4               ; Flamme (Grafikindex)
; Power-Ups (Kacheltyp = Grafikindex)
T_PU_RANGE  equ 6               ; Flammenreichweite +1
T_PU_BOMB   equ 7               ; eine Bombe mehr
T_PU_SPEED  equ 8               ; schneller laufen
PU_CHANCE   equ 64              ; Anteil der Bloecke mit Power-Up (von 256)
MAX_RANGE   equ 6               ; Obergrenzen
MAX_PBOMBS  equ 5
MIN_DELAY   equ 4               ; schnellster Schritt (Frames Pause)
; Flammen stehen als 0x80 + Restdauer im Feld (Bit 7 = Flamme)
FLAME_TICKS equ 25              ; Flammendauer in Frames
FLAME_VAL   equ 0x80 + FLAME_TICKS
BOMB_FUSE   equ 150             ; Zuenddauer in Frames (3 Sekunden)
BOMB_URGENT equ 50              ; unter dieser Restzeit pulsiert die Bombe schneller
T_BOMB2     equ 5               ; Grafikindex: Bombe, zweiter Animationsframe
; Spielablauf
ROUND_TIME  equ 120             ; Rundenzeit in Sekunden
DECIDE_FRAMES equ 30            ; Wartezeit, bis eine Runde entschieden wird
OVER_FRAMES equ 100             ; Mindestanzeige des Ergebnisses
SD_RATE     equ 6               ; Frames je Endspiel-Wand
DEFAULT_WINS equ 2              ; Siege bis zum Spielgewinn (Voreinstellung)
MAX_WINS    equ 5
RS_RUN      equ 0               ; Rundenzustaende
RS_DECIDE   equ 1
RS_OVER     equ 2
; Monster (Einzelspieler)
MAX_MON     equ 6               ; Monsterplaetze
MS_SIZE     equ 8               ; Bytes je Monster
MX          equ 0               ; Kachel x
MY          equ 1               ; Kachel y
MDIR        equ 2               ; Laufrichtung
MALIVE      equ 3               ; 1 = lebt
MDELAY      equ 4               ; Frames bis zum naechsten Schritt
MTYPE       equ 5               ; 0 = zufaellig, 1 = verfolgt den Spieler
MON_DELAY_DUMB  equ 18          ; Frames je Schritt
MON_DELAY_SMART equ 12
START_LIVES equ 3
MAX_LEVEL   equ 9
MAX_BOMBS   equ 8               ; Bombenplaetze insgesamt
BS_SIZE     equ 8               ; Bytes je Bombenplatz

BLOCK_CHANCE equ 170            ; Blockwahrscheinlichkeit (von 256)

ATTR_TITLE  equ 0x46            ; hell gelb auf schwarz
ATTR_TEXT   equ 0x07            ; weiss auf schwarz
ATTR_P1     equ 0x47            ; Spieler 1: hell weiss auf schwarz
ATTR_P2     equ 0x43            ; Spieler 2: hell magenta auf schwarz
ATTR_DEAD   equ 0x42            ; Todesmeldung: hell rot auf schwarz

; Richtungen (Index in dir_dx / dir_dy und in spr_gfx)
DIR_UP      equ 0
DIR_RIGHT   equ 1
DIR_DOWN    equ 2
DIR_LEFT    equ 3

; Joystick-Bits (Ergebnis von read_joy1 / read_joy2, aktiv = 1)
J_FIRE      equ 0
J_UP        equ 1
J_DOWN      equ 2
J_RIGHT     equ 3
J_LEFT      equ 4
JM_FIRE     equ 1               ; Maske von J_FIRE

; Spieler-Struktur (PS_SIZE Bytes je Spieler)
PX          equ 0               ; Kachel x
PY          equ 1               ; Kachel y
PDIR        equ 2               ; Blickrichtung
PALIVE      equ 3               ; 1 = lebt
PDELAY      equ 4               ; Frames bis zum naechsten Schritt
PATTR       equ 5               ; Farbattribut des Sprites
PRANGE      equ 6               ; Flammenreichweite
PMAXB       equ 7               ; maximale Anzahl gleichzeitiger Bomben
PFIRE       equ 8               ; Feuertaste im letzten Frame (0/1)
POWNER      equ 9               ; Spielernummer (0/1)
PSPEED      equ 10              ; Frames Pause nach einem Schritt
PS_SIZE     equ 12

; Bombenplatz (BS_SIZE Bytes): Zeit (0 = frei), x, y, Besitzer, Reichweite

MOVE_DELAY  equ 8               ; Frames pro Schritt (50 Hz / 8 = 6,25 Schritte/s)

; ---- Variablen (freier RAM, nicht im TAP) -----------------
VARS        equ 0xA000
seed        equ VARS            ; 2 Bytes
cur_attr    equ VARS + 2        ; 1 Byte: Attribut fuer draw_cell
dirty       equ VARS + 3        ; 1 = Spieler muessen neu gezeichnet werden
ex_cx       equ VARS + 4        ; Explosion: Zentrum x
ex_cy       equ VARS + 5        ; Explosion: Zentrum y
ex_range    equ VARS + 6        ; Explosion: Reichweite
ex_dir      equ VARS + 7        ; Explosion: aktuelle Richtung
ex_cnt      equ VARS + 8        ; Explosion: verbleibende Schritte
anim        equ VARS + 9        ; Frame-Zaehler fuer Animationen
bomb_frame  equ VARS + 10       ; Bombenanimation: 0 oder 2 (Grafik 3 oder 5)
field       equ VARS + 16       ; FW*FH Bytes: Kacheltypen
hidden      equ VARS + 0x200    ; FW*FH Bytes: in Bloecken versteckte Power-Ups
HIDDEN_OFF  equ hidden - field
; Spielablauf-Variablen
numbuf      equ VARS + 0x2B0    ; 4 Bytes: Textpuffer fuer Zahlen
rstate      equ VARS + 0x2B4    ; Rundenzustand (RS_...)
rcnt        equ VARS + 0x2B5    ; Zaehler fuer Entscheidung / Anzeige
armed       equ VARS + 0x2B6    ; 1 = Feuer wurde losgelassen
match_over  equ VARS + 0x2B7    ; 1 = jemand hat das Spiel gewonnen
score1      equ VARS + 0x2B8
score2      equ VARS + 0x2B9
wins_needed equ VARS + 0x2BA
time_left   equ VARS + 0x2BB    ; Restzeit in Sekunden
tcnt        equ VARS + 0x2BC    ; Frames innerhalb der Sekunde
sd_active   equ VARS + 0x2BD    ; Endspiel laeuft
sd_cnt      equ VARS + 0x2BE
sd_x        equ VARS + 0x2BF    ; naechste Endspiel-Wand
sd_y        equ VARS + 0x2C0
sd_dir      equ VARS + 0x2C1    ; 0 rechts, 1 runter, 2 links, 3 hoch
sd_l        equ VARS + 0x2C2    ; verbleibende Grenzen der Spirale
sd_r        equ VARS + 0x2C3
sd_t        equ VARS + 0x2C4
sd_b        equ VARS + 0x2C5
sd_done     equ VARS + 0x2C6    ; Spirale ist fertig
menu_prev   equ VARS + 0x2C7    ; Menue: Joystickstand im letzten Frame
menu_cur    equ VARS + 0x2C8
game_mode   equ VARS + 0x2C9    ; 0 = Einzelspieler (Monster), 1 = zwei Spieler
level       equ VARS + 0x2CA    ; Einzelspieler: aktuelles Level 1..9
lives       equ VARS + 0x2CB    ; Einzelspieler: Leben
mon_idx     equ VARS + 0x2CC    ; Hilfsvariable beim Aufstellen der Monster
mons        equ VARS + 0x330    ; MAX_MON * MS_SIZE Bytes
bigbuf      equ VARS + 0x300    ; 32 Bytes: grosses Zeichen (2x2 Zellen)
bombs       equ VARS + 0xC0     ; MAX_BOMBS * BS_SIZE Bytes
pl1         equ VARS + 0x100    ; Spieler 1
pl2         equ pl1 + PS_SIZE   ; Spieler 2

; ============================================================
; Programmstart
; ============================================================
start:
        xor a
        out (0xFE),a            ; Rand schwarz
        call seed_init
        ld a,DEFAULT_WINS
        ld (wins_needed),a
        ld a,1
        ld (game_mode),a        ; Voreinstellung: zwei Spieler

title:
        call title_screen       ; kehrt zurueck, wenn FEUER gedrueckt wurde
        xor a
        ld (score1),a
        ld (score2),a
        ld a,1
        ld (level),a
        ld a,START_LIVES
        ld (lives),a

next_round:
        call init_round
        call cls
        call draw_header
        call init_field
        call draw_field
        call init_players
        call init_bombs
        xor a
        ld (dirty),a
        call init_monsters      ; Einzelspieler: Monster aufstellen, Spieler 2 weg
        call draw_actors

; ---- Hauptschleife: ein Durchlauf pro Frame (50 Hz) -------
game_loop:
        halt
        call rnd                ; Zufallsgenerator weiterdrehen
        ld a,0x7F
        in a,(0xFE)             ; Reihe B-N-M-Symbol-Leertaste
        rra                     ; Carry = Leertaste (0 = gedrueckt)
        jp nc,title             ; Leertaste: abbrechen
        ld a,(rstate)
        cp RS_OVER
        jr nc,gl_world          ; Runde vorbei: Spieler eingefroren
        ld ix,pl1
        call read_joy1
        ld h,a
        ld a,(game_mode)
        or a
        ld a,h
        jr nz,gl_p1
        call read_joy2          ; Einzelspieler: beide Sticks steuern Spieler 1
        or h
gl_p1:
        call update_player
        ld ix,pl2
        call read_joy2
        call update_player
        call update_monsters
gl_world:
        call update_bombs
        call check_hits
        call check_mon_hits
        call animate_bombs
        call update_flames
        ld a,(dirty)
        or a
        jr z,gl_logic
        xor a
        ld (dirty),a
        call draw_actors        ; Monster und Spieler nach Flammen wieder oben
gl_logic:
        call round_logic        ; Carry = Runde ist endgueltig vorbei
        jr nc,game_loop
        ld a,(match_over)
        or a
        jp nz,title
        jp next_round

; ============================================================
; Joystick lesen (Sinclair IF2)
; out: A = Bits J_FIRE, J_UP, J_DOWN, J_RIGHT, J_LEFT (aktiv = 1)
; ============================================================
; Joystick 1 = Tasten 6 7 8 9 0 (Port 0xEFFE):
;   Bit0 = 0 (Feuer), Bit1 = 9 (hoch), Bit2 = 8 (runter),
;   Bit3 = 7 (rechts), Bit4 = 6 (links)  -> passt direkt
read_joy1:
        ld bc,0xEFFE
        in a,(c)
        cpl
        and 0x1F
        ret

; Joystick 2 = Tasten 1 2 3 4 5 (Port 0xF7FE):
;   Bit0 = 1 (links), Bit1 = 2 (rechts), Bit2 = 3 (runter),
;   Bit3 = 4 (hoch), Bit4 = 5 (Feuer)    -> Bits umdrehen
read_joy2:
        ld bc,0xF7FE
        in a,(c)
        cpl
        and 0x1F
        ld e,a
        ld d,0
        ld b,5
rj2_rev:
        rr e
        rl d
        djnz rj2_rev
        ld a,d
        ret

; ============================================================
; Spieler
; ============================================================
init_players:
        ld hl,pl_init
        ld de,pl1
        ld bc,PS_SIZE*2
        ldir
        ret

; zeichnet beide Spieler
draw_players:
        ld ix,pl1
        call draw_player
        ld ix,pl2
        jp draw_player

; zeichnet Monster, dann Spieler (Spieler liegen oben)
draw_actors:
        call draw_monsters
        jp draw_players

; in: IX = Spieler
draw_player:
        ld a,(ix+PALIVE)
        or a
        ret z
        ld a,(ix+PATTR)
        ld (cur_attr),a
        ld a,(ix+PY)
        add a,a
        add a,FIELD_ROW
        ld b,a                  ; Zeichenzeile
        ld a,(ix+PX)
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld a,(ix+PDIR)
        jp draw_sprite

; in: IX = Spieler, A = Joystick-Bits
update_player:
        ld e,a                  ; Joystick-Bits merken
        ld a,(ix+PALIVE)
        or a
        ret z
        ; Feuer-Flanke: Bombe legen
        ld a,e
        and JM_FIRE
        ld d,a                  ; D = Feuer jetzt (0 oder 1)
        ld a,(ix+PFIRE)
        ld (ix+PFIRE),d
        or a
        jr nz,up_move           ; Taste war schon gedrueckt
        ld a,d
        or a
        jr z,up_move
        push de
        call place_bomb
        pop de
up_move:
        ld a,(ix+PDELAY)
        or a
        jr z,up_ready
        dec (ix+PDELAY)
        ret
up_ready:
        ld a,e
        ; Richtung bestimmen: hoch vor runter vor links vor rechts
        ld d,DIR_UP
        bit J_UP,a
        jr nz,up_dir
        ld d,DIR_DOWN
        bit J_DOWN,a
        jr nz,up_dir
        ld d,DIR_LEFT
        bit J_LEFT,a
        jr nz,up_dir
        ld d,DIR_RIGHT
        bit J_RIGHT,a
        ret z                   ; nichts gedrueckt
up_dir:
        ld (ix+PDIR),d          ; Blickrichtung uebernehmen
        ; Zielkachel berechnen
        ld e,d
        ld d,0
        ld hl,dir_dx
        add hl,de
        ld a,(ix+PX)
        add a,(hl)
        ld b,a                  ; neues x
        ld hl,dir_dy
        add hl,de
        ld a,(ix+PY)
        add a,(hl)
        ld c,a                  ; neues y
        call field_addr
        ld a,(hl)
        or a                    ; T_EMPTY?
        jr z,up_free
        cp T_BOMB+1
        jr c,up_blocked         ; Wand, Block, Bombe: gesperrt
up_free:                        ; leer, Power-Up oder Flamme (die ist toedlich)
        ; Schritt: alte Kachel neu zeichnen, Position setzen
        push bc
        ld b,(ix+PX)
        ld c,(ix+PY)
        call redraw_tile
        pop bc
        ld (ix+PX),b
        ld (ix+PY),c
        ld a,(ix+PSPEED)
        ld (ix+PDELAY),a
        ; Power-Up aufnehmen?
        call field_addr
        ld a,(hl)
        cp T_PU_RANGE
        jr c,up_done
        cp 0x80
        jr nc,up_done           ; Flamme
        ld (hl),T_EMPTY         ; Power-Up verschwindet von der Kachel
        call take_powerup
up_done:
        jp draw_players
up_blocked:
        jp draw_player          ; nur die Blickrichtung hat sich evtl. geaendert

; in: IX = Spieler, A = Power-Up-Typ
take_powerup:
        cp T_PU_BOMB
        jr z,tp_bomb
        jr nc,tp_speed
        ld a,(ix+PRANGE)        ; Stern: Reichweite +1
        cp MAX_RANGE
        ret nc
        inc (ix+PRANGE)
        ret
tp_bomb:
        ld a,(ix+PMAXB)         ; Bombe: eine mehr gleichzeitig
        cp MAX_PBOMBS
        ret nc
        inc (ix+PMAXB)
        ret
tp_speed:
        ld a,(ix+PSPEED)        ; Blitz: kuerzere Pause zwischen Schritten
        cp MIN_DELAY+1
        ret c
        dec (ix+PSPEED)
        ret

; ============================================================
; Bomben
; ============================================================
init_bombs:
        ld hl,bombs
        ld de,bombs+1
        ld bc,MAX_BOMBS*BS_SIZE-1
        ld (hl),0
        ldir
        xor a
        ld (bomb_frame),a
        ret

; in: IX = Spieler; legt eine Bombe auf seine Kachel, falls erlaubt
place_bomb:
        ld b,(ix+PX)
        ld c,(ix+PY)
        call field_addr
        ld a,(hl)
        or a
        ret nz                  ; Kachel nicht frei
        ; eigene Bomben zaehlen (C) und freien Platz suchen (DE)
        ld hl,bombs
        ld b,MAX_BOMBS
        ld c,0
        ld de,0
pb_scan:
        ld a,(hl)
        or a
        jr nz,pb_used
        ld a,d                  ; Platz ist frei: den ersten merken
        or e
        jr nz,pb_next
        ld d,h
        ld e,l
        jr pb_next
pb_used:
        push hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)               ; Besitzer
        pop hl
        cp (ix+POWNER)
        jr nz,pb_next
        inc c
pb_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,pb_cont
        inc h
pb_cont:
        djnz pb_scan
        ld a,c
        cp (ix+PMAXB)
        ret nc                  ; schon genug Bomben gelegt
        ld a,d
        or e
        ret z                   ; kein freier Platz
        ex de,hl                ; HL = Bombenplatz
        ld (hl),BOMB_FUSE
        inc hl
        ld a,(ix+PX)
        ld (hl),a
        inc hl
        ld a,(ix+PY)
        ld (hl),a
        inc hl
        ld a,(ix+POWNER)
        ld (hl),a
        inc hl
        ld a,(ix+PRANGE)
        ld (hl),a
        ld b,(ix+PX)
        ld c,(ix+PY)
        call field_addr
        ld (hl),T_BOMB          ; die Spielerfigur verdeckt die Bombe,
        ret                     ; bis sie die Kachel verlaesst

; Zuendschnuere herunterzaehlen, abgelaufene Bomben sprengen
update_bombs:
        ld hl,bombs
        ld b,MAX_BOMBS
ub_loop:
        ld a,(hl)
        or a
        jr z,ub_next
        dec a
        ld (hl),a
        jr nz,ub_next
        push bc
        push hl
        call explode
        pop hl
        pop bc
ub_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ub_cont
        inc h
ub_cont:
        djnz ub_loop
        ret

; Bombenanimation: alle Bomben pulsieren im gleichen Takt (2 Frames),
; alle 8 Bildschirmframes; ist eine Zuendschnur fast durch (unter
; BOMB_URGENT), doppelt so schnell. Bomben unter einer Spielerfigur
; werden nicht neu gezeichnet; die Figur verdeckt sie ohnehin.
animate_bombs:
        ld hl,anim
        inc (hl)
        ld d,(hl)               ; D = Frame-Zaehler
        ld hl,bombs
        ld b,MAX_BOMBS
        ld e,8                  ; normaler Takt
ab_scan:
        ld a,(hl)
        or a
        jr z,ab_next
        cp BOMB_URGENT
        jr nc,ab_next
        ld e,4                  ; eine Bombe geht bald hoch: schneller
ab_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ab_cont
        inc h
ab_cont:
        djnz ab_scan
        ld a,d
        and e
        jr z,ab_set
        ld a,2
ab_set:
        ld hl,bomb_frame
        cp (hl)
        ret z                   ; Frame hat sich nicht geaendert
        ld (hl),a
        ld hl,bombs
        ld d,MAX_BOMBS
ab_loop:
        ld a,(hl)
        or a
        jr z,ab_skip
        push hl
        inc hl
        ld b,(hl)               ; x
        inc hl
        ld c,(hl)               ; y
        call tile_has_player
        call z,redraw_tile
        pop hl
ab_skip:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,ab_next2
        inc h
ab_next2:
        dec d
        jr nz,ab_loop
        ret

; in: B = x, C = y; out: NZ = ein lebender Spieler steht auf der Kachel
; erhaelt BC, DE, HL
tile_has_player:
        ld a,(pl1+PALIVE)
        or a
        jr z,thp_p2
        ld a,(pl1+PX)
        cp b
        jr nz,thp_p2
        ld a,(pl1+PY)
        cp c
        jr z,thp_yes
thp_p2:
        ld a,(pl2+PALIVE)
        or a
        jr z,thp_no
        ld a,(pl2+PX)
        cp b
        jr nz,thp_no
        ld a,(pl2+PY)
        cp c
        jr z,thp_yes
thp_no:
        xor a                   ; Z: niemand da
        ret
thp_yes:
        ld a,1
        or a                    ; NZ: Spieler steht darauf
        ret

; in: HL = Bombenplatz (Zeit ist schon 0)
; setzt die Flammen: Zentrum und je Richtung bis Reichweite;
; Wand stoppt, Block und Power-Up brennen ab (und stoppen), Bombe wird gezuendet
explode:
        inc hl
        ld a,(hl)
        ld (ex_cx),a
        inc hl
        ld a,(hl)
        ld (ex_cy),a
        inc hl
        inc hl
        ld a,(hl)
        ld (ex_range),a
        ld a,(ex_cx)
        ld b,a
        ld a,(ex_cy)
        ld c,a
        call set_flame          ; Zentrum
        xor a
        ld (ex_dir),a
ex_dir_loop:
        ld a,(ex_cx)
        ld b,a
        ld a,(ex_cy)
        ld c,a
        ld a,(ex_range)
        ld (ex_cnt),a
ex_step:
        ld a,(ex_dir)
        ld e,a
        ld d,0
        ld hl,dir_dx
        add hl,de
        ld a,b
        add a,(hl)
        ld b,a
        ld hl,dir_dy
        add hl,de
        ld a,c
        add a,(hl)
        ld c,a                  ; naechste Kachel in dieser Richtung
        call field_addr
        ld a,(hl)
        or a
        jr z,ex_flame           ; leer: Flamme
        cp 0x80
        jr nc,ex_flame          ; schon Flamme: weiter
        cp T_BLOCK
        jr z,ex_block
        cp T_BOMB
        jr z,ex_bomb
        cp T_PU_RANGE
        jr nc,ex_block          ; ein Power-Up verbrennt wie ein Block
        jr ex_stop              ; feste Wand: hier ist Schluss
ex_block:
        call set_flame          ; Block/Power-Up brennt, die Flamme endet hier
        jr ex_stop
ex_bomb:
        call trigger_bomb       ; Kettenreaktion: die Bombe dort zuenden
        jr ex_stop
ex_flame:
        call set_flame          ; leer oder schon Flamme: (neu) setzen
        ld hl,ex_cnt
        dec (hl)
        jr nz,ex_step
ex_stop:
        ld hl,ex_dir
        inc (hl)
        ld a,(hl)
        cp 4
        jr c,ex_dir_loop
        ld a,1
        ld (dirty),a
        ret

; in: B = x, C = y; zuendet die Bombe auf dieser Kachel (Rest = 1 Frame)
; erhaelt BC; veraendert A, D, E, HL
trigger_bomb:
        ld e,1
; in: B = x, C = y, E = neue Restzeit der Bombe auf dieser Kachel
; (0 = Bombe entfernen); erhaelt BC; veraendert A, D, HL
set_bomb_timer:
        ld hl,bombs
        ld d,MAX_BOMBS
tb_loop:
        ld a,(hl)
        or a
        jr z,tb_next
        push hl
        inc hl
        ld a,(hl)
        cp b
        jr nz,tb_no
        inc hl
        ld a,(hl)
        cp c
        jr nz,tb_no
        pop hl
        ld (hl),e               ; 1 = explodiert beim naechsten Durchlauf
        ret
tb_no:
        pop hl
tb_next:
        ld a,l
        add a,BS_SIZE
        ld l,a
        jr nc,tb_cont
        inc h
tb_cont:
        dec d
        jr nz,tb_loop
        ret

; in: B = x, C = y; setzt die Kachel auf Flamme und zeichnet sie
set_flame:
        call field_addr
        ld (hl),FLAME_VAL
        jp redraw_tile

; Steht ein lebender Spieler in einer Flamme, stirbt er
check_hits:
        ld a,(rstate)
        cp RS_OVER
        ret nc                  ; nach dem Rundenende ist niemand mehr verwundbar
        ld ix,pl1
        call hit_check
        ld ix,pl2
hit_check:
        ld a,(ix+PALIVE)
        or a
        ret z
        ld b,(ix+PX)
        ld c,(ix+PY)
        call field_addr
        ld a,(hl)
        cp 0x80
        ret c                   ; keine Flamme auf der Kachel
        ld (ix+PALIVE),0        ; getroffen
        jp redraw_tile          ; Figur wegzeichnen

; Meldungszeile (Zeile 1) leeren
clear_msgs:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld hl,txt_blank
        ld b,1
        ld c,1
        jp print_at

; Flammen herunterzaehlen, erloschene werden wieder leer
update_flames:
        ld hl,field
        ld d,0                  ; y
uf_row:
        ld e,0                  ; x
uf_col:
        ld a,(hl)
        bit 7,a
        jr z,uf_next
        dec a
        cp 0x80
        jr nz,uf_store
        push hl                 ; Flamme erloschen: verstecktes Power-Up
        ld bc,HIDDEN_OFF        ; (oder leer) wird sichtbar
        add hl,bc
        ld a,(hl)
        ld (hl),0
        pop hl
        ld (hl),a
        push hl
        ld b,e
        ld c,d
        call redraw_tile
        pop hl
        ld a,1
        ld (dirty),a
        jr uf_next
uf_store:
        ld (hl),a
uf_next:
        inc hl
        inc e
        ld a,e
        cp FW
        jr nz,uf_col
        inc d
        ld a,d
        cp FH
        jr nz,uf_row
        ret


; ============================================================
; Monster (Einzelspieler)
; ============================================================
; Monster liegen wie die Spieler nicht im Feld, sondern in eigenen
; Strukturen (mons). Zufalls-Monster laufen geradeaus und biegen
; zufaellig ab; Verfolger laufen auf den Spieler zu und meiden Flammen.

; Monster loeschen und aufstellen; im Einzelspieler ist Spieler 2 nicht dabei
init_monsters:
        ld hl,mons
        ld de,mons+1
        ld bc,MAX_MON*MS_SIZE-1
        ld (hl),0
        ldir
        ld a,(game_mode)
        or a
        ret nz                  ; zwei Spieler: keine Monster
        ld (pl2+PALIVE),a       ; A = 0: Spieler 2 spielt nicht mit
        ld a,(level)
        inc a                   ; Level n: n+1 Monster
        cp MAX_MON+1
        jr c,im_n
        ld a,MAX_MON
im_n:
        ld b,a                  ; Anzahl
        xor a
        ld (mon_idx),a
        ld ix,mons
im_loop:
        push bc
im_find:
        call rnd
        and 15
        jr z,im_find
        cp FW-1
        jr nc,im_find           ; x = 1..13
        ld d,a
im_fy:
        call rnd
        and 15
        jr z,im_fy
        cp FH-1
        jr nc,im_fy             ; y = 1..9
        ld e,a
        add a,d
        cp 8
        jr c,im_find            ; zu nah am Start von Spieler 1
        ld b,d
        ld c,e
        call field_addr
        ld a,(hl)
        or a
        jr nz,im_find           ; Kachel nicht leer
        call mon_at
        jr nz,im_find           ; schon ein Monster dort
        ld (ix+MX),b
        ld (ix+MY),c
        ld (ix+MALIVE),1
        ld (ix+MDELAY),30       ; kurze Schonfrist zum Start
        call rnd
        and 3
        ld (ix+MDIR),a
        ld (ix+MTYPE),0
        ld a,(level)
        cp 3
        jr c,im_next            ; unter Level 3: nur Zufalls-Monster
        ld a,(mon_idx)
        and 1
        ld (ix+MTYPE),a         ; jedes zweite Monster verfolgt den Spieler
im_next:
        ld a,(mon_idx)
        inc a
        ld (mon_idx),a
        ld de,MS_SIZE
        add ix,de
        pop bc
        djnz im_loop
        jp show_status1         ; Gegneranzeige in der Kopfzeile

; in: B = x, C = y; out: NZ = dort steht ein lebendes Monster
; erhaelt BC, DE, HL
mon_at:
        push hl
        push de
        ld hl,mons
        ld d,MAX_MON
ma_loop:
        ld a,(hl)
        cp b
        jr nz,ma_next
        inc hl
        ld a,(hl)
        inc hl
        inc hl
        ld e,(hl)               ; lebt?
        dec hl
        dec hl
        dec hl
        cp c
        jr nz,ma_next
        ld a,e
        or a
        jr nz,ma_yes
ma_next:
        ld a,l
        add a,MS_SIZE
        ld l,a
        jr nc,ma_cont
        inc h
ma_cont:
        dec d
        jr nz,ma_loop
        xor a                   ; Z: keins
        pop de
        pop hl
        ret
ma_yes:
        ld a,1
        or a                    ; NZ
        pop de
        pop hl
        ret

; out: A = Anzahl lebender Monster
count_monsters:
        ld hl,mons+MALIVE
        ld de,MS_SIZE
        ld b,MAX_MON
        ld c,0
cmn_loop:
        ld a,(hl)
        add a,c
        ld c,a
        add hl,de
        djnz cmn_loop
        ld a,c
        ret

; alle Monster einen Schritt weiter (jedes mit eigener Pause)
update_monsters:
        ld a,(game_mode)
        or a
        ret nz
        ld ix,mons
        ld b,MAX_MON
um_loop:
        push bc
        ld a,(ix+MALIVE)
        or a
        call nz,move_monster
        pop bc
        ld de,MS_SIZE
        add ix,de
        djnz um_loop
        ld a,(anim)             ; alle 8 Frames Beinchen wechseln
        and 7
        ret nz
        jp draw_monsters

; in: IX = Monster
move_monster:
        ld a,(ix+MDELAY)
        or a
        jr z,mm_go
        dec (ix+MDELAY)
        ret
mm_go:
        ld a,(ix+MTYPE)
        or a
        jr z,mm_dumb
        call rnd
        and 3
        jr z,mm_dumb            ; Verfolger wird manchmal zufaellig
        ; Richtung zum Spieler: H = dx, L = dy
        ld a,(pl1+PX)
        sub (ix+MX)
        ld h,a
        ld a,(pl1+PY)
        sub (ix+MY)
        ld l,a
        ld a,h
        ld d,0xFF               ; D = waagerechte Richtung (FF = keine)
        or a
        jr z,ms_h_done
        ld d,DIR_RIGHT
        jp p,ms_h_done
        ld d,DIR_LEFT
ms_h_done:
        ld a,l
        ld e,0xFF               ; E = senkrechte Richtung
        or a
        jr z,ms_v_done
        ld e,DIR_DOWN
        jp p,ms_v_done
        ld e,DIR_UP
ms_v_done:
        ld a,h                  ; Betraege vergleichen
        or a
        jp p,ms_ah
        neg
ms_ah:
        ld h,a
        ld a,l
        or a
        jp p,ms_al
        neg
ms_al:
        cp h                    ; |dy| < |dx| ?
        jr c,ms_order_ok        ; ja: waagerecht zuerst
        ld a,d                  ; sonst senkrecht zuerst
        ld d,e
        ld e,a
ms_order_ok:
        ld a,d
        cp 0xFF
        jr z,ms_try_e
        call mon_try
        jr c,mm_step
ms_try_e:
        ld a,e
        cp 0xFF
        jr z,mm_dumb
        ld d,e
        call mon_try
        jr c,mm_step
mm_dumb:
        call rnd
        and 3
        jr z,mm_rand            ; manchmal einfach abbiegen
        ld d,(ix+MDIR)
        call mon_try
        jr c,mm_step
mm_rand:
        call rnd
        and 3
        ld d,a
        ld e,4                  ; alle vier Richtungen ab einer zufaelligen
mr_loop:
        call mon_try
        jr c,mm_step
        ld a,d
        inc a
        and 3
        ld d,a
        dec e
        jr nz,mr_loop
        ld (ix+MDELAY),6        ; eingesperrt: kurz warten
        ret
mm_step:
        ld (ix+MDIR),d
        push bc
        ld b,(ix+MX)
        ld c,(ix+MY)
        call redraw_tile        ; alte Kachel wiederherstellen
        pop bc
        ld (ix+MX),b
        ld (ix+MY),c
        ld a,(ix+MTYPE)
        or a
        ld a,MON_DELAY_DUMB
        jr z,mm_dl
        ld a,MON_DELAY_SMART
mm_dl:
        ld (ix+MDELAY),a
        jp draw_monster

; in: IX = Monster, D = Richtung
; out: Carry = Schritt moeglich, dann B = x, C = y der Zielkachel
; erhaelt DE
mon_try:
        push de
        ld e,d
        ld d,0
        ld hl,dir_dx
        add hl,de
        ld a,(ix+MX)
        add a,(hl)
        ld b,a
        ld hl,dir_dy
        add hl,de
        ld a,(ix+MY)
        add a,(hl)
        ld c,a
        call field_addr
        ld a,(hl)
        or a
        jr z,mt_ok              ; leer
        cp 0x80
        jr nc,mt_flame
        cp T_PU_RANGE
        jr c,mt_no              ; Wand, Block, Bombe
        jr mt_ok                ; Power-Up
mt_flame:
        ld a,(ix+MTYPE)
        or a
        jr nz,mt_no             ; Verfolger meidet Flammen
mt_ok:
        call mon_at
        jr nz,mt_no             ; anderes Monster im Weg
        pop de
        scf
        ret
mt_no:
        pop de
        and a
        ret

; Flammen toeten Monster, Beruehrung toetet den Spieler
check_mon_hits:
        ld a,(game_mode)
        or a
        ret nz
        ld a,(rstate)
        cp RS_OVER
        ret nc
        ld ix,mons
        ld d,MAX_MON
cmh_loop:
        ld a,(ix+MALIVE)
        or a
        jr z,cmh_next
        ld b,(ix+MX)
        ld c,(ix+MY)
        call field_addr
        ld a,(hl)
        cp 0x80
        jr c,cmh_contact
        ld (ix+MALIVE),0        ; in der Flamme gestorben
        call redraw_tile
        ld a,1
        ld (dirty),a
        push de
        call show_status1
        pop de
        jr cmh_next
cmh_contact:
        ld a,(pl1+PALIVE)
        or a
        jr z,cmh_next
        ld a,(pl1+PX)
        cp b
        jr nz,cmh_next
        ld a,(pl1+PY)
        cp c
        jr nz,cmh_next
        xor a
        ld (pl1+PALIVE),a       ; vom Monster erwischt
        call redraw_tile
        ld a,1
        ld (dirty),a
cmh_next:
        push de
        ld de,MS_SIZE
        add ix,de
        pop de
        dec d
        jr nz,cmh_loop
        ret

draw_monsters:
        ld ix,mons
        ld b,MAX_MON
dms_loop:
        push bc
        call draw_monster
        pop bc
        ld de,MS_SIZE
        add ix,de
        djnz dms_loop
        ret

; in: IX = Monster
draw_monster:
        ld a,(ix+MALIVE)
        or a
        ret z
        ld a,(ix+MTYPE)
        ld e,a
        ld d,0
        ld hl,mon_attr
        add hl,de
        ld a,(hl)
        ld (cur_attr),a
        ld a,(ix+MTYPE)
        add a,a
        ld e,a                  ; Typ * 2
        ld a,(anim)
        rrca
        rrca
        rrca
        and 1                   ; Bit 3 der Frames: Beinchen
        add a,e
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; * 32
        ld de,mon_gfx
        add hl,de
        ld a,(ix+MY)
        add a,a
        add a,FIELD_ROW
        ld b,a
        ld a,(ix+MX)
        add a,a
        add a,FIELD_COL
        ld c,a
        jp draw_gfx

; ============================================================
; Spielablauf: Runden, Zeit, Endspiel
; ============================================================
init_round:
        xor a
        ld (rstate),a
        ld (armed),a
        ld (match_over),a
        ld (sd_active),a
        ld (sd_done),a
        ld (tcnt),a
        ld (sd_dir),a
        ld a,ROUND_TIME
        ld (time_left),a
        ld a,1
        ld (sd_x),a
        ld (sd_y),a
        ld (sd_l),a
        ld (sd_t),a
        ld a,FW-2
        ld (sd_r),a
        ld a,FH-2
        ld (sd_b),a
        ld a,SD_RATE
        ld (sd_cnt),a
        ret

; out: Carry gesetzt = die Runde ist endgueltig vorbei (naechste Runde / Titel)
round_logic:
        ld a,(game_mode)
        or a
        jp z,round_logic1       ; Einzelspieler
        ld a,(rstate)
        cp RS_DECIDE
        jr z,rl_decide
        jr nc,rl_over
        ; --- Runde laeuft
        call update_time
        call update_sudden
        call count_alive
        cp 2
        jr nc,rl_nc             ; beide leben noch
        ld a,RS_DECIDE          ; einer ist tot: kurz warten, ob der zweite folgt
        ld (rstate),a
        ld a,DECIDE_FRAMES
        ld (rcnt),a
rl_nc:
        and a                   ; Carry = 0
        ret

rl_decide:
        ld hl,rcnt
        dec (hl)
        jr nz,rl_nc
        call count_alive
        or a
        jr z,rl_draw
        ld a,(pl1+PALIVE)
        or a
        jr z,rl_p2win
        ld hl,score1            ; Spieler 1 hat gewonnen
        ld de,txt_p1pt
        ld bc,txt_p1win
        jr rl_win
rl_p2win:
        ld hl,score2
        ld de,txt_p2pt
        ld bc,txt_p2win
rl_win:
        inc (hl)
        ld a,(hl)
        ld hl,wins_needed
        cp (hl)
        jr c,rl_round           ; noch nicht genug Siege
        ld a,1
        ld (match_over),a
        ld h,b                  ; Text: "SPIELER n SIEGT!"
        ld l,c
        jr rl_show
rl_round:
        ex de,hl                ; Text: "SPIELER n PUNKT"
        jr rl_show
rl_draw:
        ld hl,txt_draw
rl_show:
        push hl
        call clear_msgs
        pop hl
        ld a,ATTR_P1
        ld (cur_attr),a
        ld b,1
        ld c,1
        call print_at
        call show_scores
        ld a,RS_OVER
        ld (rstate),a
        ld a,OVER_FRAMES
        ld (rcnt),a
        and a
        ret

; Runde vorbei: Ergebnis stehen lassen, dann auf FEUER warten
rl_over:
        ld a,(rcnt)
        or a
        jr z,rl_wait
        dec a
        ld (rcnt),a
        jr nz,rl_nc
        ld hl,txt_prompt        ; Mindestzeit um: Hinweis zeigen
        ld bc,1*256+19
        ld a,ATTR_TITLE
        call put_text
        and a
        ret
rl_wait:
        call any_fire
        jr nz,rl_pressed
        ld a,1
        ld (armed),a            ; Feuer losgelassen: jetzt wird es erkannt
        and a
        ret
rl_pressed:
        ld a,(armed)
        or a
        ret z                   ; (Carry = 0) Feuer wird noch von vorhin gehalten
        scf
        ret

; Einzelspieler: Level geschafft oder Leben verloren
round_logic1:
        ld a,(rstate)
        cp RS_DECIDE
        jr z,r1_decide
        jp nc,rl_over
        ld a,(pl1+PALIVE)
        or a
        jr z,r1_start           ; Spieler tot
        call count_monsters
        or a
        jp nz,rl_nc             ; es gibt noch Gegner
r1_start:
        ld a,RS_DECIDE
        ld (rstate),a
        ld a,DECIDE_FRAMES
        ld (rcnt),a
        and a
        ret
r1_decide:
        ld hl,rcnt
        dec (hl)
        jp nz,rl_nc
        ld a,(pl1+PALIVE)
        or a
        jr z,r1_dead
        ld a,(level)            ; alle Monster tot: naechstes Level
        cp MAX_LEVEL
        jr nc,r1_ok
        inc a
        ld (level),a
r1_ok:
        ld hl,txt_lvl_ok
        jp rl_show
r1_dead:
        ld hl,lives
        dec (hl)
        ld hl,txt_lost
        jp nz,rl_show
        ld a,1
        ld (match_over),a       ; alle Leben weg: Spiel vorbei
        ld hl,txt_gameover
        jp rl_show

; out: A = Anzahl lebender Spieler
count_alive:
        xor a
        ld hl,pl1+PALIVE
        add a,(hl)
        ld hl,pl2+PALIVE
        add a,(hl)
        ret

; out: NZ = ein Feuerknopf ist gedrueckt
any_fire:
        call read_joy1
        and JM_FIRE
        ret nz
        call read_joy2
        and JM_FIRE
        ret

; Restzeit herunterzaehlen und anzeigen
update_time:
        ld a,(sd_active)
        or a
        ret nz
        ld hl,tcnt
        inc (hl)
        ld a,(hl)
        cp 50
        ret c
        ld (hl),0
        ld hl,time_left
        dec (hl)
        call show_time
        ld a,(time_left)
        or a
        ret nz
        ld a,1                  ; Zeit abgelaufen: Endspiel beginnt
        ld (sd_active),a
        ld hl,txt_sd
        ld bc,1*256+1
        ld a,ATTR_DEAD
        jp put_text

show_time:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld a,(time_left)
        ld b,0
        ld c,14
        jp print_num3

show_scores:
        ld a,(game_mode)
        or a
        jp z,show_status1
        ld a,ATTR_P1
        ld (cur_attr),a
        ld a,(score1)
        ld b,0
        ld c,22
        call print_digit
        ld a,ATTR_P2
        ld (cur_attr),a
        ld a,(score2)
        ld b,0
        ld c,28
        jp print_digit

; Einzelspieler: Level, Leben und Gegner in der Kopfzeile
show_status1:
        ld a,ATTR_TEXT
        ld (cur_attr),a
        ld a,(level)
        ld b,0
        ld c,14
        call print_digit
        ld a,(lives)
        ld b,0
        ld c,22
        call print_digit
        call count_monsters
        ld b,0
        ld c,31
        jp print_digit

; Endspiel: im Takt SD_RATE eine Wand mehr, spiralfoermig von aussen
update_sudden:
        ld a,(sd_active)
        or a
        ret z
        ld a,(sd_done)
        or a
        ret nz
        ld hl,sd_cnt
        dec (hl)
        ret nz
        ld (hl),SD_RATE
us_next:
        ld a,(sd_done)
        or a
        ret nz
        ld a,(sd_x)
        ld b,a
        ld a,(sd_y)
        ld c,a
        call field_addr
        ld a,(hl)
        cp T_WALL
        jr nz,us_wall
        call sd_advance         ; ist schon Wand (Saeule): ohne Pause weiter
        jr us_next
us_wall:
        ld (hl),T_WALL
        push hl
        ld de,HIDDEN_OFF
        add hl,de
        ld (hl),0               ; verstecktes Power-Up geht verloren
        pop hl
        ld e,0
        call set_bomb_timer     ; eine Bombe auf der Kachel wird entfernt
        call kill_at            ; wer dort steht, wird zerquetscht
        call redraw_tile
        call sd_advance
        ld a,1
        ld (dirty),a
        ret

; in: B = x, C = y; Spieler auf dieser Kachel sterben
kill_at:
        ld ix,pl1
        call ka_one
        ld ix,pl2
ka_one:
        ld a,(ix+PALIVE)
        or a
        ret z
        ld a,(ix+PX)
        cp b
        ret nz
        ld a,(ix+PY)
        cp c
        ret nz
        ld (ix+PALIVE),0
        ret

; naechste Kachel der Spirale (sd_x, sd_y) bestimmen
sd_advance:
        ld a,(sd_dir)
        or a
        jr z,sa_right
        cp 1
        jr z,sa_down
        cp 2
        jr z,sa_left
        ; hoch
        ld a,(sd_y)
        ld hl,sd_t
        cp (hl)
        jr z,sa_up_turn
        dec a
        ld (sd_y),a
        ret
sa_up_turn:
        ld hl,sd_l
        inc (hl)
        xor a                   ; Richtung rechts
        ld (sd_dir),a
        ld a,(sd_x)
        inc a
        ld (sd_x),a
        jr sa_check
sa_right:
        ld a,(sd_x)
        ld hl,sd_r
        cp (hl)
        jr z,sa_right_turn
        inc a
        ld (sd_x),a
        ret
sa_right_turn:
        ld hl,sd_t
        inc (hl)
        ld a,1                  ; Richtung runter
        ld (sd_dir),a
        ld a,(sd_y)
        inc a
        ld (sd_y),a
        jr sa_check
sa_down:
        ld a,(sd_y)
        ld hl,sd_b
        cp (hl)
        jr z,sa_down_turn
        inc a
        ld (sd_y),a
        ret
sa_down_turn:
        ld hl,sd_r
        dec (hl)
        ld a,2                  ; Richtung links
        ld (sd_dir),a
        ld a,(sd_x)
        dec a
        ld (sd_x),a
        jr sa_check
sa_left:
        ld a,(sd_x)
        ld hl,sd_l
        cp (hl)
        jr z,sa_left_turn
        dec a
        ld (sd_x),a
        ret
sa_left_turn:
        ld hl,sd_b
        dec (hl)
        ld a,3                  ; Richtung hoch
        ld (sd_dir),a
        ld a,(sd_y)
        dec a
        ld (sd_y),a
sa_check:                       ; fertig, wenn sich die Grenzen kreuzen
        ld a,(sd_r)
        ld hl,sd_l
        cp (hl)
        jr c,sa_finish
        ld a,(sd_b)
        ld hl,sd_t
        cp (hl)
        ret nc
sa_finish:
        ld a,1
        ld (sd_done),a
        ret

; ============================================================
; Titelbild und Menue
; ============================================================
; kehrt zurueck, sobald FEUER gedrueckt wird
title_screen:
        call cls
        call draw_title_static
        call show_menu
ts_rel:
        call any_fire           ; erst warten, bis kein Feuer mehr gehalten wird
        jr nz,ts_rel
        xor a
        ld (menu_prev),a
ts_loop:
        halt
        call rnd
        call read_joy1
        ld (menu_cur),a
        call read_joy2
        ld hl,menu_cur
        or (hl)                 ; Joystick 1 oder 2
        ld hl,menu_prev
        ld b,(hl)
        ld (hl),a
        ld c,a
        ld a,b
        cpl
        and c                   ; A = neu gedrueckte Richtungen/Feuer
        ld e,a
        bit J_FIRE,e
        ret nz                  ; Start
        bit J_UP,e
        jr nz,ts_mode
        bit J_DOWN,e
        jr z,ts_wins
ts_mode:
        ld a,(game_mode)        ; hoch / runter: Einzelspieler <-> zwei Spieler
        xor 1
        ld (game_mode),a
        call show_menu
        jr ts_loop
ts_wins:
        ld a,(wins_needed)
        bit J_LEFT,e
        jr z,ts_right
        cp 1
        jr z,ts_loop
        dec a
        jr ts_set
ts_right:
        bit J_RIGHT,e
        jr z,ts_loop
        cp MAX_WINS
        jr nc,ts_loop
        inc a
ts_set:
        ld (wins_needed),a
        call show_menu
        jr ts_loop

; Spielart (Zeile 19) und Siege bzw. Hinweis (Zeile 20) anzeigen
show_menu:
        ld hl,txt_t11
        ld bc,19*256+3
        ld a,ATTR_TEXT
        call put_text
        ld hl,txt_m2
        ld a,(game_mode)
        or a
        jr nz,sm_txt
        ld hl,txt_m1
sm_txt:
        ld bc,19*256+13
        ld a,ATTR_TITLE
        call put_text
        ld hl,txt_blank
        ld bc,20*256+1
        ld a,ATTR_TEXT
        call put_text
        ld a,(game_mode)
        or a
        jr nz,sm_wins
        ld hl,txt_t12
        ld bc,20*256+3
        ld a,ATTR_TEXT
        jp put_text
sm_wins:
        ld hl,txt_t8
        ld bc,20*256+3
        ld a,ATTR_TEXT
        call put_text
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld a,(wins_needed)
        ld b,20
        ld c,28
        jp print_digit

draw_title_static:
        ; grosser Titel, jeder Buchstabe in anderer Farbe
        ld hl,title_big
        ld d,6
        ld c,10                 ; Spalte
tt_loop:
        ld a,(hl)               ; Zeichen
        inc hl
        ld e,(hl)               ; Farbe
        inc hl
        push hl
        push de
        ld b,a
        ld a,e
        ld (cur_attr),a
        ld a,b
        ld b,2                  ; Zeile
        call big_char
        pop de
        pop hl
        inc c
        inc c
        dec d
        jr nz,tt_loop
        ; Bombe und Flamme neben dem Titel
        ld a,T_BOMB
        ld bc,2*256+6
        call draw_tile
        ld a,T_FLAME
        ld bc,2*256+24
        call draw_tile
        ld hl,txt_t1
        ld bc,6*256+2
        ld a,ATTR_TEXT
        call put_text
        ; Legende der Power-Ups
        ld a,T_PU_RANGE
        ld bc,9*256+3
        call draw_tile
        ld hl,txt_t2
        ld bc,9*256+6
        ld a,ATTR_TEXT
        call put_text
        ld a,T_PU_BOMB
        ld bc,11*256+3
        call draw_tile
        ld hl,txt_t3
        ld bc,11*256+6
        ld a,ATTR_TEXT
        call put_text
        ld a,T_PU_SPEED
        ld bc,13*256+3
        call draw_tile
        ld hl,txt_t4
        ld bc,13*256+6
        ld a,ATTR_TEXT
        call put_text
        ; Steuerung
        ld hl,txt_t5
        ld bc,15*256+2
        ld a,ATTR_P1
        call put_text
        ld hl,txt_t6
        ld bc,16*256+2
        ld a,ATTR_P2
        call put_text
        ld hl,txt_t7
        ld bc,17*256+2
        ld a,ATTR_TEXT
        call put_text
        ; Menue (Zeilen 19/20 zeichnet show_menu)
        ld hl,txt_t9
        ld bc,21*256+4
        ld a,0x05               ; cyan
        call put_text
        ld hl,txt_t10
        ld bc,23*256+9
        ld a,0xC6               ; blinkend, hell gelb
        jp put_text

; Spielkopf: Titel, Zeit, Spielstand
draw_header:
        ld hl,txt_title
        ld bc,0*256+1
        ld a,ATTR_TITLE
        call put_text
        ld a,(game_mode)
        or a
        jr nz,dh_two
        ld hl,txt_level
        ld bc,0*256+8
        ld a,ATTR_TEXT
        call put_text
        ld hl,txt_lives
        ld bc,0*256+16
        ld a,ATTR_P1
        call put_text
        ld hl,txt_enemy
        ld bc,0*256+24
        ld a,ATTR_P2
        call put_text
        jp show_status1
dh_two:
        ld hl,txt_zeit
        ld bc,0*256+9
        ld a,ATTR_TEXT
        call put_text
        ld hl,txt_p1
        ld bc,0*256+19
        ld a,ATTR_P1
        call put_text
        ld hl,txt_p2
        ld bc,0*256+25
        ld a,ATTR_P2
        call put_text
        call show_time
        jp show_scores

; ============================================================
; Text: Zahlen und grosse Zeichen
; ============================================================
; in: HL = Text, B = Zeile, C = Spalte, A = Attribut
put_text:
        ld (cur_attr),a
        jp print_at

; in: A = Ziffer 0..9, B = Zeile, C = Spalte, (cur_attr)
print_digit:
        add a,'0'
        ld (numbuf),a
        xor a
        ld (numbuf+1),a
        ld hl,numbuf
        jp print_at

; in: A = Zahl 0..255 (dreistellig), B = Zeile, C = Spalte, (cur_attr)
print_num3:
        ld hl,numbuf
        ld d,'0'
pn_h:
        cp 100
        jr c,pn_h_done
        sub 100
        inc d
        jr pn_h
pn_h_done:
        ld (hl),d
        inc hl
        ld d,'0'
pn_t:
        cp 10
        jr c,pn_t_done
        sub 10
        inc d
        jr pn_t
pn_t_done:
        ld (hl),d
        inc hl
        add a,'0'
        ld (hl),a
        inc hl
        ld (hl),0
        ld hl,numbuf
        jp print_at

; in: A = Zeichencode, B = Zeile, C = Spalte, (cur_attr)
; zeichnet das Zeichen doppelt gross (16x16 aus dem ROM-Zeichensatz)
; erhaelt BC; veraendert A, DE, HL
big_char:
        push bc
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,0x3C00
        add hl,de               ; HL = Glyphe im ROM (8 Bytes)
        ld de,bigbuf
        ld c,8                  ; 8 Quellzeilen
bg_row:
        ld a,(hl)
        inc hl
        ld b,a                  ; B = Quellzeile
        push hl
        rrca
        rrca
        rrca
        rrca
        and 15
        call nib_expand         ; A = linke Haelfte, 8 Bit breit
        ld (de),a               ; oben links, Zeile 2i
        inc de
        ld (de),a               ; Zeile 2i+1
        dec de
        ld a,b
        and 15
        call nib_expand         ; A = rechte Haelfte
        ld hl,8
        add hl,de
        ld (hl),a               ; oben rechts, Zeile 2i
        inc hl
        ld (hl),a               ; Zeile 2i+1
        inc de
        inc de
        ld a,e
        cp 8                    ; nach 4 Quellzeilen weiter bei der unteren Haelfte
        jr nz,bg_nxt
        ld e,16
bg_nxt:
        pop hl
        dec c
        jr nz,bg_row
        pop bc
        ld hl,bigbuf
        jp draw_gfx

; in: A = Nibble 0..15; out: A = jedes Bit verdoppelt (8 Bit); veraendert HL
nib_expand:
        ld hl,nib_tab
        add a,l
        ld l,a
        jr nc,ne_ok
        inc h
ne_ok:
        ld a,(hl)
        ret

; ============================================================
; anykey: Z gesetzt = keine Taste gedrueckt
; ============================================================
anykey:
        xor a
        in a,(0xFE)             ; alle Tastaturreihen gleichzeitig
        cpl
        and 0x1F
        ret

; ============================================================
; cls: Bildschirm loeschen, Attribute weiss auf schwarz
; ============================================================
cls:
        ld hl,0x4000
        ld de,0x4001
        ld bc,0x17FF
        ld (hl),0
        ldir
        ld hl,0x5800
        ld de,0x5801
        ld bc,0x02FF
        ld (hl),ATTR_TEXT
        ldir
        ret

; ============================================================
; Zufallszahlen (16-Bit xorshift)
; ============================================================
seed_init:
        ld hl,(23672)           ; Systemvariable FRAMES
        ld a,r
        xor l
        ld l,a
        ld a,h
        or l
        jr nz,seed_ok
        ld hl,0xACE1            ; Seed darf nicht 0 sein
seed_ok:
        ld (seed),hl
        ret

; out: A = Zufallsbyte; alle anderen Register bleiben erhalten
rnd:
        push hl
        ld hl,(seed)
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
        pop hl
        ret

; ============================================================
; Spielfeld erzeugen
; ============================================================
init_field:
        ld hl,field
        ld c,0                  ; y
if_row:
        ld b,0                  ; x
if_col:
        call tile_for
        ld (hl),a
        cp T_BLOCK
        jr z,if_block
        xor a                   ; nichts versteckt
        jr if_hid
if_block:
        call pick_powerup       ; A = 0 oder Power-Up-Typ
if_hid:
        ld de,HIDDEN_OFF
        add hl,de
        ld (hl),a
        or a
        sbc hl,de
        inc hl
        inc b
        ld a,b
        cp FW
        jr nz,if_col
        inc c
        ld a,c
        cp FH
        jr nz,if_row
        ret

; out: A = 0 (kein Power-Up) oder Typ des Power-Ups in einem Block
; veraendert: A, E
pick_powerup:
        call rnd
        cp PU_CHANCE
        jr nc,pp_none
        call rnd
        ld e,a
        cp 86
        ld a,T_PU_RANGE
        ret c
        ld a,e
        cp 172
        ld a,T_PU_BOMB
        ret c
        ld a,T_PU_SPEED
        ret
pp_none:
        xor a
        ret

; in:  B = x, C = y
; out: A = Kacheltyp
; veraendert: A, DE (BC und HL bleiben erhalten)
tile_for:
        ; Rand
        ld a,b
        or a
        jr z,tf_wall
        cp FW-1
        jr z,tf_wall
        ld a,c
        or a
        jr z,tf_wall
        cp FH-1
        jr z,tf_wall
        ; Saeulen: x und y beide gerade
        ld a,b
        or c
        and 1
        jr z,tf_wall
        ; Ecken freihalten: Abstand zur naechsten Ecke dx+dy <= 3
        ld a,b
        cp FW/2
        jr c,tf_dx
        ld a,FW-1
        sub b
tf_dx:
        ld e,a                  ; dx
        ld a,c
        cp FH/2
        jr c,tf_dy
        ld a,FH-1
        sub c
tf_dy:
        add a,e                 ; dx+dy
        cp 4
        jr c,tf_empty
        ; zufaellig Block oder leer
        call rnd
        cp BLOCK_CHANCE
        jr nc,tf_empty
        ld a,T_BLOCK
        ret
tf_empty:
        xor a                   ; T_EMPTY
        ret
tf_wall:
        ld a,T_WALL
        ret

; in:  B = x, C = y (Kachelkoordinaten)
; out: HL = Adresse der Kachel im Feld (field + y*15 + x)
; veraendert: A, HL (BC und DE bleiben erhalten)
field_addr:
        push de
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; y*16
        ld e,c
        ld d,0
        or a
        sbc hl,de               ; y*15
        ld e,b
        add hl,de               ; + x
        ld de,field
        add hl,de
        pop de
        ret

; ============================================================
; Spielfeld zeichnen
; ============================================================
draw_field:
        ld hl,field
        ld d,0                  ; y
df_row:
        ld e,0                  ; x
df_col:
        ld a,d
        add a,a
        add a,FIELD_ROW
        ld b,a                  ; Zeichenzeile
        ld a,e
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld a,(hl)
        call draw_tile          ; erhaelt BC, DE, HL
        inc hl
        inc e
        ld a,e
        cp FW
        jr nz,df_col
        inc d
        ld a,d
        cp FH
        jr nz,df_row
        ret

; in: B = x, C = y (Kachelkoordinaten)
; zeichnet die Kachel aus dem Spielfeld neu (ohne Spieler)
; erhaelt BC, DE; veraendert A, HL
redraw_tile:
        push bc
        push de
        call field_addr
        ld e,(hl)               ; Kacheltyp
        ld a,c
        add a,a
        add a,FIELD_ROW
        ld d,a                  ; Zeichenzeile
        ld a,b
        add a,a
        add a,FIELD_COL
        ld c,a                  ; Zeichenspalte
        ld b,d
        ld a,e
        call draw_tile
        pop de
        pop bc
        ret

; ============================================================
; draw_tile: eine 16x16-Kachel zeichnen
; in: A = Kacheltyp, B = Zeichenzeile, C = Zeichenspalte
; erhaelt BC, DE, HL
; ============================================================
draw_tile:
        push de
        push hl
        bit 7,a
        jr z,dt_type
        ld a,T_FLAME            ; Flammen-Bytes (0x80+Restdauer) -> Grafik 4
dt_type:
        cp T_BOMB
        jr nz,dt_go
        ld a,(bomb_frame)       ; Bombe: Animationsframe 0 oder 2
        add a,T_BOMB            ; -> Grafik 3 oder 5
dt_go:
        ld e,a
        ld d,0
        ld hl,tile_attr
        add hl,de
        ld a,(hl)
        ld (cur_attr),a         ; Attribut der Kachel
        ld l,e
        ld h,0
        add hl,hl               ; *2
        add hl,hl               ; *4
        add hl,hl               ; *8
        add hl,hl               ; *16
        add hl,hl               ; *32
        ld de,tile_gfx
        add hl,de               ; HL = Grafik der Kachel
        call draw_gfx
        pop hl
        pop de
        ret

; ============================================================
; draw_sprite: Spieler-Sprite zeichnen (Attribut in cur_attr)
; in: A = Richtung, B = Zeichenzeile, C = Zeichenspalte
; erhaelt BC, DE, HL
; ============================================================
draw_sprite:
        push de
        push hl
        ld l,a
        ld h,0
        add hl,hl               ; *2
        add hl,hl               ; *4
        add hl,hl               ; *8
        add hl,hl               ; *16
        add hl,hl               ; *32
        ld de,spr_gfx
        add hl,de
        call draw_gfx
        pop hl
        pop de
        ret

; ============================================================
; draw_gfx: 16x16-Grafik aus 4 Zellen (OL, OR, UL, UR) zeichnen
; in: HL = 32 Bytes Grafik, B = Zeile, C = Spalte, (cur_attr)
; erhaelt BC; HL zeigt danach hinter die Grafik
; ============================================================
draw_gfx:
        call draw_cell          ; oben links
        inc c
        call draw_cell          ; oben rechts
        dec c
        inc b
        call draw_cell          ; unten links
        inc c
        call draw_cell          ; unten rechts
        dec c
        dec b
        ret

; ============================================================
; draw_cell: eine 8x8-Zelle samt Attribut zeichnen
; in: HL = 8 Bytes Grafik, B = Zeile, C = Spalte, (cur_attr)
; out: HL zeigt hinter die 8 Bytes; BC bleibt erhalten
; veraendert: A, DE
; ============================================================
draw_cell:
        push bc
        ; Bildschirmadresse der Zelle
        ld a,b
        and 0x18
        or 0x40
        ld d,a
        ld a,b
        and 7
        rrca
        rrca
        rrca                    ; (Zeile & 7) * 32
        add a,c
        ld e,a
        ld b,8
dc_line:
        ld a,(hl)
        ld (de),a
        inc hl
        inc d
        djnz dc_line
        pop bc
        ; Attributadresse: 0x5800 + Zeile*32 + Spalte
        ld a,b
        rrca
        rrca
        rrca
        ld e,a
        and 3
        or 0x58
        ld d,a
        ld a,e
        and 0xE0
        add a,c
        ld e,a
        ld a,(cur_attr)
        ld (de),a
        ret

; ============================================================
; print_at: Text mit dem ROM-Zeichensatz ausgeben
; in: HL = Text (Ende mit 0), B = Zeile, C = Spalte, (cur_attr)
; ============================================================
print_at:
        ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl               ; *8
        ld de,0x3C00            ; ROM-Zeichensatz (Zeichen 32 liegt bei 0x3D00)
        add hl,de
        call draw_cell
        pop hl
        inc c
        jr print_at

; ============================================================
; Daten
; ============================================================
txt_title:
        db "XBLAST",0
txt_zeit:
        db "ZEIT",0
txt_p1:
        db "P1",0
txt_p2:
        db "P2",0
txt_p1pt:
        db "SPIELER 1 PUNKT",0
txt_p2pt:
        db "SPIELER 2 PUNKT",0
txt_p1win:
        db "SPIELER 1 SIEGT!",0
txt_p2win:
        db "SPIELER 2 SIEGT!",0
txt_draw:
        db "UNENTSCHIEDEN",0
txt_sd:
        db "ENDSPIEL!",0
txt_prompt:
        db "FEUER: WEITER",0
txt_t1:
        db "BOMBEN-DUELL UND MONSTERJAGD",0
txt_t2:
        db "MEHR REICHWEITE",0
txt_t3:
        db "MEHR BOMBEN",0
txt_t4:
        db "SCHNELLER LAUFEN",0
txt_t5:
        db "SPIELER 1: JOYSTICK 1 (6-0)",0
txt_t6:
        db "SPIELER 2: JOYSTICK 2 (1-5)",0
txt_t7:
        db "FEUER = BOMBE LEGEN",0
txt_t8:
        db "SIEGE ZUM SPIELGEWINN:",0
txt_t9:
        db "STICK: HOCH/RUNTER=SPIELART",0
txt_t10:
        db "FEUER = START",0
txt_t11:
        db "SPIELART:",0
txt_t12:
        db "ALLE MONSTER BESIEGEN!",0
txt_m1:
        db "1 SPIELER",0
txt_m2:
        db "2 SPIELER",0
txt_level:
        db "LEVEL",0
txt_lives:
        db "LEBEN",0
txt_enemy:
        db "GEGNER",0
txt_lvl_ok:
        db "LEVEL GESCHAFFT!",0
txt_lost:
        db "LEBEN VERLOREN",0
txt_gameover:
        db "SPIEL VORBEI!",0
txt_blank:
        db "                              ",0

; Titelbuchstaben (Zeichen, Farbe)
title_big:
        db 'X',0x42,'B',0x46,'L',0x44,'A',0x45,'S',0x43,'T',0x47

; Verdopplung der Bits eines Nibbles (fuer big_char)
nib_tab:
        db 0x00,0x03,0x0C,0x0F,0x30,0x33,0x3C,0x3F
        db 0xC0,0xC3,0xCC,0xCF,0xF0,0xF3,0xFC,0xFF

; Startwerte der Spieler: x, y, Richtung, lebt, Verzoegerung, Attribut
; dazu: Reichweite, max. Bomben, Feuer, Spielernummer, Schrittpause
pl_init:
        db 1,1,DIR_DOWN,1,0,ATTR_P1,2,1,0,0,MOVE_DELAY,0
        db FW-2,FH-2,DIR_UP,1,0,ATTR_P2,2,1,0,1,MOVE_DELAY,0

; Schrittweite je Richtung (hoch, rechts, runter, links)
dir_dx:
        db 0,1,0,255
dir_dy:
        db 255,0,1,0

; Attribute je Kacheltyp
tile_attr:
        db 0x01                 ; leer:  blaue Punkte auf schwarz
        db 0x4D                 ; Wand:  hell cyan auf blau
        db 0x7A                 ; Block: rot auf hellweiss (Ziegel)
        db 0x42                 ; Bombe: hell rot auf schwarz
        db 0x56                 ; Flamme: hell gelb auf rot
        db 0x42                 ; Bombe, Frame 2: hell rot auf schwarz
        db 0x4E                 ; Power-Up Reichweite: gelb auf blau
        db 0x57                 ; Power-Up Bombe: weiss auf rot
        db 0x67                 ; Power-Up Tempo: weiss auf gruen

; Kachelgrafiken: je 4 Zellen (oben links, oben rechts,
; unten links, unten rechts) zu 8 Bytes = 32 Bytes
tile_gfx:
        ; leer
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x80
        db 0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        db 0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        ; feste Wand
        db 0xFF,0x80,0xAA,0x95,0xAA,0x95,0xAA,0x95
        db 0xFF,0x01,0xA9,0x55,0xA9,0x55,0xA9,0x55
        db 0xAA,0x95,0xAA,0x95,0xAA,0x95,0x80,0xFF
        db 0xA9,0x55,0xA9,0x55,0xA9,0x55,0x01,0xFF
        ; Block (Ziegel)
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        db 0xFE,0xFE,0xFE,0x00,0xEF,0xEF,0xEF,0x00
        ; Bombe
        db 0x00,0x00,0x00,0x00,0x01,0x07,0x0F,0x19
        db 0x04,0x0A,0x0C,0x30,0xC0,0xE0,0xF0,0xF8
        db 0x1B,0x3B,0x3F,0x1F,0x1F,0x0F,0x07,0x01
        db 0xF8,0xFC,0xFC,0xF8,0xF8,0xF0,0xE0,0x80
        ; Flamme
        db 0x00,0x01,0x01,0x07,0x0B,0x1F,0x37,0x7E
        db 0x00,0x80,0xC0,0xA0,0xF0,0x78,0xEC,0xFC
        db 0x6F,0x3D,0x1F,0x0B,0x07,0x03,0x00,0x00
        db 0xDE,0xF8,0xB8,0xF0,0x60,0xC0,0x80,0x00
        ; Bombe, Frame 2 (aufgeblaeht, Funken anders)
        db 0x00,0x00,0x00,0x00,0x07,0x0F,0x1F,0x31
        db 0x14,0x0C,0x3A,0x40,0xE0,0xF0,0xF8,0xFC
        db 0x37,0x37,0x3F,0x3F,0x3F,0x1F,0x1F,0x07
        db 0xFC,0xFC,0xFC,0xFC,0xFC,0xF8,0xF8,0xE0
        ; Power-Up Reichweite (Stern)
        db 0xFF,0x80,0x81,0x81,0x81,0x83,0x87,0xBF
        db 0xFF,0x01,0x81,0x81,0x81,0xC1,0xE1,0xFD
        db 0xBF,0x87,0x83,0x81,0x81,0x81,0x80,0xFF
        db 0xFD,0xE1,0xC1,0x81,0x81,0x81,0x01,0xFF
        ; Power-Up Bombe
        db 0xFF,0x80,0x80,0x80,0x80,0x80,0x87,0x8F
        db 0xFF,0x01,0x1D,0x19,0x61,0x81,0xC1,0xE1
        db 0x8B,0x8B,0x8F,0x8F,0x87,0x80,0x80,0xFF
        db 0xE1,0xE1,0xE1,0xE1,0xC1,0x01,0x01,0xFF
        ; Power-Up Tempo (Blitz)
        db 0xFF,0x80,0x80,0x80,0x80,0x81,0x83,0x83
        db 0xFF,0x01,0x3D,0x79,0xF1,0xE1,0xFD,0xF9
        db 0x80,0x80,0x80,0x81,0x83,0x86,0x80,0xFF
        db 0x39,0x71,0xE1,0xC1,0x01,0x01,0x01,0xFF

; Spieler-Sprites (Blick hoch, rechts, runter, links), je 32 Bytes
spr_gfx:
        ; Blick hoch
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x1F,0x1F
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xF8,0xF8
        db 0x1F,0x1F,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0xF8,0xF8,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick rechts
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x19
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x38
        db 0x19,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x38,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick runter
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x1A
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x58
        db 0x1A,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x58,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C
        ; Blick links
        db 0x00,0x01,0x03,0x07,0x0F,0x1F,0x18,0x1C
        db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0x18,0x98
        db 0x1C,0x18,0x1F,0x0F,0x0D,0x1D,0x19,0x39
        db 0x98,0x18,0xF8,0xF0,0xB0,0xB8,0x98,0x9C

; Monster-Sprites: Zufalls-Monster (2 Frames), Verfolger (2 Frames)
mon_attr:
        db 0x44,0x46            ; gruen, gelb
mon_gfx:
        ; Zufalls-Monster, Frame 1
        db 0x00,0x00,0x03,0x0F,0x1F,0x3F,0x39,0x39
        db 0x00,0x00,0xC0,0xF0,0xF8,0xFC,0x9C,0x9C
        db 0x3F,0x3F,0x3F,0x3F,0x1F,0x1B,0x31,0x31
        db 0xFC,0xFC,0xFC,0xFC,0xF8,0xD8,0x8C,0x8C
        ; Zufalls-Monster, Frame 2
        db 0x00,0x00,0x03,0x0F,0x1F,0x3F,0x39,0x39
        db 0x00,0x00,0xC0,0xF0,0xF8,0xFC,0x9C,0x9C
        db 0x3F,0x3F,0x3F,0x3F,0x1F,0x1E,0x0C,0x18
        db 0xFC,0xFC,0xFC,0xFC,0xF8,0x78,0x30,0x18
        ; Verfolger, Frame 1
        db 0x21,0x33,0x3F,0x7F,0x7F,0x77,0x63,0x77
        db 0x84,0xCC,0xFC,0xFE,0xFE,0xDE,0x8E,0xDE
        db 0x7F,0x7F,0x7F,0x7F,0x7F,0x6E,0x46,0x00
        db 0xFE,0xFE,0xFE,0xFE,0xFE,0x76,0x62,0x00
        ; Verfolger, Frame 2
        db 0x21,0x33,0x3F,0x7F,0x7F,0x77,0x63,0x77
        db 0x84,0xCC,0xFC,0xFE,0xFE,0xDE,0x8E,0xDE
        db 0x7F,0x7F,0x7F,0x7F,0x7F,0x76,0x22,0x00
        db 0xFE,0xFE,0xFE,0xFE,0xFE,0x6E,0x44,0x00

        end start
