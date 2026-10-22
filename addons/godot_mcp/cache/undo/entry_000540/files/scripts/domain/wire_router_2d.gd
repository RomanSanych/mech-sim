extends RefCounted
## Ортогональная трассировка 2D: лёгкие кандидаты + кэш; A* только при пересечении УГО.

const Geom = preload("res://scripts/domain/symbol_geom.gd")

const GRID := 10.0
const W_EL := 900.0
const W_AWAY := 14.0
## Один лишний угол дороже десятков px длины — без «ступенек» на длинной вертикали.
const W_BEND := 420.0
const EL_HIT_FOR_ASTAR := 0.18
const OWN_PORT_CLEAR := 3.4
const ASTAR_MAX_ITERS := 4000
const MARGIN_CELLS := 28
## Чужое УГО в клетке A* — почти стена (ПЦ/клапаны крупные, мягкий штраф резал корпус).
const FOREIGN_CELL_COST := 90.0
const OWN_BODY_CELL_COST := 14.0
## Порог площади A*-сетки (клетки); плотная схема — шире коридор обхода.
const ASTAR_MAX_CELLS := 36002

static var _layout_hash: int = 0
static var _obs_rects: Array = [] # [{id:int, rect:Rect2}]
static var _path_cache: Dictionary = {} # wire_id -> PackedVector2Array
static var _wire_key_cache: Dictionary = {} # wire_id -> String
static var _batch: bool = false
## Во время drag элементов — только кратчайший Г-маршрут (без A*/скоринга).
static var drag_lite: bool = false
## Ручная правка схемы: без A* — только short/joints (автороут отключён).
static var manual_edit: bool = true
## Id элементов, которые сейчас тащат — чужие провода не перетрассируем.
static var drag_ids: Dictionary = {}
static var _frozen_paths: Dictionary = {} # wire_id -> PackedVector2Array


static func invalidate() -> void:
	_layout_hash = 0
	_batch = false
	_path_cache.clear()
	_wire_key_cache.clear()
	_obs_rects.clear()
	if not drag_lite:
		_frozen_paths.clear()
		drag_ids.clear()


## Только один провод (add) — без сброса кэша остальных.
static func invalidate_wire(wire_id: int) -> void:
	_path_cache.erase(wire_id)
	_wire_key_cache.erase(wire_id)
	_frozen_paths.erase(wire_id)


## Зафиксировать трассы проводов, не связанных с тащимыми элементами.
static func begin_element_drag(circuit, ids: Array) -> void:
	drag_lite = true
	drag_ids.clear()
	_frozen_paths.clear()
	for id in ids:
		drag_ids[int(id)] = true
	if circuit == null:
		return
	_sync_layout(circuit)
	_batch = true
	for wire in circuit.wires:
		var aid: int = int(wire.a_id)
		var bid: int = int(wire.b_id)
		if drag_ids.has(aid) or drag_ids.has(bid):
			continue
		var joints: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
		if not joints.is_empty():
			continue
		var pts: PackedVector2Array = path_for(circuit, wire)
		if pts.size() >= 2:
			_frozen_paths[int(wire.id)] = pts


static func end_element_drag() -> void:
	drag_lite = false
	drag_ids.clear()
	_frozen_paths.clear()
	invalidate()


## Один раз перед пачкой path_for (например в _draw) — без повторного хэша на каждый провод.
static func prepare(circuit) -> void:
	if circuit == null:
		return
	_sync_layout(circuit)
	_batch = true


static func end_batch() -> void:
	_batch = false




static func _circuit_has_rail(circuit) -> bool:
	for el in circuit.elements:
		if str(el.kind) == "rail":
			return true
	return false

static func path_for(circuit, wire) -> PackedVector2Array:
	if circuit == null or wire == null:
		return PackedVector2Array()
	var a = circuit.get_element(int(wire.a_id))
	var b = circuit.get_element(int(wire.b_id))
	if a == null or b == null:
		return PackedVector2Array()
	if str(a.kind) == "rail" or str(b.kind) == "rail":
		# Шина не участвует в топологии провода.
		return PackedVector2Array()
	var joints: Array = wire.joints if typeof(wire.joints) == TYPE_ARRAY else []
	if not joints.is_empty():
		return Geom.polyline(a, str(wire.a_port), b, str(wire.b_port), joints)
	var wid: int = int(wire.id)
	# Чужие провода при drag — замороженный путь (не «плывут» вокруг тащимого УГО).
	if drag_lite and not drag_ids.has(int(a.id)) and not drag_ids.has(int(b.id)) and _frozen_paths.has(wid):
		return _frozen_paths[wid] as PackedVector2Array
	if not _batch:
		_sync_layout(circuit)
	# Ключ включает world-tip: смена раскладки портов (ресивер и т.п.) сбрасывает кэш.
	var pa0: Dictionary = Geom.port_by_name(a, str(wire.a_port))
	var pb0: Dictionary = Geom.port_by_name(b, str(wire.b_port))
	var ta: Vector2 = Geom.to_world(a, pa0["local"]) if not pa0.is_empty() else Vector2.ZERO
	var tb: Vector2 = Geom.to_world(b, pb0["local"]) if not pb0.is_empty() else Vector2.ZERO
	# ROUTE_REV: сброс кэша при смене алгоритма обхода УГО.
	var wkey: String = "r4|%d|%s|%.1f,%.1f|%d|%s|%.1f,%.1f" % [
		int(wire.a_id), str(wire.a_port), ta.x, ta.y,
		int(wire.b_id), str(wire.b_port), tb.x, tb.y,
	]
	if _path_cache.has(wid) and str(_wire_key_cache.get(wid, "")) == wkey:
		return _path_cache[wid] as PackedVector2Array
	# Ручная правка / drag: короткий Г + штраф за чужие трассы (без полного A*).
	var pts: PackedVector2Array
	if drag_lite or manual_edit:
		pts = _short_route(a, str(wire.a_port), b, str(wire.b_port), circuit, wid)
	else:
		pts = route(circuit, wire)
	_path_cache[wid] = pts
	_wire_key_cache[wid] = wkey
	return pts


static func _rail_path(a, a_port: String, b, b_port: String) -> PackedVector2Array:
	const Rail2D = preload("res://scripts/domain/rail_2d.gd")
	if str(a.kind) == "rail" and str(b.kind) != "rail":
		var pts: PackedVector2Array = Rail2D.approach_path(b, b_port, a, a_port)
		pts.reverse()
		return pts
	if str(b.kind) == "rail" and str(a.kind) != "rail":
		return Rail2D.approach_path(a, a_port, b, b_port)
	# Шина–шина: прямая ортогональ между отводами.
	return _short_route(a, a_port, b, b_port)


## Кардиналь нормали порта (±X / ±Y).
static func _ray_cardinal(n: Vector2) -> Vector2:
	if absf(n.x) >= absf(n.y):
		if absf(n.x) < 1.0e-6:
			return Vector2(1.0, 0.0)
		return Vector2(signf(n.x), 0.0)
	if absf(n.y) < 1.0e-6:
		return Vector2(0.0, 1.0)
	return Vector2(0.0, signf(n.y))


## Стык двух полулучей вдоль нормалей; Vector2(INF,INF) если не пересекаются.
static func _half_ray_meet(a: Vector2, na: Vector2, b: Vector2, bn: Vector2) -> Vector2:
	var a_h: bool = absf(na.x) >= absf(na.y)
	var b_h: bool = absf(bn.x) >= absf(bn.y)
	if a_h == b_h:
		# Параллель: стык только если коллинеарны и смотрят друг на друга.
		if a_h:
			if absf(a.y - b.y) > 0.51:
				return Vector2(INF, INF)
			var dx: float = b.x - a.x
			if dx * na.x <= 0.5 or (-dx) * bn.x <= 0.5:
				return Vector2(INF, INF)
			return Vector2((a.x + b.x) * 0.5, a.y)
		if absf(a.x - b.x) > 0.51:
			return Vector2(INF, INF)
		var dy: float = b.y - a.y
		if dy * na.y <= 0.5 or (-dy) * bn.y <= 0.5:
			return Vector2(INF, INF)
		return Vector2(a.x, (a.y + b.y) * 0.5)
	var meet: Vector2
	if a_h:
		meet = Vector2(b.x, a.y)
		if (meet.x - a.x) * na.x <= 0.5:
			return Vector2(INF, INF)
		if (meet.y - b.y) * bn.y <= 0.5:
			return Vector2(INF, INF)
	else:
		meet = Vector2(a.x, b.y)
		if (meet.y - a.y) * na.y <= 0.5:
			return Vector2(INF, INF)
		if (meet.x - b.x) * bn.x <= 0.5:
			return Vector2(INF, INF)
	return meet


