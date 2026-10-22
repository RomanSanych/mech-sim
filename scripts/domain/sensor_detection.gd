class_name SensorDetection
extends RefCounted
## Hit-тест зон датчиков. Форма зоны = один источник правды с sensor_field_viz.


const DetectMat = preload("res://scripts/domain/detect_material.gd")

## Осевая полудлина поля кольцевого магнита поршня (мм), если нет Sn на цели.
const DEFAULT_MAGNET_AXIAL_MM := 16.0
## Насколько поле «выбивает» за наружный габарит корпуса (доля); +≈1/7 к прежнему 1.12.
const MAGNET_FIELD_OVERSHOOT := 1.28


## Нормализованная уставка 0.01…1.0 (винт чувствительности).
static func threshold_norm(el) -> float:
	if el == null:
		return 0.5
	var pct: float = 50.0
	if "threshold_pct" in el:
		pct = float(el.threshold_pct)
	return clampf(pct, 1.0, 100.0) / 100.0


## Описание объёма срабатывания (локаль датчика, ось чутья = +X к торцу).
static func zone_desc(el) -> Dictionary:
	if el == null:
		return {}
	var sn_m: float = maxf(float(el.sense_range_mm), 0.5) * 0.001
	# Уставка: выше % → дальше / чувствительнее (I/C/компакт-оптика).
	if str(el.sensor_class) in ["inductive", "capacitive"] \
			or (str(el.sensor_class) == "optical" and str(el.optical_form) == "compact"):
		sn_m *= threshold_norm(el)
	var od_m: float = maxf(float(el.body_od_mm), 8.0) * 0.001
	var body_l: float = maxf(float(el.stroke_mm), 40.0) * 0.001
	var face_x: float = body_l * 0.5
	# Радиус зоны ≥ торца: иначе крупный корпус ПЦ «мимо» узкого цилиндра Sn.
	var zone_r: float = maxf(od_m * 0.65, sn_m * 0.55)
	match str(el.sensor_class):
		"pressure_switch", "pressure_tx", "rtd":
			# Давление / температура процесса — не пространственная зона hit-теста.
			return {}
		"optical":
			# Компакт / fallback без волокна: конус с торца корпуса.
			return {
				"shape": "cone",
				"origin": Vector3(face_x + sn_m * 0.5, 0.0, 0.0),
				"axis": Vector3.RIGHT,
				"radius": maxf(sn_m * 0.18, 0.01),
				"length": sn_m,
				"sn_m": sn_m,
				"face": Vector3(face_x, 0.0, 0.0),
			}
		"ultrasonic":
			# Конус УЗ (= hit-тест + sensor_field_viz). sn_m — конец диапазона.
			var sn_min_m: float = 0.0
			if "sense_min_mm" in el:
				sn_min_m = maxf(float(el.sense_min_mm), 0.0) * 0.001
			return {
				"shape": "cone",
				"origin": Vector3(face_x + sn_m * 0.5, 0.0, 0.0),
				"axis": Vector3.RIGHT,
				"radius": maxf(sn_m * 0.16, 0.012),
				"length": sn_m,
				"sn_m": sn_m,
				"sn_min_m": sn_min_m,
				"face": Vector3(face_x, 0.0, 0.0),
			}
		"reed":
			# Компактная зона головки (визуал датчика). Hit = поле магнита, не эта сфера.
			var head_r: float = maxf(od_m * 0.85, 0.006)
			return {
				"shape": "sphere",
				"origin": Vector3.ZERO,
				"axis": Vector3.RIGHT,
				"radius": head_r,
				"length": head_r * 2.0,
				"sn_m": sn_m,
				"face": Vector3.ZERO,
			}
		_:
			return {
				"shape": "cylinder",
				"origin": Vector3(face_x + sn_m * 0.5, 0.0, 0.0),
				"axis": Vector3.RIGHT,
				"radius": zone_r,
				"length": sn_m,
				"sn_m": sn_m,
				"face": Vector3(face_x, 0.0, 0.0),
			}


## Поле магнита поршня в локали Rod (центр пояска без el.x — Rod уже сдвинут).
static func cylinder_magnet_field_rod_local(el) -> Dictionary:
	var bore_m: float = maxf(float(el.bore_mm), 20.0) * 0.001
	var piston_t: float = maxf(bore_m * 0.22, 0.006)
	var half_yz: float = _cylinder_outer_half_yz(el)
	var radius: float = half_yz * MAGNET_FIELD_OVERSHOOT
	# Осевая ширина поля — на треть меньше толщины поршня.
	var length: float = piston_t * (2.0 / 3.0)
	var piston0: float = _cylinder_piston0_local(el)
	return {
		"shape": "cylinder",
		"origin": Vector3(piston0, 0.0, 0.0),
		"axis": Vector3.RIGHT,
		"radius": radius,
		"length": length,
		"kind": "magnetic",
	}


## Мировое поле магнита (= hit-тест для геркона).
static func cylinder_magnet_field_world(el) -> Dictionary:
	var local_f: Dictionary = cylinder_magnet_field_rod_local(el)
	if local_f.is_empty():
		return {}
	var x_m: float = float(el.x) if "x" in el else 0.0
	var center_local := Vector3(float((local_f.get("origin", Vector3.ZERO) as Vector3).x) + x_m, 0.0, 0.0)
	var length: float = float(local_f.get("length", 0.03))
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var axis_w: Vector3 = (el.world_basis * Vector3.RIGHT).normalized()
	var center_w: Vector3 = xf * center_local
	var face_w: Vector3 = center_w - axis_w * (length * 0.5)
	return {
		"shape": "cylinder",
		"pos": center_w,
		"face": face_w,
		"axis": axis_w,
		"radius": float(local_f.get("radius", 0.03)),
		"length": length,
		"el_id": int(el.id),
		"kind": "piston_magnet",
	}


## Поле магнита: объём = hit-тест (цилиндр пояска; у свободного магнита — сфера).
static func source_field_desc(el) -> Dictionary:
	if el == null:
		return {}
	if str(el.kind) == "cylinder" and _cylinder_has_magnet(el):
		return cylinder_magnet_field_rod_local(el)
	if DetectMat.normalize(DetectMat.default_for_element(el)) == DetectMat.MAGNET:
		var r_mm: float = DEFAULT_MAGNET_AXIAL_MM
		if "sense_range_mm" in el and float(el.sense_range_mm) > 0.1:
			r_mm = float(el.sense_range_mm)
		var r: float = r_mm * 0.001
		return {
			"shape": "sphere",
			"origin": Vector3.ZERO,
			"axis": Vector3.UP,
			"radius": r,
			"length": r * 2.0,
			"kind": "magnetic",
		}
	return {}


## Мировые поля магнитных источников (поршень ПЦ + элементы с тегом magnet).
static func magnet_sources_world(circuit) -> Array:
	var out: Array = []
	if circuit == null:
		return out
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) == "cylinder" and _cylinder_has_magnet(el):
			var field: Dictionary = cylinder_magnet_field_world(el)
			if not field.is_empty():
				out.append(field)
			continue
		var mat: String = DetectMat.default_for_element(el)
		if DetectMat.normalize(mat) != DetectMat.MAGNET:
			continue
		var r_mm: float = DEFAULT_MAGNET_AXIAL_MM
		if "sense_range_mm" in el and float(el.sense_range_mm) > 0.1:
			r_mm = float(el.sense_range_mm)
		var r: float = r_mm * 0.001
		out.append({
			"shape": "sphere",
			"pos": el.world_pos as Vector3,
			"face": el.world_pos as Vector3,
			"axis": Vector3.UP,
			"radius": r,
			"length": r * 2.0,
			"el_id": int(el.id),
			"kind": "magnet",
		})
	return out


