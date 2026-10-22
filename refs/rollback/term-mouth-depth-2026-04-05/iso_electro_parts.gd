extends RefCounted
## Общие детали процедурного реализма DIN-аппаратов (без GLB).

const Parts = preload("res://scripts/view3d/pneumo_parts.gd")


static func mm(v: float) -> float:
	return Parts.mm(v)


static func mat_black() -> StandardMaterial3D:
	return Parts.mat("ep_blk", Color(0.08, 0.08, 0.1), 0.1, 0.55)


static func mat_black_soft() -> StandardMaterial3D:
	return Parts.mat("ep_blk2", Color(0.12, 0.12, 0.14), 0.12, 0.6)


static func mat_orange() -> StandardMaterial3D:
	return Parts.mat("ep_or", Color(0.92, 0.45, 0.1), 0.06, 0.48)


static func mat_ral7035() -> StandardMaterial3D:
	return Parts.mat("ep_7035", Color(0.78, 0.80, 0.82), 0.12, 0.58)


static func mat_ral7035_dark() -> StandardMaterial3D:
	return Parts.mat("ep_7035d", Color(0.62, 0.64, 0.66), 0.15, 0.55)


static func mat_beige() -> StandardMaterial3D:
	return Parts.mat("ep_beige", Color(0.88, 0.86, 0.78), 0.05, 0.62)


## Finder 58.xx колодка / фиксатор (реф 583490120050SPB).
static func mat_finder_blue() -> StandardMaterial3D:
	return Parts.mat("ep_fnd_bl", Color(0.12, 0.28, 0.72), 0.08, 0.48)


static func mat_cream_face() -> StandardMaterial3D:
	return Parts.mat("ep_cream", Color(0.93, 0.91, 0.84), 0.06, 0.62)


static func mat_green() -> StandardMaterial3D:
	return Parts.mat("ep_grn", Color(0.2, 0.55, 0.28), 0.05, 0.55)


static func mat_well() -> StandardMaterial3D:
	return Parts.mat("ep_well", Color(0.12, 0.12, 0.13), 0.25, 0.72)


static func mat_coil_cu() -> StandardMaterial3D:
	return Parts.mat("ep_coil", Color(0.82, 0.72, 0.55), 0.35, 0.42)


static func mat_coil_bobbin() -> StandardMaterial3D:
	return Parts.mat("ep_bobbin", Color(0.92, 0.92, 0.94), 0.08, 0.55)


static func mat_fe() -> StandardMaterial3D:
	return Parts.mat("ep_fe", Color(0.45, 0.46, 0.48), 0.55, 0.35)


static func set_xray(mi: MeshInstance3D, role: String) -> void:
	mi.set_meta("xray_role", role)


## Колодец винта на лице (+Z): углубление, винт, крест, вход провода по wire_dir.
static func screw_well_face(parent: Node3D, pos: Vector3, wire_dir: Vector3, well_mm: float = 7.0) -> void:
	var s: float = mm(well_mm)
	Parts.box(parent, Vector3(s, s, mm(5.5)), pos, mat_well(), "internal")
	Parts.cyl(parent, mm(1.8), mm(3.4), pos + Vector3(0, 0, mm(1.4)), "z", Parts.alum(), 10, "internal")
	# Крест шлица.
	Parts.box(parent, Vector3(mm(2.8), mm(0.35), mm(0.6)), pos + Vector3(0, 0, mm(3.0)), Parts.alum(), "internal")
	Parts.box(parent, Vector3(mm(0.35), mm(2.8), mm(0.6)), pos + Vector3(0, 0, mm(3.0)), Parts.alum(), "internal")
	var nd: Vector3 = wire_dir.normalized() if wire_dir.length_squared() > 1e-8 else Vector3(0, 1, 0)
	var entry: Vector3 = pos + nd * mm(5.2)
	Parts.box(parent, Vector3(mm(5.2), mm(4.2), mm(3.2)), entry, mat_well(), "internal")


