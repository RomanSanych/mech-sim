class_name ValveLibrary
extends RefCounted
## Каталог клеток золотника (envelopes) и рецептов готовых ПР.
## AS BD не используется — только data/valves/*.json.

const ENVELOPES_PATH := "res://data/valves/envelopes.json"
const RECIPES_PATH := "res://data/valves/recipes.json"

static var _ready := false
static var _envelopes: Dictionary = {} # id -> Dictionary
static var _recipes: Dictionary = {} # id -> Dictionary
static var _envelope_order: PackedStringArray = PackedStringArray()
static var _recipe_order: PackedStringArray = PackedStringArray()


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	_load_envelopes()
	_load_recipes()


static func envelope(id: String) -> Dictionary:
	ensure_loaded()
	if _envelopes.has(id):
		return (_envelopes[id] as Dictionary).duplicate(true)
	return {}


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


static func envelopes_for_ways(ways: int) -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _envelope_order:
		if _envelope_ok(id, ways):
			out.append(envelope(id))
	return out


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var rec := recipe(id)
	if rec.is_empty():
		return false
	el.recipe_id = str(rec.get("id", id))
	el.valve_ways = int(rec.get("ways", 5))
	el.valve_positions = int(rec.get("positions", 2))
	if rec.has("valve_center"):
		el.valve_center = str(rec["valve_center"])
	elif int(el.valve_positions) != 3:
		el.valve_center = "none"
	if rec.has("valve_nc_no"):
		el.valve_nc_no = str(rec["valve_nc_no"])
	if rec.has("op_left"):
		el.op_left = str(rec["op_left"])
	if rec.has("op_right"):
		el.op_right = str(rec["op_right"])
	if rec.has("port_3"):
		el.port_3 = str(rec["port_3"])
	if rec.has("port_5"):
		el.port_5 = str(rec["port_5"])
	if rec.has("pilot_supply"):
		el.pilot_supply = str(rec["pilot_supply"])
	el.spool_envelopes = _to_packed(rec.get("envelopes", []))
	return true


static func default_envelope_ids(el) -> PackedStringArray:
	var ways := int(el.valve_ways)
	var positions := int(el.valve_positions)
	var center := str(el.valve_center)
	var nc := str(el.valve_nc_no) == "nc"
	var out := PackedStringArray()
	match ways:
		2:
			if nc:
				out = PackedStringArray(["2_open_P_A", "2_closed"])
			else:
				out = PackedStringArray(["2_closed", "2_open_P_A"])
		3:
			if positions == 3:
				out = PackedStringArray(["3_work_P_A", _center_id_3(center), "3_rest_A_R"])
			elif nc:
				out = PackedStringArray(["3_work_P_A", "3_rest_A_R"])
			else:
				out = PackedStringArray(["3_rest_A_R", "3_work_P_A"])
		4:
			out = PackedStringArray(["4_work_P_A", "4_rest_P_B"])
		_:
			if positions == 3:
				out = PackedStringArray(["5_2_work_P_A", _center_id_5(center), "5_2_rest_P_B"])
			else:
				out = PackedStringArray(["5_2_work_P_A", "5_2_rest_P_B"])
	while out.size() < positions:
		out.append(out[out.size() - 1] if out.size() > 0 else "")
	if out.size() > positions:
		out.resize(positions)
	return out


static func normalize_spool(el) -> void:
	ensure_loaded()
	var n := maxi(int(el.valve_positions), 1)
	var cur: PackedStringArray = PackedStringArray()
	if el.get("spool_envelopes") != null:
		cur = _to_packed(el.spool_envelopes)
	var defaults := default_envelope_ids(el)
	# Пустой массив или неверная длина → рецепт, иначе дефолты ways/positions.
	if cur.is_empty() or cur.size() != n:
		var rid := str(el.get("recipe_id") if el.get("recipe_id") != null else "")
		if rid != "":
			var rec := recipe(rid)
			if not rec.is_empty() and int(rec.get("ways", -1)) == int(el.valve_ways) \
					and int(rec.get("positions", -1)) == int(el.valve_positions):
				cur = _to_packed(rec.get("envelopes", []))
		if cur.is_empty() or cur.size() != n:
			cur = defaults
	var out := PackedStringArray()
	var ways := int(el.valve_ways)
	for i in n:
		var id := str(cur[i]) if i < cur.size() else ""
		if not _envelope_ok(id, ways):
			id = defaults[i] if i < defaults.size() else ""
		out.append(id)
	el.spool_envelopes = out


static func path_pairs_from_spool(el, pos: int) -> Array:
	ensure_loaded()
	normalize_spool(el)
	var ids: PackedStringArray = el.spool_envelopes
	pos = clampi(pos, 0, maxi(ids.size() - 1, 0))
	if pos < 0 or pos >= ids.size():
		return []
	var env := envelope(str(ids[pos]))
	if env.is_empty():
		return []
	var paths: Array = env.get("paths", [])
	var out: Array = []
	for pair in paths:
		if pair is Array and pair.size() >= 2:
			out.append([str(pair[0]), str(pair[1])])
	return out


static func _center_id_5(center: String) -> String:
	match center:
		"exhausted":
			return "5_3_center_exhausted"
		"pressurized":
			return "5_3_center_pressurized"
		"floating":
			return "5_3_center_floating"
		_:
			return "5_3_center_closed"


static func _center_id_3(center: String) -> String:
	match center:
		"exhausted":
			return "3_3_center_exhausted"
		"pressurized":
			return "3_3_center_pressurized"
		_:
			return "3_3_center_closed"


static func _envelope_ok(id: String, ways: int) -> bool:
	if id == "" or not _envelopes.has(id):
		return false
	var allowed: Array = _envelopes[id].get("ways", [])
	for w in allowed:
		if int(w) == ways:
			return true
	return false


static func _to_packed(value) -> PackedStringArray:
	var out := PackedStringArray()
	if value is PackedStringArray:
		for x in value:
			out.append(str(x))
		return out
	if value is Array:
		for x in value:
			out.append(str(x))
	return out


static func _load_envelopes() -> void:
	_envelopes.clear()
	_envelope_order = PackedStringArray()
	if not FileAccess.file_exists(ENVELOPES_PATH):
		push_warning("Valve envelopes missing: %s" % ENVELOPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ENVELOPES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid envelopes JSON")
		return
	var list: Array = parsed.get("envelopes", [])
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var id := str(item.get("id", ""))
		if id == "":
			continue
		_envelopes[id] = item
		_envelope_order.append(id)


static func _load_recipes() -> void:
	_recipes.clear()
	_recipe_order = PackedStringArray()
	if not FileAccess.file_exists(RECIPES_PATH):
		push_warning("Valve recipes missing: %s" % RECIPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid recipes JSON")
		return
	var list: Array = parsed.get("recipes", [])
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var id := str(item.get("id", ""))
		if id == "":
			continue
		_recipes[id] = item
		_recipe_order.append(id)
