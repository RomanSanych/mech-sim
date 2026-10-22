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
	# Корпус + начинка с типоразмером почти как штуцер (иначе глушители сталкиваются).
	var body_s: float = clampf(fit_scale, 0.72, 2.0)
	body_l *= body_s
	body_h *= body_s
	body_w *= body_s
	var alum := Parts.alum()
	var alum_dark := Parts.alum_dark()
	var black := Parts.black()

	# Корпус над золотником — окно рентгена; крышка/лапы/бобышки остаются shell.
	Parts.box(parent, Vector3(body_l, body_h, body_w), Vector3.ZERO, alum, "window")
	Parts.box(parent, Vector3(body_l * 0.96, body_h * 0.1, body_w * 0.96), Vector3(0, body_h * 0.5 + body_h * 0.03, 0), alum, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(2.5) * body_s, body_w * 0.7), Vector3(0, body_h * 0.5 + body_h * 0.08, -body_w * 0.04), alum_dark, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(3.0) * body_s, body_w * 0.16), Vector3(0, -body_h * 0.5 - Parts.mm(1.0) * body_s, body_w * 0.34), alum_dark, "shell")
	Parts.box(parent, Vector3(body_l * 0.9, Parts.mm(3.0) * body_s, body_w * 0.16), Vector3(0, -body_h * 0.5 - Parts.mm(1.0) * body_s, -body_w * 0.34), alum_dark, "shell")

	var boss_r: float = Parts.mm(6.5) * body_s
	var boss_h: float = Parts.mm(2.5) * body_s
	for spec in _port_layout_3d(ways, body_l, body_h):
		var ox: float = spec["x"]
		var oy: float = spec["y"]
		var top: bool = bool(spec["top"])
		var boss := Vector3(ox, oy + (boss_h * 0.48 if top else -boss_h * 0.48), body_w * 0.08)
		Parts.cyl(parent, boss_r, boss_h, boss, ("y" if top else "-y"), alum_dark, 12, "shell")
		Parts.cyl(parent, boss_r * 0.69, boss_h * 0.48, boss + Vector3(0, (boss_h * 0.6 if top else -boss_h * 0.6), 0), ("y" if top else "-y"), black, 12, "shell")

	var pitch: float = _port_pitch(body_l)
	parent.set_meta("spool_pitch", pitch)
	var spool := Node3D.new()
	spool.name = "Spool"
	spool.set_meta("body_l", body_l)
	spool.set_meta("spool_pitch", pitch)
	parent.add_child(spool)
	_build_spool_internals(spool, el, ways, body_l, body_h, pitch, body_s)
	# Каналы портов → расточка (видны в X-ray); подсветка открытых — по клетке позиции.
	_build_port_galleries(parent, el, ways, body_l, body_h, body_w, body_s)

	_build_end_and_spring(parent, spool, el, true, -body_l * 0.5, body_l, body_h, body_w, body_s)
	_build_end_and_spring(parent, spool, el, false, body_l * 0.5, body_l, body_h, body_w, body_s)
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
		var dir3: Vector3 = Vector3.UP if top else Vector3.DOWN
		if ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler":
			# Торец глушителя — точка выхлопа для конусов потока (не точка трубки).
			tip = Parts.add_silencer(parent, origin, axis, fit_scale * 0.95)
		else:
			tip = Parts.add_fitting(parent, origin, axis, fit_scale)
		info["ports"][name] = tip
		info["dirs"][name] = dir3

	_build_op(parent, spool, el, true, -body_l * 0.5, body_h, body_w, body_s, circuit, info)
	_build_op(parent, spool, el, false, body_l * 0.5, body_h, body_w, body_s, circuit, info)

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
	parent.set_meta("body_s", body_s)
	return info


static func _build_end_and_spring(
	parent: Node, spool: Node3D, el, left: bool, face_x: float,
	body_l: float, body_h: float, body_w: float, body_s: float
) -> void:
	var op := str(el.op_left) if left else str(el.op_right)
	var sign := -1.0 if left else 1.0
	# Торцевая стенка чуть снаружи корпуса — без z-fight с торцом window.
	var wall_t: float = Parts.mm(3.5) * body_s
	Parts.box(
		parent,
		Vector3(wall_t, body_h * 0.96, body_w * 0.96),
		Vector3(face_x + sign * (wall_t * 0.5 + Parts.mm(0.2) * body_s), 0, 0),
		Parts.alum_dark(),
		"shell"
	)
	if op != "spring":
		return
	var spring := Node3D.new()
	spring.name = "SpringL" if left else "SpringR"
	spring.set_meta("sign", sign)
	spring.set_meta("face_x", face_x)
	parent.add_child(spring)
	for _i in 7:
		Parts.cyl(spring, body_h * 0.16, Parts.mm(1.8) * body_s, Vector3.ZERO, "x", Parts.steel(), 12, "internal")
	_layout_spring_coils(spring, 0.0, body_l, body_h)


