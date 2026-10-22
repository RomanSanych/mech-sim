func _build_spu() -> void:
	# Per schematic (side + top): two levers in series, vertical hinge screws.
	# Well clevis ─(screw)─ red lever ─(screw)─ green lever ─(hex screw)─ bolt
	# Green sits slightly above red at the elbow; fold is in the horizontal plane.
	_spu = Node3D.new()
	_spu.name = "SPU"
	add_child(_spu)
	var local_up := Vector3(0, 1, 0)
	var fb: Dictionary = feed_basis()
	var axis: Vector3 = fb["feed_axis"]
	var mat_l := _mat_spu if _mat_spu else _mat_tray
	var mat_j := _mat_joint if _mat_joint else mat_l

	_lever1_len = 1.15
	_lever2_len = 1.15

	# --- Well clevis: two lugs + vertical screw (orange pin in schematic) ---
	var well_mount := Node3D.new()
	well_mount.name = "WellMount"
	_spu.add_child(well_mount)
	_spu_pin_shaft = well_mount
	for side in [-1.0, 1.0]:
		var lug := CSGBox3D.new()
		lug.name = "Clevis_%s" % ("A" if side < 0.0 else "B")
		lug.size = Vector3(0.28, 0.1, 0.32)
		lug.position = local_up * (side * 0.12)
		lug.material = mat_l
		well_mount.add_child(lug)
	var well_screw := CSGCylinder3D.new()
	well_screw.name = "WellScrew"
	well_screw.radius = 0.05
	well_screw.height = 0.38
	well_screw.sides = 8
	well_screw.material = mat_j
	well_mount.add_child(well_screw)
	var well_head := CSGCylinder3D.new()
	well_head.name = "WellScrewHead"
	well_head.radius = 0.09
	well_head.height = 0.06
	well_head.sides = 6
	well_head.position = local_up * 0.2
	well_head.material = mat_j
	well_mount.add_child(well_head)
	var well_stub := CSGBox3D.new()
	well_stub.name = "ShaftStub"
	well_stub.size = Vector3(0.35, 0.22, 0.28)
	well_stub.position = -axis * 0.18
	well_stub.material = mat_l
	well_mount.add_child(well_stub)

	_spu_lever1 = _make_lever_bar("Lever1", _lever1_len, mat_l) ## red
	_spu.add_child(_spu_lever1)
	_spu_lever2 = _make_lever_bar("Lever2", _lever2_len, mat_l) ## green (sits above)
	_spu.add_child(_spu_lever2)

	# --- Elbow: vertical screw through both levers ---
	_spu_elbow = Node3D.new()
	_spu_elbow.name = "Elbow"
	_spu.add_child(_spu_elbow)
	var elbow_bolt := CSGCylinder3D.new()
	elbow_bolt.radius = 0.05
	elbow_bolt.height = 0.42
	elbow_bolt.sides = 8
	elbow_bolt.material = mat_j
	_spu_elbow.add_child(elbow_bolt)
	var elbow_nut := CSGCylinder3D.new()
	elbow_nut.radius = 0.09
	elbow_nut.height = 0.07
	elbow_nut.sides = 6
	elbow_nut.position = local_up * 0.18
	elbow_nut.material = mat_j
	_spu_elbow.add_child(elbow_nut)
	var elbow_cap := CSGCylinder3D.new()
	elbow_cap.radius = 0.08
	elbow_cap.height = 0.05
	elbow_cap.sides = 6
	elbow_cap.position = -local_up * 0.16
	elbow_cap.material = mat_j
	_spu_elbow.add_child(elbow_cap)

	# --- Bolt end: hex screw through green lever into bolt eyelet ---
	_spu_bracket = Node3D.new()
	_spu_bracket.name = "BoltEyelet"
	_spu.add_child(_spu_bracket)
	var eye_hex := CSGCylinder3D.new()
	eye_hex.name = "Hex"
	eye_hex.radius = 0.14
	eye_hex.height = 0.12
	eye_hex.sides = 6
	eye_hex.smooth_faces = false
	eye_hex.position = local_up * 0.14
	eye_hex.material = mat_j
	_spu_bracket.add_child(eye_hex)
	var eye_pin := CSGCylinder3D.new()
	eye_pin.name = "EyePin"
	eye_pin.radius = 0.05
	eye_pin.height = 0.36
	eye_pin.sides = 8
	eye_pin.material = mat_j
	_spu_bracket.add_child(eye_pin)
	var eye_tab := CSGBox3D.new()
	eye_tab.name = "Tab"
	eye_tab.size = Vector3(0.22, 0.16, 0.28)
	eye_tab.position = -axis * 0.1
	eye_tab.material = mat_l
	_spu_bracket.add_child(eye_tab)

	for nm in ["FeedPawl", "CamRail", "FeedRail", "PivotBlock", "BoltCatch"]:
		var old := _spu.get_node_or_null(nm)
		if old:
			old.visible = false


