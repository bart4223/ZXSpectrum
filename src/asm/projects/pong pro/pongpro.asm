; ============================================================
;  PONG PRO  fuer ZX Spectrum 128K / +2 / +2A / +3  -  Maschinencode
;  Zwei Spieler, Sinclair-Interface-2-Joysticks
;    Stick 1 (Tasten 6-0): rechter Schlaeger, Feuer = Taste 0
;    Stick 2 (Tasten 1-5): linker Schlaeger,  Feuer = Taste 5
;
;  Neu gegenueber der 48K-Fassung:
;    - Doppelpuffer: Bank 5 und Bank 7 wechseln sich als sichtbarer
;      Bildschirm ab (Port $7FFD, Bit 3). Gezeichnet wird immer im
;      unsichtbaren Bild, umgeschaltet wird direkt nach dem Bild-
;      interrupt  ->  kein Flackern.
;    - AY-3-8912: Titelmusik, Siegesfanfare, Soundeffekte und
;      Schlagzeug, alles im IM2-Interrupt (50 Hz), die Spiel-
;      schleife wird nie mehr durch Toene blockiert.
;    - Farbschweif hinter dem Ball (Attribute, pro Puffer getrennt)
;    - Eigene Textausgabe, keine ROM-Aufrufe (nur der Zeichensatz
;      bei $3D00 wird gelesen, dazu bleibt das 48K-ROM eingeblendet)
;
;  Assembliert mit sjasmplus:  sjasmplus --nologo pongpro.asm
;  (erzeugt pongpro.sna und pongpro.bin, siehe SAVE-Zeilen am Ende)
; ============================================================
        DEVICE ZXSPECTRUM128
        ORG 0x8000

; ---- Einstellungen (hier kannst du drehen) ----------------
LEVEL0  EQU 3           ; voreingestelltes Tempo (1..5), im Startbild mit Stick aenderbar
                        ; Startgeschwindigkeit = Tempo Pixel/Bild (50 Bilder/s),
                        ; Maximum = Start+3 (hoechstens 7)
WINSC   EQU 5           ; Punkte zum Sieg
PSTEP   EQU 3           ; Schlaeger senkrecht: Pixel pro Bild
HSTEP   EQU 2           ; Schlaeger seitlich: Pixel pro Bild
; ---- feste Werte ------------------------------------------
PADH    EQU 24          ; Schlaegerhoehe
PXL0    EQU 10          ; linker Schlaeger: Grundstellung (linke Kante)
PXLMAX  EQU 62          ; ... weitester Vorstoss (Mitte der linken Haelfte)
PXR0    EQU 242         ; rechter Schlaeger: Grundstellung
PXRMIN  EQU 190         ; ... weitester Vorstoss (Mitte der rechten Haelfte)
TOPLIM  EQU 26          ; oberste y-Position (Schlaeger/Ball)
PADMAX  EQU 158         ; unterste y-Position des Schlaegers
TIE     EQU 0xFF        ; Musik: Note weiterklingen lassen

; ---- Speicherplan --------------------------------------------
;  $8000-$AFFF  Programm und Daten (Bank 2, immer eingeblendet)
;  $B000-$B0FF  Variablen
;  $B100-$B7F0  Stack
;  $B800-$B900  IM2-Vektortabelle, $B9B9: JP IMH
;  $C000-$FFFF  Bank 7 (zweiter Bildschirm) - dauerhaft eingeblendet
;  $4000-$7FFF  Bank 5 (erster Bildschirm)
STACKTOP EQU 0xB7F0
VARS    EQU 0xB000
pyl     EQU VARS+0      ; y linker Schlaeger
pyr     EQU VARS+1      ; y rechter Schlaeger
bx      EQU VARS+2      ; Ball x (linke Kante)
by      EQU VARS+3      ; Ball y (obere Kante)
dxv     EQU VARS+4      ; Ball dx (vorzeichenbehaftet)
dyv     EQU VARS+5      ; Ball dy (vorzeichenbehaftet)
spd     EQU VARS+6      ; aktuelle Geschwindigkeit
hits    EQU VARS+7      ; Treffer seit letzter Beschleunigung
sl      EQU VARS+8      ; Punkte links
sr      EQU VARS+9      ; Punkte rechts
serv    EQU VARS+10     ; Aufschlagrichtung: 0 = nach rechts, 1 = nach links
tmp     EQU VARS+11
tmp2    EQU VARS+12
level   EQU VARS+13     ; gewaehltes Tempo 1..5
spd0v   EQU VARS+14     ; Startgeschwindigkeit
spdmx   EQU VARS+15     ; Maximalgeschwindigkeit
selprev EQU VARS+16
selrow  EQU VARS+17
bcol    EQU VARS+18     ; Ball-Attribut (BRIGHT + INK)
bidx    EQU VARS+19     ; Index in COLTAB
firep   EQU VARS+20     ; Feuerknopf im letzten Bild gedrueckt?
gptr    EQU VARS+21     ; (2 Bytes) Zeiger auf Zeichenbild
vol     EQU VARS+23     ; Lautstaerke 0 (aus) .. 5 (voll)
pxl     EQU VARS+24     ; x linker Schlaeger (muss pyl+24 sein!)
pxr     EQU VARS+25     ; x rechter Schlaeger (muss pyr+24 sein!)
lmin    EQU VARS+30
lmax    EQU VARS+31
sndf    EQU VARS+32     ; Ton vormerken: 1 = Schlaeger, 2 = Wand
bufhi   EQU VARS+33     ; Zeichenpuffer: $00 = Bank 5 ($4000), $80 = Bank 7 ($C000)
dispsel EQU VARS+34     ; sichtbarer Bildschirm: 0 = Bank 5, 1 = Bank 7
p7ffd   EQU VARS+35     ; Kopie von Port $7FFD (Port ist nicht lesbar)
recp    EQU VARS+36     ; (2 Bytes) Zeiger auf den Aufzeichnungssatz des Zeichenpuffers
hcount  EQU VARS+38     ; Laenge der Ballspur (0..6)
hist    EQU VARS+39     ; 6 x (Zeile,Spalte) Ballspur, neuester zuerst (12 Bytes)
pratt   EQU VARS+51     ; Text-Attribut
prrow   EQU VARS+52     ; Textzeile
prcol   EQU VARS+53     ; Textspalte
frames  EQU VARS+54     ; Bildzaehler (vom Interrupt erhoeht)
bflash  EQU VARS+55     ; Rahmenblitz: Restbilder
logoan  EQU VARS+56     ; Logo-Farbwechsel aktiv?
musicon EQU VARS+57
mptr    EQU VARS+58     ; (2 Bytes) aktuelle Notenzeile
msong   EQU VARS+60     ; (2 Bytes) Liedanfang
mtick   EQU VARS+62     ; Restbilder der Zeile
mnA     EQU VARS+63
mnB     EQU VARS+64
mvA     EQU VARS+65
mvB     EQU VARS+66
sfxfr   EQU VARS+67     ; Effekt: Restbilder (0 = frei)
sfxprio EQU VARS+68
sfxper  EQU VARS+69     ; (2 Bytes) Periode
sfxdlt  EQU VARS+71     ; (2 Bytes) Periodenaenderung pro Bild
sfxvol  EQU VARS+73     ; Lautstaerke 0..255 (obere 4 Bit = AY-Wert)
sfxvdec EQU VARS+74
sfxnoi  EQU VARS+75
sfxtone EQU VARS+76
AYR     EQU VARS+80     ; Schatten der AY-Register 0..10 (11 Bytes)
BREC0   EQU VARS+0x80   ; Aufzeichnung fuer Bank 5
BREC1   EQU VARS+0xA0   ; Aufzeichnung fuer Bank 7
; Aufbau eines Aufzeichnungssatzes: was steht gerade in diesem Puffer?
R_BX    EQU 0           ; Ball x
R_BY    EQU 1           ; Ball y
R_PLX   EQU 2           ; linker Schlaeger x
R_PLY   EQU 3           ; linker Schlaeger y
R_PRX   EQU 4           ; rechter Schlaeger x
R_PRY   EQU 5           ; rechter Schlaeger y
R_VALID EQU 6           ; Ball gezeichnet?
R_TN    EQU 7           ; Anzahl gefaerbter Spurzellen
R_TR    EQU 8           ; 6 x (Zeile,Spalte)

