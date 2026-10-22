extends Node2D
## Слой анимации УГО: отдельные Node2D на ПЦ/ПР. Base запечён/заморожен — не очищается.

const MotionPartScript = preload("res://scripts/ui/schematic_motion_part.gd")

var owner_view: Control = null
var _parts: Dictionary = {} # el_id -> MotionPart


func set_active(on: bool) -> void:
	visible = on
	if not on:
		for id in _parts.keys():
			var n: Node2D = _parts[id] as Node2D
			if n != null:
				n.visible = false


func sync(circuit, font: Font, active: bool, force_redraw: bool = false) -> void:
	if not active or circuit == null:
		set_active(false)
		return
	visible = true
	var z: float = 1.0
	if owner_view != null:
		z = maxf(float(owner_view.get("zoom")), 0.05)
	var keep: Dictionary = {}
	for el in circuit.elements:
		if el == null:
			continue
		var k: String = str(el.kind)
		# Anim: поршень ПЦ; вал поворотного ПЦ; шарик ИЛИ / тарелка быстрого выхлопа (корпус на Base);
		# ключ датчика + свечение лампы (Base при Run заморожен).
		var acls: String = str(el.get("accessory_class") if el.get("accessory_class") != null else "")
		var is_motion_acc: bool = k == "accessory" and acls in ["shuttle", "quick_exhaust", "shutoff", "relief"]
		var is_runtime_el: bool = k == "sensor" or (
			k == "electro" and str(el.get("electro_class") if el.get("electro_class") != null else "") == "lamp"
		)
		if k != "cylinder" and k != "rotary_cylinder" and k != "air_motor" and not is_motion_acc and not is_runtime_el:
			continue
		var eid: int = int(el.id)
		keep[eid] = true
		var part: Node2D = _parts.get(eid) as Node2D
		if part == null:
			part = MotionPartScript.new()
			part.name = "Motion_%d" % eid
			part.z_index = 0
			add_child(part)
			_parts[eid] = part
			part.bind_element(el, font, z, circuit)
		else:
			part.sync_element(el, z, circuit)
			if force_redraw and part.has_method("force_redraw"):
				part.force_redraw()
	var drop: Array = []
	for eid in _parts.keys():
		if not keep.has(int(eid)):
			drop.append(int(eid))
	for eid2 in drop:
		var n2: Node2D = _parts[eid2] as Node2D
		_parts.erase(eid2)
		if n2 != null:
			n2.queue_free()
