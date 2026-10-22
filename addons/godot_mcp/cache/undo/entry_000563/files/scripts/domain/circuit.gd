class_name Circuit
extends RefCounted
## Изотермическая модель пневмопривода.
## Камеры и трубки — объёмы идеального газа: P = m R T / V.
## Расход между объёмами — сужающееся сопло (докритический и критический режим).
## Шток — второй закон Ньютона: давление, площадь, пружина, нагрузка, трение.
## Неподключённый канал по умолчанию открыт в атмосферу через присоединительное отверстие.

const ATM := 101325.0
const R_AIR := 287.05
const GAMMA := 1.4
const TUBE_CD := 0.2
const PORT_CD := 0.62

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
const Catalog = preload("res://scripts/domain/cylinder_catalog.gd")
const CylLib = preload("res://scripts/domain/cylinder_library.gd")
const RotaryCat = preload("res://scripts/domain/rotary_catalog.gd")
const RotaryLib = preload("res://scripts/domain/rotary_library.gd")
const MotorCat = preload("res://scripts/domain/motor_catalog.gd")
const MotorLib = preload("res://scripts/domain/motor_library.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const ElectroSymbols = preload("res://scripts/domain/electro_symbols.gd")
const ElecNet = preload("res://scripts/domain/electrical_network.gd")
const ValveCat = preload("res://scripts/domain/valve_catalog.gd")
const ValveLib = preload("res://scripts/domain/valve_library.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const SensorLib = preload("res://scripts/domain/sensor_library.gd")
const SensorCat = preload("res://scripts/domain/sensor_catalog.gd")
const SensorSig = preload("res://scripts/domain/sensor_signal.gd")
const SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const EditHistoryScript = preload("res://scripts/domain/edit_history.gd")

var elements: Array = []
var wires: Array = []
## Viz сброса редуктора: id → секунды хвоста анимации (сброс на малом объёме — доли кадра).
var relief_trail_s: Dictionary = {}
## id с сбросом в текущем step() — хвост зажигаем после субшагов.
var _relief_latch: Dictionary = {}
var selected_ids: Array = []
var selected_wire_id := -1
## Мультивыбор жил (Shift+ЛКМ) для групповой линии; selected_wire_id — последняя.
var selected_wire_ids: Array = []
var selection_space := "" # "" | schematic | workshop — откуда выбран элемент
## Перед connect из 3D: мировая точка для переходника (середина шланга).
var _pending_adapter_world = null

## Наведение 2D↔3D: клемма / элемент / линия.
var hover_el_id := -1
var hover_port := ""
var hover_wire_id := -1
var hover_space := "" # "" | schematic | workshop
var running := false
## Режим «ДАВЛЕНИЕ»: подсветка линий/элементов по давлению (2D и 3D).
var pressure_viz := false
## Режим зон датчиков: полупрозрачные коллайдеры Sn / полей (вместе с pressure_viz).
var sensor_field_viz := false
var speed := 1.0
var sim_time := 0.0
var gas_t := 293.15
var hint := ""
var hint_until := 0
var clipboard: Array = []
var clipboard_wires: Array = []
## Сглаженная шкала избытка для 2D/3D подкраски — без «дыхания» от численных пиков.
var _viz_max_over_smooth := 0.0
## Индекс порт→провод (rebuild в step / при изменении wires).
var _port_wire_index: Dictionary = {} # "elId|port" -> Wire (последний)
var _port_wires_index: Dictionary = {} # "elId|port" -> Array[Wire]
var _port_wire_index_dirty: bool = true
## Индекс id→элемент (rebuild в step / при изменении elements).
var _element_index: Dictionary = {} # id -> Element
var _element_index_dirty: bool = true
## Элементы с пневмопроводом — остальные (галерея без связей) не симулируем.
var _sim_active_els: Dictionary = {} # el_id -> true
## Кэш гидравлики провода на кадр (vol / effective area).
var _wire_vol_frame: Dictionary = {} # wire_id -> float
var _wire_area_frame: Dictionary = {} # wire_id -> float
var _has_electro_cached: bool = false
var _has_electro_dirty: bool = true
var _perf_ms_step: float = 0.0
## Следующий step пропустить (кадр тяжёлой 2D-перерисовки) — без рывка FPS.
var _skip_step_once: bool = false

var _next_id := 1
var _cyl_n := 0
var _rotary_n := 0
var _motor_n := 0
var _sensor_n := 0
var _src_n := 0
var _valve_n := 0
var _junc_n := 0
var _acc_n := 0
var _rail_n := 0
var _electro_n := {} # prefix -> count
var cabinet_door_open := true
var _history = EditHistoryScript.new()
var _last_snapshot: Dictionary = {}
var _history_restoring := false
var _history_group_depth := 0
var _history_group_pending := false
## Снимок undo: не паковать всю сцену синхронно в клик (фриз на 60+ УГО).
var _history_snapshot_dirty: bool = false

signal scene_changed
signal hover_port_changed


func _init() -> void:
	_last_snapshot = to_scene_dict()


## space + (port | element | wire). Пустые id сбрасывают наведение.
func set_hover(space: String, el_id: int = -1, port: String = "", wire_id: int = -1) -> void:
	var wid: int = wire_id
	var eid: int = -1 if wid >= 0 else el_id
	var p: String = "" if wid >= 0 or eid < 0 else port
	if wid < 0 and eid < 0:
		p = ""
	var sp: String = space if (eid >= 0 or wid >= 0) else ""
	if hover_el_id == eid and hover_port == p and hover_wire_id == wid and hover_space == sp:
		return
	hover_el_id = eid
	hover_port = p
	hover_wire_id = wid
	hover_space = sp
	hover_port_changed.emit()


func set_hover_port(space: String, el_id: int, port: String) -> void:
	set_hover(space, el_id, port, -1)


func clear_hover(space: String = "") -> void:
	if space != "" and hover_space != "" and hover_space != space:
		return
	set_hover("", -1, "", -1)


func touch_scene() -> void:
	if not _history_restoring:
		# До push — добить отложенный снимок прошлого жеста (уже post-state).
		if _history_snapshot_dirty:
			_flush_history_snapshot()
		if _history_group_depth > 0:
			if _history_group_pending:
				_history.push(_last_snapshot)
				_history_group_pending = false
			_schedule_history_snapshot()
		else:
			_history.push(_last_snapshot)
			_schedule_history_snapshot()
	scene_changed.emit()


func _touch_scene() -> void:
	touch_scene()


func _schedule_history_snapshot() -> void:
	if _history_snapshot_dirty:
		return
	_history_snapshot_dirty = true
	call_deferred("_flush_history_snapshot")


func _flush_history_snapshot() -> void:
	if not _history_snapshot_dirty:
		return
	_history_snapshot_dirty = false
	if _history_restoring:
		return
	_last_snapshot = to_scene_dict()


## Перед save / undo / закрытием — снимок обязан быть актуальным.
func ensure_history_snapshot() -> void:
	if _history_snapshot_dirty:
		_flush_history_snapshot()


func begin_history_group() -> void:
	## Один шаг undo на весь жест (перенос / изгиб).
	_history_group_depth += 1
	if _history_group_depth == 1:
		_history_group_pending = true


func end_history_group() -> void:
	if _history_group_depth > 0:
		_history_group_depth -= 1
	if _history_group_depth == 0:
		_history_group_pending = false
		if not _history_restoring:
			_flush_history_snapshot()


func can_undo() -> bool:
	return _history.can_undo()


func can_redo() -> bool:
	return _history.can_redo()


func undo_edit() -> bool:
	if not can_undo():
		return false
	ensure_history_snapshot()
	var prev: Dictionary = _history.undo(to_scene_dict())
	if prev.is_empty():
		return false
	_history_restoring = true
	var err := from_scene_dict(prev)
	_history_restoring = false
	if err != "":
		notify(err)
		return false
	_history_snapshot_dirty = false
	_last_snapshot = to_scene_dict()
	scene_changed.emit()
	return true


func redo_edit() -> bool:
	if not can_redo():
		return false
	ensure_history_snapshot()
	var nxt: Dictionary = _history.redo(to_scene_dict())
	if nxt.is_empty():
		return false
	_history_restoring = true
	var err := from_scene_dict(nxt)
	_history_restoring = false
	if err != "":
		notify(err)
		return false
	_history_snapshot_dirty = false
	_last_snapshot = to_scene_dict()
	scene_changed.emit()
	return true


func reset_history() -> void:
	_history.clear()
	_history_group_depth = 0
	_history_group_pending = false
	_history_snapshot_dirty = false
	_last_snapshot = to_scene_dict()


class Element extends RefCounted:
	var id := 0
	var kind := "cylinder"
	var tag := ""
	var tag_offset := Vector2.ZERO # сдвиг обозначения от позиции по умолчанию (верх-право)
	var position := Vector2.ZERO
	var rotation_quad := 0
	var action := "double" # double | spring_return | spring_extend
	var bore_mm := 32.0
	var rod_mm := 12.0
	var stroke_mm := 100.0
	var spring_rate := 0.45 # Н/мм
	var spring_preload := 18.0
	var mass_kg := 0.22
	var friction_n := 10.0
	var load_n := 0.0 # положительная сопротивляется выдвижению
	var open_ports := true
	var cushion := true
	var piston_kind := "simple"
	var cush_cap := "none"
	var cush_rod := "none"
	var cush_open_cap := 0.35 # 0=закрыто (сильно), 1=открыто (слабо) — игла PPV
	var cush_open_rod := 0.35
	var spring_side := "none"
	var rod_mode := "single"
	var rod_end := "plain"
	var brake := "none" # none | nc | end_lock
	var port_cap := "connect"
	var port_rod := "connect"
	var carriage := "none"
	var bump_end := "none" # none | elastic | ysr — упоры бесштоковой каретки
	var mount := "clevis" # none | foot | flange_front | flange_rear | clevis | trunnion
	var guide := "none" # none | bushing | non_rot
	var seal_leak := 0.0 # 0…1 учебная утечка
	var catalog_id := "generic"
	var variant_id := "ppv"
	var cushion_mm := 17.0
	var through_rod := false
	var body_style := "profile"
	var body_style_user := false # true = юзер зафиксировал стиль корпуса
	var order_code := ""
	var port_name := "G1/8"
	## Каталожный фитинг ПЦ: id из TubeFittingCatalog (thread + OD трубки).
	var fitting_id := "G1/8_6"
	## Наружный Ø трубки, мм, задаваемый фитингом ПЦ (и позже арматурой).
	var tube_od_mm := 6.0
	var rod_thread := "M10×1.25"
	var pressure_bar := 6.0
	var temperature_c := 20.0
	var x := 0.0
	var v := 0.0
	var m_cap := 0.0
	var m_rod := 0.0
	var p_cap := 101325.0
	var p_rod := 101325.0
	var q_cap := 0.0
	var q_rod := 0.0
	var world_pos := Vector3.ZERO
	var world_basis := Basis.IDENTITY
	var auto_ground := true
	var end_locked := false # стопор end_lock активен
	# --- Распределитель (ISO 1219) ---
	var valve_ways := 5
	var valve_positions := 2
	var valve_center := "none" # none | closed | exhausted | pressurized | floating
	var valve_nc_no := "nc" # nc | no — для 2/2 и 3/2
	var rest_pos := 0
	var valve_pos := 0
	var op_left := "solenoid_pilot"
	var op_right := "spring"
	var pilot_supply := "internal"
	var valve_cv := 1.0
	var command_left := false
	var command_right := false
	var port_3 := "muffler" # muffler | fitting — выхлоп 3(R1)
	var port_5 := "muffler" # muffler | fitting — выхлоп 5(R2)
	var override_left := true # ручной дублёр ЭМ слева
	var override_right := true
	var recipe_id := ""
	var spool_envelopes: PackedStringArray = PackedStringArray()
	var port_mass := {} # port name -> kg
	var port_press := {} # port name -> Pa
	var port_q := {} # port name -> м³/с (+ в порт, − из порта / выхлоп)
	var junction_style := "tee" # tee | wye | manifold | adapter
	var junction_ports := 3
	## Переходник: OD трубки на порту 2 (порт 1 = tube_od_mm).
	var tube_od_b_mm := 0.0
	# --- Пневмоаксессуары (дроссель / ОК / ресивер / редуктор / FRL) ---
	var accessory_class := "" # throttle | … | shuttle | and_valve | quick_exhaust | shutoff | relief
	var opening := 1.0 # 0…1 уровень открытия дросселя / отсечного (0=закрыт)
	var volume_l := 1.0 # литры — ресивер
	var reservoir_ports := 1 # 1…5 бобышек сверху на ресивере
	var set_pressure_bar := 6.0 # уставка редуктора / FRL
	## Редуктор: колпачок поднят (разблокирован) — можно крутить уставку в 3D.
	var regulator_unlocked := false
	## Обратный клапан: давление открытия (crack), бар изб. (каталог ISO/производитель).
	var crack_pressure_bar := 0.2
	## Номинальный расход Nl/мин при 6 бар, ΔP=1 бар (каталог).
	var flow_nl_min := 600.0
	# --- Поворотный ПЦ / пневмомотор ---
	var rotary_class := "" # rack_pinion | vane | gear | vane_motor | turbine
	var angle_max_deg := 180.0
	var torque_nm_at_6bar := 9.0 # ППЦ: момент; ПМ: stall @6 бар
	var free_rpm := 0.0 # пневмомотор: холостые об/мин @6 бар
	var angle := 0.0 # рад (ППЦ / анимация вала ПМ)
	var omega := 0.0 # рад/с
	# --- Шина УГО (ортогональная полилиния) ---
	var rail_domain := "electric" # electric | pneumatic
	var rail_points: PackedVector2Array = PackedVector2Array()
	var rail_taps: Array = [] # [{name, seg, u}]
	var rail_tap_seq := 0
	# --- Электроавтоматика ---
	var electro_class := ""
	var electro_mount := "din" # din | door | none
	var tag_prefix := "E"
	var lamp_color := "white"
	var btn_color := "white" # цвет клавиши кнопки (гриб всегда red)
	var caption := "" # название на наклейке щита
	var delay_on := 0.0
	var delay_off := 0.0
	var timer_mode := "on" # on | off | both
	var timer_unit := 1 # 0=мс, 1=с, 2=мин
	var timer_value := 1.0 # уставка: мс 1…999, с/мин 1…59
	var poles := 1
	var curve := "C"
	var rating_a := 16.0
	var i_delta_ma := 30.0
	var u_min := 180.0
	var u_max := 260.0
	var phase := ""
	var voltage := 220.0
	var link_valve := false
	var group_template := ""
	## DIN-клеммник: общая шина-перемычка; color_id — цвет корпуса (как у провода).
	var terminal_bus := false
	var color_id := ""
	## БП/прибор: сдвиг таблиц Конт./Цепь по Y (клетки); прижаты к L/R краю.
	var device_table_dy_left := 0.0
	var device_table_dy_right := 0.0
	## 1 = старые порты 1/1b; 2 = слева нечёт / справа чёт (1/2, 3/4…).
	var terminal_port_scheme := 2
	var electro_ports: Array = []
	var coil_ports: PackedStringArray = PackedStringArray()
	var contact_defs: Array = []
	var switch_positions := 2 # число положений SA
	var switch_pos := 0 # текущее положение 0..n-1
	var switch_map: Array = [] # [ряд][положение] = bool (замкнут)
	var switch_labels: PackedStringArray = PackedStringArray() # названия положений
	var energized := false
	var pressed := false
	var latching := false # кнопка с фиксацией (иначе моментальная)
	var closed := true
	var lit := false
	var timer_armed := false
	var timer_elapsed := 0.0
	var detached := false
	var hide_unused_contacts := false # 2D: прятать контакты без проводов (кроме первого)
	var member_role := "device"
	var member_index := 0
	var group_id := -1
	var group_tag := ""
	var linked_valve_side := "" # "" | L | R
	var din_slot := -1
	var door_slot := -1
	var door_xy := Vector2(-1, -1) # локаль DoorGrid; (-1,-1) = из door_slot
	# --- Датчики / СИ ---
	var sensor_class := "" # inductive | reed | capacitive | optical | …
	var sensor_active := true # false = пассивный (геркон / сухой контакт)
	var sense_range_mm := 4.0
	var hysteresis_mm := 0.4
	var body_od_mm := 12.0
	var supply_mode := "24dc" # 24dc | 220ac
	var output_type := "npn" # npn | pnp | contact
	var contact_form := "no" # no | nc
	var detect_material := "" # override материала корпуса; "" = default по kind
	var sensor_powered := false # runtime: питание головки
	var sensor_target := false # runtime: цель в зоне (без учёта питания)
	var analog_kind := "" # "" | 4_20ma | 0_10v | 0_1v | rtd
	var wire_scheme := 3 # 2/3/4 для ТС
	var analog_value := 0.0
	var input_expect := "any" # согласование NPN/PNP/contact на стороне прибора

	func pack() -> Dictionary:
		return {
			"id": id, "kind": kind, "tag": tag, "tag_offset": tag_offset, "position": position,
			"rotation_quad": rotation_quad, "action": action,
			"bore_mm": bore_mm, "rod_mm": rod_mm, "stroke_mm": stroke_mm,
			"spring_rate": spring_rate, "spring_preload": spring_preload,
			"mass_kg": mass_kg, "friction_n": friction_n, "load_n": load_n,
			"open_ports": open_ports, "cushion": cushion,
			"piston_kind": piston_kind, "cush_cap": cush_cap, "cush_rod": cush_rod,
			"cush_open_cap": cush_open_cap, "cush_open_rod": cush_open_rod,
			"spring_side": spring_side, "rod_mode": rod_mode, "rod_end": rod_end, "brake": brake,
			"port_cap": port_cap, "port_rod": port_rod, "carriage": carriage,
			"bump_end": bump_end, "mount": mount, "guide": guide, "seal_leak": seal_leak,
			"catalog_id": catalog_id, "variant_id": variant_id,
			"cushion_mm": cushion_mm, "through_rod": through_rod,
			"body_style": body_style, "body_style_user": body_style_user, "order_code": order_code,
			"port_name": port_name, "fitting_id": fitting_id, "tube_od_mm": tube_od_mm,
			"tube_od_b_mm": tube_od_b_mm,
			"rod_thread": rod_thread,
			"pressure_bar": pressure_bar, "temperature_c": temperature_c,
			"world_pos": world_pos, "world_basis": world_basis,
			"auto_ground": auto_ground,
			"valve_ways": valve_ways, "valve_positions": valve_positions,
			"valve_center": valve_center, "valve_nc_no": valve_nc_no,
			"rest_pos": rest_pos, "valve_pos": valve_pos,
			"op_left": op_left, "op_right": op_right, "pilot_supply": pilot_supply,
			"valve_cv": valve_cv, "command_left": command_left, "command_right": command_right,
			"port_3": port_3, "port_5": port_5,
			"override_left": override_left, "override_right": override_right,
			"recipe_id": recipe_id, "spool_envelopes": Array(spool_envelopes),
			"port_mass": port_mass.duplicate(), "port_press": port_press.duplicate(),
			"port_q": port_q.duplicate(),
			"junction_style": junction_style, "junction_ports": junction_ports,
			"accessory_class": accessory_class, "opening": opening,
			"volume_l": volume_l, "reservoir_ports": reservoir_ports,
			"set_pressure_bar": set_pressure_bar,
			"regulator_unlocked": regulator_unlocked,
			"crack_pressure_bar": crack_pressure_bar, "flow_nl_min": flow_nl_min,
			"rotary_class": rotary_class, "angle_max_deg": angle_max_deg,
			"torque_nm_at_6bar": torque_nm_at_6bar, "free_rpm": free_rpm,
			"angle": angle, "omega": omega,
			"rail_domain": rail_domain,
			"rail_points": Array(rail_points),
			"rail_taps": rail_taps.duplicate(true),
			"rail_tap_seq": rail_tap_seq,
			"electro_class": electro_class, "electro_mount": electro_mount, "tag_prefix": tag_prefix,
			"lamp_color": lamp_color, "btn_color": btn_color, "caption": caption,
			"delay_on": delay_on, "delay_off": delay_off,
			"timer_mode": timer_mode, "timer_unit": timer_unit, "timer_value": timer_value,
			"poles": poles, "curve": curve, "rating_a": rating_a, "i_delta_ma": i_delta_ma,
			"u_min": u_min, "u_max": u_max, "phase": phase, "voltage": voltage,
			"link_valve": link_valve, "group_template": group_template,
			"terminal_bus": terminal_bus, "color_id": color_id,
			"terminal_port_scheme": terminal_port_scheme,
			"electro_ports": electro_ports.duplicate(true),
			"coil_ports": Array(coil_ports),
			"contact_defs": contact_defs.duplicate(true),
			"switch_positions": switch_positions, "switch_pos": switch_pos,
			"switch_map": switch_map.duplicate(true),
			"switch_labels": Array(switch_labels),
			"energized": energized, "pressed": pressed, "latching": latching, "closed": closed, "lit": lit,
			"timer_armed": timer_armed, "timer_elapsed": timer_elapsed,
			"detached": detached, "hide_unused_contacts": hide_unused_contacts,
			"member_role": member_role, "member_index": member_index,
			"group_id": group_id, "group_tag": group_tag, "linked_valve_side": linked_valve_side,
			"din_slot": din_slot, "door_slot": door_slot, "door_xy": door_xy,
			"sensor_class": sensor_class, "sensor_active": sensor_active,
			"sense_range_mm": sense_range_mm, "hysteresis_mm": hysteresis_mm,
			"body_od_mm": body_od_mm, "supply_mode": supply_mode,
			"output_type": output_type, "contact_form": contact_form,
			"detect_material": detect_material,
			"sensor_powered": sensor_powered, "sensor_target": sensor_target,
			"analog_kind": analog_kind, "wire_scheme": wire_scheme,
			"analog_value": analog_value, "input_expect": input_expect,
		}


class Wire extends RefCounted:
	var id := 0
	var a_id := 0
	var a_port := ""
	var b_id := 0
	var b_port := ""
	## Пневмо: внутр. ⌀ мм (физика). Электро: сечение мм² (см. каталог в UI).
	var id_mm := 4.0
	## Пневмо: наружный ⌀ трубки, мм (каталог QS); 0 = ещё не задан.
	var od_mm := 6.0
	## Длина центральной линии 3D-трубки, м (0 = ещё нет 3D → fallback схема).
	var length_m := 0.0
	## Цвет линии: "" = авто; иначе id из каталога (brown/black/… или tube_blue).
	var color_id := ""
	## Порядковый номер в домене (электро / пневмо), 1…N; перенумеруется при удалении.
	var num := 0
	## Сдвиг номера на схеме (как tag_offset у элементов): mid / вход шины.
	var num_offset := Vector2.ZERO
	## Сдвиг второй метки у шины (выход).
	var num_offset_b := Vector2.ZERO
	## Только 2D: обрыв линии электрической связи (ГОСТ 2.721 п.8) — середина не рисуется.
	var broken := false
	## Только 2D: id группы взаимосвязи (>0); 0 = нет (ГОСТ 2.702 §5.2.13 / 2.721 п.7).
	var group_id := 0
	## Поворот кембрика вокруг оси провода (рад), концы A/B.
	var sleeve_yaw_a := 0.0
	var sleeve_yaw_b := 0.0
	var mass := 0.0
	var vol := 0.0
	var pressure := 101325.0
	## Сглаженное P для tip/цвета — без пилы от численного ring.
	var pressure_vis := 101325.0
	var flow_m3s := 0.0
	## Сглаженный расход для анимации (антидребезг направления).
	var flow_vis := 0.0
	## Защёлкнутый знак для визуализации (−1 / 0 / +1).
	var flow_sign := 0.0
	## Сколько секунд держится запрос на разворот знака.
	var flow_flip_t := 0.0
	## Фаза анимации конусов 0…1 (интеграл скорости — без телепорта при скачке Q).
	var flow_phase := 0.0
	## Сглаженная скорость анимации конусов (1/с вдоль трубки).
	var flow_anim_speed := 0.0
	## Липкое число конусов (антимерцание при колебании |Q| у порогов).
	var flow_puff_n := 0
	var joints: Array = []


## Каталог внутр. ⌀ пневмотрубок, мм.
static func tube_diameter_catalog() -> Array:
	return [4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]


## Каталог сечений медного провода, мм².
static func wire_section_catalog() -> Array:
	return [0.5, 0.75, 1.0, 1.5, 2.5, 4.0, 6.0]


## Наружный Ø ПВХ-изоляции (ПВ-3 / установочный), мм — по сечению жилы.
static func wire_od_mm(section_mm2: float) -> float:
	var s: float = snap_wire_section(section_mm2)
	if is_equal_approx(s, 0.5):
		return 2.2
	if is_equal_approx(s, 0.75):
		return 2.45
	if is_equal_approx(s, 1.0):
		return 2.7
	if is_equal_approx(s, 1.5):
		return 3.05
	if is_equal_approx(s, 2.5):
		return 3.7
	if is_equal_approx(s, 4.0):
		return 4.45
	if is_equal_approx(s, 6.0):
		return 5.2
	return 1.55 * sqrt(maxf(s, 0.25)) + 1.2


## Ближайшее сечение из каталога.
static func snap_wire_section(section_mm2: float) -> float:
	var best: float = 1.5
	var best_d: float = 1.0e9
	for v in wire_section_catalog():
		var s: float = float(v)
		var d: float = absf(float(section_mm2) - s)
		if d < best_d:
			best_d = d
			best = s
	return best


## Каталог цветов: [{id, title}, …] для пневмо / электро.
static func line_color_catalog(electric: bool) -> Array:
	if electric:
		return [
			{"id": "", "title": "Авто (по шине/порту)"},
			{"id": "brown", "title": "Коричневый"},
			{"id": "black", "title": "Чёрный"},
			{"id": "grey", "title": "Серый"},
			{"id": "white", "title": "Белый"},
			{"id": "lightblue", "title": "Голубой"},
			{"id": "red", "title": "Красный"},
			{"id": "pe", "title": "Жёлто-зелёный полосатый"},
		]
	return [
		{"id": "", "title": "Авто (синий)"},
		{"id": "tube_blue", "title": "Синий"},
		{"id": "tube_black", "title": "Чёрный"},
	]


static func line_color_from_id(color_id: String) -> Color:
	# Алиасы: demo/gen часто пишет blue/green (= N / PE), не lightblue/pe.
	match str(color_id):
		"brown":
			return Color(0.45, 0.28, 0.12)
		"black", "tube_black":
			return Color(0.08, 0.08, 0.1)
		"grey":
			# Темнее прежнего — чтобы отличался от «белого» на бумаге схемы.
			return Color(0.32, 0.33, 0.36)
		"white":
			# Не чистый белый: на светлой схеме иначе теряется (как бывший серый).
			return Color(0.58, 0.59, 0.62)
		"blue", "lightblue":
			# Как жила N у вводного кабеля (_wire_gost_color).
			return Color(0.15, 0.35, 0.85)
		"red":
			return Color(0.82, 0.12, 0.12)
		"green", "pe":
			return Color(0.55, 0.75, 0.15) # PE (solid; полоса — отдельно на Tube)
		"tube_blue":
			return Color(0.12, 0.42, 0.78)
		_:
			return Color(0.12, 0.12, 0.14)


func add_element(kind: String, at: Vector2) -> Element:
	var recipe_id := ""
	var cyl_recipe_id := ""
	var rotary_recipe_id := ""
	var motor_recipe_id := ""
	var sensor_recipe_id := ""
	var electro_recipe_id := ""
	var acc_recipe_id := ""
	var jstyle := "tee"
	if kind.begins_with("valve@"):
		recipe_id = kind.substr(6)
		kind = "valve"
	elif kind.begins_with("cylinder@"):
		cyl_recipe_id = kind.substr(9)
		kind = "cylinder"
	elif kind.begins_with("rotary_cylinder@"):
		rotary_recipe_id = kind.substr(16)
		kind = "rotary_cylinder"
	elif kind.begins_with("air_motor@"):
		motor_recipe_id = kind.substr(10)
		kind = "air_motor"
	elif kind.begins_with("sensor@"):
		sensor_recipe_id = kind.substr(7)
		kind = "sensor"
	elif kind.begins_with("electro@"):
		electro_recipe_id = kind.substr(8)
		kind = "electro"
	elif kind.begins_with("accessory@"):
		acc_recipe_id = kind.substr(10)
		kind = "accessory"
	elif kind == "coil":
		# Совместимость: старый kind → катушка ЭМ в электробиблиотеке.
		electro_recipe_id = "solenoid_coil"
		kind = "electro"
	elif kind.begins_with("junction@"):
		jstyle = kind.substr(9)
		kind = "junction"
	var rail_dom := ""
	if kind.begins_with("rail@"):
		rail_dom = kind.substr(5)
		kind = "rail"
	elif kind == "rail":
		rail_dom = "electric"
	var el := Element.new()
	el.id = _next_id
	_next_id += 1
	el.kind = kind
	el.position = at.snapped(Vector2(10, 10)) # = SymbolGeom.SCH_GRID
	var slot := _count_kind(kind)
	if kind == "source":
		_src_n += 1
		el.tag_prefix = AccLib.gost_tag_prefix(el)
		el.tag = "%s%d" % [el.tag_prefix, _src_n]
		el.world_pos = Vector3(slot * 0.46, 0.0, 0.42)
	elif kind == "valve":
		_valve_n += 1
		el.tag_prefix = "Р"
		el.tag = "Р%d" % _valve_n
		el.world_pos = Vector3(slot * 0.40, 0.0, -0.36)
		if recipe_id == "":
			recipe_id = "5_2_sol_spring"
		if not ValveLib.apply_recipe(el, recipe_id):
			el.valve_ways = 5
			el.valve_positions = 2
			el.op_left = "solenoid_pilot"
			el.op_right = "spring"
		ValveCat.conform(el)
		el.valve_pos = int(el.rest_pos)
	elif kind == "accessory":
		_acc_n += 1
		el.world_pos = Vector3(slot * 0.32, 0.02, 0.22)
		if acc_recipe_id == "":
			acc_recipe_id = "throttle"
		if not AccLib.apply_recipe(el, acc_recipe_id):
			el.accessory_class = "throttle"
			el.opening = 0.5
			el.valve_cv = 1.0
			el.tag_prefix = AccLib.gost_accessory_prefix("throttle")
		# По умолчанию Ø6; ОК — средний ряд каталога.
		if str(el.accessory_class) == "check":
			AccLib.apply_check_catalog(el, 1)
		elif str(el.accessory_class) == "shutoff":
			AccLib.configure_shutoff_valve_ugo(el)
			el.valve_pos = 0
			el.opening = 0.0
		elif float(el.tube_od_mm) < 1.0:
			TubeFit.apply_armature_od(el, 6.0)
		el.tag_prefix = AccLib.gost_tag_prefix(el)
		el.tag = "%s%d" % [el.tag_prefix, _acc_n]
	elif kind == "junction":
		_junc_n += 1
		el.tag_prefix = "У"
		el.tag = "У%d" % _junc_n
		el.junction_style = jstyle if jstyle in ["tee", "wye", "manifold", "adapter"] else "tee"
		if el.junction_style == "adapter":
			el.junction_ports = 2
			# По умолчанию Ø6→Ø8; в параметрах меняется вручную.
			el.tube_od_mm = 6.0
			el.tube_od_b_mm = 8.0
			el.port_name = TubeFit.thread_for_tube_od(6.0)
		elif el.junction_style == "manifold":
			el.junction_ports = 5
			el.tube_od_mm = 0.0
			el.tube_od_b_mm = 0.0
			el.port_name = ""
		else:
			el.junction_ports = 3
			# 0 = авто по трубке при соединении; иначе конфликт Ø6 с крупной линией.
			el.tube_od_mm = 0.0
			el.tube_od_b_mm = 0.0
			el.port_name = ""
		el.world_pos = Vector3(slot * 0.28, 0.02, 0.18)
		el.fitting_id = ""
	elif kind == "rail":
		_rail_n += 1
		el.tag = ""
		el.rail_domain = "pneumatic" if rail_dom == "pneumatic" else "electric"
		el.rail_points = Rail2D.default_points()
		el.rail_taps = []
		el.rail_tap_seq = 0
		el.world_pos = Vector3(slot * 0.30, 0.02, 0.10)
		el.auto_ground = false
	elif kind == "electro":
		if electro_recipe_id == "":
			electro_recipe_id = "lamp"
		ElectroLib.apply_recipe(el, electro_recipe_id)
		var pref := str(el.tag_prefix)
		var n: int = int(_electro_n.get(pref, 0)) + 1
		_electro_n[pref] = n
		el.tag = "%s%d" % [pref, n]
		el.group_tag = el.tag
		el.world_pos = Vector3(0.15 + float(slot % 8) * 0.045, 0.12, -0.85)
		el.auto_ground = false
	elif kind == "rotary_cylinder":
		_rotary_n += 1
		el.tag_prefix = "ППЦ"
		el.tag = "ППЦ%d" % _rotary_n
		el.world_pos = Vector3(slot * 0.48, 0.0, 0.12)
		if rotary_recipe_id == "":
			rotary_recipe_id = "rack_pinion_180"
		if not RotaryLib.apply_recipe(el, rotary_recipe_id):
			el.rotary_class = "rack_pinion"
			el.bore_mm = 40.0
			el.angle_max_deg = 180.0
			RotaryCat.conform(el)
	elif kind == "air_motor":
		_motor_n += 1
		el.tag_prefix = "ПМ"
		el.tag = "ПМ%d" % _motor_n
		el.world_pos = Vector3(slot * 0.42, 0.0, 0.08)
		if motor_recipe_id == "":
			motor_recipe_id = "gear_2am"
		if not MotorLib.apply_recipe(el, motor_recipe_id):
			el.rotary_class = "gear"
			el.free_rpm = 3000.0
			el.torque_nm_at_6bar = 3.05
			el.port_3 = "muffler"
			el.port_5 = "fitting"
			MotorCat.conform(el)
	elif kind == "sensor":
		_sensor_n += 1
		el.world_pos = Vector3(slot * 0.36, 0.05, 0.28)
		el.auto_ground = true
		if sensor_recipe_id == "":
			sensor_recipe_id = "inductive_m12"
		if not SensorLib.apply_recipe(el, sensor_recipe_id):
			el.sensor_class = "inductive"
			el.sensor_active = true
			el.sense_range_mm = 4.0
			el.body_od_mm = 12.0
			el.stroke_mm = 50.0
			el.supply_mode = "24dc"
			el.output_type = "npn"
			el.contact_form = "no"
			el.tag_prefix = "SQ"
			SensorCat.conform_inductive(el)
		el.tag_prefix = SensorLib.gost_prefix(str(el.sensor_class))
		el.tag = "%s%d" % [el.tag_prefix, _sensor_n]
	else:
		_cyl_n += 1
		el.tag_prefix = "Ц"
		el.tag = "Ц%d" % _cyl_n
		el.world_pos = Vector3(slot * 0.46, 0.0, 0.0)
		if cyl_recipe_id == "":
			cyl_recipe_id = "da_basic"
		if not CylLib.apply_recipe(el, cyl_recipe_id):
			Catalog.conform(el)
		TubeFit.conform_cylinder_fitting(el)
	_init_state(el, true)
	elements.append(el)
	invalidate_element_index()
	if kind == "electro" and str(el.electro_class) == "supply":
		# База L на primary; N/PE — supply_leg (spawn выставляет ports).
		ElectroLib.spawn_supply_legs(self, el, el.position)
	elif kind == "electro" and str(el.group_template) != "" and str(el.electro_class) != "contact":
		ElectroLib.spawn_group_members(self, el, el.position)
	renumber_tags()
	select_only(el.id)
	_touch_scene()
	return el


## Добавить элемент без select/touch/renumber (для членов группы).
func add_element_raw(kind: String, at: Vector2) -> Element:
	var el := Element.new()
	el.id = _next_id
	_next_id += 1
	el.kind = kind
	el.position = at.snapped(Vector2(10, 10))
	elements.append(el)
	invalidate_element_index()
	_init_state(el, true)
	return el


func renumber_tags() -> void:
	# ГОСТ 2.704-2011: буква(ы) + порядковый номер в пределах одинакового буквенного обозначения.
	var ordered: Array = elements.duplicate()
	ordered.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var n_src := 0
	var n_valve := 0
	var n_cyl := 0
	var n_junc := 0
	var n_acc := 0
	var n_rail := 0
	var pneumo_counts := {} # префикс ГОСТ → счётчик
	var electro_counts := {}
	var valve_tags_by_id := {} # id клапана → "Р1" (для катушек ЭМ)
	# Сначала пневмо + главные электроэлементы (не detached-контакты).
	for el in ordered:
		match str(el.kind):
			"source", "valve", "accessory", "junction", "cylinder":
				var ppref: String = AccLib.gost_tag_prefix(el)
				el.tag_prefix = ppref
				var pn: int = int(pneumo_counts.get(ppref, 0)) + 1
				pneumo_counts[ppref] = pn
				el.tag = "%s%d" % [ppref, pn]
				match str(el.kind):
					"source":
						n_src += 1
					"valve":
						n_valve += 1
						valve_tags_by_id[int(el.id)] = el.tag
					"accessory":
						n_acc += 1
					"junction":
						n_junc += 1
					"cylinder":
						n_cyl += 1
			"rail":
				n_rail += 1
				el.tag = ""
			"electro":
				if str(el.member_role) == "contact":
					continue
				var pref := str(el.tag_prefix)
				if pref == "":
					pref = "E"
				var n: int = int(electro_counts.get(pref, 0)) + 1
				electro_counts[pref] = n
				var base := "%s%d" % [pref, n]
				el.tag = base
				el.group_tag = base
				# Катушка ЭМ на ПР: Р1L / Р1R (база = тег распределителя, см. electrical_network).
				if str(el.electro_class) == "solenoid_coil":
					var side := str(el.linked_valve_side)
					if side != "L" and side != "R":
						side = "L"
					var vtag: String = "Р%d" % maxi(n_valve, 1)
					var host_id: int = int(el.group_id)
					if host_id >= 0 and valve_tags_by_id.has(host_id):
						vtag = str(valve_tags_by_id[host_id])
					el.tag = "%s%s" % [vtag, side]
					el.group_tag = el.tag
			_:
				pass
	for el in ordered:
		if str(el.kind) != "electro" or str(el.member_role) != "contact":
			continue
		var gtag := str(el.group_tag)
		if gtag == "":
			# Найти primary группы.
			for other in ordered:
				if int(other.id) == int(el.group_id):
					gtag = str(other.tag)
					el.group_tag = gtag
					break
		# Первый контакт кнопки неотделим — без отдельной подписи.
		if ElectroLib.is_button_fixed_contact(self, el):
			el.detached = false
			el.tag = ""
			continue
		if bool(el.detached):
			el.tag = "%s.%d" % [gtag if gtag != "" else "E0", int(el.member_index)]
		else:
			el.tag = ""
	_electro_n = electro_counts
	_src_n = n_src
	_valve_n = n_valve
	_cyl_n = n_cyl
	_junc_n = n_junc
	_acc_n = n_acc
	_rail_n = n_rail


func _count_kind(kind: String) -> int:
	var n := 0
	for el in elements:
		if el.kind == kind:
			n += 1
	return n


func get_element(id: int) -> Element:
	if _element_index_dirty:
		_rebuild_element_index()
	if _element_index.has(id):
		return _element_index[id] as Element
	return null


func get_wire(id: int) -> Wire:
	for wire in wires:
		if wire.id == id:
			return wire
	return null


func _rebuild_element_index() -> void:
	_element_index.clear()
	for el in elements:
		if el == null:
			continue
		_element_index[int(el.id)] = el
	_element_index_dirty = false


func invalidate_element_index() -> void:
	_element_index_dirty = true
	_has_electro_dirty = true


func select_only(id: int, space: String = "") -> void:
	selected_ids = [id] if id >= 0 else []
	selected_wire_id = -1
	selected_wire_ids.clear()
	if space != "":
		selection_space = space
	elif id < 0:
		selection_space = ""


func select_wire(id: int, space: String = "") -> void:
	selected_ids.clear()
	selected_wire_id = id
	selected_wire_ids.clear()
	if id >= 0:
		selected_wire_ids.append(id)
	if space != "":
		selection_space = space


func toggle_wire_select(id: int, space: String = "") -> void:
	selected_ids.clear()
	if id < 0:
		return
	var ix: int = selected_wire_ids.find(id)
	if ix >= 0:
		selected_wire_ids.remove_at(ix)
	else:
		selected_wire_ids.append(id)
	if selected_wire_ids.is_empty():
		selected_wire_id = -1
	else:
		selected_wire_id = int(selected_wire_ids[selected_wire_ids.size() - 1])
	if space != "":
		selection_space = space


func clear_selection() -> void:
	selected_ids.clear()
	selected_wire_id = -1
	selected_wire_ids.clear()
	selection_space = ""


func wire_is_electric(wire: Wire) -> bool:
	if wire == null:
		return false
	var ea := get_element(int(wire.a_id))
	if ea == null:
		return false
	return port_domain(ea, str(wire.a_port)) == "electric"


func set_wire_broken(wire_id: int, broken: bool) -> void:
	var w := get_wire(wire_id)
	if w == null or not wire_is_electric(w):
		return
	w.broken = broken
	w.group_id = 0 # старый wire.group_id больше не используется


## Жила визуально проходит через групповую линию (rail УГО).
func wire_on_group_line(wire_id: int) -> bool:
	var w := get_wire(wire_id)
	if w == null or not wire_is_electric(w):
		return false
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var Rail2D = preload("res://scripts/domain/rail_2d.gd")
	var pts: PackedVector2Array = WireRouter2D.path_for(self, w)
	if pts.size() < 2:
		return false
	var vis: Dictionary = Rail2D.visual_for_path(self, "electric", pts)
	var parts: Array = vis.get("parts", []) as Array
	# Коридор: середина скрыта → ≥2 хвоста, или один укороченный.
	if parts.size() >= 2:
		return true
	if parts.size() == 1:
		var p0: PackedVector2Array = parts[0] as PackedVector2Array
		return p0.size() >= 2 and _poly_len(p0) + 1.0 < _poly_len(pts)
	return false


## Убрать из групповой: скрытый участок сдвинуть вправо на несколько клеток.
func nudge_wire_off_group_line(wire_id: int) -> void:
	var w := get_wire(wire_id)
	if w == null or not wire_is_electric(w):
		return
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var Rail2D = preload("res://scripts/domain/rail_2d.gd")
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var pts: PackedVector2Array = WireRouter2D.path_for(self, w)
	if pts.size() < 2:
		return
	var vis: Dictionary = Rail2D.visual_for_path(self, "electric", pts)
	var parts: Array = vis.get("parts", []) as Array
	var shift: Vector2 = Vector2(Geom.SCH_GRID * 3.0, 0.0)
	# Материализуем joints = все промежуточные точки, сдвигая «скрытую» середину вправо.
	var new_joints: Array = []
	if parts.size() >= 2:
		var enter: Vector2 = (parts[0] as PackedVector2Array)[(parts[0] as PackedVector2Array).size() - 1]
		var exit_p: Vector2 = (parts[parts.size() - 1] as PackedVector2Array)[0]
		# Хвост A → вход+сдвиг → выход+сдвиг → хвост B (орто).
		var a_pts: PackedVector2Array = parts[0] as PackedVector2Array
		var b_pts: PackedVector2Array = parts[parts.size() - 1] as PackedVector2Array
		for i in range(1, a_pts.size()):
			new_joints.append(a_pts[i])
		var mid_a: Vector2 = enter + shift
		var mid_b: Vector2 = exit_p + shift
		mid_a = Vector2(snappedf(mid_a.x, Geom.SCH_GRID), snappedf(mid_a.y, Geom.SCH_GRID))
		mid_b = Vector2(snappedf(mid_b.x, Geom.SCH_GRID), snappedf(mid_b.y, Geom.SCH_GRID))
		if new_joints.is_empty() or (new_joints[new_joints.size() - 1] as Vector2).distance_to(mid_a) > 0.5:
			new_joints.append(mid_a)
		if mid_b.distance_to(mid_a) > 0.5:
			new_joints.append(mid_b)
		for i in range(b_pts.size() - 1):
			new_joints.append(b_pts[i])
	else:
		# Нет явного клипа — сдвинуть все суставы вправо.
		for j in w.joints:
			if typeof(j) == TYPE_VECTOR2:
				var p: Vector2 = j as Vector2
				new_joints.append(p + shift)
			else:
				new_joints.append(j)
		if new_joints.is_empty() and pts.size() >= 3:
			for i in range(1, pts.size() - 1):
				new_joints.append(pts[i] + shift)
	w.joints = new_joints
	w.group_id = 0
	WireRouter2D.invalidate()
	touch_scene()
	notify("Жила выведена из групповой линии")


func _poly_len(pts: PackedVector2Array) -> float:
	var L: float = 0.0
	for i in range(pts.size() - 1):
		L += pts[i].distance_to(pts[i + 1])
	return L


func primary() -> Element:
	if selected_ids.is_empty():
		return null
	return get_element(selected_ids[selected_ids.size() - 1])


func remove_selected() -> void:
	if selected_wire_id >= 0:
		remove_wire(selected_wire_id)
		return
	var ids := selected_ids.duplicate()
	selected_ids.clear()
	if ids.is_empty():
		return
	begin_history_group()
	for id in ids:
		_remove_element(id, false)
	renumber_wires()
	renumber_tags()
	WireRouter2D.invalidate()
	_touch_scene()
	end_history_group()


func remove_element(id: int) -> void:
	begin_history_group()
	_remove_element(id, false)
	renumber_wires()
	renumber_tags()
	WireRouter2D.invalidate()
	_touch_scene()
	end_history_group()


func _remove_element(id: int, renumber_now: bool = true, opts: Dictionary = {}) -> void:
	# opts: promote_fixed_button (Del с схемы), sync_button_defs (после удаления доп. контакта).
	var promote_fixed: bool = bool(opts.get("promote_fixed_button", true))
	var sync_btn_defs: bool = bool(opts.get("sync_button_defs", true))
	var el0 = get_element(id)
	# Первый ключ кнопки — только вместе с актуатором.
	if promote_fixed and el0 != null and ElectroLib.is_button_fixed_contact(self, el0):
		id = int(el0.group_id)
		el0 = get_element(id)
	# Доп. контакт кнопки: после удаления убрать единицу из перечня primary.
	var sync_primary_id: int = -1
	var sync_member_index: int = -1
	if sync_btn_defs and el0 != null and str(el0.member_role) == "contact":
		var p0 = get_element(int(el0.group_id))
		if p0 != null and str(p0.electro_class) in ["button", "e_stop"] \
				and not ElectroLib.is_button_fixed_contact(self, el0):
			sync_primary_id = int(p0.id)
			sync_member_index = int(el0.member_index)
	# С электрогруппой: удаление primary уносит неоткреплённые контакты.
	var drop_ids := {id: true}
	var primary = get_element(id)
	if primary != null and str(primary.kind) == "electro" and str(primary.member_role) != "contact":
		for m in electro_group_members(int(primary.group_id) if int(primary.group_id) >= 0 else id):
			if int(m.id) != id and str(m.member_role) == "contact" and not bool(m.detached):
				drop_ids[m.id] = true
	var kept_wires: Array = []
	for wire in wires:
		if drop_ids.has(wire.a_id) or drop_ids.has(wire.b_id):
			continue
		kept_wires.append(wire)
	wires = kept_wires
	invalidate_port_wire_index()
	var kept_els: Array = []
	for el in elements:
		if not drop_ids.has(el.id):
			kept_els.append(el)
	elements = kept_els
	invalidate_element_index()
	if sync_primary_id >= 0:
		var p_sync = get_element(sync_primary_id)
		if p_sync != null:
			ElectroLib.drop_button_contact_unit(self, p_sync, sync_member_index)
	if renumber_now:
		renumber_wires()
		renumber_tags()
		WireRouter2D.invalidate()


func remove_wire(id: int) -> void:
	for i in wires.size():
		if wires[i].id == id:
			wires.remove_at(i)
			invalidate_port_wire_index()
			renumber_wires()
			_touch_scene()
			break
	if selected_wire_id == id:
		selected_wire_id = -1
	var six: int = selected_wire_ids.find(id)
	if six >= 0:
		selected_wire_ids.remove_at(six)


## Концевые упоры DIN не храним как элементы: УГО нет, в 3D — `_ensure_din_stops`.
func _strip_din_stop_elements() -> void:
	var keep: Array = []
	var removed: Dictionary = {}
	for el in elements:
		if str(el.kind) == "electro" and str(el.electro_class) == "din_stop":
			removed[int(el.id)] = true
			continue
		keep.append(el)
	if removed.is_empty():
		return
	elements = keep
	var sel_rm: Array = []
	for sid in selected_ids:
		if removed.has(int(sid)):
			sel_rm.append(sid)
	for sid2 in sel_rm:
		selected_ids.erase(sid2)


func migrate_rail_terminal_wires() -> void:
	## Старые сцены: провода к шине → прямые связи между приборами; шина остаётся визуальной.
	var drop: Dictionary = {}
	var peers: Dictionary = {} # rail_id -> [{id, port}]
	for wire in wires:
		var a = get_element(int(wire.a_id))
		var b = get_element(int(wire.b_id))
		var rail = null
		var peer_id := -1
		var peer_port := ""
		if a != null and str(a.kind) == "rail":
			rail = a
			peer_id = int(wire.b_id)
			peer_port = str(wire.b_port)
		elif b != null and str(b.kind) == "rail":
			rail = b
			peer_id = int(wire.a_id)
			peer_port = str(wire.a_port)
		if rail == null:
			continue
		drop[int(wire.id)] = true
		var rid: int = int(rail.id)
		if not peers.has(rid):
			peers[rid] = []
		(peers[rid] as Array).append({"id": peer_id, "port": peer_port})
	if drop.is_empty():
		return
	var kept: Array = []
	for wire in wires:
		if not drop.has(int(wire.id)):
			kept.append(wire)
	wires = kept
	invalidate_port_wire_index()
	for rid in peers.keys():
		var rail_el = get_element(int(rid))
		if rail_el != null:
			rail_el.rail_taps = []
		var list: Array = peers[rid] as Array
		for i in list.size():
			for j in range(i + 1, list.size()):
				var pa: Dictionary = list[i]
				var pb: Dictionary = list[j]
				if int(pa["id"]) == int(pb["id"]):
					continue
				_add_wire_raw(int(pa["id"]), str(pa["port"]), int(pb["id"]), str(pb["port"]))
	renumber_wires()
	WireRouter2D.invalidate()

## Порядковые номера линий: отдельно электро и пневмо, по возрастанию id.
func renumber_wires() -> void:
	var elec: Array = []
	var pneum: Array = []
	for w in wires:
		var ea = get_element(int(w.a_id))
		var is_elec: bool = ea != null and port_domain(ea, str(w.a_port)) == "electric"
		if is_elec:
			elec.append(w)
		else:
			pneum.append(w)
	elec.sort_custom(func(a, b): return int(a.id) < int(b.id))
	pneum.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for i in elec.size():
		elec[i].num = i + 1
	for i in pneum.size():
		pneum[i].num = i + 1


## Буквенно-позиционное обозначение аппарата (KL3, не KL3.1 у контакта).
func element_designation(el) -> String:
	if el == null:
		return "?"
	if str(el.kind) == "electro":
		var gt: String = str(el.group_tag).strip_edges()
		if gt != "":
			return gt
		if str(el.member_role) == "contact" and int(el.group_id) >= 0:
			var prim = get_element(int(el.group_id))
			if prim != null:
				var pt: String = str(prim.tag).strip_edges()
				if pt != "":
					return pt
	var t: String = str(el.tag).strip_edges()
	return t if t != "" else "?"


## Русское имя порта для подсказки (позиции 1…5 / буквенно-цифровые клеммы не трогаем).
func port_label_ru(el, port: String) -> String:
	var p: String = str(port)
	if el == null:
		return p
	match str(el.kind):
		"cylinder":
			if p == "cap":
				return "Поршневая"
			if p == "rod":
				return "Штоковая"
		"source":
			if p == "out":
				return "Выход"
	return p


## Роль электроконтакта для подписей/кембриков: только COM / NO / NC.
func contact_role_ru(role: String) -> String:
	match str(role):
		"COM", "NC", "NO":
			return str(role)
		_:
			return str(role)


## Тип элемента для подсказки (не путать с буквенно-позиционным обозначением).
func element_kind_ru(el) -> String:
	if el == null:
		return ""
	match str(el.kind):
		"source":
			return "Источник давления"
		"junction":
			match str(el.get("junction_style") if el.get("junction_style") != null else "tee"):
				"wye":
					return "Тройник Y"
				"manifold":
					return "Коллектор"
				"adapter":
					return "Переходник Ø"
				_:
					return "Тройник"
		"cylinder":
			return "Пневмоцилиндр"
		"valve":
			return "Распределитель"
		"accessory":
			match str(el.accessory_class):
				"check":
					return "Обратный клапан"
				"throttle":
					return "Дроссель регулируемый"
				"throttle_fixed":
					return "Дроссель нерегулируемый"
				"throttle_check":
					return "Дроссель с обратным клапаном"
				"throttle_check_fixed":
					return "Дроссель с ОК (нерегулируемый)"
				"reservoir":
					return "Ресивер"
				"regulator":
					return "Регулятор давления"
				"frl":
					return "Блок подготовки воздуха"
				"shuttle":
					return "Клапан «ИЛИ»"
				"and_valve":
					return "Клапан «И»"
				"quick_exhaust":
					return "Клапан быстрого выхлопа"
				"shutoff":
					return "Отсечной кран"
				_:
					return "Арматура"
		"electro":
			return _electro_kind_ru(el)
		"coil":
			return "Катушка"
		"rail":
			return "Шина"
		_:
			return ""


## Название электроэлемента: title из рецепта каталога, иначе класс.
func _electro_kind_ru(el) -> String:
	var rid: String = str(el.recipe_id) if el.get("recipe_id") != null else ""
	if rid != "":
		var rec: Dictionary = ElectroLib.recipe(rid)
		var title: String = str(rec.get("title", ""))
		if title != "":
			return title
	# Отдельный контакт группы (без своего recipe_id).
	if str(el.member_role) == "contact" or str(el.electro_class) == "contact":
		return "Контакт"
	match str(el.electro_class):
		"button":
			return "Кнопка"
		"e_stop":
			return "Аварийная кнопка"
		"switch":
			return "Переключатель"
		"lamp":
			return "Лампа сигнальная"
		"relay":
			return "Реле промежуточное"
		"timer_relay":
			return "Реле времени"
		"solenoid_coil":
			return "Катушка ЭМ"
		"mcb":
			return "Автомат"
		"rcd":
			return "УЗО"
		"rcbo":
			return "АВДТ"
		"contactor":
			return "Контактор"
		"thermal":
			return "Тепловое реле"
		"voltage_relay":
			return "Реле напряжения"
		"terminal":
			return "Клеммник"
		"psu":
			return "Блок питания"
		"supply":
			return "Ввод питания"
		"busbar":
			return "Шина"
		"din_stop":
			return "Концевой упор DIN"
		"din_socket":
			return "Розетка DIN"
		_:
			return "Электроаппарат"


## Конец линии для подсказки: KL1:42(NC) или КМ1:выход.
func wire_end_tip(el_id: int, port: String) -> String:
	var el := get_element(el_id)
	var p: String = str(port)
	if el == null:
		return "?:%s" % p
	var tag: String = element_designation(el)
	var p_show: String = port_label_ru(el, p)
	if str(el.kind) == "electro" and str(el.electro_class) == "terminal":
		var lab: String = ElectroLib.terminal_port_label(el, p)
		if lab != "":
			return "%s:%s(%s)" % [tag, p_show, lab]
		return "%s:%s" % [tag, p_show]
	var role: String = ElectroLib.port_contact_role(el, p)
	if role != "":
		return "%s:%s(%s)" % [tag, p_show, contact_role_ru(role)]
	return "%s:%s" % [tag, p_show]


## Реквизит конца для кембрика: 1:KL1:42(…).
func wire_end_mark_label(wire: Wire, at_a: bool) -> String:
	if wire == null:
		return ""
	var n: int = int(wire.num)
	if n <= 0:
		renumber_wires()
		n = int(wire.num)
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	return str(n) + ":" + wire_end_tip(el_id, port)


## Всплывашка линии — одинаково для 2D и 3D (BBCode, параметр = строка).
func wire_hover_tip(wire: Wire) -> String:
	if wire == null:
		return ""
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var n: int = int(wire.num)
	if n <= 0:
		renumber_wires()
		n = int(wire.num)
	var a_s: String = wire_end_tip(int(wire.a_id), str(wire.a_port))
	var b_s: String = wire_end_tip(int(wire.b_id), str(wire.b_port))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Линия %s" % SimV.tip_b(str(n)))
	lines.append("%s ↔ %s" % [SimV.tip_b(a_s), SimV.tip_b(b_s)])
	var a_el := get_element(int(wire.a_id))
	var is_elec: bool = a_el != null and port_domain(a_el, str(wire.a_port)) == "electric"
	if not is_elec:
		var od_show: float = float(wire.od_mm)
		if od_show < 1.0:
			od_show = float(wire.id_mm)
		lines.append(SimV.tip_kv("Наружный диаметр (OD)", "%.0f мм" % od_show))
		lines.append(SimV.tip_kv("Внутренний диаметр (ID)", "%.1f мм" % float(wire.id_mm)))
		var len_m: float = _wire_path_length_m(wire)
		var vol_cm3: float = _wire_volume(wire) * 1.0e6
		lines.append(SimV.tip_kv("Длина (L)", "%.2f м" % len_m))
		lines.append(SimV.tip_kv("Объём (V)", "%.1f см³" % vol_cm3))
	if running or sim_time > 0.0:
		if not is_elec:
			lines.append(SimV.format_pressure_flow(wire_viz_pressure(wire), float(wire.flow_vis)))
	return "\n".join(lines)


## Подсказка по корпусу элемента — одна и та же в 2D и 3D.
func element_sim_tip(el_id: int) -> String:
	var el := get_element(el_id)
	if el == null:
		return ""
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var tag: String = element_designation(el)
	var kind_s: String = element_kind_ru(el)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(SimV.tip_b(tag) if kind_s == "" else "%s · %s" % [SimV.tip_b(tag), kind_s])
	# Редактор: настройки, которые раньше были на УГО (% дросселя).
	if not running and sim_time <= 0.0:
		if str(el.kind) == "accessory":
			var cls_e: String = str(el.accessory_class)
			if cls_e in ["throttle", "throttle_check"]:
				lines.append(SimV.tip_kv("Открытие", "%.0f%%" % (clampf(float(el.opening), 0.0, 1.0) * 100.0)))
				lines.append(SimV.tip_kv("Давление открытия КО", "%.2f бар" % float(el.crack_pressure_bar)))
			elif cls_e == "throttle_check_fixed":
				lines.append(SimV.tip_kv("Сечение (фикс.)", "%.0f%%" % (clampf(float(el.opening), 0.0, 1.0) * 100.0)))
				lines.append(SimV.tip_kv("Давление открытия КО", "%.2f бар" % float(el.crack_pressure_bar)))
			elif cls_e == "throttle_fixed":
				lines.append(SimV.tip_kv("Сечение", "Фиксированное"))
			elif cls_e == "check":
				lines.append(SimV.tip_kv("Давление открытия", "%.2f бар" % float(el.crack_pressure_bar)))
			elif cls_e in ["regulator", "frl"]:
				lines.append(SimV.tip_kv("Уставка", "%.2f бар" % float(el.set_pressure_bar)))
			elif cls_e == "reservoir":
				lines.append(SimV.tip_kv("Объём (V)", "%.1f л" % float(el.volume_l)))
			elif cls_e == "shutoff":
				lines.append(SimV.tip_kv("Состояние", "Открыт" if int(el.valve_pos) >= 1 else "Закрыт"))
		return "\n".join(lines)
	match str(el.kind):
		"source":
			var ps: float = float(el.pressure_bar) * 1.0e5 + ATM
			lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(ps)))
		"junction":
			lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(float(el.p_cap))))
		"cylinder":
			var stroke_m: float = maxf(float(el.stroke_mm) * 0.001, 1.0e-6)
			var pct: float = clampf(float(el.x) / stroke_m, 0.0, 1.0) * 100.0
			lines.append(SimV.tip_kv("Поршневая · давление (P)", SimV.format_bar(float(el.p_cap))))
			lines.append(SimV.tip_kv("Штоковая · давление (P)", SimV.format_bar(float(el.p_rod))))
			lines.append(SimV.tip_kv("Ход", "%.0f%%" % pct))
		"rotary_cylinder":
			var th_max: float = maxf(deg_to_rad(float(el.angle_max_deg)), 1.0e-6)
			var pct_r: float = clampf(float(el.angle) / th_max, 0.0, 1.0) * 100.0
			var pa_r: float = float(el.port_press.get("a", ATM)) if el.get("port_press") != null else ATM
			var pb_r: float = float(el.port_press.get("b", ATM)) if el.get("port_press") != null else ATM
			lines.append(SimV.tip_kv("Камера a (между) · P", SimV.format_bar(pa_r)))
			lines.append(SimV.tip_kv("Камера b (снаружи) · P", SimV.format_bar(pb_r)))
			lines.append(SimV.tip_kv("Угол", "%.0f%% (%.0f°)" % [pct_r, rad_to_deg(float(el.angle))]))
			lines.append(SimV.tip_kv("Момент @6 бар", "%.1f Н·м" % float(el.torque_nm_at_6bar)))
		"air_motor":
			var pin_t: float = float(el.port_press.get("in", ATM)) if el.get("port_press") != null else ATM
			var pex_t: float = float(el.port_press.get("exhaust", ATM)) if el.get("port_press") != null else ATM
			var rpm_t: float = absf(float(el.omega)) * 60.0 / TAU
			lines.append(SimV.tip_kv("Вход · P", SimV.format_bar(pin_t)))
			lines.append(SimV.tip_kv("Выхлоп · P", SimV.format_bar(pex_t)))
			lines.append(SimV.tip_kv("Скорость", "%.0f об/мин" % rpm_t))
			lines.append(SimV.tip_kv("Stall @6 бар", "%.2f Н·м" % float(el.torque_nm_at_6bar)))
		"valve":
			var npos: int = maxi(int(el.valve_positions), 1)
			var p_el: float = element_viz_pressure(el)
			lines.append(SimV.tip_kv("Позиция золотника", "%d из %d" % [int(el.valve_pos) + 1, npos]))
			lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(p_el)))
		"accessory":
			var p1: float = float(el.port_press.get("1", ATM)) if el.get("port_press") != null else ATM
			var p2: float = float(el.port_press.get("2", ATM)) if el.get("port_press") != null else ATM
			if str(el.accessory_class) == "check":
				var st: String = "Открыт" if float(el.opening) > 0.5 else "Закрыт"
				lines.append(SimV.tip_kv("Состояние", st))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
				lines.append(SimV.tip_kv("Давление открытия", "%.2f бар" % float(el.crack_pressure_bar)))
			elif str(el.accessory_class) in ["throttle", "throttle_check"]:
				lines.append(SimV.tip_kv("Открытие", "%.0f%%" % (clampf(float(el.opening), 0.0, 1.0) * 100.0)))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
			elif str(el.accessory_class) == "throttle_fixed":
				lines.append(SimV.tip_kv("Сечение", "Фиксированное"))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
			elif str(el.accessory_class) == "reservoir":
				lines.append(SimV.tip_kv("Объём (V)", "%.1f л" % float(el.volume_l)))
				lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(p1)))
			elif str(el.accessory_class) in ["regulator", "frl"]:
				lines.append(SimV.tip_kv("Уставка", "%.2f бар" % float(el.set_pressure_bar)))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
			elif str(el.accessory_class) == "shutoff":
				var st_z: String = "Открыт" if float(el.opening) > 0.5 else "Закрыт"
				lines.append(SimV.tip_kv("Состояние", st_z))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
			elif str(el.accessory_class) == "relief":
				var st_r: String = "Открыт" if float(el.opening) > 0.15 else "Закрыт"
				if bool(el.pressed):
					st_r = "Ручной сброс"
				lines.append(SimV.tip_kv("Уставка", "%.2f бар" % float(el.set_pressure_bar)))
				lines.append(SimV.tip_kv("Состояние", st_r))
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
			else:
				lines.append(SimV.tip_kv("Порт 1 · давление (P)", SimV.format_bar(p1)))
				lines.append(SimV.tip_kv("Порт 2 · давление (P)", SimV.format_bar(p2)))
		_:
			pass
	return "\n".join(lines)


