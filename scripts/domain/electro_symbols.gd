class_name ElectroSymbols
extends RefCounted
## УГО по рефам out/electro_refs/user + ГОСТ 2.755 / 2.756.
## Управление (кнопка/контакт/лампа/катушка): горизонтальная цепь.
## Защита (АВ/УЗО/дифа): полюса столбцами, знаки крест / прямоугольник / овал.

const _ElectroLib = preload("res://scripts/domain/electro_library.gd")

const SCH_GRID := 10.0
# Геометрия из DXF U578/U580/U584/U582; масштаб так, что GAP DXF=3 → одна клетка сетки.
const DXF_SCALE := 10.0 / 3.0
const LEAD_X := 10.0 # порт контакта на ±(GAP+LEAD)=±20
const GAP := 3.0 * DXF_SCALE
const TAB := 4.0 * DXF_SCALE
const NC_OVER := 1.0 * DXF_SCALE
const NO_RISE := 3.46 * DXF_SCALE
const NC_TIP_EXTRA := 0.04 * DXF_SCALE
const BTN_LINK := 8.0 * DXF_SCALE
const BTN_BAR := 3.0 * DXF_SCALE
const BTN_LIP := 2.0 * DXF_SCALE
const BTN_STEM := 1.73 * DXF_SCALE
const BTN_DASH := 1.5 * DXF_SCALE
const BTN_DASH_GAP := 1.0 * DXF_SCALE
const CONTACT_W := 1.5
const LAMP_R := 10.0
# Катушка: ЭМ — гориз. A1↑/A2↓; реле/КТ/КМ — на 90° (вертик. корпус, A1←/A2→).
const COIL_HW := 20.0 # половина длинной стороны
const COIL_HH := 10.0 # половина короткой стороны
const COIL_W := COIL_HW # совместимость со старыми ссылками
const COIL_H := COIL_HH
const POLE_DX := 20.0 # шаг полюсов АВ/УЗО — кратно SCH_GRID
const BRK_TOP := -20.0
const BRK_BOT := 20.0
const BRK_STUB := 10.0 # вывод до порта: ±30 на сетке
const STUB_X := GAP
const STUB_Y := TAB
const BTN_H := BTN_LINK
const SW_DX := 20.0 # шаг положений — кратно сетке
const SW_DY := 20.0 # шаг рядов контактов
const ROW_H := 20.0 # строки клеммников / БП / шины
const MUSH_R := 3.0 * DXF_SCALE
const DIN_MODULE_MM := 17.5 # 1 модуль = ширина корпуса АВ


## Реле/КТ/КМ (не ЭМ): корпус вертикально, выводы с боков — мехсвязь снизу не из провода.
static func coil_side_leads(el) -> bool:
	if el == null:
		return true
	return str(el.electro_class) != "solenoid_coil"


## Половина ширины тела (X).
static func coil_body_hw(el = null) -> float:
	return COIL_HH if coil_side_leads(el) else COIL_HW


## Половина высоты тела (Y).
static func coil_body_hh(el = null) -> float:
	return COIL_HW if coil_side_leads(el) else COIL_HH


## Нижняя грань тела катушки (локальный +Y вниз).
static func coil_body_bottom(el = null) -> float:
	return coil_body_hh(el)


## Y центра первого контакта под катушкой.
## Между низом корпуса и верхом УГО контакта (НЗ перекидного) — минимум 1 клетка.
static func coil_contact_stack_y0(el = null, first_contact = null) -> float:
	var base: float = coil_body_bottom(el)
	if not coil_side_leads(el):
		base += LEAD_X
	# По умолчанию запас как у перекидного (−2 клетки вверх).
	var up: float = contact_extent_up(first_contact) if first_contact != null else 2.0 * SCH_GRID
	return base + SCH_GRID + up


static func button_has_members(el) -> bool:
	return str(el.electro_class) in ["button", "e_stop"] and str(el.member_role) == "main" and int(el.group_id) == int(el.id)


static func contact_unit_type(el) -> String:
	if el == null or typeof(el.contact_defs) != TYPE_ARRAY or el.contact_defs.is_empty():
		return "no"
	if typeof(el.contact_defs[0]) != TYPE_DICTIONARY:
		return "no"
	var t: String = str(el.contact_defs[0].get("type", "no"))
	if t == "co" or t == "nc" or t == "no":
		return t
	return "no"


## Выступ контакта вверх от оси (локальный Y растёт вниз).
static func contact_extent_up(el) -> float:
	var up: float = 0.0
	match contact_unit_type(el):
		"co":
			up = 2.0 * SCH_GRID # НЗ перекидного сверху (−2 клетки)
		"no":
			up = NO_RISE
		_:
			up = 0.0
	# Улыбка KT над каждым контактом — учитываем в шаге стека.
	if _is_timer_contact(el):
		up = maxf(up, 20.0) # дуга выше на 0.5 клетки + запас
	return up


## Выступ контакта вниз от оси.
static func contact_extent_down(el) -> float:
	match contact_unit_type(el):
		"nc":
			return TAB + NC_TIP_EXTRA
		"co":
			# НО на оси; вниз хвост не рисуем.
			return 0.0
		_:
			return 0.0


## Сдвиг первого перекидного под кнопкой: НЗ (−2 клетки) не заходит в скобу «П».
static func changeover_under_actuator_offset() -> float:
	var need: float = 2.0 * SCH_GRID - BTN_LINK + BTN_LIP + SCH_GRID * 0.5
	return maxf(SCH_GRID, ceilf(need / SCH_GRID - 1.0e-6) * SCH_GRID)


## Минимальный шаг центров по сетке SCH_GRID — без пересечения геометрии УГО.
static func button_contact_step(cur, nxt) -> float:
	if cur == null or nxt == null:
		return 2.0 * SCH_GRID
	var need: float = contact_extent_down(cur) + contact_extent_up(nxt)
	# Между точками подключения соседних единиц — минимум две клетки.
	need = maxf(need, 2.0 * SCH_GRID)
	# НЗ следующего перекидного не должен совпасть с НО/осью текущего.
	if contact_unit_type(nxt) == "co":
		need = maxf(need, contact_extent_up(nxt) + 2.0 * SCH_GRID)
	return maxf(2.0 * SCH_GRID, ceilf(need / SCH_GRID - 1.0e-6) * SCH_GRID)


static func ports(el) -> Array:
	var cls := str(el.electro_class)
	match cls:
		"solenoid_coil", "relay", "timer_relay", "voltage_relay", "contactor":
			if str(el.member_role) == "contact":
				return _contact_ports(el)
			var hw: float = coil_body_hw(el)
			var hh: float = coil_body_hh(el)
			if coil_side_leads(el):
				return [
					{"name": "A1", "local": Vector2(-hw - LEAD_X, 0.0), "normal": Vector2.LEFT},
					{"name": "A2", "local": Vector2(hw + LEAD_X, 0.0), "normal": Vector2.RIGHT},
				]
			return [
				{"name": "A1", "local": Vector2(0, -hh - LEAD_X), "normal": Vector2.UP},
				{"name": "A2", "local": Vector2(0, hh + LEAD_X), "normal": Vector2.DOWN},
			]
		"button", "e_stop":
			# Порты только у членов-контактов — иначе дубль цепи на primary.
			if button_has_members(el):
				return []
			return _contact_ports(el)
		"contact":
			return _contact_ports(el)
		"switch":
			return _switch_ports(el)
		"thermal":
			if str(el.member_role) == "contact":
				return _contact_ports(el)
			return _thermal_power_ports(el)
		"lamp":
			return [
				{"name": "X1", "local": Vector2(-LAMP_R - LEAD_X, 0), "normal": Vector2.LEFT},
				{"name": "X2", "local": Vector2(LAMP_R + LEAD_X, 0), "normal": Vector2.RIGHT},
			]
		"supply":
			# База L на primary (один порт); N/PE — supply_leg.
			if str(el.member_role) == "main" and int(el.group_id) == int(el.id):
				var defs0: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
				if defs0.size() == 1:
					return _supply_leg_ports(el)
				if defs0.is_empty():
					return []
			return _supply_ports(el)
		"supply_leg":
			return _supply_leg_ports(el)
		"psu", "generic_device", "rtd_meter":
			return _device_ports(el)
		"terminal":
			return _terminal_table_ports(el)
		"busbar":
			return _bus_ports(el)
		"mcb", "rcd", "rcbo":
			return _breaker_ports(el)
		"din_socket":
			return [
				{"name": "L", "local": Vector2(-LEAD_X, -10), "normal": Vector2.LEFT},
				{"name": "N", "local": Vector2(-LEAD_X, 0), "normal": Vector2.LEFT},
				{"name": "PE", "local": Vector2(-LEAD_X, 10), "normal": Vector2.LEFT},
			]
		"din_stop":
			return []
		_:
			return _contact_ports_named(el.electro_ports)


static func part_zones(el) -> Array:
	# Активные зоны для ПКМ на УГО (меньшая площадь выигрывает в part_hit).
	var cls := str(el.electro_class)
	if cls == "lamp":
		var d: float = LAMP_R * 2.0 + 4.0
		return [{"id": "lens", "rect": Rect2(-d * 0.5, -d * 0.5, d, d)}]
	if cls in ["button", "e_stop"] and str(el.member_role) != "contact":
		var lip_up: float = BTN_LIP if (bool(el.latching) or cls == "e_stop") else 0.0
		var top: float = BTN_LINK + (MUSH_R if cls == "e_stop" else BTN_LIP) + lip_up + 4.0
		var half: float = maxf(BTN_BAR, GAP) + 4.0
		return [{"id": "operator", "rect": Rect2(-half, -top, half * 2.0, top + 6.0)}]
	if cls == "switch":
		var b: Rect2 = _switch_bounds(el)
		return [{"id": "cam", "rect": b}]
	if cls in ["mcb", "rcd", "rcbo"]:
		var poles: int = _breaker_pole_count(el)
		var w: float = float(poles - 1) * POLE_DX + 16.0
		return [{"id": "lever", "rect": Rect2(-w * 0.5, BRK_TOP, w, BRK_BOT - BRK_TOP)}]
	if cls in ["solenoid_coil", "relay", "timer_relay", "voltage_relay", "contactor"] and str(el.member_role) != "contact":
		var zhw: float = coil_body_hw(el)
		var zhh: float = coil_body_hh(el)
		var zones: Array = [{"id": "coil", "rect": Rect2(-zhw - 2.0, -zhh - 2.0, zhw * 2.0 + 4.0, zhh * 2.0 + 4.0)}]
		if cls == "solenoid_coil":
			zones.append({"id": "pilot", "rect": Rect2(zhw, -zhh - 2.0, 22.0, zhh * 2.0 + 4.0)})
		return zones
	if cls == "busbar":
		var n: int = maxi(el.electro_ports.size(), 2)
		return [
			{"id": "bus_color", "rect": Rect2(-4.0, -14.0, float(n) * ROW_H + 16.0, 18.0)},
			{"id": "bus_taps", "rect": Rect2(-4.0, 4.0, float(n) * ROW_H + 16.0, 22.0)},
		]
	if cls in ["psu", "generic_device"]:
		var lay: Dictionary = _device_layout(el)
		var x0: float = float(lay["x0"])
		var x1: float = float(lay["x1"])
		var y0: float = float(lay["y0"])
		var y_title: float = float(lay["y_title"])
		var x_l0: float = float(lay.get("x_l0", x0))
		var x_l1: float = float(lay.get("x_l1", lay["xl1"]))
		var x_r0: float = float(lay.get("x_r0", lay["xr0"]))
		var x_r1: float = float(lay.get("x_r1", x1))
		var y_tbl_l: float = float(lay["y_tbl_l"])
		var y_bot_l: float = float(lay["y_bot_l"])
		var y_tbl_r: float = float(lay["y_tbl_r"])
		var y_bot_r: float = float(lay["y_bot_r"])
		var zones: Array = [
			{"id": "device_title", "rect": Rect2(x0, y0, x1 - x0, y_title - y0)},
		]
		if not (lay["left"] as Array).is_empty():
			zones.append({"id": "device_table_left", "rect": Rect2(x_l0, y_tbl_l, x_l1 - x_l0, y_bot_l - y_tbl_l)})
		if not (lay["right"] as Array).is_empty():
			zones.append({"id": "device_table_right", "rect": Rect2(x_r0, y_tbl_r, x_r1 - x_r0, y_bot_r - y_tbl_r)})
		zones.append({"id": "device_ports", "rect": Rect2(x0, y_title, x1 - x0, float(lay["y1"]) - y_title)})
		return zones
	if cls == "supply":
		return [{"id": "supply", "rect": local_bounds(el)}]
	if cls == "terminal":
		return [{"id": "terminal", "rect": local_bounds(el)}]
	return []


