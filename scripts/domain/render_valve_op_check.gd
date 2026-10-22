extends SceneTree
## Headless PNG эталон УГО 5/2 (ISO сетка). Без await — force_draw.


const Geom = preload("res://scripts/domain/symbol_geom.gd")
const CircuitScript = preload("res://scripts/domain/circuit.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var circuit = CircuitScript.new()
	var valve = circuit.add_element("valve", Vector2(240, 150))
	valve.valve_ways = 5
	valve.valve_positions = 2
	valve.op_left = "solenoid_pilot"
	valve.op_right = "spring"
	valve.port_3 = "muffler"
	valve.port_5 = "muffler"
	circuit.retune_geometry(valve)
	var sol: Dictionary = Geom.valve_operator_bbox(valve, true)
	var w := float(sol["right"]) - float(sol["left"])
	var h := float(sol["bottom"]) - float(sol["top"])
	var body_bot := Geom.VALVE_SQ * 0.5
	var want_h := 2.0 * Geom.VALVE_SOL_H
	print("solenoid_pilot stack top=%.1f bottom=%.1f w=%.1f h=%.1f (want %.1fx%.1f)" % [
		sol["top"], sol["bottom"], w, h, Geom.VALVE_SOL_W, want_h,
	])
	if absf(w - Geom.VALVE_SOL_W) > 0.01 or absf(h - want_h) > 0.01:
		print("FAIL solenoid_pilot stack size")
		quit(1)
		return
	if absf(float(sol["bottom"]) - body_bot) > 0.01:
		print("FAIL coil not bottom")
		quit(1)
		return
	if not Geom.port_by_name(valve, "3").is_empty():
		print("FAIL muffler must hide tube port")
		quit(1)
		return
	if Geom.port_by_name(valve, "12").is_empty():
		print("FAIL pilot port 12 missing")
		quit(1)
		return
	var muff: Dictionary = Geom.valve_muffler_mark_metrics()
	if absf(float(muff["aspect"]) - 2.0) > 0.05:
		print("FAIL muffler aspect")
		quit(1)
		return
	var coil = circuit.add_element("coil", Vector2(400, 150))
	var a1 := Geom.port_by_name(coil, "A1")
	var a2 := Geom.port_by_name(coil, "A2")
	if a1.is_empty() or a2.is_empty():
		print("FAIL coil A1/A2")
		quit(1)
		return

	var dir := "D:/mech-sim/tools/as_extract/out/captures"
	DirAccess.make_dir_recursive_absolute(dir)
	# Мета для сверки (всегда).
	var meta := {
		"solenoid_pilot": sol,
		"solenoid_coil_w": Geom.VALVE_SOL_W,
		"solenoid_coil_h": Geom.VALVE_SOL_H,
		"pilot_port_12": Geom.port_by_name(valve, "12"),
		"spring": Geom.valve_operator_bbox(valve, false),
		"muffler": muff,
		"coil_ports": {"A1": a1, "A2": a2},
		"valve_sq": Geom.VALVE_SQ,
		"dims_338L": "valve_338L_015_02",
	}
	var meta_path := dir + "/valve_5_2_ugo.json"
	var mf := FileAccess.open(meta_path, FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(meta, "\t"))
		mf.close()
		print("Wrote ", meta_path)

	var sv := SubViewport.new()
	sv.size = Vector2i(520, 320)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	var paint := Paint.new()
	paint.el = valve
	paint.size = Vector2(520, 320)
	sv.add_child(paint)
	root.add_child(sv)
	paint.queue_redraw()
	RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_draw(false, 0.0)
	var path := dir + "/valve_5_2_ugo.png"
	var tex: ViewportTexture = sv.get_texture()
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 2:
		print("WARN viewport empty, meta only")
		quit(0)
		return
	var err := img.save_png(path)
	print("Wrote ", path, " err=", err, " px=", img.get_width(), "x", img.get_height())
	quit(0 if err == OK else 1)


class Paint extends Control:
	var el
	func _ready() -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.89, 0.914, 0.925), true)
		for x in range(0, int(size.x), 20):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.78, 0.82, 0.85), 1.0)
		for y in range(0, int(size.y), 20):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.78, 0.82, 0.85), 1.0)
		if el != null:
			Geom.draw_element(self, el, ThemeDB.fallback_font, true, false, "", false)
