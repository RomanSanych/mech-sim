extends Node
## Один SubViewport для 2D-УГО превью библиотеки. Без роя Control._draw(Geom).

signal thumb_ready(kind: String, texture: Texture2D)

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const ValveLib = preload("res://scripts/domain/valve_library.gd")
const ValveCat = preload("res://scripts/domain/valve_catalog.gd")
const CylLib = preload("res://scripts/domain/cylinder_library.gd")
const RotaryLib = preload("res://scripts/domain/rotary_library.gd")
const MotorLib = preload("res://scripts/domain/motor_library.gd")
const SensorLib = preload("res://scripts/domain/sensor_library.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")

const THUMB_SIZE := Vector2i(118, 84)

var _vp: SubViewport
var _drawer: Control
var _queue: Array[String] = []
var _cache: Dictionary = {} # kind -> Texture2D
var _busy := false
var _pending: Dictionary = {} # kind -> true
var _active := false


func set_active(on: bool) -> void:
	_active = on


func is_active() -> bool:
	return _active


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = THUMB_SIZE
	_vp.transparent_bg = true
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_drawer = _Drawer.new()
	_drawer.size = Vector2(THUMB_SIZE)
	_vp.add_child(_drawer)
	set_process(true)


func get_cached(kind: String) -> Texture2D:
	return _cache.get(kind, null)


func cache_size() -> int:
	return _cache.size()


func request(kind: String) -> void:
	if kind == "" or _cache.has(kind) or _pending.has(kind):
		return
	_pending[kind] = true
	_queue.append(kind)


func has_work() -> bool:
	return _busy or not _queue.is_empty()


func pending_total() -> int:
	return _queue.size() + (1 if _busy else 0)


func warm_queue() -> void:
	while has_work():
		if not await bake_next():
			return
	if not await _await_frame():
		return


func bake_next() -> bool:
	## Один kind за вызов. Возвращает false если дерево снято.
	if _busy or _queue.is_empty():
		return is_instance_valid(self) and is_inside_tree()
	_busy = true
	var kind := str(_queue.pop_front())
	await _run_bake(kind)
	return is_instance_valid(self) and is_inside_tree()


func _await_frame() -> bool:
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	await tree.process_frame
	return is_instance_valid(self) and is_inside_tree()


func _process(_delta: float) -> void:
	if not _active or _busy or _queue.is_empty():
		return
	if not is_inside_tree():
		return
	_busy = true
	var kind := str(_queue.pop_front())
	_run_bake(kind)


func _run_bake(kind: String) -> void:
	if _drawer == null or _vp == null or not is_inside_tree():
		_pending.erase(kind)
		_busy = false
		return
	(_drawer as _Drawer).kind = kind
	_drawer.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not await _await_frame():
		_pending.erase(kind)
		_busy = false
		return
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(_vp):
		var tex := _vp.get_texture()
		if tex != null:
			img = tex.get_image()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_pending.erase(kind)
	if img != null and not img.is_empty():
		var out := ImageTexture.create_from_image(img)
		_cache[kind] = out
		thumb_ready.emit(kind, out)
	# Idle после get_image/create — разгрузить кадр.
	if not await _await_frame():
		_busy = false
		return
	_busy = false


class _Drawer extends Control:
	var kind := "cylinder"

	func _draw() -> void:
		var el := _PreviewEl.new(kind)
		var font := get_theme_default_font()
		var box: Rect2 = Geom.library_bounds(el)
		var pad := 3.0
		var sx := (size.x - pad * 2.0) / maxf(box.size.x, 1.0)
		var sy := (size.y - pad * 2.0) / maxf(box.size.y, 1.0)
		var s := minf(sx, sy)
		var origin := size * 0.5 - box.get_center() * s
		Geom.begin_library_preview(UiTheme.preview_ink(), s)
		draw_set_transform(origin, 0.0, Vector2(s, s))
		Geom.draw_element(self, el, font, false, false, "")
		Geom.end_library_preview()


