#!/usr/bin/env python3
"""Hoehlen-Textkarten (levels/*.cave) -> Assembler-Daten (ersetzt ;@@LEVELS@@ im Quelltext).

Aufruf: gen_levels.py <quelle.asm> <ziel.asm> <levels-verzeichnis> [vorschau-verzeichnis]
Pruefungen: Format, Rockford/Ausgang genau einmal, Stahlrand, Ausgang erreichbar,
genug Diamanten. Mit Vorschau-Verzeichnis entsteht je Hoehle ein PNG der ganzen Hoehle.
"""
import glob, os, re, sys
from collections import deque

W, H = 40, 22
# Zeichen -> Kachel-ID
CHARS = {
    ' ': 0, '.': 1, 'W': 2, '#': 3, 'o': 4, '*': 5, 'R': 6, 'X': 15,
    'F': 16, 'S': 24, 'M': 40, 'A': 43, 'G': 44, '~': 45, 'B': 48,
}
DEFAULTS = dict(need=10, time=150, magic=160, amoeba=40)


def parse(path):
    head, rows, in_map = {}, [], False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if in_map:
            if line.strip() == "" and len(rows) >= H:
                continue
            rows.append(line)
        elif line.strip().lower() == "map:":
            in_map = True
        else:
            line = line.split(";")[0].strip()
            if not line:
                continue
            k, _, v = line.partition(":")
            head[k.strip().lower()] = v.strip()
    return head, rows


def check(name, head, rows):
    errs = []
    for k in head:
        if k not in ("name", "need", "time", "magic", "amoeba", "extra"):
            errs.append(f"unbekannter Kopfwert '{k}'")
    if len(rows) != H:
        errs.append(f"{len(rows)} Zeilen statt {H}")
    for y, r in enumerate(rows):
        if len(r) != W:
            errs.append(f"Zeile {y}: {len(r)} Zeichen statt {W}")
        for x, c in enumerate(r):
            if c not in CHARS:
                errs.append(f"Zeile {y} Spalte {x}: unbekanntes Zeichen {c!r}")
    if errs:
        return errs
    flat = "".join(rows)
    for c, label in (("R", "Rockford"), ("X", "Ausgang")):
        if flat.count(c) != 1:
            errs.append(f"{label} ('{c}') muss genau einmal vorkommen, gefunden: {flat.count(c)}")
    for x in range(W):
        if rows[0][x] != '#' or rows[H - 1][x] != '#':
            errs.append("Stahlrand oben/unten unvollstaendig")
            break
    for y in range(H):
        if rows[y][0] != '#' or rows[y][W - 1] != '#':
            errs.append("Stahlrand links/rechts unvollstaendig")
            break
    return errs


def reachable(rows):
    """Grobe Pruefung: Rockford kommt ueber begehbare Felder (leer, Erde, Diamant, Stein = schiebbar,
    Gegner = auch) zum Ausgang. Ziegel, Stahl, Lava, Bomben und Zauberwand sperren."""
    flat = "".join(rows)
    start = flat.index('R')
    ok = set(" .*oXFSAG")
    ok.add('o')
    seen = {start}
    q = deque([start])
    dia = 0
    while q:
        i = q.popleft()
        if flat[i] == '*':
            dia += 1
        for o in (-1, 1, -W, W):
            j = i + o
            if 0 <= j < len(flat) and j not in seen and flat[j] in ok:
                seen.add(j)
                q.append(j)
    return flat.index('X') in seen, dia


def rle(tiles):
    out, i = [], 0
    while i < len(tiles):
        j = i
        while j < len(tiles) and tiles[j] == tiles[i] and j - i < 255:
            j += 1
        out.append((j - i, tiles[i]))
        i = j
    return out


