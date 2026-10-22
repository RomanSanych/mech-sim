class_name IsoRotaryRack
extends RefCounted
## 3D поворотный ПЦ: корпус CSG (короб + канал + воздуховоды-вычитания).
## Рейка сплошная от поршня, 8 зубьев. Вал — один цилиндр сквозь шестерню. θ = s/r.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const RotaryCat = preload("res://scripts/domain/rotary_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")

const PRESSURE_ANGLE := 20.0
const RACK_TEETH := 8
const PINION_TEETH := 16

static var _mats := {}


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var bore_m: float = float(el.bore_mm) * 0.001
	var r_pin: float = RotaryCat.pinion_radius_m(float(el.bore_mm))
	var th_max: float = deg_to_rad(float(el.angle_max_deg))
	var stroke: float = r_pin * th_max

	var z_teeth: int = PINION_TEETH
	var module: float = (2.0 * r_pin) / float(z_teeth)
	var addendum: float = module * 0.9
	var dedendum: float = module * 1.1
	var pitch: float = PI * module
	var clear: float = module * 0.14

	var pinion_tip: float = r_pin + addendum
	var body_inner: float = pinion_tip + clear
	var body_z: float = module * 2.2
	var rack_outer: float = body_inner + body_z
	var bore_r: float = maxf(bore_m * 0.5, rack_outer * 1.03)
	var pist_r: float = bore_r * 0.99
	var pist_t: float = maxf(bore_m * 0.36, 0.011)
	# Толще заготовка шестерни — торец ступицы читается сплошным диском.
	var face_w: float = clampf(module * 7.0, r_pin * 0.9, bore_r * 0.95)
	var body_y: float = maxf(face_w * 1.1, module * 4.0)
	var tooth_h: float = body_inner - (r_pin - addendum - clear)

	var rack_len: float = float(RACK_TEETH) * pitch
	var gear_gap: float = r_pin + addendum + clear + pist_t * 0.5
	var tip_gap: float = 0.5 * (rack_len + pist_t) + clear
	var gap0: float = maxf(gear_gap, tip_gap)

	var wall: float = maxf(bore_r * 0.48, 0.0085)
	var box_h: float = bore_r * 2.0 + wall * 2.3
	var box_d: float = maxf(bore_r * 2.0 + wall * 2.3, rack_outer * 2.0 + wall * 1.2)
	var end_cap: float = maxf(bore_r * 0.28, pist_t * 0.85)
	var half_len: float = gap0 + stroke + pist_t * 0.5 + end_cap
	var box_l: float = half_len * 2.0
	var fillet_r: float = clampf(minf(box_h, box_d) * 0.12, Parts.mm(2.5), Parts.mm(5.5))

	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 8.0 if float(el.bore_mm) >= 40.0 else 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55

	var mat_alum: StandardMaterial3D = _m("rr9_alum", Color(0.74, 0.76, 0.78), 0.58, 0.40)
	var mat_shell: StandardMaterial3D = _m("rr9_shell", Color(0.78, 0.80, 0.82), 0.42, 0.48)
	var mat_end: StandardMaterial3D = _m("rr9_end", Color(0.58, 0.60, 0.62), 0.5, 0.50)
	var mat_seal: StandardMaterial3D = _m("rr9_seal", Color(0.08, 0.08, 0.09), 0.0, 0.9)

	var shaft_r: float = maxf(r_pin * 0.42, 0.004) * 1.3
	var y_top_face: float = box_h * 0.5
	var y_bot_face: float = -box_h * 0.5
	var old_top: float = maxf(box_h * 0.42, face_w * 0.55 + 0.04)
	var old_protrusion: float = maxf(old_top - y_top_face, Parts.mm(8.0))
	var y_shaft_bot: float = y_bot_face
	var y_shaft_top: float = y_top_face + old_protrusion * 1.5

	# Корпус + канал + воздуховоды + отверстия под вал; фитинги на устьях.
	var ports: Dictionary = _build_body_csg(
		parent, box_l, box_h, box_d, fillet_r, bore_r, wall,
		half_len, end_cap, gap0, stroke, pist_t, fit_scale, shaft_r, mat_shell
	)
	info["ports"]["a"] = ports["a"]
	info["ports"]["b"] = ports["b"]
	var dir_a: Vector3 = ports["dir_a"] as Vector3
	var dir_b: Vector3 = ports["dir_b"] as Vector3
	info["dirs"]["a"] = dir_a
	info["dirs"]["b"] = dir_b

	_box(parent, Vector3(end_cap * 0.9, box_h * 0.92, box_d * 0.92), Vector3(-half_len, 0.0, 0.0), mat_end, "shell")
	_box(parent, Vector3(end_cap * 0.9, box_h * 0.92, box_d * 0.92), Vector3(half_len, 0.0, 0.0), mat_end, "shell")

	var internals := Node3D.new()
	internals.name = "Internals"
	parent.add_child(internals)

	var gear_root := Node3D.new()
	gear_root.name = "Gear"
	internals.add_child(gear_root)
	_add_pinion(gear_root, r_pin, module, addendum, dedendum, z_teeth, face_w, shaft_r, mat_alum)
	_add_output_shaft(gear_root, shaft_r, y_shaft_bot, y_shaft_top, mat_alum)

	# По 2 O-ring вверху и внизу корпуса, охватывают вал (в стенке, не крутятся с шестернёй).
	var or_tube: float = clampf(shaft_r * 0.22, Parts.mm(0.7), Parts.mm(1.4))
	var wall_pad: float = wall * 0.55
	Parts.oring(parent, shaft_r * 1.01, or_tube, Vector3(0.0, y_top_face - wall_pad * 0.35, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.01, or_tube, Vector3(0.0, y_top_face - wall_pad * 0.85, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.01, or_tube, Vector3(0.0, y_bot_face + wall_pad * 0.35, 0.0), "y", mat_seal)
	Parts.oring(parent, shaft_r * 1.01, or_tube, Vector3(0.0, y_bot_face + wall_pad * 0.85, 0.0), "y", mat_seal)

	var rack_center: float = pist_t * 0.5 + rack_len * 0.5

	var left := Node3D.new()
	left.name = "PistonL"
	internals.add_child(left)
	_cyl(left, pist_r, pist_t, Vector3.ZERO, "x", mat_alum, 24, "internal")
	_cyl(left, pist_r * 1.015, pist_t * 0.14, Vector3(pist_t * 0.28, 0.0, 0.0), "x", mat_seal, 18, "internal")
	_cyl(left, pist_r * 1.015, pist_t * 0.14, Vector3(-pist_t * 0.28, 0.0, 0.0), "x", mat_seal, 18, "internal")
	var rack_l := Node3D.new()
	rack_l.name = "RackL"
	left.add_child(rack_l)
	rack_l.position = Vector3(rack_center, 0.0, 0.0)
	_add_rack(rack_l, rack_len, module, face_w, body_inner, body_z, body_y, tooth_h, -1.0, mat_alum)

	var right := Node3D.new()
	right.name = "PistonR"
	internals.add_child(right)
	_cyl(right, pist_r, pist_t, Vector3.ZERO, "x", mat_alum, 24, "internal")
	_cyl(right, pist_r * 1.015, pist_t * 0.14, Vector3(pist_t * 0.28, 0.0, 0.0), "x", mat_seal, 18, "internal")
	_cyl(right, pist_r * 1.015, pist_t * 0.14, Vector3(-pist_t * 0.28, 0.0, 0.0), "x", mat_seal, 18, "internal")
	var rack_r := Node3D.new()
	rack_r.name = "RackR"
	right.add_child(rack_r)
	rack_r.position = Vector3(-rack_center, 0.0, 0.0)
	_add_rack(rack_r, rack_len, module, face_w, body_inner, body_z, body_y, tooth_h, 1.0, mat_alum)

	parent.set_meta("rotary_gap0", gap0)
	parent.set_meta("rotary_r", r_pin)
	parent.set_meta("xray_role", "window")
	apply_state(parent, el)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, y_shaft_top + 0.02, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	return info


static func apply_state(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var gap0: float = float(root.get_meta("rotary_gap0", 0.02))
	var r_pin: float = float(root.get_meta("rotary_r", 0.01))
	var th: float = float(el.angle)
	var travel: float = r_pin * th
	var left: Node3D = root.get_node_or_null("Internals/PistonL") as Node3D
	var right: Node3D = root.get_node_or_null("Internals/PistonR") as Node3D
	var gear: Node3D = root.get_node_or_null("Internals/Gear") as Node3D
	if left != null:
		left.position.x = -(gap0 + travel)
	if right != null:
		right.position.x = gap0 + travel
	if gear != null:
		gear.rotation.y = -th


static func apply_xray(root: Node3D, on: bool) -> void:
	var Iso = preload("res://scripts/view3d/iso_cylinder.gd")
	Iso.apply_xray(root, on, false)


## CSG: скруглённый короб − канал поршней − воздуховоды − отверстия вала; фитинги.
static func _build_body_csg(
	parent: Node, box_l: float, box_h: float, box_d: float, fillet_r: float,
	bore_r: float, wall: float, half_len: float, end_cap: float,
	gap0: float, stroke: float, pist_t: float, fit_scale: float, shaft_r: float, mat: Material
) -> Dictionary:
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var UNION := CSGShape3D.OPERATION_UNION
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"

	var r: float = fillet_r
	var hh: float = box_h * 0.5
	var hd: float = box_d * 0.5
	comb.add_child(CsgBake.box(Vector3(box_l, box_h - 2.0 * r, box_d - 2.0 * r), Vector3.ZERO, UNION))
	comb.add_child(CsgBake.box(Vector3(box_l, box_h - 2.0 * r, box_d), Vector3.ZERO, UNION))
	comb.add_child(CsgBake.box(Vector3(box_l, box_h, box_d - 2.0 * r), Vector3.ZERO, UNION))
	var corners: Array = [
		Vector3(0.0, -(hh - r), -(hd - r)),
		Vector3(0.0, hh - r, -(hd - r)),
		Vector3(0.0, -(hh - r), hd - r),
		Vector3(0.0, hh - r, hd - r),
	]
	for cpos in corners:
		comb.add_child(CsgBake.cyl(r, box_l, cpos as Vector3, "x", UNION, 12))

	# Главный круглый канал под поршни.
	comb.add_child(CsgBake.cyl(bore_r * 1.02, box_l + Parts.mm(2.0), Vector3.ZERO, "x", SUB, 28))
	# Сквозные отверстия под вал в верхней и нижней стенке.
	var shaft_clear: float = shaft_r * 1.08
	comb.add_child(CsgBake.cyl(shaft_clear, box_h + Parts.mm(4.0), Vector3.ZERO, "y", SUB, 20))

	# Оба фитинга на передней грани (+Z): a — короткий в центр; b — длинная галерея к наружным.
	var chan_r: float = clampf(bore_r * 0.15, Parts.mm(1.5), Parts.mm(2.8))
	var z_face: float = hd
	var z_mouth: float = z_face + chan_r * 0.25
	var z_gal: float = bore_r * 0.45

	var x_outer: float = 0.5 * ((gap0 + stroke + pist_t * 0.5) + (half_len - end_cap))
	x_outer = clampf(x_outer, gap0 + stroke + pist_t * 0.55, half_len - end_cap - chan_r * 2.5)

	# --- a: ниже рейки → короткий −Z в среднюю полость ---
	var y_a: float = -bore_r * 0.48
	var z_a_end: float = bore_r * 0.25
	_csg_chan_z(comb, chan_r, 0.0, y_a, z_mouth, z_a_end, SUB)

	# --- b: выше a, заметно ниже скругления/потолка; −Z → ±X → −Y ---
	var x_b_fit: float = x_outer * 0.35
	# Галерея чуть над каналом поршней — не на радиусе корпуса.
	var y_b: float = clampf(
		bore_r + chan_r * 1.35, bore_r + chan_r * 1.15, hh - r - wall * 0.85
	)
	var y_b_into: float = bore_r * 0.30
	_csg_chan_z(comb, chan_r, x_b_fit, y_b, z_mouth, z_gal, SUB)
	_csg_junction(comb, chan_r * 1.12, Vector3(x_b_fit, y_b, z_gal), SUB)
	_csg_chan_x(comb, chan_r, x_b_fit, -x_outer, y_b, z_gal, SUB)
	_csg_chan_x(comb, chan_r, x_b_fit, x_outer, y_b, z_gal, SUB)
	_csg_junction(comb, chan_r * 1.08, Vector3(-x_outer, y_b, z_gal), SUB)
	_csg_junction(comb, chan_r * 1.08, Vector3(x_outer, y_b, z_gal), SUB)
	_csg_chan_y(comb, chan_r, -x_outer, y_b, z_gal, y_b_into, SUB)
	_csg_chan_y(comb, chan_r, x_outer, y_b, z_gal, y_b_into, SUB)

	CsgBake.attach(parent, comb, mat, "window")

	var tip_a: Vector3 = Parts.add_fitting(parent, Vector3(0.0, y_a, z_face), "z", fit_scale, true)
	var tip_b: Vector3 = Parts.add_fitting(parent, Vector3(x_b_fit, y_b, z_face), "z", fit_scale * 0.95, true)
	return {"a": tip_a, "b": tip_b, "dir_a": Vector3.BACK, "dir_b": Vector3.BACK}


static func _csg_chan_z(
	comb: CSGCombiner3D, rad: float, x: float, y: float, z_from: float, z_to: float,
	op: CSGShape3D.Operation
) -> void:
	var lo: float = minf(z_from, z_to)
	var hi: float = maxf(z_from, z_to)
	var h: float = hi - lo + rad * 0.4
	comb.add_child(CsgBake.cyl(rad, h, Vector3(x, y, 0.5 * (lo + hi)), "z", op, 12))


static func _csg_chan_x(
	comb: CSGCombiner3D, rad: float, x_from: float, x_to: float, y: float, z: float,
	op: CSGShape3D.Operation
) -> void:
	var lo: float = minf(x_from, x_to)
	var hi: float = maxf(x_from, x_to)
	var h: float = hi - lo + rad * 0.4
	comb.add_child(CsgBake.cyl(rad, h, Vector3(0.5 * (lo + hi), y, z), "x", op, 12))


static func _csg_chan_y(
	comb: CSGCombiner3D, rad: float, x: float, y_from: float, z: float, y_to: float,
	op: CSGShape3D.Operation
) -> void:
	var lo: float = minf(y_from, y_to)
	var hi: float = maxf(y_from, y_to)
	var h: float = hi - lo + rad * 0.5
	comb.add_child(CsgBake.cyl(rad, h, Vector3(x, 0.5 * (lo + hi), z), "y", op, 12))


static func _csg_junction(
	comb: CSGCombiner3D, rad: float, center: Vector3, op: CSGShape3D.Operation
) -> void:
	var s := CSGSphere3D.new()
	s.radius = rad
	s.radial_segments = 12
	s.rings = 8
	s.position = center
	s.operation = op
	comb.add_child(s)


## Вал: снизу до грани корпуса, сверху удлинён; CSG — шестигранник, резьба + шлиц на торце.
static func _add_output_shaft(
	parent: Node, shaft_r: float, y_bot: float, y_top: float, mat: Material
) -> void:
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var UNION := CSGShape3D.OPERATION_UNION
	var shaft_h: float = y_top - y_bot
	var mid_y: float = 0.5 * (y_bot + y_top)
	var comb := CSGCombiner3D.new()
	comb.name = "ShaftCSG"
	comb.add_child(CsgBake.cyl(shaft_r, shaft_h, Vector3(0.0, mid_y, 0.0), "y", UNION, 28))

	# Снизу: шестигранное углубление под ключ (3 бокса → шестигранник).
	var hex_depth: float = clampf(shaft_r * 1.1, Parts.mm(3.0), Parts.mm(6.0))
	var hex_f2f: float = shaft_r * 1.15
	var hex_mid_y: float = y_bot + hex_depth * 0.5
	var hex_group := CSGCombiner3D.new()
	hex_group.operation = SUB
	for i in 3:
		var hb := CsgBake.box(
			Vector3(hex_f2f, hex_depth + Parts.mm(0.2), hex_f2f / sqrt(3.0)),
			Vector3(0.0, hex_mid_y, 0.0),
			UNION
		)
		hb.rotation_degrees = Vector3(0.0, 60.0 * float(i), 0.0)
		hex_group.add_child(hb)
	comb.add_child(hex_group)

	# Сверху: круглое отверстие под резьбу.
	var tap_r: float = shaft_r * 0.38
	var tap_depth: float = clampf(shaft_r * 1.6, Parts.mm(4.0), Parts.mm(8.0))
	var tap_mid: float = y_top - tap_depth * 0.5
	comb.add_child(CsgBake.cyl(tap_r, tap_depth + Parts.mm(0.3), Vector3(0.0, tap_mid, 0.0), "y", SUB, 16))

	# Сверху на торце: шлиц через отверстие (как у винта).
	var slot_len: float = shaft_r * 2.15
	var slot_thick: float = clampf(shaft_r * 0.28, Parts.mm(0.9), Parts.mm(1.8))
	var slot_depth: float = clampf(tap_depth * 0.55, Parts.mm(2.0), Parts.mm(4.5))
	comb.add_child(CsgBake.box(
		Vector3(slot_len, slot_depth, slot_thick),
		Vector3(0.0, y_top - slot_depth * 0.45, 0.0),
		SUB
	))

	CsgBake.attach(parent, comb, mat, "internal")
	comb.name = "Shaft"


static func _add_pinion(
	parent: Node, r_pitch: float, module: float, addendum: float, dedendum: float,
	z_teeth: int, face_w: float, shaft_r: float, mat: Material
) -> void:
	var r_root: float = maxf(r_pitch - dedendum, r_pitch * 0.5)
	var r_tip: float = r_pitch + addendum
	# Диск ступицы до корня зуба; вал толстый и проходит насквозь — без полости.
	var hub_r: float = r_root
	var hub := _cyl(parent, hub_r, face_w, Vector3.ZERO, "y", mat, 32, "internal")
	hub.name = "Hub"
	var alpha: float = deg_to_rad(PRESSURE_ANGLE)
	var pitch_half: float = (PI * module) * 0.22
	for i in z_teeth:
		var ang: float = TAU * float(i) / float(z_teeth)
		var mi := MeshInstance3D.new()
		mi.mesh = _make_tooth_mesh(hub_r * 0.98, r_tip, r_pitch, pitch_half, alpha, face_w)
		mi.material_override = mat
		mi.rotation.y = -ang
		mi.set_meta("xray_role", "internal")
		parent.add_child(mi)


static func _make_tooth_mesh(
	r_root: float, r_tip: float, r_pitch: float, pitch_half: float, alpha: float, face_w: float
) -> ArrayMesh:
	var tip_half: float = maxf(pitch_half - tan(alpha) * (r_tip - r_pitch), pitch_half * 0.3)
	var root_half: float = pitch_half + tan(alpha) * maxf(r_pitch - r_root, 0.0) * 0.85
	var hy: float = face_w * 0.5
	var p := PackedVector3Array([
		Vector3(r_root, -hy, -root_half),
		Vector3(r_root, -hy, root_half),
		Vector3(r_tip, -hy, tip_half),
		Vector3(r_tip, -hy, -tip_half),
		Vector3(r_root, hy, -root_half),
		Vector3(r_root, hy, root_half),
		Vector3(r_tip, hy, tip_half),
		Vector3(r_tip, hy, -tip_half),
	])
	return _mesh_from_box_corners(p)


static func _add_rack(
	rack: Node3D, rack_len: float, module: float, face_w: float,
	body_inner: float, body_z: float, body_y: float,
	tooth_h: float, sign_toward_pinion: float, mat: Material
) -> void:
	var eps: float = module * 0.06
	var body_center_z: float
	var z_root: float
	if sign_toward_pinion < 0.0:
		body_center_z = (body_inner + eps) + body_z * 0.5
		z_root = body_inner
	else:
		body_center_z = -(body_inner + eps) - body_z * 0.5
		z_root = -body_inner
	_box(rack, Vector3(rack_len, body_y, body_z), Vector3(0.0, 0.0, body_center_z), mat, "internal")
	_add_rack_teeth(rack, rack_len, module, face_w, z_root, tooth_h, sign_toward_pinion, mat)


static func _add_rack_teeth(
	rack: Node3D, rack_len: float, module: float, face_w: float,
	z_root: float, tooth_h: float, sign_toward_pinion: float, mat: Material
) -> void:
	var pitch: float = PI * module
	var alpha: float = deg_to_rad(PRESSURE_ANGLE)
	var half_space: float = pitch * 0.5
	var root_w: float = half_space * 0.85
	var tip_w: float = maxf(root_w - 2.0 * tan(alpha) * tooth_h, root_w * 0.38)
	var x0: float = -rack_len * 0.5 + pitch * 0.5
	for i in RACK_TEETH:
		var mi := MeshInstance3D.new()
		mi.mesh = _make_rack_tooth_mesh(root_w, tip_w, tooth_h, face_w * 0.88, sign_toward_pinion)
		mi.position = Vector3(x0 + float(i) * pitch, 0.0, z_root)
		mi.material_override = mat
		mi.set_meta("xray_role", "internal")
		rack.add_child(mi)


static func _make_rack_tooth_mesh(
	root_w: float, tip_w: float, height: float, face_w: float, sign_toward_pinion: float
) -> ArrayMesh:
	var hy: float = face_w * 0.5
	var z0: float = 0.0
	var z1: float = sign_toward_pinion * height
	var rw: float = root_w * 0.5
	var tw: float = tip_w * 0.5
	var p := PackedVector3Array([
		Vector3(-rw, -hy, z0),
		Vector3(rw, -hy, z0),
		Vector3(tw, -hy, z1),
		Vector3(-tw, -hy, z1),
		Vector3(-rw, hy, z0),
		Vector3(rw, hy, z0),
		Vector3(tw, hy, z1),
		Vector3(-tw, hy, z1),
	])
	return _mesh_from_box_corners(p)


static func _mesh_from_box_corners(p: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array = [
		[0, 1, 2, 3], [4, 7, 6, 5],
		[0, 3, 7, 4], [1, 5, 6, 2],
		[3, 2, 6, 7], [0, 4, 5, 1],
	]
	for f in faces:
		var a: Vector3 = p[int(f[0])]
		var b: Vector3 = p[int(f[1])]
		var c: Vector3 = p[int(f[2])]
		var d: Vector3 = p[int(f[3])]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if n.length_squared() < 1.0e-10:
			continue
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)
	return st.commit()


static func _m(key: String, color: Color, metallic: float, rough: float, alpha: float = 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.metallic = metallic
	mat.roughness = rough
	if alpha < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = mat
	return mat


static func _box(parent: Node, size: Vector3, center: Vector3, mat: Material, role: String = "shell") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	parent.add_child(mi)
	return mi


static func _cyl(
	parent: Node, radius: float, length: float, center: Vector3, axis: String,
	mat: Material, segs: int = 24, role: String = "shell"
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(length, 0.0004)
	mesh.radial_segments = segs
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	if axis == "x":
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif axis == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(mi)
	return mi
