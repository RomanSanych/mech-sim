# -*- coding: utf-8 -*-
"""Import throttle+check UGO from AS DXF blocks → data/symbols JSON.

Left INSERT = fixed (no arrow), right = adjustable (arrow).
Blocks are vertical; bake CCW90 → port1 left / port2 right on y=0, tip ±30.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DXF = ROOT / "out" / "throttle_check_schema.dxf"
OUT_DIR = Path(__file__).resolve().parents[2].parent / "data" / "symbols"
TIP = 30.0


def parse_blocks(path: Path) -> dict[str, list[list[list[float]]]]:
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

	blocks: dict[str, list] = {}
	cur: str | None = None
	ents: list = []
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
				blocks[cur] = ents
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
	return blocks


def insert_order(path: Path) -> list[str]:
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

	ins: list[tuple[float, str]] = []
	while True:
		p = np()
		if p is None:
			break
		c, v = p
		if c == "0" and v.upper() == "INSERT":
			name = None
			ix = 0.0
			while True:
				q = np()
				if q is None:
					break
				if q[0] == "0":
					unread()
					break
				if q[0] == "2":
					name = q[1]
				if q[0] == "10":
					ix = float(q[1])
			if name:
				ins.append((ix, name))
	ins.sort(key=lambda t: t[0])
	return [name for _, name in ins]


def ccw90(pts: list[list[float]]) -> list[list[float]]:
	return [[-float(p[1]), float(p[0])] for p in pts]


def is_arrow_stroke(st: list[list[float]]) -> bool:
	"""Adjustable arrow: shaft from ~body toward left + small arrowhead poly."""
	xs = [p[0] for p in st]
	ys = [p[1] for p in st]
	# Local DXF before rotate: shaft (5.66,-10.29)→(0.5,-12.5)
	if len(st) == 2:
		ax, ay = st[0]
		bx, by = st[1]
		if min(ax, bx) < 2.0 and max(ax, bx) < 7.0 and -13.5 < min(ay, by) < -9.0:
			return True
	# Arrowhead cluster near (5.66,-10.29) — маленький, не рамка корпуса.
	if 4 <= len(st) <= 8:
		w = max(xs) - min(xs)
		h = max(ys) - min(ys)
		if w > 5.0 or h > 5.0:
			return False
		cx = sum(xs) / len(xs)
		cy = sum(ys) / len(ys)
		if 4.5 < cx < 8.0 and -12.0 < cy < -8.5:
			return True
	return False


def is_circle_stroke(st: list[list[float]]) -> bool:
	if len(st) < 24:
		return False
	xs = [p[0] for p in st]
	ys = [p[1] for p in st]
	w = max(xs) - min(xs)
	h = max(ys) - min(ys)
	return abs(w - h) < max(w, h) * 0.35 and 1.5 < w < 8.0


def bake(raw: list[list[list[float]]], adjustable: bool) -> dict:
	arrow_raw = [st for st in raw if is_arrow_stroke(st)]
	body_raw = [st for st in raw if not is_arrow_stroke(st)]
	# Port axis in DXF: vertical line x≈4, y∈[−22, 0]
	# After CCW90: x' = −y ∈ [0, 22], y' = 4 → horizontal at y'=4
	body = [ccw90(st) for st in body_raw]
	arrow = [ccw90(st) for st in arrow_raw]
	# Shift so port axis → y=0 (y' was ≈4)
	ys_port = [4.0]
	for st in body:
		for p in st:
			# Collect points that were on the main stem (original x≈4 → y'≈4)
			if abs(p[1] - 4.0) < 0.35:
				ys_port.append(p[1])
	y_axis = sum(ys_port) / len(ys_port)
	body = [[[p[0], p[1] - y_axis] for p in st] for st in body]
	arrow = [[[p[0], p[1] - y_axis] for p in st] for st in arrow]
	# Scale so port tips (orig y=0 and y=-22 → x'=0 and x'=22) → ±TIP
	# After shift, tips at x=0 and x=22 roughly; center at 11.
	xs_tip = []
	for st in body:
		for p in st:
			if abs(p[1]) < 0.4:
				xs_tip.append(p[0])
	if not xs_tip:
		xs_tip = [0.0, 22.0]
	x_lo, x_hi = min(xs_tip), max(xs_tip)
	cx = 0.5 * (x_lo + x_hi)
	half = max(abs(x_hi - cx), abs(x_lo - cx), 1.0)
	k = TIP / half

	def xf(st: list[list[float]]) -> list[list[float]]:
		return [[round((p[0] - cx) * k, 3), round(p[1] * k, 3)] for p in st]

	body = [xf(st) for st in body]
	arrow = [xf(st) for st in arrow]

	circle: list = []
	strokes: list = []
	for st in body:
		xs = [p[0] for p in st]
		ys = [p[1] for p in st]
		w = max(xs) - min(xs)
		h = max(ys) - min(ys)
		if len(st) >= 24 and abs(w - h) < max(w, h) * 0.4 and 1.5 < w < 14.0:
			circle = st
			continue
		strokes.append(st)

	cxb = cyb = rb = 0.0
	if circle:
		xs = [p[0] for p in circle]
		ys = [p[1] for p in circle]
		cxb = sum(xs) / len(xs)
		cyb = sum(ys) / len(ys)
		rb = sum(math.hypot(x - cxb, y - cyb) for x, y in zip(xs, ys)) / len(xs)

	# Ensure port stems reach exact tips on grid.
	strokes.append([[-TIP, 0.0], [-TIP + 0.001, 0.0]])  # marker only — strip below
	# Replace: add stem extensions if missing
	has_l = any(abs(p[0] + TIP) < 0.05 and abs(p[1]) < 0.05 for st in strokes for p in st)
	has_r = any(abs(p[0] - TIP) < 0.05 and abs(p[1]) < 0.05 for st in strokes for p in st)
	strokes = [st for st in strokes if not (len(st) == 2 and abs(st[0][0] + TIP) < 0.1 and abs(st[1][0] + TIP) < 0.1)]
	# Find nearest stem ends on axis and extend
	axis_pts = []
	for st in strokes:
		for p in st:
			if abs(p[1]) < 0.6:
				axis_pts.append(p[0])
	if axis_pts:
		inner_l = min(axis_pts)
		inner_r = max(axis_pts)
		if not has_l or inner_l > -TIP + 0.5:
			strokes.append([[-TIP, 0.0], [min(inner_l, -TIP + 8.0), 0.0]])
		if not has_r or inner_r < TIP - 0.5:
			strokes.append([[max(inner_r, TIP - 8.0), 0.0], [TIP, 0.0]])

	return {
		"source": "Проект1_Схема1.dxf block → CCW90, tip±30",
		"note": "port1 left / port2 right; check free 2→1; throttle meters 1→2",
		"adjustable": adjustable,
		"port_l": [-TIP, 0.0],
		"port_r": [TIP, 0.0],
		"ball_open_dx": round(3.5 * k / (TIP / 11.0), 3) if False else 3.5,
		"strokes": strokes,
		"arrow_strokes": arrow if adjustable else [],
		"circle": circle,
		"ball_cx": round(cxb, 3),
		"ball_cy": round(cyb, 3),
		"ball_r": round(rb, 3) if rb > 0.5 else 3.2,
	}


def main() -> None:
	blocks = parse_blocks(DXF)
	order = insert_order(DXF)
	if len(order) < 2:
		raise SystemExit(f"need 2 inserts, got {order}")
	left_name, right_name = order[0], order[1]
	fixed = bake(blocks[left_name], False)
	adj = bake(blocks[right_name], True)
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	p_fixed = OUT_DIR / "throttle_check_fixed_ugo.json"
	p_adj = OUT_DIR / "throttle_check_ugo.json"
	p_fixed.write_text(json.dumps(fixed, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
	p_adj.write_text(json.dumps(adj, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
	print("fixed", p_fixed, "strokes", len(fixed["strokes"]), "arrow", len(fixed["arrow_strokes"]), "ball", fixed["ball_cx"], fixed["ball_cy"], fixed["ball_r"])
	print("adj  ", p_adj, "strokes", len(adj["strokes"]), "arrow", len(adj["arrow_strokes"]), "ball", adj["ball_cx"], adj["ball_cy"], adj["ball_r"])


if __name__ == "__main__":
	main()
