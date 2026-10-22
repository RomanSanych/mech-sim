class_name IsoValve
extends RefCounted
## 3D пневмораспределитель по обмерам Camozzi STEP.
## ЭМ = трубка+толкатель+гайка flush к корпусу; катушка только при связанном coil.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")


static func build(parent: Node3D, el, circuit = null) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var ways := int(el.valve_ways)
	var positions := int(el.valve_positions)
	# Корпус по Camozzi 338L STEP (body 32.3×48×22); длина растёт с ways/positions.
	var v338: Dictionary = Parts.dims().get("valve_338L_015_02", {})
	var body_bb = v338.get("body", [32.3, 48.0, 22.0])
	var body_h := Parts.mm(float(body_bb[0]))
	# STEP 22 мм по Z визуально узкий — +⅓ к ширине корпуса.
	var body_w := Parts.mm(float(body_bb[2])) * 1.35
	# +¼ к длине: STEP 48 мм по оси золотника визуально короткий на схеме/в цехе.
	var body_l := (
		Parts.mm(float(body_bb[1]))
		+ Parts.mm(12.0) * float(maxi(positions - 2, 0))
		+ Parts.mm(3.0) * float(maxi(ways - 5, 0))
	) * 1.25
	# Типоразмер порта: корпус чуть крупнее; штуцеры — заметно от thread/OD.
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var fit_thread: String = str(el.port_name)
	var fit_od: float = float(el.tube_od_mm)
	if fit_od < 1.0:
		fit_od = 6.0
	var fit_scale: float = TubeFit.fitting_scale(fit_thread, fit_od)
	# Чуть сильнее разница M5…G1/2, чтобы смена типоразмера читалась сразу.
	fit_scale = clampf(fit_scale * 1.08, 0.6, 2.4)
	var body_s: float = clampf(0.86 + 0.16 * fit_scale, 0.8, 1.35)
	body_l *= body_s
	body_h *= body_s
	body_w *= body_s
	var alum := Parts.alum()
	var alum_dark := Parts.alum_dark()
	var black := Parts.black()

	# Корпус над золотником — окно рентгена; крышка/лапы/бобышки остаются shell.
	Parts.box(parent, Vector3(body_l, body_h, body_w), Vector3.ZERO, alum, "window")
	Parts.box(parent, Vector3(body_l * 0.96, body_h * 0.1, body_w * 0.96), Vector3(0, body_h * 0.5 + body_h * 0.03, 0), alum, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(2.5), body_w * 0.7), Vector3(0, body_h * 0.5 + body_h * 0.08, -body_w * 0.04), alum_dark, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(3.0), body_w * 0.16), Vector3(0, -body_h * 0.5 - Parts.mm(1.0), body_w * 0.34), alum_dark, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(3.0), body_w * 0.16), Vector3(0, -body_h * 0.5 - Parts.mm(1.0), -body_w * 0.34), alum_dark, "shell")

	var boss_r: float = Parts.mm(6.5) * clampf(fit_scale, 0.7, 1.8)
	var boss_h: float = Parts.mm(2.5) * clampf(0.85 + 0.15 * fit_scale, 0.85, 1.4)
	for spec in _port_layout_3d(ways, body_l, body_h):
		var ox: float = spec["x"]
		var oy: float = spec["y"]
		var top: bool = bool(spec["top"])
		var boss := Vector3(ox, oy + (boss_h * 0.48 if top else -boss_h * 0.48), body_w * 0.08)
		Parts.cyl(parent, boss_r, boss_h, boss, ("y" if top else "-y"), alum_dark, 12, "shell")
		Parts.cyl(parent, boss_r * 0.69, boss_h * 0.48, boss + Vector3(0, (boss_h * 0.6 if top else -boss_h * 0.6), 0), ("y" if top else "-y"), black, 12, "shell")

	var spool := Node3D.new()
	spool.name = "Spool"
	spool.set_meta("body_l", body_l)
	parent.add_child(spool)
	_build_spool_internals(spool, el, ways, body_l, body_h)
	# Каналы портов → расточка (видны в X-ray); подсветка открытых — по клетке позиции.
	_build_port_galleries(parent, el, ways, body_l, body_h, body_w)

	_build_end_and_spring(parent, spool, el, true, -body_l * 0.5, body_l, body_h, body_w)
	_build_end_and_spring(parent, spool, el, false, body_l * 0.5, body_l, body_h, body_w)
	_update_spool(spool, el, body_l)
	_update_spring(parent, el, body_l)

	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var names: PackedStringArray = ValveCat.port_names(el)
	for spec in _port_layout_3d(ways, body_l, body_h):
		var name: String = str(spec["name"])
		if not names.has(name):
			continue
		var origin := Vector3(spec["x"], spec["y"], body_w * 0.08)
		var top: bool = bool(spec["top"])
		var axis := "y" if top else "-y"
		var tip: Vector3
		if ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler":
			Parts.add_silencer(parent, origin, axis, fit_scale * 0.95)
		else:
			tip = Parts.add_fitting(parent, origin, axis, fit_scale)
			info["ports"][name] = tip
			info["dirs"][name] = Vector3.UP if top else Vector3.DOWN

	_build_op(parent, spool, el, true, -body_l * 0.5, body_h, body_w, circuit, info)
	_build_op(parent, spool, el, false, body_l * 0.5, body_h, body_w, circuit, info)

	var label := Label3D.new()
	label.name = "Tag"
	label.text = el.tag
	label.font_size = 40
	label.pixel_size = 0.00048
	label.modulate = Color(0.12, 0.14, 0.16)
	label.outline_modulate = Color(0.9, 0.92, 0.94)
	label.outline_size = 4
	label.position = Vector3(0, body_h * 0.5 + Parts.mm(12.0), -body_w * 0.15)
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.visible = false # обозначение — во всплывающей подсказке
	parent.add_child(label)
	parent.set_meta("body_l", body_l)
	parent.set_meta("body_h", body_h)
	return info


