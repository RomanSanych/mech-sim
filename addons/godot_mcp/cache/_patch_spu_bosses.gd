func _build_spu() -> void:
	# Plane // HandleHex face: shaft aft-wall clevis → red → elbow → green → HandleHex.
	# Bolt forward: folded DOWN. Bolt aft: straighten.
	_spu = Node3D.new()
	_spu.name = "SPU"
	add_child(_spu)
	var hinge := Vector3(1, 0, 0)
	var mat_red := _flat(Color(0.72, 0.18, 0.14))
	var mat_green := _flat(Color(0.18, 0.55, 0.28))
	var mat_j := _mat_joint if _mat_joint else _flat(Color(0.35, 0.32, 0.28))

	_lever1_len = 2.05
	_lever2_len = 2.05

	# Marker at clevis center — semicircle lugs live on the shaft
	var well_mount := Node3D.new()
	well_mount.name = "WellMount"
	_spu.add_child(well_mount)
	_spu_pin_shaft = well_mount

	_spu_lever1 = _make_lever_bar("Lever1", _lever1_len, mat_red)
	_spu.add_child(_spu_lever1)
	_spu_lever2 = _make_lever_bar("Lever2", _lever2_len, mat_green)
	_spu.add_child(_spu_lever2)

	# End bosses: always // hinge → coaxial with clevis / elbow / handle stem
	_spu_boss_rw = _make_lever_boss("BossRedWell", mat_j, 0.34)
	_spu.add_child(_spu_boss_rw)
	_spu_boss_re = _make_lever_boss("BossRedElbow", mat_j, 0.34)
	_spu.add_child(_spu_boss_re)
	_spu_boss_ge = _make_lever_boss("BossGreenElbow", mat_j, 0.34)
	_spu.add_child(_spu_boss_ge)
	_spu_boss_gb = _make_lever_boss("BossGreenHandle", mat_j, 0.38)
	_spu.add_child(_spu_boss_gb)

	_spu_elbow = Node3D.new()
	_spu_elbow.name = "Elbow"
	_spu.add_child(_spu_elbow)
	var elbow_bolt := CSGCylinder3D.new()
	elbow_bolt.radius = 0.055
	elbow_bolt.height = 0.78
	elbow_bolt.sides = 8
	elbow_bolt.rotation_degrees = Vector3(0, 0, 90)
	elbow_bolt.material = mat_j
	_spu_elbow.add_child(elbow_bolt)
	var elbow_nut := CSGCylinder3D.new()
	elbow_nut.radius = 0.11
	elbow_nut.height = 0.08
	elbow_nut.sides = 6
	elbow_nut.rotation_degrees = Vector3(0, 0, 90)
	elbow_nut.position = hinge * 0.36
	elbow_nut.material = mat_j
	_spu_elbow.add_child(elbow_nut)
	var elbow_cap := CSGCylinder3D.new()
	elbow_cap.radius = 0.11
	elbow_cap.height = 0.08
	elbow_cap.sides = 6
	elbow_cap.rotation_degrees = Vector3(0, 0, 90)
	elbow_cap.position = -hinge * 0.36
	elbow_cap.material = mat_j
	_spu_elbow.add_child(elbow_cap)

	# Green end rides the charging-handle stem — pin // handle axis
	_spu_bracket = Node3D.new()
	_spu_bracket.name = "BoltEyelet"
	_spu.add_child(_spu_bracket)
	var eye_pin := CSGCylinder3D.new()
	eye_pin.name = "EyePin"
	eye_pin.radius = 0.05
	eye_pin.height = 0.42
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
	# Plane // HandleHex face (hinge ≈ world X): fold in YZ — DOWN at rest, straight when aft.
	var local_up := Vector3(0, 1, 0)
	var t := clampf(bolt_t, 0.0, 1.0)
	var handle_local := to_local(handle_global)
	var _face_unused := to_local(bolt_face_global)

	# Red end: fixed on shaft AFT outer wall (clevis between semicircle lugs)
	var well_pin := _shaft_pin
	if well_pin.length_squared() < 0.01:
		well_pin = Vector3(handle_local.x, 0.05, mag_z - 0.55)

	# Green end: charging-handle hex / stem axis
	var bolt_pin := handle_local

	var dist := well_pin.distance_to(bolt_pin)
	var max_reach := _lever1_len + _lever2_len
	if dist > max_reach - 0.02:
		var half_len := dist * 0.5 + 0.02
		_lever1_len = half_len
		_lever2_len = half_len
		_resize_lever_bar(_spu_lever1, _lever1_len)
		_resize_lever_bar(_spu_lever2, _lever2_len)
	elif dist < 0.05:
		bolt_pin = well_pin + Vector3(0.0, 0.0, -0.05)

	var mid := (well_pin + bolt_pin) * 0.5
	var ab := bolt_pin - well_pin
	var d := ab.length()
	var half := d * 0.5
	var h := sqrt(maxf(_lever1_len * _lever1_len - half * half, 0.0))
	var along := ab / maxf(d, 0.001)
	var fold_dir := -local_up
	fold_dir = fold_dir - along * fold_dir.dot(along)
	if fold_dir.length_squared() < 0.001:
		fold_dir = -local_up
	fold_dir = fold_dir.normalized()
	h *= lerpf(1.0, 0.05, t)
	var elbow := mid + fold_dir * h

	# Stack levers on opposite faces; hinge = handle stem = clevis pin
	var hinge := Vector3(1, 0, 0)
	var sep := 0.28
	var well_r := well_pin + hinge * sep
	var elbow_r := elbow + hinge * sep
	var elbow_g := elbow - hinge * sep
	var bolt_g := bolt_pin - hinge * sep

	# Pins/bosses stay // hinge (never tilt with the fold)
	var pin_b := _hinge_basis(hinge)
	if _spu_pin_shaft:
		_spu_pin_shaft.position = well_pin
		_spu_pin_shaft.basis = pin_b
		_spu_pin_shaft.scale = Vector3.ONE
	if _spu_bracket:
		_spu_bracket.position = bolt_pin
		_spu_bracket.basis = pin_b
		_spu_bracket.scale = Vector3.ONE
	if _spu_elbow:
		_spu_elbow.position = elbow
		_spu_elbow.basis = pin_b
		_spu_elbow.scale = Vector3.ONE

	_place_hinge_boss(_spu_boss_rw, well_r, pin_b)
	_place_hinge_boss(_spu_boss_re, elbow_r, pin_b)
	_place_hinge_boss(_spu_boss_ge, elbow_g, pin_b)
	_place_hinge_boss(_spu_boss_gb, bolt_g, pin_b)

	if _spu_lever1:
		_orient_rod(_spu_lever1, well_r, elbow_r, hinge)
	if _spu_lever2:
		_orient_rod(_spu_lever2, elbow_g, bolt_g, hinge)

	for nm in ["FeedPawl", "CamRail", "FeedRail", "PivotBlock", "BoltCatch"]:
		var old := _spu.get_node_or_null(nm)
		if old:
			old.visible = false


