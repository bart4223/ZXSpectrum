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
vol     EQU VARS+23     ; Lautstaerke 0 (aus) .. 5 (voll)
pxl     EQU VARS+24     ; x linker Schlaeger (muss pyl+24 sein!)
pxr     EQU VARS+25     ; x rechter Schlaeger (muss pyr+24 sein!)
oy      EQU VARS+26
ny      EQU VARS+27
ox      EQU VARS+28
nx      EQU VARS+29
lmin    EQU VARS+30
lmax    EQU VARS+31
beepf   EQU VARS+32     ; Treffer-Ton vormerken (wird nach dem Zeichnen gespielt)

; ============================================================
START:  EI
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
        LD A,PXL0
        LD (pxl),A
        LD A,PXR0
        LD (pxr),A
        CALL DRAWPADS
        LD A,1
        LD (firep),A
        XOR A
        LD (beepf),A
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
        LD A,(beepf)
        OR A
        JR Z,MAIN
        XOR A
        LD (beepf),A
        LD B,110                ; Treffer-Ton
        LD C,30
        CALL BEEP
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
        LD (beepf),A            ; Ton erst nach dem Zeichnen des Balls spielen
        RET

; ============================================================
;  Schlaeger steuern
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
STEER:  PUSH HL
        LD A,(HL)
        LD (oy),A
        ADD A,B
        CP TOPLIM
        JR NC,ST1
        LD A,TOPLIM
ST1:    CP PADMAX+1
        JR C,ST2
        LD A,PADMAX
ST2:    LD (ny),A
        LD DE,24
        ADD HL,DE               ; HL = Adresse von px
        LD A,(HL)
        LD (ox),A
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
ST4:    LD A,E
        LD (nx),A
        LD A,(ox)
        LD B,A
        LD A,(nx)
        CP B
        JR NZ,ST5
        LD A,(oy)
        LD B,A
        LD A,(ny)
        CP B
        JR NZ,ST5
        POP HL                  ; nichts geaendert
        RET
ST5:    LD A,(ox)
        LD C,A
        LD A,(oy)
        LD B,PADH
        CALL DRAWSPR            ; alte Position loeschen
        POP HL
        LD A,(ny)
        LD (HL),A
        LD DE,24
        ADD HL,DE
        LD A,(nx)
        LD (HL),A
        LD C,A
        LD A,(ny)
        LD B,PADH
        JP DRAWSPR              ; neue Position zeichnen

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

; Ball (4x4) an (bx,by) zeichnen/loeschen (XOR)
DRAWBALL:
        LD A,(bx)
        LD C,A
        LD A,(by)
        LD B,4
        ; weiter mit DRAWSPR

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
        LD A,15
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
        LD A,6
        RST 16
        LD HL,MSGTEMPO
        CALL PRSTR
        LD A,(level)
        ADD A,'0'
        RST 16
        LD HL,MSGEND
        CALL PRSTR
        RET

; Zeile "Lautstaerke: < n >" in Zeile (selrow)+1 ausgeben (0 = "aus")
PRVOL:  LD A,22
        RST 16
        LD A,(selrow)
        INC A
        RST 16
        LD A,6
        RST 16
        LD HL,MSGVOL
        CALL PRSTR
        LD A,(vol)
        OR A
        JR NZ,PV1
        LD HL,MSGAUS
        CALL PRSTR
        JR PV2
PV1:    ADD A,'0'
        RST 16
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
        LD B,110                ; Testton in neuer Lautstaerke
        LD C,30
        CALL BEEP
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

; Ton: B = halbe Periode (hoeher = tiefer), C = Anzahl Halbperioden.
; Lautstaerke (vol 0..5) ueber das Tastverhaeltnis: Einphase = B >> (5-vol),
; die Periode (2*B) und damit die Tonhoehe bleiben gleich. vol 5 = 50 % (wie bisher).
BEEP:   LD A,(vol)
        OR A
        RET Z                   ; aus
        LD D,B                  ; D = Einphase
        LD E,A
        LD A,5
        SUB E
        JR Z,BPH0
BPSH:   SRL D
        DEC A
        JR NZ,BPSH
BPH0:   LD A,D
        OR A
        JR NZ,BPH1
        INC D                   ; mindestens 1
BPH1:   LD A,B
        SUB D
        LD E,A                  ; E = Rest der ersten Auszeit (B - Einphase)
        SRL C                   ; C = Anzahl Perioden
BPL:    LD A,0x10
        OUT (254),A
        LD A,D
BPA:    DEC A
        JR NZ,BPA               ; Einphase
        XOR A
        OUT (254),A
        LD A,B
BPB:    DEC A
        JR NZ,BPB               ; erste Haelfte der Auszeit
        LD A,E
        OR A
        JR Z,BPC
BPD:    DEC A
        JR NZ,BPD               ; Rest der Auszeit
BPC:    DEC C
        JR NZ,BPL
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

MSG1:   DEFB 22,8,5,"Pong fuer zwei Spieler"
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
MSGOVER:DEFB 22,5,11,"SPIELENDE",255
MSGL:   DEFB 22,11,9,"LINKS gewinnt",255
MSGR:   DEFB 22,11,8,"RECHTS gewinnt",255
MSGFIRE:DEFB 22,15,6,18,1,"FEUER = neues Spiel",18,0,255

        END START
