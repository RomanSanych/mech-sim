extends RefCounted
## Один общий электрощит: корпус, DIN TS35, шины, дверца, слоты din/door.

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const IsoElectro = preload("res://scripts/view3d/iso_electro.gd")

const CABINET_NAME := "Cabinet"
const DIN_RAILS := 3
## Рабочие полумодули на рейке (−1 с каждого конца, чтобы упор не тонул в верт. КК).
const DIN_HALFS := 38 # −4 модуля (8 полумодулей) к 46 — влезает в панель с верт. КК
const DIN_SLOTS := DIN_HALFS # совместимость имён
const DIN_END_HALFS := 1 # запас с каждого конца рейки
const DIN_MODULE_MM := 17.5
const DIN_PITCH_MM := 8.75 # шаг = 0.5 модуля
## Шаг между соседними рядами стека KK/DIN (−¼ к прежним 125 мм).
const ROW_PITCH_MM := 94.0


static func ensure(parent: Node3D, circuit) -> Node3D:
	if parent == null or circuit == null:
		return null
	var need := false
	for el in circuit.elements:
		if str(el.kind) == "electro" and str(el.electro_mount) in ["din", "door"]:
			need = true
			break
	var existing := parent.get_node_or_null(CABINET_NAME) as Node3D
	if not need:
		if existing != null:
			existing.queue_free()
		return null
	# cab_ver 18: шаг 94; рейка −4 модуля; стек КК/DIN по центру монтажной панели.
	var ver: int = int(existing.get_meta("cab_ver", 0)) if existing != null else 0
	if existing != null and ver < 18:
		if ver >= 6 and ver < 7:
			for el in circuit.elements:
				if str(el.kind) == "electro" and str(el.electro_mount) == "din" and int(el.din_slot) >= 0:
					el.din_slot = int(el.din_slot) * 2
		existing.queue_free()
		existing = null
	if existing == null:
		existing = _build(parent)
	_sync_door(existing, circuit)
	_layout_modules(existing, circuit)
	_ensure_din_stops(existing, circuit)
	_ensure_supply_cables(existing, circuit)
	return existing


static func _stops_sig(circuit) -> String:
	# Только занятость DIN — без пересборки каждый кадр.
	var parts: PackedStringArray = PackedStringArray()
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_mount) != "din":
			continue
		if str(el.member_role) == "contact" or str(el.electro_class) == "din_stop":
			continue
		if int(el.din_slot) < 0:
			continue
		parts.append("%d:%d:%d" % [int(el.id), int(el.din_slot), din_width_slots(el)])
	parts.sort()
	return "|".join(parts)


static func _supply_sig(circuit) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_class) != "supply":
			continue
		var names: PackedStringArray = PackedStringArray()
		for p in el.electro_ports:
			if typeof(p) == TYPE_DICTIONARY:
				names.append(str(p.get("name", "")))
		parts.append("%d:%s" % [int(el.id), ",".join(names)])
	parts.sort()
	return "|".join(parts)