static func _layout_spring_coils(spring: Node3D, spool_x: float, body_l: float, body_h: float) -> void:
	var sign: float = float(spring.get_meta("sign", 1.0))
	var face_x: float = float(spring.get_meta("face_x", 0.0))
	# Стенка снаружи; торец золотника — ближе к центру (пружина на сжатие).
	var wall_x: float = face_x - sign * Parts.mm(1.0)
	var spool_end: float = spool_x + sign * body_l * 0.22
	# Не даём торцу уйти за стенку / «перетянуть» пружину.
	if sign > 0.0:
		spool_end = minf(spool_end, wall_x - Parts.mm(2.0))
	else:
		spool_end = maxf(spool_end, wall_x + Parts.mm(2.0))
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


static func _port_pitch(body_l: float) -> float:
	return body_l * 0.26


static func _port_layout_3d(ways: int, body_l: float, body_h: float) -> Array:
	var y_top := body_h * 0.5
	var y_bot := -body_h * 0.5
	var pitch: float = _port_pitch(body_l)
	match ways:
		2:
			return [
				{"name": "1", "x": -pitch * 0.35, "y": y_bot, "top": false},
				{"name": "2", "x": pitch * 0.35, "y": y_top, "top": true},
			]
		3:
			# Разнесённые станции: поясок может закрыть P, оставив A открытым.
			return [
				{"name": "1", "x": -pitch, "y": y_bot, "top": false},
				{"name": "2", "x": 0.0, "y": y_top, "top": true},
				{"name": "3", "x": pitch, "y": y_bot, "top": false},
			]
		4:
			return [
				{"name": "1", "x": -pitch, "y": y_bot, "top": false},
				{"name": "2", "x": -pitch * 0.35, "y": y_top, "top": true},
				{"name": "4", "x": pitch * 0.35, "y": y_top, "top": true},
				{"name": "3", "x": pitch, "y": y_bot, "top": false},
			]
		_:
			# 5/2…: 3|1|5 снизу, 2|4 сверху на полушаге.
			return [
				{"name": "3", "x": -pitch, "y": y_bot, "top": false},
				{"name": "1", "x": 0.0, "y": y_bot, "top": false},
				{"name": "5", "x": pitch, "y": y_bot, "top": false},
				{"name": "2", "x": -pitch * 0.5, "y": y_top, "top": true},
				{"name": "4", "x": pitch * 0.5, "y": y_top, "top": true},
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


## Пояски/проточки: закрытые каналы; ход должен сдвигать поясок с устья канала.
static func _build_spool_internals(
	spool: Node3D, el, ways: int, body_l: float, body_h: float, pitch: float, body_s: float
) -> void:
	var spool_m := Parts.mat("cv_spool", Color(0.88, 0.89, 0.90), 0.95, 0.18)
	var rubber := Parts.rubber()
	# Узкий вал + высокий поясок — в рентгене видна проточка и перекрытие устья.
	var shaft_r: float = body_h * 0.12
	var land_r: float = body_h * 0.26
	var tube_r: float = body_h * 0.026
	# Узже шага портов, иначе пояски сливаются и «всегда закрыто».
	var land_w: float = clampf(Parts.mm(5.5) * body_s, pitch * 0.22, pitch * 0.36)
	# Ход ≥ ширины пояска — при переключении устье гарантированно открывается.
	var max_travel: float = clampf(maxf(land_w * 1.05, pitch * 0.42), pitch * 0.32, body_l * 0.15)
	var shaft_len: float = body_l - 2.0 * max_travel - Parts.mm(3.0) * body_s
	shaft_len = clampf(shaft_len, body_l * 0.55, body_l * 0.82)
	Parts.cyl(spool, shaft_r, shaft_len, Vector3.ZERO, "x", spool_m, 18, "internal")
	var land_xs: Array = _spool_land_locals(el, ways, pitch, body_l, max_travel)
	var half_lim: float = body_l * 0.48
	for lx_v in land_xs:
		var lx: float = float(lx_v)
		if absf(lx) > half_lim:
			continue
		Parts.cyl(spool, land_r, land_w, Vector3(lx, 0, 0), "x", spool_m, 16, "internal")
		Parts.oring(spool, land_r * 0.92, tube_r, Vector3(lx - land_w * 0.38, 0, 0), "x", rubber)
		Parts.oring(spool, land_r * 0.92, tube_r, Vector3(lx + land_w * 0.38, 0, 0), "x", rubber)
	# Торцевые пояски — только если не сливаются с уплотнительными.
	var end_x: float = shaft_len * 0.47
	var end_w: float = land_w * 0.45
	for side in [-1.0, 1.0]:
		var ex: float = side * end_x
		var near_seal: bool = false
		for lx_v2 in land_xs:
			if absf(float(lx_v2) - ex) < land_w * 0.9:
				near_seal = true
				break
		if near_seal or absf(ex) > half_lim:
			continue
		Parts.cyl(spool, land_r * 0.92, end_w, Vector3(ex, 0, 0), "x", spool_m, 14, "internal")
	spool.set_meta("land_r", land_r)
	spool.set_meta("max_travel", max_travel)


## Пояски в локали покоя (spool.x=0); второй — под ход к пружине/от кнопки.
static func _spool_land_locals(
	el, ways: int, pitch: float, body_l: float, max_travel: float = -1.0
) -> Array:
	var port_x: Dictionary = _port_x_map(ways, body_l)
	var rest_i: int = clampi(int(el.rest_pos), 0, maxi(int(el.valve_positions) - 1, 0))
	if max_travel < 0.0:
		max_travel = minf(pitch * 0.42, body_l * 0.15)
	var lands: Array = []
	for pn in _closed_port_names(el, rest_i):
		if port_x.has(pn):
			lands.append(float(port_x[pn]))
	var npos: int = maxi(int(el.valve_positions), 1)
	for pi in npos:
		if pi == rest_i:
			continue
		var sx: float = _spool_x_for_pos(el, pi, pitch, body_l, max_travel)
		for pn in _closed_port_names(el, pi):
			if not port_x.has(pn):
				continue
			var local_x: float = float(port_x[pn]) - sx
			if _land_blocks_open_at_rest(local_x, el, rest_i, port_x, pitch):
				continue
			var dup := false
			for ex in lands:
				if absf(float(ex) - local_x) < pitch * 0.18:
					dup = true
					break
			if not dup:
				lands.append(local_x)
	if lands.is_empty():
		lands = [-pitch] if ways == 3 else [-pitch, pitch]
	return lands


static func _port_x_map(ways: int, body_l: float) -> Dictionary:
	var port_x: Dictionary = {}
	for spec in _port_layout_3d(ways, body_l, 0.03):
		port_x[str(spec["name"])] = float(spec["x"])
	return port_x


static func _land_blocks_open_at_rest(
	local_x: float, el, rest_i: int, port_x: Dictionary, pitch: float
) -> bool:
	var closed_rest: Array = _closed_port_names(el, rest_i)
	for pname in port_x.keys():
		var pn: String = str(pname)
		var is_rest_closed: bool = false
		for cr in closed_rest:
			if str(cr) == pn:
				is_rest_closed = true
				break
		if is_rest_closed:
			continue
		if absf(float(port_x[pn]) - local_x) < pitch * 0.28:
			return true
	return false


static func _closed_port_names(el, pos: int) -> Array:
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var pairs: Array = ValveLib.path_pairs_from_spool(el, pos)
	var open: Dictionary = {}
	for pair in pairs:
		if pair is Array and pair.size() >= 2:
			open[str(pair[0])] = true
			open[str(pair[1])] = true
	var closed: Array = []
	for pname in ValveCat.port_names(el):
		var n: String = str(pname)
		if not open.has(n):
			closed.append(n)
	return closed


static func _mean_closed_x(el, pos: int, port_x: Dictionary) -> float:
	var xs: Array = []
	for pn in _closed_port_names(el, pos):
		if port_x.has(pn):
			xs.append(float(port_x[pn]))
	if xs.is_empty():
		return 0.0
	var s: float = 0.0
	for v in xs:
		s += float(v)
	return s / float(xs.size())


## Направление хода от органа: левая кнопка/ЭМ толкает золотник в +X (к правой пружине).
## Правый орган толкает в −X. Пружина при этом сжимается, не растягивается.
static func _spool_push_dir(el) -> float:
	var ol: String = str(el.op_left)
	var orr: String = str(el.op_right)
	var left_drives: bool = ol != "spring" and ol != ""
	var right_drives: bool = orr != "spring" and orr != ""
	if left_drives and not right_drives:
		return 1.0
	if right_drives and not left_drives:
		return -1.0
	# Два органа / две пружины: меньший индекс клетки = сдвиг в +X (как кнопка слева).
	return 1.0


## Ось: 0 в rest; при уходе от покоя — в сторону нажатия органа (сжатие пружины).
static func _spool_x_for_pos(
	el, pos: int, pitch: float, body_l: float = -1.0, max_travel: float = -1.0
) -> float:
	var positions := maxi(int(el.valve_positions), 2)
	var rest_i: int = clampi(int(el.rest_pos), 0, positions - 1)
	pos = clampi(pos, 0, positions - 1)
	if pos == rest_i:
		return 0.0
	if body_l < 0.0:
		body_l = pitch / 0.26
	if max_travel < 0.0:
		max_travel = minf(pitch * 0.42, body_l * 0.15)
	var push: float = _spool_push_dir(el)
	if positions <= 2:
		var work_i: int = 0 if rest_i != 0 else 1
		var frac: float = float(pos - rest_i) / float(work_i - rest_i)
		return push * max_travel * clampf(absf(frac), 0.0, 1.0)
	# 5/3: клетка слева от покоя — как левый орган (+X); справа — как правый (−X).
	if pos < rest_i:
		return push * max_travel
	return -push * max_travel


static func _update_spool(spool: Node3D, el, body_l: float) -> void:
	var pitch: float = float(spool.get_meta("spool_pitch", _port_pitch(body_l)))
	var max_travel: float = float(spool.get_meta("max_travel", minf(pitch * 0.42, body_l * 0.15)))
	var x: float = _spool_x_for_pos(el, int(el.valve_pos), pitch, body_l, max_travel)
	spool.position.x = clampf(x, -max_travel, max_travel)


static func _update_spring(root: Node3D, el, body_l: float) -> void:
	var spool := root.get_node_or_null("Spool")
	if spool == null:
		return
	var body_h := float(root.get_meta("body_h", Parts.mm(32.0)))
	for name in ["SpringL", "SpringR"]:
		var spring := root.get_node_or_null(name)
		if spring:
			_layout_spring_coils(spring, spool.position.x, body_l, body_h)


static func _build_port_galleries(
	parent: Node, _el, ways: int, body_l: float, body_h: float, body_w: float, body_s: float
) -> void:
	var fold := Node3D.new()
	fold.name = "Galleries"
	parent.add_child(fold)
	# Устье у пояска (land_r≈0.26·h); канал тоньше проточки, чтобы кольцо читалось.
	var bore_r: float = body_h * 0.26
	var gal_r: float = minf(Parts.mm(2.0) * body_s, body_h * 0.045)
	# Ближе к оси золотника, чем бобышка — пересечение с пояском в рентгене.
	var gal_z: float = minf(body_w * 0.08, bore_r * 0.35)
	for spec in _port_layout_3d(ways, body_l, body_h):
		var ox: float = spec["x"]
		var oy: float = spec["y"]
		var top: bool = bool(spec["top"])
		var axis := "y" if top else "-y"
		var len := absf(oy) - bore_r * 0.35
		if len < Parts.mm(2.0) * body_s:
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
		mesh.top_radius = gal_r
		mesh.bottom_radius = gal_r
		mesh.height = len
		mesh.radial_segments = 10
		mi.mesh = mesh
		mi.position = Vector3(ox, mid_y, gal_z)
		mi.material_override = mat
		mi.set_meta("xray_role", "internal")
		mi.set_meta("flow_viz", true)
		mi.set_meta("port_name", str(spec["name"]))
		mi.set_meta("gal_len_full", len)
		mi.set_meta("gal_oy", oy)
		mi.set_meta("gal_top", top)
		mi.set_meta("gal_ox", ox)
		mi.set_meta("gal_z", gal_z)
		mi.set_meta("gal_land_r", bore_r)
		mi.name = "Gal_%s" % str(spec["name"])
		Parts._orient(mi, axis)
		fold.add_child(mi)
	var bridges := Node3D.new()
	bridges.name = "FlowBridges"
	parent.add_child(bridges)
	parent.set_meta("body_l", body_l)
	parent.set_meta("body_h", body_h)
	parent.set_meta("body_w", body_w)


## Подсветка каналов и мостиков: дискретные состояния (без дрожания от шума P/Q).
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
		if not bool(mi.get_meta("flow_viz", false)):
			mi.set_meta("flow_viz", true)
		var pname := str(mi.get_meta("port_name", ""))
		var is_open: bool = open_ports.has(pname)
		var is_exh_port: bool = ValveCat.is_exhaust_port(pname)
		var p := float(el.port_press.get(pname, 101325.0))
		var gauge := clampf((p - 101325.0) / 6.0e5, 0.0, 1.0)
		var q := float(el.port_q.get(pname, 0.0)) if el.get("port_q") != null else 0.0
		var was_flow: bool = bool(mi.get_meta("flow_active", false))
		# Поток наружу (выхлоп) или заметный ΔP — как у рабочих 1/2.
		var flowing: bool = false
		if is_exh_port:
			flowing = (q < -8.0e-6 or gauge >= 0.08) if not was_flow else (q < -1.0e-7 or gauge >= 0.04)
		else:
			flowing = gauge >= 0.12 if not was_flow else gauge >= 0.06
		mi.set_meta("flow_active", flowing)
		# Дискретные ступени давления — без «плавания» emission от шума sim.
		var band: int = 0
		if gauge >= 0.08:
			band = mini(4, int(floor(clampf(gauge, 0.0, 1.0) * 4.0)) + 1)
		var kind: String = "closed"
		if is_open:
			if flowing or band > 0:
				# Выхлоп 3/5 — тот же голубой, что каналы 1–2 (не «зелёный atm»).
				kind = "p%d" % maxi(band, 1)
			elif is_exh_port:
				# Стравлено: открытая клетка, но воздуха нет — дефолт, не подсветка.
				kind = "idle"
			else:
				kind = "atm"
		var state: String = "%s|%s" % ["1" if is_open else "0", kind]
		if str(mi.get_meta("flow_state", "")) == state:
			continue
		mi.set_meta("flow_state", state)
		_set_gallery_reach(mi, is_open)
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		if kind == "closed" or kind == "idle":
			# Дефолт галереи (как при сборке) / закрытый канал.
			mat.albedo_color = Color(0.45, 0.55, 0.62, 0.35) if kind == "idle" else Color(0.38, 0.40, 0.43, 0.28)
			mat.emission = Color(0.2, 0.25, 0.3) if kind == "idle" else Color(0.12, 0.13, 0.14)
			mat.emission_energy_multiplier = 0.15 if kind == "idle" else 0.04
		elif kind.begins_with("p"):
			var gq: float = float(band) / 4.0 if band > 0 else 0.25
			mat.albedo_color = Color(0.2, 0.75, 1.0, 0.55 + gq * 0.35)
			mat.emission = Color(0.15, 0.65, 1.0)
			mat.emission_energy_multiplier = 0.45 + gq * 0.7
		else:
			# Рабочий порт открыт, но без давления (не выхлоп).
			mat.albedo_color = Color(0.35, 0.7, 0.55, 0.45)
			mat.emission = Color(0.2, 0.55, 0.4)
			mat.emission_energy_multiplier = 0.35
	_sync_flow_bridges(root, el, pairs)


## Открытый канал доходит до расточки; закрытый обрывается у пояска.
static func _set_gallery_reach(mi: MeshInstance3D, is_open: bool) -> void:
	var full: float = float(mi.get_meta("gal_len_full", 0.0))
	if full < 1.0e-6:
		return
	if mi.has_meta("gal_reach_open") and bool(mi.get_meta("gal_reach_open")) == is_open:
		return
	mi.set_meta("gal_reach_open", is_open)
	var oy: float = float(mi.get_meta("gal_oy", 0.0))
	var ox: float = float(mi.get_meta("gal_ox", 0.0))
	var gz: float = float(mi.get_meta("gal_z", 0.0))
	var land_r: float = float(mi.get_meta("gal_land_r", absf(oy) * 0.48))
	var y_port: float = oy
	# Открыт — почти до оси; закрыт — у внешнего радиуса пояска.
	var y_inner: float = signf(oy) * (land_r * 0.35 if is_open else land_r * 1.05)
	var len: float = absf(y_port - y_inner)
	var mesh: CylinderMesh = mi.mesh as CylinderMesh
	if mesh != null:
		mesh.height = maxf(len, full * 0.2)
	var mid_y: float = 0.5 * (y_port + y_inner)
	mi.position = Vector3(ox, mid_y, gz)


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
			var br: float = body_h * 0.05
			mesh.top_radius = br
			mesh.bottom_radius = br
			mesh.height = span * 0.92
			mesh.radial_segments = 8
			mi.mesh = mesh
			mi.position = mid
			mi.material_override = mat
			mi.set_meta("xray_role", "internal")
			mi.set_meta("flow_viz", true)
			mi.set_meta("flow_pair", "%s-%s" % [a, b])
			mi.set_meta("port_a", a)
			mi.set_meta("port_b", b)
			bridges.add_child(mi)
			var dir := Vector3(xb - xa, yb - ya, 0.0)
			if dir.length_squared() > 1.0e-10:
				mi.look_at(mi.global_position + dir.normalized(), Vector3.BACK)
				mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Цвета мостиков — только при смене дискретного состояния.
	for child in bridges.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi2 := child as MeshInstance3D
		if not bool(mi2.get_meta("flow_viz", false)):
			mi2.set_meta("flow_viz", true)
		var a2 := str(mi2.get_meta("port_a", ""))
		var b2 := str(mi2.get_meta("port_b", ""))
		var pa := float(el.port_press.get(a2, 101325.0))
		var pb := float(el.port_press.get(b2, 101325.0))
		var hot := maxf(pa, pb)
		var gauge := clampf((hot - 101325.0) / 6.0e5, 0.0, 1.0)
		var mat2 := mi2.material_override as StandardMaterial3D
		if mat2 == null:
			continue
		var qa2: float = float(el.port_q.get(a2, 0.0)) if el.get("port_q") != null else 0.0
		var qb2: float = float(el.port_q.get(b2, 0.0)) if el.get("port_q") != null else 0.0
		var qmag2: float = maxf(absf(qa2), absf(qb2))
		var was_b: bool = bool(mi2.get_meta("flow_active", false))
		var flowing2: bool = (qmag2 > 8.0e-6 or gauge >= 0.08) if not was_b else (qmag2 > 1.0e-7 or gauge >= 0.04)
		mi2.set_meta("flow_active", flowing2)
		var band2: int = 0
		if gauge >= 0.08:
			band2 = mini(4, int(floor(clampf(gauge, 0.0, 1.0) * 4.0)) + 1)
		# Мостик к выхлопу — тот же голубой при потоке/давлении; после стравливания — дефолт.
		var bkind: String = "idle"
		if flowing2 or band2 > 0:
			bkind = "p%d" % maxi(band2, 1)
		if str(mi2.get_meta("flow_state", "")) == bkind:
			continue
		mi2.set_meta("flow_state", bkind)
		if bkind == "idle":
			mat2.albedo_color = Color(0.45, 0.55, 0.62, 0.28)
			mat2.emission = Color(0.2, 0.25, 0.3)
			mat2.emission_energy_multiplier = 0.12
		else:
			var gq2: float = float(band2) / 4.0 if band2 > 0 else 0.25
			mat2.albedo_color = Color(0.2, 0.85, 1.0, 0.35 + gq2 * 0.4)
			mat2.emission = Color(0.2, 0.8, 1.0)
			mat2.emission_energy_multiplier = 0.5 + gq2 * 0.8


static func _has_override(el, left: bool) -> bool:
	if left:
		return bool(el.get("override_left") if el.get("override_left") != null else true)
	return bool(el.get("override_right") if el.get("override_right") != null else true)


static func _build_op(
	parent: Node, spool: Node3D, el, left: bool, face_x: float,
	body_h: float, body_w: float, body_s: float, circuit = null, info: Dictionary = {}
) -> void:
	var op := str(el.op_left) if left else str(el.op_right)
	var sign := -1.0 if left else 1.0
	var axis := "x" if sign > 0.0 else "-x"
	match op:
		"solenoid", "solenoid_pilot":
			var pilot_on_tube := op == "solenoid_pilot"
			var tip: Vector3 = Parts.add_armature_tube(parent, face_x, sign, body_h, spool, left, pilot_on_tube)
			if pilot_on_tube:
				Parts.box(
					parent,
					Vector3(Parts.mm(8.0) * body_s, body_h * 0.55, body_w * 0.7),
					Vector3(face_x + sign * Parts.mm(4.0) * body_s, body_h * 0.08, 0),
					Parts.alum(),
					"shell"
				)
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
			info["ports"][pn] = Vector3(face_x + sign * Parts.mm(14.0) * body_s, 0, 0)
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
