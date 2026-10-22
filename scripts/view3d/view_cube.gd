extends Control
## Куб выбора вида (как в CAD): крутится с камерой, клик по грани/углу.

signal view_chosen(yaw: float, pitch: float)

const UiTheme = preload("res://scripts/app/ui_theme.gd")

const CUBE_SIZE := 92.0
const HALF := 0.55

## Грани: нормаль → подпись.
const FACES := [
	{"n": Vector3(0, 0, 1), "label": "ПЕР"},
	{"n": Vector3(0, 0, -1), "label": "ЗАД"},
	{"n": Vector3(1, 0, 0), "label": "ПРАВ"},
	{"n": Vector3(-1, 0, 0), "label": "ЛЕВ"},
	{"n": Vector3(0, 1, 0), "label": "ВЕРХ"},
	{"n": Vector3(0, -1, 0), "label": "НИЗ"},
]

var yaw := 0.7
var pitch := 0.42
var _hover := -1 # индекс грани, или -(10+corner) для угла
var _corners: Array = [] # кэш проекций углов для hit
var _face_proj: Array = [] # {i, depth, poly, center}


func _ready() -> void:
	custom_minimum_size = Vector2(CUBE_SIZE + 8.0, CUBE_SIZE + 8.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Клик по грани/углу — плавный вид на выделение (или сцену)"


func set_orientation(y: float, p: float) -> void:
	if absf(y - yaw) < 1e-4 and absf(p - pitch) < 1e-4:
		return
	yaw = y
	pitch = p
	queue_redraw()


func _process(_dt: float) -> void:
	# Hover при движении мыши без ожидания gui_input motion.
	if not get_global_rect().has_point(get_global_mouse_position()):
		if _hover != -1:
			_hover = -1
			queue_redraw()
		return
	var local := get_local_mouse_position()
	var h := _hit_at(local)
	if h != _hover:
		_hover = h
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var h := _hit_at(event.position)
		if h == -1:
			return
		var dir := _hit_direction(h)
		var orbit := _dir_to_orbit(dir)
		view_chosen.emit(orbit.x, orbit.y)
		accept_event()
	elif event is InputEventMouseMotion:
		var h2 := _hit_at(event.position)
		if h2 != _hover:
			_hover = h2
			queue_redraw()


func _view_basis() -> Basis:
	# Та же сферическая камера, что в workshop_view.
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	if offset.length_squared() < 1e-8:
		offset = Vector3(0, 0, 1)
	var forward := (-offset).normalized() # куда смотрит камера
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	return Basis(right, up, -forward)


func _project(local3: Vector3, basis: Basis, center: Vector2, scale: float) -> Vector3:
	# x,y экрана; z — глубина (больше = ближе к камере).
	var cam := basis.inverse() * local3
	return Vector3(center.x + cam.x * scale, center.y - cam.y * scale, -cam.z)


func _face_corners(n: Vector3) -> PackedVector3Array:
	var ax := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var u := n.cross(ax).normalized()
	var v := n.cross(u).normalized()
	var c := n * HALF
	return PackedVector3Array([
		c + (-u - v) * HALF,
		c + (u - v) * HALF,
		c + (u + v) * HALF,
		c + (-u + v) * HALF,
	])


func _rebuild_proj() -> void:
	_face_proj.clear()
	_corners.clear()
	var basis := _view_basis()
	var center := size * 0.5
	var scale := minf(size.x, size.y) * 0.42
	for i in FACES.size():
		var n: Vector3 = FACES[i]["n"]
		var corners := _face_corners(n)
		var poly := PackedVector2Array()
		var depth_sum := 0.0
		for p in corners:
			var pr := _project(p, basis, center, scale)
			poly.append(Vector2(pr.x, pr.y))
			depth_sum += pr.z
		var depth := depth_sum * 0.25
		# Лицо к камере, если нормаль смотрит на наблюдателя.
		var n_cam: Vector3 = basis.inverse() * n
		var facing: bool = n_cam.z < -0.05
		var mid := _project(n * HALF, basis, center, scale)
		_face_proj.append({
			"i": i,
			"depth": depth,
			"poly": poly,
			"center": Vector2(mid.x, mid.y),
			"facing": facing,
			"label": str(FACES[i]["label"]),
		})
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx, sy, sz) * HALF
				var pr := _project(p, basis, center, scale)
				_corners.append({
					"dir": Vector3(sx, sy, sz).normalized(),
					"p": Vector2(pr.x, pr.y),
					"depth": pr.z,
				})


