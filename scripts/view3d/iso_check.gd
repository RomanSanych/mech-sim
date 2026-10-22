class_name IsoCheck
extends RefCounted
## 3D обратный клапан: серебристый цилиндр, фитинги, шар + пружина.
## Порт 1 (седло/треугольник, −X) → порт 2 (пружина, +X).
## Канал: у седла уже шара; дальше чуть шире шара. Масштаб от OD трубки.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_l: float = Parts.mm(36.0) * body_s
	var body_r: float = Parts.mm(9.0) * body_s
	var ball_r: float = Parts.mm(3.6) * body_s
	var seat_r: float = ball_r * 0.62
	var bore_r: float = ball_r * 1.12
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.72
	var seat_x: float = -body_l * 0.12
	_build_body(parent, body_l, body_r, seat_x, seat_r, bore_r)
	var tip_l: Vector3 = Parts.add_fitting(
		parent, Vector3(-body_l * 0.5 + embed, 0.0, 0.0), "-x", fit_scale, true
	)
	var tip_r: Vector3 = Parts.add_fitting(
		parent, Vector3(body_l * 0.5 - embed, 0.0, 0.0), "x", fit_scale, true
	)
	info["ports"]["1"] = tip_l
	info["ports"]["2"] = tip_r
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	_build_internals(parent, body_l, seat_x, ball_r, seat_r, body_s)
	apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_r + Parts.mm(14.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_check", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(12.0) * body_s, -body_r, -body_r),
		Vector3(body_l + Parts.mm(24.0) * body_s, body_r * 2.0, body_r * 2.0)
	))
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null:
		return
	var open: float = clampf(float(el.opening), 0.0, 1.0)
	var ball: Node3D = root.get_node_or_null("CheckBall") as Node3D
	if ball != null:
		var x0: float = float(ball.get_meta("x0", ball.position.x))
		ball.set_meta("x0", x0)
		var travel: float = float(ball.get_meta("travel", Parts.mm(7.0)))
		ball.position.x = x0 + open * travel
	var spring: Node3D = root.get_node_or_null("CheckSpring") as Node3D
	if spring != null:
		_refresh_spring(spring, open)


static func _body_silver() -> StandardMaterial3D:
	return Parts.mat("check_body", Color(0.72, 0.74, 0.76), 0.82, 0.32)


static func _build_body(
	parent: Node, body_l: float, body_r: float, seat_x: float, seat_r: float, bore_r: float
) -> void:
	var mat: Material = _body_silver()
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_l, Vector3.ZERO, "x", UNION, 32))
	# Входной канал порт 1 → седло: диаметр седла, иначе в рентгене «дыра» между штуцером и кольцом.
	var inlet_from: float = -body_l * 0.5 + Parts.mm(1.2)
	var inlet_to: float = seat_x - Parts.mm(0.6)
	var inlet_len: float = maxf(inlet_to - inlet_from, Parts.mm(2.0))
	var inlet_cx: float = inlet_from + inlet_len * 0.5
	comb.add_child(CsgBake.cyl(seat_r, inlet_len, Vector3(inlet_cx, 0.0, 0.0), "x", SUB, 16))
	# Камера хода шара (после седла): чуть шире шара — начинается СРАЗУ справа от седла.
	var chamber_len: float = body_l * 0.5 - seat_x + Parts.mm(1.0)
	var chamber_cx: float = seat_x + Parts.mm(0.4) + chamber_len * 0.5
	comb.add_child(CsgBake.cyl(bore_r, chamber_len, Vector3(chamber_cx, 0.0, 0.0), "x", SUB, 18))
	# Явная ступенька седла: тонкий диск-отверстие seat_r в плоскости seat_x.
	comb.add_child(CsgBake.cyl(
		seat_r, Parts.mm(1.6), Vector3(seat_x, 0.0, 0.0), "x", SUB, 16
	))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_internals(
	parent: Node, body_l: float, seat_x: float, ball_r: float, seat_r: float, body_s: float
) -> void:
	var travel: float = Parts.mm(7.0) * body_s
	var spring_end: float = body_l * 0.36
	# Видимое кольцо седла (торец ступеньки) — чуть больше отверстия.
	Parts.cyl(
		parent, seat_r * 1.35, Parts.mm(1.4) * body_s,
		Vector3(seat_x - Parts.mm(0.5) * body_s, 0.0, 0.0), "x",
		Parts.mat("check_seat", Color(0.42, 0.44, 0.47), 0.55, 0.45),
		18, "internal"
	)
	# Шар закрыт: прижат к седлу справа от ступеньки.
	var x0: float = seat_x + ball_r * 0.15
	var ball := MeshInstance3D.new()
	ball.name = "CheckBall"
	var sph := SphereMesh.new()
	sph.radius = ball_r
	sph.height = ball_r * 2.0
	sph.radial_segments = 20
	sph.rings = 12
	ball.mesh = sph
	ball.position = Vector3(x0, 0.0, 0.0)
	ball.set_meta("x0", x0)
	ball.set_meta("travel", travel)
	ball.set_meta("spring_end", spring_end)
	ball.material_override = Parts.mat("check_ball", Color(0.62, 0.63, 0.66), 0.9, 0.22)
	ball.set_meta("xray_role", "internal")
	parent.add_child(ball)
	var spring := Node3D.new()
	spring.name = "CheckSpring"
	spring.set_meta("xray_role", "internal")
	spring.set_meta("ball_r", ball_r)
	spring.set_meta("spring_end", spring_end)
	spring.set_meta("x0", x0)
	spring.set_meta("travel", travel)
	spring.set_meta("body_s", body_s)
	parent.add_child(spring)
	_refresh_spring(spring, 0.0)


static func _refresh_spring(spring: Node3D, open: float) -> void:
	var ball_r: float = float(spring.get_meta("ball_r", Parts.mm(3.6)))
	var spring_end: float = float(spring.get_meta("spring_end", Parts.mm(10.0)))
	var x0: float = float(spring.get_meta("x0", 0.0))
	var travel: float = float(spring.get_meta("travel", Parts.mm(7.0)))
	var body_s: float = float(spring.get_meta("body_s", 1.0))
	var ball_x: float = x0 + clampf(open, 0.0, 1.0) * travel
	var x_start: float = ball_x + ball_r * 0.92
	var x_end: float = spring_end
	if x_end < x_start + Parts.mm(2.0) * body_s:
		x_end = x_start + Parts.mm(2.0) * body_s
	var mi := spring.get_node_or_null("Coil") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Coil"
		mi.material_override = Parts.mat("check_spring", Color(0.78, 0.72, 0.35), 0.92, 0.28)
		mi.set_meta("xray_role", "internal")
		spring.add_child(mi)
	var IsoCyl = preload("res://scripts/view3d/iso_cylinder.gd")
	mi.mesh = IsoCyl._build_helix_spring_mesh(
		x_start, x_end, Parts.mm(2.6) * body_s, Parts.mm(0.35) * body_s, 7
	)
