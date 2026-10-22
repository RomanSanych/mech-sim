extends Control

const CircuitScript = preload("res://scripts/domain/circuit.gd")
const SchematicScript = preload("res://scripts/ui/schematic_view.gd")
const LibraryScript = preload("res://scripts/ui/library_panel.gd")
const WorkshopScript = preload("res://scripts/view3d/workshop_view.gd")
const ViewCubeScript = preload("res://scripts/view3d/view_cube.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")
const PdfExport = preload("res://scripts/app/pdf_export.gd")
const BootSplashScript = preload("res://scripts/ui/boot_splash.gd")
const SchematicLayout = preload("res://scripts/domain/schematic_layout.gd")
const ElectroAutoroute = preload("res://scripts/domain/electro_autoroute.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
const Geom = preload("res://scripts/domain/symbol_geom.gd")

var SCENE_FILTER := PackedStringArray([
	"*.msim ; MechSim сцена",
	"*.mechsim.json ; JSON (устаревший)",
	"*.json ; JSON",
])
var PDF_FILTER := PackedStringArray(["*.pdf ; PDF"])

var circuit = CircuitScript.new()
var schematic: Control
var workshop: Node3D
var _library_2d: Control
var _library_3d: Control
var _play: Button
var _reset: Button
var _theme_btn: Button
var _btn_2d: Button
var _btn_3d: Button
var _btn_orient: Button
var _btn_pressure: Button
var _btn_sensor_field: Button
var _btn_thermal: Button
var _btn_xray: Button
var _thermal_legend: PanelContainer
var _thermal_legend_bar: ColorRect
var _thermal_legend_min: Label
var _thermal_legend_max: Label
var _thermal_legend_tex: ImageTexture
var _cam_orbit: Button
var _cam_fly: Button
var _cam_fpv: Button
var _cam_label: TextureRect
var _speed_label: Label
var _status: Label
var _ghost: Label
var _drag_kind := ""
var _armed_3d_kind := ""
var _view: SubViewport
var _view_container: SubViewportContainer
var _overlay: Control
var _view_tip: PanelContainer
var _view_tip_label: RichTextLabel
var _view3d_tip_text: String = ""
var _view3d_tip_refresh_usec: int = 0
var _view3d_tip_local: Vector2 = Vector2.ZERO
var _view_cube: Control
var _cam_help: PanelContainer
var _cam_help_label: Label
var _shell: VBoxContainer
var _backdrop: ColorRect
var _menubar_panel: PanelContainer
var _menu_buttons: Array[MenuButton] = []
var _scene_path := ""
var _file_dlg: FileDialog
var _file_mode := "" # open | save | save_as | pdf2d | pdf3d
var _dirty := false
var _show_2d := true
var _show_3d := true
var _orient_vertical := true # true: 2D|3D; false: 3D сверху, 2D снизу
var _main_split: SplitContainer
var _pane_2d: Control
var _pane_3d: Control
var _lib2d_slot: MarginContainer
var _lib3d_slot: MarginContainer
var _grip2d: Control
var _grip3d: Control
var _lib2d_width := 280
var _lib3d_width := 280
var _lib2d_collapsed := false
var _lib3d_collapsed := false
# Godot 4: split_offset — смещение от середины (0 = 50/50).
var _main_split_offset_h := 0
var _main_split_offset_v := 0
var _syncing_libs := false
var _boot_splash: Control
var _perf_hud: bool = false
var _play_btn_running: int = -1 # -1 unknown; 0/1 last styled run state
const _LIB_W_DEFAULT := 280
const _LIB_W_MIN := 200
const _LIB_W_MAX := 360
const _GRIP_W := 5


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var wipe := FileAccess.open("user://boot_trace.txt", FileAccess.WRITE)
	if wipe:
		wipe.store_string("")
		wipe.flush()
	_boot_trace("ready:start")
	UiTheme.load_settings()
	theme = _make_theme()
	_configure_window()
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.color = UiTheme.window_bg()
	add_child(_backdrop)
	_fit_to_window()
	_boot_trace("ready:backdrop")
	_show_boot_splash()
	_set_boot_status("Запуск…")
	_set_boot_progress(0.05)
	await get_tree().process_frame
	_boot_trace("ready:after_splash_frame")
	await _boot_sequence()
	_boot_trace("ready:done")


func _boot_sequence() -> void:
	## Вся тяжёлая загрузка — под splash, с подписью над прогрессбаром.
	_set_boot_status("Сборка интерфейса…")
	_set_boot_progress(0.10)
	_boot_build_ui()
	_fix_split_layout()
	if not await _await_boot_frame():
		return
	if not await _await_boot_frame():
		return

	_set_boot_status("Справочник клапанов…")
	_set_boot_progress(0.16)
	if not await _await_boot_frame():
		return
	_preload_valve_catalog()
	if not await _await_boot_frame():
		return

	_set_boot_status("Каталог 2D…")
	_set_boot_progress(0.20)
	if _library_2d != null and _library_2d.has_method("populate_stepped"):
		await _library_2d.populate_stepped(func(done: int, total: int):
			_set_boot_status("Каталог 2D %d / %d…" % [done, total])
			_set_boot_progress(0.20 + 0.12 * float(done) / float(maxi(total, 1)))
		)
	elif _library_2d != null and _library_2d.has_method("populate"):
		_library_2d.populate()
	_boot_trace("boot:lib2d")
	_fix_split_layout()
	if not await _await_boot_frame():
		return

	_set_boot_status("Каталог 3D…")
	_set_boot_progress(0.34)
	if _library_3d != null and _library_3d.has_method("set_preview_mode"):
		_library_3d.set_preview_mode("model3d")
	if not await _await_boot_frame():
		return
	if _library_3d != null and _library_3d.has_method("populate_stepped"):
		await _library_3d.populate_stepped(func(done: int, total: int):
			_set_boot_status("Каталог 3D %d / %d…" % [done, total])
			_set_boot_progress(0.34 + 0.12 * float(done) / float(maxi(total, 1)))
		)
	elif _library_3d != null and _library_3d.has_method("populate"):
		_library_3d.populate()
	_boot_trace("boot:lib3d")
	_fix_split_layout()
	if not await _await_boot_frame():
		return

	_set_boot_status("3D-цех…")
	_set_boot_progress(0.48)
	_attach_workshop_now()
	_fix_split_layout()
	_boot_trace("boot:workshop")
	if not await _await_boot_frame():
		return
	if not await _await_boot_frame():
		return

	_set_boot_status("УГО библиотеки…")
	_set_boot_progress(0.52)
	if not await _await_boot_frame():
		return
	if _library_2d != null and _library_2d.has_method("enqueue_all_catalog_previews"):
		_library_2d.enqueue_all_catalog_previews()
	if not await _await_boot_frame():
		return
	if _library_2d != null and _library_2d.has_method("warm_previews_stepped"):
		await _library_2d.warm_previews_stepped(func(done: int, total: int):
			_set_boot_status("УГО %d / %d…" % [done, total])
			_set_boot_progress(0.52 + 0.20 * float(done) / float(maxi(total, 1)))
		)
	var c2 := int(_library_2d.preview_cache_count()) if _library_2d != null and _library_2d.has_method("preview_cache_count") else -1
	_boot_trace("boot:bake2d cache=%d" % c2)

	_set_boot_status("3D-миниатюры…")
	_set_boot_progress(0.74)
	if not await _await_boot_frame():
		return
	if _library_3d != null and _library_3d.has_method("enqueue_all_catalog_previews"):
		_library_3d.enqueue_all_catalog_previews()
	if not await _await_boot_frame():
		return
	if _library_3d != null and _library_3d.has_method("warm_previews_stepped"):
		await _library_3d.warm_previews_stepped(func(done: int, total: int):
			_set_boot_status("3D-миниатюры %d / %d…" % [done, total])
			_set_boot_progress(0.74 + 0.18 * float(done) / float(maxi(total, 1)))
		)
	var c3 := int(_library_3d.preview_cache_count()) if _library_3d != null and _library_3d.has_method("preview_cache_count") else -1
	_boot_trace("boot:bake3d cache=%d" % c3)

	_set_boot_status("Раскладка окна…")
	_set_boot_progress(0.94)
	for _i in 6:
		_fix_split_layout()
		if not await _await_boot_frame():
			return
	_boot_trace_layout("pre_done")

	# Прогрев 3D под splash — свет и пол уже в кадре к моменту исчезновения оверлея.
	_set_boot_status("3D-вид…")
	_set_boot_progress(0.97)
	await _wake_workshop_viewport()
	_boot_trace("boot:workshop_lit")

	_set_boot_status("Готово")
	_set_boot_progress(1.0)
	_mark_boot_loaded()
	_boot_trace("boot:complete")
	_try_auto_open_review_scene()


func _boot_trace_layout(tag: String) -> void:
	var l2 := _lib2d_slot.size if _lib2d_slot != null else Vector2.ZERO
	var s2 := schematic.size if schematic != null else Vector2.ZERO
	var p2 := _pane_2d.size if _pane_2d != null else Vector2.ZERO
	var p3 := _pane_3d.size if _pane_3d != null else Vector2.ZERO
	var l3 := _lib3d_slot.size if _lib3d_slot != null else Vector2.ZERO
	var ms := _main_split.size if _main_split != null else Vector2.ZERO
	_boot_trace("layout:%s main=%.0fx%.0f pane2=%.0fx%.0f lib2=%.0f sch=%.0f pane3=%.0fx%.0f lib3=%.0f" % [
		tag, ms.x, ms.y, p2.x, p2.y, l2.x, s2.x, p3.x, p3.y, l3.x
	])


func _preload_valve_catalog() -> void:
	## Отдельный шаг splash — JSON рецептов не бьёт по populate.
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var CylLib = preload("res://scripts/domain/cylinder_library.gd")
	ValveLib.ensure_loaded()
	CylLib.ensure_loaded()


func _boot_build_ui() -> void:
	_boot_trace("ui:shell")
	_shell = VBoxContainer.new()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shell.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shell.add_theme_constant_override("separation", 0)
	add_child(_shell)

	_boot_trace("ui:toolbar")
	_shell.add_child(_toolbar())

	_boot_trace("ui:pane_2d")
	_pane_2d = _make_2d_pane()
	_boot_trace("ui:pane_2d_done")

	_boot_trace("ui:pane_3d")
	_pane_3d = _make_3d_pane()
	_boot_trace("ui:pane_3d_done")

	_boot_trace("ui:split")
	_rebuild_main_split()
	_status = Label.new()
	_status.custom_minimum_size = Vector2(0, 28)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_box := PanelContainer.new()
	status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 12)
	status_margin.add_theme_constant_override("margin_right", 12)
	status_box.add_child(status_margin)
	status_margin.add_child(_status)
	_shell.add_child(status_box)
	_ghost = Label.new()
	_ghost.visible = false
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.add_theme_font_size_override("font_size", 13)
	_ghost.z_index = 100
	add_child(_ghost)
	_setup_file_dialog()
	_apply_chrome_colors()
	_refresh_view_buttons()
	circuit.scene_changed.connect(mark_dirty)
	_update_window_title()
	get_viewport().size_changed.connect(func():
		_fit_to_window()
		call_deferred("_fix_split_layout")
	)
	_fit_to_window()
	_fix_split_layout()
	_boot_trace("ui:done")


func _boot_trace(step: String) -> void:
	var path := "user://boot_trace.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string("%d %s\n" % [Time.get_ticks_msec(), step])
	f.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		# Пока UI ещё не собран (splash-кадр), не трогаем раскладку лишний раз.
		if _shell == null:
			_fit_to_window()
			return
		_fit_to_window()


func _show_boot_splash() -> void:
	if has_node("BootSplashLayer"):
		return
	var layer := CanvasLayer.new()
	layer.name = "BootSplashLayer"
	layer.layer = 128
	add_child(layer)
	var splash: Control = BootSplashScript.new()
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	splash.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_boot_splash = splash
	if splash.has_signal("finished"):
		splash.finished.connect(_on_boot_splash_finished)
	layer.add_child(splash)
	if splash.has_method("_fit"):
		splash.call("_fit")
	_set_boot_progress(0.04)
	_boot_trace("splash:shown")


func _set_boot_progress(p: float) -> void:
	if _boot_splash != null and is_instance_valid(_boot_splash) and _boot_splash.has_method("set_load_progress"):
		_boot_splash.set_load_progress(p)


func _set_boot_status(text: String) -> void:
	if _boot_splash != null and is_instance_valid(_boot_splash) and _boot_splash.has_method("set_status_text"):
		_boot_splash.set_status_text(text)


func _mark_boot_loaded() -> void:
	if _boot_splash != null and is_instance_valid(_boot_splash) and _boot_splash.has_method("mark_load_complete"):
		_boot_splash.mark_load_complete()


func _on_boot_splash_finished() -> void:
	_boot_trace("splash:finished")
	_boot_splash = null
	# На случай, если прогрев не успел — включаем цех при закрытии splash.
	if _view != null and is_instance_valid(_view):
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_fix_split_layout()
	_boot_trace_layout("after_splash")


func _await_boot_frame() -> bool:
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	await tree.process_frame
	return is_instance_valid(self) and is_inside_tree()


func _wake_workshop_viewport() -> void:
	## Включаем рендер цеха ещё под splash, чтобы к fade-out свет уже был в кадре.
	if _view == null or not is_instance_valid(_view):
		return
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		if not await _await_boot_frame():
			return
		await RenderingServer.frame_post_draw


func _attach_workshop_now() -> void:
	_boot_trace("workshop:attach_begin")
	if _view == null or not is_instance_valid(_view):
		_boot_trace("workshop:no_view")
		return
	if workshop != null and is_instance_valid(workshop):
		# Пока пекутся миниатюры — не крутим цех каждый кадр.
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_boot_trace("workshop:already")
		return
	workshop = Node3D.new()
	workshop.set_script(WorkshopScript)
	workshop.circuit = circuit
	if workshop.has_signal("request_element_props"):
		workshop.request_element_props.connect(_on_workshop_request_element_props)
	if workshop.has_signal("request_hit_picker"):
		workshop.request_hit_picker.connect(_on_workshop_request_hit_picker)
	if workshop.has_signal("sim_control_changed"):
		workshop.sim_control_changed.connect(_on_workshop_sim_control_changed)
	_view.add_child(workshop)
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_boot_trace("workshop:attached")


func _on_workshop_sim_control_changed() -> void:
	## Кнопка/орган в 3D → сразу обновить УГО на 2D (при Run Base иначе заморожен).
	if schematic != null and is_instance_valid(schematic) and schematic.has_method("notify_sim_control_changed"):
		schematic.notify_sim_control_changed()


func _on_workshop_request_element_props(el_id: int, screen: Vector2 = Vector2.ZERO) -> void:
	## ПКМ в 3D → общее окно элемента (float) на оверлее 3D, не панель «Свойства».
	if schematic == null or not is_instance_valid(schematic):
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var local: Vector2 = screen
	if local == Vector2.ZERO:
		local = _overlay.get_local_mouse_position()
	if schematic.has_method("open_element_props_from_3d"):
		schematic.open_element_props_from_3d(el_id, _overlay, local)


func _on_workshop_request_hit_picker(hits: Array, screen: Vector2 = Vector2.ZERO) -> void:
	## ЛКМ в 3D по нескольким объектам → белый список на оверлее.
	if schematic == null or not is_instance_valid(schematic):
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	# Тултип (z=60) иначе остаётся поверх списка выбора (z=30).
	_hide_view3d_tip()
	var local: Vector2 = screen
	if local == Vector2.ZERO:
		local = _overlay.get_local_mouse_position()
	else:
		# screen из SubViewport — перевести в координаты оверлея.
		local = _overlay.get_local_mouse_position()
	if schematic.has_method("open_hit_picker_from_3d"):
		schematic.open_hit_picker_from_3d(hits, _overlay, local)


func _fix_split_layout() -> void:
	## HBox-слоты: библиотека всегда фиксированной ширины, схема/цех забирают остаток.
	_lib2d_width = clampi(_lib2d_width, _LIB_W_MIN, _LIB_W_MAX)
	_lib3d_width = clampi(_lib3d_width, _LIB_W_MIN, _LIB_W_MAX)
	_apply_lib_offsets()
	if _main_split != null and _show_2d and _show_3d:
		_main_split.split_offset = _main_split_offset_h if _orient_vertical else _main_split_offset_v


func _fit_to_window() -> void:
	# stretch=disabled: UI в пикселях окна, без масштабирования → нет блюра и сплющивания.
	# Якоря TOP_LEFT (не FULL_RECT): иначе set size при opposite anchors сыпет WARNING в отладчик.
	var w := get_window()
	var ws: Vector2 = Vector2(w.size) if w != null else get_viewport().get_visible_rect().size
	if ws.x < 2.0 or ws.y < 2.0:
		return
	_fit_control_pixels(self, ws)
	if _backdrop != null:
		_fit_control_pixels(_backdrop, ws)
	if _shell != null:
		_fit_control_pixels(_shell, ws)


func _fit_control_pixels(ctrl: Control, ws: Vector2) -> void:
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	ctrl.position = Vector2.ZERO
	ctrl.size = ws


func _configure_window() -> void:
	var w := get_window()
	w.title = "MechSim — пневмосхема"
	w.borderless = false
	w.unresizable = false
	w.min_size = Vector2i(960, 600)
	# Без bitmap-stretch: чёткие шрифты при ресайзе.
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	w.content_scale_factor = 1.0
	w.content_scale_size = Vector2i.ZERO
	var root := get_tree().root
	if root != w:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_factor = 1.0
		root.content_scale_size = Vector2i.ZERO
	# По умолчанию — развёрнутое окно (и из редактора, и в экспорте).
	if w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		w.mode = Window.MODE_MAXIMIZED
	elif w.mode != Window.MODE_MAXIMIZED and w.mode != Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_MAXIMIZED
	call_deferred("_ensure_maximized")


func _ensure_maximized() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		w.mode = Window.MODE_MAXIMIZED
	elif w.mode != Window.MODE_MAXIMIZED and w.mode != Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_MAXIMIZED
	_boot_trace("window:mode=%d size=%dx%d" % [int(w.mode), w.size.x, w.size.y])


