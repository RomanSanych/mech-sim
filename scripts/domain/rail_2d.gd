class_name Rail2D
extends RefCounted
## Ортогональная групповая линия УГО (электро / пневмо; бывш. «шина»): точки, Г-изгиб.

const Geom = preload("res://scripts/domain/symbol_geom.gd")

const GRID := 10.0
const DEFAULT_HALF := 40.0
const HIT_PX := 14.0
const TAP_MERGE := 6.0


static func default_points() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-DEFAULT_HALF, 0.0), Vector2(DEFAULT_HALF, 0.0)])


static func ensure_points(el) -> void:
	if el == null:
		return
	var pts: PackedVector2Array = el.rail_points as PackedVector2Array
	if pts.size() < 2:
		el.rail_points = default_points()
		return
	el.rail_points = ortho_clean(pts)


static func ortho_clean(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 2:
		return default_points()
	var out := PackedVector2Array()
	out.append(pts[0].snapped(Vector2(GRID, GRID)))
	for i in range(1, pts.size()):
		var prev: Vector2 = out[out.size() - 1]
		var cur: Vector2 = pts[i].snapped(Vector2(GRID, GRID))
		var dx: float = absf(cur.x - prev.x)
		var dy: float = absf(cur.y - prev.y)
		if dx < 0.5 and dy < 0.5:
			continue
		if dx >= dy:
			cur.y = prev.y
		else:
			cur.x = prev.x
		if out[out.size() - 1].distance_squared_to(cur) > 0.25:
			out.append(cur)
	if out.size() < 2:
		return default_points()
	return _simplify_collinear(out)


## Убрать коллинеарные вершины и микро-лестницы на шине.
static func _simplify_collinear(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var cur: PackedVector2Array = pts
	for _pass in 4:
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		var changed: bool = false
		var i: int = 1
		while i < cur.size() - 1:
			var a: Vector2 = nxt[nxt.size() - 1]
			var b: Vector2 = cur[i]
			var c: Vector2 = cur[i + 1]
			var ab: Vector2 = b - a
			var bc: Vector2 = c - b
			# Коллинеарный H/V в одном направлении — выкинуть b (не разворот).
			var col_hv: bool = (absf(ab.x) < 0.51 and absf(bc.x) < 0.51) \
				or (absf(ab.y) < 0.51 and absf(bc.y) < 0.51)
			if col_hv and ab.dot(bc) > 0.0:
				changed = true
				i += 1
				continue
			# Разворот 180° на одной оси.
			if col_hv and ab.dot(bc) < -0.01:
				changed = true
				i += 1
				continue
			nxt.append(b)
			i += 1
		nxt.append(cur[cur.size() - 1])
		cur = nxt
		if not changed:
			break
	if cur.size() < 2:
		return default_points()
	return cur


static func world_polyline(el) -> PackedVector2Array:
	ensure_points(el)
	var out := PackedVector2Array()
	for p in el.rail_points:
		out.append(Geom.to_world(el, p))
	return out


static func local_bounds(el) -> Rect2:
	ensure_points(el)
	var pts: PackedVector2Array = el.rail_points
	var r := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		r = r.expand(pts[i])
	return r.grow(8.0)


static func ports(_el) -> Array:
	# Шина УГО — не прибор: клемм/отводов в топологии нет.
	return []


static func point_on_local(el, seg: int, u: float) -> Vector2:
	ensure_points(el)
	var pts: PackedVector2Array = el.rail_points
	var i: int = clampi(seg, 0, maxi(pts.size() - 2, 0))
	return pts[i].lerp(pts[i + 1], clampf(u, 0.0, 1.0))


static func normal_at_seg(el, seg: int) -> Vector2:
	ensure_points(el)
	var pts: PackedVector2Array = el.rail_points
	var i: int = clampi(seg, 0, maxi(pts.size() - 2, 0))
	var d: Vector2 = pts[i + 1] - pts[i]
	if absf(d.x) >= absf(d.y):
		return Vector2.UP
	return Vector2.RIGHT


static func closest_on_rail(el, world: Vector2) -> Dictionary:
	ensure_points(el)
	var best: Dictionary = {}
	var best_d: float = 1.0e9
	var pts_w: PackedVector2Array = world_polyline(el)
	for i in range(pts_w.size() - 1):
		var a: Vector2 = pts_w[i]
		var b: Vector2 = pts_w[i + 1]
		var ab: Vector2 = b - a
		var den: float = ab.length_squared()
		var u: float = 0.0
		if den > 1.0e-8:
			u = clampf((world - a).dot(ab) / den, 0.0, 1.0)
		var foot: Vector2 = a.lerp(b, u)
		var d: float = world.distance_to(foot)
		if d < best_d:
			best_d = d
			best = {
				"seg": i,
				"u": u,
				"world": foot,
				"local": point_on_local(el, i, u),
				"dist": d,
			}
	return best


static func hit_body(el, world: Vector2, zoom: float) -> bool:
	var hit: Dictionary = closest_on_rail(el, world)
	if hit.is_empty():
		return false
	return float(hit.get("dist", 1.0e9)) <= HIT_PX / maxf(zoom, 0.35)


## Путь жилы сейчас визуально входит в эту шину (gates visual_for_path).
static func path_uses_rail(
	circuit, domain: String, pts: PackedVector2Array, rail_id: int, skip_rail_ids: Array = []
) -> bool:
	if circuit == null or pts.size() < 2 or rail_id < 0:
		return false
	if skip_rail_ids.has(rail_id):
		return false
	var vis: Dictionary = visual_for_path(circuit, domain, pts, skip_rail_ids)
	var gates: Array = vis.get("gates", []) as Array
	for g in gates:
		if typeof(g) != TYPE_DICTIONARY:
			continue
		if int(g.get("rail_id", -1)) == rail_id:
			return true
	return false


## Трасса ⊥-клипит конкретную шину (для heal skip).
static func path_clips_rail(el, pts: PackedVector2Array) -> bool:
	if el == null or str(el.kind) != "rail" or pts.size() < 2:
		return false
	var clip: Dictionary = _clip_against_rail(el, pts)
	if clip.is_empty():
		return false
	return bool(clip.get("perp_ok", false))


## Сдвиг точки вдоль деформированной полилинии (тот же сегмент/u, иначе доля длины).
static func map_point_poly_delta(
	p: Vector2, poly0: PackedVector2Array, poly1: PackedVector2Array, thr: float
) -> Vector2:
	if poly0.size() < 2 or poly1.size() < 2:
		return Vector2.ZERO
	var best_d: float = 1.0e9
	var best_seg: int = 0
	var best_u: float = 0.0
	var best_foot: Vector2 = p
	for i in range(poly0.size() - 1):
		var a: Vector2 = poly0[i]
		var b: Vector2 = poly0[i + 1]
		var ab: Vector2 = b - a
		var den: float = ab.length_squared()
		var u: float = 0.0
		if den > 1.0e-8:
			u = clampf((p - a).dot(ab) / den, 0.0, 1.0)
		var foot: Vector2 = a.lerp(b, u)
		var d: float = p.distance_to(foot)
		if d < best_d:
			best_d = d
			best_seg = i
			best_u = u
			best_foot = foot
	if best_d > thr:
		return Vector2.ZERO
	var foot1: Vector2 = best_foot
	if poly1.size() == poly0.size() and best_seg < poly1.size() - 1:
		foot1 = poly1[best_seg].lerp(poly1[best_seg + 1], best_u)
	else:
		var len0: float = 0.0
		for i in range(poly0.size() - 1):
			len0 += poly0[i].distance_to(poly0[i + 1])
		var along: float = 0.0
		for i in range(best_seg):
			along += poly0[i].distance_to(poly0[i + 1])
		along += best_u * poly0[best_seg].distance_to(poly0[best_seg + 1])
		var frac: float = along / maxf(len0, 1.0e-6)
		var len1: float = 0.0
		for i in range(poly1.size() - 1):
			len1 += poly1[i].distance_to(poly1[i + 1])
		var want: float = frac * len1
		var acc: float = 0.0
		foot1 = poly1[poly1.size() - 1]
		for i in range(poly1.size() - 1):
			var seg_len: float = poly1[i].distance_to(poly1[i + 1])
			if acc + seg_len >= want - 1.0e-6 or i == poly1.size() - 2:
				var u1: float = 0.0 if seg_len < 1.0e-8 else clampf((want - acc) / seg_len, 0.0, 1.0)
				foot1 = poly1[i].lerp(poly1[i + 1], u1)
				break
			acc += seg_len
	return foot1 - best_foot


## Визуальный коридор: тонкий провод заходит/выходит из шины ⊥, середина не рисуется.
## Без «притяжения» по nearest (диагонали / заход с торца) — только орто-пересечения трассы с rail.
## skip_rail_ids — шины после «Убрать из групповой» (жила рисуется целиком).
## { "parts": Array[PackedVector2Array], "gates": Array[{pos, rail_id}] }
static func visual_for_path(
	circuit, domain: String, pts: PackedVector2Array, skip_rail_ids: Array = []
) -> Dictionary:
	var empty: Dictionary = {"parts": [pts] if pts.size() >= 2 else [], "gates": []}
	if circuit == null or pts.size() < 2:
		return {"parts": [], "gates": []}
	var best_rail = null
	var best_span: float = -1.0
	var best_clip: Dictionary = {}
	for el in circuit.elements:
		if str(el.kind) != "rail":
			continue
		if skip_rail_ids.has(int(el.id)):
			continue
		var rd: String = "electric" if str(el.rail_domain) == "electric" else "pneumatic"
		if rd != domain:
			continue
		var clip: Dictionary = _clip_against_rail(el, pts)
		if clip.is_empty():
			continue
		# Вход и выход только перпендикулярно оси шины (не вдоль / не с торца).
		if not bool(clip.get("perp_ok", false)):
			continue
		var span: float = float(clip.get("span", 0.0))
		if span <= best_span:
			continue
		best_span = span
		best_rail = el
		best_clip = clip
	if best_rail == null or best_clip.is_empty():
		return empty
	var enter_w: Vector2 = best_clip["enter"] as Vector2
	var exit_w: Vector2 = best_clip["exit"] as Vector2
	var seg_enter: int = int(best_clip.get("seg_enter", 0))
	var seg_exit: int = int(best_clip.get("seg_exit", 0))
	var parts: Array = []
	var part_a2 := PackedVector2Array()
	for i in range(seg_enter + 1):
		part_a2.append(pts[i])
	if part_a2.is_empty():
		part_a2.append(enter_w)
	elif part_a2[part_a2.size() - 1].distance_to(enter_w) <= 0.5:
		part_a2[part_a2.size() - 1] = enter_w
	else:
		part_a2.append(enter_w)
	var part_b2 := PackedVector2Array()
	part_b2.append(exit_w)
	var i_start: int = seg_exit + 1
	if i_start < pts.size():
		var stub: Vector2 = pts[i_start]
		var nh: Dictionary = closest_on_rail(best_rail, stub)
		if not nh.is_empty() and float(nh.get("dist", 1.0e9)) <= 12.0 and stub.distance_to(exit_w) <= GRID * 3.0:
			i_start += 1
	for i in range(i_start, pts.size()):
		var p: Vector2 = pts[i]
		if part_b2[part_b2.size() - 1].distance_to(p) <= 0.5:
			continue
		part_b2.append(p)
	if part_a2.size() >= 2:
		parts.append(Geom._dedupe(part_a2))
	if part_b2.size() >= 2:
		parts.append(Geom._dedupe(part_b2))
	if parts.is_empty():
		return empty
	return {
		"parts": parts,
		"gates": [
			{"pos": enter_w, "rail_id": int(best_rail.id)},
			{"pos": exit_w, "rail_id": int(best_rail.id)},
		],
	}


static func _arc_between_feet(el, ha: Dictionary, hb: Dictionary) -> float:
	var pts_w: PackedVector2Array = world_polyline(el)
	if pts_w.size() < 2:
		return 0.0
	var sa: int = int(ha.get("seg", 0))
	var sb: int = int(hb.get("seg", 0))
	var ua: float = float(ha.get("u", 0.0))
	var ub: float = float(hb.get("u", 0.0))
	if sa > sb or (sa == sb and ua > ub):
		var tmp_s: int = sa
		var tmp_u: float = ua
		sa = sb
		ua = ub
		sb = tmp_s
		ub = tmp_u
	if sa == sb:
		return absf(ub - ua) * pts_w[sa].distance_to(pts_w[sa + 1])
	var span: float = (1.0 - ua) * pts_w[sa].distance_to(pts_w[sa + 1])
	for k in range(sa + 1, sb):
		span += pts_w[k].distance_to(pts_w[k + 1])
	span += ub * pts_w[sb].distance_to(pts_w[sb + 1])
	return span


## Первое и последнее ⊥-пересечение пути с шиной (без касания вдоль).
static func _clip_against_rail(el, pts: PackedVector2Array) -> Dictionary:
	var hits: Array = [] # {seg, t, world, dist, rail_dir}
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var h: Dictionary = _segment_rail_hit(el, a, b, 12.0)
		if h.is_empty():
			continue
		hits.append({
			"seg": i,
			"t": float(h["t"]),
			"world": h["world"] as Vector2,
			"dist": float(h["dist"]),
			"rail_dir": h.get("rail_dir", Vector2.RIGHT) as Vector2,
		})
	if hits.is_empty():
		return {}
	hits.sort_custom(func(x, y):
		var sx: int = int(x["seg"])
		var sy: int = int(y["seg"])
		if sx != sy:
			return sx < sy
		return float(x["t"]) < float(y["t"])
	)
	var first: Dictionary = hits[0]
	var last: Dictionary = hits[hits.size() - 1]
	var enter_w: Vector2 = first["world"] as Vector2
	var exit_w: Vector2 = last["world"] as Vector2
	var seg_enter: int = int(first["seg"])
	var seg_exit: int = int(last["seg"])
	# Одно пересечение без протяжённого коридора — не прячем середину.
	if seg_enter == seg_exit and absf(float(last["t"]) - float(first["t"])) < 0.02:
		return {}
	var span: float = 0.0
	if seg_enter == seg_exit:
		span = absf(float(last["t"]) - float(first["t"])) * pts[seg_enter].distance_to(pts[seg_enter + 1])
	else:
		span = (1.0 - float(first["t"])) * pts[seg_enter].distance_to(pts[seg_enter + 1])
		for k in range(seg_enter + 1, seg_exit):
			span += pts[k].distance_to(pts[k + 1])
		span += float(last["t"]) * pts[seg_exit].distance_to(pts[seg_exit + 1])
	if seg_enter == 0 and float(first["t"]) < 0.02:
		return {}
	# Подход к шине должен быть ⊥ (не вдоль групповой).
	var perp_ok: bool = _wire_seg_perp_rail(pts, seg_enter, first["rail_dir"] as Vector2) \
			and _wire_seg_perp_rail(pts, seg_exit, last["rail_dir"] as Vector2)
	return {
		"enter": enter_w,
		"exit": exit_w,
		"seg_enter": seg_enter,
		"seg_exit": seg_exit,
		"span": maxf(span, GRID * 0.5),
		"perp_ok": perp_ok,
	}


static func _wire_seg_perp_rail(pts: PackedVector2Array, seg: int, rail_dir: Vector2) -> bool:
	if seg < 0 or seg >= pts.size() - 1:
		return false
	var wd: Vector2 = pts[seg + 1] - pts[seg]
	if wd.length_squared() < 0.01 or rail_dir.length_squared() < 0.01:
		return false
	# Ортогональные схемы: |dot| мал → ⊥; большой |dot| → вдоль (запрет).
	return absf(wd.normalized().dot(rail_dir.normalized())) <= 0.35


## Только орто-пересечение сегмента пути с сегментом шины (без sample вдоль).
static func _segment_rail_hit(el, a: Vector2, b: Vector2, _thr: float) -> Dictionary:
	var rail_pts: PackedVector2Array = world_polyline(el)
	for i in range(rail_pts.size() - 1):
		var cross: Dictionary = _ortho_segments_meet(a, b, rail_pts[i], rail_pts[i + 1])
		if cross.is_empty():
			continue
		var tw: Vector2 = cross["p"] as Vector2
		var tt: float = float(cross["t"])
		var rdir: Vector2 = rail_pts[i + 1] - rail_pts[i]
		return {"t": tt, "world": tw, "dist": 0.0, "rail_dir": rdir}
	return {}


static func _ortho_segments_meet(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	# Ортогональные отрезки: один H, другой V (как на схеме).
	var ab_h: bool = absf(a.y - b.y) <= absf(a.x - b.x)
	var cd_h: bool = absf(c.y - d.y) <= absf(c.x - d.x)
	if ab_h == cd_h:
		# Параллельны — пересечения нет (касание вдоль шины обрабатывается sample).
		return {}
	if ab_h:
		var y: float = a.y
		var x0: float = minf(a.x, b.x)
		var x1: float = maxf(a.x, b.x)
		var x: float = c.x
		var y0: float = minf(c.y, d.y)
		var y1: float = maxf(c.y, d.y)
		if x < x0 - 0.1 or x > x1 + 0.1 or y < y0 - 0.1 or y > y1 + 0.1:
			return {}
		var t: float = 0.0 if absf(b.x - a.x) < 1.0e-6 else (x - a.x) / (b.x - a.x)
		return {"p": Vector2(x, y), "t": clampf(t, 0.0, 1.0)}
	var x2: float = a.x
	var y2: float = c.y
	var ya0: float = minf(a.y, b.y)
	var ya1: float = maxf(a.y, b.y)
	var xa0: float = minf(c.x, d.x)
	var xa1: float = maxf(c.x, d.x)
	if x2 < xa0 - 0.1 or x2 > xa1 + 0.1 or y2 < ya0 - 0.1 or y2 > ya1 + 0.1:
		return {}
	var t2: float = 0.0 if absf(b.y - a.y) < 1.0e-6 else (y2 - a.y) / (b.y - a.y)
	return {"p": Vector2(x2, y2), "t": clampf(t2, 0.0, 1.0)}


static func point_near_rail(circuit, domain: String, world: Vector2, thr: float = 10.0) -> bool:
	if circuit == null:
		return false
	for el in circuit.elements:
		if str(el.kind) != "rail":
			continue
		var rd: String = "electric" if str(el.rail_domain) == "electric" else "pneumatic"
		if rd != domain:
			continue
		var hit: Dictionary = closest_on_rail(el, world)
		if not hit.is_empty() and float(hit.get("dist", 1.0e9)) <= thr:
			return true
	return false


static func ensure_tap_at(el, world: Vector2) -> String:
	var hit: Dictionary = closest_on_rail(el, world)
	if hit.is_empty():
		return ""
	var taps: Array = el.rail_taps if typeof(el.rail_taps) == TYPE_ARRAY else []
	var foot_w: Vector2 = hit["world"] as Vector2
	for tap in taps:
		if typeof(tap) != TYPE_DICTIONARY:
			continue
		var loc: Vector2 = point_on_local(el, int(tap.get("seg", 0)), float(tap.get("u", 0.5)))
		var tw: Vector2 = Geom.to_world(el, loc)
		if tw.distance_to(foot_w) <= TAP_MERGE:
			return str(tap.get("name", ""))
	var n: int = int(el.rail_tap_seq) + 1
	el.rail_tap_seq = n
	var name := "t%d" % n
	taps.append({"name": name, "seg": int(hit["seg"]), "u": float(hit["u"])})
	el.rail_taps = taps
	return name


static func prune_unused_taps(circuit, el) -> void:
	if circuit == null or el == null or str(el.kind) != "rail":
		return
	var taps: Array = el.rail_taps if typeof(el.rail_taps) == TYPE_ARRAY else []
	var kept: Array = []
	for tap in taps:
		if typeof(tap) != TYPE_DICTIONARY:
			continue
		var nm := str(tap.get("name", ""))
		if nm != "" and circuit.wire_on(int(el.id), nm) != null:
			kept.append(tap)
	el.rail_taps = kept


static func approach_path(device_el, device_port: String, rail_el, rail_port: String) -> PackedVector2Array:
	var pa: Dictionary = Geom.port_by_name(device_el, device_port)
	var pb: Dictionary = Geom.port_by_name(rail_el, rail_port)
	if pa.is_empty() or pb.is_empty():
		return PackedVector2Array()
	var a: Vector2 = Geom.to_world(device_el, pa["local"])
	var b: Vector2 = Geom.to_world(rail_el, pb["local"])
	var an: Vector2 = (pa["normal"] as Vector2).rotated(float(device_el.rotation_quad) * PI * 0.5)
	if an.length_squared() < 1.0e-8:
		an = Vector2.RIGHT
	an = an.normalized()
	var stub: float = 18.0 if str(rail_el.rail_domain) == "pneumatic" else 8.0
	var a1: Vector2 = a + an * stub
	# Последний шаг к шине — по нормали сегмента (перпендикулярно линии шины).
	var bn: Vector2 = (pb["normal"] as Vector2).rotated(float(rail_el.rotation_quad) * PI * 0.5)
	if bn.length_squared() < 1.0e-8:
		bn = Vector2.UP
	bn = bn.normalized()
	var approach: Vector2 = b - bn * stub * 0.5
	if absf(bn.x) > absf(bn.y):
		# Сегмент вертикальный → нормаль по X; выравниваем Y.
		var mid_h := Vector2(a1.x, approach.y)
		return Geom._dedupe(PackedVector2Array([a, a1, mid_h, approach, b]))
	var mid_v := Vector2(approach.x, a1.y)
	return Geom._dedupe(PackedVector2Array([a, a1, mid_v, approach, b]))


static func hit_vertex(el, world: Vector2, zoom: float) -> int:
	var pts_w: PackedVector2Array = world_polyline(el)
	var thr: float = (HIT_PX * 1.35) / maxf(zoom, 0.35)
	var best: int = -1
	var best_d: float = thr
	for i in range(pts_w.size()):
		var d: float = world.distance_to(pts_w[i])
		# Концы — чуть приоритетнее (продление шины).
		var end_boost: float = 0.0
		if i == 0 or i == pts_w.size() - 1:
			end_boost = thr * 0.15
		if d - end_boost <= best_d:
			best_d = d - end_boost
			best = i
	return best


static func hit_segment_mid(el, world: Vector2, zoom: float) -> int:
	var pts_w: PackedVector2Array = world_polyline(el)
	var thr: float = (HIT_PX * 0.85) / maxf(zoom, 0.35)
	var best: int = -1
	var best_d: float = thr
	for i in range(pts_w.size() - 1):
		var mid: Vector2 = (pts_w[i] + pts_w[i + 1]) * 0.5
		var d: float = world.distance_to(mid)
		if d <= best_d:
			best_d = d
			best = i
	return best


static func remove_vertex(el, index: int) -> bool:
	ensure_points(el)
	var snaps: Array = _tap_world_snapshot(el)
	var pts: PackedVector2Array = el.rail_points.duplicate()
	if index < 0 or index >= pts.size() or pts.size() <= 2:
		return false
	pts.remove_at(index)
	el.rail_points = ortho_clean(pts)
	_retarget_taps(el, snaps)
	return el.rail_points.size() >= 2


static func move_vertex(el, index: int, world: Vector2) -> int:
	ensure_points(el)
	var pts: PackedVector2Array = el.rail_points.duplicate()
	if index < 0 or index >= pts.size():
		return index
	var n: int = pts.size()
	var is_end: bool = index == 0 or index == n - 1
	if is_end and n >= 2:
		# Без якоря сессии — якорь = соседняя вершина (не наращивать ступеньки).
		var anchor: int = 1 if index == 0 else n - 2
		return move_end(el, anchor, index == 0, world)
	# Угол между фиксированными соседями — одна вершина, без сдвига соседей.
	var snaps: Array = _tap_world_snapshot(el)
	var local: Vector2 = Geom.to_local(el, world).snapped(Vector2(GRID, GRID))
	var prev: Vector2 = pts[index - 1]
	var nxt: Vector2 = pts[index + 1]
	var c_hv := Vector2(nxt.x, prev.y)
	var c_vh := Vector2(prev.x, nxt.y)
	var corner: Vector2 = c_hv if local.distance_squared_to(c_hv) <= local.distance_squared_to(c_vh) else c_vh
	pts[index] = corner
	el.rail_points = ortho_clean(pts)
	_retarget_taps(el, snaps)
	# После simplify индекс угла может сдвинуться — ищем ближайший к выбранному углу.
	var best_i: int = 0
	var best_d: float = 1.0e9
	for i in el.rail_points.size():
		var d: float = (el.rail_points[i] as Vector2).distance_squared_to(corner)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


## Продление / «Г» от фиксированного якоря (якорь не меняется за всю тягу).
## from_start=true — тянем pts[0]; иначе — последний конец.
static func move_end(el, anchor_i: int, from_start: bool, world: Vector2) -> int:
	ensure_points(el)
	var snaps: Array = _tap_world_snapshot(el)
	var pts: PackedVector2Array = el.rail_points.duplicate()
	var n: int = pts.size()
	if n < 2:
		return 0
	anchor_i = clampi(anchor_i, 0, n - 1)
	if from_start and anchor_i < 1:
		anchor_i = 1
	if not from_start and anchor_i > n - 2:
		anchor_i = n - 2
	var adj: Vector2 = pts[anchor_i]
	var local: Vector2 = Geom.to_local(el, world).snapped(Vector2(GRID, GRID))
	var prefer_h: bool = _end_prefer_horizontal(pts, anchor_i, from_start)
	var tip_part: PackedVector2Array = _end_tip_from_anchor(adj, local, prefer_h)
	var out := PackedVector2Array()
	if from_start:
		# tip_part = [adj … tip] → [tip … adj] + хвост после якоря.
		for i in range(tip_part.size() - 1, -1, -1):
			out.append(tip_part[i])
		for i in range(anchor_i + 1, n):
			out.append(pts[i])
	else:
		for i in range(anchor_i):
			out.append(pts[i])
		for p in tip_part:
			out.append(p)
	el.rail_points = ortho_clean(out)
	_retarget_taps(el, snaps)
	if from_start:
		return 0
	return maxi(el.rail_points.size() - 1, 0)


static func _end_prefer_horizontal(pts: PackedVector2Array, anchor_i: int, from_start: bool) -> bool:
	if from_start:
		if anchor_i + 1 < pts.size():
			var nxt: Vector2 = pts[anchor_i + 1]
			var adj: Vector2 = pts[anchor_i]
			return absf(nxt.x - adj.x) >= absf(nxt.y - adj.y)
	else:
		if anchor_i >= 1:
			var prev: Vector2 = pts[anchor_i - 1]
			var adj2: Vector2 = pts[anchor_i]
			return absf(adj2.x - prev.x) >= absf(adj2.y - prev.y)
		if anchor_i + 1 < pts.size():
			var tip0: Vector2 = pts[anchor_i + 1]
			var adj3: Vector2 = pts[anchor_i]
			return absf(tip0.x - adj3.x) >= absf(tip0.y - adj3.y)
	return true


## От якоря: вдоль оси (удлинить/укоротить) или один перпендикуляр → «Г».
static func _end_tip_from_anchor(adj: Vector2, local: Vector2, prefer_h: bool) -> PackedVector2Array:
	var dx: float = local.x - adj.x
	var dy: float = local.y - adj.y
	# Липкий коридор: внутри — только продление, без угла.
	var corridor: float = GRID * 0.99
	var out := PackedVector2Array()
	out.append(adj)
	if prefer_h:
		if absf(dy) < corridor:
			var tip_h := Vector2(local.x, adj.y)
			if absf(tip_h.x - adj.x) < GRID * 0.5:
				tip_h.x = adj.x + (GRID if dx >= 0.0 else -GRID)
			out.append(tip_h)
			return out
		if absf(dx) < GRID * 0.5:
			var tip_v := Vector2(adj.x, local.y)
			if absf(tip_v.y - adj.y) < GRID * 0.5:
				tip_v.y = adj.y + (GRID if dy >= 0.0 else -GRID)
			out.append(tip_v)
			return out
		var elbow_h := Vector2(local.x, adj.y)
		out.append(elbow_h)
		out.append(Vector2(local.x, local.y))
		return out
	if absf(dx) < corridor:
		var tip_v2 := Vector2(adj.x, local.y)
		if absf(tip_v2.y - adj.y) < GRID * 0.5:
			tip_v2.y = adj.y + (GRID if dy >= 0.0 else -GRID)
		out.append(tip_v2)
		return out
	if absf(dy) < GRID * 0.5:
		var tip_h2 := Vector2(local.x, adj.y)
		if absf(tip_h2.x - adj.x) < GRID * 0.5:
			tip_h2.x = adj.x + (GRID if dx >= 0.0 else -GRID)
		out.append(tip_h2)
		return out
	var elbow_v := Vector2(adj.x, local.y)
	out.append(elbow_v)
	out.append(Vector2(local.x, local.y))
	return out


## Тяга середины сегмента. Возвращает актуальный индекс сегмента (после вставки U — средний).
## Прямая (2 точки) — один раз вставить «П»; иначе только сдвигать сегмент, без новых вершин.
static func insert_vertex_from_mid(el, seg: int, world: Vector2) -> int:
	ensure_points(el)
	var snaps: Array = _tap_world_snapshot(el)
	var pts: PackedVector2Array = el.rail_points.duplicate()
	if seg < 0 or seg >= pts.size() - 1:
		return seg
	var local: Vector2 = Geom.to_local(el, world).snapped(Vector2(GRID, GRID))
	var a: Vector2 = pts[seg]
	var b: Vector2 = pts[seg + 1]
	var horiz: bool = absf(b.x - a.x) >= absf(b.y - a.y)
	if pts.size() == 2:
		# Первый изгиб: A–B → A–угол–угол–B.
		if horiz:
			var y0: float = local.y
			if absf(y0 - a.y) < GRID * 0.5:
				return seg
			pts.insert(1, Vector2(a.x, y0))
			pts.insert(2, Vector2(b.x, y0))
		else:
			var x0: float = local.x
			if absf(x0 - a.x) < GRID * 0.5:
				return seg
			pts.insert(1, Vector2(x0, a.y))
			pts.insert(2, Vector2(x0, b.y))
		el.rail_points = ortho_clean(pts)
		_retarget_taps(el, snaps)
		return 1 if el.rail_points.size() >= 4 else 0
	# Уже есть изломы — сдвигаем выбранный сегмент, соседи удлиняются/укорачиваются.
	if horiz:
		var y: float = local.y
		if absf(y - a.y) < 0.5 and absf(y - b.y) < 0.5:
			return seg
		pts[seg].y = y
		pts[seg + 1].y = y
	else:
		var x: float = local.x
		if absf(x - a.x) < 0.5 and absf(x - b.x) < 0.5:
			return seg
		pts[seg].x = x
		pts[seg + 1].x = x
	el.rail_points = ortho_clean(pts)
	_retarget_taps(el, snaps)
	# После simplify сегмент может схлопнуться — ищем ближайший к курсору.
	var hit_seg: int = hit_segment_mid(el, world, 1.0)
	if hit_seg >= 0:
		return hit_seg
	return clampi(seg, 0, maxi(el.rail_points.size() - 2, 0))


static func _tap_world_snapshot(el) -> Array:
	var taps: Array = el.rail_taps if typeof(el.rail_taps) == TYPE_ARRAY else []
	var out: Array = []
	for tap in taps:
		if typeof(tap) != TYPE_DICTIONARY:
			continue
		var nm := str(tap.get("name", ""))
		if nm == "":
			continue
		var loc: Vector2 = point_on_local(el, int(tap.get("seg", 0)), float(tap.get("u", 0.5)))
		out.append({"name": nm, "world": Geom.to_world(el, loc)})
	return out


static func _retarget_taps(el, snaps: Array = []) -> void:
	if snaps.is_empty():
		snaps = _tap_world_snapshot(el)
	var updated: Array = []
	for snap in snaps:
		if typeof(snap) != TYPE_DICTIONARY:
			continue
		var w: Vector2 = snap.get("world", Vector2.ZERO) as Vector2
		var hit: Dictionary = closest_on_rail(el, w)
		if hit.is_empty():
			continue
		updated.append({
			"name": str(snap.get("name", "")),
			"seg": int(hit["seg"]),
			"u": float(hit["u"]),
		})
	el.rail_taps = updated
