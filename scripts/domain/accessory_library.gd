class_name AccessoryLibrary
extends RefCounted
## Рецепты пневмоаксессуаров (дроссель, ОК, ресивер, редуктор, FRL, ИЛИ, отсечной…).

const RECIPES_PATH := "res://data/accessories/recipes.json"

const CATEGORY_ORDER := ["flow", "storage", "prep"]
const CATEGORY_TITLE := {
	"flow": "Расход / направление",
	"storage": "Накопители",
	"prep": "Подготовка воздуха",
}

static var _ready := false
static var _recipes: Dictionary = {}
static var _recipe_order: PackedStringArray = PackedStringArray()


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	_load_recipes()


static func recipe(id: String) -> Dictionary:
	ensure_loaded()
	if _recipes.has(id):
		return (_recipes[id] as Dictionary).duplicate(true)
	return {}


static func all_recipes() -> Array:
	ensure_loaded()
	var out: Array = []
	for rid in _recipe_order:
		out.append(recipe(rid))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.catalog_id = el.recipe_id
	el.accessory_class = str(rec.get("accessory_class", "throttle"))
	# ГОСТ 2.704-2011 прил. А (не учебные 1Z / Z).
	el.tag_prefix = gost_accessory_prefix(str(el.accessory_class))
	if rec.has("opening"):
		el.opening = clampf(float(rec["opening"]), 0.0, 1.0)
	if rec.has("volume_l"):
		el.volume_l = maxf(float(rec["volume_l"]), 0.05)
	if rec.has("reservoir_ports") and "reservoir_ports" in el:
		el.reservoir_ports = clampi(int(rec["reservoir_ports"]), 1, 5)
	if rec.has("set_pressure_bar"):
		el.set_pressure_bar = clampf(float(rec["set_pressure_bar"]), 0.0, 16.0)
	if rec.has("valve_cv"):
		el.valve_cv = clampf(float(rec["valve_cv"]), 0.2, 4.0)
	if rec.has("crack_pressure_bar") and "crack_pressure_bar" in el:
		el.crack_pressure_bar = clampf(float(rec["crack_pressure_bar"]), 0.01, 5.0)
	if rec.has("flow_nl_min") and "flow_nl_min" in el:
		el.flow_nl_min = clampf(float(rec["flow_nl_min"]), 10.0, 20000.0)
	# open_ports из рецепта (для ПЦ и т.п.); ресивер стравливает свободные бобышки отдельно в circuit.
	if "open_ports" in el:
		el.open_ports = bool(rec.get("open_ports", false))
	# Ресивер: подтянуть резьбу/OD из ближайшего типоразмера; по умолчанию 1 бобышка.
	if str(el.accessory_class) == "reservoir":
		var keep_ports: int = reservoir_port_count(el)
		var best_i: int = 3
		var best_d: float = 1.0e9
		var vol0: float = float(el.volume_l)
		var rows: Array = reservoir_catalog()
		for i in rows.size():
			var d: float = absf(float((rows[i] as Dictionary).get("volume_l", 0.0)) - vol0)
			if d < best_d:
				best_d = d
				best_i = i
		apply_reservoir_catalog(el, best_i)
		_set_reservoir_ports(el, keep_ports)
	elif str(el.accessory_class) == "regulator":
		# По умолчанию G1/4 · Ø8.
		apply_regulator_catalog(el, 1)
	elif str(el.accessory_class) == "shuttle":
		# По умолчанию G1/4 · Ø8 · 1170 Nl/мин (Festo OS-1/4-B).
		apply_shuttle_catalog(el, 1)
		if not rec.has("opening"):
			el.opening = 0.5
	elif str(el.accessory_class) == "and_valve":
		# По умолчанию G1/4 · Ø8 · ~1000 Nl/мин (dual-pressure / AND).
		apply_and_catalog(el, 1)
		if not rec.has("opening"):
			el.opening = 0.5
	elif str(el.accessory_class) == "quick_exhaust":
		# По умолчанию SE-1/4-B; выхлоп 3 — глушитель (как у ПР).
		apply_quick_exhaust_catalog(el, 1)
		el.port_3 = "muffler"
		if not rec.has("opening"):
			el.opening = 0.0
	elif str(el.accessory_class) == "shutoff":
		# По умолчанию QH-QS-6; NC — закрыт (opening→0, valve_pos=0).
		apply_shutoff_catalog(el, 1)
		configure_shutoff_valve_ugo(el)
	elif str(el.accessory_class) == "relief":
		# По умолчанию G1/4 · Ø8 · уставка 6 бар (Camozzi VMR-класс).
		apply_relief_catalog(el, 1)
		if not rec.has("opening"):
			el.opening = 0.0
		el.port_3 = "muffler"
		el.pressed = false
	return true


