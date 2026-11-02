; ===========================================================
;  SUPERMARIO (Feuerwehr-Jump'n'Run)  -  ZX Spectrum 128K
;  Stufe 0: Kacheln, Figuren-Studien, statischer Wiesenbildschirm
;  Assembler: pasmo   (pasmo --tapbas supermario.asm supermario.tap)
;  Diese Datei wird aus src/supermario.asm.in + tools/gen.py erzeugt.
; ===========================================================

SKYATTR         equ 68h                 ; Paper cyan hell, Ink schwarz

                org 8000h

start:          ld a,5                  ; Rand cyan
                out (0FEh),a

                ld hl,4000h             ; Bildschirm loeschen
                ld de,4001h
                ld bc,17FFh
                ld (hl),0
                ldir

                ld hl,5800h             ; Attribute: Himmel
                ld de,5801h
                ld bc,02FFh
                ld (hl),SKYATTR
                ldir

; ---- Karte zeichnen (16x12 Kacheln) ----
                ld hl,level_map
                ld b,0                  ; ty
map_row:        ld c,0                  ; tx
map_col:        push hl
                push bc
                ld a,(hl)
                or a                    ; 0 = Himmel, schon gezeichnet
                call nz,draw_tile
                pop bc
                pop hl
                inc hl
                inc c
                ld a,c
                cp 16
                jr nz,map_col
                inc b
                ld a,b
                cp 12
                jr nz,map_row

; ---- Figuren zeichnen ----
                ld hl,objects
obj_next:       ld a,(hl)
                cp 0FFh
                jr z,obj_done
                inc hl
                ld c,(hl)               ; cx (Zeichenzelle)
                inc hl
                ld b,(hl)               ; cy (Zeichenzelle)
                inc hl
                push hl
                call draw_sprite
                pop hl
                jr obj_next
obj_done:
main_loop:      halt
                jr main_loop

; ---------------------------------------------------------
; cell_addr: B=cy (0..23), C=cx (0..31)  ->  DE = Bildschirmadresse
; ---------------------------------------------------------
cell_addr:      ld a,b
                and 18h
                or 40h
                ld d,a
                ld a,b
                and 7
                rrca
                rrca
                rrca
                add a,c
                ld e,a
                ret

; ---------------------------------------------------------
; put_cell: HL=Quelle (8 Byte), B=cy, C=cx   (HL wird +8)
; ---------------------------------------------------------
put_cell:       call cell_addr
                ld b,8
pc_row:         ld a,(hl)
                ld (de),a
                inc hl
                inc d
                djnz pc_row
                ret

; ---------------------------------------------------------
; put_mcell: HL=Quelle (8x Maske,Pixel), B=cy, C=cx   (HL wird +16)
; Maske: Bit 1 = Hintergrund behalten
; ---------------------------------------------------------
put_mcell:      call cell_addr
                ld b,8
pm_row:         ld a,(de)
                and (hl)
                inc hl
                or (hl)
                inc hl
                ld (de),a
                inc d
                djnz pm_row
                ret

; ---------------------------------------------------------
; attr_addr: B=cy, C=cx -> DE = Attributadresse
; ---------------------------------------------------------
attr_addr:      ld a,b
                rrca
                rrca
                rrca
                ld e,a
                and 3
                or 58h
                ld d,a
                ld a,e
                and 0E0h
                add a,c
                ld e,a
                ret

; put_attr: A=Attribut, B=cy, C=cx   (HL, BC bleiben)
put_attr:       push af
                call attr_addr
                pop af
                ld (de),a
                ret

; put_sattr: A=Ink (0FFh = nichts), B=cy, C=cx; behaelt Paper/Bright
put_sattr:      cp 0FFh
                ret z
                ld (v_ink),a
                push bc
                call attr_addr
                ld a,(de)
                and 78h
                ld b,a
                ld a,(v_ink)
                or b
                ld (de),a
                pop bc
                ret

; ---------------------------------------------------------
; Zellkoordinaten aus v_cx / v_cy in B / C laden
; ---------------------------------------------------------
ld_cell:        ld a,(v_cy)
                add a,d                 ; D = Zeilenversatz
                ld b,a
                ld a,(v_cx)
                add a,e                 ; E = Spaltenversatz
                ld c,a
                ret

