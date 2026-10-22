class_name IsoQuickExhaust
extends RefCounted
## 3D клапан быстрого выхлопа (Festo SE / тарелка):
## порт 1 — вход (−X), порт 2 — ПЦ (+Y), порт 3 — выхлоп (−Y: глушитель или штуцер).
## opening 1 = питание (тарелка к выхлопу, 1→2); 0 = выхлоп (тарелка к входу, 2→3).

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const ValveCat = preload("res://scripts/domain/valve_catalog.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 8.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_r: float = Parts.mm(14.0) * body_s
	var body_h: float = Parts.mm(28.0) * body_s
	var base_r: float = Parts.mm(18.0) * body_s
	var base_h: float = Parts.mm(8.0) * body_s
	var bore_r: float = Parts.mm(4.2) * body_s
	var disc_r: float = Parts.mm(5.5) * body_s
	var chamber_r: float = Parts.mm(6.8) * body_s
	_build_body(parent, body_r, body_h, base_r, base_h, bore_r, chamber_r, body_s)
	var side_origin := Vector3(-body_r * 0.55, Parts.mm(4.0) * body_s, 0.0)
	var tip_1: Vector3 = Parts.add_fitting(parent, side_origin, "-x", fit_scale, true)
	var tip_2: Vector3 = Parts.add_fitting(
		parent, Vector3(0.0, body_h * 0.5 - Parts.mm(1.0) * body_s, 0.0), "y", fit_scale * 0.95, true
	)
	var exh_origin := Vector3(0.0, -body_h * 0.5 - base_h * 0.15, 0.0)
	var tip_3: Vector3
	var muffler: bool = ValveCat.exhaust_fit(el, "3") == "muffler"
	if muffler:
		tip_3 = Parts.add_silencer(parent, exh_origin, "-y", fit_scale * 1.05)
	else:
		tip_3 = Parts.add_fitting(parent, exh_origin, "-y", fit_scale, true)
	info["ports"]["1"] = tip_1
	info["ports"]["2"] = tip_2
	info["ports"]["3"] = tip_3
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.UP
	info["dirs"]["3"] = Vector3.DOWN
	_build_disc(parent, disc_r, body_s)
	apply_opening(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(body_r + Parts.mm(10.0) * body_s, Parts.mm(8.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_quick_exhaust", true)
	parent.set_meta("y_supply", Parts.mm(2.5) * body_s)
	parent.set_meta("y_exhaust", -Parts.mm(3.5) * body_s)
	return info


static func apply_opening(root: Node3D, el) -> void:
	if root == null:
		return
	var disc: Node3D = root.get_node_or_null("ExhaustDisc") as Node3D
	if disc == null:
		return
	var side: float = clampf(float(el.opening), 0.0, 1.0)
	var y_exh: float = float(root.get_meta("y_exhaust", -0.0035))
	var y_sup: float = float(root.get_meta("y_supply", 0.0025))
	# opening 1 → тарелка к выхлопу (вниз к седлу 3); 0 → к входу (вверх, седло 1).
	disc.position.y = lerpf(y_sup, y_exh, side)


static func _body_mat() -> StandardMaterial3D:
	return Parts.mat("qe_body", Color(0.72, 0.74, 0.76), 0.55, 0.38)


static func _build_body(
	parent: Node, body_r: float, body_h: float, base_r: float, base_h: float,
	bore_r: float, chamber_r: float, body_s: float
) -> void:
	var mat: Material = _body_mat()
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 28))
	comb.add_child(CsgBake.cyl(
		base_r, base_h, Vector3(0.0, -body_h * 0.5 - base_h * 0.35, 0.0), "y", UNION, 24
	))
	# Камера тарелки.
	comb.add_child(CsgBake.cyl(chamber_r, Parts.mm(12.0) * body_s, Vector3.ZERO, "y", SUB, 18))
	# Канал к порту 1 (−X).
	comb.add_child(CsgBake.cyl(
		bore_r, body_r * 1.15, Vector3(-body_r * 0.35, Parts.mm(4.0) * body_s, 0.0), "x", SUB, 14
	))
	# Канал к порту 2 (+Y).
	comb.add_child(CsgBake.cyl(
		bore_r * 0.95, body_h * 0.55, Vector3(0.0, body_h * 0.28, 0.0), "y", SUB, 14
	))
	# Канал выхлопа (−Y) — шире.
	comb.add_child(CsgBake.cyl(
		bore_r * 1.25, body_h * 0.55 + base_h, Vector3(0.0, -body_h * 0.28, 0.0), "y", SUB, 16
	))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_disc(parent: Node, disc_r: float, body_s: float) -> void:
	var disc := MeshInstance3D.new()
	disc.name = "ExhaustDisc"
	var mesh := CylinderMesh.new()
	mesh.top_radius = disc_r
	mesh.bottom_radius = disc_r * 0.92
	mesh.height = Parts.mm(2.8) * body_s
	mesh.radial_segments = 24
	disc.mesh = mesh
	disc.material_override = Parts.mat("qe_disc", Color(0.85, 0.22, 0.18), 0.35, 0.55)
	disc.set_meta("xray_role", "internal")
	disc.position = Vector3(0.0, Parts.mm(2.5) * body_s, 0.0)
	parent.add_child(disc)
	# Центральный «носик» тарелки (седло входа).
	var nub := MeshInstance3D.new()
	nub.name = "DiscNub"
	var nub_m := CylinderMesh.new()
	nub_m.top_radius = disc_r * 0.35
	nub_m.bottom_radius = disc_r * 0.42
	nub_m.height = Parts.mm(2.2) * body_s
	nub_m.radial_segments = 16
	nub.mesh = nub_m
	nub.position = Vector3(0.0, Parts.mm(2.0) * body_s, 0.0)
	nub.material_override = Parts.mat("qe_disc_nub", Color(0.75, 0.18, 0.15), 0.4, 0.5)
	nub.set_meta("xray_role", "internal")
	disc.add_child(nub)
