class_name ElectricalNetwork
extends RefCounted
## Учебный решатель электрических цепей: связность L↔N через контакты/катушки.
## Не полноценный SPICE — ориентир на логику автоматики и лампы/реле/кнопки.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const SensorSig = preload("res://scripts/domain/sensor_signal.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")


static func step(circuit, dt: float) -> void:
	if circuit == null:
		return
	var nodes: Dictionary = {} # key -> {v: float, fixed: bool}
	var edges: Array = [] # {a, b, closed}

	# Шины и источники.
	for el in circuit.elements:
		if str(el.kind) == "sensor":
			for port in Geom.ports(el):
				var pnm: String = str(port["name"])
				# Оптопорты OPT* — не электрическая сеть.
				if Geom.port_domain(el, pnm) != "electric":
					continue
				_fix_node(nodes, _pkey(el.id, pnm), 0.0, false)
			continue
		if str(el.kind) != "electro":
			continue
		match str(el.electro_class):
			"supply", "supply_leg":
				var svolt: float = float(el.voltage)
				if str(el.electro_class) == "supply_leg" and svolt <= 0.0:
					var spr = circuit.get_element(int(el.group_id))
					if spr != null:
						svolt = float(spr.voltage)
				for port in Geom.ports(el):
					var snm := str(port["name"])
					var sv: float = 0.0
					var sfix: bool = true
					match snm:
						"L", "L1":
							sv = svolt if svolt > 0.0 else 230.0
						"L2":
							sv = svolt if svolt > 0.0 else 400.0
						"L3":
							sv = svolt if svolt > 0.0 else 400.0
						"N", "PE":
							sv = 0.0
						_:
							sfix = false
					_fix_node(nodes, _pkey(el.id, snm), sv, sfix)
			"psu":
				# Входы L/N/PE и выходы +24/0 — сначала свободные.
				# +24/0 фиксируем только после питания L↔N (_apply_psu_outputs).
				for port in Geom.ports(el):
					_fix_node(nodes, _pkey(el.id, str(port["name"])), 0.0, false)
			"terminal", "busbar":
				var ph := str(el.phase)
				var bus_v: float = 0.0
				var bus_fixed: bool = true
				match ph:
					"L", "L1", "brown":
						bus_v = 230.0
					"L2":
						bus_v = 230.0
					"L3", "gray", "grey":
						bus_v = 230.0
					"+", "plus", "red":
						bus_v = 24.0
					"N", "PE", "green", "-", "minus", "black":
						bus_v = 0.0
					_:
						bus_fixed = false
				for port in Geom.ports(el):
					var nm := str(port["name"])
					_fix_node(nodes, _pkey(el.id, nm), bus_v, bus_fixed)
			_:
				for port in Geom.ports(el):
					_fix_node(nodes, _pkey(el.id, str(port["name"])), 0.0, false)

	# Внутренние связи аппаратов (без выходных ключей датчиков — сначала питание).
	for el in circuit.elements:
		if str(el.kind) == "electro":
			_device_edges(el, edges, dt)

	# Провода электрического домена.
	for wire in circuit.wires:
		var a = circuit.get_element(int(wire.a_id))
		var b = circuit.get_element(int(wire.b_id))
		if a == null or b == null:
			continue
		if Geom.port_domain(a, str(wire.a_port)) != "electric":
			continue
		if Geom.port_domain(b, str(wire.b_port)) != "electric":
			continue
		_fix_node(nodes, _pkey(a.id, wire.a_port), 0.0, false)
		_fix_node(nodes, _pkey(b.id, wire.b_port), 0.0, false)
		edges.append({"a": _pkey(a.id, wire.a_port), "b": _pkey(b.id, wire.b_port), "closed": true})

	_propagate(nodes, edges)
	# БП: +24/0 только если на L–N есть сеть (иначе выходы «воздух»).
	if _apply_psu_outputs(nodes, circuit):
		_propagate(nodes, edges)

	# Питание активных датчиков → выходные ключи → второй проход.
	var base_edge_n: int = edges.size()
	var has_sensors: bool = false
	for el in circuit.elements:
		if el == null or str(el.kind) != "sensor":
			continue
		has_sensors = true
		_update_sensor_power(el, nodes, circuit)
		_sensor_output_edges(el, edges)
	if has_sensors:
		_propagate(nodes, edges)
		# Пересчёт sensing с актуальным питанием (активный без питания — не срабатывает).
		SensorDetect.step(circuit)
		while edges.size() > base_edge_n:
			edges.pop_back()
		for el2 in circuit.elements:
			if el2 == null or str(el2.kind) != "sensor":
				continue
			_update_sensor_power(el2, nodes, circuit)
			_sensor_output_edges(el2, edges)
		_propagate(nodes, edges)

	# Обновить состояния элементов.
	for el in circuit.elements:
		if str(el.kind) != "electro":
			continue
		match str(el.electro_class):
			"lamp":
				var need: float = maxf(float(el.voltage) * 0.35, 8.0)
				el.lit = _load_fed(nodes, int(el.id), "X1", "X2", need)
			"relay", "timer_relay", "voltage_relay", "contactor", "solenoid_coil":
				var ports: PackedStringArray = el.coil_ports
				if ports.size() >= 2:
					var fed: bool = _load_fed(nodes, int(el.id), str(ports[0]), str(ports[1]), 50.0)
					_update_coil_state(el, fed, dt)
			_:
				pass

	# Команды ПР от возбуждённых катушек ЭМ + sync контактов группы.
	_sync_valve_commands(circuit)
	# Флаги КЗ до защиты — тепловизор видит ток, пока рычаг ещё в I.
	_publish_short_flags(circuit, nodes)
	# Учебная защита: нагрев / мгновенное отключение АВ и УЗО.
	_update_protection(circuit, nodes, dt)
	# Кэш потенциалов для подсказок на проводах (не V/R жилы).
	circuit.electro_nodes = nodes


