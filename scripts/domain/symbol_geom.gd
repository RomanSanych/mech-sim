class_name SymbolGeom
extends RefCounted
## УГО цилиндра: топология ISO 1219-1, рабочий масштаб под конфигуратор (как собранный AS).
## Layout/hit: data/symbols/verin_default.json

const Strokes = preload("res://scripts/domain/symbol_strokes.gd")
const ElectroSym = preload("res://scripts/domain/electro_symbols.gd")
const SensorSig = preload("res://scripts/domain/sensor_signal.gd")
const UiTheme = preload("res://scripts/app/ui_theme.gd")

const INK := Color(0.08, 0.11, 0.15)
const PAPER := Color(0.890, 0.914, 0.925)
## Временная подмена тёмных штрихов (превью библиотеки на тёмном фоне).
static var _ink_override := Color(0, 0, 0, 0)
## Компактное превью библиотеки: без тега и подписей портов.
static var _library_preview := false
## Масштаб transform превью (width в local → px = width * scale).
static var _library_scale := 1.0
## SCH_GRID=10; УГО дросселя было ~2 клетки → ×1.5 ≈ ближе к 3.
const THROTTLE_UGO_SCALE := 1.5
## КП: квадрат DXF ±10 → ×2 = ±20 (= VALVE_SQ/2), как клетка распреда.
const RELIEF_UGO_SCALE := 2.0
## Контекст слоя схемы: без set_meta на рисуемом CanvasItem (иначе повторный _draw).
static var _sch_ctx_active: bool = false
static var _sch_ctx_zoom: float = 1.0
static var _sch_ctx_pan: Vector2 = Vector2.ZERO
static var _sch_ctx_world_xform: bool = false
static var _sch_ctx_wires: Array = []
static var _sch_ctx_p_max: float = 0.0
static var _sch_ctx_label_boxes: Array = []
static var _sch_ctx_circuit = null


static func begin_sch_layer_draw(
	p_zoom: float, p_pan: Vector2, world_xform: bool, wires: Array, p_max_over: float,
	p_circuit = null
) -> void:
	_sch_ctx_active = true
	_sch_ctx_zoom = p_zoom
	_sch_ctx_pan = p_pan
	_sch_ctx_world_xform = world_xform
	_sch_ctx_wires = wires
	_sch_ctx_p_max = p_max_over
	_sch_ctx_circuit = p_circuit
	_sch_ctx_label_boxes = []


static func end_sch_layer_draw() -> void:
	_sch_ctx_active = false
	_sch_ctx_wires = []
	_sch_ctx_label_boxes = []
	_sch_ctx_circuit = null


static func _sch_has_zoom(ci: CanvasItem) -> bool:
	return _sch_ctx_active or (ci != null and ci.has_meta("sch_zoom"))


static func _sch_zoom_of(ci: CanvasItem) -> float:
	if _sch_ctx_active:
		return _sch_ctx_zoom
	if ci != null and ci.has_meta("sch_zoom"):
		return float(ci.get_meta("sch_zoom"))
	return 1.0


static func _sch_pan_of(ci: CanvasItem) -> Vector2:
	if _sch_ctx_active:
		return _sch_ctx_pan
	if ci != null and ci.has_meta("sch_pan"):
		return ci.get_meta("sch_pan") as Vector2
	return Vector2.ZERO


static func _sch_world_xform_of(ci: CanvasItem) -> bool:
	if _sch_ctx_active:
		return _sch_ctx_world_xform
	return ci != null and ci.has_meta("sch_world_xform") and bool(ci.get_meta("sch_world_xform"))


static func _sch_p_max_of(ci: CanvasItem) -> float:
	if _sch_ctx_active:
		return _sch_ctx_p_max
	if ci != null and ci.has_meta("sch_p_max_over"):
		return float(ci.get_meta("sch_p_max_over"))
	return 0.0


static func _sch_wires_of(ci: CanvasItem) -> Array:
	if _sch_ctx_active:
		return _sch_ctx_wires
	if ci != null and ci.has_meta("sch_wires"):
		return ci.get_meta("sch_wires") as Array
	return []


static func begin_preview_ink(color: Color = Color(0.94, 0.96, 0.98)) -> void:
	_ink_override = color


static func end_preview_ink() -> void:
	_ink_override = Color(0, 0, 0, 0)


## Цвет выделения/наведения УГО — как у выбранной жилы (не рамка).
static func selection_ink(dark: bool = false) -> Color:
	return Color(0.45, 0.72, 1.0) if dark else Color(0.10, 0.38, 0.82)


## World-rect зоны параметризации (для clip-подсветки части).
static func part_zone_world(el, part_id: String) -> Rect2:
	if el == null or part_id == "":
		return Rect2()
	for zone in part_zones(el):
		if str(zone.get("id", "")) != part_id:
			continue
		var zr: Rect2 = zone["rect"]
		return _local_rect_world(el, zr)
	return Rect2()


static func begin_library_preview(ink_color: Color, draw_scale: float = 1.0) -> void:
	_library_preview = true
	_library_scale = maxf(draw_scale, 0.05)
	begin_preview_ink(ink_color)


static func end_library_preview() -> void:
	_library_preview = false
	_library_scale = 1.0
	end_preview_ink()


static func library_bounds(el) -> Rect2:
	# Локальный bbox символа для вписывания в ячейку библиотеки.
	if el.kind == "source":
		var x0 := SRC_TIP_X - SRC_DEPTH - 4.0
		return Rect2(x0, -SRC_HALF_H - 4.0, SRC_DEPTH + 8.0, SRC_HALF_H * 2.0 + 8.0)
	if el.kind == "electro":
		return ElectroSym.local_bounds(el).grow(4.0)
	if el.kind == "coil":
		return _coil_local_bounds().grow(4.0)
	if el.kind == "valve":
		var n := _valve_positions_count(el)
		var body_w := float(n) * VALVE_SQ
		var slide := _valve_slide_x(el)
		var x0 := -body_w * 0.5 + slide - VALVE_OP - 2.0
		var x1 := body_w * 0.5 + slide + VALVE_OP + 2.0
		# Порты якоря без slide — расширяем по ним.
		x0 = minf(x0, -body_w * 0.5 - 6.0)
		x1 = maxf(x1, body_w * 0.5 + 6.0)
		var top := VALVE_SQ * 0.5 + (16.0 if _valve_has_top_ports(el) else 6.0)
		var bot := VALVE_SQ * 0.5 + 34.0
		return Rect2(x0, -top, x1 - x0, top + bot)
	if el.kind == "accessory":
		return _accessory_local_bounds(el).grow(4.0)
	if el.kind == "rail":
		return Rail2D.local_bounds(el).grow(6.0)
	if el.kind == "rotary_cylinder":
		return _rotary_local_bounds().grow(4.0)
	if el.kind == "air_motor":
		return _air_motor_local_bounds().grow(4.0)
	if el.kind == "sensor":
		return _sensor_local_bounds(el).grow(4.0)
	var left := BODY_L - 8.0
	var right := ROD_X + 8.0 if _mode(el) != "rodless" else BODY_R + 8.0
	return Rect2(left, BODY_T - 20.0, right - left, (BODY_B + PORT_DROP + 6.0) - (BODY_T - 20.0))


static func ink() -> Color:
	return _ink_override if _ink_override.a > 0.01 else INK


## Домен порта для цвета точки соединения (как Circuit.port_domain).
static func port_domain(el, port_name: String) -> String:
	if el == null:
		return "pneumatic"
	if str(el.kind) == "rail":
		return "electric" if str(el.rail_domain) == "electric" else "pneumatic"
	var p := str(port_name)
	# Оптоволокно: чёрный кабель как трубка (не электро в щите).
	if str(el.kind) == "opto_tip":
		return "optic"
	if p.begins_with("OPT") or p.begins_with("opt"):
		return "optic"
	# Реле давления / ПИП: пневмопорт P / 1 — не электро.
	if str(el.kind) == "sensor":
		var scls: String = str(el.sensor_class)
		if scls == "pressure_switch" or scls == "pressure_tx":
			if p in ["P", "1", "p"]:
				return "pneumatic"
			return "electric"
	if str(el.kind) == "coil" or str(el.kind) == "electro" or str(el.kind) == "sensor":
		return "electric"
	# Не эвристика по «O…»: порт источника «out» иначе красится как оптика (фиолетовый).
	# Электро клеммы A1/A2/… — не одиночная «a» (пневмопорт ППЦ / аксессуаров).
	if p.length() >= 2 and (p.begins_with("A") or p.begins_with("a")):
		return "electric"
	if p.begins_with("H") or p.begins_with("h"):
		return "hydraulic"
	return "pneumatic"


static func port_domain_color(domain: String) -> Color:
	match str(domain):
		"electric":
			return Color(0.95, 1.0, 0.12) # неоново-жёлтый
		"hydraulic":
			return Color(0.06, 0.06, 0.08) # чёрный
		"optic":
			return Color(0.58, 0.22, 0.92) # фиолетовый
		_:
			# На тёмном холсте чуть ярче, иначе синие точки/хвосты тонут.
			return Color(0.35, 0.68, 0.98) if UiTheme.dark else Color(0.0, 0.42, 0.78)


## Точка соединения: маленькая заливка + граница того же цвета. Только если visible.
static func _draw_port_marker(ci: CanvasItem, el, tip_local: Vector2, domain: String, visible: bool) -> void:
	if not visible or _library_preview:
		return
	var col := port_domain_color(domain)
	var p := to_world(el, tip_local)
	ci.draw_circle(p, 2.15, col)
	ci.draw_arc(p, 2.85, 0.0, TAU, 18, col, 1.35, true)


static func _resolve_ink(color: Color) -> Color:
	if _ink_override.a <= 0.01:
		return color
	# Тёмные штрихи/подписи → светлые; акценты и заливки не трогаем.
	var lum := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	if lum < 0.38 and color.a > 0.01:
		return Color(_ink_override.r, _ink_override.g, _ink_override.b, color.a)
	return color
const M_PER_PX := 0.004
const CUSH_ARM := 14.0

const BODY_L := -80.0
const BODY_R := 80.0
const BODY_T := -36.0
const BODY_B := 36.0
const ROD_X := 132.0
const PISTON_A := -27.0
const PISTON_B := 50.0
const PISTON_GAP := 28.0
# Tip портов на SCH_GRID (было −71 / Y=72 → микроизгиб провода у cap).
const PORT_CAP_X := -70.0
const PORT_ROD_X := 70.0
const PORT_DROP := 34.0 # BODY_B(36)+34 = 70
const ROD_GAP := 9.0
## Клетка позиции — квадрат. Катушка ВНИЗУ; пилот — треугольник в такой же рамке.
const VALVE_SQ := 40.0
const VALVE_M := VALVE_SQ * 0.5
const VALVE_SOL_H := VALVE_SQ * 0.5
const VALVE_SOL_W := VALVE_SQ * 0.85
const VALVE_PILOT_W := VALVE_SOL_W
const VALVE_OP_H := VALVE_SOL_H
const VALVE_SPR_W := VALVE_SQ * 0.69
## Запас по ширине: катушка/пилот одной ширины; стек solenoid_pilot — две высоты.
const VALVE_OP := VALVE_SOL_W + 8.0
## Шаг схемы: snap элементов/проводов, сетка и оси портов УГО.
const SCH_GRID := 10.0


## Катушка (отдельный эл. элемент): прямоугольник + выводы + пилот-треугольники.
const COIL_RW := 28.0
const COIL_RH := 16.0
const COIL_LEAD := 12.0
const COIL_PILOT_GAP := 10.0
const COIL_PILOT_W := 14.0
const COIL_PILOT_H := 22.0
const COIL_STEM := 6.0
## Источник энергии (ГОСТ 2.780 / ISO 1219): компактный незалитый треугольник.
const SRC_TIP_X := 10.0
const SRC_DEPTH := 24.0
const SRC_HALF_H := 13.5


static func ports(el) -> Array:
	if el.kind == "source":
		return [{"name": "out", "local": Vector2(SRC_TIP_X, 0), "normal": Vector2.RIGHT}]
	if el.kind == "electro":
		return ElectroSym.ports(el)
	if el.kind == "sensor":
		return _sensor_ports(el)
	if el.kind == "opto_tip":
		return _opto_tip_ports(el)
	if el.kind == "coil":
		var y_top := -COIL_RH * 0.5 - COIL_LEAD
		var y_bot := COIL_RH * 0.5 + COIL_LEAD
		return [
			{"name": "A1", "local": Vector2(0.0, y_top), "normal": Vector2.UP},
			{"name": "A2", "local": Vector2(0.0, y_bot), "normal": Vector2.DOWN},
		]
	if el.kind == "junction":
		return _junction_ports(el)
	if el.kind == "accessory":
		return _accessory_ports(el)
	if el.kind == "rail":
		return Rail2D.ports(el)
	if el.kind == "valve":
		return _valve_ports(el)
	if el.kind == "rotary_cylinder":
		var data_r: Dictionary = _rotary_cylinder_ugo_data()
		# DXF/AS: вертикальные хвосты под диаметром; tips на SCH_GRID, нормаль вниз.
		var pa: Array = data_r.get("port_a", [-SCH_GRID, SCH_GRID * 2.0]) as Array
		var pb: Array = data_r.get("port_b", [SCH_GRID, SCH_GRID * 2.0]) as Array
		var ax: float = float(pa[0]) if pa.size() >= 1 else -SCH_GRID
		var ay: float = float(pa[1]) if pa.size() >= 2 else SCH_GRID * 2.0
		var bx: float = float(pb[0]) if pb.size() >= 1 else SCH_GRID
		var by: float = float(pb[1]) if pb.size() >= 2 else SCH_GRID * 2.0
		var nrm := Vector2.DOWN
		var pn: Array = data_r.get("port_normal", [0.0, 1.0]) as Array
		if pn.size() >= 2:
			nrm = Vector2(float(pn[0]), float(pn[1]))
			if nrm.length_squared() < 1.0e-8:
				nrm = Vector2.DOWN
			else:
				nrm = nrm.normalized()
		return [
			{"name": "a", "local": Vector2(ax, ay), "normal": nrm},
			{"name": "b", "local": Vector2(bx, by), "normal": nrm},
		]
	if el.kind == "air_motor":
		# Реверсивный ISO: tips ±40 на оси центра круга (SCH_GRID); вал вверх.
		var tip_m: float = SCH_GRID * 4.0
		var MotorCat = preload("res://scripts/domain/motor_catalog.gd")
		var in_muff: bool = MotorCat.port_is_muffler(el, "in")
		var exh_muff: bool = MotorCat.port_is_muffler(el, "exhaust")
		return [
			{
				"name": "in",
				"local": Vector2(-tip_m, 0.0),
				"normal": Vector2.LEFT,
				"muffler": in_muff,
			},
			{
				"name": "exhaust",
				"local": Vector2(tip_m, 0.0),
				"normal": Vector2.RIGHT,
				"muffler": exh_muff,
			},
		]
	var list: Array = []
	if el.action != "spring_extend" and _port_style(el, "cap") == "connect":
		list.append({
			"name": "cap",
			"local": Vector2(PORT_CAP_X, BODY_B + PORT_DROP),
			"normal": Vector2.DOWN,
		})
	if el.action != "spring_return" and _port_style(el, "rod") == "connect":
		list.append({
			"name": "rod",
			"local": Vector2(PORT_ROD_X, BODY_B + PORT_DROP),
			"normal": Vector2.DOWN,
		})
	# NC-зажим штока: пилотный порт разжима (пневматика).
	if str(el.get("brake") if el.get("brake") != null else "none") == "nc" and _mode(el) != "rodless":
		var bl: Dictionary = _brake_layout()
		list.append({
			"name": "brake",
			"local": bl["port"],
			"normal": Vector2.RIGHT,
		})
	return list


static func port_by_name(el, port_name: String) -> Dictionary:
	for port in ports(el):
		var item: Dictionary = port
		if str(item["name"]) == port_name:
			return item
	return {}


static func to_world(el, local: Vector2) -> Vector2:
	return el.position + local.rotated(float(el.rotation_quad) * PI * 0.5)


static func to_local(el, world: Vector2) -> Vector2:
	return (world - el.position).rotated(-float(el.rotation_quad) * PI * 0.5)


static func piston_x(el) -> float:
	Strokes.ensure_loaded()
	var pa: float = Strokes.layout("piston_a", PISTON_A)
	var pb: float = Strokes.layout("piston_b", PISTON_B)
	var span := maxf(el.stroke_mm, 1.0)
	var t := clampf(el.x * 1000.0 / span, 0.0, 1.0)
	return lerpf(pa, pb, t)


static func polyline(a_el, a_port: String, b_el, b_port: String, joints: Array) -> PackedVector2Array:
	var pa := port_by_name(a_el, a_port)
	var pb := port_by_name(b_el, b_port)
	if pa.is_empty() or pb.is_empty():
		return PackedVector2Array()
	var a: Vector2 = to_world(a_el, pa["local"])
	var b: Vector2 = to_world(b_el, pb["local"])
	if joints.is_empty():
		var an: Vector2 = pa["normal"].rotated(float(a_el.rotation_quad) * PI * 0.5)
		var bn: Vector2 = pb["normal"].rotated(float(b_el.rotation_quad) * PI * 0.5)
		# Электрика: короткий отросток — иначе «голые» хвосты после пина УГО.
		var stub: float = 4.0 if port_domain(a_el, a_port) == "electric" and port_domain(b_el, b_port) == "electric" else SCH_GRID * 3.0
		return _shortest_ortho_route(a, an, b, bn, stub)
	var seq := PackedVector2Array()
	seq.append(a)
	for joint in joints:
		seq.append(joint)
	seq.append(b)
	# Суставы могли остаться с реверсом/лишними углами после резинки — схлопнуть до ortho.
	return simplify_ortho_path(_dedupe(_ortho(seq)))


## Кратчайший ортогональный путь (Г/Z) с короткими отростками от портов.
static func _shortest_ortho_route(a: Vector2, an: Vector2, b: Vector2, bn: Vector2, stub: float = SCH_GRID * 2.0) -> PackedVector2Array:
	# stub кратен сетке; конец отростка — на узле сетки (без микроизломов). stub≤0 → tip↔tip.
	var a2: Vector2 = a
	var b2: Vector2 = b
	if stub > 0.01:
		var stub_g: float = maxf(roundf(stub / SCH_GRID) * SCH_GRID, SCH_GRID)
		a2 = _stub_end_on_grid(a, an, stub_g)
		b2 = _stub_end_on_grid(b, bn, stub_g)
	var via_h := _dedupe(_ortho(PackedVector2Array([a, a2, Vector2(b2.x, a2.y), b2, b])))
	var via_v := _dedupe(_ortho(PackedVector2Array([a, a2, Vector2(a2.x, b2.y), b2, b])))
	var lh: float = path_length_px(via_h)
	var lv: float = path_length_px(via_v)
	# Порт B вверх/вниз: всегда via_v, если не заметно длиннее (иначе режем золотник).
	if absf(bn.y) > absf(bn.x) and lv <= lh + SCH_GRID * 8.0:
		return via_v
	if absf(bn.x) > absf(bn.y) and lh <= lv + SCH_GRID * 8.0:
		return via_h
	if lv + 0.01 < lh:
		return via_v
	return via_h


static func _stub_end_on_grid(tip: Vector2, normal: Vector2, stub: float) -> Vector2:
	var n: Vector2 = normal
	if absf(n.x) >= absf(n.y):
		n = Vector2(signf(n.x) if absf(n.x) > 1.0e-6 else 1.0, 0.0)
		var x: float = tip.x + n.x * stub
		x = ceilf(x / SCH_GRID) * SCH_GRID if n.x > 0.0 else floorf(x / SCH_GRID) * SCH_GRID
		if absf(x - tip.x) < stub - 0.01:
			x += n.x * SCH_GRID
		return Vector2(x, tip.y)
	n = Vector2(0.0, signf(n.y) if absf(n.y) > 1.0e-6 else 1.0)
	var y: float = tip.y + n.y * stub
	y = ceilf(y / SCH_GRID) * SCH_GRID if n.y > 0.0 else floorf(y / SCH_GRID) * SCH_GRID
	if absf(y - tip.y) < stub - 0.01:
		y += n.y * SCH_GRID
	return Vector2(tip.x, y)


static func _ortho(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size()):
		var prev: Vector2 = out[out.size() - 1]
		var cur: Vector2 = pts[i]
		if absf(prev.x - cur.x) > 0.75 and absf(prev.y - cur.y) > 0.75:
			out.append(Vector2(cur.x, prev.y))
		if out[out.size() - 1].distance_to(cur) > 0.5:
			out.append(cur)
	return out


static func _dedupe(pts: PackedVector2Array) -> PackedVector2Array:
	var clean := PackedVector2Array()
	for point in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(point) > 0.5:
			clean.append(point)
	return clean


