extends PanelContainer

signal item_chosen(kind: String)
signal drag_started(kind: String)
signal filter_changed(query: String, fav_only: bool)
signal favorites_changed()

const ValveLib = preload("res://scripts/domain/valve_library.gd")
const CylLib = preload("res://scripts/domain/cylinder_library.gd")
const RotaryLib = preload("res://scripts/domain/rotary_library.gd")
const MotorLib = preload("res://scripts/domain/motor_library.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const AccLib = preload("res://scripts/domain/accessory_library.gd")
const SensorLib = preload("res://scripts/domain/sensor_library.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")
const ThumbBakerScript = preload("res://scripts/ui/library_thumb_baker.gd")
const SymbolBakerScript = preload("res://scripts/ui/library_symbol_baker.gd")
const FAV_PATH := "user://library_favorites.json"

var font: Font
var _favorites: Dictionary = {} # kind -> true
var _fav_only := false
var _query := ""
var _collapsed: Dictionary = {} # section_id -> collapsed
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _pad: MarginContainer
var _search: LineEdit
var _fav_btn: Button
var _title: Label
var _note: Label
var _row_down := {}
var _row_sent := {}
var _heading_title := "Библиотека"
var _heading_note := ""
var _preview_mode := "symbol" # symbol | model3d
var _thumb_baker: Node
var _symbol_baker: Node
var _thumb_targets: Dictionary = {} # kind -> Array[TextureRect]
var _symbol_targets: Dictionary = {} # kind -> Array[SymbolPreview]
var _content_ready := false


func _ready() -> void:
	_load_favorites()
	# Ширину задаёт слот в main_shell (HBox). Здесь только clip + мягкий min для лейблов.
	custom_minimum_size = Vector2(0, 0)
	clip_contents = true
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	_title = Label.new()
	_title.text = _heading_title
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(120, 0)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_title)

	_search = LineEdit.new()
	_search.placeholder_text = "Поиск…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(120, 0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(t: String):
		_query = t.strip_edges().to_lower()
		if _content_ready:
			_rebuild()
		filter_changed.emit(_query, _fav_only)
	)
	root.add_child(_search)

	_fav_btn = Button.new()
	_fav_btn.toggle_mode = true
	_fav_btn.focus_mode = Control.FOCUS_NONE
	_fav_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fav_btn.toggled.connect(func(on: bool):
		_fav_only = on
		_update_fav_btn()
		if _content_ready:
			_rebuild()
		filter_changed.emit(_query, _fav_only)
	)
	root.add_child(_fav_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var scroll_panel := StyleBoxFlat.new()
	scroll_panel.bg_color = Color(0, 0, 0, 0)
	scroll_panel.set_content_margin_all(0)
	_scroll.add_theme_stylebox_override("panel", scroll_panel)
	root.add_child(_scroll)

	_pad = MarginContainer.new()
	_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad.add_theme_constant_override("margin_right", 8)
	_scroll.add_child(_pad)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pad.add_child(_list_box)
	_scroll.resized.connect(_sync_list_width)

	_note = Label.new()
	_note.visible = false
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(120, 0)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.add_theme_font_size_override("font_size", 12)
	root.add_child(_note)

	apply_ui_theme()
	# Список заполняем явно через populate() — под splash.
	call_deferred("_sync_list_width")


func _collapse_all_sections() -> void:
	## При загрузке все каталоги свёрнуты — раскрывает пользователь.
	for id in ["pneumo", "pneumo_source", "fittings", "cylinders", "valves", "electro", "sensors"]:
		_collapsed[id] = true
	for ways in [2, 3, 4, 5]:
		_collapsed["valve_%d" % ways] = true
	for cat in CylLib.CATEGORY_ORDER:
		_collapsed["cyl_%s" % cat] = true
	for cat in ElectroLib.CATEGORY_ORDER:
		_collapsed["electro_%s" % cat] = true
	for cat in SensorLib.CATEGORY_ORDER:
		_collapsed["sensor_%s" % cat] = true


func populate() -> void:
	_content_ready = true
	_collapse_all_sections()
	if _list_box == null:
		push_warning("LibraryPanel.populate: list not ready")
		return
	_rebuild()


func populate_stepped(on_step: Callable = Callable()) -> void:
	## Строит список по одному элементу за кадр — без фриза на splash.
	_content_ready = true
	_collapse_all_sections()
	if _list_box == null:
		return
	_thumb_targets.clear()
	_symbol_targets.clear()
	var old := _list_box.get_children()
	for child in old:
		_list_box.remove_child(child)
		child.queue_free()
	if not await _await_lib_frame():
		return
	if on_step.is_valid():
		on_step.call(0, 1)
	if not await _await_lib_frame():
		return
	var entries := _catalog_entries()
	if not await _await_lib_frame():
		return
	var steps: Array = []
	steps.append({"title": "Пневматика", "id": "pneumo", "items": [], "depth": 0, "header_only": true})
	steps.append({"title": "Электрика", "id": "electro", "items": [], "depth": 0, "header_only": true})
	var item_total := 0
	for step in steps:
		item_total += 1
		if not bool(step.get("header_only", false)):
			item_total += (step["items"] as Array).size()
	item_total = maxi(item_total, 1)
	var done := 0
	for step in steps:
		_list_box.add_child(_section_header(str(step["id"]), str(step["title"]), int(step["depth"])))
		done += 1
		if on_step.is_valid():
			on_step.call(done, item_total)
		if not await _await_lib_frame():
			return
		if bool(step.get("header_only", false)) or bool(_collapsed.get(str(step["id"]), true)):
			continue
		for e in step["items"]:
			_list_box.add_child(_item_row(e))
			done += 1
			if on_step.is_valid():
				on_step.call(done, item_total)
			# Два idle — splash успевает перерисоваться между строками.
			if not await _await_lib_frame():
				return
			if not await _await_lib_frame():
				return
	call_deferred("_sync_list_width")


func _await_lib_frame() -> bool:
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	await tree.process_frame
	return is_instance_valid(self) and is_inside_tree()


func list_item_count() -> int:
	return _list_box.get_child_count() if _list_box != null else 0


func start_preview_baking() -> void:
	## SubViewport/печку поднимаем только здесь — не во время populate списка.
	if _preview_mode == "model3d":
		_ensure_thumb_baker()
		if _thumb_baker != null and _thumb_baker.has_method("set_active"):
			_thumb_baker.set_active(true)
		_enqueue_kinds(_thumb_targets.keys())
	else:
		_ensure_symbol_baker()
		if _symbol_baker != null and _symbol_baker.has_method("set_active"):
			_symbol_baker.set_active(true)
		_enqueue_kinds(_symbol_targets.keys())


func enqueue_all_catalog_previews() -> void:
	## Все kind из каталога — в т.ч. свёрнутые секции (полная предзагрузка).
	var kinds: Array = []
	for e in _catalog_entries():
		kinds.append(str(e.get("kind", "")))
	if _preview_mode == "model3d":
		_ensure_thumb_baker()
		if _thumb_baker != null and _thumb_baker.has_method("set_active"):
			_thumb_baker.set_active(true)
	else:
		_ensure_symbol_baker()
		if _symbol_baker != null and _symbol_baker.has_method("set_active"):
			_symbol_baker.set_active(true)
	_enqueue_kinds(kinds)


func warm_previews() -> void:
	## Дождаться опустошения очереди печки.
	var baker: Node = _thumb_baker if _preview_mode == "model3d" else _symbol_baker
	if baker != null and baker.has_method("warm_queue"):
		await baker.warm_queue()


func warm_previews_stepped(on_step: Callable) -> void:
	## Явные шаги bake: статус → idle → один kind → idle (без гонки с _process).
	var baker: Node = _thumb_baker if _preview_mode == "model3d" else _symbol_baker
	if baker == null or not is_instance_valid(baker):
		return
	if baker.has_method("set_active"):
		baker.set_active(false)
	var total := 0
	if baker.has_method("cache_size"):
		total += int(baker.cache_size())
	if baker.has_method("pending_total"):
		total += int(baker.pending_total())
	total = maxi(total, 1)
	while baker.has_method("has_work") and baker.has_work():
		var done := int(baker.cache_size()) if baker.has_method("cache_size") else 0
		if on_step.is_valid():
			on_step.call(done, total)
		# Кадр на splash до тяжёлого draw.
		if not await _await_lib_frame():
			return
		if baker.has_method("bake_next"):
			await baker.bake_next()
		elif baker.has_method("set_active"):
			baker.set_active(true)
			if not await _await_lib_frame():
				return
			baker.set_active(false)
		# Кадр на splash после bake.
		if not await _await_lib_frame():
			return
	var final_done := int(baker.cache_size()) if baker.has_method("cache_size") else total
	if on_step.is_valid():
		on_step.call(final_done, total)
	if baker.has_method("set_active"):
		baker.set_active(true)
	if not await _await_lib_frame():
		return


func preview_cache_count() -> int:
	var baker: Node = _thumb_baker if _preview_mode == "model3d" else _symbol_baker
	if baker == null or not is_instance_valid(baker):
		return 0
	if baker.has_method("cache_size"):
		return int(baker.cache_size())
	return 0


func _enqueue_kinds(kinds: Array) -> void:
	for k in kinds:
		var kind := str(k)
		if kind == "":
			continue
		if _preview_mode == "model3d":
			if _thumb_baker == null:
				continue
			var cached: Texture2D = _thumb_baker.get_cached(kind) if _thumb_baker.has_method("get_cached") else null
			if cached != null:
				_on_thumb_ready(kind, cached)
			elif _thumb_baker.has_method("request"):
				_thumb_baker.request(kind)
		else:
			if _symbol_baker == null:
				continue
			var cached2: Texture2D = _symbol_baker.get_cached(kind) if _symbol_baker.has_method("get_cached") else null
			if cached2 != null:
				_on_symbol_ready(kind, cached2)
			elif _symbol_baker.has_method("request"):
				_symbol_baker.request(kind)


func set_heading(title: String, note: String = "") -> void:
	_heading_title = title
	_heading_note = note
	if _title:
		_title.text = _heading_title
	if _note:
		# Поясняющие подписи под библиотекой отключены.
		_note.visible = false
		_note.text = ""


func set_preview_mode(mode: String) -> void:
	var next := "model3d" if mode == "model3d" else "symbol"
	if _preview_mode == next:
		return
	_preview_mode = next
	if _content_ready and is_inside_tree() and _list_box != null:
		_rebuild()


func _ensure_thumb_baker() -> void:
	if _thumb_baker != null and is_instance_valid(_thumb_baker):
		return
	if not is_inside_tree():
		return
	_thumb_baker = ThumbBakerScript.new()
	_thumb_baker.name = "ThumbBaker"
	# Держим на current_scene — переживает reparent HSplit.
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_thumb_baker)
	_thumb_baker.thumb_ready.connect(_on_thumb_ready)


