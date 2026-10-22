extends RefCounted
## Прототип авторасстановки и автотрассировки электросхемы.
## Зоны слева направо, трассы по фиксированным коридорам (не свободный A*).
## Сила и управление не делят коридор. Общий возврат / ввод — групповая линия.
## Длинная сила через таблицу управления — визуальный обрыв, не змейка.

const Geom = preload("res://scripts/domain/symbol_geom.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")

const GRID := 10.0
const GAP := 30.0
const STUB := 40.0
const BREAK_CROSS := 4
const BREAK_LEN := 260.0


static func arrange(circuit) -> Dictionary:
	if circuit == null:
		return {"ok": false, "moved": 0, "rails": 0, "broken": 0, "rungs": 0}
	var orig: Dictionary = {}
	var old_bb: Rect2 = _bounds_of(circuit, orig)
	var old_center: Vector2 = old_bb.get_center() if orig.size() > 0 else Vector2.ZERO
	_drop_rails(circuit)
	_detach_wired_contacts(circuit)
	_clear_electric_routes(circuit)
	var orig_y: Dictionary = {}
	var orig_x: Dictionary = {}
	for el in circuit.elements:
		orig_y[int(el.id)] = float(el.position.y)
		orig_x[int(el.id)] = float(el.position.x)
	var rungs: Array = _build_rungs(circuit, orig_y)
	var claimed: Dictionary = {}
	_claim_rungs(rungs, claimed)
	var power_rows: Array = _power_rows(circuit, claimed, orig_x)
	for row in power_rows:
		for idv in row as Array:
			claimed[int(idv)] = true
	var terms: Dictionary = _classify_terminals(circuit, claimed)
	var origin: Vector2 = old_bb.position.snapped(Vector2(GRID, GRID))
	var placed: Dictionary = {}
	var cursor_y: float = origin.y
	var zone_a: Rect2 = _place_zone_a(circuit, origin, placed)
	cursor_y = maxf(cursor_y, zone_a.position.y + zone_a.size.y)
	var breakers: Dictionary = _split_breakers(circuit, orig_x, orig_y)
	var zone_b: Rect2 = _place_breakers(circuit, zone_a, origin.y, breakers, placed)
	_align_supply_to_breakers(circuit, placed)
	zone_a = _bounds_placed(circuit, placed, zone_a)
	zone_b = _bounds_placed(circuit, placed, zone_b)
	var col_skip: Dictionary = _column_id_set(circuit, rungs)
	var y_power_bottom: float = maxf(zone_a.position.y + zone_a.size.y, zone_b.position.y + zone_b.size.y)
	var y_bus: float = snappedf(y_power_bottom + GAP, GRID)
	var power_bottom: float = _place_power_rows(circuit, power_rows, zone_a, y_bus, placed, col_skip)
	var y_header: float = snappedf(zone_b.position.y + zone_b.size.y + GRID * 2.0, GRID) if zone_b.size != Vector2.ZERO else snappedf(y_bus, GRID)
	var y_ctrl: float = snappedf(y_header + GRID * 16.0, GRID)
	var coil_cx: float = snappedf(origin.x + GRID * 28.0, GRID)
	if zone_b.size != Vector2.ZERO:
		coil_cx = snappedf(zone_b.position.x + zone_b.size.x + GAP + GRID * 4.0, GRID)
	var rung_meta: Dictionary = _place_rungs(circuit, rungs, coil_cx, y_ctrl, placed, orig_y)
	_place_terminals(circuit, terms, rung_meta, placed)
	_align_plus_to_rungs(circuit, terms, rung_meta, placed)
	_align_psu_to_return(circuit, rung_meta, placed)
	_place_device_table(circuit, claimed, placed, rung_meta)
	_layout_attached(circuit)
	_place_wired_orphans(circuit, placed)
	_place_leftovers(circuit, placed, rung_meta)
	_clear_label_offsets(circuit)
	var ctx: Dictionary = _corridors(circuit, breakers, terms, rung_meta)
	_route_all(circuit, ctx)
	var broken_n: int = _break_busy(circuit, ctx)
	_recenter(circuit, old_center)
	WireRouter2D.invalidate()
	if circuit.has_method("touch_scene"):
		circuit.touch_scene()
	var moved: int = 0
	for el2 in circuit.elements:
		var pid: int = int(el2.id)
		if not orig.has(pid):
			moved += 1
			continue
		var was: Vector2 = orig[pid] as Vector2
		if was.distance_squared_to(el2.position) > 0.25:
			moved += 1
	return {
		"ok": true,
		"moved": moved,
		"rails": int(ctx.get("rail_n", 0)),
		"broken": broken_n,
		"rungs": rungs.size(),
		"hits": _body_hits(circuit),
	}


# --- подготовка -----------------------------------------------------------

static func _drop_rails(circuit) -> void:
	var ids: Array = []
	for el in circuit.elements:
		if el != null and str(el.kind) == "rail":
			ids.append(int(el.id))
	for idv in ids:
		circuit._remove_element(int(idv), false)


static func _detach_wired_contacts(circuit) -> void:
	var n: int = 0
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) != "contact":
			continue
		if ElectroLib.is_button_fixed_contact(circuit, el):
			continue
		if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		if not ElectroLib.contact_has_any_wire(circuit, el):
			continue
		if not bool(el.detached):
			el.detached = true
			n += 1
	if n > 0 and circuit.has_method("renumber_tags"):
		circuit.renumber_tags()


static func _clear_electric_routes(circuit) -> void:
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		w.joints = []
		w.broken = false
		w.rail_skip_ids = []
		w.rail_merge = true


static func _clear_label_offsets(circuit) -> void:
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		el.tag_offset = Vector2.ZERO
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		w.num_offset = Vector2.ZERO
		w.num_offset_b = Vector2.ZERO


static func _bounds_of(circuit, orig: Dictionary) -> Rect2:
	var box := Rect2()
	var any: bool = false
	for el in circuit.elements:
		if el == null or str(el.kind) == "rail":
			continue
		orig[int(el.id)] = el.position
		var b: Rect2 = Geom.world_bounds(el)
		if not any:
			box = b
			any = true
		else:
			box = box.expand(b.position).expand(b.position + b.size)
	return box


# --- топология ------------------------------------------------------------

static func _build_rungs(circuit, orig_y: Dictionary) -> Array:
	var loads: Array = []
	for el in circuit.elements:
		if _is_load(el):
			loads.append(el)
	loads.sort_custom(func(a, b):
		return float(orig_y.get(int(a.id), 0.0)) < float(orig_y.get(int(b.id), 0.0))
	)
	var rungs: Array = []
	for load in loads:
		var chain: Array = _hot_chain(circuit, load)
		rungs.append({"load": int(load.id), "chain": chain})
	return rungs


static func _hot_chain(circuit, load) -> Array:
	var port: String = "A1" if str(load.electro_class) != "lamp" else "X1"
	if Geom.port_by_name(load, port).is_empty():
		return []
	var chain: Array = []
	var seen: Dictionary = {int(load.id): true}
	var cur = load
	var guard: int = 0
	while guard < 16:
		guard += 1
		var step: Dictionary = _pick_upstream(circuit, cur, port, seen)
		if step.is_empty():
			break
		var other = step["other"]
		var arrived: String = str(step["port"])
		if other == null or seen.has(int(other.id)) or _is_chain_stop(other):
			break
		seen[int(other.id)] = true
		var place = other
		if ElectroLib.is_button_fixed_contact(circuit, other):
			var parent = circuit.get_element(int(other.group_id))
			if parent != null:
				place = parent
				seen[int(parent.id)] = true
		chain.append(int(place.id))
		var nxt: PackedStringArray = _other_ports(circuit, other, arrived)
		if nxt.is_empty():
			break
		var next_port: String = str(nxt[0])
		if nxt.size() > 1:
			var best_d: int = 999
			var found: bool = false
			for pn in nxt:
				var alt: Dictionary = _pick_upstream(circuit, other, str(pn), seen)
				if alt.is_empty():
					continue
				var dalt: int = _dist_to_stop(circuit, alt["other"], seen)
				if dalt < best_d:
					best_d = dalt
					next_port = str(pn)
					found = true
			if not found:
				break
		cur = other
		port = next_port
	chain.reverse()
	return chain


## Из порта назад к источнику: не сворачивать в параллельный контакт, который упирается в уже пройденное.
static func _pick_upstream(circuit, cur, port: String, seen: Dictionary) -> Dictionary:
	var wires: Array = circuit.wires_on_port(int(cur.id), port)
	var best: Dictionary = {}
	var best_dist: int = 999
	for w in wires:
		var other = _peer_el(circuit, w, cur)
		if other == null or seen.has(int(other.id)):
			continue
		if _is_chain_stop(other):
			continue
		var dist: int = _dist_to_stop(circuit, other, seen)
		if dist < best_dist:
			best_dist = dist
			best = {"wire": w, "other": other, "port": _peer_port(w, cur)}
	return best


static func _dist_to_stop(circuit, start, blocked: Dictionary) -> int:
	var dist: Dictionary = {int(start.id): 0}
	var queue: Array = [int(start.id)]
	var qi: int = 0
	while qi < queue.size():
		var id: int = int(queue[qi])
		qi += 1
		var d0: int = int(dist[id])
		if d0 > 8:
			continue
		var el = circuit.get_element(id)
		if el == null:
			continue
		for w in circuit.wires:
			var nxt_id: int = -1
			if int(w.a_id) == id:
				nxt_id = int(w.b_id)
			elif int(w.b_id) == id:
				nxt_id = int(w.a_id)
			else:
				continue
			if blocked.has(nxt_id) or dist.has(nxt_id):
				continue
			var nxt = circuit.get_element(nxt_id)
			if nxt != null and _is_chain_stop(nxt):
				return d0 + 1
			dist[nxt_id] = d0 + 1
			queue.append(nxt_id)
	return 99


static func _claim_rungs(rungs: Array, claimed: Dictionary) -> void:
	for rung in rungs:
		var item: Dictionary = rung
		claimed[int(item["load"])] = true
		var chain: Array = item["chain"] as Array
		var keep: Array = []
		for idv in chain:
			var id: int = int(idv)
			if claimed.has(id):
				continue
			claimed[id] = true
			keep.append(id)
		item["chain"] = keep


static func _power_rows(circuit, claimed: Dictionary, orig_x: Dictionary) -> Array:
	var ids: Dictionary = {}
	var order: Array = []
	for el in circuit.elements:
		if not _is_power_gadget(circuit, el, claimed):
			continue
		ids[int(el.id)] = true
		order.append(el)
	order.sort_custom(func(a, b):
		return float(orig_x.get(int(a.id), 0.0)) < float(orig_x.get(int(b.id), 0.0))
	)
	var adj: Dictionary = {}
	for w in circuit.wires:
		var a: int = int(w.a_id)
		var b: int = int(w.b_id)
		if not ids.has(a) or not ids.has(b):
			continue
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var rows: Array = []
	var seen: Dictionary = {}
	for el in order:
		var start: int = int(el.id)
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		while not stack.is_empty():
			var id: int = int(stack.pop_back())
			if seen.has(id):
				continue
			seen[id] = true
			comp.append(id)
			for nb in adj.get(id, []) as Array:
				if not seen.has(int(nb)):
					stack.append(int(nb))
		comp.sort_custom(func(a, b):
			return float(orig_x.get(int(a), 0.0)) < float(orig_x.get(int(b), 0.0))
		)
		rows.append(comp)
	return rows


