#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собрать учебные electro-сцены (.mechsim.json) для проверки симуляции."""
from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "test" / "electro_sim"
DIN_SLOTS = 38
IDENTITY_BASIS = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def din(rail: int, half: int) -> int:
	return rail * DIN_SLOTS + half


def el_base(
	*,
	eid: int,
	tag: str,
	recipe_id: str,
	electro_class: str,
	electro_mount: str,
	tag_prefix: str,
	position: list[float],
	electro_ports: list,
	**kw,
) -> dict:
	d = {
		"kind": "electro",
		"id": eid,
		"tag": tag,
		"tag_offset": [0, 0],
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
		"piston_kind": "simple",
		"cush_cap": "none",
		"cush_rod": "none",
		"cush_open_cap": 0.35,
		"cush_open_rod": 0.35,
		"spring_side": "none",
		"rod_mode": "single",
		"rod_end": "plain",
		"brake": "none",
		"port_cap": "connect",
		"port_rod": "connect",
		"carriage": "none",
		"bump_end": "none",
		"mount": "clevis",
		"guide": "none",
		"seal_leak": 0.0,
		"catalog_id": recipe_id,
		"variant_id": "ppv",
		"cushion_mm": 17.0,
		"through_rod": False,
		"body_style": "profile",
		"body_style_user": False,
		"order_code": "",
		"port_name": "G1/8",
		"rod_thread": "",
		"pressure_bar": 6.0,
		"temperature_c": 20.0,
		"world_pos": [0.0, 0.0, 0.0],
		"world_basis": IDENTITY_BASIS,
		"valve_ways": 5,
		"valve_positions": 2,
		"valve_center": "none",
		"valve_nc_no": "nc",
		"rest_pos": 0,
		"valve_pos": 0,
		"op_left": "solenoid_pilot",
		"op_right": "spring",
		"pilot_supply": "internal",
		"valve_cv": 1.0,
		"command_left": False,
		"command_right": False,
		"port_3": "muffler",
		"port_5": "muffler",
		"override_left": True,
		"override_right": True,
		"spool_envelopes": [],
		"port_mass": {},
		"port_press": {},
		"port_q": {},
		"junction_style": "tee",
		"junction_ports": 3,
		"switch_pos": 0,
		"switch_map": [],
		"switch_labels": [],
		"energized": False,
		"pressed": False,
		"lit": False,
		"timer_armed": False,
		"timer_elapsed": 0.0,
		"detached": False,
		"linked_valve_side": "",
		"door_slot": -1,
		"door_xy": [-1, -1],
		"recipe_id": recipe_id,
		"electro_class": electro_class,
		"electro_mount": electro_mount,
		"tag_prefix": tag_prefix,
		"lamp_color": "white",
		"btn_color": "white",
		"caption": "",
		"delay_on": 0.0,
		"delay_off": 0.0,
		"timer_mode": "",
		"timer_unit": 1,
		"timer_value": 0.0,
		"poles": 1,
		"curve": "C",
		"rating_a": 16.0,
		"i_delta_ma": 30.0,
		"u_min": 180.0,
		"u_max": 6.0 if electro_class in ("mcb", "rcd", "rcbo") else 260.0,
		"phase": "",
		"voltage": 230.0,
		"link_valve": False,
		"group_template": "",
		"terminal_bus": False,
		"color_id": "",
		"electro_ports": electro_ports,
		"coil_ports": [],
		"contact_defs": [],
		"switch_positions": 2,
		"latching": False,
		"closed": False,
		"member_role": "device",
		"member_index": 0,
		"group_id": -1,
		"group_tag": "",
		"din_slot": -1,
		"position": position,
		"hide_unused_contacts": False,
	}
	d.update(kw)
	return d


def wire(wid: int, a: int, ap: str, b: int, bp: str, color: str = "", mm: float = 1.5) -> dict:
	return {
		"id": wid,
		"a_id": a,
		"a_port": ap,
		"b_id": b,
		"b_port": bp,
		"id_mm": mm,
		"color_id": color,
		"num": 0,
		"sleeve_yaw_a": 0.0,
		"sleeve_yaw_b": 0.0,
		"joints": [],
	}


def scene(title: str, note: str, elements: list, wires: list, next_id: int) -> dict:
	return {
		"format": "mechsim-scene",
		"version": 1,
		"title": title,
		"note": note,
		"elements": elements,
		"wires": wires,
		"next_id": next_id,
	}


