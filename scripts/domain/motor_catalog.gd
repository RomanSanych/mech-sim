class_name MotorCatalog
extends RefCounted
## Пневмомоторы: учебные типоряды по каталогам GAST / Deprag / Atlas (@≈6–7 бар).
## AM-ряд — rotary vane; gear — учебный шестерённый с теми же якорями stall.
## Turbine — те же якоря stall (учебный размер), rpm/Qn — характер турбины
## (выше холостые, Qn ≈0.6× лопастного: Deprag/Atlas ~+40% КПД vs vane).
## Таблица stall→rpm/Qn — внутренний источник подстановки; не пункт меню «класс».

const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")

## Опорный stall 2AM — масштаб 3D = 1.0.
const STALL_REF_NM := 3.05
## Опорные холостые для ANGLE_VIS (учебный масштаб угла 3D/УГО).
const ANGLE_VIS_REF_RPM := 4000.0
const ANGLE_VIS_BASE := 0.07


static func sizes_gear() -> Array:
	return ["1am", "2am", "4am"]


static func sizes_vane() -> Array:
	# GAST lubricated rotary vane AM (те же якоря stall, что у ряда gear).
	return ["1am", "2am", "4am"]


static func sizes_turbine() -> Array:
	# Учебный ряд stall как у AM; rpm/Qn — турбинная кривая (Deprag/Atlas КПД).
	return ["1am", "2am", "4am"]


static func free_rpm_gear(size_id: String) -> float:
	match size_id:
		"1am":
			return 10000.0
		"2am":
			return 3000.0
		"4am":
			return 3000.0
		_:
			return 3000.0


static func free_rpm_vane(size_id: String) -> float:
	# Холостые у лопастных чуть выше типичного шестерённого того же stall (ротор без зубчатой пары).
	match size_id:
		"1am":
			return 12000.0
		"2am":
			return 4000.0
		"4am":
			return 3500.0
		_:
			return 4000.0


static func free_rpm_turbine(size_id: String) -> float:
	# Турбинная ячейка: выше холостые при том же учебном stall (до редуктора).
	match size_id:
		"1am":
			return 18000.0
		"2am":
			return 12000.0
		"4am":
			return 8000.0
		_:
			return 12000.0


static func stall_nm_gear(size_id: String) -> float:
	match size_id:
		"1am":
			return 0.65
		"2am":
			return 3.05
		"4am":
			return 6.3
		_:
			return 3.05


static func stall_nm_vane(size_id: String) -> float:
	# GAST 1AM / 2AM / 4AM max torque @≈7 бар — учебный якорь @6 бар.
	return stall_nm_gear(size_id)


static func stall_nm_turbine(size_id: String) -> float:
	return stall_nm_gear(size_id)


static func flow_nl_min_gear(size_id: String) -> float:
	match size_id:
		"1am":
			return 580.0
		"2am":
			return 825.0
		"4am":
			return 2200.0
		_:
			return 825.0


static func flow_nl_min_vane(size_id: String) -> float:
	# Расход лопастного ряда чуть выше (утечки по лопастям) при том же stall.
	match size_id:
		"1am":
			return 620.0
		"2am":
			return 900.0
		"4am":
			return 2400.0
		_:
			return 900.0


static func flow_nl_min_turbine(size_id: String) -> float:
	# ≈0.6× лопастного: Deprag/Atlas — турбина до ~40% эффективнее vane.
	match size_id:
		"1am":
			return 380.0
		"2am":
			return 540.0
		"4am":
			return 1450.0
		_:
			return 540.0


static func power_kw_gear(size_id: String) -> float:
	match size_id:
		"1am":
			return 0.33
		"2am":
			return 0.68
		"4am":
			return 1.3
		_:
			return 0.68


static func power_kw_vane(size_id: String) -> float:
	return power_kw_gear(size_id)


static func power_kw_turbine(size_id: String) -> float:
	return power_kw_gear(size_id)


static func port_for_gear(size_id: String) -> String:
	match size_id:
		"1am":
			return "G1/8"
		_:
			return "G1/4"


static func port_for_vane(size_id: String) -> String:
	return port_for_gear(size_id)


static func port_for_turbine(size_id: String) -> String:
	return port_for_gear(size_id)


static func stall_min_gear() -> float:
	var lo: float = stall_nm_gear("1am")
	for sid in sizes_gear():
		lo = minf(lo, stall_nm_gear(str(sid)))
	return lo


static func stall_max_gear() -> float:
	var hi: float = stall_nm_gear("1am")
	for sid in sizes_gear():
		hi = maxf(hi, stall_nm_gear(str(sid)))
	return hi