## Колодец винта сверху (+Y): для DIN-клемм.
static func screw_well_top(parent: Node3D, pos: Vector3, wire_dir: Vector3) -> void:
	Parts.box(parent, Vector3(mm(5.0), mm(3.5), mm(5.0)), pos, mat_well(), "internal")
	Parts.cyl(parent, mm(1.5), mm(3.5), pos + Vector3(0, mm(1.2), 0), "y", Parts.alum(), 8, "internal")
	Parts.box(parent, Vector3(mm(2.4), mm(0.5), mm(0.35)), pos + Vector3(0, mm(2.6), 0), Parts.alum(), "internal")
	Parts.box(parent, Vector3(mm(0.35), mm(0.5), mm(2.4)), pos + Vector3(0, mm(2.6), 0), Parts.alum(), "internal")
	var nd: Vector3 = wire_dir.normalized() if wire_dir.length_squared() > 1e-8 else Vector3(0, 0, 1)
	var entry: Vector3 = pos + nd * mm(6.0) + Vector3(0, mm(-2.0), 0)
	Parts.box(parent, Vector3(mm(4.5), mm(4.5), mm(2.8)), entry, mat_well(), "internal")


## Оранжевый DIN-замок (вытяжка спереди-снизу).
static func din_clip_orange(parent: Node3D, center: Vector3, w: float) -> void:
	Parts.box(parent, Vector3(w * 0.42, mm(5.5), mm(9.0)), center, mat_orange(), "shell")
	Parts.box(parent, Vector3(w * 0.28, mm(3.0), mm(4.0)), center + Vector3(0, mm(-3.5), mm(2.0)), mat_orange(), "shell")


## Серый DIN-паз / губки на шляпу TS35.
static func din_clip_grey(parent: Node3D, center: Vector3, w: float) -> void:
	Parts.box(parent, Vector3(w * 0.75, mm(7.0), mm(10.0)), center, mat_black(), "internal")
	Parts.box(parent, Vector3(w * 0.55, mm(4.0), mm(6.0)), center + Vector3(0, mm(-4.0), mm(2.0)), Parts.black(), "internal")


## Перегородки между клеммами вдоль оси X.
static func barrier_row(parent: Node3D, origin: Vector3, count: int, pitch: float, size: Vector3, mat: StandardMaterial3D = null) -> void:
	var m: StandardMaterial3D = mat if mat != null else mat_black()
	for i in range(count + 1):
		var x: float = origin.x - float(count - 1) * pitch * 0.5 - pitch * 0.5 + float(i) * pitch
		Parts.box(parent, size, Vector3(x, origin.y, origin.z), m, "shell")


## Ряд щелей под плоские ножки реле (на верхней плоскости колодки).
static func pin_slot_row(parent: Node3D, origin: Vector3, count: int, pitch: float, slot_w: float, slot_d: float, slot_h: float) -> void:
	for i in count:
		var x: float = origin.x + (float(i) - float(count - 1) * 0.5) * pitch
		Parts.box(parent, Vector3(slot_w, slot_h, slot_d), Vector3(x, origin.y, origin.z), mat_well(), "internal")


## Прозрачный корпус реле/модуля.
static func clear_cover(parent: Node3D, size: Vector3, center: Vector3, alpha: float = 0.28) -> MeshInstance3D:
	var cover_mat := StandardMaterial3D.new()
	cover_mat.albedo_color = Color(0.78, 0.86, 0.92, alpha)
	cover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cover_mat.roughness = 0.1
	cover_mat.metallic = 0.05
	var cover := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = size
	cover.mesh = cmesh
	cover.position = center
	cover.material_override = cover_mat
	set_xray(cover, "shell")
	parent.add_child(cover)
	return cover


## Мелкая подпись на лице аппарата.
static func face_label(parent: Node3D, text: String, pos: Vector3, size: int = 11, pixel: float = 0.0002) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = size
	lab.pixel_size = pixel
	lab.modulate = Color(0.1, 0.1, 0.12)
	lab.outline_size = 0
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.position = pos
	parent.add_child(lab)
	return lab


