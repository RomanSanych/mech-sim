class_name ValveCatalog
extends RefCounted
## Композиционный пневмораспределитель по ISO 1219-1:
## ways × positions × center × операторы L/R.
## Типоразмер портов — учебный ряд по мотивам Festo VUVG / Camozzi 338 (thread + OD + Qn).

const ValveLib = preload("res://scripts/domain/valve_library.gd")


## Каталог типоразмеров: id → резьба, OD трубки, Qn (Nl/мин при 6→5 бар).
static func size_classes() -> Array:
	return [
		_size("M5_4", "M5", 4.0, 180.0, "M5 · трубка Ø4 · Qn≈180"),
		_size("G1/8_6", "G1/8", 6.0, 650.0, "G1/8 · Ø6 · Qn≈650"),
		_size("G1/8_8", "G1/8", 8.0, 750.0, "G1/8 · Ø8 · Qn≈750"),
		_size("G1/4_8", "G1/4", 8.0, 1200.0, "G1/4 · Ø8 · Qn≈1200"),
		_size("G1/4_10", "G1/4", 10.0, 1400.0, "G1/4 · Ø10 · Qn≈1400"),
		_size("G3/8_10", "G3/8", 10.0, 2200.0, "G3/8 · Ø10 · Qn≈2200"),
		_size("G3/8_12", "G3/8", 12.0, 2600.0, "G3/8 · Ø12 · Qn≈2600"),
		_size("G1/2_12", "G1/2", 12.0, 3800.0, "G1/2 · Ø12 · Qn≈3800"),
		_size("G1/2_14", "G1/2", 14.0, 4200.0, "G1/2 · Ø14 · Qn≈4200"),
	]


static func size_by_id(size_id: String) -> Dictionary:
	var want: String = str(size_id)
	for item in size_classes():
		if str(item.get("id", "")) == want:
			return item as Dictionary
	return {}


## Типовой размер: 2/3 линии → G1/8·Ø6; 4/5 → G1/4·Ø8.
static func default_size_id(ways: int) -> String:
	if int(ways) <= 3:
		return "G1/8_6"
	return "G1/4_8"


static func apply_size(el, size_id: String) -> String:
	if el == null or str(el.kind) != "valve":
		return ""
	var row: Dictionary = size_by_id(size_id)
	var note: String = ""
	if row.is_empty():
		row = size_by_id(default_size_id(int(el.valve_ways)))
		note = "Типоразмер приведён к %s." % str(row.get("label", ""))
	el.fitting_id = str(row.get("id", ""))
	el.port_name = str(row.get("thread", "G1/8"))
	el.tube_od_mm = float(row.get("tube_od_mm", 6.0))
	var qn: float = float(row.get("qn", 650.0))
	# Как у обратного клапана: G1/8 · Qn600 ≈ Cv 1.0.
	el.valve_cv = clampf(qn / 600.0, 0.2, 4.0)
	if el.get("flow_nl_min") != null:
		el.flow_nl_min = qn
	return note


static func conform_size(el) -> String:
	if el == null or str(el.kind) != "valve":
		return ""
	var cur: String = str(el.fitting_id) if el.get("fitting_id") != null else ""
	if cur != "" and not size_by_id(cur).is_empty():
		# Синхронизировать thread/OD; Cv не трогать (мог быть подкручен вручную).
		var row: Dictionary = size_by_id(cur)
		el.fitting_id = str(row.get("id", ""))
		el.port_name = str(row.get("thread", "G1/8"))
		el.tube_od_mm = float(row.get("tube_od_mm", 6.0))
		return ""
	# Старые сцены: только port_name / ways — подобрать ближайший ряд.
	var thread: String = str(el.port_name) if el.get("port_name") != null else ""
	var od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0
	if thread != "" and od >= 1.0:
		for item in size_classes():
			if str(item.get("thread", "")) == thread and absf(float(item.get("tube_od_mm", 0.0)) - od) < 0.15:
				return apply_size(el, str(item.get("id", "")))
	return apply_size(el, default_size_id(int(el.valve_ways)))


