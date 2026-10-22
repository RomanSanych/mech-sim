class_name IsoThrottle
extends RefCounted
## 3D дроссель: CSG → запечённый Mesh.
## Корпус: крест боксов + цилиндры вдоль Z (скругления на виде сбоку, XY).
## Канал: сквозной CSG-туннель + пробка с шейкой. Винт — faceted mesh, не CSG.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var fixed: bool = str(el.accessory_class) == "throttle_fixed"
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_l: float = Parts.mm(30.0) * body_s
	var body_h: float = Parts.mm(22.0) * body_s
	var body_d: float = Parts.mm(18.0) * body_s
	var fillet_r: float = Parts.mm(3.0) * body_s
	var black := Parts.black()
	var fit_total: float = Parts.mm(27.0) * fit_scale
	# Глубже в корпус — хвостовик штуцера входит в канал, без зазора.
	var embed: float = fit_total * 0.55
	_build_body_csg(parent, fixed, body_l, body_h, body_d, fillet_r, embed, black, body_s)
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
	if not fixed:
		_build_brass_screw(parent, body_h, body_s)
		apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(18.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("throttle_fixed", fixed)
	parent.set_meta("accessory_throttle", true)
	parent.set_meta("body_s", body_s)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(12.0) * body_s, -body_h * 0.5, -body_d * 0.5),
		Vector3(body_l + Parts.mm(24.0) * body_s, body_h, body_d)
	))
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null or bool(root.get_meta("throttle_fixed", false)):
		return
	var open: float = clampf(float(el.opening), 0.0, 1.0)
	var body_s: float = float(root.get_meta("body_s", 1.0))
	var travel: float = Parts.mm(5.0) * body_s
	var screw: Node3D = root.get_node_or_null("ThrottleScrew") as Node3D
	if screw == null:
		return
	var y0: float = float(screw.get_meta("y0", screw.position.y))
	screw.set_meta("y0", y0)
	screw.position.y = y0 - (1.0 - open) * travel
	# Правая резьба: закрытие (opening↓) — по часовой сверху на шляпку (−Y в Godot).
	screw.rotation_degrees = Vector3(0.0, -(1.0 - open) * 900.0, 0.0)


