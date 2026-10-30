; ============================================================
; XBlast fuer den ZX Spectrum - Stufe 8: Feinschliff
; Assembler: pasmo   (pasmo --tapbas xblast.asm xblast.tap)
; ============================================================
; Zwei Fassungen aus einer Quelle (Konstante AY128 weiter unten):
;   AY128 = 0 : 48K mit Beeper-Sound        -> xblast.tap
;   AY128 = 1 : 128K mit AY-Musik und Effekten -> xblastpro.tap
; Der Beeper spielt pro Frame nur einen kurzen Ton-Burst, so bleibt das
; Spiel im 50-Hz-Takt. Im Titelbild schaltet die Taste T die Lautstaerke
; durch: 5 Stufen und Aus.
;
; Stufe 8: Power-Up-Anzeige in Zeile 1 (Symbole fuer Reichweite, Bomben,
; Tempo mit Zaehler), vier Feldlayouts mit Namen, Serienstand und Level-Rekord
; im Titelbild (gelten nur fuer die laufende Sitzung).
;
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
AY128       equ 1               ; 0 = 48K Beeper, 1 = 128K AY (siehe Kopf)
FW          equ 15              ; Feldbreite in Kacheln
LAY_COUNT   equ 13              ; Layouts: 0-3 zufaellig, 4-12 gebaut
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
T_EXIT      equ 9               ; Ausgang (Einzelspieler, erscheint nach dem letzten Monster)
PU_CHANCE   equ 64              ; Anteil der Bloecke mit Power-Up (von 256)
MAX_RANGE   equ 6               ; Obergrenzen
MAX_PBOMBS  equ 5
MIN_DELAY   equ 4               ; schnellster Schritt (Frames Pause)
; Flammen stehen als 0x80 + Restdauer im Feld (Bit 7 = Flamme)
FLAME_TICKS equ 15              ; Flammendauer in Frames (0,3 Sekunden)
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
; Sound
SFX_PLACE   equ 1               ; Effekte (Nummer = Prioritaet)
SFX_MENU    equ 2
SFX_POWERUP equ 3
SFX_MONSTER equ 4
SFX_EXPLODE equ 5
SFX_DIE     equ 6
SONG_TITLE  equ 0               ; Songs
SONG_GAME   equ 1
SONG_WIN    equ 2
SONG_LOSE   equ 3
NOTE_OFF    equ 254             ; Ton aus
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
; Sound-Variablen
snd_on      equ VARS + 0x2D0    ; 1 = Ton an
song_id     equ VARS + 0x2D1    ; laufender Song (255 = keiner)
song_beg    equ VARS + 0x2D2    ; 2 Bytes: Songanfang
song_ptr    equ VARS + 0x2D4    ; 2 Bytes: naechste Zeile
song_rl     equ VARS + 0x2D6    ; Frames je Zeile
song_cnt    equ VARS + 0x2D7    ; Frames bis zur naechsten Zeile
song_loop   equ VARS + 0x2D8
song_par    equ VARS + 0x2D9    ; 48K: Burst-Verkuerzung, 128K: leiser
ev_a        equ VARS + 0x2DA    ; Ereignisse der aktuellen Zeile (0 = keins)
ev_b        equ VARS + 0x2DB
ev_c        equ VARS + 0x2DC
sfx_pri     equ VARS + 0x2DD    ; Prioritaet des laufenden Effekts
sfx_cnt     equ VARS + 0x2DE    ; verbleibende Frames des Effekts
sfx_ptr     equ VARS + 0x2DF    ; 2 Bytes
bp_note     equ VARS + 0x2E1    ; 48K: aktuelle Note
ay_vol_a    equ VARS + 0x2E2    ; 128K: Lautstaerke Melodie
ay_vol_b    equ VARS + 0x2E3    ; 128K: Lautstaerke Bass
ay_per_a    equ VARS + 0x2E4    ; 2 Bytes: Tonperiode Melodie
ay_per_b    equ VARS + 0x2E6    ; 2 Bytes: Tonperiode Bass
m_prev      equ VARS + 0x2E8    ; Taste M im letzten Frame
snd_fc      equ VARS + 0x2E9    ; Frame-Zaehler fuer das Ausklingen
snd_vol     equ VARS + 0x2EA    ; Lautstaerke 0 (aus) .. 5
snd_att     equ VARS + 0x2EB    ; 128K: Abzug von der AY-Lautstaerke
layout      equ VARS + 0x2EC    ; Feldlayout 0..3
mw1         equ VARS + 0x2ED    ; gewonnene Spiele Spieler 1 (Sitzung)
mw2         equ VARS + 0x2EE    ; gewonnene Spiele Spieler 2 (Sitzung)
best_level  equ VARS + 0x2EF    ; Einzelspieler: bestes Level der Sitzung
exit_on     equ VARS + 0x2F0    ; 1 = Ausgang ist offen
pts         equ VARS + 0x2F1    ; 2 Bytes: Punkte (Einzelspieler)
best_pts    equ VARS + 0x2F3    ; 2 Bytes: Punkte-Rekord der Sitzung
title_cnt   equ VARS + 0x2F5    ; Titelbild: Frame-Zaehler fuer die Bombenanimation
ay_regs     equ VARS + 0x360    ; 13 Bytes: Schattenregister des AY
mons        equ VARS + 0x330    ; MAX_MON * MS_SIZE Bytes
bigbuf      equ VARS + 0x300    ; 32 Bytes: grosses Zeichen (2x2 Zellen)
bombs       equ VARS + 0xC0     ; MAX_BOMBS * BS_SIZE Bytes
pl1         equ VARS + 0x100    ; Spieler 1
pl2         equ pl1 + PS_SIZE   ; Spieler 2

; ============================================================
; Programmstart
; ============================================================
start:
        IF AY128
        ; 128K: 48K-BASIC-ROM einblenden, denn print_at liest den Zeichensatz
        ; bei 0x3D00 (je nach Start liegt sonst der Editor-ROM 0 dort).
        ; Zuerst 0x1FFD (+2A/+3: ROM 3), dann 0x7FFD (ROM-Bit 4 = 1).
        di
        ld bc,0x1FFD
        ld a,0x04
        out (c),a
        ld bc,0x7FFD
        ld a,0x10
        out (c),a
        ei
        ENDIF
        xor a
        out (0xFE),a            ; Rand schwarz
        call seed_init
        call snd_init
        xor a
        ld (mw1),a
        ld (mw2),a
        ld (best_level),a
        ld (best_pts),a
        ld (best_pts+1),a
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
        ld hl,0
        ld (pts),hl
st_rl:  call rnd
        and 15
        cp LAY_COUNT
        jr nc,st_rl
        ld (layout),a           ; erstes Layout zufaellig

next_round:
        call pick_layout
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
        call show_layout
        call show_hud
        ld a,SONG_GAME
        call snd_song

; ---- Hauptschleife: ein Durchlauf pro Frame (50 Hz) -------
game_loop:
        halt
        call rnd                ; Zufallsgenerator weiterdrehen
        call snd_tick           ; Sound: einen Frame weiter
        ld a,0x7F
        in a,(0xFE)             ; Reihe B-N-M-Symbol-Leertaste
        rra                     ; Carry = Leertaste (0 = gedrueckt)
        jp nc,title             ; Leertaste: abbrechen
        ld a,0xDF
        in a,(0xFE)             ; Reihe P-O-I-U-Y
        and 1
        call z,pause_game       ; P: Pause
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
        cp T_EXIT
        jr z,up_done            ; Ausgang bleibt liegen
        cp 0x80
        jr nc,up_done           ; Flamme
        ld (hl),T_EMPTY         ; Power-Up verschwindet von der Kachel
        call take_powerup
        call show_hud_ix        ; Anzeige in Zeile 1 aktualisieren
up_done:
        jp draw_players
