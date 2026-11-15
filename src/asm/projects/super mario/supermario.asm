; ===========================================================
;  SUPERMARIO (Feuerwehr-Jump'n'Run)  -  ZX Spectrum 128K
;  Stufe 3: Laufen, Springen, Kollision, Scrolling in 8-Pixel-Schritten (64 Kacheln breit), Doppelpuffer, ULAplus
;  Assembler: pasmo   (pasmo --tapbas --name supermario supermario.asm supermario.tap)
;  Diese Datei wird aus src/supermario.asm.in + tools/gen.py erzeugt.
;
;  Steuerung: Joystick 1 (Sinclair, Tasten 6-0) oder O/P, Leertaste/Feuer = Start und Sprung
;             G = zwischen klein und gross umschalten (Test, ab Stufe 7 Power-up)
;  Speicher:  Code ab 6000h; Variablen ab VARS (nicht im TAP); IM2-Tabelle 0BE00h;
;             Bank 7 (0C000h) = zweiter Bildschirm, Stack ganz oben.
; ===========================================================

ULAPLUS         equ 1                   ; 1 = ULAplus (Auslieferung), 0 = nur Diagnose-Build ohne Portzugriff

VARS            equ 0B800h
IM2TAB          equ 0BE00h              ; 257 Bytes 0BFh
IM2VEC          equ 0BFBFh              ; Handler: ei / reti
STACKTOP        equ 0FFF0h
BANKREG         equ 7FFDh

; ---- Eingabe-Bits (wie Sinclair-Joystick 1, nach CPL) ----
I_FIRE          equ 01h
I_UP            equ 02h
I_DOWN          equ 04h
I_RIGHT         equ 08h
I_LEFT          equ 10h
I_SIZE          equ 20h                 ; Taste G

; ---- Physik (Festkomma 8.8, Pixel pro Bild) ----
ACC             equ 0030h               ; Beschleunigung
TURN            equ 0070h               ; Gegenbremsen beim Richtungswechsel
FRIC            equ 0020h               ; Auslaufen ohne Eingabe
MAXV            equ 0200h               ; hoechstes Tempo 2 Pixel/Bild
XMAX            equ 0F000h              ; rechte Grenze 240 Pixel
ANIMPER         equ 5                   ; Bilder je Laufphase
GRAV            equ 0038h               ; Schwerkraft je Bild
JUMPV           equ 0500h               ; Absprunggeschwindigkeit (5 Pixel/Bild nach oben)
CUTV            equ 0200h               ; Feuer losgelassen: Aufstieg auf 2 Pixel/Bild begrenzen
MAXFALL         equ 0600h
CAMTR_R         equ 136                 ; ab dieser Bildschirm-x scrollt die Kamera nach rechts
CAMTR_L         equ 104                 ; unter dieser Bildschirm-x nach links

; ---- Variablen (VARS, bei Start geloescht) ----
V_BANK          equ VARS+0              ; Zeichenpuffer: 0 = Bank 5 (4000h), 80h = Bank 7 (0C000h)
V_ATTR          equ VARS+1              ; Attribut fuer print_str
PX              equ VARS+2              ; x als 8.8, High-Byte = Pixel
PV              equ VARS+4              ; Tempo 8.8 mit Vorzeichen
PDIR            equ VARS+6              ; 0 rechts, 1 links
PFRM            equ VARS+7              ; 0 steht, 1/2 laeuft
PTIM            equ VARS+8
PSIZE           equ VARS+9              ; 0 klein, 1 gross
INP             equ VARS+10
INPOLD          equ VARS+11
OLD0            equ VARS+12             ; Merker Puffer 0: gueltig, x, Groesse, y
OLD1            equ VARS+16             ; Merker Puffer 1
PY              equ VARS+20             ; y (Oberkante) als 8.8
VY              equ VARS+22             ; vertikales Tempo 8.8 mit Vorzeichen
PGND            equ VARS+24             ; 1 = steht auf festem Grund
V_JREQ          equ VARS+25             ; Sprung-Anforderung (Feuer-Flanke)
V_H             equ VARS+26             ; Hoehe 16 oder 32
V_TY0           equ VARS+27             ; Kachelzeilen der Figur
V_TY1           equ VARS+28
V_XL            equ VARS+29             ; Koerperkanten x+2 / x+13
V_XR            equ VARS+30
V_Y             equ VARS+31
V_CX            equ VARS+32
V_ROWS          equ VARS+33
V_O             equ VARS+34
V_K             equ VARS+35
V_R1            equ VARS+36
V_R2            equ VARS+37
V_NR            equ VARS+38
V_I1            equ VARS+39
V_I2            equ VARS+40
V_F1            equ VARS+41
V_F2            equ VARS+42
V_RX            equ VARS+43
V_RS            equ VARS+44
V_RY            equ VARS+45
V_TX0           equ VARS+46
V_TX1           equ VARS+47
V_RTY1          equ VARS+48
V_IMG           equ VARS+50             ; Wort
V_FLG           equ VARS+52             ; Wort
V_INKP          equ VARS+54             ; Wort
V_BLK           equ VARS+56             ; Wort
V_FLGOFF        equ VARS+58             ; Wort
V_SAVEY         equ VARS+60
V_CY            equ VARS+61
V_X             equ VARS+62
CAM             equ VARS+64             ; Kameraposition in Zellen (Ziel)
BCAM0           equ VARS+65             ; Kamera, die Puffer 0 gerade zeigt
BCAM1           equ VARS+66
V_CAMD          equ VARS+67             ; Kamera des gezeichneten Puffers
V_CI            equ VARS+68
V_TP            equ VARS+69             ; Wort
V_KB            equ VARS+71
V_J             equ VARS+72
V_M0            equ VARS+73
V_M1            equ VARS+74
V_M2            equ VARS+75
V_R             equ VARS+76
V_MB            equ VARS+77
V_MP            equ VARS+78             ; Wort
V_IP            equ VARS+80             ; Wort: Zeiger in scroll_idx
V_AH            equ VARS+82
V_DIR           equ VARS+83             ; 0 = Kamera rechts, 1 = links
VARS_LEN        equ 96

                org 6000h

; Speicherplan: 6000h-7FFFh liegt im gebremsten (contended) RAM der ULA, dort nur selten gelesene Daten
; (Palette, vorverschobene Figurenbilder). Der heisse Code (Zeichnen, Scrollen, Physik) und seine Tabellen
; folgen dahinter im ungebremsten RAM ab ca. 8000h.
                jp start
; ---- ULAplus-Palette: 4 Paletten x (8 Ink + 8 Paper), Byte = GGGRRRBB ----
palette:
                db 025h,0FFh,0DCh,038h,0BDh,046h,07Ch,0A9h,06Bh,08Fh,0D3h,0D7h,0A9h,029h,02Ch,024h
                db 024h,0FFh,064h,0CDh,0DCh,028h,038h,0B6h,089h,070h,069h,054h,04Ch,074h,0D7h,025h
                db 025h,0FFh,0DCh,038h,0BDh,046h,07Ch,0A9h,06Bh,08Fh,0D3h,0D7h,0A9h,029h,02Ch,024h
                db 024h,0FFh,064h,0CDh,0DCh,028h,038h,0B6h,089h,070h,069h,054h,04Ch,074h,0D7h,025h

; ---- Bilder: je 4 Verschiebungen x (Zeilen x 6 Byte + Flags) ----
img_s0_d0_f0:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 7,6
img_s0_d0_f1:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 7,6
img_s0_d0_f2:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F9h,6,08Fh,070h,0FFh,0
                db 0F1h,00Eh,0E3h,01Ch,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FEh,1,063h,09Ch,0FFh,0
                db 0FCh,3,078h,087h,0FFh,0
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,098h,067h,0FFh,0
                db 0FFh,0,01Eh,0E1h,03Fh,0C0h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0E6h,019h,03Fh,0C0h
                db 0FFh,0,0C7h,038h,08Fh,070h
                db 7,6
img_s0_d0_f3:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,08Fh,070h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0C0h,03Fh,2,0FDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0C8h,037h,012h,0EDh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,023h,0DCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0F2h,00Dh,4,0FBh,0BFh,040h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,8,0F7h,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FCh,3,0,0FFh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FCh,3,081h,07Eh,02Fh,0D0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C2h,03Dh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,0,0FFh,00Bh,0F4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,020h,0DFh,04Bh,0B4h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 7,7
img_s0_d1_f0:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 7,7
img_s0_d1_f1:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F9h,6,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FEh,1,067h,098h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,099h,066h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0E6h,019h,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 7,7
img_s0_d1_f2:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F1h,00Eh,09Fh,060h,0FFh,0
                db 0C7h,038h,08Fh,070h,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,067h,098h,0FFh,0
                db 0F1h,00Eh,0E3h,01Ch,0FFh,0
                db 7,3
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,019h,0E6h,0FFh,0
                db 0FCh,3,078h,087h,0FFh,0
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C6h,039h,07Fh,080h
                db 0FFh,0,01Eh,0E1h,03Fh,0C0h
                db 7,7
img_s0_d1_f3:
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F1h,00Eh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 040h,0BFh,3,0FCh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 048h,0B7h,013h,0ECh,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 3,3
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,043h,0BCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0D0h,02Fh,0,0FFh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0D2h,02Dh,4,0FBh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 7,7
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,010h,0EFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F4h,00Bh,0,0FFh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0F4h,00Bh,081h,07Eh,03Fh,0C0h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 7,7
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C4h,03Bh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FDh,2,0,0FFh,00Fh,0F0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FDh,2,020h,0DFh,04Fh,0B0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 7,7
img_s1_d0_f0:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 7,6,7,6
img_s1_d0_f1:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 0C3h,03Ch,0C3h,03Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 0F0h,00Fh,0F0h,00Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 0FCh,3,03Ch,0C3h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 0FFh,0,00Fh,0F0h,00Fh,0F0h
                db 7,6,7,6