## Каталог шаровых отсечных кранов (Festo QH): Qn @ 6→5 бар.
static func shutoff_catalog() -> Array:
	return [
		{"label": "QH-QS-4 · Ø4 · 148 Nl/мин", "tube_od_mm": 4.0, "flow": 148.0},
		{"label": "QH-QS-6 · Ø6 · 533 Nl/мин", "tube_od_mm": 6.0, "flow": 533.0},
		{"label": "QH-QS-6-1/8 · Ø6 · 560 Nl/мин", "tube_od_mm": 6.0, "flow": 560.0, "thread": "R1/8"},
	]


static func apply_shutoff_catalog(el, index: int) -> void:
	var cat: Array = shutoff_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 6.0)))
	if "port_name" in el:
		el.port_name = str(row.get("thread", TubeFit.thread_for_tube_od(float(row.get("tube_od_mm", 6.0)))))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 533.0))
	el.valve_cv = clampf(float(row.get("flow", 533.0)) / 600.0, 0.2, 4.0)


## Поля УГО 2/2 NC, ручное с двух сторон (без вариаций конфигуратора).
static func configure_shutoff_valve_ugo(el) -> void:
	el.valve_ways = 2
	el.valve_positions = 2
	el.valve_nc_no = "nc"
	el.rest_pos = 0
	el.op_left = "button"
	el.op_right = "button"
	el.spool_envelopes = PackedStringArray(["2_closed", "2_open_P_A"])
	# Цель положения: 0=закрыт, 1=открыт; opening плавно догоняет.
	if int(el.valve_pos) < 0 or int(el.valve_pos) > 1:
		el.valve_pos = 0
	if float(el.opening) < 0.0 or float(el.opening) > 1.0:
		el.opening = 0.0


## Плавный ход рукоятки/шара к valve_pos (0/1). ~0.35 с на 90°.
static func advance_shutoff(el, dt: float) -> void:
	if el == null or str(el.accessory_class) != "shutoff":
		return
	var target: float = 1.0 if int(el.valve_pos) >= 1 else 0.0
	el.opening = move_toward(float(el.opening), target, 2.8 * maxf(dt, 0.0))


static func toggle_shutoff(el) -> void:
	if el == null or str(el.accessory_class) != "shutoff":
		return
	el.valve_pos = 0 if int(el.valve_pos) >= 1 else 1


static func set_shutoff_open(el, open: bool) -> void:
	if el == null or str(el.accessory_class) != "shutoff":
		return
	el.valve_pos = 1 if open else 0


## Каталог клапанов «ИЛИ» (shuttle / OR): Festo OS-ряд, Qn @ 6→5 бар.
static func shuttle_catalog() -> Array:
	return [
		{"label": "G1/8 · Ø6 · 500 Nl/мин", "thread": "G1/8", "tube_od_mm": 6.0, "flow": 500.0},
		{"label": "G1/4 · Ø8 · 1170 Nl/мин", "thread": "G1/4", "tube_od_mm": 8.0, "flow": 1170.0},
		{"label": "G1/2 · Ø12 · 5000 Nl/мин", "thread": "G1/2", "tube_od_mm": 12.0, "flow": 5000.0},
	]


