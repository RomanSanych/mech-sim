class_name CylinderCatalog
extends RefCounted
## Дженерик-цилиндр: части УГО как в компоновщике схемы, а числа — из реальных рядов
## ISO 6432, ISO 21287 и ISO 15552 (Festo DSBC/DSNU/ADN, Camozzi 63/32).
## Производитель не выбирается. Если сочетания нет ни в одном из этих рядов, об этом пишется прямо.

static func bores() -> Array:
	return [8, 10, 12, 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200]


static func bore_row(bore_mm: float) -> Dictionary:
	var table := {
		8: _row(8, [4], "M5", "M4", 200, 0, false),
		10: _row(10, [4], "M5", "M4", 200, 0, false),
		12: _row(12, [6], "M5", "M5", 300, 0, false),
		16: _row(16, [6, 8], "M5", "M6", 300, 0, false),
		20: _row(20, [8, 10], "G1/8", "M8", 500, 0, false),
		25: _row(25, [10], "G1/8", "M10×1.25", 500, 0, false),
		32: _row(32, [12], "G1/8", "M10×1.25", 2800, 17, true),
		40: _row(40, [16, 12], "G1/4", "M12×1.25", 2800, 19, true),
		50: _row(50, [20, 16], "G1/4", "M16×1.5", 2800, 22, true),
		63: _row(63, [20, 16], "G3/8", "M16×1.5", 2800, 22, true),
		80: _row(80, [25, 20], "G3/8", "M20×1.5", 2800, 31, true),
		100: _row(100, [25, 20], "G1/2", "M20×1.5", 2800, 31, true),
		125: _row(125, [32, 25], "G1/2", "M27×2", 2800, 45, true),
		160: _row(160, [40], "G3/4", "M36×2", 2500, 45, true),
		200: _row(200, [40], "G3/4", "M36×2", 2500, 45, true),
	}
	var best_d := 32
	var best := 1.0e9
	for key in table.keys():
		var dist := absf(float(key) - bore_mm)
		if dist < best:
			best = dist
			best_d = int(key)
	return table[best_d]


static func rod_label(bore_mm: float, rod_mm: float) -> String:
	var row := bore_row(bore_mm)
	var rods: Array = row["rods"]
	if rods.size() == 1:
		return "%.0f мм" % float(rods[0])
	if absf(float(rods[0]) - rod_mm) < 0.1:
		return "%.0f мм, профиль ISO 15552" % rod_mm
	return "%.0f мм, компакт ISO 21287" % rod_mm


static func part_options(part: String) -> Array:
	match part:
		"piston":
			return [
				_opt("simple", "Простой"),
				_opt("magnetic", "Магнитный"),
			]
		"cush_cap", "cush_rod":
			return [
				_opt("none", "Нет"),
				_opt("fixed", "Фиксированная (P)"),
				_opt("adjustable", "Регулируемая (PPV)"),
				_opt("self", "Самонастраивающаяся (PPS)"),
			]
		"spring":
			return [
				_opt("none", "Нет"),
				_opt("rod", "В штоковой полости"),
				_opt("cap", "В бесштоковой полости"),
			]
		"rod":
			return [
				_opt("single", "Одноштоковый"),
				_opt("through", "Проходной шток"),
				_opt("carriage", "Каретка (щелевая)"),
				_opt("magnetic", "Магнитная каретка"),
			]
		"brake":
			return [
				_opt("none", "Нет"),
				_opt("nc", "Зажим штока (NC)"),
				_opt("end_lock", "Стопор в конце хода"),
			]
		"mount":
			return [
				_opt("none", "Без крепления"),
				_opt("foot", "Лапы"),
				_opt("flange_front", "Фланец спереди"),
				_opt("flange_rear", "Фланец сзади"),
				_opt("clevis", "Серьга сзади"),
				_opt("trunnion", "Цапфы"),
			]
		"guide":
			return [
				_opt("none", "Обычная"),
				_opt("bushing", "Усиленная втулка"),
				_opt("non_rot", "Антиповорот"),
			]
		"bump_end":
			return [
				_opt("none", "Нет"),
				_opt("elastic", "Эластичные упоры"),
				_opt("ysr", "Амортизаторы YSR"),
			]
		"body":
			return [
				_opt("round", "Круглый"),
				_opt("profile", "Профиль ISO 15552"),
				_opt("compact", "Компакт ISO 21287"),
			]
	return []


