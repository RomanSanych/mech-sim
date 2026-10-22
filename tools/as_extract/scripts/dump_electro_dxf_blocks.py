#!/usr/bin/env python3
"""Dump normalized line geometry from electro UGO DXF blocks."""
from __future__ import annotations

import json
import math
import sys
from collections import Counter
from pathlib import Path

DXF = Path(r"D:\mech-sim\out\electro_refs\user\ugo_electrical_schemes.dxf")
OUT = Path(r"D:\mech-sim\out\electro_refs\user\dxf_block_geom.json")


def parse_blocks(lines: list[str]) -> dict[str, list[dict]]:
	i = 0
	blocks: dict[str, list[dict]] = {}
	in_blocks = False
	cur_name: str | None = None
	cur_ents: list[dict] = []
	cur: dict | None = None
	while i < len(lines) - 1:
		code = lines[i].strip()
		val = lines[i + 1].rstrip("\r")
		i += 2
		if code == "2" and val == "BLOCKS":
			in_blocks = True
			continue
		if not in_blocks:
			continue
		if code == "0" and val == "ENDSEC":
			if cur_name is not None:
				if cur:
					cur_ents.append(cur)
				blocks[cur_name] = cur_ents
			break
		if code == "0" and val == "BLOCK":
			if cur_name is not None:
				if cur:
					cur_ents.append(cur)
				blocks[cur_name] = cur_ents
			cur_name = None
			cur_ents = []
			cur = {"type": "BLOCK"}
			continue
		if code == "0" and val == "ENDBLK":
			if cur:
				cur_ents.append(cur)
				cur = None
			if cur_name is not None:
				blocks[cur_name] = cur_ents
			cur_name = None
			cur_ents = []
			continue
		if code == "0":
			if cur:
				cur_ents.append(cur)
			cur = {"type": val}
			continue
		if cur is None:
			continue
		cur.setdefault(code, []).append(val)
		if cur.get("type") == "BLOCK" and code == "2" and cur_name is None:
			cur_name = val
	return blocks


def flatten(blocks: dict, name: str, ox: float = 0.0, oy: float = 0.0, depth: int = 0, seen: set | None = None) -> list:
	if seen is None:
		seen = set()
	if name in seen or depth > 6:
		return []
	seen = set(seen)
	seen.add(name)
	out: list = []
	for e in blocks.get(name, []):
		t = e["type"]
		if t == "LINE":
			x1 = float(e["10"][0]) + ox
			y1 = float(e["20"][0]) + oy
			x2 = float(e["11"][0]) + ox
			y2 = float(e["21"][0]) + oy
			out.append(("L", x1, y1, x2, y2))
		elif t == "CIRCLE":
			out.append(("C", float(e["10"][0]) + ox, float(e["20"][0]) + oy, float(e["40"][0])))
		elif t == "ARC":
			out.append(
				(
					"A",
					float(e["10"][0]) + ox,
					float(e["20"][0]) + oy,
					float(e["40"][0]),
					float(e.get("50", ["0"])[0]),
					float(e.get("51", ["0"])[0]),
				)
			)
		elif t == "INSERT":
			bn = e.get("2", [""])[0]
			ix = float(e.get("10", ["0"])[0]) + ox
			iy = float(e.get("20", ["0"])[0]) + oy
			sx = float(e.get("41", ["1"])[0])
			sy = float(e.get("42", [str(sx)])[0])
			kids = flatten(blocks, bn, ix, iy, depth + 1, seen)
			if abs(sx - 1.0) > 1e-9 or abs(sy - 1.0) > 1e-9:
				nk = []
				for k in kids:
					if k[0] == "L":
						nk.append(
							(
								"L",
								ix + (k[1] - ix) * sx,
								iy + (k[2] - iy) * sy,
								ix + (k[3] - ix) * sx,
								iy + (k[4] - iy) * sy,
							)
						)
					else:
						nk.append(k)
				kids = nk
			out.extend(kids)
	return out


def normalize(prims: list) -> tuple[list, dict | None]:
	xs: list[float] = []
	ys: list[float] = []
	for p in prims:
		if p[0] == "L":
			xs += [p[1], p[3]]
			ys += [p[2], p[4]]
		elif p[0] in ("C", "A"):
			xs.append(p[1])
			ys.append(p[2])
	if not xs:
		return prims, None
	yc: Counter = Counter()
	for p in prims:
		if p[0] == "L" and abs(p[2] - p[4]) < 0.25:
			yc[round((p[2] + p[4]) / 2.0, 3)] += abs(p[3] - p[1])
	wire_y = yc.most_common(1)[0][0] if yc else float(min(ys))
	cx = (min(xs) + max(xs)) / 2.0
	out = []
	for p in prims:
		if p[0] == "L":
			out.append(("L", p[1] - cx, p[2] - wire_y, p[3] - cx, p[4] - wire_y))
		elif p[0] == "C":
			out.append(("C", p[1] - cx, p[2] - wire_y, p[3]))
		elif p[0] == "A":
			out.append(("A", p[1] - cx, p[2] - wire_y, p[3], p[4], p[5]))
	meta = {
		"cx": cx,
		"wire_y": wire_y,
		"w": max(xs) - min(xs),
		"h": max(ys) - min(ys),
		"xmin": min(xs) - cx,
		"xmax": max(xs) - cx,
		"ymin": min(ys) - wire_y,
		"ymax": max(ys) - wire_y,
	}
	return out, meta


def main() -> int:
	lines = DXF.read_text(encoding="utf-8").splitlines()
	blocks = parse_blocks(lines)
	interesting = [
		"U578",
		"U580",
		"U579",
		"U584",
		"U1332",
		"U1333",
		"U1334",
		"U1335",
		"U768",
		"U769",
		"U771",
		"U773",
		"U487",
		"U486",
		"U489",
		"U491",
		"U492",
		"U459",
		"U598",
		"U499",
		"U500",
		"U643",
		"U644",
		"U670",
		"U803",
		"U1346",
		"U462",
		"U463",
		"U605",
		"U606",
		"U607",
		"U616",
		"U617",
		"U640",
		"U641",
		"U629",
	]
	report: dict = {}
	for name in interesting:
		prims = flatten(blocks, name)
		norm, meta = normalize(prims)
		print(f"==== {name} meta={meta} n={len(norm)}")
		lines_out = []
		for pr in sorted(norm, key=lambda p: (p[0], p[2], p[1])):
			if pr[0] == "L":
				msg = (
					f"  L ({pr[1]:7.3f},{pr[2]:7.3f})->({pr[3]:7.3f},{pr[4]:7.3f}) "
					f"len={math.hypot(pr[3] - pr[1], pr[4] - pr[2]):.3f}"
				)
				print(msg)
				lines_out.append(
					{
						"a": [round(pr[1], 4), round(pr[2], 4)],
						"b": [round(pr[3], 4), round(pr[4], 4)],
					}
				)
			else:
				print(" ", pr)
		report[name] = {"meta": meta, "lines": lines_out, "raw": [list(x) for x in norm]}
	OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
	print("wrote", OUT)
	return 0


if __name__ == "__main__":
	sys.exit(main())