func _ensure_symbol_baker() -> void:
	if _symbol_baker != null and is_instance_valid(_symbol_baker):
		return
	if not is_inside_tree():
		return
	_symbol_baker = SymbolBakerScript.new()
	_symbol_baker.name = "SymbolBaker"
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_symbol_baker)
	_symbol_baker.thumb_ready.connect(_on_symbol_ready)


func _on_symbol_ready(kind: String, texture: Texture2D) -> void:
	var targets: Array = _symbol_targets.get(kind, [])
	for sp in targets:
		if sp != null and is_instance_valid(sp) and sp.has_method("set_texture"):
			sp.set_texture(texture)


func _bind_symbol(kind: String, sp: Control) -> void:
	if not _symbol_targets.has(kind):
		_symbol_targets[kind] = []
	(_symbol_targets[kind] as Array).append(sp)
	# Печку не создаём здесь — только после start_preview_baking().
	if _symbol_baker == null or not is_instance_valid(_symbol_baker):
		return
	var cached: Texture2D = _symbol_baker.get_cached(kind) if _symbol_baker.has_method("get_cached") else null
	if cached != null and sp.has_method("set_texture"):
		sp.set_texture(cached)
	elif _symbol_baker.has_method("is_active") and _symbol_baker.is_active() and _symbol_baker.has_method("request"):
		_symbol_baker.request(kind)


