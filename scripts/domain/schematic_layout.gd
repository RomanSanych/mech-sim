extends RefCounted
## Авторазводка 2D-схемы: релейная логика (L/+ слева, N/−/PE справа) + меньше крестов.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")

const GRID := 10.0
const W_CROSS := 95.0
const W_BEND := 6.0
const W_ELHIT := 55.0
const W_OVERLAP := 180.0
const W_WIRE_NEAR := 40.0
const W_SPAN := 0.008
const W_FACE := 28.0
const W_RAIL := 12.0
const NUDGE_STEPS := [1, 2, 3, 4, 6, 8, 10, 12, 16]
## Зазор при раздвижении наложений (датчик / БП крупнее типового УГО).
const OVERLAP_PUSH := 5.0
## Колонки релейной раскладки (мир схемы, шаг GRID).
const RELAY_X_POWER := 60.0
const RELAY_X_LEFT := 220.0
const RELAY_X_CTRL0 := 300.0
const RELAY_X_RIGHT := 780.0
const RELAY_X_PE := 880.0
const RELAY_Y0 := 40.0
const RELAY_RUNG := 70.0
const RELAY_CTRL_STEP := 80.0
## АВ/УЗО: 90° CW — tip↑ становится вправо, tip↓ влево (гориз. цепь).
const BREAKER_LAY_ROT := 1


static func arrange(circuit) -> Dictionary:
	## {ok, moved, score_before, score_after}
	if circuit == null:
		return {"ok": false, "moved": 0, "score_before": 0.0, "score_after": 0.0}
	_clear_joints(circuit)
	WireRouter2D.invalidate()
	var n_el: int = circuit.elements.size() if circuit.elements != null else 0
	var do_full_score: bool = n_el <= 40
	var before: float = score(circuit) if do_full_score else 0.0
	var snapshot: Array = _snapshot_pose(circuit)
	var moved: int = 0
	# Релейный seed: рельсы L/+ | цепи | N/−/PE + отцепление контактов как у юзера.
	moved += _seed_relay_layout(circuit)
	moved += _resolve_overlaps(circuit)
	moved += _resolve_overlaps(circuit)
	# Полный score-optimize — только на компактных схемах (иначе минуты на dense).
	if do_full_score:
		moved += _optimize_symmetric_ports(circuit)
		moved += _hill_climb(circuit)
		moved += _optimize_symmetric_ports(circuit)
		moved += _hill_climb(circuit)
	else:
		moved += _flip_symmetric_by_rails(circuit)
		moved += _nudge_rung_align(circuit)
	moved += _resolve_overlaps(circuit)
	# Финал: сила сверху → столбец катушек → N правее столбца (align до reseat).
	var rails_fin: Dictionary = _classify_rails(circuit)
	moved += _reseat_power_band(circuit, rails_fin)
	moved += _align_coil_column(circuit, rails_fin)
	moved += _reseat_rails_flanking_control(circuit, rails_fin)
	moved += _clamp_control_inside_rails(circuit, rails_fin)
	moved += _resolve_overlaps(circuit)
	moved += _reseat_power_band(circuit, rails_fin)
	moved += _align_coil_column(circuit, rails_fin)
	moved += _reseat_rails_flanking_control(circuit, rails_fin)
	moved += _place_orphan_terminals(circuit, rails_fin)
	# Финал после reseat: иначе широкие клеммники снова наслаиваются.
	moved += _resolve_overlaps(circuit)
	# Ещё раз столбец катушек — overlap мог сдвинуть Y и снова посадить KL на KL.
	moved += _align_coil_column(circuit, rails_fin)
	_clear_joints(circuit)
	WireRouter2D.invalidate()
	var after: float = score(circuit) if do_full_score else float(moved)
	# Откат только на компактных: seed часто чуть хуже по score, но читаемее.
	if do_full_score and after > before + 0.5 and moved < 8:
		_restore_pose(circuit, snapshot)
		WireRouter2D.invalidate()
		after = score(circuit)
		moved = 0
	if moved > 0 and circuit.has_method("touch_scene"):
		circuit.touch_scene()
	return {
		"ok": true,
		"moved": moved,
		"score_before": before,
		"score_after": after,
	}


## Релейная раскладка: hide unused → detach → сила сверху → гориз. цепи → рельсы по краям.
static func _seed_relay_layout(circuit) -> int:
	var moved: int = 0
	# Как галочка «Скрыть неиспользуемые» в свойствах катушки/КМ/KK.
	moved += _enable_hide_unused_contacts(circuit)
	moved += _detach_wired_contacts(circuit)
	var rails: Dictionary = _classify_rails(circuit)
	# Сила — полоса сверху; АВ/УЗО повёрнуты (отростки горизонтально).
	moved += _place_power_column(circuit, rails)
	moved += _orient_vertical_port_devices(circuit)
	var y_ctrl: float = _power_band_bottom(circuit, rails) + GRID * 8.0
	moved += _place_control_rungs(circuit, rails, y_ctrl)
	# Столбец катушек, затем L/N по краям (align до reseat — иначе N впритык).
	moved += _align_coil_column(circuit, rails)
	moved += _reseat_rails_flanking_control(circuit, rails)
	moved += _clamp_control_inside_rails(circuit, rails)
	moved += _place_orphan_terminals(circuit, rails)
	moved += _place_field_band(circuit, rails)
	WireRouter2D.invalidate()
	return moved


## АВ/УЗО обратно в верхнюю силовую полосу (overlap не должен тащить их в лестницу).
static func _reseat_power_band(circuit, rails: Dictionary) -> int:
	return _place_power_column(circuit, rails)


## Тепловое / приборы с tip↑↓ — на 90°, чтобы жилы шли горизонтально (как R у юзера).
static func _orient_vertical_port_devices(circuit) -> int:
	var n: int = 0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) == "contact":
			continue
		var cls: String = str(el.electro_class)
		if cls not in ["thermal", "mcb", "rcd", "rcbo"]:
			continue
		if int(el.rotation_quad) == BREAKER_LAY_ROT:
			continue
		_set_rot_with_group(circuit, el, BREAKER_LAY_ROT)
		n += 1
	return n


## То же, что юзер включает в свойствах: скрыть контакты без проводов (кроме первого).
static func _enable_hide_unused_contacts(circuit) -> int:
	var n: int = 0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) == "contact":
			continue
		var cls: String = str(el.electro_class)
		if cls not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			continue
		if bool(el.hide_unused_contacts):
			continue
		var unused: bool = false
		var gid: int = int(el.group_id) if int(el.group_id) >= 0 else int(el.id)
		for m in circuit.electro_group_members(gid):
			if str(m.member_role) != "contact":
				continue
			if ElectroLib.is_coil_first_contact(circuit, m):
				continue
			if ElectroLib.is_button_fixed_contact(circuit, m):
				continue
			if not ElectroLib.contact_has_any_wire(circuit, m):
				unused = true
				break
		if unused:
			el.hide_unused_contacts = true
			n += 1
	return n


## То же, что юзер делает мышкой: контакт с проводом вне столбика группы → detached.
static func _detach_wired_contacts(circuit) -> int:
	var n: int = 0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) != "contact":
			continue
		if ElectroLib.is_button_fixed_contact(circuit, el):
			continue
		# Уже скрытые «неиспользуемые» не трогаем.
		if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		if not ElectroLib.contact_has_any_wire(circuit, el):
			continue
		if not bool(el.detached):
			el.detached = true
			n += 1
	if n > 0 and circuit.has_method("renumber_tags"):
		circuit.renumber_tags()
	return n


static func _power_band_bottom(circuit, rails: Dictionary) -> float:
	var rail_set: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv in rails.get(key, []) as Array:
			rail_set[int(idv)] = true
	var bottom: float = RELAY_Y0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if rail_set.has(int(el.id)):
			continue
		if str(el.electro_class) not in ["mcb", "rcd", "rcbo", "psu", "supply"]:
			continue
		var b: Rect2 = Geom.world_bounds(el)
		bottom = maxf(bottom, b.position.y + b.size.y)
	return bottom


