extends Node3D
## Трёхмерный цех: параметрические модели, мировой гизмо и поток воздуха.

const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const IsoRotary = preload("res://scripts/view3d/iso_rotary.gd")
const IsoAirMotor = preload("res://scripts/view3d/iso_air_motor.gd")
const IsoInductive = preload("res://scripts/view3d/iso_inductive.gd")
const IsoCapacitive = preload("res://scripts/view3d/iso_capacitive.gd")
const IsoReed = preload("res://scripts/view3d/iso_reed.gd")
const IsoPressureSwitch = preload("res://scripts/view3d/iso_pressure_switch.gd")
const IsoPressureTx = preload("res://scripts/view3d/iso_pressure_tx.gd")
const IsoRtd = preload("res://scripts/view3d/iso_rtd.gd")
const IsoOptical = preload("res://scripts/view3d/iso_optical.gd")
const IsoOpticalCompact = preload("res://scripts/view3d/iso_optical_compact.gd")
const IsoUltrasonic = preload("res://scripts/view3d/iso_ultrasonic.gd")
const IsoOptoTip = preload("res://scripts/view3d/iso_opto_tip.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
const SensorSig = preload("res://scripts/domain/sensor_signal.gd")
const IsoElectro = preload("res://scripts/view3d/iso_electro.gd")
const IsoValve = preload("res://scripts/view3d/iso_valve.gd")
const IsoJunction = preload("res://scripts/view3d/iso_junction.gd")
const IsoThrottle = preload("res://scripts/view3d/iso_throttle.gd")
const IsoCheck = preload("res://scripts/view3d/iso_check.gd")
const IsoThrottleCheck = preload("res://scripts/view3d/iso_throttle_check.gd")
const IsoShuttle = preload("res://scripts/view3d/iso_shuttle.gd")
const IsoAnd = preload("res://scripts/view3d/iso_and.gd")
const IsoQuickExhaust = preload("res://scripts/view3d/iso_quick_exhaust.gd")
const IsoRelief = preload("res://scripts/view3d/iso_relief.gd")
const IsoShutoff = preload("res://scripts/view3d/iso_shutoff.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const IsoReservoir = preload("res://scripts/view3d/iso_reservoir.gd")
const IsoRegulator = preload("res://scripts/view3d/iso_regulator.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const Geom = preload("res://scripts/domain/symbol_geom.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")
const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const ThermalViz = preload("res://scripts/domain/thermal_viz.gd")
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
## Кэш шкалы тепловизора для легенды UI (мин/макс °C).
var _thermal_range := {"min": 20.0, "max": 22.0, "ambient": 20.0}
var _thermal_was_on := false

var _camera: Camera3D
var _machines: Node3D
var _hoses: Node3D
var _flows: Node3D
var _gizmo: Node3D
var _records := {}
var _hose_nodes := {}
## Чёрная оболочка полевого кабеля датчика (sensor_id → Node3D).
var _sensor_sheath_nodes := {}
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
## Подсветка жилы при hover (отдельный меш — не зависит от dense/Door Tube).
var _hover_hose_glow: MeshInstance3D
var _hover_hose_glow_mat: StandardMaterial3D
var _hover_hose_glow_id: int = -1
var _drag_point := 0.0
var _drag_angle := 0.0
var _drag_pos := Vector3.ZERO
var _drag_basis := Basis.IDENTITY
## Жест гизмо сдвинул/вернул transform — нужен touch_scene в undo-группу.
var _gizmo_moved := false
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
## Ghost-drag DIN/door: оригинал на месте, призрак едет; слот/xy — только на отпускании.
var _module_ghost: Node3D = null
var _module_ghost_slot: int = -1
var _module_ghost_xy: Vector2 = Vector2(-1, -1)
var _module_origin_slot: int = -1
var _module_origin_xy: Vector2 = Vector2(-1, -1)
var _timer_dial_kind := "" # value | unit
var _timer_dial_accum := 0.0
## Удержание +/− оптоусилителя (тик + автоповтор с ускорением, как Lanbao FD3).
var _amp_btn_name := "" # BtnPlus | BtnMinus
var _amp_btn_hold_t := 0.0
var _amp_btn_next_t := 0.0
## Винт реле давления: set | hyst (порог / дифференциал).
var _ps_screw_role := ""
## Автоповтор +/−: всегда ±1 тик; разгон до ~18 тик/с (не «десятки» за кадр).
const AMP_REPEAT_DELAY := 0.38
const AMP_INTERVAL_START := 0.16
const AMP_INTERVAL_MIN := 0.055
const AMP_ACCEL_SEC := 2.2
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
var _elec_sep_dirty: bool = true
## Idle: не гонять hose каждый кадр на плотном щите.
var _hose_idle_skip: int = 0
## Бюджет первичной/грязной сборки жил за кадр (иначе 80+ mesh = фриз).
var _hose_build_budget: int = 8
## Порог dense-LOD: меньше Label3D / НШВИ-деталей / sides трубок.
const DENSE_ELEC_WIRE_LOD := 40
## Один ArrayMesh на все электрожилы (вместо ~74 MeshInstance).
var _dense_elec_batch: MeshInstance3D = null
var _dense_elec_batch_sig: String = ""
## Legacy tip-batch MMI (выключен — только гасим, если остались от старого прогона).
var _dense_sleeve_mmi: MultiMeshInstance3D = null
var _dense_collar_mmi: MultiMeshInstance3D = null
var _dense_metal_mmi: MultiMeshInstance3D = null
var _dense_tip_batch_sig: String = ""
## Кэш готовности жил — не сканировать 70+ mesh каждый кадр.
var _hoses_ready_cached: bool = false
## Инкремент при add/remove: только грязные id + peers, без O(W) remesh всех.
var _hose_known_ids: Dictionary = {} # wire_id -> true
var _hose_wire_dirty: Dictionary = {} # wire_id -> true
## Тяжёлый post (dense batch / зубья) — после бюджета mesh, не каждый кадр mid-build.
var _hose_heavy_pending: bool = false
## Add-wire: batch/зубья выключены (индивидуальные Tube), пересборка после паузы.
var _hose_batch_suspended: bool = false
var _hose_heavy_idle_frames: int = 0
const HOSE_HEAVY_IDLE_FRAMES := 40
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
## Дверца: НШВИ по нормали → запас → 90° вверх → кембрик → запас → КК. Без отвода вбок.
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
## ЛКМ: несколько машин под лучом → белый список на оверлее 3D.
signal request_hit_picker(hits: Array, screen: Vector2)
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
	for _i in 120:
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
			sim_control_changed.emit()
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
		elif _drag == "threshold_screw":
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			_ps_screw_role = ""
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "amp_btn":
			_end_amp_btn_hold()
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
		elif _drag == "relief_screw":
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			if circuit != null:
				circuit.touch_scene()
		elif _drag == "relief_handle":
			var hid: int = _actuate_el_id
			var hroot: Node3D = _module_hit_node
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			if circuit != null:
				var hel = circuit.get_element(hid)
				if hel != null and str(hel.accessory_class) == "relief":
					hel.pressed = false
					if hroot != null and is_instance_valid(hroot):
						IsoRelief.apply_state(hroot, hel)
				circuit.touch_scene()
		elif _drag == "door_module" or _drag == "din_module":
			var mod_id: int = _actuate_el_id
			var was_din: bool = _drag == "din_module"
			var was_click: bool = not _module_moved and bool(circuit != null and circuit.running)
			var hit_pt: Vector3 = _module_hit_pt
			var hit_node: Node3D = _module_hit_node
			var pending_slot: int = _module_ghost_slot
			var pending_xy: Vector2 = _module_ghost_xy
			var did_move: bool = _module_moved
			_clear_module_ghost()
			_drag = ""
			_actuate_el_id = -1
			_module_hit_node = null
			_module_moved = false
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
				elif did_move:
					var mel2 = circuit.get_element(mod_id)
					if mel2 != null:
						if was_din and pending_slot >= 0:
							IsoCabinet.try_set_din_slot(circuit, mel2, pending_slot)
						elif not was_din and pending_xy.x >= 0.0:
							IsoCabinet.try_set_door_xy(circuit, mel2, pending_xy)
						circuit.touch_scene()
					# Сразу layout + упоры + жилы — иначе залипают на старых позах до след. ensure.
					_hose_hq_pending = true
					_elec_sep_dirty = true
					_hoses_ready_cached = false
					if _machines != null:
						IsoCabinet.invalidate_layout(_machines)
						IsoCabinet.ensure(_machines, circuit)
					_sync_hoses()
		elif _drag == "gizmo":
			_hose_hq_pending = true
			_elec_sep_dirty = true
			if circuit != null:
				if _gizmo_moved:
					circuit.touch_scene()
				if circuit.has_method("end_history_group"):
					circuit.end_history_group()
			_gizmo_moved = false
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
		# gui_input оверлея может не получить LMB-up (курсор ушёл на другую панель) —
		# тогда орган «липнет» к мыши. Сбрасываем, если ЛКМ уже отпущена.
		if _organ_drag_needs_lmb() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _drag == "regulator_knob":
				# Без unlock-по-клику — только снять залипание после LMB-up вне оверлея.
				_drag = ""
				_actuate_el_id = -1
				_module_hit_node = null
				_module_moved = false
			else:
				release_organ_drag()
			return
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
	_hoses_ready_cached = false
	_dense_elec_batch_sig = ""
	_dense_tip_batch_sig = ""
	_dense_tip_batch_set_visible(false)
	_hose_known_ids.clear()
	_hose_wire_dirty.clear()
	_hose_heavy_pending = true
	_hose_batch_suspended = false
	_hose_heavy_idle_frames = 0
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid] as Node3D
		if node != null and is_instance_valid(node):
			node.remove_meta("geom_sig")
			node.remove_meta("door_span")
			node.remove_meta("curve_pts_cab")
			node.remove_meta("curve_pts_cab_duct")


## После анимации дверцы: сбросить sig дверных пролётов и локальных перемычек.
## (Для смены модуля/маршрута — не для поворота петли; поворот → только гофра.)
func _invalidate_door_span_hose_cache() -> void:
	_door_flex_sig = ""
	_hose_hq_pending = true
	if circuit == null:
		return
	for wire in circuit.wires:
		if wire == null:
			continue
		if not _wire_is_door_cabinet_span(wire) and not _wire_is_door_local(wire):
			continue
		var node: Node3D = _hose_nodes.get(int(wire.id), null) as Node3D
		if node == null or not is_instance_valid(node):
			continue
		# Только geom_sig — кэш door/cab duct оставляем для следующей анимации.
		node.remove_meta("geom_sig")
		node.remove_meta("door_hinge_absorb")


## World-tip дверных жил съехал из‑за петли — принять новый geom_sig без remesh.
func _hose_mark_door_wires_absorb_hinge() -> void:
	if circuit == null:
		return
	for wire in circuit.wires:
		if wire == null:
			continue
		if not _wire_is_door_cabinet_span(wire) and not _wire_is_door_local(wire):
			continue
		var node: Node3D = _hose_nodes.get(int(wire.id), null) as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get_meta("tube_on_door", false)):
			node.set_meta("door_hinge_absorb", true)


## Ревью щита: пролёт на гофру/петлю (WASD сразу работает).
func aim_review_cabinet() -> void:
	cam_mode = "fly"
	xray = false
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


## MCP: принудительно посадить дверные Tube на полотно (после HQ / если meta без parent).
func debug_ensure_door_tubes() -> Dictionary:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return {"ok": false}
	_hose_ensure_door_wires_on_door(cab, false)
	return debug_door_wire_probe()


## MCP / отладка: открыть или закрыть дверцу щита (с анимацией).
func debug_toggle_cabinet_door(slow: bool = false) -> bool:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return false
	if slow:
		cab.set_meta("door_anim_slow", true)
	else:
		cab.set_meta("door_anim_slow", false)
	IsoCabinet.toggle_door(cab, circuit)
	return true


## Сразу после toggle: угол / tween (ловим мгновенный snap).
func debug_door_toggle_and_status(slow: bool = true, force_open_first: bool = true) -> Dictionary:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var out: Dictionary = {"ok": false}
	if cab == null:
		return out
	var hinge: Node3D = cab.get_node_or_null("DoorHinge") as Node3D
	if hinge == null:
		return out
	if force_open_first:
		cab.set_meta("door_open", true)
		if circuit != null:
			circuit.cabinet_door_open = true
		hinge.rotation_degrees = Vector3(0.0, -110.0, 0.0)
		if cab.has_meta("door_tween"):
			var old_tw = cab.get_meta("door_tween")
			if old_tw is Tween and is_instance_valid(old_tw):
				(old_tw as Tween).kill()
			cab.remove_meta("door_tween")
	cab.set_meta("door_anim_slow", slow)
	IsoCabinet.toggle_door(cab, circuit)
	var tw = cab.get_meta("door_tween") if cab.has_meta("door_tween") else null
	var tw_run: bool = tw is Tween and is_instance_valid(tw) and (tw as Tween).is_running()
	var probe: Dictionary = debug_door_wire_probe()
	out = {
		"ok": true,
		"door_open": bool(cab.get_meta("door_open", true)),
		"slow_meta": bool(cab.get_meta("door_anim_slow", false)),
		"hinge_y": hinge.rotation_degrees.y,
		"tween_running": tw_run,
		"animating": IsoCabinet.is_door_animating(cab),
		"tube_parent_door": int(probe.get("tube_parent_door", 0)),
		"tube_parent_hose": int(probe.get("tube_parent_hose", 0)),
		"tube_on_door_meta": int(probe.get("tube_on_door_meta", 0)),
		"batch_visible": _dense_elec_batch != null and is_instance_valid(_dense_elec_batch) and _dense_elec_batch.visible,
	}
	return out


## Снимок для ревью: угол петли + есть ли door-transform кэш у пролётов.
func debug_door_wire_probe() -> Dictionary:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var out: Dictionary = {
		"ok": cab != null,
		"animating": false,
		"hinge_y": 0.0,
		"door_open": false,
		"span_total": 0,
		"span_with_local_cache": 0,
		"span_doorxf_sig": 0,
		"tube_on_door_meta": 0,
		"tube_parent_door": 0,
		"tube_parent_hose": 0,
		"tube_missing": 0,
		"batch_visible": false,
	}
	if cab == null:
		return out
	out["animating"] = IsoCabinet.is_door_animating(cab)
	out["door_open"] = bool(cab.get_meta("door_open", true))
	out["batch_visible"] = _dense_elec_batch != null and is_instance_valid(_dense_elec_batch) and _dense_elec_batch.visible
	var hinge: Node3D = cab.get_node_or_null("DoorHinge") as Node3D
	if hinge != null:
		out["hinge_y"] = hinge.rotation_degrees.y
	var door: Node3D = cab.get_node_or_null("DoorHinge/Door") as Node3D
	if circuit == null:
		return out
	var with_cache: int = 0
	var doorxf: int = 0
	var total: int = 0
	var on_meta: int = 0
	var par_door: int = 0
	var par_hose: int = 0
	var missing: int = 0
	for wire in circuit.wires:
		if wire == null:
			continue
		var is_door_w: bool = _wire_is_door_cabinet_span(wire) or _wire_is_door_local(wire)
		if not is_door_w:
			continue
		if _wire_is_door_cabinet_span(wire):
			total += 1
		var node: Node3D = _hose_nodes.get(int(wire.id), null) as Node3D
		if node == null:
			continue
		if node.has_meta("curve_pts_door_duct_local") and node.has_meta("curve_pts_cab_duct"):
			with_cache += 1
		var gsig: String = str(node.get_meta("geom_sig", ""))
		if gsig.begins_with("doorxf|"):
			doorxf += 1
		if bool(node.get_meta("tube_on_door", false)):
			on_meta += 1
		var mi: MeshInstance3D = _hose_find_tube(node, door)
		if mi == null:
			missing += 1
		elif door != null and mi.get_parent() == door:
			par_door += 1
		else:
			par_hose += 1
	out["span_total"] = total
	out["span_with_local_cache"] = with_cache
	out["span_doorxf_sig"] = doorxf
	out["tube_on_door_meta"] = on_meta
	out["tube_parent_door"] = par_door
	out["tube_parent_hose"] = par_hose
	out["tube_missing"] = missing
	return out


## Ревью произвольной точки (дроссель и т.п.). Только камера — рентген не трогаем.
func aim_review_point(look: Vector3, fly_pos: Vector3) -> void:
	cam_mode = "fly"
	_target = look
	_fly_pos = fly_pos
	_aim_fly_at_target()
	_clamp_fly_pos()
	_place_camera()


func _drag_locks_hover() -> bool:
	return _drag in ["timer_dial", "throttle_screw", "threshold_screw", "amp_btn", "regulator_knob", "relief_screw", "relief_handle", "din_module", "door_module", "actuate", "electro_btn", "gizmo", "wire_port", "sleeve_yaw"]


func _organ_drag_needs_lmb() -> bool:
	return _drag in [
		"threshold_screw", "throttle_screw", "relief_screw", "timer_dial",
		"regulator_knob", "sleeve_yaw", "amp_btn",
	]


## Сброс винта/диска/+/− по глобальному LMB-up (когда overlay не получил событие).
## Регулятор сюда не входит — unlock по клику обрабатывает gui_input оверлея.
func release_organ_drag() -> void:
	if _drag not in ["threshold_screw", "throttle_screw", "relief_screw", "timer_dial", "sleeve_yaw", "amp_btn"]:
		return
	if _drag == "sleeve_yaw":
		_sleeve_drag_wire_id = -1
		_sleeve_drag_end = ""
		_sleeve_drag_node = null
	elif _drag == "timer_dial":
		_timer_dial_kind = ""
		_timer_dial_accum = 0.0
	elif _drag == "amp_btn":
		_amp_btn_name = ""
		_amp_btn_hold_t = 0.0
		_amp_btn_next_t = 0.0
	_ps_screw_role = ""
	_drag = ""
	_actuate_el_id = -1
	_module_hit_node = null
	_module_moved = false
	if circuit != null:
		circuit.touch_scene()


func _begin_amp_btn_hold(el_id: int, root: Node3D, btn_name: String) -> void:
	_drag = "amp_btn"
	_actuate_el_id = el_id
	_module_hit_node = root
	_amp_btn_name = btn_name
	_amp_btn_hold_t = 0.0
	_amp_btn_next_t = AMP_REPEAT_DELAY
	_apply_amp_set_tick(1 if btn_name == "BtnPlus" else -1)
	if circuit != null:
		circuit.select_only(el_id, "workshop")
	if root != null:
		var bnode: Node3D = root.get_node_or_null(btn_name) as Node3D
		_show_hover_hl_node(bnode if bnode != null else root)


func _end_amp_btn_hold() -> void:
	_amp_btn_name = ""
	_amp_btn_hold_t = 0.0
	_amp_btn_next_t = 0.0
	_drag = ""
	_actuate_el_id = -1
	_module_hit_node = null
	if circuit != null:
		circuit.touch_scene()


func _amp_repeat_interval(hold_t: float) -> float:
	# Чем дольше держишь — тем короче пауза (как key-repeat / Lanbao).
	var accel_t: float = maxf(hold_t - AMP_REPEAT_DELAY, 0.0)
	var k: float = clampf(accel_t / AMP_ACCEL_SEC, 0.0, 1.0)
	k = k * k
	return lerpf(AMP_INTERVAL_START, AMP_INTERVAL_MIN, k)


func _apply_amp_set_tick(delta_ticks: int) -> void:
	if circuit == null or delta_ticks == 0:
		return
	var el = circuit.get_element(_actuate_el_id)
	if el == null or str(el.kind) != "sensor":
		return
	var cls: String = str(el.sensor_class)
	if cls == "optical":
		IsoOptical.nudge_setpoint(el, delta_ticks)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			IsoOptical.apply_panel(_module_hit_node, el, circuit)
	elif cls == "ultrasonic":
		IsoUltrasonic.nudge_setpoint(el, delta_ticks)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			IsoUltrasonic.apply_display(_module_hit_node, el, circuit)
	else:
		return
	sim_control_changed.emit()


func _tick_amp_btn_hold(dt: float) -> void:
	if _drag != "amp_btn":
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_amp_btn_hold()
		return
	_amp_btn_hold_t += dt
	_amp_btn_next_t -= dt
	if _amp_btn_next_t > 0.0:
		return
	var dir: int = 1 if _amp_btn_name == "BtnPlus" else -1
	_apply_amp_set_tick(dir)
	_amp_btn_next_t = _amp_repeat_interval(_amp_btn_hold_t)


## Камера в движении: мышь (orbit/look/pan) или WASD/пролёт — 3D SubViewport должен быть ALWAYS.
func is_camera_navigating() -> bool:
	if _drag in ["orbit", "look", "pan"]:
		return true
	if _orbit_anim_t > 0.0:
		return true
	# Fly/FPV: иначе FPS «60», а картинка 3D стробится (UPDATE_ONCE раз в N кадров).
	if cam_mode == "fly" or cam_mode == "fpv":
		if _move_vel.length_squared() > 1.0e-8:
			return true
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) \
				or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) \
				or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E) \
				or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN) \
				or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT):
			return true
	return false


func _bind_ext_hover() -> void:
	if _ext_hover_bound or circuit == null:
		return
	if circuit.has_signal("hover_port_changed"):
		circuit.hover_port_changed.connect(_on_circuit_hover_port_changed)
		_ext_hover_bound = true
		# Уже есть наведение со схемы (мышь не была в 3D) — сразу показать.
		if str(circuit.hover_space) == "schematic":
			_apply_schematic_hover_hl()


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
	if circuit == null or not is_inside_tree():
		return
	var wid: int = int(circuit.hover_wire_id)
	if wid >= 0:
		var hose: Node3D = _hose_nodes.get(wid, null)
		if hose != null and is_instance_valid(hose) and hose.is_inside_tree():
			_show_hover_hl_hose(hose)
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
		var hnode: Node3D = hose_hit.get("node", null) as Node3D
		if hnode != null:
			_show_hover_hl_hose(hnode)
		else:
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
	# Винт уставки датчика I/C/компакт-оптика / реле давления (уставка|гистерезис).
	var thr_sens_h: Dictionary = _pick_threshold_screw(origin, dir)
	if not thr_sens_h.is_empty():
		var sid_h: int = int(thr_sens_h.get("id", -1))
		var sroot_h: Node3D = thr_sens_h.get("root", null) as Node3D
		var role_h: String = str(thr_sens_h.get("role", ""))
		var sscrew: Node3D = null
		if sroot_h != null:
			if role_h == "set":
				sscrew = sroot_h.get_node_or_null("SetScrew") as Node3D
			elif role_h == "hyst":
				sscrew = sroot_h.get_node_or_null("HystScrew") as Node3D
			else:
				sscrew = sroot_h.get_node_or_null("ThresholdScrew") as Node3D
		_show_hover_hl_node(sscrew if sscrew != null else sroot_h)
		circuit.set_hover("workshop", sid_h, "", -1)
		if circuit != null:
			var organ: String = "винт уставки"
			if role_h == "hyst":
				organ = "винт гистерезиса (дифференциал)"
			elif role_h == "set":
				organ = "винт уставки срабатывания"
			return "%s\nОрган: %s" % [circuit.element_sim_tip(sid_h), organ]
		return "Датчик · винт уставки"
	# Кнопки панели оптоусилителя.
	var amp_h: Dictionary = _pick_amp_panel_button(origin, dir)
	if not amp_h.is_empty():
		var aid_h: int = int(amp_h.get("id", -1))
		var aroot_h: Node3D = amp_h.get("root", null) as Node3D
		var bname_h: String = str(amp_h.get("btn", ""))
		var bnode_h: Node3D = aroot_h.get_node_or_null(bname_h) as Node3D if aroot_h != null else null
		_show_hover_hl_node(bnode_h if bnode_h != null else aroot_h)
		circuit.set_hover("workshop", aid_h, "", -1)
		var btn_ru: String = bname_h
		match bname_h:
			"BtnPlus":
				btn_ru = "+ (уставка ↑)"
			"BtnMinus":
				btn_ru = "− (уставка ↓)"
			"BtnSet":
				btn_ru = "SET (teach)"
			"BtnMode":
				btn_ru = "MODE (LO/DO)"
		if circuit != null:
			return "%s\nОрган: %s" % [circuit.element_sim_tip(aid_h), btn_ru]
		return "Оптоусилитель · %s" % btn_ru
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
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		# Не требовать Tube под hose: у дверцы Tube на Door, в dense — скрыт.
		var pts: PackedVector3Array = _hose_world_curve_pts(node)
		if pts.size() < 2:
			continue
		var radius: float = float(node.get_meta("tube_radius", 0.0025))
		var box: AABB = _polyline_aabb(pts).grow(radius + 0.006)
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


## AABB полилинии (world).
func _polyline_aabb(pts: PackedVector3Array) -> AABB:
	if pts.is_empty():
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for i in range(1, pts.size()):
		box = box.expand(pts[i])
	return box