static func apply_shuttle_catalog(el, index: int) -> void:
	var cat: Array = shuttle_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 8.0)))
	if "port_name" in el:
		el.port_name = str(row.get("thread", "G1/4"))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 1170.0))
	el.valve_cv = clampf(float(row.get("flow", 1170.0)) / 1000.0, 0.3, 6.0)


## Каталог клапанов «И» (dual-pressure / AND): Qn @ 6→5 бар, типоразмеры как у OS.
static func and_catalog() -> Array:
	return [
		{"label": "G1/8 · Ø6 · 450 Nl/мин", "thread": "G1/8", "tube_od_mm": 6.0, "flow": 450.0},
		{"label": "G1/4 · Ø8 · 1000 Nl/мин", "thread": "G1/4", "tube_od_mm": 8.0, "flow": 1000.0},
		{"label": "G1/2 · Ø12 · 4200 Nl/мин", "thread": "G1/2", "tube_od_mm": 12.0, "flow": 4200.0},
	]


static func apply_and_catalog(el, index: int) -> void:
	var cat: Array = and_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 8.0)))
	if "port_name" in el:
		el.port_name = str(row.get("thread", "G1/4"))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 1000.0))
	el.valve_cv = clampf(float(row.get("flow", 1000.0)) / 1000.0, 0.3, 6.0)


## Каталог быстрого выхлопа (Festo SE): Qn 1→2 и 2→3 @ 6→5 бар.
static func quick_exhaust_catalog() -> Array:
	return [
		{"label": "G1/8 · Ø6 · 300/660 Nl/мин", "thread": "G1/8", "tube_od_mm": 6.0, "flow": 300.0, "flow_exh": 660.0},
		{"label": "G1/4 · Ø8 · 960/1200 Nl/мин", "thread": "G1/4", "tube_od_mm": 8.0, "flow": 960.0, "flow_exh": 1200.0},
		{"label": "G3/8 · Ø10 · 2880/2760 Nl/мин", "thread": "G3/8", "tube_od_mm": 10.0, "flow": 2880.0, "flow_exh": 2760.0},
		{"label": "G1/2 · Ø12 · 4560/6480 Nl/мин", "thread": "G1/2", "tube_od_mm": 12.0, "flow": 4560.0, "flow_exh": 6480.0},
	]


static func apply_quick_exhaust_catalog(el, index: int) -> void:
	var cat: Array = quick_exhaust_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 8.0)))
	if "port_name" in el:
		el.port_name = str(row.get("thread", "G1/4"))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 960.0))
	el.valve_cv = clampf(float(row.get("flow", 960.0)) / 800.0, 0.3, 6.0)


## Каталог предохранительных клапанов (Camozzi VMR / spring relief): уставка 0.5…10 бар.
static func relief_catalog() -> Array:
	return [
		{"label": "G1/8 · Ø6 · 0.5…10 бар · 350 Nl/мин", "thread": "G1/8", "tube_od_mm": 6.0, "flow": 350.0, "set_max": 10.0},
		{"label": "G1/4 · Ø8 · 0.5…10 бар · 700 Nl/мин", "thread": "G1/4", "tube_od_mm": 8.0, "flow": 700.0, "set_max": 10.0},
		{"label": "G3/8 · Ø10 · 0.5…10 бар · 1400 Nl/мин", "thread": "G3/8", "tube_od_mm": 10.0, "flow": 1400.0, "set_max": 10.0},
	]


static func apply_relief_catalog(el, index: int) -> void:
	var cat: Array = relief_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 8.0)))
	if "port_name" in el:
		el.port_name = str(row.get("thread", "G1/4"))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 700.0))
	el.valve_cv = clampf(float(row.get("flow", 700.0)) / 700.0, 0.3, 6.0)
	var set_max: float = clampf(float(row.get("set_max", 10.0)), 1.0, 16.0)
	el.set_pressure_bar = clampf(float(el.set_pressure_bar), 0.5, set_max)


