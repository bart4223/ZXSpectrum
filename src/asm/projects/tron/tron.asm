; ============================================================
;  TRON fuer den ZX Spectrum 128K  -  Stufe 8: Sound (Titelmusik, Jingles, Effekte)
;  Assembler: pasmo (--tapbas)    Dateien: tron.asm / tron.tap
; ============================================================
;  Bildschirm: 32x24 Zellen
;    Zeilen 0-1   : HUD (P1 | TRON | P2)
;    Zeile  2     : oberer Rahmen
;    Zeilen 3-22  : Spielfeld (Zellen 1..30)  = 240x160 Pixel
;    Zeile  23    : unterer Rahmen
;  Rahmenzellen sind voll gesetzt (0xFF): ein Pixeltest am Zielpixel
;  erkennt die Wand ohne Koordinatenvergleich.
; ============================================================

TESTMODE        equ 0           ; 1 = Selbsttest der Pixelroutinen (nur Build-Skript)
AITEST          equ 0           ; 1 = beide Fahrzeuge vom Computer gesteuert (nur Testbau)
RNG_SEED        equ 0xACE1      ; Startwert des Zufallsgenerators (im Testbau variiert)
LEVEL_P1        equ 1           ; nur AITEST: Stufe von Fahrzeug 1 / 2
LEVEL_P2        equ 1
ARENA_DEFAULT   equ 0           ; Arena beim Start: 0 leer, 1 Block, 2 Pfeiler, 3 Rahmen, 4 Zufall
LEVEL_DEFAULT   equ 1           ; Computerstufe: 0 leicht, 1 mittel, 2 schwer
FIRE_NEW        equ 1           ; Testbau: Feuer startet die Runde neu (0 = Feuer ist Boost)
TESTBUILD       equ 0           ; 1 = Testbau: kein Countdown, Feuer startet die Runde sofort neu

                org 0x8000

VARS            equ 0xB000      ; Variablenbereich (Code muss darunter enden)
ytab            equ VARS        ; 192 Zeilenadressen (384 Byte)
plus_avail      equ VARS+0x200  ; 1 = ULAplus vorhanden
plus_on         equ VARS+0x201  ; 1 = erweiterter Farbraum aktiv
key_prev        equ VARS+0x202  ; letzter Zustand Taste C (Bit 3, 0 = gedrueckt)
txt_attr        equ VARS+0x203  ; Attribut fuer print_str
CTX1            equ VARS+0x210  ; Kontext Spieler 1 (16 Byte, siehe Spielablauf)
CTX2            equ VARS+0x220  ; Kontext Spieler 2
tick            equ VARS+0x240  ; Frame-Zaehler fuer das Tempo
state           equ VARS+0x241  ; 0 = Fahrt, 1 = Crash-Animation, 2 = Pause nach dem Crash
anim            equ VARS+0x242  ; Bildzaehler fuer Animation und Pause
result          equ VARS+0x243  ; Rundenergebnis: 0 offen, 1 = P1 gewinnt, 2 = P2 gewinnt, 3 = Remis
scx             equ VARS+0x244  ; Mitte der Funken (X)
scy             equ VARS+0x245  ; Mitte der Funken (Y)
spk_r           equ VARS+0x246  ; Radius der Funken
score1          equ VARS+0x247  ; gewonnene Runden Spieler 1
score2          equ VARS+0x248  ; gewonnene Runden Spieler 2
match_over      equ VARS+0x249  ; 0 laeuft, 1/2 = Sieger des Matches
paused          equ VARS+0x24A  ; 1 = Pause
p_prev          equ VARS+0x24B  ; letzter Zustand Taste P (Bit 0, 0 = gedrueckt)
jptr            equ VARS+0x24C  ; Zeiger auf die laufende Jingle-Tabelle (0 = keiner)
jcnt            equ VARS+0x24E  ; Restbilder der aktuellen Jingle-Note
sd_buf          equ VARS+0x250  ; Textpuffer fuer ein einzelnes Zeichen
pts1            equ VARS+0x254  ; Gesamtpunkte Spieler 1: 4 Dezimalziffern (Tausender zuerst)
pts2            equ VARS+0x258  ; Gesamtpunkte Spieler 2
mode            equ VARS+0x25C  ; 0 = 1 Spieler, 1 = 2 Spieler
speed           equ VARS+0x25D  ; 0 langsam, 1 normal, 2 schnell
vol             equ VARS+0x25E  ; Lautstaerke 0 (aus) .. 5
s_prev          equ VARS+0x25F  ; letzter Zustand Taste S
t_prev          equ VARS+0x260  ; letzter Zustand Taste T
spd_frames      equ VARS+0x261  ; Bilder pro Schritt
spd_steps       equ VARS+0x262  ; Schritte pro Bild (1 oder 2)
record          equ VARS+0x264  ; Rekord: 4 Dezimalziffern (hoechste Gesamtpunkte eines Matches, nur Sitzung)
bg_y            equ VARS+0x26A
bg_x            equ VARS+0x26B
bg_buf          equ VARS+0x26C
rng             equ VARS+0x270  ; Zufallsgenerator (16 Bit)
level           equ VARS+0x272  ; Computerstufe 0 leicht, 1 mittel, 2 schwer
ai_x            equ VARS+0x273
ai_y            equ VARS+0x274
ai_m            equ VARS+0x275  ; aktuelle Fahrtrichtung des Computers
ai_L            equ VARS+0x276  ; Vorausschau: so viele freie Pixel geradeaus genuegen
ai_R            equ VARS+0x277  ; Reichweite der Raumbewertung
ai_rm           equ VARS+0x278  ; Maske fuer Zufallskurven (0 = nie)
ai_mm           equ VARS+0x279  ; Maske fuer Fehlentscheidungen (0 = nie)
ray_dir         equ VARS+0x27A
sc_dir          equ VARS+0x27B
sc_sum          equ VARS+0x27C
ai_s0           equ VARS+0x27D  ; Bewertung geradeaus / links / rechts
ai_s1           equ VARS+0x27E
ai_s2           equ VARS+0x27F
ai_cl           equ VARS+0x280
ai_cr           equ VARS+0x281
d_prev          equ VARS+0x282  ; letzter Zustand Taste D
arena           equ VARS+0x283  ; Menuewahl: 0 leer, 1 Block, 2 Pfeiler, 3 Rahmen, 4 Zufall
arena_cur       equ VARS+0x284  ; tatsaechliche Arena der laufenden Runde (0..3)
a_prev          equ VARS+0x285  ; letzter Zustand Taste A
MUSCH           equ VARS+0x290  ; 3 Musikkanaele je 16 Byte
mus_on          equ VARS+0x2C0  ; 1 = Titelmusik laeuft
sfx_cnt         equ VARS+0x2C1  ; Rest des Bedien-Pieps auf Kanal C
testres         equ VARS+0x300  ; Ergebnisse des Selbsttests
owner           equ VARS+0x400  ; Besitzer-Tabelle 32x24 (0 leer, 1 = P1, 2 = P2, 3 = beide)

TWO_PLAYERS     equ 1           ; 0 = nur Spieler 1 (Testbau)
STEP_FRAMES     equ 1           ; Frames pro Schritt (1 = 50 Pixel/s, Feldbreite in ca. 5 s)
START_X         equ 64
START_Y         equ 104
CRASH_FRAMES    equ 30          ; Dauer der Funken-Animation (Frames)
WAIT_FRAMES     equ 75          ; Pause nach der Animation bis zur neuen Runde (1,5 s)
POINTS_WIN     equ 2           ; Rundensieg: +100 (Hunderterstelle um 2 Ziffern vor Einer)
WINS_NEEDED     equ 3           ; Match: Best of 5 = 3 Siege
CD_STEP         equ 50          ; Countdown: Bilder pro Ziffer (3 - 2 - 1)

ATTR_FIELD      equ 0x47        ; BRIGHT, Paper 0, Ink 7
ATTR_FRAME      equ 0x43        ; BRIGHT, Paper 0, Ink 3 (Magenta/Violett)
ATTR_BLACK      equ 0x40
ATTR_OBST       equ 0x44        ; Hindernisse: BRIGHT, Gruen
ATTR_P1         equ 0x45        ; Cyan
ATTR_P2         equ 0x42        ; Rot/Orange
ATTR_TITLE      equ 0x46        ; Gelb
ATTR_P1_DIM     equ 0x05        ; Spur P1: Cyan, gedaempft (ohne BRIGHT)
ATTR_P2_DIM     equ 0x02        ; Spur P2: Orange, gedaempft
ATTR_CROSS_DIM  equ 0x07        ; Zelle von beiden befahren: Weiss, gedaempft

G_SP            equ 15          ; Glyph-Nummern im Font
G_P             equ 10
G_T             equ 11
G_R             equ 12
G_O             equ 13
G_N             equ 14
G_G             equ 16
G_E             equ 17
G_W             equ 18
G_I             equ 19
G_M             equ 20
G_S             equ 21
G_F             equ 22
G_U             equ 23
G_A             equ 24
G_L             equ 25
G_C             equ 26
G_H             equ 27
G_K             equ 28
G_D             equ 29
G_B             equ 30
G_GT            equ 31
G_Z             equ 32

ROW_FRAME_TOP   equ 2
ROW_FRAME_BOT   equ 23
COL_FRAME_L     equ 0
COL_FRAME_R     equ 31

; ------------------------------------------------------------
start:
                di
                ld sp,0x7FF0
                ld bc,0x7FFD            ; 128K: ROM 1 (48K-ROM), Bank 0, Bildschirm normal
                ld a,0x10
                out (c),a
                xor a
                out (0xFE),a            ; Rand schwarz

                ld a,0x08
                ld (key_prev),a         ; Taste C losgelassen
                xor a
                ld (plus_on),a
                call detect_plus
                ld a,(plus_avail)
                ld (plus_on),a          ; ULAplus automatisch an, wenn vorhanden
                call apply_mode

                ld hl,score1            ; Match-Variablen loeschen
                ld de,score1+1
                ld bc,8
                ld (hl),0
                ldir
                call clear_pts
                ld a,1
                ld (p_prev),a           ; Taste P losgelassen

                call init_settings
                call init_ytab
                if TESTBUILD
                call new_round
                else
                call title_enter
                endif

                if TESTMODE
                call selftest
                endif

                im 1
                ei
main:
                halt
                call read_keys
                call read_pause
                call read_vol
                ld a,(paused)
                or a
                jr nz,main              ; Pause: nichts bewegt sich
                ld a,(state)
                cp 5
                jr z,m_title
                call read_joy1
                call read_joy2
                call dispatch
                call jingle_step
                jr main
m_title:        call title_input
                call title_step
                call music_step
                call jingle_step
                jr main

; Zustand: 0 Fahrt, 1 Crash-Animation, 2 Pause nach der Runde, 3 Countdown, 4 Match zu Ende
dispatch:
                ld a,(state)
                or a
                jp z,game_step
                cp 1
                jp z,crash_step
                cp 2
                jp z,wait_step
                cp 3
                jp z,countdown_step
                cp 4
                jp z,match_step
                ret                     ; 5 = Titelbild: eigene Schleife