def ports_named(*names: str, typ: str = "line") -> list:
	return [{"name": n, "type": typ} for n in names]


def scene_01_lamp() -> dict:
	# XS → QF(1P) → HL → N. Нормальное свечение после включения рычага.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qf = el_base(
		eid=2, tag="QF1", recipe_id="mcb_1p", electro_class="mcb",
		electro_mount="din", tag_prefix="QF", position=[200, 40],
		electro_ports=ports_named("1", "2"),
		poles=1, rating_a=16.0, curve="C", u_max=6.0, din_slot=din(0, 2),
	)
	hl = el_base(
		eid=3, tag="HL1", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[360, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="white",
	)
	wires = [
		wire(10, 1, "L", 2, "1", "brown"),
		wire(11, 2, "2", 3, "X1", "brown"),
		wire(12, 3, "X2", 1, "N", "blue"),
	]
	return scene(
		"Симуляция 01 — лампа через АВ",
		"▶ Пуск → включить рычаг QF1 (I) → HL1 должна загореться. Сброс — АВ снова OFF.",
		[xs, qf, hl],
		wires,
		20,
	)


def scene_02_short() -> dict:
	# XS.L → QF → XS.N без нагрузки: учебное КЗ при включении АВ.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qf = el_base(
		eid=2, tag="QF1", recipe_id="mcb_1p", electro_class="mcb",
		electro_mount="din", tag_prefix="QF", position=[200, 40],
		electro_ports=ports_named("1", "2"),
		poles=1, rating_a=16.0, curve="C", u_max=6.0, din_slot=din(0, 2),
	)
	wires = [
		wire(10, 1, "L", 2, "1", "brown"),
		wire(11, 2, "2", 1, "N", "blue"),  # КЗ L–N через АВ
	]
	return scene(
		"Симуляция 02 — КЗ через АВ",
		"▶ Пуск → рычаг QF1 (I): кратко встанет в I, затем выбьет в O. Статус: «QF1: срабатывание — короткое замыкание».",
		[xs, qf],
		wires,
		20,
	)