## World-полилиния жилы (door-local → world при необходимости).
func _hose_world_curve_pts(hose: Node3D) -> PackedVector3Array:
	if hose == null:
		return PackedVector3Array()
	var pts: PackedVector3Array = hose.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
	if pts.size() >= 2:
		return pts
	pts = hose.get_meta("curve_pts_mesh", PackedVector3Array()) as PackedVector3Array
	if pts.size() >= 2:
		return pts
	pts = hose.get_meta("curve_pts_ortho", PackedVector3Array()) as PackedVector3Array
	if pts.size() >= 2:
		return pts
	# Дверная локаль + кабинетный канал.
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door: Node3D = cab.get_node_or_null("DoorHinge/Door") as Node3D if cab != null else null
	var local_d: PackedVector3Array = PackedVector3Array()
	if hose.has_meta("curve_pts_door_duct_local"):
		local_d = hose.get_meta("curve_pts_door_duct_local") as PackedVector3Array
	elif hose.has_meta("curve_pts_door_local"):
		local_d = hose.get_meta("curve_pts_door_local") as PackedVector3Array
	var out := PackedVector3Array()
	if door != null and local_d.size() >= 2:
		for p in _hose_points_door_to_world(local_d, door):
			out.append(p)
	var cab_pts: PackedVector3Array = hose.get_meta("curve_pts_cab", PackedVector3Array()) as PackedVector3Array
	if cab_pts.is_empty() and hose.has_meta("curve_pts_cab_duct"):
		cab_pts = hose.get_meta("curve_pts_cab_duct") as PackedVector3Array
	for p2 in cab_pts:
		out.append(p2)
	return out


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
	_hide_hover_hose_glow()


func _hide_hover_hl_meshes() -> void:
	_clear_hover_hl_overlays()
	if _hover_hl_mesh_root != null:
		_hover_hl_mesh_root.visible = false


func _ensure_hover_hose_glow() -> void:
	if _hover_hose_glow != null and is_instance_valid(_hover_hose_glow):
		if is_inside_tree() and not _hover_hose_glow.is_inside_tree():
			add_child(_hover_hose_glow)
		return
	_hover_hose_glow = MeshInstance3D.new()
	_hover_hose_glow.name = "HoverHoseGlow"
	_hover_hose_glow_mat = StandardMaterial3D.new()
	_hover_hose_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_hose_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Как hover провода в 2D (янтарный).
	_hover_hose_glow_mat.albedo_color = Color(1.0, 0.82, 0.25, 0.55)
	_hover_hose_glow_mat.emission_enabled = true
	_hover_hose_glow_mat.emission = Color(1.0, 0.78, 0.2)
	_hover_hose_glow_mat.emission_energy_multiplier = 0.85
	_hover_hose_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_hose_glow_mat.no_depth_test = true
	_hover_hose_glow_mat.render_priority = 18
	_hover_hose_glow.material_override = _hover_hose_glow_mat
	_hover_hose_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover_hose_glow.visible = false
	if is_inside_tree():
		add_child(_hover_hose_glow)


func _hide_hover_hose_glow() -> void:
	_hover_hose_glow_id = -1
	if _hover_hose_glow != null and is_instance_valid(_hover_hose_glow):
		_hover_hose_glow.visible = false


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
	if _hover_hl != null and is_instance_valid(_hover_hl):
		# После clear/rebuild узел мог остаться orphan — вернуть в дерево.
		if is_inside_tree() and not _hover_hl.is_inside_tree():
			add_child(_hover_hl)
		if _hover_hl_mesh_root != null and is_instance_valid(_hover_hl_mesh_root) \
				and is_inside_tree() and not _hover_hl_mesh_root.is_inside_tree():
			add_child(_hover_hl_mesh_root)
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
	if is_inside_tree():
		add_child(_hover_hl)
	_hover_hl_mesh_root = Node3D.new()
	_hover_hl_mesh_root.name = "HoverHighlightMeshes"
	_hover_hl_mesh_root.visible = false
	if is_inside_tree():
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
	if not is_inside_tree():
		return
	_ensure_hover_hl()
	if _hover_hl == null or not _hover_hl.is_inside_tree():
		return
	_hide_hover_hl_meshes()
	_hide_hover_hose_glow()
	_hover_hl_sphere.radius = radius
	_hover_hl_sphere.height = radius * 2.0
	_hover_hl.mesh = _hover_hl_sphere
	_hover_hl.global_position = world_pos
	_hover_hl.scale = Vector3.ONE
	_hover_hl.global_basis = Basis.IDENTITY
	_hover_hl.visible = true


## Плоский куб по зеву клеммы: основание ≈ разъём, малая высота вдоль входа провода.
func _show_hover_hl_port(world_pos: Vector3, world_dir: Vector3) -> void:
	if not is_inside_tree():
		return
	_ensure_hover_hl()
	if _hover_hl == null or not _hover_hl.is_inside_tree():
		return
	_hide_hover_hl_meshes()
	_hide_hover_hose_glow()
	_hover_hl.mesh = _hover_hl_box
	var n: Vector3 = world_dir.normalized() if world_dir.length_squared() > 1.0e-8 else Vector3.UP
	_hover_hl.global_basis = _basis_y_from_normal(n)
	# Чуть наружу по оси входа — без z-fighting с зевом.
	_hover_hl.global_position = world_pos + n * 0.0009
	_hover_hl.scale = _port_hit_size()
	_hover_hl.visible = true


func _port_hit_size() -> Vector3:
	# Чуть больше зева (~1.25×), без «липкого» наведения на соседние клеммы.
	return Vector3(0.0080, 0.0042, 0.0072)


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
	if not is_inside_tree():
		return
	_ensure_hover_hl()
	_hide_hover_hose_glow()
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		clear_hover_highlight()
		return
	var sid: int = node.get_instance_id()
	if sid != _hover_hl_src_id or _hover_hl_src_pairs.is_empty():
		_rebuild_hover_hl_meshes(node)
	if _hover_hl_src_pairs.is_empty():
		_show_hover_hl_sphere(node.global_position, 0.035)
		return
	if _hover_hl != null:
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
		# Dense batch: Tube был скрыт — вернуть после hover.
		if bool(pair.get("force_vis", false)):
			src.visible = false
	_hover_hl_src_pairs.clear()
	_hover_hl_src_id = 0


## Подсветка всей жилы: glow-трубка по world curve (dense/Door/TubeCab — без overlay).
func _show_hover_hl_hose(hose: Node3D) -> void:
	if not is_inside_tree():
		return
	_ensure_hover_hl()
	_ensure_hover_hose_glow()
	if hose == null or not is_instance_valid(hose) or not hose.is_inside_tree():
		clear_hover_highlight()
		return
	if _hover_hl != null:
		_hover_hl.visible = false
	_clear_hover_hl_overlays()
	if _hover_hl_mesh_root != null:
		_hover_hl_mesh_root.visible = false
	var pts: PackedVector3Array = _hose_world_curve_pts(hose)
	if pts.size() < 2:
		_hide_hover_hose_glow()
		_show_hover_hl_sphere(hose.global_position, 0.006)
		return
	if _hover_hose_glow == null or not _hover_hose_glow.is_inside_tree():
		return
	var hid: int = hose.get_instance_id()
	var hr: float = maxf(float(hose.get_meta("tube_radius", 0.0025)) * 1.65, 0.0022)
	# Не пересобирать меш, если та же жила (частый motion на схеме).
	if hid == _hover_hose_glow_id and _hover_hose_glow.visible and _hover_hose_glow.mesh != null:
		return
	var glow_pts: PackedVector3Array = pts
	if glow_pts.size() > 48:
		glow_pts = _decimate_polyline(glow_pts, 48)
	_hover_hose_glow.mesh = _build_tube_mesh(glow_pts, hr, 7)
	_hover_hose_glow.global_transform = Transform3D.IDENTITY
	_hover_hose_glow.visible = true
	_hover_hose_glow_id = hid


## Проредить полилинию до max_pts (концы сохраняем).
func _decimate_polyline(pts: PackedVector3Array, max_pts: int) -> PackedVector3Array:
	if pts.size() <= max_pts or max_pts < 2:
		return pts
	var out := PackedVector3Array()
	var last: int = pts.size() - 1
	for i in max_pts:
		var idx: int = int(round(float(i) * float(last) / float(max_pts - 1)))
		out.append(pts[idx])
	return out


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
	var frame_n: int = Engine.get_process_frames()
	var cam_moved: bool = false
	match cam_mode:
		"fpv":
			_fpv_settle_height(dt)
			_fpv_move(dt)
			cam_moved = true
		"fly":
			cam_moved = _fly_move(dt)
		_:
			# Орбита: только анимация куба; WASD сюда больше не двигает фокус.
			if _orbit_anim_t > 0.0:
				_step_orbit_anim(dt)
				cam_moved = true
	# Камера: только при движении / пока mesh ещё собирается.
	if cam_moved or not _hoses_ready_cached:
		_place_camera()
	# Автоповтор +/− усилителя — до idle-skip, иначе удержание «молчит» вне Run.
	if _drag == "amp_btn":
		_tick_amp_btn_hold(dt)
	if circuit == null:
		return
	# Hover со схемы → 3D: bind без ожидания мыши в 3D-панели.
	_bind_ext_hover()
	# Вне Run тоже крутим рукоятку отсечного к цели (клик в 3D/схеме).
	if not circuit.running:
		for el_z in circuit.elements:
			if el_z != null and str(el_z.kind) == "accessory" and str(el_z.accessory_class) == "shutoff":
				AccLib.advance_shutoff(el_z, dt)
	var cyl_moving: bool = circuit.running and _any_cylinder_moving()
	# Не вызывать _hoses_are_ready() каждый кадр — O(wires) по meta/mesh.
	# Add/remove провода: сразу сбросить кэш (иначе до 45 кадров «готово» без новой жилы).
	var wcount_now: int = circuit.wires.size()
	if wcount_now != int(_hose_known_ids.size()) and not _hose_known_ids.is_empty():
		_hoses_ready_cached = false
	elif _hose_known_ids.is_empty() and wcount_now > 0 and _hose_nodes.size() < wcount_now:
		_hoses_ready_cached = false
	var hoses_ready: bool = _hoses_ready_cached
	if not hoses_ready or _hose_heavy_pending or (frame_n % 45) == 0:
		hoses_ready = _hoses_are_ready()
		_hoses_ready_cached = hoses_ready
	var cab_proc: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_anim: bool = cab_proc != null and IsoCabinet.is_door_animating(cab_proc)
	# Idle electro: полный skip — machines/cab/hoses не трогаем, пока нет dirty.
	# Дверца: нельзя skip — иначе flex/batch/ensure не крутятся, жилы повисают.
	# cam_moved (WASD) НЕ должен гонять sync машин — иначе рывки элементов.
	if not circuit.running and hoses_ready and _build_queue.is_empty() \
			and not _drag_locks_hover() and not _hose_hq_pending \
			and not _elec_sep_dirty and not door_anim and not _hose_heavy_pending \
			and _hose_wire_dirty.is_empty():
		return
	# При Run: реже full sync (плотный щит иначе ~30–40 FPS).
	var dense_run: bool = _dense_elec_lod()
	var run_skip_n: int = 3 if dense_run else 2
	if circuit.running and (frame_n % run_skip_n) != 0 and not cyl_moving and not door_anim \
			and hoses_ready and _build_queue.is_empty():
		return
	var t0: int = Time.get_ticks_usec() if _perf_hud else 0
	# В симуляции — лёгкий апдейт поз/штока; полный сиг — только в редактировании.
	# Idle electro: машины не двигаются — не гонять O(elements) sig каждый кадр.
	# Дверца: модули на DoorGrid крутятся сами — не гонять O(elements) каждый кадр (фриз/ФПС).
	var need_machines: bool = not door_anim
	if need_machines:
		if not circuit.running and hoses_ready and _build_queue.is_empty() \
				and not _drag_locks_hover() and not _hose_hq_pending:
			need_machines = (frame_n % 15) == 0
		elif circuit.running and dense_run and not cyl_moving:
			# Плотный electro: state модулей редко меняет 3D-mesh.
			need_machines = (frame_n % 6) == 0
	if need_machines:
		_sync_machines(circuit.running)
	if _perf_hud:
		_perf_ms_machines = float(Time.get_ticks_usec() - t0) * 0.001
		t0 = Time.get_ticks_usec()
	# Щит: при анимации дверцы layout не нужен (полотно+модули уже в иерархии).
	var need_cab: bool = (not door_anim) and (cab_proc == null or not _build_queue.is_empty())
	if not need_cab and not door_anim:
		if circuit.running:
			need_cab = (frame_n % (12 if dense_run else 8)) == 0
		else:
			# Плотный щит: ensure редко — layout_occ_sig early-out всё равно дешёвый, но не бесплатный.
			need_cab = (frame_n % 30) == 0 or _hose_hq_pending
	if need_cab:
		IsoCabinet.ensure(_machines, circuit)
	# Трубки: при Run реже; в idle edit — только dirty / редкий refresh.
	var need_hoses: bool = true
	if door_anim:
		need_hoses = true
	elif not hoses_ready or not _build_queue.is_empty() or _hose_hq_pending:
		need_hoses = true
	elif _drag in ["din_module", "door_module"]:
		# Ghost-drag: жилы к старому месту, без mid-drag rebuild.
		need_hoses = false
	elif _drag_locks_hover():
		need_hoses = true
	elif circuit.running:
		if cyl_moving:
			need_hoses = (frame_n % 3) == 0
		elif bool(circuit.pressure_viz):
			need_hoses = (frame_n % 6) == 0
		elif dense_run:
			# Electro-only dense: жилы статичны в Run — не гонять O(W) каждый тик.
			need_hoses = (frame_n % 45) == 0
		else:
			need_hoses = (frame_n % 20) == 0
	else:
		# Edit idle: после сборки mesh — не трогать жилы, пока нет dirty/HQ.
		need_hoses = (
			(not hoses_ready) or _hose_hq_pending or _elec_sep_dirty
			or not _hose_wire_dirty.is_empty()
		)
		# Suspended batch: после add не гонять O(W) каждый кадр — только таймер.
		if _hose_batch_suspended and hoses_ready and _hose_wire_dirty.is_empty() \
				and not _hose_hq_pending and not _elec_sep_dirty:
			_hose_heavy_idle_frames += 1
			if _hose_heavy_idle_frames >= HOSE_HEAVY_IDLE_FRAMES:
				need_hoses = true # один кадр: вернуть dense-batch
			else:
				need_hoses = false
		elif not need_hoses:
			_hose_idle_skip = 0
		else:
			_hose_idle_skip += 1
			var urgent_hoses: bool = (not hoses_ready) or not _hose_wire_dirty.is_empty()
			if hoses_ready and not urgent_hoses and _hose_idle_skip < 2:
				need_hoses = false
			elif need_hoses:
				_hose_idle_skip = 0
	if need_hoses:
		_sync_hoses()
		hoses_ready = _hoses_are_ready()
		_hoses_ready_cached = hoses_ready
	if _perf_hud:
		_perf_ms_hoses = float(Time.get_ticks_usec() - t0) * 0.001
	# Тепловизор: отдельный проход (корпуса + жилы + DIN), не зависит от dirty жил.
	var tv_every: int = 2 if circuit.running else 3
	if bool(circuit.thermal_viz) or _thermal_was_on:
		if (frame_n % tv_every) == 0 or bool(circuit.thermal_viz) != _thermal_was_on:
			_sync_thermal_viz_pass()
	if circuit.running or circuit.sim_time > 0.0:
		# Каждый кадр — иначе конусы «стробят» при движении.
		if bool(circuit.pressure_viz):
			_sync_flows()
		else:
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


func get_camera_world_pos() -> Vector3:
	if _camera != null and is_instance_valid(_camera):
		return _camera.global_position
	if cam_mode == "fpv":
		return _fpv_pos
	if cam_mode == "fly":
		return _fly_pos
	return _target


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
	if _drag == "gizmo" and circuit != null and circuit.has_method("end_history_group"):
		circuit.end_history_group()
	_gizmo_moved = false
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
func _fly_move(dt: float) -> bool:
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
		return false
	_fly_pos += _move_vel * dt
	_clamp_fly_pos()
	return true


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
	# Dense: пол уже скрыт — не трогать материалы каждый кадр.
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
			# Цилиндры / поворотные — каждый кадр; остальное — раз в 3 кадра.
			if str(el.kind) != "cylinder" and str(el.kind) != "rotary_cylinder" \
					and str(el.kind) != "air_motor" and str(el.kind) != "sensor" \
					and str(el.kind) != "opto_tip" \
					and (frame % 3) != 0:
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
		elif acc_sig == "shutoff":
			acc_sig = "shutoff:v2"
		elif acc_sig == "and_valve":
			acc_sig = "and_valve:v3"
		elif acc_sig == "relief":
			acc_sig = "relief:v2:%s" % str(el.port_3)
		elif acc_sig == "reservoir":
			acc_sig = "reservoir:v2:%.2f:%d" % [float(el.volume_l), int(el.reservoir_ports)]
		var fit_sig: String = "%s:%.1f:%.1f:%s" % [
			str(el.fitting_id) if el.get("fitting_id") != null else "",
			float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0,
			float(el.tube_od_b_mm) if el.get("tube_od_b_mm") != null else 0.0,
			str(el.junction_style) if el.get("junction_style") != null else "",
		]
		var rotary_sig: String = "%s:%.0f:%.0f" % [
			str(el.get("rotary_class") if el.get("rotary_class") != null else ""),
			float(el.get("angle_max_deg") if el.get("angle_max_deg") != null else 180.0),
			float(el.bore_mm),
		]
		# ПМ: stall меняет масштаб всего 3D — обязателен в sig, иначе меш не пересоберётся.
		# v10: глушитель/штуцер на in и exhaust по отдельности (port_5/port_3 уже в sig).
		var motor_sig: String = "v10:%.3f" % [
			float(el.get("torque_nm_at_6bar") if el.get("torque_nm_at_6bar") != null else 0.0),
		]
		var sensor_sig: String = "%s:%.1f:%.1f:%.1f:%s:%s:%s" % [
			str(el.get("sensor_class") if el.get("sensor_class") != null else ""),
			float(el.get("body_od_mm") if el.get("body_od_mm") != null else 12.0),
			float(el.get("sense_range_mm") if el.get("sense_range_mm") != null else 4.0),
			float(el.stroke_mm),
			str(el.get("output_type") if el.get("output_type") != null else "npn"),
			str(el.get("supply_mode") if el.get("supply_mode") != null else "24dc"),
			str(el.get("opto_role") if el.get("opto_role") != null else ""),
		]
		var sig := "%s|%s|%.3f|%.3f|%.3f|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%.2f|%s|%.2f|%.2f|%d|%d|%s|%s|%s|%s|%s|%.2f|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
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
			spool_sig, junc_sig, acc_sig, fit_sig, rotary_sig, motor_sig, sensor_sig,
		]
		# v5: гильза CSG + поле магнита (длина 2/3 поршня, радиус +1/7).
		if str(el.kind) == "cylinder":
			sig = "%s|cap_gal:v5" % sig
		# v3: масштаб корпуса + пояски/ход золотника (перекрытие каналов).
		if str(el.kind) == "valve":
			sig = "%s|valve_body:v3" % sig
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
			elif el.kind == "rotary_cylinder":
				info = IsoRotary.build(built, el)
			elif el.kind == "air_motor":
				info = IsoAirMotor.build(built, el)
			elif el.kind == "sensor":
				info = _build_sensor_3d(built, el)
			elif el.kind == "opto_tip":
				info = IsoOptoTip.build(built, el)
			else:
				info = Iso.build(built, el)
			built.set_meta("ports", info["ports"])
			built.set_meta("dirs", info["dirs"])
			# Всегда: выключить галереи/вернуть opaque, если рентген выкл.
			if el.kind == "rotary_cylinder":
				IsoRotary.apply_xray(built, xray)
			elif el.kind == "air_motor":
				IsoAirMotor.apply_xray(built, xray)
			else:
				Iso.apply_xray(built, xray)
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
	if el.kind == "accessory" and str(el.accessory_class) in ["throttle", "throttle_fixed", "throttle_check", "throttle_check_fixed", "check", "regulator", "shuttle", "and_valve", "quick_exhaust", "shutoff", "relief"]:
		var p1v: float = float(el.port_press.get("1", 101325.0)) if el.get("port_press") != null else 101325.0
		var p2v: float = float(el.port_press.get("2", 101325.0)) if el.get("port_press") != null else 101325.0
		var open_sig: String = "%.3f|%.2f|%.0f|%.0f|%d|%s" % [
			float(el.opening), float(el.set_pressure_bar), p1v, p2v, int(el.valve_pos),
			"1" if bool(el.pressed) else "0"
		]
		if (not sim_light) or str(root.get_meta("rt_open", "")) != open_sig:
			if str(el.accessory_class) == "throttle":
				IsoThrottle.apply_opening(root, el)
			elif str(el.accessory_class) in ["throttle_check", "throttle_check_fixed"]:
				IsoThrottleCheck.apply_opening(root, el)
			elif str(el.accessory_class) == "check":
				IsoCheck.apply_opening(root, el)
			elif str(el.accessory_class) == "shuttle":
				IsoShuttle.apply_opening(root, el)
			elif str(el.accessory_class) == "and_valve":
				IsoAnd.apply_opening(root, el)
			elif str(el.accessory_class) == "quick_exhaust":
				IsoQuickExhaust.apply_opening(root, el)
			elif str(el.accessory_class) == "relief":
				IsoRelief.apply_state(root, el)
			elif str(el.accessory_class) == "shutoff":
				IsoShutoff.apply_opening(root, el)
			elif str(el.accessory_class) == "regulator":
				IsoRegulator.apply_knob(root, el)
			root.set_meta("rt_open", open_sig)
	# CSG → mesh: повторно применить рентген (вкл/выкл) после bake (арматура, переходник…).
	if str(el.kind) in ["accessory", "junction", "valve", "cylinder", "rotary_cylinder", "air_motor"] \
			and not bool(root.get_meta("accessory_regulator", false)):
		var xray_pending: bool = not bool(root.get_meta("xray_ok", false))
		if not xray_pending:
			for ch in root.get_children():
				if ch is CSGCombiner3D or str(ch.name).begins_with("CSG_"):
					xray_pending = true
					break
		if xray_pending and (frame % 6) == 0:
			if el.kind == "rotary_cylinder":
				IsoRotary.apply_xray(root, xray)
			elif el.kind == "air_motor":
				IsoAirMotor.apply_xray(root, xray)
			else:
				Iso.apply_xray(root, xray)
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
	if el.kind == "rotary_cylinder":
		IsoRotary.apply_state(root, el)
	elif el.kind == "air_motor":
		IsoAirMotor.apply_state(root, el)
	elif el.kind == "sensor":
		_sync_sensor_runtime(root, el)
	elif el.kind == "opto_tip":
		_sync_opto_tip_runtime(root, el)
	if el.kind == "cylinder":
		var viz_mag: bool = circuit != null and bool(circuit.sensor_field_viz)
		var mag_active: bool = false
		if viz_mag and circuit != null:
			for s in circuit.elements:
				if s == null or str(s.kind) != "sensor":
					continue
				if str(s.sensor_class) == "reed" and bool(s.sensor_target):
					mag_active = true
					break
		Iso.apply_magnet_field_viz(root, viz_mag, mag_active, el)
	if el.kind == "cylinder" and str(el.get("spring_side") if el.get("spring_side") != null else "none") != "none":
		if (not sim_light) or (frame % 2) == 0:
			Iso.update_spring(root, el)
			var spring_n := root.get_node_or_null("Spring")
			if spring_n:
				Iso.apply_xray(spring_n, xray)
	var needle := root.get_node_or_null("Needle")
	if needle and el.kind == "source":
		var bar: float = float(el.pressure_bar)
		var link = circuit.wire_on(el.id, "out")
		if link != null and circuit.sim_time > 0.0:
			bar = (link.pressure - ATM) / 1.0e5
		needle.rotation_degrees = Vector3(0, 0, lerpf(50.0, -230.0, clampf(bar / 10.0, 0.0, 1.0)))
	# Pressure viz — реже при Run. Тепловизор перекрывает (отдельный pass).
	var pviz_every: int = 4 if sim_light else 2
	if (frame % pviz_every) == 0 and str(el.kind) in [
		"source", "junction", "accessory", "cylinder", "rotary_cylinder", "air_motor", "valve"
	]:
		if bool(circuit.thermal_viz):
			_apply_pressure_viz_root(root, el, false, -1.0)
		else:
			_apply_pressure_viz_root(root, el, bool(circuit.pressure_viz), pviz_max)


## Шкала для UI-легенды тепловизора.
func thermal_legend_range() -> Dictionary:
	return _thermal_range.duplicate()