up_blocked:
        jp draw_player          ; nur die Blickrichtung hat sich evtl. geaendert

; in: IX = Spieler, A = Power-Up-Typ
take_powerup:
        push af
        ld a,SFX_POWERUP
        call snd_sfx
        pop af
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
        ld a,SFX_PLACE          ; bis sie die Kachel verlaesst
        jp snd_sfx

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
        cp T_EXIT
        jr z,ex_stop            ; der Ausgang ist unzerstoerbar
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
        ld a,SFX_EXPLODE
        jp snd_sfx

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
        ld a,SFX_DIE
        call snd_sfx
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
        push de
        ld de,100               ; Punkte: 100, Verfolger 200
        ld a,(ix+MTYPE)
        or a
        jr z,cmh_pts
        ld de,200
cmh_pts:
        call add_pts
        pop de
        ld a,SFX_MONSTER
        call snd_sfx
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
        ld a,SFX_DIE
        call snd_sfx
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
        ld (exit_on),a
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
        jp nc,rl_over
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
        ld a,SONG_WIN           ; Fanfare (snd_song erhaelt alle Register)
        call snd_song
        inc (hl)
        ld a,(hl)
        push hl                 ; Zeiger auf score1 / score2 merken
        ld hl,wins_needed
        cp (hl)
        pop hl
        jr c,rl_round           ; noch nicht genug Siege
        ld a,1
        ld (match_over),a
        ld a,l                  ; Spielgewinn der Sitzung zaehlen
        ld hl,mw1
        cp score1 & 255
        jr z,rl_mw
        inc hl                  ; mw2 liegt direkt hinter mw1
rl_mw:
        inc (hl)
        ld h,b                  ; Text: "SPIELER n SIEGT!"
        ld l,c
        jr rl_show
rl_round:
        ex de,hl                ; Text: "SPIELER n PUNKT"
        jr rl_show
rl_draw:
        ld a,SONG_LOSE          ; Unentschieden: kurzer Jingle
        call snd_song
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
        jp nz,rl_nc
        ld a,(match_over)
        or a
        jr nz,rl_prompt
        scf                     ; naechste Runde startet von selbst (nur nach Spielende: FEUER)
        ret
rl_prompt:
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
        ld a,(exit_on)
        or a
        jp z,place_exit         ; alle Monster tot: Ausgang oeffnen
        ld a,(pl1+PX)
        ld b,a
        ld a,(pl1+PY)
        ld c,a
        call field_addr
        ld a,(hl)
        cp T_EXIT
        jp nz,rl_nc             ; Spieler steht noch nicht im Ausgang
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
        ld de,500               ; Bonus fuers Level
        call add_pts
        ld a,(level)            ; Ausgang erreicht: naechstes Level
        cp MAX_LEVEL
        jr nc,r1_ok
        inc a
        ld (level),a
        call upd_level          ; Punkte-Rekord zaehlt erst am Spielende
r1_ok:
        ld a,SONG_WIN
        call snd_song
        ld hl,txt_lvl_ok
        jp rl_show
r1_dead:
        ld hl,lives
        dec (hl)
        jr nz,r1_life
        ld a,1
        ld (match_over),a       ; alle Leben weg: Spiel vorbei
        ld de,txt_gameover
        call is_record          ; Carry = mehr Punkte als der Rekord
        jr nc,r1_go
        ld de,txt_record
r1_go:
        push de
        call upd_best
        ld a,SONG_LOSE
        call snd_song
        pop hl
        jp rl_show
r1_life:
        ld a,SONG_LOSE          ; Jingle: Leben verloren
        call snd_song
        ld hl,txt_lost
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
        ld bc,1*256+10
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
        call print_digit
        ld hl,txt_pkt
        ld bc,1*256+23
        ld a,ATTR_TEXT
        call put_text
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld hl,(pts)
        ld bc,1*256+26
        jp print_num5

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
        ld a,SFX_DIE
        jp snd_sfx

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
        ld a,SONG_TITLE
        call snd_song
ts_rel:
        call any_fire           ; erst warten, bis kein Feuer mehr gehalten wird
        jr nz,ts_rel
        xor a
        ld (menu_prev),a
ts_loop:
        halt
        call rnd
        call snd_tick
        ld hl,title_cnt
        inc (hl)
        ld a,(hl)
        and 15
        jr nz,ts_noanim
        ld a,(bomb_frame)       ; Bombe neben dem Titel pulsiert
        xor 2
        ld (bomb_frame),a
        ld a,T_BOMB
        ld bc,2*256+6
        call draw_tile
ts_noanim:
        call check_mute
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
        ld a,SFX_MENU
        call snd_sfx
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
        ld a,SFX_MENU
        call snd_sfx
        call show_menu
        jr ts_loop

; Spielart (Zeile 19) und Siege bzw. Hinweis (Zeile 20) anzeigen
show_menu:
        call show_session       ; Zeile 7: Serienstand / Rekord
        ld hl,txt_vol           ; Zeile 22: Lautstaerke
        ld bc,22*256+9
        ld a,ATTR_TEXT
        call put_text
        ld a,(snd_vol)
        or a
        ld hl,txt_aus
        ld bc,22*256+18
        ld a,ATTR_TITLE
        jr z,sm_vol_txt
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld a,(snd_vol)
        ld bc,22*256+18
        call print_digit
        ld hl,txt_von5
        ld bc,22*256+19
        ld a,ATTR_TITLE
sm_vol_txt:
        call put_text
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
        xor a
        ld (bomb_frame),a       ; Bombe startet im ersten Animationsframe
        ld (title_cnt),a
        ld a,T_BOMB
        ld bc,2*256+6
        call draw_tile
        ld a,T_FLAME
        ld bc,2*256+24
        call draw_tile
        ld hl,txt_t1
        ld bc,5*256+2
        ld a,ATTR_TEXT
        call put_text
        ; Legende der Power-Ups
        ld a,T_PU_RANGE
        ld bc,9*256+6
        call draw_tile
        ld hl,txt_t2
        ld bc,9*256+9
        ld a,ATTR_TEXT
        call put_text
        ld a,T_PU_BOMB
        ld bc,11*256+6
        call draw_tile
        ld hl,txt_t3
        ld bc,11*256+9
        ld a,ATTR_TEXT
        call put_text
        ld a,T_PU_SPEED
        ld bc,13*256+6
        call draw_tile
        ld hl,txt_t4
        ld bc,13*256+9
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
        ld hl,txt_t12p
        ld bc,17*256+22
        ld a,ATTR_TEXT
        call put_text
        ; Menue (Zeilen 19/20 zeichnet show_menu)
        ld hl,txt_t9
        ld bc,21*256+3
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
        ld a,(layout)
        cp 4
        jr nc,tf_hand           ; gebautes Level
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
        ; Saeulen: x und y beide gerade (Layout 2: nur jede zweite Diagonale)
        ld a,b
        or c
        and 1
        jr nz,tf_nopillar
        ld a,(layout)
        cp 2
        jr nz,tf_wall
        ld a,b
        add a,c
        and 3
        jr z,tf_wall
tf_nopillar:
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
        ; Layout 3 (Kreuzweg): mittlere Spalte und Zeile bleiben frei
        ld a,(layout)
        cp 3
        jr nz,tf_rnd
        ld a,b
        cp FW/2
        jr z,tf_empty
        ld a,c
        cp FH/2
        jr z,tf_empty
tf_rnd:
        ; zufaellig Block oder leer, Dichte je nach Layout
        call rnd
        ld e,a
        ld d,BLOCK_CHANCE
        ld a,(layout)
        cp 1
        jr nz,tf_d2
        ld d,225                ; dichter Wald
tf_d2:
        cp 2
        jr nz,tf_d3
        ld d,140                ; offene Halle
tf_d3:
        cp 3
        jr nz,tf_d4
        ld d,190                ; Kreuzweg
