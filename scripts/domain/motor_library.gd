class_name MotorLibrary
extends RefCounted
## Рецепты пневмомоторов (data/motor/recipes.json).

const RECIPES_PATH := "res://data/motor/recipes.json"
const MotorCat = preload("res://scripts/domain/motor_catalog.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")

const CATEGORY_ORDER := ["gear", "vane", "turbine"]
const CATEGORY_TITLE := {
	"gear": "Шестерённые",
	"vane": "Лопастные",
	"turbine": "Турбинные",
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
	for id in _recipe_order:
		out.append(recipe(id))
	return out


static func recipes_for_category(category: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _recipe_order:
		var rec: Dictionary = _recipes[id]
		if str(rec.get("category", "gear")) == category:
			out.append(recipe(id))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.catalog_id = str(rec.get("id", id))
	el.kind = "air_motor"
	el.rotary_class = str(rec.get("motor_class", rec.get("rotary_class", "gear")))
	if rec.has("free_rpm"):
		el.free_rpm = float(rec["free_rpm"])
	if rec.has("stall_nm_at_6bar"):
		el.torque_nm_at_6bar = float(rec["stall_nm_at_6bar"])
	elif rec.has("torque_nm_at_6bar"):
		el.torque_nm_at_6bar = float(rec["torque_nm_at_6bar"])
	if rec.has("flow_nl_min"):
		el.flow_nl_min = float(rec["flow_nl_min"])
	if rec.has("port_name"):
		el.port_name = str(rec["port_name"])
	if rec.has("tube_od_mm"):
		el.tube_od_mm = float(rec["tube_od_mm"])
	if rec.has("port_3"):
		el.port_3 = str(rec["port_3"])
	if rec.has("port_5"):
		el.port_5 = str(rec["port_5"])
	else:
		el.port_5 = "fitting"
	el.tag_prefix = "ПМ"
	el.order_code = "ПМ-%s" % str(el.recipe_id).to_upper()
	MotorCat.conform(el)
	if str(el.fitting_id) == "" and float(el.tube_od_mm) >= 1.0:
		TubeFit.apply_armature_od(el, float(el.tube_od_mm))
	return true


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
