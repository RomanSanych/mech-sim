class_name SensorCatalog
extends RefCounted
## Каталожные типоразмеры БВ (индуктивные / ёмкостные M8…M30; герконы Т-паз / тяга).
## УЗ: диапазон min…max + analog_kind (Pepperl+Fuchs / SICK / Banner-класс).

const SensorSig = preload("res://scripts/domain/sensor_signal.gd")


static func inductive_sizes() -> Array:
	return [
		{"label": "M8 · Sn 2 мм", "body_od_mm": 8.0, "sense_range_mm": 2.0, "hysteresis_mm": 0.2, "body_len_mm": 45.0},
		{"label": "M12 · Sn 4 мм", "body_od_mm": 12.0, "sense_range_mm": 4.0, "hysteresis_mm": 0.4, "body_len_mm": 50.0},
		{"label": "M18 · Sn 8 мм", "body_od_mm": 18.0, "sense_range_mm": 8.0, "hysteresis_mm": 0.8, "body_len_mm": 60.0},
		{"label": "M30 · Sn 15 мм", "body_od_mm": 30.0, "sense_range_mm": 15.0, "hysteresis_mm": 1.5, "body_len_mm": 70.0},
	]


## Оптический усилитель с выносным оптоволокном (Lanbao FD3 / Festo SOE-класс).
## Sn — диффузный номинал по белой карте; барьер/рефлектор — длиннее (см. SensorDetection).
static func optical_sizes() -> Array:
	return optical_fiber_sizes()


static func optical_fiber_sizes() -> Array:
	return [
		{"label": "FD3 · Sn 100 мм", "body_od_mm": 30.0, "sense_range_mm": 100.0, "hysteresis_mm": 5.0, "body_len_mm": 70.0, "optical_form": "fiber"},
		{"label": "FD3 · Sn 200 мм", "body_od_mm": 30.0, "sense_range_mm": 200.0, "hysteresis_mm": 8.0, "body_len_mm": 70.0, "optical_form": "fiber"},
	]


## Компактный цилиндрический оптический (диффуз/рефлектор, без волокна). Meandr / LANBAO M18-класс.
static func optical_compact_sizes() -> Array:
	return [
		{"label": "M12 · Sn 40 мм", "body_od_mm": 12.0, "sense_range_mm": 40.0, "hysteresis_mm": 2.0, "body_len_mm": 55.0, "optical_form": "compact"},
		{"label": "M18 · Sn 100 мм", "body_od_mm": 18.0, "sense_range_mm": 100.0, "hysteresis_mm": 5.0, "body_len_mm": 65.0, "optical_form": "compact"},
		{"label": "M30 · Sn 200 мм", "body_od_mm": 30.0, "sense_range_mm": 200.0, "hysteresis_mm": 8.0, "body_len_mm": 75.0, "optical_form": "compact"},
	]


## Ёмкостные цилиндрические (SICK CM / Omron E2K-класс, non-flush).
## Sn — номинал по воде / сильному диэлектрику; пластик/металл — через capacitive_range_factor.
static func capacitive_sizes() -> Array:
	return [
		{"label": "M12 · Sn 4 мм", "body_od_mm": 12.0, "sense_range_mm": 4.0, "hysteresis_mm": 0.4, "body_len_mm": 55.0},
		{"label": "M18 · Sn 8 мм", "body_od_mm": 18.0, "sense_range_mm": 8.0, "hysteresis_mm": 0.8, "body_len_mm": 65.0},
		{"label": "M18 · Sn 12 мм", "body_od_mm": 18.0, "sense_range_mm": 12.0, "hysteresis_mm": 1.2, "body_len_mm": 65.0},
		{"label": "M30 · Sn 15 мм", "body_od_mm": 30.0, "sense_range_mm": 15.0, "hysteresis_mm": 1.5, "body_len_mm": 75.0},
	]


