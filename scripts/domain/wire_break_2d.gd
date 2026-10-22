extends RefCounted
## 2D-обрыв линии электрической связи (ГОСТ 2.721 п.8 / п.35).
## Групповая линия — отдельно через rail УГО (Rail2D), не через wire.group_id.
## Электрика и 3D не меняются — только чертёж схемы.

const Geom = preload("res://scripts/domain/symbol_geom.gd")

## Хвост у порта: 4 клетки сетки по нормали отростка.
const STUB_LEN := 40.0


static func is_schematic_cut(wire) -> bool:
	return wire != null and bool(wire.broken)


## Хвост от tip порта вдоль world-нормали: {pts, tip, dir} или {}.
static func port_stub(circuit, wire, at_a: bool) -> Dictionary:
	if circuit == null or wire == null:
		return {}
	var el_id: int = int(wire.a_id) if at_a else int(wire.b_id)
	var port: String = str(wire.a_port) if at_a else str(wire.b_port)
	var el = circuit.get_element(el_id)
	if el == null:
		return {}
	var tip_local := Vector2.ZERO
	var n_local := Vector2.RIGHT
	var found: bool = false
	for p in Geom.ports(el):
		if str(p.get("name", "")) != port:
			continue
		tip_local = p["local"] as Vector2
		n_local = p.get("normal", Vector2.RIGHT) as Vector2
		found = true
		break
	if not found:
		return {}
	var tip_w: Vector2 = Geom.to_world(el, tip_local)
	var n_w: Vector2 = n_local.rotated(float(el.rotation_quad) * PI * 0.5)
	if n_w.length_squared() < 1.0e-8:
		n_w = Vector2.RIGHT
	else:
		n_w = n_w.normalized()
	var end_w: Vector2 = tip_w + n_w * STUB_LEN
	# Концы на сетке — стрелка/номер стыкуются ровно.
	var g: float = Geom.SCH_GRID
	end_w = Vector2(snappedf(end_w.x, g), snappedf(end_w.y, g))
	if end_w.distance_to(tip_w) < g * 0.5:
		end_w = tip_w + n_w * STUB_LEN
	var along: Vector2 = end_w - tip_w
	if along.length_squared() < 1.0e-8:
		along = n_w
	else:
		along = along.normalized()
	return {
		"pts": PackedVector2Array([tip_w, end_w]),
		"tip": end_w,
		"dir": along,
	}


## Части для отрисовки: два хвоста по нормалям портов (не по трассе).
static func visual_parts(circuit, wire, pts: PackedVector2Array = PackedVector2Array()) -> Array:
	if wire == null:
		return []
	if not is_schematic_cut(wire):
		if pts.size() >= 2:
			return [pts]
		return []
	var parts: Array = []
	var sa: Dictionary = port_stub(circuit, wire, true)
	var sb: Dictionary = port_stub(circuit, wire, false)
	if not sa.is_empty():
		parts.append(sa["pts"] as PackedVector2Array)
	if not sb.is_empty():
		parts.append(sb["pts"] as PackedVector2Array)
	# Fallback: если порты не найдены — короткие хвосты по трассе.
	if parts.is_empty() and pts.size() >= 2:
		var a: PackedVector2Array = stub_prefix(pts, STUB_LEN)
		var b: PackedVector2Array = stub_suffix(pts, STUB_LEN)
		if a.size() >= 2:
			parts.append(a)
		if b.size() >= 2:
			parts.append(b)
	return parts


## Свободный конец хвоста + направление «от порта».
static func break_tip(circuit, wire, at_start: bool, pts: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var stub: Dictionary = port_stub(circuit, wire, at_start)
	if not stub.is_empty():
		return {"pos": stub["tip"] as Vector2, "dir": stub["dir"] as Vector2}
	# Fallback по трассе.
	var path: PackedVector2Array = stub_prefix(pts, STUB_LEN) if at_start else stub_suffix(pts, STUB_LEN)
	if path.size() < 2:
		return {}
	var tip: Vector2
	var along: Vector2
	if at_start:
		tip = path[path.size() - 1]
		along = path[path.size() - 1] - path[0]
	else:
		tip = path[0]
		along = path[0] - path[path.size() - 1]
	if along.length_squared() < 1.0e-8:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	return {"pos": tip, "dir": along}


static func stub_prefix(pts: PackedVector2Array, length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2 or length <= 0.0:
		return out
	out.append(pts[0])
	var left: float = length
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 1.0e-6:
			continue
		if seg >= left:
			out.append(a.lerp(b, left / seg))
			return out
		out.append(b)
		left -= seg
	return out


static func stub_suffix(pts: PackedVector2Array, length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2 or length <= 0.0:
		return out
	var rev := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		rev.append(pts[i])
	var pref: PackedVector2Array = stub_prefix(rev, length)
	for i in range(pref.size() - 1, -1, -1):
		out.append(pref[i])
	return out