; ------------------------------------------------------------
;  Spielablauf (Stufe 3: zwei Motorraeder, Kollision, Crash, Neustart)
; ------------------------------------------------------------
; Kontext je Spieler (16 Byte, Zugriff ueber IX):
;   +0 X   +1 Y   +2 Wunschrichtung   +3 zuletzt gefahrene Richtung   +4 Kennung (1/2)
;   +5 Status (0 nicht dabei, 1 faehrt, 2 gecrasht)   +6/+7 Zielpixel X/Y   +8 Ziel belegt
;   +9/+10 vorherige Position   +11/+12 Zellindex des Kopfes
C_X             equ 0
C_Y             equ 1
C_DIR           equ 2
C_MDIR          equ 3
C_ID            equ 4
C_STAT          equ 5
C_TX            equ 6
C_TY            equ 7
C_HIT           equ 8
C_PX            equ 9           ; Position vor dem letzten Zug
C_PY            equ 10
C_CL            equ 11          ; Zellindex des Kopfes (16 Bit)
C_CH            equ 12
C_EN            equ 13          ; Boost-Energie (0..BOOST_MAX)
C_BST           equ 14          ; 1 = Feuer gedrueckt (Boost gewuenscht)
C_CHG           equ 15          ; Zaehler fuer das Aufladen
BOOST_MAX       equ 32          ; Energie = Zusatzschritte, Balken 4 Zellen
BOOST_RECH      equ 7           ; Maske: alle 8 Schritte +1 Energie

; Neues Spielfeld aufbauen und beide Motorraeder an den Start setzen
new_round:
                call cls
                call draw_frame
                call draw_field_attrs
                call draw_arena
                call draw_hud
                call init_game
                if TESTBUILD
                else
                ld a,3                  ; Countdown: Koepfe stehen sichtbar am Start
                ld (state),a
                ld a,3
                ld d,1
                ld e,15
                call show_digit
                ld hl,beep_cd
                jp jingle_start
                endif
                ret

init_game:
                ld hl,0
                ld (jptr),hl            ; kein Jingle
                call ay_silence
                ld hl,owner
                ld de,owner+1
                ld bc,767
                ld (hl),0
                ldir
                ld hl,ctx_init1
                ld de,CTX1
                ld bc,11
                ldir
                ld hl,ctx_init2
                ld de,CTX2
                ld bc,11
                ldir
                xor a
                ld (tick),a
                ld (state),a
                ld (anim),a
                ld (result),a
                ld a,BOOST_MAX
                ld (CTX1+C_EN),a
                ld (CTX2+C_EN),a
                xor a
                ld (CTX1+C_BST),a
                ld (CTX2+C_BST),a
                ld (CTX1+C_CHG),a
                ld (CTX2+C_CHG),a
                ld d,1
                ld e,6
                ld b,4
                ld a,ATTR_P1
                call attr_fill
                ld e,22
                ld b,4
                ld a,ATTR_P2
                call attr_fill
                ld ix,CTX1
                call draw_bar
                ld ix,CTX2
                call draw_bar
                ld ix,CTX1
                call plot_head          ; Startpixel
                ld a,(CTX2+C_STAT)
                or a
                ret z
                ld ix,CTX2
                jp plot_head

; X, Y, Wunschrichtung, letzte Richtung, Kennung, Status (TWO_PLAYERS), Ziel X/Y, belegt, vorherige X/Y
ctx_init1:      db START_X,START_Y,1,1,1,1,0,0,0,START_X,START_Y
ctx_init2:      db 255-START_X,START_Y,3,3,2,TWO_PLAYERS,0,0,0,255-START_X,START_Y

; Feuer: nur nach dem Matchende (zurueck ins Titelbild); im Testbau startet es die Runde neu
fire_pressed:
                if TESTBUILD
                if FIRE_NEW
                jp new_round
                else
                ret
                endif
                else
                ld a,(state)
                cp 4
                ret nz
                ld a,(anim)
                cp 50
                ret c                   ; kurze Sperre, damit gedrueckt gehaltenes Feuer nicht sofort durchschlaegt
                jp title_enter
                endif

; Sinclair-Joystick 1 (Tasten 6-0, Port 0xEFFE, Bit = 0 wenn gedrueckt):
; Bit 4 links, Bit 3 rechts, Bit 2 runter, Bit 1 hoch, Bit 0 Feuer
read_joy1:
                ld a,0xEF
                in a,(0xFE)
                ld b,a
                ld a,1
                bit 0,b
                jr nz,rj1_nf
                ld (CTX1+C_BST),a       ; Feuer: Boost wuenschen
                push bc
                call fire_pressed
                pop bc
                jr rj1_f
rj1_nf:         xor a
                ld (CTX1+C_BST),a
rj1_f:          ld ix,CTX1
                bit 1,b
                jr nz,rj1_nu
                xor a                   ; hoch
                jr apply_dir
rj1_nu:         bit 2,b
                jr nz,rj1_nd
                ld a,2                  ; runter
                jr apply_dir
rj1_nd:         bit 4,b
                jr nz,rj1_nl
                ld a,3                  ; links
                jr apply_dir
rj1_nl:         bit 3,b
                ret nz
                ld a,1                  ; rechts
                jr apply_dir

; Sinclair-Joystick 2 (Tasten 1-5, Port 0xF7FE, Bit = 0 wenn gedrueckt):
; Bit 0 links, Bit 1 rechts, Bit 2 runter, Bit 3 hoch, Bit 4 Feuer
read_joy2:
                ld a,0xF7
                in a,(0xFE)
                ld b,a
                xor a
                ld (CTX2+C_BST),a
                bit 4,b
                jr nz,rj2_nf
                push bc
                call fire_pressed
                pop bc
                ld a,(mode)
                ld (CTX2+C_BST),a       ; nur im 2-Spieler-Modus Boost (mode = 1)
rj2_nf:         ld a,(mode)
                or a
                ret z                   ; 1 Spieler: Fahrzeug 2 steuert der Computer
                ld ix,CTX2
                bit 3,b
                jr nz,rj2_nu
                xor a                   ; hoch
                jr apply_dir
rj2_nu:         bit 2,b
                jr nz,rj2_nd
                ld a,2                  ; runter
                jr apply_dir
rj2_nd:         bit 0,b
                jr nz,rj2_nl
                ld a,3                  ; links
                jr apply_dir
rj2_nl:         bit 1,b
                ret nz
                ld a,1                  ; rechts
                ; weiter mit apply_dir

; A = gewuenschte Richtung, IX = Kontext. Umkehr um 180 Grad gegenueber der
; zuletzt gefahrenen Richtung wird ignoriert.
apply_dir:
                ld d,a
                xor (ix+C_MDIR)
                cp 2
                ret z
                ld a,d
                ld (ix+C_DIR),a
                ret

; Ein Schritt fuer beide Spieler, wenn das Tempo es erlaubt:
;  1. Ziele beider Spieler bestimmen und auf Belegung pruefen (noch nichts zeichnen)
;  2. gleiches Ziel: beide verlieren (Remis)
;  3. Zuege ausfuehren bzw. Crash eintragen
;  4. Rundenende pruefen
game_step:
                ld a,(tick)
                inc a
                ld (tick),a
                ld hl,spd_frames
                cp (hl)
                ret c
                xor a
                ld (tick),a
                call game_move
                ld a,(state)
                or a
                ret nz                  ; Crash im ersten Schritt
                ld a,(spd_steps)
                cp 2
                jr c,gs_boost
                call game_move          ; schnell: zweiter Schritt im selben Bild, jeder Schritt wird einzeln geprueft
                ld a,(state)
                or a
                ret nz
gs_boost:       ld ix,CTX1              ; Boost: ein Zusatzschritt je Schritt, solange Feuer und Energie da sind
                call boost_one
                ld a,(state)
                or a
                ret nz
                ld ix,CTX2
                jp boost_one

; IX = Kontext: Boost-Zusatzschritt (nur ein Fahrzeug) oder Aufladen
boost_one:
                ld a,(ix+C_STAT)
                cp 1
                ret nz
                ld a,(ix+C_BST)
                or a
                jr z,bo_rech
                ld a,(ix+C_EN)
                or a
                ret z                   ; leer: kein Boost, kein Aufladen bei gehaltenem Feuer
                dec (ix+C_EN)
                call draw_bar
                call calc_target
                call move_or_crash
                jp eval_crash
bo_rech:        inc (ix+C_CHG)
                ld a,(ix+C_CHG)
                and BOOST_RECH
                ret nz
                ld a,(ix+C_EN)
                cp BOOST_MAX
                ret nc
                inc a
                ld (ix+C_EN),a
                jp draw_bar

; IX = Kontext: Energiebalken in Zeile 1 (Spieler 1 ab Spalte 6, Spieler 2 ab Spalte 22), 4 Zellen
draw_bar:
                ld e,6
                ld a,(ix+C_ID)
                cp 1
                jr z,dbr
                ld e,22
dbr:            ld d,1
                ld c,(ix+C_EN)
                ld b,4
dbl:            ld a,8
                cp c
                jr c,dbf                ; Energie > 8: volle Zelle
                ld a,c
dbf:            ld l,a                  ; n = Pixel in dieser Zelle
                ld a,c
                sub l
                ld c,a
                ld a,l
                ld hl,bar_mask
                add a,l
                ld l,a
                jr nc,dbm
                inc h
dbm:            ld a,(hl)
                push af
                call cell_addr
                pop af
                inc h
                inc h
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc e
                djnz dbl
                ret
bar_mask:       db 0x00,0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE,0xFF

game_move:
                if AITEST
                ld a,LEVEL_P1
                ld (level),a
                ld ix,CTX1
                call ai_think
                ld a,LEVEL_P2
                ld (level),a
                ld ix,CTX2
                call ai_think
                else
                ld a,(mode)
                or a
                jr nz,gm_h
                ld ix,CTX2              ; 1 Spieler: Computer steuert Fahrzeug 2
                call ai_think
gm_h:
                endif
                ld ix,CTX1
                call calc_target
                ld ix,CTX2
                call calc_target
                ld a,(CTX1+C_STAT)
                ld b,a
                ld a,(CTX2+C_STAT)
                and b
                jr z,gs_noshare
                ld a,(CTX1+C_TX)
                ld b,a
                ld a,(CTX2+C_TX)
                cp b
                jr nz,gs_noshare
                ld a,(CTX1+C_TY)
                ld b,a
                ld a,(CTX2+C_TY)
                cp b
                jr nz,gs_noshare
                ld a,1                  ; beide wollen dasselbe Pixel: beide crashen
                ld (CTX1+C_HIT),a
                ld (CTX2+C_HIT),a
gs_noshare:
                ld ix,CTX1
                call move_or_crash
                ld ix,CTX2
                call move_or_crash
eval_crash:
                ld b,0
                ld a,(CTX1+C_STAT)
                cp 2
                jr nz,ge1
                set 0,b                 ; P1 gecrasht