## left / right / pe — id клеммников и вводов, образующих «рельсы» потенциала.
static func _classify_rails(circuit) -> Dictionary:
	var left: Array = []
	var right: Array = []
	var pe: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		var side: String = _rail_side_of(circuit, el)
		if side == "left":
			left.append(int(el.id))
		elif side == "right":
			right.append(int(el.id))
		elif side == "pe":
			pe.append(int(el.id))
	return {"left": left, "right": right, "pe": pe}


static func _rail_side_of(circuit, el) -> String:
	var cls: String = str(el.electro_class)
	var tag: String = str(el.tag).to_upper()
	var phase: String = str(el.phase).to_upper()
	if cls == "supply":
		return "left"
	if cls == "supply_leg":
		# Только отцепленные — иначе arrange утащит ноги из столбика XS.
		if not bool(el.detached):
			return ""
		if phase in ["PE", "GREEN"] or tag.find("PE") >= 0:
			return "pe"
		if phase in ["N", "0", "-", "BLUE"] or tag.find(".N") >= 0 or tag.ends_with("N"):
			return "right"
		if phase in ["L", "L1", "L2", "L3", "+", "+24", "BROWN"] or tag.find(".L") >= 0:
			return "left"
		return "left"
	if cls == "busbar":
		if phase in ["PE", "GREEN"] or tag.find("PE") >= 0:
			return "pe"
		if phase in ["N", "0", "-", "BLUE"] or tag.find("XTN") >= 0 or tag.ends_with("N"):
			return "right"
		if phase in ["L", "L1", "L2", "L3", "+", "+24", "BROWN"] or tag.find("XTL") >= 0:
			return "left"
	if cls == "terminal":
		if phase in ["PE", "GREEN"] or tag.find("PE") >= 0:
			return "pe"
		if phase in ["N", "0", "-", "BLUE"] or tag.find("XTN") >= 0:
			return "right"
		if phase in ["L", "L1", "L2", "L3", "+", "+24", "BROWN"] or tag.find("XTL") >= 0:
			return "left"
		# Без phase — по связи со вводом L/N/PE.
		var via: String = _terminal_supply_hint(circuit, el)
		if via != "":
			return via
		# По доминирующему color_id на проводах клеммы.
		var col_side: String = _terminal_color_hint(circuit, el)
		if col_side != "":
			return col_side
	return ""


static func _terminal_supply_hint(circuit, el) -> String:
	for w in circuit.wires:
		var other = null
		var oport: String = ""
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
			oport = str(w.b_port)
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
			oport = str(w.a_port)
		else:
			continue
		if other == null or str(other.electro_class) != "supply":
			continue
		var pn: String = oport.to_upper()
		if pn == "PE":
			return "pe"
		if pn in ["N", "0", "-"]:
			return "right"
		if pn in ["L", "L1", "L2", "L3", "+", "+24"]:
			return "left"
	return ""


static func _terminal_color_hint(circuit, el) -> String:
	var brown: int = 0
	var blue: int = 0
	var green: int = 0
	for w in circuit.wires:
		if int(w.a_id) != int(el.id) and int(w.b_id) != int(el.id):
			continue
		var cid: String = str(w.color_id)
		if cid in ["brown", "black"]:
			brown += 1
		elif cid in ["blue", "lightblue"]:
			blue += 1
		elif cid in ["green", "pe"]:
			green += 1
	if green > brown and green > blue:
		return "pe"
	if blue > brown:
		return "right"
	if brown > 0:
		return "left"
	return ""


static func _stack_ids(circuit, ids: Array, x: float, y0: float, gap: float) -> int:
	if ids.is_empty():
		return 0
	var els: Array = []
	for idv in ids:
		var el = circuit.get_element(int(idv))
		if el != null:
			els.append(el)
	els.sort_custom(func(a, b): return float(a.position.y) < float(b.position.y))
	var moved: int = 0
	var y: float = y0
	for el in els:
		var bb: Rect2 = Geom.world_bounds(el)
		var half_h: float = maxf(bb.size.y * 0.5, GRID * 2.0)
		# Место под tag над клеммником (рисуется выше bbox тела).
		var tag_pad: float = GRID * 3.0 if str(el.electro_class) == "terminal" else 0.0
		var want: Vector2 = Vector2(x, y + half_h + tag_pad).snapped(Vector2(GRID, GRID))
		if want.distance_squared_to(el.position) > 0.25:
			_set_pos_with_group(circuit, el, want)
			moved += 1
		# Клеммник-шина: без поворота; вертикальный столбик.
		if str(el.electro_class) in ["terminal", "busbar", "supply"]:
			if int(el.rotation_quad) != 0:
				_set_rot_with_group(circuit, el, 0)
				moved += 1
		y += half_h * 2.0 + tag_pad + gap
	return moved


## Макс. полуширина УГО по id (центр → край).
static func _max_half_w(circuit, ids: Array) -> float:
	var hw: float = GRID * 4.0
	for idv in ids:
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		hw = maxf(hw, Geom.world_bounds(el).size.x * 0.5)
	return hw


## L/+ левее bbox гориз. цепей; N/−/PE — правее (только средствами расстановки УГО).
static func _reseat_rails_flanking_control(circuit, rails: Dictionary) -> int:
	var rail_set: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv in rails.get(key, []) as Array:
			rail_set[int(idv)] = true
	var min_x: float = 1.0e9
	var max_x: float = -1.0e9
	var min_y: float = 1.0e9
	var any: bool = false
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if rail_set.has(int(el.id)):
			continue
		if str(el.electro_class) in ["mcb", "rcd", "rcbo", "psu"]:
			continue
		if str(el.member_role) == "contact" and not bool(el.detached):
			continue
		if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var cls: String = str(el.electro_class)
		if cls not in ["contact", "lamp", "relay", "timer_relay", "contactor", "thermal",
				"voltage_relay", "button", "e_stop", "switch", "solenoid_coil"]:
			continue
		var b: Rect2 = Geom.world_bounds(el)
		min_x = minf(min_x, b.position.x)
		max_x = maxf(max_x, b.position.x + b.size.x)
		min_y = minf(min_y, b.position.y)
		any = true
	var left_ids: Array = rails.get("left", []) as Array
	var right_ids: Array = rails.get("right", []) as Array
	var pe_ids: Array = rails.get("pe", []) as Array
	# Клеммник в один ряд — широкий: колонки L/N/PE по реальной полуширине.
	var left_hw: float = _max_half_w(circuit, left_ids)
	var right_hw: float = _max_half_w(circuit, right_ids)
	var pe_hw: float = _max_half_w(circuit, pe_ids)
	var flank: float = GRID * 4.0
	var left_x: float = RELAY_X_LEFT
	var right_x: float = RELAY_X_RIGHT
	var pe_x: float = RELAY_X_PE
	var y0: float = RELAY_Y0
	if any:
		# Правый край L ≤ min_x − flank; левый край N ≥ max_x + flank.
		left_x = snappedf(min_x - flank - left_hw, GRID)
		right_x = snappedf(max_x + flank + right_hw, GRID)
		y0 = snappedf(min_y, GRID)
	else:
		left_x = snappedf(RELAY_X_LEFT, GRID)
		right_x = snappedf(maxf(RELAY_X_RIGHT, left_x + left_hw + flank + right_hw), GRID)
	# N и PE не наслаивать (раньше gap=12 клеток хватало узкой таблице).
	pe_x = snappedf(right_x + right_hw + flank + pe_hw, GRID)
	if left_x + left_hw + flank > right_x - right_hw:
		var need: float = left_hw + flank + right_hw
		var mid: float = snappedf((left_x + right_x) * 0.5, GRID)
		left_x = snappedf(mid - need * 0.5, GRID)
		right_x = snappedf(mid + need * 0.5, GRID)
		pe_x = snappedf(right_x + right_hw + flank + pe_hw, GRID)
	var moved: int = 0
	moved += _stack_ids(circuit, left_ids, left_x, y0, GRID * 6.0)
	moved += _stack_ids(circuit, right_ids, right_x, y0, GRID * 6.0)
	moved += _stack_ids(circuit, pe_ids, pe_x, y0, GRID * 6.0)
	return moved