## Перпендикуляры к нормали, сначала «от корпуса» УГО.
static func _perp_dirs_away(tip: Vector2, normal: Vector2, body_center: Vector2) -> Array:
	var n: Vector2 = _ray_cardinal(normal)
	var p0: Vector2
	var p1: Vector2
	if absf(n.x) > 0.5:
		p0 = Vector2(0.0, -1.0)
		p1 = Vector2(0.0, 1.0)
	else:
		p0 = Vector2(-1.0, 0.0)
		p1 = Vector2(1.0, 0.0)
	var to_body: Vector2 = body_center - tip
	# Не вести первым шагом в сторону центра УГО.
	if p0.dot(to_body) > p1.dot(to_body):
		return [p1, p0]
	return [p0, p1]


static func _skirt_skip_ids(a_el, b_el, circuit) -> Dictionary:
	var skip: Dictionary = {int(a_el.id): true, int(b_el.id): true}
	if circuit == null:
		return skip
	var ga: int = int(a_el.group_id)
	var gb: int = int(b_el.group_id)
	if ga >= 0:
		skip[ga] = true
	if gb >= 0:
		skip[gb] = true
	# Ноги XS (N/PE) и контакты группы — не «чужие» препятствия для жилы к primary.
	for el in circuit.elements:
		var eid: int = int(el.id)
		if skip.has(eid):
			continue
		var eg: int = int(el.group_id)
		if eg == int(a_el.id) or eg == int(b_el.id) or (ga >= 0 and eg == ga) or (gb >= 0 and eg == gb):
			skip[eid] = true
	return skip


static func _skirt_rects(circuit, skip_ids: Dictionary) -> Array:
	var out: Array = []
	if circuit == null:
		return out
	for el in circuit.elements:
		if str(el.kind) == "rail":
			continue
		var eid: int = int(el.id)
		if skip_ids.has(eid):
			continue
		out.append(Geom.world_bounds(el).grow(GRID))
	return out


static func _seg_hits_skirts(p0: Vector2, p1: Vector2, skirts: Array) -> bool:
	if skirts.is_empty():
		return false
	var dist: float = p0.distance_to(p1)
	var steps: int = maxi(int(ceil(dist / GRID)), 1)
	for s in range(1, steps):
		var t: float = float(s) / float(steps)
		var p: Vector2 = p0.lerp(p1, t)
		for r in skirts:
			if (r as Rect2).has_point(p):
				return true
	return false


static func _path_hits_skirts(pts: PackedVector2Array, skirts: Array) -> bool:
	for i in range(pts.size() - 1):
		if _seg_hits_skirts(pts[i], pts[i + 1], skirts):
			return true
	return false


static func _ortho_cross_count(a: PackedVector2Array, b: PackedVector2Array) -> int:
	var n: int = 0
	for i in range(a.size() - 1):
		var a0: Vector2 = a[i]
		var a1: Vector2 = a[i + 1]
		var a_h: bool = absf(a0.y - a1.y) < 0.51
		for j in range(b.size() - 1):
			var b0: Vector2 = b[j]
			var b1: Vector2 = b[j + 1]
			var b_h: bool = absf(b0.y - b1.y) < 0.51
			if a_h == b_h:
				continue
			if a_h:
				var y: float = a0.y
				var x0: float = minf(a0.x, a1.x)
				var x1: float = maxf(a0.x, a1.x)
				var x: float = b0.x
				var y0: float = minf(b0.y, b1.y)
				var y1: float = maxf(b0.y, b1.y)
				if x > x0 + 0.5 and x < x1 - 0.5 and y > y0 + 0.5 and y < y1 - 0.5:
					n += 1
			else:
				var y2: float = b0.y
				var x2: float = a0.x
				var xa0: float = minf(b0.x, b1.x)
				var xa1: float = maxf(b0.x, b1.x)
				var ya0: float = minf(a0.y, a1.y)
				var ya1: float = maxf(a0.y, a1.y)
				if x2 > xa0 + 0.5 and x2 < xa1 - 0.5 and y2 > ya0 + 0.5 and y2 < ya1 - 0.5:
					n += 1
	return n


static func _path_wire_crosses(pts: PackedVector2Array, others: Array) -> int:
	var n: int = 0
	for other in others:
		n += _ortho_cross_count(pts, other as PackedVector2Array)
	return n


static func _path_has_diagonal(pts: PackedVector2Array) -> bool:
	for i in range(pts.size() - 1):
		if absf(pts[i].x - pts[i + 1].x) > 0.75 and absf(pts[i].y - pts[i + 1].y) > 0.75:
			return true
	return false


static func _ensure_ortho_path(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var clean: PackedVector2Array = Geom.simplify_ortho_path(Geom._dedupe(Geom._ortho(pts)))
	if _path_has_diagonal(clean):
		clean = Geom._dedupe(Geom._ortho(clean))
	return clean


static func _append_ray_cand(cands: Array, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var clean: PackedVector2Array = _ensure_ortho_path(pts)
	if clean.size() >= 2 and not _path_has_diagonal(clean):
		cands.append(clean)


## Обход одного юбка-rect: цепочка по 4 сторонам (+1 уже в grow).
static func _skirt_wrap_paths(a2: Vector2, b2: Vector2, a: Vector2, b: Vector2, skirt: Rect2) -> Array:
	var out: Array = []
	var left: float = skirt.position.x
	var right: float = skirt.end.x
	var top: float = skirt.position.y
	var bot: float = skirt.end.y
	for y in [top, bot]:
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(a2.x, y), Vector2(b2.x, y), b2, b]))
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(a2.x, y), Vector2(left, y), Vector2(left, b2.y), b2, b]))
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(a2.x, y), Vector2(right, y), Vector2(right, b2.y), b2, b]))
	for x in [left, right]:
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(x, a2.y), Vector2(x, b2.y), b2, b]))
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(x, a2.y), Vector2(x, top), Vector2(b2.x, top), b2, b]))
		_append_ray_cand(out, PackedVector2Array([a, a2, Vector2(x, a2.y), Vector2(x, bot), Vector2(b2.x, bot), b2, b]))
	return out