ge1:            ld a,(CTX2+C_STAT)
                cp 2
                jr nz,ge2
                set 1,b                 ; P2 gecrasht
ge2:            ld a,b
                or a
                ret z                   ; niemand gecrasht: weiterfahren
                cp 3
                jr z,ge_set             ; beide: Remis (3)
                xor 3                   ; nur P1 gecrasht -> P2 gewinnt (2), nur P2 -> P1 gewinnt (1)
ge_set:         ld (result),a
                jp crash_start

; IX = Kontext: Zielpixel bestimmen, Belegung (Wand oder Spur) merken
calc_target:
                ld a,(ix+C_STAT)
                cp 1
                ret nz
                ld e,(ix+C_X)
                ld d,(ix+C_Y)
                ld a,(ix+C_DIR)
                or a
                jr z,ct_up
                cp 1
                jr z,ct_right
                cp 2
                jr z,ct_down
                dec e                   ; links
                jr ct_go
ct_up:          dec d
                jr ct_go
ct_right:       inc e
                jr ct_go
ct_down:        inc d
ct_go:          ld (ix+C_TX),e
                ld (ix+C_TY),d
                call pixel_test         ; Z = frei, NZ = belegt (DE bleibt erhalten)
                ld a,0
                jr z,ct_set
                inc a
ct_set:         ld (ix+C_HIT),a
                ret

; IX = Kontext: Zielpixel belegt -> gecrasht, sonst Kopf ziehen und Spur setzen
move_or_crash:
                ld a,(ix+C_STAT)
                cp 1
                ret nz
                ld a,(ix+C_HIT)
                or a
                jr z,moc_move
                ld (ix+C_STAT),2
                ret
moc_move:       ld a,(ix+C_X)
                ld (ix+C_PX),a
                ld a,(ix+C_Y)
                ld (ix+C_PY),a
                ld a,(ix+C_DIR)
                ld (ix+C_MDIR),a
                ld a,(ix+C_TX)
                ld (ix+C_X),a
                ld a,(ix+C_TY)
                ld (ix+C_Y),a
                call pts_step           ; 1 Punkt je gefahrenem Schritt
                ; weiter mit plot_head

; IX = Kontext: Kopfpixel setzen, Besitzer eintragen, neue Kopfzelle und die
; Zelle des vorherigen Kopfes neu faerben
plot_head:
                ld d,(ix+C_Y)
                ld e,(ix+C_X)
                push de
                call pixel_set
                pop de
                call cell_index         ; HL = neue Kopfzelle
                ld (ix+C_CL),l
                ld (ix+C_CH),h
                push hl
                ld bc,owner
                add hl,bc
                ld a,(hl)
                or (ix+C_ID)
                ld (hl),a
                pop hl
                call paint_cell
                ld d,(ix+C_PY)
                ld e,(ix+C_PX)
                call cell_index         ; HL = vorherige Zelle (gleich der neuen, wenn nicht gewechselt)
                ; weiter mit paint_cell

; HL = Zellindex: Attribut aus Besitzer (1 = P1 cyan, 2 = P2 orange, 3 = beide: weiss),
; gedaempft; BRIGHT, wenn der Kopf eines Spielers in dieser Zelle steht
paint_cell:
                push hl
                ld bc,owner
                add hl,bc
                ld e,(hl)
                ld d,0
                ld hl,attr_by_owner
                add hl,de
                ld c,(hl)               ; C = Attribut ohne BRIGHT
                pop hl
                ld a,(CTX1+C_STAT)
                or a
                jr z,pc_h2
                ld de,(CTX1+C_CL)
                or a
                sbc hl,de
                add hl,de               ; HL zurueck, Z bleibt erhalten
                jr nz,pc_h2
                set 6,c                 ; Kopf von P1 in dieser Zelle
pc_h2:          ld a,(CTX2+C_STAT)
                or a
                jr z,pc_set
                ld de,(CTX2+C_CL)
                or a
                sbc hl,de
                add hl,de
                jr nz,pc_set
                set 6,c                 ; Kopf von P2 in dieser Zelle
pc_set:         ld de,0x5800
                add hl,de
                ld (hl),c
                ret

attr_by_owner:  db ATTR_FIELD,ATTR_P1_DIM,ATTR_P2_DIM,ATTR_CROSS_DIM

; D=y, E=x -> HL = Zellindex (Zeile*32 + Spalte), DE bleibt erhalten
cell_index:
                ld a,d
                rrca
                rrca
                rrca
                and 0x1F
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,e
                rrca
                rrca
                rrca
                and 0x1F
                add a,l
                ld l,a
                ret

; ------------------------------------------------------------
;  Crash (Stufe 2)
; ------------------------------------------------------------
crash_start:
                ld a,1
                ld (state),a
                xor a
                ld (anim),a
                call show_result
                call score_update
                ld a,7
                ld e,0x23               ; Mixer: Ton C + Rauschen A und B an, Rest aus
                jp ay_wr

; Punkt fuer den Sieger der Runde, HUD neu, Matchsieger vormerken
score_update:
                ld a,(result)
                cp 1
                jr z,su1
                cp 2
                ret nz
                ld hl,score2
                inc (hl)
                ld a,(hl)
                cp WINS_NEEDED
                jr c,su_d
                ld a,2
                ld (match_over),a
                jr su_d
su1:            ld hl,score1
                inc (hl)
                ld a,(hl)
                cp WINS_NEEDED
                jr c,su_d
                ld a,1
                ld (match_over),a
su_d:           ld a,(result)
                ld hl,pts1+1            ; Hunderterstelle
                cp 1
                jr z,su_b
                ld hl,pts2+1
su_b:           ld b,2
                call pt_inc
                jp draw_hud

; Ein Bild der Funken-Animation: alten Ring loeschen, neuen zeichnen, Rauschen
; (Funken werden per XOR gesetzt; das zweite XOR stellt den Untergrund exakt her)
crash_step:
                ld a,(anim)
                or a
                jr z,cs_nodel
                call sparks_both        ; A = Radius des zuletzt gezeichneten Rings
cs_nodel:
                ld a,(anim)
                inc a
                ld (anim),a
                cp CRASH_FRAMES+1
                jr nc,cs_end
                call sparks_both
                jp crash_sound
cs_end:
                call ay_silence
                ld a,2
                ld (state),a
                xor a
                ld (anim),a
                ld a,(result)
                cp 3
                ld hl,jingle_draw
                jr z,cs_jg
                cp 2
                ld hl,jingle_win
                jr nz,cs_jg
                ld a,(mode)             ; 1 Spieler: gewinnt der Computer, klingt es traurig
                or a
                jr nz,cs_jg
                ld hl,jingle_lose
cs_jg:          jp jingle_start

; Pause nach dem Crash, danach neue Runde
wait_step:
                ld a,(anim)
                inc a
                ld (anim),a
                cp WAIT_FRAMES
                ret c
                ld a,(match_over)
                or a
                jp z,new_round
                ; Match zu Ende: Siegertext und Fanfare, Feuer startet ein neues Match
                ld a,4
                ld (state),a
                xor a
                ld (anim),a
                ld (tick),a
                ld hl,pts1              ; Rekord der Sitzung
                call rec_try
                ld a,(mode)
                or a
                jr z,we_nr
                ld hl,pts2
                call rec_try
we_nr:          ld hl,fanfare
                ld a,(match_over)
                cp 2
                jr nz,we_go
                ld a,(mode)
                or a
                jr nz,we_go
                ld hl,fanfare_lose      ; Computer gewinnt das Match
we_go:          jp jingle_start

; Matchende: Siegertext und Aufforderung wechseln alle 64 Bilder
match_step:
                ld a,(anim)
                cp 100
                jr nc,ms_a
                inc a
                ld (anim),a
ms_a:           ld a,(tick)
                ld b,a
                inc a
                ld (tick),a
                ld a,b
                and 0x3F
                ret nz
                bit 6,b
                jr nz,ms_press
                ld a,(match_over)
                cp 2
                ld a,ATTR_P1
                ld hl,str_m_p1
                jr nz,ms_pr
                ld a,ATTR_P2
                ld hl,str_m_p2
                jr ms_pr
ms_press:       ld a,ATTR_TITLE
                ld hl,str_press
ms_pr:          ld (txt_attr),a
                ld d,1
                ld e,11
                jp print_str

str_m_p1:       db 15,10,1,15,21,19,17,16,11,15,15,0xFF       ; P1 SIEGT
str_m_p2:       db 15,10,2,15,21,19,17,16,11,15,15,0xFF
str_press:      db 15,15,15,22,17,23,17,12,15,15,15,0xFF      ; FEUER

; Countdown 3 - 2 - 1, dann Start
countdown_step:
                ld a,(anim)
                inc a
                ld (anim),a
                cp CD_STEP
                jr z,cd2
                cp CD_STEP*2
                jr z,cd1
                cp CD_STEP*3
                ret nz
                xor a                   ; Los!
                ld (state),a
                ld (anim),a
                ld a,15
                ld d,1
                ld e,15
                call show_digit
                ld hl,beep_go
                jp jingle_start
cd2:            ld a,2
                jr cd_show
cd1:            ld a,1
cd_show:        ld d,1
                ld e,15
                call show_digit
                ld hl,beep_cd
                jp jingle_start

; A = Glyph, D = Zeile, E = Spalte, Farbe wie bei show_digit (gelb) bzw. txt_attr
show_digit:
                ld b,a
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld a,b
show_glyph:
                ld (sd_buf),a
                ld a,0xFF
                ld (sd_buf+1),a
                ld hl,sd_buf
                jp print_str


; ------------------------------------------------------------
;  Stufe 6: Titelbild, Menue, Einstellungen
; ------------------------------------------------------------
; Standardwerte der Sitzung: 2 Spieler, Tempo normal, Lautstaerke 5, Rekord 0
init_settings:
                ld a,1
                ld (mode),a
                ld (speed),a
                ld (s_prev),a
                ld (t_prev),a
                ld (d_prev),a
                ld (a_prev),a
                ld a,ARENA_DEFAULT
                ld (arena),a
                ld (arena_cur),a
                ld a,1
                ld hl,RNG_SEED
                ld (rng),hl
                ld a,LEVEL_DEFAULT
                ld (level),a
                ld a,1
                if TESTBUILD
                ld a,5                  ; Testbau: volle Lautstaerke
                else
                ld a,3                  ; Standard-Lautstaerke 3
                endif
                ld (vol),a
                ld hl,record
                ld de,record+1
                ld bc,3
                ld (hl),0
                ldir
                jp apply_speed

; speed -> spd_frames / spd_steps (langsam 2 Bilder je Schritt, normal STEP_FRAMES, schnell 2 Schritte je Bild)
apply_speed:
                ld a,(speed)
                add a,a
                ld e,a
                ld d,0
                ld hl,speed_tab
                add hl,de
                ld a,(hl)
                ld (spd_frames),a
                inc hl
                ld a,(hl)
                ld (spd_steps),a
                ret
speed_tab:      db 2,1, STEP_FRAMES,1, 1,2