def scene_03_rcd_ok() -> dict:
	# УЗО 1P+N: 1/2=N, 3/4=L1. Норма + проверка TEST.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qd = el_base(
		eid=2, tag="QD1", recipe_id="rcd_1pn", electro_class="rcd",
		electro_mount="din", tag_prefix="QD", position=[200, 40],
		electro_ports=ports_named("1", "2", "3", "4"),
		poles=2, rating_a=25.0, i_delta_ma=30.0, phase="AC", u_max=6.0,
		din_slot=din(0, 2),
	)
	hl = el_base(
		eid=3, tag="HL1", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[400, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="green",
	)
	wires = [
		wire(10, 1, "N", 2, "1", "blue"),   # N top
		wire(11, 1, "L", 2, "3", "brown"),  # L top
		wire(12, 2, "4", 3, "X1", "brown"),  # L load
		wire(13, 2, "2", 3, "X2", "blue"),   # N load
	]
	return scene(
		"Симуляция 03 — УЗО и лампа (норма + TEST)",
		"▶ Пуск → рычаг QD1 (I) → HL1 горит. Затем TEST на 3D/схеме → УЗО OFF, лампа гаснет. Снова I — снова горит.",
		[xs, qd, hl],
		wires,
		20,
	)


def scene_04_rcd_leak() -> dict:
	# Утечка: нагрузка L за УЗО посажена на PE-шину → учебное отключение УЗО.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qd = el_base(
		eid=2, tag="QD1", recipe_id="rcd_1pn", electro_class="rcd",
		electro_mount="din", tag_prefix="QD", position=[200, 40],
		electro_ports=ports_named("1", "2", "3", "4"),
		poles=2, rating_a=25.0, i_delta_ma=30.0, phase="AC", u_max=6.0,
		din_slot=din(0, 2),
	)
	pe = el_base(
		eid=3, tag="PE1", recipe_id="bus_bar", electro_class="busbar",
		electro_mount="din", tag_prefix="XN", position=[200, 160],
		electro_ports=ports_named("1", "2", "3", "4", "5", "6"),
		phase="PE", caption="PE", color_id="green",
		din_slot=din(1, 2), u_max=260.0,
	)
	hl = el_base(
		eid=4, tag="HL1", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[420, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="red",
	)
	wires = [
		wire(10, 1, "N", 2, "1", "blue"),
		wire(11, 1, "L", 2, "3", "brown"),
		wire(12, 2, "4", 4, "X1", "brown"),
		wire(13, 2, "2", 4, "X2", "blue"),
		wire(14, 1, "PE", 3, "1", "green"),
		# Утечка: фаза после УЗО на PE-шину.
		wire(15, 2, "4", 3, "2", "brown"),
	]
	return scene(
		"Симуляция 04 — утечка на PE (УЗО)",
		"▶ Пуск → рычаг QD1 (I): кратко I, затем выбьет. Статус: «QD1: срабатывание — утечка на PE (дифф.)». Учебная эвристика, не IΔn.",
		[xs, qd, pe, hl],
		wires,
		20,
	)


def _btn_pair(
	*,
	main_id: int,
	contact_id: int,
	tag: str,
	pos: list[float],
	recipe_id: str,
	defs: list,
	btn_color: str = "white",
) -> tuple[dict, dict]:
	tmpl = {
		"btn_no": "button_no",
		"btn_nc": "button_nc",
		"btn_no_nc": "button_dual",
		"estop_nc": "estop",
	}.get(recipe_id, "button")
	main = el_base(
		eid=main_id, tag=tag, recipe_id=recipe_id, electro_class="button",
		electro_mount="door", tag_prefix="SB", position=pos,
		electro_ports=[],
		contact_defs=defs,
		group_template=tmpl,
		member_role="main",
		member_index=0,
		group_id=main_id,
		group_tag=tag,
		btn_color=btn_color,
		u_max=260.0,
	)
	contact = el_base(
		eid=contact_id, tag=f"{tag}.1", recipe_id=recipe_id, electro_class="contact",
		electro_mount="none", tag_prefix="SB", position=[pos[0], pos[1] + 40.0],
		electro_ports=[],
		contact_defs=[d.copy() for d in defs],
		member_role="contact",
		member_index=1,
		group_id=main_id,
		group_tag=tag,
		u_max=260.0,
	)
	return main, contact


def _relay_1c_pair(*, main_id: int, contact_id: int, tag: str, pos: list[float], din_slot: int) -> tuple[dict, dict]:
	defs = [
		{"name": "11", "type": "co"},
		{"name": "12", "type": "nc"},
		{"name": "14", "type": "no"},
	]
	main = el_base(
		eid=main_id, tag=tag, recipe_id="relay_1c", electro_class="relay",
		electro_mount="din", tag_prefix="KL", position=pos,
		electro_ports=[],
		coil_ports=["A1", "A2"],
		contact_defs=defs,
		group_template="relay_1",
		member_role="main",
		member_index=0,
		group_id=main_id,
		group_tag=tag,
		voltage=230.0,
		rating_a=10.0,
		din_slot=din_slot,
		u_max=260.0,
	)
	contact = el_base(
		eid=contact_id, tag=f"{tag}.1", recipe_id="relay_1c", electro_class="contact",
		electro_mount="none", tag_prefix="KL", position=[pos[0], pos[1] + 40.0],
		electro_ports=[],
		contact_defs=[d.copy() for d in defs],
		member_role="contact",
		member_index=1,
		group_id=main_id,
		group_tag=tag,
		u_max=260.0,
	)
	return main, contact


def scene_05_button() -> dict:
	# Кнопка НО + член-контакт SB1.1 (13/14) — как из каталога.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qf = el_base(
		eid=2, tag="QF1", recipe_id="mcb_1p", electro_class="mcb",
		electro_mount="din", tag_prefix="QF", position=[180, 40],
		electro_ports=ports_named("1", "2"),
		poles=1, rating_a=16.0, curve="C", u_max=6.0, din_slot=din(0, 2),
	)
	sb = el_base(
		eid=3, tag="SB1", recipe_id="btn_no", electro_class="button",
		electro_mount="door", tag_prefix="SB", position=[320, 40],
		electro_ports=[],
		contact_defs=[{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		group_template="button_no",
		member_role="main",
		member_index=0,
		group_id=3,
		group_tag="SB1",
		btn_color="white",
		u_max=260.0,
	)
	# Порты 13/14 живут на члене-контакте, не на актуаторе.
	sb_c = el_base(
		eid=4, tag="SB1.1", recipe_id="btn_no", electro_class="contact",
		electro_mount="none", tag_prefix="SB", position=[320, 80],
		electro_ports=[],
		contact_defs=[{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		group_template="",
		member_role="contact",
		member_index=1,
		group_id=3,
		group_tag="SB1",
		u_max=260.0,
	)
	hl = el_base(
		eid=5, tag="HL1", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[480, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="yellow",
	)
	wires = [
		wire(10, 1, "L", 2, "1", "brown"),
		wire(11, 2, "2", 4, "13", "brown"),  # к контакту SB1.1
		wire(12, 4, "14", 5, "X1", "brown"),
		wire(13, 5, "X2", 1, "N", "blue"),
	]
	return scene(
		"Симуляция 05 — кнопка и лампа",
		"▶ Пуск → рычаг QF1 (I) → зажать SB1 → HL1 горит, отпустить — гаснет. Моментная кнопка (контакт SB1.1).",
		[xs, qf, sb, sb_c, hl],
		wires,
		20,
	)


def scene_06_relay_or() -> dict:
	# SB1 ИЛИ SB2 → катушка KL; HL зел. на НО, красн. на НЗ.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qf = el_base(
		eid=2, tag="QF1", recipe_id="mcb_1p", electro_class="mcb",
		electro_mount="din", tag_prefix="QF", position=[160, 40],
		electro_ports=ports_named("1", "2"),
		poles=1, rating_a=16.0, curve="C", u_max=6.0, din_slot=din(0, 2),
	)
	sb1, sb1c = _btn_pair(
		main_id=3, contact_id=4, tag="SB1", pos=[280, 20],
		recipe_id="btn_no",
		defs=[{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		btn_color="green",
	)
	sb2, sb2c = _btn_pair(
		main_id=5, contact_id=6, tag="SB2", pos=[280, 140],
		recipe_id="btn_no",
		defs=[{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		btn_color="green",
	)
	kl, klc = _relay_1c_pair(
		main_id=7, contact_id=8, tag="KL1", pos=[420, 80], din_slot=din(0, 8),
	)
	hl_g = el_base(
		eid=9, tag="HL_NO", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[580, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="green", caption="НО",
	)
	hl_r = el_base(
		eid=10, tag="HL_NC", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[580, 140],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="red", caption="НЗ",
	)
	wires = [
		wire(20, 1, "L", 2, "1", "brown"),
		wire(21, 2, "2", 4, "13", "brown"),  # фаза → SB1
		wire(22, 2, "2", 8, "11", "brown"),  # фаза → COM реле
		wire(23, 4, "13", 6, "13", "brown"),  # та же фаза → SB2
		wire(24, 4, "14", 7, "A1", "brown"),  # SB1 → катушка
		wire(25, 6, "14", 7, "A1", "brown"),  # SB2 → катушка (ИЛИ)
		wire(26, 7, "A2", 1, "N", "blue"),
		wire(27, 8, "14", 9, "X1", "brown"),  # НО → зел.
		wire(28, 9, "X2", 1, "N", "blue"),
		wire(29, 8, "12", 10, "X1", "brown"),  # НЗ → красн.
		wire(30, 10, "X2", 1, "N", "blue"),
	]
	return scene(
		"Симуляция 06 — реле, логика ИЛИ",
		"▶ Пуск → QF1=I. Покой: HL_NC (красн.). Зажать SB1 или SB2 → KL1, HL_NO (зел.), красн. гаснет. Отпустить — снова красн.",
		[xs, qf, sb1, sb1c, sb2, sb2c, kl, klc, hl_g, hl_r],
		wires,
		40,
	)


def scene_07_relay_latch() -> dict:
	# Пуск НО + стоп НЗ + самоподхват НО реле; индикация НО/НЗ лампами.
	xs = el_base(
		eid=1, tag="XS1", recipe_id="supply_1ph", electro_class="supply",
		electro_mount="none", tag_prefix="XS", position=[40, 40],
		electro_ports=ports_named("L", "N", "PE", typ="source"),
		voltage=230.0, poles=1, u_max=260.0,
	)
	qf = el_base(
		eid=2, tag="QF1", recipe_id="mcb_1p", electro_class="mcb",
		electro_mount="din", tag_prefix="QF", position=[160, 40],
		electro_ports=ports_named("1", "2"),
		poles=1, rating_a=16.0, curve="C", u_max=6.0, din_slot=din(0, 2),
	)
	sb_stop, sb_stop_c = _btn_pair(
		main_id=3, contact_id=4, tag="SB_STOP", pos=[280, 20],
		recipe_id="btn_nc",
		defs=[{"name": "11", "type": "nc"}, {"name": "12", "type": "nc"}],
		btn_color="red",
	)
	sb_start, sb_start_c = _btn_pair(
		main_id=5, contact_id=6, tag="SB_START", pos=[280, 140],
		recipe_id="btn_no",
		defs=[{"name": "13", "type": "no"}, {"name": "14", "type": "no"}],
		btn_color="green",
	)
	kl, klc = _relay_1c_pair(
		main_id=7, contact_id=8, tag="KL1", pos=[420, 80], din_slot=din(0, 8),
	)
	hl_g = el_base(
		eid=9, tag="HL_NO", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[580, 40],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="green", caption="НО / RUN",
	)
	hl_r = el_base(
		eid=10, tag="HL_NC", recipe_id="lamp", electro_class="lamp",
		electro_mount="door", tag_prefix="HL", position=[580, 140],
		electro_ports=ports_named("X1", "X2"),
		voltage=220.0, lamp_color="red", caption="НЗ / STOP",
	)
	wires = [
		wire(20, 1, "L", 2, "1", "brown"),
		wire(21, 2, "2", 4, "11", "brown"),  # на стоп НЗ
		wire(22, 4, "12", 6, "13", "brown"),  # после стопа → пуск
		wire(23, 4, "12", 8, "11", "brown"),  # после стопа → COM
		wire(24, 6, "14", 7, "A1", "brown"),  # пуск → катушка
		wire(25, 8, "14", 7, "A1", "brown"),  # самоподхват НО → катушка
		wire(26, 7, "A2", 1, "N", "blue"),
		wire(27, 8, "14", 9, "X1", "brown"),  # НО → зел. (2-й на 14)
		wire(28, 9, "X2", 1, "N", "blue"),
		wire(29, 8, "12", 10, "X1", "brown"),  # НЗ → красн.
		wire(30, 10, "X2", 1, "N", "blue"),
	]
	return scene(
		"Симуляция 07 — реле, самоподхват",
		"▶ Пуск → QF1=I. Покой: HL_NC красн. Импульс SB_START → KL держится, HL_NO зел. SB_STOP → сброс, снова красн.",
		[xs, qf, sb_stop, sb_stop_c, sb_start, sb_start_c, kl, klc, hl_g, hl_r],
		wires,
		40,
	)


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	scenes = [
		("01_lamp_ok.mechsim.json", scene_01_lamp()),
		("02_short_trip.mechsim.json", scene_02_short()),
		("03_rcd_ok_test.mechsim.json", scene_03_rcd_ok()),
		("04_rcd_pe_leak.mechsim.json", scene_04_rcd_leak()),
		("05_button_lamp.mechsim.json", scene_05_button()),
		("06_relay_or.mechsim.json", scene_06_relay_or()),
		("07_relay_latch.mechsim.json", scene_07_relay_latch()),
	]
	readme_lines = [
		"# Учебные сцены электрики (симуляция)",
		"",
		"Открыть: **Файл → Открыть** → файлы в этой папке (`.mechsim.json`).",
		"",
		"После загрузки АВ/УЗО всегда в **OFF** — сначала ▶ Пуск, затем рычаг **I**.",
		"",
		"| Файл | Что проверяет | Ожидание |",
		"|------|---------------|----------|",
	]
	titles = {
		"01_lamp_ok.mechsim.json": ("лампа через АВ", "HL1 горит при QF=I"),
		"02_short_trip.mechsim.json": ("КЗ L–N через АВ", "рычаг I → выбивает O + статус «КЗ»"),
		"03_rcd_ok_test.mechsim.json": ("УЗО + лампа + TEST", "горит; TEST → OFF"),
		"04_rcd_pe_leak.mechsim.json": ("утечка на PE", "УЗО отключается при I"),
		"05_button_lamp.mechsim.json": ("кнопка + лампа", "горит только при нажатии SB"),
		"06_relay_or.mechsim.json": ("реле ИЛИ (SB1∨SB2)", "зел. при любой кнопке; красн. в покое"),
		"07_relay_latch.mechsim.json": ("реле самоподхват", "START держит; STOP сбрасывает; зел/красн"),
	}
	for name, data in scenes:
		path = OUT / name
		path.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
		print("wrote", path)
		t, exp = titles[name]
		readme_lines.append(f"| `{name}` | {t} | {exp} |")
	readme_lines += [
		"",
		"Модель учебная (связность узлов): без реального IΔn/Icu и токов по сечению.",
		"См. `scripts/domain/electrical_network.gd`.",
		"",
	]
	(OUT / "README.md").write_text("\n".join(readme_lines), encoding="utf-8")
	print("wrote", OUT / "README.md")


if __name__ == "__main__":
	main()