## Подсказка по порту — та же полнота, что у корпуса (+ расход на порту).
func port_sim_tip(el_id: int, port: String) -> String:
	var el := get_element(el_id)
	var p: String = str(port)
	if el == null:
		return "?:%s" % p
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var head: String = wire_end_tip(el_id, p)
	var kind_s: String = element_kind_ru(el)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(SimV.tip_b(head) if kind_s == "" else "%s · %s" % [SimV.tip_b(head), kind_s])
	if not running and sim_time <= 0.0:
		if str(el.kind) == "accessory":
			var cls_p: String = str(el.accessory_class)
			if cls_p in ["throttle", "throttle_check"]:
				lines.append(SimV.tip_kv("Открытие", "%.0f%%" % (clampf(float(el.opening), 0.0, 1.0) * 100.0)))
			elif cls_p == "throttle_fixed":
				lines.append(SimV.tip_kv("Сечение", "Фиксированное"))
			elif cls_p == "check":
				lines.append(SimV.tip_kv("Давление открытия", "%.2f бар" % float(el.crack_pressure_bar)))
		return "\n".join(lines)
	if port_domain(el, p) == "electric":
		return "\n".join(lines)
	var press_pa: float = ATM
	var q: float = 0.0
	match str(el.kind):
		"cylinder":
			if p == "cap":
				press_pa = float(el.p_cap)
				q = float(el.q_cap)
			elif p == "rod":
				press_pa = float(el.p_rod)
				q = float(el.q_rod)
			elif el.port_press.has(p):
				press_pa = float(el.port_press[p])
				q = float(el.port_q.get(p, 0.0)) if el.get("port_q") != null else 0.0
			var stroke_m: float = maxf(float(el.stroke_mm) * 0.001, 1.0e-6)
			var pct: float = clampf(float(el.x) / stroke_m, 0.0, 1.0) * 100.0
			lines.append(SimV.format_pressure_flow(press_pa, q))
			lines.append(SimV.tip_kv("Ход", "%.0f%%" % pct))
		"source":
			press_pa = float(el.pressure_bar) * 1.0e5 + ATM
			lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(press_pa)))
		"junction":
			press_pa = float(el.p_cap)
			lines.append(SimV.tip_kv("Давление (P)", SimV.format_bar(press_pa)))
		"valve":
			if el.port_press.has(p):
				press_pa = float(el.port_press[p])
			q = port_viz_q(el, p)
			var npos: int = maxi(int(el.valve_positions), 1)
			lines.append(SimV.format_pressure_flow(press_pa, q))
			lines.append(SimV.tip_kv("Позиция золотника", "%d из %d" % [int(el.valve_pos) + 1, npos]))
		"accessory":
			if el.port_press.has(p):
				press_pa = float(el.port_press[p])
			# Открытый / подключённый: tip = сквозной (не net≈0 у ресивера).
			q = port_viz_q(el, p)
			lines.append(SimV.format_pressure_flow(press_pa, q))
			if str(el.accessory_class) == "check":
				lines.append(SimV.tip_kv("Состояние", "Открыт" if float(el.opening) > 0.5 else "Закрыт"))
				lines.append(SimV.tip_kv("Давление открытия", "%.2f бар" % float(el.crack_pressure_bar)))
			elif str(el.accessory_class) in ["throttle", "throttle_check"]:
				lines.append(SimV.tip_kv("Открытие", "%.0f%%" % (clampf(float(el.opening), 0.0, 1.0) * 100.0)))
		_:
			if el.port_press.has(p):
				press_pa = float(el.port_press[p])
			if str(el.kind) == "source":
				q = 0.0
				if el.port_q.has(p):
					q = float(el.port_q[p])
			else:
				q = port_viz_q(el, p)
			lines.append(SimV.format_pressure_flow(press_pa, q))
	return "\n".join(lines)