img_s1_d0_f2:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,01Fh,0E0h,0FFh,0
                db 0F8h,7,03Fh,0C0h,0FFh,0
                db 0F9h,6,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F3h,00Ch,0CFh,030h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,7,0F8h,0FFh,0
                db 0FEh,1,00Fh,0F0h,0FFh,0
                db 0FEh,1,047h,0B8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,0F3h,00Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,1,0FEh,0FFh,0
                db 0FFh,0,083h,07Ch,0FFh,0
                db 0FFh,0,091h,06Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,03Ch,0C3h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,07Fh,080h
                db 0FFh,0,0E0h,01Fh,0FFh,0
                db 0FFh,0,0E4h,01Bh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0CFh,030h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 7,6,7,6
img_s1_d0_f3:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 7,3,7,7
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 7,6,7,7
img_s1_d1_f0:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 7,6,7,6
img_s1_d1_f1:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E1h,01Eh,087h,078h,0FFh,0
                db 0C1h,03Eh,083h,07Ch,0FFh,0
                db 0C3h,03Ch,0C3h,03Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,061h,09Eh,0FFh,0
                db 0F0h,00Fh,060h,09Fh,0FFh,0
                db 0F0h,00Fh,0F0h,00Fh,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,018h,0E7h,07Fh,080h
                db 0FCh,3,018h,0E7h,03Fh,0C0h
                db 0FCh,3,03Ch,0C3h,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,086h,079h,01Fh,0E0h
                db 0FFh,0,6,0F9h,00Fh,0F0h
                db 0FFh,0,00Fh,0F0h,00Fh,0F0h
                db 7,6,7,6
img_s1_d1_f2:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F8h,7,00Fh,0F0h,0FFh,0
                db 0FCh,3,01Fh,0E0h,0FFh,0
                db 0F8h,7,09Fh,060h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0F3h,00Ch,0CFh,030h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FEh,1,3,0FCh,0FFh,0
                db 0FFh,0,7,0F8h,0FFh,0
                db 0FEh,1,027h,0D8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0FCh,3,0F3h,00Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 7,3,7,3
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,080h,07Fh,0FFh,0
                db 0FFh,0,0C1h,03Eh,0FFh,0
                db 0FFh,0,089h,076h,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FFh,0,03Ch,0C3h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0E0h,01Fh,03Fh,0C0h
                db 0FFh,0,0F0h,00Fh,07Fh,080h
                db 0FFh,0,0E2h,01Dh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,0CFh,030h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 7,6,7,6
img_s1_d1_f3:
                db 0FEh,1,07Fh,080h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 0E0h,01Fh,7,0F8h,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 0FFh,0,0FFh,0,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F4h,00Bh,02Fh,0D0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0FCh,3,03Fh,0C0h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0C0h,03Fh,3,0FCh,0FFh,0
                db 080h,07Fh,1,0FEh,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 011h,0EEh,088h,077h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 010h,0EFh,8,0F7h,0FFh,0
                db 0F0h,00Fh,00Fh,0F0h,0FFh,0
                db 0F8h,7,01Fh,0E0h,0FFh,0
                db 0F1h,00Eh,08Fh,070h,0FFh,0
                db 0E3h,01Ch,0C7h,038h,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0C7h,038h,0E3h,01Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 0CFh,030h,0F3h,00Ch,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 08Fh,070h,0F1h,00Eh,0FFh,0
                db 3,3,3,3
                db 0FFh,0,09Fh,060h,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0F8h,7,1,0FEh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FDh,2,00Bh,0F4h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FFh,0,00Fh,0F0h,0FFh,0
                db 0FCh,3,3,0FCh,0FFh,0
                db 0F0h,00Fh,0,0FFh,0FFh,0
                db 0E0h,01Fh,0,0FFh,07Fh,080h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,062h,09Dh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0C4h,03Bh,2,0FDh,03Fh,0C0h
                db 0FCh,3,3,0FCh,0FFh,0
                db 0FEh,1,7,0F8h,0FFh,0
                db 0FCh,3,063h,09Ch,0FFh,0
                db 0F8h,7,0F1h,00Eh,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F1h,00Eh,0F8h,7,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 0F3h,00Ch,0FCh,3,0FFh,0
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 0E3h,01Ch,0FCh,3,07Fh,080h
                db 7,3,7,7
                db 0FFh,0,0E7h,018h,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0FEh,1,0,0FFh,07Fh,080h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,042h,0BDh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0C3h,03Ch,0FFh,0
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FCh,3,0,0FFh,03Fh,0C0h
                db 0F8h,7,0,0FFh,01Fh,0E0h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,018h,0E7h,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0F1h,00Eh,0,0FFh,08Fh,070h
                db 0FFh,0,0,0FFh,0FFh,0
                db 0FFh,0,081h,07Eh,0FFh,0
                db 0FFh,0,018h,0E7h,0FFh,0
                db 0FEh,1,03Ch,0C3h,07Fh,080h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,07Eh,081h,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 0FCh,3,0FFh,0,03Fh,0C0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 0F8h,7,0FFh,0,01Fh,0E0h
                db 7,2,7,7
                db 0FFh,0,0F9h,6,0FFh,0
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FFh,0,080h,07Fh,01Fh,0E0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FFh,0,0FFh,0,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0D0h,02Fh,0BFh,040h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0F0h,00Fh,0FFh,0
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0,0FFh,00Fh,0F0h
                db 0FEh,1,0,0FFh,7,0F8h
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,046h,0B9h,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FCh,3,040h,0BFh,023h,0DCh
                db 0FFh,0,0C0h,03Fh,03Fh,0C0h
                db 0FFh,0,0E0h,01Fh,07Fh,080h
                db 0FFh,0,0C6h,039h,03Fh,0C0h
                db 0FFh,0,08Fh,070h,01Fh,0E0h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,01Fh,0E0h,08Fh,070h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 0FFh,0,03Fh,0C0h,0CFh,030h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 0FEh,1,03Fh,0C0h,0C7h,038h
                db 7,6,7,7


start:          di
                ld sp,STACKTOP
                ld bc,BANKREG           ; 48K-ROM (Schrift), Bank 7 bei 0C000h, Bank 5 sichtbar
                ld a,17h
                out (c),a
                xor a                   ; Rand schwarz
                out (0FEh),a
                call init_im2
                if ULAPLUS
; ---- ULAplus: Palette blind schreiben (nie zuruecklesen!) ----
                ld hl,palette
                ld e,0                  ; Palettenindex 0..63
                ld d,64
pal_loop:       ld bc,0BF3Bh            ; Registerport
                ld a,e
                out (c),a
                ld b,0FFh               ; Datenport 0FF3Bh
                ld a,(hl)
                out (c),a
                inc hl
                inc e
                dec d
                jr nz,pal_loop
                ld bc,0BF3Bh            ; Register 64 = Modusgruppe
                ld a,40h
                out (c),a
                ld b,0FFh
                ld a,1                  ; Palettenmodus an
                out (c),a
                endif
                ld hl,VARS              ; Variablen loeschen
                ld de,VARS+1
                ld bc,VARS_LEN-1
                ld (hl),0
                ldir
                call clear_both
                ei
                call title_screen
                call clear_both
                call new_game

main_loop:      call read_input
                call update_player
                call restore_old
                call sync_cam
                call draw_player
main_wait:      halt                    ; auf den naechsten Bildwechsel warten
                call flip
                jr main_loop

; ---------------------------------------------------------
; IM2: Tabelle 257 x 0BFh, Handler bei 0BFBFh = ei / reti
; ---------------------------------------------------------
init_im2:       ld hl,IM2TAB
                ld de,IM2TAB+1
                ld bc,256
                ld (hl),0BFh
                ldir
                ld hl,IM2VEC
                ld (hl),0FBh            ; ei
                inc hl
                ld (hl),0EDh            ; reti
                inc hl
                ld (hl),4Dh
                ld a,high IM2TAB
                ld i,a
                im 2
                ret

; ---------------------------------------------------------
; beide Bildschirme (Bank 5 und Bank 7) loeschen, Attribute 0
; ---------------------------------------------------------
clear_both:     ld hl,4000h
                ld de,4001h
                ld bc,1AFFh
                ld (hl),0
                ldir
                ld hl,0C000h
                ld de,0C001h
                ld bc,1AFFh
                ld (hl),0
                ldir
                ret

; ---------------------------------------------------------
; Titelbild (Bank 5): Text mit der ROM-Schrift (3C00h + Zeichen*8)
; ---------------------------------------------------------
title_screen:   ld hl,5800h
                ld de,5801h
                ld bc,02FFh
                ld (hl),38h             ; Paper 7 (dunkel), Ink 0
                ldir
                xor a
                ld (V_BANK),a
                ld a,3Ah                ; Ink 2 (gold)
                ld (V_ATTR),a
                ld hl,txt_title
                ld b,8
                ld c,9
                call print_str
                ld a,39h                ; Ink 1 (weiss)
                ld (V_ATTR),a
                ld hl,txt_stage
                ld b,11
                ld c,8
                call print_str
                ld hl,txt_start
                ld b,15
                ld c,2
                call print_str
                ld hl,txt_keys
                ld b,17
                ld c,1
                call print_str
ts_wait:        halt
                call read_input
                ld a,(INP)
                and I_FIRE
                jr z,ts_wait
ts_rel:         halt
                call read_input
                ld a,(INP)
                and I_FIRE
                jr nz,ts_rel
                ret