func warm_visible_previews() -> void:
	## Ждёт отрисовки всех запрошенных 3D-миниатюр (один общий viewport).
	if _preview_mode != "model3d":
		return
	_ensure_thumb_baker()
	if _thumb_baker != null and _thumb_baker.has_method("warm_queue"):
		await _thumb_baker.warm_queue()


func _on_thumb_ready(kind: String, texture: Texture2D) -> void:
	var targets: Array = _thumb_targets.get(kind, [])
	for tr in targets:
		if tr is TextureRect and is_instance_valid(tr):
			(tr as TextureRect).texture = texture


func _bind_thumb(kind: String, tr: TextureRect) -> void:
	if not _thumb_targets.has(kind):
		_thumb_targets[kind] = []
	(_thumb_targets[kind] as Array).append(tr)
	# Запросы — в start_preview_baking(); здесь cache hit / дозапрос если печка уже активна.
	if _thumb_baker == null or not is_instance_valid(_thumb_baker):
		return
	var cached: Texture2D = _thumb_baker.get_cached(kind) if _thumb_baker.has_method("get_cached") else null
	if cached != null:
		tr.texture = cached
	elif _thumb_baker.has_method("is_active") and _thumb_baker.is_active() and _thumb_baker.has_method("request"):
		_thumb_baker.request(kind)


