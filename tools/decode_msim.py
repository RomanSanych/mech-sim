#!/usr/bin/env python3
"""Decode MechSim .msim (MSIM+xor+deflate) to JSON."""
import sys, zlib, json, pathlib

MAGIC = b"MSIM"
KEY = b"MechSim-MSIM-v1"

def decode(path: pathlib.Path) -> dict:
    raw = path.read_bytes()
    if raw[:4] != MAGIC:
        raise SystemExit(f"not MSIM: {path}")
    ver = raw[4]
    if ver != 1:
        raise SystemExit(f"bad ver {ver}")
    n = int.from_bytes(raw[5:9], "little")
    masked = raw[9:9+n]
    packed = bytes(b ^ KEY[i % len(KEY)] for i, b in enumerate(masked))
    text = zlib.decompress(packed).decode("utf-8")
    return json.loads(text)

def main():
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".mechsim.json")
    data = decode(src)
    dst.write_text(json.dumps(data, ensure_ascii=False, indent="\t"), encoding="utf-8")
    els = data.get("elements", [])
    wires = data.get("wires", [])
    print(f"wrote {dst} elements={len(els)} wires={len(wires)}")

if __name__ == "__main__":
    main()
