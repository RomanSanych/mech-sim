# -*- coding: utf-8 -*-
"""УГО поворотного ПЦ из Проект1_Схема1.dxf (один чистый символ) → rotary_cylinder_ugo.json.

CAD: диаметр y=-11, x=5..17; полукруг вверх к y=-5; вал x=10..12, y≈-5..0.
Центр диаметра (11,-11). Порты — вертикальные хвосты под диаметром (ISO/AS);
tips на SCH_GRID (±10, +20), нормаль вниз.
Штрихи вала — отдельно в shaft_strokes (анимация ±45° от вертикали).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

DXF = Path(r"C:\Users\RomanSanych\Documents\Проект1_Схема1.dxf")
OUT = Path(r"D:\mech-sim\data\symbols\rotary_cylinder_ugo.json")
SCH_GRID = 10.0
# Tips портов: x ±1×grid, y +2×grid (удлинение CAD ±7.5→±10, stub 10→20).
PORT_TIP_X = SCH_GRID
PORT_TIP_Y = SCH_GRID * 2.0
OX = 11.0
OY = -11.0
R_CAD = 6.0
SCALE = 15.0 / R_CAD  # полукруг r≈15 на схеме


def read_entities(path: Path) -> list[dict]:
	lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
	i = 0

	def next_pair():
		nonlocal i
		if i + 1 >= len(lines):
			return None
		c, v = lines[i].strip(), lines[i + 1].strip()
		i += 2
		return c, v

	ents: list[dict] = []
	while True:
		p = next_pair()
		if p is None:
			break
		if p[0] != "0":
			continue
		ent = p[1].upper()
		if ent == "LWPOLYLINE":
			pts: list[list[float]] = []
			closed = False
			px = None
			while True:
				q = next_pair()
				if q is None:
					break
				c, v = q
				if c == "0":
					i -= 2
					break
				if c == "70":
					closed = (int(float(v)) & 1) != 0
				elif c == "10":
					px = float(v)
				elif c == "20" and px is not None:
					pts.append([px, float(v)])
					px = None
			if len(pts) >= 2:
				ents.append({"type": "poly", "closed": closed, "pts": pts})
		elif ent == "LINE":
			x1 = y1 = x2 = y2 = None
			while True:
				q = next_pair()
				if q is None:
					break
				c, v = q
				if c == "0":
					i -= 2
					break
				if c == "10":
					x1 = float(v)
				elif c == "20":
					y1 = float(v)
				elif c == "11":
					x2 = float(v)
				elif c == "21":
					y2 = float(v)
			if x1 is not None:
				ents.append({"type": "poly", "closed": False, "pts": [[x1, y1], [x2, y2]]})
	return ents


def xf(x: float, y: float) -> list[float]:
	return [round((x - OX) * SCALE, 4), round(-(y - OY) * SCALE, 4)]


def xf_pts(pts: list[list[float]]) -> list[list[float]]:
	return [xf(p[0], p[1]) for p in pts]


def is_shaft(pts: list[list[float]]) -> bool:
	"""Прямоугольник вала: x≈10..12, y от ≈-5 до 0 (над полукругом)."""
	xs = [p[0] for p in pts]
	ys = [p[1] for p in pts]
	mx = 0.5 * (min(xs) + max(xs))
	if not (9.5 <= mx <= 12.5):
		return False
	# Верх вала у y≈0; низ не ниже вершины полукруга сильно.
	if max(ys) < -0.5:
		return False
	if min(ys) < -6.0:
		return False
	return True


def is_port_stub_vertical(pts: list[list[float]]) -> bool:
	"""Вертикальные хвосты под диаметром (CAD y < −11) — это tips портов a/b."""
	if len(pts) != 2:
		return False
	(x0, y0), (x1, y1) = pts
	if abs(x0 - x1) > 0.2:
		return False
	return max(y0, y1) <= -10.5 and min(y0, y1) < -12.0


def _port_stub_on_grid(cad_pts: list[list[float]]) -> list[list[float]]:
	"""CAD-хвост → sch: x на ±PORT_TIP_X, от диаметра (y=0) до PORT_TIP_Y."""
	xs = [p[0] for p in cad_pts]
	mx = 0.5 * (min(xs) + max(xs))
	sign = -1.0 if mx < OX else 1.0
	x = sign * PORT_TIP_X
	return [[x, 0.0], [x, PORT_TIP_Y]]


def main() -> None:
	ents = read_entities(DXF)
	strokes: list[list[list[float]]] = []
	shaft: list[list[list[float]]] = []
	port_stubs: list[list[list[float]]] = []
	for e in ents:
		pts = e["pts"]
		if is_port_stub_vertical(pts):
			port_stubs.append(_port_stub_on_grid(pts))
			continue
		w = xf_pts(pts)
		if e.get("closed") and w and w[0] != w[-1]:
			w = w + [w[0][:]]
		if is_shaft(pts):
			shaft.append(w)
		else:
			strokes.append(w)

	circle_r = round(R_CAD * SCALE, 4)
	# Вертикальные tips a/b под диаметром (сетка ±10, y=+20). Не горизонталь по диаметру.
	if not port_stubs:
		port_stubs = [
			[[-PORT_TIP_X, 0.0], [-PORT_TIP_X, PORT_TIP_Y]],
			[[PORT_TIP_X, 0.0], [PORT_TIP_X, PORT_TIP_Y]],
		]
	for stub in port_stubs:
		strokes.append(stub)

	# Замкнуть низ вала (в DXF открыт в полукруг) — три стороны уже есть.
	if shaft:
		# Добавить нижнюю перемычку по минимуму y штрихов вала.
		ys_bot = []
		xs_l = []
		xs_r = []
		for s in shaft:
			for p in s:
				ys_bot.append(p[1])
				xs_l.append(p[0])
				xs_r.append(p[0])
		y_bot = max(ys_bot)  # у вала «низ» ближе к 0 на схеме? после xf: CAD y=-5 → sch≈-15
		# После xf: CAD y↑ → sch y↓ (отриц.). Низ вала (ближе к диаметру) = max(sch y) среди вала.
		y_near = max(ys_bot)
		x_lo = min(xs_l)
		x_hi = max(xs_r)
		# Нижняя кромка уже может отсутствовать — добавить.
		has_bot = any(
			len(s) == 2 and abs(s[0][1] - y_near) < 0.3 and abs(s[1][1] - y_near) < 0.3
			for s in shaft
		)
		if not has_bot:
			shaft.append([[x_lo, y_near], [x_hi, y_near]])

	# tip a = левый (x<0), tip b = правый
	pa = [-PORT_TIP_X, PORT_TIP_Y]
	pb = [PORT_TIP_X, PORT_TIP_Y]
	for stub in port_stubs:
		x0 = stub[0][0]
		if x0 < 0.0:
			pa = [stub[-1][0], stub[-1][1]]
		else:
			pb = [stub[-1][0], stub[-1][1]]
	out = {
		"source": "Проект1_Схема1.dxf — поворотный пневмоцилиндр (один символ)",
		"note": "Вал (shaft_strokes) вращается вокруг (0,0). Порты вниз под диаметром, tips на SCH_GRID. УГО: ±45° от вертикали по ходу.",
		"scale": SCALE,
		"circle_r": circle_r,
		"pivot": [0.0, 0.0],
		"port_a": pa,
		"port_b": pb,
		"port_normal": [0.0, 1.0],
		"shaft_rest_deg": 0.0,
		"shaft_in_deg": 45.0,
		"shaft_out_deg": -45.0,
		"strokes": strokes,
		"shaft_strokes": shaft,
	}
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
	print("wrote", OUT)
	print("strokes", len(strokes), "shaft", len(shaft), "r", circle_r, "scale", SCALE)
	for i, s in enumerate(shaft):
		print(" shaft", i, s)
	xs = [p[0] for s in strokes for p in s]
	ys = [p[1] for s in strokes for p in s]
	print(" strokes bbox x=[%.1f,%.1f] y=[%.1f,%.1f]" % (min(xs), max(xs), min(ys), max(ys)))


if __name__ == "__main__":
	main()