func _update_window_title() -> void:
	var name := "Без имени"
	if _scene_path != "":
		name = _scene_path.get_file()
	var mark := "*" if _dirty else ""
	get_window().title = "MechSim — %s%s" % [name, mark]


func mark_dirty() -> void:
	_dirty = true
	_update_window_title()


func _setup_file_dialog() -> void:
	_file_dlg = FileDialog.new()
	_file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_file_dlg.use_native_dialog = true
	_file_dlg.file_selected.connect(_on_file_selected)
	add_child(_file_dlg)


func _menu_button(title: String, items: Array) -> MenuButton:
	var btn := MenuButton.new()
	btn.text = title
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var popup := btn.get_popup()
	popup.clear()
	var id := 0
	var actions: Dictionary = {}
	for item in items:
		var label: String = str(item[0])
		var action: String = str(item[1])
		if label == "-":
			popup.add_separator()
			continue
		popup.add_item(label, id)
		actions[id] = action
		# [label, action, keycode, shift?]
		if item.size() >= 3 and int(item[2]) != 0:
			var key: int = int(item[2])
			var shift: bool = item.size() >= 4 and bool(item[3])
			var ev := InputEventKey.new()
			ev.keycode = key as Key
			ev.ctrl_pressed = key != KEY_F11
			ev.shift_pressed = shift
			popup.set_item_accelerator(id, ev.get_keycode_with_modifiers())
		id += 1
	btn.set_meta("menu_actions", actions)
	popup.id_pressed.connect(func(pressed_id: int):
		var map: Dictionary = btn.get_meta("menu_actions")
		if map.has(pressed_id):
			_menu_action(str(map[pressed_id]))
	)
	_style_menu_button(btn)
	_menu_buttons.append(btn)
	return btn


func _style_menu_button(btn: MenuButton) -> void:
	var fg := UiTheme.text()
	var muted := UiTheme.muted()
	# Все состояния, включая hover+pressed (меню открыто) — иначе текст белеет.
	for key in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
		"font_focus_color", "font_disabled_color", "font_outline_color",
	]:
		btn.add_theme_color_override(key, muted if key == "font_disabled_color" else fg)
	var hover := StyleBoxFlat.new()
	hover.bg_color = UiTheme.menu_hover()
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	hover.content_margin_top = 4
	hover.content_margin_bottom = 4
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 10
	empty.content_margin_right = 10
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("hover_pressed", hover)
	btn.add_theme_stylebox_override("focus", empty)
	_style_popup_menu(btn.get_popup())


func _style_popup_menu(popup: PopupMenu) -> void:
	# Без тени и тёмной рамки — иначе вокруг светлого меню виден «угольный» контур.
	var panel := StyleBoxFlat.new()
	panel.bg_color = UiTheme.menu_bg()
	panel.border_color = UiTheme.menu_border()
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(6)
	panel.shadow_size = 0
	popup.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = UiTheme.menu_hover()
	hover.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("hover", hover)
	var sep := StyleBoxFlat.new()
	sep.bg_color = UiTheme.menu_border()
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	popup.add_theme_stylebox_override("separator", sep)
	popup.add_theme_color_override("font_color", UiTheme.text())
	popup.add_theme_color_override("font_hover_color", UiTheme.text())
	popup.add_theme_color_override("font_accelerator_color", UiTheme.muted())
	popup.add_theme_color_override("font_separator_color", UiTheme.muted())
	popup.add_theme_font_size_override("font_size", 13)
	popup.transparent = true
	popup.transparent_bg = true
	popup.borderless = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var e := event as InputEventKey
	if e.ctrl_pressed and e.keycode == KEY_N:
		_menu_action("new")
		accept_event()
	elif e.ctrl_pressed and e.keycode == KEY_O:
		_menu_action("open")
		accept_event()
	elif e.ctrl_pressed and e.shift_pressed and e.keycode == KEY_S:
		_menu_action("save_as")
		accept_event()
	elif e.ctrl_pressed and e.keycode == KEY_S:
		_menu_action("save")
		accept_event()
	elif e.ctrl_pressed and e.keycode == KEY_Q:
		_menu_action("quit")
		accept_event()
	elif e.ctrl_pressed and e.keycode == KEY_Z and not e.shift_pressed:
		_menu_action("undo")
		accept_event()
	elif e.ctrl_pressed and (e.keycode == KEY_Y or (e.keycode == KEY_Z and e.shift_pressed)):
		_menu_action("redo")
		accept_event()
	elif e.keycode == KEY_F11:
		_menu_action("fullscreen")
		accept_event()


func _menu_action(action: String) -> void:
	match action:
		"new":
			_new_scene()
		"open":
			_file_mode = "open"
			_file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dlg.filters = SCENE_FILTER
			_file_dlg.title = "Открыть сцену"
			_file_dlg.popup_centered_ratio(0.6)
		"undo":
			_undo_edit()
		"redo":
			_redo_edit()
		"arrange_schematic":
			_arrange_schematic()
		"save":
			_save_scene(false)
		"save_as":
			_save_scene(true)
		"pdf2d":
			_file_mode = "pdf2d"
			_file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_file_dlg.filters = PDF_FILTER
			_file_dlg.title = "Экспорт 2D схемы в PDF"
			_file_dlg.current_file = "schematic.pdf"
			_file_dlg.popup_centered_ratio(0.6)
		"pdf3d":
			_file_mode = "pdf3d"
			_file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_file_dlg.filters = PDF_FILTER
			_file_dlg.title = "Экспорт 3D сцены в PDF"
			_file_dlg.current_file = "workshop.pdf"
			_file_dlg.popup_centered_ratio(0.6)
		"quit":
			get_tree().quit()
		"fullscreen":
			var w := get_window()
			if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
				w.mode = Window.MODE_WINDOWED
			else:
				w.mode = Window.MODE_FULLSCREEN
		"maximize":
			get_window().mode = Window.MODE_MAXIMIZED
		"windowed":
			get_window().mode = Window.MODE_WINDOWED
		"minimize":
			get_window().mode = Window.MODE_MINIMIZED
		"bug_report":
			_open_bug_report()
		"perf_hud":
			_perf_hud = not _perf_hud
			if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_perf_hud"):
				workshop.set_perf_hud(_perf_hud)
			circuit.notify("Нагрузка: %s" % ("вкл" if _perf_hud else "выкл"))


func _redraw_schematic() -> void:
	if schematic == null:
		return
	if schematic.has_method("redraw_scheme"):
		schematic.redraw_scheme()
	else:
		schematic.queue_redraw()


func _new_scene() -> void:
	circuit.clear_scene()
	if circuit.has_method("reset_history"):
		circuit.reset_history()
	_scene_path = ""
	_dirty = false
	_redraw_schematic()
	_update_window_title()
	circuit.notify("Новая сцена")


func _undo_edit() -> void:
	if circuit == null or not circuit.has_method("undo_edit"):
		return
	if circuit.undo_edit():
		_redraw_schematic()
		_dirty = true
		_update_window_title()


func _redo_edit() -> void:
	if circuit == null or not circuit.has_method("redo_edit"):
		return
	if circuit.redo_edit():
		_redraw_schematic()
		_dirty = true
		_update_window_title()



## Агент: обрыв на всех электро-жилах + скрыть неиспользуемые контакты + авто-подписи.
func apply_agent_review_flags() -> Dictionary:
	if schematic != null and schematic.has_method("apply_review_break_and_hide_unused"):
		schematic.apply_review_break_and_hide_unused()
		return {"ok": true}
	return {"ok": false}


func _arrange_schematic() -> Dictionary:
	if circuit == null:
		return {"ok": false, "moved": 0}
	if circuit.has_method("begin_history_group"):
		circuit.begin_history_group()
	var res: Dictionary = ElectroAutoroute.arrange(circuit)
	WireRouter2D.invalidate()
	WireRouter2D.prepare(circuit)
	for w in circuit.wires:
		WireRouter2D.path_for(circuit, w)
	WireRouter2D.end_batch()
	if schematic != null and schematic.has_method("auto_place_element_tags"):
		schematic.auto_place_element_tags(true)
	if circuit.has_method("end_history_group"):
		circuit.end_history_group()
	_redraw_schematic()
	_dirty = true
	_update_window_title()
	var moved: int = int(res.get("moved", 0))
	var rails_n: int = int(res.get("rails", 0))
	var broken_n: int = int(res.get("broken", 0))
	circuit.notify("Автотрасса: сдвигов %d · коридоров %d · обрывов %d" % [moved, rails_n, broken_n])
	return res


## Диагностика жил по номерам на схеме (напр. [65, 69, 71]).
func agent_wire_nums_probe(nums: Array = []) -> Dictionary:
	if circuit == null:
		return {"ok": false}
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var want: Dictionary = {}
	for n in nums:
		want[int(n)] = true
	WireRouter2D.prepare(circuit)
	var rows: Array = []
	for w in circuit.wires:
		if not want.is_empty() and not want.has(int(w.num)):
			continue
		var pts: PackedVector2Array = WireRouter2D.path_for(circuit, w)
		var ea = circuit.get_element(int(w.a_id))
		var eb = circuit.get_element(int(w.b_id))
		var through: Array = []
		var skip: Dictionary = {int(w.a_id): true, int(w.b_id): true}
		for el in circuit.elements:
			if skip.has(int(el.id)):
				continue
			var r: Rect2 = Geom.world_bounds(el).grow(Geom.SCH_GRID * 0.35)
			for i in range(pts.size() - 1):
				var mid: Vector2 = (pts[i] + pts[i + 1]) * 0.5
				if r.has_point(mid):
					through.append(str(el.tag))
					break
		var pts_out: Array = []
		for p in pts:
			pts_out.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		var d0: Vector2 = pts[1] - pts[0] if pts.size() >= 2 else Vector2.ZERO
		var d1: Vector2 = pts[pts.size() - 2] - pts[pts.size() - 1] if pts.size() >= 2 else Vector2.ZERO
		rows.append({
			"num": int(w.num),
			"a": str(ea.tag) if ea else "?",
			"ap": str(w.a_port),
			"b": str(eb.tag) if eb else "?",
			"bp": str(w.b_port),
			"a_cls": str(ea.electro_class) if ea else "",
			"b_cls": str(eb.electro_class) if eb else "",
			"d0": [snappedf(d0.x, 0.1), snappedf(d0.y, 0.1)],
			"d1": [snappedf(d1.x, 0.1), snappedf(d1.y, 0.1)],
			"pts": pts_out,
			"through": through,
		})
	WireRouter2D.end_batch()
	return {"ok": true, "wires": rows}