static func local_bounds(el) -> Rect2:
	# Строго по нарисованным штрихам (без «ореола») — зона выбора = этот Rect.
	var cls := str(el.electro_class)
	match cls:
		"lamp":
			return Rect2(-LAMP_R - LEAD_X, -LAMP_R, (LAMP_R + LEAD_X) * 2.0, LAMP_R * 2.0)
		"button", "e_stop":
			if button_has_members(el):
				var half: float = maxf(MUSH_R if str(el.electro_class) == "e_stop" else BTN_BAR, GAP)
				var top: float = BTN_LINK + (MUSH_R if str(el.electro_class) == "e_stop" else BTN_LIP)
				return Rect2(-half, -top, half * 2.0, top)
			return _contact_bounds(el)
		"switch":
			return _switch_bounds(el)
		"contact":
			return _contact_bounds(el)
		"solenoid_coil", "relay", "timer_relay", "voltage_relay", "contactor":
			if str(el.member_role) == "contact":
				return _contact_bounds(el)
			var bhw: float = coil_body_hw(el)
			var bhh: float = coil_body_hh(el)
			if coil_side_leads(el):
				return Rect2(-bhw - LEAD_X, -bhh, (bhw + LEAD_X) * 2.0, bhh * 2.0)
			return Rect2(-bhw, -bhh - LEAD_X, bhw * 2.0, (bhh + LEAD_X) * 2.0)
		"mcb", "rcd", "rcbo":
			return _breaker_bounds(el)
		"supply":
			var defs_b: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
			if str(el.member_role) == "main" and defs_b.size() <= 1:
				# База L — одна ячейка (без пустой шапки над столбиком).
				return _supply_leg_bounds(el)
			return _supply_bounds(el)
		"supply_leg":
			return _supply_leg_bounds(el)
		"psu", "generic_device", "rtd_meter":
			return _device_bounds(el)
		"terminal":
			return _terminal_table_bounds(el)
		"busbar":
			var n_bb: int = maxi(el.electro_ports.size(), 1)
			var x1_bb: float = 10.0 + float(n_bb - 1) * ROW_H + 10.0
			return Rect2(0.0, -5.0, x1_bb, 25.0)
		"din_socket":
			return Rect2(-LEAD_X - 6.0, -20, LEAD_X + 28.0, 40)
		"din_stop":
			return Rect2(-10, -20, 20, 40)
		"thermal":
			if str(el.member_role) == "contact":
				return _contact_bounds(el)
			# Рамка ±26×±12 + силовые выводы ±30 по Y.
			return Rect2(-26.0, -30.0, 52.0, 60.0)
		_:
			return Rect2(-20, -20, 40, 40)


## Габарит АВ/УЗО по штрихам (выводы, ключ, овал ТТ) — без +24/+16 pad.
static func _breaker_bounds(el) -> Rect2:
	var poles: int = _breaker_pole_count(el)
	var cls: String = str(el.electro_class)
	var half: float = float(maxi(poles - 1, 0)) * POLE_DX * 0.5
	var bot_stub: float = BRK_STUB + (2.0 * SCH_GRID if cls in ["rcd", "rcbo"] else 0.0)
	# Открытый ключ −11; крест ±4; овал/связь УЗО левее.
	var left: float = -half - 12.0
	var right: float = half + 8.0
	var top: float = BRK_TOP - BRK_STUB
	var bot: float = BRK_BOT + bot_stub
	if cls in ["rcd", "rcbo"]:
		var rx: float = half + 8.0
		left = minf(left, -rx - 6.0)
		right = maxf(right, rx)
		bot = maxf(bot, (BRK_BOT - 2.0) + 12.0 + 5.0)
	return Rect2(left, top, right - left, bot - top)


static func _contact_bounds(el) -> Rect2:
	var defs: Array = el.contact_defs
	var is_btn: bool = str(el.electro_class) in ["button", "e_stop"]
	var is_ps: bool = _is_pressure_switch_contact(el)
	var half_w: float = GAP + LEAD_X # tip порта по X
	if defs.size() >= 1 and typeof(defs[0]) == TYPE_DICTIONARY and str(defs[0].get("type", "")) == "co":
		# НЗ на −2 клетки; у кнопки сверху скоба «П» / гриб.
		var up: float = 2.0 * SCH_GRID
		if is_btn:
			var btn_top_co: float = BTN_LINK + (MUSH_R if str(el.electro_class) == "e_stop" else BTN_LIP)
			up = maxf(up, btn_top_co)
		if is_ps:
			up = maxf(up, BTN_LINK + _pressure_act_box_hh() * 2.0)
		return Rect2(-half_w, -up, half_w * 2.0, up + TAB)
	var pairs: int = maxi(int(ceil(float(maxi(el.contact_defs.size(), 2)) / 2.0)), 1)
	var h: float = ROW_H * float(pairs)
	var btn_top: float = BTN_LINK + (MUSH_R if str(el.electro_class) == "e_stop" else BTN_LIP)
	var top: float = btn_top if is_btn else NO_RISE
	if is_ps:
		top = maxf(top, BTN_LINK + _pressure_act_box_hh() * 2.0 + SCH_GRID * 0.2)
		half_w = maxf(half_w, _pressure_act_box_hw())
	var bot: float = TAB
	var extra: float = 16.0 if _is_timer_contact(el) else 0.0
	return Rect2(-half_w, -top - extra, half_w * 2.0, h + top + bot + extra)