static func _build_end_and_spring(parent: Node, spool: Node3D, el, left: bool, face_x: float, body_l: float, body_h: float, body_w: float) -> void:
	var op := str(el.op_left) if left else str(el.op_right)
	var sign := -1.0 if left else 1.0
	# Торцевая стенка flush с торцом корпуса.
	Parts.box(parent, Vector3(Parts.mm(3.5), body_h * 0.96, body_w * 0.96), Vector3(face_x + sign * Parts.mm(1.75), 0, 0), Parts.alum_dark(), "shell")
	if op != "spring":
		return
	var spring := Node3D.new()
	spring.name = "SpringL" if left else "SpringR"
	spring.set_meta("sign", sign)
	spring.set_meta("face_x", face_x)
	parent.add_child(spring)
	for _i in 7:
		Parts.cyl(spring, body_h * 0.16, Parts.mm(1.8), Vector3.ZERO, "x", Parts.steel(), 12, "internal")
	_layout_spring_coils(spring, 0.0, body_l, body_h)


static func _layout_spring_coils(spring: Node3D, spool_x: float, body_l: float, body_h: float) -> void:
	var sign: float = float(spring.get_meta("sign", 1.0))
	var face_x: float = float(spring.get_meta("face_x", 0.0))
	var wall_x := face_x - sign * Parts.mm(1.0)
	var spool_end := spool_x + sign * body_l * 0.28
	var x0 := minf(wall_x, spool_end)
	var x1 := maxf(wall_x, spool_end)
	var kids := spring.get_children()
	var n := kids.size()
	for i in n:
		var mi: Node = kids[i]
		if mi is MeshInstance3D:
			var t := (float(i) + 0.5) / float(n)
			mi.position = Vector3(lerpf(x0, x1, t), 0, 0)
			var mesh: CylinderMesh = (mi as MeshInstance3D).mesh
			if mesh:
				mesh.top_radius = body_h * (0.13 + 0.03 * sin(t * PI))
				mesh.bottom_radius = mesh.top_radius


static func _port_layout_3d(ways: int, body_l: float, body_h: float) -> Array:
	var y_top := body_h * 0.5
	var y_bot := -body_h * 0.5
	match ways:
		2:
			return [
				{"name": "1", "x": 0.0, "y": y_bot, "top": false},
				{"name": "2", "x": 0.0, "y": y_top, "top": true},
			]
		3:
			return [
				{"name": "1", "x": -body_l * 0.22, "y": y_bot, "top": false},
				{"name": "2", "x": -body_l * 0.22, "y": y_top, "top": true},
				{"name": "3", "x": body_l * 0.22, "y": y_bot, "top": false},
			]
		4:
			return [
				{"name": "1", "x": -body_l * 0.22, "y": y_bot, "top": false},
				{"name": "2", "x": -body_l * 0.22, "y": y_top, "top": true},
				{"name": "4", "x": body_l * 0.22, "y": y_top, "top": true},
				{"name": "3", "x": body_l * 0.22, "y": y_bot, "top": false},
			]
		_:
			return [
				{"name": "3", "x": -body_l * 0.32, "y": y_bot, "top": false},
				{"name": "1", "x": 0.0, "y": y_bot, "top": false},
				{"name": "5", "x": body_l * 0.32, "y": y_bot, "top": false},
				{"name": "2", "x": -body_l * 0.22, "y": y_top, "top": true},
				{"name": "4", "x": body_l * 0.22, "y": y_top, "top": true},
			]


