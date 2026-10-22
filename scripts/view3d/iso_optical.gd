class_name IsoOptical
extends RefCounted
## 3D оптический усилитель FD3-класс: корпус, OPT, кабель, панель SET/PV, кнопки, OUT LED.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
const DispFont = preload("res://scripts/domain/sensor_display_font.gd")

## Дисплей SET/PV: 000…999 (как Lanbao FD3). 100% уставки → 999.
const DISP_SCALE := 9.99
const DISP_MAX := 999


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var len_mm: float = maxf(float(el.stroke_mm), 60.0)
	var body_l: float = Parts.mm(len_mm)
	var body_w: float = Parts.mm(32.0)
	var body_h: float = Parts.mm(52.0)
	var plastic := Parts.mat("opt_body", Color(0.14, 0.16, 0.2), 0.08, 0.62)
	var accent := Parts.mat("opt_accent", Color(0.72, 0.78, 0.22), 0.05, 0.55)
	var metal := Parts.mat("opt_socket", Color(0.55, 0.56, 0.58), 0.75, 0.35)
	var fiber_mat := Parts.mat("opt_fiber", Color(0.05, 0.05, 0.06), 0.02, 0.75)
	var panel := Parts.mat("opt_panel", Color(0.08, 0.09, 0.11), 0.05, 0.7)
	var btn := Parts.mat("opt_btn", Color(0.22, 0.24, 0.28), 0.1, 0.55)

	Parts.box(parent, Vector3(body_l, body_h, body_w), Vector3.ZERO, plastic, "shell")
	Parts.box(
		parent,
		Vector3(Parts.mm(2.2), body_h * 0.5, body_w * 0.62),
		Vector3(body_l * 0.5 - Parts.mm(3.2), 0.0, 0.0),
		accent,
		"shell"
	)
	parent.set_meta("detect_material", "plastic")

	# Верхняя панель (как FD3 / dual-display): PV (факт) + SET (уставка).
	var pan_y: float = body_h * 0.5 + Parts.mm(0.6)
	Parts.box(parent, Vector3(body_l * 0.72, Parts.mm(1.2), body_w * 0.78), Vector3(0.0, pan_y, 0.0), panel, "control")
	_add_digit_display(parent, "DispPV", Vector3(-Parts.mm(10.0), pan_y + Parts.mm(1.2), 0.0), Color(1.0, 0.25, 0.12))
	_add_digit_display(parent, "DispSET", Vector3(Parts.mm(10.0), pan_y + Parts.mm(1.2), 0.0), Color(0.2, 0.95, 0.35))
	# Кнопки: MODE / SET (мелкие) + две кнопки уставки + / − (крупнее).
	var by: float = pan_y + Parts.mm(0.4)
	var bz: float = body_w * 0.28
	_add_panel_button(parent, "BtnMode", Vector3(-Parts.mm(14.0), by, bz), btn, Parts.mm(1.8))
	_add_panel_button(parent, "BtnSet", Vector3(-Parts.mm(5.0), by, bz), btn, Parts.mm(1.8))
	_add_panel_button(parent, "BtnPlus", Vector3(Parts.mm(5.5), by, bz), btn, Parts.mm(2.6))
	_add_panel_button(parent, "BtnMinus", Vector3(Parts.mm(14.5), by, bz), btn, Parts.mm(2.6))
	# OUT LED на торце панели.
	var out_led := MeshInstance3D.new()
	out_led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(1.8)
	sph.height = Parts.mm(3.6)
	out_led.mesh = sph
	out_led.position = Vector3(body_l * 0.28, pan_y + Parts.mm(2.0), -body_w * 0.22)
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.35, 0.08, 0.08)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.15, 0.02, 0.02)
	led_mat.emission_energy_multiplier = 0.2
	out_led.material_override = led_mat
	out_led.set_meta("xray_role", "control")
	parent.add_child(out_led)

	# Разъёмы оптоволокна спереди (+X).
	var sock_y: float = body_h * 0.12
	var sock_x: float = body_l * 0.5 + Parts.mm(2.0)
	for i in 2:
		var sy: float = sock_y if i == 0 else -sock_y
		var c := Vector3(sock_x, sy, 0.0)
		Parts.cyl(parent, Parts.mm(3.2), Parts.mm(6.0), c, "x", metal, 12, "shell")
		var tip := Vector3(sock_x + Parts.mm(5.5), sy, 0.0)
		Parts.cyl(parent, Parts.mm(1.1), Parts.mm(5.0), tip, "x", fiber_mat, 10, "shell")
		var pname: String = "OPT1" if i == 0 else "OPT2"
		info["ports"][pname] = tip + Vector3(Parts.mm(2.5), 0.0, 0.0)
		info["dirs"][pname] = Vector3.RIGHT

	# Электрокабель + винт уставки на ЗАДНЕМ торце (−X).
	var cable_r: float = Parts.mm(2.6)
	var cable_stub_l: float = Parts.mm(12.0)
	var cable_mat: Material = Parts.mat("opt_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)
	var x_rear0: float = -body_l * 0.5
	var cable_c: float = x_rear0 - cable_stub_l * 0.45
	Parts.cyl(parent, cable_r, cable_stub_l, Vector3(cable_c, 0.0, 0.0), "x", cable_mat, 12, "shell")
	var cable_tip := Vector3(x_rear0 - cable_stub_l * 0.95, 0.0, 0.0)
	Parts.cyl(parent, cable_r * 1.02, Parts.mm(1.2), cable_tip + Vector3(Parts.mm(0.4), 0.0, 0.0), "x", cable_mat, 14, "shell")
	parent.set_meta("cable_exit_local", cable_tip)
	parent.set_meta("cable_exit_dir", Vector3.LEFT)
	info["ports"]["+"] = cable_tip
	info["ports"]["OUT"] = cable_tip
	info["ports"]["0"] = cable_tip
	info["dirs"]["+"] = Vector3.LEFT
	info["dirs"]["OUT"] = Vector3.LEFT
	info["dirs"]["0"] = Vector3.LEFT
	# Уставка только кнопками +/− на панели (винта на усилителе нет).

	var zone := MeshInstance3D.new()
	zone.name = "SenseZone"
	zone.visible = false
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	parent.add_child(zone)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 16
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(18.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_optical", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(18.0), -body_h * 0.5 - Parts.mm(4.0), -body_w * 0.5 - Parts.mm(4.0)),
		Vector3(body_l + Parts.mm(36.0), body_h + Parts.mm(22.0), body_w + Parts.mm(8.0))
	))
	apply_led(parent, el)
	apply_zone_viz(parent, el, false)
	apply_panel(parent, el, null)
	return info