; B = Port-High, C = Bitmaske, HL = Byte "letzter Zustand": Carry = Taste neu gedrueckt
key_edge:
                push bc
                ld c,0xFE
                in a,(c)
                pop bc
                and c
                ld d,a                  ; 0 = gedrueckt
                ld a,(hl)
                ld e,a
                ld (hl),d
                ld a,d
                or a
                ret nz
                ld a,e
                or a
                ret z
                scf
                ret

; Taste T: Lautstaerke 5 - 4 - 3 - 2 - 1 - aus - 5 ..., jederzeit
read_vol:
                ld b,0xFB
                ld c,0x10
                ld hl,t_prev
                call key_edge
                ret nc
                ld a,(vol)
                or a
                jr nz,vn_dec
                ld a,5
                jr vn_set
vn_dec:         dec a
vn_set:         ld (vol),a
                ld a,(state)
                cp 5
                jr z,vn_t
                or a
                ret nz                  ; nur waehrend der Fahrt piepsen
                jr vn_beep
vn_t:           call draw_vol
                jp ui_blip              ; im Titelbild: Blip auf Kanal C in der neuen Lautstaerke
vn_beep:        ld a,(vol)
                or a
                ret z
                ld hl,beep_cd
                jp jingle_start

; Rekord vergleichen: HL = 4 Ziffern; ist der Wert groesser, wird er uebernommen
rec_try:
                ld de,record
                push hl
                ld b,4
rt1:            ld a,(de)
                cp (hl)
                jr c,rt_copy
                jr nz,rt_end
                inc hl
                inc de
                djnz rt1
                jr rt_end
rt_copy:        pop hl
                ld de,record
                ld bc,4
                ldir
                ret
rt_end:         pop hl
                ret

; Titelbild aufbauen, Zustand 5
title_enter:
                ld a,5
                ld (state),a
                xor a
                ld (anim),a
                ld (tick),a
                ld (paused),a
                ld hl,0
                ld (jptr),hl
                call ay_silence
                call cls
                call draw_frame
                call draw_field_attrs
                ; grosses TRON (Glyphen vierfach vergroessert, 32x32 Pixel)
                ld a,G_T
                ld d,4
                ld e,8
                call big_glyph
                ld a,G_R
                ld d,4
                ld e,12
                call big_glyph
                ld a,G_O
                ld d,4
                ld e,16
                call big_glyph
                ld a,G_N
                ld d,4
                ld e,20
                call big_glyph
                ld b,2                  ; Farben: T R cyan, O N orange; oben hell, unten gedaempft
                ld d,4
tl1:            push bc
                ld a,ATTR_P1
                ld e,8
                ld b,8
                call attr_fill
                ld a,ATTR_P2
                ld e,16
                ld b,8
                call attr_fill
                inc d
                pop bc
                djnz tl1
                ld b,2
tl2:            push bc
                ld a,ATTR_P1_DIM
                ld e,8
                ld b,8
                call attr_fill
                ld a,0x02
                ld e,16
                ld b,8
                call attr_fill
                inc d
                pop bc
                djnz tl2
                ; zwei Spuren, die aufeinander zufahren
                ld d,75
                ld e,24
tl3:            push de
                call pixel_set
                pop de
                inc e
                ld a,e
                cp 113
                jr nz,tl3
                ld e,144
tl4:            push de
                call pixel_set
                pop de
                inc e
                ld a,e
                cp 232
                jr nz,tl4
                ld d,9
                ld e,3
                ld b,11
                ld a,ATTR_P1_DIM
                call attr_fill
                ld e,14
                ld b,1
                ld a,ATTR_P1
                call attr_fill
                ld e,18
                ld b,1
                ld a,ATTR_P2
                call attr_fill
                ld e,19
                ld b,10
                ld a,0x02
                call attr_fill
                call draw_mode
                call draw_level
                call draw_speed
                call draw_arena_menu
                call draw_vol
                call draw_record
                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_hint1
                ld d,21
                ld e,8
                call print_str
                ld hl,str_hint2
                ld d,22
                ld e,4
                call print_str
                jp mus_start

; D = Zeile, E = Spalte, B = Anzahl, A = Attribut; Ergebnis: HL = Adresse des ersten Attributs
attr_fill:
                push af
                push de
                push bc
                ld l,d
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld c,e
                ld b,0
                add hl,bc
                ld bc,0x5800
                add hl,bc
                pop bc
                pop de
                pop af
                push hl
                ld c,a
af1:            ld (hl),c
                inc hl
                djnz af1
                pop hl
                ret

; A = Glyph, D = Zeile, E = Spalte (Zelle): Glyph vierfach vergroessert (32x32 Pixel)
big_glyph:
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,font
                add hl,bc
                push hl
                pop ix
                ld a,d
                add a,a
                add a,a
                add a,a
                ld (bg_y),a
                ld a,e
                add a,a
                add a,a
                add a,a
                ld (bg_x),a
                ld b,8
bg_row:         push bc
                ld a,(ix+0)
                ld c,a
                ld hl,bg_buf
                ld a,c
                rlca
                rlca
                and 3
                call bg_ex
                ld a,c
                rrca
                rrca
                rrca
                rrca
                and 3
                call bg_ex
                ld a,c
                rrca
                rrca
                and 3
                call bg_ex
                ld a,c
                and 3
                call bg_ex
                ld b,4
bg_rep:         push bc
                ld a,(bg_y)
                ld d,a
                ld a,(bg_x)
                ld e,a
                call pixel_addr
                ex de,hl
                ld hl,bg_buf
                ld bc,4
                ldir
                ld hl,bg_y
                inc (hl)
                pop bc
                djnz bg_rep
                inc ix
                pop bc
                djnz bg_row
                ret
bg_ex:          ld e,a
                ld d,0
                push hl
                ld hl,tab4
                add hl,de
                ld a,(hl)
                pop hl
                ld (hl),a
                inc hl
                ret
tab4:           db 0x00,0x0F,0xF0,0xFF

; Menuezeilen
draw_mode:
                ld a,(mode)
                or a
                ld a,ATTR_TITLE
                jr z,dm1
                ld a,ATTR_P1_DIM
dm1:            ld (txt_attr),a
                ld hl,str_1p
                ld d,10
                ld e,12
                call print_str
                ld a,(mode)
                or a
                ld a,G_GT
                jr z,dm1m
                ld a,G_SP
dm1m:           ld d,10
                ld e,10
                call show_glyph
                ld a,(mode)
                or a
                ld a,ATTR_P1_DIM
                jr z,dm2
                ld a,ATTR_TITLE
dm2:            ld (txt_attr),a
                ld hl,str_2p
                ld d,12
                ld e,12
                call print_str
                ld a,(mode)
                or a
                ld a,G_SP
                jr z,dm2m
                ld a,G_GT
dm2m:           ld d,12
                ld e,10
                jp show_glyph

; Computerstufe (nur im 1-Spieler-Modus hervorgehoben)
draw_level:
                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_stufe
                ld d,14
                ld e,9
                call print_str
                ld a,(mode)
                or a
                ld a,ATTR_TITLE
                jr z,dl1
                ld a,ATTR_P1_DIM
dl1:            ld (txt_attr),a
                ld a,(level)
                add a,a
                ld e,a
                ld d,0
                ld hl,str_lv_tab
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld d,14
                ld e,15
                jp print_str

draw_speed:
                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_tempo
                ld d,15
                ld e,9
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld a,(speed)
                add a,a
                ld e,a
                ld d,0
                ld hl,str_speed_tab
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld d,15
                ld e,15
                jp print_str

draw_vol:
                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_ton
                ld d,17
                ld e,11
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld a,(vol)
                or a
                jr nz,dv1
                ld hl,str_aus
                ld d,17
                ld e,15
                jp print_str
dv1:            ld d,17
                ld e,15
                call show_glyph
                ld hl,str_blank2
                ld d,17
                ld e,16
                jp print_str

; Arena-Auswahl im Menue
draw_arena_menu:
                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_arena
                ld d,16
                ld e,9
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld a,(arena)
                add a,a
                ld e,a
                ld d,0
                ld hl,str_ar_tab
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld d,16
                ld e,15
                jp print_str

draw_record:                ld a,ATTR_P1_DIM
                ld (txt_attr),a
                ld hl,str_rekord
                ld d,19
                ld e,10
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld hl,record
                ld de,0x1311
                jp draw_pts

str_1p:         db 1,G_SP,G_S,G_P,G_I,G_E,G_L,G_E,G_R,0xFF
str_2p:         db 2,G_SP,G_S,G_P,G_I,G_E,G_L,G_E,G_R,0xFF
str_tempo:      db G_T,G_E,G_M,G_P,G_O,0xFF
str_sp0:        db G_L,G_A,G_N,G_G,G_S,G_A,G_M,0xFF
str_sp1:        db G_N,G_O,G_R,G_M,G_A,G_L,G_SP,0xFF
str_sp2:        db G_S,G_C,G_H,G_N,G_E,G_L,G_L,0xFF
str_speed_tab:  dw str_sp0,str_sp1,str_sp2
str_ton:        db G_T,G_O,G_N,0xFF
str_aus:        db G_A,G_U,G_S,0xFF
str_blank2:     db G_SP,G_SP,0xFF
str_rekord:     db G_R,G_E,G_K,G_O,G_R,G_D,G_SP,0xFF
str_fire:       db G_F,G_E,G_U,G_E,G_R,0xFF
str_hint1:      db G_S,G_SP,G_T,G_E,G_M,G_P,G_O,G_SP,G_SP,G_D,G_SP,G_S,G_T,G_U,G_F,G_E,0xFF
str_hint2:      db G_A,G_SP,G_A,G_R,G_E,G_N,G_A,G_SP,G_SP,G_T,G_SP,G_T,G_O,G_N,G_SP,G_SP,G_C,G_SP,G_F,G_A,G_R,G_B,G_E,0xFF
str_arena:      db G_A,G_R,G_E,G_N,G_A,0xFF
str_ar0:        db G_L,G_E,G_E,G_R,G_SP,G_SP,G_SP,0xFF
str_ar1:        db G_B,G_L,G_O,G_C,G_K,G_SP,G_SP,0xFF
str_ar2:        db G_P,G_F,G_E,G_I,G_L,G_E,G_R,0xFF
str_ar3:        db G_R,G_A,G_H,G_M,G_E,G_N,G_SP,0xFF
str_ar4:        db G_Z,G_U,G_F,G_A,G_L,G_L,G_SP,0xFF
str_ar_tab:     dw str_ar0,str_ar1,str_ar2,str_ar3,str_ar4
str_stufe:      db G_S,G_T,G_U,G_F,G_E,0xFF
str_lv0:        db G_L,G_E,G_I,G_C,G_H,G_T,0xFF
str_lv1:        db G_M,G_I,G_T,G_T,G_E,G_L,0xFF
str_lv2:        db G_S,G_C,G_H,G_W,G_E,G_R,0xFF
str_lv_tab:     dw str_lv0,str_lv1,str_lv2

