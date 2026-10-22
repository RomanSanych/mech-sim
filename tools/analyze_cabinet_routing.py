#!/usr/bin/env python3
import json, math, sys
from collections import Counter, defaultdict
from pathlib import Path

# Optional: decode .msim via sibling script
ROOT = Path(__file__).resolve().parents[1]
src = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "test" / "demo_cabinet_review_wip.mechsim.json")
msim = ROOT / "test" / "demo_cabinet_review_wip.msim"
json_out = ROOT / "test" / "demo_cabinet_review_wip.mechsim.json"

if msim.exists():
    # refresh json from latest msim
    sys.path.insert(0, str(Path(__file__).parent))
    from decode_msim import decode
    data = decode(msim)
    json_out.write_text(json.dumps(data, ensure_ascii=False, indent="\t"), encoding="utf-8")
    d = data
    print("refreshed from", msim)
else:
    d = json.loads(src.read_text(encoding="utf-8"))
    print("loaded", src)

els = {e["id"]: e for e in d["elements"]}
wires = d["wires"]


def pos(eid):
    e = els.get(eid)
    return tuple(e["position"]) if e else None


def tag(eid):
    e = els.get(eid)
    if not e:
        return "?"
    return e.get("tag") or e.get("electro_class") or e.get("kind")


def klass(eid):
    e = els.get(eid)
    if not e:
        return "?"
    return e.get("electro_class") or e.get("kind")


print("elements", len(els), "wires", len(wires))