; print_str: HL = Text (0-terminiert), B = Zeile, C = Spalte, Attribut in V_ATTR
print_str:      ld a,(hl)
                or a
                ret z
                push hl
                push bc
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,3C00h
                add hl,de               ; HL = Zeichenmuster
                call cell_addr
                ld b,8
ps_row:         ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz ps_row
                pop bc
                push bc
                call attr_addr
                ld a,(V_ATTR)
                ld (de),a
                pop bc
                inc c
                pop hl
                inc hl
                jr print_str

; ---------------------------------------------------------
; Neues Spiel: Szene in beide Puffer, Spieler auf Startposition
; ---------------------------------------------------------
new_game:       xor a
                ld (V_BANK),a
                call draw_scene
                ld a,80h
                ld (V_BANK),a
                call draw_scene
                ld hl,2000h             ; x = 32
                ld (PX),hl
                ld hl,0
                ld (PV),hl
                xor a
                ld (PDIR),a
                ld (PFRM),a
                ld (PTIM),a
                ld (PSIZE),a
                ld (OLD0),a
                ld (OLD1),a
                ld (INPOLD),a
                ld (CAM),a
                ld (BCAM0),a
                ld (BCAM1),a
                ld (VY),a
                ld (VY+1),a
                ld (V_JREQ),a
                ld hl,9000h             ; y = 144 (klein, auf dem Boden)
                ld (PY),hl
                ld a,1
                ld (PGND),a
                ret                     ; V_BANK = 80h: erst in Bank 7 zeichnen, Bank 5 ist sichtbar

draw_scene:     ld hl,level_map
                ld b,0
ds_row:         ld c,0
ds_col:         push hl
                push bc
                ld a,(hl)
                call draw_tile
                pop bc
                pop hl
                inc hl
                inc c
                ld a,c
                cp 16
                jr nz,ds_col
                ld de,48                ; Zeilenabstand der Welt = 64
                add hl,de
                inc b
                ld a,b
                cp 12
                jr nz,ds_row
                ret

; ---------------------------------------------------------
; Bildwechsel: den eben gezeichneten Puffer anzeigen, dann den anderen zum Zeichnen waehlen
; ---------------------------------------------------------
flip:           ld a,17h
                ld hl,V_BANK
                bit 7,(hl)
                jr z,fl_a
                ld a,1Fh
fl_a:           ld bc,BANKREG
                out (c),a
                ld a,(V_BANK)
                xor 80h
                ld (V_BANK),a
                ret

; ---------------------------------------------------------
; cell_addr: B=cy (0..23), C=cx (0..31)  ->  DE = Pixeladresse im Zeichenpuffer
; ---------------------------------------------------------
cell_addr:      ld a,b
                and 18h
                or 40h
                ld d,a
                ld a,(V_BANK)
                or d
                ld d,a
                ld a,b
                and 7
                rrca
                rrca
                rrca
                add a,c
                ld e,a
                ret

; attr_addr: B=cy, C=cx -> DE = Attributadresse im Zeichenpuffer
attr_addr:      ld a,b
                rrca
                rrca
                rrca
                ld e,a
                and 3
                or 58h
                ld d,a
                ld a,(V_BANK)
                or d
                ld d,a
                ld a,e
                and 0E0h
                add a,c
                ld e,a
                ret

; ---------------------------------------------------------
; draw_tile: A=Kachel-Instanz, B=ty, C=tx (16x16 Pixel). Zerstoert alle Register.
; Kachel-Daten: TL,TR,BL,BR je 8 Byte, danach 4 Attribute
; ---------------------------------------------------------
draw_tile:      ld e,a
                ld d,0
                ld hl,tile_ptr
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl                ; HL = Kachel-Daten
                ld a,c
                add a,a
                ld c,a                  ; cx = 2*tx
                ld a,b
                add a,a
                ld b,a                  ; cy = 2*ty
                push bc
                call cell_addr
                push de
                call blit8              ; links oben
                pop de
                inc e
                push de
                call blit8              ; rechts oben
                pop de
                ld a,e
                add a,31
                ld e,a
                push de
                call blit8              ; links unten
                pop de
                inc e
                call blit8              ; rechts unten
                pop bc
                call attr_addr
                ld a,(hl)
                ld (de),a
                inc hl
                inc e
                ld a,(hl)
                ld (de),a
                inc hl
                ld a,e
                add a,31
                ld e,a
                ld a,(hl)
                ld (de),a
                inc hl
                inc e
                ld a,(hl)
                ld (de),a
                ret

blit8:          ld b,8
bl8_l:          ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz bl8_l
                ret

; ---------------------------------------------------------
; Eingabe: INP = Sinclair-Joystick 1 (Tasten 6-0) oder O/P/Leertaste, plus G
; ---------------------------------------------------------
read_input:     ld bc,0EFFEh
                in a,(c)
                cpl
                and 1Fh
                ld d,a
                ld bc,0DFFEh            ; P O I U Y
                in a,(c)
                ld e,a
                bit 0,e                 ; P = rechts
                jr nz,ri_1
                ld a,d
                or I_RIGHT
                ld d,a
ri_1:           bit 1,e                 ; O = links
                jr nz,ri_2
                ld a,d
                or I_LEFT
                ld d,a
ri_2:           ld bc,7FFEh             ; Leertaste
                in a,(c)
                bit 0,a
                jr nz,ri_3
                ld a,d
                or I_FIRE
                ld d,a
ri_3:           ld bc,0FDFEh            ; A S D F G
                in a,(c)
                bit 4,a
                jr nz,ri_4
                ld a,d
                or I_SIZE
                ld d,a
ri_4:           ld a,d
                ld (INP),a
                ret

; ---------------------------------------------------------
; Spieler: Groesse, Beschleunigung, Bewegung, Animation
; ---------------------------------------------------------
update_player:  ld a,(INPOLD)           ; Feuer-Flanke -> Sprung-Anforderung
                cpl
                ld b,a
                ld a,(INP)
                and b
                and I_FIRE
                ld (V_JREQ),a
                ld a,(INPOLD)           ; G: Flanke -> klein/gross
                and I_SIZE
                jr nz,up_sz_done
                ld a,(INP)
                and I_SIZE
                jr z,up_sz_done
                call toggle_size
up_sz_done:     call calc_rows
                ld a,(INP)
                ld (INPOLD),a
                and I_LEFT+I_RIGHT
                jr z,up_none
                cp I_LEFT+I_RIGHT
                jr z,up_none
                cp I_LEFT
                jr z,up_left
; ---- rechts
                xor a
                ld (PDIR),a
                ld hl,(PV)
                ld de,ACC
                bit 7,h
                jr z,up_r1
                ld de,TURN
up_r1:          add hl,de
                bit 7,h
                jr nz,up_rok
                ld a,h
                cp 2
                jr c,up_rok
                ld hl,MAXV
up_rok:         ld (PV),hl
                jr up_move
; ---- links
up_left:        ld a,1
                ld (PDIR),a
                ld hl,(PV)
                ld de,ACC
                bit 7,h
                jr nz,up_l1
                ld de,TURN
up_l1:          or a
                sbc hl,de
                bit 7,h
                jr z,up_lok
                ld a,h
                cp 0FEh
                jr nc,up_lok
                ld hl,0FE00h            ; -MAXV
up_lok:         ld (PV),hl
                jr up_move
; ---- ohne Eingabe: auslaufen
up_none:        ld hl,(PV)
                ld a,h
                or l
                jr z,up_move
                bit 7,h
                jr nz,un_neg
                ld de,FRIC
                or a
                sbc hl,de
                jr nc,un_st
                ld hl,0
                jr un_st
un_neg:         ld de,FRIC
                add hl,de
                bit 7,h
                jr nz,un_st
                ld hl,0
un_st:          ld (PV),hl
; ---- bewegen, an den Raendern anhalten
up_move:        ld a,(PV+1)
                bit 7,a
                jr nz,um_neg
                ld hl,(PV)
                ld de,(PX)
                add hl,de
                ld a,h
                cp 0F0h
                jr c,um_st
                ld hl,XMAX
                ld de,0
                ld (PV),de
                jr um_st
um_neg:         ld hl,(PV)
                ld de,(PX)
                add hl,de
                jr c,um_st
                ld hl,0
                ld de,0
                ld (PV),de
um_st:          ld (PX),hl
                call hcollide
                call vertical
                call camera
; ---- Animation
                ld a,(PGND)
                or a
                jr nz,an_gr
                ld a,3                  ; Sprungbild
                ld (PFRM),a
                xor a
                ld (PTIM),a
                ret
an_gr:          ld a,(PFRM)
                cp 3
                jr nz,an_g2
                xor a
                ld (PFRM),a
                ld (PTIM),a
an_g2:
                ld hl,(PV)
                bit 7,h
                jr z,an_1
                ld de,0
                ex de,hl
                or a
                sbc hl,de               ; HL = |v|
an_1:           ld a,h
                or a
                jr nz,an_run
                ld a,l
                cp 40h
                jr c,an_stand
an_run:         ld a,(PFRM)
                or a
                jr nz,an_cnt
                inc a
                ld (PFRM),a
                xor a
                ld (PTIM),a
                ret
an_cnt:         ld a,(PTIM)
                inc a
                cp ANIMPER
                jr c,an_t
                ld a,(PFRM)
                cp 1
                ld a,1
                jr nz,an_f
                ld a,2
an_f:           ld (PFRM),a
                xor a
an_t:           ld (PTIM),a
                ret
an_stand:       xor a
                ld (PFRM),a
                ld (PTIM),a
                ret