func _sync_list_width() -> void:
	## ScrollContainer сам не растягивает ребёнка — задаём ширину списка = ширина скролла.
	## Слот библиотеки уже ограничен max-width, наружу не раздуемся.
	if _scroll == null or _pad == null or _list_box == null:
		return
	var w := _scroll.size.x
	if w < 8.0:
		return
	_pad.custom_minimum_size.x = w
	_list_box.custom_minimum_size.x = maxf(w - 8.0, 0.0)
	_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func get_query() -> String:
	return _query


func get_fav_only() -> bool:
	return _fav_only


func apply_filter(query: String, fav_only: bool) -> void:
	if _query == query and _fav_only == fav_only:
		return
	_query = query
	_fav_only = fav_only
	if _search != null and _search.text != query:
		_search.set_block_signals(true)
		_search.text = query
		_search.set_block_signals(false)
	if _fav_btn != null:
		_fav_btn.set_pressed_no_signal(_fav_only)
	_update_fav_btn()
	if _content_ready:
		_rebuild()


func reload_favorites() -> void:
	_load_favorites()
	if _content_ready:
		_rebuild()


func apply_ui_theme() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = UiTheme.panel_bg()
	add_theme_stylebox_override("panel", panel)
	if _title:
		_title.add_theme_color_override("font_color", UiTheme.text())
	if _note:
		_note.add_theme_color_override("font_color", UiTheme.muted())
	if _search:
		_search.add_theme_color_override("font_color", UiTheme.text())
		_search.add_theme_color_override("font_placeholder_color", UiTheme.muted())
	_update_fav_btn()
	if is_inside_tree() and _list_box != null and _content_ready:
		_rebuild()


func _update_fav_btn() -> void:
	if _fav_btn == null:
		return
	_fav_btn.text = "★ Избранные" if _fav_only else "☆ Избранные"
	_fav_btn.tooltip_text = ""
	var bg: Color = UiTheme.accent() if _fav_only else UiTheme.neutral_btn()
	_fav_btn.add_theme_stylebox_override("normal", _fav_flat(bg))
	_fav_btn.add_theme_stylebox_override("hover", _fav_flat(bg.lightened(0.12)))
	_fav_btn.add_theme_stylebox_override("pressed", _fav_flat(bg.darkened(0.08)))
	_fav_btn.add_theme_stylebox_override("hover_pressed", _fav_flat(bg.lightened(0.08)))
	_fav_btn.add_theme_stylebox_override("focus", _fav_flat(bg))
	var fg := Color(0.97, 0.98, 0.99)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_fav_btn.add_theme_color_override(key, fg)


