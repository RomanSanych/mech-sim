# -*- coding: utf-8 -*-
"""
УГО клапана «ИЛИ» из Проект1_Схема1.dxf — один символ на листе.

Повторяем штрихи DXF 1:1 (scale + flip Y). Не рисуем «от себя».
Без пружины = те же штрихи минус зигзаг пружины; шарик один (анимация).
Tips: горизонталь DXF уже → ±30; порт 3 удлиняем до −30 (сетка SCH_GRID).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

DXF = Path(r"C:\Users\RomanSanych\Documents\Проект1_Схема1.dxf")
OUT_PLAIN = Path(r"D:\mech-sim\data\symbols\shuttle_ugo.json")
OUT_SPRING = Path(r"D:\mech-sim\data\symbols\shuttle_spring_ugo.json")
TIP = 30.0

# Центр символа в DXF: середина tips 0…24, ось канала y=-8.
OX = 12.0
OY = -8.0
SCALE = TIP / 12.0  # 2.5 — tips 0/24 → ±30 без выдуманного масштаба


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
		elif ent == "CIRCLE":
			cx = cy = r = None
			while True:
				q = next_pair()
				if q is None:
					break
				c, v = q
				if c == "0":
					i -= 2
					break
				if c == "10":
					cx = float(v)
				elif c == "20":
					cy = float(v)
				elif c == "40":
					r = float(v)
			if None not in (cx, cy, r):
				ents.append({"type": "circle", "cx": cx, "cy": cy, "r": r})
	return ents


def seg_len(a: list[float], b: list[float]) -> float:
	return math.hypot(b[0] - a[0], b[1] - a[1])


def is_ball_poly(pts: list[list[float]]) -> bool:
	"""Полилиния-окружность шарика (~центр 12,-8 или у седла)."""
	if len(pts) < 20:
		return False
	xs = [p[0] for p in pts]
	ys = [p[1] for p in pts]
	cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
	w, h = max(xs) - min(xs), max(ys) - min(ys)
	if w < 0.4 or abs(w - h) > max(w, h) * 0.35:
		return False
	# Шарики в DXF: центр (12,-8) и седло справа (17,-8).
	if abs(cy - OY) > 2.0:
		return False
	return abs(cx - OX) < 6.5


def is_seat_seg(pts: list[list[float]]) -> bool:
	"""V-сёдла DXF: слева tip≈5.58→7.58, справа 16.42→18.42 — не пружина."""
	if len(pts) != 2:
		return False
	(x0, y0), (x1, y1) = pts
	xs, xe = sorted([x0, x1])
	my = 0.5 * (y0 + y1)
	if abs(my - OY) > 3.2:
		return False
	if 5.3 <= xs <= 5.9 and 7.3 <= xe <= 7.9:
		return True
	if 16.1 <= xs <= 16.7 and 18.1 <= xe <= 18.7:
		return True
	return False


def is_spring_seg(pts: list[list[float]]) -> bool:
	"""Только звенья зигзага пружины между сёдлами — не шток порта 3 и не V-сёдла."""
	if len(pts) != 2:
		return False
	if is_seat_seg(pts):
		return False
	(x0, y0), (x1, y1) = pts
	mx = 0.5 * (x0 + x1)
	my = 0.5 * (y0 + y1)
	dx, dy = abs(x1 - x0), abs(y1 - y0)
	L = seg_len(pts[0], pts[1])
	# Шток порта 3 — вертикаль на x=12 — никогда не пружина.
	if abs(mx - OX) < 0.35 and dx < 0.35:
		return False
	# Пружина: короткие наклонные строго между рукавами сёдел.
	if not (6.6 <= mx <= 16.2):
		return False
	if abs(my - OY) > 3.2:
		return False
	if L < 0.25 or L > 4.5:
		return False
	# Нужен заметный dy (зигзаг); чистый горизонт — канал, не пружина.
	if dy < 0.4:
		return False
	return True


def xf(x: float, y: float) -> list[float]:
	return [round((x - OX) * SCALE, 4), round(-(y - OY) * SCALE, 4)]


def circle_poly(cx: float, cy: float, r: float, n: int = 48) -> list:
	return [
		[
			round(cx + r * math.cos(2 * math.pi * i / n), 4),
			round(cy + r * math.sin(2 * math.pi * i / n), 4),
		]
		for i in range(n + 1)
	]


def stroke_key(pts: list[list[float]]) -> tuple:
	"""Канонический ключ для дедупа (порядок точек не важен для 2-point)."""
	r = [(round(p[0], 3), round(p[1], 3)) for p in pts]
	if len(r) == 2 and r[0] > r[1]:
		r = [r[1], r[0]]
	return tuple(r)


def extend_port3_tip(pts: list[list[float]]) -> list[list[float]]:
	"""Только наружный шток порта 3: удлинить tip до −TIP (на сетке)."""
	if len(pts) != 2:
		return pts
	(x0, y0), (x1, y1) = pts
	if abs(x0) > 1.0 or abs(x1) > 1.0:
		return pts
	if abs(y0 - y1) < 1.0:
		return pts
	# Наружный шток: один конец у корпуса (|y|≈10), другой дальше вверх листа (−Y).
	lo, hi = (pts[0], pts[1]) if y0 < y1 else (pts[1], pts[0])
	# После flip: порт 3 в −Y; наружный tip — меньший y.
	if lo[1] > -12.0:
		return pts
	return [[0.0, -TIP], [hi[0], hi[1]]]


def build(ents: list, include_spring: bool) -> dict:
	# Радиус шарика: CIRCLE r=1 у седла / полилиния w≈2 — не мелкий CIRCLE r=0.5.
	ball_r_dxf = 0.0
	for e in ents:
		if e["type"] == "circle" and abs(float(e["cy"]) - OY) < 1.5:
			if float(e["r"]) >= 0.9:
				ball_r_dxf = max(ball_r_dxf, float(e["r"]))
		elif e["type"] == "poly" and is_ball_poly(e["pts"]):
			xs = [p[0] for p in e["pts"]]
			ys = [p[1] for p in e["pts"]]
			cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
			ball_r_dxf = max(
				ball_r_dxf,
				sum(math.hypot(x - cx, y - cy) for x, y in zip(xs, ys)) / len(xs),
			)
	if ball_r_dxf < 0.5:
		ball_r_dxf = 1.0
	ball_r = ball_r_dxf * SCALE

	strokes: list[list[list[float]]] = []
	seen: set[tuple] = set()
	for e in ents:
		if e["type"] == "circle":
			continue
		if is_ball_poly(e["pts"]):
			continue
		if (not include_spring) and is_spring_seg(e["pts"]):
			continue
		pts = [xf(p[0], p[1]) for p in e["pts"]]
		if e.get("closed") and pts and pts[0] != pts[-1]:
			pts.append(pts[0][:])
		pts = extend_port3_tip(pts)
		pts = [[round(p[0], 3), round(p[1], 3)] for p in pts]
		key = stroke_key(pts)
		if key in seen:
			continue
		seen.add(key)
		strokes.append(pts)

	# Седла DXF: tip ≈5.58 и ≈18.42 → ±(18.42-12)*scale.
	# Центр шарика = tip ± r — касается V, не пересекает.
	seat_tip = abs(18.42 - OX) * SCALE
	travel = max(seat_tip - ball_r, ball_r * 0.5)

	return {
		"source": "Проект1_Схема1.dxf — клапан ИЛИ (штрихи 1:1)",
		"note": "DXF scale=2.5 flipY; tips ±30; opening 0→седло1, 1→седло2. Шарик касается tip седла.",
		"scale": round(SCALE, 6),
		"has_spring": include_spring,
		"port_1": [-TIP, 0.0],
		"port_2": [TIP, 0.0],
		"port_3": [0.0, -TIP],
		"ball_r": round(ball_r, 4),
		"ball_cx0": 0.0,
		"ball_cy0": 0.0,
		"seat_tip": round(seat_tip, 3),
		"ball_travel": round(travel, 3),
		"strokes": strokes,
		"circle": circle_poly(0.0, 0.0, ball_r),
	}


def main() -> None:
	ents = read_entities(DXF)
	print("ents", len(ents))
	spring_n = sum(1 for e in ents if e["type"] == "poly" and is_spring_seg(e["pts"]))
	ball_n = sum(1 for e in ents if e["type"] == "poly" and is_ball_poly(e["pts"]))
	print("spring_segs", spring_n, "ball_polys", ball_n)
	plain = build(ents, include_spring=False)
	spring = build(ents, include_spring=True)
	OUT_PLAIN.write_text(json.dumps(plain, ensure_ascii=False, indent=2), encoding="utf-8")
	OUT_SPRING.write_text(json.dumps(spring, ensure_ascii=False, indent=2), encoding="utf-8")
	xs = [p[0] for st in plain["strokes"] for p in st]
	ys = [p[1] for st in plain["strokes"] for p in st]
	print(
		"plain n",
		len(plain["strokes"]),
		"scale",
		plain["scale"],
		"ball_r",
		plain["ball_r"],
		"travel",
		plain["ball_travel"],
		"bb",
		min(xs),
		min(ys),
		max(xs),
		max(ys),
	)
	print("spring n", len(spring["strokes"]))


if __name__ == "__main__":
	main()
