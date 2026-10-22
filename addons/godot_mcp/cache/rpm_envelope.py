import math

ENERGY_TO_BOLT = 0.16
K_VIS_DIV = 135.0
M_REF = 0.42
TRAVEL_MAX = 3.6 * 1.15
TRAVEL_MIN = 0.5
MAG_WELL_D = 1.65
FEED_PAST = 0.2
MM_TO_FEED = 0.006
bolt_rest_z, bolt_length, mag_z = 1.35, 4.2, 1.0

cals = {
  "9x19": dict(energy=520, mag_scale=1.0, overall=29.7),
  "9x18": dict(energy=300, mag_scale=0.92, overall=25.0),
  "45acp": dict(energy=480, mag_scale=1.22, overall=32.0),
  "22lr": dict(energy=140, mag_scale=0.78, overall=25.4),
}

def feed_min(c):
    well_d = MAG_WELL_D * c["mag_scale"]
    mag_rear = mag_z - well_d * 0.5
    face_rest = bolt_rest_z + bolt_length * 0.5
    past = FEED_PAST + c["overall"] * MM_TO_FEED
    return face_rest - mag_rear + past

def compute(cal, mass, spring):
    c = cals[cal]
    e_bolt = c["energy"] * ENERGY_TO_BOLT
    k_vis = max(spring / K_VIS_DIV, 0.5)
    travel = math.sqrt(2 * e_bolt / k_vis) * (M_REF / max(mass, 0.05)) ** 0.18
    travel = max(TRAVEL_MIN, min(TRAVEL_MAX, travel))
    fm = feed_min(c)
    v0 = math.sqrt(2 * e_bolt / max(mass, 0.05))
    fire_back = max(0.028, min(0.26, 0.45 * travel / max(v0, 1.0)))
    kt = (spring - 400) / (5000 - 400)
    fire_back *= 1.4 + (0.88 - 1.4) * kt
    fire_back = max(0.028, min(0.3, fire_back))
    t_spring = math.pi * 0.5 * math.sqrt(mass / max(spring, 1))
    fire_fwd = max(0.03, min(0.55, t_spring * 8.0 * (0.7 + (1.3 - 0.7) * (travel / TRAVEL_MAX))))
    cycle = fire_back + fire_fwd + 0.045
    rpm = 60.0 / max(cycle, 0.05)
    ok = travel + 0.02 >= fm
    face_rear = (bolt_rest_z - travel) + bolt_length * 0.5
    clear = (mag_z - MAG_WELL_D * c["mag_scale"] * 0.5) - face_rear
    return dict(travel=travel, feed=fm, rpm=rpm, ok=ok, clear=clear)

print("=== DEFAULT mass=0.42 spring=1600 ===")
for cal in cals:
    r = compute(cal, 0.42, 1600)
    print(f"{cal:6} RPM={r['rpm']:6.0f} stroke={r['travel']:.2f} need={r['feed']:.2f} OK={r['ok']} clear={r['clear']:+.2f}")

print()
print("=== FEEDING RPM envelope (mass 0.15-1.2, spring 400-5000) ===")
for cal in cals:
    ok_rpms = []
    for mi in range(0, 21):
        mass = 0.15 + mi * (1.2 - 0.15) / 20
        for si in range(0, 47):
            spring = 400 + si * (5000 - 400) / 46
            r = compute(cal, mass, spring)
            if r["ok"]:
                ok_rpms.append((r["rpm"], mass, spring, r["travel"]))
    if ok_rpms:
        lo = min(ok_rpms, key=lambda x: x[0])
        hi = max(ok_rpms, key=lambda x: x[0])
        print(f"{cal:6} feeding RPM {lo[0]:.0f}-{hi[0]:.0f}")
        print(f"       slowest: m={lo[1]:.2f} k={lo[2]:.0f} stroke={lo[3]:.2f}")
        print(f"       fastest: m={hi[1]:.2f} k={hi[2]:.0f} stroke={hi[3]:.2f}")
        print(f"       n_ok={len(ok_rpms)}/{21*47} default_ok={compute(cal,0.42,1600)['ok']}")
    else:
        print(f"{cal:6} NO feeding configs!")

print()
print("=== Notable configs ===")
for cal in cals:
    a = compute(cal, 0.22, 700)
    b = compute(cal, 0.85, 900)
    c = compute(cal, 0.42, 1600)
    d = compute(cal, 0.25, 2000)
    print(f"{cal}: L/soft={a['rpm']:.0f}/{a['ok']} mid={c['rpm']:.0f}/{c['ok']} H/soft={b['rpm']:.0f}/{b['ok']} L/stiff={d['rpm']:.0f}/{d['ok']}")