static func pick_screw(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	if root == null or bool(root.get_meta("throttle_fixed", false)):
		return false
	var screw: Node3D = root.get_node_or_null("ThrottleScrew") as Node3D
	if screw == null:
		return false
	var center: Vector3 = screw.global_position
	var radius: float = Parts.mm(7.0)
	var w: Vector3 = origin - center
	var b: float = dir.dot(w)
	var c: float = w.dot(w) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		var local: Vector3 = root.to_local(origin + dir * origin.distance_to(center))
		var tip: Vector3 = root.to_local(center)
		return absf(local.x - tip.x) < Parts.mm(8.0) and absf(local.z - tip.z) < Parts.mm(8.0) \
				and local.y > tip.y - Parts.mm(4.0) and local.y < tip.y + Parts.mm(14.0)
	var t: float = -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t >= 0.0 and t < 2.5


## Фаски на виде сбоку (XY): крест боксов + цилиндры вдоль Z.
## Канал — сквозной туннель + пробка с шейкой (доходит до штуцеров).
static func _build_body_csg(
	parent: Node, fixed: bool, body_l: float, body_h: float, body_d: float,
	fillet_r: float, embed: float, mat: Material, body_s: float = 1.0
) -> void:
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var r: float = fillet_r
	var hl: float = body_l * 0.5
	var hh: float = body_h * 0.5
	# Крест: полная высота уже по X, полная длина уже по Y → углы под цилиндры Z.
	comb.add_child(CsgBake.box(Vector3(body_l - 2.0 * r, body_h, body_d), Vector3.ZERO))
	comb.add_child(CsgBake.box(Vector3(body_l, body_h - 2.0 * r, body_d), Vector3.ZERO))
	var corners: Array = [
		Vector3(-(hl - r), -(hh - r), 0.0),
		Vector3(hl - r, -(hh - r), 0.0),
		Vector3(-(hl - r), hh - r, 0.0),
		Vector3(hl - r, hh - r, 0.0),
	]
	for cpos in corners:
		comb.add_child(CsgBake.cyl(r, body_d, cpos as Vector3, "z", CSGShape3D.OPERATION_UNION, 12))
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var UNION := CSGShape3D.OPERATION_UNION
	var r_wide: float = Parts.mm(3.0) * body_s
	var tunnel_len: float = body_l + embed * 2.0 + Parts.mm(6.0) * body_s
	# Канал круглый (цилиндр вдоль X), не квадратный бокс.
	if fixed:
		var r_neck: float = Parts.mm(0.95) * body_s
		var gap: float = Parts.mm(3.5) * body_s
		comb.add_child(CsgBake.cyl(r_wide, tunnel_len, Vector3.ZERO, "x", SUB, 20))
		comb.add_child(CsgBake.cyl(r_wide + Parts.mm(0.25) * body_s, gap, Vector3.ZERO, "x", UNION, 20))
		comb.add_child(CsgBake.cyl(r_neck, gap + Parts.mm(1.0) * body_s, Vector3.ZERO, "x", SUB, 16))
	else:
		var r_seat: float = Parts.mm(2.8) * body_s
		var seat_gap: float = Parts.mm(5.0) * body_s
		comb.add_child(CsgBake.cyl(r_wide, tunnel_len, Vector3.ZERO, "x", SUB, 20))
		comb.add_child(CsgBake.cyl(r_wide + Parts.mm(0.25) * body_s, seat_gap, Vector3.ZERO, "x", UNION, 20))
		comb.add_child(CsgBake.cyl(r_seat, seat_gap, Vector3.ZERO, "x", SUB, 16))
		comb.add_child(CsgBake.cyl(
			Parts.mm(3.4) * body_s, Parts.mm(16.0) * body_s, Vector3(0.0, Parts.mm(2.0) * body_s, 0.0), "y", SUB, 18
		))
	CsgBake.attach(parent, comb, mat, "window")


## Латунный винт: круглая шляпка с углублением под прямой шлиц; стержень Ø = канал.
static func _screw_brass() -> StandardMaterial3D:
	# Не Parts.brass() (0.94/0.26) — на CSG-шляпке даёт «залитый» хром.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.55, 0.24)
	m.metallic = 0.68
	m.roughness = 0.48
	return m


static func _build_brass_screw(parent: Node, body_h: float, body_s: float = 1.0) -> void:
	var brass: StandardMaterial3D = _screw_brass()
	var base_y: float = body_h * 0.5
	var head_r: float = Parts.mm(5.5) * body_s
	var head_h: float = Parts.mm(5.0) * body_s
	# Радиус вертикального канала в корпусе (CSG SUB по Y).
	var shaft_r: float = Parts.mm(3.4) * body_s
	var nut_h: float = Parts.mm(2.2) * body_s
	var nut_y: float = base_y + Parts.mm(1.2) * body_s
	Parts.cyl(parent, Parts.mm(6.5) * body_s, nut_h, Vector3(0.0, nut_y, 0.0), "y", brass, 16, "control")
	var nut_top: float = nut_y + nut_h * 0.5
	var neck_h: float = Parts.mm(15.0) * body_s
	var screw := Node3D.new()
	screw.name = "ThrottleScrew"
	screw.position = Vector3(0.0, nut_top + neck_h + Parts.mm(0.5) * body_s, 0.0)
	screw.set_meta("y0", screw.position.y)
	screw.set_meta("throttle_screw", true)
	parent.add_child(screw)
	# Шляпка CSG: цилиндр минус бокс → настоящее углубление шлица.
	var head_csg := CSGCombiner3D.new()
	head_csg.name = "HeadCSG"
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	head_csg.add_child(CsgBake.cyl(head_r, head_h, Vector3(0.0, head_h * 0.5, 0.0), "y", CSGShape3D.OPERATION_UNION, 24))
	# Шлиц длиннее диаметра шляпки — прорезает насквозь.
	head_csg.add_child(CsgBake.box(
		Vector3(head_r * 2.0 + Parts.mm(1.5) * body_s, Parts.mm(2.6) * body_s, Parts.mm(1.25) * body_s),
		Vector3(0.0, head_h - Parts.mm(0.35) * body_s, 0.0),
		SUB
	))
	CsgBake.attach(screw, head_csg, brass, "control")
	# Стержень: в закрытом чуть ниже оси канала (не чрезмерно).
	var tip_y: float = -screw.position.y + Parts.mm(0.5) * body_s
	var shaft_top: float = 0.0
	var shaft_bot: float = tip_y
	var shaft_h: float = maxf(shaft_top - shaft_bot, Parts.mm(1.0) * body_s)
	var shaft_mid: float = 0.5 * (shaft_top + shaft_bot)
	Parts.cyl(screw, shaft_r, shaft_h, Vector3(0.0, shaft_mid, 0.0), "y", brass, 16, "control")
