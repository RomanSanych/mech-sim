class_name IsoUltrasonic
extends RefCounted
## 3D ультразвуковой аналоговый датчик: корпус, мембрана, дисплей мм/SET, кабель, LED, конус зоны.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
const DispFont = preload("res://scripts/domain/sensor_display_font.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 18.0)
	var len_mm: float = maxf(float(el.stroke_mm), 60.0)
	var body_l: float = Parts.mm(len_mm)
	var body_w: float = Parts.mm(maxf(od_mm * 1.15, 28.0))
	var body_h: float = Parts.mm(maxf(od_mm * 1.05, 26.0))
	var plastic := Parts.mat("us_body", Color(0.16, 0.18, 0.22), 0.08, 0.62)
	var accent := Parts.mat("us_accent", Color(0.88, 0.72, 0.12), 0.05, 0.5)
	var face_mat := Parts.mat("us_face", Color(0.12, 0.12, 0.14), 0.15, 0.7)
	var membrane := Parts.mat("us_mem", Color(0.55, 0.56, 0.58), 0.35, 0.55)
	var panel := Parts.mat("us_panel", Color(0.06, 0.07, 0.09), 0.05, 0.75)
	var btn := Parts.mat("us_btn", Color(0.22, 0.24, 0.28), 0.1, 0.55)

	Parts.box(parent, Vector3(body_l, body_h, body_w), Vector3.ZERO, plastic, "shell")
	# Жёлтая маркировка «акустический» торец (+X).
	Parts.box(
		parent,
		Vector3(Parts.mm(2.4), body_h * 0.72, body_w * 0.72),
		Vector3(body_l * 0.5 - Parts.mm(1.0), 0.0, 0.0),
		accent,
		"shell"
	)
	Parts.box(
		parent,
		Vector3(Parts.mm(1.6), body_h * 0.55, body_w * 0.55),
		Vector3(body_l * 0.5 + Parts.mm(0.4), 0.0, 0.0),
		face_mat,
		"shell"
	)
	# Мембрана / излучатель.
	Parts.cyl(
		parent,
		Parts.mm(maxf(od_mm * 0.28, 6.0)),
		Parts.mm(2.0),
		Vector3(body_l * 0.5 + Parts.mm(1.6), 0.0, 0.0),
		"x",
		membrane,
		16,
		"shell"
	)
	parent.set_meta("detect_material", "plastic")
	parent.set_meta("sense_face_local", Vector3(body_l * 0.5 + Parts.mm(2.0), 0.0, 0.0))

	# Панель: PV (дистанция) + SET (уставка switching distance) + кнопки.
	var pan_y: float = body_h * 0.5 + Parts.mm(0.5)
	Parts.box(
		parent,
		Vector3(body_l * 0.72, Parts.mm(1.0), body_w * 0.78),
		Vector3(0.0, pan_y, 0.0),
		panel,
		"control"
	)
	_add_digit_display(parent, "DispDist", Vector3(-Parts.mm(9.0), pan_y + Parts.mm(1.0), 0.0), Color(0.2, 0.95, 0.45))
	_add_digit_display(parent, "DispSET", Vector3(Parts.mm(9.0), pan_y + Parts.mm(1.0), 0.0), Color(1.0, 0.55, 0.12))
	var by: float = pan_y + Parts.mm(0.35)
	var bz: float = body_w * 0.28
	_add_panel_button(parent, "BtnSet", Vector3(-Parts.mm(12.0), by, bz), btn, Parts.mm(1.8))
	_add_panel_button(parent, "BtnPlus", Vector3(Parts.mm(4.0), by, bz), btn, Parts.mm(2.4))
	_add_panel_button(parent, "BtnMinus", Vector3(Parts.mm(13.0), by, bz), btn, Parts.mm(2.4))

	# Кабель сзади (−X).
	var cable_r: float = Parts.mm(2.6)
	var cable_stub_l: float = Parts.mm(12.0)
	var cable_mat: Material = Parts.mat("us_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)
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

	var led := MeshInstance3D.new()
	led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(1.7)
	sph.height = Parts.mm(3.4)
	led.mesh = sph
	led.position = Vector3(x_rear0 + Parts.mm(8.0), body_h * 0.42, body_w * 0.42)
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.35, 0.08, 0.08)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.15, 0.02, 0.02)
	led_mat.emission_energy_multiplier = 0.2
	led.material_override = led_mat
	led.set_meta("xray_role", "control")
	parent.add_child(led)

	_build_zone_mesh(parent, el)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 16
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(16.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_ultrasonic", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(18.0), -body_h * 0.5 - Parts.mm(4.0), -body_w * 0.5 - Parts.mm(4.0)),
		Vector3(body_l + Parts.mm(36.0), body_h + Parts.mm(20.0), body_w + Parts.mm(8.0))
	))
	apply_led(parent, el)
	apply_zone_viz(parent, el, false)
	apply_display(parent, el, null)
	return info


