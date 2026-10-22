class_name IsoThrottleCheck
extends RefCounted
## 3D дроссель с ОК — как на УГО: один вход / один выход,
## внутри два параллельных канала, соединённых галереями на торцах.
## Верхний — дроссель (винт); нижний — КО.
## КО: седло у порта 2; пружина со стороны порта 1; поток 2→1 (от ПЦ)
## давит на шар со стороны без пружины и отжимает его от седла.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const IsoThrottle = preload("res://scripts/view3d/iso_throttle.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var fixed: bool = str(el.accessory_class) == "throttle_check_fixed"
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_l: float = Parts.mm(44.0) * body_s
	# Выше/ниже — место под разнесённые каналы и упор пружины.
	var body_h: float = Parts.mm(40.0) * body_s
	var body_d: float = Parts.mm(20.0) * body_s
	var fillet_r: float = Parts.mm(3.0) * body_s
	# Дроссель выше оси штуцеров; КО заметно ниже — без пересечения с винтом.
	var thr_y: float = Parts.mm(2.0) * body_s
	var chk_y: float = -Parts.mm(11.0) * body_s
	var black := Parts.black()
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.55
	var ball_r: float = Parts.mm(3.0) * body_s
	var seat_r: float = ball_r * 0.58
	var bore_r: float = ball_r * 1.14
	# Седло у порта 2 (+X); камера шара слева; пружина ещё левее (порт 1).
	var seat_x: float = body_l * 0.12
	_build_body_csg(
		parent, fixed, body_l, body_h, body_d, fillet_r, embed, black, body_s,
		thr_y, chk_y, seat_x, seat_r, bore_r, ball_r
	)
	var tip_l: Vector3 = Parts.add_fitting(
		parent, Vector3(-body_l * 0.5 + embed, thr_y, 0.0), "-x", fit_scale, true
	)
	var tip_r: Vector3 = Parts.add_fitting(
		parent, Vector3(body_l * 0.5 - embed, thr_y, 0.0), "x", fit_scale, true
	)
	info["ports"]["1"] = tip_l
	info["ports"]["2"] = tip_r
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	_build_check_internals(parent, body_l, seat_x, ball_r, seat_r, bore_r, body_s, chk_y)
	if not fixed:
		_build_throttle_screw(parent, body_h, body_s, thr_y)
	parent.set_meta("thr_y", thr_y)
	parent.set_meta("chk_y", chk_y)
	parent.set_meta("throttle_fixed", fixed)
	parent.set_meta("accessory_throttle_check", true)
	parent.set_meta("body_s", body_s)
	apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(16.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(12.0) * body_s, -body_h * 0.5, -body_d * 0.5),
		Vector3(body_l + Parts.mm(24.0) * body_s, body_h, body_d)
	))
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	if not bool(root.get_meta("throttle_fixed", false)):
		IsoThrottle.apply_opening(root, el)
	var press = el.get("port_press")
	var p1: float = 101325.0
	var p2: float = 101325.0
	if press is Dictionary:
		p1 = float((press as Dictionary).get("1", 101325.0))
		p2 = float((press as Dictionary).get("2", 101325.0))
	var crack_bar: float = 0.2
	if el.get("crack_pressure_bar") != null:
		crack_bar = float(el.get("crack_pressure_bar"))
	var crack_pa: float = clampf(crack_bar, 0.01, 5.0) * 1.0e5
	# Открытие КО при давлении со стороны ПЦ (порт 2).
	var check_open: float = clampf(((p2 - p1) - crack_pa) / 0.30e5, 0.0, 1.0)
	var ball: Node3D = root.get_node_or_null("CheckBall") as Node3D
	if ball != null:
		var x0: float = float(ball.get_meta("x0", ball.position.x))
		var travel: float = float(ball.get_meta("travel", Parts.mm(6.0)))
		var chk_y: float = float(ball.get_meta("chk_y", ball.position.y))
		# От седла (справа) — влево, к пружине.
		ball.position = Vector3(x0 - check_open * travel, chk_y, 0.0)
	var spring: Node3D = root.get_node_or_null("CheckSpring") as Node3D
	if spring != null:
		_refresh_check_spring(spring, check_open)