## Ультразвуковые аналоговые (Pepperl+Fuchs UB / SICK UM / Banner QT-класс).
## sense_min_mm — мёртвая зона; sense_range_mm — конец измерительного диапазона.
static func ultrasonic_sizes() -> Array:
	return [
		{
			"label": "M18 · 50…500 мм · 0–10 В",
			"body_od_mm": 18.0,
			"sense_min_mm": 50.0,
			"sense_range_mm": 500.0,
			"hysteresis_mm": 5.0,
			"body_len_mm": 70.0,
			"analog_kind": "0_10v",
		},
		{
			"label": "M30 · 100…1000 мм · 0–10 В",
			"body_od_mm": 30.0,
			"sense_min_mm": 100.0,
			"sense_range_mm": 1000.0,
			"hysteresis_mm": 10.0,
			"body_len_mm": 85.0,
			"analog_kind": "0_10v",
		},
		{
			"label": "M30 · 200…2000 мм · 4–20 мА",
			"body_od_mm": 30.0,
			"sense_min_mm": 200.0,
			"sense_range_mm": 2000.0,
			"hysteresis_mm": 20.0,
			"body_len_mm": 90.0,
			"analog_kind": "4_20ma",
		},
	]


## Реле давления без шкалы (Festo PEV / мембрана ROSMA RD-класс).
## Пассивный сухой контакт от деформации мембраны/сильфона — без Uпит головки.
## set = давление включения (бар изб.); hyst = дифференциал отпускания вниз.
static func pressure_switch_sizes() -> Array:
	return [
		{
			"label": "PEV · 1…10 бар",
			"range_min_bar": 1.0,
			"range_max_bar": 10.0,
			"set_pressure_bar": 2.0,
			"hysteresis_bar": 0.4,
			"body_od_mm": 40.0,
			"body_len_mm": 70.0,
		},
		{
			"label": "Мембрана · 0.2…6 бар",
			"range_min_bar": 0.2,
			"range_max_bar": 6.0,
			"set_pressure_bar": 1.5,
			"hysteresis_bar": 0.25,
			"body_od_mm": 36.0,
			"body_len_mm": 65.0,
		},
		{
			"label": "Низкое · 0.05…1 бар",
			"range_min_bar": 0.05,
			"range_max_bar": 1.0,
			"set_pressure_bar": 0.4,
			"hysteresis_bar": 0.08,
			"body_od_mm": 36.0,
			"body_len_mm": 60.0,
		},
	]


static func nearest_pressure_switch_index(range_max_bar: float) -> int:
	var best_i: int = 0
	var best_d: float = 1.0e9
	var rows: Array = pressure_switch_sizes()
	for i in rows.size():
		var d: float = absf(float((rows[i] as Dictionary).get("range_max_bar", 10.0)) - range_max_bar)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_pressure_switch_size(el, index: int) -> void:
	var rows: Array = pressure_switch_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 40.0))
	el.stroke_mm = float(row.get("body_len_mm", 70.0))
	el.sense_range_mm = float(row.get("range_max_bar", 10.0)) # max шкалы уставки, бар
	el.sense_min_mm = float(row.get("range_min_bar", 0.2)) # min шкалы, бар
	el.set_pressure_bar = float(row.get("set_pressure_bar", 2.0))
	if "hysteresis_bar" in el:
		el.hysteresis_bar = float(row.get("hysteresis_bar", 0.4))
	el.sensor_active = false
	el.output_type = "contact"