## Автотрасса: полулучи по нормалям → стык; иначе перпендикуляр от УГО; обход bbox±1; без cross важнее длины.
static func _ray_skirt_route(
	a_el, a: Vector2, an: Vector2, b_el, b: Vector2, bn: Vector2, circuit = null, self_wid: int = -1
) -> PackedVector2Array:
	var na: Vector2 = _ray_cardinal(an)
	var nb: Vector2 = _ray_cardinal(bn)
	var skip_ids: Dictionary = _skirt_skip_ids(a_el, b_el, circuit)
	if circuit != null and not _batch:
		_sync_layout(circuit)
	var skirts: Array = _skirt_rects(circuit, skip_ids)
	var others: Array = []
	if circuit != null and self_wid >= 0 and circuit.wires.size() <= 80:
		others = _other_wire_paths(circuit, self_wid)
	var ca: Vector2 = Geom.world_bounds(a_el).get_center()
	var cb: Vector2 = Geom.world_bounds(b_el).get_center()
	var cands: Array = []
	# 1) Стык полулучей — если tip на одной оси навстречу, сразу прямая (без «ступеньки»).
	var meet: Vector2 = _half_ray_meet(a, na, b, nb)
	if meet.x < INF * 0.5:
		var meet_pts: PackedVector2Array = _ensure_ortho_path(PackedVector2Array([a, meet, b]))
		var colinear_face: bool = (
			(absf(a.x - b.x) <= 0.51 and absf(na.x) < 0.5 and absf(nb.x) < 0.5)
			or (absf(a.y - b.y) <= 0.51 and absf(na.y) < 0.5 and absf(nb.y) < 0.5)
		)
		if colinear_face and meet_pts.size() >= 2 and not _path_has_diagonal(meet_pts):
			if _against_port_exit_penalty(meet_pts, a, na, b, nb) < GRID * 40.0:
				return meet_pts
		_append_ray_cand(cands, PackedVector2Array([a, meet, b]))
	# 2) Отростки по нормали + Г / перпендикуляр «от корпуса».
	var depths: Array = [GRID, GRID * 2.0, GRID * 4.0]
	var perps_a: Array = _perp_dirs_away(a, na, ca)
	var perps_b: Array = _perp_dirs_away(b, nb, cb)
	for da in depths:
		var a2: Vector2 = _stub_on_grid(a, na, da)
		for db in depths:
			var b2: Vector2 = _stub_on_grid(b, nb, db)
			_append_ray_cand(cands, PackedVector2Array([a, a2, Vector2(b2.x, a2.y), b2, b]))
			_append_ray_cand(cands, PackedVector2Array([a, a2, Vector2(a2.x, b2.y), b2, b]))
			# Перпендикуляр к отростку, первым — «от» УГО (не в корпус).
			var pad0: Vector2 = perps_a[0] as Vector2
			for ext in [GRID * 2.0, GRID * 4.0, GRID * 6.0]:
				var ap: Vector2 = (a2 + pad0 * ext).snapped(Vector2(GRID, GRID))
				_append_ray_cand(cands, PackedVector2Array([a, a2, ap, Vector2(b2.x, ap.y), b2, b]))
				_append_ray_cand(cands, PackedVector2Array([a, a2, ap, Vector2(ap.x, b2.y), b2, b]))
			var pbd0: Vector2 = perps_b[0] as Vector2
			for ext2 in [GRID * 2.0, GRID * 4.0]:
				var bp: Vector2 = (b2 + pbd0 * ext2).snapped(Vector2(GRID, GRID))
				_append_ray_cand(cands, PackedVector2Array([a, a2, Vector2(a2.x, bp.y), bp, b2, b]))
				_append_ray_cand(cands, PackedVector2Array([a, a2, Vector2(bp.x, a2.y), bp, b2, b]))
	# 3) Обход пересекающих юбок (цепочка по сторонам bbox±1).
	var a0: Vector2 = _stub_on_grid(a, na, GRID * 2.0)
	var b0: Vector2 = _stub_on_grid(b, nb, GRID * 2.0)
	var route_box: Rect2 = Rect2(a, Vector2.ZERO).expand(b).grow(GRID * 2.0)
	var wrap_n: int = 0
	for sk in skirts:
		var sr: Rect2 = sk as Rect2
		if not route_box.intersects(sr):
			continue
		for wp in _skirt_wrap_paths(a0, b0, a, b, sr):
			cands.append(wp)
			wrap_n += 1
			if wrap_n >= 36:
				break
		if wrap_n >= 36:
			break
	if cands.is_empty():
		return PackedVector2Array()
	var best: PackedVector2Array = PackedVector2Array()
	var best_cross: int = 1 << 30
	var best_skirt: int = 1 << 30
	var best_sc: float = 1.0e30
	for c in cands:
		var pts: PackedVector2Array = c as PackedVector2Array
		if pts.size() < 2 or _path_has_diagonal(pts):
			continue
		# Первый шаг — только наружу по нормали.
		if _against_port_exit_penalty(pts, a, na, b, nb) >= GRID * 40.0:
			continue
		if pts.size() >= 2:
			var leave_b: Vector2 = pts[pts.size() - 2] - pts[pts.size() - 1]
			# Заход в tip_b — вдоль нормали наружу (как выход из tip_a).
			if leave_b.length_squared() > 0.25 and leave_b.normalized().dot(nb) < 0.5:
				continue
		var crosses: int = _path_wire_crosses(pts, others)
		var skirt_hit: int = 1 if _path_hits_skirts(pts, skirts) else 0
		var plen: float = Geom.path_length_px(pts)
		var bends: float = float(_count_bends(pts))
		var sc: float = plen + bends * W_BEND
		# Сначала без юбки (не резать УГО), затем без cross, затем короче.
		var better: bool = false
		if skirt_hit < best_skirt:
			better = true
		elif skirt_hit == best_skirt and crosses < best_cross:
			better = true
		elif skirt_hit == best_skirt and crosses == best_cross and sc < best_sc:
			better = true
		if better:
			best_cross = crosses
			best_skirt = skirt_hit
			best_sc = sc
			best = pts
	if best.is_empty() or _path_has_diagonal(best):
		return PackedVector2Array()
	# Грязный луч (режет УГО) — не принимаем; пусть midfield/A* обойдёт.
	if best_skirt > 0:
		return PackedVector2Array()
	return _ensure_ortho_path(best)


static func _short_route(
	a_el, a_port: String, b_el, b_port: String, circuit = null, self_wid: int = -1
) -> PackedVector2Array:
	var pa: Dictionary = Geom.port_by_name(a_el, a_port)
	var pb: Dictionary = Geom.port_by_name(b_el, b_port)
	if pa.is_empty() or pb.is_empty():
		return PackedVector2Array()
	var a: Vector2 = Geom.to_world(a_el, pa["local"])
	var b: Vector2 = Geom.to_world(b_el, pb["local"])
	var an: Vector2 = (pa["normal"] as Vector2).rotated(float(a_el.rotation_quad) * PI * 0.5)
	var bn: Vector2 = (pb["normal"] as Vector2).rotated(float(b_el.rotation_quad) * PI * 0.5)
	# Лучевая трасса — только если НЕ режет чужие УГО (иначе midfield/A*).
	var a_rail: bool = _is_scheme_rail_el(a_el)
	var b_rail: bool = _is_scheme_rail_el(b_el)
	# Лучевая трасса: юбки концов в skip → луч режет рамку клеммника. Для rail — только stub-маршрут.
	if not a_rail and not b_rail:
		var ray_pts: PackedVector2Array = _ray_skirt_route(
			a_el, a, an, b_el, b, bn, circuit, self_wid
		)
		if ray_pts.size() >= 2:
			var ray_skip: Dictionary = _skirt_skip_ids(a_el, b_el, circuit)
			var ray_skirts: Array = _skirt_rects(circuit, ray_skip)
			if not _path_hits_skirts(ray_pts, ray_skirts):
				return ray_pts
	# Отросток кратен сетке — иначе a2/b2 мимо клетки → микроизломы.
	# Электро: пин УГО уже = LEAD; при близких tip stub=0 — иначе обрывы после сдвига на клетку.
	# Клеммник/шина: tip внутри рамки → минимум 2 клетки по нормали до изгиба (как отросток УГО).
	var is_elec: bool = (
		Geom.port_domain(a_el, a_port) == "electric"
		and Geom.port_domain(b_el, b_port) == "electric"
	)
	var stub_a: float = GRID * 2.0
	var stub_b: float = GRID * 2.0
	if is_elec:
		stub_a = GRID * 0.4
		stub_b = GRID * 0.4
		if a.distance_to(b) < GRID * 2.5 and not a_rail and not b_rail:
			stub_a = 0.0
			stub_b = 0.0
	if a_rail:
		stub_a = GRID * 2.0
	if b_rail:
		stub_b = GRID * 2.0
	var stub: float = maxf(stub_a, stub_b)
	var a2: Vector2 = a if stub_a <= 0.01 else _stub_on_grid(a, an, stub_a)
	var b2: Vector2 = b if stub_b <= 0.01 else _stub_on_grid(b, bn, stub_b)
	# Обход — полный bbox; хит-тест — обрезан у tip, иначе полоса у stub «закрывает» прямой Г вниз.
	var ra_obs: Rect2 = Geom.world_bounds(a_el).grow(GRID * 0.35)
	var rb_obs: Rect2 = Geom.world_bounds(b_el).grow(GRID * 0.35)
	var ra: Rect2 = _hit_bounds_clipped(a_el, a, an, GRID * 0.35)
	var rb: Rect2 = _hit_bounds_clipped(b_el, b, bn, GRID * 0.35)
	# Электро: короткий Г только если не режет чужие УГО (иначе обход / A*).
	# Никогда не принимать «Г вниз→вправо» сквозь лестницу без проверки midfield/A*.
	var skip_ids: Dictionary = {int(a_el.id): true, int(b_el.id): true}
	if is_elec:
		var simple: PackedVector2Array = Geom.simplify_ortho_path(
			Geom._dedupe(Geom._ortho(Geom._shortest_ortho_route(a, an, b, bn, stub)))
		)
		if simple.size() >= 2 and _against_port_exit_penalty(simple, a, an, b, bn) < 1.0:
			var simple_f: float = _element_hits(simple, skip_ids, a, b, an, bn, stub, true)
			# Длинные жилы (>8 клеток) — всегда через кандидаты (простой Г режет середину).
			var manh0: float = absf(a.x - b.x) + absf(a.y - b.y)
			if simple_f < 0.02 and manh0 < GRID * 8.0:
				return simple
	var cands: Array = _bus_tap_candidates(a, a2, b, b2, a_el, b_el)
	cands.append_array(_short_avoid_candidates(a, a2, b, b2, an, bn, ra_obs, rb_obs))
	# Коридоры вокруг всех УГО между tip'ами (не только bbox концов).
	cands.append_array(_midfield_avoid_candidates(a, a2, b, b2, skip_ids))
	var others: Array = []
	# Плотные электросхемы: near-others = O(W²·сегменты) → фризы; на >40 жил пропускаем.
	if circuit != null and self_wid >= 0 and circuit.wires.size() <= 40:
		others = _other_wire_paths(circuit, self_wid)
	var best_clear: PackedVector2Array = PackedVector2Array()
	var best_clear_sc: float = 1.0e30
	var best: PackedVector2Array = PackedVector2Array()
	var best_sc: float = 1.0e30
	var prefer_bus: bool = _is_scheme_rail_el(a_el) or _is_scheme_rail_el(b_el)
	for c in cands:
		var pts: PackedVector2Array = c as PackedVector2Array
		if pts.size() < 2:
			continue
		# Stub a2/b2 не схлопывать (коллинеарный tip→a2→left иначе режет КМ1).
		var final_pts: PackedVector2Array = _finalize_short_path(pts, a, a2, b, b2)
		var hits: float = _path_body_hits(final_pts, ra, rb, a, b, an, bn, stub)
		# Чужие УГО — штраф; «чисто» = нет чужих (свой корпус у tip не блокирует обход).
		var foreign: float = _element_hits(final_pts, skip_ids, a, b, an, bn, stub, true)
		var own_pen: float = _element_hits(final_pts, skip_ids, a, b, an, bn, stub, false) - foreign
		var plen: float = Geom.path_length_px(final_pts)
		var bends: float = float(_count_bends(final_pts))
		var away: float = _away_from_target(final_pts, a2, b2)
		var near: float = _path_near_others(final_pts, others)
		# Первый шаг внутрь корпуса (против нормали tip) — типичная «петля» линии 2.
		var back: float = _against_port_exit_penalty(final_pts, a, an, b, bn)
		var manh: float = absf(a.x - b.x) + absf(a.y - b.y)
		# Длинный крюк (линия 2: вверх на −50 вместо Г) — сильный штраф сверх manhattan.
		var detour: float = 0.0
		if plen > manh * 1.45 + GRID * 4.0:
			detour = (plen - manh) * 3.5
		var bus_bonus: float = 0.0
		if prefer_bus and _path_follows_bus_tap(final_pts, a, b, a_el, b_el):
			bus_bonus = GRID * 18.0
		if hits < 0.02 and foreign < 0.02:
			# Прямой спуск от stub важнее крюка вверх→влево вокруг КМ1.
			# near — развести параллельные линии (иначе short кладёт 2/3 на одну клетку).
			var csc: float = bends * W_BEND + plen + away * 55.0 + 80.0 * near + back + detour - bus_bonus
			if csc < best_clear_sc:
				best_clear_sc = csc
				best_clear = final_pts
			continue
		var sc: float = plen + W_EL * (hits + foreign * 1.4 + own_pen * 0.35) + bends * W_BEND + away * 55.0 + 80.0 * near + back + detour - bus_bonus
		if absf(bn.y) > absf(bn.x) and final_pts.size() >= 4:
			var has_outer_y: bool = false
			for i in final_pts.size():
				if absf(final_pts[i].y - b2.y) < 0.51:
					has_outer_y = true
					break
			if has_outer_y:
				sc -= GRID * 3.0
		if sc < best_sc:
			best_sc = sc
			best = final_pts
	if not best_clear.is_empty():
		return best_clear
	# Грязный кандидат: коридор сверху/снизу, затем A*.
	var dirty_hits: float = 99.0
	if not best.is_empty():
		dirty_hits = _element_hits(best, skip_ids, a, b, an, bn, stub, true)
		if dirty_hits < 0.05:
			return best
	var cor: PackedVector2Array = _astar_corridor_fallback(a, a2, b, b2, skip_ids, an, bn, stub)
	if cor.size() >= 2:
		var cor_final: PackedVector2Array = _finalize_short_path(cor, a, a2, b, b2)
		var cor_f: float = _element_hits(cor_final, skip_ids, a, b, an, bn, stub, true)
		if cor_f < 0.05 or cor_f + 0.02 < dirty_hits:
			return cor_final
	var ast: PackedVector2Array = _astar_route(a, a2, b, b2, skip_ids, a, b, an, bn, stub)
	if ast.size() >= 2:
		var ast_final: PackedVector2Array = _finalize_short_path(ast, a, a2, b, b2)
		var ast_foreign: float = _element_hits(ast_final, skip_ids, a, b, an, bn, stub, true)
		# Чистый обход важнее короткого пути сквозь УГО (даже если длиннее).
		if ast_foreign < 0.05:
			return ast_final
		if best.is_empty() or (dirty_hits > 0.08 and ast_foreign + 0.02 < dirty_hits):
			return ast_final
	if not best.is_empty():
		return best
	var fb: PackedVector2Array = Geom._shortest_ortho_route(a, an, b, bn, stub)
	return _finalize_short_path(fb, a, a2, b, b2)


