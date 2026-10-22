# -*- coding: utf-8 -*-
from pathlib import Path

DXF = Path(r"C:\Users\RomanSanych\Documents\Проект1_Схема1.dxf")
lines = DXF.read_text(encoding="utf-8", errors="replace").splitlines()
i = 0


def np():
	global i
	if i + 1 >= len(lines):
		return None
	c, v = lines[i].strip(), lines[i + 1].strip()
	i += 2
	return c, v


ents = []
while True:
	p2 = np()
	if p2 is None:
		break
	if p2[0] != "0":
		continue
	ent = p2[1].upper()
	if ent == "LWPOLYLINE":
		pts = []
		closed = False
		px = None
		while True:
			q = np()
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
			ents.append({"t": "poly", "c": closed, "pts": pts})
	elif ent == "LINE":
		x1 = y1 = x2 = y2 = None
		while True:
			q = np()
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
			ents.append({"t": "line", "c": False, "pts": [[x1, y1], [x2, y2]]})

for idx, e in enumerate(ents):
	pts = e["pts"]
	xs = [a for a, _b in pts]
	ys = [b for _a, b in pts]
	print("--- %d %s closed=%s n=%d x=[%.2f,%.2f] y=[%.2f,%.2f]" % (
		idx, e["t"], e["c"], len(pts), min(xs), max(xs), min(ys), max(ys),
	))
	if len(pts) <= 14:
		for pt in pts:
			print("   ", [round(pt[0], 3), round(pt[1], 3)])
	else:
		print("   first", [round(pts[0][0], 3), round(pts[0][1], 3)],
			"mid", [round(pts[len(pts) // 2][0], 3), round(pts[len(pts) // 2][1], 3)],
			"last", [round(pts[-1][0], 3), round(pts[-1][1], 3)])