static func _cylinder_outer_half_yz(el) -> float:
	var bore_m: float = maxf(float(el.bore_mm), 20.0) * 0.001
	var style: String = str(el.body_style) if "body_style" in el else ""
	var rod_mode: String = str(el.rod_mode) if "rod_mode" in el else ""
	var rodless: bool = rod_mode == "rodless"
	var roundish: bool = style == "round" or style == "tierod" or rodless
	if roundish:
		return bore_m * (0.58 if rodless else 0.62) * 1.08
	var profile: float = bore_m * (1.15 if style == "compact" else 1.48)
	return profile * 0.52


static func _cylinder_piston0_local(el) -> float:
	var bore_m: float = maxf(float(el.bore_mm), 20.0) * 0.001
	var stroke_m: float = maxf(float(el.stroke_mm), 40.0) * 0.001
	var style: String = str(el.body_style) if "body_style" in el else ""
	var rod_mode: String = str(el.rod_mode) if "rod_mode" in el else ""
	var rodless: bool = rod_mode == "rodless"
	var cap_l: float = maxf(bore_m * (0.45 if rodless else (0.38 if style == "compact" else 0.72)), 0.012)
	var barrel_l: float = stroke_m + maxf(bore_m * (0.25 if rodless else (0.18 if style == "compact" else 0.40)), 0.01)
	var total: float = cap_l * 2.0 + barrel_l
	var x0: float = -total * 0.5
	return x0 + cap_l + 0.004


static func _element_is_magnet_source(el) -> bool:
	if el == null:
		return false
	if str(el.kind) == "cylinder" and _cylinder_has_magnet(el):
		return true
	return DetectMat.normalize(DetectMat.default_for_element(el)) == DetectMat.MAGNET


static func _cylinder_has_magnet(el) -> bool:
	var pk: String = str(el.piston_kind) if "piston_kind" in el else ""
	if pk == "magnetic":
		return true
	var rod_mode: String = str(el.rod_mode) if "rod_mode" in el else ""
	var carriage: String = str(el.carriage) if "carriage" in el else ""
	return rod_mode == "rodless" and carriage == "magnetic"


## Локальный центр магнитного пояска поршня (как в iso_cylinder: piston0 + el.x).
static func cylinder_magnet_local(el) -> Vector3:
	var piston0: float = _cylinder_piston0_local(el)
	var x_m: float = float(el.x) if "x" in el else 0.0
	return Vector3(piston0 + x_m, 0.0, 0.0)


static func step(circuit) -> void:
	if circuit == null:
		return
	for el in circuit.elements:
		if el == null or str(el.kind) != "sensor":
			continue
		_step_one(circuit, el)


static func _step_one(circuit, el) -> void:
	if str(el.sensor_class) == "pressure_switch":
		_step_pressure_switch(circuit, el)
		return
	if str(el.sensor_class) == "pressure_tx":
		_step_pressure_tx(circuit, el)
		return
	if str(el.sensor_class) == "rtd":
		_step_rtd(circuit, el)
		return
	var target: bool = false
	match str(el.sensor_class):
		"reed":
			target = _magnet_in_reed_zone(circuit, el)
		"optical":
			target = _optical_sense(circuit, el)
		"ultrasonic":
			target = _ultrasonic_sense(circuit, el)
		_:
			target = _metal_in_zone(circuit, el)
	el.sensor_target = target
	var powered: bool = bool(el.sensor_powered)
	if not bool(el.sensor_active):
		powered = true
	var sense: bool = powered and target
	if bool(el.pressed) and powered and not target:
		match str(el.sensor_class):
			"reed":
				sense = _magnet_in_reed_zone(circuit, el, true)
			"optical":
				sense = _optical_sense(circuit, el, true)
			"ultrasonic":
				sense = _ultrasonic_sense(circuit, el, true)
			_:
				sense = _metal_in_zone(circuit, el, true)
	el.pressed = sense
	el.lit = sense
	if str(el.sensor_class) == "ultrasonic":
		_update_ultrasonic_analog(circuit, el, powered)


## Давление в подключённой пневмолинии (бар изб.). Нет трубки → 0 (атмосфера).
static func pressure_switch_line_bar(circuit, el) -> float:
	if circuit == null or el == null:
		return 0.0
	var eid: int = int(el.id)
	for wire in circuit.wires:
		if wire == null:
			continue
		var hit: bool = false
		if int(wire.a_id) == eid and str(wire.a_port) in ["P", "1", "p"]:
			hit = true
		elif int(wire.b_id) == eid and str(wire.b_port) in ["P", "1", "p"]:
			hit = true
		if not hit:
			continue
		return maxf((float(wire.pressure) - 101325.0) / 1.0e5, 0.0)
	return 0.0


## Пассивное реле давления: включение @ уставка, отпускание @ уставка − гистерезис.
static func _step_pressure_switch(circuit, el) -> void:
	var p_bar: float = pressure_switch_line_bar(circuit, el)
	var set_b: float = float(el.set_pressure_bar)
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		pmax = pmin + 0.05
	set_b = clampf(set_b, pmin, pmax)
	var hyst: float = maxf(float(el.hysteresis_bar), 0.02)
	hyst = minf(hyst, maxf(set_b - pmin, 0.02))
	var was_on: bool = bool(el.sensor_target)
	var on: bool = false
	if was_on:
		# Удержание, пока P не уйдёт ниже уставки на дифференциал.
		on = p_bar >= (set_b - hyst)
	else:
		on = p_bar >= set_b
	el.sensor_target = on
	# Пассивный: без Uпит головки (как геркон).
	el.sensor_powered = true
	el.pressed = on
	el.lit = on


## Активный ПИП: P линии → analog_value по шкале диапазона. Без Uпит → 0 / invalid.
## Blind: локального дисплея нет — P и сигнал в tooltip.
static func _step_pressure_tx(circuit, el) -> void:
	var SensorSig = preload("res://scripts/domain/sensor_signal.gd")
	var p_bar: float = pressure_switch_line_bar(circuit, el)
	var powered: bool = bool(el.sensor_powered)
	el.sensor_target = powered
	el.pressed = false
	el.lit = powered
	if not powered:
		el.analog_value = 0.0
		return
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		pmax = pmin + 0.05
	var t: float = clampf((p_bar - pmin) / (pmax - pmin), 0.0, 1.0)
	el.analog_value = SensorSig.analog_from_norm(str(el.analog_kind), t, true)


## Пассивный ТС: T зоны → R(НСХ) → Rизм (2/3/4 + кабель) → показание вторички (°C).
## analog_value = Tизм °C при питании вторички; иначе 0 / invalid.
static func _step_rtd(circuit, el) -> void:
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var SensorCat = preload("res://scripts/domain/sensor_catalog.gd")
	var tmin: float = float(el.sense_min_mm)
	var tmax: float = float(el.sense_range_mm)
	if tmax < tmin + 1.0:
		tmax = tmin + 1.0
	var t_zone: float = clampf(float(el.temperature_c), tmin, tmax)
	el.temperature_c = t_zone
	var typ: String = SensorCat.rtd_type_of(el)
	var r_sensor: float = Rtd.resistance_ohm(t_zone, typ)
	var cable: Dictionary = rtd_cable_params(circuit, el)
	var r_lead: float = Rtd.lead_ohm(float(cable.get("length_m", 0.0)), float(cable.get("section_mm2", 0.75)))
	var scheme: int = clampi(int(el.wire_scheme), 2, 4)
	var r_meas: float = Rtd.measured_ohm(r_sensor, r_lead, scheme)
	var t_meas: float = Rtd.temperature_c(r_meas, typ)
	# Пассивный зонд: «питание головки» не нужно; валидность = вторичка под Uпит.
	var meter_on: bool = bool(el.sensor_powered)
	el.sensor_target = meter_on
	el.pressed = false
	el.lit = meter_on
	if not meter_on:
		el.analog_value = 0.0
		return
	el.analog_value = t_meas