static func conform_pressure_switch(el) -> void:
	if el == null:
		return
	el.sensor_active = false
	el.output_type = "contact"
	var rmax: float = float(el.sense_range_mm) if float(el.sense_range_mm) > 0.05 else 10.0
	var idx: int = nearest_pressure_switch_index(rmax)
	if float(el.sense_range_mm) < 0.05 or float(el.body_od_mm) < 1.0:
		apply_pressure_switch_size(el, idx)
		return
	var row: Dictionary = pressure_switch_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 40.0))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 70.0))
	if float(el.sense_min_mm) < 0.001:
		el.sense_min_mm = float(row.get("range_min_bar", 0.2))
	if "hysteresis_bar" in el and float(el.hysteresis_bar) < 0.001:
		el.hysteresis_bar = float(row.get("hysteresis_bar", 0.4))
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	el.set_pressure_bar = clampf(float(el.set_pressure_bar), pmin, pmax)
	if "hysteresis_bar" in el:
		var hmax: float = maxf(pmax - pmin, 0.05)
		el.hysteresis_bar = clampf(float(el.hysteresis_bar), 0.02, hmax)


## Геркон на ПЦ: зазор до магнита поршня (Festo SME-8 / SMC D-A93-класс).
static func reed_sizes() -> Array:
	return [
		{"label": "Т-паз · 18 мм", "body_od_mm": 8.0, "sense_range_mm": 18.0, "hysteresis_mm": 1.5, "body_len_mm": 36.0},
		{"label": "Т-паз · 22 мм", "body_od_mm": 8.0, "sense_range_mm": 22.0, "hysteresis_mm": 1.8, "body_len_mm": 36.0},
		{"label": "Тяга · 22 мм", "body_od_mm": 10.0, "sense_range_mm": 22.0, "hysteresis_mm": 2.0, "body_len_mm": 42.0},
	]


static func nearest_inductive_index(body_od_mm: float) -> int:
	var best_i: int = 1
	var best_d: float = 1.0e9
	var rows: Array = inductive_sizes()
	for i in rows.size():
		var d: float = absf(float((rows[i] as Dictionary).get("body_od_mm", 12.0)) - body_od_mm)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_inductive_size(el, index: int) -> void:
	var rows: Array = inductive_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 12.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 4.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 0.4))
	el.stroke_mm = float(row.get("body_len_mm", 50.0)) # reuse stroke_mm as body length mm


static func conform_inductive(el) -> void:
	if el == null:
		return
	var idx: int = nearest_inductive_index(float(el.body_od_mm) if float(el.body_od_mm) > 0.1 else 12.0)
	# Не затирать ручной Sn, если уже задан близко к каталогу размера.
	var od: float = float(el.body_od_mm)
	if od < 1.0:
		apply_inductive_size(el, idx)
		return
	var row: Dictionary = inductive_sizes()[idx] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 12.0))
	if float(el.sense_range_mm) < 0.1:
		el.sense_range_mm = float(row.get("sense_range_mm", 4.0))
	if float(el.hysteresis_mm) < 0.01:
		el.hysteresis_mm = float(row.get("hysteresis_mm", 0.4))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 50.0))


static func nearest_reed_index(body_od_mm: float, sense_range_mm: float = 0.0) -> int:
	var best_i: int = 0
	var best_d: float = 1.0e9
	var rows: Array = reed_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var d_od: float = absf(float(row.get("body_od_mm", 8.0)) - body_od_mm)
		var d_sn: float = 0.0
		if sense_range_mm > 0.1:
			d_sn = absf(float(row.get("sense_range_mm", 18.0)) - sense_range_mm) * 0.05
		var d: float = d_od + d_sn
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_reed_size(el, index: int) -> void:
	var rows: Array = reed_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 8.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 18.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 1.5))
	el.stroke_mm = float(row.get("body_len_mm", 36.0))
	el.sensor_active = false
	el.output_type = "contact"


static func conform_reed(el) -> void:
	if el == null:
		return
	el.sensor_active = false
	el.output_type = "contact"
	var od: float = float(el.body_od_mm) if float(el.body_od_mm) > 0.1 else 8.0
	var idx: int = nearest_reed_index(od, float(el.sense_range_mm))
	if od < 1.0 or float(el.sense_range_mm) < 0.1:
		apply_reed_size(el, idx)
		return
	var row: Dictionary = reed_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 8.0))
	if float(el.sense_range_mm) < 0.1:
		el.sense_range_mm = float(row.get("sense_range_mm", 18.0))
	if float(el.hysteresis_mm) < 0.01:
		el.hysteresis_mm = float(row.get("hysteresis_mm", 1.5))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 36.0))


