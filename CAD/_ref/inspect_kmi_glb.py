#!/usr/bin/env python3
import json
import struct
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
p = Path(r"D:/mech-sim/CAD/magnetic_contactor_kmi-10910.glb")
data = p.read_bytes()
off = 12
clen, _ctype = struct.unpack_from("<I4s", data, off)
off += 8
j = json.loads(data[off : off + clen].decode("utf-8"))
ex = j["asset"].get("extras") or {}
print("title", ex.get("title"))
print("license", ex.get("license"))
print("source", ex.get("source"))
print("nodes", len(j["nodes"]), "meshes", len(j["meshes"]))
for i, n in enumerate(j["nodes"]):
    name = n.get("name", "")
    print(
        f"N{i} name={name!r} t={n.get('translation')} s={n.get('scale')} "
        f"mesh={n.get('mesh')} ch={n.get('children')}"
    )
mins, maxs = [], []
for a in j.get("accessors", []):
    if a.get("type") == "VEC3" and "min" in a and "max" in a:
        mins.append(a["min"])
        maxs.append(a["max"])
if mins:
    gmn = [min(m[k] for m in mins) for k in range(3)]
    gmx = [max(m[k] for m in maxs) for k in range(3)]
    size = [gmx[k] - gmn[k] for k in range(3)]
    print("AABB min", gmn, "max", gmx, "size_m", size)
    print("size_mm", [s * 1000 for s in size])
for i, m in enumerate(j.get("materials", [])):
    pbr = m.get("pbrMetallicRoughness") or {}
    print("MAT", i, m.get("name"), pbr.get("baseColorFactor"))
for i, m in enumerate(j.get("meshes", [])):
    name = "".join(c if ord(c) < 128 else "?" for c in (m.get("name") or ""))
    print("mesh", i, name, "prims", len(m.get("primitives", [])))