static func _classify_terminals(circuit, control: Dictionary) -> Dictionary:
	var hot: Dictionary = {}
	var ret: Dictionary = {}
	for w in circuit.wires:
		_count_term_end(circuit, w, int(w.a_id), str(w.a_port), int(w.b_id), str(w.b_port), control, hot, ret)
		_count_term_end(circuit, w, int(w.b_id), str(w.b_port), int(w.a_id), str(w.a_port), control, hot, ret)
	var plus_id: int = _argmax(hot)
	var ret_id: int = _argmax(ret)
	if plus_id == ret_id:
		if int(ret.get(ret_id, 0)) > int(hot.get(plus_id, 0)):
			plus_id = _argmax_except(hot, ret_id)
		else:
			ret_id = _argmax_except(ret, plus_id)
	if int(hot.get(plus_id, 0)) < 2:
		plus_id = -1
	if int(ret.get(ret_id, 0)) < 2:
		ret_id = -1
	return {"plus": plus_id, "ret": ret_id}


static func _count_term_end(circuit, _w, tid: int, _tp: String, oid: int, op: String, control: Dictionary, hot: Dictionary, ret: Dictionary) -> void:
	var term = circuit.get_element(tid)
	var other = circuit.get_element(oid)
	if term == null or other == null:
		return
	if str(term.electro_class) != "terminal":
		return
	if str(other.electro_class) == "terminal":
		return
	var role: String = _port_role(op)
	if role == "ret" or (control.has(oid) and role != "hot" and op in ["A2", "X2"]):
		ret[tid] = int(ret.get(tid, 0)) + 1
		return
	if role == "hot" or control.has(oid):
		hot[tid] = int(hot.get(tid, 0)) + 1


# --- расстановка ----------------------------------------------------------

## Ноги ввода на одной высоте с выводами автомата — прямая, без лишнего угла.
static func _align_supply_to_breakers(circuit, placed: Dictionary) -> void:
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var leg = null
		var brk = null
		var leg_port := ""
		var brk_port := ""
		var a_in: bool = str(a.electro_class) in ["supply", "supply_leg"]
		var b_in: bool = str(b.electro_class) in ["supply", "supply_leg"]
		if a_in and _is_breaker(b):
			leg = a
			brk = b
			leg_port = str(w.a_port)
			brk_port = str(w.b_port)
		elif b_in and _is_breaker(a):
			leg = b
			brk = a
			leg_port = str(w.b_port)
			brk_port = str(w.a_port)
		else:
			continue
		if not placed.has(int(leg.id)) or not placed.has(int(brk.id)):
			continue
		var tb: Dictionary = _tip(brk, brk_port)
		var tl: Dictionary = _tip(leg, leg_port)
		if tb.is_empty() or tl.is_empty():
			continue
		var want: Vector2 = tb["tip"] as Vector2
		var have: Vector2 = tl["tip"] as Vector2
		var dy: float = want.y - have.y
		if absf(dy) < 0.5:
			continue
		# Y tips точно совпадают (snap только по X), иначе остаётся лишний излом.
		var np: Vector2 = leg.position + Vector2(0.0, dy)
		np.x = snappedf(np.x, GRID)
		_move(circuit, leg, np)


static func _bounds_placed(circuit, placed: Dictionary, fallback: Rect2) -> Rect2:
	var box := Rect2()
	var any: bool = false
	for idv in placed.keys():
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		var b: Rect2 = Geom.world_bounds(el)
		if not any:
			box = b
			any = true
		else:
			box = box.expand(b.position).expand(b.position + b.size)
	return box if any else fallback


## Плюс: сдвинуть клеммник так, чтобы tips совпали со строками; строки — к tips.
static func _align_plus_to_rungs(circuit, terms: Dictionary, meta: Dictionary, placed: Dictionary) -> void:
	var plus = circuit.get_element(int(terms.get("plus", -1)))
	if plus == null or not placed.has(int(plus.id)):
		return
	var pairs: Array = []
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var other = null
		var pport := ""
		if int(a.id) == int(plus.id):
			other = b
			pport = str(w.a_port)
		elif int(b.id) == int(plus.id):
			other = a
			pport = str(w.b_port)
		else:
			continue
		if not (_is_load(other) or str(other.member_role) == "contact"):
			continue
		var tip_p: Dictionary = _tip(plus, pport)
		var tip_o: Dictionary = _tip(other, _row_port(circuit, other) if str(other.member_role) != "contact" else _first_port(other))
		if tip_p.is_empty():
			continue
		var oy: float = float(other.position.y)
		if not tip_o.is_empty():
			oy = float((tip_o["tip"] as Vector2).y)
		pairs.append({"port": pport, "y": oy, "id": int(other.id)})
	if pairs.is_empty():
		return
	var err: float = 0.0
	for item in pairs:
		var tip2: Dictionary = _tip(plus, str(item["port"]))
		if tip2.is_empty():
			continue
		err += float(item["y"]) - float((tip2["tip"] as Vector2).y)
	var dy: float = snappedf(err / float(pairs.size()), GRID)
	if absf(dy) > 0.5:
		_move(circuit, plus, (plus.position + Vector2(0.0, dy)).snapped(Vector2(GRID, GRID)))
	var ys: Dictionary = meta.get("ys", {}) as Dictionary
	for item2 in pairs:
		var tip3: Dictionary = _tip(plus, str(item2["port"]))
		if tip3.is_empty():
			continue
		var want_y: float = float((tip3["tip"] as Vector2).y)
		var el = circuit.get_element(int(item2["id"]))
		if el == null:
			continue
		var tip_e: Dictionary = _tip(el, _row_port(circuit, el))
		var have_y: float = float(el.position.y)
		if not tip_e.is_empty():
			have_y = float((tip_e["tip"] as Vector2).y)
		var ddy: float = want_y - have_y
		if absf(ddy) < 0.5:
			ys[int(el.id)] = want_y
			continue
		var old_tip_y: float = have_y
		_move(circuit, el, (el.position + Vector2(0.0, ddy)).snapped(Vector2(GRID, GRID)))
		ys[int(el.id)] = want_y
		for el2 in circuit.elements:
			if el2 == null or not placed.has(int(el2.id)):
				continue
			if int(el2.id) == int(el.id):
				continue
			if str(el2.member_role) != "contact" and str(el2.electro_class) not in ["button", "e_stop"]:
				continue
			var tip2: Dictionary = _tip(el2, _row_port(circuit, el2))
			var y2: float = float(el2.position.y)
			if not tip2.is_empty():
				y2 = float((tip2["tip"] as Vector2).y)
			if absf(y2 - old_tip_y) > GRID * 3.0:
				continue
			if absf(float(el2.position.x) - float(el.position.x)) > GRID * 40.0:
				continue
			_move(circuit, el2, (el2.position + Vector2(0.0, ddy)).snapped(Vector2(GRID, GRID)))
	meta["ys"] = ys


## БП ниже таблицы: N на высоте клеммы возврата, жила 21 — Г под схемой.
static func _align_psu_to_return(circuit, meta: Dictionary, placed: Dictionary) -> void:
	var block: Rect2 = meta.get("block", Rect2()) as Rect2
	var floor_y: float = block.position.y + block.size.y + GAP * 2.0 if block.size != Vector2.ZERO else 0.0
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var psu = null
		var term = null
		var psu_port := ""
		var term_port := ""
		if str(a.electro_class) == "psu" and str(b.electro_class) == "terminal":
			psu = a
			term = b
			psu_port = str(w.a_port)
			term_port = str(w.b_port)
		elif str(b.electro_class) == "psu" and str(a.electro_class) == "terminal":
			psu = b
			term = a
			psu_port = str(w.b_port)
			term_port = str(w.a_port)
		else:
			continue
		if psu_port.to_upper() != "N":
			continue
		if not placed.has(int(psu.id)) or not placed.has(int(term.id)):
			continue
		var tp: Dictionary = _tip(term, term_port)
		var pp: Dictionary = _tip(psu, psu_port)
		if tp.is_empty() or pp.is_empty():
			continue
		var want_y: float = snappedf(maxf(float((tp["tip"] as Vector2).y), floor_y), GRID)
		var have_y: float = float((pp["tip"] as Vector2).y)
		var dy: float = want_y - have_y
		if absf(dy) < 0.5:
			break
		_move(circuit, psu, psu.position + Vector2(0.0, dy))
		break


static func _first_port(el) -> String:
	var ports: Array = Geom.ports(el)
	for p in ports:
		if typeof(p) == TYPE_DICTIONARY:
			return str(p.get("name", "1"))
	return "1"


static func _place_zone_a(circuit, origin: Vector2, placed: Dictionary) -> Rect2:
	var items: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		var cls: String = str(el.electro_class)
		if cls == "supply" or cls == "psu":
			items.append(el)
		elif cls == "supply_leg" and not _feeds_terminal(circuit, el):
			items.append(el)
	items.sort_custom(func(a, b):
		return _zone_a_rank(a) < _zone_a_rank(b)
	)
	var y: float = origin.y
	var left: float = origin.x
	var box := Rect2(origin, Vector2.ZERO)
	var any: bool = false
	for el in items:
		_set_rot(el, 0)
		var b: Rect2 = _place_top_left(circuit, el, left, y)
		placed[int(el.id)] = true
		y = snappedf(b.position.y + b.size.y + GAP, GRID)
		if not any:
			box = b
			any = true
		else:
			box = box.expand(b.position).expand(b.position + b.size)
	return box


static func _feeds_terminal(circuit, el) -> bool:
	var to_term: bool = false
	for w in circuit.wires:
		var other = null
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
		else:
			continue
		if other == null:
			continue
		if str(other.electro_class) == "terminal":
			to_term = true
		elif not _is_power_end(other):
			return false
	return to_term


static func _split_breakers(circuit, orig_x: Dictionary, orig_y: Dictionary) -> Dictionary:
	var all: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		var cls: String = str(el.electro_class)
		if cls in ["mcb", "rcd", "rcbo"]:
			all.append(el)
	var peer: Dictionary = {}
	for w in circuit.wires:
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		if not _is_breaker(a) or not _is_breaker(b):
			continue
		if str(w.a_port) == "1" and str(w.b_port) == "1":
			peer[int(a.id)] = true
			peer[int(b.id)] = true
	var peers: Array = []
	var infeed: Array = []
	for el in all:
		if peer.has(int(el.id)):
			peers.append(el)
		else:
			infeed.append(el)
	peers.sort_custom(func(a, b):
		return float(orig_x.get(int(a.id), 0.0)) < float(orig_x.get(int(b.id), 0.0))
	)
	infeed.sort_custom(func(a, b):
		return float(orig_y.get(int(a.id), 0.0)) < float(orig_y.get(int(b.id), 0.0))
	)
	return {"peer": peer, "peers": peers, "infeed": infeed}


static func _rung_depth_map(circuit, rungs: Array, orig_y: Dictionary) -> Dictionary:
	var depth_of: Dictionary = {}
	for rung in rungs:
		var item: Dictionary = rung
		var lid: int = int(item["load"])
		var y: float = float(orig_y.get(lid, 0.0))
		depth_of[lid] = y
		for idv in item["chain"] as Array:
			var id: int = int(idv)
			depth_of[id] = y
			var el = circuit.get_element(id)
			if el == null or str(el.electro_class) not in ["button", "e_stop"]:
				continue
			if not circuit.has_method("electro_group_members"):
				continue
			for m in circuit.electro_group_members(id):
				if m != null:
					depth_of[int(m.id)] = y
	return depth_of


static func _place_breakers(circuit, zone_a: Rect2, top: float, breakers: Dictionary, placed: Dictionary) -> Rect2:
	var x: float = snappedf(zone_a.position.x + zone_a.size.x + GAP * 2.0, GRID)
	if zone_a.size == Vector2.ZERO:
		x = GRID * 4.0
	var y: float = top
	var box := Rect2(Vector2(x, y), Vector2.ZERO)
	var any: bool = false
	for el in breakers.get("infeed", []) as Array:
		_set_rot(el, 0)
		var b: Rect2 = _place_top_left(circuit, el, x, y)
		placed[int(el.id)] = true
		y = snappedf(b.position.y + b.size.y + GAP, GRID)
		box = b if not any else box.expand(b.position).expand(b.position + b.size)
		any = true
	# Ряд автоматов — под вводом, слева направо как на эталоне. Столбец катушек сядет у правого края ряда.
	var row_x: float = x
	# Зазор над рядом — чтобы шина ввода шла над выводами, а не сквозь вводной автомат.
	var row_top: float = snappedf((box.position.y + box.size.y + GRID * 8.0) if any else top, GRID)
	for el2 in breakers.get("peers", []) as Array:
		_set_rot(el2, 0)
		var b2: Rect2 = _place_top_left(circuit, el2, row_x, row_top)
		placed[int(el2.id)] = true
		row_x = snappedf(b2.position.x + b2.size.x + GRID * 2.0, GRID)
		box = b2 if not any else box.expand(b2.position).expand(b2.position + b2.size)
		any = true
	return box