## Длина/сечение полевого кабеля ТС (жилы 1…N к вторичке). Берёт max length_m и min сечение.
static func rtd_cable_params(circuit, el) -> Dictionary:
	var out: Dictionary = {"length_m": 0.0, "section_mm2": 0.75}
	if circuit == null or el == null:
		return out
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var cores: PackedStringArray = Rtd.core_names(int(el.wire_scheme))
	var eid: int = int(el.id)
	var meter_id: int = -1
	for m in circuit.electro_group_members(eid):
		if str(m.member_role) == "device" and str(m.electro_class) == "rtd_meter":
			meter_id = int(m.id)
			break
	var len_max: float = 0.0
	var sec_min: float = 1.0e9
	var found: int = 0
	for wire in circuit.wires:
		if wire == null:
			continue
		var a_ok: bool = false
		var b_ok: bool = false
		if int(wire.a_id) == eid and str(wire.a_port) in cores:
			a_ok = true
		elif int(wire.b_id) == eid and str(wire.b_port) in cores:
			b_ok = true
		if not a_ok and not b_ok:
			continue
		var other_id: int = int(wire.b_id) if a_ok else int(wire.a_id)
		if meter_id >= 0 and other_id != meter_id:
			# Допускаем и прямое соединение к любому электро (щит).
			var other = circuit.get_element(other_id)
			if other == null or str(other.kind) != "electro":
				continue
		found += 1
		len_max = maxf(len_max, float(wire.length_m))
		sec_min = minf(sec_min, maxf(float(wire.id_mm), 0.1))
	if found <= 0:
		return out
	if len_max < 0.01:
		# Нет 3D-длины: оценка по world-позиции зонда ↔ щит (~2 м минимум).
		len_max = 2.0
		var prim = circuit.get_element(eid)
		if prim != null:
			var wp: Vector3 = prim.world_pos as Vector3
			# Кабинет условно у x≈1.2 м — учебный fallback.
			len_max = maxf(len_max, absf(wp.x - 1.2) + absf(wp.z) + 1.5)
	out["length_m"] = len_max
	out["section_mm2"] = sec_min if sec_min < 1.0e8 else 0.75
	return out


## Rдат / Rизм / Tизм для tooltip (без требования питания вторички).
static func rtd_probe_snapshot(circuit, el) -> Dictionary:
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var SensorCat = preload("res://scripts/domain/sensor_catalog.gd")
	var empty: Dictionary = {
		"t_zone": 20.0, "r_sensor": 100.0, "r_lead": 0.0, "r_meas": 100.0,
		"t_meas": 20.0, "length_m": 0.0, "section_mm2": 0.75, "scheme": 3,
	}
	if el == null:
		return empty
	var typ: String = SensorCat.rtd_type_of(el)
	var t_zone: float = float(el.temperature_c)
	var r_sensor: float = Rtd.resistance_ohm(t_zone, typ)
	var cable: Dictionary = rtd_cable_params(circuit, el)
	var r_lead: float = Rtd.lead_ohm(float(cable.get("length_m", 0.0)), float(cable.get("section_mm2", 0.75)))
	var scheme: int = clampi(int(el.wire_scheme), 2, 4)
	var r_meas: float = Rtd.measured_ohm(r_sensor, r_lead, scheme)
	return {
		"t_zone": t_zone,
		"r_sensor": r_sensor,
		"r_lead": r_lead,
		"r_meas": r_meas,
		"t_meas": Rtd.temperature_c(r_meas, typ),
		"length_m": float(cable.get("length_m", 0.0)),
		"section_mm2": float(cable.get("section_mm2", 0.75)),
		"scheme": scheme,
		"type": typ,
	}


## Оптонаконечники, связанные с усилителем чёрным оптокабелем (домен optic).
static func linked_opto_tips(circuit, amp) -> Array:
	var out: Array = []
	if circuit == null or amp == null:
		return out
	var amp_id: int = int(amp.id)
	for wire in circuit.wires:
		if wire == null:
			continue
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		if ea == null or eb == null:
			continue
		var da: String = str(circuit.port_domain(ea, str(wire.a_port)))
		if da != "optic":
			continue
		var tip = null
		if int(wire.a_id) == amp_id and str(eb.kind) == "opto_tip":
			tip = eb
		elif int(wire.b_id) == amp_id and str(ea.kind) == "opto_tip":
			tip = ea
		if tip != null and not out.has(tip):
			out.append(tip)
	return out


## Режим по геометрии наконечников: barrier | retro | diffuse | none.
static func optical_mode(circuit, amp) -> String:
	var tips: Array = linked_opto_tips(circuit, amp)
	var has_tx: bool = false
	var has_rx: bool = false
	var has_head: bool = false
	for t in tips:
		match str(t.opto_role):
			"emitter":
				has_tx = true
			"receiver":
				has_rx = true
			_:
				has_head = true
	if has_tx and has_rx:
		return "barrier"
	if has_head:
		# Рефлектор в луче → R, иначе диффуз.
		for t in tips:
			if str(t.opto_role) == "emitter" or str(t.opto_role) == "receiver":
				continue
			if _optical_sees_reflector(circuit, t, amp):
				return "retro"
		return "diffuse"
	return "none"


## Объёмы лучей/конусов для sensor_field_viz (= hit-тест). Мировые.
static func optical_beam_world(circuit, amp) -> Array:
	var out: Array = []
	if circuit == null or amp == null:
		return out
	var tips: Array = linked_opto_tips(circuit, amp)
	var mode: String = optical_mode(circuit, amp)
	var sn_m: float = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var hyst: float = 0.0
	match mode:
		"barrier":
			var tx = _first_tip_role(tips, "emitter")
			var rx = _first_tip_role(tips, "receiver")
			if tx != null:
				var a: Vector3 = _tip_face_world(tx)
				var axis: Vector3 = _tip_axis_world(tx)
				var length: float = maxf(float(tx.sense_range_mm), float(amp.sense_range_mm) * 4.0) * 0.001
				length = minf(length, 3.5)
				if rx != null:
					var along_rx: float = (_tip_face_world(rx) - a).dot(axis)
					if along_rx > 0.01:
						length = minf(length, along_rx)
				# Луч обрезаем по первому препятствию (не «просвечивает» объект).
				var hit_d: float = _ray_hit_first_occluder(circuit, amp, tx, rx, a, axis, length)
				if hit_d >= 0.0:
					length = hit_d
				if length > 0.002:
					out.append({
						"shape": "cylinder",
						"pos": a + axis * (length * 0.5),
						"face": a,
						"axis": axis,
						"radius": 0.004,
						"length": length,
						"kind": "optical_barrier",
						"el_id": int(amp.id),
					})
		"retro":
			var head_r = _first_tip_role(tips, "head")
			if head_r == null:
				head_r = _first_tip_role(tips, "")
			if head_r != null:
				var face_r: Vector3 = _tip_face_world(head_r)
				var axis_r: Vector3 = _tip_axis_world(head_r)
				var reach_r: float = maxf(sn_m * 3.0, 0.3)
				var hit_r: Dictionary = _optical_first_hit(circuit, amp, head_r, face_r, axis_r, reach_r, hyst)
				var len_r: float = float(hit_r.get("dist", reach_r))
				out.append({
					"shape": "cylinder",
					"pos": face_r + axis_r * (len_r * 0.5),
					"face": face_r,
					"axis": axis_r,
					"radius": 0.005,
					"length": len_r,
					"kind": "optical_retro",
					"el_id": int(amp.id),
				})
		"diffuse":
			var head_d = _first_tip_role(tips, "head")
			if head_d == null:
				head_d = _first_tip_role(tips, "")
			if head_d != null:
				var face_d: Vector3 = _tip_face_world(head_d)
				var axis_d: Vector3 = _tip_axis_world(head_d)
				var cone_r: float = maxf(sn_m * 0.18, 0.01)
				out.append({
					"shape": "cone",
					"pos": face_d + axis_d * (sn_m * 0.5),
					"face": face_d,
					"axis": axis_d,
					"radius": cone_r,
					"length": sn_m,
					"kind": "optical_diffuse",
					"el_id": int(amp.id),
				})
		_:
			pass
	return out