## Силовая полоса сверху: АВ/УЗО повёрнуты на 90° — отростки влево/вправо (гориз. цепь).
static func _place_power_column(circuit, rails: Dictionary) -> int:
	var rail_set: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv in rails.get(key, []) as Array:
			rail_set[int(idv)] = true
	var power: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if rail_set.has(int(el.id)):
			continue
		if str(el.member_role) == "contact":
			continue
		var cls: String = str(el.electro_class)
		if cls in ["mcb", "rcd", "rcbo", "psu"]:
			power.append(el)
	power.sort_custom(func(a, b):
		if absf(float(a.position.y) - float(b.position.y)) > 1.0:
			return float(a.position.y) < float(b.position.y)
		return float(a.position.x) < float(b.position.x)
	)
	var moved: int = 0
	var y: float = RELAY_Y0
	var x: float = RELAY_X_POWER
	for el in power:
		var cls2: String = str(el.electro_class)
		# АВ/УЗО: порты на горизонталь (rot=1, как юзер жмёт R).
		if cls2 in ["mcb", "rcd", "rcbo"]:
			if int(el.rotation_quad) != BREAKER_LAY_ROT:
				_set_rot_with_group(circuit, el, BREAKER_LAY_ROT)
				moved += 1
		elif int(el.rotation_quad) != 0:
			_set_rot_with_group(circuit, el, 0)
			moved += 1
		var half_h: float = maxf(Geom.world_bounds(el).size.y * 0.5, GRID * 4.0)
		var half_w: float = maxf(Geom.world_bounds(el).size.x * 0.5, GRID * 4.0)
		var want: Vector2 = Vector2(x + half_w, y + half_h).snapped(Vector2(GRID, GRID))
		if want.distance_squared_to(el.position) > 0.25:
			_set_pos_with_group(circuit, el, want)
			moved += 1
		x += half_w * 2.0 + GRID * 6.0
		if x > RELAY_X_POWER + GRID * 90.0:
			x = RELAY_X_POWER
			y += half_h * 2.0 + GRID * 6.0
	return moved


## Катушки/контакты/лампы строго между L и N (не правее XTN / не левее XTL).
static func _clamp_control_inside_rails(circuit, rails: Dictionary) -> int:
	var left_edge: float = RELAY_X_LEFT
	var right_edge: float = RELAY_X_RIGHT
	var nl: int = 0
	var nr: int = 0
	for idv in rails.get("left", []) as Array:
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		var b: Rect2 = Geom.world_bounds(el)
		left_edge = b.position.x + b.size.x if nl == 0 else maxf(left_edge, b.position.x + b.size.x)
		nl += 1
	for idv2 in rails.get("right", []) as Array:
		var el2 = circuit.get_element(int(idv2))
		if el2 == null:
			continue
		var b2: Rect2 = Geom.world_bounds(el2)
		right_edge = b2.position.x if nr == 0 else minf(right_edge, b2.position.x)
		nr += 1
	for idv3 in rails.get("pe", []) as Array:
		var el3 = circuit.get_element(int(idv3))
		if el3 == null:
			continue
		var b3: Rect2 = Geom.world_bounds(el3)
		right_edge = minf(right_edge, b3.position.x)
	if nl < 1 or nr < 1:
		return 0
	var x_lo: float = left_edge + GRID * 4.0
	var x_hi: float = right_edge - GRID * 4.0
	if x_hi <= x_lo + GRID * 4.0:
		return 0
	var moved: int = 0
	var rail_set: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv4 in rails.get(key, []) as Array:
			rail_set[int(idv4)] = true
	for el4 in circuit.elements:
		if el4 == null or str(el4.kind) != "electro":
			continue
		if rail_set.has(int(el4.id)):
			continue
		var cls: String = str(el4.electro_class)
		if cls in ["mcb", "rcd", "rcbo", "psu", "supply"]:
			continue
		if str(el4.member_role) == "contact" and not bool(el4.detached):
			continue
		if cls not in ["contact", "lamp", "relay", "timer_relay", "contactor", "thermal",
				"voltage_relay", "button", "e_stop", "switch", "solenoid_coil"]:
			continue
		var bb: Rect2 = Geom.world_bounds(el4)
		var cx: float = bb.get_center().x
		var want_x: float = clampf(cx, x_lo + bb.size.x * 0.5, x_hi - bb.size.x * 0.5)
		if absf(want_x - float(el4.position.x)) < 0.5:
			continue
		var want: Vector2 = Vector2(want_x, el4.position.y).snapped(Vector2(GRID, GRID))
		_set_pos_with_group(circuit, el4, want)
		moved += 1
	return moved


## Цепи управления: одна Y на ступень, порты влево/вправо, элементы слева→направо.
static func _place_control_rungs(circuit, rails: Dictionary, y0: float = RELAY_Y0) -> int:
	var left_set: Dictionary = {}
	var right_set: Dictionary = {}
	for idv in rails.get("left", []) as Array:
		left_set[int(idv)] = true
	for idv in rails.get("right", []) as Array:
		right_set[int(idv)] = true
	for idv in rails.get("pe", []) as Array:
		right_set[int(idv)] = true
	if left_set.is_empty() or right_set.is_empty():
		return _place_control_fallback(circuit, rails, y0)
	var adj: Dictionary = _elec_adjacency(circuit)
	var rungs: Array = _extract_control_rungs(circuit, adj, left_set, right_set)
	if rungs.is_empty():
		return _place_control_fallback(circuit, rails, y0)
	var moved: int = 0
	var placed: Dictionary = {}
	for idv in left_set.keys():
		placed[int(idv)] = true
	for idv in right_set.keys():
		placed[int(idv)] = true
	var y: float = y0
	for ri in rungs.size():
		var path: Array = rungs[ri] as Array
		var nodes: Array = []
		for idv2 in path:
			var eid: int = int(idv2)
			if left_set.has(eid) or right_set.has(eid):
				continue
			if placed.has(eid):
				continue
			var el = circuit.get_element(eid)
			if el == null:
				continue
			if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
				continue
			nodes.append(el)
		if nodes.is_empty():
			continue
		# Контакты/кнопки слева→направо; катушка/лампа — в конец ступени (к N).
		var series: Array = []
		var sinks: Array = []
		for el_n in nodes:
			if _is_coil_like(el_n) or str(el_n.electro_class) == "lamp":
				sinks.append(el_n)
			else:
				series.append(el_n)
		var ordered: Array = series + sinks
		var x: float = RELAY_X_CTRL0
		for el2 in ordered:
			# Горизонтальная цепь: выводы влево/вправо (АВ/тепловое — уже rot=90°).
			var cls2: String = str(el2.electro_class)
			if cls2 not in ["mcb", "rcd", "rcbo", "switch", "thermal"]:
				if int(el2.rotation_quad) != 0:
					_set_rot_with_group(circuit, el2, 0)
					moved += 1
			var half_w: float = maxf(Geom.world_bounds(el2).size.x * 0.5, GRID * 3.0)
			var want: Vector2 = Vector2(x + half_w, y).snapped(Vector2(GRID, GRID))
			if want.distance_squared_to(el2.position) > 0.25:
				_set_pos_with_group(circuit, el2, want)
				moved += 1
			placed[int(el2.id)] = true
			if str(el2.member_role) == "contact":
				moved += _place_button_actuator_near(circuit, el2, want, placed)
			x = want.x + half_w + GRID * 5.0
		y += RELAY_RUNG
	moved += _place_leftover_control(circuit, placed, y, rails)
	return moved


## Катушки/лампы в один столбец у правого рельса (как KM на РКС).
## Bbox катушки + неотнесённых видимых контактов (иначе overlap видит только корпус ~2×1 клетки).
static func _coil_group_bounds(circuit, el) -> Rect2:
	if el == null:
		return Rect2()
	if _is_coil_like(el) and str(el.member_role) != "contact":
		var gid: int = int(el.group_id) if int(el.group_id) >= 0 else int(el.id)
		var fr: Rect2 = Geom.electro_group_frame(circuit, gid, true)
		if fr.size.x > 0.5 and fr.size.y > 0.5:
			return fr
	return Geom.world_bounds(el)


