extends Node3D
## Трёхмерный цех: параметрические модели, мировой гизмо и поток воздуха.

const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const IsoValve = preload("res://scripts/view3d/iso_valve.gd")
const IsoJunction = preload("res://scripts/view3d/iso_junction.gd")
const IsoCabinet = preload("res://scripts/view3d/iso_cabinet.gd")
const IsoElectro = preload("res://scripts/view3d/iso_electro.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const Geom = preload("res://scripts/domain/symbol_geom.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")
const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const ATM := 101325.0
const FLOOR_TOP_Y := 0.0
## Плоскость посадки аппаратов (низ модели) — примерно уровень рук/глаз стоящего человека.
const WORK_Y := 1.35
## Высота глаз в режиме FPV.
const EYE_Y := 1.65
const FPV_SPEED := 0.48
const FLY_SPEED := 0.62
## Разгон / торможение WASD (1/с) — без рывка при нажатии/отпуске.
const MOVE_ACCEL := 5.5
const MOVE_DECEL := 7.5

var circuit = null
var mode := "move" # move | rotate
var xray := false
var cam_mode := "fly" # orbit | fly | fpv

var _camera: Camera3D
var _machines: Node3D
var _hoses: Node3D
var _flows: Node3D
var _gizmo: Node3D
var _records := {}
var _hose_nodes := {}
var _flow_pool: Array = []
# Пролёт/FPV: yaw/pitch = направление взгляда. Орбита: тот же угол — смещение камеры от цели.
var _yaw := PI - 0.55
var _pitch := -0.18
var _distance := 1.45
var _fov := 38.0 # общий FOV — иначе при смене режима «прыгает» дистанция
var _target := Vector3(0.2, WORK_Y + 0.08, 0.0)
var _fpv_pos := Vector3(0.2, EYE_Y, 1.6)
var _fly_pos := Vector3(0.55, WORK_Y + 0.28, 1.55)
var _move_vel := Vector3.ZERO
var _fpv_settle_t := 0.0 # плавный спуск к EYE_Y после орбиты сверху
var _fpv_settle_from_y := EYE_Y
const FPV_SETTLE_SEC := 0.5
## Плавный переход орбиты с куба вида.
var _orbit_anim_t := 0.0
var _orbit_anim_dur := 0.0
var _orbit_from_yaw := 0.0
var _orbit_from_pitch := 0.0
var _orbit_from_target := Vector3.ZERO
var _orbit_from_dist := 0.0
var _orbit_to_yaw := 0.0
var _orbit_to_pitch := 0.0
var _orbit_to_target := Vector3.ZERO
var _orbit_to_dist := 0.0
const ORBIT_ANIM_SEC := 0.42
var _drag := ""
var _hover := ""
var _last_hover_screen := Vector2.ZERO
var _hover_hl: MeshInstance3D
var _hover_hl_mat: StandardMaterial3D
var _hover_hl_sphere: SphereMesh
var _hover_hl_box: BoxMesh
## Призрак провода при протяжке ЛКМ (как линия в 2D).
var _wire_ghost: MeshInstance3D
var _wire_ghost_mat: StandardMaterial3D
var _drag_point := 0.0
var _drag_angle := 0.0
var _drag_pos := Vector3.ZERO
var _drag_basis := Basis.IDENTITY
var _axis := Vector3.RIGHT
var _len := 0.18
var _actuate_el_id := -1
var _actuate_side := ""
var _actuate_node: Node3D = null
var _actuate_tween: Tween = null
var _module_press := Vector2.ZERO
var _module_hit_pt := Vector3.ZERO
var _module_hit_node: Node3D = null
var _module_moved := false
var _timer_dial_kind := "" # value | unit
var _timer_dial_accum := 0.0
var _wire_port_a_id := -1
var _wire_port_a_name := ""
var _ext_hover_bound := false
## Кэш КК на кадр + флаг «после drag нужен HQ-rebuild».
var _hose_ducts_cache: Dictionary = {}
var _hose_ducts_frame: int = -1
var _hose_hq_pending: bool = false
## Разведение электропроводов: уникальная дорожка + сдвиг у клемм модуля.
var _elec_lane_by_wire: Dictionary = {} # wire_id -> int (−N…+N)
var _elec_exit_off: Dictionary = {} # "elId|port" -> Vector3
const ELEC_LANE_PITCH := 0.0055 # м между трассами (≥ Ø типичных 0.5…6 мм²)
## ПКМ: клик (свойства) vs drag (орбита/look).
var _rmb_press := Vector2.ZERO
var _rmb_moved := false
var _rmb_pending := false

signal request_element_props(el_id: int, screen: Vector2)
var _env: Environment
var _floor_mat: StandardMaterial3D
var _grid_mat: StandardMaterial3D
var _floor_mi: MeshInstance3D
var _grid_mi: MeshInstance3D


func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.65
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	apply_ui_theme()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 36, 0)
	sun.light_energy = 1.25
	# Compatibility: тени DirectionalLight иногда роняют процесс при старте/ресайзе.
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.35
	add_child(fill)

	_camera = Camera3D.new()
	_camera.fov = _fov
	_camera.near = 0.01
	_camera.current = true
	add_child(_camera)

	_add_floor()
	_machines = Node3D.new()
	_machines.name = "Machines"
	add_child(_machines)
	_hoses = Node3D.new()
	add_child(_hoses)
	_flows = Node3D.new()
	add_child(_flows)
	_gizmo = Node3D.new()
	_gizmo.name = "EditGizmo"
	add_child(_gizmo)
	_build_gizmo()
	_gizmo.visible = false
	_ensure_hover_hl()
	_ensure_wire_ghost()
	_aim_fly_at_target()
	for _i in 72:
		var dot := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.006
		mesh.height = 0.012
		dot.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.55, 0.86, 1.0, 0.85)
		dot.material_override = mat
		dot.visible = false
		_flows.add_child(dot)
		_flow_pool.append(dot)
	_place_camera()