static func pick_screw(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	if root == null or bool(root.get_meta("throttle_fixed", false)):
		return false
	return IsoThrottle.pick_screw(root, origin, dir)


static func _build_body_csg(
	parent: Node, fixed: bool, body_l: float, body_h: float, body_d: float,
	fillet_r: float, embed: float, mat: Material, body_s: float,
	thr_y: float, chk_y: float, seat_x: float, seat_r: float, bore_r: float, ball_r: float
) -> void:
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var r: float = fillet_r
	var hl: float = body_l * 0.5
	var hh: float = body_h * 0.5
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.box(Vector3(body_l - 2.0 * r, body_h, body_d), Vector3.ZERO))
	comb.add_child(CsgBake.box(Vector3(body_l, body_h - 2.0 * r, body_d), Vector3.ZERO))
	var corners: Array = [
		Vector3(-(hl - r), -(hh - r), 0.0),
		Vector3(hl - r, -(hh - r), 0.0),
		Vector3(-(hl - r), hh - r, 0.0),
		Vector3(hl - r, hh - r, 0.0),
	]
	for cpos in corners:
		comb.add_child(CsgBake.cyl(r, body_d, cpos as Vector3, "z", UNION, 12))

	var r_thr: float = Parts.mm(2.9) * body_s
	var tunnel_len: float = body_l + embed * 2.0 + Parts.mm(4.0) * body_s
	comb.add_child(CsgBake.cyl(r_thr, tunnel_len, Vector3(0.0, thr_y, 0.0), "x", SUB, 20))

	# Перемычки и канал КО одного Ø — стык без «ступеньки».
	var gal_r: float = bore_r
	var gal_x_l: float = -hl + Parts.mm(5.5) * body_s
	var gal_x_r: float = hl - Parts.mm(5.5) * body_s
	# Горизонталь заходит за ось перемычки на полный радиус — иначе торец
	# цилиндра оставляет «мембрану» в месте T-стыка.
	var overlap: float = gal_r
	var chamber_from: float = gal_x_l - overlap
	var chamber_to: float = seat_x - Parts.mm(0.6) * body_s
	var chamber_len: float = maxf(chamber_to - chamber_from, ball_r * 3.5)
	var chamber_cx: float = chamber_from + chamber_len * 0.5
	comb.add_child(CsgBake.cyl(bore_r, chamber_len, Vector3(chamber_cx, chk_y, 0.0), "x", SUB, 18))
	# Узкое седло — единственная ступенька в канале.
	comb.add_child(CsgBake.cyl(
		seat_r, Parts.mm(3.2) * body_s, Vector3(seat_x, chk_y, 0.0), "x", SUB, 16
	))
	# Выход снова Ø канала до правой перемычки.
	var out_from: float = seat_x + Parts.mm(0.8) * body_s
	var out_to: float = gal_x_r + overlap
	var out_len: float = maxf(out_to - out_from, Parts.mm(4.0) * body_s)
	var out_cx: float = out_from + out_len * 0.5
	comb.add_child(CsgBake.cyl(bore_r, out_len, Vector3(out_cx, chk_y, 0.0), "x", SUB, 18))

	# Вертикальные круглые перемычки thr↔chk (Ø = bore_r).
	# Высота с запасом на оба радиуса — перемычка «съедает» стенки каналов.
	var gal_h: float = absf(thr_y - chk_y) + r_thr + bore_r
	var gal_y: float = 0.5 * (thr_y + chk_y)
	comb.add_child(CsgBake.cyl(gal_r, gal_h, Vector3(gal_x_l, gal_y, 0.0), "y", SUB, 18))
	comb.add_child(CsgBake.cyl(gal_r, gal_h, Vector3(gal_x_r, gal_y, 0.0), "y", SUB, 18))

	if fixed:
		var r_neck: float = Parts.mm(0.95) * body_s
		var gap: float = Parts.mm(3.5) * body_s
		comb.add_child(CsgBake.cyl(r_thr + Parts.mm(0.25) * body_s, gap, Vector3(0.0, thr_y, 0.0), "x", UNION, 20))
		comb.add_child(CsgBake.cyl(r_neck, gap + Parts.mm(1.0) * body_s, Vector3(0.0, thr_y, 0.0), "x", SUB, 16))
	else:
		var r_seat: float = Parts.mm(2.6) * body_s
		var seat_gap: float = Parts.mm(5.0) * body_s
		comb.add_child(CsgBake.cyl(r_thr + Parts.mm(0.25) * body_s, seat_gap, Vector3(0.0, thr_y, 0.0), "x", UNION, 20))
		comb.add_child(CsgBake.cyl(r_seat, seat_gap, Vector3(0.0, thr_y, 0.0), "x", SUB, 16))
		var well_h: float = body_h * 0.5 - thr_y + Parts.mm(4.0) * body_s
		var well_cy: float = thr_y + well_h * 0.5
		comb.add_child(CsgBake.cyl(
			Parts.mm(3.4) * body_s, well_h, Vector3(0.0, well_cy, 0.0), "y", SUB, 18
		))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_throttle_screw(parent: Node, body_h: float, body_s: float, thr_y: float) -> void:
	IsoThrottle._build_brass_screw(parent, body_h, body_s)
	var screw: Node3D = parent.get_node_or_null("ThrottleScrew") as Node3D
	if screw == null:
		return
	var tip_y: float = thr_y - screw.position.y
	for ch in screw.get_children():
		if ch is MeshInstance3D and str(ch.name) != "HeadCSG":
			var mi: MeshInstance3D = ch as MeshInstance3D
			var mesh: CylinderMesh = mi.mesh as CylinderMesh
			if mesh == null:
				continue
			var shaft_top: float = 0.0
			var shaft_bot: float = tip_y + Parts.mm(0.4) * body_s
			var shaft_h: float = maxf(shaft_top - shaft_bot, Parts.mm(1.0) * body_s)
			mesh.height = shaft_h
			mi.position.y = 0.5 * (shaft_top + shaft_bot)
			break