## Режим «ТЕПЛОВИЗОР»: окраска корпусов/жил/щита по условной °C.
func _sync_thermal_viz_pass() -> void:
	if circuit == null:
		return
	var on: bool = bool(circuit.thermal_viz)
	if on:
		# Без Play — мгновенный стационар; при Run динамика идёт из Circuit.step.
		if not bool(circuit.running):
			ThermalViz.advance(circuit, 0.0, true)
		_thermal_range = ThermalViz.scene_range_c(circuit)
	var t_min: float = float(_thermal_range.get("min", 20.0))
	var t_max: float = float(_thermal_range.get("max", 22.0))
	var t_amb: float = float(_thermal_range.get("ambient", 20.0))
	# Полевые машины / зонды.
	for id in _records.keys():
		var rec = _records[id]
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null:
			continue
		var el = circuit.get_element(int(id))
		if el == null:
			continue
		if on and str(el.kind) == "cylinder":
			_apply_thermal_viz_cylinder(root, on, el, t_min, t_max)
		else:
			var t_c: float = ThermalViz.element_temp_c(circuit, el) if on else 0.0
			var tint: Color = ThermalViz.color_for_t(t_c, t_min, t_max) if on else Color.WHITE
			_apply_thermal_viz_root(root, on, tint)
	# Щит: модули — своя T; DIN/короба/дверца/корпус — T щита.
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab != null:
		var t_cab: float = ThermalViz.cabinet_shell_temp_c(circuit) if on else t_amb
		var tint_cab: Color = ThermalViz.color_for_t(t_cab, t_min, t_max) if on else Color.WHITE
		for mod in IsoCabinet.iter_modules(cab):
			if mod == null or not is_instance_valid(mod):
				continue
			var mid: int = int(mod.get_meta("el_id", -1)) if mod.has_meta("el_id") else -1
			if mid < 0:
				var nm: String = str(mod.name)
				if nm.begins_with("E") or nm.begins_with("M"):
					mid = int(nm.substr(1)) if nm.substr(1).is_valid_int() else -1
			var el_m = circuit.get_element(mid) if mid >= 0 else null
			var t_m: float = ThermalViz.element_temp_c(circuit, el_m) if on and el_m != null else t_cab
			var tint_m: Color = ThermalViz.color_for_t(t_m, t_min, t_max) if on else Color.WHITE
			_apply_thermal_viz_root(mod as Node3D, on, tint_m)
		# Пассивные части щита (не Modules): корпус, DIN, короба, дверца, кабели питания.
		for cab_ch in cab.get_children():
			if cab_ch == null or not (cab_ch is Node3D):
				continue
			var cnm: String = str(cab_ch.name)
			if cnm == "Modules" or cnm == "Galleries" or cnm == "FlowBridges":
				continue
			if cnm == "DoorHinge":
				_apply_thermal_cabinet_door(cab_ch as Node3D, on, tint_cab, t_min, t_max)
				continue
			_apply_thermal_viz_root(cab_ch as Node3D, on, tint_cab)
	# Жилы / трубки — весь hose-узел (Tube/TubeCab/гильзы/НШВИ).
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var wire = circuit.get_wire(int(wid)) if circuit.has_method("get_wire") else null
		if wire == null:
			for w in circuit.wires:
				if w != null and int(w.id) == int(wid):
					wire = w
					break
		if wire == null:
			continue
		var tw: float = ThermalViz.wire_temp_c(circuit, wire) if on else t_amb
		var tint_w: Color = ThermalViz.color_for_t(tw, t_min, t_max) if on else Color.WHITE
		_apply_thermal_viz_root(node, on, tint_w)
		# Дверная жила могла уехать на Door — Tube уже не под hose.
		var door_b: Node3D = _hose_cabinet_door()
		if door_b != null:
			var tube_dw: MeshInstance3D = _hose_find_tube(node, door_b)
			if tube_dw != null and tube_dw.get_parent() != node:
				_apply_thermal_viz_root(tube_dw, on, tint_w)
	for sid in _sensor_sheath_nodes.keys():
		var snode: Node3D = _sensor_sheath_nodes[sid] as Node3D
		if snode == null or not is_instance_valid(snode):
			continue
		var sel = circuit.get_element(int(sid))
		var ts: float = ThermalViz.element_temp_c(circuit, sel) if on and sel != null else t_amb
		var tint_s: Color = ThermalViz.color_for_t(ts, t_min, t_max) if on else Color.WHITE
		_apply_thermal_viz_root(snode, on, tint_s)
	_thermal_was_on = on


## Дверца щита: полотно/короб — T щита; модули на DoorGrid уже в iter_modules.
func _apply_thermal_cabinet_door(
	hinge: Node3D, on: bool, tint_cab: Color, t_min: float, t_max: float
) -> void:
	if hinge == null:
		return
	var _tm: float = t_min
	var _tx: float = t_max
	for ch in hinge.get_children():
		if ch == null or not (ch is Node3D):
			continue
		if str(ch.name) == "Door":
			for dch in ch.get_children():
				if dch == null or not (dch is Node3D):
					continue
				if str(dch.name) == "DoorGrid":
					continue # модули — отдельно
				_apply_thermal_viz_root(dch as Node3D, on, tint_cab)
		else:
			_apply_thermal_viz_root(ch as Node3D, on, tint_cab)


func _apply_thermal_viz_root(root: Node3D, on: bool, tint: Color) -> void:
	if root == null:
		return
	var xr_sig: String = "1" if xray else "0"
	if root.has_meta("tviz_last_on") and root.has_meta("tviz_last_tint") and root.has_meta("tviz_last_xr"):
		if bool(root.get_meta("tviz_last_on")) == on \
				and (root.get_meta("tviz_last_tint") as Color).is_equal_approx(tint) \
				and str(root.get_meta("tviz_last_xr")) == xr_sig:
			return
	root.set_meta("tviz_last_on", on)
	root.set_meta("tviz_last_tint", tint)
	root.set_meta("tviz_last_xr", xr_sig)
	_apply_thermal_viz_node(root, on, tint, "")


func _apply_thermal_viz_cylinder(root: Node3D, on: bool, el, t_min: float, t_max: float) -> void:
	if root == null:
		return
	var parts: Dictionary = ThermalViz.cylinder_part_temps_c(circuit, el) if on else {}
	var sig: String = "off"
	if on:
		var bits: PackedStringArray = PackedStringArray()
		for k in ThermalViz.CYL_PART_KEYS:
			bits.append("%.1f" % float(parts.get(k, 0.0)))
		sig = "|".join(bits)
	var xr_sig: String = "1" if xray else "0"
	if root.has_meta("tviz_cyl_sig") and root.has_meta("tviz_last_on") and root.has_meta("tviz_last_xr"):
		if bool(root.get_meta("tviz_last_on")) == on \
				and str(root.get_meta("tviz_cyl_sig")) == sig \
				and str(root.get_meta("tviz_last_xr")) == xr_sig:
			return
	root.set_meta("tviz_last_on", on)
	root.set_meta("tviz_cyl_sig", sig)
	root.set_meta("tviz_last_xr", xr_sig)
	_apply_thermal_viz_node_parts(root, on, parts, t_min, t_max)


func _thermal_part_of(gi: GeometryInstance3D) -> String:
	if gi.has_meta("thermal_part"):
		return str(gi.get_meta("thermal_part"))
	var nm: String = str(gi.name)
	if nm.contains("Barrel") or nm.begins_with("Mesh_window"):
		# Cap/Gasket тоже могут быть window — ниже по имени.
		pass
	if nm.contains("Gasket"):
		return "gland"
	if nm.contains("CapCSG") or nm.begins_with("Cap"):
		return "cap"
	if nm.contains("Barrel"):
		return "barrel"
	var role: String = str(gi.get_meta("xray_role", "shell"))
	var p: Node = gi.get_parent()
	var pnm: String = str(p.name) if p != null else ""
	if pnm == "Rod" or nm == "Rod":
		if role == "internal":
			return "piston"
		return "rod"
	if role == "window":
		return "barrel"
	if role == "internal":
		return "piston"
	return "shell"


func _apply_thermal_viz_node_parts(
	node: Node, on: bool, parts: Dictionary, t_min: float, t_max: float
) -> void:
	if str(node.name) == "Galleries" or str(node.name) == "FlowBridges":
		return
	if node is Label3D:
		for ch0 in node.get_children():
			_apply_thermal_viz_node_parts(ch0, on, parts, t_min, t_max)
		return
	if node is GeometryInstance3D and (node is MeshInstance3D or node is CSGShape3D):
		var gi := node as GeometryInstance3D
		var part: String = _thermal_part_of(gi)
		var t_c: float = float(parts.get(part, parts.get("barrel", 20.0))) if on else 0.0
		var tint: Color = ThermalViz.color_for_t(t_c, t_min, t_max) if on else Color.WHITE
		_paint_thermal_gi(gi, on, tint)
	for ch in node.get_children():
		_apply_thermal_viz_node_parts(ch, on, parts, t_min, t_max)


func _apply_thermal_viz_node(node: Node, on: bool, tint: Color, _part_hint: String = "") -> void:
	if str(node.name) == "Galleries" or str(node.name) == "FlowBridges":
		return
	if node is Label3D:
		for ch0 in node.get_children():
			_apply_thermal_viz_node(ch0, on, tint, _part_hint)
		return
	if node is GeometryInstance3D and (node is MeshInstance3D or node is CSGShape3D):
		_paint_thermal_gi(node as GeometryInstance3D, on, tint)
	for ch in node.get_children():
		_apply_thermal_viz_node(ch, on, tint, _part_hint)


## Окраска одного GI: при рентгене window — tint на ghost (как pressure_viz).
func _paint_thermal_gi(gi: GeometryInstance3D, on: bool, tint: Color) -> void:
	if bool(gi.get_meta("flow_viz", false)) or bool(gi.get_meta("field_viz", false)):
		return
	var role: String = str(gi.get_meta("xray_role", "shell"))
	if not gi.has_meta("tviz_base_mat"):
		var cand: StandardMaterial3D = null
		if gi.has_meta("xray_base_mat") and gi.get_meta("xray_base_mat") is StandardMaterial3D:
			cand = gi.get_meta("xray_base_mat") as StandardMaterial3D
		elif gi.has_meta("pviz_base_mat") and gi.get_meta("pviz_base_mat") is StandardMaterial3D:
			cand = gi.get_meta("pviz_base_mat") as StandardMaterial3D
		elif gi.material_override is StandardMaterial3D:
			cand = gi.material_override as StandardMaterial3D
		elif gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var sm = mi.mesh.surface_get_material(0)
				if sm is StandardMaterial3D:
					cand = sm as StandardMaterial3D
		if cand == null:
			cand = StandardMaterial3D.new()
			cand.albedo_color = Color(0.55, 0.58, 0.62)
			cand.roughness = 0.7
		if cand != null and not Iso._mat_is_xray_ghost(cand):
			gi.set_meta("tviz_base_mat", cand)
	if on and gi.has_meta("tviz_base_mat"):
		var base_m: StandardMaterial3D = gi.get_meta("tviz_base_mat") as StandardMaterial3D
		var painted: StandardMaterial3D = null
		if gi.has_meta("tviz_painted"):
			painted = gi.get_meta("tviz_painted") as StandardMaterial3D
		else:
			painted = base_m.duplicate() as StandardMaterial3D
			gi.set_meta("tviz_painted", painted)
		painted.albedo_color = Color(tint.r, tint.g, tint.b, base_m.albedo_color.a)
		painted.metallic = 0.0
		painted.roughness = 0.85
		painted.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		painted.emission_enabled = false
		if xray and role == "window":
			# Красим отдельный ghost, не подменяя xray_ghost painted'ом навсегда.
			var ghost_t: StandardMaterial3D = painted.duplicate() as StandardMaterial3D
			if gi.has_meta("xray_ghost") and gi.get_meta("xray_ghost") != painted:
				var src_g: StandardMaterial3D = gi.get_meta("xray_ghost") as StandardMaterial3D
				if src_g != null:
					ghost_t = src_g.duplicate() as StandardMaterial3D
			ghost_t.albedo_color = Color(tint.r, tint.g, tint.b, 0.22)
			ghost_t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_t.metallic = 0.0
			ghost_t.roughness = 0.85
			ghost_t.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gi.set_meta("tviz_ghost", ghost_t)
			gi.material_override = ghost_t
		else:
			gi.material_override = painted
	elif not on and gi.has_meta("tviz_base_mat"):
		var base_rest: StandardMaterial3D = gi.get_meta("tviz_base_mat") as StandardMaterial3D
		if xray and role == "window" and gi.has_meta("xray_ghost"):
			gi.material_override = gi.get_meta("xray_ghost")
		elif xray and role == "internal" and gi.has_meta("xray_lit"):
			gi.material_override = gi.get_meta("xray_lit")
		else:
			gi.material_override = base_rest


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
	# Galleries/FlowBridges — отдельная подсветка путей, не красить «давлением корпуса».
	if str(node.name) == "Galleries" or str(node.name) == "FlowBridges":
		return
	if node is GeometryInstance3D and (node is MeshInstance3D or node is CSGShape3D):
		var gi := node as GeometryInstance3D
		if bool(gi.get_meta("flow_viz", false)) or bool(gi.get_meta("field_viz", false)):
			# field_viz = SenseZone / MagnetField — не красить и не трогать alpha.
			return
		# control (рычаг/винт КП) не красим — иначе рычаг «пропадает» в цвет давления.
		var role: String = str(gi.get_meta("xray_role", "shell"))
		if role != "control" and (gi.material_override is StandardMaterial3D or gi.has_meta("pviz_base_mat")):
			if not gi.has_meta("pviz_base_mat"):
				# Не запоминать ghost рентгена как базу — иначе alpha «плывёт».
				var cand: StandardMaterial3D = null
				if gi.has_meta("xray_base_mat") and gi.get_meta("xray_base_mat") is StandardMaterial3D:
					cand = gi.get_meta("xray_base_mat") as StandardMaterial3D
				elif gi.material_override is StandardMaterial3D:
					cand = gi.material_override as StandardMaterial3D
				if cand != null and not Iso._mat_is_xray_ghost(cand):
					gi.set_meta("pviz_base_mat", cand)
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
				if xray and role == "window":
					# Красим отдельный ghost, не подменяя xray_ghost painted'ом навсегда.
					var ghost_p: StandardMaterial3D = null
					if gi.has_meta("xray_ghost") and gi.get_meta("xray_ghost") != painted:
						ghost_p = gi.get_meta("xray_ghost") as StandardMaterial3D
					if ghost_p == null:
						ghost_p = base_m.duplicate() as StandardMaterial3D
						gi.set_meta("xray_ghost", ghost_p)
					ghost_p.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					ghost_p.albedo_color = Color(tint.r, tint.g, tint.b, 0.22)
					ghost_p.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					ghost_p.cull_mode = BaseMaterial3D.CULL_DISABLED
					ghost_p.metallic = minf(float(base_m.metallic), 0.25)
					if not gi.has_meta("xray_base_mat"):
						gi.set_meta("xray_base_mat", base_m)
					gi.material_override = ghost_p
				else:
					# Сброс ghost-режима, если рентген выключен (painted переиспользуется).
					painted.transparency = base_m.transparency
					painted.depth_draw_mode = base_m.depth_draw_mode
					painted.cull_mode = base_m.cull_mode
					gi.material_override = painted
			elif not on and gi.has_meta("pviz_base_mat"):
				# Не снимать рентген вместе с давлением.
				if xray and role == "window" and gi.has_meta("xray_ghost"):
					var g_off: StandardMaterial3D = gi.get_meta("xray_ghost") as StandardMaterial3D
					# Сбросить tint давления с ghost → цвет базы + alpha окна.
					var base_off: StandardMaterial3D = gi.get_meta("pviz_base_mat") as StandardMaterial3D
					if g_off != null and base_off != null:
						var bc: Color = base_off.albedo_color
						g_off.albedo_color = Color(bc.r, bc.g, bc.b, 0.22)
					gi.material_override = g_off if g_off != null else gi.get_meta("pviz_base_mat")
				elif xray and role == "internal" and gi.has_meta("xray_lit"):
					gi.material_override = gi.get_meta("xray_lit")
				else:
					var base_rest: StandardMaterial3D = gi.get_meta("pviz_base_mat") as StandardMaterial3D
					gi.material_override = base_rest
					# Если на слоте залип ghost — вернуть opaque базу.
					if base_rest != null and gi.material_override is StandardMaterial3D \
							and Iso._mat_is_xray_ghost(gi.material_override as StandardMaterial3D):
						gi.material_override = base_rest
	for ch in node.get_children():
		_apply_pressure_viz_node(ch, on, tint)


func _build_sensor_3d(parent: Node3D, el) -> Dictionary:
	match str(el.sensor_class):
		"reed":
			return IsoReed.build(parent, el)
		"capacitive":
			return IsoCapacitive.build(parent, el)
		"optical":
			if str(el.optical_form) == "compact":
				return IsoOpticalCompact.build(parent, el)
			return IsoOptical.build(parent, el)
		"ultrasonic":
			return IsoUltrasonic.build(parent, el)
		"pressure_switch":
			return IsoPressureSwitch.build(parent, el)
		"pressure_tx":
			return IsoPressureTx.build(parent, el)
		"rtd":
			return IsoRtd.build(parent, el)
		"inductive", "":
			return IsoInductive.build(parent, el)
		_:
			# Заглушка под другие классы волны A/B/C.
			return IsoInductive.build(parent, el)


func _sync_sensor_runtime(root: Node3D, el) -> void:
	if root == null or el == null:
		return
	var viz_on: bool = circuit != null and bool(circuit.sensor_field_viz)
	match str(el.sensor_class):
		"pressure_switch":
			IsoPressureSwitch.apply_led(root, el)
			IsoPressureSwitch.apply_adjustments(root, el)
		"pressure_tx":
			IsoPressureTx.apply_led(root, el)
			IsoPressureTx.apply_membrane(root, el, circuit)
			var xr_sig: String = "1" if xray else "0"
			if str(root.get_meta("pt_xray", "")) != xr_sig:
				IsoPressureTx.apply_xray(root, xray)
				root.set_meta("pt_xray", xr_sig)
		"rtd":
			IsoRtd.apply_led(root, el)
			_sync_rtd_meter_display(el)
		"reed":
			IsoReed.apply_led(root, el)
			IsoReed.apply_zone_viz(root, el, viz_on)
		"capacitive":
			IsoCapacitive.apply_led(root, el)
			IsoCapacitive.apply_zone_viz(root, el, viz_on)
			IsoCapacitive.apply_threshold_screw(root, el)
		"optical":
			if str(el.optical_form) == "compact":
				IsoOpticalCompact.apply_led(root, el)
				IsoOpticalCompact.apply_zone_viz(root, el, viz_on)
				IsoOpticalCompact.apply_threshold_screw(root, el)
			else:
				IsoOptical.apply_led(root, el)
				IsoOptical.apply_zone_viz(root, el, viz_on)
				IsoOptical.apply_panel(root, el, circuit)
		"ultrasonic":
			IsoUltrasonic.apply_led(root, el)
			IsoUltrasonic.apply_zone_viz(root, el, viz_on)
			IsoUltrasonic.apply_display(root, el, circuit)
		"inductive", "":
			IsoInductive.apply_led(root, el)
			IsoInductive.apply_zone_viz(root, el, viz_on)
			IsoInductive.apply_threshold_screw(root, el)
		_:
			IsoInductive.apply_led(root, el)
			IsoInductive.apply_zone_viz(root, el, viz_on)


func _sync_opto_tip_runtime(root: Node3D, el) -> void:
	if root == null or el == null or circuit == null:
		return
	var viz_on: bool = bool(circuit.sensor_field_viz)
	var amp = _amp_for_opto_tip(el)
	IsoOptoTip.apply_zone_viz(root, el, viz_on, amp, circuit)


func _amp_for_opto_tip(tip):
	if tip == null or circuit == null:
		return null
	var tip_id: int = int(tip.id)
	for wire in circuit.wires:
		if wire == null:
			continue
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		if ea == null or eb == null:
			continue
		if circuit.port_domain(ea, str(wire.a_port)) != "optic":
			continue
		if int(wire.a_id) == tip_id and str(eb.kind) == "sensor" and str(eb.sensor_class) == "optical":
			return eb
		if int(wire.b_id) == tip_id and str(ea.kind) == "sensor" and str(ea.sensor_class) == "optical":
			return ea
	return null


func _build_accessory_3d(parent: Node3D, el) -> Dictionary:
	var cls := str(el.accessory_class)
	if cls in ["throttle", "throttle_fixed"]:
		return IsoThrottle.build(parent, el)
	if cls == "check":
		return IsoCheck.build(parent, el)
	if cls in ["throttle_check", "throttle_check_fixed"]:
		return IsoThrottleCheck.build(parent, el)
	if cls == "shuttle":
		return IsoShuttle.build(parent, el)
	if cls == "and_valve":
		return IsoAnd.build(parent, el)
	if cls == "quick_exhaust":
		return IsoQuickExhaust.build(parent, el)
	if cls == "relief":
		return IsoRelief.build(parent, el)
	if cls == "shutoff":
		return IsoShutoff.build(parent, el)
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
	_hoses_ready_cached = false
	_dense_elec_batch_sig = ""
	_dense_tip_batch_sig = ""
	_dense_tip_batch_set_visible(false)
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


func _dense_elec_lod() -> bool:
	return circuit != null and circuit.wires.size() > DENSE_ELEC_WIRE_LOD


func set_perf_hud(on: bool) -> void:
	_perf_hud = on


## Плотный щит: сетку гасим (fill); пол оставляем — ориентир камеры.
func set_dense_scene_lod(on: bool) -> void:
	if _floor_mi != null and not on:
		_floor_mi.visible = true
	if on:
		_update_floor_opacity()
	if _grid_mi != null:
		_grid_mi.visible = not on


## Отключён: MultiMesh tip ломал видимость кембриков (transform space). Label3D по-прежнему off.
func _dense_tip_batch_set_visible(on: bool) -> void:
	if _dense_sleeve_mmi != null and is_instance_valid(_dense_sleeve_mmi):
		_dense_sleeve_mmi.visible = on
	if _dense_collar_mmi != null and is_instance_valid(_dense_collar_mmi):
		_dense_collar_mmi.visible = on
	if _dense_metal_mmi != null and is_instance_valid(_dense_metal_mmi):
		_dense_metal_mmi.visible = on


## Все электрожилы → 1–4 draw call (по цвету), вместо MeshInstance на каждую.
func _sync_dense_elec_batch() -> void:
	if _hoses == null or circuit == null:
		return
	if not _dense_elec_lod():
		if _dense_elec_batch != null:
			_dense_elec_batch.visible = false
		for wid in _hose_nodes.keys():
			var n0: Node3D = _hose_nodes[wid] as Node3D
			if n0 == null:
				continue
			var t0: MeshInstance3D = n0.get_node_or_null("Tube") as MeshInstance3D
			if t0 != null:
				t0.visible = true
		return
	var sig_parts: PackedStringArray = PackedStringArray()
	var groups: Dictionary = {} # color_key -> Array[{pts, r}]
	var cab_b: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_b: Node3D = cab_b.get_node_or_null("DoorHinge/Door") as Node3D if cab_b != null else null
	for wire in circuit.wires:
		var node: Node3D = _hose_nodes.get(wire.id, null) as Node3D
		if node == null or not node.visible:
			continue
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		if ea == null or eb == null:
			continue
		var elec_a: bool = Geom.port_domain(ea, str(wire.a_port)) == "electric"
		var elec_b: bool = Geom.port_domain(eb, str(wire.b_port)) == "electric"
		if not (elec_a or elec_b):
			continue
		# Дверные пролёты/локали — НЕ в batch: Tube(+tips) на полотне, иначе «повисание» в world.
		var door_wire: bool = _wire_is_door_cabinet_span(wire) or _wire_is_door_local(wire)
		if door_wire:
			var tube_dw: MeshInstance3D = _hose_find_tube(node, door_b)
			if tube_dw != null:
				tube_dw.visible = true
			var tube2_dw: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
			if tube2_dw != null:
				tube2_dw.visible = true
			continue
		# PE — не в batch: нужна полосатая текстура как у жилы ввода.
		var cid_raw: String = str(wire.color_id)
		var is_pe_wire: bool = cid_raw in ["pe", "green"] \
				or _electro_hose_is_pe(ea, str(wire.a_port), eb, str(wire.b_port))
		if is_pe_wire:
			var tube_pe: MeshInstance3D = _hose_find_tube(node, door_b)
			if tube_pe != null:
				tube_pe.visible = true
			var tube2_pe: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
			if tube2_pe != null:
				tube2_pe.visible = true
			continue
		# Только обрезанный меш (под НШВИ/кембрик) — иначе batch лезет в колпачок → «пила».
		var pts: PackedVector3Array = node.get_meta("curve_pts_mesh", PackedVector3Array()) as PackedVector3Array
		if pts.size() < 2:
			pts = node.get_meta("curve_pts", PackedVector3Array()) as PackedVector3Array
			var ta: float = float(node.get_meta("trim_a", 0.0))
			var tb: float = float(node.get_meta("trim_b", 0.0))
			if ta <= 1.0e-6 and _wire_end_wants_nshvi(wire, true):
				ta = ELEC_TUBE_TRIM
			if tb <= 1.0e-6 and _wire_end_wants_nshvi(wire, false):
				tb = ELEC_TUBE_TRIM
			if pts.size() >= 2 and (ta > 1.0e-6 or tb > 1.0e-6):
				pts = _trim_polyline_ends(pts, ta, tb)
		if pts.size() < 2:
			continue
		var r: float = float(node.get_meta("tube_radius", 0.0018))
		var cid: String = cid_raw
		# Нормализуем alias (blue→lightblue) для группировки batch.
		if cid == "blue":
			cid = "lightblue"
		elif cid == "":
			# Без color_id — ключ по ГОСТ-порту источника, не «всё brown».
			var src0: Array = _electro_hose_source(ea, str(wire.a_port), eb, str(wire.b_port))
			var pn: String = str(src0[1])
			match pn:
				"L", "L1", "+", "+24":
					cid = "brown"
				"L2", "OUT":
					cid = "black"
				"L3":
					cid = "grey"
				"N", "0", "-":
					cid = "lightblue"
				_:
					cid = "brown"
		if not groups.has(cid):
			groups[cid] = []
		(groups[cid] as Array).append({"pts": pts, "r": r})
		sig_parts.append("%d:%d:%.4f:%s" % [int(wire.id), pts.size(), r, cid])
		# Индивидуальные Tube гасим — рисует batch.
		var tube: MeshInstance3D = _hose_find_tube(node, door_b)
		if tube != null:
			tube.visible = false
		var tube2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
		if tube2 != null:
			tube2.visible = false
	var sig: String = "nodoortrim4|" + "|".join(sig_parts)
	if sig == _dense_elec_batch_sig and _dense_elec_batch != null and _dense_elec_batch.visible:
		return
	_dense_elec_batch_sig = sig
	if _dense_elec_batch == null or not is_instance_valid(_dense_elec_batch):
		_dense_elec_batch = MeshInstance3D.new()
		_dense_elec_batch.name = "DenseElecBatch"
		_dense_elec_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hoses.add_child(_dense_elec_batch)
	var am := ArrayMesh.new()
	var surf_i: int = 0
	for cid2 in groups.keys():
		var arr: Array = groups[cid2] as Array
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for rec in arr:
			var pts2: PackedVector3Array = rec["pts"] as PackedVector3Array
			var rr: float = float(rec["r"])
			_append_tube_to_surface(st, pts2, rr, 6)
		st.generate_normals()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Circuit.line_color_from_id(str(cid2))
		mat.roughness = 0.5
		mat.metallic = 0.02
		am.surface_set_material(surf_i, mat)
		surf_i += 1
	_dense_elec_batch.mesh = am
	_dense_elec_batch.visible = surf_i > 0