static func _build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = CABINET_NAME
	# Низ щита на рабочей плоскости (~1.35 м), как пневмоэлементы.
	root.position = Vector3(-0.55, 1.35, -1.05)
	parent.add_child(root)

	# Корпус темнее дверцы — иначе при закрытой двери всё сливается в один блок.
	# Новые ключи mat (…_v12): кэш Parts.mat не обновляет цвет по старому имени.
	var shell_mat := Parts.mat("cab_shell_v12", Color(0.30, 0.32, 0.35), 0.34, 0.55)
	var lip_mat := Parts.mat("cab_lip_v12", Color(0.22, 0.23, 0.26), 0.22, 0.62)
	var door_mat := Parts.mat("cab_door_v12", Color(0.56, 0.58, 0.61), 0.18, 0.42)
	var door_edge := Parts.mat("cab_door_edge_v12", Color(0.20, 0.21, 0.23), 0.12, 0.68)
	var panel_mat := Parts.mat("cab_panel", Color(0.48, 0.50, 0.53), 0.18, 0.62)
	var din_mat := Parts.mat("cab_din", Color(0.58, 0.60, 0.62), 0.82, 0.38)

	var w := Parts.mm(600.0)
	var h := Parts.mm(800.0)
	var d := Parts.mm(250.0)
	Parts.box(root, Vector3(w, h, Parts.mm(8.0)), Vector3(0, h * 0.5, -d * 0.5), shell_mat, "shell")
	Parts.box(root, Vector3(Parts.mm(8.0), h, d), Vector3(-w * 0.5, h * 0.5, 0), shell_mat, "shell")
	Parts.box(root, Vector3(Parts.mm(8.0), h, d), Vector3(w * 0.5, h * 0.5, 0), shell_mat, "shell")
	Parts.box(root, Vector3(w, Parts.mm(8.0), d), Vector3(0, h, 0), shell_mat, "shell")
	Parts.box(root, Vector3(w, Parts.mm(8.0), d), Vector3(0, 0, 0), shell_mat, "shell")
	# Передний отлив проёма — под дверцей (дверца закрывает почти весь фасад).
	var lip_t: float = Parts.mm(12.0)
	var lip_z: float = d * 0.5 - Parts.mm(3.0)
	Parts.box(root, Vector3(w, lip_t, Parts.mm(5.0)), Vector3(0, h - lip_t * 0.5, lip_z), lip_mat, "shell")
	Parts.box(root, Vector3(w, lip_t, Parts.mm(5.0)), Vector3(0, lip_t * 0.5, lip_z), lip_mat, "shell")
	Parts.box(root, Vector3(lip_t, h - lip_t * 2.0, Parts.mm(5.0)), Vector3(-w * 0.5 + lip_t * 0.5, h * 0.5, lip_z), lip_mat, "shell")
	Parts.box(root, Vector3(lip_t, h - lip_t * 2.0, Parts.mm(5.0)), Vector3(w * 0.5 - lip_t * 0.5, h * 0.5, lip_z), lip_mat, "shell")

	Parts.box(root, Vector3(w * 0.92, h * 0.9, Parts.mm(4.0)), Vector3(0, h * 0.5, -d * 0.35), panel_mat, "shell")

	var rails := Node3D.new()
	rails.name = "DinRails"
	root.add_child(rails)
	var pitch: float = Parts.mm(DIN_PITCH_MM)
	# Длина рейки = полезные полуслоты + по ½ модуля с каждого конца под упор.
	# Иначе справа остаётся «пустой» кусок рейки вне DIN_HALFS (как на скрине).
	var rail_len: float = pitch * float(DIN_HALFS + 2 * DIN_END_HALFS)
	var row_pitch: float = Parts.mm(ROW_PITCH_MM)
	var panel_z: float = -d * 0.35
	var rail_z: float = panel_z + Parts.mm(2.0)
	# Стек снизу вверх: KK, DIN, KK, DIN, KK, DIN, KK — по центру монтажной панели.
	var n_stack: int = DIN_RAILS * 2 + 1
	var stack_span: float = float(n_stack - 1) * row_pitch
	var panel_cy: float = h * 0.5
	var stack0: float = panel_cy - stack_span * 0.5
	var rail_ys: PackedFloat32Array = PackedFloat32Array()
	var duct_ys: PackedFloat32Array = PackedFloat32Array()
	for si in n_stack:
		var y: float = stack0 + float(si) * row_pitch
		if si % 2 == 0:
			duct_ys.append(y)
		else:
			rail_ys.append(y)
	# Полезное поле: −½ модуля с каждого конца (упор не тонет в верт. КК).
	var slot_origin_x: float = -rail_len * 0.5 + pitch * (float(DIN_END_HALFS) + 0.5)
	for i in rail_ys.size():
		var y: float = rail_ys[i]
		var rail := Node3D.new()
		rail.name = "Rail%d" % i
		rail.position = Vector3(0, y, rail_z)
		rails.add_child(rail)
		_build_ts35_rail(rail, rail_len, din_mat)
		rail.set_meta("rail_index", i)
		rail.set_meta("slot_count", DIN_SLOTS)
		rail.set_meta("slot_pitch", pitch)
		rail.set_meta("rail_len", rail_len)
		rail.set_meta("slot_origin", Vector3(slot_origin_x, 0.0, 0.0))

	_build_cable_ducts(root, rail_len, duct_ys, panel_z)

	# Слоты под gland — только координаты; корпус gland появляется с вводным кабелем.
	var gland_pos: Array = []
	for i in 5:
		var x := -w * 0.32 + float(i) * w * 0.16
		gland_pos.append(Vector3(x, Parts.mm(6.0), d * 0.12))
	root.set_meta("gland_positions", gland_pos)

	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-w * 0.5, h * 0.5, d * 0.5)
	root.add_child(hinge)
	var door := Node3D.new()
	door.name = "Door"
	hinge.add_child(door)
	# В размер фасада: зазор ~1.5 мм с каждой стороны (не «щели»).
	var door_clear: float = Parts.mm(3.0)
	var door_w: float = w - door_clear
	var door_h: float = h - door_clear
	var door_cx: float = door_w * 0.5
	Parts.box(door, Vector3(door_w, door_h, Parts.mm(8.0)), Vector3(door_cx, 0, 0), door_mat, "shell")
	Parts.box(door, Vector3(door_w * 0.96, door_h * 0.96, Parts.mm(3.0)), Vector3(door_cx, 0, -Parts.mm(5.0)), Parts.mat("gasket", Color(0.12, 0.12, 0.13), 0.0, 0.9), "shell")
	# Тёмная рамка на лице — читаемость без уменьшения дверцы.
	var fr: float = Parts.mm(18.0)
	var fz: float = Parts.mm(3.2)
	var face_z: float = Parts.mm(4.6)
	Parts.box(door, Vector3(door_w, fr, fz), Vector3(door_cx, door_h * 0.5 - fr * 0.5, face_z), door_edge, "shell")
	Parts.box(door, Vector3(door_w, fr, fz), Vector3(door_cx, -door_h * 0.5 + fr * 0.5, face_z), door_edge, "shell")
	Parts.box(door, Vector3(fr, door_h - fr * 2.0, fz), Vector3(door_cx - door_w * 0.5 + fr * 0.5, 0, face_z), door_edge, "shell")
	Parts.box(door, Vector3(fr, door_h - fr * 2.0, fz), Vector3(door_cx + door_w * 0.5 - fr * 0.5, 0, face_z), door_edge, "shell")
	var handle := Node3D.new()
	handle.name = "Handle"
	handle.position = Vector3(door_w * 0.92, 0, Parts.mm(14.0))
	door.add_child(handle)
	Parts.box(handle, Vector3(Parts.mm(16.0), Parts.mm(90.0), Parts.mm(22.0)), Vector3.ZERO, Parts.black(), "control")
	Parts.cyl(handle, Parts.mm(8.0), Parts.mm(10.0), Vector3(0, Parts.mm(-55.0), 0), "z", Parts.alum(), 12, "control")
	var door_grid := Node3D.new()
	door_grid.name = "DoorGrid"
	door_grid.position = Vector3(door_w * 0.145, -door_h * 0.29, Parts.mm(5.0))
	door.add_child(door_grid)
	door_grid.set_meta("cols", 4)
	# Шаг ≥ габарит кнопки/лампы + наклейка в своей ячейке (не наезжает на соседа сверху).
	door_grid.set_meta("pitch", Parts.mm(62.0))
	door_grid.set_meta("area", Vector2(door_w * 0.72, door_h * 0.55))

	var modules := Node3D.new()
	modules.name = "Modules"
	root.add_child(modules)

	root.set_meta("door_open", true)
	root.set_meta("cab_ver", 18)
	root.set_meta("width", w)
	root.set_meta("height", h)
	root.set_meta("depth", d)
	_apply_hinge(root)
	return root


## Горизонтали по заданным Y стека + вертикали слева/справа на всю высоту стека.
static func _build_cable_ducts(root: Node3D, rail_len: float, duct_ys: PackedFloat32Array, panel_z: float) -> void:
	var old := root.get_node_or_null("CableDucts")
	if old != null:
		old.queue_free()
	var host := Node3D.new()
	host.name = "CableDucts"
	root.add_child(host)
	# Каталог 80×40 (Ш×В): Ш от панели (×2 — глубже канал под крышкой), В — высота пальцев.
	var duct_sh: float = Parts.mm(80.0)
	var duct_vh: float = Parts.mm(40.0)
	var duct_mat := Parts.mat("cab_duct_v17", Color(0.62, 0.64, 0.66), 0.04, 0.72)
	var lid_mat := Parts.mat("cab_duct_lid_v17", Color(0.58, 0.60, 0.62), 0.04, 0.68)
	if duct_ys.is_empty():
		return
	var duct_z: float = panel_z + Parts.mm(1.5) + duct_sh * 0.5
	var x0: float = -rail_len * 0.5
	var horizontals: Array = []
	for hi in duct_ys.size():
		var dy: float = duct_ys[hi]
		var node := Node3D.new()
		node.name = "HDuct%d" % hi
		node.position = Vector3(0, dy, duct_z)
		host.add_child(node)
		_build_perf_duct(node, rail_len, duct_vh, duct_sh, true, duct_mat, lid_mat)
		var info := {
			"kind": "h",
			"index": hi,
			"y": dy,
			"z": duct_z,
			"x0": x0,
			"x1": -x0,
			"sh": duct_sh,
			"vh": duct_vh,
		}
		node.set_meta("duct", info)
		horizontals.append(info)
	var y_bot: float = duct_ys[0] - duct_vh * 0.5
	var y_top: float = duct_ys[duct_ys.size() - 1] + duct_vh * 0.5
	var v_len: float = y_top - y_bot
	var v_cy: float = (y_bot + y_top) * 0.5
	var verticals: Array = []
	for side in [-1, 1]:
		var vx: float = side * (rail_len * 0.5 + duct_vh * 0.5 + Parts.mm(2.0))
		var node_v := Node3D.new()
		node_v.name = "VDuct%s" % ("L" if side < 0 else "R")
		node_v.position = Vector3(vx, v_cy, duct_z)
		host.add_child(node_v)
		_build_perf_duct(node_v, v_len, duct_vh, duct_sh, false, duct_mat, lid_mat)
		var vinfo := {
			"kind": "v",
			"side": side,
			"x": vx,
			"z": duct_z,
			"y0": y_bot,
			"y1": y_top,
			"sh": duct_sh,
			"vh": duct_vh,
		}
		node_v.set_meta("duct", vinfo)
		verticals.append(vinfo)
	host.set_meta("horizontals", horizontals)
	host.set_meta("verticals", verticals)
	root.set_meta("duct_z", duct_z)
	root.set_meta("duct_sh", duct_sh)
	root.set_meta("duct_vh", duct_vh)


