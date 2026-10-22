class_name IsoRegulator
extends RefCounted
## 3D редуктор (КР): чёрный квадратный корпус из двух половин, фитинги L/R,
## низкая гайка + колпачок-ручка (клик = lock/unlock, drag = уставка).
## Рентген не делаем — всё shell.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")

## 0 = полностью затянут (седло закрыто, питания 1→2 нет).
const SET_MIN_BAR := 0.0
const SET_MAX_BAR := 10.0
const SHUT_BAR := 0.05 # ниже — полное перекрытие питания
const KNOB_LIFT_MM := 8.0
const KNOB_TURNS := 2.5 # полных оборота от min до max


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od: float = TubeFit.port_tube_od(el, "")
	if od < 1.0:
		od = 8.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var body_s: float = TubeFit.armature_body_scale(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.55
	var body_w: float = Parts.mm(42.0) * body_s
	var body_h: float = Parts.mm(48.0) * body_s
	var body_d: float = Parts.mm(42.0) * body_s
	var black: StandardMaterial3D = Parts.black()
	var metal: StandardMaterial3D = Parts.steel()
	var knob_mat: StandardMaterial3D = Parts.mat("reg_knob", Color(0.18, 0.19, 0.21), 0.08, 0.72)
	_build_body(parent, body_w, body_h, body_d, black, metal, body_s)
	var fit_total: float = Parts.mm(27.0) * fit_scale
	var embed: float = fit_total * 0.55
	var port_y: float = -body_h * 0.08
	var tip_l: Vector3 = Parts.add_fitting(
		parent, Vector3(-body_w * 0.5 + embed, port_y, 0.0), "-x", fit_scale, true
	)
	var tip_r: Vector3 = Parts.add_fitting(
		parent, Vector3(body_w * 0.5 - embed, port_y, 0.0), "x", fit_scale, true
	)
	info["ports"]["1"] = tip_l
	info["ports"]["2"] = tip_r
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	_build_knob_stack(parent, body_h, body_s, metal, knob_mat)
	apply_knob(parent, el)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 18
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(28.0) * body_s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)
	parent.set_meta("accessory_regulator", true)
	parent.set_meta("body_s", body_s)
	# Сброс (relief): из‑под нижнего бобышки вниз — видно, куда уходит давление.
	var boss_h: float = Parts.mm(8.0) * body_s
	parent.set_meta("relief_local", Vector3(0.0, -body_h * 0.5 - boss_h * 0.95, 0.0))
	parent.set_meta("relief_dir", Vector3.DOWN)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-body_w * 0.5 - Parts.mm(14.0) * body_s, -body_h * 0.55, -body_d * 0.5),
		Vector3(body_w + Parts.mm(28.0) * body_s, body_h * 1.35, body_d)
	))
	return info