; Joystick im Titelbild: links/hoch = 1 Spieler, rechts/runter = 2 Spieler, Feuer = Start
title_input:
                ld a,0xEF
                in a,(0xFE)
                ld b,a                  ; Joystick 1
                ld a,0xF7
                in a,(0xFE)
                ld c,a                  ; Joystick 2
                bit 0,b
                jr z,ti_fire
                bit 4,c
                jr z,ti_fire
                bit 1,b
                jr z,ti_1p
                bit 4,b
                jr z,ti_1p
                bit 3,c
                jr z,ti_1p
                bit 0,c
                jr z,ti_1p
                bit 2,b
                jr z,ti_2p
                bit 3,b
                jr z,ti_2p
                bit 2,c
                jr z,ti_2p
                bit 1,c
                jr z,ti_2p
                ret
ti_1p:          xor a
                jr ti_set
ti_2p:          ld a,1
ti_set:         ld hl,mode
                cp (hl)
                ret z
                ld (hl),a
                call ui_blip
                call draw_mode
                jp draw_level
ti_fire:        ld a,(anim)
                cp 25
                ret c                   ; Sperre: gehaltenes Feuer vom Matchende zaehlt nicht
                xor a
                ld (score1),a
                ld (score2),a
                ld (match_over),a
                call clear_pts
                call apply_speed
                call mus_stop
                jp new_round

; Titelbild: Taste S schaltet das Tempo, FEUER blinkt
title_step:
                ld a,(anim)
                cp 100
                jr nc,ts1
                inc a
                ld (anim),a
ts1:            ld b,0xFD
                ld c,0x02
                ld hl,s_prev
                call key_edge
                jr nc,ts2
                ld a,(speed)
                inc a
                cp 3
                jr c,ts_s
                xor a
ts_s:           ld (speed),a
                call ui_blip
                call draw_speed
ts2:            ld b,0xFD
                ld c,0x04
                ld hl,d_prev
                call key_edge
                jr nc,ts4
                ld a,(level)
                inc a
                cp 3
                jr c,ts_l
                xor a
ts_l:           ld (level),a
                call ui_blip
                call draw_level
ts4:            ld b,0xFD
                ld c,0x01
                ld hl,a_prev
                call key_edge
                jr nc,ts5
                ld a,(arena)
                inc a
                cp 5
                jr c,ts_a
                xor a
ts_a:           ld (arena),a
                call ui_blip
                call draw_arena_menu
ts5:            ld a,r                  ; Zufallsgenerator mit der Wartezeit des Spielers mischen
                ld hl,rng
                xor (hl)
                or 1
                ld (hl),a
                ld a,(tick)
                inc a
                ld (tick),a
                ld b,a
                and 0x1F
                ret nz
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld hl,str_fire
                bit 5,b
                jr z,ts3
                ld hl,str_blank5
ts3:            ld d,20
                ld e,14
                jp print_str


; ------------------------------------------------------------
;  Stufe 7: Computergegner
; ------------------------------------------------------------
; Zufallszahl (xorshift 16 Bit): A = H = zufaellig
rand8:
                ld hl,(rng)
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
                ld (rng),hl
                ret

; A = Richtung (0 hoch, 1 rechts, 2 runter, 3 links): D/E um einen Schritt weiter
step_de:
                or a
                jr z,sd_up
                cp 1
                jr z,sd_r
                cp 2
                jr z,sd_dn
                dec e
                ret
sd_up:          dec d
                ret
sd_r:           inc e
                ret
sd_dn:          inc d
                ret

; A = Richtung, D = y, E = x, B = Maximum: C = Anzahl freier Pixel hintereinander
; (ab dem Nachbarpixel; D/E sind danach unbestimmt). Waagerecht wird Byte und Maske mitgefuehrt.
ray:
                cp 1
                jr z,ray_hr
                cp 3
                jr z,ray_hl
                ld c,0
                or a
                jr nz,rvd
rvu:            dec d
                push bc
                call pixel_test
                pop bc
                ret nz
                inc c
                ld a,c
                cp b
                jr nz,rvu
                ret
rvd:            inc d
                push bc
                call pixel_test
                pop bc
                ret nz
                inc c
                ld a,c
                cp b
                jr nz,rvd
                ret
ray_hr:         push bc
                call pixel_addr         ; HL = Byte, A = Maske
                pop bc
                ld e,a
                ld c,0
rhr:            ld a,e
                rrca
                ld e,a
                jr nc,rhr1
                inc hl
rhr1:           ld a,(hl)
                and e
                ret nz
                inc c
                ld a,c
                cp b
                jr nz,rhr
                ret
ray_hl:         push bc
                call pixel_addr
                pop bc
                ld e,a
                ld c,0
rhl:            ld a,e
                rlca
                ld e,a
                jr nc,rhl1
                dec hl
rhl1:           ld a,(hl)
                and e
                ret nz
                inc c
                ld a,c
                cp b
                jr nz,rhl
                ret

; A = Richtung: Bewertung dieses Zuges von (ai_x,ai_y) aus. 0 = sofort blockiert,
; sonst 1 + freie Strecke voraus + links + rechts ab dem naechsten Pixel (je max. ai_R)
score_dir:
                ld (sc_dir),a
                ld a,(ai_y)
                ld d,a
                ld a,(ai_x)
                ld e,a
                ld a,(sc_dir)
                call step_de
                call pixel_test
                jr z,sc_free
                xor a
                ret
sc_free:        push de
                ld a,(ai_R)
                ld b,a
                ld a,(sc_dir)
                call ray
                ld a,c
                ld (sc_sum),a
                pop de
                push de
                ld a,(ai_R)
                ld b,a
                ld a,(sc_dir)
                add a,3
                and 3
                call ray
                ld a,(sc_sum)
                add a,c
                ld (sc_sum),a
                pop de
                ld a,(ai_R)
                ld b,a
                ld a,(sc_dir)
                inc a
                and 3
                call ray
                ld a,(sc_sum)
                add a,c
                inc a
                ret

; Parameter je Stufe: L (geradeaus frei genug), R (Reichweite), Zufallskurven-Maske, Fehler-Maske
ai_par:
                db 1,6,0x3F,0x03        ; leicht:  reagiert erst direkt vor dem Hindernis, sieht kurz, macht Fehler
                db 4,14,0x7F,0x0F       ; mittel:  weicht rechtzeitig aus, gelegentliche Fehlwahl
                db 8,20,0,0             ; schwer:  weit voraus, bewertet den Raum, keine Zufaelle

; IX = Kontext des Computers: Richtung fuer den naechsten Schritt waehlen
ai_think:
                ld a,(ix+C_STAT)
                cp 1
                ret nz
                ld a,(ix+C_X)
                ld (ai_x),a
                ld a,(ix+C_Y)
                ld (ai_y),a
                ld a,(ix+C_MDIR)
                ld (ai_m),a
                ld a,(level)
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,ai_par
                add hl,de
                ld a,(hl)
                ld (ai_L),a
                inc hl
                ld a,(hl)
                ld (ai_R),a
                inc hl
                ld a,(hl)
                ld (ai_rm),a
                inc hl
                ld a,(hl)
                ld (ai_mm),a
                ld a,(ai_y)
                ld d,a
                ld a,(ai_x)
                ld e,a
                ld a,(ai_L)
                ld b,a
                ld a,(ai_m)
                call ray                ; C = freie Pixel voraus (max. L)
                ld a,(ai_L)
                cp c
                jr z,at_str             ; weit genug frei: geradeaus
                ld a,(ai_m)
                call score_dir
                ld (ai_s0),a
                ld a,(ai_m)
                add a,3
                and 3
                ld (ai_cl),a
                call score_dir
                ld (ai_s1),a
                ld a,(ai_m)
                inc a
                and 3
                ld (ai_cr),a
                call score_dir
                ld (ai_s2),a
                ld a,(ai_mm)            ; Fehlentscheidung: zufaellig einen freien Kandidaten waehlen
                or a
                jr z,at_best
                ld b,a
                call rand8
                and b
                jr nz,at_best
                call rand8
                and 3
                cp 3
                jr c,at_m1
                ld a,2
at_m1:          ld e,a
                ld d,0
                ld hl,ai_s0
                add hl,de
                ld a,(hl)
                or a
                jr z,at_best            ; gewaehlter Zug ist blockiert: lieber den besten
                ld a,e
                jr at_pick
at_best:        ld a,(ai_s0)            ; bester Zug, bei Gleichstand geradeaus
                ld b,a
                ld c,0
                ld a,(ai_s1)
                cp b
                jr z,at_b1
                jr c,at_b1
                ld b,a
                ld c,1
at_b1:          ld a,(ai_s2)
                cp b
                jr z,at_b2
                jr c,at_b2
                ld b,a
                ld c,2
at_b2:          ld a,c
at_pick:        or a
                jr z,at_str
                dec a
                ld a,(ai_cl)
                jr z,at_set
                ld a,(ai_cr)
at_set:         ld (ix+C_DIR),a
                ret
at_str:         ld a,(ix+C_MDIR)
                ld (ix+C_DIR),a
                ld a,(ai_rm)            ; gelegentlich eine freiwillige Kurve (nur in offenes Gelaende)
                or a
                ret z
                ld b,a
                call rand8
                and b
                ret nz
                call rand8
                and 1
                ld a,(ai_m)
                jr z,at_rl
                inc a
                jr at_rc
at_rl:          add a,3
at_rc:          and 3
                ld (ai_cr),a
                call score_dir
                ld c,a
                ld a,(ai_R)
                add a,a
                cp c
                jr z,at_ok
                ret nc                  ; Bewertung kleiner als 2*R: nicht offen genug
at_ok:          ld a,(ai_cr)
                ld (ix+C_DIR),a
                ret


; ------------------------------------------------------------
;  Stufe 8: Titelmusik (3 Kanaele, 50 Hz-Takt), Bedien-Blip
; ------------------------------------------------------------
; Kanal-Block (16 Byte): +0/1 Zeiger, +2 Restdauer, +3 Bilder seit Notenbeginn, +4 Tonregister,
; +5 Lautstaerkeregister, +6 Startlautstaerke, +7 Mindestlautstaerke, +8/9 Anfang (Schleife),
; +10 aktuelle Note (0 = Pause), +11/12 aktuelle Periode
mus_tpl:
                dw mus_a
                db 0,0,0,8,12,7
                dw mus_a
                db 0
                dw 0
                db 0,0,0
                dw mus_b
                db 0,0,2,9,12,9
                dw mus_b
                db 0
                dw 0
                db 0,0,0
                dw mus_c
                db 0,0,4,10,9,4
                dw mus_c
                db 0
                dw 0
                db 0,0,0

mus_start:
                ld hl,mus_tpl
                ld de,MUSCH
                ld bc,48
                ldir
                ld a,1
                ld (mus_on),a
                xor a
                ld (sfx_cnt),a
                ld a,7
                ld e,0x38               ; drei Toene, kein Rauschen
                jp ay_wr

mus_stop:
                xor a
                ld (mus_on),a
                ld (sfx_cnt),a
                jp ay_silence