## U-канал с пальцами и крышкой. horizontal: длина по X; иначе длина по Y (вертикаль).
static func _build_perf_duct(node: Node3D, length: float, vh: float, sh: float, horizontal: bool, body_mat: Material, lid_mat: Material) -> void:
	var wall_t: float = Parts.mm(1.6)
	var base_t: float = Parts.mm(2.0)
	var finger_pitch: float = Parts.mm(12.0)
	var finger_gap: float = Parts.mm(4.0)
	var finger_w: float = finger_pitch - finger_gap
	var lid_t: float = Parts.mm(1.8)
	# Локально: длина вдоль X; сечение Y=vh, Z=sh; база на −Z, крышка на +Z.
	# База/пальцы — control (не гаснут на рентгене); крышка — shell (просвечивает).
	var base_size := Vector3(length, vh, base_t)
	var base_c := Vector3(0, 0, -sh * 0.5 + base_t * 0.5)
	Parts.box(node, base_size, base_c, body_mat, "control")
	var side_h: float = sh - base_t
	var side_z: float = -sh * 0.5 + base_t + side_h * 0.5
	var n_fingers: int = maxi(int(floor(length / finger_pitch)), 2)
	var span: float = float(n_fingers) * finger_pitch
	var x_start: float = -span * 0.5 + finger_pitch * 0.5
	for side_y in [-1.0, 1.0]:
		var y_c: float = side_y * (vh * 0.5 - wall_t * 0.5)
		for fi in n_fingers:
			var fx: float = x_start + float(fi) * finger_pitch
			Parts.box(
				node,
				Vector3(finger_w, wall_t, side_h),
				Vector3(fx, y_c, side_z),
				body_mat,
				"control"
			)
	var lid_n: int = node.get_child_count()
	Parts.box(
		node,
		Vector3(length * 0.98, vh + Parts.mm(1.0), lid_t),
		Vector3(0, 0, sh * 0.5 - lid_t * 0.5),
		lid_mat,
		"shell"
	)
	if node.get_child_count() > lid_n:
		var lid_mi: Node = node.get_child(node.get_child_count() - 1)
		lid_mi.name = "Lid"
	if not horizontal:
		node.rotation_degrees = Vector3(0, 0, 90)


## Сведения о КК для маршрутизации проводов (мировые координаты).
## Ось ряда — из живого узла HDuct/VDuct.global_position, не из устаревшего meta+to_global.
static func cable_ducts_world(root: Node3D) -> Dictionary:
	if root == null:
		return {}
	var host := root.get_node_or_null("CableDucts") as Node3D
	if host == null:
		return {}
	var h_out: Array = []
	var v_out: Array = []
	for child in host.get_children():
		if not (child is Node3D) or not child.has_meta("duct"):
			continue
		var node: Node3D = child as Node3D
		var inf: Dictionary = node.get_meta("duct")
		var sh: float = float(inf.get("sh", Parts.mm(80.0)))
		var vh: float = float(inf.get("vh", Parts.mm(40.0)))
		var gp: Vector3 = node.global_position
		if str(inf.get("kind", "")) == "h":
			# Extent по X в local meta → world через узел (учитывает transform host/root).
			var xa: Vector3 = node.to_global(Vector3(float(inf.get("x0", 0.0)), 0.0, 0.0))
			var xb: Vector3 = node.to_global(Vector3(float(inf.get("x1", 0.0)), 0.0, 0.0))
			h_out.append({
				"y": gp.y,
				"z": gp.z,
				"x0": minf(xa.x, xb.x),
				"x1": maxf(xa.x, xb.x),
				"sh": sh,
				"vh": vh,
				"index": int(inf.get("index", h_out.size())),
			})
		else:
			# y0/y1 в meta — root-local; ось X/Z — из живого узла.
			var y0_l: float = float(inf.get("y0", 0.0))
			var y1_l: float = float(inf.get("y1", 0.0))
			var ya: Vector3 = root.to_global(Vector3(float(inf.get("x", 0.0)), y0_l, float(inf.get("z", 0.0))))
			var yb: Vector3 = root.to_global(Vector3(float(inf.get("x", 0.0)), y1_l, float(inf.get("z", 0.0))))
			v_out.append({
				"x": gp.x,
				"z": gp.z,
				"y0": minf(ya.y, yb.y),
				"y1": maxf(ya.y, yb.y),
				"sh": sh,
				"vh": vh,
				"side": int(inf.get("side", 0)),
			})
	return {"h": h_out, "v": v_out}


static func _build_ts35_rail(rail: Node3D, length: float, mat: Material) -> void:
	# TS35×7.5: длина X, ширина профиля Y=35, высота от панели Z=7.5.
	var floor_w := Parts.mm(27.0)
	Parts.box(rail, Vector3(length, floor_w, Parts.mm(1.0)), Vector3(0, 0, Parts.mm(0.5)), mat, "shell")
	var wall_h := Parts.mm(6.5)
	var wall_z := Parts.mm(1.0) + wall_h * 0.5
	Parts.box(rail, Vector3(length, Parts.mm(1.2), wall_h), Vector3(0, -Parts.mm(13.5), wall_z), mat, "shell")
	Parts.box(rail, Vector3(length, Parts.mm(1.2), wall_h), Vector3(0, Parts.mm(13.5), wall_z), mat, "shell")
	Parts.box(rail, Vector3(length, Parts.mm(3.5), Parts.mm(1.0)), Vector3(0, -Parts.mm(15.75), Parts.mm(7.0)), mat, "shell")
	Parts.box(rail, Vector3(length, Parts.mm(3.5), Parts.mm(1.0)), Vector3(0, Parts.mm(15.75), Parts.mm(7.0)), mat, "shell")
	# Овальные пазы крепления (визуально): 20×6.3, шаг 30.
	var hole := Parts.mat("din_slot", Color(0.22, 0.23, 0.25), 0.35, 0.6)
	var slot_pitch := Parts.mm(30.0)
	var slot_len := Parts.mm(20.0)
	var n: int = maxi(int(floor(length / slot_pitch)), 1)
	for i in n:
		var x: float = -length * 0.5 + Parts.mm(15.0) + float(i) * slot_pitch
		if x + slot_len * 0.5 > length * 0.5:
			break
		Parts.box(rail, Vector3(slot_len, Parts.mm(6.3), Parts.mm(0.7)), Vector3(x, 0, Parts.mm(0.95)), hole, "internal")


