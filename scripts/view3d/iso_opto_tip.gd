class_name IsoOptoTip
extends RefCounted
## 3D оптонаконечник: серебро + тёмный нос встык; линзы утоплены спереди (от кабеля).


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 3.5)
	if od_mm > 6.0:
		od_mm *= 0.5
	var len_mm: float = maxf(float(el.stroke_mm), 18.0)
	var r: float = Parts.mm(od_mm * 0.5)
	var body_l: float = Parts.mm(len_mm)
	var role: String = str(el.opto_role)
	var metal := Parts.mat("otip_body", Color(0.62, 0.64, 0.66), 0.75, 0.32)
	var cap := Parts.mat("otip_cap", Color(0.1, 0.1, 0.12), 0.05, 0.72)
	var lens_tx := Parts.mat("otip_lens_tx", Color(0.95, 0.4, 0.18), 0.05, 0.28)
	var lens_rx := Parts.mat("otip_lens_rx", Color(0.3, 0.75, 0.5), 0.05, 0.28)
	var lens_one := lens_tx if role == "emitter" else (lens_rx if role == "receiver" else lens_tx)
	var fiber := Parts.mat("otip_fiber", Color(0.04, 0.04, 0.05), 0.02, 0.8)

	var x0: float = -body_l * 0.5
	var x1: float = body_l * 0.5
	# Нос (тёмный) спереди; серебро стык в стык без зазора.
	var nose_l: float = Parts.mm(3.2)
	var silver_l: float = maxf(body_l - nose_l, Parts.mm(12.0))
	var x_join: float = x1 - nose_l
	Parts.cyl(parent, r * 1.0, silver_l, Vector3(x0 + silver_l * 0.5, 0.0, 0.0), "x", metal, 14, "shell")
	Parts.cyl(parent, r * 1.02, nose_l, Vector3(x_join + nose_l * 0.5, 0.0, 0.0), "x", cap, 16, "shell")

	# Линзы: ось +X, чуть утоплены в нос, выступают НАРУЖУ (от кабеля).
	var lens_r: float = r * 0.36
	var lens_h: float = Parts.mm(1.4)
	# Центр линзы ближе к переднему торцу; наружный край ≈ x1 − 0.2 мм.
	var lens_c_x: float = x1 - lens_h * 0.35
	if role == "head":
		var off: float = r * 0.38
		Parts.cyl(parent, lens_r, lens_h, Vector3(lens_c_x, off, 0.0), "x", lens_tx, 12, "shell")
		Parts.cyl(parent, lens_r, lens_h, Vector3(lens_c_x, -off, 0.0), "x", lens_rx, 12, "shell")
	else:
		Parts.cyl(parent, lens_r * 1.1, lens_h, Vector3(lens_c_x, 0.0, 0.0), "x", lens_one, 12, "shell")

	# Оптокабель сзади (−X).
	var cable_r: float = Parts.mm(0.85)
	var cable_l: float = Parts.mm(8.0)
	if role == "head":
		var off_y: float = Parts.mm(1.0)
		for i in 2:
			var sy: float = off_y if i == 0 else -off_y
			Parts.cyl(parent, cable_r, cable_l, Vector3(x0 - cable_l * 0.35, sy, 0.0), "x", fiber, 8, "shell")
			var tip := Vector3(x0 - cable_l * 0.9, sy, 0.0)
			var pname: String = "OPT1" if i == 0 else "OPT2"
			info["ports"][pname] = tip
			info["dirs"][pname] = Vector3.LEFT
		info["ports"]["OPT"] = info["ports"]["OPT1"]
		info["dirs"]["OPT"] = Vector3.LEFT
	else:
		Parts.cyl(parent, cable_r, cable_l, Vector3(x0 - cable_l * 0.4, 0.0, 0.0), "x", fiber, 8, "shell")
		var opt_tip := Vector3(x0 - cable_l * 0.95, 0.0, 0.0)
		info["ports"]["OPT"] = opt_tip
		info["dirs"]["OPT"] = Vector3.LEFT

	parent.set_meta("detect_material", "plastic")
	parent.set_meta("sense_face_local", Vector3(x1, 0.0, 0.0))
	parent.set_meta("opto_role", role)
	_build_beam_mesh(parent, el)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 12
	tag.pixel_size = 0.00024
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, r + Parts.mm(8.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("seat_aabb", AABB(
		Vector3(x0 - Parts.mm(12.0), -r * 2.2, -r * 2.2),
		Vector3(body_l + Parts.mm(20.0), r * 4.4, r * 4.4)
	))
	apply_zone_viz(parent, el, false)
	return info


static func _build_beam_mesh(parent: Node3D, el) -> void:
	if str(el.opto_role) == "receiver":
		return
	var zone := MeshInstance3D.new()
	zone.name = "SenseBeam"
	var cyl := CylinderMesh.new()
	var sn_m: float = maxf(float(el.sense_range_mm), 50.0) * 0.001
	var role: String = str(el.opto_role)
	if role == "emitter":
		cyl.top_radius = 0.0025
		cyl.bottom_radius = 0.0025
		cyl.height = minf(sn_m, 0.8)
	else:
		cyl.top_radius = maxf(sn_m * 0.12, 0.006)
		cyl.bottom_radius = 0.0015
		cyl.height = sn_m
	cyl.radial_segments = 14
	zone.mesh = cyl
	zone.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	var face_x: float = maxf(float(el.stroke_mm), 18.0) * 0.0005
	zone.position = Vector3(face_x + cyl.height * 0.5, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.2, 0.75, 0.95, 0.22)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	zone.material_override = mat
	zone.visible = false
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	parent.add_child(zone)


static func apply_zone_viz(root: Node3D, el, on: bool, amp = null, circuit = null) -> void:
	if root == null:
		return
	var role: String = str(el.opto_role)
	if role == "receiver":
		var zhide: MeshInstance3D = root.get_node_or_null("SenseBeam") as MeshInstance3D
		if zhide != null:
			zhide.visible = false
		return
	var zone: MeshInstance3D = root.get_node_or_null("SenseBeam") as MeshInstance3D
	if zone == null:
		return
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	zone.visible = bool(on)
	if not on:
		return
	var mesh: CylinderMesh = zone.mesh as CylinderMesh
	if mesh == null:
		return
	var sn_m: float = maxf(float(el.sense_range_mm), 50.0) * 0.001
	if amp != null:
		sn_m = maxf(float(amp.sense_range_mm), 10.0) * 0.001
	var face_x: float = maxf(float(el.stroke_mm), 18.0) * 0.0005
	if role == "emitter" and circuit != null and amp != null:
		var beams: Array = SensorDetect.optical_beam_world(circuit, amp)
		for b in beams:
			if str(b.get("kind", "")) != "optical_barrier":
				continue
			# Длина до препятствия или до RX.
			var length: float = float(b.get("length", sn_m))
			mesh.top_radius = 0.003
			mesh.bottom_radius = 0.003
			mesh.height = maxf(length, 0.01)
			zone.position = Vector3(face_x + mesh.height * 0.5, 0.0, 0.0)
			break
	elif role == "emitter":
		mesh.top_radius = 0.0025
		mesh.bottom_radius = 0.0025
		mesh.height = minf(sn_m * 4.0, 0.9)
		zone.position = Vector3(face_x + mesh.height * 0.5, 0.0, 0.0)
	else:
		var len_d: float = sn_m
		if circuit != null and amp != null:
			var beams_d: Array = SensorDetect.optical_beam_world(circuit, amp)
			for bd in beams_d:
				if str(bd.get("kind", "")) in ["optical_diffuse", "optical_retro"]:
					len_d = maxf(float(bd.get("length", sn_m)), 0.01)
					break
		mesh.top_radius = maxf(len_d * 0.15, 0.008)
		mesh.bottom_radius = 0.0015
		mesh.height = len_d
		zone.position = Vector3(face_x + mesh.height * 0.5, 0.0, 0.0)
	var mat: StandardMaterial3D = zone.material_override as StandardMaterial3D
	if mat != null:
		if amp != null:
			mat.albedo_color = SensorDetect.zone_viz_color(amp)
		else:
			mat.albedo_color = Color(0.2, 0.75, 0.95, 0.22)