## Нижняя цель автомата. Глубже — левее, чтобы короткий спуск справа не пересёк длинный слева.
static func _feed_depth(circuit, el, depth_of: Dictionary) -> float:
	var best: float = -1.0e8
	var found: bool = false
	for w in circuit.wires:
		var other = null
		var port: String = ""
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
			port = str(w.a_port)
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
			port = str(w.b_port)
		else:
			continue
		if other == null or port == "1" or _is_breaker(other):
			continue
		var d: float = float(depth_of.get(int(other.id), other.position.y))
		if not depth_of.has(int(other.id)):
			d = 1.0e6
		if not found or d > best:
			best = d
			found = true
	if not found:
		return 1.0e6
	return best


static func _place_power_rows(circuit, rows: Array, zone_b: Rect2, y_bus: float, placed: Dictionary, skip: Dictionary) -> float:
	var y: float = snappedf(y_bus + GAP, GRID)
	var left: float = zone_b.position.x if zone_b.size != Vector2.ZERO else GRID * 8.0
	for row in rows:
		var x: float = left
		var row_bottom: float = y
		for idv in row as Array:
			var el = circuit.get_element(int(idv))
			if el == null or skip.has(int(idv)) or placed.has(int(idv)):
				continue
			var rot: int = 3 if str(el.electro_class) == "thermal" and str(el.member_role) != "contact" else 0
			_set_rot(el, rot)
			var b: Rect2 = _place_top_left(circuit, el, x, y)
			placed[int(el.id)] = true
			x = snappedf(b.position.x + b.size.x + GAP, GRID)
			row_bottom = maxf(row_bottom, b.position.y + b.size.y)
		y = snappedf(row_bottom + GAP, GRID)
	return y


static func _column_id_set(circuit, rungs: Array) -> Dictionary:
	var skip: Dictionary = {}
	for idv in _column_list(circuit, rungs):
		skip[int(idv)] = true
	return skip


## Катушки, лампы и силовые контакты — один столбец, сверху вниз по исходной высоте.
static func _column_list(circuit, rungs: Array) -> Array:
	var in_chain: Dictionary = {}
	var ids: Array = []
	var seen: Dictionary = {}
	for rung in rungs:
		var item: Dictionary = rung
		var lid: int = int(item["load"])
		if not seen.has(lid):
			seen[lid] = true
			ids.append(lid)
		for idv in item["chain"] as Array:
			in_chain[int(idv)] = true
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		var id: int = int(el.id)
		if seen.has(id) or in_chain.has(id):
			continue
		var take: bool = false
		if str(el.electro_class) == "thermal" and str(el.member_role) != "contact":
			take = true
		elif _is_power_contact(circuit, el):
			take = true
		if not take:
			continue
		seen[id] = true
		ids.append(id)
	ids.sort_custom(func(a, b):
		var ea = circuit.get_element(int(a))
		var eb = circuit.get_element(int(b))
		var ya: float = float(ea.position.y) if ea != null else 0.0
		var yb: float = float(eb.position.y) if eb != null else 0.0
		return ya < yb
	)
	return ids


## Пара «контакт — тепловое» на одной горизонтали. Возвращает вторую деталь.
static func _series_thermal(circuit, el):
	if el == null:
		return null
	for w in circuit.wires:
		var other = null
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
		else:
			continue
		if other == null:
			continue
		var el_th: bool = str(el.electro_class) == "thermal" and str(el.member_role) != "contact"
		var o_th: bool = str(other.electro_class) == "thermal" and str(other.member_role) != "contact"
		var el_c: bool = str(el.member_role) == "contact"
		var o_c: bool = str(other.member_role) == "contact"
		if (el_c and o_th) or (el_th and o_c):
			return other
	return null


static func _series_port_to(circuit, el, other) -> String:
	for w in circuit.wires:
		if int(w.a_id) == int(el.id) and int(w.b_id) == int(other.id):
			return str(w.a_port)
		if int(w.b_id) == int(el.id) and int(w.a_id) == int(other.id):
			return str(w.b_port)
	return _row_port(circuit, el)


static func _place_port_at(circuit, el, port: String, left: float, tip_y: float) -> Rect2:
	var tip: Dictionary = _tip(el, port)
	var b: Rect2 = Geom.world_bounds(el)
	var want_y: float = float(el.position.y)
	if not tip.is_empty():
		want_y = tip_y - float((tip["tip"] as Vector2).y) + float(el.position.y)
	var delta := Vector2(left - b.position.x, want_y - float(el.position.y))
	_move(circuit, el, (el.position + delta).snapped(Vector2(GRID, GRID)))
	return Geom.world_bounds(el)


static func _is_power_contact(circuit, el) -> bool:
	if el == null or str(el.member_role) != "contact":
		return false
	if ElectroLib.is_button_fixed_contact(circuit, el):
		return false
	if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
		return false
	if not ElectroLib.contact_has_any_wire(circuit, el):
		return false
	for w in circuit.wires:
		var other = null
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
		else:
			continue
		if other != null and (_is_breaker(other) or (_is_power_end(other) and str(other.electro_class) != "terminal")):
			return true
	return false


static func _place_rungs(circuit, rungs: Array, coil_cx: float, y_ctrl: float, placed: Dictionary, _orig_y: Dictionary) -> Dictionary:
	var y: float = y_ctrl
	var ys: Dictionary = {}
	var block := Rect2()
	var any: bool = false
	var column_right: float = coil_cx
	var skip_col: Dictionary = {}
	for idv in _column_list(circuit, rungs):
		var el = circuit.get_element(int(idv))
		if el == null or placed.has(int(idv)) or skip_col.has(int(idv)):
			continue
		# Контакт слева, тепловое справа на одной высоте tips.
		var mate = _series_thermal(circuit, el)
		var left_el = el
		var right_el = null
		if mate != null and not placed.has(int(mate.id)):
			var el_th: bool = str(el.electro_class) == "thermal" and str(el.member_role) != "contact"
			if el_th:
				left_el = mate
				right_el = el
			else:
				right_el = mate
		var rot_l: int = 0
		_set_rot(left_el, rot_l)
		var half: float = Geom.world_bounds(left_el).size.x * 0.5
		var left: float = snappedf(coil_cx - half, GRID)
		var b: Rect2 = _place_top_left(circuit, left_el, left, y)
		placed[int(left_el.id)] = true
		skip_col[int(left_el.id)] = true
		column_right = maxf(column_right, b.position.x + b.size.x)
		var port: String = _row_port(circuit, left_el)
		if right_el != null:
			port = _series_port_to(circuit, left_el, right_el)
		var tip: Dictionary = _tip(left_el, port)
		var py: float = b.get_center().y
		if not tip.is_empty():
			py = float((tip["tip"] as Vector2).y)
		ys[int(left_el.id)] = py
		var row_bottom: float = b.position.y + b.size.y
		if right_el != null:
			_set_rot(right_el, 3)
			var rport: String = _series_port_to(circuit, right_el, left_el)
			var rleft: float = snappedf(b.position.x + b.size.x + GRID * 2.0, GRID)
			var bm: Rect2 = _place_port_at(circuit, right_el, rport, rleft, py)
			placed[int(right_el.id)] = true
			skip_col[int(right_el.id)] = true
			column_right = maxf(column_right, bm.position.x + bm.size.x)
			ys[int(right_el.id)] = py
			row_bottom = maxf(row_bottom, bm.position.y + bm.size.y)
			if not any:
				block = b.expand(bm.position).expand(bm.position + bm.size)
				any = true
			else:
				block = block.expand(b.position).expand(b.position + b.size)
				block = block.expand(bm.position).expand(bm.position + bm.size)
		else:
			if not any:
				block = b
				any = true
			else:
				block = block.expand(b.position).expand(b.position + b.size)
		y = snappedf(row_bottom + GAP + GRID * 4.0, GRID)
	for rung in rungs:
		var item: Dictionary = rung
		var load = circuit.get_element(int(item["load"]))
		if load == null:
			continue
		var rung_y: float = float(ys.get(int(load.id), load.position.y))
		var chain: Array = item["chain"] as Array
		var total: float = 0.0
		var widths: Array = []
		for idv2 in chain:
			var el2 = circuit.get_element(int(idv2))
			if el2 == null or placed.has(int(idv2)):
				widths.append(-1.0)
				continue
			_set_rot(el2, 0)
			var ww: float = Geom.world_bounds(el2).size.x
			widths.append(ww)
			total += ww + GAP
		if total > GAP:
			total -= GAP
		var load_left: float = Geom.world_bounds(load).position.x
		var x: float = snappedf(load_left - GAP - STUB - total, GRID)
		var i: int = 0
		for idv3 in chain:
			var ww2: float = float(widths[i])
			i += 1
			if ww2 < 0.0:
				continue
			var el3 = circuit.get_element(int(idv3))
			if el3 == null:
				continue
			var b3: Rect2 = _place_on_row(circuit, el3, x, rung_y)
			placed[int(el3.id)] = true
			x = snappedf(b3.position.x + b3.size.x + GAP, GRID)
			if not any:
				block = b3
				any = true
			else:
				block = block.expand(b3.position).expand(b3.position + b3.size)
		ys[int(load.id)] = rung_y
	return {
		"y0": y_ctrl,
		"y1": y,
		"coil_cx": coil_cx,
		"x_ctrl": coil_cx,
		"x_rail": snappedf(column_right + GAP * 3.0, GRID),
		"y_header": y_ctrl - GRID * 15.0,
		"block": block,
		"ys": ys,
		"lanes": {},
		"any": any,
	}


static func _place_terminals(circuit, terms: Dictionary, meta: Dictionary, placed: Dictionary) -> void:
	var block: Rect2 = meta.get("block", Rect2()) as Rect2
	var y0: float = float(meta.get("y0", 0.0))
	if not bool(meta.get("any", false)):
		y0 = float(meta.get("y0", 0.0))
		block = Rect2(Vector2(float(meta.get("x_ctrl", 0.0)), y0), Vector2(GRID * 20.0, GRID * 10.0))
	var plus = circuit.get_element(int(terms.get("plus", -1)))
	var ret = circuit.get_element(int(terms.get("ret", -1)))
	var plus_right: float = block.position.x
	if plus != null:
		_set_rot(plus, 1)
		var bw: float = Geom.world_bounds(plus).size.x
		# Зазор слева от ключей: вертикали плюса не режут контакты.
		var left: float = snappedf(block.position.x - GAP * 4.0 - STUB - bw, GRID)
		var b: Rect2 = _place_top_left(circuit, plus, left, block.position.y)
		placed[int(plus.id)] = true
		plus_right = b.position.x + b.size.x
		block = block.expand(b.position).expand(b.position + b.size)
	var ret_left: float = 1.0e9
	var x: float = snappedf(block.position.x + block.size.x + GAP * 6.0, GRID)
	var y: float = block.position.y
	var fields: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.electro_class) != "terminal":
			continue
		if placed.has(int(el.id)):
			continue
		fields.append(el)
	if ret != null and not placed.has(int(ret.id)):
		fields.append(ret)
	fields.sort_custom(func(a, b):
		return float(a.position.y) < float(b.position.y)
	)
	for el in fields:
		_set_rot(el, 3)
	for el2 in circuit.elements:
		if el2 == null or str(el2.kind) != "electro" or placed.has(int(el2.id)):
			continue
		if str(el2.electro_class) == "supply_leg" and _feeds_terminal(circuit, el2):
			fields.append(el2)
	var field_right: float = x
	for el in fields:
		var bf: Rect2 = _place_top_left(circuit, el, x, y)
		placed[int(el.id)] = true
		y = snappedf(bf.position.y + bf.size.y + GAP, GRID)
		block = block.expand(bf.position).expand(bf.position + bf.size)
		ret_left = minf(ret_left, bf.position.x)
		field_right = maxf(field_right, bf.position.x + bf.size.x)
	if fields.size() > 0:
		meta["x_rail"] = snappedf(ret_left - GAP * 2.0, GRID)
		# Порты rot=3 смотрят влево — обход слева от столбца, не сквозь корпуса.
		meta["x_field"] = snappedf(ret_left - GAP * 3.0, GRID)
	meta["block"] = block
	meta["plus_right"] = plus_right
	meta["ret_left"] = ret_left