## Локальный Z задней грани корпуса (самое −Z). origin_z = −back_z → зад на панели.
static func _din_body_back_z(el) -> float:
	if el == null:
		return -Parts.mm(37.0)
	match str(el.electro_class):
		"psu", "generic_device":
			return -Parts.mm(29.0) # DRA d≈58
		"busbar":
			return -Parts.mm(2.0)
		"terminal":
			return -Parts.mm(18.0)
		"contactor", "voltage_relay":
			return -Parts.mm(40.0) # КМИ d≈80
		"thermal":
			return -Parts.mm(36.0)
		"relay":
			return -Parts.mm(38.0) # спинка 94.04 к DIN
		"timer_relay":
			# FAZ-корпус как у 1P АВ: задняя грань mod_step ≈ −0.38·d.
			return -Parts.mm(78.5) * 0.38
		"din_stop":
			return -Parts.mm(12.0)
		_:
			return -Parts.mm(37.0) # FAZ/DFS2 глубина ≈72–75


static func din_width_slots(el) -> int:
	# Возвращает ширину в ПОЛУМОДУЛЯХ (0.5 × 17.5 мм). 1P АВ = 2.
	if el == null:
		return 2
	var cls := str(el.electro_class)
	match cls:
		"mcb":
			return maxi(int(el.poles), 1) * 2
		"rcd", "rcbo":
			return 8 if int(el.poles) >= 4 else 4
		"contactor":
			return 5 # КМИ-10910 = 45 мм
		"thermal":
			return 6
		"psu":
			return 4
		"busbar":
			return 2 # база 1 модуль; латунь поперёк рейки
		"relay":
			# По текущему числу контактов (не только recipe_id).
			return IsoElectro.relay_din_slots(el)
		"timer_relay":
			return 3 # 1.5 модуля = 3×8.75 мм (корпус = слот − зазор)
		"voltage_relay":
			return 2
		"terminal":
			return maxi(el.electro_ports.size(), 1) # 0.5 модуля на клемму
		"din_stop":
			return 1
		_:
			return maxi(int(el.poles), 1) * 2


static func encode_din(rail_i: int, slot: int) -> int:
	return clampi(rail_i, 0, DIN_RAILS - 1) * DIN_SLOTS + clampi(slot, 0, DIN_SLOTS - 1)


static func din_rail_of(slot: int) -> int:
	return clampi(int(slot) / DIN_SLOTS, 0, DIN_RAILS - 1) # integer slots/rail


static func din_offset_of(slot: int) -> int:
	return posmod(int(slot), DIN_SLOTS)


## Мировые X (left, right) ближайшей по Y DIN-рейки к точке; Vector2.ZERO если нет щита.
static func din_nearest_rail_x_range(root: Node3D, world_pos: Vector3) -> Vector2:
	if root == null:
		return Vector2.ZERO
	var rails := root.get_node_or_null("DinRails") as Node3D
	if rails == null:
		return Vector2.ZERO
	var best_d: float = INF
	var best := Vector2.ZERO
	for child in rails.get_children():
		if not (child is Node3D):
			continue
		var rail: Node3D = child as Node3D
		var rlen: float = float(rail.get_meta("rail_len", 0.0))
		if rlen < 1.0e-4:
			var pitch: float = float(rail.get_meta("slot_pitch", Parts.mm(DIN_PITCH_MM)))
			var origin: Vector3 = rail.get_meta("slot_origin", Vector3.ZERO) as Vector3
			rlen = maxf((pitch * 0.5 - origin.x) * 2.0, pitch * float(DIN_SLOTS))
		var left_w: Vector3 = rail.to_global(Vector3(-rlen * 0.5, 0.0, 0.0))
		var right_w: Vector3 = rail.to_global(Vector3(rlen * 0.5, 0.0, 0.0))
		var mid_w: Vector3 = rail.to_global(Vector3.ZERO)
		var d: float = absf(world_pos.y - mid_w.y)
		if d < best_d:
			best_d = d
			best = Vector2(minf(left_w.x, right_w.x), maxf(left_w.x, right_w.x))
	return best


static func din_range_free(circuit, start_slot: int, width: int, exclude_id: int) -> bool:
	if circuit == null or width <= 0:
		return false
	var rail: int = din_rail_of(start_slot)
	var off: int = din_offset_of(start_slot)
	if off + width > DIN_SLOTS:
		return false
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_mount) != "din":
			continue
		if str(el.member_role) == "contact":
			continue
		if int(el.id) == exclude_id:
			continue
		var s: int = int(el.din_slot)
		if s < 0:
			continue
		if din_rail_of(s) != rail:
			continue
		var w: int = din_width_slots(el)
		var a0: int = din_offset_of(s)
		var a1: int = a0 + w
		var b0: int = off
		var b1: int = off + width
		if a0 < b1 and b0 < a1:
			return false
	return true


static func find_free_din_slot(circuit, width: int, prefer: int = 0, exclude_id: int = -1) -> int:
	width = maxi(width, 1)
	var start: int = maxi(prefer, 0)
	for s in range(start, DIN_RAILS * DIN_SLOTS):
		if din_range_free(circuit, s, width, exclude_id):
			return s
	for s in range(0, start):
		if din_range_free(circuit, s, width, exclude_id):
			return s
	return -1


static func door_cell_free(circuit, xy: Vector2, exclude_id: int) -> bool:
	if circuit == null:
		return false
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_mount) != "door":
			continue
		if str(el.member_role) == "contact":
			continue
		if int(el.id) == exclude_id:
			continue
		if absf(float(el.door_xy.x) - xy.x) < 1.0e-4 and absf(float(el.door_xy.y) - xy.y) < 1.0e-4:
			return false
	return true


static func find_free_door_xy(circuit, pitch: float, area: Vector2, cols: int, prefer_slot: int, exclude_id: int) -> Vector2:
	var max_c: int = maxi(int(floor(area.x / pitch + 1.0e-6)), 0)
	var max_r: int = maxi(int(floor(area.y / pitch + 1.0e-6)), 0)
	var total: int = (max_c + 1) * (max_r + 1)
	var start: int = clampi(prefer_slot, 0, maxi(total - 1, 0))
	for k in total:
		var idx: int = (start + k) % total
		var col: int = posmod(idx, max_c + 1)
		var row: int = int(idx / (max_c + 1))
		var xy := Vector2(float(col) * pitch, float(row) * pitch)
		if door_cell_free(circuit, xy, exclude_id):
			return xy
	return Vector2(-1, -1)


