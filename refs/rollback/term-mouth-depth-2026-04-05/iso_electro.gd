extends RefCounted
## 3D-модули по рефам out/electro_refs/user + DIN 43880.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const EP = preload("res://scripts/view3d/iso_electro_parts.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")

const CAPTION_MAX_CHARS := 14
const CAPTION_MIN_W_MM := 28.0
const CAPTION_MAX_W_MM := 56.0


static func build_din_stop_only(parent: Node3D) -> void:
	_build_stop(parent)


static func build(parent: Node3D, el) -> void:
	var cls := str(el.electro_class)
	match cls:
		"lamp":
			_build_lamp(parent, el)
		"button", "e_stop":
			_build_button(parent, el)
		"switch":
			_build_switch(parent, el)
		"relay":
			_build_relay(parent, el)
		"timer_relay":
			_build_timer(parent, el)
		"voltage_relay", "contactor":
			_build_contactor(parent, el)
		"mcb":
			_build_breaker(parent, el, Color(0.92, 0.78, 0.12)) # жёлтый рычаг
		"rcd":
			_build_breaker(parent, el, Color(0.15, 0.35, 0.85)) # синий рычаг УЗО
		"rcbo":
			_build_breaker(parent, el, Color(0.92, 0.78, 0.12))
		"terminal":
			_build_terminal(parent, el)
		"busbar":
			_build_busbar(parent, el)
		"supply":
			_build_supply(parent, el)
		"psu", "generic_device":
			_build_psu(parent, el)
		"din_socket":
			_build_socket(parent)
		"din_stop":
			_build_stop(parent)
		"thermal":
			_build_thermal(parent)
		"solenoid_coil":
			Parts.add_coil_on_tube(parent, 0.0, 1.0, 0.04)
		_:
			Parts.box(parent, Vector3(Parts.mm(18.0), Parts.mm(85.0), Parts.mm(69.0)), Vector3.ZERO, _ral7035(), "shell")
	# Рентген — только где непрозрачный корпус скрывает нутро.
	# Промежуточное реле (KL): колпак и так прозрачный / белый модуль пустой.
	parent.set_meta("xray_capable", _is_xray_capable(cls))
	var on_door: bool = str(el.electro_mount) == "door"
	if on_door:
		# Наклейка над аппаратом (создаём сразу — иначе легко «не увидеть»).
		_make_caption_plate(parent)
		_sync_caption_plate(parent, el)
	_attach_ports_and_screws(parent, el)
	var label := Label3D.new()
	label.name = "Tag"
	label.text = str(el.tag)
	label.font_size = 20 if on_door else 26
	label.pixel_size = 0.00032 if on_door else 0.00038
	label.modulate = Color(0.12, 0.14, 0.16)
	label.outline_modulate = Color(0.92, 0.94, 0.96)
	label.outline_size = 3
	# На дверце тег чуть сбоку; наклейка с названием — сверху.
	var tag_y: float = Parts.mm(48.0)
	if cls == "relay":
		tag_y = Parts.mm(58.0)
	elif cls == "timer_relay":
		tag_y = Parts.mm(54.0)
	elif cls in ["mcb", "rcd", "rcbo"]:
		tag_y = Parts.mm(52.0)
	elif cls == "psu":
		tag_y = Parts.mm(55.0)
	label.position = Vector3(Parts.mm(18.0), Parts.mm(-2.0), Parts.mm(8.0)) if on_door else Vector3(0, tag_y, Parts.mm(36.0))
	label.visible = false # обозначение — во всплывающей подсказке
	parent.add_child(label)


static func update_state(parent: Node3D, el) -> void:
	if parent == null or el == null:
		return
	parent.set_meta("xray_capable", _is_xray_capable(str(el.electro_class)))
	var tag := parent.get_node_or_null("Tag") as Label3D
	if tag != null and str(tag.text) != str(el.tag):
		tag.text = str(el.tag)
	var bus_cap := parent.get_node_or_null("BusCaption") as Label3D
	if bus_cap != null:
		bus_cap.text = str(el.caption)
	_sync_caption_plate(parent, el)
	var lens_root := parent.get_node_or_null("Lens")
	if lens_root != null:
		var base := _lamp_color(str(el.lamp_color))
		var meshes: Array = []
		if lens_root is MeshInstance3D:
			meshes.append(lens_root)
		else:
			for c in lens_root.get_children():
				if c is MeshInstance3D:
					meshes.append(c)
		for mi in meshes:
			var mat := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if mat == null:
				mat = StandardMaterial3D.new()
				(mi as MeshInstance3D).material_override = mat
			if bool(el.lit):
				mat.albedo_color = Color(base.r, base.g, base.b, 0.92)
				mat.emission_enabled = true
				mat.emission = base
				mat.emission_energy_multiplier = 2.8
			else:
				mat.albedo_color = Color(base.r * 0.75, base.g * 0.75, base.b * 0.75, 0.88)
				mat.emission_enabled = false
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.22
	var head := parent.get_node_or_null("Head") as Node3D
	if head != null:
		var cls_h := str(el.electro_class)
		if cls_h == "switch":
			# Кулачок крутится по положениям; не утапливается как кнопка.
			head.position = Vector3.ZERO
			var pos: int = clampi(int(el.switch_pos), 0, maxi(int(el.switch_positions), 2) - 1)
			head.rotation_degrees = Vector3(0, 0, switch_mark_angle_deg(el, pos))
		else:
			head.rotation_degrees = Vector3.ZERO
			# Головка выступает наружу (+Z); при нажатии утапливается к дверце.
			head.position.z = Parts.mm(-2.5) if bool(el.pressed) else 0.0
	var lever := parent.get_node_or_null("Lever") as Node3D
	if lever != null:
		# Ось X ⊥ боковине: вверх (ON/closed) / вниз (OFF/open), как на рефе FAZ.
		lever.rotation_degrees = Vector3(-35.0 if bool(el.closed) else 35.0, 0, 0)
	var ind := parent.get_node_or_null("PosInd") as MeshInstance3D
	if ind != null:
		var im := ind.material_override as StandardMaterial3D
		if im == null:
			im = StandardMaterial3D.new()
			ind.material_override = im
		im.albedo_color = Color(0.85, 0.15, 0.12) if bool(el.closed) else Color(0.15, 0.65, 0.28)
	var body_glow := parent.get_node_or_null("BodyGlow") as MeshInstance3D
	if body_glow == null:
		body_glow = parent.get_node_or_null("RelayModule/BodyGlow") as MeshInstance3D
	if body_glow != null:
		body_glow.visible = true
		var gm: StandardMaterial3D = body_glow.material_override as StandardMaterial3D
		_status_led_apply(gm, bool(el.energized))
	var plunger := parent.get_node_or_null("Plunger") as Node3D
	if plunger != null:
		plunger.position.y = Parts.mm(-3.0) if bool(el.energized) else 0.0
	var armature := parent.get_node_or_null("RelayModule/Armature") as Node3D
	if armature == null:
		armature = parent.get_node_or_null("Armature") as Node3D
	if armature != null:
		# «Г»: покой — игла упирается в низ КОМ; сработка — КОМ к НО (+Y).
		armature.position.y = Parts.mm(3.6) if bool(el.energized) else 0.0
	var com_bar := parent.get_node_or_null("RelayModule/ComBar") as Node3D
	if com_bar != null:
		com_bar.position.y = Parts.mm(2.0) if bool(el.energized) else Parts.mm(-1.8)
	var dial_on := parent.get_node_or_null("DialOn") as Node3D
	if dial_on != null:
		dial_on.rotation_degrees = Vector3(0, 0, _timer_value_to_dial_deg(float(el.timer_value), int(el.timer_unit)))
	var dial_unit := parent.get_node_or_null("DialUnit") as Node3D
	if dial_unit == null:
		dial_unit = parent.get_node_or_null("DialOff") as Node3D
	if dial_unit != null:
		dial_unit.rotation_degrees = Vector3(0, 0, _timer_unit_to_dial_deg(int(el.timer_unit)))


## Угол засечки шкалы (от +Y к +X): 0 слева (−135°), 10 справа (+135°).
const TIMER_VALUE_ARC_START_DEG := -135.0
const TIMER_VALUE_ARC_SPAN_DEG := 270.0


static func _timer_body_size() -> Vector3:
	# 1.5 модуля = 3 полумодуля × 8.75; −зазор как у реле — без щели к соседу.
	var w: float = Parts.mm(8.75) * 3.0 - Parts.mm(0.9)
	return Vector3(w, Parts.mm(92.0), Parts.mm(78.5))


static func _timer_value_norm(value: float, unit: int) -> float:
	var lim: Vector2 = ElectroLib.timer_value_limits(unit)
	return clampf((clampf(value, lim.x, lim.y) - lim.x) / maxf(lim.y - lim.x, 1.0), 0.0, 1.0)


static func _timer_value_tick_ang_deg(value: float, unit: int = 1) -> float:
	return TIMER_VALUE_ARC_START_DEG + _timer_value_norm(value, unit) * TIMER_VALUE_ARC_SPAN_DEG


static func _timer_value_to_dial_deg(value: float, unit: int = 1) -> float:
	# Метка крутилки в +Y; θ = −ang_засечки, чтобы указатель совпал со шкалой.
	return -_timer_value_tick_ang_deg(value, unit)


static func _timer_unit_tick_ang_deg(unit: int) -> float:
	# мс слева / с сверху / мин справа.
	match clampi(unit, 0, 2):
		0:
			return -90.0
		2:
			return 90.0
		_:
			return 0.0


static func _timer_unit_to_dial_deg(unit: int) -> float:
	return -_timer_unit_tick_ang_deg(unit)


static func _delay_to_dial_deg(sec: float) -> float:
	# Совместимость: секунды на шкале «с» (1…59).
	return _timer_value_to_dial_deg(clampf(sec, 1.0, 59.0), 1)


static func _timer_delay_caption(el) -> String:
	return ElectroLib.timer_format_value(el)


## Позиция наклейки: над своим УГО, но внутри шага DoorGrid (~62 мм), без налезания на соседа сверху.
static func _caption_local_pos(el) -> Vector3:
	var cls := str(el.electro_class)
	match cls:
		"switch":
			# Над лицом 48×48, по центру; y≈31 мм — в пределах DoorGrid pitch/2.
			return Vector3(0.0, Parts.mm(31.0), Parts.mm(6.0))
		"e_stop":
			return Vector3(0.0, Parts.mm(29.0), Parts.mm(6.0))
		"lamp":
			return Vector3(0.0, Parts.mm(28.0), Parts.mm(6.0))
		_:
			# Кнопка: над головкой (~11–16 мм) и ниже середины зазора к соседу (pitch/2).
			return Vector3(0.0, Parts.mm(27.0), Parts.mm(6.0))


static func _fit_caption_text(text: String) -> String:
	if text.length() <= CAPTION_MAX_CHARS:
		return text
	return text.substr(0, CAPTION_MAX_CHARS - 1) + "…"


static func _caption_width_mm(shown: String) -> float:
	var w: float = 14.0 + float(shown.length()) * 3.6
	return clampf(w, CAPTION_MIN_W_MM, CAPTION_MAX_W_MM)


static func _layout_caption_plate(plate: Node3D, shown: String) -> void:
	var w_mm: float = _caption_width_mm(shown)
	var border := plate.get_node_or_null("Border") as MeshInstance3D
	if border != null and border.mesh is BoxMesh:
		var bm := border.mesh as BoxMesh
		bm.size = Vector3(Parts.mm(w_mm), Parts.mm(14.0), Parts.mm(1.0))
	var face := plate.get_node_or_null("Face") as MeshInstance3D
	if face != null and face.mesh is BoxMesh:
		var fm := face.mesh as BoxMesh
		fm.size = Vector3(Parts.mm(w_mm - 4.0), Parts.mm(11.0), Parts.mm(1.2))
	var lab := plate.get_node_or_null("Text") as Label3D
	if lab != null:
		lab.text = shown
		# Чуть мельче на длинных строках, чтобы не вылезать за плитку.
		var n: int = shown.length()
		lab.pixel_size = 0.00026 if n <= 8 else (0.00022 if n <= 12 else 0.00018)


static func _sync_caption_plate(parent: Node3D, el) -> void:
	var plate := parent.get_node_or_null("CaptionPlate") as Node3D
	if str(el.electro_mount) != "door":
		if plate != null:
			plate.visible = false
		return
	var text := str(el.caption).strip_edges()
	# Обозначение (KL1/SB1) — только в tooltip; наклейка лишь при явном caption.
	if plate == null:
		plate = _make_caption_plate(parent)
	plate.position = _caption_local_pos(el)
	plate.visible = text != ""
	if text != "":
		_layout_caption_plate(plate, _fit_caption_text(text))
	var tag := parent.get_node_or_null("Tag") as Label3D
	if tag != null:
		tag.visible = false