static func nearest_capacitive_index(body_od_mm: float, sense_range_mm: float = 0.0) -> int:
	var best_i: int = 1
	var best_d: float = 1.0e9
	var rows: Array = capacitive_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var d_od: float = absf(float(row.get("body_od_mm", 18.0)) - body_od_mm)
		var d_sn: float = 0.0
		if sense_range_mm > 0.1:
			d_sn = absf(float(row.get("sense_range_mm", 8.0)) - sense_range_mm) * 0.08
		var d: float = d_od + d_sn
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_capacitive_size(el, index: int) -> void:
	var rows: Array = capacitive_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 18.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 8.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 0.8))
	el.stroke_mm = float(row.get("body_len_mm", 65.0))
	el.sensor_active = true


static func conform_capacitive(el) -> void:
	if el == null:
		return
	el.sensor_active = true
	var od: float = float(el.body_od_mm) if float(el.body_od_mm) > 0.1 else 18.0
	var idx: int = nearest_capacitive_index(od, float(el.sense_range_mm))
	if od < 1.0 or float(el.sense_range_mm) < 0.1:
		apply_capacitive_size(el, idx)
		return
	var row: Dictionary = capacitive_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 18.0))
	if float(el.sense_range_mm) < 0.1:
		el.sense_range_mm = float(row.get("sense_range_mm", 8.0))
	if float(el.hysteresis_mm) < 0.01:
		el.hysteresis_mm = float(row.get("hysteresis_mm", 0.8))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 65.0))


static func nearest_optical_index(sense_range_mm: float) -> int:
	return nearest_optical_fiber_index(sense_range_mm)


static func nearest_optical_fiber_index(sense_range_mm: float) -> int:
	var best_i: int = 0
	var best_d: float = 1.0e9
	var rows: Array = optical_fiber_sizes()
	for i in rows.size():
		var d: float = absf(float((rows[i] as Dictionary).get("sense_range_mm", 100.0)) - sense_range_mm)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func nearest_optical_compact_index(body_od_mm: float, sense_range_mm: float = 0.0) -> int:
	var best_i: int = 1
	var best_d: float = 1.0e9
	var rows: Array = optical_compact_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var d: float = absf(float(row.get("body_od_mm", 18.0)) - body_od_mm)
		if sense_range_mm > 0.1:
			d += absf(float(row.get("sense_range_mm", 100.0)) - sense_range_mm) * 0.02
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_optical_size(el, index: int) -> void:
	apply_optical_fiber_size(el, index)


static func apply_optical_fiber_size(el, index: int) -> void:
	var rows: Array = optical_fiber_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.optical_form = "fiber"
	el.body_od_mm = float(row.get("body_od_mm", 30.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 100.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 5.0))
	el.stroke_mm = float(row.get("body_len_mm", 70.0))
	el.sensor_active = true
	if float(el.threshold_pct) < 0.5:
		el.threshold_pct = 50.0


static func apply_optical_compact_size(el, index: int) -> void:
	var rows: Array = optical_compact_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.optical_form = "compact"
	el.body_od_mm = float(row.get("body_od_mm", 18.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 100.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 5.0))
	el.stroke_mm = float(row.get("body_len_mm", 65.0))
	el.sensor_active = true
	if float(el.threshold_pct) < 0.5:
		el.threshold_pct = 50.0