; ---- Makros ---------------------------------------------------
        MACRO GRP n1,n2,n3,bs,d1,d2     ; 4 Zeilen: Arpeggio n1,n2,n3,n2 + Bass + Schlagzeug
        DEFB 6,n1,bs,d1
        DEFB 6,n2,TIE,0
        DEFB 6,n3,TIE,d2
        DEFB 6,n2,TIE,0
        ENDM
        MACRO SFXD prio,fr,per,dlt,vol16,vdec,noi,tone
        DEFB prio,fr
        DEFW per
        DEFW dlt
        DEFB vol16,vdec,noi,tone
        ENDM

; ============================================================
START:  DI
        LD (OLDSP),SP
        LD SP,STACKTOP
        LD HL,VARS
        LD DE,VARS+1
        LD BC,255
        LD (HL),0
        LDIR
        LD A,7
        LD (pratt),A
        ; ---- Test: ist wirklich ein 128er da? (Bank-Umschaltung wirkt)
        LD BC,0x7FFD
        LD A,0x10
        OUT (C),A               ; Bank 0 nach $C000
        LD A,0xA5
        LD (0xC000),A
        LD A,0x11
        OUT (C),A               ; Bank 1 nach $C000
        LD A,0x5A
        LD (0xC000),A
        LD A,0x10
        OUT (C),A               ; wieder Bank 0
        LD A,(0xC000)
        CP 0xA5
        JP NZ,NO128
        ; ---- 48K-BASIC-ROM (Zeichensatz bei $3D00), Bank 7 dauerhaft nach $C000, Bildschirm Bank 5
        ;      +2A/+3: ROM 3 = 48K-ROM braucht Bit 2 von Port $1FFD. Auf dem 128K/+2 landet
        ;      dieser Schreibzugriff (unvollstaendige Decodierung) ebenfalls in $7FFD und wird
        ;      durch den naechsten Schreibzugriff sofort ueberschrieben - Reihenfolge nicht aendern!
        LD BC,0x1FFD
        LD A,0x04
        OUT (C),A
        LD BC,0x7FFD
        LD A,0x17
        LD (p7ffd),A
        OUT (C),A
        LD A,0x3C               ; AY-Mixer: alle Toene ausser C, kein Rauschen
        LD (AYR+7),A
        ; ---- IM2: Tabelle $B800..$B900 voller $B9, Sprung bei $B9B9
        LD HL,0xB800
        LD DE,0xB801
        LD BC,256
        LD (HL),0xB9
        LDIR
        LD A,0xC3
        LD (0xB9B9),A
        LD HL,IMH
        LD (0xB9BA),HL
        LD A,0xB8
        LD I,A
        IM 2
        EI
        CALL SETUP
        LD A,5
        LD (vol),A
        XOR A
        LD (bidx),A
        LD A,0x47
        LD (bcol),A
        LD A,LEVEL0
        LD (level),A
        CALL SETLEVEL
        CALL SPLASH

NEWGAME:
        CALL TOBANK5
        LD HL,0x4000
        CALL CLSBUF
        LD HL,0xC000
        CALL CLSBUF
        XOR A
        LD (sl),A
        LD (sr),A
        LD (hits),A
        LD (serv),A
        LD (sndf),A
        LD (hcount),A
        LD A,(spd0v)
        LD (spd),A
        LD A,92
        LD (pyl),A
        LD (pyr),A
        LD A,PXL0
        LD (pxl),A
        LD A,PXR0
        LD (pxr),A
        LD A,1
        LD (firep),A
        CALL MUSICSTOP
        LD IX,BREC0
        XOR A
        CALL INITBUF            ; Bank 5: Spielfeld, Schlaeger, Stand
        LD IX,BREC1
        LD A,0x80
        CALL INITBUF            ; Bank 7: dasselbe
        CALL SETBACK
        CALL SERVE

; ---- Hauptschleife: genau ein Durchlauf pro Bild (50 Hz) ----
;  Erst rechnen und ins unsichtbare Bild zeichnen, dann HALT,
;  dann sofort umschalten (noch im oberen Rand -> kein Tearing).
MAIN:   CALL FIRECOL            ; Feuerknopf = naechste Ballfarbe
        CALL MOVEPADS
        CALL MOVEBALL
        OR A
        JR NZ,SCORED
        CALL UPDHIST
        CALL RENDER
        CALL SNDREQ
MAIN_HALT:
        HALT
        CALL FLIP
        CALL SETBACK
        JR MAIN

; ---- Punkt gefallen: A=1 links punktet, A=2 rechts punktet ----
SCORED: CP 1
        JR NZ,SC2
        LD A,(sl)
        INC A
        LD (sl),A
        XOR A
        LD (serv),A
        JR SC3
SC2:    LD A,(sr)
        INC A
        LD (sr),A
        LD A,1
        LD (serv),A
SC3:    CALL HIDEBOTH           ; Ball und Spur aus beiden Puffern entfernen
        LD A,4
        CALL PRBOTH             ; neuer Stand in beiden Puffern
        LD HL,SFX_SCORE
        CALL SFXPLAY
        LD A,2                  ; roter Rahmen fuer ein paar Bilder
        OUT (254),A
        LD A,12
        LD (bflash),A
        LD B,28
SC4:    HALT
        DJNZ SC4
        LD A,(sl)
        CP WINSC
        JP Z,GAMEOVER
        LD A,(sr)
        CP WINSC
        JP Z,GAMEOVER
        LD A,(spd0v)
        LD (spd),A
        XOR A
        LD (hits),A
        CALL SERVE
        JP MAIN

; ---- Spielende ----------------------------------------------
GAMEOVER:
        CALL TOBANK5
        LD HL,0x4000
        CALL CLSBUF
        LD HL,MSGOVER
        CALL PRSTR
        LD A,64
        CALL PRBIG
        CALL FINCOLORS
        LD A,(sl)
        CP WINSC
        LD HL,MSGL
        JR Z,GO1
        LD HL,MSGR
GO1:    CALL PRSTR
        LD HL,MSGFIRE
        CALL PRSTR
        LD HL,MSGHINT
        CALL PRSTR
        LD A,17
        LD (selrow),A
        CALL PRTEMPO
        CALL PRVOL
        LD HL,SONG_WIN          ; Fanfare, waehrend der Siegerbildschirm schon steht
        CALL MUSICSTART
        CALL SELECTLOOP
        JP NEWGAME

; ---- kein 128er: Meldung und zurueck ins BASIC --------------
NO128:  LD A,0x10
        LD BC,0x7FFD
        OUT (C),A
        LD HL,MSGNO128
        CALL PRSTR
        LD SP,(OLDSP)
        EI
        RET

OLDSP:  DEFW 0

; ============================================================
;  Ball bewegen. Rueckgabe A: 0 = weiter, 1 = Ball rechts raus
;  (links punktet), 2 = Ball links raus (rechts punktet)
; ============================================================
MOVEBALL:
        ; ---- senkrecht ----
        LD A,(dyv)
        LD B,A
        LD A,(by)
        ADD A,B
        CP TOPLIM
        JR NC,MBV1
        LD A,TOPLIM
        JR MBVN
MBV1:   CP 179
        JR C,MBV2
        LD A,178
MBVN:   LD B,A
        LD A,2
        LD (sndf),A             ; Wandton
        LD A,(dyv)
        NEG
        LD (dyv),A
        LD A,B