## Если L–N БП питаются от сети — зажать выходы +24/0; иначе снять фиксацию.
static func _apply_psu_outputs(nodes: Dictionary, circuit) -> bool:
	var changed: bool = false
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro" or str(el.electro_class) != "psu":
			continue
		var fed: bool = _load_fed(nodes, int(el.id), "L", "N", 100.0)
		var v_out: float = float(el.voltage) if float(el.voltage) > 0.0 else 24.0
		var k24: String = _pkey(el.id, "+24")
		var k0: String = _pkey(el.id, "0")
		var was_fixed: bool = bool(nodes.get(k24, {}).get("fixed", false))
		if fed:
			if not was_fixed or absf(float(nodes.get(k24, {}).get("v", 0.0)) - v_out) > 0.1:
				changed = true
			nodes[k24] = {"v": v_out, "fixed": true, "driven": true}
			nodes[k0] = {"v": 0.0, "fixed": true, "driven": true}
		else:
			if was_fixed:
				changed = true
			nodes[k24] = {"v": 0.0, "fixed": false, "driven": false}
			nodes[k0] = {"v": 0.0, "fixed": false, "driven": false}
	return changed


static func _update_sensor_power(el, nodes: Dictionary, circuit = null) -> void:
	# B3: пассивный зонд, но показание требует Uпит вторички — не early-return.
	if str(el.sensor_class) == "rtd" and circuit != null:
		var eid_rtd: int = int(el.id)
		for m in circuit.electro_group_members(int(el.id)):
			if str(m.member_role) == "device" and str(m.electro_class) == "rtd_meter":
				eid_rtd = int(m.id)
				break
		if _load_fed(nodes, eid_rtd, "+24", "0", 10.0) or _load_fed(nodes, eid_rtd, "+", "0", 10.0) \
				or _load_fed(nodes, eid_rtd, "+", "-", 10.0):
			el.sensor_powered = true
		else:
			el.sensor_powered = false
		return
	if not bool(el.sensor_active):
		el.sensor_powered = true
		return
	var need: float = SensorSig.supply_need_v(str(el.supply_mode))
	var eid: int = int(el.id)
	# B2: Uпит на клеммной таблице PT·.1 (не на пневмо-УГО).
	if str(el.sensor_class) == "pressure_tx" and circuit != null:
		for m in circuit.electro_group_members(int(el.id)):
			if str(m.member_role) == "device":
				eid = int(m.id)
				break
		# Клеммы + / − (или legacy 0).
		if _load_fed(nodes, eid, "+", "-", need) or _load_fed(nodes, eid, "+", "0", need):
			el.sensor_powered = true
		else:
			el.sensor_powered = false
		return
	el.sensor_powered = _load_fed(nodes, eid, "+", "0", need)


