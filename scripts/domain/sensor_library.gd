class_name SensorLibrary
extends RefCounted
## Рецепты датчиков (data/sensors/recipes.json).

const RECIPES_PATH := "res://data/sensors/recipes.json"
const SensorCat = preload("res://scripts/domain/sensor_catalog.gd")
const SensorSig = preload("res://scripts/domain/sensor_signal.gd")

const CATEGORY_ORDER := ["proximity", "process", "motion", "indicating"]
const CATEGORY_TITLE := {
	"proximity": "Позиция / наличие",
	"process": "Давление / температура",
	"motion": "Скорость / расход / уровень",
	"indicating": "Показывающие",
}

static var _ready := false
static var _recipes: Dictionary = {}
static var _recipe_order: PackedStringArray = PackedStringArray()


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	_load_recipes()


static func reload() -> void:
	_ready = false
	ensure_loaded()


static func recipe(id: String) -> Dictionary:
	ensure_loaded()
	if _recipes.has(id):
		return (_recipes[id] as Dictionary).duplicate(true)
	return {}


static func all_recipes() -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _recipe_order:
		out.append(recipe(id))
	return out


static func recipes_for_category(category: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _recipe_order:
		var rec: Dictionary = _recipes[id]
		if str(rec.get("category", "proximity")) == category:
			out.append(recipe(id))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.catalog_id = el.recipe_id
	var ekind: String = str(rec.get("element_kind", "sensor"))
	if ekind == "opto_tip":
		el.kind = "opto_tip"
		if "opto_role" in el:
			el.opto_role = str(rec.get("opto_role", "head"))
		el.sensor_class = "optical"
		el.sensor_active = false
		el.body_od_mm = float(rec.get("body_od_mm", 4.0))
		el.stroke_mm = float(rec.get("body_len_mm", 22.0))
		el.sense_range_mm = float(rec.get("sense_range_mm", 200.0))
		el.hysteresis_mm = float(rec.get("hysteresis_mm", 5.0))
		el.tag_prefix = str(rec.get("tag_prefix", "БВ"))
		el.order_code = "TIP-%s" % str(el.recipe_id).to_upper()
		return true
	el.kind = "sensor"
	el.sensor_class = str(rec.get("sensor_class", "inductive"))
	el.sensor_active = bool(rec.get("sensor_active", true))
	el.sense_range_mm = float(rec.get("sense_range_mm", 4.0))
	el.hysteresis_mm = float(rec.get("hysteresis_mm", 0.4))
	el.body_od_mm = float(rec.get("body_od_mm", 12.0))
	el.stroke_mm = float(rec.get("body_len_mm", 50.0))
	el.supply_mode = SensorSig.normalize_supply(str(rec.get("supply_mode", "24dc")))
	el.output_type = SensorSig.normalize_output(str(rec.get("output_type", "npn")))
	el.contact_form = SensorSig.normalize_form(str(rec.get("contact_form", "no")))
	el.tag_prefix = str(rec.get("tag_prefix", "SQ"))
	el.analog_kind = SensorSig.normalize_analog(str(rec.get("analog_kind", "")))
	el.wire_scheme = clampi(int(rec.get("wire_scheme", 3)), 2, 4)
	el.order_code = "SQ-%s" % str(el.recipe_id).to_upper()
	if "sense_min_mm" in el:
		el.sense_min_mm = float(rec.get("sense_min_mm", el.sense_min_mm))
	if "optical_form" in el:
		el.optical_form = "compact" if str(rec.get("optical_form", "fiber")) == "compact" else "fiber"
	if "threshold_pct" in el:
		el.threshold_pct = clampf(float(rec.get("threshold_pct", 50.0)), 0.0, 100.0)
	if str(el.sensor_class) == "pressure_switch":
		el.tag_prefix = str(rec.get("tag_prefix", "KP"))
		el.order_code = "KP-%s" % str(el.recipe_id).to_upper()
		if "hysteresis_bar" in el:
			el.hysteresis_bar = float(rec.get("hysteresis_bar", 0.4))
		el.set_pressure_bar = float(rec.get("set_pressure_bar", 2.0))
		el.sense_min_mm = float(rec.get("range_min_bar", 0.2))
		el.sense_range_mm = float(rec.get("range_max_bar", 10.0))
		el.contact_defs = _pressure_switch_contact_defs(str(el.contact_form))
		el.group_template = "pressure_switch"
	if str(el.sensor_class) == "pressure_tx":
		el.tag_prefix = str(rec.get("tag_prefix", "PT"))
		el.order_code = "PT-%s" % str(el.recipe_id).to_upper()
		el.sense_min_mm = float(rec.get("range_min_bar", 0.0))
		el.sense_range_mm = float(rec.get("range_max_bar", 10.0))
		el.sensor_active = true
		el.analog_kind = SensorSig.normalize_analog(str(rec.get("analog_kind", el.analog_kind)))
		if str(el.analog_kind) == "":
			el.analog_kind = SensorSig.ANALOG_4_20MA
		el.group_template = "pressure_tx"
	if str(el.sensor_class) == "rtd":
		el.tag_prefix = str(rec.get("tag_prefix", "SK"))
		el.order_code = "SK-%s" % str(el.recipe_id).to_upper()
		el.sense_min_mm = float(rec.get("range_min_c", -50.0))
		el.sense_range_mm = float(rec.get("range_max_c", 400.0))
		el.sensor_active = false
		el.analog_kind = SensorSig.ANALOG_RTD
		el.output_type = SensorSig.OUT_CONTACT
		el.wire_scheme = clampi(int(rec.get("wire_scheme", el.wire_scheme)), 2, 4)
		el.group_template = "rtd"
		# T зоны клампит conform_rtd (не трогать temperature_c здесь — _PreviewEl/bake).
	if str(el.sensor_class) == "inductive":
		SensorCat.conform_inductive(el)
	elif str(el.sensor_class) == "reed":
		SensorCat.conform_reed(el)
	elif str(el.sensor_class) == "capacitive":
		SensorCat.conform_capacitive(el)
	elif str(el.sensor_class) == "optical":
		SensorCat.conform_optical(el)
	elif str(el.sensor_class) == "ultrasonic":
		SensorCat.conform_ultrasonic(el)
	elif str(el.sensor_class) == "pressure_switch":
		SensorCat.conform_pressure_switch(el)
	elif str(el.sensor_class) == "pressure_tx":
		SensorCat.conform_pressure_tx(el)
	elif str(el.sensor_class) == "rtd":
		SensorCat.conform_rtd(el)
	return true


static func _pressure_switch_contact_defs(form: String) -> Array:
	var t: String = "nc" if SensorSig.normalize_form(form) == SensorSig.FORM_NC else "no"
	return [
		{"name": "1", "type": t},
		{"name": "2", "type": t},
	]


## Контакт KP1.1 для реле давления (как у кнопки/реле): схема отдельно от пневмо-УГО.
static func spawn_pressure_switch_contact(circuit, primary) -> Array:
	var created: Array = []
	if primary == null or circuit == null:
		return created
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "pressure_switch":
		return created
	# Уже есть контакт группы — не дублировать.
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) == "contact":
			return created
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.group_tag = str(primary.tag)
	primary.member_role = "main"
	primary.member_index = 0
	primary.detached = false
	primary.contact_defs = _pressure_switch_contact_defs(str(primary.contact_form))
	var grid: float = 10.0 # SymbolGeom.SCH_GRID
	var pos: Vector2 = (primary.position + Vector2(0.0, grid * 6.0)).snapped(Vector2(grid, grid))
	var child = circuit.add_element_raw("electro", pos)
	if child == null:
		return created
	child.recipe_id = str(primary.recipe_id)
	child.catalog_id = child.recipe_id
	child.electro_class = "contact"
	child.electro_mount = "none"
	child.tag_prefix = str(primary.tag_prefix)
	child.contact_defs = primary.contact_defs.duplicate(true)
	child.group_id = gid
	child.group_tag = str(primary.tag)
	child.member_role = "contact"
	child.member_index = 1
	child.detached = false
	child.energized = false
	child.pressed = false
	child.tag = "%s.1" % str(primary.tag)
	# Метка для УГО: коробка «P» вместо кнопки.
	child.caption = "P"
	created.append(child)
	return created


