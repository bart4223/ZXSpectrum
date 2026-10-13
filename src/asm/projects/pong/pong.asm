; ============================================================
;  PONG fuer ZX Spectrum (48K)  -  Maschinencode
;  Zwei Spieler, Sinclair-Interface-2-Joysticks
;    Stick 1 (Tasten 6-0): rechter Schlaeger, Feuer = Taste 0
;    Stick 2 (Tasten 1-5): linker Schlaeger,  Feuer = Taste 5
;  Assembliert mit pasmo:  pasmo --tapbas pongmc.asm pongmc.tap
; ============================================================
        ORG 32768

; ---- Einstellungen (hier kannst du drehen) ----------------
LEVEL0  EQU 3           ; voreingestelltes Tempo (1..5), im Startbild mit Stick aenderbar
                        ; Startgeschwindigkeit = Tempo Pixel/Bild (50 Bilder/s),
                        ; Maximum = Start+3 (hoechstens 7)
WINSC   EQU 5           ; Punkte zum Sieg
PSTEP   EQU 3           ; Schlaegergeschwindigkeit in Pixel pro Bild
; ---- feste Werte ------------------------------------------
PADH    EQU 24          ; Schlaegerhoehe
PADPAT  EQU 0x3C        ; Schlaegerbild (4 Pixel breit)
TOPLIM  EQU 26          ; oberste y-Position (Schlaeger/Ball)
PADMAX  EQU 158         ; unterste y-Position des Schlaegers

; ---- Variablen (im RAM oberhalb des Programms) -------------
VARS    EQU 0xF000
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

; ============================================================
START:  EI
        CALL SETUP
        XOR A
        LD (bidx),A
        LD A,0x47
        LD (bcol),A
        LD A,LEVEL0
        LD (level),A
        CALL SETLEVEL
        CALL SPLASH

NEWGAME:
        CALL 0x0DAF             ; CLS
        CALL DRAWCOURT
        XOR A
        LD (sl),A
        LD (sr),A
        LD (hits),A
        LD (serv),A
        LD A,(spd0v)
        LD (spd),A
        LD A,92
        LD (pyl),A
        LD (pyr),A
        LD C,1
        CALL DRAWPAD
        LD A,92
        LD C,30
        CALL DRAWPAD
        LD A,1
        LD (firep),A
        LD A,4
        CALL PRBIG
        CALL SERVE

; ---- Hauptschleife: genau ein Durchlauf pro Bild (50 Hz) ----
MAIN:   HALT
        CALL ERASEBALL          ; Ball loeschen (XOR, Farbe zuruecksetzen)
        CALL FIRECOL            ; Feuerknopf = naechste Ballfarbe
        CALL MOVEPADS
        CALL MOVEBALL
        OR A
        JR NZ,SCORED
        CALL SHOWBALL           ; Ball neu zeichnen und faerben
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
SC3:    LD A,4
        CALL PRBIG
        LD B,200
        LD C,70
        CALL BEEP
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
        CALL SNDWIN
        CALL 0x0DAF
        LD HL,MSGOVER
        CALL PRSTR
        LD A,64
        CALL PRBIG
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
        CALL SELECTLOOP
        JP NEWGAME

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
        LD A,(dyv)
        NEG
        LD (dyv),A
        LD A,B
MBV2:   LD (by),A
        ; ---- waagerecht ----
        LD A,(dxv)
        LD C,A                  ; C = dx
        LD A,(bx)
        LD B,A                  ; B = altes bx
        ADD A,C
        LD D,A                  ; D = neues bx
        BIT 7,C
        JR NZ,MBLEFT
        ; --- Ball fliegt nach rechts ---
        LD A,B
        CP 239
        JR NC,MBR_NC            ; schon hinter der Schlaegerebene
        LD A,D
        CP 239
        JR C,MBR_NC             ; Ebene noch nicht erreicht
        LD A,(pyr)
        CALL HITTEST
        JR NC,MBR_NC
        LD A,238
        LD (bx),A
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
        ; --- Ball fliegt nach links ---
MBLEFT: LD A,B
        CP 14
        JR C,MBL_NC
        LD A,D
        CP 14
        JR NC,MBL_NC
        LD A,(pyl)
        CALL HITTEST
        JR NC,MBL_NC
        LD A,14
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
        LD B,110
        LD C,30
        CALL BEEP
        RET