; ---------------------------------------------------------
; Alte Position im Zeichenpuffer aus der Karte wiederherstellen (Kacheln neu zeichnen)
; Merker je Puffer: gueltig, x, Groesse
; ---------------------------------------------------------
restore_old:    ld hl,OLD0
                ld de,BCAM0
                ld a,(V_BANK)
                or a
                jr z,ro_a
                ld hl,OLD1
                ld de,BCAM1
ro_a:           ld a,(de)
                ld (V_CAMD),a
                ld a,(hl)
                or a
                ret z
                inc hl
                ld a,(hl)
                ld (V_RX),a
                inc hl
                ld a,(hl)
                ld (V_RS),a
                inc hl
                ld a,(hl)
                ld (V_RY),a
                ld a,(V_RX)             ; Zellspalten von x bis x+15
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_TX0),a
                ld a,(V_RX)
                add a,15
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_TX1),a
                ld a,(V_RS)             ; Zellzeilen von y bis y+H-1
                or a
                ld a,15
                jr z,ro_h
                ld a,31
ro_h:           ld b,a
                ld a,(V_RY)
                add a,b
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_RTY1),a
                ld a,(V_RY)
                rrca
                rrca
                rrca
                and 1Fh
                ld b,a
ro_row:         ld a,(V_TX0)
                ld c,a
ro_col:         push bc
                call draw_cell
                pop bc
                ld a,(V_TX1)
                cp c
                jr z,ro_cd
                inc c
                jr ro_col
ro_cd:          ld a,(V_RTY1)
                cp b
                ret z
                inc b
                jr ro_row

; ---------------------------------------------------------
; Kamera: Bildschirm-x ueber/unter der Zone -> eine Zelle (8 Pixel) scrollen, x um 8 anpassen
; ---------------------------------------------------------
camera:         ld a,(PX+1)
                cp CAMTR_R
                jr c,cm_l
                ld a,(CAM)
                cp CAMMAX
                ret nc
                inc a
                ld (CAM),a
                ld a,(PX+1)
                sub 8
                ld (PX+1),a
                ret
cm_l:           cp CAMTR_L
                ret nc
                ld a,(CAM)
                or a
                ret z
                dec a
                ld (CAM),a
                ld a,(PX+1)
                add a,8
                ld (PX+1),a
                ret

; ---------------------------------------------------------
; draw_cell: B = Zellzeile (0..23), C = Bildschirmspalte (0..31); zeichnet die Weltzelle (V_CAMD + C)
; aus der Kachelkarte in den Zeichenpuffer (8 Pixelzeilen + Attribut). Zerstoert alle Register.
; ---------------------------------------------------------
draw_cell:      push bc
                ld a,(V_CAMD)
                add a,c
                ld e,a                  ; Weltzelle
                ld a,b
                and 1
                add a,a
                ld d,a
                ld a,e
                and 1
                or d
                ld (V_CI),a             ; Zelle in der Kachel: 0 TL, 1 TR, 2 BL, 3 BR
                ld a,e
                srl a
                ld e,a                  ; Welt-Kachelspalte
                ld a,b
                srl a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl               ; ty*64
                ld d,0
                add hl,de
                ld de,level_map
                add hl,de
                ld e,(hl)               ; Kachel-Instanz
                ld d,0
                ld hl,tile_ptr
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl                ; HL = Kachel-Daten
                ld (V_TP),hl
                ld a,(V_CI)
                add a,a
                add a,a
                add a,a
                ld c,a
                ld b,0
                add hl,bc               ; HL = Pixel der Zelle
                pop bc
                push bc
                call cell_addr
                call blit8
                pop bc
                call attr_addr
                ld hl,(V_TP)
                ld a,(V_CI)
                add a,32
                ld c,a
                ld b,0
                add hl,bc
                ld a,(hl)
                ld (de),a
                ret

; ---------------------------------------------------------
; sync_cam: Zeichenpuffer schrittweise auf die Zielkamera bringen (nur Zellen neu zeichnen, die sich aendern)
; ---------------------------------------------------------
sync_cam:       ld hl,BCAM0
                ld a,(V_BANK)
                or a
                jr z,sy_a
                ld hl,BCAM1
sy_a:           ld a,(CAM)
                ld c,(hl)
                cp c
                ret z
                jr c,sy_left
                ld a,c                  ; rechts: Grenzen ab c
                ld (V_KB),a
                xor a
                ld (V_DIR),a
                inc c
                jr sy_go
sy_left:        dec c
                ld a,c                  ; links: Grenzen ab c-1
                ld (V_KB),a
                ld a,1
                ld (V_DIR),a
sy_go:          ld (hl),c
                ld a,c
                ld (V_CAMD),a
                push hl
                call scroll_step
                pop hl
                jr sy_a

scroll_step:    ld a,(V_BANK)
                or 58h
                ld (V_AH+0),a           ; Attribut-Highbyte-Basis zwischenspeichern (V_AHB = V_AH)
                ld hl,scroll_idxR
                ld a,(V_DIR)
                or a
                jr z,ss_d
                ld hl,scroll_idxL
ss_d:           ld a,(V_KB)
                ld e,a
                ld d,0
                add hl,de
                add hl,de
                ld (V_IP),hl
                xor a
                ld (V_J),a
ss_col:         ld hl,(V_IP)
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld (V_IP),hl            ; BC = Liste dieser Spalte
ss_ent:         ld a,(bc)               ; E-Basis
                ld l,a
                inc bc
                ld a,(bc)               ; D-Basis, 0 = Ende
                or a
                jr z,ss_cn
                ld h,a
                inc bc
                ld a,(V_J)              ; Spalte und Puffer einsetzen
                or l
                ld l,a
                ld a,(V_BANK)
                or h
                ld h,a
                and 18h                 ; Attribut-Highbyte vorbereiten
                rrca
                rrca
                rrca
                ld d,a
                ld a,(V_AH)             ; = Bank | 58h (siehe oben)
                or d
                ld d,a                  ; D = Attribut-Highbyte (merken)
                ld a,(bc)               ; Zeiger auf die Zellgrafik
                ld e,a
                inc bc
                ld a,(bc)
                inc bc
                or a
                jr z,ss_emp
                push de                 ; D merken
                ld d,a
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                inc de
                inc h
                ld a,(de)
                ld (hl),a
                pop de
                ld h,d                  ; HL = Attributadresse
                ld a,(bc)
                inc bc
                ld (hl),a
                jr ss_ent
ss_emp:         xor a                   ; leere Zelle: 8 Nullzeilen
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                inc h
                ld (hl),a
                ld h,d
                ld a,(bc)
                inc bc
                ld (hl),a
                jr ss_ent
ss_cn:          ld a,(V_J)
                inc a
                ld (V_J),a
                cp 32
                jr c,ss_col
                ret

; ---------------------------------------------------------
; Spieler zeichnen: Bild (Groesse, Richtung, Phase) in der Verschiebung (x and 6)/2,
; 3 Zellen breit, maskiert; danach Ink der Zellen setzen (nur wo Pixel liegen)
; ---------------------------------------------------------
draw_player:    ld a,(PX+1)
                ld (V_X),a
                ld a,(PY+1)
                ld (V_Y),a
                ld a,(PSIZE)            ; Bildnummer = Groesse*8 + Richtung*4 + Phase
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(PDIR)
                add a,a
                add a,a
                add a,b
                ld hl,PFRM
                add a,(hl)
                add a,a
                ld e,a
                ld d,0
                ld hl,img_ptr
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = Bildanfang
                ld a,(PSIZE)
                or a
                jr nz,dp_large
                ld hl,BLK_SMALL
                ld (V_BLK),hl
                ld hl,ink_small
                ld (V_INKP),hl
                ld a,2
                ld (V_ROWS),a
                ld hl,96
                ld (V_FLGOFF),hl
                jr dp_c
dp_large:       ld hl,BLK_LARGE
                ld (V_BLK),hl
                ld hl,ink_large
                ld (V_INKP),hl
                ld a,4
                ld (V_ROWS),a
                ld hl,192
                ld (V_FLGOFF),hl
dp_c:           ld a,(V_X)              ; Verschiebung (x and 6)/2
                and 6
                rrca
                ld b,a
                ld hl,(V_BLK)
                ex de,hl                ; HL = Bildanfang, DE = Blockgroesse
                ld a,b
                or a
                jr z,dp_s0
dp_shl:         add hl,de
                djnz dp_shl
dp_s0:          ld (V_IMG),hl
                ld de,(V_FLGOFF)
                add hl,de
                ld (V_FLG),hl
                ld a,(V_X)
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_CX),a
; ---- Pixelzeilen: Bildschirmadresse der Zeile y, Spalte cx
                ld a,(V_Y)
                ld c,a
                and 0C0h
                rrca
                rrca
                rrca
                ld b,a
                ld a,c
                and 7
                or b
                or 40h
                ld b,a
                ld a,(V_BANK)
                or b
                ld d,a
                ld a,c
                and 38h
                add a,a
                add a,a
                ld e,a
                ld a,(V_CX)
                add a,e
                ld e,a
                ld a,(V_ROWS)
                add a,a
                add a,a
                add a,a
                ld b,a                  ; Zeilen
                ld hl,(V_IMG)
dp_line:        ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                inc e
                ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                inc e
                ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                dec e
                dec e
                inc d                   ; naechste Pixelzeile
                ld a,d
                and 7
                jr nz,dp_nx
                ld a,e
                add a,32
                ld e,a
                jr c,dp_nx
                ld a,d
                sub 8
                ld d,a