static func draw(ci: CanvasItem, el, font: Font, selected: bool, hover_port: String, ink: Color, to_world: Callable, stroke_w: Callable, stroke_aa: Callable, draw_tag: Callable, port_domain: Callable, draw_marker: Callable, hover_part: String = "", omit_motion: bool = false) -> void:
	var cls := str(el.electro_class)
	match cls:
		"lamp":
			_draw_lamp(ci, el, ink, to_world, stroke_w, stroke_aa, omit_motion)
		"button", "e_stop":
			_draw_button(ci, el, ink, to_world, stroke_w, stroke_aa)
		"switch":
			_draw_switch(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"solenoid_coil", "relay", "timer_relay", "voltage_relay", "contactor":
			if str(el.member_role) == "contact":
				_draw_contact(ci, el, ink, to_world, stroke_w, stroke_aa)
			else:
				_draw_coil(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"contact":
			_draw_contact(ci, el, ink, to_world, stroke_w, stroke_aa)
		"mcb", "rcd", "rcbo":
			_draw_breaker(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"supply":
			_draw_supply(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"supply_leg":
			_draw_supply_leg(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"psu", "generic_device", "rtd_meter":
			_draw_device(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"terminal":
			_draw_terminal_table(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"busbar":
			_draw_busbar(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		"din_socket":
			_draw_socket(ci, el, ink, to_world, stroke_w, stroke_aa)
		"din_stop":
			_draw_stop(ci, el, ink, to_world, stroke_w, stroke_aa)
		"thermal":
			if str(el.member_role) == "contact":
				_draw_contact(ci, el, ink, to_world, stroke_w, stroke_aa)
			else:
				_draw_thermal(ci, el, ink, to_world, stroke_w, stroke_aa)
		_:
			_draw_box_generic(ci, el, ink, to_world, stroke_w, stroke_aa)
	for port in ports(el):
		draw_marker.call(ci, el, port["local"], port_domain.call(el, str(port["name"])), hover_port == str(port["name"]))
	# hover_part: клип-подсветка части делает caller (SchematicView), здесь рамку не рисуем.
	# Контакты и ноги ввода: тег только после отцепления (иначе XS1.L/N/PE поверх рядов).
	var role_tag: String = str(el.member_role)
	# Контакт реле давления KP1.1 — тег всегда (как на учебной схеме).
	if role_tag not in ["contact", "supply_leg"] or bool(el.detached) \
			or _is_pressure_switch_contact(el) or _is_pressure_tx_terminal(el) \
			or _is_rtd_meter(el):
		draw_tag.call(ci, el, font, 13, selected)


static func electro_group_frame(circuit, group_id: int, exclude_detached: bool, exclude_id: int = -1) -> Rect2:
	var primary = null
	for el in circuit.elements:
		if int(el.id) == group_id:
			primary = el
			break
	var r := Rect2()
	var has := false
	if primary != null and int(primary.id) != exclude_id:
		if str(primary.kind) == "electro" or (
			str(primary.kind) == "sensor" and str(primary.sensor_class) in ["pressure_switch", "pressure_tx", "rtd"]
		):
			var lb: Rect2
			if str(primary.kind) == "electro":
				lb = local_bounds(primary)
			else:
				lb = preload("res://scripts/domain/symbol_geom.gd").library_bounds(primary)
			r = Rect2(primary.position + lb.position, lb.size)
			has = true
	for el in circuit.elements:
		if str(el.kind) != "electro" or int(el.group_id) != group_id:
			continue
		if int(el.id) == exclude_id:
			continue
		if exclude_detached and bool(el.detached):
			continue
		if _ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var elb := local_bounds(el)
		var er := Rect2(el.position + elb.position, elb.size)
		if not has:
			r = er
			has = true
		else:
			r = r.merge(er)
	return r


static func _corners_world(el, lb: Rect2) -> Array:
	return [
		el.position + lb.position,
		el.position + lb.position + Vector2(lb.size.x, 0),
		el.position + lb.position + lb.size,
		el.position + lb.position + Vector2(0, lb.size.y),
	]


static func draw_group_overlays(ci: CanvasItem, circuit, font: Font, drag_exclude_ids: Array = []) -> void:
	# Кнопка: пунктирная мехсвязь к неотнесённым; отнесённый — без рамки.
	# Реле/КМ/KT: столбик под катушкой + мехсвязь от нижней грани; отнесённый — штрих + рамка.
	var seen: Dictionary = {}
	for el in circuit.elements:
		# Группы реле/ПИП давления: primary = sensor, члены = electro.
		if str(el.kind) != "electro" and not (
			str(el.kind) == "sensor" and str(el.sensor_class) in ["pressure_switch", "pressure_tx", "rtd"]
		):
			continue
		var gid: int = int(el.group_id) if str(el.kind) == "electro" else int(el.id)
		if str(el.kind) == "sensor":
			gid = int(el.id)
		if gid <= 0 or seen.has(gid):
			continue
		seen[gid] = true
		if drag_exclude_ids.has(gid):
			continue
		var primary = circuit.get_element(gid)
		if primary == null:
			continue
		var is_btn: bool = str(primary.electro_class) in ["button", "e_stop"]
		var is_coil: bool = str(primary.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]
		var is_ps: bool = str(primary.kind) == "sensor" and str(primary.sensor_class) == "pressure_switch"
		var is_pt: bool = str(primary.kind) == "sensor" and str(primary.sensor_class) == "pressure_tx"
		var is_rtd: bool = str(primary.kind) == "sensor" and str(primary.sensor_class) == "rtd"
		if is_btn:
			_ElectroLib.layout_button_contacts(circuit, primary)
			_draw_button_mech_links(ci, circuit, primary)
			continue
		if is_coil:
			# Как у кнопок: мехсвязь только к неотнесённым; отнесённый — без рамки и без штриха.
			_ElectroLib.layout_coil_contacts(circuit, primary)
			_draw_coil_mech_links(ci, circuit, primary)
			continue
		if is_ps:
			_draw_pressure_switch_mech_links(ci, circuit, primary)
			continue
		# ПИП / ТС: УГО и табличка вторички — без мехсвязи.
		if is_pt or is_rtd:
			continue
		var has_det2: bool = false
		for other2 in circuit.elements:
			if str(other2.kind) != "electro" or int(other2.group_id) != gid:
				continue
			if bool(other2.detached) and str(other2.member_role) == "contact":
				has_det2 = true
				_draw_dash_line(ci, primary.position, other2.position, Color(0.35, 0.4, 0.5, 0.5), 3.0, 3.0)
		if not has_det2:
			continue
		var fr2 := electro_group_frame(circuit, gid, true)
		if fr2.size.x < 2.0 or fr2.size.y < 2.0:
			continue
		_draw_dash_rect(ci, fr2.grow(6.0), Color(0.2, 0.35, 0.55, 0.55), 4.0, 3.0)


static func _draw_pressure_switch_mech_links(ci: CanvasItem, circuit, primary) -> void:
	var attached: Array = []
	for m in circuit.elements:
		if str(m.kind) != "electro" or int(m.group_id) != int(primary.id):
			continue
		if str(m.member_role) != "contact" or bool(m.detached):
			continue
		attached.append(m)
	if attached.is_empty():
		return
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var pang: float = float(primary.rotation_quad) * PI * 0.5
	var a: Vector2 = primary.position + Vector2(0.0, SCH_GRID * 2.0).rotated(pang)
	var last = attached[attached.size() - 1]
	var tt: String = "no"
	if typeof(last.contact_defs) == TYPE_ARRAY and last.contact_defs.size() > 0 \
			and typeof(last.contact_defs[0]) == TYPE_DICTIONARY:
		tt = str(last.contact_defs[0].get("type", "no"))
	var y_tip: float = _actuator_stem_tip_y(0.0, tt) - BTN_LINK
	var lang: float = float(last.rotation_quad) * PI * 0.5
	var b: Vector2 = last.position + Vector2(0.0, y_tip).rotated(lang)
	_draw_dash_line(ci, a, b, Color(0.08, 0.09, 0.12, 1.0), 2.4, 2.0, 1.35, false)


static func _draw_button_mech_links(ci: CanvasItem, circuit, primary) -> void:
	var attached: Array = []
	for m in circuit.elements:
		if str(m.kind) != "electro" or int(m.group_id) != int(primary.id):
			continue
		if str(m.member_role) != "contact" or bool(m.detached):
			continue
		attached.append(m)
	if attached.is_empty():
		return
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	# Стойка от скобы/гриба до последнего контакта в столбике (с учётом поворота группы).
	var y_top: float = -BTN_LINK + (0.0 if str(primary.electro_class) == "e_stop" else BTN_LIP)
	var pang: float = float(primary.rotation_quad) * PI * 0.5
	var a: Vector2 = primary.position + Vector2(0.0, y_top).rotated(pang)
	var last = attached[attached.size() - 1]
	# До наклона первого/последнего контакта, не до центра — иначе короткий обрубок под диагональю.
	var tt: String = "no"
	if typeof(last.contact_defs) == TYPE_ARRAY and last.contact_defs.size() > 0 and typeof(last.contact_defs[0]) == TYPE_DICTIONARY:
		tt = str(last.contact_defs[0].get("type", "no"))
	var y_tip: float = _actuator_stem_tip_y(0.0, tt)
	var lang: float = float(last.rotation_quad) * PI * 0.5
	var b: Vector2 = last.position + Vector2(0.0, y_tip).rotated(lang)
	# Без AA — иначе «мыльная» штриховая на сетке.
	_draw_dash_line(ci, a, b, Color(0.08, 0.09, 0.12, 1.0), 2.4, 2.0, 1.35, false)


static func _draw_coil_mech_links(ci: CanvasItem, circuit, primary) -> void:
	var attached: Array = []
	for m in circuit.elements:
		if str(m.kind) != "electro" or int(m.group_id) != int(primary.id):
			continue
		if str(m.member_role) != "contact" or bool(m.detached):
			continue
		if _ElectroLib.coil_contact_hidden_on_scheme(circuit, m):
			continue
		attached.append(m)
	if attached.is_empty():
		return
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var pang: float = float(primary.rotation_quad) * PI * 0.5
	# От нижней грани тела катушки, не от центра.
	var a: Vector2 = primary.position + Vector2(0.0, coil_body_bottom(primary)).rotated(pang)
	var last = attached[attached.size() - 1]
	var tt: String = "no"
	if typeof(last.contact_defs) == TYPE_ARRAY and last.contact_defs.size() > 0 and typeof(last.contact_defs[0]) == TYPE_DICTIONARY:
		tt = str(last.contact_defs[0].get("type", "no"))
	var y_tip: float = _actuator_stem_tip_y(0.0, tt)
	var lang: float = float(last.rotation_quad) * PI * 0.5
	var b: Vector2 = last.position + Vector2(0.0, y_tip).rotated(lang)
	_draw_dash_line(ci, a, b, Color(0.08, 0.09, 0.12, 1.0), 2.4, 2.0, 1.35, false)


static func _contact_ports(el) -> Array:
	return _contact_ports_named(el.contact_defs)


static func _contact_ports_named(defs: Array) -> Array:
	if defs.is_empty():
		return [
			{"name": "1", "local": Vector2(-STUB_X - LEAD_X, 0), "normal": Vector2.LEFT},
			{"name": "2", "local": Vector2(STUB_X + LEAD_X, 0), "normal": Vector2.RIGHT},
		]
	# Перекидной (U579): общий слева на оси, НО справа на оси, НЗ справа сверху (−2 клетки).
	if defs.size() >= 1 and typeof(defs[0]) == TYPE_DICTIONARY and str(defs[0].get("type", "")) == "co":
		var n_c: String = str(defs[0].get("name", "11"))
		var n_nc: String = str(defs[1].get("name", "12")) if defs.size() > 1 else "12"
		var n_no: String = str(defs[2].get("name", "14")) if defs.size() > 2 else "14"
		var y_nc: float = -2.0 * SCH_GRID
		return [
			{"name": n_c, "local": Vector2(-STUB_X - LEAD_X, 0), "normal": Vector2.LEFT},
			{"name": n_no, "local": Vector2(STUB_X + LEAD_X, 0), "normal": Vector2.RIGHT},
			{"name": n_nc, "local": Vector2(STUB_X + LEAD_X, y_nc), "normal": Vector2.RIGHT},
		]
	var pairs: int = int(ceil(float(defs.size()) / 2.0))
	var out: Array = []
	for pi in pairs:
		# Тот же шаг, что в _draw_contact (20 = 2 клетки).
		var y: float = (float(pi) - float(pairs - 1) * 0.5) * ROW_H
		var i0: int = pi * 2
		var nl: String = str(defs[i0].get("name", i0)) if i0 < defs.size() else str(i0)
		var nr: String = str(defs[i0 + 1].get("name", i0 + 1)) if i0 + 1 < defs.size() else str(i0 + 1)
		out.append({"name": nl, "local": Vector2(-STUB_X - LEAD_X, y), "normal": Vector2.LEFT})
		out.append({"name": nr, "local": Vector2(STUB_X + LEAD_X, y), "normal": Vector2.RIGHT})
	return out


static func _breaker_pole_count(el) -> int:
	var poles: int = maxi(int(el.poles), 1)
	var cls := str(el.electro_class)
	if cls in ["rcd", "rcbo"]:
		# 1P+N → 2 столбца, 3P+N → 4.
		return clampi(maxi(poles, 2), 2, 4)
	return poles


static func _breaker_ports(el) -> Array:
	var poles: int = _breaker_pole_count(el)
	var out: Array = []
	var cls := str(el.electro_class)
	var bot_stub: float = BRK_STUB + (2.0 * SCH_GRID if cls in ["rcd", "rcbo"] else 0.0)
	var x0: float = -float(poles - 1) * POLE_DX * 0.5
	for i in poles:
		var x: float = x0 + float(i) * POLE_DX
		out.append({"name": str(i * 2 + 1), "local": Vector2(x, BRK_TOP - BRK_STUB), "normal": Vector2.UP})
		out.append({"name": str(i * 2 + 2), "local": Vector2(x, BRK_BOT + bot_stub), "normal": Vector2.DOWN})
	return out


static func _bus_ports(el) -> Array:
	var defs: Array = el.electro_ports
	var n: int = maxi(defs.size(), 1)
	var out: Array = []
	for i in n:
		var x: float = 10.0 + float(i) * ROW_H
		var nm: String = str(defs[i].get("name", i + 1)) if i < defs.size() and typeof(defs[i]) == TYPE_DICTIONARY else str(i + 1)
		out.append({"name": nm, "local": Vector2(x, 20.0), "normal": Vector2.DOWN})
	return out


static func _thermal_power_ports(el) -> Array:
	var out: Array = []
	var labels := ["1", "3", "5", "2", "4", "6"]
	for i in 3:
		var x: float = -20.0 + float(i) * 20.0
		out.append({"name": labels[i], "local": Vector2(x, -30.0), "normal": Vector2.UP})
		out.append({"name": labels[i + 3], "local": Vector2(x, 30.0), "normal": Vector2.DOWN})
	return out


## Контекст схемы (для «Скрыть неиспользуемые» на клеммнике).
static var scheme_circuit = null


## Шаг между tips клеммника в клетках (≥2). Высота блока всегда 2 клетки.
static func _term_pitch_cells(el = null) -> int:
	var pitch: int = 2
	if el != null:
		var raw: Variant = el.get("terminal_pitch_cells")
		if raw != null:
			pitch = maxi(int(raw), 2)
	return pitch


## Горизонтальный шаг tip↔tip (кратен SCH_GRID).
static func _term_pitch_step(el = null) -> float:
	return SCH_GRID * float(_term_pitch_cells(el))


## Высота ряда клеммника — всегда 2 клетки (шаг меняет только ширину/расстояние tips).
static func _term_row_h(_el = null) -> float:
	return SCH_GRID * 2.0


## Совместимость: «ячейка» = горизонтальный шаг tips.
static func _term_cell(el = null) -> float:
	return _term_pitch_step(el)


static func _term_pole_count(el) -> int:
	if str(el.phase) != "":
		return 1
	return maxi(el.electro_ports.size(), 1)


## Число кружков/портов: 2 на полюс (1–2, 3–4…), все в одном ряду.
static func _term_port_count(el) -> int:
	return _term_pole_count(el) * 2


static func _term_v_gap() -> float:
	return SCH_GRID


static func _term_lead() -> float:
	return 0.0 # кружок = точка подключения, без отростка


static func _term_col_w(el = null) -> float:
	return _term_pitch_step(el)


static func _term_mid_w() -> float:
	return 0.0


## Есть ли жила на конкретном tip XT (скан wires[] — индекс wire_on бывает устаревшим).
static func _terminal_port_has_wire(el, port_name: String) -> bool:
	if el == null or scheme_circuit == null:
		return false
	var eid: int = int(el.id)
	var want: String = str(port_name)
	for w in scheme_circuit.wires:
		if w == null:
			continue
		if int(w.a_id) == eid and str(w.a_port) == want:
			return true
		if int(w.b_id) == eid and str(w.b_port) == want:
			return true
	return false


## Имена портов слева→направо с учётом «Скрыть неиспользуемые».
## Прячем каждый tip без жилы; занятые остаются (плотный ряд).
static func _terminal_visible_names(el) -> Array:
	var n_all: int = _term_port_count(el)
	var out: Array = []
	var hide_on: bool = false
	if el != null:
		var hide_raw: Variant = el.get("hide_unused_contacts")
		hide_on = hide_raw != null and bool(hide_raw) and scheme_circuit != null
	for i in n_all:
		var pname: String = str(i + 1)
		if hide_on and not _terminal_port_has_wire(el, pname):
			continue
		out.append(pname)
	# Не оставлять пустой УГО — хотя бы первая точка.
	if out.is_empty() and n_all >= 1:
		out.append("1")
	return out


## Раскладка: tips на SCH_GRID; высота 2 клетки.
## При hide — только видимые tips плотным рядом (n = число видимых).
## Первый tip якорится как при шаге 2.
## {n, step, h, x_first, x0, x1, y0, y1, names}
static func _terminal_layout(el) -> Dictionary:
	var names: Array = _terminal_visible_names(el)
	var n: int = maxi(names.size(), 1)
	var step: float = _term_pitch_step(el)
	var h: float = _term_row_h(el)
	var x_first: float = snappedf(-float(n - 1) * SCH_GRID, SCH_GRID) if n >= 1 else 0.0
	var x0: float = x_first - SCH_GRID
	var x1: float = x_first + float(maxi(n - 1, 0)) * step + SCH_GRID
	x0 = snappedf(x0, SCH_GRID)
	x1 = snappedf(x1, SCH_GRID)
	if x1 <= x0:
		x1 = x0 + maxf(step, SCH_GRID * 2.0)
	return {
		"n": n,
		"step": step,
		"h": h,
		"x_first": x_first,
		"x0": x0,
		"x1": x1,
		"y0": -h * 0.5,
		"y1": h * 0.5,
		"names": names,
	}


## Tip клеммника без жилы — прячем при hide_unused_contacts.
static func terminal_port_unused(el, port_name: String) -> bool:
	if el == null:
		return false
	var hide_raw: Variant = el.get("hide_unused_contacts")
	if hide_raw == null or not bool(hide_raw):
		return false
	if scheme_circuit == null:
		return false
	return not _terminal_port_has_wire(el, str(port_name))


static func _terminal_table_ports(el) -> Array:
	var lay: Dictionary = _terminal_layout(el)
	var step: float = float(lay["step"])
	var x_first: float = float(lay["x_first"])
	var names: Array = lay.get("names", []) as Array
	var out: Array = []
	for i in names.size():
		var pname: String = str(names[i])
		var cx: float = x_first + float(i) * step
		out.append({"name": pname, "local": Vector2(cx, 0.0), "normal": Vector2.UP})
	return out


static func _terminal_table_bounds(el) -> Rect2:
	var lay: Dictionary = _terminal_layout(el)
	var x0: float = float(lay["x0"])
	var x1: float = float(lay["x1"])
	var y0: float = float(lay["y0"])
	var y1: float = float(lay["y1"])
	return Rect2(x0, y0, x1 - x0, y1 - y0)


static func _device_port_side(p: Dictionary) -> String:
	var side_s: String = str(p.get("side", "")).strip_edges().to_lower()
	if side_s == "right" or side_s == "left":
		return side_s
	var nm: String = str(p.get("name", "")).strip_edges().to_upper()
	# DC-выходы БП — всегда справа, даже если в сцене side забыли.
	if nm in ["+24", "+24V", "24V", "0", "0V", "+", "-"]:
		return "right"
	if nm in ["L", "N", "PE", "L1", "L2", "L3"]:
		return "left"
	if str(p.get("type", "")) == "source":
		return "right"
	return "left"


static func _device_port_circuit(p: Dictionary) -> String:
	var circ: String = str(p.get("circuit", "")).strip_edges()
	if circ != "":
		return circ
	var nm: String = str(p.get("name", "")).strip_edges()
	match nm.to_upper():
		"L", "L1":
			return "L ~220В"
		"N":
			return "N ~220В"
		"PE":
			return "PE"
		"+24", "+24V", "24V", "+":
			return "+24В"
		"0", "0V", "-":
			return "0В"
		"OUT", "SIG", "SIGNAL":
			return "Сигнал"
		_:
			return nm


static func _device_side_ports(el, side: String) -> Array:
	var defs: Array = el.electro_ports
	var left: Array = []
	var right: Array = []
	for p in defs:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var enriched: Dictionary = (p as Dictionary).duplicate(true)
		enriched["circuit"] = _device_port_circuit(enriched)
		if _device_port_side(enriched) == "right":
			right.append(enriched)
		else:
			left.append(enriched)
	if left.is_empty() and right.is_empty():
		left = [
			{"name": "L", "circuit": "L ~220В"},
			{"name": "N", "circuit": "N ~220В"},
			{"name": "PE", "circuit": "PE"},
		]
		right = [
			{"name": "+24", "circuit": "+24В"},
			{"name": "0", "circuit": "0В"},
		]
	return left if side == "left" else right


static func _device_cont_w() -> float:
	return SCH_GRID * 3.0 # «Конт.»


static func _device_circ_w() -> float:
	# Шире: подписи вроде «L ~220В» / «+24В» должны влезать в ячейку.
	return SCH_GRID * 7.0 # «Цепь»


static func _device_mid_gap() -> float:
	return SCH_GRID * 2.0 # зазор между таблицами; mid = 10 → рамки на сетке


static func _device_row_h() -> float:
	# Как у supply / клеммников: центры строк и выводы на SCH_GRID.
	return ROW_H


static func _device_table_pad() -> float:
	return SCH_GRID * 2.0


static func _device_half_w() -> float:
	return _device_cont_w() + _device_circ_w()


static func _device_table_dy(el, side: String) -> float:
	# PreviewEl / урезанные объекты могут не иметь полей — тогда 0.
	var key: String = "device_table_dy_right" if side == "right" else "device_table_dy_left"
	var v = el.get(key) if el != null else null
	var raw: float = float(v) if v != null else 0.0
	return snappedf(raw, SCH_GRID)


## Край отрисовки логической таблицы («left»/«right» = группа портов). По умолчанию = группа.
static func _device_table_edge(el, table: String) -> String:
	var key: String = "device_table_edge_left" if table == "left" else "device_table_edge_right"
	var v = el.get(key) if el != null else null
	if v != null:
		var s: String = str(v).strip_edges().to_lower()
		if s == "left" or s == "right":
			return s
	return "left" if table == "left" else "right"


static func _device_table_y_span(n_ports: int, dy: float, rh: float) -> Dictionary:
	var nn: int = maxi(n_ports, 1)
	var y_hdr: float = -float(nn - 1) * rh * 0.5 - rh * 0.5 + dy
	return {
		"y_tbl": y_hdr - rh,
		"y_hdr": y_hdr,
		"y_bot": y_hdr + float(nn) * rh,
		"n": nn,
	}


## dy так, чтобы таблицы на одном краю не сливались (мин. зазор mid_gap).
static func device_clamp_table_dy(el, table: String, dy: float) -> float:
	var want: float = snappedf(dy, SCH_GRID)
	if el == null or table not in ["left", "right"]:
		return want
	var other: String = "right" if table == "left" else "left"
	if _device_side_ports(el, other).is_empty():
		return want
	if _device_table_edge(el, table) != _device_table_edge(el, other):
		return want
	var rh: float = _device_row_h()
	var gap: float = _device_mid_gap()
	var n_m: int = _device_side_ports(el, table).size()
	var n_o: int = _device_side_ports(el, other).size()
	var span_o: Dictionary = _device_table_y_span(n_o, _device_table_dy(el, other), rh)
	var span_m: Dictionary = _device_table_y_span(n_m, want, rh)
	var y_tbl_m: float = float(span_m["y_tbl"])
	var y_bot_m: float = float(span_m["y_bot"])
	var y_tbl_o: float = float(span_o["y_tbl"])
	var y_bot_o: float = float(span_o["y_bot"])
	if y_bot_m <= y_tbl_o - gap or y_tbl_m >= y_bot_o + gap:
		return want
	var mid_m: float = (y_tbl_m + y_bot_m) * 0.5
	var mid_o: float = (y_tbl_o + y_bot_o) * 0.5
	var nn_m: int = int(span_m["n"])
	var y_tbl_want: float
	if mid_m <= mid_o:
		y_tbl_want = y_tbl_o - gap - (y_bot_m - y_tbl_m)
	else:
		y_tbl_want = y_bot_o + gap
	var dy_fix: float = y_tbl_want + float(nn_m - 1) * rh * 0.5 + rh * 1.5
	return snappedf(dy_fix, SCH_GRID)


static func _device_layout(el) -> Dictionary:
	# Логические таблицы (left/right порты) независимы; edge — L/R край.
	# Один край на обе → стек по Y с mid_gap, ширина 1 кол. Разные края → dual.
	var left: Array = _device_side_ports(el, "left")
	var right: Array = _device_side_ports(el, "right")
	var has_l: bool = not left.is_empty()
	var has_r: bool = not right.is_empty()
	var n_l: int = left.size()
	var n_r: int = right.size()
	var n: int = maxi(maxi(n_l, n_r), 1)
	var hw: float = _device_half_w()
	var mid: float = _device_mid_gap() * 0.5
	var rh: float = _device_row_h()
	var title_h: float = SCH_GRID * 2.0
	var pad: float = _device_table_pad()
	var edge_l: String = _device_table_edge(el, "left") if has_l else ""
	var edge_r: String = _device_table_edge(el, "right") if has_r else ""
	var dual: bool = has_l and has_r and edge_l != edge_r
	var stacked: bool = has_l and has_r and edge_l == edge_r
	var x0: float
	var x1: float
	if dual:
		x0 = -(hw + mid)
		x1 = hw + mid
	elif has_l or has_r:
		x0 = -hw * 0.5
		x1 = hw * 0.5
	else:
		x0 = -(hw + mid)
		x1 = hw + mid
	var x_l0: float = x0
	var x_l1: float = x1
	var x_r0: float = x0
	var x_r1: float = x1
	if dual:
		if edge_l == "left":
			x_l0 = x0
			x_l1 = -mid
		else:
			x_l0 = mid
			x_l1 = x1
		if edge_r == "left":
			x_r0 = x0
			x_r1 = -mid
		else:
			x_r0 = mid
			x_r1 = x1
	var dy_l: float = _device_table_dy(el, "left")
	var dy_r: float = _device_table_dy(el, "right")
	if stacked:
		# Без мутации el: при пересечении сдвигаем правую логическую таблицу ниже левой.
		var gap_y: float = _device_mid_gap()
		var span_try_l: Dictionary = _device_table_y_span(n_l, dy_l, rh)
		var span_try_r: Dictionary = _device_table_y_span(n_r, dy_r, rh)
		var ok_sep: bool = (
			float(span_try_r["y_bot"]) <= float(span_try_l["y_tbl"]) - gap_y
			or float(span_try_r["y_tbl"]) >= float(span_try_l["y_bot"]) + gap_y
		)
		if not ok_sep:
			var nn_r: int = int(span_try_r["n"])
			var y_tbl_want: float = float(span_try_l["y_bot"]) + gap_y
			dy_r = snappedf(y_tbl_want + float(nn_r - 1) * rh * 0.5 + rh * 1.5, SCH_GRID)
	var span_l: Dictionary = _device_table_y_span(n_l, dy_l, rh)
	var span_r: Dictionary = _device_table_y_span(n_r, dy_r, rh)
	var y_hdr_l: float = float(span_l["y_hdr"])
	var y_hdr_r: float = float(span_r["y_hdr"])
	var y_tbl_l: float = float(span_l["y_tbl"])
	var y_tbl_r: float = float(span_r["y_tbl"])
	var y_bot_l: float = float(span_l["y_bot"])
	var y_bot_r: float = float(span_r["y_bot"])
	var y_content_top: float
	var y_content_bot: float
	if has_l and has_r:
		y_content_top = minf(y_tbl_l, y_tbl_r)
		y_content_bot = maxf(y_bot_l, y_bot_r)
	elif has_l:
		y_content_top = y_tbl_l
		y_content_bot = y_bot_l
	elif has_r:
		y_content_top = y_tbl_r
		y_content_bot = y_bot_r
	else:
		y_content_top = y_tbl_l
		y_content_bot = y_bot_l
	var y_title: float = y_content_top - pad
	var y0: float = y_title - title_h
	var y1: float = y_content_bot + pad
	var xl1: float = x_l1 if has_l else -mid
	var xr0: float = x_r0 if has_r else mid
	return {
		"left": left, "right": right, "n": n,
		"n_l": n_l, "n_r": n_r,
		"x0": x0, "x1": x1,
		"xl1": xl1, "xr0": xr0,
		"x_l0": x_l0, "x_l1": x_l1, "x_r0": x_r0, "x_r1": x_r1,
		"edge_l": edge_l, "edge_r": edge_r,
		"dual": dual, "stacked": stacked,
		"y0": y0, "y1": y1, "y_title": y_title,
		"y_tbl_l": y_tbl_l, "y_hdr_l": y_hdr_l, "y_bot_l": y_bot_l,
		"y_tbl_r": y_tbl_r, "y_hdr_r": y_hdr_r, "y_bot_r": y_bot_r,
		"y_tbl": y_tbl_l, "y_hdr": y_hdr_l, "y_bot": y_bot_l,
		"cont_w": _device_cont_w(), "rh": rh, "pad": pad,
		"dy_l": dy_l, "dy_r": dy_r,
	}


## Перенести логическую таблицу на другой край (порты не сливаются).
## Край занят → стек с зазором по Y; ширина рамки 1 колонка.
static func device_move_table_to_side(el, table: String, to_edge: String) -> void:
	if el == null or table not in ["left", "right"] or to_edge not in ["left", "right"]:
		return
	var edge_key: String = "device_table_edge_left" if table == "left" else "device_table_edge_right"
	if _device_table_edge(el, table) == to_edge:
		return
	el.set(edge_key, to_edge)
	var other: String = "right" if table == "left" else "left"
	if _device_side_ports(el, other).is_empty():
		return
	if _device_table_edge(el, other) != to_edge:
		return
	var rh: float = _device_row_h()
	var gap: float = _device_mid_gap()
	var n_other: int = _device_side_ports(el, other).size()
	var n_moved: int = _device_side_ports(el, table).size()
	var span_o: Dictionary = _device_table_y_span(n_other, _device_table_dy(el, other), rh)
	var nn_m: int = maxi(n_moved, 1)
	var y_tbl_want: float = float(span_o["y_bot"]) + gap
	var dy_m: float = y_tbl_want + float(nn_m - 1) * rh * 0.5 + rh * 1.5
	var dy_key: String = "device_table_dy_left" if table == "left" else "device_table_dy_right"
	el.set(dy_key, snappedf(dy_m, SCH_GRID))


## Полный обмен краёв L↔R. Для жеста «перенести одну» — device_move_table_to_side.
static func device_swap_table_sides(el) -> void:
	if el == null:
		return
	var e_l: String = _device_table_edge(el, "left")
	var e_r: String = _device_table_edge(el, "right")
	el.set("device_table_edge_left", e_r)
	el.set("device_table_edge_right", e_l)
	if el.get("device_table_dy_left") == null and el.get("device_table_dy_right") == null:
		return
	var tmp: float = float(el.get("device_table_dy_left"))
	el.set("device_table_dy_left", float(el.get("device_table_dy_right")))
	el.set("device_table_dy_right", tmp)


static func _device_ports(el) -> Array:
	var lay: Dictionary = _device_layout(el)
	var left: Array = lay["left"]
	var right: Array = lay["right"]
	var x_l0: float = float(lay.get("x_l0", lay["x0"]))
	var x_l1: float = float(lay.get("x_l1", lay["xl1"]))
	var x_r0: float = float(lay.get("x_r0", lay["xr0"]))
	var x_r1: float = float(lay.get("x_r1", lay["x1"]))
	var edge_l: String = str(lay.get("edge_l", "left"))
	var edge_r: String = str(lay.get("edge_r", "right"))
	var y_hdr_l: float = float(lay["y_hdr_l"])
	var y_hdr_r: float = float(lay["y_hdr_r"])
	var rh: float = float(lay["rh"])
	var out: Array = []
	for i in left.size():
		var y: float = y_hdr_l + float(i) * rh + rh * 0.5
		if edge_l == "right":
			out.append({"name": str(left[i].get("name", i)), "local": Vector2(x_l1 + LEAD_X, y), "normal": Vector2.RIGHT})
		else:
			out.append({"name": str(left[i].get("name", i)), "local": Vector2(x_l0 - LEAD_X, y), "normal": Vector2.LEFT})
	for i in right.size():
		var y: float = y_hdr_r + float(i) * rh + rh * 0.5
		if edge_r == "left":
			out.append({"name": str(right[i].get("name", i)), "local": Vector2(x_r0 - LEAD_X, y), "normal": Vector2.LEFT})
		else:
			out.append({"name": str(right[i].get("name", i)), "local": Vector2(x_r1 + LEAD_X, y), "normal": Vector2.RIGHT})
	return out


static func _device_bounds(el) -> Rect2:
	var lay: Dictionary = _device_layout(el)
	var x0: float = float(lay["x0"])
	var x1: float = float(lay["x1"])
	var y0: float = float(lay["y0"])
	var y1: float = float(lay["y1"])
	return Rect2(x0 - LEAD_X, y0, (x1 - x0) + LEAD_X * 2.0, y1 - y0)


static func _switch_npos(el) -> int:
	return maxi(int(el.switch_positions), 2)


static func _switch_rows(el) -> int:
	return maxi(int(ceil(float(maxi(el.contact_defs.size(), 2)) / 2.0)), 1)


static func _switch_pos_label(el, pi: int) -> String:
	var labels: PackedStringArray = el.switch_labels if el.switch_labels is PackedStringArray else PackedStringArray()
	var lab: String = str(labels[pi]).strip_edges() if pi < labels.size() else ""
	if lab == "":
		lab = str(pi)
	return lab


static func _switch_label_width(lab: String, font: Font = null, size: int = 9) -> float:
	var f: Font = font if font != null else ThemeDB.fallback_font
	if f != null:
		return f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return maxf(8.0, float(lab.length()) * 7.0)


## Положение SA по клику в локали УГО (ближайшая вертикаль / подпись).
static func switch_pos_at_local(el, local: Vector2) -> int:
	var npos: int = _switch_npos(el)
	var dx: float = _switch_col_dx(el)
	var x0: float = -float(npos - 1) * dx * 0.5
	var best: int = 0
	var best_d: float = 1.0e9
	for pi in npos:
		var x: float = x0 + float(pi) * dx
		var d: float = absf(local.x - x)
		if d < best_d:
			best_d = d
			best = pi
	return best


## Шаг колонок положений: не уже SW_DX и не уже самой широкой подписи (+зазор).
## Шрифт фиксируем (fallback) — тот же шаг в ports() и в draw, без расхождения.
static func _switch_col_dx(el) -> float:
	var npos: int = _switch_npos(el)
	var need: float = SW_DX
	var f: Font = ThemeDB.fallback_font
	for pi in npos:
		var w: float = _switch_label_width(_switch_pos_label(el, pi), f, 9) + 8.0
		need = maxf(need, w)
	return maxf(SW_DX, ceilf(need / SCH_GRID - 1.0e-6) * SCH_GRID)


static func _switch_port_x(el) -> float:
	# Вывод на сетке: крайняя колонка ± dx/2*(n-1), плюс один шаг сетки на отвод.
	var npos: int = _switch_npos(el)
	var dx: float = _switch_col_dx(el)
	return float(npos - 1) * dx * 0.5 + SCH_GRID * 2.0


static func _switch_ports(el) -> Array:
	var rows: int = _switch_rows(el)
	var px: float = _switch_port_x(el)
	var defs: Array = el.contact_defs
	var out: Array = []
	for ri in rows:
		var y: float = (float(ri) - float(rows - 1) * 0.5) * SW_DY
		var i0: int = ri * 2
		var nl: String = str(defs[i0].get("name", i0 + 1)) if i0 < defs.size() and typeof(defs[i0]) == TYPE_DICTIONARY else str(i0 + 1)
		var nr: String = str(defs[i0 + 1].get("name", i0 + 2)) if i0 + 1 < defs.size() and typeof(defs[i0 + 1]) == TYPE_DICTIONARY else str(i0 + 2)
		out.append({"name": nl, "local": Vector2(-px, y), "normal": Vector2.LEFT})
		out.append({"name": nr, "local": Vector2(px, y), "normal": Vector2.RIGHT})
	return out


static func _switch_bounds(el) -> Rect2:
	var rows: int = _switch_rows(el)
	var px: float = _switch_port_x(el)
	var top: float = float(rows - 1) * SW_DY * 0.5 + 22.0 # место под подписи положений
	var bot: float = float(rows - 1) * SW_DY * 0.5 + 6.0
	return Rect2(-px, -top, px * 2.0, top + bot)


# --- draw helpers ---

static func _line(ci, el, a: Vector2, b: Vector2, ink: Color, to_world: Callable, stroke_w: Callable, stroke_aa: Callable, w: float = 1.5) -> void:
	ci.draw_line(to_world.call(el, a), to_world.call(el, b), ink, stroke_w.call(w), stroke_aa.call())


static func _box(ci, el, x0: float, y0: float, x1: float, y1: float, ink: Color, to_world: Callable, stroke_w: Callable, stroke_aa: Callable) -> void:
	_line(ci, el, Vector2(x0, y0), Vector2(x1, y0), ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x1, y0), Vector2(x1, y1), ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x1, y1), Vector2(x0, y1), ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x0, y1), Vector2(x0, y0), ink, to_world, stroke_w, stroke_aa)


static func _filled_dot(ci, el, p: Vector2, ink: Color, to_world: Callable, r: float = 2.2) -> void:
	ci.draw_circle(to_world.call(el, p), r, ink)


## Текст в экранных px (как Geom._text) — без размытия при zoom; upright при любом повороте УГО.
## local = центр надписи. min_fs: для ячеек БП — 1 (иначе пол 9px раздувает текст при zoom-out).
static func _text(
	ci: CanvasItem, el, font: Font, to_world: Callable, local: Vector2, text: String, size: int, color: Color,
	min_fs: int = 9
) -> void:
	if font == null or text == "":
		return
	var world: Vector2 = to_world.call(el, local)
	var z: float = 1.0
	var pan := Vector2.ZERO
	var screen_space: bool = SymbolGeom._sch_screen_space(ci)
	var world_crisp: bool = SymbolGeom._sch_has_zoom(ci) and SymbolGeom._sch_world_xform_of(ci)
	if screen_space or world_crisp:
		z = maxf(SymbolGeom._sch_zoom_of(ci), 0.05)
	if screen_space:
		pan = SymbolGeom._sch_pan_of(ci)
	var pos: Vector2 = world
	if screen_space:
		pos = pan + world * z
	elif world_crisp:
		pos = world * z
	var floor_fs: int = maxi(min_fs, 1)
	var fs: int = maxi(size, floor_fs)
	if screen_space or world_crisp:
		fs = maxi(int(round(float(size) * z)), floor_fs)
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc: float = font.get_ascent(fs)
	var desc: float = font.get_descent(fs)
	# Baseline так, чтобы визуальный центр глифа совпал с pos.
	var origin: Vector2 = pos - Vector2(tw * 0.5, -(asc - desc) * 0.5)
	var halo := Color(1, 1, 1, 0.88) if color.r + color.g + color.b < 1.5 else Color(0.08, 0.1, 0.12, 0.5)
	if screen_space:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif world_crisp:
		SymbolGeom._begin_world_crisp_text(ci, z)
	ci.draw_string(font, origin + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
	ci.draw_string(font, origin + Vector2(-1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
	ci.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	if screen_space:
		ci.draw_set_transform(pan, 0.0, Vector2(z, z))
	elif world_crisp:
		SymbolGeom._end_world_crisp_text(ci)


static func _is_power_contact(el) -> bool:
	if str(el.recipe_id).begins_with("contactor") or str(el.electro_class) == "contactor":
		var defs: Array = el.contact_defs
		if defs.is_empty():
			return false
		var nm: String = str(defs[0].get("name", ""))
		return nm in ["1", "2", "3", "4", "5", "6"]
	return false


static func _is_timer_contact(el) -> bool:
	return str(el.recipe_id).begins_with("timer") or str(el.electro_class) == "timer_relay"


static func _contact_endpoints(y: float, t: String) -> Dictionary:
	var xl: float = -GAP
	var xr: float = GAP
	if t == "nc":
		# U580: крючок (3,0)→(3,-4); наклон (-3,0)→(4,-4.04). У нас +Y вниз.
		return {
			"hinge": Vector2(xl, y),
			"tip": Vector2(xr + NC_OVER, y + TAB + NC_TIP_EXTRA),
			"tab_from": Vector2(xr, y),
			"tab_to": Vector2(xr, y + TAB),
		}
	# U578: наклон (-3,0)→(3,+3.46) — кончик на оси правого вывода, выше провода.
	return {
		"hinge": Vector2(xl, y),
		"tip": Vector2(xr, y - NO_RISE),
		"tab_from": Vector2.ZERO,
		"tab_to": Vector2.ZERO,
	}


static func _draw_contact_pair(ci, el, y: float, t: String, ink, to_world, stroke_w, stroke_aa, power: bool = false, delay: String = "") -> void:
	var xl: float = -GAP
	var xr: float = GAP
	var w: float = CONTACT_W
	# Два отдельных горизонталя на одной линии.
	_line(ci, el, Vector2(xl - LEAD_X, y), Vector2(xl, y), ink, to_world, stroke_w, stroke_aa, w)
	_line(ci, el, Vector2(xr, y), Vector2(xr + LEAD_X, y), ink, to_world, stroke_w, stroke_aa, w)
	var actuated: bool = bool(el.energized) or bool(el.pressed)
	if t == "nc":
		_line(ci, el, Vector2(xr, y), Vector2(xr, y + TAB), ink, to_world, stroke_w, stroke_aa, w)
		if actuated:
			# НЗ разомкнут — наклон вверх, как НО.
			_line(ci, el, Vector2(xl, y), Vector2(xr, y - NO_RISE), ink, to_world, stroke_w, stroke_aa, w)
		else:
			_line(ci, el, Vector2(xl, y), Vector2(xr + NC_OVER, y + TAB + NC_TIP_EXTRA), ink, to_world, stroke_w, stroke_aa, w)
	else:
		if actuated:
			# НО замкнут — мост по оси провода.
			_line(ci, el, Vector2(xl, y), Vector2(xr, y), ink, to_world, stroke_w, stroke_aa, w)
		else:
			_line(ci, el, Vector2(xl, y), Vector2(xr, y - NO_RISE), ink, to_world, stroke_w, stroke_aa, w)
	if power:
		# Полукруг: левый конец совпадает с концом правого вывода (центр = xr + r).
		var pr: float = 2.8
		ci.draw_arc(to_world.call(el, Vector2(xr + pr, y)), pr, PI, TAU, 16, ink, stroke_w.call(w), false)
	if delay != "":
		_draw_delay_arc(ci, el, y, t, delay, actuated, ink, to_world, stroke_w, stroke_aa)


static func _delay_movable_tip(y: float, t: String, actuated: bool) -> Vector2:
	# Середина подвижной части контакта (куда доходит штрих от улыбки).
	var xl: float = -GAP
	var xr: float = GAP
	if t == "co":
		# Перекидной: покой — наклон к НЗ; сработка — мост на НО по оси.
		if actuated:
			return Vector2((xl + xr) * 0.5, y)
		return Vector2((xl + xr) * 0.5, y - 2.02 * DXF_SCALE)
	if t == "nc":
		if actuated:
			return Vector2((xl + xr) * 0.5, y - NO_RISE * 0.5)
		return Vector2((xl + xr) * 0.5 + NC_OVER * 0.5, y + (TAB + NC_TIP_EXTRA) * 0.5)
	if actuated:
		return Vector2((xl + xr) * 0.5, y)
	return Vector2((xl + xr) * 0.5, y - NO_RISE * 0.5)


static func _draw_delay_arc(ci, el, y: float, t: String, kind: String, actuated: bool, ink, to_world, stroke_w, stroke_aa) -> void:
	# Улыбка выше; штрих строго вертикально (x=0) от центра дуги до Y подвижной части.
	# both: спинами (∪ сверху + ∩ снизу, вершины в одной точке) — не кружок.
	var r: float = 4.0
	var meet: Vector2 = Vector2(0.0, y - 16.0)
	var ink_w: float = stroke_w.call(1.35)
	if kind == "both":
		ci.draw_arc(to_world.call(el, meet + Vector2(0.0, -r)), r, 0.0, PI, 18, ink, ink_w, false)
		ci.draw_arc(to_world.call(el, meet + Vector2(0.0, r)), r, PI, TAU, 18, ink, ink_w, false)
	elif kind == "on":
		ci.draw_arc(to_world.call(el, meet), r, PI, TAU, 18, ink, ink_w, false)
	elif kind == "off":
		ci.draw_arc(to_world.call(el, meet), r, 0.0, PI, 18, ink, ink_w, false)
	var tip: Vector2 = _delay_movable_tip(y, t, actuated)
	# Не тянуть к X наклонной — иначе пунктир «ломается» по диагонали.
	_draw_mech_link(ci, el, meet, Vector2(0.0, tip.y), ink, to_world, stroke_w)


static func _draw_mech_link(ci, el, from: Vector2, to: Vector2, ink, to_world, stroke_w) -> void:
	# Пунктир стойки кнопки как в DXF U584/U582: штрих ≈1.5, зазор ≈1.0.
	var a: Vector2 = to_world.call(el, from)
	var b: Vector2 = to_world.call(el, to)
	_draw_dash_line(ci, a, b, ink, BTN_DASH, BTN_DASH_GAP, stroke_w.call(CONTACT_W), false)


static func _actuator_stem_tip_y(contact_y: float, t: String) -> float:
	# Куда упирается пунктир: НЗ — вниз к крючку; перекидной — к наклону на НЗ; НО — к подъёму.
	if t == "nc":
		return contact_y + BTN_STEM
	if t == "co":
		return contact_y - 4.04 * DXF_SCALE
	return contact_y - BTN_STEM


static func _draw_button_actuator(ci, el, contact_y: float, t: String, ink, to_world, stroke_w, stroke_aa, latch: bool = false) -> void:
	if str(el.electro_class) == "e_stop":
		_draw_mushroom_actuator(ci, el, contact_y, t, ink, to_world, stroke_w, stroke_aa)
		return
	# U584 (НО) / U582 (НЗ): скоба «П»; с фиксацией — как «П», но правый конец отогнут вверх.
	var y_bar: float = contact_y - BTN_LINK
	var y_stem_top: float = y_bar + BTN_LIP
	var y_stem_bot: float = _actuator_stem_tip_y(contact_y, t)
	# С членами группы пунктир рисует overlay до последнего контакта — здесь не дублируем.
	if not button_has_members(el):
		_draw_mech_link(ci, el, Vector2(0.0, y_stem_top), Vector2(0.0, y_stem_bot), ink, to_world, stroke_w)
	_line(ci, el, Vector2(-BTN_BAR, y_bar), Vector2(BTN_BAR, y_bar), ink, to_world, stroke_w, stroke_aa, CONTACT_W)
	_line(ci, el, Vector2(-BTN_BAR, y_bar), Vector2(-BTN_BAR, y_bar + BTN_LIP), ink, to_world, stroke_w, stroke_aa, CONTACT_W)
	if latch:
		# Фиксация: правая ножка вверх (не вниз и не «коробочка»).
		_line(ci, el, Vector2(BTN_BAR, y_bar), Vector2(BTN_BAR, y_bar - BTN_LIP), ink, to_world, stroke_w, stroke_aa, CONTACT_W)
	else:
		_line(ci, el, Vector2(BTN_BAR, y_bar), Vector2(BTN_BAR, y_bar + BTN_LIP), ink, to_world, stroke_w, stroke_aa, CONTACT_W)


static func _draw_mushroom_actuator(ci, el, contact_y: float, t: String, ink, to_world, stroke_w, stroke_aa) -> void:
	# Гриб: полукруг на базе + пунктир к контакту (реф пользователя).
	var y_base: float = contact_y - BTN_LINK
	var y_stem_bot: float = _actuator_stem_tip_y(contact_y, t)
	var c: Vector2 = to_world.call(el, Vector2(0.0, y_base))
	var w: float = stroke_w.call(CONTACT_W + 0.4)
	# Godot 2D (y вниз): 0…π — нижняя полуокружность; π…τ — верхняя (гриб вверх).
	ci.draw_arc(c, MUSH_R, PI, TAU, 28, ink, w, stroke_aa.call())
	_line(ci, el, Vector2(-MUSH_R, y_base), Vector2(MUSH_R, y_base), ink, to_world, stroke_w, stroke_aa, CONTACT_W + 0.4)
	if not button_has_members(el):
		_draw_mech_link(ci, el, Vector2(0.0, y_base), Vector2(0.0, y_stem_bot), ink, to_world, stroke_w)


static func _first_type(el) -> String:
	var defs: Array = el.contact_defs
	if defs.size() > 0 and typeof(defs[0]) == TYPE_DICTIONARY:
		return str(defs[0].get("type", "no"))
	return "no"


static func _timer_delay_kind(el) -> String:
	var mode: String = str(el.timer_mode) if el != null else ""
	if mode in ["on", "off", "both"]:
		return mode
	var rid := str(el.recipe_id)
	if rid.find("off") >= 0:
		return "off"
	if rid.find("on") >= 0:
		return "on"
	var on: float = float(el.delay_on)
	var off: float = float(el.delay_off)
	if on > 0.0 and off > 0.0:
		return "both"
	if off > 0.0:
		return "off"
	if on > 0.0:
		return "on"
	return ""


static func _timer_setpoint_text(el) -> String:
	var mode: String = _timer_delay_kind(el)
	var value: float = float(el.timer_value) if el != null else 1.0
	var unit_i: int = int(el.timer_unit) if el != null else 1
	var lim: Vector2 = _ElectroLib.timer_value_limits(unit_i)
	value = clampf(roundf(value), lim.x, lim.y)
	var unit: String = _ElectroLib.timer_unit_label(unit_i)
	var val_txt: String = "%.0f%s" % [value, unit]
	match mode:
		"off":
			return "t↓%s" % val_txt
		"both":
			return "t↑↓%s" % val_txt
		"on":
			return "t↑%s" % val_txt
		_:
			return ""


static func _is_pressure_switch_contact(el) -> bool:
	# Контакт KP1.1: caption «P» или group_template у primary.
	if el == null:
		return false
	if str(el.caption) == "P":
		return true
	if str(el.member_role) == "contact" and str(el.group_tag).begins_with("KP"):
		return true
	return false


static func _is_pressure_tx_terminal(el) -> bool:
	if el == null:
		return false
	if str(el.member_role) == "device" and str(el.group_tag).begins_with("PT"):
		return true
	if str(el.member_role) == "device" and str(el.electro_class) == "generic_device" \
			and str(el.recipe_id).begins_with("pressure_tx"):
		return true
	return false


static func _is_rtd_meter(el) -> bool:
	if el == null:
		return false
	if str(el.electro_class) == "rtd_meter":
		return true
	if str(el.member_role) == "device" and str(el.group_tag).begins_with("SK"):
		return true
	if str(el.member_role) == "device" and str(el.recipe_id).begins_with("rtd_"):
		return true
	return false


static func _draw_contact(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	var defs: Array = el.contact_defs
	var power: bool = _is_power_contact(el)
	var delay: String = ""
	# Улыбка на каждом контакте KT (задержка относится ко всем).
	if _is_timer_contact(el):
		delay = _timer_delay_kind(el)
	var ps_act: bool = _is_pressure_switch_contact(el)
	if defs.is_empty():
		_draw_contact_pair(ci, el, 0.0, "no", ink, to_world, stroke_w, stroke_aa, power, delay)
		if ps_act:
			_draw_pressure_actuator(ci, el, 0.0, "no", ink, to_world, stroke_w, stroke_aa)
		return
	if typeof(defs[0]) == TYPE_DICTIONARY and str(defs[0].get("type", "")) == "co":
		_draw_changeover(ci, el, 0.0, ink, to_world, stroke_w, stroke_aa, delay)
		if ps_act:
			_draw_pressure_actuator(ci, el, 0.0, "co", ink, to_world, stroke_w, stroke_aa)
		return
	var pairs: int = int(ceil(float(defs.size()) / 2.0))
	for pi in pairs:
		var y: float = (float(pi) - float(pairs - 1) * 0.5) * ROW_H
		var t := "no"
		var i0: int = pi * 2
		if i0 < defs.size() and typeof(defs[i0]) == TYPE_DICTIONARY:
			t = str(defs[i0].get("type", "no"))
		_draw_contact_pair(ci, el, y, t, ink, to_world, stroke_w, stroke_aa, power, delay)
		if ps_act and pi == 0:
			_draw_pressure_actuator(ci, el, y, t, ink, to_world, stroke_w, stroke_aa)


## Половина ширины/высоты рамки «P» (зазор вокруг буквы ~1.5–2 ед.).
static func _pressure_act_box_hw() -> float:
	return 7.2


static func _pressure_act_box_hh() -> float:
	return 10.5


## Прямоугольник + буква «P» (штрихи пневмо-УГО), буква по центру рамки.
static func _draw_pressure_actuator(ci, el, contact_y: float, t: String, ink, to_world, stroke_w, stroke_aa) -> void:
	var box_hw: float = _pressure_act_box_hw()
	var box_hh: float = _pressure_act_box_hh()
	var y_box: float = contact_y - BTN_LINK - box_hh * 0.15
	var y_stem_bot: float = _actuator_stem_tip_y(contact_y, t)
	var y_stem_top: float = y_box + box_hh
	_draw_mech_link(ci, el, Vector2(0.0, y_stem_top), Vector2(0.0, y_stem_bot), ink, to_world, stroke_w)
	var sw: float = stroke_w.call(CONTACT_W * 1.15)
	var aa: bool = bool(stroke_aa.call())
	var corners: PackedVector2Array = PackedVector2Array([
		to_world.call(el, Vector2(-box_hw, y_box - box_hh)),
		to_world.call(el, Vector2(box_hw, y_box - box_hh)),
		to_world.call(el, Vector2(box_hw, y_box + box_hh)),
		to_world.call(el, Vector2(-box_hw, y_box + box_hh)),
		to_world.call(el, Vector2(-box_hw, y_box - box_hh)),
	])
	ci.draw_polyline(corners, ink, sw, aa)
	# Центрируем DXF-букву P внутри рамки.
	var raw: Array = _pressure_ugo_letter_p_strokes()
	var min_x: float = 1.0e9
	var max_x: float = -1.0e9
	var min_y: float = 1.0e9
	var max_y: float = -1.0e9
	for item0 in raw:
		var st0: PackedVector2Array = item0 as PackedVector2Array
		for p0 in st0:
			min_x = minf(min_x, p0.x)
			max_x = maxf(max_x, p0.x)
			min_y = minf(min_y, p0.y)
			max_y = maxf(max_y, p0.y)
	var cx: float = 0.5 * (min_x + max_x)
	var cy: float = 0.5 * (min_y + max_y)
	for item in raw:
		var stroke: PackedVector2Array = item as PackedVector2Array
		if stroke.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in stroke:
			pts.append(to_world.call(el, Vector2(p.x - cx, y_box + (p.y - cy))))
		ci.draw_polyline(pts, ink, sw, aa)


## Штрихи буквы «P» из пневмо-УГО (сырые DXF-координаты).
static func _pressure_ugo_letter_p_strokes() -> Array:
	return [
		PackedVector2Array([Vector2(-12.188, -1.875), Vector2(-12.188, 13.125)]),
		PackedVector2Array([Vector2(-12.188, -1.875), Vector2(-7.5, -1.875)]),
		PackedVector2Array([Vector2(-7.5, 7.5), Vector2(-12.188, 7.5)]),
		PackedVector2Array([
			Vector2(-7.5, -1.875), Vector2(-7.2, -1.8), Vector2(-6.937, -1.725),
			Vector2(-6.637, -1.613), Vector2(-6.375, -1.5), Vector2(-6.113, -1.35),
			Vector2(-5.85, -1.2), Vector2(-5.588, -1.05), Vector2(-5.363, -0.863),
			Vector2(-5.137, -0.637), Vector2(-4.95, -0.45), Vector2(-4.725, -0.225),
			Vector2(-4.575, 0.0), Vector2(-4.387, 0.262), Vector2(-4.238, 0.525),
			Vector2(-4.125, 0.787), Vector2(-3.975, 1.05), Vector2(-3.9, 1.35),
			Vector2(-3.787, 1.613), Vector2(-3.75, 1.912), Vector2(-3.713, 2.213),
			Vector2(-3.675, 2.512), Vector2(-3.675, 2.812), Vector2(-3.675, 3.113),
			Vector2(-3.713, 3.412), Vector2(-3.75, 3.713), Vector2(-3.787, 4.012),
			Vector2(-3.9, 4.275), Vector2(-3.975, 4.575), Vector2(-4.125, 4.838),
			Vector2(-4.238, 5.1), Vector2(-4.387, 5.363), Vector2(-4.575, 5.625),
			Vector2(-4.725, 5.85), Vector2(-4.95, 6.075), Vector2(-5.137, 6.262),
			Vector2(-5.363, 6.488), Vector2(-5.588, 6.675), Vector2(-5.85, 6.825),
			Vector2(-6.113, 6.975), Vector2(-6.375, 7.125), Vector2(-6.637, 7.238),
			Vector2(-6.937, 7.35), Vector2(-7.2, 7.425), Vector2(-7.5, 7.5),
		]),
	]


static func _draw_changeover(ci, el, y: float, ink, to_world, stroke_w, stroke_aa, delay: String = "") -> void:
	# U579: общий слева на оси, НО справа на оси, НЗ сверху (−2 клетки) с вертикалью.
	# Норма — наклон к НЗ вверх (−3,0)→(4,4.04); актив — мост на НО по оси.
	var xl: float = -GAP
	var xr: float = GAP
	var w: float = CONTACT_W
	var y_nc: float = y - 2.0 * SCH_GRID
	var tip_nc := Vector2(xr + NC_OVER, y - 4.04 * DXF_SCALE)
	_line(ci, el, Vector2(xl - LEAD_X, y), Vector2(xl, y), ink, to_world, stroke_w, stroke_aa, w)
	_line(ci, el, Vector2(xr, y), Vector2(xr + LEAD_X, y), ink, to_world, stroke_w, stroke_aa, w)
	_line(ci, el, Vector2(xr, y_nc), Vector2(xr + LEAD_X, y_nc), ink, to_world, stroke_w, stroke_aa, w)
	_line(ci, el, Vector2(xr, y - 2.0 * DXF_SCALE), Vector2(xr, y_nc), ink, to_world, stroke_w, stroke_aa, w)
	var to_no: bool = bool(el.energized) or bool(el.pressed)
	if to_no:
		_line(ci, el, Vector2(xl, y), Vector2(xr + NC_OVER, y), ink, to_world, stroke_w, stroke_aa, w)
	else:
		_line(ci, el, Vector2(xl, y), tip_nc, ink, to_world, stroke_w, stroke_aa, w)
	if delay != "":
		_draw_delay_arc(ci, el, y, "co", delay, to_no, ink, to_world, stroke_w, stroke_aa)


static func _draw_button(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	var latch: bool = bool(el.latching) or str(el.electro_class) == "e_stop"
	var tt := _first_type(el)
	if button_has_members(el):
		# Контакты рисуют члены группы — primary только актуатор.
		_draw_button_actuator(ci, el, 0.0, tt, ink, to_world, stroke_w, stroke_aa, latch)
		return
	var defs: Array = el.contact_defs
	var pairs: int = maxi(int(ceil(float(maxi(defs.size(), 2)) / 2.0)), 1)
	for pi in pairs:
		var y: float = (float(pi) - float(pairs - 1) * 0.5) * 20.0
		var t2 := "no"
		var i0: int = pi * 2
		if i0 < defs.size() and typeof(defs[i0]) == TYPE_DICTIONARY:
			t2 = str(defs[i0].get("type", "no"))
		if t2 == "co":
			_draw_changeover(ci, el, y, ink, to_world, stroke_w, stroke_aa)
		else:
			_draw_contact_pair(ci, el, y, t2, ink, to_world, stroke_w, stroke_aa)
		if pi == 0:
			_draw_button_actuator(ci, el, y, t2 if t2 != "co" else "no", ink, to_world, stroke_w, stroke_aa, latch)


static func _draw_switch(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	# Вертикали = положения; горизонтали = контакты; точки = замыкание по switch_map.
	if typeof(el.switch_map) != TYPE_ARRAY or el.switch_map.is_empty():
		# Ленивая нормализация без зависимости от ElectroLibrary в draw-пути.
		var npos0: int = maxi(int(el.switch_positions), 2)
		el.switch_positions = npos0
		var nrows0: int = _switch_rows(el)
		var neu: Array = []
		for ri0 in nrows0:
			var row0: Array = []
			for pi0 in npos0:
				row0.append(pi0 == (ri0 % npos0))
			neu.append(row0)
		el.switch_map = neu
	var rows: int = _switch_rows(el)
	var npos: int = _switch_npos(el)
	var dx: float = _switch_col_dx(el)
	var px: float = _switch_port_x(el)
	var x0: float = -float(npos - 1) * dx * 0.5
	var y_top: float = -float(rows - 1) * SW_DY * 0.5 - 10.0
	var y_bot: float = float(rows - 1) * SW_DY * 0.5 + 6.0
	var cur: int = clampi(int(el.switch_pos), 0, npos - 1)
	for pi in npos:
		var x: float = x0 + float(pi) * dx
		_line(ci, el, Vector2(x, y_top + 6.0), Vector2(x, y_bot), ink, to_world, stroke_w, stroke_aa, 1.2)
		var lab: String = _switch_pos_label(el, pi)
		var tw: float = _switch_label_width(lab, font, 9)
		# Центр подписи = ось колонки; шаг dx уже ≥ ширины + зазор — без налезаний.
		_text(ci, el, font, to_world, Vector2(x - tw * 0.5, y_top - 2.0), lab, 9, ink)
	var map: Array = el.switch_map if typeof(el.switch_map) == TYPE_ARRAY else []
	for ri in rows:
		var y: float = (float(ri) - float(rows - 1) * 0.5) * SW_DY
		_line(ci, el, Vector2(-px, y), Vector2(x0, y), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x0 + float(npos - 1) * dx, y), Vector2(px, y), ink, to_world, stroke_w, stroke_aa)
		var row: Array = map[ri] if ri < map.size() and typeof(map[ri]) == TYPE_ARRAY else []
		for pi2 in npos:
			var closed: bool = bool(row[pi2]) if pi2 < row.size() else (pi2 == (ri % npos))
			if not closed:
				continue
			var x2: float = x0 + float(pi2) * dx
			# Текущее положение — чуть крупнее точка.
			_filled_dot(ci, el, Vector2(x2, y), ink, to_world, 2.8 if pi2 == cur else 2.2)


static func _draw_coil(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	var hw: float = coil_body_hw(el)
	var hh: float = coil_body_hh(el)
	_box(ci, el, -hw, -hh, hw, hh, ink, to_world, stroke_w, stroke_aa)
	if coil_side_leads(el):
		# Вертикальный корпус: A1← / A2→; низ свободен под мехсвязь.
		_line(ci, el, Vector2(-hw, 0), Vector2(-hw - LEAD_X, 0), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(hw, 0), Vector2(hw + LEAD_X, 0), ink, to_world, stroke_w, stroke_aa)
	else:
		# ЭМ: горизонтальный, A1↑ / A2↓.
		_line(ci, el, Vector2(0, -hh), Vector2(0, -hh - LEAD_X), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(0, hh), Vector2(0, hh + LEAD_X), ink, to_world, stroke_w, stroke_aa)
	var cls := str(el.electro_class)
	if cls == "timer_relay":
		# Отсек с X сверху: диагонали в углы прямоугольника отсека.
		var y0: float = -hh
		var y1: float = -hh + SCH_GRID
		_line(ci, el, Vector2(-hw, y1), Vector2(hw, y1), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(-hw, y0), Vector2(hw, y1), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(hw, y0), Vector2(-hw, y1), ink, to_world, stroke_w, stroke_aa)
		# Уставка рядом с катушкой KT (синхрон с крутилками 3D).
		if font != null:
			var delay_txt: String = _timer_setpoint_text(el)
			if delay_txt != "":
				_text(ci, el, font, to_world, Vector2(hw + 4.0, -2.0), delay_txt, 9, ink)
	if cls == "solenoid_coil":
		# Пилот клапана справа: пунктир + два треугольника остриём друг к другу.
		var jx: float = hw + 12.0
		_draw_dash_line(
			ci,
			to_world.call(el, Vector2(hw, 0)),
			to_world.call(el, Vector2(jx, 0)),
			ink, 2.0, 1.6, stroke_w.call(1.35), false
		)
		var pw: float = 11.0
		var half_h: float = 9.0
		var pts_top := PackedVector2Array([
			to_world.call(el, Vector2(jx, 0)),
			to_world.call(el, Vector2(jx - pw * 0.5, -half_h)),
			to_world.call(el, Vector2(jx + pw * 0.5, -half_h)),
			to_world.call(el, Vector2(jx, 0)),
		])
		var pts_bot := PackedVector2Array([
			to_world.call(el, Vector2(jx, 0)),
			to_world.call(el, Vector2(jx - pw * 0.5, half_h)),
			to_world.call(el, Vector2(jx + pw * 0.5, half_h)),
			to_world.call(el, Vector2(jx, 0)),
		])
		ci.draw_polyline(pts_top, ink, stroke_w.call(1.5), false)
		ci.draw_polyline(pts_bot, ink, stroke_w.call(1.5), false)
		_line(ci, el, Vector2(jx, -half_h), Vector2(jx, -half_h - 6.0), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(jx, half_h), Vector2(jx, half_h + 6.0), ink, to_world, stroke_w, stroke_aa)
	if bool(el.energized):
		ci.draw_rect(Rect2(to_world.call(el, Vector2(-hw + 1, -hh + 1)), Vector2((hw - 1) * 2.0, (hh - 1) * 2.0)), Color(0.2, 0.7, 0.35, 0.16), true)


static func _draw_lamp(ci, el, ink, to_world, stroke_w, stroke_aa, omit_glow: bool = false) -> void:
	_line(ci, el, Vector2(-LAMP_R - LEAD_X, 0), Vector2(-LAMP_R, 0), ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(LAMP_R, 0), Vector2(LAMP_R + LEAD_X, 0), ink, to_world, stroke_w, stroke_aa)
	ci.draw_arc(to_world.call(el, Vector2.ZERO), LAMP_R, 0.0, TAU, 32, ink, stroke_w.call(1.5), stroke_aa.call())
	var x: float = LAMP_R * 0.7
	_line(ci, el, Vector2(-x, -x), Vector2(x, x), ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x, -x), Vector2(-x, x), ink, to_world, stroke_w, stroke_aa)
	# omit_glow: корпус на Base; свечение — SchemeAnim (Base заморожен при Run).
	if omit_glow:
		return
	_draw_lamp_glow(ci, el, to_world)


static func draw_lamp_motion(ci: CanvasItem, el, to_world: Callable) -> void:
	if el == null or str(el.electro_class) != "lamp":
		return
	_draw_lamp_glow(ci, el, to_world)


static func _draw_lamp_glow(ci, el, to_world: Callable) -> void:
	if not bool(el.lit):
		return
	var glow: Color = _lamp_glow_color(str(el.lamp_color))
	ci.draw_circle(to_world.call(el, Vector2.ZERO), LAMP_R * 0.85, Color(glow.r, glow.g, glow.b, 0.55))
	ci.draw_circle(to_world.call(el, Vector2.ZERO), LAMP_R * 0.45, Color(glow.r, glow.g, glow.b, 0.75))


static func _lamp_glow_color(name: String) -> Color:
	match name:
		"red":
			return Color(1.0, 0.25, 0.18)
		"green":
			return Color(0.25, 0.95, 0.35)
		"yellow":
			return Color(1.0, 0.9, 0.2)
		_:
			return Color(1.0, 0.95, 0.75)


static func _draw_breaker(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	# Реф ugo_mcb_*: крест сверху, прямоугольник слева на ключе (без кружка шарнира).
	# Реф ugo_rcd_*: овал ТТ + связь; двойная мехсвязь попадает в ключи.
	var poles: int = _breaker_pole_count(el)
	var cls := str(el.electro_class)
	var has_cross: bool = cls in ["mcb", "rcbo"]
	var has_auto: bool = cls in ["mcb", "rcbo"]
	var has_diff: bool = cls in ["rcd", "rcbo"]
	var x0: float = -float(poles - 1) * POLE_DX * 0.5
	var y_top: float = BRK_TOP
	var y_bot: float = BRK_BOT
	var hinge_y: float = y_bot - 2.0
	var open: bool = not bool(el.closed)
	var link_t: float = 0.55 # доля вдоль ключа для двойной связи
	# УЗО: выводы снизу на 2 клетки ниже овала.
	var bot_stub: float = BRK_STUB + (2.0 * SCH_GRID if has_diff else 0.0)
	var hinges: Array = []
	var tips: Array = []
	for i in poles:
		var x: float = x0 + float(i) * POLE_DX
		_line(ci, el, Vector2(x, y_top - BRK_STUB), Vector2(x, y_top), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x, hinge_y), Vector2(x, y_bot + bot_stub), ink, to_world, stroke_w, stroke_aa)
		var hinge := Vector2(x, hinge_y)
		# Замкнут: ключ до верхнего вывода (видимое замыкание); разомкнут — наклон влево.
		var tip: Vector2 = Vector2(x - 11.0, y_top + 8.0) if open else Vector2(x, y_top)
		hinges.append(hinge)
		tips.append(tip)
		_line(ci, el, hinge, tip, ink, to_world, stroke_w, stroke_aa)
		if not open:
			# Точка контакта на верхнем выводе — читается «замкнуто».
			_filled_dot(ci, el, Vector2(x, y_top), ink, to_world, 2.2)
		# УЗО/АВДТ: N / L1… у верхнего вывода — куда что сажать.
		if has_diff and font != null:
			var role: String = _ElectroLib.port_diff_line_role(el, str(i * 2 + 1))
			if role != "":
				_text(ci, el, font, to_world, Vector2(x + 5.0, y_top - BRK_STUB - 2.0), role, 8, ink)
		if has_cross:
			_line(ci, el, Vector2(x - 4.0, y_top - 4.0), Vector2(x + 4.0, y_top + 4.0), ink, to_world, stroke_w, stroke_aa, 1.25)
			_line(ci, el, Vector2(x + 4.0, y_top - 4.0), Vector2(x - 4.0, y_top + 4.0), ink, to_world, stroke_w, stroke_aa, 1.25)
		if has_auto and i == 0:
			# Прямоугольник слева от ключа: низ на линии, шире чем выше.
			var along: Vector2 = (tip - hinge).normalized()
			var perp := Vector2(along.y, -along.x) # наружу влево от наклона
			var mid: Vector2 = hinge.lerp(tip, 0.42)
			var half_len: float = 5.5
			var half_th: float = 2.2
			var c0: Vector2 = mid - along * half_len + perp * 0.2
			var c1: Vector2 = mid + along * half_len + perp * 0.2
			var c2: Vector2 = mid + along * half_len + perp * (half_th * 2.0 + 0.2)
			var c3: Vector2 = mid - along * half_len + perp * (half_th * 2.0 + 0.2)
			_line(ci, el, c0, c1, ink, to_world, stroke_w, stroke_aa, 1.2)
			_line(ci, el, c1, c2, ink, to_world, stroke_w, stroke_aa, 1.2)
			_line(ci, el, c2, c3, ink, to_world, stroke_w, stroke_aa, 1.2)
			_line(ci, el, c3, c0, ink, to_world, stroke_w, stroke_aa, 1.2)
	var link0: Vector2 = hinges[0].lerp(tips[0], link_t)
	var link1: Vector2 = hinges[poles - 1].lerp(tips[poles - 1], link_t)
	if poles > 1:
		# Двойная связь горизонтально через точки на ключах (не «слипшийся» наклон).
		var my: float = (link0.y + link1.y) * 0.5
		_line(ci, el, Vector2(link0.x, my - 1.6), Vector2(link1.x, my - 1.6), ink, to_world, stroke_w, stroke_aa, 1.25)
		_line(ci, el, Vector2(link0.x, my + 1.6), Vector2(link1.x, my + 1.6), ink, to_world, stroke_w, stroke_aa, 1.25)
	if has_diff:
		var cx: float = x0 + float(poles - 1) * POLE_DX * 0.5
		var cy: float = hinge_y + 12.0
		var rx: float = float(poles - 1) * POLE_DX * 0.5 + 8.0
		var ry: float = 5.0
		var oval := PackedVector2Array()
		for a in 36:
			var ang: float = TAU * float(a) / 36.0
			oval.append(to_world.call(el, Vector2(cx + cos(ang) * rx, cy + sin(ang) * ry)))
		oval.append(oval[0])
		ci.draw_polyline(oval, ink, stroke_w.call(1.35), false)
		var left_x: float = cx - rx
		_line(ci, el, Vector2(left_x, cy), Vector2(left_x - 6.0, cy), ink, to_world, stroke_w, stroke_aa, 1.2)
		_line(ci, el, Vector2(left_x - 6.0, cy), Vector2(left_x - 6.0, link0.y), ink, to_world, stroke_w, stroke_aa, 1.2)
		_line(ci, el, Vector2(left_x - 6.0, link0.y), link0, ink, to_world, stroke_w, stroke_aa, 1.2)
	if font != null and cls == "mcb":
		_text(ci, el, font, to_world, Vector2(x0 + float(poles - 1) * POLE_DX + 10.0, -2), "%s%.0f" % [str(el.curve), float(el.rating_a)], 10, ink)
	elif font != null and cls == "rcbo":
		_text(ci, el, font, to_world, Vector2(x0 + float(poles - 1) * POLE_DX + 10.0, -2), "%s%.0f/%.0fмА" % [str(el.curve), float(el.rating_a), float(el.i_delta_ma)], 9, ink)
	elif font != null and cls == "rcd":
		_text(ci, el, font, to_world, Vector2(x0 + float(poles - 1) * POLE_DX + 10.0, -2), "%.0fА/%.0fмА" % [float(el.rating_a), float(el.i_delta_ma)], 9, ink)


static func _supply_names(el) -> PackedStringArray:
	var defs: Array = el.electro_ports
	if defs.size() >= 1:
		var names := PackedStringArray()
		for p in defs:
			if typeof(p) == TYPE_DICTIONARY:
				var nm: String = str(p.get("name", ""))
				if nm != "":
					names.append(nm)
		if names.size() >= 1:
			return names
	# 1ф по умолчанию; poles>=3 → 3ф без PE в списке портов схемы.
	if int(el.poles) >= 3:
		return PackedStringArray(["L1", "L2", "L3", "N"])
	return PackedStringArray(["L", "N", "PE"])


static func _supply_ports(el) -> Array:
	var names: PackedStringArray = _supply_names(el)
	var n: int = names.size()
	var y_top: float = -float(n) * ROW_H * 0.5
	var out: Array = []
	for i in n:
		var y: float = y_top + float(i) * ROW_H + ROW_H * 0.5
		out.append({"name": str(names[i]), "local": Vector2(30.0 + LEAD_X, y), "normal": Vector2.RIGHT})
	return out


static func _supply_leg_ports(el) -> Array:
	var nm: String = str(el.phase) if str(el.phase) != "" else str(el.caption)
	if nm == "":
		var defs: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
		if defs.size() > 0 and typeof(defs[0]) == TYPE_DICTIONARY:
			nm = str(defs[0].get("name", "L"))
	if nm == "":
		nm = "L"
	return [{"name": nm, "local": Vector2(30.0 + LEAD_X, 0.0), "normal": Vector2.RIGHT}]


static func _supply_bounds(el) -> Rect2:
	var n: int = maxi(_supply_names(el).size(), 3)
	var h: float = float(n) * ROW_H
	# Рамка −4…30 + вывод LEAD_X; без лишнего pad.
	return Rect2(-4.0, -h * 0.5, 30.0 + LEAD_X + 4.0, h)


static func _supply_leg_bounds(_el) -> Rect2:
	return Rect2(-4.0, -ROW_H * 0.5, 30.0 + LEAD_X + 4.0, ROW_H)


static func _supply_is_base_row(el) -> bool:
	# Primary с одним портом L (или L1) — база; N/PE рисуют supply_leg.
	var defs: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
	return str(el.member_role) == "main" and defs.size() <= 1


static func _draw_supply(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	# База XS = ряд L (без пустого квадрата сверху). Не смотреть _supply_names fallback.
	if _supply_is_base_row(el):
		_draw_supply_leg(ci, el, ink, to_world, stroke_w, stroke_aa, font)
		return
	var names: PackedStringArray = _supply_names(el)
	# Прямоугольник-источник: строки L/N/PE (или L1…N), выводы справа на сетке.
	var n: int = names.size()
	var y_top: float = -float(n) * ROW_H * 0.5
	var y_bot: float = y_top + float(n) * ROW_H
	var x0: float = -4.0
	var x1: float = 30.0
	_box(ci, el, x0, y_top, x1, y_bot, ink, to_world, stroke_w, stroke_aa)
	for i in n:
		var y0: float = y_top + float(i) * ROW_H
		var yc: float = y0 + ROW_H * 0.5
		if i > 0:
			_line(ci, el, Vector2(x0, y0), Vector2(x1, y0), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x1, yc), Vector2(x1 + LEAD_X, yc), ink, to_world, stroke_w, stroke_aa)
		if font != null:
			var lab: String = str(names[i])
			# Центр ячейки — выравнивание текста в экранных px делает _text.
			_text(ci, el, font, to_world, Vector2((x0 + x1) * 0.5, yc), lab, 10, ink)


static func _draw_supply_leg(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	var nm: String = str(el.phase) if str(el.phase) != "" else str(el.caption)
	if nm == "":
		nm = "L"
	var x0: float = -4.0
	var x1: float = 30.0
	var y0: float = -ROW_H * 0.5
	var y1: float = ROW_H * 0.5
	_box(ci, el, x0, y0, x1, y1, ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x1, 0.0), Vector2(x1 + LEAD_X, 0.0), ink, to_world, stroke_w, stroke_aa)
	if font != null:
		_text(ci, el, font, to_world, Vector2((x0 + x1) * 0.5, 0.0), nm, 10, ink)


static func _draw_terminal_table(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	# Ряд tips с шагом pitch; высота всегда 2 клетки. Tag колодки — над блоком.
	var lay: Dictionary = _terminal_layout(el)
	var n: int = int(lay["n"])
	var step: float = float(lay["step"])
	var x_first: float = float(lay["x_first"])
	var x0: float = float(lay["x0"])
	var x1: float = float(lay["x1"])
	var y0: float = float(lay["y0"])
	var y1: float = float(lay["y1"])
	var poles: int = _term_pole_count(el)
	var bus: bool = bool(el.terminal_bus) and poles > 1 and str(el.phase) == ""
	var names: Array = lay.get("names", []) as Array
	_box(ci, el, x0, y0, x1, y1, ink, to_world, stroke_w, stroke_aa)
	# Перегородки между видимыми полюсами (плотный ряд), не внутри пары.
	if not bus:
		for i in range(2, n, 2):
			var xv: float = x_first + (float(i) - 0.5) * step
			xv = snappedf(xv, SCH_GRID)
			_line(ci, el, Vector2(xv, y0), Vector2(xv, y1), ink, to_world, stroke_w, stroke_aa)
	var r_dot: float = SCH_GRID * 0.5 # Ø = 1 клетка
	for i in names.size():
		var pname: String = str(names[i])
		var cx: float = x_first + float(i) * step
		var c := Vector2(cx, 0.0)
		_filled_dot(ci, el, c, ink, to_world, r_dot)
		if font != null:
			_text(ci, el, font, to_world, c + Vector2(0.0, -r_dot - 3.5), pname, 9, ink)


static func _draw_screw_term(ci, el, p: Vector2, ink, to_world, stroke_w, stroke_aa) -> void:
	ci.draw_arc(to_world.call(el, p), 3.2, 0.0, TAU, 16, ink, stroke_w.call(1.35), stroke_aa.call())
	_line(ci, el, p + Vector2(-2.4, 2.4), p + Vector2(2.4, -2.4), ink, to_world, stroke_w, stroke_aa, 1.2)


static func _draw_busbar(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	var defs: Array = el.electro_ports
	var n: int = maxi(defs.size(), 1)
	var x1: float = 10.0 + float(n - 1) * ROW_H + 10.0
	_box(ci, el, 0, -5, x1, 5, ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(0, -5), Vector2(x1, -5), ink, to_world, stroke_w, stroke_aa, 2.0)
	_line(ci, el, Vector2(0, 5), Vector2(x1, 5), ink, to_world, stroke_w, stroke_aa, 2.0)
	for i in n:
		var x: float = 10.0 + float(i) * ROW_H
		_filled_dot(ci, el, Vector2(x, 0), ink, to_world, 2.5)
		_line(ci, el, Vector2(x, 5), Vector2(x, 20), ink, to_world, stroke_w, stroke_aa)
	if font != null and str(el.caption) != "":
		_text(ci, el, font, to_world, Vector2(x1 * 0.5 - 4.0, -14.0), str(el.caption), 10, ink)


static func _device_cell_text(ci, el, font: Font, to_world: Callable, cell: Rect2, text: String, size: int, ink: Color) -> void:
	# Центр ячейки → _text (он сам центрирует). size подгоняем под ширину/высоту ячейки.
	if font == null or text == "":
		return
	var max_w: float = maxf(cell.size.x - 2.0, 4.0)
	var max_h: float = maxf(cell.size.y - 2.0, 4.0)
	while size > 6:
		var tw: float = _switch_label_width(text, font, size)
		var th: float = float(size) + 2.0
		if tw <= max_w and th <= max_h:
			break
		size -= 1
	var cx: float = cell.position.x + cell.size.x * 0.5
	var cy: float = cell.position.y + cell.size.y * 0.5
	_text(ci, el, font, to_world, Vector2(cx, cy), text, size, ink, 1)


static func _draw_device_table_block(
	ci, el, ink, to_world, stroke_w, stroke_aa, font: Font,
	ports: Array, n_rows: int, edge: String,
	xe0: float, xe1: float, y_tbl: float, y_hdr: float, y_bot: float,
	cont_w: float, rh: float
) -> void:
	if ports.is_empty():
		return
	_box(ci, el, xe0, y_tbl, xe1, y_bot, ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(xe0, y_hdr), Vector2(xe1, y_hdr), ink, to_world, stroke_w, stroke_aa)
	var cont_left: bool = edge != "right"
	if cont_left:
		_line(ci, el, Vector2(xe0 + cont_w, y_tbl), Vector2(xe0 + cont_w, y_bot), ink, to_world, stroke_w, stroke_aa)
		_device_cell_text(ci, el, font, to_world, Rect2(xe0, y_tbl, cont_w, rh), "Конт.", 9, ink)
		_device_cell_text(ci, el, font, to_world, Rect2(xe0 + cont_w, y_tbl, xe1 - (xe0 + cont_w), rh), "Цепь", 9, ink)
	else:
		_line(ci, el, Vector2(xe1 - cont_w, y_tbl), Vector2(xe1 - cont_w, y_bot), ink, to_world, stroke_w, stroke_aa)
		_device_cell_text(ci, el, font, to_world, Rect2(xe0, y_tbl, (xe1 - cont_w) - xe0, rh), "Цепь", 9, ink)
		_device_cell_text(ci, el, font, to_world, Rect2(xe1 - cont_w, y_tbl, cont_w, rh), "Конт.", 9, ink)
	for i in n_rows:
		var y_row: float = y_hdr + float(i) * rh
		if i > 0:
			_line(ci, el, Vector2(xe0, y_row), Vector2(xe1, y_row), ink, to_world, stroke_w, stroke_aa)
		if i >= ports.size():
			continue
		var yc: float = y_row + rh * 0.5
		var nm: String = str(ports[i].get("name", ""))
		var circ: String = _device_port_circuit(ports[i] as Dictionary)
		if cont_left:
			_line(ci, el, Vector2(xe0 - LEAD_X, yc), Vector2(xe0, yc), ink, to_world, stroke_w, stroke_aa, CONTACT_W)
			_device_cell_text(ci, el, font, to_world, Rect2(xe0, y_row, cont_w, rh), nm, 9, ink)
			_device_cell_text(ci, el, font, to_world, Rect2(xe0 + cont_w, y_row, xe1 - (xe0 + cont_w), rh), circ, 8, ink)
		else:
			_line(ci, el, Vector2(xe1, yc), Vector2(xe1 + LEAD_X, yc), ink, to_world, stroke_w, stroke_aa, CONTACT_W)
			_device_cell_text(ci, el, font, to_world, Rect2(xe0, y_row, (xe1 - cont_w) - xe0, rh), circ, 8, ink)
			_device_cell_text(ci, el, font, to_world, Rect2(xe1 - cont_w, y_row, cont_w, rh), nm, 9, ink)


static func _draw_device(ci, el, ink, to_world, stroke_w, stroke_aa, font: Font = null) -> void:
	# Одна внешняя рамка; шапка flush; таблицы по edge (стек или dual, без слияния портов).
	var lay: Dictionary = _device_layout(el)
	var left: Array = lay["left"]
	var right: Array = lay["right"]
	var n_l: int = int(lay.get("n_l", left.size()))
	var n_r: int = int(lay.get("n_r", right.size()))
	var x0: float = float(lay["x0"])
	var x1: float = float(lay["x1"])
	var x_l0: float = float(lay.get("x_l0", x0))
	var x_l1: float = float(lay.get("x_l1", lay["xl1"]))
	var x_r0: float = float(lay.get("x_r0", lay["xr0"]))
	var x_r1: float = float(lay.get("x_r1", x1))
	var edge_l: String = str(lay.get("edge_l", "left"))
	var edge_r: String = str(lay.get("edge_r", "right"))
	var y0: float = float(lay["y0"])
	var y1: float = float(lay["y1"])
	var y_title: float = float(lay["y_title"])
	var y_tbl_l: float = float(lay["y_tbl_l"])
	var y_hdr_l: float = float(lay["y_hdr_l"])
	var y_bot_l: float = float(lay["y_bot_l"])
	var y_tbl_r: float = float(lay["y_tbl_r"])
	var y_hdr_r: float = float(lay["y_hdr_r"])
	var y_bot_r: float = float(lay["y_bot_r"])
	var cont_w: float = float(lay["cont_w"])
	var rh: float = float(lay["rh"])
	_box(ci, el, x0, y0, x1, y1, ink, to_world, stroke_w, stroke_aa)
	_line(ci, el, Vector2(x0, y_title), Vector2(x1, y_title), ink, to_world, stroke_w, stroke_aa)
	var title: String = str(el.caption)
	if title == "":
		title = ("БП %.0fВ" % float(el.voltage)) if str(el.electro_class) == "psu" else (str(el.tag) if str(el.tag) != "" else "A")
	_device_cell_text(ci, el, font, to_world, Rect2(x0, y0, x1 - x0, y_title - y0), title, 11, ink)
	_draw_device_table_block(
		ci, el, ink, to_world, stroke_w, stroke_aa, font,
		left, n_l, edge_l, x_l0, x_l1, y_tbl_l, y_hdr_l, y_bot_l, cont_w, rh
	)
	_draw_device_table_block(
		ci, el, ink, to_world, stroke_w, stroke_aa, font,
		right, n_r, edge_r, x_r0, x_r1, y_tbl_r, y_hdr_r, y_bot_r, cont_w, rh
	)


static func _draw_socket(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	_box(ci, el, -4, -16, 18, 16, ink, to_world, stroke_w, stroke_aa)
	ci.draw_arc(to_world.call(el, Vector2(7, 0)), 6.0, 0.0, TAU, 20, ink, stroke_w.call(1.3), stroke_aa.call())
	for y in [-10.0, 0.0, 10.0]:
		_line(ci, el, Vector2(-LEAD_X, y), Vector2(-4, y), ink, to_world, stroke_w, stroke_aa)


static func _draw_stop(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	_box(ci, el, -6, -16, 6, 16, ink, to_world, stroke_w, stroke_aa)


static func _draw_thermal(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	# 3 пластины в рамке (реф KK), полюса на сетке 20.
	_box(ci, el, -26, -12, 26, 12, ink, to_world, stroke_w, stroke_aa)
	for i in 3:
		var x: float = -20.0 + float(i) * 20.0
		_line(ci, el, Vector2(x, -30), Vector2(x, 30), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x, -4), Vector2(x + 6, -4), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x + 6, -4), Vector2(x + 6, 4), ink, to_world, stroke_w, stroke_aa)
		_line(ci, el, Vector2(x + 6, 4), Vector2(x, 4), ink, to_world, stroke_w, stroke_aa)


static func _draw_box_generic(ci, el, ink, to_world, stroke_w, stroke_aa) -> void:
	var b := local_bounds(el)
	_box(ci, el, b.position.x + 4, b.position.y + 4, b.position.x + b.size.x - 4, b.position.y + b.size.y - 4, ink, to_world, stroke_w, stroke_aa)


static func _draw_dash_rect(ci: CanvasItem, r: Rect2, col: Color, dash: float, gap: float) -> void:
	var pts := [
		r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y),
	]
	for i in 4:
		_draw_dash_line(ci, pts[i], pts[(i + 1) % 4], col, dash, gap)


static func _draw_dash_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, dash: float, gap: float, width: float = 1.2, antialiased: bool = true) -> void:
	var d: Vector2 = b - a
	var len: float = d.length()
	if len < 0.5:
		return
	var dir: Vector2 = d / len
	# Подгоняем период под длину: целое число штрихов, линия заканчивается штрихом (без обрубка).
	var period: float = dash + gap
	var n_dash: int = maxi(1, int(round((len + gap) / period)))
	var fit_dash: float = dash
	var fit_gap: float = gap
	if n_dash <= 1:
		fit_dash = len
		fit_gap = 0.0
	else:
		var scale: float = len / (float(n_dash) * dash + float(n_dash - 1) * gap)
		fit_dash = dash * scale
		fit_gap = gap * scale
	var t: float = 0.0
	for i in n_dash:
		var t2: float = minf(t + fit_dash, len)
		if t2 - t > 0.25:
			ci.draw_line(a + dir * t, a + dir * t2, col, width, antialiased)
		t = t2 + fit_gap
