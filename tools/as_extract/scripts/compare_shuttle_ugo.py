# -*- coding: utf-8 -*-
from pathlib import Path
import math
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_shuttle_dxf import read_entities, is_spring_seg, is_ball_poly, DXF

ents = read_entities(DXF)
fig, axes = plt.subplots(1, 2, figsize=(12, 5))
ax = axes[0]
for e in ents:
	if e["type"] == "circle":
		t = [i * 2 * math.pi / 48 for i in range(49)]
		ax.plot(
			[e["cx"] + e["r"] * math.cos(a) for a in t],
			[e["cy"] + e["r"] * math.sin(a) for a in t],
			"r-",
			lw=1.2,
		)
	else:
		xs = [p[0] for p in e["pts"]]
		ys = [p[1] for p in e["pts"]]
		if is_ball_poly(e["pts"]):
			c = "green"
		elif is_spring_seg(e["pts"]):
			c = "orange"
		else:
			c = "black"
		ax.plot(xs, ys, color=c, lw=1.0)
ax.set_aspect("equal")
ax.set_title("RAW DXF")
ax.grid(True, alpha=0.3)

s = json.loads(Path(r"D:\mech-sim\data\symbols\shuttle_ugo.json").read_text(encoding="utf-8"))
ax = axes[1]
for st in s["strokes"]:
	ax.plot([p[0] for p in st], [p[1] for p in st], "k-", lw=1.2)
r = float(s["ball_r"])
n = 48
ax.plot(
	[r * math.cos(2 * math.pi * i / n) for i in range(n + 1)],
	[r * math.sin(2 * math.pi * i / n) for i in range(n + 1)],
	"r-",
	lw=1.5,
)
for name, key in [("1", "port_1"), ("2", "port_2"), ("3", "port_3")]:
	p = s[key]
	ax.plot(p[0], p[1], "bo")
	ax.text(p[0], p[1], name)
ax.set_aspect("equal")
ax.invert_yaxis()
ax.set_title(f"plain n={len(s['strokes'])} ball_r={s['ball_r']}")
ax.grid(True, alpha=0.3)
out = Path(r"D:\mech-sim\tools\as_extract\out\strokes\shuttle_dxf_compare.png")
fig.savefig(out, dpi=140, bbox_inches="tight")
print("wrote", out)
