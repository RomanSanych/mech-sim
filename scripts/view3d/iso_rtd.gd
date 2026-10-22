class_name IsoRtd
extends RefCounted
## 3D зонд ТС (Pt100): гильза + штуцер + клеммная головка (референс «голова + gland вниз»).
## Без head-mount TX — дисплей на вторичке в щите. Кабель из gland головки вниз.


const Parts = preload("res://scripts/view3d/pneumo_parts.gd")
const Rtd = preload("res://scripts/domain/rtd_nsx.gd")


static func build(parent: Node3D, el) -> Dictionary:
	var info := {"ports": {}, "dirs": {}}
	var od_mm: float = maxf(float(el.body_od_mm), 6.0)
	var len_mm: float = maxf(float(el.stroke_mm), 100.0)
	var sheath_r: float = Parts.mm(od_mm * 0.5)
	# Ось зонда = +X (горизонтально, как на референсе); среда / наконечник в −X.
	var immerse_l: float = Parts.mm(len_mm * 0.42)
	var neck_l: float = Parts.mm(len_mm * 0.28)
	var steel := Parts.mat("rtd_steel", Color(0.78, 0.80, 0.82), 0.88, 0.28)
	var steel2 := Parts.mat("rtd_steel2", Color(0.62, 0.64, 0.66), 0.85, 0.32)
	var tip_m := Parts.mat("rtd_tip", Color(0.55, 0.57, 0.6), 0.8, 0.35)
	var head_m := Parts.mat("rtd_head", Color(0.08, 0.08, 0.1), 0.06, 0.72)
	var head_cap := Parts.mat("rtd_cap", Color(0.12, 0.12, 0.14), 0.08, 0.65)
	var cable_mat := Parts.mat("rtd_cable", Color(0.08, 0.08, 0.1), 0.02, 0.7)
	var gland_m := Parts.mat("rtd_gland", Color(0.18, 0.18, 0.2), 0.2, 0.55)

	# Погружная часть (влево, −X).
	Parts.cyl(
		parent, sheath_r, immerse_l,
		Vector3(-immerse_l * 0.5 - Parts.mm(2.0), 0.0, 0.0), "x", steel, 16, "shell"
	)
	Parts.cyl(
		parent, sheath_r * 0.78, Parts.mm(6.0),
		Vector3(-immerse_l - Parts.mm(4.0), 0.0, 0.0), "x", tip_m, 12, "shell"
	)
	# Процессное присоединение: шестигранная гайка + резьбовой хвостовик.
	var hex_x: float = 0.0
	var hex_af: float = Parts.mm(maxf(od_mm * 2.2, 16.0))
	var hex_h: float = Parts.mm(7.0)
	Parts._hex(parent, hex_af, hex_h, Vector3(hex_x, 0.0, 0.0), "x", steel2)
	Parts.cyl(
		parent, sheath_r * 1.15, Parts.mm(10.0),
		Vector3(hex_x - hex_h * 0.5 - Parts.mm(5.0), 0.0, 0.0), "x", tip_m, 14, "shell"
	)
	# Шейка к головке (+X).
	Parts.cyl(
		parent, sheath_r, neck_l,
		Vector3(hex_x + hex_h * 0.5 + neck_l * 0.5, 0.0, 0.0), "x", steel, 16, "shell"
	)
	parent.set_meta("detect_material", "steel")

	# Клеммная головка: ниже ×3, шире ×2 относительно прежней «башни».
	var head_x: float = hex_x + hex_h * 0.5 + neck_l + Parts.mm(2.0)
	var head_r: float = Parts.mm(maxf(od_mm * 2.2, 20.0)) # было ×0.5 → диаметр ×2
	var head_h: float = Parts.mm(32.0) / 3.0
	var head_y: float = head_h * 0.15
	Parts.cyl(parent, head_r, head_h, Vector3(head_x, head_y, 0.0), "y", head_m, 24, "shell")
	# Винтовая крышка сверху (рифление).
	var cap_h: float = Parts.mm(4.0)
	var cap_y: float = head_y + head_h * 0.5 + cap_h * 0.45
	Parts.cyl(parent, head_r * 0.94, cap_h, Vector3(head_x, cap_y, 0.0), "y", head_cap, 20, "shell")
	for i in 8:
		var ang: float = float(i) * TAU / 8.0
		var rx: float = head_r * 0.90
		Parts.box(
			parent,
			Vector3(Parts.mm(2.2), Parts.mm(3.2), Parts.mm(2.8)),
			Vector3(head_x + cos(ang) * rx, cap_y, sin(ang) * rx),
			head_cap,
			"shell"
		)
	# Боковой штуцер головки на шейку.
	Parts.cyl(
		parent, sheath_r * 1.05, Parts.mm(10.0),
		Vector3(head_x - head_r * 0.55, head_y, 0.0), "x", steel2, 12, "shell"
	)

	# Кабельный gland вниз (−Y) — как на референсе.
	var gland_y0: float = head_y - head_h * 0.5
	Parts.cyl(
		parent, Parts.mm(5.2), Parts.mm(7.0),
		Vector3(head_x, gland_y0 - Parts.mm(3.0), 0.0), "y", gland_m, 12, "shell"
	)
	Parts.cyl(
		parent, Parts.mm(4.0), Parts.mm(5.0),
		Vector3(head_x, gland_y0 - Parts.mm(9.0), 0.0), "y", gland_m, 12, "shell"
	)
	var cable_r: float = Parts.mm(2.5)
	var cable_stub_l: float = Parts.mm(16.0)
	var cable_mid_y: float = gland_y0 - Parts.mm(12.0) - cable_stub_l * 0.45
	Parts.cyl(
		parent, cable_r, cable_stub_l,
		Vector3(head_x, cable_mid_y, 0.0), "y", cable_mat, 12, "shell"
	)
	var cable_tip := Vector3(head_x, gland_y0 - Parts.mm(12.0) - cable_stub_l * 0.95, 0.0)
	parent.set_meta("cable_exit_local", cable_tip)
	parent.set_meta("cable_exit_dir", Vector3.DOWN)

	var cores: PackedStringArray = Rtd.core_names(int(el.wire_scheme))
	for nm in cores:
		info["ports"][str(nm)] = cable_tip
		info["dirs"][str(nm)] = Vector3.DOWN

	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(el.tag)
	tag.font_size = 16
	tag.pixel_size = 0.00028
	tag.modulate = Color(0.9, 0.92, 0.94)
	tag.position = Vector3(head_x, cap_y + Parts.mm(8.0), 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	parent.add_child(tag)

	parent.set_meta("sensor_rtd", true)
	var span_x: float = immerse_l + neck_l + head_r * 2.0 + Parts.mm(40.0)
	parent.set_meta("seat_aabb", AABB(
		Vector3(-immerse_l - Parts.mm(12.0), cable_tip.y - Parts.mm(8.0), -head_r * 1.15),
		Vector3(span_x, head_h + Parts.mm(36.0), head_r * 2.3)
	))
	return info


## Раньше LED на головке; индикация — на вторичке в щите.
static func apply_led(_root: Node3D, _el) -> void:
	pass
