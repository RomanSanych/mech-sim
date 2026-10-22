func update_spu(bolt_face_global: Vector3, handle_global: Vector3, bolt_t: float) -> void:
	if _spu == null:
		return
	# Plane of the charging-handle hex: same height (Y) as HandleHex, on the feed side.
	# Well lug bolted to the shaft outer face; bolt eyelet on the bolt OD near the FACE.
	var fb: Dictionary = feed_basis()
	var axis: Vector3 = fb["feed_axis"]
	var local_up := Vector3(0, 1, 0)
	var t := clampf(bolt_t, 0.0, 1.0)
	var handle_local := to_local(handle_global)
	var face_local := to_local(bolt_face_global)
	var hy := handle_local.y

	# Well pin: sit on the shaft outer face (from build), height of the hex
	var well_pin := _shaft_pin
	if well_pin.length_squared() < 0.01:
		well_pin = axis * (tube_r + 0.95) + Vector3(0.0, hy, mag_z)
	well_pin.y = hy
	well_pin.z = mag_z

	# Bolt eyelet: feed-side OD of the bolt, near the breech face (rides with bolt Z)
	var br := tube_r * 0.76
	var bolt_pin := axis * (br + 0.4) + Vector3(0.0, hy, face_local.z - 0.15)

	var dist := well_pin.distance_to(bolt_pin)
	# Size bars to the rest span so they don't hang a mile below the shaft at rest
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
	# Fold in the handle plane — local -up (perp floor when upright), mild at rest
	var fold_amt := lerpf(0.55, 0.08, t)
	var fold_dir := -local_up * fold_amt
	fold_dir = fold_dir - along * fold_dir.dot(along)
	if fold_dir.length_squared() < 0.001:
		fold_dir = -axis
		fold_dir = fold_dir - along * fold_dir.dot(along)
	fold_dir = fold_dir.normalized()
	# Cap fold height so the elbow stays near the shaft
	h = minf(h, 0.85)
	var elbow := mid + fold_dir * h

	var hinge := along.cross(fold_dir).normalized()
	if hinge.length_squared() < 0.001:
		hinge = Vector3(0, 0, 1).cross(along).normalized()
	var mount_b := Basis(along, fold_dir, hinge).orthonormalized()
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

