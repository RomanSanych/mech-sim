# -*- coding: utf-8 -*-
"""Import quick-exhaust UGO from AS DXF → data/symbols/quick_exhaust_ugo.json.

Layout (after center/scale/flipY): port1 left, port2 up (−Y), port3 right (+ muffler).
Tips on SCH_GRID (±30 / 0).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DXF = ROOT / "out" / "quick_exhaust_schema.dxf"
OUT = Path(__file__).resolve().parents[2].parent / "data" / "symbols" / "quick_exhaust_ugo.json"
TIP = 30.0
SCALE = 2.5
OX = 12.0
OY = -8.0


def parse_block(path: Path) -> list[list[list[float]]]:
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
			while True:
				q = np()
				if q is None:
					break
				if q[0] == "0":
					unread()
					break
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
				ents.append([[float(a), float(b)] for a, b in pts])
	return ents


def xf(x: float, y: float) -> list[float]:
	return [round((x - OX) * SCALE, 4), round(-(y - OY) * SCALE, 4)]


def is_ball_poly(pts: list[list[float]]) -> bool:
	if len(pts) < 20:
		return False
	xs = [p[0] for p in pts]
	ys = [p[1] for p in pts]
	cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
	w, h = max(xs) - min(xs), max(ys) - min(ys)
	if w < 0.4 or abs(w - h) > max(w, h) * 0.35:
		return False
	if abs(cy - OY) > 2.0:
		return False
	return abs(cx - OX) < 6.5


def is_muffler_seg(pts: list[list[float]]) -> bool:
	"""Правый глушитель DXF: x≳16, y≳−6 (сырые координаты)."""
	if not pts:
		return False
	xs = [p[0] for p in pts]
	ys = [p[1] for p in pts]
	mx = sum(xs) / len(xs)
	my = sum(ys) / len(ys)
	# Корпус-прямоугольник [4,-4]…[20,-12] — не глушитель.
	if my < -3.5:
		return False
	return mx >= 15.5


def stroke_key(pts: list[list[float]]) -> tuple:
	r = [(round(p[0], 3), round(p[1], 3)) for p in pts]
	if len(r) == 2 and r[0] > r[1]:
		r = [r[1], r[0]]
	return tuple(r)


def extend_tips(pts: list[list[float]]) -> list[list[float]]:
	if len(pts) != 2:
		return pts
	(x0, y0), (x1, y1) = pts
	# Порт 1 слева.
	if abs(y0) < 1.0 and abs(y1) < 1.0 and min(x0, x1) < -18.0:
		lo, hi = (pts[0], pts[1]) if x0 < x1 else (pts[1], pts[0])
		return [[-TIP, 0.0], [hi[0], hi[1]]]
	# Порт 3 справа (до корпуса; глушитель отдельно).
	if abs(y0) < 1.0 and abs(y1) < 1.0 and max(x0, x1) > 18.0:
		lo, hi = (pts[0], pts[1]) if x0 > x1 else (pts[1], pts[0])
		return [[TIP, 0.0], [hi[0], hi[1]]]
	# Порт 2 вверх (−Y).
	if abs(x0) < 1.0 and abs(x1) < 1.0 and min(y0, y1) < -8.0:
		lo, hi = (pts[0], pts[1]) if y0 < y1 else (pts[1], pts[0])
		return [[0.0, -TIP], [hi[0], hi[1]]]
	return pts


def circle_poly(cx: float, cy: float, r: float, n: int = 48) -> list:
	return [
		[
			round(cx + r * math.cos(2 * math.pi * i / n), 4),
			round(cy + r * math.sin(2 * math.pi * i / n), 4),
		]
		for i in range(n + 1)
	]


def build(ents: list) -> dict:
	ball_r_dxf = 1.0
	for e in ents:
		if is_ball_poly(e):
			xs = [p[0] for p in e]
			ys = [p[1] for p in e]
			cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
			ball_r_dxf = max(
				ball_r_dxf,
				sum(math.hypot(x - cx, y - cy) for x, y in zip(xs, ys)) / len(xs),
			)
	ball_r = ball_r_dxf * SCALE

	strokes: list = []
	muffler_strokes: list = []
	seen: set = set()
	seen_m: set = set()
	for e in ents:
		if is_ball_poly(e):
			continue
		raw = e
		pts = [xf(p[0], p[1]) for p in raw]
		if raw[0] == raw[-1] and len(pts) > 2:
			pass
		is_muff = is_muffler_seg(raw)
		# Диагональ к глушителю тоже в muffler.
		if len(raw) == 2:
			(ax, ay), (bx, by) = raw
			if max(ax, bx) > 15.0 and max(ay, by) > -1.0 and min(ay, by) > -5.0:
				is_muff = True
		pts = extend_tips(pts) if not is_muff else pts
		pts = [[round(p[0], 3), round(p[1], 3)] for p in pts]
		key = stroke_key(pts)
		if is_muff:
			if key in seen_m:
				continue
			seen_m.add(key)
			muffler_strokes.append(pts)
		else:
			if key in seen:
				continue
			seen.add(key)
			strokes.append(pts)

	seat_tip = abs(18.42 - OX) * SCALE
	travel = max(seat_tip - ball_r, ball_r * 0.5)

	return {
		"source": "Проект1_Схема1.dxf — быстрый выхлоп",
		"note": "1=вход (−X), 2=ПЦ (−Y), 3=выхлоп (+X). opening 1=питание (тарелка к выхлопу), 0=выхлоп (тарелка к входу). muffler_strokes — глушитель на 3.",
		"scale": SCALE,
		"port_1": [-TIP, 0.0],
		"port_2": [0.0, -TIP],
		"port_3": [TIP, 0.0],
		"ball_r": round(ball_r, 4),
		"ball_cx0": 0.0,
		"ball_cy0": 0.0,
		"seat_tip": round(seat_tip, 3),
		"ball_travel": round(travel, 3),
		"strokes": strokes,
		"muffler_strokes": muffler_strokes,
		"circle": circle_poly(0.0, 0.0, ball_r),
	}


def main() -> None:
	ents = parse_block(DXF)
	if not ents:
		raise SystemExit("no block ents in %s" % DXF)
	data = build(ents)
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print("wrote", OUT, "strokes", len(data["strokes"]), "muffler", len(data["muffler_strokes"]))


if __name__ == "__main__":
	main()