## Диагностика одной жилы: path + чужие УГО на пути.
func agent_wire_hit_probe(wire_id: int = -1) -> Dictionary:
	if circuit == null:
		return {"ok": false}
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	WireRouter2D.invalidate()
	WireRouter2D.prepare(circuit)
	var w = null
	if wire_id >= 0:
		w = circuit.get_wire(wire_id)
	if w == null and circuit.wires.size() > 0:
		w = circuit.wires[0]
	if w == null:
		WireRouter2D.end_batch()
		return {"ok": false, "err": "no wire"}
	var pts: PackedVector2Array = WireRouter2D.path_for(circuit, w)
	var skip: Dictionary = {int(w.a_id): true, int(w.b_id): true}
	var through: Array = []
	for el in circuit.elements:
		if skip.has(int(el.id)):
			continue
		var r: Rect2 = Geom.world_bounds(el).grow(Geom.SCH_GRID * 0.35)
		for i in range(pts.size() - 1):
			var mid: Vector2 = (pts[i] + pts[i + 1]) * 0.5
			if r.has_point(mid):
				through.append({"tag": str(el.tag), "cls": str(el.electro_class), "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
				break
	var ea = circuit.get_element(int(w.a_id))
	var eb = circuit.get_element(int(w.b_id))
	var pts_out: Array = []
	for p in pts:
		pts_out.append([p.x, p.y])
	WireRouter2D.end_batch()
	return {
		"ok": true,
		"wire": int(w.id),
		"a": str(ea.tag) if ea else "?",
		"b": str(eb.tag) if eb else "?",
		"pts": pts_out,
		"through": through,
		"obs_n": WireRouter2D._obs_rects.size(),
		"route_rev": 2,
	}


## Аудит 2D: рельсы vs катушки, повороты АВ, доля гориз. сегментов жил.
func agent_layout_audit() -> Dictionary:
	if circuit == null:
		return {"ok": false}
	var SchematicLayout = preload("res://scripts/domain/schematic_layout.gd")
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var rails: Dictionary = SchematicLayout._classify_rails(circuit)
	var rail_rows: Array = []
	for side in ["left", "right", "pe"]:
		for idv in rails.get(side, []) as Array:
			var el = circuit.get_element(int(idv))
			if el == null:
				continue
			var b: Rect2 = Geom.world_bounds(el)
			rail_rows.append({
				"side": side,
				"tag": str(el.tag),
				"id": int(el.id),
				"x": float(el.position.x),
				"y": float(el.position.y),
				"x0": b.position.x,
				"x1": b.position.x + b.size.x,
				"rot": int(el.rotation_quad),
			})
	var ctrl_rows: Array = []
	var max_ctrl_x1: float = -1.0e9
	var offenders: Array = [] # control right of right-rail
	var right_min_x0: float = 1.0e9
	for rr in rail_rows:
		if str(rr["side"]) in ["right", "pe"]:
			right_min_x0 = minf(right_min_x0, float(rr["x0"]))
	for el2 in circuit.elements:
		if el2 == null or str(el2.kind) != "electro":
			continue
		var cls: String = str(el2.electro_class)
		var role: String = str(el2.member_role)
		if cls in ["terminal", "busbar", "supply"]:
			continue
		if role == "contact" and not bool(el2.detached):
			continue
		if cls in ["contact", "lamp", "relay", "timer_relay", "contactor", "thermal",
				"voltage_relay", "button", "e_stop", "switch", "solenoid_coil"] \
				or (cls in ["mcb", "rcd", "rcbo", "psu"]):
			var b2: Rect2 = Geom.world_bounds(el2)
			var x1: float = b2.position.x + b2.size.x
			max_ctrl_x1 = maxf(max_ctrl_x1, x1)
			ctrl_rows.append({
				"tag": str(el2.tag),
				"cls": cls,
				"role": role,
				"x": float(el2.position.x),
				"y": float(el2.position.y),
				"x0": b2.position.x,
				"x1": x1,
				"rot": int(el2.rotation_quad),
			})
			if x1 > right_min_x0 - 1.0 and cls not in ["mcb", "rcd", "rcbo", "psu"]:
				offenders.append({
					"tag": str(el2.tag),
					"cls": cls,
					"x1": x1,
					"rail_x0": right_min_x0,
					"delta": x1 - right_min_x0,
				})
	ctrl_rows.sort_custom(func(a, b): return float(a["x1"]) > float(b["x1"]))
	# Ориентация АВ.
	var brk: Array = []
	for el3 in circuit.elements:
		if el3 == null:
			continue
		if str(el3.electro_class) in ["mcb", "rcd", "rcbo"]:
			brk.append({"tag": str(el3.tag), "rot": int(el3.rotation_quad)})
	# Сегменты жил: гориз vs верт.
	WireRouter2D.prepare(circuit)
	var n_h: int = 0
	var n_v: int = 0
	var n_wires: int = 0
	for w in circuit.wires:
		n_wires += 1
		var pts: PackedVector2Array = WireRouter2D.path_for(circuit, w)
		for i in range(pts.size() - 1):
			var d: Vector2 = pts[i + 1] - pts[i]
			if absf(d.x) >= absf(d.y):
				n_h += 1
			else:
				n_v += 1
	WireRouter2D.end_batch()
	offenders.sort_custom(func(a, b): return float(a["delta"]) > float(b["delta"]))
	# Длинные вертикали (≥3 клеток) — источник «каши».
	var long_v: Array = []
	WireRouter2D.prepare(circuit)
	for w2 in circuit.wires:
		var pts2: PackedVector2Array = WireRouter2D.path_for(circuit, w2)
		var vlen: float = 0.0
		for i2 in range(pts2.size() - 1):
			var d2: Vector2 = pts2[i2 + 1] - pts2[i2]
			if absf(d2.x) < 0.51:
				vlen += absf(d2.y)
		if vlen >= 30.0:
			var ea = circuit.get_element(int(w2.a_id))
			var eb = circuit.get_element(int(w2.b_id))
			long_v.append({
				"vlen": vlen,
				"a": str(ea.tag) if ea else "?",
				"ap": str(w2.a_port),
				"b": str(eb.tag) if eb else "?",
				"bp": str(w2.b_port),
			})
	WireRouter2D.end_batch()
	long_v.sort_custom(func(a, b): return float(a["vlen"]) > float(b["vlen"]))
	var brk_pos: Array = []
	for el4 in circuit.elements:
		if el4 == null or str(el4.electro_class) not in ["mcb", "rcd", "rcbo"]:
			continue
		var bb: Rect2 = Geom.world_bounds(el4)
		brk_pos.append({
			"tag": str(el4.tag),
			"rot": int(el4.rotation_quad),
			"x0": bb.position.x,
			"x1": bb.position.x + bb.size.x,
			"y": float(el4.position.y),
		})
	var hit_paths: Array = []
	WireRouter2D.prepare(circuit)
	for wh in circuit.wires:
		hit_paths.append(WireRouter2D.path_for(circuit, wh))
	WireRouter2D.end_batch()
	var wire_el_hits: float = SchematicLayout._wire_element_hits(circuit, hit_paths)
	var foreign_hits: Array = []
	var foreign_n: float = 0.0
	var term_stub_bad: Array = []
	for wi_f in circuit.wires.size():
		if wi_f >= hit_paths.size():
			break
		var wf = circuit.wires[wi_f]
		var pts_f: PackedVector2Array = hit_paths[wi_f] as PackedVector2Array
		if pts_f.size() < 2:
			continue
		var skip_f: Dictionary = {int(wf.a_id): true, int(wf.b_id): true}
		for el_f in circuit.elements:
			var eid_f: int = int(el_f.id)
			if skip_f.has(eid_f):
				continue
			var rf: Rect2 = Geom.world_bounds(el_f).grow(Geom.SCH_GRID * 0.35)
			var hit_f: bool = false
			for i_f in range(pts_f.size() - 1):
				var mid_f: Vector2 = (pts_f[i_f] + pts_f[i_f + 1]) * 0.5
				if rf.has_point(mid_f):
					hit_f = true
					break
			if hit_f:
				foreign_n += 1.0
				var ea_f = circuit.get_element(int(wf.a_id))
				var eb_f = circuit.get_element(int(wf.b_id))
				foreign_hits.append({
					"wire": int(wf.id),
					"num": int(wf.num),
					"a": str(ea_f.tag) if ea_f else "?",
					"b": str(eb_f.tag) if eb_f else "?",
					"through": str(el_f.tag),
				})
		# Подход к клеммнику: первый/последний сегмент ⊥ длинной стороне, ≥2 клетки.
		var ea_t = circuit.get_element(int(wf.a_id))
		var eb_t = circuit.get_element(int(wf.b_id))
		for end_i in 2:
			var el_t = ea_t if end_i == 0 else eb_t
			if el_t == null or str(el_t.electro_class) not in ["terminal", "busbar"]:
				continue
			var tip_t: Vector2 = pts_f[0] if end_i == 0 else pts_f[pts_f.size() - 1]
			var nxt_t: Vector2 = pts_f[1] if end_i == 0 else pts_f[pts_f.size() - 2]
			var d_t: Vector2 = nxt_t - tip_t
			var rb_t: Rect2 = Geom.world_bounds(el_t)
			var long_x_t: bool = rb_t.size.x >= rb_t.size.y
			var ok_stub: bool = false
			if long_x_t:
				ok_stub = absf(d_t.x) <= 0.6 and absf(d_t.y) + 0.51 >= Geom.SCH_GRID * 3.0
			else:
				ok_stub = absf(d_t.y) <= 0.6 and absf(d_t.x) + 0.51 >= Geom.SCH_GRID * 3.0
			if not ok_stub:
				term_stub_bad.append({
					"num": int(wf.num),
					"wire": int(wf.id),
					"tag": str(el_t.tag),
					"dx": d_t.x,
					"dy": d_t.y,
				})
	return {
		"ok": true,
		"rails": rail_rows,
		"right_min_x0": right_min_x0,
		"max_ctrl_x1": max_ctrl_x1,
		"ctrl_past_right_rail": max_ctrl_x1 > right_min_x0,
		"top_ctrl_by_x1": ctrl_rows.slice(0, mini(12, ctrl_rows.size())),
		"offenders": offenders.slice(0, mini(15, offenders.size())),
		"breakers": brk,
		"breaker_pos": brk_pos,
		"long_verticals": long_v.slice(0, mini(12, long_v.size())),
		"wire_segs_h": n_h,
		"wire_segs_v": n_v,
		"wires": n_wires,
		"wire_el_hits": wire_el_hits,
		"foreign_el_hits": foreign_n,
		"foreign_samples": foreign_hits.slice(0, mini(20, foreign_hits.size())),
		"term_stub_bad": term_stub_bad.slice(0, mini(30, term_stub_bad.size())),
		"term_stub_bad_n": term_stub_bad.size(),
	}


## Диагностика релейной раскладки (агент / отладка).
func agent_relay_layout_probe() -> Dictionary:
	if circuit == null:
		return {"ok": false}
	var head: Array = []
	for i in mini(circuit.elements.size(), 12):
		var el0 = circuit.elements[i]
		if el0 == null:
			continue
		head.append({
			"id": int(el0.id),
			"tag": str(el0.tag),
			"kind": str(el0.kind),
			"cls": str(el0.electro_class),
			"role": str(el0.member_role),
			"phase": str(el0.phase),
			"detached": bool(el0.detached),
			"pos": [float(el0.position.x), float(el0.position.y)],
		})
	var rails: Dictionary = SchematicLayout._classify_rails(circuit)
	var seed_moved: int = SchematicLayout._seed_relay_layout(circuit)
	_redraw_schematic()
	var head2: Array = []
	for j in mini(circuit.elements.size(), 12):
		var el1 = circuit.elements[j]
		if el1 == null:
			continue
		head2.append({
			"tag": str(el1.tag),
			"cls": str(el1.electro_class),
			"detached": bool(el1.detached),
			"pos": [float(el1.position.x), float(el1.position.y)],
		})
	return {
		"ok": true,
		"n": circuit.elements.size(),
		"rails": rails,
		"seed_moved": seed_moved,
		"before": head,
		"after": head2,
	}

func _open_bug_report() -> void:
	var BugRep = preload("res://scripts/app/bug_report.gd")
	BugRep.show_dialog(
		self,
		circuit,
		func() -> Image:
			var tex: ViewportTexture = get_viewport().get_texture()
			if tex == null:
				return null
			return tex.get_image()
		,
		func(path: String) -> String:
			var extra := {}
			if schematic:
				extra["schematic"] = {
					"zoom": schematic.zoom,
					"pan": [schematic.pan.x, schematic.pan.y],
				}
			return circuit.save_scene_file(path, extra)
	)


func _save_scene(force_dialog: bool) -> void:
	if force_dialog or _scene_path == "":
		_file_mode = "save_as"
		_file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dlg.filters = SCENE_FILTER
		_file_dlg.title = "Сохранить сцену"
		var cur_name: String = _scene_path.get_file() if _scene_path != "" else "scene.msim"
		if not cur_name.to_lower().ends_with(".msim"):
			cur_name = "scene.msim"
		_file_dlg.current_file = cur_name
		_file_dlg.popup_centered_ratio(0.6)
		return
	_write_scene(_scene_path)


func _write_scene(path: String) -> void:
	path = _ensure_msim_path(path)
	var extra := {}
	if schematic:
		extra["schematic"] = {
			"zoom": schematic.zoom,
			"pan": [schematic.pan.x, schematic.pan.y],
		}
	var err := circuit.save_scene_file(path, extra)
	if err != "":
		circuit.notify(err)
		return
	_scene_path = path
	_dirty = false
	_update_window_title()
	circuit.notify("Сохранено: %s" % path.get_file())


func _ensure_msim_path(path: String) -> String:
	var lower: String = path.to_lower()
	if lower.ends_with(".msim"):
		return path
	if lower.ends_with(".mechsim.json"):
		return path.substr(0, path.length() - ".mechsim.json".length()) + ".msim"
	if lower.ends_with(".json"):
		return path.get_basename() + ".msim"
	return path + ".msim"


func _on_file_selected(path: String) -> void:
	match _file_mode:
		"open":
			open_scene_path(path)
		"save", "save_as":
			_write_scene(path)
		"pdf2d":
			await _export_pdf_2d(path)
		"pdf3d":
			await _export_pdf_3d(path)


## Открыть .msim / .mechsim.json (диалог, CLI --open=, agent review).
func open_scene_path(path: String) -> bool:
	if path.strip_edges() == "":
		return false
	var res: Dictionary = circuit.load_scene_file(path)
	if str(res.get("error", "")) != "":
		circuit.notify(str(res["error"]))
		return false
	_scene_path = path
	_dirty = false
	var data: Dictionary = res.get("data", {})
	if schematic and data.has("schematic"):
		var sc: Dictionary = data["schematic"]
		schematic.zoom = float(sc.get("zoom", 1.0))
		var pan = sc.get("pan", [48, 56])
		if pan is Array and pan.size() >= 2:
			schematic.pan = Vector2(float(pan[0]), float(pan[1]))
	_redraw_schematic()
	# Большие сцены: 3D-модели пакетами, чтобы не фризить UI на одном кадре.
	if workshop != null and is_instance_valid(workshop) and workshop.has_method("begin_chunked_build"):
		var n_el: int = circuit.elements.size()
		var budget: int = 3 if n_el > 30 else (4 if n_el > 16 else 8)
		workshop.begin_chunked_build(budget)
	_apply_dense_viewport_lod()
	_update_window_title()
	circuit.notify("Открыто: %s" % path.get_file())
	return true


var _dense_3d_lod: bool = false
var _dense_3d_cam_yaw: float = 1.0e9
var _dense_3d_cam_pitch: float = 1.0e9
var _dense_3d_cam_pos: Vector3 = Vector3(1.0e9, 1.0e9, 1.0e9)
var _cube_cam_yaw: float = 1.0e9
var _cube_cam_pitch: float = 1.0e9
## Перетаскивание сплита 2D|3D — без ALWAYS картинка стробит (UPDATE_ONCE на меняющемся size).
var _main_split_dragging: bool = false
var _dense_3d_vp_size: Vector2i = Vector2i.ZERO
var _dense_3d_resize_hold_msec: int = 0


## Плотный электрощит: floor/grid off + idle 3D реже. Без stretch_shrink — иначе мыло.
func _apply_dense_viewport_lod() -> void:
	_dense_3d_lod = circuit != null and circuit.wires.size() > 40
	if _view_container != null and is_instance_valid(_view_container):
		_view_container.stretch_shrink = 1
	if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_dense_scene_lod"):
		workshop.set_dense_scene_lod(_dense_3d_lod)


func _tick_dense_3d_render() -> void:
	if not _dense_3d_lod or _view == null or not is_instance_valid(_view) or not _show_3d:
		if _view != null and is_instance_valid(_view) and _show_3d:
			_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	# Ресайз окна / сплит: size SubViewport плывёт — нужен каждый кадр.
	var vp_sz: Vector2i = _view.size
	if vp_sz != _dense_3d_vp_size:
		_dense_3d_vp_size = vp_sz
		_dense_3d_resize_hold_msec = Time.get_ticks_msec() + 220
	if _main_split_dragging or Time.get_ticks_msec() < _dense_3d_resize_hold_msec:
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	var cam_busy: bool = false
	if workshop != null and is_instance_valid(workshop):
		if workshop.has_method("is_camera_navigating") and bool(workshop.is_camera_navigating()):
			cam_busy = true
		if not cam_busy and workshop.has_method("get_orbit"):
			var orb: Vector2 = workshop.get_orbit()
			if absf(orb.x - _dense_3d_cam_yaw) > 0.0005 or absf(orb.y - _dense_3d_cam_pitch) > 0.0005:
				cam_busy = true
				_dense_3d_cam_yaw = orb.x
				_dense_3d_cam_pitch = orb.y
		# Fly: сдвиг позиции камеры (WASD) без смены yaw/pitch.
		if not cam_busy and workshop.has_method("get_camera_world_pos"):
			var cpos: Vector3 = workshop.get_camera_world_pos() as Vector3
			if cpos.distance_squared_to(_dense_3d_cam_pos) > 1.0e-8:
				cam_busy = true
				_dense_3d_cam_pos = cpos
	if cam_busy or (workshop != null and workshop.has_method("_drag_locks_hover") and workshop._drag_locks_hover()):
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	# Только полный покой: 3D реже. Движение камеры всегда ALWAYS (иначе «мыльный» строб).
	var period: int = 2
	if circuit != null and bool(circuit.running) and not bool(circuit.pressure_viz):
		period = 3
	if (Engine.get_process_frames() % period) == 0:
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED


## После правок агент пишет путь в res://test/.agent_review_scene и запускает игру.
func _try_auto_open_review_scene() -> void:
	var path: String = ""
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("--open="):
			path = a.substr(7).strip_edges()
		elif a.ends_with(".msim") or a.ends_with(".mechsim.json") or a.ends_with(".json"):
			path = a.strip_edges()
	var marker := "res://test/.agent_review_scene"
	if path == "" and FileAccess.file_exists(marker):
		var f := FileAccess.open(marker, FileAccess.READ)
		if f != null:
			path = f.get_as_text().strip_edges()
			f.close()
		# Одноразово: не открывать эту же сцену при каждом следующем F5.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	if path == "":
		return
	if not open_scene_path(path):
		return
	# Демо/ревью: раскладку из файла не трогаем. Одноразовый маркер — прогон прототипа коридоров.
	WireRouter2D.invalidate()
	_redraw_schematic()
	var route_flag := "res://test/.agent_autoroute"
	if FileAccess.file_exists(route_flag):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(route_flag))
		_arrange_schematic()
	# 3D + пролёт (WASD), не орбита — иначе клавиши «мёртвые» до переключения режима.
	_show_2d = true
	_show_3d = true
	_rebuild_main_split()
	_refresh_view_buttons()
	if workshop != null and is_instance_valid(workshop):
		if workshop.has_method("clear_hose_geom_cache"):
			workshop.clear_hose_geom_cache()
		if workshop.has_method("set_cam_mode"):
			workshop.set_cam_mode("fly")
		# Демо дросселя / ОК — камера на Z1, не на щит.
		if path.contains("throttle") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.35, 1.38, 0.0), Vector3(0.55, 1.46, 0.18))
		elif path.contains("check") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.38, 1.38, 0.0), Vector3(0.62, 1.48, 0.22))
		elif path.contains("pc_fittings") and workshop.has_method("aim_review_point"):
			# Три ПЦ: камера на крупный 3A (Ø63 · трубка Ø10) — гибы видны сразу.
			workshop.aim_review_point(Vector3(0.45, 1.42, -0.35), Vector3(0.85, 1.55, -0.05))
		elif path.contains("valve_sizes") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.45, 1.42, 0.0), Vector3(0.9, 1.55, 0.25))
		elif path.contains("armature_sizes") and workshop.has_method("aim_review_point"):
			# Тройник Ø6 · дроссель Ø10 · ОК Ø12 — разница масштаба сразу видна.
			workshop.aim_review_point(Vector3(0.45, 1.42, 0.0), Vector3(0.95, 1.55, 0.35))
		elif path.contains("pneumo_review") and workshop.has_method("aim_review_point"):
			# ОК с выхлопом + тройник — шевроны/конусы и перепад давления сразу в кадре.
			workshop.aim_review_point(Vector3(0.35, 1.40, 0.15), Vector3(0.75, 1.52, 0.35))
		elif path.contains("reservoir") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.35, 1.38, -0.15), Vector3(0.85, 1.55, 0.15))
		elif path.contains("regulator") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.35, 1.40, 0.0), Vector3(0.75, 1.58, 0.25))
		elif path.contains("junction_atm") and workshop.has_method("aim_review_point"):
			# Тройник со свободными штуцерами — выхлоп в атмосферу в кадре.
			workshop.aim_review_point(Vector3(0.2, 1.38, 0.1), Vector3(0.55, 1.5, 0.28))
		elif path.contains("quick_exhaust") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.32, 1.38, 0.0), Vector3(0.72, 1.55, 0.28))
		elif path.contains("relief") and workshop.has_method("aim_review_point"):
			# Сбоку: рычаг + винт сверху + окно пружины.
			workshop.aim_review_point(Vector3(0.42, 1.40, 0.0), Vector3(0.78, 1.52, 0.22))
		elif path.contains("shuttle") and workshop.has_method("aim_review_point"):

			# КМ + две 3/2 кнопки + ИЛИ по центру — чтобы жать Р1/Р2 и видеть шарик.
			workshop.aim_review_point(Vector3(0.28, 1.38, 0.05), Vector3(0.85, 1.55, 0.45))
		elif path.contains("shutoff") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.32, 1.38, 0.0), Vector3(0.7, 1.55, 0.25))
		elif path.contains("and_valve_regulators") and workshop.has_method("aim_review_point"):
			# КР1/КР2 + И по центру — крутить уставки и смотреть гантель/выхлоп 3.
			workshop.aim_review_point(Vector3(0.7, 1.38, 0.0), Vector3(1.05, 1.52, 0.35))
		elif path.contains("and_valve") and workshop.has_method("aim_review_point"):
			workshop.aim_review_point(Vector3(0.45, 1.36, 0.0), Vector3(0.45, 1.42, 0.09))
		elif path.contains("rotary_vane") and workshop.has_method("aim_review_point"):
			# Лопастной ППЦ: корпус, лопасть, упор и порты спереди.
			workshop.aim_review_point(Vector3(1.0, 1.40, 1.35), Vector3(1.25, 1.58, 1.70))
		elif path.contains("rotary") and workshop.has_method("aim_review_point"):
			# ППЦ рейка–шестерня: спереди-сверху — торец шестерни/вала и каналы.
			workshop.aim_review_point(Vector3(1.0, 1.40, 1.35), Vector3(1.22, 1.62, 1.72))
		elif path.contains("air_motor") and workshop.has_method("aim_review_point"):
			# Шестерённый ПМ: stadium-корпус, зацепление и каналы слева/справа.
			workshop.aim_review_point(Vector3(0.75, 1.40, 1.35), Vector3(1.20, 1.65, 1.90))
		elif path.contains("thermal_short") and workshop.has_method("aim_review_cabinet"):
			# Щит с КЗ — камера на DIN / жилы.
			workshop.aim_review_cabinet()
		elif path.contains("thermal_viz") and workshop.has_method("aim_review_point"):
			# Крупный ПЦ с автоходом — смотреть нагрев корпуса.
			workshop.aim_review_point(Vector3(0.85, 1.40, 0.05), Vector3(1.25, 1.58, 0.45))
		elif path.contains("sensor_rtd") and workshop.has_method("aim_review_point"):
			# Зонды ТС + кабель к щиту.
			workshop.aim_review_point(Vector3(0.30, 1.40, 0.55), Vector3(0.55, 1.55, 0.95))
		elif path.contains("sensor") and workshop.has_method("aim_review_point"):
			# Индуктивный БВ + алюминиевый ПЦ в зоне Sn + кабель к gland.
			workshop.aim_review_point(Vector3(0.45, 1.42, 0.18), Vector3(0.85, 1.55, 0.55))
		elif workshop.has_method("aim_review_cabinet"):
			workshop.aim_review_cabinet()
		# Ревью-демо: режимы viz до пуска (иначе КЗ успеет выбить АВ до тепловизора).
		if path.contains("demo_") and circuit != null:
			if path.contains("thermal_viz") or path.contains("thermal_short") \
					or path.contains("sensor_rtd") \
					or path.contains("demo_sensor_rtd") or path.contains("pneumo_review") \
					or path.contains("demo_throttle"):
				_set_thermal_viz(true)
			# КЗ-демо: АВ в I (Reset всегда оставляет АВ в O).
			if path.contains("thermal_short"):
				agent_arm_thermal_short()
				# running уже включён в arm — не дублировать ниже для этого файла.
			if path.contains("sensor"):
				_set_sensor_field_viz(true)
			# Выхлоп/конусы сразу видны на демо открытых портов (без принудительного рентгена).
			if path.contains("junction_atm") or path.contains("pneumo_review") or path.contains("shuttle"):
				_set_pressure_viz(true)
				if workshop.has_method("set_xray"):
					workshop.set_xray(false)
				if _btn_xray != null:
					_btn_xray.set_pressed_no_signal(false)
					_style_toggle_button(_btn_xray, false)
			# Клапан «И» / предохранительный / поворотный ПЦ: сразу рентген — внутренности.
			if path.contains("and_valve") or path.contains("relief") or path.contains("rotary") \
					or path.contains("air_motor"):
				if workshop.has_method("set_xray"):
					workshop.set_xray(true)
				if _btn_xray != null:
					_btn_xray.set_pressed_no_signal(true)
					_style_toggle_button(_btn_xray, true)
				_set_pressure_viz(true)
				if _btn_pressure != null:
					_btn_pressure.set_pressed_no_signal(true)
					_style_toggle_button(_btn_pressure, true)
			if not path.contains("thermal_short"):
				circuit.running = true
				_sync_play_button()
				if schematic != null and schematic.has_method("refresh_sim_edit_lock"):
					schematic.refresh_sim_edit_lock()
		# Фокус клавиатуры на оверлей 3D — WASD сразу после старта.
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.grab_focus()


