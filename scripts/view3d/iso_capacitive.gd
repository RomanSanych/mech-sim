class_name IsoCapacitive
extends RefCounted
## 3D ёмкостный БВ: резьбовой цилиндр, кремовый торец (диэлектрик), гайки, кабель, LED.
## Зона SenseZone = тот же объём, что hit-тест (SensorDetection.zone_desc).


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 8.0)
	var len_mm: float = maxf(float(el.stroke_mm), 40.0)
	var r: float = Parts.mm(od_mm * 0.5)
	var body_l: float = Parts.mm(len_mm)
	var metal := Parts.mat("cap_body", Color(0.76, 0.78, 0.80), 0.88, 0.28)
	# Кремовый/янтарный торец — отличие от синего inductive non-flush.
	var tip_col := Color(0.92, 0.78, 0.28)
	var tip_mat := Parts.mat("cap_tip", tip_col, 0.05, 0.55)
	var plastic := Parts.mat("cap_rear", Color(0.12, 0.14, 0.18), 0.05, 0.65)
	var nut_mat := Parts.mat("cap_nut", Color(0.7, 0.72, 0.74), 0.75, 0.35)

	var rear_l: float = Parts.mm(11.0)
	var x_rear0: float = -body_l * 0.5
	var x_join: float = x_rear0 + rear_l
	var tip_h: float = Parts.mm(3.6)
	var x_tip: float = body_l * 0.5
	var metal_l: float = maxf(x_tip - tip_h * 0.5 - x_join, Parts.mm(20.0))
	var metal_c: float = x_join + metal_l * 0.5

	Parts.cyl(parent, r * 1.04, rear_l, Vector3(x_rear0 + rear_l * 0.5, 0.0, 0.0), "x", plastic, 20, "shell")
	Parts.cyl(parent, r * 0.99, metal_l + Parts.mm(1.0), Vector3(metal_c - Parts.mm(0.5), 0.0, 0.0), "x", metal, 28, "shell")

	var n_rings: int = clampi(int(od_mm * 0.55), 6, 14)
	for i in n_rings:
		var t: float = float(i) / float(maxi(n_rings - 1, 1))
		var x: float = x_join + Parts.mm(2.0) + t * (metal_l - Parts.mm(6.0))
		Parts.cyl(parent, r * 1.03, Parts.mm(0.55), Vector3(x, 0.0, 0.0), "x", metal, 20, "shell")

	Parts.cyl(parent, r * 1.02, tip_h, Vector3(x_tip - tip_h * 0.35, 0.0, 0.0), "x", tip_mat, 24, "shell")
	# Корпус датчика — пластик/металл головки; не цель детекта для себя.
	parent.set_meta("detect_material", "plastic")
	parent.set_meta("sense_face_local", Vector3(x_tip, 0.0, 0.0))

	_add_hex_nut(parent, Vector3(x_join + metal_l * 0.28, 0.0, 0.0), r * 1.35, Parts.mm(3.5), nut_mat)
	_add_hex_nut(parent, Vector3(x_join + metal_l * 0.55, 0.0, 0.0), r * 1.35, Parts.mm(3.5), nut_mat)

	var cable_r: float = Parts.mm(2.6)
	var cable_stub_l: float = Parts.mm(10.0)
	var cable_mat: Material = Parts.mat("cap_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)
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

	_add_threshold_screw(parent, Vector3(x_rear0 - Parts.mm(1.2), r * 0.45, 0.0), el)

	var led := MeshInstance3D.new()
	led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(1.6)
	sph.height = Parts.mm(3.2)
	led.mesh = sph
	led.position = Vector3(x_rear0 + rear_l * 0.55, r * 0.9, 0.0)
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
	tag.position = Vector3(0.0, r + Parts.mm(12.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_capacitive", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(x_rear0 - Parts.mm(16.0), -r * 1.5, -r * 1.5),
		Vector3(body_l + Parts.mm(28.0), r * 3.0, r * 3.0)
	))
	apply_led(parent, el)
	apply_zone_viz(parent, el, false)
	apply_threshold_screw(parent, el)
	return info


static func _add_threshold_screw(parent: Node3D, center: Vector3, el) -> void:
	var screw := Node3D.new()
	screw.name = "ThresholdScrew"
	screw.position = center
	parent.add_child(screw)
	var metal := Parts.mat("cap_thr", Color(0.72, 0.74, 0.76), 0.9, 0.22)
	Parts.cyl(screw, Parts.mm(2.2), Parts.mm(4.0), Vector3.ZERO, "-x", metal, 8, "control")
	Parts.cyl(screw, Parts.mm(3.0), Parts.mm(1.3), Vector3(-Parts.mm(2.2), 0.0, 0.0), "-x", metal, 6, "control")
	Parts.box(
		screw,
		Vector3(Parts.mm(0.35), Parts.mm(2.4), Parts.mm(0.55)),
		Vector3(-Parts.mm(2.85), 0.0, 0.0),
		Parts.mat("cap_thr_slot", Color(0.12, 0.12, 0.14), 0.15, 0.75),
		"control"
	)
	screw.set_meta("threshold_screw", true)
	apply_threshold_screw(parent, el)


static func apply_threshold_screw(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var screw: Node3D = root.get_node_or_null("ThresholdScrew") as Node3D
	if screw == null:
		return
	screw.rotation_degrees = Vector3(clampf(float(el.threshold_pct), 0.0, 100.0) * 3.6, 0.0, 0.0)


static func _add_hex_nut(parent: Node, center: Vector3, across_r: float, thick: float, mat: Material) -> void:
	Parts.cyl(parent, across_r, thick, center, "x", mat, 6, "shell")


static func _build_zone_mesh(parent: Node3D, el) -> void:
	var z: Dictionary = SensorDetect.zone_desc(el)
	if z.is_empty():
		return
	var zone := MeshInstance3D.new()
	zone.name = "SenseZone"
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(z.get("radius", 0.01))
	cyl.bottom_radius = float(z.get("radius", 0.01))
	cyl.height = maxf(float(z.get("length", 0.004)), 0.001)
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
	# Не internal: рентген иначе форсит visible и «белит» корпус сферой зоны.
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	parent.add_child(zone)


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
		mesh.bottom_radius = float(z.get("radius", mesh.bottom_radius))
		mesh.height = maxf(float(z.get("length", mesh.height)), 0.001)
		zone.position = z.get("origin", zone.position) as Vector3
	var mat: StandardMaterial3D = zone.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = SensorDetect.zone_viz_color(el)