tf_d4:
        ld a,e
        cp d
        jr nc,tf_empty
        ld a,T_BLOCK
        ret
tf_empty:
        xor a                   ; T_EMPTY
        ret
tf_wall:
        ld a,T_WALL
        ret
; gebautes Level: Zeichen aus der Textkarte lesen (# Wand, o Block, sonst leer)
tf_hand:
        sub 4
        add a,a
        ld e,a
        ld d,0
        push hl
        ld hl,map_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = Kartenanfang
        ld l,c
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; 16*y
        push de
        ld e,c
        ld d,0
        or a
        sbc hl,de               ; 15*y
        ld e,b
        add hl,de               ; + x
        pop de
        add hl,de
        ld a,(hl)
        pop hl
        cp "#"
        jr z,tf_wall
        cp "o"
        jr z,tf_blk
        xor a
        ret
tf_blk:
        ld a,T_BLOCK
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
; Stufe 8: Layouts, Power-Up-Anzeige, Sitzungsstatistik
; ============================================================
; Layout fuer die kommende Runde: Einzelspieler nach Level,
; Zwei Spieler reihum
pick_layout:
        call rnd
        and 3
        jr nz,pl_built          ; 3 von 4 Runden: gebautes Level
        call rnd
        and 3                   ; 1 von 4 Runden: Zufallslayout 0-3
        jr pl_chk
pl_built:
        call rnd
        and 15
        cp 9
        jr nc,pl_built
        add a,4                 ; zufaellig eines der 9 gebauten Level
pl_chk:
        ld hl,layout
        cp (hl)
        jr z,pick_layout        ; nie zweimal hintereinander dasselbe
        ld (hl),a
        ret

; Name des Layouts in Zeile 1 (Mitte)
show_layout:
        ld a,(layout)
        add a,a
        ld e,a
        ld d,0
        ld hl,layout_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,1*256+10
        ld a,ATTR_TEXT
        jp put_text

; Power-Up-Anzeige beider Spieler (Zeile 1: P1 links, P2 rechts)
show_hud:
        ld ix,pl1
        call show_hud_ix
        ld a,(game_mode)
        or a
        ret z                   ; Einzelspieler: nur Spieler 1
        ld ix,pl2
; in: IX = Spieler; Anzeige: Symbol + Ziffer fuer Reichweite, Bomben und
; Tempo-Stufe (8 Zellen in Zeile 1, Spieler 1 ab Spalte 1, Spieler 2 ab 23)
show_hud_ix:
        ld c,1
        ld a,(ix+POWNER)
        or a
        jr z,hud_go
        ld c,23
hud_go:
        ld b,1
        ld hl,gl_range
        ld d,0x46               ; gelb
        ld e,(ix+PRANGE)
        call hud_item
        ld hl,gl_bomb
        ld d,0x42               ; rot
        ld e,(ix+PMAXB)
        call hud_item
        ld hl,gl_speed
        ld d,0x44               ; gruen
        ld a,MOVE_DELAY
        sub (ix+PSPEED)
        ld e,a
; in: HL = 8-Byte-Symbol, D = Symbol-Attribut, E = Wert, B/C = Zeile/Spalte,
; IX = Spieler; zeichnet Symbol und Ziffer, C zeigt danach 3 Spalten weiter
hud_item:
        push bc
        push de
        ld a,d
        ld (cur_attr),a
        call draw_cell          ; Symbol (erhaelt BC)
        pop de
        pop bc
        inc c
        push bc
        ld a,(ix+PATTR)
        ld (cur_attr),a         ; Ziffer in der Farbe des Spielers
        ld a,e
        call print_digit
        pop bc
        inc c
        inc c
        ret

; Symbole fuer die Anzeige (8x8)
gl_range:
        db 0x18,0x18,0x3C,0xFF,0xFF,0x3C,0x18,0x18
gl_bomb:
        db 0x02,0x04,0x1C,0x3E,0x3E,0x3E,0x1C,0x00
gl_speed:
        db 0x06,0x0C,0x18,0x3E,0x0C,0x18,0x30,0x40

; Einzelspieler: Level-Rekord der Sitzung nachziehen
upd_best:
        call is_record
        jr nc,ub_lvl
        ld hl,(pts)
        ld (best_pts),hl
upd_level:
ub_lvl:
        ld a,(level)
        ld hl,best_level
        cp (hl)
        ret c
        ld (hl),a
        ret

; out: Carry = pts > best_pts; erhaelt DE, BC
is_record:
        ld hl,(best_pts)
        ld a,(pts)
        sub l
        ld a,(pts+1)
        sbc a,h
        jr nc,ir_ge             ; pts >= best_pts
        and a
        ret
ir_ge:
        ld a,(pts)
        cp l
        jr nz,ir_yes
        ld a,(pts+1)
        cp h
        jr nz,ir_yes
        and a                   ; gleich: kein neuer Rekord
        ret
ir_yes:
        scf
        ret

; in: DE = Punkte; addiert zu pts (Deckel 65535); veraendert A, HL
add_pts:
        ld hl,(pts)
        add hl,de
        jr nc,ap_ok
        ld hl,65535
ap_ok:
        ld (pts),hl
        ret

; in: HL = Wert 0..65535, B = Zeile, C = Spalte der ersten Ziffer, (cur_attr)
; schreibt 5 Ziffern (mit fuehrenden Nullen); veraendert A, DE, HL
print_num5:
        push ix                 ; IX gehoert dem Aufrufer (Monsterschleife)
        push bc
        ld ix,bigbuf+16         ; Textpuffer
        push ix
        ld de,10000
        call pn5_dig
        ld de,1000
        call pn5_dig
        ld de,100
        call pn5_dig
        ld de,10
        call pn5_dig
        ld a,l
        add a,'0'
        ld (ix+0),a
        ld (ix+1),0
        pop hl
        pop bc
        pop ix
        jp print_at
pn5_dig:
        ld a,'0'-1
pn5_sub:
        inc a
        or a
        sbc hl,de
        jr nc,pn5_sub
        add hl,de
        ld (ix+0),a
        inc ix
        ret

; Ausgang an einer zufaelligen leeren Kachel oeffnen (Einzelspieler)
; Carry = 0 beim Rueckkehr (Rundenlogik laeuft weiter)
place_exit:
        ld e,200                ; Versuche
pe_try:
        call rnd
        and 15
        cp 13
        jr nc,pe_try
        inc a
        ld b,a                  ; x = 1..13
pe_y:
        call rnd
        and 15
        cp 9
        jr nc,pe_y
        inc a
        ld c,a                  ; y = 1..9
        call field_addr
        ld a,(hl)
        or a
        jr nz,pe_next           ; nur leere Kacheln
        ld a,e
        cp 100
        jr c,pe_ok              ; nach 100 Versuchen nicht mehr waehlerisch
        ld a,(pl1+PX)           ; Abstand zum Spieler mindestens 4
        sub b
        jr nc,pe_dx
        neg
pe_dx:
        ld d,a
        ld a,(pl1+PY)
        sub c
        jr nc,pe_dy
        neg
pe_dy:
        add a,d
        cp 4
        jr nc,pe_ok
pe_next:
        dec e
        jr nz,pe_try
        and a
        ret                     ; nichts gefunden: naechster Frame neuer Versuch
pe_ok:
        ld (hl),T_EXIT
        call redraw_tile
        ld a,1
        ld (exit_on),a
        ld a,SFX_POWERUP
        call snd_sfx
        ld hl,txt_exit
        ld bc,1*256+10
        ld a,ATTR_TITLE
        call put_text
        and a
        ret

; P: Spiel anhalten; P erneut = weiter, Leertaste = zum Titel
pause_game:
        xor a
        out (0xFE),a
        IF AY128
        call ay_reset           ; Ton stumm schalten
        ENDIF
        ld hl,txt_pause
        ld bc,1*256+10
        ld a,ATTR_TITLE
        call put_text
pg_rel:
        halt
        ld a,0xDF
        in a,(0xFE)
        and 1
        jr z,pg_rel             ; P loslassen
pg_wait:
        halt
        ld a,0x7F
        in a,(0xFE)
        rra
        jr nc,pg_quit           ; Leertaste: Spiel beenden
        ld a,0xDF
        in a,(0xFE)
        and 1
        jr nz,pg_wait
pg_rel2:
        halt
        ld a,0xDF
        in a,(0xFE)
        and 1
        jr z,pg_rel2
        ld a,(sd_active)
        or a
        jr z,pg_nosd
        ld hl,txt_sd
        ld bc,1*256+10
        ld a,ATTR_DEAD
        jp put_text
pg_nosd:
        ld a,(exit_on)
        or a
        jp z,show_layout
        ld hl,txt_exit
        ld bc,1*256+10
        ld a,ATTR_TITLE
        jp put_text
pg_quit:
        pop af                  ; Ruecksprung verwerfen
        jp title

; Titelbild, Zeile 7: Serienstand (2 Spieler) oder Level-Rekord (1 Spieler)
show_session:
        ld hl,txt_blank
        ld bc,7*256+1
        ld a,ATTR_TEXT
        call put_text
        ld a,(game_mode)
        or a
        jr z,ss_one
        ld hl,txt_serie
        ld bc,7*256+6
        ld a,ATTR_TEXT
        call put_text
        ld hl,txt_p1
        ld bc,7*256+13
        ld a,ATTR_P1
        call put_text
        ld a,(mw1)
        ld b,7
        ld c,16
        call show_cnt1
        ld hl,txt_colon
        ld bc,7*256+18
        ld a,ATTR_TEXT
        call put_text
        ld a,(mw2)
        ld b,7
        ld c,20
        ld hl,txt_p2
        push af
        push bc
        ld bc,7*256+22
        ld a,ATTR_P2
        call put_text
        pop bc
        pop af
        jr show_cnt2
ss_one:
        ld a,(best_level)
        or a
        ret z                   ; noch kein Rekord
        ld hl,txt_rekord
        ld bc,7*256+4
        ld a,ATTR_TEXT
        call put_text
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld a,(best_level)
        ld b,7
        ld c,18
        call print_digit
        ld hl,(best_pts)
        ld bc,7*256+21
        call print_num5
        ld hl,txt_pkt
        ld bc,7*256+27
        ld a,ATTR_TEXT
        jp put_text

; in: A = Zaehler, B/C = Zeile/Spalte; Ziffer in der Farbe von Spieler 1 bzw. 2
show_cnt1:
        ld d,ATTR_P1
        jr show_cnt
show_cnt2:
        ld d,ATTR_P2
show_cnt:
        cp 10
        jr c,sc_ok
        ld a,9                  ; mehr als eine Stelle: bei 9 deckeln
sc_ok:
        ld e,a
        ld a,d
        ld (cur_attr),a
        ld a,e
        jp print_digit

; ============================================================
; Sound
; ============================================================
; Gemeinsamer Kern: Songs sind Zeilen zu je 3 Bytes (Melodie, Bass,
; Schlagzeug); song_step liefert pro Frame die Ereignisse ev_a/b/c.
; Effekte laufen auf eigener Spur (128K: Kanal C, 48K: Vorrang vor Musik).

snd_init:
        ld hl,snd_on
        ld de,snd_on+1
        ld bc,0x19
        ld (hl),0
        ldir                    ; alle Sound-Variablen auf 0
        ld a,1
        ld (snd_on),a
        ld a,5
        ld (snd_vol),a          ; volle Lautstaerke
        xor a
        ld (snd_att),a
        ld a,0xFF
        ld (song_id),a
        IF AY128
        jp ay_reset
        ELSE
        ret
        ENDIF

; in: A = Songnummer; erhaelt alle Register
snd_song:
        push af
        push bc
        push de
        push hl
        ld b,a
        ld a,(snd_on)
        or a
        jr z,sn_done
        ld a,b
        ld (song_id),a
        ld c,a
        add a,a
        add a,a
        add a,c                 ; * 5 Bytes je Eintrag
        ld e,a
        ld d,0
        ld hl,song_tab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (song_beg),de
        ld (song_ptr),de
        ld a,(hl)
        ld (song_rl),a
        inc hl
        ld a,(hl)
        ld (song_loop),a
        inc hl
        ld a,(hl)
        ld (song_par),a
        ld a,1
        ld (song_cnt),a         ; erste Zeile sofort
        xor a
        IF AY128
        ld (ay_vol_a),a
        ld (ay_vol_b),a
        ELSE
        ld (bp_note),a
        ENDIF
sn_done:
        pop hl
        pop de
        pop bc
        pop af
        ret

; in: A = Effektnummer (= Prioritaet); erhaelt alle Register
snd_sfx:
        push af
        push bc
        push de
        push hl
        ld b,a
        ld a,(snd_on)
        or a
        jr z,sx_done
        ld e,b
        ld d,0
        ld hl,sfx_tab
        add hl,de
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = Effektdaten
        call sfx_start
sx_done:
        pop hl
        pop de
        pop bc
        pop af
        ret

; in: DE = Effektdaten (1. Byte = Frames), B = Prioritaet
; startet den Effekt, wenn kein wichtigerer laeuft
sfx_start:
        ld a,(sfx_cnt)
        or a
        jr z,ss_go
        ld a,(sfx_pri)
        cp b
        jr z,ss_go
        ret nc                  ; laufender Effekt ist wichtiger
ss_go:
        ld a,b
        ld (sfx_pri),a
        ld a,(de)
        ld (sfx_cnt),a
        inc de
        ld (sfx_ptr),de
        ret

; Lautstaerke eine Stufe weiter: 1 .. 5, dann Aus, dann wieder 1
snd_cycle:
        ld a,(snd_vol)
        inc a
        cp 6
        jr c,sc_set
        xor a
sc_set:
        ld (snd_vol),a
        ld e,a
        ld d,0
        ld hl,snd_att_tab
        add hl,de
        ld a,(hl)
        ld (snd_att),a
        ld a,(snd_vol)
        or a
        jr z,sc_off
        ld a,1
        ld (snd_on),a
        ret
sc_off:
        ld (snd_on),a           ; A = 0: alles stumm
        ld (sfx_cnt),a
        ld (bp_note),a
        ld a,0xFF
        ld (song_id),a
        IF AY128
        jp ay_reset
        ELSE
        ret
        ENDIF

; Abzug je Lautstaerkestufe (0 = aus, 1 .. 5) von der AY-Lautstaerke
snd_att_tab:
        db 0,9,6,4,2,0

; Taste T abfragen (Flanke): Lautstaerke weiterschalten, Anzeige aktualisieren
check_mute:
        ld a,0xFB
        in a,(0xFE)             ; Reihe Q W E R T
        cpl
        and 0x10                ; NZ = T gedrueckt
        ld hl,m_prev
        ld b,(hl)
        ld (hl),a
        ld c,a
        ld a,b
        cpl
        and c                   ; neu gedrueckt?
        ret z
        call snd_cycle
        ld a,(snd_vol)
        cp 1
        jr nz,cm_blip
        ld a,SONG_TITLE         ; aus Aus kommend: Titelmelodie von vorn
        call snd_song
        jr cm_show
cm_blip:
        ld a,SFX_MENU           ; hoerbare Probe der neuen Lautstaerke
        call snd_sfx
cm_show:
        jp show_menu

; einmal pro Frame direkt nach HALT aufrufen
snd_tick:
        ld a,(snd_on)
        or a
        ret z
        ld hl,snd_fc
        inc (hl)
        call song_step
        IF AY128
        jp ay_update
        ELSE
        jp bp_update
        ENDIF

; liest bei Bedarf die naechste Songzeile -> ev_a, ev_b, ev_c
song_step:
        xor a
        ld (ev_a),a
        ld (ev_b),a
        ld (ev_c),a
        ld a,(song_id)
        cp 0xFF
        ret z                   ; kein Song
        ld hl,song_cnt
        dec (hl)
        ret nz
        ld a,(song_rl)
        ld (hl),a
ss_fetch:
        ld hl,(song_ptr)
        ld a,(hl)
        cp 0xFF
        jr z,ss_end
        ld (ev_a),a
        inc hl
        ld a,(hl)
        ld (ev_b),a
        inc hl
        ld a,(hl)
        ld (ev_c),a
        inc hl
        ld (song_ptr),hl
        ret
ss_end:
        ld a,(song_loop)
        or a
        jr z,ss_stop
        ld hl,(song_beg)        ; Schleife: von vorn
        ld (song_ptr),hl
        jr ss_fetch
ss_stop:
        ld a,0xFF
        ld (song_id),a
        ld a,NOTE_OFF
        ld (ev_a),a
        ld (ev_b),a
        ret

IF AY128
; ------------------------------------------------------------
; 128K: AY-3-8912. Kanal A = Melodie, B = Bass, C = Schlagzeug/Effekte
; ------------------------------------------------------------
ay_update:
        ; --- Melodie (Kanal A)
        ld a,(ev_a)
        or a
        jr z,au_b
        cp NOTE_OFF
        jr z,au_a_off
        call ay_period
        ld (ay_per_a),hl
        ld a,13
        ld (ay_vol_a),a
        jr au_b
au_a_off:
        xor a
        ld (ay_vol_a),a
        ; --- Bass (Kanal B)
au_b:
        ld a,(ev_b)
        or a
        jr z,au_decay
        cp NOTE_OFF
        jr z,au_b_off
        call ay_period
        ld (ay_per_b),hl
        ld a,12
        ld (ay_vol_b),a
        jr au_decay
au_b_off:
        xor a
        ld (ay_vol_b),a
        ; --- Lautstaerke klingt alle 4 Frames bis 9 aus
au_decay:
        ld a,(snd_fc)
        and 3
        jr nz,au_drum
        ld a,(ay_vol_a)
        cp 10
        jr c,au_d1
        dec a
        ld (ay_vol_a),a
au_d1:
        ld a,(ay_vol_b)
        cp 10
        jr c,au_drum
        dec a
        ld (ay_vol_b),a
        ; --- Schlagzeug-Ereignis startet einen Effekt auf Kanal C
au_drum:
        ld a,(ev_c)
        or a
        jr z,au_c
        ld hl,dr_tab-2
        ld e,a
        ld d,0
        add hl,de
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld b,0                  ; Prioritaet 0: Effekte gehen vor
        call sfx_start
        ; --- Kanal C: Effekt oder Schlagzeug weiterlaufen lassen
au_c:
        ld a,(sfx_cnt)
        or a
        jr z,au_c_off
        dec a
        ld (sfx_cnt),a
        ld hl,(sfx_ptr)
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = Tonperiode (0 = kein Ton)
        inc hl
        ld c,(hl)               ; C = Rauschen (0 = keins)
        inc hl
        ld b,(hl)               ; B = Lautstaerke
        inc hl
        ld (sfx_ptr),hl
        ld a,e
        ld (ay_regs+4),a
        ld a,d
        ld (ay_regs+5),a
        ld a,c
        ld (ay_regs+6),a
        ld a,(snd_att)          ; Gesamtlautstaerke: Abzug von der Effekt-Lautstaerke
        ld l,a
        ld a,b
        sub l
        jr nc,au_cv
        xor a
au_cv:
        ld (ay_regs+10),a
        ld a,d                  ; Mixer: Ton C nur mit Tonperiode, Rauschen C nur mit Rauschen
        or e
        ld a,0x3C
        jr z,au_nt
        and 0xFB
au_nt:
        ld l,a
        ld a,c
        or a
        ld a,l
        jr z,au_nn
        and 0xDF
au_nn:
        ld (ay_regs+7),a
        jr au_vol
au_c_off:
        xor a
        ld (ay_regs+10),a
        ld a,0x3C
        ld (ay_regs+7),a
        ; --- Lautstaerke (mit Song-Abzug) und Tonperioden in die Register
au_vol:
        ld a,(song_par)
        ld c,a
        ld a,(snd_att)
        add a,c
        ld c,a                  ; Abzug = Song + Gesamtlautstaerke
        ld a,(sfx_cnt)
        or a
        jr z,au_noduck
        ld a,(sfx_pri)
        cp SFX_EXPLODE
        jr c,au_noduck
        ld a,c                  ; Explosion/Tod: Musik 4 Stufen leiser, der Peng steht vorn
        add a,4
        ld c,a
au_noduck:
        ld a,(ay_vol_a)
        sub c
        jr nc,au_va
        xor a
au_va:
        ld (ay_regs+8),a
        ld a,(ay_vol_b)
        sub c
        jr nc,au_vb
        xor a
au_vb:
        ld (ay_regs+9),a
        ld hl,(ay_per_a)
        ld (ay_regs),hl
        ld hl,(ay_per_b)
        ld (ay_regs+2),hl
        ; weiter mit ay_flush

; schreibt die 13 Schattenregister in den AY
ay_flush:
        ld hl,ay_regs
        ld d,0
af_loop:
        ld bc,0xFFFD
        out (c),d
        ld a,(hl)
        ld b,0xBF
        out (c),a
        inc hl
        inc d
        ld a,d
        cp 13
        jr nz,af_loop
        ret

; alles stumm
ay_reset:
        ld hl,ay_regs
        ld de,ay_regs+1
        ld bc,12
        ld (hl),0
        ldir
        ld a,0x3F
        ld (ay_regs+7),a
        jr ay_flush

; in: A = Note 1..60; out: HL = Tonperiode
ay_period:
        dec a
        add a,a
        ld e,a
        ld d,0
        ld hl,ay_notes
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ret
ELSE
; ------------------------------------------------------------
; 48K: Beeper. Pro Frame ein kurzer Ton-Burst (Effekt vor Melodie).
; ------------------------------------------------------------
bp_update:
        ld a,(sfx_cnt)
        or a
        jr z,bp_music
        dec a
        ld (sfx_cnt),a
        ld hl,(sfx_ptr)
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = Halbperiode N (0 = Rauschen)
        inc hl
        ld b,(hl)               ; B = Anzahl Umschaltungen
        inc hl
        ld (sfx_ptr),hl
        ld a,d
        or e
        jr nz,bp_sfx_go
        call rnd                ; Rauschen: zufaellige Halbperiode
        and 0x3F
        add a,20
        ld e,a
        ld d,0
bp_sfx_go:
        ex de,hl
        jr snd_burst
bp_music:
        ld a,(ev_a)
        or a
        jr z,bp_m_play
        ld (bp_note),a
bp_m_play:
        ld a,(bp_note)
        or a
        ret z
        cp NOTE_OFF
        ret nc                  ; Pause
        dec a
        ld c,a
        add a,a
        add a,c                 ; * 3 Bytes je Note
        ld e,a
        ld d,0
        ld hl,bp_notes
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)               ; B = Umschaltungen fuer ca. 15 ms
        ld a,(song_par)
        or a
        jr z,bp_noshift
        ld c,a
