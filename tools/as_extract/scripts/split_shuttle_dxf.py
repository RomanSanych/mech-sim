# -*- coding: utf-8 -*-
"""Split shuttle OR DXF import into left (no spring) / right (spring) UGO JSON."""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "out" / "strokes" / "shuttle_or_raw.json"
OUT_DIR = Path(__file__).resolve().parents[2].parent / "data" / "symbols"
TIP = 30.0  # SCH_GRID * 3


def mid(stroke: dict) -> tuple[float, float]:
    pts = stroke.get("polyline") or []
    if not pts:
        return 0.0, 0.0
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def bbox(strokes: list) -> tuple[float, float, float, float]:
    xs: list[float] = []
    ys: list[float] = []
    for s in strokes:
        for p in s.get("polyline") or []:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    return min(xs), min(ys), max(xs), max(ys)


def translate(strokes: list, dx: float, dy: float) -> list:
    out = []
    for s in strokes:
        pts = [[float(p[0]) + dx, float(p[1]) + dy] for p in (s.get("polyline") or [])]
        out.append({"part": str(s.get("part", "line")), "polyline": pts})
    return out


def scale(strokes: list, k: float) -> list:
    out = []
    for s in strokes:
        pts = [[float(p[0]) * k, float(p[1]) * k] for p in (s.get("polyline") or [])]
        out.append({"part": str(s.get("part", "line")), "polyline": pts})
    return out


def is_circle_like(stroke: dict) -> bool:
    pts = stroke.get("polyline") or []
    if len(pts) < 8:
        return False
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    if w < 0.5 or h < 0.5:
        return False
    return abs(w - h) < max(w, h) * 0.45


def circle_center_r(stroke: dict) -> tuple[float, float, float]:
    pts = stroke.get("polyline") or []
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    r = sum(math.hypot(x - cx, y - cy) for x, y in zip(xs, ys)) / len(xs)
    return cx, cy, r


def spring_score(strokes: list) -> float:
    """Zigzag / dense short segments near one side → spring."""
    score = 0.0
    for s in strokes:
        pts = s.get("polyline") or []
        if len(pts) < 2:
            continue
        for a, b in zip(pts, pts[1:]):
            dx = float(b[0]) - float(a[0])
            dy = float(b[1]) - float(a[1])
            L = math.hypot(dx, dy)
            if 0.3 < L < 6.0 and abs(dy) > abs(dx) * 0.4:
                score += 1.0
    return score


def normalize_symbol(strokes: list) -> dict:
    x0, y0, x1, y1 = bbox(strokes)
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    local = translate(strokes, -cx, -cy)
    lx, ly, rx, ry = bbox(local)
    # Horizontal span to ±TIP (ports 1/2)
    half = max(abs(lx), abs(rx), 1.0)
    k = TIP / half
    local = scale(local, k)
    lx, ly, rx, ry = bbox(local)
    local = translate(local, -(lx + rx) * 0.5, 0.0)

    circles = []
    lines = []
    for s in local:
        if is_circle_like(s):
            cxb, cyb, rb = circle_center_r(s)
            circles.append(
                {
                    "cx": round(cxb, 3),
                    "cy": round(cyb, 3),
                    "r": round(rb, 3),
                    "polyline": [[round(float(p[0]), 3), round(float(p[1]), 3)] for p in s["polyline"]],
                }
            )
        else:
            lines.append([[round(float(p[0]), 3), round(float(p[1]), 3)] for p in s["polyline"]])

    # Outlet port 3: vertical tip with larger |y|
    lx, ly, rx, ry = bbox(local)
    port3_y = -TIP if abs(ly) >= abs(ry) else TIP
    # Prefer direction of a near-vertical center stub
    stub_votes = 0
    for ln in lines:
        if len(ln) < 2:
            continue
        ax, ay = ln[0]
        bx, by = ln[-1]
        if abs(ax) < 10 and abs(bx) < 10:
            stub_votes += 1 if (ay + by) * 0.5 < 0 else -1
    if stub_votes != 0:
        port3_y = -TIP if stub_votes > 0 else TIP

    ball = circles[0] if circles else {"cx": 0.0, "cy": 0.0, "r": 6.0, "polyline": []}
    return {
        "port_1": [-TIP, 0.0],
        "port_2": [TIP, 0.0],
        "port_3": [0.0, port3_y],
        "ball": ball,
        "strokes": lines,
        "circles": circles,
        "bbox": [round(v, 3) for v in bbox(local)],
        "spring_score": spring_score(local),
    }


def best_split(strokes: list) -> float:
    """Largest gap between stroke mid-X, ignoring tiny outlier groups."""
    mids = sorted(mid(s)[0] for s in strokes)
    # Smooth: only consider gaps where both sides have enough strokes
    best = (0.0, 0.0)  # gap, split
    for i in range(1, len(mids)):
        gap = mids[i] - mids[i - 1]
        if gap < 8.0:
            continue
        left_n = i
        right_n = len(mids) - i
        if left_n < 15 or right_n < 15:
            continue
        if gap > best[0]:
            best = (gap, (mids[i] + mids[i - 1]) * 0.5)
    if best[0] > 0:
        return best[1]
    # Fallback: median X of stroke mids
    return mids[len(mids) // 2]


def pack(sym: dict, source: str, has_spring: bool) -> dict:
    ball = sym["ball"]
    return {
        "source": source,
        "note": "ports 1/2 = входы, 3 = общий; шарик к седлу низкого давления",
        "scale": 1.0,
        "has_spring": has_spring,
        "port_1": sym["port_1"],
        "port_2": sym["port_2"],
        "port_3": sym["port_3"],
        "ball_r": ball.get("r", 6.0),
        "ball_cx0": ball.get("cx", 0.0),
        "ball_cy0": ball.get("cy", 0.0),
        "ball_travel": 5.5,
        "strokes": sym["strokes"],
        "circle": ball.get("polyline") or [],
        "bbox": sym["bbox"],
    }


def main() -> None:
    doc = json.loads(RAW.read_text(encoding="utf-8"))
    strokes = list(doc.get("strokes") or [])
    xs = [mid(s)[0] for s in strokes]
    print("n", len(strokes), "x", min(xs), max(xs))
    split = best_split(strokes)
    print("split_x", split)
    left = [s for s in strokes if mid(s)[0] < split]
    right = [s for s in strokes if mid(s)[0] >= split]
    print("left", len(left), "right", len(right))

    a = normalize_symbol(left)
    b = normalize_symbol(right)
    print("A spring_score", a["spring_score"], "bbox", a["bbox"], "p3", a["port_3"], "circles", len(a["circles"]))
    print("B spring_score", b["spring_score"], "bbox", b["bbox"], "p3", b["port_3"], "circles", len(b["circles"]))

    # Lower spring score = without spring
    if a["spring_score"] <= b["spring_score"]:
        plain, spring = a, b
    else:
        plain, spring = b, a

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    p1 = OUT_DIR / "shuttle_ugo.json"
    p2 = OUT_DIR / "shuttle_spring_ugo.json"
    d1 = pack(plain, "Проект1_Схема1.dxf — ИЛИ без пружины", False)
    d2 = pack(spring, "Проект1_Схема1.dxf — ИЛИ с пружиной", True)
    p1.write_text(json.dumps(d1, ensure_ascii=False, indent=2), encoding="utf-8")
    p2.write_text(json.dumps(d2, ensure_ascii=False, indent=2), encoding="utf-8")
    print("wrote", p1, "strokes", len(d1["strokes"]))
    print("wrote", p2, "strokes", len(d2["strokes"]))


if __name__ == "__main__":
    main()
