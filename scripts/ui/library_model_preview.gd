extends SubViewportContainer
## Компактный 3D-рендер элемента каталога для библиотеки 3D.
## Общий World3D + ленивая сборка: иначе десятки own_world_3d валят Compatibility.

const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const IsoRotary = preload("res://scripts/view3d/iso_rotary.gd")
const IsoAirMotor = preload("res://scripts/view3d/iso_air_motor.gd")
const IsoInductive = preload("res://scripts/view3d/iso_inductive.gd")
const IsoCapacitive = preload("res://scripts/view3d/iso_capacitive.gd")
const IsoReed = preload("res://scripts/view3d/iso_reed.gd")
const IsoOptical = preload("res://scripts/view3d/iso_optical.gd")
const IsoOpticalCompact = preload("res://scripts/view3d/iso_optical_compact.gd")
const IsoUltrasonic = preload("res://scripts/view3d/iso_ultrasonic.gd")
const IsoOptoTip = preload("res://scripts/view3d/iso_opto_tip.gd")
const IsoValve = preload("res://scripts/view3d/iso_valve.gd")
const IsoJunction = preload("res://scripts/view3d/iso_junction.gd")
const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const ValveLib = preload("res://scripts/domain/valve_library.gd")
const ValveCat = preload("res://scripts/domain/valve_catalog.gd")
const CylLib = preload("res://scripts/domain/cylinder_library.gd")
const RotaryLib = preload("res://scripts/domain/rotary_library.gd")
const MotorLib = preload("res://scripts/domain/motor_library.gd")
const SensorLib = preload("res://scripts/domain/sensor_library.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const IsoThrottle = preload("res://scripts/view3d/iso_throttle.gd")
const IsoCheck = preload("res://scripts/view3d/iso_check.gd")
const IsoThrottleCheck = preload("res://scripts/view3d/iso_throttle_check.gd")
const IsoShuttle = preload("res://scripts/view3d/iso_shuttle.gd")
const IsoAnd = preload("res://scripts/view3d/iso_and.gd")
const IsoReservoir = preload("res://scripts/view3d/iso_reservoir.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")

const SLOT_STRIDE := 40.0

static var _shared_world: World3D
static var _next_slot := 0

var kind := "cylinder"
var _vp: SubViewport
var _root: Node3D
var _model: Node3D
var _cam: Camera3D
var _built := false
var _building := false
var _slot := 0
var _anchor := Vector3.ZERO


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(118, 84)
	if _shared_world == null:
		_shared_world = World3D.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = UiTheme.panel_bg().lightened(0.04 if UiTheme.dark else 0.02)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.75, 0.78, 0.82)
		environment.ambient_light_energy = 0.55
		_shared_world.environment = environment
	_slot = _next_slot
	_next_slot += 1
	_anchor = Vector3(float(_slot) * SLOT_STRIDE, 0.0, 0.0)

	_vp = SubViewport.new()
	_vp.size = Vector2i(maxi(int(custom_minimum_size.x), 96), maxi(int(custom_minimum_size.y), 72))
	_vp.transparent_bg = true
	_vp.own_world_3d = false
	_vp.world_3d = _shared_world
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	_root = Node3D.new()
	_root.position = _anchor
	_vp.add_child(_root)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-42, 48, 0)
	_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(18, -130, 0)
	_root.add_child(fill)

	_model = Node3D.new()
	_root.add_child(_model)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 32.0
	_root.add_child(_cam)
	# Лениво: собрать модель при первом показе, не при создании всех строк сразу.
	set_process(true)


func set_kind(k: String) -> void:
	kind = k
	_built = false
	if is_inside_tree() and is_visible_in_tree():
		ensure_built()


func ensure_built() -> void:
	if _built or _building:
		return
	if not is_inside_tree():
		return
	_rebuild_model()


func _process(_delta: float) -> void:
	if _built or _building:
		set_process(false)
		return
	if is_visible_in_tree() and size.x > 2.0 and size.y > 2.0:
		ensure_built()
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree() and not _built:
			set_process(true)
	elif what == NOTIFICATION_RESIZED and _vp != null:
		var s := Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 48))
		if _vp.size != s:
			_vp.size = s
			if _built:
				_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				call_deferred("_arm_when_visible")