static func _place_wired_orphans(circuit, placed: Dictionary) -> void:
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) != "contact" or not bool(el.detached):
			continue
		if placed.has(int(el.id)):
			continue
		if not ElectroLib.contact_has_any_wire(circuit, el):
			continue
		var host = null
		for w in circuit.wires:
			var other = null
			if int(w.a_id) == int(el.id):
				other = circuit.get_element(int(w.b_id))
			elif int(w.b_id) == int(el.id):
				other = circuit.get_element(int(w.a_id))
			else:
				continue
			if other == null or str(other.member_role) != "contact":
				continue
			var ready: bool = placed.has(int(other.id))
			if not ready and int(other.group_id) > 0:
				ready = placed.has(int(other.group_id))
			if not ready:
				continue
			host = other
			if ElectroLib.is_button_fixed_contact(circuit, other):
				break
		if host == null:
			continue
		_set_rot(el, 0)
		var hb: Rect2 = Geom.world_bounds(host)
		var below: float = snappedf(hb.position.y + hb.size.y + GRID, GRID)
		_place_top_left(circuit, el, hb.position.x, below)
		placed[int(el.id)] = true


static func _place_device_table(circuit, claimed: Dictionary, placed: Dictionary, meta: Dictionary) -> void:
	var block: Rect2 = meta.get("block", Rect2()) as Rect2
	var items: Array = []
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) != "contact":
			continue
		if not bool(el.detached):
			continue
		if claimed.has(int(el.id)) or placed.has(int(el.id)):
			continue
		if ElectroLib.contact_has_any_wire(circuit, el):
			continue
		items.append(el)
	items.sort_custom(func(a, b):
		var ga: String = str(a.group_tag)
		var gb: String = str(b.group_tag)
		if ga != gb:
			return ga < gb
		return int(a.member_index) < int(b.member_index)
	)
	var x: float = snappedf(block.position.x + block.size.x + GAP * 2.0, GRID)
	var y: float = block.position.y
	for el2 in items:
		_set_rot(el2, 0)
		var b: Rect2 = _place_top_left(circuit, el2, x, y)
		placed[int(el2.id)] = true
		y = snappedf(b.position.y + b.size.y + GRID, GRID)
		block = block.expand(b.position).expand(b.position + b.size)
	meta["block"] = block


static func _place_leftovers(circuit, placed: Dictionary, meta: Dictionary) -> void:
	var block: Rect2 = meta.get("block", Rect2()) as Rect2
	var y: float = snappedf(block.position.y + block.size.y + GAP * 2.0, GRID)
	var x: float = block.position.x
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if placed.has(int(el.id)):
			continue
		if str(el.member_role) == "contact" and not bool(el.detached):
			continue
		if ElectroLib.is_button_fixed_contact(circuit, el):
			continue
		if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		if str(el.electro_class) == "din_stop":
			continue
		_set_rot(el, 0)
		var b: Rect2 = _place_top_left(circuit, el, x, y)
		placed[int(el.id)] = true
		x = snappedf(b.position.x + b.size.x + GAP, GRID)


static func _layout_attached(circuit) -> void:
	for el in circuit.elements:
		if el == null or str(el.kind) != "electro":
			continue
		if str(el.member_role) == "contact":
			continue
		var cls: String = str(el.electro_class)
		if cls in ["button", "e_stop"]:
			ElectroLib.layout_button_contacts(circuit, el)
		elif cls in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
			ElectroLib.layout_coil_contacts(circuit, el)


# --- коридоры и трассы ----------------------------------------------------

static func _corridors(circuit, breakers: Dictionary, terms: Dictionary, meta: Dictionary) -> Dictionary:
	var peer: Dictionary = breakers.get("peer", {}) as Dictionary
	var y_top: float = 0.0
	var have_top: bool = false
	var x0: float = 0.0
	var x1: float = 0.0
	for idv in peer.keys():
		var el = circuit.get_element(int(idv))
		if el == null:
			continue
		var tip: Dictionary = _tip(el, "1")
		if tip.is_empty():
			continue
		var ty: float = float((tip["tip"] as Vector2).y)
		var tx: float = float((tip["tip"] as Vector2).x)
		if not have_top:
			y_top = ty
			x0 = tx
			x1 = tx
			have_top = true
		else:
			y_top = minf(y_top, ty)
			x0 = minf(x0, tx)
			x1 = maxf(x1, tx)
	y_top = snappedf(y_top - GRID * 4.0, GRID)
	var rail_n: int = 0
	var rail_ys: Array = []
	if have_top and x1 - x0 > GRID * 2.0:
		_add_h_rail(circuit, snappedf(x0 - GRID, GRID), snappedf(x1 + GRID, GRID), y_top)
		rail_ys.append(y_top)
		rail_n += 1
	var block: Rect2 = meta.get("block", Rect2()) as Rect2
	var plus = circuit.get_element(int(terms.get("plus", -1)))
	var ret = circuit.get_element(int(terms.get("ret", -1)))
	var x_plus: float = 0.0
	var x_ret: float = 0.0
	var have_plus: bool = false
	var have_ret: bool = false
	var y_rail0: float = block.position.y - GRID * 2.0
	var y_rail1: float = block.position.y + block.size.y + GRID * 2.0
	# Плюс — прямые строки к клеммнику, без вертикального рельса (как в эталоне).
	if plus != null:
		var pb: Rect2 = Geom.world_bounds(plus)
		x_plus = snappedf(pb.position.x + pb.size.x + GAP, GRID)
	var x_rail: float = float(meta.get("x_rail", 0.0))
	var have_rail: bool = meta.has("x_rail")
	if have_rail or ret != null:
		if have_rail:
			x_ret = x_rail
		elif ret != null:
			var rb: Rect2 = Geom.world_bounds(ret)
			x_ret = snappedf(rb.position.x - GAP, GRID)
		_add_v_rail(circuit, x_ret, snappedf(y_rail0, GRID), snappedf(y_rail1, GRID))
		rail_n += 1
		have_ret = true
	var rung_of: Dictionary = {}
	var ys: Dictionary = meta.get("ys", {}) as Dictionary
	for lid in ys.keys():
		rung_of[int(lid)] = int(lid)
	return {
		"peer": peer,
		"y_top": y_top,
		"have_top": have_top,
		"x_plus": x_plus,
		"x_ret": x_ret,
		"have_plus": have_plus,
		"have_ret": have_ret,
		"plus": int(terms.get("plus", -1)),
		"ret": int(terms.get("ret", -1)),
		"ys": ys,
		"rail_ys": rail_ys,
		"rail_xs": _rail_xs(x_plus, have_plus, x_ret, have_ret),
		"rail_n": rail_n,
		"ctrl": block,
		"y_chan": _header_channel(circuit),
		"rung_x0": float(meta.get("x_ctrl", 0.0)),
		"rung_x1": float(meta.get("coil_cx", 0.0)) + GRID * 4.0,
		"rung_ys_list": _ys_list(ys),
		"lanes": meta.get("lanes", {}) as Dictionary,
		"y_header": float(meta.get("y_header", 0.0)),
		"x_field": float(meta.get("x_field", 0.0)),
		"have_field": meta.has("x_field"),
	}


static func _rail_xs(x_plus: float, have_plus: bool, x_ret: float, have_ret: bool) -> Array:
	var xs: Array = []
	if have_plus:
		xs.append(x_plus)
	if have_ret:
		xs.append(x_ret)
	return xs


static func _route_all(circuit, ctx: Dictionary) -> void:
	var rung_of: Dictionary = _rung_index(circuit, ctx)
	ctx["rung_of"] = rung_of
	ctx["taken_h"] = []
	ctx["taken_v"] = []
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var path: Array = _route_wire(circuit, w, a, b, ctx)
		var lock: bool = _lock_route(a, b, path)
		if not lock:
			path = _keep_clear(circuit, w, a, b, path, ctx)
		else:
			w.broken = false
		if path.size() >= 2 and not bool(w.broken):
			w.joints = _joints_of(path)
			_claim_path(Geom.polyline(a, str(w.a_port), b, str(w.b_port), w.joints), ctx)


static func _ys_list(ys: Dictionary) -> Array:
	var out: Array = []
	for k in ys.keys():
		out.append(float(ys[k]))
	return out