static func part_title(part: String) -> String:
	match part:
		"piston":
			return "Поршень"
		"cush_cap":
			return "Амортизация слева"
		"cush_rod":
			return "Амортизация справа"
		"spring":
			return "Пружина"
		"rod":
			return "Шток"
		"brake":
			return "Тормоз / стопор"
		"mount":
			return "Крепление"
		"guide":
			return "Направляющая"
		"bump_end":
			return "Упоры каретки"
		"body":
			return "Корпус"
	return "Часть"


static func conform(el) -> String:
	var notes: PackedStringArray = []
	var row := bore_row(float(el.bore_mm))
	if absf(float(row["d"]) - float(el.bore_mm)) > 0.1:
		notes.append("Диаметр поршня приведён к стандартному ряду: %.0f мм." % row["d"])
	el.bore_mm = float(row["d"])
	var rods: Array = row["rods"]
	var rod_in := float(el.rod_mm)
	var rod := _nearest(rod_in, rods)
	if str(el.rod_mode) == "rodless":
		rod = 0.0
	elif absf(rod - rod_in) > 0.1:
		notes.append("Шток %.0f мм для ∅%.0f в рядах ISO не встречается. Взято %.0f мм." % [rod_in, el.bore_mm, rod])
	el.rod_mm = rod
	# port_name / tube_od задаёт TubeFittingCatalog после conform (фитинг под bore).
	el.port_name = str(row["port"])
	el.rod_thread = str(row["thread"])
	el.through_rod = str(el.rod_mode) == "through"
	var pk := str(el.piston_kind)
	if pk != "simple" and pk != "magnetic":
		el.piston_kind = "simple"
	el.rod_end = "plain"
	var brake := str(el.brake)
	if brake != "none" and brake != "nc" and brake != "end_lock":
		el.brake = "none"
		brake = "none"
	if brake != "none" and str(el.rod_mode) == "rodless":
		notes.append("Тормоз/стопор на бесштоковом в учебной модели не ставят — сброшен.")
		el.brake = "none"
	if brake == "nc" and not bool(row["lock"]) and el.bore_mm < 32.0:
		notes.append("Зажим штока обычно от ∅32; оставлено как учебный вариант.")
	var mount := str(el.mount)
	if mount == "":
		el.mount = "clevis" if str(el.rod_mode) != "rodless" else "foot"
		mount = str(el.mount)
	if mount != "none" and mount != "foot" and mount != "flange_front" and mount != "flange_rear" and mount != "clevis" and mount != "trunnion":
		el.mount = "clevis" if str(el.rod_mode) != "rodless" else "foot"
		mount = str(el.mount)
	if str(el.rod_mode) == "rodless" and mount == "clevis":
		el.mount = "foot"
		mount = "foot"
	var guide := str(el.guide)
	if guide != "none" and guide != "bushing" and guide != "non_rot":
		el.guide = "none"
		guide = "none"
	if guide == "non_rot" and str(el.rod_mode) == "rodless":
		notes.append("Антиповорот для бесштокового не задают — сброшен.")
		el.guide = "none"
	el.seal_leak = clampf(float(el.seal_leak), 0.0, 1.0)
	el.cush_open_cap = clampf(float(el.cush_open_cap), 0.0, 1.0)
	el.cush_open_rod = clampf(float(el.cush_open_rod), 0.0, 1.0)
	var bump := str(el.bump_end)
	if bump != "none" and bump != "elastic" and bump != "ysr":
		el.bump_end = "none"
		bump = "none"
	if str(el.rod_mode) != "rodless":
		el.bump_end = "none"
	var spring := str(el.spring_side)
	if spring == "both":
		notes.append("Пружина с обеих сторон в каталогах пневмоцилиндров не встречается.")
		el.spring_side = "none"
		spring = "none"
	# Пружина в полости → выхлоп на этой полости, линия подключения на другой.
	if spring == "rod":
		el.port_rod = "exhaust"
		el.port_cap = "connect"
	elif spring == "cap":
		el.port_cap = "exhaust"
		el.port_rod = "connect"
	else:
		el.port_cap = "connect"
		el.port_rod = "connect"
	el.action = "double"
	if str(el.port_rod) == "exhaust" and str(el.port_cap) != "exhaust":
		el.action = "spring_return"
	elif str(el.port_cap) == "exhaust" and str(el.port_rod) != "exhaust":
		el.action = "spring_extend"
	if str(el.rod_mode) == "rodless" and spring != "none":
		notes.append("Бесштоковый с пружиной — учебная схема (в ISO-рядах так обычно не заказывают).")
	if str(el.rod_mode) == "rodless" and (el.bore_mm < 16.0 or el.bore_mm > 80.0):
		notes.append("Бесштоковые обычно имеют диаметр 16…80 мм.")
	if el.through_rod and el.bore_mm < 12.0:
		notes.append("Проходной шток у диаметров меньше 12 мм в стандартах не встречается.")
	var left := str(el.cush_cap)
	var right := str(el.cush_rod)
	if left != "none" and left != "fixed" and left != "adjustable" and left != "self":
		el.cush_cap = "none"
		left = "none"
	if right != "none" and right != "fixed" and right != "adjustable" and right != "self":
		el.cush_rod = "none"
		right = "none"
	var wants_long := left == "adjustable" or right == "adjustable" or left == "self" or right == "self"
	if wants_long and float(row["ppv"]) <= 0.0:
		notes.append("Длинный пневмодемпфер у ∅%.0f в стандартах не делают, остаётся фиксированное кольцо." % el.bore_mm)
		if left == "adjustable" or left == "self":
			el.cush_cap = "fixed"
			left = "fixed"
		if right == "adjustable" or right == "self":
			el.cush_rod = "fixed"
			right = "fixed"
	el.cushion = left != "none" or right != "none"
	if wants_long and float(row["ppv"]) > 0.0:
		el.cushion_mm = float(row["ppv"])
	elif el.cushion:
		el.cushion_mm = 2.0
	else:
		el.cushion_mm = 0.0
	var stroke_in := float(el.stroke_mm)
	var stroke := clampf(stroke_in, 5.0, float(row["smax"]))
	if absf(stroke - stroke_in) > 0.1:
		notes.append("Ход для ∅%.0f ограничен 5…%.0f мм." % [el.bore_mm, row["smax"]])
	el.stroke_mm = stroke
	if el.action != "double" and el.stroke_mm > 80.0:
		notes.append("У односторонних цилиндров стандартный ход обычно до 50–80 мм. Более длинный делают по заказу.")
	_dynamics(el, row)
	if str(el.spring_side) == "none":
		el.spring_rate = 0.0
		el.spring_preload = 0.0
	# Стиль корпуса: авто из ряда, если юзер не фиксировал.
	if not bool(el.body_style_user):
		if el.bore_mm < 32.0:
			el.body_style = "round"
		elif rods.size() > 1 and absf(el.rod_mm - float(rods[0])) > 0.1 and not el.through_rod:
			el.body_style = "compact"
		else:
			el.body_style = "profile"
		if str(el.rod_mode) == "rodless":
			el.body_style = "compact"
	else:
		var bs := str(el.body_style)
		if bs != "round" and bs != "profile" and bs != "compact":
			el.body_style = "profile"
		if el.bore_mm < 32.0 and bs == "profile":
			notes.append("Профиль ISO 15552 обычно от ∅32; для малого диаметра типичен круглый корпус.")
		if bs == "compact" and el.bore_mm < 12.0:
			notes.append("Компакт ISO 21287 обычно от ∅12.")
	el.order_code = _plain_name(el)
	return " ".join(notes)


