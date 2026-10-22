# -*- coding: utf-8 -*-
"""Import pressure-relief UGO from AS DXF → data/symbols/relief_ugo.json.

AutomationStudioLT3 → dashed (выпуск от штуцера в камеру / контур привода).
Tips on SCH_GRID (±30).
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DXF = ROOT / "out" / "relief_valve_schema.dxf"
OUT = Path(__file__).resolve().parents[2].parent / "data" / "symbols" / "relief_ugo.json"
TIP = 30.0
SCALE = 2.5
OX = 8.0
OY = -8.0


def parse_block(path: Path) -> list[tuple[str, list[list[float]]]]:
	lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
	i = 0
	n = len(lines)

	def np():
		nonlocal i
		if i >= n - 1:
			return None
		c = lines[i].strip()
		v = lines[i + 1].strip()
		i += 2
		return c, v

	def unread():
		nonlocal i
		i -= 2

	ents: list = []
	cur: str | None = None
	while True:
		p = np()
		if p is None:
			break
		c, v = p
		if c == "0" and v.upper() == "BLOCK":
			name = None
			while True:
				q = np()
				if q is None:
					break
				if q[0] == "0":
					unread()
					break
				if q[0] == "2":
					name = q[1]
			cur = name
			ents = []
			continue
		if c == "0" and v.upper() == "ENDBLK":
			if cur and not cur.startswith("*"):
				return ents
			cur = None
			continue
		if cur is not None and c == "0" and v.upper() == "LWPOLYLINE":
			pts: list[list[float]] = []
			closed = False
			px = None
			ltype = "Continuous"
			while True:
				q = np()
				if q is None:
					break
				if q[0] == "0":
					unread()
					break
				if q[0] == "6":
					ltype = q[1]
				if q[0] == "70" and (int(float(q[1])) & 1):
					closed = True
				if q[0] == "10":
					px = float(q[1])
				if q[0] == "20" and px is not None:
					pts.append([px, float(q[1])])
					px = None
			if len(pts) >= 2:
				if closed and pts[0] != pts[-1]:
					pts = pts + [pts[0][:]]
				ents.append((ltype, [[float(a), float(b)] for a, b in pts]))
	return ents


def xf(x: float, y: float) -> list[float]:
	return [round((x - OX) * SCALE, 4), round(-(y - OY) * SCALE, 4)]


def stroke_key(pts: list[list[float]]) -> tuple:
	r = [(round(p[0], 3), round(p[1], 3)) for p in pts]
	if len(r) == 2 and r[0] > r[1]:
		r = [r[1], r[0]]
	return tuple(r)


def extend_tips(pts: list[list[float]]) -> list[list[float]]:
	if len(pts) != 2:
		return pts
	(x0, y0), (x1, y1) = pts
	if abs(y0) < 1.5 and abs(y1) < 1.5 and min(x0, x1) < -8.0:
		lo, hi = (pts[0], pts[1]) if x0 < x1 else (pts[1], pts[0])
		return [[-TIP, 0.0], [hi[0], 0.0]]
	if abs(y0) < 1.5 and abs(y1) < 1.5 and max(x0, x1) > 8.0:
		lo, hi = (pts[0], pts[1]) if x0 > x1 else (pts[1], pts[0])
		return [[TIP, 0.0], [hi[0], 0.0]]
	return pts


def is_dashed(ltype: str) -> bool:
	u = ltype.upper()
	return "LT3" in u or "DASH" in u or "HIDDEN" in u


def build(ents: list) -> dict:
	strokes: list = []
	dashed: list = []
	seen: set = set()
	seen_d: set = set()
	for ltype, e in ents:
		pts = [xf(p[0], p[1]) for p in e]
		pts = extend_tips(pts) if not is_dashed(ltype) else pts
		pts = [[round(p[0], 3), round(p[1], 3)] for p in pts]
		key = stroke_key(pts)
		if is_dashed(ltype):
			if key in seen_d:
				continue
			seen_d.add(key)
			dashed.append(pts)
		else:
			if key in seen:
				continue
			seen.add(key)
			strokes.append(pts)
	return {
		"source": "Проект1_Схема1.dxf — предохранительный клапан",
		"note": "1=вход (−X), 2=сброс (+X). dashed=AutomationStudioLT3 (выпуск штуцер→камера / контур привода).",
		"scale": SCALE,
		"port_1": [-TIP, 0.0],
		"port_2": [TIP, 0.0],
		"strokes": strokes,
		"dashed": dashed,
	}


def main() -> None:
	ents = parse_block(DXF)
	if not ents:
		raise SystemExit("no block ents in %s" % DXF)
	data = build(ents)
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print("wrote", OUT, "strokes", len(data["strokes"]), "dashed", len(data["dashed"]))


if __name__ == "__main__":
	main()