## Snap + simplify середины; концы и отростки a2/b2 сохраняем.
static func _finalize_short_path(
	pts: PackedVector2Array, a: Vector2, a2: Vector2, b: Vector2, b2: Vector2
) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var snapped: PackedVector2Array = _snap_route_grid(pts, a, b)
	var mid := PackedVector2Array()
	mid.append(a2)
	for i in range(1, snapped.size() - 1):
		var p: Vector2 = snapped[i]
		if p.distance_to(a) < 0.75 or p.distance_to(b) < 0.75:
			continue
		if p.distance_to(a2) < 0.75 or p.distance_to(b2) < 0.75:
			continue
		mid.append(p)
	mid.append(b2)
	var mid_s: PackedVector2Array = Geom.simplify_ortho_path(mid)
	var out := PackedVector2Array()
	out.append(a)
	for p in mid_s:
		if out[out.size() - 1].distance_to(p) > 0.5:
			out.append(p)
	if out[out.size() - 1].distance_to(b) > 0.5:
		out.append(b)
	out = Geom._dedupe(Geom._ortho(out))
	out = _flatten_unit_jogs(out)
	return Geom.simplify_ortho_path(out)


## Штраф, если первый шаг от tip не вдоль нормали наружу (вбок/внутрь → кривой stub).
static func _against_port_exit_penalty(
	pts: PackedVector2Array, _a: Vector2, an: Vector2, _b: Vector2, _bn: Vector2
) -> float:
	if pts.size() < 2 or an.length_squared() < 1.0e-8:
		return 0.0
	var d0: Vector2 = pts[1] - pts[0]
	if d0.length_squared() < 0.25:
		return 0.0
	# Раньше только «не внутрь» — боковой микрошаг (линия 7: 210→216) проходил.
	if d0.normalized().dot(an.normalized()) < 0.5:
		return GRID * 48.0
	return 0.0


static func _count_bends(pts: PackedVector2Array) -> int:
	if pts.size() < 3:
		return 0
	var n: int = 0
	for i in range(1, pts.size() - 1):
		var ab: Vector2 = pts[i] - pts[i - 1]
		var bc: Vector2 = pts[i + 1] - pts[i]
		if ab.length_squared() < 0.25 or bc.length_squared() < 0.25:
			continue
		# Поворот, если направления не коллинеарны.
		if absf(ab.x * bc.y - ab.y * bc.x) > 0.5:
			n += 1
	return n