MBV2:   LD (by),A
        ; ---- waagerecht ----
        LD A,(dxv)
        LD C,A                  ; C = dx
        LD A,(bx)
        ADD A,C
        LD D,A                  ; D = neues bx
        BIT 7,C
        JR NZ,MBLEFT
        ; --- Ball fliegt nach rechts: Trefferzone am rechten Schlaeger
        ;     bx in [pxr-4, pxr+4]  (Schlaegerbreite 4 + Ballbreite 4 + Spielraum)
        LD A,(pxr)
        SUB 4
        LD E,A
        LD A,D
        CP E
        JR C,MBR_NC             ; noch vor der Zone
        LD A,(pxr)
        ADD A,4
        LD E,A
        LD A,D
        CP E
        JR C,MBR_Z
        JR NZ,MBR_NC            ; schon hinter der Zone
MBR_Z:  LD A,(pyr)
        CALL HITTEST
        JR NC,MBR_NC
        LD A,(pxr)
        SUB 5
        LD (bx),A               ; Ball sitzt direkt vor dem Schlaeger
        LD A,(pyr)
        CALL PADHIT
        LD A,(spd)
        NEG
        LD (dxv),A
        XOR A
        RET
MBR_NC: LD A,D
        CP 248
        JR NC,MBR_OUT
        LD (bx),A
        XOR A
        RET
MBR_OUT:LD A,1
        RET
        ; --- Ball fliegt nach links: Trefferzone am linken Schlaeger
MBLEFT: LD A,(pxl)
        SUB 4
        LD E,A
        LD A,D
        CP E
        JR C,MBL_NC
        LD A,(pxl)
        ADD A,4
        LD E,A
        LD A,D
        CP E
        JR C,MBL_Z
        JR NZ,MBL_NC
MBL_Z:  LD A,(pyl)
        CALL HITTEST
        JR NC,MBL_NC
        LD A,(pxl)
        ADD A,5
        LD (bx),A
        LD A,(pyl)
        CALL PADHIT
        LD A,(spd)
        LD (dxv),A
        XOR A
        RET
MBL_NC: LD A,D
        CP 8
        JR C,MBL_OUT
        LD (bx),A
        XOR A
        RET
MBL_OUT:LD A,2
        RET

; ---- Trifft der Ball (y) den Schlaeger mit Oberkante A? Carry = Treffer
HITTEST:LD E,A
        LD A,(by)
        ADD A,3
        CP E
        JR C,HT_NO              ; Ball-Unterkante ueber dem Schlaeger
        LD A,E
        ADD A,PADH-1
        LD E,A
        LD A,(by)
        CP E
        JR C,HT_YES
        JR Z,HT_YES
HT_NO:  AND A
        RET
HT_YES: SCF
        RET

; ---- Schlaegertreffer: neuer Winkel, Ton, Tempo steigern
PADHIT: LD E,A
        LD A,(by)
        ADD A,2
        SUB E
        SUB 12                  ; A = Trefferabstand zur Mitte (-13..13)
        LD D,A
        BIT 7,A
        JR Z,PHA
        NEG
PHA:    LD B,A                  ; B = |Abstand|
        LD A,(spd)
        CP 3
        JR C,PHK
        LD A,3                  ; Winkel waechst nur bis Tempo 3 mit
PHK:    LD E,A
        XOR A
PHM:    ADD A,B                 ; A = |Abstand| * Tempo
        DEC E
        JR NZ,PHM
        LD B,0
PHD:    CP 12                   ; B = A / 12
        JR C,PHQ
        SUB 12
        INC B
        JR PHD
PHQ:    LD A,B
        OR A
        JR NZ,PHS
        INC A                   ; mindestens 1
PHS:    BIT 7,D
        JR Z,PH1
        NEG                     ; ueber der Mitte -> Ball nach oben
PH1:    LD (dyv),A
        LD A,(hits)
        INC A
        CP 3
        JR C,PH2
        LD A,(spdmx)
        LD B,A
        LD A,(spd)
        CP B
        JR NC,PH3
        INC A
        LD (spd),A
PH3:    XOR A
PH2:    LD (hits),A
        LD A,1
        LD (sndf),A             ; Ton wird im Hauptprogramm gestartet
        RET

; ============================================================
;  Schlaeger steuern (nur noch Zustand aendern, gezeichnet wird in RENDER)
; ============================================================
MOVEPADS:
        ; links = Stick 2 (Tasten 1-5): hoch 4 (Bit 3), runter 3 (Bit 2), links 1 (Bit 0), rechts 2 (Bit 1)
        LD BC,0xF7FE
        IN A,(C)
        LD E,A
        LD B,0                  ; B = Schritt senkrecht
        LD C,0                  ; C = Schritt seitlich
        BIT 3,E
        JR NZ,MP1
        LD B,256-PSTEP
MP1:    BIT 2,E
        JR NZ,MP2
        LD B,PSTEP
MP2:    BIT 0,E
        JR NZ,MP3
        LD C,256-HSTEP
MP3:    BIT 1,E
        JR NZ,MP4
        LD C,HSTEP
MP4:    LD A,PXL0
        LD (lmin),A
        LD A,PXLMAX
        LD (lmax),A
        LD HL,pyl
        CALL STEER
        ; rechts = Stick 1 (Tasten 6-0): hoch 9 (Bit 1), runter 8 (Bit 2), links 6 (Bit 4), rechts 7 (Bit 3)
        LD BC,0xEFFE
        IN A,(C)
        LD E,A
        LD B,0
        LD C,0
        BIT 1,E
        JR NZ,MP5
        LD B,256-PSTEP
MP5:    BIT 2,E
        JR NZ,MP6
        LD B,PSTEP
MP6:    BIT 4,E
        JR NZ,MP7
        LD C,256-HSTEP
MP7:    BIT 3,E
        JR NZ,MP8
        LD C,HSTEP
MP8:    LD A,PXRMIN
        LD (lmin),A
        LD A,PXR0
        LD (lmax),A
        LD HL,pyr
        CALL STEER
        RET

; Schlaeger bewegen. HL = Adresse von py (px liegt 24 Bytes dahinter),
; B = Schritt senkrecht, C = Schritt seitlich, (lmin)/(lmax) = Grenzen fuer px
STEER:  LD A,(HL)
        ADD A,B
        CP TOPLIM
        JR NC,ST1
        LD A,TOPLIM
ST1:    CP PADMAX+1
        JR C,ST2
        LD A,PADMAX
ST2:    LD (HL),A               ; neues y
        LD DE,24
        ADD HL,DE               ; HL = Adresse von px
        LD A,(HL)
        ADD A,C
        LD E,A                  ; E = Kandidat fuer neues px
        LD A,(lmin)
        CP E
        JR C,ST3                ; lmin < Kandidat
        JR Z,ST3
        LD E,A                  ; Kandidat < lmin -> auf lmin
ST3:    LD A,(lmax)
        CP E
        JR NC,ST4               ; lmax >= Kandidat
        LD E,A                  ; Kandidat > lmax -> auf lmax
ST4:    LD (HL),E
        RET

; ============================================================
;  Doppelpuffer
; ============================================================
; Sichtbaren Bildschirm zwischen Bank 5 und Bank 7 umschalten
FLIP:   LD A,(dispsel)
        XOR 1
        LD (dispsel),A
        LD A,(p7ffd)
        XOR 8
        LD (p7ffd),A
        LD BC,0x7FFD
        OUT (C),A
        RET

; Zeichenpuffer = der gerade unsichtbare Bildschirm
SETBACK:LD A,(dispsel)
        OR A
        JR NZ,SB1
        LD A,0x80               ; Bank 5 sichtbar -> in Bank 7 ($C000) zeichnen
        LD (bufhi),A
        LD HL,BREC1
        LD (recp),HL
        RET
SB1:    XOR A                   ; Bank 7 sichtbar -> in Bank 5 ($4000) zeichnen
        LD (bufhi),A
        LD HL,BREC0
        LD (recp),HL
        RET

; Bank 5 sichtbar machen, in Bank 5 zeichnen (Menues, Textausgabe)
TOBANK5:LD A,(dispsel)
        OR A
        CALL NZ,FLIP
        XOR A
        LD (bufhi),A
        RET

