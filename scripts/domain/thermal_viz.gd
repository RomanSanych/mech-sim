class_name ThermalViz
extends RefCounted
## Учебный «тепловизор»: °C + динамика тела без «потолков ради красоты».
## Электро: P=I²R → ΔT=P·Rth (КЗ даёт сотни/тысячи °C — так и должно быть видно).
## Пневмо: в корпус идёт доля диссипации |Q|·|Δp| (большинство уносит газ), плюс F·v.
## ТС: T зоны на зонде. Шкала легенды — min/max сцены (как камера).


const T_AMB_FALLBACK := 20.0
## Только численная защита от Inf/NaN в шейдере (не учебный «потолок»).
const T_NUM_MAX := 4000.0
const TAU_BODY_S := 18.0
## Жила тонкая — греется/стынет быстрее корпуса (КЗ видно за доли секунды).
const TAU_WIRE_S := 1.0
const RANGE_FLOOR := 2.0

## Тепловое сопротивление корпус→среда, °C/Вт (порядок величины для стенда).
const RTH_WIRE_ELEC := 12.0
const RTH_DEVICE := 10.0
const RTH_SOLENOID := 22.0 # катушка компактнее → выше Rth
const RTH_CABINET := 1.8
const RTH_TUBE := 5.0
const RTH_PNEUMO_BODY := 2.8

## Доля |Q|·|Δp|, оседающая в твёрдом теле (остальное — энтальпия газа / выхлоп).
const ETA_TUBE := 0.012
const ETA_VALVE := 0.07
const ETA_ACCESS := 0.10
const ETA_SILENCER := 0.16
const ETA_CYL_THROTTLE := 0.025
const ETA_MOTOR := 0.12
const ETA_SOURCE := 0.03
const ETA_COMPRESS_WALL := 0.05
## Доля F·v, оседающая в металле/уплотнениях (остальное — газ в зазоре / воздух).
const ETA_CYL_FRIC := 0.22

## Rth частей ПЦ, °C/Вт: гильза — большой радиатор; уплотнения — локально горячие.
const RTH_CYL_BARREL := 2.2
const RTH_CYL_PISTON := 14.0
const RTH_CYL_ROD := 6.5
const RTH_CYL_CAP := 3.0
const RTH_CYL_GLAND := 20.0
const RTH_CYL_SHELL := 1.0

const CYL_PART_KEYS: Array[String] = ["barrel", "piston", "rod", "cap", "gland", "shell"]


static func ambient_c(circuit) -> float:
	if circuit == null:
		return T_AMB_FALLBACK
	var tk: float = float(circuit.gas_t) if float(circuit.gas_t) > 200.0 else (T_AMB_FALLBACK + 273.15)
	return tk - 273.15


## Палитра ironbow: тёмно-синий → красный → оранжевый → жёлтый → белый.
static func color_norm(u: float) -> Color:
	var t: float = clampf(u, 0.0, 1.0)
	var c0 := Color(0.02, 0.05, 0.32)
	var c1 := Color(0.18, 0.12, 0.55)
	var c2 := Color(0.72, 0.08, 0.22)
	var c3 := Color(0.98, 0.45, 0.05)
	var c4 := Color(1.0, 0.92, 0.35)
	var c5 := Color(1.0, 0.98, 0.92)
	if t <= 0.2:
		return c0.lerp(c1, t / 0.2)
	if t <= 0.4:
		return c1.lerp(c2, (t - 0.2) / 0.2)
	if t <= 0.6:
		return c2.lerp(c3, (t - 0.4) / 0.2)
	if t <= 0.8:
		return c3.lerp(c4, (t - 0.6) / 0.2)
	return c4.lerp(c5, (t - 0.8) / 0.2)


static func color_for_t(t_c: float, t_min: float, t_max: float) -> Color:
	var lo: float = t_min
	var hi: float = t_max
	if hi - lo < 0.05:
		hi = lo + RANGE_FLOOR
	var u: float = clampf((t_c - lo) / (hi - lo), 0.0, 1.0)
	return color_norm(u)


static func _finite_t(t_c: float, fallback: float) -> float:
	if is_nan(t_c) or is_inf(t_c):
		return fallback
	return clampf(t_c, -273.0, T_NUM_MAX)


static func _body_t_get(obj, tamb: float) -> float:
	if obj == null:
		return tamb
	var t: float = float(obj.thermal_body_c) if obj.get("thermal_body_c") != null else tamb
	if t < -200.0 or is_nan(t) or is_inf(t):
		return tamb
	return _finite_t(t, tamb)


