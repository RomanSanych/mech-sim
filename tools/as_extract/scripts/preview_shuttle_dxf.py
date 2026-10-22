# -*- coding: utf-8 -*-
from pathlib import Path
import importlib.util

spec = importlib.util.spec_from_file_location(
	"imp", Path(__file__).with_name("import_shuttle_dxf.py")
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ents = m.read_entities(m.DXF)
fig, ax = plt.subplots(figsize=(12, 4))
for e in ents:
	if e["type"] == "circle":
		ax.add_patch(plt.Circle((e["cx"], e["cy"]), e["r"], fill=False, color="red", lw=1.5))
		ax.text(e["cx"], e["cy"] + 1.2, f"r={e['r']}", ha="center", fontsize=8, color="red")
	else:
		xs = [p[0] for p in e["pts"]]
		ys = [p[1] for p in e["pts"]]
		ax.plot(xs, ys, color="black", lw=0.9)
ax.set_aspect("equal")
ax.grid(True, alpha=0.3)
ax.axvline(14.5, color="blue", ls="--", alpha=0.5)
ax.invert_yaxis()
out = Path(__file__).resolve().parents[1] / "out" / "strokes" / "shuttle_dxf_preview.png"
fig.savefig(out, dpi=160, bbox_inches="tight")
print("wrote", out)
