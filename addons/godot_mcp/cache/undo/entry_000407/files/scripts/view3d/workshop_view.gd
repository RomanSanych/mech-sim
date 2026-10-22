extends Node3D
## Трёхмерный цех: параметрические модели, мировой гизмо и поток воздуха.

const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const IsoValve = preload("res://scripts/view3d/iso_valve.gd")
const IsoJunction = preload("res://scripts/view3d/iso_junction.gd")
const IsoThrottle = preload("res://scripts/view3d/iso_throttle.gd")
const IsoCheck = preload("res://scripts/view3d/iso_check.gd")
const IsoReservoir = preload("res://scripts/view3d/iso_reservoir.gd")
const IsoRegulator = preload("res://scripts/view3d/iso_regulator.gd")
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
## Подсветка корпуса: rim-overlay на исходных мешах (не клоны-пластинки).
var _hover_hl_mesh_root: Node3D
var _hover_hl_grow_mat: ShaderMaterial
var _hover_hl_src_id: int = 0
var _hover_hl_src_pairs: Array = [] # [{src: MeshInstance3D, prev: Material}]
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
var _sleeve_drag_wire_id := -1
var _sleeve_drag_end := "" # "a" | "b"
var _sleeve_drag_node: MeshInstance3D = null
var _ext_hover_bound := false
## Кэш КК на кадр + флаг «после drag нужен HQ-rebuild».
var _hose_ducts_cache: Dictionary = {}
var _hose_ducts_frame: int = -1
var _hose_hq_pending: bool = false
## Орто-каркас последней пневмотрубки (до fillet) — для tip/зубьев КК.
var _hose_last_ortho: PackedVector3Array = PackedVector3Array()
var _duct_finger_sig: String = ""
## Гофра дверца↔щит (одна на все жилы) + кэш кабинетной части при анимации дверцы.
var _door_flex_node: MeshInstance3D = null
var _door_flex_sig: String = ""
## Прошлый кадр дверца анимировалась — на спаде нужен полный HQ-пересчёт пролётов.
var _door_was_animating: bool = false
## Сдвоенные НШВИ на клеммах с двумя проводами: "elId|port" -> Node3D.
var _nshvi_doubles: Dictionary = {}
## Разведение электропроводов: уникальная дорожка + сдвиг у клемм модуля.
var _elec_lane_by_wire: Dictionary = {} # wire_id -> int (−N…+N)
var _elec_exit_off: Dictionary = {} # "elId|port" -> Vector3
## Perf: кэши на кадр (большие сцены).
var _coil_sig_frame: int = -1
var _coil_sig_cached: String = ""
var _has_elec_wires_frame: int = -1
var _has_elec_wires_cached: bool = false
var _pviz_max_frame: int = -1
var _pviz_max_pa: float = 0.0
## Пакетная сборка 3D после загрузки сцены.
var _build_queue: Array = [] # element ids
var _build_budget: int = 4
var _perf_hud: bool = false
var _perf_ms_machines: float = 0.0
var _perf_ms_hoses: float = 0.0
const ELEC_LANE_PITCH := 0.0085 # м между трассами в сечении КК (≥ Ø + зазор)
## НШВИ: гильза ~10 мм целиком (для иксрея); за кромку клеммы ~2 мм.
const ELEC_NSHVI_METAL_LEN := 0.010
const ELEC_NSHVI_METAL_PEEK := 0.002
const ELEC_NSHVI_COLLAR_LEN := 0.008
## Колпачок: ¾ цилиндр + ¼ усечённый конус к гильзе.
const ELEC_NSHVI_COLLAR_CONE_FRAC := 0.25
## Маркировочный кембрик: ГОСТ — длина не менее 20 мм.
const ELEC_MARK_LEN := 0.020
const ELEC_SLEEVE_LEN := ELEC_MARK_LEN
## Нахлёст кембрика на колпачок (зазора быть не должно).
const ELEC_SLEEVE_OVERLAP := 0.0005
## Стопка у клеммы (выступ+колпачок+кембрик).
const ELEC_TIP_STACK := ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN + ELEC_MARK_LEN - ELEC_SLEEVE_OVERLAP
## Прямой запас после кембрика до первого гиба — иначе fillet «перекручивает» трубку у края.
const ELEC_JUMPER_BEND_CLEAR := 0.010
const ELEC_JUMPER_STUB := ELEC_TIP_STACK + ELEC_JUMPER_BEND_CLEAR
## Короткий пень — только для классификации jumper/duct (не для геометрии пути).
const ELEC_SLEEVE_STUB := ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN + 0.001
## В КК: прямой участок через всю стопку НШВИ+кембрик + запас до fillet.
const ELEC_DUCT_STUB := ELEC_TIP_STACK + ELEC_JUMPER_BEND_CLEAR
## Ввод (без НШВИ): кембрик ≥20 мм на изоляции — stub не короче маркировки.
const ELEC_MARK_ONLY_STUB := 0.001 + ELEC_MARK_LEN + ELEC_JUMPER_BEND_CLEAR
## Обрезка трубки чуть короче стопки — провод заходит в кембрик (без щели).
const ELEC_TUBE_TRIM := ELEC_TIP_STACK - 0.0018
const ELEC_TUBE_IN_MARK := 0.0018
## Дверца: НШВИ → 90° вверх → кембрик на прямой → запас → дальше. Без отвода вбок.
const ELEC_DOOR_BEND_CLEAR := 0.010
const ELEC_DOOR_RISE_BEFORE_MARK := 0.012
const ELEC_DOOR_AFTER_MARK := 0.014
const ELEC_DOOR_TUBE_TRIM := ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN - 0.0012
const ELEC_DOOR_BEND_R := 0.0035
const ELEC_FLEX_APPROACH := 0.014
## Нахлёст изоляции внутрь гофры (убирает визуальный обрыв у торцов).
const ELEC_FLEX_WIRE_OVERLAP := 0.048
## Доп. точки вдоль оси гофры — жила «заходит» в ребристый рукав.
const ELEC_FLEX_ENTER_STEPS := 6
const ELEC_FLEX_ENTER_STEP := 0.014
## ПКМ: клик (свойства) vs drag (орбита/look).
var _rmb_press := Vector2.ZERO
var _rmb_moved := false
var _rmb_pending := false

signal request_element_props(el_id: int, screen: Vector2)
## Орган/кнопка в 3D изменили состояние — схема должна перерисовать УГО.
signal sim_control_changed
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
	fill.shadow_enabled = false
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
	# Щит всегда в цехе — не ждём появления электроэлементов.
	IsoCabinet.ensure(_machines, null)
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
		# Конус: остриё по +Y меша → ориентируем +Y по направлению потока.
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.0055
		mesh.height = 0.016
		mesh.radial_segments = 10
		dot.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		elif _drag == "sleeve_yaw":
			_sleeve_drag_wire_id = -1
			_sleeve_drag_end = ""
			_sleeve_drag_node = null
			_drag = ""
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "actuate":
			_end_actuate()
		elif _drag == "electro_btn":
			var bel = circuit.get_element(_actuate_el_id) if circuit != null else null
			if bel != null and str(bel.kind) == "electro" and not bool(bel.latching):
				bel.pressed = false
				if _module_hit_node != null and is_instance_valid(_module_hit_node):
					IsoElectro.update_state(_module_hit_node, bel)
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
		elif _drag == "timer_dial":
			_drag = ""
			_timer_dial_kind = ""
			_timer_dial_accum = 0.0
			_actuate_el_id = -1
			_module_hit_node = null
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "throttle_screw":
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "regulator_knob":
			var was_click_reg: bool = not _module_moved
			var reg_id: int = _actuate_el_id
			var reg_root: Node3D = _module_hit_node
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			_module_moved = false
			if was_click_reg and circuit != null:
				var rel = circuit.get_element(reg_id)
				if rel != null and str(rel.accessory_class) == "regulator":
					rel.regulator_unlocked = not bool(rel.regulator_unlocked)
					if reg_root != null and is_instance_valid(reg_root):
						IsoRegulator.apply_knob(reg_root, rel)
					circuit.notify(
						"Ручка разблокирована — крутите для уставки" if bool(rel.regulator_unlocked)
						else "Ручка заблокирована"
					)
					circuit.touch_scene()
			elif circuit != null:
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
						var ray_up: Dictionary = _ray(event.position)
						_click_electro_3d(
							mel, hit_pt, hit_node,
							ray_up.get("origin", Vector3.ZERO) as Vector3,
							ray_up.get("dir", Vector3.FORWARD) as Vector3
						)
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


## Сброс кэша трубок (после load сцены / смены якорей гофры).
func clear_hose_geom_cache() -> void:
	_door_flex_sig = ""
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid] as Node3D
		if node != null and is_instance_valid(node):
			node.remove_meta("geom_sig")
			node.remove_meta("door_span")
			node.remove_meta("curve_pts_cab")
			node.remove_meta("curve_pts_cab_duct")


## После анимации дверцы: сбросить sig дверных пролётов — иначе останется
## старый curve_pts_cab (жила торчит из гофры).
func _invalidate_door_span_hose_cache() -> void:
	_door_flex_sig = ""
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not bool(node.get_meta("door_span", false)):
			continue
		node.remove_meta("geom_sig")
		node.remove_meta("curve_pts_cab")
		node.remove_meta("curve_pts_cab_duct")


## Ревью щита: пролёт на гофру/петлю (WASD сразу работает).
func aim_review_cabinet() -> void:
	cam_mode = "fly"
	xray = false
	clear_hose_geom_cache()
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var look: Vector3 = _target
	if cab != null:
		IsoCabinet.apply_xray(cab, false)
		var anchors: Dictionary = IsoCabinet.harness_anchors_world(cab)
		if not anchors.is_empty():
			var a: Vector3 = anchors["door_exit"] as Vector3
			var b: Vector3 = anchors["cab_entry"] as Vector3
			look = a.lerp(b, 0.35) + Vector3(0.0, 0.05, 0.0)
		else:
			look = cab.global_position + Vector3(-0.05, 0.40, 0.22)
	_fly_pos = look + Vector3(0.95, 0.35, 0.85)
	_target = look
	_aim_fly_at_target()
	_clamp_fly_pos()
	_place_camera()


## Ревью произвольной точки (дроссель и т.п.).
func aim_review_point(look: Vector3, fly_pos: Vector3) -> void:
	cam_mode = "fly"
	xray = true
	_target = look
	_fly_pos = fly_pos
	_aim_fly_at_target()
	_clamp_fly_pos()
	_place_camera()
	set_xray(true)


func _drag_locks_hover() -> bool:
	return _drag in ["timer_dial", "throttle_screw", "regulator_knob", "din_module", "door_module", "actuate", "electro_btn", "gizmo", "wire_port", "sleeve_yaw"]


## ПКМ-орбита / look / middle-pan — не гонять hover/overlay каждый кадр.
func is_camera_navigating() -> bool:
	return _drag in ["orbit", "look", "pan"]


func _bind_ext_hover() -> void:
	if _ext_hover_bound or circuit == null:
		return
	if circuit.has_signal("hover_port_changed"):
		circuit.hover_port_changed.connect(_on_circuit_hover_port_changed)
		_ext_hover_bound = true


func _on_circuit_hover_port_changed() -> void:
	if circuit == null:
		return
	if str(circuit.hover_space) == "schematic":
		_apply_schematic_hover_hl()
		return
	# Сброс наведения со схемы (пустое место) — иначе 3D-подсветка остаётся.
	if str(circuit.hover_space) == "":
		clear_hover_highlight()


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
	# Поворот/пан камеры: не пересчитывать подсветку (иначе фризы на каждом motion).
	if is_camera_navigating():
		return ""
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
				if str(eel.electro_class) in ["mcb", "rcd", "rcbo"] and mnode != null:
					var ctrl_hit: Dictionary = IsoElectro.pick_breaker_ctrl(mnode, origin, dir)
					var ctrl: String = str(ctrl_hit.get("ctrl", ""))
					if ctrl == "lever":
						var lnode: Node3D = ctrl_hit.get("node", null) as Node3D
						_show_hover_hl_node(lnode if lnode != null else mnode)
						circuit.set_hover("workshop", eid, "", -1)
						var st_av: String = "включен" if bool(eel.closed) else "отключен"
						return "%s · рычаг (%s)" % [str(eel.tag), st_av]
					if ctrl == "test":
						var tnode: Node3D = ctrl_hit.get("node", null) as Node3D
						_show_hover_hl_node(tnode if tnode != null else mnode)
						circuit.set_hover("workshop", eid, "", -1)
						return "%s · кнопка контроля" % str(eel.tag)
				_show_hover_hl_node(mnode)
				circuit.set_hover("workshop", eid, "", -1)
				return circuit.element_sim_tip(eid) if circuit != null else str(eel.tag)
	# Винт дросселя — как рычаг автомата: подсветка самой детали, не всего корпуса.
	var thr_hit: Dictionary = _pick_throttle_screw(origin, dir)
	if not thr_hit.is_empty():
		var tid: int = int(thr_hit.get("id", -1))
		var troot: Node3D = thr_hit.get("root", null) as Node3D
		var screw: Node3D = troot.get_node_or_null("ThrottleScrew") as Node3D if troot != null else null
		_show_hover_hl_node(screw if screw != null else troot)
		var tel = circuit.get_element(tid)
		circuit.set_hover("workshop", tid, "", -1)
		if tel != null and circuit != null:
			var body_tip: String = circuit.element_sim_tip(tid)
			return "%s\nОрган: винт настройки" % body_tip
		return "Дроссель · винт настройки"
	var reg_hit: Dictionary = _pick_regulator_knob(origin, dir)
	if not reg_hit.is_empty():
		var rid: int = int(reg_hit.get("id", -1))
		var rroot: Node3D = reg_hit.get("root", null) as Node3D
		var knob: Node3D = rroot.get_node_or_null("RegulatorKnob") as Node3D if rroot != null else null
		_show_hover_hl_node(knob if knob != null else rroot)
		var rel = circuit.get_element(rid)
		circuit.set_hover("workshop", rid, "", -1)
		if rel != null and circuit != null:
			var lock_s: String = "разблокирована" if bool(rel.regulator_unlocked) else "заблокирована"
			return "%s\nОрган: ручка уставки (%s)" % [circuit.element_sim_tip(rid), lock_s]
		return "Редуктор · ручка уставки"
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
			return circuit.element_sim_tip(mid) if circuit != null else str(mel.tag)
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
	if w != null and circuit != null:
		# Тот же реквизит, что 2D-тултип: 1:KL1:A1 | 1:KL2:14
		tip = circuit.wire_hover_tip(w)
		if tip == "":
			tip = "Линия"
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
	_hide_hover_hl_meshes()


func _hide_hover_hl_meshes() -> void:
	_clear_hover_hl_overlays()
	if _hover_hl_mesh_root != null:
		_hover_hl_mesh_root.visible = false


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
	_hover_hl_mat.albedo_color = Color(UiTheme.ACCENT_CYAN, 0.50)
	_hover_hl_mat.emission_enabled = true
	_hover_hl_mat.emission = UiTheme.ACCENT_CYAN
	_hover_hl_mat.emission_energy_multiplier = 0.70
	_hover_hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_hl.material_override = _hover_hl_mat
	_hover_hl.visible = false
	_hover_hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hover_hl)
	_hover_hl_mesh_root = Node3D.new()
	_hover_hl_mesh_root.name = "HoverHighlightMeshes"
	_hover_hl_mesh_root.visible = false
	add_child(_hover_hl_mesh_root)
	_hover_hl_grow_mat = _make_hover_hl_grow_mat()


func _make_hover_hl_grow_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh: Shader = load("res://shaders/hover_mesh_grow.gdshader") as Shader
	if sh == null:
		sh = Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, specular_disabled, shadows_disabled;
uniform vec4 glow_color : source_color = vec4(0.0, 0.745, 0.953, 1.0);
uniform float fill = 0.18;
uniform float rim_pow = 2.2;
uniform float rim_strength = 0.95;
void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_pow);
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * (0.4 + rim * 0.7);
	ALPHA = clamp(fill + rim * rim_strength, 0.0, 0.92);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("glow_color", UiTheme.ACCENT_CYAN)
	mat.set_shader_parameter("fill", 0.18)
	mat.set_shader_parameter("rim_pow", 2.2)
	mat.set_shader_parameter("rim_strength", 0.95)
	return mat


func _hover_hl_part_material() -> Material:
	_ensure_hover_hl()
	return _hover_hl_grow_mat if _hover_hl_grow_mat != null else _hover_hl_mat


func _show_hover_hl_sphere(world_pos: Vector3, radius: float) -> void:
	_ensure_hover_hl()
	_hide_hover_hl_meshes()
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
	_hide_hover_hl_meshes()
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
	var sid: int = node.get_instance_id()
	if sid != _hover_hl_src_id or _hover_hl_src_pairs.is_empty():
		_rebuild_hover_hl_meshes(node)
	if _hover_hl_src_pairs.is_empty():
		_show_hover_hl_sphere(node.global_position, 0.035)
		return
	_hover_hl.visible = false
	if _hover_hl_mesh_root != null:
		_hover_hl_mesh_root.visible = false


func _clear_hover_hl_overlays() -> void:
	for pair_v in _hover_hl_src_pairs:
		if typeof(pair_v) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_v
		# Нельзя `as MeshInstance3D` на freed — сначала is_instance_valid на Variant.
		var src_v = pair.get("src", null)
		if src_v == null or not is_instance_valid(src_v):
			continue
		if not (src_v is MeshInstance3D):
			continue
		var src: MeshInstance3D = src_v
		var prev_v = pair.get("prev", null)
		if prev_v != null and not is_instance_valid(prev_v):
			prev_v = null
		src.material_overlay = prev_v as Material
	_hover_hl_src_pairs.clear()
	_hover_hl_src_id = 0


func _rebuild_hover_hl_meshes(node: Node3D) -> void:
	_ensure_hover_hl()
	_clear_hover_hl_overlays()
	if _hover_hl_mesh_root != null:
		for ch in _hover_hl_mesh_root.get_children():
			_hover_hl_mesh_root.remove_child(ch)
			ch.free()
	_hover_hl_src_id = node.get_instance_id() if node != null else 0
	if node == null:
		return
	var mat: Material = _hover_hl_part_material()
	var sources: Array = _collect_hover_hl_meshes(node)
	for src_v in sources:
		if src_v == null or not is_instance_valid(src_v) or not (src_v is MeshInstance3D):
			continue
		var src: MeshInstance3D = src_v
		if src.mesh == null:
			continue
		var prev: Material = src.material_overlay
		src.material_overlay = mat
		_hover_hl_src_pairs.append({"src": src, "prev": prev})


const HOVER_HL_MAX_MESHES := 10


func _collect_hover_hl_meshes(root: Node3D) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label3D:
			continue
		var nm: String = str(n.name)
		if nm == "SchematicGlow" or nm.begins_with("HoverHighlight"):
			continue
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh != null and mi.visible and not bool(mi.get_meta("hover_hl_skip", false)):
				out.append(mi)
		for ch in n.get_children():
			stack.append(ch)
	# Много мелких деталей (автомат) → overlay на всех даёт фриз; берём крупнейшие.
	if out.size() <= HOVER_HL_MAX_MESHES:
		return out
	var scored: Array = []
	for mi_v in out:
		var mi2: MeshInstance3D = mi_v as MeshInstance3D
		var aabb: AABB = mi2.get_aabb()
		var vol: float = maxf(aabb.size.x, 0.0001) * maxf(aabb.size.y, 0.0001) * maxf(aabb.size.z, 0.0001)
		scored.append({"mi": mi2, "vol": vol})
	scored.sort_custom(func(a, b): return float(a["vol"]) > float(b["vol"]))
	var capped: Array = []
	for i in mini(scored.size(), HOVER_HL_MAX_MESHES):
		capped.append(scored[i]["mi"])
	return capped


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
	# Тот же полный текст, что на 2D-схеме.
	var tip: String = circuit.port_sim_tip(int(best_el.id), best_port) if circuit != null else (
		"%s:%s" % [best_tag, best_port]
	)
	if tip == "":
		tip = "%s:%s" % [best_tag, best_port]
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
	var frame_n: int = Engine.get_process_frames()
	var cyl_moving: bool = circuit.running and _any_cylinder_moving()
	var hoses_ready: bool = _hoses_are_ready()
	# При Run: полный 3D-sync не каждый кадр — но не пропускать, пока трубки/модели не готовы.
	if circuit.running and (frame_n % 2) != 0 and not cyl_moving \
			and hoses_ready and _build_queue.is_empty():
		return
	var t0: int = Time.get_ticks_usec() if _perf_hud else 0
	# В симуляции — лёгкий апдейт поз/штока; полный сиг — только в редактировании.
	_sync_machines(circuit.running)
	if _perf_hud:
		_perf_ms_machines = float(Time.get_ticks_usec() - t0) * 0.001
		t0 = Time.get_ticks_usec()
	# Щит: при Run не каждый кадр (DIN/дверца не двигаются от пневмо-шага).
	if not circuit.running or (frame_n % 8) == 0 \
			or _machines.get_node_or_null(IsoCabinet.CABINET_NAME) == null:
		IsoCabinet.ensure(_machines, circuit)
	# Трубки: при Run реже, но пока mesh нет — каждый кадр.
	var need_hoses: bool = true
	if circuit.running:
		if not hoses_ready or not _build_queue.is_empty():
			need_hoses = true
		elif cyl_moving:
			need_hoses = (frame_n % 3) == 0
		elif bool(circuit.pressure_viz):
			need_hoses = (frame_n % 6) == 0
		else:
			# Редкий refresh (порты/посадка моделей после chunked build).
			need_hoses = (frame_n % 20) == 0
	if need_hoses:
		_sync_hoses()
		hoses_ready = _hoses_are_ready()
	if _perf_hud:
		_perf_ms_hoses = float(Time.get_ticks_usec() - t0) * 0.001
	if circuit.running or circuit.sim_time > 0.0:
		if bool(circuit.pressure_viz) and (not circuit.running or (frame_n % 2) == 0):
			_sync_flows()
		elif not bool(circuit.pressure_viz):
			for puff in _flow_pool:
				puff.visible = false
	else:
		for puff in _flow_pool:
			puff.visible = false
	if not circuit.running or (frame_n % 2) == 0:
		_sync_gizmo()