func handle_view_event(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_cancel_orbit_anim()
		if cam_mode == "fpv":
			_fpv_pos += _look_flat() * 0.11 * _cam_mod()
			_clamp_fpv_pos()
		elif cam_mode == "fly":
			_fly_pos += _look_dir() * 0.14 * _cam_mod()
			_clamp_fly_pos()
		else:
			var near_f := 0.89 if _distance < 0.35 else (0.92 if _distance < 0.8 else 0.95)
			_distance = clampf(_distance * near_f, 0.018, 8.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_cancel_orbit_anim()
		if cam_mode == "fpv":
			_fpv_pos -= _look_flat() * 0.11 * _cam_mod()
			_clamp_fpv_pos()
		elif cam_mode == "fly":
			_fly_pos -= _look_dir() * 0.14 * _cam_mod()
			_clamp_fly_pos()
		else:
			var far_f := 1.12 if _distance < 0.35 else (1.08 if _distance < 0.8 else 1.05)
			_distance = clampf(_distance * far_f, 0.018, 8.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_cancel_orbit_anim()
			_rmb_press = event.position
			_rmb_moved = false
			_rmb_pending = true
			# Орбиту/look включаем только после сдвига — иначе клик сразу крутит камеру.
			_drag = ""
		else:
			_drag = ""
			if not _rmb_moved:
				_rmb_try_open_props(_rmb_press)
			_rmb_pending = false
			_rmb_moved = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if cam_mode == "orbit":
			if event.pressed:
				_cancel_orbit_anim()
			_drag = "pan" if event.pressed else ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_cancel_orbit_anim()
			_begin_pick(event.position)
		elif _drag == "actuate":
			_end_actuate()
		elif _drag == "electro_btn":
			var bel = circuit.get_element(_actuate_el_id) if circuit != null else null
			if bel != null and str(bel.kind) == "electro" and not bool(bel.latching):
				bel.pressed = false
			_drag = ""
			_actuate_el_id = -1
		elif _drag == "timer_dial":
			_drag = ""
			_timer_dial_kind = ""
			_timer_dial_accum = 0.0
			_actuate_el_id = -1
			_module_hit_node = null
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "door_module" or _drag == "din_module":
			var mod_id: int = _actuate_el_id
			var was_click: bool = not _module_moved and bool(circuit != null and circuit.running)
			var hit_pt: Vector3 = _module_hit_pt
			var hit_node: Node3D = _module_hit_node
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			_module_moved = false
			_hose_hq_pending = true
			if circuit != null:
				if was_click:
					var mel = circuit.get_element(mod_id)
					if mel != null:
						_click_electro_3d(mel, hit_pt, hit_node)
				else:
					circuit.touch_scene()
		elif _drag == "gizmo":
			_hose_hq_pending = true
			if circuit != null:
				circuit.touch_scene()
			_drag = ""
		elif _drag == "wire_port":
			_finish_wire_port(event.position)
		elif _drag == "click":
			_drag = ""
	elif event is InputEventMouseMotion and _rmb_pending and _drag == "":
		_last_hover_screen = event.position
		if event.position.distance_to(_rmb_press) > 4.0:
			_rmb_moved = true
			_rmb_pending = false
			_drag = "orbit" if cam_mode == "orbit" else "look"
			_on_drag(event)
	elif event is InputEventMouseMotion and _drag != "" and _drag != "actuate":
		_on_drag(event)
	elif event is InputEventMouseMotion:
		_hover_gizmo(event.position)
		_last_hover_screen = event.position


func _aim_fly_at_target() -> void:
	# Стартовый пролёт смотрит на рабочую точку, а не «в пустоту» за камерой.
	var to: Vector3 = _target - _fly_pos
	if to.length_squared() < 1e-6:
		to = Vector3(0, -0.1, -1)
	to = to.normalized()
	_yaw = atan2(to.x, to.z)
	_pitch = clampf(asin(clampf(to.y, -1.0, 1.0)), -1.45, 1.45)
	_fpv_pos = Vector3(_fly_pos.x, EYE_Y, _fly_pos.z)
	_place_camera()


func _drag_locks_hover() -> bool:
	return _drag in ["timer_dial", "din_module", "door_module", "actuate", "electro_btn", "gizmo", "wire_port"]


func _bind_ext_hover() -> void:
	if _ext_hover_bound or circuit == null:
		return
	if circuit.has_signal("hover_port_changed"):
		circuit.hover_port_changed.connect(_on_circuit_hover_port_changed)
		_ext_hover_bound = true


func _on_circuit_hover_port_changed() -> void:
	if circuit == null:
		return
	if str(circuit.hover_space) != "schematic":
		return
	_apply_schematic_hover_hl()


func _apply_schematic_hover_hl() -> void:
	if circuit == null:
		return
	var wid: int = int(circuit.hover_wire_id)
	if wid >= 0:
		var hose: Node3D = _hose_nodes.get(wid, null)
		if hose != null:
			var pts: PackedVector3Array = hose.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
			var hr: float = float(hose.get_meta("tube_radius", 0.0025))
			if pts.size() >= 2:
				var mid_i: int = int(pts.size() / 2)
				_show_hover_hl_sphere(pts[mid_i], maxf(hr * 2.4, 0.0045))
			else:
				_show_hover_hl_sphere(hose.global_position, 0.006)
			return
		clear_hover_highlight()
		return
	var eid: int = int(circuit.hover_el_id)
	if eid < 0:
		clear_hover_highlight()
		return
	var port: String = str(circuit.hover_port)
	if port != "":
		var pos = _port_world(eid, port)
		if pos != null:
			_show_hover_hl_port(pos as Vector3, _port_dir_world(eid, port))
			return
	var root: Node3D = _electro_port_root(eid)
	if root == null:
		var rec = _records.get(eid, null)
		if rec != null:
			root = rec["root"] as Node3D
	if root != null:
		_show_hover_hl_node(root)
	else:
		clear_hover_highlight()


## Текст всплывающей подсказки под курсором (обозначение или Tag:контакт) + подсветка зоны.
func hover_tip_at(screen: Vector2 = Vector2.INF) -> String:
	if circuit == null or _camera == null:
		clear_hover_highlight()
		return ""
	_bind_ext_hover()
	# Пока ЛКМ удерживает элемент — не перехватывать хитбокс соседа под курсором.
	if _drag_locks_hover() and _drag != "wire_port":
		return _hover_tip_locked()
	var scr: Vector2 = _last_hover_screen if screen == Vector2.INF else screen
	var ray := _ray(scr)
	var origin: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var port_hit: Dictionary = _pick_port_hover(origin, dir)
	if not port_hit.is_empty():
		_show_hover_hl_port(
			port_hit["pos"] as Vector3,
			port_hit.get("dir", Vector3.UP) as Vector3
		)
		circuit.set_hover("workshop", int(port_hit.get("id", -1)), str(port_hit.get("port", "")), -1)
		return str(port_hit["tip"])
	# Провод/трубка в 3D.
	var hose_hit: Dictionary = _pick_hose_hover(origin, dir)
	if not hose_hit.is_empty():
		var hid: int = int(hose_hit.get("id", -1))
		var hit_pos: Vector3 = hose_hit.get("pos", Vector3.ZERO) as Vector3
		var hit_r: float = float(hose_hit.get("radius", 0.003))
		_show_hover_hl_sphere(hit_pos, maxf(hit_r * 2.4, 0.0045))
		circuit.set_hover("workshop", -1, "", hid)
		return str(hose_hit.get("tip", "Линия"))
	# Щит: ручка дверцы / электромодуль.
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab != null:
		var hit_cab: Dictionary = IsoCabinet.pick_interact(cab, origin, dir)
		var cab_kind: String = str(hit_cab.get("kind", ""))
		if cab_kind == "door":
			var hnode: Node3D = hit_cab.get("node", null) as Node3D
			if hnode != null:
				_show_hover_hl_node(hnode)
			if str(circuit.hover_space) == "workshop":
				circuit.clear_hover("workshop")
			var open: bool = bool(cab.get_meta("door_open", true))
			return "Дверца щита · %s" % ("закрыть" if open else "открыть")
		if cab_kind == "module":
			var eid: int = int(hit_cab.get("id", -1))
			var eel = circuit.get_element(eid)
			var mnode: Node3D = hit_cab.get("node", null) as Node3D
			if eel != null:
				if str(eel.electro_class) == "timer_relay" and mnode != null:
					var hit_pt: Vector3 = hit_cab.get("point", Vector3.ZERO) as Vector3
					var zone_tip: String = _timer_zone_tip(eel, mnode, hit_pt)
					if zone_tip != "":
						_show_timer_zone_hl(mnode, zone_tip)
						return zone_tip
				_show_hover_hl_node(mnode)
				circuit.set_hover("workshop", eid, "", -1)
				return str(eel.tag)
	# Пневматика / прочие машины.
	var mid: int = _pick_machine(origin, dir)
	if mid >= 0:
		var mel = circuit.get_element(mid)
		var rec = _records.get(mid, null)
		if mel != null:
			if rec != null:
				_show_hover_hl_node(rec["root"] as Node3D)
			else:
				clear_hover_highlight()
			circuit.set_hover("workshop", mid, "", -1)
			return str(mel.tag)
	# Подсветка с 2D, если в 3D ничего не нашли.
	if str(circuit.hover_space) == "schematic":
		_apply_schematic_hover_hl()
		return ""
	if str(circuit.hover_space) == "workshop":
		circuit.clear_hover("workshop")
	clear_hover_highlight()
	return ""


func _pick_hose_hover(origin: Vector3, dir: Vector3) -> Dictionary:
	var best_t: float = 1.0e9
	var best_id: int = -1
	var best_node: Node3D = null
	var best_pos := Vector3.ZERO
	var best_r: float = 0.003
	var dlen: float = dir.length()
	if dlen < 1.0e-10:
		return {}
	var dnorm: Vector3 = dir / dlen
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid]
		if node == null or not node.visible:
			continue
		var mi: MeshInstance3D = node.get_node_or_null("Tube") as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var pts: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
		if pts.size() < 2:
			continue
		var radius: float = float(node.get_meta("tube_radius", 0.0025))
		# Широкий AABB — только отсев; хит — по капсулам вдоль полилинии (+офсет).
		var box: AABB = mi.global_transform * mi.get_aabb()
		box = box.grow(radius + 0.004)
		if _ray_aabb(origin, dnorm, box) < 0.0:
			continue
		var hit_r: float = radius + 0.0028
		var t: float = _ray_polyline_capsule(origin, dnorm, pts, hit_r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_id = int(wid)
			best_node = node
			best_pos = origin + dnorm * t
			best_r = radius
	if best_id < 0:
		return {}
	var tip := "Линия"
	var w = circuit.get_wire(best_id) if circuit != null else null
	if w != null:
		var ea = circuit.get_element(int(w.a_id))
		var is_elec: bool = ea != null and Geom.port_domain(ea, str(w.a_port)) == "electric"
		tip = "Провод" if is_elec else "Трубка"
		if str(w.color_id) != "":
			tip += " · %s" % str(w.color_id)
	return {"id": best_id, "node": best_node, "tip": tip, "pos": best_pos, "radius": best_r}


## Луч × трубка по полилинии (капсулы на сегментах). t ≥ 0 или −1.
func _ray_polyline_capsule(origin: Vector3, dir: Vector3, pts: PackedVector3Array, radius: float) -> float:
	var best: float = -1.0
	for i in range(pts.size() - 1):
		var t: float = _ray_capsule(origin, dir, pts[i], pts[i + 1], radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Луч × капсула (отрезок + сферы на концах). dir — единичный.
func _ray_capsule(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var ab: Vector3 = b - a
	var ab_len: float = ab.length()
	var best: float = -1.0
	if ab_len < 1.0e-7:
		return _ray_sphere(origin, dir, a, radius)
	var ab_n: Vector3 = ab / ab_len
	var ao: Vector3 = origin - a
	var d_ab: float = dir.dot(ab_n)
	var ao_ab: float = ao.dot(ab_n)
	var m: Vector3 = dir - ab_n * d_ab
	var n: Vector3 = ao - ab_n * ao_ab
	var aa: float = m.dot(m)
	var bb: float = 2.0 * m.dot(n)
	var cc: float = n.dot(n) - radius * radius
	if aa > 1.0e-12:
		var disc: float = bb * bb - 4.0 * aa * cc
		if disc >= 0.0:
			var s: float = sqrt(disc)
			for k in 2:
				var t: float = (-bb + (s if k == 0 else -s)) / (2.0 * aa)
				if t < 0.0:
					continue
				var u: float = ao_ab + t * d_ab
				if u < 0.0 or u > ab_len:
					continue
				if best < 0.0 or t < best:
					best = t
	var ta: float = _ray_sphere(origin, dir, a, radius)
	var tb: float = _ray_sphere(origin, dir, b, radius)
	if ta >= 0.0 and (best < 0.0 or ta < best):
		best = ta
	if tb >= 0.0 and (best < 0.0 or tb < best):
		best = tb
	return best


func _ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc: Vector3 = origin - center
	var b: float = dir.dot(oc)
	var c: float = oc.dot(oc) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		return -1.0
	var sd: float = sqrt(disc)
	var t0: float = -b - sd
	if t0 >= 0.0:
		return t0
	var t1: float = -b + sd
	return t1 if t1 >= 0.0 else -1.0


func clear_hover_highlight() -> void:
	if _hover_hl != null:
		_hover_hl.visible = false


func _ensure_wire_ghost() -> void:
	if _wire_ghost != null:
		return
	_wire_ghost = MeshInstance3D.new()
	_wire_ghost.name = "WireGhost"
	_wire_ghost_mat = StandardMaterial3D.new()
	_wire_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire_ghost_mat.albedo_color = Color(0.25, 0.72, 1.0, 0.48)
	_wire_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wire_ghost_mat.no_depth_test = true
	_wire_ghost_mat.render_priority = 20
	_wire_ghost.material_override = _wire_ghost_mat
	_wire_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wire_ghost.visible = false
	add_child(_wire_ghost)


func _hide_wire_ghost() -> void:
	if _wire_ghost != null:
		_wire_ghost.visible = false


## Резинка при протяжке: клемма → курсор (или snap к целевой клемме).
func _update_wire_ghost(screen: Vector2) -> void:
	_ensure_wire_ghost()
	if _wire_port_a_id < 0 or _wire_port_a_name == "" or _camera == null:
		_hide_wire_ghost()
		return
	var start = _port_world(_wire_port_a_id, _wire_port_a_name)
	if start == null:
		_hide_wire_ghost()
		return
	var a: Vector3 = start as Vector3
	var da: Vector3 = _port_dir_world(_wire_port_a_id, _wire_port_a_name)
	var na: Vector3 = da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var a1: Vector3 = a + na * 0.008
	var ray := _ray(screen)
	var hit: Dictionary = _pick_port_hover(ray["origin"], ray["dir"])
	var tip: Vector3
	var snapped: bool = false
	if not hit.is_empty():
		var bid: int = int(hit.get("id", -1))
		var bport: String = str(hit.get("port", ""))
		if bid >= 0 and bport != "" and not (bid == _wire_port_a_id and bport == _wire_port_a_name):
			tip = hit["pos"] as Vector3
			snapped = true
	if not snapped:
		# Та же «глубина», что у стартовой клеммы от камеры — линия едет за мышью на экране.
		var depth: float = _camera.global_position.distance_to(a)
		depth = clampf(depth, 0.06, 6.0)
		tip = (ray["origin"] as Vector3) + (ray["dir"] as Vector3) * depth
		var stretch: Vector3 = tip - a1
		var max_len: float = 1.4
		if stretch.length() > max_len:
			tip = a1 + stretch.normalized() * max_len
	var pts := PackedVector3Array()
	pts.append(a)
	pts.append(a1)
	if snapped:
		var db: Vector3 = hit.get("dir", Vector3.UP) as Vector3
		var nb: Vector3 = db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
		var b1: Vector3 = tip + nb * 0.008
		# Короткий орто-мостик: не полный роутер, но понятнее прямой линии в корпус.
		if absf(a1.x - b1.x) > 0.002 and absf(a1.y - b1.y) > 0.002:
			pts.append(Vector3(a1.x, b1.y, a1.z))
		pts.append(b1)
		pts.append(tip)
		_wire_ghost_mat.albedo_color = Color(0.35, 0.95, 0.55, 0.58)
	else:
		pts.append(tip)
		_wire_ghost_mat.albedo_color = Color(0.25, 0.72, 1.0, 0.48)
	_wire_ghost.mesh = _build_tube_mesh(pts, 0.00115, 7)
	_wire_ghost.visible = pts.size() >= 2


func _ensure_hover_hl() -> void:
	if _hover_hl != null:
		return
	_hover_hl = MeshInstance3D.new()
	_hover_hl.name = "HoverHighlight"
	_hover_hl_sphere = SphereMesh.new()
	_hover_hl_sphere.radius = 0.009
	_hover_hl_sphere.height = 0.018
	_hover_hl_box = BoxMesh.new()
	_hover_hl_box.size = Vector3.ONE
	_hover_hl.mesh = _hover_hl_sphere
	_hover_hl_mat = StandardMaterial3D.new()
	_hover_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_hl_mat.albedo_color = Color(1.0, 0.82, 0.22, 0.42)
	_hover_hl_mat.emission_enabled = true
	_hover_hl_mat.emission = Color(1.0, 0.78, 0.18)
	_hover_hl_mat.emission_energy_multiplier = 0.85
	_hover_hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_hl.material_override = _hover_hl_mat
	_hover_hl.visible = false
	_hover_hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hover_hl)


func _show_hover_hl_sphere(world_pos: Vector3, radius: float) -> void:
	_ensure_hover_hl()
	_hover_hl_sphere.radius = radius
	_hover_hl_sphere.height = radius * 2.0
	_hover_hl.mesh = _hover_hl_sphere
	_hover_hl.global_position = world_pos
	_hover_hl.scale = Vector3.ONE
	_hover_hl.global_basis = Basis.IDENTITY
	_hover_hl.visible = true


## Плоский куб по зеву клеммы: основание ≈ разъём, малая высота вдоль входа провода.
func _show_hover_hl_port(world_pos: Vector3, world_dir: Vector3) -> void:
	_ensure_hover_hl()
	_hover_hl.mesh = _hover_hl_box
	var n: Vector3 = world_dir.normalized() if world_dir.length_squared() > 1.0e-8 else Vector3.UP
	_hover_hl.global_basis = _basis_y_from_normal(n)
	# Чуть наружу по оси входа — без z-fighting с зевом.
	_hover_hl.global_position = world_pos + n * 0.0009
	_hover_hl.scale = _port_hit_size()
	_hover_hl.visible = true


func _port_hit_size() -> Vector3:
	# X/Z — основание разъёма, Y — вдоль входа; чуть больше зева (5.5×2.6×5.0).
	return Vector3(0.0064, 0.0034, 0.0058)


func _basis_y_from_normal(n: Vector3) -> Basis:
	var y: Vector3 = n.normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var x: Vector3 = ref.cross(y)
	if x.length_squared() < 1.0e-8:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


func _show_hover_hl_node(node: Node3D) -> void:
	_ensure_hover_hl()
	if node == null or not is_instance_valid(node):
		clear_hover_highlight()
		return
	var aabb: AABB = _node_world_aabb(node)
	if aabb.size.length_squared() < 1.0e-8:
		_show_hover_hl_sphere(node.global_position, 0.035)
		return
	_hover_hl.mesh = _hover_hl_box
	_hover_hl.global_basis = Basis.IDENTITY
	_hover_hl.global_position = aabb.get_center()
	_hover_hl.scale = aabb.size * 1.06 + Vector3(0.004, 0.004, 0.004)
	_hover_hl.visible = true


func _node_world_aabb(node: Node3D) -> AABB:
	var acc := AABB()
	var has: bool = false
	if node == null:
		return acc
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh != null and mi.visible:
				var local_aabb: AABB = mi.get_aabb()
				var world_aabb: AABB = mi.global_transform * local_aabb
				if not has:
					acc = world_aabb
					has = true
				else:
					acc = acc.merge(world_aabb)
		for ch in n.get_children():
			stack.append(ch)
	return acc


func _pick_port_hover(origin: Vector3, dir: Vector3) -> Dictionary:
	var best_t: float = 1.0e9
	var best_tag := ""
	var best_port := ""
	var best_el = null
	var best_pos := Vector3.ZERO
	var best_dir := Vector3.UP
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab != null:
		for node in IsoCabinet.iter_modules(cab):
			if node == null:
				continue
			var eid: int = int(node.get_meta("el_id", -1))
			var el = circuit.get_element(eid)
			if el == null:
				continue
			var hit := _nearest_port_on_node(node, origin, dir)
			if hit.is_empty():
				continue
			var t: float = float(hit["t"])
			if t < best_t:
				best_t = t
				best_tag = str(el.tag)
				best_port = str(hit["port"])
				best_el = el
				best_pos = hit["pos"] as Vector3
				best_dir = hit["dir"] as Vector3
	for id in _records.keys():
		var root: Node3D = _records[id]["root"]
		if root == null:
			continue
		var el2 = circuit.get_element(int(id))
		if el2 == null:
			continue
		var hit2 := _nearest_port_on_node(root, origin, dir)
		if hit2.is_empty():
			continue
		var t2: float = float(hit2["t"])
		if t2 < best_t:
			best_t = t2
			best_tag = str(el2.tag)
			best_port = str(hit2["port"])
			best_el = el2
			best_pos = hit2["pos"] as Vector3
			best_dir = hit2["dir"] as Vector3
	if best_port == "" or best_el == null:
		return {}
	var role: String = ""
	if str(best_el.kind) == "electro":
		role = IsoElectro.port_contact_role(best_el, best_port)
	var tip: String = "%s:%s(%s)" % [best_tag, best_port, role] if role != "" else "%s:%s" % [best_tag, best_port]
	return {"tip": tip, "pos": best_pos, "port": best_port, "dir": best_dir, "id": int(best_el.id)}


func _nearest_port_on_node(node: Node3D, origin: Vector3, dir: Vector3) -> Dictionary:
	if node == null or not node.has_meta("ports"):
		return {}
	var ports = node.get_meta("ports")
	if typeof(ports) != TYPE_DICTIONARY:
		return {}
	var dirs: Dictionary = {}
	if node.has_meta("dirs") and typeof(node.get_meta("dirs")) == TYPE_DICTIONARY:
		dirs = node.get_meta("dirs")
	var half: Vector3 = _port_hit_size() * 0.5
	var best_t: float = 1.0e9
	var best_name := ""
	var best_pos := Vector3.ZERO
	var best_dir := Vector3.UP
	for pname in ports.keys():
		var nm: String = str(pname)
		if not _is_tip_port_name(nm):
			continue
		var local_pos: Vector3 = ports[pname] as Vector3
		var world: Vector3 = node.to_global(local_pos)
		var local_dir: Vector3 = dirs.get(nm, Vector3(0, 1, 0)) as Vector3
		if local_dir.length_squared() < 1.0e-8:
			local_dir = Vector3(0, 1, 0)
		var world_dir: Vector3 = node.global_transform.basis * local_dir
		if world_dir.length_squared() < 1.0e-8:
			world_dir = Vector3.UP
		else:
			world_dir = world_dir.normalized()
		var basis: Basis = _basis_y_from_normal(world_dir)
		var t: float = _ray_obb(origin, dir, world, basis, half)
		if t < 0.0 or t >= best_t:
			continue
		best_t = t
		best_name = nm
		best_pos = world
		best_dir = world_dir
	if best_name == "":
		return {}
	return {"t": best_t, "port": best_name, "pos": best_pos, "dir": best_dir}


## Луч × ориентированный бокс; t вдоль dir или −1.
func _ray_obb(origin: Vector3, dir: Vector3, center: Vector3, basis: Basis, half: Vector3) -> float:
	var inv: Basis = basis.inverse()
	var o: Vector3 = inv * (origin - center)
	var d: Vector3 = inv * dir
	var tmin: float = 0.0
	var tmax: float = 1.0e9
	for axis in 3:
		var oi: float = o[axis]
		var di: float = d[axis]
		var hi: float = half[axis]
		if absf(di) < 1.0e-9:
			if oi < -hi or oi > hi:
				return -1.0
			continue
		var t1: float = (-hi - oi) / di
		var t2: float = (hi - oi) / di
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin if tmin >= 0.0 else (tmax if tmax >= 0.0 else -1.0)


func _is_tip_port_name(name: String) -> bool:
	# Якоря проводов C1A/C2B — не показываем как клемму.
	if name.length() >= 3 and name[0] == "C":
		var last: String = name[name.length() - 1]
		if last == "A" or last == "B":
			var mid := name.substr(1, name.length() - 2)
			if mid.is_valid_int():
				return false
	return true


func _process(dt: float) -> void:
	match cam_mode:
		"fpv":
			_fpv_settle_height(dt)
			_fpv_move(dt)
		"fly":
			_fly_move(dt)
		_:
			# Орбита: только анимация куба; WASD сюда больше не двигает фокус.
			if _orbit_anim_t > 0.0:
				_step_orbit_anim(dt)
	_place_camera()
	if circuit == null:
		return
	# В симуляции — лёгкий апдейт поз/штока; полный сиг — только в редактировании.
	_sync_machines(circuit.running)
	var cab := IsoCabinet.ensure(_machines, circuit)
	if cab != null and xray:
		IsoCabinet.apply_xray(cab, true)
	_sync_hoses()
	if circuit.running or circuit.sim_time > 0.0:
		_sync_flows()
	else:
		for puff in _flow_pool:
			puff.visible = false
	if not circuit.running or (Engine.get_process_frames() % 2) == 0:
		_sync_gizmo()


func get_orbit() -> Vector2:
	return Vector2(_yaw, _pitch)


func set_orbit(yaw: float, pitch: float) -> void:
	# Мгновенно (без анимации) — для внутренних вызовов.
	_cancel_orbit_anim()
	_yaw = yaw
	# Для видов сверху/снизу с куба — почти ±90°; орбита мышью чуть уже.
	_pitch = clampf(pitch, -1.55, 1.55)
	_place_camera()


## Куб вида: плавно повернуть камеру и сфокусировать на выделении / сцене.
func orbit_to_view(yaw: float, pitch: float) -> void:
	# Куб работает только в орбите.
	if cam_mode != "orbit":
		return
	var focus: Dictionary = _view_focus()
	var to_target: Vector3 = focus["center"] as Vector3
	var to_dist: float = float(focus["distance"])
	var to_yaw: float = yaw
	var to_pitch: float = clampf(pitch, -1.55, 1.55)
	# Уже почти там — без анимации.
	var yaw_d: float = absf(wrapf(to_yaw - _yaw, -PI, PI))
	var pitch_d: float = absf(to_pitch - _pitch)
	var target_d: float = _target.distance_to(to_target)
	var dist_d: float = absf(to_dist - _distance)
	if yaw_d < 0.02 and pitch_d < 0.02 and target_d < 0.01 and dist_d < 0.01:
		_yaw = to_yaw
		_pitch = to_pitch
		_target = to_target
		_distance = to_dist
		_place_camera()
		return
	_orbit_from_yaw = _yaw
	_orbit_from_pitch = _pitch
	_orbit_from_target = _target
	_orbit_from_dist = _distance
	_orbit_to_yaw = _orbit_from_yaw + wrapf(to_yaw - _orbit_from_yaw, -PI, PI)
	_orbit_to_pitch = to_pitch
	_orbit_to_target = to_target
	_orbit_to_dist = to_dist
	_orbit_anim_dur = ORBIT_ANIM_SEC
	_orbit_anim_t = ORBIT_ANIM_SEC


func _cancel_orbit_anim() -> void:
	_orbit_anim_t = 0.0
	_orbit_anim_dur = 0.0


func _step_orbit_anim(dt: float) -> void:
	if _orbit_anim_dur <= 1e-6:
		_cancel_orbit_anim()
		return
	_orbit_anim_t = maxf(_orbit_anim_t - dt, 0.0)
	var u: float = 1.0 - _orbit_anim_t / _orbit_anim_dur
	# smoothstep
	u = u * u * (3.0 - 2.0 * u)
	_yaw = lerpf(_orbit_from_yaw, _orbit_to_yaw, u)
	_pitch = lerpf(_orbit_from_pitch, _orbit_to_pitch, u)
	_target = _orbit_from_target.lerp(_orbit_to_target, u)
	_distance = lerpf(_orbit_from_dist, _orbit_to_dist, u)
	if _orbit_anim_t <= 0.0:
		_yaw = _orbit_to_yaw
		_pitch = _orbit_to_pitch
		_target = _orbit_to_target
		_distance = _orbit_to_dist
		_cancel_orbit_anim()


## Центр и дистанция для куба вида: выделение → иначе вся сцена.
func _view_focus() -> Dictionary:
	var box := _focus_aabb()
	var center: Vector3 = box.get_center()
	# Не уводим фокус под пол.
	center.y = maxf(center.y, WORK_Y * 0.35)
	var radius: float = maxf(box.size.length() * 0.5, 0.08)
	var half_fov: float = deg_to_rad(maxf(_fov, 12.0)) * 0.5
	var dist: float = radius / maxf(tan(half_fov), 0.05) * 1.45
	dist = clampf(dist, 0.12, 8.0)
	return {"center": center, "distance": dist}


func _focus_aabb() -> AABB:
	var acc := AABB()
	var started := false
	# 1) Выделение в цехе — смотрим на выбранное.
	if circuit != null and str(circuit.selection_space) == "workshop" and not circuit.selected_ids.is_empty():
		for id in circuit.selected_ids:
			var part := _element_world_aabb(int(id))
			if part.size.length_squared() < 1.0e-10:
				continue
			if not started:
				acc = part
				started = true
			else:
				acc = acc.merge(part)
		if started:
			return acc.grow(0.02)
	# 2) Иначе — вся сцена (машины + щит).
	for id in _records.keys():
		var root: Node3D = _records[id]["root"]
		if root == null or not is_instance_valid(root):
			continue
		var wa := _node_world_aabb(root)
		if wa.size.length_squared() < 1.0e-10:
			continue
		if not started:
			acc = wa
			started = true
		else:
			acc = acc.merge(wa)
	if _machines != null:
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab != null and is_instance_valid(cab):
			var ca := _node_world_aabb(cab)
			if ca.size.length_squared() > 1.0e-10:
				if not started:
					acc = ca
					started = true
				else:
					acc = acc.merge(ca)
	if not started:
		return AABB(_target - Vector3(0.35, 0.25, 0.35), Vector3(0.7, 0.5, 0.7))
	return acc.grow(0.04)


func _element_world_aabb(el_id: int) -> AABB:
	if circuit == null:
		return AABB()
	var el = circuit.get_element(el_id)
	if el == null:
		return AABB()
	if _is_cabinet_electro(el):
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
		if cab != null:
			var node := IsoCabinet.module_node(cab, el_id)
			if node != null:
				return _node_world_aabb(node)
	var rec = _records.get(el_id, null)
	if rec != null:
		var root: Node3D = rec.get("root", null)
		if root != null and is_instance_valid(root):
			return _node_world_aabb(root)
	var p: Vector3 = el.world_pos if el != null else _target
	return AABB(p - Vector3(0.08, 0.08, 0.08), Vector3(0.16, 0.16, 0.16))


func get_cam_mode() -> String:
	return cam_mode


func set_cam_mode(mode_name: String) -> void:
	var next: String = str(mode_name)
	if next != "orbit" and next != "fly" and next != "fpv":
		next = "orbit"
	if next == cam_mode:
		return
	_cancel_orbit_anim()
	# Сохраняем взгляд и позицию — без визуального скачка.
	var cam_pos: Vector3 = _camera.global_position if _camera != null else (
		_fpv_pos if cam_mode == "fpv" else (_fly_pos if cam_mode == "fly" else _target + _look_dir() * _distance)
	)
	var forward: Vector3 = -_camera.global_transform.basis.z if _camera != null else (
		_look_dir() if cam_mode != "orbit" else -_look_dir()
	)
	if forward.length_squared() < 1e-8:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	if _camera != null:
		_fov = _camera.fov
	match next:
		"fpv":
			_fpv_pos = cam_pos
			_yaw = atan2(forward.x, forward.z)
			_pitch = clampf(asin(clampf(forward.y, -1.0, 1.0)), -1.2, 1.2)
			if absf(cam_pos.y - EYE_Y) > 0.02:
				_fpv_settle_from_y = cam_pos.y
				_fpv_settle_t = FPV_SETTLE_SEC
			else:
				_fpv_settle_t = 0.0
				_fpv_pos.y = EYE_Y
		"fly":
			_fly_pos = cam_pos
			_yaw = atan2(forward.x, forward.z)
			_pitch = clampf(asin(clampf(forward.y, -1.0, 1.0)), -1.45, 1.45)
			_fpv_settle_t = 0.0
			_clamp_fly_pos()
		_:
			# Орбита: camera = target + offset, offset вдоль −forward от взгляда.
			_yaw = atan2(-forward.x, -forward.z)
			_pitch = clampf(asin(clampf(-forward.y, -1.0, 1.0)), -1.55, 1.55)
			_distance = clampf(_distance, 0.018, 8.0)
			_target = cam_pos + forward * _distance
			_fpv_settle_t = 0.0
	cam_mode = next
	_drag = ""
	_move_vel = Vector3.ZERO
	_place_camera()


func _look_dir() -> Vector3:
	return Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)).normalized()


func _look_flat() -> Vector3:
	var v := Vector3(sin(_yaw), 0.0, cos(_yaw))
	if v.length_squared() < 1e-8:
		return Vector3(0, 0, -1)
	return v.normalized()


func _fpv_settle_height(dt: float) -> void:
	if _fpv_settle_t <= 0.0:
		return
	_fpv_settle_t = maxf(_fpv_settle_t - dt, 0.0)
	var u: float = 1.0 - _fpv_settle_t / FPV_SETTLE_SEC
	u = u * u * (3.0 - 2.0 * u) # smoothstep
	_fpv_pos.y = lerpf(_fpv_settle_from_y, EYE_Y, u)


func _fpv_move(dt: float) -> void:
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		wish += _look_flat()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		wish -= _look_flat()
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		wish -= _look_flat().cross(Vector3.UP)
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		wish += _look_flat().cross(Vector3.UP)
	if wish.length_squared() > 1e-8:
		wish = wish.normalized()
	_move_vel = _smooth_move_vel(_move_vel, wish, FPV_SPEED * _cam_mod(), dt)
	if _move_vel.length_squared() < 1.0e-10:
		return
	_fpv_pos += _move_vel * dt
	# Ходьба — сразу на уровень глаз; срыв плавного спуска.
	_fpv_settle_t = 0.0
	_fpv_pos.y = EYE_Y
	_clamp_fpv_pos()


func _clamp_fpv_pos() -> void:
	_fpv_pos.x = clampf(_fpv_pos.x, -6.0, 6.0)
	_fpv_pos.z = clampf(_fpv_pos.z, -6.0, 6.0)


## Пролёт: свободная камера (WASD + Q/E), без привязки к фокусу и без высоты глаз.
func _fly_move(dt: float) -> void:
	var wish := Vector3.ZERO
	var fwd: Vector3 = _look_dir()
	var right: Vector3 = fwd.cross(Vector3.UP)
	if right.length_squared() < 1.0e-8:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		wish += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		wish -= fwd
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		wish -= right
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		wish += right
	if Input.is_key_pressed(KEY_E):
		wish += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		wish -= Vector3.UP
	if wish.length_squared() > 1.0e-8:
		wish = wish.normalized()
	_move_vel = _smooth_move_vel(_move_vel, wish, FLY_SPEED * _cam_mod(), dt)
	if _move_vel.length_squared() < 1.0e-10:
		return
	_fly_pos += _move_vel * dt
	_clamp_fly_pos()


func _smooth_move_vel(vel: Vector3, wish_dir: Vector3, max_speed: float, dt: float) -> Vector3:
	var target: Vector3 = wish_dir * max_speed
	var rate: float = MOVE_ACCEL if wish_dir.length_squared() > 1.0e-8 else MOVE_DECEL
	var t: float = clampf(rate * dt, 0.0, 1.0)
	var next: Vector3 = vel.lerp(target, t)
	if next.length_squared() < 1.0e-8:
		return Vector3.ZERO
	return next


func _clamp_fly_pos() -> void:
	_fly_pos.x = clampf(_fly_pos.x, -6.0, 6.0)
	_fly_pos.y = clampf(_fly_pos.y, 0.08, 5.5)
	_fly_pos.z = clampf(_fly_pos.z, -6.0, 6.0)


func _place_camera() -> void:
	if _camera == null:
		return
	if cam_mode == "fpv":
		_camera.position = _fpv_pos
		var look_at_p: Vector3 = _fpv_pos + _look_dir()
		if absf(look_at_p.y - _fpv_pos.y) < 1e-4 and absf(_look_dir().x) < 1e-4 and absf(_look_dir().z) < 1e-4:
			look_at_p += Vector3(0.001, 0, 0)
		_camera.look_at(look_at_p, Vector3.UP)
	elif cam_mode == "fly":
		_camera.position = _fly_pos
		var look_fly: Vector3 = _fly_pos + _look_dir()
		if absf(look_fly.y - _fly_pos.y) < 1e-4 and absf(_look_dir().x) < 1e-4 and absf(_look_dir().z) < 1e-4:
			look_fly += Vector3(0.001, 0, 0)
		_camera.look_at(look_fly, Vector3.UP)
	else:
		var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
		_camera.position = _target + offset
		_camera.look_at(_target, Vector3.UP)
	_camera.fov = _fov
	_update_floor_opacity()


func apply_ui_theme() -> void:
	if _env == null:
		return
	_env.background_color = UiTheme.workshop_bg()
	_env.ambient_light_color = UiTheme.workshop_ambient()
	_env.ambient_light_energy = 0.55 if UiTheme.dark else 0.85
	if _floor_mat:
		var fc := UiTheme.workshop_floor()
		_floor_mat.albedo_color = Color(fc.r, fc.g, fc.b, _floor_mat.albedo_color.a)
	if _grid_mat:
		# Сетка пересобирается через vertex colors — достаточно смены пола/фона.
		pass
	_update_floor_opacity()


func _update_floor_opacity() -> void:
	## Под полом камера не должна упираться в непрозрачную плиту — пол и сетка гаснут.
	if _camera == null:
		return
	var under: float = clampf((FLOOR_TOP_Y - _camera.position.y) / 0.06, 0.0, 1.0)
	var floor_a: float = 1.0 - under
	var grid_a: float = (0.55 if not UiTheme.dark else 0.55) * (1.0 - under)
	if _floor_mat != null:
		_floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if under > 0.001 else BaseMaterial3D.TRANSPARENCY_DISABLED
		var fc := UiTheme.workshop_floor()
		_floor_mat.albedo_color = Color(fc.r, fc.g, fc.b, floor_a)
		_floor_mat.depth_draw_mode = (
			BaseMaterial3D.DEPTH_DRAW_ALWAYS if under > 0.001 else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		)
	if _floor_mi != null:
		_floor_mi.visible = floor_a > 0.02
	if _grid_mat != null:
		_grid_mat.albedo_color = Color(1, 1, 1, grid_a)
	if _grid_mi != null:
		_grid_mi.visible = under < 0.98


func _add_floor() -> void:
	_floor_mi = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.04, 6.0)
	_floor_mi.mesh = box
	_floor_mi.position = Vector3(0, -0.02, 0)
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = UiTheme.workshop_floor()
	_floor_mat.roughness = 0.9
	_floor_mi.material_override = _floor_mat
	add_child(_floor_mi)
	_grid_mi = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var extent := 2.4
	var step := 0.2
	var x := -extent
	var major_c := Color(0.45, 0.58, 0.72, 0.55) if not UiTheme.dark else Color(0.32, 0.42, 0.58, 0.55)
	var minor_c := Color(0.40, 0.52, 0.64, 0.35) if not UiTheme.dark else Color(0.22, 0.32, 0.44, 0.35)
	while x <= extent + 0.001:
		var major := absf(fmod(x, 1.0)) < 0.001
		im.surface_set_color(major_c if major else minor_c)
		im.surface_add_vertex(Vector3(x, 0.001, -extent))
		im.surface_add_vertex(Vector3(x, 0.001, extent))
		im.surface_add_vertex(Vector3(-extent, 0.001, x))
		im.surface_add_vertex(Vector3(extent, 0.001, x))
		x += step
	im.surface_end()
	_grid_mi.mesh = im
	_grid_mat = StandardMaterial3D.new()
	_grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_mat.vertex_color_use_as_albedo = true
	_grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_mi.material_override = _grid_mat
	add_child(_grid_mi)


func _sync_machines(sim_light: bool = false) -> void:
	var alive := {}
	var frame := Engine.get_process_frames()
	for el in circuit.elements:
		if el.kind == "coil":
			# Катушка не отдельная машина — надевается на трубку ЭМ распреда по метке.
			continue
		if el.kind == "electro":
			# DIN/дверца — в общем щите; катушка ЭМ — на трубке ПР; контакты группы — только 2D.
			continue
		alive[el.id] = true
		var rec = _records.get(el.id, null)
		if not sim_light or rec == null:
			var spool_sig := ",".join(PackedStringArray(el.spool_envelopes)) if el.get("spool_envelopes") != null else ""
			var junc_sig := "%s:%d:v3" % [
				str(el.get("junction_style") if el.get("junction_style") != null else ""),
				int(el.get("junction_ports") if el.get("junction_ports") != null else 0),
			]
			var sig := "%s|%s|%.3f|%.3f|%.3f|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%.2f|%s|%.2f|%.2f|%d|%d|%s|%s|%s|%s|%s|%.2f|%s|%s|%s|%s|%s|%s|%s" % [
				el.kind, el.action, el.bore_mm, el.rod_mm, el.stroke_mm,
				el.body_style, el.rod_mode, el.spring_side, el.rod_end, el.brake, el.port_name,
				el.cush_cap, el.cush_rod, el.piston_kind, el.carriage,
				el.mount, el.guide, el.bump_end, el.seal_leak, el.body_style_user,
				el.cush_open_cap, el.cush_open_rod,
				el.valve_ways, el.valve_positions, el.valve_center, el.op_left, el.op_right,
				el.pilot_supply, el.valve_nc_no, el.valve_cv,
				el.port_3, el.port_5, _coil_sig_for(el),
				"1" if bool(el.get("override_left") if el.get("override_left") != null else true) else "0",
				"1" if bool(el.get("override_right") if el.get("override_right") != null else true) else "0",
				spool_sig, junc_sig,
			]
			var reseat: bool = bool(el.auto_ground)
			if rec != null and rec.has("seat_y") and absf(el.world_pos.y - float(rec["seat_y"])) < 0.004:
				reseat = true
			# Старые сцены сидели у пола — один раз поднять на рабочую плоскость.
			if float(el.world_pos.y) < WORK_Y * 0.55:
				reseat = true
			if rec == null or rec["sig"] != sig:
				if rec != null:
					rec["root"].queue_free()
					rec["shadow"].queue_free()
				var built := Node3D.new()
				_machines.add_child(built)
				var info: Dictionary
				if el.kind == "valve":
					info = IsoValve.build(built, el, circuit)
				elif el.kind == "junction":
					info = IsoJunction.build(built, el)
				else:
					info = Iso.build(built, el)
				built.set_meta("ports", info["ports"])
				built.set_meta("dirs", info["dirs"])
				if xray:
					Iso.apply_xray(built, true)
				var shadow_new := MeshInstance3D.new()
				var sm := CylinderMesh.new()
				sm.top_radius = 0.04
				sm.bottom_radius = 0.04
				sm.height = 0.002
				shadow_new.mesh = sm
				var smat := StandardMaterial3D.new()
				smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				smat.albedo_color = Color(0, 0, 0, 0.22)
				shadow_new.material_override = smat
				_machines.add_child(shadow_new)
				rec = {"root": built, "sig": sig, "shadow": shadow_new}
				_records[el.id] = rec
				if reseat:
					var box: AABB = _model_aabb(built)
					if box.size.length() > 0.0001:
						el.world_pos.y = -box.position.y + WORK_Y
					else:
						el.world_pos.y = WORK_Y
					rec["seat_y"] = el.world_pos.y
					el.auto_ground = false
				var sh_box: AABB = _model_aabb(built)
				var sh_r := clampf(maxf(sh_box.size.x, sh_box.size.z) * 0.45, 0.012, 0.10)
				sm.top_radius = sh_r
				sm.bottom_radius = sh_r
			elif reseat and rec != null:
				var box2: AABB = _model_aabb(rec["root"])
				if box2.size.length() > 0.0001:
					el.world_pos.y = -box2.position.y + WORK_Y
				else:
					el.world_pos.y = WORK_Y
				rec["seat_y"] = el.world_pos.y
				el.auto_ground = false
		if rec == null:
			continue
		var root: Node3D = rec["root"]
		if el.kind == "junction" and not sim_light:
			_orient_junction_3d(el)
		root.position = el.world_pos
		root.basis = el.world_basis
		if not sim_light:
			var tag := root.get_node_or_null("Tag")
			if tag and str(tag.text) != str(el.tag):
				tag.text = el.tag
		if el.kind == "valve":
			var do_viz: bool = xray and (frame % 4) == 0
			IsoValve.update_spool(root, el, do_viz)
			# 2D-нажатие органа ставит command_* — двигаем 3D-кнопки/плунжеры тоже.
			_sync_actuators_from_commands(el, root)
		var rod := root.get_node_or_null("Rod")
		if rod:
			rod.position.x = el.x
		if el.kind == "cylinder" and str(el.get("spring_side") if el.get("spring_side") != null else "none") != "none":
			if (not sim_light) or (frame % 2) == 0:
				Iso.update_spring(root, el)
		if xray and (frame % 4) == 0:
			var spring_n := root.get_node_or_null("Spring")
			if spring_n:
				Iso.apply_xray(spring_n, true)
		var needle := root.get_node_or_null("Needle")
		if needle and el.kind == "source":
			var bar: float = float(el.pressure_bar)
			var link = circuit.wire_on(el.id, "out")
			if link != null and circuit.sim_time > 0.0:
				bar = (link.pressure - ATM) / 1.0e5
			needle.rotation_degrees = Vector3(0, 0, lerpf(50.0, -230.0, clampf(bar / 10.0, 0.0, 1.0)))
		var shadow: MeshInstance3D = rec["shadow"]
		var foot: float
		if str(el.kind) == "source":
			foot = 0.09
		elif str(el.kind) == "junction":
			foot = 0.02
		elif str(el.kind) == "valve":
			foot = 0.045
		else:
			foot = maxf(float(el.bore_mm) * 0.0032, 0.06)
		(shadow.mesh as CylinderMesh).top_radius = foot
		(shadow.mesh as CylinderMesh).bottom_radius = foot
		shadow.position = Vector3(el.world_pos.x, WORK_Y + 0.002, el.world_pos.z)
	var stale: Array = []
	for id in _records.keys():
		if not alive.has(id):
			stale.append(id)
	for id in stale:
		_records[id]["root"].queue_free()
		_records[id]["shadow"].queue_free()
		_records.erase(id)


func _orient_junction_3d(el) -> void:
	# Повернуть тройник в цехе по соседям (ось 1–2 вдоль прохода).
	var rec = _records.get(el.id, null)
	if rec != null and bool(rec.get("user_rotated", false)):
		return
	var p1 = null
	var p2 = null
	var p3 = null
	for port_name in ["1", "2", "3"]:
		var w = circuit.wire_on(el.id, port_name)
		if w == null:
			continue
		var other_id: int = w.b_id if w.a_id == el.id else w.a_id
		var other = circuit.get_element(other_id)
		if other == null:
			continue
		var pos: Vector3 = other.world_pos
		match port_name:
			"1":
				p1 = pos
			"2":
				p2 = pos
			"3":
				p3 = pos
	if p1 == null or p2 == null:
		var yaw := float(el.rotation_quad) * PI * 0.5
		el.world_basis = Basis(Vector3.UP, -yaw)
		return
	var axis: Vector3 = p2 - p1
	axis.y = 0.0
	if axis.length_squared() < 1.0e-6:
		return
	axis = axis.normalized()
	var z_axis := axis.cross(Vector3.UP)
	if z_axis.length_squared() < 1.0e-8:
		return
	z_axis = z_axis.normalized()
	el.world_basis = Basis(axis, Vector3.UP, z_axis)
	if p3 != null:
		var branch: Vector3 = p3 - el.world_pos
		branch.y = 0.0
		# Порт 3 модели — +Y (вверх); для напольной разводки ветка обычно в сторону — поднимем корпус не трогаем.
		# Если оба соседа 1/2 на полу, ось уже вдоль прохода.
		pass
	if rec != null:
		rec["junc_auto"] = true


func _coil_sig_for(el) -> String:
	if el.kind != "valve" or circuit == null:
		return ""
	var parts: PackedStringArray = []
	for other in circuit.elements:
		var k := str(other.kind)
		if k == "coil" or (k == "electro" and str(other.electro_class) == "solenoid_coil"):
			parts.append(str(other.tag))
	parts.sort()
	return ",".join(parts)


func _electro_hose_source(ea, a_port: String, eb, b_port: String) -> Array:
	# Цвет берём у источника (кабель/ввод/шина), не у прибора на другом конце.
	var pairs: Array = [[ea, a_port], [eb, b_port]]
	for pair in pairs:
		var el = pair[0]
		if el != null and str(el.electro_class) == "supply":
			return [el, str(pair[1])]
	for pair2 in pairs:
		var el2 = pair2[0]
		if el2 != null and str(el2.electro_class) == "busbar":
			return [el2, str(pair2[1])]
	for pair3 in pairs:
		if pair3[0] != null:
			return [pair3[0], str(pair3[1])]
	return [null, ""]


func _electro_port_gost_color(port_name: String) -> Color:
	match str(port_name):
		"L", "L1", "+24", "+":
			return Color(0.45, 0.28, 0.12)
		"L2":
			return Color(0.08, 0.08, 0.1)
		"L3", "0", "-":
			return Color(0.55, 0.56, 0.58)
		"N":
			return Color(0.15, 0.35, 0.85)
		"PE":
			return Color(0.55, 0.75, 0.15)
		_:
			return Color(0.12, 0.12, 0.14)


func _electro_hose_color(ea, a_port: String, eb, b_port: String) -> Color:
	var src: Array = _electro_hose_source(ea, a_port, eb, b_port)
	return _electro_port_gost_color(str(src[1]))


func _electro_hose_is_pe(ea, a_port: String, eb, b_port: String) -> bool:
	# Полосатый PE только если источник — жила PE, а не клемма PE прибора.
	var src: Array = _electro_hose_source(ea, a_port, eb, b_port)
	return str(src[1]) == "PE"


func _pe_hose_material(mat: StandardMaterial3D) -> void:
	# Жёлто-зелёная продольная полоса (ГОСТ PE), не solid.
	if mat.get_meta("pe_striped", false):
		return
	var img := Image.create(8, 2, false, Image.FORMAT_RGBA8)
	for x in 8:
		var c: Color = Color(0.88, 0.78, 0.12) if x < 4 else Color(0.18, 0.62, 0.16)
		for y in 2:
			img.set_pixel(x, y, c)
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(2.0, 3.0, 1.0)
	mat.albedo_color = Color(1, 1, 1)
	mat.set_meta("pe_striped", true)


func _clear_pe_hose_material(mat: StandardMaterial3D) -> void:
	if not mat.get_meta("pe_striped", false):
		return
	mat.albedo_texture = null
	mat.uv1_scale = Vector3(1, 1, 1)
	mat.set_meta("pe_striped", false)


func _sync_hoses() -> void:
	# ArrayMesh-трубки/провода: без CSG — основной источник тормозов на многих элементах.
	var alive := {}
	const CURVE_PTS := 12
	var drag_lite: bool = _drag in ["din_module", "door_module"]
	var drag_el: int = _actuate_el_id if drag_lite else -1
	# Во время drag — только провода к модулю; полный HQ после отпускания.
	var want_hq: bool = (not drag_lite) or _hose_hq_pending
	if want_hq and not drag_lite:
		_hose_hq_pending = false
	# Кэш КК один раз на кадр (не на каждый провод).
	_hose_ducts_cached()
	_elec_rebuild_separation()
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		var elec_a: bool = ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric"
		var elec_b: bool = eb != null and Geom.port_domain(eb, str(wire.b_port)) == "electric"
		var is_elec: bool = elec_a or elec_b
		alive[wire.id] = true
		var node: Node3D = _hose_nodes.get(wire.id, null)
		if node == null:
			node = _make_hose_node()
			_hoses.add_child(node)
			_hose_nodes[wire.id] = node
		# Drag: чужие провода не трогаем (порты не двигались).
		if drag_lite and drag_el >= 0 and not _wire_touches_drag_el(wire, drag_el):
			continue
		var a = _port_world(wire.a_id, wire.a_port)
		var b = _port_world(wire.b_id, wire.b_port)
		if a == null or b == null:
			node.visible = false
			continue
		node.visible = true
		var da := _port_dir_world(wire.a_id, wire.a_port)
		var db := _port_dir_world(wire.b_id, wire.b_port)
		var mat: StandardMaterial3D = node.get_meta("mat")
		var radius: float
		var pe: bool = false
		var color_id: String = str(wire.color_id)
		if is_elec:
			pe = color_id == "pe" or (color_id == "" and _electro_hose_is_pe(ea, str(wire.a_port), eb, str(wire.b_port)))
			if pe:
				_pe_hose_material(mat)
			else:
				_clear_pe_hose_material(mat)
				if color_id != "":
					mat.albedo_color = Circuit.line_color_from_id(color_id)
				else:
					mat.albedo_color = _electro_hose_color(ea, str(wire.a_port), eb, str(wire.b_port))
			# Сечение мм² → наружный Ø ПВХ (примерно): OD≈1.6·√S + 1.25 мм.
			var a_mm2: float = maxf(float(wire.id_mm), 0.25)
			var od_mm: float = 1.6 * sqrt(a_mm2) + 1.25
			radius = clampf(od_mm * 0.0005, 0.0009, 0.0045)
			# Чуть внутрь зева (не к винту): порты уже на кромке отверстия.
			var inset: float = 0.0009
			a = a - da.normalized() * inset
			b = b - db.normalized() * inset
		else:
			_clear_pe_hose_material(mat)
			if color_id != "":
				mat.albedo_color = Circuit.line_color_from_id(color_id)
			else:
				var gauge: float = clampf((float(wire.pressure) - ATM) / 6.0e5, 0.0, 1.0)
				mat.albedo_color = UiTheme.BRAND_BLUE.lerp(UiTheme.ACCENT_CYAN, gauge * 0.55)
			radius = clampf(float(wire.id_mm) * 0.00055, 0.0016, 0.0045)
		var lane: int = _elec_wire_lane(wire) if is_elec else 0
		var qtag: String = "L" if drag_lite else "H"
		var sig := "%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.5f|%d|%d|%s|route14|%d|%s" % [
			a.x, a.y, a.z, b.x, b.y, b.z, da.x, da.y, da.z, db.x, db.y, db.z, radius, 1 if is_elec else 0, 1 if pe else 0, color_id, lane, qtag,
		]
		if str(node.get_meta("geom_sig", "")) != sig:
			var pts: PackedVector3Array
			if is_elec:
				pts = _hose_ortho_elec(a, da, b, db, wire, lane)
				# Сначала убрать микро-изломы (они дают «кручения» после fillet).
				pts = _hose_simplify_path(pts, maxf(radius * 2.0, 0.0012))
				# Радиус гиба ~3…4×OD (не фиксированные 7 мм на тонком проводе).
				var bend: float = clampf(radius * 6.0, 0.0025, 0.010)
				if drag_lite:
					pts = _fillet_polyline(pts, bend, 3)
				else:
					pts = _fillet_polyline(pts, bend, 6)
					pts = _hose_simplify_path(pts, maxf(radius * 0.4, 0.00025))
			else:
				pts = _hose_curve(a, da, b, db, CURVE_PTS)
				pts = _fillet_polyline(pts, maxf(radius * 3.5, 0.006), 4 if drag_lite else 6)
				if not drag_lite:
					pts = _hose_simplify_path(pts, maxf(radius * 0.35, 0.00025))
			_apply_hose_path(node, pts, radius)
			node.set_meta("geom_sig", sig)
			node.set_meta("curve_pts", pts)
		node.set_meta("a", a)
		node.set_meta("b", b)
	if not drag_lite:
		var stale: Array = []
		for id in _hose_nodes.keys():
			if not alive.has(id):
				stale.append(id)
		for id in stale:
			_hose_nodes[id].queue_free()
			_hose_nodes.erase(id)


func _hose_ducts_cached() -> Dictionary:
	var fr: int = Engine.get_process_frames()
	if fr == _hose_ducts_frame:
		return _hose_ducts_cache
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	_hose_ducts_cache = IsoCabinet.cable_ducts_world(cab)
	_hose_ducts_frame = fr
	return _hose_ducts_cache


## Уникальная дорожка среди всех электропроводов (не hash — иначе коллизии).
func _elec_wire_lane(wire) -> int:
	if wire == null:
		return 0
	return int(_elec_lane_by_wire.get(int(wire.id), 0))


## Раз в кадр: lane по wire.id + боковой сдвиг выхода с одной грани модуля.
func _elec_rebuild_separation() -> void:
	_elec_lane_by_wire.clear()
	_elec_exit_off.clear()
	if circuit == null:
		return
	var elec_ids: Array = []
	# Группы выходов: primary_el + сторона нормали → порты с проводами.
	var face_groups: Dictionary = {} # key -> Array[{sort, el, port, n}]
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		if ea == null or eb == null:
			continue
		var elec_a: bool = Geom.port_domain(ea, str(wire.a_port)) == "electric"
		var elec_b: bool = Geom.port_domain(eb, str(wire.b_port)) == "electric"
		if not (elec_a or elec_b):
			continue
		elec_ids.append(int(wire.id))
		_elec_collect_face_end(face_groups, int(wire.a_id), str(wire.a_port))
		_elec_collect_face_end(face_groups, int(wire.b_id), str(wire.b_port))
	elec_ids.sort()
	var n_w: int = elec_ids.size()
	for i in n_w:
		# Плотный индекс 0…N−1 → уникальная ячейка в _elec_pack_lane.
		_elec_lane_by_wire[int(elec_ids[i])] = i
	# На одной грани — развести пеньки шире диаметра (шаг клемм часто меньше ⌀ провода).
	for key in face_groups.keys():
		var arr: Array = face_groups[key]
		if arr.size() < 2:
			continue
		arr.sort_custom(func(p, q): return float(p["sort"]) < float(q["sort"]))
		var pitch: float = ELEC_LANE_PITCH
		var mid: float = float(arr.size() - 1) * 0.5
		for i in arr.size():
			var rec: Dictionary = arr[i]
			var nrm: Vector3 = rec["n"] as Vector3
			var lat: Vector3 = _elec_face_lateral(nrm)
			var off: Vector3 = lat * ((float(i) - mid) * pitch)
			var ek: String = "%d|%s" % [int(rec["el"]), str(rec["port"])]
			_elec_exit_off[ek] = off


func _elec_collect_face_end(face_groups: Dictionary, el_id: int, port: String) -> void:
	var pos = _port_world(el_id, port)
	var dir: Vector3 = _port_dir_world(el_id, port)
	if pos == null or dir.length_squared() < 1.0e-10:
		return
	var n: Vector3 = dir.normalized()
	var pid: int = _elec_primary_el_id(el_id)
	var face: int = 0
	if n.y > 0.35:
		face = 1
	elif n.y < -0.35:
		face = 2
	elif n.z > 0.35:
		face = 3
	elif n.z < -0.35:
		face = 4
	else:
		face = 5 if n.x >= 0.0 else 6
	var key: String = "%d:%d" % [pid, face]
	if not face_groups.has(key):
		face_groups[key] = []
	var sort_v: float = float(pos.x)
	if face == 3 or face == 4:
		sort_v = float(pos.y)
	elif face >= 5:
		sort_v = float(pos.y)
	# Без дублей одного порта.
	for prev in face_groups[key]:
		if int(prev["el"]) == el_id and str(prev["port"]) == port:
			return
	face_groups[key].append({"el": el_id, "port": port, "n": n, "sort": sort_v})


func _elec_face_lateral(n: Vector3) -> Vector3:
	## Ось разведения на грани (перпендикуляр выходу клеммы).
	var lat: Vector3
	if absf(n.y) > 0.35:
		lat = Vector3.RIGHT # верх/низ → вдоль ряда клемм (X щита)
	else:
		lat = Vector3.UP.cross(n)
		if lat.length_squared() < 1.0e-8:
			lat = Vector3.RIGHT.cross(n)
	if lat.length_squared() < 1.0e-8:
		return Vector3.RIGHT
	return lat.normalized()


func _elec_exit_offset_for(el_id: int, port: String) -> Vector3:
	var ek: String = "%d|%s" % [el_id, port]
	if _elec_exit_off.has(ek):
		return _elec_exit_off[ek] as Vector3
	return Vector3.ZERO


## Уникальный индекс 0…N−1 → сетка в сечении КК (без пересечений).
func _elec_pack_lane(idx: int) -> Vector2:
	var cols: int = 5
	var i: int = maxi(idx, 0)
	var col: int = i % cols
	var row: int = int(i / cols)
	var col_c: float = float(col) - float(cols - 1) * 0.5
	return Vector2(col_c * ELEC_LANE_PITCH, float(row) * (ELEC_LANE_PITCH * 0.7))


func _wire_touches_drag_el(wire, el_id: int) -> bool:
	if wire == null or el_id < 0 or circuit == null:
		return false
	var pa: int = _elec_primary_el_id(int(wire.a_id))
	var pb: int = _elec_primary_el_id(int(wire.b_id))
	return pa == el_id or pb == el_id or int(wire.a_id) == el_id or int(wire.b_id) == el_id


func _make_hose_node() -> Node3D:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Tube"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiTheme.BRAND_BLUE.lightened(0.08)
	mat.roughness = 0.48
	mat.metallic = 0.02
	mi.material_override = mat
	node.add_child(mi)
	node.set_meta("mat", mat)
	return node


func _apply_hose_path(node: Node3D, pts: PackedVector3Array, radius: float) -> void:
	var mi: MeshInstance3D = node.get_node("Tube")
	mi.mesh = _build_tube_mesh(pts, radius, 10)
	node.set_meta("curve_pts", pts)
	node.set_meta("tube_radius", radius)


## Скругление углов полилинии: дуга постоянного радиуса вместо острого 90° (без заужения трубы).
func _fillet_polyline(pts: PackedVector3Array, bend_r: float, segs: int = 6) -> PackedVector3Array:
	if pts.size() < 3 or bend_r < 1.0e-5:
		return pts
	var out := PackedVector3Array()
	out.append(pts[0])
	var nseg: int = maxi(segs, 3)
	for i in range(1, pts.size() - 1):
		var prev: Vector3 = pts[i - 1]
		var cur: Vector3 = pts[i]
		var next: Vector3 = pts[i + 1]
		var d0: Vector3 = cur - prev
		var d1: Vector3 = next - cur
		var l0: float = d0.length()
		var l1: float = d1.length()
		if l0 < 1.0e-5 or l1 < 1.0e-5:
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		var u0: Vector3 = d0 / l0
		var u1: Vector3 = d1 / l1
		var defl: float = (-u0).angle_to(u1)
		if defl < deg_to_rad(18.0) or defl > deg_to_rad(170.0):
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		var trim: float = bend_r * tan(defl * 0.5)
		trim = minf(trim, minf(l0 * 0.48, l1 * 0.48))
		if trim < 1.0e-5:
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		var p_enter: Vector3 = cur - u0 * trim
		var p_exit: Vector3 = cur + u1 * trim
		var axis: Vector3 = u0.cross(u1)
		if axis.length_squared() < 1.0e-12:
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		axis = axis.normalized()
		var n_in: Vector3 = axis.cross(u0).normalized()
		if n_in.dot(u1) < 0.0:
			n_in = -n_in
		var r_use: float = trim / maxf(tan(defl * 0.5), 1.0e-5)
		var center: Vector3 = p_enter + n_in * r_use
		if out[out.size() - 1].distance_squared_to(p_enter) > 1.0e-10:
			out.append(p_enter)
		var a0: Vector3 = p_enter - center
		var a1: Vector3 = p_exit - center
		for k in range(1, nseg):
			var t: float = float(k) / float(nseg)
			var dir: Vector3 = a0.slerp(a1, t)
			if dir.length_squared() < 1.0e-12:
				continue
			out.append(center + dir.normalized() * r_use)
		out.append(p_exit)
	out.append(pts[pts.size() - 1])
	return out


## Убрать микро-сегменты и почти коллинеарные точки (ломают кадр трубки).
func _hose_simplify_path(pts: PackedVector3Array, min_seg: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var raw := PackedVector3Array()
	raw.append(pts[0])
	for i in range(1, pts.size()):
		if raw[raw.size() - 1].distance_to(pts[i]) >= min_seg:
			raw.append(pts[i])
	if raw[raw.size() - 1].distance_squared_to(pts[pts.size() - 1]) > 1.0e-12:
		raw.append(pts[pts.size() - 1])
	if raw.size() < 3:
		return raw
	var out := PackedVector3Array()
	out.append(raw[0])
	for i in range(1, raw.size() - 1):
		var a: Vector3 = out[out.size() - 1]
		var b: Vector3 = raw[i]
		var c: Vector3 = raw[i + 1]
		var d0: Vector3 = b - a
		var d1: Vector3 = c - b
		var l0: float = d0.length()
		var l1: float = d1.length()
		if l0 < 1.0e-8 or l1 < 1.0e-8:
			continue
		# Почти прямая — точку можно выкинуть.
		if (d0 / l0).dot(d1 / l1) > 0.998:
			continue
		out.append(b)
	out.append(raw[raw.size() - 1])
	return out if out.size() >= 2 else raw


func _build_tube_mesh(pts: PackedVector3Array, radius: float, sides: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if pts.size() < 2:
		return mesh
	var path: PackedVector3Array = pts
	var n_pts: int = path.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Касательные по исходящему сегменту (стабильнее центральной разности на изломах).
	var tangents: Array = []
	for i in n_pts:
		var t: Vector3
		if i < n_pts - 1:
			t = path[i + 1] - path[i]
		else:
			t = path[i] - path[i - 1]
		if t.length_squared() < 1.0e-14:
			t = tangents[i - 1] if i > 0 else Vector3.FORWARD
		else:
			t = t.normalized()
		tangents.append(t)
	var t0: Vector3 = tangents[0]
	var ref: Vector3 = Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal: Vector3 = t0.cross(ref)
	if normal.length_squared() < 1.0e-12:
		normal = t0.cross(Vector3.FORWARD)
	normal = normal.normalized()
	var binorm: Vector3 = t0.cross(normal).normalized()
	normal = binorm.cross(t0).normalized()
	var side_n: int = maxi(sides, 5)
	for i in n_pts:
		var ti: Vector3 = tangents[i]
		if i > 0:
			var tprev: Vector3 = tangents[i - 1]
			var dot: float = clampf(tprev.dot(ti), -1.0, 1.0)
			if dot < -0.9995:
				# Разворот ~180°: отражаем нормаль, без нестабильной оси.
				var axis_f: Vector3 = normal
				if absf(tprev.dot(axis_f)) > 0.9:
					axis_f = binorm
				normal = Basis(axis_f.normalized(), PI) * normal
			elif dot < 0.9995:
				var axis: Vector3 = tprev.cross(ti)
				if axis.length_squared() > 1.0e-12:
					normal = Basis(axis.normalized(), acos(dot)) * normal
			# Ортонормаль к новой касательной (rotation minimizing).
			normal = (normal - ti * normal.dot(ti))
			if normal.length_squared() < 1.0e-12:
				var r2: Vector3 = Vector3.UP if absf(ti.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
				normal = ti.cross(r2).normalized()
			else:
				normal = normal.normalized()
			binorm = ti.cross(normal).normalized()
			normal = binorm.cross(ti).normalized()
		var v_base: int = verts.size()
		var u: float = float(i) / float(maxi(n_pts - 1, 1))
		for s in side_n:
			var ang: float = TAU * float(s) / float(side_n)
			var dir: Vector3 = (normal * cos(ang) + binorm * sin(ang)).normalized()
			verts.append(path[i] + dir * radius)
			norms.append(dir)
			uvs.append(Vector2(float(s) / float(side_n), u))
		if i > 0:
			var prev: int = v_base - side_n
			for s in side_n:
				var s1: int = (s + 1) % side_n
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
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sync_flows() -> void:
	var cursor := 0
	if circuit.running or circuit.sim_time > 0.0:
		for wire in circuit.wires:
			if absf(wire.flow_m3s) < 2.0e-5 or cursor >= _flow_pool.size() - 4:
				continue
			var node: Node3D = _hose_nodes.get(wire.id, null)
			if node == null or not node.visible:
				continue
			var curve: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array())
			if curve.size() < 2:
				continue
			var qabs := absf(wire.flow_m3s)
			if qabs < 4.0e-5:
				continue
			# Скорость шариков ∝ |расход|; без нижней «полки», иначе бегут при нуле.
			var speed := clampf(qabs * 55.0, 0.05, 2.2) * signf(wire.flow_m3s)
			var n_puffs := 2 if qabs < 1.5e-4 else (3 if qabs < 4.0e-4 else 4)
			for k in n_puffs:
				var t := fposmod(circuit.sim_time * speed + float(k) / float(n_puffs), 1.0)
				var idx := t * float(curve.size() - 1)
				var i0 := clampi(int(floor(idx)), 0, curve.size() - 1)
				var i1 := clampi(i0 + 1, 0, curve.size() - 1)
				_place_puff(cursor, curve[i0].lerp(curve[i1], idx - float(i0)), Color(0.62, 0.9, 1.0, 0.9))
				cursor += 1
		for el in circuit.elements:
			if el.kind == "cylinder":
				var root = _records.get(el.id, {}).get("root", null)
				if root == null:
					continue
				var dirs: Dictionary = root.get_meta("dirs")
				for port_name in ["cap", "rod"]:
					if circuit.wire_on(el.id, port_name) != null or cursor >= _flow_pool.size():
						continue
					var q: float = el.q_cap if port_name == "cap" else el.q_rod
					if absf(q) < 2.0e-5:
						continue
					var pos = _port_world(el.id, port_name)
					if pos == null or not dirs.has(port_name):
						continue
					var outward: Vector3 = root.global_transform.basis * dirs[port_name]
					var leaving := q < 0.0
					var t := fposmod(circuit.sim_time * (0.8 if leaving else -0.8), 1.0)
					var color := Color(0.95, 0.55, 0.25, 0.75) if leaving else Color(0.62, 0.9, 1.0, 0.75)
					_place_puff(cursor, pos + outward * (0.02 + t * 0.06), color)
					cursor += 1
			elif el.kind == "valve" and xray:
				cursor = _puff_valve_flows(el, cursor)
	for i in range(cursor, _flow_pool.size()):
		_flow_pool[i].visible = false


func _puff_valve_flows(el, cursor: int) -> int:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	var dirs: Dictionary = root.get_meta("dirs") if root.has_meta("dirs") else {}
	var ports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	# Выхлоп в атмосферу — тёплые частицы из глушителя/порта 3/5.
	for name in ValveCat.port_names(el):
		if cursor >= _flow_pool.size():
			break
		if not ValveCat.is_exhaust_port(name):
			continue
		var q := float(el.port_q.get(name, 0.0)) if el.get("port_q") != null else 0.0
		if q > -2.0e-5:
			continue
		if not ports.has(name):
			continue
		var pos: Vector3 = root.global_transform * ports[name]
		var outward := Vector3.DOWN
		if dirs.has(name):
			outward = root.global_transform.basis * dirs[name]
		var t := fposmod(circuit.sim_time * 1.1, 1.0)
		_place_puff(cursor, pos + outward * (0.01 + t * 0.07), Color(1.0, 0.5, 0.15, 0.85))
		cursor += 1
	# Внутренние мостики — направление по расходу (port_q < 0 = уходит из объёма порта).
	var pairs: Array = ValveLib.path_pairs_from_spool(el, int(el.valve_pos))
	for pair in pairs:
		if cursor >= _flow_pool.size() - 1:
			break
		if not (pair is Array) or pair.size() < 2:
			continue
		var a := str(pair[0])
		var b := str(pair[1])
		if not ports.has(a) or not ports.has(b):
			continue
		var pa: Vector3 = root.global_transform * ports[a]
		var pb: Vector3 = root.global_transform * ports[b]
		var mid := (pa + pb) * 0.5
		mid.y = root.global_position.y
		var qa := float(el.port_q.get(a, 0.0)) if el.get("port_q") != null else 0.0
		var qb := float(el.port_q.get(b, 0.0)) if el.get("port_q") != null else 0.0
		var pa_p := float(el.port_press.get(a, ATM))
		var pb_p := float(el.port_press.get(b, ATM))
		var a_exh := ValveCat.is_exhaust_port(a)
		var b_exh := ValveCat.is_exhaust_port(b)
		var qmag := maxf(absf(qa), absf(qb))
		# Устаканилось — не гоняем шарики туда-сюда.
		if qmag < 4.0e-5 and absf(pa_p - pb_p) < 2.5e4:
			continue
		var from_a: bool
		if b_exh and not a_exh:
			from_a = true # рабочий → выхлоп
		elif a_exh and not b_exh:
			from_a = false
		else:
			from_a = pa_p >= pb_p + 500.0
			if absf(pa_p - pb_p) < 2000.0:
				from_a = qa < qb
		var col := Color(1.0, 0.55, 0.2, 0.9) if (a_exh or b_exh) else Color(0.45, 0.9, 1.0, 0.9)
		var speed := clampf(qmag * 40.0 + absf(pa_p - pb_p) * 2.0e-7, 0.08, 1.8)
		var t := fposmod(circuit.sim_time * speed, 1.0)
		var p := pa.lerp(pb, t) if from_a else pb.lerp(pa, t)
		p = p.lerp(mid, 0.35)
		_place_puff(cursor, p, col)
		cursor += 1
	return cursor


func _place_puff(index: int, at: Vector3, color: Color) -> void:
	var dot: MeshInstance3D = _flow_pool[index]
	dot.visible = true
	dot.position = at
	(dot.material_override as StandardMaterial3D).albedo_color = color


func _port_world(el_id: int, port: String):
	var rec = _records.get(el_id, null)
	if rec != null:
		var ports: Dictionary = rec["root"].get_meta("ports")
		if ports.has(port):
			return rec["root"].global_transform * ports[port]
	var root := _electro_port_root(el_id)
	if root == null:
		return null
	var eports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	var key := _electro_port_key(el_id, port, eports)
	if key == "" or not eports.has(key):
		return null
	return root.global_transform * eports[key]


func _port_dir_world(el_id: int, port: String) -> Vector3:
	var rec = _records.get(el_id, null)
	if rec != null:
		var root_p: Node3D = rec["root"]
		var dirs_p: Dictionary = root_p.get_meta("dirs") if root_p.has_meta("dirs") else {}
		if dirs_p.has(port):
			var d0: Vector3 = root_p.global_transform.basis * dirs_p[port]
			if d0.length_squared() > 1.0e-8:
				return d0.normalized()
		return Vector3.UP
	var root := _electro_port_root(el_id)
	if root == null:
		return Vector3(0, 0, -1)
	var dirs: Dictionary = root.get_meta("dirs") if root.has_meta("dirs") else {}
	var eports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	var key := _electro_port_key(el_id, port, eports)
	if key != "" and dirs.has(key):
		var d: Vector3 = root.global_transform.basis * dirs[key]
		if d.length_squared() > 1.0e-8:
			return d.normalized()
	return root.global_transform.basis.z.normalized() * -1.0


func _electro_port_root(el_id: int) -> Node3D:
	if circuit == null or _machines == null:
		return null
	var el = circuit.get_element(el_id)
	if el == null or str(el.kind) != "electro":
		return null
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
	if cab == null:
		return null
	var mid: int = int(el.id)
	# Контакты группы — клеммы на 3D primary (кнопка/реле на DIN/дверце).
	if str(el.member_role) == "contact" and int(el.group_id) > 0:
		mid = int(el.group_id)
	return IsoCabinet.module_node(cab, mid)


func _electro_port_key(el_id: int, port: String, ports: Dictionary) -> String:
	if ports.has(port):
		return port
	var el = circuit.get_element(el_id) if circuit != null else null
	if el == null:
		return ""
	# Члены-контакты: пара C{i}A / C{i}B на primary.
	if str(el.member_role) == "contact":
		var idx: int = maxi(int(el.member_index), 1)
		var defs: Array = el.contact_defs if typeof(el.contact_defs) == TYPE_ARRAY else []
		var names: Array = []
		for d in defs:
			if typeof(d) == TYPE_DICTIONARY:
				names.append(str(d.get("name", "")))
		if names.size() >= 2:
			if port == str(names[0]) and ports.has("C%dA" % idx):
				return "C%dA" % idx
			if port == str(names[1]) and ports.has("C%dB" % idx):
				return "C%dB" % idx
		if ports.has("C%dA" % idx) and (port.ends_with("1") or port.ends_with("3") or port.ends_with("5") or port.ends_with("7") or port.ends_with("9")):
			return "C%dA" % idx
		if ports.has("C%dB" % idx):
			return "C%dB" % idx
	# Контакты реле на корпусе primary: T1.. 
	if str(el.member_role) == "contact" and ports.has("T1"):
		var mi: int = maxi(int(el.member_index), 1)
		var tkey := "T%d" % mi
		if ports.has(tkey):
			return tkey
	return ""


func _hose_curve(a: Vector3, da: Vector3, b: Vector3, db: Vector3, n: int) -> PackedVector3Array:
	# Прямой выход из цанги, затем Безье между «пеньками» — без перелома у фитинга.
	var na := da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var nb := db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
	var span := maxf(a.distance_to(b), 0.001)
	var stub := clampf(span * 0.14, 0.010, 0.036)
	var a1 := a + na * stub
	var b1 := b + nb * stub
	var mid_span := maxf(a1.distance_to(b1), 0.001)
	var tan_len := clampf(mid_span * 0.38, stub * 0.9, 0.09)
	# Не даём ручкам утащить кривую назад в фитинг.
	var c1 := a1 + na * tan_len
	var c2 := b1 + nb * tan_len
	var out := PackedVector3Array()
	var steps := maxi(n - 1, 1)
	for i in n:
		var t := float(i) / float(steps)
		var p: Vector3
		if t <= 0.0:
			p = a
		elif t >= 1.0:
			p = b
		else:
			# Переход a→a1→кривая→b1→b: края — линейные пеньки из цанги.
			var edge := clampf(stub / maxf(span * 0.5, stub * 2.0), 0.08, 0.22)
			var mid_w := 1.0 - 2.0 * edge
			if mid_w < 0.2:
				edge = 0.1
				mid_w = 0.8
			if t < edge:
				p = a.lerp(a1, t / edge)
			elif t > 1.0 - edge:
				p = b1.lerp(b, (t - (1.0 - edge)) / edge)
			else:
				var s := (t - edge) / mid_w
				var u := 1.0 - s
				p = u * u * u * a1 + 3.0 * u * u * s * c1 + 3.0 * u * s * s * c2 + s * s * s * b1
		out.append(p)
	return out


## Ортогональная укладка электропроводов.
## Длинные: вне корпуса → в КК → ближайший торец → вертикаль КК → к B → к клемме.
## Короткие: одна сторона / соседние / вертикальная «рот-в-рот» между рейками.
func _hose_ortho_elec(a: Vector3, da: Vector3, b: Vector3, db: Vector3, wire = null, lane: int = 0) -> PackedVector3Array:
	var na := da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var nb := db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
	var stub: float = 0.007
	var a1: Vector3 = a + na * stub
	var b1: Vector3 = b + nb * stub
	var ida: int = _elec_primary_el_id(int(wire.a_id)) if wire != null else -1
	var idb: int = _elec_primary_el_id(int(wire.b_id)) if wire != null else -1
	# Сдвиг ряда — только после пенька (у клеммы строго по нормали, иначе «излом» из зева).
	var off_a: Vector3 = _elec_exit_offset_for(int(wire.a_id), str(wire.a_port)) if wire != null else Vector3.ZERO
	var off_b: Vector3 = _elec_exit_offset_for(int(wire.b_id), str(wire.b_port)) if wire != null else Vector3.ZERO
	if _elec_wire_is_jumper(wire, a1, na, b1, nb):
		return _hose_ortho_elec_jumper(a, a1, b, b1, na, nb, ida, idb, lane, off_a, off_b)
	return _hose_ortho_elec_duct(a, a1, na, b, b1, nb, ida, idb, lane, off_a, off_b)


## Длинный маршрут через перфорированные кабель-каналы.
func _hose_ortho_elec_duct(a: Vector3, a1: Vector3, na: Vector3, b: Vector3, b1: Vector3, nb: Vector3, ida: int, idb: int, lane: int = 0, off_a: Vector3 = Vector3.ZERO, off_b: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var ducts: Dictionary = _hose_ducts_cached()
	var hs: Array = ducts.get("h", [])
	var vs: Array = ducts.get("v", [])
	# Выход вниз/вверх: не выносить на «лицо» модуля — иначе петля вперёд и назад в КК.
	# Разведение ряда — на clear (после пенька по нормали).
	var clear_a: Vector3 = _elec_clear_for_duct(a1, na, ida) + off_a
	var clear_b: Vector3 = _elec_clear_for_duct(b1, nb, idb) + off_b
	var pack: Vector2 = _elec_pack_lane(lane)
	var o_lat: float = pack.x
	var o_dep: float = pack.y
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	if hs.is_empty() or vs.is_empty():
		var duct_z: float = _elec_duct_z(clear_a, clear_b) + o_dep
		var side_x: float = _elec_nearest_side_x(clear_a, clear_b) + o_lat
		var yb: float = _elec_duct_y(clear_b, nb) + o_lat
		_elec_push_into_hduct(pts, clear_a, duct_z, clear_a.y)
		_hose_ortho_push(pts, Vector3(side_x, clear_a.y, duct_z))
		_hose_ortho_push(pts, Vector3(side_x, yb, duct_z))
		_elec_push_out_of_hduct(pts, clear_b, duct_z, yb)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	var ha: Dictionary = _elec_pick_h_duct(hs, clear_a, na)
	var hb: Dictionary = _elec_pick_h_duct(hs, clear_b, nb)
	var za: float = float(ha.get("z", clear_a.z - 0.04)) + o_dep
	var zb: float = float(hb.get("z", clear_b.z - 0.04)) + o_dep
	var ya: float = float(ha.get("y", clear_a.y)) + o_lat
	var yb2: float = float(hb.get("y", clear_b.y)) + o_lat
	# Вход: сначала под модуль (Y), затем вглубь КК (Z), затем на ось канала — без выноса вперёд.
	_elec_push_into_hduct(pts, clear_a, za, ya)
	if absf(ya - yb2) < 0.010 and absf(za - zb) < 0.008:
		# Один гориз. КК — вдоль него.
		_hose_ortho_push(pts, Vector3(clear_b.x, ya, za))
		_elec_push_out_of_hduct(pts, clear_b, za, ya)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	# Разные КК: вертикаль только в боковом КК.
	var mid_x: float = (clear_a.x + clear_b.x) * 0.5
	var route_x: float = _elec_nearest_v_duct_x(vs, mid_x) + o_lat
	_hose_ortho_push(pts, Vector3(route_x, ya, za))
	_hose_ortho_push(pts, Vector3(route_x, yb2, zb))
	_hose_ortho_push(pts, Vector3(clear_b.x, yb2, zb))
	_elec_push_out_of_hduct(pts, clear_b, zb, yb2)
	_hose_ortho_push(pts, b1)
	_hose_ortho_push(pts, b)
	return pts


## Спуск/подъём к КК: clear → (x, clear.y, z_duct) → (x, y_duct, z_duct). Без петли «вперёд».
func _elec_push_into_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, y_duct: float) -> void:
	_hose_ortho_push(pts, clear)
	# В глубину канала на высоте уже вне корпуса, затем на ось Y.
	_hose_ortho_push(pts, Vector3(clear.x, clear.y, z_duct))
	_hose_ortho_push(pts, Vector3(clear.x, y_duct, z_duct))


## Выход из КК к clear у клеммы B (зеркало входа).
func _elec_push_out_of_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, _y_duct: float) -> void:
	_hose_ortho_push(pts, Vector3(clear.x, clear.y, z_duct))
	_hose_ortho_push(pts, clear)


## Clear для укладки в КК: уводим только по нормали/Y, Z клеммы не тянем на «лицо».
func _elec_clear_for_duct(p: Vector3, n: Vector3, el_id: int) -> Vector3:
	var q: Vector3 = p + n * 0.005
	if el_id < 0:
		return q
	var root: Node3D = _electro_port_root(el_id)
	if root == null:
		return q
	var box: AABB = _module_world_aabb(root)
	if box.size.length_squared() < 1.0e-12:
		return q
	var pad: float = 0.010
	if n.y < -0.30:
		q.y = minf(q.y, box.position.y - pad)
		# Z оставляем от пенька (не face_z) — вход в КК сразу «назад» в канал.
		q.z = p.z
	elif n.y > 0.30:
		q.y = maxf(q.y, box.position.y + box.size.y + pad)
		q.z = p.z
	else:
		var face_z: float = box.position.z + box.size.z
		q.z = maxf(q.z, face_z + pad)
	return q


func _elec_pick_h_duct(hs: Array, p: Vector3, n: Vector3) -> Dictionary:
	if hs.is_empty():
		return {}
	var prefer_below: bool = n.y < -0.15
	var prefer_above: bool = n.y > 0.15
	var best: Dictionary = {}
	var best_score: float = 1.0e9
	# Сначала только КК по направлению выхода клеммы (без «петли» вверх/вниз).
	for pass_i in 2:
		best = {}
		best_score = 1.0e9
		for h in hs:
			var hy: float = float(h.get("y", 0.0))
			var dy: float = hy - p.y
			if pass_i == 0:
				if prefer_below and dy > 0.003:
					continue
				if prefer_above and dy < -0.003:
					continue
			var score: float = absf(dy)
			if score < best_score:
				best_score = score
				best = h
		if not best.is_empty():
			return best
	return hs[0]


func _elec_nearest_v_duct_x(vs: Array, mid_x: float) -> float:
	if vs.is_empty():
		return mid_x
	var best_x: float = float(vs[0].get("x", mid_x))
	var best_d: float = absf(best_x - mid_x)
	for v in vs:
		var vx: float = float(v.get("x", mid_x))
		var d: float = absf(vx - mid_x)
		if d < best_d:
			best_d = d
			best_x = vx
	return best_x


## Точка сразу вне AABB прибора по направлению клеммы (анти-clip).
func _elec_clear_outside(p: Vector3, n: Vector3, el_id: int) -> Vector3:
	var q: Vector3 = p + n * 0.006
	if el_id < 0:
		return q
	var root: Node3D = _electro_port_root(el_id)
	if root == null:
		return q
	var box: AABB = _module_world_aabb(root)
	if box.size.length_squared() < 1.0e-12:
		return q
	var pad: float = 0.012
	var face_z: float = box.position.z + box.size.z
	if n.y < -0.30:
		q.y = minf(q.y, box.position.y - pad)
		# Не уходить вглубь корпуса по Z — иначе вертикаль к КК режет колодку.
		q.z = maxf(q.z, face_z - 0.008)
	elif n.y > 0.30:
		q.y = maxf(q.y, box.position.y + box.size.y + pad)
		q.z = maxf(q.z, face_z - 0.008)
	else:
		# Торцевые порты — чуть вперёд от корпуса (к дверце).
		q.z = maxf(q.z, face_z + pad)
	return q


## Короткая перемычка: мостик снаружи корпуса, без КК.
func _hose_ortho_elec_jumper(a: Vector3, a1: Vector3, b: Vector3, b1: Vector3, na: Vector3, nb: Vector3, ida: int = -1, idb: int = -1, lane: int = 0, off_a: Vector3 = Vector3.ZERO, off_b: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	var ca: Vector3 = _elec_clear_outside(a1, na, ida) + off_a
	var cb: Vector3 = _elec_clear_outside(b1, nb, idb) + off_b
	_hose_ortho_push(pts, ca)
	var pack: Vector2 = _elec_pack_lane(lane)
	var o_lat: float = pack.x
	var o_dep: float = pack.y
	var facing_vert: bool = (na.y > 0.30 and nb.y < -0.30) or (na.y < -0.30 and nb.y > 0.30)
	if facing_vert:
		var mid_x: float = (ca.x + cb.x) * 0.5 + o_lat
		var mid_z: float = maxf(ca.z, cb.z) + 0.004 + o_dep
		_hose_ortho_push(pts, Vector3(mid_x, ca.y, mid_z))
		_hose_ortho_push(pts, Vector3(mid_x, cb.y, mid_z))
		_hose_ortho_push(pts, cb)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	var clear: float = 0.012
	var bridge_y: float
	if na.y < -0.35 and nb.y < -0.35:
		bridge_y = minf(ca.y, cb.y) - clear + o_lat
	elif na.y > 0.35 and nb.y > 0.35:
		bridge_y = maxf(ca.y, cb.y) + clear + o_lat
	else:
		bridge_y = (ca.y + cb.y) * 0.5 + o_lat
	# Перед фронтом приборов, не сквозь ступени корпуса.
	var front_z: float = maxf(ca.z, cb.z) + 0.006 + o_dep
	_hose_ortho_push(pts, Vector3(ca.x, bridge_y, ca.z))
	_hose_ortho_push(pts, Vector3(ca.x, bridge_y, front_z))
	_hose_ortho_push(pts, Vector3(cb.x, bridge_y, front_z))
	_hose_ortho_push(pts, Vector3(cb.x, bridge_y, cb.z))
	_hose_ortho_push(pts, cb)
	_hose_ortho_push(pts, b1)
	_hose_ortho_push(pts, b)
	return pts


## Короткая укладка: одна сторона без пересечения, либо вертикальная перемычка между рейками.
func _elec_wire_is_jumper(wire, a1: Vector3, na: Vector3, b1: Vector3, nb: Vector3) -> bool:
	if wire == null or circuit == null:
		return false
	var ida: int = _elec_primary_el_id(int(wire.a_id))
	var idb: int = _elec_primary_el_id(int(wire.b_id))
	if ida < 0 or idb < 0:
		return false
	var same_side: bool = (na.y < -0.30 and nb.y < -0.30) or (na.y > 0.30 and nb.y > 0.30)
	if ida == idb:
		return same_side
	var ea = circuit.get_element(ida)
	var eb = circuit.get_element(idb)
	if ea == null or eb == null:
		return false
	if str(ea.kind) != "electro" or str(eb.kind) != "electro":
		return false
	var ma: String = str(ea.electro_mount)
	var mb: String = str(eb.electro_mount)
	if ma != mb:
		return false
	if ma == "din":
		var ra: int = IsoCabinet.din_rail_of(int(ea.din_slot))
		var rb: int = IsoCabinet.din_rail_of(int(eb.din_slot))
		if ra != rb:
			# Между рейками короткой бывает только «рот-в-рот» (верх↔низ).
			return _elec_is_vertical_stack_jumper(ea, eb, a1, na, b1, nb, ida, idb)
	if not same_side:
		return false
	return not _elec_front_blocked_between(ida, idb, a1, b1)


## Приборы на разных рейках в одном «столбце», клеммы смотрят друг на друга.
func _elec_is_vertical_stack_jumper(ea, eb, a1: Vector3, na: Vector3, b1: Vector3, nb: Vector3, ida: int, idb: int) -> bool:
	var ra: int = IsoCabinet.din_rail_of(int(ea.din_slot))
	var rb: int = IsoCabinet.din_rail_of(int(eb.din_slot))
	if ra == rb:
		return false
	# Клеммы направлены навстречу (верх↔низ).
	var a_up: bool = na.y > 0.30
	var b_up: bool = nb.y > 0.30
	var a_dn: bool = na.y < -0.30
	var b_dn: bool = nb.y < -0.30
	if not ((a_up and b_dn) or (a_dn and b_up)):
		return false
	# Нижняя клемма — та, что смотрит вверх; верхняя — вниз.
	if a_up and a1.y >= b1.y - 0.002:
		return false
	if b_up and b1.y >= a1.y - 0.002:
		return false
	# Один столбец по X, зазор между рейками разумный.
	if absf(a1.x - b1.x) > 0.040:
		return false
	if absf(a1.y - b1.y) > 0.170:
		return false
	return not _elec_vertical_blocked_between(ida, idb, a1, b1)


## Чужой модуль в вертикальном зазоре между клеммами (тот же столбец X).
func _elec_vertical_blocked_between(ida: int, idb: int, a1: Vector3, b1: Vector3) -> bool:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return false
	var y0: float = minf(a1.y, b1.y)
	var y1: float = maxf(a1.y, b1.y)
	if y1 - y0 < 0.004:
		return false
	var x_mid: float = (a1.x + b1.x) * 0.5
	var mods := cab.get_node_or_null("Modules") as Node3D
	if mods == null:
		return false
	for child in mods.get_children():
		if not (child is Node3D):
			continue
		var n: Node3D = child as Node3D
		if n.is_queued_for_deletion():
			continue
		var eid: int = int(n.get_meta("el_id", -1))
		if eid < 0 or eid == ida or eid == idb:
			continue
		var box: AABB = _module_world_aabb(n)
		if box.size.length_squared() < 1.0e-12:
			continue
		var mx0: float = box.position.x
		var mx1: float = box.position.x + box.size.x
		if x_mid < mx0 - 0.002 or x_mid > mx1 + 0.002:
			continue
		var my0: float = box.position.y
		var my1: float = box.position.y + box.size.y
		var overlap: float = minf(y1, my1) - maxf(y0, my0)
		if overlap > 0.003:
			return true
	return false


func _elec_primary_el_id(el_id: int) -> int:
	if circuit == null:
		return el_id
	var el = circuit.get_element(el_id)
	if el == null:
		return -1
	if str(el.member_role) == "contact" and int(el.group_id) > 0:
		return int(el.group_id)
	return int(el.id)


## Есть ли чужой модуль на отрезке X между клеммами (тот же ряд) — путь по фронту пересёк бы прибор.
func _elec_front_blocked_between(ida: int, idb: int, a1: Vector3, b1: Vector3) -> bool:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return absf(a1.x - b1.x) > 0.045
	var x0: float = minf(a1.x, b1.x)
	var x1: float = maxf(a1.x, b1.x)
	if x1 - x0 < 0.004:
		return false
	var y_mid: float = (a1.y + b1.y) * 0.5
	var hosts: Array = []
	var mods := cab.get_node_or_null("Modules") as Node3D
	if mods != null:
		hosts.append(mods)
	var dgrid: Node3D = IsoCabinet.door_grid(cab)
	if dgrid != null:
		hosts.append(dgrid)
	for host in hosts:
		for child in host.get_children():
			if not (child is Node3D):
				continue
			var n: Node3D = child as Node3D
			if n.is_queued_for_deletion():
				continue
			var eid: int = int(n.get_meta("el_id", -1))
			if eid < 0 or eid == ida or eid == idb:
				continue
			var box: AABB = _module_world_aabb(n)
			if box.size.length_squared() < 1.0e-12:
				continue
			var cy: float = box.position.y + box.size.y * 0.5
			if absf(cy - y_mid) > 0.070:
				continue
			var mx0: float = box.position.x
			var mx1: float = box.position.x + box.size.x
			# Чужой корпус перекрывает интервал между клеммами → нельзя вести по фронту.
			var overlap: float = minf(x1, mx1) - maxf(x0, mx0)
			if overlap > 0.003:
				return true
	return false


func _module_world_aabb(node: Node3D) -> AABB:
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
				if world_aabb.size.length_squared() >= 1.0e-12:
					if not started:
						acc = world_aabb
						started = true
					else:
						acc = acc.merge(world_aabb)
		for ch in n.get_children():
			stack.append(ch)
	return acc if started else AABB()


## Z канала у монтажной панели (почти вплотную к стенке, чуть перед плоскостью DIN).
func _elec_duct_z(a: Vector3, b: Vector3) -> float:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var rail_z: float = _elec_nearest_rail_z(cab, (a + b) * 0.5)
	var term_z: float = minf(a.z, b.z)
	if rail_z < 1.0e20:
		# ~6 мм перед рейкой — почти вплотную к панели, не внутрь листа.
		var near_panel: float = rail_z + 0.006
		return clampf(near_panel, term_z - 0.060, term_z - 0.010)
	return term_z - 0.045


func _elec_nearest_rail_z(cab: Node3D, world_pos: Vector3) -> float:
	if cab == null:
		return INF
	var rails := cab.get_node_or_null("DinRails") as Node3D
	if rails == null:
		return INF
	var best_d: float = INF
	var best_z: float = INF
	for child in rails.get_children():
		if not (child is Node3D):
			continue
		var rail: Node3D = child as Node3D
		var mid_w: Vector3 = rail.to_global(Vector3.ZERO)
		var d: float = absf(world_pos.y - mid_w.y)
		if d < best_d:
			best_d = d
			best_z = mid_w.z
	return best_z


## Y подхода: под рядом при нижних клеммах, над рядом при верхних.
func _elec_duct_y(p: Vector3, n: Vector3) -> float:
	var clear: float = 0.020
	if n.y < -0.25:
		return p.y - clear
	if n.y > 0.25:
		return p.y + clear
	return p.y - clear


## X коридора у ближайшего торца DIN-рейки.
func _elec_nearest_side_x(a: Vector3, b: Vector3) -> float:
	var mid: float = (a.x + b.x) * 0.5
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var rail_xr: Vector2 = IsoCabinet.din_nearest_rail_x_range(cab, (a + b) * 0.5)
	var inset: float = 0.014
	if rail_xr != Vector2.ZERO:
		if absf(mid - rail_xr.x) <= absf(mid - rail_xr.y):
			return rail_xr.x + inset
		return rail_xr.y - inset
	return minf(a.x, b.x) - 0.028


func _hose_ortho_push(pts: PackedVector3Array, p: Vector3) -> void:
	if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(p) > 1.0e-8:
		pts.append(p)


func _sag(a: Vector3, b: Vector3, t: float) -> Vector3:
	# Совместимость для частиц потока.
	var pts := _hose_curve(a, Vector3.UP, b, Vector3.UP, 12)
	var idx := clampf(t, 0.0, 1.0) * float(pts.size() - 1)
	var i0 := clampi(int(floor(idx)), 0, pts.size() - 1)
	var i1 := clampi(i0 + 1, 0, pts.size() - 1)
	return pts[i0].lerp(pts[i1], idx - float(i0))


func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.0001:
		return Basis.IDENTITY
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _selected():
	if circuit == null:
		return null
	return circuit.primary()


func _is_cabinet_electro(el) -> bool:
	return el != null and str(el.kind) == "electro" and str(el.electro_mount) in ["door", "din"]


func _element_gizmo_pos(el) -> Vector3:
	# Кнопки/лампы на щитке живут в Modules, не в world_pos цеха.
	if _is_cabinet_electro(el):
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
		if cab != null:
			var node := IsoCabinet.module_node(cab, int(el.id))
			if node != null:
				return node.global_position
	return el.world_pos if el != null else Vector3.ZERO


func _sync_gizmo() -> void:
	if _gizmo == null:
		return
	var el = _selected()
	# Гизмо — при выборе в 3D-цехе (и при пуске, и на паузе).
	# На дверце/DIN гизмо мировых осей не показываем — модуль двигается по плоскости щита.
	var show_gizmo: bool = (
		el != null
		and str(circuit.selection_space) == "workshop"
		and not _is_cabinet_electro(el)
	)
	_gizmo.visible = show_gizmo
	_sync_schematic_glow()
	if not show_gizmo:
		return
	var at: Vector3 = _element_gizmo_pos(el)
	_gizmo.position = at
	# Поверх моделей, чтобы кольца/оси не клипались корпусом.
	if _gizmo.get_parent() == self:
		move_child(_gizmo, get_child_count() - 1)
	# Постоянный экранный размер (~14% высоты вида), не «съезжает» при зуме/FOV.
	_len = _gizmo_screen_len(at)
	_layout_gizmo()
	for child in _gizmo.get_children():
		var axis_name: String = str(child.name)
		var hot: bool = axis_name == _hover or axis_name == _axis_name()
		child.visible = _part_visible(axis_name)
		if child is MeshInstance3D:
			var mat := child.material_override as StandardMaterial3D
			if mat == null:
				mat = _gizmo_mat(_axis_color(axis_name))
				child.material_override = mat
			mat.albedo_color = Color(1.0, 0.82, 0.25) if hot else _axis_color(axis_name)
			mat.no_depth_test = true
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _sync_schematic_glow() -> void:
	var schematic_sel: bool = str(circuit.selection_space) == "schematic"
	for id in _records.keys():
		var rec = _records[id]
		var root: Node3D = rec["root"]
		var on: bool = schematic_sel and circuit.selected_ids.has(id)
		var glow: MeshInstance3D = rec.get("glow", null)
		if on:
			if glow == null or not is_instance_valid(glow):
				glow = MeshInstance3D.new()
				glow.name = "SchematicGlow"
				var box := BoxMesh.new()
				glow.mesh = box
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(UiTheme.ACCENT_CYAN.r, UiTheme.ACCENT_CYAN.g, UiTheme.ACCENT_CYAN.b, 0.18)
				mat.no_depth_test = false
				mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				glow.material_override = mat
				root.add_child(glow)
				rec["glow"] = glow
			var aabb := _model_aabb(root)
			var mesh := glow.mesh as BoxMesh
			# Чуть больше габарита модели, без учёта самого glow.
			var pad := 0.008
			mesh.size = Vector3(maxf(aabb.size.x, 0.02), maxf(aabb.size.y, 0.02), maxf(aabb.size.z, 0.02)) + Vector3(pad, pad, pad) * 2.0
			glow.position = aabb.position + aabb.size * 0.5
			glow.visible = true
		elif glow != null and is_instance_valid(glow):
			glow.visible = false


func _part_visible(_axis_name: String) -> bool:
	return true


func _axis_name() -> String:
	if _drag != "gizmo":
		return ""
	return _hover


func _axis_color(axis_name: String) -> Color:
	if axis_name.begins_with("X"):
		return Color(0.9, 0.28, 0.22)
	if axis_name.begins_with("Y"):
		return Color(0.3, 0.75, 0.32)
	return UiTheme.BRAND_BLUE.lightened(0.2)


func _gizmo_screen_len(at: Vector3) -> float:
	# Мировая длина стрелки так, чтобы на экране занимала ~14% высоты viewport.
	if _camera == null:
		return 0.12
	var dist := maxf(_camera.global_position.distance_to(at), 0.01)
	var world_h := 2.0 * dist * tan(deg_to_rad(_camera.fov) * 0.5)
	return clampf(world_h * 0.14, 0.025, 0.55)


func _build_gizmo() -> void:
	for spec in [["X", Vector3.RIGHT], ["Y", Vector3.UP], ["Z", Vector3(0, 0, 1)]]:
		var shaft := MeshInstance3D.new()
		shaft.name = spec[0]
		var sm := CylinderMesh.new()
		shaft.mesh = sm
		shaft.material_override = _gizmo_mat(_axis_color(spec[0]))
		_gizmo.add_child(shaft)
		var ring := MeshInstance3D.new()
		ring.name = spec[0] + "R"
		var torus := TorusMesh.new()
		ring.mesh = torus
		ring.material_override = _gizmo_mat(_axis_color(spec[0]))
		_gizmo.add_child(ring)
	_layout_gizmo()


func _gizmo_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Compatibility: alpha+no_depth часто «съедает» гизмо — рисуем непрозрачно поверх глубины.
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 127
	return mat


func set_xray(enabled: bool) -> void:
	xray = enabled
	for id in _records.keys():
		var rec = _records[id]
		if rec != null and rec.has("root"):
			Iso.apply_xray(rec["root"], xray)
	# Щит: рентген только у модулей с внутренностями.
	if _machines != null:
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab != null:
			IsoCabinet.apply_xray(cab, xray)


func _layout_gizmo() -> void:
	var axes := {"X": Vector3.RIGHT, "Y": Vector3.UP, "Z": Vector3(0, 0, 1)}
	for name in axes.keys():
		var axis: Vector3 = axes[name]
		var shaft: MeshInstance3D = _gizmo.get_node(name)
		var mesh := shaft.mesh as CylinderMesh
		mesh.top_radius = maxf(_len * 0.014, 0.00035)
		mesh.bottom_radius = maxf(_len * 0.038, 0.0007)
		mesh.height = _len
		shaft.position = axis * (_len * 0.5)
		shaft.basis = _basis_y(axis)
		var ring: MeshInstance3D = _gizmo.get_node(name + "R")
		var torus := ring.mesh as TorusMesh
		# Тонкое кольцо: major≈0.4·len, minor≈0.02·len (inner/outer = крайние радиусы).
		var major := _len * 0.40
		var minor := maxf(_len * 0.018, 0.00035)
		torus.inner_radius = maxf(major - minor, 0.0002)
		torus.outer_radius = major + minor
		torus.rings = 20
		torus.ring_segments = 28
		if name == "X":
			ring.rotation_degrees = Vector3(0, 0, 90)
		elif name == "Z":
			ring.rotation_degrees = Vector3(90, 0, 0)
		else:
			ring.rotation_degrees = Vector3.ZERO


func _rmb_try_open_props(screen: Vector2) -> void:
	## ПКМ-клик (без drag) по любому 3D-элементу с частями → панель свойств на схеме.
	if circuit == null:
		return
	var ray := _ray(screen)
	var eid: int = -1
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab != null:
		var hit_cab: Dictionary = IsoCabinet.pick_interact(cab, ray["origin"], ray["dir"])
		if str(hit_cab.get("kind", "")) == "module":
			eid = int(hit_cab.get("id", -1))
	if eid < 0:
		eid = _pick_machine(ray["origin"], ray["dir"])
	if eid < 0:
		return
	var el = circuit.get_element(eid)
	if el == null:
		return
	# Контакт группы → primary (кнопка/катушка/реле).
	if str(el.kind) == "electro" and str(el.member_role) == "contact" and int(el.group_id) >= 0:
		eid = int(el.group_id)
		el = circuit.get_element(eid)
		if el == null:
			return
	if Geom.part_zones(el).is_empty() and str(el.kind) not in ["cylinder", "valve", "electro", "source", "junction"]:
		return
	circuit.select_only(eid, "workshop")
	request_element_props.emit(eid, screen)


func _begin_pick(screen: Vector2) -> void:
	if circuit == null:
		return
	# Не начинать новый захват, пока ЛКМ уже держит элемент.
	if _drag_locks_hover():
		return
	var ray := _ray(screen)
	# Соединение проводов в 3D: ЛКМ на клемме → вести → отпустить на другой.
	var port0: Dictionary = _pick_port_hover(ray["origin"], ray["dir"])
	if not port0.is_empty():
		_drag = "wire_port"
		_wire_port_a_id = int(port0.get("id", -1))
		_wire_port_a_name = str(port0.get("port", ""))
		_show_hover_hl_port(port0["pos"] as Vector3, port0.get("dir", Vector3.UP) as Vector3)
		_update_wire_ghost(screen)
		return
	# Щит / электромодули.
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
	if cab != null:
		var hit_cab: Dictionary = IsoCabinet.pick_interact(cab, ray["origin"], ray["dir"])
		if not hit_cab.is_empty():
			if str(hit_cab.get("kind", "")) == "door":
				IsoCabinet.toggle_door(cab, circuit)
				return
			if str(hit_cab.get("kind", "")) == "module":
				var eid: int = int(hit_cab.get("id", -1))
				var eel = circuit.get_element(eid)
				if eel != null:
					circuit.select_only(eid, "workshop")
					var hit_pt: Vector3 = hit_cab.get("point", Vector3.ZERO) as Vector3
					var hit_node := hit_cab.get("node") as Node3D
					# Крутилки KT на лице — уставка всегда; иначе перенос модуля
					# (короткий клик при пуске — воздействие, см. отпускание ЛКМ).
					if str(eel.electro_class) == "timer_relay" and hit_node != null:
						var dial_kind: String = _timer_dial_kind_at(hit_node, hit_pt)
						if dial_kind != "":
							_drag = "timer_dial"
							_timer_dial_kind = dial_kind
							_timer_dial_accum = 0.0
							_actuate_el_id = eid
							_module_hit_node = hit_node
							_module_press = screen
							return
					if str(eel.electro_mount) == "door" or str(eel.electro_mount) == "din":
						_drag = "door_module" if str(eel.electro_mount) == "door" else "din_module"
						_actuate_el_id = eid
						_module_press = screen
						_module_hit_pt = hit_pt
						_module_hit_node = hit_node
						_module_moved = false
				return
	# Органы пневмораспределителя — при пуске (на паузе не перехватывают гизмо).
	if bool(circuit.running):
		var act := _pick_actuator(ray["origin"], ray["dir"])
		if not act.is_empty():
			_begin_actuate(int(act["id"]), str(act["side"]), act["node"] as Node3D)
			return
	var handle := _pick_handle(ray["origin"], ray["dir"])
	if handle != "":
		var el = _selected()
		if el == null:
			return
		_drag = "gizmo"
		_hover = handle
		_axis = _vector_for(handle)
		_drag_pos = el.world_pos
		_drag_basis = el.world_basis
		# Кольцо = поворот, стрелка = перемещение (оба гизмо видны сразу).
		mode = "rotate" if handle.ends_with("R") else "move"
		if mode == "move":
			_drag_point = _axis_coord(ray["origin"], ray["dir"], el.world_pos, _axis)
		else:
			_drag_angle = _axis_angle(ray["origin"], ray["dir"], el.world_pos, _axis)
		return
	var picked := _pick_machine(ray["origin"], ray["dir"])
	if picked >= 0:
		circuit.select_only(picked, "workshop")
		_drag = "click"
		_sync_gizmo()
	else:
		circuit.clear_selection()
		_drag = "click"
		_sync_gizmo()


func _finish_wire_port(screen: Vector2) -> void:
	var a_id: int = _wire_port_a_id
	var a_port: String = _wire_port_a_name
	_drag = ""
	_wire_port_a_id = -1
	_wire_port_a_name = ""
	_hide_wire_ghost()
	if circuit == null or a_id < 0 or a_port == "":
		return
	var ray := _ray(screen)
	var port_b: Dictionary = _pick_port_hover(ray["origin"], ray["dir"])
	if port_b.is_empty():
		circuit.notify("Соединение отменено")
		return
	var b_id: int = int(port_b.get("id", -1))
	var b_port: String = str(port_b.get("port", ""))
	if b_id < 0 or b_port == "":
		return
	# Клеммы контактов в 3D на primary, на схеме — у member (11/COM…).
	var a_end: Dictionary = IsoElectro.resolve_scheme_wire_end(circuit, a_id, a_port)
	var b_end: Dictionary = IsoElectro.resolve_scheme_wire_end(circuit, b_id, b_port)
	if a_end.is_empty() or b_end.is_empty():
		circuit.notify("У элемента нет такого канала")
		return
	var ra_id: int = int(a_end["id"])
	var ra_port: String = str(a_end["port"])
	var rb_id: int = int(b_end["id"])
	var rb_port: String = str(b_end["port"])
	if ra_id == rb_id and ra_port == rb_port:
		circuit.notify("Нельзя соединить порт сам с собой")
		return
	if circuit.connect_or_branch(ra_id, ra_port, rb_id, rb_port):
		circuit.notify("Соединение создано")


func _click_electro_3d(el, hit_point: Vector3 = Vector3.ZERO, hit_node: Node3D = null) -> void:
	# Короткий клик (мышь уже отпущена): моментная кнопка — импульс, не hold.
	if el == null or str(el.kind) != "electro":
		return
	if str(el.electro_class) in ["button", "e_stop"] and not bool(el.latching) and str(el.electro_class) != "e_stop":
		el.pressed = true
		var eid: int = int(el.id)
		get_tree().create_timer(0.12).timeout.connect(func():
			if circuit == null:
				return
			var bel = circuit.get_element(eid)
			if bel != null and str(bel.kind) == "electro" and not bool(bel.latching):
				bel.pressed = false
		)
		return
	_toggle_electro_3d(el, hit_point, hit_node)


func _toggle_electro_3d(el, hit_point: Vector3 = Vector3.ZERO, hit_node: Node3D = null) -> void:
	if el == null or str(el.kind) != "electro":
		return
	match str(el.electro_class):
		"button", "e_stop":
			if bool(el.latching) or str(el.electro_class) == "e_stop":
				el.pressed = not bool(el.pressed)
			else:
				el.pressed = true
				_drag = "electro_btn"
				_actuate_el_id = int(el.id)
		"switch":
			# Клик по риске/сектору лица — сразу в это положение (не +1 по кругу).
			if hit_node != null:
				var local: Vector3 = hit_node.to_local(hit_point)
				ElectroLib.set_switch_pos(el, IsoElectro.switch_pos_from_local_hit(el, local))
			else:
				ElectroLib.set_switch_pos(el, (int(el.switch_pos) + 1) % maxi(int(el.switch_positions), 2))
		"mcb", "rcd", "rcbo":
			el.closed = not bool(el.closed)
		"thermal":
			el.pressed = not bool(el.pressed)
		"timer_relay":
			pass
		_:
			pass


func _hover_tip_locked() -> String:
	var el = circuit.get_element(_actuate_el_id) if circuit != null else null
	if el == null:
		return ""
	if _drag == "timer_dial" and _module_hit_node != null:
		var tip: String = ""
		if _timer_dial_kind == "value":
			tip = "Задержка: %s" % ElectroLib.timer_format_value(el)
		elif _timer_dial_kind == "unit":
			tip = "Единицы: %s" % ElectroLib.timer_unit_label(int(el.timer_unit))
		_show_timer_zone_hl(_module_hit_node, tip)
		return tip
	if _drag in ["din_module", "door_module", "electro_btn", "actuate"]:
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			_show_hover_hl_node(_module_hit_node)
		elif _actuate_node != null and is_instance_valid(_actuate_node):
			_show_hover_hl_node(_actuate_node)
		return str(el.tag)
	if _drag == "gizmo":
		clear_hover_highlight()
		return str(el.tag)
	return ""


func _show_hover_hl_fixed(root: Node3D, local_pos: Vector3, size: Vector3) -> void:
	_ensure_hover_hl()
	if root == null or not is_instance_valid(root):
		clear_hover_highlight()
		return
	_hover_hl.mesh = _hover_hl_box
	_hover_hl.global_basis = root.global_basis
	_hover_hl.global_position = root.to_global(local_pos)
	_hover_hl.scale = size
	_hover_hl.visible = true


func _show_timer_zone_hl(root: Node3D, tip: String) -> void:
	if root == null:
		return
	var zone: Node3D = null
	if tip.begins_with("Задержка"):
		zone = root.get_node_or_null("DialOnZone") as Node3D
	elif tip.begins_with("Единицы"):
		zone = root.get_node_or_null("DialUnitZone") as Node3D
	elif tip.begins_with("U "):
		zone = root.get_node_or_null("LedU") as Node3D
	if zone != null:
		var sz: Vector3 = Vector3(0.014, 0.014, 0.006) if not tip.begins_with("U ") else Vector3(0.007, 0.007, 0.005)
		_show_hover_hl_fixed(root, zone.position, sz)
	else:
		_show_hover_hl_node(root)


func _timer_dial_kind_at(node: Node3D, world_pt: Vector3) -> String:
	if node == null:
		return ""
	var local_t: Vector3 = node.to_local(world_pt)
	var zone_on := node.get_node_or_null("DialOnZone") as Node3D
	var zone_unit := node.get_node_or_null("DialUnitZone") as Node3D
	if zone_on != null and local_t.distance_to(zone_on.position) < Parts.mm(9.0):
		return "value"
	if zone_unit != null and local_t.distance_to(zone_unit.position) < Parts.mm(9.0):
		return "unit"
	var dial_on := node.get_node_or_null("DialOn") as Node3D
	var dial_unit := node.get_node_or_null("DialUnit") as Node3D
	if dial_unit == null:
		dial_unit = node.get_node_or_null("DialOff") as Node3D
	if dial_on != null and local_t.distance_to(dial_on.position) < Parts.mm(9.0):
		return "value"
	if dial_unit != null and local_t.distance_to(dial_unit.position) < Parts.mm(9.0):
		return "unit"
	return ""


func _timer_zone_tip(el, node: Node3D, world_pt: Vector3) -> String:
	if el == null or node == null:
		return ""
	var local_t: Vector3 = node.to_local(world_pt)
	var dial_kind: String = _timer_dial_kind_at(node, world_pt)
	if dial_kind == "value":
		return "Задержка: %s" % ElectroLib.timer_format_value(el)
	if dial_kind == "unit":
		return "Единицы: %s" % ElectroLib.timer_unit_label(int(el.timer_unit))
	var led := node.get_node_or_null("LedU") as Node3D
	if led != null and local_t.distance_to(led.position) < Parts.mm(6.0):
		return "U питания"
	return ""


func _sync_timer_group_delays(primary) -> void:
	if primary == null or circuit == null:
		return
	ElectroLib.timer_sync_delays(primary)
	var gid: int = int(primary.id)
	for other in circuit.elements:
		if int(other.group_id) != gid:
			continue
		other.delay_on = float(primary.delay_on)
		other.delay_off = float(primary.delay_off)
		other.timer_mode = str(primary.timer_mode)
		other.timer_unit = int(primary.timer_unit)
		other.timer_value = float(primary.timer_value)


func _begin_actuate(el_id: int, side: String, node: Node3D) -> void:
	var el = circuit.get_element(el_id)
	if el == null or node == null:
		return
	_drag = "actuate"
	_actuate_el_id = el_id
	_actuate_side = side
	_actuate_node = node
	if side == "left":
		el.command_left = true
	else:
		el.command_right = true
	circuit.refresh_valve_pos(el)
	circuit.select_only(el_id, "workshop")
	node.set_meta("_cmd_pressed", true)
	_tween_actuator(node, true)


func _end_actuate() -> void:
	if _actuate_el_id >= 0 and circuit != null:
		var el = circuit.get_element(_actuate_el_id)
		if el != null:
			if _actuate_side == "left":
				el.command_left = false
			else:
				el.command_right = false
			circuit.refresh_valve_pos(el)
	if _actuate_node != null and is_instance_valid(_actuate_node):
		_actuate_node.set_meta("_cmd_pressed", false)
		_tween_actuator(_actuate_node, false)
	_drag = ""
	_actuate_el_id = -1
	_actuate_side = ""
	_actuate_node = null


func _sync_actuators_from_commands(el, root: Node3D) -> void:
	if el == null or root == null:
		return
	for act in _find_actuators(root):
		if act == null or not is_instance_valid(act):
			continue
		var side := str(act.get_meta("actuate_side", ""))
		var pressed := false
		if side == "left":
			pressed = bool(el.command_left)
		elif side == "right":
			pressed = bool(el.command_right)
		else:
			continue
		# Локальный 3D-drag уже ведёт этот орган.
		if _drag == "actuate" and _actuate_el_id == int(el.id) and _actuate_side == side:
			act.set_meta("_cmd_pressed", pressed)
			continue
		var prev = act.get_meta("_cmd_pressed", null)
		if prev != null and bool(prev) == pressed:
			continue
		act.set_meta("_cmd_pressed", pressed)
		_tween_actuator(act, pressed)


func _tween_actuator(node: Node3D, pressed: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rest: Vector3 = node.get_meta("actuate_rest", Vector3.ZERO)
	var travel: Vector3 = node.get_meta("actuate_travel", Vector3.ZERO)
	var target := rest + travel if pressed else rest
	if node.has_meta("_act_tween"):
		var old = node.get_meta("_act_tween")
		if old is Tween and is_instance_valid(old):
			(old as Tween).kill()
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", target, 0.08)
	node.set_meta("_act_tween", tw)
	_actuate_tween = tw


func _pick_actuator(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := 1.0e9
	for id in _records.keys():
		var root: Node3D = _records[id]["root"]
		for act in _find_actuators(root):
			var side := str(act.get_meta("actuate_side", ""))
			if side == "":
				continue
			var local: AABB = _model_aabb(act)
			if local.size.length() < 1e-6:
				continue
			# Немного раздуваем хитбокс для удобства клика.
			local = local.grow(0.012)
			var world := _xform_aabb(local, act.global_transform)
			var t := _ray_aabb(origin, dir, world)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {"id": id, "side": side, "node": act}
	return best


func _find_actuators(root: Node) -> Array:
	var out: Array = []
	if root is Node3D and root.has_meta("actuate_side"):
		out.append(root)
	for child in root.get_children():
		out.append_array(_find_actuators(child))
	return out


func _cam_mod() -> float:
	if Input.is_key_pressed(KEY_SHIFT):
		return 3.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return 0.14
	return 1.0


func _on_drag(event: InputEventMouseMotion) -> void:
	if _drag == "wire_port":
		_last_hover_screen = event.position
		var ray_w := _ray(event.position)
		var hit_w: Dictionary = _pick_port_hover(ray_w["origin"], ray_w["dir"])
		if not hit_w.is_empty():
			_show_hover_hl_port(hit_w["pos"] as Vector3, hit_w.get("dir", Vector3.UP) as Vector3)
		_update_wire_ghost(event.position)
		return
	var mod := _cam_mod()
	if _drag == "orbit" or _drag == "look":
		_yaw -= event.relative.x * 0.004 * mod
		var pitch_lim: float = 1.20 if cam_mode == "fpv" else 1.45
		# Пролёт/FPV: мышь вверх = смотреть вверх; в орбите знак другой (камера снаружи).
		var dy: float = event.relative.y * 0.004 * mod
		if cam_mode == "fpv" or cam_mode == "fly":
			dy = -dy
		_pitch = clampf(_pitch + dy, -pitch_lim, pitch_lim)
		return
	if _drag == "pan":
		var right := _camera.global_basis.x
		var up := _camera.global_basis.y
		var scale := _distance * 0.00075 * mod
		_target += (-right * event.relative.x + up * event.relative.y) * scale
		return
	if _drag == "timer_dial":
		var tel = circuit.get_element(_actuate_el_id) if circuit != null else null
		if tel == null or str(tel.electro_class) != "timer_relay":
			return
		# Горизонталь мыши крутит: вправо → по часовой (увеличение уставки).
		var dx: float = float(event.relative.x)
		if _timer_dial_kind == "value":
			var lim: Vector2 = ElectroLib.timer_value_limits(int(tel.timer_unit))
			var span: float = lim.y - lim.x
			# Полный ход шкалы ≈ 220 px мыши; шаг целый.
			var step: float = maxf(span / 220.0, 1.0)
			tel.timer_value = clampf(roundf(float(tel.timer_value) + dx * step), lim.x, lim.y)
			_sync_timer_group_delays(tel)
		elif _timer_dial_kind == "unit":
			_timer_dial_accum += dx
			if _timer_dial_accum > 28.0:
				tel.timer_unit = mini(int(tel.timer_unit) + 1, 2)
				ElectroLib.timer_clamp_value(tel)
				_timer_dial_accum = 0.0
				_sync_timer_group_delays(tel)
			elif _timer_dial_accum < -28.0:
				tel.timer_unit = maxi(int(tel.timer_unit) - 1, 0)
				ElectroLib.timer_clamp_value(tel)
				_timer_dial_accum = 0.0
				_sync_timer_group_delays(tel)
		if _module_hit_node != null:
			IsoElectro.update_state(_module_hit_node, tel)
		return
	if _drag == "door_module":
		if event.position.distance_to(_module_press) > 4.0:
			_module_moved = true
		var del = circuit.get_element(_actuate_el_id) if circuit != null else null
		if del == null or str(del.electro_mount) != "door":
			return
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab == null:
			return
		var ray_d := _ray(event.position)
		var xy: Vector2 = IsoCabinet.project_door_xy(cab, ray_d["origin"], ray_d["dir"])
		if xy.x >= 0.0:
			IsoCabinet.try_set_door_xy(circuit, del, xy)
		return
	if _drag == "din_module":
		if event.position.distance_to(_module_press) > 4.0:
			_module_moved = true
		var din_el = circuit.get_element(_actuate_el_id) if circuit != null else null
		if din_el == null or str(din_el.electro_mount) != "din":
			return
		var cab_d := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab_d == null:
			return
		var ray_din := _ray(event.position)
		var width: int = IsoCabinet.din_width_slots(din_el)
		var slot: int = IsoCabinet.project_din_slot(cab_d, ray_din["origin"], ray_din["dir"], width, circuit, int(din_el.id))
		if slot >= 0:
			IsoCabinet.try_set_din_slot(circuit, din_el, slot)
		return
	if _drag != "gizmo":
		return
	var el = _selected()
	if el == null:
		return
	var ray := _ray(event.position)
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var fine := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	if mode == "move":
		var coord := _axis_coord(ray["origin"], ray["dir"], _drag_pos, _axis)
		var delta_m := coord - _drag_point
		# Shift = 5 мм, Ctrl = 1 мм; без модификатора — плавно.
		var step_m := 0.0
		if fine:
			step_m = 0.001
		elif shift:
			step_m = 0.005
		if step_m > 0.0:
			delta_m = roundf(delta_m / step_m) * step_m
		el.world_pos = _drag_pos + _axis * delta_m
		el.auto_ground = false
	else:
		var angle := _axis_angle(ray["origin"], ray["dir"], el.world_pos, _axis)
		var delta := wrapf(angle - _drag_angle, -PI, PI)
		# Поворот: по умолчанию 5°, Shift 15°, Ctrl 1°.
		var step_deg := 5.0
		if fine:
			step_deg = 1.0
		elif shift:
			step_deg = 15.0
		var step_a := deg_to_rad(step_deg)
		delta = roundf(delta / step_a) * step_a
		el.world_basis = Basis(_axis, delta) * _drag_basis
		var rec_r = _records.get(el.id, null)
		if rec_r != null:
			rec_r["user_rotated"] = true


func _hover_gizmo(screen: Vector2) -> void:
	if _drag == "gizmo":
		return
	var ray := _ray(screen)
	_hover = _pick_handle(ray["origin"], ray["dir"])


func _ray(screen: Vector2) -> Dictionary:
	return {
		"origin": _camera.project_ray_origin(screen),
		"dir": _camera.project_ray_normal(screen),
	}


func pick_floor_point(screen: Vector2) -> Vector3:
	# Пересечение с рабочей плоскостью (не с полом) — аппараты сразу на уровне глаз.
	if _camera == null:
		return Vector3(0, WORK_Y, 0)
	var ray := _ray(screen)
	var hit = _ray_plane(ray["origin"], ray["dir"], Vector3(0, WORK_Y, 0), Vector3.UP)
	if hit == null:
		var o: Vector3 = ray["origin"]
		o.y = WORK_Y
		return o
	var p: Vector3 = hit
	p.y = WORK_Y
	return p


func _vector_for(handle: String) -> Vector3:
	if handle.begins_with("X"):
		return Vector3.RIGHT
	if handle.begins_with("Y"):
		return Vector3.UP
	return Vector3(0, 0, 1)


func _pick_handle(origin: Vector3, dir: Vector3) -> String:
	var el = _selected()
	if el == null:
		return ""
	if _is_cabinet_electro(el):
		return ""
	var best := ""
	# Порог попадания масштабируется с экранным размером гизмо.
	var best_d := clampf(_len * 0.22, 0.008, 0.08)
	for name in ["X", "Y", "Z", "XR", "YR", "ZR"]:
		var axis := _vector_for(name)
		var dist: float
		if name.ends_with("R"):
			dist = _ring_distance(origin, dir, el.world_pos, axis, _len * 0.40)
		else:
			dist = _segment_distance(origin, dir, el.world_pos, axis, _len)
		if dist >= 0.0 and dist < best_d:
			best_d = dist
			best = name
	return best


func _pick_machine(origin: Vector3, dir: Vector3) -> int:
	var best := -1
	var best_t := 1.0e9
	for id in _records.keys():
		var root: Node3D = _records[id]["root"]
		var local: AABB = _model_aabb(root)
		var world := _xform_aabb(local, root.global_transform)
		var t := _ray_aabb(origin, dir, world)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = id
	return best


func _segment_distance(origin: Vector3, dir: Vector3, point: Vector3, axis: Vector3, length: float) -> float:
	var pair := _line_line(origin, dir, point, axis)
	var s: float = pair.y
	if pair.x < 0.0 or s < 0.0 or s > length:
		return -1.0
	var on_ray := origin + dir * pair.x
	var on_axis := point + axis * s
	return on_ray.distance_to(on_axis)


func _ring_distance(origin: Vector3, dir: Vector3, center: Vector3, axis: Vector3, radius: float) -> float:
	var hit = _ray_plane(origin, dir, center, axis)
	if hit == null:
		return -1.0
	var radial := (hit as Vector3) - center
	return absf(radial.length() - radius)


func _line_line(origin: Vector3, dir: Vector3, point: Vector3, axis: Vector3) -> Vector2:
	var w0 := origin - point
	var a := dir.dot(dir)
	var b := dir.dot(axis)
	var c := axis.dot(axis)
	var d := dir.dot(w0)
	var e := axis.dot(w0)
	var denom := a * c - b * b
	if absf(denom) < 1.0e-8:
		return Vector2(0.0, 0.0)
	var t := (b * e - c * d) / denom
	var s := (a * e - b * d) / denom
	return Vector2(t, s)


func _axis_coord(origin: Vector3, dir: Vector3, point: Vector3, axis: Vector3) -> float:
	var cam := (_camera.global_position - point).normalized()
	var normal := axis.cross(cam).cross(axis)
	if normal.length_squared() < 1.0e-6:
		normal = axis.cross(Vector3.UP)
	normal = normal.normalized()
	var hit = _ray_plane(origin, dir, point, normal)
	if hit == null:
		return 0.0
	return (hit - point).dot(axis)


func _axis_angle(origin: Vector3, dir: Vector3, point: Vector3, axis: Vector3) -> float:
	var hit = _ray_plane(origin, dir, point, axis)
	if hit == null:
		return 0.0
	var v: Vector3 = hit - point
	var ref_x := axis.cross(Vector3.UP)
	if ref_x.length_squared() < 1.0e-6:
		ref_x = axis.cross(Vector3.RIGHT)
	ref_x = ref_x.normalized()
	var ref_y := axis.cross(ref_x).normalized()
	return atan2(v.dot(ref_y), v.dot(ref_x))


func _ray_plane(origin: Vector3, dir: Vector3, point: Vector3, normal: Vector3):
	var den := normal.dot(dir)
	if absf(den) < 1.0e-6:
		return null
	var t := normal.dot(point - origin) / den
	if t < 0.0:
		return null
	return origin + dir * t


func _ray_aabb(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var tmin := 0.0
	var tmax := 1.0e9
	for i in 3:
		var o := origin[i]
		var d := dir[i]
		var mn := box.position[i]
		var mx := mn + box.size[i]
		if absf(d) < 1.0e-8:
			if o < mn or o > mx:
				return -1.0
			continue
		var t1 := (mn - o) / d
		var t2 := (mx - o) / d
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin


func _model_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var started := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if str(child.name) == "SchematicGlow":
				continue
			stack.append(child)
			if child is Label3D:
				continue
			if child is VisualInstance3D:
				var visual := child as VisualInstance3D
				var xf := root.global_transform.affine_inverse() * visual.global_transform
				var box := _xform_aabb(visual.get_aabb(), xf)
				if box.size.length() < 1.0e-8:
					continue
				if not started:
					merged = box
					started = true
				else:
					merged = merged.merge(box)
	return merged


func _xform_aabb(box: AABB, xf: Transform3D) -> AABB:
	var merged := AABB(xf * box.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		merged = merged.expand(xf * box.get_endpoint(i))
	return merged
