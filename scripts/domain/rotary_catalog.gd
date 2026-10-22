class_name RotaryCatalog
extends RefCounted
## Поворотные ПЦ: типоряды по Festo DRQ (rack) / DSM (vane).
## Не SKU-picker — таблицы size → момент / порт / угол.

static func bores_rack() -> Array:
	return [16, 20, 25, 32, 40, 50, 63, 80, 100]


static func bores_vane() -> Array:
	# Festo DSM sizes.
	return [6, 8, 10, 12, 16, 25, 32, 40, 63]


static func angles_rack() -> Array:
	return [90, 180, 270, 360]


static func angles_vane() -> Array:
	return [90, 180, 270]


## Теоретический момент @6 бар (Н·м), ряд близкий к DRQ.
static func torque_at_6bar(bore_mm: float) -> float:
	var table := {
		16: 1.0,
		20: 1.8,
		25: 3.2,
		32: 5.5,
		40: 9.0,
		50: 15.0,
		63: 25.0,
		80: 42.0,
		100: 70.0,
	}
	var b: int = _nearest_bore(bore_mm, bores_rack())
	return float(table.get(b, 9.0))


## Момент @6 бар (Н·м), ряд близкий к Festo DSM (одинарная лопасть).
static func torque_vane_at_6bar(size_mm: float) -> float:
	var table := {
		6: 0.15,
		8: 0.35,
		10: 0.85,
		12: 1.25,
		16: 2.5,
		25: 5.0,
		32: 10.0,
		40: 20.0,
		63: 40.0,
	}
	var b: int = _nearest_bore(size_mm, bores_vane())
	return float(table.get(b, 10.0))


static func port_for_bore(bore_mm: float) -> String:
	var b: int = _nearest_bore(bore_mm, bores_rack())
	if b <= 25:
		return "G1/8"
	if b <= 50:
		return "G1/4"
	if b <= 80:
		return "G3/8"
	return "G1/2"


static func port_for_vane(size_mm: float) -> String:
	var b: int = _nearest_bore(size_mm, bores_vane())
	if b <= 16:
		return "M5"
	if b <= 40:
		return "G1/8"
	return "G1/4"


static func pinion_radius_m(bore_mm: float) -> float:
	# Учебный радиус делительной окружности шестерни.
	return clampf(float(bore_mm) * 0.35 * 0.001, 0.004, 0.035)


## Радиус камеры лопастного DSM (м) по типоразмеру.
static func vane_chamber_r_m(size_mm: float) -> float:
	return clampf(float(size_mm) * 0.001 * 0.88, 0.005, 0.055)


static func vane_shaft_r_m(size_mm: float) -> float:
	return clampf(float(size_mm) * 0.001 * 0.22, 0.002, 0.014)


static func vane_height_m(size_mm: float) -> float:
	return clampf(float(size_mm) * 0.001 * 0.95, 0.008, 0.060)


static func piston_area_m2(bore_mm: float) -> float:
	var r: float = float(bore_mm) * 0.0005
	return PI * r * r


static func is_vane(el) -> bool:
	return el != null and str(el.rotary_class) == "vane"


static func conform(el) -> void:
	if el == null:
		return
	if is_vane(el):
		_conform_vane(el)
	else:
		_conform_rack(el)


static func _conform_rack(el) -> void:
	var b: int = _nearest_bore(float(el.bore_mm), bores_rack())
	el.bore_mm = float(b)
	var ang: float = float(el.angle_max_deg)
	var best_a: float = 180.0
	var best_d: float = 1.0e9
	for a in angles_rack():
		var d: float = absf(float(a) - ang)
		if d < best_d:
			best_d = d
			best_a = float(a)
	el.angle_max_deg = best_a
	el.torque_nm_at_6bar = torque_at_6bar(el.bore_mm)
	el.port_name = port_for_bore(el.bore_mm)
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	if str(el.fitting_id) == "" or float(el.tube_od_mm) < 1.0:
		TubeFit.apply_armature_od(el, 8.0 if b >= 40 else 6.0)
	el.angle = clampf(float(el.angle), 0.0, deg_to_rad(el.angle_max_deg))
	el.mass_kg = clampf(0.15 + float(b) * 0.012, 0.2, 4.0)
	el.friction_n = clampf(2.0 + float(b) * 0.08, 2.0, 20.0)
	el.order_code = "ППЦ-%d-%d" % [b, int(el.angle_max_deg)]
	if str(el.rotary_class) == "":
		el.rotary_class = "rack_pinion"
	if str(el.tag_prefix) == "" or str(el.tag_prefix) == "E":
		el.tag_prefix = "ППЦ"


static func _conform_vane(el) -> void:
	var b: int = _nearest_bore(float(el.bore_mm), bores_vane())
	el.bore_mm = float(b)
	var ang: float = float(el.angle_max_deg)
	var best_a: float = 180.0
	var best_d: float = 1.0e9
	for a in angles_vane():
		var d: float = absf(float(a) - ang)
		if d < best_d:
			best_d = d
			best_a = float(a)
	el.angle_max_deg = best_a
	el.torque_nm_at_6bar = torque_vane_at_6bar(el.bore_mm)
	el.port_name = port_for_vane(el.bore_mm)
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od: float = 6.0 if b <= 40 else 8.0
	if b <= 16:
		od = 4.0
	if str(el.fitting_id) == "" or float(el.tube_od_mm) < 1.0:
		TubeFit.apply_armature_od(el, od)
	el.angle = clampf(float(el.angle), 0.0, deg_to_rad(el.angle_max_deg))
	el.mass_kg = clampf(0.08 + float(b) * 0.018, 0.12, 3.5)
	el.friction_n = clampf(1.2 + float(b) * 0.06, 1.0, 18.0)
	el.order_code = "ППЦ-Л-%d-%d" % [b, int(el.angle_max_deg)]
	el.rotary_class = "vane"
	if str(el.tag_prefix) == "" or str(el.tag_prefix) == "E":
		el.tag_prefix = "ППЦ"


static func _nearest_bore(bore_mm: float, list: Array) -> int:
	var best: int = int(list[0])
	var best_d: float = 1.0e9
	for key in list:
		var dist: float = absf(float(key) - bore_mm)
		if dist < best_d:
			best_d = dist
			best = int(key)
	return best