; Bildschirm loeschen: HL = $4000 oder $C000 (Pixel 0, Attribute 7)
CLSBUF: LD D,H
        LD E,L
        INC DE
        LD (HL),0
        LD BC,0x17FF
        LDIR
        LD H,D
        LD L,E
        LD D,H
        LD E,L
        INC DE
        LD (HL),7
        LD BC,0x02FF
        LDIR
        RET

; Puffer vorbereiten: A = bufhi ($00/$80), IX = Aufzeichnungssatz
INITBUF:LD (bufhi),A
        CALL DRAWCOURT
        CALL DRAWPADS
        LD A,4
        CALL PRBIG
        LD A,(pxl)
        LD (IX+R_PLX),A
        LD A,(pyl)
        LD (IX+R_PLY),A
        LD A,(pxr)
        LD (IX+R_PRX),A
        LD A,(pyr)
        LD (IX+R_PRY),A
        XOR A
        LD (IX+R_VALID),A
        LD (IX+R_TN),A
        RET

; Spielstand in beide Puffer schreiben (A = obere Pixelzeile)
PRBOTH: PUSH AF
        XOR A
        LD (bufhi),A
        POP AF
        PUSH AF
        CALL PRBIG
        LD A,0x80
        LD (bufhi),A
        POP AF
        CALL PRBIG
        JP SETBACK

; Ball und Spur aus beiden Puffern entfernen
HIDEBOTH:
        XOR A
        LD (bufhi),A
        LD IX,BREC0
        CALL ERASEREC
        LD A,0x80
        LD (bufhi),A
        LD IX,BREC1
        CALL ERASEREC
        JP SETBACK

; Ballspur fortschreiben: Zelle der Ballmitte vorn einfuegen
UPDHIST:LD HL,hist+9
        LD DE,hist+11
        LD BC,10
        LDDR                    ; Eintraege 0..4 -> 1..5
        LD A,(by)
        ADD A,2
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (hist),A             ; Zeile
        LD A,(bx)
        ADD A,2
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (hist+1),A           ; Spalte
        LD A,(hcount)
        CP 6
        RET NC
        INC A
        LD (hcount),A
        RET

; Alles Bewegliche im Zeichenpuffer auf den aktuellen Zustand bringen:
; alte Position (laut Aufzeichnungssatz) per XOR loeschen, neue zeichnen.
RENDER: LD IX,(recp)
        CALL ERASEREC           ; alter Ball + alte Spur weg
        ; ---- linker Schlaeger (nur wenn er sich gegenueber diesem Puffer bewegt hat)
        LD A,(pxl)
        CP (IX+R_PLX)
        JR NZ,RN_L
        LD A,(pyl)
        CP (IX+R_PLY)
        JR Z,RN_R
RN_L:   LD C,(IX+R_PLX)
        LD A,(IX+R_PLY)
        LD B,PADH
        CALL DRAWSPR
        LD A,(pxl)
        LD (IX+R_PLX),A
        LD C,A
        LD A,(pyl)
        LD (IX+R_PLY),A
        LD B,PADH
        CALL DRAWSPR
        ; ---- rechter Schlaeger
RN_R:   LD A,(pxr)
        CP (IX+R_PRX)
        JR NZ,RN_R2
        LD A,(pyr)
        CP (IX+R_PRY)
        JR Z,RN_T
RN_R2:  LD C,(IX+R_PRX)
        LD A,(IX+R_PRY)
        LD B,PADH
        CALL DRAWSPR
        LD A,(pxr)
        LD (IX+R_PRX),A
        LD C,A
        LD A,(pyr)
        LD (IX+R_PRY),A
        LD B,PADH
        CALL DRAWSPR
        ; ---- Ballspur: aktuelle Zellen merken und faerben (aelteste zuerst)
RN_T:   LD A,(hcount)
        LD (IX+R_TN),A
        PUSH IX
        POP HL
        LD DE,R_TR
        ADD HL,DE
        EX DE,HL
        LD HL,hist
        LD BC,12
        LDIR
        LD A,(IX+R_TN)
        CP 2
        JR C,RN_B
        DEC A
        LD B,A                  ; B = Alter der aeltesten Zelle (= Index)
        PUSH IX
        POP HL
        LD DE,R_TR
        ADD HL,DE
        LD E,B
        LD D,0
        ADD HL,DE
        ADD HL,DE               ; HL -> Eintrag Nr. B
RN_TL:  LD A,(HL)               ; Zeile
        INC HL
        LD C,(HL)               ; Spalte
        DEC HL
        DEC HL
        DEC HL                  ; HL -> vorheriger (juengerer) Eintrag
        PUSH HL
        PUSH BC
        LD HL,TRCOL
        LD E,B
        LD D,0
        ADD HL,DE
        LD E,(HL)               ; Farbe passend zum Alter
        POP BC
        CALL SETCELL
        POP HL
        DJNZ RN_TL
        ; ---- Ball
RN_B:   LD A,(bx)
        LD (IX+R_BX),A
        LD C,A
        LD A,(by)
        LD (IX+R_BY),A
        LD B,4
        CALL DRAWSPR
        LD A,(bx)
        LD C,A
        LD A,(by)
        LD B,A
        LD A,(bcol)
        LD E,A
        CALL BALLATTR
        LD (IX+R_VALID),1
        RET

; Ball und Spur aus dem Puffer von IX entfernen (Pixel per XOR, Attribute zurueck auf 7)
ERASEREC:
        LD A,(IX+R_VALID)
        OR A
        JR Z,ER_T
        LD C,(IX+R_BX)
        LD A,(IX+R_BY)
        LD B,4
        CALL DRAWSPR
        LD C,(IX+R_BX)
        LD B,(IX+R_BY)
        LD E,7
        CALL BALLATTR
        LD (IX+R_VALID),0
ER_T:   LD A,(IX+R_TN)
        OR A
        RET Z
        LD B,A
        PUSH IX
        POP HL
        LD DE,R_TR
        ADD HL,DE
ER_L:   LD A,(HL)
        INC HL
        LD C,(HL)
        INC HL
        PUSH HL
        LD E,7
        CALL SETCELL
        POP HL
        DJNZ ER_L
        LD (IX+R_TN),0
        RET

; ============================================================
;  Grafik
; ============================================================
; A = y (0..191), C = Spalte (0..31)  ->  HL = Bildschirmadresse im Zeichenpuffer
ROWADDR:LD H,A
        AND 7
        OR 0x40
        LD L,A
        LD A,H
        RRA
        RRA
        RRA
        AND 0x18
        OR L
        LD L,A
        LD A,H
        ADD A,A
        ADD A,A
        AND 0xE0
        OR C
        LD H,L
        LD L,A
        LD A,(bufhi)            ; $80 -> $4000 wird $C000
        OR H
        LD H,A
        RET

; eine Pixelzeile nach unten
DOWNHL: INC H
        LD A,H
        AND 7
        RET NZ
        LD A,L
        ADD A,32
        LD L,A
        RET C
        LD A,H
        SUB 8
        LD H,A
        RET

; Beide Schlaeger an ihren gespeicherten Positionen zeichnen
DRAWPADS:
        LD A,(pxl)
        LD C,A
        LD A,(pyl)
        LD B,PADH
        CALL DRAWSPR
        LD A,(pxr)
        LD C,A
        LD A,(pyr)
        LD B,PADH
        JP DRAWSPR

; Sprite 4 Pixel breit, pixelgenau (XOR): A = y, C = x (linke Kante), B = Zeilen
DRAWSPR:LD (tmp),A
        LD A,C
        AND 7
        LD E,A
        LD D,0
        LD HL,TAB1
        ADD HL,DE
        LD A,(HL)
        PUSH AF
        LD HL,TAB2
        ADD HL,DE
        LD A,(HL)
        LD E,A                  ; E = Muster rechtes Byte
        POP AF
        LD D,A                  ; D = Muster linkes Byte
        LD A,C
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD C,A                  ; C = Spalte
        LD A,(tmp)
        CALL ROWADDR
