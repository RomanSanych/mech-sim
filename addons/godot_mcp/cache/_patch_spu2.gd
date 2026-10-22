func _build_spu() -> void:
	# Plane // HandleHex face (YZ): well aft-wall clevis → red → elbow → green → HandleHex.
	# Bolt forward: folded DOWN. Bolt aft: straighten.
	_spu = Node3D.new()
	_spu.name = "SPU"
	add_child(_spu)
	var local_up := Vector3(0, 1, 0)
	# Hinge axis = lateral X (⊥ to hex face plane)
	var hinge := Vector3(1, 0, 0)
	var mat_l := _mat_spu if _mat_spu else _mat_tray
	var mat_j := _mat_joint if _mat_joint else mat_l

	_lever1_len = 1.35
	_lever2_len = 1.35

	# Clevis on shaft AFT wall: two semicircle lugs // bolt-head plane, red lever between
	var well_mount := Node3D.new()
	well_mount.name = "WellMount"
	_spu.add_child(well_mount)
	_spu_pin_shaft = well_mount
	for side in [-1.0, 1.0]:
		var lug := CSGCylinder3D.new()
		lug.name = "Clevis_%s" % ("A" if side < 0.0 else "B")
		lug.radius = 0.2
		lug.height = 0.1
		lug.sides = 12
		# Cylinder axis along hinge (X) — semicircle readout when viewed along bore
		lug.rotation_degrees = Vector3(0, 0, 90)
		lug.position = hinge * (side * 0.15)
		lug.material = mat_l
		well_mount.add_child(lug)
	var well_screw := CSGCylinder3D.new()
	well_screw.name = "WellScrew"
	well_screw.radius = 0.05
	well_screw.height = 0.4
	well_screw.sides = 8
	well_screw.rotation_degrees = Vector3(0, 0, 90)
	well_screw.material = mat_j
	well_mount.add_child(well_screw)
	var well_head := CSGCylinder3D.new()
	well_head.name = "WellScrewHead"
	well_head.radius = 0.09
	well_head.height = 0.06
	well_head.sides = 6
	well_head.rotation_degrees = Vector3(0, 0, 90)
	well_head.position = hinge * 0.22
	well_head.material = mat_j
	well_mount.add_child(well_head)

	_spu_lever1 = _make_lever_bar("Lever1", _lever1_len, mat_l) ## red
	_spu.add_child(_spu_lever1)
	_spu_lever2 = _make_lever_bar("Lever2", _lever2_len, mat_l) ## green
	_spu.add_child(_spu_lever2)

	_spu_elbow = Node3D.new()
	_spu_elbow.name = "Elbow"
	_spu.add_child(_spu_elbow)
	var elbow_bolt := CSGCylinder3D.new()
	elbow_bolt.radius = 0.05
	elbow_bolt.height = 0.4
	elbow_bolt.sides = 8
	elbow_bolt.rotation_degrees = Vector3(0, 0, 90)
	elbow_bolt.material = mat_j
	_spu_elbow.add_child(elbow_bolt)
	var elbow_nut := CSGCylinder3D.new()
	elbow_nut.radius = 0.09
	elbow_nut.height = 0.07
	elbow_nut.sides = 6
	elbow_nut.rotation_degrees = Vector3(0, 0, 90)
	elbow_nut.position = hinge * 0.16
	elbow_nut.material = mat_j
	_spu_elbow.add_child(elbow_nut)
	var elbow_cap := CSGCylinder3D.new()
	elbow_cap.radius = 0.08
	elbow_cap.height = 0.05
	elbow_cap.sides = 6
	elbow_cap.rotation_degrees = Vector3(0, 0, 90)
	elbow_cap.position = -hinge * 0.16
	elbow_cap.material = mat_j
	_spu_elbow.add_child(elbow_cap)

	# Green end rides the charging-handle hex (no separate phantom eyelet)
	_spu_bracket = Node3D.new()
	_spu_bracket.name = "BoltEyelet"
	_spu.add_child(_spu_bracket)
	var eye_ring := CSGTorus3D.new()
	eye_ring.name = "Eye"
	eye_ring.inner_radius = 0.05
	eye_ring.outer_radius = 0.12
	eye_ring.ring_sides = 8
	eye_ring.sides = 10
	eye_ring.rotation_degrees = Vector3(0, 0, 90)
	eye_ring.material = mat_j
	_spu_bracket.add_child(eye_ring)
	var eye_pin := CSGCylinder3D.new()
	eye_pin.name = "EyePin"
	eye_pin.radius = 0.045
	eye_pin.height = 0.3
	eye_pin.sides = 8
	eye_pin.rotation_degrees = Vector3(0, 0, 90)
	eye_pin.material = mat_j
	_spu_bracket.add_child(eye_pin)

	for nm in ["FeedPawl", "CamRail", "FeedRail", "PivotBlock", "BoltCatch"]:
		var old := _spu.get_node_or_null(nm)
		if old:
			old.visible = false