func _any_cylinder_moving() -> bool:
	if circuit == null:
		return false
	for el in circuit.elements:
		if el != null and str(el.kind) == "cylinder" and absf(float(el.v)) > 1.0e-4:
			return true
	return false


func _hoses_are_ready() -> bool:
	## Есть mesh у всех пневмо/электро проводов (после load/chunked build).
	if circuit == null or circuit.wires.is_empty():
		return true
	if _hose_nodes.size() < circuit.wires.size():
		return false
	for wire in circuit.wires:
		if wire == null:
			continue
		var node: Node3D = _hose_nodes.get(wire.id, null)
		if node == null or not is_instance_valid(node):
			return false
		if str(node.get_meta("geom_sig", "")) == "":
			return false
		var tube: MeshInstance3D = node.get_node_or_null("Tube") as MeshInstance3D
		if tube == null or tube.mesh == null:
			return false
	return true


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
	if not sim_light:
		_coil_sig_refresh()
	var pviz_max: float = _pressure_viz_max_cached()
	# Пакетная сборка после load: не больше _build_budget новых Iso*.build за кадр.
	var builds_left: int = _build_budget if not _build_queue.is_empty() else 999999
	for el in circuit.elements:
		if el.kind == "coil":
			# Катушка не отдельная машина — надевается на трубку ЭМ распреда по метке.
			continue
		if el.kind == "electro":
			# DIN/дверца — в общем щите; катушка ЭМ — на трубке ПР; контакты группы — только 2D.
			continue
		if el.kind == "rail":
			# Шина УГО — только схема 2D.
			continue
		alive[el.id] = true
		var rec = _records.get(el.id, null)
		# При Run: без гигантской sig-строки — только анимация существующих моделей.
		if sim_light and rec != null:
			# Цилиндры — каждый кадр (шток); остальное — раз в 3 кадра.
			if str(el.kind) != "cylinder" and (frame % 3) != 0:
				continue
			_sync_machine_runtime(el, rec["root"] as Node3D, frame, pviz_max)
			continue
		# Сигнатуру геометрии — только в редактировании / при отсутствии модели.
		var spool_sig := ",".join(PackedStringArray(el.spool_envelopes)) if el.get("spool_envelopes") != null else ""
		var junc_sig := "%s:%d:v3" % [
			str(el.get("junction_style") if el.get("junction_style") != null else ""),
			int(el.get("junction_ports") if el.get("junction_ports") != null else 0),
		]
		var acc_sig := str(el.get("accessory_class") if el.get("accessory_class") != null else "")
		# v2: check — входной канал до седла в CSG; reservoir — баллон CRVZS.
		if acc_sig == "check":
			acc_sig = "check:v2"
		elif acc_sig == "reservoir":
			acc_sig = "reservoir:v2:%.2f:%d" % [float(el.volume_l), int(el.reservoir_ports)]
		var fit_sig: String = "%s:%.1f" % [
			str(el.fitting_id) if el.get("fitting_id") != null else "",
			float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0,
		]
		var sig := "%s|%s|%.3f|%.3f|%.3f|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%.2f|%s|%.2f|%.2f|%d|%d|%s|%s|%s|%s|%s|%.2f|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
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
			spool_sig, junc_sig, acc_sig, fit_sig,
		]
		# Посадка один раз: auto_ground или старые сцены у пола. Не пересчитывать
		# AABB каждый кадр — подвижный винт/шток иначе «подбрасывает» элемент.
		var reseat: bool = bool(el.auto_ground) or float(el.world_pos.y) < WORK_Y * 0.55
		var need_build: bool = rec == null or str(rec.get("sig", "")) != sig
		if not need_build:
			# Уже собрано — убрать из очереди пакетной загрузки (иначе budget залипает).
			_build_queue.erase(el.id)
		else:
			if builds_left <= 0:
				# Отложить на следующий кадр — UI остаётся отзывчивым.
				if not _build_queue.has(el.id):
					_build_queue.append(el.id)
				continue
			builds_left -= 1
			_build_queue.erase(el.id)
			if rec != null:
				rec["root"].queue_free()
				if rec.get("shadow") != null and is_instance_valid(rec["shadow"]):
					rec["shadow"].queue_free()
			var built := Node3D.new()
			_machines.add_child(built)
			var info: Dictionary
			if el.kind == "valve":
				info = IsoValve.build(built, el, circuit)
			elif el.kind == "junction":
				info = IsoJunction.build(built, el)
			elif el.kind == "accessory":
				info = _build_accessory_3d(built, el)
			else:
				info = Iso.build(built, el)
			built.set_meta("ports", info["ports"])
			built.set_meta("dirs", info["dirs"])
			if xray:
				Iso.apply_xray(built, true)
			rec = {"root": built, "sig": sig, "shadow": null}
			_records[el.id] = rec
			if reseat:
				var box: AABB = _seat_aabb(built)
				if box.size.length() > 0.0001:
					el.world_pos.y = -box.position.y + WORK_Y
				else:
					el.world_pos.y = WORK_Y
				rec["seat_y"] = el.world_pos.y
				el.auto_ground = false
		if rec == null:
			continue
		_sync_machine_runtime(el, rec["root"] as Node3D, frame, pviz_max, false)
	var stale: Array = []
	for id in _records.keys():
		if not alive.has(id):
			stale.append(id)
	for id in stale:
		_records[id]["root"].queue_free()
		if _records[id].get("shadow") != null and is_instance_valid(_records[id]["shadow"]):
			_records[id]["shadow"].queue_free()
		_records.erase(id)


## Позы/шток/золотник/opening — без пересборки sig (и в Run, и после edit-sync).
func _sync_machine_runtime(el, root: Node3D, frame: int, pviz_max: float, sim_light: bool = true) -> void:
	if root == null or el == null:
		return
	# Ориентацию тройника в Run не трогаем каждый кадр — уже выставлена при сборке/edit.
	if not sim_light and el.kind == "junction":
		_orient_junction_3d(el)
	root.position = el.world_pos
	root.basis = el.world_basis
	if not sim_light:
		var tag := root.get_node_or_null("Tag")
		if tag and str(tag.text) != str(el.tag):
			tag.text = el.tag
	if el.kind == "valve":
		var vpos: int = int(el.valve_pos)
		var vcmd: String = "%s|%s|%d" % [str(el.command_left), str(el.command_right), vpos]
		if (not sim_light) or str(root.get_meta("rt_valve", "")) != vcmd or (xray and (frame % 4) == 0):
			var do_viz: bool = xray and (frame % 4) == 0
			IsoValve.update_spool(root, el, do_viz)
			_sync_actuators_from_commands(el, root)
			root.set_meta("rt_valve", vcmd)
	if el.kind == "accessory" and str(el.accessory_class) in ["throttle", "throttle_fixed", "check", "regulator"]:
		var open_sig: String = "%.3f|%.2f" % [float(el.opening), float(el.set_pressure_bar)]
		if (not sim_light) or str(root.get_meta("rt_open", "")) != open_sig:
			if str(el.accessory_class) == "throttle":
				IsoThrottle.apply_opening(root, el)
			elif str(el.accessory_class) == "check":
				IsoCheck.apply_opening(root, el)
			elif str(el.accessory_class) == "regulator":
				IsoRegulator.apply_knob(root, el)
			root.set_meta("rt_open", open_sig)
		if xray and str(el.accessory_class) != "regulator":
			var xray_pending: bool = not bool(root.get_meta("xray_ok", false))
			if not xray_pending:
				for ch in root.get_children():
					if ch is CSGCombiner3D or str(ch.name).begins_with("CSG_"):
						xray_pending = true
						break
			if xray_pending and (frame % 6) == 0:
				Iso.apply_xray(root, true)
				var still_csg: bool = false
				for ch2 in root.get_children():
					if ch2 is CSGCombiner3D or str(ch2.name).begins_with("CSG_"):
						still_csg = true
						break
				if not still_csg:
					root.set_meta("xray_ok", true)
	var rod := root.get_node_or_null("Rod")
	if rod:
		rod.position.x = el.x
	if el.kind == "cylinder" and str(el.get("spring_side") if el.get("spring_side") != null else "none") != "none":
		if (not sim_light) or (frame % 2) == 0:
			Iso.update_spring(root, el)
			if xray:
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
	# Pressure viz — реже при Run.
	var pviz_every: int = 4 if sim_light else 2
	if (frame % pviz_every) == 0 and str(el.kind) in ["source", "junction", "accessory", "cylinder", "valve"]:
		_apply_pressure_viz_root(root, el, bool(circuit.pressure_viz), pviz_max)


## Режим «ДАВЛЕНИЕ»: все корпуса → светло-серый, tint по давлению элемента.
func _apply_pressure_viz_root(root: Node3D, el, on: bool, p_max_over: float = -1.0) -> void:
	if root == null or el == null:
		return
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var base_gray := Color(0.82, 0.83, 0.84)
	var tint: Color = base_gray
	if on:
		var pmax: float = p_max_over if p_max_over >= 0.0 else _pressure_viz_max_cached()
		tint = SimV.pressure_color(
			circuit.element_viz_pressure(el), base_gray, pmax
		)
	# Пропуск DFS, если tint/режим не изменились.
	if root.has_meta("pviz_last_on") and root.has_meta("pviz_last_tint"):
		if bool(root.get_meta("pviz_last_on")) == on \
				and (root.get_meta("pviz_last_tint") as Color).is_equal_approx(tint):
			return
	root.set_meta("pviz_last_on", on)
	root.set_meta("pviz_last_tint", tint)
	_apply_pressure_viz_node(root, on, tint)


func _apply_pressure_viz_node(node: Node, on: bool, tint: Color) -> void:
	if node is GeometryInstance3D and (node is MeshInstance3D or node is CSGShape3D):
		var gi := node as GeometryInstance3D
		# В т.ч. control (винт дросселя, рёбра рукоятки КР) — красим вместе с корпусом.
		if gi.material_override is StandardMaterial3D or gi.has_meta("pviz_base_mat"):
			if not gi.has_meta("pviz_base_mat") and gi.material_override is StandardMaterial3D:
				gi.set_meta("pviz_base_mat", gi.material_override)
			if on and gi.has_meta("pviz_base_mat"):
				var base_m: StandardMaterial3D = gi.get_meta("pviz_base_mat") as StandardMaterial3D
				var painted: StandardMaterial3D = null
				if gi.has_meta("pviz_painted"):
					painted = gi.get_meta("pviz_painted") as StandardMaterial3D
				else:
					painted = base_m.duplicate() as StandardMaterial3D
					gi.set_meta("pviz_painted", painted)
				painted.albedo_color = Color(tint.r, tint.g, tint.b, base_m.albedo_color.a)
				# Без сильного metal — иначе «хром» глушит синий.
				painted.metallic = minf(float(base_m.metallic), 0.25)
				gi.material_override = painted
			elif not on and gi.has_meta("pviz_base_mat"):
				gi.material_override = gi.get_meta("pviz_base_mat")
	for ch in node.get_children():
		_apply_pressure_viz_node(ch, on, tint)