func _append_tube_to_surface(st: SurfaceTool, pts: PackedVector3Array, radius: float, sides: int) -> void:
	if pts.size() < 2 or radius < 1.0e-6:
		return
	var mesh: ArrayMesh = _build_tube_mesh(pts, radius, sides)
	if mesh == null or mesh.get_surface_count() < 1:
		return
	# append_from вместо копирования каждого треугольника вручную (×N фриз на dense).
	st.append_from(mesh, 0, Transform3D.IDENTITY)


func perf_ms_summary() -> String:
	return "3D machines %.1f ms · hoses %.1f ms" % [_perf_ms_machines, _perf_ms_hoses]


func _electro_hose_source(ea, a_port: String, eb, b_port: String) -> Array:
	# Цвет берём у источника (кабель/ввод/шина), не у прибора на другом конце.
	var pairs: Array = [[ea, a_port], [eb, b_port]]
	for pair in pairs:
		var el = pair[0]
		if el != null and str(el.electro_class) in ["supply", "supply_leg"]:
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
			return Color(0.45, 0.28, 0.12) # коричневый — фаза / +
		"L2":
			return Color(0.08, 0.08, 0.1) # чёрный — L2
		"L3":
			return Color(0.55, 0.56, 0.58) # серый — L3
		"OUT":
			return Color(0.08, 0.08, 0.1) # чёрный — сигнал датчика
		"N", "0", "-":
			return Color(0.15, 0.35, 0.85) # голубой — N / 0В / −
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
	# DIN/door — ghost без live-hose; gizmo — лёгкий hose (как раньше).
	var drag_lite: bool = _drag == "gizmo"
	var drag_el: int = -1
	if _drag in ["din_module", "door_module"]:
		# Не трогать жилы, пока модуль на призраке — иначе «зависание» и достройка.
		return
	var drag_ids: Dictionary = {}
	if drag_lite and _drag == "gizmo" and circuit != null:
		for sid in circuit.selected_ids:
			drag_ids[int(sid)] = true
	elif drag_lite and drag_el >= 0:
		drag_ids[drag_el] = true
	var cab_now := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_lite: bool = cab_now != null and IsoCabinet.is_door_animating(cab_now)
	# Анимация дверцы: ТОЛЬКО гофра. Жилы на Door крутятся сами; batch щита не трогаем
	# (иначе моргание: batch hide → индивидуальные Tube ещё invisible → remesh на конце).
	if door_lite:
		_door_was_animating = true
		var bundle_anim: Array = []
		for w_anim in circuit.wires:
			if w_anim == null:
				continue
			var ea_a = circuit.get_element(int(w_anim.a_id))
			var eb_a = circuit.get_element(int(w_anim.b_id))
			var elec_aa: bool = ea_a != null and Geom.port_domain(ea_a, str(w_anim.a_port)) == "electric"
			var elec_ba: bool = eb_a != null and Geom.port_domain(eb_a, str(w_anim.b_port)) == "electric"
			if (elec_aa or elec_ba) and _wire_is_door_cabinet_span(w_anim):
				bundle_anim.append(w_anim)
		_sync_door_harness_flex(bundle_anim, true)
		return
	if _door_was_animating:
		# Конец анимации: одна гофра в позе покоя; жилы не пересобираем.
		_door_was_animating = false
		_door_flex_sig = ""
		_hose_mark_door_wires_absorb_hinge()
		var bundle_end: Array = []
		for w_end in circuit.wires:
			if w_end == null:
				continue
			var ea_e = circuit.get_element(int(w_end.a_id))
			var eb_e = circuit.get_element(int(w_end.b_id))
			var elec_ae: bool = ea_e != null and Geom.port_domain(ea_e, str(w_end.a_port)) == "electric"
			var elec_be: bool = eb_e != null and Geom.port_domain(eb_e, str(w_end.b_port)) == "electric"
			if (elec_ae or elec_be) and _wire_is_door_cabinet_span(w_end):
				bundle_end.append(w_end)
		_sync_door_harness_flex(bundle_end, false)
		return
	# Drag — lite. HQ после дверцы — с бюджетом (не force_full → фриз на все жилы).
	var force_full_hoses: bool = drag_lite
	# Кэш КК один раз на кадр (не на каждый провод).
	_hose_ducts_cached()
	var has_elec: bool = _scene_has_elec_wires()
	# Separation только при dirty / не во время дверцы.
	if has_elec and not drag_lite and (_elec_sep_dirty or _hose_hq_pending):
		_elec_rebuild_separation()
		_elec_sep_dirty = false
		# Полный sep → все электрожилы могут сменить lane.
		for w_sep in circuit.wires:
			if w_sep == null:
				continue
			_hose_wire_dirty[int(w_sep.id)] = true
		_hose_heavy_pending = true
	# Add/remove: грязь только новых + peers на тех же клеммах (без remesh всех).
	_hose_collect_wire_set_dirty()
	var incremental_hoses: bool = (
		not force_full_hoses and not _hose_hq_pending and not _elec_sep_dirty
		and not _hose_wire_dirty.is_empty()
	)
	var pviz_max_hose: float = _pressure_viz_max_cached()
	var door_bundle: Array = []
	# Dense + add: 1 жила/кадр — иначе door-span remesh одной жилы всё ещё фризит.
	var hose_builds_left: int = 1 if (incremental_hoses and _dense_elec_lod()) else _hose_build_budget
	var budget_hoses: bool = not force_full_hoses
	var hoses_still_dirty: bool = false
	for wire in circuit.wires:
		var ea = circuit.get_element(int(wire.a_id))
		var eb = circuit.get_element(int(wire.b_id))
		var elec_a: bool = ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric"
		var elec_b: bool = eb != null and Geom.port_domain(eb, str(wire.b_port)) == "electric"
		var is_elec: bool = elec_a or elec_b
		var is_optic: bool = ea != null and Geom.port_domain(ea, str(wire.a_port)) == "optic"
		# Бандл гофры — по составу схемы, не по удачности _port_world в этом кадре
		# (иначе при клике на УГО гофра на кадр гаснет).
		if is_elec and _wire_is_door_cabinet_span(wire):
			door_bundle.append(wire)
		alive[wire.id] = true
		var node: Node3D = _hose_nodes.get(wire.id, null)
		if node == null:
			node = _make_hose_node()
			node.name = "H%d" % int(wire.id)
			_hoses.add_child(node)
			_hose_nodes[wire.id] = node
		elif not str(node.name).begins_with("H"):
			node.name = "H%d" % int(wire.id)
		# Инкремент add: чужие жилы не трогаем (нет _port_world / sig / sleeves).
		if incremental_hoses and not _hose_wire_dirty.has(int(wire.id)):
			if str(node.get_meta("geom_sig", "")) != "":
				continue
		# Дверца: чужие жилы / уже на полотне — без _port_world/sig (иначе фриз на плотном щите).
		if door_lite:
			if not is_elec:
				continue
			var ds_early: bool = _wire_is_door_cabinet_span(wire)
			var dl_early: bool = (not ds_early) and _wire_is_door_local(wire)
			if not ds_early and not dl_early:
				continue
			if bool(node.get_meta("tube_on_door", false)):
				continue
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
		if circuit.running and not is_elec and not is_optic and not drag_lite:
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
					if node.has_meta("mat") and str(wire.color_id) == "":
						var mat_s: StandardMaterial3D = node.get_meta("mat") as StandardMaterial3D
						if mat_s != null:
							if bool(circuit.pressure_viz):
								var base_s := Color(0.82, 0.83, 0.84)
								mat_s.albedo_color = SimVis.pressure_color(
									circuit.wire_viz_pressure(wire), base_s, pviz_max_hose
								)
							else:
								mat_s.albedo_color = UiTheme.BRAND_BLUE.lightened(0.05)
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
		# Датчик↔щит: снаружи оболочка; жила от gland веером (как кабель питания).
		var sens_span_id: int = _wire_sensor_cabinet_span(wire) if is_elec else -1
		if sens_span_id >= 0:
			var exit_raw = _sensor_cable_exit_world(sens_span_id)
			var exit_from: Vector3 = exit_raw as Vector3 if exit_raw != null else (a as Vector3)
			# Тот же слот, что у оболочки датчика — не ближайший (иначе совпадёт с вводом питания).
			var gland_w: Vector3 = _gland_world_for_sensor(sens_span_id, exit_from)
			# Поле = зонд/корпус/KP1.1; щит = DIN/дверца (в т.ч. вторичка ТС) — не оба!
			var a_field: bool = _wire_end_is_sensor_field(int(wire.a_id), sens_span_id)
			var core_port: String = str(wire.a_port) if a_field else str(wire.b_port)
			# KP1.1: порты 1/2 → жилы OUT/0. У ТС tips уже 1…N — не трогать.
			var span_el = circuit.get_element(sens_span_id)
			var span_cls: String = str(span_el.sensor_class) if span_el != null else ""
			if span_cls == "pressure_switch":
				if core_port in ["1", "13"]:
					core_port = "OUT"
				elif core_port in ["2", "14"]:
					core_port = "0"
			var gland_tip: Vector3 = _sensor_gland_core_tip(gland_w, core_port, sens_span_id)
			if a_field:
				a = gland_tip
				da = Vector3.UP
			else:
				b = gland_tip
				db = Vector3.UP
			node.set_meta("sensor_field", sens_span_id)
		else:
			node.set_meta("sensor_field", -1)
		var mat: StandardMaterial3D = node.get_meta("mat")
		var radius: float
		var pe: bool = false
		var color_id: String = str(wire.color_id)
		if is_elec:
			# PE: color_id pe/green или жила PE у ввода/шины (как у кабеля ввода).
			pe = color_id in ["pe", "green"] \
					or _electro_hose_is_pe(ea, str(wire.a_port), eb, str(wire.b_port))
			if pe:
				_pe_hose_material(mat)
			else:
				_clear_pe_hose_material(mat)
				if color_id != "":
					mat.albedo_color = Circuit.line_color_from_id(color_id)
				else:
					# Без color_id — ГОСТ по порту источника (кабель/ввод/шина).
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
		elif is_optic:
			_clear_pe_hose_material(mat)
			# Оптокабель: постоянный чёрный Ø, без давления/сужений.
			mat.albedo_color = Color(0.06, 0.06, 0.07)
			mat.roughness = 0.75
			mat.metallic = 0.02
			var od_opt: float = float(wire.od_mm) if float(wire.od_mm) >= 1.5 else 2.2
			radius = clampf(od_opt * 0.0005, 0.0010, 0.0014)
			# da/db — родные нормали портов (хвост tip = −X). Не тянуть к peer:
			# у приёмника ~180° принудительный разворот давал перелом у штуцера.
			var oinset: float = clampf(radius * 0.35, 0.0005, 0.0012)
			a = a - da.normalized() * oinset
			b = b - db.normalized() * oinset
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
			if _wire_end_wants_nshvi(wire, true):
				nshvi_flags |= 1
			if _wire_end_wants_nshvi(wire, false):
				nshvi_flags |= 2
		# Якоря гофры НЕ в geom_sig жил: иначе open/close дверцы → remesh всех электро-жил.
		# Гофра — отдельный меш (_sync_door_harness_flex).
		# route53: door-local мостик на глубине пеньков (не сквозь кнопки).
		var sig := "%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.5f|%d|%d|%s|route53duct|%d|%s|%d" % [
			a.x, a.y, a.z, b.x, b.y, b.z, da.x, da.y, da.z, db.x, db.y, db.z, radius, 1 if is_elec else 0, 1 if pe else 0, color_id, lane, qtag, nshvi_flags,
		]
		var door_span: bool = is_elec and _wire_is_door_cabinet_span(wire)
		var door_local: bool = is_elec and (not door_span) and _wire_is_door_local(wire)
		var geom_changed: bool = str(node.get_meta("geom_sig", "")) != sig
		# Петля дверцы двигает world-tip, mesh в door-local — remesh не нужен (только гофра).
		if geom_changed and (door_span or door_local) and bool(node.get_meta("tube_on_door", false)):
			if bool(node.get_meta("door_hinge_absorb", false)) or not _hose_hq_pending:
				var prev_sig: String = str(node.get_meta("geom_sig", ""))
				if prev_sig != "" or bool(node.get_meta("door_hinge_absorb", false)):
					node.set_meta("geom_sig", sig)
					node.remove_meta("door_hinge_absorb")
					geom_changed = false
		if geom_changed and budget_hoses and hose_builds_left <= 0:
			hoses_still_dirty = true
			continue
		if geom_changed and budget_hoses:
			hose_builds_left -= 1
		# Без смены геометрии — только цвет (давление вкл/выкл).
		if not geom_changed:
			if not is_elec:
				if color_id != "":
					mat.albedo_color = Circuit.line_color_from_id(color_id)
				elif bool(circuit.pressure_viz):
					var SimVp = preload("res://scripts/domain/sim_vis.gd")
					var base_h := Color(0.82, 0.83, 0.84)
					mat.albedo_color = SimVp.pressure_color(
						circuit.wire_viz_pressure(wire), base_h, pviz_max_hose
					)
				else:
					mat.albedo_color = UiTheme.BRAND_BLUE.lightened(0.05)
			continue
		if geom_changed:
			var pts: PackedVector3Array
			var pts_ortho := PackedVector3Array()
			var trim_a: float = 0.0
			var trim_b: float = 0.0
			if is_elec:
				if _wire_end_wants_nshvi(wire, true):
					trim_a = ELEC_TUBE_TRIM
				if _wire_end_wants_nshvi(wire, false):
					trim_b = ELEC_TUBE_TRIM
			if is_elec and door_local:
				# Оба на дверце: перемычка у приборов (не через дверной КК).
				if _wire_end_wants_nshvi(wire, true):
					trim_a = ELEC_DOOR_TUBE_TRIM
				if _wire_end_wants_nshvi(wire, false):
					trim_b = ELEC_DOOR_TUBE_TRIM
				var door_n_loc: Node3D = cab_now.get_node_or_null("DoorHinge/Door") as Node3D if cab_now != null else null
				if door_lite and door_n_loc != null and bool(node.get_meta("tube_on_door", false)):
					# Tube уже на полотне — крутится сам, без remesh.
					node.set_meta("geom_sig", sig)
					node.set_meta("door_span", false)
				else:
					var dd_loc: Dictionary = IsoCabinet.door_cable_duct_world(cab_now) if cab_now != null else {}
					pts = _hose_door_local_run(a, da, b, db, dd_loc)
					if pts.size() >= 2:
						pts = _hose_clean_elec_path(pts, maxf(radius * 0.7, 0.0006))
						pts_ortho = pts
						pts = _fillet_polyline(pts, ELEC_DOOR_BEND_R, 4 if drag_lite else 6)
						if door_n_loc != null:
							var local_dl: PackedVector3Array = _hose_points_world_to_door(pts, door_n_loc)
							node.set_meta("curve_pts_door_local", local_dl)
							_apply_hose_path_split(
								node, local_dl, PackedVector3Array(), radius,
								trim_a, trim_b, 0.0, 0.0, false, door_n_loc, false
							)
							_hide_hose_tube_cab(node)
						else:
							_apply_hose_path(node, pts, radius, trim_a, trim_b)
							_hide_hose_tube_cab(node)
						node.set_meta("geom_sig", sig)
						node.set_meta("curve_pts", pts)
						node.set_meta("door_span", false)
						node.set_meta("curve_pts_ortho", pts_ortho)
			elif is_elec and door_span:
				var a_on_door: bool = _electro_mount_of(int(wire.a_id)) == "door"
				# Дверца: trim под НШВИ (+длиннее для сдвоенного); кабинет — обычная стопка.
				var door_trim_a: float = _elec_door_tube_trim(int(wire.a_id), str(wire.a_port))
				var door_trim_b: float = _elec_door_tube_trim(int(wire.b_id), str(wire.b_port))
				if a_on_door:
					trim_a = door_trim_a
					trim_b = ELEC_TUBE_TRIM if _wire_end_wants_nshvi(wire, false) else 0.0
				else:
					trim_a = ELEC_TUBE_TRIM if _wire_end_wants_nshvi(wire, true) else 0.0
					trim_b = door_trim_b
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
				var door_n_span: Node3D = cab_now.get_node_or_null("DoorHinge/Door") as Node3D if cab_now != null else null
				if door_lite and bool(node.get_meta("door_span", false)) \
						and bool(node.get_meta("tube_on_door", false)) and node.has_meta("curve_pts_cab_duct"):
					# Tube на полотне крутится сам; обновляем только кабинет+заход в гофру.
					var enter_d_lite: float = 0.10
					var anchors_lite: Dictionary = IsoCabinet.harness_anchors_world(cab_now) if cab_now != null else {}
					var pts_cab_duct: PackedVector3Array = node.get_meta("curve_pts_cab_duct") as PackedVector3Array
					var cab_flex_lite: PackedVector3Array = _flex_wire_along_centerline(anchors_lite, lane, false, enter_d_lite)
					var pts_cab: PackedVector3Array = PackedVector3Array()
					for p_cfl in cab_flex_lite:
						pts_cab.append(p_cfl)
					for p_cd in pts_cab_duct:
						_hose_ortho_push(pts_cab, p_cd)
					_apply_hose_path_split(
						node, PackedVector3Array(), pts_cab, radius,
						0.0, 0.0, cab_trim_start, cab_trim_end, true, door_n_span, true
					)
					node.set_meta("geom_sig", sig)
					node.set_meta("door_span", true)
				else:
					var door_el_w: int = int(wire.a_id) if a_on_door else int(wire.b_id)
					var door_port_w: String = str(wire.a_port) if a_on_door else str(wire.b_port)
					split = _hose_ortho_elec_door_span(
						a, a1s, da, b, b1s, db, ida2, idb2, lane, a_on_door, door_el_w, door_port_w
					)
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
						# Жёсткая часть на полотне — локаль дверцы + parent Tube (без remesh при анимации).
						var pts_d_local: PackedVector3Array = pts_d
						if door_n_span != null:
							pts_d_local = _hose_points_world_to_door(pts_d, door_n_span)
							node.set_meta("curve_pts_door_duct_local", pts_d_local)
						# cab_flex — от внутри гофры к торцу; вставляем ПЕРЕД кабинным каналом.
						# door_flex не кладём в Tube (иначе нельзя parent на дверцу) — гофра закрывает стык.
						if cab_flex.size() >= 2:
							var merged_c := PackedVector3Array()
							for p_cf in cab_flex:
								merged_c.append(p_cf)
							for p_c in pts_c:
								_hose_ortho_push(merged_c, p_c)
							pts_c = merged_c
						_apply_hose_path_split(
							node, pts_d_local, pts_c, radius,
							door_trim_start, door_trim_end, cab_trim_start, cab_trim_end,
							false, door_n_span, false
						)
						node.set_meta("geom_sig", sig)
						node.set_meta("door_span", true)
						node.set_meta("curve_pts_ortho", pts_d)
						node.set_meta("curve_pts_cab", pts_c)
						# door_flex только в ortho/meta для зубьев/pick (world).
						if door_flex.size() >= 2:
							var ortho_w := PackedVector3Array()
							for p_o in pts_d:
								ortho_w.append(p_o)
							for p_df2 in door_flex:
								_hose_ortho_push(ortho_w, p_df2)
							node.set_meta("curve_pts_ortho", ortho_w)
			elif is_elec:
				pts = _hose_ortho_elec(a, da, b, db, wire, lane)
				# Спайки / развороты / микро-рёбра — до fillet, иначе узлы и перекруты.
				pts = _hose_clean_elec_path(pts, maxf(radius * 1.6, 0.0010))
				pts_ortho = pts
				var min_edge: float = _polyline_min_edge(pts)
				var bend: float = clampf(minf(radius * 5.0, min_edge * 0.35), 0.0018, 0.008)
				var wcount_e: int = circuit.wires.size() if circuit != null else 0
				if drag_lite or wcount_e > 40:
					pts = _fillet_polyline(pts, bend, 3 if wcount_e > 40 else 4)
				else:
					pts = _fillet_polyline(pts, bend, 8)
					pts = _hose_clean_elec_path(pts, maxf(radius * 0.4, 0.00025))
				_apply_hose_path(node, pts, radius, trim_a, trim_b)
				_hide_hose_tube_cab(node)
				node.set_meta("geom_sig", sig)
				node.set_meta("curve_pts", pts)
				node.set_meta("door_span", false)
				node.set_meta("curve_pts_ortho", pts_ortho if pts_ortho.size() >= 2 else pts)
			elif is_optic:
				# Оптоволокно: пеньки строго по нормали порта (хвост tip); плавный U-turn при ~180°.
				var curve_n_o: int = 48 if not drag_lite else 28
				pts = _hose_curve_optic(a, da, b, db, curve_n_o, radius)
				pts_ortho = pts
				_apply_hose_path(node, pts, radius, trim_a, trim_b)
				_hide_hose_tube_cab(node)
				node.set_meta("geom_sig", sig)
				node.set_meta("curve_pts", pts)
				node.set_meta("door_span", false)
				node.set_meta("curve_pts_ortho", pts_ortho)
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
		if geom_changed and not is_elec and not is_optic and circuit != null and circuit.has_method("apply_wire_length_3d"):
			circuit.apply_wire_length_3d(wire, curve_pts)
		if not door_lite:
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
		if not drag_lite and not door_lite:
			_sync_sensor_cable_sheaths()
		# Сдвоенные НШВИ — лёгкий (с place_sig); dense batch/зубья — не на add-wire.
		if not drag_lite and not door_lite:
			_sync_nshvi_doubles()
		if not drag_lite and not door_lite:
			var add_busy: bool = hoses_still_dirty or not _hose_wire_dirty.is_empty()
			if add_busy:
				# Add/mid-build: НЕ пересобирать ArrayMesh всех жил (главный фриз).
				_hose_batch_suspended = true
				_hose_heavy_pending = true
				_hose_heavy_idle_frames = 0
				_hose_suspend_dense_batch()
				# Mesh грязных готов — снять dirty, чтобы не крутить O(W) до batch.
				if not hoses_still_dirty:
					_hose_wire_dirty.clear()
			elif _hose_hq_pending or (
				_hose_batch_suspended and _hose_heavy_idle_frames >= HOSE_HEAVY_IDLE_FRAMES
			):
				_dense_elec_batch_sig = ""
				_sync_dense_elec_batch()
				_sync_duct_finger_cutouts()
				_hose_heavy_pending = false
				_hose_wire_dirty.clear()
				_hose_batch_suspended = false
				_hose_heavy_idle_frames = 0
			elif _hose_batch_suspended:
				_hose_suspend_dense_batch()
			_hose_ensure_door_wires_on_door(cab_now, false)
	# HQ после дверцы/dirty — крутим с бюджетом, пока не догоним.
	if _hose_hq_pending and not door_lite and not drag_lite and not hoses_still_dirty:
		_hose_hq_pending = false