## Убрать коллинеарности и мелкие П/U-шпоры (≤1.5 клетки) после A*/ортогонали.
static func simplify_ortho_path(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var g: float = SCH_GRID
	var cur: PackedVector2Array = _dedupe(pts)
	for _pass in 6:
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		var i: int = 1
		var changed: bool = false
		while i < cur.size() - 1:
			var a: Vector2 = nxt[nxt.size() - 1]
			var b: Vector2 = cur[i]
			var c: Vector2 = cur[i + 1]
			var ab: Vector2 = b - a
			var bc: Vector2 = c - b
			# Коллинеарные H/V в одном направлении — выкинуть b.
			# Разворот 180° (dot≤0) нельзя схлопывать как «коллинеар» — иначе режется угол и остаётся диагональ.
			var col_hv: bool = (absf(ab.x) < 0.51 and absf(bc.x) < 0.51) \
				or (absf(ab.y) < 0.51 and absf(bc.y) < 0.51)
			if col_hv and ab.dot(bc) > 0.0:
				changed = true
				i += 1
				continue
			# Разворот 180° на одной оси — выкинуть b (a→c остаётся ортогональным).
			var d_ab: float = ab.length()
			var d_bc: float = bc.length()
			if col_hv and ab.dot(bc) < -0.01:
				changed = true
				i += 1
				continue
			# Микро-лестница A–B–C–D (проступь 1 клетка): схлопнуть; длинные плечи тоже.
			if i + 2 < cur.size():
				var d: Vector2 = cur[i + 2]
				var cd: Vector2 = d - c
				var d_cd: float = cd.length()
				var ab_h: bool = absf(ab.y) < 0.51 and absf(ab.x) >= 0.51
				var bc_h: bool = absf(bc.y) < 0.51 and absf(bc.x) >= 0.51
				var cd_h: bool = absf(cd.y) < 0.51 and absf(cd.x) >= 0.51
				# Только строго осевые сегменты — иначе схлоп даёт диагональ.
				var ab_v: bool = absf(ab.x) < 0.51 and absf(ab.y) >= 0.51
				var bc_v: bool = absf(bc.x) < 0.51 and absf(bc.y) >= 0.51
				var cd_v: bool = absf(cd.x) < 0.51 and absf(cd.y) >= 0.51
				var ab_axis: bool = ab_h or ab_v
				var bc_axis: bool = bc_h or bc_v
				var cd_axis: bool = cd_h or cd_v
				if ab_axis and bc_axis and cd_axis and ab_h != bc_h and ab_h == cd_h \
						and d_bc <= g * 1.55 and ab.dot(cd) > 0.0:
					# Короткий проступень: один угол. Длинный — выпрямление по оси большего плеча.
					if d_ab <= g * 2.6 and d_cd <= g * 2.6:
						var corner: Vector2 = Vector2(d.x, a.y) if ab_h else Vector2(a.x, d.y)
						if corner.distance_to(a) > 0.5:
							nxt.append(corner)
						changed = true
						i += 2
						continue
					var end_pt: Vector2
					if ab_h:
						var y_keep: float = a.y if d_ab >= d_cd else d.y
						end_pt = Vector2(d.x, y_keep)
					else:
						var x_keep: float = a.x if d_ab >= d_cd else d.x
						end_pt = Vector2(x_keep, d.y)
					if end_pt.distance_to(a) > 0.5:
						nxt.append(end_pt)
					changed = true
					i += 3
					continue
			nxt.append(b)
			i += 1
		nxt.append(cur[cur.size() - 1])
		# Любой схлоп мог оставить диагональ — вернуть ортогональ.
		nxt = _dedupe(_ortho(nxt))
		if not changed or nxt.size() == cur.size():
			return nxt
		cur = nxt
	return cur


static func path_length_px(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


static func hose_length_m(a_el, a_port: String, b_el, b_port: String, joints: Array) -> float:
	var pixels := path_length_px(polyline(a_el, a_port, b_el, b_port, joints))
	return clampf(pixels * M_PER_PX, 0.2, 12.0)


static func body_hit(el, world: Vector2) -> bool:
	var local := to_local(el, world)
	if el.kind == "source":
		# Треугольник + небольшой inflate — не прямоугольная рамка (углы блокировали подписи).
		return _source_tri_hit(local, 2.0)
	if el.kind == "electro":
		return ElectroSym.local_bounds(el).has_point(local)
	if el.kind == "coil":
		var box := _coil_local_bounds()
		return box.has_point(local)
	if el.kind == "junction":
		return _junction_local_bounds(el).has_point(local)
	if el.kind == "accessory":
		return _accessory_local_bounds(el).has_point(local)
	if el.kind == "rail":
		return Rail2D.hit_body(el, world, 1.0)
	if el.kind == "valve":
		var box := _valve_local_bounds(el)
		return box.has_point(local)
	if el.kind == "rotary_cylinder":
		return _rotary_local_bounds().has_point(local)
	if el.kind == "air_motor":
		return _air_motor_local_bounds().has_point(local)
	if el.kind == "sensor":
		return _sensor_local_bounds(el).has_point(local)
	if el.kind == "opto_tip":
		return _opto_tip_local_bounds().has_point(local)
	var left := BODY_L - (ROD_X - BODY_R) - 8.0 if _mode(el) == "through" else BODY_L - 8.0
	var right := ROD_X + 8.0 if _mode(el) != "rodless" else BODY_R + 8.0
	var top := BODY_T - 34.0
	var bottom := BODY_B + PORT_DROP + 8.0
	return local.x >= left and local.x <= right and local.y >= top and local.y <= bottom


static func port_hit(el, world: Vector2, zoom: float) -> String:
	var radius := 11.0 / maxf(zoom, 0.35)
	var best := ""
	var best_d := radius
	var local := to_local(el, world)
	for port in ports(el):
		var d: float = local.distance_to(port["local"])
		if d <= best_d:
			best_d = d
			best = port["name"]
	return best


## Корпус для обхода трассой: у ПР/отсечного — только клетки золотника (без органов),
## иначе «короткий Г» считает левый орган препятствием и всё равно режет середину.
static func route_body_bounds(el) -> Rect2:
	if el == null:
		return Rect2()
	var is_shut: bool = str(el.kind) == "accessory" \
			and str(el.get("accessory_class") if el.get("accessory_class") != null else "") == "shutoff"
	if str(el.kind) == "valve" or is_shut:
		var n: int = _valve_positions_count(el)
		var body_w: float = float(n) * VALVE_SQ
		var y0: float = -VALVE_SQ * 0.5
		var local_box := Rect2(-body_w * 0.5, y0, body_w, VALVE_SQ)
		var c0: Vector2 = to_world(el, local_box.position)
		var c1: Vector2 = to_world(el, local_box.position + Vector2(local_box.size.x, 0.0))
		var c2: Vector2 = to_world(el, local_box.position + local_box.size)
		var c3: Vector2 = to_world(el, local_box.position + Vector2(0.0, local_box.size.y))
		var box := Rect2(c0, Vector2.ZERO)
		box = box.expand(c1).expand(c2).expand(c3)
		return box.grow(SCH_GRID * 0.4)
	return world_bounds(el).grow(SCH_GRID * 0.25)


static func world_bounds(el) -> Rect2:
	var locals: Array[Vector2] = []
	if el.kind == "source":
		var x0 := SRC_TIP_X - SRC_DEPTH - 2.0
		var x1 := SRC_TIP_X + 4.0
		locals = [Vector2(x0, -SRC_HALF_H - 2.0), Vector2(x1, SRC_HALF_H + 2.0)]
	elif el.kind == "electro":
		var eb := ElectroSym.local_bounds(el)
		locals = [eb.position, eb.position + eb.size]
	elif el.kind == "coil":
		var cb := _coil_local_bounds()
		locals = [cb.position, cb.position + cb.size]
	elif el.kind == "junction":
		var jb := _junction_local_bounds(el)
		locals = [jb.position, jb.position + jb.size]
	elif el.kind == "accessory":
		var ab: Rect2 = _accessory_local_bounds(el)
		locals = [ab.position, ab.position + ab.size]
	elif el.kind == "rail":
		var rb: Rect2 = Rail2D.local_bounds(el)
		locals = [rb.position, rb.position + rb.size]
	elif el.kind == "valve":
		var box := _valve_local_bounds(el)
		locals = [box.position, box.position + box.size]
	elif el.kind == "rotary_cylinder":
		var rb2: Rect2 = _rotary_local_bounds()
		locals = [rb2.position, rb2.position + rb2.size]
	elif el.kind == "air_motor":
		var mb: Rect2 = _air_motor_local_bounds()
		locals = [mb.position, mb.position + mb.size]
	elif el.kind == "sensor":
		var sb: Rect2 = _sensor_local_bounds(el)
		locals = [sb.position, sb.position + sb.size]
	else:
		var left := BODY_L - (ROD_X - BODY_R) - 8.0 if _mode(el) == "through" else BODY_L - 8.0
		var right := ROD_X + 10.0 if _mode(el) != "rodless" else BODY_R + 8.0
		var top := BODY_T - 36.0
		var br := str(el.get("brake") if el.get("brake") != null else "none")
		if br == "nc" and _mode(el) != "rodless":
			var bl: Dictionary = _brake_layout()
			var port_pt: Vector2 = bl["port"]
			right = maxf(right, port_pt.x + 4.0)
			top = minf(top, float(bl["by0"]) - 20.0)
		locals = [Vector2(left, top), Vector2(right, BODY_B + PORT_DROP + 10)]
	var first := to_world(el, locals[0])
	var box := Rect2(first, Vector2.ZERO)
	for corner_l in locals:
		box = box.expand(to_world(el, corner_l))
	var alt_a := Vector2(locals[0].x, locals[1].y)
	var alt_b := Vector2(locals[1].x, locals[0].y)
	box = box.expand(to_world(el, alt_a))
	box = box.expand(to_world(el, alt_b))
	return box.grow(3.0 if el.kind == "valve" else 6.0)


static func draw_element(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	hover_part: String = "", omit_motion: bool = false
) -> void:
	Strokes.ensure_loaded()
	if el.kind == "source":
		_draw_source(ci, el, font, selected, show_values, hover_port)
	elif el.kind == "electro":
		ElectroSym.draw(ci, el, font, selected, hover_port, ink(), to_world, _stroke_w, _stroke_aa, _draw_element_tag, port_domain, _draw_port_marker, hover_part)
	elif el.kind == "coil":
		_draw_coil(ci, el, font, selected, hover_port)
	elif el.kind == "junction":
		_draw_junction(ci, el, font, selected, show_values, hover_port)
	elif el.kind == "accessory":
		_draw_accessory(ci, el, font, selected, show_values, hover_port, omit_motion)
	elif el.kind == "rail":
		_draw_rail(ci, el, font, selected, hover_port)
	elif el.kind == "valve":
		_draw_valve(ci, el, font, selected, show_values, hover_port, hover_part, omit_motion)
	elif el.kind == "rotary_cylinder":
		_draw_rotary_cylinder(ci, el, font, selected, show_values, hover_port, omit_motion)
	elif el.kind == "air_motor":
		_draw_air_motor(ci, el, font, selected, show_values, hover_port, omit_motion)
	elif el.kind == "sensor":
		_draw_sensor(ci, el, font, selected, show_values, hover_port, omit_motion)
	elif el.kind == "opto_tip":
		_draw_opto_tip(ci, el, font, selected, hover_port)
	else:
		_draw_cylinder(ci, el, font, selected, show_values, hover_port, hover_part, omit_motion)


## Движущиеся части ПЦ (поршень/шток/демпферы) — для отдельного Anim-слоя.
static func draw_cylinder_motion(ci: CanvasItem, el) -> void:
	if el == null or str(el.kind) != "cylinder":
		return
	Strokes.ensure_loaded()
	var px := piston_x(el)
	_draw_cylinder_pressure_fills(ci, el, px)
	var rod_mode := _mode(el)
	var spring := _spring_side(el)
	if spring == "rod" or spring == "both":
		_chamber_spring(ci, el, px + 4.0, BODY_R - 4.0)
	if spring == "cap" or spring == "both":
		_chamber_spring(ci, el, BODY_L + 4.0, px - PISTON_GAP - 4.0)
	if rod_mode == "rodless":
		_draw_carriage(ci, el)
	else:
		var rod_from := px
		if _cushion_kind(el, false) != "none":
			rod_from = px + CUSH_ARM
		_rod(ci, el, rod_from, ROD_X)
		if rod_mode == "through":
			var left_tip := BODY_L - (ROD_X - BODY_R)
			var left_from := px - PISTON_GAP
			if _cushion_kind(el, true) != "none":
				left_from = px - PISTON_GAP - CUSH_ARM
			_rod(ci, el, left_from, left_tip)
	_draw_piston(ci, el, px)
	_draw_cushions(ci, el, px)


## Золотник + органы ПР (порты остаются на shell). Также отсечной (accessory shutoff).
static func draw_valve_motion(ci: CanvasItem, el, font: Font) -> void:
	if el == null:
		return
	var is_shut: bool = str(el.kind) == "accessory" \
			and str(el.get("accessory_class") if el.get("accessory_class") != null else "") == "shutoff"
	if str(el.kind) != "valve" and not is_shut:
		return
	Strokes.ensure_loaded()
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var y0 := -VALVE_SQ * 0.5
	var y1 := VALVE_SQ * 0.5
	var slide := _valve_slide_x(el)
	for i in n:
		var xa := x0 + float(i) * VALVE_SQ + slide
		var xb := xa + VALVE_SQ
		_box(ci, el, xa, y0, xb, y1, INK)
		_draw_valve_envelope(ci, el, ValveCat, i, xa, xb, y0, y1)
	_draw_valve_operator(ci, el, str(el.get("op_left") if el.get("op_left") != null else "spring"), x0 - VALVE_OP + slide, x0 + slide, y0, y1, true, font)
	_draw_valve_operator(ci, el, str(el.get("op_right") if el.get("op_right") != null else "spring"), x0 + body_w + slide, x0 + body_w + VALVE_OP + slide, y0, y1, false, font)


## Только органы распределителя (для чёрной отрисовки поверх серого корпуса в Run).
static func draw_valve_operators(ci: CanvasItem, el, font: Font) -> void:
	if el == null or str(el.kind) != "valve":
		return
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var y0 := -VALVE_SQ * 0.5
	var y1 := VALVE_SQ * 0.5
	var slide := _valve_slide_x(el)
	_draw_valve_operator(ci, el, str(el.get("op_left") if el.get("op_left") != null else "spring"), x0 - VALVE_OP + slide, x0 + slide, y0, y1, true, font)
	_draw_valve_operator(ci, el, str(el.get("op_right") if el.get("op_right") != null else "spring"), x0 + body_w + slide, x0 + body_w + VALVE_OP + slide, y0, y1, false, font)


static func electro_group_frame(circuit, group_id: int, exclude_detached: bool = true, exclude_id: int = -1) -> Rect2:
	return ElectroSym.electro_group_frame(circuit, group_id, exclude_detached, exclude_id)


static func draw_electro_group_overlays(ci: CanvasItem, circuit, font: Font, drag_exclude_ids: Array = []) -> void:
	ElectroSym.draw_group_overlays(ci, circuit, font, drag_exclude_ids)


static func _coil_local_bounds() -> Rect2:
	var y0 := -COIL_RH * 0.5 - COIL_LEAD
	var y1 := COIL_RH * 0.5 + COIL_LEAD
	var x0 := -COIL_RW * 0.5
	var x1 := COIL_RW * 0.5 + COIL_PILOT_GAP + COIL_PILOT_W
	var stem_extra := COIL_STEM
	return Rect2(Vector2(x0, y0 - stem_extra), Vector2(x1 - x0, (y1 + stem_extra) - (y0 - stem_extra)))


static func _junction_port_count(el) -> int:
	var style := str(el.get("junction_style") if el.get("junction_style") != null else "tee")
	if style == "adapter":
		return 2
	var n := int(el.get("junction_ports") if el.get("junction_ports") != null else 3)
	return clampi(n, 3, 6)


static func _junction_local_bounds(el) -> Rect2:
	var style := str(el.get("junction_style") if el.get("junction_style") != null else "tee")
	if style == "adapter":
		var tip_a: float = SCH_GRID * 2.0 # 20
		return Rect2(-tip_a - 2.0, -10.0, tip_a * 2.0 + 4.0, 20.0)
	if style == "manifold":
		var n := _junction_port_count(el)
		var w := 18.0 + float(n) * 10.0
		return Rect2(-w * 0.5, -16.0, w, 36.0)
	var tip: float = SCH_GRID * 2.0 # 20 — порты на сетке
	return Rect2(-tip, -tip, tip * 2.0, tip * 2.0)


static func _junction_ports(el) -> Array:
	var style := str(el.get("junction_style") if el.get("junction_style") != null else "tee")
	var n := _junction_port_count(el)
	var out: Array = []
	if style == "adapter":
		# Прямой переходник: tips ±20 на сетке.
		var tip_ad: float = SCH_GRID * 2.0
		return [
			{"name": "1", "local": Vector2(-tip_ad, 0.0), "normal": Vector2.LEFT},
			{"name": "2", "local": Vector2(tip_ad, 0.0), "normal": Vector2.RIGHT},
		]
	if style == "manifold":
		var span := 12.0 * float(maxi(n - 3, 1))
		out.append({"name": "1", "local": Vector2(-span * 0.5 - 14.0, 0.0), "normal": Vector2.LEFT})
		out.append({"name": "2", "local": Vector2(span * 0.5 + 14.0, 0.0), "normal": Vector2.RIGHT})
		var side := n - 2
		for i in side:
			var x := 0.0 if side == 1 else lerpf(-span * 0.5, span * 0.5, float(i) / float(side - 1))
			out.append({"name": str(i + 3), "local": Vector2(x, 16.0), "normal": Vector2.DOWN})
		return out
	if style == "wye":
		# Tips на сетке: (0,20), (−20,−20), (20,−20) при position на клетке.
		return [
			{"name": "1", "local": Vector2(0.0, SCH_GRID * 2.0), "normal": Vector2.DOWN},
			{"name": "2", "local": Vector2(-SCH_GRID * 2.0, -SCH_GRID * 2.0), "normal": Vector2(-0.6, -0.8).normalized()},
			{"name": "3", "local": Vector2(SCH_GRID * 2.0, -SCH_GRID * 2.0), "normal": Vector2(0.6, -0.8).normalized()},
		]
	# tee: tip = 20 (SCH_GRID×2).
	var tip: float = SCH_GRID * 2.0
	return [
		{"name": "1", "local": Vector2(-tip, 0.0), "normal": Vector2.LEFT},
		{"name": "2", "local": Vector2(tip, 0.0), "normal": Vector2.RIGHT},
		{"name": "3", "local": Vector2(0.0, -tip), "normal": Vector2.UP},
	]


## Хвост УГО аксессуара: tip порта на кратной SCH_GRID (элемент на сетке → провод на сетке).
static func _accessory_port_tip(_el = null) -> float:
	return SCH_GRID * 3.0 # 30


static func _accessory_local_bounds(el) -> Rect2:
	var tip: float = _accessory_port_tip(el)
	var pad: float = 4.0
	var cls: String = str(el.accessory_class) if el != null else ""
	if cls in ["throttle", "throttle_fixed"]:
		var s: float = THROTTLE_UGO_SCALE
		var half_h: float = 22.0 * s
		return Rect2(-tip - pad, -half_h, (tip + pad) * 2.0, half_h * 2.0)
	if cls == "reservoir":
		var AccR = preload("res://scripts/domain/accessory_library.gd")
		var n: int = AccR.reservoir_port_count(el) if el != null else 1
		var half_w: float = _reservoir_body_half_w(n)
		var tip_y: float = _reservoir_tip_y()
		var ry: float = _reservoir_body_ry()
		return Rect2(-half_w - pad, tip_y - pad, (half_w + pad) * 2.0, -tip_y + ry + pad)
	if cls == "regulator":
		# DXF: tips ±30; пружина/выхлоп вверх (~−41), канал LT3 вниз (~+22).
		return Rect2(-tip - pad, -44.0 - pad, (tip + pad) * 2.0, 44.0 + 26.0 + pad * 2.0)
	if cls == "shuttle" or cls == "and_valve":
		# Tips ±30 по X и ±30 по Y (порт 3).
		return Rect2(-tip - pad, -tip - pad, (tip + pad) * 2.0, (tip + pad) * 2.0)
	if cls == "shutoff":
		return _valve_local_bounds(el)
	if cls == "quick_exhaust":
		# 1/3 по X ±30, 2 вверх −30; глушитель на 3 чуть шире.
		return Rect2(-tip - pad, -tip - pad, (tip + pad) * 2.0 + 4.0, (tip + pad) * 2.0)
	if cls == "relief":
		# Квадрат ±20 (как VALVE_SQ); пружина сверху ~×2; tips ±30.
		var rs: float = RELIEF_UGO_SCALE
		return Rect2(-tip - pad, -12.0 * rs - pad, (tip + pad) * 2.0, 12.0 * rs + 28.0 * rs + pad * 2.0)
	if cls in ["throttle_check", "throttle_check_fixed"]:
		# DXF: линия на y=0, обводной КО снизу (~y +22).
		return Rect2(-tip - pad, -16.0 - pad, (tip + pad) * 2.0, 16.0 + 28.0 + pad * 2.0)
	return Rect2(-tip - pad, -22.0, (tip + pad) * 2.0, 44.0)


## Сужение дросселя по DXF (Проект1_Схема1): после поворота вертикального УГО
## на горизонтальные порты — дуги сверху/снизу линии (не )( слева/справа).
static var _throttle_ugo: Dictionary = {}
## Обратный клапан: DXF CCW90, треугольник=седло=порт1 слева; пружина справа.
static var _check_ugo: Dictionary = {}
## Редуктор: DXF Проект1_Схема1, tips ±30, пунктир = канал сброса → треугольник выхлопа.
static var _regulator_ugo: Dictionary = {}
## Клапан «ИЛИ»: DXF Проект1_Схема1 (слева без пружины).
static var _shuttle_ugo: Dictionary = {}
## Клапан «И»: DXF Проект1_Схема1 (две черты).
static var _and_ugo: Dictionary = {}
## Быстрый выхлоп: DXF Проект1_Схема1.
static var _quick_exhaust_ugo: Dictionary = {}
## Предохранительный клапан: DXF Проект1_Схема1.
static var _relief_ugo: Dictionary = {}
## Поворотный ПЦ (рейка–шестерня): DXF Проект1_Схема1.
static var _rotary_cylinder_ugo: Dictionary = {}
## Дроссель с ОК: регулируемый / фиксированный (DXF Проект1_Схема1).
static var _throttle_check_ugo: Dictionary = {}
static var _throttle_check_fixed_ugo: Dictionary = {}


static func _throttle_ugo_data() -> Dictionary:
	if not _throttle_ugo.is_empty():
		return _throttle_ugo
	var path := "res://data/symbols/throttle_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_throttle_ugo = parsed
	return _throttle_ugo


static func _check_ugo_data() -> Dictionary:
	if not _check_ugo.is_empty():
		return _check_ugo
	var path := "res://data/symbols/check_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_check_ugo = parsed
	return _check_ugo


static func _regulator_ugo_data() -> Dictionary:
	# Всегда с диска — правки JSON без перезапуска редактора.
	var path := "res://data/symbols/regulator_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_regulator_ugo = parsed
			return _regulator_ugo
	return _regulator_ugo


static func _shuttle_ugo_data() -> Dictionary:
	var path := "res://data/symbols/shuttle_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_shuttle_ugo = parsed
			return _shuttle_ugo
	return _shuttle_ugo


static func _and_ugo_data() -> Dictionary:
	var path := "res://data/symbols/and_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_and_ugo = parsed
			return _and_ugo
	return _and_ugo


static func _quick_exhaust_ugo_data() -> Dictionary:
	var path := "res://data/symbols/quick_exhaust_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_quick_exhaust_ugo = parsed
			return _quick_exhaust_ugo
	return _quick_exhaust_ugo


static func _relief_ugo_data() -> Dictionary:
	var path := "res://data/symbols/relief_ugo.json"
	# С диска — правки JSON без перезапуска.
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_relief_ugo = parsed
			return _relief_ugo
	return _relief_ugo


static func _rotary_cylinder_ugo_data() -> Dictionary:
	var path := "res://data/symbols/rotary_cylinder_ugo.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_rotary_cylinder_ugo = parsed
			return _rotary_cylinder_ugo
	return _rotary_cylinder_ugo


static func _rotary_local_bounds() -> Rect2:
	# Порты вниз (tips y=+20); вал до y≈−28; полукруг до y≈−22.
	return Rect2(-20.0, -32.0, 40.0, 56.0)


static func _air_motor_local_bounds() -> Rect2:
	# Круг r≈25; tips ±40 на оси центра; вал вверх (×1.3 к прежнему).
	return Rect2(-44.0, -40.0, 88.0, 70.0)


static func _draw_air_motor(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	omit_motion: bool = false
) -> void:
	var ink_c: Color = ink()
	var sw: float = _stroke_w(1.75)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.75, _sch_zoom_of(ci))
	# tip ±40 (=4×SCH_GRID); круг и треугольники ×1.3; порты по диаметру через центр.
	var r: float = 24.8
	var tip: float = SCH_GRID * 4.0
	var c0: Vector2 = to_world(el, Vector2.ZERO)
	ci.draw_arc(c0, r, 0.0, TAU, 56, ink_c, sw, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(-r, 0.0)), to_world(el, Vector2(-tip, 0.0)), ink_c, sw, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(r, 0.0)), to_world(el, Vector2(tip, 0.0)), ink_c, sw, _stroke_aa())
	_draw_air_motor_triangles(ci, el, ink_c, sw)
	_draw_air_motor_shaft_fixed(ci, el, ink_c, sw)
	for port in ports(el):
		var pname: String = str(port["name"])
		if bool(port.get("muffler", false)):
			var nrm: Vector2 = port["normal"] as Vector2
			_draw_valve_muffler_mark(ci, el, port["local"] as Vector2, nrm)
			continue
		_draw_port_marker(ci, el, port["local"] as Vector2, port_domain(el, pname), hover_port == pname)
	_draw_element_tag(ci, el, font, 12, selected)
	if show_values:
		pass


static func _draw_air_motor_triangles(ci: CanvasItem, el, ink_c: Color, sw: float) -> void:
	# Полые треугольники навстречу на оси портов (центр круга). ×1.3 от DXF-пропорций.
	var ax: float = 8.5
	var bx: float = 22.0
	var hy: float = 7.8
	var r_pts: Array[Vector2] = [
		Vector2(ax, 0.0), Vector2(bx, -hy), Vector2(bx, hy)
	]
	var l_pts: Array[Vector2] = [
		Vector2(-ax, 0.0), Vector2(-bx, -hy), Vector2(-bx, hy)
	]
	for i in 3:
		var j: int = (i + 1) % 3
		ci.draw_line(to_world(el, r_pts[i]), to_world(el, r_pts[j]), ink_c, sw, _stroke_aa())
		ci.draw_line(to_world(el, l_pts[i]), to_world(el, l_pts[j]), ink_c, sw, _stroke_aa())


static func _draw_air_motor_shaft_fixed(ci: CanvasItem, el, ink_c: Color, sw: float) -> void:
	# Вал вверх от круга — неподвижен.
	var hw: float = 3.9
	var y0: float = -24.8
	var y1: float = -36.5
	ci.draw_line(to_world(el, Vector2(-hw, y0)), to_world(el, Vector2(-hw, y1)), ink_c, sw, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(hw, y0)), to_world(el, Vector2(hw, y1)), ink_c, sw, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(-7.8, y1)), to_world(el, Vector2(7.8, y1)), ink_c, sw, _stroke_aa())


## Анимация УГО: дуга-стрелка вокруг вала (сверху), направление по знаку omega.
static func draw_air_motor_motion(ci: CanvasItem, el) -> void:
	if el == null or str(el.kind) != "air_motor":
		return
	var sw: float = _stroke_w(1.8)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.8, _sch_zoom_of(ci))
	var ink_c: Color = ink()
	var omega_raw: float = float(el.omega) if el.get("omega") != null else 0.0
	if absf(omega_raw) < 0.8:
		return
	var sense: float = 1.0 if omega_raw >= 0.0 else -1.0
	var rr: float = 26.0
	var a0: float = deg_to_rad(-155.0)
	var a1: float = deg_to_rad(-25.0)
	if sense < 0.0:
		var tmp: float = a0
		a0 = -PI - a1
		a1 = -PI - tmp
	var pts := PackedVector2Array()
	var n: int = 18
	var pivot := Vector2(0.0, -10.0)
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var ang: float = lerpf(a0, a1, t)
		pts.append(to_world(el, Vector2(cos(ang), sin(ang)) * rr + pivot))
	if pts.size() >= 2:
		ci.draw_polyline(pts, ink_c, sw, _stroke_aa())
	var tip_ang: float = a1
	var tip_c: Vector2 = Vector2(cos(tip_ang), sin(tip_ang)) * rr + pivot
	var tang := Vector2(-sin(tip_ang), cos(tip_ang)) * sense
	var nrm: Vector2 = (tip_c - pivot).normalized()
	var head := PackedVector2Array([
		to_world(el, tip_c),
		to_world(el, tip_c - tang * 6.5 - nrm * 3.0),
		to_world(el, tip_c - tang * 6.5 + nrm * 3.0),
	])
	ci.draw_colored_polygon(head, ink_c)


static func _draw_rotary_cylinder(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	omit_motion: bool = false
) -> void:
	var ink_c: Color = ink()
	_draw_rotary_cylinder_ugo(ci, el, ink_c, omit_motion)
	for port in ports(el):
		var pname: String = str(port["name"])
		var tip_local: Vector2 = port["local"] as Vector2
		_draw_port_marker(ci, el, tip_local, port_domain(el, pname), hover_port == pname)
	_draw_element_tag(ci, el, font, 12, selected)
	if show_values:
		pass


static func _draw_rotary_cylinder_ugo(ci: CanvasItem, el, ink_c: Color, omit_motion: bool = false) -> void:
	var data: Dictionary = _rotary_cylinder_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	for st in data.get("strokes", []) as Array:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	if omit_motion:
		return
	_draw_rotary_shaft_motion(ci, el, ink_c, sw, data)


## Вал УГО: прямоугольник сверху вращается вокруг центра диаметра (0,0).
static func draw_rotary_cylinder_motion(ci: CanvasItem, el) -> void:
	if el == null or str(el.kind) != "rotary_cylinder":
		return
	var data: Dictionary = _rotary_cylinder_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	_draw_rotary_shaft_motion(ci, el, ink(), sw, data)


static func _draw_rotary_shaft_motion(
	ci: CanvasItem, el, ink_c: Color, sw: float, data: Dictionary
) -> void:
	# УГО: от вертикали ±45° — задвинуты (angle=0) вправо, выдвинуты (angle=max) влево.
	var th_max: float = deg_to_rad(float(el.angle_max_deg)) if el.get("angle_max_deg") != null else PI
	th_max = maxf(th_max, 1.0e-6)
	var th: float = clampf(float(el.angle) if el.get("angle") != null else 0.0, 0.0, th_max)
	var pct: float = th / th_max
	var deg_in: float = float(data.get("shaft_in_deg", 45.0))
	var deg_out: float = float(data.get("shaft_out_deg", -45.0))
	var ang: float = deg_to_rad(lerpf(deg_in, deg_out, pct))
	var pivot := Vector2.ZERO
	var piv_raw: Array = data.get("pivot", [0.0, 0.0]) as Array
	if piv_raw.size() >= 2:
		pivot = Vector2(float(piv_raw[0]), float(piv_raw[1]))
	for st in data.get("shaft_strokes", []) as Array:
		if not (st is Array):
			continue
		var poly := PackedVector2Array()
		for p in st as Array:
			if p is Array and p.size() >= 2:
				var loc := Vector2(float(p[0]), float(p[1])) - pivot
				loc = loc.rotated(ang) + pivot
				poly.append(to_world(el, loc))
		if poly.size() >= 2:
			ci.draw_polyline(poly, ink_c, sw, _stroke_aa())