def build(levels_dir, preview_dir=None):
    files = sorted(glob.glob(os.path.join(levels_dir, "*.cave")))
    if not files:
        raise SystemExit("keine .cave-Dateien in " + levels_dir)
    blocks, table, summary = [], [], []
    for n, f in enumerate(files, 1):
        name = os.path.basename(f)
        head, rows = parse(f)
        errs = check(name, head, rows)
        if errs:
            raise SystemExit(f"{name}: " + "; ".join(errs[:8]))
        h = {k: int(head.get(k, v)) for k, v in DEFAULTS.items()}
        extra = int(head.get("extra", 0))      # Diamanten, die erst im Spiel entstehen (Sprengung, Zauberwand, Amoebe)
        for k in h:
            if not 0 < h[k] < 256:
                raise SystemExit(f"{name}: {k} muss zwischen 1 und 255 liegen")
        flat = "".join(rows)
        r = flat.index('R'); x_ = flat.index('X')
        ok, dia = reachable(rows)
        if not ok:
            raise SystemExit(f"{name}: Ausgang ist von Rockford aus nicht erreichbar")
        if dia + extra < h["need"] + 2:
            raise SystemExit(f"{name}: nur {dia}+{extra} Diamanten, Quote ist {h['need']} (mind. 2 Reserve)")
        tiles = [CHARS[c] for c in flat]
        runs = rle(tiles)
        label = f"lvl_{n:02d}"
        table.append(label)
        lines = [f"{label}:                                 ; {head.get('name', name)}",
                 f"        db      {h['need']},{h['time']},{h['magic']},{h['amoeba']},{r % W},{r // W},{x_ % W},{x_ // W}"]
        for i in range(0, len(runs), 8):
            lines.append("        db      " + ",".join(f"{c},{t}" for c, t in runs[i:i + 8]))
        lines.append("        db      0")
        blocks.append("\n".join(lines))
        size = 8 + 2 * len(runs) + 1
        summary.append(f"  {n:2d} {head.get('name', name):<20} Quote {h['need']:2d} von {dia:2d}+{extra} Diamanten, {size} Bytes ({len(runs)} Laeufe)")
        if preview_dir:
            os.makedirs(preview_dir, exist_ok=True)
            preview(rows, os.path.join(preview_dir, os.path.splitext(name)[0] + ".png"))
    text = f"LEVEL_COUNT     equ     {len(files)}\nlevel_table:\n"
    text += "".join(f"        dw      {l}\n" for l in table) + "\n" + "\n\n".join(blocks) + "\n"
    return text, summary


def preview(rows, path):
    """Vorschau: eine Kachel = 12x12 Pixel, einfache Farben (nicht die Spielgrafik)."""
    from PIL import Image, ImageDraw
    col = {' ': (0, 0, 0), '.': (170, 60, 20), 'W': (200, 60, 40), '#': (40, 80, 200), 'o': (210, 210, 210),
           '*': (255, 255, 255), 'R': (255, 230, 0), 'X': (0, 220, 0), 'F': (255, 160, 0), 'S': (0, 220, 220),
           'M': (0, 200, 200), 'A': (0, 220, 0), 'G': (255, 120, 120), '~': (255, 90, 0), 'B': (200, 0, 200)}
    S = 12
    im = Image.new("RGB", (W * S, H * S))
    d = ImageDraw.Draw(im)
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            d.rectangle([x * S, y * S, x * S + S - 2, y * S + S - 2], fill=col[c])
            if c == '*':
                d.polygon([(x * S + 5, y * S + 1), (x * S + 10, y * S + 5), (x * S + 5, y * S + 10), (x * S, y * S + 5)], fill=(90, 200, 255))
            if c == 'o':
                d.ellipse([x * S + 1, y * S + 1, x * S + 9, y * S + 9], fill=(235, 235, 235))
    im.save(path)


def main(src, dst, levels_dir, preview_dir=None):
    text, summary = build(levels_dir, preview_dir)
    s = open(src, encoding="utf-8").read()
    assert ";@@LEVELS@@" in s, "Marke ;@@LEVELS@@ fehlt"
    open(dst, "w", encoding="utf-8").write(s.replace(";@@LEVELS@@", text))
    print("Hoehlen:")
    print("\n".join(summary))


if __name__ == "__main__":
    main(*sys.argv[1:])
