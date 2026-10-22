class_name UiTheme
extends RefCounted
## GUAP brand tokens + light/dark shell. Schematic stays paper-like.

const SETTINGS_PATH := "user://ui_settings.json"

## Pantone 300 / brand guide primary
const BRAND_BLUE := Color(0.0 / 255.0, 90.0 / 255.0, 170.0 / 255.0) # #005aaa
const BRAND_BLUE_LIGHT := Color(0.0 / 255.0, 108.0 / 255.0, 182.0 / 255.0) # #006cb6
const ACCENT_MAGENTA := Color(231.0 / 255.0, 43.0 / 255.0, 112.0 / 255.0) # #e72b70
const ACCENT_PURPLE := Color(171.0 / 255.0, 58.0 / 255.0, 141.0 / 255.0) # #ab3a8d
const ACCENT_CYAN := Color(0.0 / 255.0, 190.0 / 255.0, 243.0 / 255.0) # #00bef3

const FONT_REGULAR_PATH := "res://assets/fonts/Roboto-Regular.ttf"
const FONT_MEDIUM_PATH := "res://assets/fonts/Roboto-Medium.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Roboto-Bold.ttf"

static var dark := true
static var _font_regular: Font
static var _font_medium: Font
static var _font_bold: Font


static func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("dark"):
		dark = bool(parsed["dark"])


static func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"dark": dark}, "\t"))


static func set_dark(value: bool) -> void:
	dark = value
	save_settings()


static func brand_blue() -> Color:
	return BRAND_BLUE


static func accent() -> Color:
	return BRAND_BLUE_LIGHT if dark else BRAND_BLUE


static func accent_hot() -> Color:
	return ACCENT_MAGENTA


static func accent_purple() -> Color:
	return ACCENT_PURPLE


static func success() -> Color:
	return Color(0.12, 0.52, 0.38) if dark else Color(0.10, 0.48, 0.34)


static func danger() -> Color:
	return Color(0.58, 0.22, 0.28) if dark else Color(0.72, 0.22, 0.30)


static func pause_btn() -> Color:
	## Жёлтая кнопка паузы (не серая).
	return Color(0.88, 0.68, 0.10) if dark else Color(0.92, 0.74, 0.12)


static func neutral_btn() -> Color:
	# Светло-серый (не синеватый) — заметный контраст с активным accent.
	return Color(0.48, 0.50, 0.54) if dark else Color(0.82, 0.84, 0.87)


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Font:
			return res as Font
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Roboto", "Segoe UI", "Arial"])
	return fallback


static func font_regular() -> Font:
	if _font_regular == null:
		_font_regular = _load_font(FONT_REGULAR_PATH)
	return _font_regular


static func font_medium() -> Font:
	if _font_medium == null:
		_font_medium = _load_font(FONT_MEDIUM_PATH)
	return _font_medium


static func font_bold() -> Font:
	if _font_bold == null:
		if ResourceLoader.exists(FONT_BOLD_PATH):
			_font_bold = _load_font(FONT_BOLD_PATH)
		else:
			# Нет файла Bold — синтетический вес от regular (иначе [b] не отличим).
			var fv := FontVariation.new()
			fv.base_font = font_regular()
			fv.variation_embolden = 1.2
			_font_bold = fv
	return _font_bold


## Для всплывающих подсказок: гарантированно отличимый полужирный.
static func font_tip_bold() -> Font:
	var fv := FontVariation.new()
	fv.base_font = font_regular()
	fv.variation_embolden = 1.25
	return fv


static func panel_bg() -> Color:
	return Color(0.10, 0.16, 0.26) if dark else Color(0.93, 0.95, 0.98)


static func window_bg() -> Color:
	return Color(0.07, 0.12, 0.20) if dark else Color(0.84, 0.89, 0.94)


static func text() -> Color:
	return Color(0.93, 0.95, 0.98) if dark else Color(0.10, 0.16, 0.26)


static func muted() -> Color:
	return Color(0.55, 0.70, 0.88) if dark else Color(0.32, 0.42, 0.55)


static func preview_ink() -> Color:
	return Color(0.94, 0.96, 0.99) if dark else Color(0.06, 0.12, 0.20)


static func schematic_bg() -> Color:
	# Тёмная тема: чуть светлее бумаги — синие пневмолинии читаются на холсте.
	return Color(0.18, 0.24, 0.34) if dark else Color(0.94, 0.96, 0.99)


static func schematic_grid() -> Color:
	# Светлая: на ~1/3 слабее прежних 0.7 — меньше спорит с УГО на белой бумаге.
	return Color(0.28, 0.38, 0.52, 0.50) if dark else Color(0.72, 0.80, 0.88, 0.47)


static func schematic_help_fg() -> Color:
	return Color(0.62, 0.74, 0.90) if dark else Color(0.22, 0.36, 0.52)


## Подписи УГО / номера линий: не красятся давлением, только тема.
static func schematic_label() -> Color:
	return Color(0.92, 0.94, 0.98) if dark else Color(0.12, 0.16, 0.22)


static func schematic_label_halo() -> Color:
	# В тёмной теме — тёмный ореол (не белая окантовка); в светлой — белый.
	return Color(0.05, 0.07, 0.10, 0.55) if dark else Color(1.0, 1.0, 1.0, 0.88)


## Системные tooltip (кнопки тулбара) и кастомные Panel-подсказки.
static func tooltip_bg() -> Color:
	return Color(0.14, 0.20, 0.30) if dark else Color(0.97, 0.98, 1.0)


static func tooltip_fg() -> Color:
	return Color(0.93, 0.95, 0.98) if dark else Color(0.10, 0.16, 0.26)


static func tooltip_border() -> Color:
	return Color(0.38, 0.50, 0.66) if dark else Color(0.55, 0.68, 0.82)


static func paper() -> Color:
	return Color(0.97, 0.98, 1.0)


static func paper_border() -> Color:
	return Color(0.55, 0.68, 0.82)


static func paper_text() -> Color:
	return Color(0.10, 0.16, 0.26)


static func paper_muted() -> Color:
	return Color(0.34, 0.42, 0.52)


static func field_active() -> Color:
	return Color(0.82, 0.90, 0.98)


static func field_border() -> Color:
	return BRAND_BLUE


static func menu_bg() -> Color:
	return Color(0.12, 0.18, 0.28) if dark else Color(0.98, 0.99, 1.0)


static func menu_field_bg() -> Color:
	return Color(0.16, 0.22, 0.34) if dark else Color(1, 1, 1, 1)


static func menu_border() -> Color:
	return Color(0.32, 0.44, 0.58) if dark else Color(0.72, 0.80, 0.88)


static func menu_hover() -> Color:
	return Color(0.18, 0.28, 0.42) if dark else Color(0.88, 0.93, 0.98)


static func workshop_bg() -> Color:
	return Color(0.08, 0.12, 0.20) if dark else Color(0.72, 0.80, 0.88)


static func workshop_floor() -> Color:
	return Color(0.14, 0.20, 0.30) if dark else Color(0.52, 0.60, 0.70)


static func workshop_ambient() -> Color:
	return Color(0.55, 0.68, 0.88) if dark else Color(0.82, 0.88, 0.95)