func update_spu(bolt_face_global: Vector3, handle_global: Vector3, bolt_t: float) -> void:
	if _spu == null:
		return
	# Plane // HandleHex face: same X as handle, fold in YZ (DOWN at rest, straight when aft).
	var local_up := Vector3(0, 1, 0)
	var t := clampf(bolt_t, 0.0, 1.0)
	var handle_local := to_local(handle_global)
	var _face_unused := to_local(bolt_face_global)

	# Well pin: shaft AFT outer wall (nearest the handle), in the hex plane
	var well_pin := _shaft_pin
	if well_pin.length_squared() < 0.01:
		well_pin = Vector3(handle_local.x, handle_local.y, mag_z - 0.55)
	# Lock into hex plane (same lateral station as the handle)
	well_pin.x = handle_local.x
	well_pin.y = handle_local.y

	# Green end on the charging-handle hex
	var bolt_pin := handle_local

	var dist := well_pin.distance_to(bolt_pin)
	var max_reach := _lever1_len + _lever2_len
	var min_reach := absf(_lever1_len - _lever2_len) + 0.08
	if dist > max_reach - 0.02:
		var half_len := dist * 0.5 + 0.02
		_lever1_len = half_len
		_lever2_len = half_len
		_resize_lever_bar(_spu_lever1, _lever1_len)
		_resize_lever_bar(_spu_lever2, _lever2_len)
	elif dist < min_reach:
		# Pins almost coincide — keep a tiny fold span
		bolt_pin = well_pin + Vector3(0, 0, -min_reach)

	var mid := (well_pin + bolt_pin) * 0.5
	var ab := bolt_pin - well_pin
	var d := ab.length()
	var half := d * 0.5
	var h := sqrt(maxf(_lever1_len * _lever1_len - half * half, 0.0))
	var along := ab / maxf(d, 0.001)
	# Fold DOWN at rest (t=0); straighten as bolt goes aft (t→1)
	var fold_dir := -local_up
	fold_dir = fold_dir - along * fold_dir.dot(along)
	if fold_dir.length_squared() < 0.001:
		fold_dir = -local_up
	fold_dir = fold_dir.normalized()
	h *= lerpf(1.0, 0.05, t)
	var elbow := mid + fold_dir * h

	var hinge := Vector3(1, 0, 0)
	var mount_b := Basis(along, local_up, hinge).orthonormalized()
	if _spu_pin_shaft:
		_spu_pin_shaft.position = well_pin
		_spu_pin_shaft.basis = mount_b
		_spu_pin_shaft.scale = Vector3.ONE
	if _spu_bracket:
		_spu_bracket.position = bolt_pin
		_spu_bracket.basis = mount_b
		_spu_bracket.scale = Vector3.ONE
	if _spu_elbow:
		_spu_elbow.position = elbow
		_spu_elbow.basis = mount_b
		_spu_elbow.scale = Vector3.ONE
	if _spu_lever1:
		_orient_rod(_spu_lever1, well_pin, elbow)
	if _spu_lever2:
		_orient_rod(_spu_lever2, elbow, bolt_pin)

	for nm in ["FeedPawl", "CamRail", "FeedRail", "PivotBlock", "BoltCatch"]:
		var old := _spu.get_node_or_null(nm)
		if old:
			old.visible = false