DS1:    LD A,(HL)
        XOR D
        LD (HL),A
        INC HL
        LD A,(HL)
        XOR E
        LD (HL),A
        DEC HL
        CALL DOWNHL
        DJNZ DS1
        RET

; Spielfeld: obere/untere Linie und gestrichelte Mittellinie
DRAWCOURT:
        LD C,0
        LD A,24
        CALL ROWADDR
        CALL FILLROW
        LD A,183
        CALL ROWADDR
        CALL FILLROW
        LD C,15
        LD E,28
DC1:    LD A,E
        AND 4
        JR NZ,DC2
        LD A,E
        CALL ROWADDR
        LD A,(HL)
        OR 1
        LD (HL),A
DC2:    INC E
        LD A,E
        CP 180
        JR C,DC1
        RET

FILLROW:LD B,32
        LD A,255
FR1:    LD (HL),A
        INC L
        DJNZ FR1
        RET

; ============================================================
;  Aufschlag: Ball in die Mitte, kurze Pause
; ============================================================
SERVE:  LD A,126
        LD (bx),A
        LD A,100
        LD (by),A
        LD A,(spd)
        INC A
        SRL A                   ; (Tempo+1)/2
        CP 3
        JR C,SVK
        LD A,2                  ; hoechstens 2
SVK:    LD B,A
        LD A,R
        RRA
        LD A,B
        JR NC,SV1
        NEG
SV1:    LD (dyv),A
        LD A,(spd)
        LD B,A
        LD A,(serv)
        OR A
        LD A,B
        JR Z,SV2
        NEG
SV2:    LD (dxv),A
        XOR A
        LD (hcount),A
        CALL UPDHIST
        CALL SETBACK
        CALL RENDER
        HALT
        CALL FLIP
        CALL SETBACK
        LD HL,SFX_SERVE
        CALL SFXPLAY
        LD B,40
SV3:    HALT
        DJNZ SV3
        RET

; ============================================================
;  Text (eigene Ausgabe, schreibt immer in Bank 5)
; ============================================================
SETUP:  XOR A
        OUT (254),A
        LD (bufhi),A
        RET

; Text ausgeben (HL), Ende = 255. Steuercodes wie im BASIC:
; 22,zeile,spalte  16,ink  17,paper  18,flash  19,bright
PRSTR:  LD A,(HL)
        CP 255
        RET Z
        INC HL
        CP 22
        JR Z,PS_AT
        CP 16
        JR Z,PS_INK
        CP 17
        JR Z,PS_PAP
        CP 18
        JR Z,PS_FLA
        CP 19
        JR Z,PS_BRI
        CALL PRCHAR
        JR PRSTR
PS_AT:  LD A,(HL)
        INC HL
        LD (prrow),A
        LD A,(HL)
        INC HL
        LD (prcol),A
        JR PRSTR
PS_INK: LD A,(HL)
        INC HL
        AND 7
        LD B,A
        LD A,(pratt)
        AND 0xF8
        OR B
        LD (pratt),A
        JR PRSTR
PS_PAP: LD A,(HL)
        INC HL
        AND 7
        ADD A,A
        ADD A,A
        ADD A,A
        LD B,A
        LD A,(pratt)
        AND 0xC7
        OR B
        LD (pratt),A
        JR PRSTR
PS_FLA: LD A,(HL)
        INC HL
        RRCA
        AND 0x80
        LD B,A
        LD A,(pratt)
        AND 0x7F
        OR B
        LD (pratt),A
        JR PRSTR
PS_BRI: LD A,(HL)
        INC HL
        RRCA
        RRCA
        AND 0x40
        LD B,A
        LD A,(pratt)
        AND 0xBF
        OR B
        LD (pratt),A
        JR PRSTR

; Zeichen A (32..127) an (prrow,prcol) mit Attribut pratt, Spalte weiterschieben
PRCHAR: PUSH BC
        PUSH DE
        PUSH HL
        SUB 32
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,0x3D00            ; Zeichensatz im ROM
        ADD HL,DE
        EX DE,HL                ; DE = Zeichenbild
        LD A,(prrow)
        LD B,A
        AND 0x18
        OR 0x40
        LD H,A
        LD A,B
        AND 7
        RRCA
        RRCA
        RRCA
        LD L,A
        LD A,(prcol)
        OR L
        LD L,A
        LD B,8
PCL:    LD A,(DE)
        LD (HL),A
        INC DE
        INC H
        DJNZ PCL
        LD A,(prcol)
        LD C,A
        LD A,(prrow)
        CALL ATTRADDR
        LD A,(pratt)
        LD (HL),A
        LD HL,prcol
        INC (HL)
        POP HL
        POP DE
        POP BC
        RET

; ============================================================
;  Ballfarbe: Attribute der vom Ball beruehrten Zellen setzen
; ============================================================
; B = y, C = x (Ball 4x4), E = Attributwert fuer alle beruehrten Zellen
BALLATTR:
        LD A,B
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (tmp),A              ; Zeile oben
        LD A,B
        ADD A,3
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (tmp2),A             ; Zeile unten
        LD A,C
        ADD A,3
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD D,A                  ; Spalte rechts
        LD A,C
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD C,A                  ; Spalte links
        LD A,(tmp)
        CALL SETCELL
        LD A,(tmp2)
        CALL SETCELL
        LD C,D
        LD A,(tmp)
        CALL SETCELL
        LD A,(tmp2)
        CALL SETCELL
        RET

; A = Zeile, C = Spalte, E = Attribut
SETCELL:CALL ATTRADDR
        LD (HL),E
        RET

; A = Zeile (0..23), C = Spalte  ->  HL = Attributadresse im Zeichenpuffer
ATTRADDR:
        RRCA
        RRCA
        RRCA
        LD L,A
        AND 3
        ADD A,0x58
        LD H,A
        LD A,L
        AND 0xE0
        OR C
        LD L,A
        LD A,(bufhi)
        OR H
        LD H,A
        RET

; Feuerknopf (Taste 0, Taste 5, Leertaste): bei neuem Druck naechste Farbe
FIRECOL:CALL READFIRE
        LD A,0
        RLA                     ; Carry -> A = 1 wenn Feuer
        LD B,A
        LD A,(firep)
        CP B
        LD A,B
        LD (firep),A
        RET Z                   ; unveraendert
        OR A
        RET Z                   ; losgelassen
        LD A,(bidx)
        INC A
        CP 6
        JR C,FC2
        XOR A
FC2:    LD (bidx),A
        LD E,A
        LD D,0
        LD HL,COLTAB
        ADD HL,DE
        LD A,(HL)
        LD (bcol),A
        RET

; ============================================================
;  Spielstand in doppelter Groesse (16x16 Pixel, ROM-Zeichensatz)
;  A = obere Pixelzeile, zeichnet in den Puffer bufhi
; ============================================================
PRBIG:  LD (tmp),A
        LD (tmp2),A
        LD C,12
        LD B,16
PBC:    PUSH BC
        LD A,(tmp2)
        CALL ROWADDR
        LD B,8
        XOR A
PBC2:   LD (HL),A
        INC HL
        DJNZ PBC2
        LD A,(tmp2)
        INC A
        LD (tmp2),A
        POP BC
        DJNZ PBC
        LD A,(sl)
        ADD A,'0'
        LD C,12
        CALL DRAWBIG
        LD A,':'
        LD C,15
        CALL DRAWBIG
        LD A,(sr)
        ADD A,'0'
        LD C,18
        CALL DRAWBIG
        RET

; A = Zeichencode, C = linke Spalte, (tmp) = obere Pixelzeile
DRAWBIG:SUB 32
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,0x3D00
        ADD HL,DE
        LD (gptr),HL
        LD A,(tmp)
        LD (tmp2),A
        LD B,8
DG1:    PUSH BC
        LD HL,(gptr)
        LD A,(HL)
        INC HL
        LD (gptr),HL
        CALL EXPAND
        LD A,(tmp2)
        CALL ROWADDR
        LD (HL),D
        INC HL
        LD (HL),E
        LD A,(tmp2)
        INC A
        LD (tmp2),A
        CALL ROWADDR
        LD (HL),D
        INC HL
        LD (HL),E
        LD A,(tmp2)
        INC A
        LD (tmp2),A
        POP BC
        DJNZ DG1
        RET