static func _route_wire(circuit, w, a, b, ctx: Dictionary) -> Array:
	var ta: Dictionary = _tip(a, str(w.a_port))
	var tb: Dictionary = _tip(b, str(w.b_port))
	if ta.is_empty() or tb.is_empty():
		return []
	var pa: Vector2 = ta["tip"] as Vector2
	var pb: Vector2 = tb["tip"] as Vector2
	var na: Vector2 = ta["n"] as Vector2
	var nb: Vector2 = tb["n"] as Vector2
	var peer: Dictionary = ctx.get("peer", {}) as Dictionary
	# Ввод автоматов — одна горизонталь, как шина на эталоне.
	if bool(ctx.get("have_top", false)) and _on_peer_line(a, str(w.a_port), b, str(w.b_port), peer):
		return _on_y(pa, pb, float(ctx["y_top"]))
	# Ввод (XS) → автомат: после выравнивания tips — прямая.
	if (str(a.electro_class) in ["supply", "supply_leg"] and _is_breaker(b)) \
			or (str(b.electro_class) in ["supply", "supply_leg"] and _is_breaker(a)):
		return _route_rung(pa, pb)
	var plus_id: int = int(ctx.get("plus", -1))
	var ret_id: int = int(ctx.get("ret", -1))
	var x_ret: float = float(ctx.get("x_ret", 0.0))
	var ctrl: Rect2 = ctx.get("ctrl", Rect2()) as Rect2
	# БП ← клемма: раньше возврата — иначе N уходит на рельс A2 и сечёт XT1.
	if (str(a.electro_class) == "psu" and str(b.electro_class) == "terminal") \
			or (str(b.electro_class) == "psu" and str(a.electro_class) == "terminal"):
		var y_h: float = maxf(pa.y, pb.y)
		var blk: Rect2 = ctx.get("ctrl", Rect2()) as Rect2
		if blk.size != Vector2.ZERO:
			y_h = maxf(y_h, blk.position.y + blk.size.y + GAP)
		var plus_el = circuit.get_element(plus_id)
		if plus_el != null:
			var pbnd: Rect2 = Geom.world_bounds(plus_el)
			y_h = maxf(y_h, pbnd.position.y + pbnd.size.y + GAP)
		y_h = snappedf(y_h, GRID)
		return _via_axis(pa, na, pb, nb, y_h, true)
	# A2/X2 — на вертикальный рельс справа от катушек, даже если второй конец не «главный» возврат.
	if bool(ctx.get("have_ret", false)) and (_is_coil_return(str(w.a_port)) or _is_coil_return(str(w.b_port))):
		return _on_x(pa, pb, x_ret)
	if bool(ctx.get("have_ret", false)) and (int(a.id) == ret_id or int(b.id) == ret_id):
		var other_ret = b if int(a.id) == ret_id else a
		if str(other_ret.electro_class) != "psu" and _in_ladder(other_ret, ctrl):
			return _on_x(pa, pb, x_ret)
	# Два полевых клеммника — обход слева от столбца, не сквозь корпуса.
	if bool(ctx.get("have_field", false)) and str(a.electro_class) == "terminal" and str(b.electro_class) == "terminal":
		if int(a.id) != plus_id and int(b.id) != plus_id:
			return _on_x(pa, pb, float(ctx["x_field"]))
	# Полевой клеммник к столбцу — по рельсу возврата, не сквозь катушки.
	var ys_col: Dictionary = ctx.get("ys", {}) as Dictionary
	if bool(ctx.get("have_ret", false)) and (str(a.electro_class) == "terminal" or str(b.electro_class) == "terminal"):
		var term_el = a if str(a.electro_class) == "terminal" else b
		if int(term_el.id) != plus_id:
			var other_c = b if term_el == a else a
			if ys_col.has(int(other_c.id)) or str(other_c.member_role) == "contact":
				return _on_x(pa, pb, x_ret)
	# Плюс к строке: из вывода наружу, не вдоль клеммника.
	if int(a.id) == plus_id or int(b.id) == plus_id:
		var other_p = b if int(a.id) == plus_id else a
		if _on_control(ctx, other_p) or _is_load(other_p):
			var lane: int = int(ctx.get("plus_i", 0))
			ctx["plus_i"] = lane + 1
			if int(a.id) == plus_id:
				return _plus_feed(pa, na, pb, nb, lane)
			return _plus_feed(pb, nb, pa, na, lane)
	var rung_of: Dictionary = ctx.get("rung_of", {}) as Dictionary
	if rung_of.has(int(a.id)) and int(rung_of.get(int(a.id), -1)) == int(rung_of.get(int(b.id), -2)):
		return _route_rung(pa, pb)
	if _both_power_band(a, b):
		return _norm_link(pa, na, pb, nb)
	if str(a.member_role) == "contact" and str(b.member_role) == "contact":
		return _norm_link(pa, na, pb, nb, GRID * 2.0)
	# С автомата вниз — своя горизонталь в зазоре над таблицей, затем столб у цели.
	# Общий y сложил бы жилы, столб сквозь таблицу режет все строки.
	if _is_breaker(a) or _is_breaker(b) or (_is_power_end(a) and not _is_power_end(b)) or (_is_power_end(b) and not _is_power_end(a)):
		var src_y: float = pa.y
		var dst_y: float = pb.y
		if absf(nb.y) > absf(na.y):
			src_y = pb.y
			dst_y = pa.y
		if dst_y > src_y + GRID:
			var lane: int = int(ctx.get("drop_i", 0))
			ctx["drop_i"] = lane + 1
			var y_h: float = snappedf(float(ctx.get("y_header", src_y)) + float(lane) * GRID, GRID)
			return _street_drop(pa, na, pb, nb, y_h)
		return _norm_link(pa, na, pb, nb)
	return _norm_link(pa, na, pb, nb)


static func _header_channel(circuit) -> float:
	var y: float = -1.0e9
	var any: bool = false
	for el in circuit.elements:
		if not _is_power_end(el):
			continue
		var b: Rect2 = Geom.world_bounds(el)
		y = maxf(y, b.position.y + b.size.y)
		any = true
	if not any:
		return 0.0
	return snappedf(y + GAP, GRID)


static func _on_peer_line(a, ap: String, b, bp: String, peer: Dictionary) -> bool:
	var a_line: bool = peer.has(int(a.id)) and ap == "1"
	var b_line: bool = peer.has(int(b.id)) and bp == "1"
	return a_line or b_line


## Короткая прямая/Г после выравнивания УГО — не заменять поиском обхода.
static func _lock_route(a, b, path: Array) -> bool:
	if path.size() < 2:
		return false
	if (str(a.electro_class) in ["supply", "supply_leg"] and _is_breaker(b)) \
			or (str(b.electro_class) in ["supply", "supply_leg"] and _is_breaker(a)):
		return true
	if str(a.member_role) == "contact" and str(b.electro_class) == "thermal":
		return true
	if str(b.member_role) == "contact" and str(a.electro_class) == "thermal":
		return true
	if str(a.electro_class) == "terminal" and str(b.electro_class) == "terminal":
		return true
	if (str(a.electro_class) == "psu" and str(b.electro_class) == "terminal") \
			or (str(b.electro_class) == "psu" and str(a.electro_class) == "terminal"):
		return true
	return false


## Шину ввода, возврат катушек и строку таблицы не рвём: это групповые линии.
static func _spare_wire(w, a, b, ctx: Dictionary) -> bool:
	if a == null or b == null:
		return false
	var peer: Dictionary = ctx.get("peer", {}) as Dictionary
	if _on_peer_line(a, str(w.a_port), b, str(w.b_port), peer):
		return true
	if _is_coil_return(str(w.a_port)) or _is_coil_return(str(w.b_port)):
		return true
	var rung_of: Dictionary = ctx.get("rung_of", {}) as Dictionary
	if rung_of.has(int(a.id)) and int(rung_of.get(int(a.id), -1)) == int(rung_of.get(int(b.id), -2)):
		return true
	var ctrl: Rect2 = ctx.get("ctrl", Rect2()) as Rect2
	if _both_above(a, b, ctrl):
		return true
	var plus_id: int = int(ctx.get("plus", -1))
	if int(a.id) == plus_id or int(b.id) == plus_id:
		return true
	if str(a.member_role) == "contact" and str(b.member_role) == "contact":
		return true
	if (str(a.electro_class) == "psu" and str(b.electro_class) == "terminal") \
			or (str(b.electro_class) == "psu" and str(a.electro_class) == "terminal"):
		return true
	if str(a.electro_class) in ["supply", "supply_leg"] or str(b.electro_class) in ["supply", "supply_leg"]:
		return true
	return false


static func _break_busy(circuit, ctx: Dictionary) -> int:
	var paths: Dictionary = {}
	var order: Array = []
	var n_pre: int = 0
	for w in circuit.wires:
		if not _electric_wire(circuit, w):
			continue
		if bool(w.broken):
			n_pre += 1
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var pts: PackedVector2Array = Geom.polyline(a, str(w.a_port), b, str(w.b_port), w.joints)
		paths[int(w.id)] = pts
		order.append(w)
	var n: int = 0
	var xs: Array = ctx.get("rail_xs", []) as Array
	var ys: Array = ctx.get("rail_ys", []) as Array
	for w2 in order:
		var pts2: PackedVector2Array = paths[int(w2.id)] as PackedVector2Array
		var a2 = circuit.get_element(int(w2.a_id))
		var b2 = circuit.get_element(int(w2.b_id))
		if _spare_wire(w2, a2, b2, ctx):
			continue
		if _wire_hits_body(circuit, a2, b2, pts2):
			_mark_broken(w2, a2, str(w2.a_port), b2, str(w2.b_port))
			n += 1
			paths.erase(int(w2.id))
			continue
	var guard: int = 0
	while guard < 24:
		guard += 1
		var worst = null
		var worst_l: float = -1.0
		for w2 in order:
			if bool(w2.broken) or not paths.has(int(w2.id)):
				continue
			var pts2: PackedVector2Array = paths[int(w2.id)] as PackedVector2Array
			var a2 = circuit.get_element(int(w2.a_id))
			var b2 = circuit.get_element(int(w2.b_id))
			if _spare_wire(w2, a2, b2, ctx):
				continue
			var crosses: int = 0
			for w3 in order:
				if int(w3.id) == int(w2.id) or bool(w3.broken) or not paths.has(int(w3.id)):
					continue
				crosses += _cross_count(pts2, paths[int(w3.id)] as PackedVector2Array, xs, ys)
			var length: float = _poly_len(pts2)
			if crosses >= BREAK_CROSS and length >= BREAK_LEN and length > worst_l:
				worst = w2
				worst_l = length
		if worst == null:
			break
		var aw = circuit.get_element(int(worst.a_id))
		var bw = circuit.get_element(int(worst.b_id))
		_mark_broken(worst, aw, str(worst.a_port), bw, str(worst.b_port))
		paths.erase(int(worst.id))
		n += 1
	return n + n_pre


static func _keep_clear(circuit, w, a, b, path: Array, ctx: Dictionary) -> Array:
	if path.size() >= 2 and _drawn_ok(circuit, w, a, b, path) and not _overlaps_taken(path, a, str(w.a_port), b, str(w.b_port), ctx):
		w.broken = false
		return path
	var ta: Dictionary = _tip(a, str(w.a_port))
	var tb: Dictionary = _tip(b, str(w.b_port))
	if ta.is_empty() or tb.is_empty():
		w.broken = true
		return path
	var pa: Vector2 = ta["tip"] as Vector2
	var pb: Vector2 = tb["tip"] as Vector2
	var na: Vector2 = ta["n"] as Vector2
	var nb: Vector2 = tb["n"] as Vector2
	var best: Array = []
	var best_l: float = 1.0e12
	var spare: Array = []
	var spare_l: float = 1.0e12
	var cands: Array = [
		path,
		_norm_link(pa, na, pb, nb),
		_norm_link(pa, na, pb, nb, GRID),
		_norm_link(pa, na, pb, nb, GRID * 2.0),
		_via_axis(pa, na, pb, nb, pa.y, true),
		_via_axis(pa, na, pb, nb, pb.y, true),
	]
	var y: float = snappedf(minf(pa.y, pb.y) - GRID * 14.0, GRID)
	var y_end: float = maxf(pa.y, pb.y) + GRID * 14.0
	while y <= y_end:
		cands.append(_via_axis(pa, na, pb, nb, y, true))
		y += GRID
	var x: float = snappedf(minf(pa.x, pb.x) - GRID * 14.0, GRID)
	var x_end: float = maxf(pa.x, pb.x) + GRID * 14.0
	while x <= x_end:
		cands.append(_via_axis(pa, na, pb, nb, x, false))
		x += GRID
	for cand in cands:
		var route: Array = cand as Array
		if route.size() < 2 or not _drawn_ok(circuit, w, a, b, route):
			continue
		var leng: float = _len_path(route)
		if leng < spare_l:
			spare_l = leng
			spare = route
		if _overlaps_taken(route, a, str(w.a_port), b, str(w.b_port), ctx):
			continue
		if leng < best_l:
			best_l = leng
			best = route
	if best.size() >= 2:
		w.broken = false
		return best
	if spare.size() >= 2:
		w.broken = false
		return spare
	w.broken = true
	var a2: Vector2 = pa + _cardinal(na) * (GRID * 4.0)
	var b2: Vector2 = pb + _cardinal(nb) * (GRID * 4.0)
	return [pa, a2, b2, pb]


static func _overlaps_taken(path: Array, a, ap: String, b, bp: String, ctx: Dictionary) -> bool:
	var pts: PackedVector2Array = Geom.polyline(a, ap, b, bp, _joints_of(path))
	var hs: Array = ctx.get("taken_h", []) as Array
	var vs: Array = ctx.get("taken_v", []) as Array
	var rys: Array = ctx.get("rail_ys", []) as Array
	var rxs: Array = ctx.get("rail_xs", []) as Array
	for i in range(maxi(pts.size() - 1, 0)):
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		if absf(p.y - q.y) <= 0.75 and absf(p.x - q.x) > 15.0:
			if _near_axis(p.y, rys):
				continue
			var x0: float = minf(p.x, q.x)
			var x1: float = maxf(p.x, q.x)
			for rec in hs:
				var row: Array = rec as Array
				if absf(float(row[0]) - p.y) > 1.0:
					continue
				var lo: float = maxf(x0, float(row[1]))
				var hi: float = minf(x1, float(row[2]))
				if hi - lo > 15.0:
					return true
		elif absf(p.x - q.x) <= 0.75 and absf(p.y - q.y) > 15.0:
			if _near_axis(p.x, rxs):
				continue
			var y0: float = minf(p.y, q.y)
			var y1: float = maxf(p.y, q.y)
			for rec2 in vs:
				var col: Array = rec2 as Array
				if absf(float(col[0]) - p.x) > 1.0:
					continue
				var lo2: float = maxf(y0, float(col[1]))
				var hi2: float = minf(y1, float(col[2]))
				if hi2 - lo2 > 15.0:
					return true
	return false


