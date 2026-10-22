import json
from pathlib import Path

raw = Path(r"C:\Users\RomanSanych\.cursor\projects\d-mech-sim\agent-tools\bf2efa65-1bd3-4fb2-bade-ba69d40db0fa.txt")
data = json.loads(raw.read_text(encoding="utf-8"))
wires = data["return_value"]["wires"]
g1 = [w for w in wires if w.get("a_tag") == "G1" or w.get("b_tag") == "G1"]
print("G1 wires:", len(g1))
for w in g1:
    print("---")
    print(f"id={w['id']} num={w['num']} {w['a_tag']}.{w['a'].split('.')[-1]} <-> {w['b_tag']}.{w['b'].split('.')[-1]} color={w['color']}")
    print(f"  a_pos={w['a_pos']} b_pos={w['b_pos']}")
    print(f"  tip_a={w['tip_a']} tip_b={w['tip_b']} gap_a={w['gap_a']} gap_b={w['gap_b']}")
    print(f"  joints={w['joints']}")
    print(f"  path={w['path']}")
    # analyze segments
    path = w["path"]
    segs = []
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        if abs(dx) < 0.5 and abs(dy) < 0.5:
            continue
        orient = "H" if abs(dy) <= abs(dx) else "V"
        segs.append(f"{orient}:{a}->{b} len={abs(dx)+abs(dy):.0f}")
    print("  segs:", " | ".join(segs))
    # reverse check
    for i in range(len(path) - 2):
        ab = (path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1])
        bc = (path[i + 2][0] - path[i + 1][0], path[i + 2][1] - path[i + 1][1])
        dot = ab[0] * bc[0] + ab[1] * bc[1]
        if dot < -0.01 and min((ab[0] ** 2 + ab[1] ** 2) ** 0.5, (bc[0] ** 2 + bc[1] ** 2) ** 0.5) > 9:
            print(f"  REVERSE at {path[i+1]}")
