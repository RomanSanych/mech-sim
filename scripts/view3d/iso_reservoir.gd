class_name IsoReservoir
extends RefCounted
## 3D пневмоаккумулятор (ресивер): баллон + бобышки сверху со штуцерами.
## Габарит от объёма (V=π·r²·L). Динамики внутри нет — без xray-window.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var dims: Dictionary = AccLib.reservoir_dims(el)
	var body_d: float = Parts.mm(float(dims.get("diameter_mm", 100.0)))
	var body_l: float = Parts.mm(float(dims.get("length_mm", 260.0)))
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = float(dims.get("tube_od_mm", 6.0))
	var thread: String = str(el.port_name) if str(el.port_name) != "" else str(dims.get("thread", TubeFit.thread_for_tube_od(od)))
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var r: float = body_d * 0.5
	var n: int = AccLib.reservoir_port_count(el)
	_build_tank(parent, body_l, r)
	_build_feet(parent, body_l, r)
	# Бобышки сверху: приваренные патрубки с вырезом + штуцер на торце.
	var stub_h: float = Parts.mm(16.0) + fit_scale * Parts.mm(3.0)
	var stub_od: float = Parts.mm(maxf(od * 0.58, 5.0))
	var stub_id: float = stub_od * 0.58
	var span: float = body_l * 0.55 if n > 1 else 0.0
	var steel: Material = _steel()
	for i in n:
		var x: float = 0.0
		if n > 1:
			x = lerpf(-span * 0.5, span * 0.5, float(i) / float(n - 1))
		var boss_base := Vector3(x, r - Parts.mm(1.5), 0.0)
		_build_stub(parent, boss_base, stub_od, stub_id, stub_h, steel)
		# Штуцер на верхнем торце (ось +Y).
		var fit_origin := boss_base + Vector3(0.0, stub_h - Parts.mm(1.0), 0.0)
		var tip: Vector3 = Parts.add_fitting(parent, fit_origin, "y", fit_scale, true)
		var pname: String = str(i + 1)
		info["ports"][pname] = tip
		info["dirs"][pname] = Vector3.UP
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, r + stub_h + Parts.mm(18.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_reservoir", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_l * 0.5 - Parts.mm(8.0), -r - Parts.mm(8.0), -r),
		Vector3(body_l + Parts.mm(16.0), body_d + stub_h + Parts.mm(28.0), body_d)
	))
	return info


static func _steel() -> StandardMaterial3D:
	return Parts.mat("res_steel", Color(0.72, 0.74, 0.76), 0.88, 0.28)


## Патрубок: наружный цилиндр минус внутренний канал (приваренная трубка).
static func _build_stub(
	parent: Node, base: Vector3, od: float, id: float, h: float, mat: Material
) -> void:
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "StubCSG"
	var center := base + Vector3(0.0, h * 0.5, 0.0)
	comb.add_child(CsgBake.cyl(od, h, center, "y", UNION, 18))
	# Канал сквозь патрубок (чуть длиннее — чистый вырез на торцах).
	comb.add_child(CsgBake.cyl(id, h + Parts.mm(2.0), center, "y", SUB, 14))
	# Кольцо «сварки» у корня.
	var weld_h: float = Parts.mm(2.4)
	comb.add_child(CsgBake.cyl(
		od * 1.22, weld_h,
		base + Vector3(0.0, weld_h * 0.35, 0.0), "y", UNION, 14
	))
	CsgBake.attach(parent, comb, mat, "shell")


static func _build_tank(parent: Node, body_l: float, r: float) -> void:
	var mat: Material = _steel()
	var cyl_l: float = maxf(body_l - r * 1.15, body_l * 0.55)
	Parts.cyl(parent, r, cyl_l, Vector3.ZERO, "x", mat, 28, "shell")
	_hemisphere(parent, Vector3(-cyl_l * 0.5, 0.0, 0.0), r, -1.0, mat)
	_hemisphere(parent, Vector3(cyl_l * 0.5, 0.0, 0.0), r, 1.0, mat)
	Parts.cyl(
		parent, r * 1.02, Parts.mm(2.2),
		Vector3(-cyl_l * 0.28, 0.0, 0.0), "x",
		Parts.mat("res_weld", Color(0.55, 0.57, 0.6), 0.7, 0.45),
		20, "shell"
	)
	Parts.cyl(
		parent, r * 1.02, Parts.mm(2.2),
		Vector3(cyl_l * 0.28, 0.0, 0.0), "x",
		Parts.mat("res_weld", Color(0.55, 0.57, 0.6), 0.7, 0.45),
		20, "shell"
	)


static func _hemisphere(parent: Node, center: Vector3, r: float, sign_x: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	sph.radial_segments = 20
	sph.rings = 10
	mi.mesh = sph
	mi.position = center + Vector3(sign_x * r * 0.08, 0.0, 0.0)
	mi.scale = Vector3(0.55, 1.0, 1.0)
	mi.material_override = mat
	mi.set_meta("xray_role", "shell")
	parent.add_child(mi)


static func _build_feet(parent: Node, body_l: float, r: float) -> void:
	var foot_mat: Material = Parts.mat("res_foot", Color(0.35, 0.37, 0.4), 0.4, 0.55)
	var y: float = -r - Parts.mm(3.0)
	var half: float = body_l * 0.28
	for sx in [-1.0, 1.0]:
		Parts.box(
			parent,
			Vector3(Parts.mm(18.0), Parts.mm(6.0), Parts.mm(22.0)),
			Vector3(sx * half, y, 0.0),
			foot_mat,
			"shell"
		)
