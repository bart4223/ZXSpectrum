; ============================================================
;  TRON fuer den ZX Spectrum 128K  -  Stufe 5: Match, Countdown, Pause, Jingles
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
ATTR_P1         equ 0x45        ; Cyan
ATTR_P2         equ 0x42        ; Rot/Orange
ATTR_TITLE      equ 0x46        ; Gelb
ATTR_P1_DIM     equ 0x05        ; Spur P1: Cyan, gedaempft (ohne BRIGHT)
ATTR_P2_DIM     equ 0x02        ; Spur P2: Orange, gedaempft
ATTR_CROSS_DIM  equ 0x07        ; Zelle von beiden befahren: Weiss, gedaempft

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

                call init_ytab
                call new_round

                if TESTMODE
                call selftest
                endif

                im 1
                ei
main:
                halt
                call read_keys
                call read_pause
                ld a,(paused)
                or a
                jr nz,main              ; Pause: nichts bewegt sich
                call read_joy1
                call read_joy2
                call dispatch
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
                jp match_step

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

; Neues Spielfeld aufbauen und beide Motorraeder an den Start setzen
new_round:
                call cls
                call draw_frame
                call draw_field_attrs
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

; Feuer: nur nach dem Matchende (neues Match); im Testbau startet es die Runde neu
fire_pressed:
                if TESTBUILD
                jp new_round
                else
                ld a,(state)
                cp 4
                ret nz
                ld a,(anim)
                cp 50
                ret c                   ; kurze Sperre, damit gedrueckt gehaltenes Feuer nicht sofort durchschlaegt
                xor a
                ld (score1),a
                ld (score2),a
                ld (match_over),a
                call clear_pts
                jp new_round
                endif

; Sinclair-Joystick 1 (Tasten 6-0, Port 0xEFFE, Bit = 0 wenn gedrueckt):
; Bit 4 links, Bit 3 rechts, Bit 2 runter, Bit 1 hoch, Bit 0 Feuer
read_joy1:
                ld a,0xEF
                in a,(0xFE)
                ld b,a
                bit 0,b
                jp z,fire_pressed
                ld ix,CTX1
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
                bit 4,b
                jp z,fire_pressed
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
                cp STEP_FRAMES
                ret c
                xor a
                ld (tick),a
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
                ld hl,jingle_win
                jr nz,cs_jg
                ld hl,jingle_draw
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
                ld hl,fanfare
                jp jingle_start

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
                ld a,8
                ld e,12
                jp ay_wr
js_end:         ld hl,0
                ld (jptr),hl
                jp ay_silence

beep_cd:        db 8,126,0, 0                               ; A5
beep_go:        db 20,63,0, 0                               ; A6
jingle_win:     db 8,212,0, 8,168,0, 14,106,0, 0            ; C5 E5 C6
jingle_draw:    db 12,27,1, 16,167,1, 0  ; G4 C4
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
                call ay_out_hl
                ld a,9                  ; Lautstaerke B
                call ay_out_hl
                ld a,10                 ; Lautstaerke C
                call ay_out_hl
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