dp_nx:          djnz dp_line
; ---- Attribute: je Bildschirm-Zellzeile k, Bildzeilen r1..r2 bestimmen den Ink
                ld a,(V_Y)
                and 7
                ld (V_O),a
                ld a,(V_Y)
                rrca
                rrca
                rrca
                and 1Fh
                ld (V_CY),a
                ld a,(V_ROWS)
                ld b,a
                ld a,(V_O)
                or a
                ld a,b
                jr z,dp_nr
                inc a
dp_nr:          ld (V_NR),a
                xor a
                ld (V_K),a
dp_ar:          ld a,(V_K)
                or a
                jr z,dp_r1z             ; k=0 -> r1=0
                ld b,a
                ld a,(V_O)
                or a
                ld a,b
                jr z,dp_r1z             ; o=0 -> r1=k
                dec a                   ; sonst r1=k-1
dp_r1z:         ld (V_R1),a
                ld a,(V_K)
                ld b,a
                ld a,(V_ROWS)
                dec a
                cp b
                jr c,dp_r2              ; r2 = min(k, rows-1)
                ld a,b
dp_r2:          ld (V_R2),a
                ld a,(V_O)              ; o=1..4: untere Bildzeile ueberwiegt -> zuerst sie
                or a
                jr z,dp_nosw
                cp 5
                jr nc,dp_nosw
                ld a,(V_R1)
                ld b,a
                ld a,(V_R2)
                ld (V_R1),a
                ld a,b
                ld (V_R2),a
dp_nosw:
                ld hl,(V_FLG)
                ld a,(V_R1)
                ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                ld (V_F1),a
                ld hl,(V_FLG)
                ld a,(V_R2)
                ld e,a
                add hl,de
                ld a,(hl)
                ld (V_F2),a
                ld hl,(V_INKP)
                ld a,(V_R1)
                ld e,a
                add hl,de
                ld a,(hl)
                ld (V_I1),a
                ld hl,(V_INKP)
                ld a,(V_R2)
                ld e,a
                add hl,de
                ld a,(hl)
                ld (V_I2),a
                ld a,(V_CY)
                ld b,a
                ld a,(V_CX)
                ld c,a
                call attr_addr
                ld a,(V_F1)
                ld b,a
                ld a,(V_F2)
                ld c,a
                ld h,1
dp_at:          ld a,b
                and h
                jr z,dp_a2
                ld a,(V_I1)
                jr dp_aset
dp_a2:          ld a,c
                and h
                jr z,dp_an
                ld a,(V_I2)
dp_aset:        ld l,a
                ld a,(de)
                and 0F8h                ; Paper und Palettenbits behalten
                or l
                ld (de),a
dp_an:          inc e
                sla h
                ld a,h
                cp 8
                jr nz,dp_at
                ld a,(V_CY)
                inc a
                ld (V_CY),a
                ld a,(V_K)
                inc a
                ld (V_K),a
                ld hl,V_NR
                cp (hl)
                jp c,dp_ar
                ld hl,OLD0              ; Merker fuer diesen Puffer
                ld a,(V_BANK)
                or a
                jr z,dp_o
                ld hl,OLD1
dp_o:           ld (hl),1
                inc hl
                ld a,(V_X)
                ld (hl),a
                inc hl
                ld a,(PSIZE)
                ld (hl),a
                inc hl
                ld a,(V_Y)
                ld (hl),a
                ret

; ---------------------------------------------------------
; Kollision und Schwerkraft
; ---------------------------------------------------------
; tile_solid: B = ty, C = tx -> A <> 0 wenn fest (unterhalb der Karte = fest). B, C bleiben erhalten.
tile_solid:     ld a,b
                cp 12
                jr nc,ts_yes
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl               ; ty*64
                ld e,c
                ld d,0
                add hl,de
                ld de,level_map
                add hl,de
                ld e,(hl)
                ld d,0
                ld hl,solid_tab
                add hl,de
                ld a,(hl)
                ret
ts_yes:         ld a,1
                ret

; calc_rows: V_H, V_TY0, V_TY1 aus PSIZE und PY
calc_rows:      ld a,(PSIZE)
                or a
                ld a,16
                jr z,cr_h
                ld a,32
cr_h:           ld (V_H),a
                dec a
                ld b,a
                ld a,(PY+1)
                add a,b
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld (V_TY1),a
                ld a,(PY+1)
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld (V_TY0),a
                ret

; px_tx: A = Bildschirm-x in Pixeln -> C = Weltkachel (Kamera in Zellen: tx = (CAM + x/8) / 2)
px_tx:          rrca
                rrca
                rrca
                and 1Fh
                ld c,a
                ld a,(CAM)
                add a,c
                srl a
                ld c,a
                ret

; solid_col: A = Pixel-x -> NZ wenn eine Kachel dieser Spalte (Zeilen V_TY0..V_TY1) fest ist
solid_col:      call px_tx
                ld a,(V_TY0)
                ld b,a
sc_l:           call tile_solid
                or a
                ret nz
                ld a,(V_TY1)
                cp b
                ret z
                inc b
                jr sc_l

; solid_row: B = ty -> NZ wenn die Kachel unter einer Koerperkante (V_XL / V_XR) fest ist
solid_row:      ld a,(V_XL)
                call px_tx
                call tile_solid
                or a
                ret nz
                ld a,(V_XR)
                call px_tx
                call tile_solid
                or a
                ret

set_edges:      ld a,(PX+1)
                add a,2
                ld (V_XL),a
                add a,11
                ld (V_XR),a
                ret

; Groesse umschalten: beim Wachsen nach oben (nur wenn Platz ist), beim Schrumpfen Fuesse halten
toggle_size:    ld a,(PY+1)
                ld (V_SAVEY),a
                ld a,(PSIZE)
                xor 1
                ld (PSIZE),a
                jr z,ts_shrink
                ld a,(V_SAVEY)
                sub 16
                jr c,ts_cancel
                ld (PY+1),a
                call calc_rows
                ld a,(PX+1)
                add a,2
                call solid_col
                jr nz,ts_cancel
                ld a,(PX+1)
                add a,13
                call solid_col
                jr nz,ts_cancel
                ret
ts_shrink:      ld a,(V_SAVEY)
                add a,16
                ld (PY+1),a
                ret
ts_cancel:      ld a,(V_SAVEY)
                ld (PY+1),a
                ld a,(PSIZE)
                xor 1
                ld (PSIZE),a
                ret

; hcollide: nach der Bewegung in x gegen feste Kacheln pruefen, an der Kante ausrichten
hcollide:       call calc_rows
                ld hl,(PV)
                ld a,h
                or l
                ret z
                bit 7,h
                jr nz,hc_left
                ld a,(PX+1)
                add a,13
                call solid_col
                ret z
                ld a,(CAM)              ; Kachelkanten liegen bei x = q (mod 16), q = 8 * (CAM and 1)
                and 1
                add a,a
                add a,a
                add a,a
                ld c,a
                ld a,(PX+1)
                add a,13
                sub c
                and 0F0h
                add a,c
                sub 14
                jr hc_snap
hc_left:        ld a,(PX+1)
                add a,2
                call solid_col
                ret z
                ld a,(CAM)
                and 1
                add a,a
                add a,a
                add a,a
                ld c,a
                ld a,(PX+1)
                add a,2
                sub c
                and 0F0h
                add a,c
                add a,14
hc_snap:        ld h,a
                ld l,0
                ld (PX),hl
                ld hl,0
                ld (PV),hl
                ret

; vertical: Sprung, Schwerkraft, Landen, Kopfstoss, Bodenkontakt
vertical:       call calc_rows          ; V_H
                ld a,(PGND)
                or a
                jr z,vt_air
                ld a,(V_JREQ)
                or a
                jr z,vt_stand
                ld hl,0-JUMPV           ; Absprung
                ld (VY),hl
                xor a
                ld (PGND),a
                jp vt_move
vt_stand:       ld hl,0
                ld (VY),hl
                jp vt_probe
vt_air:         ld hl,(VY)
                bit 7,h
                jr z,vt_g2
                ld a,(INP)              ; Aufstieg: Feuer losgelassen -> abbremsen
                and I_FIRE
                jr nz,vt_g2
                ld de,0-CUTV
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,vt_g2
                ex de,hl
vt_g2:          ld de,GRAV
                add hl,de
                bit 7,h
                jr nz,vt_g3
                ld a,h
                cp 6
                jr c,vt_g3
                ld hl,MAXFALL
vt_g3:          ld (VY),hl
vt_move:        ld hl,(VY)
                ld de,(PY)
                add hl,de
                ld a,(VY+1)
                bit 7,a
                jp z,vt_down
; ---- aufwaerts
                jr c,vt_up
                ld hl,0                 ; oben aus dem Bild: bei 0 anhalten
vt_up:          ld (PY),hl
                call set_edges
                ld a,(PY+1)
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld b,a
                call solid_row
                jp z,vt_probe
                ld a,(PY+1)             ; Kopfstoss: unter die Kachel setzen
                and 0F0h
                add a,16
                ld h,a
                ld l,0
                ld (PY),hl
                ld hl,0
                ld (VY),hl
                jp vt_probe
; ---- abwaerts
vt_down:        ld (PY),hl
                call set_edges
                ld a,(V_H)
                dec a
                ld c,a
                ld a,(PY+1)
                add a,c
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld b,a
                call solid_row
                jp z,vt_probe
                ld a,(V_H)              ; Landen: Fuesse auf die Kachelkante
                ld c,a
                dec a
                ld b,a
                ld a,(PY+1)
                add a,b
                and 0F0h
                sub c
                ld h,a
                ld l,0
                ld (PY),hl
                ld hl,0
                ld (VY),hl