static func _align_coil_column(circuit, rails: Dictionary) -> int:
	var right_edge: float = RELAY_X_RIGHT
	var nr: int = 0
	for idv in rails.get("right", []) as Array:
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		var b: Rect2 = Geom.world_bounds(el)
		right_edge = b.position.x if nr == 0 else minf(right_edge, b.position.x)
		nr += 1
	for idv2 in rails.get("pe", []) as Array:
		var el2 = circuit.get_element(int(idv2))
		if el2 == null:
			continue
		var b2: Rect2 = Geom.world_bounds(el2)
		right_edge = minf(right_edge, b2.position.x)
	# Без правого рельса всё равно выравниваем столбец (иначе KL1/KL2 остаются внахлёст).
	var coil_x: float = snappedf(right_edge - GRID * 10.0, GRID) if nr >= 1 \
			else snappedf(RELAY_X_RIGHT - GRID * 10.0, GRID)
	var coils: Array = []
	for el3 in circuit.elements:
		if el3 == null or str(el3.kind) != "electro":
			continue
		if str(el3.member_role) == "contact":
			continue
		if not (_is_coil_like(el3) or str(el3.electro_class) == "lamp"):
			continue
		coils.append(el3)
	if coils.is_empty():
		return 0
	# Y, затем id — при одинаковом Y (одна ступень) стабильный порядок KL1→KL2.
	coils.sort_custom(func(a, b):
		var dy: float = float(a.position.y) - float(b.position.y)
		if absf(dy) > 0.5:
			return dy < 0.0
		return int(a.id) < int(b.id)
	)
	# Фиксированный шаг по центрам корпуса — не пакуем по group-bounds:
	# при hide_unused / одинаковой ступени рамки схлопывали KL1 на KL2.
	var stride: float = RELAY_RUNG
	var y0: float = snappedf(float(coils[0].position.y), GRID)
	var moved: int = 0
	for i in coils.size():
		var el3 = coils[i]
		var want_y: float = snappedf(y0 + float(i) * stride, GRID)
		var want: Vector2 = Vector2(coil_x, want_y)
		if want.distance_squared_to(el3.position) > 0.25:
			_set_pos_with_group(circuit, el3, want)
			moved += 1
		if _is_coil_like(el3):
			ElectroLib.layout_coil_contacts(circuit, el3)
	return moved


static func _place_button_actuator_near(circuit, contact, contact_pos: Vector2, placed: Dictionary) -> int:
	var primary = circuit.get_element(int(contact.group_id))
	if primary == null:
		return 0
	if str(primary.electro_class) not in ["button", "e_stop"]:
		return 0
	if placed.has(int(primary.id)):
		return 0
	var want: Vector2 = Vector2(contact_pos.x, contact_pos.y - GRID * 5.0).snapped(Vector2(GRID, GRID))
	var moved: int = 0
	if want.distance_squared_to(primary.position) > 0.25:
		_set_pos_with_group(circuit, primary, want)
		moved += 1
	placed[int(primary.id)] = true
	return moved


static func _place_leftover_control(circuit, placed: Dictionary, y0: float, rails: Dictionary) -> int:
	var left_overs: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if placed.has(int(el.id)):
			continue
		if str(el.member_role) == "contact" and not bool(el.detached):
			continue
		var cls: String = str(el.electro_class)
		if cls in ["mcb", "rcd", "rcbo", "psu", "supply", "terminal", "busbar"]:
			continue
		if cls in ["contact", "lamp", "relay", "timer_relay", "contactor", "thermal",
				"voltage_relay", "button", "e_stop", "switch", "solenoid_coil"]:
			left_overs.append(el)
	if left_overs.is_empty():
		return 0
	left_overs.sort_custom(func(a, b): return float(a.position.y) < float(b.position.y))
	var moved: int = 0
	var y: float = y0
	var x: float = RELAY_X_CTRL0
	for el in left_overs:
		var want: Vector2 = Vector2(x, y).snapped(Vector2(GRID, GRID))
		if _is_coil_like(el) or str(el.electro_class) == "lamp":
			want.x = RELAY_X_RIGHT - GRID * 10.0
		if want.distance_squared_to(el.position) > 0.25:
			_set_pos_with_group(circuit, el, want)
			moved += 1
		placed[int(el.id)] = true
		y += RELAY_RUNG * 0.85
		if y > y0 + GRID * 40.0:
			y = y0
			x += RELAY_CTRL_STEP
	return moved


static func _place_control_fallback(circuit, rails: Dictionary, y0: float = RELAY_Y0) -> int:
	# Нет явных рельсов — одна полоса управления между дефолтными X.
	var placed: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv in rails.get(key, []) as Array:
			placed[int(idv)] = true
	return _place_leftover_control(circuit, placed, y0, rails)


static func _place_field_band(circuit, _rails: Dictionary) -> int:
	# Пневмо/датчики/прочее — ниже электролестницы.
	var field: Array = []
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) == "electro" or str(el.kind) == "coil":
			continue
		field.append(el)
	if field.is_empty():
		return 0
	return _pack_row(circuit, field, RELAY_Y0 + GRID * 55.0, GRID * 10.0)


## Клеммники вне рельсов L/N/PE — в ряд с зазором по реальной ширине (не 740/840 внахлёст).
static func _place_orphan_terminals(circuit, rails: Dictionary) -> int:
	var rail_set: Dictionary = {}
	for key in ["left", "right", "pe"]:
		for idv in rails.get(key, []) as Array:
			rail_set[int(idv)] = true
	var terms: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) != "terminal":
			continue
		if rail_set.has(int(el.id)):
			continue
		terms.append(el)
	if terms.is_empty():
		return 0
	var y_band: float = RELAY_Y0 + GRID * 14.0
	for el2 in circuit.elements:
		if el2 == null or str(el2.kind) != "electro":
			continue
		if str(el2.electro_class) in ["mcb", "rcd", "rcbo", "psu"]:
			y_band = maxf(y_band, Geom.world_bounds(el2).position.y + Geom.world_bounds(el2).size.y + GRID * 4.0)
	return _pack_row(circuit, terms, snappedf(y_band, GRID), GRID * 4.0)


static func _is_coil_like(el) -> bool:
	if el == null:
		return false
	if str(el.kind) == "coil":
		return true
	var cls: String = str(el.electro_class)
	return cls in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay", "solenoid_coil"] \
			and str(el.member_role) != "contact"


## Неорграф электропроводов: id → Array[id соседей].
static func _elec_adjacency(circuit) -> Dictionary:
	var adj: Dictionary = {}
	for w in circuit.wires:
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var da: String = Geom.port_domain(a, str(w.a_port))
		var db: String = Geom.port_domain(b, str(w.b_port))
		if da != "electric" and db != "electric":
			continue
		# Силовые жилы АВ (чёрные между полюсами) не строят ступени управления.
		if _is_power_trunk_wire(a, str(w.a_port), b, str(w.b_port), str(w.color_id)):
			continue
		var aid: int = int(a.id)
		var bid: int = int(b.id)
		if not adj.has(aid):
			adj[aid] = []
		if not adj.has(bid):
			adj[bid] = []
		(adj[aid] as Array).append(bid)
		(adj[bid] as Array).append(aid)
	return adj


static func _is_power_trunk_wire(a, ap: String, b, bp: String, color_id: String) -> bool:
	# Чёрные/силовые между автоматами / силовыми полюсами КМ/KK — не ступень управления.
	var ca: String = str(a.electro_class)
	var cb: String = str(b.electro_class)
	var power_cls: Dictionary = {
		"mcb": true, "rcd": true, "rcbo": true, "contactor": true, "thermal": true,
	}
	if not power_cls.has(ca) or not power_cls.has(cb):
		return false
	if str(a.member_role) == "contact" or str(b.member_role) == "contact":
		return false
	# Катушечные порты — управление.
	if ap in ["A1", "A2"] or bp in ["A1", "A2"]:
		return false
	if color_id in ["brown", "blue", "lightblue", "green", "pe"]:
		return false
	return true