## Новые/удалённые провода → dirty id + peers на тех же клеммах; lane новым без полного sep.
func _hose_collect_wire_set_dirty() -> void:
	if circuit == null:
		return
	var alive_ids: Dictionary = {}
	var added: Array = []
	for wire in circuit.wires:
		if wire == null:
			continue
		var wid: int = int(wire.id)
		alive_ids[wid] = true
		if not _hose_known_ids.has(wid):
			added.append(wire)
	var removed: bool = false
	for kid in _hose_known_ids.keys():
		if not alive_ids.has(int(kid)):
			removed = true
			_elec_lane_by_wire.erase(int(kid))
			_hose_wire_dirty.erase(int(kid))
	if removed:
		_hose_heavy_pending = true
		_dense_elec_batch_sig = ""
		_duct_finger_sig = ""
	for w_new in added:
		var nid: int = int(w_new.id)
		_hose_wire_dirty[nid] = true
		_hose_heavy_pending = true
		# Lane без полного rebuild (иначе сдвиг индексов → remesh всех).
		if not _elec_lane_by_wire.has(nid):
			var mx: int = -1
			for lv in _elec_lane_by_wire.values():
				mx = maxi(mx, int(lv))
			_elec_lane_by_wire[nid] = mx + 1
		# Peers на клеммах: pair-offset / сдвоенный НШВИ.
		for end_i in 2:
			var el_id: int = int(w_new.a_id) if end_i == 0 else int(w_new.b_id)
			var port: String = str(w_new.a_port) if end_i == 0 else str(w_new.b_port)
			var peers: Array = circuit.wires_on_port(el_id, port)
			for peer in peers:
				if peer == null:
					continue
				_hose_wire_dirty[int(peer.id)] = true
				var pnode: Node3D = _hose_nodes.get(int(peer.id), null) as Node3D
				if pnode != null:
					pnode.remove_meta("geom_sig")
		var nnode: Node3D = _hose_nodes.get(nid, null) as Node3D
		if nnode != null:
			nnode.remove_meta("geom_sig")
	if not added.is_empty():
		_elec_cluster_double_nshvi_lanes()
	_hose_known_ids = alive_ids


## Add-wire: погасить dense-batch, показать все индивидуальные Tube (без фриза remesh).
func _hose_suspend_dense_batch() -> void:
	if _dense_elec_batch != null and is_instance_valid(_dense_elec_batch):
		_dense_elec_batch.visible = false
	var cab_b: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_b: Node3D = cab_b.get_node_or_null("DoorHinge/Door") as Node3D if cab_b != null else null
	for wid in _hose_nodes.keys():
		var node: Node3D = _hose_nodes[wid] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var tube: MeshInstance3D = _hose_find_tube(node, door_b)
		if tube != null and tube.mesh != null:
			tube.visible = true
		var tube2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
		if tube2 != null and tube2.mesh != null:
			tube2.visible = true


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
	sig_parts.append("%d:%d:%d|v4locY" % [host_id, door_id, fingers.size()])
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
		_duct_finger_show_all(fi)
	if paths.is_empty():
		return
	# Зазор между зубами ≈ 4 мм: prox ≥ ползазора + Ø/2, иначе провод в щели «не задевает» AABB.
	var gap_half: float = Parts.mm(2.2)
	for fi2 in fingers:
		if fi2 is MultiMeshInstance3D and bool(fi2.get_meta("duct_finger_mm", false)):
			_duct_finger_mm_cutouts(fi2 as MultiMeshInstance3D, paths, gap_half)
			continue
		var fmi: MeshInstance3D = fi2 as MeshInstance3D
		if fmi == null or fmi.mesh == null:
			continue
		var box: AABB = fmi.global_transform * fmi.get_aabb()
		if _duct_finger_hit_paths(box, paths, gap_half):
			fmi.visible = false


func _duct_finger_show_all(fi) -> void:
	if fi is MultiMeshInstance3D and bool(fi.get_meta("duct_finger_mm", false)):
		var mmi: MultiMeshInstance3D = fi as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		if mm == null:
			return
		var bases: Array = fi.get_meta("finger_bases", []) as Array
		for i in mm.instance_count:
			if i < bases.size() and bases[i] is Transform3D:
				mm.set_instance_transform(i, bases[i] as Transform3D)
		return
	var fmi: MeshInstance3D = fi as MeshInstance3D
	if fmi != null:
		fmi.visible = true


func _duct_finger_mm_cutouts(mmi: MultiMeshInstance3D, paths: Array, gap_half: float) -> void:
	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		return
	var fsize: Vector3 = mmi.get_meta("finger_size", Vector3(0.008, 0.0016, 0.02)) as Vector3
	# В локали MMI: длина по X, тонкая стенка по Y — не world AABB (на повёрнутой дверце косил весь ряд).
	var inv: Transform3D = mmi.global_transform.affine_inverse()
	var local_paths: Array = []
	for pr in paths:
		var pts_w: PackedVector3Array = pr["pts"] as PackedVector3Array
		var pts_l := PackedVector3Array()
		for pw in pts_w:
			pts_l.append(inv * pw)
		local_paths.append({"pts": pts_l, "r": float(pr["r"])})
	var half: Vector3 = fsize * 0.5
	for i in mm.instance_count:
		var lxf: Transform3D = mm.get_instance_transform(i)
		var fc: Vector3 = lxf.origin
		if _duct_finger_hit_local(fc, half, local_paths, gap_half):
			var hide_xf := Transform3D(Basis.from_scale(Vector3(1.0e-4, 1.0e-4, 1.0e-4)), lxf.origin)
			mm.set_instance_transform(i, hide_xf)


## paths уже в локали зуба/MMI. Режем только сегмент сквозь тонкую ось (Y), не продольный бег по X.
func _duct_finger_hit_local(fc: Vector3, half: Vector3, local_paths: Array, gap_half: float) -> bool:
	var min_cross: float = Parts.mm(3.5)
	for pr in local_paths:
		var pts2: PackedVector3Array = pr["pts"] as PackedVector3Array
		var wr: float = float(pr["r"])
		var prox: float = maxf(wr + gap_half, Parts.mm(3.0))
		var box := AABB(
			fc - half - Vector3(prox, prox * 0.35, prox),
			half * 2.0 + Vector3(prox * 2.0, prox * 0.7, prox * 2.0)
		)
		for si in range(pts2.size() - 1):
			var p0: Vector3 = pts2[si]
			var p1: Vector3 = pts2[si + 1]
			var d: Vector3 = p1 - p0
			var ax: float = absf(d.x)
			var ay: float = absf(d.y)
			# Продольный бег вдоль канала (X) — не зуб.
			if ax > Parts.mm(10.0) and ax > ay * 1.8:
				continue
			# Сквозь стенку зуба: заметный ход по тонкой оси Y.
			if ay < min_cross:
				continue
			if _segment_hits_aabb(p0, p1, box):
				return true
	return false


func _duct_finger_hit_paths(box: AABB, paths: Array, gap_half: float) -> bool:
	## Legacy world-AABB (MeshInstance). Без near_point — он косил соседние зубья.
	for pr in paths:
		var pts2: PackedVector3Array = pr["pts"] as PackedVector3Array
		var wr: float = float(pr["r"])
		var prox: float = maxf(wr + gap_half, Parts.mm(3.0))
		var grown: AABB = box.grow(prox)
		var ext: Vector3 = box.size
		# Тонкая ось world-AABB (грубо) — сегмент должен иметь ход вдоль неё.
		var thin_ax: int = 0
		if ext.y <= ext.x and ext.y <= ext.z:
			thin_ax = 1
		elif ext.z <= ext.x and ext.z <= ext.y:
			thin_ax = 2
		for si in range(pts2.size() - 1):
			var p0: Vector3 = pts2[si]
			var p1: Vector3 = pts2[si + 1]
			var d: Vector3 = p1 - p0
			var cross: float = absf(d.x) if thin_ax == 0 else (absf(d.y) if thin_ax == 1 else absf(d.z))
			if cross < Parts.mm(3.5):
				continue
			if _segment_hits_aabb(p0, p1, grown):
				return true
	return false


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
		if c is MultiMeshInstance3D and bool(c.get_meta("duct_finger_mm", false)):
			continue
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
	if n is MultiMeshInstance3D and bool(n.get_meta("duct_finger_mm", false)):
		out.append(n)
	elif n is MeshInstance3D and bool(n.get_meta("duct_finger", false)):
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


func _hose_cabinet_door() -> Node3D:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	return cab.get_node_or_null("DoorHinge/Door") as Node3D if cab != null else null


## Убрать дубликат бирки под hose, если канон уже на Door (иначе RID explosion).
func _hose_free_stale_tip_under_hose(hose: Node3D, logical: String, keep: Node3D) -> void:
	if hose == null or keep == null:
		return
	var s0: Node = hose.get_node_or_null(logical)
	if s0 != null and s0 != keep:
		s0.name = "%s_dead_%d" % [logical, s0.get_instance_id()]
		s0.queue_free()
	var dname: String = _hose_door_tip_name(hose, logical)
	var s1: Node = hose.get_node_or_null(dname)
	if s1 != null and s1 != keep:
		s1.name = "%s_dead_%d" % [dname, s1.get_instance_id()]
		s1.queue_free()


func _ensure_hose_sleeves(node: Node3D) -> void:
	if node == null:
		return
	# Бирки могли уехать на Door (SleeveA_H12) — не плодить SleeveA под hose каждый кадр.
	var door: Node3D = _hose_cabinet_door()
	var sa: Node3D = _hose_find_tip(node, "SleeveA", door)
	if sa == null:
		_make_mark_sleeve(node, "SleeveA")
	else:
		_hose_free_stale_tip_under_hose(node, "SleeveA", sa)
	var sb: Node3D = _hose_find_tip(node, "SleeveB", door)
	if sb == null:
		_make_mark_sleeve(node, "SleeveB")
	else:
		_hose_free_stale_tip_under_hose(node, "SleeveB", sb)
	var na: Node3D = _hose_find_tip(node, "NshviA", door)
	if na == null:
		_make_nshvi_node(node, "NshviA")
	else:
		_hose_free_stale_tip_under_hose(node, "NshviA", na)
	var nb: Node3D = _hose_find_tip(node, "NshviB", door)
	if nb == null:
		_make_nshvi_node(node, "NshviB")
	else:
		_hose_free_stale_tip_under_hose(node, "NshviB", nb)
	# Миграция: цифры жили на цветном колпачке — переносим на белый кембрик.
	for sn in ["SleeveA", "SleeveB"]:
		var sl: MeshInstance3D = _hose_find_tip(node, sn, door) as MeshInstance3D
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


func _hose_door_tube_name(hose: Node3D) -> String:
	return "DoorTube_%s" % str(hose.name)


func _hose_door_tip_name(hose: Node3D, logical: String) -> String:
	return "%s_%s" % [logical, str(hose.name)]


func _hose_find_tube(hose: Node3D, door: Node3D = null) -> MeshInstance3D:
	# Сначала полотно: иначе устаревший Tube под hose перекрывает DoorTube и плодит дубликаты.
	if door != null and hose != null:
		var td: MeshInstance3D = door.get_node_or_null(_hose_door_tube_name(hose)) as MeshInstance3D
		if td != null:
			return td
	if hose != null:
		var t0: MeshInstance3D = hose.get_node_or_null("Tube") as MeshInstance3D
		if t0 != null:
			return t0
		var t1: MeshInstance3D = hose.get_node_or_null(_hose_door_tube_name(hose)) as MeshInstance3D
		if t1 != null:
			return t1
	return null


func _hose_find_tip(hose: Node3D, logical: String, door: Node3D = null) -> Node3D:
	# Сначала полотно — иначе stale SleeveA под hose перекрывает Door и плодит дубликаты.
	if door != null and hose != null:
		var td: Node3D = door.get_node_or_null(_hose_door_tip_name(hose, logical)) as Node3D
		if td != null and is_instance_valid(td) and not td.is_queued_for_deletion():
			return td
	if hose != null:
		var t0: Node3D = hose.get_node_or_null(logical) as Node3D
		if t0 != null and is_instance_valid(t0) and not t0.is_queued_for_deletion():
			return t0
		var t1: Node3D = hose.get_node_or_null(_hose_door_tip_name(hose, logical)) as Node3D
		if t1 != null and is_instance_valid(t1) and not t1.is_queued_for_deletion():
			return t1
	return null


func _hose_reparent_keep_global(n: Node3D, new_parent: Node3D, new_name: String) -> void:
	if n == null or new_parent == null:
		return
	if n.get_parent() == new_parent and str(n.name) == new_name:
		return
	# Освободить имя на целевом родителе (иначе Godot → SleeveA_H5_2 и утечка RID).
	var existing: Node = new_parent.get_node_or_null(new_name)
	if existing != null and existing != n:
		existing.name = "%s_dead_%d" % [new_name, existing.get_instance_id()]
		existing.queue_free()
	n.name = new_name
	if n.get_parent() == new_parent:
		return
	var gxf: Transform3D = n.global_transform
	var vis: bool = n.visible
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	new_parent.add_child(n)
	n.global_transform = gxf
	n.visible = vis


func _hose_tube_attach_to_door(mi: MeshInstance3D, door: Node3D, hose: Node3D) -> void:
	if mi == null or door == null or hose == null:
		return
	# Меш в локали дверцы (pts уже door-local) — Identity, не keep_global.
	mi.name = _hose_door_tube_name(hose)
	# Убрать дубликат Tube под hose (старый world-меш → «повисание»).
	var stale: MeshInstance3D = hose.get_node_or_null("Tube") as MeshInstance3D
	if stale != null and stale != mi:
		stale.queue_free()
	var stale2: MeshInstance3D = hose.get_node_or_null(_hose_door_tube_name(hose)) as MeshInstance3D
	if stale2 != null and stale2 != mi:
		stale2.queue_free()
	if mi.get_parent() == door:
		mi.transform = Transform3D.IDENTITY
		return
	var keep_vis: bool = mi.visible
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	door.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.visible = keep_vis


func _hose_tube_attach_to_hose(mi: MeshInstance3D, hose: Node3D) -> void:
	if mi == null or hose == null:
		return
	mi.name = "Tube"
	if mi.get_parent() == hose:
		mi.transform = Transform3D.IDENTITY
		return
	var keep_vis: bool = mi.visible
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	hose.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.visible = keep_vis


## Гарантировать: дверные жилы/бирки на Door (не в world-batch). lite=true — без тяжёлого remesh.
func _hose_ensure_door_wires_on_door(cab: Node3D, lite: bool) -> void:
	if cab == null or circuit == null:
		return
	var door: Node3D = cab.get_node_or_null("DoorHinge/Door") as Node3D
	if door == null:
		return
	for wire in circuit.wires:
		if wire == null:
			continue
		if not _wire_is_door_cabinet_span(wire) and not _wire_is_door_local(wire):
			continue
		var node: Node3D = _hose_nodes.get(int(wire.id), null) as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not str(node.name).begins_with("H"):
			node.name = "H%d" % int(wire.id)
		var mi: MeshInstance3D = _hose_find_tube(node, door)
		var on_door: bool = mi != null and is_instance_valid(mi) and mi.get_parent() == door
		if not on_door:
			node.set_meta("tube_on_door", false)
			var local_pts: PackedVector3Array = PackedVector3Array()
			if node.has_meta("curve_pts_door_duct_local"):
				local_pts = node.get_meta("curve_pts_door_duct_local") as PackedVector3Array
			elif node.has_meta("curve_pts_door_local"):
				local_pts = node.get_meta("curve_pts_door_local") as PackedVector3Array
			if local_pts.size() >= 2:
				var cab_pts: PackedVector3Array = PackedVector3Array()
				if _wire_is_door_cabinet_span(wire):
					cab_pts = node.get_meta("curve_pts_cab", PackedVector3Array()) as PackedVector3Array
					if cab_pts.is_empty() and node.has_meta("curve_pts_cab_duct"):
						cab_pts = node.get_meta("curve_pts_cab_duct") as PackedVector3Array
				var rr: float = float(node.get_meta("tube_radius", 0.002))
				_apply_hose_path_split(
					node, local_pts, cab_pts, rr,
					0.0, 0.0, 0.0, 0.0, lite, door, false
				)
				mi = _hose_find_tube(node, door)
				on_door = mi != null and is_instance_valid(mi) and mi.get_parent() == door
		if on_door and mi != null:
			mi.visible = true
			node.set_meta("tube_on_door", true)
			_hose_bind_door_end_tips(node, wire, door)
		var t2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
		if t2 != null:
			t2.visible = true


## Кембрик/НШВИ дверного конца — на полотно (как Tube), иначе отстают при анимации.
func _hose_bind_door_end_tips(hose: Node3D, wire, door: Node3D) -> void:
	if hose == null or wire == null or door == null:
		return
	var a_on: bool = _electro_mount_of(int(wire.a_id)) == "door"
	var b_on: bool = _electro_mount_of(int(wire.b_id)) == "door"
	if _wire_is_door_local(wire):
		a_on = true
		b_on = true
	var sa: Node3D = _hose_find_tip(hose, "SleeveA", door)
	var sb: Node3D = _hose_find_tip(hose, "SleeveB", door)
	var na: Node3D = _hose_find_tip(hose, "NshviA", door)
	var nb: Node3D = _hose_find_tip(hose, "NshviB", door)
	if a_on:
		if sa != null:
			_hose_reparent_keep_global(sa, door, _hose_door_tip_name(hose, "SleeveA"))
		if na != null:
			_hose_reparent_keep_global(na, door, _hose_door_tip_name(hose, "NshviA"))
	else:
		if sa != null:
			_hose_reparent_keep_global(sa, hose, "SleeveA")
		if na != null:
			_hose_reparent_keep_global(na, hose, "NshviA")
	if b_on:
		if sb != null:
			_hose_reparent_keep_global(sb, door, _hose_door_tip_name(hose, "SleeveB"))
		if nb != null:
			_hose_reparent_keep_global(nb, door, _hose_door_tip_name(hose, "NshviB"))
	else:
		if sb != null:
			_hose_reparent_keep_global(sb, hose, "SleeveB")
		if nb != null:
			_hose_reparent_keep_global(nb, hose, "NshviB")
	hose.set_meta("tips_on_door", a_on or b_on)


func _apply_hose_path_split(
	node: Node3D,
	pts_door: PackedVector3Array,
	pts_cab: PackedVector3Array,
	radius: float,
	trim_door_start: float,
	trim_door_end: float,
	trim_cab_start: float,
	trim_cab_end: float,
	lite: bool = false,
	door_parent: Node3D = null,
	skip_door_mesh: bool = false
) -> void:
	var mi: MeshInstance3D = _hose_find_tube(node, door_parent)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Tube"
		mi.material_override = node.get_meta("mat", null) as Material
		node.add_child(mi)
	var mi2: MeshInstance3D = node.get_node_or_null("TubeCab") as MeshInstance3D
	if mi2 == null:
		mi2 = MeshInstance3D.new()
		mi2.name = "TubeCab"
		mi2.material_override = mi.material_override
		node.add_child(mi2)
	var wcount_s: int = circuit.wires.size() if circuit != null else 0
	var sides_s: int = 5 if lite else clampi(int(round(8.0 + radius * 900.0)), 10, 18)
	if not lite:
		if wcount_s > DENSE_ELEC_WIRE_LOD:
			sides_s = clampi(sides_s - 6, 6, 8)
		elif wcount_s > 20:
			sides_s = clampi(sides_s - 2, 8, 14)
	if not skip_door_mesh:
		var mesh_d: PackedVector3Array = pts_door
		if pts_door.size() >= 2 and (trim_door_start > 1.0e-6 or trim_door_end > 1.0e-6):
			mesh_d = _trim_polyline_ends(pts_door, maxf(trim_door_start, 0.0), maxf(trim_door_end, 0.0))
		mi.mesh = _build_tube_mesh(mesh_d, radius, sides_s) if mesh_d.size() >= 2 else null
	# Parent всегда, даже при skip_door_mesh (иначе meta tube_on_door без reparent → повисание).
	if door_parent != null:
		_hose_tube_attach_to_door(mi, door_parent, node)
	else:
		_hose_tube_attach_to_hose(mi, node)
	var mesh_c: PackedVector3Array = pts_cab
	if pts_cab.size() >= 2 and (trim_cab_start > 1.0e-6 or trim_cab_end > 1.0e-6):
		mesh_c = _trim_polyline_ends(pts_cab, maxf(trim_cab_start, 0.0), maxf(trim_cab_end, 0.0))
	mi2.mesh = _build_tube_mesh(mesh_c, radius, sides_s) if mesh_c.size() >= 2 else null
	mi2.visible = mesh_c.size() >= 2
	var combined := PackedVector3Array()
	var combined_mesh := PackedVector3Array()
	# Для meta/pick: дверная часть в world, если родитель — дверца.
	if door_parent != null and pts_door.size() >= 2:
		for p in _hose_points_door_to_world(pts_door, door_parent):
			combined.append(p)
		if not skip_door_mesh:
			var mesh_d_w: PackedVector3Array = pts_door
			if pts_door.size() >= 2 and (trim_door_start > 1.0e-6 or trim_door_end > 1.0e-6):
				mesh_d_w = _trim_polyline_ends(pts_door, maxf(trim_door_start, 0.0), maxf(trim_door_end, 0.0))
			for p2 in _hose_points_door_to_world(mesh_d_w, door_parent):
				combined_mesh.append(p2)
	else:
		for p in pts_door:
			combined.append(p)
		if not skip_door_mesh:
			var mesh_d2: PackedVector3Array = pts_door
			if pts_door.size() >= 2 and (trim_door_start > 1.0e-6 or trim_door_end > 1.0e-6):
				mesh_d2 = _trim_polyline_ends(pts_door, maxf(trim_door_start, 0.0), maxf(trim_door_end, 0.0))
			for p3 in mesh_d2:
				combined_mesh.append(p3)
	for p in pts_cab:
		combined.append(p)
	for p4 in mesh_c:
		combined_mesh.append(p4)
	node.set_meta("curve_pts", combined)
	node.set_meta("curve_pts_mesh", combined_mesh if combined_mesh.size() >= 2 else combined)
	node.set_meta("curve_pts_door", pts_door)
	node.set_meta("curve_pts_cab", pts_cab)
	node.set_meta("trim_a", trim_door_start)
	node.set_meta("trim_b", trim_cab_end)
	node.set_meta("tube_radius", radius)
	node.set_meta("tube_on_door", door_parent != null and mi.get_parent() == door_parent)


func _apply_hose_path(
	node: Node3D, pts: PackedVector3Array, radius: float, trim_a: float = 0.0, trim_b: float = 0.0,
	lite: bool = false
) -> void:
	var mi: MeshInstance3D = node.get_node("Tube")
	# Под НШВИ изоляцию срезаем; со стороны источника/стыка — до конца, без щели.
	var mesh_pts: PackedVector3Array = pts
	if pts.size() >= 2 and (trim_a > 1.0e-6 or trim_b > 1.0e-6):
		mesh_pts = _trim_polyline_ends(pts, maxf(trim_a, 0.0), maxf(trim_b, 0.0))
	# Толстые пневмотрубки — больше сегментов кольца; LOD при многих проводах.
	var wcount2: int = circuit.wires.size() if circuit != null else 0
	var sides: int = 5 if lite else clampi(int(round(8.0 + radius * 900.0)), 10, 18)
	if not lite:
		if wcount2 > 40:
			sides = clampi(sides - 6, 6, 8)
		elif wcount2 > 20:
			sides = clampi(sides - 2, 8, 14)
	mi.mesh = _build_tube_mesh(mesh_pts, radius, sides)
	node.set_meta("curve_pts", pts)
	node.set_meta("curve_pts_mesh", mesh_pts)
	node.set_meta("trim_a", trim_a)
	node.set_meta("trim_b", trim_b)
	node.set_meta("tube_radius", radius)


