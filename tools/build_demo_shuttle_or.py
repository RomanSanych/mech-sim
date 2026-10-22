# -*- coding: utf-8 -*-
"""Демо ИЛИ: два КМ с разным давлением + две 3/2 кнопки → порты 1/2."""
from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALVE_TPL = ROOT / "test" / "_valve32_template.json"
OUT = ROOT / "test" / "demo_shuttle_or.mechsim.json"


def source(eid: int, tag: str, pos, world, bar: float) -> dict:
	return {
		"kind": "source",
		"id": eid,
		"tag": tag,
		"tag_offset": [0.0, 0.0],
		"position": list(pos),
		"rotation_quad": 0,
		"action": "none",
		"bore_mm": 32.0,
		"rod_mm": 12.0,
		"stroke_mm": 100.0,
		"spring_rate": 0.0,
		"spring_preload": 0.0,
		"mass_kg": 1.0,
		"friction_n": 5.0,
		"load_n": 0.0,
		"open_ports": False,
		"cushion": False,
		"pressure_bar": bar,
		"temperature_c": 20.0,
		"world_pos": list(world),
		"world_basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
		"auto_ground": False,
		"tag_prefix": "КМ",
	}


def shuttle(eid: int) -> dict:
	return {
		"kind": "accessory",
		"id": eid,
		"tag": "КЛ1",
		"tag_offset": [0.0, 0.0],
		"position": [240.0, 100.0],
		"rotation_quad": 0,
		"action": "none",
		"bore_mm": 32.0,
		"rod_mm": 12.0,
		"stroke_mm": 100.0,
		"spring_rate": 0.0,
		"spring_preload": 0.0,
		"mass_kg": 1.0,
		"friction_n": 5.0,
		"load_n": 0.0,
		"open_ports": False,
		"cushion": False,
		"pressure_bar": 6.0,
		"temperature_c": 20.0,
		"world_pos": [0.55, 1.35, 0.05],
		"world_basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
		"recipe_id": "shuttle",
		"catalog_id": "shuttle",
		"accessory_class": "shuttle",
		"tag_prefix": "КЛ",
		"opening": 0.5,
		"flow_nl_min": 1170.0,
		"valve_cv": 1.2,
		"tube_od_mm": 8.0,
		"port_name": "G1/4",
		"auto_ground": False,
	}


def valve32(tpl: dict, eid: int, tag: str, pos, world) -> dict:
	v = deepcopy(tpl)
	v["id"] = eid
	v["tag"] = tag
	v["tag_prefix"] = "Р"
	v["position"] = list(pos)
	v["world_pos"] = list(world)
	v["world_basis"] = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	v["command_left"] = False
	v["command_right"] = False
	v["pressed"] = False
	v["valve_pos"] = int(v.get("rest_pos", 1))
	v["tube_od_mm"] = 8.0
	return v


def wire(wid: int, a_id: int, a_port: str, b_id: int, b_port: str, joints) -> dict:
	return {
		"id": wid,
		"num": wid,
		"a_id": a_id,
		"a_port": a_port,
		"b_id": b_id,
		"b_port": b_port,
		"id_mm": 5.0,
		"od_mm": 8.0,
		"joints": [list(j) for j in joints],
	}


def main() -> None:
	tpl = json.loads(VALVE_TPL.read_text(encoding="utf-8"))
	# ids: 1 КМ1, 2 КМ2, 3 Р1, 4 Р2, 5 КЛ1
	elements = [
		source(1, "КМ1", (40.0, 40.0), (0.0, 1.35, 0.35), 6.0),
		source(2, "КМ2", (40.0, 160.0), (0.0, 1.35, -0.25), 3.0),
		valve32(tpl, 3, "Р1", (140.0, 40.0), (0.28, 1.35, 0.35)),
		valve32(tpl, 4, "Р2", (140.0, 160.0), (0.28, 1.35, -0.25)),
		shuttle(5),
	]
	wires = [
		# КМ1(6бар) → Р1.1 → КЛ1.1
		wire(1, 1, "out", 3, "1", [[90.0, 40.0]]),
		wire(2, 3, "2", 5, "1", [[200.0, 40.0], [200.0, 100.0]]),
		# КМ2(3бар) → Р2.1 → КЛ1.2
		wire(3, 2, "out", 4, "1", [[90.0, 160.0]]),
		wire(4, 4, "2", 5, "2", [[200.0, 160.0], [280.0, 160.0], [280.0, 100.0]]),
	]
	scene = {
		"format": "mechsim-scene",
		"version": 1,
		"title": "Демо: клапан ИЛИ (shuttle)",
		"note": (
			"КМ1=6 бар → Р1 (кнопка) → порт 1; КМ2=3 бар → Р2 (кнопка) → порт 2; "
			"выход 3 свободен. Run: жми Р1/Р2 в 3D — разное давление на седлах, шарик к меньшему."
		),
		"cabinet_door_open": True,
		"next_id": 6,
		"elements": elements,
		"wires": wires,
	}
	OUT.write_text(json.dumps(scene, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
	print("wrote", OUT, "elements", len(elements), "wires", len(wires))


if __name__ == "__main__":
	main()