; ---------------------------------------------------------
; draw_tile: A=Kachel-Id, B=ty, C=tx  (16x16 Pixel)
; ---------------------------------------------------------
draw_tile:      ld e,a
                ld a,c
                add a,a
                ld (v_cx),a
                ld a,b
                add a,a
                ld (v_cy),a
                ld l,e
                ld h,0
                add hl,hl
                ld de,tile_ptr
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl                ; HL = Kachel-Daten
                ld de,0000h
                call ld_cell
                call put_cell
                ld de,0001h
                call ld_cell
                call put_cell
                ld de,0100h
                call ld_cell
                call put_cell
                ld de,0101h
                call ld_cell
                call put_cell
                ld de,0000h             ; Attribute TL, TR, BL, BR
                call ld_cell
                ld a,(hl)
                inc hl
                call put_attr
                ld de,0001h
                call ld_cell
                ld a,(hl)
                inc hl
                call put_attr
                ld de,0100h
                call ld_cell
                ld a,(hl)
                inc hl
                call put_attr
                ld de,0101h
                call ld_cell
                ld a,(hl)
                call put_attr
                ret

; ---------------------------------------------------------
; draw_sprite: A=Sprite-Id, B=cy, C=cx   (16x16, mit Maske)
; ---------------------------------------------------------
draw_sprite:    ld e,a
                ld a,c
                ld (v_cx),a
                ld a,b
                ld (v_cy),a
                ld l,e
                ld h,0
                add hl,hl
                ld de,spr_ptr
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl                ; HL = Sprite-Daten
                ld de,0000h
                call ld_cell
                call put_mcell
                ld de,0001h
                call ld_cell
                call put_mcell
                ld de,0100h
                call ld_cell
                call put_mcell
                ld de,0101h
                call ld_cell
                call put_mcell
                ld de,0000h             ; Ink TL, TR, BL, BR
                call ld_cell
                ld a,(hl)
                inc hl
                call put_sattr
                ld de,0001h
                call ld_cell
                ld a,(hl)
                inc hl
                call put_sattr
                ld de,0100h
                call ld_cell
                ld a,(hl)
                inc hl
                call put_sattr
                ld de,0101h
                call ld_cell
                ld a,(hl)
                call put_sattr
                ret

; ---------------------------------------------------------
; Variablen
; ---------------------------------------------------------
v_cx:           db 0
v_cy:           db 0
v_ink:          db 0

; ---------------------------------------------------------
; Daten (vom Generator erzeugt)
; ---------------------------------------------------------
; ---- Kachel-Zeiger ----
tile_ptr:
                dw tile_sky
                dw tile_cloud_l
                dw tile_cloud_r
                dw tile_hill_l
                dw tile_hill_m
                dw tile_hill_r
                dw tile_grass
                dw tile_dirt
                dw tile_stone
                dw tile_brick
                dw tile_chest
                dw tile_barrel
                dw tile_coin
                dw tile_hydrant

; ---- Kacheln: TL,TR,BL,BR je 8 Byte, dann 4 Attribute ----
tile_sky:
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0
                db 068h,068h,068h,068h
tile_cloud_l:
                db 0,0,0,3,7,00Fh,03Fh,07Fh
                db 0,0,0,0E0h,0F0h,0F8h,0F8h,0FFh
                db 0FFh,0FFh,0FFh,07Fh,03Fh,0,0,0
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 06Fh,06Fh,06Fh,06Fh
tile_cloud_r:
                db 0,0,0,7,00Fh,01Fh,01Fh,0FFh
                db 0,0,0,0C0h,0E0h,0F0h,0FCh,0FEh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0,0,0
                db 0FFh,0FFh,0FFh,0FEh,0FCh,0,0,0
                db 06Fh,06Fh,06Fh,06Fh
tile_hill_l:
                db 0,0,0,0,0,0,0,0
                db 1,3,7,00Fh,01Fh,03Fh,07Fh,0FFh
                db 1,3,7,00Fh,01Fh,03Fh,07Fh,0FFh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 06Ch,06Ch,06Ch,06Ch
