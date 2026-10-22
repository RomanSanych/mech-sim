class_name IsoAnd
extends RefCounted
## 3D клапан «И»: две торцевые полости + средняя (порт 3), седла-перегородки между ними.
## opening 0.5 = зазор конус↔седло (оба входа → 3); 0/1 = конус в седле (стравливание).

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 8.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_l: float = Parts.mm(54.0) * body_s
	var body_r: float = Parts.mm(11.0) * body_s
	var bore_r: float = Parts.mm(5.5) * body_s
	var seat_or: float = Parts.mm(2.9) * body_s
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.28
	# Седла внутрь от штуцеров: видны в «окне», короткая гантель, есть ход.
	var wall_l: float = -body_l * 0.20
	var wall_r: float = body_l * 0.20
	var end_l: float = -body_l * 0.40
	var end_r: float = body_l * 0.40
	_build_body(parent, body_l, body_r, wall_l, wall_r, seat_or, bore_r, body_s)
	_add_seat_rings(parent, wall_l, wall_r, bore_r, seat_or, body_s)
	var tip_l: Vector3 = Parts.add_fitting(
		parent, Vector3(-body_l * 0.5 + embed, 0.0, 0.0), "-x", fit_scale, true
	)
	var tip_r: Vector3 = Parts.add_fitting(
		parent, Vector3(body_l * 0.5 - embed, 0.0, 0.0), "x", fit_scale, true
	)
	var tip_t: Vector3 = Parts.add_fitting(
		parent, Vector3(0.0, body_r - Parts.mm(0.8) * body_s, 0.0), "y", fit_scale * 0.92, true
	)
	info["ports"]["1"] = tip_l
	info["ports"]["2"] = tip_r
	info["ports"]["3"] = tip_t
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	info["dirs"]["3"] = Vector3.UP
	_build_spool(parent, wall_l, wall_r, end_l, end_r, bore_r, seat_or, body_s)
	apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_r + Parts.mm(18.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_and_valve", true)
	parent.set_meta("xray_role", "window")
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null:
		return
	var side: float = clampf(float(el.opening), 0.0, 1.0)
	var spool: Node3D = root.get_node_or_null("AndSpool") as Node3D
	if spool == null:
		return
	var x0: float = float(spool.get_meta("x_left", spool.position.x))
	var x1: float = float(spool.get_meta("x_right", spool.position.x))
	spool.position.x = lerpf(x0, x1, side)


static func _body_mat() -> StandardMaterial3D:
	return Parts.mat("and_body", Color(0.70, 0.73, 0.76), 0.8, 0.34)


static func _build_body(
	parent: Node,
	body_l: float,
	body_r: float,
	wall_l: float,
	wall_r: float,
	seat_or: float,
	bore_r: float,
	body_s: float
) -> void:
	var mat: Material = _body_mat()
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_l, Vector3.ZERO, "x", UNION, 32))
	# Сквозной канал одного диаметра — средняя и крайние полости.
	var bore_len: float = body_l * 0.82 + Parts.mm(1.0)
	comb.add_child(CsgBake.cyl(bore_r, bore_len, Vector3.ZERO, "x", SUB, 24))
	# Седла-перегородки: кольца в канале с отверстием (UNION диск − отверстие).
	var ring_h: float = Parts.mm(2.4) * body_s
	_add_body_seat(comb, wall_l, -1.0, bore_r, seat_or, ring_h, body_s, UNION, SUB)
	_add_body_seat(comb, wall_r, 1.0, bore_r, seat_or, ring_h, body_s, UNION, SUB)
	# Выход 3 из средней камеры (между седлами).
	comb.add_child(CsgBake.cyl(
		seat_or * 1.2, body_r * 1.15, Vector3(0.0, body_r * 0.42, 0.0), "y", SUB, 14
	))
	CsgBake.attach(parent, comb, mat, "window")


## Перегородка-седло в теле: диск на всю ширину канала + отверстие + конус ртом к штуцеру.
static func _add_body_seat(
	comb: CSGCombiner3D,
	seat_x: float,
	side_sign: float,
	bore_r: float,
	seat_or: float,
	ring_h: float,
	body_s: float,
	UNION: CSGShape3D.Operation,
	SUB: CSGShape3D.Operation
) -> void:
	comb.add_child(CsgBake.cyl(bore_r * 0.995, ring_h, Vector3(seat_x, 0.0, 0.0), "x", UNION, 22))
	# Коническая чашка со стороны штуцера (вычитание конуса).
	var cup_h: float = Parts.mm(2.6) * body_s
	var pocket := CSGCylinder3D.new()
	pocket.radius = bore_r * 0.92
	pocket.height = cup_h
	pocket.cone = true
	pocket.sides = 20
	pocket.operation = SUB
	pocket.position = Vector3(seat_x + side_sign * (ring_h * 0.15 + cup_h * 0.35), 0.0, 0.0)
	if side_sign < 0.0:
		pocket.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	else:
		pocket.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	comb.add_child(pocket)
	# Сквозное отверстие седла.
	comb.add_child(CsgBake.cyl(
		seat_or, ring_h + cup_h + Parts.mm(1.2) * body_s,
		Vector3(seat_x + side_sign * cup_h * 0.2, 0.0, 0.0), "x", SUB, 18
	))


