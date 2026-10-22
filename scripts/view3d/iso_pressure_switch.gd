class_name IsoPressureSwitch
extends RefCounted
## 3D реле давления B1: корпус без показывающей шкалы текущего P;
## два винта (уставка / гистерезис) + указатели на шкалах настройки; LED; штуцер; кабель.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 30.0)
	var s: float = od_mm / 40.0
	var body_w: float = Parts.mm(42.0) * s
	var body_h: float = Parts.mm(52.0) * s
	var body_d: float = Parts.mm(36.0) * s
	var shell := Parts.mat("ps_shell", Color(0.82, 0.84, 0.86), 0.12, 0.55)
	var metal := Parts.mat("ps_metal", Color(0.72, 0.74, 0.76), 0.85, 0.3)
	var dark := Parts.mat("ps_dark", Color(0.18, 0.2, 0.22), 0.15, 0.6)
	var red_m := Parts.mat("ps_ptr", Color(0.85, 0.12, 0.1), 0.2, 0.45)
	var window_m := Parts.mat("ps_win", Color(0.55, 0.72, 0.78, 0.35), 0.05, 0.2)
	if window_m is StandardMaterial3D:
		(window_m as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var label_m := Parts.mat("ps_label", Color(0.96, 0.96, 0.97), 0.08, 0.7)
	var cable_mat: Material = Parts.mat("ps_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)

	Parts.box(parent, Vector3(body_w, body_h, body_d), Vector3.ZERO, shell, "shell")
	Parts.box(
		parent,
		Vector3(body_w * 1.02, Parts.mm(4.0) * s, body_d * 1.05),
		Vector3(0.0, -body_h * 0.5 - Parts.mm(1.5) * s, 0.0),
		metal,
		"shell"
	)

	# Окно шкал настройки (уставка слева, дифференциал справа).
	var win_z: float = body_d * 0.5 + Parts.mm(0.4) * s
	var scale_h: float = body_h * 0.34
	var scale_y0: float = -scale_h * 0.5 + body_h * 0.02
	Parts.box(
		parent,
		Vector3(body_w * 0.32, body_h * 0.46, Parts.mm(1.2) * s),
		Vector3(-body_w * 0.22, body_h * 0.02, win_z),
		window_m,
		"control"
	)
	# Направляющие шкал.
	var set_x: float = -body_w * 0.30
	var hyst_x: float = -body_w * 0.14
	Parts.box(
		parent,
		Vector3(Parts.mm(1.1) * s, scale_h, Parts.mm(0.5) * s),
		Vector3(set_x, body_h * 0.02, win_z + Parts.mm(0.5) * s),
		dark,
		"control"
	)
	Parts.box(
		parent,
		Vector3(Parts.mm(1.1) * s, scale_h * 0.85, Parts.mm(0.5) * s),
		Vector3(hyst_x, body_h * 0.02, win_z + Parts.mm(0.5) * s),
		dark,
		"control"
	)
	# Риски шкалы уставки (5 делений).
	for i in 5:
		var t: float = float(i) / 4.0
		var ry: float = scale_y0 + t * scale_h
		Parts.box(
			parent,
			Vector3(Parts.mm(3.2) * s, Parts.mm(0.45) * s, Parts.mm(0.4) * s),
			Vector3(set_x - Parts.mm(2.2) * s, ry, win_z + Parts.mm(0.55) * s),
			dark,
			"control"
		)
	# Риски дифференциала (4 деления).
	for j in 4:
		var t2: float = float(j) / 3.0
		var ry2: float = scale_y0 + t2 * scale_h * 0.85
		Parts.box(
			parent,
			Vector3(Parts.mm(2.6) * s, Parts.mm(0.4) * s, Parts.mm(0.4) * s),
			Vector3(hyst_x + Parts.mm(2.0) * s, ry2, win_z + Parts.mm(0.55) * s),
			dark,
			"control"
		)

	# Указатели (красные) — ездят по шкалам в apply_adjustments.
	var ptr_set := Node3D.new()
	ptr_set.name = "SetPointer"
	ptr_set.position = Vector3(set_x + Parts.mm(2.5) * s, body_h * 0.02, win_z + Parts.mm(0.9) * s)
	parent.add_child(ptr_set)
	Parts.box(
		ptr_set,
		Vector3(Parts.mm(4.5) * s, Parts.mm(1.2) * s, Parts.mm(0.7) * s),
		Vector3.ZERO,
		red_m,
		"control"
	)
	ptr_set.set_meta("scale_y0", scale_y0)
	ptr_set.set_meta("scale_h", scale_h)

	var ptr_hyst := Node3D.new()
	ptr_hyst.name = "HystPointer"
	ptr_hyst.position = Vector3(hyst_x - Parts.mm(2.2) * s, body_h * 0.02, win_z + Parts.mm(0.9) * s)
	parent.add_child(ptr_hyst)
	Parts.box(
		ptr_hyst,
		Vector3(Parts.mm(3.8) * s, Parts.mm(1.1) * s, Parts.mm(0.7) * s),
		Vector3.ZERO,
		red_m,
		"control"
	)
	ptr_hyst.set_meta("scale_y0", scale_y0)
	ptr_hyst.set_meta("scale_h", scale_h * 0.85)

	Parts.box(
		parent,
		Vector3(body_w * 0.32, body_h * 0.28, Parts.mm(0.8) * s),
		Vector3(body_w * 0.2, body_h * 0.08, body_d * 0.5 + Parts.mm(0.3) * s),
		label_m,
		"shell"
	)

	# Винты: слева уставка (SetScrew), справа гистерезис (HystScrew).
	var screw_y: float = body_h * 0.5 + Parts.mm(1.5) * s
	_add_adj_screw(parent, "SetScrew", Vector3(-body_w * 0.18, screw_y, 0.0), s, metal, dark)
	_add_adj_screw(parent, "HystScrew", Vector3(body_w * 0.12, screw_y, 0.0), s, metal, dark)
	parent.set_meta("ps_scale_s", s)

	parent.set_meta("detect_material", "plastic")

	var od: float = TubeFit.port_tube_od(el, "P")
	if od < 1.0:
		od = 6.0
	var thread: String = str(el.port_name) if str(el.port_name) != "" else TubeFit.thread_for_tube_od(od)
	var fit_scale: float = TubeFit.fitting_scale(thread, od) * 0.7
	var tip_p: Vector3 = Parts.add_fitting(
		parent,
		Vector3(0.0, -body_h * 0.5 - Parts.mm(2.0) * s, 0.0),
		"-y",
		fit_scale,
		true
	)
	info["ports"]["P"] = tip_p
	info["dirs"]["P"] = Vector3.DOWN

	var cable_r: float = Parts.mm(2.4)
	var cable_stub_l: float = Parts.mm(14.0)
	var x_rear0: float = -body_w * 0.5
	var cable_c: float = x_rear0 - cable_stub_l * 0.45
	Parts.cyl(parent, cable_r, cable_stub_l, Vector3(cable_c, body_h * 0.15, 0.0), "x", cable_mat, 12, "shell")
	var cable_tip := Vector3(x_rear0 - cable_stub_l * 0.95, body_h * 0.15, 0.0)
	Parts.cyl(parent, cable_r * 1.02, Parts.mm(1.2), cable_tip + Vector3(Parts.mm(0.4), 0.0, 0.0), "x", cable_mat, 14, "shell")
	parent.set_meta("cable_exit_local", cable_tip)
	parent.set_meta("cable_exit_dir", Vector3.LEFT)
	info["ports"]["OUT"] = cable_tip
	info["ports"]["0"] = cable_tip
	info["ports"]["1"] = cable_tip
	info["ports"]["2"] = cable_tip
	info["dirs"]["OUT"] = Vector3.LEFT
	info["dirs"]["0"] = Vector3.LEFT
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.LEFT

	var led := MeshInstance3D.new()
	led.name = "SensorLed"
	var sph := SphereMesh.new()
	sph.radius = Parts.mm(2.0) * s
	sph.height = Parts.mm(4.0) * s
	led.mesh = sph
	led.position = Vector3(body_w * 0.28, body_h * 0.32, body_d * 0.5 + Parts.mm(1.0) * s)
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.35, 0.08, 0.08)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.15, 0.02, 0.02)
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
	tag.position = Vector3(0.0, body_h * 0.5 + Parts.mm(14.0) * s, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_pressure_switch", true)
	parent.set_meta("seat_aabb", AABB(
		Vector3(x_rear0 - Parts.mm(16.0), -body_h * 0.5 - Parts.mm(28.0) * s, -body_d * 0.6),
		Vector3(body_w + Parts.mm(30.0), body_h + Parts.mm(40.0) * s, body_d * 1.2)
	))
	apply_led(parent, el)
	apply_adjustments(parent, el)
	return info


static func _add_adj_screw(
	parent: Node3D, screw_name: String, center: Vector3, s: float, metal: Material, dark: Material
) -> void:
	var screw := Node3D.new()
	screw.name = screw_name
	screw.position = center
	parent.add_child(screw)
	Parts.cyl(screw, Parts.mm(3.4) * s, Parts.mm(7.0) * s, Vector3.ZERO, "y", metal, 10, "control")
	Parts.cyl(
		screw, Parts.mm(4.2) * s, Parts.mm(1.6) * s,
		Vector3(0.0, Parts.mm(3.2) * s, 0.0), "y", metal, 8, "control"
	)
	Parts.box(
		screw,
		Vector3(Parts.mm(5.0) * s, Parts.mm(0.55) * s, Parts.mm(0.9) * s),
		Vector3(0.0, Parts.mm(3.9) * s, 0.0),
		dark,
		"control"
	)
	screw.set_meta("ps_adj_screw", true)
	screw.set_meta("ps_adj_role", "set" if screw_name == "SetScrew" else "hyst")


## Норма уставки 0…1 в диапазоне каталога.
static func set_norm(el) -> float:
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		pmax = pmin + 0.05
	return clampf((float(el.set_pressure_bar) - pmin) / (pmax - pmin), 0.0, 1.0)


## Норма гистерезиса 0…1 по фиксированной шкале дифференциала (не зависит от уставки).
static func hyst_norm(el) -> float:
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	var hmax: float = maxf(pmax - pmin, 0.05)
	var hmin: float = 0.02
	return clampf((float(el.hysteresis_bar) - hmin) / (hmax - hmin), 0.0, 1.0)


static func apply_adjustments(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var sn: float = set_norm(el)
	var hn: float = hyst_norm(el)
	var set_sc: Node3D = root.get_node_or_null("SetScrew") as Node3D
	if set_sc != null:
		# Поворот винта ~ 270° по шкале.
		set_sc.rotation_degrees = Vector3(0.0, sn * 270.0, 0.0)
	var hyst_sc: Node3D = root.get_node_or_null("HystScrew") as Node3D
	if hyst_sc != null:
		hyst_sc.rotation_degrees = Vector3(0.0, hn * 270.0, 0.0)
	var ptr_s: Node3D = root.get_node_or_null("SetPointer") as Node3D
	if ptr_s != null:
		var y0s: float = float(ptr_s.get_meta("scale_y0", 0.0))
		var hs: float = float(ptr_s.get_meta("scale_h", 0.02))
		ptr_s.position.y = y0s + sn * hs
	var ptr_h: Node3D = root.get_node_or_null("HystPointer") as Node3D
	if ptr_h != null:
		var y0h: float = float(ptr_h.get_meta("scale_y0", 0.0))
		var hh: float = float(ptr_h.get_meta("scale_h", 0.02))
		ptr_h.position.y = y0h + hn * hh


static func apply_led(root: Node3D, el) -> void:
	if root == null:
		return
	var led: MeshInstance3D = root.get_node_or_null("SensorLed") as MeshInstance3D
	if led == null:
		return
	var mat: StandardMaterial3D = led.material_override as StandardMaterial3D
	if mat == null:
		return
	var on: bool = bool(el.lit) or bool(el.pressed)
	if on:
		mat.albedo_color = Color(0.95, 0.2, 0.12)
		mat.emission = Color(0.95, 0.25, 0.1)
		mat.emission_energy_multiplier = 2.4
	else:
		mat.albedo_color = Color(0.35, 0.08, 0.08)
		mat.emission = Color(0.15, 0.02, 0.02)
		mat.emission_energy_multiplier = 0.2


## Изменить уставку/гистерезис от жеста мыши (d_ang > 0 = выше).
static func nudge_from_drag(el, role: String, d_ang: float) -> void:
	if el == null:
		return
	var pmin: float = float(el.sense_min_mm)
	var pmax: float = float(el.sense_range_mm)
	if pmax < pmin + 0.05:
		pmax = pmin + 0.05
	var hmax: float = maxf(pmax - pmin, 0.05)
	if role == "hyst":
		# Шкала дифференциала независима от уставки (как в свойствах / каталоге).
		el.hysteresis_bar = clampf(float(el.hysteresis_bar) + d_ang * 0.012, 0.02, hmax)
	else:
		el.set_pressure_bar = clampf(float(el.set_pressure_bar) + d_ang * 0.018, pmin, pmax)
		# Значение гистерезиса не трогаем — иначе засечка «едет» вместе с уставкой.
