extends Node2D
## Призрак УГО при переносе: один _draw при создании, дальше только position (без redraw схемы).
## Табличный УГО: set_table_preview — перерисовка раскладки без мутации «живого» el до commit.

const Geom = preload("res://scripts/domain/symbol_geom.gd")

var el_id: int = -1
var _el = null
var _font: Font = null
## {dy_l, dy_r, edge_l, edge_r} — превью таблиц БП; пусто = как у el.
var _table_preview: Dictionary = {}


func setup(el, p_font: Font) -> void:
	_el = el
	_font = p_font
	el_id = int(el.id) if el != null else -1
	_table_preview.clear()
	if el != null:
		position = el.position
	modulate = Color(0.25, 0.55, 0.95, 0.5)
	z_as_relative = true
	z_index = 8
	queue_redraw()


func set_table_preview(preview: Dictionary) -> void:
	_table_preview = preview.duplicate(true)
	queue_redraw()


func _draw() -> void:
	if _el == null or _font == null:
		return
	# Рисуем в локали узла: временно обнуляем position элемента.
	var saved: Vector2 = _el.position
	_el.position = Vector2.ZERO
	var snap: Dictionary = {}
	if not _table_preview.is_empty():
		snap = {
			"dy_l": float(_el.device_table_dy_left),
			"dy_r": float(_el.device_table_dy_right),
			"edge_l": str(_el.device_table_edge_left),
			"edge_r": str(_el.device_table_edge_right),
		}
		_el.device_table_dy_left = float(_table_preview.get("dy_l", snap["dy_l"]))
		_el.device_table_dy_right = float(_table_preview.get("dy_r", snap["dy_r"]))
		_el.device_table_edge_left = str(_table_preview.get("edge_l", snap["edge_l"]))
		_el.device_table_edge_right = str(_table_preview.get("edge_r", snap["edge_r"]))
	# zoom родителя SchemeWorld — иначе подписи призрака в fs@1px и блюр.
	var z: float = 1.0
	var p: Node = get_parent()
	if p is Node2D:
		z = maxf(absf((p as Node2D).scale.x), 0.05)
	Geom.begin_sch_layer_draw(z, Vector2.ZERO, true, [], 0.0)
	Geom.draw_element(self, _el, _font, true, false, "", "", false)
	Geom.end_sch_layer_draw()
	if not snap.is_empty():
		_el.device_table_dy_left = float(snap["dy_l"])
		_el.device_table_dy_right = float(snap["dy_r"])
		_el.device_table_edge_left = str(snap["edge_l"])
		_el.device_table_edge_right = str(snap["edge_r"])
	_el.position = saved
