# -*- coding: utf-8 -*-
"""УГО клапана «И» из Проект1_Схема1.dxf → data/symbols/and_ugo.json.

Штрихи DXF 1:1 (scale + flip Y). Tips: 1/2 уже ±30; порт 3 удлиняем до −30 (SCH_GRID).
opening 0.5 = центр (оба прохода), 0/1 = сдвиг гантели к седлу.
"""
from __future__ import annotations

import json
from pathlib import Path

DXF = Path(r"C:\Users\RomanSanych\Documents\Проект1_Схема1.dxf")
OUT = Path(r"D:\mech-sim\data\symbols\and_ugo.json")
TIP = 30.0
OX = 12.0
OY = -8.0
SCALE = TIP / 12.0  # 2.5


def read_polys(path: Path) -> list[list[list[float]]]:
	lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
	i = 0

	def next_pair():
		nonlocal i
		if i + 1 >= len(lines):
			return None
		c, v = lines[i].strip(), lines[i + 1].strip()
		i += 2
		return c, v

	out: list[list[list[float]]] = []
	while True:
		p = next_pair()
		if p is None:
			break
		if p[0] != "0" or p[1].upper() != "LWPOLYLINE":
			continue
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
			if closed and pts[0] != pts[-1]:
				pts = pts + [pts[0][:]]
			out.append(pts)
	return out


def xf(x: float, y: float) -> list[float]:
	return [round((x - OX) * SCALE, 4), round(-(y - OY) * SCALE, 4)]


def main() -> None:
	raw = read_polys(DXF)
	strokes: list[list[list[float]]] = []
	for pts in raw:
		strokes.append([xf(p[0], p[1]) for p in pts])
	# Порт 3: в DXF хвост до −20 → удлинить до −30 на сетке.
	strokes.append([[0.0, -20.0], [0.0, -30.0]])
	data = {
		"source": "Проект1_Схема1.dxf — клапан И (штрихи 1:1)",
		"note": "DXF scale=2.5 flipY; tips ±30 / −30. opening 0.5=центр гантели, 0→седло1, 1→седло2.",
		"scale": SCALE,
		"port_1": [-TIP, 0.0],
		"port_2": [TIP, 0.0],
		"port_3": [0.0, -TIP],
		"spool_travel": 10.0,
		"strokes": strokes,
	}
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print("wrote", OUT, "strokes", len(strokes))


if __name__ == "__main__":
	main()
