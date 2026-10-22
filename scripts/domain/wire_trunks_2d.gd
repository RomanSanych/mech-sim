extends RefCounted
## Номера проводов на 2D: середина линии сверху; у групповой линии (rail) — вход/выход.
## Обрыв: парный номер за стрелкой на обоих хвостах (ГОСТ 2.721).

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const WireBreak2D = preload("res://scripts/domain/wire_break_2d.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")

const GRID := 10.0
const MID_ABOVE := 7.0


## {trunks, end_labels, join_labels, group_trunks}.
static func build(circuit, wire_paths: Array) -> Dictionary:
	return labels_for_wires(circuit, wire_paths)


static func end_labels_only(circuit, wire_paths: Array) -> Dictionary:
	return labels_for_wires(circuit, wire_paths)


static func labels_for_wires(circuit, wire_paths: Array) -> Dictionary:
	var empty: Dictionary = {
		"trunks": [], "end_labels": [], "join_labels": [], "group_trunks": []
	}
	if circuit == null or wire_paths.is_empty():
		return empty
	var end_labels: Array = []
	for wi in circuit.wires.size():
		if wi >= wire_paths.size():
			break
		var wire = circuit.wires[wi]
		var pts: PackedVector2Array = wire_paths[wi] as PackedVector2Array
		if pts.size() < 2:
			continue
		var num: int = int(wire.num)
		if num <= 0:
			continue
		var a_el = circuit.get_element(int(wire.a_id))
		if a_el == null:
			continue
		var domain: String = Geom.port_domain(a_el, str(wire.a_port))
		# Обрыв: номер за стрелкой на обоих хвостах.
		if domain == "electric" and WireBreak2D.is_schematic_cut(wire):
			var lab_a: Dictionary = _label_at_break(circuit, wire, true, pts, num)
			var lab_b: Dictionary = _label_at_break(circuit, wire, false, pts, num)
			if not lab_a.is_empty():
				lab_a["pos"] = (lab_a["pos"] as Vector2) + Vector2(wire.num_offset)
				end_labels.append(lab_a)
			if not lab_b.is_empty():
				lab_b["pos"] = (lab_b["pos"] as Vector2) + Vector2(wire.num_offset_b)
				end_labels.append(lab_b)
			continue
		if circuit.has_method("heal_wire_rail_skips"):
			circuit.heal_wire_rail_skips(wire, pts)
		var skip_ids: Array = []
		if circuit.has_method("wire_rail_skip_ids"):
			skip_ids = circuit.wire_rail_skip_ids(wire)
		var vis: Dictionary = Rail2D.visual_for_path(circuit, domain, pts, skip_ids)
		var parts: Array = vis.get("parts", [pts]) as Array
		if parts.is_empty():
			parts = [pts]
		var touches_rail: bool = false
		for part_v in parts:
			var part: PackedVector2Array = part_v as PackedVector2Array
			if part.size() < 2:
				continue
			if Rail2D.point_near_rail(circuit, domain, part[0]) \
					or Rail2D.point_near_rail(circuit, domain, part[part.size() - 1]):
				touches_rail = true
				break
		if touches_rail:
			# Групповая линия: номер у ввода и вывода.
			var part_i: int = 0
			for part_v2 in parts:
				var part2: PackedVector2Array = part_v2 as PackedVector2Array
				if part2.size() < 2:
					continue
				var on_a: bool = Rail2D.point_near_rail(circuit, domain, part2[0])
				var on_b: bool = Rail2D.point_near_rail(circuit, domain, part2[part2.size() - 1])
				if on_a:
					var lab_ra: Dictionary = _label_at_wire_end_placed(
						circuit, part2, true, num, int(wire.id), true, wire_paths, wi
					)
					lab_ra["end"] = "%d_a" % part_i
					lab_ra["pos"] = (lab_ra["pos"] as Vector2) + Vector2(wire.num_offset)
					end_labels.append(lab_ra)
				if on_b:
					var lab_rb: Dictionary = _label_at_wire_end_placed(
						circuit, part2, false, num, int(wire.id), true, wire_paths, wi
					)
					lab_rb["end"] = "%d_b" % part_i
					lab_rb["pos"] = (lab_rb["pos"] as Vector2) + Vector2(wire.num_offset_b)
					end_labels.append(lab_rb)
				part_i += 1
		else:
			var mid_lab: Dictionary = _label_mid_placed(circuit, pts, num, int(wire.id), wire_paths, wi)
			if not mid_lab.is_empty():
				mid_lab["pos"] = (mid_lab["pos"] as Vector2) + Vector2(wire.num_offset)
				end_labels.append(mid_lab)
	_stagger_break_labels(end_labels)
	_deconflict_end_labels(circuit, end_labels, wire_paths)
	return {
		"trunks": [],
		"end_labels": end_labels,
		"join_labels": [],
		"group_trunks": [],
	}


