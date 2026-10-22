import json
from pathlib import Path

p = Path(r"C:\Users\RomanSanych\.cursor\projects\d-mech-sim\agent-tools\559489db-b547-49cc-b865-6a1cfac344e3.txt")
data = json.loads(p.read_text(encoding="utf-8"))
wires = data["return_value"]["wires"]
qf = [w for w in wires if w.get("a_tag") == "QF1" or w.get("b_tag") == "QF1"]
keys = ["id", "num", "a", "b", "a_tag", "b_tag", "a_pos", "b_pos", "tip_a", "tip_b", "joints", "path"]
out = {"tag": "QF1", "phase": "before_move", "n": len(qf), "wires": [{k: w[k] for k in keys} for w in qf]}
dest = Path(r"C:\Users\RomanSanych\AppData\Local\Cursor\AgentStores\cursor_agent_stores\f9531259-c70e-485f-9272-7236ac6dfb64\files\qf1_wires_before.json")
dest.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print("saved", dest, "n=", len(qf))
for w in qf:
    print(w["id"], w["num"], w["a_tag"] + "." + w["a"].split(".")[-1], "<->", w["b_tag"] + "." + w["b"].split(".")[-1], "path_pts=", len(w["path"]), "joints=", len(w["joints"]))
