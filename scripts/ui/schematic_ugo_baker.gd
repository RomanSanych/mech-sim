extends Node
## Запекание одного УГО схемы в Texture2D. Канон — SymbolGeom._draw.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")

signal baked(el_id: int, texture: Texture2D, local_origin: Vector2)

var _vp: SubViewport
var _drawer: Control
var _busy: bool = false
var _queue: Array = [] # {id, el_ref, font, omit_motion, dark}
var _pending: Dictionary = {} # id -> true


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.name = "UgoBakeVP"
	_vp.transparent_bg = true
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_drawer = _UgoDrawer.new()
	_vp.add_child(_drawer)
	set_process(true)


func invalidate(el_id: int = -1) -> void:
	if el_id < 0:
		_queue.clear()
		_pending.clear()
		return
	_pending.erase(el_id)
	var i: int = 0
	while i < _queue.size():
		if int(_queue[i].get("id", -1)) == el_id:
			_queue.remove_at(i)
		else:
			i += 1


func request_bake(el, font: Font, omit_motion: bool) -> void:
	if el == null or _drawer == null:
		return
	var eid: int = int(el.id)
	if _pending.has(eid):
		return
	_pending[eid] = true
	_queue.append({
		"id": eid,
		"el": el,
		"font": font,
		"omit_motion": omit_motion,
		"dark": UiTheme.dark,
	})


func _process(_dt: float) -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	var job: Dictionary = _queue.pop_front()
	_run_bake(job)


func _run_bake(job: Dictionary) -> void:
	var eid: int = int(job.get("id", -1))
	var el = job.get("el", null)
	var font: Font = job.get("font", null) as Font
	var omit_motion: bool = bool(job.get("omit_motion", false))
	if el == null or not is_instance_valid(_vp):
		_pending.erase(eid)
		_busy = false
		return
	var saved_pos: Vector2 = el.position
	el.position = Vector2.ZERO
	var box: Rect2 = Geom.world_bounds(el).grow(6.0)
	if box.size.x < 4.0 or box.size.y < 4.0:
		box = Rect2(-40, -40, 80, 80)
	el.position = saved_pos
	var w: int = clampi(int(ceil(box.size.x)), 8, 1024)
	var h: int = clampi(int(ceil(box.size.y)), 8, 1024)
	_vp.size = Vector2i(w, h)
	_drawer.set("el", el)
	_drawer.set("font", font)
	_drawer.set("omit_motion", omit_motion)
	_drawer.set("local_origin", box.position)
	_drawer.set("bake_size", Vector2(float(w), float(h)))
	_drawer.size = Vector2(w, h)
	_drawer.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var tree := get_tree()
	if tree == null:
		_pending.erase(eid)
		_busy = false
		return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(_vp):
		var tex := _vp.get_texture()
		if tex != null:
			img = tex.get_image()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_pending.erase(eid)
	if img != null and not img.is_empty():
		var out := ImageTexture.create_from_image(img)
		baked.emit(eid, out, box.position)
	_busy = false


class _UgoDrawer extends Control:
	var el = null
	var font: Font = null
	var omit_motion: bool = false
	var local_origin: Vector2 = Vector2.ZERO
	var bake_size: Vector2 = Vector2(64, 64)

	func _draw() -> void:
		if el == null:
			return
		var saved: Vector2 = el.position
		el.position = Vector2.ZERO
		Geom.begin_sch_layer_draw(1.0, Vector2.ZERO, true, [], 0.0)
		if UiTheme.dark:
			Geom.begin_preview_ink(UiTheme.preview_ink())
		draw_set_transform(-local_origin, 0.0, Vector2.ONE)
		Geom.draw_element(self, el, font, false, false, "", "", omit_motion)
		if UiTheme.dark:
			Geom.end_preview_ink()
		Geom.end_sch_layer_draw()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		el.position = saved