## Седло у +X (порт 2); упор пружины у порта 1 (−X).
static func _build_check_internals(
	parent: Node, body_l: float, seat_x: float, ball_r: float, seat_r: float,
	bore_r: float, body_s: float, chk_y: float
) -> void:
	var travel: float = Parts.mm(5.5) * body_s
	var abutment_x: float = -body_l * 0.28
	# Торец пружины на плоскости кольца-упора.
	var spring_end: float = abutment_x + Parts.mm(0.6) * body_s
	var seat_mat := Parts.mat("tc_seat", Color(0.38, 0.40, 0.43), 0.55, 0.42)
	var seat_face := Parts.mat("tc_seat_face", Color(0.28, 0.30, 0.33), 0.45, 0.5)
	var stop_mat := Parts.mat("tc_spring_stop", Color(0.55, 0.52, 0.42), 0.75, 0.38)
	# Обод седла (наружный) — ступенька в канале.
	Parts.cyl(
		parent, bore_r * 0.98, Parts.mm(2.4) * body_s,
		Vector3(seat_x + Parts.mm(0.3) * body_s, chk_y, 0.0), "x", seat_mat, 20, "internal"
	)
	# Торцевая «чашка» седла — плоскость, к которой прилегает шар (смотрит в −X).
	Parts.cyl(
		parent, seat_r * 1.55, Parts.mm(1.2) * body_s,
		Vector3(seat_x - Parts.mm(0.55) * body_s, chk_y, 0.0), "x", seat_face, 20, "internal"
	)
	# Устье отверстия седла.
	Parts.cyl(
		parent, seat_r * 1.05, Parts.mm(1.6) * body_s,
		Vector3(seat_x, chk_y, 0.0), "x",
		Parts.mat("tc_seat_bore", Color(0.22, 0.23, 0.25), 0.4, 0.55),
		16, "internal"
	)
	# Упор пружины — кольцо с большим отверстием (воздух идёт сквозь центр).
	_add_spring_abutment_ring(parent, abutment_x, chk_y, bore_r, body_s, stop_mat)
	# Закрыт: шар слева у торца седла.
	var x0: float = seat_x - Parts.mm(0.55) * body_s - ball_r * 0.92
	var ball := MeshInstance3D.new()
	ball.name = "CheckBall"
	var sph := SphereMesh.new()
	sph.radius = ball_r
	sph.height = ball_r * 2.0
	sph.radial_segments = 20
	sph.rings = 12
	ball.mesh = sph
	ball.position = Vector3(x0, chk_y, 0.0)
	ball.set_meta("x0", x0)
	ball.set_meta("chk_y", chk_y)
	ball.set_meta("travel", travel)
	ball.set_meta("spring_end", spring_end)
	ball.material_override = Parts.mat("tc_ball", Color(0.62, 0.63, 0.66), 0.9, 0.22)
	ball.set_meta("xray_role", "internal")
	parent.add_child(ball)
	var spring := Node3D.new()
	spring.name = "CheckSpring"
	spring.position = Vector3(0.0, chk_y, 0.0)
	spring.set_meta("xray_role", "internal")
	spring.set_meta("ball_r", ball_r)
	spring.set_meta("spring_end", spring_end)
	spring.set_meta("x0", x0)
	spring.set_meta("travel", travel)
	spring.set_meta("body_s", body_s)
	spring.set_meta("chk_y", chk_y)
	parent.add_child(spring)
	_refresh_check_spring(spring, 0.0)


