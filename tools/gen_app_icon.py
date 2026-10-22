"""MechSim app icon: official FSPO mark (white) on brand blue tile."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MARK = ROOT / "assets" / "brand" / "fspo_mark.png"
OUT_PNG = ROOT / "assets" / "brand" / "app_icon.png"
OUT_SVG = ROOT / "icon.svg"

BRAND = (0, 90, 170, 255)  # #005aaa
WHITE = (255, 255, 255, 255)


def mark_to_white(src: Image.Image) -> Image.Image:
	"""Blue/dark ink on light → white with soft alpha (keeps mark AA)."""
	img = src.convert("RGBA")
	px = img.load()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			ink = (1.0 - (r + g + b) / (3.0 * 255.0)) * (a / 255.0)
			# Lift mid-tones so the stroke stays solid; keep fringe for AA.
			coverage = max(0.0, min(1.0, (ink - 0.04) / 0.55))
			px[x, y] = (255, 255, 255, int(round(coverage * 255.0)))
	return img


def render_png(size: int = 512) -> None:
	mark = mark_to_white(Image.open(MARK))
	alpha = mark.split()[3]
	bbox = alpha.getbbox()
	if bbox is None:
		raise RuntimeError("FSPO mark has no ink")
	# Small pad so crop doesn't clip soft AA fringe.
	pad_px = 2
	x0 = max(0, bbox[0] - pad_px)
	y0 = max(0, bbox[1] - pad_px)
	x1 = min(mark.width, bbox[2] + pad_px)
	y1 = min(mark.height, bbox[3] + pad_px)
	mark = mark.crop((x0, y0, x1, y1))
	mw, mh = mark.size
	side = max(mw, mh)
	square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	square.paste(mark, ((side - mw) // 2, (side - mh) // 2), mark)

	# Upscale mark first (LANCZOS), then composite — cleaner than binary threshold.
	ss = 4
	big = size * ss
	canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
	draw = ImageDraw.Draw(canvas)
	pad = int(0.02 * big)
	radius = int(0.22 * big)
	draw.rounded_rectangle([pad, pad, big - 1 - pad, big - 1 - pad], radius=radius, fill=BRAND)

	inset = int(big * 0.14)
	target = big - 2 * inset
	gear = square.resize((target, target), Image.Resampling.LANCZOS)
	canvas.paste(gear, (inset, inset), gear)

	tile = canvas.resize((size, size), Image.Resampling.LANCZOS)
	bg = Image.new("RGBA", (size, size), BRAND)
	out = Image.alpha_composite(bg, tile).convert("RGB").convert("RGBA")
	OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
	out.save(OUT_PNG, "PNG")
	print("wrote", OUT_PNG, out.size)


def write_svg() -> None:
	"""Stroke-based FSPO-like mark (matches faculty silhouette; PNG is authoritative)."""
	# Geometry mirrors assets/brand/fspo_mark: 8 rounded teeth, split rim, dual inner arcs.
	svg = """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect width="128" height="128" rx="28" fill="#005aaa"/>
  <g fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" transform="translate(64 64)">
    <!-- Outer rim split at top/bottom (faculty mark) -->
    <path d="M -10,-34 A 34,34 0 0 0 -34,0 A 34,34 0 0 0 -10,34"/>
    <path d="M 10,34 A 34,34 0 0 0 34,0 A 34,34 0 0 0 10,-34"/>
    <!-- 8 teeth -->
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(45)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(90)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(135)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(180)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(225)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(270)"/>
    <path d="M -7,-34 L -7,-46 L 7,-46 L 7,-34" transform="rotate(315)"/>
    <!-- Inner facing arcs -->
    <path d="M -5,-17 A 18,18 0 1 0 -5,17"/>
    <path d="M 5,17 A 18,18 0 1 0 5,-17"/>
  </g>
</svg>
"""
	OUT_SVG.write_text(svg, encoding="utf-8")
	print("wrote", OUT_SVG)


if __name__ == "__main__":
	render_png()
	write_svg()