static func sync_pressure_switch_contact_form(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "pressure_switch":
		return
	primary.contact_defs = _pressure_switch_contact_defs(str(primary.contact_form))
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) != "contact":
			continue
		m.contact_defs = primary.contact_defs.duplicate(true)
		m.tag_prefix = str(primary.tag_prefix)
		m.group_tag = str(primary.tag)


## Заголовок клеммной таблички ПИП (не tag).
const PRESSURE_TX_TABLE_CAPTION := "Преобразователь давления"


## Клеммная табличка PT: одна колодка +, −, сигнал (как УГО БП). Tag = PT (не ·.1).
static func _pressure_tx_terminal_ports() -> Array:
	return [
		{"name": "+", "type": "line", "side": "left", "circuit": "+"},
		{"name": "-", "type": "line", "side": "left", "circuit": "−"},
		{"name": "OUT", "type": "line", "side": "left", "circuit": "Сигнал"},
	]


static func spawn_pressure_tx_terminals(circuit, primary) -> Array:
	var created: Array = []
	if primary == null or circuit == null:
		return created
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "pressure_tx":
		return created
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) == "device":
			return created
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.group_tag = str(primary.tag)
	primary.member_role = "main"
	primary.member_index = 0
	primary.detached = false
	primary.group_template = "pressure_tx"
	var grid: float = 10.0
	var pos: Vector2 = (primary.position + Vector2(0.0, grid * 7.0)).snapped(Vector2(grid, grid))
	var child = circuit.add_element_raw("electro", pos)
	if child == null:
		return created
	child.recipe_id = str(primary.recipe_id)
	child.catalog_id = child.recipe_id
	child.electro_class = "generic_device"
	child.electro_mount = "none"
	child.tag_prefix = str(primary.tag_prefix)
	child.electro_ports = _pressure_tx_terminal_ports()
	child.group_id = gid
	child.group_tag = str(primary.tag)
	child.member_role = "device"
	child.member_index = 1
	child.detached = false
	# Та же позиция PT на электросхеме; в рамке таблицы — название прибора.
	child.tag = str(primary.tag)
	child.caption = PRESSURE_TX_TABLE_CAPTION
	created.append(child)
	return created