func _rebuild_model() -> void:
	if _model == null or _vp == null:
		return
	_building = true
	while _model.get_child_count() > 0:
		var child := _model.get_child(0)
		_model.remove_child(child)
		child.queue_free()
	var el: PreviewEl = _make_element(kind)
	match el.kind:
		"valve":
			IsoValve.build(_model, el, null)
		"junction":
			IsoJunction.build(_model, el)
		"electro":
			IsoElectro.build(_model, el)
		"coil":
			Parts.add_coil_on_tube(_model, 0.0, 1.0, 0.04)
		"accessory":
			_build_accessory_proxy(_model, el)
		"rotary_cylinder":
			IsoRotary.build(_model, el)
		"air_motor":
			IsoAirMotor.build(_model, el)
		"sensor":
			if str(el.sensor_class) == "reed":
				IsoReed.build(_model, el)
			elif str(el.sensor_class) == "capacitive":
				IsoCapacitive.build(_model, el)
			elif str(el.sensor_class) == "optical":
				if str(el.optical_form) == "compact":
					IsoOpticalCompact.build(_model, el)
				else:
					IsoOptical.build(_model, el)
			elif str(el.sensor_class) == "ultrasonic":
				IsoUltrasonic.build(_model, el)
			elif str(el.sensor_class) == "rtd":
				preload("res://scripts/view3d/iso_rtd.gd").build(_model, el)
			elif str(el.sensor_class) == "pressure_tx":
				preload("res://scripts/view3d/iso_pressure_tx.gd").build(_model, el)
			elif str(el.sensor_class) == "pressure_switch":
				preload("res://scripts/view3d/iso_pressure_switch.gd").build(_model, el)
			else:
				IsoInductive.build(_model, el)
		"opto_tip":
			IsoOptoTip.build(_model, el)
		_:
			Iso.build(_model, el)
	_hide_tags(_model)
	_frame_camera()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_built = true
	_building = false
	call_deferred("_arm_when_visible")


func _arm_when_visible() -> void:
	if _vp == null or not is_instance_valid(_vp):
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _build_accessory_proxy(parent: Node3D, el) -> void:
	var cls := str(el.accessory_class)
	if cls in ["throttle", "throttle_fixed"]:
		IsoThrottle.build(parent, el)
		return
	if cls == "check":
		IsoCheck.build(parent, el)
		return
	if cls in ["throttle_check", "throttle_check_fixed"]:
		IsoThrottleCheck.build(parent, el)
		return
	if cls == "shuttle":
		IsoShuttle.build(parent, el)
		return
	if cls == "and_valve":
		IsoAnd.build(parent, el)
		return
	if cls == "relief":
		const IsoRelief = preload("res://scripts/view3d/iso_relief.gd")
		IsoRelief.build(parent, el)
		return
	if cls == "quick_exhaust":
		const IsoQuickExhaust = preload("res://scripts/view3d/iso_quick_exhaust.gd")
		IsoQuickExhaust.build(parent, el)
		return
	if cls == "reservoir":
		IsoReservoir.build(parent, el)
		return
	if cls == "regulator":
		const IsoRegulator = preload("res://scripts/view3d/iso_regulator.gd")
		IsoRegulator.build(parent, el)
		return
	# Прокси 3D до отдельных моделей остальных аксессуаров.
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	if cls == "frl":
		box.size = Vector3(Parts.mm(55.0), Parts.mm(40.0), Parts.mm(40.0))
	else:
		box.size = Vector3(Parts.mm(36.0), Parts.mm(28.0), Parts.mm(28.0))
	body.mesh = box
	body.material_override = Parts.mat("acc_proxy", Color(0.78, 0.82, 0.86), 0.15, 0.55)
	parent.add_child(body)


func _hide_tags(node: Node) -> void:
	if node is Label3D:
		(node as Label3D).visible = false
	for child in node.get_children():
		_hide_tags(child)


func _frame_camera() -> void:
	var box := _compute_aabb(_model, Transform3D.IDENTITY)
	if box.size.length() < 1.0e-5:
		_cam.position = Vector3(0.18, 0.12, 0.22)
		_cam.look_at(Vector3.ZERO, Vector3.UP)
		return
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.02)
	var dist := radius * 2.35
	_cam.position = center + Vector3(dist * 0.72, dist * 0.48, dist * 0.88)
	_cam.look_at(center, Vector3.UP)
	_cam.near = 0.01
	_cam.far = maxf(dist * 8.0, 4.0)


func _compute_aabb(node: Node, xf: Transform3D) -> AABB:
	var local_xf := xf
	if node is Node3D:
		local_xf = xf * (node as Node3D).transform
	var acc := AABB()
	var any := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb := mi.mesh.get_aabb()
			var pts := [
				local_xf * mesh_aabb.position,
				local_xf * (mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, 0)),
				local_xf * (mesh_aabb.position + Vector3(0, mesh_aabb.size.y, 0)),
				local_xf * (mesh_aabb.position + Vector3(0, 0, mesh_aabb.size.z)),
				local_xf * (mesh_aabb.position + Vector3(mesh_aabb.size.x, mesh_aabb.size.y, 0)),
				local_xf * (mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, mesh_aabb.size.z)),
				local_xf * (mesh_aabb.position + Vector3(0, mesh_aabb.size.y, mesh_aabb.size.z)),
				local_xf * (mesh_aabb.position + mesh_aabb.size),
			]
			for p in pts:
				if not any:
					acc = AABB(p, Vector3.ZERO)
					any = true
				else:
					acc = acc.expand(p)
	for child in node.get_children():
		var child_aabb := _compute_aabb(child, local_xf)
		if child_aabb.size.length_squared() > 0.0:
			if not any:
				acc = child_aabb
				any = true
			else:
				acc = acc.merge(child_aabb)
	return acc if any else AABB()


