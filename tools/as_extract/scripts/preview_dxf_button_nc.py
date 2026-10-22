#!/usr/bin/env python3
"""Rasterize DXF U582 (NC button) for visual check."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dump_electro_dxf_blocks import DXF, flatten, normalize, parse_blocks  # type: ignore

OUT = Path(r"D:\mech-sim\out\electro_refs\user\ugo_button_nc_from_dxf_U582.png")


def main() -> int:
	blocks = parse_blocks(DXF.read_text(encoding="utf-8").splitlines())
	norm, meta = normalize(flatten(blocks, "U582"))
	assert meta
	# Flip Y for image (DXF Y-up → image Y-down), pad
	scale = 8.0
	pad = 20
	w = int(meta["w"] * scale) + pad * 2
	h = int(meta["h"] * scale) + pad * 2
	im = Image.new("RGB", (w, h), (230, 240, 248))
	dr = ImageDraw.Draw(im)
	# grid every 1 DXF unit
	ox = pad + (-meta["xmin"]) * scale
	oy = pad + meta["ymax"] * scale

	def X(x: float) -> float:
		return ox + x * scale

	def Y(y: float) -> float:
		return oy - y * scale

	# grid
	for gx in range(int(meta["xmin"]) - 1, int(meta["xmax"]) + 2):
		dr.line([(X(gx), 0), (X(gx), h)], fill=(200, 220, 235), width=1)
	for gy in range(int(meta["ymin"]) - 1, int(meta["ymax"]) + 2):
		dr.line([(0, Y(gy)), (w, Y(gy))], fill=(200, 220, 235), width=1)
	# wire
	dr.line([(0, Y(0)), (w, Y(0))], fill=(160, 190, 210), width=1)
	for p in norm:
		if p[0] == "L":
			dr.line([(X(p[1]), Y(p[2])), (X(p[3]), Y(p[4]))], fill=(20, 20, 20), width=2)
	im.save(OUT)
	print("wrote", OUT, "meta", meta)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
