class_name MechSimMark
extends Control
## Exact FSPO faculty mark from official asset (no redraw).

const MARK_PATH := "res://assets/brand/fspo_mark.png"

@export var white_mode := false

var _tex: Texture2D
var _white_tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(96, 96)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex = load(MARK_PATH) as Texture2D
	set_process(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var s := minf(size.x, size.y)
	if s < 2.0:
		return
	var rect := Rect2((size.x - s) * 0.5, (size.y - s) * 0.5, s, s)
	if white_mode:
		var wt := _get_white_tex()
		if wt != null:
			draw_texture_rect(wt, rect, false)
		return
	draw_texture_rect(_tex, rect, false)


func _get_white_tex() -> Texture2D:
	if _white_tex != null:
		return _white_tex
	var src := _source_image()
	if src == null:
		return null
	var img := _to_white_silhouette(src)
	_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


func _source_image() -> Image:
	if _tex != null:
		var img := _tex.get_image()
		if img != null:
			return img
	if FileAccess.file_exists(MARK_PATH):
		var img2 := Image.new()
		if img2.load(MARK_PATH) == OK:
			return img2
	return null


static func _to_white_silhouette(src: Image) -> Image:
	var img := src.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			var ink: float = (1.0 - (px.r + px.g + px.b) / 3.0) * px.a
			if ink > 0.18:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img