static func _claim_path(pts: PackedVector2Array, ctx: Dictionary) -> void:
	if pts.size() < 4:
		return
	var hs: Array = ctx["taken_h"] as Array
	var vs: Array = ctx["taken_v"] as Array
	var rys: Array = ctx.get("rail_ys", []) as Array
	var rxs: Array = ctx.get("rail_xs", []) as Array
	for i in range(1, pts.size() - 2):
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		if absf(p.y - q.y) <= 0.75 and absf(p.x - q.x) > 15.0 and not _near_axis(p.y, rys):
			hs.append([p.y, minf(p.x, q.x), maxf(p.x, q.x)])
		elif absf(p.x - q.x) <= 0.75 and absf(p.y - q.y) > 15.0 and not _near_axis(p.x, rxs):
			vs.append([p.x, minf(p.y, q.y), maxf(p.y, q.y)])


static func _near_axis(v: float, axes: Array) -> bool:
	for item in axes:
		if absf(float(item) - v) <= 1.5:
			return true
	return false


static func _via_axis(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, line: float, horizontal: bool, step: float = STUB) -> Array:
	var a2: Vector2 = pa + _cardinal(na) * step
	var b2: Vector2 = pb + _cardinal(nb) * step
	if horizontal:
		return [pa, a2, Vector2(a2.x, line), Vector2(b2.x, line), b2, pb]
	return [pa, a2, Vector2(line, a2.y), Vector2(line, b2.y), b2, pb]


static func _drawn_ok(circuit, w, a, b, path: Array) -> bool:
	if path.size() < 2:
		return false
	var pts: PackedVector2Array = Geom.polyline(a, str(w.a_port), b, str(w.b_port), _joints_of(path))
	if _self_cross(pts):
		return false
	if not _norms_ok(a, str(w.a_port), b, str(w.b_port), pts):
		return false
	return not _wire_hits_body(circuit, a, b, pts)


static func _norms_ok(a, ap: String, b, bp: String, pts: PackedVector2Array) -> bool:
	if pts.size() < 2:
		return false
	var da: Vector2 = pts[1] - pts[0]
	if da.length() > 6.0 and _port_dot(a, ap, da) < 0.2:
		return false
	var db: Vector2 = pts[pts.size() - 2] - pts[pts.size() - 1]
	if db.length() > 6.0 and _port_dot(b, bp, db) < 0.2:
		return false
	return true


static func _port_dot(el, port: String, dir: Vector2) -> float:
	var p: Dictionary = Geom.port_by_name(el, port)
	if p.is_empty() or dir.length_squared() < 0.01:
		return 1.0
	var n: Vector2 = (p["normal"] as Vector2).rotated(float(el.rotation_quad) * PI * 0.5)
	if n.length_squared() < 0.01:
		return 1.0
	return n.normalized().dot(dir.normalized())


## Плюс: короткий выход из клеммы, вертикаль у клеммника, горизонталь на высоте строки.
static func _plus_feed(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, lane: int = 0) -> Array:
	var a2: Vector2 = pa + _cardinal(na) * (STUB + float(lane) * GRID)
	var b2: Vector2 = pb + _cardinal(nb) * STUB
	if absf(a2.y - b2.y) <= GRID:
		return [pa, a2, b2, pb]
	return [pa, a2, Vector2(a2.x, b2.y), b2, pb]


## Из порта по нормали. Если цель позади вывода — сначала в сторону, не сквозь знак.
static func _norm_link(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, step: float = STUB) -> Array:
	var a2: Vector2 = pa + _cardinal(na) * step
	var b2: Vector2 = pb + _cardinal(nb) * step
	if absf(a2.y - b2.y) <= 0.75 and absf(_cardinal(na).x) > 0.5 and absf(_cardinal(nb).x) > 0.5:
		return [pa, a2, b2, pb]
	var na_c: Vector2 = _cardinal(na)
	if absf(na_c.y) >= absf(na_c.x):
		var back_v: bool = (na_c.y > 0.0 and b2.y < a2.y - 0.5) or (na_c.y < 0.0 and b2.y > a2.y + 0.5)
		if back_v:
			return [pa, a2, Vector2(b2.x, a2.y), b2, pb]
		return [pa, a2, Vector2(a2.x, b2.y), b2, pb]
	var back_h: bool = (na_c.x > 0.0 and b2.x < a2.x - 0.5) or (na_c.x < 0.0 and b2.x > a2.x + 0.5)
	if back_h:
		return [pa, a2, Vector2(a2.x, b2.y), b2, pb]
	return [pa, a2, Vector2(b2.x, a2.y), b2, pb]


static func _self_cross(pts: PackedVector2Array) -> bool:
	if pts.size() < 4:
		return false
	for i in range(pts.size() - 1):
		for j in range(i + 2, pts.size() - 1):
			var hit: Vector2 = _seg_hit(pts[i], pts[i + 1], pts[j], pts[j + 1])
			if hit.x < 1.0e8:
				return true
	return false


static func _seg_hits_rect(p: Vector2, q: Vector2, rect: Rect2) -> bool:
	var inner: Rect2 = rect.grow(-4.0)
	if inner.size.x < 2.0 or inner.size.y < 2.0:
		return false
	var x0: float = inner.position.x
	var y0: float = inner.position.y
	var x1: float = x0 + inner.size.x
	var y1: float = y0 + inner.size.y
	if absf(p.y - q.y) <= 0.75:
		var yy: float = p.y
		if yy <= y0 or yy >= y1:
			return false
		var xa: float = minf(p.x, q.x)
		var xb: float = maxf(p.x, q.x)
		return xb > x0 + 1.0 and xa < x1 - 1.0
	if absf(p.x - q.x) <= 0.75:
		var xx: float = p.x
		if xx <= x0 or xx >= x1:
			return false
		var ya: float = minf(p.y, q.y)
		var yb: float = maxf(p.y, q.y)
		return yb > y0 + 1.0 and ya < y1 - 1.0
	return false


static func _skip_body(circuit, el, a, b) -> bool:
	if el == null or el == a or el == b:
		return true
	if str(el.kind) == "rail":
		return true
	if ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
		return true
	# Контакт кнопки нарисован на самой кнопке. Катушка реле — отдельный знак, провод сквозь неё нельзя.
	var a_btn: bool = str(a.electro_class) in ["button", "e_stop"]
	var b_btn: bool = str(b.electro_class) in ["button", "e_stop"]
	var el_btn: bool = str(el.electro_class) in ["button", "e_stop"]
	if (int(el.group_id) == int(a.id) and a_btn) or (int(el.group_id) == int(b.id) and b_btn):
		return true
	if (int(a.group_id) == int(el.id) and el_btn) or (int(b.group_id) == int(el.id) and el_btn):
		return true
	if int(a.group_id) > 0 and int(a.group_id) == int(el.group_id) and (a_btn or el_btn):
		return true
	if int(b.group_id) > 0 and int(b.group_id) == int(el.group_id) and (b_btn or el_btn):
		return true
	return false


static func _street_drop(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, y_h: float) -> Array:
	var src: Vector2 = pa
	var dst: Vector2 = pb
	var src_n: Vector2 = na
	var dst_n: Vector2 = nb
	if absf(nb.y) > absf(na.y):
		src = pb
		dst = pa
		src_n = nb
		dst_n = na
	var out: Vector2 = src + _cardinal(src_n) * STUB
	var approach: Vector2 = dst + _cardinal(dst_n) * (GRID * 2.0)
	return [src, out, Vector2(out.x, y_h), Vector2(approach.x, y_h), approach, dst]


static func _header_drop(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, y_h: float) -> Array:
	var src: Vector2 = pa
	var dst: Vector2 = pb
	var src_n: Vector2 = na
	var dst_n: Vector2 = nb
	if absf(nb.y) > absf(na.y):
		src = pb
		dst = pa
		src_n = nb
		dst_n = na
	var approach: Vector2 = dst + dst_n * (STUB + GAP)
	var out: Vector2 = src + src_n * STUB
	return [src, out, Vector2(src.x, y_h), Vector2(approach.x, y_h), approach, dst]


static func _header_only(pts: PackedVector2Array, y_limit: float) -> bool:
	if pts.size() < 2:
		return false
	for i in range(pts.size() - 1):
		if absf(pts[i].y - pts[i + 1].y) > 0.75:
			continue
		if absf(pts[i].x - pts[i + 1].x) <= GRID * 12.0:
			continue
		if pts[i].y > y_limit + GRID:
			return false
	return true


static func _wire_hits_body(circuit, a, b, pts: PackedVector2Array) -> bool:
	if a == null or b == null:
		return false
	for i in range(maxi(pts.size() - 1, 0)):
		for el in circuit.elements:
			if _skip_body(circuit, el, a, b):
				continue
			var r: Rect2 = Geom.world_bounds(el)
			if r.size.x < 4.0 or r.size.y < 4.0:
				continue
			if _seg_hits_rect(pts[i], pts[i + 1], r):
				return true
	return false


static func _short_tap(pts: PackedVector2Array) -> bool:
	if pts.size() < 2:
		return false
	var x0: float = pts[0].x
	var x1: float = pts[0].x
	var bends: int = 0
	for i in range(1, pts.size()):
		x0 = minf(x0, pts[i].x)
		x1 = maxf(x1, pts[i].x)
		if i < 2:
			continue
		var prev: Vector2 = pts[i - 1] - pts[i - 2]
		var cur: Vector2 = pts[i] - pts[i - 1]
		if absf(prev.x * cur.y - prev.y * cur.x) > 1.0:
			bends += 1
	return bends <= 1 and (x1 - x0) <= GRID * 32.0


static func _both_above(a, b, ctrl: Rect2) -> bool:
	if a == null or b == null or ctrl.size == Vector2.ZERO:
		return false
	var top: float = ctrl.position.y
	return float(a.position.y) < top - GRID and float(b.position.y) < top - GRID


static func _force_power_break(a, b, pts: PackedVector2Array, ctrl: Rect2) -> bool:
	if a == null or b == null or pts.size() < 2:
		return false
	var pa: bool = _is_power_end(a)
	var pb: bool = _is_power_end(b)
	if pa == pb:
		return false
	if not ctrl.has_area() or ctrl.size == Vector2.ZERO:
		return false
	var y0: float = minf(pts[0].y, pts[pts.size() - 1].y)
	var y1: float = maxf(pts[0].y, pts[pts.size() - 1].y)
	var x0: float = minf(pts[0].x, pts[pts.size() - 1].x)
	var x1: float = maxf(pts[0].x, pts[pts.size() - 1].x)
	var cy0: float = ctrl.position.y
	var cy1: float = ctrl.position.y + ctrl.size.y
	var cx0: float = ctrl.position.x
	var cx1: float = ctrl.position.x + ctrl.size.x
	var cross_y: bool = y0 < cy1 - GRID and y1 > cy0 + GRID and (y1 - y0) > GRID * 16.0
	var cross_x: bool = x0 < cx1 and x1 > cx0
	return cross_y and cross_x