; A = Byte -> D:E = 16 Bit, jedes Bit verdoppelt
EXPAND: LD B,A
        RRCA
        RRCA
        RRCA
        RRCA
        AND 0x0F
        LD E,A
        LD D,0
        LD HL,EXP4
        ADD HL,DE
        LD A,(HL)
        PUSH AF
        LD A,B
        AND 0x0F
        LD E,A
        LD D,0
        LD HL,EXP4
        ADD HL,DE
        LD E,(HL)
        POP AF
        LD D,A
        RET

; Tempo aus Level berechnen
SETLEVEL:
        LD A,(level)
        LD (spd0v),A
        ADD A,3
        CP 8
        JR C,SLV1
        LD A,7
SLV1:   LD (spdmx),A
        RET

; Zeile "Tempo:  < n >" in Zeile (selrow) ausgeben
PRTEMPO:LD A,(selrow)
        LD (prrow),A
        LD A,6
        LD (prcol),A
        LD HL,MSGTEMPO
        CALL PRSTR
        LD A,(level)
        ADD A,'0'
        CALL PRCHAR
        LD HL,MSGEND
        CALL PRSTR
        RET

; Zeile "Lautstaerke: < n >" in Zeile (selrow)+1 ausgeben (0 = "aus")
PRVOL:  LD A,(selrow)
        INC A
        LD (prrow),A
        LD A,6
        LD (prcol),A
        LD HL,MSGVOL
        CALL PRSTR
        LD A,(vol)
        OR A
        JR NZ,PV1
        LD HL,MSGAUS
        CALL PRSTR
        JR PV2
PV1:    ADD A,'0'
        CALL PRCHAR
PV2:    LD HL,MSGEND
        CALL PRSTR
        RET

; Stick lesen: A = 0 nichts, 1 hoch, 2 runter, 3 links, 4 rechts
READSEL:LD BC,0xEFFE
        IN A,(C)
        LD E,A
        LD BC,0xF7FE
        IN A,(C)
        LD D,A
        BIT 1,E                 ; Stick 1 hoch (Taste 9)
        JR Z,RS_UP
        BIT 3,D                 ; Stick 2 hoch (Taste 4)
        JR Z,RS_UP
        BIT 2,E                 ; runter (Taste 8)
        JR Z,RS_DN
        BIT 2,D                 ; runter (Taste 3)
        JR Z,RS_DN
        BIT 4,E                 ; Stick 1 links (Taste 6)
        JR Z,RS_LF
        BIT 0,D                 ; Stick 2 links (Taste 1)
        JR Z,RS_LF
        BIT 3,E                 ; Stick 1 rechts (Taste 7)
        JR Z,RS_RT
        BIT 1,D                 ; Stick 2 rechts (Taste 2)
        JR Z,RS_RT
        XOR A
        RET
RS_UP:  LD A,1
        RET
RS_DN:  LD A,2
        RET
RS_LF:  LD A,3
        RET
RS_RT:  LD A,4
        RET

; Tempo (hoch/runter) und Lautstaerke (links/rechts) waehlen, Feuer = weiter
SELECTLOOP:
        XOR A
        LD (selprev),A
        CALL PRTEMPO
        CALL PRVOL
        LD B,25
SL0:    HALT
        DJNZ SL0
SL1:    HALT
        CALL LOGOCYC
        CALL READSEL
        LD B,A
        LD A,(selprev)
        CP B
        LD A,B
        LD (selprev),A
        JR Z,SL2                ; Zustand unveraendert
        OR A
        JR Z,SL2                ; losgelassen
        CP 1
        JR Z,SLUP
        CP 2
        JR Z,SLDN
        CP 3
        JR Z,SLVD
        LD A,(vol)              ; rechts: lauter
        CP 5
        JR NC,SL2
        INC A
        JR SLV
SLVD:   LD A,(vol)              ; links: leiser
        OR A
        JR Z,SL2
        DEC A
SLV:    LD (vol),A
        CALL PRVOL
        LD HL,SFX_TEST          ; Testton in neuer Lautstaerke
        CALL SFXPLAY
        JR SL2
SLUP:   LD A,(level)
        CP 5
        JR NC,SL2
        INC A
        JR SL4
SLDN:   LD A,(level)
        CP 2
        JR C,SL2
        DEC A
SL4:    LD (level),A
        CALL SETLEVEL
        CALL PRTEMPO
SL2:    CALL READFIRE
        JR NC,SL1
        RET

READFIRE:
        LD BC,0xEFFE
        IN A,(C)
        BIT 0,A
        JR Z,RF_YES
        LD BC,0xF7FE
        IN A,(C)
        BIT 4,A
        JR Z,RF_YES
        LD BC,0x7FFE
        IN A,(C)
        BIT 0,A
        JR Z,RF_YES
        AND A
        RET
RF_YES: SCF
        RET

; Logo im Startbild: alle acht Bilder die Farben der Zeilen weiterdrehen
LOGOCYC:LD A,(logoan)
        OR A
        RET Z
        LD A,(frames)
        AND 7
        RET NZ
        LD HL,0x5840            ; Zeilen 2..6 des Attributbereichs
        LD B,160
LC1:    LD A,(HL)
        CP 7
        JR Z,LC2                ; nicht Teil des Logos
        ADD A,8
        CP 0x3F
        JR C,LC3
        SUB 0x28                ; 0x17 (rot) .. 0x37 (gelb), dann wieder von vorn
LC3:    LD (HL),A
LC2:    INC HL
        DJNZ LC1
        RET

; Siegerbildschirm einfaerben: Farbbaender oben (Zeile 1) und unten (Zeile 22),
; Endstand: Sieger gruen, Verlierer rot, Doppelpunkt weiss
FINCOLORS:
        LD HL,BANDTAB
        LD DE,0x5820
        LD BC,32
        LDIR
        LD HL,BANDTAB
        LD DE,0x5AC0
        LD BC,32
        LDIR
        LD A,(sl)
        CP WINSC
        LD B,0x44               ; links gruen (hell)
        LD C,0x42               ; rechts rot (hell)
        JR Z,FCO1
        LD B,0x42
        LD C,0x44
FCO1:   LD A,B
        LD HL,0x590C            ; linke Ziffer: Zeilen 8/9, Spalten 12-13
        CALL FILL2
        LD A,0x47
        LD HL,0x590F            ; Doppelpunkt: Spalten 15-16
        CALL FILL2
        LD A,C
        LD HL,0x5912            ; rechte Ziffer: Spalten 18-19
        CALL FILL2
        RET

; A = Attribut, HL = Attributadresse: 2x2 Zellen setzen
FILL2:  LD (HL),A
        INC HL
        LD (HL),A
        LD DE,31
        ADD HL,DE
        LD (HL),A
        INC HL
        LD (HL),A
        RET

; Startbildschirm
SPLASH: LD HL,0x4000
        CALL CLSBUF
        LD HL,LETTERS
        LD DE,0x5844
        LD A,0x17
        LD (tmp),A
        LD C,5
SPR:    LD B,23
        PUSH DE
SPC:    LD A,(HL)
        INC HL
        CP '1'
        JR NZ,SPS
        LD A,(tmp)
        LD (DE),A
SPS:    INC DE
        DJNZ SPC
        POP DE
        LD A,E
        ADD A,32
        LD E,A
        JR NC,SPN
        INC D
SPN:    LD A,(tmp)
        ADD A,8
        LD (tmp),A
        DEC C
        JR NZ,SPR
        LD HL,MSG1
        CALL PRSTR
        LD HL,MSGHINT
        CALL PRSTR
        LD A,15
        LD (selrow),A
        CALL PRTEMPO
        CALL PRVOL
        LD A,1
        LD (logoan),A
        LD HL,SONG_TITLE        ; Titelmusik laeuft im Interrupt weiter
        CALL MUSICSTART
        CALL SELECTLOOP
        XOR A
        LD (logoan),A
        RET

