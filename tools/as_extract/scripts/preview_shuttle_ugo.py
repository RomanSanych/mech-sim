# -*- coding: utf-8 -*-
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

s = json.loads(Path(r"D:\mech-sim\data\symbols\shuttle_ugo.json").read_text(encoding="utf-8"))
fig, ax = plt.subplots(figsize=(6, 6))
for st in s["strokes"]:
	xs = [p[0] for p in st]
	ys = [p[1] for p in st]
	ax.plot(xs, ys, color="black", lw=1.2)
r = float(s["ball_r"])
n = 48
xs = [r * math.cos(2 * math.pi * i / n) for i in range(n + 1)]
ys = [r * math.sin(2 * math.pi * i / n) for i in range(n + 1)]
ax.plot(xs, ys, color="red", lw=1.5)
for name, key in [("1", "port_1"), ("2", "port_2"), ("3", "port_3")]:
	p = s[key]
	ax.plot(p[0], p[1], "bo")
	ax.text(p[0], p[1], name)
ax.set_aspect("equal")
ax.grid(True, alpha=0.3)
ax.invert_yaxis()
ax.set_title(f"shuttle_ugo scale={s['scale']} ball_r={s['ball_r']} n={len(s['strokes'])}")
out = Path(r"D:\mech-sim\tools\as_extract\out\strokes\shuttle_ugo_preview.png")
fig.savefig(out, dpi=140, bbox_inches="tight")
print("wrote", out)