static func _first_tip_role(tips: Array, role: String):
	for t in tips:
		if role == "":
			return t
		if str(t.opto_role) == role:
			return t
		if role == "head" and str(t.opto_role) not in ["emitter", "receiver"]:
			return t
	return null


static func _tip_face_world(tip) -> Vector3:
	var od_m: float = maxf(float(tip.body_od_mm), 6.0) * 0.001
	var len_m: float = maxf(float(tip.stroke_mm), 20.0) * 0.001
	var local := Vector3(len_m * 0.5, 0.0, 0.0)
	var xf := Transform3D(tip.world_basis, tip.world_pos)
	return xf * local


static func _tip_axis_world(tip) -> Vector3:
	var ax: Vector3 = (tip.world_basis * Vector3.RIGHT)
	if ax.length_squared() < 1.0e-10:
		return Vector3.RIGHT
	return ax.normalized()


static func _optical_sense(circuit, el, use_hysteresis: bool = false) -> bool:
	# Компактный датчик — только D/R с корпуса (винт уставки = дальность), без PV/SET.
	if str(el.optical_form) == "compact":
		if _optical_sees_reflector_from_amp(circuit, el):
			return _optical_retro_from_amp(circuit, el, use_hysteresis)
		return _optical_diffuse_from_amp(circuit, el, use_hysteresis)
	# Волоконный усилитель (Lanbao FD3): OUT = сравнение PV и SET + LO/DO.
	# Light-ON: PV ≥ SET; Dark-ON: PV < SET. Иначе уставка на дисплее не влияет на выход.
	var pv: int = optical_signal_level(circuit, el)
	return _optical_out_from_pv_set(el, pv, use_hysteresis)


## Выход усилителя по дисплейным PV/SET (0…999) и режиму LO/DO.
static func _optical_out_from_pv_set(el, pv: int, use_hysteresis: bool) -> bool:
	var set_n: int = clampi(
		int(round(clampf(float(el.threshold_pct), 0.0, 100.0) * 9.99)),
		0, 999
	)
	var light_on: bool = true
	if el != null and "optical_light_on" in el:
		light_on = bool(el.optical_light_on)
	var hyst: int = 0
	if use_hysteresis and el != null:
		hyst = clampi(int(round(maxf(float(el.hysteresis_mm), 0.0) * 2.0)), 5, 60)
	if light_on:
		return int(pv) >= (set_n - hyst)
	return int(pv) < (set_n + hyst)


static func _optical_sees_reflector(circuit, tip, amp) -> bool:
	var face: Vector3 = _tip_face_world(tip)
	var axis: Vector3 = _tip_axis_world(tip)
	var sn_m: float = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var reach: float = maxf(sn_m * 3.0, 0.3)
	var hit: Dictionary = _optical_first_hit(circuit, amp, tip, face, axis, reach, 0.0)
	if not bool(hit.get("ok", false)):
		return false
	return DetectMat.is_reflector(str(hit.get("mat", "")))


## Уровень сигнала 0…999 для дисплея усилителя (PV).
static func optical_signal_level(circuit, amp) -> int:
	if circuit == null or amp == null:
		return 0
	if str(amp.optical_form) == "compact":
		return _optical_signal_from_amp(circuit, amp)
	var tips: Array = linked_opto_tips(circuit, amp)
	var mode: String = optical_mode(circuit, amp)
	match mode:
		"barrier":
			var tx = _first_tip_role(tips, "emitter")
			var rx = _first_tip_role(tips, "receiver")
			if tx == null or rx == null:
				return 0
			return _optical_barrier_pv(circuit, amp, tx, rx)
		"retro", "diffuse":
			var head = _first_tip_role(tips, "head")
			if head == null:
				return 0
			return _optical_signal_from_tip(circuit, amp, head)
		_:
			return 0


## Барьер: свой TX + засветка от чужих излучателей/голов (crosstalk в апертуру RX).
static func _optical_barrier_pv(circuit, amp, tx, rx) -> int:
	var own: int = _optical_src_beam_pv(circuit, amp, tx, rx)
	var foreign: int = _optical_foreign_beams_pv(circuit, amp, rx, int(tx.id) if tx != null else -1)
	var best: int = maxi(own, foreign)
	return best if best > 0 else 14


## Свет в апертуре RX от одного источника (emitter / head tip). 0 = нет вклада.
static func _optical_src_beam_pv(circuit, owner_amp, src, rx) -> int:
	if src == null or rx == null:
		return 0
	var a: Vector3 = _tip_face_world(src)
	var b: Vector3 = _tip_face_world(rx)
	var sax: Vector3 = _tip_axis_world(src)
	var rax: Vector3 = _tip_axis_world(rx)
	var src_amp = _amp_for_tip(circuit, src)
	if src_amp == null:
		src_amp = owner_amp
	var reach: float = maxf(float(src.sense_range_mm), 50.0) * 0.001
	if src_amp != null:
		reach = maxf(reach, maxf(float(src_amp.sense_range_mm), 50.0) * 0.001 * 4.0)
	reach = minf(maxf(reach, 0.05), 3.5)
	var along: float = (b - a).dot(sax)
	if along < 0.008 or along > reach:
		return 0
	var miss: float = (a + sax * along).distance_to(b)
	var beam_r: float = 0.0035 + along * 0.016
	# Голова D/R — шире конус, чем узкий барьерный TX.
	if str(src.opto_role) == "head":
		beam_r = 0.008 + along * 0.055
	if miss > beam_r * 2.2:
		return 0
	var spot: float = clampf(1.0 - miss / maxf(beam_r, 0.001), 0.0, 1.0)
	var rx_face: float = clampf(rax.dot(-sax), 0.0, 1.0)
	if rx_face < 0.22:
		return 0
	var dist_q: float = 1.0 / (1.0 + along * along * 3.0)
	var q: float = pow(spot, 0.85) * pow(rx_face, 0.75) * dist_q
	if _ray_hit_first_occluder(circuit, src_amp, src, rx, a, sax, along) >= 0.0:
		return clampi(int(round(10.0 + q * 40.0)), 8, 50)
	return clampi(int(round(45.0 + q * 910.0)), 30, 960)


## Чужие emitter/head (+ компакт-оптика) → вклад в PV приёмника барьера.
static func _optical_foreign_beams_pv(circuit, amp, rx, skip_tip_id: int) -> int:
	if circuit == null or rx == null:
		return 0
	var best: int = 0
	var rx_id: int = int(rx.id)
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) == "opto_tip":
			var role: String = str(el.opto_role)
			if role != "emitter" and role != "head":
				continue
			var tid: int = int(el.id)
			if tid == skip_tip_id or tid == rx_id:
				continue
			best = maxi(best, _optical_src_beam_pv(circuit, amp, el, rx))
		elif str(el.kind) == "sensor" and str(el.sensor_class) == "optical":
			if int(el.id) == int(amp.id):
				continue
			if str(el.optical_form) != "compact":
				continue
			best = maxi(best, _optical_compact_beam_pv(circuit, el, rx))
	return best


## Компактный датчик как источник засветки (луч с торца корпуса).
static func _optical_compact_beam_pv(circuit, src_amp, rx) -> int:
	if src_amp == null or rx == null:
		return 0
	var z: Dictionary = zone_desc(src_amp)
	if z.is_empty():
		return 0
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(src_amp.world_basis, src_amp.world_pos)
	var a: Vector3 = xf * face_local
	var sax: Vector3 = (src_amp.world_basis * Vector3.RIGHT).normalized()
	var b: Vector3 = _tip_face_world(rx)
	var rax: Vector3 = _tip_axis_world(rx)
	var reach: float = minf(maxf(float(z.get("sn_m", 0.1)) * 1.2, 0.05), 3.5)
	var along: float = (b - a).dot(sax)
	if along < 0.008 or along > reach:
		return 0
	var miss: float = (a + sax * along).distance_to(b)
	var beam_r: float = 0.01 + along * 0.06
	if miss > beam_r * 2.2:
		return 0
	var spot: float = clampf(1.0 - miss / maxf(beam_r, 0.001), 0.0, 1.0)
	var rx_face: float = clampf(rax.dot(-sax), 0.0, 1.0)
	if rx_face < 0.22:
		return 0
	var dist_q: float = 1.0 / (1.0 + along * along * 3.0)
	var q: float = pow(spot, 0.85) * pow(rx_face, 0.75) * dist_q
	if _ray_hit_first_occluder(circuit, src_amp, null, rx, a, sax, along) >= 0.0:
		return clampi(int(round(10.0 + q * 40.0)), 8, 50)
	return clampi(int(round(45.0 + q * 910.0)), 30, 960)