func _export_pdf_2d(path: String) -> void:
	if schematic == null:
		return
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	if full == null:
		circuit.notify("Не удалось захватить схему")
		return
	var r := schematic.get_global_rect()
	var region := Rect2i(Vector2i(r.position), Vector2i(r.size))
	region = region.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if region.size.x < 8 or region.size.y < 8:
		circuit.notify("Область схемы слишком мала")
		return
	var img := full.get_region(region)
	if not path.to_lower().ends_with(".pdf"):
		path += ".pdf"
	var err := PdfExport.save_image_pdf(img, path, "MechSim 2D")
	if err != OK:
		circuit.notify("Ошибка экспорта PDF (%d)" % err)
	else:
		circuit.notify("PDF схемы: %s" % path.get_file())


func _export_pdf_3d(path: String) -> void:
	if _view == null:
		return
	await RenderingServer.frame_post_draw
	var tex := _view.get_texture()
	if tex == null:
		circuit.notify("Не удалось захватить 3D вид")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		circuit.notify("Пустой кадр 3D")
		return
	if not path.to_lower().ends_with(".pdf"):
		path += ".pdf"
	var err := PdfExport.save_image_pdf(img, path, "MechSim 3D")
	if err != OK:
		circuit.notify("Ошибка экспорта PDF (%d)" % err)
	else:
		circuit.notify("PDF 3D: %s" % path.get_file())


## Для агента: диагностика барьерной/волоконной оптики (PV/SET/геометрия tip).
func agent_optical_probe(el_id: int = -1) -> Dictionary:
	var Detect = preload("res://scripts/domain/sensor_detection.gd")
	var out: Dictionary = {"ok": false, "sensors": []}
	if circuit == null:
		return out
	out["ok"] = true
	out["running"] = bool(circuit.running)
	for el in circuit.elements:
		if el == null or str(el.kind) != "sensor" or str(el.sensor_class) != "optical":
			continue
		if str(el.optical_form) == "compact":
			continue
		if el_id >= 0 and int(el.id) != el_id:
			continue
		var mode: String = Detect.optical_mode(circuit, el)
		var pv: int = Detect.optical_signal_level(circuit, el)
		var set_n: int = clampi(
			int(round(clampf(float(el.threshold_pct), 0.0, 100.0) * 9.99)), 0, 999
		)
		var tips: Array = Detect.linked_opto_tips(circuit, el)
		var tip_info: Array = []
		for t in tips:
			var face: Vector3 = Detect._tip_face_world(t)
			var axis: Vector3 = Detect._tip_axis_world(t)
			tip_info.append({
				"id": int(t.id),
				"tag": str(t.tag),
				"role": str(t.opto_role),
				"pos": [float(t.world_pos.x), float(t.world_pos.y), float(t.world_pos.z)],
				"face": [face.x, face.y, face.z],
				"axis": [axis.x, axis.y, axis.z],
			})
		var detail: Dictionary = {}
		if mode == "barrier":
			var tx = Detect._first_tip_role(tips, "emitter")
			var rx = Detect._first_tip_role(tips, "receiver")
			if tx != null and rx != null:
				var a: Vector3 = Detect._tip_face_world(tx)
				var b: Vector3 = Detect._tip_face_world(rx)
				var tax: Vector3 = Detect._tip_axis_world(tx)
				var rax: Vector3 = Detect._tip_axis_world(rx)
				var along: float = (b - a).dot(tax)
				var miss: float = (a + tax * along).distance_to(b) if along > 0.0 else -1.0
				var beam_r: float = 0.0035 + maxf(along, 0.0) * 0.016
				var dist_q: float = 1.0 / (1.0 + maxf(along, 0.0) * maxf(along, 0.0) * 3.0)
				var own_pv: int = Detect._optical_src_beam_pv(circuit, el, tx, rx)
				var foreign_pv: int = Detect._optical_foreign_beams_pv(circuit, el, rx, int(tx.id))
				detail = {
					"along_m": along,
					"miss_m": miss,
					"beam_r_m": beam_r,
					"rx_face": rax.dot(-tax),
					"dist_q": dist_q,
					"tx_axis": [tax.x, tax.y, tax.z],
					"rx_axis": [rax.x, rax.y, rax.z],
					"occ": Detect._ray_hit_first_occluder(circuit, el, tx, rx, a, tax, maxf(along, 0.01)),
					"own_pv": own_pv,
					"foreign_pv": foreign_pv,
				}
		out["sensors"].append({
			"id": int(el.id),
			"tag": str(el.tag),
			"mode": mode,
			"pv": pv,
			"set": set_n,
			"lo": bool(el.optical_light_on),
			"pressed": bool(el.pressed),
			"powered": bool(el.sensor_powered),
			"threshold_pct": float(el.threshold_pct),
			"amp_pos": [float(el.world_pos.x), float(el.world_pos.y), float(el.world_pos.z)],
			"tips": tip_info,
			"barrier": detail,
		})
	return out


## Демо КЗ: тепловизор + АВ в I + Run (после open_scene_path).
func agent_arm_thermal_short() -> Dictionary:
	var out: Dictionary = {"ok": false}
	if circuit == null:
		return out
	var ElecN = preload("res://scripts/domain/electrical_network.gd")
	ElecN.clear_protection_state()
	_set_thermal_viz(true)
	var n_qf: int = 0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) in ["mcb", "rcd", "rcbo"]:
			el.closed = true
			n_qf += 1
	if n_qf > 0 and circuit.has_method("bump_scheme_control"):
		circuit.bump_scheme_control()
	circuit.running = true
	if schematic != null and schematic.has_method("notify_sim_control_changed"):
		schematic.notify_sim_control_changed()
	_sync_play_button()
	if schematic != null and schematic.has_method("refresh_sim_edit_lock"):
		schematic.refresh_sim_edit_lock()
	if workshop != null and workshop.has_method("aim_review_cabinet"):
		workshop.aim_review_cabinet()
	# Один шаг сразу — проверить КЗ/ток до следующего кадра.
	ElecN.step(circuit, 0.05)
	var ThermalV0 = preload("res://scripts/domain/thermal_viz.gd")
	ThermalV0.advance(circuit, 0.05)
	out["ok"] = true
	out["breakers_closed"] = n_qf
	out["running"] = bool(circuit.running)
	out["thermal_viz"] = bool(circuit.thermal_viz)
	out["electro_short"] = bool(circuit.electro_short)
	out["electro_fault_a"] = float(circuit.electro_fault_a)
	if not circuit.wires.is_empty() and circuit.wires[0] != null:
		out["i0"] = float(circuit.call("_electro_wire_current_a", circuit.wires[0]))
		out["t0"] = float(ThermalV0.wire_temp_c(circuit, circuit.wires[0]))
	return out


## Диагностика тепловизора: флаг + шкала мин/макс.
func agent_thermal_probe() -> Dictionary:
	var out: Dictionary = {"ok": false, "thermal_viz": false, "range": {}}
	if circuit == null:
		return out
	out["ok"] = true
	out["thermal_viz"] = bool(circuit.thermal_viz)
	out["running"] = bool(circuit.running)
	out["electro_short"] = bool(circuit.electro_short)
	out["electro_fault_a"] = float(circuit.electro_fault_a)
	var nodes_dbg: Dictionary = {}
	for nk in circuit.electro_nodes.keys():
		var nks: String = str(nk)
		var info = circuit.electro_nodes[nk]
		nodes_dbg[nks] = {
			"v": float(info.get("v", 0.0)) if typeof(info) == TYPE_DICTIONARY else 0.0,
			"fixed": bool(info.get("fixed", false)) if typeof(info) == TYPE_DICTIONARY else false,
			"driven": bool(info.get("driven", false)) if typeof(info) == TYPE_DICTIONARY else false,
		}
	out["nodes"] = nodes_dbg
	var wmeta: Array = []
	for w in circuit.wires:
		if w == null:
			continue
		wmeta.append({
			"id": int(w.id),
			"a": "%d:%s" % [int(w.a_id), str(w.a_port)],
			"b": "%d:%s" % [int(w.b_id), str(w.b_port)],
			"dom": str(circuit.port_domain(circuit.get_element(int(w.a_id)), str(w.a_port))),
		})
	out["wire_meta"] = wmeta
	if workshop != null and is_instance_valid(workshop) and workshop.has_method("thermal_legend_range"):
		out["range"] = workshop.thermal_legend_range()
	else:
		var ThermalV = preload("res://scripts/domain/thermal_viz.gd")
		out["range"] = ThermalV.scene_range_c(circuit)
	out["legend_visible"] = _thermal_legend != null and is_instance_valid(_thermal_legend) and _thermal_legend.visible
	var ThermalVp = preload("res://scripts/domain/thermal_viz.gd")
	var wires_info: Array = []
	for w in circuit.wires:
		if w == null:
			continue
		wires_info.append({
			"id": int(w.id),
			"t_c": float(ThermalVp.wire_temp_c(circuit, w)),
			"p_w": float(ThermalVp.wire_heat_power_w(circuit, w)),
			"i_a": float(circuit.call("_electro_wire_current_a", w)),
			"sec": float(w.id_mm),
		})
	out["wires"] = wires_info
	var brk: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) not in ["mcb", "rcd", "rcbo"]:
			continue
		brk.append({"tag": str(el.tag), "closed": bool(el.closed), "rating_a": float(el.rating_a)})
	out["breakers"] = brk
	return out


## Диагностика ТС B3: питание вторички, R/T, схема жил.
func agent_rtd_probe(el_id: int = -1) -> Dictionary:
	var Detect = preload("res://scripts/domain/sensor_detection.gd")
	var out: Dictionary = {"ok": false, "running": false, "sensors": []}
	if circuit == null:
		return out
	out["ok"] = true
	out["running"] = bool(circuit.running)
	for el in circuit.elements:
		if el == null or str(el.kind) != "sensor" or str(el.sensor_class) != "rtd":
			continue
		if el_id >= 0 and int(el.id) != el_id:
			continue
		var snap: Dictionary = Detect.rtd_probe_snapshot(circuit, el)
		var meter_id: int = -1
		var meter_ports: Array = []
		for m in circuit.electro_group_members(int(el.id)):
			if str(m.member_role) == "device" and str(m.electro_class) == "rtd_meter":
				meter_id = int(m.id)
				for p in m.electro_ports:
					meter_ports.append(str(p.get("name", "")))
				break
		var core_wires: Array = []
		for w in circuit.wires:
			if w == null:
				continue
			var a_s: bool = int(w.a_id) == int(el.id)
			var b_s: bool = int(w.b_id) == int(el.id)
			if not a_s and not b_s:
				continue
			core_wires.append({
				"num": int(w.num),
				"id": int(w.id),
				"port": str(w.a_port) if a_s else str(w.b_port),
				"to": int(w.b_id) if a_s else int(w.a_id),
				"length_m": float(w.length_m),
			})
		var disp_text: String = ""
		if workshop != null and is_instance_valid(workshop) and meter_id >= 0 \
				and workshop.has_method("_electro_port_root"):
			var mroot: Node3D = workshop.call("_electro_port_root", meter_id) as Node3D
			if mroot != null:
				var lab: Label3D = mroot.get_node_or_null("RtdDisp/Text") as Label3D
				if lab != null:
					disp_text = str(lab.text)
		out["sensors"].append({
			"id": int(el.id),
			"tag": str(el.tag),
			"scheme": int(el.wire_scheme),
			"powered": bool(el.sensor_powered),
			"lit": bool(el.lit),
			"analog_value": float(el.analog_value),
			"temperature_c": float(el.temperature_c),
			"meter_id": meter_id,
			"meter_ports": meter_ports,
			"core_wires": core_wires,
			"disp_text": disp_text,
			"snap": snap,
		})
	return out


## Для агента: выставить opening аксессуара (0…1).
func agent_set_opening(el_id: int, opening: float) -> void:
	var el = circuit.get_element(int(el_id))
	if el == null:
		return
	el.opening = clampf(float(opening), 0.0, 1.0)
	circuit.touch_scene()


## Для агента: уставка редуктора, бар.
func agent_set_pressure_bar(el_id: int, bar: float) -> void:
	var el = circuit.get_element(int(el_id))
	if el == null:
		return
	el.set_pressure_bar = clampf(float(bar), 0.0, 16.0)
	circuit.touch_scene()


## Принудительно зажечь хвост viz сброса (проверка 3D-конусов).
func agent_force_relief_trail(el_id: int = 2, seconds: float = 0.55) -> void:
	circuit.relief_trail_s[int(el_id)] = maxf(float(seconds), 0.05)


func agent_set_hover(space: String, el_id: int, port: String = "", wire_id: int = -1) -> void:
	if circuit == null:
		return
	circuit.set_hover(space, el_id, port, wire_id)


## Удержание органа ПР на схеме (как зажатая кнопка) — для проверки FPS.
func agent_actuate_valve(el_id: int, side: String = "left", on: bool = true) -> void:
	if circuit == null:
		return
	var el = circuit.get_element(el_id)
	if el == null or str(el.kind) != "valve":
		return
	if on:
		if side == "right":
			el.command_right = true
			el.command_left = false
		else:
			el.command_left = true
			el.command_right = false
	else:
		el.command_left = false
		el.command_right = false
	if circuit.has_method("refresh_valve_pos"):
		circuit.refresh_valve_pos(el)
	if schematic != null and is_instance_valid(schematic) and schematic.has_method("agent_set_actuate_hold"):
		schematic.agent_set_actuate_hold(el_id, side, on)


## Сводка нагрузки для агента (FPS / step / 2D / 3D).
func agent_perf_report() -> Dictionary:
	var ms_draw: float = 0.0
	if schematic != null and schematic.has_method("perf_ms_draw"):
		ms_draw = schematic.perf_ms_draw()
	var ms_mach: float = 0.0
	var ms_hose: float = 0.0
	if workshop != null and is_instance_valid(workshop):
		if workshop.get("_perf_ms_machines") != null:
			ms_mach = float(workshop.get("_perf_ms_machines"))
		if workshop.get("_perf_ms_hoses") != null:
			ms_hose = float(workshop.get("_perf_ms_hoses"))
	var draw_dbg: Dictionary = {}
	if schematic != null and schematic.has_method("perf_draw_debug"):
		draw_dbg = schematic.perf_draw_debug()
	return {
		"fps": Engine.get_frames_per_second(),
		"running": bool(circuit.running) if circuit != null else false,
		"ms_step": circuit.perf_ms_step() if circuit != null and circuit.has_method("perf_ms_step") else 0.0,
		"ms_draw": ms_draw,
		"ms_machines": ms_mach,
		"ms_hoses": ms_hose,
		"elements": circuit.elements.size() if circuit != null else 0,
		"wires": circuit.wires.size() if circuit != null else 0,
		"hover_space": str(circuit.hover_space) if circuit != null else "",
		"hover_el": int(circuit.hover_el_id) if circuit != null else -1,
		"draw_dbg": draw_dbg,
	}


## Давления/уставки для проверки симуляции (редуктор и т.п.).
func agent_pressure_report() -> Dictionary:
	var els: Array = []
	for el in circuit.elements:
		if el == null:
			continue
		var row: Dictionary = {
			"id": int(el.id),
			"tag": str(el.tag),
			"kind": str(el.kind),
		}
		if str(el.kind) == "source":
			row["src_bar"] = snappedf(float(el.pressure_bar), 0.01)
		if str(el.kind) == "accessory":
			row["cls"] = str(el.accessory_class)
			row["set_bar"] = snappedf(float(el.set_pressure_bar), 0.01)
			row["opening"] = snappedf(float(el.opening), 0.01)
			if str(el.accessory_class) in ["regulator", "frl"]:
				row["relief"] = bool(circuit.regulator_relief_active(int(el.id)))
		var pb: Dictionary = {}
		if el.get("port_press") != null:
			for k in el.port_press.keys():
				pb[str(k)] = snappedf((float(el.port_press[k]) - 101325.0) / 1.0e5, 0.01)
		row["p_bar"] = pb
		els.append(row)
	var ws: Array = []
	for w in circuit.wires:
		ws.append({
			"id": int(w.id),
			"num": int(w.num),
			"a": "%d.%s" % [int(w.a_id), str(w.a_port)],
			"b": "%d.%s" % [int(w.b_id), str(w.b_port)],
			"p_bar": snappedf((float(w.pressure) - 101325.0) / 1.0e5, 0.01),
			"q_nl_min": snappedf(float(w.flow_vis) * 60000.0, 0.1),
		})
	return {
		"running": bool(circuit.running),
		"sim_time": snappedf(float(circuit.sim_time), 0.01),
		"elements": els,
		"wires": ws,
	}


## Снимок визуализации для агента (расходы, выхлоп ATM, opening ОК).
## Принудительно сбросить joints у жил по номеру/id (напр. [2]).
func agent_set_el_pose(el_id: int, x: float, y: float, rot_quad: int = 0) -> bool:
	var el = circuit.get_element(int(el_id))
	if el == null:
		return false
	el.position = Vector2(x, y)
	el.rotation_quad = int(rot_quad)
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	WireRouter2D.invalidate()
	if schematic != null and schematic.has_method("redraw_scheme"):
		schematic.redraw_scheme()
	return true