func _fav_flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _rebuild() -> void:
	if _list_box == null:
		return
	_thumb_targets.clear()
	_symbol_targets.clear()
	# Сразу снимаем детей: queue_free без remove_child в 4.7 иногда сносит и новые строки.
	var old := _list_box.get_children()
	for child in old:
		_list_box.remove_child(child)
		child.queue_free()
	var entries := _catalog_entries()
	if _fav_only:
		var any := false
		for e in entries:
			if _favorites.get(str(e["kind"]), false) and _matches(e):
				_list_box.add_child(_item_row(e))
				any = true
		if not any:
			_list_box.add_child(_hint("Нет избранных по текущему поиску"))
		call_deferred("_sync_list_width")
		return

	# Пневматика → источник, фитинги, ПЦ, ПР
	var pneumo_items: Array = []
	for e in entries:
		if str(e["group"]) == "pneumo" and _matches(e):
			pneumo_items.append(e)
	var fittings: Array = []
	for e in entries:
		if str(e["group"]) == "fittings" and _matches(e):
			fittings.append(e)
	var rail_p: Array = []
	for e in entries:
		if str(e["group"]) == "rail_pneumo" and _matches(e):
			rail_p.append(e)
	var pneumo_subs: Array = [
		{"id": "pneumo_source", "title": "Источник", "items": pneumo_items},
		{"id": "fittings", "title": "Фитинги / ветвление", "items": fittings},
	]
	if not rail_p.is_empty():
		pneumo_subs.append({"id": "rail_pneumo", "title": "Шина", "items": rail_p})
	pneumo_subs.append({"id": "accessories", "title": "Аксессуары", "items": [], "children": _accessory_children(entries)})
	pneumo_subs.append({"id": "cylinders", "title": "Пневмоцилиндры", "items": [], "children": _cylinder_children(entries)})
	pneumo_subs.append({"id": "rotary", "title": "Поворотные ПЦ", "items": [], "children": _rotary_children(entries)})
	pneumo_subs.append({"id": "motors", "title": "Пневмомоторы", "items": [], "children": _motor_children(entries)})
	pneumo_subs.append({"id": "valves", "title": "Распределители", "items": [], "children": _valve_children(entries)})
	_add_nested_catalog("pneumo", "Пневматика", pneumo_subs, 0)

	# Датчики → proximity / process / …
	_add_nested_catalog(
		"sensors",
		"Датчики",
		_sensor_children(entries),
		0,
	)

	# Электрика → подкаталоги по category рецептов
	_add_nested_catalog(
		"electro",
		"Электрика",
		_electro_children(entries),
		0,
	)
	call_deferred("_sync_list_width")


func _cylinder_children(entries: Array) -> Array:
	var out: Array = []
	for cat in CylLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "cylinder" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(CylLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "cyl_%s" % cat, "title": title, "items": items})
	return out


func _rotary_children(entries: Array) -> Array:
	var out: Array = []
	for cat in RotaryLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "rotary" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(RotaryLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "rot_%s" % cat, "title": title, "items": items})
	return out


func _motor_children(entries: Array) -> Array:
	var out: Array = []
	for cat in MotorLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "motor" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(MotorLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "mot_%s" % cat, "title": title, "items": items})
	return out


func _valve_children(entries: Array) -> Array:
	var ways_order := [2, 3, 4, 5]
	var ways_title := {
		2: "Двухлинейные",
		3: "Трёхлинейные",
		4: "Четырёхлинейные",
		5: "Пятилинейные",
	}
	var out: Array = []
	for ways in ways_order:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "valve" and int(e.get("ways", 0)) == ways and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		out.append({"id": "valve_%d" % ways, "title": ways_title[ways], "items": items})
	return out


func _accessory_children(entries: Array) -> Array:
	var out: Array = []
	for cat in AccLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "accessory" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(AccLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "acc_%s" % cat, "title": title, "items": items})
	return out


func _electro_children(entries: Array) -> Array:
	var out: Array = []
	var rails: Array = []
	for e in entries:
		if str(e["group"]) == "rail_elec" and _matches(e):
			rails.append(e)
	if not rails.is_empty():
		out.append({"id": "elec_rail", "title": "Шина", "items": rails})
	for cat in ElectroLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "electro" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(ElectroLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "electro_%s" % cat, "title": title, "items": items})
	return out


func _sensor_children(entries: Array) -> Array:
	var out: Array = []
	for cat in SensorLib.CATEGORY_ORDER:
		var items: Array = []
		for e in entries:
			if str(e["group"]) == "sensor" and str(e.get("category", "")) == cat and _matches(e):
				items.append(e)
		if items.is_empty() and _query != "":
			continue
		var title: String = str(SensorLib.CATEGORY_TITLE.get(cat, cat))
		out.append({"id": "sensor_%s" % cat, "title": title, "items": items})
	return out


func _add_nested_catalog(parent_id: String, parent_title: String, children: Array, depth: int = 0) -> void:
	var visible := false
	for sub in children:
		var nested: Array = sub.get("children", []) if typeof(sub) == TYPE_DICTIONARY else []
		if not (sub["items"] as Array).is_empty() or not nested.is_empty() or _query == "":
			visible = true
			break
	if not visible and _query != "":
		return
	var parent_collapsed := bool(_collapsed.get(parent_id, true))
	_list_box.add_child(_section_header(parent_id, parent_title, depth))
	if parent_collapsed:
		return
	for sub in children:
		var sid: String = sub["id"]
		var items: Array = sub["items"]
		var nested2: Array = sub.get("children", []) if typeof(sub) == TYPE_DICTIONARY else []
		if items.is_empty() and nested2.is_empty() and _query != "":
			continue
		if not nested2.is_empty():
			# Подкаталог с собственными детьми (ПЦ / ПР).
			_add_nested_catalog(sid, str(sub["title"]), nested2, depth + 1)
			continue
		_list_box.add_child(_section_header(sid, str(sub["title"]), depth + 1))
		if bool(_collapsed.get(sid, true)):
			continue
		for e in items:
			_list_box.add_child(_item_row(e))


