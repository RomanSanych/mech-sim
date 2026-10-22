class_name IsoPressureTx
extends RefCounted
## 3D датчик избыточного давления B2 (ПИП): «карандаш» нерж. + DIN 43650 голова,
## штуцер снизу, кабель вбок. Blind — без локального дисплея.
## Рентген: канал + камера мембраны; шток от мембраны к электронике двигается вместе с ней.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
const CsgBake = preload("res://scripts/view3d/csg_bake.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 18.0)
	var len_mm: float = maxf(float(el.stroke_mm), 60.0)
	var body_r: float = Parts.mm(od_mm * 0.5)
	var body_h: float = Parts.mm(len_mm * 0.55)
	var steel := Parts.mat("pt_steel", Color(0.72, 0.74, 0.76), 0.88, 0.28)
	var steel_dark := Parts.mat("pt_steel2", Color(0.55, 0.57, 0.6), 0.9, 0.32)
	var din := Parts.mat("pt_din", Color(0.08, 0.08, 0.1), 0.05, 0.72)
	var din_mark := Parts.mat("pt_din_m", Color(0.14, 0.14, 0.16), 0.08, 0.65)
	var screw_m := Parts.mat("pt_scr", Color(0.78, 0.8, 0.82), 0.85, 0.35)
	var cable_mat: Material = Parts.mat("pt_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)
	var mem_mat := Parts.mat("pt_mem", Color(0.78, 0.62, 0.28), 0.55, 0.42)
	var seat_mat := Parts.mat("pt_seat", Color(0.45, 0.47, 0.5), 0.75, 0.35)
	var stem_mat := Parts.mat("pt_stem", Color(0.58, 0.60, 0.64), 0.85, 0.32)

	# Корпус с каналом: ввод → камера мембраны → направляющая штока вверх.
	var seat_y: float = -body_h * 0.32
	_build_body_with_channel(parent, body_r, body_h, seat_y, steel)
	# Поясок сверху корпуса — непрозрачный (нет динамики).
	Parts.cyl(
		parent,
		body_r * 1.02,
		Parts.mm(3.0),
		Vector3(0.0, body_h * 0.42, 0.0),
		"y",
		steel_dark,
		16,
		"shell"
	)
	parent.set_meta("detect_material", "steel")

	# Внутренности: седло + мембрана + шток (дочерний к мембране → едет вместе).
	_build_internals(parent, body_r, body_h, seat_y, mem_mat, seat_mat, stem_mat)

	# DIN 43650 Form A — прямоугольная голова сверху (shell).
	var head_w: float = Parts.mm(maxf(od_mm * 1.35, 28.0))
	var head_h: float = Parts.mm(22.0)
	var head_d: float = Parts.mm(maxf(od_mm * 1.25, 26.0))
	var head_y: float = body_h * 0.5 + head_h * 0.5 - Parts.mm(1.0)
	Parts.box(parent, Vector3(head_w, head_h, head_d), Vector3(0.0, head_y, 0.0), din, "shell")
	Parts.box(
		parent,
		Vector3(head_w * 0.72, head_h * 0.55, Parts.mm(0.8)),
		Vector3(0.0, head_y + Parts.mm(1.0), head_d * 0.5 + Parts.mm(0.2)),
		din_mark,
		"shell"
	)
	Parts.cyl(
		parent,
		Parts.mm(2.2),
		Parts.mm(4.0),
		Vector3(0.0, head_y + head_h * 0.5 + Parts.mm(1.5), 0.0),
		"y",
		screw_m,
		10,
		"control"
	)

	# Кабельный ввод / gland вбок (+X).
	var gland_x0: float = head_w * 0.5
	var gland_y: float = head_y
	Parts.cyl(
		parent,
		Parts.mm(5.5),
		Parts.mm(8.0),
		Vector3(gland_x0 + Parts.mm(4.0), gland_y, 0.0),
		"x",
		din,
		12,
		"shell"
	)
	Parts.cyl(
		parent,
		Parts.mm(4.2),
		Parts.mm(6.0),
		Vector3(gland_x0 + Parts.mm(11.0), gland_y, 0.0),
		"x",
		din,
		12,
		"shell"
	)
	var cable_r: float = Parts.mm(2.5)
	var cable_stub_l: float = Parts.mm(14.0)
	var cable_c: float = gland_x0 + Parts.mm(14.0) + cable_stub_l * 0.45
	Parts.cyl(parent, cable_r, cable_stub_l, Vector3(cable_c, gland_y, 0.0), "x", cable_mat, 12, "shell")
	var cable_tip := Vector3(gland_x0 + Parts.mm(14.0) + cable_stub_l * 0.95, gland_y, 0.0)
	Parts.cyl(
		parent, cable_r * 1.02, Parts.mm(1.2),
		cable_tip - Vector3(Parts.mm(0.4), 0.0, 0.0), "x", cable_mat, 14, "shell"
	)
	parent.set_meta("cable_exit_local", cable_tip)
	parent.set_meta("cable_exit_dir", Vector3.RIGHT)
	info["ports"]["+"] = cable_tip
	info["ports"]["OUT"] = cable_tip
	info["ports"]["0"] = cable_tip
	info["ports"]["-"] = cable_tip
	info["dirs"]["+"] = Vector3.RIGHT
	info["dirs"]["OUT"] = Vector3.RIGHT
	info["dirs"]["0"] = Vector3.RIGHT
	info["dirs"]["-"] = Vector3.RIGHT

	# Штуцер снизу — shell (не окно).
	var od: float = TubeFit.port_tube_od(el, "P")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.72
	var tip_p: Vector3 = Parts.add_fitting(
		parent,
		Vector3(0.0, -body_h * 0.5 - Parts.mm(1.0), 0.0),
		"-y",
		fit_scale,
		true
	)
	info["ports"]["P"] = tip_p
	info["dirs"]["P"] = Vector3.DOWN

	var led := MeshInstance3D.new()
	led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(1.6)
	sph.height = Parts.mm(3.2)
	led.mesh = sph
	led.position = Vector3(-head_w * 0.28, head_y + head_h * 0.15, head_d * 0.5 + Parts.mm(1.0))
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.25, 0.3, 0.12)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.08, 0.1, 0.03)
	led_mat.emission_energy_multiplier = 0.2
	led.material_override = led_mat
	led.set_meta("xray_role", "control")
	parent.add_child(led)

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 16
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.15, 0.17, 0.2)
	tag.position = Vector3(0.0, head_y + head_h * 0.5 + Parts.mm(12.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_pressure_tx", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-head_w * 0.7, tip_p.y - Parts.mm(8.0), -head_d * 0.7),
		Vector3(head_w * 1.4 + Parts.mm(36.0), body_h + head_h + Parts.mm(40.0), head_d * 1.4)
	))
	apply_led(parent, el)
	apply_membrane(parent, el, null)
	return info