func agent_clear_wire_joints(nums: Array = []) -> Dictionary:
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var want: Dictionary = {}
	for n in nums:
		want[int(n)] = true
	var cleared: Array = []
	for w in circuit.wires:
		var num: int = int(w.num) if w.get("num") != null else -1
		if not want.is_empty() and not want.has(num) and not want.has(int(w.id)):
			continue
		var joints: Array = w.joints if typeof(w.joints) == TYPE_ARRAY else []
		if joints.is_empty():
			continue
		w.joints.clear()
		WireRouter2D.invalidate_wire(int(w.id))
		cleared.append({"id": int(w.id), "num": num})
	if not cleared.is_empty():
		WireRouter2D.invalidate()
		if schematic != null and schematic.has_method("redraw_scheme"):
			schematic.redraw_scheme()
		circuit.touch_scene()
	return {"cleared": cleared, "n": cleared.size()}


func agent_heal_loopy_wires(tags: Array = []) -> Dictionary:
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var want: Dictionary = {}
	for t in tags:
		want[str(t)] = true
	var cleared: Array = []
	for w in circuit.wires:
		var el_a = circuit.get_element(int(w.a_id))
		var el_b = circuit.get_element(int(w.b_id))
		if el_a == null or el_b == null:
			continue
		var ta: String = str(el_a.tag)
		var tb: String = str(el_b.tag)
		if not want.is_empty():
			var hit: bool = want.has(ta) or want.has(tb)
			if not hit:
				for k in want.keys():
					var ks: String = str(k)
					if ta.begins_with(ks) or tb.begins_with(ks):
						hit = true
						break
			if not hit:
				continue
		var joints: Array = w.joints if typeof(w.joints) == TYPE_ARRAY else []
		if joints.is_empty():
			continue
		var pa: Dictionary = Geom.port_by_name(el_a, str(w.a_port))
		var pb: Dictionary = Geom.port_by_name(el_b, str(w.b_port))
		if pa.is_empty() or pb.is_empty():
			continue
		var tip_a: Vector2 = Geom.to_world(el_a, pa["local"] as Vector2)
		var tip_b: Vector2 = Geom.to_world(el_b, pb["local"] as Vector2)
		var manh: float = absf(tip_a.x - tip_b.x) + absf(tip_a.y - tip_b.y)
		var pts: PackedVector2Array = Geom.polyline(el_a, str(w.a_port), el_b, str(w.b_port), joints)
		var plen: float = Geom.path_length_px(pts)
		var g: float = Geom.SCH_GRID
		var loopy: bool = plen > manh * 1.85 + g * 6.0
		if not loopy and joints.size() >= 2:
			var bb: Rect2 = Rect2(tip_a, Vector2.ZERO).expand(tip_b).grow(g * 1.5)
			var outside: int = 0
			for j in joints:
				if typeof(j) == TYPE_VECTOR2 and not bb.has_point(j as Vector2):
					outside += 1
			if outside >= 2 and plen > manh * 1.35 + g * 4.0:
				loopy = true
		# Соосные tip навстречу + лишние суставы («ступенька» L↔QF).
		if not loopy and joints.size() >= 1:
			var na: Vector2 = (pa["normal"] as Vector2).rotated(float(el_a.rotation_quad) * PI * 0.5)
			var nb: Vector2 = (pb["normal"] as Vector2).rotated(float(el_b.rotation_quad) * PI * 0.5)
			var same_col: bool = absf(tip_a.x - tip_b.x) <= g * 0.51
			var same_row: bool = absf(tip_a.y - tip_b.y) <= g * 0.51
			if same_col and absf(na.x) < 0.5 and absf(nb.x) < 0.5:
				var dy: float = tip_b.y - tip_a.y
				if absf(dy) > g * 0.5 and dy * na.y > 0.5 and (-dy) * nb.y > 0.5:
					loopy = true
			elif same_row and absf(na.y) < 0.5 and absf(nb.y) < 0.5:
				var dx: float = tip_b.x - tip_a.x
				if absf(dx) > g * 0.5 and dx * na.x > 0.5 and (-dx) * nb.x > 0.5:
					loopy = true
		if not loopy:
			for i in range(pts.size() - 2):
				var ab: Vector2 = pts[i + 1] - pts[i]
				var bc: Vector2 = pts[i + 2] - pts[i + 1]
				if ab.dot(bc) < -0.01 and minf(ab.length(), bc.length()) > g * 0.9:
					loopy = true
					break
		if not loopy:
			continue
		w.joints.clear()
		WireRouter2D.invalidate_wire(int(w.id))
		cleared.append({
			"id": int(w.id),
			"a_tag": ta,
			"b_tag": tb,
			"plen": snappedf(plen, 0.1),
			"manh": snappedf(manh, 0.1),
		})
	if not cleared.is_empty():
		WireRouter2D.invalidate()
		if schematic != null and schematic.has_method("redraw_scheme"):
			schematic.redraw_scheme()
		circuit.touch_scene()
	return {"cleared": cleared, "n": cleared.size()}


func agent_wire_gap_diag(nums: Array = []) -> Dictionary:
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	WireRouter2D.invalidate()
	var want: Dictionary = {}
	for n in nums:
		want[int(n)] = true
	var out: Array = []
	for w in circuit.wires:
		var num: int = int(w.num) if w.get("num") != null else 0
		if not want.is_empty() and not want.has(num) and not want.has(int(w.id)):
			continue
		var el_a = circuit.get_element(int(w.a_id))
		var el_b = circuit.get_element(int(w.b_id))
		var tip_a := Vector2.ZERO
		var tip_b := Vector2.ZERO
		if el_a != null:
			var pa: Dictionary = Geom.port_by_name(el_a, str(w.a_port))
			if not pa.is_empty():
				tip_a = Geom.to_world(el_a, pa["local"] as Vector2)
		if el_b != null:
			var pb: Dictionary = Geom.port_by_name(el_b, str(w.b_port))
			if not pb.is_empty():
				tip_b = Geom.to_world(el_b, pb["local"] as Vector2)
		var pts: PackedVector2Array = WireRouter2D.path_for(circuit, w)
		var diag_segs: Array = []
		for i in range(pts.size() - 1):
			var ddx: float = absf(pts[i].x - pts[i + 1].x)
			var ddy: float = absf(pts[i].y - pts[i + 1].y)
			if ddx > 0.75 and ddy > 0.75:
				diag_segs.append([i, [snappedf(pts[i].x, 0.01), snappedf(pts[i].y, 0.01)], [snappedf(pts[i + 1].x, 0.01), snappedf(pts[i + 1].y, 0.01)]])
		var forced: PackedVector2Array = Geom.simplify_ortho_path(Geom._dedupe(Geom._ortho(pts)))
		var forced_xy: Array = []
		for i in forced.size():
			forced_xy.append([snappedf(forced[i].x, 0.01), snappedf(forced[i].y, 0.01)])
		var path_xy: Array = []
		for i in pts.size():
			path_xy.append([snappedf(pts[i].x, 0.01), snappedf(pts[i].y, 0.01)])
		var jxy: Array = []
		for j in w.joints:
			if typeof(j) == TYPE_VECTOR2:
				jxy.append([snappedf((j as Vector2).x, 0.01), snappedf((j as Vector2).y, 0.01)])
		var gap_a: float = -1.0
		var gap_b: float = -1.0
		if pts.size() >= 1:
			gap_a = pts[0].distance_to(tip_a)
		if pts.size() >= 2:
			gap_b = pts[pts.size() - 1].distance_to(tip_b)
		var na := Vector2.ZERO
		var nb := Vector2.ZERO
		var ra: int = 0
		var rb: int = 0
		if el_a != null:
			ra = int(el_a.rotation_quad)
			var pda: Dictionary = Geom.port_by_name(el_a, str(w.a_port))
			if not pda.is_empty():
				na = (pda["normal"] as Vector2).rotated(float(ra) * PI * 0.5)
		if el_b != null:
			rb = int(el_b.rotation_quad)
			var pdb: Dictionary = Geom.port_by_name(el_b, str(w.b_port))
			if not pdb.is_empty():
				nb = (pdb["normal"] as Vector2).rotated(float(rb) * PI * 0.5)
		out.append({
			"id": int(w.id),
			"num": num,
			"a": "%d.%s" % [int(w.a_id), str(w.a_port)],
			"b": "%d.%s" % [int(w.b_id), str(w.b_port)],
			"a_tag": str(el_a.tag) if el_a else "",
			"b_tag": str(el_b.tag) if el_b else "",
			"a_pos": [el_a.position.x, el_a.position.y] if el_a else [],
			"b_pos": [el_b.position.x, el_b.position.y] if el_b else [],
			"a_rot": ra,
			"b_rot": rb,
			"an": [snappedf(na.x, 0.01), snappedf(na.y, 0.01)],
			"bn": [snappedf(nb.x, 0.01), snappedf(nb.y, 0.01)],
			"tip_a": [snappedf(tip_a.x, 0.01), snappedf(tip_a.y, 0.01)],
			"tip_b": [snappedf(tip_b.x, 0.01), snappedf(tip_b.y, 0.01)],
			"gap_a": snappedf(gap_a, 0.01),
			"gap_b": snappedf(gap_b, 0.01),
			"joints": jxy,
			"path": path_xy,
			"diag_segs": diag_segs,
			"forced_ortho": forced_xy,
			"color": str(w.color_id),
		})
	return {"wires": out}


func agent_viz_dump() -> Dictionary:
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	var Geom = preload("res://scripts/domain/symbol_geom.gd")
	var wires_out: Array = []
	for w in circuit.wires:
		var pts: PackedVector2Array = WireRouter2D.path_for(circuit, w)
		var path_xy: Array = []
		for i in pts.size():
			path_xy.append([pts[i].x, pts[i].y])
		var tip_a_off: bool = false
		var tip_b_off: bool = false
		if pts.size() >= 2:
			var g: float = Geom.SCH_GRID
			tip_a_off = fposmod(absf(pts[0].x), g) > 0.05 and fposmod(absf(pts[0].x), g) < g - 0.05 \
				or fposmod(absf(pts[0].y), g) > 0.05 and fposmod(absf(pts[0].y), g) < g - 0.05
			var last: Vector2 = pts[pts.size() - 1]
			tip_b_off = fposmod(absf(last.x), g) > 0.05 and fposmod(absf(last.x), g) < g - 0.05 \
				or fposmod(absf(last.y), g) > 0.05 and fposmod(absf(last.y), g) < g - 0.05
		var curve3: Array = []
		var kink3: float = 0.0
		if workshop != null and is_instance_valid(workshop) and workshop.get("_hose_nodes") != null:
			var hn: Dictionary = workshop.get("_hose_nodes") as Dictionary
			var node: Node3D = hn.get(int(w.id), null) as Node3D
			if node != null and node.has_meta("curve_pts"):
				var c3: PackedVector3Array = node.get_meta("curve_pts") as PackedVector3Array
				for j in mini(c3.size(), 24):
					curve3.append([snappedf(c3[j].x, 0.001), snappedf(c3[j].y, 0.001), snappedf(c3[j].z, 0.001)])
				if c3.size() >= 24:
					curve3.append(["…", c3.size()])
				# Макс. излом: 1 − |t0·t1| на соседних сегментах (1 = 90°+).
				for k in range(1, c3.size() - 1):
					var t0: Vector3 = c3[k] - c3[k - 1]
					var t1: Vector3 = c3[k + 1] - c3[k]
					if t0.length_squared() < 1.0e-12 or t1.length_squared() < 1.0e-12:
						continue
					var ang: float = 1.0 - absf(t0.normalized().dot(t1.normalized()))
					kink3 = maxf(kink3, ang)
		wires_out.append({
			"id": int(w.id),
			"a": "%d.%s" % [int(w.a_id), str(w.a_port)],
			"b": "%d.%s" % [int(w.b_id), str(w.b_port)],
			"od_mm": float(w.od_mm),
			"id_mm": float(w.id_mm),
			"length_m": float(w.length_m),
			"length_used_m": float(circuit._wire_path_length_m(w)),
			"vol_cm3": float(circuit._wire_volume(w)) * 1.0e6,
			"flow_m3s": float(w.flow_m3s),
			"flow_vis": float(w.flow_vis),
			"flow_sign": float(w.flow_sign),
			"flow_phase": float(w.flow_phase),
			"p_bar": (float(w.pressure) - 101325.0) / 1.0e5,
			"path": path_xy,
			"tip_off_grid": tip_a_off or tip_b_off,
			"curve3_head": curve3,
			"kink3": snappedf(kink3, 0.001),
		})
	var ports_out: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) in ["electro", "coil", "rail"]:
			continue
		var item: Dictionary = {
			"id": int(el.id),
			"kind": str(el.kind),
			"tag": str(el.tag),
			"opening": float(el.opening) if el.get("opening") != null else -1.0,
		}
		if str(el.kind) == "accessory":
			item["cls"] = str(el.accessory_class)
			item["set_bar"] = float(el.set_pressure_bar)
		if str(el.kind) == "source":
			item["src_bar"] = float(el.pressure_bar)
		var press: Dictionary = {}
		var qs: Dictionary = {}
		for port in Geom.ports(el):
			var pname: String = str(port["name"])
			if Geom.port_domain(el, pname) == "electric":
				continue
			if el.get("port_press") != null and el.port_press.has(pname):
				press[pname] = snappedf((float(el.port_press[pname]) - 101325.0) / 1.0e5, 0.01)
			elif str(el.kind) == "source" and pname == "out":
				press[pname] = snappedf(float(el.pressure_bar), 0.01)
			if circuit.wire_on(int(el.id), pname) == null:
				qs[pname] = float(circuit.open_port_viz_q(el, pname))
		item["p_bar"] = press
		item["open_q"] = qs
		if str(el.kind) == "cylinder":
			item["p_cap_bar"] = (float(el.p_cap) - 101325.0) / 1.0e5
			item["p_rod_bar"] = (float(el.p_rod) - 101325.0) / 1.0e5
			item["x_mm"] = float(el.x) * 1000.0
			item["v"] = float(el.v)
		ports_out.append(item)
	return {
		"running": bool(circuit.running),
		"sim_time": float(circuit.sim_time),
		"wires": wires_out,
		"open_ports": ports_out,
	}


func _toggle_play_pause() -> void:
	circuit.running = not bool(circuit.running)
	_sync_play_button()
	_redraw_schematic()
	if schematic != null and schematic.has_method("refresh_sim_edit_lock"):
		schematic.refresh_sim_edit_lock()


func _reset_simulation() -> void:
	circuit.reset_simulation()
	_sync_play_button()
	_redraw_schematic()
	if schematic != null and schematic.has_method("refresh_sim_edit_lock"):
		schematic.refresh_sim_edit_lock()


func _sync_play_button() -> void:
	if _play == null:
		return
	var running_i: int = 1 if bool(circuit.running) else 0
	if running_i == _play_btn_running:
		return
	_play_btn_running = running_i
	if running_i == 1:
		_play.text = "❚❚"
		_style_button(_play, UiTheme.pause_btn())
		_play.tooltip_text = "Пауза (заморозка времени)"
	else:
		_play.text = "▶"
		_style_button(_play, UiTheme.success())
		_play.tooltip_text = "Пуск симуляции"


func _process(delta: float) -> void:
	if circuit.running:
		# Фиксированный потолок dt — без спирали «кадр тормозит → step больше → ещё хуже».
		# Не догоняем пропущенное время: приоритет стабильных 60 FPS UI.
		circuit.step(minf(delta, 1.0 / 60.0))
	# Размер SubViewport при stretch=true задаёт SubViewportContainer (+ stretch_shrink).
	_tick_dense_3d_render()
	if _show_3d:
		_sync_view_cube()
		if _view_cube != null:
			# Куб вида — только в орбите.
			var cam_ok: bool = true
			if workshop != null and is_instance_valid(workshop) and workshop.has_method("get_cam_mode"):
				cam_ok = str(workshop.get_cam_mode()) == "orbit"
			_view_cube.visible = cam_ok
		# Живые параметры в тултипе при неподвижной мыши.
		if _view_tip != null and _view_tip.visible \
				and (bool(circuit.running) or float(circuit.sim_time) > 0.0):
			var now_u: int = Time.get_ticks_usec()
			if (now_u - _view3d_tip_refresh_usec) >= 100000:
				_update_view3d_tip(_view3d_tip_local)
		if circuit != null and bool(circuit.thermal_viz) and (Engine.get_process_frames() % 8) == 0:
			_refresh_thermal_legend()
	elif _view_cube != null:
		_view_cube.visible = false
	if _thermal_legend != null and is_instance_valid(_thermal_legend):
		_thermal_legend.visible = _show_3d and circuit != null and bool(circuit.thermal_viz)
	# Пока _ready ждёт кадры под splash, кнопок ещё нет.
	if _play == null or _reset == null or _status == null:
		return
	_sync_play_button()
	# Статус/describe_selection не каждый кадр — на плотном щите это заметный CPU.
	if (Engine.get_process_frames() % 8) != 0 and not _perf_hud:
		return
	var fps: float = Engine.get_frames_per_second()
	var hint := circuit.active_hint()
	if _perf_hud:
		var ms_step: float = circuit.perf_ms_step() if circuit.has_method("perf_ms_step") else 0.0
		var ms_draw: float = 0.0
		if schematic != null and schematic.has_method("perf_ms_draw"):
			ms_draw = schematic.perf_ms_draw()
		var ms3d: String = ""
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("perf_ms_summary"):
			ms3d = " · " + str(workshop.perf_ms_summary())
		_status.text = "FPS %.0f · step %.1f ms · 2D draw %.1f ms%s" % [fps, ms_step, ms_draw, ms3d]
	elif hint != "":
		_status.text = "FPS %.0f  ·  %s" % [fps, hint]
	else:
		_status.text = "FPS %.0f  ·  %s" % [fps, circuit.describe_selection()]


func _input(event: InputEvent) -> void:
	# LMB-up всегда (даже мимо 3D-оверлея) — иначе винт уставки/дроссель «липнет» к мыши.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("release_organ_drag"):
			workshop.release_organ_drag()
	if _drag_kind == "":
		return
	if event is InputEventMouseMotion:
		_ghost.position = event.global_position + Vector2(14, 12)
		_ghost.visible = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var gp: Vector2 = event.global_position
		if _show_2d and schematic != null and schematic.get_global_rect().has_point(gp):
			schematic.place_at_global(_drag_kind, gp)
		elif _show_3d and _overlay != null and _overlay.get_global_rect().has_point(gp):
			_place_kind_in_3d(_drag_kind, _overlay.get_local_mouse_position())
		_drag_kind = ""
		_ghost.visible = false