; jedes Bild im Titelbild
music_step:
                ld a,(mus_on)
                or a
                ret z
                ld ix,MUSCH
                call chan_step
                ld ix,MUSCH+16
                call chan_step
                ld ix,MUSCH+32
                call chan_step
                ld a,(sfx_cnt)
                or a
                ret z
                dec a
                ld (sfx_cnt),a
                jr z,sf_end
                ld hl,blip_tab
                ld e,a
                ld d,0
                add hl,de
                ld e,(hl)
                ld a,4
                call ay_wr
                ld a,5
                ld e,0
                call ay_wr
                ld a,12
                call vol_apply
                ld e,a
                ld a,10
                jp ay_wr
sf_end:         ld a,4                  ; Kanal C wieder auf die laufende Note
                ld e,(ix+11)
                call ay_wr
                ld a,5
                ld e,(ix+12)
                jp ay_wr
blip_tab:       db 0,90,120

; Bedien-Blip (Menue): kurzer Ton auf Kanal C ueber der Musik
ui_blip:
                ld a,(mus_on)
                or a
                ret z
                ld a,3
                ld (sfx_cnt),a
                ret

; IX = Kanal-Block
chan_step:
                ld a,(ix+2)
                or a
                call z,chan_load
                call chan_vol
                dec (ix+2)
                ret

chan_load:
                ld l,(ix+0)
                ld h,(ix+1)
                ld a,(hl)
                cp 0xFF
                jr nz,cl1
                ld l,(ix+8)             ; Ende der Folge: von vorn
                ld h,(ix+9)
                ld a,(hl)
cl1:            ld (ix+10),a
                inc hl
                ld b,(hl)
                inc hl
                ld (ix+0),l
                ld (ix+1),h
                ld (ix+2),b
                ld (ix+3),0
                or a
                ret z                   ; Pause
                dec a
                ld l,a
                ld h,0
                add hl,hl
                ld de,ptab
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ix+11),e
                ld (ix+12),d
                ld a,(ix+4)
                call ay_wr
                ld a,(ix+4)
                inc a
                ld e,d
                jp ay_wr

; Lautstaerke: fallend von Startwert bis Minimum (alle 4 Bilder um 1), mit eingestellter Lautstaerke skaliert
chan_vol:
                ld a,(ix+10)
                ld e,0
                or a
                jr z,cv_w
                ld a,(ix+3)
                srl a
                srl a
                ld b,a
                ld a,(ix+6)
                sub b
                jr c,cv_min
                cp (ix+7)
                jr nc,cv2
cv_min:         ld a,(ix+7)
cv2:            call vol_apply
                ld e,a
cv_w:           ld a,(ix+5)
                call ay_wr
                inc (ix+3)
                ret

ptab:
                dw 1695,1599,1510,1425,1345,1270,1198,1131
                dw 1068,1008,951,898,847,800,755,712
                dw 673,635,599,566,534,504,476,449
                dw 424,400,377,356,336,317,300,283
                dw 267,252,238,224,212,200,189,178
                dw 168,159,150,141,133,126,119,112
                dw 106,100,94,89,84,79,75,71
                dw 67,63,59,56
mus_a:
                db 46,30,49,10,48,20,46,20,41,40,0,40,42,30,46,10
                db 44,20,42,20,37,40,0,40,41,30,44,10,41,20,39,20
                db 37,40,0,40,39,30,44,10,42,20,41,20,39,40,0,40
                db 255,0
mus_b:
                db 10,10,10,10,22,10,10,10,10,10,10,10,22,10,10,10
                db 10,10,10,10,22,10,10,10,10,10,10,10,22,10,10,10
                db 18,10,18,10,30,10,18,10,18,10,18,10,30,10,18,10
                db 18,10,18,10,30,10,18,10,18,10,18,10,30,10,18,10
                db 13,10,13,10,25,10,13,10,13,10,13,10,25,10,13,10
                db 13,10,13,10,25,10,13,10,13,10,13,10,25,10,13,10
                db 8,10,8,10,20,10,8,10,8,10,8,10,20,10,8,10
                db 8,10,8,10,20,10,8,10,8,10,8,10,20,10,8,10
                db 255,0
mus_c:
                db 22,5,25,5,29,5,34,5,29,5,25,5,29,5,34,5
                db 22,5,25,5,29,5,34,5,29,5,25,5,29,5,25,5
                db 22,5,25,5,29,5,34,5,29,5,25,5,29,5,34,5
                db 22,5,25,5,29,5,34,5,29,5,25,5,29,5,25,5
                db 18,5,22,5,25,5,30,5,25,5,22,5,25,5,30,5
                db 18,5,22,5,25,5,30,5,25,5,22,5,25,5,22,5
                db 18,5,22,5,25,5,30,5,25,5,22,5,25,5,30,5
                db 18,5,22,5,25,5,30,5,25,5,22,5,25,5,22,5
                db 13,5,17,5,20,5,25,5,20,5,17,5,20,5,25,5
                db 13,5,17,5,20,5,25,5,20,5,17,5,20,5,17,5
                db 13,5,17,5,20,5,25,5,20,5,17,5,20,5,25,5
                db 13,5,17,5,20,5,25,5,20,5,17,5,20,5,17,5
                db 20,5,24,5,27,5,32,5,27,5,24,5,27,5,32,5
                db 20,5,24,5,27,5,32,5,27,5,24,5,27,5,24,5
                db 20,5,24,5,27,5,32,5,27,5,24,5,27,5,32,5
                db 20,5,24,5,27,5,32,5,27,5,24,5,27,5,24,5
                db 255,0

; Pause: Taste P (Port 0xDFFE Bit 0), nur waehrend der Fahrt
read_pause:
                ld a,0xDF
                in a,(0xFE)
                and 1
                ld b,a
                ld a,(p_prev)
                ld c,a
                ld a,b
                ld (p_prev),a
                or a
                ret nz
                ld a,c
                or a
                ret z
                ld a,(state)
                or a
                ret nz
                ld a,(paused)
                xor 1
                ld (paused),a
                jr z,rp_off
                call ay_silence
                ld a,ATTR_TITLE
                ld hl,str_pause
                jr rp_pr
rp_off:         ld a,ATTR_TITLE
                ld hl,str_blank5
rp_pr:          ld (txt_attr),a
                ld d,1
                ld e,13
                jp print_str

str_pause:      db 10,24,23,21,17,0xFF                     ; PAUSE
str_blank5:     db 15,15,15,15,15,0xFF

; ------------------------------------------------------------
;  Jingles ueber Kanal A: Tabelle = (Dauer, Periode lo, Periode hi) ..., 0
; ------------------------------------------------------------
; HL = Tabelle
jingle_start:
                ld (jptr),hl
                xor a
                ld (jcnt),a
                ld a,7
                ld e,0x3E               ; nur Ton A
                jp ay_wr

jingle_step:
                ld hl,(jptr)
                ld a,h
                or l
                ret z
                ld a,(jcnt)
                or a
                jr z,js_next
                dec a
                ld (jcnt),a
                ret
js_next:        ld a,(hl)
                or a
                jr z,js_end
                inc hl
                ld (jcnt),a
                xor a
                call ay_out_hl          ; Periode lo
                ld a,1
                call ay_out_hl          ; Periode hi
                ld (jptr),hl
                ld a,12
                call vol_apply
                ld e,a
                ld a,8
                jp ay_wr
js_end:         ld hl,0
                ld (jptr),hl
                jp ay_silence

beep_cd:        db 8,126,0, 0                               ; A5
beep_go:        db 20,63,0, 0                               ; A6
jingle_win:     db 8,212,0, 8,168,0, 14,106,0, 0            ; C5 E5 C6
jingle_draw:    db 12,27,1, 16,167,1, 0  ; G4 C4
jingle_lose:    db 10,27,1, 10,80,1, 24,167,1, 0           ; G4 E4 C4
fanfare_lose:   db 14,212,0, 14,27,1, 14,80,1, 50,167,1, 0 ; C5 G4 E4 C4
fanfare:        db 8,212,0, 8,168,0, 8,141,0, 8,106,0, 8,141,0, 40,106,0, 0

; A = Radius: Funken fuer jeden gecrashten Spieler (Mitte = sein Kopf)
sparks_both:
                ld (spk_r),a
                ld ix,CTX1
                call spark_ctx
                ld ix,CTX2
spark_ctx:
                ld a,(ix+C_STAT)
                cp 2
                ret nz
                ld a,(ix+C_X)
                ld (scx),a
                ld a,(ix+C_Y)
                ld (scy),a
                ld a,(spk_r)
                jp sparks_xor

; A = Radius: drei Ringe (Radius, Radius-3, Radius-6) mit je 8 Funken per XOR
sparks_xor:
                ld c,a
                or a
                ret z
                ld b,3
sx1:            push bc
                call ring8
                pop bc
                ld a,c
                sub 3
                ret z
                ret c
                ld c,a
                djnz sx1
                ret

; C = Radius (>= 1), Mitte = (scx,scy); Funken ausserhalb des Bildes entfallen
ring8:
                ld ix,dirtab
                ld b,8
r8l:            push bc
                ld a,(scx)
                ld l,a
                ld h,0
                ld a,(ix+0)
                call add_off
                ld a,h
                or a
                jr nz,r8skip
                ld e,l
                ld a,(scy)
                ld l,a
                ld h,0
                ld a,(ix+1)
                call add_off
                ld a,h
                or a
                jr nz,r8skip
                ld a,l
                cp 192
                jr nc,r8skip
                ld d,a
                call pixel_xor
r8skip:         inc ix
                inc ix
                pop bc
                djnz r8l
                ret

; HL = HL + A * C   (A = 0, 1 oder 0xFF; C = Radius; 16 Bit)
add_off:
                or a
                ret z
                cp 1
                jr z,ao_plus
                ld a,l
                sub c
                ld l,a
                ret nc
                dec h
                ret
ao_plus:        ld a,l
                add a,c
                ld l,a
                ret nc
                inc h
                ret

; D=y, E=x: Pixel umschalten
pixel_xor:
                call pixel_addr
                xor (hl)
                ld (hl),a
                ret

; Richtungen (dx,dy): hoch, hoch-rechts, rechts, runter-rechts, runter, runter-links, links, hoch-links
dirtab:         db 0,0xFF, 1,0xFF, 1,0, 1,1, 0,1, 0xFF,1, 0xFF,0, 0xFF,0xFF

; ------------------------------------------------------------
;  Sound ueber den AY-3-8912 (128K): Register 0xFFFD, Daten 0xBFFD
; ------------------------------------------------------------
; A = Register, E = Wert
ay_wr:
                ld bc,0xFFFD
                out (c),a
                ld b,0xBF
                out (c),e
                ret

; A = Register, (HL) = Wert, HL wird weitergezaehlt
ay_out_hl:
                ld bc,0xFFFD
                out (c),a
                ld a,(hl)
                inc hl
                ld b,0xBF
                out (c),a
                ret

