extends Node2D
## Одна анимируемая часть УГО (ПЦ или золотник ПР). Лёгкий _draw только этого узла —
## Base/схема не очищаются. Канон геометрии — SymbolGeom.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const ElectroSym = preload("res://scripts/domain/electro_symbols.gd")

var el_id: int = -1
var kind: String = ""
var font: Font = null
var sch_zoom: float = 1.0
var circuit = null
var _el = null
var _last_sig: String = ""


func bind_element(el, p_font: Font, p_zoom: float = 1.0, p_circuit = null) -> void:
	_el = el
	el_id = int(el.id) if el != null else -1
	kind = str(el.kind) if el != null else ""
	font = p_font
	sch_zoom = maxf(p_zoom, 0.05)
	circuit = p_circuit
	_last_sig = ""
	queue_redraw()


func force_redraw() -> void:
	_last_sig = ""
	queue_redraw()


func sync_element(el, p_zoom: float = -1.0, p_circuit = null) -> void:
	_el = el
	if p_circuit != null:
		circuit = p_circuit
	if p_zoom > 0.0:
		sch_zoom = maxf(p_zoom, 0.05)
	if el == null:
		visible = false
		return
	visible = true
	var sig: String = _motion_sig(el)
	if sig != _last_sig:
		_last_sig = sig
		queue_redraw()


func _cylinder_trigger_sig(el) -> String:
	if circuit == null or el == null:
		return ""
	var SensorDetect = preload("res://scripts/domain/sensor_detection.gd")
	var marks: Array = SensorDetect.cylinder_stroke_triggers(circuit, el)
	var parts: PackedStringArray = PackedStringArray()
	for m in marks:
		var sid: int = int(m.get("sensor_id", -1))
		var closed: int = 0
		if sid >= 0:
			var sens = circuit.get_element(sid)
			if sens != null and "sensor_closed" in sens and bool(sens.sensor_closed):
				closed = 1
		parts.append("%d:%d" % [sid, closed])
	return ",".join(parts)


func _motion_sig(el) -> String:
	if str(el.kind) == "cylinder":
		# x — ход штока (м); + срабатывание герконов для подсветки △ на линейке.
		return "%.5f|%.0f|%.0f|%s|%s" % [
			float(el.x), float(el.p_cap), float(el.p_rod), str(el.get("piston_kind")),
			_cylinder_trigger_sig(el),
		]
	if str(el.kind) == "rotary_cylinder" or str(el.kind) == "air_motor":
		return "rr|%.5f|%.3f" % [float(el.angle), float(el.omega)]
	if str(el.kind) == "valve":
		return "%d|%s|%s" % [int(el.valve_pos), str(el.get("op_left")), str(el.get("op_right"))]
	if str(el.kind) == "accessory":
		var acls: String = str(el.get("accessory_class") if el.get("accessory_class") != null else "")
		if acls == "shuttle":
			# opening 0…1 — положение шарика ИЛИ.
			return "sh|%.4f" % clampf(float(el.opening), 0.0, 1.0)
		if acls == "quick_exhaust":
			return "qe|%.4f" % clampf(float(el.opening), 0.0, 1.0)
		if acls == "shutoff":
			return "zo|%.4f|%d" % [clampf(float(el.opening), 0.0, 1.0), int(el.valve_pos)]
		if acls == "relief":
			var open_r: float = clampf(float(el.opening), 0.0, 1.0)
			if bool(el.pressed):
				open_r = 1.0
			return "rl|%.4f|%d" % [open_r, 1 if bool(el.pressed) else 0]
	if str(el.kind) == "sensor":
		return "sc|%d|%s" % [1 if bool(el.sensor_closed) else 0, str(el.contact_form)]
	if str(el.kind) == "electro" and str(el.electro_class) == "lamp":
		return "lp|%d|%s" % [1 if bool(el.lit) else 0, str(el.lamp_color)]
	return ""


func _draw() -> void:
	if _el == null:
		return
	# zoom схемы — толщина штрихов; parent SchemeWorld уже scale=zoom.
	Geom.begin_sch_layer_draw(sch_zoom, Vector2.ZERO, true, [], 0.0, circuit)
	match kind:
		"cylinder":
			Geom.draw_cylinder_motion(self, _el)
		"rotary_cylinder":
			Geom.draw_rotary_cylinder_motion(self, _el)
		"air_motor":
			Geom.draw_air_motor_motion(self, _el)
		"valve":
			# ПР целиком на Base; Anim только для плавного slide (поверх).
			Geom.draw_valve_motion(self, _el, font)
		"accessory":
			var acls2: String = str(_el.get("accessory_class") if _el.get("accessory_class") != null else "")
			if acls2 == "shuttle":
				Geom.draw_shuttle_motion(self, _el)
			elif acls2 == "quick_exhaust":
				Geom.draw_quick_exhaust_motion(self, _el)
			elif acls2 == "shutoff":
				Geom.draw_shutoff_motion(self, _el, font)
			elif acls2 == "relief":
				Geom.draw_relief_motion(self, _el)
		"sensor":
			Geom.draw_sensor_motion(self, _el)
		"electro":
			if str(_el.electro_class) == "lamp":
				ElectroSym.draw_lamp_motion(self, _el, Geom.to_world)
	Geom.end_sch_layer_draw()