static func _throttle_check_ugo_data(el) -> Dictionary:
	var fixed: bool = str(el.accessory_class) == "throttle_check_fixed" if el != null else false
	var path: String = "res://data/symbols/throttle_check_fixed_ugo.json" if fixed \
			else "res://data/symbols/throttle_check_ugo.json"
	# С диска — правки JSON без перезапуска.
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			if fixed:
				_throttle_check_fixed_ugo = parsed
			else:
				_throttle_check_ugo = parsed
			return parsed
	return _throttle_check_fixed_ugo if fixed else _throttle_check_ugo


## Открытие шара обводного КО (2→1): 0 у седла, 1 открыт.
static func _throttle_check_ball_open(el) -> float:
	if el == null:
		return 0.0
	var press = el.get("port_press")
	var p1: float = 101325.0
	var p2: float = 101325.0
	if press is Dictionary:
		p1 = float((press as Dictionary).get("1", 101325.0))
		p2 = float((press as Dictionary).get("2", 101325.0))
	var crack_bar: float = 0.2
	if el.get("crack_pressure_bar") != null:
		crack_bar = float(el.get("crack_pressure_bar"))
	var crack_pa: float = clampf(crack_bar, 0.01, 5.0) * 1.0e5
	var travel_pa: float = 0.30e5
	return clampf(((p2 - p1) - crack_pa) / travel_pa, 0.0, 1.0)