func _hose_points_world_to_door(pts: PackedVector3Array, door: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if door == null:
		return pts
	for p in pts:
		out.append(door.to_local(p))
	return out


func _hose_points_door_to_world(pts: PackedVector3Array, door: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if door == null:
		return pts
	for p in pts:
		out.append(door.to_global(p))
	return out


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


## НШВИ только на клеммах приборов/клеммников — не на жилах вводного кабеля (источник)
## и не на конце жилы у gland датчика (там кембрик как у питания).
func _end_wants_nshvi(el_id: int, _port: String) -> bool:
	if circuit == null or el_id < 0:
		return false
	var el = circuit.get_element(el_id)
	if el == null:
		return false
	if str(el.kind) == "sensor":
		return false
	if str(el.kind) != "electro":
		return false
	if str(el.electro_class) in ["supply", "supply_leg"]:
		return false
	return true


## Полевой конец span датчик↔щит: корпус/зонд или контакт KP1.1 (не вторичка/PT device).
func _wire_end_is_sensor_field(el_id: int, sens_span_id: int) -> bool:
	if el_id < 0 or sens_span_id < 0:
		return false
	if el_id == sens_span_id:
		return true
	if circuit == null:
		return false
	var el = circuit.get_element(el_id)
	if el == null or str(el.kind) != "electro":
		return false
	# Только контакт реле давления — кабель от корпуса KP; device (PT/RTD meter) = щит.
	if str(el.member_role) != "contact":
		return false
	return _pressure_switch_primary_id(el_id) == sens_span_id


## Конец провода у gland полевого кабеля датчика (схема: sensor/KP → щит).
## Tip в 3D — веер у gland; НШВИ нет, только кембрик на изоляции (как у ввода XS).
func _wire_end_is_sensor_gland(wire, at_a: bool) -> bool:
	if wire == null:
		return false
	var sid: int = _wire_sensor_cabinet_span(wire)
	if sid < 0:
		return false
	var eid: int = int(wire.a_id) if at_a else int(wire.b_id)
	return _wire_end_is_sensor_field(eid, sid)


## НШВИ с учётом gland-конца полевого кабеля (PT/KP/датчик).
func _wire_end_wants_nshvi(wire, at_a: bool) -> bool:
	if _wire_end_is_sensor_gland(wire, at_a):
		return false
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	return _end_wants_nshvi(el_id, port)


func _is_sensor_el(el_id: int) -> bool:
	if circuit == null or el_id < 0:
		return false
	var el = circuit.get_element(el_id)
	return el != null and str(el.kind) == "sensor"


## Primary для портов на полевом корпусе: KP1.1 (contact) / клеммы ПИП (device).
## Вторичка ТС (rtd_meter) — DIN в щите, не сюда: иначе tip «1» берётся с зонда.
func _pressure_switch_primary_id(el_id: int) -> int:
	if circuit == null or el_id < 0:
		return -1
	var el = circuit.get_element(el_id)
	if el == null or str(el.kind) != "electro":
		return -1
	var role: String = str(el.member_role)
	if role != "contact" and role != "device":
		return -1
	var prim = circuit.get_element(int(el.group_id))
	if prim == null or str(prim.kind) != "sensor":
		return -1
	var scls: String = str(prim.sensor_class)
	if role == "contact" and scls != "pressure_switch":
		return -1
	# Только field TX: клеммы на корпусе ПИП. rtd_meter — модуль щита.
	if role == "device" and scls != "pressure_tx":
		return -1
	return int(prim.id)


## Обновить дисплей вторички ТС в щите по analog_value primary.
func _sync_rtd_meter_display(primary) -> void:
	if circuit == null or primary == null:
		return
	if str(primary.sensor_class) != "rtd":
		return
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) != "device" or str(m.electro_class) != "rtd_meter":
			continue
		# DIN-модуль в шкафу — не в _records полевых машин.
		var root: Node3D = _electro_port_root(int(m.id))
		if root == null:
			continue
		IsoElectro.apply_rtd_meter_display(root, float(primary.analog_value), bool(primary.sensor_powered))


## Полевой кабель датчика → щит: жилы внутри от gland; снаружи — оболочка.
func _wire_sensor_cabinet_span(wire) -> int:
	if wire == null or circuit == null:
		return -1
	var a_sens: bool = _is_sensor_el(int(wire.a_id))
	var b_sens: bool = _is_sensor_el(int(wire.b_id))
	var a_ps: int = _pressure_switch_primary_id(int(wire.a_id))
	var b_ps: int = _pressure_switch_primary_id(int(wire.b_id))
	# Контакт KP1.1 ↔ щит → оболочка от корпуса реле давления.
	if a_ps >= 0 and not b_sens and b_ps < 0:
		var other_b = circuit.get_element(int(wire.b_id))
		if other_b != null and str(other_b.kind) == "electro" \
				and str(other_b.electro_mount) in ["din", "door"]:
			return a_ps
	if b_ps >= 0 and not a_sens and a_ps < 0:
		var other_a = circuit.get_element(int(wire.a_id))
		if other_a != null and str(other_a.kind) == "electro" \
				and str(other_a.electro_mount) in ["din", "door"]:
			return b_ps
	if a_sens == b_sens:
		return -1
	var other_id: int = int(wire.b_id) if a_sens else int(wire.a_id)
	var other = circuit.get_element(other_id)
	if other == null or str(other.kind) != "electro":
		return -1
	if str(other.electro_mount) not in ["din", "door"]:
		return -1
	return int(wire.a_id) if a_sens else int(wire.b_id)


## Веер жил у gland: +, OUT, 0 — как у кабеля питания (отдельные старты + бирки).
## Реле давления / геркон: только OUT, 0 (сухой контакт).
func _sensor_gland_core_tip(gland_world: Vector3, port: String, sensor_id: int) -> Vector3:
	var order: PackedStringArray = PackedStringArray(["+", "OUT", "0"])
	if circuit != null:
		var sel = circuit.get_element(sensor_id)
		if sel != null and str(sel.kind) == "sensor":
			var scls: String = str(sel.sensor_class)
			if scls == "pressure_tx":
				order = PackedStringArray(["+", "-", "OUT"])
			elif scls == "rtd":
				order = preload("res://scripts/domain/rtd_nsx.gd").core_names(int(sel.wire_scheme))
			elif scls == "pressure_switch" or scls == "reed" \
					or (not bool(sel.sensor_active) and SensorSig.normalize_output(str(sel.output_type)) == SensorSig.OUT_CONTACT):
				order = PackedStringArray(["OUT", "0"])
	var idx: int = order.find(port)
	if idx < 0:
		idx = 0
	var core_od: float = Circuit.wire_od_mm(0.75) * 0.001
	var pitch: float = core_od + Parts.mm(0.8)
	var nwire: int = order.size()
	var ox: float = (float(idx) - float(nwire - 1) * 0.5) * pitch
	# Как supply: концы жил выше gland, чтобы хватило места под кембрик ≥20 мм.
	return gland_world + Vector3(ox, Parts.mm(34.0), Parts.mm(1.0))


func _sensor_cable_exit_world(sensor_id: int):
	var rec = _records.get(sensor_id, null)
	if rec == null:
		return null
	var root: Node3D = rec["root"] as Node3D
	if root == null:
		return null
	if root.has_meta("cable_exit_local"):
		return root.global_transform * (root.get_meta("cable_exit_local") as Vector3)
	var ports: Dictionary = root.get_meta("ports") if root.has_meta("ports") else {}
	if ports.has("OUT"):
		return root.global_transform * ports["OUT"]
	return root.global_position


func _sensor_cable_exit_dir(sensor_id: int) -> Vector3:
	var rec = _records.get(sensor_id, null)
	if rec == null:
		return Vector3.LEFT
	var root: Node3D = rec["root"] as Node3D
	if root == null:
		return Vector3.LEFT
	if root.has_meta("cable_exit_dir"):
		var d: Vector3 = root.global_transform.basis * (root.get_meta("cable_exit_dir") as Vector3)
		if d.length_squared() > 1.0e-10:
			return d.normalized()
	return -root.global_transform.basis.x.normalized()


func _nearest_gland_world(from: Vector3) -> Vector3:
	return _gland_world_for_sensor(-1, from)


## Сколько слотов gland занято вводами питания (XS) — датчики начинаются после них.
func _supply_gland_slot_count() -> int:
	if circuit == null:
		return 0
	var n: int = 0
	for el in circuit.elements:
		if el != null and str(el.kind) == "electro" and str(el.electro_class) == "supply":
			n += 1
	return n


## Кабельный ввод щита: слот датчика ≠ ввод питания; датчики — с offset по числу supply.
func _gland_world_for_sensor(sensor_id: int, from: Vector3) -> Vector3:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return from + Vector3(0.0, -0.2, 0.3)
	var glands: Array = cab.get_meta("gland_positions", []) as Array
	if glands.is_empty():
		return cab.global_transform * Vector3(0.0, Parts.mm(6.0), Parts.mm(30.0))
	var supply_n: int = _supply_gland_slot_count()
	if sensor_id >= 0 and circuit != null:
		var ids: Array = []
		for wire in circuit.wires:
			var sid: int = _wire_sensor_cabinet_span(wire)
			if sid >= 0 and not ids.has(sid):
				ids.append(sid)
		ids.sort()
		var idx: int = ids.find(sensor_id)
		if idx < 0:
			idx = abs(sensor_id) % maxi(glands.size(), 1)
		# Пропускаем слоты 0..supply_n-1 (кабели XS / mains).
		var slot: int = (supply_n + idx) % glands.size()
		return cab.global_transform * (glands[slot] as Vector3)
	# Fallback без id: ближайший свободный от питания слот.
	var start: int = mini(supply_n, glands.size() - 1)
	var best: Vector3 = cab.global_transform * (glands[start] as Vector3)
	var best_d: float = from.distance_squared_to(best)
	for i in range(start, glands.size()):
		var g: Vector3 = cab.global_transform * (glands[i] as Vector3)
		var d: float = from.distance_squared_to(g)
		if d < best_d:
			best_d = d
			best = g
	return best


func _gland_inner_tip(gland_world: Vector3) -> Vector3:
	# Совпадает с высотой веера жил (см. _sensor_gland_core_tip).
	return gland_world + Vector3(0.0, Parts.mm(34.0), Parts.mm(1.0))


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
	var cab_sl: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door_sl: Node3D = cab_sl.get_node_or_null("DoorHinge/Door") as Node3D if cab_sl != null else null
	var sa: MeshInstance3D = _hose_find_tip(node, "SleeveA", door_sl) as MeshInstance3D
	var sb: MeshInstance3D = _hose_find_tip(node, "SleeveB", door_sl) as MeshInstance3D
	var na: Node3D = _hose_find_tip(node, "NshviA", door_sl)
	var nb: Node3D = _hose_find_tip(node, "NshviB", door_sl)
	if sa == null or sb == null:
		return
	# Dense LOD: кембрик/НШВИ остаются; подпись — одна сторона (см. _orient_mark_labels).
	if (not is_elec) or pts.size() < 2 or wire_num <= 0 or wire == null:
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
	var nshvi_a: bool = _wire_end_wants_nshvi(wire, true)
	var nshvi_b: bool = _wire_end_wants_nshvi(wire, false)
	var hide_a: bool = _port_needs_double_nshvi(int(wire.a_id), str(wire.a_port))
	var hide_b: bool = _port_needs_double_nshvi(int(wire.b_id), str(wire.b_port))
	# Конец у датчика на схеме = старт жилы у gland: кембрик как у ввода питания, без НШВИ.
	# PT/KP клеммы тоже (не только kind=sensor) — иначе trim НШВИ даёт щель у кембрика.
	if _wire_end_is_sensor_gland(wire, true):
		nshvi_a = false
		hide_a = false
	if _wire_end_is_sensor_gland(wire, false):
		nshvi_b = false
		hide_b = false
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
	# Кембрик: полный реквизит; gland/источник — на изоляции без НШВИ.
	# Дверца (span и local-перемычка): кембрик на подъёме; подпись от полотна.
	var mark_a: String = circuit.wire_end_mark_label(wire, true)
	var mark_b: String = circuit.wire_end_mark_label(wire, false)
	var door_a: bool = _electro_mount_of(int(wire.a_id)) == "door"
	var door_b: bool = _electro_mount_of(int(wire.b_id)) == "door"
	var door_local: bool = _wire_is_door_local(wire)
	if door_a and (nshvi_a or hide_a):
		_place_door_mark_sleeve(sa, tip_a, dir_a, mark_r, mark_a, yaw_a, hide_a)
	else:
		_place_mark_sleeve(sa, tip_a, dir_a, mark_r, mark_a, yaw_a, hide_a, nshvi_a, face_a)
	if door_b and (nshvi_b or hide_b):
		_place_door_mark_sleeve(sb, tip_b, dir_b, mark_r, mark_b, yaw_b, hide_b)
	else:
		_place_mark_sleeve(sb, tip_b, dir_b, mark_r, mark_b, yaw_b, hide_b, nshvi_b, face_b)
	# После расстановки в world — дверные концы на полотно (едут с анимацией без remesh).
	if door_sl != null and (door_a or door_b or door_local):
		_hose_bind_door_end_tips(node, wire, door_sl)


## Чёрная оболочка полевого кабеля датчика → gland снизу щита (как трубка).
func _sync_sensor_cable_sheaths() -> void:
	if circuit == null or _hoses == null:
		return
	var wanted: Dictionary = {} # sensor_id -> true
	for wire in circuit.wires:
		var sid: int = _wire_sensor_cabinet_span(wire)
		if sid >= 0:
			wanted[sid] = true
	var stale: Array = []
	for sid in _sensor_sheath_nodes.keys():
		if not wanted.has(int(sid)):
			stale.append(int(sid))
	for sid2 in stale:
		var dead: Node3D = _sensor_sheath_nodes[sid2] as Node3D
		if dead != null and is_instance_valid(dead):
			dead.queue_free()
		_sensor_sheath_nodes.erase(sid2)
	for sid3 in wanted.keys():
		var sensor_id: int = int(sid3)
		var exit_v = _sensor_cable_exit_world(sensor_id)
		if exit_v == null:
			continue
		var exit_pos: Vector3 = exit_v as Vector3
		var exit_dir: Vector3 = _sensor_cable_exit_dir(sensor_id)
		var gland: Vector3 = _gland_world_for_sensor(sensor_id, exit_pos)
		var node: Node3D = _sensor_sheath_nodes.get(sensor_id, null) as Node3D
		if node == null or not is_instance_valid(node):
			node = _make_hose_node()
			node.name = "SensorSheath_%d" % sensor_id
			_hoses.add_child(node)
			_sensor_sheath_nodes[sensor_id] = node
			# Без бирок/НШВИ на оболочке.
			for sn in ["SleeveA", "SleeveB", "NshviA", "NshviB"]:
				var ch: Node = node.get_node_or_null(sn)
				if ch != null:
					ch.visible = false
		var mat: StandardMaterial3D = node.get_meta("mat") as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.08, 0.08, 0.1)
			mat.roughness = 0.7
			mat.metallic = 0.05
		var sheath_r: float = Parts.mm(3.2)
		var sig: String = "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.4f" % [
			exit_pos.x, exit_pos.y, exit_pos.z, gland.x, gland.y, gland.z, sheath_r
		]
		# Оболочка может не меняться при смене 2/3/4 — веер жил у gland всё равно обновить.
		if str(node.get_meta("geom_sig", "")) != sig:
			# Маршрут как у пневмотрубки (Безье), не ортогональный электропровод.
			var da: Vector3 = exit_dir
			var db: Vector3 = Vector3.DOWN # вход в gland снизу вверх → направление подхода снизу
			var pts: PackedVector3Array = _hose_curve(exit_pos, da, gland, db, 36, sheath_r)
			_apply_hose_path(node, pts, sheath_r, 0.0, 0.0)
			_hide_hose_tube_cab(node)
			node.set_meta("geom_sig", sig)
		node.visible = true
		# Простой gland на нижней стенке; sig внутри учитывает wire_scheme / число жил.
		_ensure_sensor_gland_visual(gland, sheath_r, sensor_id)


func _ensure_sensor_gland_visual(gland_world: Vector3, sheath_r: float, sensor_id: int) -> void:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return
	var holder: Node3D = cab.get_node_or_null("SensorGlands") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "SensorGlands"
		cab.add_child(holder)
	var name: String = "SG%d" % sensor_id
	var node: Node3D = holder.get_node_or_null(name) as Node3D
	var local_g: Vector3 = cab.to_local(gland_world)
	# Как кабель питания: оболочка → gland → короткие цветные жилы до кембриков.
	var order: PackedStringArray = PackedStringArray(["+", "OUT", "0"])
	if circuit != null:
		var sgel = circuit.get_element(sensor_id)
		if sgel != null and str(sgel.kind) == "sensor":
			var sgcls: String = str(sgel.sensor_class)
			if sgcls == "pressure_tx":
				# 3-wire ПИП: + коричн., − голубой, OUT чёрный (сигнал).
				order = PackedStringArray(["+", "-", "OUT"])
			elif sgcls == "rtd":
				order = preload("res://scripts/domain/rtd_nsx.gd").core_names(int(sgel.wire_scheme))
			elif sgcls == "pressure_switch" or sgcls == "reed":
				order = PackedStringArray(["OUT", "0"])
	var core_od: float = Circuit.wire_od_mm(0.75) * 0.001
	var core_r: float = core_od * 0.5
	var pitch: float = core_od + Parts.mm(0.8)
	var sig: String = "v2|%s|%.3f|%.4f|%.4f" % [",".join(order), local_g.x, sheath_r, pitch]
	if node != null and str(node.get_meta("sig", "")) == sig:
		return
	if node != null:
		node.queue_free()
	node = Node3D.new()
	node.name = name
	node.set_meta("sig", sig)
	holder.add_child(node)
	node.position = local_g
	var gland_body_r: float = sheath_r + Parts.mm(1.2)
	var gland_nut_r: float = sheath_r + Parts.mm(2.0)
	Parts.cyl(node, gland_nut_r, Parts.mm(8.0), Vector3(0.0, Parts.mm(2.0), 0.0), "y", Parts.mat("sgland_nut", Color(0.12, 0.12, 0.14), 0.15, 0.55), 8, "shell")
	Parts.cyl(node, gland_body_r, Parts.mm(4.0), Vector3(0.0, Parts.mm(8.0), 0.0), "y", Parts.mat("sgland_body", Color(0.18, 0.18, 0.2), 0.2, 0.6), 12, "shell")
	# Веер жил: от верха gland до старта кембрика (без пустоты).
	var y_core0: float = Parts.mm(10.0)
	var y_core1: float = Parts.mm(34.0)
	var core_h: float = y_core1 - y_core0
	var nwire: int = order.size()
	for i in nwire:
		var nm: String = str(order[i])
		var ox: float = (float(i) - float(nwire - 1) * 0.5) * pitch
		var core_mid := Vector3(ox, (y_core0 + y_core1) * 0.5, Parts.mm(1.0))
		var col: Color = _sensor_core_color(nm)
		# v3: −/0 = голубой (раньше кэш mat мог держать серый/чёрный).
		Parts.cyl(
			node, core_r, core_h, core_mid, "y",
			Parts.mat("sgcore_v3_%s_%d" % [nm, sensor_id], col, 0.15, 0.55), 8, "shell"
		)


func _sensor_core_color(port: String) -> Color:
	match str(port):
		"+":
			return Circuit.line_color_from_id("brown")
		"0", "-":
			return Circuit.line_color_from_id("lightblue")
		"OUT":
			return Circuit.line_color_from_id("black")
		"1":
			return Circuit.line_color_from_id("brown")
		"2":
			return Circuit.line_color_from_id("white")
		"3":
			return Circuit.line_color_from_id("lightblue")
		"4":
			return Circuit.line_color_from_id("black")
		_:
			return Color(0.35, 0.35, 0.38)


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
	var body_r: float = maxf(collar_r, tip_od + 0.00015)
	# Корень = геометрический центр всего колпачка.
	var collar_center: Vector3 = tip_pos + tang * (peek - join + collar_h * 0.5)
	var basis: Basis = _sleeve_basis_door_panel(tang, yaw_twist, face_out)
	root.global_transform = Transform3D(basis, collar_center)
	root.visible = true
	root.set_meta("yaw_twist", yaw_twist)
	# Локально: −Y к клемме. Снизу конус → сверху цилиндр (всегда, и на dense).
	var y0: float = -collar_h * 0.5
	var dense: bool = _dense_elec_lod()
	var segs: int = 12 if dense else 16
	var cone: MeshInstance3D = root.get_node_or_null("CollarCone") as MeshInstance3D
	if cone != null:
		var ccyl: CylinderMesh = _nshvi_ensure_cyl_mesh(cone)
		ccyl.bottom_radius = tip_od
		ccyl.top_radius = body_r
		ccyl.height = cone_h
		ccyl.radial_segments = segs
		_nshvi_apply_collar_mat(cone, collar_col)
		cone.position = Vector3(0.0, y0 + cone_h * 0.5, 0.0)
		cone.scale = Vector3.ONE
		cone.visible = true
	var body: MeshInstance3D = root.get_node_or_null("CollarBody") as MeshInstance3D
	if body != null:
		var bcyl: CylinderMesh = _nshvi_ensure_cyl_mesh(body)
		bcyl.top_radius = body_r
		bcyl.bottom_radius = body_r
		bcyl.height = body_h
		bcyl.radial_segments = segs
		_nshvi_apply_collar_mat(body, collar_col)
		body.position = Vector3(0.0, y0 + cone_h + body_h * 0.5, 0.0)
		body.scale = Vector3.ONE
		body.visible = true
	var old_collar: MeshInstance3D = root.get_node_or_null("Collar") as MeshInstance3D
	if old_collar != null:
		old_collar.visible = false
	var metal: MeshInstance3D = root.get_node_or_null("Metal") as MeshInstance3D
	if metal != null:
		var mcyl: CylinderMesh = _nshvi_ensure_cyl_mesh(metal)
		mcyl.top_radius = metal_r
		mcyl.bottom_radius = metal_r
		mcyl.height = metal_h
		mcyl.radial_segments = 10 if dense else 12
		metal.position = Vector3(0.0, -(collar_h * 0.5 + metal_h * 0.5 - join), 0.0)
		metal.rotation = Vector3.ZERO
		metal.scale = Vector3.ONE
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


## CylinderMesh после RID-лимита может быть null / не Cylinder — всегда чинить.
func _nshvi_ensure_cyl_mesh(mi: MeshInstance3D) -> CylinderMesh:
	var cyl: CylinderMesh = mi.mesh as CylinderMesh if mi != null else null
	if cyl == null:
		cyl = CylinderMesh.new()
		if mi != null:
			mi.mesh = cyl
	return cyl


func _ensure_nshvi_collar_parts(root: Node3D) -> void:
	if root == null:
		return
	for part_name in ["CollarBody", "CollarCone"]:
		var existing: MeshInstance3D = root.get_node_or_null(part_name) as MeshInstance3D
		if existing != null:
			_nshvi_ensure_cyl_mesh(existing)
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
		# Небольшой зазор вместо overlap — иначе z-fight «зубьев» кембрик↔колпачок.
		var gap: float = 0.00025
		mark_start = ELEC_NSHVI_METAL_PEEK - join + collar_h + gap
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
	# Dense: одна сторона подписи (NumP) — вдвое меньше Label3D draw calls.
	var dense_one_side: bool = _dense_elec_lod()
	for child in sleeve.get_children():
		if not (child is Label3D):
			continue
		var lab: Label3D = child as Label3D
		if not lab.has_meta("side"):
			lab.visible = false
			continue
		var side: float = float(lab.get_meta("side"))
		if dense_one_side and side < 0.0:
			lab.visible = false
			continue
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
	# Dense: сдвоенные НШВИ оставляем (без Label3D) — иначе на сдвоенных клеммах пусто
	# (одиночные там скрыты через hide_a/hide_b).
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
		# На дверце — parent на полотно (иначе отстают при open/close).
		var door_n: Node3D = _hose_cabinet_door()
		var on_door: bool = _electro_mount_of(el_id2) == "door"
		var dname: String = "DblNshvi_%d_%s" % [el_id2, port2.replace("/", "_")]
		if on_door and door_n != null:
			_hose_reparent_keep_global(node, door_n, dname)
		elif node.get_parent() != _hoses:
			_hose_reparent_keep_global(node, _hoses, dname)


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
	var dense: bool = _dense_elec_lod()
	var tang: Vector3 = nrm.normalized() if nrm.length_squared() > 1.0e-12 else Vector3.UP
	# Не пересобирать пирамиду каждый кадр, пока поза/Ø те же.
	var place_sig: String = "%.4f,%.4f,%.4f|%.3f,%.3f,%.3f|%.2f|%d" % [
		port_pos.x, port_pos.y, port_pos.z, tang.x, tang.y, tang.z, mm2, 1 if dense else 0,
	]
	if str(root.get_meta("place_sig", "")) == place_sig and root.visible:
		return
	root.set_meta("place_sig", place_sig)
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
		cone.scale = Vector3.ONE
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
		body.scale = Vector3.ONE
		body.visible = true
	var old_collar: MeshInstance3D = root.get_node_or_null("Collar") as MeshInstance3D
	if old_collar != null:
		old_collar.visible = false
		for child in old_collar.get_children():
			if child is Label3D:
				(child as Label3D).visible = false
	# Подписи — дорогие Label3D; на плотной схеме гасим (меш колпачка оставляем).
	if dense:
		for child2 in root.find_children("*", "Label3D", true, false):
			(child2 as Label3D).visible = false
	var metal: MeshInstance3D = root.get_node_or_null("Metal") as MeshInstance3D
	if metal != null:
		var cyl: CylinderMesh = metal.mesh as CylinderMesh
		if cyl == null:
			cyl = CylinderMesh.new()
			metal.mesh = cyl
		cyl.top_radius = metal_r
		cyl.bottom_radius = metal_r
		cyl.height = metal_h
		cyl.radial_segments = 8 if dense else 12
		metal.position = Vector3(0.0, -(collar_h * 0.5 + metal_h * 0.5 - join), 0.0)
		metal.scale = Vector3.ONE
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


