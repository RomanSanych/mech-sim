# -*- coding: utf-8 -*-
"""УГО датчика давления (пневмочасть) из Проект1_Схема1.dxf → pressure_tx_ugo.json.

Tips на SCH_GRID: tip P = (−30, 0). Scale/flipY как у реле давления B1.
"""
from __future__ import annotations

import json
from pathlib import Path

DXF = Path(r"C:\Users\RomanSanych\Documents\Проект1_Схема1.dxf")
OUT = Path(__file__).resolve().parents[2].parent / "data" / "symbols" / "pressure_tx_ugo.json"
TIP = 30.0
SCALE = 3.75
# Tip в DXF: (0, −4) → (−30, 0)
OX = 0.0 + TIP / SCALE  # 8.0
OY = -4.0


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
	# Гарантируем tip P на −30 (хвост от тела ≈ −15).
	has_tip = False
	for st in strokes:
		if len(st) >= 2:
			for pt in st:
				if abs(pt[0] + TIP) < 0.2 and abs(pt[1]) < 0.2:
					has_tip = True
					break
	if not has_tip:
		strokes.append([[-15.0, 0.0], [-TIP, 0.0]])
	xs = [p[0] for st in strokes for p in st]
	ys = [p[1] for st in strokes for p in st]
	data = {
		"source": "Проект1_Схема1.dxf — датчик давления (пневмочасть)",
		"note": "DXF scale=3.75 flipY; tip P = (−30,0) на SCH_GRID",
		"scale": SCALE,
		"port_p": [-TIP, 0.0],
		"bbox": [min(xs), min(ys), max(xs), max(ys)],
		"strokes": strokes,
	}
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
	print("wrote", OUT, "strokes", len(strokes), "bbox", data["bbox"])


if __name__ == "__main__":
	main()