tile_hill_m:
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 06Ch,06Ch,06Ch,06Ch
tile_hill_r:
                db 080h,0C0h,0E0h,0F0h,0F8h,0FCh,0FEh,0FFh
                db 0,0,0,0,0,0,0,0
                db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
                db 080h,0C0h,0E0h,0F0h,0F8h,0FCh,0FEh,0FFh
                db 06Ch,06Ch,06Ch,06Ch
tile_grass:
                db 0,0,020h,0,2,0ADh,089h,0
                db 0,0,084h,0,010h,06Bh,024h,0
                db 044h,2,082h,010h,021h,2,040h,8
                db 022h,8,020h,010h,0,022h,8,040h
                db 020h,020h,016h,016h
tile_dirt:
                db 0,0,0,2,011h,038h,040h,081h
                db 010h,2,040h,0DAh,0,2,0,0
                db 090h,031h,010h,044h,050h,0,0,080h
                db 019h,8,040h,0,010h,080h,040h,8
                db 016h,016h,016h,016h
tile_stone:
                db 0FFh,080h,080h,080h,080h,080h,080h,080h
                db 0FFh,0,0,0,0,0,0,0
                db 0FFh,0,0,0,0,0,0,0
                db 0FFh,080h,080h,080h,080h,080h,080h,080h
                db 00Fh,00Fh,00Fh,00Fh
tile_brick:
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 0FFh,080h,080h,080h,0FFh,8,8,8
                db 017h,017h,017h,017h
tile_chest:
                db 0FFh,080h,080h,080h,080h,0FFh,080h,081h
                db 0FFh,1,1,1,1,0FFh,1,081h
                db 083h,083h,081h,080h,080h,080h,080h,0FFh
                db 0C1h,0C1h,081h,1,1,1,1,0FFh
                db 070h,070h,070h,070h
tile_barrel:
                db 07Fh,092h,0FFh,0FFh,092h,092h,092h,092h
                db 0FEh,049h,0FFh,0FFh,049h,049h,049h,049h
                db 092h,092h,092h,092h,0FFh,0FFh,092h,07Fh
                db 049h,049h,049h,049h,0FFh,0FFh,049h,0FEh
                db 016h,016h,016h,016h
tile_coin:
                db 0,0,3,7,00Fh,00Eh,00Eh,00Eh
                db 0,0,0C0h,0E0h,0F0h,070h,070h,070h
                db 00Eh,00Eh,00Eh,00Fh,7,3,0,0
                db 070h,070h,070h,0F0h,0E0h,0C0h,0,0
                db 06Eh,06Eh,06Eh,06Eh
tile_hydrant:
                db 0,0,7,00Fh,00Fh,7,00Fh,03Fh
                db 0,0,0E0h,0F0h,0F0h,0E0h,0F0h,0FCh
                db 03Fh,0EFh,0EFh,03Fh,00Fh,00Fh,03Fh,03Fh
                db 0FCh,0F7h,0F7h,0FCh,0F0h,0F0h,0FCh,0FCh
                db 06Ah,06Ah,06Ah,06Ah

; ---- Sprite-Zeiger ----
spr_ptr:
                dw spr_ff_a
                dw spr_ff_b
                dw spr_ff2_a
                dw spr_ff2_b
                dw spr_ffl_head
                dw spr_ffl_body_a
                dw spr_ffl_body_b
                dw spr_flame_a
                dw spr_flame_b
                dw spr_smoke_a
                dw spr_smoke_b

; ---- Sprites: je Zelle 8x (Maske,Pixel), dann 4 Ink-Werte ----
spr_ff_a:
                db 0F8h,7,0F0h,00Fh,0E0h,01Fh,080h,07Fh,0F0h,00Fh,0F0h,00Fh,0F0h,00Fh,0F8h,7
                db 01Fh,0E0h,00Fh,0F0h,7,0F8h,1,0FEh,00Fh,0F0h,08Fh,070h,00Fh,0F0h,01Fh,0E0h
                db 0E0h,01Fh,0C0h,03Fh,0C8h,037h,0C8h,037h,0F0h,00Fh,0F9h,6,0F9h,6,0F1h,00Eh
                db 7,0F8h,2,0FDh,012h,0EDh,012h,0EDh,00Fh,0F0h,09Fh,060h,09Fh,060h,08Fh,070h
                db 6,6,2,2