## Жадные пути left→right по рёбрам (каждое ребро один раз) → ступени лестницы.
static func _extract_control_rungs(circuit, adj: Dictionary, left_set: Dictionary, right_set: Dictionary) -> Array:
	var used: Dictionary = {} # "min:max" → true
	var rungs: Array = []
	var starts: Array = []
	for lid in left_set.keys():
		starts.append(int(lid))
	starts.sort()
	for lid in starts:
		var neighbors: Array = adj.get(int(lid), []) as Array
		var neigh_sorted: Array = neighbors.duplicate()
		neigh_sorted.sort()
		for nid in neigh_sorted:
			var ek: String = _edge_key(int(lid), int(nid))
			if used.has(ek):
				continue
			var path: Array = _walk_to_right(adj, int(lid), int(nid), right_set, used, left_set)
			if path.size() >= 2:
				rungs.append(path)
	# Стабильный порядок: по среднему Y текущих позиций.
	rungs.sort_custom(func(pa, pb):
		return _path_mean_y(circuit, pa) < _path_mean_y(circuit, pb)
	)
	return rungs


static func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _path_mean_y(circuit, path: Array) -> float:
	var s: float = 0.0
	var n: int = 0
	for idv in path:
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		s += float(el.position.y)
		n += 1
	return s / float(maxi(n, 1))


static func _walk_to_right(
	adj: Dictionary, start: int, first: int, right_set: Dictionary, used: Dictionary, left_set: Dictionary
) -> Array:
	var path: Array = [start, first]
	used[_edge_key(start, first)] = true
	var cur: int = first
	var prev: int = start
	for _step in range(48):
		if right_set.has(cur):
			return path
		var nxt: int = _pick_next_hop(adj, cur, prev, right_set, left_set, used)
		if nxt < 0:
			break
		used[_edge_key(cur, nxt)] = true
		path.append(nxt)
		prev = cur
		cur = nxt
	if right_set.has(cur):
		return path
	# Не дошли до N — всё же ступень, если есть внутренние узлы.
	if path.size() >= 3:
		return path
	return []


static func _pick_next_hop(
	adj: Dictionary, cur: int, prev: int, right_set: Dictionary, left_set: Dictionary, used: Dictionary
) -> int:
	var neighbors: Array = adj.get(cur, []) as Array
	var best: int = -1
	var best_score: int = -999999
	for nid0 in neighbors:
		var nid: int = int(nid0)
		if nid == prev:
			continue
		var ek: String = _edge_key(cur, nid)
		if used.has(ek):
			continue
		# Не возвращаться сразу на левый рельс, если есть альтернатива.
		var sc: int = 0
		if right_set.has(nid):
			sc += 100
		if left_set.has(nid):
			sc -= 50
		sc += int(nid) % 7 # лёгкая детерминированность
		if sc > best_score:
			best_score = sc
			best = nid
	return best


## Dense: развернуть 2-полюсник так, чтобы «вход» смотрел к L, «выход» к N — без score().
static func _flip_symmetric_by_rails(circuit) -> int:
	var rails: Dictionary = _classify_rails(circuit)
	var left_x: float = RELAY_X_LEFT
	var right_x: float = RELAY_X_RIGHT
	var nl: int = 0
	var nr: int = 0
	for idv in rails.get("left", []) as Array:
		var el = circuit.get_element(int(idv))
		if el != null:
			left_x += float(el.position.x)
			nl += 1
	for idv2 in rails.get("right", []) as Array:
		var el2 = circuit.get_element(int(idv2))
		if el2 != null:
			right_x += float(el2.position.x)
			nr += 1
	if nl > 0:
		left_x /= float(nl)
	if nr > 0:
		right_x /= float(nr)
	var mid: float = (left_x + right_x) * 0.5
	var changed: int = 0
	for el3 in circuit.elements:
		if el3 == null or str(el3.kind) != "electro":
			continue
		var pair: PackedStringArray = _symmetric_port_pair(el3)
		if pair.size() < 2:
			continue
		# Слева от середины — «левый» порт к L; справа — к N.
		var want_left_is_in: bool = float(el3.position.x) <= mid
		var p_left: String = str(pair[0])
		var p_right: String = str(pair[1])
		# Уже в каноне (pair[0]=лево мира)? Проверяем нормали.
		var ports: Array = Geom.ports(el3)
		if ports.size() < 2:
			continue
		var ang: float = float(el3.rotation_quad) * PI * 0.5
		var n0: Vector2 = ((ports[0] as Dictionary).get("normal", Vector2.ZERO) as Vector2).rotated(ang)
		# Если левый в мире порт — pair[0]; иначе свап имён уже в pair.
		# Хотим: провод от L приходит на p_left когда элемент слева/в цепи.
		var wires_l: Array = _wires_on_port(circuit, int(el3.id), p_left)
		var wires_r: Array = _wires_on_port(circuit, int(el3.id), p_right)
		if wires_l.is_empty() and wires_r.is_empty():
			continue
		# Если правый порт тянется к L — перевернуть.
		if _wires_touch_rail_side(circuit, wires_r, "left") and not _wires_touch_rail_side(circuit, wires_l, "left"):
			_swap_element_ports(circuit, int(el3.id), p_left, p_right)
			changed += 1
		elif _wires_touch_rail_side(circuit, wires_l, "right") and not _wires_touch_rail_side(circuit, wires_r, "right"):
			_swap_element_ports(circuit, int(el3.id), p_left, p_right)
			changed += 1
		elif want_left_is_in and n0.x > 0.5:
			# Корпус развёрнут «задом» — крутим на 180°.
			_set_rot_with_group(circuit, el3, (int(el3.rotation_quad) + 2) % 4)
			changed += 1
	WireRouter2D.invalidate()
	return changed


static func _wires_touch_rail_side(circuit, wires: Array, side: String) -> bool:
	var rails: Dictionary = _classify_rails(circuit)
	var ids: Array = rails.get(side, []) as Array
	if side == "right":
		ids = (rails.get("right", []) as Array) + (rails.get("pe", []) as Array)
	var set: Dictionary = {}
	for idv in ids:
		set[int(idv)] = true
	for w in wires:
		if set.has(int(w.a_id)) or set.has(int(w.b_id)):
			return true
		# Один прыжок через соседа (клемма ряда).
		var oa: int = int(w.a_id)
		var ob: int = int(w.b_id)
		for other_id in [oa, ob]:
			if set.has(other_id):
				return true
	return false


## Dense: лёгкий сдвиг по X к слоту цепи без полного score.
static func _nudge_rung_align(circuit) -> int:
	var rails: Dictionary = _classify_rails(circuit)
	var left_x: float = RELAY_X_LEFT
	var right_x: float = RELAY_X_RIGHT
	var nl: int = 0
	var nr: int = 0
	for idv in rails.get("left", []) as Array:
		var el = circuit.get_element(int(idv))
		if el != null:
			left_x += float(el.position.x)
			nl += 1
	for idv2 in rails.get("right", []) as Array:
		var el2 = circuit.get_element(int(idv2))
		if el2 != null:
			right_x += float(el2.position.x)
			nr += 1
	if nl > 0:
		left_x /= float(nl)
	if nr > 0:
		right_x /= float(nr)
	var moved: int = 0
	for el3 in circuit.elements:
		if el3 == null or str(el3.kind) != "electro":
			continue
		if str(el3.member_role) == "contact" and not bool(el3.detached):
			continue
		var cls: String = str(el3.electro_class)
		if cls in ["terminal", "busbar", "supply", "mcb", "rcd", "rcbo", "psu"]:
			continue
		var x: float = float(el3.position.x)
		var want_x: float = x
		# Катушки/лампы — у правого рельса, но слева от него (не за XTN).
		if _is_coil_like(el3) or cls == "lamp":
			want_x = clampf(x, left_x + GRID * 10.0, right_x - GRID * 8.0)
			want_x = maxf(want_x, right_x - GRID * 16.0)
		elif cls in ["contact", "button", "e_stop", "switch"]:
			want_x = clampf(x, left_x + GRID * 6.0, right_x - GRID * 16.0)
		if absf(want_x - x) < GRID * 0.5:
			continue
		var want: Vector2 = Vector2(want_x, el3.position.y).snapped(Vector2(GRID, GRID))
		_set_pos_with_group(circuit, el3, want)
		moved += 1
	WireRouter2D.invalidate()
	return moved