; ---- Bodenkontakt pruefen (nur wenn nicht aufsteigend)
vt_probe:       call set_edges
                xor a
                ld (PGND),a
                ld a,(VY+1)
                bit 7,a
                ret nz
                ld a,(V_H)
                ld c,a
                ld a,(PY+1)
                add a,c
                rrca
                rrca
                rrca
                rrca
                and 0Fh
                ld b,a
                call solid_row
                ret z
                ld a,1
                ld (PGND),a
                ret

; ---------------------------------------------------------
; Texte
; ---------------------------------------------------------
txt_title:      db "FEUERWEHRMANN",0
txt_stage:      db "STUFE 3 - SCROLLEN",0
txt_start:      db "FEUER ODER LEERTASTE = START",0
txt_keys:       db "O P LAUFEN SPACE SPRUNG G=GROSS",0

; ---------------------------------------------------------
; Daten (vom Generator erzeugt)
; ---------------------------------------------------------
; ---- Kachel-Zeiger ----
tile_ptr:
                dw tile_sky_0
                dw tile_cloud_l_0
                dw tile_cloud_r_0
                dw tile_sky_1
                dw tile_coin_1
                dw tile_stone
                dw tile_brick
                dw tile_chest
                dw tile_sky_2
                dw tile_sky_3
                dw tile_barrel
                dw tile_hill_l_3
                dw tile_hill_m_3
                dw tile_hill_r_3
                dw tile_hydrant
                dw tile_grass
                dw tile_dirt

; ---- fest (1) oder frei (0) je Kachel-Instanz ----
solid_tab:
                db 0,0,0,0,0,1,1,1,0,0,1,0,0,0,1,1,1

; ---- Kacheln: TL,TR,BL,BR je 8 Byte, dann 4 Attribute ----
tile_sky_0:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 1,1,1,1
tile_cloud_l_0:
                db 0,0,0,3,7,00Fh,03Fh,07Fh
                db 0,0,0,0E0h,0F0h,0F8h,0F8h,0FFh
                db 0FFh,0FFh,0FFh,07Fh,03Fh,0,0,0
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 1,1,1,1
tile_cloud_r_0:
                db 0,0,0,7,00Fh,01Fh,01Fh,0FFh
                db 0,0,0,0C0h,0E0h,0F0h,0FCh,0FEh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 0FFh,0FFh,0FFh,0FEh,0FCh,0,0,0
                db 1,1,1,1
tile_sky_1:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 9,9,9,9
tile_coin_1:
                db 0,0,3,7,00Fh,00Eh,00Eh,00Eh
                db 0,0,0C0h,0E0h,0F0h,070h,070h,070h
                db 00Eh,00Eh,00Eh,00Fh,7,3,0,0
                db 070h,070h,070h,0F0h,0E0h,0C0h,0,0
                db 00Ah,00Ah,00Ah,00Ah
tile_stone:
                db 0FFh,080h,080h,080h,080h,080h,080h,080h
                db 0FFh,080h,080h,080h,080h,080h,080h,080h
                db 0FFh,8,8,8,8,8,8,8
                db 0FFh,8,8,8,8,8,8,8
                db 057h,057h,057h,057h
tile_brick:
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 05Fh,05Fh,05Fh,05Fh
tile_chest:
                db 0FFh,080h,080h,080h,080h,0FFh,080h,081h
                db 0FFh,1,1,1,1,0FFh,1,081h
                db 083h,083h,081h,080h,080h,080h,080h,0FFh
                db 0C1h,0C1h,081h,1,1,1,1,0FFh
                db 064h,064h,064h,064h
tile_sky_2:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 011h,011h,011h,011h
tile_sky_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,019h,019h
tile_barrel:
                db 07Fh,092h,0FFh,0FFh,092h,092h,092h,092h
                db 0FEh,049h,0FFh,0FFh,049h,049h,049h,049h
                db 092h,092h,092h,092h,0FFh,0FFh,092h,07Fh
                db 049h,049h,049h,049h,0FFh,0FFh,049h,0FEh
                db 06Dh,06Dh,06Dh,06Dh
tile_hill_l_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,019h,021h
tile_hill_m_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 021h,021h,021h,021h
tile_hill_r_3:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 019h,019h,021h,019h
tile_hydrant:
                db 0,0,7,00Fh,00Fh,7,00Fh,03Fh
                db 0,0,0E0h,0F0h,0F0h,0E0h,0F0h,0FCh
                db 03Fh,0EFh,0EFh,03Fh,00Fh,00Fh,03Fh,03Fh
                db 0FCh,0F7h,0F7h,0FCh,0F0h,0F0h,0FCh,0FCh
                db 076h,076h,076h,076h
tile_grass:
                db 0,0,020h,0,2,0ADh,089h,0
                db 0,0,020h,0,2,0ADh,089h,0
                db 044h,2,082h,010h,021h,2,040h,8
                db 044h,2,082h,010h,021h,2,040h,8
                db 042h,042h,04Dh,04Dh
tile_dirt:
                db 0,010h,0,2,0,040h,2,0DAh
                db 0,010h,0,2,0,040h,2,0DAh
                db 0,010h,0,2,0,040h,2,0DAh
                db 0,010h,0,2,0,040h,2,0DAh
                db 04Dh,04Dh,04Dh,04Dh

; ---- Welt: 64 Kacheln breit, Zeilenabstand 64 (Kachel-Instanz-Nummern) ----
CAMMAX          equ 96
level_map:
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,1,2,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0
                db 0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,4,4,4,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,5
                db 3,3,3,3,3,3,4,4,4,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,4,4,4,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,5
                db 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,6,7,6,7,6,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,5,5
                db 8,8,8,8,8,6,7,6,7,6,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,5,5,5
                db 8,8,8,8,8,8,8,8,8,8,8,8,8,6,6,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,6,7,6,8,8,8,8,8,8,8,8,8,8,8,8,8,8,5,5,8,8,8,8,8,8,8,8,8,5,5,5,5
                db 9,9,9,9,9,9,9,9,9,9,9,5,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,00Ah,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,5,9,9,5,5,5,5,9,9,9,9,00Ah,9,9,5,5,5,5,5
                db 9,9,00Bh,00Ch,00Dh,9,9,00Ah,9,9,5,5,9,9,00Eh,9,9,9,9,9,00Eh,9,9,9,00Bh,00Ch,00Dh,9,00Ah,00Ah,9,9,9,9,9,9,9,9,9,9,00Bh,00Ch,00Dh,9,5,5,9,5,5,5,5,5,5,9,00Eh,9,00Ah,00Ah,5,5,5,5,5,5
                db 00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh
                db 010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h,010h

; ---- Zellgrafiken: 34 verschiedene Zellen ----
cell_gfx:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,020h,0,2,0ADh,089h,0
                db 044h,2,082h,010h,021h,2,040h,8
                db 0,010h,0,2,0,040h,2,0DAh
                db 0,0,0,3,7,00Fh,03Fh,07Fh
                db 0FFh,0FFh,0FFh,07Fh,03Fh,0,0,0
                db 0,0,0,0E0h,0F0h,0F8h,0F8h,0FFh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,7,00Fh,01Fh,01Fh,0FFh
                db 0,0,0,0C0h,0E0h,0F0h,0FCh,0FEh
                db 0FFh,0FFh,0FFh,0FEh,0FCh,0,0,0
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0,0,3,7,00Fh,00Eh,00Eh,00Eh
                db 00Eh,00Eh,00Eh,00Fh,7,3,0,0
                db 0FFh,080h,080h,080h,080h,0FFh,080h,081h
                db 083h,083h,081h,080h,080h,080h,080h,0FFh
                db 0,0,0C0h,0E0h,0F0h,070h,070h,070h
                db 070h,070h,070h,0F0h,0E0h,0C0h,0,0
                db 0FFh,1,1,1,1,0FFh,1,081h
                db 0C1h,0C1h,081h,1,1,1,1,0FFh
                db 07Fh,092h,0FFh,0FFh,092h,092h,092h,092h
                db 092h,092h,092h,092h,0FFh,0FFh,092h,07Fh
                db 0FEh,049h,0FFh,0FFh,049h,049h,049h,049h
                db 049h,049h,049h,049h,0FFh,0FFh,049h,0FEh
                db 0FFh,080h,080h,080h,080h,080h,080h,080h
                db 0FFh,8,8,8,8,8,8,8
                db 0,0,7,00Fh,00Fh,7,00Fh,03Fh
                db 03Fh,0EFh,0EFh,03Fh,00Fh,00Fh,03Fh,03Fh
                db 0,0,0E0h,0F0h,0F0h,0E0h,0F0h,0FCh
                db 0FCh,0F7h,0F7h,0FCh,0F0h,0F0h,0FCh,0FCh

; ---- Scroll-Listen je Zellgrenze (rechts: Zelle k+1 sichtbar machen, links: Zelle k) ----
sl_none:        db 0,0
slR_3:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 0,0
slR_4:
                db 64,64
                dw cell_gfx+72
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 96,80
                dw 0
                db 33
                db 0,0
slR_5:
                db 64,64
                dw cell_gfx+96
                db 1
                db 64,80
                dw 0
                db 33
                db 0,0
slR_6:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_7:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 64,80
                dw 0
                db 25
                db 0,0
slR_8:
                db 96,80
                dw 0
                db 25
                db 0,0
slR_9:
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_11:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 128,72
                dw cell_gfx+144
                db 100
                db 160,72
                dw cell_gfx+152
                db 100
                db 0,0
slR_12:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 128,72
                dw cell_gfx+176
                db 100
                db 160,72
                dw cell_gfx+184
                db 100
                db 0,0