static func _mark_broken(w, a, ap: String, b, bp: String) -> void:
	var ta: Dictionary = _tip(a, ap)
	var tb: Dictionary = _tip(b, bp)
	if ta.is_empty() or tb.is_empty():
		w.broken = true
		return
	var pa: Vector2 = ta["tip"] as Vector2
	var pb: Vector2 = tb["tip"] as Vector2
	var na: Vector2 = ta["n"] as Vector2
	var nb: Vector2 = tb["n"] as Vector2
	var a2: Vector2 = pa + _cardinal(na) * (GRID * 4.0)
	var b2: Vector2 = pb + _cardinal(nb) * (GRID * 4.0)
	w.joints = _joints_of([pa, a2, Vector2(b2.x, a2.y), b2, pb])
	w.broken = true


# --- геометрия трасс ------------------------------------------------------

static func _route_drop(w, pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, a, b, ctx: Dictionary) -> Array:
	var src: Vector2 = pa
	var dst: Vector2 = pb
	var src_n: Vector2 = na
	var dst_n: Vector2 = nb
	var target = b
	if absf(nb.y) > absf(na.y):
		src = pb
		dst = pa
		src_n = nb
		dst_n = na
		target = a
	var lanes: Dictionary = ctx.get("lanes", {}) as Dictionary
	var y_lane: float = float(ctx.get("y_chan", src.y))
	if lanes.has(int(target.id)):
		y_lane = float(lanes[int(target.id)])
	var src_out: Vector2 = src + src_n * STUB
	var approach: Vector2 = dst + dst_n * STUB
	var path: Array = [src, src_out, Vector2(src.x, y_lane), Vector2(approach.x, y_lane), approach, dst]
	if not lanes.has(int(target.id)):
		var ctrl: Rect2 = ctx.get("ctrl", Rect2()) as Rect2
		if not _both_above(a, b, ctrl) and _path_hits_rect(path, ctrl):
			w.broken = true
	return path


static func _path_hits_rect(path: Array, r: Rect2) -> bool:
	if r.size == Vector2.ZERO:
		return false
	var inner: Rect2 = r.grow(-GRID)
	if inner.size.x < 4.0 or inner.size.y < 4.0:
		return false
	for i in range(maxi(path.size() - 1, 0)):
		var p: Vector2 = path[i] as Vector2
		var q: Vector2 = path[i + 1] as Vector2
		if absf(p.y - q.y) <= 0.75:
			var y: float = p.y
			if y < inner.position.y or y > inner.position.y + inner.size.y:
				continue
			var x0: float = minf(p.x, q.x)
			var x1: float = maxf(p.x, q.x)
			if x1 > inner.position.x and x0 < inner.position.x + inner.size.x:
				return true
		else:
			var x: float = p.x
			if x < inner.position.x or x > inner.position.x + inner.size.x:
				continue
			var y0: float = minf(p.y, q.y)
			var y1: float = maxf(p.y, q.y)
			if y1 > inner.position.y and y0 < inner.position.y + inner.size.y:
				return true
	return false


static func _is_coil_return(port: String) -> bool:
	var p: String = port.to_upper()
	return p == "A2" or p == "X2"


static func _in_ladder(el, ctrl: Rect2) -> bool:
	if el == null or ctrl.size == Vector2.ZERO:
		return false
	return float(el.position.y) >= ctrl.position.y - GRID * 2.0


static func _on_y(pa: Vector2, pb: Vector2, y_line: float) -> Array:
	return [pa, Vector2(pa.x, y_line), Vector2(pb.x, y_line), pb]


static func _on_x(pa: Vector2, pb: Vector2, x_line: float) -> Array:
	return [pa, Vector2(x_line, pa.y), Vector2(x_line, pb.y), pb]


static func _elbow_at_x(pa: Vector2, pb: Vector2, x_elbow: float) -> Array:
	if absf(pa.y - pb.y) <= 0.75:
		return [pa, (pa + pb) * 0.5, pb]
	return [pa, Vector2(x_elbow, pa.y), Vector2(x_elbow, pb.y), pb]


static func _route_rung(pa: Vector2, pb: Vector2) -> Array:
	if absf(pa.y - pb.y) <= GRID * 1.5:
		# Почти одна высота — прямая (не «лесенка» из‑за 1 клетки).
		return [pa, (pa + pb) * 0.5, pb]
	return _elbow_at_x(pa, pb, pa.x)


## Столб под автоматом, если он не сечёт чужие строки; иначе горизонталь в зазоре над таблицей.
static func _route_power_drop(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, ctx: Dictionary) -> Array:
	var src: Vector2 = pa
	var dst: Vector2 = pb
	if absf(nb.y) > absf(na.y):
		src = pb
		dst = pa
	var ys: Array = ctx.get("rung_ys_list", []) as Array
	var x0: float = float(ctx.get("rung_x0", 0.0))
	var x1: float = float(ctx.get("rung_x1", 0.0))
	var drop_n: int = _v_hits_rungs(src.x, src.y, dst.y, ys, x0, x1)
	if drop_n <= 2:
		return _elbow_at_x(pa, pb, src.x)
	var y_gap: float = float(ctx.get("y_chan", src.y))
	var gap_n: int = _v_hits_rungs(dst.x, y_gap, dst.y, ys, x0, x1)
	if gap_n <= 2:
		return [pa, Vector2(pa.x, y_gap), Vector2(pb.x, y_gap), pb]
	return _elbow_at_x(pa, pb, src.x)


static func _v_hits_rungs(x: float, y0: float, y1: float, ys: Array, x0: float, x1: float) -> int:
	if x1 <= x0 or x < x0 - GRID or x > x1 + GRID:
		return 0
	var lo: float = minf(y0, y1)
	var hi: float = maxf(y0, y1)
	var n: int = 0
	for yv in ys:
		var y: float = float(yv)
		if y > lo + GRID and y < hi - GRID:
			n += 1
	return n


static func _via_h(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, y_line: float) -> Array:
	var a2: Vector2 = _stub(pa, na)
	var b2: Vector2 = _stub(pb, nb)
	var path: Array = [pa, a2]
	if absf(a2.y - y_line) > 0.5:
		path.append(Vector2(a2.x, y_line))
	path.append(Vector2(b2.x, y_line))
	if absf(b2.y - y_line) > 0.5:
		path.append(b2)
	else:
		path.append(b2)
	path.append(pb)
	return path


static func _via_v(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2, x_line: float) -> Array:
	var a2: Vector2 = _stub(pa, na)
	var b2: Vector2 = _stub(pb, nb)
	var path: Array = [pa, a2, Vector2(x_line, a2.y), Vector2(x_line, b2.y), b2, pb]
	return path


static func _direct(pa: Vector2, na: Vector2, pb: Vector2, nb: Vector2) -> Array:
	var a2: Vector2 = _stub(pa, na)
	var b2: Vector2 = _stub(pb, nb)
	var via_h: Array = [pa, a2, Vector2(b2.x, a2.y), b2, pb]
	var via_v: Array = [pa, a2, Vector2(a2.x, b2.y), b2, pb]
	if absf(pa.y - pb.y) <= 0.75 and absf(na.x) >= absf(na.y) and absf(nb.x) >= absf(nb.y):
		return [pa, (pa + pb) * 0.5, pb]
	if _len_path(via_v) + 0.01 < _len_path(via_h):
		return via_v
	return via_h


static func _joints_of(path: Array) -> Array:
	var seq := PackedVector2Array()
	for p in path:
		seq.append(p as Vector2)
	var clean: PackedVector2Array = Geom.simplify_ortho_path(Geom._dedupe(Geom._ortho(seq)))
	var joints: Array = []
	if clean.size() <= 2:
		if clean.size() == 2:
			joints.append((clean[0] + clean[1]) * 0.5)
		return joints
	for i in range(1, clean.size() - 1):
		joints.append(clean[i])
	return joints


static func _stub(tip: Vector2, n: Vector2) -> Vector2:
	var c: Vector2 = _cardinal(n)
	var p: Vector2 = (tip + c * STUB).snapped(Vector2(GRID, GRID))
	if (p - tip).dot(c) < GRID * 0.5:
		p += c * GRID
	return p


static func _cardinal(n: Vector2) -> Vector2:
	if absf(n.x) >= absf(n.y):
		return Vector2(1.0 if n.x >= 0.0 else -1.0, 0.0)
	return Vector2(0.0, 1.0 if n.y >= 0.0 else -1.0)


static func _add_h_rail(circuit, x0: float, x1: float, y: float) -> void:
	var el = circuit.add_element_raw("rail", Vector2(x0, y))
	el.rail_domain = "electric"
	el.tag = ""
	el.rail_taps = []
	el.rail_points = PackedVector2Array([Vector2.ZERO, Vector2(x1 - x0, 0.0)])


static func _add_v_rail(circuit, x: float, y0: float, y1: float) -> void:
	if absf(y1 - y0) < GRID * 3.0:
		return
	var el = circuit.add_element_raw("rail", Vector2(x, y0))
	el.rail_domain = "electric"
	el.tag = ""
	el.rail_taps = []
	el.rail_points = PackedVector2Array([Vector2.ZERO, Vector2(0.0, y1 - y0)])


# --- размещение одного УГО ------------------------------------------------

static func _place_top_left(circuit, el, left: float, top: float) -> Rect2:
	var b: Rect2 = Geom.world_bounds(el)
	var delta := Vector2(left - b.position.x, top - b.position.y)
	_move(circuit, el, (el.position + delta).snapped(Vector2(GRID, GRID)))
	return Geom.world_bounds(el)


static func _place_on_row(circuit, el, left: float, rung_y: float) -> Rect2:
	var port: String = _row_port(circuit, el)
	var tip: Dictionary = _tip(el, port)
	var b: Rect2 = Geom.world_bounds(el)
	var want_y: float = rung_y
	if not tip.is_empty():
		want_y = rung_y - float((tip["tip"] as Vector2).y) + float(el.position.y)
	var delta := Vector2(left - b.position.x, want_y - float(el.position.y))
	_move(circuit, el, (el.position + delta).snapped(Vector2(GRID, GRID)))
	if str(el.electro_class) in ["button", "e_stop"] and str(el.member_role) != "contact":
		ElectroLib.layout_button_contacts(circuit, el)
		var fixed = _button_fixed(circuit, el)
		if fixed != null:
			var tp: Dictionary = _tip(fixed, _row_port(circuit, fixed))
			if not tp.is_empty():
				var dy: float = rung_y - float((tp["tip"] as Vector2).y)
				_move(circuit, el, el.position + Vector2(0.0, dy))
				ElectroLib.layout_button_contacts(circuit, el)
	return _row_bounds(circuit, el)


static func _place_center_x(circuit, el, cx: float, rung_y: float) -> Rect2:
	var port: String = "X1" if str(el.electro_class) == "lamp" else "A1"
	if Geom.port_by_name(el, port).is_empty():
		port = _row_port(circuit, el)
	var tip: Dictionary = _tip(el, port)
	var b: Rect2 = Geom.world_bounds(el)
	var target_x: float = cx - b.size.x * 0.5
	var want_y: float = float(el.position.y)
	if not tip.is_empty():
		want_y = rung_y - float((tip["tip"] as Vector2).y) + float(el.position.y)
	var delta := Vector2(target_x - b.position.x, want_y - float(el.position.y))
	_move(circuit, el, (el.position + delta).snapped(Vector2(GRID, GRID)))
	return Geom.world_bounds(el)


static func _row_bounds(circuit, el) -> Rect2:
	var b: Rect2 = Geom.world_bounds(el)
	if str(el.electro_class) in ["button", "e_stop"]:
		var fixed = _button_fixed(circuit, el)
		if fixed != null:
			var fb: Rect2 = Geom.world_bounds(fixed)
			b = b.expand(fb.position).expand(fb.position + fb.size)
	return b