func port_domain(el: Element, port: String) -> String:
	# Среды не смешиваются на одном проводе.
	if el == null:
		return ""
	return Geom.port_domain(el, port)


## Макс. проводов на порт: электро клемма = 2; отвод шины = 1; иначе 1.
func port_wire_limit(el, port: String) -> int:
	if el == null:
		return 1
	# Электро: до 2 жил в одну клемму (сдвоенный НШВИ). Пневмо: строго 1 трубка на порт.
	if port_domain(el, port) == "electric" and str(el.kind) == "electro":
		return 2
	return 1


func _port_busy_message(el, port: String) -> String:
	if el != null and port_domain(el, port) == "electric":
		return "В клемму уже два провода — для разветвления используйте клеммник"
	return "Пневмопорт занят — вторая трубка невозможна, нужен тройник / ветвитель"


## Шина — не клеммник: провод к шине не сажается (только визуальный коридор).
func connect_to_rail(_from_id: int, _from_port: String, _rail_id: int, _world: Vector2) -> bool:
	notify("Групповая линия — визуальная трасса. Соединяйте приборы напрямую; общий участок скроется.")
	return false


func wires_on_port(el_id: int, port: String) -> Array:
	if _port_wire_index_dirty:
		_rebuild_port_wire_index()
	var key: String = "%d|%s" % [el_id, port]
	if not _port_wires_index.has(key):
		return []
	# duplicate: callers sort in-place (сдвоенный НШВИ).
	return (_port_wires_index[key] as Array).duplicate()


func port_wire_count(el_id: int, port: String) -> int:
	if _port_wire_index_dirty:
		_rebuild_port_wire_index()
	var key: String = "%d|%s" % [el_id, port]
	if not _port_wires_index.has(key):
		return 0
	return (_port_wires_index[key] as Array).size()


func add_wire(a_id: int, a_port: String, b_id: int, b_port: String) -> bool:
	if a_id == b_id and a_port == b_port:
		notify("Нельзя соединить порт сам с собой")
		return false
	var a := get_element(a_id)
	var b := get_element(b_id)
	if a == null or b == null:
		return false
	if str(a.kind) == "rail" or str(b.kind) == "rail":
		notify("Групповая линия — визуальная трасса, не клеммник")
		return false
	if Geom.port_by_name(a, a_port).is_empty() or Geom.port_by_name(b, b_port).is_empty():
		notify("У элемента нет такого канала")
		return false
	var da := port_domain(a, a_port)
	var db := port_domain(b, b_port)
	if da != db:
		notify("Нельзя соединять электрический и пневматический порты")
		return false
	if port_wire_count(a_id, a_port) >= port_wire_limit(a, a_port):
		notify(_port_busy_message(a, a_port))
		return false
	if port_wire_count(b_id, b_port) >= port_wire_limit(b, b_port):
		notify(_port_busy_message(b, b_port))
		return false
	return _add_wire_raw(a_id, a_port, b_id, b_port)


## Соединение с явными ортогональными joints (ручная проводка, без автороута).
func add_wire_with_joints(a_id: int, a_port: String, b_id: int, b_port: String, joints: Array) -> bool:
	# Трасса передаётся сразу — при разном Ø переходник сядет на половину пути.
	if not _add_wire_raw_ex(a_id, a_port, b_id, b_port, joints):
		return false
	# Не WireRouter2D.invalidate() — сброс кэша ВСЕХ трасс = фриз на плотной схеме.
	# Новая жила не в кэше; позиции УГО не менялись — старые path_for валидны.
	_touch_scene()
	return true


func _add_wire_raw(a_id: int, a_port: String, b_id: int, b_port: String) -> bool:
	return _add_wire_raw_ex(a_id, a_port, b_id, b_port, [])


## joints — точки 2D-трассы (без tip'ов); при разном Ø — шланг–переходник–шланг.
func _add_wire_raw_ex(a_id: int, a_port: String, b_id: int, b_port: String, joints: Array) -> bool:
	var a := get_element(a_id)
	var b := get_element(b_id)
	if a == null or b == null:
		return false
	if port_domain(a, a_port) != port_domain(b, b_port):
		notify("Нельзя соединять электрический и пневматический порты")
		return false
	# Защита: даже внутренние вызовы не сажают 2-ю пневмотрубку на один порт.
	if port_wire_count(a_id, a_port) >= port_wire_limit(a, a_port):
		notify(_port_busy_message(a, a_port))
		return false
	if port_wire_count(b_id, b_port) >= port_wire_limit(b, b_port):
		notify(_port_busy_message(b, b_port))
		return false
	var is_elec: bool = port_domain(a, a_port) == "electric"
	var od_pick: float = 0.0
	if not is_elec:
		var oa: float = TubeFit.port_tube_od(a, a_port)
		var ob: float = TubeFit.port_tube_od(b, b_port)
		if oa >= 1.0 and ob >= 1.0 and absf(oa - ob) > 0.15:
			return _add_wire_via_adapter(a_id, a_port, b_id, b_port, oa, ob, joints)
		od_pick = _resolve_tube_od_for_link(a, a_port, b, b_port)
		if od_pick < 1.0:
			notify("Нельзя соединить порты с разным Ø трубки — нужен переходник")
			return false
	return _spawn_wire(a_id, a_port, b_id, b_port, od_pick if not is_elec else 0.0, is_elec, joints)


func _spawn_wire(
	a_id: int, a_port: String, b_id: int, b_port: String,
	od_pick: float, is_elec: bool, joints: Array
) -> bool:
	var a := get_element(a_id)
	var b := get_element(b_id)
	if a == null or b == null:
		return false
	var wire := Wire.new()
	wire.id = _next_id
	_next_id += 1
	wire.a_id = a_id
	wire.a_port = a_port
	wire.b_id = b_id
	wire.b_port = b_port
	if is_elec:
		wire.id_mm = 1.5
	else:
		TubeFit.apply_tube_od_to_wire(wire, od_pick)
		for el_fix in [a, b]:
			if el_fix == null:
				continue
			if str(el_fix.kind) == "junction" and str(el_fix.junction_style) == "adapter":
				continue
			if str(el_fix.kind) in ["junction", "accessory"] and float(el_fix.tube_od_mm) < 1.0:
				TubeFit.apply_armature_od(el_fix, od_pick)
	wire.joints.clear()
	for j in joints:
		if typeof(j) == TYPE_VECTOR2:
			wire.joints.append((j as Vector2).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID)))
	_init_wire(wire)
	wires.append(wire)
	invalidate_port_wire_index()
	renumber_wires()
	selected_wire_id = wire.id
	selected_ids.clear()
	_touch_scene()
	return true


## Разный Ø: шланг A→переходник→шланг B; переходник ≈ на половине трассы.
func _add_wire_via_adapter(
	a_id: int, a_port: String, b_id: int, b_port: String,
	od_a: float, od_b: float, joints: Array
) -> bool:
	var tip_a: Vector2 = _element_port_tip_world(a_id, a_port)
	var tip_b: Vector2 = _element_port_tip_world(b_id, b_port)
	var mid_sch: Vector2 = _polyline_midpoint(tip_a, joints, tip_b)
	mid_sch = mid_sch.snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))
	var halves: Dictionary = _polyline_split_at_mid(tip_a, joints, tip_b, mid_sch)
	var j_a: Array = halves.get("a", []) as Array
	var j_b: Array = halves.get("b", []) as Array
	var el := add_element("junction@adapter", mid_sch)
	el.tube_od_mm = TubeFit.snap_tube_od(od_a)
	el.tube_od_b_mm = TubeFit.snap_tube_od(od_b)
	el.port_name = TubeFit.thread_for_tube_od(el.tube_od_mm)
	# Ориентация: порт 1 (−X) к A, порт 2 (+X) к B.
	var t: Vector2 = tip_b - tip_a
	if t.length_squared() < 1.0e-6 and j_a.size() + j_b.size() > 0:
		t = Vector2.RIGHT
	el.rotation_quad = _junction_quad_for_tangent(t if t.length_squared() > 1.0e-6 else Vector2.RIGHT)
	# 3D: середина между портами (workshop может задать _pending_adapter_world).
	var mid_w = _pending_adapter_world
	_pending_adapter_world = null
	if mid_w is Vector3:
		el.world_pos = mid_w as Vector3
		el.auto_ground = false
	else:
		var wa = _port_world_hint(a_id, a_port)
		var wb = _port_world_hint(b_id, b_port)
		if wa != null and wb != null:
			el.world_pos = ((wa as Vector3) + (wb as Vector3)) * 0.5
			el.auto_ground = false
			var dir3: Vector3 = (wb as Vector3) - (wa as Vector3)
			dir3.y = 0.0
			if dir3.length_squared() > 1.0e-8:
				dir3 = dir3.normalized()
				# Порт 1 = −X, порт 2 = +X → ось +X к B.
				el.world_basis = Basis(Vector3.UP, atan2(-dir3.z, dir3.x))
	if not _spawn_wire(a_id, a_port, el.id, "1", el.tube_od_mm, false, j_a):
		return false
	if not _spawn_wire(el.id, "2", b_id, b_port, el.tube_od_b_mm, false, j_b):
		return false
	select_only(el.id, "schematic")
	notify("Вставлен переходник Ø%.0f→Ø%.0f" % [el.tube_od_mm, el.tube_od_b_mm])
	return true


func _element_port_tip_world(el_id: int, port: String) -> Vector2:
	var el := get_element(el_id)
	if el == null:
		return Vector2.ZERO
	for p in Geom.ports(el):
		if str(p.get("name", "")) == port:
			var local: Vector2 = p["local"] as Vector2
			return Geom.to_world(el, local)
	return el.position


func _port_world_hint(el_id: int, port: String):
	# Без workshop: оценка из 2D → плоскость цеха.
	var tip: Vector2 = _element_port_tip_world(el_id, port)
	var el := get_element(el_id)
	if el == null:
		return null
	var base: Vector3 = el.world_pos
	return Vector3(base.x + tip.x * 0.001, base.y, base.z + tip.y * 0.001)


func _polyline_midpoint(a: Vector2, joints: Array, b: Vector2) -> Vector2:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(a)
	for j in joints:
		if typeof(j) == TYPE_VECTOR2:
			pts.append(j as Vector2)
	pts.append(b)
	if pts.size() < 2:
		return (a + b) * 0.5
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	if total < 1.0e-3:
		return (a + b) * 0.5
	var half: float = total * 0.5
	var acc: float = 0.0
	for i in range(pts.size() - 1):
		var seg: float = pts[i].distance_to(pts[i + 1])
		if acc + seg >= half:
			var t: float = 0.0 if seg < 1.0e-9 else (half - acc) / seg
			return pts[i].lerp(pts[i + 1], t)
		acc += seg
	return b


func _polyline_split_at_mid(a: Vector2, joints: Array, b: Vector2, mid: Vector2) -> Dictionary:
	var pts: Array = [a]
	for j in joints:
		if typeof(j) == TYPE_VECTOR2:
			pts.append(j)
	pts.append(b)
	# Ближайший сегмент к mid → режем трассу.
	var best_i: int = 0
	var best_d: float = 1.0e12
	for i in range(pts.size() - 1):
		var d: float = _dist_point_seg(mid, pts[i] as Vector2, pts[i + 1] as Vector2)
		if d < best_d:
			best_d = d
			best_i = i
	var ja: Array = []
	for i in range(1, best_i + 1):
		ja.append(pts[i])
	# mid как конец первой половины не кладём в joints (tip переходника).
	var jb: Array = []
	for i in range(best_i + 1, pts.size() - 1):
		jb.append(pts[i])
	return {"a": ja, "b": jb}


## Умное соединение: электро — до 2 проводов на клемму; пневмо — тройник на линии (не 2 трубки в одну цангу).
func connect_or_branch(a_id: int, a_port: String, b_id: int, b_port: String) -> bool:
	var a := get_element(a_id)
	var b := get_element(b_id)
	var ca: int = port_wire_count(a_id, a_port)
	var cb: int = port_wire_count(b_id, b_port)
	var la: int = port_wire_limit(a, a_port)
	var lb: int = port_wire_limit(b, b_port)
	# Прямое соединение, пока оба порта не исчерпали лимит.
	if ca < la and cb < lb:
		return add_wire(a_id, a_port, b_id, b_port)
	if ca >= la and cb >= lb:
		var both_elec: bool = a != null and b != null \
				and port_domain(a, a_port) == "electric" and port_domain(b, b_port) == "electric"
		if both_elec:
			notify("Обе клеммы заняты — используйте клеммник или шину")
		else:
			notify("Оба пневмопорта заняты — поставьте тройник / коллектор")
		return false
	var wa := wire_on(a_id, a_port)
	var wb := wire_on(b_id, b_port)
	if wa != null and wb != null:
		notify("Оба канала заняты — вставьте коллектор вручную")
		return false
	var busy: Wire = wa if wa != null else wb
	if busy == null:
		notify("Порт занят — для разветвления нужен тройник")
		return false
	var free_id := b_id if wa != null else a_id
	var free_port := b_port if wa != null else a_port
	var at := _wire_midpoint(busy)
	var busy_el := get_element(busy.a_id)
	var is_elec: bool = busy_el != null and port_domain(busy_el, str(busy.a_port)) == "electric"
	if is_elec:
		var term := insert_terminal_on_wire(busy.id, at)
		if term == null:
			return false
		var free_t := _terminal_free_port(term)
		if free_t == "":
			notify("У клеммника нет свободного порта")
			return false
		return _add_wire_raw(term.id, free_t, free_id, free_port)
	# Пневматика: не вторая трубка в цангу — тройник в разрыв существующей линии.
	var junc := insert_junction_on_wire(busy.id, at, "tee")
	if junc == null:
		return false
	var free_j := _junction_free_port(junc)
	if free_j == "":
		notify("У тройника нет свободного порта")
		return false
	var ok: bool = _add_wire_raw(junc.id, free_j, free_id, free_port)
	if ok:
		notify("Вставлен тройник — на один пневмопорт только одна трубка")
	return ok


## Вставка DIN-клеммы в разрыв электропровода (вместо пневмотройника).
func insert_terminal_on_wire(wire_id: int, at: Vector2) -> Element:
	var w := get_wire(wire_id)
	if w == null:
		return null
	var a_id := w.a_id
	var a_port := w.a_port
	var b_id := w.b_id
	var b_port := w.b_port
	remove_wire(wire_id)
	var el := add_element("electro@term_block_1", at)
	if el == null:
		return null
	# Feed-through: слева нечёт / справа чёт (1–2); без шины ряды изолированы.
	_add_wire_raw(a_id, a_port, el.id, "1")
	_add_wire_raw(el.id, "2", b_id, b_port)
	select_only(el.id, "schematic")
	notify("Вставлена клемма DIN — свободный порт для ответвления")
	return el


func _terminal_free_port(el: Element) -> String:
	if el == null:
		return ""
	for port in Geom.ports(el):
		var name := str(port["name"])
		if port_wire_count(el.id, name) < port_wire_limit(el, name):
			return name
	return ""


## Вставка узла в разрыв линии (2D точка / 3D тройник).
func insert_junction_on_wire(wire_id: int, at: Vector2, style: String = "tee") -> Element:
	var w := get_wire(wire_id)
	if w == null:
		return null
	var a_id := w.a_id
	var a_port := w.a_port
	var b_id := w.b_id
	var b_port := w.b_port
	var od_keep: float = float(w.od_mm)
	remove_wire(wire_id)
	var el := add_element("junction@" + style, at)
	# Без автоповорота по касательной — пользователь крутит сам (R).
	el.rotation_quad = 0
	if od_keep >= 1.0:
		TubeFit.apply_armature_od(el, od_keep)
	_add_wire_raw(a_id, a_port, el.id, "1")
	_add_wire_raw(el.id, "2", b_id, b_port)
	select_only(el.id, "schematic")
	notify("Вставлен %s — свободный порт для ответвления" % _junction_title(el))
	return el


func _wire_tangent_at(wire: Wire, at: Vector2) -> Vector2:
	var a := get_element(wire.a_id)
	var b := get_element(wire.b_id)
	if a == null or b == null:
		return Vector2.RIGHT
	var pts := WireRouter2D.path_for(self, wire)
	if pts.size() < 2:
		return Vector2.RIGHT
	var best_i := 0
	var best_d := 1.0e12
	for i in range(pts.size() - 1):
		var d := _dist_point_seg(at, pts[i], pts[i + 1])
		if d < best_d:
			best_d = d
			best_i = i
	var t: Vector2 = pts[best_i + 1] - pts[best_i]
	if t.length_squared() < 1.0e-6:
		return Vector2.RIGHT
	return t.normalized()


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1.0e-8 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _junction_quad_for_tangent(t: Vector2) -> int:
	# Порты 1–2 лежат на локальной оси X; повернуть УГО вдоль прохода линии.
	if absf(t.x) >= absf(t.y):
		return 0 if t.x >= 0.0 else 2
	return 1 if t.y >= 0.0 else 3


## Повернуть тройник так, чтобы свободный/ответвляющий порт смотрел к третьей линии.
func orient_junction(el: Element) -> void:
	if el == null or el.kind != "junction":
		return
	if str(el.junction_style) == "manifold":
		return
	var used: Dictionary = {}
	var dirs: Dictionary = {}
	for port in Geom.ports(el):
		var name := str(port["name"])
		var w := wire_on(el.id, name)
		if w == null:
			continue
		used[name] = true
		var other_id: int = w.b_id if w.a_id == el.id else w.a_id
		var other := get_element(other_id)
		if other == null:
			continue
		var pdesc := Geom.port_by_name(el, name)
		var tip: Vector2 = el.position if pdesc.is_empty() else Geom.to_world(el, pdesc["local"])
		var away: Vector2 = other.position - tip
		if away.length_squared() < 1.0:
			away = other.position - el.position
		if away.length_squared() > 1.0e-6:
			dirs[name] = away.normalized()
	if dirs.has("1") and dirs.has("2"):
		var through: Vector2 = (dirs["2"] - dirs["1"]).normalized()
		if through.length_squared() < 1.0e-6:
			through = dirs["2"]
		el.rotation_quad = _junction_quad_for_tangent(through)
	# Ответвление (порт 3): развернуть так, чтобы нормаль смотрела к третьему соседу.
	if dirs.has("3"):
		var want: Vector2 = dirs["3"]
		var best_q := el.rotation_quad
		var best_dot := -2.0
		var cands: Array = [0, 1, 2, 3]
		if dirs.has("1") and dirs.has("2"):
			var through2: Vector2 = (dirs["2"] - dirs["1"]).normalized()
			if through2.length_squared() > 1.0e-6:
				var base := _junction_quad_for_tangent(through2)
				cands = [base, (base + 2) % 4]
		for q in cands:
			# Порт 3: local (0,-1) после поворота квадранта.
			var nn2: Vector2 = Vector2(0, -1).rotated(float(q) * PI * 0.5)
			var d2 := nn2.dot(want)
			if d2 > best_dot:
				best_dot = d2
				best_q = int(q)
		el.rotation_quad = best_q


func branch_onto_wire(wire_id: int, at: Vector2, from_id: int, from_port: String, style: String = "tee") -> bool:
	if wire_on(from_id, from_port) != null:
		var src_w := wire_on(from_id, from_port)
		var j_src := insert_junction_on_wire(src_w.id, _wire_midpoint(src_w), "tee")
		if j_src == null:
			return false
		from_id = j_src.id
		from_port = _junction_free_port(j_src)
		if from_port == "":
			return false
	var junc := insert_junction_on_wire(wire_id, at, style)
	if junc == null:
		return false
	var free_j := _junction_free_port(junc)
	if free_j == "":
		return false
	return _add_wire_raw(from_id, from_port, junc.id, free_j)


func _junction_free_port(el: Element) -> String:
	for port in Geom.ports(el):
		var name := str(port["name"])
		if wire_on(el.id, name) == null:
			return name
	return ""


func _junction_title(el: Element) -> String:
	match str(el.junction_style):
		"wye":
			return "Y-тройник"
		"manifold":
			return "Коллектор"
		"adapter":
			return "Переходник Ø→Ø"
		_:
			return "Тройник"


func _wire_midpoint(wire: Wire) -> Vector2:
	var a := get_element(wire.a_id)
	var b := get_element(wire.b_id)
	if a == null or b == null:
		return Vector2.ZERO
	var pa := Geom.port_by_name(a, wire.a_port)
	var pb := Geom.port_by_name(b, wire.b_port)
	if pa.is_empty() or pb.is_empty():
		return (a.position + b.position) * 0.5
	return (Geom.to_world(a, pa["local"]) + Geom.to_world(b, pb["local"])) * 0.5


func wire_on(el_id: int, port: String) -> Wire:
	if _port_wire_index_dirty:
		_rebuild_port_wire_index()
	var key: String = "%d|%s" % [el_id, port]
	if _port_wire_index.has(key):
		return _port_wire_index[key] as Wire
	return null


func _rebuild_port_wire_index() -> void:
	_port_wire_index.clear()
	_port_wires_index.clear()
	for wire in wires:
		if wire == null:
			continue
		for key in [
			"%d|%s" % [int(wire.a_id), str(wire.a_port)],
			"%d|%s" % [int(wire.b_id), str(wire.b_port)],
		]:
			_port_wire_index[key] = wire
			if not _port_wires_index.has(key):
				_port_wires_index[key] = []
			(_port_wires_index[key] as Array).append(wire)
	_port_wire_index_dirty = false


func invalidate_port_wire_index() -> void:
	_port_wire_index_dirty = true


func _refresh_accessory_port_viz_q() -> void:
	## Сквозной расход для tip — один раз за кадр (не в каждом субшаге).
	for el in elements:
		if el == null or str(el.kind) != "accessory":
			continue
		if el.get("port_q") == null:
			continue
		for name2 in AccLib.port_names(el):
			var q_net: float = float(el.port_q.get(name2, 0.0))
			var q_viz2: float = port_viz_q(el, str(name2))
			if absf(q_viz2) > absf(q_net):
				el.port_q[name2] = q_viz2


func _advance_wire_flow_phase(dt: float) -> void:
	## Фаза анимации потока — один раз за кадр (не в каждом субшаге).
	if dt <= 0.0:
		return
	for wire in wires:
		var area_viz: float = PI * pow(maxf(float(wire.id_mm), 0.5) * 0.0005, 2.0)
		var spd_tgt: float = 0.0
		if absf(float(wire.flow_vis)) > SimVis.FLOW_DEAD:
			spd_tgt = absf(SimVis.puff_speed(float(wire.flow_vis), area_viz))
		var prev_spd: float = float(wire.flow_anim_speed)
		# Attack быстрее decay — конусы сразу трогаются при появлении Q.
		var a_spd: float = 0.4 if spd_tgt > prev_spd else 0.1
		wire.flow_anim_speed = lerpf(prev_spd, spd_tgt, a_spd)
		if float(wire.flow_anim_speed) > 5.0e-5:
			wire.flow_phase = fposmod(float(wire.flow_phase) + float(wire.flow_anim_speed) * dt, 1.0)


func notify(text: String) -> void:
	hint = text
	hint_until = Time.get_ticks_msec() + 4200


func active_hint() -> String:
	if hint != "" and Time.get_ticks_msec() < hint_until:
		return hint
	return ""


## Поворот выделения. Возвращает id элементов, у которых сменился tip (для перетрассировки).
func rotate_selected() -> Dictionary:
	var done: Dictionary = {}
	if selected_ids.is_empty():
		return done
	for id in selected_ids.duplicate():
		if done.has(id):
			continue
		var el := get_element(id)
		if el == null:
			continue
		# Электрогруппа: primary + неоткреплённые контакты/ноги ввода крутятся вместе.
		if str(el.kind) == "electro" and int(el.group_id) >= 0:
			var gid: int = int(el.group_id)
			var primary = get_element(gid)
			if primary != null:
				var role: String = str(el.member_role)
				var solo_detach: bool = (
					role in ["contact", "supply_leg"]
					and bool(el.detached)
					and not ElectroLib.is_button_fixed_contact(self, el)
					and not ElectroLib.is_supply_fixed_leg(self, el)
				)
				if not solo_detach:
					_rotate_electro_group(primary, done)
					continue
		el.rotation_quad = (el.rotation_quad + 1) % 4
		done[id] = true
	_touch_scene()
	return done