func _build_accessory_3d(parent: Node3D, el) -> Dictionary:
	var cls := str(el.accessory_class)
	if cls in ["throttle", "throttle_fixed"]:
		return IsoThrottle.build(parent, el)
	if cls == "check":
		return IsoCheck.build(parent, el)
	if cls == "reservoir":
		return IsoReservoir.build(parent, el)
	if cls == "regulator":
		return IsoRegulator.build(parent, el)
	# Прокси 3D до отдельных моделей остальных аксессуаров.
	var info := {"ports": {}, "dirs": {}}
	var size := Vector3(Parts.mm(36.0), Parts.mm(28.0), Parts.mm(28.0))
	if cls == "frl":
		size = Vector3(Parts.mm(55.0), Parts.mm(40.0), Parts.mm(40.0))
	Parts.box(parent, size, Vector3.ZERO, Parts.mat("acc_body", Color(0.78, 0.82, 0.86), 0.15, 0.55), "shell")
	var tip1 := Vector3(-size.x * 0.5 - Parts.mm(6.0), 0.0, 0.0)
	var tip2 := Vector3(size.x * 0.5 + Parts.mm(6.0), 0.0, 0.0)
	info["ports"]["1"] = tip1
	info["ports"]["2"] = tip2
	info["dirs"]["1"] = Vector3.LEFT
	info["dirs"]["2"] = Vector3.RIGHT
	if cls == "frl":
		parent.set_meta("relief_local", Vector3(0.0, -size.y * 0.5 - Parts.mm(2.0), 0.0))
		parent.set_meta("relief_dir", Vector3.DOWN)
	var label := Label3D.new()
	label.name = "Tag"
	label.text = str(el.tag)
	label.font_size = 18
	label.pixel_size = 0.00028
	label.modulate = Color(0.15, 0.17, 0.2)
	label.position = Vector3(0, size.y * 0.5 + Parts.mm(8.0), 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visible = false
	parent.add_child(label)
	return info


func _orient_junction_3d(el) -> void:
	# 3D yaw = rotation_quad схемы (те же порты 1/2/3, что на УГО).
	# Ручной поворот гизмо в цехе — user_rotated, не трогаем.
	var rec = _records.get(el.id, null)
	if rec != null and bool(rec.get("user_rotated", false)):
		return
	var yaw: float = float(el.rotation_quad) * PI * 0.5
	el.world_basis = Basis(Vector3.UP, -yaw)
	if rec != null:
		rec["junc_auto"] = true


func _coil_sig_refresh() -> void:
	## Один проход по elements на кадр — иначе O(E²) из sig каждого valve.
	var fr: int = Engine.get_process_frames()
	if fr == _coil_sig_frame:
		return
	_coil_sig_frame = fr
	var parts: PackedStringArray = []
	if circuit == null:
		_coil_sig_cached = ""
		return
	for other in circuit.elements:
		var k := str(other.kind)
		if k == "coil" or (k == "electro" and str(other.electro_class) == "solenoid_coil"):
			parts.append(str(other.tag))
	parts.sort()
	_coil_sig_cached = ",".join(parts)


func _coil_sig_for(el) -> String:
	if el.kind != "valve" or circuit == null:
		return ""
	_coil_sig_refresh()
	return _coil_sig_cached


func _pressure_viz_max_cached() -> float:
	var fr: int = Engine.get_process_frames()
	if fr != _pviz_max_frame:
		_pviz_max_frame = fr
		if circuit != null and bool(circuit.pressure_viz):
			_pviz_max_pa = circuit.viz_max_over_pa()
		else:
			_pviz_max_pa = 0.0
	return _pviz_max_pa


func _scene_has_elec_wires() -> bool:
	var fr: int = Engine.get_process_frames()
	if fr == _has_elec_wires_frame:
		return _has_elec_wires_cached
	_has_elec_wires_frame = fr
	_has_elec_wires_cached = false
	if circuit == null:
		return false
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		if ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric":
			_has_elec_wires_cached = true
			break
		var eb = circuit.get_element(int(wire.b_id))
		if eb != null and Geom.port_domain(eb, str(wire.b_port)) == "electric":
			_has_elec_wires_cached = true
			break
	return _has_elec_wires_cached


func begin_chunked_build(budget: int = 4) -> void:
	## После load_scene: собирать Iso*.build пакетами, не блокируя UI.
	_build_budget = maxi(budget, 1)
	_build_queue.clear()
	# Старые трубки сбросить — пересоберём, когда появятся порты машин.
	for id in _hose_nodes.keys():
		if is_instance_valid(_hose_nodes[id]):
			_hose_nodes[id].queue_free()
	_hose_nodes.clear()
	if circuit == null:
		return
	for el in circuit.elements:
		if el.kind in ["coil", "electro", "rail"]:
			continue
		_build_queue.append(el.id)


func set_perf_hud(on: bool) -> void:
	_perf_hud = on


func perf_ms_summary() -> String:
	return "3D machines %.1f ms · hoses %.1f ms" % [_perf_ms_machines, _perf_ms_hoses]


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
	# Gizmo / DIN / дверца: лёгкий режим — только линии к тащимому элементу, без HQ.
	var drag_lite: bool = _drag in ["din_module", "door_module", "gizmo"]
	var drag_el: int = _actuate_el_id if drag_lite and _drag != "gizmo" else -1
	var drag_ids: Dictionary = {}
	if drag_lite and _drag == "gizmo" and circuit != null:
		for sid in circuit.selected_ids:
			drag_ids[int(sid)] = true
	elif drag_lite and drag_el >= 0:
		drag_ids[drag_el] = true
	var cab_now := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_lite: bool = cab_now != null and IsoCabinet.is_door_animating(cab_now)
	# Конец анимации дверцы: принудительный HQ — иначе geom_sig уже «новый», а cab-жила старая.
	if _door_was_animating and not door_lite:
		_invalidate_door_span_hose_cache()
	_door_was_animating = door_lite
	# Во время drag — только провода к модулю; полный HQ после отпускания.
	var want_hq: bool = (not drag_lite) or _hose_hq_pending
	if want_hq and not drag_lite:
		_hose_hq_pending = false
	# Кэш КК один раз на кадр (не на каждый провод).
	_hose_ducts_cached()
	var has_elec: bool = _scene_has_elec_wires()
	if has_elec and not door_lite and not drag_lite:
		_elec_rebuild_separation()
	var pviz_max_hose: float = _pressure_viz_max_cached()
	var door_bundle: Array = []
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		var elec_a: bool = ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric"
		var elec_b: bool = eb != null and Geom.port_domain(eb, str(wire.b_port)) == "electric"
		var is_elec: bool = elec_a or elec_b
		# Бандл гофры — по составу схемы, не по удачности _port_world в этом кадре
		# (иначе при клике на УГО гофра на кадр гаснет).
		if is_elec and _wire_is_door_cabinet_span(wire):
			door_bundle.append(wire)
		alive[wire.id] = true
		var node: Node3D = _hose_nodes.get(wire.id, null)
		if node == null:
			node = _make_hose_node()
			_hoses.add_child(node)
			_hose_nodes[wire.id] = node
		# Drag: чужие провода не трогаем (порты не двигались).
		if drag_lite and not drag_ids.is_empty():
			var touch: bool = false
			for eid in drag_ids.keys():
				if _wire_touches_drag_el(wire, int(eid)):
					touch = true
					break
			if not touch:
				continue
		# При Run: трубки без движущегося штока — не трогать mesh (только цвет давления).
		# Если geom ещё не собран — не continue: иначе трубки так и не появятся.
		if circuit.running and not is_elec and not drag_lite:
			var has_geom: bool = str(node.get_meta("geom_sig", "")) != ""
			var tube_mi: MeshInstance3D = node.get_node_or_null("Tube") as MeshInstance3D
			var has_mesh: bool = tube_mi != null and tube_mi.mesh != null
			if has_geom and has_mesh:
				var touch_moving: bool = false
				for end_el in [ea, eb]:
					if end_el == null or str(end_el.kind) != "cylinder":
						continue
					# Только скорость: положение x≠0 само по себе путь не меняет каждый кадр.
					if absf(float(end_el.v)) > 1.0e-4:
						touch_moving = true
						break
				if not touch_moving:
					if bool(circuit.pressure_viz) and node.has_meta("mat"):
						var mat_s: StandardMaterial3D = node.get_meta("mat") as StandardMaterial3D
						if mat_s != null and str(wire.color_id) == "":
							var base_s := Color(0.82, 0.83, 0.84)
							mat_s.albedo_color = SimVis.pressure_color(
								circuit.wire_viz_pressure(wire), base_s, pviz_max_hose
							)
					continue
		var a = _port_world(wire.a_id, wire.a_port)
		var b = _port_world(wire.b_id, wire.b_port)
		if a == null or b == null:
			node.visible = false
			_sync_hose_sleeves(node, PackedVector3Array(), 0.0, 0, false)
			continue
		node.visible = true
		_ensure_hose_sleeves(node)
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
			# Сечение мм² → реальный наружный Ø ПВХ (см. Circuit.wire_od_mm).
			var od_mm: float = Circuit.wire_od_mm(float(wire.id_mm))
			radius = clampf(od_mm * 0.0005, 0.0009, 0.0045)
			# Чуть внутрь зева (не к винту): порты уже на кромке отверстия.
			var inset: float = 0.0009
			a = a - da.normalized() * inset
			b = b - db.normalized() * inset
			# Два провода в клемме → параллельный заход в сдвоенный НШВИ.
			a = a + _nshvi_pair_end_offset(wire, true, od_mm)
			b = b + _nshvi_pair_end_offset(wire, false, od_mm)
		else:
			_clear_pe_hose_material(mat)
			if color_id != "":
				mat.albedo_color = Circuit.line_color_from_id(color_id)
			elif bool(circuit.pressure_viz):
				var SimV = preload("res://scripts/domain/sim_vis.gd")
				var base_hose := Color(0.82, 0.83, 0.84)
				mat.albedo_color = SimV.pressure_color(
					circuit.wire_viz_pressure(wire), base_hose, pviz_max_hose
				)
			else:
				mat.albedo_color = UiTheme.BRAND_BLUE.lightened(0.05)
			# Наружный Ø трубки (каталог); fallback — старый id_mm как OD.
			var od_hose: float = float(wire.od_mm) if float(wire.od_mm) >= 1.0 else float(wire.id_mm)
			radius = clampf(od_hose * 0.0005, 0.0016, 0.0085)
			# Пневмотрубка чуть внутрь цанги; на толстых не загонять глубоко — ломает кадр у порта.
			var pinset: float = clampf(radius * 0.55, 0.0012, 0.0032)
			a = a - da.normalized() * pinset
			b = b - db.normalized() * pinset
		var lane: int = _elec_wire_lane(wire) if is_elec else 0
		var qtag: String = "L" if drag_lite else "H"
		var nshvi_flags: int = 0
		if is_elec:
			if _end_wants_nshvi(int(wire.a_id), str(wire.a_port)):
				nshvi_flags |= 1
			if _end_wants_nshvi(int(wire.b_id), str(wire.b_port)):
				nshvi_flags |= 2
		var flex_sig: String = ""
		if is_elec and cab_now != null:
			var anch_sig: Dictionary = IsoCabinet.harness_anchors_world(cab_now)
			if not anch_sig.is_empty():
				var fe: Vector3 = anch_sig["door_exit"] as Vector3
				var fc: Vector3 = anch_sig["cab_entry"] as Vector3
				# Крупнее квант — иначе микродрожь якорей пересобирает жилы+гофру каждый клик.
				flex_sig = "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f" % [fe.x, fe.y, fe.z, fc.x, fc.y, fc.z]
		var sig := "%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.5f|%d|%d|%s|route45bezier|%d|%s|%d|%s" % [
			a.x, a.y, a.z, b.x, b.y, b.z, da.x, da.y, da.z, db.x, db.y, db.z, radius, 1 if is_elec else 0, 1 if pe else 0, color_id, lane, qtag, nshvi_flags, flex_sig,
		]
		var door_span: bool = is_elec and _wire_is_door_cabinet_span(wire)
		var door_local: bool = is_elec and (not door_span) and _wire_is_door_local(wire)
		var geom_changed: bool = str(node.get_meta("geom_sig", "")) != sig
		# При Run без смены геометрии — только цвет давления (без mesh/рукавов).
		if not geom_changed:
			if not is_elec and bool(circuit.pressure_viz):
				var SimVp = preload("res://scripts/domain/sim_vis.gd")
				var base_h := Color(0.82, 0.83, 0.84)
				mat.albedo_color = SimVp.pressure_color(
					circuit.wire_viz_pressure(wire), base_h, pviz_max_hose
				)
			continue
		if geom_changed:
			var pts: PackedVector3Array
			var pts_ortho := PackedVector3Array()
			var trim_a: float = 0.0
			var trim_b: float = 0.0
			if is_elec:
				if _end_wants_nshvi(int(wire.a_id), str(wire.a_port)):
					trim_a = ELEC_TUBE_TRIM
				if _end_wants_nshvi(int(wire.b_id), str(wire.b_port)):
					trim_b = ELEC_TUBE_TRIM
			if is_elec and door_local:
				# Оба на дверце: перемычка у приборов (не через дверной КК).
				if _end_wants_nshvi(int(wire.a_id), str(wire.a_port)):
					trim_a = ELEC_DOOR_TUBE_TRIM
				if _end_wants_nshvi(int(wire.b_id), str(wire.b_port)):
					trim_b = ELEC_DOOR_TUBE_TRIM
				var dd_loc: Dictionary = IsoCabinet.door_cable_duct_world(cab_now) if cab_now != null else {}
				pts = _hose_door_local_run(a, da, b, db, dd_loc)
				if pts.size() >= 2:
					pts = _hose_clean_elec_path(pts, maxf(radius * 0.7, 0.0006))
					pts_ortho = pts
					pts = _fillet_polyline(pts, ELEC_DOOR_BEND_R, 4 if drag_lite else 6)
					_apply_hose_path(node, pts, radius, trim_a, trim_b)
					_hide_hose_tube_cab(node)
					node.set_meta("geom_sig", sig)
					node.set_meta("curve_pts", pts)
					node.set_meta("door_span", false)
					node.set_meta("curve_pts_ortho", pts_ortho)
			elif is_elec and door_span:
				var a_on_door: bool = _electro_mount_of(int(wire.a_id)) == "door"
				# Дверца: кембрик на подъёме — trim только под НШВИ; кабинет — обычная стопка.
				if a_on_door:
					trim_a = ELEC_DOOR_TUBE_TRIM if _end_wants_nshvi(int(wire.a_id), str(wire.a_port)) else 0.0
					trim_b = ELEC_TUBE_TRIM if _end_wants_nshvi(int(wire.b_id), str(wire.b_port)) else 0.0
				else:
					trim_a = ELEC_TUBE_TRIM if _end_wants_nshvi(int(wire.a_id), str(wire.a_port)) else 0.0
					trim_b = ELEC_DOOR_TUBE_TRIM if _end_wants_nshvi(int(wire.b_id), str(wire.b_port)) else 0.0
				var stub_a: float = _elec_duct_end_stub(wire, true)
				var stub_b: float = _elec_duct_end_stub(wire, false)
				var a1s: Vector3 = a + da.normalized() * stub_a
				var b1s: Vector3 = b + db.normalized() * stub_b
				var ida2: int = _elec_primary_el_id(int(wire.a_id))
				var idb2: int = _elec_primary_el_id(int(wire.b_id))
				var split: Dictionary
				var door_trim_start: float = trim_a if a_on_door else trim_b
				var door_trim_end: float = 0.0
				var cab_trim_start: float = 0.0
				var cab_trim_end: float = trim_b if a_on_door else trim_a
				if door_lite and bool(node.get_meta("door_span", false)) and node.has_meta("curve_pts_cab_duct"):
					# Анимация дверцы: кабинетный КК заморожен, оба захода в гофру — по текущей оси.
					var dd_only: Dictionary = IsoCabinet.door_cable_duct_world(cab_now) if cab_now != null else {}
					var door_port: Vector3 = a if a_on_door else b
					var door_n: Vector3 = da if a_on_door else db
					var pts_door: PackedVector3Array = _hose_door_duct_run(door_port, door_n, dd_only, true, cab_now, lane)
					pts_door = _hose_clean_elec_path(pts_door, maxf(radius * 1.6, 0.0010))
					pts_door = _fillet_polyline(pts_door, clampf(radius * 4.0, 0.0018, 0.006), 4)
					var enter_d_lite: float = 0.10
					var anchors_lite: Dictionary = IsoCabinet.harness_anchors_world(cab_now) if cab_now != null else {}
					var door_flex_lite: PackedVector3Array = _flex_wire_along_centerline(anchors_lite, lane, true, enter_d_lite)
					for p_dfl in door_flex_lite:
						_hose_ortho_push(pts_door, p_dfl)
					var pts_cab_duct: PackedVector3Array = node.get_meta("curve_pts_cab_duct") as PackedVector3Array
					var cab_flex_lite: PackedVector3Array = _flex_wire_along_centerline(anchors_lite, lane, false, enter_d_lite)
					var pts_cab: PackedVector3Array = PackedVector3Array()
					for p_cfl in cab_flex_lite:
						pts_cab.append(p_cfl)
					for p_cd in pts_cab_duct:
						_hose_ortho_push(pts_cab, p_cd)
					_apply_hose_path_split(node, pts_door, pts_cab, radius,
						door_trim_start, door_trim_end, cab_trim_start, cab_trim_end)
					# Не писать финальный sig — иначе после анимации HQ не запустится.
					node.set_meta("geom_sig", str(sig) + "|door_anim")
					node.set_meta("door_span", true)
				else:
					split = _hose_ortho_elec_door_span(a, a1s, da, b, b1s, db, ida2, idb2, lane, a_on_door)
					var pts_d: PackedVector3Array = split.get("door", PackedVector3Array()) as PackedVector3Array
					var pts_c: PackedVector3Array = split.get("cab", PackedVector3Array()) as PackedVector3Array
					# Якоря гофры ещё не готовы — не кэшировать пустой путь (иначе «напрямую» навсегда).
					if pts_d.size() < 2 or pts_c.size() < 2:
						pass
					else:
						# Сначала канал (clean+fillet), затем «укол» вдоль оси гофры — иначе fillet
						# срезает вход и жила визуально не заходит в ребристый рукав.
						var door_flex: PackedVector3Array = split.get("door_flex", PackedVector3Array()) as PackedVector3Array
						var cab_flex: PackedVector3Array = split.get("cab_flex", PackedVector3Array()) as PackedVector3Array
						pts_d = _hose_clean_elec_path(pts_d, maxf(radius * 0.7, 0.0006))
						pts_c = _hose_clean_elec_path(pts_c, maxf(radius * 1.6, 0.0010))
						var bend_door: float = ELEC_DOOR_BEND_R
						var bend_cab: float = clampf(radius * 3.2, 0.0022, 0.008)
						if drag_lite or door_lite:
							pts_d = _fillet_polyline(pts_d, bend_door, 4)
							pts_c = _fillet_polyline(pts_c, bend_cab, 4)
						else:
							pts_d = _fillet_polyline(pts_d, bend_door, 6)
							pts_c = _fillet_polyline(pts_c, bend_cab, 8)
						# Канал щита без гофры — для анимации дверцы.
						node.set_meta("curve_pts_cab_duct", pts_c)
						for p_df in door_flex:
							_hose_ortho_push(pts_d, p_df)
						# cab_flex — от внутри гофры к торцу; вставляем ПЕРЕД кабинным каналом.
						if cab_flex.size() >= 2:
							var merged_c := PackedVector3Array()
							for p_cf in cab_flex:
								merged_c.append(p_cf)
							for p_c in pts_c:
								_hose_ortho_push(merged_c, p_c)
							pts_c = merged_c
						_apply_hose_path_split(node, pts_d, pts_c, radius,
							door_trim_start, door_trim_end, cab_trim_start, cab_trim_end)
						node.set_meta("geom_sig", sig)
						node.set_meta("door_span", true)
						node.set_meta("curve_pts_ortho", pts_d)
						node.set_meta("curve_pts_cab", pts_c)
			elif is_elec:
				pts = _hose_ortho_elec(a, da, b, db, wire, lane)
				# Спайки / развороты / микро-рёбра — до fillet, иначе узлы и перекруты.
				pts = _hose_clean_elec_path(pts, maxf(radius * 1.6, 0.0010))
				pts_ortho = pts
				var min_edge: float = _polyline_min_edge(pts)
				var bend: float = clampf(minf(radius * 5.0, min_edge * 0.35), 0.0018, 0.008)
				if drag_lite:
					pts = _fillet_polyline(pts, bend, 4)
				else:
					pts = _fillet_polyline(pts, bend, 8)
					pts = _hose_clean_elec_path(pts, maxf(radius * 0.4, 0.00025))
				_apply_hose_path(node, pts, radius, trim_a, trim_b)
				_hide_hose_tube_cab(node)
				node.set_meta("geom_sig", sig)
				node.set_meta("curve_pts", pts)
				node.set_meta("door_span", false)
				node.set_meta("curve_pts_ortho", pts_ortho if pts_ortho.size() >= 2 else pts)
			else:
				# Пневмо: кубическая Безье + короткие пеньки по оси цанги (без орто-«коробок»).
				# LOD: при многих трубках / Run — меньше точек кривой (только визуал).
				var wcount: int = circuit.wires.size() if circuit != null else 0
				var curve_n: int
				if drag_lite or (circuit != null and circuit.running):
					curve_n = 22 if circuit != null and circuit.running else 28
				elif wcount > 40:
					curve_n = clampi(int(round(20.0 + radius * 1600.0)), 18, 32)
				elif wcount > 20:
					curve_n = clampi(int(round(26.0 + radius * 2200.0)), 24, 44)
				else:
					curve_n = clampi(int(round(32.0 + radius * 2800.0)), 32, 56)
				pts = _hose_curve(a, da, b, db, curve_n, radius)
				pts_ortho = pts
				if not drag_lite and radius < 0.0035:
					pts = _hose_simplify_path(pts, maxf(radius * 0.18, 0.0002))
				_apply_hose_path(node, pts, radius, trim_a, trim_b)
				_hide_hose_tube_cab(node)
				node.set_meta("geom_sig", sig)
				node.set_meta("curve_pts", pts)
				node.set_meta("door_span", false)
				node.set_meta("curve_pts_ortho", pts_ortho)
		var curve_pts: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
		var tube_r: float = float(node.get_meta("tube_radius", radius))
		node.set_meta("a", a)
		node.set_meta("b", b)
		node.set_meta("da", da)
		node.set_meta("db", db)
		# Физика L/V: только при смене геометрии трубки (не каждый кадр).
		if geom_changed and not is_elec and circuit != null and circuit.has_method("apply_wire_length_3d"):
			circuit.apply_wire_length_3d(wire, curve_pts)
		_sync_hose_sleeves(node, curve_pts, tube_r, int(wire.num), is_elec, wire)
	if not drag_lite:
		var stale: Array = []
		for id in _hose_nodes.keys():
			if not alive.has(id):
				stale.append(id)
		for id in stale:
			_hose_nodes[id].queue_free()
			_hose_nodes.erase(id)
	if has_elec:
		_sync_door_harness_flex(door_bundle, door_lite)
		# Сдвоенные НШВИ на клеммах с двумя проводами.
		if not drag_lite and not door_lite:
			_sync_nshvi_doubles()
		# Зубья КК, пересечённые проводом — скрыть (вход/выход из канала).
		if not drag_lite and not door_lite:
			_sync_duct_finger_cutouts()


## Скрыть зубья перфорированного КК у входа/выхода провода (в т.ч. провод в зазоре между зубами).
func _sync_duct_finger_cutouts() -> void:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return
	var host: Node3D = cab.get_node_or_null("CableDucts") as Node3D
	var door_duct: Node3D = cab.get_node_or_null("DoorHinge/Door/DoorCableDuct") as Node3D
	if host == null and door_duct == null:
		return
	var fingers: Array = []
	if host != null:
		_ensure_duct_finger_metas(host)
		_collect_duct_fingers(host, fingers)
	if door_duct != null:
		_ensure_duct_finger_metas_single(door_duct)
		_collect_duct_fingers(door_duct, fingers)
	var paths: Array = [] # {pts, r}
	var sig_parts: PackedStringArray = PackedStringArray()
	var host_id: int = host.get_instance_id() if host != null else 0
	var door_id: int = door_duct.get_instance_id() if door_duct != null else 0
	sig_parts.append("%d:%d:%d|v3" % [host_id, door_id, fingers.size()])
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid]
		if node == null or not node.visible:
			continue
		# Орто-ломаная точнее для зубьев; fillet уводит дугу от стенки.
		var pts: PackedVector3Array = node.get_meta("curve_pts_ortho", PackedVector3Array()) as PackedVector3Array
		if pts.size() < 2:
			pts = node.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
		if pts.size() < 2:
			continue
		var r: float = float(node.get_meta("tube_radius", 0.002))
		paths.append({"pts": pts, "r": r})
		var mid_i: int = pts.size() / 2
		var acc: Vector3 = Vector3.ZERO
		for p in pts:
			acc += p
		sig_parts.append("%d:%d:%.4f:%.3f,%.3f,%.3f:%.3f,%.3f,%.3f" % [
			int(wid), pts.size(), r,
			pts[mid_i].x, pts[mid_i].y, pts[mid_i].z,
			acc.x, acc.y, acc.z,
		])
	var sig: String = "|".join(sig_parts)
	if sig == _duct_finger_sig:
		return
	_duct_finger_sig = sig
	for fi in fingers:
		var mi: MeshInstance3D = fi as MeshInstance3D
		if mi != null:
			mi.visible = true
	if paths.is_empty():
		return
	# Зазор между зубами ≈ 4 мм: prox ≥ ползазора + Ø/2, иначе провод в щели «не задевает» AABB.
	var gap_half: float = Parts.mm(2.2)
	for fi2 in fingers:
		var fmi: MeshInstance3D = fi2 as MeshInstance3D
		if fmi == null or fmi.mesh == null:
			continue
		var box: AABB = fmi.global_transform * fmi.get_aabb()
		var hit: bool = false
		for pr in paths:
			var pts2: PackedVector3Array = pr["pts"] as PackedVector3Array
			var wr: float = float(pr["r"])
			var prox: float = maxf(wr + gap_half, Parts.mm(3.8))
			var grown: AABB = box.grow(prox)
			for si in range(pts2.size() - 1):
				if _segment_hits_aabb(pts2[si], pts2[si + 1], grown):
					hit = true
					break
				# Доп.: ближайшая точка отрезка к центру зуба (щель рядом).
				if _segment_near_point(pts2[si], pts2[si + 1], box.get_center(), prox + Parts.mm(1.5)):
					hit = true
					break
			if hit:
				break
		if hit:
			fmi.visible = false


func _ensure_duct_finger_metas(host: Node3D) -> void:
	# Уже собранный щит мог быть без meta — пометить тонкие «пальцы» перфорации.
	if host == null:
		return
	for duct in host.get_children():
		if duct is Node3D:
			_ensure_duct_finger_metas_single(duct as Node3D)


func _ensure_duct_finger_metas_single(duct: Node3D) -> void:
	if duct == null:
		return
	for c in duct.get_children():
		if not (c is MeshInstance3D) or str(c.name) == "Lid":
			continue
		var mi: MeshInstance3D = c as MeshInstance3D
		if bool(mi.get_meta("duct_finger", false)):
			continue
		if str(mi.name).begins_with("Finger"):
			mi.set_meta("duct_finger", true)
			continue
		var bm: BoxMesh = mi.mesh as BoxMesh
		if bm == null:
			continue
		var s: Vector3 = bm.size
		var sx: float = s.x
		var sy: float = s.y
		var sz: float = s.z
		var a: float = minf(sx, minf(sy, sz))
		var c3: float = maxf(sx, maxf(sy, sz))
		var b: float = sx + sy + sz - a - c3
		if a < Parts.mm(2.5) and b < Parts.mm(14.0) and c3 > Parts.mm(16.0):
			mi.set_meta("duct_finger", true)
			if not str(mi.name).begins_with("Finger"):
				mi.name = "Finger"


func _collect_duct_fingers(n: Node, out: Array) -> void:
	if n is MeshInstance3D and bool(n.get_meta("duct_finger", false)):
		out.append(n)
	for c in n.get_children():
		_collect_duct_fingers(c, out)


## Отрезок пересекает AABB (включая концы внутри).
func _segment_hits_aabb(a: Vector3, b: Vector3, box: AABB) -> bool:
	if box.has_point(a) or box.has_point(b):
		return true
	var hit: Variant = box.intersects_segment(a, b)
	return hit != null


## Отрезок ближе radius к точке (для зуба у щели, куда проходит провод).
func _segment_near_point(a: Vector3, b: Vector3, p: Vector3, radius: float) -> bool:
	var ab: Vector3 = b - a
	var lab2: float = ab.length_squared()
	if lab2 < 1.0e-12:
		return a.distance_squared_to(p) <= radius * radius
	var t: float = clampf((p - a).dot(ab) / lab2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(p) <= radius * radius


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


## Ключ сортировки door↔cab: локаль дверцы (не зависит от угла петли).
func _elec_door_span_sort_key(wire, pa: Vector3, pb: Vector3) -> float:
	if wire == null:
		return 0.0
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab) if cab != null else {}
	var door: Node3D = dd.get("door", null) as Node3D
	var a_on_door: bool = _electro_mount_of(int(wire.a_id)) == "door"
	var p_door: Vector3 = pa if a_on_door else pb
	if door != null:
		var loc: Vector3 = door.to_local(p_door)
		return loc.x * 1000.0 + float(int(wire.id)) * 0.001
	return float(int(wire.id))


## Раз в кадр: lane по пространству (X) + боковой сдвиг выхода с одной грани модуля.
func _elec_rebuild_separation() -> void:
	_elec_lane_by_wire.clear()
	_elec_exit_off.clear()
	if circuit == null:
		return
	# Jumpers и duct — отдельные нумерации. Lane по X, не по id — иначе трассы крест-накрест.
	var duct_recs: Array = [] # {id, x}
	var jump_recs: Array = []
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
		var wid: int = int(wire.id)
		var pa = _port_world(wire.a_id, wire.a_port)
		var pb = _port_world(wire.b_id, wire.b_port)
		var da: Vector3 = _port_dir_world(wire.a_id, wire.a_port)
		var db: Vector3 = _port_dir_world(wire.b_id, wire.b_port)
		var is_jump: bool = false
		var x_key: float = 0.0
		if pa != null and pb != null:
			# Дверные пролёты: ключ в локали дверцы — иначе после open/close
			# world-X переставляет lane и жилы в гофре меняются местами.
			if _wire_is_door_cabinet_span(wire):
				x_key = _elec_door_span_sort_key(wire, pa, pb)
			else:
				x_key = (float(pa.x) + float(pb.x)) * 0.5
			if da.length_squared() > 1.0e-10 and db.length_squared() > 1.0e-10:
				var na: Vector3 = da.normalized()
				var nb: Vector3 = db.normalized()
				var a1: Vector3 = pa + na * ELEC_SLEEVE_STUB
				var b1: Vector3 = pb + nb * ELEC_SLEEVE_STUB
				is_jump = _elec_wire_is_jumper(wire, a1, na, b1, nb)
		var rec_w: Dictionary = {"id": wid, "x": x_key}
		if is_jump:
			jump_recs.append(rec_w)
		else:
			duct_recs.append(rec_w)
		_elec_collect_face_end(face_groups, int(wire.a_id), str(wire.a_port))
		_elec_collect_face_end(face_groups, int(wire.b_id), str(wire.b_port))
	duct_recs.sort_custom(func(p, q): return float(p["x"]) < float(q["x"]))
	jump_recs.sort_custom(func(p, q): return float(p["x"]) < float(q["x"]))
	for i in duct_recs.size():
		_elec_lane_by_wire[int(duct_recs[i]["id"])] = i
	for i in jump_recs.size():
		_elec_lane_by_wire[int(jump_recs[i]["id"])] = i
	# Сдвоенный НШВИ: lane соседей в порядке дальнего X — иначе крест у колпачка/в боковом КК.
	_elec_cluster_double_nshvi_lanes()
	# На одной грани — развести пеньки (для jumper). Duct — только pack в сечении КК.
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