## Ряд винтовых колодцев на ступени колодки (±Z лицо).
static func terminal_step_row(parent: Node3D, y: float, z: float, end_sign: float, n: int, pitch: float, body_w: float) -> void:
	var step_d: float = mm(9.0)
	Parts.box(parent, Vector3(body_w * 0.92, mm(7.5), step_d), Vector3(0, y, z), mat_black_soft(), "shell")
	barrier_row(parent, Vector3(0, y, z + end_sign * mm(2.5)), n, pitch, Vector3(mm(1.4), mm(6.5), mm(7.0)), mat_black())
	for i in n:
		var x: float = (float(i) - float(n - 1) * 0.5) * pitch
		screw_well_face(parent, Vector3(x, y, z + end_sign * mm(2.0)), Vector3(0, 0, end_sign), 6.2)


## Катушка реле: каркас + обмотка.
static func relay_coil(parent: Node3D, center: Vector3) -> void:
	Parts.cyl(parent, mm(9.0), mm(8.0), center + Vector3(0, mm(10.0), 0), "y", mat_coil_bobbin(), 14, "internal")
	Parts.cyl(parent, mm(9.0), mm(8.0), center + Vector3(0, mm(-10.0), 0), "y", mat_coil_bobbin(), 14, "internal")
	Parts.cyl(parent, mm(7.5), mm(18.0), center, "y", mat_coil_cu(), 16, "internal")
	Parts.box(parent, Vector3(mm(4.0), mm(20.0), mm(4.0)), center, mat_fe(), "internal")


## Плоские ножки реле вниз (−Y).
static func relay_pins(parent: Node3D, origin: Vector3, count: int, pitch: float) -> void:
	for i in count:
		var x: float = origin.x + (float(i) - float(count - 1) * 0.5) * pitch
		Parts.box(parent, Vector3(mm(1.2), mm(8.0), mm(3.2)), Vector3(x, origin.y, origin.z), Parts.alum(), "internal")


## Заклёпки / стык половин корпуса АВ по периметру.
static func housing_rivets(parent: Node3D, w: float, h: float, d: float) -> void:
	var brass := Parts.brass()
	var pts: Array = [
		Vector3(-w * 0.42, h * 0.35, d * 0.05),
		Vector3(w * 0.42, h * 0.35, d * 0.05),
		Vector3(-w * 0.42, -h * 0.35, d * 0.05),
		Vector3(w * 0.42, -h * 0.35, d * 0.05),
		Vector3(-w * 0.42, 0, d * 0.05),
		Vector3(w * 0.42, 0, d * 0.05),
	]
	for p in pts:
		Parts.cyl(parent, mm(1.1), mm(2.0), p, "z", brass, 8, "shell")


## Улучшенный ступенчатый корпус DIN (реф FAZ / DFS2: паз по боку, глубокие зевы клемм).
## term_wells=false — сплошные полки до лица (для KT: без тёмных «дыр» сбоку).
static func mod_step_body_hi(parent: Node3D, w: float, h: float, d: float, body: StandardMaterial3D, term_wells: bool = true) -> void:
	Parts.box(parent, Vector3(w, h, d * 0.52), Vector3(0, 0, -d * 0.12), body, "shell")
	din_clip_grey(parent, Vector3(0, -h * 0.42, -d * 0.32), w)
	Parts.box(parent, Vector3(w * 0.98, h * 0.52, d * 0.4), Vector3(0, 0, d * 0.28), body, "shell")
	if term_wells:
		# Короткие ступени + тёмные зевы под клеммы АВ/УЗО.
		Parts.box(parent, Vector3(w * 0.98, h * 0.18, d * 0.3), Vector3(0, h * 0.4, d * 0.12), body, "shell")
		Parts.box(parent, Vector3(w * 0.98, h * 0.18, d * 0.3), Vector3(0, -h * 0.4, d * 0.12), body, "shell")
		Parts.box(parent, Vector3(w * 0.82, mm(8.0), mm(10.0)), Vector3(0, h * 0.42, d * 0.22), mat_well(), "internal")
		Parts.box(parent, Vector3(w * 0.82, mm(8.0), mm(10.0)), Vector3(0, -h * 0.42, d * 0.22), mat_well(), "internal")
	else:
		# Полки до передней плоскости — без бокового кармана.
		Parts.box(parent, Vector3(w * 0.98, h * 0.22, d * 0.56), Vector3(0, h * 0.39, d * 0.20), body, "shell")
		Parts.box(parent, Vector3(w * 0.98, h * 0.22, d * 0.56), Vector3(0, -h * 0.39, d * 0.20), body, "shell")
	# Вертикальный паз половины корпуса (FAZ).
	Parts.box(parent, Vector3(mm(1.1), h * 0.72, d * 0.22), Vector3(-w * 0.498, 0, d * 0.02), mat_ral7035_dark(), "shell")
	Parts.box(parent, Vector3(mm(1.1), h * 0.72, d * 0.22), Vector3(w * 0.498, 0, d * 0.02), mat_ral7035_dark(), "shell")
	# Боковые рёбра / охлаждение.
	for i in 5:
		var y: float = -h * 0.35 + float(i) * h * 0.175
		Parts.box(parent, Vector3(mm(0.9), mm(2.5), d * 0.28), Vector3(-w * 0.495, y, d * 0.05), mat_ral7035_dark(), "shell")
		Parts.box(parent, Vector3(mm(0.9), mm(2.5), d * 0.28), Vector3(w * 0.495, y, d * 0.05), mat_ral7035_dark(), "shell")
	housing_rivets(parent, w, h, d)


