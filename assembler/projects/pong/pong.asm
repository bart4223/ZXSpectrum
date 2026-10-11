; ============================================================
;  PONG fuer ZX Spectrum (48K)  -  Maschinencode
;  Zwei Spieler, Sinclair-Interface-2-Joysticks
;    Stick 1 (Tasten 6-0): rechter Schlaeger, Feuer = Taste 0
;    Stick 2 (Tasten 1-5): linker Schlaeger,  Feuer = Taste 5
;  Assembliert mit pasmo:  pasmo --tapbas pongmc.asm pongmc.tap
; ============================================================
        ORG 32768

; ---- Einstellungen (hier kannst du drehen) ----------------
SPD0    EQU 3           ; Startgeschwindigkeit in Pixel pro Bild (50 Bilder/s)
SPDMAX  EQU 6           ; Maximalgeschwindigkeit (hoechstens 7!)
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

; ============================================================
START:  EI
        CALL SETUP
        CALL SPLASH

NEWGAME:
        CALL 0x0DAF             ; CLS
        CALL DRAWCOURT
        XOR A
        LD (sl),A
        LD (sr),A
        LD (hits),A
        LD (serv),A
        LD A,SPD0
        LD (spd),A
        LD A,92
        LD (pyl),A
        LD (pyr),A
        LD C,1
        CALL DRAWPAD
        LD A,92
        LD C,30
        CALL DRAWPAD
        LD B,0
        LD C,13
        CALL PRSCORE
        CALL SERVE

; ---- Hauptschleife: genau ein Durchlauf pro Bild (50 Hz) ----
MAIN:   HALT
        CALL DRAWBALL           ; Ball loeschen (XOR)
        CALL MOVEPADS
        CALL MOVEBALL
        OR A
        JR NZ,SCORED
        CALL DRAWBALL           ; Ball neu zeichnen
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
SC3:    LD B,0
        LD C,13
        CALL PRSCORE
        LD B,200
        LD C,70
        CALL BEEP
        LD A,(sl)
        CP WINSC
        JP Z,GAMEOVER
        LD A,(sr)
        CP WINSC
        JP Z,GAMEOVER
        LD A,SPD0
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
        LD B,8
        LD C,13
        CALL PRSCORE
        LD A,(sl)
        CP WINSC
        LD HL,MSGL
        JR Z,GO1
        LD HL,MSGR
GO1:    CALL PRSTR
        LD HL,MSGFIRE
        CALL PRSTR
        CALL WAITFIRE
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
        SUB 12
        SRA A
        SRA A
        JR NZ,PH1
        LD A,1
PH1:    LD (dyv),A
        LD A,(hits)
        INC A
        CP 3
        JR C,PH2
        LD A,(spd)
        CP SPDMAX
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
        LD A,R
        RRA
        LD A,2
        JR NC,SV1
        LD A,256-2
SV1:    LD (dyv),A
        LD A,(spd)
        LD B,A
        LD A,(serv)
        OR A
        LD A,B
        JR Z,SV2
        NEG
SV2:    LD (dxv),A
        CALL DRAWBALL
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
        CALL WAITFIRE
        RET

; Text ausgeben (HL), Ende = 255
PRSTR:  LD A,(HL)
        CP 255
        RET Z
        RST 16
        INC HL
        JR PRSTR

; Spielstand "links : rechts" an Zeile B, Spalte C
PRSCORE:LD A,B
        LD (tmp),A
        LD A,C
        LD (tmp2),A
        LD A,22
        RST 16
        LD A,(tmp)
        RST 16
        LD A,(tmp2)
        RST 16
        LD A,(sl)
        ADD A,'0'
        RST 16
        LD A,32
        RST 16
        LD A,':'
        RST 16
        LD A,32
        RST 16
        LD A,(sr)
        ADD A,'0'
        RST 16
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
MSGOVER:DEFB 22,5,11,"SPIELENDE",255
MSGL:   DEFB 22,11,9,"LINKS gewinnt",255
MSGR:   DEFB 22,11,8,"RECHTS gewinnt",255
MSGFIRE:DEFB 22,15,6,18,1,"FEUER = neues Spiel",18,0,255

        END START