func _rotate_electro_group(primary, done: Dictionary) -> void:
	if primary == null:
		return
	var pivot: Vector2 = primary.position
	var members: Array = [primary]
	for m in electro_group_members(int(primary.id)):
		if int(m.id) == int(primary.id):
			continue
		var mrole: String = str(m.member_role)
		if mrole not in ["contact", "supply_leg"]:
			continue
		if bool(m.detached) and not ElectroLib.is_button_fixed_contact(self, m):
			continue
		members.append(m)
	for m in members:
		var rel: Vector2 = m.position - pivot
		m.position = (pivot + rel.rotated(PI * 0.5)).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))
		m.rotation_quad = (int(m.rotation_quad) + 1) % 4
		done[int(m.id)] = true
	if str(primary.electro_class) in ["button", "e_stop"]:
		# Столбик пересобрать вдоль нового локального +Y.
		ElectroLib.layout_button_contacts(self, primary)
	elif str(primary.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		ElectroLib.layout_coil_contacts(self, primary)
	elif str(primary.electro_class) == "supply":
		ElectroLib.layout_supply_legs(self, primary)


func copy_selected() -> void:
	clipboard.clear()
	clipboard_wires.clear()
	if selected_ids.is_empty():
		return
	var have := {}
	for id in selected_ids:
		var el := get_element(id)
		if el == null:
			continue
		clipboard.append(el.pack())
		have[id] = true
	for wire in wires:
		if have.has(wire.a_id) and have.has(wire.b_id):
			clipboard_wires.append({
				"a": wire.a_id, "ap": wire.a_port,
				"b": wire.b_id, "bp": wire.b_port, "d": wire.id_mm,
				"color_id": wire.color_id,
				"joints": wire.joints.duplicate(),
			})


func cut_selected() -> void:
	if selected_ids.is_empty():
		return
	copy_selected()
	remove_selected()


func paste(anchor: Vector2) -> void:
	if clipboard.is_empty():
		notify("Буфер пуст")
		return
	var center := Vector2.ZERO
	for item in clipboard:
		center += item["position"]
	center /= float(clipboard.size())
	var delta := anchor.snapped(Vector2(10, 10)) - center.snapped(Vector2(10, 10))
	var map := {}
	var fresh: Array[int] = []
	for item in clipboard:
		var el := _element_from_pack(item)
		el.position = (item["position"] + delta).snapped(Vector2(10, 10))
		el.world_pos = item["world_pos"] + Vector3(0.16, 0.0, 0.12)
		el.auto_ground = false
		_register(el)
		_init_state(el, true)
		map[item["id"]] = el.id
		fresh.append(el.id)
	# Контакты: group_id → новый id primary, если primary тоже вставлен.
	for item in clipboard:
		var nid: int = int(map.get(item["id"], -1))
		var el2 := get_element(nid)
		if el2 == null or str(el2.member_role) != "contact":
			continue
		var old_gid: int = int(item.get("group_id", -1))
		if map.has(old_gid):
			el2.group_id = int(map[old_gid])
	for link in clipboard_wires:
		if map.has(link["a"]) and map.has(link["b"]):
			if add_wire(map[link["a"]], link["ap"], map[link["b"]], link["bp"]):
				var placed: Wire = wires[wires.size() - 1]
				placed.id_mm = link["d"]
				placed.color_id = str(link.get("color_id", ""))
				_init_wire(placed)
				placed.joints = []
				for point in link.get("joints", []):
					placed.joints.append(point + delta)
	ElectroLib.migrate_terminal_wires(self)
	migrate_rail_terminal_wires()
	renumber_wires()
	_finalize_pasted_contacts(fresh)
	selected_ids = fresh
	selected_wire_id = -1
	selected_wire_ids.clear()
	renumber_tags()
	_touch_scene()


## После вставки контакта: при копии — в перечень реле; позиция вне столбца → detached.
func _finalize_pasted_contacts(fresh: Array) -> void:
	for id in fresh:
		var el := get_element(int(id))
		if el == null or str(el.kind) != "electro" or str(el.member_role) != "contact":
			continue
		var primary = get_element(int(el.group_id))
		if primary == null:
			continue
		if str(primary.electro_class) not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			update_electro_detach(el)
			continue
		var dup_idx: bool = false
		for m in electro_group_members(int(primary.id)):
			if int(m.id) == int(el.id):
				continue
			if str(m.member_role) == "contact" and int(m.member_index) == int(el.member_index):
				dup_idx = true
				break
		if dup_idx:
			ElectroLib.adopt_pasted_coil_contact(self, primary, el)
		update_electro_detach(el)


func duplicate_selected() -> void:
	if selected_ids.is_empty():
		return
	copy_selected()
	var anchor := Vector2.ZERO
	var n := 0
	for item in clipboard:
		anchor += item["position"]
		n += 1
	if n == 0:
		return
	paste(anchor / float(n) + Vector2(30, 30))


func _element_from_pack(item: Dictionary) -> Element:
	var el := Element.new()
	el.kind = item["kind"]
	# Старые сцены: kind=coil → электрокатушка ЭМ.
	if str(el.kind) == "coil":
		el.kind = "electro"
		if str(item.get("electro_class", "")) == "":
			item = item.duplicate(true)
			item["electro_class"] = "solenoid_coil"
			item["electro_mount"] = "none"
			item["tag_prefix"] = "YV"
			item["link_valve"] = true
			item["coil_ports"] = ["A1", "A2"]
			item["recipe_id"] = "solenoid_coil"
	el.tag = item["tag"]
	el.tag_offset = item.get("tag_offset", Vector2.ZERO)
	if typeof(el.tag_offset) != TYPE_VECTOR2:
		el.tag_offset = Vector2.ZERO
	el.position = item["position"]
	el.rotation_quad = int(item.get("rotation_quad", 0))
	el.action = str(item.get("action", "none"))
	# Поля ПЦ — с дефолтами: у source/accessory/junction в демо часто опущены.
	el.bore_mm = float(item.get("bore_mm", 32.0))
	el.rod_mm = float(item.get("rod_mm", 12.0))
	el.stroke_mm = float(item.get("stroke_mm", 100.0))
	el.spring_rate = float(item.get("spring_rate", 0.0))
	el.spring_preload = float(item.get("spring_preload", 0.0))
	el.mass_kg = float(item.get("mass_kg", 1.0))
	el.friction_n = float(item.get("friction_n", 5.0))
	el.load_n = float(item.get("load_n", 0.0))
	el.open_ports = bool(item.get("open_ports", false))
	el.cushion = bool(item.get("cushion", false))
	el.piston_kind = str(item.get("piston_kind", "simple"))
	el.cush_cap = str(item.get("cush_cap", "none"))
	el.cush_rod = str(item.get("cush_rod", "none"))
	el.cush_open_cap = float(item.get("cush_open_cap", 0.35))
	el.cush_open_rod = float(item.get("cush_open_rod", 0.35))
	el.spring_side = str(item.get("spring_side", "none"))
	el.rod_mode = str(item.get("rod_mode", "single"))
	el.rod_end = str(item.get("rod_end", "plain"))
	el.brake = str(item.get("brake", "none"))
	el.port_cap = str(item.get("port_cap", "connect"))
	el.port_rod = str(item.get("port_rod", "connect"))
	el.carriage = str(item.get("carriage", "none"))
	el.bump_end = str(item.get("bump_end", "none"))
	el.mount = str(item.get("mount", "clevis"))
	el.guide = str(item.get("guide", "none"))
	el.seal_leak = float(item.get("seal_leak", 0.0))
	el.catalog_id = str(item.get("catalog_id", "generic"))
	el.variant_id = str(item.get("variant_id", "ppv"))
	el.cushion_mm = float(item.get("cushion_mm", 17.0))
	el.through_rod = bool(item.get("through_rod", false))
	el.body_style = str(item.get("body_style", "profile"))
	el.body_style_user = bool(item.get("body_style_user", false))
	el.order_code = str(item.get("order_code", ""))
	el.port_name = str(item.get("port_name", "G1/8"))
	el.fitting_id = str(item.get("fitting_id", ""))
	el.tube_od_mm = float(item.get("tube_od_mm", 0.0))
	el.tube_od_b_mm = float(item.get("tube_od_b_mm", 0.0))
	el.rod_thread = str(item.get("rod_thread", ""))
	if str(el.kind) == "cylinder":
		if el.fitting_id == "" or el.tube_od_mm < 1.0:
			TubeFit.conform_cylinder_fitting(el)
		else:
			TubeFit.apply_fitting(el, el.fitting_id)
	el.pressure_bar = float(item.get("pressure_bar", 6.0))
	el.temperature_c = float(item.get("temperature_c", 20.0))
	var wp = item.get("world_pos", Vector3.ZERO)
	if wp is Vector3:
		el.world_pos = wp
	else:
		el.world_pos = _json_vec3(wp)
	var wb = item.get("world_basis", null)
	if wb is Basis:
		el.world_basis = wb
	else:
		el.world_basis = _json_basis(wb)
	if item.has("auto_ground"):
		el.auto_ground = bool(item.get("auto_ground", true))
	el.valve_ways = int(item.get("valve_ways", 5))
	el.valve_positions = int(item.get("valve_positions", 2))
	el.valve_center = str(item.get("valve_center", "none"))
	el.valve_nc_no = str(item.get("valve_nc_no", "nc"))
	el.rest_pos = int(item.get("rest_pos", 0))
	el.valve_pos = int(item.get("valve_pos", 0))
	el.op_left = str(item.get("op_left", "solenoid_pilot"))
	el.op_right = str(item.get("op_right", "spring"))
	el.pilot_supply = str(item.get("pilot_supply", "internal"))
	el.valve_cv = float(item.get("valve_cv", 1.0))
	if str(el.kind) == "valve":
		ValveCat.conform_size(el)
	el.command_left = bool(item.get("command_left", false))
	el.command_right = bool(item.get("command_right", false))
	el.port_3 = str(item.get("port_3", "muffler"))
	# ПМ: port_5 = порт in (по умолчанию штуцер); у клапанов port_5 = выхлоп R2.
	if str(el.kind) == "air_motor":
		el.port_5 = str(item.get("port_5", "fitting"))
	else:
		el.port_5 = str(item.get("port_5", "muffler"))
	el.override_left = bool(item.get("override_left", true))
	el.override_right = bool(item.get("override_right", true))
	el.recipe_id = str(item.get("recipe_id", ""))
	el.spool_envelopes = PackedStringArray()
	var se = item.get("spool_envelopes", [])
	if se is Array or se is PackedStringArray:
		for x in se:
			el.spool_envelopes.append(str(x))
	el.port_mass = item.get("port_mass", {}).duplicate() if typeof(item.get("port_mass", {})) == TYPE_DICTIONARY else {}
	el.port_press = item.get("port_press", {}).duplicate() if typeof(item.get("port_press", {})) == TYPE_DICTIONARY else {}
	el.port_q = item.get("port_q", {}).duplicate() if typeof(item.get("port_q", {})) == TYPE_DICTIONARY else {}
	el.junction_style = str(item.get("junction_style", "tee"))
	el.junction_ports = int(item.get("junction_ports", 3))
	el.accessory_class = str(item.get("accessory_class", ""))
	el.opening = clampf(float(item.get("opening", 1.0)), 0.0, 1.0)
	if str(el.accessory_class) == "shutoff":
		AccLib.configure_shutoff_valve_ugo(el)
		# Цель из сохранённого valve_pos; opening — текущая поза анимации.
		el.valve_pos = clampi(int(item.get("valve_pos", 0)), 0, 1)
		if not item.has("opening"):
			el.opening = float(el.valve_pos)
	el.volume_l = maxf(float(item.get("volume_l", 1.0)), 0.05)
	el.reservoir_ports = clampi(int(item.get("reservoir_ports", 1)), 1, 5)
	el.set_pressure_bar = clampf(float(item.get("set_pressure_bar", 6.0)), 0.0, 16.0)
	el.regulator_unlocked = bool(item.get("regulator_unlocked", false))
	el.crack_pressure_bar = clampf(float(item.get("crack_pressure_bar", 0.2)), 0.01, 5.0)
	el.flow_nl_min = clampf(float(item.get("flow_nl_min", 600.0)), 10.0, 20000.0)
	el.rotary_class = str(item.get("rotary_class", ""))
	el.angle_max_deg = float(item.get("angle_max_deg", 180.0))
	el.torque_nm_at_6bar = float(item.get("torque_nm_at_6bar", 9.0))
	el.free_rpm = float(item.get("free_rpm", 0.0))
	el.angle = float(item.get("angle", 0.0))
	el.omega = float(item.get("omega", 0.0))
	if str(el.kind) == "rotary_cylinder":
		if el.rotary_class == "":
			el.rotary_class = "rack_pinion"
		RotaryCat.conform(el)
	if str(el.kind) == "air_motor":
		if el.rotary_class == "":
			el.rotary_class = "gear"
		MotorCat.conform(el)
	el.rail_domain = str(item.get("rail_domain", "electric"))
	el.rail_points = PackedVector2Array()
	var rp = item.get("rail_points", [])
	if rp is Array or rp is PackedVector2Array:
		for pt in rp:
			el.rail_points.append(_json_vec2(pt) if not (pt is Vector2) else pt)
	if el.rail_points.size() < 2 and str(el.kind) == "rail":
		el.rail_points = Rail2D.default_points()
	el.rail_taps = []
	var rt = item.get("rail_taps", [])
	if rt is Array:
		for tap in rt:
			if typeof(tap) == TYPE_DICTIONARY:
				el.rail_taps.append((tap as Dictionary).duplicate(true))
	el.rail_tap_seq = int(item.get("rail_tap_seq", 0))
	el.electro_class = str(item.get("electro_class", ""))
	el.electro_mount = str(item.get("electro_mount", "din"))
	el.tag_prefix = str(item.get("tag_prefix", "E"))
	el.lamp_color = str(item.get("lamp_color", "white"))
	el.btn_color = str(item.get("btn_color", "white"))
	el.caption = str(item.get("caption", ""))
	# Старые recipe lamp_white/red/... → одна позиция lamp (цвет уже в lamp_color).
	if el.recipe_id.begins_with("lamp_"):
		var legacy_c: String = el.recipe_id.substr(5)
		if legacy_c in ["white", "red", "green", "yellow"] and not item.has("lamp_color"):
			el.lamp_color = legacy_c
		el.recipe_id = "lamp"
		el.catalog_id = "lamp"
	if el.recipe_id in ["timer_on", "timer_off"]:
		el.recipe_id = "timer_relay"
		el.catalog_id = "timer_relay"
	# Старые АВ с номиналом в id → АВ 1P/2P/3P (класс/In уже в полях файла).
	if el.recipe_id.begins_with("mcb_1p") and el.recipe_id != "mcb_1p":
		el.recipe_id = "mcb_1p"
		el.catalog_id = "mcb_1p"
	elif el.recipe_id.begins_with("mcb_2p") and el.recipe_id != "mcb_2p":
		el.recipe_id = "mcb_2p"
		el.catalog_id = "mcb_2p"
	elif el.recipe_id.begins_with("mcb_3p") and el.recipe_id != "mcb_3p":
		el.recipe_id = "mcb_3p"
		el.catalog_id = "mcb_3p"
	# Старые УЗО/АВДТ → 1P+N / 3P+N.
	elif el.recipe_id.begins_with("rcd_2p") or el.recipe_id == "rcd_1pn":
		el.recipe_id = "rcd_1pn"
		el.catalog_id = "rcd_1pn"
	elif el.recipe_id.begins_with("rcd_4p") or el.recipe_id == "rcd_3pn":
		el.recipe_id = "rcd_3pn"
		el.catalog_id = "rcd_3pn"
	elif el.recipe_id.begins_with("rcbo_1p") or el.recipe_id == "rcbo_1pn":
		el.recipe_id = "rcbo_1pn"
		el.catalog_id = "rcbo_1pn"
	elif el.recipe_id.begins_with("rcbo_3p") or el.recipe_id == "rcbo_3pn":
		el.recipe_id = "rcbo_3pn"
		el.catalog_id = "rcbo_3pn"
	el.delay_on = float(item.get("delay_on", 0.0))
	el.delay_off = float(item.get("delay_off", 0.0))
	el.timer_mode = str(item.get("timer_mode", ""))
	el.timer_unit = int(item.get("timer_unit", 1))
	el.timer_value = float(item.get("timer_value", 0.0))
	el.poles = int(item.get("poles", 1))
	el.curve = str(item.get("curve", "C"))
	el.rating_a = float(item.get("rating_a", 16.0))
	el.i_delta_ma = float(item.get("i_delta_ma", 30.0))
	el.u_min = float(item.get("u_min", 180.0))
	el.u_max = float(item.get("u_max", 260.0))
	el.phase = str(item.get("phase", ""))
	el.voltage = float(item.get("voltage", 230.0))
	el.link_valve = bool(item.get("link_valve", false))
	el.group_template = str(item.get("group_template", ""))
	el.terminal_bus = bool(item.get("terminal_bus", false))
	el.color_id = str(item.get("color_id", ""))
	# Старые сцены без поля — порты 1/1b; новые элементы — нечёт/чёт.
	if item.has("terminal_port_scheme"):
		el.terminal_port_scheme = int(item.get("terminal_port_scheme", 2))
	elif str(item.get("electro_class", "")) == "terminal":
		el.terminal_port_scheme = 1
	else:
		el.terminal_port_scheme = 2
	# Переключатель — без отдельных членов группы (таблица на самом УГО).
	if str(el.electro_class) == "switch":
		el.group_template = ""
	el.electro_ports = item.get("electro_ports", []).duplicate(true) if typeof(item.get("electro_ports", [])) == TYPE_ARRAY else []
	el.coil_ports = PackedStringArray()
	var cp = item.get("coil_ports", [])
	if cp is Array or cp is PackedStringArray:
		for x in cp:
			el.coil_ports.append(str(x))
	el.contact_defs = item.get("contact_defs", []).duplicate(true) if typeof(item.get("contact_defs", [])) == TYPE_ARRAY else []
	el.switch_positions = maxi(int(item.get("switch_positions", 2)), 2)
	el.switch_pos = int(item.get("switch_pos", 0))
	el.switch_map = item.get("switch_map", []).duplicate(true) if typeof(item.get("switch_map", [])) == TYPE_ARRAY else []
	el.switch_labels = PackedStringArray()
	var sl = item.get("switch_labels", [])
	if sl is Array or sl is PackedStringArray:
		for x in sl:
			el.switch_labels.append(str(x))
	# УЗО/АВДТ: полюса и порты 1…2n; старые N/N2 → нумерация + remap проводов.
	if str(el.electro_class) in ["rcd", "rcbo"]:
		_migrate_diff_breaker_element(el)
	el.energized = bool(item.get("energized", false))
	el.pressed = bool(item.get("pressed", false))
	el.latching = bool(item.get("latching", str(item.get("electro_class", "")) == "e_stop"))
	# АВ/УЗО/АВДТ без явного closed в файле — OFF (как новые из каталога).
	var cls_load: String = str(item.get("electro_class", ""))
	var closed_default: bool = false if cls_load in ["mcb", "rcd", "rcbo"] else true
	el.closed = bool(item.get("closed", closed_default))
	el.lit = bool(item.get("lit", false))
	el.timer_armed = bool(item.get("timer_armed", false))
	el.timer_elapsed = float(item.get("timer_elapsed", 0.0))
	el.detached = bool(item.get("detached", false))
	el.hide_unused_contacts = bool(item.get("hide_unused_contacts", false))
	el.member_role = str(item.get("member_role", "device"))
	el.member_index = int(item.get("member_index", 0))
	el.group_id = int(item.get("group_id", -1))
	el.group_tag = str(item.get("group_tag", ""))
	el.linked_valve_side = str(item.get("linked_valve_side", ""))
	el.din_slot = int(item.get("din_slot", -1))
	el.door_slot = int(item.get("door_slot", -1))
	el.door_xy = _json_vec2(item.get("door_xy", Vector2(-1, -1)))
	el.sensor_class = str(item.get("sensor_class", ""))
	el.sensor_active = bool(item.get("sensor_active", true))
	el.sense_range_mm = float(item.get("sense_range_mm", 4.0))
	el.hysteresis_mm = float(item.get("hysteresis_mm", 0.4))
	el.body_od_mm = float(item.get("body_od_mm", 12.0))
	el.supply_mode = SensorSig.normalize_supply(str(item.get("supply_mode", "24dc")))
	el.output_type = SensorSig.normalize_output(str(item.get("output_type", "npn")))
	el.contact_form = SensorSig.normalize_form(str(item.get("contact_form", "no")))
	el.detect_material = str(item.get("detect_material", ""))
	el.sensor_powered = bool(item.get("sensor_powered", false))
	el.sensor_target = bool(item.get("sensor_target", false))
	el.analog_kind = str(item.get("analog_kind", ""))
	el.wire_scheme = clampi(int(item.get("wire_scheme", 3)), 2, 4)
	el.analog_value = float(item.get("analog_value", 0.0))
	el.input_expect = str(item.get("input_expect", "any"))
	if str(el.kind) == "sensor":
		if el.sensor_class == "":
			el.sensor_class = "inductive"
		if str(el.recipe_id) != "":
			SensorLib.apply_recipe(el, str(el.recipe_id))
			# Не затирать сохранённые overrides после recipe.
			if item.has("sense_range_mm"):
				el.sense_range_mm = float(item.get("sense_range_mm", el.sense_range_mm))
			if item.has("output_type"):
				el.output_type = SensorSig.normalize_output(str(item.get("output_type", el.output_type)))
			if item.has("contact_form"):
				el.contact_form = SensorSig.normalize_form(str(item.get("contact_form", el.contact_form)))
			if item.has("supply_mode"):
				el.supply_mode = SensorSig.normalize_supply(str(item.get("supply_mode", el.supply_mode)))
			if item.has("body_od_mm"):
				el.body_od_mm = float(item.get("body_od_mm", el.body_od_mm))
		elif str(el.sensor_class) == "inductive":
			SensorCat.conform_inductive(el)
	if str(el.electro_class) == "switch":
		ElectroLib.ensure_switch(el)
	if str(el.electro_class) == "e_stop":
		el.btn_color = "red"
		el.latching = true
	# 48 В у катушек больше не предлагаем — старые сцены → 24 В.
	if str(el.electro_class) in ["relay", "timer_relay", "contactor", "solenoid_coil", "voltage_relay"]:
		if absf(float(el.voltage) - 48.0) < 0.5:
			el.voltage = 24.0
	if str(el.electro_class) == "timer_relay" and str(el.member_role) != "contact":
		ElectroLib.normalize_timer_relay(el)
	return el


func _register(el: Element) -> void:
	el.id = _next_id
	_next_id += 1
	elements.append(el)
	invalidate_element_index()


## OD трубки для новой связи: согласованные ограничения портов или 0 при конфликте.
func _resolve_tube_od_for_link(a: Element, a_port: String, b: Element, b_port: String) -> float:
	var oa: float = TubeFit.port_tube_od(a, a_port)
	var ob: float = TubeFit.port_tube_od(b, b_port)
	if oa >= 1.0 and ob >= 1.0 and absf(oa - ob) > 0.15:
		return 0.0
	if oa >= 1.0:
		return oa
	if ob >= 1.0:
		return ob
	return 6.0


## После смены фитинга/типоразмера — обновить OD трубок на портах элемента.
func _sync_wires_od_from_port_el(el: Element) -> void:
	if el == null:
		return
	var kind: String = str(el.kind)
	if kind != "cylinder" and kind != "valve" and kind != "junction" and kind != "accessory":
		return
	var is_adapter: bool = kind == "junction" and str(el.junction_style) == "adapter"
	for w in wires:
		if w == null:
			continue
		var on_a: bool = int(w.a_id) == int(el.id)
		var on_b: bool = int(w.b_id) == int(el.id)
		if not on_a and not on_b:
			continue
		var my_port: String = str(w.a_port) if on_a else str(w.b_port)
		var od: float = TubeFit.port_tube_od(el, my_port)
		if od < 1.0:
			continue
		var other_id: int = int(w.b_id) if on_a else int(w.a_id)
		var other_port: String = str(w.b_port) if on_a else str(w.a_port)
		var other = get_element(other_id)
		var o_od: float = TubeFit.port_tube_od(other, other_port)
		if (not is_adapter) and o_od >= 1.0 and absf(o_od - od) > 0.15:
			notify("Трубка к %s: конфликт Ø — нужен переходник (оставлен прежний Ø)." % str(el.tag))
			continue
		TubeFit.apply_tube_od_to_wire(w, od)


## Совместимость со старыми вызовами.
func _sync_wires_od_from_cylinder(el: Element) -> void:
	_sync_wires_od_from_port_el(el)


func retune_geometry(el: Element) -> String:
	if el.kind == "valve":
		var note: String = ValveCat.conform(el)
		_ensure_valve_ports(el)
		_drop_invalid_wires(el)
		_sync_wires_od_from_port_el(el)
		return note
	if el.kind == "rotary_cylinder":
		RotaryCat.conform(el)
		el.angle = clampf(el.angle, 0.0, deg_to_rad(float(el.angle_max_deg)))
		var rv: Dictionary = _rotary_chamber_vols(el)
		for pname in ["a", "b"]:
			var vol_r: float = float(rv[pname])
			var p_r: float = float(el.port_press.get(pname, ATM))
			el.port_mass[pname] = maxf(p_r, 2000.0) * vol_r / (R_AIR * gas_t)
			el.port_press[pname] = p_r
		_sync_wires_od_from_port_el(el)
		_drop_invalid_wires(el)
		return "ППЦ ∅%.0f · %.0f° · M@6бар %.1f Н·м" % [
			float(el.bore_mm), float(el.angle_max_deg), float(el.torque_nm_at_6bar),
		]
	if el.kind == "air_motor":
		MotorCat.conform(el)
		var mvol: float = MotorCat.port_vol_m3(el)
		for pname in ["in", "exhaust"]:
			var p_m: float = float(el.port_press.get(pname, ATM))
			el.port_mass[pname] = maxf(p_m, 2000.0) * mvol / (R_AIR * gas_t)
			el.port_press[pname] = p_m
		_sync_wires_od_from_port_el(el)
		_drop_invalid_wires(el)
		return "ПМ stall %.2f Н·м · %.0f об/мин · %s" % [
			float(el.torque_nm_at_6bar), float(el.free_rpm), str(el.port_name),
		]
	if el.kind != "cylinder":
		return ""
	var notes: PackedStringArray = []
	var catalog_note: String = Catalog.conform(el)
	if catalog_note != "":
		notes.append(catalog_note)
	var fit_note: String = TubeFit.conform_cylinder_fitting(el)
	if fit_note != "":
		notes.append(fit_note)
	_sync_wires_od_from_port_el(el)
	el.load_n = clampf(el.load_n, -20000.0, 20000.0)
	var pcap := el.p_cap
	var prod := el.p_rod
	# В покое: пружина в бесштоковой → шток выдвинут; пружина в штоковой → втянут.
	if not running:
		if el.action == "spring_extend":
			el.x = _stroke_m(el)
		elif el.action == "spring_return":
			el.x = 0.0
		else:
			el.x = clampf(el.x, 0.0, _stroke_m(el))
	else:
		el.x = clampf(el.x, 0.0, _stroke_m(el))
	_write_channel(el, "cap", pcap)
	_write_channel(el, "rod", prod)
	_ensure_cylinder_aux_ports(el)
	_drop_invalid_wires(el)
	return " ".join(notes)


func retune_source(el: Element) -> String:
	var notes: PackedStringArray = []
	var pressure := clampf(el.pressure_bar, 0.0, 16.0)
	if absf(pressure - el.pressure_bar) > 0.001:
		notes.append("Давление источника ограничено диапазоном 0…16 бар.")
	el.pressure_bar = pressure
	var temp := clampf(el.temperature_c, -20.0, 80.0)
	if absf(temp - el.temperature_c) > 0.01:
		notes.append("Температура ограничена диапазоном −20…80 °C.")
	el.temperature_c = temp
	return " ".join(notes)


func reconfigure_action(el: Element) -> void:
	_init_state(el, true)
	_drop_invalid_wires(el)


func retune_wire(wire: Wire) -> void:
	var ea := get_element(int(wire.a_id))
	var is_elec: bool = ea != null and port_domain(ea, str(wire.a_port)) == "electric"
	if is_elec:
		var sizes: Array = wire_section_catalog()
		var best: float = float(sizes[0])
		var best_d: float = absf(float(wire.id_mm) - best)
		for s in sizes:
			var d: float = absf(float(wire.id_mm) - float(s))
			if d < best_d:
				best_d = d
				best = float(s)
		wire.id_mm = best
	else:
		var od_cur: float = float(wire.od_mm)
		if od_cur < 1.0:
			od_cur = float(wire.id_mm)
		TubeFit.apply_tube_od_to_wire(wire, od_cur)
	wire.color_id = str(wire.color_id)
	var p := wire.pressure
	_init_wire(wire)
	if wire.vol > 0.0:
		wire.mass = p * wire.vol / (R_AIR * gas_t)
		wire.pressure = p
	_touch_scene()


func _drop_invalid_wires(el: Element) -> void:
	var kept: Array = []
	for wire in wires:
		var drop := false
		if wire.a_id == el.id and Geom.port_by_name(el, wire.a_port).is_empty():
			drop = true
		if wire.b_id == el.id and Geom.port_by_name(el, wire.b_port).is_empty():
			drop = true
		if not drop:
			kept.append(wire)
		elif selected_wire_id == wire.id:
			selected_wire_id = -1
	if kept.size() != wires.size():
		wires = kept
		renumber_wires()
	else:
		wires = kept


func reset_simulation() -> void:
	# Сброс состояния; остаёмся на паузе (физика не тикает).
	running = false
	sim_time = 0.0
	_viz_max_over_smooth = 0.0
	gas_t = _mean_source_temperature()
	for el in elements:
		_init_state(el, true)
	for wire in wires:
		_init_wire(wire)
	scene_changed.emit()


func _reset_electro_state(el: Element) -> void:
	if el == null or str(el.kind) != "electro":
		return
	var cls: String = str(el.electro_class)
	el.energized = false
	el.pressed = false
	el.lit = false
	el.timer_armed = false
	el.timer_elapsed = 0.0
	el.switch_pos = 0
	# АВ/УЗО/АВДТ — в OFF; прочие силовые контакты не держат «замкнуто» после сброса.
	if cls in ["mcb", "rcd", "rcbo"]:
		el.closed = false
	elif cls in ["contactor", "relay", "timer_relay", "thermal", "voltage_relay", "button", "e_stop", "switch", "lamp"]:
		# Катушки/кнопки — обесточены; closed у АВ уже сброшен выше.
		pass


## Старые УЗО/АВДТ с портами N/N2 → нумерация 1…2n; remap проводов в meta.
func _migrate_diff_breaker_element(el: Element) -> void:
	var rid: String = str(el.recipe_id)
	if rid in ["rcd_1pn", "rcbo_1pn"]:
		el.poles = 2
	elif rid in ["rcd_3pn", "rcbo_3pn"]:
		el.poles = 4
	else:
		el.poles = clampi(maxi(int(el.poles), 2), 2, 4)
	var has_legacy: bool = false
	for p in el.electro_ports:
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) in ["N", "N2"]:
			has_legacy = true
			break
	var need_n: int = int(el.poles) * 2
	if has_legacy:
		var remap: Dictionary = {}
		if rid == "rcd_1pn":
			# Было L слева (1/2), N справа → N слева (1/2), L справа (3/4).
			remap = {"1": "3", "2": "4", "N": "1", "N2": "2"}
		elif rid == "rcbo_1pn":
			remap = {"N": "3", "N2": "4"}
		elif rid == "rcd_3pn":
			remap = {"1": "3", "2": "4", "3": "5", "4": "6", "5": "7", "6": "8", "N": "1", "N2": "2"}
		elif rid == "rcbo_3pn":
			remap = {"N": "7", "N2": "8"}
		if not remap.is_empty():
			el.set_meta("diff_port_remap", remap)
	if has_legacy or el.electro_ports.size() != need_n:
		var rec: Dictionary = ElectroLib.recipe(rid)
		if not rec.is_empty():
			var ports_v: Variant = rec.get("ports", [])
			if typeof(ports_v) == TYPE_ARRAY:
				el.electro_ports = (ports_v as Array).duplicate(true)


