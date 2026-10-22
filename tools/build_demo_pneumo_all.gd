extends Node
## Одноразово: собрать test/demo_pneumo_all.mechsim.json со всеми пневмоэлементами.

const CircuitScript = preload("res://scripts/domain/circuit.gd")
const TubeFit = preload("res://scripts/domain/tube_fitting_catalog.gd")

const OUT_PATH := "res://test/demo_pneumo_all.mechsim.json"
const OD := 6.0


func _ready() -> void:
	var err: String = _build_and_save()
	if err != "":
		push_error(err)
		print("[demo_pneumo_all] FAIL: ", err)
	else:
		print("[demo_pneumo_all] OK -> ", OUT_PATH)
	await get_tree().process_frame
	get_tree().quit()


func _build_and_save() -> String:
	var c = CircuitScript.new()
	var ids: Dictionary = {}

	# ——— Ряд 1: подготовка воздуха ———
	ids["km1"] = _add(c, "source", Vector2(40, 40), Vector3(0.0, 1.35, 0.55))
	c.get_element(ids["km1"]).pressure_bar = 8.0
	ids["frl"] = _add(c, "accessory@frl", Vector2(160, 40), Vector3(0.32, 1.35, 0.55))
	c.get_element(ids["frl"]).set_pressure_bar = 6.0
	ids["tee1"] = _add(c, "junction@tee", Vector2(280, 40), Vector3(0.55, 1.35, 0.55))
	ids["kr"] = _add(c, "accessory@regulator", Vector2(400, 40), Vector3(0.82, 1.35, 0.55))
	c.get_element(ids["kr"]).set_pressure_bar = 4.0
	ids["tee2"] = _add(c, "junction@tee", Vector2(520, 40), Vector3(1.08, 1.35, 0.55))

	# ——— Ряд 2: расход / обратные / ресивер / фитинги ———
	ids["check"] = _add(c, "accessory@check", Vector2(640, 40), Vector3(1.35, 1.35, 0.55))
	ids["thr"] = _add(c, "accessory@throttle", Vector2(760, 40), Vector3(1.62, 1.35, 0.55))
	c.get_element(ids["thr"]).opening = 0.55
	ids["thr_fix"] = _add(c, "accessory@throttle_fixed", Vector2(520, 140), Vector3(1.08, 1.35, 0.28))
	c.get_element(ids["thr_fix"]).opening = 0.4
	ids["thr_ck"] = _add(c, "accessory@throttle_check", Vector2(400, 140), Vector3(0.82, 1.35, 0.28))
	c.get_element(ids["thr_ck"]).opening = 0.5
	ids["res"] = _add(c, "accessory@reservoir", Vector2(280, 140), Vector3(0.55, 1.35, 0.28))
	ids["wye"] = _add(c, "junction@wye", Vector2(160, 140), Vector3(0.28, 1.35, 0.28))
	ids["manif"] = _add(c, "junction@manifold", Vector2(40, 140), Vector3(0.0, 1.35, 0.28))

	# ——— Ряд 3: Ц двусторонний + 5/2 кнопка ———
	ids["km2"] = _add(c, "source", Vector2(40, 260), Vector3(0.0, 1.35, -0.05))
	c.get_element(ids["km2"]).pressure_bar = 6.0
	ids["v52"] = _add(c, "valve@5_2_button_spring", Vector2(200, 260), Vector3(0.45, 1.35, -0.05))
	ids["cyl_da"] = _add(c, "cylinder@da_basic", Vector2(420, 240), Vector3(0.95, 1.35, -0.05))

	# ——— Ряд 4: Ц односторонний + 3/2 кнопка ———
	ids["km3"] = _add(c, "source", Vector2(40, 380), Vector3(0.0, 1.35, -0.45))
	c.get_element(ids["km3"]).pressure_bar = 6.0
	ids["v32"] = _add(c, "valve@3_2_nc_button_spring", Vector2(200, 380), Vector3(0.45, 1.35, -0.45))
	ids["cyl_sa"] = _add(c, "cylinder@sa_return", Vector2(400, 380), Vector3(0.9, 1.35, -0.45))

	# ——— Галерея остальных распределителей ———
	var valve_gallery: PackedStringArray = PackedStringArray([
		"2_2_nc_sol_spring", "2_2_no_sol_spring",
		"3_2_nc_sol_spring", "3_2_no_sol_spring",
		"3_2_nc_roller_spring", "3_2_nc_pilot_spring",
		"4_2_sol_spring", "5_2_sol_spring", "5_2_dual_sol",
		"5_3_closed_dual_sol", "5_3_exhausted_dual_sol",
		"5_3_pressurized_dual_sol", "5_3_floating_dual_sol",
	])
	for i in valve_gallery.size():
		var rid: String = valve_gallery[i]
		var col: int = i % 7
		var row: int = i / 7
		ids["vg_%s" % rid] = _add(
			c,
			"valve@%s" % rid,
			Vector2(40.0 + float(col) * 120.0, 500.0 + float(row) * 90.0),
			Vector3(float(col) * 0.38, 1.35, -0.85 - float(row) * 0.32)
		)

	# ——— Галерея остальных цилиндров ———
	var cyl_gallery: PackedStringArray = PackedStringArray([
		"da_magnetic", "da_ppv", "da_pps", "sa_extend",
		"thr_basic", "thr_magnetic",
		"rodless_slot", "rodless_magnetic", "rodless_ysr",
		"brake_nc", "brake_end",
	])
	for j in cyl_gallery.size():
		var crid: String = cyl_gallery[j]
		var ccol: int = j % 6
		var crow: int = j / 6
		ids["cg_%s" % crid] = _add(
			c,
			"cylinder@%s" % crid,
			Vector2(40.0 + float(ccol) * 140.0, 720.0 + float(crow) * 100.0),
			Vector3(1.6 + float(ccol) * 0.42, 1.35, 0.4 - float(crow) * 0.35)
		)

	ids["rail"] = _add(c, "rail@pneumatic", Vector2(700, 260), Vector3(1.5, 1.35, -0.2))

	# Единый Ø6 на всех рабочих элементах — иначе add_wire откажет.
	for el in c.elements:
		_force_od6(el)

	ids["km4"] = _add(c, "source", Vector2(640, 260), Vector3(1.35, 1.35, -0.05))
	c.get_element(ids["km4"]).pressure_bar = 6.0
	_force_od6(c.get_element(ids["km4"]))
	_force_od6(c.get_element(ids["vg_5_2_sol_spring"]))
	_force_od6(c.get_element(ids["manif"]))

	var links: Array = [
		[ids["km1"], "out", ids["frl"], "1"],
		[ids["frl"], "2", ids["tee1"], "1"],
		[ids["tee1"], "2", ids["kr"], "1"],
		[ids["tee1"], "3", ids["wye"], "1"],
		[ids["kr"], "2", ids["tee2"], "1"],
		[ids["tee2"], "2", ids["check"], "1"],
		[ids["check"], "2", ids["thr"], "1"],
		[ids["tee2"], "3", ids["thr_fix"], "1"],
		[ids["wye"], "2", ids["res"], "1"],
		[ids["wye"], "3", ids["thr_ck"], "1"],
		[ids["km2"], "out", ids["v52"], "1"],
		[ids["v52"], "2", ids["cyl_da"], "cap"],
		[ids["v52"], "4", ids["cyl_da"], "rod"],
		[ids["km3"], "out", ids["v32"], "1"],
		[ids["v32"], "2", ids["cyl_sa"], "cap"],
		[ids["km4"], "out", ids["manif"], "1"],
		[ids["manif"], "2", ids["vg_5_2_sol_spring"], "1"],
	]
	for link in links:
		var a_id: int = int(link[0])
		var a_port: String = str(link[1])
		var b_id: int = int(link[2])
		var b_port: String = str(link[3])
		if not c.add_wire(a_id, a_port, b_id, b_port):
			var ae = c.get_element(a_id)
			var be = c.get_element(b_id)
			return "Провод %s(%s).%s → %s(%s).%s не создан (OD a=%.1f b=%.1f)" % [
				str(ae.tag) if ae else "?", str(a_id), a_port,
				str(be.tag) if be else "?", str(b_id), b_port,
				float(ae.tube_od_mm) if ae else -1.0,
				float(be.tube_od_mm) if be else -1.0,
			]

	var data: Dictionary = c.to_scene_dict({
		"title": "Демо: все пневмоэлементы",
		"note": "Галерея + рабочие контуры (трубки Ø6).\n• КМ1(8бар)→FRL→T→КР(4бар)→T→КО→ДР; Y→ресивер и ДР с ОК; свободные порты = атм.\n• КМ2→5/2 кнопка→Ц двусторонний; КМ3→3/2 кнопка→Ц односторонний.\n• КМ4→коллектор→5/2 ЭМ (галерея).\n• Ниже — остальные распреды и цилиндры. Пуск · Рентген · Давление.",
		"cabinet_door_open": true,
		"schematic": {"zoom": 0.72, "pan": [10, 0]},
	})
	var text: String = JSON.stringify(data, "\t")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		return "Не удалось записать %s" % OUT_PATH
	f.store_string(text)
	f.close()
	return ""


func _add(c, kind: String, sch: Vector2, world: Vector3) -> int:
	var el = c.add_element(kind, sch)
	el.world_pos = world
	el.auto_ground = false
	if el.world_pos.y < 1.0:
		el.world_pos.y = 1.35
	_force_od6(el)
	return int(el.id)


func _force_od6(el) -> void:
	if el == null:
		return
	var k: String = str(el.kind)
	if k == "rail" or k == "electro" or k == "source":
		return
	if k in ["accessory", "junction"]:
		TubeFit.apply_armature_od(el, OD)
		return
	if k == "valve":
		el.tube_od_mm = OD
		el.port_name = TubeFit.thread_for_tube_od(OD)
		el.fitting_id = ""
		return
	if k == "cylinder":
		var picked: String = ""
		for item in TubeFit.fittings_for_bore(float(el.bore_mm)):
			if absf(float(item.get("tube_od_mm", 0.0)) - OD) < 0.15:
				picked = str(item.get("id", ""))
				break
		if picked != "":
			TubeFit.apply_fitting(el, picked)
		else:
			el.tube_od_mm = OD
			el.port_name = TubeFit.thread_for_tube_od(OD)