## Убрать ступеньку в 1 клетку на длинной прямой (V–H–V / H–V–H).
static func _flatten_unit_jogs(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 4:
		return pts
	var cur: PackedVector2Array = pts
	for _pass in 4:
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		var i: int = 1
		var changed: bool = false
		while i < cur.size() - 2:
			var p0: Vector2 = nxt[nxt.size() - 1]
			var p1: Vector2 = cur[i]
			var p2: Vector2 = cur[i + 1]
			var p3: Vector2 = cur[i + 2]
			var d01: Vector2 = p1 - p0
			var d12: Vector2 = p2 - p1
			var d23: Vector2 = p3 - p2
			var jog: float = d12.length()
			# Ступенька ~1 клетка между двумя параллельными сегментами одного направления.
			if jog <= GRID * 1.05 + 0.51 and jog >= GRID * 0.5 \
					and d01.length() >= GRID * 0.9 and d23.length() >= GRID * 0.9:
				var h01: bool = absf(d01.y) < 0.51
				var h12: bool = absf(d12.y) < 0.51
				var h23: bool = absf(d23.y) < 0.51
				if h01 != h12 and h01 == h23 and d01.dot(d23) > 0.0:
					# Держим ось более длинного сегмента; p3 сдвигаем — без хвоста-ступеньки.
					var end_pt: Vector2
					if h01:
						var y_keep: float = p0.y if d01.length() >= d23.length() else p3.y
						end_pt = Vector2(p3.x, y_keep)
					else:
						var x_keep: float = p0.x if d01.length() >= d23.length() else p3.x
						end_pt = Vector2(x_keep, p3.y)
					if end_pt.distance_to(p0) > 0.5:
						nxt.append(end_pt)
					changed = true
					i += 3 # p1,p2,p3 заменены на end_pt
					continue
			nxt.append(p1)
			i += 1
		while i < cur.size():
			nxt.append(cur[i])
			i += 1
		nxt = Geom._dedupe(Geom._ortho(nxt))
		if not changed:
			return nxt
		cur = nxt
	return cur


static func _pair_obs_rects(a_el, b_el) -> Array:
	var out: Array = []
	for el in [a_el, b_el]:
		if el == null or str(el.kind) == "rail":
			continue
		var grow: float = GRID * 0.55
		if str(el.kind) == "source":
			grow = GRID * 0.9
		elif str(el.kind) == "valve" or str(el.kind) == "accessory":
			grow = GRID * 0.85
		out.append({"id": int(el.id), "rect": Geom.world_bounds(el).grow(grow)})
	return out


## Bbox для хит-теста: не захватывает полосу снаружи tip по нормали (там stub/подход).
static func _hit_bounds_clipped(el, tip: Vector2, normal: Vector2, grow: float) -> Rect2:
	var r: Rect2 = Geom.world_bounds(el).grow(grow)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return r
	var n: Vector2 = normal
	if absf(n.x) >= absf(n.y):
		if n.x > 0.0:
			var max_r: float = tip.x + 0.75
			if r.position.x + r.size.x > max_r:
				r.size.x = maxf(max_r - r.position.x, GRID * 0.5)
		elif n.x < 0.0:
			var min_l: float = tip.x - 0.75
			if r.position.x < min_l:
				var right: float = r.position.x + r.size.x
				r.position.x = min_l
				r.size.x = maxf(right - min_l, GRID * 0.5)
	else:
		if n.y > 0.0:
			var max_b: float = tip.y + 0.75
			if r.position.y + r.size.y > max_b:
				r.size.y = maxf(max_b - r.position.y, GRID * 0.5)
		elif n.y < 0.0:
			var min_t: float = tip.y - 0.75
			if r.position.y < min_t:
				var bot: float = r.position.y + r.size.y
				r.position.y = min_t
				r.size.y = maxf(bot - min_t, GRID * 0.5)
	return r


## Кандидаты Г/U с обходом полного bbox (слева/справа/сверху/снизу).
static func _is_scheme_rail_el(el) -> bool:
	if el == null:
		return false
	return str(el.electro_class) in ["terminal", "busbar"]


## РКС: вдоль X tip клеммника (вертикаль шины) + короткий гориз. отросток к устройству.
static func _bus_tap_candidates(
	a: Vector2, a2: Vector2, b: Vector2, b2: Vector2, a_el, b_el
) -> Array:
	var out: Array = []
	var a_rail: bool = _is_scheme_rail_el(a_el)
	var b_rail: bool = _is_scheme_rail_el(b_el)
	if a_rail == b_rail:
		return out
	if b_rail:
		var bus_x: float = snappedf(b.x, GRID)
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(bus_x, a2.y), Vector2(bus_x, b.y), b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, a2.y), Vector2(bus_x, a2.y), Vector2(bus_x, b.y), b
		]))))
		# Небольшой сдвиг параллельных отростков (±1 клетка по Y).
		for dy_i in [-1, 1]:
			var ay: float = a2.y + float(dy_i) * GRID
			out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
				a, a2, Vector2(a2.x, ay), Vector2(bus_x, ay), Vector2(bus_x, b.y), b
			]))))
	else:
		var bus_x2: float = snappedf(a.x, GRID)
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, Vector2(bus_x2, a.y), Vector2(bus_x2, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, Vector2(bus_x2, a.y), Vector2(bus_x2, b2.y), Vector2(b2.x, b2.y), b2, b
		]))))
		for dy_i2 in [-1, 1]:
			var by: float = b2.y + float(dy_i2) * GRID
			out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
				a, Vector2(bus_x2, a.y), Vector2(bus_x2, by), Vector2(b2.x, by), b2, b
			]))))
	return out


static func _path_follows_bus_tap(
	pts: PackedVector2Array, a: Vector2, b: Vector2, a_el, b_el
) -> bool:
	if pts.size() < 3:
		return false
	var bus_x: float = 0.0
	if _is_scheme_rail_el(b_el):
		bus_x = snappedf(b.x, GRID)
	elif _is_scheme_rail_el(a_el):
		bus_x = snappedf(a.x, GRID)
	else:
		return false
	var on_bus: float = 0.0
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		if absf(p0.x - bus_x) < 0.6 and absf(p1.x - bus_x) < 0.6:
			on_bus += absf(p1.y - p0.y)
	return on_bus >= GRID * 0.5


## Обход кластера чужих УГО между a2 и b2 (лево/право/верх/низ полосы).
static func _midfield_avoid_candidates(
	a: Vector2, a2: Vector2, b: Vector2, b2: Vector2, skip_ids: Dictionary
) -> Array:
	var out: Array = []
	if _obs_rects.is_empty():
		return out
	var span: Rect2 = Rect2(a2, Vector2.ZERO).expand(b2).grow(GRID * 3.0)
	var left: float = 1.0e9
	var right: float = -1.0e9
	var top: float = 1.0e9
	var bot: float = -1.0e9
	var any: bool = false
	for obs in _obs_rects:
		var oid: int = int(obs["id"])
		if skip_ids.has(oid):
			continue
		var r: Rect2 = obs["rect"]
		if not r.intersects(span):
			continue
		any = true
		left = minf(left, r.position.x)
		right = maxf(right, r.position.x + r.size.x)
		top = minf(top, r.position.y)
		bot = maxf(bot, r.position.y + r.size.y)
	if not any:
		return out
	# Только обход СВЕРХУ/СНИЗУ кластера. Кандидат «sx→горизонталь на b2.y»
	# режет всю лестницу катушек (и A* на длинных жилах не влезает в сетку).
	for pad_i in [3, 6, 10, 14]:
		var pad: float = GRID * float(pad_i)
		var lx: float = floorf((left - pad) / GRID) * GRID
		var rx: float = ceilf((right + pad) / GRID) * GRID
		var ty: float = floorf((top - pad) / GRID) * GRID
		var by: float = ceilf((bot + pad) / GRID) * GRID
		for sy in [ty, by]:
			out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
				a, a2, Vector2(a2.x, sy), Vector2(b2.x, sy), b2, b
			]))))
			for sx in [lx, rx]:
				out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
					a, a2, Vector2(a2.x, sy), Vector2(sx, sy), Vector2(sx, b2.y), b2, b
				]))))
				out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
					a, a2, Vector2(sx, a2.y), Vector2(sx, sy), Vector2(b2.x, sy), b2, b
				]))))
	return out


static func _short_avoid_candidates(
	a: Vector2, a2: Vector2, b: Vector2, b2: Vector2,
	an: Vector2, bn: Vector2, ra: Rect2, rb: Rect2
) -> Array:
	var out: Array = []
	# Прямые Г — первыми (меньше углов): stub → к уровню b2 / под оба УГО.
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([a, a2, Vector2(a2.x, b2.y), b2, b]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([a, a2, Vector2(b2.x, a2.y), b2, b]))))
	# Сдвиг «победного» Г по a2.y / b2.y — иначе два провода с одним stub-Y слипаются.
	for dy_i in [-2, -1, 1, 2]:
		var ay: float = a2.y + float(dy_i) * GRID
		var by: float = b2.y + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, ay), Vector2(b2.x, ay), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, by), Vector2(b2.x, by), b2, b
		]))))
		var bx: float = b2.x + float(dy_i) * GRID
		var ax: float = a2.x + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(bx, a2.y), Vector2(bx, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(ax, a2.y), Vector2(ax, b2.y), b2, b
		]))))
	var obs := ra.merge(rb)
	var left_x: float = floorf((obs.position.x - GRID * 2.0) / GRID) * GRID
	var right_x: float = ceilf((obs.position.x + obs.size.x + GRID * 2.0) / GRID) * GRID
	var top_y: float = floorf((obs.position.y - GRID * 2.0) / GRID) * GRID
	var bot_y: float = ceilf((obs.position.y + obs.size.y + GRID * 2.0) / GRID) * GRID
	# Если цель ниже stub — горизонталь не выше b2.y (без крюка над КМ1).
	var prefer_bot: bool = b2.y >= a2.y - GRID * 0.5
	var lane_y: float = bot_y if prefer_bot else top_y
	var a_left: float = floorf((ra.position.x - GRID * 2.0) / GRID) * GRID
	var a_right: float = ceilf((ra.position.x + ra.size.x + GRID * 2.0) / GRID) * GRID
	var b_left: float = floorf((rb.position.x - GRID * 2.0) / GRID) * GRID
	var b_right: float = ceilf((rb.position.x + rb.size.x + GRID * 2.0) / GRID) * GRID
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, lane_y), Vector2(b2.x, lane_y), b2, b
	]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, bot_y), Vector2(b2.x, bot_y), b2, b
	]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, top_y), Vector2(b2.x, top_y), b2, b
	]))))
	# Параллельные коридоры ±1…2 клетки вокруг lane/top/bot.
	for dy_i in [-2, -1, 1, 2]:
		var ly: float = lane_y + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, ly), Vector2(b2.x, ly), b2, b
		]))))
		var by2: float = bot_y + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, by2), Vector2(b2.x, by2), b2, b
		]))))
		var ty2: float = top_y + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, ty2), Vector2(b2.x, ty2), b2, b
		]))))
		var rx: float = right_x + float(dy_i) * GRID
		var lx: float = left_x + float(dy_i) * GRID
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, top_y), Vector2(rx, top_y), Vector2(rx, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, top_y), Vector2(lx, top_y), Vector2(lx, b2.y), b2, b
		]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, bot_y), Vector2(b_left, bot_y), Vector2(b_left, b2.y), b2, b
	]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, bot_y), Vector2(b_right, bot_y), Vector2(b_right, b2.y), b2, b
	]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, top_y), Vector2(b_left, top_y), Vector2(b_left, b2.y), b2, b
	]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
		a, a2, Vector2(a2.x, top_y), Vector2(b_right, top_y), Vector2(b_right, b2.y), b2, b
	]))))
	# Обход слева/справа: только через top/bot, не tip→left по одной горизонтали.
	for sx in [left_x, right_x, a_left, a_right, b_left, b_right]:
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, bot_y), Vector2(sx, bot_y), Vector2(sx, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, top_y), Vector2(sx, top_y), Vector2(sx, b2.y), b2, b
		]))))
	if absf(an.x) >= absf(an.y):
		var out_x: float = a_right if an.x > 0.0 else a_left
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(out_x, a2.y), Vector2(out_x, bot_y), Vector2(b2.x, bot_y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(out_x, a2.y), Vector2(out_x, top_y), Vector2(b2.x, top_y), b2, b
		]))))
		var side_x: float = right_x if an.x > 0.0 else left_x
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, bot_y), Vector2(side_x, bot_y), Vector2(side_x, b2.y), b2, b
		]))))
	return out