static func stall_min_vane() -> float:
	var lo: float = stall_nm_vane("1am")
	for sid in sizes_vane():
		lo = minf(lo, stall_nm_vane(str(sid)))
	return lo


static func stall_max_vane() -> float:
	var hi: float = stall_nm_vane("1am")
	for sid in sizes_vane():
		hi = maxf(hi, stall_nm_vane(str(sid)))
	return hi


static func stall_min_turbine() -> float:
	var lo: float = stall_nm_turbine("1am")
	for sid in sizes_turbine():
		lo = minf(lo, stall_nm_turbine(str(sid)))
	return lo


static func stall_max_turbine() -> float:
	var hi: float = stall_nm_turbine("1am")
	for sid in sizes_turbine():
		hi = maxf(hi, stall_nm_turbine(str(sid)))
	return hi


static func stall_min_of(el) -> float:
	if is_turbine(el):
		return stall_min_turbine()
	if is_vane(el):
		return stall_min_vane()
	return stall_min_gear()


static func stall_max_of(el) -> float:
	if is_turbine(el):
		return stall_max_turbine()
	if is_vane(el):
		return stall_max_vane()
	return stall_max_gear()


## Ближайший размер ряда по моменту стоп (для rpm/Qn из таблицы).
static func nearest_size_by_stall(stall: float) -> String:
	return _nearest_size(stall, sizes_gear(), "gear")


static func nearest_size_by_stall_vane(stall: float) -> String:
	return _nearest_size(stall, sizes_vane(), "vane")


static func nearest_size_by_stall_turbine(stall: float) -> String:
	return _nearest_size(stall, sizes_turbine(), "turbine")


static func _nearest_size(stall: float, sizes: Array, kind: String) -> String:
	var best: String = "2am"
	var best_d: float = 1.0e9
	for sid_v in sizes:
		var sid: String = str(sid_v)
		var cat_stall: float = stall_nm_gear(sid)
		if kind == "vane":
			cat_stall = stall_nm_vane(sid)
		elif kind == "turbine":
			cat_stall = stall_nm_turbine(sid)
		var d: float = absf(cat_stall - stall)
		if d < best_d:
			best_d = d
			best = sid
	return best


static func size_id_of(el) -> String:
	if el == null:
		return "2am"
	var stall: float = float(el.torque_nm_at_6bar) if el.get("torque_nm_at_6bar") != null else 0.0
	if stall >= 0.05:
		if is_turbine(el):
			return nearest_size_by_stall_turbine(stall)
		if is_vane(el):
			return nearest_size_by_stall_vane(stall)
		return nearest_size_by_stall(stall)
	var rid: String = str(el.recipe_id) if el.get("recipe_id") != null else ""
	if rid.ends_with("1am") or rid.contains("1am"):
		return "1am"
	if rid.ends_with("4am") or rid.contains("4am"):
		return "4am"
	return "2am"


## Якорь UI: задать stall, подставить rpm/Qn из ближайшей строки каталога.
static func apply_stall_anchor(el, stall_nm_val: float) -> void:
	if el == null:
		return
	if is_turbine(el):
		_apply_stall_anchor_kind(el, stall_nm_val, "turbine")
	elif is_vane(el):
		_apply_stall_anchor_kind(el, stall_nm_val, "vane")
	else:
		_apply_stall_anchor_kind(el, stall_nm_val, "gear")


static func _apply_stall_anchor_kind(el, stall_nm_val: float, kind: String) -> void:
	var lo: float = stall_min_gear()
	var hi: float = stall_max_gear()
	if kind == "vane":
		lo = stall_min_vane()
		hi = stall_max_vane()
	elif kind == "turbine":
		lo = stall_min_turbine()
		hi = stall_max_turbine()
	el.torque_nm_at_6bar = clampf(float(stall_nm_val), lo, hi)
	el.recipe_id = ""
	var sid: String = "2am"
	if kind == "vane":
		sid = nearest_size_by_stall_vane(float(el.torque_nm_at_6bar))
		el.free_rpm = free_rpm_vane(sid)
		el.flow_nl_min = flow_nl_min_vane(sid)
	elif kind == "turbine":
		sid = nearest_size_by_stall_turbine(float(el.torque_nm_at_6bar))
		el.free_rpm = free_rpm_turbine(sid)
		el.flow_nl_min = flow_nl_min_turbine(sid)
	else:
		sid = nearest_size_by_stall(float(el.torque_nm_at_6bar))
		el.free_rpm = free_rpm_gear(sid)
		el.flow_nl_min = flow_nl_min_gear(sid)
	el.mass_kg = 0.4 + stall_nm(el) * 0.15
	el.friction_n = 0.8 + stall_nm(el) * 0.12