func _apply_diff_breaker_wire_remaps() -> void:
	for el in elements:
		if el == null or not el.has_meta("diff_port_remap"):
			continue
		var remap: Dictionary = el.get_meta("diff_port_remap") as Dictionary
		for wire in wires:
			if wire == null:
				continue
			if int(wire.a_id) == int(el.id) and remap.has(str(wire.a_port)):
				wire.a_port = str(remap[str(wire.a_port)])
			if int(wire.b_id) == int(el.id) and remap.has(str(wire.b_port)):
				wire.b_port = str(remap[str(wire.b_port)])
		el.remove_meta("diff_port_remap")


func _init_state(el: Element, to_rest: bool) -> void:
	if el.kind == "valve":
		_ensure_valve_ports(el)
		if to_rest:
			el.valve_pos = int(el.rest_pos)
			el.command_left = false
			el.command_right = false
			var vvol: float = _valve_port_vol(el)
			for vname in ValveCat.port_names(el):
				el.port_press[vname] = ATM
				el.port_mass[vname] = ATM * vvol / (R_AIR * gas_t)
				el.port_q[vname] = 0.0
		return
	if el.kind == "accessory":
		_ensure_accessory_ports(el)
		if to_rest:
			# Иначе после Reset в штуцерах остаётся 6 бар → мгновенный удар в пустые трубки/ПЦ.
			var avol: float = _accessory_port_vol(el)
			for aname in AccLib.port_names(el):
				el.port_press[aname] = ATM
				el.port_mass[aname] = ATM * avol / (R_AIR * gas_t)
				el.port_q[aname] = 0.0
			# Подвижные части — в покой (давлений нет). Дроссель/уставку не трогаем.
			var acls: String = str(el.accessory_class)
			match acls:
				"check":
					el.opening = 0.0
				"shutoff":
					el.valve_pos = 0
					el.opening = 0.0
				"and_valve":
					el.opening = 0.5
				"shuttle":
					el.opening = 0.5
				"quick_exhaust":
					# Без питания тарелка к входу — путь 2→3 (выхлоп).
					el.opening = 0.0
				"relief":
					el.opening = 0.0
					el.pressed = false
		return
	if el.kind == "rail":
		Rail2D.ensure_points(el)
		el.rail_taps = []
		return
	if el.kind == "junction":
		var vol := _junction_vol(el)
		el.p_cap = ATM
		el.m_cap = ATM * vol / (R_AIR * gas_t)
		el.p_rod = ATM
		el.m_rod = 0.0
		return
	if el.kind == "electro":
		if to_rest:
			_reset_electro_state(el)
		el.p_cap = ATM
		el.p_rod = ATM
		return
	if el.kind == "rotary_cylinder":
		if to_rest:
			el.angle = 0.0
			el.omega = 0.0
		el.angle = clampf(el.angle, 0.0, deg_to_rad(float(el.angle_max_deg)))
		var rv: Dictionary = _rotary_chamber_vols(el)
		for pname in ["a", "b"]:
			var vol_r: float = float(rv[pname])
			var p_r: float = ATM if to_rest else float(el.port_press.get(pname, ATM))
			el.port_press[pname] = p_r
			el.port_mass[pname] = maxf(p_r, 2000.0) * vol_r / (R_AIR * gas_t)
			el.port_q[pname] = 0.0
		el.p_cap = float(el.port_press.get("a", ATM))
		el.p_rod = float(el.port_press.get("b", ATM))
		return
	if el.kind == "air_motor":
		if to_rest:
			el.angle = 0.0
			el.omega = 0.0
		var mvol: float = MotorCat.port_vol_m3(el)
		for pname in ["in", "exhaust"]:
			var p_m: float = ATM if to_rest else float(el.port_press.get(pname, ATM))
			el.port_press[pname] = p_m
			el.port_mass[pname] = maxf(p_m, 2000.0) * mvol / (R_AIR * gas_t)
			el.port_q[pname] = 0.0
		el.p_cap = float(el.port_press.get("in", ATM))
		el.p_rod = float(el.port_press.get("exhaust", ATM))
		return
	if el.kind == "sensor":
		if to_rest:
			# Покой: выход разомкнут, LED выкл; питание/цель пересчитаются при Play.
			el.pressed = false
			el.lit = false
			el.sensor_target = false
			el.sensor_powered = false
		el.p_cap = ATM
		el.p_rod = ATM
		return
	if el.kind != "cylinder":
		el.p_cap = ATM
		el.p_rod = ATM
		return
	if to_rest:
		el.v = 0.0
		el.x = _stroke_m(el) if el.action == "spring_extend" else 0.0
		el.q_cap = 0.0
		el.q_rod = 0.0
	el.x = clampf(el.x, 0.0, _stroke_m(el))
	_write_channel(el, "cap", ATM if to_rest else el.p_cap)
	_write_channel(el, "rod", ATM if to_rest else el.p_rod)
	_ensure_cylinder_aux_ports(el)


func defer_step_once() -> void:
	_skip_step_once = true


func step(frame_dt: float) -> void:
	if _skip_step_once:
		_skip_step_once = false
		_perf_ms_step = 0.0
		return
	var total := maxf(frame_dt, 0.0) * speed
	if total <= 0.0:
		return
	var t0: int = Time.get_ticks_usec()
	_adopt_temperature()
	# Индексы — только если грязные (не полный rebuild каждый кадр).
	if _element_index_dirty:
		_rebuild_element_index()
	if _port_wire_index_dirty:
		_rebuild_port_wire_index()
	_rebuild_sim_active()
	_cache_wire_hydraulics()
	# Порты клапанов/арматуры — один раз за кадр, не в каждом субшаге.
	_ensure_active_ports()
	# Датчики: hit-тест зон (до электрики — pressed/LED).
	if _scene_has_sensors():
		SensorDetect.step(self)
	# Электрическая сеть — электро и/или датчики с электропортами.
	if _scene_has_electro():
		ElecNet.step(self, total)
	# Активная сложность (связанная пневмосеть), не вся галерея элементов.
	var complexity: int = _sim_active_els.size() + _pneumo_wire_count() * 2
	var h := 0.0010 if complexity > 18 else 0.0006
	var max_n := 20 if complexity > 36 else (28 if complexity > 18 else 40)
	# Крупные схемы: меньше субшагов — тот же суммарный dt, стабильный FPS.
	if complexity > 80:
		max_n = mini(max_n, 6)
	elif complexity > 50:
		max_n = mini(max_n, 8)
	elif complexity > 30:
		max_n = mini(max_n, 12)
	# Адаптивно под бюджет кадра (~16 ms @ 60 FPS): step целимся ≤ ~5–6 ms.
	if _perf_ms_step > 8.0:
		max_n = mini(max_n, 3)
	elif _perf_ms_step > 6.0:
		max_n = mini(max_n, 4)
	elif _perf_ms_step > 4.5:
		max_n = mini(max_n, 6)
	var n := clampi(int(ceil(total / h)), 1, max_n)
	h = total / float(n)
	_relief_latch.clear()
	for _i in n:
		_substep(h)
	for eid in _relief_latch.keys():
		relief_trail_s[int(eid)] = 0.55
	_relief_latch.clear()
	_tick_regulator_relief_trail(total)
	_tick_shutoff_animation(total)
	_refresh_accessory_port_viz_q()
	_advance_wire_flow_phase(total)
	sim_time += total
	_smooth_wire_pressure_vis()
	_update_viz_max_over_smooth()
	_perf_ms_step = float(Time.get_ticks_usec() - t0) * 0.001


func _scene_has_electro() -> bool:
	if _has_electro_dirty:
		_has_electro_cached = false
		for el in elements:
			if el == null:
				continue
			if str(el.kind) == "electro" or str(el.kind) == "sensor":
				_has_electro_cached = true
				break
		_has_electro_dirty = false
	return _has_electro_cached


func _scene_has_sensors() -> bool:
	for el in elements:
		if el != null and str(el.kind) == "sensor":
			return true
	return false


func _pneumo_wire_count() -> int:
	var n: int = 0
	for wire in wires:
		if wire == null:
			continue
		var ea = get_element(int(wire.a_id))
		if ea != null and port_domain(ea, str(wire.a_port)) != "electric":
			n += 1
	return n


func _rebuild_sim_active() -> void:
	_sim_active_els.clear()
	for wire in wires:
		if wire == null:
			continue
		var ea = get_element(int(wire.a_id))
		var eb = get_element(int(wire.b_id))
		if ea != null and port_domain(ea, str(wire.a_port)) == "electric":
			continue
		if ea != null:
			_sim_active_els[int(ea.id)] = true
		if eb != null:
			_sim_active_els[int(eb.id)] = true


func _cache_wire_hydraulics() -> void:
	_wire_vol_frame.clear()
	_wire_area_frame.clear()
	for wire in wires:
		if wire == null:
			continue
		var ea = get_element(int(wire.a_id))
		if ea != null and port_domain(ea, str(wire.a_port)) == "electric":
			continue
		var wid: int = int(wire.id)
		var vol: float = _wire_volume(wire)
		wire.vol = vol
		_wire_vol_frame[wid] = vol
		_wire_area_frame[wid] = _tube_area(wire)


func _ensure_active_ports() -> void:
	for el_id in _sim_active_els.keys():
		var el = get_element(int(el_id))
		if el == null:
			continue
		match str(el.kind):
			"valve":
				_ensure_valve_ports(el)
			"accessory":
				_ensure_accessory_ports(el)
			"cylinder":
				_ensure_cylinder_aux_ports(el)


func has_electro() -> bool:
	return _scene_has_electro()


## Элемент участвует в пневмо-шаге (есть провод). Вне Run — всегда true для UI.
func is_sim_active(el_id: int) -> bool:
	if not running:
		return true
	return _sim_active_els.has(int(el_id))


func electro_group_members(group_id: int) -> Array:
	var out: Array = []
	for el in elements:
		if str(el.kind) == "electro" and int(el.group_id) == group_id:
			out.append(el)
	return out