static func _add_digit_display(parent: Node3D, name: String, center: Vector3, col: Color) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = center
	parent.add_child(root)
	var frame := Parts.mat("us_disp_fr", Color(0.04, 0.05, 0.06), 0.05, 0.85)
	Parts.box(root, Vector3(Parts.mm(15.0), Parts.mm(0.7), Parts.mm(8.0)), Vector3.ZERO, frame, "control")
	var lab := Label3D.new()
	lab.name = "Text"
	lab.text = "----"
	lab.font = DispFont.get_font()
	lab.font_size = 24
	lab.pixel_size = 0.0002
	lab.modulate = col
	lab.position = Vector3(0.0, Parts.mm(0.9), 0.0)
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lab.set_meta("xray_role", "control")
	root.add_child(lab)


static func _add_panel_button(parent: Node3D, name: String, center: Vector3, mat: Material, radius: float) -> void:
	var n := Node3D.new()
	n.name = name
	n.position = center
	n.set_meta("amp_button", true)
	parent.add_child(n)
	Parts.cyl(n, radius, Parts.mm(1.8), Vector3.ZERO, "y", mat, 10, "control")


static func nudge_setpoint(el, delta_mm: int) -> void:
	if el == null or delta_mm == 0:
		return
	var cur: float = SensorDetect.ultrasonic_setpoint_mm(el)
	SensorDetect.set_ultrasonic_setpoint_mm(el, cur + float(delta_mm))


static func teach_setpoint(el, circuit) -> void:
	if el == null:
		return
	var dist_mm: float = -1.0
	if circuit != null:
		dist_mm = SensorDetect.ultrasonic_distance_mm(circuit, el)
	if dist_mm < 0.0:
		return
	SensorDetect.set_ultrasonic_setpoint_mm(el, dist_mm)


static func _build_zone_mesh(parent: Node3D, el) -> void:
	var z: Dictionary = SensorDetect.zone_desc(el)
	if z.is_empty():
		return
	var zone := MeshInstance3D.new()
	zone.name = "SenseZone"
	var cyl := CylinderMesh.new()
	# Конус: узкий у мембраны → широкий на конце диапазона.
	cyl.top_radius = float(z.get("radius", 0.04))
	cyl.bottom_radius = 0.003
	cyl.height = maxf(float(z.get("length", 0.5)), 0.001)
	cyl.radial_segments = 20
	zone.mesh = cyl
	zone.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	zone.position = z.get("origin", Vector3.ZERO) as Vector3
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = SensorDetect.zone_viz_color(el)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	zone.material_override = mat
	zone.visible = false
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	parent.add_child(zone)


static func apply_display(root: Node3D, el, circuit = null) -> void:
	if root == null or el == null:
		return
	var set_mm: float = SensorDetect.ultrasonic_setpoint_mm(el)
	var disp_set: Node3D = root.get_node_or_null("DispSET") as Node3D
	if disp_set != null:
		var tset: Label3D = disp_set.get_node_or_null("Text") as Label3D
		if tset != null:
			tset.text = "%4.0f" % set_mm
			tset.modulate = Color(1.0, 0.55, 0.12)
	var disp: Node3D = root.get_node_or_null("DispDist") as Node3D
	if disp == null:
		return
	var lab: Label3D = disp.get_node_or_null("Text") as Label3D
	if lab == null:
		return
	if not bool(el.sensor_powered) and bool(el.sensor_active):
		lab.text = "----"
		lab.modulate = Color(0.45, 0.45, 0.48)
		return
	var dist_mm: float = -1.0
	if circuit != null:
		dist_mm = SensorDetect.ultrasonic_distance_mm(circuit, el)
	elif bool(el.sensor_target):
		dist_mm = set_mm
	if dist_mm < 0.0:
		lab.text = "----"
		lab.modulate = Color(0.55, 0.35, 0.15)
	else:
		lab.text = "%4.0f" % dist_mm
		lab.modulate = Color(0.2, 0.95, 0.45)


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
	if zone == null:
		return
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	zone.visible = bool(on)
	if not on:
		return
	var z: Dictionary = SensorDetect.zone_desc(el)
	var mesh: CylinderMesh = zone.mesh as CylinderMesh
	if mesh != null and not z.is_empty():
		mesh.top_radius = float(z.get("radius", mesh.top_radius))
		mesh.bottom_radius = 0.003
		mesh.height = maxf(float(z.get("length", mesh.height)), 0.001)
		zone.position = z.get("origin", zone.position) as Vector3
	var mat: StandardMaterial3D = zone.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = SensorDetect.zone_viz_color(el)