## Два обрыва с одной клеммы: номера не накрывают друг друга (сдвиг ⊥ хвосту).
static func _stagger_break_labels(end_labels: Array) -> void:
	var idxs: Array = []
	for i in end_labels.size():
		var it: Dictionary = end_labels[i] as Dictionary
		if bool(it.get("break", false)):
			idxs.append(i)
	if idxs.size() < 2:
		return
	var used: Dictionary = {}
	for ai in idxs.size():
		var i0: int = int(idxs[ai])
		if used.has(i0):
			continue
		var a: Dictionary = end_labels[i0] as Dictionary
		var pa: Vector2 = a.get("pos", Vector2.ZERO) as Vector2
		var cluster: Array = [i0]
		for bi in range(ai + 1, idxs.size()):
			var i1: int = int(idxs[bi])
			if used.has(i1):
				continue
			var b: Dictionary = end_labels[i1] as Dictionary
			var pb: Vector2 = b.get("pos", Vector2.ZERO) as Vector2
			if pa.distance_to(pb) <= GRID * 2.2:
				cluster.append(i1)
		if cluster.size() < 2:
			continue
		cluster.sort_custom(func(ia, ib):
			var na: int = int((end_labels[int(ia)] as Dictionary).get("num", 0))
			var nb: int = int((end_labels[int(ib)] as Dictionary).get("num", 0))
			if na != nb:
				return na < nb
			return int(ia) < int(ib)
		)
		var n: int = cluster.size()
		for ci in n:
			var li: int = int(cluster[ci])
			used[li] = true
			var lab: Dictionary = end_labels[li] as Dictionary
			var along: Vector2 = lab.get("along", Vector2.RIGHT) as Vector2
			if along.length_squared() < 1.0e-8:
				along = Vector2.RIGHT
			else:
				along = along.normalized()
			var perp: Vector2 = Vector2(-along.y, along.x)
			var slot: float = float(ci) - float(n - 1) * 0.5
			lab["pos"] = (lab["pos"] as Vector2) + perp * (GRID * 1.1 * slot)
			end_labels[li] = lab



## Номер сразу за стрелкой обрыва (вдоль хвоста).
static func _label_at_break(circuit, wire, at_start: bool, pts: PackedVector2Array, num: int) -> Dictionary:
	var tip: Dictionary = WireBreak2D.break_tip(circuit, wire, at_start, pts)
	if tip.is_empty():
		return {}
	var pos: Vector2 = tip["pos"] as Vector2
	var along: Vector2 = tip["dir"] as Vector2
	if along.length_squared() < 1.0e-8:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	# Номер сразу за стрелкой (длина стрелки ≈ 1 клетка).
	pos = pos + along * (GRID * 1.15)
	return {
		"pos": pos,
		"along": along,
		"num": num,
		"wire_id": int(wire.id),
		"end": "a" if at_start else "b",
		"on_rail": false,
		"above": true,
		"break": true,
	}