bp_sh:
        srl b                   ; kuerzerer Burst: Platz fuer die Spiellogik
        dec c
        jr nz,bp_sh
        ld a,b
        or a
        jr nz,bp_noshift
        ld b,1
bp_noshift:
        ex de,hl

; in: HL = Halbperiode N, B = Anzahl Umschaltungen (>= 1)
; Rechteckton auf dem Lautsprecher (Bit 4 von Port 0xFE); Rand bleibt schwarz
; Die Lautstaerke (snd_vol 1..5) kuerzt den Burst: leiser = weniger Energie
snd_burst:
        ld a,(snd_vol)
        cp 5
        jr z,sb_go
        ld c,a                  ; Lautstaerke 1..4: Burst auf Vol/5 kuerzen
        xor a
sb_mul:
        add a,b
        dec c
        jr nz,sb_mul            ; A = B * Lautstaerke
        ld d,0
sb_div:
        sub 5
        jr c,sb_divd
        inc d
        jr sb_div
sb_divd:
        ld a,d                  ; A = B * Vol / 5
        cp 2
        jr nc,sb_set
        ld a,b                  ; mindestens 2 Umschaltungen (eine, wenn B = 1)
        cp 3
        jr c,sb_set
        ld a,2
sb_set:
        ld b,a
sb_go:
        ld c,0x10
