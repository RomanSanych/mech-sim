class_name IsoAirMotorVane
extends RefCounted
## 3D лопастной пневмомотор (реверсивный):
## корпус «перевёрнутая U» сверху; эксцентричная камера; ротор с пазами;
## лопатки подпружинены — выдвигаются до стенки полости;
## штуцеры на плоской грани, оси в зону сжатия лопаток;
## верх/низ корпуса — один CSG window (без отдельной крышки).

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const MotorCat = preload("res://scripts/domain/motor_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const Rack = preload("res://scripts/view3d/iso_rotary_rack.gd")

const VANE_COUNT := 4


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = float(el.tube_od_mm)
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var s: float = MotorCat.geom_scale(el)

	# t_min (ближний зазор) без изменений; ход лопатки −¼ от исходного размаха
	# (не t_max×0.75 — иначе ход почти пропадает).
	var r_ch0: float = Parts.mm(18.0) * s
	var ecc0: float = Parts.mm(4.2) * s
	var tip_clear: float = Parts.mm(0.35) * s
	var t_min: float = _chamber_wall_dist(PI, ecc0, r_ch0)
	var t_max0: float = _chamber_wall_dist(0.0, ecc0, r_ch0)
	var stroke0: float = maxf(t_max0 - t_min, Parts.mm(2.0) * s)
	var t_max: float = t_min + stroke0 * 0.75
	var r_ch: float = 0.5 * (t_min + t_max)
	var ecc: float = 0.5 * (t_max - t_min)
	var rot_clear: float = Parts.mm(1.2) * s
	var r_rot: float = maxf(t_min - rot_clear, Parts.mm(6.0) * s)
	var wall: float = Parts.mm(3.8) * s
	# Круглая сторона покрывает эксцентричную камеру (+Z); плоская грань на −Z.
	var body_r: float = r_ch + ecc + wall
	var h_ch: float = Parts.mm(22.0) * s
	var deck: float = Parts.mm(4.0) * s
	var body_h: float = h_ch + deck * 2.0
	var shaft_r: float = maxf(r_rot * 0.28, Parts.mm(3.0) * s)
	var vane_t: float = clampf(r_rot * 0.14, Parts.mm(1.4) * s, Parts.mm(2.8) * s)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var bore_r: float = shaft_r * 1.12
	# Длина по полностью задвинутому положению: дно паза → стенка полости.
	var slot_bottom: float = shaft_r * 1.2
	var vane_len: float = maxf((t_min - tip_clear) - slot_bottom, Parts.mm(3.0) * s)

	var mat_body: StandardMaterial3D = Parts.mat("motor_vane_body", Color(0.62, 0.65, 0.68), 0.45, 0.42)
	var mat_rotor: StandardMaterial3D = Parts.mat("motor_vane_rotor", Color(0.74, 0.76, 0.78), 0.58, 0.40)
	var mat_vane: StandardMaterial3D = Parts.mat("motor_vane_blade", Color(0.55, 0.58, 0.62), 0.4, 0.45)
	var mat_heel: StandardMaterial3D = Parts.mat("motor_vane_heel", Color(0.92, 0.55, 0.18), 0.2, 0.55)
	var mat_slot: StandardMaterial3D = Parts.mat("motor_vane_slot", Color(0.18, 0.19, 0.21), 0.15, 0.75)
	var mat_brg: StandardMaterial3D = Parts.mat("motor_bearing", Color(0.22, 0.23, 0.25), 0.55, 0.35)

	var z_face: float = -body_r
	var chan_r: float = clampf(r_ch * 0.16, Parts.mm(2.0), Parts.mm(3.4))
	var x_port: float = clampf(r_rot * 0.55 + chan_r * 1.2, Parts.mm(6.0) * s, body_r * 0.42)
	# Ниже по плоской грани — оси смотрят в зону, где лопатки задвинуты (−Z).
	var y_port: float = -h_ch * 0.28

	_build_body_csg(
		parent, body_r, body_h, r_ch, h_ch, bore_r, ecc, chan_r, x_port, y_port, z_face, mat_body
	)

	var internals := Node3D.new()
	internals.name = "Internals"
	parent.add_child(internals)

	var rotor := Node3D.new()
	rotor.name = "Rotor"
	internals.add_child(rotor)

	_build_rotor_hub(rotor, r_rot, h_ch * 0.92, shaft_r, vane_t, mat_rotor, mat_slot)

	for i in VANE_COUNT:
		var ang: float = TAU * float(i) / float(VANE_COUNT)
		# Каретка в пазу: только сдвиг вдоль местной +Z; длина Blade неизменна.
		var slide := Node3D.new()
		slide.name = "Vane%d" % i
		slide.rotation.y = ang
		slide.set_meta("vane_local_ang", ang)
		rotor.add_child(slide)
		var blade := MeshInstance3D.new()
		blade.name = "Blade"
		blade.mesh = BoxMesh.new()
		(blade.mesh as BoxMesh).size = Vector3(vane_t * 0.92, h_ch * 0.86, vane_len)
		blade.material_override = mat_vane
		blade.set_meta("xray_role", "internal")
		slide.add_child(blade)
		# Яркий «каблук» — внутренний край, который ездит по пазу.
		var heel := MeshInstance3D.new()
		heel.name = "Heel"
		heel.mesh = BoxMesh.new()
		(heel.mesh as BoxMesh).size = Vector3(vane_t * 1.05, h_ch * 0.8, maxf(vane_len * 0.12, Parts.mm(1.2) * s))
		heel.position = Vector3(0.0, 0.0, -vane_len * 0.5 + (heel.mesh as BoxMesh).size.z * 0.5)
		heel.material_override = mat_heel
		heel.set_meta("xray_role", "internal")
		blade.add_child(heel)

	var y_face: float = body_h * 0.5
	var protrude: float = Parts.mm(16.0) * s
	Rack._add_output_shaft(rotor, shaft_r, -y_face * 0.15, y_face + protrude, mat_rotor)

	var brg_h: float = Parts.mm(4.0) * s
	_add_bearing(parent, Vector3(0.0, y_face - brg_h * 0.4, 0.0), shaft_r, brg_h, mat_brg, "BearingTop")

	# Порты на плоской грани (−Z); каждый — глушитель или штуцер.
	if MotorCat.port_is_muffler(el, "in"):
		info["ports"]["in"] = Parts.add_silencer(
			parent, Vector3(-x_port, y_port, z_face), "-z", fit_scale * 1.05
		)
	else:
		info["ports"]["in"] = Parts.add_fitting(
			parent, Vector3(-x_port, y_port, z_face), "-z", fit_scale, true
		)
	info["dirs"]["in"] = Vector3.FORWARD

	if MotorCat.port_is_muffler(el, "exhaust"):
		info["ports"]["exhaust"] = Parts.add_silencer(
			parent, Vector3(x_port, y_port, z_face), "-z", fit_scale * 1.05
		)
	else:
		info["ports"]["exhaust"] = Parts.add_fitting(
			parent, Vector3(x_port, y_port, z_face), "-z", fit_scale, true
		)
	info["dirs"]["exhaust"] = Vector3.FORWARD

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

	parent.set_meta("air_motor_vane", true)
	parent.set_meta("vane_count", VANE_COUNT)
	parent.set_meta("vane_r_ch", r_ch)
	parent.set_meta("vane_ecc", ecc)
	parent.set_meta("vane_len", vane_len)
	parent.set_meta("vane_tip_clear", tip_clear)
	parent.set_meta("vane_slot_bottom", slot_bottom)
	parent.set_meta("vane_t_min", t_min)
	parent.set_meta("vane_t_max", t_max)
	apply_state(parent, el)
	return info


## Расстояние от оси ротора до стенки камеры вдоль угла θ (0 = +Z).
static func _chamber_wall_dist(theta: float, ecc: float, r_ch: float) -> float:
	var uc: float = ecc * cos(theta)
	var disc: float = uc * uc - ecc * ecc + r_ch * r_ch
	if disc < 0.0:
		return maxf(r_ch - ecc, 0.01)
	var root: float = sqrt(disc)
	var t1: float = uc - root
	var t2: float = uc + root
	if t1 > 0.01:
		return t1
	return maxf(t2, 0.01)


static func _build_body_csg(
	parent: Node3D,
	body_r: float, body_h: float, r_ch: float, h_ch: float, bore_r: float, ecc: float,
	chan_r: float, x_port: float, y_port: float, z_face: float, mat: Material
) -> void:
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	# Круглая часть (+Z) + прямоугольник на −Z → сверху «перевёрнутая U».
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 32))
	comb.add_child(CsgBake.box(
		Vector3(body_r * 2.0, body_h, body_r),
		Vector3(0.0, 0.0, -body_r * 0.5),
		UNION
	))
	# Камера эксцентрична к +Z: узкий зазор (лопатки задвинуты) у плоской грани −Z.
	# Верх/низ корпуса сплошные (h_ch < body_h) — отдельной крышки нет.
	comb.add_child(CsgBake.cyl(r_ch, h_ch, Vector3(0.0, 0.0, ecc), "y", SUB, 28))
	comb.add_child(CsgBake.cyl(bore_r, body_h + Parts.mm(2.0), Vector3.ZERO, "y", SUB, 20))
	# Каналы от плоской грани в зону сжатия.
	var z_into: float = - (r_ch - ecc) * 0.35
	_csg_chan_z(comb, chan_r, -x_port, y_port, z_face - chan_r * 0.15, z_into, SUB)
	_csg_chan_z(comb, chan_r, x_port, y_port, z_face - chan_r * 0.15, z_into, SUB)
	CsgBake.attach(parent, comb, mat, "window")