static func _label_mid_above(pts: PackedVector2Array, num: int, wire_id: int) -> Dictionary:
	if pts.size() < 2:
		return {}
	# Самый длинный сегмент — якорь середины.
	var best_i: int = 0
	var best_len: float = -1.0
	for i in range(pts.size() - 1):
		var L: float = pts[i].distance_to(pts[i + 1])
		if L > best_len:
			best_len = L
			best_i = i
	if best_len < GRID * 0.4:
		var mid: Vector2 = _point_at(pts, _poly_len(pts) * 0.5)
		return {
			"pos": mid + Vector2(0.0, -MID_ABOVE),
			"num": num,
			"wire_id": wire_id,
			"end": "mid",
			"on_rail": false,
			"above": true,
		}
	var a: Vector2 = pts[best_i]
	var b: Vector2 = pts[best_i + 1]
	var mid_seg: Vector2 = (a + b) * 0.5
	# «Сверху» на схеме = −Y (не нормаль к сегменту — иначе на части трасс номер оказывается снизу).
	return {
		"pos": mid_seg + Vector2(0.0, -MID_ABOVE),
		"num": num,
		"wire_id": wire_id,
		"end": "mid",
		"on_rail": false,
		"above": true,
	}


## Номер у длинного сегмента: приоритет справа от жилы, далее CCW; без наезда на УГО/другие жилы.
static func _label_mid_placed(
	circuit, pts: PackedVector2Array, num: int, wire_id: int, all_paths: Array, self_wi: int
) -> Dictionary:
	var base: Dictionary = _label_mid_above(pts, num, wire_id)
	if base.is_empty() or circuit == null:
		return base
	var anchor: Vector2 = (base["pos"] as Vector2) - Vector2(0.0, -MID_ABOVE)
	# anchor = mid_seg; пересчитаем.
	var best_i: int = 0
	var best_len: float = -1.0
	for i in range(pts.size() - 1):
		var L: float = pts[i].distance_to(pts[i + 1])
		if L > best_len:
			best_len = L
			best_i = i
	if best_len >= GRID * 0.4:
		anchor = (pts[best_i] + pts[best_i + 1]) * 0.5
	else:
		anchor = _point_at(pts, _poly_len(pts) * 0.5)
	var bodies: Array = _body_rects(circuit)
	for ring in 4:
		var rad: float = MID_ABOVE + float(ring) * GRID
		for step in 8:
			var a: float = float(step) * TAU / 8.0
			var dir: Vector2 = Vector2(cos(a), -sin(a)) # 0 = справа, CCW
			var pos: Vector2 = anchor + dir * rad
			if _num_pos_hits(pos, bodies, all_paths, self_wi):
				continue
			base["pos"] = pos
			base["along"] = dir
			return base
	return base


static func _num_pos_hits(pos: Vector2, bodies: Array, all_paths: Array, self_wi: int) -> bool:
	var pad: float = 6.0
	for r in bodies:
		if (r as Rect2).grow(pad * 0.35).has_point(pos):
			return true
	for wi in all_paths.size():
		if wi == self_wi:
			continue
		var pts: PackedVector2Array = all_paths[wi] as PackedVector2Array
		for i in range(pts.size() - 1):
			var ab: Vector2 = pts[i + 1] - pts[i]
			var L2: float = ab.length_squared()
			var t: float = 0.0
			if L2 > 1.0e-8:
				t = clampf((pos - pts[i]).dot(ab) / L2, 0.0, 1.0)
			if pos.distance_to(pts[i] + ab * t) < pad:
				return true
	return false


static func _label_at_wire_end(pts: PackedVector2Array, at_start: bool, num: int, wire_id: int, on_rail: bool) -> Dictionary:
	var n: int = pts.size()
	var tip: Vector2 = pts[0] if at_start else pts[n - 1]
	var nxt: Vector2 = pts[1] if at_start else pts[n - 2]
	var along: Vector2 = (nxt - tip)
	if along.length_squared() < 1.0e-8:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	# Чуть от торца вдоль провода + вверх.
	var pos: Vector2 = tip + along * (GRID * 0.85) + Vector2(0.0, -MID_ABOVE * 0.85)
	return {
		"pos": pos,
		"along": along,
		"num": num,
		"wire_id": wire_id,
		"end": "a" if at_start else "b",
		"on_rail": on_rail,
		"above": true,
	}