sb_loop:
        ld a,c
        out (0xFE),a
        xor 0x10
        ld c,a
        ld d,h
        ld e,l
sb_dly:
        dec de
        ld a,d
        or e
        jr nz,sb_dly            ; 26 T je Durchlauf
        djnz sb_loop
        xor a
        out (0xFE),a
        ret
ENDIF

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
txt_pause:
        db "PAUSE        ",0
txt_exit:
        db "AUSGANG AUF  ",0
txt_pkt:
        db "PKT",0
txt_record:
        db "NEUER REKORD!",0
txt_sd:
        db "ENDSPIEL!    ",0
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
txt_t12p:
        db "P = PAUSE",0
txt_t8:
        db "SIEGE ZUM SPIELGEWINN:",0
txt_t9:
        db "STICK: HOCH/RUNTER=SPIELART",0
txt_t10:
        db "FEUER = START",0
txt_serie:
        db "SERIE:",0
txt_colon:
        db ":",0
txt_rekord:
        db "REKORD: LEVEL",0
; Layout-Namen (je 13 Zeichen, damit der Vorgaenger ueberschrieben wird)
layout_tab:
        dw lay_0,lay_1,lay_2,lay_3,lay_4,lay_5,lay_6,lay_7,lay_8,lay_9,lay_10,lay_11,lay_12