static func toggle_door(root: Node3D, circuit = null) -> void:
	if root == null:
		return
	var open: bool = not bool(root.get_meta("door_open", true))
	root.set_meta("door_open", open)
	if circuit != null:
		circuit.cabinet_door_open = open
	_apply_hinge(root, true)


static func _door_target_yaw(open: bool) -> float:
	return -90.0 if open else 0.0


static func _apply_hinge(root: Node3D, animate: bool = false) -> void:
	var hinge := root.get_node_or_null("DoorHinge") as Node3D
	if hinge == null:
		return
	var open: bool = bool(root.get_meta("door_open", true))
	var target_y: float = _door_target_yaw(open)
	if absf(hinge.rotation_degrees.y - target_y) < 0.05:
		hinge.rotation_degrees = Vector3(0, target_y, 0)
		return
	if root.has_meta("door_tween"):
		var old = root.get_meta("door_tween")
		if old is Tween and is_instance_valid(old):
			(old as Tween).kill()
		root.remove_meta("door_tween")
	if not animate or not hinge.is_inside_tree():
		hinge.rotation_degrees = Vector3(0, target_y, 0)
		return
	var tw: Tween = hinge.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(hinge, "rotation_degrees:y", target_y, 0.55)
	root.set_meta("door_tween", tw)


static func _sync_door(root: Node3D, circuit) -> void:
	if root == null:
		return
	# Старт/стоп симуляции дверцу не трогает — только ручной toggle / сохранённое состояние.
	var animate := false
	if circuit != null:
		var want: bool = bool(circuit.cabinet_door_open)
		var cur: bool = bool(root.get_meta("door_open", true))
		if want != cur:
			root.set_meta("door_open", want)
			animate = true
	if animate:
		_apply_hinge(root, true)


static func _find_module(modules: Node3D, door_grid: Node3D, el_id: int) -> Node3D:
	var key := "E%d" % el_id
	if modules != null:
		var n := modules.get_node_or_null(key) as Node3D
		if n != null and not n.is_queued_for_deletion():
			return n
	if door_grid != null:
		var n2 := door_grid.get_node_or_null(key) as Node3D
		if n2 != null and not n2.is_queued_for_deletion():
			return n2
	return null


static func _retire_module(node: Node3D) -> void:
	if node == null:
		return
	# Иначе queue_free + новый узел с тем же именем → дубликаты «призраки».
	node.name = "%s_dead_%d" % [node.name, node.get_instance_id()]
	node.queue_free()


static func _layout_modules(root: Node3D, circuit) -> void:
	var modules := root.get_node_or_null("Modules") as Node3D
	if modules == null:
		return
	var alive := {}
	var door_cursor := 0
	var rails := root.get_node_or_null("DinRails")
	var door_grid := root.get_node_or_null("DoorHinge/Door/DoorGrid") as Node3D
	# 1) Сначала закрепить DIN-слоты — от них зависит тон соседей.
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.member_role) == "contact":
			continue
		if str(el.electro_mount) != "din":
			continue
		var width0: int = din_width_slots(el)
		if int(el.din_slot) < 0 or not din_range_free(circuit, int(el.din_slot), width0, int(el.id)):
			el.din_slot = find_free_din_slot(circuit, width0, maxi(int(el.din_slot), 0), int(el.id))
	var din_shades: Dictionary = _din_neighbor_shades(circuit)
	# 2) Сборка / поза.
	for el in circuit.elements:
		if str(el.kind) != "electro":
			continue
		# Только primary/device на DIN/дверце — контакты группы живут только на схеме.
		if str(el.member_role) == "contact":
			continue
		var mount := str(el.electro_mount)
		if mount != "din" and mount != "door":
			continue
		alive[el.id] = true
		var node: Node3D = _find_module(modules, door_grid, int(el.id))
		var shade: int = int(din_shades.get(int(el.id), 0))
		var relay_fp: String = ""
		if str(el.electro_class) == "relay":
			relay_fp = "%d:%s:%s:%d" % [
				IsoElectro.relay_pole_count(el),
				IsoElectro.relay_contact_fingerprint(el),
				IsoElectro.relay_ladder_mode(el),
				shade,
			]
		elif str(el.electro_class) == "timer_relay":
			relay_fp = "kt7:%d" % shade
		var term_fp: String = ""
		if str(el.electro_class) == "terminal":
			var parts: PackedStringArray = PackedStringArray()
			parts.append("bus=%d" % (1 if bool(el.terminal_bus) else 0))
			parts.append("col=%s" % str(el.color_id))
			for pi in el.electro_ports.size():
				if typeof(el.electro_ports[pi]) != TYPE_DICTIONARY:
					continue
				var pd: Dictionary = el.electro_ports[pi]
				parts.append("%s/%s" % [str(pd.get("label", "")), str(pd.get("color_id", ""))])
			term_fp = "|".join(parts)
		var sig := "geo42|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s" % [
			el.electro_class, el.recipe_id, el.lamp_color, el.btn_color, el.poles, el.tag, el.caption,
			str(el.switch_positions), str(el.phase), el.electro_ports.size(), relay_fp, term_fp,
		]
		if node == null or str(node.get_meta("sig", "")) != sig:
			if node != null:
				_retire_module(node)
			node = Node3D.new()
			node.name = "E%d" % el.id
			# Дверные модули — дети DoorGrid: едут с дверцей, без «остатка» в открытой позе.
			var host: Node3D = door_grid if mount == "door" and door_grid != null else modules
			host.add_child(node)
			node.set_meta("din_shade", shade)
			IsoElectro.build(node, el)
			node.set_meta("sig", sig)
			node.set_meta("el_id", el.id)
			node.set_meta("electro_act", true)
		elif mount == "door" and door_grid != null and node.get_parent() != door_grid:
			node.reparent(door_grid, false)
		elif mount == "din" and node.get_parent() != modules:
			node.reparent(modules, false)
		if mount == "din" and rails != null:
			var width: int = din_width_slots(el)
			var rail_i: int = din_rail_of(int(el.din_slot))
			var slot_on_rail: int = din_offset_of(int(el.din_slot))
			var rail := rails.get_node_or_null("Rail%d" % rail_i) as Node3D
			if rail != null:
				var origin: Vector3 = rail.get_meta("slot_origin", Vector3.ZERO)
				var pitch: float = float(rail.get_meta("slot_pitch", Parts.mm(DIN_PITCH_MM)))
				var x_off: float = float(slot_on_rail) * pitch + float(width - 1) * pitch * 0.5
				# Задняя грань на плоскости панели (rail local z≈0 = лицо монтажной панели).
				var z_off: float = -_din_body_back_z(el)
				node.global_position = rail.to_global(origin + Vector3(x_off, 0.0, z_off))
				node.global_basis = rail.global_basis
		elif mount == "door" and door_grid != null:
			var cols: int = int(door_grid.get_meta("cols", 4))
			var pitch_d: float = float(door_grid.get_meta("pitch", Parts.mm(62.0)))
			var area: Vector2 = door_grid.get_meta("area", Vector2(Parts.mm(400.0), Parts.mm(400.0))) as Vector2
			if float(el.door_xy.x) < 0.0 and float(el.door_xy.y) < 0.0:
				el.door_xy = find_free_door_xy(circuit, pitch_d, area, cols, door_cursor, int(el.id))
				door_cursor += 1
			else:
				el.door_xy = snap_door_xy(el.door_xy, pitch_d, area)
				if not door_cell_free(circuit, el.door_xy, int(el.id)):
					el.door_xy = find_free_door_xy(circuit, pitch_d, area, cols, door_cursor, int(el.id))
					door_cursor += 1
			# Локально на дверце — следует за шарниром автоматически.
			node.position = Vector3(el.door_xy.x, el.door_xy.y, 0.0)
			node.basis = Basis.IDENTITY
		IsoElectro.update_state(node, el)
	for child in _module_children(modules, door_grid):
		var eid: int = int(child.get_meta("el_id", -1))
		if not alive.has(eid):
			_retire_module(child)