func open_properties() -> void:
	if schematic and schematic.has_method("open_properties_at"):
		schematic.open_properties_at()
		return


func _ghost_label_for(kind: String) -> String:
	if kind.begins_with("valve"):
		return "Пневмораспределитель"
	if kind.begins_with("cylinder"):
		return "Пневмоцилиндр"
	if kind.begins_with("rotary_cylinder"):
		return "Поворотный ПЦ"
	if kind.begins_with("air_motor"):
		return "Пневмомотор"
	if kind.begins_with("accessory"):
		return "Пневмоаксессуар"
	if kind.begins_with("electro") or kind == "coil":
		return "Электроэлемент"
	if kind.begins_with("junction"):
		return "Фитинг"
	return "Источник"


func _begin_drag(kind: String) -> void:
	_drag_kind = kind
	_armed_3d_kind = ""
	_ghost.text = _ghost_label_for(kind)
	_ghost.visible = true


func _next_schematic_slot() -> Vector2:
	var n := 0
	if circuit != null:
		n = circuit.elements.size()
	return Vector2(120.0 + float(n % 8) * 80.0, 100.0 + float(n / 8.0) * 100.0)


func _place_kind_in_3d(kind: String, screen_local: Vector2) -> void:
	# Шина УГО — только схема 2D, на 3D-сцену не ставим.
	if kind == "rail" or kind.begins_with("rail@"):
		return
	if workshop == null or not workshop.has_method("pick_floor_point"):
		return
	var world: Vector3 = workshop.pick_floor_point(screen_local)
	var el = circuit.add_element(kind, _next_schematic_slot())
	if el == null:
		return
	el.world_pos = world
	el.auto_ground = true
	circuit.select_only(el.id, "workshop")
	_redraw_schematic()


func _toolbar() -> Control:
	var bar := PanelContainer.new()
	_menubar_panel = bar
	bar.custom_minimum_size = Vector2(0, 48)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = UiTheme.panel_bg()
	bar.add_theme_stylebox_override("panel", bar_style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var left := HBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	left.add_child(_menu_button("Файл", [
		["Новая сцена", "new", KEY_N],
		["Открыть…", "open", KEY_O],
		["Сохранить", "save", KEY_S],
		["Сохранить как…", "save_as", KEY_S, true],
		["-", "", 0],
		["Экспорт 2D схемы в PDF…", "pdf2d", 0],
		["Экспорт 3D сцены в PDF…", "pdf3d", 0],
		["-", "", 0],
		["Выход", "quit", KEY_Q],
	]))
	left.add_child(_menu_button("Правка", [
		["Отменить", "undo", KEY_Z],
		["Повторить", "redo", KEY_Y],
		["-", "", 0],
		["Упорядочить схему", "arrange_schematic", 0],
	]))
	left.add_child(_menu_button("Вид", [
		["Во весь экран", "fullscreen", KEY_F11],
		["Развернуть", "maximize", 0],
		["Оконный режим", "windowed", 0],
		["Свернуть", "minimize", 0],
		["-", "", 0],
		["Показать FPS / нагрузку", "perf_hud", 0],
	]))
	left.add_child(_menu_button("Помощь", [
		["Сообщить об ошибке…", "bug_report", 0],
	]))
	row.add_child(left)

	# Пуск левее центра — место справа под «Отображение» и тему.
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_BEGIN
	center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_theme_constant_override("separation", 8)
	_play = _button("▶", UiTheme.success())
	_reset = _button("↺", UiTheme.danger())
	for b in [_play, _reset]:
		b.custom_minimum_size = Vector2(40, 32)
		b.add_theme_font_size_override("font_size", 16)
	_play.tooltip_text = "Пуск / пауза"
	_reset.tooltip_text = "Сброс в исходное состояние"
	_play.pressed.connect(_toggle_play_pause)
	_reset.pressed.connect(_reset_simulation)
	center.add_child(_play)
	center.add_child(_reset)
	var rule := VSeparator.new()
	rule.custom_minimum_size = Vector2(2, 24)
	center.add_child(rule)
	var speed_caption := Label.new()
	speed_caption.text = "Скорость"
	speed_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_child(speed_caption)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 3.0
	slider.step = 0.1
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(120, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = ""
	slider.value_changed.connect(func(v):
		circuit.speed = v
		_speed_label.text = "×%.1f" % v
	)
	center.add_child(slider)
	_speed_label = Label.new()
	_speed_label.text = "×1.0"
	_speed_label.custom_minimum_size = Vector2(42, 0)
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_child(_speed_label)
	var disp_sep := VSeparator.new()
	disp_sep.custom_minimum_size = Vector2(2, 24)
	center.add_child(disp_sep)
	var disp_lab := Label.new()
	disp_lab.text = "Отображение:"
	disp_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_child(disp_lab)
	_btn_xray = _toggle_view_button("Рентген")
	_btn_xray.button_pressed = false
	_btn_xray.tooltip_text = "Рентген: просветить корпуса над движущейся механикой"
	_btn_xray.toggled.connect(func(on: bool):
		if workshop != null and is_instance_valid(workshop):
			workshop.set_xray(on)
		_style_toggle_button(_btn_xray, on)
	)
	_style_toggle_button(_btn_xray, false)
	center.add_child(_btn_xray)
	_btn_pressure = _toggle_view_button("Давление")
	_btn_pressure.button_pressed = false
	_btn_pressure.tooltip_text = "Подсветка линий и элементов по давлению (2D и 3D)"
	_btn_pressure.toggled.connect(func(on: bool):
		_set_pressure_viz(on)
	)
	_style_toggle_button(_btn_pressure, false)
	center.add_child(_btn_pressure)
	_btn_sensor_field = _toggle_view_button("Зоны")
	_btn_sensor_field.button_pressed = false
	_btn_sensor_field.tooltip_text = "Зоны датчиков: формы коллайдеров Sn (можно вместе с Давлением)"
	_btn_sensor_field.toggled.connect(func(on: bool):
		_set_sensor_field_viz(on)
	)
	_style_toggle_button(_btn_sensor_field, false)
	center.add_child(_btn_sensor_field)
	_btn_thermal = _toggle_view_button("Тепловизор")
	_btn_thermal.button_pressed = false
	_btn_thermal.custom_minimum_size = Vector2(110, 32)
	_btn_thermal.tooltip_text = "Тепловизор 3D: °C по сцене (щит/жилы/корпуса). ТС — T зоны; электро — I²R; пневмо — дросселирование, трение, выхлоп, катушки. Шкала справа сверху."
	_btn_thermal.toggled.connect(func(on: bool):
		_set_thermal_viz(on)
	)
	_style_toggle_button(_btn_thermal, false)
	center.add_child(_btn_thermal)
	row.add_child(center)

	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 8)
	_theme_btn = _button("Светлая", UiTheme.accent())
	_theme_btn.custom_minimum_size = Vector2(128, 34)
	_theme_btn.expand_icon = true
	_theme_btn.pressed.connect(_toggle_theme)
	right.add_child(_theme_btn)

	var view_sep := VSeparator.new()
	view_sep.custom_minimum_size = Vector2(2, 24)
	right.add_child(view_sep)

	_btn_2d = _toggle_view_button("2D")
	_btn_2d.tooltip_text = ""
	_btn_2d.toggled.connect(func(on: bool):
		_show_2d = on
		if not _show_2d and not _show_3d:
			_show_3d = true
		_rebuild_main_split()
		_refresh_view_buttons()
	)
	right.add_child(_btn_2d)

	_btn_3d = _toggle_view_button("3D")
	_btn_3d.tooltip_text = ""
	_btn_3d.toggled.connect(func(on: bool):
		_show_3d = on
		if not _show_2d and not _show_3d:
			_show_2d = true
		_rebuild_main_split()
		_refresh_view_buttons()
	)
	right.add_child(_btn_3d)

	_btn_orient = _toggle_view_button("││")
	_btn_orient.toggle_mode = true
	_btn_orient.pressed.connect(_toggle_orientation)
	right.add_child(_btn_orient)
	row.add_child(right)

	_refresh_theme_button()
	_refresh_view_buttons()
	return bar


func _toggle_view_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(44, 32)
	button.button_pressed = true
	_style_toggle_button(button, true)
	return button


func _style_toggle_button(button: Button, on: bool) -> void:
	if button == null:
		return
	var color := UiTheme.accent() if on else UiTheme.neutral_btn()
	var normal := _flat(color, 6)
	var hover := _flat(color.lightened(0.08 if on else 0.04), 6)
	var pressed := _flat(color.darkened(0.08), 6)
	# Иконки камеры — ужеже поля, чем текстовые 2D/3D.
	if button.icon != null and str(button.text).is_empty():
		normal.content_margin_left = 8
		normal.content_margin_right = 8
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		hover.content_margin_left = 8
		hover.content_margin_right = 8
		hover.content_margin_top = 6
		hover.content_margin_bottom = 6
		pressed.content_margin_left = 8
		pressed.content_margin_right = 8
		pressed.content_margin_top = 6
		pressed.content_margin_bottom = 6
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	# На светло-серой неактивной — тёмный текст/иконка; на синей — белый.
	var fg := Color(0.97, 0.98, 0.99)
	if not on and not UiTheme.dark:
		fg = Color(0.22, 0.24, 0.28)
	elif not on and UiTheme.dark:
		fg = Color(0.93, 0.94, 0.96)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, fg)
	for ikey in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(ikey, fg)


func _toggle_orientation() -> void:
	_orient_vertical = not _orient_vertical
	_rebuild_main_split()
	_refresh_view_buttons()


func _set_pressure_viz(on: bool) -> void:
	circuit.pressure_viz = bool(on)
	if _btn_pressure != null:
		_btn_pressure.set_pressed_no_signal(bool(on))
		_btn_pressure.text = "Давление"
		_style_toggle_button(_btn_pressure, bool(on))
	_redraw_schematic()


func _set_sensor_field_viz(on: bool) -> void:
	circuit.sensor_field_viz = bool(on)
	if _btn_sensor_field != null:
		_btn_sensor_field.set_pressed_no_signal(bool(on))
		_btn_sensor_field.text = "Зоны"
		_style_toggle_button(_btn_sensor_field, bool(on))
	_redraw_schematic()


func _set_thermal_viz(on: bool) -> void:
	circuit.thermal_viz = bool(on)
	if _btn_thermal != null:
		_btn_thermal.set_pressed_no_signal(bool(on))
		_btn_thermal.text = "Тепловизор"
		_style_toggle_button(_btn_thermal, bool(on))
	_ensure_thermal_legend()
	if _thermal_legend != null:
		_thermal_legend.visible = bool(on) and _show_3d
	if bool(on):
		_refresh_thermal_legend()


func _ensure_thermal_legend() -> void:
	if _thermal_legend != null and is_instance_valid(_thermal_legend):
		return
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var ThermalV = preload("res://scripts/domain/thermal_viz.gd")
	_thermal_legend = PanelContainer.new()
	_thermal_legend.name = "ThermalLegend"
	_thermal_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thermal_legend.z_index = 45
	_thermal_legend.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_thermal_legend.anchor_left = 1.0
	_thermal_legend.anchor_right = 1.0
	_thermal_legend.anchor_top = 0.0
	_thermal_legend.anchor_bottom = 0.0
	_thermal_legend.offset_left = -132.0
	_thermal_legend.offset_right = -12.0
	_thermal_legend.offset_top = 12.0
	_thermal_legend.offset_bottom = 148.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_thermal_legend.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_thermal_legend.add_child(col)
	var title := Label.new()
	title.text = "°C"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	col.add_child(title)
	_thermal_legend_max = Label.new()
	_thermal_legend_max.text = "—"
	_thermal_legend_max.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thermal_legend_max.add_theme_font_size_override("font_size", 11)
	_thermal_legend_max.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	col.add_child(_thermal_legend_max)
	_thermal_legend_bar = ColorRect.new()
	_thermal_legend_bar.custom_minimum_size = Vector2(28, 90)
	_thermal_legend_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Градиент через shader-less: ImageTexture на TextureRect лучше.
	var tex_rect := TextureRect.new()
	tex_rect.name = "Grad"
	tex_rect.custom_minimum_size = Vector2(28, 90)
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var img := Image.create(8, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var u: float = 1.0 - float(y) / 63.0
		var c: Color = ThermalV.color_norm(u)
		for x in 8:
			img.set_pixel(x, y, c)
	_thermal_legend_tex = ImageTexture.create_from_image(img)
	tex_rect.texture = _thermal_legend_tex
	col.add_child(tex_rect)
	_thermal_legend_bar.visible = false
	col.add_child(_thermal_legend_bar)
	_thermal_legend_min = Label.new()
	_thermal_legend_min.text = "—"
	_thermal_legend_min.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thermal_legend_min.add_theme_font_size_override("font_size", 11)
	_thermal_legend_min.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0))
	col.add_child(_thermal_legend_min)
	_thermal_legend.visible = false
	_overlay.add_child(_thermal_legend)


func _refresh_thermal_legend() -> void:
	if _thermal_legend == null or not is_instance_valid(_thermal_legend):
		return
	if circuit == null or not bool(circuit.thermal_viz):
		_thermal_legend.visible = false
		return
	_thermal_legend.visible = _show_3d
	var rng: Dictionary = {}
	if workshop != null and is_instance_valid(workshop) and workshop.has_method("thermal_legend_range"):
		rng = workshop.thermal_legend_range()
	else:
		var ThermalV2 = preload("res://scripts/domain/thermal_viz.gd")
		rng = ThermalV2.scene_range_c(circuit)
	var t_min: float = float(rng.get("min", 20.0))
	var t_max: float = float(rng.get("max", 22.0))
	if _thermal_legend_min != null:
		_thermal_legend_min.text = "%.1f" % t_min
	if _thermal_legend_max != null:
		_thermal_legend_max.text = "%.1f" % t_max
	# Палитра могла смениться — пересобрать градиент легенды.
	if _thermal_legend_tex != null:
		var ThermalVg = preload("res://scripts/domain/thermal_viz.gd")
		var img := Image.create(8, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			var u: float = 1.0 - float(y) / 63.0
			var c: Color = ThermalVg.color_norm(u)
			for x in 8:
				img.set_pixel(x, y, c)
		_thermal_legend_tex.set_image(img)


func _refresh_view_buttons() -> void:
	if _btn_pressure:
		var pv: bool = bool(circuit.pressure_viz)
		_btn_pressure.set_pressed_no_signal(pv)
		_btn_pressure.text = "Давление"
		_style_toggle_button(_btn_pressure, pv)
	if _btn_sensor_field:
		var sv: bool = bool(circuit.sensor_field_viz)
		_btn_sensor_field.set_pressed_no_signal(sv)
		_btn_sensor_field.text = "Зоны"
		_style_toggle_button(_btn_sensor_field, sv)
	if _btn_thermal:
		var tv: bool = bool(circuit.thermal_viz)
		_btn_thermal.set_pressed_no_signal(tv)
		_btn_thermal.text = "Тепловизор"
		_style_toggle_button(_btn_thermal, tv)
		if _thermal_legend != null:
			_thermal_legend.visible = tv and _show_3d
	if _btn_xray:
		var xr: bool = false
		if workshop != null and is_instance_valid(workshop):
			xr = bool(workshop.xray)
		_btn_xray.set_pressed_no_signal(xr)
		_style_toggle_button(_btn_xray, xr)
	if _btn_2d:
		_btn_2d.set_pressed_no_signal(_show_2d)
		_style_toggle_button(_btn_2d, _show_2d)
	if _btn_3d:
		_btn_3d.set_pressed_no_signal(_show_3d)
		_style_toggle_button(_btn_3d, _show_3d)
	if _btn_orient:
		_btn_orient.set_pressed_no_signal(not _orient_vertical)
		_btn_orient.text = "││" if _orient_vertical else "══"
		_btn_orient.tooltip_text = ""
		_btn_orient.disabled = not (_show_2d and _show_3d)
		_style_toggle_button(_btn_orient, not _orient_vertical)
	if _cam_orbit != null and is_instance_valid(_cam_orbit):
		_style_toggle_button(_cam_orbit, _cam_orbit.button_pressed)
	if _cam_fly != null and is_instance_valid(_cam_fly):
		_style_toggle_button(_cam_fly, _cam_fly.button_pressed)
	if _cam_fpv != null and is_instance_valid(_cam_fpv):
		_style_toggle_button(_cam_fpv, _cam_fpv.button_pressed)


func _toggle_theme() -> void:
	UiTheme.set_dark(not UiTheme.dark)
	theme = _make_theme()
	_apply_chrome_colors()
	_refresh_theme_button()
	_refresh_view_buttons()
	for lib in [_library_2d, _library_3d]:
		if lib and lib.has_method("apply_ui_theme"):
			lib.apply_ui_theme()
	if schematic and schematic.has_method("apply_ui_theme"):
		schematic.apply_ui_theme()
	if workshop and workshop.has_method("apply_ui_theme"):
		workshop.apply_ui_theme()


func _refresh_theme_button() -> void:
	if _theme_btn == null:
		return
	# Текущая тема + iOS-луна после текста; луна ≈ −⅓ от прежнего размера.
	if UiTheme.dark:
		_theme_btn.text = "Тёмная"
		_theme_btn.icon = _ui_tex("res://assets/ui/theme_moon_dark.png", false, 18)
		_theme_btn.tooltip_text = "Сейчас тёмная тема · нажмите для светлой"
	else:
		_theme_btn.text = "Светлая"
		_theme_btn.icon = _ui_tex("res://assets/ui/theme_moon_light.png", false, 18)
		_theme_btn.tooltip_text = "Сейчас светлая тема · нажмите для тёмной"
	_theme_btn.expand_icon = false
	_theme_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_theme_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_button(_theme_btn, UiTheme.accent())
	# Цветные эмодзи — не перекрашивать в белый.
	for ikey in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		_theme_btn.add_theme_color_override(ikey, Color.WHITE)
	_refresh_cam_label_theme()


func _refresh_cam_label_theme() -> void:
	if _cam_label == null or not is_instance_valid(_cam_label):
		return
	# Светлая тема — тёмно-синий (бренд); тёмная — светлый силуэт.
	if UiTheme.dark:
		_cam_label.modulate = Color(0.95, 0.96, 0.98, 0.95)
	else:
		_cam_label.modulate = UiTheme.brand_blue()


func _apply_chrome_colors() -> void:
	_refresh_cam_label_theme()
	if _backdrop:
		_backdrop.color = UiTheme.window_bg()
	if _menubar_panel:
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = UiTheme.panel_bg()
		_menubar_panel.add_theme_stylebox_override("panel", bar_style)
	if _ghost:
		_ghost.add_theme_color_override("font_color", UiTheme.text())
	if _view_tip != null:
		var tip_paper2 := StyleBoxFlat.new()
		tip_paper2.bg_color = UiTheme.tooltip_bg()
		tip_paper2.border_color = UiTheme.tooltip_border()
		tip_paper2.set_border_width_all(1)
		tip_paper2.set_corner_radius_all(4)
		tip_paper2.content_margin_left = 8
		tip_paper2.content_margin_right = 8
		tip_paper2.content_margin_top = 5
		tip_paper2.content_margin_bottom = 5
		_view_tip.add_theme_stylebox_override("panel", tip_paper2)
	if _view_tip_label != null:
		_view_tip_label.add_theme_font_override("normal_font", UiTheme.font_regular())
		_view_tip_label.add_theme_font_override("bold_font", UiTheme.font_tip_bold())
		_view_tip_label.add_theme_font_size_override("normal_font_size", 16)
		_view_tip_label.add_theme_font_size_override("bold_font_size", 16)
		_view_tip_label.add_theme_color_override("default_color", UiTheme.tooltip_fg())
	_style_cam_help()
	if _status:
		_status.add_theme_color_override("font_color", UiTheme.text())
	for btn in _menu_buttons:
		_style_menu_button(btn)


func _rebuild_main_split() -> void:
	if _main_split != null:
		_remember_main_split_offset()
		for child in _main_split.get_children():
			_main_split.remove_child(child)
		var old := _main_split
		_main_split = null
		old.queue_free()

	if _orient_vertical:
		_main_split = HSplitContainer.new()
	else:
		_main_split = VSplitContainer.new()
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shell.add_child(_main_split)
	# toolbar = 0, content = 1, status later becomes last
	if _shell.get_child_count() > 1:
		_shell.move_child(_main_split, 1)

	_pane_2d.visible = _show_2d
	_pane_3d.visible = _show_3d
	if _library_2d:
		_library_2d.visible = _show_2d
	if _library_3d:
		_library_3d.visible = _show_3d
	# 3D выкл — не крутить _process и не рендерить SubViewport.
	if workshop != null and is_instance_valid(workshop):
		workshop.set_process(_show_3d)
	if _view != null and is_instance_valid(_view):
		_view.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if _show_3d else SubViewport.UPDATE_DISABLED
		)

	if _orient_vertical:
		if _show_2d:
			_main_split.add_child(_pane_2d)
		if _show_3d:
			_main_split.add_child(_pane_3d)
	else:
		if _show_3d:
			_main_split.add_child(_pane_3d)
		if _show_2d:
			_main_split.add_child(_pane_2d)

	if _show_2d and _show_3d:
		_main_split.split_offset = _main_split_offset_h if _orient_vertical else _main_split_offset_v
	_main_split_dragging = false
	if not _main_split.drag_started.is_connected(_on_main_split_drag_started):
		_main_split.drag_started.connect(_on_main_split_drag_started)
	if not _main_split.drag_ended.is_connected(_on_main_split_drag_ended):
		_main_split.drag_ended.connect(_on_main_split_drag_ended)
	if not _main_split.dragged.is_connected(_on_main_split_dragged):
		_main_split.dragged.connect(_on_main_split_dragged)
	if schematic != null and is_instance_valid(schematic) and schematic.has_method("arm_viewport_relayout"):
		schematic.arm_viewport_relayout()
	call_deferred("_apply_lib_offsets")
	call_deferred("_fix_split_layout")
	call_deferred("_clamp_main_split")
	call_deferred("_refresh_schematic_after_split")