## Нормаль лицевой плоскости для кембрика: DIN +Z щита; дверца −Z полотна
## (от двери внутрь / к зрителю на клеммах — иначе цифры смотрят в лист).
func _sleeve_face_out_for_end(el_id: int) -> Vector3:
	if _electro_mount_of(el_id) != "door":
		return Vector3(0.0, 0.0, 1.0)
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	if cab == null:
		return Vector3(0.0, 0.0, -1.0)
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab)
	var door: Node3D = dd.get("door", null) as Node3D
	if door == null:
		return Vector3(0.0, 0.0, -1.0)
	# Порты на −Z; подпись от полотна к зрителю.
	var n: Vector3 = door.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	if n.length_squared() < 1.0e-12:
		return Vector3(0.0, 0.0, -1.0)
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
		var cab_pk: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
		var door_pk: Node3D = cab_pk.get_node_or_null("DoorHinge/Door") as Node3D if cab_pk != null else null
		for end_name in ["SleeveA", "SleeveB"]:
			var sleeve: MeshInstance3D = _hose_find_tip(node, end_name, door_pk) as MeshInstance3D
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
	if pts.size() < 2 or radius < 1.0e-7:
		return mesh
	# Микро-сегменты → вырожденные кольца (заужения / чёрные «короны» у кембрика).
	var min_seg: float = maxf(radius * 0.45, 0.00022)
	var path: PackedVector3Array = _hose_tube_path_sanitize(pts, min_seg)
	if path.size() < 2:
		return mesh
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
			if dot < -0.995:
				# ~180°: новый кадр от ti (negation даёт складку / чёрные треугольники).
				var r2: Vector3 = Vector3.RIGHT if absf(ti.dot(Vector3.UP)) > 0.9 else Vector3.UP
				normal = (r2 - ti * r2.dot(ti)).normalized()
			elif dot < 0.9995:
				var axis: Vector3 = tprev.cross(ti)
				if axis.length_squared() > 1.0e-12:
					normal = Basis(axis.normalized(), acos(dot)) * normal
			normal = (normal - ti * normal.dot(ti))
			if normal.length_squared() < 1.0e-12:
				var r3: Vector3 = Vector3.RIGHT if absf(ti.dot(Vector3.UP)) > 0.9 else Vector3.UP
				normal = (r3 - ti * r3.dot(ti)).normalized()
			else:
				normal = normal.normalized()
			binorm = ti.cross(normal)
			if binorm.length_squared() < 1.0e-12:
				var r4: Vector3 = Vector3.FORWARD if absf(ti.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
				normal = (r4 - ti * r4.dot(ti)).normalized()
				binorm = ti.cross(normal).normalized()
			else:
				binorm = binorm.normalized()
			normal = binorm.cross(ti).normalized()
		var v_base: int = verts.size()
		var u: float = float(i) / float(maxi(n_pts - 1, 1))
		for s in side_n:
			var ang: float = TAU * float(s) / float(side_n)
			var dir: Vector3 = (normal * cos(ang) + binorm * sin(ang)).normalized()
			verts.append(path[i] + dir * radius)
			norms.append(dir)
			uvs.append(Vector2(float(s) / float(side_n), u))
		if i > 0 and v_base >= side_n:
			var prev: int = v_base - side_n
			for s in side_n:
				var s1: int = (s + 1) % side_n
				indices.append(prev + s)
				indices.append(v_base + s)
				indices.append(v_base + s1)
				indices.append(prev + s)
				indices.append(v_base + s1)
				indices.append(prev + s1)
	if verts.size() < side_n * 2 or indices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Убрать микро-дубли до построения трубки (иначе вырожденные кольца на trim/гибе).
func _hose_tube_path_sanitize(pts: PackedVector3Array, min_seg: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts
	var eps: float = maxf(min_seg, 0.00018)
	var out := PackedVector3Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		if out[out.size() - 1].distance_to(pts[i]) >= eps:
			out.append(pts[i])
	var last: Vector3 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_squared_to(last) < eps * eps:
		if out.size() >= 2:
			out[out.size() - 1] = last
		else:
			out.append(last)
	else:
		out.append(last)
	return out if out.size() >= 2 else pts


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
			if cursor >= _flow_pool.size() - 2:
				break
			var q_vis: float = float(wire.flow_vis)
			var qabs: float = absf(q_vis)
			# Держим конусы, пока ещё крутится фаза — короткие провалы Q не гасят линию.
			var hold_anim: bool = float(wire.flow_anim_speed) > 0.012 and float(wire.flow_sign) != 0.0
			if qabs < SimV.FLOW_DEAD:
				if hold_anim:
					q_vis = float(wire.flow_sign) * SimV.FLOW_DEAD * 2.5
					qabs = absf(q_vis)
				else:
					wire.flow_puff_n = 0
					continue
			var node: Node3D = _hose_nodes.get(wire.id, null)
			if node == null or not node.visible:
				continue
			var curve: PackedVector3Array = node.get_meta("curve_pts", PackedVector3Array())
			if curve.size() < 2:
				continue
			var ea = circuit.get_element(int(wire.a_id))
			if ea != null and Geom.port_domain(ea, str(wire.a_port)) in ["electric", "optic"]:
				continue
			var n_puffs: int = SimV.puff_count_sticky(qabs, int(wire.flow_puff_n))
			wire.flow_puff_n = n_puffs
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
			if dir3 == 0.0:
				dir3 = float(wire.flow_sign)
			if dir3 == 0.0:
				dir3 = 1.0
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
				elif str(el.accessory_class) == "relief":
					cursor = _puff_safety_relief(el, cursor)
			elif el.kind == "valve":
				cursor = _puff_open_port_atm(el, cursor)
				# Глушители 3/5 — конусы всегда (не только в рентгене).
				cursor = _puff_valve_muffler_exhaust(el, cursor)
				if xray:
					cursor = _puff_valve_flows(el, cursor)
	for i in range(cursor, _flow_pool.size()):
		_flow_pool[i].visible = false


## Предохранительный клапан: конусы из глушителя/штуцера сброса (−X).
func _puff_safety_relief(el, cursor: int) -> int:
	var Parts = preload("res://scripts/view3d/pneumo_parts.gd")
	var root = _records.get(el.id, {}).get("root", null)
	if root == null:
		return cursor
	# Активный сброс: latch/хвост или тарелка открыта.
	var active: bool = circuit.regulator_relief_active(int(el.id)) \
			or float(el.opening) > 0.08 or bool(el.pressed)
	if not active:
		return cursor
	var local: Vector3 = Vector3(-Parts.mm(14.0), -Parts.mm(2.0), 0.0)
	if root.has_meta("relief_local"):
		local = root.get_meta("relief_local")
	var outward: Vector3 = Vector3.LEFT
	if root.has_meta("relief_dir"):
		outward = (root.global_transform.basis * root.get_meta("relief_dir")).normalized()
	else:
		outward = (root.global_transform.basis * Vector3.LEFT).normalized()
	var pos: Vector3 = root.global_transform * local
	var n_puffs: int = 4 if float(el.opening) > 0.35 or bool(el.pressed) else 2
	var od: float = maxf(float(el.tube_od_mm), 6.0)
	for k in n_puffs:
		if cursor >= _flow_pool.size():
			break
		var t: float = fposmod(circuit.sim_time * 1.45 + float(k) / float(maxi(n_puffs, 1)), 1.0)
		_place_puff(
			cursor,
			pos + outward * (0.014 + t * 0.09),
			Color(0.62, 0.9, 1.0, 0.85),
			outward,
			od
		)
		cursor += 1
	return cursor


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
	# Выхлоп 2→3 / 4→5 — только снаружи из глушителя (_puff_valve_muffler_exhaust).
	# Оранжевые конусы «сквозь корпус» по пути к R не рисуем: в рентгене выглядят как мусор внутри ПР.
	# Здесь — только рабочие мостики (P↔A / P↔B) в x-ray.
	var pairs: Array = ValveLib.path_pairs_from_spool(el, int(el.valve_pos))
	for pair in pairs:
		if cursor >= _flow_pool.size() - 1:
			break
		if not (pair is Array) or pair.size() < 2:
			continue
		var a := str(pair[0])
		var b := str(pair[1])
		if ValveCat.is_exhaust_port(a) or ValveCat.is_exhaust_port(b):
			continue
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
		var qmag := maxf(absf(qa), absf(qb))
		# Устаканилось — не гоняем конусы туда-сюда.
		if qmag < 4.0e-5 and absf(pa_p - pb_p) < 2.5e4:
			continue
		var from_a: bool = pa_p >= pb_p + 500.0
		if absf(pa_p - pb_p) < 2000.0:
			from_a = qa < qb
		var col := Color(0.45, 0.9, 1.0, 0.9)
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
	# ×1.5 — читаемее на общем плане цеха.
	var s: float = clampf(maxf(od_mm, 2.0) / 6.0, 0.55, 2.8) * 1.5
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
	# Контакт KP1.1 → клеммы на 3D корпусе реле давления.
	var ps_id: int = _pressure_switch_primary_id(el_id)
	if ps_id >= 0:
		var prec = _records.get(ps_id, null)
		if prec != null:
			var pports: Dictionary = prec["root"].get_meta("ports") if prec["root"].has_meta("ports") else {}
			var pkey: String = port
			if not pports.has(pkey):
				if port in ["1", "13"]:
					pkey = "OUT" if pports.has("OUT") else "1"
				elif port in ["2", "14"]:
					pkey = "0" if pports.has("0") else "2"
			if pports.has(pkey):
				return prec["root"].global_transform * pports[pkey]
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
	var ps_id2: int = _pressure_switch_primary_id(el_id)
	if ps_id2 >= 0:
		var prec2 = _records.get(ps_id2, null)
		if prec2 != null:
			var root_ps: Node3D = prec2["root"] as Node3D
			var dirs_ps: Dictionary = root_ps.get_meta("dirs") if root_ps.has_meta("dirs") else {}
			var dk: String = "OUT" if port in ["1", "13", "OUT"] else "0"
			if dirs_ps.has(dk):
				var dps: Vector3 = root_ps.global_transform.basis * dirs_ps[dk]
				if dps.length_squared() > 1.0e-8:
					return dps.normalized()
			return Vector3.LEFT
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
	# Ноги ввода N/PE: жилы на SupplyCables/E{primary}, не на отдельном модуле.
	elif str(el.electro_class) == "supply_leg" and int(el.group_id) > 0:
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


## Оптокабель: пеньки по нормали порта; при выходе «спиной» к peer — длиннее дуга (U-turn без перелома).
func _hose_curve_optic(a: Vector3, da: Vector3, b: Vector3, db: Vector3, n: int, tube_r: float = 0.0012) -> PackedVector3Array:
	var na := da.normalized() if da.length_squared() > 1.0e-10 else Vector3.UP
	var nb := db.normalized() if db.length_squared() > 1.0e-10 else Vector3.UP
	var r: float = maxf(tube_r, 0.0010)
	var span0: float = maxf(a.distance_to(b), 0.001)
	var to_b: Vector3 = ((b as Vector3) - (a as Vector3)) / span0
	var leave_a: float = na.dot(to_b)
	var leave_b: float = nb.dot(-to_b)
	# Выход «назад» от peer (типичный приёмник ~180°) — удлиняем пенёк вдоль хвоста.
	var rev_a: float = clampf(0.35 - leave_a, 0.0, 1.35)
	var rev_b: float = clampf(0.35 - leave_b, 0.0, 1.35)
	var stub_a: float = clampf(r * (3.2 + 10.0 * rev_a), 0.008, 0.045)
	var stub_b: float = clampf(r * (3.2 + 10.0 * rev_b), 0.008, 0.045)
	stub_a = minf(stub_a, span0 * 0.42)
	stub_b = minf(stub_b, span0 * 0.42)
	var a1: Vector3 = a + na * stub_a
	var b1: Vector3 = b + nb * stub_b
	var span: float = maxf(a1.distance_to(b1), 0.001)
	var turn: float = clampf(1.0 - absf(na.dot(nb)), 0.0, 1.0)
	var reverse: float = maxf(rev_a, rev_b)
	var tan_lo: float = maxf(0.018, r * 8.0)
	var tan_hi: float = maxf(0.22, r * 48.0)
	var tan_len: float = clampf(
		span * (0.36 + 0.22 * turn + 0.38 * reverse),
		tan_lo, tan_hi
	)
	tan_len = minf(tan_len, span * 0.62)
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
	var lod: bool = _dense_elec_lod()
	var pitch: float = 0.0045 if lod else 0.0028
	var samples_per_rib: int = 6 if lod else 10
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
	var ring: int = clampi(sides, 8, 12) if lod else maxi(sides, 20)
	return _build_tube_mesh_varying(dense, radii, ring)


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
	# При анимации — квант ~2° по шарниру (не каждый мм → меньше фризов).
	var sig: String
	if door_animating:
		var hinge_q: int = 0
		var hinge_n: Node3D = cab.get_node_or_null("DoorHinge") as Node3D
		if hinge_n != null:
			hinge_q = int(round(hinge_n.rotation_degrees.y * 0.5))
		sig = "v6a|h%d|%.3f|%d" % [hinge_q, r, bundle.size()]
	else:
		sig = "v6|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.3f|%d" % [a.x, a.y, a.z, b.x, b.y, b.z, r, bundle.size()]
	if sig == _door_flex_sig and mi.mesh != null:
		mi.visible = true
		return
	var pts: PackedVector3Array = _door_flex_centerline(anchors)
	if pts.size() < 2:
		return
	var flex_sides: int = 8 if door_animating else (10 if _dense_elec_lod() else 20)
	var new_mesh: ArrayMesh = _build_ribbed_tube_mesh(pts, r, flex_sides)
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


## Клемма дверцы (−Z): НШВИ по нормали → запас → 90° вверх → кембрик → бок КК → канал → гофра.
func _hose_door_duct_run(
	port: Vector3,
	n_port: Vector3,
	door_duct: Dictionary,
	to_exit: bool,
	cab: Node3D = null,
	lane: int = 0,
	door_el_id: int = -1,
	door_port_name: String = ""
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
	var dbl: bool = door_el_id >= 0 and door_port_name != "" and _port_needs_double_nshvi(door_el_id, door_port_name)
	var collar_h: float = ELEC_NSHVI_COLLAR_LEN * (1.35 if dbl else 1.0)
	var nshvi_len: float = ELEC_NSHVI_METAL_PEEK + collar_h
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var p_nshvi: Vector3 = port + na * nshvi_len
	# Прямо из колпачка, гибь вверх, затем кембрик на подъёме.
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


## НШВИ → подъём → кембрик → орто по дверце → к другому прибору (не в КК).
## Нельзя _elec_push_ortho по world XYZ: при открытой дверце (110°) получаются петли в воздухе.
func _hose_door_local_jumper(a: Vector3, na: Vector3, b: Vector3, nb: Vector3) -> PackedVector3Array:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var door: Node3D = cab.get_node_or_null("DoorHinge/Door") as Node3D if cab != null else null
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab) if cab != null else {}
	var a_run: Dictionary = _hose_door_rise_mark_pts(a, na, door, dd, false)
	var b_run: Dictionary = _hose_door_rise_mark_pts(b, nb, door, dd, false)
	var pts_a: PackedVector3Array = a_run.get("pts", PackedVector3Array()) as PackedVector3Array
	var pts_b: PackedVector3Array = b_run.get("pts", PackedVector3Array()) as PackedVector3Array
	var after_a: Vector3 = a_run.get("after", a) as Vector3
	var after_b: Vector3 = b_run.get("after", b) as Vector3
	var pts := PackedVector3Array()
	for p in pts_a:
		_hose_ortho_push(pts, p)
	if door != null:
		_elec_push_ortho_on_door(pts, door, after_a, after_b)
	else:
		_elec_push_ortho(pts, after_a, after_b)
	for i in range(pts_b.size() - 1, -1, -1):
		_hose_ortho_push(pts, pts_b[i])
	return pts


## Выход с дверного порта: НШВИ по нормали → запас → подъём → кембрик → запас.
## Возвращает {pts, after, riser}.
func _hose_door_rise_mark_pts(
	port: Vector3,
	n_port: Vector3,
	door: Node3D,
	door_duct: Dictionary,
	dbl: bool
) -> Dictionary:
	var na: Vector3 = n_port.normalized() if n_port.length_squared() > 1.0e-10 else Vector3.BACK
	var collar_h: float = ELEC_NSHVI_COLLAR_LEN * (1.35 if dbl else 1.0)
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var riser: Vector3 = Vector3.UP
	if door != null and not door_duct.is_empty():
		var y: float = float(door_duct.get("y", 0.0))
		var vh: float = float(door_duct.get("vh", Parts.mm(28.0)))
		var local: Vector3 = door.to_local(port)
		var side_sign: float = 1.0 if local.y >= y else -1.0
		var y_side: float = y + side_sign * (vh * 0.5 + Parts.mm(3.0))
		var toward_y: float = signf(y_side - local.y)
		if absf(toward_y) < 0.5:
			toward_y = -side_sign
		var door_y: Vector3 = door.global_transform.basis * Vector3(0.0, 1.0, 0.0)
		if door_y.length_squared() > 1.0e-10:
			door_y = door_y.normalized()
		riser = door_y * toward_y
	elif door != null:
		var door_y2: Vector3 = door.global_transform.basis * Vector3(0.0, 1.0, 0.0)
		if door_y2.length_squared() > 1.0e-10:
			riser = door_y2.normalized()
	var p_nshvi: Vector3 = port + na * (ELEC_NSHVI_METAL_PEEK + collar_h)
	var p_clear: Vector3 = p_nshvi + na * clear
	var p_rise: Vector3 = p_clear + riser * ELEC_DOOR_RISE_BEFORE_MARK
	var p_mark_end: Vector3 = p_rise + riser * ELEC_MARK_LEN
	var p_after: Vector3 = p_mark_end + riser * ELEC_DOOR_AFTER_MARK
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, port)
	_hose_ortho_push(pts, p_nshvi)
	_hose_ortho_push(pts, p_clear)
	_hose_ortho_push(pts, p_rise)
	_hose_ortho_push(pts, p_mark_end)
	_hose_ortho_push(pts, p_after)
	return {"pts": pts, "after": p_after, "riser": riser}


## Орто-мостик в плоскости дверцы (local X/Y).
## Z = глубина пеньков (после НШВИ/подъёма): тянуть к полотну (z≈−12) резало корпуса кнопок.
func _elec_push_ortho_on_door(pts: PackedVector3Array, door: Node3D, from_w: Vector3, to_w: Vector3) -> void:
	if door == null:
		_elec_push_ortho(pts, from_w, to_w)
		return
	if pts.is_empty():
		_hose_ortho_push(pts, from_w)
	var la: Vector3 = door.to_local(from_w)
	var lb: Vector3 = door.to_local(to_w)
	# −Z внутрь щита: min = глубже пеньков, за корпусами; не ближе полотна чем пеньки.
	var z_bridge: float = minf(la.z, lb.z)
	# Чуть глубже запаса — fillet не задевает корпуса.
	z_bridge -= Parts.mm(4.0)
	var cur: Vector3 = Vector3(la.x, la.y, z_bridge)
	# Стартовая точка мостика на общей глубине у дверцы.
	_hose_ortho_push(pts, door.to_global(cur))
	var dx: float = absf(cur.x - lb.x)
	var dy: float = absf(cur.y - lb.y)
	# Сначала большая ось — меньше «рамок» на плоскости дверцы.
	if dx >= dy:
		if dx > 1.0e-5:
			cur = Vector3(lb.x, cur.y, z_bridge)
			_hose_ortho_push(pts, door.to_global(cur))
		if dy > 1.0e-5:
			cur = Vector3(cur.x, lb.y, z_bridge)
			_hose_ortho_push(pts, door.to_global(cur))
	else:
		if dy > 1.0e-5:
			cur = Vector3(cur.x, lb.y, z_bridge)
			_hose_ortho_push(pts, door.to_global(cur))
		if dx > 1.0e-5:
			cur = Vector3(lb.x, cur.y, z_bridge)
			_hose_ortho_push(pts, door.to_global(cur))
	# Выход на глубину целевого пенька (если отличалась).
	if absf(z_bridge - lb.z) > 1.0e-5:
		_hose_ortho_push(pts, door.to_global(Vector3(lb.x, lb.y, lb.z)))


func _hose_ortho_elec_door_span(
	a: Vector3, a1: Vector3, na: Vector3,
	b: Vector3, b1: Vector3, nb: Vector3,
	ida: int, idb: int, lane: int, a_on_door: bool,
	door_el_id: int = -1, door_port_name: String = ""
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
	var door_pts: PackedVector3Array = _hose_door_duct_run(
		door_port, door_n, dd, true, cab, lane, door_el_id, door_port_name
	)
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


## Кембрик на прямом подъёме после запаса за НШВИ; цифры — от полотна двери (−Z).
func _place_door_mark_sleeve(
	sleeve: MeshInstance3D,
	tip_pos: Vector3,
	tip_dir: Vector3,
	mark_r: float,
	mark_text: String,
	yaw_twist: float,
	after_double: bool = false
) -> void:
	var cab: Node3D = _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D if _machines != null else null
	var dd: Dictionary = IsoCabinet.door_cable_duct_world(cab) if cab != null else {}
	var na: Vector3 = tip_dir.normalized() if tip_dir.length_squared() > 1.0e-12 else Vector3.BACK
	var clear: float = maxf(ELEC_DOOR_BEND_CLEAR, ELEC_DOOR_BEND_R * 1.85)
	var collar_h: float = ELEC_NSHVI_COLLAR_LEN * (1.35 if after_double else 1.0)
	var nshvi_end: Vector3 = tip_pos + na * (ELEC_NSHVI_METAL_PEEK + collar_h)
	var p_clear: Vector3 = nshvi_end + na * clear
	var riser: Vector3 = Vector3.UP
	# От полотна (−Z двери): к зрителю на клеммах, не в лист.
	var face_away: Vector3 = Vector3(0.0, 0.0, -1.0)
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
			var fn: Vector3 = door.global_transform.basis * Vector3(0.0, 0.0, -1.0)
			if fn.length_squared() > 1.0e-12:
				face_away = fn.normalized()
	var mark_origin: Vector3 = p_clear + riser * ELEC_DOOR_RISE_BEFORE_MARK
	# has_nshvi=false: кембрик уже на riser, не вдоль нормали порта.
	_place_mark_sleeve(sleeve, mark_origin, riser, mark_r * 0.92, mark_text, yaw_twist, false, false, face_away)


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
## Длина trim у дверного конца: только НШВИ (кембрик на подъёме, не в trim).
func _elec_door_tube_trim(el_id: int, port: String) -> float:
	if not _end_wants_nshvi(el_id, port) and not _port_needs_double_nshvi(el_id, port):
		return 0.0
	var collar: float = ELEC_NSHVI_COLLAR_LEN * (1.35 if _port_needs_double_nshvi(el_id, port) else 1.0)
	return ELEC_NSHVI_METAL_PEEK + collar - 0.0012


func _elec_duct_end_stub(wire, at_a: bool) -> float:
	if wire == null:
		return ELEC_SLEEVE_STUB
	# Gland полевого кабеля / ввод XS: без НШВИ, кембрик ≥20 мм — гибы только после него.
	if _wire_end_is_sensor_gland(wire, at_a):
		return ELEC_MARK_ONLY_STUB
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	if _end_wants_nshvi(el_id, port):
		return ELEC_DUCT_STUB
	if circuit != null:
		var el = circuit.get_element(el_id)
		if el != null:
			if str(el.kind) == "electro" and str(el.electro_class) in ["supply", "supply_leg"]:
				return ELEC_MARK_ONLY_STUB
			if str(el.kind) == "sensor":
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
		var vh0: float = Parts.mm(40.0)
		_elec_enter_hduct(pts, a1, clear_a, duct_z, y_in, vh0)
		_hose_ortho_push(pts, Vector3(clear_a.x, ya0, duct_z))
		_hose_ortho_push(pts, Vector3(side_x, ya0, duct_z))
		_hose_ortho_push(pts, Vector3(side_x, yb, duct_z))
		_elec_leave_hduct(pts, clear_b, duct_z, yb, y_out, vh0)
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
	var vha: float = float(ha.get("vh", Parts.mm(40.0)))
	var vhb: float = float(hb.get("vh", Parts.mm(40.0)))
	# dep не в крышку (+Z): держим глубже центра, ближе к базе.
	var sha: float = float(ha.get("sh", Parts.mm(80.0)))
	var shb: float = float(hb.get("sh", Parts.mm(80.0)))
	var za0: float = float(ha.get("z", clear_a.z - 0.04))
	var zb0: float = float(hb.get("z", clear_b.z - 0.04))
	za = clampf(za, za0 - sha * 0.30, za0 + sha * 0.12)
	zb = clampf(zb, zb0 - shb * 0.30, zb0 + shb * 0.12)
	var ya: float = ya_base + o_lat
	var yb2: float = yb_base + o_lat
	_elec_enter_hduct(pts, a1, clear_a, za, ya_base, vha)
	if absf(clear_a.y - ya) > 0.0012:
		_hose_ortho_push(pts, Vector3(clear_a.x, ya, za)) # lat только в КК
	if absf(ya - yb2) < 0.010 and absf(za - zb) < 0.008:
		_hose_ortho_push(pts, Vector3(clear_b.x, ya, za))
		_elec_leave_hduct(pts, clear_b, za, ya, yb_base, vhb)
		_elec_push_ortho(pts, clear_b, b1)
		_hose_ortho_push(pts, b1)
		_hose_ortho_push(pts, b)
		return pts
	# Верт. КК: lat→X, dep→Z. Вход в верт. — через бок (±X), не через крышку.
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
	_elec_leave_hduct(pts, clear_b, zb, yb2, yb_base, vhb)
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


## Вход в гориз. КК: clear → бок (зубья) → Z в канал. Не сквозь крышку (+Z).
func _elec_enter_hduct(
	pts: PackedVector3Array, a1: Vector3, clear: Vector3, z_duct: float,
	duct_y: float = NAN, vh: float = 0.0
) -> void:
	_elec_push_ortho(pts, a1, clear)
	var cur: Vector3 = pts[pts.size() - 1]
	var hy: float = cur.y if is_nan(duct_y) else duct_y
	var half: float = maxf(vh * 0.5, Parts.mm(12.0))
	var side_sign: float = 1.0 if cur.y >= hy else -1.0
	# Зазор за наружной гранью пальцев (+крышка чуть шире vh).
	var y_side: float = hy + side_sign * (half + Parts.mm(4.5))
	# Сначала всегда выйти за зубья по Y — иначе Z-ход режет крышку.
	if absf(cur.y - y_side) > 0.0008:
		_hose_ortho_push(pts, Vector3(cur.x, y_side, cur.z))
		cur = pts[pts.size() - 1]
	if absf(cur.z - z_duct) > 0.0012:
		_hose_ortho_push(pts, Vector3(cur.x, y_side, z_duct))


## Выход: lane → бок зубьев → Z наружу → clear (не сквозь крышку).
func _elec_leave_hduct(
	pts: PackedVector3Array, clear: Vector3, z_duct: float, y_lane: float,
	duct_y: float = NAN, vh: float = 0.0
) -> void:
	_hose_ortho_push(pts, Vector3(clear.x, y_lane, z_duct))
	var hy: float = y_lane if is_nan(duct_y) else duct_y
	var half: float = maxf(vh * 0.5, Parts.mm(12.0))
	var side_sign: float = 1.0 if clear.y >= hy else -1.0
	var y_side: float = hy + side_sign * (half + Parts.mm(4.5))
	# Сначала сквозь зубья (±Y), потом Z к клемме — не через крышку.
	if absf(y_lane - y_side) > 0.0008:
		_hose_ortho_push(pts, Vector3(clear.x, y_side, z_duct))
	var cur: Vector3 = pts[pts.size() - 1]
	if absf(cur.z - clear.z) > 0.0012:
		_hose_ortho_push(pts, Vector3(cur.x, cur.y, clear.z))
		cur = pts[pts.size() - 1]
	_hose_ortho_push(pts, clear)


## Совместимость: старые вызовы.
func _elec_push_into_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, y_duct: float = 0.0) -> void:
	var a1: Vector3 = pts[pts.size() - 1] if not pts.is_empty() else clear
	_elec_enter_hduct(pts, a1, clear, z_duct, y_duct, Parts.mm(40.0))


func _elec_push_out_of_hduct(pts: PackedVector3Array, clear: Vector3, z_duct: float, y_duct: float) -> void:
	_elec_leave_hduct(pts, clear, z_duct, y_duct, y_duct, Parts.mm(40.0))


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
## Для перемычек: Z у фронта корпуса — мостик идёт перед приборами, не сквозь ступени.
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
		# Чуть перед фронтом — вертикаль/U не режет колодку.
		q.z = maxf(q.z, face_z - 0.008)
	elif n.y > 0.30:
		q.y = maxf(q.y, box.position.y + box.size.y + pad)
		q.z = maxf(q.z, face_z - 0.008)
	else:
		# Торцевые порты — чуть вперёд от корпуса (к дверце).
		q.z = maxf(q.z, face_z + pad)
	return q


## Короткая перемычка: мостик ПЕРЕД фронтом приборов (front_z), не сквозь корпуса.
func _hose_ortho_elec_jumper(a: Vector3, a1: Vector3, b: Vector3, b1: Vector3, na: Vector3, nb: Vector3, ida: int = -1, idb: int = -1, lane: int = 0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	_hose_ortho_push(pts, a)
	_hose_ortho_push(pts, a1)
	var ca: Vector3 = _elec_clear_outside(a1, na, ida)
	var cb: Vector3 = _elec_clear_outside(b1, nb, idb)
	_hose_ortho_push(pts, ca)
	var pack: Vector2 = _elec_pack_lane(lane)
	var o_lat: float = pack.x
	var o_dep: float = pack.y
	var facing_vert: bool = (na.y > 0.30 and nb.y < -0.30) or (na.y < -0.30 and nb.y > 0.30)
	if facing_vert:
		# Рот-в-рот: вертикаль тоже перед фронтом, не world-ortho сквозь ряд.
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
	elif (na.y + nb.y) >= 0.0:
		bridge_y = maxf(ca.y, cb.y) + clear + o_lat
	else:
		bridge_y = minf(ca.y, cb.y) - clear + o_lat
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
		# Одна рейка, разные аппараты → всегда КК (не перемычка перед рядом: 4/5/7 и т.п.).
		return false
	if not same_side:
		return false
	if absf(a1.x - b1.x) > Parts.mm(38.0):
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
	var y0: float = minf(a1.y, b1.y)
	var y1: float = maxf(a1.y, b1.y)
	# Полоса проверки: отрезок клемм ± запас по высоте корпуса (не только 70 мм от центра).
	var y_pad: float = 0.055
	var y_lo: float = y0 - y_pad
	var y_hi: float = y1 + y_pad
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
			var my0: float = box.position.y
			var my1: float = box.position.y + box.size.y
			var y_overlap: float = minf(y_hi, my1) - maxf(y_lo, my0)
			if y_overlap <= 0.002:
				continue
			var mx0: float = box.position.x
			var mx1: float = box.position.x + box.size.x
			# Чужой корпус перекрывает интервал между клеммами → в КК, не по фронту.
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
	var pviz_on: bool = circuit != null and bool(circuit.pressure_viz)
	var pviz_max: float = _pressure_viz_max_cached() if pviz_on else -1.0
	for id in _records.keys():
		var rec = _records[id]
		if rec == null or not rec.has("root"):
			continue
		var root_x: Node3D = rec["root"] as Node3D
		if root_x == null:
			continue
		# Редуктор: рентген не делаем.
		if bool(root_x.get_meta("accessory_regulator", false)):
			continue
		# После CSG-bake и смены режима — переприменить с нуля.
		if root_x.has_meta("xray_ok"):
			root_x.remove_meta("xray_ok")
		if root_x.has_meta("pviz_last_on"):
			root_x.remove_meta("pviz_last_on")
		if root_x.has_meta("tviz_last_on"):
			root_x.remove_meta("tviz_last_on")
		if root_x.has_meta("tviz_cyl_sig"):
			root_x.remove_meta("tviz_cyl_sig")
		Iso.apply_xray(root_x, xray)
		# Всегда переложить «Давление» (вкл или выкл) — иначе после рентгена
		# часть корпусов остаётся в tint давления / ghost.
		# Датчики/электро — не пневмо: не красить (иначе корпус «белеет»).
		# on=false сбрасывает залипший tint с прошлых apply.
		var el_x = circuit.get_element(int(id)) if circuit != null else null
		if el_x != null:
			var kind_x: String = str(el_x.kind)
			if kind_x in [
				"source", "junction", "accessory", "cylinder", "rotary_cylinder", "air_motor", "valve"
			]:
				_apply_pressure_viz_root(root_x, el_x, pviz_on, pviz_max)
			elif kind_x in ["sensor", "opto_tip", "electro", "coil"]:
				_apply_pressure_viz_root(root_x, el_x, false, -1.0)
		# Распред: галереи/мостики только в рентгене.
		if circuit != null:
			var el_v = circuit.get_element(int(id))
			if el_v != null and str(el_v.kind) == "valve":
				IsoValve.update_spool(root_x, el_v, xray)
	# Щит: рентген только у модулей с внутренностями.
	if _machines != null:
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab != null:
			IsoCabinet.apply_xray(cab, xray)
	# Тепловизор после рентгена — иначе ghost без tint / залипший opaque.
	if circuit != null and bool(circuit.thermal_viz):
		_sync_thermal_viz_pass()


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
						sim_control_changed.emit()
						return
					if str(eel.electro_mount) == "door" or str(eel.electro_mount) == "din":
						# При пуске — только клик-действие, без переноса по DIN/дверце.
						_drag = "door_module" if str(eel.electro_mount) == "door" else "din_module"
						_actuate_el_id = eid
						_module_press = screen
						_module_hit_pt = hit_pt
						_module_hit_node = hit_node
						_module_moved = false
						_module_origin_slot = int(eel.din_slot)
						_module_origin_xy = eel.door_xy if eel.door_xy is Vector2 else Vector2(-1, -1)
						_module_ghost_slot = _module_origin_slot
						_module_ghost_xy = _module_origin_xy
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
	# Винт уставки датчика (I/C/O) / реле давления (set|hyst).
	var thr_sens: Dictionary = _pick_threshold_screw(ray["origin"], ray["dir"])
	if not thr_sens.is_empty():
		_drag = "threshold_screw"
		_actuate_el_id = int(thr_sens.get("id", -1))
		_module_hit_node = thr_sens.get("root") as Node3D
		_ps_screw_role = str(thr_sens.get("role", ""))
		circuit.select_only(_actuate_el_id, "workshop")
		return
	# Кнопки панели оптоусилителя / УЗ (+ / − удержание; SET / MODE — клик).
	var amp_btn: Dictionary = _pick_amp_panel_button(ray["origin"], ray["dir"])
	if not amp_btn.is_empty():
		var aid: int = int(amp_btn.get("id", -1))
		var ael = circuit.get_element(aid)
		var bname: String = str(amp_btn.get("btn", ""))
		var aroot: Node3D = amp_btn.get("root") as Node3D
		if ael != null:
			if bname == "BtnPlus" or bname == "BtnMinus":
				_begin_amp_btn_hold(aid, aroot, bname)
			else:
				match bname:
					"BtnSet":
						if str(ael.sensor_class) == "ultrasonic":
							# Teach: SET = текущая дистанция.
							IsoUltrasonic.teach_setpoint(ael, circuit)
						else:
							# Teach: SET = текущий PV.
							IsoOptical.set_display_set_value(
								ael, SensorDetect.optical_signal_level(circuit, ael)
							)
					"BtnMode":
						ael.optical_light_on = not bool(ael.optical_light_on)
				if aroot != null:
					if str(ael.sensor_class) == "ultrasonic":
						IsoUltrasonic.apply_display(aroot, ael, circuit)
					else:
						IsoOptical.apply_panel(aroot, ael, circuit)
				circuit.select_only(aid, "workshop")
				sim_control_changed.emit()
		return
	# Рукоятка отсечного крана — переключение открыт/закрыт.
	var shut_hit: Dictionary = _pick_shutoff_handle(ray["origin"], ray["dir"])
	if not shut_hit.is_empty():
		var sid: int = int(shut_hit.get("id", -1))
		var sel = circuit.get_element(sid)
		if sel != null:
			AccLib.toggle_shutoff(sel)
			var sroot: Node3D = shut_hit.get("root") as Node3D
			if sroot != null:
				IsoShutoff.apply_opening(sroot, sel)
			circuit.select_only(sid, "workshop")
			sim_control_changed.emit()
		return
	# Предохранительный: винт сверху (уставка) — раньше рычага, чтобы не перехватывать.
	var rel_s: Dictionary = _pick_relief_screw(ray["origin"], ray["dir"])
	if not rel_s.is_empty():
		_drag = "relief_screw"
		_actuate_el_id = int(rel_s.get("id", -1))
		_module_hit_node = rel_s.get("root") as Node3D
		circuit.select_only(_actuate_el_id, "workshop")
		return
	var rel_h: Dictionary = _pick_relief_handle(ray["origin"], ray["dir"])
	if not rel_h.is_empty():
		_drag = "relief_handle"
		_actuate_el_id = int(rel_h.get("id", -1))
		_module_hit_node = rel_h.get("root") as Node3D
		var rhel = circuit.get_element(_actuate_el_id)
		if rhel != null:
			rhel.pressed = true
			if _module_hit_node != null:
				IsoRelief.apply_state(_module_hit_node, rhel)
		circuit.select_only(_actuate_el_id, "workshop")
		sim_control_changed.emit()
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
		_gizmo_moved = false
		_hover = handle
		_axis = _vector_for(handle)
		_drag_pos = el.world_pos
		_drag_basis = el.world_basis
		# Один шаг Undo на весь жест (как перенос на схеме).
		if circuit != null and circuit.has_method("begin_history_group"):
			circuit.begin_history_group()
		# Кольцо = поворот, стрелка = перемещение (оба гизмо видны сразу).
		mode = "rotate" if handle.ends_with("R") else "move"
		if mode == "move":
			_drag_point = _axis_coord(ray["origin"], ray["dir"], el.world_pos, _axis)
		else:
			_drag_angle = _axis_angle(ray["origin"], ray["dir"], el.world_pos, _axis)
		return
	# Несколько машин под лучом (ПЦ + геркон…) — белый список, как на 2D.
	var mach_hits: Array = _collect_machine_hits(ray["origin"], ray["dir"])
	if mach_hits.size() >= 2:
		request_hit_picker.emit(mach_hits, screen)
		_drag = ""
		return
	var picked: int = -1
	if mach_hits.size() == 1:
		picked = int((mach_hits[0] as Dictionary).get("id", -1))
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
	# Середина 3D для авто-переходника при разном Ø.
	var pa_w = _port_world(ra_id, ra_port)
	var pb_w = _port_world(rb_id, rb_port)
	if pa_w != null and pb_w != null:
		circuit._pending_adapter_world = ((pa_w as Vector3) + (pb_w as Vector3)) * 0.5
	if circuit.connect_or_branch(ra_id, ra_port, rb_id, rb_port):
		circuit.notify("Соединение создано")
	circuit._pending_adapter_world = null


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
	sim_control_changed.emit()


func _clear_module_ghost() -> void:
	if _module_ghost != null and is_instance_valid(_module_ghost):
		_module_ghost.queue_free()
	_module_ghost = null
	_module_ghost_slot = -1
	_module_ghost_xy = Vector2(-1, -1)


func _ensure_module_ghost() -> void:
	if _module_ghost != null and is_instance_valid(_module_ghost):
		return
	var src: Node3D = _module_hit_node
	if src == null or not is_instance_valid(src):
		return
	_module_ghost = src.duplicate() as Node3D
	if _module_ghost == null:
		return
	_module_ghost.name = "ModuleDragGhost"
	_module_ghost.set_meta("el_id", -1)
	_module_ghost.set_meta("electro_act", false)
	_apply_module_ghost_look(_module_ghost)
	var host: Node = src.get_parent()
	if host != null:
		host.add_child(_module_ghost)
	else:
		add_child(_module_ghost)
	_module_ghost.global_transform = src.global_transform


func _apply_module_ghost_look(n: Node) -> void:
	if n is GeometryInstance3D:
		var gi: GeometryInstance3D = n as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var base: Material = gi.material_override
		if base == null and gi is MeshInstance3D:
			var mi: MeshInstance3D = gi as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				base = mi.mesh.surface_get_material(0)
		var ghost_m: StandardMaterial3D = null
		if base is StandardMaterial3D:
			ghost_m = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			ghost_m = StandardMaterial3D.new()
			ghost_m.albedo_color = Color(0.35, 0.65, 0.95, 0.42)
		ghost_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = ghost_m.albedo_color
		ghost_m.albedo_color = Color(c.r, c.g, c.b, 0.42)
		ghost_m.metallic = minf(float(ghost_m.metallic), 0.15)
		ghost_m.roughness = maxf(float(ghost_m.roughness), 0.55)
		ghost_m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		gi.material_override = ghost_m
	elif n is Label3D:
		(n as Label3D).modulate.a = 0.35
	for ch in n.get_children():
		_apply_module_ghost_look(ch)


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
		var thr_cls: String = str(thr.accessory_class) if thr != null else ""
		if thr == null or not (thr_cls == "throttle" or thr_cls == "throttle_check"):
			return
		# Вправо / вниз мыши = по часовой = винт глубже = меньше opening.
		var d_ang: float = float(event.relative.x) + float(event.relative.y) * 0.35
		thr.opening = clampf(float(thr.opening) - d_ang * 0.0045, 0.0, 1.0)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			if thr_cls == "throttle_check":
				IsoThrottleCheck.apply_opening(_module_hit_node, thr)
			else:
				IsoThrottle.apply_opening(_module_hit_node, thr)
		return
	if _drag == "threshold_screw":
		var sens = circuit.get_element(_actuate_el_id) if circuit != null else null
		if sens == null or str(sens.kind) != "sensor":
			return
		var d_thr: float = float(event.relative.x) + float(event.relative.y) * 0.35
		if str(sens.sensor_class) == "pressure_switch":
			var role: String = _ps_screw_role if _ps_screw_role != "" else "set"
			IsoPressureSwitch.nudge_from_drag(sens, role, d_thr)
			if _module_hit_node != null and is_instance_valid(_module_hit_node):
				IsoPressureSwitch.apply_adjustments(_module_hit_node, sens)
			sim_control_changed.emit()
			return
		sens.threshold_pct = clampf(float(sens.threshold_pct) + d_thr * 0.35, 0.0, 100.0)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			match str(sens.sensor_class):
				"optical":
					# Усилитель с индикаторами — только кнопки +/−; винт только у compact.
					if str(sens.optical_form) == "compact":
						IsoOpticalCompact.apply_threshold_screw(_module_hit_node, sens)
				"capacitive":
					IsoCapacitive.apply_threshold_screw(_module_hit_node, sens)
				_:
					IsoInductive.apply_threshold_screw(_module_hit_node, sens)
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
	if _drag == "relief_screw":
		var rsc = circuit.get_element(_actuate_el_id) if circuit != null else null
		if rsc == null or str(rsc.accessory_class) != "relief":
			return
		var d_rel: float = float(event.relative.x) + float(event.relative.y) * 0.35
		rsc.set_pressure_bar = clampf(
			float(rsc.set_pressure_bar) + d_rel * 0.018,
			IsoRelief.SET_MIN_BAR, IsoRelief.SET_MAX_BAR
		)
		if _module_hit_node != null and is_instance_valid(_module_hit_node):
			IsoRelief.apply_state(_module_hit_node, rsc)
		return
	if _drag == "door_module":
		# При пуске — только клик (перенос запрещён).
		if circuit != null and bool(circuit.running):
			return
		if event.position.distance_to(_module_press) > 4.0:
			_module_moved = true
			_ensure_module_ghost()
		var del = circuit.get_element(_actuate_el_id) if circuit != null else null
		if del == null or str(del.electro_mount) != "door":
			return
		var cab := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab == null or _module_ghost == null:
			return
		var ray_d := _ray(event.position)
		var xy: Vector2 = IsoCabinet.project_door_xy(cab, ray_d["origin"], ray_d["dir"])
		if xy.x >= 0.0 and IsoCabinet.door_cell_free(circuit, xy, int(del.id)):
			_module_ghost_xy = xy
			IsoCabinet.apply_door_pose(_module_ghost, cab, xy)
		return
	if _drag == "din_module":
		if circuit != null and bool(circuit.running):
			return
		if event.position.distance_to(_module_press) > 4.0:
			_module_moved = true
			_ensure_module_ghost()
		var din_el = circuit.get_element(_actuate_el_id) if circuit != null else null
		if din_el == null or str(din_el.electro_mount) != "din":
			return
		var cab_d := _machines.get_node_or_null(IsoCabinet.CABINET_NAME) as Node3D
		if cab_d == null or _module_ghost == null:
			return
		var ray_din := _ray(event.position)
		var width: int = IsoCabinet.din_width_slots(din_el)
		var slot: int = IsoCabinet.project_din_slot(cab_d, ray_din["origin"], ray_din["dir"], width, circuit, int(din_el.id))
		if slot >= 0:
			_module_ghost_slot = slot
			IsoCabinet.apply_din_pose(_module_ghost, cab_d, din_el, slot)
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
		var next_pos: Vector3 = _drag_pos + _axis * delta_m
		if next_pos.distance_squared_to(el.world_pos) > 1.0e-12:
			_gizmo_moved = true
		el.world_pos = next_pos
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
		var next_basis: Basis = Basis(_axis, delta) * _drag_basis
		if not next_basis.is_equal_approx(el.world_basis):
			_gizmo_moved = true
		el.world_basis = next_basis
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
		if str(el.kind) != "accessory":
			continue
		var acls: String = str(el.accessory_class)
		if acls != "throttle" and acls != "throttle_check":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		var hit: bool = IsoThrottleCheck.pick_screw(root, origin, dir) if acls == "throttle_check" \
				else IsoThrottle.pick_screw(root, origin, dir)
		if root == null or not hit:
			continue
		var screw: Node3D = root.get_node_or_null("ThrottleScrew") as Node3D
		var center: Vector3 = screw.global_position if screw != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
	return best


func _pick_threshold_screw(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	var dir_n: Vector3 = dir.normalized()
	for el in circuit.elements:
		if str(el.kind) != "sensor":
			continue
		var cls: String = str(el.sensor_class)
		if cls not in ["inductive", "capacitive", "optical", "pressure_switch"]:
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null:
			continue
		var candidates: Array = []
		if cls == "pressure_switch":
			candidates = [
				{"node": root.get_node_or_null("SetScrew"), "role": "set"},
				{"node": root.get_node_or_null("HystScrew"), "role": "hyst"},
			]
		else:
			candidates = [{"node": root.get_node_or_null("ThresholdScrew"), "role": ""}]
		for cand in candidates:
			var screw: Node3D = cand.get("node") as Node3D
			if screw == null:
				continue
			var center: Vector3 = screw.global_position
			var to_c: Vector3 = center - origin
			var t: float = to_c.dot(dir_n)
			if t < 0.0:
				continue
			var closest: Vector3 = origin + dir_n * t
			var hit_r: float = Parts.mm(9.0) if cls == "pressure_switch" else Parts.mm(8.0)
			if closest.distance_to(center) > hit_r:
				continue
			if t < best_t:
				best_t = t
				best = {"id": int(el.id), "root": root, "role": str(cand.get("role", ""))}
	return best


func _pick_amp_panel_button(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	var dir_n: Vector3 = dir.normalized()
	for el in circuit.elements:
		if str(el.kind) != "sensor":
			continue
		var cls: String = str(el.sensor_class)
		if cls == "optical":
			if str(el.optical_form) == "compact":
				continue
		elif cls != "ultrasonic":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null:
			continue
		var btns: Array = ["BtnPlus", "BtnMinus", "BtnSet", "BtnMode"] if cls == "optical" \
				else ["BtnPlus", "BtnMinus", "BtnSet"]
		for bname in btns:
			var btn: Node3D = root.get_node_or_null(str(bname)) as Node3D
			if btn == null:
				continue
			var center: Vector3 = btn.global_position
			var to_c: Vector3 = center - origin
			var t: float = to_c.dot(dir_n)
			if t < 0.0:
				continue
			var closest: Vector3 = origin + dir_n * t
			if closest.distance_to(center) > Parts.mm(5.0):
				continue
			if t < best_t:
				best_t = t
				best = {"id": int(el.id), "root": root, "btn": str(bname)}
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


func _pick_shutoff_handle(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "accessory" or str(el.accessory_class) != "shutoff":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not IsoShutoff.pick_handle(root, origin, dir):
			continue
		var handle: Node3D = root.get_node_or_null("ShutoffRotor/Handle") as Node3D
		var center: Vector3 = handle.global_position if handle != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
	return best


func _pick_relief_screw(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "accessory" or str(el.accessory_class) != "relief":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not IsoRelief.pick_screw(root, origin, dir):
			continue
		var screw: Node3D = root.get_node_or_null("ReliefScrew") as Node3D
		var center: Vector3 = screw.global_position if screw != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
	return best


func _pick_relief_handle(origin: Vector3, dir: Vector3) -> Dictionary:
	if circuit == null:
		return {}
	var best_t: float = 1.0e9
	var best: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "accessory" or str(el.accessory_class) != "relief":
			continue
		var rec = _records.get(el.id, null)
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not IsoRelief.pick_handle(root, origin, dir):
			continue
		var handle: Node3D = root.get_node_or_null("ReliefHandle") as Node3D
		var center: Vector3 = handle.global_position if handle != null else root.global_position
		var t: float = origin.distance_to(center)
		if t < best_t:
			best_t = t
			best = {"id": int(el.id), "root": root}
	return best


func _pick_machine(origin: Vector3, dir: Vector3) -> int:
	var hits: Array = _collect_machine_hits(origin, dir)
	if hits.is_empty():
		return -1
	return int(hits[0].get("id", -1))


## Все машины, пересечённые лучом (ближайшие в окне глубины) — для ЛКМ-списка.
func _collect_machine_hits(origin: Vector3, dir: Vector3) -> Array:
	var raw: Array = []
	if circuit == null:
		return raw
	for id in _records.keys():
		var rec = _records[id]
		if rec == null or not rec.has("root"):
			continue
		var root: Node3D = rec["root"] as Node3D
		if root == null or not is_instance_valid(root):
			continue
		var local: AABB = _model_aabb(root)
		var world: AABB = _xform_aabb(local, root.global_transform)
		var t: float = _ray_aabb(origin, dir, world)
		if t < 0.0:
			continue
		var el = circuit.get_element(int(id))
		if el == null:
			continue
		var tag: String = str(el.tag)
		if tag == "":
			tag = str(el.kind)
		var title: String = tag
		var kind_s: String = str(el.kind)
		if kind_s == "sensor":
			title = "%s · датчик" % tag
		elif kind_s == "cylinder":
			title = "%s · ПЦ" % tag
		elif kind_s == "valve":
			title = "%s · ПР" % tag
		raw.append({"id": int(id), "t": t, "title": title})
	raw.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	if raw.is_empty():
		return raw
	# Только слой у ближайшего попадания — не тащить дальние объекты сцены.
	var t0: float = float(raw[0].get("t", 0.0))
	var depth_win: float = 0.14
	var out: Array = []
	for item_v in raw:
		var item: Dictionary = item_v as Dictionary
		if float(item.get("t", 0.0)) > t0 + depth_win:
			break
		out.append(item)
	return out


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
