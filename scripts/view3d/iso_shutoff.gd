class_name IsoShutoff
extends RefCounted
## 3D отсечной шаровой кран (Festo QH-класс): чёрный корпус со скруглениями,
## фитинги L/R, синяя рукоятка сверху, шар с каналом (рентген).
## opening 0 = закрыт (канал ⊥ потоку), 1 = открыт (канал соосно X).

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
	var body_l: float = Parts.mm(28.0) * body_s
	var body_h: float = Parts.mm(20.0) * body_s
	var body_d: float = Parts.mm(18.0) * body_s
	var fillet_r: float = Parts.mm(3.0) * body_s
	var ball_r: float = Parts.mm(5.2) * body_s
	var bore_r: float = Parts.mm(2.4) * body_s
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.55
	_build_body_csg(parent, body_l, body_h, body_d, fillet_r, embed, ball_r, bore_r, body_s)
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
	_build_rotor(parent, body_h, ball_r, bore_r, body_s)
	apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(20.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_shutoff", true)
	parent.set_meta("body_s", body_s)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(12.0) * body_s, -body_h * 0.5, -body_d * 0.5),
		Vector3(body_l + Parts.mm(24.0) * body_s, body_h + Parts.mm(18.0) * body_s, body_d)
	))
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null:
		return
	var open: float = clampf(float(el.opening), 0.0, 1.0)
	# 0° = открыт (канал вдоль X), 90° = закрыт.
	var deg: float = (1.0 - open) * 90.0
	var rotor: Node3D = root.get_node_or_null("ShutoffRotor") as Node3D
	if rotor != null:
		rotor.rotation_degrees = Vector3(0.0, deg, 0.0)


static func pick_handle(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	if root == null:
		return false
	var handle: Node3D = root.get_node_or_null("ShutoffRotor/Handle") as Node3D
	if handle == null:
		handle = root.get_node_or_null("ShutoffRotor") as Node3D
	if handle == null:
		return false
	var center: Vector3 = handle.global_position
	var radius: float = Parts.mm(9.0)
	var w: Vector3 = origin - center
	var b: float = dir.dot(w)
	var c: float = w.dot(w) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		var local: Vector3 = root.to_local(origin + dir * origin.distance_to(center))
		var tip: Vector3 = root.to_local(center)
		return absf(local.x - tip.x) < Parts.mm(10.0) and absf(local.z - tip.z) < Parts.mm(10.0) \
				and local.y > tip.y - Parts.mm(4.0) and local.y < tip.y + Parts.mm(16.0)
	var t: float = -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t >= 0.0 and t < 2.5


static func _build_body_csg(
	parent: Node, body_l: float, body_h: float, body_d: float,
	fillet_r: float, embed: float, ball_r: float, bore_r: float, body_s: float
) -> void:
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var r: float = fillet_r
	var hl: float = body_l * 0.5
	var hh: float = body_h * 0.5
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
	var tunnel_len: float = body_l + embed * 2.0 + Parts.mm(6.0) * body_s
	comb.add_child(CsgBake.cyl(bore_r * 1.15, tunnel_len, Vector3.ZERO, "x", SUB, 20))
	# Камера шара.
	var chamber := CSGSphere3D.new()
	chamber.radius = ball_r * 1.08
	chamber.radial_segments = 18
	chamber.rings = 10
	chamber.operation = SUB
	chamber.position = Vector3.ZERO
	comb.add_child(chamber)
	# Шейка под шток рукоятки.
	comb.add_child(CsgBake.cyl(
		Parts.mm(2.6) * body_s, Parts.mm(10.0) * body_s,
		Vector3(0.0, body_h * 0.35, 0.0), "y", SUB, 14
	))
	CsgBake.attach(parent, comb, Parts.black(), "window")


static func _build_rotor(
	parent: Node, body_h: float, ball_r: float, bore_r: float, body_s: float
) -> void:
	var rotor := Node3D.new()
	rotor.name = "ShutoffRotor"
	rotor.set_meta("xray_role", "internal")
	parent.add_child(rotor)
	# Шар с каналом.
	var ball_csg := CSGCombiner3D.new()
	ball_csg.name = "BallCSG"
	var sph := CSGSphere3D.new()
	sph.radius = ball_r
	sph.radial_segments = 20
	sph.rings = 12
	sph.operation = CSGShape3D.OPERATION_UNION
	ball_csg.add_child(sph)
	ball_csg.add_child(CsgBake.cyl(
		bore_r, ball_r * 2.4, Vector3.ZERO, "x", CSGShape3D.OPERATION_SUBTRACTION, 16
	))
	CsgBake.attach(rotor, ball_csg, Parts.steel(), "internal")
	# Шток: от верха шара (не в канал) до плоскости корпуса; ручка впритык к корпусу.
	var body_top: float = body_h * 0.5
	var stem_bot: float = ball_r * 0.92
	var stem_top: float = body_top
	var stem_h: float = maxf(stem_top - stem_bot, Parts.mm(1.5) * body_s)
	var stem_mid: float = stem_bot + stem_h * 0.5
	Parts.cyl(
		rotor, Parts.mm(2.2) * body_s, stem_h,
		Vector3(0.0, stem_mid, 0.0), "y",
		Parts.mat("shutoff_stem", Color(0.55, 0.56, 0.58), 0.85, 0.3),
		14, "internal"
	)
	var handle := Node3D.new()
	handle.name = "Handle"
	# Низ рукоятки = верх корпуса (без зазора).
	handle.position = Vector3(0.0, body_top, 0.0)
	handle.set_meta("xray_role", "control")
	rotor.add_child(handle)
	var blue: StandardMaterial3D = Parts.plastic_blue()
	var knurl_h: float = Parts.mm(5.5) * body_s
	# Накатанный цилиндр: низ на y=0 (плоскость корпуса).
	Parts.cyl(
		handle, Parts.mm(5.5) * body_s, knurl_h,
		Vector3(0.0, knurl_h * 0.5, 0.0), "y", blue, 20, "control"
	)
	# Плоский флажок вдоль потока (X) в открытом положении.
	var tab_h: float = Parts.mm(2.2) * body_s
	Parts.box(
		handle,
		Vector3(Parts.mm(11.0) * body_s, tab_h, Parts.mm(4.0) * body_s),
		Vector3(0.0, knurl_h + tab_h * 0.5, 0.0),
		blue, "control"
	)