static func _csg_chan_z(
	comb: CSGCombiner3D, rad: float, x: float, y: float, z_from: float, z_to: float,
	op: CSGShape3D.Operation
) -> void:
	var lo: float = minf(z_from, z_to)
	var hi: float = maxf(z_from, z_to)
	var h: float = hi - lo + rad * 0.4
	comb.add_child(CsgBake.cyl(rad, h, Vector3(x, y, 0.5 * (lo + hi)), "z", op, 12))


static func _build_rotor_hub(
	rotor: Node3D, r_rot: float, h: float, shaft_r: float, vane_t: float,
	mat: Material, mat_slot: Material
) -> void:
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "HubCSG"
	comb.add_child(CsgBake.cyl(r_rot, h, Vector3.ZERO, "y", UNION, 28))
	# Сквозные пазы: от вала до наружного Ø — дно паза видно в рентгене.
	var slot_w: float = vane_t * 1.4
	var r_in: float = shaft_r * 1.2
	var slot_len: float = (r_rot - r_in) + Parts.mm(1.2)
	var slot_mid: float = 0.5 * (r_in + r_rot)
	var slot_h: float = h * 1.08
	for i in VANE_COUNT:
		var ang: float = TAU * float(i) / float(VANE_COUNT)
		var cx: float = sin(ang) * slot_mid
		var cz: float = cos(ang) * slot_mid
		var slot := CsgBake.box(Vector3(slot_w, slot_h, slot_len), Vector3(cx, 0.0, cz), SUB)
		slot.rotation.y = ang
		comb.add_child(slot)
	comb.add_child(CsgBake.cyl(shaft_r * 1.02, h + Parts.mm(1.0), Vector3.ZERO, "y", SUB, 16))
	CsgBake.attach(rotor, comb, mat, "internal")
	# Тёмное «дно» паза — читается ход каблука лопатки.
	for i in VANE_COUNT:
		var ang2: float = TAU * float(i) / float(VANE_COUNT)
		var floor_mi := MeshInstance3D.new()
		floor_mi.name = "SlotFloor%d" % i
		floor_mi.mesh = BoxMesh.new()
		(floor_mi.mesh as BoxMesh).size = Vector3(slot_w * 0.92, Parts.mm(0.8), slot_len * 0.96)
		floor_mi.position = Vector3(
			sin(ang2) * slot_mid, -h * 0.42, cos(ang2) * slot_mid
		)
		floor_mi.rotation.y = ang2
		floor_mi.material_override = mat_slot
		floor_mi.set_meta("xray_role", "internal")
		rotor.add_child(floor_mi)


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
	var th: float = float(el.angle)
	rotor.rotation.y = th
	var r_ch: float = float(root.get_meta("vane_r_ch", 0.02))
	var ecc: float = float(root.get_meta("vane_ecc", 0.004))
	var vane_len: float = float(root.get_meta("vane_len", 0.02))
	var tip_clear: float = float(root.get_meta("vane_tip_clear", 0.0003))
	var n: int = int(root.get_meta("vane_count", VANE_COUNT))
	for i in n:
		var slide: Node3D = rotor.get_node_or_null("Vane%d" % i) as Node3D
		if slide == null:
			continue
		var blade: MeshInstance3D = slide.get_node_or_null("Blade") as MeshInstance3D
		if blade == null:
			continue
		var local_ang: float = float(slide.get_meta("vane_local_ang", TAU * float(i) / float(n)))
		# Подпружинена наружу: кончик у стенки; длина фиксирована (дно паза→стенка при задвижении).
		var world_ang: float = local_ang + th
		var tip_r: float = _chamber_wall_dist(world_ang, ecc, r_ch) - tip_clear
		var slot_bottom: float = float(root.get_meta("vane_slot_bottom", 0.0))
		# Не тонуть за дно паза (численный запас).
		tip_r = maxf(tip_r, slot_bottom + vane_len)
		var mid_z: float = tip_r - vane_len * 0.5
		blade.position = Vector3(0.0, 0.0, mid_z)


static func apply_xray(root: Node3D, on: bool) -> void:
	if root == null:
		return
	Iso.apply_xray(root, on, false)