## Отросток от tip: длина ≥ stub, конец на узле сетки по оси нормали.
static func _stub_on_grid(tip: Vector2, normal: Vector2, stub: float) -> Vector2:
	var n: Vector2 = normal
	if absf(n.x) >= absf(n.y):
		n = Vector2(signf(n.x) if absf(n.x) > 1.0e-6 else 1.0, 0.0)
		var x: float = tip.x + n.x * stub
		x = ceilf(x / GRID) * GRID if n.x > 0.0 else floorf(x / GRID) * GRID
		if absf(x - tip.x) < stub - 0.01:
			x += n.x * GRID
		return Vector2(x, tip.y)
	n = Vector2(0.0, signf(n.y) if absf(n.y) > 1.0e-6 else 1.0)
	var y: float = tip.y + n.y * stub
	y = ceilf(y / GRID) * GRID if n.y > 0.0 else floorf(y / GRID) * GRID
	if absf(y - tip.y) < stub - 0.01:
		y += n.y * GRID
	return Vector2(tip.x, y)


## Точка в коридоре отростка (наружу по нормали) — не «шар» вокруг tip (иначе режем КМ1).
static func _in_stub_corridor(p: Vector2, tip: Vector2, normal: Vector2, stub: float) -> bool:
	var n: Vector2 = normal
	if absf(n.x) >= absf(n.y):
		n = Vector2(signf(n.x) if absf(n.x) > 1.0e-6 else 1.0, 0.0)
		var along: float = (p.x - tip.x) * n.x
		if along < -0.51 or along > stub + GRID * 0.6:
			return false
		return absf(p.y - tip.y) <= GRID * 0.55
	n = Vector2(0.0, signf(n.y) if absf(n.y) > 1.0e-6 else 1.0)
	var along_y: float = (p.y - tip.y) * n.y
	if along_y < -0.51 or along_y > stub + GRID * 0.6:
		return false
	return absf(p.x - tip.x) <= GRID * 0.55


## Сколько клеток пути лежит внутри корпусов (не на отростке порта наружу).
static func _path_body_hits(
	pts: PackedVector2Array, ra: Rect2, rb: Rect2,
	port_a: Vector2, port_b: Vector2,
	normal_a: Vector2 = Vector2.ZERO, normal_b: Vector2 = Vector2.ZERO,
	stub: float = GRID * 2.0
) -> float:
	if pts.size() < 2:
		return 0.0
	var hits: float = 0.0
	var step: float = GRID * 0.5
	var has_na: bool = normal_a.length_squared() > 1.0e-6
	var has_nb: bool = normal_b.length_squared() > 1.0e-6
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var dist: float = p0.distance_to(p1)
		var steps: int = maxi(int(ceil(dist / step)), 1)
		for s in range(0, steps + 1):
			var t: float = float(s) / float(steps)
			var p: Vector2 = p0.lerp(p1, t)
			if has_na and _in_stub_corridor(p, port_a, normal_a, stub):
				continue
			if has_nb and _in_stub_corridor(p, port_b, normal_b, stub):
				continue
			# Без нормалей — узкий допуск только у самого tip (legacy).
			if not has_na and p.distance_to(port_a) <= GRID * 0.6:
				continue
			if not has_nb and p.distance_to(port_b) <= GRID * 0.6:
				continue
			if ra.has_point(p) or rb.has_point(p):
				hits += 1.0
	return hits


static func route(circuit, wire) -> PackedVector2Array:
	if circuit == null or wire == null:
		return PackedVector2Array()
	var a_el = circuit.get_element(int(wire.a_id))
	var b_el = circuit.get_element(int(wire.b_id))
	if a_el == null or b_el == null:
		return PackedVector2Array()
	var pa: Dictionary = Geom.port_by_name(a_el, str(wire.a_port))
	var pb: Dictionary = Geom.port_by_name(b_el, str(wire.b_port))
	if pa.is_empty() or pb.is_empty():
		return PackedVector2Array()
	var a: Vector2 = Geom.to_world(a_el, pa["local"])
	var b: Vector2 = Geom.to_world(b_el, pb["local"])
	var an: Vector2 = (pa["normal"] as Vector2).rotated(float(a_el.rotation_quad) * PI * 0.5)
	var bn: Vector2 = (pb["normal"] as Vector2).rotated(float(b_el.rotation_quad) * PI * 0.5)
	var is_elec: bool = (
		Geom.port_domain(a_el, str(wire.a_port)) == "electric"
		and Geom.port_domain(b_el, str(wire.b_port)) == "electric"
	)
	var stub: float = GRID * 0.8 if is_elec else GRID * 2.0
	if is_elec and a.distance_to(b) < GRID * 2.5:
		stub = 0.0
	var a2: Vector2 = a if stub <= 0.01 else _stub_on_grid(a, an, stub)
	var b2: Vector2 = b if stub <= 0.01 else _stub_on_grid(b, bn, stub)
	var skip_ids: Dictionary = {int(a_el.id): true, int(b_el.id): true}
	var cands: Array = _candidates(a, a2, b, b2)
	cands.append_array(_midfield_avoid_candidates(a, a2, b, b2, skip_ids))

	var others: Array = []
	if circuit.wires.size() <= 40:
		others = _other_wire_paths(circuit, int(wire.id))
	var best: PackedVector2Array = PackedVector2Array()
	var best_score: float = 1.0e30
	var best_el_hits: float = 1.0e9
	for c in cands:
		var pts: PackedVector2Array = c as PackedVector2Array
		if pts.size() < 2:
			continue
		var el_h: float = _element_hits(pts, skip_ids, a, b, an, bn, stub)
		var near: float = _path_near_others(pts, others)
		var away: float = _away_from_target(pts, a, b)
		var sc: float = (
			Geom.path_length_px(pts) + W_EL * el_h + 35.0 * near + W_AWAY * away
			+ W_BEND * float(_count_bends(pts))
		)
		if sc < best_score:
			best_score = sc
			best = pts
			best_el_hits = el_h
	if best.is_empty():
		return _flatten_unit_jogs(Geom.simplify_ortho_path(Geom._shortest_ortho_route(a, an, b, bn, stub)))
	# A* только если простой обход режет УГО.
	if best_el_hits >= EL_HIT_FOR_ASTAR:
		var ast: PackedVector2Array = _astar_route(a, a2, b, b2, skip_ids, a, b, an, bn, stub)
		if ast.size() >= 2:
			var el_h2: float = _element_hits(ast, skip_ids, a, b, an, bn, stub)
			var near2: float = _path_near_others(ast, others)
			var away2: float = _away_from_target(ast, a, b)
			var sc2: float = (
				Geom.path_length_px(ast) + W_EL * el_h2 + 35.0 * near2 + W_AWAY * away2
				+ W_BEND * float(_count_bends(ast))
			)
			# Меньше пересечений УГО важнее длины (ПЦ/крупная пневматика).
			if el_h2 + 0.05 < best_el_hits or sc2 + 0.5 < best_score:
				best = ast
	return _flatten_unit_jogs(Geom.simplify_ortho_path(_snap_route_grid(best, a, b)))