func _add_section(id: String, title: String, items: Array, depth: int) -> void:
	if items.is_empty() and _query != "":
		return
	_list_box.add_child(_section_header(id, title, depth))
	if bool(_collapsed.get(id, true)):
		return
	for e in items:
		_list_box.add_child(_item_row(e))


func _section_header(id: String, title: String, depth: int) -> Control:
	var collapsed := bool(_collapsed.get(id, true))
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "%s %s" % ["▸" if collapsed else "▾", title]
	btn.tooltip_text = ""
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", depth * 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.custom_minimum_size = Vector2(80, 0)
	pad.add_child(btn)
	btn.pressed.connect(func():
		_collapsed[id] = not bool(_collapsed.get(id, true))
		_rebuild()
	)
	btn.add_theme_color_override("font_color", UiTheme.muted())
	btn.add_theme_color_override("font_hover_color", UiTheme.text())
	btn.add_theme_color_override("font_pressed_color", UiTheme.text())
	# Плоская «секция», без тяжёлой кнопки.
	btn.flat = true
	return pad


func _hint(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_color_override("font_color", UiTheme.muted())
	lab.add_theme_font_size_override("font_size", 12)
	return lab


func _catalog_entries() -> Array:
	var out: Array = []
	out.append({"kind": "source", "title": "Источник энергии", "group": "pneumo"})
	out.append({"kind": "junction@tee", "title": "Тройник T", "group": "fittings"})
	out.append({"kind": "junction@wye", "title": "Тройник Y", "group": "fittings"})
	out.append({"kind": "junction@manifold", "title": "Коллектор 5 портов", "group": "fittings"})
	out.append({"kind": "junction@adapter", "title": "Переходник Ø→Ø", "group": "fittings"})
	# Групповая линия (бывш. шина УГО) — условность 2D, в 3D не показываем.
	if _preview_mode != "model3d":
		out.append({"kind": "rail@pneumatic", "title": "Групповая линия (пневмо)", "group": "rail_pneumo"})
		out.append({"kind": "rail@electric", "title": "Групповая линия", "group": "rail_elec"})
	for rec in CylLib.all_recipes():
		var rid := str(rec.get("id", ""))
		out.append({
			"kind": "cylinder@%s" % rid,
			"title": str(rec.get("title", rid)),
			"group": "cylinder",
			"category": str(rec.get("category", "double")),
		})
	for rec in RotaryLib.all_recipes():
		var rrid := str(rec.get("id", ""))
		out.append({
			"kind": "rotary_cylinder@%s" % rrid,
			"title": str(rec.get("title", rrid)),
			"group": "rotary",
			"category": str(rec.get("category", "rack_pinion")),
		})
	for rec in MotorLib.all_recipes():
		var mrid := str(rec.get("id", ""))
		out.append({
			"kind": "air_motor@%s" % mrid,
			"title": str(rec.get("title", mrid)),
			"group": "motor",
			"category": str(rec.get("category", "gear")),
		})
	for rec in ValveLib.all_recipes():
		var rid := str(rec.get("id", ""))
		out.append({
			"kind": "valve@%s" % rid,
			"title": str(rec.get("title", rid)),
			"group": "valve",
			"ways": int(rec.get("ways", 5)),
		})
	for rec in AccLib.all_recipes():
		var arid := str(rec.get("id", ""))
		out.append({
			"kind": "accessory@%s" % arid,
			"title": str(rec.get("title", arid)),
			"group": "accessory",
			"category": str(rec.get("category", "flow")),
		})
	for rec in ElectroLib.all_recipes():
		var rid := str(rec.get("id", ""))
		out.append({
			"kind": "electro@%s" % rid,
			"title": str(rec.get("title", rid)),
			"group": "electro",
			"category": str(rec.get("category", "terminals")),
		})
	for rec in SensorLib.all_recipes():
		var srid := str(rec.get("id", ""))
		out.append({
			"kind": "sensor@%s" % srid,
			"title": str(rec.get("title", srid)),
			"group": "sensor",
			"category": str(rec.get("category", "proximity")),
		})
	return out


func _matches(e: Dictionary) -> bool:
	if _query == "":
		return true
	var title := str(e.get("title", "")).to_lower()
	var kind := str(e.get("kind", "")).to_lower()
	return _query in title or _query in kind


func _item_row(e: Dictionary) -> Control:
	var kind := str(e["kind"])
	var row := PanelContainer.new()
	row.tooltip_text = ""
	row.custom_minimum_size = Vector2(0, 96)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inner)

	var preview: Control
	if _preview_mode == "model3d":
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(118, 84)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Пока печётся 3D — лёгкий placeholder цветом панели.
		var ph := StyleBoxFlat.new()
		ph.bg_color = UiTheme.panel_bg().darkened(0.06 if UiTheme.dark else 0.04)
		var holder := PanelContainer.new()
		holder.custom_minimum_size = Vector2(118, 84)
		holder.add_theme_stylebox_override("panel", ph)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		preview = holder
		_bind_thumb(kind, tr)
	else:
		var sp := SymbolPreview.new()
		sp.kind = kind
		sp.custom_minimum_size = Vector2(118, 84)
		sp.clip_contents = true
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		preview = sp
		_bind_symbol(kind, sp)
	preview.size_flags_stretch_ratio = 0.0
	inner.add_child(preview)

	var label := Label.new()
	label.text = str(e["title"])
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_stretch_ratio = 1.0
	label.custom_minimum_size = Vector2(100, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", UiTheme.text())
	inner.add_child(label)

	var star := Button.new()
	star.focus_mode = Control.FOCUS_NONE
	star.flat = true
	star.custom_minimum_size = Vector2(28, 28)
	star.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fav := bool(_favorites.get(kind, false))
	star.text = "★" if fav else "☆"
	star.tooltip_text = ""
	star.add_theme_color_override("font_color", UiTheme.ACCENT_MAGENTA.lightened(0.25) if fav else UiTheme.muted())
	star.pressed.connect(func():
		if _favorites.get(kind, false):
			_favorites.erase(kind)
		else:
			_favorites[kind] = true
		_save_favorites()
		favorites_changed.emit()
		_rebuild()
	)
	inner.add_child(star)

	row.gui_input.connect(func(event): _row_input(kind, event))
	return row


func _row_input(kind: String, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_row_down[kind] = event.position
			_row_sent[kind] = false
		else:
			if _row_down.has(kind) and not _row_sent.get(kind, false):
				item_chosen.emit(kind)
			_row_down.erase(kind)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _row_down.has(kind) and not _row_sent.get(kind, false):
		if event.position.distance_to(_row_down[kind]) > 6.0:
			_row_sent[kind] = true
			drag_started.emit(kind)
		get_viewport().set_input_as_handled()


func _load_favorites() -> void:
	_favorites.clear()
	if not FileAccess.file_exists(FAV_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FAV_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Array = parsed.get("kinds", [])
	for k in arr:
		_favorites[str(k)] = true


func _save_favorites() -> void:
	var kinds: Array = []
	for k in _favorites.keys():
		kinds.append(str(k))
	kinds.sort()
	var f := FileAccess.open(FAV_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"kinds": kinds}, "\t"))


class SymbolPreview extends Control:
	## Текстура из SymbolBaker; без прямого Geom.draw в ячейке (Compatibility crash).
	var kind := "cylinder"
	var _tex: TextureRect
	var _pending: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		_ensure_tex()

	func _ready() -> void:
		_ensure_tex()
		if _pending != null:
			_tex.texture = _pending
			_pending = null
			queue_redraw()

	func _ensure_tex() -> void:
		if _tex != null and is_instance_valid(_tex):
			return
		_tex = TextureRect.new()
		_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tex)

	func _draw() -> void:
		if _tex != null and _tex.texture != null:
			return
		var bg := UiTheme.panel_bg().darkened(0.05 if UiTheme.dark else 0.03)
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		var ink := UiTheme.preview_ink()
		ink.a = 0.35
		draw_rect(Rect2(size * 0.2, size * 0.6), ink, false, 1.5)

	func set_texture(tex: Texture2D) -> void:
		_pending = tex
		_ensure_tex()
		_tex.texture = tex
		queue_redraw()
