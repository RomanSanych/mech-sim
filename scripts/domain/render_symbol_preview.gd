extends SceneTree


const Geom = preload("res://scripts/domain/symbol_geom.gd")
const CircuitScript = preload("res://scripts/domain/circuit.gd")


func _initialize() -> void:
	var circuit = CircuitScript.new()
	var el = circuit.add_element("cylinder", Vector2(180, 120))
	var sv := SubViewport.new()
	sv.size = Vector2i(420, 260)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var paint := Paint.new()
	paint.el = el
	paint.position = Vector2.ZERO
	paint.size = Vector2(420, 260)
	sv.add_child(paint)
	root.add_child(sv)
	await process_frame
	await process_frame
	await process_frame
	var out: Image = sv.get_texture().get_image()
	var path := "D:/mech-sim/tools/as_extract/out/captures/mechsim_cylinder.png"
	out.save_png(path)
	print("Wrote ", path)
	quit()


class Paint extends Control:
	var el
	func _ready() -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1), true)
		if el != null:
			Geom.draw_element(self, el, ThemeDB.fallback_font, false, false, "", false)