; ============================================================
;  Schlaeger steuern
; ============================================================
MOVEPADS:
        ; links = Stick 2 (Tasten 1-5): hoch = 4 (Bit 3), runter = 3 (Bit 2)
        LD BC,0xF7FE
        IN A,(C)
        LD E,A
        LD B,0
        BIT 3,E
        JR NZ,MP1
        LD B,256-PSTEP
MP1:    BIT 2,E
        JR NZ,MP2
        LD B,PSTEP
MP2:    LD C,1
        LD HL,pyl
        CALL STEER
        ; rechts = Stick 1 (Tasten 6-0): hoch = 9 (Bit 1), runter = 8 (Bit 2)
        LD BC,0xEFFE
        IN A,(C)
        LD E,A
        LD B,0
        BIT 1,E
        JR NZ,MP3
        LD B,256-PSTEP
MP3:    BIT 2,E
        JR NZ,MP4
        LD B,PSTEP
MP4:    LD C,30
        LD HL,pyr
        CALL STEER
        RET

; HL = Adresse von py, C = Spalte, B = Schritt (vorzeichenbehaftet)
STEER:  LD A,B
        OR A
        RET Z
        LD A,(HL)
        ADD A,B
        CP TOPLIM
        JR NC,ST1
        LD A,TOPLIM
ST1:    CP PADMAX+1
        JR C,ST2
        LD A,PADMAX
ST2:    LD D,A
        LD A,(HL)
        CP D
        RET Z
        PUSH HL
        CALL DRAWPAD            ; alte Position loeschen
        POP HL
        LD A,D
        LD (HL),A
        CALL DRAWPAD            ; neue Position zeichnen
        RET

; ============================================================
;  Grafik
; ============================================================
; A = y (0..191), C = Spalte (0..31)  ->  HL = Bildschirmadresse
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

; Schlaeger (XOR) zeichnen/loeschen: A = y, C = Spalte
DRAWPAD:CALL ROWADDR
        LD B,PADH
DP1:    LD A,(HL)
        XOR PADPAT
        LD (HL),A
        CALL DOWNHL
        DJNZ DP1
        RET

; Ball (4x4, XOR) zeichnen/loeschen an (bx,by)
DRAWBALL:
        LD A,(bx)
        LD C,A
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
        LD A,(by)
        CALL ROWADDR
        LD B,4
DB1:    LD A,(HL)
        XOR D
        LD (HL),A
        INC HL
        LD A,(HL)
        XOR E
        LD (HL),A
        DEC HL
        CALL DOWNHL
        DJNZ DB1
        RET

COLTAB: DEFB 0x47,0x46,0x44,0x45,0x43,0x42     ; weiss, gelb, gruen, cyan, magenta, rot
EXP4:   DEFB 0x00,0x03,0x0C,0x0F,0x30,0x33,0x3C,0x3F,0xC0,0xC3,0xCC,0xCF,0xF0,0xF3,0xFC,0xFF
TAB1:   DEFB 0xF0,0x78,0x3C,0x1E,0x0F,0x07,0x03,0x01
TAB2:   DEFB 0x00,0x00,0x00,0x00,0x00,0x80,0xC0,0xE0

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
        CALL SHOWBALL
        LD B,40
SV3:    HALT
        DJNZ SV3
        RET

; ============================================================
;  Eingabe / Text / Ton
; ============================================================
SETUP:  XOR A
        OUT (254),A
        LD A,7
        LD (23693),A            ; ATTR-P: INK 7, PAPER 0
        LD (23695),A            ; ATTR-T
        XOR A
        LD (23624),A
        LD A,2
        CALL 0x1601             ; Kanal "S" oeffnen
        RET

; Startbildschirm
SPLASH: CALL 0x0DAF
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
        LD A,16
        LD (selrow),A
        CALL SELECTLOOP
        RET

; Text ausgeben (HL), Ende = 255
PRSTR:  LD A,(HL)
        CP 255
        RET Z
        RST 16
        INC HL
        JR PRSTR

; ============================================================
;  Ballfarbe: Attribute der vom Ball beruehrten Zellen setzen
; ============================================================
ERASEBALL:
        CALL DRAWBALL
        LD A,7                  ; Standard: weiss auf schwarz
        JR BALLATTR
SHOWBALL:
        CALL DRAWBALL
        LD A,(bcol)

