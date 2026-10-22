class_name IsoAirMotor
extends RefCounted
## Диспетчер 3D пневмомотора: шестерённый / лопастной / турбинный.

const Gear = preload("res://scripts/view3d/iso_air_motor_gear.gd")
const Vane = preload("res://scripts/view3d/iso_air_motor_vane.gd")
const Turbine = preload("res://scripts/view3d/iso_air_motor_turbine.gd")


static func build(parent: Node3D, el) -> Dictionary:
	if el != null and str(el.rotary_class) == "turbine":
		return Turbine.build(parent, el)
	if el != null and str(el.rotary_class) == "vane":
		return Vane.build(parent, el)
	return Gear.build(parent, el)


static func apply_state(root: Node3D, el) -> void:
	if el != null and str(el.rotary_class) == "turbine":
		Turbine.apply_state(root, el)
	elif el != null and str(el.rotary_class) == "vane":
		Vane.apply_state(root, el)
	else:
		Gear.apply_state(root, el)


static func apply_xray(root: Node3D, on: bool) -> void:
	if root == null:
		return
	if bool(root.get_meta("air_motor_turbine", false)):
		Turbine.apply_xray(root, on)
	elif bool(root.get_meta("air_motor_vane", false)):
		Vane.apply_xray(root, on)
	else:
		Gear.apply_xray(root, on)