static func _sensor_output_edges(el, edges: Array) -> void:
	# Реле давления B1: сухой контакт на KP1.1 (electro group), не OUT/0 на головке.
	if str(el.sensor_class) == "pressure_switch":
		var form_ps: bool = SensorSig.normalize_form(str(el.contact_form)) == SensorSig.FORM_NO
		var on_ps: bool = bool(el.pressed)
		el.lit = on_ps
		el.sensor_closed = on_ps if form_ps else not on_ps
		return
	# ПИП B2: только аналог на OUT; дискретного ключа нет. LED = питание.
	if str(el.sensor_class) == "pressure_tx":
		var powered_tx: bool = bool(el.sensor_powered) if bool(el.sensor_active) else true
		el.pressed = false
		el.lit = powered_tx
		el.sensor_closed = false
		return
	# ТС B3: пассивный R; дискрет нет; lit = вторичка под питанием.
	if str(el.sensor_class) == "rtd":
		el.pressed = false
		el.lit = bool(el.sensor_powered)
		el.sensor_closed = false
		return
	# Активный без питания — выход разомкнут (даже при цели в зоне).
	var powered: bool = bool(el.sensor_powered) if bool(el.sensor_active) else true
	# pressed уже от SensorDetect (с гистерезисом); без питания — сбросить.
	var sensing: bool = bool(el.pressed) if powered else false
	el.pressed = sensing
	el.lit = sensing
	var form_no: bool = SensorSig.normalize_form(str(el.contact_form)) == SensorSig.FORM_NO
	var closed: bool = sensing if form_no else (powered and not sensing)
	if not powered and bool(el.sensor_active):
		closed = false
	el.sensor_closed = closed
	var out_t: String = SensorSig.normalize_output(str(el.output_type))
	match out_t:
		SensorSig.OUT_NPN:
			# Ключ между OUT и 0 (sinking).
			edges.append({"a": _pkey(el.id, "OUT"), "b": _pkey(el.id, "0"), "closed": closed})
		SensorSig.OUT_PNP:
			# Ключ между OUT и + (sourcing).
			edges.append({"a": _pkey(el.id, "OUT"), "b": _pkey(el.id, "+"), "closed": closed})
		SensorSig.OUT_CONTACT:
			# Сухой контакт: OUT↔0 (2 провода; без Uпит головки).
			edges.append({"a": _pkey(el.id, "OUT"), "b": _pkey(el.id, "0"), "closed": closed})
		_:
			edges.append({"a": _pkey(el.id, "OUT"), "b": _pkey(el.id, "0"), "closed": closed})


static func _device_edges(el, edges: Array, dt: float) -> void:
	var cls := str(el.electro_class)
	match cls:
		"switch":
			_switch_edges(el, edges)
		"button", "e_stop", "contact", "thermal":
			_contact_edges(el, edges, _contacts_closed(el))
		"relay", "timer_relay", "voltage_relay", "contactor":
			# Катушка не замыкает A1-A2; контакты зависят от energized.
			_contact_edges(el, edges, el.energized)
		"mcb", "rcd", "rcbo":
			if el.closed:
				_series_ports(el, edges)
		"din_socket":
			pass
		"terminal", "busbar":
			var names: Array = []
			for p in Geom.ports(el):
				names.append(str(p["name"]))
			# Шина / phase-клемма / busbar: все порты в одном узле.
			# Обычный клеммник без шины: только feed-through ряда (1–2, 3–4…).
			var all_short: bool = str(cls) == "busbar" or str(el.phase) != "" or bool(el.terminal_bus)
			if all_short:
				for i in names.size():
					for j in range(i + 1, names.size()):
						edges.append({"a": _pkey(el.id, names[i]), "b": _pkey(el.id, names[j]), "closed": true})
			else:
				var rows: int = maxi(int(el.electro_ports.size()), 1)
				for ri in rows:
					var a_nm: String = str(ri * 2 + 1)
					var b_nm: String = str(ri * 2 + 2)
					if a_nm in names and b_nm in names:
						edges.append({"a": _pkey(el.id, a_nm), "b": _pkey(el.id, b_nm), "closed": true})
		_:
			pass
	# dt reserved for future thermal/timer internals
	var _dt := dt