func _refresh_schematic_after_split() -> void:
	if not _show_2d:
		return
	if schematic == null or not is_instance_valid(schematic):
		return
	if schematic.has_method("notify_viewport_relayout"):
		schematic.notify_viewport_relayout()
	# Первый кадр после reparent часто ещё с size=0 / пустым canvas — повтор после layout.
	call_deferred("_refresh_schematic_after_split_late")


func _refresh_schematic_after_split_late() -> void:
	if not _show_2d:
		return
	if schematic == null or not is_instance_valid(schematic):
		return
	if schematic.has_method("notify_viewport_relayout"):
		schematic.notify_viewport_relayout()


func _on_main_split_drag_started() -> void:
	_main_split_dragging = true
	if _view != null and is_instance_valid(_view) and _show_3d:
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _on_main_split_drag_ended() -> void:
	_main_split_dragging = false
	_dense_3d_resize_hold_msec = Time.get_ticks_msec() + 220
	_remember_main_split_offset()


func _on_main_split_dragged(_offset: int) -> void:
	_main_split_dragging = true
	if _view != null and is_instance_valid(_view) and _show_3d:
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _remember_main_split_offset() -> void:
	if _main_split == null:
		return
	if not (_show_2d and _show_3d):
		return
	if _orient_vertical:
		_main_split_offset_h = _main_split.split_offset
	else:
		_main_split_offset_v = _main_split.split_offset


func _clamp_main_split() -> void:
	if _main_split == null or not (_show_2d and _show_3d):
		return
	var span := _main_split.size.x if _orient_vertical else _main_split.size.y
	if span < 160.0:
		return
	# offset от середины: оставляем каждой стороне ≥160px
	var max_off := int(span * 0.5) - 160
	if max_off < 0:
		_main_split.split_offset = 0
		return
	_main_split.split_offset = clampi(_main_split.split_offset, -max_off, max_off)
	if _orient_vertical:
		_main_split_offset_h = _main_split.split_offset
	else:
		_main_split_offset_v = _main_split.split_offset


func _make_lib_slot() -> MarginContainer:
	## Фиксированная ширина: min=max, без EXPAND — схема/цех забирают остаток.
	var slot := MarginContainer.new()
	slot.add_theme_constant_override("margin_left", 0)
	slot.add_theme_constant_override("margin_right", 0)
	slot.add_theme_constant_override("margin_top", 0)
	slot.add_theme_constant_override("margin_bottom", 0)
	slot.custom_minimum_size = Vector2(_LIB_W_DEFAULT, 0)
	slot.custom_maximum_size = Vector2(_LIB_W_DEFAULT, 100000.0)
	slot.propagate_maximum_size = true
	slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.clip_contents = true
	return slot


func _make_2d_pane() -> Control:
	var host := HBoxContainer.new()
	host.add_theme_constant_override("separation", 0)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_lib2d_slot = _make_lib_slot()

	_library_2d = LibraryScript.new()
	_library_2d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_2d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_2d.set_heading("Библиотека 2D")
	_library_2d.item_chosen.connect(func(kind):
		_armed_3d_kind = ""
		schematic.armed_kind = kind
		schematic.grab_focus()
	)
	_library_2d.drag_started.connect(_begin_drag)
	_library_2d.filter_changed.connect(func(q: String, f: bool): _on_lib_filter_changed(q, f, _library_2d))
	_library_2d.favorites_changed.connect(func(): _on_lib_favorites_changed(_library_2d))
	_lib2d_slot.add_child(_library_2d)

	_grip2d = _make_width_grip(true)

	schematic = SchematicScript.new()
	schematic.circuit = circuit
	schematic.font = theme.default_font
	schematic.custom_minimum_size = Vector2(160, 0)
	schematic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schematic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	schematic.size_flags_stretch_ratio = 1.0

	host.add_child(_lib2d_slot)
	host.add_child(_grip2d)
	host.add_child(schematic)
	return host


func _make_3d_pane() -> Control:
	var host := HBoxContainer.new()
	host.add_theme_constant_override("separation", 0)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pane := Control.new()
	pane.custom_minimum_size = Vector2(160, 0)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 1.0
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.stretch_shrink = 1
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane.add_child(vpc)
	_view_container = vpc
	_view = SubViewport.new()
	_view.handle_input_locally = false
	_view.gui_disable_input = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.size = Vector2i(800, 600)
	vpc.add_child(_view)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.focus_mode = Control.FOCUS_ALL
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_overlay.mouse_exited.connect(func():
		if _view_tip != null:
			_view_tip.visible = false
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("clear_hover_highlight"):
			workshop.clear_hover_highlight()
		if circuit != null and circuit.has_method("clear_hover"):
			circuit.clear_hover("workshop")
		if schematic != null and is_instance_valid(schematic):
			if schematic.has_method("notify_external_hover"):
				schematic.notify_external_hover()
			else:
				schematic.queue_redraw()
	)
	pane.add_child(_overlay)
	_view_tip = PanelContainer.new()
	_view_tip.name = "View3DTip"
	_view_tip.visible = false
	_view_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_tip.z_index = 60
	var tip_paper := StyleBoxFlat.new()
	tip_paper.bg_color = UiTheme.tooltip_bg()
	tip_paper.border_color = UiTheme.tooltip_border()
	tip_paper.set_border_width_all(1)
	tip_paper.set_corner_radius_all(4)
	tip_paper.content_margin_left = 8
	tip_paper.content_margin_right = 8
	tip_paper.content_margin_top = 5
	tip_paper.content_margin_bottom = 5
	_view_tip.add_theme_stylebox_override("panel", tip_paper)
	_view_tip_label = RichTextLabel.new()
	_view_tip_label.bbcode_enabled = true
	_view_tip_label.fit_content = true
	_view_tip_label.scroll_active = false
	_view_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_view_tip_label.add_theme_font_override("normal_font", UiTheme.font_regular())
	_view_tip_label.add_theme_font_override("bold_font", UiTheme.font_tip_bold())
	_view_tip_label.add_theme_font_size_override("normal_font_size", 16)
	_view_tip_label.add_theme_font_size_override("bold_font_size", 16)
	_view_tip_label.add_theme_color_override("default_color", UiTheme.tooltip_fg())
	_view_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_tip.add_child(_view_tip_label)
	pane.add_child(_view_tip)
	var modes := HBoxContainer.new()
	modes.position = Vector2(12, 12)
	modes.add_theme_constant_override("separation", 8)
	_cam_label = TextureRect.new()
	_cam_label.texture = _ui_tex("res://assets/ui/cam_label.png", true, 28)
	_cam_label.custom_minimum_size = Vector2(34, 34)
	_cam_label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam_label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cam_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_cam_label_theme()
	modes.add_child(_cam_label)
	_cam_orbit = _cam_icon_button("orbit")
	_cam_fly = _cam_icon_button("fly")
	_cam_fpv = _cam_icon_button("fpv")
	_cam_orbit.tooltip_text = "Орбита"
	_cam_fly.tooltip_text = "Полет"
	_cam_fpv.tooltip_text = "От первого лица"
	var sync_cam_btns := func(mode_name: String):
		_cam_orbit.set_pressed_no_signal(mode_name == "orbit")
		_cam_fly.set_pressed_no_signal(mode_name == "fly")
		_cam_fpv.set_pressed_no_signal(mode_name == "fpv")
		_style_toggle_button(_cam_orbit, mode_name == "orbit")
		_style_toggle_button(_cam_fly, mode_name == "fly")
		_style_toggle_button(_cam_fpv, mode_name == "fpv")
		if _view_cube != null and is_instance_valid(_view_cube):
			_view_cube.visible = mode_name == "orbit"
		_set_cam_help(mode_name)
	_cam_orbit.pressed.connect(func():
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_cam_mode"):
			workshop.set_cam_mode("orbit")
		sync_cam_btns.call("orbit")
	)
	_cam_fly.pressed.connect(func():
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_cam_mode"):
			workshop.set_cam_mode("fly")
		sync_cam_btns.call("fly")
	)
	_cam_fpv.pressed.connect(func():
		if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_cam_mode"):
			workshop.set_cam_mode("fpv")
		sync_cam_btns.call("fpv")
	)
	modes.add_child(_cam_orbit)
	modes.add_child(_cam_fly)
	modes.add_child(_cam_fpv)
	sync_cam_btns.call("fly")
	pane.add_child(modes)
	# Рентген/Давление — только в тулбаре «Отображение:»; восстановить рентген после пересборки 3D.
	if _btn_xray != null and workshop != null and is_instance_valid(workshop):
		workshop.set_xray(_btn_xray.button_pressed)
	_cam_help = PanelContainer.new()
	_cam_help.name = "CamHelp"
	_cam_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_help.z_index = 40
	_cam_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_help.anchor_top = 1.0
	_cam_help.anchor_bottom = 1.0
	_cam_help.offset_top = -30.0
	_cam_help.offset_bottom = 0.0
	_cam_help.offset_left = 0.0
	_cam_help.offset_right = 0.0
	_cam_help_label = Label.new()
	_cam_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cam_help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cam_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_help.add_child(_cam_help_label)
	pane.add_child(_cam_help)
	_style_cam_help()
	_set_cam_help("fly")
	if workshop != null and is_instance_valid(workshop) and workshop.has_method("set_cam_mode"):
		workshop.set_cam_mode("fly")
	_view_cube = ViewCubeScript.new()
	_view_cube.name = "ViewCube"
	_view_cube.anchor_left = 1.0
	_view_cube.anchor_top = 0.0
	_view_cube.anchor_right = 1.0
	_view_cube.anchor_bottom = 0.0
	_view_cube.offset_left = -108.0
	_view_cube.offset_top = 10.0
	_view_cube.offset_right = -10.0
	_view_cube.offset_bottom = 108.0
	_view_cube.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_view_cube.view_chosen.connect(_on_view_cube_chosen)
	pane.add_child(_view_cube)
	pane.resized.connect(func():
		vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	)

	_grip3d = _make_width_grip(false)

	_lib3d_slot = _make_lib_slot()

	_library_3d = LibraryScript.new()
	_library_3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_3d.set_heading("Библиотека 3D")
	_library_3d.item_chosen.connect(func(kind):
		schematic.armed_kind = ""
		_armed_3d_kind = kind
	)
	_library_3d.drag_started.connect(_begin_drag)
	_library_3d.filter_changed.connect(func(q: String, f: bool): _on_lib_filter_changed(q, f, _library_3d))
	_library_3d.favorites_changed.connect(func(): _on_lib_favorites_changed(_library_3d))
	_lib3d_slot.add_child(_library_3d)

	host.add_child(pane)
	host.add_child(_grip3d)
	host.add_child(_lib3d_slot)
	return host


func _make_width_grip(lib_is_first: bool) -> ColorRect:
	var grip := ColorRect.new()
	grip.color = Color(0, 0, 0, 0.08)
	grip.custom_minimum_size = Vector2(_GRIP_W, 0)
	grip.custom_maximum_size = Vector2(_GRIP_W, 100000.0)
	grip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"drag": false, "moved": false}
	grip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				state["drag"] = true
				state["moved"] = false
			else:
				if state["drag"] and not state["moved"]:
					if lib_is_first:
						_lib2d_collapsed = not _lib2d_collapsed
					else:
						_lib3d_collapsed = not _lib3d_collapsed
					_apply_lib_offsets()
				state["drag"] = false
			grip.accept_event()
		elif ev is InputEventMouseMotion and state["drag"]:
			if absf(ev.relative.x) > 0.5:
				state["moved"] = true
			if lib_is_first:
				_lib2d_collapsed = false
				_lib2d_width = clampi(_lib2d_width + int(ev.relative.x), _LIB_W_MIN, _LIB_W_MAX)
			else:
				_lib3d_collapsed = false
				_lib3d_width = clampi(_lib3d_width - int(ev.relative.x), _LIB_W_MIN, _LIB_W_MAX)
			_apply_lib_offsets()
			grip.accept_event()
	)
	return grip


func _on_overlay_gui_input(event: InputEvent) -> void:
	# Оверлей в фокусе (WASD). Не accept'ить клавиши целиком — иначе Ctrl+Z/Y
	# не доходят до _unhandled_key_input и Undo после гизмо «мёртвый».
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		var ctrl: bool = ke.ctrl_pressed or ke.meta_pressed
		if ctrl and ke.keycode == KEY_Z and not ke.shift_pressed:
			_undo_edit()
			_overlay.accept_event()
			return
		if ctrl and (ke.keycode == KEY_Y or (ke.keycode == KEY_Z and ke.shift_pressed)):
			_redo_edit()
			_overlay.accept_event()
			return
		return
	# Клик по пустому 3D (мимо панели) — закрыть белые окошки свойств.
	# Сами панели MOUSE_FILTER_STOP — клик по ним сюда не доходит.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if schematic != null and schematic.has_method("hide_unpinned_floats"):
			schematic.hide_unpinned_floats()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# ЛКМ: сразу убрать тултип (пикер/свойства откроются поверх).
		_hide_view3d_tip()
		if _armed_3d_kind != "":
			_place_kind_in_3d(_armed_3d_kind, event.position)
			_armed_3d_kind = ""
			_overlay.accept_event()
			return
	if workshop:
		workshop.handle_view_event(event)
	if event is InputEventMouseMotion:
		_update_view3d_tip(event.position)
	_overlay.accept_event()


func _hide_view3d_tip() -> void:
	if _view_tip != null:
		_view_tip.visible = false
		_view_tip.custom_minimum_size = Vector2.ZERO
	_view3d_tip_text = ""


## Пока на 3D-оверлее открыт список выбора / свойства — тултип не показывать.
func _view3d_tip_blocked_by_float() -> bool:
	if schematic == null or not is_instance_valid(schematic):
		return false
	if _overlay == null or not is_instance_valid(_overlay):
		return false
	if schematic.has_method("has_visible_float_on"):
		return bool(schematic.has_visible_float_on(_overlay))
	return false