static func sync_pressure_tx_terminal(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "pressure_tx":
		return
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) != "device":
			continue
		m.electro_ports = _pressure_tx_terminal_ports()
		m.tag_prefix = str(primary.tag_prefix)
		m.group_tag = str(primary.tag)
		m.caption = PRESSURE_TX_TABLE_CAPTION
		m.tag = str(primary.tag)


## Заголовок вторичного прибора ТС (не tag).
const RTD_METER_CAPTION := "Вторичный прибор ТС"


## Клеммы вторички: +24/0 питание прибора + жилы ТС 1…N.
static func _rtd_meter_ports(wire_scheme: int) -> Array:
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var out: Array = [
		{"name": "+24", "type": "line", "side": "left", "circuit": "+24В"},
		{"name": "0", "type": "line", "side": "left", "circuit": "0В"},
	]
	for nm in Rtd.core_names(wire_scheme):
		out.append({"name": str(nm), "type": "line", "side": "left", "circuit": "ТС%s" % str(nm)})
	return out


## Вторичный прибор в щите (DIN) + клеммы на схеме. Чистый ТС на primary — без head-TX.
static func spawn_rtd_meter(circuit, primary) -> Array:
	var created: Array = []
	if primary == null or circuit == null:
		return created
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "rtd":
		return created
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) == "device":
			return created
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.group_tag = str(primary.tag)
	primary.member_role = "main"
	primary.member_index = 0
	primary.detached = false
	primary.group_template = "rtd"
	var grid: float = 10.0
	var pos: Vector2 = (primary.position + Vector2(0.0, grid * 7.0)).snapped(Vector2(grid, grid))
	var child = circuit.add_element_raw("electro", pos)
	if child == null:
		return created
	child.recipe_id = str(primary.recipe_id)
	child.catalog_id = child.recipe_id
	child.electro_class = "rtd_meter"
	child.electro_mount = "din"
	child.tag_prefix = str(primary.tag_prefix)
	child.electro_ports = _rtd_meter_ports(int(primary.wire_scheme))
	child.group_id = gid
	child.group_tag = str(primary.tag)
	child.member_role = "device"
	child.member_index = 1
	child.detached = false
	child.tag = str(primary.tag)
	child.caption = RTD_METER_CAPTION
	child.din_slot = -1
	created.append(child)
	return created


static func sync_rtd_meter(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.kind) != "sensor" or str(primary.sensor_class) != "rtd":
		return
	primary.wire_scheme = clampi(int(primary.wire_scheme), 2, 4)
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) != "device":
			continue
		m.electro_class = "rtd_meter"
		m.electro_ports = _rtd_meter_ports(int(primary.wire_scheme))
		m.tag_prefix = str(primary.tag_prefix)
		m.group_tag = str(primary.tag)
		m.caption = RTD_METER_CAPTION
		m.tag = str(primary.tag)


## Рецепты усилителя (не оптонаконечники).
static func amplifier_recipes() -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _recipe_order:
		var rec: Dictionary = _recipes[id] as Dictionary
		if str(rec.get("element_kind", "sensor")) == "opto_tip":
			continue
		out.append(recipe(id))
	return out


static func tip_recipes() -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _recipe_order:
		var rec: Dictionary = _recipes[id] as Dictionary
		if str(rec.get("element_kind", "")) == "opto_tip":
			out.append(recipe(id))
	return out


static func gost_prefix(sensor_class: String) -> String:
	match str(sensor_class):
		"inductive", "capacitive", "optical", "ultrasonic", "reed":
			return "SQ"
		"pressure_switch", "pressure":
			return "KP"
		"pressure_tx":
			return "PT"
		"rtd", "temp", "thermocouple", "bimetal":
			return "SK"
		"encoder", "flow", "level":
			return "BR"
		_:
			return "SQ"


static func _load_recipes() -> void:
	_recipes.clear()
	_recipe_order.clear()
	if not FileAccess.file_exists(RECIPES_PATH):
		return
	var f := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Array = (parsed as Dictionary).get("recipes", []) as Array
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rid: String = str(item.get("id", ""))
		if rid == "":
			continue
		_recipes[rid] = item
		_recipe_order.append(rid)