; ============================================================
;  Ton: Anforderungen aus dem Spiel
; ============================================================
SNDREQ: LD A,(sndf)
        OR A
        RET Z
        LD B,A
        XOR A
        LD (sndf),A
        LD A,B
        CP 1
        LD HL,SFX_PAD
        JR Z,SQ1
        LD HL,SFX_WALL
SQ1:    JP SFXPLAY

; ============================================================
;  AY-Sound. Alles ab hier laeuft im 50-Hz-Interrupt (IM2).
; ============================================================
IMH:    PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD HL,frames
        INC (HL)
        CALL MUSICTICK
        CALL SFXTICK
        CALL AYDUMP
        LD A,(bflash)           ; Rahmenblitz abklingen lassen
        OR A
        JR Z,IMH2
        DEC A
        LD (bflash),A
        JR NZ,IMH2
        OUT (254),A             ; A = 0 -> schwarzer Rahmen
IMH2:   POP HL
        POP DE
        POP BC
        POP AF
        EI
        RETI

; Schatten-Register 0..10 in den AY schreiben
AYDUMP: LD HL,AYR
        LD D,0
        LD E,11
AYD1:   LD BC,0xFFFD
        OUT (C),D
        LD A,(HL)
        LD B,0xBF
        OUT (C),A
        INC HL
        INC D
        DEC E
        JR NZ,AYD1
        RET

; A = Wert 0..15 -> A = Wert * Lautstaerke/5
MASTERVOL:
        LD E,A
        LD A,(vol)
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,A
        OR E
        LD E,A
        LD D,0
        LD HL,VOLTAB
        ADD HL,DE
        LD A,(HL)
        RET

; A = Notenindex (0 = nichts aendern), HL = Ziel (2 Bytes Periode)
SETTONE:OR A
        RET Z
        DEC A
        LD E,A
        LD D,0
        PUSH HL
        LD HL,PERTAB
        ADD HL,DE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; ---- Musik: Zeilen zu je 4 Bytes: Dauer (Bilder), Note A, Note B, Schlagzeug
;      Dauer 0 = Lied von vorn, $FF = Ende. Note 0 = Pause, TIE = weiterklingen.
MUSICSTART:
        DI
        LD (mptr),HL
        LD (msong),HL
        XOR A
        LD (mtick),A
        LD (mvA),A
        LD (mvB),A
        INC A
        LD (musicon),A
        EI
        RET

MUSICSTOP:
        DI
        XOR A
        LD (musicon),A
        LD (sfxfr),A
        EI
        RET

MUSICTICK:
        LD A,(musicon)
        OR A
        JR NZ,MT_ON
        XOR A
        LD (AYR+8),A
        LD (AYR+9),A
        RET
MT_ON:  LD A,(mtick)
        OR A
        JR NZ,MT_RUN
        ; ---- naechste Zeile holen
        LD HL,(mptr)
        LD A,(HL)
        OR A
        JR NZ,MT_NF
        LD HL,(msong)           ; Dauer 0: Lied von vorn
        LD A,(HL)
MT_NF:  CP 0xFF
        JR NZ,MT_ROW
        XOR A                   ; Ende des Liedes
        LD (musicon),A
        LD (AYR+8),A
        LD (AYR+9),A
        RET
MT_ROW: LD (mtick),A
        INC HL
        LD A,(HL)               ; Note A
        INC HL
        CP TIE
        JR Z,MT_B
        LD (mnA),A
        LD C,12
        OR A
        JR NZ,MT_A1
        LD C,0
MT_A1:  LD A,C
        LD (mvA),A
MT_B:   LD A,(HL)               ; Note B
        INC HL
        CP TIE
        JR Z,MT_D
        LD (mnB),A
        LD C,11
        OR A
        JR NZ,MT_B1
        LD C,0
MT_B1:  LD A,C
        LD (mvB),A
MT_D:   LD A,(HL)               ; Schlagzeug
        INC HL
        LD (mptr),HL
        OR A
        JR Z,MT_RUN
        DEC A
        LD E,A
        LD D,0
        LD HL,DRUMTAB
        ADD HL,DE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL SFXSTART
MT_RUN: LD HL,mtick
        DEC (HL)
        LD A,(mnA)
        LD HL,AYR+0
        CALL SETTONE
        LD A,(mnB)
        LD HL,AYR+2
        CALL SETTONE
        LD A,(mvA)              ; leichtes Abklingen bis Stufe 6
        CP 7
        JR C,MT_V1
        DEC A
        LD (mvA),A
MT_V1:  LD A,(mvB)
        CP 7
        JR C,MT_V2
        DEC A
        LD (mvB),A
MT_V2:  LD A,(mvA)
        CALL MASTERVOL
        LD (AYR+8),A
        LD A,(mvB)
        CALL MASTERVOL
        LD (AYR+9),A
        RET

; ---- Effekte auf Kanal C: HL -> 10 Byte Beschreibung (SFXD)
SFXPLAY:DI
        CALL SFXSTART
        EI
        RET

SFXSTART:
        LD A,(sfxfr)
        OR A
        JR Z,SS_GO              ; frei
        LD A,(sfxprio)
        LD B,A
        LD A,(HL)
        CP B
        RET C                   ; laufender Effekt wichtiger
SS_GO:  LD A,(HL)
        INC HL
        LD (sfxprio),A
        LD A,(HL)
        INC HL
        LD (sfxfr),A
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (sfxper),DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (sfxdlt),DE
        LD A,(HL)
        INC HL
        LD (sfxvol),A
        LD A,(HL)
        INC HL
        LD (sfxvdec),A
        LD A,(HL)
        INC HL
        LD (sfxnoi),A
        LD A,(HL)
        LD (sfxtone),A
        RET

SFXTICK:LD A,(sfxfr)
        OR A
        JR Z,SX_OFF
        DEC A
        LD (sfxfr),A
        LD HL,(sfxper)
        LD (AYR+4),HL           ; Tonhoehe Kanal C
        LD DE,(sfxdlt)
        ADD HL,DE
        LD (sfxper),HL          ; naechstes Bild: Tonhoehe gleiten
        LD A,(sfxvol)
        LD B,A
        SRL A
        SRL A
        SRL A
        SRL A
        CALL MASTERVOL
        LD (AYR+10),A
        LD A,(sfxvdec)
        LD C,A
        LD A,B
        SUB C
        JR NC,SX_V
        XOR A
SX_V:   LD (sfxvol),A
        LD A,(sfxnoi)
        LD (AYR+6),A
        LD C,0x18               ; Rauschen A/B aus
        LD A,(sfxtone)
        OR A
        JR NZ,SX_M1
        LD A,C
        OR 4                    ; kein Ton auf C
        LD C,A
SX_M1:  LD A,(sfxnoi)
        OR A
        JR NZ,SX_M2
        LD A,C
        OR 0x20                 ; kein Rauschen auf C
        LD C,A
SX_M2:  LD A,C
        LD (AYR+7),A
        RET
SX_OFF: XOR A
        LD (AYR+10),A
        LD A,0x3C
        LD (AYR+7),A
        RET

; ============================================================
;  Daten
; ============================================================
BANDTAB:
        DEFB 0x50,0x50,0x70,0x70,0x60,0x60,0x68,0x68
        DEFB 0x58,0x58,0x50,0x50,0x70,0x70,0x60,0x60
        DEFB 0x68,0x68,0x58,0x58,0x50,0x50,0x70,0x70
        DEFB 0x60,0x60,0x68,0x68,0x58,0x58,0x50,0x50