static func _contacts_closed(el) -> bool:
	var cls := str(el.electro_class)
	if cls == "button" or cls == "e_stop":
		return bool(el.pressed)
	if cls == "contact":
		# Контакт группы: состояние от primary.
		return false # заполняется через group — см. ниже с circuit? упрощение: храним на contact.energized от primary
	if cls == "thermal":
		return not bool(el.pressed) # pressed = сработало
	return false


static func _switch_edges(el, edges: Array) -> void:
	var npos: int = maxi(int(el.switch_positions), 2)
	var pos: int = clampi(int(el.switch_pos), 0, npos - 1)
	var defs: Array = el.contact_defs
	var map: Array = el.switch_map if typeof(el.switch_map) == TYPE_ARRAY else []
	var rows: int = maxi(int(ceil(float(maxi(defs.size(), 2)) / 2.0)), 1)
	for ri in rows:
		var i0: int = ri * 2
		if i0 + 1 >= defs.size():
			break
		var a: Dictionary = defs[i0] if typeof(defs[i0]) == TYPE_DICTIONARY else {}
		var b: Dictionary = defs[i0 + 1] if typeof(defs[i0 + 1]) == TYPE_DICTIONARY else {}
		var closed: bool = false
		if ri < map.size() and typeof(map[ri]) == TYPE_ARRAY:
			var row: Array = map[ri]
			closed = bool(row[pos]) if pos < row.size() else false
		else:
			closed = (pos == (ri % npos))
		edges.append({
			"a": _pkey(el.id, str(a.get("name", ""))),
			"b": _pkey(el.id, str(b.get("name", ""))),
			"closed": closed,
		})


static func _contact_edges(el, edges: Array, device_on: bool) -> void:
	var defs: Array = el.contact_defs
	var on: bool = device_on
	if str(el.member_role) == "contact":
		on = bool(el.energized)
	var i := 0
	while i < defs.size():
		var a: Dictionary = defs[i] if typeof(defs[i]) == TYPE_DICTIONARY else {}
		var t := str(a.get("type", "no"))
		if t == "co" and i + 2 < defs.size():
			# Перекидной: common–НЗ (покой) / common–НО (нажат).
			var nc: Dictionary = defs[i + 1] if typeof(defs[i + 1]) == TYPE_DICTIONARY else {}
			var no: Dictionary = defs[i + 2] if typeof(defs[i + 2]) == TYPE_DICTIONARY else {}
			var common := _pkey(el.id, str(a.get("name", "")))
			edges.append({"a": common, "b": _pkey(el.id, str(nc.get("name", ""))), "closed": not on})
			edges.append({"a": common, "b": _pkey(el.id, str(no.get("name", ""))), "closed": on})
			i += 3
			continue
		if i + 1 >= defs.size():
			break
		var b: Dictionary = defs[i + 1] if typeof(defs[i + 1]) == TYPE_DICTIONARY else {}
		var tt := str(a.get("type", "no"))
		var closed := (on and tt == "no") or ((not on) and tt == "nc")
		edges.append({
			"a": _pkey(el.id, str(a.get("name", ""))),
			"b": _pkey(el.id, str(b.get("name", ""))),
			"closed": closed,
		})
		i += 2