static func update_spool(root: Node3D, el, with_flow_viz: bool = true) -> void:
	var spool := root.get_node_or_null("Spool")
	if spool == null:
		return
	var body_l := float(root.get_meta("body_l", 0.08))
	_update_spool(spool, el, body_l)
	_update_spring(root, el, body_l)
	if with_flow_viz:
		update_flow_viz(root, el)


## Золотник: вал + O-ring у каждого канала. Потоки — отдельным слоем FlowViz (не на золотнике).
static func _build_spool_internals(spool: Node3D, _el, ways: int, body_l: float, body_h: float) -> void:
	var spool_m := Parts.mat("cv_spool", Color(0.88, 0.89, 0.90), 0.95, 0.18)
	var rubber := Parts.rubber()
	var shaft_r := body_h * 0.15
	var land_r := body_h * 0.20
	var tube_r := body_h * 0.034
	Parts.cyl(spool, shaft_r, body_l * 0.74, Vector3.ZERO, "x", spool_m, 18, "internal")
	var xs: Array = []
	for spec in _port_layout_3d(ways, body_l, body_h):
		var x: float = float(spec["x"])
		var dup := false
		for ex in xs:
			if absf(float(ex) - x) < Parts.mm(0.25):
				dup = true
				break
		if not dup:
			xs.append(x)
	xs.sort()
	var land_h := Parts.mm(2.6)
	for i in xs.size():
		var x: float = float(xs[i])
		Parts.oring(spool, shaft_r, tube_r, Vector3(x, 0, 0), "x", rubber)
		# Пояски между каналами — постоянная геометрия золотника.
		if i + 1 < xs.size():
			var x2: float = float(xs[i + 1])
			var mid := (x + x2) * 0.5
			var gap := absf(x2 - x)
			if gap > Parts.mm(4.0):
				Parts.cyl(spool, land_r, gap * 0.35, Vector3(mid, 0, 0), "x", spool_m, 14, "internal")


static func _update_spool(spool: Node3D, el, body_l: float) -> void:
	var positions := maxi(int(el.valve_positions), 2)
	var pos := clampi(int(el.valve_pos), 0, positions - 1)
	var t := float(pos) / float(positions - 1) if positions > 1 else 0.0
	# Правый орган (14) толкает золотник влево — как сдвиг клеток УГО при активной правой клетке.
	spool.position.x = lerpf(body_l * 0.1, -body_l * 0.1, t)


static func _update_spring(root: Node3D, el, body_l: float) -> void:
	var spool := root.get_node_or_null("Spool")
	if spool == null:
		return
	var body_h := float(root.get_meta("body_h", Parts.mm(32.0)))
	for name in ["SpringL", "SpringR"]:
		var spring := root.get_node_or_null(name)
		if spring:
			_layout_spring_coils(spring, spool.position.x, body_l, body_h)


static func _build_port_galleries(parent: Node, _el, ways: int, body_l: float, body_h: float, body_w: float) -> void:
	var fold := Node3D.new()
	fold.name = "Galleries"
	parent.add_child(fold)
	var bore_r := body_h * 0.24
	for spec in _port_layout_3d(ways, body_l, body_h):
		var ox: float = spec["x"]
		var oy: float = spec["y"]
		var top: bool = bool(spec["top"])
		var axis := "y" if top else "-y"
		var len := absf(oy) - bore_r * 0.35
		if len < Parts.mm(2.0):
			continue
		var mid_y := oy * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.55, 0.62, 0.35)
		mat.metallic = 0.05
		mat.roughness = 0.4
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.25, 0.3)
		mat.emission_energy_multiplier = 0.15
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = Parts.mm(2.2)
		mesh.bottom_radius = Parts.mm(2.2)
		mesh.height = len
		mesh.radial_segments = 10
		mi.mesh = mesh
		mi.position = Vector3(ox, mid_y, body_w * 0.08)
		mi.material_override = mat
		mi.set_meta("xray_role", "internal")
		mi.set_meta("port_name", str(spec["name"]))
		mi.name = "Gal_%s" % str(spec["name"])
		Parts._orient(mi, axis)
		fold.add_child(mi)
	var bridges := Node3D.new()
	bridges.name = "FlowBridges"
	parent.add_child(bridges)
	parent.set_meta("body_l", body_l)
	parent.set_meta("body_h", body_h)
	parent.set_meta("body_w", body_w)


