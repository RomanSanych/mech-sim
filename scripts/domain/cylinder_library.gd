class_name CylinderLibrary
extends RefCounted
## Каталог типовых пневмоцилиндров (рецепты УГО/геометрии).
## data/cylinders/recipes.json — по аналогии с ValveLibrary.

const RECIPES_PATH := "res://data/cylinders/recipes.json"

## Порядок и подписи логических категорий в библиотеке.
const CATEGORY_ORDER := ["double", "single", "through", "rodless", "brake"]
const CATEGORY_TITLE := {
	"double": "Двустороннего действия",
	"single": "Одностороннего действия",
	"through": "Со сквозным штоком",
	"rodless": "Бесштоковые",
	"brake": "Со стопором / тормозом",
}

static var _ready := false
static var _recipes: Dictionary = {} # id -> Dictionary
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
		if str(rec.get("category", "double")) == category:
			out.append(recipe(id))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.catalog_id = str(rec.get("id", id))
	if rec.has("rod_mode"):
		el.rod_mode = str(rec["rod_mode"])
	if rec.has("spring_side"):
		el.spring_side = str(rec["spring_side"])
	if rec.has("piston_kind"):
		el.piston_kind = str(rec["piston_kind"])
	if rec.has("cush_cap"):
		el.cush_cap = str(rec["cush_cap"])
	if rec.has("cush_rod"):
		el.cush_rod = str(rec["cush_rod"])
	if rec.has("brake"):
		el.brake = str(rec["brake"])
	if rec.has("carriage"):
		el.carriage = str(rec["carriage"])
	if rec.has("bump_end"):
		el.bump_end = str(rec["bump_end"])
	else:
		el.bump_end = "none"
	if rec.has("body_style"):
		el.body_style = str(rec["body_style"])
		el.body_style_user = true
	if rec.has("mount"):
		el.mount = str(rec["mount"])
	if rec.has("guide"):
		el.guide = str(rec["guide"])
	if rec.has("bore_mm"):
		el.bore_mm = float(rec["bore_mm"])
	if rec.has("rod_mm"):
		el.rod_mm = float(rec["rod_mm"])
	if rec.has("stroke_mm"):
		el.stroke_mm = float(rec["stroke_mm"])
	# Согласовать action / порты / ряды ISO.
	var Catalog = preload("res://scripts/domain/cylinder_catalog.gd")
	Catalog.conform(el)
	return true


static func _load_recipes() -> void:
	_recipes.clear()
	_recipe_order = PackedStringArray()
	if not FileAccess.file_exists(RECIPES_PATH):
		push_warning("Cylinder recipes missing: %s" % RECIPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid cylinder recipes JSON")
		return
	var list: Array = parsed.get("recipes", [])
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rid := str(item.get("id", ""))
		if rid == "":
			continue
		_recipes[rid] = item
		_recipe_order.append(rid)