## Кольцо-упор: тонкий обод у стенки канала, центр открыт под воздух и пружину.
static func _add_spring_abutment_ring(
	parent: Node, x: float, y: float, bore_r: float, body_s: float, mat: Material
) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "SpringAbutment"
	var torus := TorusMesh.new()
	# Как Parts.oring: inner/outer — крайние радиусы от оси тора (отверстие = inner).
	var minor: float = Parts.mm(0.55) * body_s
	var major: float = bore_r * 0.82
	torus.inner_radius = maxf(major - minor, bore_r * 0.55)
	torus.outer_radius = minf(major + minor, bore_r * 0.96)
	torus.rings = 18
	torus.ring_segments = 12
	ring.mesh = torus
	ring.material_override = mat
	ring.set_meta("xray_role", "internal")
	# Тор по умолчанию вокруг Y; ось канала = X → поворот как у Parts.oring.
	ring.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	ring.position = Vector3(x, y, 0.0)
	parent.add_child(ring)


## Пружина слева от шара: при открытии (шар ←) сжимается.
static func _refresh_check_spring(spring: Node3D, open: float) -> void:
	var ball_r: float = float(spring.get_meta("ball_r", Parts.mm(3.0)))
	var spring_end: float = float(spring.get_meta("spring_end", -0.01))
	var x0: float = float(spring.get_meta("x0", 0.0))
	var travel: float = float(spring.get_meta("travel", Parts.mm(5.5)))
	var body_s: float = float(spring.get_meta("body_s", 1.0))
	var ball_x: float = x0 - clampf(open, 0.0, 1.0) * travel
	var x_start: float = spring_end
	var x_end: float = ball_x - ball_r * 0.92
	if x_end < x_start + Parts.mm(2.0) * body_s:
		x_end = x_start + Parts.mm(2.0) * body_s
	var mi := spring.get_node_or_null("Coil") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Coil"
		mi.material_override = Parts.mat("tc_spring", Color(0.78, 0.72, 0.35), 0.92, 0.28)
		mi.set_meta("xray_role", "internal")
		spring.add_child(mi)
	var IsoCyl = preload("res://scripts/view3d/iso_cylinder.gd")
	mi.mesh = IsoCyl._build_helix_spring_mesh(
		x_start, x_end, Parts.mm(2.5) * body_s, Parts.mm(0.35) * body_s, 7
	)
