class_name IsoRotaryVane
extends RefCounted
## 3D лопастной поворотный ПЦ (Festo DSM-класс): корпус CSG, лопасть, упор, вал, порты.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const RotaryCat = preload("res://scripts/domain/rotary_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")

static var _mats := {}


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var size_mm: float = float(el.bore_mm)
	var th_max: float = deg_to_rad(float(el.angle_max_deg))
	var r_ch: float = RotaryCat.vane_chamber_r_m(size_mm)
	var shaft_r: float = RotaryCat.vane_shaft_r_m(size_mm)
	var h_ch: float = RotaryCat.vane_height_m(size_mm)
	var wall: float = maxf(r_ch * 0.28, Parts.mm(3.5))
	var body_r: float = r_ch + wall
	var body_h: float = h_ch + wall * 1.8
	var stop_w: float = clampf(r_ch * 0.16, Parts.mm(2.0), Parts.mm(4.5))
	var vane_t: float = clampf(r_ch * 0.12, Parts.mm(1.5), Parts.mm(3.5))
	var hub_r: float = shaft_r * 1.35

	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 6.0 if size_mm <= 40.0 else 8.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55

	var mat_shell: StandardMaterial3D = _m("rv3_shell", Color(0.78, 0.80, 0.82), 0.42, 0.48)
	var mat_alum: StandardMaterial3D = _m("rv3_alum", Color(0.72, 0.74, 0.76), 0.58, 0.40)
	var mat_steel: StandardMaterial3D = _m("rv3_steel", Color(0.55, 0.57, 0.60), 0.7, 0.35)
	var mat_seal: StandardMaterial3D = _m("rv3_seal", Color(0.08, 0.08, 0.09), 0.0, 0.9)
	var mat_stop: StandardMaterial3D = _m("rv3_stop", Color(0.35, 0.36, 0.38), 0.45, 0.55)

	var ports: Dictionary = _build_body_csg(
		parent, body_r, body_h, r_ch, h_ch, shaft_r, stop_w, fit_scale, mat_shell
	)
	info["ports"]["a"] = ports["a"]
	info["ports"]["b"] = ports["b"]
	info["dirs"]["a"] = Vector3.BACK
	info["dirs"]["b"] = Vector3.BACK

	# Перегородка на +Z — от ступицы до стенки; щёки = упоры лопасти.
	var stop_len: float = r_ch - hub_r - Parts.mm(0.4)
	_box(
		parent,
		Vector3(stop_w, h_ch * 0.96, stop_len),
		Vector3(0.0, 0.0, hub_r + stop_len * 0.5),
		mat_stop,
		"internal"
	)

	var rotor := Node3D.new()
	rotor.name = "Rotor"
	parent.add_child(rotor)

	var y_bot: float = -body_h * 0.5
	var y_top: float = body_h * 0.5 + maxf(body_r * 0.55, Parts.mm(12.0))
	_add_shaft_csg(rotor, shaft_r, y_bot, y_top, mat_steel)

	var hub := _cyl(rotor, hub_r, h_ch * 0.94, Vector3.ZERO, "y", mat_alum, 28, "internal")
	hub.name = "VaneHub"

	var vane_len: float = r_ch - hub_r - Parts.mm(0.6)
	var vane := _box(
		rotor,
		Vector3(vane_t, h_ch * 0.92, vane_len),
		Vector3(0.0, 0.0, hub_r + vane_len * 0.5),
		mat_alum,
		"internal"
	)
	vane.name = "Vane"
	_box(
		rotor,
		Vector3(vane_t * 1.12, h_ch * 0.88, Parts.mm(1.0)),
		Vector3(0.0, 0.0, r_ch - Parts.mm(0.9)),
		mat_seal,
		"internal"
	)

	var or_t: float = clampf(shaft_r * 0.22, Parts.mm(0.6), Parts.mm(1.2))
	Parts.oring(parent, shaft_r * 1.02, or_t, Vector3(0.0, body_h * 0.5 - wall * 0.35, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.02, or_t, Vector3(0.0, body_h * 0.5 - wall * 0.75, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.02, or_t, Vector3(0.0, -body_h * 0.5 + wall * 0.35, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.02, or_t, Vector3(0.0, -body_h * 0.5 + wall * 0.75, 0.0), "y", mat_seal)

	# Геометрический зазор до щеки; крайние положения дальше (как прежнее «правое»).
	var cheek: float = atan2(stop_w * 0.5 + vane_t * 0.55, (hub_r + r_ch) * 0.5)
	var clear: float = clampf(cheek * 3.0, cheek + deg_to_rad(10.0), PI * 0.35)
	var span: float = maxf(TAU - 2.0 * clear, 0.5)
	parent.set_meta("rotary_th_max", th_max)
	parent.set_meta("vane_park", clear)
	parent.set_meta("vane_span", span)
	parent.set_meta("xray_role", "window")
	apply_state(parent, el)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, y_top + 0.015, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	return info


static func apply_state(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var rotor: Node3D = root.get_node_or_null("Rotor") as Node3D
	if rotor == null:
		return
	var clear: float = float(root.get_meta("vane_park", 0.15))
	var span: float = float(root.get_meta("vane_span", PI))
	var th_max: float = float(root.get_meta("rotary_th_max", PI))
	if th_max < 1.0e-6:
		th_max = PI
	# Симметрично ±clear от перегородки (clear > щека — не вплотную).
	# Ход длинной дугой через полость: t=0 → +clear, t=1 → −clear.
	var t: float = clampf(float(el.angle) / th_max, 0.0, 1.0)
	rotor.rotation.y = clear + t * span


static func apply_xray(root: Node3D, on: bool) -> void:
	var Iso = preload("res://scripts/view3d/iso_cylinder.gd")
	Iso.apply_xray(root, on, false)


static func _add_shaft_csg(
	parent: Node, shaft_r: float, y_bot: float, y_top: float, mat: Material
) -> void:
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var UNION := CSGShape3D.OPERATION_UNION
	var shaft_h: float = y_top - y_bot
	var mid_y: float = 0.5 * (y_bot + y_top)
	var comb := CSGCombiner3D.new()
	comb.name = "ShaftCSG"
	comb.add_child(CsgBake.cyl(shaft_r, shaft_h, Vector3(0.0, mid_y, 0.0), "y", UNION, 28))

	var tap_r: float = shaft_r * 0.38
	var tap_depth: float = clampf(shaft_r * 1.7, Parts.mm(4.0), Parts.mm(8.0))
	var tap_mid: float = y_top - tap_depth * 0.5
	comb.add_child(CsgBake.cyl(tap_r, tap_depth + Parts.mm(0.3), Vector3(0.0, tap_mid, 0.0), "y", SUB, 16))

	# Шлиц вдоль +Z — сонаправлен с лопастью (локально тоже +Z).
	var slot_len: float = shaft_r * 2.15
	var slot_thick: float = clampf(shaft_r * 0.28, Parts.mm(0.9), Parts.mm(1.8))
	var slot_depth: float = clampf(tap_depth * 0.55, Parts.mm(2.0), Parts.mm(4.5))
	comb.add_child(CsgBake.box(
		Vector3(slot_thick, slot_depth, slot_len),
		Vector3(0.0, y_top - slot_depth * 0.45, 0.0),
		SUB
	))

	CsgBake.attach(parent, comb, mat, "internal")
	comb.name = "Shaft"


static func _build_body_csg(
	parent: Node, body_r: float, body_h: float, r_ch: float, h_ch: float,
	shaft_r: float, stop_w: float, fit_scale: float, mat: Material
) -> Dictionary:
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var UNION := CSGShape3D.OPERATION_UNION
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	# Круглая часть.
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 32))
	# Прямоугольник на +Z: ширина=Ø, высота=H, глубина=R от оси —
	# смыкается с кругом по диаметральной плоскости → силуэт «перевёрнутая U» / D.
	comb.add_child(CsgBake.box(
		Vector3(body_r * 2.0, body_h, body_r),
		Vector3(0.0, 0.0, body_r * 0.5),
		UNION
	))
	# Камера и вал.
	comb.add_child(CsgBake.cyl(r_ch, h_ch, Vector3.ZERO, "y", SUB, 28))
	comb.add_child(CsgBake.cyl(shaft_r * 1.08, body_h + Parts.mm(4.0), Vector3.ZERO, "y", SUB, 20))

	var chan_r: float = clampf(r_ch * 0.14, Parts.mm(1.2), Parts.mm(2.4))
	# Передняя грань прямоугольника: z = body_r.
	var z_face: float = body_r
	var z_mouth: float = z_face + chan_r * 0.2
	var z_into: float = r_ch * 0.55
	var x_port: float = stop_w * 0.85 + chan_r * 1.8
	var y_port: float = -h_ch * 0.15
	_csg_chan_z(comb, chan_r, -x_port, y_port, z_mouth, z_into, SUB)
	_csg_chan_z(comb, chan_r, x_port, y_port, z_mouth, z_into, SUB)

	CsgBake.attach(parent, comb, mat, "window")

	var tip_a: Vector3 = Parts.add_fitting(parent, Vector3(-x_port, y_port, z_face), "z", fit_scale, true)
	var tip_b: Vector3 = Parts.add_fitting(parent, Vector3(x_port, y_port, z_face), "z", fit_scale * 0.95, true)
	return {"a": tip_a, "b": tip_b}


static func _csg_chan_z(
	comb: CSGCombiner3D, rad: float, x: float, y: float, z_from: float, z_to: float,
	op: CSGShape3D.Operation
) -> void:
	var lo: float = minf(z_from, z_to)
	var hi: float = maxf(z_from, z_to)
	var h: float = hi - lo + rad * 0.4
	comb.add_child(CsgBake.cyl(rad, h, Vector3(x, y, 0.5 * (lo + hi)), "z", op, 12))


static func _m(key: String, color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = rough
	_mats[key] = mat
	return mat


static func _box(parent: Node, size: Vector3, center: Vector3, mat: Material, role: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	parent.add_child(mi)
	return mi


static func _cyl(
	parent: Node, radius: float, length: float, center: Vector3, axis: String,
	mat: Material, segs: int, role: String
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(length, 0.0004)
	mesh.radial_segments = segs
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	if axis == "x":
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif axis == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(mi)
	return mi