## Уникальный индекс 0…N−1 → смещение в сечении КК.
## Сначала dep (Z от панели), потом lat — иначе все жилы в боковом КК на одном удалении.
func _elec_pack_lane(idx: int) -> Vector2:
	var i: int = maxi(idx, 0)
	var dep_slots: int = 6 # ~40 мм КК → ±21 мм при pitch 8.5
	var lat_slots: int = 4
	var dep_i: int = i % dep_slots
	var lat_i: int = mini(int(i / dep_slots), lat_slots - 1)
	var lat_c: float = float(lat_i) - float(lat_slots - 1) * 0.5
	var dep_c: float = float(dep_i) - float(dep_slots - 1) * 0.5
	return Vector2(lat_c * ELEC_LANE_PITCH, dep_c * ELEC_LANE_PITCH)


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
	var mi2 := MeshInstance3D.new()
	mi2.name = "TubeCab"
	mi2.material_override = mat
	mi2.visible = false
	node.add_child(mi2)
	node.set_meta("mat", mat)
	_make_mark_sleeve(node, "SleeveA")
	_make_mark_sleeve(node, "SleeveB")
	_make_nshvi_node(node, "NshviA")
	_make_nshvi_node(node, "NshviB")
	return node


func _ensure_hose_sleeves(node: Node3D) -> void:
	if node == null:
		return
	if node.get_node_or_null("SleeveA") == null:
		_make_mark_sleeve(node, "SleeveA")
	if node.get_node_or_null("SleeveB") == null:
		_make_mark_sleeve(node, "SleeveB")
	if node.get_node_or_null("NshviA") == null:
		_make_nshvi_node(node, "NshviA")
	if node.get_node_or_null("NshviB") == null:
		_make_nshvi_node(node, "NshviB")
	# Миграция: цифры жили на цветном колпачке — переносим на белый кембрик.
	for sn in ["SleeveA", "SleeveB"]:
		var sl: MeshInstance3D = node.get_node_or_null(sn) as MeshInstance3D
		if sl == null:
			continue
		var metal_old: Node = sl.get_node_or_null("Metal")
		if metal_old != null:
			metal_old.queue_free()
		_ensure_sleeve_num_labels(sl)


func _make_mark_sleeve(parent: Node3D, name: String) -> void:
	# Белый маркировочный кембрик ≥20 мм + номер провода.
	var sleeve := MeshInstance3D.new()
	sleeve.name = name
	sleeve.visible = false
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.002
	cyl.bottom_radius = 0.002
	cyl.height = ELEC_MARK_LEN
	cyl.radial_segments = 14
	sleeve.mesh = cyl
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.96, 0.96, 0.94)
	smat.roughness = 0.55
	smat.metallic = 0.0
	sleeve.material_override = smat
	parent.add_child(sleeve)
	for side in [-1.0, 1.0]:
		var lab := Label3D.new()
		lab.name = "Num%s" % ("P" if side > 0.0 else "M")
		lab.text = ""
		lab.font_size = 21
		lab.pixel_size = 0.000063
		lab.modulate = Color(0.08, 0.08, 0.1)
		lab.outline_size = 0
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.no_depth_test = false
		lab.set_meta("side", side)
		sleeve.add_child(lab)


func _make_nshvi_node(parent: Node3D, name: String) -> void:
	var root := Node3D.new()
	root.name = name
	root.visible = false
	parent.add_child(root)
	for part_name in ["CollarBody", "CollarCone"]:
		var part := MeshInstance3D.new()
		part.name = part_name
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 16
		part.mesh = cyl
		var cmat := StandardMaterial3D.new()
		cmat.roughness = 0.48
		part.material_override = cmat
		root.add_child(part)
	var metal := MeshInstance3D.new()
	metal.name = "Metal"
	metal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mcyl := CylinderMesh.new()
	mcyl.radial_segments = 12
	metal.mesh = mcyl
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.78, 0.80, 0.84)
	mmat.roughness = 0.32
	mmat.metallic = 0.88
	metal.material_override = mmat
	root.add_child(metal)


func _make_hose_sleeve(parent: Node3D, name: String) -> void:
	_make_mark_sleeve(parent, name)



func _hide_hose_tube_cab(node: Node3D) -> void:
	if node == null:
		return
	var t2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
	if t2 != null:
		t2.visible = false
		t2.mesh = null


func _apply_hose_path_split(
	node: Node3D,
	pts_door: PackedVector3Array,
	pts_cab: PackedVector3Array,
	radius: float,
	trim_door_start: float,
	trim_door_end: float,
	trim_cab_start: float,
	trim_cab_end: float
) -> void:
	var mi: MeshInstance3D = node.get_node("Tube") as MeshInstance3D
	var mi2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
	if mi2 == null:
		mi2 = MeshInstance3D.new()
		mi2.name = "TubeCab"
		mi2.material_override = mi.material_override
		node.add_child(mi2)
	var mesh_d: PackedVector3Array = pts_door
	if pts_door.size() >= 2 and (trim_door_start > 1.0e-6 or trim_door_end > 1.0e-6):
		mesh_d = _trim_polyline_ends(pts_door, maxf(trim_door_start, 0.0), maxf(trim_door_end, 0.0))
	var mesh_c: PackedVector3Array = pts_cab
	if pts_cab.size() >= 2 and (trim_cab_start > 1.0e-6 or trim_cab_end > 1.0e-6):
		mesh_c = _trim_polyline_ends(pts_cab, maxf(trim_cab_start, 0.0), maxf(trim_cab_end, 0.0))
	mi.mesh = _build_tube_mesh(mesh_d, radius, 10) if mesh_d.size() >= 2 else null
	mi2.mesh = _build_tube_mesh(mesh_c, radius, 10) if mesh_c.size() >= 2 else null
	mi2.visible = mesh_c.size() >= 2
	var combined := PackedVector3Array()
	for p in pts_door:
		combined.append(p)
	for p in pts_cab:
		combined.append(p)
	node.set_meta("curve_pts", combined)
	node.set_meta("curve_pts_door", pts_door)
	node.set_meta("curve_pts_cab", pts_cab)
	node.set_meta("tube_radius", radius)


func _apply_hose_path(node: Node3D, pts: PackedVector3Array, radius: float, trim_a: float = 0.0, trim_b: float = 0.0) -> void:
	var mi: MeshInstance3D = node.get_node("Tube")
	# Под НШВИ изоляцию срезаем; со стороны источника/стыка — до конца, без щели.
	var mesh_pts: PackedVector3Array = pts
	if pts.size() >= 2 and (trim_a > 1.0e-6 or trim_b > 1.0e-6):
		mesh_pts = _trim_polyline_ends(pts, maxf(trim_a, 0.0), maxf(trim_b, 0.0))
	# Толстые пневмотрубки — больше сегментов кольца; LOD при многих проводах.
	var wcount2: int = circuit.wires.size() if circuit != null else 0
	var sides: int = clampi(int(round(8.0 + radius * 900.0)), 10, 18)
	if wcount2 > 40:
		sides = clampi(sides - 4, 7, 12)
	elif wcount2 > 20:
		sides = clampi(sides - 2, 8, 14)
	mi.mesh = _build_tube_mesh(mesh_pts, radius, sides)
	node.set_meta("curve_pts", pts)
	node.set_meta("tube_radius", radius)


## Срезать концы полилинии на trim_a / trim_b метров вдоль длины.
func _trim_polyline_ends(pts: PackedVector3Array, trim_a: float, trim_b: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	if total < trim_a + trim_b + 0.004:
		return pts
	var from_a: Dictionary = _point_along_path(pts, trim_a)
	var from_b: Dictionary = _point_along_path(pts, total - trim_b)
	if from_a.is_empty() or from_b.is_empty():
		return pts
	var i0: int = int(from_a["seg"])
	var i1: int = int(from_b["seg"])
	var out := PackedVector3Array()
	out.append(from_a["pos"] as Vector3)
	for i in range(i0 + 1, i1 + 1):
		if i > 0 and i < pts.size():
			out.append(pts[i])
	var end_p: Vector3 = from_b["pos"] as Vector3
	if out[out.size() - 1].distance_squared_to(end_p) > 1.0e-12:
		out.append(end_p)
	return out if out.size() >= 2 else pts


## Точка и касательная на дуге пути (s от начала). seg — индекс сегмента.
func _point_along_path(pts: PackedVector3Array, s: float) -> Dictionary:
	if pts.size() < 2:
		return {}
	var remain: float = maxf(s, 0.0)
	for i in range(pts.size() - 1):
		var seg: Vector3 = pts[i + 1] - pts[i]
		var L: float = seg.length()
		if L < 1.0e-9:
			continue
		if remain <= L + 1.0e-9:
			var t: float = clampf(remain / L, 0.0, 1.0)
			return {"pos": pts[i] + seg * t, "tang": seg / L, "seg": i}
		remain -= L
	var last: Vector3 = pts[pts.size() - 1] - pts[pts.size() - 2]
	var Ln: float = last.length()
	return {
		"pos": pts[pts.size() - 1],
		"tang": last / Ln if Ln > 1.0e-9 else Vector3.UP,
		"seg": pts.size() - 2,
	}


## Цвет колпачка НШВИ по сечению (DIN/Rexant: 0.5 бел … 2.5 син …).
func _nshvi_collar_color(section_mm2: float) -> Color:
	var s: float = Circuit.snap_wire_section(section_mm2)
	if is_equal_approx(s, 0.5):
		return Color(0.96, 0.96, 0.94)
	if is_equal_approx(s, 0.75):
		return Color(0.55, 0.56, 0.58)
	if is_equal_approx(s, 1.0):
		return Color(0.86, 0.14, 0.14)
	if is_equal_approx(s, 1.5):
		return Color(0.12, 0.12, 0.14)
	if is_equal_approx(s, 2.5):
		return Color(0.16, 0.38, 0.86)
	if is_equal_approx(s, 4.0):
		return Color(0.90, 0.78, 0.12)
	if is_equal_approx(s, 6.0):
		return Color(0.22, 0.62, 0.28)
	return Color(0.86, 0.14, 0.14)


func _nshvi_metal_radius(section_mm2: float) -> float:
	var s: float = Circuit.snap_wire_section(section_mm2)
	# Внутр. гильза чуть больше жилы (√(S/π) + обжим).
	var core_r_mm: float = sqrt(maxf(s, 0.25) / PI) + 0.15
	return clampf(core_r_mm * 0.001, 0.00055, 0.0022)


func _nshvi_collar_radius(wire_r: float, section_mm2: float) -> float:
	var od_r: float = Circuit.wire_od_mm(section_mm2) * 0.0005
	return maxf(od_r * 1.15, wire_r + 0.00035)


## Радиус маркировочного кембрика (как у рукава на жиле).
func _nshvi_mark_radius_from_od(od_mm: float) -> float:
	var wire_r: float = od_mm * 0.0005
	var collar_r: float = maxf(wire_r * 1.15, wire_r + 0.00035)
	return maxf(collar_r * 0.98, wire_r * 1.18)


## Шаг двух жил в сдвоенном НШВИ: кембрики впритык (центр–центр = Ø кембрика).
func _nshvi_pair_pitch_m(od_mm: float) -> float:
	return _nshvi_mark_radius_from_od(od_mm) * 2.0


## НШВИ только на клеммах приборов/клеммников — не на жилах вводного кабеля (источник).
func _end_wants_nshvi(el_id: int, _port: String) -> bool:
	if circuit == null or el_id < 0:
		return false
	var el = circuit.get_element(el_id)
	if el == null or str(el.kind) != "electro":
		return false
	if str(el.electro_class) == "supply":
		return false
	return true


## Два провода на порту → сдвоенный НШВИ (только если конец вообще допускает НШВИ).
func _port_needs_double_nshvi(el_id: int, port: String) -> bool:
	if circuit == null or el_id < 0 or port == "":
		return false
	if not _end_wants_nshvi(el_id, port):
		return false
	return circuit.port_wire_count(el_id, port) >= 2


## X дальнего конца провода (относительно данного порта) — для порядка в сдвоенном НШВИ.
func _elec_wire_far_x(wire, el_id: int, port: String) -> float:
	if wire == null:
		return 0.0
	var at_a: bool = int(wire.a_id) == el_id and str(wire.a_port) == port
	var other_id: int = int(wire.b_id) if at_a else int(wire.a_id)
	var other_port: String = str(wire.b_port) if at_a else str(wire.a_port)
	var pos = _port_world(other_id, other_port)
	if pos == null:
		return 0.0
	return float(pos.x)


## Соседи по сдвоенному НШВИ получают подряд идущие lane в порядке дальнего X.
func _elec_cluster_double_nshvi_lanes() -> void:
	if circuit == null:
		return
	var seen_ports: Dictionary = {}
	for wire in circuit.wires:
		if wire == null:
			continue
		for at_a in [true, false]:
			var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
			var port: String = str(wire.a_port) if at_a else str(wire.b_port)
			var pk: String = "%d|%s" % [el_id, port]
			if seen_ports.has(pk):
				continue
			seen_ports[pk] = true
			if not _port_needs_double_nshvi(el_id, port):
				continue
			var peers: Array = circuit.wires_on_port(el_id, port)
			var duct_peers: Array = []
			for p in peers:
				var wid: int = int(p.id)
				if not _elec_lane_by_wire.has(wid):
					continue
				duct_peers.append(p)
			if duct_peers.size() < 2:
				continue
			duct_peers.sort_custom(func(p, q):
				var xp: float = _elec_wire_far_x(p, el_id, port)
				var xq: float = _elec_wire_far_x(q, el_id, port)
				if absf(xp - xq) > 1.0e-6:
					return xp < xq
				return int(p.id) < int(q.id)
			)
			var lanes: Array = []
			for p2 in duct_peers:
				lanes.append(int(_elec_lane_by_wire[int(p2.id)]))
			lanes.sort()
			for i in duct_peers.size():
				_elec_lane_by_wire[int(duct_peers[i].id)] = int(lanes[i])


## Боковой сдвиг конца для параллельного входа в сдвоенный НШВИ.
func _nshvi_pair_end_offset(wire, at_a: bool, od_mm: float) -> Vector3:
	if wire == null or circuit == null:
		return Vector3.ZERO
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	var peers: Array = circuit.wires_on_port(el_id, port)
	if peers.size() < 2:
		return Vector3.ZERO
	# Порядок = дальний X (как lane после cluster) — левая жила уходит левее.
	peers.sort_custom(func(p, q):
		var xp: float = _elec_wire_far_x(p, el_id, port)
		var xq: float = _elec_wire_far_x(q, el_id, port)
		if absf(xp - xq) > 1.0e-6:
			return xp < xq
		var lp: int = int(_elec_lane_by_wire.get(int(p.id), int(p.id)))
		var lq: int = int(_elec_lane_by_wire.get(int(q.id), int(q.id)))
		if lp != lq:
			return lp < lq
		return int(p.id) < int(q.id)
	)
	var idx: int = 0
	for i in peers.size():
		if int(peers[i].id) == int(wire.id):
			idx = i
			break
	var dir: Vector3 = _port_dir_world(el_id, port)
	if dir.length_squared() < 1.0e-10:
		return Vector3.ZERO
	var lat: Vector3 = _elec_face_lateral(dir.normalized())
	var pitch: float = _nshvi_pair_pitch_m(od_mm)
	var mid: float = float(peers.size() - 1) * 0.5
	return lat * ((float(idx) - mid) * pitch)


## НШВИ на концах + маркировочный кембрик ≥20 мм с номером. Сдвоенный НШВИ — отдельно.
func _sync_hose_sleeves(node: Node3D, pts: PackedVector3Array, radius: float, wire_num: int, is_elec: bool, wire = null) -> void:
	_ensure_hose_sleeves(node)
	var sa: MeshInstance3D = node.get_node_or_null("SleeveA") as MeshInstance3D
	var sb: MeshInstance3D = node.get_node_or_null("SleeveB") as MeshInstance3D
	var na: Node3D = node.get_node_or_null("NshviA") as Node3D
	var nb: Node3D = node.get_node_or_null("NshviB") as Node3D
	if sa == null or sb == null:
		return
	if not is_elec or pts.size() < 2 or wire_num <= 0 or wire == null:
		sa.visible = false
		sb.visible = false
		if na != null:
			na.visible = false
		if nb != null:
			nb.visible = false
		return
	var tip_a: Vector3 = node.get_meta("a", pts[0]) as Vector3
	var tip_b: Vector3 = node.get_meta("b", pts[pts.size() - 1]) as Vector3
	var dir_a: Vector3 = node.get_meta("da", Vector3.UP) as Vector3
	var dir_b: Vector3 = node.get_meta("db", Vector3.UP) as Vector3
	if dir_a.length_squared() < 1.0e-10:
		dir_a = Vector3.UP
	if dir_b.length_squared() < 1.0e-10:
		dir_b = Vector3.UP
	dir_a = dir_a.normalized()
	dir_b = dir_b.normalized()
	var mm2: float = float(wire.id_mm)
	var collar_r: float = _nshvi_collar_radius(radius, mm2)
	var metal_r: float = _nshvi_metal_radius(mm2)
	var collar_col: Color = _nshvi_collar_color(mm2)
	# Кембрик ≈ Ø колпачка; чуть толще изоляции.
	var mark_r: float = maxf(collar_r * 0.98, radius * 1.18)
	var yaw_a: float = float(wire.sleeve_yaw_a)
	var yaw_b: float = float(wire.sleeve_yaw_b)
	var nshvi_a: bool = _end_wants_nshvi(int(wire.a_id), str(wire.a_port))
	var nshvi_b: bool = _end_wants_nshvi(int(wire.b_id), str(wire.b_port))
	var hide_a: bool = _port_needs_double_nshvi(int(wire.a_id), str(wire.a_port))
	var hide_b: bool = _port_needs_double_nshvi(int(wire.b_id), str(wire.b_port))
	var face_a: Vector3 = _sleeve_face_out_for_end(int(wire.a_id))
	var face_b: Vector3 = _sleeve_face_out_for_end(int(wire.b_id))
	if na != null:
		if not nshvi_a or hide_a:
			na.visible = false
		else:
			_place_nshvi(na, tip_a, dir_a, collar_r, metal_r, collar_col, yaw_a, face_a)
	if nb != null:
		if not nshvi_b or hide_b:
			nb.visible = false
		else:
			_place_nshvi(nb, tip_b, dir_b, collar_r, metal_r, collar_col, yaw_b, face_b)
	# Кембрик: полный реквизит; со стороны источника — на изоляции без НШВИ.
	# Дверца→щит: кембрик на подъёме к КК. Локаль на дверце — вдоль выхода (перемычка).
	var mark_a: String = circuit.wire_end_mark_label(wire, true)
	var mark_b: String = circuit.wire_end_mark_label(wire, false)
	var door_a: bool = _electro_mount_of(int(wire.a_id)) == "door"
	var door_b: bool = _electro_mount_of(int(wire.b_id)) == "door"
	var door_local: bool = _wire_is_door_local(wire)
	if door_a and nshvi_a and not hide_a and not door_local:
		_place_door_mark_sleeve(sa, tip_a, dir_a, mark_r, mark_a, yaw_a)
	else:
		_place_mark_sleeve(sa, tip_a, dir_a, mark_r, mark_a, yaw_a, hide_a, nshvi_a, face_a)
	if door_b and nshvi_b and not hide_b and not door_local:
		_place_door_mark_sleeve(sb, tip_b, dir_b, mark_r, mark_b, yaw_b)
	else:
		_place_mark_sleeve(sb, tip_b, dir_b, mark_r, mark_b, yaw_b, hide_b, nshvi_b, face_b)


## НШВИ: гильза 10 мм + колпачок (¾ цилиндр + ¼ конус к наконечнику).
func _place_nshvi(
	root: Node3D,
	tip_pos: Vector3,
	tip_dir: Vector3,
	collar_r: float,
	metal_r: float,
	collar_col: Color,
	yaw_twist: float = 0.0,
	face_out: Vector3 = Vector3.ZERO
) -> void:
	_ensure_nshvi_collar_parts(root)
	var tang: Vector3 = tip_dir.normalized() if tip_dir.length_squared() > 1.0e-12 else Vector3.UP
	var metal_h: float = ELEC_NSHVI_METAL_LEN
	var peek: float = ELEC_NSHVI_METAL_PEEK
	var collar_h: float = ELEC_NSHVI_COLLAR_LEN
	var cone_h: float = collar_h * ELEC_NSHVI_COLLAR_CONE_FRAC
	var body_h: float = collar_h - cone_h
	var join: float = 0.00035
	var tip_od: float = maxf(metal_r * 1.15, collar_r * 0.42)
	# Корень = геометрический центр всего колпачка.
	var collar_center: Vector3 = tip_pos + tang * (peek - join + collar_h * 0.5)
	var basis: Basis = _sleeve_basis_door_panel(tang, yaw_twist, face_out)
	root.global_transform = Transform3D(basis, collar_center)
	root.visible = true
	root.set_meta("yaw_twist", yaw_twist)
	# Локально: −Y к клемме. Снизу конус → сверху цилиндр.
	var y0: float = -collar_h * 0.5
	var cone: MeshInstance3D = root.get_node_or_null("CollarCone") as MeshInstance3D
	if cone != null:
		var ccyl: CylinderMesh = cone.mesh as CylinderMesh
		if ccyl == null:
			ccyl = CylinderMesh.new()
			cone.mesh = ccyl
		ccyl.bottom_radius = tip_od
		ccyl.top_radius = collar_r
		ccyl.height = cone_h
		ccyl.radial_segments = 16
		_nshvi_apply_collar_mat(cone, collar_col)
		cone.position = Vector3(0.0, y0 + cone_h * 0.5, 0.0)
		cone.visible = true
	var body: MeshInstance3D = root.get_node_or_null("CollarBody") as MeshInstance3D
	if body != null:
		var bcyl: CylinderMesh = body.mesh as CylinderMesh
		if bcyl == null:
			bcyl = CylinderMesh.new()
			body.mesh = bcyl
		bcyl.top_radius = collar_r
		bcyl.bottom_radius = collar_r
		bcyl.height = body_h
		bcyl.radial_segments = 16
		_nshvi_apply_collar_mat(body, collar_col)
		body.position = Vector3(0.0, y0 + cone_h + body_h * 0.5, 0.0)
		body.visible = true
	var old_collar: MeshInstance3D = root.get_node_or_null("Collar") as MeshInstance3D
	if old_collar != null:
		old_collar.visible = false
	var metal: MeshInstance3D = root.get_node_or_null("Metal") as MeshInstance3D
	if metal != null:
		var mcyl: CylinderMesh = metal.mesh as CylinderMesh
		if mcyl == null:
			mcyl = CylinderMesh.new()
			metal.mesh = mcyl
		mcyl.top_radius = metal_r
		mcyl.bottom_radius = metal_r
		mcyl.height = metal_h
		mcyl.radial_segments = 12
		metal.position = Vector3(0.0, -(collar_h * 0.5 + metal_h * 0.5 - join), 0.0)
		metal.rotation = Vector3.ZERO
		metal.visible = true
		metal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _nshvi_apply_collar_mat(mi: MeshInstance3D, col: Color) -> void:
	var cmat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if cmat == null:
		cmat = StandardMaterial3D.new()
		mi.material_override = cmat
	cmat.albedo_color = col
	cmat.roughness = 0.48
	cmat.metallic = 0.0


func _ensure_nshvi_collar_parts(root: Node3D) -> void:
	if root == null:
		return
	for part_name in ["CollarBody", "CollarCone"]:
		if root.get_node_or_null(part_name) != null:
			continue
		var part := MeshInstance3D.new()
		part.name = part_name
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 16
		part.mesh = cyl
		var cmat := StandardMaterial3D.new()
		cmat.roughness = 0.48
		part.material_override = cmat
		root.add_child(part)


## Кембрик ≥20 мм соосно нормали клеммы; с НШВИ — встык к колпачку, иначе на изоляции у стыка.
func _place_mark_sleeve(
	sleeve: MeshInstance3D,
	tip_pos: Vector3,
	tip_dir: Vector3,
	mark_r: float,
	mark_text: String,
	yaw_twist: float = 0.0,
	after_double_nshvi: bool = false,
	has_nshvi: bool = true,
	face_out: Vector3 = Vector3.ZERO
) -> void:
	var tang: Vector3 = tip_dir.normalized() if tip_dir.length_squared() > 1.0e-12 else Vector3.UP
	var mark_h: float = ELEC_MARK_LEN
	var mark_start: float
	if has_nshvi or after_double_nshvi:
		var collar_h: float = ELEC_NSHVI_COLLAR_LEN * (1.35 if after_double_nshvi else 1.0)
		var join: float = 0.00035
		mark_start = ELEC_NSHVI_METAL_PEEK - join + collar_h - ELEC_SLEEVE_OVERLAP
	else:
		# Стык удлинения / жила источника: кембрик на изоляции, без щели к стыку.
		mark_start = 0.001
	var center: Vector3 = tip_pos + tang * (mark_start + mark_h * 0.5)
	var cyl: CylinderMesh = sleeve.mesh as CylinderMesh
	if cyl == null:
		cyl = CylinderMesh.new()
		sleeve.mesh = cyl
	cyl.top_radius = mark_r
	cyl.bottom_radius = mark_r
	cyl.height = mark_h
	cyl.radial_segments = 14
	var smat: StandardMaterial3D = sleeve.material_override as StandardMaterial3D
	if smat == null:
		smat = StandardMaterial3D.new()
		sleeve.material_override = smat
	smat.albedo_color = Color(0.96, 0.96, 0.94)
	smat.roughness = 0.55
	smat.metallic = 0.0
	# Только цифры крутим yaw'ом; сам кембрик — строго по оси выхода.
	var basis: Basis = _sleeve_basis_door_panel(tang, 0.0, face_out)
	sleeve.global_transform = Transform3D(basis, center)
	sleeve.visible = true
	sleeve.set_meta("yaw_twist", yaw_twist)
	_ensure_sleeve_num_labels(sleeve)
	_orient_mark_labels(sleeve, basis, center, mark_r, mark_text, yaw_twist)


## Текст на кембрике вдоль оси (basis.y); yaw крутит только сторону подписи.
func _orient_mark_labels(
	sleeve: MeshInstance3D,
	basis: Basis,
	center: Vector3,
	mark_r: float,
	mark_text: String,
	yaw_twist: float = 0.0
) -> void:
	var twist: Basis = Basis(basis.y, yaw_twist) if absf(yaw_twist) > 1.0e-6 else Basis.IDENTITY
	# Размер фиксированный — длина кембрика (≥20 мм) вмещает реквизит без ужатия.
	var px: float = 0.000063
	for child in sleeve.get_children():
		if not (child is Label3D):
			continue
		var lab: Label3D = child as Label3D
		if not lab.has_meta("side"):
			lab.visible = false
			continue
		var side: float = float(lab.get_meta("side"))
		lab.text = mark_text
		lab.visible = mark_text != ""
		lab.modulate = Color(0.08, 0.08, 0.1)
		lab.font_size = 21
		lab.pixel_size = px
		lab.double_sided = false
		var outward: Vector3 = (twist * basis.x) * side
		var eps: float = 0.00022
		var lab_basis: Basis = _label_basis_along_sleeve(outward, basis.y)
		var local_xf: Transform3D = sleeve.global_transform.affine_inverse() * Transform3D(
			lab_basis, center + outward * (mark_r + eps)
		)
		lab.transform = local_xf


## Базис Label3D: +Z наружу, +X вдоль оси кембрика; низ глифа по возможности к +X щита.
func _label_basis_along_sleeve(outward: Vector3, along: Vector3) -> Basis:
	var n: Vector3 = outward.normalized() if outward.length_squared() > 1.0e-12 else Vector3.FORWARD
	var ax: Vector3 = along - n * along.dot(n)
	if ax.length_squared() < 1.0e-8:
		ax = Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
		if ax.length_squared() < 1.0e-8:
			ax = Vector3.UP - n * Vector3.UP.dot(n)
	ax = ax.normalized()
	var right_wall := Vector3.RIGHT
	var bottom_pref: Vector3 = right_wall - n * right_wall.dot(n)
	if bottom_pref.length_squared() < 1.0e-8:
		bottom_pref = Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if bottom_pref.length_squared() < 1.0e-8:
		bottom_pref = ax
	bottom_pref = bottom_pref.normalized()
	var lx: Vector3 = ax
	var ly: Vector3 = n.cross(lx)
	if ly.length_squared() < 1.0e-8:
		lx = Vector3.FORWARD.cross(n).normalized()
		ly = n.cross(lx)
	ly = ly.normalized()
	# Низ глифа (−ly) к правой стенке, если это не ломает ось чтения.
	if ly.dot(-bottom_pref) < 0.0:
		lx = -lx
		ly = -ly
	return Basis(lx, ly, n)


## Сдвоенные НШВИ: один широкий колпачок на клемму с двумя проводами.
func _sync_nshvi_doubles() -> void:
	if circuit == null or _hoses == null:
		return
	var want: Dictionary = {} # key -> {el_id, port, mm2, nums}
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		if ea == null or Geom.port_domain(ea, str(wire.a_port)) != "electric":
			continue
		for end_i in 2:
			var el_id: int = int(wire.a_id) if end_i == 0 else int(wire.b_id)
			var port: String = str(wire.a_port) if end_i == 0 else str(wire.b_port)
			if not _port_needs_double_nshvi(el_id, port):
				continue
			var key: String = "%d|%s" % [el_id, port]
			if not want.has(key):
				want[key] = {
					"el_id": el_id,
					"port": port,
					"mm2": float(wire.id_mm),
					"nums": [],
				}
			var rec: Dictionary = want[key]
			rec["mm2"] = maxf(float(rec["mm2"]), float(wire.id_mm))
			var nums: Array = rec["nums"] as Array
			var n: int = int(wire.num)
			if n > 0 and not nums.has(n):
				nums.append(n)
			rec["nums"] = nums
			want[key] = rec
	var stale: Array = []
	for k in _nshvi_doubles.keys():
		if not want.has(str(k)):
			stale.append(k)
	for k2 in stale:
		var old_n: Node = _nshvi_doubles[k2] as Node
		if old_n != null:
			old_n.queue_free()
		_nshvi_doubles.erase(k2)
	for key3 in want.keys():
		var info: Dictionary = want[key3]
		var el_id2: int = int(info["el_id"])
		var port2: String = str(info["port"])
		var pos = _port_world(el_id2, port2)
		var dir: Vector3 = _port_dir_world(el_id2, port2)
		if pos == null or dir.length_squared() < 1.0e-10:
			continue
		var nrm: Vector3 = dir.normalized()
		var mm2: float = float(info["mm2"])
		var node: Node3D = _nshvi_doubles.get(key3, null) as Node3D
		if node == null or not is_instance_valid(node):
			node = _make_double_nshvi_node()
			_hoses.add_child(node)
			_nshvi_doubles[key3] = node
		_place_double_nshvi(node, pos as Vector3, nrm, mm2, info["nums"] as Array)


func _make_double_nshvi_node() -> Node3D:
	var root := Node3D.new()
	root.name = "DoubleNshvi"
	var collar := MeshInstance3D.new()
	collar.name = "Collar"
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	collar.mesh = box
	var cmat := StandardMaterial3D.new()
	cmat.roughness = 0.48
	collar.material_override = cmat
	root.add_child(collar)
	var metal := MeshInstance3D.new()
	metal.name = "Metal"
	metal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 12
	metal.mesh = cyl
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.78, 0.80, 0.84)
	mmat.roughness = 0.32
	mmat.metallic = 0.88
	metal.material_override = mmat
	root.add_child(metal)
	for side in [-1.0, 1.0]:
		var lab := Label3D.new()
		lab.name = "Num%s" % ("P" if side > 0.0 else "M")
		lab.font_size = 22
		lab.pixel_size = 0.000065
		lab.outline_size = 0
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.set_meta("side", side)
		collar.add_child(lab)
	return root


