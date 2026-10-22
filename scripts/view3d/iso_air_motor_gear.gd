class_name IsoAirMotorGear
extends RefCounted
## 3D шестерённый пневмомотор (реверсивный):
## stadium-корпус; каналы ±X к зацеплению; две шестерни как у рейка-ПЦ;
## отверстия под валы + подшипники на выходах; глушитель — Parts.add_silencer (широким к корпусу).

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const MotorCat = preload("res://scripts/domain/motor_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const Rack = preload("res://scripts/view3d/iso_rotary_rack.gd")

const PINION_TEETH := 16


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = float(el.tube_od_mm)
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	# Весь мотор (stadium, полости, шестерни, валы) — от момента стоп.
	var s: float = MotorCat.geom_scale(el)

	var r_pin: float = Parts.mm(10.0) * s
	var z_teeth: int = PINION_TEETH
	var module: float = (2.0 * r_pin) / float(z_teeth)
	var addendum: float = module * 0.9
	var dedendum: float = module * 1.1
	var tip_r: float = r_pin + addendum
	var face_w: float = clampf(module * 7.0, r_pin * 0.9, Parts.mm(14.0) * s)
	var shaft_r: float = maxf(r_pin * 0.42, Parts.mm(3.2)) * 1.15
	var clear: float = module * 0.2
	var cav_r: float = tip_r + clear
	var z_a: float = -r_pin
	var z_b: float = r_pin

	var wall: float = Parts.mm(3.5) * s
	var body_x: float = cav_r * 2.0 + wall * 2.2
	var body_y: float = face_w + wall * 2.0
	var mid_z: float = 2.0 * r_pin
	var end_r: float = body_x * 0.5
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var bore_r: float = shaft_r * 1.12

	var mat_body: StandardMaterial3D = Parts.mat("motor_body", Color(0.62, 0.65, 0.68), 0.45, 0.42)
	var mat_gear: StandardMaterial3D = Parts.mat("motor_gear", Color(0.74, 0.76, 0.78), 0.58, 0.40)
	var mat_brg: StandardMaterial3D = Parts.mat("motor_bearing", Color(0.22, 0.23, 0.25), 0.55, 0.35)

	_build_body_csg(
		parent, body_x, body_y, mid_z, end_r, cav_r, face_w, z_a, z_b, bore_r, mat_body
	)

	var internals := Node3D.new()
	internals.name = "Internals"
	parent.add_child(internals)

	var y_face: float = body_y * 0.5
	var protrude: float = Parts.mm(14.0) * s
	var ga := Node3D.new()
	ga.name = "GearA"
	ga.position = Vector3(0.0, 0.0, z_a)
	internals.add_child(ga)
	Rack._add_pinion(ga, r_pin, module, addendum, dedendum, z_teeth, face_w, shaft_r, mat_gear)
	Rack._add_output_shaft(ga, shaft_r, -y_face, y_face + protrude, mat_gear)

	var gb := Node3D.new()
	gb.name = "GearB"
	gb.position = Vector3(0.0, 0.0, z_b)
	internals.add_child(gb)
	Rack._add_pinion(gb, r_pin, module, addendum, dedendum, z_teeth, face_w, shaft_r, mat_gear)
	var shaft_flip := Node3D.new()
	shaft_flip.name = "ShaftFlip"
	shaft_flip.rotation_degrees.x = 180.0
	gb.add_child(shaft_flip)
	Rack._add_output_shaft(shaft_flip, shaft_r, -y_face, y_face + protrude, mat_gear)
	gb.rotation.y = PI / float(z_teeth)

	# Подшипники в местах выхода валов из корпуса (не крутятся с валом).
	var brg_h: float = Parts.mm(4.5) * s
	_add_bearing(parent, Vector3(0.0, y_face - brg_h * 0.35, z_a), shaft_r, brg_h, mat_brg, "BearingA")
	_add_bearing(parent, Vector3(0.0, -y_face + brg_h * 0.35, z_b), shaft_r, brg_h, mat_brg, "BearingB")

	var x_face: float = body_x * 0.5
	if MotorCat.port_is_muffler(el, "in"):
		info["ports"]["in"] = Parts.add_silencer(
			parent, Vector3(-x_face, 0.0, 0.0), "-x", fit_scale * 1.05
		)
	else:
		info["ports"]["in"] = Parts.add_fitting(
			parent, Vector3(-x_face, 0.0, 0.0), "-x", fit_scale, true
		)
	info["dirs"]["in"] = Vector3.LEFT

	if MotorCat.port_is_muffler(el, "exhaust"):
		# Широкая сторона конуса к корпусу — канон Parts.add_silencer.
		info["ports"]["exhaust"] = Parts.add_silencer(
			parent, Vector3(x_face, 0.0, 0.0), "x", fit_scale * 1.05
		)
	else:
		info["ports"]["exhaust"] = Parts.add_fitting(
			parent, Vector3(x_face, 0.0, 0.0), "x", fit_scale, true
		)
	info["dirs"]["exhaust"] = Vector3.RIGHT

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, y_face + Parts.mm(12.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("air_motor_gear", true)
	parent.set_meta("motor_teeth", z_teeth)
	apply_state(parent, el)
	return info


static func _build_body_csg(
	parent: Node3D,
	body_x: float, body_y: float, mid_z: float, end_r: float,
	cav_r: float, face_w: float, z_a: float, z_b: float, bore_r: float, mat: Material
) -> void:
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	comb.add_child(CsgBake.box(Vector3(body_x, body_y, mid_z), Vector3.ZERO, UNION))
	comb.add_child(CsgBake.cyl(end_r, body_y, Vector3(0.0, 0.0, mid_z * 0.5), "y", UNION, 28))
	comb.add_child(CsgBake.cyl(end_r, body_y, Vector3(0.0, 0.0, -mid_z * 0.5), "y", UNION, 28))
	comb.add_child(CsgBake.cyl(cav_r, face_w + Parts.mm(0.4), Vector3(0.0, 0.0, z_a), "y", SUB, 28))
	comb.add_child(CsgBake.cyl(cav_r, face_w + Parts.mm(0.4), Vector3(0.0, 0.0, z_b), "y", SUB, 28))
	var chan_r: float = clampf(cav_r * 0.22, Parts.mm(2.0), Parts.mm(3.5))
	var x_face: float = body_x * 0.5
	var chan_len: float = x_face + chan_r * 0.5
	comb.add_child(CsgBake.cyl(chan_r, chan_len, Vector3(-x_face * 0.5, 0.0, 0.0), "x", SUB, 14))
	comb.add_child(CsgBake.cyl(chan_r, chan_len, Vector3(x_face * 0.5, 0.0, 0.0), "x", SUB, 14))
	# Сквозные отверстия под валы (чуть больше Ø вала).
	comb.add_child(CsgBake.cyl(bore_r, body_y + Parts.mm(2.0), Vector3(0.0, 0.0, z_a), "y", SUB, 20))
	comb.add_child(CsgBake.cyl(bore_r, body_y + Parts.mm(2.0), Vector3(0.0, 0.0, z_b), "y", SUB, 20))
	CsgBake.attach(parent, comb, mat, "window")


## Наружное кольцо + дорожка: вал крутится в отверстии без «трения» о корпус.
static func _add_bearing(
	parent: Node3D, at: Vector3, shaft_r: float, h: float, mat: Material, bname: String
) -> void:
	var root := Node3D.new()
	root.name = bname
	root.position = at
	parent.add_child(root)
	var od: float = shaft_r * 1.85
	var id: float = shaft_r * 1.08
	var outer := MeshInstance3D.new()
	outer.name = "Outer"
	outer.mesh = CylinderMesh.new()
	(outer.mesh as CylinderMesh).top_radius = od
	(outer.mesh as CylinderMesh).bottom_radius = od
	(outer.mesh as CylinderMesh).height = h
	(outer.mesh as CylinderMesh).radial_segments = 24
	outer.material_override = mat
	outer.set_meta("xray_role", "shell")
	root.add_child(outer)
	# Внутренняя «дорожка» чуть светлее — читается как подшипник.
	var race := MeshInstance3D.new()
	race.name = "Race"
	race.mesh = CylinderMesh.new()
	(race.mesh as CylinderMesh).top_radius = id * 1.15
	(race.mesh as CylinderMesh).bottom_radius = id * 1.15
	(race.mesh as CylinderMesh).height = h * 0.72
	(race.mesh as CylinderMesh).radial_segments = 20
	var mat_race: StandardMaterial3D = Parts.mat(
		"motor_bearing_race", Color(0.55, 0.56, 0.58), 0.65, 0.28
	)
	race.material_override = mat_race
	race.set_meta("xray_role", "shell")
	root.add_child(race)


static func apply_state(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var th: float = float(el.angle)
	var teeth: int = int(root.get_meta("motor_teeth", PINION_TEETH))
	var mesh_off: float = PI / float(maxi(teeth, 1))
	var ga: Node3D = root.get_node_or_null("Internals/GearA") as Node3D
	var gb: Node3D = root.get_node_or_null("Internals/GearB") as Node3D
	if ga != null:
		ga.rotation.y = th
	if gb != null:
		gb.rotation.y = -th + mesh_off


static func apply_xray(root: Node3D, on: bool) -> void:
	if root == null:
		return
	Iso.apply_xray(root, on, false)