static func _make_caption_plate(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "CaptionPlate"
	root.position = Vector3(0.0, Parts.mm(27.0), Parts.mm(6.0))
	parent.add_child(root)
	var border := MeshInstance3D.new()
	border.name = "Border"
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(Parts.mm(50.0), Parts.mm(14.0), Parts.mm(1.0))
	border.mesh = bmesh
	border.material_override = Parts.mat("cap_border", Color(0.12, 0.32, 0.72), 0.15, 0.5)
	root.add_child(border)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(Parts.mm(46.0), Parts.mm(11.0), Parts.mm(1.2))
	face.mesh = fmesh
	face.position = Vector3(0, 0, Parts.mm(0.4))
	face.material_override = Parts.mat("cap_face", Color(0.98, 0.98, 0.99), 0.05, 0.65)
	root.add_child(face)
	var lab := Label3D.new()
	lab.name = "Text"
	lab.text = ""
	lab.font_size = 28
	lab.pixel_size = 0.00026
	lab.modulate = Color(0.06, 0.06, 0.08)
	lab.outline_size = 0
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.position = Vector3(0, 0, Parts.mm(1.1))
	# Текст читается снаружи дверцы (смотрим против +Z).
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root.add_child(lab)
	return root


static func _ral7035() -> StandardMaterial3D:
	return Parts.mat("ral7035", Color(0.78, 0.80, 0.82), 0.12, 0.58)


static func _ral7035_dark() -> StandardMaterial3D:
	return Parts.mat("ral7035d", Color(0.62, 0.64, 0.66), 0.15, 0.55)


static func _term_beige() -> StandardMaterial3D:
	return Parts.mat("term_beige", Color(0.88, 0.86, 0.78), 0.05, 0.62)


static func _green_insert() -> StandardMaterial3D:
	return Parts.mat("term_grn", Color(0.2, 0.55, 0.28), 0.05, 0.55)


## Индикатор катушки (зелёный LED на лице), не «квадрат внутри» на рентгене.
static func _add_status_led(parent: Node3D, pos: Vector3, on: bool) -> MeshInstance3D:
	# Тёмный ободок.
	Parts.cyl(parent, Parts.mm(2.2), Parts.mm(0.6), pos + Vector3(0, 0, -Parts.mm(0.2)), "z", EP.mat_black(), 12, "shell")
	var glow := MeshInstance3D.new()
	glow.name = "BodyGlow"
	var mesh := CylinderMesh.new()
	mesh.top_radius = Parts.mm(1.55)
	mesh.bottom_radius = Parts.mm(1.55)
	mesh.height = Parts.mm(1.1)
	mesh.radial_segments = 14
	glow.mesh = mesh
	glow.position = pos
	glow.rotation_degrees = Vector3(90, 0, 0)
	var gm := StandardMaterial3D.new()
	_status_led_apply(gm, on)
	glow.material_override = gm
	glow.visible = true
	_set_xray(glow, "control")
	parent.add_child(glow)
	return glow


static func _status_led_apply(mat: StandardMaterial3D, on: bool) -> void:
	if mat == null:
		return
	if on:
		mat.albedo_color = Color(0.18, 0.88, 0.32)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.95, 0.35)
		mat.emission_energy_multiplier = 1.35
	else:
		mat.albedo_color = Color(0.08, 0.18, 0.10)
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0
	mat.roughness = 0.35
	mat.metallic = 0.05


## Модульный корпус DIN со ступенчатым лицом (как ВА47 / F202 / RT-SBA).
static func _mod_step_body(parent: Node3D, w: float, h: float, d: float, body: StandardMaterial3D, term_wells: bool = true) -> void:
	EP.mod_step_body_hi(parent, w, h, d, body, term_wells)


## Колодец винтовой клеммы на лице (+Z) + отверстие под провод сверху/снизу.
static func _screw_well(parent: Node3D, pos: Vector3, wire_dir: Vector3) -> void:
	EP.screw_well_face(parent, pos, wire_dir)


static func _is_xray_capable(cls: String) -> bool:
	# KT без нутра — рентген не включаем.
	return cls in [
		"voltage_relay", "contactor", "thermal",
		"mcb", "rcd", "rcbo", "psu",
	]


static func _orange_relay() -> StandardMaterial3D:
	return EP.mat_orange()


static func _lamp_color(name: String) -> Color:
	match name:
		"red":
			return Color(0.9, 0.15, 0.12)
		"green":
			return Color(0.15, 0.75, 0.28)
		"yellow":
			return Color(0.92, 0.82, 0.18)
		_:
			return Color(0.92, 0.93, 0.95)


static func _set_xray(mi: MeshInstance3D, role: String) -> void:
	mi.set_meta("xray_role", role)


static func _screw(parent: Node3D, pos: Vector3, axis: String = "z") -> void:
	Parts.cyl(parent, Parts.mm(2.1), Parts.mm(3.2), pos, axis, Parts.brass(), 8, "shell")
	var tip := pos
	match axis:
		"y", "-y":
			tip += Vector3(0, Parts.mm(2.0) * (1.0 if axis == "y" else -1.0), 0)
		"x", "-x":
			tip += Vector3(Parts.mm(2.0) * (1.0 if axis == "x" else -1.0), 0, 0)
		_:
			tip += Vector3(0, 0, Parts.mm(2.0) * (1.0 if not axis.begins_with("-") else -1.0))
	Parts.cyl(parent, Parts.mm(1.1), Parts.mm(1.0), tip, axis, Parts.alum(), 6, "shell")


static func _port(ports: Dictionary, dirs: Dictionary, name: String, pos: Vector3, dir: Vector3) -> void:
	ports[name] = pos
	dirs[name] = dir.normalized() if dir.length_squared() > 1e-8 else Vector3(0, 0, 1)


## Точка входа провода в зев Finder (не центр винта на лице).
static func _finder_wire_port(screw: Vector3, from_up: bool) -> Vector3:
	var y_sign: float = 1.0 if from_up else -1.0
	# Центр наружной кромки зева: колодец +4 мм по Y, полувысота 1.6 мм → ~5.6 мм; зев утоплен на −2.5 мм по Z.
	return screw + Vector3(0.0, y_sign * Parts.mm(5.6), -Parts.mm(2.5))