static func _series_ports(el, edges: Array) -> void:
	var names: Array = []
	for p in Geom.ports(el):
		names.append(str(p["name"]))
	# 1-2, 3-4, …
	var i := 0
	while i + 1 < names.size():
		edges.append({"a": _pkey(el.id, names[i]), "b": _pkey(el.id, names[i + 1]), "closed": true})
		i += 2


static func _update_coil_state(el, fed: bool, dt: float) -> void:
	var cls := str(el.electro_class)
	if cls == "timer_relay":
		if fed:
			el.timer_elapsed = float(el.timer_elapsed) + dt
			if float(el.delay_on) <= 0.001 or el.timer_elapsed >= float(el.delay_on):
				el.energized = true
		else:
			if el.energized and float(el.delay_off) > 0.001:
				el.timer_elapsed = float(el.timer_elapsed) + dt
				if el.timer_elapsed >= float(el.delay_off):
					el.energized = false
					el.timer_elapsed = 0.0
			else:
				el.energized = false
				el.timer_elapsed = 0.0
		return
	el.energized = fed
	el.timer_elapsed = 0.0


static func _sync_valve_commands(circuit) -> void:
	var want: Dictionary = {} # "id:L" -> true
	var managed: Dictionary = {} # valve_id -> true
	for coil in circuit.elements:
		if str(coil.kind) != "electro" or str(coil.electro_class) != "solenoid_coil":
			continue
		var tag := str(coil.tag)
		var side := "L"
		if str(coil.linked_valve_side) in ["L", "R"]:
			side = str(coil.linked_valve_side)
		elif tag.ends_with("R") or tag.ends_with("r"):
			side = "R"
		var base := tag
		if base.ends_with("L") or base.ends_with("R") or base.ends_with("l") or base.ends_with("r"):
			base = base.substr(0, base.length() - 1)
		for el in circuit.elements:
			if str(el.kind) != "valve" or str(el.tag) != base:
				continue
			managed[el.id] = true
			if bool(coil.energized):
				want["%d:%s" % [el.id, side]] = true
	for el in circuit.elements:
		if str(el.kind) != "valve" or not managed.has(el.id):
			continue
		el.command_left = bool(want.get("%d:L" % el.id, false))
		el.command_right = bool(want.get("%d:R" % el.id, false))
	# Контакты группы: состояние от primary (реле/кнопка).
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.member_role) != "contact":
			continue
		var primary = circuit.get_element(int(el.group_id))
		if primary != null:
			el.energized = bool(primary.energized) or bool(primary.pressed)


static func _propagate(nodes: Dictionary, edges: Array) -> void:
	# Union-find по замкнутым рёбрам, затем max voltage в компоненте с fixed.
	var parent := {}
	for k in nodes.keys():
		parent[k] = k

	var find := func(x: String) -> String:
		var cur := x
		while str(parent[cur]) != cur:
			parent[cur] = parent[parent[cur]]
			cur = str(parent[cur])
		return cur

	for e in edges:
		if not bool(e.get("closed", false)):
			continue
		var a := str(e["a"])
		var b := str(e["b"])
		if not nodes.has(a) or not nodes.has(b):
			continue
		var ra: String = find.call(a)
		var rb: String = find.call(b)
		if ra != rb:
			parent[rb] = ra

	var root_v := {} # root -> voltage
	var root_fixed := {}
	for k in nodes.keys():
		var r: String = find.call(str(k))
		var info: Dictionary = nodes[k]
		var v: float = float(info.get("v", 0.0))
		if bool(info.get("fixed", false)):
			if not root_fixed.get(r, false) or v > float(root_v.get(r, -1.0e9)):
				root_v[r] = v
				root_fixed[r] = true
		elif not root_fixed.get(r, false):
			root_v[r] = maxf(float(root_v.get(r, 0.0)), v)

	for k in nodes.keys():
		var r2: String = find.call(str(k))
		nodes[k]["v"] = float(root_v.get(r2, 0.0))
		# driven: потенциал задан фиксированным источником в компоненте (не «воздух = 0»).
		nodes[k]["driven"] = bool(root_fixed.get(r2, false))