## Индекс чередования тона: 0/1 по порядку устройств на каждой DIN-рейке.
static func _din_neighbor_shades(circuit) -> Dictionary:
	var by_rail: Dictionary = {}
	if circuit == null:
		return {}
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_mount) != "din":
			continue
		if str(el.member_role) == "contact" or str(el.electro_class) == "din_stop":
			continue
		var slot: int = int(el.din_slot)
		if slot < 0:
			continue
		var rail_i: int = din_rail_of(slot)
		if not by_rail.has(rail_i):
			by_rail[rail_i] = []
		(by_rail[rail_i] as Array).append({"slot": din_offset_of(slot), "id": int(el.id)})
	var out: Dictionary = {}
	for rail_i2 in by_rail.keys():
		var arr: Array = by_rail[rail_i2]
		arr.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
		for i in arr.size():
			out[int(arr[i]["id"])] = i % 2
	return out


## Концевые упоры по краям занятых участков каждой DIN (авто; без УГО на схеме).
static func _ensure_din_stops(root: Node3D, circuit) -> void:
	if root == null or circuit == null:
		return
	var modules := root.get_node_or_null("Modules") as Node3D
	if modules == null:
		return
	var sig: String = "v3|" + _stops_sig(circuit)
	if str(root.get_meta("stops_sig", "")) == sig:
		return
	root.set_meta("stops_sig", sig)
	for c in modules.get_children():
		if c is Node3D and str((c as Node3D).get_meta("auto_din_stop", "")) != "":
			(c as Node3D).queue_free()
	for rail_i in DIN_RAILS:
		var occupied: Array = [] # [start_half, end_half)
		for el in circuit.elements:
			if str(el.kind) != "electro" or str(el.electro_mount) != "din":
				continue
			if str(el.member_role) == "contact" or str(el.electro_class) == "din_stop":
				continue
			if int(el.din_slot) < 0 or din_rail_of(int(el.din_slot)) != rail_i:
				continue
			var off: int = din_offset_of(int(el.din_slot))
			var w: int = din_width_slots(el)
			occupied.append([off, off + w])
		if occupied.is_empty():
			continue
		occupied.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		# Края блока: упор СЛЕВА от первого полуслота (cur0-1, может быть −1)
		# и СПРАВА в первом свободном (cur1, может быть DIN_HALFS) — без пересечения с модулем.
		var edges: Array = []
		var cur0: int = int(occupied[0][0])
		var cur1: int = int(occupied[0][1])
		for i in range(1, occupied.size()):
			var a0: int = int(occupied[i][0])
			var a1: int = int(occupied[i][1])
			if a0 <= cur1:
				cur1 = maxi(cur1, a1)
			else:
				edges.append(cur0 - 1)
				edges.append(cur1)
				cur0 = a0
				cur1 = a1
		edges.append(cur0 - 1)
		edges.append(cur1)
		var rails := root.get_node_or_null("DinRails") as Node3D
		var rail := rails.get_node_or_null("Rail%d" % rail_i) as Node3D if rails != null else null
		if rail == null:
			continue
		var origin: Vector3 = rail.get_meta("slot_origin", Vector3.ZERO)
		var pitch: float = float(rail.get_meta("slot_pitch", Parts.mm(DIN_PITCH_MM)))
		var seen_e: Dictionary = {}
		for eh in edges:
			var e: int = int(eh)
			if e < -1 or e > DIN_HALFS:
				continue
			if seen_e.has(e):
				continue
			seen_e[e] = true
			var stop := Node3D.new()
			stop.name = "AutoStop_R%d_%d" % [rail_i, e]
			stop.set_meta("auto_din_stop", "%d:%d" % [rail_i, e])
			modules.add_child(stop)
			var stop_z: float = Parts.mm(12.0)
			stop.global_position = rail.to_global(origin + Vector3(float(e) * pitch, 0.0, stop_z))
			stop.global_basis = rail.global_basis
			IsoElectro.build_din_stop_only(stop)