## Двухъярусные клеммы УЗО (реф Doepke DFS2: large two-tier terminals).
static func two_tier_terminals(parent: Node3D, w: float, h: float, d: float, poles: int) -> void:
	var pitch: float = w / float(maxi(poles, 1))
	for tier in 2:
		var y_off: float = h * (0.38 if tier == 0 else 0.46)
		var z_off: float = d * (0.18 if tier == 0 else 0.28)
		for end_s in [-1.0, 1.0]:
			Parts.box(
				parent,
				Vector3(w * 0.92, mm(6.5), mm(8.0)),
				Vector3(0, end_s * y_off, z_off),
				mat_ral7035_dark(),
				"shell"
			)
			for i in poles:
				var x: float = -w * 0.5 + pitch * 0.5 + float(i) * pitch
				screw_well_face(
					parent,
					Vector3(x, end_s * y_off, z_off + mm(2.0)),
					Vector3(0, end_s, 0),
					6.8
				)


## Окно под маркировку (Doepke viewing window).
static func label_window(parent: Node3D, center: Vector3, size: Vector3) -> void:
	Parts.box(parent, size, center, Parts.mat("ep_win_fr", Color(0.55, 0.56, 0.58), 0.15, 0.45), "shell")
	Parts.box(
		parent,
		Vector3(size.x * 0.88, size.y * 0.75, size.z * 0.6),
		center + Vector3(0, 0, mm(0.4)),
		Parts.mat("ep_win_paper", Color(0.96, 0.96, 0.94), 0.05, 0.7),
		"shell"
	)


## Рычаг АВ/УЗО (реф Schneider iC60 / FAZ): ось X ⊥ боковине.
## При 0° рукоятка вдоль +Y; update_state: ON ≈ −35° (вверх), OFF ≈ +35° (вниз).
static func breaker_lever(parent: Node3D, color: Color, width: float) -> Node3D:
	var lever := Node3D.new()
	lever.name = "Lever"
	parent.add_child(lever)
	var lever_mat := Parts.mat("brk_lev_hi", color, 0.05, 0.42)
	Parts.cyl(lever, mm(2.4), width * 0.92, Vector3.ZERO, "x", Parts.mat("brk_pivot", Color(0.2, 0.2, 0.22), 0.25, 0.45), 12, "actuator")
	# Изогнутая лопатка iC60: тело + скруглённый нос.
	Parts.box(lever, Vector3(width * 0.9, mm(14.0), mm(7.0)), Vector3(0, mm(6.5), mm(4.5)), lever_mat, "actuator")
	Parts.box(lever, Vector3(width * 0.78, mm(6.0), mm(5.5)), Vector3(0, mm(13.5), mm(6.5)), lever_mat, "actuator")
	Parts.cyl(lever, mm(3.2), width * 0.7, Vector3(0, mm(16.5), mm(7.0)), "x", lever_mat, 10, "actuator")
	for i in 3:
		var t: float = mm(3.5) + float(i) * mm(3.2)
		Parts.box(lever, Vector3(width * 0.65, mm(0.7), mm(1.0)), Vector3(0, t, mm(8.0)), lever_mat, "actuator")
	return lever


