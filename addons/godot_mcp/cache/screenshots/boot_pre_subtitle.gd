extends Control
## Оверлей поверх уже открытого окна: компактная синяя подложка + пиксельный МЕХСИМ / FSPO.

signal finished

const FSPO_MARK_PATH := "res://assets/brand/fspo_mark.png"
const PAD_IN := 0.22
const REVEAL_DURATION := 1.05
const HOLD_AFTER := 0.35
const HOLD_AFTER_LOAD := 3.0
const FADE_OUT := 0.28
const MIN_SHOW := 1.0
const KEY_SKIP_AFTER := 0.55
const PAD_MARGIN_RATIO := 0.22 # отступ подложки относительно блока
const BAR_ROW_GAP_CELLS := 2 # зазор логотип → бар в обычных клетках сетки
const BAR_CHUNK_CELLS := 2 # пиксель бара = 2×2 обычных клетки

const UiTheme = preload("res://scripts/app/ui_theme.gd")

# Bitmaps with solid 2px strokes (no 1px diagonals / holes). Word: М Е Х С И М
const WORD_GLYPHS: Array = [
	[ # М
		"1100000011",
		"1110000111",
		"1111001111",
		"1111111111",
		"1100110011",
		"1100000011",
		"1100000011",
		"1100000011",
		"1100000011",
		"1100000011",
	],
	[ # Е
		"1111111111",
		"1111111111",
		"1100000000",
		"1100000000",
		"1111111100",
		"1111111100",
		"1100000000",
		"1100000000",
		"1111111111",
		"1111111111",
	],
	[ # Х
		"1100000011",
		"1110000111",
		"0111001110",
		"0011111100",
		"0001111000",
		"0001111000",
		"0011111100",
		"0111001110",
		"1110000111",
		"1100000011",
	],
	[ # С
		"0011111100",
		"0111111110",
		"1110000111",
		"1100000011",
		"1100000000",
		"1100000000",
		"1100000011",
		"1110000111",
		"0111111110",
		"0011111100",
	],
	[ # И
		"1100000011",
		"1100000011",
		"1100001111",
		"1100011111",
		"1100111011",
		"1101110011",
		"1111100011",
		"1111000011",
		"1100000011",
		"1100000011",
	],
	[ # М
		"1100000011",
		"1110000111",
		"1111001111",
		"1111111111",
		"1100110011",
		"1100000011",
		"1100000011",
		"1100000011",
		"1100000011",
		"1100000011",
	],
]

const GLYPH_W := 10
const GLYPH_H := 10
const LOGO_N := 40
const LOGO_GAP := 3
const INK_THRESHOLD := 0.18

enum Phase { PAD, REVEAL, HOLD, FADE, DONE }

var _cells: Array[Vector2i] = []
var _order: Array[int] = []
var _visible_count := 0
var _elapsed := 0.0
var _phase_t := 0.0
var _phase: int = Phase.PAD
var _origin := Vector2.ZERO
var _block_size := Vector2.ZERO
var _pad_rect := Rect2()
var _pixel := 12
var _gap := 3
var _cell := 15
var _grid_w := 0
var _grid_h := 0
var _pad_alpha := 1.0
var _content_alpha := 1.0
var _closing := false
var _load_progress := 0.0
var _display_progress := 0.0
var _load_complete := false
var _post_load_hold_t := -1.0
var _logo_ready := false
var _bar_origin := Vector2.ZERO
var _bar_slots := 0
var _bar_pixel := 24.0
var _bar_cell := 28.0
var _status_text := ""
var _status_origin := Vector2.ZERO


func set_load_progress(p: float) -> void:
	_load_progress = clampf(p, 0.0, 1.0)
	if _load_progress >= 1.0:
		_load_complete = true
	queue_redraw()


func set_status_text(text: String) -> void:
	_status_text = text
	queue_redraw()


func mark_load_complete() -> void:
	_load_progress = 1.0
	_load_complete = true
	_status_text = "Готово"
	if _post_load_hold_t < 0.0:
		_post_load_hold_t = 0.0
	queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_index = 200
	_build_cells()
	if _cells.is_empty():
		push_error("MechSim splash: empty pixel mask (check FSPO mark asset)")
	_order.clear()
	for i in _cells.size():
		_order.append(i)
	_order.shuffle()
	set_process(true)
	set_process_unhandled_input(true)
	resized.connect(_relayout)
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_fit)
	_fit()
	call_deferred("_fit")


func _fit() -> void:
	var ws := get_viewport().get_visible_rect().size
	if ws.x < 2.0 or ws.y < 2.0:
		var w := get_window()
		if w != null:
			ws = Vector2(w.size)
	if ws.x < 2.0 or ws.y < 2.0:
		ws = Vector2(1600, 900)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0.0
	anchor_bottom = 0.0
	position = Vector2.ZERO
	size = ws
	_relayout()