## Подсветка каналов и мостиков по давлению/открытым путям (каждый кадр в x-ray).
static func update_flow_viz(root: Node3D, el) -> void:
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var gals := root.get_node_or_null("Galleries")
	if gals == null:
		return
	var pairs: Array = ValveLib.path_pairs_from_spool(el, int(el.valve_pos))
	var open_ports := {}
	for pair in pairs:
		if pair is Array and pair.size() >= 2:
			open_ports[str(pair[0])] = true
			open_ports[str(pair[1])] = true
	for child in gals.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		var pname := str(mi.get_meta("port_name", ""))
		var p := float(el.port_press.get(pname, 101325.0))
		var gauge := clampf((p - 101325.0) / 6.0e5, 0.0, 1.0)
		var q := float(el.port_q.get(pname, 0.0)) if el.get("port_q") != null else 0.0
		var exhausting := ValveCat.is_exhaust_port(pname) and q < -1.0e-6
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		if exhausting:
			# Выхлоп в атмосферу — тот же голубой поток.
			mat.albedo_color = Color(0.2, 0.75, 1.0, 0.75)
			mat.emission = Color(0.15, 0.65, 1.0)
			mat.emission_energy_multiplier = 0.9
		elif open_ports.has(pname) and gauge > 0.05:
			# Открытый канал под давлением — холодный голубой.
			mat.albedo_color = Color(0.2, 0.75, 1.0, 0.55 + gauge * 0.35)
			mat.emission = Color(0.15, 0.65, 1.0)
			mat.emission_energy_multiplier = 0.4 + gauge * 0.9
		elif open_ports.has(pname):
			# Открыт, но без давления (связь с атмосферой / пусто).
			mat.albedo_color = Color(0.35, 0.7, 0.55, 0.45)
			mat.emission = Color(0.2, 0.55, 0.4)
			mat.emission_energy_multiplier = 0.35
		else:
			mat.albedo_color = Color(0.42, 0.48, 0.52, 0.22)
			mat.emission = Color(0.2, 0.22, 0.25)
			mat.emission_energy_multiplier = 0.08
	_sync_flow_bridges(root, el, pairs)


static func _sync_flow_bridges(root: Node3D, el, pairs: Array) -> void:
	var bridges := root.get_node_or_null("FlowBridges")
	if bridges == null:
		return
	var body_l := float(root.get_meta("body_l", 0.08))
	var body_h := float(root.get_meta("body_h", 0.032))
	var body_w := float(root.get_meta("body_w", 0.03))
	var ways := int(el.valve_ways)
	var sig_parts: PackedStringArray = []
	for pair in pairs:
		if pair is Array and pair.size() >= 2:
			sig_parts.append("%s-%s" % [str(pair[0]), str(pair[1])])
	sig_parts.sort()
	var pair_sig := "%d|%s" % [int(el.valve_pos), ",".join(sig_parts)]
	var need_rebuild: bool = str(bridges.get_meta("pair_sig", "")) != pair_sig
	if need_rebuild:
		while bridges.get_child_count() > 0:
			var old := bridges.get_child(0)
			bridges.remove_child(old)
			old.queue_free()
		bridges.set_meta("pair_sig", pair_sig)
		var port_x := {}
		var port_y := {}
		for spec in _port_layout_3d(ways, body_l, body_h):
			port_x[str(spec["name"])] = float(spec["x"])
			port_y[str(spec["name"])] = float(spec["y"]) * 0.15
		for pair in pairs:
			if not (pair is Array) or pair.size() < 2:
				continue
			var a := str(pair[0])
			var b := str(pair[1])
			if not port_x.has(a) or not port_x.has(b):
				continue
			var xa: float = float(port_x[a])
			var xb: float = float(port_x[b])
			var ya: float = float(port_y.get(a, 0.0))
			var yb: float = float(port_y.get(b, 0.0))
			var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5, body_w * 0.08)
			var span := Vector2(xb - xa, yb - ya).length()
			if span < Parts.mm(1.0):
				continue
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			var mi := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = Parts.mm(1.6)
			mesh.bottom_radius = Parts.mm(1.6)
			mesh.height = span * 0.92
			mesh.radial_segments = 8
			mi.mesh = mesh
			mi.position = mid
			mi.material_override = mat
			mi.set_meta("xray_role", "internal")
			mi.set_meta("flow_pair", "%s-%s" % [a, b])
			mi.set_meta("port_a", a)
			mi.set_meta("port_b", b)
			bridges.add_child(mi)
			var dir := Vector3(xb - xa, yb - ya, 0.0)
			if dir.length_squared() > 1.0e-10:
				mi.look_at(mi.global_position + dir.normalized(), Vector3.BACK)
				mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Только цвета — каждый кадр, без пересоздания мешей.
	for child in bridges.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi2 := child as MeshInstance3D
		var a2 := str(mi2.get_meta("port_a", ""))
		var b2 := str(mi2.get_meta("port_b", ""))
		var pa := float(el.port_press.get(a2, 101325.0))
		var pb := float(el.port_press.get(b2, 101325.0))
		var hot := maxf(pa, pb)
		var gauge := clampf((hot - 101325.0) / 6.0e5, 0.0, 1.0)
		var mat2 := mi2.material_override as StandardMaterial3D
		if mat2 == null:
			continue
		var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
		var exh := ValveCat.is_exhaust_port(a2) or ValveCat.is_exhaust_port(b2)
		if exh and gauge < 0.08:
			mat2.albedo_color = Color(0.95, 0.5, 0.18, 0.4)
			mat2.emission = Color(1.0, 0.45, 0.12)
			mat2.emission_energy_multiplier = 0.55
		else:
			mat2.albedo_color = Color(0.2, 0.85, 1.0, 0.35 + gauge * 0.4)
			mat2.emission = Color(0.2, 0.8, 1.0)
			mat2.emission_energy_multiplier = 0.5 + gauge * 0.8