static func _pack_row(circuit, els: Array, y_band: float, min_gap: float) -> int:
	if els.is_empty():
		return 0
	els.sort_custom(func(a, b): return float(a.position.x) < float(b.position.x))
	var moved: int = 0
	var cursor_x: float = GRID * 4.0
	for el in els:
		var half_w: float = maxf(Geom.world_bounds(el).size.x * 0.5, GRID * 3.0)
		var want: Vector2 = Vector2(cursor_x + half_w, y_band).snapped(Vector2(GRID, GRID))
		if want.distance_squared_to(el.position) > 0.25:
			_set_pos_with_group(circuit, el, want)
			moved += 1
		cursor_x = want.x + half_w + min_gap
	WireRouter2D.invalidate()
	return moved


static func _snapshot_pose(circuit) -> Array:
	var out: Array = []
	for el in circuit.elements:
		out.append({
			"id": int(el.id),
			"pos": el.position,
			"rot": int(el.rotation_quad),
			"detached": bool(el.detached),
		})
	var wires_snap: Array = []
	for w in circuit.wires:
		wires_snap.append({
			"id": int(w.id),
			"ap": str(w.a_port),
			"bp": str(w.b_port),
		})
	return [out, wires_snap]


static func _restore_pose(circuit, snap: Array) -> void:
	if snap.size() < 2:
		return
	var els: Array = snap[0] as Array
	var by_id: Dictionary = {}
	for item in els:
		by_id[int(item["id"])] = item
	for el in circuit.elements:
		var item = by_id.get(int(el.id), null)
		if item == null:
			continue
		el.position = item["pos"]
		el.rotation_quad = int(item["rot"])
		if item.has("detached"):
			el.detached = bool(item["detached"])
	var wby: Dictionary = {}
	for item in snap[1] as Array:
		wby[int(item["id"])] = item
	for w in circuit.wires:
		var wi = wby.get(int(w.id), null)
		if wi == null:
			continue
		w.a_port = str(wi["ap"])
		w.b_port = str(wi["bp"])


static func score(circuit) -> float:
	if circuit == null:
		return 1.0e9
	WireRouter2D.prepare(circuit)
	var paths: Array = []
	for wire in circuit.wires:
		paths.append(WireRouter2D.path_for(circuit, wire))
	WireRouter2D.end_batch()
	var s: float = 0.0
	s += W_OVERLAP * _element_overlap(circuit)
	s += W_CROSS * float(_wire_crossings(paths))
	s += W_BEND * float(_wire_bends(paths))
	s += W_ELHIT * _wire_element_hits(circuit, paths)
	s += W_WIRE_NEAR * _wire_nearness(paths)
	s += W_SPAN * _span_cost(circuit)
	s += W_FACE * _port_face_mismatch(circuit)
	s += W_RAIL * _rail_side_mismatch(circuit)
	return s


## Штраф: L/+ должны быть левее N/−/PE (релейные рельсы).
static func _rail_side_mismatch(circuit) -> float:
	var rails: Dictionary = _classify_rails(circuit)
	var cost: float = 0.0
	var left_xs: Array = []
	var right_xs: Array = []
	for idv in rails.get("left", []) as Array:
		var el = circuit.get_element(int(idv))
		if el != null:
			left_xs.append(float(el.position.x))
	for idv in rails.get("right", []) as Array:
		var el2 = circuit.get_element(int(idv))
		if el2 != null:
			right_xs.append(float(el2.position.x))
	for idv2 in rails.get("pe", []) as Array:
		var el3 = circuit.get_element(int(idv2))
		if el3 != null:
			right_xs.append(float(el3.position.x))
	if left_xs.is_empty() or right_xs.is_empty():
		return 0.0
	var left_max: float = left_xs[0]
	for x in left_xs:
		left_max = maxf(left_max, float(x))
	var right_min: float = right_xs[0]
	for x2 in right_xs:
		right_min = minf(right_min, float(x2))
	if left_max >= right_min - GRID * 2.0:
		cost += (left_max - right_min + GRID * 2.0) / GRID
	return cost


static func _clear_joints(circuit) -> void:
	for wire in circuit.wires:
		wire.joints = []


## НО-контакт кнопки / лампа: стороны взаимозаменяемы — выбрать разводку с лучшей оценкой.
static func _optimize_symmetric_ports(circuit) -> int:
	var changed: int = 0
	for el in circuit.elements:
		if str(el.kind) != "electro":
			continue
		var pair: PackedStringArray = _symmetric_port_pair(el)
		if pair.size() < 2:
			continue
		var p_left: String = str(pair[0])
		var p_right: String = str(pair[1])
		var wires_l: Array = _wires_on_port(circuit, int(el.id), p_left)
		var wires_r: Array = _wires_on_port(circuit, int(el.id), p_right)
		if wires_l.is_empty() and wires_r.is_empty():
			continue
		var before: float = score(circuit)
		_swap_element_ports(circuit, int(el.id), p_left, p_right)
		WireRouter2D.invalidate()
		var after: float = score(circuit)
		if after + 0.05 < before:
			changed += 1
		else:
			_swap_element_ports(circuit, int(el.id), p_left, p_right)
			WireRouter2D.invalidate()
	return changed


## Штраф за «не ту» сторону 2-полюсника:
## горизонтальные соседи — порты навстречу; вертикальные — с одного фланга (без С-петли).
static func _port_face_mismatch(circuit) -> float:
	var cost: float = 0.0
	for w in circuit.wires:
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		if not _is_symmetric_two_port(a) and not _is_symmetric_two_port(b):
			continue
		var pa: Dictionary = Geom.port_by_name(a, str(w.a_port))
		var pb: Dictionary = Geom.port_by_name(b, str(w.b_port))
		if pa.is_empty() or pb.is_empty():
			continue
		var aw: Vector2 = Geom.to_world(a, pa["local"])
		var bw: Vector2 = Geom.to_world(b, pb["local"])
		var mid: Vector2 = bw - aw
		if mid.length() < GRID * 0.5:
			continue
		var dir: Vector2 = mid.normalized()
		var ang_a: float = float(a.rotation_quad) * PI * 0.5
		var ang_b: float = float(b.rotation_quad) * PI * 0.5
		var na: Vector2 = (pa.get("normal", Vector2.ZERO) as Vector2).rotated(ang_a)
		var nb: Vector2 = (pb.get("normal", Vector2.ZERO) as Vector2).rotated(ang_b)
		var horiz: bool = absf(mid.x) >= absf(mid.y) * 0.85
		if horiz:
			# Навстречу: SB→HL по линии — правый к левому.
			var face: float = na.dot(dir) + nb.dot(-dir)
			if face < 1.2:
				cost += (1.2 - face)
		else:
			# Стопка: оба вывода с одного бока (нормали сонаправлены).
			var same: float = na.dot(nb)
			if same < 0.5:
				cost += (0.5 - same) * 2.0
			# И фланг должен смотреть наружу от оси «друг под другом», не в корпус.
			var side: Vector2 = Vector2(-dir.y, dir.x)
			var flank: float = absf(na.dot(side))
			if flank < 0.6:
				cost += (0.6 - flank)
	return cost


static func _is_symmetric_two_port(el) -> bool:
	return _symmetric_port_pair(el).size() >= 2