func _relayout() -> void:
	_recompute_metrics()
	# Логотип + статус загрузки + прогрессбар (чанки 2×2).
	var logo_h := float(_grid_h) * float(_cell) - float(_gap)
	_bar_pixel = float(_pixel * BAR_CHUNK_CELLS)
	_bar_cell = float(_cell * BAR_CHUNK_CELLS)
	_bar_slots = maxi(4, int(floor((_block_size.x + float(_gap)) / _bar_cell)))
	var bar_w := float(_bar_slots) * _bar_cell - float(_gap * BAR_CHUNK_CELLS)
	var status_gap := float(_cell)
	var status_h := float(_pixel) * 1.35
	var bar_gap := float(_cell * BAR_ROW_GAP_CELLS)
	var total := Vector2(
		maxf(_block_size.x, bar_w),
		logo_h + status_gap + status_h + bar_gap + _bar_pixel
	)
	_origin = (size - total) * 0.5
	_status_origin = Vector2(
		_origin.x,
		_origin.y + logo_h + status_gap
	)
	_bar_origin = Vector2(
		_origin.x + (_block_size.x - bar_w) * 0.5,
		_status_origin.y + status_h + bar_gap
	)
	var margin := Vector2(
		maxi(18, int(round(total.x * PAD_MARGIN_RATIO * 0.5))),
		maxi(16, int(round(total.y * PAD_MARGIN_RATIO * 0.5)))
	)
	_pad_rect = Rect2(_origin - margin, total + margin * 2.0)
	queue_redraw()


func _build_cells() -> void:
	_cells.clear()
	var cursor_x := 0
	var letter_gap := 2
	var text_cells: Array[Vector2i] = []
	for glyph in WORD_GLYPHS:
		var rows: Array = glyph
		for y in rows.size():
			var row: String = str(rows[y])
			for x in row.length():
				if row[x] == "1":
					text_cells.append(Vector2i(cursor_x + x, y))
		cursor_x += GLYPH_W + letter_gap
	var text_w := cursor_x - letter_gap

	var logo_cells := _rasterize_fspo_exact(LOGO_N)
	var logo_x0 := text_w + LOGO_GAP
	var text_y0 := int(floor(float(LOGO_N - GLYPH_H) * 0.5))
	for c in text_cells:
		_cells.append(Vector2i(c.x, c.y + text_y0))
	for c in logo_cells:
		_cells.append(Vector2i(logo_x0 + c.x, c.y))

	_grid_w = logo_x0 + LOGO_N
	_grid_h = LOGO_N
	_recompute_metrics()


func _load_fspo_image() -> Image:
	if ResourceLoader.exists(FSPO_MARK_PATH):
		var res := load(FSPO_MARK_PATH)
		if res is Texture2D:
			var from_tex := (res as Texture2D).get_image()
			if from_tex != null:
				return from_tex
		elif res is Image:
			return res as Image
	var img := Image.new()
	if img.load(FSPO_MARK_PATH) == OK:
		return img
	return null


func _rasterize_fspo_exact(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var src := _load_fspo_image()
	if src == null:
		push_error("FSPO mark missing: %s" % FSPO_MARK_PATH)
		return out
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)

	var bbox := _ink_bbox(src)
	if bbox.size.x < 2 or bbox.size.y < 2:
		push_error("FSPO mark has no ink pixels")
		return out

	var side := maxi(bbox.size.x, bbox.size.y)
	var pad_x := int(floor(float(side - bbox.size.x) * 0.5))
	var pad_y := int(floor(float(side - bbox.size.y) * 0.5))
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color(1, 1, 1, 0))
	square.blit_rect(src, Rect2i(bbox.position, bbox.size), Vector2i(pad_x, pad_y))

	var mask := square.duplicate()
	mask.resize(n, n, Image.INTERPOLATE_NEAREST)

	for gy in n:
		for gx in n:
			if _is_ink(mask.get_pixel(gx, gy)):
				out.append(Vector2i(gx, gy))
	return out


func _ink_bbox(img: Image) -> Rect2i:
	var iw := img.get_width()
	var ih := img.get_height()
	var min_x := iw
	var min_y := ih
	var max_x := -1
	var max_y := -1
	for y in ih:
		for x in iw:
			if _is_ink(img.get_pixel(x, y)):
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _is_ink(px: Color) -> bool:
	var whiteness := (px.r + px.g + px.b) / 3.0
	return (1.0 - whiteness) * px.a > INK_THRESHOLD