static func _body_t_set(obj, t_c: float) -> void:
	if obj == null:
		return
	obj.thermal_body_c = _finite_t(t_c, ambient_c(null))


## Мощность электроприбора, Вт — без потолка (потери БП / катушка / лампа).
static func device_power_w(circuit, el) -> float:
	if circuit == null or el == null:
		return 0.0
	if str(el.kind) == "sensor":
		if str(el.sensor_class) == "rtd":
			return 0.0
		if bool(el.sensor_powered):
			if str(el.sensor_class) == "pressure_tx":
				return 24.0 * 0.025
			if bool(el.sensor_active):
				return 24.0 * 0.015
		return 0.0
	if str(el.kind) == "coil":
		return 2.4 if bool(el.energized) else 0.0
	if str(el.kind) != "electro":
		return 0.0
	var cls: String = str(el.electro_class)
	match cls:
		"psu":
			var i_dc: float = maxf(float(circuit.call("_psu_dc_rail_load_a", el)), 0.0)
			var v_dc: float = maxf(float(el.voltage), 0.0)
			# Потери ≈ (1/η − 1)·Pвых, η≈0.85.
			return v_dc * i_dc * (1.0 / 0.85 - 1.0)
		"rtd_meter":
			var prim = circuit.get_element(int(el.group_id))
			return 0.5 if prim != null and bool(prim.sensor_powered) else 0.0
		"lamp":
			# Номинал лампы; при КЗ ток считает жила (I²R), не этот член.
			return (float(el.voltage) if float(el.voltage) > 1.0 else 24.0) * 0.1 if bool(el.lit) else 0.0
		"relay", "timer_relay", "voltage_relay", "contactor":
			return 1.2 if bool(el.energized) else 0.0
		"solenoid_coil":
			return 2.5 if bool(el.energized) else 0.0
		"thermal":
			return 0.8 if bool(el.energized) or bool(el.closed) else 0.15
		_:
			return 0.0


static func device_rth(el) -> float:
	if el == null:
		return RTH_DEVICE
	if str(el.kind) == "coil":
		return RTH_SOLENOID
	if str(el.kind) == "electro" and str(el.electro_class) == "solenoid_coil":
		return RTH_SOLENOID
	return RTH_DEVICE


static func _element_flow_dp(circuit, el) -> Vector2:
	if circuit == null or el == null:
		return Vector2.ZERO
	var q_abs: float = 0.0
	var dp_best: float = 0.0
	var p_hi: float = 0.0
	var p_lo: float = 1.0e12
	var any_p: bool = false
	if el.get("port_press") != null and typeof(el.port_press) == TYPE_DICTIONARY:
		for pk in el.port_press.keys():
			var pp: float = float(el.port_press[pk])
			any_p = true
			p_hi = maxf(p_hi, pp)
			p_lo = minf(p_lo, pp)
			q_abs = maxf(q_abs, absf(float(circuit.port_viz_q(el, str(pk)))))
	match str(el.kind):
		"cylinder":
			q_abs = maxf(q_abs, maxf(absf(float(el.q_cap)), absf(float(el.q_rod))))
			p_hi = maxf(float(el.p_cap), float(el.p_rod))
			p_lo = minf(float(el.p_cap), float(el.p_rod))
			any_p = true
		"junction":
			q_abs = maxf(q_abs, absf(float(el.q_cap)))
			p_hi = float(el.p_cap)
			p_lo = float(el.p_cap)
			any_p = true
		"source":
			q_abs = absf(float(circuit.port_viz_q(el, "out")))
			p_hi = float(el.pressure_bar) * 1.0e5 + 101325.0
			p_lo = 101325.0
			any_p = true
	if any_p:
		dp_best = maxf(p_hi - p_lo, 0.0)
	return Vector2(q_abs, dp_best)