class _PreviewEl extends RefCounted:
	var kind: String
	var tag := ""
	var position := Vector2.ZERO
	var rotation_quad := 0
	var rail_domain := "electric"
	var rail_points: PackedVector2Array = PackedVector2Array()
	var rail_taps: Array = []
	var rail_tap_seq := 0
	var tag_offset := Vector2.ZERO
	var action := "double"
	var x := 0.0
	var stroke_mm := 100.0
	var bore_mm := 32.0
	var rod_mm := 12.0
	var spring_side := "none"
	var spring_rate := 0.0
	var spring_preload := 0.0
	var rod_mode := "single"
	var through_rod := false
	var rod_end := "plain"
	var rod_thread := "M10×1.25"
	var piston_kind := "simple"
	var cush_cap := "none"
	var cush_rod := "none"
	var cush_open_cap := 0.35
	var cush_open_rod := 0.35
	var cushion := false
	var cushion_mm := 0.0
	var brake := "none"
	var carriage := "none"
	var bump_end := "none"
	var mount := "clevis"
	var guide := "none"
	var seal_leak := 0.0
	var body_style := "profile"
	var body_style_user := false
	var port_cap := "connect"
	var port_rod := "connect"
	var catalog_id := "generic"
	var mass_kg := 0.22
	var friction_n := 10.0
	var p_cap := 101325.0
	var p_rod := 101325.0
	var pressure_bar := 6.0
	var valve_ways := 5
	var valve_positions := 2
	var valve_center := "none"
	var valve_nc_no := "nc"
	var valve_pos := 1
	var rest_pos := 1
	var op_left := "solenoid_pilot"
	var op_right := "spring"
	var pilot_supply := "internal"
	var valve_cv := 1.0
	var port_name := "G1/8"
	var fitting_id := "G1/8_6"
	var tube_od_mm := 6.0
	var tube_od_b_mm := 0.0
	var order_code := ""
	var command_left := false
	var command_right := false
	var port_3 := "muffler"
	var port_5 := "muffler"
	var recipe_id := ""
	var spool_envelopes: PackedStringArray = PackedStringArray()
	var port_press := {}
	var junction_style := "tee"
	var junction_ports := 3
	var accessory_class := ""
	var opening := 1.0
	var volume_l := 1.0
	var reservoir_ports := 1
	var set_pressure_bar := 6.0
	var regulator_unlocked := false
	var crack_pressure_bar := 0.2
	var flow_nl_min := 600.0
	var rotary_class := ""
	var angle_max_deg := 180.0
	var torque_nm_at_6bar := 9.0
	var free_rpm := 0.0
	var angle := 0.0
	var omega := 0.0
	var sensor_class := ""
	var sensor_active := true
	var sense_range_mm := 4.0
	var sense_min_mm := 0.0
	var hysteresis_mm := 0.4
	var body_od_mm := 12.0
	var supply_mode := "24dc"
	var output_type := "npn"
	var contact_form := "no"
	var detect_material := ""
	var sensor_powered := false
	var sensor_target := false
	var sensor_closed := false
	var analog_kind := ""
	var wire_scheme := 3
	var analog_value := 0.0
	var temperature_c := 20.0
	var hysteresis_bar := 0.4
	var opto_role := ""
	var optical_form := "fiber"
	var optical_light_on := false
	var threshold_pct := 50.0
	var electro_class := ""
	var electro_mount := "din"
	var tag_prefix := "E"
	var lamp_color := "white"
	var btn_color := "white"
	var caption := ""
	var delay_on := 0.0
	var delay_off := 0.0
	var timer_mode := "on"
	var timer_unit := 1
	var timer_value := 1.0
	var poles := 1
	var curve := "C"
	var rating_a := 16.0
	var i_delta_ma := 30.0
	var u_min := 180.0
	var u_max := 260.0
	var phase := ""
	var voltage := 230.0
	var link_valve := false
	var group_template := ""
	var terminal_bus := false
	var color_id := ""
	var device_table_dy_left := 0.0
	var device_table_dy_right := 0.0
	var device_table_edge_left := "left"
	var device_table_edge_right := "right"
	var terminal_port_scheme := 2
	var terminal_pitch_cells := 2
	var electro_ports: Array = []
	var coil_ports: PackedStringArray = PackedStringArray()
	var contact_defs: Array = []
	var switch_positions := 2
	var switch_pos := 0
	var switch_map: Array = []
	var switch_labels: PackedStringArray = PackedStringArray()
	var energized := false
	var pressed := false
	var latching := false
	var closed := true
	var lit := false
	var timer_armed := false
	var timer_elapsed := 0.0
	var detached := false
	var hide_unused_contacts := false
	var member_role := "device"
	var member_index := 0
	var group_id := -1
	var group_tag := ""
	var linked_valve_side := ""
	var din_slot := -1
	var door_slot := -1
	var door_xy := Vector2(-1, -1)

	func _init(k: String) -> void:
		kind = k
		if k.begins_with("valve@"):
			var rid := k.substr(6)
			kind = "valve"
			tag = "Р1"
			tag_prefix = "Р"
			ValveLib.apply_recipe(self, rid)
			ValveCat.conform(self)
			valve_pos = int(rest_pos)
		elif k.begins_with("cylinder@"):
			var cid := k.substr(9)
			kind = "cylinder"
			tag = "Ц1"
			tag_prefix = "Ц"
			CylLib.apply_recipe(self, cid)
		elif k.begins_with("rotary_cylinder@"):
			var rid := k.substr(16)
			kind = "rotary_cylinder"
			tag = "ППЦ1"
			tag_prefix = "ППЦ"
			RotaryLib.apply_recipe(self, rid)
		elif k.begins_with("air_motor@"):
			var mid := k.substr(10)
			kind = "air_motor"
			tag = "ПМ1"
			tag_prefix = "ПМ"
			MotorLib.apply_recipe(self, mid)
		elif k.begins_with("sensor@"):
			var sid := k.substr(7)
			kind = "sensor"
			tag = "SQ1"
			tag_prefix = "SQ"
			SensorLib.apply_recipe(self, sid)
		elif k.begins_with("electro@"):
			var eid := k.substr(8)
			kind = "electro"
			tag = "E1"
			ElectroLib.apply_recipe(self, eid)
			tag = "%s1" % tag_prefix
		elif k.begins_with("accessory@"):
			var aid := k.substr(10)
			kind = "accessory"
			AccLib.apply_recipe(self, aid)
			tag_prefix = AccLib.gost_tag_prefix(self)
			tag = "%s1" % tag_prefix
		elif k.begins_with("junction@"):
			junction_style = k.substr(9)
			kind = "junction"
			tag = "У1"
			tag_prefix = "У"
			if junction_style == "adapter":
				junction_ports = 2
				tube_od_mm = 6.0
				tube_od_b_mm = 8.0
				port_name = TubeFit.thread_for_tube_od(6.0)
			elif junction_style == "manifold":
				junction_ports = 5
			else:
				junction_ports = 3
		elif k.begins_with("rail@"):
			kind = "rail"
			tag = ""
			rail_domain = "pneumatic" if k.substr(5) == "pneumatic" else "electric"
			rail_points = Rail2D.default_points()
			rail_taps = []
		elif k == "valve":
			tag = "Р1"
			tag_prefix = "Р"
		elif k == "coil" or k == "electro@solenoid_coil":
			kind = "electro"
			tag = "Р1L"
			ElectroLib.apply_recipe(self, "solenoid_coil")
		elif k == "source":
			tag = "КМ1"
			tag_prefix = "КМ"
		else:
			kind = "cylinder"
			tag = "Ц1"
			tag_prefix = "Ц"
			CylLib.apply_recipe(self, "da_basic")
