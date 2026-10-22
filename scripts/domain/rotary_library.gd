class_name RotaryLibrary
extends RefCounted
## Рецепты поворотных ПЦ (data/rotary/recipes.json).

const RECIPES_PATH := "res://data/rotary/recipes.json"

const CATEGORY_ORDER := ["rack_pinion", "vane"]
const CATEGORY_TITLE := {
	"rack_pinion": "Поршневые (рейка–шестерня)",
	"vane": "Лопастные",
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
		if str(rec.get("category", "rack_pinion")) == category:
			out.append(recipe(id))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.catalog_id = str(rec.get("id", id))
	el.kind = "rotary_cylinder"
	el.rotary_class = str(rec.get("rotary_class", "rack_pinion"))
	if rec.has("bore_mm"):
		el.bore_mm = float(rec["bore_mm"])
	if rec.has("angle_max_deg"):
		el.angle_max_deg = float(rec["angle_max_deg"])
	if rec.has("torque_nm_at_6bar"):
		el.torque_nm_at_6bar = float(rec["torque_nm_at_6bar"])
	el.tag_prefix = "ППЦ"
	var Cat = preload("res://scripts/domain/rotary_catalog.gd")
	Cat.conform(el)
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
		var id: String = str(item.get("id", ""))
		if id == "":
			continue
		_recipes[id] = item
		_recipe_order.append(id)