static func apply_knob(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var body_s: float = float(root.get_meta("body_s", 1.0))
	var unlocked: bool = bool(el.regulator_unlocked) if "regulator_unlocked" in el else false
	var set_bar: float = clampf(float(el.set_pressure_bar), SET_MIN_BAR, SET_MAX_BAR)
	var t: float = (set_bar - SET_MIN_BAR) / (SET_MAX_BAR - SET_MIN_BAR)
	var knob: Node3D = root.get_node_or_null("RegulatorKnob") as Node3D
	if knob == null:
		return
	var y0: float = float(knob.get_meta("y0", knob.position.y))
	knob.set_meta("y0", y0)
	var lift: float = Parts.mm(KNOB_LIFT_MM) * body_s if unlocked else 0.0
	knob.position.y = y0 + lift
	# Правая резьба сверху: рост уставки = против часовой (−Y в Godot) — как «затягивание» пружины.
	knob.rotation_degrees = Vector3(0.0, -t * KNOB_TURNS * 360.0, 0.0)


static func pick_knob(root: Node3D, origin: Vector3, dir: Vector3) -> bool:
	if root == null:
		return false
	var knob: Node3D = root.get_node_or_null("RegulatorKnob") as Node3D
	if knob == null:
		return false
	var center: Vector3 = knob.global_position
	var radius: float = Parts.mm(14.0)
	var w: Vector3 = origin - center
	var b: float = dir.dot(w)
	var c: float = w.dot(w) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		var local: Vector3 = root.to_local(origin + dir * origin.distance_to(center))
		var tip: Vector3 = root.to_local(center)
		return absf(local.x - tip.x) < Parts.mm(16.0) and absf(local.z - tip.z) < Parts.mm(16.0) \
				and local.y > tip.y - Parts.mm(6.0) and local.y < tip.y + Parts.mm(20.0)
	var t: float = -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	return t >= 0.0 and t < 2.5


static func _build_body(
	parent: Node, body_w: float, body_h: float, body_d: float,
	black: Material, metal: Material, body_s: float
) -> void:
	var comb := CSGCombiner3D.new()
	var half_h: float = body_h * 0.5
	# Нижняя и верхняя половины — шов посредине.
	var lower := CsgBake.box(Vector3(body_w, half_h * 0.98, body_d), Vector3(0.0, -half_h * 0.5, 0.0))
	var upper := CsgBake.box(Vector3(body_w * 0.98, half_h * 0.98, body_d * 0.98), Vector3(0.0, half_h * 0.5, 0.0))
	comb.add_child(lower)
	comb.add_child(upper)
	# Скругления вертикальных рёбер (цилиндры по углам).
	var fillet_r: float = Parts.mm(5.0) * body_s
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = sx * (body_w * 0.5 - fillet_r * 0.85)
			var cz: float = sz * (body_d * 0.5 - fillet_r * 0.85)
			comb.add_child(CsgBake.cyl(fillet_r, body_h * 0.96, Vector3(cx, 0.0, cz), "y"))
	# Нижний цилиндрический выступ.
	var boss_h: float = Parts.mm(8.0) * body_s
	var boss_r: float = Parts.mm(7.0) * body_s
	comb.add_child(CsgBake.cyl(boss_r, boss_h, Vector3(0.0, -body_h * 0.5 - boss_h * 0.45, 0.0), "y"))
	# Передний порт под манометр (заглушка-кольцо, без стрелки).
	var gauge_r: float = Parts.mm(5.5) * body_s
	var gauge_d: float = Parts.mm(4.0) * body_s
	comb.add_child(CsgBake.cyl(
		gauge_r, gauge_d,
		Vector3(0.0, -body_h * 0.05, body_d * 0.5 - gauge_d * 0.35),
		"z"
	))
	CsgBake.attach(parent, comb, black, "shell")
	# Винты по углам верхней половины (шляпки).
	var screw_y: float = half_h * 0.92
	var screw_inset: float = Parts.mm(6.0) * body_s
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			Parts.cyl(
				parent, Parts.mm(1.8) * body_s, Parts.mm(1.2) * body_s,
				Vector3(sx2 * (body_w * 0.5 - screw_inset), screw_y, sz2 * (body_d * 0.5 - screw_inset)),
				"y", metal, 10, "shell"
			)


static func _build_knob_stack(
	parent: Node, body_h: float, body_s: float, metal: Material, knob_mat: Material
) -> void:
	var top_y: float = body_h * 0.5
	# Короткая шейка — только чтобы гайка села на верхнюю плоскость корпуса.
	var neck_h: float = Parts.mm(2.5) * body_s
	var neck_r: float = Parts.mm(9.0) * body_s
	Parts.cyl(
		parent, neck_r, neck_h,
		Vector3(0.0, top_y + neck_h * 0.5, 0.0),
		"y", Parts.mat("reg_neck", Color(0.14, 0.14, 0.15), 0.1, 0.7), 20, "shell"
	)
	# Большая низкая гайка — прижата к верху корпуса (низ гайки ≈ top_y + neck).
	var nut_h: float = Parts.mm(4.0) * body_s
	var nut_y: float = top_y + neck_h + nut_h * 0.5
	var nut_chrome: StandardMaterial3D = Parts.mat(
		"reg_nut_chrome", Color(0.78, 0.80, 0.84), 0.96, 0.18
	)
	var nut := MeshInstance3D.new()
	nut.name = "RegulatorNut"
	var nut_mesh := CylinderMesh.new()
	nut_mesh.top_radius = Parts.mm(17.0) * body_s
	nut_mesh.bottom_radius = Parts.mm(17.0) * body_s
	nut_mesh.height = nut_h
	nut_mesh.radial_segments = 6
	nut.mesh = nut_mesh
	nut.material_override = nut_chrome
	nut.position = Vector3(0.0, nut_y, 0.0)
	nut.set_meta("xray_role", "shell")
	parent.add_child(nut)
	# Шпилька уставки над гайкой.
	var stem_h: float = Parts.mm(12.0) * body_s
	var stem_y0: float = nut_y + nut_h * 0.5
	Parts.cyl(
		parent, Parts.mm(3.2) * body_s, stem_h,
		Vector3(0.0, stem_y0 + stem_h * 0.4, 0.0),
		"y", metal, 12, "shell"
	)
	# Колпачок-ручка с продольными рёбрами.
	var knob := Node3D.new()
	knob.name = "RegulatorKnob"
	var knob_y0: float = stem_y0 + Parts.mm(2.0) * body_s
	knob.position = Vector3(0.0, knob_y0, 0.0)
	knob.set_meta("y0", knob_y0)
	knob.set_meta("xray_role", "control")
	parent.add_child(knob)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = Parts.mm(13.0) * body_s
	cap_mesh.bottom_radius = Parts.mm(13.5) * body_s
	cap_mesh.height = Parts.mm(18.0) * body_s
	cap_mesh.radial_segments = 24
	cap.mesh = cap_mesh
	cap.material_override = knob_mat
	cap.position = Vector3(0.0, Parts.mm(9.0) * body_s, 0.0)
	knob.add_child(cap)
	# Рёбра (knurl): тонкая ось по нормали цилиндра, длина по Y.
	var ribs: int = 12
	var rib_r: float = Parts.mm(14.2) * body_s
	var rib_y: float = Parts.mm(9.0) * body_s
	for i in ribs:
		var ang: float = TAU * float(i) / float(ribs)
		var rib := MeshInstance3D.new()
		var rib_mesh := BoxMesh.new()
		# X = радиальной толщины (по нормали), Y = высота, Z = ширина по касательной.
		rib_mesh.size = Vector3(Parts.mm(1.6) * body_s, Parts.mm(16.0) * body_s, Parts.mm(2.2) * body_s)
		rib.mesh = rib_mesh
		rib.material_override = knob_mat
		rib.position = Vector3(cos(ang) * rib_r, rib_y, sin(ang) * rib_r)
		# +X → (cos, 0, sin) — перпендикулярно образующей цилиндра.
		rib.rotation = Vector3(0.0, ang, 0.0)
		rib.set_meta("xray_role", "control")
		knob.add_child(rib)