spr_ff_b:
                db 0F8h,7,0F0h,00Fh,0E0h,01Fh,080h,07Fh,0F0h,00Fh,0F0h,00Fh,0F0h,00Fh,0F8h,7
                db 01Fh,0E0h,00Fh,0F0h,7,0F8h,1,0FEh,00Fh,0F0h,08Fh,070h,00Fh,0F0h,01Fh,0E0h
                db 0E0h,01Fh,0C0h,03Fh,0C8h,037h,0C8h,037h,0F0h,00Fh,0FCh,3,0F9h,6,0F1h,00Eh
                db 7,0F8h,2,0FDh,012h,0EDh,012h,0EDh,00Fh,0F0h,03Fh,0C0h,08Fh,070h,0E3h,01Ch
                db 6,6,2,2
spr_ff2_a:
                db 0F8h,7,0F0h,00Fh,0E0h,01Fh,080h,07Fh,0F0h,00Fh,0F0h,00Fh,0F0h,00Fh,0F8h,7
                db 01Fh,0E0h,00Fh,0F0h,7,0F8h,1,0FEh,00Fh,0F0h,08Fh,070h,00Fh,0F0h,01Fh,0E0h
                db 0E0h,01Fh,0C0h,03Fh,0C8h,037h,0C8h,037h,0F0h,00Fh,0F9h,6,0F9h,6,0F1h,00Eh
                db 7,0F8h,2,0FDh,012h,0EDh,012h,0EDh,00Fh,0F0h,09Fh,060h,09Fh,060h,08Fh,070h
                db 6,6,1,1
spr_ff2_b:
                db 0F8h,7,0F0h,00Fh,0E0h,01Fh,080h,07Fh,0F0h,00Fh,0F0h,00Fh,0F0h,00Fh,0F8h,7
                db 01Fh,0E0h,00Fh,0F0h,7,0F8h,1,0FEh,00Fh,0F0h,08Fh,070h,00Fh,0F0h,01Fh,0E0h
                db 0E0h,01Fh,0C0h,03Fh,0C8h,037h,0C8h,037h,0F0h,00Fh,0FCh,3,0F9h,6,0F1h,00Eh
                db 7,0F8h,2,0FDh,012h,0EDh,012h,0EDh,00Fh,0F0h,03Fh,0C0h,08Fh,070h,0E3h,01Ch
                db 6,6,1,1
spr_ffl_head:
                db 0F8h,7,0F0h,00Fh,0E0h,01Fh,0C0h,03Fh,080h,07Fh,0F0h,00Fh,0F0h,00Fh,0F0h,00Fh
                db 01Fh,0E0h,00Fh,0F0h,7,0F8h,3,0FCh,1,0FEh,00Fh,0F0h,08Fh,070h,00Fh,0F0h
                db 0F8h,7,0E0h,01Fh,0C0h,03Fh,080h,07Fh,088h,077h,088h,077h,088h,077h,088h,077h
                db 01Fh,0E0h,7,0F8h,3,0FCh,1,0FEh,011h,0EEh,011h,0EEh,011h,0EEh,011h,0EEh
                db 6,6,2,2
spr_ffl_body_a:
                db 088h,077h,088h,077h,088h,077h,0C8h,037h,0F0h,00Fh,0F5h,00Ah,0F0h,00Fh,0F0h,00Fh
                db 011h,0EEh,011h,0EEh,011h,0EEh,013h,0ECh,00Fh,0F0h,0AFh,050h,00Fh,0F0h,00Fh,0F0h
                db 0F1h,00Eh,0F1h,00Eh,0F1h,00Eh,0F1h,00Eh,0F1h,00Eh,0E1h,01Eh,0C1h,03Eh,0C3h,03Ch
                db 08Fh,070h,08Fh,070h,08Fh,070h,08Fh,070h,08Fh,070h,087h,078h,083h,07Ch,0C3h,03Ch
                db 2,2,1,1
