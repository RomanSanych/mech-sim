class_name IsoRelief
extends RefCounted
## 3D предохранительный клапан (Camozzi VMR / spring relief):
## 1 = вход (−Y), 2 = сброс (−X, штуцер или глушитель).
## opening 0 = тарелка на седле; 1 = открыт (тарелка жмёт пружину снизу).
## set_pressure_bar — уставка (винт сверху сжимает пружину сверху);
## pressed — боковой рычаг поднимает воротник на штоке → тарелку.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")

const SET_MIN_BAR := 0.5
const SET_MAX_BAR := 10.0
const SCREW_TURNS := 3.5
const COIL_COUNT := 7


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 8.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_r: float = Parts.mm(13.0) * body_s
	var body_h: float = Parts.mm(22.0) * body_s
	var spring_r: float = Parts.mm(9.0) * body_s
	var spring_h: float = Parts.mm(18.0) * body_s
	var bore_r: float = Parts.mm(3.6) * body_s
	var seat_or: float = Parts.mm(2.8) * body_s
	var disc_r: float = Parts.mm(4.8) * body_s
	var chamber_r: float = Parts.mm(6.2) * body_s
	_build_body(parent, body_r, body_h, spring_r, spring_h, bore_r, chamber_r, seat_or, body_s)
	var tip_1: Vector3 = Parts.add_fitting(
		parent, Vector3(0.0, -body_h * 0.5 - Parts.mm(1.0) * body_s, 0.0), "-y", fit_scale, true
	)
	var out_origin := Vector3(-body_r * 0.55, -Parts.mm(2.0) * body_s, 0.0)
	var tip_2: Vector3
	var muffler: bool = str(el.port_3) == "muffler"
	if muffler:
		tip_2 = Parts.add_silencer(parent, out_origin, "-x", fit_scale * 1.05)
	else:
		tip_2 = Parts.add_fitting(parent, out_origin, "-x", fit_scale, true)
	info["ports"]["1"] = tip_1
	info["dirs"]["1"] = Vector3.DOWN
	if not muffler:
		info["ports"]["2"] = tip_2
		info["dirs"]["2"] = Vector3.LEFT
	parent.set_meta("relief_local", tip_2 if muffler else out_origin)
	parent.set_meta("relief_dir", Vector3.LEFT)
	_build_internals(parent, body_r, body_h, spring_h, disc_r, seat_or, spring_r, body_s)
	parent.set_meta("body_s", body_s)
	parent.set_meta("y_closed", -Parts.mm(1.4) * body_s)
	parent.set_meta("y_open", Parts.mm(6.5) * body_s)
	# Низ пружины = верх тарелки (тарелка жмёт витки снизу).
	parent.set_meta("spring_top0", body_h * 0.5 + spring_h * 0.72)
	parent.set_meta("spring_bot0", -Parts.mm(1.4) * body_s + Parts.mm(1.2) * body_s)
	parent.set_meta("accessory_relief", true)
	parent.set_meta("xray_role", "window")
	apply_state(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(body_r + Parts.mm(10.0) * body_s, Parts.mm(6.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	return info


static func apply_state(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var body_s: float = float(root.get_meta("body_s", 1.0))
	var open: float = clampf(float(el.opening), 0.0, 1.0)
	if bool(el.pressed):
		open = 1.0
	var y0: float = float(root.get_meta("y_closed", -0.0015))
	var y1: float = float(root.get_meta("y_open", 0.0065))
	var lift: float = lerpf(y0, y1, open) - y0
	var set_bar: float = clampf(float(el.set_pressure_bar), SET_MIN_BAR, SET_MAX_BAR)
	var set_t: float = (set_bar - SET_MIN_BAR) / (SET_MAX_BAR - SET_MIN_BAR)
	# Тарелка/шток/воротник — lift. Винт — тот же lift минус уставка (связан со штоком).
	var screw_travel: float = set_t * Parts.mm(2.4) * body_s
	var disc: Node3D = root.get_node_or_null("ReliefDisc") as Node3D
	if disc != null:
		var dy0: float = float(disc.get_meta("y0", disc.position.y))
		disc.set_meta("y0", dy0)
		disc.position.y = dy0 + lift
	var stem: Node3D = root.get_node_or_null("ReliefStem") as Node3D
	if stem != null:
		var sy0: float = float(stem.get_meta("y0", stem.position.y))
		stem.set_meta("y0", sy0)
		stem.position.y = sy0 + lift
	var collar: Node3D = root.get_node_or_null("ReliefCollar") as Node3D
	if collar != null:
		var cy0: float = float(collar.get_meta("y0", collar.position.y))
		collar.set_meta("y0", cy0)
		collar.position.y = cy0 + lift
	var seat: Node3D = root.get_node_or_null("ReliefUpperSeat") as Node3D
	if seat != null:
		var uy0: float = float(seat.get_meta("y0", seat.position.y))
		seat.set_meta("y0", uy0)
		# Опора пружины на корпусе: только уставка (тарелка жмёт пружину снизу при lift).
		seat.position.y = uy0 - screw_travel
	var screw: Node3D = root.get_node_or_null("ReliefScrew") as Node3D
	if screw != null:
		var scy0: float = float(screw.get_meta("y0", screw.position.y))
		screw.set_meta("y0", scy0)
		screw.position.y = scy0 + lift - screw_travel
		screw.rotation_degrees = Vector3(0.0, -set_t * SCREW_TURNS * 360.0, 0.0)
	# Пружина: низ = тарелка, верх = шайба (уставка).
	var spring: Node3D = root.get_node_or_null("ReliefSpring") as Node3D
	if spring != null:
		var bot0: float = float(root.get_meta("spring_bot0", 0.0))
		var top0: float = float(root.get_meta("spring_top0", 0.01))
		var h0: float = maxf(top0 - bot0, Parts.mm(4.0) * body_s)
		var bot: float = bot0 + lift
		var top: float = top0 - screw_travel
		var h: float = maxf(top - bot, Parts.mm(2.0) * body_s)
		var squash: float = clampf(h / h0, 0.35, 1.05)
		spring.scale = Vector3(1.0, squash, 1.0)
		spring.position.y = (bot + top) * 0.5
	# Боковой рычаг: поворот вокруг оси Z у корпуса — палец поднимает воротник.
	var handle: Node3D = root.get_node_or_null("ReliefHandle") as Node3D
	if handle != null:
		# Умеренный угол: вилка поднимает воротник, рукоятка вниз — без прохода сквозь крышу.
		var ang: float = -26.0 if bool(el.pressed) else 0.0
		handle.rotation_degrees = Vector3(0.0, 0.0, ang)


static func pick_screw(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	return _pick_node(root, "ReliefScrew", origin, dir, Parts.mm(11.0))


static func pick_handle(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	# Рычаг сбоку — пик по узлу + по кончику рукоятки.
	if _pick_node(root, "ReliefHandle", origin, dir, Parts.mm(16.0)):
		return true
	var handle: Node3D = root.get_node_or_null("ReliefHandle") as Node3D
	if handle == null:
		return false
	var tip: Node3D = handle.get_node_or_null("LeverTip") as Node3D
	if tip == null:
		return false
	return _ray_near(origin, dir, tip.global_position, Parts.mm(12.0))


static func _pick_node(root: Node3D, name: String, origin: Vector3, dir: Vector3, radius: float) -> bool:
	if root == null:
		return false
	var node: Node3D = root.get_node_or_null(name) as Node3D
	if node == null:
		return false
	return _ray_near(origin, dir, node.global_position, radius)


static func _ray_near(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> bool:
	var w: Vector3 = origin - center
	var b: float = dir.dot(w)
	var c: float = w.dot(w) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		var closest: Vector3 = origin + dir * maxf(-b, 0.0)
		return closest.distance_to(center) < radius * 1.6
	var t: float = -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t >= 0.0 and t < 3.0


static func _body_mat() -> StandardMaterial3D:
	return Parts.mat("relief_body", Color(0.72, 0.74, 0.76), 0.55, 0.38)


static func _build_body(
	parent: Node,
	body_r: float,
	body_h: float,
	spring_r: float,
	spring_h: float,
	bore_r: float,
	chamber_r: float,
	seat_or: float,
	body_s: float
) -> void:
	var mat: Material = _body_mat()
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 28))
	comb.add_child(CsgBake.cyl(
		spring_r, spring_h,
		Vector3(0.0, body_h * 0.5 + spring_h * 0.45, 0.0), "y", UNION, 24
	))
	comb.add_child(CsgBake.cyl(chamber_r, Parts.mm(10.0) * body_s, Vector3(0.0, Parts.mm(1.0) * body_s, 0.0), "y", SUB, 18))
	comb.add_child(CsgBake.cyl(
		bore_r, body_h * 0.55, Vector3(0.0, -body_h * 0.28, 0.0), "y", SUB, 14
	))
	comb.add_child(CsgBake.cyl(seat_or, Parts.mm(2.2) * body_s, Vector3(0.0, -Parts.mm(3.0) * body_s, 0.0), "y", SUB, 16))
	comb.add_child(CsgBake.cyl(
		bore_r * 1.1, body_r * 1.2,
		Vector3(-body_r * 0.35, -Parts.mm(2.0) * body_s, 0.0), "x", SUB, 14
	))
	comb.add_child(CsgBake.cyl(
		spring_r * 0.78, spring_h * 0.85,
		Vector3(0.0, body_h * 0.5 + spring_h * 0.4, 0.0), "y", SUB, 18
	))
	# Паз рычага только в стенке камеры пружины (+X), выше стыка с нижним корпусом.
	var wall_in: float = spring_r * 0.78
	var slot_x: float = (wall_in + spring_r) * 0.5 + Parts.mm(0.4) * body_s
	var slot_dx: float = (spring_r - wall_in) + Parts.mm(2.2) * body_s
	var slot_y: float = body_h * 0.5 + spring_h * 0.32
	var slot_dy: float = minf(spring_h * 0.55, Parts.mm(10.0) * body_s)
	comb.add_child(CsgBake.box(
		Vector3(slot_dx, slot_dy, Parts.mm(12.0) * body_s),
		Vector3(slot_x, slot_y, 0.0),
		SUB
	))
	CsgBake.attach(parent, comb, mat, "window")
	# Седло подачи: кольцевой поясок, на который садится тарелка (видно в рентгене).
	var seat_mat: Material = Parts.mat("relief_seat", Color(0.22, 0.24, 0.28), 0.35, 0.55)
	var seat_y: float = -Parts.mm(3.2) * body_s
	Parts.cyl(
		parent, seat_or * 1.55, Parts.mm(2.8) * body_s,
		Vector3(0.0, seat_y, 0.0), "y", seat_mat, 20, "internal"
	)
	# Фаска седла (конус вверх к тарелке).
	var seat_face := MeshInstance3D.new()
	seat_face.name = "ReliefSeatFace"
	var sfm := CylinderMesh.new()
	sfm.top_radius = seat_or * 1.05
	sfm.bottom_radius = seat_or * 1.55
	sfm.height = Parts.mm(1.4) * body_s
	sfm.radial_segments = 20
	seat_face.mesh = sfm
	seat_face.position = Vector3(0.0, seat_y + Parts.mm(1.6) * body_s, 0.0)
	seat_face.material_override = Parts.mat("relief_seat_face", Color(0.32, 0.34, 0.38), 0.45, 0.5)
	seat_face.set_meta("xray_role", "internal")
	parent.add_child(seat_face)
	Parts.oring(
		parent, seat_or * 1.15, Parts.mm(0.65) * body_s,
		Vector3(0.0, seat_y + Parts.mm(2.0) * body_s, 0.0), "y",
		Parts.mat("relief_seat_oring", Color(0.12, 0.12, 0.13), 0.1, 0.7)
	)


static func _build_internals(
	parent: Node,
	body_r: float,
	body_h: float,
	spring_h: float,
	disc_r: float,
	seat_or: float,
	spring_r: float,
	body_s: float
) -> void:
	# Тарелка чуть выше фаски седла (−3.2 + 1.6 ≈ −1.6 мм).
	var y_disc: float = -Parts.mm(1.4) * body_s
	var disc := MeshInstance3D.new()
	disc.name = "ReliefDisc"
	var dm := CylinderMesh.new()
	dm.top_radius = disc_r * 0.92
	dm.bottom_radius = disc_r
	dm.height = Parts.mm(2.4) * body_s
	dm.radial_segments = 22
	disc.mesh = dm
	disc.material_override = Parts.mat("relief_disc", Color(0.82, 0.22, 0.18), 0.35, 0.55)
	disc.position = Vector3(0.0, y_disc, 0.0)
	disc.set_meta("y0", y_disc)
	disc.set_meta("xray_role", "internal")
	parent.add_child(disc)
	Parts.cyl(
		disc, seat_or * 1.2, Parts.mm(1.1) * body_s,
		Vector3(0.0, -Parts.mm(1.5) * body_s, 0.0), "y",
		Parts.mat("relief_seal", Color(0.12, 0.12, 0.13), 0.1, 0.7), 14, "internal"
	)
	# Шток: от тарелки до головки винта (общий ход при открытии).
	var screw_h: float = Parts.mm(9.0) * body_s
	var screw_y: float = body_h * 0.5 + spring_h * 1.05
	var stem_bot: float = y_disc + Parts.mm(1.2) * body_s
	var stem_top: float = screw_y - screw_h * 0.35
	var stem_len: float = maxf(stem_top - stem_bot, Parts.mm(8.0) * body_s)
	var stem_mid: float = (stem_bot + stem_top) * 0.5
	var stem := Node3D.new()
	stem.name = "ReliefStem"
	stem.position = Vector3(0.0, stem_mid, 0.0)
	stem.set_meta("y0", stem_mid)
	stem.set_meta("xray_role", "internal")
	Parts.cyl(
		stem, Parts.mm(1.3) * body_s, stem_len,
		Vector3.ZERO, "y",
		Parts.mat("relief_stem", Color(0.55, 0.57, 0.6), 0.7, 0.35), 12, "internal"
	)
	parent.add_child(stem)
	# Воротник в зоне пружины — рычаг цепляет его выше тарелки (читаемая кинематика).
	var collar_y: float = body_h * 0.5 + spring_h * 0.22
	var collar := Node3D.new()
	collar.name = "ReliefCollar"
	collar.position = Vector3(0.0, collar_y, 0.0)
	collar.set_meta("y0", collar_y)
	collar.set_meta("xray_role", "internal")
	Parts.cyl(
		collar, Parts.mm(4.6) * body_s, Parts.mm(2.6) * body_s,
		Vector3.ZERO, "y",
		Parts.mat("relief_collar", Color(0.92, 0.55, 0.12), 0.45, 0.45), 16, "internal"
	)
	parent.add_child(collar)
	# Пружина: витки между тарелкой и опорой винта (позиция/масштаб в apply_state).
	var spring_bot0: float = y_disc + Parts.mm(1.2) * body_s
	var spring_top0: float = body_h * 0.5 + spring_h * 0.72
	var spring_mid: float = (spring_bot0 + spring_top0) * 0.5
	var spring_half: float = (spring_top0 - spring_bot0) * 0.5
	var spring := Node3D.new()
	spring.name = "ReliefSpring"
	spring.position = Vector3(0.0, spring_mid, 0.0)
	spring.set_meta("xray_role", "internal")
	for i in COIL_COUNT:
		var t: float = float(i) / float(maxi(COIL_COUNT - 1, 1))
		var ly: float = -spring_half + t * spring_half * 2.0
		Parts.oring(
			spring, spring_r * 0.52, Parts.mm(0.55) * body_s,
			Vector3(0.0, ly, 0.0), "y",
			Parts.mat("relief_spring", Color(0.78, 0.78, 0.8), 0.85, 0.3)
		)
	# Нижняя шайба на тарелке — видно, что пружина опирается на неё.
	Parts.cyl(
		disc, disc_r * 0.72, Parts.mm(1.0) * body_s,
		Vector3(0.0, Parts.mm(1.5) * body_s, 0.0), "y",
		Parts.mat("relief_lower_seat", Color(0.58, 0.6, 0.64), 0.55, 0.4), 16, "internal"
	)
	parent.add_child(spring)
	# Опора пружины (шайба) + регулировочный винт сверху — вне зоны рычага.
	var upper_y: float = spring_top0 + Parts.mm(1.0) * body_s
	var upper := Node3D.new()
	upper.name = "ReliefUpperSeat"
	upper.position = Vector3(0.0, upper_y, 0.0)
	upper.set_meta("y0", upper_y)
	upper.set_meta("xray_role", "internal")
	Parts.cyl(
		upper, spring_r * 0.58, Parts.mm(1.6) * body_s,
		Vector3.ZERO, "y",
		Parts.mat("relief_washer", Color(0.5, 0.52, 0.55), 0.65, 0.4), 18, "internal"
	)
	parent.add_child(upper)
	# Головка ×2: CSG-цилиндр со шлицем-углублением сверху (не выступающий брусок).
	var screw := Node3D.new()
	screw.name = "ReliefScrew"
	screw.position = Vector3(0.0, screw_y, 0.0)
	screw.set_meta("y0", screw_y)
	screw.set_meta("xray_role", "control")
	var screw_r: float = Parts.mm(6.5) * body_s
	var slot_d: float = Parts.mm(1.8) * body_s
	var slot_w: float = Parts.mm(1.5) * body_s
	var slot_len: float = screw_r * 1.85
	var screw_csg := CSGCombiner3D.new()
	screw_csg.name = "ScrewHeadCSG"
	var S_UNION := CSGShape3D.OPERATION_UNION
	var S_SUB := CSGShape3D.OPERATION_SUBTRACTION
	screw_csg.add_child(CsgBake.cyl(screw_r, screw_h, Vector3.ZERO, "y", S_UNION, 22))
	# Шлиц: вычитание с торца (+Y), чуть глубже поверхности.
	screw_csg.add_child(CsgBake.box(
		Vector3(slot_len, slot_d * 1.15, slot_w),
		Vector3(0.0, screw_h * 0.5 - slot_d * 0.35, 0.0),
		S_SUB
	))
	CsgBake.attach(
		screw, screw_csg,
		Parts.mat("relief_screw", Color(0.42, 0.44, 0.48), 0.75, 0.35),
		"control"
	)
	# Тёмное дно шлица — читается как углубление при любом освещении.
	Parts.box(
		screw,
		Vector3(slot_len * 0.92, Parts.mm(0.35) * body_s, slot_w * 0.85),
		Vector3(0.0, screw_h * 0.5 - slot_d * 0.85, 0.0),
		Parts.mat("relief_slot", Color(0.12, 0.12, 0.14), 0.15, 0.75), "control"
	)
	for k in 8:
		var a: float = float(k) * TAU / 8.0
		Parts.box(
			screw,
			Vector3(Parts.mm(1.1) * body_s, screw_h * 0.85, Parts.mm(1.1) * body_s),
			Vector3(cos(a) * Parts.mm(5.6) * body_s, -Parts.mm(0.3) * body_s, sin(a) * Parts.mm(5.6) * body_s),
			Parts.mat("relief_knurl", Color(0.35, 0.37, 0.4), 0.6, 0.45), "control"
		)
	parent.add_child(screw)
	# Боковой рычаг подрыва: ось у корпуса (+X), палец под воротником, рукоятка наружу.
	_build_side_lever(parent, body_r, body_h, collar_y, body_s)


static func _build_side_lever(
	parent: Node, body_r: float, body_h: float, collar_y: float, body_s: float
) -> void:
	var pivot := Vector3(body_r * 0.92, collar_y - Parts.mm(1.0) * body_s, 0.0)
	var handle := Node3D.new()
	handle.name = "ReliefHandle"
	handle.position = pivot
	handle.set_meta("y0", pivot.y)
	handle.set_meta("xray_role", "control")
	var hmat: Material = Parts.mat("relief_handle", Color(0.82, 0.16, 0.14), 0.2, 0.55)
	# Вилка под воротником (низкая — при повороте не протыкает крышу камеры пружины).
	Parts.box(
		handle,
		Vector3(Parts.mm(9.0) * body_s, Parts.mm(1.6) * body_s, Parts.mm(7.0) * body_s),
		Vector3(-Parts.mm(5.5) * body_s, Parts.mm(1.6) * body_s, 0.0),
		hmat, "control"
	)
	Parts.box(
		handle,
		Vector3(Parts.mm(3.2) * body_s, Parts.mm(2.4) * body_s, Parts.mm(1.8) * body_s),
		Vector3(-Parts.mm(8.2) * body_s, Parts.mm(2.4) * body_s, Parts.mm(2.6) * body_s),
		hmat, "control"
	)
	Parts.box(
		handle,
		Vector3(Parts.mm(3.2) * body_s, Parts.mm(2.4) * body_s, Parts.mm(1.8) * body_s),
		Vector3(-Parts.mm(8.2) * body_s, Parts.mm(2.4) * body_s, -Parts.mm(2.6) * body_s),
		hmat, "control"
	)
	# Рукоятка наружу (+X).
	Parts.box(
		handle,
		Vector3(Parts.mm(16.0) * body_s, Parts.mm(2.4) * body_s, Parts.mm(4.0) * body_s),
		Vector3(Parts.mm(10.0) * body_s, 0.0, 0.0),
		hmat, "control"
	)
	var tip := Node3D.new()
	tip.name = "LeverTip"
	tip.position = Vector3(Parts.mm(18.0) * body_s, 0.0, 0.0)
	handle.add_child(tip)
	Parts.cyl(
		handle, Parts.mm(3.2) * body_s, Parts.mm(5.0) * body_s,
		Vector3(Parts.mm(18.0) * body_s, 0.0, 0.0), "z",
		Parts.mat("relief_grip", Color(0.7, 0.12, 0.1), 0.15, 0.6), 12, "control"
	)
	# Ось/ушко на корпусе (неподвижное, рядом).
	Parts.cyl(
		parent, Parts.mm(2.4) * body_s, Parts.mm(6.0) * body_s,
		pivot + Vector3(0.0, 0.0, 0.0), "z",
		Parts.mat("relief_pivot", Color(0.4, 0.42, 0.45), 0.55, 0.45), 12, "shell"
	)
	parent.add_child(handle)
