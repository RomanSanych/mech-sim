class_name IsoAirMotorTurbine
extends RefCounted
## 3D турбинный пневмомотор (реверсивный):
## цилиндрический корпус; радиальная турбина; сопловые каналы ±X в CSG;
## окно рентгена только над камерой с колесом; глушитель — Parts.add_silencer.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const MotorCat = preload("res://scripts/domain/motor_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const Rack = preload("res://scripts/view3d/iso_rotary_rack.gd")

const BLADE_COUNT := 10


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = float(el.tube_od_mm)
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var s: float = MotorCat.geom_scale(el)

	var r_wheel: float = Parts.mm(16.0) * s
	var r_hub: float = r_wheel * 0.32
	var wall: float = Parts.mm(3.6) * s
	var clear: float = Parts.mm(1.4) * s
	var r_ch: float = r_wheel + clear
	var body_r: float = r_ch + wall
	var h_ch: float = Parts.mm(14.0) * s
	var deck: float = Parts.mm(4.5) * s
	var body_h: float = h_ch + deck * 2.0
	var shaft_r: float = maxf(r_hub * 0.55, Parts.mm(3.0) * s)
	var bore_r: float = shaft_r * 1.12
	var blade_t: float = clampf(r_wheel * 0.08, Parts.mm(1.1) * s, Parts.mm(2.2) * s)
	var blade_h: float = h_ch * 0.78
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55

	var mat_body: StandardMaterial3D = Parts.mat("motor_turbine_body", Color(0.60, 0.64, 0.68), 0.45, 0.42)
	var mat_wheel: StandardMaterial3D = Parts.mat("motor_turbine_wheel", Color(0.76, 0.78, 0.80), 0.58, 0.38)
	var mat_blade: StandardMaterial3D = Parts.mat("motor_turbine_blade", Color(0.88, 0.62, 0.22), 0.25, 0.50)
	var mat_brg: StandardMaterial3D = Parts.mat("motor_bearing", Color(0.22, 0.23, 0.25), 0.55, 0.35)

	var chan_r: float = clampf(r_ch * 0.18, Parts.mm(2.0), Parts.mm(3.6))
	var y_port: float = 0.0

	_build_body_csg(parent, body_r, body_h, r_ch, h_ch, bore_r, chan_r, mat_body)

	var internals := Node3D.new()
	internals.name = "Internals"
	parent.add_child(internals)

	var rotor := Node3D.new()
	rotor.name = "Rotor"
	internals.add_child(rotor)

	# Зазор до стенки камеры — лопатки не «втыкаются» в каналы.
	var tip_clear: float = Parts.mm(0.8) * s
	_build_turbine_wheel(
		rotor, r_hub, r_wheel - tip_clear, blade_h, blade_t, mat_wheel, mat_blade
	)

	var y_face: float = body_h * 0.5
	var protrude: float = Parts.mm(16.0) * s
	Rack._add_output_shaft(rotor, shaft_r, -y_face * 0.2, y_face + protrude, mat_wheel)

	var brg_h: float = Parts.mm(4.0) * s
	_add_bearing(parent, Vector3(0.0, y_face - brg_h * 0.4, 0.0), shaft_r, brg_h, mat_brg, "BearingTop")
	_add_bearing(parent, Vector3(0.0, -y_face + brg_h * 0.4, 0.0), shaft_r, brg_h, mat_brg, "BearingBot")

	var x_face: float = body_r
	if MotorCat.port_is_muffler(el, "in"):
		info["ports"]["in"] = Parts.add_silencer(
			parent, Vector3(-x_face, y_port, 0.0), "-x", fit_scale * 1.05
		)
	else:
		info["ports"]["in"] = Parts.add_fitting(
			parent, Vector3(-x_face, y_port, 0.0), "-x", fit_scale, true
		)
	info["dirs"]["in"] = Vector3.LEFT

	if MotorCat.port_is_muffler(el, "exhaust"):
		info["ports"]["exhaust"] = Parts.add_silencer(
			parent, Vector3(x_face, y_port, 0.0), "x", fit_scale * 1.05
		)
	else:
		info["ports"]["exhaust"] = Parts.add_fitting(
			parent, Vector3(x_face, y_port, 0.0), "x", fit_scale, true
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

	parent.set_meta("air_motor_turbine", true)
	parent.set_meta("turbine_blades", BLADE_COUNT)
	apply_state(parent, el)
	return info


static func _build_body_csg(
	parent: Node3D,
	body_r: float, body_h: float, r_ch: float, h_ch: float, bore_r: float,
	chan_r: float, mat: Material
) -> void:
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	# Цилиндр корпуса; камера по высоте колеса — window только над динамикой.
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 32))
	comb.add_child(CsgBake.cyl(r_ch, h_ch, Vector3.ZERO, "y", SUB, 28))
	comb.add_child(CsgBake.cyl(bore_r, body_h + Parts.mm(2.0), Vector3.ZERO, "y", SUB, 20))
	var x_face: float = body_r
	var chan_len: float = x_face - r_ch * 0.35 + chan_r
	comb.add_child(CsgBake.cyl(
		chan_r, chan_len, Vector3(-(x_face + r_ch * 0.35) * 0.5, 0.0, 0.0), "x", SUB, 14
	))
	comb.add_child(CsgBake.cyl(
		chan_r, chan_len, Vector3((x_face + r_ch * 0.35) * 0.5, 0.0, 0.0), "x", SUB, 14
	))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_turbine_wheel(
	rotor: Node3D, r_hub: float, r_tip: float, blade_h: float, blade_t: float,
	mat_hub: Material, mat_blade: Material
) -> void:
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	hub.mesh = CylinderMesh.new()
	(hub.mesh as CylinderMesh).top_radius = r_hub
	(hub.mesh as CylinderMesh).bottom_radius = r_hub
	(hub.mesh as CylinderMesh).height = blade_h * 0.95
	(hub.mesh as CylinderMesh).radial_segments = 24
	hub.material_override = mat_hub
	hub.set_meta("xray_role", "internal")
	rotor.add_child(hub)

	# Тонкий диск-ступица в плоскости вращения (ось = вал Y).
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = CylinderMesh.new()
	(disc.mesh as CylinderMesh).top_radius = r_tip * 0.96
	(disc.mesh as CylinderMesh).bottom_radius = r_tip * 0.96
	(disc.mesh as CylinderMesh).height = blade_h * 0.16
	(disc.mesh as CylinderMesh).radial_segments = 28
	disc.material_override = mat_hub
	disc.set_meta("xray_role", "internal")
	rotor.add_child(disc)

	var blade_len: float = maxf(r_tip - r_hub * 0.9, Parts.mm(2.0))
	var mid_r: float = r_hub * 0.9 + blade_len * 0.5
	for i in BLADE_COUNT:
		var ang: float = TAU * float(i) / float(BLADE_COUNT)
		var blade := MeshInstance3D.new()
		blade.name = "Blade%d" % i
		blade.mesh = BoxMesh.new()
		(blade.mesh as BoxMesh).size = Vector3(blade_t, blade_h * 0.88, blade_len)
		# Ковш согласован с +ω (in→exhaust): наклон −азимут, не +.
		blade.position = Vector3(sin(ang) * mid_r, 0.0, cos(ang) * mid_r)
		blade.rotation.y = ang - 0.28
		blade.material_override = mat_blade
		blade.set_meta("xray_role", "internal")
		rotor.add_child(blade)


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
	var rotor: Node3D = root.get_node_or_null("Internals/Rotor") as Node3D
	if rotor == null:
		return
	rotor.rotation.y = float(el.angle)


static func apply_xray(root: Node3D, on: bool) -> void:
	if root == null:
		return
	Iso.apply_xray(root, on, false)