## Мощность в твёрдое тело от пневмопроцессов, Вт.
static func pneumo_heat_power_w(circuit, el) -> float:
	if circuit == null or el == null:
		return 0.0
	var kind: String = str(el.kind)
	if kind in ["electro", "coil", "rail"]:
		return 0.0
	if kind == "sensor":
		var scls: String = str(el.sensor_class)
		if scls != "pressure_switch" and scls != "pressure_tx":
			return 0.0
	var fd: Vector2 = _element_flow_dp(circuit, el)
	var q_abs: float = fd.x
	var dp: float = fd.y
	var p_diss: float = absf(q_abs) * absf(dp) # Вт в газе/дросселе
	var p_w: float = 0.0
	match kind:
		"cylinder":
			# Сумма по частям — для совместимости; визуал красит по thermal_parts.
			var parts_p: Dictionary = cylinder_part_powers_w(circuit, el)
			for pk in parts_p.keys():
				p_w += float(parts_p[pk])
		"valve":
			p_w += ETA_VALVE * p_diss
			if bool(el.command_left) and ("solenoid" in str(el.op_left)):
				p_w += 2.5
			if bool(el.command_right) and ("solenoid" in str(el.op_right)):
				p_w += 2.5
			for ex_port in ["3", "5"]:
				var qex: float = float(circuit.open_port_viz_q(el, ex_port))
				if qex < -1.0e-8:
					var pex: float = float(el.port_press.get(ex_port, 101325.0)) \
							if el.get("port_press") != null else 101325.0
					p_w += ETA_SILENCER * absf(qex) * maxf(pex - 101325.0, 0.0)
		"accessory":
			var acls: String = str(el.accessory_class)
			var eta: float = ETA_ACCESS
			if acls in ["silencer", "muffler", "quick_exhaust"]:
				eta = ETA_SILENCER
			p_w += eta * p_diss
		"air_motor":
			p_w += ETA_MOTOR * p_diss
		"rotary_cylinder":
			p_w += ETA_CYL_THROTTLE * p_diss
		"junction":
			p_w += ETA_TUBE * p_diss
		"source":
			p_w += ETA_SOURCE * p_diss
		"sensor":
			p_w += ETA_ACCESS * 0.5 * p_diss
		_:
			p_w += ETA_TUBE * p_diss
	if is_nan(p_w) or is_inf(p_w):
		return 0.0
	return maxf(p_w, 0.0)


static func element_heat_power_w(circuit, el) -> float:
	return device_power_w(circuit, el) + pneumo_heat_power_w(circuit, el)


static func element_rth(el) -> float:
	if el == null:
		return RTH_DEVICE
	var kind: String = str(el.kind)
	if kind in ["cylinder", "valve", "accessory", "junction", "rotary_cylinder", "air_motor", "source"]:
		return RTH_PNEUMO_BODY
	if kind == "sensor" and str(el.sensor_class) in ["pressure_switch", "pressure_tx"]:
		return RTH_PNEUMO_BODY
	return device_rth(el)


static func element_temp_c(circuit, el) -> float:
	var tamb: float = ambient_c(circuit)
	if el == null:
		return tamb
	if str(el.kind) == "sensor" and str(el.sensor_class) == "rtd":
		return float(el.temperature_c)
	# Для ПЦ «корпус» в попапе/шкале = гильза (не max уплотнений).
	if str(el.kind) == "cylinder":
		return part_temp_c(el, "barrel", tamb)
	return _body_t_get(el, tamb)


## Мощности нагрева частей ПЦ, Вт (трение → уплотнения; дроссель → крышки; сжатие → гильза).
static func cylinder_part_powers_w(circuit, el) -> Dictionary:
	var out: Dictionary = {}
	for k in CYL_PART_KEYS:
		out[k] = 0.0
	if circuit == null or el == null or str(el.kind) != "cylinder":
		return out
	var fd: Vector2 = _element_flow_dp(circuit, el)
	var p_throttle: float = ETA_CYL_THROTTLE * absf(fd.x) * absf(fd.y)
	var p_fric: float = ETA_CYL_FRIC * maxf(float(el.friction_n), 0.0) * absf(float(el.v))
	var a_bore: float = PI * pow(float(el.bore_mm) * 0.001 * 0.5, 2.0)
	var p_comp: float = ETA_COMPRESS_WALL * absf(float(el.p_cap) - float(el.p_rod)) \
			* a_bore * absf(float(el.v))
	# Распределение: трение в основном на поршневых кольцах и сальнике штока.
	out["gland"] = 0.40 * p_fric + 0.05 * p_throttle
	out["piston"] = 0.42 * p_fric + 0.20 * p_comp
	out["rod"] = 0.10 * p_fric + 0.08 * p_throttle
	out["barrel"] = 0.08 * p_fric + 0.55 * p_comp + 0.20 * p_throttle
	out["cap"] = 0.55 * p_throttle + 0.25 * p_comp
	out["shell"] = 0.0
	for k in CYL_PART_KEYS:
		var pw: float = float(out[k])
		if is_nan(pw) or is_inf(pw):
			out[k] = 0.0
		else:
			out[k] = maxf(pw, 0.0)
	return out


static func cylinder_part_rth(part: String) -> float:
	match part:
		"barrel":
			return RTH_CYL_BARREL
		"piston":
			return RTH_CYL_PISTON
		"rod":
			return RTH_CYL_ROD
		"cap":
			return RTH_CYL_CAP
		"gland":
			return RTH_CYL_GLAND
		"shell":
			return RTH_CYL_SHELL
		_:
			return RTH_PNEUMO_BODY