; A = Register, (HL) = Lautstaerke 0..15, wird mit der eingestellten Lautstaerke skaliert
ay_out_vol:
                ld bc,0xFFFD
                out (c),a
                ld a,(hl)
                inc hl
                push hl
                call vol_apply
                pop hl
                ld bc,0xBFFD
                out (c),a
                ret

; A = Lautstaerke 0..15 -> skaliert mit vol (0..5) ueber voltab
vol_apply:
                ld b,a
                ld a,(vol)
                add a,a
                add a,a
                add a,a
                add a,a
                add a,b
                ld c,a
                ld b,0
                ld hl,voltab
                add hl,bc
                ld a,(hl)
                ret

; Zeile je Stufe 0..5, Spalte = Lautstaerke 0..15 (gerundet raw*stufe/5)   [erzeugt von tools/aytab.py]
voltab:
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
                db 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
                db 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
                db 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
                db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

; alles stumm: Lautstaerken 0, Mixer alles aus
ay_silence:
                ld e,0
                ld a,8
                call ay_wr
                ld a,9
                call ay_wr
                ld a,10
                call ay_wr
                ld a,7
                ld e,0x3F
                jp ay_wr

; Crash-Sound pro Bild k = anim (1..30): sechs Register aus aytab
; Kanal A+B: Rauschen (hell -> dumpf, laut -> leise), Kanal C: tiefer fallender Ton
crash_sound:
                ld a,(anim)
                dec a
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl               ; 4k
                add hl,de
                add hl,de               ; 6k
                ld de,aytab
                add hl,de
                ld a,6                  ; Rauschperiode
                call ay_out_hl
                ld a,8                  ; Lautstaerke A
                call ay_out_vol
                ld a,9                  ; Lautstaerke B
                call ay_out_vol
                ld a,10                 ; Lautstaerke C
                call ay_out_vol
                ld a,4                  ; Tonperiode C, tief
                call ay_out_hl
                ld a,5                  ; Tonperiode C, hoch
                jp ay_out_hl

; je Bild: Rauschperiode, Lautstaerke A, B, C, Tonperiode C (lo, hi)   [erzeugt von tools/aytab.py]
aytab:
                db 3,15,13,13,144,1
                db 4,15,13,12,213,1
                db 4,14,12,12,26,2
                db 5,14,12,11,95,2
                db 6,13,11,11,164,2
                db 7,13,11,10,233,2
                db 7,12,10,9,46,3
                db 8,12,10,9,115,3
                db 9,11,9,8,184,3
                db 10,11,9,8,253,3
                db 10,10,8,7,66,4
                db 11,10,8,6,135,4
                db 12,9,7,6,204,4
                db 12,9,7,5,17,5
                db 13,8,6,5,86,5
                db 14,8,6,4,154,5
                db 15,7,5,4,223,5
                db 15,7,5,3,36,6
                db 16,6,4,2,105,6
                db 17,6,4,2,174,6
                db 17,5,3,1,243,6
                db 18,5,3,1,56,7
                db 19,4,2,0,125,7
                db 20,4,2,0,194,7
                db 20,3,1,0,7,8
                db 21,3,1,0,76,8
                db 22,2,0,0,145,8
                db 23,2,0,0,214,8
                db 23,1,0,0,27,9
                db 24,1,0,0,96,9


; ------------------------------------------------------------
;  Bildschirm
; ------------------------------------------------------------
cls:
                ld hl,0x4000
                ld de,0x4001
                ld bc,6143
                ld (hl),0
                ldir
                ld hl,0x5800
                ld de,0x5801
                ld bc,767
                ld (hl),ATTR_BLACK
                ldir
                ret

; D=Zeile, E=Spalte -> HL = Adresse des ersten Bitmap-Bytes der Zelle
cell_addr:
                ld a,d
                and 0x18
                or 0x40
                ld h,a
                ld a,d
                and 7
                rrca
                rrca
                rrca
                or e
                ld l,a
                ret

; D=Zeile, E=Spalte -> HL = Attribut-Adresse (BC bleibt erhalten)
attr_addr:
                ld h,0
                ld l,d
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld d,0
                add hl,de
                ld de,0x5800
                add hl,de
                ret

; D=Zeile, E=Spalte: Zelle voll setzen (DE bleibt erhalten)
solid_cell:
                push de
                call cell_addr
                ld b,8
sc1:            ld (hl),0xFF
                inc h
                djnz sc1
                pop de
                ret

; ------------------------------------------------------------
;  Stufe 9: Arenen
; ------------------------------------------------------------
; Hindernis-Zelle: voll gesetzt, eigene Wandfarbe (DE bleibt erhalten)
obst_cell:
                call solid_cell
                push de
                call attr_addr
                ld (hl),ATTR_OBST
                pop de
                ret

; Rechteck aus Hindernissen: D/E = Zeile/Spalte links oben, B = Hoehe, C = Breite
obst_rect:
                push de
                push bc
orr_r:          push de
                push bc
orr_c:          push bc
                call obst_cell
                pop bc
                inc e
                dec c
                jr nz,orr_c
                pop bc
                pop de
                inc d
                djnz orr_r
                pop bc
                pop de
                ret

; zeichnet die Arena der Runde (arena_cur wird aus arena bestimmt)
draw_arena:
                ld a,(arena)
                cp 4
                jr nz,da_set
                call rand8
                and 3
da_set:         ld (arena_cur),a
                or a
                ret z
                dec a
                jr z,da_block
                dec a
                jr z,da_pillars
                ; Rahmen mit Luecken: Ring Spalten 9-22, Zeilen 8-17
                ld d,8
                ld e,9
                ld b,1
                ld c,6                  ; oben links (Spalten 9-14)
                call obst_rect
                ld e,17
                call obst_rect          ; oben rechts (17-22)
                ld d,17
                ld e,9
                call obst_rect          ; unten links
                ld e,17
                call obst_rect          ; unten rechts
                ld d,9
                ld e,9
                ld b,3
                ld c,1                  ; links oben (Zeilen 9-11)
                call obst_rect
                ld e,22
                call obst_rect
                ld d,14
                ld e,9
                call obst_rect          ; links unten (14-16)
                ld e,22
                jp obst_rect
da_block:       ld d,11
                ld e,14
                ld b,4
                ld c,4
                jp obst_rect
da_pillars:     ld hl,pillar_tab
dp_l:           ld d,(hl)
                inc hl
                ld a,d
                cp 0xFF
                ret z
                ld e,(hl)
                inc hl
                push hl
                call obst_cell
                pop hl
                jr dp_l
pillar_tab:     db 7,6, 7,12, 7,19, 7,25
                db 18,6, 18,12, 18,19, 18,25
                db 0xFF

draw_frame:
                ld e,0
df1:            ld d,ROW_FRAME_TOP
                call solid_cell
                ld d,ROW_FRAME_BOT
                call solid_cell
                inc e
                ld a,e
                cp 32
                jr nz,df1
                ld d,ROW_FRAME_TOP+1
df2:            ld e,COL_FRAME_L
                call solid_cell
                ld e,COL_FRAME_R
                call solid_cell
                inc d
                ld a,d
                cp ROW_FRAME_BOT
                jr nz,df2
                ret

; Attribute von Rahmen und Spielfeld (Feld schwarz, Rahmen violett)
draw_field_attrs:
                ld d,ROW_FRAME_TOP
dfa_r:          ld e,0
dfa_c:          ld a,d
                cp ROW_FRAME_TOP
                jr z,dfa_frame
                cp ROW_FRAME_BOT
                jr z,dfa_frame
                ld a,e
                cp COL_FRAME_L
                jr z,dfa_frame
                cp COL_FRAME_R
                jr z,dfa_frame
                ld c,ATTR_FIELD         ; Feld komplett schwarz (Gitter entfernt)
                jr dfa_set
dfa_frame:      ld c,ATTR_FRAME
dfa_set:        push de
                call attr_addr
                ld (hl),c
                pop de
                inc e
                ld a,e
                cp 32
                jr nz,dfa_c
                inc d
                ld a,d
                cp 24
                jr nz,dfa_r
                ret

; ------------------------------------------------------------
;  Text (eigener Mini-Zeichensatz, unabhaengig von der ROM)
;  Glyphen: 0-9 Ziffern, 10=P, 11=T, 12=R, 13=O, 14=N, 15=Leerzeichen,
;           16=G, 17=E, 18=W, 19=I, 20=M, 21=S
; ------------------------------------------------------------
; A=Glyphe, D=Zeile, E=Spalte (DE bleibt erhalten)
put_glyph:
                push de
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,font
                add hl,bc
                push hl
                call cell_addr
                ex de,hl
                pop hl
                ld b,8
pg1:            ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz pg1
                pop de
                ret

; HL=String (Glyphen, Ende 0xFF), D=Zeile, E=Startspalte, txt_attr = Farbe
print_str:
                ld a,(hl)
                cp 0xFF
                ret z
                push hl
                call put_glyph
                push de
                call attr_addr
                ld a,(txt_attr)
                ld (hl),a
                pop de
                pop hl
                inc hl
                inc e
                jr print_str

draw_hud:
                ld a,ATTR_P1
                ld (txt_attr),a
                ld hl,str_p1
                ld d,0
                ld e,1
                call print_str
                ld a,ATTR_TITLE
                ld (txt_attr),a
                ld hl,str_title
                ld d,0
                ld e,14
                call print_str
                ld a,ATTR_P2
                ld (txt_attr),a
                ld hl,str_p2
                ld d,0
                ld e,27
                call print_str
                ld a,ATTR_P1            ; Siege
                ld (txt_attr),a
                ld a,(score1)
                ld d,0
                ld e,4
                call show_glyph
                ld a,ATTR_P2
                ld (txt_attr),a
                ld a,(score2)
                ld d,0
                ld e,30
                call show_glyph
                ld a,ATTR_P1            ; Gesamtpunkte
                ld (txt_attr),a
                ld hl,pts1
                ld de,0x0101
                call draw_pts
                ld a,ATTR_P2
                ld (txt_attr),a
                ld hl,pts2
                ld de,0x011B
                jp draw_pts

; Gesamtpunkte: 4 Dezimalziffern, 1 Punkt je Schritt, +100 je gewonnener Runde
clear_pts:
                ld hl,pts1
                ld de,pts1+1
                ld bc,7
                ld (hl),0
                ldir
                ret

; IX = Kontext: Punkt fuer den Schritt, Anzeige der Ziffern auffrischen
pts_step:
                ld a,(ix+C_ID)
                cp 1
                ld hl,pts1+3
                ld de,0x0101
                ld a,ATTR_P1
                jr z,ps_go
                ld hl,pts2+3
                ld de,0x011B
                ld a,ATTR_P2
ps_go:          ld (txt_attr),a
                push de
                ld b,4
                call pt_inc
                pop de
                ld a,(ix+C_ID)
                ld hl,pts1
                cp 1
                jr z,draw_pts
                ld hl,pts2
                ; weiter mit draw_pts

; HL = 4 Ziffern, D = Zeile, E = Spalte, txt_attr = Farbe
draw_pts:
                ld b,4