static func quick_exhaust_exh_ratio(el) -> float:
	var qn: float = float(el.flow_nl_min) if el != null else 960.0
	for row_v in quick_exhaust_catalog():
		var row: Dictionary = row_v as Dictionary
		if absf(float(row.get("flow", 0.0)) - qn) < 1.0:
			var fp: float = maxf(float(row.get("flow", 1.0)), 1.0)
			return clampf(float(row.get("flow_exh", fp)) / fp, 0.8, 4.0)
	# SE-1/4 по умолчанию: 1200/960.
	return 1.25


## Каталог обратных клапанов (учебный ряд: резьба ISO 228 / ISO 261, Qn @ 6→5 бар).
## thread + tube_od_mm — для 3D-масштаба и согласования трубок.
static func check_catalog() -> Array:
	return [
		{"label": "M5 · Ø4 · 1.0 бар · 50 Nl/мин", "thread": "M5", "tube_od_mm": 4.0, "crack": 1.0, "flow": 50.0},
		{"label": "G1/8 · Ø6 · 0.2 бар · 600 Nl/мин", "thread": "G1/8", "tube_od_mm": 6.0, "crack": 0.2, "flow": 600.0},
		{"label": "G1/4 · Ø8 · 0.2 бар · 1400 Nl/мин", "thread": "G1/4", "tube_od_mm": 8.0, "crack": 0.2, "flow": 1400.0},
		{"label": "G3/8 · Ø10 · 0.02 бар · 3000 Nl/мин", "thread": "G3/8", "tube_od_mm": 10.0, "crack": 0.02, "flow": 3000.0},
		{"label": "G1/2 · Ø12 · 0.02 бар · 5800 Nl/мин", "thread": "G1/2", "tube_od_mm": 12.0, "crack": 0.02, "flow": 5800.0},
	]


## Учебный ряд дросселей по OD трубки (Qn при 6→5 бар).
static func throttle_catalog() -> Array:
	return [
		{"label": "Ø4", "tube_od_mm": 4.0, "flow": 120.0},
		{"label": "Ø6", "tube_od_mm": 6.0, "flow": 400.0},
		{"label": "Ø8", "tube_od_mm": 8.0, "flow": 800.0},
		{"label": "Ø10", "tube_od_mm": 10.0, "flow": 1400.0},
		{"label": "Ø12", "tube_od_mm": 12.0, "flow": 2200.0},
	]


## Учебный ряд редукторов (MS/AR-класс): резьба + OD + диапазон уставки.
static func regulator_catalog() -> Array:
	return [
		{"label": "G1/8 · Ø6 · 0.5…7 бар", "thread": "G1/8", "tube_od_mm": 6.0, "set_max": 7.0, "flow": 550.0},
		{"label": "G1/4 · Ø8 · 0.5…10 бар", "thread": "G1/4", "tube_od_mm": 8.0, "set_max": 10.0, "flow": 1400.0},
		{"label": "G3/8 · Ø10 · 0.5…10 бар", "thread": "G3/8", "tube_od_mm": 10.0, "set_max": 10.0, "flow": 3000.0},
		{"label": "G1/2 · Ø12 · 0.5…10 бар", "thread": "G1/2", "tube_od_mm": 12.0, "set_max": 10.0, "flow": 5000.0},
	]


static func apply_regulator_catalog(el, index: int) -> void:
	var cat: Array = regulator_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od: float = float(row.get("tube_od_mm", 8.0))
	TubeFit.apply_armature_od(el, od)
	el.port_name = str(row.get("thread", TubeFit.thread_for_tube_od(od)))
	var set_max: float = clampf(float(row.get("set_max", 10.0)), 1.0, 16.0)
	el.set_pressure_bar = clampf(float(el.set_pressure_bar), 0.0, set_max)
	if "flow_nl_min" in el:
		el.flow_nl_min = clampf(float(row.get("flow", 1400.0)), 10.0, 20000.0)
	el.valve_cv = clampf(od / 6.0, 0.4, 3.5)