static func _fix_node(nodes: Dictionary, key: String, v: float, fixed: bool) -> void:
	if nodes.has(key) and bool(nodes[key].get("fixed", false)):
		return
	nodes[key] = {"v": v, "fixed": fixed, "driven": fixed}


static func _node_v(nodes: Dictionary, key: String) -> float:
	if not nodes.has(key):
		return 0.0
	return float(nodes[key].get("v", 0.0))


static func _node_driven(nodes: Dictionary, key: String) -> bool:
	if not nodes.has(key):
		return false
	return bool(nodes[key].get("driven", false))


static func _load_fed(nodes: Dictionary, el_id: int, port_a: String, port_b: String, need: float) -> bool:
	# Оба вывода должны быть привязаны к фиксированным источникам (фаза и возврат).
	var ka := _pkey(el_id, port_a)
	var kb := _pkey(el_id, port_b)
	if not _node_driven(nodes, ka) or not _node_driven(nodes, kb):
		return false
	return absf(_node_v(nodes, ka) - _node_v(nodes, kb)) > need


static func _pkey(el_id: int, port: String) -> String:
	return "%d:%s" % [el_id, port]


static func _em_mult(curve: String) -> Vector2:
	match curve.to_upper():
		"B":
			return Vector2(3.0, 5.0)
		"D":
			return Vector2(10.0, 20.0)
		_:
			return Vector2(5.0, 10.0)


## id → sim_time, когда впервые увидели аварию при замкнутом аппарате (задержка рычага I→O).
static var _prot_fault_since_sim: Dictionary = {}


static func clear_protection_state() -> void:
	_prot_fault_since_sim.clear()


static func _trip_breaker(circuit, el, reason: String) -> void:
	el.closed = false
	el.timer_elapsed = 0.0
	_prot_fault_since_sim.erase(int(el.id))
	if circuit != null and circuit.has_method("bump_scheme_control"):
		circuit.bump_scheme_control()
	if circuit != null and circuit.has_method("notify"):
		circuit.notify("%s: срабатывание — %s" % [str(el.tag), reason])


static func _prot_hold_ready(circuit, el_id: int, hold_s: float = 0.2) -> bool:
	# Пауза по sim_time — сбрасывается при загрузке сцены (не залипает между F5).
	var now: float = float(circuit.sim_time) if circuit != null else 0.0
	if not _prot_fault_since_sim.has(el_id):
		_prot_fault_since_sim[el_id] = now
		return false
	return (now - float(_prot_fault_since_sim[el_id])) >= hold_s


static func _publish_short_flags(circuit, nodes: Dictionary) -> void:
	if circuit == null:
		return
	var short_like: bool = _detect_short(circuit, nodes)
	circuit.electro_short = short_like
	var i_f: float = 0.0
	if short_like:
		i_f = 400.0
		for el in circuit.elements:
			if el == null or str(el.kind) != "electro":
				continue
			if str(el.electro_class) not in ["mcb", "rcd", "rcbo"]:
				continue
			if not bool(el.closed):
				continue
			i_f = maxf(i_f, maxf(float(el.rating_a), 1.0) * 50.0)
	circuit.electro_fault_a = i_f