## Круглый зев клеммы iC60 (двойной зажим, винт внутри).
static func round_term_mouth(parent: Node3D, pos: Vector3, wire_dir: Vector3) -> void:
	Parts.cyl(parent, mm(4.2), mm(6.0), pos, "z", mat_well(), 12, "internal")
	Parts.cyl(parent, mm(1.7), mm(3.2), pos + Vector3(0, 0, mm(1.2)), "z", Parts.alum(), 8, "internal")
	Parts.box(parent, Vector3(mm(2.6), mm(0.35), mm(0.5)), pos + Vector3(0, 0, mm(2.6)), Parts.alum(), "internal")
	Parts.box(parent, Vector3(mm(0.35), mm(2.6), mm(0.5)), pos + Vector3(0, 0, mm(2.6)), Parts.alum(), "internal")
	var nd: Vector3 = wire_dir.normalized() if wire_dir.length_squared() > 1e-8 else Vector3(0, 1, 0)
	Parts.box(parent, Vector3(mm(5.0), mm(4.0), mm(3.0)), pos + nd * mm(5.0), mat_well(), "internal")


## Клемма KT: винт на +Z, зев ±Y = размер подсветки порта (5.5×2.6×5.0 мм).
static func kt_term_well(parent: Node3D, pos: Vector3, wire_from_up: bool = true) -> void:
	var y_sign: float = 1.0 if wire_from_up else -1.0
	Parts.cyl(parent, mm(2.9), mm(5.0), pos + Vector3(0, 0, -mm(1.0)), "z", mat_well(), 14, "internal")
	Parts.cyl(parent, mm(1.55), mm(2.4), pos + Vector3(0, 0, mm(0.2)), "z", Parts.alum(), 10, "shell")
	Parts.box(parent, Vector3(mm(2.3), mm(0.32), mm(0.45)), pos + Vector3(0, 0, mm(1.5)), Parts.alum(), "shell")
	Parts.box(parent, Vector3(mm(0.32), mm(2.3), mm(0.45)), pos + Vector3(0, 0, mm(1.5)), Parts.alum(), "shell")
	# Основание разъёма XZ, малая высота вдоль входа (Y); подсветка чуть больше.
	Parts.box(
		parent,
		Vector3(mm(5.5), mm(2.6), mm(5.0)),
		pos + Vector3(0, y_sign * mm(3.8), -mm(2.2)),
		mat_well(),
		"internal"
	)


## Клемма Finder 94.04: круглый колодец винта на лице (+Z) + зев провода на ±Y.
## pos — центр колодца на лицевой плоскости ступени (винт смотрит на дверцу).
## wire_from_up=true → зев на +Y (верхние COM/NO/NC); false → на −Y (A1/A2).
static func finder_term_well(parent: Node3D, pos: Vector3, wire_from_up: bool = true) -> void:
	var y_sign: float = 1.0 if wire_from_up else -1.0
	# Круглая лунка-впадина на лице (+Z), не бугор.
	Parts.cyl(parent, mm(2.9), mm(5.0), pos + Vector3(0, 0, -mm(1.0)), "z", mat_well(), 14, "internal")
	# Головка винта внутри лунки, ось +Z (отвёртка с дверцы).
	Parts.cyl(parent, mm(1.55), mm(2.4), pos + Vector3(0, 0, mm(0.2)), "z", Parts.alum(), 10, "shell")
	Parts.box(parent, Vector3(mm(2.3), mm(0.32), mm(0.45)), pos + Vector3(0, 0, mm(1.5)), Parts.alum(), "shell")
	Parts.box(parent, Vector3(mm(0.32), mm(2.3), mm(0.45)), pos + Vector3(0, 0, mm(1.5)), Parts.alum(), "shell")
	# Прямоугольный зев провода на торце ступени (±Y) — впадина внутрь тела.
	Parts.box(
		parent,
		Vector3(mm(4.2), mm(3.2), mm(4.0)),
		pos + Vector3(0, y_sign * mm(4.0), -mm(2.5)),
		mat_well(),
		"internal"
	)
