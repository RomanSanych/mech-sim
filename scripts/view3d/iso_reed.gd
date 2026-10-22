class_name IsoReed
extends RefCounted
## 3D геркон (Т-паз / хомут на гильзу ПЦ): корпус, кабель, LED, сфера SenseZone.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 6.0)
	var len_mm: float = maxf(float(el.stroke_mm), 28.0)
	var r: float = Parts.mm(od_mm * 0.5)
	var body_l: float = Parts.mm(len_mm)
	var body := Parts.mat("reed_body", Color(0.12, 0.14, 0.18), 0.08, 0.62)
	var accent := Parts.mat("reed_accent", Color(0.18, 0.55, 0.42), 0.12, 0.5)
	var clamp_m := Parts.mat("reed_clamp", Color(0.72, 0.74, 0.76), 0.85, 0.3)
	var cable_mat: Material = Parts.mat("reed_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)

	# Узкий брусок вдоль оси гильзы (локаль X); «вход» в Т-паз снизу.
	var half_l: float = body_l * 0.5
	Parts.box(parent, Vector3(body_l, r * 1.55, r * 1.35), Vector3.ZERO, body, "shell")
	Parts.box(parent, Vector3(body_l * 0.55, r * 0.35, r * 1.5), Vector3(0.0, -r * 0.95, 0.0), accent, "shell")
	# Хомут / губки крепления к профилю.
	Parts.box(parent, Vector3(Parts.mm(6.0), r * 0.9, r * 2.4), Vector3(-half_l * 0.35, -r * 0.2, 0.0), clamp_m, "shell")
	Parts.box(parent, Vector3(Parts.mm(6.0), r * 0.9, r * 2.4), Vector3(half_l * 0.35, -r * 0.2, 0.0), clamp_m, "shell")

	parent.set_meta("detect_material", "plastic")
	parent.set_meta("sense_face_local", Vector3.ZERO)

	# Кабель с торца (−X), как у индуктивного.
	var cable_r: float = Parts.mm(2.2)
	var cable_stub_l: float = Parts.mm(12.0)
	var x_rear0: float = -half_l
	var cable_c: float = x_rear0 - cable_stub_l * 0.45
	Parts.cyl(parent, cable_r, cable_stub_l, Vector3(cable_c, 0.0, 0.0), "x", cable_mat, 12, "shell")
	var cable_tip := Vector3(x_rear0 - cable_stub_l * 0.95, 0.0, 0.0)
	Parts.cyl(parent, cable_r * 1.02, Parts.mm(1.2), cable_tip + Vector3(Parts.mm(0.4), 0.0, 0.0), "x", cable_mat, 14, "shell")
	parent.set_meta("cable_exit_local", cable_tip)
	parent.set_meta("cable_exit_dir", Vector3.LEFT)
	# Сухой контакт: 2 жилы (OUT / 0), без Uпит головки.
	info["ports"]["OUT"] = cable_tip
	info["ports"]["0"] = cable_tip
	info["dirs"]["OUT"] = Vector3.LEFT
	info["dirs"]["0"] = Vector3.LEFT

	var led := MeshInstance3D.new()
	led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(1.4)
	sph.height = Parts.mm(2.8)
	led.mesh = sph
	led.position = Vector3(half_l * 0.15, r * 0.95, 0.0)
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
	tag.position = Vector3(0.0, r + Parts.mm(10.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_reed", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(x_rear0 - Parts.mm(14.0), -r * 2.2, -r * 2.0),
		Vector3(body_l + Parts.mm(26.0), r * 4.0, r * 4.0)
	))
	apply_led(parent, el)
	apply_zone_viz(parent, el, false)
	return info


static func _build_zone_mesh(parent: Node3D, el) -> void:
	var z: Dictionary = SensorDetect.zone_desc(el)
	if z.is_empty():
		return
	var zone := MeshInstance3D.new()
	zone.name = "SenseZone"
	var mesh := SphereMesh.new()
	mesh.radius = float(z.get("radius", 0.018))
	mesh.height = float(z.get("radius", 0.018)) * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	zone.mesh = mesh
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
	# Подтянуть метки на уже собранных мешах (после смены роли зоны).
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	zone.visible = bool(on)
	if not on:
		return
	var z: Dictionary = SensorDetect.zone_desc(el)
	var mesh: SphereMesh = zone.mesh as SphereMesh
	if mesh != null and not z.is_empty():
		var rad: float = float(z.get("radius", mesh.radius))
		mesh.radius = rad
		mesh.height = rad * 2.0
		zone.position = z.get("origin", zone.position) as Vector3
	var mat: StandardMaterial3D = zone.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = SensorDetect.zone_viz_color(el)