func _update_view3d_tip(local_pos: Vector2) -> void:
	if _view_tip == null or _view_tip_label == null:
		return
	_view3d_tip_local = local_pos
	if workshop == null or not is_instance_valid(workshop) or not workshop.has_method("hover_tip_at"):
		_hide_view3d_tip()
		return
	# Орбита/look/pan: не трогаем hover и 2D — иначе фриз на каждом motion.
	if workshop.has_method("is_camera_navigating") and bool(workshop.is_camera_navigating()):
		_hide_view3d_tip()
		return
	if _view3d_tip_blocked_by_float():
		_hide_view3d_tip()
		return
	var prev_el: int = int(circuit.hover_el_id) if circuit != null else -1
	var prev_port: String = str(circuit.hover_port) if circuit != null else ""
	var prev_wire: int = int(circuit.hover_wire_id) if circuit != null else -1
	var prev_space: String = str(circuit.hover_space) if circuit != null else ""
	var text: String = str(workshop.hover_tip_at(local_pos))
	var hover_changed: bool = circuit != null and (
		int(circuit.hover_el_id) != prev_el
		or str(circuit.hover_port) != prev_port
		or int(circuit.hover_wire_id) != prev_wire
		or str(circuit.hover_space) != prev_space
	)
	# 3D→2D: при Run только лёгкий Live; chrome.queue_redraw тянул Base на 30+ ms.
	if hover_changed and schematic != null and is_instance_valid(schematic):
		if schematic.has_method("notify_external_hover"):
			schematic.notify_external_hover()
		else:
			schematic.queue_redraw()
	if text == "":
		_hide_view3d_tip()
		return
	# BBCode: при смене цели сразу; живые числа на том же приборе — ≤4 Hz.
	var now_usec: int = Time.get_ticks_usec()
	var tip_due: bool = hover_changed or _view3d_tip_text == "" \
			or (now_usec - _view3d_tip_refresh_usec) >= 250000
	if text != _view3d_tip_text and tip_due:
		_view3d_tip_text = text
		_view3d_tip_refresh_usec = now_usec
		_view_tip_label.clear()
		_view_tip_label.parse_bbcode(text)
		var tip_sz: Vector2 = _measure_view3d_tip(text)
		_view_tip.custom_minimum_size = tip_sz
		_view_tip.size = tip_sz
	_view_tip.visible = true
	var tip_sz2: Vector2 = _view_tip.size
	var pane: Control = _view_tip.get_parent() as Control
	var max_x: float = pane.size.x - tip_sz2.x - 8.0 if pane != null else local_pos.x + 14.0
	var max_y: float = pane.size.y - tip_sz2.y - 8.0 if pane != null else local_pos.y + 18.0
	_view_tip.position = Vector2(
		clampf(local_pos.x + 14.0, 8.0, maxf(max_x, 8.0)),
		clampf(local_pos.y + 18.0, 8.0, maxf(max_y, 8.0))
	)


func _measure_view3d_tip(text: String) -> Vector2:
	var font: Font = _view_tip_label.get_theme_font("normal_font")
	var font_size: int = _view_tip_label.get_theme_font_size("normal_font_size")
	if font == null:
		font = ThemeDB.fallback_font
	if font_size <= 0:
		font_size = 16
	var plain: String = text.replace("[b]", "").replace("[/b]", "")
	var max_w: float = 0.0
	var lines: PackedStringArray = plain.split("\n")
	for line in lines:
		var w: float = font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var line_h: float = font.get_height(font_size)
	var pad_x: float = 16.0
	var pad_y: float = 10.0
	var sb: StyleBox = _view_tip.get_theme_stylebox("panel")
	if sb != null:
		pad_x = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
		pad_y = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	var n: int = maxi(lines.size(), 1)
	return Vector2(ceilf(max_w + pad_x + 4.0), ceilf(line_h * float(n) + pad_y + 2.0))


func _on_view_cube_chosen(yaw: float, pitch: float) -> void:
	if workshop == null or not is_instance_valid(workshop):
		return
	if workshop.has_method("orbit_to_view"):
		workshop.orbit_to_view(yaw, pitch)
	elif workshop.has_method("set_orbit"):
		workshop.set_orbit(yaw, pitch)


func _cam_help_text(mode_name: String) -> String:
	# Как в Blender: «Клавиша - Действие»; только рабочие в этом режиме камеры.
	match mode_name:
		"fly":
			return "ПКМ - Взгляд · W/A/S/D - Движение · Q - Вниз · E - Вверх · Колесо - Вперёд/назад · Shift - Быстрее · Ctrl - Медленнее"
		"fpv":
			return "ПКМ - Взгляд · W/A/S/D - Ходьба · Колесо - Шаг · Shift - Быстрее · Ctrl - Медленнее"
		_:
			return "ПКМ - Вращение · СКМ - Панорама · Колесо - Масштаб · Куб вида - Ракурс"


func _set_cam_help(mode_name: String) -> void:
	if _cam_help_label == null:
		return
	_cam_help_label.text = _cam_help_text(mode_name)
	if _cam_help != null:
		_cam_help.visible = _show_3d


func _style_cam_help() -> void:
	if _cam_help == null or _cam_help_label == null:
		return
	var bar := StyleBoxFlat.new()
	var bg := UiTheme.panel_bg()
	bg.a = 0.88 if UiTheme.dark else 0.90
	bar.bg_color = bg
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	bar.content_margin_top = 4
	bar.content_margin_bottom = 4
	_cam_help.add_theme_stylebox_override("panel", bar)
	_cam_help_label.add_theme_font_size_override("font_size", 13)
	_cam_help_label.add_theme_color_override("font_color", UiTheme.muted())
	var font: Font = UiTheme.font_regular()
	if font != null:
		_cam_help_label.add_theme_font_override("font", font)


func _sync_view_cube() -> void:
	if _view_cube == null or not is_instance_valid(_view_cube):
		return
	if workshop == null or not is_instance_valid(workshop) or not workshop.has_method("get_orbit"):
		return
	var o: Vector2 = workshop.get_orbit()
	if absf(o.x - _cube_cam_yaw) < 0.0005 and absf(o.y - _cube_cam_pitch) < 0.0005:
		return
	_cube_cam_yaw = o.x
	_cube_cam_pitch = o.y
	if _view_cube.has_method("set_orientation"):
		_view_cube.set_orientation(o.x, o.y)


func _on_lib_filter_changed(query: String, fav_only: bool, source: Control) -> void:
	if _syncing_libs:
		return
	_syncing_libs = true
	var peer: Control = _library_3d if source == _library_2d else _library_2d
	if peer and peer.has_method("apply_filter"):
		peer.apply_filter(query, fav_only)
	_syncing_libs = false


func _on_lib_favorites_changed(source: Control) -> void:
	if _syncing_libs:
		return
	_syncing_libs = true
	var peer: Control = _library_3d if source == _library_2d else _library_2d
	if peer and peer.has_method("reload_favorites"):
		peer.reload_favorites()
	_syncing_libs = false


func _apply_lib_offsets() -> void:
	_lib2d_width = clampi(_lib2d_width, _LIB_W_MIN, _LIB_W_MAX)
	_lib3d_width = clampi(_lib3d_width, _LIB_W_MIN, _LIB_W_MAX)
	if _lib2d_slot != null:
		_lib2d_slot.visible = _show_2d and not _lib2d_collapsed
		_lib2d_slot.custom_minimum_size = Vector2(float(_lib2d_width), 0)
		_lib2d_slot.custom_maximum_size = Vector2(float(_lib2d_width), 100000.0)
		_lib2d_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if _grip2d != null:
		_grip2d.visible = _show_2d and not _lib2d_collapsed
	if _lib3d_slot != null:
		_lib3d_slot.visible = _show_3d and not _lib3d_collapsed
		_lib3d_slot.custom_minimum_size = Vector2(float(_lib3d_width), 0)
		_lib3d_slot.custom_maximum_size = Vector2(float(_lib3d_width), 100000.0)
		_lib3d_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if _grip3d != null:
		_grip3d.visible = _show_3d and not _lib3d_collapsed
	if _library_2d != null:
		_library_2d.visible = _show_2d
	if _library_3d != null:
		_library_3d.visible = _show_3d


func _cam_icon_button(mode_name: String) -> Button:
	var button := _toggle_view_button("")
	var path := "res://assets/ui/cam_orbit.png"
	var center_ink: bool = false
	match mode_name:
		"fly":
			path = "res://assets/ui/cam_fly.png"
		"fpv":
			path = "res://assets/ui/cam_fpv.png"
			center_ink = true
		_:
			path = "res://assets/ui/cam_orbit.png"
	button.icon = _ui_tex(path, true, 28, center_ink)
	button.expand_icon = true
	# Было ~36×32 → +30%.
	button.custom_minimum_size = Vector2(47, 42)
	button.button_pressed = false
	_style_toggle_button(button, false)
	return button


var _ui_tex_cache: Dictionary = {} # path|sil|px|center -> Texture2D


func _ui_tex(path: String, white_silhouette: bool, target_px: int = 28, center_content: bool = false) -> Texture2D:
	var key: String = "%s|%s|%d|%s" % [path, str(white_silhouette), target_px, str(center_content)]
	if _ui_tex_cache.has(key):
		return _ui_tex_cache[key] as Texture2D
	var src: Image = null
	# Свежий файл с диска (знак ГУАП и т.п.) — не брать устаревший импорт.
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			src = img
	if src == null and ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			src = (loaded as Texture2D).get_image()
	if src == null:
		var empty := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		empty.fill(Color(1, 1, 1, 0.2))
		var fb := ImageTexture.create_from_image(empty)
		_ui_tex_cache[key] = fb
		return fb
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var out: Image = src.duplicate()
	if white_silhouette:
		out = _to_white_silhouette(src)
	if center_content:
		out = _center_opaque_square(out)
	var max_side: int = maxi(out.get_width(), out.get_height())
	var want: int = maxi(12, target_px)
	if max_side > want:
		var scale: float = float(want) / float(max_side)
		out.resize(
			maxi(1, int(round(float(out.get_width()) * scale))),
			maxi(1, int(round(float(out.get_height()) * scale))),
			Image.INTERPOLATE_LANCZOS
		)
	var tex := ImageTexture.create_from_image(out)
	_ui_tex_cache[key] = tex
	return tex


func _center_opaque_square(src: Image) -> Image:
	## Обрезать по ink и вписать в квадрат по центру (для асимметричного человечка FPV).
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var w: int = src.get_width()
	var h: int = src.get_height()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.12:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return src
	var bw: int = max_x - min_x + 1
	var bh: int = max_y - min_y + 1
	var side: int = maxi(bw, bh) + 2
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ox: int = (side - bw) / 2
	var oy: int = (side - bh) / 2
	out.blit_rect(src, Rect2i(min_x, min_y, bw, bh), Vector2i(ox, oy))
	return out


func _to_white_silhouette(src: Image) -> Image:
	var img := src.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			if px.a < 0.12:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Тёмный/цветной ink → белый; белый фон → прозрачный.
			var lum: float = (px.r + px.g + px.b) / 3.0
			var ink: float = (1.0 - lum) * px.a
			# Цветной знак ГУАП: насыщенный цвет тоже ink.
			var chroma: float = maxf(px.r, maxf(px.g, px.b)) - minf(px.r, minf(px.g, px.b))
			if ink > 0.12 or (chroma > 0.12 and px.a > 0.35 and lum < 0.92):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(92, 32)
	_style_button(button, color)
	return button


func _style_button(button: Button, color: Color) -> void:
	if button == null:
		return
	var normal := _flat(color, 6)
	var hover := _flat(color.lightened(0.12), 6)
	var pressed := _flat(color.darkened(0.08), 6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled_bg := Color(0.2, 0.22, 0.25) if UiTheme.dark else Color(0.72, 0.74, 0.78)
	button.add_theme_stylebox_override("disabled", _flat(disabled_bg, 6))
	var icon_fg := Color(0.97, 0.98, 0.99)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, icon_fg)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.62))


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = 10
	box.content_margin_right = 10
	return box


func _make_theme() -> Theme:
	var made := Theme.new()
	made.default_font = UiTheme.font_regular()
	made.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = UiTheme.panel_bg()
	made.set_stylebox("panel", "PanelContainer", panel)
	var self_panel := StyleBoxFlat.new()
	self_panel.bg_color = UiTheme.window_bg()
	made.set_stylebox("panel", "Panel", self_panel)
	made.set_color("font_color", "Label", UiTheme.text())
	made.set_color("font_color", "LineEdit", UiTheme.text())
	made.set_color("font_placeholder_color", "LineEdit", UiTheme.muted())
	var menu_fg := UiTheme.text()
	for mk in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		made.set_color(mk, "MenuButton", menu_fg)
	made.set_color("font_disabled_color", "MenuButton", UiTheme.muted())
	made.set_color("font_color", "PopupMenu", menu_fg)
	made.set_color("font_hover_color", "PopupMenu", menu_fg)
	made.set_color("font_accelerator_color", "PopupMenu", UiTheme.muted())
	made.set_color("font_separator_color", "PopupMenu", UiTheme.muted())
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = UiTheme.menu_bg()
	popup_panel.border_color = UiTheme.menu_border()
	popup_panel.set_border_width_all(1)
	popup_panel.set_corner_radius_all(6)
	popup_panel.set_content_margin_all(6)
	popup_panel.shadow_size = 0
	made.set_stylebox("panel", "PopupMenu", popup_panel)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = UiTheme.menu_hover()
	popup_hover.set_corner_radius_all(4)
	made.set_stylebox("hover", "PopupMenu", popup_hover)
	# Нативные tooltip кнопок (Пуск, Орбита/Пролёт/FPV…) — не серый OS-стиль.
	var tip_panel := StyleBoxFlat.new()
	tip_panel.bg_color = UiTheme.tooltip_bg()
	tip_panel.border_color = UiTheme.tooltip_border()
	tip_panel.set_border_width_all(1)
	tip_panel.set_corner_radius_all(4)
	tip_panel.content_margin_left = 8
	tip_panel.content_margin_right = 8
	tip_panel.content_margin_top = 5
	tip_panel.content_margin_bottom = 5
	tip_panel.shadow_size = 0
	made.set_stylebox("panel", "TooltipPanel", tip_panel)
	made.set_color("font_color", "TooltipLabel", UiTheme.tooltip_fg())
	made.set_font("font", "TooltipLabel", UiTheme.font_regular())
	made.set_font_size("font_size", "TooltipLabel", 13)
	var edit := StyleBoxFlat.new()
	edit.bg_color = UiTheme.window_bg().lightened(0.04 if UiTheme.dark else 0.08)
	edit.border_color = UiTheme.muted().darkened(0.2)
	edit.set_border_width_all(1)
	edit.set_corner_radius_all(4)
	edit.content_margin_left = 8
	edit.content_margin_right = 8
	edit.content_margin_top = 4
	edit.content_margin_bottom = 4
	made.set_stylebox("normal", "LineEdit", edit)
	made.set_stylebox("focus", "LineEdit", edit)
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = UiTheme.window_bg()
	scroll.set_content_margin_all(0)
	made.set_stylebox("panel", "ScrollContainer", scroll)
	return made


## Диагностика XT: ряды, hide, занятость портов / «висячие» жилы.
func agent_terminal_probe(tag: String = "XT1") -> Dictionary:
	if circuit == null:
		return {"ok": false}
	var el = null
	for e in circuit.elements:
		if str(e.tag) == tag and str(e.electro_class) == "terminal":
			el = e
			break
	if el == null:
		return {"ok": false, "err": "not found"}
	var poles: int = maxi(el.electro_ports.size(), 1)
	var ports_used: Array = []
	var poles_used: Array = []
	for row in poles:
		var left: String = str(row * 2 + 1)
		var right: String = str(row * 2 + 2)
		var lu: bool = circuit.wire_on(int(el.id), left) != null
		var ru: bool = circuit.wire_on(int(el.id), right) != null
		if lu:
			ports_used.append(left)
		if ru:
			ports_used.append(right)
		if lu or ru:
			poles_used.append(row)
	var all_wire_ports: Array = []
	var dangling: Array = []
	for w in circuit.wires:
		for side in [[int(w.a_id), str(w.a_port)], [int(w.b_id), str(w.b_port)]]:
			if int(side[0]) != int(el.id):
				continue
			var pn: String = str(side[1])
			all_wire_ports.append(pn)
			if not pn.is_valid_int():
				dangling.append(pn)
				continue
			var n: int = int(pn)
			if n < 1 or n > poles * 2:
				dangling.append(pn)
	var ElectroSym = preload("res://scripts/domain/electro_symbols.gd")
	ElectroSym.scheme_circuit = circuit
	# Принудительно пересобрать индекс — ловим рассинхрон wire_on vs wires[].
	if circuit.has_method("invalidate_port_wire_index"):
		circuit.invalidate_port_wire_index()
	var ports_used2: Array = []
	for pn2 in all_wire_ports:
		if circuit.wire_on(int(el.id), str(pn2)) != null and not ports_used2.has(str(pn2)):
			ports_used2.append(str(pn2))
	var wire_samples: Array = []
	for w in circuit.wires:
		if int(w.a_id) == int(el.id):
			wire_samples.append({
				"wid": int(w.id), "side": "a",
				"port": str(w.a_port), "port_type": typeof(w.a_port),
				"on": circuit.wire_on(int(el.id), str(w.a_port)) != null,
			})
		if int(w.b_id) == int(el.id):
			wire_samples.append({
				"wid": int(w.id), "side": "b",
				"port": str(w.b_port), "port_type": typeof(w.b_port),
				"on": circuit.wire_on(int(el.id), str(w.b_port)) != null,
			})
	var vis: Array = ElectroSym._terminal_visible_names(el)
	el.hide_unused_contacts = true
	var vis_hide: Array = ElectroSym._terminal_visible_names(el)
	el.hide_unused_contacts = bool(false) # restore; probe only
	return {
		"ok": true,
		"id": int(el.id),
		"poles": poles,
		"hide": bool(el.hide_unused_contacts),
		"ports_used": ports_used,
		"ports_used_after_invalidate": ports_used2,
		"poles_used": poles_used,
		"n_ports_used": ports_used.size(),
		"n_poles_used": poles_used.size(),
		"all_wire_ports": all_wire_ports,
		"dangling_ports": dangling,
		"wire_samples": wire_samples,
		"visible_names": vis,
		"visible_when_hide": vis_hide,
		"scheme": int(el.terminal_port_scheme),
	}
