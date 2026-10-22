extends RefCounted
## Воксельный A* внутри объёма кабельных каналов (H/V).
## Снаружи КК не ищет — только орто-соседи ±X/±Y/±Z.

const STEP_COST := 1.0
const TURN_PENALTY := 2.8
const DIR_NONE := -1
## ±X, ±Y, ±Z
const DIRS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## walkable: Dictionary "ix,iy,iz" -> true; origin — угол сетки; cell — шаг (м).
## vh/sh — fallback; предпочтительно h["vh"]/h["sh"] из cable_ducts_world.
static func build_walkable(hs: Array, vs: Array, cell: float, vh: float, sh: float) -> Dictionary:
	var cell_s: float = maxf(cell, 0.006)
	var cells: Dictionary = {}
	var min_p := Vector3(1.0e9, 1.0e9, 1.0e9)
	var max_p := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for h in hs:
		var hy: float = float(h.get("y", 0.0))
		var hz: float = float(h.get("z", 0.0))
		var x0: float = float(h.get("x0", 0.0))
		var x1: float = float(h.get("x1", 0.0))
		var half_y: float = float(h.get("vh", vh)) * 0.38
		var half_z: float = float(h.get("sh", sh)) * 0.38
		min_p.x = minf(min_p.x, x0)
		max_p.x = maxf(max_p.x, x1)
		min_p.y = minf(min_p.y, hy - half_y)
		max_p.y = maxf(max_p.y, hy + half_y)
		min_p.z = minf(min_p.z, hz - half_z)
		max_p.z = maxf(max_p.z, hz + half_z)
	for v in vs:
		var vx: float = float(v.get("x", 0.0))
		var vz: float = float(v.get("z", 0.0))
		var y0: float = float(v.get("y0", 0.0))
		var y1: float = float(v.get("y1", 0.0))
		var half_y_v: float = float(v.get("vh", vh)) * 0.38
		var half_z_v: float = float(v.get("sh", sh)) * 0.38
		min_p.x = minf(min_p.x, vx - half_y_v)
		max_p.x = maxf(max_p.x, vx + half_y_v)
		min_p.y = minf(min_p.y, y0)
		max_p.y = maxf(max_p.y, y1)
		min_p.z = minf(min_p.z, vz - half_z_v)
		max_p.z = maxf(max_p.z, vz + half_z_v)
	if min_p.x > 1.0e8:
		return {"cells": {}, "origin": Vector3.ZERO, "cell": cell_s}
	var origin: Vector3 = min_p - Vector3(cell_s, cell_s, cell_s) * 0.5
	for h2 in hs:
		var hy2: float = float(h2.get("y", 0.0))
		var hz2: float = float(h2.get("z", 0.0))
		var xa: float = float(h2.get("x0", 0.0))
		var xb: float = float(h2.get("x1", 0.0))
		var hyh: float = float(h2.get("vh", vh)) * 0.38
		var hzh: float = float(h2.get("sh", sh)) * 0.38
		_fill_box(cells, origin, cell_s, xa, xb, hy2 - hyh, hy2 + hyh, hz2 - hzh, hz2 + hzh)
	for v2 in vs:
		var vx2: float = float(v2.get("x", 0.0))
		var vz2: float = float(v2.get("z", 0.0))
		var ya: float = float(v2.get("y0", 0.0))
		var yb: float = float(v2.get("y1", 0.0))
		var vyh: float = float(v2.get("vh", vh)) * 0.38
		var vzh: float = float(v2.get("sh", sh)) * 0.38
		_fill_box(cells, origin, cell_s, vx2 - vyh, vx2 + vyh, ya, yb, vz2 - vzh, vz2 + vzh)
	return {"cells": cells, "origin": origin, "cell": cell_s}