## Тёмные кольца на седлах — читаются в рентгене поверх полупрозрачного корпуса.
static func _add_seat_rings(
	parent: Node, wall_l: float, wall_r: float, bore_r: float, seat_or: float, body_s: float
) -> void:
	var seat_mat: Material = Parts.mat("and_seat", Color(0.22, 0.24, 0.28), 0.35, 0.62)
	var tube_r: float = maxf((bore_r - seat_or) * 0.38, Parts.mm(0.9) * body_s)
	Parts.oring(parent, seat_or * 1.05, tube_r, Vector3(wall_l, 0.0, 0.0), "x", seat_mat)
	Parts.oring(parent, seat_or * 1.05, tube_r, Vector3(wall_r, 0.0, 0.0), "x", seat_mat)


static func _build_spool(
	parent: Node,
	wall_l: float,
	wall_r: float,
	end_l: float,
	end_r: float,
	bore_r: float,
	seat_or: float,
	body_s: float
) -> void:
	var spool := Node3D.new()
	spool.name = "AndSpool"
	spool.set_meta("xray_role", "internal")
	var rod_r: float = Parts.mm(1.2) * body_s
	var plate_r: float = bore_r * 0.88
	var plate_h: float = Parts.mm(1.6) * body_s
	var cone_h: float = Parts.mm(3.2) * body_s
	var tip_r: float = seat_or * 0.55
	# Зазор конус↔седло в центре — кольцевой проход в среднюю камеру.
	var gap: float = Parts.mm(2.8) * body_s
	var mat_rod: Material = Parts.mat("and_spool", Color(0.78, 0.52, 0.22), 0.4, 0.5)
	var mat_plate: Material = Parts.mat("and_plate", Color(0.42, 0.45, 0.50), 0.4, 0.52)
	# Тарелки в крайних полостях (снаружи седел), конусы смотрят к седлам.
	var left_plate_x: float = wall_l - gap - cone_h - plate_h * 0.5
	var right_plate_x: float = wall_r + gap + cone_h + plate_h * 0.5
	left_plate_x = maxf(left_plate_x, end_l + plate_h * 0.55)
	right_plate_x = minf(right_plate_x, end_r - plate_h * 0.55)
	var rod_len: float = right_plate_x - left_plate_x
	Parts.cyl(spool, rod_r, maxf(rod_len, Parts.mm(2.0)), Vector3.ZERO, "x", mat_rod, 12, "internal")
	Parts.cyl(
		spool, plate_r, plate_h,
		Vector3(left_plate_x, 0.0, 0.0), "x", mat_plate, 20, "internal"
	)
	Parts.frustum(
		spool, tip_r, plate_r, cone_h,
		Vector3(left_plate_x + plate_h * 0.35 + cone_h * 0.5, 0.0, 0.0),
		"x", mat_plate, 20, "internal"
	)
	Parts.cyl(
		spool, plate_r, plate_h,
		Vector3(right_plate_x, 0.0, 0.0), "x", mat_plate, 20, "internal"
	)
	Parts.frustum(
		spool, tip_r, plate_r, cone_h,
		Vector3(right_plate_x - plate_h * 0.35 - cone_h * 0.5, 0.0, 0.0),
		"-x", mat_plate, 20, "internal"
	)
	# Ход: конус доходит до седла; запас до торца полости.
	var seat_travel: float = gap + cone_h * 0.45
	var lim_l: float = absf(left_plate_x - end_l) - plate_h * 0.2
	var lim_r: float = absf(end_r - right_plate_x) - plate_h * 0.2
	var travel: float = minf(seat_travel, minf(lim_l, lim_r))
	travel = maxf(travel, Parts.mm(2.0) * body_s)
	spool.set_meta("x_left", -travel)
	spool.set_meta("x_right", travel)
	spool.set_meta("plate_r", plate_r)
	spool.set_meta("bore_r", bore_r)
	spool.position = Vector3.ZERO
	parent.add_child(spool)