dp1:            push bc
                push hl
                push de
                ld a,(hl)
                call show_glyph
                pop de
                pop hl
                pop bc
                inc hl
                inc e
                djnz dp1
                ret

; HL = Ziffer (Einer-, Hunderter...), B = Anzahl Ziffern bis zur Tausenderstelle: +1 mit Uebertrag
pt_inc:
                inc (hl)
                ld a,(hl)
                cp 10
                ret c
                ld (hl),0
                dec hl
                djnz pt_inc
                inc hl                  ; Ueberlauf: auf 9999 begrenzen
                ld b,4
                ld a,9
pt_sat:         ld (hl),a
                inc hl
                djnz pt_sat
                ret

str_p1:         db 10,1,15,0xFF
str_title:      db 11,12,13,14,0xFF
str_p2:         db 10,2,15,0xFF

; Ergebnis in HUD-Zeile 1: "P1 GEWINNT", "P2 GEWINNT" oder "REMIS"
show_result:
                ld a,(result)
                cp 3
                jr z,sr_draw
                cp 2
                jr z,sr_p2
                ld a,ATTR_P1
                ld hl,str_p1win
                ld e,11
                jr sr_print
sr_p2:          ld a,ATTR_P2
                ld hl,str_p2win
                ld e,11
                jr sr_print
sr_draw:        ld a,ATTR_TITLE
                ld hl,str_draw
                ld e,13
sr_print:       ld (txt_attr),a
                ld d,1
                jp print_str

str_p1win:      db 10,1,15,16,17,18,19,14,14,11,0xFF
str_p2win:      db 10,2,15,16,17,18,19,14,14,11,0xFF
str_draw:       db 12,17,20,19,21,0xFF

font:           ; 0-9
                db 0x00,0x3C,0x46,0x4A,0x52,0x62,0x3C,0x00
                db 0x00,0x18,0x28,0x08,0x08,0x08,0x3E,0x00
                db 0x00,0x3C,0x42,0x02,0x3C,0x40,0x7E,0x00
                db 0x00,0x3C,0x42,0x0C,0x02,0x42,0x3C,0x00
                db 0x00,0x08,0x18,0x28,0x48,0x7E,0x08,0x00
                db 0x00,0x7E,0x40,0x7C,0x02,0x42,0x3C,0x00
                db 0x00,0x3C,0x40,0x7C,0x42,0x42,0x3C,0x00
                db 0x00,0x7E,0x02,0x04,0x08,0x10,0x10,0x00
                db 0x00,0x3C,0x42,0x3C,0x42,0x42,0x3C,0x00
                db 0x00,0x3C,0x42,0x3E,0x02,0x04,0x38,0x00
                ; P T R O N Leerzeichen
                db 0x00,0x7C,0x42,0x42,0x7C,0x40,0x40,0x00
                db 0x00,0xFE,0x10,0x10,0x10,0x10,0x10,0x00
                db 0x00,0x7C,0x42,0x42,0x7C,0x44,0x42,0x00
                db 0x00,0x3C,0x42,0x42,0x42,0x42,0x3C,0x00
                db 0x00,0x42,0x62,0x52,0x4A,0x46,0x42,0x00
                db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                ; G E W I M S
                db 0x00,0x3C,0x42,0x40,0x4E,0x42,0x3C,0x00
                db 0x00,0x7E,0x40,0x7C,0x40,0x40,0x7E,0x00
                db 0x00,0x42,0x42,0x42,0x5A,0x66,0x42,0x00
                db 0x00,0x3E,0x08,0x08,0x08,0x08,0x3E,0x00
                db 0x00,0x42,0x66,0x5A,0x42,0x42,0x42,0x00
                db 0x00,0x3C,0x40,0x3C,0x02,0x42,0x3C,0x00
                ; F U A
                db 0x00,0x7E,0x40,0x7C,0x40,0x40,0x40,0x00
                db 0x00,0x42,0x42,0x42,0x42,0x42,0x3C,0x00
                db 0x00,0x3C,0x42,0x42,0x7E,0x42,0x42,0x00
                ; L C H K D B >
                db 0x00,0x40,0x40,0x40,0x40,0x40,0x7E,0x00
                db 0x00,0x3C,0x42,0x40,0x40,0x42,0x3C,0x00
                db 0x00,0x42,0x42,0x7E,0x42,0x42,0x42,0x00
                db 0x00,0x44,0x48,0x70,0x48,0x44,0x42,0x00
                db 0x00,0x78,0x44,0x42,0x42,0x44,0x78,0x00
                db 0x00,0x7C,0x42,0x7C,0x42,0x42,0x7C,0x00
                db 0x00,0x60,0x30,0x18,0x30,0x60,0x00,0x00
                ; Z
                db 0x00,0x7E,0x04,0x08,0x10,0x20,0x7E,0x00

; ------------------------------------------------------------
;  Pixelroutinen (fuer die naechsten Stufen)
; ------------------------------------------------------------
; Zeilenadress-Tabelle: ytab[y] = Adresse des ersten Bytes der Pixelzeile y
init_ytab:
                ld hl,ytab
                ld c,0
yt1:            ld a,c
                and 0xC0
                rrca
                rrca
                rrca
                ld b,a
                ld a,c
                and 7
                or b
                or 0x40
                ld d,a                  ; High-Byte
                ld a,c
                and 0x38
                rlca
                rlca
                ld e,a                  ; Low-Byte
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                inc c
                ld a,c
                cp 192
                jr nz,yt1
                ret

; D=y (0..191), E=x (0..255) -> HL = Byte-Adresse, A = Bitmaske (DE bleibt)
pixel_addr:
                ld l,d
                ld h,0
                add hl,hl
                ld bc,ytab
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld a,e
                rrca
                rrca
                rrca
                and 0x1F
                or l
                ld l,a
                ld a,e
                and 7
                ld c,a
                ld b,0
                push hl
                ld hl,xmask
                add hl,bc
                ld a,(hl)
                pop hl
                ret

pixel_set:
                call pixel_addr
                or (hl)
                ld (hl),a
                ret

; Z = Pixel nicht gesetzt, NZ = gesetzt (Wand oder Spur)
pixel_test:
                call pixel_addr
                and (hl)
                ret

xmask:          db 0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01

; ------------------------------------------------------------
;  ULAplus (Ports 0xBF3B Auswahl / 0xFF3B Daten)
; ------------------------------------------------------------
; A=Wert: Palettenzelle 0 beschreiben und zuruecklesen, Z = gleich
dp_try:
                ld d,a
                ld bc,0xBF3B
                xor a
                out (c),a
                ld bc,0xFF3B
                out (c),d
                ld bc,0xBF3B
                xor a
                out (c),a
                ld bc,0xFF3B
                in a,(c)
                cp d
                ret

detect_plus:
                xor a
                ld (plus_avail),a
                ld a,0x55
                call dp_try
                ret nz
                ld a,0xAA
                call dp_try
                ret nz
                ld a,1
                ld (plus_avail),a
                ret

; plus_on = 1: Palette laden und ULAplus einschalten, sonst ausschalten
apply_mode:
                ld a,(plus_avail)
                or a
                ret z
                ld a,(plus_on)
                or a
                jr z,am_off
                call set_palette
                ld bc,0xBF3B
                ld a,0x40
                out (c),a
                ld bc,0xFF3B
                ld a,1
                out (c),a
                ret
am_off:         ld bc,0xBF3B
                ld a,0x40
                out (c),a
                ld bc,0xFF3B
                xor a
                out (c),a
                ret

; 64 Eintraege: CLUT = Flash*2 + Bright. Bright (Bit 4 des Index) bekommt die
; leuchtende Neon-Tabelle, ohne Bright die gedaempfte (Spuren), Flash wird nicht benutzt.
set_palette:
                ld d,0
sp1:            ld a,d
                and 0x10
                ld hl,palette_dim
                jr z,sp2
                ld hl,palette_vivid
sp2:            ld a,d
                and 15
                ld e,a
                ld a,l
                add a,e
                ld l,a
                jr nc,sp3
                inc h
sp3:            ld bc,0xBF3B
                out (c),d
                ld bc,0xFF3B
                ld a,(hl)
                out (c),a
                inc d
                ld a,d
                cp 64
                jr nz,sp1
                ret

; GRB 3-3-2:  Tinte 0-7, Paper 0-7 (Index 8-15)
palette_vivid:
                ; Tinte: schwarz, blau, orange, violett, gruen, cyan, gelb, weiss
                db 0x00,0x03,0x5C,0x1B,0xE0,0xE3,0xFC,0xFF
                db 0x00,0x01,0x5C,0x1B,0xE0,0xE3,0xFC,0xFF
palette_dim:    ; dieselben Farbtoene, etwa halb so hell (Spuren)
                db 0x00,0x01,0x30,0x0E,0x80,0x82,0x90,0x92
                db 0x00,0x01,0x5C,0x1B,0xE0,0xE3,0xFC,0xFF

; ------------------------------------------------------------
;  Tastatur: C schaltet den Farbraum um (nur mit ULAplus)
; ------------------------------------------------------------
read_keys:
                ld a,0xFE
                in a,(0xFE)
                and 0x08                ; 0 = gedrueckt
                ld b,a
                ld a,(key_prev)
                ld c,a
                ld a,b
                ld (key_prev),a
                or a
                ret nz
                ld a,c
                or a
                ret z
                ; steigende Flanke -> umschalten
                ld a,(plus_avail)
                or a
                ret z
                ld a,(plus_on)
                xor 1
                ld (plus_on),a
                call apply_mode
                ret

; ------------------------------------------------------------
;  Selbsttest (nur TESTMODE=1)
; ------------------------------------------------------------
                if TESTMODE
selftest:
                ld ix,testres           ; Ergebnis-Zeiger in IX (pixel_addr nutzt HL)
                ld d,40
                ld e,100
                call pixel_set
                ld d,40
                ld e,100
                call tst                ; 1: gesetztes Pixel
                ld d,40
                ld e,101
                call tst                ; 0: Nachbar
                ld d,100
                ld e,3
                call tst                ; 1: linke Wand
                ld d,100
                ld e,20
                call tst                ; 0: Feld
                ld d,50
                ld e,250
                call tst                ; 1: rechte Wand
                ld d,17
                ld e,100
                call tst                ; 1: oberer Rahmen
                ld d,185
                ld e,100
                call tst                ; 1: unterer Rahmen
                ld d,100
                ld e,127
                call tst                ; 0: Feldmitte
                ld d,191
                ld e,255
                call tst                ; 1: Ecke rechts unten
                ld d,20
                ld e,8
                call tst                ; 1: Ecke Wand/Feld (Zeile 2, Spalte 1)
                ld d,24
                ld e,8
                call tst                ; 0: erstes Feldpixel (Zeile 3, Spalte 1)
                ld d,0
                ld e,0
                call pixel_set          ; Testpixel links oben
                ld d,191
                ld e,0
                call pixel_set
                ret

tst:            call pixel_test
                jr z,tst0
                ld (ix+0),1
                inc ix
                ret
tst0:           ld (ix+0),0
                inc ix
                ret
                endif

                end start