## Цилиндр корпуса: вычитание вводного канала + камеры под мембрану.
static func _build_body_with_channel(
	parent: Node3D, body_r: float, body_h: float, seat_y: float, mat: Material
) -> void:
	var comb := CSGCombiner3D.new()
	comb.name = "BodyCSG"
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	comb.add_child(CsgBake.cyl(body_r, body_h, Vector3.ZERO, "y", UNION, 24))
	# Камера мембраны (шире ввода) — место посадки диска.
	var chamber_r: float = body_r * 0.82
	var chamber_bot: float = seat_y - Parts.mm(5.5)
	var chamber_top: float = seat_y + Parts.mm(7.0)
	var chamber_h: float = chamber_top - chamber_bot
	comb.add_child(CsgBake.cyl(
		chamber_r, chamber_h,
		Vector3(0.0, (chamber_top + chamber_bot) * 0.5, 0.0), "y", SUB, 20
	))
	# Узкий канал давления: от низа корпуса (к штуцеру) вверх в камеру.
	var bore_r: float = body_r * 0.30
	var inlet_bot: float = -body_h * 0.5 - Parts.mm(2.5)
	var inlet_top: float = chamber_bot + Parts.mm(1.5)
	var inlet_h: float = inlet_top - inlet_bot
	comb.add_child(CsgBake.cyl(
		bore_r, inlet_h,
		Vector3(0.0, (inlet_top + inlet_bot) * 0.5, 0.0), "y", SUB, 14
	))
	# Направляющая штока: от камеры вверх к зоне электроники / DIN.
	var guide_r: float = body_r * 0.20
	var guide_bot: float = chamber_top - Parts.mm(1.0)
	var guide_top: float = body_h * 0.40
	var guide_h: float = maxf(guide_top - guide_bot, Parts.mm(8.0))
	comb.add_child(CsgBake.cyl(
		guide_r, guide_h,
		Vector3(0.0, guide_bot + guide_h * 0.5, 0.0), "y", SUB, 12
	))
	CsgBake.attach(parent, comb, mat, "window")