static func card(el) -> String:
	var row := bore_row(float(el.bore_mm))
	var rods: Array = row["rods"]
	var rod_text := "бесштоковый, площади полостей равны"
	if str(el.rod_mode) == "through":
		rod_text = "проходной шток %.0f мм, %s, площади кольцевые и равны" % [el.rod_mm, el.rod_thread]
	elif str(el.rod_mode) != "rodless":
		rod_text = "шток %s, резьба %s" % [rod_label(el.bore_mm, el.rod_mm), el.rod_thread]
	var families := "ISO 6432"
	if el.bore_mm >= 32.0:
		families = "ISO 15552"
		if rods.size() > 1:
			families = "ISO 15552 и ISO 21287"
	elif el.bore_mm >= 12.0:
		families = "ISO 6432 и ISO 21287"
	return "Обобщённый цилиндр по рядам %s.\nПорт %s. %s.\nДемпфер слева: %s, справа: %s.\nПружина: %s.\nПодвижная масса %.3f кг. Рабочий ход до %.0f мм." % [
		families,
		el.port_name,
		rod_text,
		_cush_name(str(el.cush_cap)),
		_cush_name(str(el.cush_rod)),
		_spring_name(str(el.spring_side)),
		el.mass_kg,
		row["smax"],
	]


static func port_orifice_mm(port_name: String) -> float:
	match port_name:
		"M5":
			return 2.5
		"G1/4":
			return 6.0
		"G3/8":
			return 8.0
		"G1/2":
			return 10.0
		"G3/4":
			return 12.0
		_:
			return 4.0