## Номер у торца / rail-gate: увести с УГО и чужих жил (как mid).
static func _label_at_wire_end_placed(
	circuit, pts: PackedVector2Array, at_start: bool, num: int, wire_id: int, on_rail: bool,
	all_paths: Array, self_wi: int
) -> Dictionary:
	var base: Dictionary = _label_at_wire_end(pts, at_start, num, wire_id, on_rail)
	if base.is_empty() or circuit == null:
		return base
	var tip: Vector2 = pts[0] if at_start else pts[pts.size() - 1]
	var along: Vector2 = base.get("along", Vector2.RIGHT) as Vector2
	if along.length_squared() < 1.0e-8:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	var perp: Vector2 = Vector2(-along.y, along.x)
	var bodies: Array = _body_rects(circuit)
	var cands: Array = [
		base["pos"] as Vector2,
		tip + along * (GRID * 0.85) + Vector2(0.0, -MID_ABOVE),
		tip + along * (GRID * 0.85) + Vector2(0.0, MID_ABOVE),
		tip + along * (GRID * 1.4) + perp * (GRID * 0.9),
		tip + along * (GRID * 1.4) - perp * (GRID * 0.9),
		tip + along * (GRID * 0.5) + perp * (GRID * 1.2),
		tip + along * (GRID * 0.5) - perp * (GRID * 1.2),
		tip + along * (GRID * 2.0) + Vector2(0.0, -MID_ABOVE),
	]
	for pos_v in cands:
		var pos: Vector2 = pos_v as Vector2
		if _num_pos_hits(pos, bodies, all_paths, self_wi):
			continue
		base["pos"] = pos
		return base
	return base


static func _body_rects(circuit) -> Array:
	var bodies: Array = []
	if circuit == null:
		return bodies
	for el in circuit.elements:
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		bodies.append(Geom.world_bounds(el).grow(3.0))
		# Тег элемента тоже не накрывать номером.
		if str(el.tag) != "":
			bodies.append(Geom.tag_world_box(el).grow(2.0))
	return bodies


## Финальный сдвиг номеров, всё ещё попавших на УГО/друг на друга.
static func _deconflict_end_labels(circuit, end_labels: Array, all_paths: Array) -> void:
	if circuit == null or end_labels.is_empty():
		return
	var bodies: Array = _body_rects(circuit)
	var placed: Array = []
	for i in end_labels.size():
		var lab: Dictionary = end_labels[i] as Dictionary
		var pos: Vector2 = lab.get("pos", Vector2.ZERO) as Vector2
		var along: Vector2 = lab.get("along", Vector2.RIGHT) as Vector2
		if along.length_squared() < 1.0e-8:
			along = Vector2.RIGHT
		else:
			along = along.normalized()
		var perp: Vector2 = Vector2(-along.y, along.x)
		var wid: int = int(lab.get("wire_id", -1))
		var self_wi: int = -1
		for wi in circuit.wires.size():
			if int(circuit.wires[wi].id) == wid:
				self_wi = wi
				break
		var best: Vector2 = pos
		var ok: bool = false
		for ring in 5:
			var rad: float = float(ring) * GRID * 0.85
			var dirs: Array = [
				Vector2.ZERO, perp, -perp, along, -along,
				(perp + along).normalized(), (perp - along).normalized(),
				(-perp + along).normalized(), (-perp - along).normalized(),
			]
			for d_v in dirs:
				var d: Vector2 = d_v as Vector2
				var cand: Vector2 = pos + d * rad
				if _num_pos_hits(cand, bodies, all_paths, self_wi):
					continue
				var hit_other: bool = false
				for p2 in placed:
					if cand.distance_to(p2 as Vector2) < GRID * 1.1:
						hit_other = true
						break
				if hit_other:
					continue
				best = cand
				ok = true
				break
			if ok:
				break
		lab["pos"] = best
		end_labels[i] = lab
		placed.append(best)


static func _poly_len(pts: PackedVector2Array) -> float:
	var L: float = 0.0
	for i in range(pts.size() - 1):
		L += pts[i].distance_to(pts[i + 1])
	return L


static func _point_at(pts: PackedVector2Array, dist: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1:
		return pts[0]
	var left: float = maxf(dist, 0.0)
	for i in range(pts.size() - 1):
		var seg: float = pts[i].distance_to(pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			var t: float = 0.0 if seg < 1.0e-8 else clampf(left / seg, 0.0, 1.0)
			return pts[i].lerp(pts[i + 1], t)
		left -= seg
	return pts[pts.size() - 1]