## Штраф за сегменты, уводящие дальше от цели (петля влево при цели справа).
static func _away_from_target(pts: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	if pts.size() < 2:
		return 0.0
	var pen: float = 0.0
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var d0: float = p0.distance_to(b)
		var d1: float = p1.distance_to(b)
		if d1 > d0 + GRID * 0.75:
			pen += (d1 - d0) / GRID
		# Отдельный штраф: уход по X от цели, когда уже «не на той» стороне.
		var dx_seg: float = p1.x - p0.x
		if absf(dx_seg) < 0.51:
			continue
		var need_x: float = b.x - a.x
		if absf(need_x) < GRID:
			continue
		if dx_seg * need_x < 0.0:
			pen += absf(dx_seg) / GRID * 0.85
	return pen


static func _other_wire_paths(circuit, self_id: int) -> Array:
	var out: Array = []
	for w in circuit.wires:
		if int(w.id) == self_id:
			continue
		var wid: int = int(w.id)
		if _path_cache.has(wid):
			out.append(_path_cache[wid])
	return out


static func _path_near_others(pts: PackedVector2Array, others: Array) -> float:
	if pts.size() < 2 or others.is_empty():
		return 0.0
	var cost: float = 0.0
	var band: float = GRID * 0.9
	for other in others:
		var b: PackedVector2Array = other as PackedVector2Array
		if b.size() < 2:
			continue
		for i in range(pts.size() - 1):
			var a0: Vector2 = pts[i]
			var a1: Vector2 = pts[i + 1]
			var a_h: bool = absf(a0.y - a1.y) < 0.51
			for j in range(b.size() - 1):
				var b0: Vector2 = b[j]
				var b1: Vector2 = b[j + 1]
				var b_h: bool = absf(b0.y - b1.y) < 0.51
				if a_h != b_h:
					continue
				if a_h:
					if absf(a0.y - b0.y) > band:
						continue
					var ov: float = minf(maxf(a0.x, a1.x), maxf(b0.x, b1.x)) - maxf(minf(a0.x, a1.x), minf(b0.x, b1.x))
					if ov > GRID * 0.4:
						cost += ov / GRID
				else:
					if absf(a0.x - b0.x) > band:
						continue
					var ov2: float = minf(maxf(a0.y, a1.y), maxf(b0.y, b1.y)) - maxf(minf(a0.y, a1.y), minf(b0.y, b1.y))
					if ov2 > GRID * 0.4:
						cost += ov2 / GRID
	return cost


static func _candidates(a: Vector2, a2: Vector2, b: Vector2, b2: Vector2) -> Array:
	var out: Array = []
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([a, a2, Vector2(b2.x, a2.y), b2, b]))))
	out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([a, a2, Vector2(a2.x, b2.y), b2, b]))))
	for pad_mul in [2.0, 4.0, 6.0]:
		var pad: float = GRID * pad_mul
		var min_x: float = minf(a2.x, b2.x) - pad
		var max_x: float = maxf(a2.x, b2.x) + pad
		var min_y: float = minf(a2.y, b2.y) - pad
		var max_y: float = maxf(a2.y, b2.y) + pad
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(min_x, a2.y), Vector2(min_x, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(max_x, a2.y), Vector2(max_x, b2.y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, min_y), Vector2(b2.x, min_y), b2, b
		]))))
		out.append(Geom._dedupe(Geom._ortho(PackedVector2Array([
			a, a2, Vector2(a2.x, max_y), Vector2(b2.x, max_y), b2, b
		]))))
	return out


static func _sync_layout(circuit) -> void:
	var h: int = int(circuit.elements.size()) * 1315423911 + int(circuit.wires.size())
	for el in circuit.elements:
		# Округление до сетки — меньше инвалидаций при микродрожи.
		var gx: int = int(round(float(el.position.x) / GRID))
		var gy: int = int(round(float(el.position.y) / GRID))
		h = ((h << 5) - h) ^ int(el.id)
		h = ((h << 5) - h) ^ gx
		h = ((h << 5) - h) ^ gy
		h = ((h << 5) - h) ^ int(el.rotation_quad)
	if h == _layout_hash and not _obs_rects.is_empty():
		return
	_layout_hash = h
	# Не чистить path_cache: чужие жилы (tip не сдвинулся) остаются как были.
	# Сдвинутые концы — invalidate_wire / смена wkey → пересчёт точечно.
	_obs_rects.clear()
	for el in circuit.elements:
		if str(el.kind) == "rail":
			continue
		var grow: float = GRID * 0.75
		var ecls: String = str(el.electro_class) if str(el.kind) == "electro" else ""
		# Зазор вокруг УГО: иначе ортогональ режет рамку/клеммник/катушку.
		if str(el.kind) == "electro" and ecls == "supply":
			grow = GRID * 1.35
		elif str(el.kind) == "electro" and ecls == "psu":
			grow = GRID * 1.55
		elif str(el.kind) == "electro" and ecls in ["mcb", "rcd", "rcbo"]:
			grow = GRID * 1.2
		elif str(el.kind) == "electro" and ecls == "terminal":
			grow = GRID * 1.1
		elif str(el.kind) == "electro" and ecls in [
			"relay", "timer_relay", "contactor", "thermal", "voltage_relay",
			"solenoid_coil", "lamp", "contact", "button", "e_stop", "switch",
		]:
			grow = GRID * 1.0
		elif str(el.kind) == "sensor":
			grow = GRID * 1.25
		elif str(el.kind) == "source":
			grow = GRID * 1.1
		elif str(el.kind) == "cylinder":
			grow = GRID * 1.35
		elif str(el.kind) == "valve":
			grow = GRID * 1.05
		elif str(el.kind) == "accessory":
			# Отсечной — УГО как 2/2 (порты сверху/снизу), иначе трасса режет корпус.
			if str(el.get("accessory_class") if el.get("accessory_class") != null else "") == "shutoff":
				grow = GRID * 1.05
			else:
				grow = GRID * 0.9
		var r: Rect2 = Geom.world_bounds(el).grow(grow)
		_obs_rects.append({"id": int(el.id), "rect": r})


static func _element_hits(
	pts: PackedVector2Array,
	skip_ids: Dictionary,
	port_a: Vector2 = Vector2.ZERO,
	port_b: Vector2 = Vector2.ZERO,
	normal_a: Vector2 = Vector2.ZERO,
	normal_b: Vector2 = Vector2.ZERO,
	stub: float = GRID * 2.0,
	foreign_only: bool = false
) -> float:
	var hits: float = 0.0
	var step: float = GRID
	var has_na: bool = normal_a.length_squared() > 1.0e-6
	var has_nb: bool = normal_b.length_squared() > 1.0e-6
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var dist: float = p0.distance_to(p1)
		var steps: int = maxi(int(ceil(dist / step)), 1)
		for s in range(1, steps):
			var t: float = float(s) / float(steps)
			var p: Vector2 = p0.lerp(p1, t)
			var at_own_port: bool = false
			if has_na and _in_stub_corridor(p, port_a, normal_a, stub):
				at_own_port = true
			elif has_nb and _in_stub_corridor(p, port_b, normal_b, stub):
				at_own_port = true
			elif not has_na and p.distance_to(port_a) <= GRID * 0.75:
				at_own_port = true
			elif not has_nb and p.distance_to(port_b) <= GRID * 0.75:
				at_own_port = true
			for obs in _obs_rects:
				var oid: int = int(obs["id"])
				if skip_ids.has(oid):
					if foreign_only or at_own_port:
						continue
				var r: Rect2 = obs["rect"]
				if r.has_point(p):
					# Сквозь свой же корпус (далеко от порта) — дороже обычного пересечения.
					hits += (1.6 if skip_ids.has(oid) else 1.0) / float(steps)
					break
	return hits


## A* в узкой полосе сверху/снизу препятствий (длинные L/N/PE жилы).
static func _astar_corridor_fallback(
	a: Vector2, a2: Vector2, b: Vector2, b2: Vector2, skip_ids: Dictionary,
	normal_a: Vector2, normal_b: Vector2, stub: float
) -> PackedVector2Array:
	var span: Rect2 = Rect2(a2, Vector2.ZERO).expand(b2).grow(GRID * 2.0)
	var top: float = 1.0e9
	var bot: float = -1.0e9
	var any: bool = false
	for obs in _obs_rects:
		if skip_ids.has(int(obs["id"])):
			continue
		var r: Rect2 = obs["rect"]
		if not r.intersects(span):
			continue
		any = true
		top = minf(top, r.position.y)
		bot = maxf(bot, r.position.y + r.size.y)
	if not any:
		top = minf(a2.y, b2.y) - GRID * 8.0
		bot = maxf(a2.y, b2.y) + GRID * 8.0
	var best: PackedVector2Array = PackedVector2Array()
	var best_f: float = 1.0e9
	for pad_i in [4, 8, 12]:
		var pad: float = GRID * float(pad_i)
		for sy in [floorf((top - pad) / GRID) * GRID, ceilf((bot + pad) / GRID) * GRID]:
			var via: PackedVector2Array = Geom._dedupe(Geom._ortho(PackedVector2Array([
				a, a2, Vector2(a2.x, sy), Vector2(b2.x, sy), b2, b
			])))
			var f: float = _element_hits(via, skip_ids, a, b, normal_a, normal_b, stub, true)
			if f < best_f:
				best_f = f
				best = via
			if f < 0.02:
				return via
	return best