static func _size(id: String, thread: String, tube_od: float, qn: float, label: String) -> Dictionary:
	return {
		"id": id,
		"thread": thread,
		"tube_od_mm": tube_od,
		"qn": qn,
		"label": label,
	}


static func part_options(part: String) -> Array:
	match part:
		"body", "ways":
			return [
				_opt("2", "2 линии (2/…)"),
				_opt("3", "3 линии (3/…)"),
				_opt("4", "4 линии (4/…)"),
				_opt("5", "5 линий (5/…)"),
			]
		"positions":
			return [
				_opt("2", "2 позиции"),
				_opt("3", "3 позиции"),
			]
		"center":
			return [
				_opt("closed", "Закрытый центр"),
				_opt("exhausted", "Выхлопной центр"),
				_opt("pressurized", "Напорный центр"),
				_opt("floating", "Плавающий центр"),
			]
		"op_left", "op_right", "op":
			return [
				_opt("spring", "Пружина"),
				_opt("button", "Кнопка"),
				_opt("plunger", "Толкатель"),
				_opt("roller", "Ролик"),
				_opt("pilot", "Пневмопилот"),
				_opt("solenoid", "Электромагнит"),
				_opt("solenoid_pilot", "Эл./пневмопилот"),
			]
		"pilot_supply":
			return [
				_opt("internal", "Внутреннее питание пилота"),
				_opt("external", "Внешнее питание пилота"),
			]
		"nc_no":
			return [
				_opt("nc", "Нормально закрытый"),
				_opt("no", "Нормально открытый"),
			]
		"override_left", "override_right", "override":
			return [
				_opt("yes", "С ручным дублёром"),
				_opt("no", "Без дублёра"),
			]
		"port_3", "port_5", "exhaust_fit":
			return [
				_opt("muffler", "Глушитель"),
				_opt("fitting", "Свободный (фитинг)"),
			]
	return []


static func part_title(part: String) -> String:
	if part.begins_with("cell_"):
		var idx := int(part.substr(5)) + 1
		return "Клетка %d" % idx
	match part:
		"body", "ways":
			return "Корпус / линии"
		"positions":
			return "Число позиций"
		"center":
			return "Среднее положение"
		"op_left":
			return "Управление слева"
		"op_right":
			return "Управление справа"
		"pilot_supply":
			return "Питание пилота"
		"nc_no":
			return "Нормальное состояние"
		"port_3":
			return "Выхлоп 3(R1)"
		"port_5":
			return "Выхлоп 5(R2)"
		"override_left":
			return "Дублёр слева"
		"override_right":
			return "Дублёр справа"
	return "Часть"