static func part_temp_c(el, part: String, tamb: float = T_AMB_FALLBACK) -> float:
	if el == null:
		return tamb
	if el.get("thermal_parts") != null and typeof(el.thermal_parts) == TYPE_DICTIONARY:
		var d: Dictionary = el.thermal_parts
		if d.has(part):
			return _finite_t(float(d[part]), tamb)
	if part == "barrel":
		return _body_t_get(el, tamb)
	return _body_t_get(el, tamb)


static func cylinder_part_temps_c(circuit, el) -> Dictionary:
	var tamb: float = ambient_c(circuit)
	var out: Dictionary = {}
	for k in CYL_PART_KEYS:
		out[k] = part_temp_c(el, k, tamb)
	return out


static func _advance_cylinder_parts(el, circuit, tamb: float, a: float, snap: bool) -> void:
	var powers: Dictionary = cylinder_part_powers_w(circuit, el)
	if el.thermal_parts == null or typeof(el.thermal_parts) != TYPE_DICTIONARY:
		el.thermal_parts = {}
	var d: Dictionary = el.thermal_parts
	for k in CYL_PART_KEYS:
		var t_ss: float = _finite_t(tamb + float(powers[k]) * cylinder_part_rth(k), tamb)
		var t_cur: float = tamb
		if d.has(k):
			t_cur = _finite_t(float(d[k]), tamb)
		elif float(el.thermal_body_c) > -200.0 and k == "barrel":
			t_cur = _body_t_get(el, tamb)
		if snap or not d.has(k):
			d[k] = t_ss
		else:
			d[k] = lerpf(t_cur, t_ss, a)
	el.thermal_parts = d
	# Корпус для совместимости = гильза.
	_body_t_set(el, float(d.get("barrel", tamb)))


## Мощность нагрева жилы, Вт. Электро: I²R без потолка тока (КЗ видно).
static func wire_heat_power_w(circuit, wire) -> float:
	if circuit == null or wire == null:
		return 0.0
	var ea = circuit.get_element(int(wire.a_id))
	if ea == null:
		return 0.0
	var domain: String = str(circuit.port_domain(ea, str(wire.a_port)))
	if domain == "optic":
		return 0.0
	if domain == "electric":
		var i_a: float = maxf(float(circuit.call("_electro_wire_current_a", wire)), 0.0)
		if i_a < 1.0e-9:
			return 0.0
		var len_m: float = maxf(float(wire.length_m), 0.0)
		if len_m < 0.01 and circuit.has_method("_wire_path_length_m"):
			len_m = maxf(float(circuit.call("_wire_path_length_m", wire)), 0.05)
		len_m = maxf(len_m, 0.02)
		# id_mm у электро — сечение мм².
		var sec: float = maxf(float(wire.id_mm), 0.05)
		var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
		var r_ohm: float = maxf(Rtd.lead_ohm(len_m, sec), 1.0e-6)
		var p_w: float = i_a * i_a * r_ohm
		if is_nan(p_w) or is_inf(p_w):
			return 0.0
		return p_w
	# Пневмотрубка: доля диссипации в стенку.
	var q: float = absf(float(wire.flow_vis))
	if q < 1.0e-9:
		q = absf(float(wire.flow_m3s))
	if q < 1.0e-12:
		return 0.0
	var eb = circuit.get_element(int(wire.b_id))
	var dp: float = 0.0
	if ea != null and eb != null:
		dp = absf(float(circuit.element_viz_pressure(ea)) - float(circuit.element_viz_pressure(eb)))
	# Если концы «равны» в viz — оценка потерь по длине ~ доля избытка в трубке.
	if dp < 1.0e3:
		dp = maxf(float(wire.pressure) - 101325.0, 0.0) * 0.04
	var p_w2: float = ETA_TUBE * q * dp
	if is_nan(p_w2) or is_inf(p_w2):
		return 0.0
	return maxf(p_w2, 0.0)


static func wire_rth(circuit, wire) -> float:
	if circuit == null or wire == null:
		return RTH_TUBE
	var ea = circuit.get_element(int(wire.a_id))
	if ea == null:
		return RTH_TUBE
	var domain: String = str(circuit.port_domain(ea, str(wire.a_port)))
	if domain == "electric":
		# Тонкое сечение → хуже охлаждение (выше Rth) — КЗ на 0.5 мм² страшнее.
		var sec: float = maxf(float(wire.id_mm), 0.05)
		return RTH_WIRE_ELEC * (1.5 / sqrt(sec))
	return RTH_TUBE


