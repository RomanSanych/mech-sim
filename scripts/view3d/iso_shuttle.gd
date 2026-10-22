class_name IsoShuttle
extends RefCounted
## 3D клапан «ИЛИ» (shuttle): корпус как у ОК, фитинги слева/справа/сверху.
## Шарик давлением к левому или правому седлу → путь 2→3 или 1→3.
## opening 0 = у седла 1 (−X), 1 = у седла 2 (+X).

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
	var body_l: float = Parts.mm(40.0) * body_s
	var body_r: float = Parts.mm(10.0) * body_s
	var ball_r: float = Parts.mm(3.8) * body_s
	var seat_r: float = ball_r * 0.62
	var bore_r: float = ball_r * 1.15
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.72
	var seat_l: float = -body_l * 0.22
	var seat_r_x: float = body_l * 0.22
	_build_body(parent, body_l, body_r, seat_l, seat_r_x, seat_r, bore_r)
	var tip_l: Vector3 = Parts.add_fitting(
		parent, Vector3(-body_l * 0.5 + embed, 0.0, 0.0), "-x", fit_scale, true
	)
	var tip_r: Vector3 = Parts.add_fitting(
		parent, Vector3(body_l * 0.5 - embed, 0.0, 0.0), "x", fit_scale, true
	)
	# Общий выход — сверху (как просил пользователь).
	var tip_t: Vector3 = Parts.add_fitting(
		parent, Vector3(0.0, body_r * 0.15, 0.0), "y", fit_scale * 0.95, true
	)
	info["ports"]["1"] = tip_l
	info["ports"]["2"] = tip_r
	info["ports"]["3"] = tip_t
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	info["dirs"]["3"] = Vector3.UP
	_build_internals(parent, seat_l, seat_r_x, ball_r, seat_r, body_s)
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
	parent.set_meta("accessory_shuttle", true)
	parent.set_meta("xray_role", "window")
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null:
		return
	var side: float = clampf(float(el.opening), 0.0, 1.0)
	var ball: Node3D = root.get_node_or_null("ShuttleBall") as Node3D
	if ball == null:
		return
	var x0: float = float(ball.get_meta("x_left", ball.position.x))
	var x1: float = float(ball.get_meta("x_right", ball.position.x))
	ball.position.x = lerpf(x0, x1, side)


static func _body_mat() -> StandardMaterial3D:
	return Parts.mat("shuttle_body", Color(0.70, 0.73, 0.76), 0.8, 0.34)


static func _build_body(
	parent: Node,
	body_l: float,
	body_r: float,
	seat_l: float,
	seat_r_x: float,
	seat_or: float,
	bore_r: float
) -> void:
	var mat: Material = _body_mat()
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_l, Vector3.ZERO, "x", UNION, 32))
	# Камера между сёдлами.
	var chamber_len: float = seat_r_x - seat_l + Parts.mm(2.0)
	var chamber_cx: float = (seat_l + seat_r_x) * 0.5
	comb.add_child(CsgBake.cyl(bore_r, chamber_len, Vector3(chamber_cx, 0.0, 0.0), "x", SUB, 18))
	# Каналы к портам 1/2.
	comb.add_child(CsgBake.cyl(
		seat_or, absf(seat_l + body_l * 0.5),
		Vector3((-body_l * 0.5 + seat_l) * 0.5, 0.0, 0.0), "x", SUB, 14
	))
	comb.add_child(CsgBake.cyl(
		seat_or, absf(body_l * 0.5 - seat_r_x),
		Vector3((seat_r_x + body_l * 0.5) * 0.5, 0.0, 0.0), "x", SUB, 14
	))
	# Канал вверх к порту 3.
	comb.add_child(CsgBake.cyl(
		seat_or * 1.05, body_r * 1.1, Vector3(0.0, body_r * 0.35, 0.0), "y", SUB, 14
	))
	# Сёдла — кольцевые ступеньки.
	comb.add_child(CsgBake.cyl(seat_or, Parts.mm(1.5), Vector3(seat_l, 0.0, 0.0), "x", SUB, 14))
	comb.add_child(CsgBake.cyl(seat_or, Parts.mm(1.5), Vector3(seat_r_x, 0.0, 0.0), "x", SUB, 14))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_internals(
	parent: Node,
	seat_l: float,
	seat_r_x: float,
	ball_r: float,
	seat_or: float,
	body_s: float
) -> void:
	var seat_mat: Material = Parts.mat("shuttle_seat", Color(0.42, 0.44, 0.47), 0.55, 0.45)
	Parts.cyl(
		parent, seat_or * 1.35, Parts.mm(1.3) * body_s,
		Vector3(seat_l, 0.0, 0.0), "x", seat_mat, 16, "internal"
	)
	Parts.cyl(
		parent, seat_or * 1.35, Parts.mm(1.3) * body_s,
		Vector3(seat_r_x, 0.0, 0.0), "x", seat_mat, 16, "internal"
	)
	# Касание седла снаружи камеры — без утопания в кольцо.
	var x_left: float = seat_l + ball_r
	var x_right: float = seat_r_x - ball_r
	var ball := MeshInstance3D.new()
	ball.name = "ShuttleBall"
	var sph := SphereMesh.new()
	sph.radius = ball_r
	sph.height = ball_r * 2.0
	ball.mesh = sph
	ball.material_override = Parts.mat("shuttle_ball", Color(0.88, 0.55, 0.22), 0.35, 0.55)
	ball.position = Vector3((x_left + x_right) * 0.5, 0.0, 0.0)
	ball.set_meta("x_left", x_left)
	ball.set_meta("x_right", x_right)
	ball.set_meta("xray_role", "internal")
	parent.add_child(ball)