static func _add_digit_display(parent: Node3D, name: String, center: Vector3, col: Color) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = center
	parent.add_child(root)
	var frame := Parts.mat("opt_disp_fr", Color(0.05, 0.05, 0.06), 0.05, 0.8)
	Parts.box(root, Vector3(Parts.mm(14.0), Parts.mm(0.8), Parts.mm(8.0)), Vector3.ZERO, frame, "control")
	var lab := Label3D.new()
	lab.name = "Text"
	lab.text = "000"
	lab.font = DispFont.get_font()
	lab.font_size = 28
	lab.pixel_size = 0.0002
	lab.modulate = col
	lab.position = Vector3(0.0, Parts.mm(1.0), 0.0)
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lab.set_meta("xray_role", "control")
	root.add_child(lab)


static func _add_panel_button(parent: Node3D, name: String, center: Vector3, mat: Material, radius: float = -1.0) -> void:
	var n := Node3D.new()
	n.name = name
	n.position = center
	n.set_meta("amp_button", true)
	parent.add_child(n)
	var r: float = radius if radius > 0.0 else Parts.mm(2.2)
	Parts.cyl(n, r, Parts.mm(1.8), Vector3.ZERO, "y", mat, 10, "control")


static func display_set_value(el) -> int:
	if el == null:
		return 0
	return clampi(int(round(clampf(float(el.threshold_pct), 0.0, 100.0) * DISP_SCALE)), 0, DISP_MAX)


static func set_display_set_value(el, n: int) -> void:
	if el == null:
		return
	el.threshold_pct = clampf(float(clampi(n, 0, DISP_MAX)) / DISP_SCALE, 0.0, 100.0)


## Один тик уставки на дисплее (±1), как кнопки +/− на FD3.
static func nudge_setpoint(el, delta_ticks: int) -> void:
	if el == null or delta_ticks == 0:
		return
	set_display_set_value(el, display_set_value(el) + delta_ticks)


static func apply_panel(root: Node3D, el, circuit = null) -> void:
	if root == null or el == null:
		return
	var set_n: int = display_set_value(el)
	var pv_n: int = 0
	if circuit != null:
		pv_n = SensorDetect.optical_signal_level(circuit, el)
	elif bool(el.pressed) or bool(el.lit):
		pv_n = mini(set_n + 80, DISP_MAX)
	var disp_set: Node3D = root.get_node_or_null("DispSET") as Node3D
	var disp_pv: Node3D = root.get_node_or_null("DispPV") as Node3D
	if disp_set != null:
		var tset: Label3D = disp_set.get_node_or_null("Text") as Label3D
		if tset != null:
			tset.text = "%03d" % set_n
	if disp_pv != null:
		var tpv: Label3D = disp_pv.get_node_or_null("Text") as Label3D
		if tpv != null:
			tpv.text = "%03d" % pv_n


static func apply_led(root: Node3D, el) -> void:
	if root == null:
		return
	var led: MeshInstance3D = root.get_node_or_null("SensorLed") as MeshInstance3D
	if led == null:
		return
	var mat: StandardMaterial3D = led.material_override as StandardMaterial3D
	if mat == null:
		return
	var on: bool = bool(el.lit) or bool(el.pressed)
	if on:
		mat.albedo_color = Color(1.0, 0.15, 0.08)
		mat.emission = Color(1.0, 0.25, 0.05)
		mat.emission_energy_multiplier = 3.5
	else:
		mat.albedo_color = Color(0.35, 0.08, 0.08)
		mat.emission = Color(0.12, 0.02, 0.02)
		mat.emission_energy_multiplier = 0.15


static func apply_zone_viz(root: Node3D, el, on: bool) -> void:
	if root == null:
		return
	var zone: MeshInstance3D = root.get_node_or_null("SenseZone") as MeshInstance3D
	if zone != null:
		zone.visible = false
	root.set_meta("optical_zone_on", bool(on))
	root.set_meta("optical_zone_color", SensorDetect.zone_viz_color(el))
