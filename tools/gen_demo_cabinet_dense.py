#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Демо плотного щита: клеммники с terminal_bus (без busbar), читаемая 2D-раскладка."""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "test" / "demo_cabinet_dense.mechsim.json"
DIN_HALFS = 38
G = 10.0  # SCH_GRID

RECIPES = {
	"supply_1ph": {
		"electro_class": "supply", "electro_mount": "none", "tag_prefix": "XS",
		"poles": 1, "voltage": 230.0,
		"electro_ports": [{"name": "L", "type": "source"}, {"name": "N", "type": "source"}, {"name": "PE", "type": "source"}],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"mcb_1p": {
		"electro_class": "mcb", "electro_mount": "din", "tag_prefix": "QF",
		"poles": 1, "curve": "C", "rating_a": 16.0, "u_max": 6.0,
		"electro_ports": [{"name": "1", "type": "line"}, {"name": "2", "type": "line"}],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"mcb_2p": {
		"electro_class": "mcb", "electro_mount": "din", "tag_prefix": "QF",
		"poles": 2, "curve": "C", "rating_a": 25.0, "u_max": 6.0,
		"electro_ports": [
			{"name": "1", "type": "line"}, {"name": "2", "type": "line"},
			{"name": "3", "type": "line"}, {"name": "4", "type": "line"},
		],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"rcd_1pn": {
		"electro_class": "rcd", "electro_mount": "din", "tag_prefix": "QD",
		"poles": 2, "rating_a": 25.0, "i_delta_ma": 30.0, "phase": "AC",
		"electro_ports": [
			{"name": "1", "type": "line"}, {"name": "2", "type": "line"},
			{"name": "3", "type": "line"}, {"name": "4", "type": "line"},
		],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"psu_24": {
		"electro_class": "psu", "electro_mount": "din", "tag_prefix": "G",
		"voltage": 24.0, "rating_a": 2.5,
		"electro_ports": [
			{"name": "L", "type": "line"}, {"name": "N", "type": "line"}, {"name": "PE", "type": "line"},
			{"name": "+24", "type": "source"}, {"name": "0", "type": "source"},
		],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"term_block_4": {
		"electro_class": "terminal", "electro_mount": "din", "tag_prefix": "XT",
		"electro_ports": [{"name": str(i), "type": "line"} for i in range(1, 5)],
		"contact_defs": [], "coil_ports": [], "group_template": "",
		"terminal_port_scheme": 2,
	},
	"relay_2c": {
		"electro_class": "relay", "electro_mount": "din", "tag_prefix": "KL",
		"voltage": 230.0, "rating_a": 10.0, "group_template": "relay_2",
		"coil_ports": ["A1", "A2"],
		"contact_defs": [
			{"name": "11", "type": "co"}, {"name": "12", "type": "nc"}, {"name": "14", "type": "no"},
			{"name": "21", "type": "co"}, {"name": "22", "type": "nc"}, {"name": "24", "type": "no"},
		],
		"electro_ports": [],
	},
	"relay_1c": {
		"electro_class": "relay", "electro_mount": "din", "tag_prefix": "KL",
		"voltage": 230.0, "rating_a": 10.0, "group_template": "relay_1",
		"coil_ports": ["A1", "A2"],
		"contact_defs": [
			{"name": "11", "type": "co"}, {"name": "12", "type": "nc"}, {"name": "14", "type": "no"},
		],
		"electro_ports": [],
	},
	"timer_relay": {
		"electro_class": "timer_relay", "electro_mount": "din", "tag_prefix": "KT",
		"voltage": 230.0, "rating_a": 8.0, "group_template": "timer",
		"coil_ports": ["A1", "A2"],
		"timer_mode": "on", "timer_unit": 1, "timer_value": 2.0, "delay_on": 2.0, "delay_off": 0.0,
		"contact_defs": [
			{"name": "COM", "type": "co"}, {"name": "NC", "type": "nc"}, {"name": "NO", "type": "no"},
		],
		"electro_ports": [],
	},
	"contactor_3p_aux": {
		"electro_class": "contactor", "electro_mount": "din", "tag_prefix": "KM",
		"voltage": 230.0, "rating_a": 25.0, "group_template": "contactor_3a",
		"coil_ports": ["A1", "A2"],
		"contact_defs": [
			{"name": "1", "type": "no"}, {"name": "2", "type": "no"},
			{"name": "3", "type": "no"}, {"name": "4", "type": "no"},
			{"name": "5", "type": "no"}, {"name": "6", "type": "no"},
			{"name": "13", "type": "no"}, {"name": "14", "type": "no"},
			{"name": "21", "type": "nc"}, {"name": "22", "type": "nc"},
		],
		"electro_ports": [],
	},
	"thermal_relay": {
		"electro_class": "thermal", "electro_mount": "din", "tag_prefix": "KK",
		"rating_a": 10.0, "group_template": "thermal",
		"contact_defs": [
			{"name": "95", "type": "nc"}, {"name": "96", "type": "nc"},
			{"name": "97", "type": "no"}, {"name": "98", "type": "no"},
		],
		"electro_ports": [
			{"name": "1", "type": "line"}, {"name": "2", "type": "line"},
			{"name": "3", "type": "line"}, {"name": "4", "type": "line"},
			{"name": "5", "type": "line"}, {"name": "6", "type": "line"},
		],
		"coil_ports": [],
	},
	"din_stop": {
		"electro_class": "din_stop", "electro_mount": "din", "tag_prefix": "E",
		"electro_ports": [], "contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"lamp": {
		"electro_class": "lamp", "electro_mount": "door", "tag_prefix": "HL",
		"voltage": 220.0, "lamp_color": "white",
		"electro_ports": [{"name": "X1", "type": "line"}, {"name": "X2", "type": "line"}],
		"contact_defs": [], "coil_ports": [], "group_template": "",
	},
	"btn_no": {
		"electro_class": "button", "electro_mount": "door", "tag_prefix": "SB",
		"group_template": "button_no", "btn_color": "green",
		"contact_defs": [{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		"electro_ports": [], "coil_ports": [],
	},
	"btn_nc": {
		"electro_class": "button", "electro_mount": "door", "tag_prefix": "SB",
		"group_template": "button_nc", "btn_color": "red",
		"contact_defs": [{"name": "11", "type": "nc"}, {"name": "12", "type": "nc"}],
		"electro_ports": [], "coil_ports": [],
	},
	"estop_nc": {
		"electro_class": "e_stop", "electro_mount": "door", "tag_prefix": "SB",
		"group_template": "estop", "btn_color": "red", "latching": True,
		"contact_defs": [{"name": "11", "type": "nc"}, {"name": "12", "type": "nc"}],
		"electro_ports": [], "coil_ports": [],
	},
	"switch_2pos": {
		"electro_class": "switch", "electro_mount": "door", "tag_prefix": "SA",
		"switch_positions": 2, "group_template": "",
		"contact_defs": [
			{"name": "1", "type": "no"}, {"name": "2", "type": "no"},
			{"name": "3", "type": "no"}, {"name": "4", "type": "no"},
		],
		"electro_ports": [], "coil_ports": [],
	},
}

WIDTH = {
	"mcb_1p": 2, "mcb_2p": 4, "rcd_1pn": 4, "psu_24": 4,
	"term_block_4": 4, "relay_2c": 2, "relay_1c": 1,
	"timer_relay": 3, "contactor_3p_aux": 5, "thermal_relay": 6, "din_stop": 1,
}


def contact_units(contacts: list) -> list:
	out, i = [], 0
	while i < len(contacts):
		a = contacts[i]
		t = a.get("type", "no")
		if t == "co":
			unit = [a]
			if i + 1 < len(contacts):
				unit.append(contacts[i + 1])
			if i + 2 < len(contacts):
				unit.append(contacts[i + 2])
			out.append(unit)
			i += len(unit)
			continue
		unit2 = [a]
		if i + 1 < len(contacts) and contacts[i + 1].get("type", "") == t:
			unit2.append(contacts[i + 1])
			i += 2
		else:
			i += 1
		out.append(unit2)
	return out


class Builder:
	def __init__(self) -> None:
		self.next_id = 1
		self.wire_id = 1000
		self.elements: list[dict] = []
		self.wires: list[dict] = []
		self.by_tag: dict[str, dict] = {}
		self.contacts: dict[str, list[dict]] = {}
		self._port_use: dict[tuple, int] = defaultdict(int)

	def alloc(self) -> int:
		i = self.next_id
		self.next_id += 1
		return i

	def add(self, rid: str, tag: str, pos: tuple[float, float], **kw) -> dict:
		rec = RECIPES[rid]
		eid = self.alloc()
		ports = kw.get("electro_ports")
		if ports is None:
			ports = [dict(p) for p in rec.get("electro_ports", [])]
		el = {
			"kind": "electro", "id": eid, "tag": tag, "tag_offset": [0, 0],
			"rotation_quad": 0, "catalog_id": rid, "recipe_id": rid, "variant_id": "ppv",
			"position": [float(pos[0]), float(pos[1])],
			"electro_class": rec["electro_class"],
			"electro_mount": rec["electro_mount"],
			"tag_prefix": kw.get("tag_prefix", rec["tag_prefix"]),
			"electro_ports": ports,
			"coil_ports": list(rec.get("coil_ports", [])),
			"contact_defs": [dict(c) for c in rec.get("contact_defs", [])],
			"group_template": rec.get("group_template", ""),
			"member_role": "device", "member_index": 0, "group_id": -1, "group_tag": "",
			"din_slot": int(kw.get("din_slot", -1)), "door_slot": -1,
			"door_xy": list(kw.get("door_xy", [-1, -1])),
			"poles": rec.get("poles", 1), "curve": rec.get("curve", "C"),
			"rating_a": rec.get("rating_a", 16.0), "i_delta_ma": rec.get("i_delta_ma", 30.0),
			"u_min": 180.0, "u_max": rec.get("u_max", 260.0),
			"phase": kw.get("phase", rec.get("phase", "")),
			"voltage": rec.get("voltage", 230.0),
			"lamp_color": kw.get("lamp_color", rec.get("lamp_color", "white")),
			"btn_color": kw.get("btn_color", rec.get("btn_color", "white")),
			"caption": kw.get("caption", rec.get("caption", "")),
			"latching": bool(rec.get("latching", False)),
			"closed": True, "pressed": False, "energized": False, "lit": False,
			"detached": False, "hide_unused_contacts": False,
			"timer_mode": rec.get("timer_mode", ""), "timer_unit": rec.get("timer_unit", 1),
			"timer_value": rec.get("timer_value", 0.0),
			"delay_on": rec.get("delay_on", 0.0), "delay_off": rec.get("delay_off", 0.0),
			"switch_positions": rec.get("switch_positions", 2),
			"terminal_port_scheme": 2,
			"terminal_bus": bool(kw.get("terminal_bus", False)),
			"color_id": str(kw.get("color_id", "")),
			"link_valve": False,
		}
		if el["electro_class"] == "switch":
			el["group_template"] = ""
		self.elements.append(el)
		self.by_tag[tag] = el
		if el["electro_class"] in ("button", "e_stop", "relay", "timer_relay", "contactor", "thermal"):
			el["member_role"] = "main"
			el["group_id"] = el["id"]
			el["group_tag"] = tag
			self._spawn_contacts(el)
		return el

	def _spawn_contacts(self, primary: dict) -> None:
		members = []
		px, py = primary["position"]
		for ui, unit in enumerate(contact_units(primary["contact_defs"])):
			idx = ui + 1
			cid = self.alloc()
			# Контакты — отдельной колонкой справа, шаг сетки (меньше пересечений).
			child = {
				"kind": "electro", "id": cid, "tag": f"{primary['tag']}.{idx}",
				"tag_offset": [0, 0], "rotation_quad": 0,
				"catalog_id": primary["recipe_id"], "recipe_id": primary["recipe_id"],
				"variant_id": "ppv",
				"position": [G * 102.0 + ui * G * 8.0, py],
				"electro_class": "contact", "electro_mount": "none",
				"tag_prefix": primary["tag_prefix"],
				"electro_ports": [], "coil_ports": [],
				"contact_defs": [dict(c) for c in unit],
				"group_template": "", "member_role": "contact", "member_index": idx,
				"group_id": primary["id"], "group_tag": primary["tag"],
				"din_slot": -1, "door_slot": -1, "door_xy": [-1, -1],
				"poles": 1, "curve": "C", "rating_a": 16.0, "i_delta_ma": 30.0,
				"u_min": 180.0, "u_max": 260.0, "phase": "", "voltage": 230.0,
				"lamp_color": "white", "btn_color": "white", "caption": "",
				"latching": False, "closed": True, "pressed": False,
				"energized": False, "lit": False, "detached": False,
				"hide_unused_contacts": False,
				"timer_mode": primary.get("timer_mode", ""),
				"timer_unit": primary.get("timer_unit", 1),
				"timer_value": primary.get("timer_value", 0.0),
				"delay_on": primary.get("delay_on", 0.0),
				"delay_off": primary.get("delay_off", 0.0),
				"switch_positions": 2, "terminal_port_scheme": 2,
				"terminal_bus": False, "color_id": "", "link_valve": False,
			}
			self.elements.append(child)
			self.by_tag[child["tag"]] = child
			members.append(child)
		self.contacts[primary["tag"]] = members

	def layout_contacts_band(self) -> None:
		"""Разнести контакты как юзер: позиция вне столбика + detached=True."""
		# Группы по group_tag → колонка
		groups: dict[str, list[dict]] = defaultdict(list)
		for el in self.elements:
			if el.get("member_role") != "contact":
				continue
			groups[str(el.get("group_tag", ""))].append(el)
		# Порядок колонок: пускатель / реле / дверца
		order = [
			"KM1", "KK1", "KL1", "KL2", "KL3", "KL4", "KL5", "KT1",
			"SB0", "SB1", "SB2", "SB3",
		]
		col = 0
		x0 = G * 100.0
		for gtag in order:
			members = groups.get(gtag, [])
			if not members:
				continue
			members.sort(key=lambda e: int(e.get("member_index", 0)))
			main = self.by_tag.get(gtag)
			base_y = float(main["position"][1]) if main else G * 20.0
			for mi, ch in enumerate(members):
				# Первый контакт кнопки/е-стопа неотделим — остаётся под актуатором.
				is_btn = bool(main) and str(main.get("electro_class", "")) in ("button", "e_stop")
				if is_btn and mi == 0:
					ch["detached"] = False
					continue
				ch["position"] = [x0 + col * G * 7.0, base_y + mi * G * 6.0]
				ch["detached"] = True
			col += 1

	def w(self, a: str, ap: str, b: str, bp: str, color: str = "brown", mm2: float = 1.5) -> None:
		ea, eb = self.by_tag[a], self.by_tag[b]
		ka, kb = (ea["id"], ap), (eb["id"], bp)
		self._port_use[ka] += 1
		self._port_use[kb] += 1
		if self._port_use[ka] > 2 or self._port_use[kb] > 2:
			raise RuntimeError(f">2 wires: {a}.{ap}={self._port_use[ka]} or {b}.{bp}={self._port_use[kb]}")
		wid = self.wire_id
		self.wire_id += 1
		self.wires.append({
			"id": wid, "a_id": ea["id"], "a_port": ap, "b_id": eb["id"], "b_port": bp,
			"id_mm": mm2, "color_id": color, "num": 0,
			"sleeve_yaw_a": 0.0, "sleeve_yaw_b": 0.0, "joints": [],
		})

	def place_rail(self, rail: int, items: list) -> None:
		# Концевые упоры DIN — не элементы схемы: в 3D авто по краям плотных групп.
		base = rail * DIN_HALFS
		slot = base + 1
		for rid, tag, pos, extra in items:
			w = WIDTH.get(rid, 4)
			if rid == "term_block_4" and extra.get("electro_ports"):
				# electro_ports[] = ряды; DIN half-slots = число рядов
				w = max(len(extra["electro_ports"]), 1)
			if slot + w > base + DIN_HALFS - 1:
				raise RuntimeError(f"rail {rail} overflow at {tag} (slot={slot}, w={w})")
			kw = dict(extra)
			kw["din_slot"] = slot
			self.add(rid, tag, pos, **kw)
			slot += w


def bus_term(rows: int = 4) -> list:
	"""Ряды клеммника (scheme2: порты 1..2*rows). Без phase — иначе UI схлопывает в 1 ряд."""
	return [{"label": "", "color_id": "", "type": "line"} for _ in range(rows)]


def port_pool(rows: int) -> list[str]:
	"""Сначала левые (нечёт), потом правые (чёт) — terminal_bus всё равно коротнуты."""
	odds = [str(i) for i in range(1, rows * 2 + 1, 2)]
	evens = [str(i) for i in range(2, rows * 2 + 1, 2)]
	return odds + evens


def build() -> dict:
	"""Плотный щит: ~30 DIN + 10 door, без busbar, полосы 2D."""
	b = Builder()
	# Полосы: питание / клеммы+БП / силовые+реле / дверца
	y1, y2, y3, y4 = G * 4, G * 18, G * 32, G * 50

	b.add("supply_1ph", "XS1", (G * 4, y1))

	b.place_rail(0, [
		("mcb_2p", "QF1", (G * 12, y1), {}),
		("rcd_1pn", "QD1", (G * 22, y1), {}),
		("mcb_1p", "QF2", (G * 32, y1), {}),
		("mcb_1p", "QF3", (G * 38, y1), {}),
		("mcb_1p", "QF4", (G * 44, y1), {}),
		("mcb_1p", "QF5", (G * 50, y1), {}),
		("mcb_1p", "QF6", (G * 56, y1), {}),
		("mcb_1p", "QF7", (G * 62, y1), {}),
		("mcb_1p", "QF8", (G * 68, y1), {}),
		("mcb_1p", "QF9", (G * 74, y1), {}),
		("mcb_1p", "QF10", (G * 80, y1), {}),
		("mcb_1p", "QF11", (G * 86, y1), {}),
	])

	# Rail1: БП + шинные клеммы L/N/PE (8+8+4 рядов = 20 half; +psu4 = 24)
	b.place_rail(1, [
		("psu_24", "G1", (G * 8, y2), {}),
		("term_block_4", "XTL1", (G * 18, y2), {
			"terminal_bus": True, "color_id": "brown", "caption": "L",
			"electro_ports": bus_term(8), "tag_prefix": "XT",
		}),
		("term_block_4", "XTN1", (G * 34, y2), {
			"terminal_bus": True, "color_id": "lightblue", "caption": "N",
			"electro_ports": bus_term(8), "tag_prefix": "XT",
		}),
		("term_block_4", "XTPE", (G * 50, y2), {
			"terminal_bus": True, "color_id": "pe", "caption": "PE",
			"electro_ports": bus_term(4), "tag_prefix": "XT",
		}),
		("mcb_1p", "QF12", (G * 62, y2), {}),
		("mcb_1p", "QF13", (G * 68, y2), {}),
		("term_block_4", "XT3", (G * 74, y2), {}),
		("term_block_4", "XT4", (G * 84, y2), {}),
	])

	b.place_rail(2, [
		("contactor_3p_aux", "KM1", (G * 10, y3), {}),
		("thermal_relay", "KK1", (G * 22, y3), {}),
		("relay_2c", "KL1", (G * 36, y3), {}),
		("relay_2c", "KL2", (G * 44, y3), {}),
		("relay_2c", "KL3", (G * 52, y3), {}),
		("relay_2c", "KL4", (G * 60, y3), {}),
		("relay_1c", "KL5", (G * 68, y3), {}),
		("timer_relay", "KT1", (G * 74, y3), {}),
	])

	for rid, tag, pos, extra in [
		("estop_nc", "SB0", (G * 8, y4), {"door_xy": [-0.09, 0.14], "btn_color": "red"}),
		("btn_no", "SB1", (G * 18, y4), {"door_xy": [0.0, 0.06], "btn_color": "green"}),
		("btn_nc", "SB2", (G * 28, y4), {"door_xy": [0.062, 0.06], "btn_color": "red"}),
		("btn_no", "SB3", (G * 38, y4), {"door_xy": [0.124, 0.06], "btn_color": "white"}),
		("switch_2pos", "SA1", (G * 48, y4), {"door_xy": [-0.09, 0.0]}),
		("lamp", "HL1", (G * 8, y4 + G * 10), {"door_xy": [-0.09, -0.08], "lamp_color": "white"}),
		("lamp", "HL2", (G * 18, y4 + G * 10), {"door_xy": [0.0, -0.08], "lamp_color": "green"}),
		("lamp", "HL3", (G * 28, y4 + G * 10), {"door_xy": [0.062, -0.08], "lamp_color": "red"}),
		("lamp", "HL4", (G * 38, y4 + G * 10), {"door_xy": [0.124, -0.08], "lamp_color": "yellow"}),
		("lamp", "HL5", (G * 48, y4 + G * 10), {"door_xy": [0.186, -0.08], "lamp_color": "white"}),
	]:
		b.add(rid, tag, pos, **extra)

	b.layout_contacts_band()

	l_pool = port_pool(8)
	n_pool = port_pool(8)
	pe_pool = port_pool(4)
	li = ni = pei = 0

	def take_l() -> str:
		nonlocal li
		if li >= len(l_pool):
			raise RuntimeError(f"L pool exhausted at {li}")
		p = l_pool[li]
		li += 1
		return p

	def take_n() -> str:
		nonlocal ni
		if ni >= len(n_pool):
			raise RuntimeError(f"N pool exhausted at {ni}")
		p = n_pool[ni]
		ni += 1
		return p

	def take_pe() -> str:
		nonlocal pei
		if pei >= len(pe_pool):
			raise RuntimeError(f"PE pool exhausted at {pei}")
		p = pe_pool[pei]
		pei += 1
		return p

	# --- Питание ---
	b.w("XS1", "L", "QF1", "1", "brown")
	b.w("XS1", "N", "QF1", "3", "blue")
	b.w("XS1", "PE", "XTPE", take_pe(), "green", 2.5)
	b.w("QF1", "2", "QD1", "1", "brown")
	b.w("QF1", "4", "QD1", "3", "blue")
	b.w("QD1", "4", "XTN1", take_n(), "blue")

	feed = ["QF2", "QF3", "QF4", "QF5", "QF6", "QF7", "QF8", "QF9", "QF10", "QF11", "QF12", "QF13"]
	b.w("QD1", "2", feed[0], "1", "brown")
	for i in range(len(feed) - 1):
		b.w(feed[i], "1", feed[i + 1], "1", "brown")

	b.w("XTPE", take_pe(), "G1", "PE", "green", 2.5)
	b.w("QF3", "2", "G1", "L", "brown")
	b.w("XTN1", take_n(), "G1", "N", "blue")
	b.w("QF2", "2", "XTL1", take_l(), "brown")

	# --- Пускатель: SB0–SB2–KK95–SB1 → KM1 ---
	b.w("XTL1", take_l(), "SB0.1", "11", "brown")
	b.w("SB0.1", "12", "SB2.1", "11", "brown")
	b.w("SB2.1", "12", "KK1.1", "95", "brown")
	b.w("KK1.1", "96", "SB1.1", "13", "brown")
	b.w("SB1.1", "14", "KM1", "A1", "brown")
	b.w("KM1", "A2", "XTN1", take_n(), "blue")
	b.w("KM1.4", "13", "SB1.1", "13", "brown")  # самоподхват (2-й на SB1.13)
	b.w("KM1.4", "14", "SB1.1", "14", "brown")

	b.w("QF9", "2", "KM1.1", "1", "black", 2.5)
	b.w("KM1.1", "2", "KK1", "1", "black", 2.5)
	b.w("KK1", "2", "XT3", "1", "black", 2.5)
	b.w("XTN1", take_n(), "XT3", "2", "blue", 2.5)

	# --- HL1 сеть ---
	b.w("XTL1", take_l(), "HL1", "X1", "brown")
	b.w("HL1", "X2", "XTN1", take_n(), "blue")

	# --- KL1 → HL2 ---
	b.w("XTL1", take_l(), "KL1", "A1", "brown")
	b.w("KL1", "A2", "XTN1", take_n(), "blue")
	b.w("XTL1", take_l(), "KL1.1", "11", "brown")
	b.w("KL1.1", "14", "HL2", "X1", "brown")
	b.w("HL2", "X2", "XTN1", take_n(), "blue")

	# --- KK авария → HL3 ---
	b.w("XTL1", take_l(), "KK1.2", "97", "brown")
	b.w("KK1.2", "98", "HL3", "X1", "brown")
	b.w("HL3", "X2", "XTN1", take_n(), "blue")

	# --- SA1 → KL2 → HL4 ---
	b.w("XTL1", take_l(), "SA1", "1", "brown")
	b.w("SA1", "2", "KL2", "A1", "brown")
	b.w("KL2", "A2", "XTN1", take_n(), "blue")
	b.w("XTL1", take_l(), "KL2.1", "11", "brown")
	b.w("KL2.1", "14", "HL4", "X1", "brown")
	b.w("HL4", "X2", "XTN1", take_n(), "blue")

	# --- SB3 → KT1 → KL3 → HL5 ---
	b.w("XTL1", take_l(), "SB3.1", "13", "brown")
	b.w("SB3.1", "14", "KT1", "A1", "brown")
	b.w("KT1", "A2", "XTN1", take_n(), "blue")
	b.w("XTL1", take_l(), "KT1.1", "COM", "brown")
	b.w("KT1.1", "NO", "KL3", "A1", "brown")
	b.w("KL3", "A2", "XTN1", take_n(), "blue")
	b.w("XTL1", take_l(), "KL3.1", "11", "brown")
	b.w("KL3.1", "14", "HL5", "X1", "brown")
	b.w("HL5", "X2", "XTN1", take_n(), "blue")

	# --- Доп. фидеры / реле (нагрузка на трассы, без >2 на порт) ---
	b.w("QF4", "2", "XT3", "3", "brown")
	b.w("QF5", "2", "XT4", "1", "brown")
	b.w("XTPE", take_pe(), "XT3", "4", "green")
	b.w("XTN1", take_n(), "XT4", "2", "blue")

	b.w("QF10", "2", "KL4", "A1", "brown")
	b.w("KL4", "A2", "XT4", "3", "blue")
	b.w("QF12", "2", "KL4.1", "11", "brown")
	b.w("KL4.1", "14", "XT3", "5", "brown")

	b.w("QF11", "2", "KL5", "A1", "brown")
	b.w("KL5", "A2", "XT4", "4", "blue")
	b.w("QF13", "2", "KL5.1", "11", "brown")
	b.w("KL5.1", "14", "XT4", "5", "brown")

	# Запасные отводы на шины (по одному)
	b.w("QF6", "2", "XTL1", take_l(), "brown")
	b.w("QF7", "2", "XTN1", take_n(), "blue")
	b.w("QF8", "2", "XTPE", take_pe(), "green")

	din_n = sum(
		1 for e in b.elements
		if e.get("electro_mount") == "din" and e["electro_class"] != "din_stop"
	)
	door_n = sum(1 for e in b.elements if e.get("electro_mount") == "door")
	print(f"L {li}/{len(l_pool)}, N {ni}/{len(n_pool)}, PE {pei}/{len(pe_pool)}")
	return {
		"format": "mechsim-scene",
		"version": 1,
		"title": "Демо: плотный щит + дверца (клеммники-шины)",
		"note": (
			f"Ревью: {din_n} DIN, {door_n} door. Без busbar — XTL/XTN/XTPE как terminal_bus. "
			"Пускатель SB0/SB2/SB1+KM1+KK1; HL1–HL5; раскладка 2D полосами."
		),
		"elements": b.elements,
		"wires": b.wires,
		"next_id": max(b.next_id, b.wire_id + 1),
	}


def main() -> None:
	data = build()
	din_n = sum(
		1 for e in data["elements"]
		if e.get("electro_mount") == "din" and e["electro_class"] != "din_stop"
	)
	door_n = sum(1 for e in data["elements"] if e.get("electro_mount") == "door")
	print(f"DIN: {din_n}, door: {door_n}, els: {len(data['elements'])}, wires: {len(data['wires'])}")
	OUT.write_text(json.dumps(data, ensure_ascii=False, indent="\t"), encoding="utf-8")
	print(f"Wrote {OUT}")


if __name__ == "__main__":
	main()