## Кабель ввода: оболочка до пола + жилы без оголёнки; порты на концах изоляции.
## Пересборка по id — существующие узлы E{id} не сбрасываются при добавлении второго ввода.
static func _ensure_supply_cables(root: Node3D, circuit) -> void:
	if root == null or circuit == null:
		return
	var sig: String = "v14|" + _supply_sig(circuit)
	if str(root.get_meta("supply_sig", "")) == sig:
		return
	root.set_meta("supply_sig", sig)
	var supplies: Array = []
	for el in circuit.elements:
		if str(el.kind) == "electro" and str(el.electro_class) == "supply":
			supplies.append(el)
	var holder := root.get_node_or_null("SupplyCables") as Node3D
	if supplies.is_empty():
		if holder != null:
			holder.name = "SupplyCables_dead"
			holder.free()
		return
	if holder == null:
		holder = Node3D.new()
		holder.name = "SupplyCables"
		root.add_child(holder)
	var wanted: Dictionary = {}
	for el in supplies:
		wanted[int(el.id)] = true
	var stale: Array = []
	for c in holder.get_children():
		var eid: int = int((c as Node).get_meta("el_id", -1))
		if not wanted.has(eid):
			stale.append(c)
	for c in stale:
		(c as Node).name = "dead_%d" % (c as Node).get_instance_id()
		(c as Node).free()
	var glands: Array = root.get_meta("gland_positions", []) as Array
	var w: float = float(root.get_meta("width", Parts.mm(600.0)))
	var d: float = float(root.get_meta("depth", Parts.mm(250.0)))
	var y_scene_floor: float = -float(root.position.y) - Parts.mm(2.0)
	for si in supplies.size():
		var el = supplies[si]
		var eid: int = int(el.id)
		var names: Array = []
		for p in el.electro_ports:
			if typeof(p) == TYPE_DICTIONARY:
				names.append(str(p.get("name", "")))
		if names.is_empty():
			names = ["L", "N", "PE"]
		var cable_sig: String = ",".join(names)
		var node := holder.get_node_or_null("E%d" % eid) as Node3D
		if node != null and str(node.get_meta("cable_sig", "")) == cable_sig:
			continue
		if node != null:
			node.name = "dead_%d" % node.get_instance_id()
			node.free()
		node = Node3D.new()
		node.name = "E%d" % eid
		node.set_meta("el_id", eid)
		node.set_meta("cable_sig", cable_sig)
		node.position = Vector3.ZERO
		holder.add_child(node)
		var gi: int = clampi(si, 0, 4)
		var gp: Vector3
		if gi < glands.size() and glands[gi] is Vector3:
			gp = glands[gi] as Vector3
		else:
			gp = Vector3(-w * 0.32 + float(gi) * w * 0.16, Parts.mm(6.0), d * 0.12)
		var y_top_j: float = gp.y + Parts.mm(4.0)
		var j_len: float = y_top_j - y_scene_floor
		var j_mid := Vector3(gp.x, (y_scene_floor + y_top_j) * 0.5, gp.z)
		# Оболочка + гайка gland.
		Parts.cyl(node, Parts.mm(7.4), j_len, j_mid, "y", Parts.mat("cab_cable", Color(0.08, 0.08, 0.09), 0.2, 0.7), 14, "shell")
		Parts.cyl(node, Parts.mm(9.0), Parts.mm(8.0), Vector3(gp.x, gp.y + Parts.mm(2.0), gp.z), "y", Parts.mat("gland_nut", Color(0.12, 0.12, 0.14), 0.15, 0.55), 8, "shell")
		Parts.cyl(node, Parts.mm(8.2), Parts.mm(4.0), Vector3(gp.x, gp.y + Parts.mm(8.0), gp.z), "y", Parts.mat("gland_body", Color(0.18, 0.18, 0.2), 0.2, 0.6), 12, "shell")
		var ports: Dictionary = {}
		var dirs: Dictionary = {}
		var nwire: int = names.size()
		for i in nwire:
			var nm: String = str(names[i])
			# Веер жил над gland — без пересечений.
			var ox: float = (float(i) - float(nwire - 1) * 0.5) * Parts.mm(4.0)
			var y_core0: float = gp.y + Parts.mm(10.0)
			var y_core1: float = gp.y + Parts.mm(34.0)
			var core_mid := Vector3(gp.x + ox, (y_core0 + y_core1) * 0.5, gp.z + Parts.mm(1.0))
			var tip := Vector3(gp.x + ox, y_core1, gp.z + Parts.mm(1.0))
			if nm == "PE":
				_add_pe_stripe_cyl(node, Parts.mm(1.7), y_core1 - y_core0, core_mid)
			else:
				var col: Color = _wire_gost_color(nm)
				Parts.cyl(node, Parts.mm(1.7), y_core1 - y_core0, core_mid, "y", Parts.mat("w_%s" % nm, col, 0.15, 0.55), 8, "shell")
			ports[nm] = tip
			dirs[nm] = Vector3(0, 1, 0)
		node.set_meta("ports", ports)
		node.set_meta("dirs", dirs)