static func _fill_box(cells: Dictionary, origin: Vector3, cell: float, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var ix0: int = int(floor((minf(x0, x1) - origin.x) / cell))
	var ix1: int = int(floor((maxf(x0, x1) - origin.x) / cell))
	var iy0: int = int(floor((minf(y0, y1) - origin.y) / cell))
	var iy1: int = int(floor((maxf(y0, y1) - origin.y) / cell))
	var iz0: int = int(floor((minf(z0, z1) - origin.z) / cell))
	var iz1: int = int(floor((maxf(z0, z1) - origin.z) / cell))
	for ix in range(ix0, ix1 + 1):
		for iy in range(iy0, iy1 + 1):
			for iz in range(iz0, iz1 + 1):
				cells[_key(ix, iy, iz)] = true


static func _key(ix: int, iy: int, iz: int) -> String:
	return "%d,%d,%d" % [ix, iy, iz]


static func world_to_cell(p: Vector3, origin: Vector3, cell: float) -> Vector3i:
	return Vector3i(
		int(floor((p.x - origin.x) / cell)),
		int(floor((p.y - origin.y) / cell)),
		int(floor((p.z - origin.z) / cell))
	)


static func cell_to_world(c: Vector3i, origin: Vector3, cell: float) -> Vector3:
	return origin + Vector3(
		(float(c.x) + 0.5) * cell,
		(float(c.y) + 0.5) * cell,
		(float(c.z) + 0.5) * cell
	)


static func nearest_walkable(p: Vector3, walkable: Dictionary, origin: Vector3, cell: float, max_r: int = 6) -> Vector3i:
	var cells: Dictionary = walkable.get("cells", {}) as Dictionary
	var c0: Vector3i = world_to_cell(p, origin, cell)
	if cells.has(_key(c0.x, c0.y, c0.z)):
		return c0
	var best: Vector3i = c0
	var best_d: int = 1 << 30
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if maxi(maxi(absi(dx), absi(dy)), absi(dz)) != r:
						continue
					var c: Vector3i = Vector3i(c0.x + dx, c0.y + dy, c0.z + dz)
					if not cells.has(_key(c.x, c.y, c.z)):
						continue
					var d: int = absi(dx) + absi(dy) + absi(dz)
					if d < best_d:
						best_d = d
						best = c
		if best_d < 1 << 30:
			return best
	return c0


## A*: кратчайший ortho-путь, штраф за смену направления (прямые участки выгоднее).
static func find_path(start_w: Vector3, goal_w: Vector3, walkable: Dictionary, occupied: Dictionary) -> PackedVector3Array:
	var cells: Dictionary = walkable.get("cells", {}) as Dictionary
	var origin: Vector3 = walkable.get("origin", Vector3.ZERO) as Vector3
	var cell: float = float(walkable.get("cell", 0.011))
	if cells.is_empty() or cell < 1.0e-6:
		return PackedVector3Array()
	var start: Vector3i = nearest_walkable(start_w, walkable, origin, cell)
	var goal: Vector3i = nearest_walkable(goal_w, walkable, origin, cell)
	var sk: String = _key(start.x, start.y, start.z)
	var gk: String = _key(goal.x, goal.y, goal.z)
	if not cells.has(sk) or not cells.has(gk):
		return PackedVector3Array()
	# state key: "ix,iy,iz,dir"
	var open: Array = [] # {f, g, ix, iy, iz, dir}
	var g_score: Dictionary = {}
	var came: Dictionary = {} # state -> prev state
	var start_state: String = "%s,%d" % [sk, DIR_NONE]
	g_score[start_state] = 0.0
	open.append({"f": float(_manhattan(start, goal)), "g": 0.0, "ix": start.x, "iy": start.y, "iz": start.z, "dir": DIR_NONE})
	var guard: int = 0
	var goal_state: String = ""
	while not open.is_empty() and guard < 80000:
		guard += 1
		var bi: int = 0
		var bf: float = float(open[0]["f"])
		for oi in range(1, open.size()):
			var fo: float = float(open[oi]["f"])
			if fo < bf:
				bf = fo
				bi = oi
		var cur: Dictionary = open[bi]
		open.remove_at(bi)
		var cix: int = int(cur["ix"])
		var ciy: int = int(cur["iy"])
		var ciz: int = int(cur["iz"])
		var cdir: int = int(cur["dir"])
		var cst: String = "%d,%d,%d,%d" % [cix, ciy, ciz, cdir]
		if cix == goal.x and ciy == goal.y and ciz == goal.z:
			goal_state = cst
			break
		var cg: float = float(cur["g"])
		if float(g_score.get(cst, 1.0e30)) < cg - 1.0e-6:
			continue
		for di in DIRS.size():
			var d: Vector3i = DIRS[di] as Vector3i
			var nix: int = cix + d.x
			var niy: int = ciy + d.y
			var niz: int = ciz + d.z
			var nk: String = _key(nix, niy, niz)
			if not cells.has(nk):
				continue
			if occupied.has(nk) and nk != gk and nk != sk:
				continue
			# Запрет разворота 180°.
			if cdir >= 0 and di == (cdir ^ 1):
				continue
			var turn: float = 0.0
			if cdir >= 0 and di != cdir:
				turn = TURN_PENALTY
			var ng: float = cg + STEP_COST + turn
			var nst: String = "%d,%d,%d,%d" % [nix, niy, niz, di]
			if ng + 1.0e-6 >= float(g_score.get(nst, 1.0e30)):
				continue
			g_score[nst] = ng
			came[nst] = cst
			var nf: float = ng + float(_manhattan(Vector3i(nix, niy, niz), goal))
			open.append({"f": nf, "g": ng, "ix": nix, "iy": niy, "iz": niz, "dir": di})
	if goal_state == "":
		return PackedVector3Array()
	# Восстановить ячейки.
	var chain: Array = []
	var st: String = goal_state
	var seen: Dictionary = {}
	while st != "" and not seen.has(st):
		seen[st] = true
		var parts: PackedStringArray = st.split(",")
		if parts.size() < 4:
			break
		chain.append(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])))
		st = str(came.get(st, ""))
	chain.reverse()
	# Сжать коллинеарные → мировые точки.
	var wpts := PackedVector3Array()
	if chain.is_empty():
		return wpts
	wpts.append(cell_to_world(chain[0] as Vector3i, origin, cell))
	for i in range(1, chain.size() - 1):
		var prev: Vector3i = chain[i - 1] as Vector3i
		var mid: Vector3i = chain[i] as Vector3i
		var nxt: Vector3i = chain[i + 1] as Vector3i
		var d0: Vector3i = mid - prev
		var d1: Vector3i = nxt - mid
		if d0 != d1:
			wpts.append(cell_to_world(mid, origin, cell))
	wpts.append(cell_to_world(chain[chain.size() - 1] as Vector3i, origin, cell))
	return wpts


static func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


## Пометить ячейки пути занятыми (без первой/последней — общие входы).
static func occupy_path(path: PackedVector3Array, occupied: Dictionary, walkable: Dictionary) -> void:
	if path.size() < 2:
		return
	var origin: Vector3 = walkable.get("origin", Vector3.ZERO) as Vector3
	var cell: float = float(walkable.get("cell", 0.011))
	for i in range(1, path.size() - 1):
		var c: Vector3i = world_to_cell(path[i], origin, cell)
		occupied[_key(c.x, c.y, c.z)] = true
	# Также промежутки между сжатыми узлами.
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ca: Vector3i = world_to_cell(a, origin, cell)
		var cb: Vector3i = world_to_cell(b, origin, cell)
		var steps: int = absi(cb.x - ca.x) + absi(cb.y - ca.y) + absi(cb.z - ca.z)
		for s in range(1, steps):
			var t: float = float(s) / float(steps)
			var p: Vector3 = a.lerp(b, t)
			var c2: Vector3i = world_to_cell(p, origin, cell)
			occupied[_key(c2.x, c2.y, c2.z)] = true