func _resize_lever_bar(rod: Node3D, length: float) -> void:
	if rod == null:
		return
	var bar := rod.get_child(0) as CSGBox3D
	if bar:
		# Slightly short of pin centers so bosses sit clear on the ends
		bar.size = Vector3(0.26, maxf(length - 0.28, 0.2), 0.52)


func _make_joint_pin(nm: String, radius: float) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	var cyl := CSGCylinder3D.new()
	cyl.radius = radius
	cyl.height = 0.28
	cyl.sides = 10
	cyl.rotation_degrees = Vector3(90, 0, 0)
	cyl.material = _mat_joint
	n.add_child(cyl)
	var cap := CSGSphere3D.new()
	cap.radius = radius * 1.15
	cap.radial_segments = 8
	cap.rings = 4
	cap.material = _mat_joint
	n.add_child(cap)
	return n


func _make_lever_boss(nm: String, mat: StandardMaterial3D, height: float) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	var boss := CSGCylinder3D.new()
	boss.radius = 0.15
	boss.height = height
	boss.sides = 12
	# Height along local X → world hinge when parent basis = _hinge_basis
	boss.rotation_degrees = Vector3(0, 0, 90)
	boss.material = mat
	n.add_child(boss)
	return n


func _hinge_basis(hinge: Vector3) -> Basis:
	var x := hinge.normalized()
	var y := Vector3(0, 1, 0)
	if absf(x.dot(y)) > 0.9:
		y = Vector3(0, 0, 1)
	y = (y - x * x.dot(y)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _place_hinge_boss(boss: Node3D, pos: Vector3, pin_b: Basis) -> void:
	if boss == null:
		return
	boss.position = pos
	boss.basis = pin_b
	boss.scale = Vector3.ONE


func _make_lever_bar(nm: String, length: float, mat: StandardMaterial3D) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	# Plate only — end bosses are separate nodes kept // hinge
	var bar := CSGBox3D.new()
	bar.size = Vector3(0.26, maxf(length - 0.28, 0.2), 0.52)
	bar.material = mat
	n.add_child(bar)
	return n


func _orient_rod(rod: Node3D, from_pt: Vector3, to_pt: Vector3, hinge: Vector3 = Vector3(1, 0, 0)) -> void:
	if rod == null:
		return
	var mid := (from_pt + to_pt) * 0.5
	rod.position = mid
	var d := to_pt - from_pt
	var L := d.length()
	if L < 0.001:
		return
	var dir := d / L
	# Stable frame: hinge stays the plate-normal so fold never spins the bar 90°
	var x_axis := hinge.normalized()
	x_axis = (x_axis - dir * x_axis.dot(dir))
	if x_axis.length_squared() < 0.0001:
		var fallback := Vector3(0, 0, 1)
		if absf(dir.dot(fallback)) > 0.9:
			fallback = Vector3(0, 1, 0)
		x_axis = fallback.cross(dir)
	x_axis = x_axis.normalized()
	if x_axis.dot(hinge) < 0.0:
		x_axis = -x_axis
	var z_axis := x_axis.cross(dir).normalized()
	rod.basis = Basis(x_axis, dir, z_axis).orthonormalized()
	rod.scale = Vector3.ONE