lay_0:
        db "KLASSISCH    ",0
lay_1:
        db "DICHTER WALD ",0
lay_2:
        db "OFFENE HALLE ",0
lay_3:
        db "KREUZWEG     ",0
txt_vol:
        db "T = TON: ",0
txt_aus:
        db "AUS ",0
txt_von5:
        db "/5 ",0
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
        db 0x45                 ; Ausgang: hell cyan auf schwarz

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
        ; Ausgang (Tuer)
        db 0x07,0x1F,0x3F,0x7F,0x7F,0x7C,0x7C,0x7C
        db 0xE0,0xF8,0xFC,0xFE,0xFE,0x3E,0x3E,0x3E
        db 0x7C,0x7C,0x7C,0x7C,0x7C,0x7C,0x7F,0x7F
        db 0x3E,0x3E,0x3E,0x06,0x3E,0x3E,0xFE,0xFE

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

; ============================================================
; Sound-Daten (erzeugt)
; ============================================================
; ---- Songdaten (gemeinsam): je Zeile 3 Bytes = Melodie, Bass, Schlagzeug
; Note 1..60 (= MIDI 36..95), 0 = unveraendert weiter, 254 = Ton aus, 255 = Ende
song_title:
        db 41,10,1
        db 0,0,3
        db 37,10,2
        db 0,0,3
        db 34,10,1
        db 37,0,3
        db 41,17,2
        db 0,0,3
        db 42,6,1
        db 0,0,3
        db 37,6,2
        db 0,0,3
        db 34,6,1
        db 37,0,3
        db 42,13,2
        db 0,0,3
        db 41,13,1
        db 0,0,3
        db 37,13,2
        db 0,0,3
        db 32,13,1
        db 37,0,3
        db 41,20,2
        db 0,0,3
        db 39,8,1
        db 0,0,3
        db 36,8,2
        db 0,0,3
        db 32,8,1
        db 36,0,3
        db 39,15,2
        db 0,0,3
        db 46,10,1
        db 0,0,3
        db 41,10,2
        db 0,0,3
        db 37,10,1
        db 41,0,3
        db 46,17,2
        db 0,0,3
        db 46,6,1
        db 0,0,3
        db 42,6,2
        db 0,0,3
        db 37,6,1
        db 42,0,3
        db 46,13,2
        db 0,0,3
        db 44,8,1
        db 0,0,3
        db 39,8,2
        db 0,0,3
        db 36,8,1
        db 39,0,3
        db 44,15,2
        db 0,0,3
        db 41,5,1
        db 39,0,3
        db 37,5,2
        db 36,0,3
        db 34,5,1
        db 0,0,3
        db 29,12,2
        db 0,0,3
        db 255,0,0
; Spielmusik: bewusst keine (Song 1 ist leer, im Spiel bleiben nur Effekte)
song_game:
        db 255,0,0
song_win:
        db 37,25,0
        db 41,29,0
        db 44,32,0
        db 49,37,0
        db 0,0,0
        db 0,0,0
        db 49,37,0
        db 254,254,0
        db 255,0,0
song_lose:
        db 34,22,0
        db 30,18,0
        db 27,15,0
        db 22,10,0
        db 0,0,0
        db 0,0,0
        db 0,0,0
        db 254,254,0
        db 255,0,0

; Songtabelle: Daten, Zeilenlaenge (Frames), Schleife, Parameter
; Parameter: 48K = Burst-Verkuerzung (Shift), 128K = Leiserstellen
song_tab:
        dw song_title
        IF AY128
        db 6,1,0
        ELSE
        db 6,1,0
        ENDIF
        dw song_game
        db 5,0,0
        dw song_win
        IF AY128
        db 5,0,0
        ELSE
        db 5,0,1
        ENDIF
        dw song_lose
        IF AY128
        db 8,0,0
        ELSE
        db 8,0,1
        ENDIF

IF AY128
; ---- 128K: AY-Tabellen
ay_notes:
        dw 1695
        dw 1600
        dw 1510
        dw 1425
        dw 1345
        dw 1270
        dw 1198
        dw 1131
        dw 1068
        dw 1008
        dw 951
        dw 898
        dw 847
        dw 800
        dw 755
        dw 713
        dw 673
        dw 635
        dw 599
        dw 566
        dw 534
        dw 504
        dw 476
        dw 449
        dw 424
        dw 400
        dw 377
        dw 356
        dw 336
        dw 317
        dw 300
        dw 283
        dw 267
        dw 252
        dw 238
        dw 224
        dw 212
        dw 200
        dw 189
        dw 178
        dw 168
        dw 159
        dw 150
        dw 141
        dw 133
        dw 126
        dw 119
        dw 112
        dw 106
        dw 100
        dw 94
        dw 89
        dw 84
        dw 79
        dw 75
        dw 71
        dw 67
        dw 63
        dw 59
        dw 56

sfx_1:
        db 3
        db 80,1,0,13   ; Ton 330 Hz, Rauschen 0, Lautstaerke 13
        db 167,1,0,11   ; Ton 262 Hz, Rauschen 0, Lautstaerke 11
        db 54,2,0,9   ; Ton 196 Hz, Rauschen 0, Lautstaerke 9
sfx_2:
        db 2
        db 111,0,0,12   ; Ton 1000 Hz, Rauschen 0, Lautstaerke 12
        db 79,0,0,10   ; Ton 1400 Hz, Rauschen 0, Lautstaerke 10
sfx_3:
        db 6
        db 212,0,0,13   ; Ton 523 Hz, Rauschen 0, Lautstaerke 13
        db 168,0,0,13   ; Ton 659 Hz, Rauschen 0, Lautstaerke 13
        db 141,0,0,13   ; Ton 784 Hz, Rauschen 0, Lautstaerke 13
        db 106,0,0,13   ; Ton 1047 Hz, Rauschen 0, Lautstaerke 13
        db 84,0,0,13   ; Ton 1319 Hz, Rauschen 0, Lautstaerke 13
        db 71,0,0,13   ; Ton 1568 Hz, Rauschen 0, Lautstaerke 13