static func _amp_for_tip(circuit, tip):
	if circuit == null or tip == null:
		return null
	var tip_id: int = int(tip.id)
	for wire in circuit.wires:
		if wire == null:
			continue
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		if ea == null or eb == null:
			continue
		if str(circuit.port_domain(ea, str(wire.a_port))) != "optic":
			continue
		if int(wire.a_id) == tip_id and str(eb.kind) == "sensor" and str(eb.sensor_class) == "optical":
			return eb
		if int(wire.b_id) == tip_id and str(ea.kind) == "sensor" and str(ea.sensor_class) == "optical":
			return ea
	return null


static func _optical_signal_from_tip(circuit, amp, tip) -> int:
	var face: Vector3 = _tip_face_world(tip)
	var axis: Vector3 = _tip_axis_world(tip)
	var sn_m: float = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var hit: Dictionary = _optical_first_hit(circuit, amp, tip, face, axis, sn_m, 0.0)
	if not bool(hit.get("ok", false)):
		return 20
	var factor: float = DetectMat.optical_diffuse_factor(str(hit.get("mat", "")))
	var dist: float = float(hit.get("dist", sn_m))
	var fall: float = clampf(1.0 - dist / maxf(sn_m, 0.001), 0.0, 1.0)
	return clampi(int(round(factor * fall * 980.0)), 0, 999)