static func _move(circuit, el, pos: Vector2) -> void:
	var delta: Vector2 = pos - el.position
	if delta.length_squared() < 0.01:
		el.position = pos
		return
	el.position = pos
	if str(el.kind) != "electro" or str(el.member_role) == "contact":
		return
	var gid: int = int(el.group_id) if int(el.group_id) >= 0 else int(el.id)
	if not circuit.has_method("electro_group_members"):
		return
	for m in circuit.electro_group_members(gid):
		if int(m.id) == int(el.id):
			continue
		if str(m.member_role) != "contact":
			continue
		if bool(m.detached) and not ElectroLib.is_button_fixed_contact(circuit, m):
			continue
		m.position = (m.position + delta).snapped(Vector2(GRID, GRID))


static func _set_rot(el, rot: int) -> void:
	el.rotation_quad = rot


static func _recenter(circuit, old_center: Vector2) -> void:
	var box := Rect2()
	var any: bool = false
	for el in circuit.elements:
		if el == null or str(el.kind) == "rail":
			continue
		var b: Rect2 = Geom.world_bounds(el)
		if not any:
			box = b
			any = true
		else:
			box = box.expand(b.position).expand(b.position + b.size)
	if not any:
		return
	var delta: Vector2 = (old_center - box.get_center()).snapped(Vector2(GRID, GRID))
	if delta.length_squared() < 0.25:
		return
	for el2 in circuit.elements:
		el2.position += delta
	for w in circuit.wires:
		var joints: Array = w.joints if typeof(w.joints) == TYPE_ARRAY else []
		if joints.is_empty():
			continue
		var moved: Array = []
		for j in joints:
			if j is Vector2:
				moved.append((j as Vector2) + delta)
			else:
				moved.append(j)
		w.joints = moved


# --- классификация --------------------------------------------------------

static func _is_load(el) -> bool:
	if el == null or str(el.kind) != "electro":
		return false
	if str(el.member_role) == "contact":
		return false
	var cls: String = str(el.electro_class)
	if cls == "lamp":
		return true
	return cls in ["relay", "timer_relay", "contactor", "voltage_relay", "solenoid_coil"]


static func _is_breaker(el) -> bool:
	if el == null:
		return false
	return str(el.electro_class) in ["mcb", "rcd", "rcbo"]


static func _is_chain_stop(el) -> bool:
	if el == null:
		return true
	var cls: String = str(el.electro_class)
	if cls in ["terminal", "supply", "supply_leg", "mcb", "rcd", "rcbo", "psu", "busbar"]:
		return true
	if cls == "thermal" and str(el.member_role) != "contact":
		return true
	if _is_load(el):
		return true
	return false


static func _is_power_end(el) -> bool:
	if el == null or str(el.kind) != "electro":
		return false
	var cls: String = str(el.electro_class)
	if cls in ["mcb", "rcd", "rcbo", "supply", "supply_leg", "psu"]:
		return true
	if cls == "thermal" and str(el.member_role) != "contact":
		return true
	return false


static func _is_power_gadget(circuit, el, claimed: Dictionary) -> bool:
	if el == null or claimed.has(int(el.id)):
		return false
	if str(el.kind) != "electro":
		return false
	if str(el.electro_class) == "thermal" and str(el.member_role) != "contact":
		return true
	if str(el.member_role) != "contact" or not bool(el.detached):
		return false
	if ElectroLib.is_button_fixed_contact(circuit, el):
		return false
	var ctrl: bool = false
	var pwr: bool = false
	for w in circuit.wires:
		var other = null
		if int(w.a_id) == int(el.id):
			other = circuit.get_element(int(w.b_id))
		elif int(w.b_id) == int(el.id):
			other = circuit.get_element(int(w.a_id))
		else:
			continue
		if other == null:
			continue
		if _is_load(other) or str(other.electro_class) in ["button", "e_stop", "switch", "lamp"]:
			ctrl = true
		if _is_power_end(other) or str(other.electro_class) == "terminal":
			pwr = true
	return pwr and not ctrl


static func _both_power_band(a, b) -> bool:
	return _is_power_end(a) and _is_power_end(b)


static func _on_control(ctx: Dictionary, el) -> bool:
	if el == null:
		return false
	var ys: Dictionary = ctx.get("ys", {}) as Dictionary
	if ys.has(int(el.id)):
		return true
	var rung_of: Dictionary = ctx.get("rung_of", {}) as Dictionary
	return rung_of.has(int(el.id))


static func _rung_index(circuit, ctx: Dictionary) -> Dictionary:
	var ys: Dictionary = ctx.get("ys", {}) as Dictionary
	var out: Dictionary = {}
	for lid in ys.keys():
		var load = circuit.get_element(int(lid))
		if load == null:
			continue
		_tag_rung(circuit, out, int(lid), int(lid))
		var chain: Array = _hot_chain(circuit, load)
		for idv in chain:
			_tag_rung(circuit, out, int(idv), int(lid))
	return out


static func _tag_rung(circuit, out: Dictionary, id: int, lid: int) -> void:
	if id < 0 or out.has(id):
		return
	out[id] = lid
	var el = circuit.get_element(id)
	if el == null or str(el.electro_class) not in ["button", "e_stop"]:
		return
	if str(el.member_role) == "contact":
		return
	if not circuit.has_method("electro_group_members"):
		return
	for m in circuit.electro_group_members(int(el.id)):
		if str(m.member_role) != "contact":
			continue
		if not out.has(int(m.id)):
			out[int(m.id)] = lid


static func _zone_a_rank(el) -> int:
	var cls: String = str(el.electro_class)
	if cls == "supply":
		return 0
	if cls == "supply_leg":
		var ph: String = str(el.phase).to_upper()
		if ph == "PE":
			return 3
		if ph in ["N", "0", "-"]:
			return 2
		return 1
	return 4


static func _port_role(port: String) -> String:
	var p: String = port.to_upper()
	if p in ["A2", "X2", "N", "0", "-", "PE"]:
		return "ret"
	if p in ["A1", "X1", "L", "L1", "L2", "L3", "+", "+24", "+24V"]:
		return "hot"
	return ""


static func _row_port(circuit, el) -> String:
	if ElectroLib.is_button_fixed_contact(circuit, el) or str(el.electro_class) in ["button", "e_stop"]:
		var host = el
		if str(el.member_role) == "contact":
			host = el
		var ports: Array = Geom.ports(host)
		for p in ports:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var n: Vector2 = p.get("normal", Vector2.LEFT) as Vector2
			if n.x < -0.5:
				return str(p.get("name", ""))
		if ports.size() > 0 and typeof(ports[0]) == TYPE_DICTIONARY:
			return str(ports[0].get("name", ""))
	var ports2: Array = Geom.ports(el)
	for p2 in ports2:
		if typeof(p2) != TYPE_DICTIONARY:
			continue
		var n2: Vector2 = p2.get("normal", Vector2.ZERO) as Vector2
		if n2.x < -0.5:
			return str(p2.get("name", ""))
	if ports2.size() > 0 and typeof(ports2[0]) == TYPE_DICTIONARY:
		return str(ports2[0].get("name", ""))
	return ""


static func _button_fixed(circuit, primary):
	for m in circuit.electro_group_members(int(primary.id)):
		if ElectroLib.is_button_fixed_contact(circuit, m):
			return m
	return null


static func _other_ports(circuit, el, except_port: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in circuit.wires:
		var pn: String = ""
		if int(w.a_id) == int(el.id):
			pn = str(w.a_port)
		elif int(w.b_id) == int(el.id):
			pn = str(w.b_port)
		else:
			continue
		if pn == except_port or pn == "":
			continue
		if not out.has(pn):
			out.append(pn)
	return out


static func _peer_el(circuit, w, el):
	if int(w.a_id) == int(el.id):
		return circuit.get_element(int(w.b_id))
	return circuit.get_element(int(w.a_id))


static func _peer_port(w, el) -> String:
	if int(w.a_id) == int(el.id):
		return str(w.b_port)
	return str(w.a_port)


static func _tip(el, port: String) -> Dictionary:
	if el == null or port == "":
		return {}
	var p: Dictionary = Geom.port_by_name(el, port)
	if p.is_empty():
		return {}
	var n: Vector2 = (p["normal"] as Vector2).rotated(float(el.rotation_quad) * PI * 0.5)
	return {"tip": Geom.to_world(el, p["local"]), "n": n}


static func _electric_wire(circuit, w) -> bool:
	var a = circuit.get_element(int(w.a_id))
	if a == null:
		return false
	return Geom.port_domain(a, str(w.a_port)) == "electric"


static func _argmax(counts: Dictionary) -> int:
	var best_id: int = -1
	var best_n: int = 0
	for k in counts.keys():
		var n: int = int(counts[k])
		if n > best_n:
			best_n = n
			best_id = int(k)
	return best_id


static func _argmax_except(counts: Dictionary, skip: int) -> int:
	var best_id: int = -1
	var best_n: int = 0
	for k in counts.keys():
		if int(k) == skip:
			continue
		var n: int = int(counts[k])
		if n > best_n:
			best_n = n
			best_id = int(k)
	return best_id


# --- пересечения ----------------------------------------------------------

static func _is_rider(pts: PackedVector2Array, xs: Array, ys: Array) -> bool:
	if pts.size() < 2:
		return false
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if absf(a.x - b.x) < 0.75 and absf(a.y - b.y) > GRID * 3.0:
			for x in xs:
				if absf(a.x - float(x)) < 1.0:
					return true
		if absf(a.y - b.y) < 0.75 and absf(a.x - b.x) > GRID * 3.0:
			for y in ys:
				if absf(a.y - float(y)) < 1.0:
					return true
	return false


static func _cross_count(a: PackedVector2Array, b: PackedVector2Array, xs: Array, ys: Array) -> int:
	if a.size() < 2 or b.size() < 2:
		return 0
	var n: int = 0
	for i in range(a.size() - 1):
		for j in range(b.size() - 1):
			var hit: Vector2 = _seg_hit(a[i], a[i + 1], b[j], b[j + 1])
			if hit.x > 1.0e8:
				continue
			if _on_corridor(hit, xs, ys):
				continue
			n += 1
	return n


static func _on_corridor(p: Vector2, xs: Array, ys: Array) -> bool:
	for x in xs:
		if absf(p.x - float(x)) <= GRID:
			return true
	for y in ys:
		if absf(p.y - float(y)) <= GRID:
			return true
	return false


static func _seg_hit(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var ab_h: bool = absf(a.y - b.y) <= absf(a.x - b.x)
	var cd_h: bool = absf(c.y - d.y) <= absf(c.x - d.x)
	if ab_h == cd_h:
		return Vector2(INF, INF)
	var h0: Vector2 = a if ab_h else c
	var h1: Vector2 = b if ab_h else d
	var v0: Vector2 = c if ab_h else a
	var v1: Vector2 = d if ab_h else b
	var y: float = h0.y
	var x: float = v0.x
	if x < minf(h0.x, h1.x) + 0.8 or x > maxf(h0.x, h1.x) - 0.8:
		return Vector2(INF, INF)
	if y < minf(v0.y, v1.y) + 0.8 or y > maxf(v0.y, v1.y) - 0.8:
		return Vector2(INF, INF)
	return Vector2(x, y)


static func _poly_len(pts: PackedVector2Array) -> float:
	var L: float = 0.0
	for i in range(maxi(pts.size() - 1, 0)):
		L += pts[i].distance_to(pts[i + 1])
	return L


static func _len_path(path: Array) -> float:
	var L: float = 0.0
	for i in range(1, path.size()):
		L += (path[i - 1] as Vector2).distance_to(path[i] as Vector2)
	return L


static func _body_hits(circuit) -> int:
	var n: int = 0
	for w in circuit.wires:
		if not _electric_wire(circuit, w) or bool(w.broken):
			continue
		var a = circuit.get_element(int(w.a_id))
		var b = circuit.get_element(int(w.b_id))
		if a == null or b == null:
			continue
		var pts: PackedVector2Array = Geom.polyline(a, str(w.a_port), b, str(w.b_port), w.joints)
		if _wire_hits_body(circuit, a, b, pts):
			n += 1
	return n