static func wire_temp_c(circuit, wire) -> float:
	var tamb: float = ambient_c(circuit)
	if wire == null:
		return tamb
	return _body_t_get(wire, tamb)


static func cabinet_shell_temp_c(circuit) -> float:
	var tamb: float = ambient_c(circuit)
	if circuit == null:
		return tamb
	var p_sum: float = 0.0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_mount) != "din" and str(el.electro_mount) != "door":
			continue
		if str(el.member_role) == "contact":
			continue
		p_sum += device_power_w(circuit, el)
	return _finite_t(tamb + p_sum * RTH_CABINET * 0.25, tamb)


static func _steady_element_t(circuit, el, tamb: float) -> float:
	if el == null:
		return tamb
	if str(el.kind) == "sensor" and str(el.sensor_class) == "rtd":
		return float(el.temperature_c)
	var p_w: float = element_heat_power_w(circuit, el)
	return _finite_t(tamb + p_w * element_rth(el), tamb)


static func _steady_wire_t(circuit, wire, tamb: float) -> float:
	if wire == null:
		return tamb
	var p_w: float = wire_heat_power_w(circuit, wire)
	return _finite_t(tamb + p_w * wire_rth(circuit, wire), tamb)


static func advance(circuit, dt: float, snap: bool = false) -> void:
	if circuit == null:
		return
	if dt <= 0.0 and not snap:
		return
	var tamb: float = ambient_c(circuit)
	var a: float = 1.0 if snap else (1.0 - exp(-dt / TAU_BODY_S))
	var a_w: float = 1.0 if snap else (1.0 - exp(-dt / TAU_WIRE_S))
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) == "sensor" and str(el.sensor_class) == "rtd":
			continue
		if str(el.kind) == "electro" and str(el.member_role) == "contact":
			continue
		if str(el.kind) == "cylinder":
			_advance_cylinder_parts(el, circuit, tamb, a, snap)
			continue
		var t_ss: float = _steady_element_t(circuit, el, tamb)
		if float(el.thermal_body_c) < -200.0 or snap:
			_body_t_set(el, t_ss)
		else:
			_body_t_set(el, lerpf(_body_t_get(el, tamb), t_ss, a))
	for wire in circuit.wires:
		if wire == null:
			continue
		var t_ss_w: float = _steady_wire_t(circuit, wire, tamb)
		# При КЗ — почти мгновенно к стационару (тонкая жила, огромный I²R).
		var aw: float = a_w
		if not snap and circuit != null and bool(circuit.electro_short) \
				and float(circuit.electro_fault_a) > 10.0:
			aw = 1.0 - exp(-dt / 0.25)
		if float(wire.thermal_body_c) < -200.0 or snap:
			_body_t_set(wire, t_ss_w)
		else:
			_body_t_set(wire, lerpf(_body_t_get(wire, tamb), t_ss_w, aw))


static func scene_range_c(circuit) -> Dictionary:
	var tamb: float = ambient_c(circuit)
	var t_min: float = tamb
	var t_max: float = tamb
	var any: bool = false
	if circuit == null:
		return {"min": tamb, "max": tamb + RANGE_FLOOR, "ambient": tamb}
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) == "electro" and str(el.member_role) == "contact":
			continue
		if str(el.kind) == "cylinder":
			var parts: Dictionary = cylinder_part_temps_c(circuit, el)
			for pk in parts.keys():
				var tp: float = float(parts[pk])
				if not any:
					t_min = tp
					t_max = tp
					any = true
				else:
					t_min = minf(t_min, tp)
					t_max = maxf(t_max, tp)
			continue
		var t: float = element_temp_c(circuit, el)
		if not any:
			t_min = t
			t_max = t
			any = true
		else:
			t_min = minf(t_min, t)
			t_max = maxf(t_max, t)
	for wire in circuit.wires:
		if wire == null:
			continue
		var tw: float = wire_temp_c(circuit, wire)
		if not any:
			t_min = tw
			t_max = tw
			any = true
		else:
			t_min = minf(t_min, tw)
			t_max = maxf(t_max, tw)
	var t_cab: float = cabinet_shell_temp_c(circuit)
	if any:
		t_min = minf(t_min, t_cab)
		t_max = maxf(t_max, t_cab)
	else:
		t_min = t_cab
		t_max = t_cab
	if t_max - t_min < RANGE_FLOOR:
		var mid: float = 0.5 * (t_min + t_max)
		t_min = mid - 0.5 * RANGE_FLOOR
		t_max = mid + 0.5 * RANGE_FLOOR
	return {"min": t_min, "max": t_max, "ambient": tamb}