static func _build_internals(
	parent: Node3D, body_r: float, body_h: float, seat_y: float,
	mem_mat: Material, seat_mat: Material, stem_mat: Material
) -> void:
	# Седло / опорное кольцо на дне камеры канала.
	Parts.cyl(
		parent,
		body_r * 0.78,
		Parts.mm(2.2),
		Vector3(0.0, seat_y - Parts.mm(1.2), 0.0),
		"y",
		seat_mat,
		16,
		"internal"
	)
	# Мембрана: плоский диск + «купол» изгиба — в камере канала.
	var mem := Node3D.new()
	mem.name = "Membrane"
	mem.position = Vector3(0.0, seat_y, 0.0)
	mem.set_meta("y0", seat_y)
	mem.set_meta("r0", body_r * 0.72)
	parent.add_child(mem)

	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = body_r * 0.72
	cyl.bottom_radius = body_r * 0.72
	cyl.height = Parts.mm(0.7)
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = mem_mat
	disc.set_meta("xray_role", "internal")
	mem.add_child(disc)

	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var sph := SphereMesh.new()
	sph.radius = body_r * 0.70
	sph.height = body_r * 1.40
	sph.radial_segments = 20
	sph.rings = 10
	dome.mesh = sph
	# Покой: почти плоский диск (сплющен по Y).
	dome.scale = Vector3(1.0, 0.10, 1.0)
	dome.position = Vector3(0.0, Parts.mm(0.2), 0.0)
	dome.material_override = mem_mat
	dome.set_meta("xray_role", "internal")
	mem.add_child(dome)

	# Неподвижный упор/сенсор вверху направляющей (корпус) — шток подходит при изгибе.
	var sense_y: float = body_h * 0.30
	var sense_h: float = Parts.mm(1.8)
	Parts.cyl(
		parent,
		body_r * 0.28,
		sense_h,
		Vector3(0.0, sense_y, 0.0),
		"y",
		Parts.mat("pt_sense", Color(0.32, 0.35, 0.40), 0.5, 0.48),
		12,
		"internal"
	)
	# Шток: от центра мембраны вверх к упору (ребёнок Membrane → lift общий).
	var stem_r: float = body_r * 0.12
	var pad_h: float = Parts.mm(2.0)
	var gap0: float = Parts.mm(2.2) # зазор покой мембрана→упор (закрывается lift≈1.2 мм)
	var stem_top_local: float = (sense_y - seat_y) - sense_h * 0.5 - gap0
	var stem_bot_local: float = Parts.mm(0.5)
	var stem_len: float = maxf(stem_top_local - stem_bot_local - pad_h, Parts.mm(10.0))
	var stem_y: float = stem_bot_local + stem_len * 0.5
	Parts.cyl(mem, stem_r, stem_len, Vector3(0.0, stem_y, 0.0), "y", stem_mat, 12, "internal")
	# Пята / толкатель на верхнем конце штока.
	var pad_y: float = stem_y + stem_len * 0.5 + pad_h * 0.5
	Parts.cyl(mem, stem_r * 2.4, pad_h, Vector3(0.0, pad_y, 0.0), "y", stem_mat, 12, "internal")


## t∈[0..1] по шкале диапазона → изгиб мембраны вверх в камеру.
static func apply_membrane(root: Node3D, el, circuit = null) -> void:
	if root == null or el == null:
		return
	var mem: Node3D = root.get_node_or_null("Membrane") as Node3D
	if mem == null:
		return
	var p_bar: float = 0.0
	if circuit != null:
		p_bar = SensorDetect.pressure_switch_line_bar(circuit, el)
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		pmax = pmin + 0.05
	var t: float = clampf((p_bar - pmin) / (pmax - pmin), 0.0, 1.0)
	var y0: float = float(mem.get_meta("y0", mem.position.y))
	# Центр чуть поднимается; купол раздувается (изгиб).
	var lift: float = Parts.mm(1.2) * t
	mem.position.y = y0 + lift
	var dome: Node3D = mem.get_node_or_null("Dome") as Node3D
	if dome != null:
		# 0.10 → ~0.55 по высоте сферы = заметный изгиб.
		var sy: float = 0.10 + t * 0.45
		dome.scale = Vector3(1.0, sy, 1.0)
		dome.position.y = Parts.mm(0.2) + Parts.mm(0.8) * t


static func apply_xray(root: Node3D, on: bool) -> void:
	Iso.apply_xray(root, on)


static func apply_led(root: Node3D, el) -> void:
	if root == null:
		return
	var led: MeshInstance3D = root.get_node_or_null("SensorLed") as MeshInstance3D
	if led == null:
		return
	var mat: StandardMaterial3D = led.material_override as StandardMaterial3D
	if mat == null:
		return
	var on: bool = bool(el.lit) or (bool(el.sensor_powered) and bool(el.sensor_active))
	if on:
		mat.albedo_color = Color(0.25, 0.95, 0.35)
		mat.emission = Color(0.2, 0.9, 0.3)
		mat.emission_energy_multiplier = 2.2
	else:
		mat.albedo_color = Color(0.25, 0.3, 0.12)
		mat.emission = Color(0.08, 0.1, 0.03)
		mat.emission_energy_multiplier = 0.2