func _place_double_nshvi(root: Node3D, port_pos: Vector3, nrm: Vector3, mm2: float, _nums: Array) -> void:
	_ensure_double_nshvi_parts(root)
	var od_mm: float = Circuit.wire_od_mm(mm2)
	var wire_r: float = od_mm * 0.0005
	var collar_r: float = _nshvi_collar_radius(wire_r, mm2)
	var mark_r: float = maxf(collar_r * 0.98, wire_r * 1.18)
	var metal_r: float = _nshvi_metal_radius(mm2) * 1.25
	var metal_h: float = ELEC_NSHVI_METAL_LEN
	var peek: float = ELEC_NSHVI_METAL_PEEK
	# Чуть длиннее одиночного — перекрыть заход обоих кембриков.
	var collar_h: float = ELEC_NSHVI_COLLAR_LEN * 1.35
	var cone_h: float = collar_h * ELEC_NSHVI_COLLAR_CONE_FRAC
	var body_h: float = collar_h - cone_h
	var join: float = 0.00035
	# Колпачок плотно вокруг двух кембриков впритык (тонкая стенка).
	var pair_pitch: float = _nshvi_pair_pitch_m(od_mm)
	var wall: float = 0.00055
	var width: float = pair_pitch + mark_r * 2.0 + wall * 2.0
	var thick: float = mark_r * 2.15 + wall
	var tip_w: float = metal_r * 2.5
	var tip_t: float = metal_r * 1.45
	var tang: Vector3 = nrm.normalized() if nrm.length_squared() > 1.0e-12 else Vector3.UP
	var collar_center: Vector3 = port_pos + tang * (peek - join + collar_h * 0.5)
	var basis: Basis = _sleeve_basis_door_panel(tang, 0.0)
	root.global_transform = Transform3D(basis, collar_center)
	root.visible = true
	var col: Color = _nshvi_collar_color(mm2)
	var y0: float = -collar_h * 0.5
	var cone: MeshInstance3D = root.get_node_or_null("CollarCone") as MeshInstance3D
	if cone != null:
		# Усечённая пирамида: −Y к наконечнику (узко), +Y к прямоугольному телу.
		cone.mesh = _make_truncated_pyramid_mesh(tip_t, tip_w, thick, width, cone_h)
		_nshvi_apply_collar_mat(cone, col)
		cone.position = Vector3(0.0, y0 + cone_h * 0.5, 0.0)
		cone.visible = true
	var body: MeshInstance3D = root.get_node_or_null("CollarBody") as MeshInstance3D
	if body != null:
		var bbox: BoxMesh = body.mesh as BoxMesh
		if bbox == null:
			bbox = BoxMesh.new()
			body.mesh = bbox
		# Z=width вдоль рейки (широкая грань к дверце), X=глубина.
		bbox.size = Vector3(thick, body_h, width)
		_nshvi_apply_collar_mat(body, col)
		body.position = Vector3(0.0, y0 + cone_h + body_h * 0.5, 0.0)
		body.visible = true
	var old_collar: MeshInstance3D = root.get_node_or_null("Collar") as MeshInstance3D
	if old_collar != null:
		old_collar.visible = false
		for child in old_collar.get_children():
			if child is Label3D:
				(child as Label3D).visible = false
	var metal: MeshInstance3D = root.get_node_or_null("Metal") as MeshInstance3D
	if metal != null:
		var cyl: CylinderMesh = metal.mesh as CylinderMesh
		if cyl == null:
			cyl = CylinderMesh.new()
			metal.mesh = cyl
		cyl.top_radius = metal_r
		cyl.bottom_radius = metal_r
		cyl.height = metal_h
		metal.position = Vector3(0.0, -(collar_h * 0.5 + metal_h * 0.5 - join), 0.0)
		metal.visible = true