slR_13:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slR_14:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slR_15:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 128,72
                dw cell_gfx+144
                db 100
                db 160,72
                dw cell_gfx+152
                db 100
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_16:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 128,72
                dw cell_gfx+176
                db 100
                db 160,72
                dw cell_gfx+184
                db 100
                db 0,0
slR_17:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 0,72
                dw 0
                db 9
                db 32,72
                dw 0
                db 9
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_18:
                db 128,64
                dw cell_gfx+72
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slR_19:
                db 128,64
                dw cell_gfx+96
                db 1
                db 128,72
                dw 0
                db 17
                db 160,72
                dw 0
                db 17
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_20:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_21:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_23:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_25:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_26:
                db 64,64
                dw cell_gfx+72
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 0,0
slR_27:
                db 64,64
                dw cell_gfx+96
                db 1
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slR_28:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slR_29:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_39:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slR_40:
                db 64,64
                dw cell_gfx+72
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slR_41:
                db 64,64
                dw cell_gfx+96
                db 1
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_42:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_43:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 0,0
slR_48:
                db 96,80
                dw 0
                db 33
                db 0,0
slR_49:
                db 64,80
                dw 0
                db 33
                db 0,0
slR_51:
                db 64,80
                dw 0
                db 25
                db 0,0
slR_52:
                db 96,80
                dw 0
                db 25
                db 0,0
slR_55:
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slR_56:
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slR_57:
                db 0,80
                dw cell_gfx+192
                db 109
                db 32,80
                dw cell_gfx+200
                db 109
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slR_58:
                db 0,80
                dw cell_gfx+208
                db 109
                db 32,80
                dw cell_gfx+216
                db 109
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slR_59:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_61:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 0,0
slR_62:
                db 128,64
                dw cell_gfx+72
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slR_63:
                db 128,64
                dw cell_gfx+96
                db 1
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_64:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_65:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 192,72
                dw cell_gfx+144
                db 100
                db 224,72
                dw cell_gfx+152
                db 100
                db 0,0
slR_66:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 192,72
                dw cell_gfx+176
                db 100
                db 224,72
                dw cell_gfx+184
                db 100
                db 0,0
slR_67:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_68:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 0,0
slR_69:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slR_70:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 0,0
slR_71:
                db 0,72
                dw 0
                db 9
                db 32,72
                dw 0
                db 9
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_73:
                db 64,72
                dw cell_gfx+144
                db 100
                db 96,72
                dw cell_gfx+152
                db 100
                db 0,0
slR_74:
                db 64,72
                dw cell_gfx+176
                db 100
                db 96,72
                dw cell_gfx+184
                db 100
                db 0,0
slR_75:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_76:
                db 64,64
                dw cell_gfx+72
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 0,0
slR_77:
                db 64,64
                dw cell_gfx+96
                db 1
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 64,72
                dw cell_gfx+144
                db 100
                db 96,72
                dw cell_gfx+152
                db 100
                db 0,0
slR_78:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 64,72
                dw cell_gfx+176
                db 100
                db 96,72
                dw cell_gfx+184
                db 100
                db 0,0
slR_79:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 0,0
slR_80:
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 96,80
                dw 0
                db 33
                db 0,0
slR_81:
                db 192,64
                dw 0
                db 9
                db 224,64
                dw 0
                db 9
                db 64,72
                dw 0
                db 9
                db 96,72
                dw 0
                db 9
                db 64,80
                dw 0
                db 33
                db 0,0
slR_83:
                db 64,80
                dw 0
                db 25
                db 0,0
slR_84:
                db 96,80
                dw 0
                db 25
                db 0,0
slR_87:
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_89:
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_91:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_93:
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_95:
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_97:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 192,72
                dw cell_gfx+224
                db 87
                db 224,72
                dw cell_gfx+232
                db 87
                db 0,0
slR_98:
                db 128,64
                dw cell_gfx+72
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slR_99:
                db 128,64
                dw cell_gfx+96
                db 1
                db 0,0
slR_100:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_101:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slR_103:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 0,0
slR_105:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_107:
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slR_108:
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slR_109:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slR_111:
                db 0,80
                dw cell_gfx+192
                db 109
                db 32,80
                dw cell_gfx+200
                db 109
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slR_112:
                db 0,80
                dw cell_gfx+208
                db 109
                db 32,80
                dw cell_gfx+216
                db 109
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slR_113:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slR_114:
                db 64,64
                dw cell_gfx+72
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slR_115:
                db 64,64
                dw cell_gfx+96
                db 1
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_116:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 0,0
slR_117:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 0,0
slR_119:
                db 192,72
                dw cell_gfx+224
                db 87
                db 224,72
                dw cell_gfx+232
                db 87
                db 0,0
slR_121:
                db 128,72
                dw cell_gfx+224
                db 87
                db 160,72
                dw cell_gfx+232
                db 87
                db 0,0
slR_123:
                db 64,72
                dw cell_gfx+224
                db 87
                db 96,72
                dw cell_gfx+232
                db 87
                db 0,0
slR_125:
                db 192,64
                dw cell_gfx+224
                db 87
                db 224,64
                dw cell_gfx+232
                db 87
                db 0,72
                dw cell_gfx+224
                db 87
                db 32,72
                dw cell_gfx+232
                db 87
                db 0,0
slL_3:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 0,0
slL_4:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 96,80
                dw 0
                db 25
                db 0,0
slL_5:
                db 64,64
                dw cell_gfx+72
                db 1
                db 64,80
                dw 0
                db 25
                db 0,0
slL_6:
                db 64,64
                dw cell_gfx+96
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_7:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 64,80
                dw 0
                db 33
                db 0,0
slL_8:
                db 96,80
                dw 0
                db 33
                db 0,0
slL_9:
                db 128,72
                dw 0
                db 17
                db 160,72
                dw 0
                db 17
                db 0,0
slL_11:
                db 0,72
                dw 0
                db 9
                db 32,72
                dw 0
                db 9
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 0,0
slL_12:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 128,72
                dw cell_gfx+144
                db 100
                db 160,72
                dw cell_gfx+152
                db 100
                db 0,0
slL_13:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 128,72
                dw cell_gfx+176
                db 100
                db 160,72
                dw cell_gfx+184
                db 100
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_14:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slL_15:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slL_16:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 128,72
                dw cell_gfx+144
                db 100
                db 160,72
                dw cell_gfx+152
                db 100
                db 0,0
slL_17:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 128,72
                dw cell_gfx+176
                db 100
                db 160,72
                dw cell_gfx+184
                db 100
                db 0,0
slL_18:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 0,0
slL_19:
                db 128,64
                dw cell_gfx+72
                db 1
                db 128,72
                dw cell_gfx+120
                db 95
                db 160,72
                dw cell_gfx+120
                db 95
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_20:
                db 128,64
                dw cell_gfx+96
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_21:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 0,0
slL_23:
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slL_25:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slL_26:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 0,0
slL_27:
                db 64,64
                dw cell_gfx+72
                db 1
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_28:
                db 64,64
                dw cell_gfx+96
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slL_29:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slL_39:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_40:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slL_41:
                db 64,64
                dw cell_gfx+72
                db 1
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slL_42:
                db 64,64
                dw cell_gfx+96
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_43:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 0,0
slL_48:
                db 96,80
                dw 0
                db 25
                db 0,0
slL_49:
                db 64,80
                dw 0
                db 25
                db 0,0
slL_51:
                db 64,80
                dw 0
                db 33
                db 0,0
slL_52:
                db 96,80
                dw 0
                db 33
                db 0,0
slL_55:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_56:
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slL_57:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slL_58:
                db 0,80
                dw cell_gfx+192
                db 109
                db 32,80
                dw cell_gfx+200
                db 109
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slL_59:
                db 0,80
                dw cell_gfx+208
                db 109
                db 32,80
                dw cell_gfx+216
                db 109
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slL_61:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 0,0
slL_62:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 0,0
slL_63:
                db 128,64
                dw cell_gfx+72
                db 1
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slL_64:
                db 128,64
                dw cell_gfx+96
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_65:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 0,72
                dw 0
                db 9
                db 32,72
                dw 0
                db 9
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 0,0
slL_66:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 192,72
                dw cell_gfx+144
                db 100
                db 224,72
                dw cell_gfx+152
                db 100
                db 0,0
slL_67:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 192,72
                dw cell_gfx+176
                db 100
                db 224,72
                dw cell_gfx+184
                db 100
                db 0,0
slL_68:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 0,0
slL_69:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 192,72
                dw cell_gfx+120
                db 95
                db 224,72
                dw cell_gfx+120
                db 95
                db 0,0
slL_70:
                db 0,72
                dw cell_gfx+128
                db 10
                db 32,72
                dw cell_gfx+136
                db 10
                db 0,0
slL_71:
                db 0,72
                dw cell_gfx+160
                db 10
                db 32,72
                dw cell_gfx+168
                db 10
                db 64,72
                dw 0
                db 9
                db 96,72
                dw 0
                db 9
                db 0,0
slL_73:
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 0,0
slL_74:
                db 64,72
                dw cell_gfx+144
                db 100
                db 96,72
                dw cell_gfx+152
                db 100
                db 0,0
slL_75:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 192,64
                dw 0
                db 9
                db 224,64
                dw 0
                db 9
                db 64,72
                dw cell_gfx+176
                db 100
                db 96,72
                dw cell_gfx+184
                db 100
                db 0,0
slL_76:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 0,0
slL_77:
                db 64,64
                dw cell_gfx+72
                db 1
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 0,0
slL_78:
                db 64,64
                dw cell_gfx+96
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 64,72
                dw cell_gfx+144
                db 100
                db 96,72
                dw cell_gfx+152
                db 100
                db 0,0
