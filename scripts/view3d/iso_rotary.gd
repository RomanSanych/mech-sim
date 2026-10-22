class_name IsoRotary
extends RefCounted
## Диспетчер 3D поворотного ПЦ: рейка–шестерня или лопастной.

const Rack = preload("res://scripts/view3d/iso_rotary_rack.gd")
const Vane = preload("res://scripts/view3d/iso_rotary_vane.gd")


static func build(parent: Node3D, el) -> Dictionary:
	if el != null and str(el.rotary_class) == "vane":
		return Vane.build(parent, el)
	return Rack.build(parent, el)


static func apply_state(root: Node3D, el) -> void:
	if el != null and str(el.rotary_class) == "vane":
		Vane.apply_state(root, el)
	else:
		Rack.apply_state(root, el)


static func apply_xray(root: Node3D, on: bool) -> void:
	# Оба класса используют тот же путь рентгена.
	Rack.apply_xray(root, on)