static func conform(el) -> String:
	var notes: PackedStringArray = []
	var ways := int(el.valve_ways)
	if ways != 2 and ways != 3 and ways != 4 and ways != 5:
		el.valve_ways = 5
		ways = 5
		notes.append("Число линий приведено к 5.")
	var positions := int(el.valve_positions)
	if positions != 2 and positions != 3:
		el.valve_positions = 2
		positions = 2
	if ways == 2 and positions == 3:
		el.valve_positions = 2
		positions = 2
		notes.append("2/3 в учебной модели не используют — взято 2/2.")
	if positions != 3:
		el.valve_center = "none"
	else:
		var c := str(el.valve_center)
		if c != "closed" and c != "exhausted" and c != "pressurized" and c != "floating":
			el.valve_center = "closed"
		if ways < 5 and str(el.valve_center) == "floating":
			el.valve_center = "closed"
			notes.append("Плавающий центр типичен для 5/3 — взят закрытый.")
	var nc := str(el.valve_nc_no)
	if nc != "nc" and nc != "no":
		el.valve_nc_no = "nc"
	if ways != 2 and ways != 3:
		el.valve_nc_no = "nc"
	el.op_left = _norm_op(str(el.op_left))
	el.op_right = _norm_op(str(el.op_right))
	if el.op_left == "none" and el.op_right == "none":
		el.op_left = "solenoid_pilot"
		el.op_right = "spring"
		notes.append("Добавлены соленоид слева и пружина справа (моностабил).")
	# Покой: пружина нарисована у квадрата покоя (ISO); бистабил 3 поз. — центр.
	if el.op_right == "spring" and el.op_left != "spring":
		el.rest_pos = positions - 1
	elif el.op_left == "spring" and el.op_right != "spring":
		el.rest_pos = 0
	elif positions == 3:
		el.rest_pos = 1
	else:
		el.rest_pos = clampi(int(el.rest_pos), 0, positions - 1)
	el.valve_pos = clampi(int(el.valve_pos), 0, positions - 1)
	var ps := str(el.pilot_supply)
	if ps != "internal" and ps != "external":
		el.pilot_supply = "internal"
	el.port_3 = _norm_exhaust_fit(str(el.get("port_3") if el.get("port_3") != null else "muffler"))
	el.port_5 = _norm_exhaust_fit(str(el.get("port_5") if el.get("port_5") != null else "muffler"))
	ValveLib.normalize_spool(el)
	var size_note: String = conform_size(el)
	if size_note != "":
		notes.append(size_note)
	el.valve_cv = clampf(float(el.valve_cv), 0.2, 4.0)
	el.order_code = _plain_name(el)
	return " ".join(notes)


static func exhaust_fit(el, name: String) -> String:
	if name == "3":
		return _norm_exhaust_fit(str(el.get("port_3") if el.get("port_3") != null else "muffler"))
	if name == "5":
		return _norm_exhaust_fit(str(el.get("port_5") if el.get("port_5") != null else "muffler"))
	return "fitting"


static func _norm_exhaust_fit(v: String) -> String:
	return "fitting" if v == "fitting" or v == "connect" or v == "open" else "muffler"


static func port_names(el) -> PackedStringArray:
	var ways := int(el.valve_ways)
	var names: PackedStringArray = []
	match ways:
		2:
			names = PackedStringArray(["1", "2"])
		3:
			names = PackedStringArray(["1", "2", "3"])
		4:
			names = PackedStringArray(["1", "2", "3", "4"])
		_:
			names = PackedStringArray(["1", "2", "3", "4", "5"])
	if _needs_pilot(el, true):
		names.append("12")
	if _needs_pilot(el, false):
		names.append("14")
	return names


static func is_exhaust_port(name: String) -> bool:
	return name == "3" or name == "5"


static func path_pairs(el, pos: int) -> Array:
	# Пары портов из выбранной клетки золотника (ValveLibrary envelopes).
	var positions := int(el.valve_positions)
	pos = clampi(pos, 0, maxi(positions - 1, 0))
	return ValveLib.path_pairs_from_spool(el, pos)


static func calc_lines(el, part: String = "") -> PackedStringArray:
	var lines: PackedStringArray = []
	var ways := int(el.valve_ways)
	var positions := int(el.valve_positions)
	match part:
		"op_left":
			lines.append("Слева: %s" % _op_name(str(el.op_left)))
			if str(el.op_left) in ["button", "plunger", "roller", "solenoid", "solenoid_pilot"]:
				lines.append("В 3D: зажми орган мышью")
		"op_right":
			lines.append("Справа: %s" % _op_name(str(el.op_right)))
			if str(el.op_right) in ["button", "plunger", "roller", "solenoid", "solenoid_pilot"]:
				lines.append("В 3D: зажми орган мышью")
		"center":
			lines.append("Центр: %s" % _center_name(str(el.valve_center)))
		_:
			lines.append("Схема %d/%d · %s" % [ways, positions, el.order_code])
			if positions == 3:
				lines.append("Среднее: %s" % _center_name(str(el.valve_center)))
			elif ways <= 3:
				lines.append("Нормально: %s" % ("закрытый" if str(el.valve_nc_no) == "nc" else "открытый"))
			lines.append("Упр. L: %s · R: %s" % [_op_name(str(el.op_left)), _op_name(str(el.op_right))])
			lines.append("Позиция сейчас: %d / %d (покой %d)" % [int(el.valve_pos) + 1, positions, int(el.rest_pos) + 1])
			lines.append("Проход Cv учебный ×%.1f · порт %s" % [float(el.valve_cv), el.port_name])
			var pairs: Array = path_pairs(el, int(el.valve_pos))
			if pairs.is_empty():
				lines.append("Сейчас все пути закрыты")
			else:
				var bits: PackedStringArray = []
				for pair in pairs:
					bits.append("%s–%s" % [pair[0], pair[1]])
				lines.append("Открыто: " + ", ".join(bits))
	return lines