static func _symmetric_port_pair(el) -> PackedStringArray:
	if el == null:
		return PackedStringArray()
	var cls: String = str(el.electro_class)
	# Контакт кнопки (НО/НЗ пара) — левый/правый вывод в мировой СК (с учётом поворота).
	if cls == "contact" or (cls in ["button", "e_stop"] and str(el.member_role) != "main"):
		var ports: Array = Geom.ports(el)
		if ports.size() != 2:
			return PackedStringArray()
		var a: Dictionary = ports[0] if typeof(ports[0]) == TYPE_DICTIONARY else {}
		var b: Dictionary = ports[1] if typeof(ports[1]) == TYPE_DICTIONARY else {}
		var ang: float = float(el.rotation_quad) * PI * 0.5
		var na: Vector2 = (a.get("normal", Vector2.ZERO) as Vector2).rotated(ang)
		var nb: Vector2 = (b.get("normal", Vector2.ZERO) as Vector2).rotated(ang)
		# Строго влево/вправо в мире — иначе перекидной с двумя выводами с одной стороны.
		if absf(na.x + 1.0) < 0.25 and absf(nb.x - 1.0) < 0.25:
			return PackedStringArray([str(a.get("name", "")), str(b.get("name", ""))])
		if absf(nb.x + 1.0) < 0.25 and absf(na.x - 1.0) < 0.25:
			return PackedStringArray([str(b.get("name", "")), str(a.get("name", ""))])
		return PackedStringArray()
	if cls == "lamp":
		return PackedStringArray(["X1", "X2"])
	return PackedStringArray()


static func _wires_on_port(circuit, el_id: int, port: String) -> Array:
	var out: Array = []
	for w in circuit.wires:
		if int(w.a_id) == el_id and str(w.a_port) == port:
			out.append(w)
		elif int(w.b_id) == el_id and str(w.b_port) == port:
			out.append(w)
	return out


static func _swap_element_ports(circuit, el_id: int, port_a: String, port_b: String) -> void:
	for w in circuit.wires:
		if int(w.a_id) == el_id:
			if str(w.a_port) == port_a:
				w.a_port = port_b
			elif str(w.a_port) == port_b:
				w.a_port = port_a
		if int(w.b_id) == el_id:
			if str(w.b_port) == port_a:
				w.b_port = port_b
			elif str(w.b_port) == port_b:
				w.b_port = port_a


static func _movable_ids(circuit) -> Array:
	var out: Array = []
	for el in circuit.elements:
		# Контакты, привязанные к группе, едут с primary — не двигаем отдельно.
		if str(el.kind) == "electro" and str(el.member_role) == "contact" and not bool(el.detached):
			continue
		out.append(int(el.id))
	return out


static func _overlap_grow_cells(el) -> float:
	if el == null:
		return 0.55
	if str(el.kind) == "sensor":
		return 1.4
	if str(el.kind) == "electro" and str(el.electro_class) == "psu":
		return 1.6
	if str(el.kind) == "electro" and str(el.electro_class) == "supply":
		return 1.0
	if str(el.kind) == "electro" and str(el.electro_class) == "terminal":
		return 1.0
	return 0.7


static func _resolve_overlaps(circuit) -> int:
	var moved: int = 0
	var ids: Array = _movable_ids(circuit)
	for _pass in range(24):
		var changed: bool = false
		for i in range(ids.size()):
			var a = circuit.get_element(int(ids[i]))
			if a == null:
				continue
			var grow_a: float = GRID * _overlap_grow_cells(a)
			# Катушки: рамка группы (корпус+контакты), иначе столбики KL1/KL2 схлопываются.
			var ra: Rect2 = _coil_group_bounds(circuit, a).grow(grow_a)
			for j in range(i + 1, ids.size()):
				var b = circuit.get_element(int(ids[j]))
				if b == null:
					continue
				var grow_b: float = GRID * _overlap_grow_cells(b)
				var rb: Rect2 = _coil_group_bounds(circuit, b).grow(grow_b)
				if not ra.intersects(rb):
					continue
				var inter: Rect2 = ra.intersection(rb)
				# Толкать на глубину пересечения + зазор, а не фиксированные 5 клеток.
				var clear: float = GRID * 2.0
				var push_x: float = maxf(inter.size.x + clear, GRID * OVERLAP_PUSH)
				var push_y: float = maxf(inter.size.y + clear, GRID * OVERLAP_PUSH)
				var prefer_y: bool = absf(ra.get_center().y - rb.get_center().y) > absf(ra.get_center().x - rb.get_center().x)
				var ca: String = str(a.electro_class)
				var cb: String = str(b.electro_class)
				# Широкие клеммники в одном ряду — разводить по X.
				if ca == "terminal" and cb == "terminal":
					prefer_y = false
				# Две катушки/лампы в одном столбце — только по Y (X выровняет _align_coil_column).
				if (_is_coil_like(a) or ca == "lamp") and (_is_coil_like(b) or cb == "lamp"):
					prefer_y = true
				# БП/АВ на ряду XT — только вниз/вверх (по X всё равно режут широкую рамку).
				var rail_cls: bool = ca in ["terminal", "busbar"] or cb in ["terminal", "busbar"]
				var power_cls: bool = ca in ["psu", "mcb", "rcd", "rcbo", "generic_device"] \
					or cb in ["psu", "mcb", "rcd", "rcbo", "generic_device"]
				if rail_cls and power_cls:
					prefer_y = true
				var push := Vector2(push_x, 0.0) if not prefer_y else Vector2(0.0, push_y)
				if prefer_y:
					if ra.get_center().y > rb.get_center().y:
						_set_pos_with_group(circuit, a, (a.position + push).snapped(Vector2(GRID, GRID)))
					else:
						_set_pos_with_group(circuit, b, (b.position + push).snapped(Vector2(GRID, GRID)))
				elif ra.get_center().x > rb.get_center().x:
					_set_pos_with_group(circuit, a, (a.position + push).snapped(Vector2(GRID, GRID)))
				else:
					_set_pos_with_group(circuit, b, (b.position + push).snapped(Vector2(GRID, GRID)))
				moved += 1
				changed = true
				WireRouter2D.invalidate()
		if not changed:
			break
	return moved


## Сдвинуть элемент; неоткреплённые контакты группы — тем же delta.
static func _set_pos_with_group(circuit, el, new_pos: Vector2) -> void:
	if el == null:
		return
	var delta: Vector2 = new_pos - el.position
	if delta.length_squared() < 0.01:
		return
	el.position = new_pos
	if str(el.kind) != "electro" or str(el.member_role) == "contact":
		return
	var gid: int = int(el.group_id) if int(el.group_id) >= 0 else int(el.id)
	for m in circuit.electro_group_members(gid):
		if int(m.id) == int(el.id):
			continue
		if str(m.member_role) != "contact":
			continue
		if bool(m.detached) and not ElectroLib.is_button_fixed_contact(circuit, m):
			continue
		m.position = (m.position + delta).snapped(Vector2(GRID, GRID))


static func _set_rot_with_group(circuit, el, new_rot: int) -> void:
	if el == null:
		return
	var old_rot: int = int(el.rotation_quad)
	if old_rot == new_rot:
		return
	el.rotation_quad = new_rot
	if str(el.kind) != "electro" or str(el.member_role) == "contact":
		return
	var cls: String = str(el.electro_class)
	if cls in ["button", "e_stop"]:
		ElectroLib.layout_button_contacts(circuit, el)
	elif cls in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		ElectroLib.layout_coil_contacts(circuit, el)