func _make_element(k: String) -> PreviewEl:
	var el := PreviewEl.new()
	el.kind = k
	if k.begins_with("valve@"):
		el.recipe_id = k.substr(6)
		el.kind = "valve"
		el.tag = "Р1"
		el.tag_prefix = "Р"
		ValveLib.apply_recipe(el, el.recipe_id)
		ValveCat.conform(el)
		el.valve_pos = int(el.rest_pos)
	elif k.begins_with("cylinder@"):
		el.recipe_id = k.substr(9)
		el.kind = "cylinder"
		el.tag = "Ц1"
		el.tag_prefix = "Ц"
		CylLib.apply_recipe(el, el.recipe_id)
	elif k.begins_with("rotary_cylinder@"):
		el.recipe_id = k.substr(16)
		el.kind = "rotary_cylinder"
		el.tag = "ППЦ1"
		el.tag_prefix = "ППЦ"
		RotaryLib.apply_recipe(el, el.recipe_id)
	elif k.begins_with("air_motor@"):
		el.recipe_id = k.substr(10)
		el.kind = "air_motor"
		el.tag = "ПМ1"
		el.tag_prefix = "ПМ"
		MotorLib.apply_recipe(el, el.recipe_id)
	elif k.begins_with("sensor@"):
		el.recipe_id = k.substr(7)
		el.kind = "sensor"
		el.tag = "SQ1"
		el.tag_prefix = "SQ"
		SensorLib.apply_recipe(el, el.recipe_id)
	elif k.begins_with("accessory@"):
		el.recipe_id = k.substr(10)
		el.kind = "accessory"
		AccLib.apply_recipe(el, el.recipe_id)
		el.tag_prefix = AccLib.gost_tag_prefix(el)
		el.tag = "%s1" % el.tag_prefix
	elif k.begins_with("junction@"):
		el.junction_style = k.substr(9)
		el.kind = "junction"
		el.tag = "У1"
		el.tag_prefix = "У"
		if el.junction_style == "adapter":
			el.junction_ports = 2
			el.tube_od_mm = 6.0
			el.tube_od_b_mm = 8.0
			el.port_name = TubeFit.thread_for_tube_od(6.0)
		elif el.junction_style == "manifold":
			el.junction_ports = 5
		else:
			el.junction_ports = 3
	elif k.begins_with("rail@"):
		el.kind = "rail"
		el.tag = ""
		el.rail_domain = "pneumatic" if k.substr(5) == "pneumatic" else "electric"
		el.rail_points = Rail2D.default_points()
		el.rail_taps = []
	elif k == "valve":
		el.tag = "Р1"
		el.tag_prefix = "Р"
		ValveLib.apply_recipe(el, "5_2_sol_spring")
		ValveCat.conform(el)
		el.valve_pos = int(el.rest_pos)
	elif k.begins_with("electro@"):
		el.recipe_id = k.substr(8)
		el.kind = "electro"
		ElectroLib.apply_recipe(el, el.recipe_id)
		el.tag = "%s1" % el.tag_prefix
	elif k == "coil":
		el.kind = "electro"
		el.tag = "Р1L"
		ElectroLib.apply_recipe(el, "solenoid_coil")
	elif k == "source":
		el.kind = "source"
		el.tag = "КМ1"
		el.tag_prefix = "КМ"
	else:
		el.kind = "cylinder"
		el.tag = "Ц1"
		el.tag_prefix = "Ц"
		CylLib.apply_recipe(el, "da_basic")
	return el


class PreviewEl extends RefCounted:
	var kind := "cylinder"
	var tag := ""
	var rail_domain := "electric"
	var rail_points: PackedVector2Array = PackedVector2Array()
	var rail_taps: Array = []
	var action := "double"
	var bore_mm := 32.0
	var rod_mm := 12.0
	var stroke_mm := 100.0
	var body_style := "profile"
	var body_style_user := false
	var rod_mode := "single"
	var through_rod := false
	var spring_side := "none"
	var rod_end := "plain"
	var brake := "none"
	var cush_cap := "none"
	var cush_rod := "none"
	var cush_open_cap := 0.35
	var cush_open_rod := 0.35
	var piston_kind := "simple"
	var carriage := "none"
	var mount := "clevis"
	var guide := "none"
	var bump_end := "none"
	var seal_leak := 0.0
	var port_name := "G1/8"
	var fitting_id := "G1/8_6"
	var tube_od_mm := 6.0
	var tube_od_b_mm := 0.0
	var rod_thread := "M10x1.25"
	var port_cap := "connect"
	var port_rod := "connect"
	var cushion := false
	var cushion_mm := 0.0
	var spring_rate := 0.0
	var spring_preload := 0.0
	var mass_kg := 1.0
	var friction_n := 10.0
	var order_code := ""
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
	var port_3 := "muffler"
	var port_5 := "muffler"
	var override_left := true
	var override_right := true
	var recipe_id := ""
	var catalog_id := "generic"
	var spool_envelopes: PackedStringArray = PackedStringArray()
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
	var port_press := {}
	var command_left := false
	var command_right := false
	var x := 0.0
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