COLTAB: DEFB 0x47,0x46,0x44,0x45,0x43,0x42     ; weiss, gelb, gruen, cyan, magenta, rot
; Ballspur: Papierfarbe je Alter 0..5 (0 wird vom Ball selbst ueberdeckt)
; nur zwei Stufen, dunkel: rot (Alter 1-2), dann blau (Alter 3-5)
TRCOL:  DEFB 0x47,0x17,0x17,0x0F,0x0F,0x0F
EXP4:   DEFB 0x00,0x03,0x0C,0x0F,0x30,0x33,0x3C,0x3F,0xC0,0xC3,0xCC,0xCF,0xF0,0xF3,0xFC,0xFF
TAB1:   DEFB 0xF0,0x78,0x3C,0x1E,0x0F,0x07,0x03,0x01
TAB2:   DEFB 0x00,0x00,0x00,0x00,0x00,0x80,0xC0,0xE0

LETTERS:
        DEFB "1111...111..1...1..1111"
        DEFB "1...1.1...1.11..1.1...."
        DEFB "1111..1...1.1.1.1.1..11"
        DEFB "1.....1...1.1..11.1...1"
        DEFB "1......111..1...1..111."

MSG1:   DEFB 22,8,5,"Pong Pro fuer zwei Spieler"
        DEFB 22,9,5,"mit AY-Musik und Effekten"
        DEFB 22,10,5,"Stick 1: rechter Schlaeger"
        DEFB 22,11,5,"Stick 2: linker Schlaeger"
        DEFB 22,12,5,"Schlaeger in 4 Richtungen"
        DEFB 22,13,6,"Erster mit 5 Punkten"
        DEFB 22,18,9,18,1,"FEUER = Start",18,0,255
MSGTEMPO:DEFB "Tempo:       < ",255
MSGVOL: DEFB "Lautstaerke: < ",255
MSGAUS: DEFB "aus",255
MSGEND: DEFB " >   ",255
MSGHINT:DEFB 22,19,4,"hoch/runter = Tempo"
        DEFB 22,20,4,"links/rechts = Lautstaerke"
        DEFB 22,21,4,"Feuer im Spiel = Ballfarbe",255
MSGOVER:DEFB 22,5,11,19,1,16,6,"SPIELENDE",16,7,19,0,255
MSGL:   DEFB 22,11,9,18,1,19,1,16,4,"LINKS gewinnt",18,0,16,7,19,0,255
MSGR:   DEFB 22,11,8,18,1,19,1,16,4,"RECHTS gewinnt",18,0,16,7,19,0,255
MSGFIRE:DEFB 22,15,6,18,1,16,5,"FEUER = neues Spiel",18,0,16,7,255
MSGNO128:DEFB 22,10,2,"Dieses Spiel braucht einen",22,11,2,"ZX Spectrum 128K (oder +2/+3).",255

; ---- Effekte: SFXD prio, bilder, periode, aenderung/bild, lautstaerke*16, abnahme/bild, rauschen, ton
SFX_PAD:  SFXD 3,7,84,5,240,30,0,1          ; heller Treffer, gleitet nach unten
SFX_WALL: SFXD 2,4,170,0,192,48,0,1         ; kurzer, tieferer Tick
SFX_SCORE:SFXD 4,30,70,18,240,8,14,1        ; fallender Ton mit Rauschen
SFX_SERVE:SFXD 2,8,300,-10,200,20,0,1       ; steigender Piep
SFX_TEST: SFXD 2,6,100,0,240,36,0,1         ; Lautstaerke-Test im Menue
DR_KICK:  SFXD 1,5,300,120,240,50,0,1       ; Bassdrum: Ton gleitet nach unten
DR_SNARE: SFXD 1,5,0,0,208,42,10,0          ; Snare: nur Rauschen
DR_HAT:   SFXD 1,2,0,0,128,60,3,0           ; Hi-Hat: kurzes Zischen
DRUMTAB:  DEFW DR_KICK,DR_SNARE,DR_HAT

; ---- Titelmusik (a-Moll, F, C, G), Dauer 0 = Schleife.
;      GRP: drei Arpeggio-Toene, Bassnote, Schlagzeug auf Zeile 1 und 3 der Gruppe
SONG_TITLE:
        GRP nA4,nC5,nE5,nA2,1,3
        GRP nA4,nC5,nE5,TIE,2,3
        GRP nC5,nE5,nA5,nE3,1,3
        GRP nE5,nC5,nA4,TIE,2,3
        GRP nF4,nA4,nC5,nF2,1,3
        GRP nF4,nA4,nC5,TIE,2,3
        GRP nA4,nC5,nF5,nC3,1,3
        GRP nC5,nA4,nF4,TIE,2,3
        GRP nG4,nC5,nE5,nC3,1,3
        GRP nG4,nC5,nE5,TIE,2,3
        GRP nC5,nE5,nG5,nG3,1,3
        GRP nE5,nC5,nG4,TIE,2,3
        GRP nG4,nB4,nD5,nG2,1,3
        GRP nG4,nB4,nD5,TIE,2,3
        GRP nB4,nD5,nG5,nD3,1,3
        GRP nD5,nB4,nG4,TIE,2,3
        DEFB 0

; ---- Siegesfanfare (spielt einmal), Dauer $FF = Ende
SONG_WIN:
        DEFB 5,nC5,nC3,1
        DEFB 5,nE5,TIE,0
        DEFB 5,nG5,nG3,2
        DEFB 5,nC6,TIE,0
        DEFB 5,nG5,nE3,1
        DEFB 5,nC6,TIE,3
        DEFB 5,nE6,nG3,2
        DEFB 5,nC6,TIE,0
        DEFB 8,nE6,nC3,1
        DEFB 8,nG6,nG3,0
        DEFB 70,nC6,nC4,2
        DEFB 0xFF

; (Notennamen, AY-Periodentabelle und Lautstaerketabelle folgen unten)
; ------------------------------------------------------------
;  Noten (Index 1 = C2 ... 60 = B6), AY-Takt 1,7734 MHz
; ------------------------------------------------------------
nC2   EQU 1
nCs2  EQU 2
nD2   EQU 3
nDs2  EQU 4
nE2   EQU 5
nF2   EQU 6
nFs2  EQU 7
nG2   EQU 8
nGs2  EQU 9
nA2   EQU 10
nAs2  EQU 11
nB2   EQU 12
nC3   EQU 13
nCs3  EQU 14
nD3   EQU 15
nDs3  EQU 16
nE3   EQU 17
nF3   EQU 18
nFs3  EQU 19
nG3   EQU 20
nGs3  EQU 21
nA3   EQU 22
nAs3  EQU 23
nB3   EQU 24
nC4   EQU 25
nCs4  EQU 26
nD4   EQU 27
nDs4  EQU 28
nE4   EQU 29
nF4   EQU 30
nFs4  EQU 31
nG4   EQU 32
nGs4  EQU 33
nA4   EQU 34
nAs4  EQU 35
nB4   EQU 36
nC5   EQU 37
nCs5  EQU 38
nD5   EQU 39
nDs5  EQU 40
nE5   EQU 41
nF5   EQU 42
nFs5  EQU 43
nG5   EQU 44
nGs5  EQU 45
nA5   EQU 46
nAs5  EQU 47
nB5   EQU 48
nC6   EQU 49
nCs6  EQU 50
nD6   EQU 51
nDs6  EQU 52
nE6   EQU 53
nF6   EQU 54
nFs6  EQU 55
nG6   EQU 56
nGs6  EQU 57
nA6   EQU 58
nAs6  EQU 59
nB6   EQU 60

PERTAB:
        DEFW 1695,1599,1510,1425,1345,1270,1198,1131
        DEFW 1068,1008,951,898,847,800,755,712
        DEFW 673,635,599,566,534,504,476,449
        DEFW 424,400,377,356,336,317,300,283
        DEFW 267,252,238,224,212,200,189,178
        DEFW 168,159,150,141,133,126,119,112
        DEFW 106,100,94,89,84,79,75,71
        DEFW 67,63,59,56

; Lautstaerke: Zeile = Master 0..5, Spalte = Wert 0..15
VOLTAB:
        DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DEFB 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
        DEFB 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
        DEFB 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
        DEFB 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
        DEFB 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

CODEEND:
        ASSERT CODEEND < 0xB000

        SAVESNA "pongpro.sna",START
        SAVEBIN "pongpro.bin",0x8000,CODEEND-0x8000
        END