static func _row(d: int, rods: Array, port: String, thread: String, smax: float, ppv: float, lock: bool) -> Dictionary:
	return {"d": d, "rods": rods, "port": port, "thread": thread, "smax": smax, "ppv": ppv, "lock": lock}


static func _opt(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label}


static func _nearest(value: float, options: Array) -> float:
	var best := float(options[0])
	var best_d := absf(value - best)
	for item in options:
		var candidate := float(item)
		var dist := absf(value - candidate)
		if dist < best_d:
			best_d = dist
			best = candidate
	return best


static func _dynamics(el, row: Dictionary) -> void:
	var bore := float(el.bore_mm)
	var area := PI * pow(bore * 0.001, 2.0) * 0.25
	var f6 := 6.0e5 * area
	var k := bore / 32.0
	if bore >= 32.0 and str(el.rod_mode) != "rodless":
		var moving0 := 0.11 * k * k
		el.mass_kg = maxf(moving0 + 0.009 * k * k * float(el.stroke_mm) / 10.0, 0.02)
	else:
		el.mass_kg = maxf(0.04 * k * k * (0.45 + float(el.stroke_mm) / 180.0), 0.02)
	el.friction_n = maxf(f6 * 0.02, 2.0)
	if str(el.brake) == "nc" and bool(row["lock"]):
		el.friction_n = maxf(el.friction_n, f6 * 1.15)
	if el.action == "double" and str(el.spring_side) != "rod" and str(el.spring_side) != "cap":
		return
	var hold := f6 * 0.12
	el.spring_preload = hold * 0.4
	el.spring_rate = maxf((hold - el.spring_preload) / maxf(float(el.stroke_mm), 1.0), 0.02)