static func _pe_stripe_texture() -> ImageTexture:
	var img := Image.create(8, 2, false, Image.FORMAT_RGBA8)
	for x in 8:
		var c: Color = Color(0.88, 0.78, 0.12) if x < 4 else Color(0.18, 0.62, 0.16)
		for y in 2:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _add_pe_stripe_cyl(parent: Node3D, radius: float, length: float, center: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.position = center
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _pe_stripe_texture()
	mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	mat.roughness = 0.55
	mat.metallic = 0.05
	mi.material_override = mat
	mi.set_meta("xray_role", "shell")
	parent.add_child(mi)


static func _wire_gost_color(name: String) -> Color:
	match name:
		"L", "L1":
			return Color(0.45, 0.28, 0.12) # коричневый
		"L2":
			return Color(0.08, 0.08, 0.1) # чёрный
		"L3":
			return Color(0.55, 0.56, 0.58) # серый
		"N":
			return Color(0.15, 0.35, 0.85) # синий
		"PE":
			return Color(0.55, 0.75, 0.15) # запасной solid, если текстура не применилась
		"+", "+24":
			return Color(0.45, 0.28, 0.12)
		"0", "-":
			return Color(0.55, 0.56, 0.58)
		_:
			return Color(0.2, 0.2, 0.22)


static func _module_children(modules: Node3D, door_grid: Node3D) -> Array:
	var out: Array = []
	if modules != null:
		for c in modules.get_children():
			if c is Node3D and (c as Node3D).has_meta("el_id"):
				out.append(c)
	if door_grid != null:
		for c2 in door_grid.get_children():
			if c2 is Node3D and (c2 as Node3D).has_meta("el_id"):
				out.append(c2)
	return out


static func iter_modules(root: Node3D) -> Array:
	if root == null:
		return []
	return _module_children(root.get_node_or_null("Modules") as Node3D, door_grid(root))


static func door_grid(root: Node3D) -> Node3D:
	if root == null:
		return null
	return root.get_node_or_null("DoorHinge/Door/DoorGrid") as Node3D


static func snap_door_xy(xy: Vector2, pitch: float, area: Vector2) -> Vector2:
	if pitch <= 1.0e-6:
		return Vector2(clampf(xy.x, 0.0, area.x), clampf(xy.y, 0.0, area.y))
	var max_c: int = maxi(int(floor(area.x / pitch + 1.0e-6)), 0)
	var max_r: int = maxi(int(floor(area.y / pitch + 1.0e-6)), 0)
	var col: int = clampi(int(round(xy.x / pitch)), 0, max_c)
	var row: int = clampi(int(round(xy.y / pitch)), 0, max_r)
	return Vector2(float(col) * pitch, float(row) * pitch)


static func project_door_xy(root: Node3D, origin: Vector3, dir: Vector3) -> Vector2:
	var grid := door_grid(root)
	if grid == null:
		return Vector2(-1, -1)
	var n: Vector3 = grid.global_transform.basis.z.normalized()
	var denom: float = dir.dot(n)
	if absf(denom) < 1e-5:
		return Vector2(-1, -1)
	var t: float = (grid.global_position - origin).dot(n) / denom
	if t < 0.0:
		return Vector2(-1, -1)
	var hit: Vector3 = origin + dir * t
	var local: Vector3 = grid.to_local(hit)
	var area: Vector2 = grid.get_meta("area", Vector2(0.4, 0.4)) as Vector2
	var pitch: float = float(grid.get_meta("pitch", Parts.mm(62.0)))
	return snap_door_xy(Vector2(local.x, local.y), pitch, area)


static func try_set_door_xy(circuit, el, xy: Vector2) -> bool:
	if circuit == null or el == null or xy.x < 0.0:
		return false
	if not door_cell_free(circuit, xy, int(el.id)):
		return false
	el.door_xy = xy
	return true


static func project_din_slot(root: Node3D, origin: Vector3, dir: Vector3, width: int, circuit, exclude_id: int) -> int:
	# Ближайшая рейка по лучу → слот; только если диапазон свободен.
	var rails := root.get_node_or_null("DinRails") if root != null else null
	if rails == null:
		return -1
	width = maxi(width, 1)
	var best_slot: int = -1
	var best_dist: float = 1.0e9
	for i in DIN_RAILS:
		var rail := rails.get_node_or_null("Rail%d" % i) as Node3D
		if rail == null:
			continue
		var n: Vector3 = rail.global_transform.basis.z.normalized()
		var denom: float = dir.dot(n)
		if absf(denom) < 1e-5:
			continue
		var plane_p: Vector3 = rail.to_global(Vector3(0, 0, Parts.mm(7.5)))
		var t: float = (plane_p - origin).dot(n) / denom
		if t < 0.0:
			continue
		var hit: Vector3 = origin + dir * t
		var local: Vector3 = rail.to_local(hit)
		# Рейка узкая по Y — отсечь промахи.
		if absf(local.y) > Parts.mm(40.0):
			continue
		var origin_x: float = float((rail.get_meta("slot_origin", Vector3.ZERO) as Vector3).x)
		var pitch: float = float(rail.get_meta("slot_pitch", Parts.mm(DIN_PITCH_MM)))
		# Центр модуля → индекс первого слота.
		var center_slot_f: float = (local.x - origin_x) / pitch
		var first: int = int(round(center_slot_f - float(width - 1) * 0.5))
		first = clampi(first, 0, DIN_SLOTS - width)
		var enc: int = encode_din(i, first)
		var dist: float = absf(local.y) + absf(local.z - Parts.mm(7.5)) * 0.25
		if dist < best_dist and din_range_free(circuit, enc, width, exclude_id):
			best_dist = dist
			best_slot = enc
	return best_slot


static func try_set_din_slot(circuit, el, slot: int) -> bool:
	if circuit == null or el == null or slot < 0:
		return false
	var width: int = din_width_slots(el)
	if not din_range_free(circuit, slot, width, int(el.id)):
		return false
	el.din_slot = slot
	return true


static func module_node(root: Node3D, el_id: int) -> Node3D:
	if root == null:
		return null
	var mod := _find_module(
		root.get_node_or_null("Modules") as Node3D,
		door_grid(root),
		el_id
	)
	if mod != null:
		return mod
	# Ввод питания: порты на жилах в SupplyCables/E{id}.
	var sc := root.get_node_or_null("SupplyCables/E%d" % el_id) as Node3D
	if sc != null and not sc.is_queued_for_deletion():
		return sc
	return null


## Рентген: модули с xray_capable + крышки кабель-каналов (shell).
static func apply_xray(root: Node3D, on: bool) -> void:
	if root == null:
		return
	var Iso = preload("res://scripts/view3d/iso_cylinder.gd")
	for child in _module_children(root.get_node_or_null("Modules") as Node3D, door_grid(root)):
		var n := child as Node3D
		if n == null or n.is_queued_for_deletion():
			continue
		var capable: bool = bool(n.get_meta("xray_capable", false))
		Iso.apply_xray(n, on and capable)
	var ducts := root.get_node_or_null("CableDucts") as Node3D
	if ducts != null:
		for dchild in ducts.get_children():
			if dchild is Node3D:
				Iso.apply_xray(dchild as Node3D, on)


static func pick_interact(root: Node3D, origin: Vector3, dir: Vector3) -> Dictionary:
	if root == null:
		return {}
	# Ручка дверцы — раньше модулей (иначе соседняя кнопка «съедает» наведение).
	var handle := root.get_node_or_null("DoorHinge/Door/Handle") as Node3D
	var handle_t: float = _ray_node_aabb(handle, origin, dir, 0.008)
	if handle_t >= 0.0:
		return {"kind": "door", "node": handle, "point": origin + dir * handle_t}
	var modules := root.get_node_or_null("Modules") as Node3D
	var dgrid := door_grid(root)
	var best_id: int = -1
	var best_node: Node3D = null
	var best_t: float = 1.0e9
	for child in _module_children(modules, dgrid):
		var n := child as Node3D
		if n == null or n.is_queued_for_deletion():
			continue
		# По корпусу (AABB мешей), не по сфере вокруг origin — иначе сосед «съедает» наведение.
		var t: float = _ray_node_aabb(n, origin, dir, 0.002)
		if t < 0.0 or t >= best_t:
			continue
		best_t = t
		best_node = n
		best_id = int(n.get_meta("el_id", -1))
	if best_node != null:
		var hit_pt: Vector3 = origin + dir * best_t
		return {"kind": "module", "node": best_node, "id": best_id, "point": hit_pt}
	return {}


## Луч × AABB мешей узла; pad — запас (м). −1 если промахи.
static func _ray_node_aabb(node: Node3D, origin: Vector3, dir: Vector3, pad: float = 0.0) -> float:
	if node == null or not is_instance_valid(node):
		return -1.0
	var acc := AABB()
	var started := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label3D or str(n.name) == "SchematicGlow":
			continue
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh != null and mi.visible:
				var world_aabb: AABB = mi.global_transform * mi.get_aabb()
				if world_aabb.size.length_squared() < 1.0e-12:
					pass
				elif not started:
					acc = world_aabb
					started = true
				else:
					acc = acc.merge(world_aabb)
		for ch in n.get_children():
			stack.append(ch)
	if not started:
		# Fallback: сфера у origin узла.
		var to: Vector3 = node.global_position - origin
		var t: float = to.dot(dir)
		if t < 0.0:
			return -1.0
		if (origin + dir * t).distance_to(node.global_position) <= 0.06:
			return t
		return -1.0
	if pad > 0.0:
		acc = acc.grow(pad)
	return _ray_aabb_t(origin, dir, acc)


static func _ray_aabb_t(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var tmin: float = 0.0
	var tmax: float = 1.0e9
	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var b0: float = box.position[axis]
		var b1: float = box.position[axis] + box.size[axis]
		if absf(d) < 1.0e-9:
			if o < b0 or o > b1:
				return -1.0
			continue
		var t1: float = (b0 - o) / d
		var t2: float = (b1 - o) / d
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return tmin if tmin >= 0.0 else tmax