; A = Attributwert fuer alle Zellen, die der Ball bei (bx,by) beruehrt
BALLATTR:
        LD E,A
        LD A,(by)
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (tmp),A              ; Zeile oben
        LD A,(by)
        ADD A,3
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD (tmp2),A             ; Zeile unten
        LD A,(bx)
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD C,A                  ; Spalte links
        LD A,(bx)
        ADD A,3
        RRCA
        RRCA
        RRCA
        AND 0x1F
        LD D,A                  ; Spalte rechts
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

SETCELL:CALL ATTRADDR
        LD (HL),E
        RET

; A = Zeile (0..23), C = Spalte  ->  HL = Attributadresse
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
;  A = obere Pixelzeile
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
PRTEMPO:LD A,22
        RST 16
        LD A,(selrow)
        RST 16
        LD A,9
        RST 16
        LD HL,MSGTEMPO
        CALL PRSTR
        LD A,(level)
        ADD A,'0'
        RST 16
        LD HL,MSGTEMPO2
        CALL PRSTR
        RET

; Stick hoch/runter lesen: A = 0 nichts, 1 hoch, 2 runter
READSEL:LD BC,0xEFFE
        IN A,(C)
        LD E,A
        LD BC,0xF7FE
        IN A,(C)
        LD D,A
        BIT 1,E
        JR Z,RS_UP
        BIT 3,D
        JR Z,RS_UP
        BIT 2,E
        JR Z,RS_DN
        BIT 2,D
        JR Z,RS_DN
        XOR A
        RET
RS_UP:  LD A,1
        RET
RS_DN:  LD A,2
        RET

; Tempo mit Stick hoch/runter waehlen, mit Feuer bestaetigen
SELECTLOOP:
        XOR A
        LD (selprev),A
        CALL PRTEMPO
        LD B,25
SL0:    HALT
        DJNZ SL0
SL1:    HALT
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
        LD A,(level)
        JR NZ,SLDN
        CP 5
        JR NC,SL2
        INC A
        JR SL4
SLDN:   CP 2
        JR C,SL2
        DEC A
SL4:    LD (level),A
        CALL SETLEVEL
        CALL PRTEMPO
SL2:    CALL READFIRE
        JR NC,SL1
        RET

; Auf Feuer warten (Taste 0, Taste 5 oder Leertaste)
WAITFIRE:
        LD B,25
WF0:    HALT
        DJNZ WF0
WF1:    CALL READFIRE
        JR NC,WF1
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

; Ton: B = Laenge der Halbperiode (hoeher = tiefer), C = Anzahl Wechsel
BEEP:   XOR A
BP1:    XOR 0x10
        OUT (254),A
        LD D,B
BP2:    DEC D
        JR NZ,BP2
        DEC C
        JR NZ,BP1
        XOR A
        OUT (254),A
        RET

SNDWIN: LD B,140
        LD C,50
        CALL BEEP
        LD B,120
        LD C,60
        CALL BEEP
        LD B,100
        LD C,90
        CALL BEEP
        RET

; ============================================================
;  Daten
; ============================================================
LETTERS:
        DEFB "1111...111..1...1..1111"
        DEFB "1...1.1...1.11..1.1...."
        DEFB "1111..1...1.1.1.1.1..11"
        DEFB "1.....1...1.1..11.1...1"
        DEFB "1......111..1...1..111."

MSG1:   DEFB 22,9,5,"Pong fuer zwei Spieler"
        DEFB 22,11,8,"Stick 1: rechts"
        DEFB 22,12,8,"Stick 2: links"
        DEFB 22,14,6,"Erster mit 5 Punkten"
        DEFB 22,18,9,18,1,"FEUER = Start",18,0,255
MSGTEMPO:DEFB "Tempo:  < ",255
MSGTEMPO2:DEFB " >",255
MSGHINT:DEFB 22,20,4,"Stick hoch/runter = Tempo"
        DEFB 22,21,4,"Feuer im Spiel = Ballfarbe",255
MSGOVER:DEFB 22,5,11,"SPIELENDE",255
MSGL:   DEFB 22,11,9,"LINKS gewinnt",255
MSGR:   DEFB 22,11,8,"RECHTS gewinnt",255
MSGFIRE:DEFB 22,15,6,18,1,"FEUER = neues Spiel",18,0,255

        END START