static func target_pos(el, p12: float = 101325.0, p14: float = 101325.0) -> int:
	var positions := int(el.valve_positions)
	var left := _side_active(el, true, p12)
	var right := _side_active(el, false, p14)
	if positions == 3:
		if left and not right:
			return 0
		if right and not left:
			return 2
		if left and right:
			return 1
		# Нет команды: пружина → покой; бистабил/фиксация → держим позицию.
		return int(el.rest_pos) if _has_spring_return(el) else int(el.valve_pos)
	# 2 позиции: оператор слева включает левый квадрат (0), справа — правый (1).
	if left and not right:
		return 0
	if right and not left:
		return 1
	if left and right:
		return int(el.valve_pos)
	return int(el.rest_pos) if _has_spring_return(el) else int(el.valve_pos)


static func _has_spring_return(el) -> bool:
	return str(el.op_left) == "spring" or str(el.op_right) == "spring"


static func _side_active(el, left: bool, pilot_p: float) -> bool:
	var op := str(el.op_left) if left else str(el.op_right)
	var cmd: bool = el.command_left if left else el.command_right
	match op:
		"none", "spring":
			return false
		"pilot":
			return pilot_p > 101325.0 + 1.5e5
		"solenoid", "solenoid_pilot", "button", "plunger", "roller":
			# Срабатывание от удержания органа в 3D (command_* — внутренний флаг).
			return cmd
		_:
			return cmd


static func _needs_pilot(el, left: bool) -> bool:
	var op := str(el.op_left) if left else str(el.op_right)
	return op == "pilot" or op == "solenoid_pilot"


static func _norm_op(value: String) -> String:
	match value:
		"spring", "button", "plunger", "roller", "pilot", "solenoid", "solenoid_pilot", "none":
			return value
		"lever", "pedal":
			return "button"
		"detent":
			return "spring"
		_:
			return "none"


static func _op_name(value: String) -> String:
	match value:
		"spring":
			return "пружина"
		"button":
			return "кнопка"
		"pedal":
			return "педаль"
		"plunger":
			return "толкатель"
		"roller":
			return "ролик"
		"pilot":
			return "пневмопилот"
		"solenoid":
			return "электромагнит"
		"solenoid_pilot":
			return "эл./пневмопилот"
		_:
			return "нет"


static func _center_name(value: String) -> String:
	match value:
		"exhausted":
			return "выхлопной"
		"pressurized":
			return "напорный"
		"floating":
			return "плавающий"
		"closed":
			return "закрытый"
		_:
			return "нет"


static func _port_thread(ways: int) -> String:
	if ways <= 3:
		return "G1/8"
	if ways == 4:
		return "G1/4"
	return "G1/4"


static func _plain_name(el) -> String:
	var ways := int(el.valve_ways)
	var pos := int(el.valve_positions)
	var base := "%d/%d" % [ways, pos]
	if pos == 3:
		return "%s %s" % [base, _center_name(str(el.valve_center))]
	if ways <= 3:
		return "%s %s" % [base, "НЗ" if str(el.valve_nc_no) == "nc" else "НО"]
	return base


static func _opt(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label}