spr_ffl_body_b:
                db 088h,077h,088h,077h,088h,077h,0C8h,037h,0F0h,00Fh,0F5h,00Ah,0F0h,00Fh,0F0h,00Fh
                db 011h,0EEh,011h,0EEh,011h,0EEh,013h,0ECh,00Fh,0F0h,0AFh,050h,00Fh,0F0h,00Fh,0F0h
                db 0F0h,00Fh,0F8h,7,0F9h,6,0F1h,00Eh,0F3h,00Ch,0E3h,01Ch,0C7h,038h,0CFh,030h
                db 01Fh,0E0h,03Fh,0C0h,01Fh,0E0h,08Fh,070h,0CFh,030h,0C7h,038h,0E3h,01Ch,0F3h,00Ch
                db 2,2,1,1
spr_flame_a:
                db 0FFh,0,0FEh,1,0FEh,1,0FCh,3,0FCh,3,0F8h,7,0F8h,7,0F0h,00Fh
                db 0FFh,0,0FFh,0,07Fh,080h,07Fh,080h,03Fh,0C0h,02Fh,0D0h,017h,0E8h,00Bh,0F4h
                db 0F0h,00Fh,0E3h,01Ch,0E3h,01Ch,0C0h,03Fh,0C0h,03Fh,0C0h,03Fh,0E0h,01Fh,0F0h,00Fh
                db 7,0F8h,013h,0ECh,011h,0EEh,0,0FFh,0,0FFh,0,0FFh,1,0FEh,00Fh,0F0h
                db 2,2,6,6
spr_flame_b:
                db 0FFh,0,0FFh,0,0FEh,1,0FEh,1,0FCh,3,0B8h,047h,0B0h,04Fh,0F0h,00Fh
                db 0FFh,0,07Fh,080h,03Fh,0C0h,03Fh,0C0h,01Fh,0E0h,01Fh,0E0h,01Fh,0E0h,00Bh,0F4h
                db 0F0h,00Fh,0E3h,01Ch,0E3h,01Ch,0C0h,03Fh,0C0h,03Fh,0C0h,03Fh,0E0h,01Fh,0F0h,00Fh
                db 7,0F8h,013h,0ECh,011h,0EEh,0,0FFh,0,0FFh,0,0FFh,1,0FEh,00Fh,0F0h
                db 2,2,6,6
spr_smoke_a:
                db 0FFh,0,0FFh,0,0FFh,0,0F8h,7,0E0h,01Fh,0C0h,03Fh,080h,07Fh,08Ch,073h
                db 0FFh,0,0FFh,0,0FFh,0,01Fh,0E0h,7,0F8h,3,0FCh,1,0FEh,031h,0CEh
                db 08Ch,073h,080h,07Fh,0C0h,03Fh,0E0h,01Fh,0F9h,6,0FDh,2,0FFh,0,0FFh,0
                db 031h,0CEh,1,0FEh,3,0FCh,7,0F8h,09Fh,060h,0BFh,040h,0FFh,0,0FFh,0
                db 0,0,0,0
spr_smoke_b:
                db 0FFh,0,0FFh,0,0FFh,0,0F0h,00Fh,0E0h,01Fh,0C0h,03Fh,080h,07Fh,08Ch,073h
                db 0FFh,0,0FFh,0,0FFh,0,03Fh,0C0h,7,0F8h,3,0FCh,1,0FEh,031h,0CEh
                db 08Ch,073h,080h,07Fh,0C0h,03Fh,0E0h,01Fh,0F3h,00Ch,0FBh,4,0FFh,0,0FFh,0
                db 031h,0CEh,1,0FEh,3,0FCh,7,0F8h,0CFh,030h,0DFh,020h,0FFh,0,0FFh,0
                db 0,0,0,0

; ---- Karte 16x12 ----
level_map:
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,1,2,0,0,0,0,0,0,0,0,0,1,2,0
                db 0,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,00Ch,00Ch,00Ch,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,0,0,0,9,00Ah,9,00Ah,9,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,00Bh,8
                db 0,0,0,0,0,0,0,0,0,0,3,4,5,00Dh,00Bh,8
                db 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6
                db 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7

; ---- Objekte: Sprite, cx, cy (Zeichenzellen), Ende = 0FFh ----
objects:
                db 0,0,012h
                db 1,2,012h
                db 4,6,010h
                db 5,6,012h
                db 4,8,010h
                db 6,8,012h
                db 7,00Ch,012h
                db 8,00Eh,012h
                db 2,010h,012h
                db 9,016h,00Ah
                db 00Ah,018h,00Ah
                db 0FFh


                end start
