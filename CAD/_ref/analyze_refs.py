#!/usr/bin/env python3
"""Measure densest bodies in CAD STEP refs (reference only)."""
from __future__ import annotations

import collections
import re
from pathlib import Path

RX = re.compile(
    r"CARTESIAN_POINT\s*\(\s*[^,]*,\s*\(\s*([-+eE0-9.]+)\s*,\s*([-+eE0-9.]+)\s*,\s*([-+eE0-9.]+)\s*\)\s*\)"
)


def parse_points(path: Path, lim: float = 800.0, max_pts: int = 250_000):
    pts = []
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "CARTESIAN_POINT" not in line:
                continue
            for m in RX.finditer(line):
                x, y, z = map(float, m.groups())
                if abs(x) > lim or abs(y) > lim or abs(z) > lim:
                    continue
                pts.append((x, y, z))
                if len(pts) >= max_pts:
                    return pts
    return pts


def aabb(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    zs = [p[2] for p in pts]
    return (
        min(xs),
        max(xs),
        min(ys),
        max(ys),
        min(zs),
        max(zs),
        max(xs) - min(xs),
        max(ys) - min(ys),
        max(zs) - min(zs),
        len(pts),
    )


def densest(pts, cell=6.0, keep=10):
    bins = collections.Counter()
    for x, y, z in pts:
        bins[(int(x // cell), int(y // cell), int(z // cell))] += 1
    top = {c for c, _ in bins.most_common(keep)}
    exp = set(top)
    for cx, cy, cz in list(top):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    exp.add((cx + dx, cy + dy, cz + dz))
    sel = [p for p in pts if (int(p[0] // cell), int(p[1] // cell), int(p[2] // cell)) in exp]
    return sel, bins.most_common(6)


def dec_x2(s: str) -> str:
    def repl(m):
        h = m.group(1)
        return "".join(chr(int(h[i : i + 4], 16)) for i in range(0, len(h), 4))

    return re.sub(r"\\X2\\([0-9A-Fa-f]+)\\X0\\", repl, s)


def products(path: Path, limit_bytes: int = 800_000):
    text = path.read_bytes()[:limit_bytes].decode("utf-8", "ignore")
    out = []
    for a, b in re.findall(r"PRODUCT\('([^']*)','([^']*)'", text):
        out.append((dec_x2(a), dec_x2(b)))
    return out


def main():
    root = Path(__file__).resolve().parent
    files = {
        "FAZ": root / "faz" / "FAZ-D16-1-NA-SP.stp",
        "Doepke": root / "doepke" / "09112601HD - 300.stp",
        "RVF": root / "rvf" / "RVF-02.STEP",
        "MRP": root / "mrp" / "MRP-6.stp",
        "RVO": root / "rvo" / "RVO-1M.stp",
    }
    for label, path in files.items():
        pts = parse_points(path)
        if not pts:
            print(label, "NO POINTS")
            continue
        a = aabb(pts)
        print(
            f"{label} full: {a[6]:.1f}x{a[7]:.1f}x{a[8]:.1f} n={a[9]} "
            f"X[{a[0]:.1f}..{a[1]:.1f}] Y[{a[2]:.1f}..{a[3]:.1f}] Z[{a[4]:.1f}..{a[5]:.1f}]"
        )
        sel, top = densest(pts)
        b = aabb(sel)
        spans = sorted([(b[6], "X"), (b[7], "Y"), (b[8], "Z")])
        print(
            f"  densest: {b[6]:.1f}x{b[7]:.1f}x{b[8]:.1f} n={b[9]} spans={spans} top={top[:3]}"
        )
        for a0, b0 in products(path)[:25]:
            if a0 or b0:
                print(f"  PROD {a0!r} | {b0!r}")

    # Doepke without bus bar
    pts = parse_points(files["Doepke"], lim=600)
    for name, filt in [
        ("|Y|<80", lambda p: abs(p[1]) < 80),
        ("|Y|<40", lambda p: abs(p[1]) < 40),
        ("Z>20 body", lambda p: p[2] > 20),
    ]:
        body = [p for p in pts if filt(p)]
        if body:
            b = aabb(body)
            print(f"Doepke {name}: {b[6]:.1f}x{b[7]:.1f}x{b[8]:.1f} n={len(body)}")

    # MRP/RVO: isolate DIN brick by finding subset with one axis ~17.5/22.5/35/45
    for label in ("MRP", "RVO"):
        pts = parse_points(files[label], lim=200, max_pts=200_000)
        # slide window on densest axis - try all permutations of cropped box
        best = None
        for cell in (4.0, 5.0, 8.0):
            sel, _ = densest(pts, cell=cell, keep=20)
            b = aabb(sel)
            spans = sorted([b[6], b[7], b[8]])
            score = abs(spans[0] - 22.5) + abs(spans[1] - 90)  # prefer DIN-ish
            if best is None or score < best[0]:
                best = (score, cell, b, spans)
        print(f"{label} best DIN-ish densest cell={best[1]} spans={best[3]} box={best[2][6]:.1f}x{best[2][7]:.1f}x{best[2][8]:.1f}")


if __name__ == "__main__":
    main()