static func conform_optical(el) -> void:
	if el == null:
		return
	el.sensor_active = true
	if str(el.optical_form) == "compact":
		var idx_c: int = nearest_optical_compact_index(float(el.body_od_mm), float(el.sense_range_mm))
		if float(el.sense_range_mm) < 0.1 or float(el.body_od_mm) < 1.0:
			apply_optical_compact_size(el, idx_c)
			return
		var row_c: Dictionary = optical_compact_sizes()[idx_c] as Dictionary
		if float(el.body_od_mm) < 1.0:
			el.body_od_mm = float(row_c.get("body_od_mm", 18.0))
		if float(el.hysteresis_mm) < 0.01:
			el.hysteresis_mm = float(row_c.get("hysteresis_mm", 5.0))
		if float(el.stroke_mm) < 10.0:
			el.stroke_mm = float(row_c.get("body_len_mm", 65.0))
		return
	el.optical_form = "fiber"
	var sn: float = float(el.sense_range_mm) if float(el.sense_range_mm) > 0.1 else 100.0
	var idx: int = nearest_optical_fiber_index(sn)
	if float(el.sense_range_mm) < 0.1 or float(el.body_od_mm) < 1.0:
		apply_optical_fiber_size(el, idx)
		return
	var row: Dictionary = optical_fiber_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 30.0))
	if float(el.hysteresis_mm) < 0.01:
		el.hysteresis_mm = float(row.get("hysteresis_mm", 5.0))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 70.0))


static func nearest_ultrasonic_index(sense_range_mm: float, sense_min_mm: float = 0.0) -> int:
	var best_i: int = 0
	var best_d: float = 1.0e9
	var rows: Array = ultrasonic_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var d: float = absf(float(row.get("sense_range_mm", 500.0)) - sense_range_mm)
		if sense_min_mm > 0.1:
			d += absf(float(row.get("sense_min_mm", 50.0)) - sense_min_mm) * 0.05
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_ultrasonic_size(el, index: int) -> void:
	var rows: Array = ultrasonic_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 18.0))
	el.sense_min_mm = float(row.get("sense_min_mm", 50.0))
	el.sense_range_mm = float(row.get("sense_range_mm", 500.0))
	el.hysteresis_mm = float(row.get("hysteresis_mm", 5.0))
	el.stroke_mm = float(row.get("body_len_mm", 70.0))
	el.sensor_active = true
	el.analog_kind = SensorSig.normalize_analog(str(row.get("analog_kind", "0_10v")))
	if str(el.analog_kind) == "":
		el.analog_kind = SensorSig.ANALOG_0_10V


static func conform_ultrasonic(el) -> void:
	if el == null:
		return
	el.sensor_active = true
	var sn: float = float(el.sense_range_mm) if float(el.sense_range_mm) > 1.0 else 500.0
	var smin: float = float(el.sense_min_mm) if "sense_min_mm" in el else 0.0
	var idx: int = nearest_ultrasonic_index(sn, smin)
	if float(el.sense_range_mm) < 1.0 or float(el.body_od_mm) < 1.0:
		apply_ultrasonic_size(el, idx)
		return
	var row: Dictionary = ultrasonic_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 18.0))
	if float(el.sense_min_mm) < 0.1:
		el.sense_min_mm = float(row.get("sense_min_mm", 50.0))
	if float(el.hysteresis_mm) < 0.01:
		el.hysteresis_mm = float(row.get("hysteresis_mm", 5.0))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 70.0))
	if str(el.analog_kind) == "":
		el.analog_kind = SensorSig.normalize_analog(str(row.get("analog_kind", "0_10v")))
		if str(el.analog_kind) == "":
			el.analog_kind = SensorSig.ANALOG_0_10V