## Масштаб всего 3D-мотора от stall (2AM → 1.0); пропорции корпуса общие.
static func geom_scale(el) -> float:
	var stall: float = stall_nm(el)
	return clampf(pow(stall / STALL_REF_NM, 0.45), 0.55, 1.55)


static func is_gear(el) -> bool:
	return el != null and str(el.kind) == "air_motor" and str(el.rotary_class) == "gear"


static func is_vane(el) -> bool:
	return el != null and str(el.kind) == "air_motor" and str(el.rotary_class) == "vane"


static func is_turbine(el) -> bool:
	return el != null and str(el.kind) == "air_motor" and str(el.rotary_class) == "turbine"


## Учебный масштаб угла 3D/УГО: при высоких free_rpm (турбина) не стробоскоп.
## Физическая ω (tip/Qn) не меняется.
static func angle_vis_factor(el) -> float:
	var rpm: float = float(el.free_rpm) if el != null and el.get("free_rpm") != null else ANGLE_VIS_REF_RPM
	if not is_turbine(el):
		return ANGLE_VIS_BASE
	return clampf(ANGLE_VIS_BASE * (ANGLE_VIS_REF_RPM / maxf(rpm, 500.0)), 0.012, ANGLE_VIS_BASE)


static func free_omega_rad_s(el) -> float:
	var rpm: float = float(el.free_rpm) if el.get("free_rpm") != null else 3000.0
	return maxf(rpm, 60.0) * TAU / 60.0


static func stall_nm(el) -> float:
	return maxf(float(el.torque_nm_at_6bar), 0.05)


## Реверсивный ПМ: каждый порт independently muffler|fitting.
## port_5 → «in»; port_3 → «exhaust» (как R1/R2 у клапанов).
static func port_is_muffler(el, port_name: String) -> bool:
	var v: String = "fitting"
	if str(port_name) == "exhaust":
		v = str(el.port_3) if el.get("port_3") != null else "muffler"
	elif str(port_name) == "in":
		v = str(el.port_5) if el.get("port_5") != null else "fitting"
	return v != "fitting" and v != "connect" and v != "open"


static func exhaust_is_muffler(el) -> bool:
	return port_is_muffler(el, "exhaust")


static func conform(el) -> void:
	if el == null:
		return
	el.kind = "air_motor"
	if str(el.rotary_class) == "":
		el.rotary_class = "gear"
	var turbine: bool = is_turbine(el)
	var vane: bool = is_vane(el)
	var sid: String = size_id_of(el)
	if float(el.free_rpm) < 1.0:
		if turbine:
			el.free_rpm = free_rpm_turbine(sid)
		elif vane:
			el.free_rpm = free_rpm_vane(sid)
		else:
			el.free_rpm = free_rpm_gear(sid)
	if float(el.torque_nm_at_6bar) < 0.01:
		if turbine:
			el.torque_nm_at_6bar = stall_nm_turbine(sid)
		elif vane:
			el.torque_nm_at_6bar = stall_nm_vane(sid)
		else:
			el.torque_nm_at_6bar = stall_nm_gear(sid)
	else:
		var lo: float = stall_min_of(el)
		var hi: float = stall_max_of(el)
		el.torque_nm_at_6bar = clampf(float(el.torque_nm_at_6bar), lo, hi)
	if float(el.flow_nl_min) < 1.0:
		if turbine:
			el.flow_nl_min = flow_nl_min_turbine(sid)
		elif vane:
			el.flow_nl_min = flow_nl_min_vane(sid)
		else:
			el.flow_nl_min = flow_nl_min_gear(sid)
	if str(el.port_name) == "":
		if turbine:
			el.port_name = port_for_turbine(sid)
		elif vane:
			el.port_name = port_for_vane(sid)
		else:
			el.port_name = port_for_gear(sid)
	if float(el.tube_od_mm) < 1.0:
		var th: String = str(el.port_name)
		el.tube_od_mm = 8.0 if th.contains("1/4") or th.contains("G1/4") else 6.0
	if str(el.port_3) == "":
		el.port_3 = "muffler"
	if str(el.port_5) == "":
		el.port_5 = "fitting"
	el.tag_prefix = "ПМ"
	if float(el.mass_kg) < 0.05:
		el.mass_kg = 0.4 + stall_nm(el) * 0.15
	if float(el.friction_n) < 0.01:
		el.friction_n = 0.8 + stall_nm(el) * 0.12


static func port_vol_m3(el) -> float:
	# Малый объём галереи порта — как у арматуры.
	var od: float = maxf(float(el.tube_od_mm), 4.0)
	return 1.2e-6 * (od / 6.0)