static func _optical_signal_from_amp(circuit, amp) -> int:
	var z: Dictionary = zone_desc(amp)
	if z.is_empty():
		return 0
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(amp.world_basis, amp.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (amp.world_basis * Vector3.RIGHT).normalized()
	var sn: float = float(z.get("sn_m", 0.1))
	var hit: Dictionary = _optical_first_hit(circuit, amp, null, face_w, axis_w, sn, 0.0)
	if not bool(hit.get("ok", false)):
		return 20
	var factor: float = DetectMat.optical_diffuse_factor(str(hit.get("mat", "")))
	var dist: float = float(hit.get("dist", sn))
	var fall: float = clampf(1.0 - dist / maxf(sn, 0.001), 0.0, 1.0)
	return clampi(int(round(factor * fall * 980.0)), 0, 999)


static func _ray_hit_first_occluder(circuit, amp, tx, rx, origin: Vector3, axis: Vector3, reach: float) -> float:
	var best: float = -1.0
	var skip: Dictionary = {}
	if amp != null:
		skip[int(amp.id)] = true
	if tx != null:
		skip[int(tx.id)] = true
	if rx != null:
		skip[int(rx.id)] = true
	for other in circuit.elements:
		if other == null or skip.has(int(other.id)):
			continue
		if str(other.kind) in ["opto_tip", "sensor", "electro", "coil", "rail"]:
			continue
		var mat: String = DetectMat.default_for_element(other)
		if not DetectMat.optical_occludes(mat):
			continue
		var d: float = _ray_hit_aabb_dist(origin, axis, reach, other)
		if d < 0.0:
			continue
		if best < 0.0 or d < best:
			best = d
	return best


static func _optical_barrier_blocked(circuit, amp, tx, rx, _use_hysteresis: bool) -> bool:
	# Луч вдоль оси TX; перекрытие — только если RX в конусе и есть окклюдер.
	var a: Vector3 = _tip_face_world(tx)
	var b: Vector3 = _tip_face_world(rx)
	var tax: Vector3 = _tip_axis_world(tx)
	var rax: Vector3 = _tip_axis_world(rx)
	var to_rx: Vector3 = b - a
	var along: float = to_rx.dot(tax)
	if along < 0.01 or along > 3.5:
		return false
	if rax.dot(-tax) < 0.25:
		return false
	var miss: float = (a + tax * along).distance_to(b)
	var beam_r: float = 0.0035 + along * 0.016
	if miss > beam_r * 2.2:
		return false
	return _ray_hit_first_occluder(circuit, amp, tx, rx, a, tax, along) >= 0.0


static func _optical_retro_blocked(circuit, amp, tip, use_hysteresis: bool) -> bool:
	var face: Vector3 = _tip_face_world(tip)
	var axis: Vector3 = _tip_axis_world(tip)
	var sn_m: float = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var hyst: float = 0.0
	if use_hysteresis:
		hyst = maxf(float(amp.hysteresis_mm), 0.0) * 0.001
	var reach: float = maxf(sn_m * 3.0, 0.3) + hyst
	var hit: Dictionary = _optical_first_hit(circuit, amp, tip, face, axis, reach, hyst)
	if not bool(hit.get("ok", false)):
		return true
	if DetectMat.is_reflector(str(hit.get("mat", ""))):
		return false
	return true


static func _optical_diffuse_hit(circuit, amp, tip, use_hysteresis: bool) -> bool:
	var face: Vector3 = _tip_face_world(tip)
	var axis: Vector3 = _tip_axis_world(tip)
	var sn_m: float = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var hyst: float = 0.0
	if use_hysteresis:
		hyst = maxf(float(amp.hysteresis_mm), 0.0) * 0.001
	var reach: float = sn_m + hyst
	var needed: float = threshold_norm(amp)
	# Несколько лучей по конусу — ловим не только «осевую» точку.
	var dirs: Array = _diffuse_sample_dirs(axis, 0.22)
	var best_strength: float = 0.0
	for dvec in dirs:
		var hit: Dictionary = _optical_first_hit(circuit, amp, tip, face, dvec as Vector3, reach, hyst)
		if not bool(hit.get("ok", false)):
			continue
		var factor: float = DetectMat.optical_diffuse_factor(str(hit.get("mat", "")))
		if factor < 0.12:
			continue
		var dist: float = float(hit.get("dist", reach))
		var falloff: float = clampf(1.0 - dist / maxf(reach, 0.001), 0.0, 1.0)
		# Угол к поверхности: ближе к нормали оси tip → сильнее возврат.
		var facing: float = maxf((dvec as Vector3).dot(axis), 0.25)
		var strength: float = factor * falloff * facing
		if strength > best_strength:
			best_strength = strength
	# Уставка: 100% ≈ белая карта на Sn; ниже — нужен ближе/ярче объект.
	return best_strength >= needed * 0.45


static func _diffuse_sample_dirs(axis: Vector3, cone: float) -> Array:
	var ax: Vector3 = axis.normalized()
	var out: Array = [ax]
	var up: Vector3 = Vector3.UP
	if absf(ax.dot(up)) > 0.9:
		up = Vector3.FORWARD
	var u: Vector3 = ax.cross(up).normalized()
	var v: Vector3 = ax.cross(u).normalized()
	for ang in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var rad: float = deg_to_rad(ang)
		var side: Vector3 = (u * cos(rad) + v * sin(rad)) * cone
		out.append((ax + side).normalized())
	return out


static func _optical_diffuse_from_amp(circuit, amp, use_hysteresis: bool) -> bool:
	var z: Dictionary = zone_desc(amp)
	if z.is_empty():
		return false
	var sn: float = float(z.get("sn_m", 0.1))
	if use_hysteresis:
		sn += maxf(float(amp.hysteresis_mm), 0.0) * 0.001
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(amp.world_basis, amp.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (amp.world_basis * Vector3.RIGHT).normalized()
	var needed: float = threshold_norm(amp)
	var best_strength: float = 0.0
	for other in circuit.elements:
		if other == null or int(other.id) == int(amp.id):
			continue
		if str(other.kind) in ["sensor", "opto_tip", "electro", "coil", "rail"]:
			continue
		var mat: String = DetectMat.default_for_element(other)
		var factor: float = DetectMat.optical_diffuse_factor(mat)
		if factor < 0.12:
			continue
		# Closest + углы AABB — разные части корпуса.
		var samples: Array = [ _closest_on_target(other, face_w) ]
		samples.append_array(_target_corners_world(other))
		for s in samples:
			var pt: Vector3 = s as Vector3
			var to_pt: Vector3 = pt - face_w
			var dist: float = to_pt.length()
			if dist < 0.001 or dist > sn * 1.05:
				continue
			var dir: Vector3 = to_pt / dist
			if dir.dot(axis_w) < 0.25:
				continue
			# Боковой разброс конуса.
			var radial: float = (pt - (face_w + axis_w * dist)).length()
			var cone_r: float = maxf(sn * 0.22, 0.012) * (dist / maxf(sn, 0.001))
			if radial > cone_r:
				continue
			var falloff: float = clampf(1.0 - dist / maxf(sn, 0.001), 0.0, 1.0)
			var strength: float = factor * falloff * maxf(dir.dot(axis_w), 0.3)
			if strength > best_strength:
				best_strength = strength
	return best_strength >= needed * 0.45


static func _optical_sees_reflector_from_amp(circuit, amp) -> bool:
	var z: Dictionary = zone_desc(amp)
	if z.is_empty():
		return false
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(amp.world_basis, amp.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (amp.world_basis * Vector3.RIGHT).normalized()
	var reach: float = maxf(float(z.get("sn_m", 0.1)) * 3.0, 0.3)
	var hit: Dictionary = _optical_first_hit(circuit, amp, null, face_w, axis_w, reach, 0.0)
	if not bool(hit.get("ok", false)):
		return false
	return DetectMat.is_reflector(str(hit.get("mat", "")))


static func _optical_retro_from_amp(circuit, amp, use_hysteresis: bool) -> bool:
	# Dark-ON: срабатывание при перекрытии пути к рефлектору.
	var z: Dictionary = zone_desc(amp)
	if z.is_empty():
		return false
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(amp.world_basis, amp.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (amp.world_basis * Vector3.RIGHT).normalized()
	var sn: float = float(z.get("sn_m", 0.1))
	if use_hysteresis:
		sn += maxf(float(amp.hysteresis_mm), 0.0) * 0.001
	var reach: float = maxf(sn * 3.0, 0.3)
	var hit: Dictionary = _optical_first_hit(circuit, amp, null, face_w, axis_w, reach, 0.0)
	if not bool(hit.get("ok", false)):
		return true
	if DetectMat.is_reflector(str(hit.get("mat", ""))):
		return false
	return true


## Первый хит луча tip→ось. {ok, dist, mat, el_id}.
static func _optical_first_hit(
	circuit, amp, tip, face: Vector3, axis: Vector3, reach: float, _hyst: float
) -> Dictionary:
	var best_d: float = reach + 1.0
	var best: Dictionary = {"ok": false}
	var skip: Dictionary = {}
	if amp != null:
		skip[int(amp.id)] = true
	if tip != null:
		skip[int(tip.id)] = true
	var ax: Vector3 = axis.normalized()
	for other in circuit.elements:
		if other == null or skip.has(int(other.id)):
			continue
		if str(other.kind) in ["opto_tip", "sensor", "electro", "coil", "rail"]:
			continue
		var mat: String = DetectMat.default_for_element(other)
		if not DetectMat.optical_occludes(mat) and not DetectMat.is_reflector(mat):
			continue
		var d: float = _ray_hit_aabb_dist(face, ax, reach, other)
		if d < 0.0:
			continue
		if d < best_d:
			best_d = d
			best = {"ok": true, "dist": d, "mat": mat, "el_id": int(other.id)}
	return best


static func _ray_hit_aabb_dist(origin: Vector3, axis: Vector3, reach: float, el) -> float:
	# Точный slab-тест ориентированного AABB в локали элемента.
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var half: Vector3 = _target_half_extents_local(el) * 1.06
	var inv: Transform3D = xf.affine_inverse()
	var o: Vector3 = inv * origin
	var d: Vector3 = inv.basis * axis
	var tmin: float = 0.0
	var tmax: float = reach
	for i in 3:
		var oi: float = o[i]
		var di: float = d[i]
		var hi: float = half[i]
		if absf(di) < 1.0e-9:
			if oi < -hi or oi > hi:
				return -1.0
			continue
		var inv_d: float = 1.0 / di
		var t1: float = (-hi - oi) * inv_d
		var t2: float = (hi - oi) * inv_d
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	if tmin >= 0.0 and tmin <= reach:
		return tmin
	if tmin < 0.0 and tmax >= 0.0 and tmax <= reach:
		return 0.0
	return -1.0


static func _segment_hits_element(a: Vector3, b: Vector3, el) -> bool:
	var seg: Vector3 = b - a
	var length: float = seg.length()
	if length < 0.001:
		return false
	var axis: Vector3 = seg / length
	return _ray_hit_aabb_dist(a, axis, length, el) >= 0.0


## Дистанция эха УЗ, мм. <0 — нет валидного отражения в диапазоне.
static func ultrasonic_distance_mm(circuit, el, use_hysteresis: bool = false) -> float:
	var hit: Dictionary = _ultrasonic_first_echo(circuit, el, use_hysteresis)
	if not bool(hit.get("ok", false)):
		return -1.0
	return float(hit.get("dist_mm", -1.0))


## Уставка дискретного OUT, мм (Pepperl+Fuchs / SICK: switching distance).
## Хранится в threshold_pct как доля измерительного диапазона sense_min…sense_range.
static func ultrasonic_setpoint_mm(el) -> float:
	if el == null:
		return 100.0
	var d_min: float = maxf(float(el.sense_min_mm) if "sense_min_mm" in el else 50.0, 1.0)
	var d_max: float = maxf(float(el.sense_range_mm), d_min + 1.0)
	var pct: float = 50.0
	if "threshold_pct" in el:
		pct = clampf(float(el.threshold_pct), 0.0, 100.0)
	return d_min + (pct / 100.0) * (d_max - d_min)


static func set_ultrasonic_setpoint_mm(el, mm: float) -> void:
	if el == null:
		return
	var d_min: float = maxf(float(el.sense_min_mm) if "sense_min_mm" in el else 50.0, 1.0)
	var d_max: float = maxf(float(el.sense_range_mm), d_min + 1.0)
	var clamped: float = clampf(mm, d_min, d_max)
	el.threshold_pct = clampf((clamped - d_min) / maxf(d_max - d_min, 1.0) * 100.0, 0.0, 100.0)


## Дискретный OUT: цель ближе уставки (switching distance), с гистерезисом при удержании.
static func ultrasonic_switch(circuit, el, use_hysteresis: bool = false) -> bool:
	var dist_mm: float = ultrasonic_distance_mm(circuit, el, false)
	if dist_mm < 0.0:
		return false
	var set_mm: float = ultrasonic_setpoint_mm(el)
	var hyst: float = 0.0
	if use_hysteresis:
		hyst = maxf(float(el.hysteresis_mm), 0.0)
	return dist_mm <= set_mm + hyst


static func _ultrasonic_sense(circuit, el, use_hysteresis: bool = false) -> bool:
	# sensor_target / дискрет: срабатывание по уставке, не «любое эхо в конусе».
	return ultrasonic_switch(circuit, el, use_hysteresis)


static func _update_ultrasonic_analog(circuit, el, powered: bool) -> void:
	var SensorSig = preload("res://scripts/domain/sensor_signal.gd")
	if not powered:
		el.analog_value = 0.0
		return
	var dist_mm: float = ultrasonic_distance_mm(circuit, el, false)
	var d_min: float = maxf(float(el.sense_min_mm) if "sense_min_mm" in el else 50.0, 1.0)
	var d_max: float = maxf(float(el.sense_range_mm), d_min + 1.0)
	# Аналог всегда от полной шкалы диапазона (независимо от уставки дискрета).
	var valid: bool = dist_mm >= d_min * 0.98 and dist_mm <= d_max * 1.02
	var t: float = 0.0
	if valid:
		t = clampf((dist_mm - d_min) / maxf(d_max - d_min, 1.0), 0.0, 1.0)
	el.analog_value = SensorSig.analog_from_norm(str(el.analog_kind), t, valid)


## Первый эхо в конусе УЗ. {ok, dist_mm, dist, mat, el_id}.
static func _ultrasonic_first_echo(circuit, el, use_hysteresis: bool = false) -> Dictionary:
	var z: Dictionary = zone_desc(el)
	if z.is_empty() or circuit == null or el == null:
		return {"ok": false}
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (el.world_basis * Vector3.RIGHT).normalized()
	var sn_max: float = float(z.get("sn_m", 0.5))
	var sn_min: float = float(z.get("sn_min_m", 0.05))
	if use_hysteresis:
		sn_max += maxf(float(el.hysteresis_mm), 0.0) * 0.001
		sn_min = maxf(sn_min - maxf(float(el.hysteresis_mm), 0.0) * 0.001 * 0.5, 0.0)
	var cone_r_far: float = float(z.get("radius", sn_max * 0.16))
	var best_d: float = sn_max + 1.0
	var best: Dictionary = {"ok": false}
	var sid: int = int(el.id)
	for other in circuit.elements:
		if other == null or int(other.id) == sid:
			continue
		if str(other.kind) in ["sensor", "opto_tip", "electro", "coil", "rail"]:
			continue
		var mat: String = DetectMat.default_for_element(other)
		var factor: float = DetectMat.ultrasonic_echo_factor(mat)
		if factor < 0.15:
			continue
		# Осевой луч + углы AABB — ловим корпус не только по центру.
		var samples: Array = [_closest_on_target(other, face_w)]
		samples.append_array(_target_corners_world(other))
		for s in samples:
			var pt: Vector3 = s as Vector3
			var to_pt: Vector3 = pt - face_w
			var dist: float = to_pt.length()
			if dist < 0.001 or dist > sn_max * 1.02:
				continue
			if dist < sn_min * 0.98:
				continue
			var dir: Vector3 = to_pt / dist
			if dir.dot(axis_w) < 0.55:
				continue
			var along: float = to_pt.dot(axis_w)
			if along < sn_min * 0.98 or along > sn_max * 1.02:
				continue
			var radial: float = (pt - (face_w + axis_w * along)).length()
			var cone_r: float = maxf(cone_r_far * (along / maxf(sn_max, 0.001)), 0.006)
			if radial > cone_r:
				continue
			# Чем ближе к оси и сильнее фактор — тем надёжнее эхо; берём ближайшее.
			if along < best_d:
				best_d = along
				best = {
					"ok": true,
					"dist": along,
					"dist_mm": along * 1000.0,
					"mat": mat,
					"el_id": int(other.id),
					"factor": factor,
				}
		# Точный slab по оси — перекрывает «центр мимо AABB».
		var ray_d: float = _ray_hit_aabb_dist(face_w, axis_w, sn_max, other)
		if ray_d >= sn_min * 0.98 and ray_d <= sn_max * 1.02 and ray_d < best_d:
			best_d = ray_d
			best = {
				"ok": true,
				"dist": ray_d,
				"dist_mm": ray_d * 1000.0,
				"mat": mat,
				"el_id": int(other.id),
				"factor": factor,
			}
	return best


static func _magnet_in_reed_zone(circuit, el, use_hysteresis: bool = false) -> bool:
	# Hit = головка геркона внутри объёма поля магнита (тот же цилиндр, что viz).
	var reed_pos: Vector3 = el.world_pos as Vector3
	var hyst: float = 0.0
	if use_hysteresis:
		hyst = maxf(float(el.hysteresis_mm), 0.0) * 0.001
	# Каталожный зазор Sn — доп. осевое окно срабатывания вдоль хода.
	var sn_axial: float = maxf(float(el.sense_range_mm), 0.0) * 0.001
	for src in magnet_sources_world(circuit):
		if int(src.get("el_id", -1)) == int(el.id):
			continue
		var shape: String = str(src.get("shape", "cylinder"))
		var radius: float = float(src.get("radius", 0.03)) + hyst * 0.25
		if shape == "sphere":
			var mpos: Vector3 = src.get("pos", Vector3.ZERO) as Vector3
			if reed_pos.distance_to(mpos) <= radius + 0.001:
				return true
			continue
		var face: Vector3 = src.get("face", Vector3.ZERO) as Vector3
		var axis: Vector3 = (src.get("axis", Vector3.RIGHT) as Vector3).normalized()
		var base_len: float = float(src.get("length", 0.03))
		# Окно ≥ Sn: поле viz + зона срабатывания геркона вдоль оси.
		var length: float = maxf(base_len, sn_axial * 2.0) + hyst
		var grow: float = (length - base_len) * 0.5
		face = face - axis * grow
		if _point_in_cylinder(reed_pos, face, axis, length, radius):
			return true
	return false


static func _metal_in_zone(circuit, el, use_hysteresis: bool = false) -> bool:
	var z: Dictionary = zone_desc(el)
	if z.is_empty():
		return false
	var sn: float = float(z.get("sn_m", 0.004))
	if use_hysteresis:
		sn += maxf(float(el.hysteresis_mm), 0.0) * 0.001
	var face_local: Vector3 = z.get("face", Vector3.ZERO) as Vector3
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var face_w: Vector3 = xf * face_local
	var axis_w: Vector3 = (el.world_basis * Vector3.RIGHT).normalized()
	var radius: float = float(z.get("radius", 0.01))
	var length: float = sn
	for other in circuit.elements:
		if other == null or int(other.id) == int(el.id):
			continue
		var mat: String = DetectMat.default_for_element(other)
		var factor: float = 0.0
		match str(el.sensor_class):
			"inductive":
				factor = DetectMat.inductive_range_factor(mat)
			"capacitive":
				factor = DetectMat.capacitive_range_factor(mat)
			_:
				factor = DetectMat.inductive_range_factor(mat)
		if factor <= 0.001:
			continue
		var eff_len: float = length * factor
		var eff_r: float = radius * maxf(sqrt(factor), 0.45)
		# Ближайшая точка ориентированного габарита + углы AABB — ловит корпус ПЦ сбоку/с торца.
		var closest: Vector3 = _closest_on_target(other, face_w)
		if _point_in_cylinder(closest, face_w, axis_w, eff_len, eff_r):
			return true
		if _point_in_cylinder(other.world_pos, face_w, axis_w, eff_len, eff_r):
			return true
		for corner in _target_corners_world(other):
			if _point_in_cylinder(corner as Vector3, face_w, axis_w, eff_len, eff_r):
				return true
		# Наконечник штока (сталь) — за пределами корпуса.
		if str(el.sensor_class) == "inductive" and str(other.kind) == "cylinder":
			var steel_f: float = DetectMat.inductive_range_factor(DetectMat.STEEL)
			if steel_f > 0.001:
				var tip_len: float = length * steel_f
				var tip_r: float = radius * maxf(sqrt(steel_f), 0.45)
				for tip_pt in _cylinder_rod_tip_points(other):
					if _point_in_cylinder(tip_pt as Vector3, face_w, axis_w, tip_len, tip_r):
						return true
	return false


static func _target_corners_world(el) -> Array:
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var h: Vector3 = _target_half_extents_local(el)
	var out: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
	return out


## Наконечник / конец штока за передней крышкой (сталь/хром) — отдельно от Al-корпуса.
static func _cylinder_rod_tip_points(el) -> Array:
	if el == null or str(el.kind) != "cylinder":
		return []
	var rod_mode: String = str(el.rod_mode) if "rod_mode" in el else ""
	if rod_mode == "rodless":
		return []
	var bore_m: float = maxf(float(el.bore_mm), 20.0) * 0.001
	var stroke_m: float = maxf(float(el.stroke_mm), 40.0) * 0.001
	var style: String = str(el.body_style) if "body_style" in el else ""
	var cap_l: float = maxf(bore_m * (0.38 if style == "compact" else 0.72), 0.012)
	var barrel_l: float = stroke_m + maxf(bore_m * (0.18 if style == "compact" else 0.40), 0.01)
	var half_body: float = (cap_l * 2.0 + barrel_l) * 0.5
	var rod_r: float = maxf(float(el.rod_mm), 8.0) * 0.0005
	# Как в iso_cylinder: tip ≈ front_face + bore*0.55 (+ наконечник).
	var tip_x: float = half_body + bore_m * 0.55 + rod_r * 2.0
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var out: Array = []
	out.append(xf * Vector3(tip_x, 0.0, 0.0))
	out.append(xf * Vector3(tip_x - rod_r * 1.5, 0.0, 0.0))
	out.append(xf * Vector3(tip_x, rod_r, 0.0))
	out.append(xf * Vector3(tip_x, -rod_r, 0.0))
	out.append(xf * Vector3(tip_x, 0.0, rod_r))
	out.append(xf * Vector3(tip_x, 0.0, -rod_r))
	return out


## Ближайшая точка корпуса цели к query (учёт длины ПЦ / арматуры).
static func _closest_on_target(el, query: Vector3) -> Vector3:
	var xf: Transform3D = Transform3D(el.world_basis, el.world_pos)
	var half: Vector3 = _target_half_extents_local(el)
	var local_q: Vector3 = xf.affine_inverse() * query
	var clamped := Vector3(
		clampf(local_q.x, -half.x, half.x),
		clampf(local_q.y, -half.y, half.y),
		clampf(local_q.z, -half.z, half.z)
	)
	return xf * clamped


static func _target_half_extents_local(el) -> Vector3:
	match str(el.kind):
		"cylinder":
			# Габарит как в iso_cylinder: профиль/труба + крышки (не «тонкий» AABB по bore/2).
			var bore_m: float = maxf(float(el.bore_mm), 20.0) * 0.001
			var stroke_m: float = maxf(float(el.stroke_mm), 40.0) * 0.001
			var style: String = str(el.body_style) if "body_style" in el else ""
			var rod_mode: String = str(el.rod_mode) if "rod_mode" in el else ""
			var rodless: bool = rod_mode == "rodless"
			var roundish: bool = style == "round" or style == "tierod" or rodless
			var cap_l: float = maxf(bore_m * (0.45 if rodless else (0.38 if style == "compact" else 0.72)), 0.012)
			var barrel_l: float = stroke_m + maxf(bore_m * (0.25 if rodless else (0.18 if style == "compact" else 0.40)), 0.01)
			var half_len: float = (cap_l * 2.0 + barrel_l) * 0.5
			var half_yz: float
			if roundish:
				half_yz = bore_m * (0.58 if rodless else 0.62) * 1.08
			else:
				# Профильный корпус: half ≈ profile/2 (profile = bore×1.48).
				var profile: float = bore_m * (1.15 if style == "compact" else 1.48)
				half_yz = profile * 0.52
			return Vector3(half_len, half_yz, half_yz)
		"rotary_cylinder", "air_motor":
			var r: float = maxf(float(el.bore_mm), 30.0) * 0.001 * 0.5
			return Vector3(r * 1.2, r, r)
		"valve":
			return Vector3(0.06, 0.035, 0.04)
		"accessory", "source":
			return Vector3(0.04, 0.03, 0.03)
		"junction":
			return Vector3(0.02, 0.015, 0.015)
		"opto_tip":
			var tip_r: float = maxf(float(el.body_od_mm), 6.0) * 0.0005
			var tip_l: float = maxf(float(el.stroke_mm), 20.0) * 0.0005
			return Vector3(tip_l, tip_r, tip_r)
		"sensor":
			var sr: float = maxf(float(el.body_od_mm), 12.0) * 0.0005
			var sl: float = maxf(float(el.stroke_mm), 40.0) * 0.0005
			return Vector3(sl, sr, sr)
		_:
			return Vector3(0.03, 0.03, 0.03)


static func _point_in_cylinder(p: Vector3, face: Vector3, axis: Vector3, length: float, radius: float) -> bool:
	var d: Vector3 = p - face
	var along: float = d.dot(axis)
	if along < -0.002 or along > length + 0.002:
		return false
	var radial: Vector3 = d - axis * along
	return radial.length() <= radius + 0.002


static func zone_viz_color(el) -> Color:
	if el == null:
		return Color(0.5, 0.5, 0.55, 0.18)
	if bool(el.sensor_active) and not bool(el.sensor_powered):
		# Серый: нет питания; чуть ярче, если цель в зоне (видна готовность).
		if bool(el.sensor_target):
			return Color(0.7, 0.55, 0.2, 0.22)
		return Color(0.45, 0.45, 0.48, 0.15)
	if bool(el.pressed) or bool(el.lit):
		return Color(0.15, 0.95, 0.35, 0.28)
	return Color(0.2, 0.75, 0.95, 0.22)


static func magnet_field_viz_color(active: bool = false) -> Color:
	if active:
		return Color(0.95, 0.35, 0.85, 0.26)
	return Color(0.75, 0.25, 0.7, 0.18)


## Метки срабатывания на УГО ПЦ: [{tag, x_m, t}] где t∈[0..1] вдоль хода.
## Сейчас — геркон по полю магнита поршня; другие классы — позже.
static func cylinder_stroke_triggers(circuit, cyl) -> Array:
	var out: Array = []
	if circuit == null or cyl == null or str(cyl.kind) != "cylinder":
		return out
	if not _cylinder_has_magnet(cyl):
		return out
	var stroke_m: float = maxf(float(cyl.stroke_mm), 1.0) * 0.001
	var piston0: float = _cylinder_piston0_local(cyl)
	var field: Dictionary = cylinder_magnet_field_rod_local(cyl)
	var base_len: float = float(field.get("length", 0.03))
	var radius: float = float(field.get("radius", 0.03))
	var cyl_xf: Transform3D = Transform3D(cyl.world_basis, cyl.world_pos)
	var inv: Transform3D = cyl_xf.affine_inverse()
	for el in circuit.elements:
		if el == null or str(el.kind) != "sensor":
			continue
		if str(el.sensor_class) != "reed":
			continue
		var reed_local: Vector3 = inv * (el.world_pos as Vector3)
		var radial: float = Vector2(reed_local.y, reed_local.z).length()
		if radial > radius + 0.002:
			continue
		var sn_axial: float = maxf(float(el.sense_range_mm), 0.0) * 0.001
		var half_l: float = maxf(base_len, sn_axial * 2.0) * 0.5
		# Центр окна: магнит в reed_local.x → x = reed_x − piston0.
		var x_c: float = reed_local.x - piston0
		var x0: float = x_c - half_l
		var x1: float = x_c + half_l
		if x1 < -0.001 or x0 > stroke_m + 0.001:
			continue
		var mark_x: float = clampf(x_c, 0.0, stroke_m)
		# Если номинал вне хода — середина пересечения окна с [0..stroke].
		if x_c < 0.0 or x_c > stroke_m:
			var a: float = maxf(x0, 0.0)
			var b: float = minf(x1, stroke_m)
			if b - a < 0.0005:
				continue
			mark_x = (a + b) * 0.5
		var t: float = clampf(mark_x / stroke_m, 0.0, 1.0)
		var tag: String = str(el.tag)
		if tag == "":
			tag = "SQ"
		out.append({"tag": tag, "x_m": mark_x, "t": t, "sensor_id": int(el.id)})
	return out
