class_name IsoJunction
extends RefCounted
## 3D фитинги ветвления: тройник T, Y и коллектор (чёрный корпус + синие цанги).
## Масштаб корпуса и цанг — от OD трубки элемента.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var style := str(el.get("junction_style") if el.get("junction_style") != null else "tee")
	if style == "adapter":
		_build_adapter(parent, info, el)
		var label_ad := Label3D.new()
		label_ad.name = "Tag"
		label_ad.text = el.tag
		label_ad.font_size = 18
		label_ad.pixel_size = 0.00028
		label_ad.modulate = Color(0.15, 0.17, 0.2)
		label_ad.position = Vector3(0, Parts.mm(12.0), Parts.mm(4.0))
		label_ad.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_ad.visible = false
		parent.add_child(label_ad)
		return info
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var tip_s: float = TubeFit.fitting_scale(thread, od) * 0.52
	match style:
		"wye":
			_build_wye(parent, info, body_s, tip_s)
		"manifold":
			_build_manifold(parent, info, maxi(int(el.get("junction_ports") if el.get("junction_ports") != null else 5), 3), body_s, tip_s)
		_:
			_build_tee(parent, info, body_s, tip_s)
	var label := Label3D.new()
	label.name = "Tag"
	label.text = el.tag
	label.font_size = 18
	label.pixel_size = 0.00028
	label.modulate = Color(0.15, 0.17, 0.2)
	label.position = Vector3(0, Parts.mm(14.0) * body_s, Parts.mm(6.0) * body_s)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visible = false # обозначение — во всплывающей подсказке
	parent.add_child(label)
	return info


static func _mat_body() -> StandardMaterial3D:
	return Parts.mat("jj_body", Color(0.07, 0.07, 0.08), 0.04, 0.75)


static func _port_tip(parent: Node, origin: Vector3, axis: String, scale := 0.5) -> Vector3:
	var d := Parts._axis_dir(axis)
	var r := Parts.mm(4.8) * scale
	var ring_h := Parts.mm(1.1) * scale
	var blue_h := Parts.mm(4.2) * scale
	Parts.cyl(parent, r * 1.06, ring_h, origin + d * (ring_h * 0.5), axis, Parts.nickel(), 16, "shell")
	Parts.cyl(parent, r, blue_h, origin + d * (ring_h + blue_h * 0.5), axis, Parts.plastic_blue(), 20, "shell")
	Parts.cyl(parent, r * 0.48, blue_h * 0.35, origin + d * (ring_h + blue_h * 0.72), axis, Parts.rubber(), 12, "shell")
	# Точка выхода шланга — чуть дальше цанги, вдоль оси.
	return origin + d * (ring_h + blue_h + Parts.mm(1.2) * scale)


static func _build_tee(parent: Node3D, info: Dictionary, body_s: float, tip_s: float) -> void:
	var body := _mat_body()
	var r := Parts.mm(5.6) * body_s
	var arm := Parts.mm(11.0) * body_s
	# Цельный T: горизонтальный проход + ответвление вверх (как УГО).
	Parts.cyl(parent, r, arm * 2.0, Vector3.ZERO, "x", body, 18, "shell")
	Parts.cyl(parent, r, arm + Parts.mm(2.0) * body_s, Vector3(0, arm * 0.5, 0), "y", body, 18, "shell")
	# Скруглённый узел в центре.
	Parts.cyl(parent, r * 1.12, Parts.mm(7.0) * body_s, Vector3.ZERO, "z", body, 16, "shell")
	Parts.cyl(parent, Parts.mm(2.0) * body_s, Parts.mm(2.0) * body_s, Vector3(-Parts.mm(4.5) * body_s, -Parts.mm(4.0) * body_s, Parts.mm(4.0) * body_s), "z", body, 10, "shell")
	Parts.cyl(parent, Parts.mm(2.0) * body_s, Parts.mm(2.0) * body_s, Vector3(Parts.mm(4.5) * body_s, -Parts.mm(4.0) * body_s, Parts.mm(4.0) * body_s), "z", body, 10, "shell")
	var tip1 := _port_tip(parent, Vector3(-arm, 0, 0), "-x", tip_s)
	var tip2 := _port_tip(parent, Vector3(arm, 0, 0), "x", tip_s)
	var tip3 := _port_tip(parent, Vector3(0, arm, 0), "y", tip_s)
	info["ports"]["1"] = tip1
	info["dirs"]["1"] = Vector3.LEFT
	info["ports"]["2"] = tip2
	info["dirs"]["2"] = Vector3.RIGHT
	info["ports"]["3"] = tip3
	info["dirs"]["3"] = Vector3.UP


