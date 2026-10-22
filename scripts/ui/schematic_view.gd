extends Control
## Поле схемы: перенос элементов, ортогональные линии связи, меню и масштаб.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const Catalog = preload("res://scripts/domain/cylinder_catalog.gd")
const ValveCat = preload("res://scripts/domain/valve_catalog.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
const ValveLib = preload("res://scripts/domain/valve_library.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const ElectroSymbols = preload("res://scripts/domain/electro_symbols.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
const WireTrunks2D = preload("res://scripts/domain/wire_trunks_2d.gd")
const WireBreak2D = preload("res://scripts/domain/wire_break_2d.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")
const BaseLayerScript = preload("res://scripts/ui/schematic_base_layer.gd")
const LiveLayerScript = preload("res://scripts/ui/schematic_live_layer.gd")
const AnimLayerScript = preload("res://scripts/ui/schematic_anim_layer.gd")
const UgoLayerScript = preload("res://scripts/ui/schematic_ugo_layer.gd")
const DragGhostScript = preload("res://scripts/ui/schematic_drag_ghost.gd")

var circuit = null
var font: Font
var zoom := 1.0
var pan := Vector2(48, 56)
var armed_kind := ""

var _mode := ""
var _press := Vector2.ZERO
var _moved := false
var _grab_id := -1
var _grab_port := ""
var _part_kind := ""
var _origins := {}
var _wire_from_id := -1
var _wire_from_port := ""
var _rail_edit_id := -1
var _rail_edit_vertex := -1
var _rail_edit_seg := -1
## Якорь конца шины на время тяги — чтобы не нарастали «ступеньки».
var _rail_edit_anchor := -1
var _rail_edit_from_start: bool = false
## Снимок коридора до rail_edit — жилы сдвигаем на release.
var _rail_edit_poly0: PackedVector2Array = PackedVector2Array()
var _rail_edit_wire_ids: Array = []
var _hover_port := ""
var _hover_id := -1
var _hover_part := ""
var _hover_part_id := -1
var _hover_body_id := -1
var _hover_sig_bound := false
var _tag_drag_id := -1
var _tag_drag_origin := Vector2.ZERO
var _tag_press_world := Vector2.ZERO
## Перетаскивание таблицы Конт./Цепь внутри БП / прибора.
var _device_table_id := -1
var _device_table_side := "" # "left" | "right" — логическая таблица
var _device_table_dy0 := 0.0
var _device_table_press_world := Vector2.ZERO
var _device_table_flipped := false
## Origin (commit) vs preview (призрак); el не мутируем до отпускания.
var _device_table_origin_dy_l := 0.0
var _device_table_origin_dy_r := 0.0
var _device_table_origin_edge_l := "left"
var _device_table_origin_edge_r := "right"
var _device_table_prev_dy_l := 0.0
var _device_table_prev_dy_r := 0.0
var _device_table_prev_edge_l := "left"
var _device_table_prev_edge_r := "right"
## Перетаскивание номера линии (как tag_offset у элементов).
var _num_drag_wire_id := -1
var _num_drag_end := "" # "mid" | "a" | "b"
var _num_drag_origin := Vector2.ZERO
var _num_press_world := Vector2.ZERO
var _menu_world := Vector2.ZERO
var _marquee := Rect2()
var _ctx: PanelContainer
## Все белые плавающие панели (включая закреплённые пином).
var _float_panels: Array = []
var _paperclip_tex: Texture2D
var _props_win: PanelContainer
var _props_host: VBoxContainer
var _props_title: Label
var _props_dragging := false
var _props_drag_off := Vector2.ZERO
## Куда временно вешаем панель (оверлей 3D); null = эта схема.
var _props_place_host: Control = null
## Хост для float-панели частей/общего (оверлей 3D).
var _float_place_host: Control = null
## Хост оверлея 3D, пока открыт ЛКМ-список выбора.
var _hit_picker_3d_host: Control = null
var _tip: PanelContainer
var _tip_label: RichTextLabel
var _tip_screen := Vector2.ZERO
var _bend_wire_id := -1
var _bend_kind := ""
var _bend_index := -1
var _bend_in_h := true
var _bend_out_h := false
var _seg_ready := false
var _seg_h := true
var _seg_j0 := -1
var _seg_j1 := -1
var _envelope_open := -1 # индекс раскрытого каталога клетки
var _props_section_idx := 0
var _props_el_id := -1
var _actuate_side := "" # left/right во время симуляции
## Perf: Base shell заморожен при Run; ПЦ/золотник — SchemeAnim (отдельные Node2D).
var _sim_redraw_accum: float = 0.0
const RUN_BASE_HZ := 3.0
const RUN_BASE_HZ_PRESS := 4.0
var _hover_prev_el: int = -2
var _hover_prev_port: String = ""
var _hover_prev_wire: int = -2
var _hover_prev_part: String = ""
var _hover_prev_part_id: int = -2
## Якорь излома под курсором: "wid:kind:index" (подсветка ручки).
var _hover_grip_key: String = ""
var _hover_prev_grip_key: String = ""
var _cached_wire_paths: Array = []
var _cached_trunk_data: Dictionary = {}
var _perf_ms_draw: float = 0.0
var _perf_ms_base: float = 0.0
var _perf_ms_live: float = 0.0
var _force_full_redraw: bool = false
var _world_root: Node2D
var _base_layer: Node2D
var _ugo_layer: Node2D
var _anim_layer: Node2D
var _live_layer: Node2D
var _paths_dirty: bool = true
## Число жил на прошлый scene_changed (−1 = ещё не синхронизировано).
var _scene_wire_count_cached: int = -1
## Последняя строка хоткеев внизу — чтобы обновлять chrome при смене выделения.
var _hotkey_help_cached: String = ""
var _was_running: bool = false
var _live_draw_busy: bool = false
var _base_draw_busy: bool = false
var _base_pending_sim_control: bool = false
## Последняя эпоха circuit.scheme_control_epoch (АВ выбил → Base).
var _scheme_ctrl_epoch: int = -1
## Zoom/pan/split во время busy Base — иначе толщина жил остаётся от старого zoom.
var _base_pending_zoom: bool = false
## После сплита/toggle 2Д|3Д: size ещё 0 или canvas сброшен — ждём resized / повторный redraw.
var _need_relayout_redraw: bool = false
var _size_redraw_queued: bool = false
## Hover не делает полный Base — только лёгкий Live.
var _live_pending: bool = false
var _live_last_msec: int = 0
const LIVE_MIN_GAP_MSEC := 50
## Счётчики для диагностики: сколько раз реально вызвали _draw слоёв.
var _dbg_base_draws: int = 0
var _dbg_base_reqs: int = 0
var _dbg_live_draws: int = 0
var _dbg_scene_changed: int = 0
var _dbg_last_base_reason: String = ""
var _base_last_req_msec: int = 0
var _base_last_draw_msec: int = 0
## Во время drag эти id не рисуем на Base (остаются на Live) — без полного redraw схемы.
var _drag_omit_ids: Dictionary = {}
## Ghost-drag: Node2D-призраки; el.position / провода — только на отпускании.
var _drag_ghosts: Dictionary = {} # id -> Node2D
var _drag_delta: Vector2 = Vector2.ZERO
## Ручная ортогональная проводка (без автороута).
var _wire_joints: Array = [] # промежуточные точки (world), без tip’ов концов
var _wire_anchor: Vector2 = Vector2.ZERO # tip стартового порта или последняя точка
var _tip_refresh_accum: float = 0.0
const TIP_REFRESH_HZ := 10.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = FOCUS_ALL
	# Раньше main_shell: успеть поставить defer_step до circuit.step в том же кадре.
	process_priority = 100
	_setup_draw_layers()
	_ctx = _create_float_panel()
	_float_panels.append(_ctx)
	add_child(_ctx)
	_setup_tip()
	_setup_props_window()
	apply_ui_theme()
	# Node2D-слои не перерисовываются сами при смене size Control (toggle 2Д|3Д / сплит).
	if not resized.is_connected(_on_schematic_resized):
		resized.connect(_on_schematic_resized)


func _setup_draw_layers() -> void:
	_world_root = Node2D.new()
	_world_root.name = "SchemeWorld"
	_world_root.z_index = 0
	add_child(_world_root)
	_base_layer = BaseLayerScript.new()
	_base_layer.name = "SchemeBase"
	_base_layer.owner_view = self
	_base_layer.z_index = 0
	_world_root.add_child(_base_layer)
	_ugo_layer = UgoLayerScript.new()
	_ugo_layer.name = "SchemeUgo"
	_ugo_layer.owner_view = self
	_ugo_layer.z_index = 1
	_world_root.add_child(_ugo_layer)
	_anim_layer = AnimLayerScript.new()
	_anim_layer.name = "SchemeAnim"
	_anim_layer.owner_view = self
	_anim_layer.z_index = 2
	_world_root.add_child(_anim_layer)
	_live_layer = LiveLayerScript.new()
	_live_layer.name = "SchemeLive"
	_live_layer.owner_view = self
	_live_layer.z_index = 3
	_world_root.add_child(_live_layer)
	_sync_world_xform()


func _sync_world_xform() -> void:
	if _world_root == null:
		return
	# Не трогать transform без изменения — иначе Godot может перерисовать Base/Live.
	if _world_root.position != pan:
		_world_root.position = pan
	var zs := Vector2(zoom, zoom)
	if _world_root.scale != zs:
		_world_root.scale = zs


func _request_base(reason: String = "") -> void:
	if _base_layer == null:
		return
	if _base_draw_busy:
		if reason == "sim_control":
			_base_pending_sim_control = true
		elif reason == "zoom" or reason == "pan" or reason == "split":
			_base_pending_zoom = true
		return
	# Жёсткий потолок при Run (кроме invalidate / drag топологии / start-stop / zoom).
	if circuit != null and (bool(circuit.running) or float(circuit.sim_time) > 0.0):
		var force: bool = (
			reason == "run_toggle"
			or reason == "invalidate"
			or reason == "anim_end"
			or reason == "sim_control"
			or reason == "zoom"
			or reason == "pan"
			or reason == "drag_end"
			or reason == "scene_changed"
			or reason == "split"
			or reason in [
				"interact:move", "interact:bend", "interact:wire", "interact:rail_edit",
				"interact:wire_num", "interact:tag", "interact:down",
			]
		)
		if not force:
			var now_m: int = Time.get_ticks_msec()
			var hz: float = RUN_BASE_HZ_PRESS if bool(circuit.pressure_viz) else RUN_BASE_HZ
			var gap_m: int = int(1000.0 / hz)
			if _base_last_req_msec > 0 and (now_m - _base_last_req_msec) < gap_m:
				return
			_base_last_req_msec = now_m
	if reason != "":
		_dbg_last_base_reason = reason
	_dbg_base_reqs += 1
	if _base_layer.has_method("request_draw"):
		_base_layer.request_draw()
	else:
		_base_layer.queue_redraw()


func _tick_sim_base_redraw(dt: float) -> void:
	_sim_redraw_accum += dt
	var hz: float = RUN_BASE_HZ_PRESS if bool(circuit.pressure_viz) else RUN_BASE_HZ
	if _sim_redraw_accum >= 1.0 / hz and not _base_draw_busy:
		_sim_redraw_accum = 0.0
		_request_base("sim_tick")


func _motion_layer_active() -> bool:
	## SchemeAnim только при Run (чёткий vector в edit; без texture-blur).
	return circuit != null and bool(circuit.running)


func _use_ugo_sprites() -> bool:
	## Texture-bake УГО отключён: блюр + фризы от SubViewport. Канон — vector _draw.
	return false


func _sync_anim_only(force_redraw: bool = false) -> void:
	if _ugo_layer != null:
		_ugo_layer.visible = false
	if _anim_layer != null and _anim_layer.has_method("sync"):
		_anim_layer.sync(circuit, font, _motion_layer_active(), force_redraw)


func _tick_run_layers(_dt: float) -> void:
	_sync_anim_only()
	# АВ/защита сработали в сети — Base при Run иначе залипает (двоение ключа с Live).
	if circuit != null:
		var ep: int = int(circuit.scheme_control_epoch)
		if ep != _scheme_ctrl_epoch:
			_scheme_ctrl_epoch = ep
			notify_sim_control_changed()
	if bool(circuit.running):
		if _live_pending and not _live_draw_busy:
			var gap_ok: bool = (Time.get_ticks_msec() - _live_last_msec) >= LIVE_MIN_GAP_MSEC
			if gap_ok:
				_request_live(true)
	else:
		_tick_sim_base_redraw(_dt)
		if _live_pending and not _live_draw_busy:
			var gap_ok2: bool = (Time.get_ticks_msec() - _live_last_msec) >= LIVE_MIN_GAP_MSEC
			if gap_ok2:
				_request_live(true)


func _request_live(immediate: bool = false) -> void:
	if _live_layer == null:
		return
	if not immediate:
		var now_m: int = Time.get_ticks_msec()
		if _live_draw_busy or (now_m - _live_last_msec) < LIVE_MIN_GAP_MSEC:
			_live_pending = true
			return
	_live_pending = false
	_live_layer.queue_redraw()


func _schedule_live() -> void:
	## Hover/3D: только лёгкий Live (рамка), не Base со всеми УГО.
	_live_pending = true


## Публично: наведение из 3D/оверлея — только Live (рамка), без полного Base.
func notify_external_hover() -> void:
	_schedule_live()


## 3D (или агент) изменил орган/кнопку — сразу обновить УГО на схеме при Run.
func notify_sim_control_changed() -> void:
	_request_base("sim_control")
	_request_live(true)


## Агент: удержание органа ПР (_mode=actuate) как при зажатой кнопке на УГО.
func agent_set_actuate_hold(el_id: int, side: String, on: bool) -> void:
	if on:
		_mode = "actuate"
		_actuate_side = side
		_grab_id = el_id
		_request_base("sim_tick")
		_request_live(true)
	else:
		if _mode == "actuate":
			_mode = ""
			_actuate_side = ""
			_grab_id = -1
			_request_base("sim_tick")
			_request_live(true)


func _request_both(reason: String = "") -> void:
	_request_base(reason)
	_request_live()


func _invalidate_scheme() -> void:
	_paths_dirty = true
	_drag_omit_ids.clear()
	_clear_drag_ghosts()
	_drag_delta = Vector2.ZERO
	_sync_world_xform()
	_request_both("invalidate")
	queue_redraw()
	_sync_anim_only()


## Публично: полная перерисовка схемы (после open/load из main_shell).
func redraw_scheme() -> void:
	_invalidate_scheme()


## Расставить подписи УГО: справа → CCW, без наложения на тела/жилы/другие подписи.
func auto_place_element_tags(force_overlapping: bool = false) -> void:
	if circuit == null or font == null:
		return
	_ensure_wire_paths()
	var body_rects: Array = []
	for el0 in circuit.elements:
		if ElectroLib.hidden_on_scheme(el0) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el0):
			continue
		body_rects.append({"id": int(el0.id), "rect": Geom.world_bounds(el0).grow(2.0)})
	var occupied: Array = []
	for el in circuit.elements:
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		if str(el.tag) == "":
			continue
		var cur_off: Vector2 = el.tag_offset if el.get("tag_offset") != null else Vector2.ZERO
		if typeof(cur_off) != TYPE_VECTOR2:
			cur_off = Vector2.ZERO
		var cur_box: Rect2 = Geom.tag_world_box(el, font, 13).grow(2.0)
		var overlaps_body: bool = false
		if force_overlapping or cur_off.length_squared() <= 0.25:
			for item in body_rects:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				if int(item.get("id", -1)) == int(el.id):
					continue
				if (item.get("rect", Rect2()) as Rect2).intersects(cur_box):
					overlaps_body = true
					break
			# Свой корпус тоже: подпись не должна лежать поверх УГО.
			if not overlaps_body:
				var own: Rect2 = Geom.world_bounds(el).grow(1.0)
				if own.intersects(cur_box):
					overlaps_body = true
		if cur_off.length_squared() > 0.25 and not (force_overlapping and overlaps_body):
			occupied.append(cur_box)
			continue
		if cur_off.length_squared() > 0.25 and force_overlapping and not overlaps_body:
			occupied.append(cur_box)
			continue
		el.tag_offset = Geom.auto_tag_offset(el, font, 13, body_rects, _cached_wire_paths, occupied)
	_request_both("tag_auto")
	queue_redraw()


## Ревью: все электро-жилы — визуальный обрыв; у катушек/КМ — скрыть неиспользуемые контакты.
func apply_review_break_and_hide_unused() -> void:
	if circuit == null:
		return
	for w in circuit.wires:
		var a = circuit.get_element(int(w.a_id))
		if a == null:
			continue
		if Geom.port_domain(a, str(w.a_port)) != "electric":
			continue
		w.broken = true
	for el in circuit.elements:
		if str(el.kind) != "electro":
			continue
		if str(el.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			el.hide_unused_contacts = true
	circuit.touch_scene()
	_paths_dirty = true
	auto_place_element_tags()
	_request_both("review_flags")
	queue_redraw()


## Пометить: после layout нужен redraw (reparent сплита / hide 3Д).
func arm_viewport_relayout() -> void:
	_need_relayout_redraw = true


func _on_schematic_resized() -> void:
	if not _need_relayout_redraw and not _size_redraw_queued:
		# Обычный resize сплита без arm — тоже нужен redraw (иначе жилы пропадают до pan).
		_need_relayout_redraw = true
	if _size_redraw_queued:
		return
	_size_redraw_queued = true
	call_deferred("_flush_size_redraw")


func _flush_size_redraw() -> void:
	_size_redraw_queued = false
	if not _need_relayout_redraw:
		return
	notify_viewport_relayout()


## После сплита/переключения 2Д|3Д: size мог быть 0 → пустой canvas; force redraw когда size валиден.
func notify_viewport_relayout() -> void:
	_sync_world_xform()
	if size.x < 8.0 or size.y < 8.0:
		_need_relayout_redraw = true
		return
	_need_relayout_redraw = false
	_request_base("split")
	_request_live(true)
	queue_redraw()
	_sync_anim_only()


func _ensure_wire_paths() -> void:
	if circuit == null:
		return
	ElectroSymbols.scheme_circuit = circuit
	# Кэш валиден и в edit/move: ghost-drag не меняет tip до отпускания — не перетрассировать.
	var reuse_paths: bool = (
		not _paths_dirty
		and _cached_wire_paths.size() == circuit.wires.size()
		and not _cached_wire_paths.is_empty()
		and (
			_mode == "" or _mode == "move" or _mode == "down"
			or _mode == "bend" or _mode == "rail_edit"
		)
	)
	if reuse_paths:
		return
	# Add одной жилы в конец: не перетрассировать всю схему (фриз на 70+).
	var n_w: int = circuit.wires.size()
	var n_c: int = _cached_wire_paths.size()
	if _paths_dirty and n_c > 0 and n_w == n_c + 1 and (_mode == "" or _mode == "wire"):
		WireRouter2D.prepare(circuit)
		var wire_paths_inc: Array = _cached_wire_paths.duplicate()
		for wi in range(n_c, n_w):
			wire_paths_inc.append(_wire_path(circuit.wires[wi]))
		WireRouter2D.end_batch()
		_cached_wire_paths = wire_paths_inc
		_cached_trunk_data = WireTrunks2D.build(circuit, wire_paths_inc)
		_paths_dirty = false
		return
	WireRouter2D.prepare(circuit)
	var wire_paths: Array = []
	for wire in circuit.wires:
		wire_paths.append(_wire_path(wire))
	WireRouter2D.end_batch()
	_cached_wire_paths = wire_paths
	_cached_trunk_data = WireTrunks2D.build(circuit, wire_paths)
	_paths_dirty = false


func _bind_layer_meta(_ci: CanvasItem, p_max_over: float = 0.0) -> void:
	# Контекст в SymbolGeom — без set_meta на рисуемом слое (иначе повторный _draw).
	Geom.begin_sch_layer_draw(zoom, pan, true, _cached_wire_paths, p_max_over, circuit)


func _clear_layer_meta(_ci: CanvasItem) -> void:
	Geom.end_sch_layer_draw()


func _view_rect_world() -> Rect2:
	var view_a: Vector2 = _screen_to_world(Vector2.ZERO)
	var view_b: Vector2 = _screen_to_world(size)
	# Запас в мире растёт при отдалении — иначе тонкие длинные жилы клипаются по краю.
	var pad: float = maxf(120.0, 80.0 / maxf(zoom, 0.2))
	return Rect2(view_a, view_b - view_a).abs().grow(pad)


## Отрезок пересекает AABB (включая касание / конец внутри).
func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var r2: Rect2 = r.abs()
	# Ортогональные жилы схемы — быстрый тест; иначе Liang-Barsky-лайт.
	var minx: float = minf(a.x, b.x)
	var maxx: float = maxf(a.x, b.x)
	var miny: float = minf(a.y, b.y)
	var maxy: float = maxf(a.y, b.y)
	if maxx < r2.position.x or minx > r2.end.x or maxy < r2.position.y or miny > r2.end.y:
		return false
	# Горизонталь / вертикаль (типичный ortho-route).
	if absf(a.y - b.y) < 0.51:
		return a.y >= r2.position.y and a.y <= r2.end.y \
				and maxx >= r2.position.x and minx <= r2.end.x
	if absf(a.x - b.x) < 0.51:
		return a.x >= r2.position.x and a.x <= r2.end.x \
				and maxy >= r2.position.y and miny <= r2.end.y
	# Диагональ (редко): bbox уже пересекается.
	return true


## Жила видна, если любой сегмент пересекает viewport (не только tip / первые 6 точек).
func _path_visible_in_view(pts: PackedVector2Array, view: Rect2) -> bool:
	if pts.size() < 2:
		return false
	for i in range(pts.size() - 1):
		if _segment_hits_rect(pts[i], pts[i + 1], view):
			return true
	return false


func _setup_tip() -> void:
	# Тема тултипа (светлая бумага / тёмный вариант) — не серый OS-tooltip.
	_tip = PanelContainer.new()
	_tip.name = "SchemeTip"
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.z_index = 50
	var paper := StyleBoxFlat.new()
	paper.bg_color = UiTheme.tooltip_bg()
	paper.border_color = UiTheme.tooltip_border()
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(4)
	paper.shadow_size = 0
	paper.content_margin_left = 8
	paper.content_margin_right = 8
	paper.content_margin_top = 5
	paper.content_margin_bottom = 5
	_tip.add_theme_stylebox_override("panel", paper)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.scroll_active = false
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_label.add_theme_font_override("normal_font", UiTheme.font_regular())
	_tip_label.add_theme_font_override("bold_font", UiTheme.font_tip_bold())
	_tip_label.add_theme_font_size_override("normal_font_size", 12)
	_tip_label.add_theme_font_size_override("bold_font_size", 12)
	_tip_label.add_theme_color_override("default_color", UiTheme.tooltip_fg())
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_label)
	add_child(_tip)


func _setup_props_window() -> void:
	# Та же белая «бумага», что у меню частей — без OS-Window и серой focus-рамки.
	_props_win = PanelContainer.new()
	_props_win.name = "PropertiesPanel"
	_props_win.visible = false
	_props_win.mouse_filter = Control.MOUSE_FILTER_STOP
	_props_win.z_index = 40
	# Не раздуваем min-size схемы, пока панель скрыта.
	_props_win.custom_minimum_size = Vector2.ZERO
	var paper := StyleBoxFlat.new()
	paper.bg_color = UiTheme.paper()
	paper.border_color = UiTheme.paper_border()
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(6)
	paper.shadow_size = 0
	paper.content_margin_left = 8
	paper.content_margin_right = 8
	paper.content_margin_top = 6
	paper.content_margin_bottom = 8
	_props_win.add_theme_stylebox_override("panel", paper)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_props_win.add_child(root)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_row.gui_input.connect(_on_props_title_input)
	root.add_child(title_row)
	_props_title = Label.new()
	_props_title.text = "Свойства"
	_props_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props_title.add_theme_font_size_override("font_size", 14)
	_props_title.add_theme_color_override("font_color", UiTheme.paper_text())
	_props_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_props_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_color_override("font_color", UiTheme.paper_muted())
	close_btn.add_theme_color_override("font_hover_color", UiTheme.accent_hot())
	close_btn.pressed.connect(close_properties)
	title_row.add_child(close_btn)
	# Без внешнего ScrollContainer: иначе вертикальный бар сжимает ширину и режет
	# секционный ряд (nav + внутренний scroll). Скролл — только внутри секций/списков.
	_props_host = VBoxContainer.new()
	_props_host.add_theme_constant_override("separation", 4)
	_props_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_props_host)
	add_child(_props_win)


func _props_clamp_host() -> Control:
	var p: Node = _props_win.get_parent() if _props_win != null else null
	if p is Control:
		return p as Control
	return self


func _reparent_props_to(host: Control) -> void:
	if _props_win == null or host == null:
		return
	if _props_win.get_parent() == host:
		return
	var was_vis: bool = _props_win.visible
	var gpos: Vector2 = _props_win.global_position
	var cur: Node = _props_win.get_parent()
	if cur != null:
		cur.remove_child(_props_win)
	host.add_child(_props_win)
	_props_win.visible = was_vis
	if was_vis:
		_props_win.global_position = gpos


func _on_props_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_props_dragging = event.pressed
		if event.pressed:
			_props_drag_off = _props_win.get_global_mouse_position() - _props_win.global_position
		accept_event()
	elif event is InputEventMouseMotion and _props_dragging:
		var gp := _props_win.get_global_mouse_position() - _props_drag_off
		var host: Control = _props_clamp_host()
		var local: Vector2 = host.get_global_transform().affine_inverse() * gp
		_props_win.position = Vector2(
			clampf(local.x, 4.0, maxf(4.0, host.size.x - _props_win.size.x - 4.0)),
			clampf(local.y, 4.0, maxf(4.0, host.size.y - _props_win.size.y - 4.0))
		)
		accept_event()


func apply_ui_theme() -> void:
	_style_float_panel(_ctx)
	for p in _float_panels:
		if p != null and is_instance_valid(p):
			_style_float_panel(p)
	if _tip_label:
		_tip_label.add_theme_font_override("normal_font", UiTheme.font_regular())
		_tip_label.add_theme_font_override("bold_font", UiTheme.font_tip_bold())
		_tip_label.add_theme_color_override("default_color", UiTheme.tooltip_fg())
	if _tip:
		var tip_panel := StyleBoxFlat.new()
		tip_panel.bg_color = UiTheme.tooltip_bg()
		tip_panel.border_color = UiTheme.tooltip_border()
		tip_panel.set_border_width_all(1)
		tip_panel.set_corner_radius_all(4)
		tip_panel.content_margin_left = 8
		tip_panel.content_margin_right = 8
		tip_panel.content_margin_top = 5
		tip_panel.content_margin_bottom = 5
		_tip.add_theme_stylebox_override("panel", tip_panel)
	_invalidate_scheme()


func _process(dt: float) -> void:
	if circuit == null:
		return
	_ensure_hover_bind()
	_ensure_scene_bind()
	var now_running: bool = bool(circuit.running)
	if now_running != _was_running:
		_was_running = now_running
		# Старт/стоп: пересобрать Base (скелет) и сбросить Live.
		if not now_running:
			_paths_dirty = true
		_request_both("run_toggle")
		_sync_anim_only(true)
		queue_redraw()
	var any_float := false
	for p in _float_panels:
		if p != null and is_instance_valid(p) and p.visible:
			any_float = true
			break
	var overlay := (_props_win != null and _props_win.visible) or any_float
	var interacting: bool = _mode != "" or _force_full_redraw
	_refresh_hotkey_help_bar()
	if interacting:
		_force_full_redraw = false
		# Удержание органа ПР / кнопки: топология не едет — нельзя полный Base каждый кадр
		# (иначе при выдвижении ПЦ FPS падает до ~25).
		if _mode == "pan":
			_sync_world_xform()
		elif _mode in ["actuate", "electro_btn"]:
			_tick_run_layers(dt)
		elif _mode in ["move", "down", "device_table"]:
			# Ghost Node2D уже обновлён в motion — без redraw Base/Live и без reroute.
			pass
		elif _mode == "wire":
			_request_live(true)
		elif _mode == "bend":
			# Только затронутая жила — не полный Base на каждый motion.
			if _bend_wire_id >= 0:
				WireRouter2D.invalidate_wire(_bend_wire_id)
				var aff_b: Dictionary = {_bend_wire_id: true}
				_patch_cached_wire_paths(aff_b)
			_request_live(true)
			queue_redraw()
		elif _mode == "rail_edit":
			# Призрак: только Live (контур rail). Не dirty paths / Base — иначе фриз и
			# жилы «притягиваются» к rail с диагоналями на каждый motion.
			_request_live(true)
		elif _mode in ["wire_num", "tag"]:
			_paths_dirty = true
			_request_both("interact:" + _mode)
			queue_redraw()
		else:
			_request_live()
			queue_redraw()
		_refresh_tip_while_sim(dt)
		return
	if overlay:
		_tick_run_layers(dt)
		_refresh_tip_while_sim(dt)
		return
	if circuit.running or circuit.sim_time > 0.0:
		_tick_run_layers(dt)
		_refresh_tip_while_sim(dt)
		return
	_sync_anim_only()
	if _live_pending and not _live_draw_busy:
		var gap_edit: bool = (Time.get_ticks_msec() - _live_last_msec) >= LIVE_MIN_GAP_MSEC
		if gap_edit:
			_request_live(true)


func _create_float_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "FloatPanel"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 30
	panel.set_meta("pinned", false)
	panel.set_meta("el_id", -1)
	panel.set_meta("part", "")
	panel.set_meta("dragging", false)
	panel.set_meta("drag_off", Vector2.ZERO)
	_style_float_panel(panel)
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 4)
	panel.add_child(root)
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_row.gui_input.connect(_on_float_title_input.bind(panel))
	root.add_child(title_row)
	var title := Label.new()
	title.name = "Title"
	title.text = ""
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UiTheme.paper_text())
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)
	var pin := Button.new()
	pin.name = "Pin"
	pin.toggle_mode = true
	pin.focus_mode = Control.FOCUS_NONE
	pin.custom_minimum_size = Vector2(28, 28)
	pin.tooltip_text = "Закрепить (не закрывать по клику мимо)"
	pin.icon = _paperclip_icon()
	pin.expand_icon = true
	_style_pin_btn(pin, false)
	pin.toggled.connect(func(on: bool):
		_on_float_pin_toggled(panel, on)
	)
	title_row.add_child(pin)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	return panel


func _style_float_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.paper()
	style.border_color = UiTheme.paper_border()
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_size = 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)


func _paperclip_icon() -> Texture2D:
	if _paperclip_tex != null:
		return _paperclip_tex
	var path := "res://assets/ui/paperclip_pin.png"
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			_paperclip_tex = loaded as Texture2D
			return _paperclip_tex
	# Fallback, если PNG ещё не импортирован.
	var s: int = 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.15, 0.16, 0.18, 1.0)
	for t in 48:
		var u: float = float(t) / 47.0
		var ang: float = PI * 0.25
		var cx: float = 8.0 + cos(ang) * (u - 0.5) * 10.0
		var cy: float = 8.0 - sin(ang) * (u - 0.5) * 10.0
		var wobble: float = sin(u * TAU * 1.5) * 1.8
		var px: int = int(round(cx + cos(ang + PI * 0.5) * wobble))
		var py: int = int(round(cy + sin(ang + PI * 0.5) * wobble))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x: int = px + dx
				var y: int = py + dy
				if x >= 0 and y >= 0 and x < s and y < s:
					img.set_pixel(x, y, ink)
	_paperclip_tex = ImageTexture.create_from_image(img)
	return _paperclip_tex


func _style_pin_btn(btn: Button, on: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiTheme.field_active() if on else Color(0, 0, 0, 0)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UiTheme.field_active()
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("hover_pressed", hover)
	btn.modulate = UiTheme.accent_hot() if on else UiTheme.paper_text()


func _on_float_pin_toggled(panel: PanelContainer, on: bool) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	panel.set_meta("pinned", on)
	var pin: Button = panel.get_node_or_null("Root/TitleRow/Pin") as Button
	if pin != null:
		_style_pin_btn(pin, on)
	if on and panel == _ctx:
		# Закрепили текущую — следующему меню нужна новая панель.
		_ctx = _create_float_panel()
		_float_panels.append(_ctx)
		add_child(_ctx)


func _on_float_title_input(event: InputEvent, panel: PanelContainer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		panel.set_meta("dragging", event.pressed)
		if event.pressed:
			panel.set_meta("drag_off", panel.get_global_mouse_position() - panel.global_position)
		accept_event()
	elif event is InputEventMouseMotion and bool(panel.get_meta("dragging", false)):
		var gp: Vector2 = panel.get_global_mouse_position() - (panel.get_meta("drag_off") as Vector2)
		var local: Vector2 = get_global_transform().affine_inverse() * gp
		var psz: Vector2 = panel.size
		panel.position = Vector2(
			clampf(local.x, 4.0, maxf(4.0, size.x - psz.x - 4.0)),
			clampf(local.y, 4.0, maxf(4.0, size.y - psz.y - 4.0))
		)
		accept_event()


func _float_title_text(el, part: String) -> String:
	var tag := "—"
	if el != null:
		tag = str(el.tag) if str(el.tag) != "" else str(el.kind)
	var part_ru: String = "Общее"
	if part != "" and part != "general":
		part_ru = _part_title_for(el, part)
	return "%s · %s" % [tag, part_ru]


func _ensure_hover_bind() -> void:
	if circuit == null or _hover_sig_bound:
		return
	if not circuit.has_signal("hover_port_changed"):
		return
	circuit.hover_port_changed.connect(_on_circuit_hover_changed)
	_hover_sig_bound = true


func _on_circuit_hover_changed() -> void:
	# Hover не должен тянуть Base (все УГО + WireRouter) — только Live-рамка.
	_schedule_live()


## Порт 3D принадлежит клемме контакта группы (не катушке A1/A2).
func _3d_port_is_group_contact(primary_id: int, hport: String) -> bool:
	if hport == "" or circuit == null:
		return false
	if hport == "A1" or hport == "A2":
		return false
	for m in circuit.electro_group_members(primary_id):
		if str(m.member_role) != "contact":
			continue
		if IsoElectro.tip_to_contact_scheme_port(hport, m) != "":
			return true
	return false


## Наведение из 3D: primary+клемма контакта → порт УГО контакта на схеме.
func _ext_hover_for_el(el) -> Dictionary:
	var out := {"port": "", "body": false}
	if circuit == null or el == null:
		return out
	if str(circuit.hover_space) != "workshop":
		return out
	var hid: int = int(circuit.hover_el_id)
	var hport: String = str(circuit.hover_port)
	if hid < 0:
		return out
	var eid: int = int(el.id)
	# Контакт группы: клеммы в 3D на primary (11/COM/…), на схеме — у member.
	if str(el.member_role) == "contact" and int(el.group_id) == hid:
		if hport == "":
			out["body"] = true
			return out
		var mapped: String = IsoElectro.tip_to_contact_scheme_port(hport, el)
		if mapped != "":
			out["port"] = mapped
		return out
	# Тот же элемент (катушка A1/A2, АВ…) — не вешать клеммы контактов на УГО primary.
	if hid == eid:
		if hport != "" and _3d_port_is_group_contact(hid, hport):
			return out
		out["port"] = hport
		out["body"] = hport == ""
	return out


func _scheme_changed() -> void:
	# Явная перерисовка схемы после правок из плавающих панелей.
	if circuit != null:
		circuit.touch_scene()
	# Обрыв/группа меняют только метки/чертёж — трассы те же, пересобрать trunk-данные.
	if not _cached_wire_paths.is_empty() and circuit != null \
			and _cached_wire_paths.size() == circuit.wires.size():
		_cached_trunk_data = WireTrunks2D.build(circuit, _cached_wire_paths)
	_invalidate_scheme()


var _scene_sig_bound: bool = false


func _ensure_scene_bind() -> void:
	if circuit == null or _scene_sig_bound:
		return
	if circuit.has_signal("scene_changed"):
		circuit.scene_changed.connect(_on_circuit_scene_changed)
		_scene_sig_bound = true


func _on_circuit_scene_changed() -> void:
	_dbg_scene_changed += 1
	# Add/remove УГО без смены числа жил — tips те же, полный reroute = фриз на dense.
	# Трассы грязные только если изменилось число проводов (или явный invalidate).
	var wn: int = circuit.wires.size() if circuit != null else 0
	if _scene_wire_count_cached < 0:
		_scene_wire_count_cached = wn
	elif wn != _scene_wire_count_cached:
		_paths_dirty = true
		_scene_wire_count_cached = wn
	# Во время Run полный invalidate каждый emit → Base 30+ ms/кадр и ~25 FPS.
	if circuit != null and (bool(circuit.running) or float(circuit.sim_time) > 0.0):
		_sync_anim_only()
		return
	_sync_world_xform()
	_request_both("scene_changed")
	queue_redraw()
	_sync_anim_only()


func place_at_global(kind: String, global_pos: Vector2) -> void:
	if circuit == null or _sim_locks_edit():
		if _sim_locks_edit() and circuit != null:
			circuit.notify("Во время симуляции схема не редактируется")
		return
	var local := get_global_transform().affine_inverse() * global_pos
	var world: Vector2 = _screen_to_world(local)
	if not _try_place_kind(kind, world):
		return
	armed_kind = ""


## Размещение с проверкой цели (катушка ЭМ — только на ПР с соленоидом).
func _try_place_kind(kind: String, world: Vector2) -> bool:
	if circuit == null or kind == "" or _sim_locks_edit():
		return false
	if _is_solenoid_kind(kind):
		var hit: Dictionary = _pick_valve_for_coil(world)
		if hit.is_empty():
			circuit.notify("Катушку ЭМ нужно бросить на распределитель с электромагнитным приводом")
			return false
		var el = circuit.add_element(kind, world)
		if el == null:
			return false
		var side: String = str(hit.get("side", "L"))
		el.linked_valve_side = side
		var valve = circuit.get_element(int(hit.get("id", -1)))
		if valve != null:
			el.group_id = int(valve.id) # привязка к ПР для тега ГОСТ (Р1L / Р1R)
			el.tag = "%s%s" % [str(valve.tag), side]
			el.group_tag = el.tag
			var dx: float = -2.0 * Geom.SCH_GRID if side == "L" else 2.0 * Geom.SCH_GRID
			el.position = (valve.position + Vector2(dx, 0.0)).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))
		circuit.select_only(el.id)
		circuit.touch_scene()
		return true
	circuit.add_element(kind, world)
	return true


func _is_solenoid_kind(kind: String) -> bool:
	if kind == "coil":
		return true
	if kind.begins_with("electro@"):
		var rid: String = kind.substr(8)
		var rec: Dictionary = ElectroLib.recipe(rid)
		if rec.is_empty():
			return rid == "solenoid_coil"
		return str(rec.get("electro_class", "")) == "solenoid_coil" or bool(rec.get("link_valve", false))
	return false


## ПР под курсором с свободной стороной ЭМ (L/R по положению клика).
func _pick_valve_for_coil(world: Vector2) -> Dictionary:
	if circuit == null:
		return {}
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if str(el.kind) != "valve":
			continue
		var has_l: bool = str(el.op_left) in ["solenoid", "solenoid_pilot"]
		var has_r: bool = str(el.op_right) in ["solenoid", "solenoid_pilot"]
		if not has_l and not has_r:
			continue
		if not Geom.body_hit(el, world):
			continue
		var side: String = "L" if world.x <= float(el.position.x) else "R"
		if side == "L" and not has_l:
			side = "R" if has_r else ""
		elif side == "R" and not has_r:
			side = "L" if has_l else ""
		if side == "":
			continue
		return {"id": int(el.id), "side": side}
	return {}


func _screen_to_world(p: Vector2) -> Vector2:
	return (p - pan) / zoom


func _gui_input(event: InputEvent) -> void:
	if circuit == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(event.position, 1.1)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(event.position, 1.0 / 1.1)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_mode = "pan"
			_press = event.position
			# Один полный Base без cull — дальше только transform + сетка (без дёрганья).
			_request_base("pan")
			queue_redraw()
		elif _mode == "pan":
			_mode = ""
			_request_base("pan")
			queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _mode == "wire":
			_wire_cancel()
			accept_event()
			return
		_open_menu(event.position)
		accept_event()
		return
	# Двойной ЛКМ не открывает свойства — случайно всплывает при нажатии кнопок.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_begin_press(event)
		else:
			# Проводка — click-to-place; release не завершает соединение.
			if _mode != "wire":
				_end_press(event)
		accept_event()
		return
	if event is InputEventMouseMotion:
		_hover(event.position)
		if _mode == "pan":
			pan += event.position - _press
			_press = event.position
			_sync_world_xform()
			# Base/УГО/жилы — дети world_root: едут с transform. Полный Base на каждый
			# motion → hitch (подергивание). Нужна только сетка в Control._draw.
			queue_redraw()
		elif _mode == "tag":
			var el_tag = circuit.get_element(_tag_drag_id)
			if el_tag != null:
				# tag_offset в локали элемента — world-delta разворачиваем обратно.
				var world_delta := _screen_to_world(event.position) - _tag_press_world
				var local_delta: Vector2 = world_delta.rotated(-float(el_tag.rotation_quad) * PI * 0.5)
				el_tag.tag_offset = (_tag_drag_origin + local_delta).snapped(Vector2(2, 2))
				_moved = true
		elif _mode == "device_table":
			var el_dt = circuit.get_element(_device_table_id)
			if el_dt != null and _device_table_side in ["left", "right"]:
				var wdelta: Vector2 = _screen_to_world(event.position) - _device_table_press_world
				var ldelta: Vector2 = wdelta.rotated(-float(el_dt.rotation_quad) * PI * 0.5)
				var changed: bool = false
				# Горизонталь → край в preview (el не трогаем; призрак).
				if absf(ldelta.x) >= Geom.SCH_GRID * 2.0:
					var to_edge: String = "right" if ldelta.x > 0.0 else "left"
					var cur_edge: String = (
						_device_table_prev_edge_l
						if _device_table_side == "left"
						else _device_table_prev_edge_r
					)
					if cur_edge != to_edge:
						_device_table_preview_move_edge(el_dt, to_edge)
						_device_table_dy0 = (
							_device_table_prev_dy_l
							if _device_table_side == "left"
							else _device_table_prev_dy_r
						)
						_device_table_press_world = _screen_to_world(event.position)
						ldelta = Vector2.ZERO
						changed = true
				var new_dy: float = _device_table_preview_clamp_dy(el_dt, _device_table_dy0 + ldelta.y)
				var cur_dy: float = (
					_device_table_prev_dy_l
					if _device_table_side == "left"
					else _device_table_prev_dy_r
				)
				if absf(new_dy - cur_dy) > 0.01:
					if _device_table_side == "left":
						_device_table_prev_dy_l = new_dy
					else:
						_device_table_prev_dy_r = new_dy
					changed = true
				if changed:
					_moved = true
					_refresh_device_table_ghost()
		elif _mode == "wire_num":
			var w_num = circuit.get_wire(_num_drag_wire_id)
			if w_num != null:
				var d_num: Vector2 = (_screen_to_world(event.position) - _num_press_world).snapped(Vector2(2, 2))
				var off: Vector2 = _num_drag_origin + d_num
				if str(_num_drag_end).ends_with("b") or str(_num_drag_end) == "b":
					w_num.num_offset_b = off
				else:
					w_num.num_offset = off
				_moved = true
				_paths_dirty = true
				_request_base()
		elif _mode == "rail_edit" and _rail_edit_id >= 0:
			var elr = circuit.get_element(_rail_edit_id)
			if elr != null and str(elr.kind) == "rail":
				var w := _screen_to_world(event.position)
				if event.position.distance_to(_press) > 3.0:
					_moved = true
				if _rail_edit_seg >= 0 and _moved:
					# Сегмент: один раз «П» на прямой, дальше только сдвиг — без наращивания точек.
					_rail_edit_seg = Rail2D.insert_vertex_from_mid(elr, _rail_edit_seg, w)
					_rail_edit_vertex = -1
					_rail_edit_anchor = -1
					# Без полного invalidate на каждый motion — иначе фриз; пересчёт на отпускании.
					_request_live(true)
				elif _rail_edit_vertex >= 0:
					if _rail_edit_anchor >= 0:
						_rail_edit_vertex = Rail2D.move_end(
							elr, _rail_edit_anchor, _rail_edit_from_start, w
						)
					else:
						_rail_edit_vertex = Rail2D.move_vertex(elr, _rail_edit_vertex, w)
					_request_live(true)
		elif _mode == "wire":
			_request_live(true)
		elif _mode == "move" or _mode == "marquee" or _mode == "down" or _mode == "bend":
			if event.position.distance_to(_press) > 4.0:
				_moved = true
				if _mode == "down":
					_promote_drag()
			if _mode == "bend":
				_apply_bend(_screen_to_world(event.position))
			elif _mode == "move":
				_drag_delta = _screen_to_world(event.position) - _screen_to_world(_press)
				_update_drag_ghosts(_drag_delta)
		elif _mode == "marquee":
			queue_redraw()
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _begin_press(event: InputEventMouseButton) -> void:
	_hide_menu()
	var world := _screen_to_world(event.position)
	_bend_wire_id = -1
	_seg_ready = false
	_part_kind = ""
	# Ручная проводка: клик = изгиб / конец (не drag-release).
	if _mode == "wire" and not _sim_locks_edit():
		var wh: Dictionary = _pick_port(world)
		if not wh.is_empty():
			_wire_try_finish(int(wh["id"]), str(wh["port"]))
		else:
			_wire_place_bend(world)
		accept_event()
		return
	if armed_kind != "":
		if _sim_locks_edit():
			circuit.notify("Во время симуляции схема не редактируется")
			_request_both()
			return
		if _try_place_kind(armed_kind, world) and not event.shift_pressed:
			armed_kind = ""
		_invalidate_scheme()
		return
	if event.shift_pressed and Input.is_key_pressed(KEY_SPACE):
		_mode = "pan"
		_press = event.position
		return
	if Input.is_key_pressed(KEY_SPACE):
		_mode = "pan"
		_press = event.position
		return
	# При пуске: органы раньше обозначения — тег SB1 сидит над скобой и иначе «съедает» клик.
	if bool(circuit.running) and not event.shift_pressed:
		for i in range(circuit.elements.size() - 1, -1, -1):
			var vel = circuit.elements[i]
			var is_shut: bool = str(vel.kind) == "accessory" and str(vel.accessory_class) == "shutoff"
			if str(vel.kind) != "valve" and not is_shut:
				continue
			var side := Geom.operator_hit(vel, world)
			if side == "":
				continue
			if is_shut:
				# Бистабил: слева = закрыть, справа = открыть (не моментная кнопка).
				var AccZ = preload("res://scripts/domain/accessory_library.gd")
				AccZ.set_shutoff_open(vel, side == "right")
				circuit.select_only(vel.id, "schematic")
				notify_sim_control_changed()
				accept_event()
				return
			_mode = "actuate"
			_actuate_side = side
			_grab_id = vel.id
			_press = event.position
			_moved = false
			if side == "left":
				vel.command_left = true
			else:
				vel.command_right = true
			circuit.refresh_valve_pos(vel)
			circuit.select_only(vel.id, "schematic")
			# Force — при Run Base иначе заморожен и орган не «нажимается».
			notify_sim_control_changed()
			accept_event()
			return
		if _try_press_electro_control(world, event):
			return
	# Ручки ВЫДЕЛЕННОЙ жилы — выше порта/корпуса/чужих УГО.
	if not _sim_locks_edit():
		var sel_grip: Dictionary = _pick_grip(world, true)
		if not sel_grip.is_empty():
			_arm_bend(sel_grip)
			_mode = "bend"
			_press = event.position
			_moved = false
			_grab_id = -2
			_grab_port = ""
			if circuit.has_method("begin_history_group"):
				circuit.begin_history_group()
			return
	# Клеммник: корпус раньше порта, если клик не вплотную к кружку (иначе XT не выбрать).
	if not _sim_locks_edit():
		var term_body = _pick_body_strict(world)
		if term_body != null and str(term_body.kind) == "electro" \
				and str(term_body.electro_class) == "terminal":
			var term_port: Dictionary = _pick_port(world)
			if term_port.is_empty() or int(term_port.get("id", -1)) != int(term_body.id):
				_begin_body_press(event, term_body, world)
				return
	# Порт — сразу старт ортогональной проводки (до тега/корпуса).
	var hit_port := _pick_port(world)
	if not hit_port.is_empty() and not _sim_locks_edit():
		_wire_start(int(hit_port["id"]), str(hit_port["port"]))
		accept_event()
		return
	# Таблица клемм БП/прибора — таскать внутри рамки (до сдвига всего УГО).
	var tbl_hit: Dictionary = _pick_device_table(world)
	if not tbl_hit.is_empty() and not _sim_locks_edit():
		var tel = circuit.get_element(int(tbl_hit["id"]))
		if tel != null:
			_mode = "device_table"
			_device_table_id = int(tel.id)
			_device_table_side = str(tbl_hit["side"])
			_device_table_origin_dy_l = float(tel.device_table_dy_left)
			_device_table_origin_dy_r = float(tel.device_table_dy_right)
			_device_table_origin_edge_l = str(tel.device_table_edge_left)
			_device_table_origin_edge_r = str(tel.device_table_edge_right)
			_device_table_prev_dy_l = _device_table_origin_dy_l
			_device_table_prev_dy_r = _device_table_origin_dy_r
			_device_table_prev_edge_l = _device_table_origin_edge_l
			_device_table_prev_edge_r = _device_table_origin_edge_r
			_device_table_dy0 = (
				_device_table_prev_dy_l
				if _device_table_side == "left"
				else _device_table_prev_dy_r
			)
			_device_table_press_world = world
			_device_table_flipped = false
			_press = event.position
			_moved = false
			_grab_id = int(tel.id)
			_grab_port = ""
			_drag_omit_ids.clear()
			circuit.select_only(tel.id, "schematic")
			if circuit.has_method("begin_history_group"):
				circuit.begin_history_group()
			# Как move: призрак поверх; el/жилы — только на отпускании.
			_spawn_device_table_ghost(tel)
			accept_event()
			return
	# Групповая линия: якоря ДО чужих ручек жил (иначе невидимый обрыв/жила съедает клик).
	var rail_edit_early: Dictionary = _pick_rail_handle(world)
	if not rail_edit_early.is_empty() and not _sim_locks_edit():
		_begin_rail_edit(rail_edit_early, event)
		return
	# Несколько объектов под ЛКМ — белый список (раньше на ПКМ).
	if not _sim_locks_edit():
		var hits_lmb: Array = _collect_hits_at(world)
		if hits_lmb.size() >= 2:
			_open_hit_picker(event.position, hits_lmb)
			accept_event()
			return
	# Корпус (строго, без pad) — раньше чужих ручек жил: иначе провод N/PE «съедает» клик по L.
	var strict_body = _pick_body_strict(world)
	if strict_body != null and not _sim_locks_edit():
		_begin_body_press(event, strict_body, world)
		return
	# Ручки невыделенных жил — после корпуса / rail (обрыв: только видимые хвосты).
	var grip := _pick_grip(world, false)
	if not grip.is_empty() and not _sim_locks_edit():
		_arm_bend(grip)
		# Сразу bend: не ждать 4px promote (ручки «через раз»).
		_mode = "bend"
		_press = event.position
		_moved = false
		_grab_id = -2
		_grab_port = ""
		if circuit.has_method("begin_history_group"):
			circuit.begin_history_group()
		return
	# Тег: pad — только вне корпуса; сам текст подписи — даже поверх рамки/корпуса.
	var tag_el = _pick_tag_for_click(world)
	if tag_el != null and not _sim_locks_edit():
		_mode = "tag"
		_tag_drag_id = tag_el.id
		_tag_drag_origin = tag_el.tag_offset
		_tag_press_world = world
		_press = event.position
		_moved = false
		_grab_id = tag_el.id
		_grab_port = ""
		circuit.select_only(tag_el.id, "schematic")
		accept_event()
		return
	# Номер линии — после ручек; без полного reroute на каждый клик.
	var num_hit: Dictionary = _pick_wire_num(world)
	if not num_hit.is_empty() and not _sim_locks_edit():
		_mode = "wire_num"
		_num_drag_wire_id = int(num_hit.get("wire_id", -1))
		_num_drag_end = str(num_hit.get("end", "mid"))
		var w0 = circuit.get_wire(_num_drag_wire_id)
		if w0 != null:
			var end0: String = str(_num_drag_end)
			_num_drag_origin = w0.num_offset_b if (end0.ends_with("b") or end0 == "b") else w0.num_offset
		else:
			_num_drag_origin = Vector2.ZERO
		_num_press_world = world
		_press = event.position
		_moved = false
		circuit.selected_wire_id = _num_drag_wire_id
		circuit.selected_ids.clear()
		accept_event()
		return
	var hit = _pick_body(world)
	if hit != null:
		_begin_body_press(event, hit, world)
		return
	var wire = _pick_wire(world)
	if wire != null:
		if event.shift_pressed:
			circuit.toggle_wire_select(wire.id, "schematic")
		else:
			circuit.select_wire(wire.id, "schematic")
		_mode = ""
		return
	_mode = "down"
	_press = event.position
	_moved = false
	_grab_id = -1
	_grab_port = ""
	if not event.shift_pressed:
		circuit.clear_selection()


func _promote_drag() -> void:
	# При пуске — без переноса/проводки/изгиба (только органы выше по _begin_press).
	if _sim_locks_edit():
		return
	if _bend_wire_id >= 0:
		_mode = "bend"
		if circuit.has_method("begin_history_group"):
			circuit.begin_history_group()
		return
	if _grab_port != "":
		# Старт проводки — сразу по клику на порт (_wire_start); сюда не попадаем.
		_wire_start(_grab_id, _grab_port)
		return
	if _grab_id >= 0:
		_mode = "move"
		if circuit.has_method("begin_history_group"):
			circuit.begin_history_group()
		_origins.clear()
		# Первый контакт кнопки = сама кнопка: тащим primary, не отрываем контакт.
		var grab_el = circuit.get_element(_grab_id)
		if grab_el != null and (
			ElectroLib.is_button_fixed_contact(circuit, grab_el)
			or ElectroLib.is_supply_fixed_leg(circuit, grab_el)
		):
			var btn = circuit.get_element(int(grab_el.group_id))
			if btn != null:
				_grab_id = int(btn.id)
				circuit.select_only(_grab_id, "schematic")
		if not circuit.selected_ids.has(_grab_id):
			circuit.select_only(_grab_id, "schematic")
		for id in circuit.selected_ids:
			var el = circuit.get_element(id)
			if el:
				_origins[id] = el.position
				# Неоткреплённые контакты / ноги ввода — тоже в origins.
				if str(el.kind) == "electro" and int(el.group_id) >= 0 \
						and str(el.member_role) not in ["contact", "supply_leg"]:
					for m in circuit.electro_group_members(int(el.group_id)):
						if str(m.member_role) in ["contact", "supply_leg"] and not bool(m.detached):
							_origins[m.id] = m.position
						elif ElectroLib.is_button_fixed_contact(circuit, m) or ElectroLib.is_supply_fixed_leg(circuit, m):
							_origins[m.id] = m.position
		# Без reroute/Base/Live: только полупрозрачные Node2D-призраки.
		_drag_delta = Vector2.ZERO
		_drag_omit_ids.clear()
		_spawn_drag_ghosts()
		return
	_mode = "marquee"
	_marquee = Rect2(_screen_to_world(_press), Vector2.ZERO)


func _end_press(event: InputEventMouseButton) -> void:
	var world := _screen_to_world(event.position)
	# move / device_table: пути уже точечно обновлены — не сбрасывать весь кэш.
	var was_move: bool = _mode == "move" or _mode == "device_table"
	if _mode == "electro_btn":
		var bel = circuit.get_element(_grab_id)
		if bel != null and str(bel.kind) == "electro" and not bool(bel.latching):
			bel.pressed = false
		_mode = ""
		_moved = false
		_grab_id = -1
		_request_live()
		return
	if _mode == "actuate":
		var el = circuit.get_element(_grab_id)
		if el != null:
			if _actuate_side == "left":
				el.command_left = false
			elif _actuate_side == "right":
				el.command_right = false
			circuit.refresh_valve_pos(el)
		_actuate_side = ""
		_mode = ""
		_moved = false
		_grab_id = -1
		notify_sim_control_changed()
		return
	elif _mode == "rail_edit":
		if _moved:
			_apply_rail_edit_corridor_shift()
			circuit.touch_scene()
			WireRouter2D.invalidate()
			_paths_dirty = true
			_request_both("rail_edit_end")
		if circuit.has_method("end_history_group"):
			circuit.end_history_group()
		_rail_edit_id = -1
		_rail_edit_vertex = -1
		_rail_edit_seg = -1
		_rail_edit_anchor = -1
		_rail_edit_from_start = false
		_rail_edit_poly0 = PackedVector2Array()
		_rail_edit_wire_ids.clear()
		_mode = ""
	elif _mode == "marquee" and _moved:
		var box := Rect2(_screen_to_world(_press), world - _screen_to_world(_press)).abs()
		if not event.shift_pressed:
			circuit.selected_ids.clear()
		circuit.selected_wire_id = -1
		for el in circuit.elements:
			if box.intersects(Geom.world_bounds(el)):
				if not circuit.selected_ids.has(el.id):
					circuit.selected_ids.append(el.id)
	elif _mode == "bend":
		var wire = circuit.get_wire(_bend_wire_id)
		if wire != null:
			_write_joints(wire)
		if _moved:
			circuit.touch_scene()
		if circuit.has_method("end_history_group"):
			circuit.end_history_group()
	elif _mode == "move":
		_commit_drag_positions(_drag_delta)
		_clear_drag_ghosts()
		# Сначала detach/layout (snap в столбик), потом reroute — иначе разрывы при коротком drag.
		_apply_electro_detach_after_move()
		_bake_moved()
		_drag_omit_ids.clear()
		_drag_delta = Vector2.ZERO
		if _moved:
			circuit.touch_scene()
		if circuit.has_method("end_history_group"):
			circuit.end_history_group()
	elif _mode == "tag":
		if _moved:
			circuit.touch_scene()
		_tag_drag_id = -1
	elif _mode == "device_table":
		var el_commit = circuit.get_element(_device_table_id)
		if el_commit != null and _moved:
			_device_table_write_el(el_commit, true)
			circuit.touch_scene()
			# Жилы после commit раскладки — не во время призрака.
			var aff_dt: Dictionary = {}
			var eid_dt: int = _device_table_id
			for w_dt in circuit.wires:
				if int(w_dt.a_id) == eid_dt or int(w_dt.b_id) == eid_dt:
					WireRouter2D.invalidate_wire(int(w_dt.id))
					aff_dt[int(w_dt.id)] = true
			if not aff_dt.is_empty():
				_patch_cached_wire_paths(aff_dt)
		if circuit.has_method("end_history_group"):
			circuit.end_history_group()
		_clear_drag_ghosts()
		_drag_omit_ids.clear()
		_device_table_id = -1
		_device_table_side = ""
		_device_table_flipped = false
	elif _mode == "wire_num":
		if _moved:
			circuit.touch_scene()
		_num_drag_wire_id = -1
		_num_drag_end = ""
	elif _mode == "down" and not _moved and bool(circuit.running) and _grab_id >= 0 and _grab_port == "":
		# Короткий клик по электроэлементу при пуске — воздействие (кнопка/АВ/SA).
		var eel = circuit.get_element(_grab_id)
		if eel != null and str(eel.kind) == "electro":
			_click_electro_schematic(eel, world)
	WireRouter2D.drag_lite = false
	_mode = ""
	_moved = false
	_grab_port = ""
	_bend_wire_id = -1
	_seg_ready = false
	# После move кэш уже точечно обновлён — полный dirty гоняет чужие жилы.
	if not was_move:
		_paths_dirty = true
	_request_both("drag_end")
	queue_redraw()


func _hover(screen: Vector2) -> void:
	# Во время ghost-drag hover/Base/Live не трогаем — только призрак едет.
	if _mode == "move" or _mode == "device_table" or (_mode == "down" and not _drag_ghosts.is_empty()):
		return
	var world := _screen_to_world(screen)
	var hit := _pick_port(world)
	if hit.is_empty():
		_hover_id = -1
		_hover_port = ""
	else:
		_hover_id = hit["id"]
		_hover_port = hit["port"]
	_hover_part = ""
	_hover_part_id = -1
	_hover_body_id = -1
	if _mode == "":
		var part := _pick_part(world)
		if not part.is_empty():
			_hover_part_id = int(part["id"])
			_hover_part = str(part["part"])
	var body = _pick_body(world)
	if body != null:
		_hover_body_id = body.id
	# Порт вне корпуса не раздувает зону выбора (раньше hover_body = port).
	var hover_wire = null
	if hit.is_empty() and body == null:
		hover_wire = _pick_wire(world)
	var new_hover_el: int = -1
	var new_hover_port: String = ""
	var new_hover_wire: int = -1
	if circuit != null:
		if _hover_port != "":
			circuit.set_hover("schematic", _hover_id, _hover_port, -1)
			new_hover_el = _hover_id
			new_hover_port = _hover_port
		elif hover_wire != null:
			circuit.set_hover("schematic", -1, "", int(hover_wire.id))
			new_hover_wire = int(hover_wire.id)
		elif body != null:
			circuit.set_hover("schematic", int(body.id), "", -1)
			new_hover_el = int(body.id)
		elif str(circuit.hover_space) == "schematic":
			circuit.clear_hover("schematic")
	# Подсветка якоря: только угол / кружок середины — НЕ полоса сегмента
	# (иначе жёлтый круг при простом hover по жиле).
	_hover_grip_key = ""
	if _mode == "" or _mode == "idle":
		var ghov: Dictionary = _pick_grip(world, false, true)
		if not ghov.is_empty() and ghov.get("wire", null) != null:
			var gw = ghov["wire"]
			_hover_grip_key = "%d:%s:%d" % [int(gw.id), str(ghov.get("kind", "")), int(ghov.get("index", -1))]
	var over_tag: bool = _pick_tag_for_click(world) != null
	if over_tag or _mode == "tag":
		mouse_default_cursor_shape = Control.CURSOR_MOVE
	elif _hover_grip_key != "" or _mode == "bend":
		mouse_default_cursor_shape = Control.CURSOR_MOVE
	elif _hover_part != "":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	_tip_screen = screen
	_update_tip()
	if _mode == "marquee":
		var a := _screen_to_world(_press)
		_marquee = Rect2(a, world - a).abs()
	# Перерисовка только если hover реально изменился (не любой жест — иначе drag жжёт Base).
	var hover_changed: bool = (
		new_hover_el != _hover_prev_el
		or new_hover_port != _hover_prev_port
		or new_hover_wire != _hover_prev_wire
		or _hover_part != _hover_prev_part
		or int(_hover_part_id) != int(_hover_prev_part_id)
		or _hover_grip_key != _hover_prev_grip_key
	)
	_hover_prev_el = new_hover_el
	_hover_prev_port = new_hover_port
	_hover_prev_wire = new_hover_wire
	_hover_prev_part = _hover_part
	_hover_prev_part_id = int(_hover_part_id)
	_hover_prev_grip_key = _hover_grip_key
	# Hover только Live (синие штрихи) — полный Base жжёт O(УГО+жилы) на каждый сдвиг.
	if hover_changed:
		_schedule_live()
	if _mode == "marquee":
		queue_redraw()


func _pick_tag(world: Vector2):
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if Geom.tag_hit(el, world, zoom, font):
			return el
	return null


## Подпись для клика: текст важнее корпуса; pad — только если корпус не под курсором.
func _pick_tag_for_click(world: Vector2):
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if Geom.tag_text_hit(el, world, font):
			return el
	var body = _pick_body(world)
	if body != null:
		return null
	return _pick_tag(world)


## Попадание в номер линии (world). Возвращает {wire_id, end} или {}.
func _pick_wire_num(world: Vector2) -> Dictionary:
	if circuit == null or font == null:
		return {}
	# Только кэш с _draw — без prepare×N на каждый клик (фризы).
	var paths: Array = _cached_wire_paths
	if paths.is_empty() or paths.size() != circuit.wires.size():
		return {}
	var trunk: Dictionary = _cached_trunk_data
	if trunk.is_empty():
		trunk = WireTrunks2D.build(circuit, paths)
	var labels: Array = []
	for item in trunk.get("end_labels", []) as Array:
		labels.append(item)
	for item2 in trunk.get("join_labels", []) as Array:
		labels.append(item2)
	# Узкий хват: не перекрывать ручки углов (раньше 14…22 world → постоянно перехват).
	var hit_r: float = clampf(9.0 / maxf(zoom, 0.25), 5.0, 12.0)
	var best: Dictionary = {}
	var best_d: float = hit_r
	for item3 in labels:
		var pos: Vector2 = item3.get("pos", Vector2.ZERO) as Vector2
		var d: float = world.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = {
				"wire_id": int(item3.get("wire_id", -1)),
				"end": str(item3.get("end", "mid")),
			}
	return best


func _refresh_tip_while_sim(dt: float) -> void:
	if circuit == null or _tip == null or not _tip.visible:
		_tip_refresh_accum = 0.0
		return
	if not bool(circuit.running) and float(circuit.sim_time) <= 0.0:
		return
	_tip_refresh_accum += dt
	if _tip_refresh_accum < 1.0 / TIP_REFRESH_HZ:
		return
	_tip_refresh_accum = 0.0
	_update_tip()


func _update_tip() -> void:
	if _tip == null or _tip_label == null:
		return
	if circuit == null:
		_tip.visible = false
		return
	# Пока открыт список выбора / свойства — не перекрывать тултипом.
	if has_visible_float_on(self):
		_tip.visible = false
		return
	var text: String = ""
	if _hover_port != "" and _hover_id >= 0:
		text = circuit.port_sim_tip(_hover_id, _hover_port)
	elif str(circuit.hover_space) == "schematic" and int(circuit.hover_wire_id) >= 0:
		var w = circuit.get_wire(int(circuit.hover_wire_id))
		if w != null:
			text = circuit.wire_hover_tip(w)
	elif _hover_body_id >= 0:
		# Корпус — тот же текст, что в 3D (element_sim_tip).
		text = circuit.element_sim_tip(int(_hover_body_id))
	if text == "":
		_tip.visible = false
		_tip.custom_minimum_size = Vector2.ZERO
		return
	_tip_label.clear()
	_tip_label.parse_bbcode(text)
	_tip.visible = true
	# Ширина по самой длинной строке (без autowrap — узкая колонка).
	var tip_sz: Vector2 = _measure_scheme_tip(text)
	_tip.custom_minimum_size = tip_sz
	_tip.size = tip_sz
	var pos: Vector2 = _tip_screen + Vector2(14, 18)
	if pos.x + tip_sz.x > size.x:
		pos.x = _tip_screen.x - tip_sz.x - 8.0
	if pos.y + tip_sz.y > size.y:
		pos.y = _tip_screen.y - tip_sz.y - 8.0
	pos.x = clampf(pos.x, 0.0, maxf(size.x - tip_sz.x, 0.0))
	pos.y = clampf(pos.y, 0.0, maxf(size.y - tip_sz.y, 0.0))
	_tip.position = pos


func _measure_scheme_tip(text: String) -> Vector2:
	var font: Font = _tip_label.get_theme_font("normal_font")
	var font_size: int = _tip_label.get_theme_font_size("normal_font_size")
	if font == null:
		font = ThemeDB.fallback_font
	if font_size <= 0:
		font_size = 12
	var plain: String = text.replace("[b]", "").replace("[/b]", "")
	var max_w: float = 0.0
	var lines: PackedStringArray = plain.split("\n")
	for line in lines:
		var w: float = font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var line_h: float = font.get_height(font_size)
	var pad_x: float = 16.0
	var pad_y: float = 10.0
	var sb: StyleBox = _tip.get_theme_stylebox("panel")
	if sb != null:
		pad_x = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
		pad_y = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	var n: int = maxi(lines.size(), 1)
	return Vector2(ceilf(max_w + pad_x + 4.0), ceilf(line_h * float(n) + pad_y + 2.0))


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _screen_to_world(screen)
	zoom = clampf(zoom * factor, 0.35, 2.8)
	pan = screen - before * zoom
	_sync_world_xform()
	# Толщина штрихов зависит от zoom (sch_zoom) — force, иначе троттлинг после Run.
	_request_both("zoom")
	queue_redraw()


func _pick_part(world: Vector2) -> Dictionary:
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		var part := Geom.part_hit(el, world, zoom)
		if part != "":
			return {"id": el.id, "part": part}
	return {}


## Попадание в таблицу Конт./Цепь БП/прибора → {id, side}.
func _pick_device_table(world: Vector2) -> Dictionary:
	if circuit == null:
		return {}
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) not in ["psu", "generic_device"]:
			continue
		var part: String = Geom.part_hit(el, world, zoom)
		if part == "device_table_left":
			return {"id": int(el.id), "side": "left"}
		if part == "device_table_right":
			return {"id": int(el.id), "side": "right"}
	return {}


func _open_parts(screen: Vector2) -> void:
	var el = circuit.get_element(_grab_id)
	var part := _part_kind
	if el == null or part == "":
		return
	_fill_ctx_menu(screen, _float_title_text(el, part), int(el.id), part, func(box: VBoxContainer) -> void:
		# Только настройки этой части — без общего расчёта и чужих полей.
		for opt in _part_options_for(el, part):
			box.add_child(_choice_button(str(opt["label"]), part, str(opt["id"]), el))
		_add_part_params(box, el, part)
	)


## ПКМ по линии — сечение/цвет в белом окошке (закрывается кликом мимо, если не pinned).
func _open_wire_ctx(screen: Vector2, wire) -> void:
	if wire == null:
		return
	if _props_win != null and _props_win.visible:
		_props_win.hide()
	_part_kind = ""
	var wtitle: String = "Линия · общее"
	if circuit != null:
		var tip: String = circuit.wire_hover_tip(wire)
		if tip != "":
			var SimVpl = preload("res://scripts/domain/sim_vis.gd")
			var first: String = SimVpl.tip_plain(tip).split("\n")[0]
			wtitle = "%s · общее" % first
	_fill_ctx_menu(screen, wtitle, -1, "general", func(box: VBoxContainer) -> void:
		_add_wire_params(box, wire)
	)


func _open_properties(screen: Vector2, el = null) -> void:
	# Окно «Свойства» отключено: общее окно элемента / параметры линии.
	if _props_win != null:
		_props_win.visible = false
	_part_kind = ""
	var wire_id: int = circuit.selected_wire_id if circuit != null else -1
	var target = el
	if target == null and wire_id < 0 and circuit != null:
		target = circuit.primary()
	if target != null and str(target.kind) == "electro" and str(target.member_role) == "contact" and int(target.group_id) >= 0:
		var primary = circuit.get_element(int(target.group_id))
		if primary != null:
			target = primary
			circuit.select_only(int(primary.id), "schematic")
	if target == null:
		if wire_id >= 0:
			var w = circuit.get_wire(wire_id)
			if w != null:
				_open_wire_ctx(screen, w)
		_props_place_host = null
		return
	_float_place_host = _props_place_host
	_props_place_host = null
	_open_general_params(screen, target)


func _props_scroll_box() -> VBoxContainer:
	# Одиночный список свойств: свой scroll с прозрачной бумагой и запасом справа.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(400, 320)
	_style_scroll(scroll)
	_props_host.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)
	return box


func _apply_props_panel_style() -> void:
	_style_float_panel(_ctx)
	if _ctx != null:
		_ctx.custom_minimum_size = Vector2(280, 120)


func _open_element_menu(screen: Vector2, el = null) -> void:
	_open_general_params(screen, el)


func _open_general_params(screen: Vector2, el = null) -> void:
	# Vector2.ZERO = «оставить где было» (после выбора в OptionButton), иначе панель уезжает в (4,4).
	if screen == Vector2.ZERO and _ctx != null and is_instance_valid(_ctx) and _ctx.visible:
		screen = _ctx.position
	var target = el
	if target == null:
		target = circuit.primary() if circuit != null else null
	if target != null and str(target.kind) == "electro" and str(target.member_role) == "contact" and int(target.group_id) >= 0:
		var primary = circuit.get_element(int(target.group_id))
		if primary != null:
			target = primary
			circuit.select_only(int(primary.id), "schematic")
	if target == null:
		return
	_part_kind = ""
	_grab_id = int(target.id)
	_fill_ctx_menu(screen, _float_title_text(target, "general"), int(target.id), "general", func(box: VBoxContainer) -> void:
		_add_general_element_params(box, target)
	)


func _fill_ctx_menu(screen: Vector2, title: String, el_id: int, part: String, build: Callable) -> void:
	_hide_menu()
	# Любое белое окно — без тултипа поверх.
	if _tip != null:
		_tip.visible = false
	var host: Control = _float_place_host if _float_place_host != null else self
	_float_place_host = null
	if _ctx == null or not is_instance_valid(_ctx) or bool(_ctx.get_meta("pinned", false)):
		_ctx = _create_float_panel()
		_float_panels.append(_ctx)
	if _ctx.get_parent() != host:
		var cur: Node = _ctx.get_parent()
		if cur != null:
			cur.remove_child(_ctx)
		host.add_child(_ctx)
	_style_float_panel(_ctx)
	_ctx.set_meta("pinned", false)
	_ctx.set_meta("el_id", el_id)
	_ctx.set_meta("part", part)
	_ctx.set_meta("dragging", false)
	_ctx.set_meta("place_host", host)
	# На оверлее 3D тултип выше (z=60) — панель выбора должна быть ещё выше.
	_ctx.z_index = 70 if host != self else 30
	var pin: Button = _ctx.get_node_or_null("Root/TitleRow/Pin") as Button
	if pin != null:
		pin.set_pressed_no_signal(false)
		_style_pin_btn(pin, false)
	var title_lbl: Label = _ctx.get_node_or_null("Root/TitleRow/Title") as Label
	if title_lbl != null:
		title_lbl.text = title
		title_lbl.add_theme_color_override("font_color", UiTheme.paper_text())
	var body: VBoxContainer = _ctx.get_node_or_null("Root/Body") as VBoxContainer
	if body == null:
		return
	while body.get_child_count() > 0:
		var old := body.get_child(0)
		body.remove_child(old)
		old.queue_free()
	_ctx.custom_minimum_size = Vector2.ZERO
	build.call(body)
	_apply_sim_edit_lock(body)
	_ctx.visible = true
	_ctx.reset_size()
	_ctx.move_to_front()
	call_deferred("_fit_ctx", screen)


## Симуляция: окна частей/общего открываются, но поля только для чтения.
func _sim_locks_edit() -> bool:
	return circuit != null and bool(circuit.running)


func _apply_sim_edit_lock(root: Node) -> void:
	if root == null:
		return
	_sync_sim_lock_banner(root as Control, _sim_locks_edit())
	_set_edit_controls_enabled(root, not _sim_locks_edit())


func _sync_sim_lock_banner(root: Control, locked: bool) -> void:
	if root == null or not (root is VBoxContainer):
		return
	var banner: Label = root.get_node_or_null("SimLockBanner") as Label
	var rule: Control = root.get_node_or_null("SimLockRule") as Control
	if locked:
		if banner == null:
			banner = Label.new()
			banner.name = "SimLockBanner"
			banner.text = "Симуляция — параметры только для просмотра.\nОрганы управления — в 3D (ручки, кнопки)."
			banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			banner.add_theme_font_size_override("font_size", 11)
			banner.add_theme_color_override("font_color", UiTheme.paper_muted())
			root.add_child(banner)
			root.move_child(banner, 0)
		if rule == null:
			rule = _menu_rule()
			rule.name = "SimLockRule"
			root.add_child(rule)
			root.move_child(rule, 1)
	else:
		if banner != null:
			banner.queue_free()
		if rule != null:
			rule.queue_free()


func _set_edit_controls_enabled(node: Node, enabled: bool) -> void:
	if node == null:
		return
	if str(node.name) in ["SimLockBanner", "SimLockRule", "Pin"]:
		pass
	elif node is LineEdit:
		(node as LineEdit).editable = enabled
	elif node is TextEdit:
		(node as TextEdit).editable = enabled
	elif node is SpinBox:
		(node as SpinBox).editable = enabled
		(node as Control).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	elif node is OptionButton:
		(node as OptionButton).disabled = not enabled
	elif node is CheckBox:
		(node as CheckBox).disabled = not enabled
	elif node is CheckButton:
		(node as CheckButton).disabled = not enabled
	elif node is Slider:
		(node as Slider).editable = enabled
	elif node is Button and not (node is OptionButton):
		var btn := node as Button
		if str(btn.name) != "Pin":
			btn.disabled = not enabled
	for child in node.get_children():
		_set_edit_controls_enabled(child, enabled)


## После пуска/паузы — lock/unlock полей в открытых float-панелях.
func refresh_sim_edit_lock() -> void:
	var locked: bool = _sim_locks_edit()
	for p in _float_panels:
		if p == null or not is_instance_valid(p) or not p.visible:
			continue
		var body: VBoxContainer = p.get_node_or_null("Root/Body") as VBoxContainer
		if body == null:
			continue
		_sync_sim_lock_banner(body, locked)
		_set_edit_controls_enabled(body, not locked)


func _fit_ctx(screen: Vector2) -> void:
	if _ctx == null or not _ctx.visible:
		return
	_ctx.reset_size()
	var host: Control = _ctx.get_parent() as Control
	if host == null:
		host = self
	var hs: Vector2 = host.size
	if hs.x < 8.0 or hs.y < 8.0:
		hs = size
	var menu_size := _ctx.get_combined_minimum_size()
	# Не раздувать ширину из‑за высоты (много контактов кнопки).
	var max_w: float = 300.0 if _part_kind != "" else 280.0
	if _part_kind.begins_with("cell_") or _part_kind == "body" or _part_kind == "general":
		max_w = 420.0
	menu_size.x = clampf(menu_size.x, 220.0, mini(max_w, maxf(220.0, hs.x - 16.0)))
	# Жёсткий потолок высоты: иначе OptionButton/подписи раздувают окно на всю схему.
	var max_h: float = mini(maxf(80.0, hs.y - 16.0), 420.0)
	menu_size.y = clampf(menu_size.y, 80.0, max_h)
	# Не сбрасывать в угол при screen=(0,0) после выбора в выпадающем списке.
	var menu_pos := screen
	if menu_pos == Vector2.ZERO:
		menu_pos = _ctx.position
	menu_pos.x = clampf(menu_pos.x, 4.0, maxf(4.0, hs.x - menu_size.x - 4.0))
	menu_pos.y = clampf(menu_pos.y, 4.0, maxf(4.0, hs.y - menu_size.y - 4.0))
	_ctx.position = menu_pos
	_ctx.size = menu_size


func _part_title_for(el, part: String) -> String:
	if el == null:
		return "Часть"
	if el.kind == "electro":
		match part:
			"lens", "lamp_color", "lamp_voltage":
				return "Лампа"
			"operator":
				return "Кнопка" if str(el.electro_class) != "e_stop" else "Гриб"
			"cam":
				return "Переключатель"
			"bus_color":
				return "Цвет шины"
			"bus_taps":
				return "Отводы шины"
			"device_title":
				return "Подпись"
			"device_ports", "device_table_left", "device_table_right":
				return "Клеммы"
			"supply":
				return "Ввод"
			"terminal":
				return "Клеммник"
			"lever":
				return "Рычаг"
			"coil":
				return "Катушка"
			"pilot":
				return "Пилот"
		return "Часть"
	if el.kind == "valve":
		return ValveCat.part_title(part)
	return Catalog.part_title(part)


func _part_options_for(el, part: String) -> Array:
	if el.kind == "electro":
		match part:
			"lens":
				# Цвет и напряжение — в _add_part_params (два блока в одном меню).
				return []
			"lamp_color":
				return [
					{"id": "white", "label": "Белая"},
					{"id": "red", "label": "Красная"},
					{"id": "green", "label": "Зелёная"},
					{"id": "yellow", "label": "Жёлтая"},
				]
			"lamp_voltage":
				return [
					{"id": "ac220", "label": "~ 220 В"},
					{"id": "dc24", "label": "= 24 В"},
				]
			"bus_color":
				return [
					{"id": "N", "label": "Голубой — нейтраль"},
					{"id": "-", "label": "Чёрный — минус"},
					{"id": "+", "label": "Красный — плюс"},
					{"id": "PE", "label": "Зелёный — PE"},
					{"id": "L1", "label": "Коричневый — L1"},
					{"id": "L2", "label": "Чёрный — L2"},
					{"id": "L3", "label": "Серый — L3"},
				]
		return []
	if el.kind == "valve":
		if part == "body":
			var opts: Array = []
			opts.append_array(ValveCat.part_options("ways"))
			return opts
		return ValveCat.part_options(part)
	return Catalog.part_options(part)


## Параметры элемента, которых нет в окнах отдельных частей УГО.
func _add_general_element_params(box: VBoxContainer, el) -> void:
	if el == null:
		return
	match str(el.kind):
		"electro":
			_add_general_electro_params(box, el)
		"cylinder":
			_add_general_cylinder_params(box, el)
		"rotary_cylinder":
			_add_general_rotary_params(box, el)
		"air_motor":
			_add_general_motor_params(box, el)
		"sensor":
			_add_general_sensor_params(box, el)
		"opto_tip":
			_add_general_opto_tip_params(box, el)
		"valve":
			_add_general_valve_params(box, el)
		"source":
			_add_source_params(box, el)
		"junction":
			_add_junction_params(box, el)
		"accessory":
			_add_accessory_params(box, el)
		_:
			var tag := LineEdit.new()
			_style_field(tag)
			tag.text = str(el.tag)
			tag.placeholder_text = "Обозначение"
			tag.custom_minimum_size = Vector2(220, 28)
			tag.text_changed.connect(func(v):
				el.tag = v.strip_edges()
				_scheme_changed()
			)
			box.add_child(_menu_labeled("Обозначение", tag))


func _add_general_electro_params(box: VBoxContainer, el) -> void:
	# Обозначение и монтаж — не в окнах частей; остальное у lens/operator/coil/…
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		el.group_tag = el.tag
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var cls_lab := Label.new()
	cls_lab.text = "Класс: %s" % str(el.electro_class)
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	var mount_lab := Label.new()
	mount_lab.text = "Монтаж: %s" % str(el.electro_mount)
	mount_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(mount_lab)
	# Если нет зон частей — поля класса здесь (без повторного «Обозначение»).
	var zones: Array = ElectroSymbols.part_zones(el)
	if not zones.is_empty():
		return
	var cls: String = str(el.electro_class)
	match cls:
		"voltage_relay":
			_add_coil_electrical_params(box, el)
		"thermal":
			if str(el.member_role) != "contact":
				_add_coil_electrical_params(box, el)
				_add_coil_contact_params(box, el)
		_:
			pass


func _add_general_rotary_params(box: VBoxContainer, el) -> void:
	var RotaryCat = preload("res://scripts/domain/rotary_catalog.gd")
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var cls_lab := Label.new()
	cls_lab.text = "Класс: рейка–шестерня"
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	var bore_box := OptionButton.new()
	_style_field(bore_box)
	bore_box.custom_minimum_size = Vector2(220, 28)
	var bore_sel := 0
	var bi := 0
	for bore in RotaryCat.bores_rack():
		bore_box.add_item("∅ %.0f мм" % float(bore))
		bore_box.set_item_metadata(bi, float(bore))
		if absf(float(bore) - float(el.bore_mm)) < 0.1:
			bore_sel = bi
		bi += 1
	bore_box.selected = bore_sel
	bore_box.item_selected.connect(func(idx: int):
		el.bore_mm = float(bore_box.get_item_metadata(idx))
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Диаметр поршня", bore_box))
	var ang_box := OptionButton.new()
	_style_field(ang_box)
	ang_box.custom_minimum_size = Vector2(220, 28)
	var ang_sel := 0
	var ai := 0
	for ang in RotaryCat.angles_rack():
		ang_box.add_item("%.0f°" % float(ang))
		ang_box.set_item_metadata(ai, float(ang))
		if absf(float(ang) - float(el.angle_max_deg)) < 0.1:
			ang_sel = ai
		ai += 1
	ang_box.selected = ang_sel
	ang_box.item_selected.connect(func(idx: int):
		el.angle_max_deg = float(ang_box.get_item_metadata(idx))
		var note2: String = circuit.retune_geometry(el)
		if note2 != "":
			circuit.notify(note2)
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Угол поворота", ang_box))
	var t_lab := Label.new()
	t_lab.text = "Момент @6 бар: %.1f Н·м · %s · Ø%.0f" % [
		float(el.torque_nm_at_6bar), str(el.port_name), float(el.tube_od_mm),
	]
	t_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(t_lab)
	_add_cylinder_fitting_control_for_rotary(box, el)


func _add_general_sensor_params(box: VBoxContainer, el) -> void:
	var SensorCat = preload("res://scripts/domain/sensor_catalog.gd")
	var SensorSig = preload("res://scripts/domain/sensor_signal.gd")
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var cls_lab := Label.new()
	var cls_name: String = str(el.sensor_class)
	if cls_name == "reed":
		cls_name = "геркон (пассивный)"
	elif cls_name == "inductive":
		cls_name = "индуктивный"
	elif cls_name == "capacitive":
		cls_name = "ёмкостный"
	elif cls_name == "optical":
		cls_name = "оптический"
	elif cls_name == "ultrasonic":
		cls_name = "ультразвуковой (аналог)"
	elif cls_name == "pressure_switch":
		cls_name = "реле давления (пассивный сухой контакт)"
	elif cls_name == "pressure_tx":
		cls_name = "датчик давления (аналог ПИП)"
	elif cls_name == "rtd":
		cls_name = "ТС / Pt100 (пассивный R + вторичка)"
	cls_lab.text = "Класс: %s" % cls_name
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	var is_reed: bool = str(el.sensor_class) == "reed"
	var is_capacitive: bool = str(el.sensor_class) == "capacitive"
	var is_optical: bool = str(el.sensor_class) == "optical"
	var is_inductive: bool = str(el.sensor_class) == "inductive"
	var is_ultrasonic: bool = str(el.sensor_class) == "ultrasonic"
	var is_pressure_switch: bool = str(el.sensor_class) == "pressure_switch"
	var is_pressure_tx: bool = str(el.sensor_class) == "pressure_tx"
	var is_rtd: bool = str(el.sensor_class) == "rtd"
	if is_optical:
		var form_box := OptionButton.new()
		_style_field(form_box)
		form_box.custom_minimum_size = Vector2(220, 28)
		form_box.add_item("Вариант 1 · усилитель + оптоволокно", 0)
		form_box.add_item("Вариант 2 · компактный датчик (D/R)", 1)
		form_box.select(1 if str(el.optical_form) == "compact" else 0)
		form_box.item_selected.connect(func(i):
			el.optical_form = "compact" if int(i) == 1 else "fiber"
			if el.optical_form == "compact":
				el.body_od_mm = 18.0
				el.stroke_mm = 65.0
				if float(el.sense_range_mm) > 300.0:
					el.sense_range_mm = 100.0
			else:
				el.body_od_mm = 30.0
				el.stroke_mm = 70.0
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Исполнение", form_box))
	if is_inductive:
		var size_box := OptionButton.new()
		_style_field(size_box)
		size_box.custom_minimum_size = Vector2(220, 28)
		var rows: Array = SensorCat.inductive_sizes()
		var sel: int = SensorCat.nearest_inductive_index(float(el.body_od_mm))
		for i in rows.size():
			size_box.add_item(str((rows[i] as Dictionary).get("label", "")), i)
		size_box.select(sel)
		size_box.item_selected.connect(func(i):
			SensorCat.apply_inductive_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", size_box))
	elif is_capacitive:
		var cap_box := OptionButton.new()
		_style_field(cap_box)
		cap_box.custom_minimum_size = Vector2(220, 28)
		var cap_rows: Array = SensorCat.capacitive_sizes()
		var cap_sel: int = SensorCat.nearest_capacitive_index(float(el.body_od_mm), float(el.sense_range_mm))
		for i in cap_rows.size():
			cap_box.add_item(str((cap_rows[i] as Dictionary).get("label", "")), i)
		cap_box.select(cap_sel)
		cap_box.item_selected.connect(func(i):
			SensorCat.apply_capacitive_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", cap_box))
	elif is_optical and str(el.optical_form) != "compact":
		var opt_box := OptionButton.new()
		_style_field(opt_box)
		opt_box.custom_minimum_size = Vector2(220, 28)
		var opt_rows: Array = SensorCat.optical_fiber_sizes()
		var opt_sel: int = SensorCat.nearest_optical_fiber_index(float(el.sense_range_mm))
		for i in opt_rows.size():
			opt_box.add_item(str((opt_rows[i] as Dictionary).get("label", "")), i)
		opt_box.select(opt_sel)
		opt_box.item_selected.connect(func(i):
			SensorCat.apply_optical_fiber_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер усилителя", opt_box))
	elif is_optical and str(el.optical_form) == "compact":
		var copt_box := OptionButton.new()
		_style_field(copt_box)
		copt_box.custom_minimum_size = Vector2(220, 28)
		var copt_rows: Array = SensorCat.optical_compact_sizes()
		var copt_sel: int = SensorCat.nearest_optical_compact_index(float(el.body_od_mm), float(el.sense_range_mm))
		for i in copt_rows.size():
			copt_box.add_item(str((copt_rows[i] as Dictionary).get("label", "")), i)
		copt_box.select(copt_sel)
		copt_box.item_selected.connect(func(i):
			SensorCat.apply_optical_compact_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", copt_box))
	elif is_reed:
		var reed_box := OptionButton.new()
		_style_field(reed_box)
		reed_box.custom_minimum_size = Vector2(220, 28)
		var reed_rows: Array = SensorCat.reed_sizes()
		var reed_sel: int = SensorCat.nearest_reed_index(float(el.body_od_mm), float(el.sense_range_mm))
		for i in reed_rows.size():
			reed_box.add_item(str((reed_rows[i] as Dictionary).get("label", "")), i)
		reed_box.select(reed_sel)
		reed_box.item_selected.connect(func(i):
			SensorCat.apply_reed_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", reed_box))
	elif is_ultrasonic:
		var us_box := OptionButton.new()
		_style_field(us_box)
		us_box.custom_minimum_size = Vector2(220, 28)
		var us_rows: Array = SensorCat.ultrasonic_sizes()
		var us_sel: int = SensorCat.nearest_ultrasonic_index(float(el.sense_range_mm), float(el.sense_min_mm))
		for i in us_rows.size():
			us_box.add_item(str((us_rows[i] as Dictionary).get("label", "")), i)
		us_box.select(us_sel)
		us_box.item_selected.connect(func(i):
			SensorCat.apply_ultrasonic_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", us_box))
	elif is_pressure_switch:
		var ps_box := OptionButton.new()
		_style_field(ps_box)
		ps_box.custom_minimum_size = Vector2(220, 28)
		var ps_rows: Array = SensorCat.pressure_switch_sizes()
		var ps_sel: int = SensorCat.nearest_pressure_switch_index(float(el.sense_range_mm))
		for i in ps_rows.size():
			ps_box.add_item(str((ps_rows[i] as Dictionary).get("label", "")), i)
		ps_box.select(ps_sel)
		ps_box.item_selected.connect(func(i):
			SensorCat.apply_pressure_switch_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Типоразмер", ps_box))
		var set_ps := SpinBox.new()
		_style_field(set_ps)
		set_ps.min_value = float(el.sense_min_mm)
		set_ps.max_value = maxf(float(el.sense_range_mm), set_ps.min_value + 0.05)
		set_ps.step = 0.05
		set_ps.value = clampf(float(el.set_pressure_bar), set_ps.min_value, set_ps.max_value)
		set_ps.suffix = " бар"
		set_ps.custom_minimum_size = Vector2(220, 28)
		set_ps.value_changed.connect(func(v):
			el.set_pressure_bar = float(v)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Уставка срабатывания", set_ps))
		var hyst_ps := SpinBox.new()
		_style_field(hyst_ps)
		hyst_ps.min_value = 0.02
		hyst_ps.max_value = maxf(float(el.sense_range_mm) - float(el.sense_min_mm), 0.1)
		hyst_ps.step = 0.05
		hyst_ps.value = clampf(float(el.hysteresis_bar), hyst_ps.min_value, hyst_ps.max_value)
		hyst_ps.suffix = " бар"
		hyst_ps.custom_minimum_size = Vector2(220, 28)
		hyst_ps.value_changed.connect(func(v):
			el.hysteresis_bar = float(v)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Гистерезис (дифференциал)", hyst_ps))
		var ps_note := Label.new()
		ps_note.text = "Отпускание при P ≤ уставка − гистерезис. Контакт на схеме: KP·.1"
		ps_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ps_note.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(ps_note)
	elif is_pressure_tx:
		var pt_box := OptionButton.new()
		_style_field(pt_box)
		pt_box.custom_minimum_size = Vector2(220, 28)
		var pt_rows: Array = SensorCat.pressure_tx_sizes()
		var pt_sel: int = SensorCat.nearest_pressure_tx_index(float(el.sense_range_mm), str(el.analog_kind))
		for i in pt_rows.size():
			pt_box.add_item(str((pt_rows[i] as Dictionary).get("label", "")), i)
		pt_box.select(pt_sel)
		pt_box.item_selected.connect(func(i):
			SensorCat.apply_pressure_tx_size(el, int(i))
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Диапазон / выход", pt_box))
		var pt_ak := OptionButton.new()
		_style_field(pt_ak)
		pt_ak.custom_minimum_size = Vector2(220, 28)
		pt_ak.add_item("4…20 мА", 0)
		pt_ak.add_item("0…10 В", 1)
		pt_ak.add_item("0…1 В", 2)
		var pt_ak_sel: int = 0
		match SensorSig.normalize_analog(str(el.analog_kind)):
			SensorSig.ANALOG_0_10V:
				pt_ak_sel = 1
			SensorSig.ANALOG_0_1V:
				pt_ak_sel = 2
			_:
				pt_ak_sel = 0
		pt_ak.select(pt_ak_sel)
		pt_ak.item_selected.connect(func(i):
			match int(i):
				1:
					el.analog_kind = SensorSig.ANALOG_0_10V
				2:
					el.analog_kind = SensorSig.ANALOG_0_1V
				_:
					el.analog_kind = SensorSig.ANALOG_4_20MA
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Аналоговый выход", pt_ak))
		var pt_note := Label.new()
		pt_note.text = "Активный ПИП: без Uпит нет валидного аналога. Blind — P и сигнал в tooltip."
		pt_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pt_note.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(pt_note)
	elif is_rtd:
		var rtd_box := OptionButton.new()
		_style_field(rtd_box)
		rtd_box.custom_minimum_size = Vector2(220, 28)
		var rtd_rows: Array = SensorCat.rtd_sizes()
		var rtd_sel: int = SensorCat.nearest_rtd_index(SensorCat.rtd_type_of(el))
		for i in rtd_rows.size():
			rtd_box.add_item(str((rtd_rows[i] as Dictionary).get("label", "")), i)
		rtd_box.select(rtd_sel)
		rtd_box.item_selected.connect(func(i):
			SensorCat.apply_rtd_size(el, int(i))
			var row_r: Dictionary = SensorCat.rtd_sizes()[int(i)] as Dictionary
			var typ_r: String = str(row_r.get("rtd_type", "pt100"))
			if typ_r == "100p":
				el.recipe_id = "rtd_100p"
			elif typ_r == "cu100":
				el.recipe_id = "rtd_cu100"
			else:
				el.recipe_id = "rtd_pt100"
			el.catalog_id = el.recipe_id
			if circuit != null:
				var SensorLibR = preload("res://scripts/domain/sensor_library.gd")
				SensorLibR.sync_rtd_meter(circuit, el)
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("НСХ / типоразмер", rtd_box))
		var ws_box := OptionButton.new()
		_style_field(ws_box)
		ws_box.custom_minimum_size = Vector2(220, 28)
		ws_box.add_item("2-провод (с погрешностью R кабеля)", 2)
		ws_box.add_item("3-провод (компенсация при равных плечах)", 3)
		ws_box.add_item("4-провод (полная компенсация)", 4)
		var ws_cur: int = clampi(int(el.wire_scheme), 2, 4)
		ws_box.select(ws_cur - 2)
		ws_box.item_selected.connect(func(i):
			el.wire_scheme = clampi(int(i) + 2, 2, 4)
			if circuit != null:
				var SensorLibW = preload("res://scripts/domain/sensor_library.gd")
				SensorLibW.sync_rtd_meter(circuit, el)
			_scheme_changed()
			call_deferred("_open_general_params", Vector2.ZERO, el)
		)
		box.add_child(_menu_labeled("Схема подключения", ws_box))
		var t_zone := SpinBox.new()
		_style_field(t_zone)
		t_zone.min_value = float(el.sense_min_mm)
		t_zone.max_value = maxf(float(el.sense_range_mm), t_zone.min_value + 1.0)
		t_zone.step = 0.5
		t_zone.value = clampf(float(el.temperature_c), t_zone.min_value, t_zone.max_value)
		t_zone.suffix = " °C"
		t_zone.custom_minimum_size = Vector2(220, 28)
		t_zone.value_changed.connect(func(v):
			el.temperature_c = float(v)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("T зоны (на зонде)", t_zone))
		var rtd_note := Label.new()
		rtd_note.text = "Пассивный ТС: 24 В в головке не нужно. Показание — на вторичке в щите (возбуждение ~40 мкА). 2-провод: Rизм = Rдат + 2·Rжилы."
		rtd_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtd_note.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(rtd_note)
	if not is_pressure_switch and not is_pressure_tx and not is_rtd:
		var sn_sb := SpinBox.new()
		_style_field(sn_sb)
		sn_sb.min_value = 0.5
		sn_sb.max_value = 40.0
		sn_sb.step = 0.1
		sn_sb.value = float(el.sense_range_mm)
		sn_sb.suffix = " мм"
		sn_sb.custom_minimum_size = Vector2(220, 28)
		sn_sb.value_changed.connect(func(v):
			el.sense_range_mm = float(v)
			_scheme_changed()
		)
		var sn_label: String = "Sn (сталь)"
		if is_reed:
			sn_label = "Зазор до магнита"
		elif is_capacitive:
			sn_label = "Sn (вода/диэлектрик)"
		elif is_optical:
			sn_label = "Sn (диффуз / белая карта)"
			sn_sb.max_value = 800.0
		elif is_ultrasonic:
			sn_label = "Дальность (конец диапазона)"
			sn_sb.min_value = 10.0
			sn_sb.max_value = 4000.0
			sn_sb.step = 1.0
		box.add_child(_menu_labeled(sn_label, sn_sb))
	if is_ultrasonic:
		var smin_sb := SpinBox.new()
		_style_field(smin_sb)
		smin_sb.min_value = 1.0
		smin_sb.max_value = 500.0
		smin_sb.step = 1.0
		smin_sb.value = maxf(float(el.sense_min_mm), 1.0)
		smin_sb.suffix = " мм"
		smin_sb.custom_minimum_size = Vector2(220, 28)
		smin_sb.value_changed.connect(func(v):
			el.sense_min_mm = float(v)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Мёртвая зона (начало)", smin_sb))
		var DetectUs = preload("res://scripts/domain/sensor_detection.gd")
		var set_sb := SpinBox.new()
		_style_field(set_sb)
		set_sb.min_value = maxf(float(el.sense_min_mm), 1.0)
		set_sb.max_value = maxf(float(el.sense_range_mm), set_sb.min_value + 1.0)
		set_sb.step = 1.0
		set_sb.value = DetectUs.ultrasonic_setpoint_mm(el)
		set_sb.suffix = " мм"
		set_sb.custom_minimum_size = Vector2(220, 28)
		set_sb.value_changed.connect(func(v):
			DetectUs.set_ultrasonic_setpoint_mm(el, float(v))
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Уставка OUT (switching)", set_sb))
		var ak_box := OptionButton.new()
		_style_field(ak_box)
		ak_box.custom_minimum_size = Vector2(220, 28)
		ak_box.add_item("0…10 В", 0)
		ak_box.add_item("4…20 мА", 1)
		ak_box.add_item("0…1 В", 2)
		var ak_sel: int = 0
		match SensorSig.normalize_analog(str(el.analog_kind)):
			SensorSig.ANALOG_4_20MA:
				ak_sel = 1
			SensorSig.ANALOG_0_1V:
				ak_sel = 2
			_:
				ak_sel = 0
		ak_box.select(ak_sel)
		ak_box.item_selected.connect(func(i):
			match int(i):
				1:
					el.analog_kind = SensorSig.ANALOG_4_20MA
				2:
					el.analog_kind = SensorSig.ANALOG_0_1V
				_:
					el.analog_kind = SensorSig.ANALOG_0_10V
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Аналоговый выход", ak_box))
	if is_inductive or is_capacitive or is_optical:
		var thr_sb := SpinBox.new()
		_style_field(thr_sb)
		thr_sb.min_value = 0.0
		thr_sb.max_value = 100.0
		thr_sb.step = 1.0
		thr_sb.value = clampf(float(el.threshold_pct), 0.0, 100.0)
		thr_sb.suffix = " %"
		thr_sb.custom_minimum_size = Vector2(220, 28)
		thr_sb.value_changed.connect(func(v):
			el.threshold_pct = clampf(float(v), 0.0, 100.0)
			_scheme_changed()
		)
		var thr_lab: String = "Уставка (винт)"
		if is_optical:
			thr_lab = "Уставка (SET / винт)"
		box.add_child(_menu_labeled(thr_lab, thr_sb))
	if is_optical and str(el.optical_form) != "compact":
		var lo_box := OptionButton.new()
		_style_field(lo_box)
		lo_box.custom_minimum_size = Vector2(220, 28)
		lo_box.add_item("Dark-ON (срабатывание при перекрытии луча)", 0)
		lo_box.add_item("Light-ON (срабатывание при наличии луча)", 1)
		lo_box.select(1 if bool(el.optical_light_on) else 0)
		lo_box.item_selected.connect(func(i):
			el.optical_light_on = int(i) == 1
			_scheme_changed()
		)
		box.add_child(_menu_labeled("LO / DO (барьер)", lo_box))
	if is_reed or is_pressure_switch:
		var out_lab := Label.new()
		if is_pressure_switch:
			out_lab.text = "Выход: сухой контакт на KP·.1 · без Uпит головки (мембрана)"
		else:
			out_lab.text = "Выход: сухой контакт · 2 провода (OUT–0), без Uпит"
		out_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(out_lab)
		el.output_type = SensorSig.OUT_CONTACT
		el.sensor_active = false
	elif is_rtd:
		var out_rtd := Label.new()
		out_rtd.text = "Выход: сопротивление ТС · вторичка в щите (Uпит прибора)"
		out_rtd.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(out_rtd)
		el.output_type = SensorSig.OUT_CONTACT
		el.sensor_active = false
		el.analog_kind = SensorSig.ANALOG_RTD
	elif is_pressure_tx:
		var supply_pt := OptionButton.new()
		_style_field(supply_pt)
		supply_pt.custom_minimum_size = Vector2(220, 28)
		supply_pt.add_item("= 24 В", 0)
		supply_pt.add_item("~ 220 В", 1)
		supply_pt.select(1 if SensorSig.normalize_supply(str(el.supply_mode)) == SensorSig.SUPPLY_220AC else 0)
		supply_pt.item_selected.connect(func(i):
			el.supply_mode = SensorSig.SUPPLY_220AC if int(i) == 1 else SensorSig.SUPPLY_24DC
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Uпит", supply_pt))
		el.sensor_active = true
	else:
		var supply_box := OptionButton.new()
		_style_field(supply_box)
		supply_box.custom_minimum_size = Vector2(220, 28)
		supply_box.add_item("= 24 В", 0)
		supply_box.add_item("~ 220 В", 1)
		supply_box.select(1 if SensorSig.normalize_supply(str(el.supply_mode)) == SensorSig.SUPPLY_220AC else 0)
		supply_box.item_selected.connect(func(i):
			el.supply_mode = SensorSig.SUPPLY_220AC if int(i) == 1 else SensorSig.SUPPLY_24DC
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Uпит", supply_box))
		var out_box := OptionButton.new()
		_style_field(out_box)
		out_box.custom_minimum_size = Vector2(220, 28)
		out_box.add_item("NPN", 0)
		out_box.add_item("PNP", 1)
		out_box.add_item("Контакт", 2)
		var out_sel: int = 0
		match SensorSig.normalize_output(str(el.output_type)):
			SensorSig.OUT_PNP:
				out_sel = 1
			SensorSig.OUT_CONTACT:
				out_sel = 2
			_:
				out_sel = 0
		out_box.select(out_sel)
		out_box.item_selected.connect(func(i):
			match int(i):
				1:
					el.output_type = SensorSig.OUT_PNP
				2:
					el.output_type = SensorSig.OUT_CONTACT
				_:
					el.output_type = SensorSig.OUT_NPN
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Тип выхода", out_box))
	if not is_pressure_tx and not is_rtd:
		var form_box := OptionButton.new()
		_style_field(form_box)
		form_box.custom_minimum_size = Vector2(220, 28)
		form_box.add_item("NO (нормально разомкнут)", 0)
		form_box.add_item("NC (нормально замкнут)", 1)
		form_box.select(1 if SensorSig.normalize_form(str(el.contact_form)) == SensorSig.FORM_NC else 0)
		form_box.item_selected.connect(func(i):
			el.contact_form = SensorSig.FORM_NC if int(i) == 1 else SensorSig.FORM_NO
			if is_pressure_switch and circuit != null:
				var SensorLibPs = preload("res://scripts/domain/sensor_library.gd")
				SensorLibPs.sync_pressure_switch_contact_form(circuit, el)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Контакт", form_box))
	if not is_pressure_switch and not is_pressure_tx and not is_rtd:
		var hyst_sb := SpinBox.new()
		_style_field(hyst_sb)
		hyst_sb.min_value = 0.0
		hyst_sb.max_value = 50.0 if is_ultrasonic else 5.0
		hyst_sb.step = 0.5 if is_ultrasonic else 0.05
		hyst_sb.value = float(el.hysteresis_mm)
		hyst_sb.suffix = " мм"
		hyst_sb.custom_minimum_size = Vector2(220, 28)
		hyst_sb.value_changed.connect(func(v):
			el.hysteresis_mm = float(v)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Гистерезис", hyst_sb))


func _add_general_opto_tip_params(box: VBoxContainer, el) -> void:
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var role_lab := Label.new()
	var role: String = str(el.opto_role)
	var role_title: String = "диффуз/рефлектор (head)"
	if role == "emitter":
		role_title = "излучатель (барьер T)"
	elif role == "receiver":
		role_title = "приёмник (барьер T)"
	role_lab.text = "Оптонаконечник: %s" % role_title
	role_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(role_lab)
	var role_box := OptionButton.new()
	_style_field(role_box)
	role_box.custom_minimum_size = Vector2(220, 28)
	role_box.add_item("Излучатель (T)", 0)
	role_box.add_item("Приёмник (T)", 1)
	role_box.add_item("Головка D/R", 2)
	var role_sel: int = 2
	if role == "emitter":
		role_sel = 0
	elif role == "receiver":
		role_sel = 1
	role_box.select(role_sel)
	role_box.item_selected.connect(func(i):
		match int(i):
			0:
				el.opto_role = "emitter"
			1:
				el.opto_role = "receiver"
			_:
				el.opto_role = "head"
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Роль", role_box))
	var hint := Label.new()
	hint.text = "Режим задаётся геометрией: T = TX↔RX навстречу; R = луч на рефлектор; D = отражение от объекта. Оптокабель — чёрный, как трубка."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(hint)


func _add_general_motor_params(box: VBoxContainer, el) -> void:
	var MotorCat = preload("res://scripts/domain/motor_catalog.gd")
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var cls_lab := Label.new()
	if MotorCat.is_turbine(el):
		cls_lab.text = "Класс: турбинный"
	elif MotorCat.is_vane(el):
		cls_lab.text = "Класс: лопастной"
	else:
		cls_lab.text = "Класс: шестерённый"
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	var stall_lo: float = MotorCat.stall_min_of(el)
	var stall_hi: float = MotorCat.stall_max_of(el)
	var stall_sb := SpinBox.new()
	_style_field(stall_sb)
	stall_sb.min_value = stall_lo
	stall_sb.max_value = stall_hi
	stall_sb.step = 0.05
	stall_sb.value = clampf(float(el.torque_nm_at_6bar), stall_lo, stall_hi)
	stall_sb.suffix = " Н·м"
	stall_sb.custom_minimum_size = Vector2(220, 28)
	stall_sb.value_changed.connect(func(v):
		# Якорь: stall → подстановка rpm/Qn из таблицы; 3D пересобирается по sig.
		MotorCat.apply_stall_anchor(el, float(v))
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Момент стоп @6 бар", stall_sb))
	var rpm_sb := SpinBox.new()
	_style_field(rpm_sb)
	rpm_sb.min_value = 100.0
	rpm_sb.max_value = 30000.0
	rpm_sb.step = 50.0
	rpm_sb.value = clampf(float(el.free_rpm), 100.0, 30000.0)
	rpm_sb.suffix = " об/мин"
	rpm_sb.custom_minimum_size = Vector2(220, 28)
	rpm_sb.value_changed.connect(func(v):
		el.free_rpm = clampf(float(v), 100.0, 30000.0)
		el.recipe_id = ""
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Холостые обороты", rpm_sb))
	var qn_sb := SpinBox.new()
	_style_field(qn_sb)
	qn_sb.min_value = 50.0
	qn_sb.max_value = 10000.0
	qn_sb.step = 10.0
	qn_sb.value = clampf(float(el.flow_nl_min), 50.0, 10000.0)
	qn_sb.suffix = " Nl/мин"
	qn_sb.custom_minimum_size = Vector2(220, 28)
	qn_sb.value_changed.connect(func(v):
		el.flow_nl_min = clampf(float(v), 50.0, 10000.0)
		el.recipe_id = ""
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Ном. расход Qn (6→5 бар)", qn_sb))
	var fit_box := OptionButton.new()
	_style_field(fit_box)
	fit_box.custom_minimum_size = Vector2(220, 28)
	var fit_rows: Array = [
		{"id": "G1/8_6", "label": "G1/8 · Ø6", "thread": "G1/8", "od": 6.0},
		{"id": "G1/4_8", "label": "G1/4 · Ø8", "thread": "G1/4", "od": 8.0},
		{"id": "G3/8_10", "label": "G3/8 · Ø10", "thread": "G3/8", "od": 10.0},
	]
	var fsel := 0
	for fi in fit_rows.size():
		var fr: Dictionary = fit_rows[fi] as Dictionary
		fit_box.add_item(str(fr.get("label", "")))
		fit_box.set_item_metadata(fi, fr)
		if str(fr.get("thread", "")) == str(el.port_name) \
				and absf(float(fr.get("od", 0.0)) - float(el.tube_od_mm)) < 0.2:
			fsel = fi
	fit_box.selected = fsel
	fit_box.item_selected.connect(func(idx: int):
		var fr2: Dictionary = fit_box.get_item_metadata(idx) as Dictionary
		el.port_name = str(fr2.get("thread", "G1/4"))
		el.tube_od_mm = float(fr2.get("od", 8.0))
		el.fitting_id = str(fr2.get("id", ""))
		el.recipe_id = ""
		if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
			circuit._sync_wires_od_from_port_el(el)
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Присоединение", fit_box))
	# Реверсивный ПМ: каждый порт — глушитель или штуцер по отдельности.
	var in_box := OptionButton.new()
	_style_field(in_box)
	in_box.custom_minimum_size = Vector2(220, 28)
	in_box.add_item("Глушитель")
	in_box.set_item_metadata(0, "muffler")
	in_box.add_item("Штуцер (трубка)")
	in_box.set_item_metadata(1, "fitting")
	in_box.selected = 0 if MotorCat.port_is_muffler(el, "in") else 1
	in_box.item_selected.connect(func(idx: int):
		el.port_5 = str(in_box.get_item_metadata(idx))
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Порт in", in_box))
	var exh_box := OptionButton.new()
	_style_field(exh_box)
	exh_box.custom_minimum_size = Vector2(220, 28)
	exh_box.add_item("Глушитель")
	exh_box.set_item_metadata(0, "muffler")
	exh_box.add_item("Штуцер (трубка)")
	exh_box.set_item_metadata(1, "fitting")
	exh_box.selected = 0 if MotorCat.port_is_muffler(el, "exhaust") else 1
	exh_box.item_selected.connect(func(idx: int):
		el.port_3 = str(exh_box.get_item_metadata(idx))
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Порт exhaust", exh_box))


func _add_cylinder_fitting_control_for_rotary(box: VBoxContainer, el) -> void:
	var fit_box := OptionButton.new()
	_style_field(fit_box)
	fit_box.custom_minimum_size = Vector2(220, 28)
	var sel: int = 0
	var i: int = 0
	var cur: String = str(el.fitting_id)
	for item in TubeFit.fittings_for_bore(float(el.bore_mm)):
		fit_box.add_item(str(item.get("label", item.get("id", ""))))
		fit_box.set_item_metadata(i, str(item.get("id", "")))
		if str(item.get("id", "")) == cur:
			sel = i
		i += 1
	fit_box.selected = sel
	fit_box.item_selected.connect(func(idx: int):
		var fid: String = str(fit_box.get_item_metadata(idx))
		var note: String = TubeFit.apply_fitting(el, fid)
		if note != "":
			circuit.notify(note)
		else:
			circuit.notify("Фитинг: %s" % str(el.fitting_id))
		_scheme_changed()
		call_deferred("_open_general_params", Vector2.ZERO, el)
	)
	box.add_child(_menu_labeled("Фитинг (цанга)", fit_box))


func _add_general_cylinder_params(box: VBoxContainer, el) -> void:
	# Поршень (bore/фитинг)/шток/амортизация — в окнах частей; здесь обозначение, нагрузка, крепёж, расчёт.
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	TubeFit.conform_cylinder_fitting(el)
	var fit_lab := Label.new()
	fit_lab.text = "Фитинг: %s · Ø%.0f" % [str(el.port_name), float(el.tube_od_mm)]
	fit_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(fit_lab)
	var fit_hint := Label.new()
	fit_hint.text = "Смена фитинга — ПКМ по поршню УГО"
	fit_hint.add_theme_font_size_override("font_size", 11)
	fit_hint.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(fit_hint)
	var load := SpinBox.new()
	_style_field(load)
	load.min_value = -2000
	load.max_value = 8000
	load.step = 5
	load.value = el.load_n
	load.custom_minimum_size = Vector2(220, 28)
	load.value_changed.connect(func(v):
		el.load_n = v
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Нагрузка, Н", load))
	if str(el.rod_mode) != "rodless":
		_add_option_param(box, el, "spring", "Пружина", str(el.spring_side), func(id: String):
			var before_action := str(el.action)
			el.spring_side = id
			var note_s: String = circuit.retune_geometry(el)
			if str(el.action) != before_action:
				circuit.reconfigure_action(el)
			if note_s != "":
				circuit.notify(note_s)
		, true)
	_add_option_param(box, el, "body", "Корпус", str(el.body_style), func(id: String):
		el.body_style = id
		_scheme_changed()
	, true)
	_add_option_param(box, el, "mount", "Крепление", str(el.mount), func(id: String):
		el.mount = id
		_scheme_changed()
	, true)
	_add_option_param(box, el, "guide", "Направляющая", str(el.guide), func(id: String):
		el.guide = id
		_scheme_changed()
	, true)
	_add_option_param(box, el, "brake", "Тормоз", str(el.brake), func(id: String):
		el.brake = id
		_scheme_changed()
	, true)
	box.add_child(_menu_rule())
	_add_calc_block(box, el, "")


func _add_general_valve_params(box: VBoxContainer, el) -> void:
	# Линии/позиции/органы/клетки — в окнах частей; типоразмер + Cv + выхлопы + расчёт — здесь.
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	_add_valve_size_control(box, el)
	var cv := HSlider.new()
	_style_slider(cv)
	cv.min_value = 0.2
	cv.max_value = 4.0
	cv.step = 0.1
	cv.value = float(el.valve_cv)
	cv.value_changed.connect(func(v):
		el.valve_cv = v
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Cv (из Qn / ручной)", cv))
	_add_valve_tab_ports(box, el)
	box.add_child(_menu_rule())
	_add_calc_block(box, el, "")


func _add_junction_params(box: VBoxContainer, el) -> void:
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	if str(el.junction_style) == "adapter":
		_add_adapter_od_pickers(box, el)
		var hint_ad := Label.new()
		hint_ad.text = "Порт 1 ← ØA, порт 2 → ØB. При соединении разных Ø вставляется сам."
		hint_ad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_ad.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_ad)
		return
	var style_box := OptionButton.new()
	_style_field(style_box)
	style_box.custom_minimum_size = Vector2(220, 28)
	var styles := [
		["tee", "Тройник T"],
		["wye", "Тройник Y"],
		["manifold", "Коллектор 5"],
		["adapter", "Переходник Ø→Ø"],
	]
	var sel := 0
	for i in styles.size():
		style_box.add_item(str(styles[i][1]))
		style_box.set_item_metadata(i, str(styles[i][0]))
		if str(styles[i][0]) == str(el.junction_style):
			sel = i
	style_box.selected = sel
	style_box.item_selected.connect(func(idx: int):
		el.junction_style = str(style_box.get_item_metadata(idx))
		if el.junction_style == "adapter":
			el.junction_ports = 2
			if float(el.tube_od_mm) < 1.0:
				el.tube_od_mm = 6.0
			if float(el.tube_od_b_mm) < 1.0:
				el.tube_od_b_mm = 8.0
		elif el.junction_style == "manifold":
			el.junction_ports = 5
		else:
			el.junction_ports = 3
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Тип фитинга", style_box))
	_add_armature_od_picker(box, el)


func _add_adapter_od_pickers(box: VBoxContainer, el) -> void:
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var sizes: Array = TubeFit.tube_od_catalog()
	var side_specs: Array = [
		["Фитинг слева (1)", "tube_od_mm"],
		["Фитинг справа (2)", "tube_od_b_mm"],
	]
	for side_v in side_specs:
		var side: Array = side_v as Array
		var caption: String = str(side[0])
		var field: String = str(side[1])
		var od_box := OptionButton.new()
		_style_field(od_box)
		od_box.custom_minimum_size = Vector2(220, 28)
		var cur: float = float(el.get(field)) if el.get(field) != null else 6.0
		if cur < 1.0:
			cur = 6.0 if field == "tube_od_mm" else 8.0
		var sel_i: int = 0
		for i in sizes.size():
			var odv: float = float(sizes[i])
			od_box.add_item("Трубка Ø%.0f" % odv)
			od_box.set_item_metadata(i, odv)
			if absf(odv - cur) < 0.15:
				sel_i = i
		od_box.select(sel_i)
		od_box.item_selected.connect(func(idx: int):
			var od_new: float = float(od_box.get_item_metadata(idx))
			if field == "tube_od_mm":
				el.tube_od_mm = od_new
				el.port_name = TubeFit.thread_for_tube_od(od_new)
			else:
				el.tube_od_b_mm = od_new
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled(caption, od_box))


func _add_armature_od_picker(box: VBoxContainer, el) -> void:
	var TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")
	var od_box := OptionButton.new()
	_style_field(od_box)
	od_box.custom_minimum_size = Vector2(220, 28)
	var cur: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0
	var sizes: Array = TubeFit.tube_od_catalog()
	var sel: int = 0
	# «Авто» — OD берётся с подключаемой трубки (тройник без явного размера).
	if str(el.kind) == "junction":
		od_box.add_item("Авто (по трубке)")
		od_box.set_item_metadata(0, 0.0)
		sel = 0
		for i in sizes.size():
			var odv: float = float(sizes[i])
			od_box.add_item("Трубка Ø%.0f" % odv)
			od_box.set_item_metadata(i + 1, odv)
			if cur >= 1.0 and absf(odv - cur) < 0.15:
				sel = i + 1
	else:
		if cur < 1.0:
			cur = 6.0
		for i in sizes.size():
			var odv2: float = float(sizes[i])
			od_box.add_item("Трубка Ø%.0f" % odv2)
			od_box.set_item_metadata(i, odv2)
			if absf(odv2 - cur) < 0.15:
				sel = i
	od_box.selected = sel
	od_box.item_selected.connect(func(idx: int):
		var od_pick: float = float(od_box.get_item_metadata(idx))
		TubeFit.apply_armature_od(el, od_pick)
		if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
			circuit._sync_wires_od_from_port_el(el)
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Типоразмер (трубка)", od_box))


func _add_valve_properties_tabs(box: VBoxContainer, el) -> void:
	_add_sectioned_props(box, [
		["Корпус", func(p: VBoxContainer): _add_valve_tab_body(p, el)],
		["Управление", func(p: VBoxContainer): _add_valve_tab_ops(p, el)],
		["Золотник", func(p: VBoxContainer): _add_envelope_pickers(p, el)],
		["Порты", func(p: VBoxContainer): _add_valve_tab_ports(p, el)],
		["Расчёт", func(p: VBoxContainer): _add_calc_block(p, el, "")],
	])


func _add_cylinder_properties_tabs(box: VBoxContainer, el) -> void:
	_add_sectioned_props(box, [
		["Параметры", func(p: VBoxContainer): _add_cylinder_params(p, el)],
		["Расчёт", func(p: VBoxContainer): _add_calc_block(p, el, "")],
	])


func _add_sectioned_props(box: VBoxContainer, sections: Array) -> void:
	# Слева разделы, справа один scroll со страницами — без серой подложки и без
	# внешнего скролла, который подрезал ширину.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 340)
	box.add_child(row)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(112, 0)
	nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 2)
	row.add_child(nav)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(260, 320)
	_style_scroll(scroll)
	row.add_child(scroll)
	# Правый запас: поля не упираются в трек скроллбара.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_top", 2)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)
	var pages_host := VBoxContainer.new()
	pages_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages_host.add_theme_constant_override("separation", 0)
	pad.add_child(pages_host)
	var pages: Array = []
	var buttons: Array = []
	var active := clampi(_props_section_idx, 0, maxi(sections.size() - 1, 0))
	_props_section_idx = active
	for i in sections.size():
		var sec: Array = sections[i]
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		page.visible = i == active
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages_host.add_child(page)
		pages.append(page)
		(sec[1] as Callable).call(page)
		var btn := Button.new()
		btn.text = str(sec[0])
		btn.toggle_mode = true
		btn.button_pressed = i == active
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_section_nav_btn(btn, i == active)
		var idx := i
		btn.pressed.connect(func():
			_props_section_idx = idx
			for j in pages.size():
				pages[j].visible = j == idx
				var b: Button = buttons[j]
				b.button_pressed = j == idx
				_style_section_nav_btn(b, j == idx)
		)
		nav.add_child(btn)
		buttons.append(btn)


func _style_section_nav_btn(btn: Button, active: bool) -> void:
	# Как пункты меню частей: без серых карточек.
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiTheme.field_active() if active else Color(0, 0, 0, 0)
	normal.border_color = UiTheme.field_border() if active else Color(0, 0, 0, 0)
	normal.border_width_left = 3 if active else 0
	normal.border_width_top = 0
	normal.border_width_right = 0
	normal.border_width_bottom = 0
	normal.set_corner_radius_all(0)
	normal.shadow_size = 0
	normal.content_margin_left = 10
	normal.content_margin_right = 8
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	if not active:
		hover.bg_color = UiTheme.paper().darkened(0.03)
	for key in ["normal", "pressed", "hover", "focus", "disabled"]:
		btn.add_theme_stylebox_override(key, hover if key == "hover" and not active else normal)
	var fg := UiTheme.paper_text()
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_focus_color", fg)
	btn.add_theme_font_size_override("font_size", 13)


func _add_valve_tab_body(box: VBoxContainer, el) -> void:
	# Устарело (панель «Свойства» отключена) — оставлено для совместимости вызовов.
	_add_valve_size_control(box, el)
	_add_option_param(box, el, "ways", "Линии", str(el.valve_ways), func(id: String):
		el.valve_ways = int(id)
		_clear_spool_schema(el)
	, true)
	_add_option_param(box, el, "positions", "Позиции", str(el.valve_positions), func(id: String):
		el.valve_positions = int(id)
		_clear_spool_schema(el)
	, true)


func _add_valve_size_control(box: VBoxContainer, el) -> void:
	if str(el.kind) != "valve":
		return
	ValveCat.conform_size(el)
	var size_box := OptionButton.new()
	_style_field(size_box)
	size_box.custom_minimum_size = Vector2(220, 28)
	var sel: int = 0
	var i: int = 0
	var cur: String = str(el.fitting_id)
	for item in ValveCat.size_classes():
		size_box.add_item(str(item.get("label", item.get("id", ""))))
		size_box.set_item_metadata(i, str(item.get("id", "")))
		if str(item.get("id", "")) == cur:
			sel = i
		i += 1
	size_box.selected = sel
	size_box.item_selected.connect(func(idx: int):
		var sid: String = str(size_box.get_item_metadata(idx))
		var note: String = ValveCat.apply_size(el, sid)
		circuit._sync_wires_od_from_port_el(el)
		if note != "":
			circuit.notify(note)
		else:
			circuit.notify("Типоразмер: %s" % str(el.fitting_id))
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Типоразмер (порт / трубка)", size_box))


func _add_valve_tab_ops(box: VBoxContainer, el) -> void:
	_add_option_param(box, el, "op_left", "Управление слева", str(el.op_left), func(id: String):
		el.op_left = id
	, true)
	if str(el.op_left) in ["solenoid", "solenoid_pilot"]:
		_add_check_param(box, el, "Ручной дублёр слева", bool(el.override_left), func(on: bool):
			el.override_left = on
		)
	_add_option_param(box, el, "op_right", "Управление справа", str(el.op_right), func(id: String):
		el.op_right = id
	, true)
	if str(el.op_right) in ["solenoid", "solenoid_pilot"]:
		_add_check_param(box, el, "Ручной дублёр справа", bool(el.override_right), func(on: bool):
			el.override_right = on
		)
	_add_option_param(box, el, "pilot_supply", "Питание пилота", str(el.pilot_supply), func(id: String):
		el.pilot_supply = id
	)


func _add_valve_tab_ports(box: VBoxContainer, el) -> void:
	if int(el.valve_ways) >= 3:
		_add_check_param(box, el, "Глушитель на 3(R1)", str(el.port_3) == "muffler", func(on: bool):
			el.port_3 = "muffler" if on else "fitting"
		)
	if int(el.valve_ways) >= 5:
		_add_check_param(box, el, "Глушитель на 5(R2)", str(el.port_5) == "muffler", func(on: bool):
			el.port_5 = "muffler" if on else "fitting"
		)
	if int(el.valve_ways) < 3:
		var empty := Label.new()
		empty.text = "Нет настраиваемых выхлопов"
		empty.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(empty)


func _add_part_params(box: VBoxContainer, el, part: String) -> void:
	# Жёстко только поля этой части УГО.
	if el.kind == "electro":
		if part == "lens":
			_add_caption_field(box, el)
			_add_electro_choice_row(box, el, "lamp_color", "Цвет линзы", "lens")
			_add_electro_choice_row(box, el, "lamp_voltage", "Напряжение", "lens")
		elif part == "operator":
			_add_button_operator_params(box, el)
		elif part == "cam":
			_add_switch_params(box, el)
		elif part == "bus_color":
			pass # варианты в _part_options_for
		elif part == "bus_taps":
			var taps := SpinBox.new()
			_style_field(taps)
			taps.min_value = 2
			taps.max_value = 12
			taps.step = 1
			taps.value = maxi(el.electro_ports.size(), 2)
			taps.custom_minimum_size = Vector2(220, 28)
			taps.value_changed.connect(func(v):
				var n: int = int(v)
				var ports: Array = []
				for i in n:
					ports.append({"name": str(i + 1), "type": "line"})
				el.electro_ports = ports
				_scheme_changed()
				call_deferred("_open_parts_refresh", el)
			)
			box.add_child(_menu_labeled("Отводов", taps))
			_add_caption_field(box, el)
		elif part == "device_title":
			_add_caption_field(box, el)
		elif part == "device_ports" or part == "device_table_left" or part == "device_table_right":
			_add_psu_params(box, el)
		elif part == "supply":
			_add_supply_params(box, el)
		elif part == "terminal":
			_add_terminal_params(box, el)
		elif part == "lever":
			_add_breaker_params(box, el)
		elif part == "coil":
			_add_coil_electrical_params(box, el)
			if str(el.electro_class) == "timer_relay":
				_add_timer_relay_params(box, el)
			elif str(el.electro_class) in ["relay", "contactor", "thermal"]:
				_add_coil_contact_params(box, el)
		elif part == "pilot":
			var side := OptionButton.new()
			_style_field(side)
			side.custom_minimum_size = Vector2(220, 28)
			side.add_item("Левая (L)", 0)
			side.add_item("Правая (R)", 1)
			side.select(1 if str(el.linked_valve_side) == "R" else 0)
			side.item_selected.connect(func(i):
				el.linked_valve_side = "R" if i == 1 else "L"
				circuit.renumber_tags()
				_scheme_changed()
			)
			box.add_child(_menu_labeled("Сторона ПР", side))
		return
	if el.kind == "valve":
		if part.begins_with("cell_"):
			var cell_i := int(part.substr(5))
			box.add_child(_menu_rule())
			_add_envelope_picker_for(box, el, cell_i)
			return
		match part:
			"body":
				box.add_child(_menu_rule())
				_add_valve_size_control(box, el)
				_add_option_param(box, el, "positions", "Позиции", str(el.valve_positions), func(id: String):
					el.valve_positions = int(id)
					_clear_spool_schema(el)
				, true)
				if int(el.valve_positions) == 3:
					_add_option_param(box, el, "center", "Центр", str(el.valve_center), func(id: String):
						el.valve_center = id
						_clear_spool_schema(el)
					, true)
				if int(el.valve_ways) <= 3:
					_add_option_param(box, el, "nc_no", "Нормально", str(el.valve_nc_no), func(id: String):
						el.valve_nc_no = id
						_clear_spool_schema(el)
					, true)
			"op_left":
				if str(el.op_left) in ["solenoid", "solenoid_pilot"]:
					box.add_child(_menu_rule())
					_add_check_param(box, el, "Ручной дублёр", bool(el.override_left), func(on: bool):
						el.override_left = on
					)
			"op_right":
				if str(el.op_right) in ["solenoid", "solenoid_pilot"]:
					box.add_child(_menu_rule())
					_add_check_param(box, el, "Ручной дублёр", bool(el.override_right), func(on: bool):
						el.override_right = on
					)
			_:
				pass
		return
	if el.kind != "cylinder":
		return
	match part:
		"piston":
			box.add_child(_menu_rule())
			_add_bore_control(box, el)
			_add_cylinder_fitting_control(box, el)
		"rod":
			box.add_child(_menu_rule())
			if str(el.rod_mode) != "rodless":
				_add_rod_control(box, el)
			_add_stroke_control(box, el)
			if str(el.rod_mode) == "rodless":
				# menu_part=rod — не уходить в отдельное крошечное меню только упоров.
				_add_part_choice_row(box, el, "bump_end", "Упоры каретки", "rod")
		"cush_cap":
			if str(el.cush_cap) == "adjustable":
				box.add_child(_menu_rule())
				_add_cush_open_control(box, el, true)
		"cush_rod":
			if str(el.cush_rod) == "adjustable":
				box.add_child(_menu_rule())
				_add_cush_open_control(box, el, false)
		_:
			pass


func _add_cush_open_control(box: VBoxContainer, el, cap_side: bool) -> void:
	var open := HSlider.new()
	_style_slider(open)
	open.min_value = 0.0
	open.max_value = 1.0
	open.step = 0.01
	open.value = float(el.cush_open_cap) if cap_side else float(el.cush_open_rod)
	open.custom_minimum_size = Vector2(220, 28)
	# Не пересобирать меню на каждый тик — иначе ползунок «прыгает» кликом.
	var part := "cush_cap" if cap_side else "cush_rod"
	open.value_changed.connect(func(v):
		if cap_side:
			el.cush_open_cap = v
		else:
			el.cush_open_rod = v
		_refresh_calc_labels(box, el, part)
	)
	box.add_child(_menu_labeled("Открытие иглы (0=жёстко)", open))


func _add_part_choice_row(box: VBoxContainer, el, part: String, caption: String, menu_part: String = "") -> void:
	box.add_child(_menu_rule())
	var head := Label.new()
	head.text = caption
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", UiTheme.muted())
	var head_pad := MarginContainer.new()
	head_pad.add_theme_constant_override("margin_left", 8)
	head_pad.add_child(head)
	box.add_child(head_pad)
	var stay := menu_part if menu_part != "" else part
	for opt in Catalog.part_options(part):
		box.add_child(_choice_button(str(opt["label"]), part, str(opt["id"]), el, stay))


func _add_electro_choice_row(box: VBoxContainer, el, part: String, caption: String, menu_part: String) -> void:
	box.add_child(_menu_rule())
	var head := Label.new()
	head.text = caption
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", UiTheme.muted())
	var head_pad := MarginContainer.new()
	head_pad.add_theme_constant_override("margin_left", 8)
	head_pad.add_child(head)
	box.add_child(head_pad)
	for opt in _part_options_for(el, part):
		box.add_child(_choice_button(str(opt["label"]), part, str(opt["id"]), el, menu_part))


func _lamp_voltage_id(el) -> String:
	return "dc24" if float(el.voltage) <= 30.0 else "ac220"


func _add_cylinder_params(box: VBoxContainer, el) -> void:
	# Параметры всего цилиндра (корпус / «Свойства»), не зоны части.
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	_add_bore_control(box, el)
	if str(el.rod_mode) != "rodless":
		_add_rod_control(box, el)
	_add_stroke_control(box, el)
	var load := SpinBox.new()
	_style_field(load)
	load.min_value = -2000
	load.max_value = 8000
	load.step = 5
	load.value = el.load_n
	load.custom_minimum_size = Vector2(220, 28)
	load.value_changed.connect(func(v):
		el.load_n = v
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Нагрузка, Н", load))
	if str(el.rod_mode) != "rodless":
		_add_option_param(box, el, "spring", "Пружина", str(el.spring_side), func(id: String):
			var before_action := str(el.action)
			el.spring_side = id
			var note_s: String = circuit.retune_geometry(el)
			if str(el.action) != before_action:
				circuit.reconfigure_action(el)
			if note_s != "":
				circuit.notify(note_s)
		, true)
	_add_option_param(box, el, "body", "Корпус", str(el.body_style), func(id: String):
		el.body_style = id
		el.body_style_user = true
	)
	_add_option_param(box, el, "mount", "Крепление", str(el.mount), func(id: String): el.mount = id)
	if str(el.rod_mode) != "rodless":
		_add_option_param(box, el, "brake", "Тормоз / стопор", str(el.brake), func(id: String): el.brake = id)
		_add_option_param(box, el, "guide", "Направляющая", str(el.guide), func(id: String): el.guide = id)
	else:
		_add_option_param(box, el, "bump_end", "Упоры каретки", str(el.bump_end), func(id: String): el.bump_end = id)
	var leak := HSlider.new()
	_style_slider(leak)
	leak.min_value = 0.0
	leak.max_value = 1.0
	leak.step = 0.01
	leak.value = float(el.seal_leak)
	leak.custom_minimum_size = Vector2(220, 28)
	leak.value_changed.connect(func(v):
		el.seal_leak = v
		_refresh_calc_labels(box, el, "")
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Утечка уплотнений", leak))


func _add_option_param(box: VBoxContainer, el, part: String, caption: String, current: String, apply: Callable, rebuild_ui: bool = false) -> void:
	var opts: Array = ValveCat.part_options(part) if el.kind == "valve" else Catalog.part_options(part)
	# Две опции yes/no или muffler/fitting — чекбокс, не выпадающий список.
	if opts.size() == 2:
		var a := str(opts[0].get("id", ""))
		var b := str(opts[1].get("id", ""))
		if (a == "yes" and b == "no") or (a == "no" and b == "yes"):
			var yes_id := a if a == "yes" else b
			_add_check_param(box, el, caption, current == yes_id, func(on: bool):
				apply.call(yes_id if on else ("no" if yes_id == "yes" else "yes"))
			, rebuild_ui)
			return
		if (a == "muffler" and b == "fitting") or (a == "fitting" and b == "muffler"):
			_add_check_param(box, el, caption if caption != "" else "Глушитель", current == "muffler", func(on: bool):
				apply.call("muffler" if on else "fitting")
			, rebuild_ui)
			return
	var opt_box := OptionButton.new()
	_style_field(opt_box)
	opt_box.custom_minimum_size = Vector2(220, 28)
	var sel := 0
	var i := 0
	for opt in opts:
		opt_box.add_item(str(opt["label"]))
		opt_box.set_item_metadata(i, str(opt["id"]))
		if str(opt["id"]) == current:
			sel = i
		i += 1
	opt_box.selected = sel
	opt_box.item_selected.connect(func(idx: int):
		apply.call(str(opt_box.get_item_metadata(idx)))
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		if rebuild_ui:
			call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled(caption, opt_box))


func _add_check_param(box: VBoxContainer, el, caption: String, checked: bool, apply: Callable, rebuild_ui: bool = false) -> void:
	# Кнопка с фиксацией — без «серой клетки» CheckBox и без пропадания текста на hover.
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = checked
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(220, 30)
	_style_toggle_btn(btn)
	_refresh_toggle_caption(btn, caption, checked)
	btn.toggled.connect(func(on: bool):
		_refresh_toggle_caption(btn, caption, on)
		_style_toggle_btn(btn)
		apply.call(on)
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		if rebuild_ui:
			call_deferred("_open_parts_refresh", el)
	)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 2)
	pad.add_theme_constant_override("margin_bottom", 2)
	pad.add_child(btn)
	box.add_child(pad)


func _refresh_toggle_caption(btn: Button, caption: String, on: bool) -> void:
	btn.text = caption
	# Выбрано — стилем кнопки, без галочки в тексте.
	_style_toggle_btn(btn)


func _style_toggle_btn(btn: Button) -> void:
	var on := btn.button_pressed
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiTheme.field_active() if on else Color(1, 1, 1, 1)
	normal.border_color = UiTheme.field_border() if on else UiTheme.paper_border()
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.shadow_size = 0
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UiTheme.field_active().darkened(0.04) if on else UiTheme.paper().darkened(0.02)
	hover.border_color = UiTheme.field_border()
	for key in ["normal", "pressed", "hover", "focus", "disabled"]:
		btn.add_theme_stylebox_override(key, hover if key == "hover" else normal)
	var fg := UiTheme.paper_text()
	for key2 in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(key2, fg)
	btn.add_theme_font_size_override("font_size", 13)


func _style_scroll(scroll: ScrollContainer) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Тема оболочки красит ScrollContainer в серый window_bg — сбрасываем.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0)
	panel.set_content_margin_all(0)
	scroll.add_theme_stylebox_override("panel", panel)
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.paper().darkened(0.04)
	track.set_corner_radius_all(3)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiTheme.paper_border()
	grab.set_corner_radius_all(3)
	var grab_h := grab.duplicate() as StyleBoxFlat
	grab_h.bg_color = UiTheme.field_border()
	var sb := scroll.get_v_scroll_bar()
	if sb == null:
		return
	# Узкий бар; место под него даёт layout ScrollContainer, не оверлей.
	sb.custom_minimum_size.x = 12
	sb.add_theme_stylebox_override("scroll", track)
	sb.add_theme_stylebox_override("scroll_focus", track)
	sb.add_theme_stylebox_override("grabber", grab)
	sb.add_theme_stylebox_override("grabber_highlight", grab_h)
	sb.add_theme_stylebox_override("grabber_pressed", grab_h)


func _add_bore_control(box: VBoxContainer, el) -> void:
	var bore_box := OptionButton.new()
	_style_field(bore_box)
	bore_box.custom_minimum_size = Vector2(220, 28)
	var bore_index := 0
	var bore_i := 0
	for bore in Catalog.bores():
		bore_box.add_item("∅ %.0f мм" % float(bore))
		bore_box.set_item_metadata(bore_i, float(bore))
		if absf(float(bore) - float(el.bore_mm)) < 0.1:
			bore_index = bore_i
		bore_i += 1
	bore_box.selected = bore_index
	bore_box.item_selected.connect(func(idx: int):
		el.bore_mm = float(bore_box.get_item_metadata(idx))
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		# Нельзя free'ить OptionButton во время его же сигнала.
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Диаметр поршня", bore_box))


func _add_cylinder_fitting_control(box: VBoxContainer, el) -> void:
	if str(el.kind) != "cylinder":
		return
	TubeFit.conform_cylinder_fitting(el)
	var fit_box := OptionButton.new()
	_style_field(fit_box)
	fit_box.custom_minimum_size = Vector2(220, 28)
	var sel: int = 0
	var i: int = 0
	var cur: String = str(el.fitting_id)
	for item in TubeFit.fittings_for_bore(float(el.bore_mm)):
		fit_box.add_item(str(item.get("label", item.get("id", ""))))
		fit_box.set_item_metadata(i, str(item.get("id", "")))
		if str(item.get("id", "")) == cur:
			sel = i
		i += 1
	fit_box.selected = sel
	fit_box.item_selected.connect(func(idx: int):
		var fid: String = str(fit_box.get_item_metadata(idx))
		var note: String = TubeFit.apply_fitting(el, fid)
		circuit._sync_wires_od_from_cylinder(el)
		if note != "":
			circuit.notify(note)
		else:
			circuit.notify("Фитинг: %s" % str(el.fitting_id))
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Фитинг (цанга)", fit_box))


func _add_rod_control(box: VBoxContainer, el) -> void:
	var row: Dictionary = Catalog.bore_row(float(el.bore_mm))
	var rod_box := OptionButton.new()
	_style_field(rod_box)
	rod_box.custom_minimum_size = Vector2(220, 28)
	var rod_index := 0
	var rod_i := 0
	for rod in row["rods"]:
		rod_box.add_item(Catalog.rod_label(float(el.bore_mm), float(rod)))
		rod_box.set_item_metadata(rod_i, float(rod))
		if absf(float(rod) - float(el.rod_mm)) < 0.1:
			rod_index = rod_i
		rod_i += 1
	rod_box.selected = rod_index
	rod_box.item_selected.connect(func(idx: int):
		el.rod_mm = float(rod_box.get_item_metadata(idx))
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Диаметр штока", rod_box))


func _add_stroke_control(box: VBoxContainer, el) -> void:
	var row: Dictionary = Catalog.bore_row(float(el.bore_mm))
	var stroke := SpinBox.new()
	_style_field(stroke)
	stroke.min_value = 5
	stroke.max_value = float(row["smax"])
	stroke.step = 1
	stroke.value = el.stroke_mm
	stroke.custom_minimum_size = Vector2(220, 28)
	stroke.value_changed.connect(func(v):
		el.stroke_mm = v
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Ход, мм", stroke))


func _add_calc_block(box: VBoxContainer, el, part: String) -> void:
	var lines: PackedStringArray = ValveCat.calc_lines(el, part) if el.kind == "valve" else Catalog.calc_lines(el, part)
	if lines.is_empty():
		return
	box.add_child(_menu_rule())
	var wrap := VBoxContainer.new()
	wrap.name = "CalcBlock"
	wrap.set_meta("part", part)
	wrap.add_theme_constant_override("separation", 1)
	box.add_child(wrap)
	_fill_calc_wrap(wrap, lines)


func _refresh_calc_labels(box: VBoxContainer, el, part: String) -> void:
	var wrap := box.get_node_or_null("CalcBlock") as VBoxContainer
	if wrap == null:
		return
	var use_part := part
	if wrap.has_meta("part"):
		use_part = str(wrap.get_meta("part"))
	var lines: PackedStringArray = ValveCat.calc_lines(el, use_part) if el.kind == "valve" else Catalog.calc_lines(el, use_part)
	_fill_calc_wrap(wrap, lines)


func _fill_calc_wrap(wrap: VBoxContainer, lines: PackedStringArray) -> void:
	while wrap.get_child_count() > 0:
		var old := wrap.get_child(0)
		wrap.remove_child(old)
		old.queue_free()
	var head := Label.new()
	head.text = "Расчёт"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", UiTheme.paper_text())
	wrap.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(grid)
	for line in lines:
		var pair := _split_calc_line(str(line))
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_color_override("font_color", UiTheme.paper_muted())
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		key.custom_minimum_size = Vector2(120, 0)
		var val := Label.new()
		val.text = pair[1]
		val.add_theme_font_size_override("font_size", 13)
		val.add_theme_color_override("font_color", UiTheme.paper_text())
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.custom_minimum_size = Vector2(160, 0)
		grid.add_child(key)
		grid.add_child(val)


func _split_calc_line(line: String) -> PackedStringArray:
	for sep in [": ", " · ", " — ", ":"]:
		var idx := line.find(sep)
		if idx > 0:
			return PackedStringArray([line.substr(0, idx).strip_edges(), line.substr(idx + sep.length()).strip_edges()])
	return PackedStringArray(["", line])


func _style_field(control: Control) -> void:
	# Поля на схеме/в свойствах — всегда светлая бумага (не тема оболочки).
	var fg := UiTheme.paper_text()
	var muted := UiTheme.paper_muted()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 1)
	normal.border_color = UiTheme.paper_border()
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UiTheme.paper().darkened(0.02)
	hover.border_color = UiTheme.field_border().lightened(0.15)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = UiTheme.field_border()
	focus.set_border_width_all(2)
	if control is OptionButton:
		var ob := control as OptionButton
		ob.add_theme_stylebox_override("normal", normal)
		ob.add_theme_stylebox_override("hover", hover)
		ob.add_theme_stylebox_override("pressed", hover)
		ob.add_theme_stylebox_override("focus", focus)
		ob.add_theme_stylebox_override("disabled", normal)
		# Все состояния шрифта — иначе при открытии popup остаётся белый из тёмной темы окна.
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_outline_color"]:
			ob.add_theme_color_override(key, fg)
		ob.add_theme_color_override("font_disabled_color", muted)
		ob.add_theme_constant_override("outline_size", 0)
		var popup := ob.get_popup()
		var pop_bg := StyleBoxFlat.new()
		pop_bg.bg_color = Color(1, 1, 1, 1)
		pop_bg.border_color = UiTheme.paper_border()
		pop_bg.set_border_width_all(1)
		pop_bg.set_corner_radius_all(3)
		pop_bg.content_margin_left = 6
		pop_bg.content_margin_right = 6
		pop_bg.content_margin_top = 4
		pop_bg.content_margin_bottom = 4
		popup.add_theme_stylebox_override("panel", pop_bg)
		for key2 in ["font_color", "font_hover_color", "font_pressed_color", "font_separator_color"]:
			popup.add_theme_color_override(key2, fg)
		popup.add_theme_color_override("font_accelerator_color", muted)
		popup.add_theme_color_override("font_disabled_color", muted)
		var item_hover := StyleBoxFlat.new()
		item_hover.bg_color = UiTheme.field_active()
		item_hover.set_corner_radius_all(2)
		popup.add_theme_stylebox_override("hover", item_hover)
		popup.add_theme_stylebox_override("selected", item_hover)
		popup.max_size = Vector2(320, 280)
		# После показа popup снова закрепить цвет кнопки (Godot иногда сбрасывает focus-цвет).
		popup.about_to_popup.connect(func():
			ob.add_theme_color_override("font_color", fg)
			ob.add_theme_color_override("font_focus_color", fg)
		)
		popup.popup_hide.connect(func():
			ob.add_theme_color_override("font_color", fg)
			ob.add_theme_color_override("font_focus_color", fg)
		)
	elif control is Button:
		var btn := control as Button
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_stylebox_override("focus", focus)
		btn.add_theme_color_override("font_color", fg)
		btn.add_theme_color_override("font_hover_color", fg)
		btn.add_theme_color_override("font_pressed_color", fg)
	elif control is SpinBox:
		var sb := control as SpinBox
		var le := sb.get_line_edit()
		if le:
			le.add_theme_stylebox_override("normal", normal)
			le.add_theme_stylebox_override("focus", focus)
			le.add_theme_color_override("font_color", fg)
			le.add_theme_color_override("font_uneditable_color", fg)
	elif control is LineEdit:
		var le2 := control as LineEdit
		le2.add_theme_stylebox_override("normal", normal)
		le2.add_theme_stylebox_override("focus", focus)
		le2.add_theme_color_override("font_color", fg)
		le2.add_theme_color_override("caret_color", fg)
		le2.add_theme_color_override("font_placeholder_color", muted)


func _style_slider(slider: HSlider) -> void:
	# Явные стили; меню не пересобирается на value_changed — drag плавный.
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.paper_border().lightened(0.25)
	track.set_corner_radius_all(3)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.field_border()
	fill.set_corner_radius_all(3)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.custom_minimum_size = Vector2(220, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_accessory_params(box: VBoxContainer, el) -> void:
	var AccLib = preload("res://scripts/domain/accessory_library.gd")
	var cls_lab := Label.new()
	cls_lab.text = AccLib.title_of(el)
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	var cls := str(el.accessory_class)
	if cls in ["throttle", "throttle_check", "throttle_check_fixed", "throttle_fixed"]:
		var thr_cat := OptionButton.new()
		_style_field(thr_cat)
		thr_cat.custom_minimum_size = Vector2(220, 28)
		var thr_rows: Array = AccLib.throttle_catalog()
		var thr_sel: int = 1
		var thr_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 6.0
		for i in thr_rows.size():
			var trow: Dictionary = thr_rows[i] as Dictionary
			thr_cat.add_item(str(trow.get("label", "")), i)
			if absf(float(trow.get("tube_od_mm", 0.0)) - thr_od) < 0.15:
				thr_sel = i
		thr_cat.select(thr_sel)
		thr_cat.item_selected.connect(func(idx: int):
			AccLib.apply_throttle_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (трубка)", thr_cat))
	if cls in ["throttle", "throttle_check"]:
		var open_sb := SpinBox.new()
		_style_field(open_sb)
		open_sb.min_value = 0
		open_sb.max_value = 100
		open_sb.step = 1
		open_sb.value = clampf(float(el.opening), 0.0, 1.0) * 100.0
		open_sb.custom_minimum_size = Vector2(220, 28)
		open_sb.value_changed.connect(func(v):
			el.opening = clampf(float(v) / 100.0, 0.0, 1.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Открытие, %", open_sb))
	if cls in ["throttle_check", "throttle_check_fixed"]:
		var crack_sb := SpinBox.new()
		_style_field(crack_sb)
		crack_sb.min_value = 0.05
		crack_sb.max_value = 2.0
		crack_sb.step = 0.05
		crack_sb.value = clampf(float(el.crack_pressure_bar), 0.05, 2.0)
		crack_sb.custom_minimum_size = Vector2(220, 28)
		crack_sb.value_changed.connect(func(v):
			el.crack_pressure_bar = clampf(float(v), 0.05, 2.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Давление открытия КО, бар", crack_sb))
	if cls in ["throttle_fixed", "throttle_check_fixed"]:
		var hint := Label.new()
		hint.text = "Фиксированное сечение (винта нет)"
		hint.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint)
	if cls == "reservoir":
		var res_cat := OptionButton.new()
		_style_field(res_cat)
		res_cat.custom_minimum_size = Vector2(220, 28)
		res_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var res_rows: Array = AccLib.reservoir_catalog()
		var res_sel: int = 3 # 2 л
		var res_vol: float = float(el.volume_l)
		for i in res_rows.size():
			var rrow: Dictionary = res_rows[i] as Dictionary
			res_cat.add_item(str(rrow.get("label", "")), i)
			if absf(float(rrow.get("volume_l", 0.0)) - res_vol) < 0.05:
				res_sel = i
		res_cat.select(res_sel)
		var vol := SpinBox.new()
		_style_field(vol)
		vol.min_value = 0.1
		vol.max_value = 200
		vol.step = 0.1
		vol.value = float(el.volume_l)
		vol.custom_minimum_size = Vector2(220, 28)
		vol.value_changed.connect(func(v):
			el.volume_l = maxf(float(v), 0.05)
			_scheme_changed()
		)
		res_cat.item_selected.connect(func(idx: int):
			var keep_n: int = clampi(int(el.reservoir_ports), 1, 5)
			AccLib.apply_reservoir_catalog(el, idx)
			el.reservoir_ports = keep_n
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			# Без полного refresh — только синхронизировать спиннер объёма.
			vol.set_value_no_signal(float(el.volume_l))
			_scheme_changed()
			call_deferred("_clamp_float_panel_size")
		)
		box.add_child(_menu_labeled("Типоразмер", res_cat))
		box.add_child(_menu_labeled("Объём, л", vol))
		var ports_sb := SpinBox.new()
		_style_field(ports_sb)
		ports_sb.min_value = 1
		ports_sb.max_value = 5
		ports_sb.step = 1
		ports_sb.rounded = true
		ports_sb.value = float(clampi(int(el.reservoir_ports), 1, 5))
		ports_sb.custom_minimum_size = Vector2(220, 28)
		ports_sb.value_changed.connect(func(v):
			el.reservoir_ports = clampi(int(round(v)), 1, 5)
			if circuit != null:
				circuit._ensure_accessory_ports(el)
				# Порты сдвинулись — сбросить joints и кэш 2D-трасс, иначе линии «висят».
				var eid: int = int(el.id)
				for wire in circuit.wires:
					if wire == null:
						continue
					if int(wire.a_id) == eid or int(wire.b_id) == eid:
						wire.joints.clear()
						circuit.retune_wire(wire)
			WireRouter2D.invalidate()
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Отводов сверху", ports_sb))
		var res_hint := Label.new()
		res_hint.text = "Свободный отвод → атмосфера (сечение ≈ штуцер). Параллельные ветки тоже работают."
		res_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		res_hint.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(res_hint)
	if cls == "regulator":
		var reg_cat := OptionButton.new()
		_style_field(reg_cat)
		reg_cat.custom_minimum_size = Vector2(220, 28)
		var reg_rows: Array = AccLib.regulator_catalog()
		var reg_sel: int = 1
		var reg_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 8.0
		for i in reg_rows.size():
			var rrow: Dictionary = reg_rows[i] as Dictionary
			reg_cat.add_item(str(rrow.get("label", "")), i)
			if absf(float(rrow.get("tube_od_mm", 0.0)) - reg_od) < 0.15:
				reg_sel = i
		reg_cat.select(reg_sel)
		var set_p := SpinBox.new()
		_style_field(set_p)
		set_p.min_value = 0.0
		set_p.max_value = 10.0
		set_p.step = 0.1
		set_p.value = float(el.set_pressure_bar)
		set_p.custom_minimum_size = Vector2(220, 28)
		set_p.value_changed.connect(func(v):
			el.set_pressure_bar = clampf(float(v), 0.0, 10.0)
			_scheme_changed()
		)
		reg_cat.item_selected.connect(func(idx: int):
			AccLib.apply_regulator_catalog(el, idx)
			var row_m: Dictionary = AccLib.regulator_catalog()[idx] as Dictionary
			set_p.max_value = clampf(float(row_m.get("set_max", 10.0)), 1.0, 16.0)
			set_p.set_value_no_signal(float(el.set_pressure_bar))
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер", reg_cat))
		box.add_child(_menu_labeled("Уставка, бар", set_p))
		var reg_hint := Label.new()
		reg_hint.text = "3D: клик по колпачку — lock/unlock; в разблокировке — крутить уставку."
		reg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reg_hint.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(reg_hint)
	if cls == "frl":
		var set_p_frl := SpinBox.new()
		_style_field(set_p_frl)
		set_p_frl.min_value = 0
		set_p_frl.max_value = 16
		set_p_frl.step = 0.1
		set_p_frl.value = float(el.set_pressure_bar)
		set_p_frl.custom_minimum_size = Vector2(220, 28)
		set_p_frl.value_changed.connect(func(v):
			el.set_pressure_bar = clampf(float(v), 0.0, 16.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Уставка, бар", set_p_frl))
	if cls == "shutoff":
		var z_opt := OptionButton.new()
		_style_field(z_opt)
		z_opt.custom_minimum_size = Vector2(220, 28)
		var z_rows: Array = AccLib.shutoff_catalog()
		var z_sel: int = 1
		var z_flow: float = float(el.flow_nl_min)
		for i in z_rows.size():
			var zrow: Dictionary = z_rows[i] as Dictionary
			z_opt.add_item(str(zrow.get("label", "")), i)
			if is_equal_approx(float(zrow.get("flow", 0.0)), z_flow):
				z_sel = i
		z_opt.select(z_sel)
		z_opt.item_selected.connect(func(idx: int):
			AccLib.apply_shutoff_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (Festo QH)", z_opt))
		_add_check_param(box, el, "Открыт", int(el.valve_pos) >= 1, func(on: bool):
			AccLib.set_shutoff_open(el, on)
			_scheme_changed()
		)
		var hint_z := Label.new()
		hint_z.text = "2/2 NC: слева на УГО — закрыть, справа — открыть; в 3D — рукоятка"
		hint_z.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_z.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_z)
	if cls == "shuttle":
		var sh_opt := OptionButton.new()
		_style_field(sh_opt)
		sh_opt.custom_minimum_size = Vector2(220, 28)
		var sh_rows: Array = AccLib.shuttle_catalog()
		var sh_sel: int = 1
		var sh_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 8.0
		for i in sh_rows.size():
			var srow: Dictionary = sh_rows[i] as Dictionary
			sh_opt.add_item(str(srow.get("label", "")), i)
			if absf(float(srow.get("tube_od_mm", 0.0)) - sh_od) < 0.15:
				sh_sel = i
		sh_opt.select(sh_sel)
		sh_opt.item_selected.connect(func(idx: int):
			AccLib.apply_shuttle_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (Festo OS)", sh_opt))
		var hint_sh := Label.new()
		hint_sh.text = "Входы 1/2 → выход 3 (большее P)"
		hint_sh.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_sh)
	if cls == "and_valve":
		var an_opt := OptionButton.new()
		_style_field(an_opt)
		an_opt.custom_minimum_size = Vector2(220, 28)
		var an_rows: Array = AccLib.and_catalog()
		var an_sel: int = 1
		var an_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 8.0
		for i in an_rows.size():
			var arow: Dictionary = an_rows[i] as Dictionary
			an_opt.add_item(str(arow.get("label", "")), i)
			if absf(float(arow.get("tube_od_mm", 0.0)) - an_od) < 0.15:
				an_sel = i
		an_opt.select(an_sel)
		an_opt.item_selected.connect(func(idx: int):
			AccLib.apply_and_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (AND)", an_opt))
		var hint_an := Label.new()
		hint_an.text = "Выход 3 только при давлении на 1 и 2"
		hint_an.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_an)
	if cls == "quick_exhaust":
		var qe_opt := OptionButton.new()
		_style_field(qe_opt)
		qe_opt.custom_minimum_size = Vector2(220, 28)
		var qe_rows: Array = AccLib.quick_exhaust_catalog()
		var qe_sel: int = 1
		var qe_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 8.0
		for i in qe_rows.size():
			var qrow: Dictionary = qe_rows[i] as Dictionary
			qe_opt.add_item(str(qrow.get("label", "")), i)
			if absf(float(qrow.get("tube_od_mm", 0.0)) - qe_od) < 0.15:
				qe_sel = i
		qe_opt.select(qe_sel)
		qe_opt.item_selected.connect(func(idx: int):
			AccLib.apply_quick_exhaust_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (Festo SE)", qe_opt))
		_add_check_param(box, el, "Глушитель на выхлопе 3", str(el.port_3) == "muffler", func(on: bool):
			el.port_3 = "muffler" if on else "fitting"
			if on and circuit != null:
				# Как у ПР: глушитель не точка проводки — снять трубку с порта 3.
				var eid: int = int(el.id)
				var drop: Array = []
				for w in circuit.wires:
					if w == null:
						continue
					if (int(w.a_id) == eid and str(w.a_port) == "3") or (int(w.b_id) == eid and str(w.b_port) == "3"):
						drop.append(w)
				for w2 in drop:
					circuit.wires.erase(w2)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		var hint_qe := Label.new()
		hint_qe.text = "1=вход → 2=ПЦ; при снятии питания 2→3 (быстрый выхлоп)"
		hint_qe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_qe.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_qe)
	if cls == "relief":
		var rl_opt := OptionButton.new()
		_style_field(rl_opt)
		rl_opt.custom_minimum_size = Vector2(220, 28)
		var rl_rows: Array = AccLib.relief_catalog()
		var rl_sel: int = 1
		var rl_od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 8.0
		for i in rl_rows.size():
			var rrow: Dictionary = rl_rows[i] as Dictionary
			rl_opt.add_item(str(rrow.get("label", "")), i)
			if absf(float(rrow.get("tube_od_mm", 0.0)) - rl_od) < 0.15:
				rl_sel = i
		rl_opt.select(rl_sel)
		rl_opt.item_selected.connect(func(idx: int):
			AccLib.apply_relief_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (VMR)", rl_opt))
		var set_sb := SpinBox.new()
		_style_field(set_sb)
		set_sb.min_value = 0.5
		set_sb.max_value = 10.0
		set_sb.step = 0.1
		set_sb.value = clampf(float(el.set_pressure_bar), 0.5, 10.0)
		set_sb.custom_minimum_size = Vector2(220, 28)
		set_sb.value_changed.connect(func(v):
			el.set_pressure_bar = clampf(float(v), 0.5, 10.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Уставка, бар", set_sb))
		var out_opt := OptionButton.new()
		_style_field(out_opt)
		out_opt.custom_minimum_size = Vector2(220, 28)
		out_opt.add_item("Глушитель", 0)
		out_opt.add_item("Штуцер", 1)
		out_opt.select(0 if str(el.port_3) == "muffler" else 1)
		out_opt.item_selected.connect(func(idx: int):
			el.port_3 = "muffler" if idx == 0 else "fitting"
			if idx == 0 and circuit != null:
				var eid2: int = int(el.id)
				var drop2: Array = []
				for w in circuit.wires:
					if w == null:
						continue
					if (int(w.a_id) == eid2 and str(w.a_port) == "2") or (int(w.b_id) == eid2 and str(w.b_port) == "2"):
						drop2.append(w)
				for w3 in drop2:
					circuit.wires.erase(w3)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Сброс 2 (как выхлоп ПР)", out_opt))
		var hint_rl := Label.new()
		hint_rl.text = "1=вход; сброс при P≥уставка. 3D: винт=уставка, рукоятка=ручной подъём"
		hint_rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_rl.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint_rl)
	if cls == "check":
		var cat_opt := OptionButton.new()
		_style_field(cat_opt)
		cat_opt.custom_minimum_size = Vector2(220, 28)
		var cat_rows: Array = AccLib.check_catalog()
		var sel: int = 1
		for i in cat_rows.size():
			var row: Dictionary = cat_rows[i] as Dictionary
			cat_opt.add_item(str(row.get("label", "")), i)
			if is_equal_approx(float(row.get("flow", 0.0)), float(el.flow_nl_min)) \
					and is_equal_approx(float(row.get("crack", 0.0)), float(el.crack_pressure_bar)):
				sel = i
		cat_opt.select(sel)
		cat_opt.item_selected.connect(func(idx: int):
			AccLib.apply_check_catalog(el, idx)
			if circuit != null and circuit.has_method("_sync_wires_od_from_port_el"):
				circuit._sync_wires_od_from_port_el(el)
			_scheme_changed()
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(_menu_labeled("Типоразмер (ISO 228)", cat_opt))
		var crack := SpinBox.new()
		_style_field(crack)
		crack.min_value = 0.01
		crack.max_value = 5.0
		crack.step = 0.01
		crack.value = float(el.crack_pressure_bar)
		crack.custom_minimum_size = Vector2(220, 28)
		crack.value_changed.connect(func(v):
			el.crack_pressure_bar = clampf(float(v), 0.01, 5.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Давление открытия, бар", crack))
		var qn := SpinBox.new()
		_style_field(qn)
		qn.min_value = 10
		qn.max_value = 20000
		qn.step = 10
		qn.value = float(el.flow_nl_min)
		qn.custom_minimum_size = Vector2(220, 28)
		qn.value_changed.connect(func(v):
			el.flow_nl_min = clampf(float(v), 10.0, 20000.0)
			el.valve_cv = clampf(float(el.flow_nl_min) / 600.0, 0.2, 4.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Расход Qn, Nl/мин (6→5 бар)", qn))
		var hint := Label.new()
		hint.text = "Qn — пропуск в открытом состоянии; давление открытия — пружина/седло"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(hint)
	elif cls != "reservoir":
		var cv := SpinBox.new()
		_style_field(cv)
		cv.min_value = 0.2
		cv.max_value = 4.0
		cv.step = 0.1
		cv.value = float(el.valve_cv)
		cv.custom_minimum_size = Vector2(220, 28)
		cv.value_changed.connect(func(v):
			el.valve_cv = clampf(float(v), 0.2, 4.0)
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Проход Cv (учебный)", cv))


func _add_source_params(box: VBoxContainer, el) -> void:
	var pressure := SpinBox.new()
	_style_field(pressure)
	pressure.min_value = 0
	pressure.max_value = 16
	pressure.step = 0.1
	pressure.value = el.pressure_bar
	pressure.custom_minimum_size = Vector2(220, 28)
	pressure.value_changed.connect(func(v):
		el.pressure_bar = v
		circuit.retune_source(el)
	)
	box.add_child(_menu_labeled("Давление, бар", pressure))
	var temp := SpinBox.new()
	_style_field(temp)
	temp.min_value = -20
	temp.max_value = 80
	temp.step = 1
	temp.value = el.temperature_c
	temp.custom_minimum_size = Vector2(220, 28)
	temp.value_changed.connect(func(v):
		el.temperature_c = v
		circuit.retune_source(el)
	)
	box.add_child(_menu_labeled("Температура, °C", temp))


func _add_electro_params(box: VBoxContainer, el) -> void:
	var tag := LineEdit.new()
	_style_field(tag)
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.custom_minimum_size = Vector2(220, 28)
	tag.text_changed.connect(func(v):
		el.tag = v.strip_edges()
		el.group_tag = el.tag
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Обозначение", tag))
	var cls_lab := Label.new()
	cls_lab.text = "Класс: %s · %s" % [str(el.electro_class), str(el.recipe_id)]
	cls_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(cls_lab)
	match str(el.electro_class):
		"lamp":
			_add_caption_field(box, el)
			var col := OptionButton.new()
			_style_field(col)
			col.custom_minimum_size = Vector2(220, 28)
			var colors := ["white", "red", "green", "yellow"]
			var titles := {"white": "Белая", "red": "Красная", "green": "Зелёная", "yellow": "Жёлтая"}
			for c in colors:
				col.add_item(str(titles.get(c, c)))
				if c == str(el.lamp_color):
					col.select(col.item_count - 1)
			col.item_selected.connect(func(i):
				_apply_part(el, "lamp_color", colors[i])
			)
			box.add_child(_menu_labeled("Цвет линзы", col))
			var volt := OptionButton.new()
			_style_field(volt)
			volt.custom_minimum_size = Vector2(220, 28)
			var volts := ["ac220", "dc24"]
			var volt_titles := {"ac220": "~ 220 В", "dc24": "= 24 В"}
			var cur_v := _lamp_voltage_id(el)
			for v in volts:
				volt.add_item(str(volt_titles.get(v, v)))
				if v == cur_v:
					volt.select(volt.item_count - 1)
			volt.item_selected.connect(func(i):
				_apply_part(el, "lamp_voltage", volts[i])
			)
			box.add_child(_menu_labeled("Напряжение", volt))
		"button", "e_stop":
			_add_button_operator_params(box, el)
		"switch":
			_add_caption_field(box, el)
			_add_switch_params(box, el)
		"timer_relay":
			_add_coil_electrical_params(box, el)
			_add_timer_relay_params(box, el)
		"mcb", "rcd", "rcbo":
			_add_breaker_params(box, el)
		"solenoid_coil":
			_add_coil_electrical_params(box, el)
			var side := OptionButton.new()
			_style_field(side)
			side.custom_minimum_size = Vector2(220, 28)
			side.add_item("Левая (L)", 0)
			side.add_item("Правая (R)", 1)
			side.select(1 if str(el.linked_valve_side) == "R" else 0)
			side.item_selected.connect(func(i):
				el.linked_valve_side = "R" if i == 1 else "L"
				circuit.renumber_tags()
				_scheme_changed()
			)
			box.add_child(_menu_labeled("Сторона ПР", side))
		"relay", "contactor", "thermal":
			_add_coil_electrical_params(box, el)
			_add_coil_contact_params(box, el)
		"busbar":
			_add_busbar_params(box, el)
		"terminal":
			_add_terminal_params(box, el)
		"supply":
			_add_supply_params(box, el)
		"psu":
			_add_psu_params(box, el)
		_:
			pass
	var mount_lab := Label.new()
	mount_lab.text = "Монтаж: %s" % str(el.electro_mount)
	mount_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(mount_lab)


func _add_breaker_params(box: VBoxContainer, el) -> void:
	var cls: String = str(el.electro_class)
	var is_mcb: bool = cls == "mcb"
	var is_rcd: bool = cls == "rcd"
	var is_rcbo: bool = cls == "rcbo"
	if is_mcb or is_rcbo:
		var curve_ob := OptionButton.new()
		_style_field(curve_ob)
		curve_ob.custom_minimum_size = Vector2(220, 28)
		var curves := ["B", "C", "D"]
		for c in curves:
			curve_ob.add_item(c)
			if c == str(el.curve).to_upper():
				curve_ob.select(curve_ob.item_count - 1)
		curve_ob.item_selected.connect(func(i):
			el.curve = curves[i]
			_scheme_changed()
			var chart = box.get_node_or_null("TccChart")
			if chart != null and chart.has_method("set_curve"):
				chart.set_curve(str(el.curve))
				chart.queue_redraw()
			_refresh_mcb_tcc_stats(box, el)
		)
		box.add_child(_menu_labeled("Класс", curve_ob))
	if is_mcb or is_rcd or is_rcbo:
		var rating_ob := OptionButton.new()
		_style_field(rating_ob)
		rating_ob.custom_minimum_size = Vector2(220, 28)
		el.rating_a = ElectroLib.mcb_snap_rating(float(el.rating_a))
		for a in ElectroLib.MCB_RATINGS_A:
			rating_ob.add_item("%.0f А" % float(a))
			if is_equal_approx(float(a), float(el.rating_a)):
				rating_ob.select(rating_ob.item_count - 1)
		rating_ob.item_selected.connect(func(i):
			el.rating_a = float(ElectroLib.MCB_RATINGS_A[i])
			_scheme_changed()
			var chart2 = box.get_node_or_null("TccChart")
			if chart2 != null and chart2.has_method("set_rating"):
				chart2.set_rating(float(el.rating_a))
				chart2.queue_redraw()
			_refresh_mcb_tcc_stats(box, el)
		)
		box.add_child(_menu_labeled("Номинал In", rating_ob))
	if is_mcb or is_rcbo:
		var icu_ob := OptionButton.new()
		_style_field(icu_ob)
		icu_ob.custom_minimum_size = Vector2(220, 28)
		el.u_max = ElectroLib.mcb_snap_icu(float(el.u_max))
		for ka in ElectroLib.MCB_ICU_KA:
			var ka_f: float = float(ka)
			var ka_lab: String = "%.0f кА" % ka_f if is_equal_approx(ka_f, floorf(ka_f)) else "%.1f кА" % ka_f
			icu_ob.add_item(ka_lab)
			if is_equal_approx(ka_f, float(el.u_max)):
				icu_ob.select(icu_ob.item_count - 1)
		icu_ob.item_selected.connect(func(i):
			el.u_max = float(ElectroLib.MCB_ICU_KA[i])
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Icu", icu_ob))
	if is_rcd or is_rcbo:
		var idelta_ob := OptionButton.new()
		_style_field(idelta_ob)
		idelta_ob.custom_minimum_size = Vector2(220, 28)
		el.i_delta_ma = ElectroLib.rcd_snap_idelta(float(el.i_delta_ma))
		for ma in ElectroLib.RCD_IDELTA_MA:
			idelta_ob.add_item("%.0f мА" % float(ma))
			if is_equal_approx(float(ma), float(el.i_delta_ma)):
				idelta_ob.select(idelta_ob.item_count - 1)
		idelta_ob.item_selected.connect(func(i):
			el.i_delta_ma = float(ElectroLib.RCD_IDELTA_MA[i])
			_scheme_changed()
		)
		box.add_child(_menu_labeled("IΔn", idelta_ob))
		var typ := OptionButton.new()
		_style_field(typ)
		typ.custom_minimum_size = Vector2(220, 28)
		var types := ["AC", "A", "B"]
		var cur_t: String = str(el.phase) if str(el.phase) in types else "AC"
		for t in types:
			typ.add_item("Тип %s" % t)
			if t == cur_t:
				typ.select(typ.item_count - 1)
		typ.item_selected.connect(func(i):
			el.phase = types[i]
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Тип УЗО", typ))
	if is_mcb or is_rcbo:
		var chart := TccChart.new()
		chart.name = "TccChart"
		chart.custom_minimum_size = Vector2(360, 220)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.set_curve(str(el.curve))
		chart.set_rating(float(el.rating_a))
		box.add_child(chart)
		var stats := Label.new()
		stats.name = "TccStats"
		stats.add_theme_color_override("font_color", UiTheme.paper_muted())
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(stats)
		_refresh_mcb_tcc_stats(box, el)


func _refresh_mcb_tcc_stats(box: VBoxContainer, el) -> void:
	var stats := box.get_node_or_null("TccStats") as Label
	if stats == null:
		return
	var inn: float = maxf(float(el.rating_a), 1.0)
	var curve: String = str(el.curve).to_upper()
	if curve not in ["B", "C", "D"]:
		curve = "C"
	# IEC 60898-1 табл. 6–7.
	var i_inf: float = 1.13 * inn
	var i_if: float = 1.45 * inn
	var i_th: float = 2.55 * inn
	var t_th: String = "1…60 с" if inn <= 32.0 else "1…120 с"
	var em_lo: float = 5.0
	var em_hi: float = 10.0
	match curve:
		"B":
			em_lo = 3.0
			em_hi = 5.0
		"D":
			em_lo = 10.0
			em_hi = 20.0
		_:
			em_lo = 5.0
			em_hi = 10.0
	stats.text = "\n".join(PackedStringArray([
		"Ток нерасцепления Inf (1.13·In) = %.1f А — тепловой не сработает за ≥1 ч" % i_inf,
		"Условный ток расцепления If (1.45·In) = %.1f А — тепловой сработает за <1 ч" % i_if,
		"Тепловой расцепитель при 2.55·In = %.1f А — время срабатывания %s" % [i_th, t_th],
		"ЭМ-расцепитель (класс %s): %.0f…%.0f·In = %.0f…%.0f А — мгновенно (~0,01 с)" % [
			curve, em_lo, em_hi, em_lo * inn, em_hi * inn
		],
	]))


class TccChart extends Control:
	## ВТХ по IEC 60898-1 табл. 6–7: Inf/If, 2.55·In, мгновенное B/C/D.
	var curve_class := "C"
	var rating_a := 16.0

	func set_curve(c: String) -> void:
		curve_class = c.to_upper()

	func set_rating(a: float) -> void:
		rating_a = maxf(a, 1.0)

	func _em_band() -> Vector2:
		match curve_class:
			"B":
				return Vector2(3.0, 5.0)
			"D":
				return Vector2(10.0, 20.0)
			_:
				return Vector2(5.0, 10.0)

	func _thermal_t(mult: float) -> float:
		# IEC 60898-1: при Inf=1.13·In не сработает за 1 ч; при If=1.45·In — сработает <1 ч;
		# при 2.55·In — от 1 с до 60 с (In≤32 А) или до 120 с (In>32 А).
		var m: float = maxf(mult, 1.01)
		if m <= 1.13:
			return 1.0e4
		if m <= 1.45:
			var t: float = (m - 1.13) / (1.45 - 1.13)
			return lerpf(7200.0, 900.0, clampf(t, 0.0, 1.0))
		if m <= 2.55:
			var t2: float = (m - 1.45) / (2.55 - 1.45)
			var t_hi: float = 60.0 if rating_a <= 32.0 else 120.0
			return lerpf(900.0, t_hi, clampf(t2, 0.0, 1.0))
		var t255: float = 60.0 if rating_a <= 32.0 else 120.0
		return clampf(t255 * pow(2.55 / m, 2.0), 0.02, t255)

	func _draw() -> void:
		var pad := Rect2(36, 12, size.x - 48, size.y - 36)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.96, 0.97, 0.98), true)
		draw_rect(pad, Color(1, 1, 1), true)
		draw_rect(pad, Color(0.7, 0.72, 0.76), false, 1.0)
		var font := get_theme_default_font()
		var band := _em_band()
		var x0 := 0.5
		var x1 := 50.0
		var y0 := 0.01
		var y1 := 10000.0
		var to_px := func(mult: float, t: float) -> Vector2:
			var lx := log(clampf(mult, x0, x1) / x0) / log(x1 / x0)
			var ly := log(clampf(t, y0, y1) / y0) / log(y1 / y0)
			return Vector2(pad.position.x + lx * pad.size.x, pad.position.y + (1.0 - ly) * pad.size.y)
		for mgrid in [1.0, 1.13, 1.45, 2.55, 5.0, 10.0, 20.0]:
			var p0: Vector2 = to_px.call(mgrid, y0)
			var p1: Vector2 = to_px.call(mgrid, y1)
			draw_line(p0, p1, Color(0.88, 0.9, 0.92), 1.0)
			if font and mgrid in [1.0, 2.55, 5.0, 10.0, 20.0]:
				var mlab: String = "%.2f" % float(mgrid)
				if is_equal_approx(mgrid, roundf(mgrid)):
					mlab = "%.0f" % float(mgrid)
				draw_string(font, Vector2(p0.x - 6, pad.position.y + pad.size.y + 14), mlab, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.38, 0.42))
		var pts := PackedVector2Array()
		var m := 1.13
		while m < band.x:
			pts.append(to_px.call(m, _thermal_t(m)))
			m *= 1.05
		pts.append(to_px.call(band.x, _thermal_t(band.x)))
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.15, 0.45, 0.75), 2.0, true)
		var a: Vector2 = to_px.call(band.x, y0)
		var b: Vector2 = to_px.call(band.y, y1)
		var zone := Rect2(Vector2(a.x, pad.position.y), Vector2(maxi(b.x - a.x, 2.0), pad.size.y))
		draw_rect(zone, Color(0.85, 0.25, 0.2, 0.18), true)
		draw_line(to_px.call(band.x, 0.01), to_px.call(band.y, 0.01), Color(0.75, 0.2, 0.15), 2.0)
		draw_line(to_px.call(band.x, 0.01), to_px.call(band.x, _thermal_t(band.x)), Color(0.75, 0.2, 0.15), 1.5)
		if font:
			draw_string(font, pad.position + Vector2(6, 14), "IEC 60898-1 · %s · In=%.0f A" % [curve_class, rating_a], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.2, 0.22, 0.26))
			draw_string(font, Vector2(4, pad.position.y + pad.size.y * 0.5), "t, с", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.38, 0.42))
			draw_string(font, Vector2(pad.position.x + pad.size.x * 0.35, size.y - 4), "I / In", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.38, 0.42))


func _electro_action_target(el):
	# Клик по контакту группы кнопки → primary (нажатие / ПКМ).
	if el == null or str(el.kind) != "electro":
		return el
	if str(el.member_role) == "contact" and int(el.group_id) >= 0:
		var primary = circuit.get_element(int(el.group_id))
		if primary != null and str(primary.electro_class) in ["button", "e_stop"]:
			return primary
	return el


## При пуске: скоба/корпус/порт кнопки → нажатие (до выбора обозначения).
func _try_press_electro_control(world: Vector2, event: InputEventMouseButton) -> bool:
	var part := _pick_part(world)
	if not part.is_empty() and str(part.get("part", "")) == "operator":
		var op_el = circuit.get_element(int(part["id"]))
		if _begin_electro_btn_press(op_el, event):
			return true
	var act_hit = _pick_body(world)
	if act_hit != null and _begin_electro_btn_press(act_hit, event):
		return true
	# Порт контакта кнопки (чуть вне корпуса) — тоже нажатие, не начало провода.
	var port_act := _pick_port(world)
	if not port_act.is_empty():
		var pel = circuit.get_element(int(port_act["id"]))
		if _begin_electro_btn_press(pel, event):
			return true
	return false


func _begin_electro_btn_press(el, event: InputEventMouseButton) -> bool:
	var btn_target = _electro_action_target(el)
	if btn_target == null or str(btn_target.kind) != "electro":
		return false
	var bcls: String = str(btn_target.electro_class)
	if bcls == "button" and not bool(btn_target.latching):
		circuit.select_only(int(btn_target.id), "schematic")
		btn_target.pressed = true
		_mode = "electro_btn"
		_grab_id = int(btn_target.id)
		_grab_port = ""
		_press = event.position
		_moved = false
		_part_kind = ""
		_request_live()
		accept_event()
		return true
	if bcls == "e_stop" or (bcls == "button" and bool(btn_target.latching)):
		circuit.select_only(int(btn_target.id), "schematic")
		btn_target.pressed = not bool(btn_target.pressed)
		_mode = ""
		_grab_id = -1
		_grab_port = ""
		_press = event.position
		_moved = false
		_request_live()
		accept_event()
		return true
	return false


func _click_electro_schematic(el, world: Vector2 = Vector2.ZERO) -> void:
	# Короткий клик на отпускании: фиксация / тумблеры / АВ.
	# Моментная кнопка обрабатывается на нажатии ЛКМ (hold), сюда не попадает.
	_press_electro_schematic(el, world)


func _press_electro_schematic(el, world: Vector2 = Vector2.ZERO) -> void:
	var target = _electro_action_target(el)
	if target == null or str(target.kind) != "electro":
		return
	match str(target.electro_class):
		"button", "e_stop":
			if bool(target.latching) or str(target.electro_class) == "e_stop":
				target.pressed = not bool(target.pressed)
			else:
				target.pressed = true
				_mode = "electro_btn"
				_grab_id = int(target.id)
		"switch":
			# Клик по колонке/подписи положения — сразу в нужное, не по кругу.
			var local: Vector2 = Geom.to_local(target, world)
			ElectroLib.set_switch_pos(target, ElectroSymbols.switch_pos_at_local(target, local))
		"mcb", "rcd", "rcbo":
			target.closed = not bool(target.closed)
		"thermal":
			target.pressed = not bool(target.pressed)
		_:
			pass
	_request_both()


func _add_caption_field(box: VBoxContainer, el) -> void:
	var cap := LineEdit.new()
	_style_field(cap)
	cap.text = str(el.caption)
	cap.placeholder_text = "Название на щитке"
	cap.custom_minimum_size = Vector2(220, 28)
	# Длинный текст не должен раздувать меню по ширине.
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.clip_contents = true
	cap.text_changed.connect(func(v):
		el.caption = v.strip_edges()
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Название", cap))


func _add_button_operator_params(box: VBoxContainer, el) -> void:
	if el == null or str(el.electro_class) not in ["button", "e_stop"]:
		return
	_add_caption_field(box, el)
	if str(el.electro_class) != "e_stop":
		var colors := ["white", "red", "green", "yellow", "black", "blue"]
		var titles := {
			"white": "Белая", "red": "Красная", "green": "Зелёная",
			"yellow": "Жёлтая", "black": "Чёрная", "blue": "Синяя",
		}
		var col := OptionButton.new()
		_style_field(col)
		col.custom_minimum_size = Vector2(220, 28)
		for c in colors:
			col.add_item(str(titles.get(c, c)))
			if c == str(el.btn_color):
				col.select(col.item_count - 1)
		col.item_selected.connect(func(i):
			el.btn_color = colors[i]
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Цвет клавиши", col))
	else:
		var lab := Label.new()
		lab.text = "Цвет клавиши: красный (аварийная кнопка)"
		lab.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(lab)
		el.btn_color = "red"
	_add_check_param(box, el, "С фиксацией", bool(el.latching) or str(el.electro_class) == "e_stop", func(on: bool):
		el.latching = on
		_scheme_changed()
	)
	box.add_child(_menu_rule())
	var kinds: Array = ElectroLib.button_contact_kinds(el)
	if kinds.is_empty():
		kinds = ["no"]
	var head := Label.new()
	head.text = "Контакты"
	head.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(head)
	for i in kinds.size():
		_add_button_contact_row(box, el, kinds, i)
	var add_btn := _plain_button("+ Добавить контакт", false)
	add_btn.pressed.connect(func():
		var k2: Array = ElectroLib.button_contact_kinds(el)
		if k2.is_empty():
			k2 = ["no"]
		k2.append("no")
		_apply_button_kinds(el, k2)
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(add_btn)


func _add_switch_params(box: VBoxContainer, el) -> void:
	if el == null or str(el.electro_class) != "switch":
		return
	ElectroLib.ensure_switch(el)
	var npos_box := SpinBox.new()
	_style_field(npos_box)
	npos_box.min_value = 2
	npos_box.max_value = 6
	npos_box.step = 1
	npos_box.value = int(el.switch_positions)
	npos_box.custom_minimum_size = Vector2(220, 28)
	npos_box.value_changed.connect(func(v):
		ElectroLib.resize_switch(el, int(v), ElectroLib.switch_row_count(el))
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Положений", npos_box))
	var nrow_box := SpinBox.new()
	_style_field(nrow_box)
	nrow_box.min_value = 1
	nrow_box.max_value = 8
	nrow_box.step = 1
	nrow_box.value = ElectroLib.switch_row_count(el)
	nrow_box.custom_minimum_size = Vector2(220, 28)
	nrow_box.value_changed.connect(func(v):
		ElectroLib.resize_switch(el, int(el.switch_positions), int(v))
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Цепей (рядов)", nrow_box))
	box.add_child(_menu_rule())
	var names_h := Label.new()
	names_h.text = "Названия положений"
	names_h.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(names_h)
	for pi in int(el.switch_positions):
		_add_switch_label_field(box, el, pi)
	box.add_child(_menu_rule())
	var hint := Label.new()
	hint.text = "Таблица замыканий (● = замкнут)"
	hint.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(hint)
	_add_switch_matrix(box, el)


func _add_switch_label_field(box: VBoxContainer, el, index: int) -> void:
	var edit := LineEdit.new()
	_style_field(edit)
	edit.text = ElectroLib.switch_label(el, index)
	edit.placeholder_text = "Положение %d" % index
	edit.custom_minimum_size = Vector2(220, 28)
	var idx: int = index
	edit.text_changed.connect(func(v):
		ElectroLib.ensure_switch(el)
		var labels: PackedStringArray = el.switch_labels
		while labels.size() <= idx:
			labels.append(str(labels.size()))
		var t: String = str(v).strip_edges()
		labels[idx] = t if t != "" else str(idx)
		el.switch_labels = labels
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Пол. %d" % index, edit))


func _add_switch_matrix(box: VBoxContainer, el) -> void:
	ElectroLib.ensure_switch(el)
	var npos: int = int(el.switch_positions)
	var rows: int = ElectroLib.switch_row_count(el)
	var grid := GridContainer.new()
	grid.columns = npos + 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var corner := Label.new()
	corner.text = ""
	grid.add_child(corner)
	for pi in npos:
		var h := Label.new()
		h.text = ElectroLib.switch_label(el, pi)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size = Vector2(36, 22)
		h.add_theme_color_override("font_color", UiTheme.paper_muted())
		grid.add_child(h)
	for ri in rows:
		var rl := Label.new()
		var i0: int = ri * 2
		var n1 := str(el.contact_defs[i0].get("name", "")) if i0 < el.contact_defs.size() else str(ri)
		var n2 := str(el.contact_defs[i0 + 1].get("name", "")) if i0 + 1 < el.contact_defs.size() else ""
		rl.text = "%s-%s" % [n1, n2]
		rl.add_theme_color_override("font_color", UiTheme.paper_text())
		rl.custom_minimum_size = Vector2(48, 28)
		grid.add_child(rl)
		for pi2 in npos:
			var on: bool = ElectroLib.switch_closed_at(el, ri, pi2)
			var cell := Button.new()
			cell.toggle_mode = true
			cell.button_pressed = on
			cell.text = "●" if on else "○"
			cell.focus_mode = Control.FOCUS_NONE
			cell.custom_minimum_size = Vector2(28, 28)
			_style_toggle_btn(cell)
			var row_i: int = ri
			var pos_i: int = pi2
			cell.toggled.connect(func(pressed_on: bool):
				ElectroLib.ensure_switch(el)
				if row_i < el.switch_map.size() and typeof(el.switch_map[row_i]) == TYPE_ARRAY:
					var row: Array = el.switch_map[row_i]
					while row.size() <= pos_i:
						row.append(false)
					row[pos_i] = pressed_on
					el.switch_map[row_i] = row
				cell.text = "●" if pressed_on else "○"
				_style_toggle_btn(cell)
				_scheme_changed()
			)
			grid.add_child(cell)
	box.add_child(grid)


func _add_button_contact_row(box: VBoxContainer, el, kinds: Array, index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := Label.new()
	lab.text = "%d." % (index + 1)
	lab.custom_minimum_size = Vector2(24, 28)
	lab.add_theme_color_override("font_color", UiTheme.paper_text())
	row.add_child(lab)
	var opt := OptionButton.new()
	_style_field(opt)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(140, 28)
	opt.fit_to_longest_item = false
	var ids := ["no", "nc", "co"]
	var labels := {"no": "НО", "nc": "НЗ", "co": "Перекидной"}
	var cur := str(kinds[index])
	for id in ids:
		opt.add_item(str(labels.get(id, id)))
		if id == cur:
			opt.select(opt.item_count - 1)
	opt.item_selected.connect(func(i):
		var k3: Array = ElectroLib.button_contact_kinds(el)
		if k3.is_empty():
			k3 = kinds.duplicate()
		while k3.size() <= index:
			k3.append("no")
		k3[index] = ids[i]
		_apply_button_kinds(el, k3)
		call_deferred("_open_parts_refresh", el)
	)
	row.add_child(opt)
	# Первый ключ — только вместе с кнопкой; × на строке 1 отключён.
	var del := _plain_button("×", index == 0 or kinds.size() <= 1)
	del.custom_minimum_size = Vector2(32, 28)
	del.pressed.connect(func():
		var k4: Array = ElectroLib.button_contact_kinds(el)
		if index == 0 or k4.size() <= 1:
			return
		k4.remove_at(index)
		_apply_button_kinds(el, k4)
		call_deferred("_open_parts_refresh", el)
	)
	row.add_child(del)
	box.add_child(row)


func _apply_button_kinds(el, kinds: Array) -> void:
	el.contact_defs = ElectroLib.make_button_contact_defs(kinds)
	el.group_template = "button"
	ElectroLib.rebuild_button_contacts(circuit, el)
	circuit.renumber_tags()
	_paths_dirty = true
	if circuit != null:
		circuit.touch_scene()
	_request_both("contacts_rebuild")
	queue_redraw()


func _apply_timer_setpoint(el) -> void:
	if el == null:
		return
	ElectroLib.timer_sync_delays(el)
	var gid: int = int(el.id)
	for other in circuit.elements:
		if int(other.group_id) != gid:
			continue
		other.delay_on = float(el.delay_on)
		other.delay_off = float(el.delay_off)
		other.timer_mode = str(el.timer_mode)
		other.timer_unit = int(el.timer_unit)
		other.timer_value = float(el.timer_value)
	_scheme_changed()


func _add_timer_relay_params(box: VBoxContainer, el) -> void:
	if el == null:
		return
	ElectroLib.normalize_timer_relay(el)
	el.hide_unused_contacts = false
	var mode_ob := OptionButton.new()
	_style_field(mode_ob)
	mode_ob.custom_minimum_size = Vector2(220, 28)
	var modes: Array = ["on", "off", "both"]
	var mode_titles := {"on": "Включения", "off": "Отключения", "both": "Вкл/Выкл"}
	var cur_mode: String = str(el.timer_mode)
	if cur_mode not in modes:
		cur_mode = "on"
	var mode_sel: int = 0
	for mi in modes.size():
		mode_ob.add_item(str(mode_titles.get(modes[mi], modes[mi])))
		if str(modes[mi]) == cur_mode:
			mode_sel = mi
	mode_ob.select(mode_sel)
	mode_ob.item_selected.connect(func(i):
		el.timer_mode = str(modes[i])
		_apply_timer_setpoint(el)
	)
	box.add_child(_menu_labeled("Тип задержки", mode_ob))
	var contact_lab := Label.new()
	contact_lab.text = "Контакт: один перекидной (NO / COM / NC)"
	contact_lab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(contact_lab)


func _add_coil_electrical_params(box: VBoxContainer, el) -> void:
	if el == null:
		return
	var cls := str(el.electro_class)
	if cls not in ["relay", "contactor", "thermal", "timer_relay", "solenoid_coil", "voltage_relay"]:
		return
	if cls != "thermal":
		var volt := OptionButton.new()
		_style_field(volt)
		volt.custom_minimum_size = Vector2(220, 28)
		# Типичные промышленные: 24 В=, 110 В~, 230 В~ (без 48 В).
		var volts := [24.0, 110.0, 230.0]
		var titles := {24.0: "= 24 В", 110.0: "~ 110 В", 230.0: "~ 230 В"}
		var cur_u: float = float(el.voltage)
		if absf(cur_u - 48.0) < 0.5:
			cur_u = 24.0
			el.voltage = 24.0
		var sel: int = 2
		for i in volts.size():
			volt.add_item(str(titles.get(volts[i], "%.0f В" % volts[i])))
			if absf(cur_u - float(volts[i])) < 0.5:
				sel = i
		volt.select(sel)
		volt.item_selected.connect(func(i):
			el.voltage = float(volts[i])
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Напряжение катушки", volt))
	if cls in ["relay", "contactor", "timer_relay"]:
		var imax := SpinBox.new()
		_style_field(imax)
		imax.min_value = 0.5
		imax.max_value = 100
		imax.step = 0.5
		imax.value = float(el.rating_a) if float(el.rating_a) > 0.0 else 10.0
		imax.custom_minimum_size = Vector2(220, 28)
		imax.value_changed.connect(func(v):
			el.rating_a = v
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Макс. ток контакта, А", imax))


func _add_coil_contact_params(box: VBoxContainer, el) -> void:
	if el == null or str(el.electro_class) not in ["relay", "contactor", "thermal"]:
		return
	if str(el.electro_class) == "contactor":
		var pwr := Label.new()
		pwr.text = "Силовые НО: %d" % int(ElectroLib.coil_power_contact_defs(el).size() / 2)
		pwr.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(pwr)
	if str(el.electro_class) == "thermal":
		var ir := SpinBox.new()
		_style_field(ir)
		ir.min_value = 0.1
		ir.max_value = 100
		ir.step = 0.1
		ir.value = float(el.rating_a) if float(el.rating_a) > 0.0 else 10.0
		ir.custom_minimum_size = Vector2(220, 28)
		ir.value_changed.connect(func(v):
			el.rating_a = v
			_scheme_changed()
		)
		box.add_child(_menu_labeled("Уставка, А", ir))
	box.add_child(_menu_rule())
	_add_check_param(box, el, "Скрыть неиспользуемые", bool(el.hide_unused_contacts), func(on: bool):
		el.hide_unused_contacts = on
		if str(el.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			ElectroLib.layout_coil_contacts(circuit, el)
		_scheme_changed()
	)
	var kinds: Array = ElectroLib.coil_aux_contact_kinds(el)
	var head := Label.new()
	head.text = "Вспомогательные контакты"
	head.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(head)
	for i in kinds.size():
		_add_coil_contact_row(box, el, kinds, i)
	var add_default: String = "co" if str(el.electro_class) == "relay" else "no"
	var add_btn := _plain_button("+ Добавить контакт", false)
	add_btn.pressed.connect(func():
		var k2: Array = ElectroLib.coil_aux_contact_kinds(el)
		k2.append(add_default)
		_apply_coil_kinds(el, k2)
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(add_btn)


func _add_coil_contact_row(box: VBoxContainer, el, kinds: Array, index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := Label.new()
	lab.text = "%d." % (index + 1)
	lab.custom_minimum_size = Vector2(24, 28)
	lab.add_theme_color_override("font_color", UiTheme.paper_text())
	row.add_child(lab)
	var opt := OptionButton.new()
	_style_field(opt)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(140, 28)
	opt.fit_to_longest_item = false
	var ids: Array = ["no", "nc", "co"] if str(el.electro_class) == "relay" else ["no", "nc"]
	var labels := {"no": "НО", "nc": "НЗ", "co": "Перекидной"}
	var cur := str(kinds[index])
	for id in ids:
		opt.add_item(str(labels.get(id, id)))
		if id == cur:
			opt.select(opt.item_count - 1)
	opt.item_selected.connect(func(i):
		var k3: Array = ElectroLib.coil_aux_contact_kinds(el)
		while k3.size() <= index:
			k3.append("no")
		k3[index] = ids[i]
		_apply_coil_kinds(el, k3)
		call_deferred("_open_parts_refresh", el)
	)
	row.add_child(opt)
	var del := _plain_button("×", kinds.size() <= 0)
	del.custom_minimum_size = Vector2(32, 28)
	del.pressed.connect(func():
		var k4: Array = ElectroLib.coil_aux_contact_kinds(el)
		if index >= 0 and index < k4.size():
			k4.remove_at(index)
		_apply_coil_kinds(el, k4)
		call_deferred("_open_parts_refresh", el)
	)
	row.add_child(del)
	box.add_child(row)


func _apply_coil_kinds(el, kinds: Array) -> void:
	if el != null and str(el.electro_class) == "timer_relay":
		ElectroLib.normalize_timer_relay(el)
		ElectroLib.rebuild_coil_contacts(circuit, el)
		circuit.renumber_tags()
		_paths_dirty = true
		if circuit != null:
			circuit.touch_scene()
		_request_both("contacts_rebuild")
		queue_redraw()
		return
	el.contact_defs = ElectroLib.make_coil_contact_defs(el, kinds)
	if str(el.group_template) == "":
		el.group_template = "coil"
	ElectroLib.rebuild_coil_contacts(circuit, el)
	circuit.renumber_tags()
	_paths_dirty = true
	if circuit != null:
		circuit.touch_scene()
	_request_both("contacts_rebuild")
	queue_redraw()


func _add_busbar_params(box: VBoxContainer, el) -> void:
	_add_caption_field(box, el)
	var heel := OptionButton.new()
	_style_field(heel)
	heel.custom_minimum_size = Vector2(220, 28)
	var heel_ids := ["N", "-", "+", "PE", "L1", "L2", "L3"]
	var heel_titles := {
		"N": "Голубой — нейтраль", "-": "Чёрный — минус", "+": "Красный — плюс",
		"PE": "Зелёный — PE", "L1": "Коричневый — L1", "L2": "Чёрный — L2", "L3": "Серый — L3",
	}
	var cur_h: String = str(el.phase) if str(el.phase) != "" else "N"
	for id in heel_ids:
		heel.add_item(str(heel_titles.get(id, id)))
		if id == cur_h:
			heel.select(heel.item_count - 1)
	heel.item_selected.connect(func(i):
		el.phase = heel_ids[i]
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Цвет базы", heel))
	var taps := SpinBox.new()
	_style_field(taps)
	taps.min_value = 2
	taps.max_value = 12
	taps.step = 1
	taps.value = maxi(el.electro_ports.size(), 2)
	taps.custom_minimum_size = Vector2(220, 28)
	taps.value_changed.connect(func(v):
		var n: int = int(v)
		var ports: Array = []
		for i in n:
			ports.append({"name": str(i + 1), "type": "line"})
		el.electro_ports = ports
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Отводов", taps))


func _add_supply_params(box: VBoxContainer, el) -> void:
	var ph := OptionButton.new()
	_style_field(ph)
	ph.custom_minimum_size = Vector2(220, 28)
	ph.add_item("1ф: L / N / PE", 0)
	ph.add_item("3ф: L1 / L2 / L3 / N", 1)
	ph.add_item("3ф: L1 / L2 / L3 / N / PE", 2)
	var cur: int = 0
	if int(el.poles) >= 3:
		cur = 2 if el.electro_ports.size() >= 5 else 1
	ph.select(cur)
	ph.item_selected.connect(func(i):
		if i == 0:
			el.poles = 1
			el.voltage = 230.0
			el.electro_ports = [
				{"name": "L", "type": "source"}, {"name": "N", "type": "source"},
				{"name": "PE", "type": "source"},
			]
			el.recipe_id = "supply_1ph"
		elif i == 1:
			el.poles = 3
			el.voltage = 400.0
			el.electro_ports = [
				{"name": "L1", "type": "source"}, {"name": "L2", "type": "source"},
				{"name": "L3", "type": "source"}, {"name": "N", "type": "source"},
			]
			el.recipe_id = "supply_3ph"
		else:
			el.poles = 3
			el.voltage = 400.0
			el.electro_ports = [
				{"name": "L1", "type": "source"}, {"name": "L2", "type": "source"},
				{"name": "L3", "type": "source"}, {"name": "N", "type": "source"},
				{"name": "PE", "type": "source"},
			]
			el.recipe_id = "supply_3ph_pe"
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Фазность", ph))
	var vlab := Label.new()
	vlab.text = "Uн: %.0f В" % float(el.voltage)
	vlab.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(vlab)


func _add_psu_params(box: VBoxContainer, el) -> void:
	_add_caption_field(box, el)
	var vout := SpinBox.new()
	_style_field(vout)
	vout.min_value = 5
	vout.max_value = 48
	vout.step = 1
	vout.value = float(el.voltage) if float(el.voltage) > 0.0 else 24.0
	vout.custom_minimum_size = Vector2(220, 28)
	vout.value_changed.connect(func(v):
		el.voltage = v
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Выход U, В", vout))
	var iout := SpinBox.new()
	_style_field(iout)
	iout.min_value = 0.5
	iout.max_value = 40
	iout.step = 0.5
	iout.value = float(el.rating_a) if float(el.rating_a) > 0.0 else 2.5
	iout.custom_minimum_size = Vector2(220, 28)
	iout.value_changed.connect(func(v):
		el.rating_a = v
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Выход Iн, А", iout))


## Скрыть неиспользуемые: плотный ряд tip с жилами + точечный reroute жил XT.
## Без touch_scene — его делает вызывающий (_add_check_param → _scheme_changed), иначе 2 undo.
func _apply_terminal_hide_unused(el, on: bool) -> void:
	if el == null or circuit == null:
		return
	var cur: bool = bool(el.hide_unused_contacts)
	if cur == on:
		return
	ElectroSymbols.scheme_circuit = circuit
	el.hide_unused_contacts = on
	var eid: int = int(el.id)
	var affected: Dictionary = {}
	for w in circuit.wires:
		if int(w.a_id) != eid and int(w.b_id) != eid:
			continue
		w.joints.clear()
		WireRouter2D.invalidate_wire(int(w.id))
		affected[int(w.id)] = true
	if not affected.is_empty():
		_paths_dirty = true
		_patch_cached_wire_paths(affected)
	_request_both("term_hide_unused")


## Смена шага XT: tip«1» и position элемента не трогаем; только точечный reroute жил XT.
func _apply_terminal_pitch(el, pitch_cells: int) -> void:
	if el == null or circuit == null:
		return
	var want: int = maxi(int(pitch_cells), 2)
	var cur_raw: Variant = el.get("terminal_pitch_cells")
	var cur: int = 2 if cur_raw == null else maxi(int(cur_raw), 2)
	if want == cur:
		return
	el.set("terminal_pitch_cells", want)
	var eid: int = int(el.id)
	var affected: Dictionary = {}
	for w in circuit.wires:
		if int(w.a_id) != eid and int(w.b_id) != eid:
			continue
		# Только жилы этого XT — без полного invalidate всей схемы (фриз).
		w.joints.clear()
		WireRouter2D.invalidate_wire(int(w.id))
		affected[int(w.id)] = true
	if not affected.is_empty():
		_paths_dirty = true
		_patch_cached_wire_paths(affected)
	circuit.touch_scene()
	_request_both("term_pitch")
	call_deferred("_open_parts_refresh", el)


func _add_terminal_params(box: VBoxContainer, el) -> void:
	if str(el.phase) != "":
		var pl := Label.new()
		pl.text = "Фаза/шина: %s" % str(el.phase)
		pl.add_theme_color_override("font_color", UiTheme.paper_muted())
		box.add_child(pl)
		_add_terminal_color_field(box, el, -1)
		return
	var rows := SpinBox.new()
	_style_field(rows)
	rows.min_value = 1
	rows.max_value = 12
	rows.step = 1
	rows.value = maxi(el.electro_ports.size(), 1)
	rows.custom_minimum_size = Vector2(220, 28)
	rows.value_changed.connect(func(v):
		# Игнор ложного value_changed при пересборке панели (иначе XT схлопывается до 1).
		var cur_rows: int = maxi(el.electro_ports.size(), 1)
		if int(v) == cur_rows:
			return
		ElectroLib.terminal_set_rows(el, int(v))
		_scheme_changed()
		call_deferred("_open_parts_refresh", el)
	)
	box.add_child(_menu_labeled("Рядов (полюсов)", rows))
	var pitch := SpinBox.new()
	_style_field(pitch)
	pitch.min_value = 2
	pitch.max_value = 8
	pitch.step = 1
	var pitch0: int = 2
	var pitch_raw: Variant = el.get("terminal_pitch_cells")
	if pitch_raw != null:
		pitch0 = maxi(int(pitch_raw), 2)
	pitch.value = pitch0
	pitch.custom_minimum_size = Vector2(220, 28)
	pitch.value_changed.connect(func(v):
		_apply_terminal_pitch(el, int(v))
	)
	box.add_child(_menu_labeled("Шаг tip↔tip (клетки, высота=2)", pitch))
	_add_check_param(box, el, "Скрыть неиспользуемые", bool(el.hide_unused_contacts), func(on: bool):
		# Только флаг+reroute; touch/refresh — один раз в _add_check_param (rebuild_ui).
		_apply_terminal_hide_unused(el, on)
	, true)
	_add_check_param(box, el, "Общая шина", bool(el.terminal_bus), func(on: bool):
		el.terminal_bus = on
		if on:
			# Один цвет на всю группу клемм.
			var seed_c: String = str(el.color_id)
			if seed_c == "" and el.electro_ports.size() > 0 and typeof(el.electro_ports[0]) == TYPE_DICTIONARY:
				seed_c = str(el.electro_ports[0].get("color_id", ""))
			el.color_id = seed_c
			for i in el.electro_ports.size():
				if typeof(el.electro_ports[i]) == TYPE_DICTIONARY:
					el.electro_ports[i]["color_id"] = seed_c
	, true)
	if bool(el.terminal_bus):
		_add_terminal_color_field(box, el, -1)
	var head := Label.new()
	head.text = "Подписи рядов (на схеме)"
	head.add_theme_color_override("font_color", UiTheme.paper_muted())
	box.add_child(head)
	var n_rows: int = maxi(el.electro_ports.size(), 1)
	for ri in n_rows:
		var row_i: int = ri
		var wrap := HBoxContainer.new()
		wrap.add_theme_constant_override("separation", 6)
		var num := Label.new()
		num.text = "%d/%d" % [row_i * 2 + 1, row_i * 2 + 2]
		num.custom_minimum_size = Vector2(40, 28)
		num.add_theme_color_override("font_color", UiTheme.paper_muted())
		wrap.add_child(num)
		var le := LineEdit.new()
		_style_field(le)
		le.placeholder_text = "+24В…"
		le.max_length = ElectroLib.TERM_ROW_LABEL_MAX
		le.text = ElectroLib.terminal_row_label(el, row_i)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.custom_minimum_size = Vector2(360, 28)
		le.text_changed.connect(func(v):
			while el.electro_ports.size() <= row_i:
				el.electro_ports.append({"label": "", "color_id": "", "type": "line"})
			if typeof(el.electro_ports[row_i]) != TYPE_DICTIONARY:
				el.electro_ports[row_i] = {"label": "", "color_id": "", "type": "line"}
			var clipped: String = str(v).strip_edges()
			if clipped.length() > ElectroLib.TERM_ROW_LABEL_MAX:
				clipped = clipped.substr(0, ElectroLib.TERM_ROW_LABEL_MAX)
				le.text = clipped
				le.caret_column = clipped.length()
			el.electro_ports[row_i]["label"] = clipped
			_scheme_changed()
		)
		wrap.add_child(le)
		box.add_child(wrap)
		if not bool(el.terminal_bus):
			_add_terminal_color_field(box, el, row_i)


func _add_terminal_color_field(box: VBoxContainer, el, row: int) -> void:
	# row < 0 → цвет всего клеммника (шина); иначе цвет одного ряда.
	var colors: Array = Circuit.line_color_catalog(true)
	var col_ob := OptionButton.new()
	_style_field(col_ob)
	col_ob.custom_minimum_size = Vector2(220, 28)
	var cur: String = str(el.color_id) if row < 0 or bool(el.terminal_bus) else ElectroLib.terminal_row_color_id(el, row)
	# Для ряда без шины — читать именно color_id ряда, не fallback элемента.
	if row >= 0 and not bool(el.terminal_bus):
		cur = ""
		if row < el.electro_ports.size() and typeof(el.electro_ports[row]) == TYPE_DICTIONARY:
			cur = str(el.electro_ports[row].get("color_id", ""))
	var col_sel: int = 0
	for ci in colors.size():
		var entry: Dictionary = colors[ci]
		col_ob.add_item(str(entry.get("title", "")))
		if str(entry.get("id", "")) == cur:
			col_sel = ci
	col_ob.select(col_sel)
	var row_cap: int = row
	col_ob.item_selected.connect(func(i):
		var cid: String = str(colors[i].get("id", ""))
		if row_cap < 0 or bool(el.terminal_bus):
			el.color_id = cid
			if bool(el.terminal_bus):
				for ri in el.electro_ports.size():
					if typeof(el.electro_ports[ri]) == TYPE_DICTIONARY:
						el.electro_ports[ri]["color_id"] = cid
		else:
			while el.electro_ports.size() <= row_cap:
				el.electro_ports.append({"label": "", "color_id": "", "type": "line"})
			if typeof(el.electro_ports[row_cap]) != TYPE_DICTIONARY:
				el.electro_ports[row_cap] = {"label": "", "color_id": "", "type": "line"}
			el.electro_ports[row_cap]["color_id"] = cid
		_scheme_changed()
	)
	var caption: String = "Цвет" if row_cap < 0 or bool(el.terminal_bus) else "Цвет ряда %d" % (row_cap + 1)
	box.add_child(_menu_labeled(caption, col_ob))


func _move_electro_group_followers(delta: Vector2) -> void:
	for id in _origins.keys():
		if circuit.selected_ids.has(id):
			continue
		var el = circuit.get_element(id)
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) not in ["contact", "supply_leg"]:
			continue
		if bool(el.detached) and not ElectroLib.is_button_fixed_contact(circuit, el) \
				and not ElectroLib.is_supply_fixed_leg(circuit, el):
			continue
		el.position = (_origins[id] + delta).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))


func _apply_electro_detach_after_move() -> void:
	if not _moved:
		return
	for id in circuit.selected_ids:
		var el = circuit.get_element(id)
		if el != null and str(el.kind) == "electro":
			circuit.update_electro_detach(el)
			if str(el.member_role) in ["contact", "supply_leg"]:
				continue
			if str(el.electro_class) in ["button", "e_stop"]:
				ElectroLib.layout_button_contacts(circuit, el)
			elif str(el.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
				ElectroLib.layout_coil_contacts(circuit, el)
			elif str(el.electro_class) == "supply":
				ElectroLib.layout_supply_legs(circuit, el)


func _add_wire_params(box: VBoxContainer, wire) -> void:
	if wire == null:
		return
	var ea = circuit.get_element(int(wire.a_id))
	var is_elec: bool = ea != null and Geom.port_domain(ea, str(wire.a_port)) == "electric"
	var title := Label.new()
	var title_s: String = "Провод" if is_elec else "Трубка"
	if circuit != null:
		var SimVpl2 = preload("res://scripts/domain/sim_vis.gd")
		title_s = SimVpl2.tip_plain(circuit.wire_hover_tip(wire)).replace("\n", "\n")
	title.text = title_s
	title.add_theme_color_override("font_color", UiTheme.paper_text())
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(220, 0)
	box.add_child(title)
	box.add_child(_menu_rule())
	var sizes: Array = Circuit.wire_section_catalog() if is_elec else TubeFit.tube_od_catalog()
	var size_ob := OptionButton.new()
	_style_field(size_ob)
	size_ob.custom_minimum_size = Vector2(220, 28)
	var size_sel: int = 0
	var best_d: float = 1.0e9
	var cur_size: float = float(wire.id_mm) if is_elec else float(wire.od_mm)
	if not is_elec and cur_size < 1.0:
		cur_size = float(wire.id_mm)
	for i in sizes.size():
		var s: float = float(sizes[i])
		if is_elec:
			size_ob.add_item(str(s) + " мм²")
		else:
			size_ob.add_item("Ø" + str(int(round(s))) + " (ID " + str(TubeFit.tube_id_mm(s)) + ")")
		var d: float = absf(cur_size - s)
		if d < best_d:
			best_d = d
			size_sel = i
	size_ob.select(size_sel)
	size_ob.item_selected.connect(func(i):
		if is_elec:
			wire.id_mm = float(sizes[i])
		else:
			TubeFit.apply_tube_od_to_wire(wire, float(sizes[i]))
		circuit.retune_wire(wire)
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Сечение, мм²" if is_elec else "Трубка OD, мм", size_ob))
	if not is_elec and circuit != null:
		var len_m: float = circuit._wire_path_length_m(wire)
		var vol_cm3: float = circuit._wire_volume(wire) * 1.0e6
		var lv := Label.new()
		lv.text = "L %.2f м · V %.1f см³  (%s)" % [
			len_m, vol_cm3, "3D" if float(wire.length_m) > 0.04 else "схема"
		]
		lv.add_theme_color_override("font_color", UiTheme.paper_muted())
		lv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(lv)
	var colors: Array = Circuit.line_color_catalog(is_elec)
	var col_ob := OptionButton.new()
	_style_field(col_ob)
	col_ob.custom_minimum_size = Vector2(220, 28)
	var col_sel: int = 0
	var cur_c: String = str(wire.color_id)
	for ci in colors.size():
		var entry: Dictionary = colors[ci]
		col_ob.add_item(str(entry.get("title", "")))
		if str(entry.get("id", "")) == cur_c:
			col_sel = ci
	col_ob.select(col_sel)
	col_ob.item_selected.connect(func(i):
		wire.color_id = str(colors[i].get("id", ""))
		circuit.retune_wire(wire)
		_scheme_changed()
	)
	box.add_child(_menu_labeled("Цвет", col_ob))
	if is_elec:
		box.add_child(_menu_rule())
		_add_wire_break_group_actions(box, wire)


func _add_wire_break_group_actions(box: VBoxContainer, wire) -> void:
	if wire == null or circuit == null:
		return
	var locked: bool = _sim_locks_edit()
	var wid: int = int(wire.id)
	if bool(wire.broken):
		var stitch_btn := _plain_button("Восстановить линию", locked)
		stitch_btn.pressed.connect(func():
			if locked:
				return
			circuit.set_wire_broken(wid, false)
			_hide_menu()
			_scheme_changed()
		)
		box.add_child(stitch_btn)
	else:
		var break_btn := _plain_button("Визуально оборвать линию", locked)
		break_btn.pressed.connect(func():
			if locked:
				return
			circuit.set_wire_broken(wid, true)
			_hide_menu()
			_scheme_changed()
		)
		box.add_child(break_btn)
	# Жила проходит через групповую линию (rail) — можно вывести скрытый участок вправо.
	if circuit.wire_on_group_line(wid):
		var leave_btn := _plain_button("Убрать из групповой линии", locked)
		leave_btn.pressed.connect(func():
			if locked:
				return
			circuit.nudge_wire_off_group_line(wid)
			_hide_menu()
			_scheme_changed()
		)
		box.add_child(leave_btn)


func _menu_labeled(caption: String, control: Control) -> Control:
	# Плоский блок как в меню частей — без серой подложки.
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiTheme.paper_muted())
	wrap.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(control)
	return wrap


func _clamp_float_panel_size(panel: PanelContainer = null) -> void:
	var p: PanelContainer = panel
	if p == null:
		p = _ctx
	if p == null or not is_instance_valid(p) or not p.visible:
		return
	var host: Control = p.get_parent() as Control
	var hs: Vector2 = host.size if host != null else size
	if hs.x < 8.0 or hs.y < 8.0:
		hs = size
	p.reset_size()
	var sz := p.get_combined_minimum_size()
	sz.x = clampf(sz.x, 220.0, mini(420.0, maxf(220.0, hs.x - 16.0)))
	var max_h: float = mini(maxf(80.0, hs.y - 16.0), 420.0)
	sz.y = clampf(sz.y, 80.0, max_h)
	p.size = sz
	p.position = Vector2(
		clampf(p.position.x, 4.0, maxf(4.0, hs.x - sz.x - 4.0)),
		clampf(p.position.y, 4.0, maxf(4.0, hs.y - sz.y - 4.0))
	)


func _open_parts_refresh(el) -> void:
	# После смены числа / раскрытия клетки — отложенная пересборка (не во время сигнала виджета).
	if el == null:
		return
	if _props_win != null and _props_win.visible:
		_props_win.visible = false
	var panel: PanelContainer = null
	var want_part: String = _part_kind if _part_kind != "" else "general"
	for p in _float_panels:
		if p == null or not is_instance_valid(p) or not p.visible:
			continue
		if int(p.get_meta("el_id", -1)) != int(el.id):
			continue
		var ppart: String = str(p.get_meta("part", ""))
		if ppart == want_part or (want_part == "general" and ppart == ""):
			panel = p
			break
		if panel == null:
			panel = p
	if panel == null and _ctx != null and _ctx.visible:
		panel = _ctx
	if panel == null:
		return
	var part: String = str(panel.get_meta("part", ""))
	var body: VBoxContainer = panel.get_node_or_null("Root/Body") as VBoxContainer
	var title_lbl: Label = panel.get_node_or_null("Root/TitleRow/Title") as Label
	if body == null:
		return
	while body.get_child_count() > 0:
		var old := body.get_child(0)
		body.remove_child(old)
		old.queue_free()
	_grab_id = int(el.id)
	if part != "" and part != "general":
		_part_kind = part
		if title_lbl != null:
			title_lbl.text = _float_title_text(el, part)
		for opt in _part_options_for(el, part):
			body.add_child(_choice_button(str(opt["label"]), part, str(opt["id"]), el))
		_add_part_params(body, el, part)
	else:
		_part_kind = ""
		if title_lbl != null:
			title_lbl.text = _float_title_text(el, "general")
		_add_general_element_params(body, el)
	_clamp_float_panel_size(panel)


func _clear_spool_schema(el) -> void:
	el.recipe_id = ""
	el.spool_envelopes = PackedStringArray()


func _add_envelope_pickers(box: VBoxContainer, el) -> void:
	ValveLib.normalize_spool(el)
	var n := int(el.valve_positions)
	for pos_i in n:
		_add_envelope_picker_for(box, el, pos_i, true)


func _add_envelope_picker_for(box: VBoxContainer, el, pos_i: int, collapsible: bool = false) -> void:
	ValveLib.normalize_spool(el)
	var envs: Array = ValveLib.envelopes_for_ways(int(el.valve_ways))
	if envs.is_empty():
		return
	var ways := int(el.valve_ways)
	var current := str(el.spool_envelopes[pos_i]) if pos_i < el.spool_envelopes.size() else ""
	var cur_title := current
	for env in envs:
		if str(env.get("id", "")) == current:
			cur_title = str(env.get("title", current))
			break
	var open := (not collapsible) or _envelope_open == pos_i
	if collapsible:
		var head := Button.new()
		head.focus_mode = Control.FOCUS_NONE
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.text = "%s Клетка %d · %s" % ["▾" if open else "▸", pos_i + 1, cur_title]
		head.custom_minimum_size = Vector2(248, 30)
		_style_field(head)
		var capture_pos := pos_i
		head.pressed.connect(func():
			_envelope_open = -1 if _envelope_open == capture_pos else capture_pos
			call_deferred("_open_parts_refresh", el)
		)
		box.add_child(head)
		if not open:
			return
	else:
		var lab := Label.new()
		lab.text = "Схема позиции: %s" % cur_title
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", UiTheme.muted())
		box.add_child(lab)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, mini(176, envs.size() * 54))
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_scroll(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 8)
	scroll.add_child(pad)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(list)
	for env in envs:
		var eid := str(env.get("id", ""))
		var row := _envelope_catalog_row(el, pos_i, ways, eid, str(env.get("title", eid)), eid == current)
		list.add_child(row)
	box.add_child(scroll)


func _envelope_catalog_row(el, pos_i: int, ways: int, env_id: String, title: String, selected: bool) -> Control:
	# PanelContainer, не Button: у Button дочерние контролы сжимаются и текст встаёт столбиком.
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(220, 50)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = title
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.BRAND_BLUE.r, UiTheme.BRAND_BLUE.g, UiTheme.BRAND_BLUE.b, 0.28) if selected else Color(1, 1, 1, 1)
	style.border_color = UiTheme.field_border() if selected else UiTheme.paper_border()
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 4
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", style)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inner)
	var thumb := EnvelopeThumb.new()
	thumb.ways = ways
	thumb.env_id = env_id
	thumb.custom_minimum_size = Vector2(44, 44)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(thumb)
	var lab := Label.new()
	lab.text = title
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.clip_text = true
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_color_override("font_color", UiTheme.text())
	lab.add_theme_font_size_override("font_size", 12)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(lab)
	if selected:
		lab.add_theme_color_override("font_color", UiTheme.accent())
	row.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		ValveLib.normalize_spool(el)
		var ids: PackedStringArray = el.spool_envelopes
		while ids.size() <= pos_i:
			ids.append("")
		ids[pos_i] = env_id
		el.spool_envelopes = ids
		el.recipe_id = ""
		# В свойствах оставляем каталог клетки открытым; из меню части — закрываем список.
		_envelope_open = -1 if str(_part_kind).begins_with("cell_") else pos_i
		var note: String = circuit.retune_geometry(el)
		if note != "":
			circuit.notify(note)
		_scheme_changed()
		_open_parts_refresh(el)
	)
	return row


class EnvelopeThumb extends Control:
	var ways := 5
	var env_id := ""

	func _draw() -> void:
		if env_id == "":
			return
		var s := minf(size.x, size.y) / (Geom.VALVE_SQ + 6.0)
		draw_set_transform(size * 0.5, 0.0, Vector2(s, s))
		Geom.draw_envelope_thumb(self, ways, env_id, UiTheme.preview_ink())


func _apply_part(el, part: String, option_id: String) -> void:
	var before := str(el.action)
	if el.kind == "electro":
		match part:
			"lamp_color":
				el.lamp_color = option_id
			"lamp_voltage":
				el.voltage = 24.0 if option_id == "dc24" else 220.0
			"bus_color":
				el.phase = option_id
		_scheme_changed()
		return
	if el.kind == "valve":
		match part:
			"body", "ways":
				el.valve_ways = int(option_id)
				_clear_spool_schema(el)
			"positions":
				el.valve_positions = int(option_id)
				_clear_spool_schema(el)
			"center":
				el.valve_center = option_id
				_clear_spool_schema(el)
			"nc_no":
				el.valve_nc_no = option_id
				_clear_spool_schema(el)
			"op_left":
				el.op_left = option_id
			"op_right":
				el.op_right = option_id
			"override_left":
				el.override_left = option_id == "yes"
			"override_right":
				el.override_right = option_id == "yes"
			"pilot_supply":
				el.pilot_supply = option_id
			"port_3":
				el.port_3 = option_id
			"port_5":
				el.port_5 = option_id
		var note_v: String = circuit.retune_geometry(el)
		if note_v != "":
			circuit.notify(note_v)
		_scheme_changed()
		return
	match part:
		"piston":
			el.piston_kind = option_id
		"cush_cap":
			el.cush_cap = option_id
		"cush_rod":
			el.cush_rod = option_id
		"spring":
			el.spring_side = option_id
		"rod":
			match option_id:
				"through":
					el.rod_mode = "through"
					el.carriage = "none"
				"carriage":
					el.rod_mode = "rodless"
					el.carriage = "plain"
				"magnetic":
					el.rod_mode = "rodless"
					el.carriage = "magnetic"
				_:
					el.rod_mode = "single"
					el.carriage = "none"
		"tip":
			el.rod_end = "plain"
		"brake":
			el.brake = option_id
		"mount":
			el.mount = option_id
		"guide":
			el.guide = option_id
		"bump_end":
			el.bump_end = option_id
		"body":
			el.body_style = option_id
			el.body_style_user = true
	var note: String = circuit.retune_geometry(el)
	if str(el.action) != before:
		circuit.reconfigure_action(el)
	if note != "":
		circuit.notify(note)
	_scheme_changed()


func _begin_body_press(event: InputEventMouseButton, hit, world: Vector2) -> void:
	_mode = "down"
	_press = event.position
	_moved = false
	# Первый ключ кнопки / база L — тащим primary, не ногу.
	var pick_id: int = int(hit.id)
	if ElectroLib.is_button_fixed_contact(circuit, hit) or ElectroLib.is_supply_fixed_leg(circuit, hit):
		var btn_main = circuit.get_element(int(hit.group_id))
		if btn_main != null:
			pick_id = int(btn_main.id)
	elif str(hit.kind) == "electro" and str(hit.member_role) == "supply_leg" and not bool(hit.detached):
		# Прикреплённая N/PE: если курсор ещё в зоне базы L — это тяга источника.
		var primary = circuit.get_element(int(hit.group_id))
		if primary != null and str(primary.electro_class) == "supply":
			if Geom.body_hit(primary, world):
				pick_id = int(primary.id)
	_grab_id = pick_id
	_grab_port = ""
	_part_kind = ""
	if event.shift_pressed:
		if circuit.selected_ids.has(pick_id):
			circuit.selected_ids.erase(pick_id)
		else:
			circuit.selected_ids.append(pick_id)
		circuit.selected_wire_id = -1
		circuit.selected_wire_ids.clear()
		circuit.selection_space = "schematic"
	elif not circuit.selected_ids.has(pick_id):
		circuit.select_only(pick_id, "schematic")
	else:
		circuit.selection_space = "schematic"


## Строгое попадание в корпус (без pad) — приоритет над жилами у XS L.
func _pick_body_strict(world: Vector2):
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		# Строго по габариту УГО — без pad.
		if not Geom.body_hit(el, world):
			continue
		# Прикреплённая нога N/PE не перекрывает базу L.
		if str(el.kind) == "electro" and str(el.member_role) == "supply_leg" and not bool(el.detached):
			var primary = circuit.get_element(int(el.group_id))
			if primary != null and str(primary.electro_class) == "supply":
				if Geom.body_hit(primary, world):
					return primary
		return el
	return null


func _pick_body(world: Vector2):
	# Зона выбора = габарит УГО (body_hit), без раздутого pad вокруг.
	var hit = null
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		if Geom.body_hit(el, world):
			hit = el
			break
	if hit == null:
		return null
	# Нога N/PE: клик по базе L берёт primary.
	if str(hit.kind) == "electro" and str(hit.member_role) == "supply_leg" and not bool(hit.detached):
		var primary2 = circuit.get_element(int(hit.group_id))
		if primary2 != null and str(primary2.electro_class) == "supply":
			if Geom.body_hit(primary2, world):
				return primary2
	return hit


func _pick_port(world: Vector2) -> Dictionary:
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var port := Geom.port_hit(el, world, zoom)
		if port != "":
			return {"id": el.id, "port": port}
	return {}


func _pick_rail_body(world: Vector2) -> Dictionary:
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if str(el.kind) != "rail":
			continue
		if Rail2D.hit_body(el, world, zoom):
			return {"id": el.id}
	return {}



func _pick_rail_handle(world: Vector2) -> Dictionary:
	if circuit == null:
		return {}
	# Сначала выделенная шина, иначе любая под курсором (ручки концов).
	var order: Array = []
	if circuit.selected_ids.size() == 1:
		order.append(int(circuit.selected_ids[0]))
	elif _rail_edit_id >= 0:
		order.append(_rail_edit_id)
	for el in circuit.elements:
		if str(el.kind) != "rail":
			continue
		var eid: int = int(el.id)
		if order.has(eid):
			continue
		order.append(eid)
	for eid in order:
		var el = circuit.get_element(int(eid))
		if el == null or str(el.kind) != "rail":
			continue
		var v: int = Rail2D.hit_vertex(el, world, zoom)
		if v >= 0:
			return {"id": int(el.id), "vertex": v, "seg": -1}
		var s: int = Rail2D.hit_segment_mid(el, world, zoom)
		if s >= 0:
			return {"id": int(el.id), "vertex": -1, "seg": s}
	return {}


func _begin_rail_edit(rail_edit: Dictionary, event: InputEventMouseButton) -> void:
	_mode = "rail_edit"
	_rail_edit_id = int(rail_edit["id"])
	_rail_edit_vertex = int(rail_edit.get("vertex", -1))
	_rail_edit_seg = int(rail_edit.get("seg", -1))
	_rail_edit_anchor = -1
	_rail_edit_from_start = false
	_rail_edit_poly0 = PackedVector2Array()
	_rail_edit_wire_ids.clear()
	_press = event.position
	_moved = false
	_grab_id = _rail_edit_id
	_grab_port = ""
	circuit.select_only(_rail_edit_id, "schematic")
	if event.alt_pressed and _rail_edit_vertex >= 0:
		var el_del = circuit.get_element(_rail_edit_id)
		if el_del != null and Rail2D.remove_vertex(el_del, _rail_edit_vertex):
			circuit.touch_scene()
			WireRouter2D.invalidate()
		_mode = ""
		_rail_edit_id = -1
		_rail_edit_vertex = -1
		_rail_edit_seg = -1
		_rail_edit_anchor = -1
		_rail_edit_from_start = false
		_invalidate_scheme()
		return
	# Конец шины: якорь соседа — тяга только удлиняет или делает одну «Г».
	var el_anchor = circuit.get_element(_rail_edit_id)
	if el_anchor != null and str(el_anchor.kind) == "rail" and _rail_edit_vertex >= 0:
		Rail2D.ensure_points(el_anchor)
		var np: int = el_anchor.rail_points.size()
		if np >= 2 and (_rail_edit_vertex == 0 or _rail_edit_vertex == np - 1):
			_rail_edit_from_start = _rail_edit_vertex == 0
			_rail_edit_anchor = 1 if _rail_edit_from_start else np - 2
	if el_anchor != null and str(el_anchor.kind) == "rail":
		_rail_edit_poly0 = Rail2D.world_polyline(el_anchor)
		_rail_edit_wire_ids = _collect_corridor_wires_on_rail(el_anchor)
		# Зафиксировать суставы до правки шины — иначе на release path_for уже новый.
		for wid_v in _rail_edit_wire_ids:
			var w0 = circuit.get_wire(int(wid_v))
			if w0 != null:
				_materialize(w0)
	if circuit.has_method("begin_history_group"):
		circuit.begin_history_group()


func _draw_rail_handles(ci: CanvasItem) -> void:
	if circuit == null or ci == null:
		return
	var sid: int = -1
	if circuit.selected_ids.size() == 1:
		sid = int(circuit.selected_ids[0])
	if sid < 0:
		return
	var el = circuit.get_element(sid)
	if el == null or str(el.kind) != "rail":
		return
	var pts: PackedVector2Array = Rail2D.world_polyline(el)
	if pts.size() < 2:
		return
	var col := Color(0.2, 0.55, 0.95, 0.95)
	var r: float = 5.0 / maxf(zoom, 0.35)
	var rm: float = 3.5 / maxf(zoom, 0.35)
	for i in range(pts.size()):
		ci.draw_circle(pts[i], r, col)
		ci.draw_arc(pts[i], r, 0.0, TAU, 18, Color(1, 1, 1, 0.9), 1.1 / maxf(zoom, 0.35), true)
	for i in range(pts.size() - 1):
		var mid: Vector2 = (pts[i] + pts[i + 1]) * 0.5
		ci.draw_circle(mid, rm, Color(col.r, col.g, col.b, 0.55))

## prefer_selected: при обычном клике держим уже выделенную жилу; при Shift-мульти — ближайшую.
func _pick_wire(world: Vector2, prefer_selected: bool = true):
	var best = null
	var best_d := clampf(10.0 / maxf(zoom, 0.2), 6.0, 22.0)
	# Кэш путей с прошлого _draw — без повторного A* на каждый motion.
	var paths: Array = _cached_wire_paths
	if paths.is_empty() or paths.size() != circuit.wires.size():
		WireRouter2D.prepare(circuit)
		paths = []
		for wire in circuit.wires:
			paths.append(_wire_path(wire))
		WireRouter2D.end_batch()
		_cached_wire_paths = paths
	var sel_id: int = int(circuit.selected_wire_id) if circuit != null else -1
	# Сначала выделенная — при наложении жил хватаем её, не соседа сверху.
	if prefer_selected and sel_id >= 0:
		for wi0 in circuit.wires.size():
			var w0 = circuit.wires[wi0]
			if int(w0.id) != sel_id:
				continue
			var pts0: PackedVector2Array = paths[wi0] as PackedVector2Array
			if _wire_hit_dist(world, w0, pts0) < best_d * 1.35:
				return w0
			break
	for wi in circuit.wires.size():
		var wire = circuit.wires[wi]
		var a = circuit.get_element(wire.a_id)
		var b = circuit.get_element(wire.b_id)
		if a == null or b == null:
			continue
		if Geom.port_domain(a, str(wire.a_port)) == "optic":
			continue
		var pts: PackedVector2Array = paths[wi] as PackedVector2Array
		var d: float = _wire_hit_dist(world, wire, pts)
		if d < best_d:
			best_d = d
			best = wire
	return best


## Дистанция до видимой части жилы (у обрыва — только хвосты).
func _wire_hit_dist(world: Vector2, wire, pts: PackedVector2Array) -> float:
	if pts.size() < 2:
		return 1.0e9
	if wire != null and WireBreak2D.is_schematic_cut(wire):
		var parts: Array = WireBreak2D.visual_parts(circuit, wire, pts)
		if parts.is_empty():
			return 1.0e9
		var best: float = 1.0e9
		for part_v in parts:
			var part: PackedVector2Array = part_v as PackedVector2Array
			if part.size() >= 2:
				best = minf(best, _dist_poly(world, part))
		return best
	return _dist_poly(world, pts)


func _dist_poly(p: Vector2, pts: PackedVector2Array) -> float:
	var best := 1.0e9
	for i in range(pts.size() - 1):
		best = minf(best, _dist_seg(p, pts[i], pts[i + 1]))
	return best


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _key(event: InputEventKey) -> void:
	var ctrl := event.ctrl_pressed or event.meta_pressed
	if event.keycode == KEY_ESCAPE:
		if (_mode == "move" or _mode == "bend") and circuit.has_method("end_history_group"):
			circuit.end_history_group()
		# Отмена ghost-drag / проводки без commit.
		_clear_drag_ghosts()
		_wire_cancel()
		_drag_delta = Vector2.ZERO
		_drag_omit_ids.clear()
		armed_kind = ""
		_mode = ""
		_hide_menu()
		accept_event()
		return
	# Копирование / выделение — можно смотреть; правки схемы при пуске — нет.
	if ctrl and event.keycode == KEY_C:
		circuit.copy_selected()
		accept_event()
		return
	if ctrl and event.keycode == KEY_A:
		circuit.selected_ids.clear()
		for el in circuit.elements:
			circuit.selected_ids.append(el.id)
		circuit.selected_wire_id = -1
		circuit.selected_wire_ids.clear()
		accept_event()
		return
	if _sim_locks_edit():
		if event.keycode in [KEY_DELETE, KEY_BACKSPACE, KEY_R] \
				or (ctrl and event.keycode in [KEY_X, KEY_V, KEY_D, KEY_Z, KEY_Y]):
			circuit.notify("Во время симуляции схема не редактируется")
			accept_event()
		return
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		circuit.remove_selected()
		accept_event()
	elif ctrl and event.keycode == KEY_X:
		circuit.cut_selected()
		accept_event()
	elif ctrl and event.keycode == KEY_V:
		circuit.paste(_screen_to_world(get_local_mouse_position()))
		accept_event()
	elif ctrl and event.keycode == KEY_D:
		circuit.duplicate_selected()
		accept_event()
	elif ctrl and event.keycode == KEY_Z and not event.shift_pressed:
		if circuit.has_method("undo_edit") and circuit.undo_edit():
			_invalidate_scheme()
		accept_event()
	elif ctrl and (event.keycode == KEY_Y or (event.keycode == KEY_Z and event.shift_pressed)):
		if circuit.has_method("redo_edit") and circuit.redo_edit():
			_invalidate_scheme()
		accept_event()
	elif event.keycode == KEY_R:
		var pre_rot: Dictionary = _snapshot_wire_paths_touching_selected()
		var rotated_r: Dictionary = circuit.rotate_selected()
		_reroute_wires_after_rotate(rotated_r, pre_rot)
		accept_event()


func _open_menu(screen: Vector2) -> void:
	grab_focus()
	apply_ui_theme()
	var world := _screen_to_world(screen)
	_menu_world = world
	# ПКМ: ближайший объект → свойства (выбор из списка — на ЛКМ).
	var hits: Array = _collect_hits_at(world)
	if hits.size() >= 1:
		_activate_hit(screen, hits[0] as Dictionary)
		return
	circuit.clear_selection()
	# Пустое место — без меню (буфер: Ctrl+X/C/V, Del).
	_part_kind = ""


## Все жилы и УГО в радиусе клика (для ЛКМ-списка при наложении).
func _collect_hits_at(world: Vector2) -> Array:
	var out: Array = []
	if circuit == null:
		return out
	var hit_r: float = clampf(10.0 / maxf(zoom, 0.2), 6.0, 22.0)
	var paths: Array = _cached_wire_paths
	if paths.is_empty() or paths.size() != circuit.wires.size():
		WireRouter2D.prepare(circuit)
		paths = []
		for w0 in circuit.wires:
			paths.append(_wire_path(w0))
		WireRouter2D.end_batch()
		_cached_wire_paths = paths
	for wi in circuit.wires.size():
		var wire = circuit.wires[wi]
		var a = circuit.get_element(int(wire.a_id))
		var b = circuit.get_element(int(wire.b_id))
		if a == null or b == null:
			continue
		if Geom.port_domain(a, str(wire.a_port)) == "optic":
			continue
		var pts: PackedVector2Array = paths[wi] as PackedVector2Array
		var d: float = _wire_hit_dist(world, wire, pts)
		if d > hit_r:
			continue
		var title: String = _hit_wire_title(wire)
		out.append({
			"kind": "wire",
			"id": int(wire.id),
			"dist": d,
			"title": title,
		})
	# УГО / части — без дублей одного id.
	var seen_el: Dictionary = {}
	for i in range(circuit.elements.size() - 1, -1, -1):
		var el = circuit.elements[i]
		if el == null:
			continue
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var eid: int = int(el.id)
		if seen_el.has(eid):
			continue
		var part: String = Geom.part_hit(el, world, zoom)
		var on_body: bool = Geom.body_hit(el, world)
		if part == "" and not on_body:
			continue
		# Нога N/PE → primary, если клик по базе.
		var target = el
		if str(el.member_role) == "supply_leg" and not bool(el.detached):
			var primary = circuit.get_element(int(el.group_id))
			if primary != null and str(primary.electro_class) == "supply" and Geom.body_hit(primary, world):
				target = primary
				eid = int(primary.id)
				if seen_el.has(eid):
					continue
				part = ""
		seen_el[eid] = true
		var tag: String = str(target.tag) if str(target.tag) != "" else str(target.kind)
		var title_el: String = tag
		if part != "":
			title_el = "%s · %s" % [tag, _part_title_for(target, part)]
		var ctr: Vector2 = Geom.world_bounds(target).get_center()
		out.append({
			"kind": "el",
			"id": eid,
			"part": part,
			"dist": world.distance_to(ctr),
			"title": title_el,
		})
	out.sort_custom(func(a, b):
		var da: float = float(a.get("dist", 0.0))
		var db: float = float(b.get("dist", 0.0))
		if absf(da - db) > 0.25:
			return da < db
		# Жилы выше УГО при равной дистанции — типичный случай «обрыв под обрывом».
		var ka: String = str(a.get("kind", ""))
		var kb: String = str(b.get("kind", ""))
		if ka != kb:
			return ka == "wire"
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return out


func _hit_wire_title(wire) -> String:
	if wire == null or circuit == null:
		return "Линия"
	var tip: String = circuit.wire_hover_tip(wire)
	var title: String = "Линия"
	if tip != "":
		var SimVpl = preload("res://scripts/domain/sim_vis.gd")
		title = SimVpl.tip_plain(tip).split("\n")[0]
	if bool(wire.broken):
		title = "%s · обрыв" % title
	return title


## Есть ли видимая плавающая панель (выбор / свойства) на указанном хосте.
func has_visible_float_on(host: Control) -> bool:
	if host == null or not is_instance_valid(host):
		return false
	for p in _float_panels:
		if p == null or not is_instance_valid(p):
			continue
		if not bool(p.visible):
			continue
		if p.get_parent() == host:
			return true
	return false


## Белое окошко: перечень объектов под ЛКМ (2D или из 3D-оверлея).
func _open_hit_picker(screen: Vector2, hits: Array, from_3d: bool = false) -> void:
	if hits.is_empty():
		return
	# Hover-тултип схемы иначе перекрывает список (z_tip=50 > z_float=30).
	if _tip != null:
		_tip.visible = false
	_part_kind = ""
	var screen_cap: Vector2 = screen
	var from_3d_cap: bool = from_3d
	_fill_ctx_menu(screen, "Выбор (%d)" % hits.size(), -1, "pick", func(box: VBoxContainer) -> void:
		for item_v in hits:
			var item: Dictionary = item_v as Dictionary
			var btn := _plain_button(str(item.get("title", "?")), false)
			var captured: Dictionary = item.duplicate(true)
			btn.pressed.connect(func():
				if from_3d_cap:
					_activate_hit_3d(captured)
				else:
					_activate_hit(screen_cap, captured)
			)
			box.add_child(btn)
	)


## Выбор из 3D: выделить в цехе (гизмо) и открыть свойства на оверлее.
func _activate_hit_3d(hit: Dictionary) -> void:
	if hit.is_empty() or circuit == null:
		return
	var eid: int = int(hit.get("id", -1))
	if eid < 0:
		return
	var el = circuit.get_element(eid)
	if el == null:
		return
	var host: Control = _hit_picker_3d_host
	_hit_picker_3d_host = null
	circuit.select_only(eid, "workshop")
	_hide_menu()
	var screen: Vector2 = Vector2.ZERO
	if host != null and is_instance_valid(host):
		screen = host.get_local_mouse_position()
	open_element_props_from_3d(eid, host, screen)


## Белый список с 3D-оверлея (ЛКМ по нескольким машинам под лучом).
func open_hit_picker_from_3d(hits: Array, host: Control = null, local_pos: Vector2 = Vector2.ZERO) -> void:
	if hits.is_empty():
		return
	_hit_picker_3d_host = host if host != null else self
	_float_place_host = _hit_picker_3d_host
	var screen: Vector2 = local_pos
	if screen == Vector2.ZERO and _float_place_host != null:
		screen = _float_place_host.get_local_mouse_position()
	var mapped: Array = []
	for item_v in hits:
		var item: Dictionary = item_v as Dictionary
		mapped.append({
			"kind": "el",
			"id": int(item.get("id", -1)),
			"part": "",
			"dist": float(item.get("t", 0.0)),
			"title": str(item.get("title", "?")),
		})
	_open_hit_picker(screen, mapped, true)


func _activate_hit(screen: Vector2, hit: Dictionary) -> void:
	if hit.is_empty() or circuit == null:
		return
	var kind: String = str(hit.get("kind", ""))
	if kind == "wire":
		var w = circuit.get_wire(int(hit.get("id", -1)))
		if w == null:
			return
		circuit.select_wire(int(w.id), "schematic")
		_schedule_live()
		_request_both("pick_wire")
		_open_wire_ctx(screen, w)
		return
	if kind == "el":
		var el = circuit.get_element(int(hit.get("id", -1)))
		if el == null:
			return
		var part: String = str(hit.get("part", ""))
		if not circuit.selected_ids.has(int(el.id)):
			circuit.select_only(int(el.id), "schematic")
		else:
			circuit.selection_space = "schematic"
		_grab_id = int(el.id)
		_schedule_live()
		if part != "" and part != "general":
			_part_kind = part
			_open_parts(screen)
		else:
			_part_kind = ""
			_open_general_params(screen, el)


func _hide_menu() -> void:
	# Закрываем только незакреплённые; pinned остаются.
	var kept: Array = []
	for p in _float_panels:
		if p == null or not is_instance_valid(p):
			continue
		if bool(p.get_meta("pinned", false)):
			kept.append(p)
			continue
		p.visible = false
		if p == _ctx:
			# Очистить тело, панель переиспользуем.
			var body: VBoxContainer = p.get_node_or_null("Root/Body") as VBoxContainer
			if body != null:
				while body.get_child_count() > 0:
					var old := body.get_child(0)
					body.remove_child(old)
					old.queue_free()
			kept.append(p)
		else:
			p.queue_free()
	_float_panels = kept
	if _ctx == null or not is_instance_valid(_ctx) or not _float_panels.has(_ctx):
		_ctx = _create_float_panel()
		_float_panels.append(_ctx)
		add_child(_ctx)


## Закрыть незакреплённые белые окошки (в т.ч. открытые поверх 3D).
func hide_unpinned_floats() -> void:
	_hide_menu()


func _selected_wire_is_pneumo() -> bool:
	if circuit == null or circuit.selected_wire_id < 0:
		return false
	var w = circuit.get_wire(circuit.selected_wire_id)
	if w == null:
		return false
	var ea = circuit.get_element(int(w.a_id))
	var eb = circuit.get_element(int(w.b_id))
	if ea != null and Geom.port_domain(ea, str(w.a_port)) == "electric":
		return false
	if eb != null and Geom.port_domain(eb, str(w.b_port)) == "electric":
		return false
	return true


func _choice_button(text: String, part: String, option_id: String, el, menu_part: String = "") -> Button:
	var current := _current_part_id(el, part)
	var button := _plain_button(text, false)
	if option_id == current:
		# Выбрано — подсветкой, без «✓» в подписи.
		button.add_theme_color_override("font_color", UiTheme.accent())
	if _sim_locks_edit():
		button.disabled = true
	button.pressed.connect(func():
		if _sim_locks_edit():
			return
		_apply_part(el, part, option_id)
		_grab_id = el.id
		# Остаёмся в родительском меню (напр. шток), а не открываем подменю одной опции.
		_part_kind = menu_part if menu_part != "" else part
		call_deferred("_open_parts_refresh", el)
	)
	return button


func _current_part_id(el, part: String) -> String:
	if el.kind == "electro":
		match part:
			"lamp_color":
				return str(el.lamp_color)
			"lamp_voltage":
				return _lamp_voltage_id(el)
			"bus_color":
				return str(el.phase) if str(el.phase) != "" else "N"
		return ""
	if el.kind == "valve":
		match part:
			"body", "ways":
				return str(el.valve_ways)
			"positions":
				return str(el.valve_positions)
			"center":
				return str(el.valve_center)
			"nc_no":
				return str(el.valve_nc_no)
			"op_left":
				return str(el.op_left)
			"op_right":
				return str(el.op_right)
			"override_left":
				return "yes" if bool(el.override_left) else "no"
			"override_right":
				return "yes" if bool(el.override_right) else "no"
			"pilot_supply":
				return str(el.pilot_supply)
			"port_3":
				return str(el.port_3)
			"port_5":
				return str(el.port_5)
		return ""
	match part:
		"piston":
			return str(el.piston_kind)
		"cush_cap":
			return str(el.cush_cap)
		"cush_rod":
			return str(el.cush_rod)
		"spring":
			return str(el.spring_side)
		"rod":
			if str(el.rod_mode) == "through":
				return "through"
			if str(el.rod_mode) == "rodless":
				return "magnetic" if str(el.carriage) == "magnetic" else "carriage"
			return "single"
		"brake":
			return str(el.brake)
		"mount":
			return str(el.mount)
		"guide":
			return str(el.guide)
		"bump_end":
			return str(el.bump_end)
		"body":
			return str(el.body_style)
	return ""


func _menu_button(text: String, id: int, disabled: bool) -> Button:
	var button := _plain_button(text, disabled)
	button.pressed.connect(func():
		_hide_menu()
		_on_menu(id)
	)
	return button


func _plain_button(text: String, disabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(220, 28)
	button.focus_mode = Control.FOCUS_NONE
	var plain := StyleBoxFlat.new()
	plain.bg_color = Color(0, 0, 0, 0)
	plain.content_margin_left = 8
	plain.content_margin_right = 8
	var hover := StyleBoxFlat.new()
	hover.bg_color = UiTheme.menu_hover()
	hover.content_margin_left = 8
	hover.content_margin_right = 8
	button.add_theme_stylebox_override("normal", plain)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", plain)
	var fg := UiTheme.text()
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_hover_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_color_override("font_disabled_color", UiTheme.muted())
	return button


func _menu_rule() -> Control:
	var rule := ColorRect.new()
	rule.color = UiTheme.menu_border()
	rule.custom_minimum_size = Vector2(160, 1)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rule


func _wire_path(wire) -> PackedVector2Array:
	return WireRouter2D.path_for(circuit, wire)


## Видимые куски жилы (обрыв / rail-коридор) — те же, что рисуются.
func _wire_visual_parts(wire, pts: PackedVector2Array) -> Array:
	if wire == null or pts.size() < 2:
		return []
	var a = circuit.get_element(int(wire.a_id))
	if a == null:
		return [pts]
	var domain: String = Geom.port_domain(a, str(wire.a_port))
	if domain == "electric" and WireBreak2D.is_schematic_cut(wire):
		return WireBreak2D.visual_parts(circuit, wire, pts)
	if domain == "electric":
		circuit.heal_wire_rail_skips(wire, pts)
	var skip_ids: Array = circuit.wire_rail_skip_ids(wire)
	var vis: Dictionary = Rail2D.visual_for_path(circuit, domain, pts, skip_ids)
	var parts: Array = vis.get("parts", [pts]) as Array
	if parts.is_empty():
		return [pts]
	return parts


## Углы для draw/pick: только на видимых кусках и с индексом в полном пути.
func _wire_corner_handles(wire, pts: PackedVector2Array) -> Array:
	var out: Array = []
	if wire == null or pts.size() < 3:
		return out
	var seen: Dictionary = {}
	var parts: Array = _wire_visual_parts(wire, pts)
	for part_v in parts:
		var part: PackedVector2Array = part_v as PackedVector2Array
		if part.size() < 3:
			continue
		for i in range(1, part.size() - 1):
			var incoming_h: bool = absf(part[i].y - part[i - 1].y) <= absf(part[i].x - part[i - 1].x)
			var outgoing_h: bool = absf(part[i + 1].y - part[i].y) <= absf(part[i + 1].x - part[i].x)
			if incoming_h == outgoing_h:
				continue
			var wpos: Vector2 = part[i]
			var idx: int = _path_vertex_index_near(pts, wpos)
			if idx < 1 or idx >= pts.size() - 1:
				continue
			if seen.has(idx):
				continue
			seen[idx] = true
			# Оси из видимого куска (полный путь в коридоре может быть коллинеарен).
			out.append({
				"pos": wpos,
				"index": idx,
				"in_h": incoming_h,
				"out_h": outgoing_h,
			})
	return out


func _path_vertex_index_near(pts: PackedVector2Array, world: Vector2) -> int:
	var best_i: int = -1
	var best_d: float = Geom.SCH_GRID * 0.85
	for i in range(1, pts.size() - 1):
		var d: float = pts[i].distance_to(world)
		if d <= best_d:
			best_d = d
			best_i = i
	return best_i


## selected_only: только ручки выделенной жилы (приоритет мыши над УГО/портами).
## anchors_only: углы + кружок середины (для hover-подсветки); без hit по всей полосе сегмента.
func _pick_grip(world: Vector2, selected_only: bool = false, anchors_only: bool = false) -> Dictionary:
	# Screen-constant hit: при zoom-out углы всё ещё ловятся.
	var corner_base: float = clampf(14.0 / maxf(zoom, 0.2), 8.0, 32.0)
	var seg_base: float = clampf(10.0 / maxf(zoom, 0.2), 6.0, 24.0)
	# Якорь середины сегмента (кружок) — hit ≈ визуал; для hover чуть теснее.
	var mid_base: float = clampf(7.5 / maxf(zoom, 0.2), 5.0, 16.0)
	if anchors_only:
		corner_base = clampf(10.0 / maxf(zoom, 0.2), 6.0, 22.0)
		mid_base = clampf(6.0 / maxf(zoom, 0.2), 4.0, 12.0)
	_ensure_wire_paths()
	var paths: Array = _cached_wire_paths
	if paths.is_empty() or paths.size() != circuit.wires.size():
		return {}
	var sel_id: int = int(circuit.selected_wire_id) if circuit != null else -1
	var has_sel: bool = sel_id >= 0
	if not has_sel and circuit != null:
		for sid in circuit.selected_wire_ids:
			has_sel = true
			sel_id = int(sid)
			break
	if selected_only and not has_sel:
		return {}
	var order: Array = []
	if sel_id >= 0:
		order.append(sel_id)
	if circuit != null:
		for sid2 in circuit.selected_wire_ids:
			var sid_i: int = int(sid2)
			if not order.has(sid_i):
				order.append(sid_i)
	if not selected_only:
		for w_all in circuit.wires:
			var wid: int = int(w_all.id)
			if not order.has(wid):
				order.append(wid)
	var corner := {}
	var best_corner_d: float = corner_base * 2.0
	for wid2 in order:
		var wire = circuit.get_wire(int(wid2))
		if wire == null:
			continue
		if WireBreak2D.is_schematic_cut(wire):
			continue
		var wi: int = -1
		for i in circuit.wires.size():
			if int(circuit.wires[i].id) == int(wid2):
				wi = i
				break
		if wi < 0 or wi >= paths.size():
			continue
		var pts: PackedVector2Array = paths[wi] as PackedVector2Array
		var mul: float = 1.45 if int(wid2) == sel_id or _wire_is_selected(wire) else 1.0
		var corner_d: float = corner_base * mul
		for h in _wire_corner_handles(wire, pts):
			var dist: float = world.distance_to(h["pos"] as Vector2)
			if dist < corner_d and dist < best_corner_d:
				best_corner_d = dist
				corner = {
					"wire": wire,
					"kind": "point",
					"index": int(h["index"]),
					"in_h": bool(h["in_h"]),
					"out_h": bool(h["out_h"]),
				}
				if int(wid2) == sel_id or _wire_is_selected(wire):
					return corner
	if not corner.is_empty():
		return corner
	# Сначала кружок-якорь середины, потом вся полоса сегмента — по видимым кускам.
	var mid_hit := {}
	var best_mid_d: float = mid_base * 2.0
	for wid_m in order:
		var wire_m = circuit.get_wire(int(wid_m))
		if wire_m == null:
			continue
		if WireBreak2D.is_schematic_cut(wire_m):
			continue
		var wi_m: int = -1
		for jm in circuit.wires.size():
			if int(circuit.wires[jm].id) == int(wid_m):
				wi_m = jm
				break
		if wi_m < 0 or wi_m >= paths.size():
			continue
		var pts_m: PackedVector2Array = paths[wi_m] as PackedVector2Array
		var mid_r: float = mid_base * (1.45 if _wire_is_selected(wire_m) else 1.0)
		for part_mv in _wire_visual_parts(wire_m, pts_m):
			var part_m: PackedVector2Array = part_mv as PackedVector2Array
			for im in range(part_m.size() - 1):
				if part_m[im].distance_to(part_m[im + 1]) < 14.0:
					continue
				var mid_pt: Vector2 = (part_m[im] + part_m[im + 1]) * 0.5
				var dm: float = world.distance_to(mid_pt)
				if dm < mid_r and dm < best_mid_d:
					var seg_i: int = _path_seg_index_near(pts_m, mid_pt)
					if seg_i < 0:
						continue
					best_mid_d = dm
					mid_hit = {"wire": wire_m, "kind": "seg", "index": seg_i}
					if _wire_is_selected(wire_m):
						return mid_hit
	if not mid_hit.is_empty():
		return mid_hit
	# Hover-подсветка: не цеплять всю полосу сегмента (жёлтый круг на любом наведении на жилу).
	if anchors_only:
		return {}
	var segment := {}
	var best_seg_d: float = seg_base * 2.0
	for wid3 in order:
		var wire3 = circuit.get_wire(int(wid3))
		if wire3 == null:
			continue
		if WireBreak2D.is_schematic_cut(wire3):
			continue
		var wi3: int = -1
		for j in circuit.wires.size():
			if int(circuit.wires[j].id) == int(wid3):
				wi3 = j
				break
		if wi3 < 0 or wi3 >= paths.size():
			continue
		var pts3: PackedVector2Array = paths[wi3] as PackedVector2Array
		var seg_d: float = seg_base * (1.45 if _wire_is_selected(wire3) else 1.0)
		for part_sv in _wire_visual_parts(wire3, pts3):
			var part_s: PackedVector2Array = part_sv as PackedVector2Array
			for i3 in range(part_s.size() - 1):
				var dist3: float = _dist_seg(world, part_s[i3], part_s[i3 + 1])
				if dist3 < seg_d and dist3 < best_seg_d:
					var seg_i3: int = _path_seg_index_near(pts3, (part_s[i3] + part_s[i3 + 1]) * 0.5)
					if seg_i3 < 0:
						continue
					best_seg_d = dist3
					segment = {"wire": wire3, "kind": "seg", "index": seg_i3}
					if _wire_is_selected(wire3):
						return segment
	return segment


func _path_seg_index_near(pts: PackedVector2Array, world: Vector2) -> int:
	var best_i: int = -1
	var best_d: float = Geom.SCH_GRID * 1.25
	for i in range(pts.size() - 1):
		var d: float = _dist_seg(world, pts[i], pts[i + 1])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _arm_bend(grip: Dictionary) -> void:
	var wire = grip["wire"]
	circuit.select_wire(wire.id, "schematic")
	_bend_wire_id = wire.id
	_bend_kind = grip["kind"]
	_bend_index = int(grip["index"])
	_bend_in_h = bool(grip.get("in_h", true))
	_bend_out_h = bool(grip.get("out_h", false))
	_seg_ready = false
	# Материализовать сразу — иначе первый motion с рассинхроном joints/path.
	_materialize(wire)
	# Сразу убрать жилу с Base — иначе призрак на старом пути до конца drag.
	_request_base("bend_start")
	_request_live(true)


func _apply_bend(world: Vector2) -> void:
	var wire = circuit.get_wire(_bend_wire_id)
	if wire == null:
		return
	_materialize(wire)
	var snapped := world.snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))
	if _bend_kind == "point":
		_move_corner(wire, snapped)
	else:
		_move_segment(wire, snapped)


func _materialize(wire) -> void:
	var pts := _wire_path(wire)
	var need: int = maxi(pts.size() - 2, 0)
	# Пусто или рассинхрон с путём (после rail/роутера) — пересобрать суставы.
	if wire.joints.is_empty() or wire.joints.size() != need:
		wire.joints.clear()
		for i in range(1, pts.size() - 1):
			wire.joints.append(pts[i])


func _move_corner(wire, target: Vector2) -> void:
	var joint := _bend_index - 1
	if joint < 0 or joint >= wire.joints.size():
		# Индекс устарел — найти ближайший сустав к целевой точке пути.
		_materialize(wire)
		joint = clampi(_bend_index - 1, 0, maxi(wire.joints.size() - 1, 0))
		if wire.joints.is_empty():
			return
	var pts := _wire_path(wire)
	if pts.size() < 2:
		return
	var pos := target
	if joint == 0:
		if _bend_in_h:
			pos.y = pts[0].y
		else:
			pos.x = pts[0].x
	else:
		var left: Vector2 = wire.joints[joint - 1]
		if _bend_in_h:
			left.y = target.y
			pos.y = target.y
		else:
			left.x = target.x
			pos.x = target.x
		wire.joints[joint - 1] = left
	var last: int = wire.joints.size() - 1
	if joint == last:
		if _bend_out_h:
			pos.y = pts[pts.size() - 1].y
		else:
			pos.x = pts[pts.size() - 1].x
	else:
		var right: Vector2 = wire.joints[joint + 1]
		if _bend_out_h:
			right.y = target.y
			pos.y = target.y
		else:
			right.x = target.x
			pos.x = target.x
		wire.joints[joint + 1] = right
	wire.joints[joint] = pos.snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))
	_bend_index = joint + 1


func _move_segment(wire, target: Vector2) -> void:
	if not _seg_ready:
		_prepare_segment(wire, target)
		_seg_ready = true
	var coord := target.y if _seg_h else target.x
	if _seg_j0 >= 0 and _seg_j0 < wire.joints.size():
		var left: Vector2 = wire.joints[_seg_j0]
		if _seg_h:
			left.y = coord
		else:
			left.x = coord
		wire.joints[_seg_j0] = left
	if _seg_j1 >= 0 and _seg_j1 < wire.joints.size() and _seg_j1 != _seg_j0:
		var right: Vector2 = wire.joints[_seg_j1]
		if _seg_h:
			right.y = coord
		else:
			right.x = coord
		wire.joints[_seg_j1] = right


func _prepare_segment(wire, target: Vector2) -> void:
	var pts := _wire_path(wire)
	var i0 := _bend_index
	if pts.size() < 2 or i0 < 0 or i0 >= pts.size() - 1:
		_seg_j0 = -1
		_seg_j1 = -1
		return
	var i1 := i0 + 1
	_seg_h = absf(pts[i1].x - pts[i0].x) >= absf(pts[i1].y - pts[i0].y)
	var port_a: Vector2 = pts[0]
	var port_b: Vector2 = pts[pts.size() - 1]
	if pts.size() == 2:
		if _seg_h:
			wire.joints = [Vector2(port_a.x, target.y), Vector2(port_b.x, target.y)]
		else:
			wire.joints = [Vector2(target.x, port_a.y), Vector2(target.x, port_b.y)]
		_seg_j0 = 0
		_seg_j1 = 1
		return
	var j0 := i0 - 1 if i0 > 0 else -1
	var j1 := i1 - 1 if i1 < pts.size() - 1 else -1
	if j0 < 0:
		var stub := Vector2(port_a.x, target.y) if _seg_h else Vector2(target.x, port_a.y)
		wire.joints.insert(0, stub)
		j1 = 1 if wire.joints.size() > 1 else 0
		j0 = 0
	elif j1 < 0:
		var stub := Vector2(port_b.x, target.y) if _seg_h else Vector2(target.x, port_b.y)
		wire.joints.append(stub)
		j1 = wire.joints.size() - 1
	_seg_j0 = j0
	_seg_j1 = j1


func _write_joints(wire) -> void:
	if wire == null or circuit == null:
		return
	var a = circuit.get_element(int(wire.a_id))
	var b = circuit.get_element(int(wire.b_id))
	var na := Vector2.ZERO
	var nb := Vector2.ZERO
	var ta := Vector2.ZERO
	var tb := Vector2.ZERO
	if a != null:
		var pa: Dictionary = Geom.port_by_name(a, str(wire.a_port))
		if not pa.is_empty():
			ta = Geom.to_world(a, pa["local"] as Vector2)
			na = (pa["normal"] as Vector2).rotated(float(a.rotation_quad) * PI * 0.5)
	if b != null:
		var pb: Dictionary = Geom.port_by_name(b, str(wire.b_port))
		if not pb.is_empty():
			tb = Geom.to_world(b, pb["local"] as Vector2)
			nb = (pb["normal"] as Vector2).rotated(float(b.rotation_quad) * PI * 0.5)
	_bake_simplified_joints(wire, _wire_path(wire), ta, tb, na, nb)
	circuit.retune_wire(wire)


## Схлопнуть путь (реверсы/коллинеар/микро-П) и записать суставы.
## Прямая / соосные tip → clear (автороут). Ручную Г (вправо→вниз и т.п.) НЕ сбрасывать —
## иначе автороут снова выберет «сначала по нормали порта» (линия 6).
func _bake_simplified_joints(
	wire, pts: PackedVector2Array, ta: Vector2, tb: Vector2, na: Vector2, nb: Vector2
) -> void:
	if wire == null:
		return
	var clean: PackedVector2Array = Geom.simplify_ortho_path(Geom._dedupe(Geom._ortho(pts)))
	wire.joints.clear()
	if clean.size() < 2:
		return
	# Только настоящая прямая tip↔tip или соосные tip навстречу.
	if clean.size() <= 2 or _tips_want_straight(ta, tb, na, nb, clean):
		return
	if _wire_path_has_reverse(clean):
		return
	for i in range(1, clean.size() - 1):
		wire.joints.append(clean[i])
	if _wire_joints_are_loopy(wire):
		wire.joints.clear()


func _wire_port_tip(el_id: int, port: String) -> Vector2:
	var el = circuit.get_element(el_id)
	if el == null:
		return Vector2.ZERO
	var p: Dictionary = Geom.port_by_name(el, port)
	if p.is_empty():
		return el.position
	return Geom.to_world(el, p["local"])


## Кратчайший путь буквой Г: from → угол → to (без from). Одинаковая манхэттен-длина — H затем V.
func _wire_l_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var g: float = Geom.SCH_GRID
	var a: Vector2 = Vector2(snappedf(from.x, g), snappedf(from.y, g))
	var b: Vector2 = Vector2(snappedf(to.x, g), snappedf(to.y, g))
	var out: PackedVector2Array = PackedVector2Array()
	if a.distance_to(b) < g * 0.5:
		return out
	if absf(a.x - b.x) < 0.5 or absf(a.y - b.y) < 0.5:
		out.append(b)
		return out
	out.append(Vector2(b.x, a.y))
	out.append(b)
	return out


func _wire_append_l(joints: Array, from: Vector2, to: Vector2) -> Vector2:
	var segs: PackedVector2Array = _wire_l_path(from, to)
	var last: Vector2 = from
	for i in segs.size():
		var p: Vector2 = segs[i]
		if p.distance_to(last) < Geom.SCH_GRID * 0.5:
			continue
		joints.append(p)
		last = p
	return last


func _wire_start(el_id: int, port: String) -> void:
	_mode = "wire"
	_wire_from_id = el_id
	_wire_from_port = port
	_wire_joints.clear()
	_wire_anchor = _wire_port_tip(el_id, port)
	_press = get_local_mouse_position()
	_moved = false
	_grab_id = el_id
	_grab_port = port
	_request_live(true)


func _wire_place_bend(world: Vector2) -> void:
	var g: float = Geom.SCH_GRID
	var pt: Vector2 = Vector2(snappedf(world.x, g), snappedf(world.y, g))
	if pt.distance_to(_wire_anchor) < g * 0.5:
		return
	_wire_anchor = _wire_append_l(_wire_joints, _wire_anchor, pt)
	_request_live(true)


func _wire_try_finish(el_id: int, port: String) -> void:
	if el_id == _wire_from_id and port == _wire_from_port:
		return
	var to_el = circuit.get_element(el_id)
	if to_el == null:
		return
	if circuit.port_wire_count(el_id, port) >= circuit.port_wire_limit(to_el, port):
		circuit.notify("Порт занят")
		return
	var tip_b: Vector2 = _wire_port_tip(el_id, port)
	var joints: Array = []
	for j in _wire_joints:
		joints.append(j)
	# Г до tip порта; сам tip — конец провода, в joints не кладём.
	var segs: PackedVector2Array = _wire_l_path(_wire_anchor, tip_b)
	for i in segs.size():
		var p: Vector2 = segs[i]
		if p.distance_to(tip_b) < 0.5:
			continue
		if joints.is_empty() or (joints[joints.size() - 1] as Vector2).distance_to(p) >= Geom.SCH_GRID * 0.5:
			joints.append(p)
	var ok: bool = false
	if circuit.has_method("add_wire_with_joints"):
		ok = bool(circuit.add_wire_with_joints(_wire_from_id, _wire_from_port, el_id, port, joints))
	else:
		ok = bool(circuit.add_wire(_wire_from_id, _wire_from_port, el_id, port))
		if ok:
			var w = circuit.get_wire(circuit.selected_wire_id)
			if w != null:
				w.joints = joints
				circuit.touch_scene()
	_wire_cancel()
	if ok:
		_paths_dirty = true
		_request_both("wire_done")


func _wire_cancel() -> void:
	_wire_joints.clear()
	_wire_from_id = -1
	_wire_from_port = ""
	_wire_anchor = Vector2.ZERO
	_grab_port = ""
	if _mode == "wire":
		_mode = ""
	_request_live(true)


func _draw_wire_draft(ci: CanvasItem) -> void:
	var from_el = circuit.get_element(_wire_from_id)
	if from_el == null:
		return
	var port := Geom.port_by_name(from_el, _wire_from_port)
	if port.is_empty():
		return
	var col := Color(0.15, 0.45, 0.75)
	var lw: float = _sch_line_world_w(1.7)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Geom.to_world(from_el, port["local"]))
	for j in _wire_joints:
		pts.append(j as Vector2)
	var cur: Vector2 = _screen_to_world(get_local_mouse_position())
	var g: float = Geom.SCH_GRID
	cur = Vector2(snappedf(cur.x, g), snappedf(cur.y, g))
	var tail: PackedVector2Array = _wire_l_path(_wire_anchor, cur)
	for i in tail.size():
		pts.append(tail[i])
	if tail.is_empty() and cur.distance_to(_wire_anchor) >= g * 0.5:
		pts.append(cur)
	for i in range(pts.size() - 1):
		ci.draw_line(pts[i], pts[i + 1], col, lw, false)
	ci.draw_circle(cur, _sch_line_world_w(3.2), col)


func _spawn_drag_ghosts() -> void:
	_clear_drag_ghosts()
	if _world_root == null or font == null:
		return
	for oid in _origins.keys():
		var el = circuit.get_element(int(oid))
		if el == null:
			continue
		var g: Node2D = DragGhostScript.new()
		g.name = "DragGhost_%d" % int(oid)
		_world_root.add_child(g)
		g.setup(el, font)
		_drag_ghosts[int(oid)] = g


func _device_table_preview_dict() -> Dictionary:
	return {
		"dy_l": _device_table_prev_dy_l,
		"dy_r": _device_table_prev_dy_r,
		"edge_l": _device_table_prev_edge_l,
		"edge_r": _device_table_prev_edge_r,
	}


func _device_table_write_el(el, from_preview: bool) -> void:
	if el == null:
		return
	if from_preview:
		el.device_table_dy_left = _device_table_prev_dy_l
		el.device_table_dy_right = _device_table_prev_dy_r
		el.device_table_edge_left = _device_table_prev_edge_l
		el.device_table_edge_right = _device_table_prev_edge_r
	else:
		el.device_table_dy_left = _device_table_origin_dy_l
		el.device_table_dy_right = _device_table_origin_dy_r
		el.device_table_edge_left = _device_table_origin_edge_l
		el.device_table_edge_right = _device_table_origin_edge_r


func _device_table_read_preview_from_el(el) -> void:
	if el == null:
		return
	_device_table_prev_dy_l = float(el.device_table_dy_left)
	_device_table_prev_dy_r = float(el.device_table_dy_right)
	_device_table_prev_edge_l = str(el.device_table_edge_left)
	_device_table_prev_edge_r = str(el.device_table_edge_right)


func _device_table_preview_move_edge(el, to_edge: String) -> void:
	# Временно пишем preview в el → helper → читаем обратно; el снова origin.
	_device_table_write_el(el, true)
	ElectroSymbols.device_move_table_to_side(el, _device_table_side, to_edge)
	_device_table_read_preview_from_el(el)
	_device_table_write_el(el, false)


func _device_table_preview_clamp_dy(el, dy: float) -> float:
	_device_table_write_el(el, true)
	var out: float = ElectroSymbols.device_clamp_table_dy(el, _device_table_side, dy)
	_device_table_write_el(el, false)
	return out


func _spawn_device_table_ghost(el) -> void:
	_clear_drag_ghosts()
	if _world_root == null or font == null or el == null:
		return
	var g: Node2D = DragGhostScript.new()
	g.name = "DragGhost_table_%d" % int(el.id)
	_world_root.add_child(g)
	g.setup(el, font)
	if g.has_method("set_table_preview"):
		g.set_table_preview(_device_table_preview_dict())
	_drag_ghosts[int(el.id)] = g


func _refresh_device_table_ghost() -> void:
	var g: Node2D = _drag_ghosts.get(_device_table_id) as Node2D
	if g != null and g.has_method("set_table_preview"):
		g.set_table_preview(_device_table_preview_dict())


func _update_drag_ghosts(delta: Vector2) -> void:
	for oid in _origins.keys():
		var g: Node2D = _drag_ghosts.get(int(oid)) as Node2D
		if g == null:
			continue
		var origin: Vector2 = _origins[oid] as Vector2
		g.position = (origin + delta).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))


func _commit_drag_positions(delta: Vector2) -> void:
	for oid in _origins.keys():
		var el = circuit.get_element(int(oid))
		if el == null:
			continue
		var origin: Vector2 = _origins[oid] as Vector2
		el.position = (origin + delta).snapped(Vector2(Geom.SCH_GRID, Geom.SCH_GRID))


func _clear_drag_ghosts() -> void:
	for oid in _drag_ghosts.keys():
		var g: Node2D = _drag_ghosts[oid] as Node2D
		if g != null and is_instance_valid(g):
			g.queue_free()
	_drag_ghosts.clear()


func _reroute_wires_of_moved(bake_physics: bool = false) -> void:
	# AS-style: топология изломов (Г/П) сохраняется; у tip — плечо может сменить
	# направление, остальные сегменты только длину. Старый путь — из кэша до patch.
	var deltas: Dictionary = {}
	for oid in _origins.keys():
		var el0 = circuit.get_element(int(oid))
		if el0 == null:
			continue
		deltas[int(oid)] = el0.position - (_origins[oid] as Vector2)
	var affected: Dictionary = {}
	for wi in circuit.wires.size():
		var wire = circuit.wires[wi]
		var aid: int = int(wire.a_id)
		var bid: int = int(wire.b_id)
		var has_a: bool = deltas.has(aid)
		var has_b: bool = deltas.has(bid)
		if not has_a and not has_b:
			continue
		var da: Vector2 = deltas.get(aid, Vector2.ZERO) as Vector2
		var db: Vector2 = deltas.get(bid, Vector2.ZERO) as Vector2
		var old_path: PackedVector2Array = PackedVector2Array()
		if wi < _cached_wire_paths.size():
			old_path = (_cached_wire_paths[wi] as PackedVector2Array).duplicate()
		if has_a and has_b and da.is_equal_approx(db):
			_rubber_band_wire(wire, old_path, true, true, da)
		else:
			_rubber_band_wire(wire, old_path, has_a, has_b, Vector2.ZERO)
		affected[int(wire.id)] = true
		if bake_physics:
			circuit.retune_wire(wire)
		else:
			WireRouter2D.invalidate_wire(int(wire.id))
	# Групповая линия: жилы коридора (не tip’ы) — сдвинуть вместе с rail.
	for oid in deltas.keys():
		var rail_el = circuit.get_element(int(oid))
		if rail_el == null or str(rail_el.kind) != "rail":
			continue
		var d_rail: Vector2 = deltas[int(oid)] as Vector2
		if d_rail.length_squared() < 0.25:
			continue
		var saved_pos: Vector2 = rail_el.position
		rail_el.position = _origins[oid] as Vector2
		var corridor_ids: Array = _collect_corridor_wires_on_rail(rail_el)
		rail_el.position = saved_pos
		for wid_v in corridor_ids:
			var wid: int = int(wid_v)
			if affected.has(wid):
				continue
			var cw = circuit.get_wire(wid)
			if cw == null:
				continue
			var old_c: PackedVector2Array = PackedVector2Array()
			for wi2 in circuit.wires.size():
				if int(circuit.wires[wi2].id) == wid:
					if wi2 < _cached_wire_paths.size():
						old_c = (_cached_wire_paths[wi2] as PackedVector2Array).duplicate()
					break
			_translate_wire_joints(cw, d_rail, old_c)
			affected[wid] = true
			if bake_physics:
				circuit.retune_wire(cw)
			else:
				WireRouter2D.invalidate_wire(wid)
	if bake_physics:
		WireRouter2D.invalidate()
	elif not affected.is_empty():
		_patch_cached_wire_paths(affected)


## Жилы, у которых visual_for_path сейчас входит в эту шину.
func _collect_corridor_wires_on_rail(rail_el) -> Array:
	var out: Array = []
	if rail_el == null or circuit == null or str(rail_el.kind) != "rail":
		return out
	var rid: int = int(rail_el.id)
	_ensure_wire_paths()
	for wi in circuit.wires.size():
		var wire = circuit.wires[wi]
		var a = circuit.get_element(int(wire.a_id))
		if a == null:
			continue
		var domain: String = Geom.port_domain(a, str(wire.a_port))
		var pts: PackedVector2Array = PackedVector2Array()
		if wi < _cached_wire_paths.size():
			pts = (_cached_wire_paths[wi] as PackedVector2Array).duplicate()
		if pts.size() < 2:
			pts = WireRouter2D.path_for(circuit, wire)
		if pts.size() < 2:
			continue
		var skip_ids: Array = circuit.wire_rail_skip_ids(wire)
		if Rail2D.path_uses_rail(circuit, domain, pts, rid, skip_ids):
			out.append(int(wire.id))
	return out


func _translate_wire_joints(wire, delta: Vector2, old_path: PackedVector2Array = PackedVector2Array()) -> void:
	if wire == null or delta.length_squared() < 0.01:
		return
	# Старый путь из кэша — иначе path_for уже видит новую шину и суставы «уедут» дважды.
	if old_path.size() >= 3:
		wire.joints.clear()
		for i in range(1, old_path.size() - 1):
			wire.joints.append(old_path[i] + delta)
		return
	_materialize(wire)
	var joints: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
	for i in joints.size():
		var j = joints[i]
		if typeof(j) == TYPE_VECTOR2:
			wire.joints[i] = (j as Vector2) + delta


## После правки геометрии шины — перенести суставы жил коридора вместе с poly.
func _apply_rail_edit_corridor_shift() -> void:
	if circuit == null or _rail_edit_id < 0 or _rail_edit_wire_ids.is_empty():
		return
	var el = circuit.get_element(_rail_edit_id)
	if el == null or str(el.kind) != "rail":
		return
	var poly0: PackedVector2Array = _rail_edit_poly0
	var poly1: PackedVector2Array = Rail2D.world_polyline(el)
	if poly0.size() < 2 or poly1.size() < 2:
		return
	var thr: float = Geom.SCH_GRID * 1.6
	var n: int = mini(poly0.size(), poly1.size())
	var uniform: bool = n >= 2
	var d0: Vector2 = poly1[0] - poly0[0]
	if uniform:
		for i in range(1, n):
			if (poly1[i] - poly0[i]).distance_to(d0) > Geom.SCH_GRID * 0.51:
				uniform = false
				break
	if uniform and d0.length_squared() < 0.25:
		return
	var affected: Dictionary = {}
	for wid_v in _rail_edit_wire_ids:
		var wire = circuit.get_wire(int(wid_v))
		if wire == null:
			continue
		_materialize(wire)
		var joints: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
		var any: bool = false
		for i in joints.size():
			var j = joints[i]
			if typeof(j) != TYPE_VECTOR2:
				continue
			var jp: Vector2 = j as Vector2
			if uniform:
				wire.joints[i] = jp + d0
				any = true
			else:
				var dd: Vector2 = Rail2D.map_point_poly_delta(jp, poly0, poly1, thr)
				if dd.length_squared() < 0.01:
					continue
				wire.joints[i] = jp + dd
				any = true
		if not any:
			continue
		affected[int(wire.id)] = true
		WireRouter2D.invalidate_wire(int(wire.id))
	if not affected.is_empty():
		_patch_cached_wire_paths(affected)


## Снимок путей жил, касающихся текущего выделения (до rotate).
func _snapshot_wire_paths_touching_selected() -> Dictionary:
	var out: Dictionary = {}
	if circuit == null:
		return out
	_ensure_wire_paths()
	var sel: Dictionary = {}
	for sid in circuit.selected_ids:
		sel[int(sid)] = true
	for wi in circuit.wires.size():
		var w = circuit.wires[wi]
		if not sel.has(int(w.a_id)) and not sel.has(int(w.b_id)):
			continue
		if wi < _cached_wire_paths.size():
			out[int(w.id)] = (_cached_wire_paths[wi] as PackedVector2Array).duplicate()
	return out


## AS rubber-band: число изломов не растёт. Двигается только сустав у tip —
## плечи Г/П меняют длину; выход tip→j0 по нормали порта наружу.
func _rubber_band_wire(
	wire, old_path: PackedVector2Array, move_a: bool, move_b: bool, translate: Vector2
) -> void:
	if wire == null or circuit == null:
		return
	var a = circuit.get_element(int(wire.a_id))
	var b = circuit.get_element(int(wire.b_id))
	if a == null or b == null:
		return
	var pa: Dictionary = Geom.port_by_name(a, str(wire.a_port))
	var pb: Dictionary = Geom.port_by_name(b, str(wire.b_port))
	if pa.is_empty() or pb.is_empty():
		return
	var new_ta: Vector2 = Geom.to_world(a, pa["local"] as Vector2)
	var new_tb: Vector2 = Geom.to_world(b, pb["local"] as Vector2)
	var na: Vector2 = (pa["normal"] as Vector2).rotated(float(a.rotation_quad) * PI * 0.5)
	var nb: Vector2 = (pb["normal"] as Vector2).rotated(float(b.rotation_quad) * PI * 0.5)
	var pts: PackedVector2Array = old_path
	if pts.size() < 2:
		var joints0: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
		if not joints0.is_empty():
			pts = PackedVector2Array()
			pts.append(new_ta - (translate if move_a else Vector2.ZERO))
			for j in joints0:
				if typeof(j) == TYPE_VECTOR2:
					pts.append(j as Vector2)
			pts.append(new_tb - (translate if move_b else Vector2.ZERO))
		else:
			wire.joints.clear()
			return
	if move_a and move_b and translate.length_squared() > 0.01:
		for i in pts.size():
			pts[i] = pts[i] + translate
	else:
		pts = _ortho_rubber_band(pts, new_ta, new_tb, move_a, move_b, na, nb)
		if pts.is_empty():
			wire.joints.clear()
			return
	_bake_simplified_joints(wire, pts, new_ta, new_tb, na, nb)


## Tip на одной оси и нормали навстречу → достаточно отрезка tip↔tip (без бокового П).
func _tips_want_straight(
	ta: Vector2, tb: Vector2, na: Vector2, nb: Vector2, pts: PackedVector2Array
) -> bool:
	if pts.size() <= 2:
		return false
	var ca: Vector2 = _cardinal_normal(na)
	var cb: Vector2 = _cardinal_normal(nb)
	if ca == Vector2.ZERO or cb == Vector2.ZERO:
		return false
	var g: float = Geom.SCH_GRID
	# Одна вертикаль, выход A вниз/вверх навстречу B.
	if absf(ta.x - tb.x) <= g * 0.51 and absf(ca.x) < 0.5 and absf(cb.x) < 0.5:
		var dy: float = tb.y - ta.y
		if absf(dy) < g * 0.5:
			return false
		if dy * ca.y > 0.5 and (-dy) * cb.y > 0.5:
			return true
	# Одна горизонталь.
	if absf(ta.y - tb.y) <= g * 0.51 and absf(ca.y) < 0.5 and absf(cb.y) < 0.5:
		var dx: float = tb.x - ta.x
		if absf(dx) < g * 0.5:
			return false
		if dx * ca.x > 0.5 and (-dx) * cb.x > 0.5:
			return true
	return false


func _ortho_rubber_band(
	pts: PackedVector2Array, new_a: Vector2, new_b: Vector2,
	move_a: bool, move_b: bool, na: Vector2, nb: Vector2
) -> PackedVector2Array:
	if pts.size() < 2:
		return PackedVector2Array([new_a, new_b])
	var out: PackedVector2Array = pts.duplicate()
	var old: PackedVector2Array = pts.duplicate()
	if move_a:
		out[0] = new_a
		if out.size() >= 3:
			out = _slide_tip_joint(out, old, true, na)
			if out.is_empty():
				return PackedVector2Array()
		elif out.size() == 2 and not move_b:
			out[1] = new_b
	if move_b:
		out[out.size() - 1] = new_b
		if out.size() >= 3:
			out = _slide_tip_joint(out, old, false, nb)
			if out.is_empty():
				return PackedVector2Array()
	var g: float = Geom.SCH_GRID
	var snapped := PackedVector2Array()
	for i in out.size():
		var p: Vector2 = out[i]
		if i == 0 or i == out.size() - 1:
			snapped.append(p)
		else:
			snapped.append(p.snapped(Vector2(g, g)))
	return snapped


## Сдвиг только j0 у tip: tip→j0 вдоль нормали наружу, j0→j1 — та же ось, что была.
## Новых суставов не добавляем. Если геометрия ломается — пустой путь → clear/autoroute.
func _slide_tip_joint(
	pts: PackedVector2Array, old_pts: PackedVector2Array, from_a: bool, normal: Vector2
) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	var npts: int = out.size()
	if npts < 3 or old_pts.size() < 3:
		return out
	var tip_i: int = 0 if from_a else npts - 1
	var j0_i: int = 1 if from_a else npts - 2
	var j1_i: int = 2 if from_a else npts - 3
	var tip: Vector2 = out[tip_i]
	var j1: Vector2 = out[j1_i]
	var old_j0: Vector2 = old_pts[1] if from_a else old_pts[old_pts.size() - 2]
	var old_j1: Vector2 = old_pts[2] if from_a else old_pts[old_pts.size() - 3]
	var seg1_h: bool = absf(old_j1.y - old_j0.y) <= absf(old_j1.x - old_j0.x)
	var n: Vector2 = _cardinal_normal(normal)
	var g: float = Geom.SCH_GRID
	var cand: Vector2
	if n == Vector2.ZERO:
		# Без нормали — классическое Г: сохранить ось j0→j1.
		if seg1_h:
			cand = Vector2(tip.x, j1.y)
		else:
			cand = Vector2(j1.x, tip.y)
	elif absf(n.x) > 0.5:
		# Выход горизонтальный (L/R): tip→j0 по H, j0→j1 по V → j0 = (j1.x, tip.y).
		cand = Vector2(j1.x, tip.y)
		if (cand - tip).dot(n) <= 0.5:
			return PackedVector2Array()
		# Если старый j0→j1 был H, а cand даёт V — это смена оси внутреннего плеча.
		# Допустимо только когда tip.y≈j1.y (тогда коллапс в прямую).
		if seg1_h and absf(tip.y - j1.y) > g * 0.5:
			# Внутреннее плечо было H: tip остаётся на ряду j1.y — иначе нужен новый излом.
			# Тянем только длину H: j0 на том же ряду, x по нормали / к j1.
			cand = Vector2(j1.x, j1.y)
			# tip→cand не ортогонален если tip.y != j1.y — нужен излом → autoroute.
			if absf(tip.y - j1.y) > 0.5 and absf(tip.x - j1.x) > 0.5:
				return PackedVector2Array()
	else:
		# Выход вертикальный (U/D): tip→j0 по V, j0→j1 по H → j0 = (tip.x, j1.y).
		cand = Vector2(tip.x, j1.y)
		if (cand - tip).dot(n) <= 0.5:
			return PackedVector2Array()
		if not seg1_h and absf(tip.x - j1.x) > g * 0.5:
			cand = Vector2(j1.x, j1.y)
			if absf(tip.x - j1.x) > 0.5 and absf(tip.y - j1.y) > 0.5:
				return PackedVector2Array()
	if cand.distance_to(tip) < 0.5:
		# Коллапс tip↔j0 — убрать j0, tip стыкуется к j1.
		var trimmed := PackedVector2Array()
		for i in npts:
			if i == j0_i:
				continue
			trimmed.append(out[i])
		return trimmed
	out[j0_i] = cand.snapped(Vector2(g, g))
	# Выход tip→j0 должен быть наружу по нормали (если нормаль есть).
	if n != Vector2.ZERO:
		var leave: Vector2 = out[j0_i] - tip
		var along: bool = (absf(n.x) > 0.5 and absf(leave.x) >= absf(leave.y) - 0.01) \
			or (absf(n.y) > 0.5 and absf(leave.y) >= absf(leave.x) - 0.01)
		if not along or leave.dot(n) <= 0.5:
			return PackedVector2Array()
	return out


func _cardinal_normal(normal: Vector2) -> Vector2:
	if absf(normal.x) >= absf(normal.y):
		if absf(normal.x) < 1.0e-6:
			return Vector2.ZERO
		return Vector2(signf(normal.x), 0.0)
	if absf(normal.y) < 1.0e-6:
		return Vector2.ZERO
	return Vector2(0.0, signf(normal.y))


func _points_colinear(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: Vector2 = b - a
	var bc: Vector2 = c - b
	if ab.length_squared() < 0.25 or bc.length_squared() < 0.25:
		return true
	var ab_h: bool = absf(ab.y) <= absf(ab.x)
	var bc_h: bool = absf(bc.y) <= absf(bc.x)
	return ab_h == bc_h


func _strip_colinear(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		if _points_colinear(out[out.size() - 1], pts[i], pts[i + 1]):
			continue
		out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return Geom._dedupe(out)


func _wire_path_has_reverse(pts: PackedVector2Array) -> bool:
	var g: float = Geom.SCH_GRID
	for i in range(pts.size() - 2):
		var ab: Vector2 = pts[i + 1] - pts[i]
		var bc: Vector2 = pts[i + 2] - pts[i + 1]
		if ab.dot(bc) < -0.01 and minf(ab.length(), bc.length()) > g * 0.9:
			return true
	return false


## Петля/мусор: только явный реверс или путь сильно длиннее manhattan.
## Ручная П (суставы вне AABB tip) — норма; раньше сбрасывалась в прямую (29/46/62/63).
func _wire_joints_are_loopy(wire) -> bool:
	if wire == null or circuit == null:
		return false
	var joints: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
	if joints.is_empty():
		return false
	var a = circuit.get_element(int(wire.a_id))
	var b = circuit.get_element(int(wire.b_id))
	if a == null or b == null:
		return false
	var pa: Dictionary = Geom.port_by_name(a, str(wire.a_port))
	var pb: Dictionary = Geom.port_by_name(b, str(wire.b_port))
	if pa.is_empty() or pb.is_empty():
		return false
	var ta: Vector2 = Geom.to_world(a, pa["local"] as Vector2)
	var tb: Vector2 = Geom.to_world(b, pb["local"] as Vector2)
	var manh: float = absf(ta.x - tb.x) + absf(ta.y - tb.y)
	var pts: PackedVector2Array = Geom.polyline(a, str(wire.a_port), b, str(wire.b_port), joints)
	var plen: float = Geom.path_length_px(pts)
	var g: float = Geom.SCH_GRID
	# Только совсем раздутый путь (после сдвига УГО), не обычная ручная П.
	if plen > manh * 3.2 + g * 16.0:
		return true
	return _wire_path_has_reverse(pts)


## После R / меню «Повернуть»: резинка от снимка пути, без полного clear joints.
func _reroute_wires_after_rotate(rotated_ids: Dictionary, pre_paths: Dictionary = {}) -> void:
	if circuit == null or rotated_ids.is_empty():
		return
	var affected: Dictionary = {}
	WireRouter2D.rotate_lite = true
	for wire in circuit.wires:
		var aid: int = int(wire.a_id)
		var bid: int = int(wire.b_id)
		var rot_a: bool = rotated_ids.has(aid)
		var rot_b: bool = rotated_ids.has(bid)
		if not rot_a and not rot_b:
			continue
		var old_path: PackedVector2Array = PackedVector2Array()
		if pre_paths.has(int(wire.id)):
			old_path = pre_paths[int(wire.id)] as PackedVector2Array
		_rubber_band_wire(wire, old_path, rot_a, rot_b, Vector2.ZERO)
		WireRouter2D.invalidate_wire(int(wire.id))
		affected[int(wire.id)] = true
	WireRouter2D.rotate_lite = false
	if affected.is_empty():
		return
	_patch_cached_wire_paths(affected)
	_request_both("rotate")
	queue_redraw()


## Пересчитать только затронутые жилы в экранном кэше — чужие пути не трогаем.
func _patch_cached_wire_paths(affected_ids: Dictionary) -> void:
	if circuit == null or affected_ids.is_empty():
		return
	if _cached_wire_paths.size() != circuit.wires.size():
		_paths_dirty = true
		return
	WireRouter2D.prepare(circuit)
	for wi in circuit.wires.size():
		var w = circuit.wires[wi]
		if not affected_ids.has(int(w.id)):
			continue
		_cached_wire_paths[wi] = _wire_path(w)
	WireRouter2D.end_batch()
	_cached_trunk_data = WireTrunks2D.build(circuit, _cached_wire_paths)
	_paths_dirty = false


func _bake_moved() -> void:
	# bake_physics=false: retune_wire на каждой жиле → N×touch_scene/history = дикий фриз.
	_reroute_wires_of_moved(false)


func close_properties() -> void:
	if _props_win != null:
		_props_dragging = false
		_props_win.visible = false
		# Вернуть панель на схему, чтобы не осталась висеть на оверлее 3D.
		if _props_win.get_parent() != self:
			_reparent_props_to(self)


func _on_menu(id: int) -> void:
	# 2=copy, 7=свойства — можно при пуске; остальное — правка схемы.
	if _sim_locks_edit() and id not in [2, 7]:
		circuit.notify("Во время симуляции схема не редактируется")
		return
	match id:
		1:
			circuit.cut_selected()
		2:
			circuit.copy_selected()
		3:
			circuit.paste(_menu_world)
		4:
			circuit.duplicate_selected()
		5:
			circuit.remove_selected()
		6:
			var pre_m: Dictionary = _snapshot_wire_paths_touching_selected()
			var rotated_m: Dictionary = circuit.rotate_selected()
			_reroute_wires_after_rotate(rotated_m, pre_m)
		7:
			var el7 = circuit.primary()
			if el7 != null:
				_open_general_params(_ctx.position if _ctx else get_local_mouse_position(), el7)
			elif circuit.selected_wire_id >= 0:
				_open_wire_ctx(_ctx.position if _ctx else get_local_mouse_position(), circuit.get_wire(circuit.selected_wire_id))
			return
		8:
			if _selected_wire_is_pneumo():
				circuit.insert_junction_on_wire(circuit.selected_wire_id, _menu_world, "tee")
		9:
			if _selected_wire_is_pneumo():
				circuit.insert_junction_on_wire(circuit.selected_wire_id, _menu_world, "wye")
		10:
			if _selected_wire_is_pneumo():
				circuit.insert_junction_on_wire(circuit.selected_wire_id, _menu_world, "manifold")
	_hide_menu()


func open_properties_at(screen: Vector2 = Vector2.ZERO) -> void:
	if screen == Vector2.ZERO:
		screen = size * 0.5
	_open_properties(screen)


## Вызов из 3D: общее окно элемента на оверлее 3D у курсора.
func open_element_props_from_3d(el_id: int, host: Control = null, local_pos: Vector2 = Vector2.ZERO) -> void:
	if circuit == null:
		return
	var el = circuit.get_element(el_id)
	if el == null:
		return
	circuit.select_only(el_id, "workshop")
	_props_place_host = host if host != null else self
	var screen: Vector2 = local_pos
	if screen == Vector2.ZERO:
		var h: Control = _props_place_host
		screen = h.size * 0.5 if h != null else size * 0.5
	_open_properties(screen, el)


func _shell():
	var node := get_parent()
	while node:
		if node.has_method("open_properties"):
			return node
		node = node.get_parent()
	return null


func _draw() -> void:
	## Chrome: бумага, сетка, marquee, подсказка. Схема — в Base/Live слоях.
	## Сетка здесь (screen-space): при zoom/pan не остаётся белых полей до перерисовки Base.
	_sync_world_xform()
	var paper := UiTheme.schematic_bg()
	draw_rect(Rect2(Vector2.ZERO, size), paper)
	if circuit == null:
		return
	var sim_live: bool = bool(circuit.running)
	if not sim_live:
		_draw_grid(self)
	if _mode == "marquee" and _moved:
		var a := pan + _marquee.position * zoom
		var b := _marquee.size * zoom
		draw_rect(Rect2(a, b), Color(0.2, 0.48, 0.85, 0.12), true)
		draw_rect(Rect2(a, b), Color(0.16, 0.46, 0.86, 0.9), false, 1.2)
	var help: String = _context_hotkey_help()
	if help != "":
		var help_font := font if font else ThemeDB.fallback_font
		var help_bg := paper
		help_bg.a = 0.92
		draw_rect(Rect2(0, size.y - 28, size.x, 28), help_bg)
		draw_string(help_font, Vector2(12, size.y - 9), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.schematic_help_fg())
	_perf_ms_draw = _perf_ms_base + _perf_ms_live


## Актуальные хоткеи (как в Blender: «Ctrl+C - Копировать»), только рабочие сейчас.
func _context_hotkey_help() -> String:
	if circuit == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var sim_lock: bool = _sim_locks_edit()
	# Режим жеста — только его отмена / завершение.
	if armed_kind != "":
		parts.append("ЛКМ - Поставить")
		parts.append("Shift+ЛКМ - Поставить ещё")
		parts.append("Esc - Отмена")
		return _fit_hotkey_help(parts)
	match str(_mode):
		"wire":
			parts.append("ЛКМ - Точка / соединить")
			parts.append("ПКМ - Отмена")
			parts.append("Esc - Отмена")
			return _fit_hotkey_help(parts)
		"pan":
			parts.append("Перетаскивание - Панорама")
			parts.append("Колесо - Масштаб")
			return _fit_hotkey_help(parts)
		"move", "down":
			parts.append("Перетаскивание - Переместить")
			parts.append("Esc - Отмена")
			return _fit_hotkey_help(parts)
		"bend":
			parts.append("Перетаскивание - Изгиб")
			parts.append("Esc - Отмена")
			return _fit_hotkey_help(parts)
		"marquee":
			parts.append("Перетаскивание - Рамка")
			parts.append("Esc - Отмена")
			return _fit_hotkey_help(parts)
		"tag", "wire_num", "rail_edit":
			parts.append("Перетаскивание - Сдвиг")
			parts.append("Esc - Отмена")
			return _fit_hotkey_help(parts)
		"actuate", "electro_btn":
			parts.append("Удержание - Орган")
			return _fit_hotkey_help(parts)
	# Обзор камеры — всегда.
	parts.append("СКМ - Панорама")
	parts.append("Space+ЛКМ - Панорама")
	parts.append("Колесо - Масштаб")
	var has_el: bool = not circuit.selected_ids.is_empty()
	var has_wire: bool = int(circuit.selected_wire_id) >= 0
	if not sim_lock:
		if has_el or has_wire:
			parts.append("Del - Удалить")
		if has_el:
			parts.append("R - Повернуть")
			parts.append("Ctrl+C - Копировать")
			parts.append("Ctrl+X - Вырезать")
			parts.append("Ctrl+D - Дублировать")
		if not circuit.clipboard.is_empty():
			parts.append("Ctrl+V - Вставить")
		parts.append("Ctrl+A - Выделить всё")
		if circuit.has_method("can_undo") and bool(circuit.can_undo()):
			parts.append("Ctrl+Z - Отменить")
		if circuit.has_method("can_redo") and bool(circuit.can_redo()):
			parts.append("Ctrl+Y - Повторить")
		parts.append("ЛКМ - Выделить")
		parts.append("ЛКМ+drag - Переместить")
		parts.append("ЛКМ (наложение) - Список")
		parts.append("ПКМ - Свойства")
	else:
		parts.append("ЛКМ - Выделить / орган")
		parts.append("Ctrl+C - Копировать")
		parts.append("Ctrl+A - Выделить всё")
	return _fit_hotkey_help(parts)


func _fit_hotkey_help(parts: PackedStringArray) -> String:
	if parts.is_empty():
		return ""
	var help_font: Font = font if font else ThemeDB.fallback_font
	var max_w: float = maxf(size.x - 24.0, 80.0)
	var out: String = ""
	for i in parts.size():
		var piece: String = str(parts[i])
		var cand: String = piece if out == "" else "%s · %s" % [out, piece]
		var tw: float = help_font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if out != "" and tw > max_w:
			break
		out = cand
	return out


func _refresh_hotkey_help_bar() -> void:
	var now: String = _context_hotkey_help()
	if now == _hotkey_help_cached:
		return
	_hotkey_help_cached = now
	queue_redraw()


func perf_ms_draw() -> float:
	return _perf_ms_draw


func perf_draw_debug() -> Dictionary:
	return {
		"ms_base": _perf_ms_base,
		"ms_live": _perf_ms_live,
		"base_draws": _dbg_base_draws,
		"base_reqs": _dbg_base_reqs,
		"live_draws": _dbg_live_draws,
		"scene_changed": _dbg_scene_changed,
		"last_base_reason": _dbg_last_base_reason,
		"mode": _mode,
		"paths_dirty": _paths_dirty,
		"live_pending": _live_pending,
		"base_busy": _base_draw_busy,
	}


## Base: топология + редкий снимок sim (поршень/давление). Номера всегда здесь.
func draw_base_layer(ci: CanvasItem) -> void:
	var t0: int = Time.get_ticks_usec()
	_base_draw_busy = true
	_dbg_base_draws += 1
	if circuit == null or ci == null:
		_perf_ms_base = 0.0
		_base_draw_busy = false
		return
	_base_last_draw_msec = Time.get_ticks_msec()
	_ensure_wire_paths()
	var show_vals: bool = bool(circuit.running) or float(circuit.sim_time) > 0.0
	var sim_live: bool = bool(circuit.running)
	var press_viz: bool = bool(circuit.pressure_viz)
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var p_max_over: float = 0.0
	if press_viz and show_vals:
		if circuit.has_method("viz_max_over_pa_cached"):
			p_max_over = circuit.viz_max_over_pa_cached()
		else:
			p_max_over = circuit.viz_max_over_pa()
	_bind_layer_meta(ci, p_max_over)
	var wire_paths: Array = _cached_wire_paths
	var trunk_data: Dictionary = _cached_trunk_data
	var view_rect: Rect2 = _view_rect_world()
	# Мелкий zoom / нулевой size после reparent сплита — cull сжигает все жилы.
	# Во время СКМ-pan cull выкл: один кадр в начале тянет всё, дальше только transform.
	var cull_wires: bool = (
		_mode != "pan" and zoom >= 0.55 and size.x > 32.0 and size.y > 32.0
	)
	# Сетка — в Control._draw (screen-space), не на Base.
	_draw_wire_trunks(ci, trunk_data)
	for wi in circuit.wires.size():
		var w = circuit.wires[wi]
		# Провода перетаскиваемых — на Live, иначе двоение/старый хвост на Base.
		if not _drag_omit_ids.is_empty() \
				and (_drag_omit_ids.has(int(w.a_id)) or _drag_omit_ids.has(int(w.b_id))):
			continue
		# Изгиб: старый путь на Base = призрак; актуальный — только на Live.
		if _bend_wire_id >= 0 and int(w.id) == _bend_wire_id:
			continue
		var wpath: PackedVector2Array = wire_paths[wi] as PackedVector2Array
		if cull_wires and wpath.size() >= 2 and not _path_visible_in_view(wpath, view_rect):
			continue
		_draw_wire(ci, w, show_vals, press_viz and show_vals, wpath, p_max_over)
	var ink_override_on: bool = false
	if press_viz and show_vals:
		ink_override_on = true
	elif UiTheme.dark:
		Geom.begin_preview_ink(UiTheme.preview_ink())
		ink_override_on = true
	# Hover/selection на Base только вне Run (при Run — лёгкий Live).
	var draw_hover_here: bool = not sim_live
	var omit_motion: bool = _motion_layer_active()
	for el in circuit.elements:
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		# Перетаскиваемые — на Live, иначе двоение и полный redraw Base.
		if _drag_omit_ids.has(int(el.id)):
			continue
		var selected: bool = circuit.selected_ids.has(el.id)
		var el_sel: bool = selected
		if cull_wires and not el_sel and not Geom.world_bounds(el).intersects(view_rect):
			continue
		var hover := ""
		if draw_hover_here:
			hover = (_hover_port if _hover_id == el.id else "")
			var ext: Dictionary = _ext_hover_for_el(el)
			if str(ext.get("port", "")) != "":
				hover = str(ext["port"])
			if _mode == "wire" and _wire_from_id == el.id and _wire_from_port != "":
				hover = _wire_from_port
		var el_sim_viz: bool = show_vals
		if sim_live and circuit.has_method("is_sim_active") and not circuit.is_sim_active(int(el.id)):
			el_sim_viz = false
		var is_ctrl: bool = press_viz and show_vals and SimV.is_sim_control(el) and str(el.kind) == "electro"
		var ink_pushed: bool = false
		if selected and not (press_viz and show_vals):
			Geom.begin_preview_ink(Geom.selection_ink(UiTheme.dark))
			ink_pushed = true
		elif press_viz and show_vals:
			# Давление красит только пневмо; электро/датчики/шины — обычный ink (не dim).
			if is_ctrl:
				Geom.begin_preview_ink(SimV.sim_control_ink(UiTheme.dark))
				ink_pushed = true
			elif str(el.kind) in [
				"source", "junction", "accessory", "cylinder", "valve",
				"rotary_cylinder", "air_motor",
			]:
				var p_pa: float = circuit.element_viz_pressure(el)
				var base_ink: Color = Color(0.78, 0.80, 0.82) if not UiTheme.dark else Color(0.55, 0.58, 0.62)
				Geom.begin_preview_ink(SimV.pressure_color_2d(p_pa, base_ink, p_max_over))
				ink_pushed = true
			# electro / sensor / coil / rail — без override
		# Base: выделение = синие штрихи; hover-часть — только на Live.
		Geom.draw_element(ci, el, font, selected, el_sim_viz, hover, "", omit_motion)
		if str(el.kind) == "valve" and el_sim_viz and not omit_motion:
			Geom.begin_preview_ink(SimV.sim_control_ink(UiTheme.dark))
			Geom.draw_valve_operators(ci, el, font)
			ink_pushed = true
		if ink_pushed:
			if UiTheme.dark and not (press_viz and show_vals):
				Geom.begin_preview_ink(UiTheme.preview_ink())
			else:
				Geom.end_preview_ink()
	# Режим давления: сбросить ink до оверлеев/номеров (иначе подписи электро красятся последним УГО).
	if press_viz and show_vals:
		Geom.end_preview_ink()
	if show_vals and press_viz:
		_draw_atm_exhausts(ci)
		for wi2 in circuit.wires.size():
			_draw_wire_flow_marks(ci, circuit.wires[wi2], wire_paths[wi2] as PackedVector2Array)
	var drag_ex: Array = []
	if _mode == "move":
		for id in circuit.selected_ids:
			var de = circuit.get_element(id)
			if de != null and str(de.kind) == "electro" and str(de.member_role) == "contact":
				drag_ex.append(id)
	if circuit.has_electro():
		Geom.draw_electro_group_overlays(ci, circuit, font, drag_ex)
	if not sim_live:
		_draw_rail_handles(ci)
	_draw_wire_num_labels(ci, trunk_data, wire_paths)
	if ink_override_on:
		Geom.end_preview_ink()
	_clear_layer_meta(ci)
	_perf_ms_base = float(Time.get_ticks_usec() - t0) * 0.001
	_perf_ms_draw = _perf_ms_base + _perf_ms_live
	_base_draw_busy = false
	if _base_pending_zoom:
		_base_pending_zoom = false
		_request_base("zoom")
	elif _base_pending_sim_control:
		_base_pending_sim_control = false
		_request_base("sim_control")


## Светло-синяя заливка зоны выбора (совпадает с Geom.body_hit / world_bounds).
func _draw_hit_zone(ci: CanvasItem, el) -> void:
	if ci == null or el == null:
		return
	var r: Rect2 = Geom.world_bounds(el)
	if r.size.x < 0.5 or r.size.y < 0.5:
		return
	var fill: Color = Color(0.55, 0.75, 1.0, 0.32) if not UiTheme.dark else Color(0.35, 0.55, 0.95, 0.28)
	var edge: Color = Color(0.35, 0.55, 0.95, 0.85) if not UiTheme.dark else Color(0.55, 0.75, 1.0, 0.75)
	ci.draw_rect(r, fill, true)
	ci.draw_rect(r, edge, false, 1.25)


## Live: hover/selection/резинка; при drag — перетаскиваемые УГО + их провода (vector).
## Подсветка одной параметризуемой части: clip + синие штрихи поверх Base.
func _draw_el_part_ink(ci: CanvasItem, el, font: Font, part_id: String, hover_port: String) -> void:
	if ci == null or el == null or part_id == "":
		return
	var zr: Rect2 = Geom.part_zone_world(el, part_id)
	var rid: RID = ci.get_canvas_item()
	var clipped: bool = zr.size.x > 0.5 and zr.size.y > 0.5
	if clipped:
		RenderingServer.canvas_item_set_custom_rect(rid, true, zr.grow(2.0))
		RenderingServer.canvas_item_set_clip(rid, true)
	Geom.begin_preview_ink(Geom.selection_ink(UiTheme.dark))
	Geom.draw_element(ci, el, font, false, false, hover_port, "", false)
	if UiTheme.dark:
		Geom.begin_preview_ink(UiTheme.preview_ink())
	else:
		Geom.end_preview_ink()
	if clipped:
		RenderingServer.canvas_item_set_clip(rid, false)
		RenderingServer.canvas_item_set_custom_rect(rid, false, Rect2())


func draw_live_layer(ci: CanvasItem) -> void:
	var t0: int = Time.get_ticks_usec()
	_live_draw_busy = true
	_dbg_live_draws += 1
	if circuit == null or ci == null:
		_perf_ms_live = 0.0
		_live_draw_busy = false
		return
	_ensure_wire_paths()
	_bind_layer_meta(ci, 0.0)
	var wire_paths: Array = _cached_wire_paths
	var dragging: bool = (
		(_mode in ["move", "down", "device_table"]) and not _drag_omit_ids.is_empty()
	)
	if _mode == "wire":
		_draw_wire_draft(ci)
	# Провода: при drag — только связанные с переносимыми; иначе hover/selection.
	var hw: int = int(circuit.hover_wire_id)
	var sw: int = int(circuit.selected_wire_id)
	var gw: int = _hover_grip_wire_id()
	for wi in circuit.wires.size():
		var w = circuit.wires[wi]
		var wid: int = int(w.id)
		var linked: bool = false
		if dragging:
			linked = _drag_omit_ids.has(int(w.a_id)) or _drag_omit_ids.has(int(w.b_id))
		var multi_sel: bool = circuit.selected_wire_ids.has(wid)
		if not linked and wid != hw and wid != sw and wid != _bend_wire_id and wid != gw and not multi_sel:
			continue
		var wpath: PackedVector2Array = wire_paths[wi] as PackedVector2Array
		_draw_wire(ci, w, false, false, wpath, 0.0)
	if UiTheme.dark:
		Geom.begin_preview_ink(UiTheme.preview_ink())
	var ids: Dictionary = {}
	if dragging:
		for oid in _drag_omit_ids.keys():
			ids[int(oid)] = true
	else:
		if int(_hover_body_id) >= 0:
			ids[int(_hover_body_id)] = true
		if int(_hover_id) >= 0:
			ids[int(_hover_id)] = true
		if int(_hover_part_id) >= 0:
			ids[int(_hover_part_id)] = true
		for sid in circuit.selected_ids:
			ids[int(sid)] = true
		var ext_hid: int = int(circuit.hover_el_id) if str(circuit.hover_space) != "" else -1
		if ext_hid >= 0:
			ids[ext_hid] = true
	for eid in ids.keys():
		var el = circuit.get_element(int(eid))
		if el == null or ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var hover := (_hover_port if _hover_id == int(el.id) else "")
		var ext: Dictionary = _ext_hover_for_el(el)
		if str(ext.get("port", "")) != "":
			hover = str(ext["port"])
		var selected: bool = circuit.selected_ids.has(el.id)
		var body_hi: bool = int(_hover_body_id) == int(el.id) or bool(ext.get("body", false))
		var hpart := (_hover_part if _hover_part_id == int(el.id) else "")
		# Часть — только она; целое выделение/hover body — все штрихи синим.
		var part_only: bool = hpart != "" and not selected
		# Зона выбора (= world_bounds / body_hit) — светло-синяя заливка при наведении.
		if body_hi and not dragging:
			_draw_hit_zone(ci, el)
		if dragging:
			Geom.begin_preview_ink(Geom.selection_ink(UiTheme.dark))
			Geom.draw_element(ci, el, font, true, false, hover, "", false)
			if UiTheme.dark:
				Geom.begin_preview_ink(UiTheme.preview_ink())
			else:
				Geom.end_preview_ink()
		elif part_only:
			_draw_el_part_ink(ci, el, font, hpart, hover)
		elif selected or body_hi or hover != "":
			Geom.begin_preview_ink(Geom.selection_ink(UiTheme.dark))
			Geom.draw_element(ci, el, font, selected, false, hover, "", false)
			if UiTheme.dark:
				Geom.begin_preview_ink(UiTheme.preview_ink())
			else:
				Geom.end_preview_ink()
	if UiTheme.dark:
		Geom.end_preview_ink()
	_clear_layer_meta(ci)
	_perf_ms_live = float(Time.get_ticks_usec() - t0) * 0.001
	_perf_ms_draw = _perf_ms_base + _perf_ms_live
	_live_last_msec = Time.get_ticks_msec()
	_live_draw_busy = false
	_live_pending = false


func _draw_grid(ci: CanvasItem) -> void:
	# Screen-space на chrome Control: всегда на весь viewport, в ногу с pan/zoom.
	var a := _screen_to_world(Vector2.ZERO)
	var b := _screen_to_world(size)
	var step := Geom.SCH_GRID
	var major_every := int(step * 5.0)
	var draw_minor: bool = zoom >= 0.55
	var x0: float = floorf(minf(a.x, b.x) / step) * step
	var x1: float = maxf(a.x, b.x)
	var y0: float = floorf(minf(a.y, b.y) / step) * step
	var y1: float = maxf(a.y, b.y)
	var base := UiTheme.schematic_grid()
	var minor := base
	minor.a = minf(base.a * 0.75, 1.0)
	var major := base.darkened(0.08 if not UiTheme.dark else 0.0).lightened(0.0 if not UiTheme.dark else 0.12)
	major.a = minf(base.a + 0.2, 1.0)
	var z: float = maxf(zoom, 0.05)
	var x: float = x0
	while x <= x1 + step * 0.01:
		var is_major: bool = int(round(absf(x))) % major_every == 0
		if is_major or draw_minor:
			var sx: float = pan.x + x * z
			ci.draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), major if is_major else minor, 1.15 if is_major else 1.0, false)
		x += step
	var y: float = y0
	while y <= y1 + step * 0.01:
		var is_major_y: bool = int(round(absf(y))) % major_every == 0
		if is_major_y or draw_minor:
			var sy: float = pan.y + y * z
			ci.draw_line(Vector2(0.0, sy), Vector2(size.x, sy), major if is_major_y else minor, 1.15 if is_major_y else 1.0, false)
		y += step


func _draw_atm_exhausts(ci: CanvasItem) -> void:
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	const ATM_DEAD := 1.0e-6
	for el in circuit.elements:
		if el == null:
			continue
		if str(el.kind) in ["electro", "coil", "rail"]:
			continue
		# Глушители ПР скрыты из Geom.ports (не точка проводки) — берём отдельно.
		var port_list: Array = []
		if str(el.kind) == "valve":
			port_list = Geom.valve_atm_exhaust_ports(el)
			for p0 in Geom.ports(el):
				port_list.append(p0)
		else:
			port_list = Geom.ports(el)
		for port in port_list:
			var pname: String = str(port["name"])
			if Geom.port_domain(el, pname) == "electric":
				continue
			if circuit.wire_on(int(el.id), pname) != null:
				continue
			var q: float = circuit.open_port_viz_q(el, pname)
			if absf(q) < ATM_DEAD:
				continue
			# Только выброс наружу (подсос в открытый штуцер не рисуем как «выхлоп»).
			if q > -ATM_DEAD:
				continue
			var tip: Vector2 = Geom.to_world(el, port["local"])
			var nrm: Vector2 = (port["normal"] as Vector2).rotated(float(el.rotation_quad) * PI * 0.5)
			if nrm.length_squared() < 1.0e-8:
				nrm = Vector2.RIGHT
			else:
				nrm = nrm.normalized()
			var outward: Vector2 = nrm
			var n_dots: int = maxi(SimV.puff_count(absf(q)), 3)
			var span: float = 42.0
			var phase: float = fposmod(float(circuit.sim_time) * 1.1, 1.0)
			for k in n_dots:
				var u: float = fposmod((float(k) + 0.35) / float(n_dots) + phase, 1.0)
				var d: float = 6.0 + u * span
				var p: Vector2 = tip + outward * d
				var a: float = clampf(1.0 - u, 0.35, 0.95)
				var col := Color(0.15, 0.62, 0.86, a)
				ci.draw_circle(p, 3.6 / zoom, col)
		if str(el.kind) == "accessory" and str(el.accessory_class) in ["regulator", "frl"]:
			if circuit.regulator_relief_active(int(el.id)):
				_draw_regulator_relief_dots(ci, el)


func _draw_regulator_relief_dots(ci: CanvasItem, el) -> void:
	var exh: Dictionary = Geom.regulator_relief_exhaust_local()
	var tip: Vector2 = Geom.to_world(el, exh["tip"] as Vector2)
	var outward: Vector2 = (exh["dir"] as Vector2).rotated(float(el.rotation_quad) * PI * 0.5).normalized()
	var trail: float = float(circuit.relief_trail_s.get(int(el.id), 0.0))
	var n_dots: int = 4 if trail > 0.2 else 3
	var span: float = 42.0
	var phase: float = fposmod(float(circuit.sim_time) * 1.1, 1.0)
	for k in n_dots:
		var u: float = fposmod((float(k) + 0.35) / float(n_dots) + phase, 1.0)
		var d: float = 6.0 + u * span
		var p: Vector2 = tip + outward * d
		var a: float = clampf(1.0 - u, 0.35, 0.95)
		ci.draw_circle(p, 3.6 / zoom, Color(0.15, 0.62, 0.86, a))


## World-ширина линии с полом по экранным px — на zoom-out не уходит в субпиксель.
func _sch_line_world_w(world_w: float, min_screen_px: float = -1.0) -> float:
	var floor_px: float = min_screen_px
	if floor_px < 0.0:
		floor_px = Geom.SCH_STROKE_MIN_PX
	var z: float = maxf(zoom, 0.05)
	return maxf(world_w, floor_px / z)


func _draw_wire_trunks(ci: CanvasItem, trunk_data: Dictionary) -> void:
	var ink := Color(0.92, 0.94, 0.97, 1.0) if UiTheme.dark else Color(0.08, 0.10, 0.14, 1.0)
	var trunks: Array = trunk_data.get("trunks", []) as Array
	var w_px: float = _sch_line_world_w(2.4)
	for tr in trunks:
		var pts: PackedVector2Array = tr.get("pts", PackedVector2Array()) as PackedVector2Array
		if pts.size() < 2:
			continue
		ci.draw_polyline(pts, ink, w_px, false)


func _draw_wire_num_labels(ci: CanvasItem, trunk_data: Dictionary, wire_paths: Array = []) -> void:
	if font == null or ci == null:
		return
	var labels: Array = []
	for item in trunk_data.get("end_labels", []) as Array:
		labels.append(item)
	for item in trunk_data.get("join_labels", []) as Array:
		labels.append(item)
	if labels.is_empty():
		return
	# SchemeWorld.scale=zoom → компенсируем, растеризация в экранных px (без блюра).
	var z: float = maxf(zoom, 0.05)
	# Один размер для всех номеров жил (обрыв и середина).
	var fs_mid: int = clampi(int(round(13.0 * z)), 10, 20)
	var fs_break: int = fs_mid
	var ink_def: Color = UiTheme.schematic_label()
	var ink_sel: Color = Color(0.10, 0.38, 0.82) if not UiTheme.dark else Color(0.45, 0.72, 1.0)
	var halo: Color = UiTheme.schematic_label_halo()
	Geom._begin_world_crisp_text(ci, z)
	for item in labels:
		var num: int = int(item.get("num", 0))
		if num <= 0:
			continue
		var is_break: bool = bool(item.get("break", false))
		var fs: int = fs_break if is_break else fs_mid
		var world: Vector2 = item.get("pos", Vector2.ZERO) as Vector2
		var txt: String = str(num)
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ascent: float = font.get_ascent(fs) * 0.35
		var origin: Vector2 = world * z - Vector2(tw * 0.5, -ascent)
		var wid: int = int(item.get("wire_id", -1))
		var ink: Color = ink_sel if (circuit != null and (
			wid == int(circuit.selected_wire_id) or circuit.selected_wire_ids.has(wid)
		)) else ink_def
		if not UiTheme.dark:
			ci.draw_string(font, origin + Vector2(1, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
			ci.draw_string(font, origin + Vector2(-1, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
			ci.draw_string(font, origin + Vector2(0, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, origin, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	Geom._end_world_crisp_text(ci)


func _label_hits_wires(world: Vector2, wire_paths: Array, min_dist: float) -> bool:
	for path_v in wire_paths:
		var pts: PackedVector2Array = path_v as PackedVector2Array
		for i in range(pts.size() - 1):
			if _dist_point_seg(world, pts[i], pts[i + 1]) < min_dist:
				return true
	return false


func _label_hits_elements(world: Vector2, rects: Array) -> bool:
	for r in rects:
		if (r as Rect2).has_point(world):
			return true
	return false


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var L2: float = ab.length_squared()
	if L2 < 1.0e-8:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / L2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _wire_is_selected(wire) -> bool:
	if wire == null or circuit == null:
		return false
	var wid: int = int(wire.id)
	if wid == int(circuit.selected_wire_id) or wid == _bend_wire_id:
		return true
	return circuit.selected_wire_ids.has(wid)


func _draw_wire(ci: CanvasItem, wire, _show_values: bool, sim_viz: bool, pts: PackedVector2Array = PackedVector2Array(), p_max_over: float = 0.0) -> void:
	var a = circuit.get_element(wire.a_id)
	var b = circuit.get_element(wire.b_id)
	if a == null or b == null or ci == null:
		return
	var domain: String = Geom.port_domain(a, str(wire.a_port))
	# Оптокабели — только 3D; на схеме не рисуем (наконечники скрыты).
	if domain == "optic":
		return
	if pts.size() < 2:
		pts = _wire_path(wire)
	if pts.size() < 2:
		return
	var is_elec: bool = domain == "electric"
	var cut_2d: bool = is_elec and WireBreak2D.is_schematic_cut(wire)
	# Не уводить конец жилы tip−normal внутрь УГО (LEAD рисует само УГО).
	var parts: Array
	if cut_2d:
		parts = WireBreak2D.visual_parts(circuit, wire, pts)
	else:
		if is_elec:
			circuit.heal_wire_rail_skips(wire, pts)
		var skip_ids: Array = circuit.wire_rail_skip_ids(wire) if is_elec else []
		var vis: Dictionary = Rail2D.visual_for_path(circuit, domain, pts, skip_ids)
		parts = vis.get("parts", [pts]) as Array
	var selected: bool = _wire_is_selected(wire)
	var hovered: bool = circuit != null and int(circuit.hover_wire_id) == int(wire.id)
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	# 2D схема: монохром (как AS) — цвет изоляции только в 3D/свойствах, иначе путается с selection.
	var ink := Color(0.92, 0.93, 0.95) if UiTheme.dark else Color(0.06, 0.07, 0.09)
	var col := ink
	if sim_viz and not is_elec:
		var base_line := Color(0.78, 0.80, 0.82) if not UiTheme.dark else Color(0.55, 0.58, 0.62)
		col = SimV.pressure_color_2d(circuit.wire_viz_pressure(wire), base_line, p_max_over)
	if selected:
		col = Color(0.45, 0.72, 1.0) if UiTheme.dark else Color(0.10, 0.38, 0.82)
	elif hovered:
		col = Color(1.0, 0.78, 0.22) if UiTheme.dark else Color(0.80, 0.48, 0.05)
	# World-толщина + пол ≥1.5 screen px (zoom-out без пропадания). Без потолка / без утолщения hover.
	var thick: float = 1.7
	if is_elec:
		thick = clampf(1.35 + sqrt(maxf(float(wire.id_mm), 0.5)) * 0.35, 1.4, 2.4)
	else:
		var od_vis: float = float(wire.od_mm)
		if od_vis < 1.0:
			od_vis = float(wire.id_mm)
		thick = clampf(1.15 + od_vis * 0.18, 1.5, 3.2)
		if sim_viz:
			thick *= 1.15
	var w_px: float = _sch_line_world_w(thick)
	for part_v in parts:
		var part: PackedVector2Array = part_v as PackedVector2Array
		if part.size() < 2:
			continue
		ci.draw_polyline(part, col, w_px, false)
	# Ручки: все — на выделенной жиле; под курсором якорь — янтарь.
	if not cut_2d and (selected or (_mode == "bend" and _bend_wire_id == int(wire.id))):
		_draw_wire_handles(ci, wire, pts, parts)
	if cut_2d:
		_draw_break_arrows(ci, wire, pts, col)


## ГОСТ 2.721 п.35: стрелка = «минус» + «больше/меньше» (−> / <−); номер — за стрелкой.
## Размер в world: длина ≈ 1 клетка, ширина головки = 0.5 клетки; без зазора от конца жилы.
## Выделение: оба конца (стрелки + маркер), даже если курсор у одного хвоста.
func _draw_break_arrows(ci: CanvasItem, wire, pts: PackedVector2Array, col: Color) -> void:
	if ci == null or wire == null:
		return
	var g: float = Geom.SCH_GRID
	var shaft: float = g * 0.5
	var head: float = g * 0.5
	var half_a: float = deg_to_rad(30.0) # ширина головки ≈ 2·head·sin(30°) = 0.5·g
	var selected: bool = _wire_is_selected(wire)
	var lw: float = _sch_line_world_w(2.15 if selected else 1.55)
	var mark_r: float = clampf(4.0 / maxf(zoom, 0.25), 2.5, 8.0)
	for at_start in [true, false]:
		var tip: Dictionary = WireBreak2D.break_tip(circuit, wire, at_start, pts)
		if tip.is_empty():
			continue
		var p: Vector2 = tip["pos"] as Vector2
		var d: Vector2 = tip["dir"] as Vector2
		# Стык со stub без зазора — стрелка продолжает линию.
		var p0: Vector2 = p
		var p1: Vector2 = p + d * shaft
		ci.draw_line(p0, p1, col, lw, false)
		var back: Vector2 = -d
		var left: Vector2 = p1 + back.rotated(half_a) * head
		var right: Vector2 = p1 + back.rotated(-half_a) * head
		ci.draw_line(p1, left, col, lw, false)
		ci.draw_line(p1, right, col, lw, false)
		if selected:
			ci.draw_circle(p, mark_r, col)
			ci.draw_arc(p, mark_r, 0.0, TAU, 16, Color(1, 1, 1, 0.85), 1.0 / maxf(zoom, 0.35), true)


func _grip_hover_on_wire(wire) -> bool:
	if wire == null or _hover_grip_key == "":
		return false
	return _hover_grip_key.begins_with("%d:" % int(wire.id))


func _hover_grip_wire_id() -> int:
	if _hover_grip_key == "":
		return -1
	var colon: int = _hover_grip_key.find(":")
	if colon <= 0:
		return -1
	return int(_hover_grip_key.substr(0, colon))


## Все якоря выделенной жилы; под курсором — янтарь.
func _draw_wire_handles(ci: CanvasItem, wire, pts: PackedVector2Array, parts: Array) -> void:
	var ink := Color(0.12, 0.42, 0.78)
	var hot_fill := Color(1.0, 0.78, 0.18)
	var hot_ink := Color(0.75, 0.42, 0.02)
	var r: float = clampf(5.5 / maxf(zoom, 0.2), 3.5, 12.0)
	var mid_r: float = r * 0.65 * (4.0 / 3.0)
	var wid: int = int(wire.id) if wire != null else -1
	for h in _wire_corner_handles(wire, pts):
		var idx: int = int(h.get("index", -1))
		var key: String = "%d:point:%d" % [wid, idx]
		var hot: bool = key == _hover_grip_key
		var p: Vector2 = h["pos"] as Vector2
		var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		if hot:
			ci.draw_rect(box.grow(1.5 / maxf(zoom, 0.2)), hot_fill, true)
			ci.draw_rect(box, hot_ink, false, maxf(1.4 / zoom, 0.1))
		else:
			ci.draw_rect(box, Color(0.98, 0.99, 1.0), true)
			ci.draw_rect(box, ink, false, maxf(1.0 / zoom, 0.08))
	for part_v in parts:
		var part: PackedVector2Array = part_v as PackedVector2Array
		for i in range(part.size() - 1):
			if part[i].distance_to(part[i + 1]) < 14.0:
				continue
			var mid_pt: Vector2 = (part[i] + part[i + 1]) * 0.5
			var seg_i: int = _path_seg_index_near(pts, mid_pt)
			var seg_key: String = "%d:seg:%d" % [wid, seg_i]
			var hot_m: bool = seg_key == _hover_grip_key
			if hot_m:
				ci.draw_circle(mid_pt, mid_r * 1.35, hot_fill)
				ci.draw_arc(mid_pt, mid_r * 1.35, 0.0, TAU, 16, hot_ink, maxf(1.2 / zoom, 0.1), true)
			else:
				ci.draw_circle(mid_pt, mid_r, ink)


func _draw_handles(ci: CanvasItem, pts: PackedVector2Array) -> void:
	# Совместимость: углы по полному пути (без rail-parts).
	var ink := Color(0.12, 0.42, 0.78)
	var r: float = clampf(5.5 / maxf(zoom, 0.2), 3.5, 12.0)
	var mid_r: float = r * 0.65 * (4.0 / 3.0)
	for i in range(1, pts.size() - 1):
		var incoming_h := absf(pts[i].y - pts[i - 1].y) <= absf(pts[i].x - pts[i - 1].x)
		var outgoing_h := absf(pts[i + 1].y - pts[i].y) <= absf(pts[i + 1].x - pts[i].x)
		if incoming_h == outgoing_h:
			continue
		var box := Rect2(pts[i] - Vector2(r, r), Vector2(r, r) * 2.0)
		ci.draw_rect(box, Color(0.98, 0.99, 1.0), true)
		ci.draw_rect(box, ink, false, maxf(1.0 / zoom, 0.08))
	for i in range(pts.size() - 1):
		if pts[i].distance_to(pts[i + 1]) < 14.0:
			continue
		ci.draw_circle((pts[i] + pts[i + 1]) * 0.5, mid_r, ink)


## Поток на трубке: статичные шевроны по центру (1…3 по |Q|). Только на линии, не на УГО.
func _draw_wire_flow_marks(ci: CanvasItem, wire, pts: PackedVector2Array) -> void:
	if wire == null or pts.size() < 2 or circuit == null or ci == null:
		return
	var ea = circuit.get_element(int(wire.a_id))
	if ea == null or Geom.port_domain(ea, str(wire.a_port)) == "electric":
		return
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var thresh: float = SimV.FLOW_DEAD
	var q: float = float(wire.flow_vis)
	if absf(q) < thresh:
		q = float(wire.flow_m3s)
	if absf(q) < thresh:
		return
	_draw_flow_chevrons(ci, pts, q)


## Статичный кластер ▶ / ▶▶ / ▶▶▶ на самом длинном прямом сегменте трубки.
func _draw_flow_chevrons(ci: CanvasItem, pts: PackedVector2Array, flow: float) -> void:
	if pts.size() < 2 or ci == null:
		return
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var qabs: float = absf(flow)
	var n: int = SimV.chevron_count(qabs)
	if n <= 0:
		return
	var flow_s: float = signf(flow)
	if flow_s == 0.0:
		return
	var ab: Vector2 = pts[pts.size() - 1] - pts[0]
	if ab.length_squared() < 1.0:
		return
	var best_a: Vector2 = pts[0]
	var best_b: Vector2 = pts[1]
	var best_len: float = -1.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: Vector2 = b - a
		var slen: float = seg.length()
		if slen < 8.0:
			continue
		if seg.dot(ab) < 0.0:
			continue
		if slen > best_len:
			best_len = slen
			best_a = a
			best_b = b
	if best_len < 8.0:
		return
	var tang: Vector2 = (best_b - best_a).normalized() * flow_s
	var center: Vector2 = best_a.lerp(best_b, 0.5)
	var gap: float = 13.5
	var origin: Vector2 = center - tang * gap * 0.5 * float(n - 1)
	for k in n:
		_draw_flow_chevron(ci, origin + tang * gap * float(k), tang)


func _draw_flow_chevron(ci: CanvasItem, at: Vector2, tang: Vector2) -> void:
	if tang.length_squared() < 1.0e-8 or ci == null:
		return
	var t: Vector2 = tang.normalized()
	var r: float = 4.65
	var tip: Vector2 = at + t * r
	var back: Vector2 = at - t * r * 0.62
	var side: Vector2 = Vector2(-t.y, t.x) * 7.26
	var tri := PackedVector2Array([tip, back + side, back - side])
	ci.draw_colored_polygon(tri, Color(0.10, 0.38, 0.88, 1.0))


func _poly_len(pts: PackedVector2Array) -> float:
	return Geom.path_length_px(pts)


func _point_at(pts: PackedVector2Array, dist: float) -> Vector2:
	var left := dist
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			var t := 0.0 if seg < 0.001 else clampf(left / seg, 0.0, 1.0)
			return pts[i].lerp(pts[i + 1], t)
		left -= seg
	return pts[pts.size() - 1]