func update_electro_detach(el: Element) -> void:
	if el == null or str(el.kind) != "electro":
		return
	var role: String = str(el.member_role)
	if role != "contact" and role != "supply_leg":
		return
	var primary = get_element(int(el.group_id))
	if primary == null:
		return
	# Ноги ввода N/PE — столбик под базой L; сама L неотделима.
	if role == "supply_leg" and str(primary.electro_class) == "supply":
		if ElectroLib.is_supply_fixed_leg(self, el):
			el.detached = false
			ElectroLib.layout_supply_legs(self, primary)
			return
		var sang: float = float(primary.rotation_quad) * PI * 0.5
		var slocal: Vector2 = (el.position - primary.position).rotated(-sang)
		# Колонка под L: |dx| мал и y ниже ряда базы.
		var inside_s: bool = (
			absf(slocal.x) <= Geom.SCH_GRID * 1.5
			and slocal.y >= ElectroSymbols.ROW_H * 0.5 - 2.0
		)
		if not inside_s and not el.detached:
			el.detached = true
			renumber_tags()
			_touch_scene()
		elif inside_s and el.detached:
			el.detached = false
			ElectroLib.layout_supply_legs(self, primary)
			renumber_tags()
			_touch_scene()
		elif inside_s and not el.detached:
			ElectroLib.layout_supply_legs(self, primary)
		return
	var is_btn: bool = str(primary.electro_class) in ["button", "e_stop"]
	if is_btn:
		# Первый контакт кнопки неотделим — всегда столбик под актуатором.
		if ElectroLib.is_button_fixed_contact(self, el):
			el.detached = false
			ElectroLib.layout_button_contacts(self, primary)
			return
		# Остальные: «на линии» в локальных координатах primary (столбик с учётом поворота).
		var ang: float = float(primary.rotation_quad) * PI * 0.5
		var local: Vector2 = (el.position - primary.position).rotated(-ang)
		var inside: bool = absf(local.x) <= Geom.SCH_GRID * 1.5 and local.y >= -5.0
		if not inside and not el.detached:
			el.detached = true
			renumber_tags()
			_touch_scene()
		elif inside and el.detached:
			el.detached = false
			ElectroLib.layout_button_contacts(self, primary)
			renumber_tags()
			_touch_scene()
		elif inside and not el.detached:
			ElectroLib.layout_button_contacts(self, primary)
		return
	# Катушка/КМ/KK: столбик под нижней гранью (как кнопка), иначе — старая рамка.
	if str(primary.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		var cang: float = float(primary.rotation_quad) * PI * 0.5
		var clocal: Vector2 = (el.position - primary.position).rotated(-cang)
		var inside_col: bool = absf(clocal.x) <= Geom.SCH_GRID * 1.5 and clocal.y >= ElectroSymbols.coil_body_bottom(primary) - 2.0
		if not inside_col and not el.detached:
			el.detached = true
			renumber_tags()
			_touch_scene()
		elif inside_col and el.detached:
			el.detached = false
			ElectroLib.layout_coil_contacts(self, primary)
			renumber_tags()
			_touch_scene()
		elif inside_col and not el.detached:
			ElectroLib.layout_coil_contacts(self, primary)
		return
	# Не включать сам контакт в рамку — иначе она растёт при drag.
	var frame := Geom.electro_group_frame(self, int(el.group_id), true, int(el.id))
	if frame.size.x < 1.0:
		return
	var center := el.position
	var inside: bool = frame.grow(6.0).has_point(center)
	if not inside and not el.detached:
		el.detached = true
		renumber_tags()
		_touch_scene()
	elif inside and el.detached:
		el.detached = false
		renumber_tags()
		_touch_scene()


func _ensure_accessory_ports(el: Element) -> void:
	var vol := _accessory_port_vol(el)
	var names := AccLib.port_names(el)
	for name in names:
		if not el.port_mass.has(name):
			el.port_mass[name] = ATM * vol / (R_AIR * gas_t)
		if not el.port_press.has(name):
			el.port_press[name] = ATM
		if not el.port_q.has(name):
			el.port_q[name] = 0.0
	var drop: Array = []
	for key in el.port_mass.keys():
		if names.find(str(key)) < 0:
			drop.append(str(key))
			el.port_mass.erase(key)
			el.port_press.erase(key)
			el.port_q.erase(key)
	# Снятые бобышки ресивера — убрать провода с этих портов.
	if str(el.accessory_class) == "reservoir" and not drop.is_empty():
		var rm: Array = []
		for w in wires:
			if w == null:
				continue
			if int(w.a_id) == int(el.id) and drop.has(str(w.a_port)):
				rm.append(int(w.id))
			elif int(w.b_id) == int(el.id) and drop.has(str(w.b_port)):
				rm.append(int(w.id))
		for wid in rm:
			remove_wire(int(wid))


func _ensure_rail_ports(el: Element) -> void:
	var vol: float = 2.0e-5
	var names: PackedStringArray = PackedStringArray()
	for p in Geom.ports(el):
		names.append(str(p["name"]))
	for name in names:
		if not el.port_mass.has(name):
			el.port_mass[name] = ATM * vol / (R_AIR * gas_t)
		if not el.port_press.has(name):
			el.port_press[name] = ATM
		if not el.port_q.has(name):
			el.port_q[name] = 0.0
	for key in el.port_mass.keys():
		if names.find(str(key)) < 0:
			el.port_mass.erase(key)
			el.port_press.erase(key)
			el.port_q.erase(key)


func _rail_internal_flow(el: Element, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, acc: Dictionary, h: float) -> void:
	# Все отводы пневмошины — один объём.
	var keys: Array = []
	for p in Geom.ports(el):
		var k := "c:%d:%s" % [el.id, str(p["name"])]
		if pmap.has(k):
			keys.append(k)
	if keys.size() < 2:
		return
	var area: float = 4.0e-6
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var e1 := {"key": str(keys[i]), "p": pmap[keys[i]]}
			var e2 := {"key": str(keys[j]), "p": pmap[keys[j]]}
			_pour(e1, e2, area, acc, pmap, mmap, vols, h)


func _accessory_port_vol(el: Element) -> float:
	if str(el.accessory_class) == "reservoir":
		# Литры → м³; делим на число бобышек (общий объём через сильный обмен).
		var n: int = clampi(int(el.reservoir_ports), 1, 5)
		return maxf(float(el.volume_l), 0.05) * 0.001 / float(n)
	# Чуть больше мёртвый объём штуцера — меньше жёсткий ring после остановки ПЦ.
	return 2.2e-5


func accessory_area(el: Element) -> float:
	var open := clampf(float(el.opening), 0.0, 1.0)
	var base := 1.2e-6 * clampf(float(el.valve_cv), 0.2, 4.0)
	match str(el.accessory_class):
		"throttle", "throttle_check":
			# Полностью закрыт — герметично (иначе «утечка» на свободном порту и сдув запертой линии).
			# У throttle_check это площадь дросселя 1→2; обводной КО считает отдельно.
			if open < 0.02:
				return 0.0
			return base * open * open
		"throttle_fixed", "throttle_check_fixed":
			# Фиксированное сечение ≈ opening из рецепта.
			return base * maxf(open * open, 0.08)
		"check":
			# Площадь из каталожного Qn (Nl/мин @ 6→5 бар), база G1/8 = 600.
			var qn: float = clampf(float(el.flow_nl_min), 10.0, 20000.0)
			return base * clampf(qn / 600.0, 0.15, 8.0)
		"shuttle":
			# Festo OS: Qn @ 6→5 бар, база G1/4 ≈ 1170.
			var qn_s: float = clampf(float(el.flow_nl_min), 50.0, 20000.0)
			return base * clampf(qn_s / 1170.0, 0.25, 8.0)
		"and_valve":
			# Dual-pressure / AND: Qn @ 6→5 бар, база G1/4 ≈ 1000.
			var qn_a: float = clampf(float(el.flow_nl_min), 50.0, 20000.0)
			return base * clampf(qn_a / 1000.0, 0.25, 8.0)
		"quick_exhaust":
			# Festo SE: Qn 1→2 @ 6→5 бар, база SE-1/4 = 960.
			var qn_q: float = clampf(float(el.flow_nl_min), 50.0, 20000.0)
			return base * clampf(qn_q / 960.0, 0.25, 10.0)
		"shutoff":
			# Festo QH: площадь ~ cos²(угол); opening 1=открыт. База QH-QS-6 = 533.
			if open < 0.02:
				return 0.0
			var qn_z: float = clampf(float(el.flow_nl_min), 50.0, 20000.0)
			return base * clampf(qn_z / 533.0, 0.2, 8.0) * open * open
		"regulator", "frl":
			# Пропускная способность ближе к каталожному Qn (база G1/4 ≈ 1400).
			var qn_r: float = clampf(float(el.flow_nl_min), 50.0, 20000.0)
			return base * clampf(qn_r / 700.0, 0.5, 10.0)
		"reservoir":
			return base * 4.0
		_:
			return base


func _accessory_internal_flow(el: Element, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, acc: Dictionary, h: float) -> void:
	var area := accessory_area(el)
	var cls := str(el.accessory_class)
	if cls == "reservoir":
		# Все бобышки — один объём: сильный обмен попарно.
		var keys_r: Array = []
		for pname in AccLib.port_names(el):
			var kr: String = "c:%d:%s" % [el.id, str(pname)]
			if pmap.has(kr):
				keys_r.append(kr)
		if keys_r.size() >= 2:
			for i in keys_r.size():
				for j in range(i + 1, keys_r.size()):
					var ra := {"key": str(keys_r[i]), "p": pmap[keys_r[i]]}
					var rb := {"key": str(keys_r[j]), "p": pmap[keys_r[j]]}
					_pour(ra, rb, area * 8.0, acc, pmap, mmap, vols, h)
		return
	if cls == "shuttle":
		_accessory_shuttle_flow(el, area, acc, pmap, mmap, vols, h)
		return
	if cls == "and_valve":
		_accessory_and_flow(el, area, acc, pmap, mmap, vols, h)
		return
	if cls == "quick_exhaust":
		_accessory_quick_exhaust_flow(el, area, acc, pmap, mmap, vols, h)
		return
	if cls == "relief":
		_accessory_relief_flow(el, area, acc, pmap, mmap, vols, h)
		return
	var k1 := "c:%d:1" % el.id
	var k2 := "c:%d:2" % el.id
	if not pmap.has(k1) or not pmap.has(k2):
		return
	var e1 := {"key": k1, "p": pmap[k1]}
	var e2 := {"key": k2, "p": pmap[k2]}
	match cls:
		"throttle", "throttle_fixed", "shutoff":
			_pour(e1, e2, area, acc, pmap, mmap, vols, h)
		"check":
			# Седло = порт 1. Пружина к седлу; открытие непрерывно по (p1−p2)−crack.
			# Неподключённый порт = ATM.
			var p1: float = float(e1["p"])
			var p2: float = float(e2["p"])
			var open1: bool = wire_on(el.id, "1") == null
			var open2: bool = wire_on(el.id, "2") == null
			var avol_chk: float = _accessory_port_vol(el)
			var m_atm_chk: float = ATM * avol_chk / (R_AIR * gas_t)
			if open1:
				p1 = ATM
				el.port_press["1"] = ATM
				el.port_mass["1"] = m_atm_chk
				pmap[k1] = ATM
				mmap[k1] = m_atm_chk
				e1 = {"key": k1, "p": ATM}
			if open2:
				p2 = ATM
				el.port_press["2"] = ATM
				el.port_mass["2"] = m_atm_chk
				pmap[k2] = ATM
				mmap[k2] = m_atm_chk
				e2 = {"key": k2, "p": ATM}
			# crack + ход пружины (~0.3 бар) до полного открытия — без бинарного щелчка.
			var spring_pa: float = clampf(float(el.crack_pressure_bar), 0.01, 5.0) * 1.0e5
			var travel_pa: float = 0.30e5
			var dp: float = p1 - p2
			el.opening = clampf((dp - spring_pa) / travel_pa, 0.0, 1.0)
			if float(el.opening) > 1.0e-4:
				var flow_area: float = area * float(el.opening)
				if open2:
					_pour(e1, {"key": "", "p": ATM}, flow_area, acc, pmap, mmap, vols, h)
				elif not open1:
					_pour(e1, e2, flow_area, acc, pmap, mmap, vols, h)
		"throttle_check", "throttle_check_fixed":
			# 1→2 — дроссель (area от opening); 2→1 — обводной КО (не зависит от винта).
			_accessory_throttle_check_flow(el, e1, e2, area, acc, pmap, mmap, vols, h)
		"regulator", "frl":
			_accessory_regulator_flow(el, e1, e2, area, acc, pmap, mmap, vols, h)
		_:
			_pour(e1, e2, area, acc, pmap, mmap, vols, h)


## Дроссель с ОК: 1→2 через сечение дросселя; 2→1 через шар (crack), винт не глушит обратку.
func _accessory_throttle_check_flow(
	el: Element, e1: Dictionary, e2: Dictionary, thr_area: float,
	acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float
) -> void:
	var k1 := str(e1.get("key", ""))
	var k2 := str(e2.get("key", ""))
	var p1: float = float(e1["p"])
	var p2: float = float(e2["p"])
	var open1: bool = wire_on(el.id, "1") == null
	var open2: bool = wire_on(el.id, "2") == null
	var avol: float = _accessory_port_vol(el)
	var m_atm: float = ATM * avol / (R_AIR * gas_t)
	if open1:
		p1 = ATM
		el.port_press["1"] = ATM
		el.port_mass["1"] = m_atm
		if k1 != "":
			pmap[k1] = ATM
			mmap[k1] = m_atm
		e1 = {"key": k1, "p": ATM}
	if open2:
		p2 = ATM
		el.port_press["2"] = ATM
		el.port_mass["2"] = m_atm
		if k2 != "":
			pmap[k2] = ATM
			mmap[k2] = m_atm
		e2 = {"key": k2, "p": ATM}
	var base: float = 1.2e-6 * clampf(float(el.valve_cv), 0.2, 4.0)
	var qn: float = clampf(float(el.flow_nl_min), 10.0, 20000.0)
	var check_base: float = base * clampf(qn / 600.0, 0.15, 8.0) * 2.2
	var spring_pa: float = clampf(float(el.crack_pressure_bar), 0.01, 5.0) * 1.0e5
	var travel_pa: float = 0.30e5
	var check_open: float = clampf(((p2 - p1) - spring_pa) / travel_pa, 0.0, 1.0)
	if p1 > p2 and thr_area > 1.0e-12:
		if open2:
			_pour(e1, {"key": "", "p": ATM}, thr_area, acc, pmap, mmap, vols, h)
		elif not open1:
			_pour(e1, e2, thr_area, acc, pmap, mmap, vols, h)
	elif check_open > 1.0e-4:
		var bypass: float = check_base * check_open
		if open1:
			_pour(e2, {"key": "", "p": ATM}, bypass, acc, pmap, mmap, vols, h)
		elif not open2:
			_pour(e2, e1, bypass, acc, pmap, mmap, vols, h)


## Клапан «ИЛИ» (shuttle): большее из P1/P2 → порт 3; меньшее седло закрыто шариком.
## opening 0…1 = положение шарика (0 = у седла 1 / путь 2→3, 1 = у седла 2 / путь 1→3).
func _accessory_shuttle_flow(
	el: Element, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float
) -> void:
	var k1 := "c:%d:1" % el.id
	var k2 := "c:%d:2" % el.id
	var k3 := "c:%d:3" % el.id
	if not pmap.has(k1) or not pmap.has(k2) or not pmap.has(k3):
		return
	var p1: float = float(pmap[k1])
	var p2: float = float(pmap[k2])
	var p3: float = float(pmap[k3])
	# Неподключённый вход = ATM (как у ОК).
	var avol: float = _accessory_port_vol(el)
	var m_atm: float = ATM * avol / (R_AIR * gas_t)
	if wire_on(el.id, "1") == null:
		p1 = ATM
		pmap[k1] = ATM
		mmap[k1] = m_atm
		el.port_press["1"] = ATM
		el.port_mass["1"] = m_atm
	if wire_on(el.id, "2") == null:
		p2 = ATM
		pmap[k2] = ATM
		mmap[k2] = m_atm
		el.port_press["2"] = ATM
		el.port_mass["2"] = m_atm
	if wire_on(el.id, "3") == null:
		p3 = ATM
		pmap[k3] = ATM
		mmap[k3] = m_atm
		el.port_press["3"] = ATM
		el.port_mass["3"] = m_atm
	# Гистерезис переключения ~0.12 бар — шарик не дребезжит на равных P.
	const HYST_PA := 1.2e4
	## Время полного хода седло↔седло (с) — видно на УГО и в 3D.
	const BALL_TRAVEL_S := 0.32
	var prev: float = clampf(float(el.opening), 0.0, 1.0)
	var target: float = prev
	if p1 > p2 + HYST_PA:
		target = 1.0 # шарик к седлу 2 → открыт путь 1→3
	elif p2 > p1 + HYST_PA:
		target = 0.0 # шарик к седлу 1 → открыт путь 2→3
	var step: float = h / BALL_TRAVEL_S
	el.opening = move_toward(prev, target, step)
	var e1 := {"key": k1, "p": pmap[k1]}
	var e2 := {"key": k2, "p": pmap[k2]}
	var e3 := {"key": k3, "p": pmap[k3]}
	var side: float = float(el.opening)
	# Сечение активного пути; второй почти закрыт.
	var a_from1: float = area * clampf((side - 0.35) / 0.45, 0.0, 1.0)
	var a_from2: float = area * clampf((0.65 - side) / 0.45, 0.0, 1.0)
	if a_from1 > 1.0e-12:
		_pour(e1, e3, a_from1, acc, pmap, mmap, vols, h)
	if a_from2 > 1.0e-12:
		_pour(e2, e3, a_from2, acc, pmap, mmap, vols, h)


## Давление «сигнала» на входе «И»: трубка (уставка КР), не камера порта после сброса в ATM.
func _and_feed_pressure_pa(el_id: int, port: String, pmap: Dictionary, port_pa: float) -> float:
	var w: Wire = wire_on(el_id, port)
	if w == null:
		return port_pa
	var wk: String = "w:%d" % int(w.id)
	if pmap.has(wk):
		return float(pmap[wk])
	return float(w.pressure)


## Клапан «И» (dual-pressure): выход 3 только при давлении на обоих входах 1 и 2.
## opening 0.5 = гантель в центре (оба сигнала); 0/1 = сдвиг при одном сигнале (стравливание 3).
func _accessory_and_flow(
	el: Element, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float
) -> void:
	var k1 := "c:%d:1" % el.id
	var k2 := "c:%d:2" % el.id
	var k3 := "c:%d:3" % el.id
	if not pmap.has(k1) or not pmap.has(k2) or not pmap.has(k3):
		return
	var p1: float = float(pmap[k1])
	var p2: float = float(pmap[k2])
	var avol: float = _accessory_port_vol(el)
	var m_atm: float = ATM * avol / (R_AIR * gas_t)
	var open1: bool = wire_on(el.id, "1") == null
	var open2: bool = wire_on(el.id, "2") == null
	var open3: bool = wire_on(el.id, "3") == null
	if open1:
		p1 = ATM
		pmap[k1] = ATM
		mmap[k1] = m_atm
		el.port_press["1"] = ATM
		el.port_mass["1"] = m_atm
	if open2:
		p2 = ATM
		pmap[k2] = ATM
		mmap[k2] = m_atm
		el.port_press["2"] = ATM
		el.port_mass["2"] = m_atm
	if open3:
		pmap[k3] = ATM
		mmap[k3] = m_atm
		el.port_press["3"] = ATM
		el.port_mass["3"] = m_atm
	const THR_PA := 5.0e4 # ~0.5 бар изб. — «есть сигнал»
	const SPOOL_TRAVEL_S := 0.28
	var prev: float = clampf(float(el.opening), 0.0, 1.0)
	# Сигнал с трубки/КР — иначе при открытом выходе 3 камеры портов «схлопываются» одинаково.
	var s1: float = _and_feed_pressure_pa(el.id, "1", pmap, p1)
	var s2: float = _and_feed_pressure_pa(el.id, "2", pmap, p2)
	var g1: bool = s1 > ATM + THR_PA
	var g2: bool = s2 > ATM + THR_PA
	# Положение только по наличию сигналов — не по ΔP.
	var target: float = 0.5
	if g1 and g2:
		target = 0.5
	elif g1 and not g2:
		target = 1.0
	elif g2 and not g1:
		target = 0.0
	el.opening = move_toward(prev, target, h / SPOOL_TRAVEL_S)
	var e1 := {"key": k1, "p": pmap[k1]}
	var e2 := {"key": k2, "p": pmap[k2]}
	# Свободный выход 3 = ATM-сток (не буфер k3).
	var sink3: Dictionary = {"key": "", "p": ATM} if open3 else {"key": k3, "p": pmap[k3]}
	var side: float = float(el.opening)
	var center: float = 1.0 - absf(side - 0.5) * 2.0
	if g1 and g2 and center > 0.15:
		var a_both: float = area * clampf(center, 0.0, 1.0)
		_pour(e1, sink3, a_both, acc, pmap, mmap, vols, h)
		_pour(e2, sink3, a_both, acc, pmap, mmap, vols, h)
	elif g1 and not g2:
		# Нет сигнала на 2 — выход стравливается в порт 2.
		if not open3:
			_pour({"key": k3, "p": pmap[k3]}, e2, area * 0.85, acc, pmap, mmap, vols, h)
	elif g2 and not g1:
		if not open3:
			_pour({"key": k3, "p": pmap[k3]}, e1, area * 0.85, acc, pmap, mmap, vols, h)


## Быстрый выхлоп: 1=вход, 2=ПЦ, 3=выхлоп.
## opening 1 = тарелка к выхлопу (питание 1→2); 0 = тарелка к входу (2→3 в атмосферу/линию).
func _accessory_quick_exhaust_flow(
	el: Element, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float
) -> void:
	var k1 := "c:%d:1" % el.id
	var k2 := "c:%d:2" % el.id
	var k3 := "c:%d:3" % el.id
	if not pmap.has(k1) or not pmap.has(k2) or not pmap.has(k3):
		return
	var p1: float = float(pmap[k1])
	var p2: float = float(pmap[k2])
	var p3: float = float(pmap[k3])
	var avol: float = _accessory_port_vol(el)
	var m_atm: float = ATM * avol / (R_AIR * gas_t)
	if wire_on(el.id, "1") == null:
		p1 = ATM
		pmap[k1] = ATM
		mmap[k1] = m_atm
		el.port_press["1"] = ATM
		el.port_mass["1"] = m_atm
	if wire_on(el.id, "2") == null:
		p2 = ATM
		pmap[k2] = ATM
		mmap[k2] = m_atm
		el.port_press["2"] = ATM
		el.port_mass["2"] = m_atm
	# Выхлоп 3: глушитель или свободный штуцер → ATM (как у ПР).
	var exh_fit: String = ValveCat.exhaust_fit(el, "3")
	var exh_to_atm: bool = wire_on(el.id, "3") == null
	if exh_to_atm:
		p3 = ATM
		pmap[k3] = ATM
		mmap[k3] = m_atm
		el.port_press["3"] = ATM
		el.port_mass["3"] = m_atm
	const HYST_PA := 8.0e3
	const DISC_TRAVEL_S := 0.22
	var prev: float = clampf(float(el.opening), 0.0, 1.0)
	var target: float = prev
	# Давление со входа сильнее — тарелка к выхлопу (питание).
	if p1 > p2 + HYST_PA:
		target = 1.0
	elif p2 > p1 + HYST_PA:
		target = 0.0
	el.opening = move_toward(prev, target, h / DISC_TRAVEL_S)
	var side: float = float(el.opening)
	var a_supply: float = area * clampf((side - 0.30) / 0.50, 0.0, 1.0)
	var exh_ratio: float = AccLib.quick_exhaust_exh_ratio(el)
	var a_exh: float = area * exh_ratio * clampf((0.70 - side) / 0.50, 0.0, 1.0)
	var e1 := {"key": k1, "p": pmap[k1]}
	var e2 := {"key": k2, "p": pmap[k2]}
	var e3 := {"key": k3, "p": pmap[k3]}
	if a_supply > 1.0e-12:
		if wire_on(el.id, "2") == null:
			_pour(e1, {"key": "", "p": ATM}, a_supply, acc, pmap, mmap, vols, h)
		elif wire_on(el.id, "1") != null:
			_pour(e1, e2, a_supply, acc, pmap, mmap, vols, h)
	if a_exh > 1.0e-12:
		if exh_to_atm or exh_fit == "muffler":
			# Прямой быстрый сброс ПЦ → ATM (глушитель / открытый 3).
			_pour(e2, {"key": "", "p": ATM}, a_exh, acc, pmap, mmap, vols, h)
		else:
			_pour(e2, e3, a_exh, acc, pmap, mmap, vols, h)


## Предохранительный клапан: вход 1 → сброс 2 при P1≥уставка; рукоятка (pressed) открывает принудительно.
## opening 0 = тарелка на седле; 1 = полностью открыт.
func _accessory_relief_flow(
	el: Element, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float
) -> void:
	var k1 := "c:%d:1" % el.id
	var k2 := "c:%d:2" % el.id
	# При глушителе порт 2 не в схеме (нет tip) — k2 может отсутствовать в pmap.
	if not pmap.has(k1):
		return
	var avol: float = _accessory_port_vol(el)
	var m_atm: float = ATM * avol / (R_AIR * gas_t)
	if wire_on(el.id, "1") == null:
		pmap[k1] = ATM
		mmap[k1] = m_atm
		el.port_press["1"] = ATM
		el.port_mass["1"] = m_atm
	var muffler: bool = str(el.port_3) == "muffler"
	var open2: bool = wire_on(el.id, "2") == null
	var to_atm: bool = muffler or open2 or not pmap.has(k2)
	if pmap.has(k2) and to_atm:
		pmap[k2] = ATM
		mmap[k2] = m_atm
		el.port_press["2"] = ATM
		el.port_mass["2"] = m_atm
	var p1: float = float(pmap[k1])
	const DISC_TRAVEL_S := 0.20
	const HYST_BAR := 0.08
	var set_b: float = clampf(float(el.set_pressure_bar), 0.5, 16.0)
	var gauge_bar: float = maxf((p1 - ATM) / 1.0e5, 0.0)
	var prev: float = clampf(float(el.opening), 0.0, 1.0)
	var target: float = 0.0
	if bool(el.pressed):
		target = 1.0
	elif gauge_bar > set_b + HYST_BAR:
		# Над уставкой — пропорциональное открытие (учебная модель).
		target = clampf((gauge_bar - set_b) / maxf(set_b * 0.35, 0.4), 0.15, 1.0)
	elif gauge_bar > set_b - HYST_BAR * 0.5 and prev > 0.05:
		# Гистерезис закрытия — тарелка не дребезжит на уставке.
		target = prev * 0.85
	else:
		target = 0.0
	el.opening = move_toward(prev, target, h / DISC_TRAVEL_S)
	var side: float = float(el.opening)
	if side < 0.02:
		return
	var a_open: float = area * clampf((side - 0.02) / 0.85, 0.0, 1.0)
	var e1 := {"key": k1, "p": pmap[k1]}
	var sink2: Dictionary = {"key": "", "p": ATM} if to_atm else {"key": k2, "p": pmap[k2]}
	_pour(e1, sink2, a_open, acc, pmap, mmap, vols, h)
	# Viz-конусы сброса (глушитель / открытый 2).
	if to_atm:
		_relief_latch[int(el.id)] = true


func _accessory_regulator_flow(el: Element, e1: Dictionary, e2: Dictionary, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float) -> void:
	# Питание 1 → уставка на 2. Подпитка при недоборе.
	# Сброс 2→ATM при переборе — редуктор с relief (пунктир+треугольник на УГО):
	# снижение уставки на запертой линии стравливает избыток (это не утечка дросселя).
	# Полностью затянут (уставка ≈ 0): седло закрыто — питания 1→2 нет.
	const SHUT_BAR := 0.05
	var set_b: float = clampf(float(el.set_pressure_bar), 0.0, 16.0)
	var p1: float = float(e1["p"])
	var p2: float = float(e2["p"])
	if p1 <= ATM + 5.0e3 and set_b > SHUT_BAR:
		return
	if set_b <= SHUT_BAR:
		# Перекрыт: только сброс вторичной в ATM (как relieving при нулевой уставке).
		if p2 > ATM + 1.2e4:
			var over_s: float = clampf((p2 - ATM) / 1.5e5, 0.08, 1.2)
			_pour(e2, {"key": "", "p": ATM}, area * 0.7 * over_s, acc, pmap, mmap, vols, h)
			_relief_latch[int(el.id)] = true
		return
	var p_set: float = (set_b + 1.01325) * 1.0e5
	var err: float = p_set - p2
	if err > 5.0e3 and p1 > p2 + 5.0e3:
		var need: float = clampf(err / maxf(p_set - ATM, 5.0e4), 0.05, 1.0)
		var head: float = clampf((p1 - p2) / maxf(p1 - ATM, 1.0e4), 0.15, 1.0)
		var feed: float = area * (0.35 + 1.65 * need) * head
		_pour(e1, e2, feed, acc, pmap, mmap, vols, h)
	elif err > 1.0e3 and p1 > p_set + 1.0e4:
		_pour(e1, e2, area * 0.25, acc, pmap, mmap, vols, h)
	# Relief только при явном переборе над уставкой (не трогаем, если крутим уставку вверх).
	if p2 > p_set + 1.2e4:
		var over: float = clampf((p2 - p_set) / 1.5e5, 0.08, 1.2)
		var relief_area: float = area * 0.7 * over
		_pour(e2, {"key": "", "p": ATM}, relief_area, acc, pmap, mmap, vols, h)
		# Хвост viz зажигаем в step() после субшагов (~0.55 с).
		_relief_latch[int(el.id)] = true


## Плавный поворот отсечного крана к valve_pos (и в Run, и для UGO/3D).
func _tick_shutoff_animation(frame_dt: float) -> void:
	var dt: float = maxf(frame_dt, 0.0)
	if dt <= 0.0:
		return
	for el in elements:
		if el != null and str(el.kind) == "accessory" and str(el.accessory_class) == "shutoff":
			AccLib.advance_shutoff(el, dt)


## Таймер хвоста анимации сброса (секунды).
func _tick_regulator_relief_trail(frame_dt: float) -> void:
	if relief_trail_s.is_empty():
		return
	var dt: float = maxf(frame_dt, 0.0)
	var drop: Array = []
	for eid in relief_trail_s.keys():
		var left: float = float(relief_trail_s[eid]) - dt
		if left <= 0.0:
			drop.append(eid)
		else:
			relief_trail_s[eid] = left
	for eid2 in drop:
		relief_trail_s.erase(eid2)


## Есть ли сейчас viz-сброс у редуктора (хвост или активный перебор).
func regulator_relief_active(el_id: int) -> bool:
	return float(relief_trail_s.get(int(el_id), 0.0)) > 0.0


func _ensure_valve_ports(el: Element) -> void:
	var keep := {}
	for name in ValveCat.port_names(el):
		keep[name] = true
		if not el.port_press.has(name):
			el.port_press[name] = ATM
		if not el.port_mass.has(name):
			el.port_mass[name] = ATM * _valve_port_vol(el) / (R_AIR * gas_t)
	var drop: Array = []
	for key in el.port_press.keys():
		if not keep.has(key):
			drop.append(key)
	for key in drop:
		el.port_press.erase(key)
		el.port_mass.erase(key)


## Пилотный объём порта тормоза NC (не камера поршня).
func _ensure_cylinder_aux_ports(el: Element) -> void:
	var keep := {}
	if str(el.brake) == "nc":
		keep["brake"] = true
		var vol := _brake_port_vol()
		if not el.port_press.has("brake"):
			el.port_press["brake"] = ATM
		if not el.port_mass.has("brake"):
			el.port_mass["brake"] = ATM * vol / (R_AIR * gas_t)
	var drop: Array = []
	for key in el.port_press.keys():
		if not keep.has(key):
			drop.append(key)
	for key in drop:
		el.port_press.erase(key)
		el.port_mass.erase(key)
		if el.port_q.has(key):
			el.port_q.erase(key)


func _brake_port_vol() -> float:
	return 8.0e-6


func _valve_port_vol(_el: Element) -> float:
	return 8.0e-6


func valve_area(el: Element) -> float:
	# Учебный эквивалент проходного сечения.
	return 1.2e-6 * clampf(float(el.valve_cv), 0.2, 4.0)


func _init_wire(wire: Wire) -> void:
	wire.vol = _wire_volume(wire)
	wire.mass = ATM * wire.vol / (R_AIR * gas_t)
	wire.pressure = ATM
	wire.pressure_vis = ATM
	wire.flow_m3s = 0.0
	wire.flow_vis = 0.0
	wire.flow_sign = 0.0
	wire.flow_flip_t = 0.0
	wire.flow_phase = 0.0
	wire.flow_anim_speed = 0.0
	wire.flow_puff_n = 0


func _stroke_m(el: Element) -> float:
	return el.stroke_mm * 0.001


func _areas(el: Element) -> Vector3:
	var bore := el.bore_mm * 0.001
	var rod := el.rod_mm * 0.001
	var cap := PI * bore * bore * 0.25
	var rod_limited := minf(rod, maxf(bore - 0.0005, bore * 0.5))
	var ann := PI * maxf(bore * bore - rod_limited * rod_limited, 0.0) * 0.25
	if el.through_rod:
		return Vector3(ann, ann, 0.0)
	var rod_a := PI * rod_limited * rod_limited * 0.25
	return Vector3(cap, ann, rod_a)


func has_channel(el: Element, channel: String) -> bool:
	if el.kind != "cylinder":
		return false
	if channel == "cap":
		if str(el.port_cap) == "exhaust":
			return false
		return el.action != "spring_extend"
	if str(el.port_rod) == "exhaust":
		return false
	return el.action != "spring_return"


func chamber_volume(el: Element, channel: String) -> float:
	var area := _areas(el)
	var a: float = area.x if channel == "cap" else area.y
	# Мёртвый объём у крышки — из той же геометрии, что 3D-труба ПЦ (хвост сверх хода).
	# Пол ≥ 1.5e-5 м³: иначе штоковая при полном выдвижении слишком жёсткая → ring P.
	var dead: float = maxf(a * _cylinder_dead_len_m(el), 1.5e-5)
	if channel == "cap":
		return dead + area.x * el.x
	return dead + area.y * (_stroke_m(el) - el.x)


## Объёмы камер поворотного ПЦ.
## Рейка: a = между поршнями, b = снаружи. Лопасть: сектора V ∝ θ·(R²−r²)·h/2.
func _rotary_chamber_vols(el: Element) -> Dictionary:
	var th_max: float = deg_to_rad(float(el.angle_max_deg))
	var th: float = clampf(float(el.angle), 0.0, th_max)
	if RotaryCat.is_vane(el):
		var R: float = RotaryCat.vane_chamber_r_m(float(el.bore_mm))
		var rs: float = RotaryCat.vane_shaft_r_m(float(el.bore_mm))
		var hh: float = RotaryCat.vane_height_m(float(el.bore_mm))
		var k: float = 0.5 * (R * R - rs * rs) * hh
		var dead_v: float = maxf(k * 0.08, 8.0e-7)
		return {"a": dead_v + k * th, "b": dead_v + k * (th_max - th)}
	var area: float = RotaryCat.piston_area_m2(float(el.bore_mm))
	var r: float = RotaryCat.pinion_radius_m(float(el.bore_mm))
	var dead: float = maxf(area * 0.008, 1.2e-6)
	var va: float = dead + 2.0 * area * r * th
	var vb: float = dead + 2.0 * area * r * (th_max - th)
	return {"a": va, "b": vb}


## Эквивалентная длина мёртвого зазора у крышки (м), согласована с IsoCylinder.barrel_l − stroke.
func _cylinder_dead_len_m(el: Element) -> float:
	var bore: float = float(el.bore_mm) * 0.001
	var style: String = str(el.body_style)
	var rodless: bool = str(el.rod_mode) == "rodless"
	var pad: float
	if rodless:
		pad = maxf(bore * 0.25, 0.01)
	elif style == "compact":
		pad = maxf(bore * 0.18, 0.01)
	else:
		pad = maxf(bore * 0.40, 0.016)
	return pad * 0.45


func explain_force(el: Element) -> String:
	var area := _areas(el)
	var cap_mm2 := area.x * 1.0e6
	var ann_mm2 := area.y * 1.0e6
	var p_cap := el.p_cap if has_channel(el, "cap") else ATM
	var p_rod := el.p_rod if has_channel(el, "rod") else ATM
	var g_cap := (p_cap - ATM) / 1.0e5
	var g_rod := (p_rod - ATM) / 1.0e5
	var push := g_cap * 1.0e5 * area.x
	var pull := g_rod * 1.0e5 * area.y
	var net := drive_force(el, p_cap, p_rod)
	var way := "равновесие"
	if net > 1.0:
		way = "выдвижение"
	elif net < -1.0:
		way = "втягивание"
	var text := "Площадь поршня %.0f мм², кольцо со стороны штока %.0f мм².\nБесштоковая полость: %.2f бар → %.0f Н на выдвижение.\nШтоковая полость: %.2f бар → %.0f Н на втягивание.\nРавнодействующая давления, пружины и нагрузки: %.0f Н, %s." % [
		cap_mm2, ann_mm2, g_cap, push, g_rod, pull, net, way,
	]
	if el.through_rod:
		text += "\nПроходной шток: рабочие площади обеих полостей одинаковые, атмосферная добавка от штока взаимно сокращается."
	elif g_rod > g_cap + 0.05 and net > 1.0:
		text += "\nДавление со стороны штока выше, но кольцевая площадь меньше полной площади поршня, поэтому шток выходит."
	return text


func drive_force(el: Element, p_cap: float, p_rod: float) -> float:
	var area := _areas(el)
	var force := p_cap * area.x - p_rod * area.y - ATM * area.z
	var x_mm := el.x * 1000.0
	if el.action == "spring_return" or (el.action == "double" and str(el.spring_side) == "rod"):
		force -= el.spring_preload + el.spring_rate * x_mm
	elif el.action == "spring_extend" or (el.action == "double" and str(el.spring_side) == "cap"):
		force += el.spring_preload + el.spring_rate * (el.stroke_mm - x_mm)
	force -= el.load_n
	return force


func _write_channel(el: Element, channel: String, pressure: float) -> void:
	if not has_channel(el, channel):
		if channel == "cap":
			el.p_cap = ATM
			el.m_cap = 0.0
		else:
			el.p_rod = ATM
			el.m_rod = 0.0
		return
	var vol := chamber_volume(el, channel)
	var mass := maxf(pressure, 2000.0) * vol / (R_AIR * gas_t)
	if channel == "cap":
		el.m_cap = mass
		el.p_cap = pressure
	else:
		el.m_rod = mass
		el.p_rod = pressure


func _pressure_of_mass(mass: float, vol: float) -> float:
	var p := mass * R_AIR * gas_t / maxf(vol, 1.0e-9)
	return clampf(p, 2000.0, 3.0e6)


func _wire_path_length_m(wire: Wire) -> float:
	# Предпочтительно длина 3D-централи (workshop пишет wire.length_m).
	# Иначе — простая 2D-polyline схемы (без умного роутера: O(route) каждый шаг).
	if wire != null and float(wire.length_m) > 0.04:
		return clampf(float(wire.length_m), 0.05, 25.0)
	var a := get_element(wire.a_id)
	var b := get_element(wire.b_id)
	if a == null or b == null:
		return 0.5
	return Geom.hose_length_m(a, wire.a_port, b, wire.b_port, wire.joints)


## Записать длину пневмотрубки из 3D-пути (м). Электро — игнор.
func apply_wire_length_3d(wire: Wire, pts: PackedVector3Array) -> void:
	if wire == null or pts.size() < 2:
		return
	var ea := get_element(int(wire.a_id))
	if ea != null and port_domain(ea, str(wire.a_port)) == "electric":
		return
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	wire.length_m = clampf(total, 0.05, 25.0)


func _wire_volume(wire: Wire) -> float:
	var length := _wire_path_length_m(wire)
	var radius := wire.id_mm * 0.0005
	return maxf(PI * radius * radius * length, 1.0e-6)


func _tube_area(wire: Wire) -> float:
	var length := _wire_path_length_m(wire)
	var radius := wire.id_mm * 0.0005
	var geometric := PI * radius * radius
	return geometric * TUBE_CD / (1.0 + length / 0.55)


func _port_area(el: Element) -> float:
	var d_mm: float = Catalog.port_orifice_mm(el.port_name)
	var radius: float = d_mm * 0.0005
	return PI * radius * radius * PORT_CD


static func mass_flow(p_a: float, p_b: float, area: float, temp: float) -> float:
	if area <= 0.0:
		return 0.0
	var up := p_a
	var down := p_b
	var direction := 1.0
	if p_b > p_a:
		up = p_b
		down = p_a
		direction = -1.0
	if up <= 1.0:
		return 0.0
	var ratio := down / up
	var crit := pow(2.0 / (GAMMA + 1.0), GAMMA / (GAMMA - 1.0))
	var mdot: float
	if ratio <= crit:
		var coef := sqrt(GAMMA / (R_AIR * temp)) * pow(2.0 / (GAMMA + 1.0), (GAMMA + 1.0) / (2.0 * (GAMMA - 1.0)))
		mdot = area * up * coef
	else:
		var inner := (2.0 * GAMMA) / (R_AIR * temp * (GAMMA - 1.0))
		inner *= pow(ratio, 2.0 / GAMMA) - pow(ratio, (GAMMA + 1.0) / GAMMA)
		mdot = area * up * sqrt(maxf(inner, 0.0))
	return direction * mdot


## Сглаженный сквозной расход A→B для анимации конусов/шевронов.
## Быстрый attack / медленный decay — дозаряд при росте P ещё виден.
## Знак липкий от шума, но разворот (выхлоп) не рисует стрелки «не туда».
func _latch_flow_sign(wire: Wire, raw_q: float, dt: float = 0.001) -> float:
	const ALPHA_UP := 0.32
	const ALPHA_DOWN := 0.055
	# ~0.5 Nl/мин (раньше 3.6) — иначе поздний дозаряд «пропадает» при живом P.
	const DEAD := 8.0e-6
	const CLEAR := 0.40
	# Уверенный разворот (~2.4 Nl/мин) — сразу; слабый — короткая пауза.
	const FLIP_Q_SNAP := 4.0e-5
	const FLIP_Q := 1.0e-4
	const HOLD := 0.10
	var h: float = maxf(dt, 1.0e-4)
	var prev: float = float(wire.flow_vis)
	var alpha: float = ALPHA_UP if absf(raw_q) >= absf(prev) else ALPHA_DOWN
	var sm: float = lerpf(prev, raw_q, alpha)
	if absf(raw_q) < DEAD:
		wire.flow_flip_t += h
		if wire.flow_sign == 0.0:
			wire.flow_vis = 0.0
			return 0.0
		# У нуля гасим, а не держим VIS_HOLD со старым знаком (иначе «ещё к потребителю»).
		var fade0: float = lerpf(absf(prev), 0.0, 0.28)
		if wire.flow_flip_t >= CLEAR or fade0 < DEAD * 0.35:
			wire.flow_vis = 0.0
			wire.flow_sign = 0.0
			wire.flow_flip_t = 0.0
			wire.flow_puff_n = 0
			return 0.0
		wire.flow_vis = fade0 * wire.flow_sign
		return float(wire.flow_vis)
	var s_raw: float = signf(raw_q)
	if wire.flow_sign == 0.0:
		# Старт: сразу заметная доля raw — конусы не ждут долгий EMA.
		wire.flow_sign = s_raw
		wire.flow_flip_t = 0.0
		wire.flow_vis = absf(raw_q) * 0.65 * s_raw
		return float(wire.flow_vis)
	if s_raw != wire.flow_sign:
		# Явный обратный расход (выхлоп после золотника) — переключаем без долгой залипалки.
		if absf(raw_q) >= FLIP_Q_SNAP:
			wire.flow_sign = s_raw
			wire.flow_flip_t = 0.0
			wire.flow_vis = absf(raw_q) * 0.8 * s_raw
			return float(wire.flow_vis)
		if absf(raw_q) >= DEAD * 2.0:
			wire.flow_flip_t += h
		else:
			wire.flow_flip_t = 0.0
		if wire.flow_flip_t >= HOLD or absf(raw_q) >= FLIP_Q:
			wire.flow_sign = s_raw
			wire.flow_flip_t = 0.0
			wire.flow_vis = absf(sm) * s_raw
			return float(wire.flow_vis)
		# Пока не уверены — гасим; не оставляем знак для hold_anim со старым направлением.
		var fade_r: float = lerpf(absf(prev), 0.0, 0.4)
		if fade_r < DEAD:
			wire.flow_vis = 0.0
			wire.flow_sign = 0.0
			wire.flow_flip_t = 0.0
			wire.flow_anim_speed = 0.0
			return 0.0
		wire.flow_vis = fade_r * wire.flow_sign
		return float(wire.flow_vis)
	wire.flow_flip_t = 0.0
	wire.flow_vis = absf(sm) * wire.flow_sign
	return float(wire.flow_vis)


## Расход на порту для tip/UI (м³/с; + в элемент, − из элемента).
## Подключённый порт: сквозной расход трубки (не net port_q — у ресивера/арматуры
## в стационаре приток и уход гасятся, net≈0 при живой линии).
func port_viz_q(el: Element, port: String) -> float:
	if el == null:
		return 0.0
	var pname: String = str(port)
	if port_domain(el, pname) == "electric":
		return 0.0
	var w: Wire = wire_on(int(el.id), pname)
	if w == null:
		return open_port_viz_q(el, pname)
	var q: float = float(w.flow_vis)
	if absf(q) < 1.0e-12:
		q = float(w.flow_m3s)
	# flow_vis >0 = A→B: уходит из A, входит в B.
	if int(w.a_id) == int(el.id) and str(w.a_port) == pname:
		return -q
	if int(w.b_id) == int(el.id) and str(w.b_port) == pname:
		return q
	return 0.0


## Расход для выхлопа/подсоса на открытом пневмопорту (м³/с; <0 = наружу в атмосферу).
func open_port_viz_q(el: Element, port: String) -> float:
	if el == null:
		return 0.0
	var pname: String = str(port)
	if wire_on(int(el.id), pname) != null:
		return 0.0
	if port_domain(el, pname) == "electric":
		return 0.0
	# ОК: net port_q≈0 в стационаре — считаем сквозной p→атм напрямую.
	if str(el.kind) == "accessory" and str(el.accessory_class) == "check":
		if float(el.opening) <= 0.5:
			return 0.0
		var area_c: float = accessory_area(el)
		if pname == "2" and wire_on(int(el.id), "1") != null:
			var p1: float = float(el.port_press.get("1", ATM)) if el.get("port_press") != null else ATM
			var mdot1: float = mass_flow(p1, ATM, area_c, gas_t)
			var rho1: float = maxf(p1 / (R_AIR * gas_t), 0.05)
			return -mdot1 / rho1
		if pname == "1" and wire_on(int(el.id), "2") != null:
			var p2: float = float(el.port_press.get("2", ATM)) if el.get("port_press") != null else ATM
			var mdot2: float = mass_flow(p2, ATM, area_c, gas_t)
			var rho2: float = maxf(p2 / (R_AIR * gas_t), 0.05)
			return -mdot2 / rho2
		return 0.0
	# Арматура/ресивер: при открытом порте port_q≈0 (вход по трубке и выход в ATM гасятся
	# в одном ключе). Для 2D/3D — сквозной расход по трубкам + запас по ΔP.
	if str(el.kind) == "accessory":
		var cls_v: String = str(el.accessory_class)
		# Закрытая игла дросселя: нет сквозного выхлопа с линии (свободный порт ≈ ATM).
		if (cls_v == "throttle" or cls_v == "throttle_check" or cls_v == "throttle_check_fixed") and float(el.opening) < 0.02:
			return 0.0
		var q_thru: float = _open_atm_thru_viz_q(el)
		if absf(q_thru) > 1.0e-9:
			return q_thru
		var pa: float = float(el.port_press.get(pname, ATM)) if el.get("port_press") != null else ATM
		var area_a: float = _open_port_atm_area(el)
		var mdot_a: float = mass_flow(pa, ATM, area_a, gas_t)
		var rho_a: float = maxf(pa / (R_AIR * gas_t), 0.05)
		return -mdot_a / rho_a
	if str(el.kind) == "junction":
		# Свободный штуцер тройника: сквозной расход с трубок + запас по ΔP узла.
		var q_j: float = _open_atm_thru_viz_q(el)
		if absf(q_j) > 1.0e-9:
			return q_j
		var pj: float = float(el.p_cap)
		var area_j: float = _open_port_atm_area(el)
		var mdot_j: float = mass_flow(pj, ATM, area_j, gas_t)
		var rho_j: float = maxf(pj / (R_AIR * gas_t), 0.05)
		return -mdot_j / rho_j
	if str(el.kind) == "cylinder":
		if pname == "cap":
			return float(el.q_cap)
		if pname == "rod":
			return float(el.q_rod)
	if str(el.kind) == "valve":
		if ValveCat.is_exhaust_port(pname):
			# 1) Сквозной выхлоп по открытой клетке (2→3 / 4→5) — даже если объём R≈ATM.
			var q_path: float = _valve_exhaust_path_viz_q(el, pname)
			if absf(q_path) > 1.0e-9:
				return q_path
			# 2) ΔP самого порта выхлопа к атмосфере.
			var pv: float = float(el.port_press.get(pname, ATM)) if el.get("port_press") != null else ATM
			var area_v: float = valve_area(el) * 6.0
			var mdot_v: float = mass_flow(pv, ATM, area_v, gas_t)
			var rho_v: float = maxf(pv / (R_AIR * gas_t), 0.05)
			return -mdot_v / rho_v
		# Невыхлопной открытый порт ПР (редко) — тот же сквозной приём.
		var q_v: float = _open_atm_thru_viz_q(el)
		if absf(q_v) > 1.0e-9:
			return q_v
	if el.get("port_q") != null and el.port_q.has(pname):
		return float(el.port_q[pname])
	return 0.0


## Выхлоп через глушитель/открытый R: расход по открытым путям клетки → этот порт → ATM.
## Нужен, когда объём R уже ≈ATM, а воздух ещё идёт с рабочего порта/ПЦ.
func _valve_exhaust_path_viz_q(el: Element, exh_name: String) -> float:
	if el == null or not ValveCat.is_exhaust_port(exh_name):
		return 0.0
	if wire_on(int(el.id), exh_name) != null:
		return 0.0
	var area: float = valve_area(el)
	if area <= 1.0e-12:
		return 0.0
	var q_sum: float = 0.0
	for pair in ValveCat.path_pairs(el, int(el.valve_pos)):
		if not (pair is Array) or pair.size() < 2:
			continue
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		var other: String = ""
		if a == exh_name:
			other = b
		elif b == exh_name:
			other = a
		else:
			continue
		if ValveCat.is_exhaust_port(other):
			continue
		var p_o: float = float(el.port_press.get(other, ATM)) if el.get("port_press") != null else ATM
		if p_o <= ATM + 800.0:
			# Запас: расход с трубки на этот рабочий порт (в элемент → на выхлоп).
			var w: Wire = wire_on(int(el.id), other)
			if w != null:
				var qw: float = float(w.flow_vis)
				if absf(qw) < 1.0e-9:
					qw = float(w.flow_m3s)
				# flow A→B: на конце a_id расход из элемента отрицательный для a.
				var into_el: float = -qw if int(w.a_id) == int(el.id) else qw
				if into_el > 1.0e-9:
					q_sum += -into_el
			continue
		var mdot: float = mass_flow(p_o, ATM, area, gas_t)
		var rho: float = maxf(p_o / (R_AIR * gas_t), 0.05)
		q_sum += -mdot / rho
	return q_sum


## Площадь открытого штуцера в атмосферу ≈ ID трубки, ограничено проходом прибора.
## Слишком большое отверстие шунтирует соседние ветки (дроссель «молчит»).
func _open_port_atm_area(el: Element) -> float:
	var od: float = 6.0
	if el != null and float(el.tube_od_mm) >= 1.0:
		od = float(el.tube_od_mm)
	var id_m: float = maxf(od * 0.7, 2.0) * 0.001
	var a_fit: float = PI * pow(id_m * 0.5, 2.0)
	# Тройник — сечение ≈ штуцер/трубка, без clamp по Cv арматуры.
	if el != null and str(el.kind) == "junction":
		return a_fit * 0.9
	var a_dev: float = accessory_area(el)
	if el != null and str(el.accessory_class) == "reservoir":
		# Отводы ресивера: не шире внутреннего прохода ×2 — иначе весь расход в открытую бобышку.
		return clampf(a_fit * 0.35, a_dev * 0.8, a_dev * 2.0)
	# Дроссель: свободный штуцер всегда открыт в атмосферу; игла только между 1↔2.
	# Нельзя зажимать ATM-сечение иглой — иначе на выходе «залипает» давление и/или
	# при почти закрытой игле clampf(a_fit, ≈0, ≈0) давал ложную картину.
	var cls_atm: String = str(el.accessory_class) if el != null else ""
	if cls_atm == "throttle" or cls_atm == "throttle_check" or cls_atm == "throttle_check_fixed":
		if a_dev <= 1.0e-12:
			# Игла закрыта: локальный объём свободного порта → ATM (линия за иглой не дует).
			return a_fit * 0.45
		return clampf(a_fit, a_dev * 0.5, a_dev * 2.5)
	return clampf(a_fit, a_dev * 0.5, a_dev * 2.5)


## Сквозной расход «трубки → открытый порт → атмосфера» для анимации (м³/с, <0 = наружу).
## port_q на открытом порту ≈0: приток и выхлоп гасятся в одном ключе за шаг.
func _open_atm_thru_viz_q(el: Element) -> float:
	if el == null:
		return 0.0
	var open_n: int = 0
	var port_list: Array = []
	if str(el.kind) == "accessory":
		for pn in AccLib.port_names(el):
			port_list.append(str(pn))
	elif str(el.kind) == "valve":
		for pn2 in ValveCat.port_names(el):
			port_list.append(str(pn2))
	else:
		for port in Geom.ports(el):
			port_list.append(str(port.get("name", "")))
	for pname in port_list:
		if pname == "":
			continue
		if port_domain(el, pname) == "electric":
			continue
		if wire_on(int(el.id), pname) == null:
			open_n += 1
	if open_n < 1:
		return 0.0
	# Суммарный приток из трубок в элемент (flow_vis >0 = A→B).
	var q_in: float = 0.0
	for w in wires:
		if w == null:
			continue
		var q: float = float(w.flow_vis)
		if absf(q) < 1.0e-9:
			q = float(w.flow_m3s)
		if int(w.a_id) == int(el.id):
			q_in += -q
		elif int(w.b_id) == int(el.id):
			q_in += q
	if absf(q_in) < 1.0e-9:
		return 0.0
	return -q_in / float(open_n)


## Макс. избыток давления на схеме (Па), для относительной подкраски.
## Берём сглаженное значение — мгновенный max после удара поршня иначе мигает тон всей схемы.
func viz_max_over_pa() -> float:
	if _viz_max_over_smooth > 1.0:
		return _viz_max_over_smooth
	return _viz_max_over_instant()


## Для отрисовки: то же, что viz_max_over_pa (сглаженный кэш после step).
func viz_max_over_pa_cached() -> float:
	return viz_max_over_pa()


func perf_ms_step() -> float:
	return _perf_ms_step


func _viz_max_over_instant() -> float:
	var best: float = 0.0
	for wire in wires:
		best = maxf(best, maxf(float(wire.pressure) - ATM, 0.0))
	for el in elements:
		if el == null or str(el.kind) in ["electro", "coil", "rail"]:
			continue
		best = maxf(best, maxf(element_viz_pressure(el) - ATM, 0.0))
	return best


## Синхрон tip-поля с физикой (без EMA — маскировало пилу от scale/ОК).
func _smooth_wire_pressure_vis() -> void:
	for wire in wires:
		if wire == null:
			continue
		wire.pressure_vis = float(wire.pressure)


## Давление трубки для tip / подкраски — мгновенное (без EMA-маски).
func wire_viz_pressure(wire: Wire) -> float:
	if wire == null:
		return ATM
	return float(wire.pressure)


func _update_viz_max_over_smooth() -> void:
	var best: float = _viz_max_over_instant()
	if best > _viz_max_over_smooth:
		# Умеренный рост — короткие пики после удара поршня не дёргают тон схемы.
		_viz_max_over_smooth = lerpf(_viz_max_over_smooth, best, 0.12)
	else:
		# Медленный спад — отсекает дребезг после остановки поршня.
		_viz_max_over_smooth = lerpf(_viz_max_over_smooth, best, 0.03)
	if best < 500.0 and _viz_max_over_smooth < 2000.0:
		_viz_max_over_smooth = 0.0


## Давление элемента для подкраски УГО (Па абс.).
func element_viz_pressure(el: Element) -> float:
	if el == null:
		return ATM
	match str(el.kind):
		"source":
			return float(el.pressure_bar) * 1.0e5 + ATM
		"junction":
			return float(el.p_cap)
		"cylinder":
			return maxf(float(el.p_cap), float(el.p_rod))
		"rotary_cylinder":
			var pa_v: float = float(el.port_press.get("a", ATM)) if el.get("port_press") != null else ATM
			var pb_v: float = float(el.port_press.get("b", ATM)) if el.get("port_press") != null else ATM
			return maxf(pa_v, pb_v)
		"air_motor":
			var pin_v: float = float(el.port_press.get("in", ATM)) if el.get("port_press") != null else ATM
			var pex_v: float = float(el.port_press.get("exhaust", ATM)) if el.get("port_press") != null else ATM
			return maxf(pin_v, pex_v)
		"accessory":
			var p1: float = float(el.port_press.get("1", ATM)) if el.get("port_press") != null else ATM
			var p2: float = float(el.port_press.get("2", ATM)) if el.get("port_press") != null else ATM
			# Для ОК с открытым выходом: красим по питающему порту.
			if str(el.accessory_class) == "check" and wire_on(int(el.id), "2") == null:
				return p1
			return maxf(p1, p2)
		"valve":
			var best: float = ATM
			if el.get("port_press") != null:
				for k in el.port_press.keys():
					best = maxf(best, float(el.port_press[k]))
			return best
		_:
			return ATM


func _mean_source_temperature() -> float:
	var sum := 0.0
	var n := 0
	for el in elements:
		if el.kind == "source":
			sum += el.temperature_c + 273.15
			n += 1
	return (sum / float(n)) if n > 0 else 293.15


func _adopt_temperature() -> void:
	var next := _mean_source_temperature()
	if absf(next - gas_t) < 0.05:
		return
	var scale := gas_t / next
	for el in elements:
		el.m_cap *= scale
		el.m_rod *= scale
		if el.kind == "valve" or el.kind == "accessory" or el.kind == "rotary_cylinder" \
				or el.kind == "air_motor":
			for key in el.port_mass.keys():
				el.port_mass[key] = float(el.port_mass[key]) * scale
	for wire in wires:
		wire.mass *= scale
	gas_t = next


func _substep(h: float) -> void:
	var pmap := {}
	var mmap := {}
	var vols := {}
	for el in elements:
		# Галерея без пневмосвязей — не считаем (экономия на demo_pneumo_all и т.п.).
		if not _sim_active_els.has(int(el.id)):
			continue
		if el.kind == "valve":
			_update_valve_pos(el)
			var vol := _valve_port_vol(el)
			for name in ValveCat.port_names(el):
				var key := "c:%d:%s" % [el.id, name]
				var mass := float(el.port_mass.get(name, ATM * vol / (R_AIR * gas_t)))
				var pressure := _pressure_of_mass(mass, vol)
				mass = pressure * vol / (R_AIR * gas_t)
				pmap[key] = pressure
				mmap[key] = mass
				vols[key] = vol
				el.port_press[name] = pressure
				el.port_mass[name] = mass
			continue
		if el.kind == "accessory":
			var avol := _accessory_port_vol(el)
			for name in AccLib.port_names(el):
				var akey := "c:%d:%s" % [el.id, name]
				var amass := float(el.port_mass.get(name, ATM * avol / (R_AIR * gas_t)))
				var ap := _pressure_of_mass(amass, avol)
				amass = ap * avol / (R_AIR * gas_t)
				pmap[akey] = ap
				mmap[akey] = amass
				vols[akey] = avol
				el.port_press[name] = ap
				el.port_mass[name] = amass
			continue
		if el.kind == "rail":
			continue
		if el.kind == "junction":
			var jvol := _junction_vol(el)
			var jkey := "c:%d:j" % el.id
			var jmass := float(el.m_cap)
			if jmass < 1.0e-12:
				jmass = ATM * jvol / (R_AIR * gas_t)
			var jp := _pressure_of_mass(jmass, jvol)
			jmass = jp * jvol / (R_AIR * gas_t)
			pmap[jkey] = jp
			mmap[jkey] = jmass
			vols[jkey] = jvol
			el.p_cap = jp
			el.m_cap = jmass
			continue
		if el.kind == "rotary_cylinder":
			var rv0: Dictionary = _rotary_chamber_vols(el)
			for rname in ["a", "b"]:
				var rkey := "c:%d:%s" % [el.id, rname]
				var rvol: float = float(rv0[rname])
				var rmass: float = float(el.port_mass.get(rname, ATM * rvol / (R_AIR * gas_t)))
				var rp: float = _pressure_of_mass(rmass, rvol)
				rmass = rp * rvol / (R_AIR * gas_t)
				pmap[rkey] = rp
				mmap[rkey] = rmass
				vols[rkey] = rvol
				el.port_press[rname] = rp
				el.port_mass[rname] = rmass
			el.p_cap = float(el.port_press.get("a", ATM))
			el.p_rod = float(el.port_press.get("b", ATM))
			continue
		if el.kind == "air_motor":
			var mvol0: float = MotorCat.port_vol_m3(el)
			for mname in ["in", "exhaust"]:
				var mkey := "c:%d:%s" % [el.id, mname]
				var mmass: float = float(el.port_mass.get(mname, ATM * mvol0 / (R_AIR * gas_t)))
				var mp: float = _pressure_of_mass(mmass, mvol0)
				mmass = mp * mvol0 / (R_AIR * gas_t)
				pmap[mkey] = mp
				mmap[mkey] = mmass
				vols[mkey] = mvol0
				el.port_press[mname] = mp
				el.port_mass[mname] = mmass
			el.p_cap = float(el.port_press.get("in", ATM))
			el.p_rod = float(el.port_press.get("exhaust", ATM))
			continue
		if el.kind != "cylinder":
			continue
		el.q_cap = 0.0
		el.q_rod = 0.0
		for channel in ["cap", "rod"]:
			if not has_channel(el, channel):
				if channel == "cap":
					el.p_cap = ATM
				else:
					el.p_rod = ATM
				continue
			var key := "c:%d:%s" % [el.id, channel]
			var vol := chamber_volume(el, channel)
			var mass: float = el.m_cap if channel == "cap" else el.m_rod
			var pressure := _pressure_of_mass(mass, vol)
			mass = pressure * vol / (R_AIR * gas_t)
			pmap[key] = pressure
			mmap[key] = mass
			vols[key] = vol
			if channel == "cap":
				el.p_cap = pressure
				el.m_cap = mass
			else:
				el.p_rod = pressure
				el.m_rod = mass
		if str(el.brake) == "nc":
			var bkey := "c:%d:brake" % el.id
			var bvol := _brake_port_vol()
			var bmass: float = float(el.port_mass.get("brake", ATM * bvol / (R_AIR * gas_t)))
			var bp := _pressure_of_mass(bmass, bvol)
			bmass = bp * bvol / (R_AIR * gas_t)
			pmap[bkey] = bp
			mmap[bkey] = bmass
			vols[bkey] = bvol
			el.port_press["brake"] = bp
			el.port_mass["brake"] = bmass
	for wire in wires:
		var wid0: int = int(wire.id)
		if not _wire_vol_frame.has(wid0):
			continue
		var wvol: float = float(_wire_vol_frame[wid0])
		wire.vol = wvol
		var pressure := _pressure_of_mass(wire.mass, wvol)
		wire.mass = pressure * wvol / (R_AIR * gas_t)
		wire.pressure = pressure
		var key := "w:%d" % wid0
		pmap[key] = pressure
		mmap[key] = wire.mass
		vols[key] = wvol

	# acc — только учёт расхода для tip/анимации; масса уже в mmap через _pour.
	var acc := {}
	# Пути золотника и арматуры — до трубок: при переключении на выхлоп градиент
	# на рабочей линии сразу «от потребителя», а не со старым знаком потока.
	for el in elements:
		if el.kind != "valve" or not _sim_active_els.has(int(el.id)):
			continue
		var v_area: float = valve_area(el)
		for pair in ValveCat.path_pairs(el, int(el.valve_pos)):
			var ka := "c:%d:%s" % [el.id, pair[0]]
			var kb := "c:%d:%s" % [el.id, pair[1]]
			if not pmap.has(ka) or not pmap.has(kb):
				continue
			_pour({"key": ka, "p": pmap[ka]}, {"key": kb, "p": pmap[kb]}, v_area, acc, pmap, mmap, vols, h)
	for el in elements:
		if el.kind != "accessory" or not _sim_active_els.has(int(el.id)):
			continue
		_accessory_internal_flow(el, pmap, mmap, vols, acc, h)
	for el in elements:
		if el.kind != "air_motor" or not _sim_active_els.has(int(el.id)):
			continue
		_air_motor_internal_flow(el, pmap, mmap, vols, acc, h)
	# Глушитель/свободный порт ПР → ATM до трубок, чтобы выхлоп сразу тянул линию.
	for el in elements:
		if el.kind != "valve" or not _sim_active_els.has(int(el.id)):
			continue
		for name in ValveCat.port_names(el):
			if wire_on(el.id, name) != null:
				continue
			var k_atm := "c:%d:%s" % [el.id, name]
			if not pmap.has(k_atm):
				continue
			var area_atm: float = valve_area(el) * (6.0 if ValveCat.is_exhaust_port(name) else 1.0)
			_pour({"key": k_atm, "p": pmap[k_atm]}, {"key": "", "p": ATM}, area_atm, acc, pmap, mmap, vols, h)

	for wire in wires:
		var wid: int = int(wire.id)
		if not _wire_vol_frame.has(wid):
			# Электро / нет в кэше — пропускаем пневмо-шаг.
			continue
		var end_a := _endpoint(wire.a_id, wire.a_port, pmap)
		var end_b := _endpoint(wire.b_id, wire.b_port, pmap)
		if end_a.is_empty() or end_b.is_empty():
			wire.flow_m3s = 0.0
			wire.flow_vis = 0.0
			wire.flow_sign = 0.0
			wire.flow_phase = 0.0
			wire.flow_anim_speed = 0.0
			wire.flow_puff_n = 0
			continue
		var area: float = float(_wire_area_frame.get(wid, _tube_area(wire)))
		var wire_key := "w:%d" % wid
		_pour(end_a, {"key": wire_key, "p": pmap[wire_key]}, area, acc, pmap, mmap, vols, h)
		_pour({"key": wire_key, "p": pmap[wire_key]}, end_b, area, acc, pmap, mmap, vols, h)
		# Сквозной A→B после обменов (pmap уже обновлён).
		var pa: float = float(pmap[end_a["key"]]) if str(end_a["key"]) != "" else float(end_a["p"])
		var pb: float = float(pmap[end_b["key"]]) if str(end_b["key"]) != "" else float(end_b["p"])
		var pw: float = float(pmap[wire_key])
		var rho_aw: float = maxf(0.5 * (pa + pw) / (R_AIR * gas_t), 0.05)
		var rho_wb: float = maxf(0.5 * (pw + pb) / (R_AIR * gas_t), 0.05)
		var q_aw: float = mass_flow(pa, pw, area, gas_t) / rho_aw
		var q_wb: float = mass_flow(pw, pb, area, gas_t) / rho_wb
		var raw_q: float = 0.5 * (q_aw + q_wb)
		wire.flow_m3s = _latch_flow_sign(wire, raw_q, h)

	for el in elements:
		if not _sim_active_els.has(int(el.id)):
			continue
		if el.kind == "cylinder":
			if not el.open_ports:
				pass
			else:
				for port in Geom.ports(el):
					var port_name: String = port["name"]
					if wire_on(el.id, port_name) != null:
						continue
					var key := "c:%d:%s" % [el.id, port_name]
					if not pmap.has(key):
						continue
					_pour({"key": key, "p": pmap[key]}, {"key": "", "p": ATM}, _port_area(el), acc, pmap, mmap, vols, h)
		elif el.kind == "rotary_cylinder":
			# Свободный порт → атмосфера (как у арматуры).
			for port_r in Geom.ports(el):
				var prn: String = str(port_r["name"])
				if wire_on(el.id, prn) != null:
					continue
				var rkey_atm := "c:%d:%s" % [el.id, prn]
				if not pmap.has(rkey_atm):
					continue
				_pour({"key": rkey_atm, "p": pmap[rkey_atm]}, {"key": "", "p": ATM}, _open_port_atm_area(el), acc, pmap, mmap, vols, h)
		elif el.kind == "air_motor":
			for port_m in Geom.ports(el):
				var pmn: String = str(port_m["name"])
				# Глушитель на любом порту — всегда в атмосферу (даже с «занятым» tip).
				var to_atm: bool = wire_on(el.id, pmn) == null
				if MotorCat.port_is_muffler(el, pmn):
					to_atm = true
				if not to_atm:
					continue
				var mkey_atm := "c:%d:%s" % [el.id, pmn]
				if not pmap.has(mkey_atm):
					continue
				var area_m: float = _open_port_atm_area(el)
				if MotorCat.port_is_muffler(el, pmn):
					area_m *= 4.0
				_pour({"key": mkey_atm, "p": pmap[mkey_atm]}, {"key": "", "p": ATM}, area_m, acc, pmap, mmap, vols, h)
		elif el.kind == "junction":
			# Тройник/коллектор: свободный штуцер травит весь узел в атмосферу.
			var jkey := "c:%d:j" % el.id
			if not pmap.has(jkey):
				continue
			var area_j: float = _open_port_atm_area(el)
			for port_j in Geom.ports(el):
				var pjname: String = str(port_j["name"])
				if wire_on(el.id, pjname) != null:
					continue
				_pour({"key": jkey, "p": pmap[jkey]}, {"key": "", "p": ATM}, area_j, acc, pmap, mmap, vols, h)
		elif el.kind == "accessory":
			# Свободный пневмопорт → атмосфера.
			# ОК: только через седло (иначе обход).
			var acc_cls: String = str(el.accessory_class)
			if acc_cls == "check":
				continue
			for port in Geom.ports(el):
				var pname: String = str(port["name"])
				if wire_on(el.id, pname) != null:
					continue
				var key_a := "c:%d:%s" % [el.id, pname]
				if not pmap.has(key_a):
					continue
				# Сечение ≈ штуцер/трубка (не «дыра в корпус») — иначе шунтирует все остальные ветки.
				var area_a: float = _open_port_atm_area(el)
				_pour({"key": key_a, "p": pmap[key_a]}, {"key": "", "p": ATM}, area_a, acc, pmap, mmap, vols, h)

	# Масса уже применена в _pour (без глобального scale — он связывал несвязанные ветки).
	for el in elements:
		if el.kind == "cylinder" and _sim_active_els.has(int(el.id)):
			_apply_seal_leak(el, h, mmap, 1.0)

	for el in elements:
		if not _sim_active_els.has(int(el.id)):
			continue
		if el.kind == "valve":
			var vol := _valve_port_vol(el)
			for name in ValveCat.port_names(el):
				var key := "c:%d:%s" % [el.id, name]
				if not mmap.has(key):
					continue
				var mass := float(mmap[key])
				var pressure := _pressure_of_mass(mass, vol)
				mass = pressure * vol / (R_AIR * gas_t)
				el.port_mass[name] = mass
				el.port_press[name] = pressure
				var rho := maxf(pressure / (R_AIR * gas_t), 0.05)
				el.port_q[name] = float(acc.get(key, 0.0)) / rho
			continue
		if el.kind == "junction":
			var jkey := "c:%d:j" % el.id
			if mmap.has(jkey):
				var jvol := _junction_vol(el)
				var jmass := float(mmap[jkey])
				var jp := _pressure_of_mass(jmass, jvol)
				el.m_cap = jp * jvol / (R_AIR * gas_t)
				el.p_cap = jp
			continue
		if el.kind == "accessory":
			var avol2 := _accessory_port_vol(el)
			for name2 in AccLib.port_names(el):
				var akey2 := "c:%d:%s" % [el.id, name2]
				if not mmap.has(akey2):
					continue
				var amass2 := float(mmap[akey2])
				var ap2 := _pressure_of_mass(amass2, avol2)
				amass2 = ap2 * avol2 / (R_AIR * gas_t)
				el.port_mass[name2] = amass2
				el.port_press[name2] = ap2
				var arho := maxf(ap2 / (R_AIR * gas_t), 0.05)
				# tip/viz сквозной расход — один раз за кадр в _refresh_accessory_port_viz_q.
				el.port_q[name2] = float(acc.get(akey2, 0.0)) / arho
			continue
		if el.kind == "rotary_cylinder":
			var rv1: Dictionary = _rotary_chamber_vols(el)
			for rname2 in ["a", "b"]:
				var rkey2 := "c:%d:%s" % [el.id, rname2]
				if not mmap.has(rkey2):
					continue
				var rvol2: float = float(rv1[rname2])
				var rmass2: float = float(mmap[rkey2])
				var rp2: float = _pressure_of_mass(rmass2, rvol2)
				rmass2 = rp2 * rvol2 / (R_AIR * gas_t)
				el.port_mass[rname2] = rmass2
				el.port_press[rname2] = rp2
				var rrho: float = maxf(rp2 / (R_AIR * gas_t), 0.05)
				el.port_q[rname2] = float(acc.get(rkey2, 0.0)) / rrho
			el.p_cap = float(el.port_press.get("a", ATM))
			el.p_rod = float(el.port_press.get("b", ATM))
			_integrate_rotary(el, h)
			continue
		if el.kind == "air_motor":
			var mvol1: float = MotorCat.port_vol_m3(el)
			for mname2 in ["in", "exhaust"]:
				var mkey2 := "c:%d:%s" % [el.id, mname2]
				if not mmap.has(mkey2):
					continue
				var mmass2: float = float(mmap[mkey2])
				var mp2: float = _pressure_of_mass(mmass2, mvol1)
				mmass2 = mp2 * mvol1 / (R_AIR * gas_t)
				el.port_mass[mname2] = mmass2
				el.port_press[mname2] = mp2
				var mrho: float = maxf(mp2 / (R_AIR * gas_t), 0.05)
				el.port_q[mname2] = float(acc.get(mkey2, 0.0)) / mrho
			el.p_cap = float(el.port_press.get("in", ATM))
			el.p_rod = float(el.port_press.get("exhaust", ATM))
			_integrate_air_motor(el, h)
			continue
		if el.kind != "cylinder":
			continue
		for channel in ["cap", "rod"]:
			var key := "c:%d:%s" % [el.id, channel]
			if not mmap.has(key):
				continue
			var vol := chamber_volume(el, channel)
			var mass := float(mmap[key])
			var pressure := _pressure_of_mass(mass, vol)
			mass = pressure * vol / (R_AIR * gas_t)
			var rho := maxf(pressure / (R_AIR * gas_t), 0.05)
			var q := float(acc.get(key, 0.0)) / rho
			if channel == "cap":
				el.m_cap = mass
				el.p_cap = pressure
				el.q_cap = q
			else:
				el.m_rod = mass
				el.p_rod = pressure
				el.q_rod = q
		if str(el.brake) == "nc":
			var bkey2 := "c:%d:brake" % el.id
			if mmap.has(bkey2):
				var bvol2 := _brake_port_vol()
				var bmass2 := float(mmap[bkey2])
				var bp2 := _pressure_of_mass(bmass2, bvol2)
				bmass2 = bp2 * bvol2 / (R_AIR * gas_t)
				el.port_mass["brake"] = bmass2
				el.port_press["brake"] = bp2
				var brho := maxf(bp2 / (R_AIR * gas_t), 0.05)
				el.port_q["brake"] = float(acc.get(bkey2, 0.0)) / brho
		_integrate_piston(el, h)

	for wire in wires:
		var key := "w:%d" % wire.id
		if not mmap.has(key):
			continue
		wire.mass = float(mmap[key])
		wire.pressure = _pressure_of_mass(wire.mass, wire.vol)
		wire.mass = wire.pressure * wire.vol / (R_AIR * gas_t)
		wire.pressure_vis = float(wire.pressure)


func _endpoint_live_p(el: Element, port: String) -> float:
	if el == null:
		return ATM
	if str(el.kind) == "source":
		return (float(el.pressure_bar) + 1.01325) * 1.0e5
	if str(el.kind) == "junction":
		return float(el.p_cap)
	if str(el.kind) == "cylinder":
		if port == "cap":
			return float(el.p_cap)
		if port == "rod":
			return float(el.p_rod)
	if str(el.kind) == "rotary_cylinder":
		if el.get("port_press") != null and el.port_press.has(port):
			return float(el.port_press[port])
	if el.get("port_press") != null and el.port_press.has(port):
		return float(el.port_press[port])
	return ATM


## Сразу пересчитать клетку золотника после нажатия органа/дублёра (и вне step симуляции).
func refresh_valve_pos(el: Element) -> void:
	if el == null or el.kind != "valve":
		return
	_ensure_valve_ports(el)
	_update_valve_pos(el)


func _update_valve_pos(el: Element) -> void:
	var p12 := float(el.port_press.get("12", ATM))
	var p14 := float(el.port_press.get("14", ATM))
	# Внутреннее питание пилота — от порта 1.
	if str(el.pilot_supply) == "internal":
		var p1 := float(el.port_press.get("1", ATM))
		if str(el.op_left) == "pilot" or str(el.op_left) == "solenoid_pilot":
			p12 = p1 if el.command_left or str(el.op_left) == "pilot" else ATM
			# For pure pilot, pressure on 12 port matters; internal means 12 is fed from 1 when "active" via external signal - simplify: use port 12 if wired else p1 when command
			if el.port_press.has("12") and wire_on(el.id, "12") != null:
				p12 = float(el.port_press["12"])
			elif str(el.op_left) == "pilot":
				p12 = p1 # always pressurized from internal — then need external vent. Educational: pilot left uses p1 as available supply, active if command_left OR use lever-style: for pilot, pressure threshold on port 12.
		if str(el.op_right) == "pilot" or str(el.op_right) == "solenoid_pilot":
			if el.port_press.has("14") and wire_on(el.id, "14") != null:
				p14 = float(el.port_press["14"])
			elif str(el.op_right) == "pilot":
				p14 = p1
	var prev_pos: int = int(el.valve_pos)
	el.valve_pos = ValveCat.target_pos(el, p12, p14)
	# Смена клетки золотника (питание↔выхлоп) — сразу сбросить липкий знак на трубках,
	# иначе стрелки ещё секунду «идут» к потребителю вместо глушителя.
	if int(el.valve_pos) != prev_pos:
		_clear_element_wire_flow_latch(el)


func _clear_element_wire_flow_latch(el: Element) -> void:
	if el == null:
		return
	var eid: int = int(el.id)
	for w in wires:
		if int(w.a_id) != eid and int(w.b_id) != eid:
			continue
		w.flow_sign = 0.0
		w.flow_flip_t = 0.0
		w.flow_vis = 0.0
		w.flow_anim_speed = 0.0
		w.flow_puff_n = 0


func _endpoint(el_id: int, port: String, pmap: Dictionary) -> Dictionary:
	var el := get_element(el_id)
	if el == null:
		return {}
	if el.kind == "source":
		return {"key": "", "p": (el.pressure_bar + 1.01325) * 1.0e5}
	if el.kind == "junction":
		var jk := "c:%d:j" % el.id
		if not pmap.has(jk):
			return {}
		return {"key": jk, "p": pmap[jk]}
	var key := "c:%d:%s" % [el.id, port]
	if not pmap.has(key):
		return {}
	return {"key": key, "p": pmap[key]}


func _junction_vol(el: Element) -> float:
	# Учебный объём узла: растёт с числом портов (переходник — 2).
	var n: int = int(el.junction_ports)
	if str(el.junction_style) == "adapter":
		n = 2
	return 2.8e-5 * float(maxi(n, 2))


## Перенос массы src→dst за субшаг. Явный Эйлер ограничен уравниванием P —
## без перелива «трубка выше концов» и без глобального scale по всей схеме.
func _pour(src: Dictionary, dst: Dictionary, area: float, acc: Dictionary, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, h: float) -> void:
	if area <= 0.0 or h <= 1.0e-12:
		return
	var ka: String = str(src.get("key", ""))
	var kb: String = str(dst.get("key", ""))
	var pa: float = float(pmap[ka]) if ka != "" and pmap.has(ka) else float(src["p"])
	var pb: float = float(pmap[kb]) if kb != "" and pmap.has(kb) else float(dst["p"])
	var mdot: float = mass_flow(pa, pb, area, gas_t)
	if absf(mdot) < 1.0e-18:
		return
	var dm: float = mdot * h
	if ka != "" and kb != "":
		if not mmap.has(ka) or not mmap.has(kb):
			return
		var ma: float = float(mmap[ka])
		var mb: float = float(mmap[kb])
		var va: float = float(vols.get(ka, 1.0e-6))
		var vb: float = float(vols.get(kb, 1.0e-6))
		# dm_eq > 0: нужно перенести a→b до p_a = p_b.
		var dm_eq: float = (ma * vb - mb * va) / maxf(va + vb, 1.0e-15)
		if dm > 0.0:
			dm = minf(dm, maxf(dm_eq, 0.0))
			dm = minf(dm, maxf(ma - 1.0e-9, 0.0))
		else:
			dm = maxf(dm, minf(dm_eq, 0.0))
			dm = maxf(dm, -maxf(mb - 1.0e-9, 0.0))
		mmap[ka] = ma - dm
		mmap[kb] = mb + dm
		pmap[ka] = _pressure_of_mass(float(mmap[ka]), va)
		pmap[kb] = _pressure_of_mass(float(mmap[kb]), vb)
	elif ka != "" and kb == "":
		if not mmap.has(ka):
			return
		var ma2: float = float(mmap[ka])
		var va2: float = float(vols.get(ka, 1.0e-6))
		var m_atm: float = ATM * va2 / (R_AIR * gas_t)
		if dm > 0.0:
			dm = minf(dm, maxf(ma2 - m_atm, 0.0))
		else:
			dm = maxf(dm, ma2 - m_atm)
		mmap[ka] = ma2 - dm
		pmap[ka] = _pressure_of_mass(float(mmap[ka]), va2)
	elif ka == "" and kb != "":
		if not mmap.has(kb):
			return
		var mb2: float = float(mmap[kb])
		var vb2: float = float(vols.get(kb, 1.0e-6))
		var m_eq: float = pa * vb2 / (R_AIR * gas_t)
		if dm > 0.0:
			dm = minf(dm, maxf(m_eq - mb2, 0.0))
		else:
			dm = maxf(dm, -maxf(mb2 - 1.0e-9, 0.0))
		mmap[kb] = mb2 + dm
		pmap[kb] = _pressure_of_mass(float(mmap[kb]), vb2)
	else:
		return
	mdot = dm / h
	if ka != "":
		acc[ka] = float(acc.get(ka, 0.0)) - mdot
	if kb != "":
		acc[kb] = float(acc.get(kb, 0.0)) + mdot


func _apply_seal_leak(el: Element, h: float, mmap: Dictionary, scale: float) -> void:
	# Учебная утечка: bypass между полостями + чуть в атмосферу.
	var leak := clampf(float(el.seal_leak), 0.0, 1.0)
	if leak < 0.001 or el.kind != "cylinder":
		return
	var key_c := "c:%d:cap" % el.id
	var key_r := "c:%d:rod" % el.id
	if not mmap.has(key_c) or not mmap.has(key_r):
		return
	var area := 2.0e-8 * leak * leak # очень малое сопло
	var m_cross := mass_flow(el.p_cap, el.p_rod, area, gas_t) * scale * h
	mmap[key_c] = maxf(float(mmap[key_c]) - m_cross, 1.0e-9)
	mmap[key_r] = maxf(float(mmap[key_r]) + m_cross, 1.0e-9)
	var m_atm_c := mass_flow(el.p_cap, ATM, area * 0.35, gas_t) * scale * h
	var m_atm_r := mass_flow(el.p_rod, ATM, area * 0.35, gas_t) * scale * h
	mmap[key_c] = maxf(float(mmap[key_c]) - m_atm_c, 1.0e-9)
	mmap[key_r] = maxf(float(mmap[key_r]) - m_atm_r, 1.0e-9)


## Пневмомотор: расход через in→exhaust; Qn растёт со |ω| (учебная кривая).
func _air_motor_internal_flow(
	el: Element, pmap: Dictionary, mmap: Dictionary, vols: Dictionary, acc: Dictionary, h: float
) -> void:
	var kin := "c:%d:in" % el.id
	var kex := "c:%d:exhaust" % el.id
	if not pmap.has(kin) or not pmap.has(kex):
		return
	var w_free: float = MotorCat.free_omega_rad_s(el)
	var speed_f: float = clampf(absf(float(el.omega)) / maxf(w_free, 1.0), 0.0, 1.2)
	# Qn @6→5 бар → эквивалентная площадь; расход растёт со скоростью (учебная кривая).
	var qn: float = maxf(float(el.flow_nl_min), 50.0)
	var area0: float = (qn / 60000.0) / 18.0 # грубо Nl/мин → м² через типичный Δp
	var area: float = area0 * (0.12 + 0.88 * speed_f)
	_pour({"key": kin, "p": pmap[kin]}, {"key": kex, "p": pmap[kex]}, area, acc, pmap, mmap, vols, h)


func _integrate_air_motor(el: Element, h: float) -> void:
	var pin: float = float(el.port_press.get("in", ATM))
	var pex: float = float(el.port_press.get("exhaust", ATM))
	var dp: float = pin - pex
	var stall: float = MotorCat.stall_nm(el)
	var w_free: float = MotorCat.free_omega_rad_s(el)
	# Реверсивный (gear/vane): знак момента = знак перепада in−exhaust.
	var load_f: float = clampf(1.0 - absf(float(el.omega)) / maxf(w_free, 1.0), 0.0, 1.0)
	var tau: float = stall * (dp / 6.0e5) * load_f
	if absf(dp) < 0.2e5:
		tau = 0.0
	var J: float = maxf(float(el.mass_kg), 0.2) * 0.0025
	var fric: float = float(el.friction_n) * 0.02
	var viscous: float = 0.0008 * (stall / 3.0)
	if absf(el.omega) < 0.5 and absf(tau) <= fric:
		el.omega = 0.0
	else:
		tau -= signf(el.omega if absf(el.omega) > 0.5 else tau) * fric
		tau -= viscous * el.omega
		el.omega += (tau / J) * h
		el.omega = clampf(el.omega, -w_free * 1.05, w_free * 1.05)
	# ω физическая — для tip/Qn; угол 3D/УГО — учебный (ANGLE_VIS).
	# Турбина: angle_vis ∝ 1/free_rpm, иначе стробоскоп на высоких холостых.
	var angle_vis: float = MotorCat.angle_vis_factor(el)
	el.angle = wrapf(float(el.angle) + float(el.omega) * angle_vis * h, 0.0, TAU)


## Поворотный ПЦ: τ ∝ (P_a − P_b); упоры 0…θ_max; Reset → угол 0.
func _integrate_rotary(el: Element, h: float) -> void:
	var pa: float = float(el.port_press.get("a", ATM))
	var pb: float = float(el.port_press.get("b", ATM))
	# Каталожный момент @6 бар × относительный перепад (a − b).
	var tau: float = float(el.torque_nm_at_6bar) * ((pa - pb) / 6.0e5)
	var r: float = RotaryCat.pinion_radius_m(float(el.bore_mm))
	if RotaryCat.is_vane(el):
		r = RotaryCat.vane_chamber_r_m(float(el.bore_mm))
	var fric_tau: float = float(el.friction_n) * r * 0.55
	var th_max: float = deg_to_rad(float(el.angle_max_deg))
	var th: float = clampf(float(el.angle), 0.0, th_max)
	var J: float = maxf(float(el.mass_kg), 0.08) * r * r * 6.0
	var viscous: float = 0.08 * (float(el.bore_mm) / 40.0)
	if absf(el.omega) < 0.02:
		if th <= 1.0e-5 and tau <= fric_tau:
			el.angle = 0.0
			el.omega = 0.0
			return
		if th >= th_max - 1.0e-5 and tau >= -fric_tau:
			el.angle = th_max
			el.omega = 0.0
			return
	var stuck: bool = absf(el.omega) < 0.01
	if stuck and absf(tau) <= fric_tau:
		el.omega = 0.0
	else:
		if stuck:
			tau -= signf(tau) * fric_tau * 0.75
		else:
			tau -= signf(el.omega) * fric_tau * 0.75
			tau -= viscous * el.omega
		el.omega += (tau / J) * h
		el.omega = clampf(el.omega, -25.0, 25.0)
		th += el.omega * h
	if th <= 0.0:
		th = 0.0
		if el.omega < 0.0:
			el.omega = 0.0
	elif th >= th_max:
		th = th_max
		if el.omega > 0.0:
			el.omega = 0.0
	el.angle = th


func _integrate_piston(el: Element, h: float) -> void:
	var p_cap := el.p_cap if has_channel(el, "cap") else ATM
	var p_rod := el.p_rod if has_channel(el, "rod") else ATM
	var force := drive_force(el, p_cap, p_rod)
	var viscous := 40.0 * (el.bore_mm / 32.0)
	var fric := float(el.friction_n)
	var guide := str(el.guide)
	if guide == "bushing":
		viscous *= 1.25
	elif guide == "non_rot":
		fric *= 1.4
		fric = maxf(fric, 25.0 * (el.bore_mm / 32.0))
	force -= _cushion_force(el, viscous)
	force -= _bump_end_force(el, viscous)
	var stroke := _stroke_m(el)
	var brake := str(el.brake)
	var hold := fric
	if brake == "nc":
		# NC: зажат пружиной; разжим при давлении на пилотном порте (≈1.5 бар изб.).
		var p_br: float = float(el.port_press.get("brake", ATM))
		var unlocked: bool = (p_br - ATM) >= 1.5e5
		if not unlocked:
			hold = maxf(hold, 6.0e5 * PI * pow(el.bore_mm * 0.001, 2.0) * 0.25 * 0.55)
	# Жёсткий упор после остановки: сила в крышку = реакция опоры (без дребезга).
	# При ударе (есть скорость) — ниже, через демпфер/сброс v.
	if absf(el.v) < 0.02:
		if el.x <= 1.0e-6 and force <= hold:
			el.x = 0.0
			el.v = 0.0
			return
		if el.x >= stroke - 1.0e-6 and force >= -hold:
			el.x = stroke
			el.v = 0.0
			return
	# End-lock: фиксация у упора.
	if brake == "end_lock":
		var near_cap := el.x <= stroke * 0.02
		var near_rod := el.x >= stroke * 0.98
		if el.end_locked or near_cap or near_rod:
			if absf(force) < hold * 1.8:
				el.end_locked = true
				el.v = 0.0
				if near_cap:
					el.x = 0.0
				elif near_rod:
					el.x = stroke
				return
			el.end_locked = false
	var stuck := absf(el.v) < 0.003
	if stuck and absf(force) <= hold:
		el.v = 0.0
	else:
		if stuck:
			force -= signf(force) * hold * 0.75
		else:
			force -= signf(el.v) * hold * 0.75
			force -= viscous * el.v
		var acc := force / maxf(el.mass_kg, 0.02)
		el.v += acc * h
		el.v = clampf(el.v, -8.0, 8.0)
		el.x += el.v * h
	if el.x <= 0.0:
		el.x = 0.0
		if el.v < 0.0:
			# Fixed: лёгкая потеря кинетики при ударе; PPV — по игле.
			if str(el.cush_cap) == "fixed":
				el.v *= 0.35
			elif str(el.cush_cap) == "adjustable":
				el.v *= lerpf(0.08, 0.55, clampf(float(el.cush_open_cap), 0.0, 1.0))
			elif str(el.cush_cap) == "self":
				el.v *= 0.2
			else:
				el.v = 0.0
	elif el.x >= stroke:
		el.x = stroke
		if el.v > 0.0:
			if str(el.cush_rod) == "fixed":
				el.v *= 0.35
			elif str(el.cush_rod) == "adjustable":
				el.v *= lerpf(0.08, 0.55, clampf(float(el.cush_open_rod), 0.0, 1.0))
			elif str(el.cush_rod) == "self":
				el.v *= 0.2
			else:
				el.v = 0.0


func _cushion_gain(kind: String, open_amt: float, speed: float) -> float:
	match kind:
		"fixed":
			return 10.0
		"adjustable":
			# Игла: 0=закрыто → сильное торможение; 1=открыто → слабое.
			# Диапазон заметный в учебной модели (не CFD PPV).
			var closed := 1.0 - clampf(open_amt, 0.0, 1.0)
			return 6.0 + 100.0 * closed * closed
		"self":
			# PPS: сильнее при высокой скорости входа в зону.
			return 14.0 + 55.0 * clampf(absf(speed) / 1.0, 0.0, 1.0)
		_:
			return 0.0


func _cushion_force(el: Element, viscous: float) -> float:
	var stroke := _stroke_m(el)
	var drag := 0.0
	var cap_kind := str(el.cush_cap)
	var rod_kind := str(el.cush_rod)
	if cap_kind != "none" and el.v < 0.0:
		var zone := _cushion_zone_m(el, true)
		if zone > 1.0e-5 and el.x < zone:
			var depth := (zone - el.x) / zone
			var gain := _cushion_gain(cap_kind, float(el.cush_open_cap), el.v)
			var open_v := float(el.cush_open_cap) if cap_kind == "adjustable" else 0.35
			var closed := 1.0 - clampf(open_v, 0.0, 1.0) if cap_kind == "adjustable" else 0.5
			# Вязкое + «упорное» сопротивление растёт к концу зоны.
			drag += el.v * viscous * (4.0 + gain * depth * depth)
			drag += signf(el.v) * viscous * (8.0 + 45.0 * closed) * depth * depth
	if rod_kind != "none" and el.v > 0.0:
		var zone := _cushion_zone_m(el, false)
		if zone > 1.0e-5 and el.x > stroke - zone:
			var depth := (el.x - (stroke - zone)) / zone
			var gain := _cushion_gain(rod_kind, float(el.cush_open_rod), el.v)
			var open_v := float(el.cush_open_rod) if rod_kind == "adjustable" else 0.35
			var closed := 1.0 - clampf(open_v, 0.0, 1.0) if rod_kind == "adjustable" else 0.5
			drag += el.v * viscous * (4.0 + gain * depth * depth)
			drag += signf(el.v) * viscous * (8.0 + 45.0 * closed) * depth * depth
	return drag


func _bump_end_force(el: Element, viscous: float) -> float:
	# Концевые амортизаторы бесштоковой каретки (поверх камерных демпферов).
	if str(el.rod_mode) != "rodless":
		return 0.0
	var kind := str(el.bump_end)
	if kind == "" or kind == "none":
		return 0.0
	var stroke := _stroke_m(el)
	var zone := 0.004 if kind == "elastic" else 0.012
	var gain := 15.0 if kind == "elastic" else 45.0
	var drag := 0.0
	if el.v < 0.0 and el.x < zone:
		var depth := (zone - el.x) / zone
		drag += el.v * viscous * (2.0 + gain * depth)
	elif el.v > 0.0 and el.x > stroke - zone:
		var depth := (el.x - (stroke - zone)) / zone
		drag += el.v * viscous * (2.0 + gain * depth)
	return drag


func _cushion_zone_m(el: Element, cap_side: bool) -> float:
	var kind := str(el.cush_cap) if cap_side else str(el.cush_rod)
	if kind == "none":
		return 0.0
	if kind == "fixed":
		return 0.0025
	# adjustable / self: длина из ряда
	var mm := maxf(float(el.cushion_mm), 8.0)
	if kind == "self":
		mm = maxf(mm * 0.85, 10.0)
	return minf(mm * 0.001, _stroke_m(el) * 0.45)


func describe_selection() -> String:
	var wire := get_wire(selected_wire_id)
	if wire != null:
		var SimVp = preload("res://scripts/domain/sim_vis.gd")
		var tip: String = SimVp.tip_plain(wire_hover_tip(wire)).replace("\n", " · ")
		var ea = get_element(int(wire.a_id))
		var is_elec: bool = ea != null and port_domain(ea, str(wire.a_port)) == "electric"
		if is_elec:
			return tip + "  ·  " + str(wire.id_mm) + " мм²"
		var q := wire.flow_m3s * 60000.0
		return tip + "  ·  ⌀ %.1f мм  ·  %.2f бар  ·  %.1f л/мин" % [
			wire.id_mm, (wire.pressure - ATM) / 1.0e5, q,
		]
	var el := primary()
	if el == null:
		return "Схема: %d эл., %d линий  ·  t = %.2f с" % [elements.size(), wires.size(), sim_time]
	if el.kind == "source":
		return "%s  ·  уставка %.2f бар  ·  %.0f °C" % [el.tag, el.pressure_bar, el.temperature_c]
	if el.kind == "valve":
		return "%s  ·  %s  ·  поз. %d/%d  ·  L:%s R:%s" % [
			el.tag, el.order_code, int(el.valve_pos) + 1, int(el.valve_positions),
			"1" if el.command_left else "0", "1" if el.command_right else "0",
		]
	if el.kind == "rotary_cylinder":
		var pa_d: float = float(el.port_press.get("a", ATM))
		var pb_d: float = float(el.port_press.get("b", ATM))
		return "%s  ·  ∅%.0f  ·  %.0f°/%.0f°  ·  Pa %.2f  ·  Pb %.2f  ·  ω %.1f рад/с" % [
			el.tag, float(el.bore_mm), rad_to_deg(float(el.angle)), float(el.angle_max_deg),
			(pa_d - ATM) / 1.0e5, (pb_d - ATM) / 1.0e5, float(el.omega),
		]
	if el.kind == "air_motor":
		var pin_d: float = float(el.port_press.get("in", ATM))
		var rpm_d: float = absf(float(el.omega)) * 60.0 / TAU
		return "%s  ·  stall %.2f Н·м  ·  %.0f/%.0f об/мин  ·  Pin %.2f бар" % [
			el.tag, float(el.torque_nm_at_6bar), rpm_d, float(el.free_rpm),
			(pin_d - ATM) / 1.0e5,
		]
	var q_in := (el.q_cap + el.q_rod) * 60000.0
	return "%s  ·  шток %.1f / %.0f мм  ·  Pпорш %s  ·  Pшток %s  ·  F %.0f Н  ·  v %.2f м/с" % [
		el.tag,
		el.x * 1000.0,
		el.stroke_mm,
		_channel_text(el, "cap"),
		_channel_text(el, "rod"),
		drive_force(el, el.p_cap if has_channel(el, "cap") else ATM, el.p_rod if has_channel(el, "rod") else ATM),
		el.v,
	]


func _channel_text(el: Element, channel: String) -> String:
	if not has_channel(el, channel):
		return "—"
	var p := el.p_cap if channel == "cap" else el.p_rod
	return "%.2f бар" % ((p - ATM) / 1.0e5)


## --- Сохранение / загрузка сцены (.msim; JSON внутри маскирован) ---
const _MSIM_MAGIC := "MSIM"
const _MSIM_VER := 1
const _MSIM_KEY := "MechSim-MSIM-v1"


func clear_scene() -> void:
	running = false
	sim_time = 0.0
	elements.clear()
	wires.clear()
	invalidate_port_wire_index()
	invalidate_element_index()
	selected_ids.clear()
	selected_wire_id = -1
	selected_wire_ids.clear()
	selection_space = ""
	_next_id = 1
	_rail_n = 0
	_cyl_n = 0
	_rotary_n = 0
	_motor_n = 0
	_src_n = 0
	_valve_n = 0
	_junc_n = 0
	_acc_n = 0
	hint = ""


func to_scene_dict(extra: Dictionary = {}) -> Dictionary:
	var els: Array = []
	for el in elements:
		els.append(_pack_element_json(el))
	var ws: Array = []
	for wire in wires:
		ws.append(_pack_wire_json(wire))
	var data := {
		"format": "mechsim-scene",
		"version": 1,
		"elements": els,
		"wires": ws,
		"next_id": _next_id,
	}
	for k in extra.keys():
		data[k] = extra[k]
	return data


func from_scene_dict(data: Dictionary) -> String:
	if data.is_empty():
		return "Пустой файл"
	if str(data.get("format", "")) != "mechsim-scene" and not data.has("elements"):
		return "Неизвестный формат файла"
	# clear_scene сбросит history, если это не undo/redo.
	clear_scene()
	var max_id := 0
	for raw in data.get("elements", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = _json_element_to_pack(raw)
		var el := _element_from_pack(item)
		el.id = int(item.get("id", _next_id))
		max_id = maxi(max_id, el.id)
		_init_state(el, true)
		elements.append(el)
	for raw_w in data.get("wires", []):
		if typeof(raw_w) != TYPE_DICTIONARY:
			continue
		var wire := Wire.new()
		wire.id = int(raw_w.get("id", _next_id))
		wire.a_id = int(raw_w.get("a_id", 0))
		wire.a_port = str(raw_w.get("a_port", ""))
		wire.b_id = int(raw_w.get("b_id", 0))
		wire.b_port = str(raw_w.get("b_port", ""))
		wire.id_mm = float(raw_w.get("id_mm", 4.0))
		wire.od_mm = float(raw_w.get("od_mm", 0.0))
		wire.color_id = str(raw_w.get("color_id", ""))
		wire.num = int(raw_w.get("num", 0))
		wire.num_offset = _json_vec2(raw_w.get("num_offset", [0, 0]))
		wire.num_offset_b = _json_vec2(raw_w.get("num_offset_b", [0, 0]))
		wire.broken = bool(raw_w.get("broken", false))
		# Старый wire.group_id (мульти-слияние) больше не используется — сбрасываем.
		wire.group_id = 0
		wire.sleeve_yaw_a = float(raw_w.get("sleeve_yaw_a", 0.0))
		wire.sleeve_yaw_b = float(raw_w.get("sleeve_yaw_b", 0.0))
		wire.joints = []
		for jp in raw_w.get("joints", []):
			wire.joints.append(_json_vec2(jp))
		max_id = maxi(max_id, wire.id)
		_init_wire(wire)
		# Старые сцены: od не было — считаем id_mm наружным типоразмером каталога.
		if wire.od_mm < 1.0 and port_domain(get_element(wire.a_id), wire.a_port) != "electric":
			TubeFit.apply_tube_od_to_wire(wire, float(wire.id_mm))
		wires.append(wire)
	_next_id = maxi(int(data.get("next_id", max_id + 1)), max_id + 1)
	# Концевые упоры DIN — не элементы схемы; в 3D ставятся авто по краям групп.
	_strip_din_stop_elements()
	# УЗО/АВДТ: применить remap портов N/N2 на проводах.
	_apply_diff_breaker_wire_remaps()
	# DIN-клеммы: 1/1b → нечёт/чёт (до раскладки групп).
	ElectroLib.migrate_terminal_wires(self)
	migrate_rail_terminal_wires()
	renumber_wires()
	# Счётчики тегов — по фактическим обозначениям, без переименования.
	_src_n = 0
	_valve_n = 0
	_cyl_n = 0
	_rotary_n = 0
	_motor_n = 0
	_sensor_n = 0
	_junc_n = 0
	_acc_n = 0
	_rail_n = 0
	for el in elements:
		match str(el.kind):
			"source":
				_src_n += 1
			"valve":
				_valve_n += 1
			"cylinder":
				_cyl_n += 1
			"rotary_cylinder":
				_rotary_n += 1
			"air_motor":
				_motor_n += 1
			"sensor":
				_sensor_n += 1
			"junction":
				_junc_n += 1
			"accessory":
				_acc_n += 1
			"rail":
				_rail_n += 1
	# Кнопки: столбик контактов под актуатором (старые сцены могли класть сбоку).
	# Переключатель: убрать ошибочно заспавненные члены группы.
	var drop_switch_contacts: Array = []
	for el in elements:
		if str(el.kind) == "electro" and str(el.electro_class) in ["button", "e_stop"]:
			if str(el.member_role) != "contact":
				el.member_role = "main"
				el.group_id = int(el.id)
				var btn_n: int = 0
				for m in electro_group_members(int(el.id)):
					if str(m.member_role) == "contact":
						btn_n += 1
				# Без членов primary = main → портов нет (button_has_members). Дособрать.
				if btn_n == 0 and typeof(el.contact_defs) == TYPE_ARRAY and not el.contact_defs.is_empty():
					if str(el.group_template) == "":
						el.group_template = "button"
					ElectroLib.rebuild_button_contacts(self, el)
				else:
					ElectroLib.layout_button_contacts(self, el)
		elif str(el.kind) == "electro" and str(el.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			if str(el.member_role) != "contact":
				el.member_role = "main"
				el.group_id = int(el.id)
				if str(el.electro_class) == "timer_relay":
					ElectroLib.normalize_timer_relay(el)
					var tm_n: int = 0
					for m in electro_group_members(int(el.id)):
						if str(m.member_role) == "contact":
							tm_n += 1
					if tm_n != 1:
						ElectroLib.rebuild_coil_contacts(self, el)
					else:
						ElectroLib.sync_coil_contact_members(self, el)
					for m2 in electro_group_members(int(el.id)):
						if str(m2.member_role) != "contact":
							continue
						m2.delay_on = float(el.delay_on)
						m2.delay_off = float(el.delay_off)
						m2.timer_mode = str(el.timer_mode)
						m2.timer_unit = int(el.timer_unit)
						m2.timer_value = float(el.timer_value)
				else:
					var coil_n: int = 0
					for m3 in electro_group_members(int(el.id)):
						if str(m3.member_role) == "contact":
							coil_n += 1
					if coil_n == 0 and typeof(el.contact_defs) == TYPE_ARRAY and not el.contact_defs.is_empty():
						if str(el.group_template) == "":
							el.group_template = "coil"
						ElectroLib.rebuild_coil_contacts(self, el)
				ElectroLib.layout_coil_contacts(self, el)
		elif str(el.kind) == "electro" and str(el.electro_class) == "switch":
			el.group_template = ""
			ElectroLib.ensure_switch(el)
		elif str(el.kind) == "electro" and str(el.electro_class) == "supply" \
				and str(el.member_role) != "supply_leg":
			el.member_role = "main"
			el.group_id = int(el.id)
			ElectroLib.ensure_supply_legs(self, el)
		elif str(el.kind) == "electro" and str(el.member_role) == "supply_leg":
			el.electro_mount = "none"
			el.electro_class = "supply_leg"
		elif str(el.kind) == "electro" and str(el.member_role) == "contact":
			el.electro_mount = "none"
			var primary = get_element(int(el.group_id))
			if primary != null and str(primary.electro_class) == "switch":
				drop_switch_contacts.append(int(el.id))
	for cid in drop_switch_contacts:
		_remove_element(cid)
	if not _history_restoring:
		reset_history()
	return ""


func save_scene_file(path: String, extra: Dictionary = {}) -> String:
	ensure_history_snapshot()
	var text := JSON.stringify(to_scene_dict(extra), "\t")
	var raw: PackedByteArray = text.to_utf8_buffer()
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var masked: PackedByteArray = _msim_xor(packed)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Не удалось сохранить: %s" % path
	f.store_buffer(_MSIM_MAGIC.to_utf8_buffer())
	f.store_8(_MSIM_VER)
	f.store_32(masked.size())
	f.store_buffer(masked)
	f.close()
	return ""


func load_scene_file(path: String) -> Dictionary:
	## { "error": String, "data": Dictionary }
	if not FileAccess.file_exists(path):
		return {"error": "Файл не найден", "data": {}}
	var parsed = _read_scene_payload(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "Повреждённый файл сцены", "data": {}}
	var err := from_scene_dict(parsed)
	if err != "":
		return {"error": err, "data": {}}
	return {"error": "", "data": parsed}


func _read_scene_payload(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var head: PackedByteArray = f.get_buffer(4)
	if head.get_string_from_utf8() == _MSIM_MAGIC:
		var ver: int = f.get_8()
		if ver != _MSIM_VER:
			f.close()
			return null
		var n: int = f.get_32()
		if n < 0 or n > 64 * 1024 * 1024:
			f.close()
			return null
		var masked: PackedByteArray = f.get_buffer(n)
		f.close()
		if masked.size() != n:
			return null
		var packed: PackedByteArray = _msim_xor(masked)
		var raw: PackedByteArray = packed.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		if raw.is_empty():
			return null
		return JSON.parse_string(raw.get_string_from_utf8())
	f.close()
	# Устаревший открытый JSON (.mechsim.json / .json).
	var legacy = JSON.parse_string(FileAccess.get_file_as_string(path))
	return legacy if typeof(legacy) == TYPE_DICTIONARY else null


func _msim_xor(data: PackedByteArray) -> PackedByteArray:
	var key: PackedByteArray = _MSIM_KEY.to_utf8_buffer()
	if key.is_empty() or data.is_empty():
		return data
	var out := PackedByteArray()
	out.resize(data.size())
	var klen: int = key.size()
	for i in data.size():
		out[i] = data[i] ^ key[i % klen]
	return out


func _pack_element_json(el: Element) -> Dictionary:
	var d: Dictionary = el.pack()
	d["position"] = _vec2_arr(el.position)
	d["tag_offset"] = _vec2_arr(el.tag_offset)
	d["door_xy"] = _vec2_arr(el.door_xy)
	d["world_pos"] = _vec3_arr(el.world_pos)
	d["world_basis"] = _basis_arr(el.world_basis)
	var rpts: Array = []
	for p in el.rail_points:
		rpts.append(_vec2_arr(p))
	d["rail_points"] = rpts
	return d


func _pack_wire_json(wire: Wire) -> Dictionary:
	var joints: Array = []
	for p in wire.joints:
		joints.append(_vec2_arr(p))
	return {
		"id": wire.id,
		"a_id": wire.a_id,
		"a_port": wire.a_port,
		"b_id": wire.b_id,
		"b_port": wire.b_port,
		"id_mm": wire.id_mm,
		"od_mm": wire.od_mm,
		"color_id": wire.color_id,
		"num": wire.num,
		"num_offset": _vec2_arr(wire.num_offset),
		"num_offset_b": _vec2_arr(wire.num_offset_b),
		"broken": wire.broken,
		"group_id": wire.group_id,
		"sleeve_yaw_a": wire.sleeve_yaw_a,
		"sleeve_yaw_b": wire.sleeve_yaw_b,
		"joints": joints,
	}


func _json_element_to_pack(raw: Dictionary) -> Dictionary:
	var item := raw.duplicate(true)
	item["position"] = _json_vec2(raw.get("position", [0, 0]))
	item["tag_offset"] = _json_vec2(raw.get("tag_offset", [0, 0]))
	item["world_pos"] = _json_vec3(raw.get("world_pos", [0, 0, 0]))
	item["world_basis"] = _json_basis(raw.get("world_basis", null))
	return item


static func _vec2_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func _vec3_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _basis_arr(b: Basis) -> Array:
	return [
		[b.x.x, b.x.y, b.x.z],
		[b.y.x, b.y.y, b.y.z],
		[b.z.x, b.z.y, b.z.z],
	]


static func _json_vec2(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary:
		return Vector2(float(v.get("x", 0)), float(v.get("y", 0)))
	return Vector2.ZERO


static func _json_vec3(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Dictionary:
		return Vector3(float(v.get("x", 0)), float(v.get("y", 0)), float(v.get("z", 0)))
	return Vector3.ZERO


static func _json_basis(v) -> Basis:
	if v is Basis:
		return v
	if v is Array and v.size() >= 3:
		var x := _json_vec3(v[0])
		var y := _json_vec3(v[1])
		var z := _json_vec3(v[2])
		return Basis(x, y, z)
	return Basis.IDENTITY