static func _attach_ports_and_screws(parent: Node3D, el) -> void:
	var ports: Dictionary = {}
	var dirs: Dictionary = {}
	var cls := str(el.electro_class)
	var mount := str(el.electro_mount)
	match cls:
		"lamp":
			# Клеммы на задней части корпуса (−Z).
			_screw(parent, Vector3(Parts.mm(-4.0), Parts.mm(0), Parts.mm(-48.0)), "z")
			_screw(parent, Vector3(Parts.mm(4.0), Parts.mm(0), Parts.mm(-48.0)), "z")
			_port(ports, dirs, "X1", Vector3(Parts.mm(-4.0), 0, Parts.mm(-50.0)), Vector3(0, 0, -1))
			_port(ports, dirs, "X2", Vector3(Parts.mm(4.0), 0, Parts.mm(-50.0)), Vector3(0, 0, -1))
		"button", "e_stop":
			_screw(parent, Vector3(Parts.mm(-5.0), 0, Parts.mm(-42.0)), "z")
			_screw(parent, Vector3(Parts.mm(5.0), 0, Parts.mm(-42.0)), "z")
			_port(ports, dirs, "1", Vector3(Parts.mm(-5.0), 0, Parts.mm(-44.0)), Vector3(0, 0, -1))
			_port(ports, dirs, "2", Vector3(Parts.mm(5.0), 0, Parts.mm(-44.0)), Vector3(0, 0, -1))
			# Якоря для членов-контактов группы (провода 3D).
			for i in 4:
				var y: float = Parts.mm(-6.0) * float(i)
				_port(ports, dirs, "C%dA" % (i + 1), Vector3(Parts.mm(-6.0), y, Parts.mm(-44.0)), Vector3(0, 0, -1))
				_port(ports, dirs, "C%dB" % (i + 1), Vector3(Parts.mm(6.0), y, Parts.mm(-44.0)), Vector3(0, 0, -1))
		"switch":
			for i in 4:
				var x: float = -Parts.mm(12.0) + float(i) * Parts.mm(8.0)
				_screw(parent, Vector3(x, Parts.mm(14.0), Parts.mm(-38.0)), "z")
				_port(ports, dirs, str(i * 2 + 1), Vector3(x, Parts.mm(14.0), Parts.mm(-40.0)), Vector3(0, 0, -1))
				_screw(parent, Vector3(x, Parts.mm(-14.0), Parts.mm(-38.0)), "z")
				_port(ports, dirs, str(i * 2 + 2), Vector3(x, Parts.mm(-14.0), Parts.mm(-40.0)), Vector3(0, 0, -1))
		"mcb", "rcd", "rcbo":
			# FAZ / DFS2: линия сверху, нагрузка снизу.
			var poles: int = maxi(int(el.poles), 1)
			if cls in ["rcd", "rcbo"]:
				poles = maxi(poles, 2)
			var w: float = Parts.mm(18.0) if (cls == "mcb" and poles == 1) else Parts.mm(17.5) * float(poles)
			if cls == "rcd" and poles == 2:
				w = Parts.mm(36.0)
			var h: float = Parts.mm(92.0) if cls == "mcb" else Parts.mm(85.0)
			var d: float = Parts.mm(78.5) if cls == "mcb" else (Parts.mm(75.0) if cls in ["rcd", "rcbo"] else Parts.mm(72.0))
			var pitch: float = w / float(poles)
			for i in poles:
				var x: float = -w * 0.5 + pitch * 0.5 + float(i) * pitch
				_port(ports, dirs, str(i * 2 + 1), Vector3(x, h * 0.42, d * 0.32), Vector3(0, 1, 0))
				_port(ports, dirs, str(i * 2 + 2), Vector3(x, -h * 0.42, d * 0.32), Vector3(0, -1, 0))
			if cls in ["rcd", "rcbo"]:
				_port(ports, dirs, "N", Vector3(w * 0.25, h * 0.48, d * 0.28), Vector3(0, 1, 0))
				_port(ports, dirs, "N2", Vector3(w * 0.25, -h * 0.48, d * 0.28), Vector3(0, -1, 0))
		"timer_relay":
			# Зев Finder ±Y (подсветка 5.5×2.6×5.0); винт на +Z лица колодки.
			var tsz: Vector3 = _timer_body_size()
			var th: float = tsz.y
			var td: float = tsz.z
			var ty_top: float = th * 0.42
			var ty_bot: float = -th * 0.42
			var term_d: float = Parts.mm(14.0)
			var step_z: float = td * 0.10
			var screw_z: float = step_z + term_d - Parts.mm(0.5)
			var mouth_y: float = Parts.mm(3.8)
			var mouth_z: float = screw_z - Parts.mm(2.2)
			_port(ports, dirs, "A1", Vector3(-Parts.mm(5.0), ty_top + mouth_y, mouth_z), Vector3(0, 1, 0))
			_port(ports, dirs, "A2", Vector3(Parts.mm(5.0), ty_top + mouth_y, mouth_z), Vector3(0, 1, 0))
			_port(ports, dirs, "NO", Vector3(-Parts.mm(7.0), ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "COM", Vector3(0.0, ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "NC", Vector3(Parts.mm(7.0), ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "C1A", Vector3(0.0, ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "C1B", Vector3(-Parts.mm(7.0), ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "15", Vector3(0.0, ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "18", Vector3(-Parts.mm(7.0), ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
			_port(ports, dirs, "16", Vector3(Parts.mm(7.0), ty_bot - mouth_y, mouth_z), Vector3(0, -1, 0))
		"relay", "voltage_relay":
			# Лестница Finder: COM/NO/NC сверху, A1/A2 снизу; провод ±Y в зев, не в винт.
			var n_p: int = _relay_pole_count(el)
			var rw: float = _relay_body_width_mm(n_p)
			var px: float = rw / (float(n_p) + 0.5)
			if n_p <= 1:
				# 1CO: A1/A2 на разных ступеньках по Y/Z.
				_port(ports, dirs, "A1", _finder_wire_port(Vector3(0, -Parts.mm(30.0), Parts.mm(6.0)), false), Vector3(0, -1, 0))
				_port(ports, dirs, "A2", _finder_wire_port(Vector3(0, -Parts.mm(40.0), Parts.mm(-2.0)), false), Vector3(0, -1, 0))
			else:
				var a_dx: float = minf(Parts.mm(6.0), rw * 0.32)
				_port(ports, dirs, "A1", _finder_wire_port(Vector3(-a_dx, -Parts.mm(36.0), Parts.mm(2.0)), false), Vector3(0, -1, 0))
				_port(ports, dirs, "A2", _finder_wire_port(Vector3(a_dx, -Parts.mm(36.0), Parts.mm(2.0)), false), Vector3(0, -1, 0))
			var ladder: String = relay_ladder_mode(el)
			var units_p: Array = relay_contact_units_info(el)
			# К модулю→наружу: НЗ / НО / КОМ (pair: контакт / общий).
			if ladder == "co":
				var row_zs: Array = [Parts.mm(14.0), Parts.mm(6.0), Parts.mm(-2.0)]
				var row_ys: Array = [Parts.mm(26.0), Parts.mm(36.0), Parts.mm(46.0)]
				var role_keys: Array = ["nc", "no", "com"]
				for i in n_p:
					var u: Dictionary = units_p[i] if i < units_p.size() else {"kind": "co", "com": str(11 + i * 10), "no": str(14 + i * 10), "nc": str(12 + i * 10)}
					var kind_i: String = str(u.get("kind", "co"))
					var x2: float = (float(i) - float(n_p - 1) * 0.5) * px
					for ri in 3:
						var role: String = str(role_keys[ri])
						if not _relay_unit_has_role(kind_i, role):
							continue
						var term: String = str(u.get(role, ""))
						if term == "":
							continue
						var screw_p: Vector3 = Vector3(x2, float(row_ys[ri]), float(row_zs[ri]))
						_port(ports, dirs, term, _finder_wire_port(screw_p, true), Vector3(0, 1, 0))
					# Алиасы члена-контакта: A=COM (край), B=NO или NC.
					var com_ri: int = 2
					var sw_ri: int = 1 if kind_i != "nc" else 0
					_port(ports, dirs, "C%dA" % (i + 1), _finder_wire_port(Vector3(x2 - Parts.mm(2.0), float(row_ys[com_ri]), float(row_zs[com_ri])), true), Vector3(0, 1, 0))
					_port(ports, dirs, "C%dB" % (i + 1), _finder_wire_port(Vector3(x2 + Parts.mm(2.0), float(row_ys[sw_ri]), float(row_zs[sw_ri])), true), Vector3(0, 1, 0))
			else:
				var row_zs2: Array = [Parts.mm(12.0), Parts.mm(2.0)]
				var row_ys2: Array = [Parts.mm(32.0), Parts.mm(44.0)]
				for i2 in n_p:
					var u2: Dictionary = units_p[i2] if i2 < units_p.size() else {"kind": "no", "com": str(13 + i2 * 10), "no": str(14 + i2 * 10), "nc": ""}
					var kind2: String = str(u2.get("kind", "no"))
					var x3: float = (float(i2) - float(n_p - 1) * 0.5) * px
					var near_key: String = "nc" if kind2 == "nc" else "no"
					var near_nm: String = str(u2.get(near_key, ""))
					var far_nm: String = str(u2.get("com", ""))
					if near_nm != "":
						_port(ports, dirs, near_nm, _finder_wire_port(Vector3(x3, float(row_ys2[0]), float(row_zs2[0])), true), Vector3(0, 1, 0))
					if far_nm != "":
						_port(ports, dirs, far_nm, _finder_wire_port(Vector3(x3, float(row_ys2[1]), float(row_zs2[1])), true), Vector3(0, 1, 0))
					_port(ports, dirs, "C%dA" % (i2 + 1), _finder_wire_port(Vector3(x3 - Parts.mm(2.0), float(row_ys2[1]), float(row_zs2[1])), true), Vector3(0, 1, 0))
					_port(ports, dirs, "C%dB" % (i2 + 1), _finder_wire_port(Vector3(x3 + Parts.mm(2.0), float(row_ys2[0]), float(row_zs2[0])), true), Vector3(0, 1, 0))
		"contactor":
			# КМИ-10910: 1/3/5 сверху, 2/4/6 снизу; A1/A2 на лице.
			var ch: float = Parts.mm(75.0)
			var cd: float = Parts.mm(80.0)
			var cw: float = Parts.mm(45.0)
			_port(ports, dirs, "A1", Vector3(-cw * 0.28, -ch * 0.08, cd * 0.48), Vector3(0, 0, 1))
			_port(ports, dirs, "A2", Vector3(cw * 0.28, -ch * 0.08, cd * 0.48), Vector3(0, 0, 1))
			for i in 3:
				var x3: float = (float(i) - 1.0) * Parts.mm(12.0)
				_port(ports, dirs, str(i * 2 + 1), Vector3(x3, ch * 0.42, cd * 0.32), Vector3(0, 1, 0))
				_port(ports, dirs, str(i * 2 + 2), Vector3(x3, -ch * 0.42, cd * 0.32), Vector3(0, -1, 0))
				_port(ports, dirs, "T%d" % (i + 1), Vector3(x3, ch * 0.42, cd * 0.32), Vector3(0, 1, 0))
				_port(ports, dirs, "T%d" % (i + 4), Vector3(x3, -ch * 0.42, cd * 0.32), Vector3(0, -1, 0))
				_port(ports, dirs, "C%dA" % (i + 1), Vector3(x3 - Parts.mm(3.0), ch * 0.42, cd * 0.32), Vector3(0, 1, 0))
				_port(ports, dirs, "C%dB" % (i + 1), Vector3(x3 + Parts.mm(3.0), -ch * 0.42, cd * 0.32), Vector3(0, -1, 0))
		"terminal":
			# Feed-through: имя / имяb с торцов ±Z (как на 2D таблице).
			var tdefs: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
			var tn: int = maxi(tdefs.size(), 1)
			var tpitch: float = Parts.mm(8.75)
			var tw: float = tpitch * float(tn)
			for ti in tn:
				var tx: float = -tw * 0.5 + tpitch * 0.5 + float(ti) * tpitch
				var tnm: String = str(ti + 1)
				if ti < tdefs.size() and typeof(tdefs[ti]) == TYPE_DICTIONARY:
					tnm = str(tdefs[ti].get("name", tnm))
				_port(ports, dirs, tnm, Vector3(tx, Parts.mm(10.0), Parts.mm(18.0)), Vector3(0, 0, 1))
				_port(ports, dirs, "%sb" % tnm, Vector3(tx, Parts.mm(10.0), -Parts.mm(18.0)), Vector3(0, 0, -1))
		"busbar":
			var n: int = maxi(el.electro_ports.size(), 4)
			var pitch: float = Parts.mm(10.0)
			var len_y: float = pitch * float(n) + Parts.mm(4.0)
			for i in n:
				var y: float = -len_y * 0.5 + Parts.mm(2.0) + float(i) * pitch + pitch * 0.5
				_port(ports, dirs, str(i + 1), Vector3(Parts.mm(-5.0), y, Parts.mm(10.0)), Vector3(-1, 0, 0))
		"supply":
			var supply_names: Array = []
			if int(el.poles) >= 3:
				supply_names = ["L1", "L2", "L3", "N"]
			else:
				supply_names = ["L", "N", "PE"]
			var sn: int = supply_names.size()
			for i in sn:
				var x: float = -Parts.mm(10.0) * float(sn - 1) * 0.5 + float(i) * Parts.mm(10.0)
				_port(ports, dirs, str(supply_names[i]), Vector3(x, Parts.mm(20.0), Parts.mm(32.0)), Vector3(0, 0, 1))
		"psu", "generic_device":
			# DRA-60: клеммы на лице, провод входит спереди (+Z), не сквозь панель снизу.
			var h_psu: float = Parts.mm(90.0)
			var d_psu: float = Parts.mm(58.0)
			var psu_in: Array = ["L", "N", "PE"]
			for i in 3:
				var x: float = Parts.mm(10.0) - float(i) * Parts.mm(10.0)
				_port(ports, dirs, str(psu_in[i]), Vector3(x, -h_psu * 0.38, d_psu * 0.55), Vector3(0, 0, 1))
			_port(ports, dirs, "+24", Vector3(-Parts.mm(8.0), h_psu * 0.38, d_psu * 0.55), Vector3(0, 0, 1))
			_port(ports, dirs, "0", Vector3(Parts.mm(8.0), h_psu * 0.38, d_psu * 0.55), Vector3(0, 0, 1))
		"din_socket":
			var sock_names: Array = ["L", "N", "PE"]
			for i in 3:
				var xs: float = -Parts.mm(12.0) + float(i) * Parts.mm(12.0)
				_port(ports, dirs, str(sock_names[i]), Vector3(xs, Parts.mm(-32.0), Parts.mm(8.0)), Vector3(0, -1, 0))
		"thermal":
			# PTA: пины снизу в КМ (вход), силовые винты сверху к двигателю (выход).
			for i in 3:
				var x: float = -Parts.mm(12.0) + float(i) * Parts.mm(12.0)
				_port(ports, dirs, str(i * 2 + 1), Vector3(x, Parts.mm(-8.0), -Parts.mm(20.0)), Vector3(0, -1, 0))
				_port(ports, dirs, str(i * 2 + 2), Vector3(x, Parts.mm(28.0), Parts.mm(20.0)), Vector3(0, 1, 0))
		_:
			pass
	# На дверце порты смотрят внутрь щита (−Z локально).
	if mount == "door" and not ports.is_empty():
		pass
	parent.set_meta("ports", ports)
	parent.set_meta("dirs", dirs)


static func _build_lamp(parent: Node3D, el) -> void:
	# Декрафт / EKF AD22: чёрный корпус за панелью, шестигранник, цветная линза снаружи.
	var black := Parts.mat("lamp_body", Color(0.07, 0.07, 0.08), 0.05, 0.62)
	var rim := Parts.mat("lamp_rim", Color(0.12, 0.12, 0.13), 0.08, 0.45)
	# Корпус (−Z) стыкуется с шестигранником у z≈0 (без воздушного зазора).
	Parts.cyl(parent, Parts.mm(9.5), Parts.mm(53.0), Vector3(0, 0, Parts.mm(-26.5)), "z", black, 22, "shell")
	# Шестигранная гайка на лице панели.
	Parts.cyl(parent, Parts.mm(14.5), Parts.mm(5.5), Vector3(0, 0, Parts.mm(2.5)), "z", black, 6, "shell")
	# Обод под линзу.
	Parts.cyl(parent, Parts.mm(12.8), Parts.mm(3.5), Vector3(0, 0, Parts.mm(7.0)), "z", rim, 22, "shell")
	var lens_root := Node3D.new()
	lens_root.name = "Lens"
	parent.add_child(lens_root)
	var col := _lamp_color(str(el.lamp_color))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.88)
	mat.roughness = 0.22
	mat.metallic = 0.05
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Цветная линза — короткий цилиндр (не сплюснутая сфера).
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = Parts.mm(11.0)
	mesh.bottom_radius = Parts.mm(11.8)
	mesh.height = Parts.mm(11.0)
	mesh.radial_segments = 28
	body.mesh = mesh
	body.position = Vector3(0, 0, Parts.mm(14.5))
	body.rotation_degrees = Vector3(90, 0, 0)
	body.material_override = mat
	_set_xray(body, "internal")
	lens_root.add_child(body)
	# Плоский торец линзы.
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = Parts.mm(10.6)
	cap_mesh.bottom_radius = Parts.mm(10.6)
	cap_mesh.height = Parts.mm(2.2)
	cap_mesh.radial_segments = 28
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0, Parts.mm(20.6))
	cap.rotation_degrees = Vector3(90, 0, 0)
	cap.material_override = mat
	_set_xray(cap, "internal")
	lens_root.add_child(cap)


static func _btn_mat(name: String) -> StandardMaterial3D:
	match name:
		"red":
			return Parts.red_btn()
		"green":
			return Parts.mat("btn_g", Color(0.12, 0.72, 0.28), 0.08, 0.45)
		"yellow":
			return Parts.mat("btn_y", Color(0.92, 0.82, 0.12), 0.08, 0.45)
		"black":
			return Parts.mat("btn_k", Color(0.12, 0.12, 0.14), 0.15, 0.4)
		"blue":
			return Parts.mat("btn_b", Color(0.15, 0.35, 0.85), 0.08, 0.45)
		_:
			return Parts.mat("btn_w", Color(0.95, 0.95, 0.97), 0.05, 0.42)


static func _build_button(parent: Node3D, el) -> void:
	# Блок контактов за панелью (−Z) → фланец у z≈0 → клавиша наружу (+Z).
	var is_estop := str(el.electro_class) == "e_stop"
	Parts.cyl(parent, Parts.mm(11.0), Parts.mm(42.0), Vector3(0, 0, Parts.mm(-25.0)), "z", Parts.mat("btn_body", Color(0.12, 0.12, 0.14), 0.1, 0.55), 20, "shell")
	Parts.cyl(parent, Parts.mm(16.0), Parts.mm(8.0), Vector3(0, 0, Parts.mm(0.0)), "z", _ral7035(), 20, "shell")
	var head := Node3D.new()
	head.name = "Head"
	parent.add_child(head)
	var col_name := "red" if is_estop else str(el.btn_color)
	var col := _btn_mat(col_name)
	var r := Parts.mm(18.0) if is_estop else Parts.mm(11.0)
	var h := Parts.mm(12.0) if is_estop else Parts.mm(8.0)
	Parts.cyl(head, r, h, Vector3(0, 0, Parts.mm(6.0)), "z", col, 20, "actuator")
	if is_estop:
		Parts.cyl(head, Parts.mm(8.0), Parts.mm(4.0), Vector3(0, 0, Parts.mm(13.0)), "z", Parts.red_btn(), 12, "actuator")
		Parts.cyl(parent, Parts.mm(20.0), Parts.mm(3.0), Vector3(0, 0, Parts.mm(1.0)), "z", Parts.mat("estop_ring", Color(0.9, 0.9, 0.92), 0.05, 0.5), 20, "shell")


## Угол риска положения на лице SA (−55…+55°, 0 = вверх / +Y).
static func switch_mark_angle_deg(el, pos: int) -> float:
	var npos: int = maxi(int(el.switch_positions), 2)
	var p: int = clampi(pos, 0, npos - 1)
	var t: float = float(p) / float(maxi(npos - 1, 1))
	return lerpf(-55.0, 55.0, t)


## Положение SA по точке клика в локали модуля (XY лица, +Y вверх к средней риске).
static func switch_pos_from_local_hit(el, local: Vector3) -> int:
	var npos: int = maxi(int(el.switch_positions), 2)
	var ang_deg: float = rad_to_deg(atan2(local.x, local.y))
	var best: int = 0
	var best_d: float = 1.0e9
	for i in npos:
		var d: float = absf(ang_deg - switch_mark_angle_deg(el, i))
		if d < best_d:
			best_d = d
			best = i
	return best


static func _build_switch(parent: Node3D, el) -> void:
	# Кулачковый: панель на дверце (+z наружу), пакет контактов внутрь (−z), стык у z=0.
	Parts.box(parent, Vector3(Parts.mm(48.0), Parts.mm(48.0), Parts.mm(4.0)), Vector3(0, 0, Parts.mm(2.0)), Parts.mat("sa_face", Color(0.94, 0.94, 0.96), 0.05, 0.55), "shell")
	Parts.box(parent, Vector3(Parts.mm(36.0), Parts.mm(36.0), Parts.mm(40.0)), Vector3(0, 0, Parts.mm(-20.0)), Parts.black(), "shell")
	# Риски положений на лице — видно, куда смотрит клювик.
	var npos: int = maxi(int(el.switch_positions), 2)
	var mark := Parts.mat("sa_mark", Color(0.15, 0.15, 0.17), 0.1, 0.45)
	for i in npos:
		var ang: float = deg_to_rad(switch_mark_angle_deg(el, i))
		var r: float = Parts.mm(18.0)
		var mx: float = sin(ang) * r
		var my: float = cos(ang) * r
		Parts.box(parent, Vector3(Parts.mm(2.2), Parts.mm(5.0), Parts.mm(1.2)), Vector3(mx, my, Parts.mm(4.2)), mark, "shell")
	var head := Node3D.new()
	head.name = "Head"
	parent.add_child(head)
	Parts.cyl(head, Parts.mm(10.0), Parts.mm(12.0), Vector3(0, 0, Parts.mm(9.0)), "z", Parts.black(), 14, "actuator")
	# Клювик / указатель: вдоль +Y головы (при angle=0 смотрит вверх к средней риске).
	Parts.box(head, Vector3(Parts.mm(3.5), Parts.mm(18.0), Parts.mm(3.5)), Vector3(0, Parts.mm(8.0), Parts.mm(15.0)), Parts.mat("sa_beak", Color(0.92, 0.55, 0.12), 0.08, 0.45), "actuator")
	Parts.cyl(head, Parts.mm(3.0), Parts.mm(2.0), Vector3(0, 0, Parts.mm(15.5)), "z", Parts.alum(), 10, "actuator")


## Число единиц контактов (перекидных / пар) по текущим contact_defs.
static func relay_pole_count(el) -> int:
	if el == null:
		return 1
	var contacts: Array = el.contact_defs if typeof(el.contact_defs) == TYPE_ARRAY else []
	if contacts.is_empty():
		var rid: String = str(el.recipe_id)
		if rid.find("4c") >= 0:
			return 4
		if rid.find("1c") >= 0:
			return 1
		if rid.find("2c") >= 0:
			return 2
		return 1
	var n: int = 0
	var i: int = 0
	while i < contacts.size():
		var a: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		var t: String = str(a.get("type", "no"))
		if t == "co":
			i += mini(3, contacts.size() - i)
			n += 1
			continue
		if i + 1 < contacts.size():
			var b: Dictionary = contacts[i + 1] if typeof(contacts[i + 1]) == TYPE_DICTIONARY else {}
			if str(b.get("type", "")) == t:
				i += 2
			else:
				i += 1
		else:
			i += 1
		n += 1
	return maxi(n, 1)


static func _relay_pole_count(el) -> int:
	return relay_pole_count(el)


## Полумодули DIN под число контактов.
static func relay_din_slots(el) -> int:
	var n: int = relay_pole_count(el)
	if n <= 1:
		return 1
	if n == 2:
		return 2
	if n == 3:
		return 3
	if n == 4:
		return 3 # Finder ≈ 27 мм ≈ 3×8.75
	return clampi(n, 4, 10)


static func _relay_body_width_mm(n_poles: int) -> float:
	# Ширина слота минус зазор — соседние реле не сливаются в один блок.
	var slots: int = 1
	if n_poles == 2:
		slots = 2
	elif n_poles == 3:
		slots = 3
	elif n_poles == 4:
		slots = 3
	elif n_poles > 4:
		slots = clampi(n_poles, 4, 10)
	var gap: float = Parts.mm(0.9)
	return Parts.mm(8.75) * float(slots) - gap


## Нутро только у стандартных 2CO / 4CO (все единицы — перекидные).
static func _relay_use_detailed_module(el) -> bool:
	var n: int = relay_pole_count(el)
	if n != 2 and n != 4:
		return false
	var contacts: Array = el.contact_defs if el != null and typeof(el.contact_defs) == TYPE_ARRAY else []
	if contacts.is_empty():
		return true
	var i: int = 0
	var units: int = 0
	while i < contacts.size():
		var a: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		if str(a.get("type", "")) != "co":
			return false
		i += mini(3, contacts.size() - i)
		units += 1
	return units == n


static func relay_contact_fingerprint(el) -> String:
	if el == null or typeof(el.contact_defs) != TYPE_ARRAY:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for d in el.contact_defs:
		if typeof(d) == TYPE_DICTIONARY:
			parts.append("%s:%s" % [str(d.get("name", "")), str(d.get("type", ""))])
	return ",".join(parts)


## Виды единиц контактов: "co" | "no" | "nc".
static func relay_contact_kinds(el) -> Array:
	var out: Array = []
	if el == null or typeof(el.contact_defs) != TYPE_ARRAY:
		return out
	var contacts: Array = el.contact_defs
	var i: int = 0
	while i < contacts.size():
		var a: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		var t: String = str(a.get("type", "no"))
		if t == "co":
			out.append("co")
			i += mini(3, contacts.size() - i)
			continue
		if t == "nc":
			out.append("nc")
		else:
			out.append("no")
		if i + 1 < contacts.size():
			var b: Dictionary = contacts[i + 1] if typeof(contacts[i + 1]) == TYPE_DICTIONARY else {}
			if str(b.get("type", "")) == t:
				i += 2
			else:
				i += 1
		else:
			i += 1
	return out


## Режим лесенки клемм: "co" (3 ступени) или "pair" (2 ступени НО/НЗ).
static func relay_ladder_mode(el) -> String:
	var kinds: Array = relay_contact_kinds(el)
	if kinds.is_empty():
		# Пустые defs — по рецепту; иначе пара (безопаснее, чем рисовать NC зря).
		var rid: String = str(el.recipe_id) if el != null else ""
		if rid.find("4c") >= 0 or rid.find("2c") >= 0 or rid.find("1c") >= 0:
			return "co"
		return "pair"
	for k in kinds:
		if str(k) == "co":
			return "co"
	return "pair"


## Единицы контактов: [{kind, com, no, nc}] — имена клемм по ролям (пустые если нет).
static func relay_contact_units_info(el) -> Array:
	var out: Array = []
	if el == null or typeof(el.contact_defs) != TYPE_ARRAY:
		return out
	var contacts: Array = el.contact_defs
	var i: int = 0
	while i < contacts.size():
		var a: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		var t: String = str(a.get("type", "no"))
		var info: Dictionary = {"kind": "no", "com": "", "no": "", "nc": ""}
		if t == "co":
			info["kind"] = "co"
			info["com"] = str(a.get("name", ""))
			var take: int = mini(3, contacts.size() - i)
			for j in range(1, take):
				var d: Dictionary = contacts[i + j] if typeof(contacts[i + j]) == TYPE_DICTIONARY else {}
				var tj: String = str(d.get("type", ""))
				if tj == "nc":
					info["nc"] = str(d.get("name", ""))
				elif tj == "no":
					info["no"] = str(d.get("name", ""))
			if str(info["nc"]) == "":
				info["nc"] = str(int(str(info["com"])) + 1) if str(info["com"]).is_valid_int() else ""
			if str(info["no"]) == "":
				info["no"] = str(int(str(info["com"])) + 3) if str(info["com"]).is_valid_int() else ""
			out.append(info)
			i += take
			continue
		info["kind"] = "nc" if t == "nc" else "no"
		var n0: String = str(a.get("name", ""))
		var n1: String = ""
		if i + 1 < contacts.size():
			var b: Dictionary = contacts[i + 1] if typeof(contacts[i + 1]) == TYPE_DICTIONARY else {}
			if str(b.get("type", "")) == t:
				n1 = str(b.get("name", ""))
				i += 2
			else:
				i += 1
		else:
			i += 1
		if info["kind"] == "nc":
			info["com"] = n0
			info["nc"] = n1 if n1 != "" else n0
		else:
			info["com"] = n0
			info["no"] = n1 if n1 != "" else n0
		out.append(info)
	return out


## Нужна ли клемма роли на данной единице (винт/зев).
static func _relay_unit_has_role(kind: String, role: String) -> bool:
	if role == "com":
		return true
	if kind == "co":
		return role == "no" or role == "nc"
	if kind == "no":
		return role == "no"
	if kind == "nc":
		return role == "nc"
	return false


## Tip-порт 3D (на primary) → имя порта УГО контакта; иначе "".
static func tip_to_contact_scheme_port(tip: String, contact_el) -> String:
	if tip == "" or contact_el == null:
		return ""
	var names: Array = []
	var defs: Array = contact_el.contact_defs if typeof(contact_el.contact_defs) == TYPE_ARRAY else []
	for d in defs:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var nm: String = str(d.get("name", ""))
		if nm != "":
			names.append(nm)
	if names.is_empty():
		return ""
	if names.has(tip):
		return tip
	var alias: String = ""
	match tip:
		"15":
			alias = "COM"
		"16":
			alias = "NC"
		"18":
			alias = "NO"
		"COM":
			alias = "15"
		"NC":
			alias = "16"
		"NO":
			alias = "18"
		_:
			alias = ""
	if alias != "" and names.has(alias):
		return alias
	var idx: int = maxi(int(contact_el.member_index), 1)
	if tip.begins_with("C") and tip.length() >= 3:
		var num_s: String = ""
		for ci in range(1, tip.length()):
			var ch: String = tip.substr(ci, 1)
			if ch >= "0" and ch <= "9":
				num_s += ch
			else:
				break
		if num_s == "" or int(num_s) != idx:
			return ""
		var suffix: String = tip.substr(tip.length() - 1, 1)
		if suffix == "A":
			return str(names[0])
		if suffix == "B":
			if names.size() >= 3:
				return str(names[2])
			if names.size() >= 2:
				return str(names[1])
			return str(names[0])
		return ""
	if tip.begins_with("T") and tip.substr(1).is_valid_int():
		if int(tip.substr(1)) != idx:
			return ""
		return str(names[0])
	return ""


## 3D клемма (часто на primary) → {id, port} для провода на схеме.
static func resolve_scheme_wire_end(circuit, el_id: int, tip_port: String) -> Dictionary:
	if circuit == null or el_id < 0 or tip_port == "":
		return {}
	var el = circuit.get_element(el_id)
	if el == null:
		return {}
	var gid: int = int(el.id)
	if str(el.member_role) == "contact" and int(el.group_id) >= 0:
		gid = int(el.group_id)
	elif int(el.group_id) >= 0:
		gid = int(el.group_id)
	# Сначала клеммы контактов группы (на схеме у members, в 3D — на primary).
	for m in circuit.electro_group_members(gid):
		if str(m.member_role) != "contact":
			continue
		var mapped: String = tip_to_contact_scheme_port(tip_port, m)
		if mapped != "":
			return {"id": int(m.id), "port": mapped}
	# A1/A2, АВ, клеммник и т.п. — порт на самом элементе.
	return {"id": el_id, "port": tip_port}


## Роль клеммы для тултипа: COM / NO / NC / "" .
static func port_contact_role(el, port_name: String) -> String:
	var nm: String = str(port_name)
	if nm == "A1" or nm == "A2":
		return ""
	if el != null and typeof(el.contact_defs) == TYPE_ARRAY:
		for d in el.contact_defs:
			if typeof(d) != TYPE_DICTIONARY:
				continue
			if str(d.get("name", "")) != nm:
				continue
			var t: String = str(d.get("type", ""))
			if t == "co":
				return "COM"
			if t == "nc":
				return "NC"
			if t == "no":
				return "NO"
	if nm.is_valid_int():
		var dig: int = int(nm) % 10
		if dig == 1:
			return "COM"
		if dig == 2:
			return "NC"
		if dig == 3 or dig == 4:
			return "NO"
	return ""


static func _relay_socket_mat(parent: Node3D) -> StandardMaterial3D:
	# Тон 0/1 — индекс соседа на DIN (не номер слота: ширины разные).
	var shade: int = 0
	if parent != null:
		shade = int(parent.get_meta("din_shade", 0))
	# Слабый контраст — едва заметное чередование.
	if shade == 1:
		return Parts.mat("ep_fnd_bl_b", Color(0.15, 0.32, 0.74), 0.08, 0.48)
	return Parts.mat("ep_fnd_bl_a", Color(0.12, 0.28, 0.68), 0.08, 0.50)


static func _timer_body_mat(parent: Node3D) -> StandardMaterial3D:
	# Чередование RAL7035 у соседних KT на DIN — как у колодок реле.
	var shade: int = 0
	if parent != null:
		shade = int(parent.get_meta("din_shade", 0))
	if shade == 1:
		return Parts.mat("kt_body_b", Color(0.70, 0.72, 0.75), 0.12, 0.56)
	return Parts.mat("kt_body_a", Color(0.78, 0.80, 0.82), 0.12, 0.58)


static func _timer_face_mat(parent: Node3D) -> StandardMaterial3D:
	# Лицо чуть светлее корпуса (не чисто белое), с тем же чередованием тона.
	var shade: int = 0
	if parent != null:
		shade = int(parent.get_meta("din_shade", 0))
	if shade == 1:
		return Parts.mat("kt_face_b", Color(0.84, 0.85, 0.87), 0.08, 0.62)
	return Parts.mat("kt_face_a", Color(0.90, 0.91, 0.92), 0.08, 0.64)


static func _build_relay(parent: Node3D, el) -> void:
	# Finder 94.04 / 58.34 — вариант A. Модуль между лесенкой и A1/A2.
	# Стандарт 2CO/4CO — нутро; иначе белый модуль. Ширина/винты — по contact_defs.
	var n_poles: int = _relay_pole_count(el)
	var w: float = _relay_body_width_mm(n_poles)
	var pitch_x: float = w / (float(n_poles) + 0.5)
	var blue: StandardMaterial3D = _relay_socket_mat(parent)
	var z_back: float = -Parts.mm(38.0)
	var ladder_mode: String = relay_ladder_mode(el)
	# Нутро только у стандартных перекидных; НО/НЗ — белый корпус и пара ступеней.
	var detailed: bool = _relay_use_detailed_module(el) and ladder_mode == "co"

	var socket := Node3D.new()
	socket.name = "Socket"
	parent.add_child(socket)

	Parts.box(socket, Vector3(w, Parts.mm(90.0), Parts.mm(10.0)), Vector3(0, 0, z_back + Parts.mm(5.0)), blue, "shell")
	EP.din_clip_grey(socket, Vector3(0, -Parts.mm(6.0), z_back - Parts.mm(2.0)), w * 0.9)

	# Площадка под реле.
	var seat_z: float = Parts.mm(-2.0)
	var seat_y: float = Parts.mm(-2.0)
	Parts.box(socket, Vector3(w, Parts.mm(40.0), Parts.mm(32.0)), Vector3(0, seat_y, z_back + Parts.mm(26.0)), blue, "shell")
	# Сплошное лицо площадки (без тёмного «выреза»).
	Parts.box(socket, Vector3(w, Parts.mm(40.0), Parts.mm(4.0)), Vector3(0, seat_y, seat_z + Parts.mm(1.0)), blue, "shell")
	# Щели под штыри: у перекидного 2 ряда, у пар НО/НЗ — по числу ступеней.
	var pin_rows: int = 2
	for row in pin_rows:
		for i in n_poles:
			var px: float = (float(i) - float(n_poles - 1) * 0.5) * pitch_x
			var py: float = seat_y + (Parts.mm(8.0) if row == 0 else Parts.mm(-8.0))
			Parts.box(socket, Vector3(Parts.mm(1.4), Parts.mm(2.2), Parts.mm(1.4)), Vector3(px, py, seat_z + Parts.mm(2.2)), EP.mat_well(), "internal")

	# Верхняя лесенка. Порядок к модулю→наружу: НЗ, НО, КОМ (у pair — контакт, КОМ).
	var units_info: Array = relay_contact_units_info(el)
	var sy_arr: Array
	var face_z_arr: Array
	var row_roles: Array
	if ladder_mode == "co":
		sy_arr = [Parts.mm(26.0), Parts.mm(36.0), Parts.mm(46.0)]
		face_z_arr = [Parts.mm(14.0), Parts.mm(6.0), Parts.mm(-2.0)]
		row_roles = ["nc", "no", "com"]
	else:
		sy_arr = [Parts.mm(32.0), Parts.mm(44.0)]
		face_z_arr = [Parts.mm(12.0), Parts.mm(2.0)]
		row_roles = ["pair", "com"] # ближе к модулю — НО/НЗ, крайний — «общий» вывод пары
	for ri in sy_arr.size():
		var sy: float = float(sy_arr[ri])
		var face_z: float = float(face_z_arr[ri])
		var depth: float = face_z - z_back
		var cz: float = z_back + depth * 0.5
		Parts.box(socket, Vector3(w, Parts.mm(10.0), depth), Vector3(0, sy, cz), blue, "shell")
		for bi in range(n_poles + 1):
			var bx: float = (float(bi) - float(n_poles) * 0.5) * pitch_x
			if absf(bx) > w * 0.48:
				continue
			Parts.box(socket, Vector3(Parts.mm(1.1), Parts.mm(8.0), Parts.mm(3.0)), Vector3(bx, sy, face_z - Parts.mm(1.0)), blue, "shell")
		var role: String = str(row_roles[ri])
		for i in n_poles:
			var kind_i: String = "co"
			if i < units_info.size():
				kind_i = str((units_info[i] as Dictionary).get("kind", "co"))
			var need_well: bool = true
			if ladder_mode == "co":
				need_well = _relay_unit_has_role(kind_i, role)
			if need_well:
				var x: float = (float(i) - float(n_poles - 1) * 0.5) * pitch_x
				EP.finder_term_well(socket, Vector3(x, sy, face_z), true)

	# Связь лесенка↔площадка.
	Parts.box(socket, Vector3(w, Parts.mm(10.0), Parts.mm(30.0)), Vector3(0, Parts.mm(16.0), z_back + Parts.mm(23.0)), blue, "shell")

	# Низ: фартук под модулем + A1/A2.
	Parts.box(socket, Vector3(w, Parts.mm(22.0), Parts.mm(34.0)), Vector3(0, Parts.mm(-18.0), z_back + Parts.mm(25.0)), blue, "shell")
	Parts.box(socket, Vector3(w, Parts.mm(22.0), Parts.mm(5.0)), Vector3(0, Parts.mm(-18.0), Parts.mm(2.5)), blue, "shell")
	if n_poles <= 1:
		# 1CO: две ступеньки — A1 и A2 не впритык.
		var a_steps: Array = [
			{"y": Parts.mm(-30.0), "z": Parts.mm(6.0), "name": "A1"},
			{"y": Parts.mm(-40.0), "z": Parts.mm(-2.0), "name": "A2"},
		]
		for st in a_steps:
			var sy_a: float = float(st["y"])
			var fz_a: float = float(st["z"])
			var dep_a: float = fz_a - z_back
			Parts.box(socket, Vector3(w, Parts.mm(10.0), dep_a), Vector3(0, sy_a, z_back + dep_a * 0.5), blue, "shell")
			EP.finder_term_well(socket, Vector3(0, sy_a, fz_a), false)
	else:
		var a_face: float = Parts.mm(2.0)
		var a_depth: float = a_face - z_back
		Parts.box(socket, Vector3(w, Parts.mm(14.0), a_depth), Vector3(0, -Parts.mm(36.0), z_back + a_depth * 0.5), blue, "shell")
		var a_dx: float = minf(Parts.mm(6.0), w * 0.32)
		EP.finder_term_well(socket, Vector3(-a_dx, -Parts.mm(36.0), a_face), false)
		EP.finder_term_well(socket, Vector3(a_dx, -Parts.mm(36.0), a_face), false)

	# ——— Модуль ———
	var mod := Node3D.new()
	mod.name = "RelayModule"
	var mod_w: float = w * (0.78 if n_poles >= 4 else 0.86)
	var mod_h: float = Parts.mm(38.0) if n_poles >= 4 else Parts.mm(34.0)
	var mod_d: float = Parts.mm(34.0)
	mod.position = Vector3(0, seat_y, seat_z + mod_d * 0.5 + Parts.mm(2.0))
	parent.add_child(mod)

	# Нестандартное число/тип контактов (и 1CO): белый корпус без нутра.
	if not detailed:
		var white: StandardMaterial3D = Parts.mat("kl_plain", Color(0.72, 0.74, 0.78), 0.06, 0.55)
		Parts.box(mod, Vector3(mod_w, mod_h, mod_d * 0.92), Vector3(0, 0, Parts.mm(1.0)), white, "shell")
		_add_status_led(mod, Vector3(0, Parts.mm(12.0), mod_d * 0.48), bool(el.energized))
		return

	# Стандарт 2CO / 4CO: прозрачный колпак + нутро (масштаб под ширину).
	var mat_cu: StandardMaterial3D = Parts.mat("kl_cu", Color(0.78, 0.48, 0.22), 0.75, 0.38)
	var mat_bobbin: StandardMaterial3D = EP.mat_coil_bobbin()
	var mat_arm: StandardMaterial3D = Parts.mat("kl_arm", Color(0.78, 0.80, 0.84), 0.85, 0.32)
	var coil_r: float = Parts.mm(7.0) if n_poles >= 4 else Parts.mm(5.2)
	var coil_len: float = Parts.mm(18.0) if n_poles >= 4 else Parts.mm(16.0)
	var leaf_pitch: float = Parts.mm(4.6) if n_poles >= 4 else Parts.mm(5.2)

	# Чёрная площадка внутри колпака + штыри в колодку.
	var base_z: float = -mod_d * 0.48
	var plate_z: float = base_z + Parts.mm(2.0)
	Parts.box(mod, Vector3(mod_w * 1.08, mod_h * 1.02, Parts.mm(3.6)), Vector3(0, 0, plate_z), EP.mat_black(), "shell")
	Parts.box(mod, Vector3(mod_w * 1.1, mod_h * 1.04, Parts.mm(1.2)), Vector3(0, 0, plate_z + Parts.mm(1.8)), EP.mat_black(), "shell")
	for pin_y2 in [Parts.mm(8.0), Parts.mm(-8.0)]:
		for i in n_poles:
			var ppx: float = (float(i) - float(n_poles - 1) * 0.5) * pitch_x * 0.85
			Parts.box(mod, Vector3(Parts.mm(1.1), Parts.mm(2.0), Parts.mm(7.0)), Vector3(ppx, pin_y2, base_z - Parts.mm(4.0)), Parts.alum(), "internal")

	EP.clear_cover(mod, Vector3(mod_w, mod_h, mod_d * 0.86), Vector3(0, 0, Parts.mm(2.0)), 0.22)

	# Катушка стоя на площадке (ось +Z): торец почти касается горизонтали якоря.
	var coil_y: float = Parts.mm(-9.0)
	var coil_z0: float = plate_z + Parts.mm(2.2)
	var coil_z: float = coil_z0 + coil_len * 0.5
	var coil_face_z: float = coil_z0 + coil_len
	Parts.cyl(mod, coil_r, Parts.mm(2.2), Vector3(0, coil_y, coil_z0 + Parts.mm(1.1)), "z", mat_bobbin, 14, "internal")
	Parts.cyl(mod, coil_r * 0.92, coil_len - Parts.mm(3.6), Vector3(0, coil_y, coil_z), "z", EP.mat_coil_cu(), 16, "internal")
	Parts.cyl(mod, coil_r, Parts.mm(2.2), Vector3(0, coil_y, coil_face_z - Parts.mm(1.1)), "z", mat_bobbin, 14, "internal")
	Parts.cyl(mod, Parts.mm(2.2), coil_len + Parts.mm(1.0), Vector3(0, coil_y, coil_z), "z", EP.mat_fe(), 10, "internal")
	Parts.cyl(mod, Parts.mm(2.8), Parts.mm(1.4), Vector3(0, coil_y, coil_face_z + Parts.mm(0.4)), "z", EP.mat_fe(), 10, "internal")

	# Перекидные от площадки почти до лица; НЗ / КОМ / НО по +Y (медь).
	var leaf_z0: float = plate_z + Parts.mm(1.8)
	var leaf_z1: float = Parts.mm(13.0)
	var leaf_h: float = leaf_z1 - leaf_z0
	var leaf_z: float = leaf_z0 + leaf_h * 0.5
	var leaf_t: float = Parts.mm(0.7)
	var y_nc: float = Parts.mm(5.0)
	var y_com: float = Parts.mm(9.0)
	var y_no: float = Parts.mm(13.0)
	var com_rest: float = Parts.mm(-1.8) # покой: КОМ к НЗ
	for i in n_poles:
		var lx: float = (float(i) - float(n_poles - 1) * 0.5) * leaf_pitch
		Parts.box(mod, Vector3(Parts.mm(1.0), leaf_t, leaf_h), Vector3(lx, y_nc, leaf_z), mat_cu, "internal")
		Parts.box(mod, Vector3(Parts.mm(1.0), leaf_t, leaf_h), Vector3(lx, y_no, leaf_z), mat_cu, "internal")
		Parts.cyl(mod, Parts.mm(0.7), Parts.mm(1.2), Vector3(lx, y_nc + Parts.mm(0.55), leaf_z1 - Parts.mm(2.5)), "y", Parts.brass(), 6, "internal")
		Parts.cyl(mod, Parts.mm(0.7), Parts.mm(1.2), Vector3(lx, y_no - Parts.mm(0.55), leaf_z1 - Parts.mm(2.5)), "y", Parts.brass(), 6, "internal")

	var com_bar := Node3D.new()
	com_bar.name = "ComBar"
	com_bar.position = Vector3(0, com_rest, 0)
	mod.add_child(com_bar)
	for i in n_poles:
		var lx2: float = (float(i) - float(n_poles - 1) * 0.5) * leaf_pitch
		Parts.box(com_bar, Vector3(Parts.mm(1.0), leaf_t, leaf_h), Vector3(lx2, y_com, leaf_z), mat_cu, "internal")
		Parts.cyl(com_bar, Parts.mm(0.7), Parts.mm(1.4), Vector3(lx2, y_com, leaf_z1 - Parts.mm(2.5)), "y", Parts.brass(), 6, "internal")

	# Якорь «Г» (серебро): одна связная буква — полка на торце катушки + стойка ЗА НЗ + круглая игла.
	# Игла упирается в НИЖНЮЮ грань КОМ, не проходит сквозь пластину.
	var com_y_rest: float = y_com + com_rest
	var com_under: float = com_y_rest - leaf_t * 0.5
	var armature := Node3D.new()
	armature.name = "Armature"
	var arm_y0: float = 0.0
	armature.position = Vector3(0, arm_y0, coil_face_z + Parts.mm(0.6))
	mod.add_child(armature)
	# Полка «Г» на торце катушки (перекрытие со стойкой по Y).
	var shelf_y0: float = coil_y - Parts.mm(6.0)
	var shelf_y1: float = y_nc - Parts.mm(1.2) # стоп ДО НЗ
	var shelf_cy: float = (shelf_y0 + shelf_y1) * 0.5
	var shelf_hy: float = shelf_y1 - shelf_y0
	Parts.box(armature, Vector3(mod_w * 0.8, shelf_hy, Parts.mm(2.0)), Vector3(0, shelf_cy, 0), mat_arm, "internal")
	# Стойка «Г» — продолжение полки вверх, останавливается ПОД НЗ (тот же Z → цельная буква).
	var stem_y0: float = shelf_y1 - Parts.mm(0.8) # нахлёст с полкой
	var stem_y1: float = y_nc - leaf_t * 0.5 - Parts.mm(0.25)
	var stem_cy: float = (stem_y0 + stem_y1) * 0.5
	var stem_hy: float = maxf(stem_y1 - stem_y0, Parts.mm(2.0))
	Parts.box(armature, Vector3(mod_w * 0.72, stem_hy, Parts.mm(2.0)), Vector3(0, stem_cy, 0), mat_arm, "internal")
	# Обход НЗ к свободному концу (+Z): короткий мостик, затем круглая игла снизу в КОМ.
	var bypass_z: float = Parts.mm(3.5)
	Parts.box(armature, Vector3(mod_w * 0.55, Parts.mm(1.4), bypass_z + Parts.mm(1.0)), Vector3(0, stem_y1 - Parts.mm(0.2), bypass_z * 0.5), mat_arm, "internal")
	var needle_y0: float = y_nc + leaf_t * 0.5 + Parts.mm(0.2) # выше НЗ
	var needle_y1: float = com_under - Parts.mm(0.12) # упор в низ КОМ
	var needle_len: float = maxf(needle_y1 - needle_y0, Parts.mm(0.8))
	var needle_cy: float = needle_y0 + needle_len * 0.5
	# Стойка-подъём от мостика до начала иглы (связь, без разрыва).
	var rise_y0: float = stem_y1 - Parts.mm(0.2)
	var rise_y1: float = needle_y0 + Parts.mm(0.2)
	Parts.box(armature, Vector3(mod_w * 0.5, maxf(rise_y1 - rise_y0, Parts.mm(1.0)), Parts.mm(1.6)), Vector3(0, (rise_y0 + rise_y1) * 0.5, bypass_z), mat_arm, "internal")
	Parts.cyl(armature, Parts.mm(0.75), needle_len, Vector3(0, needle_cy, bypass_z), "y", mat_arm, 12, "internal")
	if bool(el.energized):
		armature.position.y = arm_y0 + Parts.mm(3.6)
		com_bar.position.y = Parts.mm(2.0)

	_add_status_led(mod, Vector3(minf(Parts.mm(6.0), mod_w * 0.35), Parts.mm(14.0), mod_d * 0.48), bool(el.energized))


static func _build_timer(parent: Node3D, el) -> void:
	# Ступень + нос до колодок; клеммы Finder: винт на +Z, зев ±Y под подсветку.
	var tsz: Vector3 = _timer_body_size()
	var w: float = tsz.x
	var h: float = tsz.y
	var d: float = tsz.z
	var body: StandardMaterial3D = _timer_body_mat(parent)
	var z_back: float = -d * 0.44
	var step_z: float = d * 0.10
	var face_z: float = d * 0.42
	var rear_depth: float = step_z - z_back
	Parts.box(parent, Vector3(w, h, rear_depth), Vector3(0, 0, z_back + rear_depth * 0.5), body, "shell")
	EP.din_clip_grey(parent, Vector3(0, -h * 0.42, z_back + Parts.mm(6.0)), w)
	var term_h: float = Parts.mm(8.0)
	var term_d: float = Parts.mm(14.0)
	var ty_top: float = h * 0.42
	var ty_bot: float = -h * 0.42
	var well_z: float = step_z + term_d * 0.5
	Parts.box(parent, Vector3(w * 0.90, term_h, term_d), Vector3(0, ty_top, well_z), EP.mat_black(), "shell")
	Parts.box(parent, Vector3(w * 0.90, term_h, term_d), Vector3(0, ty_bot, well_z), EP.mat_black(), "shell")
	# Белый нос впритык к чёрным колодкам сверху и снизу.
	var nose_top: float = ty_top - term_h * 0.5
	var nose_bot: float = ty_bot + term_h * 0.5
	var nose_h: float = nose_top - nose_bot
	var nose_cy: float = (nose_top + nose_bot) * 0.5
	var nose_depth: float = face_z - step_z
	Parts.box(parent, Vector3(w * 0.98, nose_h, nose_depth), Vector3(0, nose_cy, step_z + nose_depth * 0.5), body, "shell")
	var cream_half: float = Parts.mm(1.5)
	var cream_z: float = face_z + cream_half
	Parts.box(parent, Vector3(w * 0.92, nose_h, cream_half * 2.0), Vector3(0, nose_cy, cream_z), _timer_face_mat(parent), "shell")
	var face_front: float = cream_z + cream_half
	# Винт на лице колодки (+Z), зев провода на ±Y (как Finder / подсветка).
	var screw_z: float = well_z + term_d * 0.5 - Parts.mm(0.5)
	var top_xs: Array = [-Parts.mm(5.0), Parts.mm(5.0)]
	var bot_xs: Array = [-Parts.mm(7.0), 0.0, Parts.mm(7.0)]
	for x in top_xs:
		EP.kt_term_well(parent, Vector3(float(x), ty_top, screw_z), true)
	for x2 in bot_xs:
		EP.kt_term_well(parent, Vector3(float(x2), ty_bot, screw_z), false)
	var dial_mat := Parts.mat("kt_dial", Color(0.82, 0.12, 0.12), 0.05, 0.45)
	var scale_mat := Parts.mat("kt_scale", Color(0.92, 0.92, 0.94), 0.06, 0.55)
	var dial_on_y: float = Parts.mm(12.0)
	var dial_unit_y: float = Parts.mm(-10.0)
	Parts.cyl(parent, Parts.mm(7.5), Parts.mm(1.2), Vector3(0, dial_on_y, face_front - Parts.mm(0.2)), "z", scale_mat, 16, "shell")
	# Засечки по дуге 0…100% шкалы (диапазон зависит от единиц).
	for ti in 7:
		var t_norm: float = float(ti) / 6.0
		var ang: float = deg_to_rad(TIMER_VALUE_ARC_START_DEG + t_norm * TIMER_VALUE_ARC_SPAN_DEG)
		var tx: float = sin(ang) * Parts.mm(6.4)
		var ty: float = cos(ang) * Parts.mm(6.4)
		Parts.box(parent, Vector3(Parts.mm(0.55), Parts.mm(1.35), Parts.mm(0.6)), Vector3(tx, dial_on_y + ty, face_front + Parts.mm(0.2)), EP.mat_black(), "shell")
	var zone_on := Node3D.new()
	zone_on.name = "DialOnZone"
	zone_on.position = Vector3(0, dial_on_y, face_front + Parts.mm(1.0))
	parent.add_child(zone_on)
	var dial_on := Node3D.new()
	dial_on.name = "DialOn"
	dial_on.position = Vector3(0, dial_on_y, face_front + Parts.mm(0.8))
	parent.add_child(dial_on)
	Parts.cyl(dial_on, Parts.mm(5.0), Parts.mm(2.8), Vector3.ZERO, "z", dial_mat, 14, "actuator")
	Parts.box(dial_on, Vector3(Parts.mm(1.1), Parts.mm(4.2), Parts.mm(0.9)), Vector3(0, Parts.mm(2.4), Parts.mm(1.2)), Parts.mat("kt_mark", Color(0.95, 0.95, 0.95), 0.05, 0.5), "actuator")
	Parts.cyl(parent, Parts.mm(7.5), Parts.mm(1.2), Vector3(0, dial_unit_y, face_front - Parts.mm(0.2)), "z", scale_mat, 16, "shell")
	for u in 3:
		var ang2: float = deg_to_rad(_timer_unit_tick_ang_deg(u))
		var tx2: float = sin(ang2) * Parts.mm(6.4)
		var ty2: float = cos(ang2) * Parts.mm(6.4)
		Parts.box(parent, Vector3(Parts.mm(0.7), Parts.mm(1.6), Parts.mm(0.6)), Vector3(tx2, dial_unit_y + ty2, face_front + Parts.mm(0.2)), EP.mat_black(), "shell")
	var zone_unit := Node3D.new()
	zone_unit.name = "DialUnitZone"
	zone_unit.position = Vector3(0, dial_unit_y, face_front + Parts.mm(1.0))
	parent.add_child(zone_unit)
	var dial_unit := Node3D.new()
	dial_unit.name = "DialUnit"
	dial_unit.position = Vector3(0, dial_unit_y, face_front + Parts.mm(0.8))
	parent.add_child(dial_unit)
	Parts.cyl(dial_unit, Parts.mm(5.0), Parts.mm(2.8), Vector3.ZERO, "z", dial_mat, 14, "actuator")
	Parts.box(dial_unit, Vector3(Parts.mm(1.1), Parts.mm(4.2), Parts.mm(0.9)), Vector3(0, Parts.mm(2.4), Parts.mm(1.2)), Parts.mat("kt_mark2", Color(0.95, 0.95, 0.95), 0.05, 0.5), "actuator")
	var led_u := Node3D.new()
	led_u.name = "LedU"
	led_u.position = Vector3(-Parts.mm(5.5), Parts.mm(24.0), face_front + Parts.mm(0.4))
	parent.add_child(led_u)
	Parts.cyl(led_u, Parts.mm(2.0), Parts.mm(1.4), Vector3.ZERO, "z", Parts.mat("led_u", Color(0.95, 0.9, 0.2), 0.1, 0.35), 10, "internal")
	var glow := MeshInstance3D.new()
	glow.name = "BodyGlow"
	var box := BoxMesh.new()
	box.size = Vector3(Parts.mm(3.5), Parts.mm(3.5), Parts.mm(1.4))
	glow.mesh = box
	glow.position = Vector3(Parts.mm(5.5), Parts.mm(24.0), face_front + Parts.mm(0.4))
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.9, 0.35)
	gm.emission_enabled = true
	gm.emission = Color(0.2, 0.9, 0.35)
	gm.emission_energy_multiplier = 1.5
	glow.material_override = gm
	glow.visible = bool(el.energized)
	_set_xray(glow, "internal")
	parent.add_child(glow)
	dial_on.rotation_degrees = Vector3(0, 0, _timer_value_to_dial_deg(float(el.timer_value), int(el.timer_unit)))
	dial_unit.rotation_degrees = Vector3(0, 0, _timer_unit_to_dial_deg(int(el.timer_unit)))


static func _build_contactor(parent: Node3D, el) -> void:
	# Реф IEK КМИ-10910 / GLB kmi-10910: 45×75×80, чёрный корпус, беж. клеммы, синяя кнопка I.
	var w := Parts.mm(45.0)
	var h := Parts.mm(75.0)
	var d := Parts.mm(80.0)
	Parts.box(parent, Vector3(w, h, d * 0.78), Vector3(0, 0, -d * 0.06), EP.mat_black(), "shell")
	EP.din_clip_grey(parent, Vector3(0, -h * 0.4, -d * 0.38), w * 0.9)
	# Боковые рёбра корпуса КМИ.
	for i in 4:
		var y: float = -h * 0.3 + float(i) * h * 0.2
		Parts.box(parent, Vector3(Parts.mm(1.0), Parts.mm(3.0), d * 0.35), Vector3(-w * 0.495, y, 0), EP.mat_black_soft(), "shell")
		Parts.box(parent, Vector3(Parts.mm(1.0), Parts.mm(3.0), d * 0.35), Vector3(w * 0.495, y, 0), EP.mat_black_soft(), "shell")
	var beige := EP.mat_beige()
	Parts.box(parent, Vector3(w * 0.98, Parts.mm(16.0), Parts.mm(28.0)), Vector3(0, h * 0.36, d * 0.28), beige, "shell")
	Parts.box(parent, Vector3(w * 0.98, Parts.mm(16.0), Parts.mm(28.0)), Vector3(0, -h * 0.36, d * 0.28), beige, "shell")
	EP.barrier_row(parent, Vector3(0, h * 0.36, d * 0.3), 3, Parts.mm(12.0), Vector3(Parts.mm(1.6), Parts.mm(14.0), Parts.mm(20.0)), EP.mat_black())
	EP.barrier_row(parent, Vector3(0, -h * 0.36, d * 0.3), 3, Parts.mm(12.0), Vector3(Parts.mm(1.6), Parts.mm(14.0), Parts.mm(20.0)), EP.mat_black())
	for i in 3:
		var x: float = (float(i) - 1.0) * Parts.mm(12.0)
		_screw_well(parent, Vector3(x, h * 0.38, d * 0.38), Vector3(0, 1, 0))
		_screw_well(parent, Vector3(x, -h * 0.38, d * 0.38), Vector3(0, -1, 0))
	# Передняя панель + синяя кнопка/индикатор I (якорь).
	Parts.box(parent, Vector3(w * 0.7, Parts.mm(36.0), Parts.mm(6.0)), Vector3(0, Parts.mm(2.0), d * 0.42), EP.mat_black_soft(), "shell")
	var plunger := Node3D.new()
	plunger.name = "Plunger"
	parent.add_child(plunger)
	var blue := Parts.mat("km_blue", Color(0.1, 0.28, 0.78), 0.08, 0.42)
	Parts.box(plunger, Vector3(Parts.mm(20.0), Parts.mm(22.0), Parts.mm(10.0)), Vector3(0, Parts.mm(2.0), d * 0.48), blue, "actuator")
	Parts.box(plunger, Vector3(Parts.mm(12.0), Parts.mm(8.0), Parts.mm(4.0)), Vector3(0, Parts.mm(2.0), d * 0.55), Parts.mat("km_blue2", Color(0.08, 0.24, 0.7), 0.08, 0.42), "actuator")
	EP.face_label(plunger, "I", Vector3(0, Parts.mm(2.0), d * 0.58), 12, 0.0002)
	# A1/A2 на лице снизу/сбоку (типичная раскладка КМИ).
	Parts.box(parent, Vector3(Parts.mm(18.0), Parts.mm(8.0), Parts.mm(10.0)), Vector3(-w * 0.28, -h * 0.08, d * 0.4), beige, "shell")
	Parts.box(parent, Vector3(Parts.mm(18.0), Parts.mm(8.0), Parts.mm(10.0)), Vector3(w * 0.28, -h * 0.08, d * 0.4), beige, "shell")
	_screw_well(parent, Vector3(-w * 0.28, -h * 0.08, d * 0.46), Vector3(0, 0, 1))
	_screw_well(parent, Vector3(w * 0.28, -h * 0.08, d * 0.46), Vector3(0, 0, 1))
	Parts.cyl(parent, Parts.mm(11.0), Parts.mm(26.0), Vector3(0, Parts.mm(-2.0), 0), "y", Parts.mat("km_coil", Color(0.2, 0.35, 0.75), 0.35, 0.5), 16, "internal")
	Parts.box(parent, Vector3(Parts.mm(7.0), Parts.mm(18.0), Parts.mm(7.0)), Vector3(0, Parts.mm(-2.0), 0), EP.mat_fe(), "internal")
	EP.face_label(parent, "КМИ", Vector3(0, Parts.mm(18.0), d * 0.48), 11, 0.00017)
	var glow := MeshInstance3D.new()
	glow.name = "BodyGlow"
	var box := BoxMesh.new()
	box.size = Vector3(Parts.mm(5.0), Parts.mm(2.5), Parts.mm(1.8))
	glow.mesh = box
	glow.position = Vector3(0, Parts.mm(-18.0), d * 0.48)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.9, 0.35)
	gm.emission_enabled = true
	gm.emission = Color(0.2, 0.9, 0.35)
	gm.emission_energy_multiplier = 1.5
	glow.material_override = gm
	glow.visible = bool(el.energized)
	_set_xray(glow, "internal")
	parent.add_child(glow)


static func _build_breaker(parent: Node3D, el, lever_color: Color) -> void:
	# Рефы: Schneider A9F03101 iC60N (MCB 18×92×78.5), Doepke DFS2 (УЗО).
	var poles := maxi(int(el.poles), 1)
	var cls := str(el.electro_class)
	if cls in ["rcd", "rcbo"]:
		poles = maxi(poles, 2)
	var w: float = Parts.mm(18.0) if (cls == "mcb" and poles == 1) else Parts.mm(17.5) * float(poles)
	if cls == "rcd" and poles == 2:
		w = Parts.mm(36.0)
	var h: float = Parts.mm(92.0) if cls == "mcb" else Parts.mm(85.0)
	var d: float = Parts.mm(78.5) if cls == "mcb" else (Parts.mm(75.0) if cls in ["rcd", "rcbo"] else Parts.mm(72.0))
	_mod_step_body(parent, w, h, d, _ral7035())
	if cls in ["rcd", "rcbo"]:
		EP.two_tier_terminals(parent, w, h, d, poles)
	else:
		# iC60: круглые зевы double terminal сверху/снизу.
		for i in poles:
			var x: float = -w * 0.5 + w / float(poles) * (float(i) + 0.5)
			EP.round_term_mouth(parent, Vector3(x, h * 0.38, d * 0.28), Vector3(0, 1, 0))
			EP.round_term_mouth(parent, Vector3(x, -h * 0.38, d * 0.28), Vector3(0, -1, 0))
			if i > 0:
				var bx: float = -w * 0.5 + float(i) * (w / float(poles))
				Parts.box(parent, Vector3(Parts.mm(1.2), h * 0.85, d * 0.35), Vector3(bx, 0, d * 0.05), EP.mat_ral7035_dark(), "shell")
	if cls == "mcb":
		EP.label_window(parent, Vector3(0, Parts.mm(22.0), d * 0.5), Vector3(w * 0.72, Parts.mm(10.0), Parts.mm(2.0)))
		EP.face_label(parent, "iC60N", Vector3(0, Parts.mm(24.0), d * 0.54), 9, 0.00015)
		EP.face_label(parent, "%s%.0f" % [str(el.curve), float(el.rating_a)], Vector3(0, Parts.mm(18.0), d * 0.54), 11, 0.00018)
	elif cls == "rcd":
		Parts.box(parent, Vector3(Parts.mm(14.0), Parts.mm(5.0), Parts.mm(1.6)), Vector3(-w * 0.28, Parts.mm(26.0), d * 0.48), Parts.mat("doepke_red", Color(0.82, 0.08, 0.1), 0.05, 0.5), "shell")
		EP.face_label(parent, "DFS2", Vector3(-w * 0.05, Parts.mm(26.0), d * 0.52), 10, 0.00017)
		EP.label_window(parent, Vector3(0, Parts.mm(16.0), d * 0.5), Vector3(w * 0.55, Parts.mm(8.0), Parts.mm(2.0)))
		EP.face_label(parent, "%.0fмА" % float(el.i_delta_ma), Vector3(0, Parts.mm(16.0), d * 0.54), 11, 0.00018)
	elif cls == "rcbo":
		Parts.box(parent, Vector3(w * 0.72, Parts.mm(5.0), Parts.mm(1.6)), Vector3(0, Parts.mm(24.0), d * 0.48), Parts.mat("yel_strip", Color(0.92, 0.82, 0.12), 0.05, 0.5), "shell")
		EP.face_label(parent, "АВДТ", Vector3(0, Parts.mm(24.0), d * 0.52), 9, 0.00016)
		EP.face_label(parent, "%s%.0f" % [str(el.curve), float(el.rating_a)], Vector3(0, Parts.mm(14.0), d * 0.52), 11, 0.00019)
		EP.face_label(parent, "%.0fмА" % float(el.i_delta_ma), Vector3(w * 0.15, Parts.mm(6.0), d * 0.52), 9, 0.00016)
	# iC60: светло-серый рычаг; УЗО — синий.
	var lev_col: Color = Color(0.82, 0.84, 0.86) if cls == "mcb" else lever_color
	var lev_w: float = Parts.mm(9.0) * float(mini(poles, 2))
	var lever := EP.breaker_lever(parent, lev_col, lev_w)
	lever.position = Vector3(-w * 0.14 if cls in ["rcd", "rcbo"] else 0.0, Parts.mm(-2.0), d * 0.52)
	lever.rotation_degrees = Vector3(-35.0 if bool(el.closed) else 35.0, 0, 0)
	EP.face_label(parent, "I", Vector3(lever.position.x + w * 0.28, Parts.mm(12.0), d * 0.54), 9, 0.00015)
	EP.face_label(parent, "O", Vector3(lever.position.x + w * 0.28, Parts.mm(-14.0), d * 0.54), 9, 0.00015)
	if cls in ["rcd", "rcbo"]:
		Parts.box(parent, Vector3(Parts.mm(9.0), Parts.mm(7.0), Parts.mm(4.0)), Vector3(w * 0.24, Parts.mm(4.0), d * 0.52), Parts.mat("test_btn", Color(0.92, 0.92, 0.94), 0.05, 0.5), "actuator")
		EP.face_label(parent, "T", Vector3(w * 0.24, Parts.mm(4.0), d * 0.57), 9, 0.00016)
	var ind := MeshInstance3D.new()
	ind.name = "PosInd"
	var imesh := BoxMesh.new()
	imesh.size = Vector3(Parts.mm(6.0), Parts.mm(4.0), Parts.mm(1.8))
	ind.mesh = imesh
	ind.position = Vector3(w * 0.05 if cls == "rcd" else 0.0, Parts.mm(-16.0), d * 0.52)
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.85, 0.15, 0.12) if bool(el.closed) else Color(0.15, 0.65, 0.28)
	ind.material_override = im
	_set_xray(ind, "internal")
	parent.add_child(ind)
	Parts.box(parent, Vector3(Parts.mm(3.5), Parts.mm(28.0), Parts.mm(8.0)), Vector3(-w * 0.18, 0, 0), Parts.mat("bi", Color(0.72, 0.55, 0.32), 0.5, 0.4), "internal")
	Parts.cyl(parent, Parts.mm(3.0), Parts.mm(20.0), Vector3(w * 0.14, Parts.mm(2.0), 0), "y", Parts.mat("em_coil", Color(0.22, 0.28, 0.38), 0.3, 0.5), 12, "internal")
	Parts.box(parent, Vector3(Parts.mm(2.0), Parts.mm(14.0), Parts.mm(2.0)), Vector3(w * 0.14, Parts.mm(-12.0), 0), Parts.alum(), "internal")
	if cls in ["rcd", "rcbo"]:
		Parts.cyl(parent, Parts.mm(10.0), Parts.mm(8.0), Vector3(0, Parts.mm(-10.0), Parts.mm(-4.0)), "y", Parts.mat("diff_tt", Color(0.42, 0.44, 0.48), 0.4, 0.5), 18, "internal")
		Parts.cyl(parent, Parts.mm(4.0), Parts.mm(10.0), Vector3(0, Parts.mm(-10.0), Parts.mm(-4.0)), "y", EP.mat_fe(), 10, "internal")


static func _build_terminal(parent: Node3D, el) -> void:
	# Винтовая DIN-клемма: PA66, 2 винта сверху, входы ±Z, латунь внутри.
	var body := Parts.mat("term_pa", Color(0.7, 0.72, 0.74), 0.05, 0.68)
	var n := maxi(el.electro_ports.size(), 1)
	var pitch := Parts.mm(8.75)
	var w := pitch * float(n)
	var h := Parts.mm(54.0)
	var d := Parts.mm(48.0)
	for i in n:
		var x: float = -w * 0.5 + pitch * 0.5 + float(i) * pitch
		Parts.box(parent, Vector3(Parts.mm(8.2), h, d), Vector3(x, 0, 0), body, "shell")
		Parts.box(parent, Vector3(Parts.mm(0.9), h * 0.75, d * 0.75), Vector3(x - Parts.mm(3.8), 0, 0), EP.mat_ral7035_dark(), "shell")
		Parts.box(parent, Vector3(Parts.mm(0.9), h * 0.75, d * 0.75), Vector3(x + Parts.mm(3.8), 0, 0), EP.mat_ral7035_dark(), "shell")
		EP.screw_well_top(parent, Vector3(x, h * 0.42, Parts.mm(11.0)), Vector3(0, 0, 1))
		EP.screw_well_top(parent, Vector3(x, h * 0.42, -Parts.mm(11.0)), Vector3(0, 0, -1))
		Parts.box(parent, Vector3(Parts.mm(3.8), Parts.mm(3.0), Parts.mm(28.0)), Vector3(x, Parts.mm(2.0), 0), Parts.brass(), "internal")
		# Маркировочная площадка.
		Parts.box(parent, Vector3(Parts.mm(6.5), Parts.mm(8.0), Parts.mm(1.2)), Vector3(x, Parts.mm(-8.0), d * 0.48), Parts.mat("term_mark", Color(0.95, 0.95, 0.92), 0.05, 0.6), "shell")
	Parts.box(parent, Vector3(w * 0.92, Parts.mm(6.0), Parts.mm(16.0)), Vector3(0, -h * 0.42, 0), body, "shell")
	EP.din_clip_grey(parent, Vector3(0, -h * 0.5, Parts.mm(2.0)), w * 0.7)


static func _bus_base_mat(el) -> StandardMaterial3D:
	# SPEC: голубой N, чёрный −/L2, красный +, зелёный PE, коричневый L1, серый L3.
	match str(el.phase):
		"PE", "green":
			return Parts.mat("bus_pe", Color(0.12, 0.55, 0.22), 0.08, 0.55)
		"+", "plus", "red":
			return Parts.mat("bus_p", Color(0.82, 0.12, 0.12), 0.08, 0.5)
		"-", "minus", "black", "L2":
			return Parts.mat("bus_m", Color(0.1, 0.1, 0.12), 0.1, 0.5)
		"L1", "L", "brown":
			return Parts.mat("bus_l1", Color(0.45, 0.28, 0.12), 0.1, 0.5)
		"L3", "gray", "grey":
			return Parts.mat("bus_l3", Color(0.55, 0.56, 0.58), 0.1, 0.5)
		_:
			return Parts.mat("bus_n", Color(0.25, 0.55, 0.9), 0.08, 0.5) # голубой N


static func _build_busbar(parent: Node3D, el) -> void:
	# База 1 модуль; латунь поперёк (+Y); винты на +Z.
	var n := maxi(el.electro_ports.size(), 4)
	var pitch := Parts.mm(10.0)
	var len_y := pitch * float(n) + Parts.mm(6.0)
	var base := _bus_base_mat(el)
	var base_w := Parts.mm(17.5)
	var bar_z := Parts.mm(10.0)
	Parts.box(parent, Vector3(base_w * 0.95, len_y * 0.55, Parts.mm(4.5)), Vector3(0, 0, Parts.mm(-2.0)), base, "shell")
	Parts.box(parent, Vector3(base_w * 0.92, Parts.mm(14.0), Parts.mm(18.0)), Vector3(0, -len_y * 0.42, Parts.mm(5.0)), base, "shell")
	Parts.box(parent, Vector3(base_w * 0.75, Parts.mm(12.0), Parts.mm(16.0)), Vector3(0, len_y * 0.42, Parts.mm(5.0)), base, "shell")
	# Фаски/ножки.
	Parts.box(parent, Vector3(base_w * 0.5, Parts.mm(4.0), Parts.mm(6.0)), Vector3(0, -len_y * 0.5, Parts.mm(2.0)), base, "shell")
	Parts.box(parent, Vector3(base_w * 0.5, Parts.mm(4.0), Parts.mm(6.0)), Vector3(0, len_y * 0.5, Parts.mm(2.0)), base, "shell")
	EP.din_clip_grey(parent, Vector3(0, 0, Parts.mm(1.0)), base_w * 0.8)
	Parts.box(parent, Vector3(Parts.mm(8.5), len_y, Parts.mm(8.5)), Vector3(0, 0, bar_z), Parts.brass(), "shell")
	# Скруглённые торцы латуни.
	Parts.cyl(parent, Parts.mm(4.25), Parts.mm(8.5), Vector3(0, -len_y * 0.5, bar_z), "z", Parts.brass(), 12, "shell")
	Parts.cyl(parent, Parts.mm(4.25), Parts.mm(8.5), Vector3(0, len_y * 0.5, bar_z), "z", Parts.brass(), 12, "shell")
	for i in n:
		var y: float = -len_y * 0.5 + Parts.mm(3.0) + float(i) * pitch + pitch * 0.5
		Parts.cyl(parent, Parts.mm(1.5), Parts.mm(2.4), Vector3(0, y, bar_z + Parts.mm(5.2)), "z", Parts.alum(), 8, "internal")
		Parts.box(parent, Vector3(Parts.mm(0.4), Parts.mm(2.2), Parts.mm(0.4)), Vector3(0, y, bar_z + Parts.mm(6.2)), Parts.alum(), "internal")
		Parts.box(parent, Vector3(Parts.mm(1.4), Parts.mm(3.0), Parts.mm(3.0)), Vector3(Parts.mm(-4.8), y, bar_z), Parts.mat("bus_hole", Color(0.1, 0.1, 0.11), 0.35, 0.65), "internal")
	if str(el.caption) != "":
		var lab := Label3D.new()
		lab.name = "BusCaption"
		lab.text = str(el.caption)
		lab.font_size = 20
		lab.pixel_size = 0.00032
		lab.modulate = Color(0.95, 0.95, 0.97)
		lab.position = Vector3(Parts.mm(11.0), 0, bar_z + Parts.mm(2.0))
		parent.add_child(lab)


static func _build_supply(parent: Node3D, el) -> void:
	var n: int = 4 if int(el.poles) >= 3 else 3
	var w := Parts.mm(17.5) * float(3 if n >= 4 else 2)
	var h := Parts.mm(70.0)
	var d := Parts.mm(60.0)
	Parts.box(parent, Vector3(w, h, d), Vector3.ZERO, _ral7035(), "shell")
	Parts.box(parent, Vector3(w * 0.9, Parts.mm(8.0), Parts.mm(10.0)), Vector3(0, -h * 0.45, -d * 0.3), Parts.black(), "internal")
	for i in n:
		var x := -Parts.mm(8.0) * float(n - 1) * 0.5 + float(i) * Parts.mm(8.0)
		Parts.cyl(parent, Parts.mm(3.0), Parts.mm(10.0), Vector3(x, Parts.mm(20.0), Parts.mm(28.0)), "z", Parts.brass(), 10, "internal")


static func _build_psu(parent: Node3D, el) -> void:
	# Mean Well DRA-60-24: голубой корпус, белая панель, колодцы на лице (+Z).
	var w := Parts.mm(35.0)
	var h := Parts.mm(90.0)
	var d := Parts.mm(58.0)
	var blue := Parts.mat("psu_body", Color(0.42, 0.58, 0.78), 0.08, 0.55)
	var face := Parts.mat("psu_face", Color(0.96, 0.96, 0.98), 0.04, 0.62)
	Parts.box(parent, Vector3(w, h, d * 0.9), Vector3(0, 0, -d * 0.02), blue, "shell")
	EP.din_clip_grey(parent, Vector3(0, -h * 0.42, -d * 0.32), w * 0.85)
	for i in 6:
		var z: float = -d * 0.32 + float(i) * Parts.mm(5.5)
		Parts.box(parent, Vector3(w * 0.72, Parts.mm(1.0), Parts.mm(2.8)), Vector3(0, h * 0.485, z), Parts.mat("vent", Color(0.32, 0.48, 0.68), 0.1, 0.6), "shell")
		Parts.box(parent, Vector3(w * 0.72, Parts.mm(1.0), Parts.mm(2.8)), Vector3(0, -h * 0.485, z), Parts.mat("vent2", Color(0.32, 0.48, 0.68), 0.1, 0.6), "shell")
	Parts.box(parent, Vector3(w * 0.96, h * 0.94, Parts.mm(2.8)), Vector3(0, 0, d * 0.48), face, "shell")
	# DC сверху: +V, +V, COM, COM
	var dc_labs: Array = ["+V", "+V", "COM", "COM"]
	for i in 4:
		var x: float = -Parts.mm(12.0) + float(i) * Parts.mm(8.0)
		EP.screw_well_face(parent, Vector3(x, h * 0.38, d * 0.52), Vector3(0, 0, 1), 5.5)
		EP.face_label(parent, str(dc_labs[i]), Vector3(x, h * 0.3, d * 0.54), 7, 0.00013)
	# AC снизу: L N PE
	var ac_labs: Array = ["L", "N", "PE"]
	for i in 3:
		var x2: float = -Parts.mm(10.0) + float(i) * Parts.mm(10.0)
		EP.screw_well_face(parent, Vector3(x2, -h * 0.38, d * 0.52), Vector3(0, 0, 1), 5.5)
		EP.face_label(parent, str(ac_labs[i]), Vector3(x2, -h * 0.3, d * 0.54), 8, 0.00014)
	Parts.cyl(parent, Parts.mm(2.2), Parts.mm(2.2), Vector3(Parts.mm(6.0), Parts.mm(8.0), d * 0.54), "z", Parts.black(), 8, "actuator")
	EP.face_label(parent, "ADJ", Vector3(Parts.mm(6.0), Parts.mm(2.0), d * 0.54), 7, 0.00012)
	var led := MeshInstance3D.new()
	led.name = "BodyGlow"
	var box := BoxMesh.new()
	box.size = Vector3(Parts.mm(3.5), Parts.mm(2.5), Parts.mm(1.5))
	led.mesh = box
	led.position = Vector3(-w * 0.22, Parts.mm(16.0), d * 0.54)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.9, 0.35)
	gm.emission_enabled = true
	gm.emission = Color(0.2, 0.9, 0.35)
	gm.emission_energy_multiplier = 1.2
	led.material_override = gm
	led.visible = true
	_set_xray(led, "internal")
	parent.add_child(led)
	EP.face_label(parent, "DC OK", Vector3(-w * 0.22, Parts.mm(11.0), d * 0.54), 7, 0.00012)
	EP.face_label(parent, "DRA-60", Vector3(0, Parts.mm(-2.0), d * 0.54), 10, 0.00017)
	EP.face_label(parent, "%.0fV" % float(el.voltage), Vector3(0, Parts.mm(-10.0), d * 0.54), 14, 0.00022)
	# Трансформатор внутри (x-ray).
	Parts.box(parent, Vector3(Parts.mm(18.0), Parts.mm(22.0), Parts.mm(16.0)), Vector3(0, 0, 0), EP.mat_fe(), "internal")
	Parts.cyl(parent, Parts.mm(6.0), Parts.mm(14.0), Vector3(0, 0, 0), "y", EP.mat_coil_cu(), 12, "internal")


static func _build_socket(parent: Node3D) -> void:
	Parts.box(parent, Vector3(Parts.mm(45.0), Parts.mm(75.0), Parts.mm(55.0)), Vector3.ZERO, _ral7035_dark(), "shell")
	Parts.box(parent, Vector3(Parts.mm(28.0), Parts.mm(18.0), Parts.mm(4.0)), Vector3(0, Parts.mm(8.0), Parts.mm(28.0)), Parts.black(), "internal")


static func _build_stop(parent: Node3D) -> void:
	# Концевой упор DIN: губки на шляпу TS35, прижимной винт на +Z.
	var body := Parts.mat("din_stop", Color(0.52, 0.54, 0.58), 0.08, 0.62)
	Parts.box(parent, Vector3(Parts.mm(9.0), Parts.mm(34.0), Parts.mm(30.0)), Vector3(0, Parts.mm(2.0), Parts.mm(2.0)), body, "shell")
	# Верхняя «шапка» с фаской.
	Parts.box(parent, Vector3(Parts.mm(9.0), Parts.mm(6.0), Parts.mm(22.0)), Vector3(0, Parts.mm(16.0), Parts.mm(4.0)), body, "shell")
	# Губки на рейку.
	Parts.box(parent, Vector3(Parts.mm(9.0), Parts.mm(7.0), Parts.mm(12.0)), Vector3(0, Parts.mm(-12.0), -Parts.mm(8.0)), body, "shell")
	Parts.box(parent, Vector3(Parts.mm(6.5), Parts.mm(4.5), Parts.mm(9.0)), Vector3(0, Parts.mm(-16.0), -Parts.mm(1.0)), EP.mat_black(), "internal")
	Parts.box(parent, Vector3(Parts.mm(7.0), Parts.mm(3.0), Parts.mm(4.0)), Vector3(0, Parts.mm(-14.0), Parts.mm(6.0)), EP.mat_orange(), "shell")
	# Прижимной винт + шайба на лицо.
	Parts.cyl(parent, Parts.mm(3.5), Parts.mm(2.0), Vector3(0, Parts.mm(4.0), Parts.mm(15.0)), "z", Parts.alum(), 12, "shell")
	Parts.cyl(parent, Parts.mm(2.4), Parts.mm(12.0), Vector3(0, Parts.mm(4.0), Parts.mm(18.0)), "z", Parts.alum(), 10, "shell")
	Parts.box(parent, Vector3(Parts.mm(3.8), Parts.mm(1.2), Parts.mm(1.4)), Vector3(0, Parts.mm(4.0), Parts.mm(23.5)), Parts.alum(), "internal")
	Parts.box(parent, Vector3(Parts.mm(1.2), Parts.mm(3.8), Parts.mm(1.4)), Vector3(0, Parts.mm(4.0), Parts.mm(23.5)), Parts.alum(), "internal")


static func _build_thermal(parent: Node3D) -> void:
	# PTA: ширина 3 модуля, пины в КМ, Reset + шкала тока.
	var w := Parts.mm(52.5)
	var h := Parts.mm(62.0)
	var d := Parts.mm(74.0)
	Parts.box(parent, Vector3(w, h, d * 0.85), Vector3(0, Parts.mm(-4.0), 0), EP.mat_black(), "shell")
	EP.din_clip_grey(parent, Vector3(0, -h * 0.48, -d * 0.2), w * 0.8)
	var beige := EP.mat_beige()
	Parts.box(parent, Vector3(w * 0.96, Parts.mm(16.0), Parts.mm(26.0)), Vector3(0, h * 0.35, d * 0.28), beige, "shell")
	EP.barrier_row(parent, Vector3(0, h * 0.35, d * 0.3), 3, Parts.mm(14.0), Vector3(Parts.mm(1.8), Parts.mm(14.0), Parts.mm(20.0)), EP.mat_black())
	for i in 3:
		var x: float = (float(i) - 1.0) * Parts.mm(14.0)
		_screw_well(parent, Vector3(x, h * 0.38, d * 0.35), Vector3(0, 1, 0))
		Parts.box(parent, Vector3(Parts.mm(4.5), Parts.mm(12.0), Parts.mm(2.2)), Vector3(x, -h * 0.58, -d * 0.12), Parts.brass(), "internal")
	# Reset (красный) + dial тока со шкалой.
	Parts.box(parent, Vector3(Parts.mm(12.0), Parts.mm(12.0), Parts.mm(7.0)), Vector3(-Parts.mm(14.0), Parts.mm(-6.0), d * 0.45), Parts.red_btn(), "actuator")
	EP.face_label(parent, "R", Vector3(-Parts.mm(14.0), Parts.mm(-6.0), d * 0.52), 10, 0.00016)
	Parts.cyl(parent, Parts.mm(7.0), Parts.mm(3.0), Vector3(Parts.mm(8.0), Parts.mm(-6.0), d * 0.48), "z", Parts.mat("kk_scale", Color(0.9, 0.9, 0.92), 0.08, 0.55), 16, "shell")
	Parts.cyl(parent, Parts.mm(4.5), Parts.mm(5.5), Vector3(Parts.mm(8.0), Parts.mm(-6.0), d * 0.5), "z", Parts.mat("kk_dial", Color(0.55, 0.56, 0.58), 0.1, 0.5), 12, "actuator")
	Parts.box(parent, Vector3(Parts.mm(1.0), Parts.mm(3.5), Parts.mm(1.0)), Vector3(Parts.mm(8.0), Parts.mm(-3.5), d * 0.54), EP.mat_black(), "actuator")
	EP.face_label(parent, "A", Vector3(Parts.mm(16.0), Parts.mm(-6.0), d * 0.52), 8, 0.00014)
	for i in 4:
		var x2: float = -Parts.mm(12.0) + float(i) * Parts.mm(8.0)
		EP.screw_well_face(parent, Vector3(x2, Parts.mm(-20.0), d * 0.45), Vector3(0, 0, 1), 5.0)
	Parts.cyl(parent, Parts.mm(4.5), Parts.mm(26.0), Vector3(0, 0, 0), "y", Parts.mat("bi2", Color(0.65, 0.5, 0.3), 0.45, 0.4), 12, "internal")
	EP.face_label(parent, "PTA", Vector3(0, Parts.mm(8.0), d * 0.48), 10, 0.00017)