slL_79:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 64,72
                dw cell_gfx+176
                db 100
                db 96,72
                dw cell_gfx+184
                db 100
                db 0,0
slL_80:
                db 192,64
                dw cell_gfx+128
                db 10
                db 224,64
                dw cell_gfx+136
                db 10
                db 96,80
                dw 0
                db 25
                db 0,0
slL_81:
                db 192,64
                dw cell_gfx+160
                db 10
                db 224,64
                dw cell_gfx+168
                db 10
                db 64,72
                dw cell_gfx+120
                db 95
                db 96,72
                dw cell_gfx+120
                db 95
                db 64,80
                dw 0
                db 25
                db 0,0
slL_83:
                db 64,80
                dw 0
                db 33
                db 0,0
slL_84:
                db 96,80
                dw 0
                db 33
                db 0,0
slL_87:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_89:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 0,0
slL_91:
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slL_93:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_95:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 0,0
slL_97:
                db 128,64
                dw 0
                db 1
                db 160,64
                dw 0
                db 1
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slL_98:
                db 128,64
                dw cell_gfx+56
                db 1
                db 160,64
                dw cell_gfx+64
                db 1
                db 0,0
slL_99:
                db 128,64
                dw cell_gfx+72
                db 1
                db 0,0
slL_100:
                db 128,64
                dw cell_gfx+96
                db 1
                db 160,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_101:
                db 128,64
                dw cell_gfx+104
                db 1
                db 160,64
                dw cell_gfx+112
                db 1
                db 192,72
                dw cell_gfx+224
                db 87
                db 224,72
                dw cell_gfx+232
                db 87
                db 0,0
slL_103:
                db 0,80
                dw cell_gfx+224
                db 87
                db 32,80
                dw cell_gfx+232
                db 87
                db 0,0
slL_105:
                db 64,80
                dw cell_gfx+224
                db 87
                db 96,80
                dw cell_gfx+232
                db 87
                db 0,0
slL_107:
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_108:
                db 64,80
                dw cell_gfx+240
                db 118
                db 96,80
                dw cell_gfx+248
                db 118
                db 0,0
slL_109:
                db 64,80
                dw cell_gfx+256
                db 118
                db 96,80
                dw cell_gfx+264
                db 118
                db 0,0
slL_111:
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 64,80
                dw 0
                db 25
                db 96,80
                dw 0
                db 25
                db 0,0
slL_112:
                db 0,80
                dw cell_gfx+192
                db 109
                db 32,80
                dw cell_gfx+200
                db 109
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slL_113:
                db 64,64
                dw 0
                db 1
                db 96,64
                dw 0
                db 1
                db 0,80
                dw cell_gfx+208
                db 109
                db 32,80
                dw cell_gfx+216
                db 109
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slL_114:
                db 64,64
                dw cell_gfx+56
                db 1
                db 96,64
                dw cell_gfx+64
                db 1
                db 64,80
                dw cell_gfx+192
                db 109
                db 96,80
                dw cell_gfx+200
                db 109
                db 0,0
slL_115:
                db 64,64
                dw cell_gfx+72
                db 1
                db 64,80
                dw cell_gfx+208
                db 109
                db 96,80
                dw cell_gfx+216
                db 109
                db 0,0
slL_116:
                db 64,64
                dw cell_gfx+96
                db 1
                db 96,64
                dw cell_gfx+80
                db 1
                db 0,0
slL_117:
                db 64,64
                dw cell_gfx+104
                db 1
                db 96,64
                dw cell_gfx+112
                db 1
                db 0,80
                dw 0
                db 25
                db 32,80
                dw 0
                db 25
                db 0,0
slL_119:
                db 192,72
                dw 0
                db 17
                db 224,72
                dw 0
                db 17
                db 0,0
slL_121:
                db 128,72
                dw 0
                db 17
                db 160,72
                dw 0
                db 17
                db 0,0
slL_123:
                db 64,72
                dw 0
                db 9
                db 96,72
                dw 0
                db 9
                db 0,0
slL_125:
                db 192,64
                dw 0
                db 9
                db 224,64
                dw 0
                db 9
                db 0,72
                dw 0
                db 9
                db 32,72
                dw 0
                db 9
                db 0,0
scroll_idxR:
                dw sl_none
                dw sl_none
                dw sl_none
                dw slR_3
                dw slR_4
                dw slR_5
                dw slR_6
                dw slR_7
                dw slR_8
                dw slR_9
                dw sl_none
                dw slR_11
                dw slR_12
                dw slR_13
                dw slR_14
                dw slR_15
                dw slR_16
                dw slR_17
                dw slR_18
                dw slR_19
                dw slR_20
                dw slR_21
                dw sl_none
                dw slR_23
                dw sl_none
                dw slR_25
                dw slR_26
                dw slR_27
                dw slR_28
                dw slR_29
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw slR_39
                dw slR_40
                dw slR_41
                dw slR_42
                dw slR_43
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw slR_48
                dw slR_49
                dw sl_none
                dw slR_51
                dw slR_52
                dw sl_none
                dw sl_none
                dw slR_55
                dw slR_56
                dw slR_57
                dw slR_58
                dw slR_59
                dw sl_none
                dw slR_61
                dw slR_62
                dw slR_63
                dw slR_64
                dw slR_65
                dw slR_66
                dw slR_67
                dw slR_68
                dw slR_69
                dw slR_70
                dw slR_71
                dw sl_none
                dw slR_73
                dw slR_74
                dw slR_75
                dw slR_76
                dw slR_77
                dw slR_78
                dw slR_79
                dw slR_80
                dw slR_81
                dw sl_none
                dw slR_83
                dw slR_84
                dw sl_none
                dw sl_none
                dw slR_87
                dw sl_none
                dw slR_89
                dw sl_none
                dw slR_91
                dw sl_none
                dw slR_93
                dw sl_none
                dw slR_95
                dw sl_none
                dw slR_97
                dw slR_98
                dw slR_99
                dw slR_100
                dw slR_101
                dw sl_none
                dw slR_103
                dw sl_none
                dw slR_105
                dw sl_none
                dw slR_107
                dw slR_108
                dw slR_109
                dw sl_none
                dw slR_111
                dw slR_112
                dw slR_113
                dw slR_114
                dw slR_115
                dw slR_116
                dw slR_117
                dw sl_none
                dw slR_119
                dw sl_none
                dw slR_121
                dw sl_none
                dw slR_123
                dw sl_none
                dw slR_125
                dw sl_none
                dw sl_none
scroll_idxL:
                dw sl_none
                dw sl_none
                dw sl_none
                dw slL_3
                dw slL_4
                dw slL_5
                dw slL_6
                dw slL_7
                dw slL_8
                dw slL_9
                dw sl_none
                dw slL_11
                dw slL_12
                dw slL_13
                dw slL_14
                dw slL_15
                dw slL_16
                dw slL_17
                dw slL_18
                dw slL_19
                dw slL_20
                dw slL_21
                dw sl_none
                dw slL_23
                dw sl_none
                dw slL_25
                dw slL_26
                dw slL_27
                dw slL_28
                dw slL_29
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw slL_39
                dw slL_40
                dw slL_41
                dw slL_42
                dw slL_43
                dw sl_none
                dw sl_none
                dw sl_none
                dw sl_none
                dw slL_48
                dw slL_49
                dw sl_none
                dw slL_51
                dw slL_52
                dw sl_none
                dw sl_none
                dw slL_55
                dw slL_56
                dw slL_57
                dw slL_58
                dw slL_59
                dw sl_none
                dw slL_61
                dw slL_62
                dw slL_63
                dw slL_64
                dw slL_65
                dw slL_66
                dw slL_67
                dw slL_68
                dw slL_69
                dw slL_70
                dw slL_71
                dw sl_none
                dw slL_73
                dw slL_74
                dw slL_75
                dw slL_76
                dw slL_77
                dw slL_78
                dw slL_79
                dw slL_80
                dw slL_81
                dw sl_none
                dw slL_83
                dw slL_84
                dw sl_none
                dw sl_none
                dw slL_87
                dw sl_none
                dw slL_89
                dw sl_none
                dw slL_91
                dw sl_none
                dw slL_93
                dw sl_none
                dw slL_95
                dw sl_none
                dw slL_97
                dw slL_98
                dw slL_99
                dw slL_100
                dw slL_101
                dw sl_none
                dw slL_103
                dw sl_none
                dw slL_105
                dw sl_none
                dw slL_107
                dw slL_108
                dw slL_109
                dw sl_none
                dw slL_111
                dw slL_112
                dw slL_113
                dw slL_114
                dw slL_115
                dw slL_116
                dw slL_117
                dw sl_none
                dw slL_119
                dw sl_none
                dw slL_121
                dw sl_none
                dw slL_123
                dw sl_none
                dw slL_125
                dw sl_none
                dw sl_none

BLK_SMALL       equ 98
BLK_LARGE       equ 196

; ---- Ink je Zellzeile ----
ink_small:
                db 2,3
ink_large:
                db 2,4,3,0

; ---- Bild-Zeiger (Groesse, Richtung, Phase) ----
img_ptr:
                dw img_s0_d0_f0
                dw img_s0_d0_f1
                dw img_s0_d0_f2
                dw img_s0_d0_f3
                dw img_s0_d1_f0
                dw img_s0_d1_f1
                dw img_s0_d1_f2
                dw img_s0_d1_f3
                dw img_s1_d0_f0
                dw img_s1_d0_f1
                dw img_s1_d0_f2
                dw img_s1_d0_f3
                dw img_s1_d1_f0
                dw img_s1_d1_f1
                dw img_s1_d1_f2
                dw img_s1_d1_f3

code_end:

                end start