sfx_4:
        db 6
        db 79,0,0,13   ; Ton 1400 Hz, Rauschen 0, Lautstaerke 13
        db 101,0,0,12   ; Ton 1100 Hz, Rauschen 0, Lautstaerke 12
        db 139,0,0,11   ; Ton 800 Hz, Rauschen 0, Lautstaerke 11
        db 111,0,0,10   ; Ton 1000 Hz, Rauschen 0, Lautstaerke 10
        db 185,0,0,9   ; Ton 600 Hz, Rauschen 0, Lautstaerke 9
        db 21,1,0,6   ; Ton 400 Hz, Rauschen 0, Lautstaerke 6
sfx_5:
        db 21
        db 85,3,1,15   ; Ton 130 Hz, Rauschen 1, Lautstaerke 15
        db 240,3,2,15   ; Ton 110 Hz, Rauschen 2, Lautstaerke 15
        db 47,6,8,15   ; Ton 70 Hz, Rauschen 8, Lautstaerke 15
        db 196,6,9,15   ; Ton 64 Hz, Rauschen 9, Lautstaerke 15
        db 55,7,10,14   ; Ton 60 Hz, Rauschen 10, Lautstaerke 14
        db 119,7,12,13   ; Ton 58 Hz, Rauschen 12, Lautstaerke 13
        db 5,8,14,12   ; Ton 54 Hz, Rauschen 14, Lautstaerke 12
        db 43,8,16,11   ; Ton 53 Hz, Rauschen 16, Lautstaerke 11
        db 84,8,18,10   ; Ton 52 Hz, Rauschen 18, Lautstaerke 10
        db 125,8,20,9   ; Ton 51 Hz, Rauschen 20, Lautstaerke 9
        db 169,8,22,8   ; Ton 50 Hz, Rauschen 22, Lautstaerke 8
        db 214,8,24,7   ; Ton 49 Hz, Rauschen 24, Lautstaerke 7
        db 5,9,26,6   ; Ton 48 Hz, Rauschen 26, Lautstaerke 6
        db 54,9,28,5   ; Ton 47 Hz, Rauschen 28, Lautstaerke 5
        db 106,9,30,4   ; Ton 46 Hz, Rauschen 30, Lautstaerke 4
        db 159,9,31,3   ; Ton 45 Hz, Rauschen 31, Lautstaerke 3
        db 215,9,31,3   ; Ton 44 Hz, Rauschen 31, Lautstaerke 3
        db 18,10,31,2   ; Ton 43 Hz, Rauschen 31, Lautstaerke 2
        db 79,10,31,2   ; Ton 42 Hz, Rauschen 31, Lautstaerke 2
        db 143,10,31,1   ; Ton 41 Hz, Rauschen 31, Lautstaerke 1
        db 211,10,31,1   ; Ton 40 Hz, Rauschen 31, Lautstaerke 1
sfx_6:
        db 14
        db 139,0,0,14   ; Ton 800 Hz, Rauschen 0, Lautstaerke 14
        db 149,0,0,13   ; Ton 745 Hz, Rauschen 0, Lautstaerke 13
        db 161,0,0,12   ; Ton 690 Hz, Rauschen 0, Lautstaerke 12
        db 175,0,0,11   ; Ton 635 Hz, Rauschen 0, Lautstaerke 11
        db 191,0,0,10   ; Ton 580 Hz, Rauschen 0, Lautstaerke 10
        db 211,0,0,9   ; Ton 525 Hz, Rauschen 0, Lautstaerke 9
        db 236,0,16,8   ; Ton 470 Hz, Rauschen 16, Lautstaerke 8
        db 11,1,17,7   ; Ton 415 Hz, Rauschen 17, Lautstaerke 7
        db 52,1,18,6   ; Ton 360 Hz, Rauschen 18, Lautstaerke 6
        db 107,1,19,5   ; Ton 305 Hz, Rauschen 19, Lautstaerke 5
        db 187,1,20,4   ; Ton 250 Hz, Rauschen 20, Lautstaerke 4
        db 56,2,21,3   ; Ton 195 Hz, Rauschen 21, Lautstaerke 3
        db 24,3,22,2   ; Ton 140 Hz, Rauschen 22, Lautstaerke 2
        db 84,4,23,1   ; Ton 100 Hz, Rauschen 23, Lautstaerke 1
drum_1:
        db 5
        db 227,2,0,15   ; Ton 150 Hz, Rauschen 0, Lautstaerke 15
        db 84,4,0,13   ; Ton 100 Hz, Rauschen 0, Lautstaerke 13
        db 47,6,0,10   ; Ton 70 Hz, Rauschen 0, Lautstaerke 10
        db 223,7,0,6   ; Ton 55 Hz, Rauschen 0, Lautstaerke 6
        db 223,7,0,3   ; Ton 55 Hz, Rauschen 0, Lautstaerke 3
drum_2:
        db 4
        db 0,0,12,13   ; Ton - Hz, Rauschen 12, Lautstaerke 13
        db 0,0,12,10   ; Ton - Hz, Rauschen 12, Lautstaerke 10
        db 0,0,14,6   ; Ton - Hz, Rauschen 14, Lautstaerke 6
        db 0,0,16,3   ; Ton - Hz, Rauschen 16, Lautstaerke 3
drum_3:
        db 3
        db 0,0,3,8   ; Ton - Hz, Rauschen 3, Lautstaerke 8
        db 0,0,3,4   ; Ton - Hz, Rauschen 3, Lautstaerke 4
        db 0,0,3,1   ; Ton - Hz, Rauschen 3, Lautstaerke 1
dr_tab:
        dw drum_1,drum_2,drum_3
ELSE
; ---- 48K: Beeper-Tabellen
; je Note: Halbperiode N (16 Bit), Toggles B fuer ca. 15 ms
bp_notes:
        dw 1028
        db 2
        dw 970
        db 2
        dw 915
        db 2
        dw 864
        db 2
        dw 815
        db 2
        dw 769
        db 3
        dw 726
        db 3
        dw 685
        db 3
        dw 647
        db 3
        dw 610
        db 3
        dw 576
        db 3
        dw 544
        db 4
        dw 513
        db 4
        dw 484
        db 4
        dw 457
        db 4
        dw 431
        db 5
        dw 407
        db 5
        dw 384
        db 5
        dw 362
        db 6
        dw 342
        db 6
        dw 323
        db 6
        dw 304
        db 7
        dw 287
        db 7
        dw 271
        db 7
        dw 256
        db 8
        dw 241
        db 8
        dw 228
        db 9
        dw 215
        db 9
        dw 203
        db 10
        dw 191
        db 10
        dw 180
        db 11
        dw 170
        db 12
        dw 161
        db 12
        dw 152
        db 13
        dw 143
        db 14
        dw 135
        db 15
        dw 127
        db 16
        dw 120
        db 17
        dw 113
        db 18
        dw 107
        db 19
        dw 101
        db 20
        dw 95
        db 21
        dw 89
        db 22
        dw 84
        db 24
        dw 80
        db 25
        dw 75
        db 26
        dw 71
        db 28
        dw 67
        db 30
        dw 63
        db 31
        dw 59
        db 33
        dw 56
        db 35
        dw 53
        db 37
        dw 50
        db 40
        dw 47
        db 42
        dw 44
        db 44
        dw 41
        db 47
        dw 39
        db 50
        dw 37
        db 53
        dw 35
        db 56
        dw 33
        db 59

sfx_1:
        db 3
        dw 203
        db 3   ; 330 Hz
        dw 255
        db 2   ; 262 Hz
        dw 342
        db 1   ; 196 Hz
