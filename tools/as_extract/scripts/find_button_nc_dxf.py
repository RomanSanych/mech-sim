#!/usr/bin/env python3
"""Find DXF blocks that look like NC pushbutton (staple + downward NC contact)."""
from __future__ import annotations

import math
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dump_electro_dxf_blocks import DXF, flatten, normalize, parse_blocks  # type: ignore


def classify(norm: list) -> dict:
	horiz = []
	vert = []
	diag_up = []
	diag_dn = []
	for p in norm:
		if p[0] != "L":
			continue
		x1, y1, x2, y2 = p[1], p[2], p[3], p[4]
		dx, dy = x2 - x1, y2 - y1
		L = math.hypot(dx, dy)
		if L < 0.2:
			continue
		if abs(dy) <= 0.15 * L:
			horiz.append(p)
		elif abs(dx) <= 0.15 * L:
			vert.append(p)
		elif dy > 0:
			diag_up.append(p)
		else:
			diag_dn.append(p)
	# staple: horizontal near ymax with two short downward verts at ends
	ys = [p[2] for p in horiz] + [p[4] for p in horiz]
	ymax = max(ys) if ys else 0.0
	staple_bars = [p for p in horiz if max(p[2], p[4]) >= ymax - 0.3 and abs(p[3] - p[1]) >= 4.0]
	has_staple = False
	lip = 0.0
	bar_w = 0.0
	bar_y = 0.0
	if staple_bars:
		bar = max(staple_bars, key=lambda p: abs(p[3] - p[1]))
		bar_y = (bar[2] + bar[4]) / 2
		bx0, bx1 = sorted([bar[1], bar[3]])
		bar_w = bx1 - bx0
		lips = []
		for v in vert:
			vx = (v[1] + v[3]) / 2
			vy0, vy1 = sorted([v[2], v[4]])
			if (abs(vx - bx0) < 0.3 or abs(vx - bx1) < 0.3) and abs(vy1 - bar_y) < 0.3 and vy0 < bar_y:
				lips.append(bar_y - vy0)
		if lips:
			has_staple = True
			lip = sum(lips) / len(lips)
	# NC tab: vertical at ~+3 from wire down
	tabs = []
	for v in vert:
		vx = (v[1] + v[3]) / 2
		vy0, vy1 = sorted([v[2], v[4]])
		if 2.5 <= vx <= 4.5 and vy0 < -0.5 and vy1 >= -0.2:
			tabs.append(vy1 - vy0 if False else -vy0)
	return {
		"has_staple": has_staple,
		"bar_y": bar_y,
		"bar_w": bar_w,
		"lip": lip,
		"diag_up": len(diag_up),
		"diag_dn": len(diag_dn),
		"n_horiz": len(horiz),
		"n_vert": len(vert),
		"tabs": tabs,
	}


def main() -> int:
	blocks = parse_blocks(DXF.read_text(encoding="utf-8").splitlines())
	hits = []
	for name in blocks:
		if not name.startswith("U"):
			continue
		prims = flatten(blocks, name)
		if len(prims) < 4 or len(prims) > 30:
			continue
		norm, meta = normalize(prims)
		if not meta or meta["w"] > 25 or meta["h"] > 30:
			continue
		c = classify(norm)
		if c["has_staple"] and (c["diag_dn"] >= 1 or c["tabs"]):
			hits.append((name, meta, c, norm))
		elif c["has_staple"] and c["diag_up"] >= 1:
			hits.append((name, meta, {**c, "kind": "NO_BTN"}, norm))
	print("hits", len(hits))
	for name, meta, c, norm in sorted(hits, key=lambda x: (-x[1]["h"], x[0]))[:40]:
		print(f"\n==== {name} h={meta['h']:.2f} w={meta['w']:.2f} {c}")
		for p in sorted([p for p in norm if p[0] == "L"], key=lambda q: (q[2], q[1])):
			print(f"  L ({p[1]:7.3f},{p[2]:7.3f})->({p[3]:7.3f},{p[4]:7.3f})")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
