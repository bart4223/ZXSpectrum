#!/usr/bin/env python3
"""Komplett-Build: Hoehlen + Kacheln einsetzen, pasmo aufrufen.
Aufruf (im Projektordner):  python3 tools/build.py
"""
import os, subprocess, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
sys.path.insert(0, os.path.join(root, "tools"))
import gen_levels, gen_tiles
gen_levels.main("boulderdash_src.asm", "build_tmp.asm", "levels", "levels/preview")
gen_tiles.main("build_tmp.asm", "boulderdash.asm")
os.remove("build_tmp.asm")
subprocess.run(["pasmo", "--tapbas", "boulderdash.asm", "boulderdash.tap", "boulderdash.sym"], check=True)
print("boulderdash.tap:", os.path.getsize("boulderdash.tap"), "Bytes")