## Усечённая пирамида вдоль Y: низ (bot_x×bot_z у гильзы) → верх (top_x×top_z у тела).
func _make_truncated_pyramid_mesh(bot_x: float, bot_z: float, top_x: float, top_z: float, h: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var hx0: float = maxf(bot_x, 0.0002) * 0.5
	var hz0: float = maxf(bot_z, 0.0002) * 0.5
	var hx1: float = maxf(top_x, 0.0002) * 0.5
	var hz1: float = maxf(top_z, 0.0002) * 0.5
	var y0: float = -maxf(h, 0.0002) * 0.5
	var y1: float = maxf(h, 0.0002) * 0.5
	var corners: Array = [
		Vector3(-hx0, y0, -hz0), Vector3(hx0, y0, -hz0),
		Vector3(hx0, y0, hz0), Vector3(-hx0, y0, hz0),
		Vector3(-hx1, y1, -hz1), Vector3(hx1, y1, -hz1),
		Vector3(hx1, y1, hz1), Vector3(-hx1, y1, hz1),
	]
	# Индексы треугольников (обход наружу).
	var tris: Array = [
		[0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
		[2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7],
		[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	for tri in tris:
		var p0: Vector3 = corners[int(tri[0])] as Vector3
		var p1: Vector3 = corners[int(tri[1])] as Vector3
		var p2: Vector3 = corners[int(tri[2])] as Vector3
		var nrm: Vector3 = (p1 - p0).cross(p2 - p0)
		if nrm.length_squared() < 1.0e-16:
			continue
		nrm = nrm.normalized()
		var base: int = verts.size()
		verts.append(p0)
		verts.append(p1)
		verts.append(p2)
		norms.append(nrm)
		norms.append(nrm)
		norms.append(nrm)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ensure_double_nshvi_parts(root: Node3D) -> void:
	if root == null:
		return
	for part_name in ["CollarBody", "CollarCone"]:
		if root.get_node_or_null(part_name) != null:
			continue
		var part := MeshInstance3D.new()
		part.name = part_name
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part_name == "CollarCone":
			part.mesh = _make_truncated_pyramid_mesh(0.002, 0.003, 0.004, 0.006, 0.002)
		else:
			part.mesh = BoxMesh.new()
		var cmat := StandardMaterial3D.new()
		cmat.roughness = 0.48
		part.material_override = cmat
		root.add_child(part)


## Базис кембрика/НШВИ: Y вдоль провода, +X к лицевой нормали (щит +Z / дверца), yaw вокруг Y.
func _sleeve_basis_door_panel(tang: Vector3, yaw_twist: float, face_out: Vector3 = Vector3.ZERO) -> Basis:
	var y: Vector3 = tang.normalized() if tang.length_squared() > 1.0e-12 else Vector3.UP
	var door: Vector3 = face_out
	if door.length_squared() < 1.0e-12:
		door = Vector3(0.0, 0.0, 1.0)
	else:
		door = door.normalized()
	var x: Vector3 = door - y * door.dot(y)
	if x.length_squared() < 1.0e-8:
		x = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	x = y.cross(z).normalized()
	var basis := Basis(x, y, z)
	if absf(yaw_twist) > 1.0e-6:
		basis = basis * Basis(Vector3.UP, yaw_twist)
	return basis


## Нормаль лицевой плоскости для кембрика: у дверцы — local +Z двери, иначе +Z щита.
func _sleeve_face_out_for_end(el_id: int) -> Vector3:
	if _electro_mount_of(el_id) != "door":
		return Vector3(0.0, 0.0, 1.0)
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return Vector3(0.0, 0.0, 1.0)
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab)
	var door: Node3D = dd.get("door", null) as Node3D
	if door == null:
		return Vector3(0.0, 0.0, 1.0)
	var n: Vector3 = door.global_transform.basis * Vector3(0.0, 0.0, 1.0)
	if n.length_squared() < 1.0e-12:
		return Vector3(0.0, 0.0, 1.0)
	return n.normalized()


func _ensure_sleeve_num_labels(sleeve: MeshInstance3D) -> void:
	if sleeve == null:
		return
	if sleeve.get_node_or_null("NumP") != null and sleeve.get_node_or_null("NumM") != null:
		return
	for side in [-1.0, 1.0]:
		var nm: String = "Num%s" % ("P" if side > 0.0 else "M")
		if sleeve.get_node_or_null(nm) != null:
			continue
		var lab := Label3D.new()
		lab.name = nm
		lab.font_size = 21
		lab.pixel_size = 0.000063
		lab.modulate = Color(0.08, 0.08, 0.1)
		lab.outline_size = 0
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.double_sided = false
		lab.set_meta("side", side)
		sleeve.add_child(lab)


func _pick_sleeve_hover(origin: Vector3, dir: Vector3) -> Dictionary:
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	var dlen: float = dir.length()
	if dlen < 1.0e-10:
		return {}
	var dnorm: Vector3 = dir / dlen
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid]
		if node == null or not node.visible:
			continue
		for end_name in ["SleeveA", "SleeveB"]:
			var sleeve: MeshInstance3D = node.get_node_or_null(end_name) as MeshInstance3D
			if sleeve == null or not sleeve.visible or sleeve.mesh == null:
				continue
			var box: AABB = sleeve.global_transform * sleeve.get_aabb()
			box = box.grow(0.0015)
			var t: float = _ray_aabb(origin, dnorm, box)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {
					"id": int(wid),
					"end": "a" if end_name == "SleeveA" else "b",
					"sleeve": sleeve,
					"pos": origin + dnorm * t,
				}
	return best


func _apply_sleeve_yaw_drag(dx: float) -> void:
	if circuit == null or _sleeve_drag_wire_id < 0:
		return
	var wire = circuit.get_wire(_sleeve_drag_wire_id)
	if wire == null:
		return
	var step: float = dx * 0.012
	if _sleeve_drag_end == "b":
		wire.sleeve_yaw_b = float(wire.sleeve_yaw_b) + step
	else:
		wire.sleeve_yaw_a = float(wire.sleeve_yaw_a) + step
	var node: Node3D = _hose_nodes.get(_sleeve_drag_wire_id, null) as Node3D
	if node == null:
		return
	var pts: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
	var radius: float = float(node.get_meta("tube_radius", 0.002))
	_sync_hose_sleeves(node, pts, radius, int(wire.num), true, wire)


func _polyline_min_edge(pts: PackedVector3Array) -> float:
	var best: float = 1.0e9
	for i in range(pts.size() - 1):
		var L: float = pts[i].distance_to(pts[i + 1])
		if L > 1.0e-6:
			best = minf(best, L)
	return best if best < 1.0e8 else 0.02


## Скругление углов: короткая дуга через Basis (без slerp — он давал «узлы»).
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
		# Короткие рёбра не скругляем — fillet съедает сегмент и петляет.
		if l0 < bend_r * 1.6 or l1 < bend_r * 1.6:
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		var u0: Vector3 = d0 / l0
		var u1: Vector3 = d1 / l1
		var defl: float = (-u0).angle_to(u1)
		if defl < deg_to_rad(18.0) or defl > deg_to_rad(160.0):
			if out[out.size() - 1].distance_squared_to(cur) > 1.0e-10:
				out.append(cur)
			continue
		var trim: float = bend_r * tan(defl * 0.5)
		trim = minf(trim, minf(l0 * 0.40, l1 * 0.40))
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
		var half: float = defl * 0.5
		var r_use: float = trim / maxf(tan(half), 1.0e-5)
		var center: Vector3 = p_enter + n_in * r_use
		if out[out.size() - 1].distance_squared_to(p_enter) > 1.0e-10:
			out.append(p_enter)
		var a0: Vector3 = p_enter - center
		# Кратчайший поворот a0 → (p_exit-center) вокруг axis.
		var ang_total: float = a0.angle_to(p_exit - center)
		if a0.cross(p_exit - center).dot(axis) < 0.0:
			ang_total = -ang_total
		for k in range(1, nseg):
			var ang: float = ang_total * (float(k) / float(nseg))
			out.append(center + Basis(axis, ang) * a0)
		out.append(p_exit)
	out.append(pts[pts.size() - 1])
	return out


## Убрать микро-сегменты и почти коллинеарные точки (ломают кадр трубки).
func _hose_simplify_path(pts: PackedVector3Array, min_seg: float) -> PackedVector3Array:
	# Пневмо Безье: только убрать микро-дубли. Электро-cleaner (коллинеарность)
	# выкидывает середины дуг и превращает шланг в «лестницу».
	if pts.size() < 2:
		return pts
	var eps: float = maxf(min_seg * 0.5, 0.00012)
	var out := PackedVector3Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		if out[out.size() - 1].distance_to(pts[i]) >= eps:
			out.append(pts[i])
	var last: Vector3 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_squared_to(last) > 1.0e-12:
		out.append(last)
	return out if out.size() >= 2 else pts


## Очистка ортогональной трассы: дубли, коллинеарность, развороты ~180°, микро-изломы.
func _hose_clean_elec_path(pts: PackedVector3Array, min_seg: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var eps: float = maxf(min_seg * 0.35, 0.00015)
	var raw := PackedVector3Array()
	raw.append(pts[0])
	for i in range(1, pts.size()):
		if raw[raw.size() - 1].distance_to(pts[i]) >= eps:
			raw.append(pts[i])
	if raw[raw.size() - 1].distance_squared_to(pts[pts.size() - 1]) > 1.0e-12:
		raw.append(pts[pts.size() - 1])
	if raw.size() < 3:
		return raw
	# Несколько проходов: после удаления спайка появляются новые коллинеарности.
	for _pass in 4:
		var next := PackedVector3Array()
		next.append(raw[0])
		var i: int = 1
		var removed: bool = false
		while i < raw.size() - 1:
			var a: Vector3 = next[next.size() - 1]
			var b: Vector3 = raw[i]
			var c: Vector3 = raw[i + 1]
			var d0: Vector3 = b - a
			var d1: Vector3 = c - b
			var l0: float = d0.length()
			var l1: float = d1.length()
			if l0 < eps or l1 < eps:
				i += 1
				removed = true
				continue
			var u0: Vector3 = d0 / l0
			var u1: Vector3 = d1 / l1
			var dot: float = u0.dot(u1)
			# Разворот / спайка — вершина вырождена.
			if dot < -0.90:
				i += 1
				removed = true
				continue
			# Почти прямая.
			if dot > 0.997:
				i += 1
				removed = true
				continue
			# Микро-излом: короткое ребро + почти обратный ход по одной оси.
			if l0 < min_seg and dot < -0.5:
				i += 1
				removed = true
				continue
			if l1 < min_seg and dot < -0.5:
				# Склеить a→c, пропустив b.
				i += 1
				removed = true
				continue
			next.append(b)
			i += 1
		next.append(raw[raw.size() - 1])
		raw = next
		if not removed or raw.size() < 3:
			break
	return raw if raw.size() >= 2 else pts


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
	# Касательные: на внутренних точках — среднее входящего/исходящего (меньше «перекрута» на гибах).
	var tangents: Array = []
	for i in n_pts:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n_pts - 1:
			t = path[i] - path[i - 1]
		else:
			var tin: Vector3 = path[i] - path[i - 1]
			var tout: Vector3 = path[i + 1] - path[i]
			var lin: float = tin.length()
			var lout: float = tout.length()
			if lin > 1.0e-9 and lout > 1.0e-9:
				t = tin / lin + tout / lout
			elif lout > 1.0e-9:
				t = tout
			else:
				t = tin
		if t.length_squared() < 1.0e-14:
			t = tangents[i - 1] if i > 0 else Vector3.FORWARD
		else:
			t = t.normalized()
		tangents.append(t)
	var t0: Vector3 = tangents[0]
	var ref: Vector3 = Vector3.RIGHT if absf(t0.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var normal: Vector3 = ref - t0 * ref.dot(t0)
	if normal.length_squared() < 1.0e-12:
		normal = Vector3.FORWARD - t0 * Vector3.FORWARD.dot(t0)
	normal = normal.normalized()
	var binorm: Vector3 = t0.cross(normal).normalized()
	normal = binorm.cross(t0).normalized()
	var side_n: int = maxi(sides, 5)
	for i in n_pts:
		var ti: Vector3 = tangents[i]
		if i > 0:
			var tprev: Vector3 = tangents[i - 1]
			var dot: float = clampf(tprev.dot(ti), -1.0, 1.0)
			if dot < -0.999:
				# Разворот ~180°: отразить нормаль в плоскости, без PI вокруг нестабильной оси.
				normal = -normal
			elif dot < 0.9995:
				var axis: Vector3 = tprev.cross(ti)
				if axis.length_squared() > 1.0e-12:
					normal = Basis(axis.normalized(), acos(dot)) * normal
			normal = (normal - ti * normal.dot(ti))
			if normal.length_squared() < 1.0e-12:
				var r2: Vector3 = Vector3.RIGHT if absf(ti.dot(Vector3.UP)) > 0.9 else Vector3.UP
				normal = (r2 - ti * r2.dot(ti)).normalized()
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
	# Конусы потока — только в режиме «Давление».
	if not bool(circuit.pressure_viz):
		for puff in _flow_pool:
			puff.visible = false
		return
	var cursor := 0
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	if circuit.running:
		for wire in circuit.wires:
			var q_vis: float = float(wire.flow_vis)
			if absf(q_vis) < SimV.FLOW_DEAD or cursor >= _flow_pool.size() - 4:
				continue
			var node: Node3D = _hose_nodes.get(wire.id, null)
			if node == null or not node.visible:
				continue
			var curve: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array())
			if curve.size() < 2:
				continue
			var ea = circuit.get_element(int(wire.a_id))
			if ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric":
				continue
			var qabs: float = absf(q_vis)
			var n_puffs: int = SimV.puff_count(qabs)
			if n_puffs <= 0:
				continue
			# На длинной трубке — чуть гуще, чтобы движение читалось.
			var path_len: float = 0.0
			for pi in range(curve.size() - 1):
				path_len += curve[pi].distance_to(curve[pi + 1])
			if path_len > 0.35:
				n_puffs = mini(n_puffs + 1, 6)
			if path_len > 0.7:
				n_puffs = mini(n_puffs + 1, 7)
			n_puffs = mini(n_puffs, _flow_pool.size() - cursor)
			var dir3: float = signf(q_vis)
			# Alpha/size ∝ |Q|: дозаряд полупрозрачный, сильный поток ярче.
			var q_t: float = clampf((qabs - SimV.FLOW_DEAD) / 3.5e-4, 0.0, 1.0)
			var col_a: float = lerpf(0.55, 0.95, q_t)
			var od_s: float = float(wire.od_mm) * lerpf(0.85, 1.15, q_t)
			for k in n_puffs:
				var t: float = fposmod(float(wire.flow_phase) + float(k) / float(n_puffs), 1.0)
				if dir3 < 0.0:
					t = 1.0 - t
				var idx: float = t * float(curve.size() - 1)
				var i0: int = clampi(int(floor(idx)), 0, curve.size() - 1)
				var i1: int = clampi(i0 + 1, 0, curve.size() - 1)
				var tang: Vector3 = curve[i1] - curve[i0]
				if tang.length_squared() < 1.0e-12 and i0 > 0:
					tang = curve[i0] - curve[i0 - 1]
				var motion: Vector3 = tang.normalized() * dir3 if tang.length_squared() > 1.0e-12 else Vector3.FORWARD
				_place_puff(
					cursor,
					curve[i0].lerp(curve[i1], idx - float(i0)),
					Color(0.62, 0.9, 1.0, col_a),
					motion,
					od_s
				)
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
					if absf(q) < SimV.FLOW_DEAD:
						continue
					var pos = _port_world(el.id, port_name)
					if pos == null or not dirs.has(port_name):
						continue
					var outward: Vector3 = root.global_transform.basis * dirs[port_name]
					var leaving: bool = q < 0.0
					var t: float = fposmod(circuit.sim_time * (0.8 if leaving else -0.8), 1.0)
					var color := Color(0.62, 0.9, 1.0, 0.75)
					var motion: Vector3 = outward.normalized() if leaving else -outward.normalized()
					_place_puff(cursor, pos + outward * (0.02 + t * 0.06), color, motion, 6.0)
					cursor += 1
			elif el.kind in ["accessory", "junction", "source"]:
				cursor = _puff_open_port_atm(el, cursor)
				if str(el.accessory_class) in ["regulator", "frl"]:
					cursor = _puff_regulator_relief(el, cursor)
			elif el.kind == "valve":
				cursor = _puff_open_port_atm(el, cursor)
				# Глушители 3/5 — конусы всегда (не только в рентгене).
				cursor = _puff_valve_muffler_exhaust(el, cursor)
				if xray:
					cursor = _puff_valve_flows(el, cursor)
	for i in range(cursor, _flow_pool.size()):
		_flow_pool[i].visible = false


## Сброс редуктора (relief): конусы из‑под нижней бобышки вниз (~0.55 с хвост).
func _puff_regulator_relief(el, cursor: int) -> int:
	var Parts = preload("res://scripts/view3d/pneumo_parts.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	if not circuit.regulator_relief_active(int(el.id)):
		return cursor
	var trail: float = float(circuit.relief_trail_s.get(int(el.id), 0.0))
	var local: Vector3 = Vector3(0.0, -Parts.mm(28.0), 0.0)
	if root.has_meta("relief_local"):
		local = root.get_meta("relief_local")
	var outward: Vector3 = Vector3.DOWN
	if root.has_meta("relief_dir"):
		outward = (root.global_transform.basis * root.get_meta("relief_dir")).normalized()
	else:
		outward = (root.global_transform.basis * Vector3.DOWN).normalized()
	var pos: Vector3 = root.global_transform * local
	var n_puffs: int = 3 if trail > 0.25 else 2
	var od: float = maxf(float(el.tube_od_mm), 6.0)
	for k in n_puffs:
		if cursor >= _flow_pool.size():
			break
		var t: float = fposmod(circuit.sim_time * 1.35 + float(k) / float(maxi(n_puffs, 1)), 1.0)
		_place_puff(
			cursor,
			pos + outward * (0.012 + t * 0.085),
			Color(0.62, 0.9, 1.0, 0.82),
			outward,
			od
		)
		cursor += 1
	return cursor


## Выхлоп/подсос на открытом пневмопорту (нет трубки).
func _puff_open_port_atm(el, cursor: int) -> int:
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	var dirs: Dictionary = root.get_meta("dirs") if root.has_meta("dirs") else {}
	const ATM_DEAD := 1.0e-6
	for port in Geom.ports(el):
		if cursor >= _flow_pool.size():
			break
		var pname: String = str(port["name"])
		if Geom.port_domain(el, pname) == "electric":
			continue
		if circuit.wire_on(int(el.id), pname) != null:
			continue
		var q: float = circuit.open_port_viz_q(el, pname)
		if absf(q) < ATM_DEAD:
			continue
		var pos = _port_world(el.id, pname)
		if pos == null:
			continue
		var outward: Vector3 = Vector3.UP
		if dirs.has(pname):
			outward = (root.global_transform.basis * dirs[pname]).normalized()
		# q<0 — наружу в атмосферу; остриё по движению среды.
		var motion: Vector3 = outward if q < 0.0 else -outward
		var n_puffs: int = maxi(mini(SimV.puff_count(absf(q)), 4), 2)
		for k in n_puffs:
			var t: float = fposmod(circuit.sim_time * 1.25 + float(k) / float(maxi(n_puffs, 1)), 1.0)
			_place_puff(cursor, pos + outward * (0.014 + t * 0.07), Color(0.62, 0.9, 1.0, 0.75), motion, 6.0)
			cursor += 1
	return cursor


## Конусы из глушителя/открытого выхлопа ПР (режим «Давление», не только x-ray).
func _puff_valve_muffler_exhaust(el, cursor: int) -> int:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	var dirs: Dictionary = root.get_meta("dirs") if root.has_meta("dirs") else {}
	var ports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	for name in ValveCat.port_names(el):
		if cursor >= _flow_pool.size() - 2:
			break
		if not ValveCat.is_exhaust_port(name):
			continue
		if circuit.wire_on(int(el.id), name) != null:
			continue
		var q: float = circuit.open_port_viz_q(el, name)
		if q > -SimV.FLOW_DEAD:
			continue
		if not ports.has(name):
			continue
		var pos: Vector3 = root.global_transform * (ports[name] as Vector3)
		var outward := Vector3.DOWN
		if dirs.has(name):
			outward = (root.global_transform.basis * (dirs[name] as Vector3)).normalized()
		else:
			outward = outward.normalized()
		var n_puffs: int = maxi(mini(SimV.puff_count(absf(q)), 4), 2)
		for k in n_puffs:
			if cursor >= _flow_pool.size():
				break
			var t: float = fposmod(circuit.sim_time * 1.2 + float(k) / float(n_puffs), 1.0)
			_place_puff(
				cursor,
				pos + outward * (0.012 + t * 0.08),
				Color(0.62, 0.9, 1.0, 0.85),
				outward,
				6.0
			)
			cursor += 1
	return cursor


func _puff_valve_flows(el, cursor: int) -> int:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	var dirs: Dictionary = root.get_meta("dirs") if root.has_meta("dirs") else {}
	var ports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	# Выхлоп в атмосферу вынесен в _puff_valve_muffler_exhaust (всегда при pressure_viz).
	# Здесь — только внутренние мостики в x-ray.
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
		# Устаканилось — не гоняем конусы туда-сюда.
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
		var motion: Vector3 = (pb - pa).normalized() if from_a else (pa - pb).normalized()
		_place_puff(cursor, p, col, motion, 6.0)
		cursor += 1
	return cursor


## Конус потока: остриё (+Y меша) вдоль dir; размер ∝ OD трубки (мм).
func _place_puff(
	index: int,
	at: Vector3,
	color: Color,
	dir: Vector3 = Vector3.ZERO,
	od_mm: float = 6.0
) -> void:
	var dot: MeshInstance3D = _flow_pool[index]
	dot.visible = true
	dot.position = at
	(dot.material_override as StandardMaterial3D).albedo_color = color
	# База меша ≈ Ø6; Ø4→0.67×, Ø10→1.67× — не тонут в толстых трубках.
	var s: float = clampf(maxf(od_mm, 2.0) / 6.0, 0.55, 2.8)
	if dir.length_squared() > 1.0e-10:
		_orient_cone_along(dot, dir, s)
	else:
		dot.basis = Basis.IDENTITY
		dot.scale = Vector3(s, s, s)


func _orient_cone_along(node: Node3D, dir: Vector3, scale_s: float = 1.0) -> void:
	var y: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y)
	if x.length_squared() < 1.0e-10:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	var s: float = maxf(scale_s, 0.05)
	node.transform = Transform3D(Basis(x * s, y * s, z * s), node.position)


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


func _hose_curve(a: Vector3, da: Vector3, b: Vector3, db: Vector3, n: int, tube_r: float = 0.002) -> PackedVector3Array:
	# Живая укладка: короткие пеньки по нормали цанги + кубическая Безье.
	# Ручки строго вдоль na/nb — стык пенёк/дуга G1, без перелома и без орто-каркаса.
	var na := da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var nb := db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
	var r: float = maxf(tube_r, 0.0012)
	var span0: float = maxf(a.distance_to(b), 0.001)
	var stub: float = clampf(r * 2.8, 0.007, 0.018)
	stub = minf(stub, span0 * 0.16)
	var a1: Vector3 = a + na * stub
	var b1: Vector3 = b + nb * stub
	var span: float = maxf(a1.distance_to(b1), 0.001)
	var port_dot: float = na.dot(nb)
	# При ~90° между нормалями — длиннее ручки (место на плавный поворот).
	var turn: float = clampf(1.0 - absf(port_dot), 0.0, 1.0)
	var tan_lo: float = maxf(0.020, r * 6.0)
	var tan_hi: float = maxf(0.15, r * 22.0)
	var tan_len: float = clampf(span * (0.34 + 0.28 * turn), tan_lo, tan_hi)
	tan_len = minf(tan_len, span * 0.48)
	var c1: Vector3 = a1 + na * tan_len
	var c2: Vector3 = b1 + nb * tan_len
	var out := PackedVector3Array()
	out.append(a)
	out.append(a1)
	var steps: int = maxi(n - 1, 1)
	for i in n:
		var s: float = float(i) / float(steps)
		var u: float = 1.0 - s
		var p: Vector3 = (
			u * u * u * a1
			+ 3.0 * u * u * s * c1
			+ 3.0 * u * s * s * c2
			+ s * s * s * b1
		)
		if out[out.size() - 1].distance_squared_to(p) > 1.0e-12:
			out.append(p)
	if out[out.size() - 1].distance_squared_to(b1) > 1.0e-12:
		out.append(b1)
	out.append(b)
	_hose_last_ortho = PackedVector3Array([a, a1, b1, b])
	return out


## Сгладить внутренние точки пути (фиксируем keep точек с каждого конца).
func _hose_relax_path(pts: PackedVector3Array, iters: int, keep: int) -> PackedVector3Array:
	if pts.size() < keep * 2 + 3 or iters <= 0:
		return pts
	var out: PackedVector3Array = pts.duplicate()
	for _pass in iters:
		var nxt: PackedVector3Array = out.duplicate()
		for j in range(keep, out.size() - keep):
			nxt[j] = out[j] * 0.5 + (out[j - 1] + out[j + 1]) * 0.25
		out = nxt
	return out


## Ортогональная укладка электропроводов.
## Длинные: вне корпуса → в КК → ближайший торец → вертикаль КК → к B → к клемме.
## Короткие: одна сторона / соседние / вертикальная «рот-в-рот» между рейками.

func _electro_mount_of(el_id: int) -> String:
	var el = circuit.get_element(_elec_primary_el_id(el_id)) if circuit != null else null
	if el == null or str(el.kind) != "electro":
		return ""
	return str(el.electro_mount)


func _wire_is_door_cabinet_span(wire) -> bool:
	if wire == null or circuit == null:
		return false
	var ma: String = _electro_mount_of(int(wire.a_id))
	var mb: String = _electro_mount_of(int(wire.b_id))
	if ma == "door" and mb != "door" and mb != "":
		return true
	if mb == "door" and ma != "door" and ma != "":
		return true
	return false


func _wire_is_door_local(wire) -> bool:
	if wire == null or circuit == null:
		return false
	return _electro_mount_of(int(wire.a_id)) == "door" and _electro_mount_of(int(wire.b_id)) == "door"


func _ensure_door_flex_node() -> MeshInstance3D:
	if _door_flex_node != null and is_instance_valid(_door_flex_node):
		return _door_flex_node
	if _hoses == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "DoorHarnessFlex"
	var mat := StandardMaterial3D.new()
	# ПВХ-гофра: нейтрально-серый, полуглянец (как кабель-трасса).
	# Godot 4: без specular (это Godot 3 SpatialMaterial — сыпет WARNING каждый кадр).
	mat.albedo_color = Color(0.58, 0.59, 0.61)
	mat.roughness = 0.32
	mat.metallic = 0.04
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_hoses.add_child(mi)
	_door_flex_node = mi
	return mi


func _door_flex_radius_m(wires: Array) -> float:
	# Ø гофры от суммарного сечения жил (мм²) + запас на укладку.
	var sum_mm2: float = 0.0
	for w in wires:
		if w == null:
			continue
		sum_mm2 += maxf(float(w.id_mm), 0.5)
	if sum_mm2 < 0.25:
		return 0.0
	var d_mm: float = clampf(sqrt(sum_mm2 * 1.35) * 1.55 + 4.0, 8.0, 28.0)
	return d_mm * 0.0005


func _build_ribbed_tube_mesh(pts: PackedVector3Array, radius: float, sides: int = 10) -> ArrayMesh:
	if pts.size() < 2 or radius < 1.0e-5:
		return ArrayMesh.new()
	# Равномерный шаг по длине дуги — одинаковые рёбра на прямых и изгибах.
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	if total < 1.0e-5:
		return ArrayMesh.new()
	var pitch: float = 0.0028
	var samples_per_rib: int = 10
	var n_samp: int = maxi(int(ceil(total / pitch * float(samples_per_rib))), samples_per_rib * 4)
	var dense := PackedVector3Array()
	var radii: Array = []
	for i in range(n_samp + 1):
		var s: float = total * float(i) / float(n_samp)
		dense.append(_point_on_polyline(pts, s))
		# Плавный round-crest (не «шайбы»).
		var phase: float = s / pitch * TAU
		var wave: float = 0.5 + 0.5 * cos(phase)
		wave = wave * wave * (3.0 - 2.0 * wave)
		radii.append(radius * lerpf(0.90, 1.10, wave))
	return _build_tube_mesh_varying(dense, radii, maxi(sides, 20))


func _point_on_polyline(pts: PackedVector3Array, dist: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	if pts.size() == 1:
		return pts[0]
	var remain: float = maxf(dist, 0.0)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var L: float = a.distance_to(b)
		if L < 1.0e-9:
			continue
		if remain <= L:
			return a.lerp(b, remain / L)
		remain -= L
	return pts[pts.size() - 1]


func _build_tube_mesh_varying(pts: PackedVector3Array, radii: Array, sides: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if pts.size() < 2 or radii.size() != pts.size():
		return mesh
	# Копия _build_tube_mesh с переменным радиусом.
	var path: PackedVector3Array = pts
	var n_pts: int = path.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tangents: Array = []
	for i in n_pts:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n_pts - 1:
			t = path[i] - path[i - 1]
		else:
			var tin: Vector3 = path[i] - path[i - 1]
			var tout: Vector3 = path[i + 1] - path[i]
			var lin: float = tin.length()
			var lout: float = tout.length()
			if lin > 1.0e-9 and lout > 1.0e-9:
				t = tin / lin + tout / lout
			elif lout > 1.0e-9:
				t = tout
			else:
				t = tin
		if t.length_squared() < 1.0e-14:
			t = tangents[i - 1] if i > 0 else Vector3.FORWARD
		else:
			t = t.normalized()
		tangents.append(t)
	var t0: Vector3 = tangents[0]
	var ref: Vector3 = Vector3.RIGHT if absf(t0.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var normal: Vector3 = ref - t0 * ref.dot(t0)
	if normal.length_squared() < 1.0e-12:
		normal = Vector3.FORWARD - t0 * Vector3.FORWARD.dot(t0)
	normal = normal.normalized()
	var binorm: Vector3 = t0.cross(normal).normalized()
	normal = binorm.cross(t0).normalized()
	var side_n: int = maxi(sides, 5)
	for i in n_pts:
		var ti: Vector3 = tangents[i]
		if i > 0:
			var tprev: Vector3 = tangents[i - 1]
			var dot: float = clampf(tprev.dot(ti), -1.0, 1.0)
			if dot < -0.999:
				normal = -normal
			elif dot < 0.9995:
				var axis: Vector3 = tprev.cross(ti)
				if axis.length_squared() > 1.0e-12:
					normal = Basis(axis.normalized(), acos(dot)) * normal
			normal = (normal - ti * normal.dot(ti))
			if normal.length_squared() < 1.0e-12:
				var r2: Vector3 = Vector3.RIGHT if absf(ti.dot(Vector3.UP)) > 0.9 else Vector3.UP
				normal = (r2 - ti * r2.dot(ti)).normalized()
			else:
				normal = normal.normalized()
			binorm = ti.cross(normal).normalized()
			normal = binorm.cross(ti).normalized()
		var rad: float = float(radii[i])
		var v_base: int = verts.size()
		var u: float = float(i) / float(maxi(n_pts - 1, 1))
		for s in side_n:
			var ang: float = TAU * float(s) / float(side_n)
			var dir: Vector3 = (normal * cos(ang) + binorm * sin(ang)).normalized()
			verts.append(path[i] + dir * rad)
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


func _sync_door_harness_flex(bundle: Array, door_animating: bool = false) -> void:
	var mi: MeshInstance3D = _ensure_door_flex_node()
	if mi == null:
		return
	# Нет дверных пролётов в схеме — можно гасить. Иначе не трогаем visible:
	# краткий пустой кадр (порт/якорь) раньше мигал гофрой при клике по УГО.
	if bundle.is_empty():
		if mi.mesh != null:
			mi.visible = false
		_door_flex_sig = ""
		return
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		# Щит временно недоступен — оставляем последний меш.
		return
	var anchors: Dictionary = IsoCabinet.harness_anchors_world(cab)
	if anchors.is_empty():
		# Якоря на кадр пусты (пересборка дверцы) — не гасим.
		return
	var r: float = _door_flex_radius_m(bundle)
	if r < 0.003:
		r = 0.004
	var a: Vector3 = anchors["door_exit"] as Vector3
	var b: Vector3 = anchors["cab_entry"] as Vector3
	# При анимации дверцы — точнее (мм), иначе ось гофры отстаёт от жил.
	var sig: String
	if door_animating:
		sig = "v6a|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f|%d" % [a.x, a.y, a.z, b.x, b.y, b.z, r, bundle.size()]
	else:
		sig = "v6|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.3f|%d" % [a.x, a.y, a.z, b.x, b.y, b.z, r, bundle.size()]
	if sig == _door_flex_sig and mi.mesh != null:
		mi.visible = true
		return
	var pts: PackedVector3Array = _door_flex_centerline(anchors)
	if pts.size() < 2:
		return
	var new_mesh: ArrayMesh = _build_ribbed_tube_mesh(pts, r, 20)
	if new_mesh.get_surface_count() < 1:
		return
	_door_flex_sig = sig
	mi.mesh = new_mesh
	mi.visible = true


## Ось гофры — та же кривая для меша и для жил (вход/выход).
func _door_flex_centerline(anchors: Dictionary) -> PackedVector3Array:
	if anchors.is_empty():
		return PackedVector3Array()
	var a: Vector3 = anchors["door_exit"] as Vector3
	var b: Vector3 = anchors["cab_entry"] as Vector3
	var da: Vector3 = anchors["door_dir"] as Vector3
	var db: Vector3 = anchors.get("cab_end_dir", anchors["cab_dir"]) as Vector3
	var pts: PackedVector3Array = _hose_curve(a, da, b, db, 20)
	var r_hint: float = 0.006
	return _fillet_polyline(pts, maxf(r_hint * 2.6, 0.012), 8)


## Точки жилы вдоль оси гофры: from_door=true — от дверцы внутрь; иначе — от щита внутрь.
func _flex_wire_along_centerline(
	anchors: Dictionary, lane: int, from_door: bool, depth: float
) -> PackedVector3Array:
	var center: PackedVector3Array = _door_flex_centerline(anchors)
	if center.size() < 2:
		return PackedVector3Array()
	var total: float = 0.0
	for i in range(center.size() - 1):
		total += center[i].distance_to(center[i + 1])
	if total < 1.0e-5:
		return PackedVector3Array()
	var enter_d: float = clampf(depth, 0.06, total * 0.48)
	var n_samp: int = maxi(ELEC_FLEX_ENTER_STEPS + 4, 8)
	var max_r: float = 0.0025
	# Параллельный перенос базиса от дверного торца — один порядок жил на всём рукаве.
	var frames: Array = []
	var f0: Dictionary = _flex_init_frame(center[1] - center[0])
	frames.append(f0)
	for ci in range(center.size() - 1):
		var seg_t: Vector3 = center[ci + 1] - center[ci]
		frames.append(_flex_transport_frame(frames[ci] as Dictionary, seg_t))
	var pack: Vector2 = _elec_pack_lane(lane)
	var out := PackedVector3Array()
	if from_door:
		for si in range(n_samp + 1):
			var s: float = enter_d * float(si) / float(n_samp)
			out.append(_flex_point_with_pack(center, frames, s, pack, max_r))
	else:
		for si in range(n_samp, -1, -1):
			var s2: float = total - enter_d * float(si) / float(n_samp)
			out.append(_flex_point_with_pack(center, frames, s2, pack, max_r))
	return out


func _flex_point_with_pack(
	center: PackedVector3Array, frames: Array, dist: float, pack: Vector2, max_r: float
) -> Vector3:
	var p: Vector3 = _point_on_polyline(center, dist)
	var fi: int = _flex_frame_index_at(center, dist)
	fi = clampi(fi, 0, frames.size() - 1)
	var fr: Dictionary = frames[fi] as Dictionary
	var n: Vector3 = fr["n"] as Vector3
	var b: Vector3 = fr["b"] as Vector3
	var off: Vector3 = n * (pack.x * 0.32) + b * (pack.y * 0.32)
	if off.length() > max_r:
		off = off.normalized() * max_r
	return p + off


func _flex_frame_index_at(pts: PackedVector3Array, dist: float) -> int:
	if pts.size() < 2:
		return 0
	var remain: float = maxf(dist, 0.0)
	for i in range(pts.size() - 1):
		var L: float = pts[i].distance_to(pts[i + 1])
		if L < 1.0e-9:
			continue
		if remain <= L:
			return i
		remain -= L
	return maxi(pts.size() - 1, 0)


func _tangent_on_polyline(pts: PackedVector3Array, dist: float) -> Vector3:
	if pts.size() < 2:
		return Vector3.FORWARD
	var remain: float = maxf(dist, 0.0)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var L: float = a.distance_to(b)
		if L < 1.0e-9:
			continue
		if remain <= L or i == pts.size() - 2:
			var t: Vector3 = b - a
			if t.length_squared() < 1.0e-12:
				return Vector3.FORWARD
			return t.normalized()
		remain -= L
	var last: Vector3 = pts[pts.size() - 1] - pts[pts.size() - 2]
	if last.length_squared() < 1.0e-12:
		return Vector3.FORWARD
	return last.normalized()


## Клемма дверцы (−Z): НШВИ прямо → запас → 90° вверх → кембрик → бок КК → канал → гофра.
func _hose_door_duct_run(
	port: Vector3,
	n_port: Vector3,
	door_duct: Dictionary,
	to_exit: bool,
	cab: Node3D = null,
	lane: int = 0
) -> PackedVector3Array:
	var door: Node3D = door_duct.get("door", null) as Node3D
	if door == null:
		return PackedVector3Array([port])
	var y: float = float(door_duct.get("y", 0.0))
	var z: float = float(door_duct.get("z", 0.0))
	var x0: float = float(door_duct.get("x0", 0.0))
	var x1: float = float(door_duct.get("x1", 0.0))
	var vh: float = float(door_duct.get("vh", Parts.mm(28.0)))
	var sh: float = float(door_duct.get("sh", Parts.mm(36.0)))
	var local: Vector3 = door.to_local(port)
	var pack: Vector2 = _elec_pack_lane(lane)
	# X клеммы до входа в КК — без бокового jog; lane только в канале/гофре.
	var lx: float = clampf(local.x, x0 + 0.012, x1 - 0.012)
	var side_sign: float = 1.0 if local.y >= y else -1.0
	var na: Vector3 = n_port.normalized() if n_port.length_squared() > 1.0e-10 else Vector3.BACK
	var door_y: Vector3 = door.global_transform.basis * Vector3(0.0, 1.0, 0.0)
	if door_y.length_squared() > 1.0e-10:
		door_y = door_y.normalized()
	else:
		door_y = Vector3.UP
	var y_side: float = y + side_sign * (vh * 0.5 + Parts.mm(3.0))
	var toward_y: float = signf(y_side - local.y)
	if absf(toward_y) < 0.5:
		toward_y = -side_sign
	var riser: Vector3 = door_y * toward_y
	var nshvi_len: float = ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var p_nshvi: Vector3 = port + na * nshvi_len
	# Прямо из колпачка, затем гибь — fillet не съедает НШВИ.
	var p_clear: Vector3 = p_nshvi + na * clear
	var p_rise: Vector3 = p_clear + riser * ELEC_DOOR_RISE_BEFORE_MARK
	var p_mark_end: Vector3 = p_rise + riser * ELEC_MARK_LEN
	var p_after: Vector3 = p_mark_end + riser * ELEC_DOOR_AFTER_MARK
	var y_lane: float = clampf(y + pack.x, y - vh * 0.32, y + vh * 0.32)
	var z_lane: float = clampf(z + pack.y, z - sh * 0.28, z + sh * 0.28)
	var px_lane: float = clampf(lx + pack.x * 0.2, x0 + 0.012, x1 - 0.012)
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, port)
	_hose_ortho_push(pts, p_nshvi)
	_hose_ortho_push(pts, p_clear)
	_hose_ortho_push(pts, p_rise)
	_hose_ortho_push(pts, p_mark_end)
	_hose_ortho_push(pts, p_after)
	var loc_after: Vector3 = door.to_local(p_after)
	# Сначала вверх/вниз к боку КК (тот же X), потом глубина Z, lane-X только у входа.
	_hose_ortho_push(pts, door.to_global(Vector3(lx, y_side, loc_after.z)))
	_hose_ortho_push(pts, door.to_global(Vector3(lx, y_side, z_lane)))
	_hose_ortho_push(pts, door.to_global(Vector3(px_lane, y_side, z_lane)))
	_hose_ortho_push(pts, door.to_global(Vector3(px_lane, y_lane, z_lane)))
	if to_exit:
		var exit_channel: Vector3 = door.to_global(Vector3(x0 + pack.x * 0.2, y_lane, z_lane))
		var p_enter: Vector3 = door.to_global(Vector3(px_lane, y_lane, z_lane))
		if p_enter.distance_to(exit_channel) > 0.008:
			_hose_ortho_push(pts, exit_channel)
		if cab != null:
			var anchors: Dictionary = IsoCabinet.harness_anchors_world(cab)
			if not anchors.is_empty():
				# До торца гофры (без захода внутрь) — заход дописывается после fillet.
				var flex_da: Vector3 = anchors["door_dir"] as Vector3
				if flex_da.length_squared() > 1.0e-10:
					flex_da = flex_da.normalized()
				else:
					flex_da = Vector3.LEFT
				var flex_off: Vector3 = _flex_bundle_offset(flex_da, lane)
				if flex_off.length() > 0.0028:
					flex_off = flex_off.normalized() * 0.0028
				var flex_a: Vector3 = (anchors["door_exit"] as Vector3) + flex_off
				_hose_ortho_push(pts, flex_a - flex_da * ELEC_FLEX_APPROACH)
				_hose_ortho_push(pts, flex_a)
		else:
			var exit_dir: Vector3 = door_duct.get("exit_dir", Vector3.LEFT) as Vector3
			if exit_dir.length_squared() > 1.0e-10:
				exit_dir = exit_dir.normalized()
			else:
				exit_dir = Vector3.LEFT
			_hose_ortho_push(pts, exit_channel + exit_dir * ELEC_FLEX_WIRE_OVERLAP)
	return pts


## Сдвиг жилы внутри гофры (перпендикуляр оси), чтобы трассы не совпадали.
func _flex_bundle_offset(along: Vector3, lane: int) -> Vector3:
	var frame: Dictionary = _flex_init_frame(along)
	var n: Vector3 = frame["n"] as Vector3
	var b: Vector3 = frame["b"] as Vector3
	var pack: Vector2 = _elec_pack_lane(lane)
	return n * (pack.x * 0.32) + b * (pack.y * 0.32)


func _flex_init_frame(along: Vector3) -> Dictionary:
	var t: Vector3 = along.normalized() if along.length_squared() > 1.0e-10 else Vector3.UP
	var ref: Vector3 = Vector3.UP
	if absf(t.dot(ref)) > 0.92:
		ref = Vector3.RIGHT
	var n: Vector3 = ref - t * ref.dot(t)
	if n.length_squared() < 1.0e-10:
		n = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
	n = n.normalized()
	# Одна ориентация нормали — иначе при повороте дверцы n/b переворачиваются и жилы меняются местами.
	if n.y < 0.0:
		n = -n
	var b: Vector3 = t.cross(n)
	if b.length_squared() < 1.0e-10:
		b = t.cross(Vector3.RIGHT)
	b = b.normalized()
	return {"t": t, "n": n, "b": b}


func _flex_transport_frame(prev: Dictionary, along: Vector3) -> Dictionary:
	var t: Vector3 = along.normalized() if along.length_squared() > 1.0e-10 else (prev["t"] as Vector3)
	var n: Vector3 = prev["n"] as Vector3
	n = n - t * n.dot(t)
	if n.length_squared() < 1.0e-10:
		return _flex_init_frame(t)
	n = n.normalized()
	# Без переворота n.y — иначе на изгибе базис скачет и жилы меняются местами.
	var b: Vector3 = t.cross(n)
	if b.length_squared() < 1.0e-10:
		return _flex_init_frame(t)
	b = b.normalized()
	return {"t": t, "n": n, "b": b}


## Оба прибора на дверце: всегда перемычка у плоскости дверцы, без дверного КК.
func _hose_door_local_run(
	a: Vector3, na: Vector3, b: Vector3, nb: Vector3, _door_duct: Dictionary
) -> PackedVector3Array:
	var na_n: Vector3 = na.normalized() if na.length_squared() > 1.0e-10 else Vector3.BACK
	var nb_n: Vector3 = nb.normalized() if nb.length_squared() > 1.0e-10 else Vector3.BACK
	return _hose_door_local_jumper(a, na_n, b, nb_n)


## НШВИ+кембрик → запас → орто по плоскости дверцы → к другому прибору (не в КК).
func _hose_door_local_jumper(a: Vector3, na: Vector3, b: Vector3, nb: Vector3) -> PackedVector3Array:
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var stub: float = ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN + ELEC_MARK_LEN + clear
	var a1: Vector3 = a + na * stub
	var b1: Vector3 = b + nb * stub
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	# Мостик в плоскости, параллельной дверце (на глубине пеньков).
	_elec_push_ortho(pts, a1, b1)
	_hose_ortho_push(pts, b1)
	_hose_ortho_push(pts, b)
	return pts


func _hose_ortho_elec_door_span(
	a: Vector3, a1: Vector3, na: Vector3,
	b: Vector3, b1: Vector3, nb: Vector3,
	ida: int, idb: int, lane: int, a_on_door: bool
) -> Dictionary:
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return {"door": PackedVector3Array(), "cab": PackedVector3Array()}
	var anchors: Dictionary = IsoCabinet.harness_anchors_world(cab)
	var dd: Dictionary = anchors.get("door_duct", {}) as Dictionary
	if anchors.is_empty() or dd.is_empty():
		return {"door": PackedVector3Array(), "cab": PackedVector3Array()}
	var door_port: Vector3 = a if a_on_door else b
	var door_n: Vector3 = na if a_on_door else nb
	var cab_port: Vector3 = b if a_on_door else a
	var cab_n: Vector3 = nb if a_on_door else na
	var cab_b1: Vector3 = b1 if a_on_door else a1
	var cab_id: int = idb if a_on_door else ida
	var door_pts: PackedVector3Array = _hose_door_duct_run(door_port, door_n, dd, true, cab, lane)
	var entry: Vector3 = anchors["cab_entry"] as Vector3
	var channel: Vector3 = anchors.get("cab_channel", entry) as Vector3
	var end_dir: Vector3 = anchors.get("cab_end_dir", anchors["cab_dir"]) as Vector3
	var into_duct: Vector3 = channel - entry
	if into_duct.length_squared() < 1.0e-10:
		into_duct = -end_dir
	else:
		into_duct = into_duct.normalized()
	var pack: Vector2 = _elec_pack_lane(lane)
	# В сечении верт. КК: lat по X (ширина пальцев), dep по Z (глубина).
	var ch_off: Vector3 = Vector3(pack.x, 0.0, pack.y)
	var channel_w: Vector3 = channel + ch_off
	var ed: Vector3 = end_dir.normalized() if end_dir.length_squared() > 1.0e-10 else Vector3.RIGHT
	var enter_depth: float = 0.10
	var door_flex: PackedVector3Array = _flex_wire_along_centerline(anchors, lane, true, enter_depth)
	var cab_flex: PackedVector3Array = _flex_wire_along_centerline(anchors, lane, false, enter_depth)
	# Кабинетный канал без захода в гофру (заход — cab_flex, дописывается после fillet).
	var cab_pts := PackedVector3Array()
	var flex_off_cab: Vector3 = _flex_bundle_offset(end_dir, lane)
	if flex_off_cab.length() > 0.0028:
		flex_off_cab = flex_off_cab.normalized() * 0.0028
	var entry_w: Vector3 = entry + flex_off_cab
	_hose_ortho_push(cab_pts, entry_w)
	_hose_ortho_push(cab_pts, entry_w - ed * ELEC_FLEX_APPROACH)
	_hose_ortho_push(cab_pts, channel_w)
	var duct_pts: PackedVector3Array = _hose_ortho_elec_duct(
		channel_w, channel_w + into_duct * 0.008, into_duct,
		cab_port, cab_b1, cab_n,
		-1, cab_id, lane, Vector3.ZERO, Vector3.ZERO
	)
	for i in range(duct_pts.size()):
		if i == 0 and cab_pts.size() > 0 and cab_pts[cab_pts.size() - 1].distance_squared_to(duct_pts[i]) < 1.0e-10:
			continue
		_hose_ortho_push(cab_pts, duct_pts[i])
	return {"door": door_pts, "cab": cab_pts, "door_flex": door_flex, "cab_flex": cab_flex}


## Кембрик на прямом подъёме после запаса за НШВИ (без отвода вбок).
func _place_door_mark_sleeve(
	sleeve: MeshInstance3D,
	tip_pos: Vector3,
	tip_dir: Vector3,
	mark_r: float,
	mark_text: String,
	yaw_twist: float
) -> void:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab) if cab != null else {}
	var na: Vector3 = tip_dir.normalized() if tip_dir.length_squared() > 1.0e-12 else Vector3.BACK
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var nshvi_end: Vector3 = tip_pos + na * (ELEC_NSHVI_METAL_PEEK + ELEC_NSHVI_COLLAR_LEN)
	var p_clear: Vector3 = nshvi_end + na * clear
	var riser: Vector3 = Vector3.UP
	var face_out: Vector3 = Vector3(0.0, 0.0, 1.0)
	if not dd.is_empty():
		var door: Node3D = dd.get("door", null) as Node3D
		if door != null:
			var y: float = float(dd.get("y", 0.0))
			var vh: float = float(dd.get("vh", Parts.mm(28.0)))
			var local: Vector3 = door.to_local(tip_pos)
			var side_sign: float = 1.0 if local.y >= y else -1.0
			var y_side: float = y + side_sign * (vh * 0.5 + Parts.mm(3.0))
			var toward_y: float = signf(y_side - local.y)
			if absf(toward_y) < 0.5:
				toward_y = -side_sign
			var door_y: Vector3 = door.global_transform.basis * Vector3(0.0, 1.0, 0.0)
			if door_y.length_squared() > 1.0e-10:
				door_y = door_y.normalized()
			riser = door_y * toward_y
			var fn: Vector3 = door.global_transform.basis * Vector3(0.0, 0.0, 1.0)
			if fn.length_squared() > 1.0e-12:
				face_out = fn.normalized()
	var mark_origin: Vector3 = p_clear + riser * ELEC_DOOR_RISE_BEFORE_MARK
	_place_mark_sleeve(sleeve, mark_origin, riser, mark_r * 0.92, mark_text, yaw_twist, false, false, face_out)


func _hose_ortho_elec(a: Vector3, da: Vector3, b: Vector3, db: Vector3, wire = null, lane: int = 0) -> PackedVector3Array:
	var na := da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var nb := db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
	# Сначала короткий пень — для классификации jumper/duct.
	var a_probe: Vector3 = a + na * ELEC_SLEEVE_STUB
	var b_probe: Vector3 = b + nb * ELEC_SLEEVE_STUB
	var ida: int = _elec_primary_el_id(int(wire.a_id)) if wire != null else -1
	var idb: int = _elec_primary_el_id(int(wire.b_id)) if wire != null else -1
	var off_a: Vector3 = _elec_exit_offset_for(int(wire.a_id), str(wire.a_port)) if wire != null else Vector3.ZERO
	var off_b: Vector3 = _elec_exit_offset_for(int(wire.b_id), str(wire.b_port)) if wire != null else Vector3.ZERO
	if _elec_wire_is_jumper(wire, a_probe, na, b_probe, nb):
		# Перемычка: без exit-off (он делал «рамки»); стопка + запас до гиба.
		var a1: Vector3 = a + na * ELEC_JUMPER_STUB
		var b1: Vector3 = b + nb * ELEC_JUMPER_STUB
		return _hose_ortho_elec_jumper(a, a1, b, b1, na, nb, ida, idb, lane)
	# В КК: сначала выйти из кембрика по нормали, потом гибы к каналу.
	var stub_a: float = _elec_duct_end_stub(wire, true)
	var stub_b: float = _elec_duct_end_stub(wire, false)
	var a1d: Vector3 = a + na * stub_a
	var b1d: Vector3 = b + nb * stub_b
	return _hose_ortho_elec_duct(a, a1d, na, b, b1d, nb, ida, idb, lane, Vector3.ZERO, Vector3.ZERO)


## Длина прямого участка у клеммы до первого гиба (НШВИ+кембрик или только кембрик на вводе).
func _elec_duct_end_stub(wire, at_a: bool) -> float:
	if wire == null:
		return ELEC_SLEEVE_STUB
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	if _end_wants_nshvi(el_id, port):
		return ELEC_DUCT_STUB
	# Источник/ввод: НШВИ нет, но маркировочный кембрик ≥20 мм — гибы только после него.
	if circuit != null:
		var el = circuit.get_element(el_id)
		if el != null and str(el.kind) == "electro" and str(el.electro_class) == "supply":
			return ELEC_MARK_ONLY_STUB
	return ELEC_SLEEVE_STUB


## Длинный маршрут через перфорированные кабель-каналы.
## Важно: lat (высота в гориз. КК) сдвигаем ТОЛЬКО внутри канала (после Z),
## иначе снаружи жилы веером пересекаются по высоте.
func _hose_ortho_elec_duct(a: Vector3, a1: Vector3, na: Vector3, b: Vector3, b1: Vector3, nb: Vector3, ida: int, idb: int, lane: int = 0, off_a: Vector3 = Vector3.ZERO, off_b: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var ducts: Dictionary = _hose_ducts_cached()
	var hs: Array = ducts.get("h", [])
	var vs: Array = ducts.get("v", [])
	var clear_a: Vector3 = _elec_clear_for_duct(a1, na, ida) + off_a
	var clear_b: Vector3 = _elec_clear_for_duct(b1, nb, idb) + off_b
	# Сохранить боковой сдвиг сдвоенного НШВИ до входа в КК.
	clear_a.x = a1.x
	clear_b.x = b1.x
	var pack: Vector2 = _elec_pack_lane(lane)
	var o_lat: float = pack.x
	var o_dep: float = pack.y
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	if hs.is_empty() or vs.is_empty():
		var duct_z: float = _elec_duct_z(clear_a, clear_b) + o_dep
		var side_x: float = _elec_nearest_side_x(clear_a, clear_b) + o_lat
		var y_in: float = clear_a.y
		var y_out: float = _elec_duct_y(clear_b, nb)
		var ya0: float = y_in + o_lat
		var yb: float = y_out + o_lat
		_elec_enter_hduct(pts, a1, clear_a, duct_z) # снаружи без o_lat
		_hose_ortho_push(pts, Vector3(clear_a.x, ya0, duct_z)) # lat внутри
		_hose_ortho_push(pts, Vector3(side_x, ya0, duct_z))
		_hose_ortho_push(pts, Vector3(side_x, yb, duct_z))
		_elec_leave_hduct(pts, clear_b, duct_z, yb)
		_elec_push_ortho(pts, clear_b, b1)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	var ha: Dictionary = _elec_pick_h_duct(hs, clear_a, na)
	var hb: Dictionary = _elec_pick_h_duct(hs, clear_b, nb)
	var za: float = float(ha.get("z", clear_a.z - 0.04)) + o_dep
	var zb: float = float(hb.get("z", clear_b.z - 0.04)) + o_dep
	var ya_base: float = float(ha.get("y", clear_a.y))
	var yb_base: float = float(hb.get("y", clear_b.y))
	var ya: float = ya_base + o_lat
	var yb2: float = yb_base + o_lat
	_elec_enter_hduct(pts, a1, clear_a, za) # Z на высоте clear — без веера снаружи
	if absf(clear_a.y - ya) > 0.0012:
		_hose_ortho_push(pts, Vector3(clear_a.x, ya, za)) # lat только в КК
	if absf(ya - yb2) < 0.010 and absf(za - zb) < 0.008:
		_hose_ortho_push(pts, Vector3(clear_b.x, ya, za))
		_elec_leave_hduct(pts, clear_b, za, ya)
		_elec_push_ortho(pts, clear_b, b1)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	# Верт. КК: lat→X, dep→Z.
	var mid_x: float = (clear_a.x + clear_b.x) * 0.5
	var base_vx: float = _elec_nearest_v_duct_x(vs, mid_x)
	var route_x: float = base_vx + o_lat
	_hose_ortho_push(pts, Vector3(route_x, ya, za))
	if absf(za - zb) > 0.0025:
		var z_v: float = (za + zb) * 0.5
		_hose_ortho_push(pts, Vector3(route_x, ya, z_v))
		_hose_ortho_push(pts, Vector3(route_x, yb2, z_v))
		_hose_ortho_push(pts, Vector3(route_x, yb2, zb))
	else:
		_hose_ortho_push(pts, Vector3(route_x, yb2, za))
		zb = za
	_hose_ortho_push(pts, Vector3(clear_b.x, yb2, zb))
	_elec_leave_hduct(pts, clear_b, zb, yb2)
	_elec_push_ortho(pts, clear_b, b1)
	_hose_ortho_push(pts, b1)
	_hose_ortho_push(pts, b)
	return pts


## Ортогональный добор: оси по убыванию |Δ| — меньше лишних «рамок».
func _elec_push_ortho(pts: PackedVector3Array, from: Vector3, to: Vector3) -> void:
	if pts.is_empty():
		_hose_ortho_push(pts, from)
	var cur: Vector3 = pts[pts.size() - 1]
	var dx: float = absf(cur.x - to.x)
	var dy: float = absf(cur.y - to.y)
	var dz: float = absf(cur.z - to.z)
	var order: Array = [[dx, 0], [dy, 1], [dz, 2]]
	order.sort_custom(func(p, q): return float(p[0]) > float(q[0]))
	for item in order:
		if float(item[0]) <= 1.0e-5:
			continue
		match int(item[1]):
			0:
				cur = Vector3(to.x, cur.y, cur.z)
			1:
				cur = Vector3(cur.x, to.y, cur.z)
			_:
				cur = Vector3(cur.x, cur.y, to.z)
		_hose_ortho_push(pts, cur)


## Вход в гориз. КК снаружи: clear → Z в канал на высоте clear (без lat-веера).
func _elec_enter_hduct(pts: PackedVector3Array, a1: Vector3, clear: Vector3, z_duct: float) -> void:
	_elec_push_ortho(pts, a1, clear)
	var cur: Vector3 = pts[pts.size() - 1]
	if absf(cur.z - z_duct) > 0.0012:
		_hose_ortho_push(pts, Vector3(cur.x, cur.y, z_duct))


## Выход: внутри выровнять Y к clear, затем Z наружу — lat не торчит снаружи.
func _elec_leave_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, y_lane: float) -> void:
	_hose_ortho_push(pts, Vector3(clear.x, y_lane, z_duct))
	var cur: Vector3 = pts[pts.size() - 1]
	if absf(cur.y - clear.y) > 0.0012:
		cur = Vector3(cur.x, clear.y, cur.z)
		_hose_ortho_push(pts, cur)
	if absf(cur.z - clear.z) > 0.0012:
		cur = Vector3(cur.x, cur.y, clear.z)
		_hose_ortho_push(pts, cur)
	_hose_ortho_push(pts, clear)


## Совместимость: старые вызовы (y_duct игнорируется — lat задаётся снаружи вызовом).
func _elec_push_into_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, _y_duct: float = 0.0) -> void:
	var a1: Vector3 = pts[pts.size() - 1] if not pts.is_empty() else clear
	_elec_enter_hduct(pts, a1, clear, z_duct)


func _elec_push_out_of_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, y_duct: float) -> void:
	_elec_leave_hduct(pts, clear, z_duct, y_duct)


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
	if n.y < -0.30:
		q.y = minf(q.y, box.position.y - pad)
		# Z клеммы: не тянуть на face_z (иначе П-перемычка уезжает к дверце).
		q.z = p.z
	elif n.y > 0.30:
		q.y = maxf(q.y, box.position.y + box.size.y + pad)
		q.z = p.z
	else:
		# Торцевые порты — чуть вперёд от корпуса (к дверце).
		var face_z: float = box.position.z + box.size.z
		q.z = maxf(q.z, face_z + pad)
	return q


## Короткая перемычка: чистая U/П от пеньков; lane слегка разводит высоту мостика.
func _hose_ortho_elec_jumper(a: Vector3, a1: Vector3, b: Vector3, b1: Vector3, na: Vector3, nb: Vector3, _ida: int = -1, _idb: int = -1, lane: int = 0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	var facing_vert: bool = (na.y > 0.30 and nb.y < -0.30) or (na.y < -0.30 and nb.y > 0.30)
	if facing_vert:
		_elec_push_ortho(pts, a1, b1)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	var rise: float = 0.012
	var pack: Vector2 = _elec_pack_lane(lane)
	# Небольшой сдвиг мостика по высоте — соседние U не в одной плоскости.
	var y_sep: float = pack.x * 0.55
	var bridge_y: float
	if na.y > 0.35 and nb.y > 0.35:
		bridge_y = maxf(a1.y, b1.y) + rise + y_sep
	elif na.y < -0.35 and nb.y < -0.35:
		bridge_y = minf(a1.y, b1.y) - rise + y_sep
	elif (na.y + nb.y) >= 0.0:
		bridge_y = maxf(a1.y, b1.y) + rise + y_sep
	else:
		bridge_y = minf(a1.y, b1.y) - rise + y_sep
	# Подъём на месте → мостик → посадка: буква U.
	# Если клеммы почти в одной точке по XZ — уводим мостик по Z, иначе трубка рвётся на 180°.
	var span_xz: float = Vector2(a1.x - b1.x, a1.z - b1.z).length()
	var min_span: float = 0.0065
	var z_bump: float = 0.0
	if span_xz < min_span:
		z_bump = -(min_span - span_xz) * 0.5 - 0.004
	_hose_ortho_push(pts, Vector3(a1.x, bridge_y, a1.z + z_bump))
	if absf(a1.z - b1.z) > 0.0015 or absf(z_bump) > 1.0e-6:
		_hose_ortho_push(pts, Vector3(a1.x, bridge_y, b1.z + z_bump))
	_hose_ortho_push(pts, Vector3(b1.x, bridge_y, b1.z + z_bump))
	_hose_ortho_push(pts, b1)
	_hose_ortho_push(pts, b)
	return pts


## Короткая укладка: одна сторона без пересечения, либо вертикальная перемычка между рейками.
## DIN↔DIN в пределах щита — перемычка/U у приборов, не обязательный заход в КК.
func _elec_wire_is_jumper(wire, a1: Vector3, na: Vector3, b1: Vector3, nb: Vector3) -> bool:
	if wire == null or circuit == null:
		return false
	var ida: int = _elec_primary_el_id(int(wire.a_id))
	var idb: int = _elec_primary_el_id(int(wire.b_id))
	if ida < 0 or idb < 0:
		return false
	var same_side: bool = (na.y < -0.30 and nb.y < -0.30) or (na.y > 0.30 and nb.y > 0.30)
	var facing_vert: bool = (na.y > 0.30 and nb.y < -0.30) or (na.y < -0.30 and nb.y > 0.30)
	if ida == idb:
		return same_side or facing_vert
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
		# Одна рейка: по фронту / короткой U, если нет чужого корпуса между клеммами.
		# В т.ч. серия верх↔низ (QF1.2→QF2.1) — не гонять в КК.
		if same_side or facing_vert:
			return not _elec_front_blocked_between(ida, idb, a1, b1)
		return false
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
	# Гизмо перемещения/поворота — только вне пуска (стоп или пауза).
	# На дверце/DIN гизмо мировых осей не показываем — модуль двигается по плоскости щита.
	var show_gizmo: bool = (
		el != null
		and not bool(circuit.running)
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
		if rec == null or not rec.has("root"):
			continue
		var root_x: Node3D = rec["root"] as Node3D
		# Редуктор: рентген не делаем.
		if root_x != null and bool(root_x.get_meta("accessory_regulator", false)):
			continue
		Iso.apply_xray(root_x, xray)
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
	if Geom.part_zones(el).is_empty() and str(el.kind) not in ["cylinder", "valve", "electro", "source", "junction", "accessory"]:
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
	var sim_on: bool = bool(circuit.running)
	# Соединение проводов в 3D — только вне симуляции.
	var port0: Dictionary = _pick_port_hover(ray["origin"], ray["dir"])
	if not port0.is_empty() and not sim_on:
		_drag = "wire_port"
		_wire_port_a_id = int(port0.get("id", -1))
		_wire_port_a_name = str(port0.get("port", ""))
		_show_hover_hl_port(port0["pos"] as Vector3, port0.get("dir", Vector3.UP) as Vector3)
		_update_wire_ghost(screen)
		return
	# Поворот кембрика — только вне симуляции.
	var sleeve_hit: Dictionary = _pick_sleeve_hover(ray["origin"], ray["dir"])
	if not sleeve_hit.is_empty() and not sim_on:
		_drag = "sleeve_yaw"
		_sleeve_drag_wire_id = int(sleeve_hit.get("id", -1))
		_sleeve_drag_end = str(sleeve_hit.get("end", "a"))
		_sleeve_drag_node = sleeve_hit.get("sleeve") as MeshInstance3D
		return
	# Щит / электромодули.
	var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
	if cab != null:
		var hit_cab: Dictionary = IsoCabinet.pick_interact(cab, ray["origin"], ray["dir"])
		if not hit_cab.is_empty():
			if str(hit_cab.get("kind", "")) == "door":
				# Дверцу можно открывать и при пуске (обзор), перенос модулей — нет.
				IsoCabinet.toggle_door(cab, circuit)
				return
			if str(hit_cab.get("kind", "")) == "module":
				var eid: int = int(hit_cab.get("id", -1))
				var eel = circuit.get_element(eid)
				if eel != null:
					circuit.select_only(eid, "workshop")
					var hit_pt: Vector3 = hit_cab.get("point", Vector3.ZERO) as Vector3
					var hit_node := hit_cab.get("node") as Node3D
					# Крутилки KT — уставка всегда (и при пуске).
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
					# При пуске: моментная кнопка — сразу нажата, пока ЛКМ зажата.
					if sim_on \
							and str(eel.electro_class) == "button" and not bool(eel.latching):
						eel.pressed = true
						_drag = "electro_btn"
						_actuate_el_id = eid
						_module_hit_node = hit_node
						if hit_node != null:
							IsoElectro.update_state(hit_node, eel)
						return
					if str(eel.electro_mount) == "door" or str(eel.electro_mount) == "din":
						# При пуске — только клик-действие, без переноса по DIN/дверце.
						_drag = "door_module" if str(eel.electro_mount) == "door" else "din_module"
						_actuate_el_id = eid
						_module_press = screen
						_module_hit_pt = hit_pt
						_module_hit_node = hit_node
						_module_moved = false
				return
	# Органы пневмораспределителя — при пуске (на паузе не перехватывают гизмо).
	if sim_on:
		var act := _pick_actuator(ray["origin"], ray["dir"])
		if not act.is_empty():
			_begin_actuate(int(act["id"]), str(act["side"]), act["node"] as Node3D)
			return
	# Винт регулируемого дросселя — крутить и при пуске (активный орган).
	var thr_hit: Dictionary = _pick_throttle_screw(ray["origin"], ray["dir"])
	if not thr_hit.is_empty():
		_drag = "throttle_screw"
		_actuate_el_id = int(thr_hit.get("id", -1))
		_module_hit_node = thr_hit.get("root") as Node3D
		circuit.select_only(_actuate_el_id, "workshop")
		return
	# Ручка редуктора: клик = lock/unlock, drag (если unlocked) = уставка.
	var reg_hit: Dictionary = _pick_regulator_knob(ray["origin"], ray["dir"])
	if not reg_hit.is_empty():
		_drag = "regulator_knob"
		_actuate_el_id = int(reg_hit.get("id", -1))
		_module_hit_node = reg_hit.get("root") as Node3D
		_module_press = screen
		_module_moved = false
		circuit.select_only(_actuate_el_id, "workshop")
		return
	var handle := _pick_handle(ray["origin"], ray["dir"])
	if handle != "" and not sim_on:
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


func _click_electro_3d(
	el,
	hit_point: Vector3 = Vector3.ZERO,
	hit_node: Node3D = null,
	ray_origin: Vector3 = Vector3.ZERO,
	ray_dir: Vector3 = Vector3.ZERO
) -> void:
	# Короткий клик (мышь уже отпущена): фиксация / тумблеры / АВ.
	# Моментная кнопка — hold на нажатии ЛКМ, сюда не попадает.
	if el == null or str(el.kind) != "electro":
		return
	if str(el.electro_class) == "button" and not bool(el.latching):
		return
	_toggle_electro_3d(el, hit_point, hit_node, ray_origin, ray_dir)


func _toggle_electro_3d(
	el,
	hit_point: Vector3 = Vector3.ZERO,
	hit_node: Node3D = null,
	ray_origin: Vector3 = Vector3.ZERO,
	ray_dir: Vector3 = Vector3.ZERO
) -> void:
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
			# Только рычаг (I/O); TEST у УЗО/АВДТ — отключение. Корпус не переключает.
			var ctrl: String = ""
			if hit_node != null and ray_dir.length_squared() > 1.0e-12:
				var ch: Dictionary = IsoElectro.pick_breaker_ctrl(hit_node, ray_origin, ray_dir)
				ctrl = str(ch.get("ctrl", ""))
			if ctrl == "lever":
				el.closed = not bool(el.closed)
			elif ctrl == "test" and str(el.electro_class) in ["rcd", "rcbo"]:
				el.closed = false
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
	if _drag == "throttle_screw":
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			_show_hover_hl_node(_module_hit_node)
		var tip_thr: String = circuit.element_sim_tip(int(el.id)) if circuit != null else str(el.tag)
		return "%s\nОрган: винт настройки" % tip_thr
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
	_hide_hover_hl_meshes()
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
	sim_control_changed.emit()


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
	sim_control_changed.emit()


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
		# default=null в get_meta Godot считает «нет default» и орёт — только has_meta.
		if act.has_meta("_cmd_pressed") and bool(act.get_meta("_cmd_pressed")) == pressed:
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
	if _drag == "sleeve_yaw":
		_last_hover_screen = event.position
		_apply_sleeve_yaw_drag(float(event.relative.x))
		return
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
	if _drag == "throttle_screw":
		var thr = circuit.get_element(_actuate_el_id) if circuit != null else null
		if thr == null or str(thr.accessory_class) != "throttle":
			return
		# Вправо / вниз мыши = по часовой = винт глубже = меньше opening.
		var d_ang: float = float(event.relative.x) + float(event.relative.y) * 0.35
		thr.opening = clampf(float(thr.opening) - d_ang * 0.0045, 0.0, 1.0)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			IsoThrottle.apply_opening(_module_hit_node, thr)
		return
	if _drag == "regulator_knob":
		if event.position.distance_to(_module_press) > 4.0:
			_module_moved = true
		var reg = circuit.get_element(_actuate_el_id) if circuit != null else null
		if reg == null or str(reg.accessory_class) != "regulator":
			return
		if not bool(reg.regulator_unlocked):
			return
		# Вправо / вниз = по часовой сверху = выше уставка.
		var d_set: float = float(event.relative.x) + float(event.relative.y) * 0.35
		reg.set_pressure_bar = clampf(
			float(reg.set_pressure_bar) + d_set * 0.018,
			IsoRegulator.SET_MIN_BAR, IsoRegulator.SET_MAX_BAR
		)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			IsoRegulator.apply_knob(_module_hit_node, reg)
		return
	if _drag == "door_module":
		# При пуске — только клик (перенос запрещён).
		if circuit != null and bool(circuit.running):
			return
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
		if circuit != null and bool(circuit.running):
			return
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
	if circuit != null and bool(circuit.running):
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
	if circuit != null and bool(circuit.running):
		_hover = ""
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


func _pick_throttle_screw(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "accessory" or str(el.accessory_class) != "throttle":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not IsoThrottle.pick_screw(root, origin, dir):
			continue
		var screw: Node3D = root.get_node_or_null("ThrottleScrew") as Node3D
		var center: Vector3 = screw.global_position if screw != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
	return best


func _pick_regulator_knob(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "accessory" or str(el.accessory_class) != "regulator":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not IsoRegulator.pick_knob(root, origin, dir):
			continue
		var knob: Node3D = root.get_node_or_null("RegulatorKnob") as Node3D
		var center: Vector3 = knob.global_position if knob != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
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


func _seat_aabb(root: Node3D) -> AABB:
	# Фиксированный габарит (дроссель и т.п.) — без подвижного винта/иглы.
	if root != null and root.has_meta("seat_aabb"):
		var fixed_box = root.get_meta("seat_aabb")
		if fixed_box is AABB:
			return fixed_box as AABB
	return _model_aabb(root)


func _model_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var started := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if str(child.name) == "SchematicGlow":
				continue
			if str(child.name) in ["ThrottleScrew", "ThrottleNeedle"]:
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
