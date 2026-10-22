import math

ENERGY_TO_BOLT = 0.16
K_VIS_DIV = 135.0
M_REF = 0.42
TRAVEL_MAX = 3.6 * 1.15
MAG_WELL_D = 1.65
FEED_PAST = 0.2
MM_TO_FEED = 0.006
bolt_rest_z, bolt_length, mag_z = 1.35, 4.2, 1.0

# Proposed timing
BACK_K = 0.22
FWD_K = 2.2
PAD = 0.012

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
    travel = max(0.5, min(TRAVEL_MAX, travel))
    fm = feed_min(c)
    v0 = math.sqrt(2 * e_bolt / max(mass, 0.05))
    kt = (spring - 400) / (5000 - 400)
    fire_back = max(0.018, min(0.085, BACK_K * travel / max(v0, 1.0)))
    fire_back *= 1.25 + (0.92 - 1.25) * kt
    fire_back = max(0.018, min(0.09, fire_back))
    t_spring = math.pi * 0.5 * math.sqrt(mass / max(spring, 1))
    fire_fwd = max(0.018, min(0.11, t_spring * FWD_K * (0.85 + 0.3 * (travel / TRAVEL_MAX))))
    cycle = fire_back + fire_fwd + PAD
    rpm = 60.0 / max(cycle, 0.04)
    ok = travel + 0.02 >= fm
    return dict(travel=travel, feed=fm, rpm=rpm, ok=ok, cycle=cycle)

print("DEFAULT 0.42/1600")
for cal in cals:
    r = compute(cal, 0.42, 1600)
    print(f"  {cal}: RPM={r['rpm']:.0f} stroke={r['travel']:.2f} OK={r['ok']} cycle={r['cycle']*1000:.0f}ms")

print("\nFEEDING envelopes")
for cal in cals:
    ok_rpms = []
    for mi in range(21):
        mass = 0.15 + mi * (1.2 - 0.15) / 20
        for si in range(47):
            spring = 400 + si * (5000 - 400) / 46
            r = compute(cal, mass, spring)
            if r["ok"]:
                ok_rpms.append(r["rpm"])
    if ok_rpms:
        print(f"  {cal}: {min(ok_rpms):.0f}-{max(ok_rpms):.0f} RPM  n={len(ok_rpms)}")
    else:
        print(f"  {cal}: none")