## Типоряды объёма ресивера (учебный ряд, резьба ISO 228 / OD трубки).
static func reservoir_catalog() -> Array:
	return [
		{"label": "0.1 л · G1/8 · Ø6", "volume_l": 0.1, "thread": "G1/8", "tube_od_mm": 6.0},
		{"label": "0.4 л · G1/4 · Ø8", "volume_l": 0.4, "thread": "G1/4", "tube_od_mm": 8.0},
		{"label": "0.75 л · G1/4 · Ø8", "volume_l": 0.75, "thread": "G1/4", "tube_od_mm": 8.0},
		{"label": "2 л · G1/2 · Ø10", "volume_l": 2.0, "thread": "G1/2", "tube_od_mm": 10.0},
		{"label": "5 л · G1 · Ø12", "volume_l": 5.0, "thread": "G1", "tube_od_mm": 12.0},
		{"label": "10 л · G1 · Ø12", "volume_l": 10.0, "thread": "G1", "tube_od_mm": 12.0},
		{"label": "20 л · G1 · Ø12", "volume_l": 20.0, "thread": "G1", "tube_od_mm": 12.0},
	]


static func apply_reservoir_catalog(el, index: int) -> void:
	var cat: Array = reservoir_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	el.volume_l = maxf(float(row.get("volume_l", 2.0)), 0.05)
	_set_reservoir_ports(el, reservoir_port_count(el))
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od: float = float(row.get("tube_od_mm", 6.0))
	TubeFit.apply_armature_od(el, od)
	el.port_name = str(row.get("thread", TubeFit.thread_for_tube_od(od)))
	el.valve_cv = clampf(od / 6.0, 0.4, 3.0)


static func _set_reservoir_ports(el, n: int) -> void:
	if el == null or not ("reservoir_ports" in el):
		return
	el.reservoir_ports = clampi(n, 1, 5)


## Габарит 3D от объёма: V = π·(D/2)²·L, L/D ≈ 2.6 (типичный баллон).
static func reservoir_dims(el) -> Dictionary:
	var vol_l: float = maxf(float(el.volume_l) if el != null else 2.0, 0.05)
	var vol_m3: float = vol_l * 0.001
	var aspect: float = 2.6 # L / D
	# D³ = 4V / (π·aspect)
	var d_m: float = pow(maxf(4.0 * vol_m3 / (PI * aspect), 1.0e-9), 1.0 / 3.0)
	var l_m: float = aspect * d_m
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od: float = 6.0
	if el != null and float(el.tube_od_mm) >= 1.0:
		od = float(el.tube_od_mm)
	else:
		# Ближайший типоразмер по объёму → OD.
		var best_od: float = 10.0
		var best_d: float = 1.0e9
		for row_v in reservoir_catalog():
			var row: Dictionary = row_v as Dictionary
			var dv: float = absf(float(row.get("volume_l", 0.0)) - vol_l)
			if dv < best_d:
				best_d = dv
				best_od = float(row.get("tube_od_mm", 10.0))
		od = best_od
	var thread: String = str(el.port_name) if el != null and str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	return {
		"volume_l": vol_l,
		"thread": thread,
		"tube_od_mm": od,
		"diameter_mm": d_m * 1000.0,
		"length_mm": l_m * 1000.0,
	}


static func reservoir_port_count(el) -> int:
	if el == null or not ("reservoir_ports" in el):
		return 1
	var raw = el.get("reservoir_ports")
	if raw == null:
		return 1
	return clampi(int(raw), 1, 5)


static func apply_check_catalog(el, index: int) -> void:
	var cat: Array = check_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	if "crack_pressure_bar" in el:
		el.crack_pressure_bar = float(row.get("crack", 0.2))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 600.0))
	# Совместимость со старым Cv: G1/8 = 1.0.
	el.valve_cv = clampf(float(row.get("flow", 600.0)) / 600.0, 0.2, 4.0)
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od: float = float(row.get("tube_od_mm", 6.0))
	TubeFit.apply_armature_od(el, od)
	el.port_name = str(row.get("thread", TubeFit.thread_for_tube_od(od)))


