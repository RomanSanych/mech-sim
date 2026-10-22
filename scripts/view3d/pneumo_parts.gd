class_name PneumoParts
extends RefCounted
## Примитивы строго по refs/cad/camozzi/dims.json (мм → м).


const DIMS_PATH := "res://refs/cad/camozzi/dims.json"

static var _mats := {}
static var _dims: Dictionary = {}


static func dims() -> Dictionary:
	if not _dims.is_empty():
		return _dims
	if FileAccess.file_exists(DIMS_PATH):
		var txt := FileAccess.get_file_as_string(DIMS_PATH)
		var data = JSON.parse_string(txt)
		if typeof(data) == TYPE_DICTIONARY:
			_dims = data.get("parts", {})
	return _dims


static func mm(v: float) -> float:
	return v * 0.001


static func mat(key: String, color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	_mats[key] = m
	return m


static func alum() -> StandardMaterial3D:
	return mat("pp_alum", Color(0.74, 0.76, 0.78), 0.58, 0.4)


static func alum_dark() -> StandardMaterial3D:
	return mat("pp_alum2", Color(0.5, 0.52, 0.54), 0.5, 0.48)


static func brass() -> StandardMaterial3D:
	return mat("pp_brass", Color(0.76, 0.58, 0.26), 0.94, 0.26)


static func black() -> StandardMaterial3D:
	return mat("pp_black", Color(0.05, 0.05, 0.06), 0.04, 0.8)


static func bronze_sinter() -> StandardMaterial3D:
	return mat("pp_sinter", Color(0.62, 0.46, 0.28), 0.22, 0.88)


static func plastic_blue() -> StandardMaterial3D:
	return mat("pp_blue", Color(0.1, 0.36, 0.72), 0.04, 0.48)


static func rubber() -> StandardMaterial3D:
	return mat("pp_rub", Color(0.08, 0.08, 0.09), 0.0, 0.9)


static func red_btn() -> StandardMaterial3D:
	return mat("pp_red", Color(0.82, 0.12, 0.1), 0.06, 0.45)


static func steel() -> StandardMaterial3D:
	return mat("pp_steel", Color(0.6, 0.61, 0.63), 0.92, 0.24)


## Никелированная латунь фитинга (реф: Male Straight push-in).
static func nickel() -> StandardMaterial3D:
	return mat("pp_nickel", Color(0.78, 0.80, 0.84), 0.93, 0.22)


static func din_blue() -> StandardMaterial3D:
	return mat("pp_din", Color(0.1, 0.34, 0.55), 0.12, 0.45)


## Camozzi 2931: резьба (цилиндр) → шестигранник AF → синее кольцо цанги. Без конусов.
## tube_flush: порт на торце цанги (трубка вплотную), иначе +1 мм запас.
static func add_fitting(parent: Node, origin: Vector3, axis: String, scale := 1.0, tube_flush := false) -> Vector3:
	var d := _axis_dir(axis)
	var p := dims().get("fitting_2931_G1_4", {})
	var total_l := mm(float(p.get("bbox", [27, 17, 15])[0])) * scale
	# hex_r в dims — половина AF; _hex ждёт across-flats.
	var af := mm(float(p.get("hex_r", 7.5)) * 2.0) * scale
	var thread_r := af * 0.36
	var collet_r := mm(float(p.get("collet_r", 5.5))) * scale
	var t := 0.0
	# 1) Резьбовой хвостовик + белый герметик.
	var thread_h := total_l * 0.30
	cyl(parent, thread_r, thread_h, origin + d * (thread_h * 0.5), axis, nickel(), 20, "shell")
	cyl(parent, thread_r * 1.06, thread_h * 0.55, origin + d * (thread_h * 0.48), axis, mat("pp_seal", Color(0.93, 0.94, 0.91), 0.2, 0.62), 18, "shell")
	t = thread_h
	# 2) Шестигранник — самый широкий сегмент, прямые грани.
	var hex_h := total_l * 0.40
	_hex(parent, af, hex_h, origin + d * (t + hex_h * 0.5), axis, nickel())
	t += hex_h
	# 3) Тонкое металлическое кольцо цанги.
	var ring_h := total_l * 0.05
	cyl(parent, collet_r * 1.08, ring_h, origin + d * (t + ring_h * 0.5), axis, nickel(), 20, "shell")
	t += ring_h
	# 4) Синее пластиковое кольцо отпускания — плоский цилиндр.
	var blue_h := total_l * 0.20
	cyl(parent, collet_r, blue_h, origin + d * (t + blue_h * 0.5), axis, plastic_blue(), 24, "shell")
	cyl(parent, collet_r * 0.52, blue_h * 0.4, origin + d * (t + blue_h * 0.72), axis, rubber(), 16, "shell")
	t += blue_h
	if tube_flush:
		# Глубже в цангу — трубка визуально сидит в синем кольце.
		return origin + d * (t - blue_h * 0.65)
	return origin + d * (t + mm(1.0) * scale)


## Camozzi S6510: латунная резьба+шестигранник → усечённый конус спечённой бронзы (плоский торец).
static func add_silencer(parent: Node, origin: Vector3, axis: String, scale := 1.0) -> Vector3:
	var d := _axis_dir(axis)
	var p := dims().get("silencer_S6510_G3_8", {})
	var total_l := mm(float(p.get("bbox", [23.5, 22, 19])[0])) * scale
	var body_r := mm(float(p.get("body_r", 9.5))) * scale
	var af := mm(float(p.get("hex_r", 6.5)) * 2.0) * scale
	var thread_r := af * 0.36
	var tip_r := body_r * 0.58
	var t := 0.0
	# 1) Резьба.
	var thread_h := total_l * 0.18
	cyl(parent, thread_r, thread_h, origin + d * (thread_h * 0.5), axis, brass(), 16, "shell")
	t = thread_h
	# 2) Латунный шестигранник под ключ.
	var hex_h := total_l * 0.16
	_hex(parent, af, hex_h, origin + d * (t + hex_h * 0.5), axis, brass())
	t += hex_h
	# 3) Буртик под запрессовку спечёнки.
	var lip_h := total_l * 0.04
	cyl(parent, body_r * 0.92, lip_h, origin + d * (t + lip_h * 0.5), axis, brass(), 16, "shell")
	t += lip_h
	# 4) Усечённый конус (frustum): широкий у шестигранника, плоский узкий торец.
	var cone_h := total_l * 0.58
	frustum(parent, body_r, tip_r, cone_h, origin + d * (t + cone_h * 0.5), axis, bronze_sinter(), 28, "shell")
	t += cone_h
	# Плоский торец — явно не остриё.
	var tip_h := total_l * 0.04
	cyl(parent, tip_r, tip_h, origin + d * (t + tip_h * 0.5), axis, bronze_sinter(), 20, "shell")
	t += tip_h
	return origin + d * (t + mm(1.0) * scale)


## 338L: фланец + трубка + гайка; опционально штуцер пилота на конце трубки.
static func add_armature_tube(parent: Node, face_x: float, sign: float, body_h: float, spool: Node3D = null, left: bool = true, end_pilot_fitting: bool = false) -> Vector3:
	var axis := "x" if sign > 0.0 else "-x"
	var p: Dictionary = dims().get("valve_338L_015_02", {})
	var tube_len := mm(float(p.get("tube_len", 14.0)))
	var tube_r := mm(float(p.get("tube_r", 5.0)))
	var flange_h := mm(float(p.get("flange_h", 3.0)))
	var flange_r := mm(float(p.get("flange_r", 9.0)))
	var nut_af := mm(float(p.get("nut_af", 15.0)))
	var nut_h := mm(float(p.get("nut_h", 5.0)))
	var flange_c := face_x + sign * (flange_h * 0.5)
	cyl(parent, flange_r, flange_h, Vector3(flange_c, 0, 0), axis, alum_dark(), 16, "shell")
	var tube_c := face_x + sign * (flange_h + tube_len * 0.5)
	cyl(parent, tube_r, tube_len, Vector3(tube_c, 0, 0), axis, steel(), 18, "shell")
	var nut_c := face_x + sign * (flange_h + tube_len + nut_h * 0.5)
	_hex(parent, nut_af, nut_h, Vector3(nut_c, 0, 0), axis, alum_dark())
	var push_len := tube_len + flange_h + mm(8.0)
	if spool != null:
		var rod := MeshInstance3D.new()
		rod.name = "ArmaturePusher"
		var mesh := CylinderMesh.new()
		mesh.top_radius = mm(2.5)
		mesh.bottom_radius = mm(2.5)
		mesh.height = push_len
		mesh.radial_segments = 12
		rod.mesh = mesh
		rod.material_override = steel()
		rod.set_meta("xray_role", "internal")
		_orient(rod, axis)
		var body_l := float(spool.get_meta("body_l", 0.08))
		rod.position = Vector3(sign * (body_l * 0.28), 0, 0)
		spool.add_child(rod)
	var tip_x := face_x + sign * (flange_h + tube_len + nut_h)
	if end_pilot_fitting:
		return add_fitting(parent, Vector3(tip_x, 0, 0), axis, 0.62)
	return Vector3(tip_x, 0, 0)


## Красный дублёр на корпусе ПР (не на трубке катушки).
static func add_body_override_button(parent: Node, face_x: float, sign: float, body_h: float, body_w: float, left: bool) -> void:
	var axis := "z"
	var tip_r := mm(3.4)
	var tip_h := mm(6.0)
	var x := face_x - sign * mm(6.0)
	var y := -body_h * 0.12
	var z := body_w * 0.5
	var act := _make_actuator(parent, left, Vector3(0, 0, -mm(3.5)))
	cyl(act, tip_r * 1.15, mm(2.0), Vector3(x, y, z + mm(1.0)), axis, alum_dark(), 12, "control")
	cyl(act, tip_r, tip_h, Vector3(x, y, z + mm(2.0) + tip_h * 0.5), axis, red_btn(), 12, "control")


## Катушка U75 — только при связанном элементе coil; садится на трубку 338L.
static func add_coil_on_tube(parent: Node, face_x: float, sign: float, _body_h: float) -> void:
	var p: Dictionary = dims().get("coil_U75_24", {})
	var bb = p.get("bbox", [22, 29.5, 39.8])
	var coil_w := mm(float(bb[0]))
	var coil_h := mm(float(bb[1]))
	var coil_d := mm(float(bb[2]))
	var v: Dictionary = dims().get("valve_338L_015_02", {})
	var flange_h := mm(float(v.get("flange_h", 3.0)))
	# Надевается на трубку сразу за фланцем (ось = длина катушки по bbox[0]).
	var cx := face_x + sign * (flange_h + coil_w * 0.5)
	var body := MeshInstance3D.new()
	body.name = "CoilBody"
	var bm := BoxMesh.new()
	bm.size = Vector3(coil_w, coil_h, coil_d)
	body.mesh = bm
	body.position = Vector3(cx, 0, 0)
	body.material_override = black()
	body.set_meta("xray_role", "shell")
	body.set_meta("part", "coil")
	parent.add_child(body)
	var din_c := Vector3(cx, coil_h * 0.5 + mm(8.0), 0)
	var din := MeshInstance3D.new()
	din.name = "CoilDin"
	var dm := BoxMesh.new()
	dm.size = Vector3(coil_w * 0.85, mm(14.0), mm(22.0))
	din.mesh = dm
	din.position = din_c
	din.material_override = din_blue()
	din.set_meta("xray_role", "shell")
	din.set_meta("part", "coil")
	parent.add_child(din)
	cyl(parent, mm(3.5), mm(8.0), din_c + Vector3(0, mm(14.0), 0), "y", black(), 8, "shell")


static func add_side_button(parent: Node, face_x: float, sign: float, spool: Node3D = null, left: bool = true) -> void:
	var axis := "x" if sign > 0.0 else "-x"
	# Фланец снаружи торцевой стенки (wall ≈3.5+0.2 мм) — без наложения на торец.
	var wall_out: float = mm(3.7)
	var flange_c: float = face_x + sign * (wall_out + mm(2.0))
	box(parent, Vector3(mm(4.0), mm(22.0), mm(20.0)), Vector3(flange_c, 0, 0), black(), "shell")
	_link_button_stem(spool, face_x, sign, axis)
	var act := _make_actuator(parent, left, Vector3(-sign * mm(5.0), 0, 0))
	# Чёрный шток: сквозь торец до стыка с OpLink и наружу к красной кнопке.
	var stem_inner: float = face_x - sign * mm(3.0)
	var stem_outer: float = face_x + sign * mm(17.0)
	var stem_c: float = 0.5 * (stem_inner + stem_outer)
	var stem_len: float = absf(stem_outer - stem_inner)
	cyl(act, mm(5.0), stem_len, Vector3(stem_c, 0, 0), axis, black(), 14, "control")
	cyl(act, mm(12.0), mm(6.0), Vector3(face_x + sign * mm(20.0), 0, 0), axis, red_btn(), 18, "control")


static func add_side_plunger(parent: Node, face_x: float, sign: float, spool: Node3D = null, left: bool = true) -> void:
	var axis := "x" if sign > 0.0 else "-x"
	var wall_out: float = mm(3.7)
	box(parent, Vector3(mm(3.0), mm(18.0), mm(18.0)), Vector3(face_x + sign * (wall_out + mm(1.5)), 0, 0), alum_dark(), "shell")
	_link_button_stem(spool, face_x, sign, axis)
	var act := _make_actuator(parent, left, Vector3(-sign * mm(6.0), 0, 0))
	var stem_inner: float = face_x - sign * mm(3.0)
	var stem_outer: float = face_x + sign * mm(22.0)
	cyl(act, mm(4.0), absf(stem_outer - stem_inner), Vector3(0.5 * (stem_inner + stem_outer), 0, 0), axis, steel(), 12, "control")
	cyl(act, mm(7.0), mm(5.0), Vector3(face_x + sign * mm(24.0), 0, 0), axis, alum_dark(), 14, "control")


static func add_side_roller(parent: Node, face_x: float, sign: float, spool: Node3D = null, left: bool = true) -> void:
	var axis := "x" if sign > 0.0 else "-x"
	var wall_out: float = mm(3.7)
	box(parent, Vector3(mm(3.0), mm(16.0), mm(16.0)), Vector3(face_x + sign * (wall_out + mm(1.5)), 0, 0), alum_dark(), "shell")
	_link_button_stem(spool, face_x, sign, axis)
	var act := _make_actuator(parent, left, Vector3(-sign * mm(5.0), 0, 0))
	var stem_inner: float = face_x - sign * mm(3.0)
	var stem_outer: float = face_x + sign * mm(18.0)
	cyl(act, mm(3.5), absf(stem_outer - stem_inner), Vector3(0.5 * (stem_inner + stem_outer), 0, 0), axis, steel(), 12, "control")
	cyl(act, mm(8.0), mm(7.0), Vector3(face_x + sign * mm(20.0), 0, 0), "z", black(), 16, "control")


static func _make_actuator(parent: Node, left: bool, travel: Vector3) -> Node3D:
	var act := Node3D.new()
	act.name = "ActuatorL" if left else "ActuatorR"
	act.set_meta("actuate_side", "left" if left else "right")
	act.set_meta("actuate_travel", travel)
	act.set_meta("actuate_rest", Vector3.ZERO)
	parent.add_child(act)
	return act


static func add_pilot_cap(parent: Node, face_x: float, sign: float) -> void:
	var axis := "x" if sign > 0.0 else "-x"
	box(parent, Vector3(mm(8.0), mm(22.0), mm(22.0)), Vector3(face_x + sign * mm(4.0), 0, 0), alum(), "shell")
	add_fitting(parent, Vector3(face_x + sign * mm(8.0), 0, 0), axis, 0.7)


## Шток от торца золотника до торца корпуса — смыкается с чёрным штоком кнопки.
static func _link_button_stem(spool: Node3D, face_x: float, sign: float, axis: String) -> void:
	if spool == null:
		return
	var body_l: float = float(spool.get_meta("body_l", 0.08))
	# В локали золотника: от конца вала (~0.37·L) наружу до плоскости торца корпуса.
	var spool_x: float = spool.position.x
	var shaft_end_local: float = sign * body_l * 0.34
	var face_local: float = face_x - spool_x
	# За торец в зону чёрного штока — нахлёст, чтобы не было щели при ходе золотника.
	var outer_local: float = face_local + sign * mm(5.0)
	var x0: float = shaft_end_local
	var x1: float = outer_local
	var link_len: float = absf(x1 - x0)
	if link_len < mm(4.0):
		link_len = mm(4.0)
	var link := MeshInstance3D.new()
	link.name = "OpLink"
	var mesh := CylinderMesh.new()
	mesh.top_radius = mm(2.4)
	mesh.bottom_radius = mm(2.4)
	mesh.height = link_len
	mesh.radial_segments = 10
	link.mesh = mesh
	link.material_override = steel()
	link.set_meta("xray_role", "internal")
	_orient(link, axis)
	link.position = Vector3(0.5 * (x0 + x1), 0, 0)
	spool.add_child(link)


static func box(parent: Node, size: Vector3, center: Vector3, mat: Material, role: String) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	parent.add_child(mi)


static func cyl(parent: Node, radius: float, length: float, center: Vector3, axis: String, mat: Material, segs: int, role: String) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(length, 0.0004)
	mesh.radial_segments = maxi(segs, 6)
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	_orient(mi, axis)
	parent.add_child(mi)


## O-ring: тор с круглым сечением. shaft_r — радиус вала под кольцом, tube_r — радиус сечения.
static func oring(parent: Node, shaft_r: float, tube_r: float, center: Vector3, axis: String, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	var major := shaft_r + tube_r
	var minor := maxf(tube_r, 0.00015)
	# Godot TorusMesh: inner/outer — крайние радиусы от оси тора.
	mesh.inner_radius = maxf(major - minor, 0.0001)
	mesh.outer_radius = major + minor
	mesh.rings = 14
	mesh.ring_segments = 22
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", "internal")
	# Тор по умолчанию вокруг Y; для золотника по X — поворот.
	var a := axis
	if a.begins_with("-"):
		a = a.substr(1)
	if a == "x":
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif a == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(mi)


## Усечённый конус: r_near у корпуса/предыдущего сегмента, r_far — наружный конец.
static func frustum(parent: Node, r_near: float, r_far: float, length: float, center: Vector3, axis: String, mat: Material, segs: int, role: String) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	# _orient("x"): +Y → −X (Z+90°). Для ±X наружный конец = top при "−x", bottom при "+x".
	# Для ±Y/±Z наружный при "−*" = bottom (без зеркала оси).
	var ax: String = str(axis)
	var neg: bool = ax.begins_with("-")
	var a: String = ax.substr(1) if neg else ax
	var r_out: float = maxf(r_far, 0.0002)
	var r_in: float = maxf(r_near, 0.0002)
	if a == "x":
		if neg:
			mesh.top_radius = r_out
			mesh.bottom_radius = r_in
		else:
			mesh.top_radius = r_in
			mesh.bottom_radius = r_out
	elif neg:
		mesh.top_radius = r_in
		mesh.bottom_radius = r_out
	else:
		mesh.top_radius = r_out
		mesh.bottom_radius = r_in
	mesh.height = maxf(length, 0.0004)
	mesh.radial_segments = maxi(segs, 8)
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	_orient(mi, axis)
	parent.add_child(mi)


## af — размер «под ключ» (across flats). Circumradius = AF / √3.
static func _hex(parent: Node, af: float, height: float, center: Vector3, axis: String, mat: Material) -> void:
	cyl(parent, maxf(af, 0.0004) / sqrt(3.0), height, center, axis, mat, 6, "shell")


static func _axis_dir(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		"z":
			return Vector3.BACK
		"-x":
			return Vector3.LEFT
		"-y":
			return Vector3.DOWN
		"-z":
			return Vector3.FORWARD
		_:
			return Vector3.UP


static func _orient(mi: MeshInstance3D, axis: String) -> void:
	var a := axis
	if a.begins_with("-"):
		a = a.substr(1)
	if a == "x":
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif a == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