static func _hill_climb(circuit) -> int:
	var moved: int = 0
	var ids: Array = _movable_ids(circuit)
	var dirs: Array = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
	]
	for _round in range(4):
		for idv in ids:
			var el = circuit.get_element(int(idv))
			if el == null:
				continue
			var best_pos: Vector2 = el.position
			var best_rot: int = int(el.rotation_quad)
			var best_sc: float = score(circuit)
			var improved: bool = false
			for step in NUDGE_STEPS:
				for d in dirs:
					var cand: Vector2 = (best_pos + (d as Vector2) * GRID * float(step)).snapped(Vector2(GRID, GRID))
					_set_pos_with_group(circuit, el, cand)
					WireRouter2D.invalidate()
					var sc: float = score(circuit)
					if sc + 0.05 < best_sc:
						best_sc = sc
						best_pos = cand
						improved = true
					else:
						_set_pos_with_group(circuit, el, best_pos)
			_set_pos_with_group(circuit, el, best_pos)
			# Поворот — вместе с контактами группы.
			if str(el.kind) == "electro" or str(el.kind) == "coil" or str(el.kind) == "junction":
				for rq in range(4):
					if rq == best_rot:
						continue
					_set_rot_with_group(circuit, el, rq)
					WireRouter2D.invalidate()
					var sc2: float = score(circuit)
					if sc2 + 0.05 < best_sc:
						best_sc = sc2
						best_rot = rq
						improved = true
					else:
						_set_rot_with_group(circuit, el, best_rot)
				_set_rot_with_group(circuit, el, best_rot)
			WireRouter2D.invalidate()
			if improved:
				moved += 1
	return moved


static func _element_overlap(circuit) -> float:
	var rects: Array = []
	for el in circuit.elements:
		if str(el.kind) == "electro" and str(el.member_role) == "contact" and not bool(el.detached):
			continue
		rects.append(Geom.world_bounds(el).grow(GRID * 0.2))
	var area: float = 0.0
	for i in range(rects.size()):
		var a: Rect2 = rects[i]
		for j in range(i + 1, rects.size()):
			var b: Rect2 = rects[j]
			if not a.intersects(b):
				continue
			var inter: Rect2 = a.intersection(b)
			area += maxf(inter.size.x, 0.0) * maxf(inter.size.y, 0.0)
	return area / (GRID * GRID)


static func _wire_bends(paths: Array) -> int:
	var n: int = 0
	for path in paths:
		var pts: PackedVector2Array = path as PackedVector2Array
		for i in range(1, pts.size() - 1):
			var d0: Vector2 = pts[i] - pts[i - 1]
			var d1: Vector2 = pts[i + 1] - pts[i]
			if absf(d0.x) < 0.5 and absf(d0.y) < 0.5:
				continue
			if absf(d1.x) < 0.5 and absf(d1.y) < 0.5:
				continue
			var ortho: bool = (absf(d0.x) < 0.5 and absf(d1.y) < 0.5) or (absf(d0.y) < 0.5 and absf(d1.x) < 0.5)
			if ortho:
				n += 1
	return n


static func _wire_crossings(paths: Array) -> int:
	var n: int = 0
	for i in range(paths.size()):
		var a: PackedVector2Array = paths[i] as PackedVector2Array
		for j in range(i + 1, paths.size()):
			var b: PackedVector2Array = paths[j] as PackedVector2Array
			n += _poly_cross_count(a, b)
	return n


## Штраф за параллельные «слипшиеся» участки (общая клетка / соседняя полоса).
static func _wire_nearness(paths: Array) -> float:
	var cost: float = 0.0
	var band: float = GRID * 0.85
	for i in range(paths.size()):
		var a: PackedVector2Array = paths[i] as PackedVector2Array
		if a.size() < 2:
			continue
		for j in range(i + 1, paths.size()):
			var b: PackedVector2Array = paths[j] as PackedVector2Array
			if b.size() < 2:
				continue
			for ia in range(a.size() - 1):
				var a0: Vector2 = a[ia]
				var a1: Vector2 = a[ia + 1]
				var a_h: bool = absf(a0.y - a1.y) < 0.51
				for ib in range(b.size() - 1):
					var b0: Vector2 = b[ib]
					var b1: Vector2 = b[ib + 1]
					var b_h: bool = absf(b0.y - b1.y) < 0.51
					if a_h != b_h:
						continue
					if a_h:
						if absf(a0.y - b0.y) > band:
							continue
						var ax0: float = minf(a0.x, a1.x)
						var ax1: float = maxf(a0.x, a1.x)
						var bx0: float = minf(b0.x, b1.x)
						var bx1: float = maxf(b0.x, b1.x)
						var ov: float = minf(ax1, bx1) - maxf(ax0, bx0)
						if ov > GRID * 0.5:
							cost += ov / GRID * (1.0 + (band - absf(a0.y - b0.y)) / band)
					else:
						if absf(a0.x - b0.x) > band:
							continue
						var ay0: float = minf(a0.y, a1.y)
						var ay1: float = maxf(a0.y, a1.y)
						var by0: float = minf(b0.y, b1.y)
						var by1: float = maxf(b0.y, b1.y)
						var ov2: float = minf(ay1, by1) - maxf(ay0, by0)
						if ov2 > GRID * 0.5:
							cost += ov2 / GRID * (1.0 + (band - absf(a0.x - b0.x)) / band)
	return cost


static func _poly_cross_count(a: PackedVector2Array, b: PackedVector2Array) -> int:
	var n: int = 0
	for i in range(a.size() - 1):
		var a0: Vector2 = a[i]
		var a1: Vector2 = a[i + 1]
		for j in range(b.size() - 1):
			var b0: Vector2 = b[j]
			var b1: Vector2 = b[j + 1]
			if _segments_cross(a0, a1, b0, b1):
				n += 1
	return n


static func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	# Строгое пересечение ортогональных отрезков (не в общей вершине).
	var ab_h: bool = absf(a.y - b.y) < 0.51
	var cd_h: bool = absf(c.y - d.y) < 0.51
	if ab_h == cd_h:
		return false
	if ab_h:
		var y: float = a.y
		var x0: float = minf(a.x, b.x)
		var x1: float = maxf(a.x, b.x)
		var x: float = c.x
		var y0: float = minf(c.y, d.y)
		var y1: float = maxf(c.y, d.y)
		return x > x0 + 0.5 and x < x1 - 0.5 and y > y0 + 0.5 and y < y1 - 0.5
	var y2: float = c.y
	var x2: float = a.x
	var xa0: float = minf(c.x, d.x)
	var xa1: float = maxf(c.x, d.x)
	var ya0: float = minf(a.y, b.y)
	var ya1: float = maxf(a.y, b.y)
	return x2 > xa0 + 0.5 and x2 < xa1 - 0.5 and y2 > ya0 + 0.5 and y2 < ya1 - 0.5


static func _wire_element_hits(circuit, paths: Array) -> float:
	var hits: float = 0.0
	for wi in circuit.wires.size():
		if wi >= paths.size():
			break
		var wire = circuit.wires[wi]
		var pts: PackedVector2Array = paths[wi] as PackedVector2Array
		if pts.size() < 2:
			continue
		var a_el = circuit.get_element(int(wire.a_id))
		var b_el = circuit.get_element(int(wire.b_id))
		var port_a := Vector2.ZERO
		var port_b := Vector2.ZERO
		if a_el != null:
			var pa: Dictionary = Geom.port_by_name(a_el, str(wire.a_port))
			if not pa.is_empty():
				port_a = Geom.to_world(a_el, pa["local"])
		if b_el != null:
			var pb: Dictionary = Geom.port_by_name(b_el, str(wire.b_port))
			if not pb.is_empty():
				port_b = Geom.to_world(b_el, pb["local"])
		var near_port: float = GRID * 3.4
		var skip := {int(wire.a_id): true, int(wire.b_id): true}
		for el in circuit.elements:
			var eid: int = int(el.id)
			var r: Rect2 = Geom.world_bounds(el).grow(GRID * 0.25)
			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var mid: Vector2 = (p0 + p1) * 0.5
				if not r.has_point(mid):
					continue
				if skip.has(eid) and (
					mid.distance_to(port_a) <= near_port or mid.distance_to(port_b) <= near_port
				):
					continue
				hits += 1.6 if skip.has(eid) else 1.0
				break
	return hits


static func _span_cost(circuit) -> float:
	if circuit.elements.is_empty():
		return 0.0
	var r := Rect2(circuit.elements[0].position, Vector2.ZERO)
	for el in circuit.elements:
		r = r.expand(el.position)
	return r.size.x + r.size.y