static func _has_override(el, left: bool) -> bool:
	if left:
		return bool(el.get("override_left") if el.get("override_left") != null else true)
	return bool(el.get("override_right") if el.get("override_right") != null else true)


static func _build_op(parent: Node, spool: Node3D, el, left: bool, face_x: float, body_h: float, body_w: float, circuit = null, info: Dictionary = {}) -> void:
	var op := str(el.op_left) if left else str(el.op_right)
	var sign := -1.0 if left else 1.0
	var axis := "x" if sign > 0.0 else "-x"
	match op:
		"solenoid", "solenoid_pilot":
			var pilot_on_tube := op == "solenoid_pilot"
			var tip: Vector3 = Parts.add_armature_tube(parent, face_x, sign, body_h, spool, left, pilot_on_tube)
			if pilot_on_tube:
				Parts.box(parent, Vector3(Parts.mm(8.0), body_h * 0.55, body_w * 0.7), Vector3(face_x + sign * Parts.mm(4.0), body_h * 0.08, 0), Parts.alum(), "shell")
				var pname := "12" if left else "14"
				info["ports"][pname] = tip
				info["dirs"][pname] = Vector3.LEFT if left else Vector3.RIGHT
			if _has_override(el, left):
				Parts.add_body_override_button(parent, face_x, sign, body_h, body_w, left)
			if _has_linked_coil(circuit, el, left):
				Parts.add_coil_on_tube(parent, face_x, sign, body_h)
		"spring":
			pass
		"pilot":
			Parts.add_pilot_cap(parent, face_x, sign)
			var pn := "12" if left else "14"
			info["ports"][pn] = Vector3(face_x + sign * Parts.mm(14.0), 0, 0)
			info["dirs"][pn] = Vector3.LEFT if left else Vector3.RIGHT
		"button":
			Parts.add_side_button(parent, face_x, sign, spool, left)
		"plunger":
			Parts.add_side_plunger(parent, face_x, sign, spool, left)
		"roller":
			Parts.add_side_roller(parent, face_x, sign, spool, left)
		_:
			pass


static func _has_linked_coil(circuit, el, left: bool) -> bool:
	if circuit == null or el == null:
		return false
	var base := str(el.tag)
	var exact := base + ("L" if left else "R")
	for other in circuit.elements:
		var kind := str(other.kind)
		if kind != "coil" and not (kind == "electro" and str(other.electro_class) == "solenoid_coil"):
			continue
		if str(other.tag) == exact:
			return true
		if kind == "electro" and str(other.linked_valve_side) == ("L" if left else "R"):
			# Привязка по стороне без точного тега.
			if str(other.tag).begins_with(base):
				return true
	return false


## Мин. зазор между торцом корпуса и ближайшим mesh ЭМ (для self_test), м.
static func armature_gap_m(root: Node3D, left: bool) -> float:
	var body_l := float(root.get_meta("body_l", 0.08))
	var face := -body_l * 0.5 if left else body_l * 0.5
	var sign := -1.0 if left else 1.0
	var best := 1.0
	for child in root.get_children():
		if child is MeshInstance3D:
			var x: float = (child as MeshInstance3D).position.x
			# Снаружи от торца.
			var outward := (x - face) * sign
			if outward > 0.0 and outward < best:
				best = outward
	return best if best < 1.0 else 0.0