static func calc_lines(el, part: String = "") -> PackedStringArray:
	# Ненастраиваемые, но важные расчётные величины для меню.
	var lines: PackedStringArray = []
	if el == null or el.kind != "cylinder":
		return lines
	var row := bore_row(float(el.bore_mm))
	var bore_m := float(el.bore_mm) * 0.001
	var rod_m := float(el.rod_mm) * 0.001
	var a_cap := PI * bore_m * bore_m * 0.25
	var a_rod := a_cap
	if str(el.rod_mode) != "rodless" and not bool(el.through_rod):
		a_rod = maxf(a_cap - PI * rod_m * rod_m * 0.25, a_cap * 0.35)
	elif bool(el.through_rod):
		a_rod = maxf(a_cap - PI * rod_m * rod_m * 0.25, a_cap * 0.35)
		a_cap = a_rod
	var f6_cap := 6.0e5 * a_cap
	var f6_rod := 6.0e5 * a_rod
	match part:
		"cush_cap", "cush_rod":
			var kind := str(el.cush_cap) if part == "cush_cap" else str(el.cush_rod)
			var open_v := float(el.cush_open_cap) if part == "cush_cap" else float(el.cush_open_rod)
			var side := "бесштоковый упор (влево)" if part == "cush_cap" else "штоковый упор (вправо)"
			match kind:
				"fixed":
					lines.append("%s: эластичное кольцо ~2,5 мм" % side)
					lines.append("Слабое притормаживание + потеря скорости при ударе")
				"adjustable":
					var mm := maxf(float(el.cushion_mm), 8.0)
					lines.append("%s: PPV ~%.0f мм хода" % [side, mm])
					lines.append("Игла открыта на %.0f%% (0=жёстко, 100=мягко)" % (open_v * 100.0))
				"self":
					var mm2 := maxf(float(el.cushion_mm) * 0.85, 10.0)
					lines.append("%s: PPS ~%.0f мм, авто по скорости" % [side, mm2])
				_:
					lines.append("%s: без демпфера — жёсткий удар в конце" % side)
		"brake":
			match str(el.brake):
				"nc":
					lines.append("Зажим штока NC: держит без пилота, сдвиг только большой силой")
				"end_lock":
					lines.append("Стопор в конце хода: фиксация у упора до превышения порога")
				_:
					lines.append("Тормоза нет")
		"mount":
			lines.append("Крепление: %s" % _mount_name(str(el.mount)))
		"guide":
			match str(el.guide):
				"bushing":
					lines.append("Усиленная втулка: чуть выше вязкое сопротивление")
				"non_rot":
					lines.append("Антиповорот: выше трение трогания")
				_:
					lines.append("Обычная направляющая")
		"bump_end":
			match str(el.bump_end):
				"elastic":
					lines.append("Эластичные упоры каретки ~4 мм")
				"ysr":
					lines.append("Амортизаторы YSR ~12 мм, сильное торможение")
				_:
					lines.append("Отдельных упоров каретки нет")
		"rod":
			if str(el.rod_mode) == "rodless":
				if str(el.carriage) == "magnetic":
					lines.append("Магнитная каретка: связь через зазор, без ярма в пазу")
				else:
					lines.append("Щелевая каретка: жёсткое ярмо через ленту паза")
				lines.append("Бесштоковый: площади полостей равны %.0f мм²" % (a_cap * 1.0e6))
			else:
				lines.append("Площадь штоковой полости %.0f мм²" % (a_rod * 1.0e6))
				lines.append("Сила втягивания при 6 бар ≈ %.0f Н" % f6_rod)
			lines.append("Рабочий ход %.0f мм (макс. ряда %.0f мм)" % [el.stroke_mm, row["smax"]])
			lines.append("Порт %s · резьба штока %s" % [el.port_name, el.rod_thread])
		"spring":
			var side := str(el.spring_side)
			if side == "none":
				lines.append("Пружины нет — ход только давлением")
			else:
				lines.append("Жёсткость %.2f Н/мм · преднатяг %.0f Н" % [el.spring_rate, el.spring_preload])
				if side == "rod":
					lines.append("Сжимается при выдвижении → тянет шток назад")
				elif side == "cap":
					lines.append("Сжимается при втягивании → толкает шток вперёд")
			lines.append("Полость с пружиной — через выхлоп (глушитель)")
		"piston":
			lines.append("Площадь поршня %.0f мм²" % (a_cap * 1.0e6))
			lines.append("Сила при 6 бар ≈ %.0f Н" % f6_cap)
			lines.append("Подвижная масса %.3f кг · трение ≈ %.0f Н" % [el.mass_kg, el.friction_n])
		_:
			lines.append("Поршень %.0f мм² · кольцо %.0f мм²" % [a_cap * 1.0e6, a_rod * 1.0e6])
			lines.append("При 6 бар: выдвижение ≈ %.0f Н, втягивание ≈ %.0f Н" % [f6_cap, f6_rod])
			lines.append("Масса %.3f кг · трение ≈ %.0f Н · порт %s" % [el.mass_kg, el.friction_n, el.port_name])
			lines.append("Корпус: %s · крепление: %s" % [el.body_style, _mount_name(str(el.mount))])
			var lc := _cush_name(str(el.cush_cap))
			var lr := _cush_name(str(el.cush_rod))
			lines.append("Демпфер L: %s · R: %s" % [lc, lr])
			if str(el.brake) != "none":
				lines.append("Тормоз: %s" % _brake_name(str(el.brake)))
			if str(el.guide) != "none":
				match str(el.guide):
					"bushing":
						lines.append("Направляющая: усиленная втулка")
					"non_rot":
						lines.append("Направляющая: антиповорот")
			var leak_v := float(el.seal_leak)
			if leak_v > 0.01:
				var leak_txt := "слабая" if leak_v < 0.35 else ("средняя" if leak_v < 0.7 else "сильная")
				lines.append("Утечка уплотнений: %s (%.0f%%) — травит давление" % [leak_txt, leak_v * 100.0])
			if str(el.rod_mode) == "rodless":
				if str(el.carriage) == "magnetic":
					lines.append("Каретка магнитная (зазор)")
				else:
					lines.append("Каретка щелевая (ярмо)")
				if str(el.bump_end) != "none":
					lines.append("Упоры каретки: %s" % ("YSR" if str(el.bump_end) == "ysr" else "эластичные"))
			if str(el.spring_side) != "none":
				lines.append("Пружина: %.2f Н/мм, преднатяг %.0f Н" % [el.spring_rate, el.spring_preload])
	return lines