## Датчик избыточного давления — аналоговый ПИП (Metran / Festo SDE / SMC PSE-класс).
## Активный: без Uпит нет валидного аналога. Диапазон бар изб. + analog_kind.
## Blind (без локального дисплея) — P и сигнал в tooltip / свойствах.
static func pressure_tx_sizes() -> Array:
	return [
		{
			"label": "0…10 бар · 4–20 мА",
			"range_min_bar": 0.0,
			"range_max_bar": 10.0,
			"body_od_mm": 22.0,
			"body_len_mm": 72.0,
			"analog_kind": "4_20ma",
		},
		{
			"label": "0…10 бар · 0–10 В",
			"range_min_bar": 0.0,
			"range_max_bar": 10.0,
			"body_od_mm": 22.0,
			"body_len_mm": 72.0,
			"analog_kind": "0_10v",
		},
		{
			"label": "0…16 бар · 4–20 мА",
			"range_min_bar": 0.0,
			"range_max_bar": 16.0,
			"body_od_mm": 22.0,
			"body_len_mm": 75.0,
			"analog_kind": "4_20ma",
		},
		{
			"label": "0…6 бар · 0–10 В",
			"range_min_bar": 0.0,
			"range_max_bar": 6.0,
			"body_od_mm": 22.0,
			"body_len_mm": 70.0,
			"analog_kind": "0_10v",
		},
	]


static func nearest_pressure_tx_index(range_max_bar: float, analog_kind: String = "") -> int:
	var best_i: int = 0
	var best_d: float = 1.0e9
	var want_ak: String = SensorSig.normalize_analog(analog_kind)
	var rows: Array = pressure_tx_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var d: float = absf(float(row.get("range_max_bar", 10.0)) - range_max_bar)
		if want_ak != "":
			var row_ak: String = SensorSig.normalize_analog(str(row.get("analog_kind", "")))
			if row_ak != want_ak:
				d += 2.0
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


static func apply_pressure_tx_size(el, index: int) -> void:
	var rows: Array = pressure_tx_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 22.0))
	el.stroke_mm = float(row.get("body_len_mm", 72.0))
	el.sense_min_mm = float(row.get("range_min_bar", 0.0))
	el.sense_range_mm = float(row.get("range_max_bar", 10.0))
	el.sensor_active = true
	el.analog_kind = SensorSig.normalize_analog(str(row.get("analog_kind", "4_20ma")))
	if str(el.analog_kind) == "":
		el.analog_kind = SensorSig.ANALOG_4_20MA
	# Аналог — основной выход; дискретный ключ не используем.
	el.output_type = SensorSig.OUT_NPN


static func conform_pressure_tx(el) -> void:
	if el == null:
		return
	el.sensor_active = true
	var rmax: float = float(el.sense_range_mm) if float(el.sense_range_mm) > 0.05 else 10.0
	var idx: int = nearest_pressure_tx_index(rmax, str(el.analog_kind))
	if float(el.sense_range_mm) < 0.05 or float(el.body_od_mm) < 1.0:
		apply_pressure_tx_size(el, idx)
		return
	var row: Dictionary = pressure_tx_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 22.0))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 72.0))
	if float(el.sense_min_mm) < 0.0:
		el.sense_min_mm = float(row.get("range_min_bar", 0.0))
	if str(el.analog_kind) == "":
		el.analog_kind = SensorSig.normalize_analog(str(row.get("analog_kind", "4_20ma")))
		if str(el.analog_kind) == "":
			el.analog_kind = SensorSig.ANALOG_4_20MA
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		el.sense_range_mm = pmin + 0.05


## ТС / Pt100 (пассивный R). ОВЕН / Элемер / WIKA-класс.
## wire_scheme 2/3/4; rtd_type в recipe_id / catalog: pt100 | 100p | cu100.
## sense_min_mm / sense_range_mm — учебный диапазон T (°C); temperature_c — T зоны на зонде.
static func rtd_sizes() -> Array:
	return [
		{
			"label": "Pt100 · −50…+400 °C · IEC",
			"rtd_type": "pt100",
			"range_min_c": -50.0,
			"range_max_c": 400.0,
			"body_od_mm": 8.0,
			"body_len_mm": 100.0,
			"wire_scheme": 3,
		},
		{
			"label": "100П · −50…+400 °C · ГОСТ",
			"rtd_type": "100p",
			"range_min_c": -50.0,
			"range_max_c": 400.0,
			"body_od_mm": 8.0,
			"body_len_mm": 100.0,
			"wire_scheme": 3,
		},
		{
			"label": "Cu100 · −50…+200 °C",
			"rtd_type": "cu100",
			"range_min_c": -50.0,
			"range_max_c": 200.0,
			"body_od_mm": 8.0,
			"body_len_mm": 90.0,
			"wire_scheme": 3,
		},
	]