func _recompute_metrics() -> void:
	if _grid_w <= 0 or _grid_h <= 0:
		return
	var target_w := maxf(520.0, size.x * 0.52)
	_pixel = maxi(5, int(floor(target_w / float(_grid_w + 2))))
	_gap = maxi(1, int(round(float(_pixel) * 0.14)))
	_cell = _pixel + _gap
	_block_size = Vector2(
		float(_grid_w) * float(_cell) - float(_gap),
		float(_grid_h) * float(_cell) - float(_gap)
	)


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	_elapsed += delta
	_phase_t += delta
	# Бар почти сразу следует за загрузкой (без «трёх пикселей» при уже большой загрузке).
	_display_progress = lerpf(_display_progress, _load_progress, clampf(delta * 18.0, 0.0, 1.0))
	if absf(_load_progress - _display_progress) < 0.01:
		_display_progress = _load_progress
	if _load_complete:
		_display_progress = 1.0
		if _post_load_hold_t < 0.0:
			_post_load_hold_t = 0.0
		else:
			_post_load_hold_t += delta
	match _phase:
		Phase.PAD:
			# Подложка видна сразу; короткая пауза — затем «высыпание» пикселей.
			_pad_alpha = 1.0
			_visible_count = 0
			_content_alpha = 1.0
			if _phase_t >= PAD_IN:
				_phase = Phase.REVEAL
				_phase_t = 0.0
		Phase.REVEAL:
			_pad_alpha = 1.0
			var progress := clampf(_phase_t / REVEAL_DURATION, 0.0, 1.0)
			_visible_count = int(floor(progress * float(_cells.size()) + 0.0001))
			if progress >= 1.0 or _cells.is_empty():
				_visible_count = _cells.size()
				_logo_ready = true
				_phase = Phase.HOLD
				_phase_t = 0.0
		Phase.HOLD:
			_pad_alpha = 1.0
			_visible_count = _cells.size()
			_logo_ready = true
			# После полной загрузки держим логотип ещё HOLD_AFTER_LOAD секунд.
			if (
				_load_complete
				and _display_progress >= 1.0
				and _post_load_hold_t >= HOLD_AFTER_LOAD
				and _elapsed >= MIN_SHOW
				and _phase_t >= HOLD_AFTER
			):
				_begin_fade()
		Phase.FADE:
			var t := clampf(_phase_t / FADE_OUT, 0.0, 1.0)
			_pad_alpha = 1.0 - t
			_content_alpha = 1.0 - t
			if t >= 1.0:
				_finish()
	queue_redraw()


func _begin_fade() -> void:
	if _closing or _phase == Phase.FADE or _phase == Phase.DONE:
		return
	if not _load_complete or _display_progress < 1.0:
		return
	_closing = true
	_phase = Phase.FADE
	_phase_t = 0.0


func _finish() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	finished.emit()
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()


func _draw() -> void:
	if _pad_alpha <= 0.001 and _phase != Phase.PAD:
		return
	if _pad_rect.size.x < 2.0 or _pad_rect.size.y < 2.0:
		return
	var blue := UiTheme.BRAND_BLUE
	blue.a = _pad_alpha
	draw_rect(_pad_rect, blue, true)
	var ink := Color(1, 1, 1, _content_alpha * _pad_alpha)
	if not _cells.is_empty() and not _order.is_empty() and _visible_count > 0:
		var n := mini(_visible_count, _order.size())
		for k in n:
			var idx: int = _order[k]
			var cell: Vector2i = _cells[idx]
			var p := _origin + Vector2(float(cell.x) * float(_cell), float(cell.y) * float(_cell))
			draw_rect(Rect2(p, Vector2(float(_pixel), float(_pixel))), ink, true)
	_draw_status_text(ink)
	_draw_progress_bar(ink)


func _draw_status_text(ink: Color) -> void:
	if _status_text == "":
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var fs := maxi(11, int(round(float(_pixel) * 0.95)))
	var tw := font.get_string_size(_status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := _origin.x + (_block_size.x - tw) * 0.5
	var y := _status_origin.y + float(fs)
	var col := Color(ink.r, ink.g, ink.b, ink.a * 0.92)
	draw_string(font, Vector2(x, y), _status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_progress_bar(ink: Color) -> void:
	if _bar_slots <= 0 or _bar_pixel < 2.0:
		return
	var filled := int(floor(_display_progress * float(_bar_slots) + 0.0001))
	filled = clampi(filled, 0, _bar_slots)
	var empty := Color(ink.r, ink.g, ink.b, ink.a * 0.22)
	for i in _bar_slots:
		var p := _bar_origin + Vector2(float(i) * _bar_cell, 0.0)
		var col := ink if i < filled else empty
		draw_rect(Rect2(p, Vector2(_bar_pixel, _bar_pixel)), col, true)


func _gui_input(event: InputEvent) -> void:
	if _try_skip(event):
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _try_skip(event):
		get_viewport().set_input_as_handled()


func _try_skip(event: InputEvent) -> bool:
	if _phase == Phase.DONE or _phase == Phase.FADE:
		return false
	# Пропуск только анимации логотипа; закрытие — строго после полной загрузки.
	var skip_logo := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip_logo = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if _elapsed >= KEY_SKIP_AFTER and (
			event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE
		):
			skip_logo = true
	if not skip_logo:
		return false
	if _phase == Phase.PAD or _phase == Phase.REVEAL:
		_pad_alpha = 1.0
		_visible_count = _cells.size()
		_logo_ready = true
		_phase = Phase.HOLD
		_phase_t = HOLD_AFTER
	# Клик/клавиша после загрузки пропускает паузу 3 с.
	if _load_complete and _display_progress >= 1.0 and _elapsed >= MIN_SHOW:
		_post_load_hold_t = HOLD_AFTER_LOAD
		_begin_fade()
	return true