func _draw() -> void:
	_rebuild_proj()
	var bg := UiTheme.panel_bg()
	bg.a = 0.55 if UiTheme.dark else 0.72
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.48, bg)

	var order: Array = _face_proj.duplicate()
	order.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))

	var font: Font = UiTheme.font_medium()
	for item in order:
		if not bool(item["facing"]):
			continue
		var i: int = int(item["i"])
		var poly: PackedVector2Array = item["poly"]
		var face_col := _face_color(i, i == _hover)
		draw_colored_polygon(poly, face_col)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, UiTheme.text().lerp(face_col, 0.35), 1.25, true)
		var label: String = item["label"]
		var c: Vector2 = item["center"]
		var fs := 11
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs) if font else Vector2(24, 12)
		var ink := UiTheme.text()
		ink.a = 0.92
		draw_string(font, c - Vector2(ts.x * 0.5, -ts.y * 0.25), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

	# Углы — маленькие точки (изометрия).
	for ci in _corners.size():
		var corner: Dictionary = _corners[ci]
		var hot: bool = _hover == -(10 + ci)
		var r := 3.6 if hot else 2.4
		var col := UiTheme.accent() if hot else UiTheme.muted()
		draw_circle(corner["p"], r, col)


func _face_color(i: int, hot: bool) -> Color:
	var base := Color(0.22, 0.32, 0.44, 0.88) if UiTheme.dark else Color(0.78, 0.84, 0.90, 0.92)
	match i:
		0, 1: # Z
			base = Color(0.28, 0.42, 0.58, 0.9) if UiTheme.dark else Color(0.70, 0.80, 0.90, 0.94)
		2, 3: # X
			base = Color(0.34, 0.36, 0.48, 0.9) if UiTheme.dark else Color(0.82, 0.78, 0.88, 0.94)
		_: # Y
			base = Color(0.26, 0.40, 0.36, 0.9) if UiTheme.dark else Color(0.74, 0.86, 0.80, 0.94)
	if hot:
		return base.lerp(UiTheme.accent(), 0.45)
	return base


func _point_in_poly(pt: Vector2, poly: PackedVector2Array) -> bool:
	# Even-odd.
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var pi: Vector2 = poly[i]
		var pj: Vector2 = poly[j]
		if ((pi.y > pt.y) != (pj.y > pt.y)) and (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y + 1e-9) + pi.x):
			inside = not inside
		j = i
	return inside


func _hit_at(local: Vector2) -> int:
	_rebuild_proj()
	# Сначала углы (удобнее попасть в изометрию).
	var best_c := -1
	var best_cd := 10.0
	for ci in _corners.size():
		var corner: Dictionary = _corners[ci]
		var d: float = local.distance_to(corner["p"])
		if d < best_cd and d <= 8.0:
			best_cd = d
			best_c = ci
	if best_c >= 0:
		return -(10 + best_c)
	var best_f := -1
	var best_depth := -1.0e9
	for item in _face_proj:
		if not bool(item["facing"]):
			continue
		if not _point_in_poly(local, item["poly"]):
			continue
		var depth: float = float(item["depth"])
		if depth > best_depth:
			best_depth = depth
			best_f = int(item["i"])
	return best_f


func _hit_direction(hit: int) -> Vector3:
	if hit <= -10:
		var ci := -hit - 10
		if ci >= 0 and ci < _corners.size():
			return (_corners[ci]["dir"] as Vector3)
		return Vector3(1, 1, 1).normalized()
	if hit >= 0 and hit < FACES.size():
		return FACES[hit]["n"]
	return Vector3(0, 0, 1)


func _dir_to_orbit(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	if absf(d.y) > 0.98:
		# Верх/низ — сохраняем текущий yaw.
		return Vector2(yaw, PI * 0.5 * signf(d.y))
	var p := asin(clampf(d.y, -1.0, 1.0))
	var y := atan2(d.x, d.z)
	return Vector2(y, p)