static func _build_wye(parent: Node3D, info: Dictionary, body_s: float, tip_s: float) -> void:
	var body := _mat_body()
	var r := Parts.mm(5.4) * body_s
	var arm := Parts.mm(11.0) * body_s
	Parts.cyl(parent, r, arm, Vector3(0, -arm * 0.5, 0), "-y", body, 16, "shell")
	var left_end := Vector3(-arm * 0.72, arm * 0.55, 0)
	var right_end := Vector3(arm * 0.72, arm * 0.55, 0)
	_angled_arm(parent, Vector3(0, -Parts.mm(2.0) * body_s, 0), left_end, r, body)
	_angled_arm(parent, Vector3(0, -Parts.mm(2.0) * body_s, 0), right_end, r, body)
	Parts.cyl(parent, Parts.mm(2.2) * body_s, Parts.mm(2.5) * body_s, Vector3(0, Parts.mm(1.0) * body_s, 0), "y", body, 10, "shell")
	info["ports"]["1"] = _port_tip(parent, Vector3(0, -arm, 0), "-y", tip_s)
	info["dirs"]["1"] = Vector3.DOWN
	# Направления Y-ветвей — вдоль осей отводов, не просто UP.
	var d2 := left_end.normalized()
	var d3 := right_end.normalized()
	info["ports"]["2"] = _port_tip(parent, left_end, "y", tip_s * 0.92)
	info["dirs"]["2"] = d2
	info["ports"]["3"] = _port_tip(parent, right_end, "y", tip_s * 0.92)
	info["dirs"]["3"] = d3


static func _angled_arm(parent: Node, from: Vector3, to: Vector3, r: float, mat: Material) -> void:
	var mid := (from + to) * 0.5
	var len := from.distance_to(to)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = maxf(len, 0.001)
	mesh.radial_segments = 14
	mi.mesh = mesh
	mi.position = mid
	mi.material_override = mat
	mi.set_meta("xray_role", "shell")
	parent.add_child(mi)
	var dir := to - from
	if dir.length_squared() > 1.0e-10:
		mi.look_at(mi.global_position + dir.normalized(), Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)


static func _build_manifold(parent: Node3D, info: Dictionary, n: int, body_s: float, tip_s: float) -> void:
	var body := _mat_body()
	n = clampi(n, 3, 6)
	var side_n := n - 2
	var r := Parts.mm(6.4) * body_s
	var pitch := Parts.mm(15.0) * body_s
	var span := pitch * float(maxi(side_n - 1, 1))
	var half := span * 0.5
	Parts.cyl(parent, r, span + Parts.mm(20.0) * body_s, Vector3.ZERO, "x", body, 18, "shell")
	info["ports"]["1"] = _port_tip(parent, Vector3(-half - Parts.mm(9.0) * body_s, 0, 0), "-x", tip_s * 0.92)
	info["dirs"]["1"] = Vector3.LEFT
	info["ports"]["2"] = _port_tip(parent, Vector3(half + Parts.mm(9.0) * body_s, 0, 0), "x", tip_s * 0.92)
	info["dirs"]["2"] = Vector3.RIGHT
	var stub := Parts.mm(9.0) * body_s
	for i in side_n:
		var x := 0.0 if side_n == 1 else lerpf(-half, half, float(i) / float(side_n - 1))
		Parts.cyl(parent, r * 0.82, stub, Vector3(x, 0, stub * 0.5), "z", body, 12, "shell")
		var pname := str(i + 3)
		info["ports"][pname] = _port_tip(parent, Vector3(x, 0, stub), "z", tip_s * 0.92)
		info["dirs"][pname] = Vector3.BACK
		if i < side_n - 1 and side_n > 1:
			var x2 := lerpf(-half, half, float(i + 1) / float(side_n - 1))
			Parts.cyl(parent, Parts.mm(2.1) * body_s, Parts.mm(2.8) * body_s, Vector3((x + x2) * 0.5, Parts.mm(5.5) * body_s, 0), "y", body, 8, "shell")