## Сдвинуть точку наружу из чужого УГО (по нормали порта / по осям).
static func _push_out_of_foreign(
	p: Vector2, skip_ids: Dictionary, normal: Vector2, max_steps: int = 12
) -> Vector2:
	var out: Vector2 = p
	var n: Vector2 = normal
	if n.length_squared() < 1.0e-6:
		n = Vector2(1.0, 0.0)
	elif absf(n.x) >= absf(n.y):
		n = Vector2(signf(n.x), 0.0)
	else:
		n = Vector2(0.0, signf(n.y))
	for _i in max_steps:
		var blocked: bool = false
		for obs in _obs_rects:
			if skip_ids.has(int(obs["id"])):
				continue
			if (obs["rect"] as Rect2).has_point(out):
				blocked = true
				break
		if not blocked:
			return out
		out += n * GRID
	# Нормаль не помогла — шаг по 4 осям.
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var q: Vector2 = p
		for _j in max_steps:
			q += d * GRID
			var hit2: bool = false
			for obs2 in _obs_rects:
				if skip_ids.has(int(obs2["id"])):
					continue
				if (obs2["rect"] as Rect2).has_point(q):
					hit2 = true
					break
			if not hit2:
				return q
	return out


static func _astar_route(
	a: Vector2, a2: Vector2, b: Vector2, b2: Vector2, skip_ids: Dictionary,
	port_a: Vector2 = Vector2.ZERO, port_b: Vector2 = Vector2.ZERO,
	normal_a: Vector2 = Vector2.ZERO, normal_b: Vector2 = Vector2.ZERO,
	stub: float = GRID * 2.0
) -> PackedVector2Array:
	var a2p: Vector2 = _push_out_of_foreign(a2, skip_ids, normal_a)
	var b2p: Vector2 = _push_out_of_foreign(b2, skip_ids, normal_b)
	var min_x: float = minf(minf(a2p.x, b2p.x), minf(a.x, b.x)) - GRID * float(MARGIN_CELLS)
	var max_x: float = maxf(maxf(a2p.x, b2p.x), maxf(a.x, b.x)) + GRID * float(MARGIN_CELLS)
	var min_y: float = minf(minf(a2p.y, b2p.y), minf(a.y, b.y)) - GRID * float(MARGIN_CELLS)
	var max_y: float = maxf(maxf(a2p.y, b2p.y), maxf(a.y, b.y)) + GRID * float(MARGIN_CELLS)
	var origin := Vector2(floorf(min_x / GRID) * GRID, floorf(min_y / GRID) * GRID)
	var w: int = int(ceil((max_x - origin.x) / GRID)) + 1
	var h: int = int(ceil((max_y - origin.y) / GRID)) + 1
	if w < 2 or h < 2:
		return PackedVector2Array()
	# Слишком большая сетка — узкий коридор по Y (верх/низ кластера), иначе A* молчит.
	if w * h > ASTAR_MAX_CELLS:
		return _astar_corridor_fallback(a, a2p, b, b2p, skip_ids, normal_a, normal_b, stub)
	var start: Vector2i = _to_cell(a2p, origin)
	var goal: Vector2i = _to_cell(b2p, origin)
	start = Vector2i(clampi(start.x, 0, w - 1), clampi(start.y, 0, h - 1))
	goal = Vector2i(clampi(goal.x, 0, w - 1), clampi(goal.y, 0, h - 1))
	var open: Dictionary = {}
	var came: Dictionary = {}
	var gscore: Dictionary = {}
	var sk: int = _key(start)
	var gk: int = _key(goal)
	open[sk] = 0.0
	gscore[sk] = 0.0
	var iters: int = 0
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not open.is_empty() and iters < ASTAR_MAX_ITERS:
		iters += 1
		var cur_k: int = _pop_best(open)
		if cur_k == gk:
			var path_cells: Array = _reconstruct(came, cur_k)
			return _cells_to_path(a, a2p, b2p, b, path_cells, origin)
		open.erase(cur_k)
		var cx: int = cur_k >> 16
		var cy: int = cur_k & 0xFFFF
		var cur_g: float = float(gscore.get(cur_k, 1.0e30))
		for d in dirs:
			var nx: int = cx + int(d.x)
			var ny: int = cy + int(d.y)
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nk: int = (nx << 16) | ny
			var world: Vector2 = origin + Vector2(float(nx) + 0.5, float(ny) + 0.5) * GRID
			var oc: float = _cell_obstacle_cost(world, skip_ids, port_a, port_b, normal_a, normal_b, stub)
			# Чужое УГО — непроходимо (иначе короткий путь сквозь ПЦ выигрывает у обхода).
			if oc >= FOREIGN_CELL_COST:
				continue
			var step: float = GRID + oc * 22.0
			var ng: float = cur_g + step
			if ng + 0.01 < float(gscore.get(nk, 1.0e30)):
				came[nk] = cur_k
				gscore[nk] = ng
				open[nk] = ng + float(absi(nx - goal.x) + absi(ny - goal.y)) * GRID
	return PackedVector2Array()


static func _cell_obstacle_cost(
	world: Vector2,
	skip_ids: Dictionary,
	port_a: Vector2 = Vector2.ZERO,
	port_b: Vector2 = Vector2.ZERO,
	normal_a: Vector2 = Vector2.ZERO,
	normal_b: Vector2 = Vector2.ZERO,
	stub: float = GRID * 2.0
) -> float:
	var at_own_port: bool = false
	if normal_a.length_squared() > 1.0e-6 and _in_stub_corridor(world, port_a, normal_a, stub):
		at_own_port = true
	elif normal_b.length_squared() > 1.0e-6 and _in_stub_corridor(world, port_b, normal_b, stub):
		at_own_port = true
	elif normal_a.length_squared() <= 1.0e-6 and world.distance_to(port_a) <= GRID * 0.75:
		at_own_port = true
	elif normal_b.length_squared() <= 1.0e-6 and world.distance_to(port_b) <= GRID * 0.75:
		at_own_port = true
	for obs in _obs_rects:
		var oid: int = int(obs["id"])
		if skip_ids.has(oid) and at_own_port:
			continue
		var r: Rect2 = obs["rect"]
		if r.has_point(world):
			# Любой корпус вне отростка порта — стена (не резать КМ1/золотник).
			return FOREIGN_CELL_COST
	return 0.0


static func _to_cell(p: Vector2, origin: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / GRID)), int(floor((p.y - origin.y) / GRID)))


static func _key(c: Vector2i) -> int:
	return (c.x << 16) | (c.y & 0xFFFF)


static func _pop_best(open: Dictionary) -> int:
	var best_k: int = -1
	var best_f: float = 1.0e30
	for k in open.keys():
		var f: float = float(open[k])
		if f < best_f:
			best_f = f
			best_k = int(k)
	return best_k


static func _reconstruct(came: Dictionary, cur_k: int) -> Array:
	var path: Array = [cur_k]
	while came.has(cur_k):
		cur_k = int(came[cur_k])
		path.append(cur_k)
	path.reverse()
	return path


static func _cells_to_path(a: Vector2, a2: Vector2, b2: Vector2, b: Vector2, cells: Array, origin: Vector2) -> PackedVector2Array:
	var seq := PackedVector2Array()
	seq.append(a)
	seq.append(a2)
	for k in cells:
		var kk: int = int(k)
		var cx: int = kk >> 16
		var cy: int = kk & 0xFFFF
		# Узлы на целой сетке (не +0.5) — иначе 5px «П» между stub и A*.
		seq.append(origin + Vector2(float(cx), float(cy)) * GRID)
	seq.append(b2)
	seq.append(b)
	return Geom.simplify_ortho_path(Geom._dedupe(Geom._ortho(seq)))


## Промежуточные точки — на SCH_GRID; концы портов без сдвига.
static func _snap_route_grid(pts: PackedVector2Array, port_a: Vector2, port_b: Vector2) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	for i in pts.size():
		var p: Vector2 = pts[i]
		if i == 0:
			out.append(port_a)
		elif i == pts.size() - 1:
			out.append(port_b)
		elif p.distance_to(port_a) < 0.75 or p.distance_to(port_b) < 0.75:
			out.append(p)
		else:
			out.append(Vector2(roundf(p.x / GRID) * GRID, roundf(p.y / GRID) * GRID))
	return Geom._dedupe(Geom._ortho(out))
