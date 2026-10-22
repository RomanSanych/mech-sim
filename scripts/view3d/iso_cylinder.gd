class_name IsoCylinder
extends RefCounted
## Параметрический цилиндр в духе ISO 15552 (Festo DSBC) и бесштокового DGC / магнитной каретки.
## PPV-винт у порта на крышке; P — эластомер на поршне; пружина — спираль.
## X-ray: role window = труба/корпус над механикой; shell = крышки/крепёж (непрозрачные).

static var _mats := {}


static func assembly_length_m(bore_mm: float, stroke_mm: float) -> float:
	var bore := bore_mm * 0.001
	var stroke := stroke_mm * 0.001
	var cap := maxf(bore * 0.72, 0.018)
	var barrel := stroke + maxf(bore * 0.40, 0.016)
	return cap * 2.0 + barrel


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	if el.kind == "source":
		_source(parent, el, info)
	else:
		_cylinder(parent, el, info)
	return info


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


static func _box(
	parent: Node, size: Vector3, center: Vector3, mat: Material,
	role: String = "shell", thermal_part: String = ""
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	if thermal_part != "":
		mi.set_meta("thermal_part", thermal_part)
	parent.add_child(mi)
	return mi


static func _cyl(
	parent: Node, radius: float, length: float, center: Vector3, axis: String,
	mat: Material, segs: int = 24, role: String = "shell", thermal_part: String = ""
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
	if thermal_part != "":
		mi.set_meta("thermal_part", thermal_part)
	if axis == "x":
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif axis == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(mi)
	return mi


static func _seg(parent: Node, a: Vector3, b: Vector3, radius: float, mat: Material, role: String = "internal") -> MeshInstance3D:
	var delta := b - a
	var length := delta.length()
	if length < 0.0002:
		return null
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	mi.mesh = mesh
	mi.position = (a + b) * 0.5
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	var y := delta.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.basis = Basis(x, y, z)
	parent.add_child(mi)
	return mi


## ghost_shell: щит/электро — корпуса shell тоже полупрозрачны (дверца, крышки КК, DIN).
## Пневмо: ghost_shell=false — shell остаётся непрозрачным (крышки без нутра).
static func apply_xray(root: Node3D, on: bool, ghost_shell: bool = false) -> void:
	_apply_xray_node(root, on, false, ghost_shell)


## Не сохранять ghost/painted как «базу» — иначе выключение рентгена не возвращает opaque.
static func _opaque_base_mat(gi: GeometryInstance3D) -> Material:
	if gi.has_meta("pviz_base_mat") and gi.get_meta("pviz_base_mat") is StandardMaterial3D:
		var pv: StandardMaterial3D = gi.get_meta("pviz_base_mat") as StandardMaterial3D
		if not _mat_is_xray_ghost(pv):
			return pv
	if gi.has_meta("xray_base_mat") and gi.get_meta("xray_base_mat") is Material:
		var xb: Material = gi.get_meta("xray_base_mat") as Material
		if xb is StandardMaterial3D and not _mat_is_xray_ghost(xb as StandardMaterial3D):
			return xb
	var cur: Material = gi.material_override
	if cur is StandardMaterial3D and _mat_is_xray_ghost(cur as StandardMaterial3D):
		return null
	return cur


## Только наш рентген-ghost (не путать с clear_cover реле — у него alpha, но depth обычный).
static func _mat_is_xray_ghost(mat: StandardMaterial3D) -> bool:
	if mat == null:
		return false
	return mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			and mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
			and mat.albedo_color.a < 0.95


static func _ensure_xray_base(gi: GeometryInstance3D) -> void:
	if gi.has_meta("xray_base_mat"):
		var existing: Material = gi.get_meta("xray_base_mat") as Material
		if existing is StandardMaterial3D and _mat_is_xray_ghost(existing as StandardMaterial3D):
			gi.remove_meta("xray_base_mat")
		else:
			return
	var base: Material = _opaque_base_mat(gi)
	if base != null:
		gi.set_meta("xray_base_mat", base)


static func _apply_window_ghost(gi: GeometryInstance3D, on: bool) -> void:
	_ensure_xray_base(gi)
	var base_w: Material = null
	if gi.has_meta("xray_base_mat"):
		base_w = gi.get_meta("xray_base_mat") as Material
	if on and base_w is StandardMaterial3D:
		var ghost: StandardMaterial3D = null
		if gi.has_meta("xray_ghost"):
			ghost = gi.get_meta("xray_ghost") as StandardMaterial3D
		if ghost == null or (gi.has_meta("pviz_painted") and ghost == gi.get_meta("pviz_painted")):
			ghost = (base_w as StandardMaterial3D).duplicate() as StandardMaterial3D
			gi.set_meta("xray_ghost", ghost)
		ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = (base_w as StandardMaterial3D).albedo_color
		# Уже полупрозрачный колпак — чуть сильнее; иначе стандартное окно.
		var a_g: float = 0.14 if c.a < 0.95 else 0.22
		ghost.albedo_color = Color(c.r, c.g, c.b, a_g)
		ghost.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
		ghost.metallic = (base_w as StandardMaterial3D).metallic
		ghost.roughness = (base_w as StandardMaterial3D).roughness
		gi.material_override = ghost
	elif base_w != null:
		gi.material_override = base_w
	elif gi.material_override is StandardMaterial3D \
			and _mat_is_xray_ghost(gi.material_override as StandardMaterial3D):
		var fix: StandardMaterial3D = (gi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		fix.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		var fc: Color = fix.albedo_color
		fix.albedo_color = Color(fc.r, fc.g, fc.b, 1.0)
		fix.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		fix.cull_mode = BaseMaterial3D.CULL_BACK
		gi.set_meta("xray_base_mat", fix)
		gi.material_override = fix


static func _apply_xray_node(
	node: Node, on: bool, under_actuator: bool = false, ghost_shell: bool = false
) -> void:
	var is_act := under_actuator or (node is Node3D and (node as Node3D).has_meta("actuate_side"))
	# MeshInstance и живой CSG (GeometryInstance3D) — один путь для рентгена.
	if node is GeometryInstance3D and (node is MeshInstance3D or node is CSGShape3D):
		var gi := node as GeometryInstance3D
		# Каналы/мостики распреда красит IsoValve.update_flow_viz — не трогать материалы.
		if bool(gi.get_meta("flow_viz", false)):
			# Вне рентгена галереи прячем — иначе «залипает» подсветка каналов.
			gi.visible = on
			for child_skip in node.get_children():
				_apply_xray_node(child_skip, on, is_act, ghost_shell)
			return
		# SenseZone / MagnetField — видимость только у режима «Зоны», не у рентгена.
		if bool(gi.get_meta("field_viz", false)):
			for child_fv in node.get_children():
				_apply_xray_node(child_fv, on, is_act, ghost_shell)
			return
		var role := str(gi.get_meta("xray_role", "shell"))
		# Органы/дублёры (нажимаемые) — всегда непрозрачные; иначе X-ray сбивает с толку.
		if is_act or role == "control":
			_ensure_xray_base(gi)
			if gi.has_meta("xray_base_mat"):
				gi.material_override = gi.get_meta("xray_base_mat")
			if gi.has_meta("xray_lit"):
				gi.remove_meta("xray_lit")
			gi.visible = true
		elif role == "internal":
			gi.visible = true
			_ensure_xray_base(gi)
			if on:
				var mat := gi.material_override as StandardMaterial3D
				if mat != null and _mat_is_xray_ghost(mat) and gi.has_meta("xray_base_mat"):
					mat = gi.get_meta("xray_base_mat") as StandardMaterial3D
					gi.material_override = mat
				if mat and not gi.has_meta("xray_lit"):
					var lit := mat.duplicate() as StandardMaterial3D
					lit.emission_enabled = true
					lit.emission = lit.albedo_color
					lit.emission_energy_multiplier = 0.35
					gi.set_meta("xray_lit", lit)
					gi.material_override = lit
				elif gi.has_meta("xray_lit"):
					gi.material_override = gi.get_meta("xray_lit")
			elif gi.has_meta("xray_base_mat"):
				gi.material_override = gi.get_meta("xray_base_mat")
				if gi.has_meta("xray_lit"):
					gi.remove_meta("xray_lit")
		elif role == "window" or (role == "shell" and ghost_shell):
			# window — пневмо; shell+ghost_shell — дверца/КК/корпуса электро.
			_apply_window_ghost(gi, on)
		elif role == "shell":
			# Пневмо: крышки/крепёж непрозрачны.
			_ensure_xray_base(gi)
			if gi.has_meta("xray_base_mat"):
				gi.material_override = gi.get_meta("xray_base_mat")
			if gi.has_meta("xray_lit"):
				gi.remove_meta("xray_lit")
			gi.visible = true
	for child in node.get_children():
		_apply_xray_node(child, on, is_act, ghost_shell)


static func _cylinder(parent: Node3D, el, info: Dictionary) -> void:
	var bore: float = float(el.bore_mm) * 0.001
	var stroke: float = float(el.stroke_mm) * 0.001
	var rod_r: float = float(el.rod_mm) * 0.0005
	var style := str(el.body_style)
	var rod_mode := str(el.rod_mode)
	if rod_mode == "" and bool(el.through_rod):
		rod_mode = "through"
	if rod_mode == "":
		rod_mode = "single"
	var cush_cap := str(el.cush_cap)
	var cush_rod := str(el.cush_rod)
	var piston_kind := str(el.piston_kind)
	var spring := str(el.spring_side)
	var carriage := str(el.carriage)
	var rodless := rod_mode == "rodless"
	var roundish := style == "round" or style == "tierod" or rodless
	var profile := bore * (1.05 if rodless else (1.15 if style == "compact" else 1.48))
	var cap_l := maxf(bore * (0.45 if rodless else (0.38 if style == "compact" else 0.72)), 0.012)
	var barrel_l := stroke + maxf(bore * (0.25 if rodless else (0.18 if style == "compact" else 0.40)), 0.01)
	var total := cap_l * 2.0 + barrel_l
	var x0 := -total * 0.5
	var cap_side := profile * (1.0 if rodless else 1.08)
	var alum := _m("alum", Color(0.74, 0.76, 0.78), 0.88, 0.32)
	var cap_mat := _m("cap", Color(0.20, 0.31, 0.40), 0.55, 0.38)
	var blue := _m("blue", Color(0.05, 0.42, 0.78), 0.15, 0.42)
	var dark := _m("groove", Color(0.15, 0.17, 0.19), 0.4, 0.55)
	var chrome := _m("chrome", Color(0.93, 0.94, 0.95), 1.0, 0.08)
	var rubber := _m("rubber", Color(0.08, 0.08, 0.09), 0.0, 0.78)
	var steel := _m("steel", Color(0.62, 0.64, 0.66), 0.95, 0.28)
	var brass := _m("brass", Color(0.72, 0.58, 0.32), 0.9, 0.32)
	var magnet := _m("magnet", Color(0.12, 0.45, 0.28), 0.2, 0.55)
	var spring_m := _m("spring_steel", Color(0.82, 0.76, 0.38), 0.95, 0.22)
	var cush_pad := _m("cush_pad", Color(0.12, 0.12, 0.13), 0.02, 0.82)

	var rear_c := x0 + cap_l * 0.5
	var barrel_c := x0 + cap_l + barrel_l * 0.5
	var front_c := x0 + cap_l + barrel_l + cap_l * 0.5
	var barrel_inner_r := bore * 0.5
	var tube_r := bore * (0.58 if rodless else 0.62)
	var cap_r_round: float = tube_r * (1.08 if rodless else 1.12)

	# Порты нужны до CSG-крышек (каналы вычитаются под штуцеры).
	var port_cap_style_pre := str(el.port_cap) if el.get("port_cap") != null else "connect"
	var port_rod_style_pre := str(el.port_rod) if el.get("port_rod") != null else "connect"
	if spring == "cap" or spring == "both":
		port_cap_style_pre = "exhaust"
	if spring == "rod" or spring == "both":
		port_rod_style_pre = "exhaust"
	var actions_pre: Array = []
	if el.action != "spring_extend":
		actions_pre.append("cap")
	if el.action != "spring_return":
		actions_pre.append("rod")
	var has_port_cap: bool = "cap" in actions_pre
	var has_port_rod: bool = "rod" in actions_pre

	# Крышки CSG: расточка под поршень + канал штуцер→полость (как на моторах).
	_build_end_cap_csg(
		parent, rear_c, cap_l, barrel_inner_r, rod_r, true, rodless, roundish,
		tube_r, cap_side, cap_r_round, has_port_cap, rod_mode == "through", cap_mat
	)
	_build_end_cap_csg(
		parent, front_c, cap_l, barrel_inner_r, rod_r, false, rodless, roundish,
		tube_r, cap_side, cap_r_round, has_port_rod, true, cap_mat
	)

	# Гильза CSG: наружный профиль − расточка Ø поршня (камера давления видна в рентгене).
	_build_barrel_csg(parent, barrel_c, barrel_l, roundish, tube_r, profile, barrel_inner_r, alum)
	if roundish:
		if style == "tierod" and not rodless:
			var tie_r := maxf(bore * 0.06, 0.003)
			var span := tube_r + tie_r * 1.4
			for side_y in [-1.0, 1.0]:
				for side_z in [-1.0, 1.0]:
					_cyl(parent, tie_r, total * 0.92, Vector3(0, side_y * span, side_z * span), "x", steel, 8, "shell")
		if rodless:
			# Уплотнительная лента сверху (механическая связь / паз).
			_box(parent, Vector3(barrel_l * 0.96, 0.002, tube_r * 0.22), Vector3(barrel_c, tube_r + 0.001, 0), dark, "shell")
	else:
		# Синие прокладки на стыке крышка/гильза — кольцо с расточкой под поршень (не сплошной диск).
		_build_end_gasket_csg(parent, x0 + cap_l, profile, barrel_inner_r, blue)
		_build_end_gasket_csg(parent, x0 + cap_l + barrel_l, profile, barrel_inner_r, blue)
		var groove_l := barrel_l * 0.86
		var groove_w := profile * 0.11
		var lift := profile * 0.5 + 0.0006
		_box(parent, Vector3(groove_l, 0.004, groove_w), Vector3(barrel_c, lift, 0), dark, "shell")
		_box(parent, Vector3(groove_l, 0.004, groove_w), Vector3(barrel_c, -lift, 0), dark, "shell")
		_box(parent, Vector3(groove_l, groove_w, 0.004), Vector3(barrel_c, 0, lift), dark, "shell")
		_box(parent, Vector3(groove_l, groove_w, 0.004), Vector3(barrel_c, 0, -lift), dark, "shell")
		var screw_r := profile * 0.055
		for sx in [rear_c, front_c]:
			for side_y in [-1.0, 1.0]:
				for side_z in [-1.0, 1.0]:
					_cyl(parent, screw_r, 0.004, Vector3(sx, side_y * cap_side * 0.34, side_z * cap_side * 0.34), "x", steel, 6, "shell")

	# Крепление по el.mount (у through — лапы, если mount не задан явно иначе).
	_build_mount(parent, el, rod_mode, rodless, roundish, tube_r, profile, cap_side, cap_l, x0, rear_c, front_c, total, steel, cap_mat)

	var front_face := x0 + total
	var rod := Node3D.new()
	rod.name = "Rod"
	parent.add_child(rod)
	var piston_x := x0 + cap_l + 0.004
	var piston_t := maxf(bore * 0.22, 0.006)

	# Поршень + (опц.) магнитный поясок. Fixed (P): эластомер на торцах поршня.
	_cyl(rod, barrel_inner_r * 0.96, piston_t, Vector3(piston_x, 0, 0), "x", alum, 24, "internal", "piston")
	if piston_kind == "magnetic" or (rodless and carriage == "magnetic"):
		_cyl(rod, barrel_inner_r * 0.98, piston_t * 0.4, Vector3(piston_x, 0, 0), "x", magnet, 24, "internal", "piston")
		_add_magnet_field_viz(rod, el)
	if cush_cap == "fixed":
		_cyl(rod, barrel_inner_r * 0.9, 0.003, Vector3(piston_x - piston_t * 0.55, 0, 0), "x", cush_pad, 16, "internal", "piston")
	if cush_rod == "fixed":
		_cyl(rod, barrel_inner_r * 0.9, 0.003, Vector3(piston_x + piston_t * 0.55, 0, 0), "x", cush_pad, 16, "internal", "piston")
	# PPV / PPS: демпферный «шип» поршня. Игла только у adjustable.
	if cush_cap == "adjustable" or cush_cap == "self":
		_cyl(rod, barrel_inner_r * 0.42, bore * 0.28, Vector3(piston_x - piston_t * 0.5 - bore * 0.12, 0, 0), "x", steel, 12, "internal", "piston")
	if cush_rod == "adjustable" or cush_rod == "self":
		_cyl(rod, barrel_inner_r * 0.42, bore * 0.28, Vector3(piston_x + piston_t * 0.5 + bore * 0.12, 0, 0), "x", steel, 12, "internal", "piston")

	if rodless:
		_build_rodless_carriage(rod, carriage, piston_x, tube_r, bore, barrel_inner_r, piston_t, blue, dark, magnet, steel)
		_build_bump_ends(parent, el, x0, total, tube_r, bore, rubber, steel)
	elif rod_r >= 0.0005:
		var guide := str(el.guide) if el.get("guide") != null else "none"
		var bush_r := rod_r * (2.2 if guide == "bushing" else 1.85)
		_cyl(parent, bush_r, cap_l * 0.22, Vector3(front_face - cap_l * 0.08, 0, 0), "x", steel, 20, "shell", "gland")
		_cyl(parent, rod_r * 1.35, 0.005, Vector3(front_face + 0.001, 0, 0), "x", rubber, 20, "shell", "gland")
		var rod_len := (front_face - piston_x) + bore * 0.55
		var tip := piston_x + rod_len
		if guide == "non_rot":
			# Квадратный / с лыской наконечник штока.
			_box(rod, Vector3(rod_len, rod_r * 1.7, rod_r * 1.7), Vector3(piston_x + rod_len * 0.5, 0, 0), chrome, "shell", "rod")
		else:
			_cyl(rod, rod_r, rod_len, Vector3(piston_x + rod_len * 0.5, 0, 0), "x", chrome, 20, "shell", "rod")
		_rod_tip(rod, el, tip, rod_r, 1.0, steel, chrome)
		if guide == "non_rot":
			_box(rod, Vector3(rod_r * 2.4, rod_r * 2.0, rod_r * 2.0), Vector3(tip - rod_r * 0.4, 0, 0), steel, "shell", "rod")
		_build_brake(parent, el, front_face, rod_r, bore, profile, steel, dark, rubber)
		if rod_mode == "through":
			var rear_len := maxf(stroke, 0.01)
			var rear_tip := piston_x - rear_len
			_cyl(rod, rod_r, rear_len, Vector3(piston_x - rear_len * 0.5, 0, 0), "x", chrome, 20, "shell", "rod")
			_cyl(parent, rod_r * 1.85, cap_l * 0.22, Vector3(x0 + cap_l * 0.08, 0, 0), "x", steel, 20, "shell", "gland")
			_cyl(parent, rod_r * 1.35, 0.005, Vector3(x0 - 0.001, 0, 0), "x", rubber, 20, "shell", "gland")
			_rod_tip(rod, el, rear_tip, rod_r, -1.0, steel, chrome)

	# Пружина: узел Spring + мета; длина обновляется от el.x в workshop (разжата при большой полости).
	var coil_r := barrel_inner_r * (0.48 if rodless else 0.38)
	if spring == "rod" or spring == "cap" or spring == "both":
		var spring_node := Node3D.new()
		spring_node.name = "Spring"
		spring_node.set_meta("side", spring)
		spring_node.set_meta("coil_r", coil_r)
		spring_node.set_meta("barrel_a", x0 + cap_l + 0.004)
		spring_node.set_meta("barrel_b", x0 + cap_l + barrel_l - 0.004)
		spring_node.set_meta("piston0", piston_x)
		spring_node.set_meta("piston_t", piston_t)
		parent.add_child(spring_node)
		_refresh_spring(spring_node, float(el.x), spring_m)

	var port_cap_style := str(el.port_cap) if el.get("port_cap") != null else "connect"
	var port_rod_style := str(el.port_rod) if el.get("port_rod") != null else "connect"
	if spring == "cap" or spring == "both":
		port_cap_style = "exhaust"
	if spring == "rod" or spring == "both":
		port_rod_style = "exhaust"
	var actions: Array = []
	if el.action != "spring_extend":
		actions.append("cap")
	if el.action != "spring_return":
		actions.append("rod")

	for port_name in actions:
		var px := rear_c if port_name == "cap" else front_c
		var pstyle := port_cap_style if port_name == "cap" else port_rod_style
		var cush_kind := cush_cap if port_name == "cap" else cush_rod
		# У бесштокового порты на боковой стороне крышки — верх свободен под каретку.
		var Parts = preload("res://scripts/view3d/pneumo_parts.gd")
		var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
		var fit_thread: String = str(el.port_name) if el.get("port_name") != null else "G1/8"
		var fit_od: float = 6.0
		if el.get("tube_od_mm") != null:
			fit_od = float(el.get("tube_od_mm"))
		var fit_s: float = TubeFit.fitting_scale(fit_thread, fit_od)
		fit_s = clampf(fit_s * clampf(bore / 0.032, 0.85, 1.1), 0.65, 2.2)
		if rodless:
			var origin_z := Vector3(px, 0, tube_r + 0.004)
			if pstyle == "exhaust":
				info["ports"][port_name] = Parts.add_silencer(parent, origin_z, "z", fit_s * 0.85)
			else:
				info["ports"][port_name] = Parts.add_fitting(parent, origin_z, "z", fit_s)
			info["dirs"][port_name] = Vector3(0, 0, 1)
			if cush_kind == "adjustable":
				var screw_y := clampf(tube_r * 0.35, 0.004, tube_r * 0.55)
				_cyl(parent, bore * 0.05, 0.008, Vector3(px, screw_y, tube_r + 0.002), "z", brass, 8, "shell")
				_cyl(parent, bore * 0.032, 0.005, Vector3(px, screw_y, tube_r + 0.008), "z", steel, 6, "shell")
		else:
			var base_y := (cap_side if not roundish else tube_r * 1.05) * 0.5
			if roundish:
				base_y = tube_r * 0.85
			var origin_y := Vector3(px, base_y, 0)
			if pstyle == "exhaust":
				info["ports"][port_name] = Parts.add_silencer(parent, origin_y, "y", fit_s * 0.85)
			else:
				info["ports"][port_name] = Parts.add_fitting(parent, origin_y, "y", fit_s)
			info["dirs"][port_name] = Vector3.UP
			if cush_kind == "adjustable":
				var half := (cap_side if not roundish else tube_r * 1.7) * 0.5
				var inset := maxf(bore * 0.1, 0.004)
				var screw_z := clampf(half * 0.42, -half + inset, half - inset)
				var screw_r := minf(bore * 0.055, half * 0.22)
				_cyl(parent, screw_r, 0.008, Vector3(px, base_y + 0.003, screw_z), "y", brass, 8, "shell")
				_cyl(parent, screw_r * 0.62, 0.005, Vector3(px, base_y + 0.009, screw_z), "y", steel, 6, "shell")

	var label := Label3D.new()
	label.name = "Tag"
	label.text = el.tag
	label.font_size = 48
	label.pixel_size = 0.00055
	label.modulate = Color(0.9, 0.93, 0.96)
	label.outline_modulate = Color(0.05, 0.08, 0.12)
	label.outline_size = 6
	var label_y := (tube_r if roundish else profile * 0.5) + 0.01
	if rodless:
		label_y = tube_r + bore * 0.85
	label.position = Vector3(barrel_c, label_y, 0)
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.visible = false # обозначение — во всплывающей подсказке
	parent.add_child(label)


## Гильза: наружный профиль − цилиндрическая расточка (ход поршня / камера давления).
static func _build_barrel_csg(
	parent: Node3D,
	barrel_c: float,
	barrel_l: float,
	roundish: bool,
	tube_r: float,
	profile: float,
	bore_r: float,
	mat: Material
) -> void:
	var CsgBake = preload("res://scripts/view3d/csg_bake.gd")
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "BarrelCSG"
	if roundish:
		comb.add_child(CsgBake.cyl(tube_r, barrel_l, Vector3.ZERO, "x", UNION, 28))
	else:
		comb.add_child(CsgBake.box(Vector3(barrel_l * 0.998, profile, profile), Vector3.ZERO, UNION))
	comb.add_child(CsgBake.cyl(bore_r, barrel_l + 0.003, Vector3.ZERO, "x", SUB, 28))
	comb.position = Vector3(barrel_c, 0.0, 0.0)
	CsgBake.attach(parent, comb, mat, "window", "barrel")


## Тонкая прокладка на торце гильзы: квадрат − отверстие под поршень.
static func _build_end_gasket_csg(
	parent: Node3D, cx: float, profile: float, bore_r: float, mat: Material
) -> void:
	var CsgBake = preload("res://scripts/view3d/csg_bake.gd")
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "GasketCSG"
	var t: float = 0.005
	var side: float = profile * 1.02
	comb.add_child(CsgBake.box(Vector3(t, side, side), Vector3.ZERO, UNION))
	comb.add_child(CsgBake.cyl(bore_r * 1.02, t + 0.002, Vector3.ZERO, "x", SUB, 22))
	comb.position = Vector3(cx, 0.0, 0.0)
	CsgBake.attach(parent, comb, mat, "window", "gland")


## Крышка ПЦ через CSG: тело − расточка под поршень − канал от штуцера (как на моторах).
static func _build_end_cap_csg(
	parent: Node3D,
	cap_cx: float,
	cap_l: float,
	bore_r: float,
	rod_r: float,
	is_rear: bool,
	rodless: bool,
	roundish: bool,
	tube_r: float,
	cap_side: float,
	cap_r_round: float,
	has_port: bool,
	rod_bore: bool,
	cap_mat: Material
) -> void:
	var CsgBake = preload("res://scripts/view3d/csg_bake.gd")
	var UNION := CSGShape3D.OPERATION_UNION
	var SUB := CSGShape3D.OPERATION_SUBTRACTION
	var comb := CSGCombiner3D.new()
	comb.name = "CapCSG_%s" % ("rear" if is_rear else "front")
	# Тело крышки в локали combiner (центр в начале координат).
	if roundish:
		comb.add_child(CsgBake.cyl(cap_r_round, cap_l, Vector3.ZERO, "x", UNION, 28))
	else:
		comb.add_child(CsgBake.box(Vector3(cap_l, cap_side, cap_side), Vector3.ZERO, UNION))
	# Расточка со стороны ствола: задняя крышка — устье к +X, передняя — к −X.
	var pocket_d: float = clampf(cap_l * 0.55, 0.007, cap_l * 0.78)
	var pocket_r: float = bore_r * 1.05
	var face_sign: float = 1.0 if is_rear else -1.0
	# Устье на грани к стволу (локаль ±cap_l/2).
	var face_local: float = face_sign * cap_l * 0.5
	var pocket_c: float = face_local - face_sign * pocket_d * 0.5
	comb.add_child(CsgBake.cyl(pocket_r, pocket_d + 0.001, Vector3(pocket_c, 0.0, 0.0), "x", SUB, 22))
	# Отверстие под шток (перед / through).
	if rod_bore and not rodless and rod_r > 0.0004:
		var rh: float = rod_r * 1.15
		comb.add_child(CsgBake.cyl(rh, cap_l + 0.004, Vector3.ZERO, "x", SUB, 16))
	# Канал штуцер → полость.
	if has_port:
		var chan_r: float = clampf(bore_r * 0.24, 0.002, 0.007)
		if rodless:
			var z_top: float = (tube_r if roundish else cap_side * 0.5) * 0.95
			var z_from: float = z_top + chan_r * 0.2
			var z_to: float = 0.0
			var z_lo: float = minf(z_from, z_to)
			var z_hi: float = maxf(z_from, z_to)
			comb.add_child(CsgBake.cyl(
				chan_r, z_hi - z_lo + chan_r * 0.5,
				Vector3(0.0, 0.0, 0.5 * (z_lo + z_hi)), "z", SUB, 12
			))
			# Связка к устью расточки по оси.
			var ax_to: float = face_local
			var ax_lo: float = minf(0.0, ax_to)
			var ax_hi: float = maxf(0.0, ax_to)
			comb.add_child(CsgBake.cyl(
				chan_r * 0.95, ax_hi - ax_lo + chan_r,
				Vector3(0.5 * (ax_lo + ax_hi), 0.0, 0.0), "x", SUB, 12
			))
		else:
			# Стык со штуцером (base_y в _cylinder) — канал пробивает наружу.
			var y_top: float = (cap_side if not roundish else tube_r * 1.05) * 0.5
			if roundish:
				y_top = tube_r * 0.85
			var y_from: float = y_top + chan_r * 0.6
			var y_to: float = 0.0
			var y_lo: float = minf(y_from, y_to)
			var y_hi: float = maxf(y_from, y_to)
			comb.add_child(CsgBake.cyl(
				chan_r, y_hi - y_lo + chan_r * 0.5,
				Vector3(0.0, 0.5 * (y_lo + y_hi), 0.0), "y", SUB, 12
			))
			var ax2_to: float = face_local
			var ax2_lo: float = minf(0.0, ax2_to)
			var ax2_hi: float = maxf(0.0, ax2_to)
			comb.add_child(CsgBake.cyl(
				chan_r * 0.95, ax2_hi - ax2_lo + chan_r,
				Vector3(0.5 * (ax2_lo + ax2_hi), 0.0, 0.0), "x", SUB, 12
			))
			# Устье в расточку — чуть шире, читается в рентгене.
			comb.add_child(CsgBake.cyl(
				chan_r * 1.2, chan_r * 1.5,
				Vector3(face_local - face_sign * chan_r * 0.4, 0.0, 0.0), "x", SUB, 10
			))
	comb.position = Vector3(cap_cx, 0.0, 0.0)
	# window: в рентгене видно расточку и канал (как корпус мотора), не opaque shell.
	CsgBake.attach(parent, comb, cap_mat, "window", "cap")


static func _build_mount(parent: Node, el, rod_mode: String, rodless: bool, roundish: bool, tube_r: float, profile: float, cap_side: float, cap_l: float, x0: float, rear_c: float, front_c: float, total: float, steel: Material, cap_mat: Material) -> void:
	var mount := str(el.mount) if el.get("mount") != null else "clevis"
	if mount == "" or mount == "none":
		return
	# Through-rod: не ставим серьгу на ось — лапы или фланец.
	if rod_mode == "through" and mount == "clevis":
		mount = "foot"
	var foot_y := -(cap_side if not roundish else tube_r) * 0.55 - 0.004
	match mount:
		"foot":
			_box(parent, Vector3(cap_l * 0.9, 0.008, profile * 0.7), Vector3(rear_c, foot_y, 0), steel, "shell")
			_box(parent, Vector3(cap_l * 0.9, 0.008, profile * 0.7), Vector3(front_c, foot_y, 0), steel, "shell")
		"flange_front":
			var fz := front_c + cap_l * 0.35
			_box(parent, Vector3(0.006, profile * 1.35, profile * 1.35), Vector3(fz, 0, 0), steel, "shell")
		"flange_rear":
			var rz := rear_c - cap_l * 0.35
			_box(parent, Vector3(0.006, profile * 1.35, profile * 1.35), Vector3(rz, 0, 0), steel, "shell")
		"trunnion":
			# Две цапфы снаружи корпуса по ±Z, без сквозного вала.
			var mid := x0 + total * 0.5
			var body_r := (cap_side if not roundish else tube_r) * 0.5
			if roundish:
				body_r = tube_r
			else:
				body_r = profile * 0.5
			var pin_r := maxf(profile * 0.07, 0.004)
			var stub := maxf(profile * 0.28, 0.012)
			var z0 := body_r + stub * 0.5 + 0.001
			_cyl(parent, pin_r, stub, Vector3(mid, 0, z0), "z", steel, 12, "shell")
			_cyl(parent, pin_r, stub, Vector3(mid, 0, -z0), "z", steel, 12, "shell")
			_cyl(parent, pin_r * 1.35, 0.005, Vector3(mid, 0, z0 + stub * 0.35), "z", steel, 10, "shell")
			_cyl(parent, pin_r * 1.35, 0.005, Vector3(mid, 0, -(z0 + stub * 0.35)), "z", steel, 10, "shell")
		"clevis":
			if rodless:
				return
			var lug_x := x0 - cap_l * 0.18
			var lug_h := profile * 0.62
			_box(parent, Vector3(cap_l * 0.7, lug_h, profile * 0.09), Vector3(lug_x, 0, profile * 0.24), cap_mat, "shell")
			_box(parent, Vector3(cap_l * 0.7, lug_h, profile * 0.09), Vector3(lug_x, 0, -profile * 0.24), cap_mat, "shell")
			_cyl(parent, profile * 0.09, profile * 0.62, Vector3(lug_x - cap_l * 0.02, 0, 0), "z", steel, 16, "shell")
		_:
			pass


static func _build_brake(parent: Node, el, front_face: float, rod_r: float, bore: float, profile: float, steel: Material, dark: Material, rubber: Material) -> void:
	var brake := str(el.brake) if el.get("brake") != null else "none"
	if brake == "" or brake == "none":
		return
	if brake == "end_lock":
		_box(parent, Vector3(0.01, profile * 0.35, profile * 0.35), Vector3(front_face + 0.008, 0, 0), dark, "shell")
		_box(parent, Vector3(0.004, rod_r * 2.4, rod_r * 2.4), Vector3(front_face + 0.014, 0, 0), steel, "shell")
		return
	# NC clamp on front cover.
	_box(parent, Vector3(bore * 0.35, bore * 0.45, bore * 0.55), Vector3(front_face + bore * 0.12, bore * 0.35, 0), steel, "shell")
	_box(parent, Vector3(bore * 0.12, rod_r * 2.2, rod_r * 2.8), Vector3(front_face + bore * 0.06, 0, 0), rubber, "shell")


static func _build_bump_ends(parent: Node, el, x0: float, total: float, tube_r: float, bore: float, rubber: Material, steel: Material) -> void:
	var bump := str(el.bump_end) if el.get("bump_end") != null else "none"
	if bump == "" or bump == "none":
		return
	var y := tube_r + bore * 0.15
	var len := 0.008 if bump == "elastic" else 0.016
	var mat := rubber if bump == "elastic" else steel
	_cyl(parent, bore * 0.12, len, Vector3(x0 + bore * 0.2, y, 0), "x", mat, 10, "shell")
	_cyl(parent, bore * 0.12, len, Vector3(x0 + total - bore * 0.2, y, 0), "x", mat, 10, "shell")
	if bump == "ysr":
		_cyl(parent, bore * 0.08, 0.01, Vector3(x0 + bore * 0.2, y + 0.006, 0), "y", steel, 8, "shell")
		_cyl(parent, bore * 0.08, 0.01, Vector3(x0 + total - bore * 0.2, y + 0.006, 0), "y", steel, 8, "shell")


static func _build_rodless_carriage(rod: Node3D, carriage: String, piston_x: float, tube_r: float, bore: float, barrel_inner_r: float, piston_t: float, blue: Material, dark: Material, magnet: Material, steel: Material) -> void:
	# Каретка сидит над трубой у поршня (не у крышек/портов). Длина ~1.1…1.4∅.
	var car_w := clampf(bore * 1.25, 0.02, 0.08)
	var car_h := bore * 0.55
	var car_d := tube_r * 2.0 + bore * 0.15
	var gap := 0.003 if carriage == "magnetic" else 0.001
	var car_y := tube_r + gap + car_h * 0.5
	_box(rod, Vector3(car_w, car_h, car_d), Vector3(piston_x, car_y, 0), blue, "shell")
	_box(rod, Vector3(car_w * 0.75, 0.003, car_d * 0.7), Vector3(piston_x, car_y + car_h * 0.5, 0), dark, "shell")
	if carriage == "magnetic":
		# Магнитная связь: внешние магниты каретки + зазор, без жёсткого моста через паз.
		_box(rod, Vector3(car_w * 0.35, car_h * 0.35, car_d * 0.2), Vector3(piston_x - car_w * 0.2, car_y - car_h * 0.15, 0), magnet, "shell")
		_box(rod, Vector3(car_w * 0.35, car_h * 0.35, car_d * 0.2), Vector3(piston_x + car_w * 0.2, car_y - car_h * 0.15, 0), magnet, "shell")
	else:
		# Механическая связь DGC: ярмо поршень → каретка через верхний паз.
		var yoke_h := (car_y - car_h * 0.5) - barrel_inner_r * 0.2
		_box(rod, Vector3(car_w * 0.28, yoke_h, bore * 0.12), Vector3(piston_x, barrel_inner_r * 0.2 + yoke_h * 0.5, 0), steel, "internal")
		_box(rod, Vector3(car_w * 0.5, 0.004, bore * 0.2), Vector3(piston_x, piston_t * 0.1, 0), steel, "internal")


static func _rod_tip(parent: Node, el, tip_x: float, rod_r: float, sign: float, steel: Material, chrome: Material) -> void:
	var kind := str(el.rod_end) if el.get("rod_end") != null else "plain"
	match kind:
		"female":
			_cyl(parent, rod_r * 1.55, rod_r * 2.8, Vector3(tip_x - sign * rod_r * 0.6, 0, 0), "x", steel, 8, "shell", "rod")
		"clevis":
			_box(parent, Vector3(rod_r * 1.2, rod_r * 3.2, rod_r * 0.5), Vector3(tip_x, 0, 0), steel, "shell", "rod")
			_box(parent, Vector3(rod_r * 1.2, rod_r * 3.2, rod_r * 0.5), Vector3(tip_x, 0, rod_r * 1.4), steel, "shell", "rod")
		"male":
			_cyl(parent, rod_r * 0.85, rod_r * 3.5, Vector3(tip_x + sign * rod_r * 0.8, 0, 0), "x", chrome, 10, "shell", "rod")
		_:
			_cyl(parent, rod_r * 1.45, rod_r * 2.4, Vector3(tip_x - sign * rod_r * 0.4, 0, 0), "x", steel, 6, "shell", "rod")


static func update_spring(root: Node3D, el) -> void:
	var spring_node := root.get_node_or_null("Spring")
	if spring_node == null:
		return
	var last := float(spring_node.get_meta("last_x", -1.0e9))
	if absf(last - float(el.x)) < 0.00025:
		return
	spring_node.set_meta("last_x", float(el.x))
	var mat := _m("spring_steel", Color(0.82, 0.76, 0.38), 0.95, 0.22)
	_refresh_spring(spring_node, float(el.x), mat)


static func _add_magnet_field_viz(rod: Node3D, el) -> void:
	var SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
	var f: Dictionary = SensorDetect.cylinder_magnet_field_rod_local(el)
	if f.is_empty():
		return
	var zone := MeshInstance3D.new()
	zone.name = "MagnetField"
	var mesh := CylinderMesh.new()
	var rad: float = float(f.get("radius", 0.03))
	var length: float = maxf(float(f.get("length", 0.03)), 0.008)
	mesh.top_radius = rad
	mesh.bottom_radius = rad
	mesh.height = length
	mesh.radial_segments = 24
	zone.mesh = mesh
	# CylinderMesh по Y → повернуть на ось X поршня.
	zone.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	zone.position = f.get("origin", Vector3.ZERO) as Vector3
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = SensorDetect.magnet_field_viz_color(false)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	zone.material_override = mat
	zone.visible = false
	# Не internal: рентген иначе форсит visible поверх режима «Зоны».
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	rod.add_child(zone)


static func apply_magnet_field_viz(root: Node3D, on: bool, active: bool = false, el = null) -> void:
	if root == null:
		return
	var rod: Node3D = root.get_node_or_null("Rod") as Node3D
	if rod == null:
		return
	var zone: MeshInstance3D = rod.get_node_or_null("MagnetField") as MeshInstance3D
	if zone == null:
		return
	zone.set_meta("field_viz", true)
	zone.set_meta("xray_role", "control")
	zone.visible = bool(on)
	if not on:
		return
	var SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
	if el != null:
		var f: Dictionary = SensorDetect.cylinder_magnet_field_rod_local(el)
		var mesh: CylinderMesh = zone.mesh as CylinderMesh
		if mesh != null and not f.is_empty():
			var rad: float = float(f.get("radius", mesh.top_radius))
			mesh.top_radius = rad
			mesh.bottom_radius = rad
			mesh.height = maxf(float(f.get("length", mesh.height)), 0.008)
			zone.position = f.get("origin", zone.position) as Vector3
	var mat: StandardMaterial3D = zone.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = SensorDetect.magnet_field_viz_color(active)


static func _refresh_spring(spring_node: Node3D, x_m: float, mat: Material) -> void:
	var side := str(spring_node.get_meta("side", "none"))
	var coil_r: float = float(spring_node.get_meta("coil_r", 0.01))
	var barrel_a: float = float(spring_node.get_meta("barrel_a", 0.0))
	var barrel_b: float = float(spring_node.get_meta("barrel_b", 0.0))
	var piston0: float = float(spring_node.get_meta("piston0", 0.0))
	var piston_t: float = float(spring_node.get_meta("piston_t", 0.006))
	var px := piston0 + x_m
	# Один MeshInstance на сторону: пересобираем гелису при сдвиге поршня.
	if side == "cap" or side == "both":
		_place_coil_stack(spring_node, "Cap", barrel_a, px - piston_t * 0.55, coil_r, mat)
	else:
		_clear_coil_stack(spring_node, "Cap")
	if side == "rod" or side == "both":
		_place_coil_stack(spring_node, "Rod", px + piston_t * 0.55, barrel_b, coil_r, mat)
	else:
		_clear_coil_stack(spring_node, "Rod")


static func _clear_coil_stack(parent: Node, prefix: String) -> void:
	var node := parent.get_node_or_null(prefix)
	if node:
		node.queue_free()


## Винтовая пружина (проволока по гелисе), не стопка колец.
static func _place_coil_stack(parent: Node, prefix: String, x0: float, x1: float, radius: float, mat: Material) -> void:
	if x1 < x0:
		var swap := x0
		x0 = x1
		x1 = swap
	var span := x1 - x0
	var min_span := maxf(radius * 1.35, 0.008)
	var draw_span := maxf(span, min_span)
	var start := x0
	if span < min_span:
		start = x1 - min_span if prefix == "Cap" else x0
	var turns: int = 9
	var wire := maxf(radius * 0.14, 0.0010)
	var coil_r := maxf(radius - wire * 0.35, wire * 2.5)

	var mi := parent.get_node_or_null(prefix) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = prefix
		mi.material_override = mat
		mi.set_meta("xray_role", "internal")
		parent.add_child(mi)
	mi.mesh = _build_helix_spring_mesh(start, start + draw_span, coil_r, wire, turns)
	mi.visible = true


static func _build_helix_spring_mesh(x0: float, x1: float, coil_r: float, wire_r: float, turns: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var span := x1 - x0
	if span < 1e-5 or coil_r < 1e-5 or wire_r < 1e-5 or turns < 1:
		return mesh
	var segs_per_turn := 14
	var n_pts: int = turns * segs_per_turn + 1
	var sides := 6
	var pts := PackedVector3Array()
	pts.resize(n_pts)
	for i in n_pts:
		var t: float = float(i) / float(n_pts - 1)
		var ang: float = t * float(turns) * TAU
		pts[i] = Vector3(x0 + span * t, coil_r * cos(ang), coil_r * sin(ang))

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var tangents: Array = []
	for i in n_pts:
		var tg: Vector3
		if i == 0:
			tg = (pts[1] - pts[0]).normalized()
		elif i == n_pts - 1:
			tg = (pts[i] - pts[i - 1]).normalized()
		else:
			tg = (pts[i + 1] - pts[i - 1]).normalized()
		if tg.length_squared() < 1e-10:
			tg = Vector3.RIGHT
		tangents.append(tg)

	var n0 := Vector3.UP
	var t0: Vector3 = tangents[0]
	if absf(t0.dot(n0)) > 0.92:
		n0 = Vector3.FORWARD
	var binorm: Vector3 = t0.cross(n0).normalized()
	var normal: Vector3 = binorm.cross(t0).normalized()
	for i in n_pts:
		var ti: Vector3 = tangents[i]
		if i > 0:
			var tprev: Vector3 = tangents[i - 1]
			var axis: Vector3 = tprev.cross(ti)
			if axis.length_squared() > 1e-10:
				var basis := Basis(axis.normalized(), tprev.angle_to(ti))
				normal = basis * normal
				binorm = ti.cross(normal).normalized()
				normal = binorm.cross(ti).normalized()
			else:
				binorm = ti.cross(normal).normalized()
				if binorm.length_squared() < 1e-10:
					binorm = Vector3.FORWARD
				normal = binorm.cross(ti).normalized()
		var v_base := verts.size()
		for s in sides:
			var ang: float = TAU * float(s) / float(sides)
			var dir: Vector3 = (normal * cos(ang) + binorm * sin(ang)).normalized()
			verts.append(pts[i] + dir * wire_r)
			norms.append(dir)
		if i > 0:
			var prev := v_base - sides
			for s in sides:
				var s1 := (s + 1) % sides
				indices.append(prev + s)
				indices.append(v_base + s)
				indices.append(v_base + s1)
				indices.append(prev + s)
				indices.append(v_base + s1)
				indices.append(prev + s1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _source(parent: Node3D, el, info: Dictionary) -> void:
	var body := _m("src_body", Color(0.16, 0.34, 0.52), 0.35, 0.42)
	var alum := _m("alum", Color(0.74, 0.76, 0.78), 0.88, 0.32)
	var black := _m("knob", Color(0.1, 0.11, 0.12), 0.05, 0.6)
	var glass := _m("glass", Color(0.75, 0.86, 0.9), 0.05, 0.12, 0.45)
	var white := _m("face", Color(0.94, 0.95, 0.96), 0.0, 0.45)
	var needle_m := _m("needle", Color(0.75, 0.18, 0.14), 0.2, 0.4)
	var blue := _m("blue", Color(0.05, 0.42, 0.78), 0.15, 0.42)
	var brass := _m("brass", Color(0.72, 0.58, 0.32), 0.9, 0.32)
	var rubber := _m("rubber", Color(0.08, 0.08, 0.09), 0.0, 0.78)

	_box(parent, Vector3(0.14, 0.012, 0.1), Vector3(0, 0.006, 0), alum, "shell")
	_box(parent, Vector3(0.09, 0.07, 0.055), Vector3(0, 0.05, 0), body, "shell")
	_box(parent, Vector3(0.05, 0.055, 0.048), Vector3(0, 0.02, 0), glass, "shell")
	_cyl(parent, 0.014, 0.018, Vector3(0.02, 0.1, 0), "y", black, 18, "shell")
	_cyl(parent, 0.022, 0.012, Vector3(-0.01, 0.05, 0.028), "z", alum, 24, "shell")
	_cyl(parent, 0.018, 0.002, Vector3(-0.01, 0.05, 0.035), "z", white, 24, "shell")
	_cyl(parent, 0.018, 0.003, Vector3(-0.01, 0.05, 0.037), "z", glass, 24, "shell")

	var needle := Node3D.new()
	needle.name = "Needle"
	needle.position = Vector3(-0.01, 0.05, 0.039)
	parent.add_child(needle)
	_box(needle, Vector3(0.0022, 0.016, 0.001), Vector3(0, 0.008, 0), needle_m, "shell")

	_cyl(parent, 0.01, 0.012, Vector3(0.045, 0.05, 0), "x", brass, 6, "shell")
	_cyl(parent, 0.008, 0.005, Vector3(0.052, 0.05, 0), "x", blue, 16, "shell")
	_cyl(parent, 0.0045, 0.014, Vector3(0.06, 0.05, 0), "x", rubber, 12, "shell")
	info["ports"]["out"] = Vector3(0.07, 0.05, 0)
	info["dirs"]["out"] = Vector3.RIGHT

	var label := Label3D.new()
	label.name = "Tag"
	label.text = el.tag
	label.font_size = 42
	label.pixel_size = 0.0005
	label.modulate = Color(0.93, 0.95, 0.97)
	label.outline_size = 6
	label.position = Vector3(0, 0.095, 0.03)
	label.visible = false # обозначение — во всплывающей подсказке
	parent.add_child(label)
