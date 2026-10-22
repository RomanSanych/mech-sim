import json
from pathlib import Path

after_raw = Path(r"C:\Users\RomanSanych\.cursor\projects\d-mech-sim\agent-tools\c2015e30-5e8a-46eb-9456-6bfae689586f.txt")
before = json.loads(Path(r"C:\Users\RomanSanych\AppData\Local\Cursor\AgentStores\cursor_agent_stores\f9531259-c70e-485f-9272-7236ac6dfb64\files\qf1_wires_before.json").read_text(encoding="utf-8"))
data = json.loads(after_raw.read_text(encoding="utf-8"))
wires = data["return_value"]["wires"]
qf = [w for w in wires if w.get("a_tag") == "QF1" or w.get("b_tag") == "QF1"]
keys = ["id", "num", "a", "b", "a_tag", "b_tag", "a_pos", "b_pos", "tip_a", "tip_b", "joints", "path"]
after = {"tag": "QF1", "phase": "after_move", "n": len(qf), "wires": [{k: w[k] for k in keys} for w in qf]}
Path(r"C:\Users\RomanSanych\AppData\Local\Cursor\AgentStores\cursor_agent_stores\f9531259-c70e-485f-9272-7236ac6dfb64\files\qf1_wires_after.json").write_text(json.dumps(after, ensure_ascii=False, indent=2), encoding="utf-8")

before_by_id = {w["id"]: w for w in before["wires"]}
print("QF1 after pos from wires:")
for w in qf:
    pos = w["b_pos"] if w["b_tag"] == "QF1" else w["a_pos"]
    print(" ", w["id"], "QF1@", pos)

print("\nCOMPARE:")
for w in qf:
    b = before_by_id.get(w["id"])
    if not b:
        print("NEW", w["id"])
        continue
    print(f"\nwire {w['id']} num={w['num']} {w['a_tag']}<->{w['b_tag']}")
    print("  before joints:", b["joints"])
    print("  after  joints:", w["joints"])
    print("  before path:  ", b["path"])
    print("  after  path:  ", w["path"])
    print("  before tip_qf:", b["tip_b"] if b["b_tag"]=="QF1" else b["tip_a"])
    print("  after  tip_qf:", w["tip_b"] if w["b_tag"]=="QF1" else w["tip_a"])