static func _update_protection(circuit, nodes: Dictionary, dt: float) -> void:
	# Оценка тока: каждая горящая лампа ≈ 0.1 А на 220 В (учебно); КЗ — |ΔU|≈Uист при нулевой нагрузке в компоненте.
	var load_a: float = 0.0
	for el in circuit.elements:
		if str(el.kind) == "electro" and str(el.electro_class) == "lamp" and bool(el.lit):
			load_a += 0.1
	# Грубый признак КЗ: фаза на N/PE при отсутствии горящих ламп.
	var short_like: bool = _detect_short(circuit, nodes)
	for el in circuit.elements:
		if str(el.kind) != "electro":
			continue
		var cls := str(el.electro_class)
		if cls not in ["mcb", "rcd", "rcbo", "thermal"]:
			continue
		var eid: int = int(el.id)
		if not bool(el.closed) and cls != "thermal":
			# Остывание.
			el.timer_elapsed = maxf(float(el.timer_elapsed) - dt * 0.5, 0.0)
			_prot_fault_since_sim.erase(eid)
			continue
		var In: float = maxf(float(el.rating_a), 1.0)
		var I: float = load_a
		if short_like:
			I = In * 50.0
		var mult: float = I / In
		if cls == "thermal":
			# Тепловое: интеграл; срабатывание → pressed.
			var was_ok: bool = not bool(el.pressed)
			el.timer_elapsed = float(el.timer_elapsed) + maxf(mult * mult - 1.0, 0.0) * dt
			if was_ok and (el.timer_elapsed > 8.0 or mult > 8.0):
				el.pressed = true
				if circuit != null and circuit.has_method("bump_scheme_control"):
					circuit.bump_scheme_control()
				if circuit != null and circuit.has_method("notify"):
					circuit.notify("%s: срабатывание — перегруз (тепловое)" % str(el.tag))
			continue
		var band: Vector2 = _em_mult(str(el.curve))
		var trip_reason: String = ""
		if short_like:
			trip_reason = "короткое замыкание"
		elif cls in ["mcb", "rcbo"] and mult >= band.x:
			trip_reason = "ЭМ расцепитель (≈%.0f×In)" % mult
		elif cls in ["rcd", "rcbo"]:
			for pe_el in circuit.elements:
				if str(pe_el.kind) != "electro":
					continue
				if str(pe_el.electro_class) == "busbar" and str(pe_el.phase) in ["PE", "green"]:
					for p in Geom.ports(pe_el):
						if absf(_node_v(nodes, _pkey(pe_el.id, str(p["name"])))) > 30.0:
							trip_reason = "утечка на PE (дифф.)"
							break
				if trip_reason != "":
					break
		if trip_reason != "":
			# Тепловизор: первые секунды не выбиваем — иначе вспышка КЗ не видна.
			if circuit != null and bool(circuit.thermal_viz) and float(circuit.sim_time) < 4.0:
				continue
			var hold_s: float = 0.2
			if _prot_hold_ready(circuit, eid, hold_s):
				_trip_breaker(circuit, el, trip_reason)
			continue
		_prot_fault_since_sim.erase(eid)
		# Тепловая ветвь: накопление I²t.
		if mult > 1.13:
			el.timer_elapsed = float(el.timer_elapsed) + (mult * mult) * dt
			var limit: float = 120.0 if In > 32.0 else 60.0
			if el.timer_elapsed > limit / maxf(mult, 1.0):
				_trip_breaker(circuit, el, "тепловой расцепитель (перегруз)")
		else:
			el.timer_elapsed = maxf(float(el.timer_elapsed) - dt * 0.35, 0.0)


static func _detect_short(circuit, nodes: Dictionary) -> bool:
	# КЗ: фаза и N/PE оказались на одном потенциале после propagate.
	# У XS1 порты N/PE часто на supply_leg (другие id) — смотрим все supply/leg группы.
	var lit_n: int = 0
	for el in circuit.elements:
		if str(el.kind) == "electro" and str(el.electro_class) == "lamp" and bool(el.lit):
			lit_n += 1
	if lit_n > 0:
		return false
	var phase_vs: Array[float] = []
	var neut_vs: Array[float] = []
	var pe_vs: Array[float] = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) not in ["supply", "supply_leg"]:
			continue
		for p in Geom.ports(el):
			var nm: String = str(p["name"])
			var vv: float = _node_v(nodes, _pkey(int(el.id), nm))
			if nm in ["L", "L1", "L2", "L3"]:
				phase_vs.append(vv)
			elif nm == "N":
				neut_vs.append(vv)
			elif nm == "PE":
				pe_vs.append(vv)
	for vp in phase_vs:
		if absf(vp) < 100.0:
			continue
		for vn in neut_vs:
			# N «подтянут» к фазе — классическое КЗ L–N.
			if absf(vn - vp) < 1.0:
				return true
		for vpe in pe_vs:
			if absf(vpe) > 100.0:
				return true
			if absf(vpe - vp) < 1.0:
				return true
	return false