sfx_2:
        db 2
        dw 66
        db 8   ; 1000 Hz
        dw 47
        db 9   ; 1400 Hz
sfx_3:
        db 6
        dw 127
        db 5   ; 523 Hz
        dw 101
        db 6   ; 659 Hz
        dw 84
        db 7   ; 784 Hz
        dw 63
        db 9   ; 1047 Hz
        dw 50
        db 11   ; 1319 Hz
        dw 41
        db 14   ; 1568 Hz
sfx_4:
        db 6
        dw 47
        db 12   ; 1400 Hz
        dw 60
        db 9   ; 1100 Hz
        dw 83
        db 6   ; 800 Hz
        dw 66
        db 7   ; 1000 Hz
        dw 111
        db 4   ; 600 Hz
        dw 167
        db 2   ; 400 Hz
sfx_5:
        db 21
        dw 0
        db 9   ; Rauschen
        dw 0
        db 9   ; Rauschen
        dw 0
        db 9   ; Rauschen
        dw 0
        db 9   ; Rauschen
        dw 0
        db 9   ; Rauschen
        dw 0
        db 8   ; Rauschen
        dw 0
        db 7   ; Rauschen
        dw 0
        db 7   ; Rauschen
        dw 0
        db 6   ; Rauschen
        dw 0
        db 6   ; Rauschen
        dw 0
        db 5   ; Rauschen
        dw 0
        db 4   ; Rauschen
        dw 0
        db 4   ; Rauschen
        dw 0
        db 3   ; Rauschen
        dw 0
        db 2   ; Rauschen
        dw 0
        db 2   ; Rauschen
        dw 0
        db 2   ; Rauschen
        dw 0
        db 1   ; Rauschen
        dw 0
        db 1   ; Rauschen
        dw 0
        db 1   ; Rauschen
        dw 0
        db 1   ; Rauschen
sfx_6:
        db 14
        dw 83
        db 7   ; 800 Hz
        dw 89
        db 6   ; 745 Hz
        dw 96
        db 6   ; 690 Hz
        dw 105
        db 5   ; 635 Hz
        dw 115
        db 4   ; 580 Hz
        dw 127
        db 3   ; 525 Hz
        dw 0
        db 5   ; Rauschen
        dw 0
        db 4   ; Rauschen
        dw 0
        db 4   ; Rauschen
        dw 0
        db 3   ; Rauschen
        dw 0
        db 2   ; Rauschen
        dw 0
        db 2   ; Rauschen
        dw 0
        db 1   ; Rauschen
        dw 0
        db 1   ; Rauschen
ENDIF

; Effekt-Tabelle (Nummer = Prioritaet)
sfx_tab:
        dw 0
        dw sfx_1   ; 1 = Bombe legen
        dw sfx_2   ; 2 = Menue
        dw sfx_3   ; 3 = Power-Up
        dw sfx_4   ; 4 = Monster stirbt
        dw sfx_5   ; 5 = Explosion
        dw sfx_6   ; 6 = Tod

; ---- Gebaute Level (erzeugt, von Hand aenderbar) ----
; # Wand   o Block   . leer
; Die Startecken (je 3 Kacheln) muessen frei bleiben.
map_0:                       ; AUFTAKT
        db "###############"
        db "#...o.o.oo.o.o#"
        db "#.#.#o#.#o#o#.#"
        db "#.............#"
        db "#.#o#o#.#o#.#o#"
        db "#o.o.oo.o.oo.o#"
        db "#o#o#.#.#o#o#o#"
        db "#o..ooo..ooo..#"
        db "#.#.#.#.#.#.#.#"
        db "#..ooo..ooo...#"
        db "###############"
map_1:                       ; GITTER
        db "###############"
        db "#....o.o.o.o.o#"
        db "#.#.#.#.#.#.#.#"
        db "#..o.o.o.o.o.o#"
        db "#.#.#.#.#.#.#.#"
        db "#o.o.o.o.o.o.o#"
        db "#.#.#.#.#.#.#.#"
        db "#o.o.o.o.o.o..#"
        db "#.#.#.#.#.#.#.#"
        db "#o.o.o.o.o....#"
        db "###############"
map_2:                       ; VIER RAEUME
        db "###############"
        db "#......o......#"
        db "#.#.#.#.#.#.#.#"
        db "#.o....o....o.#"
        db "#.#.#.#o#.#.#.#"
        db "#oo.ooooooo.oo#"
        db "#.#.#.#o#.#.#.#"
        db "#.o....o....o.#"
        db "#.#.#.#.#.#.#.#"
        db "#......o......#"
        db "###############"
map_3:                       ; DIAGONALE
        db "###############"
        db "#...oo..oo..oo#"
        db "#.#o#.#o#.#o#.#"
        db "#.oo..oo..oo..#"
        db "#o#.#o#.#o#.#o#"
        db "#o..oo..oo..oo#"
        db "#.#o#.#o#.#o#.#"
        db "#.oo..oo..oo..#"
        db "#o#.#o#.#o#.#.#"
        db "#o..oo..oo....#"
        db "###############"
map_4:                       ; SPIRALE
        db "###############"
        db "#.............#"
        db "#.#.#.#.#.#.#.#"
        db "#..oooo.oooo..#"
        db "#.#o#.#.#.#o#.#"
        db "#....o.o.o....#"
        db "#.#o#.#.#.#o#.#"
        db "#..oooo.oooo..#"
        db "#.#.#.#.#.#.#.#"
        db "#.............#"
        db "###############"
map_5:                       ; LABYRINTH
        db "###############"
        db "#.............#"
        db "#.#.#.#.#.#.#.#"
        db "#.ooooo.ooooo.#"
        db "#.#.#.#.#.#.#.#"
        db "#....o...o....#"
        db "#.#.#.#.#.#.#.#"
        db "#.ooooo.ooooo.#"
        db "#.#.#.#.#.#.#.#"
        db "#.............#"
        db "###############"
map_6:                       ; INSELN
        db "###############"
        db "#.....o...o...#"
        db "#.#o#o#o#o#o#.#"
        db "#.o.o.o.o.o.o.#"
        db "#.#o#o#o#o#o#o#"
        db "#.o.o.o.o.o.o.#"
        db "#o#o#o#o#o#o#.#"
        db "#.o.o.o.o.o.o.#"
        db "#.#o#o#o#o#o#.#"
        db "#...o...o.....#"
        db "###############"
map_7:                       ; FESTUNG
        db "###############"
        db "#.....o.o.....#"
        db "#.#.#.#.#.#.#.#"
        db "#...ooooooo...#"
        db "#.#.#.#.#.#.#.#"
        db "#...o.....o...#"
        db "#.#.#.#.#.#.#.#"
        db "#...ooo.ooo...#"
        db "#.#.#.#.#.#.#.#"
        db "#.....o.o.....#"
        db "###############"
map_8:                       ; ZICKZACK
        db "###############"
        db "#...oo....oo..#"
        db "#.#.#o#.#.#o#.#"
        db "#..o..o..o..o.#"
        db "#o#.#.#o#.#.#o#"
        db "#oo....oo....o#"
        db "#.#o#.#.#o#.#.#"
        db "#...oo....oo..#"
        db "#.#.#o#.#.#o#.#"
        db "#..o..o..o....#"
        db "###############"
map_tab:
        dw map_0,map_1,map_2,map_3,map_4,map_5,map_6,map_7,map_8
; Layout-Namen (je 13 Zeichen)
lay_4:
        db "AUFTAKT      ",0
lay_5:
        db "GITTER       ",0
lay_6:
        db "VIER RAEUME  ",0
lay_7:
        db "DIAGONALE    ",0
lay_8:
        db "SPIRALE      ",0
lay_9:
        db "LABYRINTH    ",0
lay_10:
        db "INSELN       ",0
lay_11:
        db "FESTUNG      ",0
lay_12:
        db "ZICKZACK     ",0

        end start
