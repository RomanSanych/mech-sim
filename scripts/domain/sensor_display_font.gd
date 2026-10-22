class_name SensorDisplayFont
extends RefCounted
## Цифровой шрифт дисплеев аналоговых СИ (волны A6/B/D).
## Импорт: assets/fonts/DigitalCyrillic.otf (из D:\digitalcyrillic1.zip).

const FONT_PATH := "res://assets/fonts/DigitalCyrillic.otf"

static var _cached: Font = null


static func get_font() -> Font:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(FONT_PATH):
		var f: Font = load(FONT_PATH) as Font
		if f != null:
			_cached = f
			return _cached
	return ThemeDB.fallback_font


static func available() -> bool:
	return ResourceLoader.exists(FONT_PATH)