static func _plain_name(el) -> String:
	return "∅%.0f × %.0f, шток %.0f" % [el.bore_mm, el.stroke_mm, el.rod_mm]


static func _cush_name(value: String) -> String:
	match value:
		"fixed":
			return "фиксированная"
		"adjustable":
			return "регулируемая PPV"
		"self":
			return "PPS"
		_:
			return "нет"


static func _mount_name(value: String) -> String:
	match value:
		"foot":
			return "лапы"
		"flange_front":
			return "фланец спереди"
		"flange_rear":
			return "фланец сзади"
		"clevis":
			return "серьга"
		"trunnion":
			return "цапфы"
		_:
			return "нет"


static func _brake_name(value: String) -> String:
	match value:
		"nc":
			return "зажим NC"
		"end_lock":
			return "стопор конца"
		"double":
			return "двойной"
		_:
			return "нет"


static func _spring_name(value: String) -> String:
	match value:
		"rod":
			return "справа, втягивает"
		"cap":
			return "слева, выдвигает"
		"both":
			return "с двух сторон, так не делают"
		_:
			return "нет"


static func _tip_name(value: String) -> String:
	match value:
		"female":
			return "внутренняя резьба"
		"plain":
			return "без наконечника"
		"clevis":
			return "вилка"
		"roller":
			return "ролик"
		_:
			return "наружная резьба"