static func _draw_throttle_check_ugo(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _throttle_check_ugo_data(el)
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var open: float = _throttle_check_ball_open(el)
	# 3D/физика: 2→1 открывает КО. На DXF V седла слева от шара — отход шара +X.
	var dx: float = float(data.get("ball_open_dx", 3.5)) * open
	for st in data.get("strokes", []) as Array:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	for st2 in data.get("arrow_strokes", []) as Array:
		if st2 is Array:
			var ap: PackedVector2Array = _poly_local_to_world(el, st2 as Array)
			if ap.size() >= 2:
				ci.draw_polyline(ap, ink_c, sw, _stroke_aa())
	var circle_raw: Array = data.get("circle", []) as Array
	if circle_raw.size() >= 3:
		var circ := PackedVector2Array()
		for p in circle_raw:
			if p is Array and p.size() >= 2:
				circ.append(to_world(el, Vector2(float(p[0]) + dx, float(p[1]))))
		if circ.size() >= 2:
			ci.draw_polyline(circ, ink_c, sw, _stroke_aa())
	else:
		var cx: float = float(data.get("ball_cx", 0.0)) + dx
		var cy: float = float(data.get("ball_cy", 16.5))
		var br: float = float(data.get("ball_r", 3.2))
		ci.draw_arc(to_world(el, Vector2(cx, cy)), br, 0.0, TAU, 36, ink_c, sw, _stroke_aa())


static func _poly_local_to_world(el, pts_raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts_raw:
		if p is Array and p.size() >= 2:
			out.append(to_world(el, Vector2(float(p[0]), float(p[1]))))
	return out


static func _draw_check_ugo(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _check_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var open: float = clampf(float(el.opening), 0.0, 1.0) if el != null else 0.0
	var dx: float = float(data.get("ball_open_dx", 5.0)) * open
	var ball_r: float = float(data.get("ball_r", 8.0))
	# Статика DXF: треугольник = седло слева (порт 1).
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	# Шарик: отодвигается от треугольника/седла вправо (+X) при открытии.
	var circle_raw: Array = data.get("circle", []) as Array
	if circle_raw.size() >= 3:
		var circ := PackedVector2Array()
		for p in circle_raw:
			if p is Array and p.size() >= 2:
				circ.append(to_world(el, Vector2(float(p[0]) + dx, float(p[1]))))
		if circ.size() >= 2:
			ci.draw_polyline(circ, ink_c, sw, _stroke_aa())
	else:
		ci.draw_arc(to_world(el, Vector2(dx, 0.0)), ball_r, 0.0, TAU, 36, ink_c, sw, _stroke_aa())
	# Пружина за шариком (справа), высота ≈ 2/3 диаметра; сжимается при открытии.
	_draw_check_spring_ugo(ci, el, ink_c, sw, ball_r, dx, data)


## ИЛИ (shuttle): штрихи DXF; шарик по opening (0→седло1, 1→седло2).
## omit_ball — при Run шарик на SchemeAnim (плавно), корпус остаётся на Base.
static func _draw_shuttle_ugo(ci: CanvasItem, el, ink_c: Color, omit_ball: bool = false) -> void:
	var data: Dictionary = _shuttle_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	if omit_ball:
		return
	_draw_shuttle_ball(ci, el, ink_c, sw, data)


static func _shuttle_ball_travel(data: Dictionary) -> float:
	var ball_r: float = float(data.get("ball_r", 4.0))
	var seat_tip: float = float(data.get("seat_tip", 0.0))
	if seat_tip > 1.0:
		# Касание вершины V: центр = tip − r (не пересекать седло).
		return maxf(seat_tip - ball_r, ball_r * 0.5)
	return float(data.get("ball_travel", 5.5))


static func _draw_shuttle_ball(ci: CanvasItem, el, ink_c: Color, sw: float, data: Dictionary) -> void:
	var side: float = clampf(float(el.opening), 0.0, 1.0) if el != null else 0.5
	var travel: float = _shuttle_ball_travel(data)
	var dx: float = lerpf(-travel, travel, side)
	var ball_r: float = float(data.get("ball_r", 4.0))
	var cx0: float = float(data.get("ball_cx0", 0.0))
	var cy0: float = float(data.get("ball_cy0", 0.0))
	var circle_raw: Array = data.get("circle", []) as Array
	if circle_raw.size() >= 3:
		var circ := PackedVector2Array()
		for p in circle_raw:
			if p is Array and p.size() >= 2:
				circ.append(to_world(el, Vector2(float(p[0]) + dx, float(p[1]) + cy0)))
		if circ.size() >= 2:
			ci.draw_polyline(circ, ink_c, sw, _stroke_aa())
	else:
		ci.draw_arc(to_world(el, Vector2(cx0 + dx, cy0)), ball_r, 0.0, TAU, 36, ink_c, sw, _stroke_aa())


## Только шарик ИЛИ — слой SchemeAnim при Run.
static func draw_shuttle_motion(ci: CanvasItem, el) -> void:
	if el == null:
		return
	var data: Dictionary = _shuttle_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	_draw_shuttle_ball(ci, el, ink(), sw, data)


## И (dual-pressure): штрихи DXF 1:1 (две черты внутри прямоугольника).
static func _draw_and_ugo(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _and_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())


## Быстрый выхлоп: штрихи DXF; тарелка/шарик по opening; глушитель на 3 по port_3.
static func _draw_quick_exhaust_ugo(ci: CanvasItem, el, ink_c: Color, omit_ball: bool = false) -> void:
	var data: Dictionary = _quick_exhaust_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	if ValveCat.exhaust_fit(el, "3") == "muffler":
		var muff_raw: Array = data.get("muffler_strokes", []) as Array
		for st2 in muff_raw:
			if st2 is Array:
				var poly_m: PackedVector2Array = _poly_local_to_world(el, st2 as Array)
				if poly_m.size() >= 2:
					ci.draw_polyline(poly_m, ink_c, sw, _stroke_aa())
		# ISO-метка глушителя на tip порта 3 (если штрихов DXF мало).
		if muff_raw.is_empty():
			var tip3 := Vector2(float((data.get("port_3", [30.0, 0.0]) as Array)[0]), 0.0)
			_draw_valve_muffler_mark(ci, el, tip3, Vector2.RIGHT)
	if omit_ball:
		return
	_draw_shuttle_ball(ci, el, ink_c, sw, data)


static func draw_quick_exhaust_motion(ci: CanvasItem, el) -> void:
	if el == null:
		return
	var data: Dictionary = _quick_exhaust_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	_draw_shuttle_ball(ci, el, ink(), sw, data)


## Предохранительный: квадрат ×RELIEF_UGO_SCALE (= клетка распреда); пружина статична;
## motion — только стрелка седла (к оси портов y=0).
static func _draw_relief_ugo(ci: CanvasItem, el, ink_c: Color, omit_motion: bool = false) -> void:
	var data: Dictionary = _relief_ugo_data()
	var s: float = RELIEF_UGO_SCALE
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var strokes_raw: Array = data.get("strokes", []) as Array
	# 0=короб, 5…=пружина+уставка (×s). 1–2=седло (motion). 3–4=порты → вручную.
	for i in strokes_raw.size():
		if i >= 1 and i <= 4:
			continue
		var st = strokes_raw[i]
		if not (st is Array):
			continue
		var poly: PackedVector2Array = _relief_poly_world(el, st as Array, true, s)
		if poly.size() >= 2:
			ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	# Порты: от края квадрата (±10·s = ±20) к tip ±30 на сетке.
	var half: float = 10.0 * s
	_line(ci, el, Vector2(-30.0, 0.0), Vector2(-half, 0.0), ink_c, 1.6)
	_line(ci, el, Vector2(30.0, 0.0), Vector2(half, 0.0), ink_c, 1.6)
	var dashed_raw: Array = data.get("dashed", []) as Array
	for st2 in dashed_raw:
		if st2 is Array:
			var dpoly: PackedVector2Array = _relief_poly_world(el, st2 as Array, true, s)
			_draw_dashed_polyline(ci, dpoly, ink_c, sw * 0.95, 5.0 * s, 3.5 * s)
	if str(el.port_3) == "muffler":
		_draw_valve_muffler_mark(ci, el, Vector2(30.0, 0.0), Vector2.RIGHT)
	if omit_motion:
		return
	_draw_relief_motion_parts(ci, el, ink_c, sw, data)


static func _relief_poly_world(el, pts_raw: Array, do_scale: bool, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts_raw:
		if p is Array and p.size() >= 2:
			var x: float = float(p[0])
			var y: float = float(p[1])
			if do_scale:
				x *= s
				y *= s
			out.append(to_world(el, Vector2(x, y)))
	return out


static func _relief_open_amt(el) -> float:
	if el == null:
		return 0.0
	var open: float = clampf(float(el.opening), 0.0, 1.0)
	if bool(el.pressed):
		open = 1.0
	return open


## Только стрелка/полоска седла: закрыта ниже оси, открыта на y=0 (уровень портов).
static func _draw_relief_motion_parts(
	ci: CanvasItem, el, ink_c: Color, sw: float, _data: Dictionary
) -> void:
	var open_amt: float = _relief_open_amt(el)
	var s: float = RELIEF_UGO_SCALE
	var half: float = 10.0 * s
	# Закрыто: y=−5·s; открыто: y=0 (ось подключения).
	var seat_y: float = lerpf(-5.0 * s, 0.0, open_amt)
	_line(ci, el, Vector2(5.0 * s, seat_y), Vector2(-half, seat_y), ink_c, 1.65)
	var sx: float = 5.0 * s
	var tri := PackedVector2Array([
		to_world(el, Vector2(sx, seat_y)),
		to_world(el, Vector2(sx, seat_y + 1.35 * s)),
		to_world(el, Vector2(sx + 5.0 * s, seat_y)),
		to_world(el, Vector2(sx, seat_y - 1.35 * s)),
		to_world(el, Vector2(sx, seat_y)),
	])
	ci.draw_polyline(tri, ink_c, sw * 1.05, _stroke_aa())


static func draw_relief_motion(ci: CanvasItem, el) -> void:
	if el == null:
		return
	var data: Dictionary = _relief_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	_draw_relief_motion_parts(ci, el, ink(), sw, data)


static func _draw_check_spring_ugo(
	ci: CanvasItem, el, ink_c: Color, sw: float, ball_r: float, ball_dx: float, data: Dictionary
) -> void:
	var h: float = float(data.get("spring_h", ball_r * 2.0 * (2.0 / 3.0)))
	var len0: float = float(data.get("spring_len_closed", 7.0))
	var len1: float = float(data.get("spring_len_open", 3.2))
	var open_amt: float = clampf(
		ball_dx / maxf(float(data.get("ball_open_dx", 5.0)), 0.001), 0.0, 1.0
	)
	var spring_len: float = lerpf(len0, len1, open_amt)
	var x0: float = ball_dx + ball_r * 0.95
	var x1: float = x0 + spring_len
	var coils: int = 5
	var pts := PackedVector2Array()
	for i in coils + 1:
		var t: float = float(i) / float(coils)
		var y: float = 0.0
		if i > 0 and i < coils:
			y = (h * 0.5) if (i % 2) == 1 else (-h * 0.5)
		pts.append(to_world(el, Vector2(lerpf(x0, x1, t), y)))
	if pts.size() >= 2:
		ci.draw_polyline(pts, ink_c, sw * 0.95, _stroke_aa())


static func _draw_throttle_restrictor(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _throttle_ugo_data()
	var top_raw: Array = data.get("arc_top", []) as Array
	var bot_raw: Array = data.get("arc_bot", []) as Array
	var s: float = THROTTLE_UGO_SCALE
	var sw: float = 1.7
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.7, _sch_zoom_of(ci))
	else:
		sw = _stroke_w(1.7)
	if top_raw.size() >= 2 and bot_raw.size() >= 2:
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		for p in top_raw:
			if p is Array and p.size() >= 2:
				top.append(to_world(el, Vector2(float(p[0]) * s, float(p[1]) * s)))
		for p in bot_raw:
			if p is Array and p.size() >= 2:
				bot.append(to_world(el, Vector2(float(p[0]) * s, float(p[1]) * s)))
		if top.size() >= 2:
			ci.draw_polyline(top, ink_c, sw, _stroke_aa())
		if bot.size() >= 2:
			ci.draw_polyline(bot, ink_c, sw, _stroke_aa())
		return
	# Fallback: пояс над/под линией (как DXF), не )( .
	var top_fb := PackedVector2Array()
	var bot_fb := PackedVector2Array()
	var n: int = 12
	for i in n + 1:
		var t: float = float(i) / float(n)
		var x: float = lerpf(-11.0, 11.0, t) * s
		var bulge: float = sin(t * PI) * 4.2 * s
		top_fb.append(to_world(el, Vector2(x, (7.8 * s) - bulge)))
		bot_fb.append(to_world(el, Vector2(x, (-7.8 * s) + bulge)))
	ci.draw_polyline(top_fb, ink_c, sw, _stroke_aa())
	ci.draw_polyline(bot_fb, ink_c, sw, _stroke_aa())


static func _draw_throttle_arrow(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _throttle_ugo_data()
	var arr: Array = data.get("arrow", []) as Array
	var s: float = THROTTLE_UGO_SCALE
	if arr.size() >= 2 and arr[0] is Array and arr[1] is Array:
		var a: Vector2 = Vector2(float(arr[0][0]) * s, float(arr[0][1]) * s)
		var b: Vector2 = Vector2(float(arr[1][0]) * s, float(arr[1][1]) * s)
		_line(ci, el, a, b, ink_c, 1.65)
		# Наконечник у верхнего конца.
		var dir: Vector2 = (b - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		_line(ci, el, b, b - dir * (4.5 * s) + perp * (2.2 * s), ink_c, 1.45)
		_line(ci, el, b, b - dir * (4.5 * s) - perp * (2.2 * s), ink_c, 1.45)
		return
	_line(ci, el, Vector2(-4.2 * s, -9.3 * s), Vector2(4.0 * s, 9.5 * s), ink_c, 1.65)
	_line(ci, el, Vector2(4.0 * s, 9.5 * s), Vector2(1.2 * s, 6.0 * s), ink_c, 1.45)
	_line(ci, el, Vector2(4.0 * s, 9.5 * s), Vector2(6.5 * s, 6.2 * s), ink_c, 1.45)


static func _draw_rail(ci: CanvasItem, el, font: Font, selected: bool, hover_port: String) -> void:
	Rail2D.ensure_points(el)
	var pts: PackedVector2Array = Rail2D.world_polyline(el)
	if pts.size() < 2:
		return
	var ink_c := ink()
	# ×2 к типичному электропроводу (~1.7 → 3.4).
	var w: float = 3.4 if selected else 3.2
	ci.draw_polyline(pts, ink_c, _stroke_w(w), _stroke_aa())
	if str(el.rail_domain) == "pneumatic":
		_draw_rail_pneumo_ends(ci, el, pts, ink_c)
	for port in Rail2D.ports(el):
		var pname := str(port["name"])
		_draw_port_marker(ci, el, port["local"], port_domain(el, pname), hover_port == pname)
	# Подпись шины не рисуем — это не аппарат.


static func _draw_rail_pneumo_ends(ci: CanvasItem, el, pts_w: PackedVector2Array, ink_c: Color) -> void:
	# Треугольник: гипотенуза к торцу шины, остриё наружу.
	if pts_w.size() < 2:
		return
	_draw_rail_end_tri(ci, pts_w[0], pts_w[1] - pts_w[0], ink_c)
	var n: int = pts_w.size()
	_draw_rail_end_tri(ci, pts_w[n - 1], pts_w[n - 2] - pts_w[n - 1], ink_c)


static func _draw_rail_end_tri(ci: CanvasItem, tip_end: Vector2, inward: Vector2, ink_c: Color) -> void:
	# tip_end — торец; inward — направление внутрь шины от торца.
	var along: Vector2 = -inward.normalized() if inward.length_squared() > 1.0e-8 else Vector2.RIGHT
	var outward: Vector2 = along
	var perp := Vector2(-outward.y, outward.x)
	var h: float = 7.0
	var d: float = 9.0
	var base_c: Vector2 = tip_end
	var tip: Vector2 = tip_end + outward * d
	var a: Vector2 = base_c + perp * (h * 0.5)
	var b: Vector2 = base_c - perp * (h * 0.5)
	ci.draw_polyline(PackedVector2Array([a, tip, b, a]), ink_c, _stroke_w(1.45), _stroke_aa())


static func _accessory_ports(el) -> Array:
	if str(el.accessory_class) == "reservoir":
		return _reservoir_ports(el)
	if str(el.accessory_class) == "shuttle":
		return _shuttle_ports(el)
	if str(el.accessory_class) == "and_valve":
		return _and_ports(el)
	if str(el.accessory_class) == "quick_exhaust":
		return _quick_exhaust_ports(el)
	if str(el.accessory_class) == "relief":
		return _relief_ports(el)
	if str(el.accessory_class) == "shutoff":
		# Как у 2/2: порт 1 снизу, порт 2 сверху (якорь покоя).
		return _valve_ports(el)
	var tip: float = _accessory_port_tip(el)
	return [
		{"name": "1", "local": Vector2(-tip, 0.0), "normal": Vector2.LEFT},
		{"name": "2", "local": Vector2(tip, 0.0), "normal": Vector2.RIGHT},
	]


## ИЛИ: 1/2 по горизонтали, 3 — общий (как в DXF: вниз на схеме = +Y).
static func _shuttle_ports(el) -> Array:
	var data: Dictionary = _shuttle_ugo_data()
	var tip: float = _accessory_port_tip(el)
	var p1: Array = data.get("port_1", [-tip, 0.0]) as Array
	var p2: Array = data.get("port_2", [tip, 0.0]) as Array
	var p3: Array = data.get("port_3", [0.0, tip]) as Array
	var a1 := Vector2(float(p1[0]), float(p1[1]))
	var a2 := Vector2(float(p2[0]), float(p2[1]))
	var a3 := Vector2(float(p3[0]), float(p3[1]))
	return [
		{"name": "1", "local": a1, "normal": Vector2.LEFT if a1.x < 0.0 else a1.normalized()},
		{"name": "2", "local": a2, "normal": Vector2.RIGHT if a2.x > 0.0 else a2.normalized()},
		{"name": "3", "local": a3, "normal": Vector2.DOWN if a3.y > 0.0 else Vector2.UP},
	]


## И: те же tips ±30 / −30 (DXF Проект1_Схема1).
static func _and_ports(el) -> Array:
	var data: Dictionary = _and_ugo_data()
	var tip: float = _accessory_port_tip(el)
	var p1: Array = data.get("port_1", [-tip, 0.0]) as Array
	var p2: Array = data.get("port_2", [tip, 0.0]) as Array
	var p3: Array = data.get("port_3", [0.0, tip]) as Array
	var a1 := Vector2(float(p1[0]), float(p1[1]))
	var a2 := Vector2(float(p2[0]), float(p2[1]))
	var a3 := Vector2(float(p3[0]), float(p3[1]))
	return [
		{"name": "1", "local": a1, "normal": Vector2.LEFT if a1.x < 0.0 else a1.normalized()},
		{"name": "2", "local": a2, "normal": Vector2.RIGHT if a2.x > 0.0 else a2.normalized()},
		{"name": "3", "local": a3, "normal": Vector2.DOWN if a3.y > 0.0 else Vector2.UP},
	]


## Быстрый выхлоп: 1 вход (−X), 2 ПЦ (−Y), 3 выхлоп (+X). Глушитель — без tip проводки.
static func _quick_exhaust_ports(el) -> Array:
	var data: Dictionary = _quick_exhaust_ugo_data()
	var tip: float = _accessory_port_tip(el)
	var p1: Array = data.get("port_1", [-tip, 0.0]) as Array
	var p2: Array = data.get("port_2", [0.0, -tip]) as Array
	var p3: Array = data.get("port_3", [tip, 0.0]) as Array
	var a1 := Vector2(float(p1[0]), float(p1[1]))
	var a2 := Vector2(float(p2[0]), float(p2[1]))
	var a3 := Vector2(float(p3[0]), float(p3[1]))
	var out: Array = [
		{"name": "1", "local": a1, "normal": Vector2.LEFT},
		{"name": "2", "local": a2, "normal": Vector2.UP},
	]
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	if ValveCat.exhaust_fit(el, "3") != "muffler":
		out.append({"name": "3", "local": a3, "normal": Vector2.RIGHT})
	return out


## Предохранительный: 1=вход, 2=сброс (если не глушитель — port_3 поле = тип выхлопа).
static func _relief_ports(el) -> Array:
	var data: Dictionary = _relief_ugo_data()
	var tip: float = _accessory_port_tip(el)
	var p1: Array = data.get("port_1", [-tip, 0.0]) as Array
	var p2: Array = data.get("port_2", [tip, 0.0]) as Array
	var a1 := Vector2(float(p1[0]), float(p1[1]))
	var a2 := Vector2(float(p2[0]), float(p2[1]))
	var out: Array = [
		{"name": "1", "local": a1, "normal": Vector2.LEFT},
	]
	if str(el.port_3) != "muffler":
		out.append({"name": "2", "local": a2, "normal": Vector2.RIGHT})
	return out


## Ресивер: бобышки сверху, tips на сетке. Только над плоской верхней гранью капсулы.
static func _reservoir_tip_y() -> float:
	# ~3× прежнего силуэта: выше body (ry≈36) + короткий отвод до −50.
	return -SCH_GRID * 5.0 # −50


static func _reservoir_body_ry() -> float:
	# 3× прежних ~12.
	return SCH_GRID * 3.6 # 36


static func _reservoir_port_pitch() -> float:
	# Чётное число клеток: при чётном n полупролёт тоже на сетке (±20, ±40…).
	return SCH_GRID * 4.0 # 40 между бобышками


static func _reservoir_flat_inset() -> float:
	# Зазор от стыка плоской грани и дуги — бобышка не на скруглении.
	return SCH_GRID * 2.0 # 20


static func _reservoir_body_half_w(n: int) -> float:
	# Ширина из раскладки портов: плоская часть ≥ span + inset с каждой стороны от скруглений.
	var nn: int = clampi(n, 1, 5)
	var ry: float = _reservoir_body_ry()
	var pitch: float = _reservoir_port_pitch()
	var span: float = 0.0 if nn <= 1 else float(nn - 1) * pitch
	var inset: float = _reservoir_flat_inset()
	var flat_half: float = maxf(SCH_GRID * 4.0, span * 0.5 + inset)
	return flat_half + ry


static func _reservoir_ports(el) -> Array:
	var AccL = preload("res://scripts/domain/accessory_library.gd")
	var n: int = AccL.reservoir_port_count(el)
	var tip_y: float = _reservoir_tip_y()
	var ry: float = _reservoir_body_ry()
	var half_w: float = _reservoir_body_half_w(n)
	var flat_half: float = half_w - ry
	var inset: float = _reservoir_flat_inset()
	var max_span: float = maxf(0.0, 2.0 * (flat_half - inset))
	max_span = floorf(max_span / SCH_GRID) * SCH_GRID
	var pitch: float = _reservoir_port_pitch()
	var span: float = 0.0 if n <= 1 else minf(float(n - 1) * pitch, max_span)
	span = roundf(span / SCH_GRID) * SCH_GRID
	var out: Array = []
	for i in n:
		var x: float = 0.0
		if n > 1:
			x = lerpf(-span * 0.5, span * 0.5, float(i) / float(n - 1))
			x = roundf(x / SCH_GRID) * SCH_GRID
			# Жёстко в плоской зоне (не на дугах).
			x = clampf(x, -(flat_half - inset), flat_half - inset)
			x = roundf(x / SCH_GRID) * SCH_GRID
		out.append({"name": str(i + 1), "local": Vector2(x, tip_y), "normal": Vector2.UP})
	return out


static func _draw_accessory(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	omit_motion: bool = false
) -> void:
	var ink_c := ink()
	var cls := str(el.accessory_class)
	var tip_x: float = _accessory_port_tip(el)
	match cls:
		"throttle", "throttle_fixed":
			# DXF: вертикальное УГО повёрнуто на L-R; дуги над/под линией + стрелка у регулируемого.
			_line(ci, el, Vector2(-tip_x, 0.0), Vector2(tip_x, 0.0), ink_c, 1.6)
			_draw_throttle_restrictor(ci, el, ink_c)
			if cls == "throttle":
				_draw_throttle_arrow(ci, el, ink_c)
		"check":
			# DXF: вертикальный шариковый ОК; CW90 → седло слева (порт 1), поток 1→2.
			# Давление — только цветом штриха УГО (без заливки-круга вокруг символа).
			_draw_check_ugo(ci, el, ink_c)
		"shuttle":
			_draw_shuttle_ugo(ci, el, ink_c, omit_motion)
		"and_valve":
			_draw_and_ugo(ci, el, ink_c)
		"quick_exhaust":
			_draw_quick_exhaust_ugo(ci, el, ink_c, omit_motion)
		"relief":
			_draw_relief_ugo(ci, el, ink_c, omit_motion)
		"throttle_check", "throttle_check_fixed":
			# DXF: дроссель на линии + обводной КО; стрелка только у регулируемого.
			_draw_throttle_check_ugo(ci, el, ink_c)
		"reservoir":
			# Капсула (прямоугольник + полукруги) + бобышки сверху (как эскиз УГО).
			_draw_reservoir_ugo(ci, el, ink_c, show_values)
		"regulator":
			_draw_regulator_ugo(ci, el, ink_c)
		"frl":
			_box(ci, el, -18.0, -12.0, 18.0, 12.0, ink_c)
			_line(ci, el, Vector2(-tip_x, 0.0), Vector2(-18.0, 0.0), ink_c, 1.6)
			_line(ci, el, Vector2(18.0, 0.0), Vector2(tip_x, 0.0), ink_c, 1.6)
			_line(ci, el, Vector2(-6.0, -12.0), Vector2(-6.0, 12.0), ink_c, 1.2)
			_line(ci, el, Vector2(6.0, -12.0), Vector2(6.0, 12.0), ink_c, 1.2)
			# Чашка фильтра снизу.
			_line(ci, el, Vector2(-4.0, 12.0), Vector2(-4.0, 18.0), ink_c, 1.3)
			_line(ci, el, Vector2(4.0, 12.0), Vector2(4.0, 18.0), ink_c, 1.3)
			_line(ci, el, Vector2(-4.0, 18.0), Vector2(4.0, 18.0), ink_c, 1.3)
		"shutoff":
			_draw_shutoff_ugo(ci, el, font, selected, hover_port, omit_motion)
			return
		_:
			_box(ci, el, -12.0, -10.0, 12.0, 10.0, ink_c)
			_line(ci, el, Vector2(-tip_x, 0.0), Vector2(-12.0, 0.0), ink_c, 1.6)
			_line(ci, el, Vector2(12.0, 0.0), Vector2(tip_x, 0.0), ink_c, 1.6)
	for port in _accessory_ports(el):
		var pname := str(port["name"])
		var tip: Vector2 = port["local"]
		_draw_port_marker(ci, el, tip, port_domain(el, pname), hover_port == pname)
	# Дроссель/ОК/ресивер/КР: величины только в тултипе.
	if show_values and cls == "frl":
		var lab: String = "%.1f бар" % float(el.set_pressure_bar)
		_text(ci, el, font, Vector2(-16.0, 26.0), lab, 10, Color(0.25, 0.35, 0.5, 0.9))
	_draw_element_tag(ci, el, font, 12, selected)


## УГО отсечного: 2/2 NC, ручные кнопки с обеих сторон (без вариаций).
static func _draw_shutoff_ugo(
	ci: CanvasItem, el, font: Font, selected: bool, hover_port: String, omit_motion: bool
) -> void:
	var AccZ = preload("res://scripts/domain/accessory_library.gd")
	AccZ.configure_shutoff_valve_ugo(el)
	# При Run клетки/органы едут на SchemeAnim. На Base — только порты+тег,
	# иначе при pressure_viz остаётся цветной «призрак» старого slide.
	if omit_motion:
		_draw_shutoff_shell(ci, el, font, selected, hover_port)
		return
	_draw_valve(ci, el, font, selected, false, hover_port, "", false)


## Неподвижная оболочка УГО отсечного (порты якоря + тег).
static func _draw_shutoff_shell(
	ci: CanvasItem, el, font: Font, selected: bool, hover_port: String
) -> void:
	for name in _valve_working_ports(el):
		var desc: Dictionary = _valve_port_desc(el, name)
		var tip: Vector2 = desc["local"]
		var edge: Vector2 = desc["edge"]
		_line(ci, el, edge, tip, ink(), 1.5)
		_draw_port_marker(ci, el, tip, port_domain(el, name), hover_port == name)
	_draw_element_tag(ci, el, font, 13, selected)


static func draw_shutoff_motion(ci: CanvasItem, el, font: Font) -> void:
	if el == null or str(el.accessory_class) != "shutoff":
		return
	var AccZ2 = preload("res://scripts/domain/accessory_library.gd")
	AccZ2.configure_shutoff_valve_ugo(el)
	draw_valve_motion(ci, el, font)


static func _draw_junction(ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String) -> void:
	var style := str(el.get("junction_style") if el.get("junction_style") != null else "tee")
	var ink_c := ink()
	var ports := _junction_ports(el)
	var body_r: float = SCH_GRID # крест до 10; хвосты до tip=20 на сетке
	if style == "adapter":
		# Небольшой прямоугольник + чёрная линия канала.
		var hx: float = SCH_GRID * 1.2 # 12
		var hy: float = SCH_GRID * 0.7 # 7
		_box(ci, el, -hx, -hy, hx, hy, ink_c)
		_line(ci, el, Vector2(-hx, 0.0), Vector2(hx, 0.0), ink_c, 1.8)
		for port_ad in ports:
			var tip_ad: Vector2 = port_ad["local"]
			var nrm_ad: Vector2 = port_ad["normal"]
			var root_ad: Vector2 = Vector2(hx * nrm_ad.x, 0.0) if absf(nrm_ad.x) > 0.5 else Vector2.ZERO
			_line(ci, el, root_ad, tip_ad, ink_c, 1.55)
			_draw_port_marker(ci, el, tip_ad, port_domain(el, str(port_ad["name"])), hover_port == str(port_ad["name"]))
		_draw_element_tag(ci, el, font, 11, selected)
		return
	# ISO-узел: компактный диск + короткие отводы к портам (не «крест» на весь габарит).
	if style == "tee":
		_line(ci, el, Vector2(-body_r, 0.0), Vector2(body_r, 0.0), ink_c, 2.0)
		_line(ci, el, Vector2(0.0, 0.0), Vector2(0.0, -body_r), ink_c, 2.0)
	elif style == "wye":
		_line(ci, el, Vector2(0.0, 0.0), Vector2(0.0, body_r), ink_c, 2.0)
		_line(ci, el, Vector2(0.0, 0.0), Vector2(-body_r * 0.9, -body_r * 0.8), ink_c, 2.0)
		_line(ci, el, Vector2(0.0, 0.0), Vector2(body_r * 0.9, -body_r * 0.8), ink_c, 2.0)
	else:
		var n := _junction_port_count(el)
		var span := 12.0 * float(maxi(n - 3, 1))
		_line(ci, el, Vector2(-span * 0.5 - 8.0, 0.0), Vector2(span * 0.5 + 8.0, 0.0), ink_c, 2.2)
	if show_values:
		var SimVj = preload("res://scripts/domain/sim_vis.gd")
		var pmax_j: float = _sch_p_max_of(ci)
		ci.draw_circle(to_world(el, Vector2.ZERO), 5.5, SimVj.pressure_color_fill(float(el.p_cap), pmax_j))
	ci.draw_circle(to_world(el, Vector2.ZERO), 3.8, ink_c)
	for port in ports:
		var tip: Vector2 = port["local"]
		var nrm: Vector2 = port["normal"]
		var root: Vector2
		if style == "manifold":
			root = Vector2(tip.x, 0.0)
		else:
			var stem: float = maxf(tip.length() - body_r, SCH_GRID * 0.5)
			root = tip - nrm * stem
		_line(ci, el, root, tip, ink_c, 1.55)
		var pname := str(port["name"])
		_draw_port_marker(ci, el, tip, port_domain(el, pname), hover_port == pname)
	_draw_element_tag(ci, el, font, 11, selected)


static func _draw_coil(ci: CanvasItem, el, font: Font, selected: bool, hover_port: String) -> void:
	# Отдельный УГО катушки (не орган на распределителе): прямоугольник, выводы A1/A2, пилот.
	var xa := -COIL_RW * 0.5
	var xb := COIL_RW * 0.5
	var ya := -COIL_RH * 0.5
	var yb := COIL_RH * 0.5
	_box(ci, el, xa, ya, xb, yb, INK)
	var a1 := Vector2(0.0, ya - COIL_LEAD)
	var a2 := Vector2(0.0, yb + COIL_LEAD)
	_line(ci, el, Vector2(0.0, ya), a1, INK, 1.45)
	_line(ci, el, Vector2(0.0, yb), a2, INK, 1.45)
	# Пилот: два треугольника остриём друг к другу + хвостики на основаниях.
	var jx := xb + COIL_PILOT_GAP
	var j := Vector2(jx, 0.0)
	_line(ci, el, Vector2(xb, 0.0), j, INK, 1.35)
	var half_h := COIL_PILOT_H * 0.5
	var pw := COIL_PILOT_W
	var top_base_y := -half_h
	var bot_base_y := half_h
	ci.draw_polyline(PackedVector2Array([
		to_world(el, j),
		to_world(el, Vector2(jx - pw * 0.5, top_base_y)),
		to_world(el, Vector2(jx + pw * 0.5, top_base_y)),
		to_world(el, j),
	]), ink(), _stroke_w(1.4), _stroke_aa())
	ci.draw_polyline(PackedVector2Array([
		to_world(el, j),
		to_world(el, Vector2(jx - pw * 0.5, bot_base_y)),
		to_world(el, Vector2(jx + pw * 0.5, bot_base_y)),
		to_world(el, j),
	]), ink(), _stroke_w(1.4), _stroke_aa())
	_line(ci, el, Vector2(jx, top_base_y), Vector2(jx, top_base_y - COIL_STEM), INK, 1.35)
	_line(ci, el, Vector2(jx, bot_base_y), Vector2(jx, bot_base_y + COIL_STEM), INK, 1.35)
	for port in ports(el):
		var tip: Vector2 = port["local"]
		var pname := str(port["name"])
		_draw_port_marker(ci, el, tip, port_domain(el, pname), hover_port == pname)
	_draw_element_tag(ci, el, font, 12, selected)


static func gauge_bar(p_abs: float) -> float:
	return (p_abs - 101325.0) / 1.0e5


static func bar_text(p_abs: float) -> String:
	return "%.2f" % gauge_bar(p_abs)


static func part_hit(el, world: Vector2, _zoom: float) -> String:
	if el.kind == "electro":
		var local_e := to_local(el, world)
		var best_e := ""
		var best_area_e := 1.0e9
		for zone in ElectroSym.part_zones(el):
			var rect_e: Rect2 = zone["rect"]
			if not rect_e.has_point(local_e):
				continue
			var area_e := rect_e.size.x * rect_e.size.y
			if area_e < best_area_e:
				best_area_e = area_e
				best_e = str(zone["id"])
		return best_e
	if el.kind == "valve":
		var local := to_local(el, world)
		var best := ""
		var best_area := 1.0e9
		for zone in part_zones(el):
			var rect: Rect2 = zone["rect"]
			if not rect.has_point(local):
				continue
			var area := rect.size.x * rect.size.y
			if area < best_area:
				best_area = area
				best = str(zone["id"])
		return best
	if el.kind != "cylinder":
		return ""
	var local := to_local(el, world)
	var best := ""
	var best_area := 1.0e9
	for zone in part_zones(el):
		var id := str(zone["id"])
		if id == "tip" or id == "carriage" or id == "port_cap" or id == "port_rod":
			continue
		var rect: Rect2 = zone["rect"]
		if not rect.has_point(local):
			continue
		var area := rect.size.x * rect.size.y
		if area < best_area:
			best_area = area
			best = id
	return best


static func part_zones(el) -> Array:
	if el.kind == "electro":
		return ElectroSym.part_zones(el)
	if el.kind == "valve":
		return _valve_zones(el)
	# Взаимно исключающие полосы. Каретка = зона «rod» (смещается вверх).
	var px := piston_x(el)
	var mode := _mode(el)
	var height := BODY_B - BODY_T
	var gap := PISTON_GAP
	var left := clampf(px - gap, BODY_L + 2.0, BODY_R - gap - 2.0)
	px = left + gap
	var cush_w := CUSH_ARM
	var zones: Array = [
		# Крупный «корпус» — проигрывает мелким зонам по площади.
		{"id": "body", "rect": Rect2(BODY_L, BODY_T, BODY_R - BODY_L, height)},
		{"id": "cush_cap", "rect": Rect2(left - cush_w, BODY_T, cush_w, height)},
		{"id": "piston", "rect": Rect2(left, BODY_T, gap, height)},
		{"id": "cush_rod", "rect": Rect2(px, BODY_T, cush_w, height)},
	]
	var spring := _spring_side(el)
	# Зоны spring всегда доступны для ПКМ (в т.ч. при spring_side=none — чтобы можно было добавить пружину).
	var cap_x0 := BODY_L
	var cap_x1 := left - cush_w
	var rod_x0 := px + cush_w
	var rod_x1 := BODY_R
	if spring == "cap" or spring == "both" or spring == "none":
		if cap_x1 > cap_x0 + 4.0:
			zones.append({"id": "spring", "rect": Rect2(cap_x0, BODY_T, maxf(cap_x1 - cap_x0, 10.0), height)})
	if spring == "rod" or spring == "both" or spring == "none":
		if rod_x1 > rod_x0 + 4.0:
			zones.append({"id": "spring", "rect": Rect2(rod_x0, BODY_T, maxf(rod_x1 - rod_x0, 10.0), height)})
	if mode == "rodless":
		zones.append({"id": "rod", "rect": Rect2(BODY_L, BODY_T - 30.0, 70.0, 28.0)})
		zones.append({"id": "bump_end", "rect": Rect2(BODY_R - 40.0, BODY_T - 30.0, 40.0, 28.0)})
	else:
		zones.append({"id": "rod", "rect": Rect2(BODY_R, -ROD_GAP - 8.0, ROD_X - BODY_R, ROD_GAP * 2.0 + 16.0)})
		zones.append({"id": "guide", "rect": Rect2(BODY_R - 6.0, BODY_T + 4.0, 18.0, height - 8.0)})
		# Зона по месту УГО тормоза (NC-блок сверху + end_lock у крышки), не у наконечника штока.
		var bl: Dictionary = _brake_layout()
		var zx0 := minf(BODY_R - 4.0, float(bl["bx0"]) - 6.0)
		var zy0 := minf(BODY_T - 16.0, float(bl["by0"]) - 20.0)
		var zx1 := float(bl["bx1"]) + 22.0
		var zy1 := maxf(BODY_T + 4.0, float(bl["by1"]) + 8.0)
		zones.append({"id": "brake", "rect": Rect2(zx0, zy0, zx1 - zx0, zy1 - zy0)})
	return zones


static func _mode(el) -> String:
	var value = el.get("rod_mode")
	if value == null:
		return "single"
	return str(value)


static func _spring_side(el) -> String:
	var value = el.get("spring_side")
	if value == null:
		if str(el.action) == "spring_return":
			return "rod"
		if str(el.action) == "spring_extend":
			return "cap"
		return "none"
	return str(value)


static func _draw_cylinder(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	hover_part: String, omit_motion: bool = false
) -> void:
	var px := piston_x(el)
	if show_values and not omit_motion:
		_draw_cylinder_pressure_fills(ci, el, px)
	_draw_body(ci, el)
	if not omit_motion:
		var rod_mode := _mode(el)
		var spring := _spring_side(el)
		if spring == "rod" or spring == "both":
			_chamber_spring(ci, el, px + 4.0, BODY_R - 4.0)
		if spring == "cap" or spring == "both":
			_chamber_spring(ci, el, BODY_L + 4.0, px - PISTON_GAP - 4.0)
		if rod_mode == "rodless":
			_draw_carriage(ci, el)
		else:
			# Шток начинается за правым демпфером, иначе линия штока режет карман U.
			var rod_from := px
			if _cushion_kind(el, false) != "none":
				rod_from = px + CUSH_ARM
			_rod(ci, el, rod_from, ROD_X)
			if rod_mode == "through":
				var left_tip := BODY_L - (ROD_X - BODY_R)
				var left_from := px - PISTON_GAP
				if _cushion_kind(el, true) != "none":
					left_from = px - PISTON_GAP - CUSH_ARM
				_rod(ci, el, left_from, left_tip)
		_draw_piston(ci, el, px)
		# Демпферы после штока (без заливки PAPER — она резала поршень и стрелку).
		_draw_cushions(ci, el, px)
	_draw_brake(ci, el, hover_port)
	# Крепления на УГО не рисуем — мешают схеме; параметр остаётся в свойствах.
	_draw_ports(ci, el, selected, show_values, hover_port, font)
	_draw_element_tag(ci, el, font, 14, selected)


static func _draw_imported_strokes(ci: CanvasItem, el) -> void:
	for item in Strokes.imported_strokes():
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var poly: Array = item.get("polyline", [])
		if poly.size() < 2:
			continue
		for i in range(poly.size() - 1):
			var a: Variant = poly[i]
			var b: Variant = poly[i + 1]
			if typeof(a) != TYPE_ARRAY or typeof(b) != TYPE_ARRAY:
				continue
			if a.size() < 2 or b.size() < 2:
				continue
			_line(ci, el, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])))



static func _local_rect_world(el, rect: Rect2) -> Rect2:
	var a := to_world(el, rect.position)
	var b := to_world(el, rect.position + rect.size)
	var box := Rect2(a, Vector2.ZERO)
	box = box.expand(b)
	box = box.expand(to_world(el, Vector2(rect.position.x, rect.end.y)))
	box = box.expand(to_world(el, Vector2(rect.end.x, rect.position.y)))
	return box


static func _draw_body(ci: CanvasItem, el) -> void:
	_line(ci, el, Vector2(BODY_L, BODY_T), Vector2(BODY_R, BODY_T))
	if _mode(el) == "rodless":
		_line(ci, el, Vector2(BODY_R, BODY_T), Vector2(BODY_R, BODY_B))
	else:
		_line(ci, el, Vector2(BODY_R, BODY_T), Vector2(BODY_R, -ROD_GAP))
		_line(ci, el, Vector2(BODY_R, ROD_GAP), Vector2(BODY_R, BODY_B))
	_line(ci, el, Vector2(BODY_R, BODY_B), Vector2(BODY_L, BODY_B))
	_line(ci, el, Vector2(BODY_L, BODY_B), Vector2(BODY_L, BODY_T))


static func _draw_cylinder_pressure_fills(ci: CanvasItem, el, px: float) -> void:
	var SimV = preload("res://scripts/domain/sim_vis.gd")
	var gap := PISTON_GAP
	var left := clampf(px - gap, BODY_L + 2.0, BODY_R - gap - 2.0)
	var piston_face := left + gap
	var pmax_c: float = _sch_p_max_of(ci)
	var cap_col: Color = SimV.pressure_color_fill(float(el.p_cap), pmax_c)
	var rod_col: Color = SimV.pressure_color_fill(float(el.p_rod), pmax_c)
	var cap_poly := PackedVector2Array([
		to_world(el, Vector2(BODY_L, BODY_T)),
		to_world(el, Vector2(left, BODY_T)),
		to_world(el, Vector2(left, BODY_B)),
		to_world(el, Vector2(BODY_L, BODY_B)),
	])
	var rod_poly := PackedVector2Array([
		to_world(el, Vector2(piston_face, BODY_T)),
		to_world(el, Vector2(BODY_R, BODY_T)),
		to_world(el, Vector2(BODY_R, BODY_B)),
		to_world(el, Vector2(piston_face, BODY_B)),
	])
	ci.draw_colored_polygon(cap_poly, cap_col)
	ci.draw_colored_polygon(rod_poly, rod_col)


static func _draw_ports(ci: CanvasItem, el, selected: bool, show_values: bool, hover_port: String, font: Font) -> void:
	for side in ["cap", "rod"]:
		var x := PORT_CAP_X if side == "cap" else PORT_ROD_X
		if _port_style(el, side) == "exhaust":
			# Малый треугольник: основание на нижней линии корпуса.
			var h := 12.0
			_triangle(ci, el, Vector2(x, BODY_B + h), Vector2.DOWN, h)
			continue
		var tip := Vector2(x, BODY_B + PORT_DROP)
		_line(ci, el, Vector2(x, BODY_B), tip)
		_draw_port_marker(ci, el, tip, port_domain(el, side), hover_port == side)


static func _port_style(el, side: String) -> String:
	var key := "port_cap" if side == "cap" else "port_rod"
	var value = el.get(key)
	if value == null or str(value) == "" or str(value) == "connect":
		return "connect"
	return "exhaust"


static func _rod(ci: CanvasItem, el, x0: float, x1: float) -> void:
	var left := minf(x0, x1)
	var right := maxf(x0, x1)
	var gap := ROD_GAP
	_line(ci, el, Vector2(left, -gap), Vector2(right, -gap))
	_line(ci, el, Vector2(left, gap), Vector2(right, gap))
	_line(ci, el, Vector2(x1, -gap), Vector2(x1, gap))


static func _draw_piston(ci: CanvasItem, el, px: float) -> void:
	var kind := "simple"
	var value = el.get("piston_kind")
	if value != null and str(value) != "":
		kind = str(value)
	if kind != "magnetic":
		kind = "simple"
	var gap := PISTON_GAP
	var left := clampf(px - gap, BODY_L + 2.0, BODY_R - gap - 2.0)
	px = left + gap
	_line(ci, el, Vector2(left, BODY_T), Vector2(left, BODY_B))
	_line(ci, el, Vector2(px, BODY_T), Vector2(px, BODY_B))
	if kind == "magnetic":
		_magnetic_c(ci, el, left, px, BODY_T, BODY_B)


static func _magnetic_c(ci: CanvasItem, el, x0: float, x1: float, y0: float, y1: float) -> void:
	# Узкий «C» по центру интервала, раскрытие вправо.
	var mid_x := (x0 + x1) * 0.5
	var half_w := minf((x1 - x0) * 0.28, 7.0)
	var back := mid_x - half_w
	var face := mid_x + half_w
	var inset := minf(6.0, (y1 - y0) * 0.14)
	var throat := minf(5.0, (y1 - y0) * 0.18)
	_fill_poly(ci, el, PackedVector2Array([
		Vector2(back, y0 + inset),
		Vector2(face, y0 + inset),
		Vector2(face, y0 + inset + throat),
		Vector2(back + half_w * 0.55, y0 + inset + throat),
		Vector2(back + half_w * 0.55, y1 - inset - throat),
		Vector2(face, y1 - inset - throat),
		Vector2(face, y1 - inset),
		Vector2(back, y1 - inset),
	]), ink())


static func _draw_cushions(ci: CanvasItem, el, px: float) -> void:
	var gap := PISTON_GAP
	var left := clampf(px - gap, BODY_L + 2.0, BODY_R - gap - 2.0)
	px = left + gap
	var cap_kind := _cushion_kind(el, true)
	var rod_kind := _cushion_kind(el, false)
	var arm := CUSH_ARM
	var half_h := 14.0
	if cap_kind != "none":
		var x := left - arm
		_line(ci, el, Vector2(x, -half_h), Vector2(x, half_h))
		_line(ci, el, Vector2(x, -half_h), Vector2(left, -half_h))
		_line(ci, el, Vector2(x, half_h), Vector2(left, half_h))
		_line(ci, el, Vector2(x, -ROD_GAP), Vector2(x, ROD_GAP), INK, 2.2)
	if rod_kind != "none":
		var x := px + arm
		_line(ci, el, Vector2(x, -half_h), Vector2(x, half_h))
		_line(ci, el, Vector2(px, -half_h), Vector2(x, -half_h))
		_line(ci, el, Vector2(px, half_h), Vector2(x, half_h))
		_line(ci, el, Vector2(x, -ROD_GAP), Vector2(x, ROD_GAP), INK, 2.2)
	# Стрелка поверх U, без пересечения с заливкой.
	var both_adj := cap_kind == "adjustable" and rod_kind == "adjustable"
	if both_adj:
		_adj_arrow(ci, el, (left + px) * 0.5)
	elif cap_kind == "adjustable":
		_adj_arrow(ci, el, left - arm * 0.5)
	elif rod_kind == "adjustable":
		_adj_arrow(ci, el, px + arm * 0.5)


static func _adj_arrow(ci: CanvasItem, el, cx: float) -> void:
	_filled_arrow(ci, el, Vector2(cx + 10.0, BODY_B + 10.0), Vector2(cx - 4.0, BODY_T - 14.0))


static func _cushion_kind(el, cap_side: bool) -> String:
	var key := "cush_cap" if cap_side else "cush_rod"
	var value = el.get(key)
	if value == null or str(value) == "":
		return "none"
	return str(value)


static func _draw_carriage(ci: CanvasItem, el) -> void:
	var kind := "none"
	var value = el.get("carriage")
	if value != null:
		kind = str(value)
	if kind == "" or kind == "none":
		kind = "plain"
	var x0 := BODY_L
	var x1 := BODY_L + 64.0
	var y0 := BODY_T - 20.0
	var y1 := BODY_T
	_line(ci, el, Vector2(x0, y1), Vector2(x0, y0))
	_line(ci, el, Vector2(x1, y1), Vector2(x1, y0))
	_line(ci, el, Vector2(x0, y0), Vector2(x1, y0))
	if kind == "magnetic":
		# «П» на всю ширину каретки.
		var pad := 4.0
		var top := y0 + 3.0
		var bot := y1 - 3.0
		_line(ci, el, Vector2(x0 + pad, bot), Vector2(x0 + pad, top), INK, 2.2)
		_line(ci, el, Vector2(x1 - pad, bot), Vector2(x1 - pad, top), INK, 2.2)
		_line(ci, el, Vector2(x0 + pad, top), Vector2(x1 - pad, top), INK, 2.2)


static func _draw_tip(ci: CanvasItem, el, at: Vector2, sign: float) -> void:
	var kind := "plain"
	var value = el.get("rod_end")
	if value != null and str(value) != "":
		kind = str(value)
	match kind:
		"female":
			_line(ci, el, at + Vector2(0.0, -6.0), at + Vector2(sign * 12.0, -6.0))
			_line(ci, el, at + Vector2(0.0, 6.0), at + Vector2(sign * 12.0, 6.0))
			_line(ci, el, at + Vector2(sign * 12.0, -6.0), at + Vector2(sign * 12.0, 6.0))
		"clevis":
			_line(ci, el, at + Vector2(sign * 2.0, -10.0), at + Vector2(sign * 2.0, 10.0))
		"roller":
			_line(ci, el, at, at + Vector2(sign * 10.0, -7.0))
			_line(ci, el, at, at + Vector2(sign * 10.0, 7.0))
			ci.draw_arc(to_world(el, at + Vector2(sign * 10.0, 0.0)), 6.0, 0.0, TAU, 24, ink(), 1.6, true)
		"male":
			_box(ci, el, at.x, -5.0, at.x + sign * 16.0, 5.0, INK)
		_:
			pass # AS default: закрытый торец канала штока уже в _rod


## Габариты УГО тормоза (локально): блок над штоком + пилотный порт справа.
static func _brake_layout() -> Dictionary:
	var bx0 := BODY_R + 18.0
	var bx1 := BODY_R + 38.0
	var by0 := -48.0
	var by1 := -26.0
	var y := (by0 + by1) * 0.5
	return {
		"bx0": bx0, "bx1": bx1, "by0": by0, "by1": by1,
		"port": Vector2(bx1 + 12.0, y),
	}


static func _outline_poly(ci: CanvasItem, el, local: PackedVector2Array, width: float = 1.55) -> void:
	if local.size() < 2:
		return
	var world := PackedVector2Array()
	for p in local:
		world.append(to_world(el, p))
	if world[0].distance_to(world[world.size() - 1]) > 0.5:
		world.append(world[0])
	ci.draw_polyline(world, ink(), _stroke_w(width), _stroke_aa())


static func _draw_brake(ci: CanvasItem, el, hover_port: String = "") -> void:
	var kind := "none"
	var value = el.get("brake")
	if value != null:
		kind = str(value)
	if kind == "" or kind == "none" or _mode(el) == "rodless":
		return
	if kind == "end_lock":
		# Стопор у передней крышки: малый блок с засечкой.
		var x0 := BODY_R - 2.0
		var x1 := BODY_R + 10.0
		_box(ci, el, x0, BODY_T - 6.0, x1, BODY_T + 2.0, INK)
		_line(ci, el, Vector2(x0 + 4.0, BODY_T - 6.0), Vector2(x0 + 4.0, BODY_T - 14.0))
		return
	# NC: зажим штока — контуры без заливки (заливка = гидравлика).
	var notch_x := BODY_R + 12.0
	_outline_poly(ci, el, PackedVector2Array([
		Vector2(notch_x - 5.0, -ROD_GAP),
		Vector2(notch_x + 5.0, -ROD_GAP),
		Vector2(notch_x, -ROD_GAP - 8.0),
	]))
	var bl: Dictionary = _brake_layout()
	var bx0: float = float(bl["bx0"])
	var bx1: float = float(bl["bx1"])
	var by0: float = float(bl["by0"])
	var by1: float = float(bl["by1"])
	var port_tip: Vector2 = bl["port"]
	_box(ci, el, bx0, by0, bx1, by1, INK)
	_outline_poly(ci, el, PackedVector2Array([
		Vector2((bx0 + bx1) * 0.5, by0 + 4.0),
		Vector2(bx0 + 4.0, by1 - 4.0),
		Vector2(bx1 - 4.0, by1 - 4.0),
	]))
	_brake_spring(ci, el, (bx0 + bx1) * 0.5, by0 - 18.0, by0)
	var y := (by0 + by1) * 0.5
	_outline_poly(ci, el, PackedVector2Array([
		Vector2(bx1, y - 3.5),
		Vector2(bx1, y + 3.5),
		port_tip,
	]))
	_draw_port_marker(ci, el, port_tip, port_domain(el, "brake"), hover_port == "brake")


static func _draw_mount(ci: CanvasItem, el) -> void:
	var kind := "clevis"
	var value = el.get("mount")
	if value != null and str(value) != "":
		kind = str(value)
	match kind:
		"foot":
			_line(ci, el, Vector2(BODY_L + 6.0, BODY_B), Vector2(BODY_L + 6.0, BODY_B + 10.0))
			_line(ci, el, Vector2(BODY_L + 2.0, BODY_B + 10.0), Vector2(BODY_L + 18.0, BODY_B + 10.0))
			_line(ci, el, Vector2(BODY_R - 6.0, BODY_B), Vector2(BODY_R - 6.0, BODY_B + 10.0))
			_line(ci, el, Vector2(BODY_R - 18.0, BODY_B + 10.0), Vector2(BODY_R - 2.0, BODY_B + 10.0))
		"flange_front":
			_line(ci, el, Vector2(BODY_R, BODY_T - 8.0), Vector2(BODY_R, BODY_B + 8.0))
			_line(ci, el, Vector2(BODY_R, BODY_T - 8.0), Vector2(BODY_R + 6.0, BODY_T - 8.0))
			_line(ci, el, Vector2(BODY_R, BODY_B + 8.0), Vector2(BODY_R + 6.0, BODY_B + 8.0))
		"flange_rear":
			_line(ci, el, Vector2(BODY_L, BODY_T - 8.0), Vector2(BODY_L, BODY_B + 8.0))
			_line(ci, el, Vector2(BODY_L, BODY_T - 8.0), Vector2(BODY_L - 6.0, BODY_T - 8.0))
			_line(ci, el, Vector2(BODY_L, BODY_B + 8.0), Vector2(BODY_L - 6.0, BODY_B + 8.0))
		"trunnion":
			var mx := (BODY_L + BODY_R) * 0.5
			_line(ci, el, Vector2(mx, BODY_T), Vector2(mx, BODY_T - 10.0))
			_line(ci, el, Vector2(mx, BODY_B), Vector2(mx, BODY_B + 10.0))
			ci.draw_arc(to_world(el, Vector2(mx, BODY_T - 10.0)), 4.0, 0.0, TAU, 16, ink(), 1.4, true)
			ci.draw_arc(to_world(el, Vector2(mx, BODY_B + 10.0)), 4.0, 0.0, TAU, 16, ink(), 1.4, true)
		"clevis":
			if _mode(el) == "rodless":
				return
			_line(ci, el, Vector2(BODY_L - 2.0, -8.0), Vector2(BODY_L - 2.0, 8.0))
			_line(ci, el, Vector2(BODY_L - 2.0, -8.0), Vector2(BODY_L - 14.0, -8.0))
			_line(ci, el, Vector2(BODY_L - 2.0, 8.0), Vector2(BODY_L - 14.0, 8.0))
			_line(ci, el, Vector2(BODY_L - 14.0, -8.0), Vector2(BODY_L - 14.0, 8.0))
		_:
			pass


static func _chamber_spring(ci: CanvasItem, el, x0: float, x1: float) -> void:
	# Фиксированное число витков: при сжатии уменьшается только шаг по оси (длина),
	# высота зигзага остаётся постоянной — как у реальной пружины на УГО.
	if x1 < x0:
		var swap := x0
		x0 = x1
		x1 = swap
	var span := x1 - x0
	if span < 4.0:
		return
	const COILS := 6
	var step := span / float(COILS)
	var mid_y := (BODY_T + BODY_B) * 0.5
	var amp: float = (BODY_B - BODY_T) * 0.5 - 3.0
	var top := mid_y - amp
	var bot := mid_y + amp
	var width := 1.35 if span < 28.0 else 1.55
	var pts := PackedVector2Array()
	pts.append(to_world(el, Vector2(x0, mid_y)))
	for i in COILS:
		var y := bot if i % 2 == 0 else top
		pts.append(to_world(el, Vector2(x0 + step * (float(i) + 0.5), y)))
	pts.append(to_world(el, Vector2(x1, mid_y)))
	ci.draw_polyline(pts, ink(), _stroke_w(width), _stroke_aa())


static func _brake_spring(ci: CanvasItem, el, x: float, y0: float, y1: float) -> void:
	var turns := 4
	var step := (y1 - y0) / float(turns)
	var pts := PackedVector2Array()
	pts.append(to_world(el, Vector2(x, y0)))
	for i in turns:
		var dx := -6.0 if i % 2 == 0 else 6.0
		pts.append(to_world(el, Vector2(x + dx, y0 + step * (float(i) + 0.5))))
	pts.append(to_world(el, Vector2(x, y1)))
	ci.draw_polyline(pts, ink(), _stroke_w(1.35), _stroke_aa())


static func _fill_rect(ci: CanvasItem, el, x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	_fill_poly(ci, el, PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
	]), color)


static func _fill_poly(ci: CanvasItem, el, local: PackedVector2Array, color: Color) -> void:
	var world := PackedVector2Array()
	for point in local:
		world.append(to_world(el, point))
	ci.draw_colored_polygon(world, _resolve_ink(color))


static func _filled_arrow(ci: CanvasItem, el, a: Vector2, b: Vector2) -> void:
	_line(ci, el, a, b)
	var delta := b - a
	if delta.length() < 1.0:
		return
	var dir := delta.normalized()
	var side := Vector2(-dir.y, dir.x)
	_fill_poly(ci, el, PackedVector2Array([
		b,
		b - dir * 10.0 + side * 4.5,
		b - dir * 10.0 - side * 4.5,
	]), ink())


static func _draw_source(ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String) -> void:
	var tip := Vector2(SRC_TIP_X, 0.0)
	var base_x := SRC_TIP_X - SRC_DEPTH
	var up := Vector2(base_x, -SRC_HALF_H)
	var down := Vector2(base_x, SRC_HALF_H)
	var poly := PackedVector2Array([
		to_world(el, tip), to_world(el, down), to_world(el, up), to_world(el, tip),
	])
	ci.draw_polyline(poly, ink(), _stroke_w(1.8), _stroke_aa())
	_draw_port_marker(ci, el, tip, port_domain(el, "out"), hover_port == "out")
	_draw_element_tag(ci, el, font, 14, selected)


static func _box(ci: CanvasItem, el, x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	var left := minf(x0, x1)
	var right := maxf(x0, x1)
	var top := minf(y0, y1)
	var bottom := maxf(y0, y1)
	_line(ci, el, Vector2(left, top), Vector2(right, top), color, 1.5)
	_line(ci, el, Vector2(right, top), Vector2(right, bottom), color, 1.5)
	_line(ci, el, Vector2(right, bottom), Vector2(left, bottom), color, 1.5)
	_line(ci, el, Vector2(left, bottom), Vector2(left, top), color, 1.5)


static func _triangle(ci: CanvasItem, el, tip: Vector2, direction: Vector2, height: float) -> void:
	var n := direction.normalized()
	var side := Vector2(-n.y, n.x)
	var base := tip - n * height
	var half := height / sqrt(3.0)
	var poly := PackedVector2Array([
		to_world(el, tip),
		to_world(el, base + side * half),
		to_world(el, base - side * half),
		to_world(el, tip),
	])
	ci.draw_polyline(poly, ink(), _stroke_w(1.6), _stroke_aa())


## Мин. экранные px штриха на схеме — ниже субпиксель, жилы/УГО пропадают (см. zoom-out).
const SCH_STROKE_MIN_PX := 1.5


static func _stroke_w(width: float) -> float:
	# В превью библиотеки штрих масштабируется transform'ом — держим ~1.7 px на экране.
	if _library_preview:
		return maxf(width, 1.7 / _library_scale)
	# На схеме: world-толщина + пол по screen px (без потолка — иначе дыхание при zoom-in).
	if _sch_ctx_active:
		return _stroke_w_zoom(width, _sch_ctx_zoom)
	return width


static func _stroke_w_zoom(width: float, zoom: float) -> float:
	# SchemeWorld.scale=zoom → screen = world*zoom. Только нижний пол, без max-clamp.
	var z: float = maxf(zoom, 0.05)
	return maxf(width, SCH_STROKE_MIN_PX / z)


static func _stroke_aa() -> bool:
	# На схеме — чётко без AA; в превью AA нужен, иначе штрихи «съедаются».
	return _library_preview


static func _line(ci: CanvasItem, el, a: Vector2, b: Vector2, color: Color = INK, width: float = 1.7) -> void:
	var w: float = width
	if _sch_has_zoom(ci) and not _library_preview:
		w = _stroke_w_zoom(width, _sch_zoom_of(ci))
	else:
		w = _stroke_w(width)
	ci.draw_line(to_world(el, a), to_world(el, b), _resolve_ink(color), w, _stroke_aa())


static func _poly(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float = 1.55) -> void:
	if pts.size() < 2:
		return
	var w: float = width
	if _sch_has_zoom(ci) and not _library_preview:
		w = _stroke_w_zoom(width, _sch_zoom_of(ci))
	else:
		w = _stroke_w(width)
	ci.draw_polyline(pts, _resolve_ink(color), w, _stroke_aa())


static func _ellipse_pts(el, center: Vector2, rx: float, ry: float, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = TAU * float(i) / float(n)
		pts.append(to_world(el, center + Vector2(cos(a) * rx, sin(a) * ry)))
	return pts


static func _draw_ellipse(ci: CanvasItem, el, center: Vector2, rx: float, ry: float, color: Color, width: float = 1.6) -> void:
	_poly(ci, _ellipse_pts(el, center, rx, ry, 40), color, width)


static func _fill_ellipse(ci: CanvasItem, el, center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts: PackedVector2Array = _ellipse_pts(el, center, rx, ry, 36)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, color)


## Локаль острия треугольника выхлопа КР и направление «от квадрата» (без rotation_quad).
static func regulator_relief_exhaust_local() -> Dictionary:
	var data: Dictionary = _regulator_ugo_data()
	var tip_a: Array = data.get("exhaust_tip", [-22.5, -15.0]) as Array
	var dir_a: Array = data.get("exhaust_dir", [-1.0, 0.0]) as Array
	var tip := Vector2(float(tip_a[0]), float(tip_a[1]))
	var dir := Vector2(float(dir_a[0]), float(dir_a[1]))
	if dir.length_squared() < 1.0e-8:
		dir = Vector2.LEFT
	else:
		dir = dir.normalized()
	return {"tip": tip, "dir": dir}


## Редуктор по DXF: корпус, стрелка, пружина, пунктир сброса → треугольник выхлопа.
static func _draw_regulator_ugo(ci: CanvasItem, el, ink_c: Color) -> void:
	var data: Dictionary = _regulator_ugo_data()
	var sw: float = _stroke_w(1.65)
	if _sch_has_zoom(ci) and not _library_preview:
		sw = _stroke_w_zoom(1.65, _sch_zoom_of(ci))
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if st is Array:
			var poly: PackedVector2Array = _poly_local_to_world(el, st as Array)
			if poly.size() >= 2:
				ci.draw_polyline(poly, ink_c, sw, _stroke_aa())
	var dashed_raw: Array = data.get("dashed", []) as Array
	for st2 in dashed_raw:
		if st2 is Array:
			var dpoly: PackedVector2Array = _poly_local_to_world(el, st2 as Array)
			_draw_dashed_polyline(ci, dpoly, ink_c, sw * 0.95, 5.0, 3.5)


static func _draw_dashed_polyline(
	ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float,
	dash_len: float, gap_len: float
) -> void:
	if pts.size() < 2:
		return
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: Vector2 = b - a
		var total: float = seg.length()
		if total < 0.05:
			continue
		var dir: Vector2 = seg / total
		var pos: float = 0.0
		var draw_on: bool = true
		while pos < total - 0.01:
			var span: float = dash_len if draw_on else gap_len
			var npos: float = minf(pos + span, total)
			if draw_on:
				ci.draw_line(a + dir * pos, a + dir * npos, color, width, _stroke_aa())
			pos = npos
			draw_on = not draw_on


## Капсула ресивера + вертикальные бобышки к tips портов.
static func _draw_reservoir_ugo(ci: CanvasItem, el, ink_c: Color, show_values: bool) -> void:
	var AccR = preload("res://scripts/domain/accessory_library.gd")
	var n: int = AccR.reservoir_port_count(el)
	var half_w: float = _reservoir_body_half_w(n)
	var ry: float = _reservoir_body_ry()
	var body_top: float = -ry
	var body_bot: float = ry
	var lw: float = 2.0
	# Прямоугольная середина + полукруги слева/справа.
	_line(ci, el, Vector2(-half_w + ry, body_top), Vector2(half_w - ry, body_top), ink_c, lw)
	_line(ci, el, Vector2(-half_w + ry, body_bot), Vector2(half_w - ry, body_bot), ink_c, lw)
	# Левая полуокружность (снаружи влево).
	var left_pts := PackedVector2Array()
	for i in 17:
		var a: float = PI * 0.5 + PI * float(i) / 16.0 # π/2 → 3π/2
		left_pts.append(to_world(el, Vector2(-half_w + ry + cos(a) * ry, sin(a) * ry)))
	_poly(ci, left_pts, ink_c, lw)
	var right_pts := PackedVector2Array()
	for i in 17:
		var a2: float = -PI * 0.5 + PI * float(i) / 16.0 # −π/2 → π/2
		right_pts.append(to_world(el, Vector2(half_w - ry + cos(a2) * ry, sin(a2) * ry)))
	_poly(ci, right_pts, ink_c, lw)
	# Заливку/цифры объёма на УГО не рисуем — только тег; давление в tip и 3D.
	# Бобышки: от плоской верхней грани до tip (x уже в зоне flat).
	for port in _reservoir_ports(el):
		var tip: Vector2 = port["local"]
		_line(ci, el, Vector2(tip.x, body_top), tip, ink_c, 1.85)


static func _sch_screen_space(ci: CanvasItem) -> bool:
	## Экранный текст на Control (pan/zoom в draw_set_transform). WorldRoot — отдельный crisp-path.
	if ci == null or not _sch_has_zoom(ci):
		return false
	if _sch_world_xform_of(ci):
		return false
	return true


## Текст под SchemeWorld.scale=zoom: компенсируем scale, растеризуем в экранных px.
static func _begin_world_crisp_text(ci: CanvasItem, z: float) -> void:
	var inv: float = 1.0 / maxf(z, 0.05)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(inv, inv))


static func _end_world_crisp_text(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _text(ci: CanvasItem, el, font: Font, local: Vector2, text: String, size: int, color: Color, vertical: bool = false) -> void:
	if font == null or text == "":
		return
	# Чёткий текст: либо screen-space на Control, либо компенсация parent scale на SchemeWorld.
	var world := to_world(el, local)
	var z: float = 1.0
	var pan := Vector2.ZERO
	var screen_space: bool = _sch_screen_space(ci)
	var world_crisp: bool = _sch_has_zoom(ci) and _sch_world_xform_of(ci)
	if screen_space or world_crisp:
		z = maxf(_sch_zoom_of(ci), 0.05)
	if screen_space:
		pan = _sch_pan_of(ci)
	var fs: int = maxi(size, 9)
	if screen_space or world_crisp:
		fs = maxi(int(round(float(size) * z)), 9)
	var col := _resolve_ink(color)
	var halo := Color(1, 1, 1, 0.88) if col.r + col.g + col.b < 1.5 else Color(0.08, 0.1, 0.12, 0.5)
	var rot := -PI * 0.5 if vertical else 0.0
	if vertical:
		# origin в локали слоя; при world_crisp scale=1/z → экранный px без блюра.
		var v_origin: Vector2 = pan + world * z if screen_space else world
		var v_scale: Vector2 = Vector2(1.0 / z, 1.0 / z) if world_crisp else Vector2.ONE
		if screen_space:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ci.draw_set_transform(v_origin, rot, v_scale)
		ci.draw_string(font, Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, Vector2(-1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if screen_space:
			ci.draw_set_transform(pan, 0.0, Vector2(z, z))
		else:
			_end_world_crisp_text(ci)
	else:
		var pos: Vector2 = world
		if screen_space:
			pos = pan + world * z
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif world_crisp:
			pos = world * z
			_begin_world_crisp_text(ci, z)
		ci.draw_string(font, pos + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, pos + Vector2(-1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if screen_space:
			ci.draw_set_transform(pan, 0.0, Vector2(z, z))
		elif world_crisp:
			_end_world_crisp_text(ci)


static func tag_default_local(el, font: Font = null, size: int = 13) -> Vector2:
	# По центру над элементом, с небольшим зазором (без налезания на УГО).
	var wh := _label_text_size_world(null, font, str(el.tag), size)
	var box := _symbol_tag_anchor_local(el)
	var gap: float = 4.0
	# Baseline над верхом силуэта: draw_string растёт вверх от baseline.
	return Vector2(box.get_center().x - wh.x * 0.5, box.position.y - gap)


static func tag_pos_local(el, font: Font = null, size: int = 13) -> Vector2:
	var off: Vector2 = el.tag_offset if el.get("tag_offset") != null else Vector2.ZERO
	if typeof(off) != TYPE_VECTOR2:
		off = Vector2.ZERO
	return tag_default_local(el, font, size) + off


static func tag_world_box(el, font: Font = null, size: int = 13) -> Rect2:
	var pos := tag_pos_local(el, font, size)
	var wh := _label_text_size_world(null, font, str(el.tag), size)
	return _label_world_box(el, pos, wh, false)


## Расставить подпись: справа → CCW, без наложения на тела/жилы/другие подписи.
static func auto_tag_offset(
	el, font: Font, size: int, body_rects: Array, wire_paths: Array, occupied: Array
) -> Vector2:
	if el == null or str(el.tag) == "":
		return Vector2.ZERO
	var wh: Vector2 = _label_text_size_world(null, font, str(el.tag), size)
	var box_l: Rect2 = _symbol_tag_anchor_local(el)
	var box_w: Rect2 = _label_world_box(el, box_l.position, box_l.size, false)
	if box_w.size.x < 0.5:
		box_w = world_bounds(el)
	var cx: Vector2 = box_w.get_center()
	var rad0: float = maxf(box_w.size.x, box_w.size.y) * 0.5 + 6.0
	var best_off: Vector2 = Vector2.ZERO
	var found: bool = false
	for ring in 4:
		var rad: float = rad0 + float(ring) * SCH_GRID
		# a=0 справа, далее CCW (в экранных координатах: cos, −sin).
		for step in 16:
			var a: float = float(step) * TAU / 16.0
			var dir: Vector2 = Vector2(cos(a), -sin(a))
			var world_tl: Vector2 = cx + dir * rad - wh * 0.5
			var lab: Rect2 = Rect2(world_tl, wh).grow(2.0)
			if _label_rect_hits_bodies(lab, body_rects, int(el.id)):
				continue
			if _label_rect_hits_wires(lab, wire_paths, 4.0):
				continue
			if _label_rect_hits_occupied(lab, occupied):
				continue
			# offset в локали: world → local относительно default.
			var want_local: Vector2 = to_local(el, world_tl)
			var def_local: Vector2 = tag_default_local(el, font, size)
			best_off = (want_local - def_local).snapped(Vector2(2, 2))
			found = true
			occupied.append(lab)
			break
		if found:
			break
	return best_off


static func _label_rect_hits_bodies(lab: Rect2, body_rects: Array, skip_id: int) -> bool:
	for item in body_rects:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if int(item.get("id", -1)) == skip_id:
			continue
		var r: Rect2 = item.get("rect", Rect2()) as Rect2
		if r.intersects(lab):
			return true
	return false


static func _label_rect_hits_wires(lab: Rect2, wire_paths: Array, min_dist: float) -> bool:
	var c: Vector2 = lab.get_center()
	for path_v in wire_paths:
		var pts: PackedVector2Array = path_v as PackedVector2Array
		for i in range(pts.size() - 1):
			if _dist_point_to_seg(c, pts[i], pts[i + 1]) < min_dist:
				return true
			# Грубая проверка концов сегмента в подписи.
			if lab.has_point(pts[i]) or lab.has_point(pts[i + 1]):
				return true
	return false


static func _label_rect_hits_occupied(lab: Rect2, occupied: Array) -> bool:
	for r in occupied:
		if (r as Rect2).intersects(lab):
			return true
	return false


static func _dist_point_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var L2: float = ab.length_squared()
	if L2 < 1.0e-8:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / L2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func tag_hit(el, world: Vector2, zoom: float, font: Font = null, size: int = 13) -> bool:
	if str(el.tag) == "":
		return false
	# Умеренный pad: крупный наезжал на корпус и перехватывал select/move.
	var pad := 4.0 / maxf(zoom, 0.35)
	return tag_world_box(el, font, size).grow(pad).has_point(world)


## Попадание в сам текст подписи (без pad) — приоритетнее корпуса/рамки.
static func tag_text_hit(el, world: Vector2, font: Font = null, size: int = 13) -> bool:
	if str(el.tag) == "":
		return false
	return tag_world_box(el, font, size).has_point(world)


static func _source_tri_hit(local: Vector2, inflate: float = 0.0) -> bool:
	var tip := Vector2(SRC_TIP_X, 0.0)
	var up := Vector2(SRC_TIP_X - SRC_DEPTH, -SRC_HALF_H)
	var down := Vector2(SRC_TIP_X - SRC_DEPTH, SRC_HALF_H)
	if inflate > 0.0:
		var c: Vector2 = (tip + up + down) / 3.0
		tip = c + (tip - c).normalized() * ((tip - c).length() + inflate)
		up = c + (up - c).normalized() * ((up - c).length() + inflate)
		down = c + (down - c).normalized() * ((down - c).length() + inflate)
	return Geometry2D.is_point_in_polygon(local, PackedVector2Array([tip, down, up]))


static func _symbol_body_local(el) -> Rect2:
	if el.kind == "valve":
		var n := _valve_positions_count(el)
		var body_w := float(n) * VALVE_SQ
		var slide := _valve_slide_x(el)
		return Rect2(-body_w * 0.5 + slide, -VALVE_SQ * 0.5, body_w, VALVE_SQ)
	if el.kind == "cylinder":
		return Rect2(BODY_L, BODY_T, BODY_R - BODY_L, BODY_B - BODY_T)
	if el.kind == "source":
		return Rect2(SRC_TIP_X - SRC_DEPTH, -SRC_HALF_H, SRC_DEPTH, SRC_HALF_H * 2.0)
	if el.kind == "electro":
		return ElectroSym.local_bounds(el)
	if el.kind == "coil":
		return _coil_local_bounds()
	if el.kind == "junction":
		return _junction_local_bounds(el)
	if el.kind == "sensor":
		return _sensor_local_bounds(el)
	if el.kind == "opto_tip":
		return _opto_tip_local_bounds()
	return Rect2(-20, -20, 40, 40)


static func _symbol_tag_anchor_local(el) -> Rect2:
	# Габарит для якоря подписи: корпус + верхние отростки (без органов слева/справа).
	if el.kind == "valve":
		# Без slide — иначе подпись едет вместе с золотником при срабатывании.
		var n := _valve_positions_count(el)
		var body_w := float(n) * VALVE_SQ
		var stub := _valve_stub_len(el, "2") if _valve_has_top_ports(el) else 0.0
		var y0 := -VALVE_SQ * 0.5 - stub
		return Rect2(-body_w * 0.5, y0, body_w, VALVE_SQ + stub)
	if el.kind == "cylinder":
		return Rect2(BODY_L, BODY_T - 2.0, BODY_R - BODY_L, (BODY_B - BODY_T) + 2.0)
	if el.kind == "source":
		return Rect2(SRC_TIP_X - SRC_DEPTH, -SRC_HALF_H - 1.0, SRC_DEPTH, SRC_HALF_H * 2.0 + 2.0)
	if el.kind == "electro":
		# Не врезать якорь внутрь УГО (trim 8 раньше сажал HL1 на лампу).
		var b: Rect2 = ElectroSym.local_bounds(el)
		var trim: float = 2.0
		return Rect2(b.position.x, b.position.y + trim, b.size.x, maxf(b.size.y - trim, 8.0))
	if el.kind == "coil":
		return _coil_local_bounds().grow_individual(0, 1, 0, 0)
	if el.kind == "junction":
		return _junction_local_bounds(el).grow_individual(0, 1, 0, 0)
	if el.kind == "sensor":
		return _sensor_local_bounds(el)
	if el.kind == "opto_tip":
		return _opto_tip_local_bounds()
	return _symbol_body_local(el)


static func _draw_element_tag(ci: CanvasItem, el, font: Font, size: int = 13, selected: bool = false) -> void:
	if _library_preview or font == null:
		return
	var text := str(el.tag)
	if text == "":
		return
	var pos := tag_pos_local(el, font, size)
	# Цвет темы, не ink/давление УГО — иначе при Play подпись красится вместе с трубкой.
	_text_tag(ci, el, font, pos, text, size)
	# При выборе — лёгкая рамка зоны подписи, чтобы было ясно: её можно тащить.
	if selected and _sch_has_zoom(ci):
		var box := tag_world_box(el, font, size).grow(3.0)
		ci.draw_rect(box, Color(0.16, 0.46, 0.86, 0.35), false, 1.0, true)


## Подпись элемента: фиксированный цвет темы, без _resolve_ink и без белой окантовки в dark.
static func _text_tag(ci: CanvasItem, el, font: Font, local: Vector2, text: String, size: int) -> void:
	if font == null or text == "":
		return
	var world := to_world(el, local)
	var z: float = 1.0
	var pan := Vector2.ZERO
	var screen_space: bool = _sch_screen_space(ci)
	var world_crisp: bool = _sch_has_zoom(ci) and _sch_world_xform_of(ci)
	if screen_space or world_crisp:
		z = maxf(_sch_zoom_of(ci), 0.05)
	if screen_space:
		pan = _sch_pan_of(ci)
	var pos: Vector2 = world
	if screen_space:
		pos = pan + world * z
	elif world_crisp:
		pos = world * z
	var fs: int = maxi(size, 9)
	if screen_space or world_crisp:
		fs = maxi(int(round(float(size) * z)), 9)
	var col: Color = UiTheme.schematic_label()
	var halo: Color = UiTheme.schematic_label_halo()
	if screen_space:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif world_crisp:
		_begin_world_crisp_text(ci, z)
	if not UiTheme.dark:
		ci.draw_string(font, pos + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
		ci.draw_string(font, pos + Vector2(-1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, halo)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if screen_space:
		ci.draw_set_transform(pan, 0.0, Vector2(z, z))
	elif world_crisp:
		_end_world_crisp_text(ci)


static func element_tooltip(el, hover_port: String = "", show_values: bool = false, hover_part: String = "") -> String:
	# Только то, что под курсором — не весь список портов элемента.
	if hover_port != "":
		return _port_tooltip_line(el, hover_port, show_values)
	if hover_part != "":
		return _part_tooltip_line(hover_part)
	return ""


static func _port_tooltip_line(el, port_name: String, show_values: bool) -> String:
	var line := ""
	match str(el.kind):
		"valve":
			if port_name == "12" or port_name == "14":
				line = port_name
			else:
				line = _valve_iso_label(port_name)
			if show_values and el.get("port_press") != null:
				var pp = el.port_press.get(port_name, 101325.0)
				line += "  ·  %s бар" % bar_text(float(pp))
		"cylinder":
			line = "Поршень" if port_name == "cap" else ("Шток" if port_name == "rod" else port_name)
			if show_values:
				var pressure: float = el.p_cap if port_name == "cap" else el.p_rod
				line += "  ·  %s бар" % bar_text(pressure)
		"source":
			line = "Выход"
			if show_values:
				line += "  ·  %.2f бар" % float(el.pressure_bar)
		"junction":
			line = port_name
			if show_values:
				var pj := float(el.p_cap) if el.get("p_cap") != null else 101325.0
				line += "  ·  %s бар" % bar_text(pj)
		"coil", "electro":
			line = port_name
		_:
			line = port_name
	return line


static func _part_tooltip_line(part: String) -> String:
	match part:
		"body":
			return "Корпус"
		"op_left":
			return "Орган слева"
		"op_right":
			return "Орган справа"
		"port_3":
			return "3(R1)"
		"port_5":
			return "5(R2)"
		"exhaust_fit":
			return "Выхлоп"
		"piston":
			return "Поршень / диаметр"
		"rod":
			return "Шток / каретка"
		"cush_cap":
			return "Демпфирование со стороны поршня"
		"cush_rod":
			return "Демпфирование со стороны штока"
		"spring":
			return "Пружина"
		"brake":
			return "Тормоз / стопор"
		"mount":
			return "Крепление"
		"guide":
			return "Направляющая"
		"bump_end":
			return "Упоры каретки"
		"tip":
			return "Наконечник штока"
		_:
			if part.begins_with("cell_"):
				return "Клетка %d" % (int(part.substr(5)) + 1)
			return part


static func _label_text_size_world(ci: CanvasItem, font: Font, text: String, size: int) -> Vector2:
	# Размер для раскладки — в мировых ед. по логическому size (без min 9px/z),
	# иначе при мелком zoom боксы раздуваются и подписи «улетают».
	var fs := maxi(size, 9)
	var px := Vector2(float(text.length()) * 6.2, 11.0)
	if font != null:
		px = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	return Vector2(maxf(px.x, 6.0), maxf(px.y, 8.0))


static func _label_world_box(el, local: Vector2, wh: Vector2, vertical: bool = false) -> Rect2:
	var origin := to_world(el, local)
	var pad := 2.5
	if vertical:
		# После −90°: длина текста вверх (−Y), высота глифа вправо (+X).
		return Rect2(origin + Vector2(-pad, -wh.x - pad), Vector2(wh.y + pad * 2.0, wh.x + pad * 2.0))
	return Rect2(origin + Vector2(-pad, -wh.y - pad), Vector2(wh.x + pad * 2.0, wh.y + pad * 2.0))


static func _label_boxes(_ci: CanvasItem) -> Array:
	if _sch_ctx_active:
		return _sch_ctx_label_boxes
	if _ci != null and _ci.has_meta("sch_label_boxes"):
		return _ci.get_meta("sch_label_boxes") as Array
	if _ci != null:
		_ci.set_meta("sch_label_boxes", [])
		return _ci.get_meta("sch_label_boxes") as Array
	return []


static func _register_label_box(ci: CanvasItem, box: Rect2) -> void:
	_label_boxes(ci).append(box)


static func _box_hits_obstacles(ci: CanvasItem, el, box: Rect2) -> bool:
	if _world_rect_hits_wires(box, _sch_wires_of(ci)):
		return true
	# Корпус/органы УГО (без зоны портовых отростков — подписи живут сбоку от них).
	var body := _symbol_keepout_world(el)
	if body.intersects(box):
		return true
	for other in _label_boxes(ci):
		if other is Rect2 and (other as Rect2).intersects(box):
			return true
	return false


static func _symbol_keepout_world(el) -> Rect2:
	# Корпус клеток (без органов/отростков) — подписи живут сбоку от ножек.
	if el.kind == "valve":
		var n := _valve_positions_count(el)
		var body_w := float(n) * VALVE_SQ
		var slide := _valve_slide_x(el)
		var x0 := -body_w * 0.5 + slide
		var x1 := body_w * 0.5 + slide
		var y0 := -VALVE_SQ * 0.5
		var y1 := VALVE_SQ * 0.5
		return _local_rect_world(el, Rect2(x0, y0, x1 - x0, y1 - y0))
	if el.kind == "cylinder":
		return _local_rect_world(el, Rect2(BODY_L, BODY_T, BODY_R - BODY_L, BODY_B - BODY_T))
	if el.kind == "source":
		return _local_rect_world(el, Rect2(SRC_TIP_X - SRC_DEPTH, -SRC_HALF_H, SRC_DEPTH, SRC_HALF_H * 2.0))
	return world_bounds(el).grow(-4.0)


static func _label_candidate_ok(ci: CanvasItem, el, box: Rect2, stub_box: Rect2, check_keepout: bool = true) -> bool:
	if stub_box.intersects(box):
		return false
	if check_keepout and _symbol_keepout_world(el).intersects(box):
		return false
	if _world_rect_hits_wires(box, _sch_wires_of(ci)):
		return false
	for other in _label_boxes(ci):
		if other is Rect2 and (other as Rect2).intersects(box):
			return false
	return true


static func _port_tip_extent_y(tip: Vector2, edge: Vector2) -> float:
	if tip.y - edge.y > VALVE_M * 1.1:
		var m := valve_muffler_mark_metrics()
		return tip.y + float(m["gap"]) + float(m["rect_w"]) + float(m["triangle_h"])
	return tip.y


static func _place_valve_port_label(ci: CanvasItem, el, font: Font, tip: Vector2, edge: Vector2, text: String, size: int, name: String) -> Dictionary:
	# Всегда горизонталь ВПЛОТНУЮ слева/справа от оси порта (как «E» у кнопки).
	# Без вертикали и без улёта под глушитель — collision только слегка сдвигает по Y.
	var wh := _label_text_size_world(ci, font, text, size)
	var top_port := tip.y < edge.y - 0.5
	var side_port := absf(tip.y - edge.y) < 0.5
	var muffler := tip.y - edge.y > VALVE_M * 1.1
	var extent_y := _port_tip_extent_y(tip, edge)
	var gap := 5.0
	var y: float
	if side_port:
		y = tip.y + wh.y * 0.35
	elif top_port:
		# Baseline у конца отростка — строка рядом с линией, не над корпусом.
		y = tip.y + wh.y * 0.35
	elif muffler:
		# Середина глушителя по высоте.
		y = lerpf(tip.y, extent_y, 0.42) + wh.y * 0.35
	else:
		y = lerpf(edge.y, tip.y, 0.55) + wh.y * 0.35
	var prefer_left := _port_prefer_left(name)
	var x: float = (tip.x - gap - wh.x) if prefer_left else (tip.x + gap)
	# Узкий коридор по Y у того же x — не уезжаем к соседнему порту.
	var best := Vector2(x, y)
	var found := false
	for dy in [0.0, -6.0, 6.0, -12.0, 12.0, -18.0, 18.0]:
		var cand := Vector2(x, y + dy)
		# Держим подпись в полосе отростка/глушителя.
		if top_port and cand.y > edge.y - 2.0:
			continue
		if (not top_port) and (not side_port) and cand.y < edge.y + 4.0:
			continue
		if muffler and cand.y > extent_y + 2.0:
			continue
		var box := _label_world_box(el, cand, wh, false)
		var hits_other := false
		for other in _label_boxes(ci):
			if other is Rect2 and (other as Rect2).intersects(box):
				hits_other = true
				break
		if hits_other:
			continue
		best = cand
		found = true
		break
	if not found:
		# Запасная сторона, всё ещё горизонталь у оси.
		var x2: float = (tip.x + gap) if prefer_left else (tip.x - gap - wh.x)
		best = Vector2(x2, y)
	_register_label_box(ci, _label_world_box(el, best, wh, false))
	return {"pos": best, "vertical": false}


static func _place_label_local(ci: CanvasItem, el, font: Font, tip: Vector2, edge: Vector2, text: String, size: int, prefer_left: bool) -> Dictionary:
	# Сбоку от оси порта. Если горизонтально не влезает — вертикаль (−90° влево).
	# Нижние порты 5/3 плотные (~VALVE_SQ/3) — не даём подписи уезжать к соседнему порту.
	var wh := _label_text_size_world(ci, font, text, size)
	var gap := 9.0
	var top_port := tip.y < edge.y - 0.5
	var side_port := absf(tip.y - edge.y) < 0.5
	var bottom_port := (not top_port) and (not side_port)
	var y_h: float
	var stub_half := 3.5
	var body_bot := VALVE_SQ * 0.5
	var body_top := -VALVE_SQ * 0.5
	var max_dx := 80.0
	var muffler := tip.y - edge.y > VALVE_M * 1.1
	if el.kind == "valve":
		if side_port:
			y_h = tip.y + wh.y * 0.35
			max_dx = VALVE_OP * 0.55
		elif top_port:
			y_h = minf(tip.y + maxf(wh.y * 0.4, 4.0), body_top - 3.0)
			gap = 10.0
			max_dx = VALVE_SQ * 0.45
		else:
			# Узкий зазор: слоты 1/3/5 на одной клетке. Вертикаль — не на оси линии.
			gap = 10.0
			max_dx = VALVE_SQ * 0.28
			stub_half = 5.0
			if muffler:
				var m := valve_muffler_mark_metrics()
				gap = maxf(gap, float(m["rect_h"]) * 0.55 + 6.0)
				stub_half = maxf(stub_half, float(m["rect_h"]) * 0.5 + 2.0)
			# Подпись ниже корпуса и не выше tip; при коротком отростке — у tip.
			var y_lo := body_bot + 4.0 + wh.y * 0.15
			var y_hi := tip.y + (2.0 if not muffler else 0.0)
			y_h = lerpf(edge.y, tip.y, 0.65) + wh.y * 0.1
			if y_lo <= y_hi:
				y_h = clampf(y_h, y_lo, y_hi)
			else:
				y_h = tip.y + wh.y * 0.35
	else:
		y_h = (tip.y + edge.y) * 0.5 + (2.0 if top_port else 4.0)
		gap = 8.0
	var stub_h := absf(tip.y - edge.y) + 14.0
	if muffler:
		var mm := valve_muffler_mark_metrics()
		stub_h += float(mm["gap"]) + float(mm["rect_w"]) + float(mm["triangle_h"])
	var stub_box := _local_rect_world(el, Rect2(tip.x - stub_half, minf(edge.y, tip.y) - 2.0, stub_half * 2.0, stub_h))
	var sides: Array = [prefer_left, not prefer_left]
	# Нижние порты: сначала вертикаль у оси (иначе длинный «1(P)» уезжает к соседу).
	# Якорь НИЖЕ tip: строка вверх, но верх текста остаётся под корпусом (не в keepout).
	if bottom_port and el.kind == "valve":
		var gy_clear := body_bot + 4.0 + wh.x
		var gy_tip := tip.y + 2.0
		if muffler:
			var m2 := valve_muffler_mark_metrics()
			gy_tip = tip.y + float(m2["gap"]) + float(m2["rect_w"]) + float(m2["triangle_h"]) + 2.0
		var gy_base := maxf(gy_clear, gy_tip)
		for side_left in sides:
			for extra_v in [0.0, 3.0, 7.0, 12.0]:
				var gx: float = (tip.x - gap - wh.y - extra_v) if bool(side_left) else (tip.x + gap + extra_v)
				if absf(gx - tip.x) > max_dx + wh.y:
					continue
				for gy in [gy_base, gy_tip, tip.y + wh.x * 0.5]:
					var vcand := Vector2(gx, float(gy))
					var vbox := _label_world_box(el, vcand, wh, true)
					if not _label_candidate_ok(ci, el, vbox, stub_box):
						continue
					_register_label_box(ci, vbox)
					return {"pos": vcand, "vertical": true}
	# Горизонталь — только пока центр подписи близко к оси порта.
	for side_left in sides:
		for extra in [0.0, 4.0, 8.0, 14.0, 22.0]:
			var x: float = (tip.x - gap - wh.x - extra) if bool(side_left) else (tip.x + gap + extra)
			var mid_x := x + wh.x * 0.5
			if absf(mid_x - tip.x) > max_dx:
				continue
			var cand := Vector2(x, y_h)
			var box := _label_world_box(el, cand, wh, false)
			if not _label_candidate_ok(ci, el, box, stub_box):
				continue
			_register_label_box(ci, box)
			return {"pos": cand, "vertical": false}
	# Вертикаль для верхних/боковых (и запас для нижних).
	if not bottom_port or el.kind != "valve":
		for side_left in sides:
			for extra_v in [0.0, 6.0, 14.0, 22.0]:
				var gx3: float = (tip.x - gap - wh.y - extra_v) if bool(side_left) else (tip.x + gap + extra_v)
				if absf(gx3 - tip.x) > max_dx + wh.y:
					continue
				var vcand3 := Vector2(gx3, tip.y - 1.0)
				var vbox3 := _label_world_box(el, vcand3, wh, true)
				if not _label_candidate_ok(ci, el, vbox3, stub_box):
					continue
				_register_label_box(ci, vbox3)
				return {"pos": vcand3, "vertical": true}
	# Forced: вертикаль у оси порта (не у соседнего), текст под корпусом.
	var forced_x: float = (tip.x - maxf(gap, 6.0) - wh.y) if prefer_left else (tip.x + maxf(gap, 6.0))
	var forced_y := tip.y + 2.0
	if bottom_port and el.kind == "valve":
		forced_y = maxf(body_bot + 4.0 + wh.x, tip.y + 2.0)
	var forced := Vector2(forced_x, forced_y)
	_register_label_box(ci, _label_world_box(el, forced, wh, true))
	return {"pos": forced, "vertical": true}


static func _place_free_label_local(ci: CanvasItem, el, font: Font, local: Vector2, text: String, size: int) -> Vector2:
	# Для тега/давления: только малый сдвиг вбок/вниз — не улетать вверх от УГО.
	var wh := _label_text_size_world(ci, font, text, size)
	var candidates: Array[Vector2] = [
		local,
		local + Vector2(-4.0, 0.0),
		local + Vector2(4.0, 0.0),
		local + Vector2(-8.0, 0.0),
		local + Vector2(0.0, 6.0),
		local + Vector2(-4.0, 6.0),
		local + Vector2(4.0, 6.0),
	]
	for cand in candidates:
		var box := _label_world_box(el, cand, wh)
		if _box_hits_obstacles(ci, el, box):
			continue
		_register_label_box(ci, box)
		return cand
	_register_label_box(ci, _label_world_box(el, local, wh))
	return local


static func _world_rect_hits_wires(box: Rect2, wires) -> bool:
	if wires == null:
		return false
	for path in wires:
		if typeof(path) != TYPE_PACKED_VECTOR2_ARRAY and not (path is PackedVector2Array):
			continue
		var pts: PackedVector2Array = path
		for i in range(pts.size() - 1):
			if _segment_hits_rect(pts[i], pts[i + 1], box):
				return true
	return false


static func _segment_hits_rect(a: Vector2, b: Vector2, box: Rect2) -> bool:
	if box.has_point(a) or box.has_point(b):
		return true
	var expanded := box.grow(2.0)
	var corners := [
		expanded.position,
		expanded.position + Vector2(expanded.size.x, 0),
		expanded.position + expanded.size,
		expanded.position + Vector2(0, expanded.size.y),
	]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-8:
		return expanded.has_point(a)
	var t := clampf((expanded.get_center() - a).dot(ab) / len2, 0.0, 1.0)
	return expanded.has_point(a + ab * t)


static func _port_prefer_left(name: String) -> bool:
	match name:
		# 1(P) — слева от центрального отростка (между 3 и 1), иначе уезжает к 5.
		"1", "2", "3", "12":
			return true
		"4", "5", "14":
			return false
		_:
			return true


# --- Пневмораспределитель ISO 1219-1 ---


static func _valve_positions_count(el) -> int:
	var v = el.get("valve_positions")
	return maxi(int(v if v != null else 2), 2)


static func _valve_local_bounds(el) -> Rect2:
	# Текущий вид (с учётом slide), без запаса «на все позиции» — иначе рамка огромная.
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var slide := _valve_slide_x(el)
	var x0 := -body_w * 0.5 + minf(slide, 0.0) - VALVE_OP - 14.0
	var x1 := body_w * 0.5 + maxf(slide, 0.0) + VALVE_OP + 14.0
	x0 = minf(x0, -body_w * 0.5 - 10.0)
	x1 = maxf(x1, body_w * 0.5 + 10.0)
	var top_ports := _valve_has_top_ports(el)
	var top := VALVE_SQ * 0.5 + (18.0 if top_ports else 10.0)
	var bot := VALVE_SQ * 0.5 + 38.0
	return Rect2(x0, -top, x1 - x0, top + bot)


static func _valve_anchor_index(el) -> int:
	## Неподвижная клетка под внешними портами (покой / центр для 3 поз.).
	var n := _valve_positions_count(el)
	if n == 3:
		return 1
	return clampi(int(el.get("rest_pos") if el.get("rest_pos") != null else 0), 0, n - 1)


static func _valve_slide_x(el) -> float:
	## Сдвиг клеток и органов: активная клетка заезжает под неподвижные порты.
	# Отсечной: плавный slide по opening (0=закрыт/покой, 1=открыт).
	if str(el.get("kind") if el.get("kind") != null else "") == "accessory" \
			and str(el.get("accessory_class") if el.get("accessory_class") != null else "") == "shutoff":
		var open_z: float = clampf(float(el.get("opening") if el.get("opening") != null else 0.0), 0.0, 1.0)
		return float(_valve_anchor_index(el)) * VALVE_SQ - open_z * VALVE_SQ
	var n := _valve_positions_count(el)
	var pos := clampi(int(el.get("valve_pos") if el.get("valve_pos") != null else 0), 0, n - 1)
	return float(_valve_anchor_index(el) - pos) * VALVE_SQ


static func _valve_has_top_ports(el) -> bool:
	# AS PortConfiguration Pneumatique: у 2…5 линий рабочие порты на HAUT.
	return int(el.get("valve_ways") if el.get("valve_ways") != null else 5) >= 2


static func _valve_port_is_top(el, name: String) -> bool:
	# Сетка AS: 2(A)/4(B) — HAUT; 1(P)/3(R)/5(R2) — BAS.
	return name == "2" or name == "4"


static func _valve_working_ports(el) -> PackedStringArray:
	var ways := int(el.get("valve_ways") if el.get("valve_ways") != null else 5)
	match ways:
		2:
			return PackedStringArray(["1", "2"])
		3:
			return PackedStringArray(["1", "2", "3"])
		4:
			return PackedStringArray(["1", "2", "3", "4"])
		_:
			return PackedStringArray(["3", "2", "1", "4", "5"])


static func _valve_tiroir_taille(el) -> int:
	# AS ValveConfigurator/PortConfiguration.xml — Pneumatique.tailleTiroir.
	var ways := int(el.get("valve_ways") if el.get("valve_ways") != null else 5)
	return 6 if ways >= 5 else 4


static func _valve_port_slot(el, name: String) -> int:
	# Слоты AS Pneumatique (VDT2…VDT5), см. out/taxonomy/distributeur.json.
	var ways := int(el.get("valve_ways") if el.get("valve_ways") != null else 5)
	match ways:
		2:
			return 2
		3:
			match name:
				"1", "2":
					return 1
				"3":
					return 3
		4:
			match name:
				"1", "2":
					return 1
				"3", "4":
					return 3
		_:
			match name:
				"3", "2":
					return 1
				"1":
					return 3
				"4", "5":
					return 5
	return 2


static func _valve_attach_square(el) -> Vector2:
	# Порты неподвижны: всегда на якорной клетке (покой / центр).
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var anchor := _valve_anchor_index(el)
	var xa := x0 + float(anchor) * VALVE_SQ
	return Vector2(xa, xa + VALVE_SQ)


static func _valve_port_x_in(el, name: String, xa: float, xb: float) -> float:
	# x = xa + (slot / taille) * width — формула слотов CFGDistributeur / PortConfiguration.
	# Округляем к SCH_GRID, чтобы оси портов совпадали с сеткой/проводами.
	var taille := float(_valve_tiroir_taille(el))
	var slot := float(_valve_port_slot(el, name))
	var raw := xa + (slot / taille) * (xb - xa)
	return snappedf(raw, SCH_GRID)


static func _valve_port_x(el, name: String) -> float:
	var sq := _valve_attach_square(el)
	return _valve_port_x_in(el, name, sq.x, sq.y)


static func _valve_stub_len(el = null, name: String = "") -> float:
	# Длины кратны SCH_GRID — tip порта лежит на сетке при position на сетке.
	if el != null and name != "":
		var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
		if ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler":
			return SCH_GRID * 3.0 # 30
	return SCH_GRID * 2.0 # 20


static func _valve_ports(el) -> Array:
	## Только каналы для трубки. Глушитель и чистый solenoid — без точек.
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var list: Array = []
	for name in _valve_working_ports(el):
		if ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler":
			continue
		list.append(_valve_port_desc(el, name))
	if ValveCat._needs_pilot(el, true):
		list.append(_valve_pilot_port_desc(el, true))
	if ValveCat._needs_pilot(el, false):
		list.append(_valve_pilot_port_desc(el, false))
	return list


static func _valve_port_desc(el, name: String) -> Dictionary:
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var y0 := -VALVE_SQ * 0.5
	var y1 := VALVE_SQ * 0.5
	var top := _valve_port_is_top(el, name)
	var px := _valve_port_x(el, name)
	var stub := _valve_stub_len(el, name)
	var tip_y := (y0 - stub) if top else (y1 + stub)
	return {
		"name": name,
		"local": Vector2(px, tip_y),
		"normal": Vector2.UP if top else Vector2.DOWN,
		"edge": Vector2(px, y0 if top else y1),
	}


static func _valve_pilot_port_desc(el, left: bool) -> Dictionary:
	## 12/14 на органе: органы едут вместе с клетками (slide), точка совпадает с отрисовкой.
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var y1 := VALVE_SQ * 0.5
	var slide := _valve_slide_x(el)
	var body_x := (x0 if left else (x0 + body_w)) + slide
	var sign := -1.0 if left else 1.0
	var kind := str(el.op_left) if left else str(el.op_right)
	var geom := _valve_pilot_frame_geom(body_x, sign, y1, kind == "solenoid_pilot")
	return {
		"name": "12" if left else "14",
		"local": geom["port"],
		"normal": Vector2.LEFT if left else Vector2.RIGHT,
		"edge": geom["port"],
	}


static func _valve_pilot_frame_geom(body_x: float, sign: float, body_bot: float, stacked_on_coil: bool) -> Dictionary:
	## Рамка пилота = размер катушки. У solenoid_pilot — над катушкой; у pilot — внизу.
	var bot: float
	var top: float
	if stacked_on_coil:
		bot = body_bot - VALVE_SOL_H
		top = body_bot - 2.0 * VALVE_SOL_H
	else:
		bot = body_bot
		top = body_bot - VALVE_SOL_H
	var x_inner := body_x
	var x_outer := body_x + sign * VALVE_SOL_W
	var xa := minf(x_inner, x_outer)
	var xb := maxf(x_inner, x_outer)
	var mid := (top + bot) * 0.5
	# Треугольник ≈ ½ ширины рамки: основание снаружи, остриё к корпусу.
	var tri_w := VALVE_SOL_W * 0.5
	var base_x := x_outer
	var tip_x := x_outer - sign * tri_w
	var port := Vector2(base_x, mid)
	return {
		"top": top, "bottom": bot, "left": xa, "right": xb,
		"mid": mid, "tip_x": tip_x, "base_x": base_x, "port": port,
		"x_inner": x_inner, "x_outer": x_outer,
	}


static func _valve_zones(el) -> Array:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var slide := _valve_slide_x(el)
	var y0 := -VALVE_SQ * 0.5
	var zones: Array = [
		# Крупная зона корпуса — проигрывает клеткам по площади (part_hit берёт меньшую).
		{"id": "body", "rect": Rect2(x0 + slide, y0, body_w, VALVE_SQ)},
		{"id": "op_left", "rect": Rect2(x0 - VALVE_OP + slide, y0, VALVE_OP, VALVE_SQ)},
		{"id": "op_right", "rect": Rect2(x0 + body_w + slide, y0, VALVE_OP, VALVE_SQ)},
	]
	# Клетки чуть меньше корпуса — узкая кромка даёт hit «body» (линии/позиции).
	var inset := 4.0
	for i in n:
		zones.append({
			"id": "cell_%d" % i,
			"rect": Rect2(
				x0 + float(i) * VALVE_SQ + slide + inset,
				y0 + inset,
				VALVE_SQ - inset * 2.0,
				VALVE_SQ - inset * 2.0
			),
		})
	# Выхлопы 3/5 — зона линии + глушителя для hover/ПКМ.
	for name in _valve_working_ports(el):
		if not ValveCat.is_exhaust_port(name):
			continue
		var desc := _valve_port_desc(el, name)
		var tip: Vector2 = desc["local"]
		var edge: Vector2 = desc["edge"]
		var zx := minf(tip.x, edge.x) - 10.0
		var zy := minf(tip.y, edge.y) - 4.0
		var zw := absf(tip.x - edge.x) + 20.0
		var zh := absf(tip.y - edge.y) + 22.0
		var part_id := "port_3" if name == "3" else ("port_5" if name == "5" else "exhaust_fit")
		zones.append({"id": part_id, "rect": Rect2(zx, zy, maxf(zw, 20.0), maxf(zh, 24.0))})
	return zones


static func _valve_iso_label(name: String) -> String:
	match name:
		"1":
			return "1(P)"
		"2":
			return "2(A)"
		"3":
			return "3(R1)"
		"4":
			return "4(B)"
		"5":
			return "5(R2)"
		_:
			return name


static func _valve_label_offset(el, name: String) -> Vector2:
	# Сбоку от оси порта — линия связи идёт вдоль нормали и не режет текст.
	if name == "12" or name == "14":
		return Vector2(-6, -10)
	if _valve_port_is_top(el, name):
		match name:
			"2":
				return Vector2(-20, -2)
			"4":
				return Vector2(6, -2)
			_:
				return Vector2(-18, -2)
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var muffler := ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler"
	if muffler:
		match name:
			"3":
				return Vector2(-16, 2)
			"5":
				return Vector2(6, 2)
			_:
				return Vector2(-14, 2)
	match name:
		"3":
			return Vector2(-14, 2)
		"1":
			return Vector2(6, 2)
		"5":
			return Vector2(6, 2)
		_:
			return Vector2(-8, 8)


static func _draw_valve(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	hover_part: String, omit_motion: bool = false
) -> void:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	# omit_motion не вырезает корпус ПР — иначе в Run остаются только порты (дыры УГО).
	if omit_motion:
		pass
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var y0 := -VALVE_SQ * 0.5
	var y1 := VALVE_SQ * 0.5
	var slide := _valve_slide_x(el)
	# Клетки + органы смещаются; порты рисуются после — без slide.
	for i in n:
		var xa := x0 + float(i) * VALVE_SQ + slide
		var xb := xa + VALVE_SQ
		_box(ci, el, xa, y0, xb, y1, INK)
		_draw_valve_envelope(ci, el, ValveCat, i, xa, xb, y0, y1)
	_draw_valve_operator(ci, el, str(el.get("op_left") if el.get("op_left") != null else "spring"), x0 - VALVE_OP + slide, x0 + slide, y0, y1, true, font)
	_draw_valve_operator(ci, el, str(el.get("op_right") if el.get("op_right") != null else "spring"), x0 + body_w + slide, x0 + body_w + VALVE_OP + slide, y0, y1, false, font)
	# Рабочие порты неподвижны (якорь) — всегда на shell.
	for name in _valve_working_ports(el):
		var desc := _valve_port_desc(el, name)
		var tip: Vector2 = desc["local"]
		var edge: Vector2 = desc["edge"]
		var nrm: Vector2 = desc["normal"]
		_line(ci, el, edge, tip, INK, 1.5)
		var muffler := ValveCat.is_exhaust_port(name) and ValveCat.exhaust_fit(el, name) == "muffler"
		if muffler:
			_draw_valve_muffler_mark(ci, el, tip, nrm)
		else:
			_draw_port_marker(ci, el, tip, port_domain(el, name), hover_port == name)
	# Пилот 12/14: только точка на гипотенузе, без отростка.
	for port in ports(el):
		var pname := str(port["name"])
		if pname != "12" and pname != "14":
			continue
		var tip2: Vector2 = port["local"]
		_draw_port_marker(ci, el, tip2, port_domain(el, pname), hover_port == pname)
	_draw_element_tag(ci, el, font, 13, selected)


static func _draw_valve_envelope(ci: CanvasItem, el, ValveCat, pos_i: int, xa: float, xb: float, y0: float, y1: float) -> void:
	var pairs: Array = ValveCat.path_pairs(el, pos_i)
	var ports := _valve_working_ports(el)
	var connected := {}
	for pair in pairs:
		connected[str(pair[0])] = true
		connected[str(pair[1])] = true
		_draw_iso_flow(ci, el, str(pair[0]), str(pair[1]), xa, xb, y0, y1)
	for name in ports:
		if connected.has(name):
			continue
		var px := _valve_port_x_in(el, name, xa, xb)
		_draw_iso_blocked(ci, el, name, px, y0, y1)


## Одна клетка золотника для каталога (без органов/подписей).
static func draw_envelope_thumb(ci: CanvasItem, ways: int, env_id: String, ink_color: Color) -> void:
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var env: Dictionary = ValveLib.envelope(env_id)
	if env.is_empty():
		return
	begin_library_preview(ink_color)
	var el := ThumbElement.new(ways)
	var xa := -VALVE_SQ * 0.5
	var xb := VALVE_SQ * 0.5
	var y0 := -VALVE_SQ * 0.5
	var y1 := VALVE_SQ * 0.5
	_box(ci, el, xa, y0, xb, y1, ink())
	var connected := {}
	for pair in env.get("paths", []):
		if pair is Array and pair.size() >= 2:
			var a := str(pair[0])
			var b := str(pair[1])
			connected[a] = true
			connected[b] = true
			_draw_iso_flow(ci, el, a, b, xa, xb, y0, y1)
	for name in _valve_working_ports(el):
		if connected.has(name):
			continue
		var px := _valve_port_x_in(el, name, xa, xb)
		_draw_iso_blocked(ci, el, name, px, y0, y1)
	end_library_preview()


static func _draw_iso_flow(ci: CanvasItem, el, a: String, b: String, xa: float, xb: float, y0: float, y1: float) -> void:
	# Разные стороны — прямая кромка–кромка; одна сторона — П-образный канал (эталон пользователя).
	var ax := _valve_port_x_in(el, a, xa, xb)
	var bx := _valve_port_x_in(el, b, xa, xb)
	var a_top := _valve_port_is_top(el, a)
	var b_top := _valve_port_is_top(el, b)
	# Направление стрелки: к «рабочему» / второму порту (как в парах каталога).
	var from_a := true
	if a != "1" and b == "1":
		from_a = false
	elif (a == "3" or a == "5") and not (b == "3" or b == "5"):
		from_a = false
	var x0p := ax if from_a else bx
	var x1p := bx if from_a else ax
	# Каналы доходят до внешней кромки клетки (без inset — иначе «зазор» на схеме).
	if a_top and b_top:
		var depth := VALVE_SQ * 0.42
		var y_edge := y0
		var y_bridge := y0 + depth
		_line(ci, el, Vector2(x0p, y_edge - 0.85), Vector2(x0p, y_bridge), INK, 1.55)
		_line(ci, el, Vector2(x0p, y_bridge), Vector2(x1p, y_bridge), INK, 1.55)
		_valve_arrow(ci, el, Vector2(x1p, y_bridge), Vector2(x1p, y_edge))
		return
	if (not a_top) and (not b_top):
		var depth_b := VALVE_SQ * 0.42
		var y_edge_b := y1
		var y_bridge_b := y1 - depth_b
		_line(ci, el, Vector2(x0p, y_edge_b + 0.85), Vector2(x0p, y_bridge_b), INK, 1.55)
		_line(ci, el, Vector2(x0p, y_bridge_b), Vector2(x1p, y_bridge_b), INK, 1.55)
		_valve_arrow(ci, el, Vector2(x1p, y_bridge_b), Vector2(x1p, y_edge_b))
		return
	var ay := y0 if (a_top if from_a else b_top) else y1
	var by := y0 if (b_top if from_a else a_top) else y1
	_valve_arrow(ci, el, Vector2(x0p, ay), Vector2(x1p, by))


static func _valve_arrow(ci: CanvasItem, el, a: Vector2, b: Vector2) -> void:
	# Ствол чуть заходит за кромку, чтобы стык с рамкой клетки был сплошным при выкл. AA.
	var delta := b - a
	var len := delta.length()
	if len < 0.5:
		return
	var dir := delta.normalized()
	var over := 0.85
	_line(ci, el, a - dir * over, b + dir * over, INK, 1.55)
	if len < 2.0:
		return
	var side := Vector2(-dir.y, dir.x)
	_fill_poly(ci, el, PackedVector2Array([
		b,
		b - dir * 6.0 + side * 3.0,
		b - dir * 6.0 - side * 3.0,
	]), ink())


static func _draw_iso_blocked(ci: CanvasItem, el, name: String, px: float, y0: float, y1: float) -> void:
	# AS: ножка от кромки внутрь; перекладина на внутреннем конце (у нижнего порта — сверху ножки).
	var top := _valve_port_is_top(el, name)
	var edge_y := y0 if top else y1
	var stem := VALVE_SQ * 0.18
	var bar_hw := VALVE_SQ * 0.10
	var bar_y := edge_y + stem if top else edge_y - stem
	# Чуть наружу за кромку — без «просвета» у рамки.
	var edge_out := edge_y - 0.85 if top else edge_y + 0.85
	_line(ci, el, Vector2(px, edge_out), Vector2(px, bar_y), ink(), 1.55)
	_line(ci, el, Vector2(px - bar_hw, bar_y), Vector2(px + bar_hw, bar_y), ink(), 1.8)


## Геометрия метки глушителя (тесты): прямоугольник ~2:1 + треугольник наружу.
static func valve_muffler_mark_metrics() -> Dictionary:
	var h := VALVE_M * 0.42
	var w := h * 2.0
	return {
		"rect_w": w,
		"rect_h": h,
		"aspect": w / h,
		"gap": VALVE_M * 0.22,
		"triangle_h": h * 0.55,
	}


## Только глушители ПР для анимации выброса (скрыты из ports() — не точка проводки).
## Открытый штуцер 3/5 без глушителя остаётся в ports().
static func valve_atm_exhaust_ports(el) -> Array:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var out: Array = []
	if el == null or str(el.kind) != "valve":
		return out
	for name in _valve_working_ports(el):
		if not ValveCat.is_exhaust_port(name):
			continue
		if ValveCat.exhaust_fit(el, name) != "muffler":
			continue
		var desc: Dictionary = _valve_port_desc(el, name)
		var tip: Vector2 = desc["local"] as Vector2
		var nrm: Vector2 = (desc["normal"] as Vector2).normalized()
		# Остриё треугольника выброса — дальше глушителя.
		var m: Dictionary = valve_muffler_mark_metrics()
		var dist: float = float(m["gap"]) + float(m["rect_w"]) + float(m["triangle_h"])
		tip = tip + nrm * dist
		out.append({"name": name, "local": tip, "normal": nrm, "muffler": true})
	return out


static func _draw_valve_muffler_mark(ci: CanvasItem, el, tip: Vector2, normal: Vector2) -> void:
	# ISO глушитель (эталон пользователя): прямоугольник ~2:1, лабиринт 2 сверху/1 снизу, треугольник наружу.
	var n := normal.normalized()
	var side := Vector2(-n.y, n.x)
	var m := valve_muffler_mark_metrics()
	var h: float = m["rect_h"]
	var w: float = m["rect_w"]
	var gap: float = m["gap"]
	var inlet := tip + n * gap
	var x0 := gap
	var x1 := gap + w
	# Углы прямоугольника: поток вдоль n, «верх» = +side.
	var a := tip + n * x0 - side * (h * 0.5)
	var b := tip + n * x0 + side * (h * 0.5)
	var c := tip + n * x1 + side * (h * 0.5)
	var d := tip + n * x1 - side * (h * 0.5)
	_line(ci, el, tip, inlet, INK, 1.45)
	ci.draw_polyline(PackedVector2Array([
		to_world(el, a), to_world(el, b), to_world(el, c), to_world(el, d), to_world(el, a),
	]), ink(), _stroke_w(1.35), _stroke_aa())
	# Перегородки: две сверху вниз (~½H), одна снизу вверх по центру между ними.
	for frac in [0.28, 0.72]:
		var px := tip + n * lerpf(x0, x1, frac)
		_line(ci, el, px + side * (h * 0.5), px, INK, 1.25)
	var pxm := tip + n * lerpf(x0, x1, 0.5)
	_line(ci, el, pxm - side * (h * 0.5), pxm, INK, 1.25)
	# Треугольник на выходе, остриё наружу.
	var base_c := tip + n * x1
	var apex := tip + n * (x1 + float(m["triangle_h"]))
	var bh := h * 0.42
	ci.draw_polyline(PackedVector2Array([
		to_world(el, base_c - side * bh),
		to_world(el, apex),
		to_world(el, base_c + side * bh),
		to_world(el, base_c - side * bh),
	]), ink(), _stroke_w(1.35), _stroke_aa())


## Полоса органа: ВНИЗУ — низ вровень с корпусом, высота = VALVE_SOL_H.
static func _valve_op_band(_y0: float, y1: float) -> Vector2:
	return Vector2(y1 - VALVE_SOL_H, y1)


## Локальный bbox органа (тесты).
static func valve_operator_bbox(el, left: bool) -> Dictionary:
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var y1 := VALVE_SQ * 0.5
	var band := _valve_op_band(-VALVE_SQ * 0.5, y1)
	var top := band.x
	var bot := band.y
	var body_x := (x0 if left else (x0 + body_w)) + _valve_slide_x(el)
	var sign := -1.0 if left else 1.0
	var kind := str(el.op_left) if left else str(el.op_right)
	match kind:
		"solenoid":
			var x_a := body_x
			var x_b := body_x + sign * VALVE_SOL_W
			return {
				"top": top, "bottom": bot,
				"left": minf(x_a, x_b), "right": maxf(x_a, x_b),
				"kind": kind,
			}
		"solenoid_pilot":
			# Стек: пилот над катушкой, общая высота 2×SOL_H.
			var x_a := body_x
			var x_b := body_x + sign * VALVE_SOL_W
			return {
				"top": bot - 2.0 * VALVE_SOL_H, "bottom": bot,
				"left": minf(x_a, x_b), "right": maxf(x_a, x_b),
				"kind": kind,
			}
		"pilot":
			var geom := _valve_pilot_frame_geom(body_x, sign, y1, false)
			return {
				"top": geom["top"], "bottom": geom["bottom"],
				"left": geom["left"], "right": geom["right"],
				"kind": kind,
			}
		"spring":
			var x_a := body_x
			var x_b := body_x + sign * VALVE_SPR_W
			return {
				"top": top, "bottom": bot,
				"left": minf(x_a, x_b), "right": maxf(x_a, x_b),
				"kind": kind,
			}
		_:
			return {"top": top, "bottom": bot, "left": body_x, "right": body_x + sign * VALVE_M, "kind": kind}


static func _draw_valve_operator(ci: CanvasItem, el, kind: String, x0: float, x1: float, y0: float, y1: float, left: bool, font: Font = null) -> void:
	var cmd: bool = bool(el.command_left) if left else bool(el.command_right)
	var body_x := x1 if left else x0
	var sign := -1.0 if left else 1.0
	var band := _valve_op_band(y0, y1)
	var top := band.x
	var bot := band.y
	var mid := (top + bot) * 0.5
	match kind:
		"spring":
			# Полная пружина ISO: фиксированные витки на всю ширину органа.
			var x_a := body_x
			var x_b := body_x + sign * VALVE_SPR_W
			var pts := PackedVector2Array()
			const COILS := 4
			pts.append(to_world(el, Vector2(x_a, mid)))
			for i in COILS:
				var t := (float(i) + 0.5) / float(COILS)
				var y := top if i % 2 == 0 else bot
				pts.append(to_world(el, Vector2(lerpf(x_a, x_b, t), y)))
			pts.append(to_world(el, Vector2(x_b, mid)))
			ci.draw_polyline(pts, ink(), _stroke_w(1.55), _stroke_aa())
		"solenoid":
			_draw_valve_solenoid_rect(ci, el, body_x, sign, top, bot, cmd)
			if _valve_has_override(el, left):
				_draw_valve_override_btn(ci, el, body_x, sign, top, bot, cmd)
		"solenoid_pilot":
			# Снизу катушка, над ней пилот в такой же рамке.
			_draw_valve_solenoid_rect(ci, el, body_x, sign, top, bot, cmd)
			_draw_valve_pilot_box(ci, el, body_x, sign, y1, true, cmd)
			if _valve_has_override(el, left):
				_draw_valve_override_btn(ci, el, body_x, sign, top, bot, cmd)
		"pilot":
			_draw_valve_pilot_box(ci, el, body_x, sign, y1, false, cmd)
		"button":
			# ГОСТ 2.781-96 → мускульное по ГОСТ 2.721-74 п.13е: шток + квадратная головка кнопки.
			_draw_gost_pushbutton(ci, el, body_x, sign, mid, cmd)
		"plunger":
			var tip_x := body_x + sign * (VALVE_M * 0.75)
			_line(ci, el, Vector2(body_x, mid), Vector2(tip_x, mid), INK, 2.0)
			_line(ci, el, Vector2(tip_x, mid - 5.0), Vector2(tip_x, mid + 5.0), INK, 1.6)
			if cmd:
				_line(ci, el, Vector2(body_x + sign * 2.0, mid), Vector2(tip_x, mid), Color(0.25, 0.55, 0.95), 2.4)
		"roller":
			var rcx := body_x + sign * (VALVE_M * 0.6)
			_line(ci, el, Vector2(body_x, mid), Vector2(rcx - sign * 5.0, mid), INK, 1.4)
			ci.draw_arc(to_world(el, Vector2(rcx, mid)), VALVE_M * 0.33, 0.0, TAU, 18, ink(), 1.45, true)
			if cmd:
				ci.draw_arc(to_world(el, Vector2(rcx, mid)), VALVE_M * 0.2, 0.0, TAU, 14, Color(0.25, 0.55, 0.95), 2.0, true)
		_:
			pass


static func _valve_has_override(el, left: bool) -> bool:
	if left:
		return bool(el.get("override_left") if el.get("override_left") != null else true)
	return bool(el.get("override_right") if el.get("override_right") != null else true)


static func _draw_valve_override_btn(ci: CanvasItem, el, body_x: float, sign: float, top: float, bot: float, cmd: bool = false) -> void:
	# Ручной дублёр — та же нажимная кнопка ГОСТ 2.721-74 п.13е.
	var mid := (top + bot) * 0.5
	var bx0 := body_x + sign * (VALVE_SOL_W + 1.5)
	_draw_gost_pushbutton(ci, el, bx0, sign, mid, cmd)


static func _draw_gost_pushbutton(ci: CanvasItem, el, body_x: float, sign: float, mid: float, cmd: bool = false) -> void:
	# ГОСТ 2.721-74 табл.6 п.13е: головка «E» (вертикаль + три полки к аппарату) и шток связи.
	# Эталон пользователя: полки одинаковой длины, между средней полкой и штоком — зазор.
	var prong := VALVE_M * 0.50
	var half_h := VALVE_M * 0.40
	var gap := VALVE_M * 0.14
	var rod := VALVE_M * 0.58
	var spine_x := body_x + sign * (rod + gap + prong)
	var prong_x := spine_x - sign * prong
	var rod_x := prong_x - sign * gap
	var ya := mid - half_h
	var yb := mid + half_h
	_line(ci, el, Vector2(spine_x, ya), Vector2(spine_x, yb), INK, 1.7)
	_line(ci, el, Vector2(spine_x, ya), Vector2(prong_x, ya), INK, 1.7)
	_line(ci, el, Vector2(spine_x, mid), Vector2(prong_x, mid), INK, 1.7)
	_line(ci, el, Vector2(spine_x, yb), Vector2(prong_x, yb), INK, 1.7)
	_line(ci, el, Vector2(rod_x, mid), Vector2(body_x, mid), INK, 1.7)
	if cmd:
		_line(ci, el, Vector2(rod_x, mid), Vector2(body_x + sign * 2.0, mid), Color(0.25, 0.55, 0.95), 2.4)


## Хит органа/дублёра. Возвращает "left" / "right" / "".
static func operator_hit(el, world: Vector2) -> String:
	var is_shutoff: bool = str(el.kind) == "accessory" \
			and str(el.get("accessory_class") if el.get("accessory_class") != null else "") == "shutoff"
	if el.kind != "valve" and not is_shutoff:
		return ""
	var local := to_local(el, world)
	var n := _valve_positions_count(el)
	var body_w := float(n) * VALVE_SQ
	var x0 := -body_w * 0.5
	var slide := _valve_slide_x(el)
	var y0 := -VALVE_SQ * 0.5
	# Зоны органов + вынесенная кнопка дублёра снаружи катушки.
	var left_rect := Rect2(x0 - VALVE_OP + slide - 14.0, y0 - 6.0, VALVE_OP + 18.0, VALVE_SQ + 12.0)
	var right_rect := Rect2(x0 + body_w + slide - 4.0, y0 - 6.0, VALVE_OP + 18.0, VALVE_SQ + 12.0)
	var op_l := str(el.get("op_left") if el.get("op_left") != null else "spring")
	var op_r := str(el.get("op_right") if el.get("op_right") != null else "spring")
	if is_shutoff:
		op_l = "button"
		op_r = "button"
	if op_l != "spring" and op_l != "none" and left_rect.has_point(local):
		return "left"
	if op_r != "spring" and op_r != "none" and right_rect.has_point(local):
		return "right"
	return ""


static func _draw_valve_solenoid_rect(ci: CanvasItem, el, body_x: float, sign: float, top: float, bot: float, cmd: bool) -> void:
	var x_a := body_x
	var x_b := body_x + sign * VALVE_SOL_W
	var xa := minf(x_a, x_b)
	var xb := maxf(x_a, x_b)
	_box(ci, el, xa, top, xb, bot, INK)
	_line(ci, el, Vector2(xa, top), Vector2(xb, bot), INK, 1.4)
	if cmd:
		_fill_rect(ci, el, xa + 1, top + 1, xb - 1, bot - 1, Color(0.25, 0.55, 0.95, 0.35))


## Пилот ISO/ГОСТ: треугольник контуром (~½ ширины рамки) остриём к корпусу, без заливки.
static func _draw_valve_pilot_box(ci: CanvasItem, el, body_x: float, sign: float, body_bot: float, stacked_on_coil: bool, cmd: bool) -> void:
	var g := _valve_pilot_frame_geom(body_x, sign, body_bot, stacked_on_coil)
	var xa: float = g["left"]
	var xb: float = g["right"]
	var top: float = g["top"]
	var bot: float = g["bottom"]
	_box(ci, el, xa, top, xb, bot, INK)
	var tip := Vector2(g["tip_x"], g["mid"])
	var base_x: float = g["base_x"]
	var y_pad := VALVE_SOL_H * 0.12
	var poly := PackedVector2Array([
		to_world(el, tip),
		to_world(el, Vector2(base_x, top + y_pad)),
		to_world(el, Vector2(base_x, bot - y_pad)),
		to_world(el, tip),
	])
	ci.draw_polyline(poly, ink(), _stroke_w(1.4), _stroke_aa())
	if cmd:
		_box(ci, el, xa, top, xb, bot, Color(0.25, 0.55, 0.95))


## --- Датчики (УГО) -----------------------------------------------------------
## Слева: I + ромб 45° с двумя вертикалями.
## Справа: tips +,OUT,0 фиксированы; контакт (LEAD+GAP+подвижная) переезжает
## между OUT↔0 (NPN) или OUT↔+ (PNP). Span пары = 2·(GAP+LEAD_X) = 40.
## Оптика: слева ещё OPT1/OPT2 на −SENSOR_LEAD.

const SENSOR_HW := 28.0
const SENSOR_HH := 48.0 # вмещает tips ±40
const SENSOR_DIV_X := -8.0
## Узкая правая область: mid≈10 → NO_RISE внутрь не задевает разделитель.
const SENSOR_BODY_RIGHT := 28.0
const SENSOR_LEAD := 40.0 # tip на SCH_GRID×4


static func _sensor_local_bounds(el) -> Rect2:
	if _sensor_is_pressure_switch(el):
		# Пневмо-УГО из DXF: tip −30, габарит ~±34 × ±21.
		return Rect2(-34.0, -22.0, 68.0, 44.0)
	if _sensor_is_pressure_tx(el):
		# Пневмо-УГО из DXF: tip −30, габарит ~±34 × ±18.
		return Rect2(-34.0, -18.0, 52.0, 36.0)
	if _sensor_is_rtd(el):
		# Квадрат T слева + термосопротивление + tips 1…4 на ±30.
		return Rect2(-34.0, -34.0, 34.0 + SENSOR_LEAD + 4.0, 68.0)
	var left: float = -SENSOR_HW - 4.0
	if _sensor_is_fiber_optical(el):
		left = -SENSOR_LEAD - 4.0
	var right: float = SENSOR_LEAD + 4.0
	return Rect2(left, -SENSOR_HH - 4.0, right - left, SENSOR_HH * 2.0 + 8.0)


static func _sensor_is_dry_contact(el) -> bool:
	return SensorSig.normalize_output(str(el.output_type)) == SensorSig.OUT_CONTACT \
		and not bool(el.sensor_active)


static func _sensor_is_fiber_optical(el) -> bool:
	return el != null and str(el.sensor_class) == "optical" and str(el.optical_form) != "compact"


static func _sensor_is_pressure_switch(el) -> bool:
	return el != null and str(el.sensor_class) == "pressure_switch"


static func _sensor_is_pressure_tx(el) -> bool:
	return el != null and str(el.sensor_class) == "pressure_tx"


static func _sensor_is_rtd(el) -> bool:
	return el != null and str(el.sensor_class) == "rtd"


static var _pressure_switch_ugo: Dictionary = {}
static var _pressure_tx_ugo: Dictionary = {}


static func _pressure_switch_ugo_data() -> Dictionary:
	var path := "res://data/symbols/pressure_switch_ugo.json"
	if _pressure_switch_ugo.is_empty() and FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_pressure_switch_ugo = parsed as Dictionary
	return _pressure_switch_ugo


static func _pressure_tx_ugo_data() -> Dictionary:
	var path := "res://data/symbols/pressure_tx_ugo.json"
	if _pressure_tx_ugo.is_empty() and FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_pressure_tx_ugo = parsed as Dictionary
	return _pressure_tx_ugo


static func _sensor_port_ys(el) -> Dictionary:
	## Tips всегда на одних Y (±4 клетки). Контакт переезжает между парами.
	var half: float = ElectroSym.GAP + ElectroSym.LEAD_X # 20
	var y_plus: float = -half * 2.0 # −40
	var y_out: float = 0.0
	var y_zero: float = half * 2.0 # +40
	var y_a: float = y_out
	var y_b: float = y_zero # NPN: OUT↔0
	if SensorSig.normalize_output(str(el.output_type)) == SensorSig.OUT_PNP:
		y_b = y_plus # PNP: OUT↔+
	return {"+": y_plus, "OUT": y_out, "0": y_zero, "a": y_a, "b": y_b}


static func _sensor_ports(el) -> Array:
	# Реле давления: только пневмопорт P (электро — на KP1.1).
	if _sensor_is_pressure_switch(el):
		var tip: Vector2 = Vector2(-SCH_GRID * 3.0, 0.0) # −30
		var data_ps: Dictionary = _pressure_switch_ugo_data()
		if data_ps.has("port_p"):
			var arr: Array = data_ps["port_p"] as Array
			if arr.size() >= 2:
				tip = Vector2(float(arr[0]), float(arr[1]))
		return [{"name": "P", "local": tip, "normal": Vector2.LEFT}]
	# ПИП: только пневмопорт P (электро — табличка PT·.1).
	if _sensor_is_pressure_tx(el):
		var tip_tx: Vector2 = Vector2(-SCH_GRID * 3.0, 0.0)
		var data_tx: Dictionary = _pressure_tx_ugo_data()
		if data_tx.has("port_p"):
			var arr_tx: Array = data_tx["port_p"] as Array
			if arr_tx.size() >= 2:
				tip_tx = Vector2(float(arr_tx[0]), float(arr_tx[1]))
		return [{"name": "P", "local": tip_tx, "normal": Vector2.LEFT}]
	# ТС: жилы 1…N на SCH_GRID (2/3/4-провод).
	if _sensor_is_rtd(el):
		return _rtd_sensor_ports(el)
	var tip_x: float = SENSOR_LEAD
	var ys: Dictionary = _sensor_port_ys(el)
	var out: Array = []
	# Пассивный сухой контакт (геркон): только 2 вывода — без «+».
	if _sensor_is_dry_contact(el):
		out = [
			{"name": "OUT", "local": Vector2(tip_x, float(ys["OUT"])), "normal": Vector2.RIGHT},
			{"name": "0", "local": Vector2(tip_x, float(ys["0"])), "normal": Vector2.RIGHT},
		]
	else:
		out = [
			{"name": "+", "local": Vector2(tip_x, float(ys["+"])), "normal": Vector2.RIGHT},
			{"name": "OUT", "local": Vector2(tip_x, float(ys["OUT"])), "normal": Vector2.RIGHT},
			{"name": "0", "local": Vector2(tip_x, float(ys["0"])), "normal": Vector2.RIGHT},
		]
	# Оптический усилитель (волокно): оптопорты слева на SCH_GRID.
	if _sensor_is_fiber_optical(el):
		var opt_x: float = -SENSOR_LEAD # −40 = −4×grid
		out.append({"name": "OPT1", "local": Vector2(opt_x, -SCH_GRID * 2.0), "normal": Vector2.LEFT})
		out.append({"name": "OPT2", "local": Vector2(opt_x, SCH_GRID * 2.0), "normal": Vector2.LEFT})
	return out


## Tips ТС на SCH_GRID: 2 → ±20; 3 → −20/0/+20; 4 → ±30/±10.
static func _rtd_sensor_ports(el) -> Array:
	var Rtd = preload("res://scripts/domain/rtd_nsx.gd")
	var scheme: int = clampi(int(el.wire_scheme) if el != null else 3, 2, 4)
	var names: PackedStringArray = Rtd.core_names(scheme)
	var ys: PackedFloat32Array = PackedFloat32Array()
	match scheme:
		2:
			ys = PackedFloat32Array([-SCH_GRID * 2.0, SCH_GRID * 2.0])
		3:
			ys = PackedFloat32Array([-SCH_GRID * 2.0, 0.0, SCH_GRID * 2.0])
		_:
			ys = PackedFloat32Array([
				-SCH_GRID * 3.0, -SCH_GRID, SCH_GRID, SCH_GRID * 3.0
			])
	var tip_x: float = SENSOR_LEAD
	var out: Array = []
	for i in names.size():
		var y: float = float(ys[i]) if i < ys.size() else 0.0
		out.append({"name": str(names[i]), "local": Vector2(tip_x, y), "normal": Vector2.RIGHT})
	return out


const OPTO_TIP_HW := 18.0
const OPTO_TIP_HH := 14.0
const OPTO_TIP_LEAD := 30.0 # 3×SCH_GRID


static func _opto_tip_local_bounds() -> Rect2:
	return Rect2(-OPTO_TIP_HW - 4.0, -OPTO_TIP_HH - 4.0, OPTO_TIP_HW + OPTO_TIP_LEAD + 8.0, OPTO_TIP_HH * 2.0 + 8.0)


static func _opto_tip_ports(el) -> Array:
	# Head: два волокна (излучатель+приёмник) в одном наконечнике.
	if el != null and str(el.opto_role) == "head":
		return [
			{"name": "OPT1", "local": Vector2(OPTO_TIP_LEAD, -SCH_GRID), "normal": Vector2.RIGHT},
			{"name": "OPT2", "local": Vector2(OPTO_TIP_LEAD, SCH_GRID), "normal": Vector2.RIGHT},
		]
	return [
		{"name": "OPT", "local": Vector2(OPTO_TIP_LEAD, 0.0), "normal": Vector2.RIGHT},
	]


static func _draw_opto_tip(ci: CanvasItem, el, font: Font, selected: bool, hover_port: String) -> void:
	var col: Color = ink()
	var sw: float = _stroke_w(1.45)
	var tl := to_world(el, Vector2(-OPTO_TIP_HW, -OPTO_TIP_HH))
	var br := to_world(el, Vector2(OPTO_TIP_HW, OPTO_TIP_HH))
	ci.draw_rect(Rect2(tl, br - tl).abs(), col, false, sw, _stroke_aa())
	# Линза / торец чутья слева.
	var lens_c := to_world(el, Vector2(-OPTO_TIP_HW + 6.0, 0.0))
	ci.draw_circle(lens_c, 4.5, Color(0, 0, 0, 0))
	ci.draw_arc(lens_c, 4.5, 0.0, TAU, 20, col, sw, _stroke_aa())
	# Хвост оптокабеля → tip OPT на сетке.
	ci.draw_line(
		to_world(el, Vector2(OPTO_TIP_HW, 0.0)),
		to_world(el, Vector2(OPTO_TIP_LEAD, 0.0)),
		col, sw, _stroke_aa()
	)
	var role: String = str(el.opto_role)
	var mark: String = "D"
	if role == "emitter":
		mark = "T"
	elif role == "receiver":
		mark = "R"
	elif role == "head":
		mark = "D"
	if font != null:
		var fs: int = 11
		var tw: float = font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(
			font,
			to_world(el, Vector2(-tw * 0.5, fs * 0.35)),
			mark,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			col
		)
	for p in _opto_tip_ports(el):
		_draw_port_marker(ci, el, p["local"], "optic", hover_port == str(p["name"]))
	_draw_element_tag(ci, el, font, 11, selected)


static func _draw_sensor(
	ci: CanvasItem, el, font: Font, selected: bool, show_values: bool, hover_port: String,
	omit_motion: bool = false
) -> void:
	if _sensor_is_pressure_switch(el):
		_draw_pressure_switch_ugo(ci, el, font, selected, hover_port)
		var _om: bool = omit_motion
		var _sv0: bool = show_values
		return
	if _sensor_is_pressure_tx(el):
		_draw_pressure_tx_ugo(ci, el, font, selected, hover_port)
		var _sv1: bool = show_values
		return
	if _sensor_is_rtd(el):
		_draw_rtd_ugo(ci, el, font, selected, hover_port)
		var _om2: bool = omit_motion
		var _sv2: bool = show_values
		return
	var col: Color = ink()
	var sw: float = _stroke_w(1.55)
	var tl := to_world(el, Vector2(-SENSOR_HW, -SENSOR_HH))
	var br := to_world(el, Vector2(SENSOR_BODY_RIGHT, SENSOR_HH))
	ci.draw_rect(Rect2(tl, br - tl).abs(), col, false, sw, _stroke_aa())
	ci.draw_line(
		to_world(el, Vector2(SENSOR_DIV_X, -SENSOR_HH)),
		to_world(el, Vector2(SENSOR_DIV_X, SENSOR_HH)),
		col, sw, _stroke_aa()
	)
	_draw_sensor_sense_marks(ci, el, col, sw, font)
	# omit_motion: корпус+выводы на Base; подвижный ключ — SchemeAnim.
	_draw_sensor_leads_and_contact(ci, el, col, sw, omit_motion)
	if _sensor_is_fiber_optical(el):
		# Хвосты оптопортов влево на SCH_GRID.
		ci.draw_line(
			to_world(el, Vector2(-SENSOR_HW, -SCH_GRID * 2.0)),
			to_world(el, Vector2(-SENSOR_LEAD, -SCH_GRID * 2.0)),
			col, sw, _stroke_aa()
		)
		ci.draw_line(
			to_world(el, Vector2(-SENSOR_HW, SCH_GRID * 2.0)),
			to_world(el, Vector2(-SENSOR_LEAD, SCH_GRID * 2.0)),
			col, sw, _stroke_aa()
		)
	for p in _sensor_ports(el):
		var nm: String = str(p["name"])
		var dom: String = port_domain(el, nm)
		_draw_port_marker(ci, el, p["local"], dom, hover_port == nm)
	_draw_element_tag(ci, el, font, 12, selected)
	var _sv: bool = show_values


## УГО ТС:
## Слева — как датчик давления: квадрат «T» (без пружины/стрелки уставки справа).
## Справа — термосопротивление (прямоугольник + диагональ t°), жилы на SCH_GRID.
static func _draw_rtd_ugo(
	ci: CanvasItem, el, font: Font, selected: bool, hover_port: String
) -> void:
	var col: Color = ink()
	var sw: float = _stroke_w(1.55)
	var aa: bool = _stroke_aa()
	# --- Пневмо/процесс: квадрат с «T» (ISO), как «P» у датчика давления. ---
	var box_hw: float = 11.0
	var box_hh: float = 14.0
	var box_cx: float = -18.0
	var box_cy: float = 0.0
	var corners := PackedVector2Array([
		to_world(el, Vector2(box_cx - box_hw, box_cy - box_hh)),
		to_world(el, Vector2(box_cx + box_hw, box_cy - box_hh)),
		to_world(el, Vector2(box_cx + box_hw, box_cy + box_hh)),
		to_world(el, Vector2(box_cx - box_hw, box_cy + box_hh)),
		to_world(el, Vector2(box_cx - box_hw, box_cy - box_hh)),
	])
	ci.draw_polyline(corners, col, sw, aa)
	if font != null:
		var fs_t: int = 14
		var tw_t: float = font.get_string_size("T", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_t).x
		ci.draw_string(
			font,
			to_world(el, Vector2(box_cx - tw_t * 0.5, box_cy + fs_t * 0.35)),
			"T",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs_t,
			col
		)
	# Связь квадрата → термосопротивление (без пружины/уставки справа).
	var r_x0: float = 2.0
	var r_x1: float = 26.0
	var r_y0: float = -7.0
	var r_y1: float = 7.0
	ci.draw_line(
		to_world(el, Vector2(box_cx + box_hw, 0.0)),
		to_world(el, Vector2(r_x0, 0.0)),
		col, sw, aa
	)
	# --- Электро: термосопротивление (резистор + диагональ t°). ---
	var rtl := to_world(el, Vector2(r_x0, r_y0))
	var rbr := to_world(el, Vector2(r_x1, r_y1))
	ci.draw_rect(Rect2(rtl, rbr - rtl).abs(), col, false, sw, aa)
	# Выводы по оси из середины торцов прямоугольника.
	ci.draw_line(
		to_world(el, Vector2(r_x0 - 4.0, 0.0)),
		to_world(el, Vector2(r_x0, 0.0)),
		col, sw, aa
	)
	ci.draw_line(
		to_world(el, Vector2(r_x1, 0.0)),
		to_world(el, Vector2(r_x1 + 4.0, 0.0)),
		col, sw, aa
	)
	# Диагональ снизу-слева → вверх-вправо + полка и «t°».
	var d0 := Vector2(r_x0 - 2.0, r_y1 + 10.0)
	var d1 := Vector2(r_x1 - 2.0, r_y0 - 6.0)
	ci.draw_line(to_world(el, d0), to_world(el, d1), col, sw * 0.95, aa)
	ci.draw_line(
		to_world(el, Vector2(d0.x - 5.0, d0.y)),
		to_world(el, d0),
		col, sw * 0.9, aa
	)
	if font != null:
		var fs_tc: int = 11
		ci.draw_string(
			font,
			to_world(el, Vector2(d0.x - 4.0, d0.y - 3.0)),
			"t°",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs_tc,
			col
		)
	# Хвосты к tips на сетке (веер от правого вывода).
	var hub := Vector2(r_x1 + 4.0, 0.0)
	for p in _rtd_sensor_ports(el):
		var loc: Vector2 = p["local"] as Vector2
		ci.draw_line(to_world(el, hub), to_world(el, loc), col, sw, aa)
		_draw_port_marker(ci, el, loc, "electric", hover_port == str(p["name"]))
	_draw_element_tag(ci, el, font, 12, selected)


## Пневмочасть реле давления (DXF пользователя); электро — KP1.1 с коробкой P.
static func _draw_pressure_switch_ugo(
	ci: CanvasItem, el, font: Font, selected: bool, hover_port: String
) -> void:
	var col: Color = ink()
	var sw: float = _stroke_w(1.45)
	var data: Dictionary = _pressure_switch_ugo_data()
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if typeof(st) != TYPE_ARRAY or (st as Array).size() < 2:
			continue
		var pts := PackedVector2Array()
		for pt in st as Array:
			if typeof(pt) != TYPE_ARRAY or (pt as Array).size() < 2:
				continue
			pts.append(to_world(el, Vector2(float(pt[0]), float(pt[1]))))
		if pts.size() >= 2:
			ci.draw_polyline(pts, col, sw, _stroke_aa())
	for p in _sensor_ports(el):
		var nm: String = str(p["name"])
		_draw_port_marker(ci, el, p["local"] as Vector2, port_domain(el, nm), hover_port == nm)
	_draw_element_tag(ci, el, font, 12, selected)


## ПИП B2: пневмочасть из DXF; электро — табличка PT·.1 (как БП).
static func _draw_pressure_tx_ugo(
	ci: CanvasItem, el, font: Font, selected: bool, hover_port: String
) -> void:
	var col: Color = ink()
	var sw: float = _stroke_w(1.45)
	var data: Dictionary = _pressure_tx_ugo_data()
	var strokes_raw: Array = data.get("strokes", []) as Array
	for st in strokes_raw:
		if typeof(st) != TYPE_ARRAY or (st as Array).size() < 2:
			continue
		var pts := PackedVector2Array()
		for pt in st as Array:
			if typeof(pt) != TYPE_ARRAY or (pt as Array).size() < 2:
				continue
			pts.append(to_world(el, Vector2(float(pt[0]), float(pt[1]))))
		if pts.size() >= 2:
			ci.draw_polyline(pts, col, sw, _stroke_aa())
	for p in _sensor_ports(el):
		var nm: String = str(p["name"])
		_draw_port_marker(ci, el, p["local"] as Vector2, port_domain(el, nm), hover_port == nm)
	_draw_element_tag(ci, el, font, 12, selected)


## Подвижный ключ геркона/датчика — для SchemeAnim (Base заморожен при Run).
static func draw_sensor_motion(ci: CanvasItem, el) -> void:
	if el == null or str(el.kind) != "sensor":
		return
	if _sensor_is_pressure_switch(el) or _sensor_is_pressure_tx(el) or _sensor_is_rtd(el):
		return
	_draw_sensor_contact_blade(ci, el, ink(), _stroke_w(1.55))


static func _draw_sensor_sense_marks(ci: CanvasItem, el, col: Color, sw: float, font: Font = null) -> void:
	var ix: float = (-SENSOR_HW + SENSOR_DIV_X) * 0.5
	var col_top: float = -SENSOR_HH + 4.0
	var col_bot: float = SENSOR_HH - 4.0
	var mid_y: float = (col_top + col_bot) * 0.5
	var iy: float = col_top + (mid_y - col_top) * 0.42
	var i_h: float = 10.0
	var i_w: float = 5.5
	ci.draw_line(to_world(el, Vector2(ix - i_w * 0.5, iy - i_h * 0.5)), to_world(el, Vector2(ix + i_w * 0.5, iy - i_h * 0.5)), col, sw, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(ix, iy - i_h * 0.5)), to_world(el, Vector2(ix, iy + i_h * 0.5)), col, sw * 1.2, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(ix - i_w * 0.5, iy + i_h * 0.5)), to_world(el, Vector2(ix + i_w * 0.5, iy + i_h * 0.5)), col, sw, _stroke_aa())
	var prox_c := Vector2(ix, mid_y + (col_bot - mid_y) * 0.48)
	var pr: float = 7.0
	pr = minf(pr, absf(ix - SENSOR_DIV_X) - 1.5)
	pr = minf(pr, absf(ix + SENSOR_HW) - 1.5)
	pr = maxf(pr, 5.0)
	var diamond := PackedVector2Array([
		to_world(el, prox_c + Vector2(0, -pr)),
		to_world(el, prox_c + Vector2(pr, 0)),
		to_world(el, prox_c + Vector2(0, pr)),
		to_world(el, prox_c + Vector2(-pr, 0)),
		to_world(el, prox_c + Vector2(0, -pr)),
	])
	ci.draw_polyline(diamond, col, sw, _stroke_aa())
	var v_dx: float = maxf(pr * 0.28, 1.8)
	var v_h: float = pr - v_dx
	ci.draw_line(to_world(el, prox_c + Vector2(-v_dx, -v_h)), to_world(el, prox_c + Vector2(-v_dx, v_h)), col, sw, _stroke_aa())
	ci.draw_line(to_world(el, prox_c + Vector2(v_dx, -v_h)), to_world(el, prox_c + Vector2(v_dx, v_h)), col, sw, _stroke_aa())
	var _f: Font = font
	var _el = el


static func _draw_sensor_leads_and_contact(
	ci: CanvasItem, el, col: Color, sw: float, omit_motion: bool = false
) -> void:
	## mid_x — ось контакта; повисающие концы линий = внешние концы LEAD реле.
	var mid_x: float = (SENSOR_DIV_X + SENSOR_BODY_RIGHT) * 0.5
	var ys: Dictionary = _sensor_port_ys(el)
	var y_a: float = float(ys["a"])
	var y_b: float = float(ys["b"])
	var y_plus: float = float(ys["+"])
	var y_out: float = float(ys["OUT"])
	var y_zero: float = float(ys["0"])
	for yv in [y_plus, y_out, y_zero]:
		var y: float = float(yv)
		if _sensor_is_dry_contact(el) and absf(y - y_plus) < 0.1:
			continue
		var is_switched: bool = absf(y - y_a) < 0.1 or absf(y - y_b) < 0.1
		if is_switched:
			ci.draw_line(to_world(el, Vector2(mid_x, y)), to_world(el, Vector2(SENSOR_LEAD, y)), col, sw, _stroke_aa())
		else:
			ci.draw_line(to_world(el, Vector2(SENSOR_BODY_RIGHT, y)), to_world(el, Vector2(SENSOR_LEAD, y)), col, sw, _stroke_aa())
	if omit_motion:
		return
	_draw_sensor_contact_blade(ci, el, col, sw)


static func _draw_sensor_contact_blade(ci: CanvasItem, el, col: Color, _sw: float) -> void:
	var mid_x: float = (SENSOR_DIV_X + SENSOR_BODY_RIGHT) * 0.5
	var ys: Dictionary = _sensor_port_ys(el)
	var y_a: float = float(ys["a"])
	var y_b: float = float(ys["b"])
	var form_nc: bool = SensorSig.normalize_form(str(el.contact_form)) == SensorSig.FORM_NC
	var actuated: bool = bool(el.pressed) or bool(el.lit)
	var lead: float = ElectroSym.LEAD_X
	var no_rise: float = ElectroSym.NO_RISE
	var sw_c: float = _stroke_w(ElectroSym.CONTACT_W)
	var dir_y: float = signf(y_b - y_a)
	if absf(dir_y) < 0.5:
		dir_y = 1.0
	var y_lead_a: float = y_a
	var y_lead_b: float = y_b
	var y_term_a: float = y_a + dir_y * lead
	var y_term_b: float = y_b - dir_y * lead
	ci.draw_line(to_world(el, Vector2(mid_x, y_lead_a)), to_world(el, Vector2(mid_x, y_term_a)), col, sw_c, _stroke_aa())
	ci.draw_line(to_world(el, Vector2(mid_x, y_term_b)), to_world(el, Vector2(mid_x, y_lead_b)), col, sw_c, _stroke_aa())
	var tab_len: float = SCH_GRID * 0.5
	if form_nc:
		ci.draw_line(to_world(el, Vector2(mid_x, y_term_b)), to_world(el, Vector2(mid_x - tab_len, y_term_b)), col, sw_c, _stroke_aa())
		if actuated:
			ci.draw_line(to_world(el, Vector2(mid_x, y_term_a)), to_world(el, Vector2(mid_x - no_rise, y_term_b)), col, sw_c, _stroke_aa())
		else:
			var tip_x: float = mid_x - tab_len * (2.0 / 3.0)
			ci.draw_line(to_world(el, Vector2(mid_x, y_term_a)), to_world(el, Vector2(tip_x, y_term_b)), col, sw_c, _stroke_aa())
	else:
		if actuated:
			ci.draw_line(to_world(el, Vector2(mid_x, y_term_a)), to_world(el, Vector2(mid_x, y_term_b)), col, sw_c, _stroke_aa())
		else:
			ci.draw_line(to_world(el, Vector2(mid_x, y_term_a)), to_world(el, Vector2(mid_x - no_rise, y_term_b)), col, sw_c, _stroke_aa())



class ThumbElement extends RefCounted:
	var kind := "valve"
	var position := Vector2.ZERO
	var rotation_quad := 0
	var valve_ways := 5
	var valve_positions := 2
	var rest_pos := 0
	var valve_pos := 0

	func _init(ways: int = 5) -> void:
		valve_ways = ways