func update_spu(bolt_face_global: Vector3, handle_global: Vector3, bolt_t: float) -> void:
	if _spu == null:
		return
	# Schematic: levers collinear along bore when straight; vertical screws; green above red.
	# Fold in the horizontal plane (perp to local up) as bolt travels.
	var fb: Dictionary = feed_basis()
	var axis: Vector3 = fb["feed_axis"]
	var local_up := Vector3(0, 1, 0)
	var t := clampf(bolt_t, 0.0, 1.0)
	var handle_local := to_local(handle_global)
	var face_local := to_local(bolt_face_global)
	var hy := handle_local.y

	# Well pin on shaft outer face
	var well_pin := _shaft_pin
	if well_pin.length_squared() < 0.01:
		well_pin = axis * (tube_r + 0.95) + Vector3(0.0, hy, mag_z)
	well_pin.y = hy
	well_pin.z = mag_z

	# Bolt pin near breech face on feed-side bolt OD
	var br := tube_r * 0.76
	var bolt_pin := axis * (br + 0.4) + Vector3(0.0, hy, face_local.z - 0.15)

	var dist := well_pin.distance_to(bolt_pin)
	var rest_span := maxf(absf(face_local.z - 0.15 - mag_z), 0.35)
	var want := clampf(rest_span * 0.85 + 0.55, 0.85, 2.4)
	if absf(_lever1_len - want) > 0.35 and dist < want * 1.6:
		_lever1_len = want
		_lever2_len = want
		_resize_lever_bar(_spu_lever1, _lever1_len)
		_resize_lever_bar(_spu_lever2, _lever2_len)
	var max_reach := _lever1_len + _lever2_len
	var min_reach := absf(_lever1_len - _lever2_len) + 0.05
	if dist > max_reach - 0.02:
		var half_len := dist * 0.5 + 0.02
		_lever1_len = half_len
		_lever2_len = half_len
		_resize_lever_bar(_spu_lever1, _lever1_len)
		_resize_lever_bar(_spu_lever2, _lever2_len)
	elif dist < min_reach:
		bolt_pin = well_pin + (bolt_pin - well_pin).normalized() * min_reach

	var mid := (well_pin + bolt_pin) * 0.5
	var ab := bolt_pin - well_pin
	var d := ab.length()
	var half := d * 0.5
	var h := sqrt(maxf(_lever1_len * _lever1_len - half * half, 0.0))
	var along := ab / maxf(d, 0.001)
	# Fold sideways in the horizontal plane (schematic top-view motion)
	var fold_dir := along.cross(local_up)
	if fold_dir.length_squared() < 0.001:
		fold_dir = -axis
	fold_dir = fold_dir.normalized()
	# Prefer folding outward (away from bore)
	if fold_dir.dot(axis) < 0.0:
		fold_dir = -fold_dir
	h = minf(h * lerpf(1.0, 0.15, t), 1.1)
	var elbow := mid + fold_dir * h
	# Green lever sits slightly above red at the joint (schematic side view)
	var stack := local_up * 0.08
	var red_a := well_pin
	var red_b := elbow
	var green_a := elbow + stack
	var green_b := bolt_pin + stack

	var mount_b := Basis(along, local_up, fold_dir).orthonormalized()
	if _spu_pin_shaft:
		_spu_pin_shaft.position = well_pin
		_spu_pin_shaft.basis = mount_b
		_spu_pin_shaft.scale = Vector3.ONE
	if _spu_bracket:
		_spu_bracket.position = bolt_pin + stack
		_spu_bracket.basis = mount_b
		_spu_bracket.scale = Vector3.ONE
	if _spu_elbow:
		_spu_elbow.position = elbow + stack * 0.5
		_spu_elbow.basis = mount_b
		_spu_elbow.scale = Vector3.ONE
	if _spu_lever1:
		_orient_rod(_spu_lever1, red_a, red_b)
	if _spu_lever2:
		_orient_rod(_spu_lever2, green_a, green_b)

	for nm in ["FeedPawl", "CamRail", "FeedRail", "PivotBlock", "BoltCatch"]:
		var old := _spu.get_node_or_null(nm)
		if old:
			old.visible = false