## Переходник Ø→Ø: чёрный цилиндр с проточкой (≈⅓ длины), цанги QS, сквозной канал (CSG).
static func _build_adapter(parent: Node3D, info: Dictionary, el) -> void:
	var od1: float = TubeFit.port_tube_od(el, "1")
	var od2: float = TubeFit.port_tube_od(el, "2")
	var thr1: String = TubeFit.thread_for_tube_od(od1)
	var thr2: String = TubeFit.thread_for_tube_od(od2)
	var fit_s1: float = TubeFit.fitting_scale(thr1, od1) * 0.55
	var fit_s2: float = TubeFit.fitting_scale(thr2, od2) * 0.55
	var body_s1: float = TubeFit.armature_body_scale(od1)
	var body_s2: float = TubeFit.armature_body_scale(od2)
	var body_s: float = maxf(body_s1, body_s2)
	var r1: float = Parts.mm(5.8) * body_s1
	var r2: float = Parts.mm(5.8) * body_s2
	var r_groove: float = (r1 + r2) * 0.5 * 0.78
	var half_l: float = Parts.mm(15.0) * body_s
	var total_l: float = half_l * 2.0
	var groove_l: float = total_l / 3.0
	var end_l: float = (total_l - groove_l) * 0.5
	var bore_r: float = Parts.mm(2.2) * body_s * clampf(minf(od1, od2) / 6.0, 0.7, 1.4)
	_build_adapter_body(parent, r1, r2, r_groove, half_l, end_l, groove_l, bore_r)
	# Как у арматуры: Camozzi QS — шестигранник + синее кольцо цанги.
	var fit_tot1: float = Parts.mm(27.0) * fit_s1
	var fit_tot2: float = Parts.mm(27.0) * fit_s2
	var embed1: float = fit_tot1 * 0.55
	var embed2: float = fit_tot2 * 0.55
	var tip1: Vector3 = Parts.add_fitting(
		parent, Vector3(-half_l + embed1, 0.0, 0.0), "-x", fit_s1, true
	)
	var tip2: Vector3 = Parts.add_fitting(
		parent, Vector3(half_l - embed2, 0.0, 0.0), "x", fit_s2, true
	)
	info["ports"]["1"] = tip1
	info["dirs"]["1"] = Vector3.LEFT
	info["ports"]["2"] = tip2
	info["dirs"]["2"] = Vector3.RIGHT


## Корпус с проточкой + сквозной вырез канала (window — полупрозрачный на рентгене).
static func _build_adapter_body(
	parent: Node, r1: float, r2: float, r_groove: float,
	half_l: float, end_l: float, groove_l: float, bore_r: float
) -> void:
	var body: Material = _mat_body()
	var comb := CSGCombiner3D.new()
	comb.name = "AdapterBodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(
		r1, end_l, Vector3(-half_l + end_l * 0.5, 0.0, 0.0), "x", UNION, 20
	))
	comb.add_child(CsgBake.cyl(r_groove, groove_l, Vector3.ZERO, "x", UNION, 18))
	comb.add_child(CsgBake.cyl(
		r2, end_l, Vector3(half_l - end_l * 0.5, 0.0, 0.0), "x", UNION, 20
	))
	# Сквозной канал — вырез, не залитый цилиндр (как у дросселя/КО).
	comb.add_child(CsgBake.cyl(
		bore_r, half_l * 2.0 + Parts.mm(4.0), Vector3.ZERO, "x", SUB, 16
	))
	CsgBake.attach(parent, comb, body, "window")