print("\n=== ZONE COLUMNS (x // 100) ===")
zones = defaultdict(list)
for e in d["elements"]:
    zones[int(e["position"][0] // 100)].append(e)
for z in sorted(zones):
    items = []
    for e in sorted(zones[z], key=lambda x: (x["position"][1], x["position"][0])):
        t = e.get("tag") or e.get("electro_class") or e.get("kind")
        items.append("%s@%d,%d" % (t, int(e["position"][0]), int(e["position"][1])))
    print("  z%d (%d): %s" % (z, len(items), ", ".join(items)))

print("\n=== RAILS ===")
for e in d["elements"]:
    if e.get("kind") != "rail":
        continue
    pts = e.get("rail_points", [])
    wpts = [[e["position"][0] + p[0], e["position"][1] + p[1]] for p in pts]
    print("  id=%s world=%s domain=%s" % (e["id"], wpts, e.get("rail_domain")))

print("\n=== WIRE ROUTING STATS ===")
n_joint = 0
n_empty = 0
bends = []
long_h = 0.0
long_v = 0.0
axis_pat = Counter()
manhattan_vs_euclid = []
for w in wires:
    js = w.get("joints") or []
    a = pos(w["a_id"])
    b = pos(w["b_id"])
    if not a or not b:
        continue
    if not js:
        n_empty += 1
        chain = [list(a), list(b)]
    else:
        n_joint += 1
        bends.append(len(js))
        chain = [list(a)] + [list(j) for j in js] + [list(b)]
    axes = []
    plen = 0.0
    for i in range(len(chain) - 1):
        dx = chain[i + 1][0] - chain[i][0]
        dy = chain[i + 1][1] - chain[i][1]
        plen += abs(dx) + abs(dy)
        if abs(dx) < 0.5 and abs(dy) < 0.5:
            continue
        if abs(dx) >= abs(dy):
            axes.append("H")
            long_h += abs(dx)
        else:
            axes.append("V")
            long_v += abs(dy)
    eu = math.hypot(a[0] - b[0], a[1] - b[1])
    if eu > 1:
        manhattan_vs_euclid.append(plen / eu)
    if axes:
        key = ">".join(axes[:8])
        axis_pat[key] += 1

print("with_joints", n_joint, "empty_joints", n_empty)
print("bend hist", dict(Counter(bends)))
print("seg length sum H/V", round(long_h), round(long_v))
if manhattan_vs_euclid:
    s = sorted(manhattan_vs_euclid)
    print("path/euclid p50", round(s[len(s) // 2], 2), "p90", round(s[int(len(s) * 0.9)], 2))
print("axis patterns top:")
for k, v in axis_pat.most_common(25):
    print(" ", v, k)
print("broken", sum(1 for w in wires if w.get("broken")))
print("rail_skip", sum(1 for w in wires if w.get("rail_skip_ids")))

print("\n=== LINK CLASSES ===")
pairs = Counter()
for w in wires:
    pairs[tuple(sorted([klass(w["a_id"]), klass(w["b_id"])]))] += 1
for k, v in pairs.most_common(30):
    print("  %s -- %s: %d" % (k[0], k[1], v))

print("\n=== GROUP_TAG CLUSTERS ===")
by_gt = defaultdict(list)
for e in d["elements"]:
    gt = e.get("group_tag") or ""
    if gt:
        by_gt[gt].append(e)
for gt, es in sorted(by_gt.items(), key=lambda x: -len(x[1])):
    if len(es) < 2:
        continue
    xs = [e["position"][0] for e in es]
    ys = [e["position"][1] for e in es]
    cl = [e.get("electro_class") for e in es]
    print("  %s n=%d x=[%.0f..%.0f] y=[%.0f..%.0f] %s" % (gt, len(es), min(xs), max(xs), min(ys), max(ys), cl))

print("\n=== MCB/RCD ===")
mcbs = [e for e in d["elements"] if e.get("electro_class") in ("mcb", "rcd")]
mcbs.sort(key=lambda e: (e["position"][0], e["position"][1]))
for e in mcbs:
    print("  %s @ %s" % (e.get("tag"), e["position"]))

print("\n=== CLASS BBOX ===")
for ec in (
    "contactor", "relay", "timer_relay", "thermal", "contact", "lamp",
    "button", "switch", "e_stop", "terminal", "psu", "supply", "mcb", "rcd",
):
    xs = [e for e in d["elements"] if e.get("electro_class") == ec]
    if not xs:
        continue
    print(
        "  %s n=%d x=[%.0f..%.0f] y=[%.0f..%.0f]"
        % (
            ec,
            len(xs),
            min(e["position"][0] for e in xs),
            max(e["position"][0] for e in xs),
            min(e["position"][1] for e in xs),
            max(e["position"][1] for e in xs),
        )
    )

print("\n=== MOST BENT / LONGEST ===")
scored = []
for w in wires:
    js = w.get("joints") or []
    a = pos(w["a_id"])
    b = pos(w["b_id"])
    if not a or not b:
        continue
    dist = math.hypot(a[0] - b[0], a[1] - b[1])
    scored.append(
        (
            len(js),
            dist,
            w.get("num"),
            tag(w["a_id"]),
            w.get("a_port"),
            tag(w["b_id"]),
            w.get("b_port"),
            bool(w.get("broken")),
            js[:5],
        )
    )
scored.sort(reverse=True)
for row in scored[:20]:
    print(
        "  num=%s bends=%d tipdist=%.0f %s.%s -> %s.%s broken=%s joints=%s" % row
    )

print("\n=== SHARED Y ROWS (grid 20, >=3) ===")
by_y = defaultdict(list)
for e in d["elements"]:
    if e.get("kind") == "rail":
        continue
    y = int(round(e["position"][1] / 20.0) * 20)
    by_y[y].append(e.get("tag") or e.get("electro_class"))
for y, ts in sorted(by_y.items()):
    if len(ts) >= 3:
        print("  y=%d: %s" % (y, ", ".join(ts)))

# dx between consecutive QF in same rough column
print("\n=== MCB NEIGHBOR DY (same x±40) ===")
for e in mcbs:
    same = [
        o
        for o in mcbs
        if o["id"] != e["id"] and abs(o["position"][0] - e["position"][0]) <= 40
    ]
    same.sort(key=lambda o: o["position"][1])
print("(see positions above for pitch)")
ys = sorted(e["position"][1] for e in mcbs if abs(e["position"][0] - (-600)) < 80)
if len(ys) >= 2:
    dys = [ys[i + 1] - ys[i] for i in range(len(ys) - 1)]
    print("  near x=-600 dy:", dys)
