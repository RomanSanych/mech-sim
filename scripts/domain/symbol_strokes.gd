extends RefCounted
## Loads committed stroke/layout JSON extracted from Automation Studio taxonomy pipeline.

const DEFAULT_PATH := "res://data/symbols/verin_default.json"

static var _data: Dictionary = {}
static var _ready := false


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	if not FileAccess.file_exists(DEFAULT_PATH):
		push_warning("Symbol strokes missing: %s" % DEFAULT_PATH)
		return
	var text := FileAccess.get_file_as_string(DEFAULT_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid symbol strokes JSON")
		return
	_data = parsed


static func layout(key: String, fallback: float) -> float:
	ensure_loaded()
	var layout_dict: Dictionary = _data.get("layout", {})
	if layout_dict.has(key):
		return float(layout_dict[key])
	return fallback


static func hit_zones_template() -> Array:
	ensure_loaded()
	var zones: Array = _data.get("hit_zones", [])
	return zones.duplicate(true)


static func meta_id() -> String:
	ensure_loaded()
	return str(_data.get("id", ""))


static func has_layer(layer_key: String) -> bool:
	ensure_loaded()
	var layers: Dictionary = _data.get("layers", {})
	return layers.has(layer_key)


static func reload() -> void:
	_ready = false
	_data = {}
	ensure_loaded()


## Flat polylines from AS DXF/EMF import (exact assembled UGO).
static func imported_strokes() -> Array:
	ensure_loaded()
	var list: Array = _data.get("strokes", [])
	return list


static func has_imported_strokes() -> bool:
	return not imported_strokes().is_empty()


static func layer_polylines(layer_key: String) -> Array:
	ensure_loaded()
	var layers: Dictionary = _data.get("layers", {})
	if not layers.has(layer_key):
		return []
	var layer: Variant = layers[layer_key]
	if typeof(layer) != TYPE_DICTIONARY:
		return []
	var strokes: Array = layer.get("strokes", [])
	return strokes