static func apply_throttle_catalog(el, index: int) -> void:
	var cat: Array = throttle_catalog()
	if index < 0 or index >= cat.size():
		return
	var row: Dictionary = cat[index] as Dictionary
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	TubeFit.apply_armature_od(el, float(row.get("tube_od_mm", 6.0)))
	if "flow_nl_min" in el:
		el.flow_nl_min = float(row.get("flow", 400.0))
	el.valve_cv = clampf(float(row.get("flow", 400.0)) / 400.0, 0.2, 4.0)


static func port_names(el) -> PackedStringArray:
	var cls := str(el.accessory_class)
	match cls:
		"reservoir":
			var n: int = reservoir_port_count(el)
			var out := PackedStringArray()
			for i in n:
				out.append(str(i + 1))
			return out
		"shuttle":
			# 1/2 — входы сигнала, 3 — выход A (Festo OS / ISO 1219 OR).
			return PackedStringArray(["1", "2", "3"])
		"and_valve":
			# 1/2 — входы, 3 — выход (dual-pressure / AND).
			return PackedStringArray(["1", "2", "3"])
		"quick_exhaust":
			# 1=вход, 2=ПЦ, 3=выхлоп (Festo SE / ISO).
			return PackedStringArray(["1", "2", "3"])
		"relief":
			# 1=вход из системы, 2=сброс (штуцер / глушитель).
			return PackedStringArray(["1", "2"])
		_:
			return PackedStringArray(["1", "2"])


## Буквенные позиционные обозначения по ГОСТ 2.704-2011, приложение А.
static func gost_accessory_prefix(cls: String) -> String:
	match str(cls):
		"throttle", "throttle_fixed", "throttle_check", "throttle_check_fixed":
			return "ДР"
		"check":
			return "КО"
		"regulator":
			return "КР"
		"reservoir":
			return "РС"
		"frl":
			return "У"
		"shuttle":
			return "КЛ" # логический клапан «ИЛИ»
		"and_valve":
			return "КЛ" # логический клапан «И»
		"quick_exhaust":
			return "КВ" # клапан быстрого выхлопа
		"shutoff":
			return "ЗК" # запорный кран
		"relief":
			return "КП" # предохранительный клапан
		_:
			return "У"


## Префикс для любого пневмоэлемента (ГОСТ 2.704-2011).
static func gost_tag_prefix(el) -> String:
	if el == null:
		return "У"
	match str(el.kind):
		"source":
			return "КМ" # компрессор / источник сжатого воздуха
		"valve":
			return "Р" # пневмораспределитель
		"cylinder":
			return "Ц" # пневмоцилиндр
		"rotary_cylinder":
			return "ППЦ"
		"air_motor":
			return "ПМ"
		"junction":
			return "У" # устройство (общее) — тройник/коллектор
		"accessory":
			return gost_accessory_prefix(str(el.accessory_class))
		_:
			return "У"


static func title_of(el) -> String:
	ensure_loaded()
	var rec := recipe(str(el.recipe_id))
	if not rec.is_empty():
		return str(rec.get("title", el.recipe_id))
	match str(el.accessory_class):
		"throttle":
			return "Дроссель регулируемый"
		"throttle_fixed":
			return "Дроссель нерегулируемый"
		"check":
			return "Обратный клапан"
		"throttle_check":
			return "Дроссель с обратным клапаном"
		"throttle_check_fixed":
			return "Дроссель с ОК (нерегулируемый)"
		"reservoir":
			return "Ресивер"
		"regulator":
			return "Редуктор"
		"frl":
			return "FRL"
		"shuttle":
			return "Клапан «ИЛИ»"
		"and_valve":
			return "Клапан «И»"
		"quick_exhaust":
			return "Клапан быстрого выхлопа"
		"shutoff":
			return "Отсечной кран"
		"relief":
			return "Предохранительный клапан"
		_:
			return "Аксессуар"


static func _load_recipes() -> void:
	_recipes.clear()
	_recipe_order = PackedStringArray()
	if not FileAccess.file_exists(RECIPES_PATH):
		push_warning("AccessoryLibrary: нет %s" % RECIPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Array = parsed.get("recipes", [])
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rid := str(item.get("id", ""))
		if rid == "":
			continue
		_recipes[rid] = item
		_recipe_order.append(rid)