static func rtd_type_of(el) -> String:
	if el == null:
		return "pt100"
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var rid: String = str(el.recipe_id).to_lower()
	if rid.contains("100p") or rid.contains("gost"):
		return Rtd.normalize_type("100p")
	if rid.contains("cu100"):
		return Rtd.normalize_type("cu100")
	if rid.contains("cu50"):
		return Rtd.normalize_type("cu50")
	var cid: String = str(el.catalog_id).to_lower()
	if cid.contains("100p"):
		return Rtd.normalize_type("100p")
	if cid.contains("cu"):
		return Rtd.normalize_type(cid)
	return Rtd.normalize_type("pt100")


static func nearest_rtd_index(rtd_type: String = "pt100") -> int:
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var want: String = Rtd.normalize_type(rtd_type)
	var rows: Array = rtd_sizes()
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		if Rtd.normalize_type(str(row.get("rtd_type", "pt100"))) == want:
			return i
	return 0


static func apply_rtd_size(el, index: int) -> void:
	var rows: Array = rtd_sizes()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index] as Dictionary
	el.body_od_mm = float(row.get("body_od_mm", 8.0))
	el.stroke_mm = float(row.get("body_len_mm", 100.0))
	el.sense_min_mm = float(row.get("range_min_c", -50.0))
	el.sense_range_mm = float(row.get("range_max_c", 400.0))
	el.sensor_active = false
	el.analog_kind = SensorSig.ANALOG_RTD
	el.output_type = SensorSig.OUT_CONTACT
	el.wire_scheme = clampi(int(row.get("wire_scheme", el.wire_scheme)), 2, 4)
	_rtd_clamp_temperature(el)


static func conform_rtd(el) -> void:
	if el == null:
		return
	el.sensor_active = false
	el.analog_kind = SensorSig.ANALOG_RTD
	el.output_type = SensorSig.OUT_CONTACT
	var idx: int = nearest_rtd_index(rtd_type_of(el))
	if float(el.body_od_mm) < 1.0 or float(el.stroke_mm) < 10.0:
		apply_rtd_size(el, idx)
		return
	var row: Dictionary = rtd_sizes()[idx] as Dictionary
	if float(el.body_od_mm) < 1.0:
		el.body_od_mm = float(row.get("body_od_mm", 8.0))
	if float(el.stroke_mm) < 10.0:
		el.stroke_mm = float(row.get("body_len_mm", 100.0))
	if float(el.sense_range_mm) < 1.0:
		el.sense_min_mm = float(row.get("range_min_c", -50.0))
		el.sense_range_mm = float(row.get("range_max_c", 400.0))
	el.wire_scheme = clampi(int(el.wire_scheme), 2, 4)
	var tmin: float = float(el.sense_min_mm)
	var tmax: float = float(el.sense_range_mm)
	if tmax < tmin + 1.0:
		tmax = tmin + 1.0
		el.sense_range_mm = tmax
	_rtd_clamp_temperature(el)


## Без `in`/прямого `.temperature_c`: у bake-_PreviewEl поле могло отсутствовать.
static func _rtd_clamp_temperature(el) -> void:
	if el == null:
		return
	var has_t: bool = false
	for p in el.get_property_list():
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if str((p as Dictionary).get("name", "")) == "temperature_c":
			has_t = true
			break
	if not has_t:
		return
	var tmin: float = float(el.sense_min_mm)
	var tmax: float = float(el.sense_range_mm)
	if tmax < tmin + 1.0:
		tmax = tmin + 1.0
	el.set("temperature_c", clampf(float(el.get("temperature_c")), tmin, tmax))
